import XCTest
@testable import TransMiVoz

private struct SondaFija: SondaDiagnostico {
    let resultado: ResultadoPrueba
    func ejecutar() async -> ResultadoPrueba { resultado }
}

/// Tarda mucho más que cualquier plazo de estas pruebas y termina antes si se cancela (como un cliente HTTP real).
private struct SondaLenta: SondaDiagnostico {
    func ejecutar() async -> ResultadoPrueba {
        try? await Task.sleep(nanoseconds: 30_000_000_000)
        return ResultadoPrueba(estado: .correcto, detalle: "No debería llegar.")
    }
}

private actor Registro {
    private(set) var orden: [String] = []
    func anotar(_ nombre: String) { orden.append(nombre) }
}

private struct SondaRegistrada: SondaDiagnostico {
    let nombre: String
    let registro: Registro
    func ejecutar() async -> ResultadoPrueba {
        await registro.anotar(nombre)
        return ResultadoPrueba(estado: .correcto, detalle: nombre)
    }
}

private struct ClienteAnunciosDeMentira: ClienteAnuncios {
    let resultado: Result<AnunciosRespuesta, ErrorConsulta>
    func consultar() async throws -> AnunciosRespuesta { try resultado.get() }
}

private struct ClienteAgenteDeMentira: ClienteAgente {
    let resultado: Result<RespuestaAgente, ErrorConsulta>
    func consultar(texto: String, origenPendiente: String?) async throws -> RespuestaAgente { try resultado.get() }
}

private struct PlanificadorDeMentira: ClientePlanificador {
    let resultado: Result<ListaLugares, ErrorConsulta>
    func buscarRutas(consulta: String) async throws -> ResultadoBusquedaRutas { throw ErrorConsulta.cancelada }
    func detalleRuta(codigo: String) async throws -> DetalleRuta { throw ErrorConsulta.cancelada }
    func listarLugares() async throws -> ListaLugares { try resultado.get() }
    func planearViaje(origen: String, destino: String) async throws -> PlanViaje { throw ErrorConsulta.cancelada }
}

@MainActor
final class DiagnosticoModeloTests: XCTestCase {
    private let correcto = ResultadoPrueba(estado: .correcto, detalle: "bien")

    private func modelo(_ sondas: [PruebaDiagnostico: any SondaDiagnostico], plazo: TimeInterval = 5) -> DiagnosticoModelo {
        DiagnosticoModelo(sondas: sondas, plazo: plazo)
    }

    /// Espera con tope a que se cumpla algo que ocurre en otra tarea.
    private func esperar(_ condicion: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condicion() { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condicion(), "no ocurrió a tiempo", file: file, line: line)
    }

    func testSinProbarNadaNoHayResultadosNiCorrectas() {
        let modelo = modelo([:])
        XCTAssertEqual(modelo.total, PruebaDiagnostico.allCases.count)
        XCTAssertEqual(modelo.correctas, 0)
        XCTAssertFalse(modelo.ocupado)
        for prueba in PruebaDiagnostico.allCases { XCTAssertEqual(modelo.fila(prueba), .sinProbar) }
    }

    func testUnaPruebaCorridaGuardaSuResultadoYSoloLasCorrectasSeCuentan() async {
        let atencion = ResultadoPrueba(estado: .atencion, detalle: "falta")
        let fallo = ResultadoPrueba(estado: .fallo, detalle: "mal")
        let modelo = modelo([.servidor: SondaFija(resultado: correcto), .voz: SondaFija(resultado: atencion), .camara: SondaFija(resultado: fallo)])
        await modelo.ejecutar(.servidor)
        await modelo.ejecutar(.voz)
        await modelo.ejecutar(.camara)
        XCTAssertEqual(modelo.fila(.servidor), .terminada(correcto))
        XCTAssertEqual(modelo.fila(.voz), .terminada(atencion))
        XCTAssertEqual(modelo.fila(.camara), .terminada(fallo))
        XCTAssertEqual(modelo.correctas, 1, "atención y fallo no cuentan como correctas")
        XCTAssertEqual(modelo.fila(.bluetooth), .sinProbar, "lo que no se probó sigue sin probar")
    }

    func testUnaPruebaSinSondaFallaYNuncaSeDaPorBuena() async {
        let modelo = modelo([:])
        await modelo.ejecutar(.microfono)
        XCTAssertEqual(modelo.fila(.microfono), .terminada(ResultadoPrueba(estado: .fallo, detalle: DiagnosticoTexto.sinSonda)))
        XCTAssertEqual(modelo.correctas, 0)
    }

    func testUnaSondaQueNoRespondeAcabaEnFalloConSuTexto() async {
        let modelo = modelo([.servidor: SondaLenta()], plazo: 0.1)
        await modelo.ejecutar(.servidor)
        XCTAssertEqual(modelo.fila(.servidor), .terminada(ResultadoPrueba(estado: .fallo, detalle: DiagnosticoTexto.sinRespuesta)))
    }

    func testProbarTodoCorreLasPruebasEnOrdenYAlTerminarNoQuedaOcupado() async {
        let registro = Registro()
        var sondas: [PruebaDiagnostico: any SondaDiagnostico] = [:]
        for prueba in PruebaDiagnostico.allCases { sondas[prueba] = SondaRegistrada(nombre: prueba.rawValue, registro: registro) }
        let modelo = modelo(sondas)
        modelo.iniciarTodo()
        XCTAssertTrue(modelo.ocupado, "«Probar todo» ocupa el diagnóstico desde que arranca")
        await esperar { !modelo.ocupado }
        let corridas = await registro.orden
        XCTAssertEqual(corridas, PruebaDiagnostico.allCases.map(\.rawValue))
        XCTAssertEqual(modelo.correctas, modelo.total)
    }

    func testMientrasOtraPruebaCorreNoSeLanzaUnaSegunda() async {
        let modelo = modelo([.servidor: SondaLenta(), .voz: SondaFija(resultado: correcto)])
        modelo.iniciar(.servidor)
        await esperar { modelo.fila(.servidor) == .probando }
        modelo.iniciar(.voz)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(modelo.fila(.voz), .sinProbar)
        modelo.cancelar()
        await esperar { !modelo.ocupado }
    }

    func testCancelarDejaLaFilaSinProbarYNoInformaResultado() async {
        let modelo = modelo([.servidor: SondaLenta()], plazo: 20)
        modelo.iniciar(.servidor)
        await esperar { modelo.fila(.servidor) == .probando }
        modelo.cancelar()
        await esperar { modelo.fila(.servidor) == .sinProbar }
        XCTAssertEqual(modelo.correctas, 0)
        XCTAssertFalse(modelo.ocupado)
    }

    // MARK: Servidor y asistente por los clientes de la app

    func testElServidorSinDireccionEsAtencionYNoUnServidorCaido() async throws {
        let resultado = await SondaServidor(cliente: ClienteAnunciosDeMentira(resultado: .failure(.servidorNoConfigurado))).ejecutar()
        XCTAssertEqual(resultado.estado, .atencion)
        XCTAssertTrue(resultado.detalle.contains("Falta la dirección del servidor."))
        XCTAssertTrue(resultado.detalle.contains("Ajustes"), "dice dónde arreglarlo")
    }

    func testElServidorQueRechazaLaClaveEsUnFalloQueNoLaMuestra() async {
        let resultado = await SondaServidor(cliente: ClienteAnunciosDeMentira(resultado: .failure(.noAutorizado))).ejecutar()
        XCTAssertEqual(resultado.estado, .fallo)
        XCTAssertTrue(resultado.detalle.contains("401"))
        for prohibido in ["Basic", "Authorization", "transmivoz:", "https://"] {
            XCTAssertFalse(resultado.detalle.contains(prohibido), "el resultado no debe mostrar «\(prohibido)»")
        }
    }

    func testElServidorQueRespondeEsCorrectoYDiceElEstadoDeLaFuente() async throws {
        let respuesta = try AnunciosRespuesta.decodificar(FixturesAnuncios.datos(FixturesAnuncios.sinFuente))
        let resultado = await SondaServidor(cliente: ClienteAnunciosDeMentira(resultado: .success(respuesta))).ejecutar()
        XCTAssertEqual(resultado.estado, .correcto)
        XCTAssertTrue(resultado.detalle.contains("Sin fuente conectada"), "una fuente caída del operador no es un servidor caído, pero se dice")
        XCTAssertTrue(resultado.detalle.contains("0 anuncios"))
    }

    func testElAsistenteQueRespondeEsCorrectoYNoMuestraSuTexto() async throws {
        let respuesta = try RespuestaAgente.decodificar(Data(FixturesHTTP.ninguna.utf8))
        let resultado = await SondaAsistente(cliente: ClienteAgenteDeMentira(resultado: .success(respuesta))).ejecutar()
        XCTAssertEqual(resultado.estado, .correcto)
        XCTAssertFalse(resultado.detalle.contains(respuesta.texto), "el texto de la respuesta del servidor no se copia al diagnóstico")
    }

    func testElAsistenteSinConexionFalla() async {
        let resultado = await SondaAsistente(cliente: ClienteAgenteDeMentira(resultado: .failure(.sinConexion))).ejecutar()
        XCTAssertEqual(resultado.estado, .fallo)
        XCTAssertTrue(resultado.detalle.contains("No hay conexión con el servidor."))
    }

    // MARK: Voz de la app (la `ControlVoz` compartida, con una salida de voz de mentira)

    private func bancoDeVoz(ruta: RutaAudio = .privada) -> (ControlVoz, SalidaVozFalsa) {
        let salida = SalidaVozFalsa()
        return (ControlVoz(salida: salida, consultarRuta: { ruta }), salida)
    }

    func testLaVozDeLaAppHablaPorLaColaUnicaYEsperaAQueTermineSinCortarla() async {
        let (voz, salida) = bancoDeVoz()
        let terminar = Task { try? await Task.sleep(nanoseconds: 150_000_000); salida.terminarSola() }
        let resultado = await SondaVoz(voz: voz, vocesEnEspanol: { 2 }).ejecutar()
        await terminar.value
        XCTAssertEqual(resultado.estado, .correcto)
        XCTAssertEqual(salida.dicho, [DiagnosticoTexto.fraseDeVoz])
        XCTAssertEqual(voz.locuciones, 1, "es una locución de la cola única de la app, no otra sesión de voz")
        XCTAssertEqual(salida.completas, [DiagnosticoTexto.fraseDeVoz], "la frase sonó entera: nadie la cortó")
    }

    func testUnaFraseQueNoTerminaSeCortaPeroSoloSiSigueSiendoLaPropia() async {
        let (voz, salida) = bancoDeVoz()
        let resultado = await SondaVoz(voz: voz, vocesEnEspanol: { 1 }, tope: 0.1).ejecutar()
        XCTAssertEqual(resultado.estado, .correcto)
        XCTAssertEqual(salida.cortadas, [DiagnosticoTexto.fraseDeVoz], "al vencer el tope corta su propia frase")
    }

    func testSinSalidaPrivadaOConLaVozApagadaNoHablaYLoDiceEnVezDeDarloPorBueno() async {
        let (_, salidaAltavoz) = bancoDeVoz(ruta: .noPrivada)
        let altavoz = await SondaVoz(voz: ControlVoz(salida: salidaAltavoz, consultarRuta: { .noPrivada }), vocesEnEspanol: { 2 }).ejecutar()
        XCTAssertEqual(altavoz.estado, .atencion)
        XCTAssertTrue(altavoz.detalle.contains("auriculares"))
        XCTAssertTrue(salidaAltavoz.dicho.isEmpty)

        let (voz, salida) = bancoDeVoz()
        voz.permitida = { false }
        let apagada = await SondaVoz(voz: voz, vocesEnEspanol: { 2 }).ejecutar()
        XCTAssertEqual(apagada.estado, .atencion)
        XCTAssertTrue(apagada.detalle.contains("apagada"))
        XCTAssertTrue(salida.dicho.isEmpty)
    }

    func testUnAvisoSonandoNoSeCortaNiSeTapaPorLaPruebaDeVoz() async {
        let (voz, salida) = bancoDeVoz()
        voz.anunciar("Objeto cerca.", prioridad: .urgente)
        let resultado = await SondaVoz(voz: voz, vocesEnEspanol: { 2 }).ejecutar()
        XCTAssertEqual(resultado.estado, .atencion)
        XCTAssertEqual(salida.dicho, ["Objeto cerca."])
        XCTAssertTrue(salida.cortadas.isEmpty)
        XCTAssertTrue(salida.hablando)
    }

    func testUnAudioQueElIPhoneNoDejaActivarEsUnFallo() async {
        let (voz, salida) = bancoDeVoz()
        salida.resultado = .sesionNoDisponible
        let resultado = await SondaVoz(voz: voz, vocesEnEspanol: { 2 }).ejecutar()
        XCTAssertEqual(resultado.estado, .fallo)
    }

    // MARK: Planificador (lista de lugares por `ClientePlanificadorHTTP.interpretar`, el mismo camino del cliente real)

    private func planificador(_ resultado: Result<ListaLugares, ErrorConsulta>) -> SondaPlanificador {
        SondaPlanificador(cliente: PlanificadorDeMentira(resultado: resultado))
    }

    func testElPlanificadorQueRespondeEsCorrectoYDiceCuantosLugares() async throws {
        let lista: ListaLugares = try decodificarPlanificador(FixturesPlanificador.lugares)
        let resultado = await planificador(.success(lista)).ejecutar()
        XCTAssertEqual(resultado.estado, .correcto)
        XCTAssertTrue(resultado.detalle.contains("3 lugares"))
    }

    func testUnCatalogoAntiguoOSinLugaresEsAtencionNoExito() async throws {
        let antiguo: ListaLugares = try decodificarPlanificador(
            variante(#""antiguo":false"#, por: #""antiguo":true"#))
        let conCatalogoAntiguo = await planificador(.success(antiguo)).ejecutar()
        XCTAssertEqual(conCatalogoAntiguo.estado, .atencion)
        let vacia: ListaLugares = try decodificarPlanificador(
            variante(#"["Estación Ejemplo Centro","Estación Ejemplo Norte","Estación Ejemplo Sur"]"#, por: "[]"))
        let resultado = await planificador(.success(vacia)).ejecutar()
        XCTAssertEqual(resultado.estado, .atencion)
        XCTAssertTrue(resultado.detalle.contains("sin lugares"))
    }

    func testUnServidorSinPlanificadorFallaConSuPropioTextoYSinDireccionEsAtencion() async throws {
        // Lo que de verdad lanza el cliente con un 404 sin el cuerpo del planificador.
        let sinEndpoint = try XCTUnwrap(errorDeInterpretar(estado: 404))
        let falla = await planificador(.failure(sinEndpoint)).ejecutar()
        XCTAssertEqual(falla.estado, .fallo)
        XCTAssertTrue(falla.detalle.contains("no tiene el planificador"))

        let sinDireccion = await planificador(.failure(.servidorNoConfigurado)).ejecutar()
        XCTAssertEqual(sinDireccion.estado, .atencion)
        let otra = await planificador(.failure(.sinConexion)).ejecutar()
        XCTAssertEqual(otra.estado, .fallo)
        XCTAssertFalse(otra.detalle.contains("planificador"), "los demás errores usan el texto de siempre")
    }

    /// El fixture de lugares con un trozo cambiado; falla si el trozo no estaba (una variante que no cambia nada probaría lo contrario).
    private func variante(_ buscado: String, por nuevo: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertTrue(FixturesPlanificador.lugares.contains(buscado), "el fixture no contiene «\(buscado)»", file: file, line: line)
        return FixturesPlanificador.lugares.replacingOccurrences(of: buscado, with: nuevo)
    }

    private func errorDeInterpretar(estado: Int) -> ErrorConsulta? {
        do {
            let _: ListaLugares = try decodificarPlanificador("{}", estado: estado)
            return nil
        } catch {
            return error as? ErrorConsulta
        }
    }

    func testLaSondaSinteticaSeRotulaComoSimulada() async {
        let resultado = await SondaSintetica(resultado: correcto).ejecutar()
        XCTAssertEqual(resultado.detalle, "[SIMULADO] bien")
        XCTAssertEqual(resultado.estado, .correcto)
    }
}
