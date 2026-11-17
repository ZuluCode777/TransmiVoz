import ContratoBLE
import XCTest
@testable import TransMiVoz

/// Radar de mesa simulado (SEN0395, una trama por segundo; cada una vence a los 500 ms, contrato BLE §7). Genera tramas
/// válidas con los bytes del contrato y deja que la prueba decida CUÁNDO llegan; qué vale lo decide `SesionProximidad`.
/// Es una simulación: no prueba el radar, el enlace ni el audio reales.
@MainActor
private final class RadarDeMesa {
    enum Muestra {
        case sinBlanco
        case presencia
        case objetivo(distanciaMm: UInt16, azimutCentesimas: Int16?)
        /// Trama sana sin resultado de radar vigente (`sinDatos(.sinResultado)`).
        case sinResultado
        /// Salud distinta de 0 (`radarNoDisponible`).
        case falloRadar(salud: UInt8)
    }

    let banco: BancoAccesorio
    private let informacion: Data
    private var secuencia: UInt16 = 0
    private var emisionReferencia: UInt32 = 0
    private var inicioReferenciaMs: Milisegundos = 0

    init(_ banco: BancoAccesorio, escenario: String) throws {
        self.banco = banco
        informacion = try EscenarioBLE.cargar(escenario).informaciones[0]
    }

    /// Conexión nueva completa: Información y referencia fresca de 40 ms.
    func sincronizar() {
        banco.transporte.emitir(.conectado(id: banco.accesorio.id))
        banco.transporte.emitir(.informacion(informacion))
        resincronizar()
    }

    /// Referencia fresca: la de cada conexión nueva y la de la vuelta a primer plano.
    func resincronizar() {
        banco.reloj.avanzar(10)
        banco.transporte.emitir(.notificacionesFijadas(false))
        inicioReferenciaMs = banco.reloj.ahora
        emisionReferencia = UInt32(truncatingIfNeeded: inicioReferenciaMs)
        banco.reloj.avanzar(40)
        banco.transporte.emitir(.respuestaMedicion(trama(.sinBlanco, emision: emisionReferencia)))
        banco.transporte.emitir(.notificacionesFijadas(true))
    }

    /// Una notificación BLE llega ahora, con la edad de la fuente UART y 20 ms en el aire.
    func muestra(_ muestra: Muestra, edadRadarMs: UInt16 = 20) {
        let transcurrido = banco.reloj.ahora - inicioReferenciaMs - 20
        let emision = emisionReferencia &+ UInt32(truncatingIfNeeded: transcurrido)
        banco.transporte.emitir(.notificacionMedicion(trama(muestra, emision: emision, edadRadarMs: edadRadarMs)))
    }

    /// El temporizador de 100 ms de la sesión (`evaluar`) con el reloj falso. Cada locución dura menos que un latido.
    func latir(hasta instante: Milisegundos) {
        while banco.reloj.ahora < instante {
            banco.reloj.avanzar(min(100, instante - banco.reloj.ahora))
            banco.modelo.evaluar()
            banco.salida.terminarSola()
        }
    }

    func latir(durante ms: Milisegundos) { latir(hasta: banco.reloj.ahora + ms) }

    /// Entre dos tramas de 1 Hz: la anterior sigue fresca a los 400 ms y vence antes de los 600 ms.
    /// Devuelve el estado crudo a los 600 ms.
    @discardableResult
    func esperarSiguienteTrama() -> EstadoAccesorio {
        latir(durante: 400)
        latir(durante: 200)
        let crudo = banco.modelo.estado
        latir(durante: 400)
        return crudo
    }

    private func trama(_ muestra: Muestra, emision: UInt32, edadRadarMs: UInt16 = 20) -> Data {
        var banderas: UInt8 = 0x01
        var distancia: UInt16 = 0xFFFF
        var azimut = Int16.min
        var edad = edadRadarMs
        var salud: UInt8 = 0
        switch muestra {
        case .sinBlanco: break
        case .presencia: banderas = 0x03
        case .objetivo(let d, let a):
            banderas = a == nil ? 0x07 : 0x0F
            distancia = d
            azimut = a ?? Int16.min
        case .sinResultado: banderas = 0x00
        case .falloRadar(let s):
            banderas = 0x00
            salud = s
            edad = 0xFFFF
        }
        // El emisor real conserva la edad pero borra las medidas cuando la fuente supera 500 ms (contrato §7).
        if edad > 500 {
            banderas = 0
            distancia = 0xFFFF
            azimut = Int16.min
        }
        secuencia &+= 1
        var datos = Data([0x01, banderas, UInt8(secuencia & 0xFF), UInt8(secuencia >> 8)])
        datos += informacion[4..<8]  // identificador de arranque
        datos += Self.leU32(emision)
        datos += Self.leU16(distancia)
        datos += Self.leU16(UInt16(bitPattern: azimut))
        datos += Self.leU16(edad)
        datos += Data([0xFF, salud])  // batería desconocida y salud
        return datos
    }

    private static func leU16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func leU32(_ v: UInt32) -> Data { leU16(UInt16(v & 0xFFFF)) + leU16(UInt16(v >> 16)) }
}

/// Voz del accesorio con el radar SEN0395 de la demostración de mesa (#41, #46). El radar entrega una observación por
/// segundo y cada una vence a los 500 ms: cerca de la mitad de cada segundo el estado crudo es «sin datos». La pantalla
/// sigue mostrando ese estado tal cual; lo que se calla es la voz. Un hueco de caducidad ordinaria de menos de
/// `graciaSinDatosMs` no se dice ni borra lo ya dicho. Averías del radar, cortes del accesorio y del Bluetooth son
/// inmediatos. Son pruebas con transporte, voz y reloj falsos: no acreditan el radar, el audio ni VoiceOver reales.
@MainActor
final class VozEstableSesionAccesorioTests: XCTestCase {
    private let presencia = "Presencia detectada."
    private let sinDeteccion = "Sin detección en este momento."
    private let sinDatos = "Sin datos del sensor."

    private func montar(_ escenario: String = "activacion-sin-blanco-y-presencia") throws -> (BancoAccesorio, RadarDeMesa) {
        let banco = BancoAccesorio()
        let radar = try RadarDeMesa(banco, escenario: escenario)
        banco.iniciar()
        radar.sincronizar()
        XCTAssertEqual(banco.modelo.estado, .sinDeteccion)
        return (banco, radar)
    }

    private func dijo(_ banco: BancoAccesorio, _ texto: String) -> Int { banco.salida.dicho.filter { $0 == texto }.count }

    private func vigentes(_ banco: BancoAccesorio) -> [TipoAviso] {
        let centro = banco.modelo.centro
        return centro.avisos.filter { centro.vigente($0) }.map(\.tipo)
    }

    private func esSinDatos(_ estado: EstadoAccesorio) -> Bool {
        if case .sinDatos = estado { return true }
        return false
    }

    // MARK: Cadencia de 1 Hz: estado crudo veraz y voz sin repeticiones

    func testBleA10HzConFuenteA1HzNoRepiteLaFraseNiValidaLaFuenteVencida() throws {
        let muestras: [(RadarDeMesa.Muestra, String)] = [(.presencia, presencia), (.sinBlanco, sinDeteccion)]
        for (muestra, frase) in muestras {
            let (banco, radar) = try montar()
            defer { banco.cerrar() }
            radar.latir(durante: 100)
            radar.muestra(muestra)
            let veces = dijo(banco, frase)
            for _ in 0..<6 {
                for edad in stride(from: 120, through: 920, by: 100) {
                    radar.latir(durante: 100)
                    radar.muestra(muestra, edadRadarMs: UInt16(edad))
                    if edad > 500 {
                        XCTAssertEqual(banco.modelo.estado, .sinDatos(.sinResultado))
                        XCTAssertTrue(vigentes(banco).isEmpty, "la fuente vencida no deja una proximidad vigente")
                    }
                }
                radar.latir(durante: 100)
                radar.muestra(muestra)
            }
            XCTAssertEqual(dijo(banco, frase), veces, "la misma detección no reinicia su frase tras cada hueco")
            XCTAssertEqual(dijo(banco, sinDatos), 0, "las notificaciones de fuente vencida tampoco se hablan en cada ciclo")
        }
    }

    func testPresenciaA1HzNoRepiteLaFraseYElEstadoCrudoSigueVenciendo() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        XCTAssertEqual(banco.modelo.estado, .presencia)
        XCTAssertEqual(dijo(banco, presencia), 1)

        for _ in 1...6 {
            radar.latir(durante: 400)
            XCTAssertEqual(banco.modelo.estado, .presencia, "a los 400 ms la trama sigue fresca")
            radar.latir(durante: 200)
            XCTAssertTrue(esSinDatos(banco.modelo.estado), "a los 600 ms vence: la pantalla no muestra presencia vieja")
            XCTAssertEqual(vigentes(banco), [], "mientras la voz espera, la lista no marca vigente la presencia vencida")
            radar.latir(durante: 400)
            radar.muestra(.presencia)
            XCTAssertEqual(banco.modelo.estado, .presencia)
            XCTAssertEqual(vigentes(banco), [.proximidad], "la trama fresca vuelve a dejarla vigente")
        }
        XCTAssertEqual(dijo(banco, presencia), 1, "la misma presencia tras un hueco corto no reinicia la frase")
        XCTAssertEqual(dijo(banco, sinDatos), 0)
        XCTAssertEqual(banco.modelo.centro.avisos.map(\.tipo), [.proximidad], "sin historial nuevo por cada hueco")
    }

    func testSinDeteccionA1HzNoRepiteLaFraseYElEstadoCrudoSigueVenciendo() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        XCTAssertEqual(dijo(banco, sinDeteccion), 1)

        for _ in 1...6 {
            radar.latir(durante: 100)
            radar.muestra(.sinBlanco)
            XCTAssertEqual(banco.modelo.estado, .sinDeteccion)
            XCTAssertTrue(esSinDatos(radar.esperarSiguienteTrama()), "el estado crudo vence a los 500 ms")
        }
        XCTAssertEqual(dijo(banco, sinDeteccion), 1)
        XCTAssertEqual(dijo(banco, sinDatos), 0)
        XCTAssertEqual(banco.modelo.centro.avisos.map(\.tipo), [], "sin detección es rutina: no entra en la lista de avisos")
    }

    func testUnObjetivoIgualTrasUnHuecoCortoNoRepiteLaFraseYUnoDistintoSi() throws {
        let (banco, radar) = try montar("objetivo-distancia-y-azimut")
        defer { banco.cerrar() }
        let frase1 = "Objeto a 1 metro, a la izquierda."
        let frase2 = "Objeto a 1,5 metros."
        for _ in 1...4 {
            radar.latir(durante: 100)
            radar.muestra(.objetivo(distanciaMm: 1200, azimutCentesimas: -3000))
            radar.esperarSiguienteTrama()
        }
        XCTAssertEqual(dijo(banco, frase1), 1)
        for _ in 1...4 {
            radar.latir(durante: 100)
            radar.muestra(.objetivo(distanciaMm: 1500, azimutCentesimas: nil))
            radar.esperarSiguienteTrama()
        }
        XCTAssertEqual(dijo(banco, frase2), 1, "la distancia cambió de verdad: se dice una vez")
        XCTAssertEqual(dijo(banco, frase1), 1)
        XCTAssertEqual(dijo(banco, sinDatos), 0)
    }

    // MARK: Un cambio real se dice

    func testUnCambioRealTrasUnHuecoCortoSeDiceUnaVez() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.esperarSiguienteTrama()
        radar.muestra(.presencia)
        XCTAssertEqual(dijo(banco, presencia), 1)

        radar.esperarSiguienteTrama()
        radar.muestra(.sinBlanco)
        XCTAssertEqual(banco.modelo.estado, .sinDeteccion)
        XCTAssertEqual(dijo(banco, sinDeteccion), 2, "la presencia terminó de verdad: se dice «sin detección»")
        XCTAssertEqual(banco.salida.dicho.last, sinDeteccion)
        XCTAssertEqual(vigentes(banco), [], "la proximidad quedó cerrada")

        radar.esperarSiguienteTrama()
        radar.muestra(.sinBlanco)
        XCTAssertEqual(dijo(banco, sinDeteccion), 2, "igual tras el hueco: no se repite")

        radar.esperarSiguienteTrama()
        radar.muestra(.presencia)
        XCTAssertEqual(dijo(banco, presencia), 2, "volvió a haber presencia de verdad")
        XCTAssertEqual(banco.salida.dicho.last, presencia)
        XCTAssertEqual(dijo(banco, sinDatos), 0)
    }

    // MARK: Gracia de 2 s exactos de «sin datos» continuo

    func testLaGraciaTerminaALos2000msDeSinDatosContinuoYNoAntes() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        while !esSinDatos(banco.modelo.estado) { radar.latir(durante: 100) }
        let inicio = banco.reloj.ahora  // el latido de 100 ms que ve el estado crudo vencido
        XCTAssertEqual(SesionAccesorioModelo.graciaSinDatosMs, 2_000)

        banco.reloj.fijar(inicio + 1_999)
        banco.modelo.evaluar()
        XCTAssertTrue(esSinDatos(banco.modelo.estado))
        XCTAssertEqual(dijo(banco, sinDatos), 0, "a 1 999 ms todavía es un hueco ordinario")
        XCTAssertEqual(vigentes(banco), [])

        banco.reloj.fijar(inicio + 2_000)
        banco.modelo.evaluar()
        XCTAssertEqual(dijo(banco, sinDatos), 1, "a los 2 000 ms continuos se avisa")
        XCTAssertEqual(vigentes(banco), [.datoVencido])

        radar.latir(durante: 3_000)
        XCTAssertEqual(dijo(banco, sinDatos), 1, "una caída continua no repite el aviso")
        XCTAssertEqual(dijo(banco, presencia), 1)
    }

    func testUnaTramaFrescaAntesDelUmbralCancelaElHuecoYElSiguienteCuentaDeNuevo() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        while !esSinDatos(banco.modelo.estado) { radar.latir(durante: 100) }
        let inicio = banco.reloj.ahora
        radar.latir(hasta: inicio + 1_900)
        radar.muestra(.presencia)
        XCTAssertEqual(banco.modelo.estado, .presencia)
        XCTAssertEqual(dijo(banco, sinDatos), 0)

        // Un hueco nuevo empieza de cero: a 1 500 ms de su inicio aún no se avisa, aunque desde el primer hueco ya pasaron
        // más de 2 000 ms.
        while !esSinDatos(banco.modelo.estado) { radar.latir(durante: 100) }
        let segundoInicio = banco.reloj.ahora
        XCTAssertGreaterThan(segundoInicio + 1_500 - inicio, 2_000)
        radar.latir(hasta: segundoInicio + 1_500)
        XCTAssertEqual(dijo(banco, sinDatos), 0)
        radar.latir(hasta: segundoInicio + 2_000)
        XCTAssertEqual(dijo(banco, sinDatos), 1)
    }

    func testTrasUnaCaidaContinuaLaRecuperacionDiceElEstadoDeAhora() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 4_000)
        XCTAssertEqual(dijo(banco, sinDatos), 1)
        XCTAssertEqual(vigentes(banco), [.datoVencido])

        radar.muestra(.presencia)
        XCTAssertEqual(banco.salida.dicho.last, presencia, "la misma presencia de antes, pero tras el aviso de caída: se dice")
        XCTAssertEqual(dijo(banco, presencia), 2)
        XCTAssertEqual(vigentes(banco), [.proximidad], "el aviso de datos vencidos se cerró")

        // Y desde ahí los huecos cortos vuelven a ser silenciosos.
        radar.esperarSiguienteTrama()
        radar.muestra(.presencia)
        XCTAssertEqual(dijo(banco, presencia), 2)
        XCTAssertEqual(dijo(banco, sinDatos), 1)
    }

    // MARK: Lo que no tiene gracia

    func testLaAveriaDelRadarSeDiceAlInstanteAunqueVengaTrasUnHueco() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 700)  // ya en el hueco ordinario
        radar.muestra(.falloRadar(salud: 2))
        XCTAssertEqual(banco.modelo.estado, .radarNoDisponible(.radarSinDatos))
        XCTAssertEqual(banco.salida.dicho.last, "Radar no disponible.", "una avería de salud no espera gracia alguna")
        XCTAssertEqual(vigentes(banco), [.datoVencido])
    }

    func testLaFuenteVencidaUsaLaGraciaAunqueLleguenNotificacionesCada100ms() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 200)
        radar.muestra(.presencia, edadRadarMs: 800)
        XCTAssertEqual(banco.modelo.estado, .sinDatos(.sinResultado))
        for edad in stride(from: 900, through: 2700, by: 100) {
            radar.latir(durante: 100)
            radar.muestra(.presencia, edadRadarMs: UInt16(edad))
            XCTAssertEqual(banco.modelo.estado, .sinDatos(.sinResultado))
        }
        radar.latir(durante: 99)
        radar.muestra(.presencia, edadRadarMs: 2799)
        XCTAssertEqual(dijo(banco, sinDatos), 0, "a los 1999 ms el mismo hueco sigue sin hablar")
        XCTAssertTrue(vigentes(banco).isEmpty)
        radar.latir(durante: 1)
        radar.muestra(.presencia, edadRadarMs: 2800)
        XCTAssertEqual(dijo(banco, sinDatos), 1, "a los 2000 ms avisa pese a recibir BLE cada 100 ms")
        XCTAssertEqual(vigentes(banco), [.datoVencido])
    }

    func testPerderElAccesorioDuranteUnHuecoSeDiceAlInstanteYLaReconexionEmpiezaDeCero() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 700)
        XCTAssertEqual(dijo(banco, sinDatos), 0)

        banco.transporte.emitir(.desconectado)
        XCTAssertEqual(banco.salida.dicho.last, "Accesorio desconectado.")
        XCTAssertEqual(vigentes(banco), [.accesorioPerdido])
        XCTAssertEqual(banco.modelo.estadoSesion, .desconectada)

        radar.latir(durante: 4_000)
        XCTAssertEqual(dijo(banco, sinDatos), 0, "lo del enlace anterior no se dice después")
        radar.sincronizar()
        XCTAssertEqual(banco.salida.dicho.suffix(2), ["Accesorio conectado. Calibrando. Aún sin avisos.", sinDeteccion])
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        XCTAssertEqual(dijo(banco, presencia), 2, "la conexión nueva no hereda lo dicho en la anterior")
    }

    func testElBluetoothApagadoDuranteUnHuecoSeDiceAlInstante() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 700)
        banco.transporte.emitir(.disponibilidad(.apagado), token: tokenSinConexion)
        XCTAssertEqual(banco.salida.dicho.last, "Bluetooth no disponible. Sin avisos.")
        XCTAssertEqual(vigentes(banco), [.accesorioPerdido])
    }

    func testPerderLosAuricularesDuranteUnHuecoVibraYAvisaAlInstante() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 700)
        banco.ruta.valor = .noPrivada
        banco.modelo.voz.rutaCambio()
        XCTAssertEqual(banco.avisos.vibraciones, 1)
        XCTAssertEqual(banco.avisos.anuncios.last, TextoAccesorio.audioSinAuriculares)
        XCTAssertEqual(dijo(banco, sinDatos), 0)
    }

    // MARK: Ciclo de vida: nada de un hueco anterior sobrevive

    func testDetenerYVolverAIniciarOlvidanElHuecoYLoDicho() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 700)

        banco.modelo.detener()
        radar.latir(durante: 3_000)
        XCTAssertEqual(dijo(banco, sinDatos), 0, "detenida no habla")
        banco.iniciar()
        radar.sincronizar()
        XCTAssertEqual(dijo(banco, sinDeteccion), 2, "sesión nueva: «sin detección» se dice de nuevo")
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        XCTAssertEqual(dijo(banco, presencia), 2)

        // El hueco de la sesión nueva cuenta desde su propio inicio, no desde el de la anterior.
        radar.latir(durante: 1_500)
        XCTAssertEqual(dijo(banco, sinDatos), 0)
    }

    func testSuspenderDescartaElHuecoYAlVolverSoloSeDiceElEstadoDeAhora() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 700)

        banco.modelo.escenaActiva(false)
        XCTAssertFalse(vigentes(banco).contains(.proximidad))
        banco.reloj.avanzar(5_000)
        banco.modelo.escenaActiva(true)
        XCTAssertEqual(banco.salida.dicho.last, "Accesorio conectado. Calibrando. Aún sin avisos.", "el estado de ahora, no el viejo")
        XCTAssertEqual(dijo(banco, sinDatos), 0)

        radar.resincronizar()
        XCTAssertEqual(banco.salida.dicho.last, sinDeteccion)
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        XCTAssertEqual(dijo(banco, presencia), 2, "tras reanudar la presencia se dice de nuevo: nada de antes de suspender sigue en pie")
        XCTAssertEqual(dijo(banco, sinDatos), 0)
    }

    // MARK: Repetir y recuperación del audio

    func testRepetirDuranteUnHuecoNoRepiteLoViejoYTrasLaTramaFrescaDiceLoActual() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        let centro = banco.modelo.centro
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        radar.latir(durante: 700)
        XCTAssertTrue(esSinDatos(banco.modelo.estado))

        let dicho = banco.salida.dicho
        centro.repetir(.proximidad)
        XCTAssertEqual(centro.resultadoRepeticion, TextoAvisos.yaNoVigente, "la presencia ya venció: no se repite")
        XCTAssertEqual(banco.salida.dicho, dicho)

        radar.latir(durante: 300)
        radar.muestra(.presencia)
        centro.repetir(.proximidad)
        XCTAssertEqual(centro.resultadoRepeticion, TextoAvisos.repitiendo)
        XCTAssertEqual(banco.salida.dicho.last, presencia)
        XCTAssertEqual(dijo(banco, presencia), 2, "solo la repetición pedida")
    }

    func testRecuperarElAudioDuranteUnHuecoNoRepiteUnaPresenciaVencida() throws {
        let (banco, radar) = try montar()
        defer { banco.cerrar() }
        radar.latir(durante: 100)
        radar.muestra(.presencia)
        banco.modelo.voz.interrupcion(comenzo: true)
        radar.latir(durante: 700)  // el estado crudo vence con la llamada en curso
        banco.modelo.voz.interrupcion(comenzo: false)
        XCTAssertEqual(banco.salida.dicho.last, sinDatos, "se revalida: el estado de ahora es sin datos, no la presencia vieja")
        XCTAssertEqual(dijo(banco, presencia), 1)

        radar.muestra(.presencia)
        XCTAssertEqual(banco.salida.dicho.last, presencia, "la trama fresca tras lo dicho al recuperar: se dice")
    }
}
