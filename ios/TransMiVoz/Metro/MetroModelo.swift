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

    @ObservationIgnored private let cliente: ClientePlanificador
    @ObservationIgnored private let ejecutor = EjecutorUnico()

    init(cliente: ClientePlanificador) {
        self.cliente = cliente
    }

    /// La pantalla aparece: pide el catálogo si no lo tiene (o si la apertura anterior terminó en error).
    func alAparecer() {
        switch estado {
        case .inactivo, .fallo: cargar()
        case .cargando, .listo: break
        }
    }

    /// «Reintentar» y primera carga.
    func cargar() {
        estado = .cargando
        ejecutor.ejecutar({ [cliente] in try await cliente.metroLinea1() }) { [self] resultado in
            switch resultado {
            case .success(let respuesta): estado = .listo(respuesta)
            case .failure(let error): estado = .fallo(error)
            }
        }
    }

    /// La pantalla dejó de verse: la petición en curso se descarta (su respuesta tardía no se aplica) y, si no había
    /// terminado, la próxima apertura vuelve a pedir. Lo ya cargado se conserva.
    func alDesaparecer() {
        ejecutor.invalidar()
        if estado == .cargando { estado = .inactivo }
    }

    func resaltar(_ idEstacion: String?) {
        guard let idEstacion else { resaltada = nil; return }
        guard case .listo(let respuesta) = estado, respuesta.estaciones.contains(where: { $0.id == idEstacion }) else { return }
        resaltada = idEstacion
    }
}
