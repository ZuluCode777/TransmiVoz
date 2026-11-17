import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// El `Locutor` de producción: dice por `ControlVoz`, el único dueño de la voz y de la sesión de audio de la app (el mismo
/// que usan los avisos del accesorio y la respuesta hablada de la consulta). No crea un sintetizador ni toca `AVAudioSession`.
///
/// **No tapa ninguna locución ajena.** `ControlVoz.anunciar` con la misma prioridad CORTA lo que suene (la cola es de uno): un
/// aviso de rutina del accesorio o la respuesta de la consulta quedarían cortados por una frase de una pantalla. Por eso, igual
/// que la consulta, si suena algo que no es de este locutor la frase no se dice (`.ocupada`) y queda en pantalla.
///
/// Si la voz de la app calla (VoiceOver activo sin haberla encendido, ruta no privada, voz apagada) la frase se anuncia con
/// VoiceOver cuando quien llama lo pide; ante una interrupción del sistema no se anuncia nada más.
@MainActor
final class LocutorControlVoz: Locutor {
    private let voz: ControlVoz?
    private let anunciador: @MainActor (String) -> Void
    /// `ControlVoz.locuciones` al empezar la última locución de este locutor; `nil` si no hay una que cortar.
    private var locucionPropia: Int?

    /// `voz` es `nil` solo en las pruebas y en vistas previas: la app arma este locutor con la `ControlVoz` de `EntornoApp`.
    init(voz: ControlVoz?, anunciador: @escaping @MainActor (String) -> Void = LocutorControlVoz.anunciarConVoiceOver) {
        self.voz = voz
        self.anunciador = anunciador
    }

    /// VoiceOver no mueve el foco con un anuncio: lo dice y sigue.
    static func anunciarConVoiceOver(_ texto: String) {
        #if canImport(SwiftUI)
        AccessibilityNotification.Announcement(texto).post()
        #endif
    }

    func decir(_ texto: String, anunciarConVoiceOver: Bool) -> ResultadoLocucion {
        guard let voz else {
            guard anunciarConVoiceOver else { return .silenciada }
            anunciador(texto)
            return .anunciada
        }
        // Suena algo que no es nuestro (un aviso del accesorio, también uno de rutina, o la consulta): ni se corta ni se tapa.
        if voz.hablando && locucionPropia != voz.locuciones { return .ocupada }
        switch voz.anunciar(texto, prioridad: .rutina) {
        case .hablado:
            locucionPropia = voz.locuciones
            return .hablada
        case .silenciado(let motivo):
            switch motivo {
            case .cedeAUnAviso, .interrumpido:
                return .ocupada
            case .rutaNoPrivada, .audioNoDisponible, .vozApagada, .severidadSilenciada:
                guard anunciarConVoiceOver else { return .silenciada }
                anunciador(texto)
                return .anunciada
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
