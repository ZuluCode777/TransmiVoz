import XCTest

/// Cableado entre pantallas de la integración (EA-25, #51): lo que ninguna pantalla prueba sola. Corren con `-PRUEBAS_UI_SIMULADAS`
/// (cliente, dictado y ubicación sintéticos y rotulados; sin red, micrófono, GPS ni voz reales). No auditan accesibilidad ni
/// prueban VoiceOver, CoreLocation ni un iPhone, y no tocan los ayudantes ni las tolerancias de `TransMiVozUITests.swift`.
final class TransMiVozIntegracionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func lanzar(_ argumentos: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += [
            "-PRUEBAS_UI_SIMULADAS", "-AppleLanguages", "(es)", "-AppleLocale", "es_CO",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
        ] + argumentos
        app.launch()
        addTeardownBlock { [app] in app?.terminate() }
        XCTAssertTrue(elemento("inicio-titulo").waitForExistence(timeout: 10), "Inicio no apareció al arrancar")
    }

    private func elemento(_ identificador: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identificador).firstMatch
    }

    /// Lleva el elemento a la vista deslizando la pantalla (con el texto grande no todo cabe).
    private func exponer(_ id: String) {
        let objetivo = elemento(id)
        XCTAssertTrue(objetivo.waitForExistence(timeout: 10), "No existe «\(id)»")
        var gestos = 0
        while !objetivo.isHittable && gestos < 14 {
            app.swipeUp(velocity: .slow)
            gestos += 1
        }
        XCTAssertTrue(objetivo.isHittable, "«\(id)» no queda a la vista")
    }

    private func abrirGpsDesdeInicio() {
        exponer("inicio-gps")
        elemento("inicio-gps").tap()
        XCTAssertTrue(app.navigationBars["Mapa y GPS"].waitForExistence(timeout: 10), "No se abrió «Mapa y GPS»")
    }

    /// Cambiar de pestaña con «Mapa y GPS» empujada suelta la ubicación (la raíz la detiene) y no se reanuda sola al volver.
    func testCambiarDePestanaSueltaLaUbicacionYNoSeReanudaSola() throws {
        lanzar(["-PRUEBAS_UI_GPS_PERMISO_CONCEDIDO"])
        abrirGpsDesdeInicio()
        XCTAssertTrue(elemento("gps-activar").exists, "nada se pide al abrir: la persona activa la ubicación")
        XCTAssertFalse(elemento("gps-detener").exists)
        elemento("gps-activar").tap()
        XCTAssertTrue(elemento("gps-detener").waitForExistence(timeout: 10), "la ubicación debía quedar activa")

        app.tabBars.buttons["Consulta"].tap()
        XCTAssertTrue(app.navigationBars["Consulta"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Inicio"].tap()
        XCTAssertTrue(app.navigationBars["Mapa y GPS"].waitForExistence(timeout: 10), "«Mapa y GPS» sigue empujada en Inicio")
        XCTAssertTrue(elemento("gps-activar").waitForExistence(timeout: 10), "al volver la ubicación está suelta: se vuelve a pedir")
        XCTAssertFalse(elemento("gps-detener").exists, "la ubicación no se reanuda sola")
    }

    /// Consulta no navega sola, pero ofrece el botón de cada pantalla que la web abre con la respuesta.
    func testConsultaOfreceLosBotonesDeRutasFrecuentesYDeMapaYGps() throws {
        lanzar()
        app.tabBars.buttons["Consulta"].tap()
        let campo = elemento("campo-pregunta")
        XCTAssertTrue(campo.waitForExistence(timeout: 10))
        campo.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "El teclado no apareció")
        campo.typeText("frecuentes")
        elemento("boton-enviar").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "El teclado debe cerrarse al enviar")
        let enlace = elemento("enlace-rutas-frecuentes-consulta")
        XCTAssertTrue(enlace.waitForExistence(timeout: 10), "falta el botón de rutas frecuentes")
        XCTAssertTrue(elemento("limite-accion").label.contains("no abre sola"), "el límite dice que Consulta no navega sola")
        enlace.tap()
        XCTAssertTrue(elemento("favoritas-vacio").waitForExistence(timeout: 10), "se abrió la lista de favoritas")
    }
}
