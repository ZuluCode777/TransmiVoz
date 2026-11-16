import XCTest
@testable import TransMiVoz

/// El asistente de voz de Ceguera total (`AgenteTotalModelo`) sobre la `ConsultaModelo` real, con cliente, reconocedor, salida de
/// voz y avisos falsos. No prueban el micrófono, la síntesis, los auriculares ni VoiceOver: solo qué decide el modelo.
@MainActor
final class AgenteTotalModeloTests: XCTestCase {
    @MainActor private final class Banco {
        let cliente = ClienteControlable()
        let salida = SalidaVozFalsa()
        let voz: ControlVoz
        let reconocedor = ReconocedorFalso()
        let dictado: DictadoModelo
        let consulta: ConsultaModelo
        let avisos = AvisosFalsos()
        let agente: AgenteTotalModelo

        init(ruta: RutaAudio = .privada, conDictado: Bool = true, apareciendo: Bool = true) {
            voz = ControlVoz(salida: salida, consultarRuta: { ruta })
            dictado = DictadoModelo(reconocedor: reconocedor, voz: voz, avisos: avisos.avisos)
            consulta = ConsultaModelo(cliente: cliente, dictado: conDictado ? dictado : nil, voz: voz)
            agente = AgenteTotalModelo(consulta: consulta, avisos: avisos.avisos)
            if apareciendo { agente.alAparecer() }
        }

        /// Lo que hace la vista: cada cambio de la consulta le llega al modelo.
        func notificar() { agente.consultaCambio(consulta.estado) }

        /// Pregunta escrita y respondida.
        func preguntar(_ frase: String, respuesta: Result<RespuestaAgente, Error>, indice: Int = 0) async {
            consulta.editarTexto(frase)
            agente.preguntar()
            await cliente.esperarConsultas(indice + 1)
            cliente.responder(respuesta, indice: indice)
            await dejarCorrer()
            notificar()
        }

        func dejarCorrer() async { try? await Task.sleep(nanoseconds: 100_000_000) }
    }

    private let sencilla = RespuestaAgente(texto: "Respuesta de prueba")

    // MARK: Micrófono

    func testTocarElMicrofonoEscuchaYOtroTocoTerminaYEnviaSolo() async {
        let banco = Banco()
        XCTAssertEqual(banco.agente.fase, .reposo)
        banco.agente.tocarMicrofono()
        banco.reconocedor.emitir(.escuchando)
        XCTAssertEqual(banco.agente.fase, .escuchando)
        XCTAssertEqual(banco.agente.valorMicrofono, "escuchando")
        XCTAssertEqual(banco.agente.titulo, "Escuchando…")

        banco.agente.tocarMicrofono()  // termina: el reconocedor entrega el texto final
        XCTAssertEqual(banco.reconocedor.veces("detener"), 1)
        banco.reconocedor.emitir(.terminado("cómo llego a Ricaurte"))
        XCTAssertEqual(banco.consulta.texto, "cómo llego a Ricaurte")
        banco.agente.dictadoTerminado()  // lo que hace la vista al ver `ultimoDictado`

        await banco.cliente.esperarConsultas(1)
        XCTAssertEqual(banco.cliente.textosRecibidos, ["cómo llego a Ricaurte"])
        XCTAssertEqual(banco.agente.fase, .pensando)
        XCTAssertEqual(banco.consulta.texto, "", "como la web, el campo queda vacío al enviar")
        XCTAssertEqual(banco.consulta.ultimoTextoEnviado, "cómo llego a Ricaurte")
    }

    func testTocarElMicrofonoMientrasPreparaOPiensaCancela() async {
        let banco = Banco()
        banco.agente.tocarMicrofono()  // iniciando: el micrófono aún no responde
        XCTAssertEqual(banco.agente.fase, .escuchando)
        banco.agente.tocarMicrofono()
        XCTAssertEqual(banco.agente.fase, .reposo)
        XCTAssertEqual(banco.reconocedor.veces("cancelar"), 1)

        banco.consulta.editarTexto("hola")
        banco.agente.preguntar()
        XCTAssertEqual(banco.agente.fase, .pensando)
        banco.agente.tocarMicrofono()  // pensando: cancela la consulta
        XCTAssertEqual(banco.consulta.estado, .cancelada)
        XCTAssertEqual(banco.agente.fase, .reposo)
    }

    func testSinDictadoElMicrofonoLoDiceYElTextoSigueDisponible() async {
        let banco = Banco(conDictado: false)
        banco.agente.tocarMicrofono()
        XCTAssertEqual(banco.agente.subtitulo, TextoAgenteTotal.sinDictado)
        XCTAssertEqual(banco.agente.valorMicrofono, "no disponible")
        XCTAssertEqual(banco.salida.dicho, [TextoAgenteTotal.saludo, TextoAgenteTotal.sinDictado])
        await banco.preguntar("hola", respuesta: .success(sencilla))
        XCTAssertEqual(banco.agente.subtitulo, "Respuesta de prueba", "una pregunta nueva sustituye el aviso")
    }

    func testUnProblemaDelDictadoPrimaSobreLaUltimaRespuestaYSeDice() async {
        let banco = Banco()
        await banco.preguntar("hola", respuesta: .success(sencilla))
        banco.reconocedor.permiso = .denegado
        banco.agente.tocarMicrofono()
        banco.agente.dictadoCambio(banco.dictado.estado)
        let mensaje = TextoDictado.descripcion(.permisoDenegado, capacidad: banco.dictado.capacidad)
        XCTAssertEqual(banco.agente.aviso, mensaje)
        XCTAssertEqual(banco.agente.subtitulo, mensaje)
        XCTAssertNil(banco.agente.respuesta, "la respuesta anterior deja de ser lo que se muestra")
        XCTAssertEqual(banco.salida.dicho.last, mensaje, "sin VoiceOver, la voz de la app lo dice")
    }

    func testConVoiceOverUnProblemaDelDictadoNoSeDiceDosVeces() async {
        let banco = Banco()
        banco.avisos.voiceOver = true
        banco.reconocedor.permiso = .denegado
        banco.agente.tocarMicrofono()
        banco.agente.dictadoCambio(banco.dictado.estado)
        // El dictado ya lo anunció por VoiceOver; la voz de la app no se suma (solo sonó el saludo, antes de activar VoiceOver).
        XCTAssertEqual(banco.salida.dicho, [TextoAgenteTotal.saludo])
        XCTAssertEqual(banco.avisos.anuncios.filter { $0.hasPrefix("Sin permiso") }.count, 1)
    }

    // MARK: Respuestas: voz y VoiceOver

    func testUnaRespuestaEscritaSeLeeEnVozAltaUnaSolaVez() async {
        let banco = Banco()
        await banco.preguntar("hola", respuesta: .success(sencilla))
        XCTAssertEqual(banco.salida.dicho, [TextoAgenteTotal.saludo, "Respuesta de prueba"])
        XCTAssertEqual(banco.agente.respuesta, sencilla)
        XCTAssertEqual(banco.agente.subtitulo, "Respuesta de prueba")
        XCTAssertTrue(banco.avisos.anuncios.isEmpty, "con la voz de la app sonando no se repite por VoiceOver")
    }

    func testUnaRespuestaDictadaNoSeLeeDosVeces() async {
        let banco = Banco()
        banco.agente.tocarMicrofono()
        banco.reconocedor.emitir(.escuchando)
        banco.agente.tocarMicrofono()
        banco.reconocedor.emitir(.terminado("hola"))
        banco.agente.dictadoTerminado()
        await banco.cliente.esperarConsultas(1)
        banco.cliente.responder(.success(sencilla))
        await banco.dejarCorrer()
        banco.notificar()
        // La consulta no la lee sola (`lecturaAutomatica` apagada): solo la lee la pantalla.
        XCTAssertEqual(banco.salida.dicho.filter { $0 == "Respuesta de prueba" }.count, 1)
    }

    func testMientrasPiensaSeAnunciaPorVoiceOver() {
        let banco = Banco()
        banco.agente.consultaCambio(.enviando)
        XCTAssertEqual(banco.avisos.anuncios, ["Pensando…"])
        XCTAssertTrue(banco.salida.dicho == [TextoAgenteTotal.saludo], "«Pensando» no se dice en voz alta, como en la web")
    }

    func testSiLaVozNoSuenaLaRespuestaVaPorVoiceOver() async {
        let banco = Banco(ruta: .noPrivada)
        await banco.preguntar("hola", respuesta: .success(sencilla))
        XCTAssertTrue(banco.salida.dicho.isEmpty, "por el altavoz la voz de la app no habla")
        XCTAssertEqual(banco.avisos.anuncios, ["Respuesta de prueba"])
    }

    func testUnErrorSeDiceConSuRecuperacionYOfreceReintentar() async {
        let banco = Banco()
        await banco.preguntar("hola", respuesta: .failure(ErrorConsulta.sinConexion))
        let texto = "\(ErrorConsulta.sinConexion.mensaje) \(ErrorConsulta.sinConexion.recuperacion)"
        XCTAssertEqual(banco.agente.subtitulo, texto)
        XCTAssertEqual(banco.salida.dicho.last, texto)
        XCTAssertTrue(banco.agente.puedeReintentar)

        banco.agente.reintentar()
        await banco.cliente.esperarConsultas(2)
        XCTAssertEqual(banco.cliente.textosRecibidos, ["hola", "hola"])
        banco.cliente.responder(.success(sencilla), indice: 1)
        await banco.dejarCorrer()
        banco.notificar()
        XCTAssertEqual(banco.agente.respuesta, sencilla)
        XCTAssertFalse(banco.agente.puedeReintentar)
    }

    func testUnErrorQueNoAdmiteReintentoNoLoOfrece() async {
        let banco = Banco()
        await banco.preguntar("hola", respuesta: .failure(ErrorConsulta.noAutorizado))
        XCTAssertFalse(banco.agente.puedeReintentar)
    }

    func testUnaPreguntaVaciaNoSaleYSeDice() {
        let banco = Banco()
        banco.agente.preguntar()
        XCTAssertEqual(banco.consulta.estado, .error(.entradaInvalida(.vacia)))
        banco.notificar()
        XCTAssertEqual(banco.agente.subtitulo, "Escribe una pregunta antes de enviar. Corrige el texto y vuelve a enviar.")
        XCTAssertEqual(banco.salida.dicho.last, banco.agente.subtitulo)
    }

    func testUnaPreguntaDemasiadoLargaConservaElTexto() {
        let banco = Banco()
        let larga = String(repeating: "a", count: 400)
        banco.consulta.editarTexto(larga)
        banco.agente.preguntar()
        XCTAssertEqual(banco.consulta.texto, larga, "si no salió, la persona puede corregirla")
    }

    func testEstaPantallaSiemprePreguntaPorElTransporteDeHoy() async {
        let banco = Banco()
        banco.consulta.escenario = .metroFuturo
        banco.consulta.editarTexto("estaciones")
        banco.agente.preguntar()
        XCTAssertEqual(banco.consulta.escenario, .transporte)
        await banco.cliente.esperarConsultas(1)
        XCTAssertEqual(banco.cliente.textosRecibidos, ["estaciones"], "sin el prefijo «Metro: »")
    }

    func testLaAclaracionDeOrigenSigueFuncionandoPorVoz() async {
        let banco = Banco()
        let pide = RespuestaAgente(texto: "¿A qué estación quieres ir?", origenPendiente: "Ricaurte")
        await banco.preguntar("salgo desde Ricaurte", respuesta: .success(pide))
        XCTAssertEqual(banco.consulta.origenPendiente, "Ricaurte")
        XCTAssertEqual(banco.salida.dicho.last, "¿A qué estación quieres ir?")
        await banco.preguntar("Calle 72", respuesta: .success(sencilla), indice: 1)
        XCTAssertEqual(banco.cliente.origenesRecibidos, [nil, "Ricaurte"])
        banco.agente.olvidarOrigen()
        XCTAssertNil(banco.consulta.origenPendiente)
    }

    // MARK: Cancelar

    func testCancelarMientrasPiensaDiceQueSeCancelaYUnaRespuestaTardiaNoHabla() async {
        let banco = Banco()
        banco.consulta.editarTexto("hola")
        banco.agente.preguntar()
        await banco.cliente.esperarConsultas(1)
        banco.agente.cancelar()
        banco.notificar()
        XCTAssertEqual(banco.consulta.estado, .cancelada)
        XCTAssertEqual(banco.salida.dicho.last, "Consulta cancelada.")
        let dichas = banco.salida.dicho.count
        banco.cliente.responder(.success(sencilla))
        await banco.dejarCorrer()
        banco.notificar()
        XCTAssertEqual(banco.salida.dicho.count, dichas)
        XCTAssertTrue(banco.agente.puedeReintentar)
    }

    func testUnaCancelacionAjenaALaPantallaNoSeDice() async {
        let banco = Banco()
        banco.consulta.editarTexto("hola")
        banco.agente.preguntar()
        await banco.cliente.esperarConsultas(1)
        banco.consulta.salir()  // la pestaña Consulta se fue
        banco.notificar()
        XCTAssertEqual(banco.consulta.estado, .cancelada)
        XCTAssertFalse(banco.salida.dicho.contains("Consulta cancelada."))
    }

    // MARK: Navegación

    func testCadaAccionAbreLaPantallaQueAbreLaWeb() {
        let casos: [(AccionAgente, DestinoAgenteTotal?)] = [
            (.ninguna, nil), (.frecuentes, .favoritas), (.gps, .gps),
            (.busqueda(estacion: "Ricaurte"), .rutas(estacion: "Ricaurte")), (.ruta(codigo: "B23"), .ruta(codigo: "B23")),
            (.viaje([]), nil),
        ]
        for (accion, esperado) in casos {
            XCTAssertEqual(AgenteTotalModelo.destino(para: accion), esperado, "\(accion)")
        }
    }

    func testUnaRespuestaConPantallaLaAbreYSuVozSigueAlSalir() async {
        let banco = Banco()
        let gps = RespuestaAgente(texto: "Voy a abrir el GPS auditivo.", accion: .gps)
        await banco.preguntar("gps", respuesta: .success(gps))
        XCTAssertEqual(banco.agente.destino, .gps)
        XCTAssertEqual(banco.salida.dicho.last, "Voy a abrir el GPS auditivo.", "sin el límite «no hay pantalla»: la abre")

        banco.agente.alDesaparecer()  // la pantalla empujada cubre a esta
        XCTAssertFalse(banco.salida.cortadas.contains("Voy a abrir el GPS auditivo."), "la voz de la respuesta que navega no se corta")
        banco.agente.destinoCerrado()
        banco.agente.alAparecer()
        XCTAssertNil(banco.agente.destino)
    }

    func testDejarLaPestanaInicioCortaLaVozDeUnaRespuestaQueAbrioUnaPantalla() async {
        let banco = Banco()
        let gps = RespuestaAgente(texto: "Voy a abrir el GPS auditivo.", accion: .gps)
        await banco.preguntar("gps", respuesta: .success(gps))
        banco.agente.alDesaparecer()  // la pantalla empujada por la respuesta cubre a esta
        XCTAssertTrue(banco.salida.hablando, "la voz de la respuesta que navega sigue sonando")

        banco.agente.alSalirDeInicio()  // la raíz cambió de pestaña
        XCTAssertTrue(banco.salida.cortadas.contains("Voy a abrir el GPS auditivo."), "salir de Inicio corta la voz de esa respuesta")
        XCTAssertFalse(banco.salida.hablando)
    }

    func testDejarLaPestanaInicioNoCortaUnAvisoDelAccesorio() async {
        let banco = Banco()
        let gps = RespuestaAgente(texto: "Voy a abrir el GPS auditivo.", accion: .gps)
        await banco.preguntar("gps", respuesta: .success(gps))
        banco.agente.alDesaparecer()
        // Después de la respuesta habla un aviso del accesorio: la cola de uno ya cortó la respuesta y lo que suena es suyo.
        banco.voz.anunciar("Aviso del accesorio", prioridad: .urgente)
        XCTAssertTrue(banco.salida.hablando)

        banco.agente.alSalirDeInicio()
        XCTAssertFalse(banco.salida.cortadas.contains("Aviso del accesorio"), "un aviso ajeno no se corta")
        XCTAssertTrue(banco.salida.hablando)
    }

    func testLasOtrasPantallasSeAbrenAMano() {
        let banco = Banco()
        banco.agente.abrir(.rutas(estacion: nil))
        XCTAssertEqual(banco.agente.destino, .rutas(estacion: nil))
        banco.agente.destinoCerrado()
        banco.agente.abrir(.favoritas)
        XCTAssertEqual(banco.agente.destino, .favoritas)
    }

    func testAbrirUnaPantallaAManoCortaLoQueSonaba() async {
        let banco = Banco()
        await banco.preguntar("hola", respuesta: .success(sencilla))
        banco.agente.abrir(.gps)
        banco.agente.alDesaparecer()
        XCTAssertTrue(banco.salida.cortadas.contains("Respuesta de prueba"))
    }

    func testUnViajeNoAbreNadaYLeeSusTramosSinElTextoDelServidor() async {
        let tramo = TramoViaje(
            codigoRuta: "H72", estacionAbordaje: "Calle 127", estacionDescenso: "Portal Usme", estacionesRecorridas: 8,
            conteoVerificado: true)
        let viaje = RespuestaAgente(
            texto: "Toma la H72 en Calle 127 y bájate en Portal Usme.", accion: .viaje([tramo]),
            catalogo: ProcedenciaCatalogo(procedencia: "Datos consultados hoy.", antiguo: false))
        let banco = Banco()
        await banco.preguntar("viaje", respuesta: .success(viaje))
        XCTAssertNil(banco.agente.destino)
        let dicho = banco.salida.dicho.last ?? ""
        XCTAssertFalse(dicho.contains("Toma la H72"), "el texto del servidor no se lee")
        XCTAssertTrue(dicho.hasPrefix(viaje.accion.limite ?? "?"))
        XCTAssertTrue(dicho.contains("Ruta H72: de Calle 127 a Portal Usme, 8 estaciones (conteo verificado)."))
        XCTAssertTrue(dicho.hasSuffix("Datos consultados hoy."))
        XCTAssertEqual(banco.agente.subtitulo, dicho, "lo que se ve es lo que se dice")
    }

    func testElLimiteDeUnaAccionSoloSeDiceSiNoSeAbreLaPantalla() {
        let gps = RespuestaAgente(texto: "Voy a abrir el GPS auditivo.", accion: .gps)
        XCTAssertEqual(AgenteTotalModelo.textoHablado(gps, destino: .gps), "Voy a abrir el GPS auditivo.")
        XCTAssertEqual(
            AgenteTotalModelo.textoHablado(gps, destino: nil), "Voy a abrir el GPS auditivo. \(gps.accion.limite ?? "")")
    }

    func testLosDatosAntiguosSeDicenYLaProcedenciaNoSeRepite() {
        let antigua = RespuestaAgente(
            texto: "La ruta Z99 es de prueba.", accion: .ruta(codigo: "Z99"),
            catalogo: ProcedenciaCatalogo(procedencia: "Datos de una copia guardada.", antiguo: true))
        XCTAssertEqual(
            AgenteTotalModelo.textoHablado(antigua, destino: .ruta(codigo: "Z99")),
            "La ruta Z99 es de prueba. Datos de una copia guardada. Los datos de TransMilenio son antiguos.")
    }

    // MARK: Ciclo de vida

    func testUnCambioDeLaConsultaConLaPantallaFueraDeVistaNoHablaNiNavega() async {
        let banco = Banco(apareciendo: false)
        let gps = RespuestaAgente(texto: "Voy a abrir el GPS auditivo.", accion: .gps)
        await banco.preguntar("gps", respuesta: .success(gps))  // hecha desde la pestaña Consulta
        XCTAssertNil(banco.agente.destino)
        XCTAssertTrue(banco.salida.dicho.isEmpty)
        XCTAssertTrue(banco.avisos.anuncios.isEmpty)
    }

    func testElSaludoSoloSinVoiceOverYUnaVezPorVisita() {
        let banco = Banco()
        XCTAssertEqual(banco.salida.dicho, [TextoAgenteTotal.saludo])
        banco.agente.alAparecer()
        XCTAssertEqual(banco.salida.dicho, [TextoAgenteTotal.saludo], "volver de una pantalla empujada no lo repite")
        banco.agente.alDesaparecer()  // salió de la pestaña
        banco.agente.alAparecer()
        XCTAssertEqual(banco.salida.dicho.filter { $0 == TextoAgenteTotal.saludo }.count, 2)

        let conVoiceOver = Banco(apareciendo: false)
        conVoiceOver.avisos.voiceOver = true
        conVoiceOver.agente.alAparecer()
        XCTAssertTrue(conVoiceOver.salida.dicho.isEmpty, "VoiceOver lee la pantalla: un saludo encima la pisaría")
    }

    func testSalirInvalidaConsultaYVozYDevuelveLaLecturaALaConsulta() async {
        let banco = Banco()
        XCTAssertFalse(banco.consulta.lecturaAutomatica)
        banco.consulta.editarTexto("lento")
        banco.agente.preguntar()
        await banco.cliente.esperarConsultas(1)
        banco.agente.alDesaparecer()
        XCTAssertEqual(banco.consulta.estado, .cancelada)
        XCTAssertTrue(banco.consulta.lecturaAutomatica)
        banco.cliente.responder(.success(sencilla))
        await banco.dejarCorrer()
        XCTAssertEqual(banco.consulta.estado, .cancelada, "una respuesta tardía no se aplica")
    }

    func testPasarASegundoPlanoCancelaLaConsulta() async {
        let banco = Banco()
        banco.consulta.editarTexto("hola")
        banco.agente.preguntar()
        await banco.cliente.esperarConsultas(1)
        banco.agente.alPasarASegundoPlano()
        XCTAssertEqual(banco.consulta.estado, .cancelada)
    }

    func testElMicrofonoYLaPistaCambianConLaFase() {
        let banco = Banco()
        XCTAssertEqual(banco.agente.pistaMicrofono, TextoAgenteTotal.pistaReposo)
        banco.agente.tocarMicrofono()
        XCTAssertEqual(banco.agente.pistaMicrofono, TextoAgenteTotal.pistaEscuchando)
        banco.agente.cancelar()
        banco.consulta.editarTexto("hola")
        banco.agente.preguntar()
        XCTAssertEqual(banco.agente.pistaMicrofono, TextoAgenteTotal.pistaPensando)
        XCTAssertEqual(banco.agente.valorMicrofono, "pensando")
    }
}
