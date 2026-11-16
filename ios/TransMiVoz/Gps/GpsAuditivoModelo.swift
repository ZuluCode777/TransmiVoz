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
///   «Repetir indicación» y «Oriéntame por voz», y, MIENTRAS haya una estación elegida, un refresco automático cada 20 s
///   (el aviso de cercanía de la web se evalúa a cada lectura; aquí, a cada refresco). Todas con un intervalo mínimo entre una
///   y otra y una sola en curso (el servidor comparte 60 peticiones por minuto entre todos los teléfonos y todas las
///   operaciones). El refresco automático nunca reintenta tras un fallo de red;
/// - una lectura de más de 60 s está vencida: no se envía ni se presenta como actual;
/// - la posición, el rumbo y las estaciones viven solo en memoria y se borran al detener. No se guardan, no se registran,
///   no van en una URL y no se imprimen;
/// - el modelo es REUTILIZABLE: `suspender()` lo deja del todo en `.inactivo` (sin temporizadores ni elección) y un `iniciar()`
///   posterior empieza limpio. `EntornoApp` lo crea una sola vez y la raíz lo suspende al cambiar de pestaña o ir a segundo plano.
@MainActor
@Observable
final class GpsAuditivoModelo {
    /// Una lectura de más de 60 s está vencida (`EDAD_MAXIMA_POSICION_MS` del servidor): no se reutiliza ni se envía.
    static let edadMaximaPosicionMs: Milisegundos = 60_000
    /// Mínimo entre dos peticiones y vigencia de la última respuesta para repetirla sin pedir otra. Propuesta de software,
    /// sin medir: deja a un teléfono en 6 por minuto como mucho, con margen bajo el tope compartido de 60 por minuto.
    static let intervaloMinimoMs: Milisegundos = 10_000
    /// Cada cuánto se refresca sola la consulta MIENTRAS haya una estación elegida, contado desde la última petición (manual o
    /// automática): para que «Estás muy cerca» pueda salir sin tocar nada. Como mucho 3 por minuto por teléfono además de las
    /// manuales, y todas bajo el mínimo de arriba: 6 por minuto en total, 18 con tres teléfonos. Propuesta de software, sin medir.
    static let intervaloRefrescoMs: Milisegundos = 20_000
    /// Cuántas frases conserva «La app dijo». `shortcut:` tope fijo; una sesión larga con refrescos que hablan cada 20 s no la
    /// crece sin límite, y lo más viejo ya no se puede repetir. Subirlo si hace falta ver más historia.
    static let maximoTranscripcion = 30

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
        /// El refresco periódico de la estación elegida: solo habla si hay algo que decir (cercanía o estación que ya no está).
        case automatica
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
    /// Lo que se dijo al abrir la ruta a pie en Mapas (también queda en pantalla); `nil` si no se abrió.
    private(set) var mensajeMapas: String?
    /// «La app dijo» (`especificacion-accesibilidad.md` §5 y §9): TODO lo que esta pantalla dice por voz, con el mismo texto exacto,
    /// de la sesión actual y en orden. Se borra al detener, al suspender y al empezar otra sesión. La última es la que repite
    /// `repetirLoDicho`.
    private(set) var transcripcion: [String] = []
    /// Cómo salió la última frase: se dijo en voz alta, la voz de la app calló o suena otro aviso (y no se le corta). `nil` sin frases.
    private(set) var resultadoVoz: ResultadoLocucion?
    /// Cuántas veces se pidió «Repetir»: la pantalla lleva el foco de VoiceOver al resultado aunque el texto sea igual al anterior.
    private(set) var repeticiones = 0
    /// Precisión de la lectura vigente, solo para mostrarla.
    private(set) var precisionMetros: Double?
    /// Dónde está la persona, solo para el mapa. Se borra al detener o al vencer.
    private(set) var posicionEnMapa: Coordenada?

    @ObservationIgnored private let cliente: ClientePlanificador
    @ObservationIgnored private let proveedor: ProveedorUbicacion
    /// La voz compartida de la app: la de esta pantalla y la de «Metro de Bogotá».
    @ObservationIgnored let locutor: Locutor
    @ObservationIgnored private let abridor: AbridorMapas
    @ObservationIgnored private let reloj: RelojMonotonico
    @ObservationIgnored private let dormir: @Sendable (Milisegundos) async throws -> Void
    @ObservationIgnored private let ejecutor = EjecutorUnico()

    @ObservationIgnored private var posicion: PosicionMedida?
    @ObservationIgnored private var rumboMedido: RumboMedido?
    @ObservationIgnored private var vencimiento: Task<Void, Never>?
    /// El refresco automático de la estación elegida; `nil` si no hay ninguno programado.
    @ObservationIgnored private var refresco: Task<Void, Never>?
    @ObservationIgnored private var ultimaPeticionMs: Milisegundos?
    @ObservationIgnored private var accionEnCurso: Accion = .primera
    /// Si la lectura de la última consulta llevaba rumbo: una respuesta sin él no se repite cuando ya hay brújula.
    @ObservationIgnored private var consultaLlevabaRumbo = false
    /// Falta la consulta automática de la primera lectura (de la sesión, o tras renovarse una lectura vencida).
    @ObservationIgnored private var consultaInicialPendiente = true
    /// La cercanía de la estación elegida ya se dijo: una sola vez por estación elegida.
    @ObservationIgnored private var cercaniaDicha = false
    /// La última frase fue una orientación del servidor (primera, actualizada, orientada, cercanía): depende de una lectura que puede
    /// vencer. Las demás (activación, permiso, Mapas, aviso de vencida) valen siempre.
    @ObservationIgnored private var ultimaEsOrientacion = false

    init(
        cliente: ClientePlanificador, proveedor: ProveedorUbicacion, locutor: Locutor,
        abridor: AbridorMapas = AbridorMapasSistema(),
        reloj: @escaping RelojMonotonico = RelojDelSistema.ahora,
        dormir: @escaping @Sendable (Milisegundos) async throws -> Void = { ms in
            try await Task.sleep(nanoseconds: UInt64(max(ms, 1)) * 1_000_000)
        }
    ) {
        self.cliente = cliente
        self.proveedor = proveedor
        self.locutor = locutor
        self.abridor = abridor
        self.reloj = reloj
        self.dormir = dormir
        rumbo = proveedor.rumboDisponible ? .sinLectura : .noDisponible
    }

    /// La persona eligió una estación y sigue en la respuesta.
    var estacionElegida: EstacionCercana? {
        guard let objetivo else { return nil }
        return respuesta?.estaciones.first { $0.nombre == objetivo }
    }

    /// Hay un refresco automático programado (solo con ubicación vigente, estación elegida y sin fallo).
    var refrescoProgramado: Bool { refresco != nil }

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
            decir(TextoGps.yaActiva)
            return
        case .vencida:
            detener()
        case .inactivo, .permisoDenegado, .permisoRestringido, .noDisponible:
            break
        }
        limpiarTranscripcion() // una sesión nueva no arrastra lo dicho en la anterior (un permiso negado no pasa por `detener`)
        estado = .pidiendoPermiso
        aviso = nil
        proveedor.alEvento = { [weak self] evento in self?.recibir(evento) }
        decir(TextoGps.activando)
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
        cancelarRefresco()
        locutor.cortarLoPropio()
        limpiarTranscripcion()
        posicion = nil
        rumboMedido = nil
        posicionEnMapa = nil
        precisionMetros = nil
        ultimaPeticionMs = nil
        accionEnCurso = .primera
        consultaLlevabaRumbo = false
        consultaInicialPendiente = true
        cercaniaDicha = false
        if habiaSesion {
            limpiarConsulta()
            objetivo = nil
            aviso = nil
            mensajeMapas = nil
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
        cancelarRefresco()
        posicion = nil
        rumboMedido = nil
        posicionEnMapa = nil
        precisionMetros = nil
        limpiarConsulta()
        objetivo = nil
        mensajeMapas = nil
        estado = nuevo
        aviso = texto
        decir(texto)
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
        cancelarRefresco()
        posicion = nil
        posicionEnMapa = nil
        precisionMetros = nil
        limpiarConsulta()
        estado = .vencida
        aviso = TextoGps.ubicacionVencida
        decir(TextoGps.ubicacionVencida)
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
        programarRefresco()
    }

    /// «Abrir en Mapas»: la ruta a pie hacia la estación en la app Mapas del sistema (como «Abrir en Google Maps» de la web). Solo
    /// recibe la estación: nombre y coordenada del catálogo. La posición de la persona no sale de aquí: va al destino y a nadie más.
    func abrirEnMapas(_ nombre: String) {
        guard estado == .activo, let estacion = respuesta?.estaciones.first(where: { $0.nombre == nombre }) else { return }
        abridor.abrirRutaAPie(haciaEstacion: estacion.nombre, en: estacion.coordenada)
        let texto = TextoGps.abriMapas(estacion.nombre)
        mensajeMapas = texto
        decir(texto)
    }

    // MARK: Refresco automático de la estación elegida

    private func cancelarRefresco() {
        refresco?.cancel()
        refresco = nil
    }

    /// Mientras haya una estación elegida, ubicación vigente y ningún fallo, pide la consulta de nuevo cada 20 s desde la última
    /// petición. Ningún evento del sensor pasa por aquí: solo este temporizador, que se cancela al detener, vencer la lectura,
    /// soltar la estación o fallar una consulta (un fallo no se reintenta solo).
    private func programarRefresco() {
        cancelarRefresco()
        guard estado == .activo, objetivo != nil, fallo == nil else { return }
        refresco = Task { [weak self, dormir] in
            while !Task.isCancelled {
                guard let restante = self?.msHastaRefresco() else { return }
                if restante <= 0 {
                    self?.refrescarSola()
                    return
                }
                do { try await dormir(restante) } catch { return }
            }
        }
    }

    private func msHastaRefresco() -> Milisegundos? {
        guard estado == .activo, objetivo != nil, fallo == nil, let ultima = ultimaPeticionMs else { return nil }
        return ultima + Self.intervaloRefrescoMs - reloj()
    }

    private func refrescarSola() {
        refresco = nil
        // Con otra petición en curso no se encola nada: al terminar bien, `aplicar` retoma el ciclo.
        guard estado == .activo, objetivo != nil, fallo == nil, !consultando else { return }
        pedir(.automatica)
    }

    /// Una respuesta reciente se vuelve a decir sin pedir otra; si no, se consulta. «Actualizar» siempre consulta.
    private func pedir(_ accion: Accion) {
        guard estado == .activo else {
            if estado == .vencida { aviso = TextoGps.ubicacionVencida; decir(TextoGps.ubicacionVencida) }
            return
        }
        if consultando {
            // Una sola petición vigente: la persona cambió de idea, la respuesta que llega dirá lo último que pidió.
            if accion != .primera { accionEnCurso = accion }
            return
        }
        let enEspera = ultimaPeticionMs.map { reloj() - $0 < Self.intervaloMinimoMs } ?? false
        if enEspera {
            // La primera consulta y el refresco bloqueados no avisan: la próxima lectura o el próximo ciclo lo reintentan.
            guard accion != .primera, accion != .automatica else { return }
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
                cancelarRefresco() // un fallo no se reintenta solo: lo reanuda la persona con «Reintentar»
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
        programarRefresco()
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

    // MARK: «La app dijo»

    /// «Repetir» de «La app dijo»: vuelve a decir EXACTAMENTE la última frase, sin consulta ni red. No toca la cercanía ya dicha, la
    /// estación elegida ni el refresco, y la voz sigue sus reglas (ruta privada, voz permitida) sin cortar jamás una locución ajena:
    /// si no suena, `resultadoVoz` lo explica y el texto sigue en pantalla. Una orientación que dependía de una lectura que ya
    /// venció no se repite: se dice el aviso de ubicación vencida en su lugar.
    func repetirLoDicho() {
        guard let frase = transcripcion.last else { return }
        repeticiones += 1
        if ultimaEsOrientacion, estado == .activo, (msHastaVencer() ?? -1) < 0 {
            vencer() // el temporizador aún no llegó: lo comprueba el propio «Repetir»
            return
        }
        resultadoVoz = locutor.decir(frase)
    }

    /// Cuánto hace que se capturó la lectura vigente, para mostrarlo junto a la precisión. Sale del reloj monotónico (el mismo del
    /// vencimiento): nunca es negativa y no existe sin lectura vigente (tras detener o vencer). Solo lee: no pide red ni toca el sensor.
    func edadLecturaMs() -> Milisegundos? {
        guard let posicion else { return nil }
        let edad = max(0, reloj() - posicion.capturadaMs)
        return edad <= Self.edadMaximaPosicionMs ? edad : nil
    }

    /// El ÚNICO camino de la voz de esta pantalla: dice la frase por el locutor compartido y anota en «La app dijo» el texto exacto y
    /// cómo salió. Así nada se dice sin quedar en texto, aunque no se haya oído (otro aviso sonando, voz apagada).
    @discardableResult
    private func decir(_ texto: String, orientacion: Bool = false) -> ResultadoLocucion {
        let resultado = locutor.decir(texto)
        transcripcion.append(texto)
        if transcripcion.count > Self.maximoTranscripcion {
            transcripcion.removeFirst(transcripcion.count - Self.maximoTranscripcion)
        }
        resultadoVoz = resultado
        ultimaEsOrientacion = orientacion
        return resultado
    }

    private func limpiarTranscripcion() {
        transcripcion = []
        resultadoVoz = nil
        ultimaEsOrientacion = false
    }

    // MARK: Voz

    /// Dice lo que el servidor devolvió. Una sola frase por vez (la voz es de cola de uno): la orientación y, si el servidor
    /// marca `muyCerca` en la estación elegida y todavía no se dijo, el aviso de cercanía. Si suena otra cosa (un aviso del
    /// accesorio) la frase no se dice y queda en pantalla; la cercanía solo se da por dicha si llegó a la persona, así que el
    /// próximo refresco la vuelve a intentar.
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
            } else {
                soltarEstacionQueYaNoEsta(&frases)
            }
        case .automatica:
            if elegida == nil { soltarEstacionQueYaNoEsta(&frases) }
        }
        var diceLaCercania = false
        if let elegida, elegida.muyCerca, !cercaniaDicha {
            diceLaCercania = true
            frases.append(TextoGps.muyCerca(elegida))
        }
        guard !frases.isEmpty else { return }
        let resultado = decir(frases.joined(separator: " "), orientacion: true)
        if diceLaCercania && resultado.seDijo { cercaniaDicha = true }
        if resultado == .ocupada && accion != .automatica { aviso = TextoGps.vozOcupada }
    }

    /// La estación elegida ya no está entre las más cercanas: se suelta (y con ella el refresco) y se dice.
    private func soltarEstacionQueYaNoEsta(_ frases: inout [String]) {
        guard let nombre = objetivo else { return }
        objetivo = nil
        frases.append(TextoGps.fueraDeLasMasCercanas(nombre))
    }
}
