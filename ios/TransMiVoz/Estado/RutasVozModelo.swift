import Foundation
import Observation

/// Búsqueda de rutas por voz: la superposición de `components/voice-overlay.tsx`. Reutiliza el dictado de la app
/// (`DictadoModelo`, el mismo de la consulta): permisos, capacidad, corte de la voz propia y respeto a los avisos del
/// accesorio vienen de ahí. Este modelo solo lo abre y lo cierra, enseña lo que se va oyendo y entrega el texto final.
///
/// - El dictado es uno solo y también lo usa la consulta con su propio campo. Mientras la superposición está abierta
///   el texto reconocido va a `transcripcion`, y al cerrarla el destino de antes se restituye tal cual (`cerrar`).
/// - Como `handleVoiceTranscript` de la web, el texto FINAL se entrega una sola vez (`entregas`, `ultimoEntregado`) y la
///   superposición se cierra; quien la muestra lo pone en el campo y busca. Lo parcial nunca busca. Escribir a mano
///   sigue siendo la alternativa: cerrar no cambia el campo.
/// - Cerrar ABORTA la captura (como `abort()` en la web): lo que ya oyó se descarta y no llega una búsqueda tardía.
/// - Al abrir se dice «Te escucho…» y la captura empieza `espera` después, para que el anuncio no entre como voz.
@MainActor
@Observable
final class RutasVozModelo {
    private(set) var abierta = false
    /// Lo que el dictado lleva oído en la captura actual (parcial o final).
    private(set) var transcripcion = ""
    /// Cuántas veces se entregó un texto final, y cuál fue el último. La vista observa el contador.
    private(set) var entregas = 0
    private(set) var ultimoEntregado: String?

    /// `nil` si quien armó los servicios no entregó el dictado: la superposición lo dice y se escribe a mano.
    let dictado: DictadoModelo?

    @ObservationIgnored private let espera: Duration
    @ObservationIgnored private let anunciar: @MainActor (String) -> Void
    @ObservationIgnored private var destinoAnterior: (@MainActor (String) -> Void)?
    @ObservationIgnored private var tarea: Task<Void, Never>?

    init(dictado: DictadoModelo?, espera: Duration = .milliseconds(1200), anunciar: @escaping @MainActor (String) -> Void = { _ in }) {
        self.dictado = dictado
        self.espera = espera
        self.anunciar = anunciar
    }

    var disponible: Bool { dictado != nil }

    func abrir() {
        guard !abierta else { return }
        abierta = true
        transcripcion = ""
        guard let dictado else { return }
        // Una captura de otra pantalla (la consulta) se corta: el micrófono es de quien lo abre ahora.
        if dictado.estado.enCurso { dictado.cancelar() }
        destinoAnterior = dictado.alTexto
        dictado.alTexto = { [weak self] texto in self?.transcripcion = texto }
        dictado.olvidarUltimoDictado()
        anunciar(TextoRutas.vozTeEscucho)
        tarea = Task { [weak self, espera] in
            try? await Task.sleep(for: espera)
            guard !Task.isCancelled, let self, self.abierta, let dictado = self.dictado, !dictado.estado.enCurso else { return }
            dictado.alternar()
        }
    }

    /// El botón «Detener» / «Hablar de nuevo».
    func alternar() {
        guard let dictado else { return }
        if !dictado.estado.enCurso { transcripcion = "" }
        dictado.alternar()
    }

    /// El estado del dictado cambió. Una captura que termina con texto (`inactivo` con `ultimoDictado`) es el texto final.
    func estadoCambio(_ nuevo: EstadoDictado) {
        guard abierta, nuevo == .inactivo, let dictado, let texto = dictado.ultimoDictado else { return }
        dictado.olvidarUltimoDictado()
        ultimoEntregado = texto
        entregas += 1
        cerrar()
    }

    func cerrar() {
        guard abierta else { return }
        abierta = false
        tarea?.cancel()
        tarea = nil
        guard let dictado else { return }
        dictado.cancelar()
        dictado.alTexto = destinoAnterior
        destinoAnterior = nil
    }
}
