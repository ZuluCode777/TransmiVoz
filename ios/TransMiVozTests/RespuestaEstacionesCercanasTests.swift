import XCTest
@testable import TransMiVoz

/// Decodificación de `estaciones-cercanas`: el cliente valida la forma y el orden de los modos, no calcula nada.
final class RespuestaEstacionesCercanasTests: XCTestCase {
    private func decodificar(_ json: String) throws -> RespuestaEstacionesCercanas { try decodificarPlanificador(json) }

    private func rechaza(_ json: String, _ mensaje: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decodificar(json), mensaje, file: file, line: line) {
            XCTAssertEqual($0 as? ErrorConsulta, .respuestaIncompatible, mensaje, file: file, line: line)
        }
    }

    /// Cambia la primera estación de un fixture.
    private func conPrimera(_ json: String, _ cambio: @escaping (inout [String: Any]) -> Void) -> String {
        modificar(json) { objeto in
            var estaciones = objeto["estaciones"] as? [[String: Any]] ?? []
            cambio(&estaciones[0])
            objeto["estaciones"] = estaciones
        }
    }

    func testLasEstacionesLlegandoDeMasCercanaAMasLejanaConSuOrientacion() throws {
        let r = try decodificar(FixturesParidad.cercanasRelativa)
        XCTAssertEqual(r.resultado, .cercanas)
        XCTAssertEqual(r.estaciones.map(\.nombre), ["Estación Ejemplo Centro", "Estación Ejemplo Norte"])
        let primera = r.estaciones[0]
        XCTAssertEqual(primera.distanciaMetros, 40)
        XCTAssertEqual(primera.distanciaHablada, "40 metros")
        XCTAssertEqual(primera.coordenada, Coordenada(latitud: 4.6504, longitud: -74.0851))
        XCTAssertEqual(primera.orientacion.modo, .relativa)
        XCTAssertEqual(primera.orientacion.cardinal, "al norte")
        XCTAssertEqual(primera.orientacion.relativa, "de frente")
        XCTAssertEqual(r.catalogo.antiguo, false)
    }

    func testMuyCercaSeLeeDelServidor() throws {
        let r = try decodificar(FixturesParidad.cercanasMuyCerca)
        XCTAssertTrue(r.estaciones[0].muyCerca)
        XCTAssertFalse(r.estaciones[1].muyCerca, "ausente vale false")
        XCTAssertFalse(try decodificar(FixturesParidad.cercanasRelativa).estaciones[0].muyCerca)
    }

    func testUnServidorAnteriorSinMuyCercaSigueSiendoValidoYNuncaAvisaDeCercania() throws {
        let r = try decodificar(FixturesParidad.cercanasServidorAnterior)
        XCTAssertEqual(r.estaciones.count, 2)
        XCTAssertTrue(r.estaciones.allSatisfy { !$0.muyCerca })
        // `null` se trata como ausente, no como un valor.
        let nulo = conPrimera(FixturesParidad.cercanasServidorAnterior) { $0["muyCerca"] = NSNull() }
        XCTAssertFalse(try decodificar(nulo).estaciones[0].muyCerca)
    }

    func testMuyCercaQueNoEsBooleanoSeRechaza() {
        for valor: Any in ["true", 1, ["a": 1]] {
            rechaza(conPrimera(FixturesParidad.cercanasMuyCerca) { $0["muyCerca"] = valor }, "muyCerca no booleano")
        }
    }

    func testCadaModoDeOrientacionDecodificaConSuReferencia() throws {
        let cardinal = try decodificar(FixturesParidad.cercanasCardinal).estaciones[0].orientacion
        XCTAssertEqual(cardinal.modo, .cardinalPrecision)
        XCTAssertEqual(cardinal.cardinal, "al norte")
        XCTAssertNil(cardinal.relativa)

        let sinDireccion = try decodificar(FixturesParidad.cercanasSinDireccion).estaciones[0].orientacion
        XCTAssertEqual(sinDireccion.modo, .sinDireccion)
        XCTAssertNil(sinDireccion.cardinal)
        XCTAssertNil(sinDireccion.relativa)
    }

    func testUnaUbicacionVencidaNoTraeEstaciones() throws {
        let r = try decodificar(FixturesParidad.cercanasVencida)
        XCTAssertEqual(r.resultado, .ubicacionVencida)
        XCTAssertTrue(r.estaciones.isEmpty)
        let conEstaciones = modificar(FixturesParidad.cercanasVencida) { objeto in
            objeto["estaciones"] = (try? JSONSerialization.jsonObject(with: Data(FixturesParidad.cercanasRelativa.utf8)) as? [String: Any])?["estaciones"] ?? []
        }
        rechaza(conEstaciones, "vencida con estaciones")
    }

    func testSinEstacionesEsUnaRespuestaValida() throws {
        let r = try decodificar(FixturesParidad.cercanasVacia)
        XCTAssertEqual(r.resultado, .cercanas)
        XCTAssertTrue(r.estaciones.isEmpty)
    }

    func testLoQueElContratoNoPermiteSeRechaza() {
        rechaza(modificar(FixturesParidad.cercanasRelativa) { $0["resultado"] = "otra-cosa" }, "resultado desconocido")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) {
            var o = $0["orientacion"] as? [String: Any] ?? [:]
            o["modo"] = "adivinando"
            $0["orientacion"] = o
        }, "modo desconocido")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) {
            var o = $0["orientacion"] as? [String: Any] ?? [:]
            o["relativa"] = NSNull()
            $0["orientacion"] = o
        }, "modo relativa sin giro")
        rechaza(conPrimera(FixturesParidad.cercanasCardinal) {
            var o = $0["orientacion"] as? [String: Any] ?? [:]
            o["relativa"] = "a tu derecha"
            $0["orientacion"] = o
        }, "giro con un modo que no es relativa")
        rechaza(conPrimera(FixturesParidad.cercanasSinDireccion) {
            var o = $0["orientacion"] as? [String: Any] ?? [:]
            o["cardinal"] = "al norte"
            $0["orientacion"] = o
        }, "dirección dentro del margen de error")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) { $0["distanciaMetros"] = -1 }, "distancia negativa")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) { $0["distanciaMetros"] = 40.5 }, "distancia no entera")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) { $0["distanciaHablada"] = " " }, "distancia hablada vacía")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) { $0["nombre"] = "" }, "nombre vacío")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) { $0["coordenada"] = ["lat": 95.0, "lng": -74.0] }, "latitud fuera de rango")
        rechaza(conPrimera(FixturesParidad.cercanasRelativa) { $0.removeValue(forKey: "orientacion") }, "sin orientación")
        rechaza(modificar(FixturesParidad.cercanasRelativa) { $0.removeValue(forKey: "catalogo") }, "sin catálogo")
        rechaza(modificar(FixturesParidad.cercanasRelativa) { objeto in
            let estaciones = objeto["estaciones"] as? [[String: Any]] ?? []
            objeto["estaciones"] = Array(repeating: estaciones[0], count: RespuestaEstacionesCercanas.maximoEstaciones + 1)
        }, "más de 4 estaciones")
    }

    func testUnaClaveNuevaDelServidorNoRompeLaRespuesta() throws {
        let json = conPrimera(modificar(FixturesParidad.cercanasRelativa) { $0["campoFuturo"] = 1 }) { $0["otroCampoFuturo"] = ["x": 1] }
        XCTAssertEqual(try decodificar(json).estaciones.count, 2)
    }

    func testElTextoDelServidorQueDescribeUnaPosicionNoSeConfundeConLaNuestra() throws {
        // La respuesta no repite la coordenada, la precisión ni el rumbo enviados: no hay dónde leerlos.
        let r = try decodificar(FixturesParidad.cercanasRelativa)
        let reflejo = String(describing: Mirror(reflecting: r).children.map(\.label))
        XCTAssertFalse(reflejo.contains("precision"))
        XCTAssertFalse(reflejo.contains("rumbo"))
    }
}
