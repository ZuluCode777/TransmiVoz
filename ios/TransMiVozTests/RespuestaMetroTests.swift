import XCTest
@testable import TransMiVoz

/// Decodificación estricta de `metro-linea-1`: lo que el contrato fija se exige y lo que el Metro no tiene (centroide, accesos,
/// servicio comercial) no se acepta ni se inventa.
final class RespuestaMetroTests: XCTestCase {
    private func decodificar(_ json: String) throws -> RespuestaMetro { try decodificarPlanificador(json) }

    private func rechaza(_ json: String, _ mensaje: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decodificar(json) as RespuestaMetro, mensaje, file: file, line: line) {
            XCTAssertEqual($0 as? ErrorConsulta, .respuestaIncompatible, mensaje, file: file, line: line)
        }
    }

    func testElCatalogoValidoTrae16EstacionesYNoTieneServicio() throws {
        let metro = try decodificar(FixturesParidad.metro)
        XCTAssertEqual(metro.estaciones.count, 16)
        XCTAssertEqual(metro.estaciones.map(\.id), (1...16).map { String(format: "E%02d", $0) })
        XCTAssertFalse(metro.linea.servicioComercial)
        XCTAssertEqual(metro.linea.subtitulo, "Línea 1 · en construcción · sin servicio")
        XCTAssertTrue(metro.textoEstado.contains("sin servicio comercial"))
        XCTAssertEqual(metro.mapa.licencia, "CC BY 4.0")
        XCTAssertEqual(metro.mapa.fechaDato, "2022-01-01")
        XCTAssertEqual(metro.mapa.consultado, "2026-01-01")
        XCTAssertEqual(metro.corte.fecha, "2026-01-01")
        XCTAssertEqual(metro.fuentes.map(\.id), ["F1", "F2"])
    }

    func testLaEstacionSinNombrePublicoSeConservaSinInventarselo() throws {
        let e07 = try decodificar(FixturesParidad.metro).estaciones[6]
        XCTAssertNil(e07.nombre)
        XCTAssertEqual(e07.nombreMostrado, "nombre pendiente")
        XCTAssertEqual(e07.nombreEstado, .pendiente)
    }

    func testLaCapaDelMapaSoloTieneTrazadoYHuellasSinUnPuntoPorEstacion() throws {
        let metro = try decodificar(FixturesParidad.metro)
        let capa = CapaMetro(metro)
        XCTAssertEqual(capa.huellas.map(\.id), metro.estaciones.map(\.id))
        XCTAssertEqual(capa.trazado, metro.mapa.trazado)
        XCTAssertEqual(capa.rotulo, metro.mapa.rotulo)
        XCTAssertEqual(capa.atribucionCorta, metro.mapa.atribucionCorta)
        // Todo lo dibujable son el trazado y los anillos: no hay otra fuente de puntos (ni centroide, ni acceso).
        XCTAssertEqual(capa.coordenadas.count, metro.mapa.trazado.count + metro.estaciones.reduce(0) { $0 + $1.huella.count })
        XCTAssertEqual(capa.huellas[0].etiqueta, metro.estaciones[0].etiquetaHuella)
        XCTAssertTrue(capa.huellas.allSatisfy { $0.etiqueta.contains("no es una entrada") })
    }

    func testServicioComercialTrueEsIncompatible() {
        let json = modificar(FixturesParidad.metro) { objeto in
            var linea = objeto["linea"] as? [String: Any] ?? [:]
            linea["servicioComercial"] = true
            objeto["linea"] = linea
        }
        rechaza(json, "servicioComercial: true")
    }

    func testUnNumeroDeEstacionesDistintoDe16SeRechaza() {
        rechaza(modificar(FixturesParidad.metro) { objeto in
            objeto["estaciones"] = Array((objeto["estaciones"] as? [Any] ?? []).dropLast())
        }, "15 estaciones")
        rechaza(modificar(FixturesParidad.metro) { objeto in
            let estaciones = objeto["estaciones"] as? [Any] ?? []
            objeto["estaciones"] = estaciones + [estaciones[0]]
        }, "17 estaciones")
    }

    func testElIdentificadorYElNumeroDeCadaEstacionDebenCoincidirConSuPosicion() {
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var estaciones = objeto["estaciones"] as? [[String: Any]] ?? []
            estaciones[2]["id"] = "E09"
            objeto["estaciones"] = estaciones
        }, "id que no corresponde")
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var estaciones = objeto["estaciones"] as? [[String: Any]] ?? []
            estaciones[2]["numero"] = 4
            objeto["estaciones"] = estaciones
        }, "número que no corresponde")
    }

    func testLasCotasDeGeometriaSeHacenCumplir() {
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var estaciones = objeto["estaciones"] as? [[String: Any]] ?? []
            estaciones[0]["huella"] = Array((estaciones[0]["huella"] as? [Any] ?? []).prefix(3))
            objeto["estaciones"] = estaciones
        }, "huella de 3 puntos")
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var mapa = objeto["mapa"] as? [String: Any] ?? [:]
            mapa["trazado"] = Array((mapa["trazado"] as? [Any] ?? []).prefix(1))
            objeto["mapa"] = mapa
        }, "trazado de un punto")
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var mapa = objeto["mapa"] as? [String: Any] ?? [:]
            mapa["trazado"] = Array(repeating: ["lat": 4.6, "lng": -74.1], count: RespuestaMetro.maximoPuntosTrazado + 1)
            objeto["mapa"] = mapa
        }, "trazado de más de 500 puntos")
    }

    func testUnaCoordenadaFueraDeRangoSeRechaza() {
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var mapa = objeto["mapa"] as? [String: Any] ?? [:]
            var trazado = mapa["trazado"] as? [[String: Any]] ?? []
            trazado[0]["lat"] = 91.0
            mapa["trazado"] = trazado
            objeto["mapa"] = mapa
        }, "latitud 91")
    }

    func testFechasTextosYCamposObligatoriosSeValidan() {
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var mapa = objeto["mapa"] as? [String: Any] ?? [:]
            mapa["fechaDato"] = "18/04/2022"
            objeto["mapa"] = mapa
        }, "fecha no ISO")
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var corte = objeto["corte"] as? [String: Any] ?? [:]
            corte["fecha"] = "ayer"
            objeto["corte"] = corte
        }, "corte no ISO")
        rechaza(modificar(FixturesParidad.metro) { $0["textoEstado"] = "  " }, "texto de estado vacío")
        rechaza(modificar(FixturesParidad.metro) { $0["atribucion"] = String(repeating: "a", count: RespuestaMetro.maximoTexto + 1) }, "texto desmedido")
        rechaza(modificar(FixturesParidad.metro) { $0.removeValue(forKey: "mapa") }, "sin mapa")
        rechaza(modificar(FixturesParidad.metro) { $0.removeValue(forKey: "linea2") }, "sin Línea 2")
        rechaza(modificar(FixturesParidad.metro) { objeto in
            var mapa = objeto["mapa"] as? [String: Any] ?? [:]
            mapa.removeValue(forKey: "atribucion")
            objeto["mapa"] = mapa
        }, "sin atribución")
    }

    func testUnaClaveQueElClienteNoConoceNoLaRechaza() throws {
        let json = modificar(FixturesParidad.metro) { $0["campoFuturo"] = ["a": 1] }
        XCTAssertEqual(try decodificar(json).estaciones.count, 16)
    }

    func testSoloLosEnlacesHttpsDeLasFuentesSeAbren() throws {
        let fuentes = try decodificar(FixturesParidad.metro).fuentes
        XCTAssertNotNil(fuentes[0].enlace)
        func fuente(_ url: String) -> FuenteMetro {
            FuenteMetro(id: "F9", entidad: "e", titulo: "t", fecha: "f", url: url, texto: "x")
        }
        XCTAssertNil(fuente("http://servidor.ejemplo/a").enlace)
        XCTAssertNil(fuente("javascript:alert(1)").enlace)
        XCTAssertNil(fuente("tel:123").enlace)
        XCTAssertNil(fuente("no es una url").enlace)
        XCTAssertNil(fuente("https://").enlace)
    }
}
