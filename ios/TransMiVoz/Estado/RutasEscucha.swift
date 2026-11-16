import Foundation
import Observation

/// «Escuchar» del detalle de una ruta (`components/route-detail.tsx`): lee la ruta en voz alta por la voz de la app
/// (`ControlVoz`), la misma de la consulta y de los avisos del accesorio, con sus mismas reglas: solo por una salida
/// privada, con la voz de la app permitida y sin interrupción en curso. Si no suena, `mensaje` dice por qué y la ruta
/// sigue escrita en la pantalla.
///
/// - Con el micrófono del dictado abierto no se habla (la voz sonaría sobre la captura).
/// - Lo que suena de otro dueño (un aviso del accesorio) no se corta ni se tapa; solo se corta la lectura propia, al
///   salir de la pantalla (`detener`) o al repetir.
@MainActor
@Observable
final class EscuchaRutaModelo {
    /// Por qué no se dijo en voz alta; `nil` si se dijo o todavía no se pidió.
    private(set) var mensaje: String?

    @ObservationIgnored private let voz: ControlVoz?
    @ObservationIgnored private let dictado: DictadoModelo?
    /// `ControlVoz.locuciones` al empezar la lectura propia; `nil` si no hay ninguna que cortar.
    @ObservationIgnored private var locucionPropia: Int?

    init(voz: ControlVoz?, dictado: DictadoModelo?) {
        self.voz = voz
        self.dictado = dictado
    }

    func escuchar(_ texto: String) {
        guard let voz else { mensaje = TextoRutas.escuchaNoDisponible; return }
        guard dictado?.capturando != true else { mensaje = TextoRutas.escuchaConMicrofono; return }
        if voz.hablando && locucionPropia != voz.locuciones { mensaje = TextoAvisos.noSeDijo(.cedeAUnAviso); return }
        switch voz.anunciar(texto) {
        case .hablado:
            locucionPropia = voz.locuciones
            mensaje = nil
        case .silenciado(let motivo):
            locucionPropia = nil
            mensaje = TextoAvisos.noSeDijo(motivo)
        }
    }

    /// La pantalla dejó de verse: corta la lectura propia y solo esa.
    func detener() {
        guard let voz, let propia = locucionPropia else { return }
        locucionPropia = nil
        if voz.locuciones == propia { voz.descartarTodo() }
    }
}
