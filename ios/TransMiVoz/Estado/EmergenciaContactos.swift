import Foundation

/// Textos y números de la pantalla Emergencia (web: `components/assistance.tsx`). Los números son los de la web y los mismos
/// de la Ayuda; cada uno es un enlace `tel:` (`LlamadaAyuda`): iOS abre su propia confirmación y es la persona quien llama.
enum TextoEmergencia {
    static let titulo = "Emergencia"
    static let subtitulo = "Llamadas de ayuda"

    /// El botón rojo grande: «Llamar al 123» y, debajo, «Emergencias».
    static let principal = LlamadaAyuda(nombre: "Línea de emergencias", numero: "123")
    static let tituloPrincipal = "Llamar al 123"
    static let notaPrincipal = "Emergencias"
    static let pistaPrincipal = "Abre el marcador del iPhone con el 123. Tú confirmas la llamada."

    /// «Otras líneas», en el orden de la web.
    static let encabezadoOtras = "Otras líneas"
    static let otras = [
        LlamadaAyuda(nombre: "Policía de TransMilenio", numero: "156"),
        LlamadaAyuda(nombre: "Atención al usuario TransMilenio", numero: "195"),
    ]

    /// Lo que la web dice al abrir la pantalla (`speak(…, { queue: true })`).
    static let introHablada = "Emergencia. Toca el botón rojo para llamar a la línea 123."

    /// Una frase por párrafo: con el texto más grande cada una cabe entera en el área visible.
    static let aclaracion = [
        "Cada botón abre el marcador del iPhone con el número escrito.",
        "La llamada no se hace sola: tú la confirmas.",
    ]

    /// Lo que lee VoiceOver de una fila de «Otras líneas» (igual que `speak` de la web al enfocarla).
    static func etiqueta(_ llamada: LlamadaAyuda) -> String { "\(llamada.nombre). Número \(llamada.numero)." }
}
