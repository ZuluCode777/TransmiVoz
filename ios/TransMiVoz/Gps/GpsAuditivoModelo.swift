import ContratoBLE
import Foundation
import Observation

/// Estado de la pantalla «Mapa y GPS» (web: `components/auditory-gps.tsx`): la ubicación y la brújula del iPhone, y las
/// estaciones más cercanas que el SERVIDOR ordena, mide y orienta (`estaciones-cercanas`). Aquí no hay reglas de
/// transporte: ni ranking, ni distancia, ni giro, ni umbral de cercanía. El modelo solo
/// - arma la lectura con lo que el sistema midió y se la manda al servidor,
/// - dice lo que el servidor devuelve (por la voz de la app) y avisa de la cercanía solo con su `muyCerca`.
///
/// Ciclo de vida (la persona manda):
/// - la ubicación solo se escucha tras `iniciar()` y se suelta con `detener()`; al salir de la pantalla, bloquear el
///   iPhone o pasar a segundo plano se detiene sola (`suspender()`) y NO se reanuda sola: la persona la vuelve a pedir;
/// - ningún evento del sensor dispara una petición. Hay petición solo con la primera lectura, «Actualizar estaciones»,
///   «Repetir indicación» y «Oriéntame por voz», todas con un intervalo mínimo entre una y otra (el servidor comparte
///   60 peticiones por minuto entre todos los teléfonos y todas las operaciones). Solo hay una en curso: pedir otra la reemplaza;
/// - una lectura de más de 60 s está vencida: no se envía ni se presenta como actual;
/// - la posición, el rumbo y las estaciones viven solo en memoria y se borran al detener. No se guardan, no se registran,
///   no van en una URL y no se imprimen.
@MainActor
@Observable
final class GpsAuditivoModelo {
    /// Una lectura de más de 60 s está vencida (`EDAD_MAXIMA_POSICION_MS` del servidor): no se reutiliza ni se envía.
    static let edadMaximaPosicionMs: Milisegundos = 60_000
    /// Mínimo entre dos peticiones y vigencia de la última respuesta para repetirla sin pedir otra. Propuesta de software,
    /// sin medir: deja a un teléfono en 6 por minuto como mucho, con margen bajo el tope compartido de 60 por minuto.
    static let intervaloMinimoMs: Milisegundos = 10_000

    enum Estado: Equatable {
        case inactivo
        /// Esperando la respuesta de la persona al aviso de permiso del sistema.
        case pidiendoPermiso
        case permisoDenegado
        case permisoRestringido
        /// La app no puede pedir la ubicación (falta la descripción de uso en la configuración del proyecto).
        case noDisponible
        /// Con permiso, sin lectura vigente todavía.
        case buscando
        case activo
        /// La última lectura pasó de 60 s y no hay una nueva. La escucha sigue: una lectura nueva la renueva.
        case vencida
    }

    /// Lo que se sabe de la brújula, para decirlo. Qué orientación da el servidor con ella lo dice su `modo`.
    enum EstadoRumbo: Equatable {
        case noDisponible
        case sinLectura
        case conLectura
    }

    /// Por qué se consulta: decide qué se dice con la respuesta.
    enum Accion: Equatable {
        case primera, actualizar, repetir, orientar
    }

    private(set) var estado: Estado = .inactivo
    /// Las estaciones de la última consulta buena. Se borra al vencer la lectura, al fallar una consulta y al detener.
    private(set) var respuesta: RespuestaEstacionesCercanas?
    /// Hay una petición en curso (la lista anterior sigue a la vista hasta que llegue la nueva).
    private(set) var consultando = false
    /// Por qué falló la última consulta; `nil` si no falló.
    private(set) var fallo: ErrorConsulta?
    /// Nombre de la estación que la persona eligió con «Oriéntame por voz».
    private(set) var objetivo: String?
    /// Resultado de la última acción en texto (espera, ubicación vencida, permiso…), para la pantalla.
    private(set) var aviso: String?
    private(set) var rumbo: EstadoRumbo = .sinLectura
    /// Precisión de la lectura vigente, solo para mostrarla.
    private(set) var precisionMetros: Double?
    /// Dónde está la persona, solo para el mapa. Se borra al detener o al vencer.
    private(set) var posicionEnMapa: Coordenada?

    @ObservationIgnored private let cliente: ClientePlanificador
    @ObservationIgnored private let proveedor: ProveedorUbicacion
    @ObservationIgnored private let locutor: Locutor
    @ObservationIgnored private let reloj: RelojMonotonico
    @ObservationIgnored private let dormir: @Sendable (Milisegundos) async throws -> Void
    @ObservationIgnored private let ejecutor = EjecutorUnico()

    @ObservationIgnored private var posicion: PosicionMedida?
    @ObservationIgnored private var rumboMedido: RumboMedido?
    @ObservationIgnored private var vencimiento: Task<Void, Never>?
    @ObservationIgnored private var ultimaPeticionMs: Milisegundos?
    @ObservationIgnored private var accionEnCurso: Accion = .primera
    /// Si la lectura de la última consulta llevaba rumbo: una respuesta sin él no se repite cuando ya hay brújula.
    @ObservationIgnored private var consultaLlevabaRumbo = false
    /// Falta la consulta automática de la primera lectura (de la sesión, o tras renovarse una lectura vencida).
    @ObservationIgnored private var consultaInicialPendiente = true
    /// La cercanía de la estación elegida ya se dijo: una sola vez por estación elegida.
    @ObservationIgnored private var cercaniaDicha = false

    init(
        cliente: ClientePlanificador, proveedor: ProveedorUbicacion, locutor: Locutor,
        reloj: @escaping RelojMonotonico = RelojDelSistema.ahora,
        dormir: @escaping @Sendable (Milisegundos) async throws -> Void = { ms in
            try await Task.sleep(nanoseconds: UInt64(max(ms, 1)) * 1_000_000)
        }
    ) {
        self.cliente = cliente
        self.proveedor = proveedor
        self.locutor = locutor
        self.reloj = reloj
        self.dormir = dormir
        rumbo = proveedor.rumboDisponible ? .sinLectura : .noDisponible
    }

    /// La persona eligió una estación y sigue en la respuesta.
    var estacionElegida: EstacionCercana? {
        guard let objetivo else { return nil }
        return respuesta?.estaciones.first { $0.nombre == objetivo }
    }

    /// Hay ubicación pedida (con o sin lectura todavía): lo que se debe soltar al irse.
    var escuchando: Bool {
        switch estado {
        case .pidiendoPermiso, .buscando, .activo, .vencida: return true
        case .inactivo, .permisoDenegado, .permisoRestringido, .noDisponible: return false
        }
    }

    // MARK: Ciclo de vida

    /// «Activar mi ubicación»: pide el permiso si hace falta y empieza a escuchar.
    func iniciar() {
        switch estado {
        case .pidiendoPermiso, .buscando, .activo:
            locutor.decir(TextoGps.yaActiva)
            return
        case .vencida:
            detener()
        case .inactivo, .permisoDenegado, .permisoRestringido, .noDisponible:
            break
        }
        estado = .pidiendoPermiso
        aviso = nil
        proveedor.alEvento = { [weak self] evento in self?.recibir(evento) }
        locutor.decir(TextoGps.activando)
        proveedor.iniciar()
    }

    /// «Detener la ubicación». Suelta el sistema, descarta la petición en curso y la voz propia y borra todo lo medido.
    func detener() {
        let habiaSesion = estado != .inactivo
        proveedor.alEvento = nil
        proveedor.detener()
        ejecutor.invalidar()
        vencimiento?.cancel()
        vencimiento = nil
        locutor.cortarLoPropio()
        posicion = nil
        rumboMedido = nil
        posicionEnMapa = nil
        precisionMetros = nil
        ultimaPeticionMs = nil
        consultaInicialPendiente = true
        cercaniaDicha = false
        if habiaSesion {
            limpiarConsulta()
            objetivo = nil
            aviso = nil
            estado = .inactivo
            rumbo = proveedor.rumboDisponible ? .sinLectura : .noDisponible
        }
    }

    /// La pantalla dejó de verse, el iPhone se bloqueó o la app pasó a segundo plano: se suelta todo y no se reanuda sola.
    func suspender() {
        guard estado != .inactivo else { return }
        detener()
    }

    private func limpiarConsulta() {
        respuesta = nil
        consultando = false
        fallo = nil
    }

    // MARK: Eventos del sensor (solo actualizan estado; ninguno pide red)

    private func recibir(_ evento: EventoUbicacion) {
        guard estado != .inactivo else { return }
        switch evento {
        case .permiso(let permiso): aplicar(permiso)
        case .posicion(let medida): aplicar(medida)
        case .rumbo(let medido): aplicar(medido)
        case .sinSenal:
            if estado == .buscando { aviso = TextoGps.sinSenal }
        }
    }

    private func aplicar(_ permiso: PermisoUbicacion) {
        switch permiso {
        case .porPreguntar:
            estado = .pidiendoPermiso
        case .concedido:
            if estado == .pidiendoPermiso { estado = .buscando; aviso = TextoGps.buscando }
        case .denegado:
            sinPermiso(.permisoDenegado, TextoGps.permisoDenegado)
        case .restringido:
            sinPermiso(.permisoRestringido, TextoGps.permisoRestringido)
        case .noDisponible:
            sinPermiso(.noDisponible, TextoGps.noDisponible)
        }
    }

    /// Sin permiso no hay nada que escuchar ni que mostrar: se suelta el sistema y se explica cómo seguir.
    private func sinPermiso(_ nuevo: Estado, _ texto: String) {
        proveedor.alEvento = nil
        proveedor.detener()
        ejecutor.invalidar()
        vencimiento?.cancel()
        vencimiento = nil
        posicion = nil
        rumboMedido = nil
        posicionEnMapa = nil
        precisionMetros = nil
        limpiarConsulta()
        objetivo = nil
        estado = nuevo
        aviso = texto
        locutor.decir(texto)
    }

    private func aplicar(_ medida: PosicionMedida) {
        // Un sistema que entrega primero una lectura guardada y vieja no la convierte en la ubicación de ahora.
        guard reloj() - medida.capturadaMs <= Self.edadMaximaPosicionMs else { return }
        let renovada = estado == .vencida
        posicion = medida
        let punto = Coordenada(latitud: medida.latitud, longitud: medida.longitud)
        if posicionEnMapa != punto { posicionEnMapa = punto }
        if precisionMetros != medida.precision { precisionMetros = medida.precision }
        estado = .activo
        if renovada { consultaInicialPendiente = true }
        if aviso == TextoGps.buscando || aviso == TextoGps.sinSenal || renovada { aviso = nil }
        programarVencimiento()
        if consultaInicialPendiente { pedir(.primera) }
    }

    private func aplicar(_ medido: RumboMedido?) {
        rumboMedido = medido
        let nuevo: EstadoRumbo = !proveedor.rumboDisponible ? .noDisponible : (medido == nil ? .sinLectura : .conLectura)
        if nuevo != rumbo { rumbo = nuevo }
    }

    // MARK: Vencimiento

    private func msHastaVencer() -> Milisegundos? {
        posicion.map { Self.edadMaximaPosicionMs - (reloj() - $0.capturadaMs) }
    }

    /// `watchPosition` no garantiza otra lectura antes de que venza la actual: un temporizador la vence a los 60 s.
    private func programarVencimiento() {
        vencimiento?.cancel()
        vencimiento = Task { [weak self, dormir] in
            while !Task.isCancelled {
                guard let restante = self?.msHastaVencer() else { return }
                if restante < 0 {
                    self?.vencer()
                    return
                }
                do { try await dormir(restante + 1) } catch { return }
            }
        }
    }

    /// La lectura pasó de 60 s: no se presenta como actual ni se reutiliza. La escucha sigue por si llega una nueva.
    private func vencer() {
        guard estado == .activo else { return }
        ejecutor.invalidar()
        vencimiento = nil
        posicion = nil
        posicionEnMapa = nil
        precisionMetros = nil
        limpiarConsulta()
        estado = .vencida
        aviso = TextoGps.ubicacionVencida
        locutor.decir(TextoGps.ubicacionVencida)
    }

    // MARK: Acciones de la persona

    func actualizar() { pedir(.actualizar) }
    func repetirIndicacion() { pedir(.repetir) }

    /// «Oriéntame por voz»: elige la estación (una sola vez se avisará de su cercanía) y la orienta con una lectura de ahora.
    func orientarHacia(_ nombre: String) {
        guard estado == .activo, respuesta?.estaciones.contains(where: { $0.nombre == nombre }) == true else { return }
        if objetivo != nombre { cercaniaDicha = false }
        objetivo = nombre
        pedir(.orientar)
    }

    /// Una respuesta reciente se vuelve a decir sin pedir otra; si no, se consulta. «Actualizar» siempre consulta.
    private func pedir(_ accion: Accion) {
        guard estado == .activo else {
            if estado == .vencida { aviso = TextoGps.ubicacionVencida; locutor.decir(TextoGps.ubicacionVencida) }
            return
        }
        if consultando {
            // Una sola petición vigente: la persona cambió de idea, la respuesta que llega dirá lo último que pidió.
            if accion != .primera { accionEnCurso = accion }
            return
        }
        let enEspera = ultimaPeticionMs.map { reloj() - $0 < Self.intervaloMinimoMs } ?? false
        if enEspera {
            // La primera consulta bloqueada no avisa: la próxima lectura la reintenta cuando pase el intervalo.
            guard accion != .primera else { return }
            if accion != .actualizar, let respuesta, consultaLlevabaRumbo == (rumboMedido != nil) {
                hablar(accion, con: respuesta)
            } else {
                aviso = TextoGps.esperaUnMomento
            }
            return
        }
        consultar(accion)
    }

    private func consultar(_ accion: Accion) {
        guard let lectura = lecturaParaEnviar() else {
            // Pasó de 60 s justo ahora: la lectura no se envía.
            vencer()
            return
        }
        accionEnCurso = accion
        consultaLlevabaRumbo = lectura.rumbo != nil
        consultaInicialPendiente = false
        ultimaPeticionMs = reloj()
        consultando = true
        fallo = nil
        aviso = nil
        ejecutor.ejecutar({ [cliente] in try await cliente.estacionesCercanas(lectura) }) { [self] resultado in
            consultando = false
            switch resultado {
            case .success(let respuesta): aplicar(respuesta)
            case .failure(let error):
                self.respuesta = nil
                fallo = error
            }
        }
    }

    private func aplicar(_ respuesta: RespuestaEstacionesCercanas) {
        self.respuesta = respuesta
        // El servidor contó la lectura como vencida: no hay estaciones y no se presenta como actual.
        if respuesta.resultado == .ubicacionVencida {
            vencer()
            return
        }
        hablar(accionEnCurso, con: respuesta)
    }

    /// La lectura que viaja al servidor: lo que el sistema midió, sin reglas. Una lectura vencida no se envía; la precisión o la
    /// calidad que el sistema da como inválida (negativa) no viajan; el rumbo solo si es verdadero y válido.
    private func lecturaParaEnviar() -> LecturaParaEnviar? {
        guard let posicion else { return nil }
        let ahora = reloj()
        let edad = ahora - posicion.capturadaMs
        guard edad <= Self.edadMaximaPosicionMs else { return nil }
        let rumboEnviado = rumboMedido.flatMap { medido -> RumboParaEnviar? in
            let edadRumbo = ahora - medido.capturadoMs
            guard edadRumbo <= Milisegundos(EntradaPlanificador.maximaEdadLecturaMs) else { return nil }
            let calidad = medido.calidad.flatMap { $0 >= 0 ? $0 : nil }
            return RumboParaEnviar(grados: medido.gradosVerdaderos, calidad: calidad, edadMs: Int(max(0, edadRumbo)))
        }
        let precision = posicion.precision.flatMap { $0 >= 0 && $0 <= EntradaPlanificador.maximoPrecisionMetros ? $0 : nil }
        return LecturaParaEnviar(
            latitud: posicion.latitud, longitud: posicion.longitud, precision: precision, edadMs: Int(max(0, edad)), rumbo: rumboEnviado)
    }

    // MARK: Voz

    /// Dice lo que el servidor devolvió. Una sola frase por vez (la voz es de cola de uno): la orientación y, si el servidor
    /// marca `muyCerca` en la estación elegida y todavía no se dijo, el aviso de cercanía.
    private func hablar(_ accion: Accion, con respuesta: RespuestaEstacionesCercanas) {
        var frases: [String] = []
        let elegida = objetivo.flatMap { nombre in respuesta.estaciones.first { $0.nombre == nombre } }
        switch accion {
        case .primera:
            frases.append(respuesta.estaciones.first.map(TextoGps.ubicacionLista) ?? TextoGps.sinEstaciones)
        case .actualizar:
            frases.append(respuesta.estaciones.first.map(TextoGps.actualizada) ?? TextoGps.sinEstaciones)
        case .repetir:
            if let estacion = elegida ?? respuesta.estaciones.first { frases.append(estacion.orientacion.indicacion) }
        case .orientar:
            if let elegida {
                frases.append(TextoGps.orientandoHacia(elegida))
            } else if let nombre = objetivo {
                objetivo = nil
                frases.append(TextoGps.fueraDeLasMasCercanas(nombre))
            }
        }
        if let elegida, elegida.muyCerca, !cercaniaDicha {
            cercaniaDicha = true
            frases.append(TextoGps.muyCerca(elegida))
        }
        if !frases.isEmpty { locutor.decir(frases.joined(separator: " ")) }
    }
}
