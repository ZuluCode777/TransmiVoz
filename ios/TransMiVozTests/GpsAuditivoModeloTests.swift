import ContratoBLE
import XCTest
@testable import TransMiVoz

/// Ciclo de vida de «Mapa y GPS» con ubicación, brújula, servidor y voz SIMULADOS: permiso, lecturas vencidas, rumbo,
/// cancelación, límite de peticiones y el aviso de cercanía que decide el servidor. Nada de esto prueba CoreLocation ni un
/// iPhone: los eventos del sensor los fabrica la prueba.
@MainActor
final class GpsAuditivoModeloTests: XCTestCase {
    /// Todo lo que rodea al modelo, junto.
    @MainActor
    private final class Banco {
        let cliente = ClientePlanificadorFalso()
        let ubicacion: UbicacionFalsa
        let locutor = LocutorFalso()
        let reloj = RelojFalso()
        let modelo: GpsAuditivoModelo
        private var respondidas = 0

        /// `sinTemporizador`: el temporizador de vencimiento nunca despierta, para probar la última guardia al enviar.
        init(brujula: Bool = true, sinTemporizador: Bool = false) {
            ubicacion = UbicacionFalsa(rumboDisponible: brujula)
            modelo = GpsAuditivoModelo(
                cliente: cliente, proveedor: ubicacion, locutor: locutor, reloj: reloj.reloj,
                // Despierta rápido y vuelve a mirar el reloj de la prueba: no espera 60 s de verdad.
                dormir: { _ in try await Task.sleep(nanoseconds: sinTemporizador ? 3_600_000_000_000 : 2_000_000) })
        }

        func posicion(precision: Double? = 10, hace: Milisegundos = 0, lat: Double = 4.6124, lng: Double = -74.0935) -> EventoUbicacion {
            .posicion(PosicionMedida(latitud: lat, longitud: lng, precision: precision, capturadaMs: reloj.ahora - hace))
        }

        func rumbo(grados: Double = 90, calidad: Double? = 10, hace: Milisegundos = 0) -> EventoUbicacion {
            .rumbo(RumboMedido(gradosVerdaderos: grados, calidad: calidad, capturadoMs: reloj.ahora - hace))
        }

        /// Activa la ubicación y entrega permiso y una primera lectura.
        func activar(precision: Double? = 10) {
            modelo.iniciar()
            ubicacion.emitir(.permiso(.porPreguntar))
            ubicacion.emitir(.permiso(.concedido))
            ubicacion.emitir(posicion(precision: precision))
        }

        var peticiones: Int { cliente.cercanas.argumentos.count }

        /// Responde la próxima petición pendiente y espera a que el modelo la procese.
        func responder(_ json: String) async throws {
            let respuesta: RespuestaEstacionesCercanas = try decodificarPlanificador(json)
            await cliente.cercanas.esperar(respondidas + 1)
            cliente.cercanas.responder(.success(respuesta), indice: respondidas)
            respondidas += 1
            await esperarHasta("que el modelo termine la consulta") { !self.modelo.consultando }
        }

        func fallar(_ error: ErrorConsulta) async {
            await cliente.cercanas.esperar(respondidas + 1)
            cliente.cercanas.responder(.failure(error), indice: respondidas)
            respondidas += 1
            await esperarHasta("que el modelo termine la consulta") { !self.modelo.consultando }
        }
    }

    private let centro = "Estación Ejemplo Centro"
    private let norte = "Estación Ejemplo Norte"

    private func estacion(_ json: String, _ indice: Int = 0) throws -> EstacionCercana {
        let respuesta: RespuestaEstacionesCercanas = try decodificarPlanificador(json)
        return respuesta.estaciones[indice]
    }

    // MARK: Nada sin que la persona lo pida

    func testNadaSeEscuchaNiSePideHastaQueLaPersonaActiva() async {
        let banco = Banco()
        XCTAssertEqual(banco.modelo.estado, .inactivo)
        XCTAssertEqual(banco.ubicacion.iniciados, 0)
        await dejarPasar()
        XCTAssertEqual(banco.peticiones, 0)
        XCTAssertTrue(banco.locutor.dichos.isEmpty)

        banco.modelo.iniciar()
        XCTAssertEqual(banco.modelo.estado, .pidiendoPermiso)
        XCTAssertEqual(banco.ubicacion.iniciados, 1)
        XCTAssertEqual(banco.locutor.dichos, [TextoGps.activando])
        XCTAssertEqual(banco.peticiones, 0, "esperar el permiso no pide estaciones")
    }

    func testActivarDosVecesNoAbreOtraSesion() {
        let banco = Banco()
        banco.modelo.iniciar()
        banco.modelo.iniciar()
        XCTAssertEqual(banco.ubicacion.iniciados, 1)
        XCTAssertEqual(banco.locutor.dichos.last, TextoGps.yaActiva)
    }

    // MARK: Permiso

    func testPermisoDenegadoRestringidoONoDisponibleSueltanTodoYExplican() async {
        let casos: [(PermisoUbicacion, GpsAuditivoModelo.Estado, String)] = [
            (.denegado, .permisoDenegado, TextoGps.permisoDenegado),
            (.restringido, .permisoRestringido, TextoGps.permisoRestringido),
            (.noDisponible, .noDisponible, TextoGps.noDisponible),
        ]
        for (permiso, estado, texto) in casos {
            let banco = Banco()
            banco.modelo.iniciar()
            banco.ubicacion.emitir(.permiso(.porPreguntar))
            banco.ubicacion.emitir(.permiso(permiso))
            XCTAssertEqual(banco.modelo.estado, estado)
            XCTAssertEqual(banco.modelo.aviso, texto)
            XCTAssertEqual(banco.locutor.dichos.last, texto)
            XCTAssertFalse(banco.modelo.escuchando, "sin permiso no hay nada que detener")
            XCTAssertGreaterThanOrEqual(banco.ubicacion.detenidos, 1, "se suelta el sistema")
            XCTAssertFalse(banco.ubicacion.hayOyente)
            banco.ubicacion.emitir(banco.posicion()) // nadie escucha: no llega
            await dejarPasar(30)
            XCTAssertEqual(banco.peticiones, 0)
            XCTAssertNil(banco.modelo.posicionEnMapa)
        }
    }

    func testTrasConcederElPermisoEnAjustesSePuedeVolverAActivar() {
        let banco = Banco()
        banco.modelo.iniciar()
        banco.ubicacion.emitir(.permiso(.denegado))
        XCTAssertEqual(banco.modelo.estado, .permisoDenegado)
        banco.modelo.iniciar()
        XCTAssertEqual(banco.modelo.estado, .pidiendoPermiso)
        XCTAssertEqual(banco.ubicacion.iniciados, 2)
        banco.ubicacion.emitir(.permiso(.concedido))
        XCTAssertEqual(banco.modelo.estado, .buscando)
    }

    func testUnPermisoRevocadoConLaUbicacionActivaLaSuelta() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        XCTAssertNotNil(banco.modelo.respuesta)
        banco.ubicacion.emitir(.permiso(.denegado))
        XCTAssertEqual(banco.modelo.estado, .permisoDenegado)
        XCTAssertNil(banco.modelo.respuesta)
        XCTAssertNil(banco.modelo.posicionEnMapa)
        XCTAssertFalse(banco.ubicacion.hayOyente)
    }

    // MARK: La primera lectura pide una vez; el sensor no pide nada

    func testLaPrimeraLecturaVigentePideLasEstacionesUnaSolaVez() async throws {
        let banco = Banco()
        banco.activar()
        XCTAssertEqual(banco.modelo.estado, .activo)
        await banco.cliente.cercanas.esperar(1)
        XCTAssertEqual(banco.cliente.lecturas.count, 1)
        let lectura = banco.cliente.lecturas[0]
        XCTAssertEqual(lectura.latitud, 4.6124)
        XCTAssertEqual(lectura.longitud, -74.0935)
        XCTAssertEqual(lectura.precision, 10)
        XCTAssertEqual(lectura.edadMs, 0)
        XCTAssertNil(lectura.rumbo, "todavía no hay brújula")
        XCTAssertTrue(banco.modelo.consultando)

        try await banco.responder(FixturesParidad.cercanasRelativa)
        XCTAssertEqual(
            banco.locutor.dichos.last,
            "Ubicación lista. La estación más cercana es Estación Ejemplo Centro, a 40 metros al norte.")
        XCTAssertEqual(banco.modelo.respuesta?.estaciones.count, 2)
    }

    func testCientosDeEventosDelSensorNoPidenNingunaEstacionMas() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        for i in 0..<200 {
            banco.reloj.avanzar(50)
            banco.ubicacion.emitir(banco.posicion(lat: 4.6124 + Double(i) * 0.00001))
            banco.ubicacion.emitir(banco.rumbo(grados: Double(i % 360)))
        }
        await dejarPasar()
        XCTAssertEqual(banco.peticiones, 1, "ni 200 lecturas ni 200 giros de la brújula tocan la red")
    }

    func testUnaLecturaVencidaAlLlegarNoSeUsaNiSePide() async {
        let banco = Banco()
        banco.modelo.iniciar()
        banco.ubicacion.emitir(.permiso(.concedido))
        banco.ubicacion.emitir(banco.posicion(hace: 61_000)) // el sistema entrega primero una lectura guardada y vieja
        await dejarPasar(30)
        XCTAssertEqual(banco.modelo.estado, .buscando)
        XCTAssertEqual(banco.peticiones, 0)
        XCTAssertNil(banco.modelo.posicionEnMapa)

        banco.ubicacion.emitir(banco.posicion(hace: 60_000)) // exactamente 60 s todavía no está vencida
        XCTAssertEqual(banco.modelo.estado, .activo)
    }

    func testSinSenalSeDiceYLaSesionSigueBuscando() {
        let banco = Banco()
        banco.modelo.iniciar()
        banco.ubicacion.emitir(.permiso(.concedido))
        banco.ubicacion.emitir(.sinSenal)
        XCTAssertEqual(banco.modelo.estado, .buscando)
        XCTAssertEqual(banco.modelo.aviso, TextoGps.sinSenal)
        banco.ubicacion.emitir(banco.posicion())
        XCTAssertEqual(banco.modelo.estado, .activo)
        XCTAssertNil(banco.modelo.aviso)
    }

    // MARK: Lo que viaja: lo medido, sin reglas

    func testLaPrecisionQueElSistemaDaComoInvalidaONoDaNoViaja() async throws {
        for precision: Double? in [nil, -1, 100_001, .nan] {
            let banco = Banco()
            banco.activar(precision: precision)
            await banco.cliente.cercanas.esperar(1)
            XCTAssertNil(banco.cliente.lecturas[0].precision, "precisión \(String(describing: precision))")
        }
        let banco = Banco()
        banco.activar(precision: 0)
        await banco.cliente.cercanas.esperar(1)
        XCTAssertEqual(banco.cliente.lecturas[0].precision, 0, "0 m es una precisión que el servidor acepta")
    }

    func testSoloElRumboVerdaderoValidoViajaConSuEdadYSuCalidad() async {
        let banco = Banco()
        banco.modelo.iniciar()
        banco.ubicacion.emitir(.permiso(.concedido))
        banco.reloj.avanzar(2_000)
        banco.ubicacion.emitir(banco.rumbo(grados: 271.5, calidad: 12, hace: 300))
        banco.ubicacion.emitir(banco.posicion(hace: 50))
        await banco.cliente.cercanas.esperar(1)
        let lectura = banco.cliente.lecturas[0]
        XCTAssertEqual(lectura.edadMs, 50)
        XCTAssertEqual(lectura.rumbo, RumboParaEnviar(grados: 271.5, calidad: 12, edadMs: 300))
        XCTAssertEqual(banco.modelo.rumbo, .conLectura)
    }

    func testUnRumboSinCalidadONegativaViajaSinCalidadYNuncaSeInventa() async {
        for calidad: Double? in [nil, -1] {
            let banco = Banco()
            banco.modelo.iniciar()
            banco.ubicacion.emitir(.permiso(.concedido))
            banco.ubicacion.emitir(banco.rumbo(calidad: calidad))
            banco.ubicacion.emitir(banco.posicion())
            await banco.cliente.cercanas.esperar(1)
            let rumbo = banco.cliente.lecturas[0].rumbo
            XCTAssertNotNil(rumbo)
            XCTAssertNil(rumbo?.calidad, "el servidor lo trata como no fiable; el cliente no le pone un valor")
        }
    }

    func testSinRumboVerdaderoNoViajaRumboAunqueAntesHubieraUno() async {
        let banco = Banco()
        banco.modelo.iniciar()
        banco.ubicacion.emitir(.permiso(.concedido))
        banco.ubicacion.emitir(banco.rumbo())
        banco.ubicacion.emitir(.rumbo(nil)) // el sistema ya no tiene un norte verdadero: invalida el anterior
        XCTAssertEqual(banco.modelo.rumbo, .sinLectura)
        banco.ubicacion.emitir(banco.posicion())
        await banco.cliente.cercanas.esperar(1)
        XCTAssertNil(banco.cliente.lecturas[0].rumbo)
    }

    func testUnRumboMuyViejoNoViaja() async {
        let banco = Banco()
        banco.modelo.iniciar()
        banco.ubicacion.emitir(.permiso(.concedido))
        banco.reloj.avanzar(700_000)
        banco.ubicacion.emitir(banco.rumbo(hace: 600_001))
        banco.ubicacion.emitir(banco.posicion())
        await banco.cliente.cercanas.esperar(1)
        XCTAssertNil(banco.cliente.lecturas[0].rumbo, "más de 600 s no cabe en el contrato")
    }

    func testSinBrujulaLaPantallaLoDice() {
        let sin = Banco(brujula: false)
        XCTAssertEqual(sin.modelo.rumbo, .noDisponible)
        let con = Banco()
        XCTAssertEqual(con.modelo.rumbo, .sinLectura)
        con.modelo.iniciar()
        con.ubicacion.emitir(.permiso(.concedido))
        con.ubicacion.emitir(con.rumbo())
        XCTAssertEqual(con.modelo.rumbo, .conLectura)
    }

    func testLaDescripcionDeUnaLecturaNoDejaLaCoordenada() {
        let medida = PosicionMedida(latitud: 4.6124, longitud: -74.0935, precision: 12, capturadaMs: 5)
        let texto = "\(medida) \(String(reflecting: medida)) \(EventoUbicacion.posicion(medida))"
        XCTAssertFalse(texto.contains("4.6124"))
        XCTAssertFalse(texto.contains("74.0935"))
    }

    // MARK: Límite de peticiones y una sola en curso

    func testActualizarRespetaElIntervaloMinimo() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)

        banco.modelo.actualizar()
        await dejarPasar(30)
        XCTAssertEqual(banco.peticiones, 1, "antes de 10 s no se pide otra vez")
        XCTAssertEqual(banco.modelo.aviso, TextoGps.esperaUnMomento)

        banco.reloj.avanzar(GpsAuditivoModelo.intervaloMinimoMs)
        banco.ubicacion.emitir(banco.posicion())
        banco.modelo.actualizar()
        await banco.cliente.cercanas.esperar(2)
        XCTAssertEqual(banco.peticiones, 2)
        XCTAssertTrue(banco.modelo.consultando)
        XCTAssertNil(banco.modelo.aviso)
    }

    func testUnMinutoDeLecturasYDeTocarActualizarPideComoMuchoSeisVeces() async throws {
        let banco = Banco()
        banco.activar()
        var respondidas = 0
        for segundo in 0..<60 {
            if segundo > 0 { banco.reloj.avanzar(1_000) }
            banco.ubicacion.emitir(banco.posicion())
            banco.modelo.actualizar() // la persona insiste cada segundo
            await dejarPasar(15)
            while respondidas < banco.peticiones {
                try await banco.responder(FixturesParidad.cercanasRelativa)
                respondidas += 1
            }
        }
        XCTAssertEqual(banco.peticiones, 6, "una por cada 10 s: tres teléfonos no pasan de 18 por minuto, bajo el tope compartido de 60")
    }

    func testPedirOtraCosaMientrasUnaPeticionVaEnCursoNoCreaOtraYLaRespuestaDiceLoUltimoPedido() async throws {
        let banco = Banco()
        banco.activar()
        await banco.cliente.cercanas.esperar(1)
        banco.modelo.actualizar()
        banco.modelo.repetirIndicacion() // cambió de idea
        await dejarPasar(30)
        XCTAssertEqual(banco.peticiones, 1)
        try await banco.responder(FixturesParidad.cercanasRelativa)
        XCTAssertEqual(banco.locutor.dichos.last, try estacion(FixturesParidad.cercanasRelativa).orientacion.indicacion)
        XCTAssertFalse(banco.locutor.dichos.contains { $0.hasPrefix("Ubicación lista") })
    }

    func testUnFalloMuestraElErrorYNingunaLecturaLoReintentaSola() async throws {
        let banco = Banco()
        banco.activar()
        await banco.fallar(.sinConexion)
        XCTAssertEqual(banco.modelo.fallo, .sinConexion)
        XCTAssertNil(banco.modelo.respuesta)
        XCTAssertFalse(banco.modelo.consultando)

        for _ in 0..<30 {
            banco.reloj.avanzar(1_000)
            banco.ubicacion.emitir(banco.posicion())
        }
        await dejarPasar()
        XCTAssertEqual(banco.peticiones, 1, "sin reintentos automáticos: la persona decide")

        banco.modelo.actualizar()
        await banco.cliente.cercanas.esperar(2)
        try await banco.responder(FixturesParidad.cercanasRelativa)
        XCTAssertNil(banco.modelo.fallo)
        XCTAssertNotNil(banco.modelo.respuesta)
    }

    func testUnTopeDelServidorSeMuestraConSuEspera() async {
        let banco = Banco()
        banco.activar()
        await banco.fallar(.demasiadasPeticiones(reintentarEnSegundos: 5))
        XCTAssertEqual(banco.modelo.fallo, .demasiadasPeticiones(reintentarEnSegundos: 5))
        XCTAssertTrue(ErrorConsulta.demasiadasPeticiones(reintentarEnSegundos: 5).mensaje.contains("5 s"))
    }

    // MARK: Repetir, orientar y elegir una estación

    func testRepetirUnaRespuestaRecienteLaDiceSinPedirOtra() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.modelo.repetirIndicacion()
        XCTAssertEqual(banco.locutor.dichos.last, "Estación Ejemplo Centro está a 40 metros de frente.")
        XCTAssertEqual(banco.peticiones, 1)
    }

    func testRepetirConUnaRespuestaVieja_PideUnaLecturaDeAhora() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.reloj.avanzar(GpsAuditivoModelo.intervaloMinimoMs)
        banco.ubicacion.emitir(banco.posicion())
        banco.modelo.repetirIndicacion()
        await banco.cliente.cercanas.esperar(2)
        XCTAssertEqual(banco.peticiones, 2)
        try await banco.responder(FixturesParidad.cercanasCardinal)
        XCTAssertEqual(banco.locutor.dichos.last, try estacion(FixturesParidad.cercanasCardinal).orientacion.indicacion)
    }

    func testNoSeRepiteUnaRespuestaHechaSinBrujulaCuandoYaHayBrujula() async throws {
        let banco = Banco()
        banco.activar() // la primera consulta salió sin rumbo
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.ubicacion.emitir(banco.rumbo())
        let dichosAntes = banco.locutor.dichos.count
        banco.modelo.repetirIndicacion()
        await dejarPasar(30)
        XCTAssertEqual(banco.locutor.dichos.count, dichosAntes, "no se dice una indicación hecha sin brújula como si lo fuera con ella")
        XCTAssertEqual(banco.modelo.aviso, TextoGps.esperaUnMomento)
        XCTAssertEqual(banco.peticiones, 1)
    }

    func testOrientarHaciaUnaEstacionDiceLaIndicacionDelServidorConSuLimite() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.modelo.orientarHacia(norte)
        XCTAssertEqual(banco.modelo.objetivo, norte)
        XCTAssertEqual(banco.modelo.estacionElegida?.nombre, norte)
        let dicho = try XCTUnwrap(banco.locutor.dichos.last)
        XCTAssertEqual(dicho, TextoGps.orientandoHacia(try estacion(FixturesParidad.cercanasRelativa, 1)))
        XCTAssertTrue(dicho.contains("Estación Ejemplo Norte está a 5,6 kilómetros de frente."))
        XCTAssertTrue(dicho.contains("la accesibilidad del acceso no está verificada"))
        XCTAssertFalse(dicho.lowercased().contains("cruce"), "no se inventa un cruce seguro")
        XCTAssertEqual(banco.peticiones, 1)
    }

    func testSoloSePuedeOrientarHaciaUnaEstacionDeLaLista() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.modelo.orientarHacia("Estación que no existe")
        XCTAssertNil(banco.modelo.objetivo)
    }

    func testUnaEstacionElegidaQueYaNoEstaEntreLasCercanasSeSueltaYSeDice() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.reloj.avanzar(GpsAuditivoModelo.intervaloMinimoMs)
        banco.ubicacion.emitir(banco.posicion())
        banco.modelo.orientarHacia(norte) // pide una lectura de ahora
        await banco.cliente.cercanas.esperar(2)
        try await banco.responder(FixturesParidad.cercanasCardinal) // la nueva lista ya no la trae
        XCTAssertNil(banco.modelo.objetivo)
        XCTAssertEqual(banco.locutor.dichos.last, TextoGps.fueraDeLasMasCercanas(norte))
    }

    // MARK: Aviso de cercanía: solo con el indicador del servidor, una vez por estación elegida

    private func cuantasVecesDijoCercania(_ banco: Banco) -> Int {
        banco.locutor.dichos.filter { $0.contains("Estás muy cerca de") }.count
    }

    func testElAvisoDeCercaniaUsaLasPalabrasDeLaWebYNoPrometeAcceso() throws {
        let texto = TextoGps.muyCerca(try estacion(FixturesParidad.cercanasMuyCerca))
        XCTAssertEqual(
            texto,
            "Estás muy cerca de Estación Ejemplo Centro, a unos 20 metros. Busca el acceso de la estación; el punto es una referencia aproximada, no un acceso verificado.")
    }

    func testSinUnaEstacionElegidaNuncaSeAvisaDeCercania() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasMuyCerca) // el servidor marca la primera muyCerca
        banco.modelo.repetirIndicacion()
        XCTAssertEqual(cuantasVecesDijoCercania(banco), 0, "la web solo avisa de la estación que la persona eligió")
    }

    func testElServidorSinMuyCercaNuncaAvisaDeCercaniaAunqueLaEstacionEsteElegida() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasServidorAnterior)
        banco.modelo.orientarHacia(centro)
        banco.reloj.avanzar(GpsAuditivoModelo.intervaloMinimoMs)
        banco.ubicacion.emitir(banco.posicion())
        banco.modelo.actualizar()
        await banco.cliente.cercanas.esperar(2)
        try await banco.responder(FixturesParidad.cercanasServidorAnterior)
        XCTAssertEqual(cuantasVecesDijoCercania(banco), 0)
    }

    func testLaCercaniaDeLaEstacionElegidaSeDiceUnaSolaVezYSeRearmaAlElegirOtra() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.modelo.orientarHacia(centro)
        XCTAssertEqual(cuantasVecesDijoCercania(banco), 0, "el servidor todavía no la marca muyCerca")

        // La persona camina: una lectura nueva trae la estación marcada.
        banco.reloj.avanzar(GpsAuditivoModelo.intervaloMinimoMs)
        banco.ubicacion.emitir(banco.posicion())
        banco.modelo.actualizar()
        await banco.cliente.cercanas.esperar(2)
        try await banco.responder(FixturesParidad.cercanasMuyCerca)
        XCTAssertEqual(cuantasVecesDijoCercania(banco), 1)
        XCTAssertTrue(banco.locutor.dichos.last?.hasPrefix("Estaciones actualizadas.") == true)
        XCTAssertTrue(banco.locutor.dichos.last?.hasSuffix(TextoGps.muyCerca(try estacion(FixturesParidad.cercanasMuyCerca))) == true)

        // Otra lectura con la misma marca: no se repite.
        banco.reloj.avanzar(GpsAuditivoModelo.intervaloMinimoMs)
        banco.ubicacion.emitir(banco.posicion())
        banco.modelo.actualizar()
        await banco.cliente.cercanas.esperar(3)
        try await banco.responder(FixturesParidad.cercanasMuyCerca)
        XCTAssertEqual(cuantasVecesDijoCercania(banco), 1, "una vez por estación elegida")
        banco.modelo.repetirIndicacion()
        XCTAssertEqual(cuantasVecesDijoCercania(banco), 1, "repetir la indicación tampoco la repite")

        // Elegir otra estación y volver a elegir esta rearma el aviso.
        banco.modelo.orientarHacia(norte)
        banco.modelo.orientarHacia(centro)
        XCTAssertEqual(cuantasVecesDijoCercania(banco), 2)
    }

    // MARK: Ubicación vencida

    func testLaUbicacionVenceALos60SegundosYNoSePresentaComoActualNiSeEnvia() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.modelo.orientarHacia(centro)

        banco.reloj.avanzar(60_001) // sin lecturas nuevas
        await esperarHasta("que venza la lectura") { banco.modelo.estado == .vencida }
        XCTAssertNil(banco.modelo.respuesta, "las estaciones de una posición vencida no se presentan")
        XCTAssertNil(banco.modelo.posicionEnMapa)
        XCTAssertEqual(banco.modelo.aviso, TextoGps.ubicacionVencida)
        XCTAssertEqual(banco.locutor.dichos.last, TextoGps.ubicacionVencida)

        banco.modelo.actualizar()
        banco.modelo.repetirIndicacion()
        await dejarPasar(30)
        XCTAssertEqual(banco.peticiones, 1, "no se envía una coordenada vencida")
        XCTAssertTrue(banco.modelo.escuchando, "la escucha sigue: una lectura nueva la renueva")
    }

    /// Aunque el temporizador llegue tarde, una lectura de más de 60 s no sale de la app: lo comprueba el propio envío.
    func testUnaLecturaQueVencioJustoAntesDeEnviarNoSale() async throws {
        let banco = Banco(sinTemporizador: true)
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.reloj.avanzar(60_001)
        XCTAssertEqual(banco.modelo.estado, .activo, "el temporizador todavía no despertó")
        banco.modelo.actualizar()
        XCTAssertEqual(banco.modelo.estado, .vencida)
        XCTAssertEqual(banco.peticiones, 1)
        XCTAssertNil(banco.modelo.respuesta)
    }

    func testUnaLecturaNuevaRenuevaLaUbicacionVencidaYVuelveAPedirUnaVez() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.reloj.avanzar(60_001)
        await esperarHasta("que venza la lectura") { banco.modelo.estado == .vencida }

        banco.ubicacion.emitir(banco.posicion())
        XCTAssertEqual(banco.modelo.estado, .activo)
        XCTAssertNil(banco.modelo.aviso)
        await banco.cliente.cercanas.esperar(2)
        XCTAssertEqual(banco.peticiones, 2)
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.ubicacion.emitir(banco.posicion())
        await dejarPasar(30)
        XCTAssertEqual(banco.peticiones, 2)
    }

    func testSiElServidorCuentaLaLecturaComoVencidaNoHayEstacionesYSeDice() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasVencida)
        XCTAssertEqual(banco.modelo.estado, .vencida)
        XCTAssertNil(banco.modelo.respuesta)
        XCTAssertEqual(banco.locutor.dichos.last, TextoGps.ubicacionVencida)
    }

    func testSinEstacionesDelServidorSeDiceHonestamente() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasVacia)
        XCTAssertEqual(banco.modelo.estado, .activo)
        XCTAssertEqual(banco.modelo.respuesta?.estaciones.count, 0)
        XCTAssertEqual(banco.locutor.dichos.last, TextoGps.sinEstaciones)
    }

    // MARK: Detener, salir y segundo plano

    func testDetenerSueltaElSensorCancelaLaPeticionCortaLaVozYBorraTodo() async throws {
        let banco = Banco()
        banco.activar()
        banco.ubicacion.emitir(banco.rumbo())
        await banco.cliente.cercanas.esperar(1)
        banco.modelo.detener()

        XCTAssertEqual(banco.modelo.estado, .inactivo)
        XCTAssertGreaterThanOrEqual(banco.ubicacion.detenidos, 1)
        XCTAssertFalse(banco.ubicacion.hayOyente)
        XCTAssertGreaterThanOrEqual(banco.locutor.cortes, 1)
        XCTAssertNil(banco.modelo.respuesta)
        XCTAssertNil(banco.modelo.posicionEnMapa)
        XCTAssertNil(banco.modelo.precisionMetros)
        XCTAssertNil(banco.modelo.objetivo)
        XCTAssertFalse(banco.modelo.consultando)

        // La respuesta que llega tarde no se aplica ni se dice.
        let dichos = banco.locutor.dichos.count
        banco.cliente.cercanas.responder(.success(try decodificarPlanificador(FixturesParidad.cercanasRelativa)))
        await dejarPasar()
        XCTAssertNil(banco.modelo.respuesta)
        XCTAssertEqual(banco.modelo.estado, .inactivo)
        XCTAssertEqual(banco.locutor.dichos.count, dichos)
    }

    func testSuspenderPorSalirDeLaPantallaOElSegundoPlanoNoSeReanudaSola() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.modelo.orientarHacia(centro)
        banco.modelo.suspender()
        XCTAssertEqual(banco.modelo.estado, .inactivo)
        XCTAssertNil(banco.modelo.respuesta)
        XCTAssertNil(banco.modelo.objetivo)
        XCTAssertFalse(banco.ubicacion.hayOyente)

        await dejarPasar()
        banco.reloj.avanzar(120_000)
        await dejarPasar()
        XCTAssertEqual(banco.modelo.estado, .inactivo, "volver a la pantalla no activa nada: la persona lo pide")
        XCTAssertEqual(banco.ubicacion.iniciados, 1)
        XCTAssertEqual(banco.peticiones, 1)
    }

    func testSuspenderSinSesionNoHaceNada() {
        let banco = Banco()
        banco.modelo.suspender()
        XCTAssertEqual(banco.ubicacion.detenidos, 0)
        XCTAssertEqual(banco.locutor.cortes, 0)
    }

    func testUnEventoQueLlegaDespuesDeDetenerSeIgnoraAunqueElSistemaLoEntregue() async {
        let banco = Banco()
        banco.activar()
        await banco.cliente.cercanas.esperar(1)
        let viejoOyente = banco.ubicacion.alEvento // el sistema ya tenía el evento en camino
        banco.modelo.detener()
        banco.reloj.avanzar(20_000)
        viejoOyente?(banco.posicion())
        viejoOyente?(banco.rumbo())
        viejoOyente?(.permiso(.concedido))
        await dejarPasar()
        XCTAssertEqual(banco.modelo.estado, .inactivo)
        XCTAssertEqual(banco.peticiones, 1)
        XCTAssertNil(banco.modelo.posicionEnMapa)
    }

    func testDetenerYVolverAActivarEmpiezaDeNuevoSinArrastrarNada() async throws {
        let banco = Banco()
        banco.activar()
        try await banco.responder(FixturesParidad.cercanasRelativa)
        banco.modelo.orientarHacia(centro)
        banco.modelo.detener()
        banco.reloj.avanzar(5_000)

        banco.activar()
        XCTAssertNil(banco.modelo.objetivo)
        XCTAssertEqual(banco.ubicacion.iniciados, 2)
        await banco.cliente.cercanas.esperar(2)
        XCTAssertEqual(banco.cliente.lecturas.count, 2)
    }
}
