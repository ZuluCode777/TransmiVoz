import XCTest
@testable import TransMiVoz

/// Funciones de rutas que la web tiene y el iPhone ganó: búsqueda por voz, «Escuchar», consulta periódica del detalle y del
/// viaje, y las alternativas del viaje. Nada de esto prueba el micrófono, el reconocimiento del español ni la voz real.
@MainActor
final class AnunciosVoz {
    var textos: [String] = []
}

@MainActor
final class RutasVozModeloTests: XCTestCase {
    private var reconocedor: ReconocedorFalso!
    private var avisos: AvisosFalsos!
    private var campo: CampoFalso!

    private func armar(permiso: PermisoVoz = .concedido) -> (DictadoModelo, RutasVozModelo) {
        avisos = AvisosFalsos()
        campo = CampoFalso()
        reconocedor = ReconocedorFalso(permiso: permiso)
        let dictado = DictadoModelo(reconocedor: reconocedor, avisos: avisos.avisos)
        campo.conectar(a: dictado) // el destino que tenía el dictado antes (la consulta)
        return (dictado, RutasVozModelo(dictado: dictado, espera: .zero))
    }

    func testAbrirEmpiezaLaCapturaDespuesDelAnuncio() async {
        let (dictado, modelo) = armar()
        let dichos = AnunciosVoz()
        let conAnuncio = RutasVozModelo(dictado: dictado, espera: .zero, anunciar: { dichos.textos.append($0) })
        conAnuncio.abrir()
        XCTAssertTrue(conAnuncio.abierta)
        XCTAssertEqual(dichos.textos, [TextoRutas.vozTeEscucho])
        await esperarHasta(reconocedor.veces("iniciar") == 1)
        XCTAssertEqual(reconocedor.veces("iniciar"), 1)
        XCTAssertFalse(modelo.abierta)
    }

    func testLoParcialSeMuestraYSoloElTextoFinalSeEntregaUnaVezYCierra() async {
        let (dictado, modelo) = armar()
        modelo.abrir()
        await esperarHasta(reconocedor.veces("iniciar") == 1)
        reconocedor.emitir(.escuchando)
        reconocedor.emitir(.parcial("ruta b"))
        XCTAssertEqual(modelo.transcripcion, "ruta b")
        XCTAssertEqual(modelo.entregas, 0, "lo parcial nunca busca")
        modelo.estadoCambio(dictado.estado)
        XCTAssertTrue(modelo.abierta)

        reconocedor.emitir(.terminado("ruta B23"))
        modelo.estadoCambio(dictado.estado) // lo que hace la vista al ver el cambio de estado
        XCTAssertEqual(modelo.entregas, 1)
        XCTAssertEqual(modelo.ultimoEntregado, "ruta B23")
        XCTAssertFalse(modelo.abierta)

        modelo.estadoCambio(dictado.estado) // un aviso repetido no entrega otra vez
        XCTAssertEqual(modelo.entregas, 1)
    }

    func testMientrasEstaAbiertoElTextoNoVaAlCampoDeLaConsultaYAlCerrarSeRestituye() async {
        let (dictado, modelo) = armar()
        modelo.abrir()
        await esperarHasta(reconocedor.veces("iniciar") == 1)
        reconocedor.emitir(.escuchando)
        reconocedor.emitir(.terminado("estación Ricaurte"))
        modelo.estadoCambio(dictado.estado)
        XCTAssertTrue(campo.escrito.isEmpty, "lo dictado en esta pantalla no se escribe en la consulta")

        dictado.alTexto?("pregunta de la consulta")
        XCTAssertEqual(campo.escrito, ["pregunta de la consulta"], "el destino de antes vuelve a ser el del dictado")
    }

    func testCerrarAbortaLaCapturaYLoQueLlegaTardeNoSeEntrega() async {
        let (dictado, modelo) = armar()
        modelo.abrir()
        await esperarHasta(reconocedor.veces("iniciar") == 1)
        let token = reconocedor.tokenVigente
        reconocedor.emitir(.escuchando)
        modelo.cerrar()
        XCTAssertFalse(modelo.abierta)
        XCTAssertEqual(dictado.estado, .inactivo)
        XCTAssertGreaterThanOrEqual(reconocedor.veces("cancelar"), 1)

        reconocedor.emitir(.terminado("llegó tarde"), token: token)
        modelo.estadoCambio(dictado.estado)
        XCTAssertEqual(modelo.entregas, 0)
        XCTAssertNil(modelo.ultimoEntregado)
    }

    func testCerrarAntesDeQueEmpieceLaCapturaNoLaAbre() async {
        let (_, modelo) = armar()
        let lento = RutasVozModelo(dictado: modelo.dictado, espera: .milliseconds(150))
        lento.abrir()
        lento.cerrar()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(reconocedor.veces("iniciar"), 0)
    }

    func testSinPermisoSeDiceYNoSeEntregaNada() async {
        let (dictado, modelo) = armar(permiso: .denegado)
        modelo.abrir()
        await esperarHasta(dictado.estado == .permisoDenegado)
        XCTAssertEqual(dictado.estado, .permisoDenegado)
        modelo.estadoCambio(dictado.estado)
        XCTAssertTrue(modelo.abierta, "la superposición sigue abierta con el motivo a la vista")
        XCTAssertEqual(modelo.entregas, 0)
    }

    func testUnaCapturaCanceladaSinTextoNoEntregaNada() async {
        let (dictado, modelo) = armar()
        modelo.abrir()
        await esperarHasta(reconocedor.veces("iniciar") == 1)
        dictado.cancelar()
        modelo.estadoCambio(dictado.estado)
        XCTAssertEqual(modelo.entregas, 0)
        XCTAssertTrue(modelo.abierta)
    }

    func testSinDictadoSeAbreYSeCierraSinFallar() async {
        let modelo = RutasVozModelo(dictado: nil)
        XCTAssertFalse(modelo.disponible)
        modelo.abrir()
        XCTAssertTrue(modelo.abierta)
        modelo.alternar()
        modelo.cerrar()
        XCTAssertFalse(modelo.abierta)
    }

    func testHablarDeNuevoLimpiaLoOidoYVuelveAEmpezar() async {
        let (dictado, modelo) = armar()
        modelo.abrir()
        await esperarHasta(reconocedor.veces("iniciar") == 1)
        reconocedor.emitir(.escuchando)
        reconocedor.emitir(.terminado("   ")) // no se entendió nada
        XCTAssertEqual(dictado.estado, .sinTexto)
        modelo.estadoCambio(dictado.estado)
        XCTAssertEqual(modelo.entregas, 0)

        modelo.alternar()
        XCTAssertEqual(reconocedor.veces("iniciar"), 2)
        XCTAssertEqual(modelo.transcripcion, "")
    }

    func testAbrirCortaUnaCapturaDeOtraPantalla() async {
        let (dictado, modelo) = armar()
        dictado.alternar() // la consulta estaba dictando
        reconocedor.emitir(.escuchando)
        XCTAssertTrue(dictado.estado.enCurso)
        modelo.abrir()
        XCTAssertEqual(dictado.estado, .inactivo)
        await esperarHasta(reconocedor.veces("iniciar") == 2)
        XCTAssertEqual(reconocedor.veces("iniciar"), 2)
    }
}

@MainActor
final class EscuchaRutaModeloTests: XCTestCase {
    private func armar(ruta: RutaAudio = .privada) -> (EscuchaRutaModelo, ControlVoz, SalidaVozFalsa) {
        let salida = SalidaVozFalsa()
        let voz = ControlVoz(salida: salida, consultarRuta: { ruta })
        return (EscuchaRutaModelo(voz: voz, dictado: nil), voz, salida)
    }

    func testEscucharLeeElTextoPorLaVozDeLaApp() async {
        let (escucha, _, salida) = armar()
        escucha.escuchar("Ruta Z99, de Norte hacia Sur.")
        XCTAssertEqual(salida.dicho, ["Ruta Z99, de Norte hacia Sur."])
        XCTAssertNil(escucha.mensaje)
    }

    func testSinVozEnLosServiciosLoDice() async {
        let escucha = EscuchaRutaModelo(voz: nil, dictado: nil)
        escucha.escuchar("texto")
        XCTAssertEqual(escucha.mensaje, TextoRutas.escuchaNoDisponible)
    }

    func testSinSalidaPrivadaNoSeHablaYSeDiceElMotivo() async {
        let (escucha, _, salida) = armar(ruta: .noPrivada)
        escucha.escuchar("texto")
        XCTAssertTrue(salida.dicho.isEmpty)
        XCTAssertEqual(escucha.mensaje, TextoAvisos.noSeDijo(.rutaNoPrivada))
    }

    func testConLaVozApagadaSeDiceElMotivo() async {
        let (escucha, voz, salida) = armar()
        voz.permitida = { false }
        escucha.escuchar("texto")
        XCTAssertTrue(salida.dicho.isEmpty)
        XCTAssertEqual(escucha.mensaje, TextoAvisos.noSeDijo(.vozApagada))
    }

    func testConElMicrofonoAbiertoNoSeHabla() async {
        let reconocedor = ReconocedorFalso()
        let dictado = DictadoModelo(reconocedor: reconocedor, avisos: AvisosFalsos().avisos)
        let salida = SalidaVozFalsa()
        let escucha = EscuchaRutaModelo(voz: ControlVoz(salida: salida, consultarRuta: { .privada }), dictado: dictado)
        dictado.alternar()
        XCTAssertTrue(dictado.capturando)
        escucha.escuchar("texto")
        XCTAssertTrue(salida.dicho.isEmpty)
        XCTAssertEqual(escucha.mensaje, TextoRutas.escuchaConMicrofono)
    }

    func testNoTapaUnAvisoQueYaSuena() async {
        let (escucha, voz, salida) = armar()
        voz.anunciar("aviso del accesorio")
        escucha.escuchar("la ruta")
        XCTAssertEqual(salida.dicho, ["aviso del accesorio"], "la lectura no cortó el aviso")
        XCTAssertEqual(escucha.mensaje, TextoAvisos.noSeDijo(.cedeAUnAviso))
    }

    func testRepetirReemplazaLaLecturaPropiaYDetenerCortaSoloLaPropia() async {
        let (escucha, voz, salida) = armar()
        escucha.escuchar("primera")
        escucha.escuchar("segunda") // la suya sigue sonando: se reemplaza
        XCTAssertEqual(salida.dicho, ["primera", "segunda"])
        escucha.detener()
        XCTAssertFalse(salida.hablando)

        escucha.escuchar("tercera")
        voz.anunciar("aviso") // otro dueño habla ahora
        escucha.detener()
        XCTAssertTrue(salida.hablando, "detener no corta lo que ya no es suyo")
    }
}

/// Un detalle y un viaje a la vista se vuelven a consultar sin tocar lo que se ve ni mover el foco.
@MainActor
final class RutasRefrescoTests: XCTestCase {
    private let norte = "Estación Ejemplo Norte"
    private let sur = "Estación Ejemplo Sur"

    private func dejarCorrer() async { try? await Task.sleep(nanoseconds: 100_000_000) }
    private func detalle() throws -> DetalleRuta { try decodificarPlanificador(FixturesPlanificador.detalle) }
    private func otroDetalle() throws -> DetalleRuta { try decodificarPlanificador(FixturesPlanificador.detalleSinVerificar) }

    private func detalleListo(_ cliente: ClientePlanificadorFalso, revalidador: RevalidadorPeriodico = RevalidadorPeriodico()) async throws -> DetalleRutaModelo {
        let modelo = DetalleRutaModelo(codigo: "Z99", cliente: cliente, revalidador: revalidador)
        modelo.cargar()
        await cliente.detalles.esperar(1)
        cliente.detalles.responder(.success(try detalle()))
        await dejarCorrer()
        XCTAssertEqual(modelo.estado, .listo(try detalle()))
        return modelo
    }

    func testRefrescarReemplazaElDetalleSinPasarPorCargando() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = try await detalleListo(cliente)
        modelo.refrescar()
        await cliente.detalles.esperar(2)
        XCTAssertEqual(modelo.estado, .listo(try detalle()), "mientras llega lo nuevo se ve lo de antes")
        cliente.detalles.responder(.success(try otroDetalle()), indice: 1)
        await dejarCorrer()
        XCTAssertEqual(modelo.estado, .listo(try otroDetalle()))
        XCTAssertFalse(modelo.refrescoFallido)
    }

    func testUnRefrescoQueFallaConservaLoVistoYLoDiceHastaQueUnoSalga() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = try await detalleListo(cliente)
        modelo.refrescar()
        await cliente.detalles.esperar(2)
        cliente.detalles.responder(.failure(ErrorConsulta.sinConexion), indice: 1)
        await dejarCorrer()
        XCTAssertEqual(modelo.estado, .listo(try detalle()))
        XCTAssertTrue(modelo.refrescoFallido)

        modelo.refrescar()
        await cliente.detalles.esperar(3)
        cliente.detalles.responder(.success(try detalle()), indice: 2)
        await dejarCorrer()
        XCTAssertFalse(modelo.refrescoFallido)
    }

    func testSinDetalleMostradoNoSePideNada() async {
        let cliente = ClientePlanificadorFalso()
        let modelo = DetalleRutaModelo(codigo: "Z99", cliente: cliente)
        modelo.refrescar()
        await dejarCorrer()
        XCTAssertTrue(cliente.detalles.argumentos.isEmpty)
    }

    func testVolverAConsultarDescartaUnRefrescoEnCurso() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = try await detalleListo(cliente)
        modelo.refrescar()
        await cliente.detalles.esperar(2)
        modelo.cargar()
        XCTAssertEqual(modelo.estado, .cargando)
        cliente.detalles.responder(.success(try otroDetalle()), indice: 1) // el refresco llega tarde
        await dejarCorrer()
        XCTAssertEqual(modelo.estado, .cargando, "lo que mandan son la carga y su resultado")
        await cliente.detalles.esperar(3)
        cliente.detalles.responder(.success(try detalle()), indice: 2)
        await dejarCorrer()
        XCTAssertEqual(modelo.estado, .listo(try detalle()))
    }

    func testElRelojDelDetalleSoloCorreMientrasLaPantallaSeVe() async throws {
        let cliente = ClientePlanificadorFalso()
        let reloj = RelojControlable()
        let modelo = try await detalleListo(cliente, revalidador: RevalidadorPeriodico(dormir: { try await reloj.dormir($0) }))
        modelo.pantallaVisible(true)
        await esperarHasta(reloj.esperando == 1)
        XCTAssertEqual(cliente.detalles.argumentos.count, 1, "nada se pide antes de los 30 s")

        reloj.avanzar()
        await cliente.detalles.esperar(2)
        cliente.detalles.responder(.success(try otroDetalle()), indice: 1)
        await dejarCorrer()
        XCTAssertEqual(modelo.estado, .listo(try otroDetalle()))

        await esperarHasta(reloj.esperando == 1)
        modelo.pantallaVisible(false)
        reloj.avanzar() // despierta cancelada: no pide nada
        await dejarCorrer()
        XCTAssertEqual(cliente.detalles.argumentos.count, 2)
    }

    // MARK: Viaje

    private func viaje() throws -> PlanViaje { try decodificarPlanificador(FixturesPlanificador.viajeOperativo) }
    private func otroViaje() throws -> PlanViaje { try decodificarPlanificador(FixturesPlanificador.viajeRecorrido) }

    private func viajePlaneado(_ cliente: ClientePlanificadorFalso, revalidador: RevalidadorPeriodico = RevalidadorPeriodico()) async throws -> ViajeModelo {
        let modelo = ViajeModelo(cliente: cliente, revalidador: revalidador)
        modelo.elegirOrigen(norte)
        modelo.elegirDestino(sur)
        modelo.planear()
        await cliente.viajes.esperar(1)
        cliente.viajes.responder(.success(try viaje()))
        await dejarCorrer()
        XCTAssertEqual(modelo.plan, .listo(try viaje()))
        return modelo
    }

    func testElViajeSeVuelveAPlanearConLosMismosLugaresSinPasarPorCargando() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = try await viajePlaneado(cliente)
        modelo.refrescarPlan()
        await cliente.viajes.esperar(2)
        XCTAssertEqual(cliente.viajes.argumentos, ["\(norte)|\(sur)", "\(norte)|\(sur)"])
        XCTAssertEqual(modelo.plan, .listo(try viaje()))
        cliente.viajes.responder(.success(try otroViaje()), indice: 1)
        await dejarCorrer()
        XCTAssertEqual(modelo.plan, .listo(try otroViaje()), "el servidor decide si el viaje sigue siendo operativo")
        XCTAssertFalse(modelo.refrescoFallido)
    }

    func testUnViajeQueNoSePudoRevalidarConservaElAnteriorYLoDice() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = try await viajePlaneado(cliente)
        modelo.refrescarPlan()
        await cliente.viajes.esperar(2)
        cliente.viajes.responder(.failure(ErrorConsulta.sinConexion), indice: 1)
        await dejarCorrer()
        XCTAssertEqual(modelo.plan, .listo(try viaje()))
        XCTAssertTrue(modelo.refrescoFallido)
    }

    func testCambiarLaSeleccionDescartaElRefrescoEnCurso() async throws {
        let cliente = ClientePlanificadorFalso()
        let modelo = try await viajePlaneado(cliente)
        modelo.refrescarPlan()
        await cliente.viajes.esperar(2)
        modelo.elegirDestino("Estación Ejemplo Centro")
        XCTAssertEqual(modelo.plan, .inactivo)
        cliente.viajes.responder(.success(try otroViaje()), indice: 1)
        await dejarCorrer()
        XCTAssertEqual(modelo.plan, .inactivo, "el refresco del viaje anterior no pisa la selección nueva")
    }

    func testSinViajeMostradoNoSeRevalida() async {
        let cliente = ClientePlanificadorFalso()
        let modelo = ViajeModelo(cliente: cliente)
        modelo.elegirOrigen(norte)
        modelo.elegirDestino(sur)
        modelo.refrescarPlan()
        await dejarCorrer()
        XCTAssertTrue(cliente.viajes.argumentos.isEmpty)
    }

    func testElRelojDelViajeSoloCorreMientrasLaPantallaSeVe() async throws {
        let cliente = ClientePlanificadorFalso()
        let reloj = RelojControlable()
        let modelo = try await viajePlaneado(cliente, revalidador: RevalidadorPeriodico(dormir: { try await reloj.dormir($0) }))
        modelo.pantallaVisible(true)
        await esperarHasta(reloj.esperando == 1)
        reloj.avanzar()
        await cliente.viajes.esperar(2)
        cliente.viajes.responder(.success(try viaje()), indice: 1)
        await dejarCorrer()

        await esperarHasta(reloj.esperando == 1)
        modelo.pantallaVisible(false)
        reloj.avanzar()
        await dejarCorrer()
        XCTAssertEqual(cliente.viajes.argumentos.count, 2)
    }
}

/// «También te sirven…»: el campo opcional `alternativas` de `planear-viaje` (contrato de `lib/contrato-planificador.ts`).
@MainActor
final class RutasAlternativasTests: XCTestCase {
    /// El mismo JSON con la clave `alternativas` añadida (el contrato manda solo `{codigoRuta}` por elemento).
    private func conAlternativas(_ json: String, _ elementos: String) -> String {
        let nuevo = json.replacingOccurrences(of: "\"rutasPorElTrazado\":[]", with: "\"alternativas\":\(elementos),\"rutasPorElTrazado\":[]")
        XCTAssertNotEqual(nuevo, json, "el fixture debía tener rutasPorElTrazado vacío")
        return nuevo
    }

    private func plan(_ json: String) throws -> PlanViaje { try decodificarPlanificador(json) }

    func testUnViajeOperativoDecodificaSusAlternativasEnElOrdenDelServidor() async throws {
        let plan = try plan(conAlternativas(FixturesPlanificador.viajeOperativo, #"[{"codigoRuta":"Z98"},{"codigoRuta":"Z97"}]"#))
        XCTAssertEqual(plan.alternativas, ["Z98", "Z97"])
        XCTAssertEqual(plan.tramos.count, 1)
    }

    func testSinLaClaveNoHayAlternativas() async throws {
        XCTAssertEqual(try plan(FixturesPlanificador.viajeOperativo).alternativas, [])
        XCTAssertEqual(try plan(FixturesPlanificador.viajeTransbordo).alternativas, [])
        XCTAssertEqual(try plan(FixturesPlanificador.viajeCandidato).alternativas, [])
    }

    func testUnaClaveDeMasEnUnaAlternativaSeIgnoraComoEnElDecodificadorDeSiempre() async throws {
        let plan = try plan(conAlternativas(FixturesPlanificador.viajeOperativo, #"[{"codigoRuta":"Z98"}]"#))
        XCTAssertEqual(plan.alternativas, ["Z98"])
    }

    func testSeRechazanLasAlternativasQueElContratoNoPermite() async {
        let invalidas = [
            // presente, pero nulo o sin elementos
            conAlternativas(FixturesPlanificador.viajeOperativo, "null"),
            conAlternativas(FixturesPlanificador.viajeOperativo, "[]"),
            // más de dos
            conAlternativas(FixturesPlanificador.viajeOperativo, #"[{"codigoRuta":"A"},{"codigoRuta":"B"},{"codigoRuta":"C"}]"#),
            // con un transbordo (dos tramos)
            conAlternativas(FixturesPlanificador.viajeTransbordo, #"[{"codigoRuta":"Z97"}]"#),
            // en un servicio candidato
            conAlternativas(FixturesPlanificador.viajeCandidato, #"[{"codigoRuta":"Z97"}]"#),
            // en un recorrido sin paradas confirmadas
            conAlternativas(FixturesPlanificador.viajeSinRecorrido, #"[{"codigoRuta":"Z97"}]"#),
            // código vacío
            conAlternativas(FixturesPlanificador.viajeOperativo, #"[{"codigoRuta":"  "}]"#),
            // sin el código
            conAlternativas(FixturesPlanificador.viajeOperativo, #"[{"ruta":"Z98"}]"#),
            // no es una lista
            conAlternativas(FixturesPlanificador.viajeOperativo, #"{"codigoRuta":"Z98"}"#),
        ]
        for json in invalidas {
            XCTAssertThrowsError(try decodificarPlanificador(json) as PlanViaje, json) { error in
                XCTAssertEqual(error as? ErrorConsulta, .respuestaIncompatible)
            }
        }
    }

    func testElTituloDiceSoloLosCodigosYNoDiceDondeSubir() async {
        XCTAssertEqual(TextoRutas.tituloAlternativas([]), "")
        XCTAssertEqual(TextoRutas.tituloAlternativas(["H54"]), "También te sirve la ruta H54")
        XCTAssertEqual(TextoRutas.tituloAlternativas(["B23", "H54"]), "También te sirven las rutas B23 y H54")
        for texto in [
            TextoRutas.tituloAlternativas(["B23", "H54"]), TextoRutas.notaAlternativas, TextoRutas.etiquetaAlternativa("H54"),
        ] {
            XCTAssertFalse(GuardiaContenido.contieneOrdenDeViaje(texto), texto)
            XCTAssertFalse(texto.localizedCaseInsensitiveContains("sube en"), texto)
        }
    }
}

/// Lo que «Escuchar» lee: las frases de `describe` de `route-detail.tsx` con lo que decidió el servidor.
@MainActor
final class RutasDescripcionHabladaTests: XCTestCase {
    func testUnaRutaConfirmadaConServicioHoyDiceSuSentidoYQueNoEsTiempoReal() async throws {
        let detalle: DetalleRuta = try decodificarPlanificador(FixturesPlanificador.detalle)
        XCTAssertEqual(
            TextoRutas.descripcionHablada(detalle),
            "Ruta Z99, de Estación Ejemplo Norte hacia Estación Ejemplo Sur. Su recorrido pasa cerca de 3 estaciones. Según su calendario verificado, hoy tiene servicio programado; no es tiempo real, confirma el horario antes de salir. Datos de prueba consultados el 1/1/2026.")
    }

    func testUnaRutaSinConfirmarNoAfirmaElSentidoNiLasParadasNiElServicio() async throws {
        let detalle: DetalleRuta = try decodificarPlanificador(FixturesPlanificador.detalleSinVerificar)
        let texto = TextoRutas.descripcionHablada(detalle)
        XCTAssertTrue(texto.hasPrefix("Ruta Z98, con sentido declarado de Estación Ejemplo Norte hacia Estación Ejemplo Sur, todavía sin confirmar con una fuente vigente."), texto)
        XCTAssertTrue(texto.contains("Aún no tengo confirmado en qué estaciones para, así que no uses el recorrido como paradas de abordaje."), texto)
        XCTAssertTrue(texto.contains("Su horario publicado entre semana es 5:00 a. m. - 11:00 p. m., pero no tengo un calendario vigente verificado"), texto)
        XCTAssertFalse(texto.contains("no tiene servicio"), "un calendario sin verificar nunca dice que no hay servicio")
    }

    func testNingunaCombinacionDelServidorDaOrdenesDeAbordaje() async throws {
        let base: DetalleRuta = try decodificarPlanificador(FixturesPlanificador.detalle)
        for sentido in [SentidoRuta.confirmado, .contradictorio, .sinConfirmar] {
            for calendario in [CalendarioRuta.opera, .noOpera, .sinVerificar] {
                for semana in ["", "5:00 a. m. - 11:00 p. m."] {
                    let detalle = DetalleRuta(
                        codigo: base.codigo, etiqueta: base.etiqueta, desde: base.desde, hacia: base.hacia, sentido: sentido,
                        calendario: calendario,
                        horario: HorarioRuta(entreSemana: semana, sabado: "", festivo: ""),
                        estaciones: Array(base.estaciones.prefix(1)), trazado: base.trazado, catalogo: base.catalogo)
                    let texto = TextoRutas.descripcionHablada(detalle)
                    XCTAssertFalse(GuardiaContenido.contieneOrdenDeViaje(texto), texto)
                    XCTAssertTrue(texto.contains("pasa cerca de 1 estación."), "una sola estación va en singular: \(texto)")
                }
            }
        }
    }
}
