import ContratoBLE
import Foundation

/// Permiso de ubicación «al usar la app», ya traducido de CoreLocation. Solo existe este nivel: la app no pide ubicación
/// «siempre» ni corre en segundo plano.
enum PermisoUbicacion: Equatable, Sendable {
    /// Todavía no se preguntó: el sistema mostrará su aviso.
    case porPreguntar
    case concedido
    case denegado
    /// Restringido por el sistema (por ejemplo, control parental): la persona no lo puede cambiar desde la app.
    case restringido
    /// La app no puede pedirlo (falta la descripción de uso en la configuración del proyecto).
    case noDisponible
}

/// Una lectura de posición. Vive solo en memoria: no se guarda, no se registra y no se imprime (su descripción la oculta).
struct PosicionMedida: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let latitud: Double
    let longitud: Double
    /// Radio de precisión en metros. `nil` si el sistema no la da (CoreLocation la da negativa cuando la coordenada no es válida).
    let precision: Double?
    /// Cuándo se capturó, en el reloj monotónico del iPhone (no la hora de pared).
    let capturadaMs: Milisegundos

    var description: String { "PosicionMedida(…)" }
    var debugDescription: String { description }
}

/// Una lectura de brújula respecto al NORTE VERDADERO. El rumbo magnético no se usa: la dirección hacia la estación es
/// geográfica, y un rumbo magnético desviaría el giro.
struct RumboMedido: Equatable, Sendable {
    /// 0…360.
    let gradosVerdaderos: Double
    /// Cota de error en grados (`headingAccuracy`); `nil` si el sistema no la da.
    let calidad: Double?
    let capturadoMs: Milisegundos
}

enum EventoUbicacion: Equatable, Sendable {
    case permiso(PermisoUbicacion)
    case posicion(PosicionMedida)
    /// `nil`: el sistema no tiene un rumbo verdadero válido ahora. Invalida el rumbo anterior: uno «bueno» ya viejo no se retiene.
    case rumbo(RumboMedido?)
    /// El sistema no pudo dar una posición (sin señal, falla momentánea). No cierra el permiso ni la sesión.
    case sinSenal
}

/// Fuente de ubicación y brújula de la pantalla «Mapa y GPS». La implementa `UbicacionCoreLocation`; las pruebas y el
/// modo de pruebas de interfaz usan dobles. Reglas del contrato:
/// - nada se escucha hasta `iniciar()` (la persona lo pide) y nada llega después de `detener()`;
/// - solo en primer plano: no hay ubicación en segundo plano ni al salir de la pantalla;
/// - los eventos llegan en el hilo principal y se limitan a actualizar el estado: ninguno dispara una petición de red.
@MainActor
protocol ProveedorUbicacion: AnyObject {
    /// ¿El iPhone tiene brújula? Sin ella nunca hay rumbo y el servidor solo da referencias cardinales.
    var rumboDisponible: Bool { get }
    /// Quien escucha los eventos. Un solo oyente.
    var alEvento: ((EventoUbicacion) -> Void)? { get set }
    /// Pide el permiso si hace falta y empieza a escuchar posición y rumbo cuando está concedido.
    func iniciar()
    /// Deja de escuchar y suelta el sistema. Idempotente.
    func detener()
}
