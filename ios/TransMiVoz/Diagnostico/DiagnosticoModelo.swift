import Foundation
import Observation

/// Las pruebas del diagnóstico, en el orden en que las corre «Probar todo» (web: `CHECKS` de `components/diagnostics.tsx`).
/// La web además prueba el contexto seguro, los mapas y la ubicación; la app para iPhone no usa ubicación ni baja mapas
/// por su cuenta, y su contexto es siempre seguro (HTTPS), así que esas no están aquí.
enum PruebaDiagnostico: String, CaseIterable, Identifiable, Sendable {
    /// El servidor de Ajustes responde (`GET /api/anuncios`, por `ClienteAnunciosHTTP`).
    case servidor
    /// El asistente responde (`POST /api/agent`, por `ClienteAgenteHTTP`).
    case asistente
    /// El planificador de rutas responde (`POST /api/planificador`, operación `listar-lugares`, por `ClientePlanificadorHTTP`).
    case planificador
    case voz
    case reconocimiento
    case microfono
    case camara
    case bluetooth

    var id: String { rawValue }
}

/// Cómo terminó una prueba. «Atención» no es un fallo ni un éxito: la prueba no pudo confirmar nada y dice qué falta
/// (por ejemplo, un permiso que todavía no se ha pedido). Solo «correcto» cuenta como correcta.
enum EstadoPrueba: Equatable, Sendable {
    case correcto, atencion, fallo
}

struct ResultadoPrueba: Equatable, Sendable {
    let estado: EstadoPrueba
    let detalle: String
}

/// Lo que muestra una fila. Un resultado solo existe si la prueba corrió: nada se da por bueno de antemano.
enum FilaDiagnostico: Equatable, Sendable {
    case sinProbar
    case probando
    case terminada(ResultadoPrueba)
}

/// Una comprobación en vivo en este iPhone. Nunca lanza: todo lo que pasa es un `ResultadoPrueba` con su texto.
protocol SondaDiagnostico: Sendable {
    func ejecutar() async -> ResultadoPrueba
}

/// Sonda de las pruebas de interfaz: un resultado fijo con la misma redacción que el real, rotulado «[SIMULADO]». Solo se
/// monta con `EntornoApp.modoPruebas` (compilación de depuración): sin permisos, audio, cámara ni Bluetooth reales.
struct SondaSintetica: SondaDiagnostico {
    let resultado: ResultadoPrueba

    func ejecutar() async -> ResultadoPrueba { DiagnosticoTexto.simulado(resultado) }
}

/// Estado del diagnóstico: una fila por prueba y las tareas que las corren. Cada prueba pasa por su sonda; sin sonda es un
/// fallo, nunca un éxito. Salir de la pantalla cancela lo que esté corriendo y esas filas vuelven a «sin probar»: el
/// resultado de una prueba cancelada no se informa.
@MainActor
@Observable
final class DiagnosticoModelo {
    /// Plazo de una prueba. Las del servidor ya traen el suyo (12 s) y el Bluetooth el suyo (3 s); este es el tope de todas.
    static let plazoPorDefecto: TimeInterval = 20

    private(set) var filas: [PruebaDiagnostico: FilaDiagnostico]
    /// «Probar todo» está corriendo (entre una prueba y la siguiente ninguna fila está «probando»).
    private(set) var todoEnCurso = false

    @ObservationIgnored private let sondas: [PruebaDiagnostico: any SondaDiagnostico]
    @ObservationIgnored private let plazo: TimeInterval
    @ObservationIgnored private var tareas: [PruebaDiagnostico: Task<Void, Never>] = [:]
    @ObservationIgnored private var tareaTodo: Task<Void, Never>?

    init(sondas: [PruebaDiagnostico: any SondaDiagnostico], plazo: TimeInterval = DiagnosticoModelo.plazoPorDefecto) {
        self.sondas = sondas
        self.plazo = plazo
        filas = Dictionary(uniqueKeysWithValues: PruebaDiagnostico.allCases.map { ($0, FilaDiagnostico.sinProbar) })
    }

    func fila(_ prueba: PruebaDiagnostico) -> FilaDiagnostico { filas[prueba] ?? .sinProbar }

    var total: Int { PruebaDiagnostico.allCases.count }

    var correctas: Int {
        filas.values.filter { fila in
            if case .terminada(let resultado) = fila { return resultado.estado == .correcto }
            return false
        }.count
    }

    /// Hay algo corriendo ahora mismo.
    var ocupado: Bool { todoEnCurso || filas.values.contains(.probando) }

    /// Corre una prueba y espera su resultado. Si ya está corriendo, no hace nada.
    func ejecutar(_ prueba: PruebaDiagnostico) async {
        guard fila(prueba) != .probando else { return }
        guard let sonda = sondas[prueba] else {
            filas[prueba] = .terminada(ResultadoPrueba(estado: .fallo, detalle: DiagnosticoTexto.sinSonda))
            return
        }
        filas[prueba] = .probando
        let resultado: ResultadoPrueba
        do {
            resultado = try await conPlazo(plazo) { await sonda.ejecutar() }
        } catch {
            resultado = ResultadoPrueba(estado: .fallo, detalle: DiagnosticoTexto.sinRespuesta)
        }
        // Cancelada (la persona salió o repitió la prueba): su resultado no se informa.
        if Task.isCancelled {
            filas[prueba] = .sinProbar
            return
        }
        filas[prueba] = .terminada(resultado)
    }

    /// Lanza una prueba sin esperarla (el botón «Probar» de su fila).
    func iniciar(_ prueba: PruebaDiagnostico) {
        guard !ocupado else { return }
        tareas[prueba] = Task { await ejecutar(prueba) }
    }

    /// «Probar todo»: una prueba tras otra, en el orden de `PruebaDiagnostico`, como la web.
    func iniciarTodo() {
        guard !ocupado else { return }
        todoEnCurso = true
        tareaTodo = Task {
            for prueba in PruebaDiagnostico.allCases {
                if Task.isCancelled { break }
                await ejecutar(prueba)
            }
            todoEnCurso = false
        }
    }

    /// Corta lo que esté corriendo. Las filas que no terminaron vuelven a «sin probar».
    func cancelar() {
        tareaTodo?.cancel()
        for tarea in tareas.values { tarea.cancel() }
        tareas = [:]
        tareaTodo = nil
        todoEnCurso = false
    }
}
