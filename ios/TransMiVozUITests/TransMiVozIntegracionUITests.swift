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

    // MARK: «La app dijo» y antigüedad de la ubicación en «Mapa y GPS» (EA-02 §5 y §9)

    private let frasePrimeraLectura = "Ubicación lista. La estación más cercana es Estación Ejemplo Centro, a 40 metros al norte."
    private let fraseActivando = "Activando ubicación. Por favor acepta el permiso."
    private let fraseVencida =
        "Tu ubicación ya no está actualizada. Espera una lectura nueva o toca «Detener la ubicación» y vuelve a activarla."

    private func activarGps(_ argumentos: [String] = ["-PRUEBAS_UI_GPS_PERMISO_CONCEDIDO"]) {
        lanzar(argumentos)
        abrirGpsDesdeInicio()
        exponer("gps-activar")
        elemento("gps-activar").tap()
    }

    /// Todo lo que la app dice queda en texto exacto, «Repetir» vuelve a decir la última frase sin consulta ni cambios, y la edad de la
    /// lectura se ve junto a la precisión y avanza.
    func testLaPrimeraLecturaDejaLaTranscripcionExactaSeRepiteSinConsultaYMuestraLaEdad() throws {
        activarGps()
        XCTAssertTrue(elemento("gps-app-dijo-1").waitForExistence(timeout: 15), "no apareció la frase de la primera lectura")
        XCTAssertEqual(elemento("gps-app-dijo").label, "La app dijo")
        XCTAssertEqual(elemento("gps-app-dijo-0").label, fraseActivando)
        XCTAssertEqual(elemento("gps-app-dijo-1").label, frasePrimeraLectura, "el texto exacto que se dijo")
        XCTAssertEqual(
            elemento("gps-app-dijo-resultado").label,
            "La voz de la app está apagada o no hay auriculares: se anunció con VoiceOver.",
            "en pruebas la salida no es privada: se dice cómo salió")

        XCTAssertTrue(elemento("gps-edad").waitForExistence(timeout: 10), "falta la edad de la lectura")
        XCTAssertTrue(elemento("gps-edad").label.hasPrefix("Lectura de ubicación de hace"), elemento("gps-edad").label)
        XCTAssertTrue(elemento("gps-precision").exists, "la edad va junto a la precisión")

        exponer("gps-repetir-dicho")
        elemento("gps-repetir-dicho").tap()
        XCTAssertEqual(elemento("gps-app-dijo-1").label, frasePrimeraLectura, "repetir no cambia la frase")
        XCTAssertFalse(elemento("gps-app-dijo-2").exists, "repetir no añade otra línea")
        XCTAssertFalse(elemento("gps-consultando").exists, "repetir no pide otra consulta")
        XCTAssertTrue(elemento("gps-estacion-0").exists)

        // La edad avanza sola mientras se ve: después de al menos un segundo ya dice «hace N segundo(s)».
        let avanzo = NSPredicate(format: "label MATCHES %@", ".*hace [1-9][0-9]* segundo.*")
        expectation(for: avanzo, evaluatedWith: elemento("gps-edad"))
        waitForExpectations(timeout: 10)
    }

    /// Detener borra la transcripción y la edad: no queda nada que repetir de la sesión anterior.
    func testDetenerBorraLaTranscripcionYLaEdad() throws {
        activarGps()
        XCTAssertTrue(elemento("gps-app-dijo-1").waitForExistence(timeout: 15))
        exponer("gps-detener")
        elemento("gps-detener").tap()
        XCTAssertTrue(elemento("gps-activar").waitForExistence(timeout: 10))
        XCTAssertFalse(elemento("gps-app-dijo").exists, "sin sesión no hay «La app dijo»")
        XCTAssertFalse(elemento("gps-repetir-dicho").exists)
        XCTAssertFalse(elemento("gps-edad").exists, "sin lectura no hay edad")
    }

    /// Una lectura que está por vencer: el aviso queda en la transcripción, las estaciones viejas desaparecen y «Repetir» dice
    /// el aviso, no la orientación vieja.
    func testUnaUbicacionVencidaDejaElAvisoEnLaTranscripcionYRepetirNoDiceLoViejo() throws {
        activarGps(["-PRUEBAS_UI_GPS_PERMISO_CONCEDIDO", "-PRUEBAS_UI_GPS_VENCE"])
        let aviso = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "gps-app-dijo-", fraseVencida)).firstMatch
        XCTAssertTrue(aviso.waitForExistence(timeout: 20), "el aviso de ubicación vencida debía quedar en «La app dijo»")
        XCTAssertFalse(elemento("gps-estacion-0").exists, "las estaciones de una lectura vencida no se presentan")
        XCTAssertFalse(elemento("gps-edad").exists, "una lectura vencida no tiene edad")
        exponer("gps-repetir-dicho")
        elemento("gps-repetir-dicho").tap()
        XCTAssertFalse(elemento("gps-estacion-0").exists)
        XCTAssertTrue(aviso.exists)
        XCTAssertEqual(elemento("gps-estado").label, fraseVencida)
    }
}

