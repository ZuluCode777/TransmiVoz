import Foundation

/// Cómo dice la pantalla «Mapa y GPS» sus orientaciones habladas. La implementa `LocutorControlVoz` sobre `ControlVoz`, el
/// ÚNICO dueño de la voz y de la sesión de audio: esta pantalla no crea sintetizador ni toca `AVAudioSession`.
@MainActor
protocol Locutor: AnyObject {
    /// Dice `texto`. La voz de la app se calla con VoiceOver activo, con una ruta de audio que no es privada o ante un aviso
    /// más importante del accesorio: el texto siempre queda en pantalla.
    func decir(_ texto: String)
    /// Corta SOLO lo que dijo este locutor, si todavía suena. Una locución ajena (un aviso del accesorio) no se toca.
    func cortarLoPropio()
}
