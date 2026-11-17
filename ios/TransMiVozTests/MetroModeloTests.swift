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

    // MARK: Narración del estado (web: `MetroList` lo dice al entrar)

    private func cargado(locutor: LocutorFalso) async throws -> (MetroModelo, ClientePlanificadorFalso) {
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente, locutor: locutor)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        cliente.metros.responder(.success(try metro()))
        let esperado = try metro()
        await esperarHasta("el catálogo") { modelo.estado == .listo(esperado) }
        return (modelo, cliente)
    }

    func testAlEntrarDiceElMismoTextoDeLaNotaUnaVezYSinAnunciarloConVoiceOver() async throws {
        let locutor = LocutorFalso()
        let (modelo, _) = try await cargado(locutor: locutor)
        XCTAssertEqual(locutor.dichos, [try metro().textoEstado], "las mismas palabras que la nota de la pantalla")
        XCTAssertEqual(locutor.anunciosConVoiceOver, [false], "VoiceOver ya lee la nota: no hay doble locución")
        XCTAssertEqual(locutor.dichos.count, 1, "una sola vez por visita")
    }

    func testNoSeNarraSiLaPantallaYaNoEstaAVista() async throws {
        let locutor = LocutorFalso()
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente, locutor: locutor)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        modelo.alDesaparecer() // la persona salió antes de que llegara el catálogo
        cliente.metros.responder(.success(try metro()))
        await dejarPasar()
        XCTAssertTrue(locutor.dichos.isEmpty)
    }

    func testAlSalirCortaSoloSuPropiaFraseYSeVuelveANarrarEnLaVisitaSiguiente() async throws {
        let locutor = LocutorFalso()
        let (modelo, _) = try await cargado(locutor: locutor)
        modelo.alDesaparecer()
        XCTAssertEqual(locutor.cortes, 1)
        modelo.alAparecer() // el catálogo ya está: no vuelve a pedirlo y sí a decirlo
        XCTAssertEqual(locutor.dichos.count, 2)
    }

    func testSiSuenaOtroAvisoNoSeDiceNiSeAvisaYRepetirExplicaPorQue() async throws {
        let locutor = LocutorFalso()
        locutor.resultado = .ocupada
        let (modelo, _) = try await cargado(locutor: locutor)
        XCTAssertNil(modelo.avisoVoz, "al entrar no se avisa de nada: la nota está en pantalla")
        modelo.repetirEstado()
        XCTAssertEqual(modelo.avisoVoz, TextoMetro.vozOcupada)
        locutor.resultado = .hablada // el aviso terminó
        modelo.repetirEstado()
        XCTAssertNil(modelo.avisoVoz)
        XCTAssertEqual(locutor.dichos.last, try metro().textoEstado)
    }

    func testConLaVozDeLaAppApagadaRepetirLoDiceYLaNotaSigueEnPantalla() async throws {
        let locutor = LocutorFalso()
        locutor.resultado = .silenciada
        let (modelo, _) = try await cargado(locutor: locutor)
        modelo.repetirEstado()
        XCTAssertEqual(modelo.avisoVoz, TextoMetro.vozApagada)
        XCTAssertTrue(TextoMetro.vozApagada.contains("VoiceOver"))
        XCTAssertEqual(locutor.anunciosConVoiceOver.last, false)
    }

    func testSinCatalogoNoHayNadaQueNarrarNiRepetir() async {
        let locutor = LocutorFalso()
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente, locutor: locutor)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        modelo.repetirEstado()
        XCTAssertTrue(locutor.dichos.isEmpty)
        XCTAssertFalse(modelo.puedeRepetirEstado)
        cliente.metros.responder(.failure(ErrorConsulta.sinConexion))
        await esperarHasta("el fallo") { modelo.estado == .fallo(.sinConexion) }
        XCTAssertTrue(locutor.dichos.isEmpty, "un error no se narra como si fuera el estado del Metro")
    }

    func testSinVozNoHayBotonDeRepetirYNadaRevienta() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        cliente.metros.responder(.success(try metro()))
        let esperado = try metro()
        await esperarHasta("el catálogo") { modelo.estado == .listo(esperado) }
        XCTAssertFalse(modelo.puedeRepetirEstado)
        modelo.repetirEstado()
        modelo.alDesaparecer()
    }

    func testUnReintentoTrasUnFalloNarraUnaVezAlCargar() async throws {
        let locutor = LocutorFalso()
        let cliente = ClientePlanificadorFalso()
        let modelo = MetroModelo(cliente: cliente, locutor: locutor)
        modelo.alAparecer()
        await cliente.metros.esperar(1)
        cliente.metros.responder(.failure(ErrorConsulta.tiempoAgotado))
        await esperarHasta("el fallo") { modelo.estado == .fallo(.tiempoAgotado) }
        modelo.cargar()
        await cliente.metros.esperar(2)
        cliente.metros.responder(.success(try metro()), indice: 1)
        await esperarHasta("lo dicho") { locutor.dichos.count == 1 }
        XCTAssertEqual(locutor.dichos, [try metro().textoEstado])
    }
}

/// Qué huella tocó la persona y si un toque cayó sobre el trazado: geometría pura, sin MapKit.
final class CapaMetroToquesTests: XCTestCase {
    private func capa() throws -> CapaMetro { CapaMetro(try decodificarPlanificador(FixturesParidad.metro) as RespuestaMetro) }

    func testUnToqueDentroDeUnaHuellaDiceCualEs() throws {
        let capa = try capa()
        // Centro de la estación n del fixture: (4,60 + (n-1)·0,008; -74,14 + (n-1)·0,004); la huella es un cuadrado de ±0,0006.
        func centro(_ n: Int) -> Coordenada { Coordenada(latitud: 4.60 + Double(n - 1) * 0.008, longitud: -74.14 + Double(n - 1) * 0.004) }
        for n in [1, 7, 16] {
            XCTAssertEqual(capa.huella(en: centro(n))?.id, String(format: "E%02d", n))
        }
        XCTAssertEqual(capa.huella(en: centro(7))?.etiqueta, "E07 · nombre pendiente: huella ilustrativa del proyecto; no es una entrada")
    }

    func testUnToqueFueraDeTodasLasHuellasNoDiceNada() throws {
        let capa = try capa()
        XCTAssertNil(capa.huella(en: Coordenada(latitud: 4.604, longitud: -74.138))) // entre dos huellas
        XCTAssertNil(capa.huella(en: Coordenada(latitud: 40, longitud: -70)))
        let primera = try XCTUnwrap(capa.huellas.first)
        XCTAssertFalse(primera.contiene(Coordenada(latitud: 4.6007, longitud: -74.14))) // apenas fuera del cuadrado
        XCTAssertTrue(primera.contiene(Coordenada(latitud: 4.6005, longitud: -74.14)))
    }

    func testUnAnilloSinPuntosNoContieneNada() {
        XCTAssertFalse(HuellaMetro(id: "E01", etiqueta: "x", anillo: []).contiene(Coordenada(latitud: 1, longitud: 1)))
    }

    func testDistanciaDeUnToqueAlTrazadoEnPantalla() {
        let linea: [(x: Double, y: Double)] = [(0, 0), (100, 0), (100, 100)]
        XCTAssertEqual(GeometriaDeToque.distancia(del: (x: 50, y: 10), alTrazado: linea) ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(GeometriaDeToque.distancia(del: (x: 110, y: 50), alTrazado: linea) ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(GeometriaDeToque.distancia(del: (x: -30, y: 40), alTrazado: linea) ?? -1, 50, accuracy: 0.0001, "antes del primer punto: al extremo")
        XCTAssertNil(GeometriaDeToque.distancia(del: (x: 1, y: 1), alTrazado: [(0, 0)]), "un punto solo no es un trazado")
        XCTAssertEqual(GeometriaDeToque.distancia(del: (x: 3, y: 4), alSegmento: (0, 0), (0, 0)), 5, accuracy: 0.0001, "segmento de largo cero")
    }
}
