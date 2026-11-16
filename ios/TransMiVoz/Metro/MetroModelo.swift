import Foundation
import Observation

/// Estado de la pantalla «Metro de Bogotá»: pide el catálogo a `POST /api/planificador` (`metro-linea-1`) y lo conserva
/// mientras la pantalla vive. El catálogo solo cambia con un despliegue: se pide una vez por apertura, sin sondeo ni
/// reintentos automáticos. Una sola petición vigente; salir de la pantalla la descarta.
@MainActor
@Observable
final class MetroModelo {
    private(set) var estado: EstadoCarga<RespuestaMetro> = .inactivo
    /// Estación cuya huella se resalta en el mapa (la persona la elige en su ficha); `nil` si ninguna.
    private(set) var resaltada: String?
    /// Qué pasó con el último «Repetir»: por qué no se oyó, si no se oyó. `nil` si se dijo o no se pidió.
    private(set) var avisoVoz: String?

    @ObservationIgnored private let cliente: ClientePlanificador
    @ObservationIgnored private let ejecutor = EjecutorUnico()
    @ObservationIgnored private let locutor: Locutor?
    /// La pantalla está a la vista: solo entonces se narra.
    @ObservationIgnored private var visible = false
    /// Ya se dijo el estado en esta visita.
    @ObservationIgnored private var narrado = false

    init(cliente: ClientePlanificador, locutor: Locutor? = nil) {
        self.cliente = cliente
        self.locutor = locutor
    }

    /// Hay voz para «Repetir».
    var puedeRepetirEstado: Bool {
        if case .listo = estado { return locutor != nil }
        return false
    }

    /// La pantalla aparece: pide el catálogo si no lo tiene (o si la apertura anterior terminó en error).
    func alAparecer() {
        visible = true
        narrado = false
        switch estado {
        case .inactivo, .fallo: cargar()
        case .cargando: break
        case .listo: narrarAlEntrar()
        }
    }

    /// «Reintentar» y primera carga.
    func cargar() {
        estado = .cargando
        ejecutor.ejecutar({ [cliente] in try await cliente.metroLinea1() }) { [self] resultado in
            switch resultado {
            case .success(let respuesta):
                estado = .listo(respuesta)
                narrarAlEntrar()
            case .failure(let error): estado = .fallo(error)
            }
        }
    }

    /// La pantalla dejó de verse: la petición en curso se descarta (su respuesta tardía no se aplica) y, si no había
    /// terminado, la próxima apertura vuelve a pedir. Lo ya cargado se conserva.
    func alDesaparecer() {
        visible = false
        narrado = false
        avisoVoz = nil
        locutor?.cortarLoPropio()
        ejecutor.invalidar()
        if estado == .cargando { estado = .inactivo }
    }

    /// La nota de estado, dicha una vez por visita y sin anunciarla con VoiceOver. Si suena otra cosa o la voz calla, no se dice:
    /// el texto está en pantalla y «Repetir» lo reintenta.
    private func narrarAlEntrar() {
        guard visible, !narrado, case .listo(let respuesta) = estado else { return }
        narrado = true
        _ = locutor?.decir(respuesta.textoEstado, anunciarConVoiceOver: false)
    }

    /// «Repetir el estado en voz alta» (EA-02 §5): la persona lo pide, así que si no se pudo decir se le explica por qué.
    func repetirEstado() {
        guard let locutor, case .listo(let respuesta) = estado else { return }
        switch locutor.decir(respuesta.textoEstado, anunciarConVoiceOver: false) {
        case .hablada: avisoVoz = nil
        case .ocupada: avisoVoz = TextoMetro.vozOcupada
        case .silenciada, .anunciada: avisoVoz = TextoMetro.vozApagada
        }
    }

    func resaltar(_ idEstacion: String?) {
        guard let idEstacion else { resaltada = nil; return }
        guard case .listo(let respuesta) = estado, respuesta.estaciones.contains(where: { $0.id == idEstacion }) else { return }
        resaltada = idEstacion
    }
}
