import ContratoBLE
import XCTest
@testable import TransMiVoz

/// El mismo JSON con un cambio, para derivar variantes inválidas de un fixture válido sin copiarlo entero.
func modificar(_ json: String, _ cambio: (inout [String: Any]) -> Void) -> String {
    var objeto = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    cambio(&objeto)
    let datos = (try? JSONSerialization.data(withJSONObject: objeto, options: [.sortedKeys])) ?? Data()
    return String(decoding: datos, as: UTF8.self)
}

/// Proveedor de ubicación que controla la prueba: no hay CoreLocation, GPS ni brújula.
@MainActor
final class UbicacionFalsa: ProveedorUbicacion {
    var alEvento: ((EventoUbicacion) -> Void)?
    var rumboDisponible: Bool
    private(set) var iniciados = 0
    private(set) var detenidos = 0

    init(rumboDisponible: Bool = true) { self.rumboDisponible = rumboDisponible }

    func iniciar() { iniciados += 1 }
    func detener() { detenidos += 1 }

    /// Entrega un evento como lo haría el sistema. Si nadie escucha (la sesión se detuvo), se pierde, como un sensor soltado.
    func emitir(_ evento: EventoUbicacion) { alEvento?(evento) }
    var hayOyente: Bool { alEvento != nil }
}

/// Locutor que anota lo que se dijo y cuántas veces se cortó lo propio. `resultado` es lo que contesta a cada frase: la prueba
/// lo cambia para simular que suena otro aviso (`.ocupada`) o que la voz está apagada (`.silenciada`).
@MainActor
final class LocutorFalso: Locutor {
    private(set) var dichos: [String] = []
    /// Si cada frase pidió anunciarse con VoiceOver cuando la voz calla.
    private(set) var anunciosConVoiceOver: [Bool] = []
    private(set) var cortes = 0
    var resultado: ResultadoLocucion = .hablada

    func decir(_ texto: String, anunciarConVoiceOver: Bool) -> ResultadoLocucion {
        dichos.append(texto)
        anunciosConVoiceOver.append(anunciarConVoiceOver)
        return resultado
    }

    func cortarLoPropio() { cortes += 1 }
}

/// Mapas del sistema de mentira: anota a qué estación se pidió la ruta, y solo eso (no recibe ninguna otra coordenada).
@MainActor
final class AbridorFalso: AbridorMapas {
    private(set) var aperturas: [(nombre: String, coordenada: Coordenada)] = []

    func abrirRutaAPie(haciaEstacion nombre: String, en coordenada: Coordenada) {
        aperturas.append((nombre, coordenada))
    }
}

/// Espera, sin dormir de más, a que se cumpla algo que ocurre en otra tarea (hasta ~5 s).
@MainActor
func esperarHasta(_ descripcion: String = "condición", file: StaticString = #filePath, line: UInt = #line, _ condicion: () -> Bool) async {
    for _ in 0..<500 where !condicion() {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertTrue(condicion(), "no se cumplió: \(descripcion)", file: file, line: line)
}

/// Deja pasar el tiempo para comprobar que NO ocurre algo (por ejemplo, una petición que no debe salir).
func dejarPasar(_ ms: UInt64 = 120) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
