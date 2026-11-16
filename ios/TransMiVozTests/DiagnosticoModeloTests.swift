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

    func testLaSondaSinteticaSeRotulaComoSimulada() async {
        let resultado = await SondaSintetica(resultado: correcto).ejecutar()
        XCTAssertEqual(resultado.detalle, "[SIMULADO] bien")
        XCTAssertEqual(resultado.estado, .correcto)
    }
}
