import Foundation

/// Aviso periódico mientras una pantalla está a la vista: es el `setInterval` de 30 s de la web (`REVALIDA_MS` en
/// `components/trip-view.tsx` y el reloj de `components/route-detail.tsx`), pero atado a la vida de la pantalla. La
/// pantalla llama a `iniciar` al aparecer y a `detener` al desaparecer o pasar a segundo plano; detenido, no queda
/// ninguna tarea y un vencimiento que llegue tarde no se entrega.
///
/// La web re-evalúa en el propio navegador el calendario y las paradas con la hora de ahora. En el iPhone esa decisión
/// es del servidor (`calendario`, `paradaVerificada`, `resultado`), así que cada vencimiento vuelve a pedirle el estado:
/// aquí solo se mide el tiempo.
@MainActor
final class RevalidadorPeriodico {
    /// `REVALIDA_MS` de la web: 30 000 ms.
    nonisolated static let intervaloPorDefecto: Duration = .seconds(30)

    /// Se llama en cada vencimiento, en el hilo principal. Solo mientras está activo.
    var alVencer: (@MainActor () -> Void)?
    private(set) var activo = false

    private let intervalo: Duration
    private let dormir: @Sendable (Duration) async throws -> Void
    private var tarea: Task<Void, Never>?
    /// Cada `iniciar` tiene la suya: la tarea de un ciclo anterior no entrega nada aunque despierte tarde.
    private var generacion = 0

    /// `dormir` existe para que las pruebas controlen el tiempo; en la app es `Task.sleep`. Sin aislamiento para poder usarlo
    /// como valor por defecto de otros inicializadores; solo guarda dos valores inmutables.
    nonisolated init(
        intervalo: Duration = RevalidadorPeriodico.intervaloPorDefecto,
        dormir: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.intervalo = intervalo
        self.dormir = dormir
    }

    /// Empieza a contar. Si ya está activo no hace nada: el primer vencimiento llega un intervalo después, no ya.
    func iniciar() {
        guard tarea == nil else { return }
        activo = true
        generacion += 1
        let mia = generacion
        tarea = Task { [weak self, intervalo, dormir] in
            while !Task.isCancelled {
                do { try await dormir(intervalo) } catch { return }
                guard !Task.isCancelled, let self, self.generacion == mia else { return }
                self.alVencer?()
            }
        }
    }

    func detener() {
        tarea?.cancel()
        tarea = nil
        activo = false
        generacion += 1
    }
}
