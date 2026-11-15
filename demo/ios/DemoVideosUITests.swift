import XCTest

// Recorridos de DEMOSTRACIÓN para grabar el Simulator. No son pruebas: no auditan ni cubren casos, solo manejan la app
// a ritmo de persona y anotan qué se hace y qué aparece en pantalla, para los subtítulos del video.
//
// No forma parte de la suite del repositorio: `demo/ios/grabar.sh` copia este archivo a `ios/TransMiVozUITests/` en el
// runner, justo antes de compilar (el grupo sincronizado del proyecto lo incluye solo), y graba cada recorrido con
// `xcrun simctl io … recordVideo`.
//
// Variables (el script las pasa con el prefijo TEST_RUNNER_):
//   DEMO_EVENTOS  archivo donde se anotan los subtítulos (una línea JSON por evento, con la hora de reloj)
//   DEMO_ORIGEN   origen HTTPS del backend Next.js arrancado en el runner (por defecto https://localhost:8443)
//   DEMO_CLAVE    clave de ese backend (APP_PASSWORD)
//   DEMO_CATEGORIA_TEXTO  tamaño de letra de la app (por defecto, el 2.º tamaño de accesibilidad); el script pone el
//                 mismo en todo el Simulator, junto con el contraste aumentado, como lo tendría una persona con baja visión
//   DEMO_ID       identificador del video (iphone-01-…): da nombre a las capturas
//   DEMO_CAPTURAS carpeta donde se guardan las capturas de pantalla (PNG) de los momentos clave

private let entorno = ProcessInfo.processInfo.environment
private let origenServidor = entorno["DEMO_ORIGEN"] ?? "https://localhost:8443"
private let claveServidor = entorno["DEMO_CLAVE"] ?? ""
private let categoriaTexto = entorno["DEMO_CATEGORIA_TEXTO"] ?? "UICTContentSizeCategoryAccessibilityL"
private let idVideo = entorno["DEMO_ID"] ?? "iphone"
private let carpetaCapturas = entorno["DEMO_CAPTURAS"] ?? ""

final class DemoVideosUITests: XCTestCase {
    private var app: XCUIApplication!
    private var capturas = 0

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Subtítulos

    /// Una línea por evento: `{"epoch": …, "tipo": …, "texto": …}`. También va al registro de xcodebuild, por si el
    /// archivo no se puede escribir desde el Simulator.
    private func anotar(_ tipo: String, _ texto: String = "") {
        let evento: [String: Any] = ["epoch": Date().timeIntervalSince1970, "tipo": tipo, "texto": texto]
        guard let datos = try? JSONSerialization.data(withJSONObject: evento),
              let linea = String(data: datos, encoding: .utf8) else { return }
        print("DEMO_EVENTO \(linea)")
        guard let ruta = entorno["DEMO_EVENTOS"], !ruta.isEmpty else { return }
        let url = URL(fileURLWithPath: ruta)
        if !FileManager.default.fileExists(atPath: ruta) {
            FileManager.default.createFile(atPath: ruta, contents: nil)
        }
        if let archivo = try? FileHandle(forWritingTo: url) {
            archivo.seekToEndOfFile()
            archivo.write(Data((linea + "\n").utf8))
            try? archivo.close()
        }
    }

    private func accion(_ texto: String) { anotar("accion", texto) }
    private func nota(_ texto: String) { anotar("nota", texto) }
    private func pantalla(_ texto: String) { anotar("pantalla", texto) }

    private func pausa(_ segundos: TimeInterval) { Thread.sleep(forTimeInterval: segundos) }

    /// Guarda una captura de la pantalla del iPhone (PNG, a la resolución del Simulator) para usarla como foto. Va también
    /// como adjunto del resultado de xcodebuild, por si el Simulator no deja escribir en la carpeta.
    private func captura(_ nombre: String) {
        capturas += 1
        let imagen = XCUIScreen.main.screenshot()
        let archivo = "\(idVideo)-\(String(format: "%02d", capturas))-\(nombre)"
        let adjunto = XCTAttachment(screenshot: imagen)
        adjunto.name = archivo
        adjunto.lifetime = .keepAlways
        add(adjunto)
        guard !carpetaCapturas.isEmpty else { return }
        let carpeta = URL(fileURLWithPath: carpetaCapturas, isDirectory: true)
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try? imagen.pngRepresentation.write(to: carpeta.appendingPathComponent("\(archivo).png"))
    }

    // MARK: Ayudas

    private func lanzar(_ argumentos: [String], titulo: String) {
        anotar("titulo", titulo)
        app = XCUIApplication()
        app.launchArguments += argumentos + [
            "-AppleLanguages", "(es)", "-AppleLocale", "es_CO", "-UIPreferredContentSizeCategoryName", categoriaTexto,
        ]
        app.launch()
        addTeardownBlock { [app] in app?.terminate() }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "La app no mostró sus pestañas")
        pausa(1.2)
        anotar("inicio")
    }

    private func terminar() {
        pausa(2.0)
        anotar("fin")
    }

    private func elemento(_ identificador: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identificador).firstMatch
    }

    private func etiquetado(_ texto: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", texto)).firstMatch
    }

    private func esperar(_ elemento: XCUIElement, _ predicado: String, _ valor: Any, _ mensaje: String, timeout: TimeInterval = 15) {
        let espera = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicado, argumentArray: [valor]), object: elemento)
        XCTAssertEqual(XCTWaiter().wait(for: [espera], timeout: timeout), .completed, mensaje)
    }

    private func tocar(_ el: XCUIElement, _ descripcion: String) {
        XCTAssertTrue(el.waitForExistence(timeout: 15), "No apareció: \(descripcion)")
        accion(descripcion)
        pausa(0.7)
        el.tap()
        pausa(0.8)
    }

    private func abrirPestana(_ nombre: String, esperarSeleccion: Bool = true) {
        let pestana = app.tabBars.buttons[nombre]
        XCTAssertTrue(pestana.waitForExistence(timeout: 15), "No existe la pestaña \(nombre)")
        if pestana.isSelected { return }
        tocar(pestana, "Toca la pestaña «\(nombre)»")
        if esperarSeleccion { esperar(pestana, "isSelected == %@", true, "No se seleccionó la pestaña \(nombre)") }
    }

    /// Escribe una letra por llamada, como una persona: un solo `typeText` mete toda la frase en menos de un segundo y en
    /// el video aparece de golpe. Se escribe en el elemento con el foco (`app`), que no busca el campo en cada letra, y
    /// se espera un poco más después de cada espacio.
    private func teclear(_ texto: String) {
        for letra in texto {
            app.typeText(String(letra))
            pausa(letra == " " ? 0.18 : 0.06)
        }
    }

    /// Toca el campo (fuera de su barra interna, como las pruebas de interfaz), escribe y espera a ver el texto completo.
    /// La clave se escribe de una vez (`humano: false`): en pantalla solo se ven puntos.
    private func escribir(_ texto: String, en campo: XCUIElement, descripcion: String? = nil, comprobar: Bool = true,
                          humano: Bool = true) {
        XCTAssertTrue(campo.waitForExistence(timeout: 15), "No apareció el campo")
        esperar(campo, "isHittable == %@", true, "El campo no es tocable")
        accion(descripcion ?? "Escribe: «\(texto)»")
        let previo = (campo.value as? String) ?? ""
        let hayTexto = comprobar && !previo.isEmpty && previo != campo.placeholderValue
        campo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            // Un segundo toque, algo más a la izquierda, por si el primero solo movió el foco.
            campo.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "El teclado no apareció")
        if hayTexto {
            // La consulta conserva la pregunta anterior. El toque deja el cursor a mitad del texto y «borrar» solo quita lo
            // de antes; lo que queda es más corto, así que el siguiente toque cae después de su final. Con letra grande,
            // tocar cerca del borde derecho no abría el teclado.
            for _ in 0..<5 {
                let actual = (campo.value as? String) ?? ""
                if actual.isEmpty || actual == campo.placeholderValue { break }
                campo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
                pausa(0.3)
                campo.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: actual.count + 2))
                pausa(0.3)
            }
        }
        if humano { teclear(texto) } else { campo.typeText(texto) }
        if comprobar { esperar(campo, "value == %@", texto, "El campo no muestra «\(texto)»") }
        pausa(0.6)
    }

    /// Con letra grande, lo que va debajo del campo (Enviar, el siguiente campo) queda bajo el teclado: se cierra
    /// arrastrando hacia abajo a través del teclado (las pantallas usan `scrollDismissesKeyboard(.interactively)`).
    private func cerrarTeclado() {
        let teclado = app.keyboards.firstMatch
        guard teclado.exists else { return }
        let ventana = app.windows.firstMatch
        let desde = ventana.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
        let hasta = ventana.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97))
        desde.press(forDuration: 0.1, thenDragTo: hasta, withVelocity: .slow, thenHoldForDuration: 0.2)
        _ = teclado.waitForNonExistence(timeout: 4)
        pausa(0.4)
    }

    /// Con el teclado abierto, sube el contenido hasta que el elemento quede entero por encima del teclado. Así se toca
    /// «Enviar» sin cerrar el teclado a mano: cerrarlo arrastrando dejaba el campo sin volver a abrir el teclado.
    private func subirSobreTeclado(_ identificador: String) {
        let objetivo = elemento(identificador)
        let teclado = app.keyboards.firstMatch
        for _ in 0..<3 {
            guard teclado.exists, objetivo.exists else { return }
            let limite = teclado.frame.minY - 12
            let exceso = objetivo.frame.maxY - limite
            if exceso <= 0 { return }
            let ventana = app.windows.firstMatch
            let inicio = ventana.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: ventana.frame.width * 0.85, dy: limite - 10))
            inicio.press(forDuration: 0.1, thenDragTo: inicio.withOffset(CGVector(dx: 0, dy: -(exceso + 30))),
                         withVelocity: .slow, thenHoldForDuration: 0.4)
            pausa(0.4)
        }
    }

    /// Arrastra el contenido `desplazamiento` puntos (positivo: hacia abajo de la pantalla), sin inercia.
    private func arrastrar(_ desplazamiento: CGFloat) {
        let ventana = app.windows.firstMatch.frame
        let contenido = app.scrollViews.firstMatch.frame
        let arriba = max(app.navigationBars.firstMatch.frame.maxY, contenido.minY)
        let abajo = min(app.tabBars.firstMatch.frame.minY, contenido.maxY)
        let inicio = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: ventana.width / 2, dy: desplazamiento > 0 ? abajo - 30 : arriba + 30))
        inicio.press(forDuration: 0.1, thenDragTo: inicio.withOffset(CGVector(dx: 0, dy: -desplazamiento)),
                     withVelocity: .slow, thenHoldForDuration: 0.4)
        pausa(0.5)
    }

    /// Desplaza hasta que el elemento quede entero entre la barra de navegación y la de pestañas. Con `comienzo`,
    /// basta que su comienzo quede arriba a la vista: un texto largo con letra grande mide más que la pantalla.
    private func mostrar(_ identificador: String, haciaAtras: Bool = false, comienzo: Bool = false) {
        let objetivo = elemento(identificador)
        for _ in 0..<6 {
            let contenido = app.scrollViews.firstMatch.frame
            let arriba = max(app.navigationBars.firstMatch.frame.maxY, contenido.minY)
            let abajo = min(app.tabBars.firstMatch.frame.minY, contenido.maxY)
            let paso = abajo - arriba - 60
            if objetivo.exists {
                let marco = objetivo.frame
                if comienzo {
                    if marco.minY >= arriba, marco.minY <= arriba + 200 { return }
                } else if marco.minY >= arriba, marco.maxY <= abajo, objetivo.isHittable {
                    return
                }
                let deseado = comienzo ? marco.minY - (arriba + 40) : marco.midY - (arriba + abajo) / 2
                if abs(deseado) < 20 { return }
                arrastrar(max(-paso, min(paso, deseado)))
            } else {
                arrastrar(haciaAtras ? -paso : paso)
            }
        }
    }

    // MARK: Consulta con el backend real

    /// Si el servidor no está configurado (primera vez en este Simulator), lo configura en Ajustes, a la vista.
    private func asegurarServidor() {
        abrirPestana("Ajustes")
        let resumen = elemento("resumen-ajustes")
        XCTAssertTrue(resumen.waitForExistence(timeout: 15))
        if resumen.label.contains(origenServidor.replacingOccurrences(of: "https://", with: "")), resumen.label.contains("con clave") {
            pantalla(resumen.label)
            captura("ajustes-servidor")
            pausa(2.0)
            return
        }
        nota("La app pide un servidor HTTPS. Aquí es el backend de este repositorio, arrancado en el mismo Mac.")
        mostrar("campo-origen")
        escribir(origenServidor, en: elemento("campo-origen"), descripcion: "Escribe la dirección del servidor")
        cerrarTeclado()
        mostrar("campo-clave")
        escribir(claveServidor, en: elemento("campo-clave"), descripcion: "Escribe la clave de acceso", comprobar: false,
                 humano: false)
        app.typeText("\n")
        if !app.keyboards.firstMatch.waitForNonExistence(timeout: 4) { cerrarTeclado() }
        let recordar = elemento("interruptor-recordar")
        mostrar("interruptor-recordar")
        accion("Activa «Recordar la clave en el Llavero»")
        pausa(0.6)
        // Con letra grande el interruptor puede ir debajo de su texto: se toca el control de dentro si lo hay.
        let control = recordar.switches.firstMatch
        if control.exists { control.tap() } else { recordar.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        pausa(0.8)
        mostrar("boton-aplicar")
        tocar(elemento("boton-aplicar"), "Toca «Aplicar»")
        let mensaje = elemento("mensaje-ajustes")
        XCTAssertTrue(mensaje.waitForExistence(timeout: 10), "No apareció el mensaje de Ajustes")
        mostrar("resumen-ajustes", haciaAtras: true)
        pantalla(mensaje.label)
        captura("ajustes-servidor")
        pausa(3.0)
    }

    /// Escribe la pregunta, la envía y anota lo que responde el servidor.
    private func preguntar(_ texto: String) {
        abrirPestana("Consulta")
        let campo = elemento("campo-pregunta")
        mostrar("campo-pregunta")
        escribir(texto, en: campo)
        subirSobreTeclado("boton-enviar")
        let enviar = elemento("boton-enviar")
        if app.keyboards.firstMatch.exists, !enviar.isHittable {
            cerrarTeclado()
            mostrar("boton-enviar")
        }
        let respuesta = elemento("texto-respuesta")
        let viaje = elemento("aviso-viaje")
        let error = elemento("mensaje-error")
        // En un segundo turno la respuesta anterior sigue a la vista hasta que la app pasa a «Consultando»: se espera una
        // respuesta distinta de esa.
        let anterior = respuesta.exists ? respuesta.label : nil
        tocar(enviar, "Toca «Enviar»")
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
        func esperarResultado() {
            let limite = Date().addingTimeInterval(25)
            while Date() < limite, !viaje.exists, !error.exists, !respuesta.exists || respuesta.label == anterior { pausa(0.3) }
            _ = elemento("progreso-consulta").waitForNonExistence(timeout: 20)
            pausa(0.5)
        }
        esperarResultado()
        // Si el servidor tarda más que el plazo de la app (12 s), la app conserva la pregunta y ofrece «Reintentar»:
        // se muestra y se usa, como haría una persona. Una sola vez.
        let reintentar = elemento("boton-reintentar")
        if error.exists, reintentar.exists {
            pantalla("No se pudo completar: \(error.label)")
            nota("El servidor tardó más que el plazo de la app; la app conserva la pregunta y ofrece «Reintentar».")
            pausa(3.0)
            mostrar("boton-reintentar")
            tocar(reintentar, "Toca «Reintentar»")
            esperarResultado()
            // Si tampoco responde, el video no muestra la función: se marca como fallido para volver a grabarlo.
            if error.exists {
                pantalla("No se pudo completar: \(error.label)")
                XCTFail("El servidor no respondió a «\(texto)» ni al reintentar")
                return
            }
        }
        if error.exists {
            pantalla("No se pudo completar: \(error.label)")
        } else if viaje.exists {
            pantalla(viaje.label)
        } else if respuesta.exists {
            var partes = [respuesta.label]
            let limiteAccion = elemento("limite-accion")
            if limiteAccion.exists { partes.append(limiteAccion.label) }
            pantalla(partes.joined(separator: " "))
        }
        XCTAssertTrue(respuesta.exists || viaje.exists || error.exists, "No llegó ninguna respuesta a «\(texto)»")
        // El resultado va encima del campo: se sube a su comienzo y se recorre, que con letra grande mide varias pantallas.
        mostrar(viaje.exists ? "aviso-viaje" : (error.exists ? "mensaje-error" : "texto-respuesta"), haciaAtras: true, comienzo: true)
        captura("respuesta")
        pausa(3.5)
        arrastrar(380)
        pausa(2.5)
        arrastrar(380)
        pausa(2.5)
    }

    // MARK: Recorridos

    /// Abre Consulta y, si el servidor aún no está configurado en este Simulator, lo configura antes.
    private func abrirConsultaConServidor() {
        abrirPestana("Consulta")
        let resumen = elemento("resumen-servidor")
        if resumen.waitForExistence(timeout: 10), resumen.label.contains("localhost:8443"), resumen.label.contains("con clave") {
            pantalla(resumen.label)
            pausa(2.0)
            return
        }
        asegurarServidor()
        abrirPestana("Consulta")
    }

    private func activarMetro() {
        let escenario = elemento("boton-escenario")
        mostrar("boton-escenario", haciaAtras: true)
        tocar(escenario, "Toca «Metro (futuro)»")
        esperar(escenario, "value == %@", "activado", "No se activó el escenario Metro")
        pantalla(elemento("introduccion-consulta").label)
        pausa(3.0)
    }

    // Una pregunta por video, con la app recién abierta. Con letra grande de accesibilidad la Consulta crea sus
    // controles al desplazarse, y tras la primera respuesta el campo a veces no abría el teclado o salía del árbol.

    func testDemo01ConsultaRecorrido() throws {
        lanzar([], titulo: "Consulta con el servidor real: recorrido de una ruta")
        nota("App de depuración sin modos de prueba: las respuestas vienen del backend Next.js con datos reales.")
        pausa(2.5)
        asegurarServidor()
        preguntar("recorrido de la B23")
        terminar()
    }

    func testDemo02ConsultaHorario() throws {
        lanzar([], titulo: "Consulta con el servidor real: horario de una ruta")
        nota("Las respuestas vienen del backend Next.js con datos reales de TransMilenio.")
        abrirConsultaConServidor()
        preguntar("horario de la H54")
        terminar()
    }

    func testDemo03ConsultaViaje() throws {
        lanzar([], titulo: "Consulta con el servidor real: cómo llegar")
        nota("Sin paradas verificadas, el servidor no da órdenes de abordaje: avisa y muestra las rutas que pasan cerca.")
        abrirConsultaConServidor()
        preguntar("quiero ir de Ricaurte a Calle 72")
        terminar()
    }

    func testDemo04MetroEstaciones() throws {
        lanzar([], titulo: "Consulta: escenario Metro (futuro), estaciones")
        abrirConsultaConServidor()
        activarMetro()
        preguntar("estaciones")
        terminar()
    }

    func testDemo05MetroEstacion() throws {
        lanzar([], titulo: "Consulta: escenario Metro (futuro), una estación")
        abrirConsultaConServidor()
        activarMetro()
        preguntar("Puente Aranda")
        let escenario = elemento("boton-escenario")
        mostrar("boton-escenario", haciaAtras: true)
        tocar(escenario, "Toca «Metro (futuro)» para volver al transporte de hoy")
        esperar(escenario, "value == %@", "desactivado", "No se desactivó el escenario Metro")
        pantalla(elemento("introduccion-consulta").label)
        terminar()
    }

    func testDemo06SesionConAccesorio() throws {
        lanzar(["-PRUEBAS_UI_ACCESORIO_SINTETICO"], titulo: "Sesión con el accesorio (transporte sintético)")
        abrirPestana("Sesión")
        nota("El Simulator no tiene Bluetooth: la pantalla real del accesorio se maneja con un transporte sintético rotulado.")
        let aviso = elemento("aviso-transporte-sintetico")
        XCTAssertTrue(aviso.waitForExistence(timeout: 15))
        pantalla(aviso.label)
        pausa(4.0)
        arrastrar(300)
        pausa(2.0)
        mostrar("boton-buscar", haciaAtras: true)
        tocar(elemento("boton-buscar"), "Toca «Buscar accesorios»")
        let continuar = elemento("boton-permiso-continuar")
        if continuar.waitForExistence(timeout: 8) {
            if elemento("texto-permiso-bluetooth").exists { pantalla(elemento("texto-permiso-bluetooth").label) }
            pausa(3.5)
            tocar(continuar, "Toca «Continuar»")
            _ = continuar.waitForNonExistence(timeout: 10)
        }
        let elegir = elemento("elegir-SINTETICO-0001")
        XCTAssertTrue(elegir.waitForExistence(timeout: 15), "No apareció el accesorio sintético")
        mostrar("elegir-SINTETICO-0001")
        tocar(elegir, "Elige «Accesorio sintético (0001)»")
        mostrar("boton-sesion-accesorio")
        let boton = elemento("boton-sesion-accesorio")
        tocar(boton, "Toca «Iniciar sesión»")
        esperar(boton, "label == %@", "Detener sesión", "La sesión no arrancó")
        mostrar("titulo-estado-accesorio")
        XCTAssertTrue(etiquetado("Bloqueado: enlace no verificado").waitForExistence(timeout: 15))
        let estado = ["titulo-estado-accesorio", "estado-accesorio", "estado-accesorio-1", "estado-accesorio-2"]
            .map { elemento($0) }.filter { $0.exists }.map { $0.label }
        pantalla(estado.joined(separator: " "))
        captura("sesion-bloqueada")
        nota("Con el transporte sintético el enlace no se verifica, así que la app bloquea los avisos y no usa ninguna medida.")
        pausa(6.0)
        arrastrar(300)
        pausa(2.5)
        mostrar("boton-sesion-accesorio", haciaAtras: true)
        tocar(boton, "Toca «Detener sesión»")
        XCTAssertTrue(etiquetado("Detenido").waitForExistence(timeout: 15))
        pantalla("Detenido")
        pausa(2.0)
        mostrar("boton-reconectar")
        tocar(elemento("boton-reconectar"), "Toca «Reconectar»")
        XCTAssertTrue(etiquetado("Bloqueado: enlace no verificado").waitForExistence(timeout: 15))
        pantalla("Bloqueado: enlace no verificado")
        pausa(3.0)
        terminar()
    }

    func testDemo07Lupa() throws {
        lanzar(["-PRUEBAS_UI_SIMULADAS"], titulo: "Lupa: permiso, aumento, filtros y congelar")
        nota("El Simulator no tiene cámara: la lupa usa una imagen sintética rotulada y los filtros no la cambian.")
        let pestana = app.tabBars.buttons["Lupa"]
        tocar(pestana, "Toca la pestaña «Lupa»")
        let explicacion = elemento("texto-permiso-camara")
        if explicacion.waitForExistence(timeout: 10) {
            pantalla(explicacion.label)
            pausa(4.0)
            tocar(elemento("boton-permiso-camara-continuar"), "Toca «Continuar»")
            _ = elemento("boton-permiso-camara-continuar").waitForNonExistence(timeout: 10)
        }
        let visor = elemento("visor-lupa")
        XCTAssertTrue(visor.waitForExistence(timeout: 15))
        esperar(visor, "value == %@", "Imagen en vivo", "La lupa no quedó activa")
        if elemento("aviso-camara-sintetica").exists { pantalla(elemento("aviso-camara-sintetica").label) }
        pausa(3.0)
        mostrar("control-aumento")
        let aumento = elemento("control-aumento")
        accion("Sube el aumento")
        for posicion in [0.3, 0.6, 1.0] {
            aumento.adjust(toNormalizedSliderPosition: posicion)
            pausa(1.2)
        }
        if let valor = aumento.value as? String { pantalla("Aumento: \(valor)") }
        captura("lupa-aumento")
        pausa(1.5)
        mostrar("filtro-invertir")
        for (id, nombre) in [("filtro-fluorescente", "Fluorescente"), ("filtro-blancoYNegro", "Blanco y negro"),
                             ("filtro-invertir", "Invertir"), ("filtro-contraste", "Alto contraste")] {
            let filtro = elemento(id)
            if filtro.exists {
                tocar(filtro, "Toca el filtro «\(nombre)»")
                pausa(1.2)
            }
        }
        mostrar("boton-congelar")
        let congelar = elemento("boton-congelar")
        tocar(congelar, "Toca «Congelar imagen»")
        esperar(congelar, "label == %@", "Reanudar", "No se congeló la imagen")
        pantalla(visor.value as? String ?? "Imagen congelada")
        captura("lupa-congelada")
        pausa(2.5)
        tocar(congelar, "Toca «Reanudar»")
        esperar(congelar, "label == %@", "Congelar imagen", "No se reanudó la imagen")
        pausa(2.0)
        terminar()
    }

    func testDemo08Ajustes() throws {
        lanzar([], titulo: "Ajustes: servidor, preferencias, favoritas y ayuda")
        asegurarServidor()
        for seccion in ["Preferencias", "Favoritas", "Ayuda"] {
            tocar(elemento("menu-mas-ajustes"), "Toca «Más ajustes»")
            tocar(etiquetado(seccion), "Elige «\(seccion)»")
            pausa(1.5)
            captura("ajustes-\(seccion.lowercased())")
            switch seccion {
            case "Favoritas":
                let vacio = elemento("favoritas-vacio")
                if vacio.waitForExistence(timeout: 5) { pantalla(vacio.label) }
            case "Ayuda":
                if elemento("ayuda-titulo-0").waitForExistence(timeout: 5) { pantalla(elemento("ayuda-titulo-0").label) }
                pausa(2.0)
                arrastrar(350)
                pausa(2.0)
                arrastrar(350)
            default:
                nota("La voz propia de los avisos del accesorio; es el mismo interruptor de la pestaña Sesión.")
            }
            pausa(3.5)
            let atras = app.navigationBars.buttons.element(boundBy: 0)
            tocar(atras, "Vuelve a Ajustes")
            pausa(1.0)
        }
        terminar()
    }

    // MARK: Rutas, viaje y avisos (lo fusionado el 13/11: #94, #92, #93 y #95)

    /// Consulta ▸ el botón del mapa de la barra de navegación abre «Rutas y viaje».
    private func abrirRutas() {
        tocar(elemento("enlace-rutas"), "Toca el botón «Rutas y viaje» de la barra (icono de mapa)")
        XCTAssertTrue(elemento("campo-busqueda-rutas").waitForExistence(timeout: 15), "No se abrió la búsqueda de rutas")
        pausa(1.0)
        let introduccion = elemento("introduccion-rutas")
        if introduccion.exists { pantalla(introduccion.label) }
        pausa(2.5)
    }

    /// Espera lo que diga `listo` o un error del planificador. Con el error y «Reintentar» a la vista, lo usa una sola vez,
    /// como haría una persona; si tampoco llega, el video no muestra la función y se marca como fallido.
    private func esperarPlanificador(_ descripcion: String, listo: () -> Bool) {
        let error = elemento("mensaje-error-rutas")
        for intento in 0..<2 {
            let limite = Date().addingTimeInterval(25)
            while Date() < limite, !listo(), !error.exists { pausa(0.3) }
            pausa(0.5)
            if listo() { return }
            let reintentar = elemento("boton-reintentar-rutas")
            guard intento == 0, error.exists, reintentar.exists else { break }
            pantalla("No se pudo completar: \(error.label)")
            nota("El servidor tardó o falló; la pantalla lo dice y ofrece «Reintentar».")
            pausa(2.5)
            mostrar("boton-reintentar-rutas")
            tocar(reintentar, "Toca «Reintentar»")
        }
        if error.exists { pantalla("No se pudo completar: \(error.label)") }
        XCTAssertTrue(listo(), "No llegó \(descripcion)")
    }

    /// Baja, con tope, hasta que exista el elemento (las listas largas se crean al desplazarse) y luego lo muestra.
    private func bajarHasta(_ identificador: String, maximo: Int = 10) {
        let objetivo = elemento(identificador)
        var gestos = 0
        while !objetivo.exists, gestos < maximo {
            arrastrar(300)
            gestos += 1
        }
        if objetivo.exists { mostrar(identificador) }
    }

    /// Abre la lista de lugares del servidor, la filtra por `nombre` y elige el primero que lo contiene.
    private func elegirLugar(_ selector: String, _ nombre: String) {
        let fila = elemento(selector)
        mostrar(selector)
        let antes = fila.label
        tocar(fila, "Toca «\(antes)»")
        let filtro = elemento("filtro-lugares")
        XCTAssertTrue(filtro.waitForExistence(timeout: 15), "No se abrió la lista de lugares")
        pausa(1.0)
        escribir(nombre, en: filtro, descripcion: "Escribe «\(nombre)» para filtrar la lista")
        let lugar = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'lugar-' AND label CONTAINS[c] %@", nombre)).firstMatch
        XCTAssertTrue(lugar.waitForExistence(timeout: 10), "El servidor no ofrece un lugar que contenga «\(nombre)»")
        pausa(1.5)
        if !lugar.isHittable {
            // El filtro es de una línea: «intro» cierra el teclado sin elegir nada.
            app.typeText("\n")
            if !app.keyboards.firstMatch.waitForNonExistence(timeout: 4) { cerrarTeclado() }
            mostrar(lugar.identifier)
        }
        let elegido = lugar.label
        tocar(lugar, "Elige «\(elegido)»")
        XCTAssertTrue(fila.waitForExistence(timeout: 15), "No volvió al viaje")
        esperar(fila, "label != %@", antes, "El selector no cambió tras elegir «\(elegido)»")
        pantalla(fila.label)
        pausa(1.5)
    }

    func testDemo09RutasYDetalle() throws {
        lanzar([], titulo: "Rutas: buscar por estación y abrir el detalle con su mapa")
        nota("Las rutas y su detalle vienen del backend Next.js con datos reales de TransMilenio. No se envía la ubicación.")
        abrirConsultaConServidor()
        abrirRutas()
        mostrar("campo-busqueda-rutas")
        escribir("Ricaurte", en: elemento("campo-busqueda-rutas"))
        accion("Toca «Buscar» en el teclado")
        app.typeText("\n")
        if !app.keyboards.firstMatch.waitForNonExistence(timeout: 4) {
            cerrarTeclado()
            mostrar("boton-buscar-rutas")
            tocar(elemento("boton-buscar-rutas"), "Toca «Buscar rutas»")
        }
        let resumen = elemento("resumen-busqueda-rutas")
        esperarPlanificador("el resultado de la búsqueda de «Ricaurte»") { resumen.exists }
        mostrar("resumen-busqueda-rutas", haciaAtras: true, comienzo: true)
        pantalla(resumen.label)
        captura("rutas-busqueda")
        pausa(3.5)

        // Las filas son «ruta-<código>»; «ruta-por-el-trazado-» y «ruta-candidata-» son del resultado de un viaje.
        let primera = app.descendants(matching: .any).matching(NSPredicate(format:
            "identifier BEGINSWITH 'ruta-' AND NOT identifier BEGINSWITH 'ruta-por-el-trazado-' AND NOT identifier BEGINSWITH 'ruta-candidata-'"
        )).firstMatch
        XCTAssertTrue(primera.waitForExistence(timeout: 10), "La búsqueda no devolvió rutas")
        let identificador = primera.identifier
        let codigo = String(identificador.dropFirst("ruta-".count))
        mostrar(identificador)
        pausa(1.5)
        tocar(primera, "Toca la ruta \(codigo)")

        let titulo = elemento("detalle-ruta-titulo")
        esperarPlanificador("el detalle de la ruta \(codigo)") { titulo.exists }
        mostrar("detalle-ruta-titulo", haciaAtras: true, comienzo: true)
        var partes = [titulo.label]
        let trayecto = elemento("detalle-ruta-trayecto")
        if trayecto.exists { partes.append(trayecto.label) }
        pantalla(partes.joined(separator: ". "))
        captura("rutas-detalle")
        pausa(3.5)
        let sentido = elemento("aviso-sentido")
        if sentido.exists {
            mostrar("aviso-sentido", comienzo: true)
            pantalla(sentido.label)
            pausa(3.5)
        }
        bajarHasta("mapa-recorrido", maximo: 6)
        if elemento("mapa-recorrido").exists {
            nota("Mapa del mismo recorrido (MapKit). Lo esencial también está en el listado de estaciones.")
            pausa(2.5)
            captura("rutas-mapa")
            pausa(2.5)
        }
        bajarHasta("titulo-estaciones")
        let estaciones = elemento("titulo-estaciones")
        if estaciones.exists {
            pantalla(estaciones.label)
            pausa(2.0)
            arrastrar(380)
            captura("rutas-estaciones")
            pausa(2.5)
            arrastrar(380)
            pausa(2.5)
        }
        terminar()
    }

    func testDemo10Viaje() throws {
        lanzar([], titulo: "Viaje entre dos lugares elegidos de una lista: de Ricaurte a Calle 72")
        nota("Origen y destino se eligen de la lista del servidor: no se escribe una frase ni se envía la ubicación.")
        abrirConsultaConServidor()
        abrirRutas()
        mostrar("enlace-viaje", haciaAtras: true)
        tocar(elemento("enlace-viaje"), "Toca «Planear un viaje entre dos lugares»")
        let origen = elemento("selector-origen")
        esperarPlanificador("la lista de lugares") { origen.exists }
        let introduccion = elemento("introduccion-viaje")
        if introduccion.exists { pantalla(introduccion.label) }
        pausa(2.5)
        elegirLugar("selector-origen", "Ricaurte")
        elegirLugar("selector-destino", "Calle 72")
        mostrar("boton-planear-viaje")
        captura("viaje-seleccion")
        tocar(elemento("boton-planear-viaje"), "Toca «Planear viaje»")

        let titulo = elemento("resultado-viaje-titulo")
        esperarPlanificador("el resultado del viaje") { titulo.exists }
        mostrar("resultado-viaje-titulo", comienzo: true)
        let notas = app.descendants(matching: .any).matching(identifier: "nota-viaje").allElementsBoundByIndex.map { $0.label }
        pantalla(([titulo.label] + notas).joined(separator: " "))
        nota("El servidor decide el estado del viaje; la app no lo recalcula ni da órdenes de abordaje sin paradas verificadas.")
        captura("viaje-resultado")
        pausa(4.5)
        for id in ["tramo-1", "tramo-2", "ruta-candidata-1", "ruta-candidata-2"] where elemento(id).exists {
            mostrar(id, comienzo: true)
            pantalla(elemento(id).label)
            pausa(3.0)
        }
        let porElTrazado = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'ruta-por-el-trazado-'")).firstMatch
        if porElTrazado.exists {
            mostrar(porElTrazado.identifier)
            pantalla(porElTrazado.label)
            captura("viaje-rutas-por-el-trazado")
            pausa(3.0)
        }
        if elemento("tramo-1").exists {
            bajarHasta("mapa-recorrido", maximo: 6)
            if elemento("mapa-recorrido").exists {
                nota("Mapa de los mismos tramos del listado (MapKit).")
                pausa(2.5)
                captura("viaje-mapa")
                pausa(2.5)
            }
        }
        terminar()
    }

    /// Con los tamaños de accesibilidad la Consulta crea sus controles al desplazarse y, tras la primera respuesta, el campo
    /// no se dejaba reutilizar de forma fiable. Este recorrido necesita dos turnos en la misma sesión, así que `grabar.sh`
    /// lo graba con el mayor tamaño estándar de letra (sin los de accesibilidad); el pie del video lo dice.
    func testDemo11Aclaracion() throws {
        lanzar([], titulo: "Consulta en dos turnos: primero el origen y después el destino")
        nota("Aquí se escribe porque el Simulator no tiene micrófono; en el iPhone se puede decir con «Dictar pregunta».")
        abrirConsultaConServidor()
        preguntar("Salgo desde Ricaurte")
        let pendiente = elemento("origen-pendiente")
        XCTAssertTrue(pendiente.waitForExistence(timeout: 10), "No quedó el origen pendiente tras «Salgo desde Ricaurte»")
        mostrar("origen-pendiente")
        pantalla(pendiente.label)
        nota("La app guarda el origen: la próxima pregunta se toma como el destino.")
        captura("origen-pendiente")
        pausa(4.0)
        preguntar("Calle 72")
        if !elemento("origen-pendiente").exists {
            nota("La segunda pregunta usó el origen guardado y el origen pendiente desapareció.")
            pausa(3.0)
        }
        terminar()
    }

    func testDemo12Avisos() throws {
        lanzar([], titulo: "Avisos: anuncios oficiales de TransMilenio y avisos propios de la app")
        abrirConsultaConServidor()
        abrirPestana("Avisos")
        nota("Los anuncios oficiales los pide la app al backend, que lee las alertas que publica TransMilenio (GTFS-RT).")
        let estado = elemento("anuncios-estado")
        XCTAssertTrue(estado.waitForExistence(timeout: 15), "La pestaña Avisos no muestra el estado de los anuncios")
        pausa(1.0)
        let progreso = elemento("anuncios-progreso")
        let limite = Date().addingTimeInterval(30)
        while Date() < limite, progreso.exists { pausa(0.3) }
        pausa(0.8)
        var partes = [estado.label]
        for indice in 0..<4 {
            let mensaje = elemento("anuncios-mensaje-\(indice)")
            guard mensaje.exists else { break }
            partes.append(mensaje.label)
        }
        pantalla(partes.joined(separator: " "))
        captura("avisos-anuncios")
        pausa(4.0)
        let anuncio = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'anuncio-' AND identifier ENDSWITH '-titulo'")).firstMatch
        if anuncio.exists {
            mostrar(anuncio.identifier)
            pantalla("Anuncio oficial: \(anuncio.label)")
            captura("avisos-anuncio")
            pausa(3.5)
            arrastrar(380)
            pausa(2.5)
        }
        mostrar("encabezado-avisos-propios")
        let propios = frases("avisos-propios-vacio")
        if !propios.isEmpty { pantalla(propios) }
        captura("avisos-propios")
        pausa(3.5)
        mostrar("interruptor-silenciar-advertencias")
        let silenciar = elemento("etiqueta-silenciar-advertencias")
        if silenciar.exists { pantalla(([silenciar.label] + [frases("nota-silencio-avisos")]).joined(separator: ". ")) }
        captura("avisos-voz")
        pausa(4.0)
        mostrar("escenario-simulado", comienzo: true)
        let simulado = frases("escenario-simulado")
        if !simulado.isEmpty { pantalla(simulado) }
        pausa(3.0)
        terminar()
    }

    /// Las frases de un párrafo de Avisos: la primera lleva `id` y las demás `id-1`, `id-2`…
    private func frases(_ id: String) -> String {
        var textos: [String] = []
        for posicion in 0..<6 {
            let parte = elemento(posicion == 0 ? id : "\(id)-\(posicion)")
            guard parte.exists else { break }
            textos.append(parte.label)
        }
        return textos.joined(separator: " ")
    }
}
