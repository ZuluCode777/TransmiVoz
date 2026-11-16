import Foundation

/// La voz de la pantalla Emergencia sobre la `ControlVoz` compartida de la app (dueño único del audio y de la cola de uno):
/// no abre otra sesión de audio ni otra cola. Sigue sus reglas, como la respuesta hablada de la consulta: solo habla si la voz
/// propia está permitida y la salida es privada (auriculares), y nunca corta ni tapa una locución ajena, como un aviso del
/// accesorio. Al salir corta solo su propia locución.
@MainActor
final class EmergenciaVozModelo {
    private let voz: ControlVoz
    /// `ControlVoz.locuciones` cuando empezó la introducción; `nil` si no habló (voz apagada, salida no privada o algo sonando).
    private var locucionPropia: Int?

    init(voz: ControlVoz) { self.voz = voz }

    /// Dice la introducción de la web («Emergencia. Toca el botón rojo…»). Con algo ya sonando no habla: un aviso del
    /// accesorio va primero y la pantalla ya muestra el botón.
    func decirIntroduccion() {
        guard !voz.hablando else { return }
        if voz.anunciar(TextoEmergencia.introHablada) == .hablado { locucionPropia = voz.locuciones }
    }

    /// La pantalla dejó de verse: corta la introducción si sigue siendo la que suena. Si después habló otro, la cola de uno ya
    /// la cortó y lo que suena no es nuestro.
    func salir() {
        guard let propia = locucionPropia else { return }
        locucionPropia = nil
        if voz.locuciones == propia { voz.descartarTodo() }
    }
}
