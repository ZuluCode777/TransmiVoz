import XCTest
@testable import TransMiVoz

/// El locutor de las pantallas «Metro de Bogotá» y «Mapa y GPS» sobre la `ControlVoz` REAL con una salida de voz simulada: nada
/// de audio. La cola de `ControlVoz` es de uno y, con la misma prioridad, una locución nueva CORTA a la que suena: el locutor no
/// debe cortar ninguna ajena, tampoco la de rutina de un accesorio.
@MainActor
final class LocutorControlVozTests: XCTestCase {
    /// Salida de voz de mentira que anota lo que se le pidió y cuántas veces se cortó.
    @MainActor
    private final class SalidaFalsa: SalidaVoz {
        private(set) var hablando = false
        private(set) var dichas: [String] = []
        private(set) var cortes = 0
        func hablar(_ texto: String) -> ResultadoHabla {
            dichas.append(texto)
            hablando = true
            return .iniciada
        }
        func detener() {
            if hablando { cortes += 1 }
            hablando = false
        }
        func terminar() { hablando = false }
    }

    private func banco(ruta: RutaAudio = .privada) -> (voz: ControlVoz, salida: SalidaFalsa, anunciados: Anunciados, locutor: LocutorControlVoz) {
        let salida = SalidaFalsa()
        let voz = ControlVoz(salida: salida, consultarRuta: { ruta })
        let anunciados = Anunciados()
        let locutor = LocutorControlVoz(voz: voz, anunciador: { anunciados.textos.append($0) })
        return (voz, salida, anunciados, locutor)
    }

    @MainActor final class Anunciados { var textos: [String] = [] }

    func testDiceLaFraseSiNoSuenaNadaMas() async throws {
        let b = banco()
        XCTAssertEqual(b.locutor.decir("hola"), .hablada)
        XCTAssertEqual(b.salida.dichas, ["hola"])
        XCTAssertTrue(b.anunciados.textos.isEmpty)
    }

    func testUnAvisoDeRutinaDelAccesorioNoSeCorta() async throws {
        let b = banco()
        b.voz.anunciar("aviso de rutina del accesorio") // la misma prioridad que la del locutor
        XCTAssertTrue(b.salida.hablando)
        XCTAssertEqual(b.locutor.decir("orientación"), .ocupada)
        XCTAssertEqual(b.locutor.decir("estado", anunciarConVoiceOver: false), .ocupada)
        XCTAssertEqual(b.salida.dichas, ["aviso de rutina del accesorio"], "la frase no se dijo")
        XCTAssertEqual(b.salida.cortes, 0, "el aviso del accesorio sigue sonando entero")
        XCTAssertTrue(b.anunciados.textos.isEmpty, "ni se anuncia con VoiceOver encima del aviso")
    }

    func testUnAvisoUrgenteTampocoSeCorta() async throws {
        let b = banco()
        b.voz.anunciar("proximidad", prioridad: .urgente)
        XCTAssertEqual(b.locutor.decir("orientación"), .ocupada)
        XCTAssertEqual(b.salida.cortes, 0)
    }

    func testUnaRespuestaDeLaConsultaQueSuenaNoSeCorta() async throws {
        let b = banco()
        b.voz.anunciar("respuesta de la consulta") // la consulta habla con `ControlVoz.anunciar` sin prioridad propia
        XCTAssertEqual(b.locutor.decir("estado"), .ocupada)
        XCTAssertEqual(b.salida.cortes, 0)
    }

    func testPuedeReemplazarSuPropiaFraseYSoloCortaLaPropia() async throws {
        let b = banco()
        XCTAssertEqual(b.locutor.decir("primera"), .hablada)
        XCTAssertEqual(b.locutor.decir("segunda"), .hablada, "la propia sí se reemplaza")
        XCTAssertEqual(b.salida.dichas, ["primera", "segunda"])
        b.locutor.cortarLoPropio()
        XCTAssertFalse(b.salida.hablando)
        XCTAssertEqual(b.salida.cortes, 2)
    }

    func testCortarLoPropioNoToca_UnaLocucionAjenaPosterior() async throws {
        let b = banco()
        b.locutor.decir("mía")
        b.salida.terminar()
        b.voz.anunciar("aviso del accesorio") // habló otro después
        let cortesAntes = b.salida.cortes
        b.locutor.cortarLoPropio()
        XCTAssertTrue(b.salida.hablando, "el aviso ajeno sigue")
        XCTAssertEqual(b.salida.cortes, cortesAntes)
    }

    func testCortarSinHaberDichoNadaNoHaceNada() async throws {
        let b = banco()
        b.voz.anunciar("ajena")
        b.locutor.cortarLoPropio()
        XCTAssertTrue(b.salida.hablando)
        XCTAssertEqual(b.salida.cortes, 0)
    }

    func testConLaVozApagadaSeAnunciaConVoiceOverSoloSiSePide() async throws {
        let b = banco()
        b.voz.permitida = { false } // VoiceOver activo sin haberla encendido, o apagada por la persona
        XCTAssertEqual(b.locutor.decir("orientación"), .anunciada)
        XCTAssertEqual(b.anunciados.textos, ["orientación"])
        XCTAssertEqual(b.locutor.decir("estado", anunciarConVoiceOver: false), .silenciada)
        XCTAssertEqual(b.anunciados.textos, ["orientación"], "una frase que VoiceOver ya lee en pantalla no se dice dos veces")
        XCTAssertTrue(b.salida.dichas.isEmpty)
    }

    func testConUnaSalidaNoPrivadaSeAnunciaConVoiceOverSoloSiSePide() async throws {
        let b = banco(ruta: .noPrivada)
        XCTAssertEqual(b.locutor.decir("orientación"), .anunciada)
        XCTAssertEqual(b.locutor.decir("estado", anunciarConVoiceOver: false), .silenciada)
        XCTAssertTrue(b.salida.dichas.isEmpty)
    }

    func testUnaInterrupcionDelSistemaNoSeRodeaConVoiceOver() async throws {
        let b = banco()
        b.voz.interrupcion(comenzo: true)
        XCTAssertEqual(b.locutor.decir("orientación"), .ocupada)
        XCTAssertTrue(b.anunciados.textos.isEmpty)
    }

    func testSinControlVozSoloAnunciaConVoiceOver() async throws {
        let anunciados = Anunciados()
        let locutor = LocutorControlVoz(voz: nil, anunciador: { anunciados.textos.append($0) })
        XCTAssertEqual(locutor.decir("a"), .anunciada)
        XCTAssertEqual(locutor.decir("b", anunciarConVoiceOver: false), .silenciada)
        XCTAssertEqual(anunciados.textos, ["a"])
        locutor.cortarLoPropio() // no revienta
    }

    func testElResultadoDiceSiLlegoALaPersona() async throws {
        XCTAssertTrue(ResultadoLocucion.hablada.seDijo)
        XCTAssertTrue(ResultadoLocucion.anunciada.seDijo)
        XCTAssertFalse(ResultadoLocucion.ocupada.seDijo)
        XCTAssertFalse(ResultadoLocucion.silenciada.seDijo)
    }
}
