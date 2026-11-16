import Foundation

/// Qué pasó con una frase que una pantalla quiso decir.
enum ResultadoLocucion: Equatable, Sendable {
    /// Salió por la voz de la app (`ControlVoz`).
    case hablada
    /// La voz de la app calló y se anunció con VoiceOver (que solo suena si está activo).
    case anunciada
    /// Suena otra locución (un aviso del accesorio, también uno de rutina, o la respuesta de la consulta) y NO se corta ni se tapa.
    case ocupada
    /// La voz de la app está apagada (VoiceOver activo o decisión de la persona), la salida de audio no es privada o el sistema
    /// no dejó hablar, y no se anunció con VoiceOver.
    case silenciada

    /// La frase llegó a la persona por voz.
    var seDijo: Bool { self == .hablada || self == .anunciada }
}

/// Cómo dicen las pantallas «Mapa y GPS» y «Metro de Bogotá» sus frases habladas. La implementa `LocutorControlVoz` sobre
/// `ControlVoz`, el ÚNICO dueño de la voz y de la sesión de audio: estas pantallas no crean sintetizador ni tocan `AVAudioSession`.
@MainActor
protocol Locutor: AnyObject {
    /// Dice `texto`. Nunca corta una locución ajena. Si la voz de la app calla, con `anunciarConVoiceOver` se anuncia con
    /// VoiceOver; sin él (frases que VoiceOver ya lee en pantalla) no se dice nada más. El texto siempre queda en pantalla.
    func decir(_ texto: String, anunciarConVoiceOver: Bool) -> ResultadoLocucion
    /// Corta SOLO lo que dijo este locutor, si todavía suena.
    func cortarLoPropio()
}

extension Locutor {
    /// Lo que la persona pidió con un botón: si la voz calla, se anuncia con VoiceOver.
    @discardableResult
    func decir(_ texto: String) -> ResultadoLocucion { decir(texto, anunciarConVoiceOver: true) }
}
