import XCTest

/// Pantallas «Metro de Bogotá» y «Mapa y GPS» (paridad con la web, EA-25). Corren con `-PRUEBAS_UI_SIMULADAS`: el planificador
/// es el simulado (datos inventados, rotulados «[SIMULADO]») y la ubicación es sintética (sin CoreLocation, GPS ni brújula
/// reales; cada variante la elige un argumento `-PRUEBAS_UI_GPS_*` o `-PRUEBAS_UI_METRO_*`). El mapa no se dibuja: la pantalla lo
/// rotula y el listado está completo. Demuestran la interfaz; NO prueban VoiceOver, CoreLocation ni un iPhone, y no tocan los
/// ayudantes ni las tolerancias de auditoría de `TransMiVozUITests.swift`: aquí la auditoría reúne TODOS los problemas de
/// TODOS los tipos y falla si hay alguno.
class ParidadUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func lanzar(_ argumentos: [String] = [], categoria: String = "UICTContentSizeCategoryL") {
        app = XCUIApplication()
        app.launchArguments += [
            "-PRUEBAS_UI_SIMULADAS", "-AppleLanguages", "(es)", "-AppleLocale", "es_CO",
            "-UIPreferredContentSizeCategoryName", categoria,
        ] + argumentos
        app.launch()
        addTeardownBlock { [app] in app?.terminate() }
        XCTAssertTrue(elemento("inicio-titulo").waitForExistence(timeout: 10), "Inicio no apareció al arrancar")
    }

    func elemento(_ identificador: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identificador).firstMatch
    }

    /// Desplaza hacia arriba la pantalla hasta que el elemento se pueda tocar (con el texto grande no todo cabe).
    func exponer(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let objetivo = elemento(id)
        XCTAssertTrue(objetivo.waitForExistence(timeout: 10), "No existe «\(id)»", file: file, line: line)
        var gestos = 0
        while !objetivo.isHittable && gestos < 14 {
            app.swipeUp(velocity: .slow)
            gestos += 1
        }
        XCTAssertTrue(objetivo.isHittable, "«\(id)» no queda a la vista tras \(gestos) desplazamientos", file: file, line: line)
    }

    func abrirBaldosa(_ id: String, barra: String, file: StaticString = #filePath, line: UInt = #line) {
        exponer(id, file: file, line: line)
        elemento(id).tap()
        XCTAssertTrue(app.navigationBars[barra].waitForExistence(timeout: 10), "No se abrió «\(barra)»", file: file, line: line)
    }

    func volverAInicio(file: StaticString = #filePath, line: UInt = #line) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(elemento("inicio-titulo").waitForExistence(timeout: 10), "No se volvió a Inicio", file: file, line: line)
    }

    /// Alto mínimo de 44 pt de un control tocable.
    func comprobarTocable(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        exponer(id, file: file, line: line)
        XCTAssertGreaterThanOrEqual(elemento(id).frame.height, 44, "«\(id)» mide menos de 44 pt", file: file, line: line)
    }

    /// Auditoría nativa de accesibilidad de todos los tipos, sin filtros ni exclusiones. Reúne todos los problemas y falla si hay alguno.
    func auditar(_ contexto: String, file: StaticString = #filePath, line: UInt = #line) throws {
        var problemas: [String] = []
        // Los mismos cuatro grupos que la auditoría de las demás pantallas: contraste, todo lo demás, y los dos que cambian fuentes.
        let grupos: [XCUIAccessibilityAuditType] = [
            .contrast, .all.subtracting([.contrast, .dynamicType, .textClipped]), .dynamicType, .textClipped,
        ]
        for tipos in grupos {
            try app.performAccessibilityAudit(for: tipos) { problema in
                problemas.append("\(problema.auditType): \(problema.compactDescription) [\(problema.element?.identifier ?? "?")]")
                return true
            }
        }
        if !problemas.isEmpty {
            let texto = XCTAttachment(string: problemas.joined(separator: "\n") + "\n\n" + app.debugDescription)
            texto.name = "auditoria-\(contexto)"
            texto.lifetime = .keepAlways
            add(texto)
        }
        XCTAssertTrue(problemas.isEmpty, "Auditoría (\(contexto)): \(problemas.count) problema(s):\n" + problemas.joined(separator: "\n"), file: file, line: line)
    }
}

// MARK: - Metro

final class TransMiVozMetroUITests: ParidadUITestCase {
    private let estaciones = (1...16).map { String(format: "E%02d", $0) }

    private func abrirMetro() {
        abrirBaldosa("inicio-metro", barra: "Metro de Bogotá")
    }

    func testMetroDiceQueNoHayServicioMuestraElMapaRotuladoYLas16Estaciones() throws {
        lanzar()
        abrirMetro()
        let estado = elemento("metro-estado")
        XCTAssertTrue(estado.waitForExistence(timeout: 10), "el catálogo no cargó")
        XCTAssertTrue(estado.label.contains("en construcción y sin servicio comercial"), estado.label)
        XCTAssertTrue(estado.label.contains("[SIMULADO]"), "los datos de prueba se rotulan: \(estado.label)")
        XCTAssertTrue(app.staticTexts["Línea 1 · en construcción · sin servicio"].exists)

        // El mapa del proyecto: rótulo y atribución como texto junto a él; en las pruebas el mapa no se dibuja y se dice.
        XCTAssertTrue(elemento("metro-rotulo").exists)
        XCTAssertEqual(elemento("metro-rotulo").label, "Metro Línea 1 · proyecto futuro, sin servicio")
        XCTAssertTrue(elemento("metro-mapa").exists)
        XCTAssertTrue(elemento("metro-mapa").label.contains("el mapa no se dibuja"))
        XCTAssertTrue(elemento("metro-aviso-mapa").exists)
        XCTAssertTrue(elemento("metro-atribucion").exists)

        // Las 16 estaciones están en el listado, completo y sin depender del mapa.
        for id in estaciones { XCTAssertTrue(elemento("metro-estacion-\(id)").exists, "falta la estación \(id)") }
        exponer("metro-estacion-E16")
        exponer("metro-linea-2")
        XCTAssertTrue(elemento("metro-linea-2").label.contains("Línea 2 · en contratación"))
        exponer("metro-fuente-F1")
    }

    func testRepetirElEstadoEnVozAltaEsUnBotonDe44PuntosYExplicaSiLaVozNoEstaActiva() throws {
        lanzar()
        abrirMetro()
        XCTAssertTrue(elemento("metro-estado").waitForExistence(timeout: 10))
        comprobarTocable("metro-repetir")
        elemento("metro-repetir").tap()
        // En las pruebas la voz de la app es de mentira (sin salida privada): se dice por qué no se oyó, y la nota sigue en pantalla.
        let aviso = elemento("metro-aviso-voz")
        XCTAssertTrue(aviso.waitForExistence(timeout: 10))
        XCTAssertTrue(aviso.label.contains("VoiceOver"), aviso.label)
        XCTAssertTrue(elemento("metro-estado").label.contains("en construcción y sin servicio comercial"))
    }

    func testElMapaDiceComoTocarUnaHuellaYLaListaSigueCompleta() throws {
        lanzar()
        abrirMetro()
        XCTAssertTrue(elemento("metro-estado").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Toca una huella del mapa para saber qué estación es; la lista de abajo tiene todas."].exists)
        for id in estaciones { XCTAssertTrue(elemento("metro-estacion-\(id)").exists) }
    }

    func testUnaEstacionSeAbreYSuHuellaSeResaltaEnElMapa() throws {
        lanzar()
        abrirMetro()
        exponer("metro-estacion-E07")
        let e07 = elemento("metro-estacion-E07")
        XCTAssertTrue(e07.label.contains("nombre pendiente"), "E07 no tiene nombre público y no se inventa: \(e07.label)")
        e07.tap()
        let resaltar = elemento("metro-resaltar-E07")
        XCTAssertTrue(resaltar.waitForExistence(timeout: 10), "la ficha no se abrió")
        comprobarTocable("metro-resaltar-E07")
        resaltar.tap()
        let nota = elemento("metro-huella-resaltada")
        XCTAssertTrue(nota.waitForExistence(timeout: 10))
        XCTAssertTrue(nota.label.contains("E07"))
        XCTAssertTrue(nota.label.contains("no es una entrada"), nota.label)
    }

    func testUnServidorAnteriorDa400SeDiceYSeOfreceReintentar() throws {
        lanzar(["-PRUEBAS_UI_METRO_ANTIGUO"])
        abrirMetro()
        let error = elemento("metro-error")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("400"), error.label)
        XCTAssertTrue(error.label.contains("versión anterior del servidor"), error.label)
        XCTAssertTrue(app.staticTexts["Línea 1 · en construcción · sin servicio"].exists, "el estado sin servicio se dice también si falla")
        XCTAssertFalse(elemento("metro-estacion-E01").exists, "sin catálogo no se muestra ninguna estación")
        comprobarTocable("metro-reintentar")
        elemento("metro-reintentar").tap() // vuelve a pedir y vuelve a fallar: el botón sigue
        XCTAssertTrue(elemento("metro-error").waitForExistence(timeout: 10))
    }

    func testSinConexionSeDiceYLaPantallaSigueDiciendoQueNoHayServicio() throws {
        lanzar(["-PRUEBAS_UI_METRO_SIN_RED"])
        abrirMetro()
        let error = elemento("metro-error")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("No hay conexión con el servidor"), error.label)
        XCTAssertTrue(elemento("metro-reintentar").exists)
    }

    func testMientrasCargaYSalirLaPeticionSeDescarta() throws {
        lanzar(["-PRUEBAS_UI_METRO_LENTO"])
        abrirMetro()
        XCTAssertTrue(elemento("metro-cargando").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Línea 1 · en construcción · sin servicio"].exists)
        volverAInicio()
        abrirMetro()
        XCTAssertTrue(elemento("metro-cargando").waitForExistence(timeout: 10), "al volver, pide de nuevo")
    }

    func testAuditoriaAccesibilidadMetro() throws {
        lanzar()
        abrirMetro()
        XCTAssertTrue(elemento("metro-estado").waitForExistence(timeout: 10))
        try auditar("metro-listo")
    }

    func testAuditoriaAccesibilidadMetroConError() throws {
        lanzar(["-PRUEBAS_UI_METRO_ANTIGUO"])
        abrirMetro()
        XCTAssertTrue(elemento("metro-error").waitForExistence(timeout: 10))
        try auditar("metro-error")
    }
}

final class TransMiVozMetroTextoGrandeUITests: ParidadUITestCase {
    func testMetroEsAlcanzableYAuditableConElTextoMasGrande() throws {
        lanzar(categoria: "UICTContentSizeCategoryAccessibilityXXXL")
        abrirBaldosa("inicio-metro", barra: "Metro de Bogotá")
        XCTAssertTrue(elemento("metro-estado").waitForExistence(timeout: 10))
        try auditar("metro-texto-grande")
        for id in ["metro-estacion-E01", "metro-estacion-E16", "metro-linea-2", "metro-fuente-F1"] { exponer(id) }
    }
}

// MARK: - Mapa y GPS

final class TransMiVozGpsUITests: ParidadUITestCase {
    private func abrirGps() {
        abrirBaldosa("inicio-gps", barra: "Mapa y GPS")
    }

    /// Abre la pantalla y activa la ubicación (la persona lo pide).
    private func activar(_ argumentos: [String] = []) {
        lanzar(argumentos)
        abrirGps()
        exponer("gps-activar")
        elemento("gps-activar").tap()
    }

    func testLaUbicacionNoSePideAlAbrirYSeExplicaAntesDeActivar() throws {
        lanzar()
        abrirGps()
        XCTAssertTrue(elemento("gps-privacidad").waitForExistence(timeout: 10))
        XCTAssertTrue(elemento("gps-privacidad").label.contains("no la guardo ni la registro"))
        XCTAssertTrue(elemento("gps-privacidad").label.contains("no la sigo en segundo plano"))
        XCTAssertTrue(elemento("gps-activar").exists)
        XCTAssertFalse(elemento("gps-detener").exists)
        XCTAssertFalse(elemento("gps-estacion-0").exists, "sin activar no hay estaciones ni lectura")
        XCTAssertFalse(elemento("gps-estado").exists)
    }

    func testActivarMuestraLasEstacionesDelServidorConSuDistanciaYSuMapaRotulado() throws {
        activar()
        let primera = elemento("gps-estacion-0")
        XCTAssertTrue(primera.waitForExistence(timeout: 15), "no aparecieron las estaciones")
        XCTAssertTrue(primera.label.contains("Estación Ejemplo Centro"), primera.label)
        XCTAssertTrue(primera.label.contains("A 40 metros al norte"), primera.label)
        XCTAssertTrue(primera.label.contains("de frente"), "la indicación del servidor se ve: \(primera.label)")
        for indice in 0..<4 { XCTAssertTrue(elemento("gps-estacion-\(indice)").exists) }
        XCTAssertTrue(elemento("gps-mapa").exists)
        XCTAssertTrue(elemento("gps-mapa").label.contains("el mapa no se dibuja"))
        XCTAssertTrue(elemento("gps-precision").label.contains("10 metros"), elemento("gps-precision").label)
        XCTAssertTrue(elemento("gps-detener").exists)
        XCTAssertTrue(elemento("procedencia-catalogo").exists)
    }

    func testOrientarseHaciaUnaEstacionLaMarcaConTextoYNoSoloConColor() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-1").waitForExistence(timeout: 15))
        comprobarTocable("gps-orientar-1")
        XCTAssertFalse(elemento("gps-estacion-1").label.contains("Orientando"))
        elemento("gps-orientar-1").tap()
        let marcada = elemento("gps-estacion-1")
        let marca = NSPredicate(format: "label CONTAINS %@", "Orientando")
        expectation(for: marca, evaluatedWith: marcada)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(elemento("gps-estacion-0").label.contains("Orientando"))
    }

    func testAbrirEnMapasEsUnBotonPorEstacionConSuAvisoDeRutaAproximadaYSinAbrirNadaEnLasPruebas() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        for indice in 0..<4 {
            XCTAssertTrue(elemento("gps-mapas-\(indice)").exists, "falta «Abrir en Mapas» de la estación \(indice)")
            let nota = elemento("gps-nota-mapas-\(indice)")
            XCTAssertTrue(nota.exists)
            XCTAssertTrue(nota.label.contains("aproximada"), nota.label)
            XCTAssertTrue(nota.label.contains("accesibilidad del acceso no está verificada"), nota.label)
        }
        comprobarTocable("gps-mapas-0")
        XCTAssertEqual(elemento("gps-mapas-0").label, "Abrir en Mapas")
        elemento("gps-mapas-0").tap()
        let aviso = elemento("gps-mapas-aviso")
        XCTAssertTrue(aviso.waitForExistence(timeout: 10))
        XCTAssertTrue(aviso.label.contains("Abrí una ruta a pie aproximada hacia Estación Ejemplo Centro en Mapas"), aviso.label)
        XCTAssertTrue(aviso.label.contains("La accesibilidad del acceso no está verificada"), aviso.label)
        XCTAssertTrue(app.state == .runningForeground, "en las pruebas no se sale de la app para abrir Mapas")
    }

    func testElAvisoDeCercaniaEnTextoSoloSaleParaLaEstacionElegidaYSiElServidorLoMarca() throws {
        activar(["-PRUEBAS_UI_GPS_MUY_CERCA"])
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        XCTAssertFalse(elemento("gps-muy-cerca-0").exists, "sin elegir la estación no hay aviso, aunque el servidor la marque")
        comprobarTocable("gps-orientar-0")
        elemento("gps-orientar-0").tap()
        let aviso = elemento("gps-muy-cerca-0")
        XCTAssertTrue(aviso.waitForExistence(timeout: 10))
        XCTAssertTrue(aviso.label.contains("Estás muy cerca de Estación Ejemplo Centro"), aviso.label)
        XCTAssertTrue(aviso.label.contains("referencia aproximada, no un acceso verificado"), aviso.label)
        XCTAssertFalse(elemento("gps-muy-cerca-1").exists)
    }

    func testSinElIndicadorDelServidorLaEstacionElegidaNoMuestraAvisoDeCercania() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        exponer("gps-orientar-0")
        elemento("gps-orientar-0").tap()
        let marcada = NSPredicate(format: "label CONTAINS %@", "Orientando")
        expectation(for: marcada, evaluatedWith: elemento("gps-estacion-0"))
        waitForExpectations(timeout: 10)
        XCTAssertFalse(elemento("gps-muy-cerca-0").exists)
    }

    func testDetenerLaUbicacionBorraLasEstacionesYSeVuelveAPedirConElBoton() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        comprobarTocable("gps-detener")
        elemento("gps-detener").tap()
        XCTAssertTrue(elemento("gps-activar").waitForExistence(timeout: 10))
        XCTAssertFalse(elemento("gps-estacion-0").exists, "al detener no queda nada de la ubicación")
        XCTAssertFalse(elemento("gps-mapa").exists)
    }

    func testSalirDeLaPantallaLaDetieneYNoSeReanudaAlVolver() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        volverAInicio()
        abrirGps()
        XCTAssertTrue(elemento("gps-activar").waitForExistence(timeout: 10))
        XCTAssertFalse(elemento("gps-estacion-0").exists, "volver a la pantalla no vuelve a pedir la ubicación")
    }

    func testPermisoDenegadoSeExplicaOfreceAjustesYElRestoDeLaAppSigue() throws {
        activar(["-PRUEBAS_UI_GPS_PERMISO_DENEGADO"])
        let estado = elemento("gps-estado")
        XCTAssertTrue(estado.waitForExistence(timeout: 10))
        XCTAssertTrue(estado.label.contains("No diste permiso de ubicación"), estado.label)
        XCTAssertTrue(elemento("gps-abrir-ajustes").exists)
        XCTAssertTrue(elemento("gps-activar").exists, "se puede volver a intentar")
        XCTAssertFalse(elemento("gps-estacion-0").exists)
        volverAInicio()
        XCTAssertTrue(app.tabBars.buttons["Consulta"].exists)
    }

    func testPermisoRestringidoSeDiceYNoOfreceAjustes() throws {
        activar(["-PRUEBAS_UI_GPS_PERMISO_RESTRINGIDO"])
        let estado = elemento("gps-estado")
        XCTAssertTrue(estado.waitForExistence(timeout: 10))
        XCTAssertTrue(estado.label.contains("restringida"), estado.label)
        XCTAssertFalse(elemento("gps-abrir-ajustes").exists)
    }

    func testSinSenalSigueBuscandoSinInventarEstaciones() throws {
        activar(["-PRUEBAS_UI_GPS_SIN_SENAL"])
        let estado = elemento("gps-estado")
        XCTAssertTrue(estado.waitForExistence(timeout: 10))
        XCTAssertTrue(estado.label.contains("Buscando tu ubicación"), estado.label)
        XCTAssertTrue(elemento("gps-detener").exists)
        XCTAssertFalse(elemento("gps-estacion-0").exists)
    }

    func testUnaUbicacionImprecisaMuestraSuPrecisionEnTexto() throws {
        activar(["-PRUEBAS_UI_GPS_IMPRECISA"])
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        XCTAssertTrue(elemento("gps-precision").label.contains("120 metros"), elemento("gps-precision").label)
    }

    func testSinBrujulaOSinLecturaDeRumboSeDice() throws {
        activar(["-PRUEBAS_UI_GPS_SIN_BRUJULA"])
        XCTAssertTrue(elemento("gps-rumbo").waitForExistence(timeout: 10))
        XCTAssertTrue(elemento("gps-rumbo").label.contains("no tiene brújula"), elemento("gps-rumbo").label)
    }

    func testSinLecturaDeRumboVerdaderoSeDice() throws {
        activar(["-PRUEBAS_UI_GPS_SIN_RUMBO"])
        XCTAssertTrue(elemento("gps-rumbo").waitForExistence(timeout: 10))
        XCTAssertTrue(elemento("gps-rumbo").label.contains("norte verdadero"), elemento("gps-rumbo").label)
    }

    func testUnaUbicacionQueVenceDejaDePresentarseComoActual() throws {
        activar(["-PRUEBAS_UI_GPS_VENCE"]) // la lectura llega con 59,5 s y vence casi enseguida
        let estado = elemento("gps-estado")
        let vencida = NSPredicate(format: "label CONTAINS %@", "ya no está actualizada")
        expectation(for: vencida, evaluatedWith: estado)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(elemento("gps-estacion-0").exists, "las estaciones de una posición vencida no se presentan")
        XCTAssertFalse(elemento("gps-repetir").exists)
        XCTAssertTrue(elemento("gps-detener").exists, "la escucha sigue: una lectura nueva la renueva")
    }

    func testActualizarDosVecesSeguidasNoPideOtraVezYLoDice() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        comprobarTocable("gps-actualizar")
        elemento("gps-actualizar").tap()
        let estado = elemento("gps-estado")
        XCTAssertTrue(estado.waitForExistence(timeout: 10))
        XCTAssertTrue(estado.label.contains("Espera unos segundos"), estado.label)
    }

    func testUnFalloDeRedSeDiceYSeOfreceReintentar() throws {
        activar(["-PRUEBAS_UI_GPS_FALLA"])
        let error = elemento("gps-error")
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertTrue(error.label.contains("No hay conexión con el servidor"), error.label)
        comprobarTocable("gps-reintentar")
        XCTAssertFalse(elemento("gps-estacion-0").exists)
    }

    func testSinEstacionesDelServidorSeDiceHonestamente() throws {
        activar(["-PRUEBAS_UI_GPS_VACIA"])
        XCTAssertTrue(elemento("gps-sin-estaciones").waitForExistence(timeout: 15))
        XCTAssertTrue(elemento("gps-sin-estaciones").label.contains("No tengo estaciones de TransMilenio"))
    }

    func testLosControlesMidenAlMenos44Puntos() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        for id in ["gps-detener", "gps-repetir", "gps-actualizar", "gps-orientar-0", "gps-orientar-3", "gps-mapas-0", "gps-mapas-3"] {
            comprobarTocable(id)
        }
    }

    func testAuditoriaAccesibilidadGpsInactivo() throws {
        lanzar()
        abrirGps()
        XCTAssertTrue(elemento("gps-privacidad").waitForExistence(timeout: 10))
        try auditar("gps-inactivo")
    }

    func testAuditoriaAccesibilidadGpsConEstaciones() throws {
        activar()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        try auditar("gps-activo")
    }

    func testAuditoriaAccesibilidadGpsPermisoDenegado() throws {
        activar(["-PRUEBAS_UI_GPS_PERMISO_DENEGADO"])
        XCTAssertTrue(elemento("gps-estado").waitForExistence(timeout: 10))
        try auditar("gps-denegado")
    }

    func testAuditoriaAccesibilidadGpsConError() throws {
        activar(["-PRUEBAS_UI_GPS_FALLA"])
        XCTAssertTrue(elemento("gps-error").waitForExistence(timeout: 15))
        try auditar("gps-error")
    }
}

final class TransMiVozGpsTextoGrandeUITests: ParidadUITestCase {
    func testGpsEsAlcanzableYAuditableConElTextoMasGrande() throws {
        lanzar(categoria: "UICTContentSizeCategoryAccessibilityXXXL")
        abrirBaldosa("inicio-gps", barra: "Mapa y GPS")
        exponer("gps-activar")
        elemento("gps-activar").tap()
        XCTAssertTrue(elemento("gps-estacion-0").waitForExistence(timeout: 15))
        try auditar("gps-texto-grande")
        for id in ["gps-detener", "gps-repetir", "gps-orientar-0", "gps-mapas-0", "gps-orientar-3", "gps-mapas-3"] { exponer(id) }
    }
}
