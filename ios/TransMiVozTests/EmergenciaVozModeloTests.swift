import XCTest
@testable import TransMiVoz

/// La introducción hablada de Emergencia pasa por la misma `ControlVoz` que los avisos del accesorio y la consulta: sigue sus
/// reglas y no abre otra cola de voz. La salida de voz es un doble: no prueba la síntesis ni los auriculares.
@MainActor
final class EmergenciaVozModeloTests: XCTestCase {
    private func banco(ruta: RutaAudio = .privada) -> (ControlVoz, SalidaVozFalsa, EmergenciaVozModelo) {
        let salida = SalidaVozFalsa()
        let voz = ControlVoz(salida: salida, consultarRuta: { ruta })
        return (voz, salida, EmergenciaVozModelo(voz: voz))
    }

    func testLaIntroduccionSaleDeLaVozCompartidaYContaComoSuLocucion() async {
        let (voz, salida, modelo) = banco()
        modelo.decirIntroduccion()
        XCTAssertEqual(salida.dicho, [TextoEmergencia.introHablada])
        XCTAssertEqual(voz.locuciones, 1, "la locución se cuenta en la cola única de la app")
        XCTAssertEqual(modelo.resultado, TextoEmergencia.dichaEnVozAlta)
        modelo.decirIntroduccion()
        XCTAssertEqual(salida.dicho.count, 1, "mientras suena no se repite")
    }

    func testSinSalidaPrivadaOConLaVozApagadaNoHablaYSalirNoCortaNada() async {
        let (_, salidaAltavoz, sinAuriculares) = banco(ruta: .noPrivada)
        sinAuriculares.decirIntroduccion()
        sinAuriculares.salir()
        XCTAssertTrue(salidaAltavoz.dicho.isEmpty)
        XCTAssertTrue(salidaAltavoz.cortadas.isEmpty)
        XCTAssertEqual(sinAuriculares.resultado, TextoAvisos.noSeDijo(.rutaNoPrivada), "sin audio, la pantalla dice por qué")

        let (voz, salida, apagada) = banco()
        voz.permitida = { false }
        apagada.decirIntroduccion()
        apagada.salir()
        XCTAssertTrue(salida.dicho.isEmpty, "respeta la elección de la persona y VoiceOver, como toda voz de la app")
        XCTAssertTrue(salida.cortadas.isEmpty)
        XCTAssertEqual(apagada.resultado, TextoAvisos.noSeDijo(.vozApagada))
    }

    func testUnAvisoSonandoNoSeTapaNiSeCortaAlSalir() async {
        let (voz, salida, modelo) = banco()
        voz.anunciar("Objeto cerca.", prioridad: .urgente)
        modelo.decirIntroduccion()
        XCTAssertEqual(salida.dicho, ["Objeto cerca."], "la introducción cede ante el aviso del accesorio")
        XCTAssertEqual(modelo.resultado, TextoEmergencia.sonandoOtroAviso)
        modelo.salir()
        XCTAssertTrue(salida.cortadas.isEmpty, "salir no corta lo que no es suyo")
        XCTAssertTrue(salida.hablando, "el aviso sigue sonando")
    }

    func testSalirCortaSoloSuPropiaLocucion() async {
        let (voz, salida, modelo) = banco()
        modelo.decirIntroduccion()
        modelo.salir()
        XCTAssertFalse(salida.hablando)
        XCTAssertEqual(salida.cortadas, [TextoEmergencia.introHablada])

        // Si después habló otro (un aviso), la cola de uno ya cortó la introducción y salir no toca lo que suena.
        let (otraVoz, otraSalida, otro) = banco()
        otro.decirIntroduccion()
        otraVoz.anunciar("Pérdida del accesorio.", prioridad: .urgente)
        XCTAssertEqual(otraSalida.cortadas, [TextoEmergencia.introHablada], "el aviso urgente cortó la introducción")
        otro.salir()
        XCTAssertFalse(otraSalida.cortadas.contains("Pérdida del accesorio."))
        XCTAssertTrue(otraSalida.hablando)
        _ = voz
    }

    // MARK: «La app dijo» con «Repetir» (texto equivalente al audio)

    func testRepetirVuelveADecirLaIntroduccionPorLaMismaColaYCuentaLaRepeticion() async {
        let (voz, salida, modelo) = banco()
        modelo.decirIntroduccion()
        modelo.repetir()
        XCTAssertEqual(salida.dicho, [TextoEmergencia.introHablada, TextoEmergencia.introHablada])
        XCTAssertEqual(voz.locuciones, 2, "las dos son locuciones de la cola única de la app")
        XCTAssertEqual(salida.cortadas, [TextoEmergencia.introHablada], "la repetición reemplaza a la propia: cola de uno")
        XCTAssertEqual(modelo.repeticiones, 1)
        XCTAssertEqual(modelo.resultado, TextoEmergencia.dichaEnVozAlta)
    }

    func testRepetirSinSalidaPrivadaNoHablaYExplicaPorQue() async {
        let (_, salida, modelo) = banco(ruta: .noPrivada)
        modelo.repetir()
        XCTAssertTrue(salida.dicho.isEmpty)
        XCTAssertEqual(modelo.resultado, TextoAvisos.noSeDijo(.rutaNoPrivada))
        XCTAssertEqual(modelo.repeticiones, 1)
    }

    func testRepetirNoCortaNiTapaUnAvisoAjeno() async {
        let (voz, salida, modelo) = banco()
        voz.anunciar("Pérdida del accesorio.", prioridad: .urgente)
        modelo.repetir()
        XCTAssertEqual(salida.dicho, ["Pérdida del accesorio."])
        XCTAssertTrue(salida.cortadas.isEmpty)
        XCTAssertTrue(salida.hablando)
        XCTAssertEqual(modelo.resultado, TextoEmergencia.sonandoOtroAviso)
    }
}
