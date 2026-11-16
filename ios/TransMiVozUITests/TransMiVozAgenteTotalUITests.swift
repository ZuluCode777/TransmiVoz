import XCTest

// Pruebas de interfaz del asistente de voz de «Ceguera total» (`AgenteTotalVista`), con cliente y dictado SIMULADOS y
// rotulados (`-PRUEBAS_UI_SIMULADAS`, `-PRUEBAS_UI_DICTADO_SINTETICO`): sin red, micrófono, audio ni VoiceOver real.
//
// Los ayudantes de `TransMiVozUITests.swift` son `private` a ese archivo y no se pueden reutilizar desde aquí: este archivo
// trae los suyos, con la misma auditoría completa (todos los grupos, sin filtros ni exclusiones).

/// Base: lanza la app, cambia a Ceguera total por el menú de modo (como `testElMenuDeModoCambiaElInicioYSeCierra`) y espera el
/// asistente de voz.
class AgenteTotalUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func lanzar(categoria: String = "UICTContentSizeCategoryL", extra: [String] = ["-PRUEBAS_UI_DICTADO_PERMISO_CONCEDIDO"]) throws {
        app = XCUIApplication()
        app.launchArguments += ["-PRUEBAS_UI_SIMULADAS", "-PRUEBAS_UI_DICTADO_SINTETICO"] + extra + [
            "-AppleLanguages", "(es)", "-AppleLocale", "es_CO", "-UIPreferredContentSizeCategoryName", categoria,
        ]
        app.launch()
        addTeardownBlock { [app] in app?.terminate() }
        let menu = elemento("boton-menu-modo")
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Inicio no apareció al arrancar")
        menu.tap()
        let total = elemento("modo-total")
        XCTAssertTrue(total.waitForExistence(timeout: 10), "No se abrió el menú de modo")
        total.tap()
        XCTAssertTrue(total.waitForNonExistence(timeout: 10), "El menú no se cerró al elegir Ceguera total")
        XCTAssertTrue(elemento("agente-total-microfono").waitForExistence(timeout: 10), "Ceguera total no muestra el asistente de voz")
    }

    func elemento(_ identificador: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identificador).firstMatch
    }

    func esperar(_ elemento: XCUIElement, _ predicado: String, _ valor: Any, _ mensaje: String, file: StaticString = #filePath, line: UInt = #line) {
        let espera = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicado, argumentArray: [valor]), object: elemento)
        XCTAssertEqual(XCTWaiter().wait(for: [espera], timeout: 10), .completed, mensaje, file: file, line: line)
    }

    /// Lleva el elemento a la vista, entero y tocable, deslizando la pantalla.
    func traer(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let objetivo = elemento(id)
        XCTAssertTrue(objetivo.waitForExistence(timeout: 10), "«\(id)» no existe", file: file, line: line)
        for _ in 0..<8 where !objetivo.isHittable { app.scrollViews.firstMatch.swipeUp() }
        for _ in 0..<8 where !objetivo.isHittable { app.scrollViews.firstMatch.swipeDown() }
        XCTAssertTrue(objetivo.isHittable, "«\(id)» no es tocable tras deslizar", file: file, line: line)
    }

    /// Escribe en el campo del asistente y espera a que muestre el texto completo.
    func escribir(_ texto: String, file: StaticString = #filePath, line: UInt = #line) {
        traer("agente-total-campo", file: file, line: line)
        let campo = elemento("agente-total-campo")
        campo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "El teclado no apareció", file: file, line: line)
        campo.typeText(texto)
        esperar(campo, "value == %@", texto, "El campo no muestra el texto escrito «\(texto)»", file: file, line: line)
    }

    /// Escribe y envía; enviar cierra el teclado.
    func preguntar(_ texto: String, file: StaticString = #filePath, line: UInt = #line) {
        escribir(texto, file: file, line: line)
        elemento("agente-total-enviar").tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "El teclado debe cerrarse al enviar", file: file, line: line)
    }

    func esperarEstado(_ etiqueta: String, file: StaticString = #filePath, line: UInt = #line) {
        let estado = elemento("agente-total-estado")
        XCTAssertTrue(estado.waitForExistence(timeout: 10), "No hay línea de estado", file: file, line: line)
        esperar(estado, "label == %@", etiqueta, "La línea de estado no dice «\(etiqueta)»", file: file, line: line)
    }

    /// Toca el micrófono, espera a que escuche, lo toca otra vez (termina y envía).
    func dictar(file: StaticString = #filePath, line: UInt = #line) {
        let microfono = elemento("agente-total-microfono")
        traer("agente-total-microfono", file: file, line: line)
        microfono.tap()
        esperar(microfono, "value == %@", "escuchando", "El dictado no pasó a escuchar", file: file, line: line)
        microfono.tap()
    }

    func volverAInicio(file: StaticString = #filePath, line: UInt = #line) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(elemento("agente-total-microfono").waitForExistence(timeout: 10), "No se volvió al asistente de voz", file: file, line: line)
    }
}

final class TransMiVozAgenteTotalUITests: AgenteTotalUITestCase {
    func testElAsistenteDeVozApareceEnCegueraTotalConSusControles() throws {
        try lanzar()
        let microfono = elemento("agente-total-microfono")
        XCTAssertEqual(microfono.label, "Asistente de voz")
        XCTAssertEqual(microfono.value as? String, "detenido")
        XCTAssertGreaterThanOrEqual(microfono.frame.height, 44)
        XCTAssertGreaterThanOrEqual(microfono.frame.width, 44)
        XCTAssertEqual(elemento("agente-total-estado").label, "Toca el micrófono y dime a dónde quieres ir")
        XCTAssertFalse(elemento("inicio-lupa").exists, "Ceguera total no muestra las baldosas")
        XCTAssertTrue(elemento("boton-menu-modo").exists, "la cabecera sigue en Ceguera total")
        XCTAssertFalse(elemento("agente-total-cancelar").exists, "sin nada en curso no hay qué cancelar")

        for id in ["agente-total-campo", "agente-total-enviar", "agente-total-enlace-rutas", "agente-total-enlace-frecuentes", "agente-total-enlace-gps"] {
            traer(id)
            XCTAssertGreaterThanOrEqual(elemento(id).frame.height, 44, "«\(id)» mide menos de 44 pt")
        }
        for id in ["agente-total-dictado", "agente-total-dictado-sintetico", "agente-total-privacidad-0", "agente-total-privacidad-1", "agente-total-privacidad-2"] {
            XCTAssertTrue(elemento(id).exists, "«\(id)» no existe")
        }
    }

    func testEscribirYEnviarMuestraLaRespuestaYLosPasos() throws {
        try lanzar()
        preguntar("hola")
        esperarEstado("[SIMULADO] Respuesta de prueba para: hola")
        XCTAssertEqual(elemento("agente-total-pregunta").label, "Preguntaste: “hola”")
        traer("agente-total-pasos")
        XCTAssertTrue(app.staticTexts["Paso simulado"].exists)
        XCTAssertEqual(elemento("agente-total-motor").label, "Motor: reglas")
    }

    func testDictarEnviaSoloAlTerminarYConservaElOrigenPendiente() throws {
        try lanzar()
        dictar()
        esperarEstado("[SIMULADO] Entendí que sales de Ricaurte. ¿A qué estación quieres ir?")
        XCTAssertEqual(elemento("agente-total-origen-pendiente").label, "Origen pendiente: Ricaurte")

        dictar()
        esperarEstado("[SIMULADO] Viaje de Ricaurte a Calle 72, con el origen que dijiste antes.")
        XCTAssertTrue(elemento("agente-total-origen-pendiente").waitForNonExistence(timeout: 10), "un viaje completo no deja origen pendiente")
    }

    func testOlvidarElOrigenPendienteLoBorra() throws {
        try lanzar()
        dictar()
        XCTAssertTrue(elemento("agente-total-origen-pendiente").waitForExistence(timeout: 10))
        traer("agente-total-olvidar-origen")
        elemento("agente-total-olvidar-origen").tap()
        XCTAssertTrue(elemento("agente-total-origen-pendiente").waitForNonExistence(timeout: 10))
    }

    func testUnaRespuestaConPantallaLaAbreSolaYSeVuelveAlAsistente() throws {
        try lanzar()
        preguntar("gps")
        XCTAssertTrue(app.navigationBars["Mapa y GPS"].waitForExistence(timeout: 10), "La respuesta no abrió Mapa y GPS")
        volverAInicio()
    }

    func testLasOtrasPantallasSeAbrenSinHablar() throws {
        try lanzar()
        traer("agente-total-enlace-rutas")
        elemento("agente-total-enlace-rutas").tap()
        XCTAssertTrue(elemento("campo-busqueda-rutas").waitForExistence(timeout: 10), "No se abrió la búsqueda de rutas")
        volverAInicio()

        traer("agente-total-enlace-frecuentes")
        elemento("agente-total-enlace-frecuentes").tap()
        XCTAssertTrue(app.navigationBars["Favoritas"].waitForExistence(timeout: 10), "No se abrieron las rutas frecuentes")
        volverAInicio()

        traer("agente-total-enlace-gps")
        elemento("agente-total-enlace-gps").tap()
        XCTAssertTrue(app.navigationBars["Mapa y GPS"].waitForExistence(timeout: 10), "No se abrió Mapa y GPS")
        volverAInicio()
    }

    func testCancelarUnaConsultaLentaYReintentar() throws {
        try lanzar()
        preguntar("lento")
        let cancelar = elemento("agente-total-cancelar")
        XCTAssertTrue(cancelar.waitForExistence(timeout: 10), "mientras piensa hay «Cancelar»")
        XCTAssertEqual(elemento("agente-total-microfono").value as? String, "pensando")
        cancelar.tap()
        esperarEstado("Consulta cancelada.")
        XCTAssertTrue(elemento("agente-total-reintentar").waitForExistence(timeout: 10), "tras cancelar se puede reintentar")
        XCTAssertFalse(app.staticTexts["[SIMULADO] Respuesta lenta que no debería verse."].exists)
    }

    func testUnFalloOfreceReintentarYConservaLaPregunta() throws {
        try lanzar()
        preguntar("frio")
        esperarEstado("El servidor no respondió a tiempo. El servidor puede estar arrancando. Espera unos segundos y pulsa Reintentar: tu pregunta se conserva. Si se repite, revisa la conexión.")
        traer("agente-total-reintentar")
        elemento("agente-total-reintentar").tap()
        esperarEstado("[SIMULADO] Respuesta tras reintentar.")
    }

    func testUnaPreguntaVaciaSeDiceYNoSale() throws {
        try lanzar()
        traer("agente-total-enviar")
        elemento("agente-total-enviar").tap()
        esperarEstado("Escribe una pregunta antes de enviar. Corrige el texto y vuelve a enviar.")
    }

    func testSinPermisoDelMicrofonoLoDiceYElTextoSigueDisponible() throws {
        try lanzar(extra: ["-PRUEBAS_UI_DICTADO_PERMISO_DENEGADO"])
        let microfono = elemento("agente-total-microfono")
        microfono.tap()
        esperar(microfono, "value == %@", "sin permiso", "El micrófono no dijo que falta el permiso")
        esperarEstado("Sin permiso de micrófono o de reconocimiento de voz. Escribe tu pregunta.")
        traer("agente-total-abrir-ajustes")
        preguntar("hola")
        esperarEstado("[SIMULADO] Respuesta de prueba para: hola")
    }

    // MARK: Auditoría automática de accesibilidad (falla el test si hay problemas)

    func testAuditoriaAccesibilidadEnReposoYConRespuesta() throws {
        try lanzar()
        try auditar(app, "agente-total-reposo", testCase: self)
        preguntar("hola")
        esperarEstado("[SIMULADO] Respuesta de prueba para: hola")
        try auditar(app, "agente-total-respuesta", testCase: self)
    }

    func testAuditoriaAccesibilidadEscuchando() throws {
        try lanzar()
        let microfono = elemento("agente-total-microfono")
        microfono.tap()
        esperar(microfono, "value == %@", "escuchando", "El dictado no pasó a escuchar")
        try auditar(app, "agente-total-escuchando", testCase: self)
        microfono.tap()  // suelta la captura sintética
    }

    func testAuditoriaAccesibilidadSinPermiso() throws {
        try lanzar(extra: ["-PRUEBAS_UI_DICTADO_PERMISO_DENEGADO"])
        let microfono = elemento("agente-total-microfono")
        microfono.tap()
        esperar(microfono, "value == %@", "sin permiso", "El micrófono no dijo que falta el permiso")
        XCTAssertTrue(elemento("agente-total-abrir-ajustes").waitForExistence(timeout: 10))
        try auditar(app, "agente-total-sin-permiso", testCase: self)
    }
}

/// El asistente de voz con el texto más grande de Dynamic Type de accesibilidad: lo esencial sigue a la vista y tocable, y la
/// pantalla entera pasa la auditoría.
final class TransMiVozAgenteTotalTextoGrandeUITests: AgenteTotalUITestCase {
    func testLosControlesSonAlcanzablesYLaPantallaPasaLaAuditoriaConTextoMuyGrande() throws {
        try lanzar(categoria: "UICTContentSizeCategoryAccessibilityXXXL")
        let microfono = elemento("agente-total-microfono")
        XCTAssertTrue(microfono.isHittable, "El micrófono no es tocable con el texto más grande")
        XCTAssertGreaterThanOrEqual(microfono.frame.height, 44)
        XCTAssertGreaterThanOrEqual(microfono.frame.width, 44)

        for id in ["agente-total-campo", "agente-total-enviar", "agente-total-enlace-rutas", "agente-total-enlace-frecuentes", "agente-total-enlace-gps"] {
            traer(id)
            XCTAssertGreaterThanOrEqual(elemento(id).frame.height, 44, "«\(id)» mide menos de 44 pt con el texto más grande")
        }
        for id in ["agente-total-dictado", "agente-total-privacidad-0", "agente-total-privacidad-1", "agente-total-privacidad-2"] {
            traer(id)  // cada párrafo cabe entero en la pantalla
        }

        // De arriba abajo: cada posición con la auditoría completa; lo recortado por las barras se mide entero en otra posición.
        let recorrido = RecorridoAuditado(app: app, caso: self)
        for _ in 0..<8 { app.scrollViews.firstMatch.swipeDown() }
        try recorrido.auditar("arriba")
        for paso in 1...10 {
            app.scrollViews.firstMatch.swipeUp()
            try recorrido.auditar("paso-\(paso)")
            if elemento("agente-total-privacidad-2").isHittable { break }
        }
        recorrido.cerrar()
    }

    func testElAsistenteEnReposoYRespondidoPasaLaAuditoriaConTextoMuyGrande() throws {
        try lanzar(categoria: "UICTContentSizeCategoryAccessibilityXXXL")
        preguntar("hola")
        esperarEstado("[SIMULADO] Respuesta de prueba para: hola")
        let recorrido = RecorridoAuditado(app: app, caso: self)
        for _ in 0..<8 { app.scrollViews.firstMatch.swipeDown() }
        try recorrido.auditar("respuesta-arriba")
        recorrido.cerrar()
    }
}

// MARK: Auditoría

/// Un hallazgo copiado dentro del manejador: más tarde la jerarquía ya es otra y no se vuelve a leer `problema.element`.
private struct Hallazgo {
    let descripcion: String
    let esContraste: Bool
    let identificador: String
    let etiqueta: String
    let marco: CGRect?
}

private func hallazgos(_ app: XCUIApplication, tipos: XCUIAccessibilityAuditType) throws -> [Hallazgo] {
    var lista: [Hallazgo] = []
    try app.performAccessibilityAudit(for: tipos) { problema in
        let elemento = problema.element
        lista.append(Hallazgo(
            descripcion: "[\(problema.auditType)] \(problema.compactDescription) | id=«\(elemento?.identifier ?? "")» etiqueta=«\(elemento?.label ?? "")» marco=\(elemento?.frame.debugDescription ?? "?")",
            esContraste: problema.auditType == .contrast, identificador: elemento?.identifier ?? "",
            etiqueta: elemento?.label ?? "", marco: elemento?.frame))
        return true
    }
    return lista
}

/// Los cuatro grupos que juntos son `.all`: el contraste va aparte y Dynamic Type y texto recortado también, como la
/// auditoría de las demás pantallas (cada petición nativa tiene un límite de ~25 s). Sin filtros ni exclusiones.
private let gruposDeAuditoria: [XCUIAccessibilityAuditType] = [
    .contrast, .all.subtracting([.contrast, .dynamicType, .textClipped]), .dynamicType, .textClipped,
]

/// Auditoría completa en la posición actual. Falla en el acto con cualquier problema.
private func auditar(_ app: XCUIApplication, _ contexto: String, testCase: XCTestCase, file: StaticString = #filePath, line: UInt = #line) throws {
    var problemas: [String] = []
    for tipos in gruposDeAuditoria { problemas += try hallazgos(app, tipos: tipos).map(\.descripcion) }
    guard !problemas.isEmpty else { return }
    let texto = XCTAttachment(string: problemas.joined(separator: "\n") + "\n\nJerarquía de accesibilidad:\n" + app.debugDescription)
    texto.name = "auditoria-\(contexto)-problemas"
    texto.lifetime = .keepAlways
    testCase.add(texto)
    XCTFail("Auditoría de accesibilidad (\(contexto)): \(problemas.count) problema(s):\n" + problemas.joined(separator: "\n"), file: file, line: line)
}

/// Auditoría de una pantalla que se desplaza (texto más grande). Con la pantalla en una posición, el contraste de un nodo
/// RECORTADO por la barra de navegación o la de pestañas lo mide el sistema sobre un trozo; eso se difiere: el nodo debe
/// aparecer ENTERO y sin problema en otra posición del recorrido. Todo lo demás (otro grupo, o un nodo entero a la vista)
/// falla en el acto. Si un nodo diferido nunca se midió entero y limpio, `cerrar` falla.
private final class RecorridoAuditado {
    private struct Clave: Hashable {
        let identificador: String
        let etiqueta: String
    }

    private let app: XCUIApplication
    private let caso: XCTestCase
    private var diferidos: Set<Clave> = []
    private var limpios: Set<Clave> = []

    init(app: XCUIApplication, caso: XCTestCase) {
        self.app = app
        self.caso = caso
    }

    /// Zona realmente visible: entre la barra de navegación y la de pestañas.
    private var zona: (arriba: CGFloat, abajo: CGFloat) {
        (app.navigationBars.firstMatch.frame.maxY, min(app.tabBars.firstMatch.frame.minY, app.scrollViews.firstMatch.frame.maxY))
    }

    private func entero(_ marco: CGRect, en zona: (arriba: CGFloat, abajo: CGFloat)) -> Bool {
        marco.minY >= zona.arriba && marco.maxY <= zona.abajo
    }

    private func nodos() throws -> [(clave: Clave, marco: CGRect)] {
        func recorrer(_ nodo: XCUIElementSnapshot) -> [(clave: Clave, marco: CGRect)] {
            [(Clave(identificador: nodo.identifier, etiqueta: nodo.label), nodo.frame)] + nodo.children.flatMap(recorrer)
        }
        return recorrer(try app.scrollViews.firstMatch.snapshot())
    }

    func auditar(_ contexto: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let visible = zona
        let antes = try nodos()
        var fallos: [String] = []
        var conProblema: Set<Clave> = []
        for tipos in gruposDeAuditoria {
            for hallazgo in try hallazgos(app, tipos: tipos) {
                let clave = Clave(identificador: hallazgo.identificador, etiqueta: hallazgo.etiqueta)
                conProblema.insert(clave)
                if hallazgo.esContraste, let marco = hallazgo.marco, !entero(marco, en: visible) {
                    diferidos.insert(clave)
                } else {
                    fallos.append(hallazgo.descripcion)
                }
            }
        }
        // Lo que estaba entero a la vista y no dio problema queda medido limpio.
        for (clave, marco) in antes where entero(marco, en: visible) && !conProblema.contains(clave) { limpios.insert(clave) }
        guard !fallos.isEmpty else { return }
        let texto = XCTAttachment(string: fallos.joined(separator: "\n") + "\n\nJerarquía de accesibilidad:\n" + app.debugDescription)
        texto.name = "auditoria-\(contexto)-problemas"
        texto.lifetime = .keepAlways
        caso.add(texto)
        XCTFail("Auditoría de accesibilidad (\(contexto)): \(fallos.count) problema(s):\n" + fallos.joined(separator: "\n"), file: file, line: line)
    }

    func cerrar(file: StaticString = #filePath, line: UInt = #line) {
        let sinMedir = diferidos.subtracting(limpios)
        guard !sinMedir.isEmpty else { return }
        let lista = sinMedir.map { "id=«\($0.identificador)» etiqueta=«\($0.etiqueta)»" }.sorted().joined(separator: "\n")
        XCTFail("Nodos con contraste diferido que nunca se midieron enteros y sin problema:\n" + lista, file: file, line: line)
    }
}
