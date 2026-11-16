import XCTest
@testable import TransMiVoz

/// Carga del Metro: una sola petición vigente, sin sondeo, errores honestos y nada que llegue tarde.
@MainActor
final class MetroModeloTests: XCTestCase {
    private func metro() throws -> RespuestaMetro { try decodificarPlanificador(FixturesParidad.metro) }

    func testAlAparecerPideElCatalogoUnaVezYLoMuestra() async throws {
        let esperado = try metro()
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        XCTAssertEqual(modelo.estado, .inactivo)
        modelo.alAparecer()
        XCTAssertEqual(modelo.estado, .cargando)
        await cliente.metros.esperar(1)
        XCTAssertEqual(cliente.metros.argumentos, ["metro-linea-1"])
        cliente.metros.responder(.success(try metro()))
        await esperarHasta("el catálogo") { modelo.estado == .listo(esperado) }

        modelo.alAparecer() // volver a la pantalla no repite la petición: el catálogo solo cambia con un despliegue
        await dejarPasar()
        XCTAssertEqual(cliente.metros.argumentos.count, 1)
    }

    func testUnErrorSeMuestraYReintentarVuelveAPedir() async throws {
        let esperado = try metro()
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        cliente.metros.responder(.failure(ErrorConsulta.sinConexion))
        await esperarHasta("el fallo") { modelo.estado == .fallo(.sinConexion) }

        modelo.cargar()
        XCTAssertEqual(modelo.estado, .cargando)
        await cliente.metros.esperar(2)
        cliente.metros.responder(.success(try metro()), indice: 1)
        await esperarHasta("el catálogo") { modelo.estado == .listo(esperado) }
    }

    func testUnFalloSePuedeReintentarAlVolverAEntrar() async {
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        cliente.metros.responder(.failure(ErrorConsulta.tiempoAgotado))
        await esperarHasta("el fallo") { modelo.estado == .fallo(.tiempoAgotado) }
        modelo.alAparecer()
        await cliente.metros.esperar(2)
        XCTAssertEqual(cliente.metros.argumentos.count, 2)
    }

    func testUnServidorAnteriorDa400YTextoPropio() {
        let texto = TextoMetro.mensaje(de: .peticionRechazada)
        XCTAssertEqual(texto, TextoMetro.servidorAnterior)
        XCTAssertTrue(texto.contains("400"))
        XCTAssertTrue(texto.contains("versión anterior del servidor"))
        // Los demás errores usan su propio mensaje y su recuperación.
        XCTAssertEqual(TextoMetro.mensaje(de: .sinConexion), "\(ErrorConsulta.sinConexion.mensaje) \(ErrorConsulta.sinConexion.recuperacion)")
        XCTAssertEqual(TextoMetro.mensaje(de: .noAutorizado), "\(ErrorConsulta.noAutorizado.mensaje) \(ErrorConsulta.noAutorizado.recuperacion)")
    }

    func testSalirDescartaLaPeticionYLaRespuestaTardiaNoSeAplica() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        modelo.alDesaparecer()
        XCTAssertEqual(modelo.estado, .inactivo)
        cliente.metros.responder(.success(try metro())) // el servidor contesta tarde
        await dejarPasar()
        XCTAssertEqual(modelo.estado, .inactivo, "lo que llega tras salir no se aplica")

        modelo.alAparecer() // al volver, pide de nuevo
        await cliente.metros.esperar(2)
        XCTAssertEqual(modelo.estado, .cargando)
    }

    func testSalirConElCatalogoYaCargadoLoConserva() async throws {
        let esperado = try metro()
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        cliente.metros.responder(.success(try metro()))
        await esperarHasta("el catálogo") { modelo.estado == .listo(esperado) }
        modelo.alDesaparecer()
        XCTAssertEqual(modelo.estado, .listo(try metro()))
    }

    func testReintentarReemplazaLaPeticionAnteriorYGanaLaUltima() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        modelo.cargar()
        await cliente.metros.esperar(1)
        modelo.cargar()
        await cliente.metros.esperar(2)
        cliente.metros.responder(.failure(ErrorConsulta.errorDelServidor(estado: 500)), indice: 1)
        await esperarHasta("el fallo de la última") { modelo.estado == .fallo(.errorDelServidor(estado: 500)) }
        cliente.metros.responder(.success(try metro()), indice: 0) // la primera llega DESPUÉS
        await dejarPasar()
        XCTAssertEqual(modelo.estado, .fallo(.errorDelServidor(estado: 500)))
    }

    func testResaltarSoloAceptaEstacionesDelCatalogoCargado() async throws {
        let esperado = try metro()
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        modelo.resaltar("E01")
        XCTAssertNil(modelo.resaltada, "sin catálogo no hay nada que resaltar")
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        cliente.metros.responder(.success(try metro()))
        await esperarHasta("el catálogo") { modelo.estado == .listo(esperado) }
        modelo.resaltar("E03")
        XCTAssertEqual(modelo.resaltada, "E03")
        modelo.resaltar("E99")
        XCTAssertEqual(modelo.resaltada, "E03", "una huella que no existe no cambia nada")
        modelo.resaltar(nil)
        XCTAssertNil(modelo.resaltada)
    }

    /// Mientras no hay catálogo (cargando) la pantalla solo dice lo que es cierto siempre: proyecto en construcción y sin servicio.
    func testMientrasCargaLaPantallaYaDiceQueNoHayServicio() {
        XCTAssertTrue(TextoMetro.cargando.contains("en construcción y sin servicio"))
    }
}
