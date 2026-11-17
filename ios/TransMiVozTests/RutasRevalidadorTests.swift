import XCTest
@testable import TransMiVoz

/// Reloj de prueba: cada `dormir` queda esperando hasta que la prueba lo despierta con `avanzar`. No respeta la cancelación
/// a propósito: modela una tarea que despierta tarde, después de que la pantalla ya se fue.
final class RelojControlable: @unchecked Sendable {
    private let candado = NSLock()
    private var pendientes: [CheckedContinuation<Void, Error>] = []
    private var pedidas: [Duration] = []

    func dormir(_ duracion: Duration) async throws {
        try await withCheckedThrowingContinuation { (continuacion: CheckedContinuation<Void, Error>) in
            candado.lock()
            pendientes.append(continuacion)
            pedidas.append(duracion)
            candado.unlock()
        }
    }

    /// Cuántas tareas están dormidas ahora.
    var esperando: Int { candado.lock(); defer { candado.unlock() }; return pendientes.count }
    /// Lo que pidió cada `dormir`, en orden.
    var duraciones: [Duration] { candado.lock(); defer { candado.unlock() }; return pedidas }

    /// Despierta la tarea que lleva más tiempo dormida.
    func avanzar() {
        candado.lock()
        guard !pendientes.isEmpty else { candado.unlock(); return }
        let continuacion = pendientes.removeFirst()
        candado.unlock()
        continuacion.resume()
    }
}

@MainActor
final class Contador {
    private(set) var cuenta = 0
    func sumar() { cuenta += 1 }
}

/// Espera, con tope, a que la condición se cumpla (las tareas del reloj saltan al hilo principal más tarde).
@MainActor
func esperarHasta(_ condicion: @autoclosure () -> Bool) async {
    for _ in 0..<500 where !condicion() { try? await Task.sleep(nanoseconds: 10_000_000) }
}

/// El reloj de 30 s de `trip-view.tsx` y `route-detail.tsx`: cuenta solo mientras la pantalla se ve y no deja nada vivo al irse.
@MainActor
final class RevalidadorPeriodicoTests: XCTestCase {
    private func armar() -> (RevalidadorPeriodico, RelojControlable, Contador) {
        let reloj = RelojControlable()
        let revalidador = RevalidadorPeriodico(dormir: { try await reloj.dormir($0) })
        let contador = Contador()
        revalidador.alVencer = { contador.sumar() }
        return (revalidador, reloj, contador)
    }

    func testElIntervaloPorDefectoEsElDeLaWeb() async {
        XCTAssertEqual(RevalidadorPeriodico.intervaloPorDefecto, .seconds(30))
    }

    func testCuentaUnIntervaloCompletoAntesDelPrimerAvisoYSigueMientrasEstaActivo() async {
        let (revalidador, reloj, contador) = armar()
        XCTAssertFalse(revalidador.activo)
        revalidador.iniciar()
        XCTAssertTrue(revalidador.activo)
        await esperarHasta(reloj.esperando == 1)
        XCTAssertEqual(reloj.duraciones, [.seconds(30)])
        XCTAssertEqual(contador.cuenta, 0, "al iniciar no avisa: el primer aviso llega un intervalo después")

        reloj.avanzar()
        await esperarHasta(contador.cuenta == 1)
        await esperarHasta(reloj.esperando == 1)
        reloj.avanzar()
        await esperarHasta(contador.cuenta == 2)
        XCTAssertEqual(contador.cuenta, 2)
    }

    func testDetenerCortaElRelojAunqueLaTareaDespierteTarde() async {
        let (revalidador, reloj, contador) = armar()
        revalidador.iniciar()
        await esperarHasta(reloj.esperando == 1)
        revalidador.detener()
        XCTAssertFalse(revalidador.activo)

        reloj.avanzar() // la tarea cancelada despierta: no entrega nada
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(contador.cuenta, 0)
        XCTAssertEqual(reloj.esperando, 0, "no queda otra espera pedida")
    }

    func testIniciarDosVecesNoDuplicaElReloj() async {
        let (revalidador, reloj, _) = armar()
        revalidador.iniciar()
        revalidador.iniciar()
        await esperarHasta(reloj.esperando >= 1)
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(reloj.esperando, 1)
    }

    func testUnCicloNuevoNoHeredaElAvisoDelCicloAnterior() async {
        let (revalidador, reloj, contador) = armar()
        revalidador.iniciar()
        await esperarHasta(reloj.esperando == 1)
        revalidador.detener()
        revalidador.iniciar() // la pantalla volvió a verse
        await esperarHasta(reloj.esperando == 2)

        reloj.avanzar() // despierta la tarea del ciclo anterior: no avisa
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(contador.cuenta, 0)
        reloj.avanzar() // la del ciclo vigente
        await esperarHasta(contador.cuenta == 1)
        XCTAssertEqual(contador.cuenta, 1)
    }
}
