import Foundation
import Observation

/// Pantalla a la que lleva una respuesta del asistente (web: `handleAgentAction` de `components/transmivoz-app.tsx`). Solo el dato
/// que la pantalla pide: la app no interpreta el transporte.
enum DestinoAgenteTotal: Hashable, Sendable {
    /// Búsqueda de rutas; con estación, ya buscada.
    case rutas(estacion: String?)
    case favoritas
    case gps
    case ruta(codigo: String)
    /// Planear un viaje entre dos lugares elegidos.
    case viaje
}

/// En qué está el asistente de voz.
enum FaseAgenteTotal: Equatable, Sendable {
    case reposo
    /// El dictado está en curso: pidiendo permisos, iniciando, escuchando o procesando lo dicho.
    case escuchando
    /// Hay una consulta al servidor en curso.
    case pensando
}

/// Textos de la pantalla de Ceguera total. Dicen lo que la app hace HOY: no mandan ubicación y el dictado puede ir a Apple.
enum TextoAgenteTotal {
    static let tituloReposo = "Asistente de voz"
    static let tituloEscuchando = "Escuchando…"
    static let tituloPensando = "Pensando…"
    static let etiquetaMicrofono = "Asistente de voz"
    static let reposo = "Toca el micrófono y dime a dónde quieres ir"
    static let saludo = "Asistente de voz. Toca el micrófono y dime a dónde quieres ir."
    static let escuchando = "Escuchando… Toca el micrófono cuando termines."
    static let pensando = "Pensando…"
    static let sinDictado = "El dictado no está disponible en esta pantalla. Escribe tu pregunta abajo."
    static let consultaCancelada = "Consulta cancelada."
    static let origenOlvidado = "Origen olvidado."

    static let pistaReposo = "Toca para decir a dónde quieres ir. También puedes escribir la pregunta más abajo."
    static let pistaEscuchando = "Toca otra vez cuando termines de hablar: se envía lo que dijiste."
    static let pistaPensando = "Cancela la consulta en curso."

    static let leQueHice = "Lo que hice"
    static let campo = "Escribe tu pregunta"
    static let marcadorCampo = "O escribe: cómo llego a Ricaurte"
    static let enviar = "Enviar pregunta"
    static let cancelar = "Cancelar"
    static let otrasPantallas = "Otras pantallas"
    static let buscarRutas = "Buscar rutas"
    static let rutasFrecuentes = "Rutas frecuentes"
    static let mapaYGps = "Mapa y GPS"
    static let planearViaje = "Planear un viaje entre dos lugares"

    /// Privacidad del asistente en el iPhone. No es la de la web: aquí el dictado es de iOS y no hay ubicación. En párrafos cortos:
    /// con el texto más grande cada uno cabe entero en la pantalla.
    static let privacidad = [
        "El dictado usa el reconocimiento de voz de tu iPhone; según el sistema, el audio puede enviarse a Apple (la línea de estado del dictado lo dice).",
        "Tu pregunta se envía al servidor configurado y, si está activo, a un modelo de lenguaje del servidor.",
        "Esta app no envía tu ubicación: di o escribe desde dónde sales. Puedes escribir en vez de hablar.",
    ]

    static func motor(_ motor: MotorAgente) -> String {
        "Motor: " + (motor == .ollama ? "Ollama" : "reglas")
    }

    /// Un tramo de viaje, tal como lo describe la pantalla de Consulta: información, nunca una orden de abordaje.
    static func tramo(_ tramo: TramoViaje) -> String {
        let conteo = tramo.conteoVerificado
            ? "\(tramo.estacionesRecorridas) estaciones (conteo verificado)"
            : "número de estaciones no verificado"
        return "Ruta \(tramo.codigoRuta): de \(tramo.estacionAbordaje) a \(tramo.estacionDescenso), \(conteo)."
    }
}

/// El asistente de voz de «Ceguera total» (web: `components/total-agent.tsx`), sobre la MISMA `ConsultaModelo` que la pestaña
/// Consulta: mismo cliente HTTP, misma aclaración de origen, mismo dictado y misma voz. Aquí solo vive lo que la pantalla de voz
/// añade: el estado que ve la persona, la política de qué se dice y por dónde, y a qué pantalla lleva cada respuesta.
///
/// - **Voz**: se dice con `ConsultaModelo.decir` (`ControlVoz`: voz permitida, ruta privada, sin micrófono abierto). Si no suena,
///   se anuncia por VoiceOver; si suena, no se repite por VoiceOver. Con VoiceOver activo no se dice el saludo ni lo que el
///   dictado ya anunció él mismo. Hoy `ControlVoz` solo habla por una ruta privada (auriculares): sin VoiceOver y por el
///   altavoz la pantalla se ve y vibra, pero no habla (ver `docs/expoandes/ios-agente-total.md`).
/// - **Dictado**: tocar el micrófono empieza; tocar otra vez termina y ENVÍA (no hay corte por silencio). «Cancelar» lo descarta todo.
///   Escribir y enviar mientras se escucha deja el micrófono, como la web.
/// - **Navegación**: como la web, una respuesta con pantalla propia la abre sola (`destino`); la voz de esa respuesta sigue
///   sonando. Un viaje no abre nada: se presenta como información y ofrece el planificador.
/// - **Invalidación**: salir de la pantalla (pestaña, modo, segundo plano) cancela captura, consulta y voz, salvo la navegación
///   que ordenó la respuesta vigente. Los cambios de la consulta que ocurren con la pantalla fuera de vista (hecha desde la
///   pestaña Consulta) no se dicen ni navegan.
@MainActor
@Observable
final class AgenteTotalModelo {
    let consulta: ConsultaModelo
    /// Pantalla que la vista debe tener abierta. La vista la empuja y la cierra con `destinoCerrado`.
    private(set) var destino: DestinoAgenteTotal?
    /// Mensaje propio de la pantalla (un problema del dictado, el dictado ausente) que prima sobre la última respuesta.
    private(set) var aviso: String?

    @ObservationIgnored private let avisos: AvisosAccesibles
    @ObservationIgnored private var activo = false
    @ObservationIgnored private var saludado = false
    /// La respuesta vigente fue la que abrió `destino`: su voz debe oírse entera aunque la pantalla deje de verse.
    @ObservationIgnored private var navegoPorRespuesta = false
    /// La persona canceló una consulta en curso: ese, y no otro, es el `.cancelada` que se dice.
    @ObservationIgnored private var esperaCancelada = false

    init(consulta: ConsultaModelo, avisos: AvisosAccesibles = AvisosAccesibles()) {
        self.consulta = consulta
        self.avisos = avisos
    }

    // MARK: Lo que ve la persona

    var fase: FaseAgenteTotal {
        if consulta.estaEnviando { return .pensando }
        if consulta.dictado?.estado.enCurso == true { return .escuchando }
        return .reposo
    }

    var titulo: String {
        switch fase {
        case .reposo: return TextoAgenteTotal.tituloReposo
        case .escuchando: return TextoAgenteTotal.tituloEscuchando
        case .pensando: return TextoAgenteTotal.tituloPensando
        }
    }

    /// Línea de estado, la «caption» de la web: qué hace el asistente ahora o qué pasó con la última pregunta.
    var subtitulo: String {
        switch fase {
        case .pensando:
            return TextoAgenteTotal.pensando
        case .escuchando:
            guard let dictado = consulta.dictado else { return TextoAgenteTotal.escuchando }
            return dictado.estado == .escuchando
                ? TextoAgenteTotal.escuchando : TextoDictado.descripcion(dictado.estado, capacidad: dictado.capacidad)
        case .reposo:
            if let aviso { return aviso }
            switch consulta.estado {
            case .inactiva: return TextoAgenteTotal.reposo
            case .enviando: return TextoAgenteTotal.pensando
            case .respuesta(let respuesta): return Self.textoHablado(respuesta, destino: Self.destino(para: respuesta.accion))
            case .error(let error): return "\(error.mensaje) \(error.recuperacion)"
            case .cancelada: return TextoAgenteTotal.consultaCancelada
            }
        }
    }

    /// La última respuesta, si es lo que la pantalla muestra (no hay un aviso ni una consulta en curso encima).
    var respuesta: RespuestaAgente? {
        guard aviso == nil, case .respuesta(let respuesta) = consulta.estado else { return nil }
        return respuesta
    }

    /// Error de la última consulta, para ofrecer «Reintentar».
    var puedeReintentar: Bool {
        guard aviso == nil, fase == .reposo, consulta.ultimoTextoEnviado != nil else { return false }
        switch consulta.estado {
        case .error(let error): return error.admiteReintento
        case .cancelada: return true
        default: return false
        }
    }

    /// Valor de accesibilidad del micrófono: el estado en palabras.
    var valorMicrofono: String {
        switch fase {
        case .pensando: return "pensando"
        case .reposo, .escuchando:
            guard let dictado = consulta.dictado else { return "no disponible" }
            return TextoDictado.valor(dictado.estado)
        }
    }

    var pistaMicrofono: String {
        switch fase {
        case .reposo: return TextoAgenteTotal.pistaReposo
        case .escuchando: return TextoAgenteTotal.pistaEscuchando
        case .pensando: return TextoAgenteTotal.pistaPensando
        }
    }

    // MARK: Respuesta → pantalla y voz

    /// Qué pantalla abre una acción del servidor, como la web. Un viaje no abre nada (nada verificado que mostrar).
    static func destino(para accion: AccionAgente) -> DestinoAgenteTotal? {
        switch accion {
        case .ninguna, .viaje: return nil
        case .frecuentes: return .favoritas
        case .gps: return .gps
        case .busqueda(let estacion): return .rutas(estacion: estacion)
        case .ruta(let codigo): return .ruta(codigo: codigo)
        }
    }

    /// Lo que la pantalla presenta y lee de una respuesta. Lo mismo que la consulta (`RespuestaAgente.textoHablado`), con dos
    /// diferencias: el límite de una acción solo se dice si la pantalla NO la abre (si no, diría «no hay pantalla» y la abriría),
    /// y un viaje, que se presenta como información, lee sus tramos. Un viaje nunca lee el texto del servidor.
    static func textoHablado(_ respuesta: RespuestaAgente, destino: DestinoAgenteTotal?) -> String {
        var partes: [String] = []
        if case .viaje(let tramos) = respuesta.accion {
            if let limite = respuesta.accion.limite { partes.append(limite) }
            partes.append(contentsOf: tramos.map(TextoAgenteTotal.tramo))
        } else {
            partes.append(respuesta.texto)
            if destino == nil, let limite = respuesta.accion.limite { partes.append(limite) }
        }
        if let procedencia = respuesta.procedenciaAparte { partes.append(procedencia) }
        if respuesta.catalogo?.antiguo == true { partes.append("Los datos de TransMilenio son antiguos.") }
        return partes.joined(separator: " ")
    }

    // MARK: Ciclo de vida de la pantalla

    func alAparecer() {
        activo = true
        navegoPorRespuesta = false
        consulta.lecturaAutomatica = false
        consulta.dictado?.actualizarCapacidad()
        guard !saludado else { return }
        saludado = true
        // Con VoiceOver activo la pantalla se lee sola al llegar el foco: un saludo encima lo pisaría.
        if !avisos.voiceOverActivo() { consulta.decir(TextoAgenteTotal.saludo) }
    }

    func alDesaparecer() {
        activo = false
        consulta.lecturaAutomatica = true
        if destino == nil {
            // La persona salió (otra pestaña u otro modo): captura, consulta y voz se invalidan y el saludo vuelve a tocar.
            saludado = false
            consulta.salir()
        } else if !navegoPorRespuesta {
            // Abrió ella una pantalla desde aquí: lo que estaba en curso ya no importa.
            consulta.salir()
        }
        // Si la respuesta vigente abrió la pantalla, su voz sigue sonando (decisión A de la web, EA-08).
    }

    func alPasarASegundoPlano() {
        consulta.salir()
    }

    /// La persona abre una de las otras pantallas desde la lista de la pantalla.
    func abrir(_ nuevo: DestinoAgenteTotal) {
        navegoPorRespuesta = false
        destino = nuevo
    }

    /// La pantalla abierta se cerró (el «atrás» del sistema).
    func destinoCerrado() {
        destino = nil
    }

    // MARK: Acciones de la persona

    /// El micrófono: empieza a escuchar; escuchando, termina y envía; si prepara o procesa, o está pensando, cancela.
    func tocarMicrofono() {
        guard let dictado = consulta.dictado else {
            avisar(TextoAgenteTotal.sinDictado)
            return
        }
        switch fase {
        case .pensando:
            cancelar()
        case .escuchando:
            if dictado.estado == .escuchando { dictado.alternar() } else { cancelar() }
        case .reposo:
            aviso = nil
            consulta.callar()
            dictado.alternar()
        }
    }

    /// Descarta captura, consulta y voz, y vuelve a reposo.
    func cancelar() {
        aviso = nil
        esperaCancelada = consulta.estaEnviando
        consulta.cancelar()
        consulta.callar()
    }

    /// Envía lo que hay en el campo. Esta pantalla no tiene escenario Metro: pregunta siempre por el transporte de hoy.
    func preguntar() {
        aviso = nil
        consulta.escenario = .transporte
        consulta.enviar()
        vaciarCampoSiSalio()
    }

    func reintentar() {
        aviso = nil
        consulta.reintentar()
        vaciarCampoSiSalio()
    }

    func olvidarOrigen() {
        consulta.olvidarOrigenPendiente()
        decir(TextoAgenteTotal.origenOlvidado)
    }

    /// El dictado entregó su texto final: se envía solo, como la web.
    func dictadoTerminado() {
        guard activo, consulta.dictado?.ultimoDictado != nil, !consulta.estaEnviando else { return }
        preguntar()
    }

    /// Un problema del dictado (permiso, sin texto, no disponible…) se dice y prima sobre la última respuesta. El propio dictado
    /// ya lo anunció por VoiceOver: aquí solo se agrega la voz de la app cuando VoiceOver no está activo.
    func dictadoCambio(_ estado: EstadoDictado) {
        guard activo, estado.esProblema, let dictado = consulta.dictado else { return }
        let texto = TextoDictado.descripcion(estado, capacidad: dictado.capacidad)
        aviso = texto
        if !avisos.voiceOverActivo() { consulta.decir(texto) }
    }

    /// La consulta cambió de estado. Solo cuenta con la pantalla a la vista y por una pregunta hecha desde ella.
    func consultaCambio(_ estado: EstadoConsulta) {
        guard activo else { return }
        switch estado {
        case .inactiva:
            break
        case .enviando:
            avisos.anunciar(TextoAgenteTotal.pensando, .rutina)
        case .respuesta(let respuesta):
            let abre = Self.destino(para: respuesta.accion)
            decir(Self.textoHablado(respuesta, destino: abre))
            if let abre {
                navegoPorRespuesta = true
                destino = abre
            }
        case .error(let error):
            decir("\(error.mensaje) \(error.recuperacion)")
        case .cancelada:
            guard esperaCancelada else { return }
            esperaCancelada = false
            decir(TextoAgenteTotal.consultaCancelada)
        }
    }

    // MARK: Internos

    /// Voz de la app y, si no suena, anuncio de VoiceOver. Nunca los dos: con la voz propia sonando VoiceOver no repite.
    private func decir(_ texto: String) {
        if consulta.decir(texto) { return }
        avisos.anunciar(texto, .rutina)
    }

    private func avisar(_ texto: String) {
        aviso = texto
        decir(texto)
    }

    /// Como la web, el campo queda vacío al enviar; si la pregunta no salió (vacía o demasiado larga) se conserva para corregirla.
    private func vaciarCampoSiSalio() {
        if consulta.estaEnviando { consulta.editarTexto("") }
    }
}
