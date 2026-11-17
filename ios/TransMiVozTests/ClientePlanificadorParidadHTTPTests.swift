import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TransMiVoz

/// `metro-linea-1` y `estaciones-cercanas` por el MISMO transporte del planificador, con la red SIMULADA: autenticación,
/// plazo, redirecciones, estados HTTP y validación. La lectura de ubicación viaja solo en el cuerpo.
final class ClientePlanificadorParidadHTTPTests: XCTestCase {
    private let origen = try! OrigenServidor.analizar("https://servidor.ejemplo").get()
    private let claveInventada = ClaveAcceso(valor: "clave-inventada-de-prueba")

    override func setUp() {
        super.setUp()
        ProtocoloSimulado.reiniciar()
    }

    override func tearDown() {
        ProtocoloSimulado.reiniciar()
        super.tearDown()
    }

    private func cliente(esperaMaxima: TimeInterval = 5, configurado: Bool = true) -> ClientePlanificadorHTTP {
        let configuracion: ConfiguracionServidor? = configurado ? ConfiguracionServidor(origen: origen, clave: claveInventada) : nil
        return ClientePlanificadorHTTP(sesion: ProtocoloSimulado.sesion(), esperaMaxima: esperaMaxima) { configuracion }
    }

    private func responder(_ estado: Int, _ json: String = "", cabeceras: [String: String] = [:]) {
        ProtocoloSimulado.manejador = { _ in .responder(estado: estado, cabeceras: cabeceras, cuerpo: Data(json.utf8)) }
    }

    private func cuerpoEnviado(file: StaticString = #filePath, line: UInt = #line) throws -> NSDictionary {
        let datos = try XCTUnwrap(ProtocoloSimulado.peticiones.last?.httpBody, file: file, line: line)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: datos) as? NSDictionary, file: file, line: line)
    }

    private func objeto(_ json: String) throws -> NSDictionary {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    private func esperarError<R>(
        _ esperado: ErrorConsulta, file: StaticString = #filePath, line: UInt = #line, _ operacion: () async throws -> R
    ) async {
        do {
            _ = try await operacion()
            XCTFail("se esperaba \(esperado)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ErrorConsulta, esperado, file: file, line: line)
        }
    }

    private let lectura = LecturaParaEnviar(
        latitud: 4.6124, longitud: -74.0935, precision: 12, edadMs: 800,
        rumbo: RumboParaEnviar(grados: 90, calidad: 10, edadMs: 300))

    // MARK: Metro

    func testMetroEnviaSoloLaOperacionConAutenticacionYSinQuery() async throws {
        responder(200, FixturesParidad.metro)
        let metro = try await cliente().metroLinea1()
        XCTAssertEqual(metro.estaciones.count, 16)

        let peticion = try XCTUnwrap(ProtocoloSimulado.peticiones.first)
        XCTAssertEqual(peticion.httpMethod, "POST")
        XCTAssertEqual(peticion.url?.absoluteString, "https://servidor.ejemplo/api/planificador")
        XCTAssertEqual(peticion.value(forHTTPHeaderField: "Authorization"), claveInventada.cabeceraBasic)
        XCTAssertEqual(peticion.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(try cuerpoEnviado(), try objeto(FixturesParidad.peticionMetro))
    }

    func testUnServidorAnteriorQueNoConoceElMetroResponde400() async {
        responder(400, #"{"error":"peticion-invalida"}"#)
        await esperarError(.peticionRechazada) { try await self.cliente().metroLinea1() }
    }

    func testMetroRechazaUnaRespuestaIncompatible() async {
        let sinServicioFalso = modificar(FixturesParidad.metro) { objeto in
            var linea = objeto["linea"] as? [String: Any] ?? [:]
            linea["servicioComercial"] = true
            objeto["linea"] = linea
        }
        for json in ["no es json", "", "{}", sinServicioFalso, FixturesParidad.cercanasRelativa] {
            responder(200, json)
            await esperarError(.respuestaIncompatible) { try await self.cliente().metroLinea1() }
        }
    }

    // MARK: Estaciones cercanas

    func testLaLecturaViajaEnElCuerpoYNuncaEnLaUrl() async throws {
        responder(200, FixturesParidad.cercanasRelativa)
        _ = try await cliente().estacionesCercanas(lectura)

        let peticion = try XCTUnwrap(ProtocoloSimulado.peticiones.first)
        XCTAssertEqual(peticion.httpMethod, "POST")
        XCTAssertEqual(try cuerpoEnviado(), try objeto(FixturesParidad.peticionCercanas))
        let direccion = peticion.url?.absoluteString ?? ""
        XCTAssertEqual(direccion, "https://servidor.ejemplo/api/planificador")
        XCTAssertNil(peticion.url?.query)
        for fragmento in ["4.6124", "74.0935", "4.61", "74.09"] { XCTAssertFalse(direccion.contains(fragmento)) }
        XCTAssertLessThanOrEqual(peticion.httpBody?.count ?? .max, EntradaPlanificador.maximoBytesCuerpo)
    }

    func testSinPrecisionNiRumboNoSeEnvianEsosCampos() async throws {
        responder(200, FixturesParidad.cercanasCardinal)
        _ = try await cliente().estacionesCercanas(
            LecturaParaEnviar(latitud: 4.6124, longitud: -74.0935, precision: nil, edadMs: 0, rumbo: nil))
        XCTAssertEqual(try cuerpoEnviado(), try objeto(FixturesParidad.peticionCercanasMinima))
        let claves = Set((try cuerpoEnviado()).allKeys.compactMap { $0 as? String })
        XCTAssertEqual(claves, ["operacion", "lat", "lng", "edadMs"])
    }

    func testSinCalidadDeRumboElRumboViajaSinCalidad() async throws {
        responder(200, FixturesParidad.cercanasRelativa)
        _ = try await cliente().estacionesCercanas(
            LecturaParaEnviar(latitud: 4.6, longitud: -74.1, precision: 8, edadMs: 5,
                              rumbo: RumboParaEnviar(grados: 359.5, calidad: nil, edadMs: 40)))
        let rumbo = try XCTUnwrap(try cuerpoEnviado()["rumbo"] as? NSDictionary)
        XCTAssertEqual(Set(rumbo.allKeys.compactMap { $0 as? String }), ["grados", "edadMs"])
    }

    func testUnaLecturaFueraDeLasCotasNoTocaLaRed() async {
        func con(
            latitud: Double = 4.6, longitud: Double = -74.1, precision: Double? = 10, edadMs: Int = 0, rumbo: RumboParaEnviar? = nil
        ) -> LecturaParaEnviar {
            LecturaParaEnviar(latitud: latitud, longitud: longitud, precision: precision, edadMs: edadMs, rumbo: rumbo)
        }
        let invalidas: [LecturaParaEnviar] = [
            con(latitud: 91), con(latitud: -91), con(longitud: 181), con(latitud: .nan), con(longitud: .infinity),
            con(precision: -1), con(precision: 100_001), con(precision: .nan),
            con(edadMs: -1), con(edadMs: 600_001),
            con(rumbo: RumboParaEnviar(grados: -1, calidad: 5, edadMs: 0)),
            con(rumbo: RumboParaEnviar(grados: 361, calidad: 5, edadMs: 0)),
            con(rumbo: RumboParaEnviar(grados: 90, calidad: 361, edadMs: 0)),
            con(rumbo: RumboParaEnviar(grados: 90, calidad: -2, edadMs: 0)),
            con(rumbo: RumboParaEnviar(grados: 90, calidad: 5, edadMs: 600_001)),
        ]
        for invalida in invalidas {
            await esperarError(.peticionRechazada) { try await self.cliente().estacionesCercanas(invalida) }
        }
        await esperarError(.servidorNoConfigurado) { try await self.cliente(configurado: false).estacionesCercanas(self.lectura) }
        XCTAssertTrue(ProtocoloSimulado.peticiones.isEmpty, "nada de eso sale de la app")
    }

    func testLosLimitesDelContratoSiSeAceptan() {
        let enElLimite = LecturaParaEnviar(
            latitud: 90, longitud: -180, precision: 100_000, edadMs: 600_000,
            rumbo: RumboParaEnviar(grados: 360, calidad: -1, edadMs: 600_000))
        XCTAssertTrue(enElLimite.esValida)
    }

    func testUnaLecturaImpresaNoDejaLaCoordenadaEnNingunRegistro() {
        let texto = "\(lectura) \(String(reflecting: lectura)) \(PeticionPlanificador.estacionesCercanas(lectura))"
        for fragmento in ["4.6124", "74.0935", "4.61", "90.0", "12.0"] { XCTAssertFalse(texto.contains(fragmento), fragmento) }
    }

    func testEstadosHttpDeEstacionesCercanas() async {
        for (estado, esperado): (Int, ErrorConsulta) in [
            (400, .peticionRechazada), (401, .noAutorizado), (413, .mensajeRechazadoPorLargo), (503, .servicioNoDisponible),
            (500, .errorDelServidor(estado: 500)), (302, .redireccionNoPermitida),
        ] {
            responder(estado, "x")
            await esperarError(esperado) { try await self.cliente().estacionesCercanas(self.lectura) }
        }
        responder(429, "x", cabeceras: ["Retry-After": "3"])
        await esperarError(.demasiadasPeticiones(reintentarEnSegundos: 3)) { try await self.cliente().estacionesCercanas(self.lectura) }
        responder(404, #"{"error":"no-encontrado"}"#)
        await esperarError(.noEncontrado) { try await self.cliente().estacionesCercanas(self.lectura) }
    }

    func testRespuestasIncompatiblesDeEstacionesCercanasSeRechazan() async {
        let sinModo = modificar(FixturesParidad.cercanasRelativa) { objeto in
            var estaciones = objeto["estaciones"] as? [[String: Any]] ?? []
            var orientacion = estaciones[0]["orientacion"] as? [String: Any] ?? [:]
            orientacion["modo"] = "otro"
            estaciones[0]["orientacion"] = orientacion
            objeto["estaciones"] = estaciones
        }
        for json in ["no es json", "", "[]", sinModo, FixturesParidad.metro] {
            responder(200, json)
            await esperarError(.respuestaIncompatible) { try await self.cliente().estacionesCercanas(self.lectura) }
        }
        responder(200, String(repeating: " ", count: ClientePlanificadorHTTP.maximoBytesRespuesta + 1))
        await esperarError(.respuestaIncompatible) { try await self.cliente().estacionesCercanas(self.lectura) }
    }

    func testSinConexionPlazoYCancelacion() async {
        ProtocoloSimulado.manejador = { _ in .fallar(.notConnectedToInternet) }
        await esperarError(.sinConexion) { try await self.cliente().estacionesCercanas(self.lectura) }
        ProtocoloSimulado.manejador = { _ in .colgar }
        await esperarError(.tiempoAgotado) { try await self.cliente(esperaMaxima: 0.3).estacionesCercanas(self.lectura) }

        let cliente = self.cliente(esperaMaxima: 30)
        let lectura = self.lectura
        let tarea = Task { try await cliente.estacionesCercanas(lectura) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        tarea.cancel()
        do {
            _ = try await tarea.value
            XCTFail("se esperaba cancelación")
        } catch {
            XCTAssertEqual(error as? ErrorConsulta, .cancelada)
        }
    }

    func testLasPeticionesNuevasSeCodificanConLasClavesDelContrato() throws {
        func codificada(_ peticion: PeticionPlanificador) throws -> NSDictionary {
            let datos = try JSONEncoder().encode(peticion)
            return try XCTUnwrap(try JSONSerialization.jsonObject(with: datos) as? NSDictionary)
        }
        XCTAssertEqual(try codificada(.metroLinea1), ["operacion": "metro-linea-1"])
        XCTAssertEqual(try codificada(.estacionesCercanas(lectura)), try objeto(FixturesParidad.peticionCercanas))
        XCTAssertNotNil(try? PeticionPlanificador.metroLinea1.validada().get())
    }
}
