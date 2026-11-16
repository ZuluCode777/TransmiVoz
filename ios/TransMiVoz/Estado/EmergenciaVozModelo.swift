import Foundation
import Observation

/// La voz de la pantalla Emergencia sobre la `ControlVoz` compartida de la app (dueño único del audio y de la cola de uno):
/// no abre otra sesión de audio ni otra cola. Sigue sus reglas, como la respuesta hablada de la consulta: solo habla si la voz
/// propia está permitida y la salida es privada (auriculares), y nunca corta ni tapa una locución ajena, como un aviso del
/// accesorio. Al salir corta solo su propia locución.
///
/// También es el texto equivalente al audio (`especificacion-accesibilidad.md` §5): la pantalla muestra lo que dice en «La
/// app dijo», con «Repetir», y `resultado` cuenta con palabras si se dijo en voz alta o por qué no.
@MainActor
@Observable
final class EmergenciaVozModelo {
    /// Cómo terminó el último intento de decir la introducción. `nil` hasta el primero.
    private(set) var resultado: String?
    /// Cuántas veces se pidió «Repetir»: la pantalla lleva el foco de VoiceOver al resultado aunque el texto sea igual al anterior.
    private(set) var repeticiones = 0

    @ObservationIgnored private let voz: ControlVoz
    /// `ControlVoz.locuciones` cuando empezó la introducción; `nil` si no habló (voz apagada, salida no privada o algo sonando).
    @ObservationIgnored private var locucionPropia: Int?

    init(voz: ControlVoz) { self.voz = voz }

    /// Dice la introducción de la web («Emergencia. Toca el botón rojo…») al abrir la pantalla. Con algo ya sonando no habla:
    /// un aviso del accesorio va primero y la pantalla ya muestra el botón y el texto. Mientras suena la propia no la repite.
    func decirIntroduccion() {
        guard !suenaLaPropia else { return }
        intentar()
    }

    /// «Repetir»: la persona lo pidió, así que vuelve a decirla aunque suene la propia. Sigue sin cortar ni tapar una ajena y
    /// sin saltarse la ruta privada ni la voz apagada: si no se dice, el resultado explica por qué.
    func repetir() {
        repeticiones += 1
        intentar()
    }

    /// La pantalla dejó de verse: corta la introducción si sigue siendo la que suena. Si después habló otro, la cola de uno ya
    /// la cortó y lo que suena no es nuestro.
    func salir() {
        guard let propia = locucionPropia else { return }
        locucionPropia = nil
        if voz.locuciones == propia { voz.descartarTodo() }
    }

    private var suenaLaPropia: Bool { voz.hablando && locucionPropia == voz.locuciones }

    private func intentar() {
        guard !voz.hablando || suenaLaPropia else {
            resultado = TextoEmergencia.sonandoOtroAviso
            return
        }
        switch voz.anunciar(TextoEmergencia.introHablada) {
        case .hablado:
            locucionPropia = voz.locuciones
            resultado = TextoEmergencia.dichaEnVozAlta
        case .silenciado(let motivo):
            locucionPropia = nil
            resultado = TextoAvisos.noSeDijo(motivo)
        }
    }
}
