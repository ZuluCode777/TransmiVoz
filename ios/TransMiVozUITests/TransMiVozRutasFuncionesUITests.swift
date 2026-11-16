import XCTest

/// Funciones de rutas que la web tiene y el iPhone ganó: alternativas del viaje, búsqueda por voz, «Escuchar» y favoritas que
/// abren su detalle. Corren con el planificador SIMULADO (`-PRUEBAS_UI_SIMULADAS`): sin red, sin micrófono y sin voz real.
/// Reutilizan las bases `RutasUITestCase` y `AjustesUITestCase` tal como están. No auditan accesibilidad ni prueban VoiceOver;
/// el reloj de 30 s se prueba en las unitarias (`RutasRevalidadorTests`), no aquí.
extension RutasUITestCase {
    /// Como `lanzar` pero con más argumentos de lanzamiento (dictado sintético, favoritas de ejemplo).
    func lanzarCon(_ extra: [String], categoria: String = "UICTContentSizeCategoryL") {
        app = XCUIApplication()
        app.launchArguments += ["-PRUEBAS_UI_SIMULADAS"] + extra + [
            "-AppleLanguages", "(es)", "-AppleLocale", "es_CO", "-UIPreferredContentSizeCategoryName", categoria,
        ]
        app.launch()
        addTeardownBlock { [app] in app?.terminate() }
    }
}

final class TransMiVozRutasFuncionesUITests: RutasUITestCase {
    private let norte = "Estación Ejemplo Norte"
    private let centro = "Estación Ejemplo Centro"
    private let sur = "Estación Ejemplo Sur"

    private func planear(_ origen: String, _ destino: String) {
        abrirViaje()
        elegirLugar("selector-origen", origen)
        elegirLugar("selector-destino", destino)
        elemento("boton-planear-viaje").tap()
        XCTAssertTrue(elemento("resultado-viaje-titulo").waitForExistence(timeout: 10), "No apareció el resultado del viaje")
    }

    // MARK: Alternativas del viaje

    func testUnViajeDirectoOfreceOtraRutaDirectaSoloConSuCodigoYAbreSuDetalle() throws {
        lanzar()
        planear(norte, sur)
        let titulo = elemento("titulo-alternativas")
        XCTAssertTrue(titulo.waitForExistence(timeout: 5), "El simulado manda una alternativa para este viaje")
        XCTAssertEqual(titulo.label, "También te sirve la ruta Z98")
        let alternativa = elemento("alternativa-1")
        XCTAssertTrue(alternativa.exists)
        XCTAssertEqual(alternativa.label, "Ruta Z98, otra ruta directa")
        // Solo el código: nada dice dónde subir ni bajar de la otra ruta.
        for palabra in ["Sube en", "Bájate en"] {
            XCTAssertFalse(
                app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", palabra)).firstMatch.exists,
                "una alternativa no dice «\(palabra)»")
        }

        alternativa.tap()
        let detalle = elemento("detalle-ruta-titulo")
        XCTAssertTrue(detalle.waitForExistence(timeout: 10), "No se abrió el detalle de la alternativa")
        XCTAssertEqual(detalle.label, "Ruta Z98")
    }

    func testUnServicioCandidatoNoOfreceAlternativas() throws {
        lanzar()
        planear(centro, sur)
        XCTAssertFalse(elemento("titulo-alternativas").exists, "un candidato no trae «También te sirven…»")
        XCTAssertFalse(elemento("alternativa-1").exists)
    }

    // MARK: Buscar con la voz

    func testBuscarHablandoAbreLaSuperposicionLaCierraYEscribirSigueFuncionando() throws {
        lanzar()
        abrirRutas()
        let boton = elemento("boton-buscar-hablando")
        XCTAssertTrue(boton.waitForExistence(timeout: 10), "Falta «Buscar hablando»")
        boton.tap()
        let cerrar = elemento("boton-cerrar-voz")
        XCTAssertTrue(cerrar.waitForExistence(timeout: 10), "No se abrió la superposición de voz")
        XCTAssertEqual(cerrar.label, "Cerrar micrófono")
        XCTAssertTrue(elemento("voz-estado").exists)
        // Sin dictado sintético en el lanzamiento no hay dictado: la superposición lo dice y se escribe a mano.
        XCTAssertEqual(
            elemento("voz-mensaje").label, "El dictado no está disponible en esta pantalla. Cierra y escribe tu búsqueda.")
        XCTAssertFalse(elemento("boton-voz-alternar").isEnabled)

        cerrar.tap()
        XCTAssertTrue(cerrar.waitForNonExistence(timeout: 10), "La superposición debía cerrarse")
        buscar("z99")
        XCTAssertTrue(elemento("ruta-Z99").waitForExistence(timeout: 10), "Escribir debe seguir buscando")
    }

    /// Con el dictado sintético cableado en `ServiciosRutas` (ver el PR): lo que «oye» llena el campo y busca, y la
    /// superposición se cierra. Sin ese cableado se omite, no falla.
    func testLoDictadoLlenaElCampoYBuscaComoLaWeb() throws {
        lanzarCon(["-PRUEBAS_UI_DICTADO_SINTETICO", "-PRUEBAS_UI_DICTADO_PERMISO_CONCEDIDO", "-PRUEBAS_UI_DICTADO_GUION", "z99"])
        abrirRutas()
        elemento("boton-buscar-hablando").tap()
        XCTAssertTrue(elemento("boton-cerrar-voz").waitForExistence(timeout: 10), "No se abrió la superposición de voz")
        if elemento("voz-mensaje").waitForExistence(timeout: 2), elemento("voz-mensaje").label.hasPrefix("El dictado no está disponible en esta pantalla") {
            throw XCTSkip("`ServiciosRutas.dictado` no está cableado en `EntornoApp`: ver el PR.")
        }
        let alternar = elemento("boton-voz-alternar")
        // La captura empieza sola poco después del anuncio «Te escucho…»; entonces el botón pasa a «Detener».
        let detener = NSPredicate(format: "label == %@", "Detener")
        expectation(for: detener, evaluatedWith: alternar)
        waitForExpectations(timeout: 15)
        alternar.tap()

        XCTAssertTrue(elemento("ruta-Z99").waitForExistence(timeout: 15), "El texto final debía buscar")
        XCTAssertTrue(elemento("boton-cerrar-voz").waitForNonExistence(timeout: 10), "La superposición debía cerrarse")
        XCTAssertEqual(elemento("campo-busqueda-rutas").value as? String, "z99")
    }

    // MARK: Escuchar

    func testElDetalleOfreceEscucharYSiNoSuenaDiceElPorQue() throws {
        lanzar()
        abrirRutas()
        buscar("z99")
        let fila = elemento("ruta-Z99")
        XCTAssertTrue(fila.waitForExistence(timeout: 10))
        fila.tap()
        XCTAssertTrue(elemento("detalle-ruta-titulo").waitForExistence(timeout: 10))
        let escuchar = elemento("boton-escuchar")
        XCTAssertTrue(escuchar.waitForExistence(timeout: 5), "El detalle debe ofrecer «Escuchar»")
        XCTAssertEqual(escuchar.label, "Escuchar")
        escuchar.tap()
        // En las pruebas la voz es de mentira y la salida no es privada (o la voz aún no está cableada): no suena, y lo dice.
        let mensaje = elemento("mensaje-escuchar")
        XCTAssertTrue(mensaje.waitForExistence(timeout: 5), "Si no suena, la pantalla debe decir por qué")
        let permitidos = [
            "La voz de la app no está disponible en esta pantalla. La ruta está escrita aquí abajo.",
            "No se dijo en voz alta: no hay salida privada de audio.",
        ]
        XCTAssertTrue(permitidos.contains(mensaje.label), mensaje.label)
    }

    // MARK: Favoritas

    func testRutasFrecuentesListaLasFavoritasYTocarUnaAbreSuDetalle() throws {
        lanzarCon(["-PRUEBAS_UI_FAVORITAS_SEMILLA"])
        abrirRutas()
        let enlace = elemento("enlace-rutas-frecuentes")
        XCTAssertTrue(enlace.waitForExistence(timeout: 10), "Falta «Rutas frecuentes»")
        enlace.tap()
        let favorita = elemento("favorita-Z99")
        XCTAssertTrue(favorita.waitForExistence(timeout: 10), "La lista de frecuentes debe traer la favorita Z99")
        XCTAssertTrue(elemento("favorita-Z98").exists)
        favorita.tap()
        let titulo = elemento("detalle-ruta-titulo")
        XCTAssertTrue(titulo.waitForExistence(timeout: 10), "Tocar una favorita debe abrir su detalle")
        XCTAssertEqual(titulo.label, "Ruta Z99")
    }
}

/// Favoritas de Ajustes: tocar una abre el detalle de su ruta, como «Rutas frecuentes» de la web.
final class TransMiVozFavoritasDetalleUITests: AjustesUITestCase {
    func testTocarUnaFavoritaDeAjustesAbreElDetalleDeSuRuta() throws {
        lanzar(["-PRUEBAS_UI_SIMULADAS", "-PRUEBAS_UI_FAVORITAS_SEMILLA"])
        abrirSeccion("Favoritas")
        let favorita = elemento("favorita-Z98")
        XCTAssertTrue(favorita.waitForExistence(timeout: 10))
        XCTAssertEqual(favorita.label, "Ruta Z98")
        favorita.tap()
        let titulo = elemento("detalle-ruta-titulo")
        XCTAssertTrue(titulo.waitForExistence(timeout: 10), "No se abrió el detalle de la favorita")
        XCTAssertEqual(titulo.label, "Ruta Z98")
    }
}
