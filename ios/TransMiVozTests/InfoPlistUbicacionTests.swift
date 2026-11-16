import XCTest
@testable import TransMiVoz

/// El texto con que iOS pide la ubicación está en el Info.plist de la app, en español, y es solo «al usar la app»: la ubicación
/// la usa «Mapa y GPS» mientras la persona la activa, sin segundo plano. Sin esta clave `UbicacionCoreLocation` dice que no
/// puede pedirla; con una de «siempre» o con un modo de fondo la app prometería lo que no hace.
final class InfoPlistUbicacionTests: XCTestCase {
    func testLaUbicacionSoloSePideAlUsarLaAppYSuTextoDiceQueSeEnviaAlServidor() {
        let info = Bundle(for: DictadoModelo.self).infoDictionary ?? [:]
        let texto = info["NSLocationWhenInUseUsageDescription"] as? String ?? ""
        XCTAssertTrue(texto.contains("ubicación"), "falta el texto del permiso de ubicación: \(texto)")
        XCTAssertTrue(texto.contains("servidor"), "el texto debe decir que la lectura se envía al servidor: \(texto)")
        XCTAssertTrue(texto.contains("no la guarda"), "el texto debe decir que la app no la guarda: \(texto)")
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"], "no hay ubicación «siempre»")
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"], "no hay ubicación «siempre»")
        XCTAssertNil(info["UIBackgroundModes"], "no hay modos de segundo plano")
    }
}
