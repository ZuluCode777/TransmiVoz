import XCTest

// Pruebas de interfaz de Emergencia y Diagnóstico, en el Simulator y sin red. Demuestran la interfaz con entradas simuladas:
// las cinco pruebas de sistema del diagnóstico son sintéticas y rotuladas «[SIMULADO]»; el servidor, el asistente y el
// planificador usan los clientes reales, que sin dirección configurada responden «falta la dirección» sin tocar la red. No
// prueban llamadas, voz, permisos, Bluetooth ni VoiceOver reales.
//
// Los ayudantes de `TransMiVozUITests.swift` (`exponer`, `FaseAuditada`, `auditar`…) son `private` de ese archivo y no se
// cambian. Aquí se repite lo mínimo, con las mismas reglas: los cuatro grupos de la auditoría nativa de siempre, sin
// ignorar ni excluir nada; solo el contraste de un nodo con identificador único, recortado por una barra y que cabría
// entero se difiere, y esa deuda obliga a medir el mismo nodo entero a la vista (`LibroContraste`, el de las demás
// pruebas). Cualquier otro hallazgo es un fallo en el acto. Si algún día los ayudantes se hacen compartidos, estas copias sobran.

// MARK: Ayudantes

private func esperar(_ elemento: XCUIElement, _ predicado: String, _ valor: Any, _ mensaje: String, file: StaticString = #filePath, line: UInt = #line) {
    let espera = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicado, argumentArray: [valor]), object: elemento)
    XCTAssertEqual(XCTWaiter().wait(for: [espera], timeout: 10), .completed, mensaje, file: file, line: line)
}

/// Zona realmente visible: entre la barra de navegación y la de pestañas, dentro del área desplazable.
private func zonaVisible(_ app: XCUIApplication) -> (arriba: CGFloat, abajo: CGFloat) {
    let contenido = app.scrollViews.firstMatch.frame
    return (max(app.navigationBars.firstMatch.frame.maxY, contenido.minY), min(app.tabBars.firstMatch.frame.minY, contenido.maxY))
}

/// Arrastra el contenido `desplazamiento` puntos (positivo = hacia delante), lejos del indicador del borde derecho.
private func arrastrar(_ desplazamiento: CGFloat, en app: XCUIApplication, velocidad: XCUIGestureVelocity) {
    let (arriba, abajo) = zonaVisible(app)
    let ventana = app.windows.firstMatch.frame
    let inicio = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: ventana.width / 2, dy: desplazamiento > 0 ? abajo - 20 : arriba + 20))
    // Mantener el dedo quieto antes de soltar evita añadir inercia al arrastre.
    inicio.press(
        forDuration: 0.1, thenDragTo: inicio.withOffset(CGVector(dx: 0, dy: -desplazamiento)),
        withVelocity: velocidad, thenHoldForDuration: 0.5)
}

/// Lleva el elemento entero y tocable entre las barras (centrado, para dejar margen a ambos lados). Si el elemento no cabe
/// o no existe, la prueba falla con su marco: nunca se da por hecho que quedó a la vista.
private func traerAVista(
    _ identificador: String, etiqueta: String? = nil, en app: XCUIApplication, velocidad: XCUIGestureVelocity = .default,
    file: StaticString = #filePath, line: UInt = #line
) {
    var consulta = app.descendants(matching: .any).matching(identifier: identificador)
    if let etiqueta { consulta = consulta.matching(NSPredicate(format: "label == %@", etiqueta)) }
    let objetivo = consulta.firstMatch
    func visible() -> Bool {
        guard objetivo.exists else { return false }
        let (arriba, abajo) = zonaVisible(app)
        let marco = objetivo.frame
        return marco.minY >= arriba && marco.maxY <= abajo && objetivo.isHittable
    }
    for _ in 0..<12 where !visible() {
        let (arriba, abajo) = zonaVisible(app)
        let paso = abajo - arriba - 40
        let desplazamiento: CGFloat = objetivo.exists ? max(-paso, min(paso, objetivo.frame.midY - (arriba + abajo) / 2)) : paso
        arrastrar(desplazamiento, en: app, velocidad: velocidad)
    }
    let (arriba, abajo) = zonaVisible(app)
    XCTAssertTrue(visible(), "«\(identificador)» no queda entero y tocable entre las barras: marco \(objetivo.exists ? "\(objetivo.frame)" : "fuera de la jerarquía visible"), visible \(arriba)…\(abajo)", file: file, line: line)
}

private struct ResultadoAuditoriaPropio {
    var hallazgos: [HallazgoAuditoria] = []
    var antesDelContraste: ObservacionContraste?
    var despuesDelContraste: ObservacionContraste?
}

/// TODOS los grupos de la auditoría nativa (los mismos cuatro de siempre, sin filtros ni exclusiones). Cada problema se copia
/// COMO VALOR dentro del manejador. El contraste va primero y se observa la jerarquía justo antes y justo después.
private func ejecutarAuditoria(_ app: XCUIApplication, _ contexto: String, observar: () throws -> ObservacionContraste) throws -> ResultadoAuditoriaPropio {
    var resultado = ResultadoAuditoriaPropio()
    let auditorias: [XCUIAccessibilityAuditType] = [
        .contrast, .all.subtracting([.contrast, .dynamicType, .textClipped]), .dynamicType, .textClipped,
    ]
    for tipos in auditorias {
        let esContraste = tipos == .contrast
        if esContraste { resultado.antesDelContraste = try observar() }
        try XCTContext.runActivity(named: "Auditoría \(contexto): \(tipos)") { _ in
            try app.performAccessibilityAudit(for: tipos) { problema in
                let elemento = problema.element
                resultado.hallazgos.append(HallazgoAuditoria(
                    tipo: "\(problema.auditType)", esContraste: problema.auditType == .contrast,
                    compacta: problema.compactDescription, detallada: problema.detailedDescription,
                    identificador: elemento?.identifier, etiqueta: elemento?.label, marco: elemento?.frame))
                return true
            }
        }
        if esContraste { resultado.despuesDelContraste = try observar() }
    }
    return resultado
}

/// Una fase estable de la pantalla (mismo estado y mismas etiquetas): audita con todos los grupos en cada posición que se le
/// pide y, al cerrar, mide entero a la vista cada nodo cuyo contraste se difirió. Los fallos se acumulan hasta `cerrar`.
private final class AuditoriaFase {
    private let app: XCUIApplication
    private let caso: XCTestCase
    private let velocidad: XCUIGestureVelocity
    private var libro: LibroContraste

    init(_ fase: String, app: XCUIApplication, caso: XCTestCase, velocidad: XCUIGestureVelocity = .default) {
        self.app = app
        self.caso = caso
        self.velocidad = velocidad
        libro = LibroContraste(fase: fase)
    }

    private func observar() throws -> ObservacionContraste {
        let contenido = app.scrollViews.firstMatch.frame
        let zona = try nodos(de: app.scrollViews.firstMatch)
        let aplicacion = try nodos(de: app)
        let vista = VistaAuditada(
            arriba: max(app.navigationBars.firstMatch.frame.maxY, contenido.minY),
            abajo: min(app.tabBars.firstMatch.frame.minY, contenido.maxY))
        return ObservacionContraste(vista: vista, zona: zona, aplicacion: aplicacion)
    }

    private func nodos(de elemento: XCUIElement) throws -> [NodoJerarquia] {
        func recorrer(_ nodo: XCUIElementSnapshot) -> [NodoJerarquia] {
            [NodoJerarquia(identificador: nodo.identifier, etiqueta: nodo.label, marco: nodo.frame)]
                + nodo.children.flatMap(recorrer)
        }
        return recorrer(try elemento.snapshot())
    }

    private func adjuntar(_ nombre: String, _ texto: String) {
        let adjunto = XCTAttachment(string: texto)
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        caso.add(adjunto)
    }

    /// Lleva el elemento a la vista, a la velocidad de la fase.
    func exponer(_ identificador: String, etiqueta: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        traerAVista(identificador, etiqueta: etiqueta, en: app, velocidad: velocidad, file: file, line: line)
    }

    /// Una auditoría completa en la posición actual. Si la maquetación cambió mientras se medía el contraste, no se
    /// clasifica ni se acredita nada de esa auditoría y la fase falla.
    func auditar(_ contexto: String) throws {
        let resultado = try ejecutarAuditoria(app, contexto, observar: observar)
        guard let antes = resultado.antesDelContraste, let despues = resultado.despuesDelContraste else {
            XCTFail("La auditoría «\(contexto)» no obtuvo las observaciones del contraste")
            return
        }
        if let motivo = ObservacionContraste.deriva(antes: antes, despues: despues) {
            libro.registrarDeriva(contexto: contexto, motivo: motivo, nodos: despues.zona.count)
            adjuntar("auditoria-\(libro.fase)-\(contexto)-problemas", "Deriva de maquetación: \(motivo)\n" + resultado.hallazgos.map(\.descripcion).joined(separator: "\n"))
            return
        }
        let lineas = libro.registrar(
            contexto: contexto, hallazgos: resultado.hallazgos, zona: despues.zona, aplicacion: despues.aplicacion, vista: despues.vista)
        adjuntar("auditoria-\(libro.fase)-\(contexto)-problemas",
            "Zona visible: \(despues.vista.arriba)…\(despues.vista.abajo)\n" + (lineas.isEmpty ? "Sin problemas." : lineas.joined(separator: "\n")))
    }

    /// Remedición obligatoria: cada deuda se lleva entera a la vista y se vuelve a auditar con todos los grupos. Si queda
    /// alguna sin saldar, o el trabajo se agota, la fase falla. Al final, un solo fallo con todos los problemas.
    func cerrar(file: StaticString = #filePath, line: UInt = #line) throws {
        var vueltas = 0
        while let clave = libro.pendientes.first {
            guard vueltas < libro.nodosMaximos else {
                for pendiente in libro.pendientes {
                    libro.darPorFallida(pendiente, motivo: "se agotaron las remediciones (una por nodo de la fase: \(libro.nodosMaximos))")
                }
                break
            }
            vueltas += 1
            exponer(clave.identificador, etiqueta: clave.etiqueta, file: file, line: line)
            try auditar("remedicion-\(vueltas)-\(clave.identificador)")
            if libro.pendientes.contains(clave) {
                libro.darPorFallida(clave, motivo: "entero a la vista no quedó medido sin problema")
            }
        }
        adjuntar("auditoria-\(libro.fase)-cobertura", libro.informe())
        guard !libro.fallos.isEmpty else { return }
        adjuntar("auditoria-\(libro.fase)-jerarquia", app.debugDescription)
        let captura = XCTAttachment(screenshot: app.screenshot())
        captura.name = "auditoria-\(libro.fase)-pantalla"
        captura.lifetime = .keepAlways
        caso.add(captura)
        XCTFail("Auditoría de accesibilidad (fase «\(libro.fase)»): \(libro.fallos.count) problema(s):\n" + libro.fallos.joined(separator: "\n"), file: file, line: line)
    }
}

// MARK: Emergencia

/// La pantalla Emergencia (`components/assistance.tsx`) abierta desde la baldosa de Inicio. No se toca ningún enlace de
/// llamada: abrir el marcador saca a la app de primer plano.
class EmergenciaUITestCase: AjustesUITestCase {
    /// Las líneas, en el orden de la web: identificador y etiqueta de accesibilidad.
    let lineas: [(id: String, etiqueta: String)] = [
        ("emergencia-llamar-123", "Llamar al 123. Emergencias."),
        ("emergencia-llamar-156", "Policía de TransMilenio. Número 156."),
        ("emergencia-llamar-195", "Atención al usuario TransMilenio. Número 195."),
    ]

    func abrirEmergencia(categoria: String, file: StaticString = #filePath, line: UInt = #line) {
        lanzar(["-PRUEBAS_UI_SIMULADAS"], categoria: categoria)
        XCTAssertTrue(elemento("inicio-titulo").waitForExistence(timeout: 10), "Inicio no apareció al arrancar", file: file, line: line)
        traerAVista("inicio-emergencia", en: app, velocidad: categoria.contains("Accessibility") ? .slow : .default, file: file, line: line)
        elemento("inicio-emergencia").tap()
        XCTAssertTrue(app.navigationBars["Emergencia"].waitForExistence(timeout: 10), "No se abrió «Emergencia»", file: file, line: line)
        XCTAssertTrue(elemento("emergencia-llamar-123").waitForExistence(timeout: 10), "Falta el botón rojo «Llamar al 123»", file: file, line: line)
    }
}

final class TransMiVozEmergenciaUITests: EmergenciaUITestCase {
    func testEmergenciaTieneElBotonRojoYLasOtrasLineasDeLaWeb() throws {
        abrirEmergencia(categoria: "UICTContentSizeCategoryL")
        let titulo = app.descendants(matching: .any).matching(identifier: "emergencia-encabezado")
            .matching(NSPredicate(format: "label == %@", "Emergencia")).firstMatch
        XCTAssertTrue(titulo.exists, "Falta la banda de título «Emergencia»")
        XCTAssertEqual(elemento("emergencia-llamar-123-titulo").label, "Llamar al 123")
        XCTAssertEqual(elemento("emergencia-llamar-123-nota").label, "Emergencias")
        XCTAssertEqual(elemento("emergencia-otras-lineas").label, "Otras líneas")
        for (id, etiqueta) in lineas {
            let linea = elemento(id)
            XCTAssertTrue(linea.waitForExistence(timeout: 10), "Falta «\(id)»")
            XCTAssertEqual(linea.label, etiqueta)
            XCTAssertGreaterThanOrEqual(linea.frame.height, 44, "«\(id)» mide menos de 44 pt de alto")
            XCTAssertGreaterThanOrEqual(linea.frame.width, 44, "«\(id)» mide menos de 44 pt de ancho")
        }
        // Una frase por párrafo y el orden de la web: el rojo primero, luego «Otras líneas» y sus dos números.
        XCTAssertEqual(elemento("emergencia-aclaracion").label, "Cada botón abre el marcador del iPhone con el número escrito.")
        XCTAssertEqual(elemento("emergencia-aclaracion-1").label, "La llamada no se hace sola: tú la confirmas.")
        let posiciones = lineas.map { elemento($0.id).frame.minY }
        XCTAssertEqual(posiciones, posiciones.sorted(), "las líneas van en el orden de la web: 123, 156, 195")
        XCTAssertLessThan(elemento("emergencia-llamar-123").frame.minY, elemento("emergencia-otras-lineas").frame.minY)
    }

    /// Texto equivalente al audio (`especificacion-accesibilidad.md` §5): lo que dice la voz está en «La app dijo», con
    /// «Repetir». En el Simulator no hay salida privada: la voz no suena y la pantalla lo dice con palabras, también al repetir.
    func testLaAppDijoMuestraLaIntroduccionYRepetirExplicaPorQueNoSeOye() throws {
        abrirEmergencia(categoria: "UICTContentSizeCategoryL")
        traerAVista("emergencia-repetir", en: app)
        XCTAssertEqual(elemento("emergencia-app-dijo").label, "La app dijo")
        XCTAssertEqual(elemento("emergencia-app-dijo-texto").label, "Emergencia. Toca el botón rojo para llamar a la línea 123.")
        let repetir = elemento("emergencia-repetir")
        XCTAssertEqual(repetir.label, "Repetir lo que dijo la app")
        XCTAssertGreaterThanOrEqual(repetir.frame.height, 44, "«Repetir» mide menos de 44 pt de alto")
        let sinSalida = "No se dijo en voz alta: no hay salida privada de audio."
        XCTAssertTrue(elemento("emergencia-app-dijo-resultado").waitForExistence(timeout: 10))
        XCTAssertEqual(elemento("emergencia-app-dijo-resultado").label, sinSalida, "al abrir, dice por qué no sonó")
        repetir.tap()
        esperar(elemento("emergencia-app-dijo-resultado"), "label == %@", sinSalida, "«Repetir» no dejó el motivo en pantalla")
    }

    func testEmergenciaVuelveAInicioConElBotonAtras() throws {
        abrirEmergencia(categoria: "UICTContentSizeCategoryL")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(elemento("inicio-titulo").waitForExistence(timeout: 10), "No se volvió a Inicio")
    }

    func testAuditoriaAccesibilidadEmergencia() throws {
        abrirEmergencia(categoria: "UICTContentSizeCategoryL")
        let fase = AuditoriaFase("emergencia", app: app, caso: self)
        fase.exponer("emergencia-encabezado", etiqueta: "Emergencia")
        try fase.auditar("emergencia-arriba")
        fase.exponer("emergencia-repetir")
        try fase.auditar("emergencia-abajo")
        try fase.cerrar()
    }
}

/// Emergencia con el texto más grande de Dynamic Type de accesibilidad: cada línea llega entera y tocable, y se audita de
/// arriba abajo. Nada de esto prueba VoiceOver real.
final class TransMiVozEmergenciaTextoGrandeUITests: EmergenciaUITestCase {
    func testEmergenciaLlegaEnteraConTextoMuyGrande() throws {
        abrirEmergencia(categoria: "UICTContentSizeCategoryAccessibilityXXXL")
        let fase = AuditoriaFase("emergencia-texto-muy-grande", app: app, caso: self, velocidad: .slow)
        for (id, etiqueta) in lineas {
            fase.exponer(id, etiqueta: etiqueta)
            XCTAssertGreaterThanOrEqual(elemento(id).frame.height, 44, "«\(id)» mide menos de 44 pt de alto")
        }
        fase.exponer("emergencia-llamar-123", etiqueta: "Llamar al 123. Emergencias.")
        try fase.auditar("texto-muy-grande-Emergencia-123")
        fase.exponer("emergencia-llamar-195", etiqueta: "Atención al usuario TransMilenio. Número 195.")
        try fase.auditar("texto-muy-grande-Emergencia-195")
        fase.exponer("emergencia-repetir")
        try fase.auditar("texto-muy-grande-Emergencia-repetir")
        try fase.cerrar()
    }
}

// MARK: Diagnóstico

/// El diagnóstico abierto desde el menú «Más ajustes» de Ajustes.
class DiagnosticoUITestCase: AjustesUITestCase {
    let pruebas = ["servidor", "asistente", "planificador", "voz", "reconocimiento", "microfono", "camara", "bluetooth"]
    let titulos = [
        "servidor": "Servidor", "asistente": "Asistente", "planificador": "Rutas y viaje", "voz": "Voz de la app", "reconocimiento": "Reconocimiento de voz",
        "microfono": "Micrófono", "camara": "Cámara", "bluetooth": "Bluetooth",
    ]

    func abrirDiagnostico(categoria: String, file: StaticString = #filePath, line: UInt = #line) {
        lanzar(["-PRUEBAS_UI_SIMULADAS"], categoria: categoria)
        abrirSeccion("Diagnóstico", file: file, line: line)
        XCTAssertTrue(app.navigationBars["Diagnóstico"].waitForExistence(timeout: 10), "No se abrió «Diagnóstico»", file: file, line: line)
        XCTAssertTrue(elemento("diagnostico-probar-todo").waitForExistence(timeout: 10), "Falta «Probar todo»", file: file, line: line)
    }

    /// «Probar todo» hasta que la última fila (Bluetooth) tiene resultado. Cada resultado empieza por su estado en palabras.
    func probarTodoYEsperar(velocidad: XCUIGestureVelocity = .default, file: StaticString = #filePath, line: UInt = #line) {
        traerAVista("diagnostico-probar-todo", en: app, velocidad: velocidad, file: file, line: line)
        elemento("diagnostico-probar-todo").tap()
        let ultimo = elemento("diagnostico-resultado-bluetooth")
        XCTAssertTrue(ultimo.waitForExistence(timeout: 10), file: file, line: line)
        esperar(ultimo, "label BEGINSWITH %@", "Correcto: ", "«Probar todo» no terminó: la última prueba sigue en «\(ultimo.label)»", file: file, line: line)
    }
}

final class TransMiVozDiagnosticoUITests: DiagnosticoUITestCase {
    func testDiagnosticoSeAbreDesdeAjustesConSusOchoPruebasSinProbar() throws {
        abrirDiagnostico(categoria: "UICTContentSizeCategoryL")
        XCTAssertEqual(elemento("diagnostico-resumen").label, "0 de 8 correctas")
        for prueba in pruebas {
            XCTAssertEqual(elemento("diagnostico-titulo-\(prueba)").label, titulos[prueba], "falta la prueba «\(prueba)»")
            XCTAssertEqual(elemento("diagnostico-resultado-\(prueba)").label, "Sin probar", "nada se da por probado antes de correr")
            XCTAssertFalse(elemento("diagnostico-demuestra-\(prueba)").label.isEmpty)
            XCTAssertTrue(elemento("diagnostico-probar-\(prueba)").exists, "falta «Probar» de «\(prueba)»")
        }
        XCTAssertEqual(elemento("diagnostico-probar-servidor").label, "Probar: Servidor")
    }

    func testProbarTodoDiceConPalabrasComoTerminoCadaPrueba() throws {
        abrirDiagnostico(categoria: "UICTContentSizeCategoryL")
        probarTodoYEsperar()
        let esperado: [String: String] = [
            // Clientes reales sin dirección configurada: no hay servidor que probar, y no es un servidor caído ni un éxito.
            "servidor": "Atención: Falta la dirección del servidor.",
            "asistente": "Atención: Falta la dirección del servidor.",
            "planificador": "Atención: Falta la dirección del servidor.",
            // Sondas sintéticas rotuladas, una de cada estado.
            "voz": "Atención: ",
            "reconocimiento": "Atención: ",
            "microfono": "Correcto: ",
            "camara": "Falló: ",
            "bluetooth": "Correcto: ",
        ]
        for prueba in pruebas {
            let resultado = elemento("diagnostico-resultado-\(prueba)")
            XCTAssertTrue(resultado.label.hasPrefix(esperado[prueba] ?? "?"), "«\(prueba)»: «\(resultado.label)»")
            XCTAssertFalse(["Sin probar", "Probando…"].contains(resultado.label), "«\(prueba)» no terminó")
        }
        for prueba in ["voz", "microfono", "camara", "bluetooth"] {
            XCTAssertTrue(elemento("diagnostico-resultado-\(prueba)").label.contains("[SIMULADO]"), "la sonda sintética de «\(prueba)» se rotula")
        }
        // Solo las correctas se cuentan: micrófono y Bluetooth.
        XCTAssertEqual(elemento("diagnostico-resumen").label, "2 de 8 correctas")
        // Nada que parezca una clave, una dirección o un encabezado de autorización.
        for prueba in pruebas {
            let texto = elemento("diagnostico-resultado-\(prueba)").label
            for prohibido in ["Basic ", "Authorization", "https://"] { XCTAssertFalse(texto.contains(prohibido), "«\(prueba)» muestra «\(prohibido)»") }
        }
    }

    func testProbarUnaPruebaSoloCambiaSuFila() throws {
        abrirDiagnostico(categoria: "UICTContentSizeCategoryL")
        traerAVista("diagnostico-probar-microfono", en: app)
        elemento("diagnostico-probar-microfono").tap()
        esperar(elemento("diagnostico-resultado-microfono"), "label BEGINSWITH %@", "Correcto: ", "La prueba del micrófono no terminó")
        XCTAssertEqual(elemento("diagnostico-resultado-voz").label, "Sin probar")
        XCTAssertEqual(elemento("diagnostico-resumen").label, "1 de 8 correctas")
    }

    func testAuditoriaAccesibilidadDiagnostico() throws {
        abrirDiagnostico(categoria: "UICTContentSizeCategoryL")
        probarTodoYEsperar()
        let fase = AuditoriaFase("diagnostico", app: app, caso: self)
        fase.exponer("diagnostico-titulo-servidor", etiqueta: "Servidor")
        try fase.auditar("diagnostico-arriba")
        fase.exponer("diagnostico-resultado-camara")
        try fase.auditar("diagnostico-medio")
        fase.exponer("diagnostico-probar-bluetooth")
        try fase.auditar("diagnostico-abajo")
        try fase.cerrar()
    }
}

/// El diagnóstico con el texto más grande de Dynamic Type de accesibilidad: cada prueba llega entera y se audita en tres
/// posiciones. Nada de esto prueba VoiceOver real.
final class TransMiVozDiagnosticoTextoGrandeUITests: DiagnosticoUITestCase {
    func testDiagnosticoLlegaEnteroConTextoMuyGrande() throws {
        abrirDiagnostico(categoria: "UICTContentSizeCategoryAccessibilityXXXL")
        probarTodoYEsperar(velocidad: .slow)
        let fase = AuditoriaFase("diagnostico-texto-muy-grande", app: app, caso: self, velocidad: .slow)
        for prueba in pruebas {
            fase.exponer("diagnostico-probar-\(prueba)")
            XCTAssertGreaterThanOrEqual(elemento("diagnostico-probar-\(prueba)").frame.height, 44, "«Probar» de «\(prueba)» mide menos de 44 pt")
        }
        fase.exponer("diagnostico-titulo-servidor", etiqueta: "Servidor")
        try fase.auditar("texto-muy-grande-Diagnostico-arriba")
        fase.exponer("diagnostico-resultado-camara")
        try fase.auditar("texto-muy-grande-Diagnostico-medio")
        fase.exponer("diagnostico-probar-bluetooth")
        try fase.auditar("texto-muy-grande-Diagnostico-abajo")
        try fase.cerrar()
    }
}
