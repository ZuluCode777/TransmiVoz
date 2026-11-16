import SwiftUI

/// El `Locutor` de producción: dice por `ControlVoz`, el único dueño de la voz y de la sesión de audio de la app (el mismo
/// que usan los avisos del accesorio y la respuesta hablada de la consulta). No crea un sintetizador ni toca `AVAudioSession`.
///
/// Sin `ControlVoz`, o si la voz de la app se calla porque la persona usa VoiceOver, la ruta de audio no es privada o la
/// apagó, el texto se anuncia con VoiceOver (que solo suena si está activo) y siempre queda en pantalla. Si calla porque
/// suena un aviso más importante del accesorio o hay una interrupción, no se anuncia nada más: no se compite con él.
@MainActor
final class LocutorControlVoz: Locutor {
    private let voz: ControlVoz?
    /// `ControlVoz.locuciones` al empezar la última locución de este locutor; `nil` si no hay una que cortar.
    private var locucionPropia: Int?

    init(voz: ControlVoz?) {
        self.voz = voz
    }

    func decir(_ texto: String) {
        guard let voz else {
            AccessibilityNotification.Announcement(texto).post()
            return
        }
        switch voz.anunciar(texto, prioridad: .rutina) {
        case .hablado:
            locucionPropia = voz.locuciones
        case .silenciado(let motivo):
            switch motivo {
            case .cedeAUnAviso, .interrumpido: break
            case .rutaNoPrivada, .audioNoDisponible, .vozApagada, .severidadSilenciada:
                AccessibilityNotification.Announcement(texto).post()
            }
        }
    }

    func cortarLoPropio() {
        guard let voz, let propia = locucionPropia else { return }
        locucionPropia = nil
        // Si después habló otro (un aviso del accesorio), la locución propia ya la cortó la cola de uno: no se toca la ajena.
        if voz.locuciones == propia { voz.descartarTodo() }
    }
}
