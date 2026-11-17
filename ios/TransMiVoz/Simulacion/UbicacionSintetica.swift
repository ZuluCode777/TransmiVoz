#if DEBUG
import ContratoBLE
import Foundation

/// Ubicación SINTÉTICA para las pruebas de interfaz de «Mapa y GPS» (con `-PRUEBAS_UI_SIMULADAS`): sin CoreLocation, sin GPS
/// ni brújula reales y sin aviso de permiso del sistema. La pantalla lo rotula. La posición es inventada (cerca de las
/// estaciones «Ejemplo» del planificador simulado).
///
/// Por defecto el permiso está por preguntar y el «sistema» concede, y llega una lectura con precisión de 10 m y brújula con
/// norte verdadero. Argumentos de arranque:
/// - `-PRUEBAS_UI_GPS_PERMISO_CONCEDIDO`: concedido de antemano;
/// - `-PRUEBAS_UI_GPS_PERMISO_DENEGADO` / `-PRUEBAS_UI_GPS_PERMISO_RESTRINGIDO`: el sistema lo niega;
/// - `-PRUEBAS_UI_GPS_SIN_SENAL`: permiso concedido y ninguna lectura (la pantalla sigue buscando);
/// - `-PRUEBAS_UI_GPS_IMPRECISA`: precisión de 120 m;
/// - `-PRUEBAS_UI_GPS_SIN_BRUJULA`: el iPhone no tiene brújula;
/// - `-PRUEBAS_UI_GPS_SIN_RUMBO`: hay brújula pero ninguna lectura con norte verdadero;
/// - `-PRUEBAS_UI_GPS_VENCE`: la lectura llega con 59,5 s de antigüedad y vence casi enseguida.
@MainActor
final class UbicacionSintetica: ProveedorUbicacion {
    enum Permiso { case porPreguntar, concedido, denegado, restringido }

    private let permiso: Permiso
    private let hayBrujula: Bool
    private let conLectura: Bool
    private let conRumbo: Bool
    private let precision: Double
    private let edadInicialMs: Milisegundos
    private let reloj: RelojMonotonico
    private var tarea: Task<Void, Never>?

    var alEvento: ((EventoUbicacion) -> Void)?
    var rumboDisponible: Bool { hayBrujula }

    init(argumentos: [String], reloj: @escaping RelojMonotonico = RelojDelSistema.ahora) {
        permiso =
            argumentos.contains("-PRUEBAS_UI_GPS_PERMISO_CONCEDIDO") ? .concedido
            : argumentos.contains("-PRUEBAS_UI_GPS_PERMISO_DENEGADO") ? .denegado
            : argumentos.contains("-PRUEBAS_UI_GPS_PERMISO_RESTRINGIDO") ? .restringido : .porPreguntar
        hayBrujula = !argumentos.contains("-PRUEBAS_UI_GPS_SIN_BRUJULA")
        conLectura = !argumentos.contains("-PRUEBAS_UI_GPS_SIN_SENAL")
        conRumbo = hayBrujula && !argumentos.contains("-PRUEBAS_UI_GPS_SIN_RUMBO")
        precision = argumentos.contains("-PRUEBAS_UI_GPS_IMPRECISA") ? 120 : 10
        edadInicialMs = argumentos.contains("-PRUEBAS_UI_GPS_VENCE") ? 59_500 : 0
        self.reloj = reloj
    }

    func iniciar() {
        tarea?.cancel()
        tarea = Task { [weak self] in
            guard let self else { return }
            switch self.permiso {
            case .denegado:
                self.alEvento?(.permiso(.porPreguntar))
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.alEvento?(.permiso(.denegado))
                return
            case .restringido:
                self.alEvento?(.permiso(.restringido))
                return
            case .porPreguntar:
                self.alEvento?(.permiso(.porPreguntar))
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                self.alEvento?(.permiso(.concedido))
            case .concedido:
                self.alEvento?(.permiso(.concedido))
            }
            guard self.conLectura else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
            // El rumbo llega antes que la lectura, como suele pasar con la brújula del iPhone: la primera consulta ya lo lleva.
            self.alEvento?(.rumbo(self.conRumbo ? RumboMedido(gradosVerdaderos: 0, calidad: 10, capturadoMs: self.reloj()) : nil))
            self.alEvento?(.posicion(PosicionMedida(
                latitud: 4.6500, longitud: -74.0850, precision: self.precision,
                capturadaMs: self.reloj() - self.edadInicialMs)))
        }
    }

    func detener() {
        tarea?.cancel()
        tarea = nil
    }
}
#endif
