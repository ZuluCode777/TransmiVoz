import Foundation

/// Textos de la pantalla Preferencias. Dicen lo que la app hace HOY.
enum TextoPreferencias {
    static let tituloVoz = "Voz de la app"
    static let etiquetaVoz = "Avisos hablados por la app"
    static let notaVoz = "Es el mismo interruptor de la pestaña Sesión. Controla si la app dice en voz alta las medidas y los avisos del accesorio, y solo por una salida de audio privada (auriculares con cable o Bluetooth). El enlace con el accesorio no está autenticado, así que la voz añade «\(TextoAccesorio.reservaEnlace)» después de cada medida y antes de «Calibrando» y «Sin detección», hasta que se oye entera y como mucho 3 veces por conexión; sin detección no significa camino libre. Con VoiceOver activo empieza apagada para no hablar dos veces. Vuelve a su valor inicial al cerrar la app."
    static let sinAccesorio = "La voz de la app no está disponible en este modo."
    static let tituloSistema = "Texto, contraste y VoiceOver"
    static let etiquetaAltoContraste = "Alto contraste (colores fluorescentes)"
    static let notaAltoContraste = "Fondo negro con letra y contornos de neón, como «Alto contraste» de la web. Mientras no lo toques, la app sigue el modo claro u oscuro de iOS; desde que lo tocas, manda lo que elijas aquí y se guarda en este iPhone."
    static let notaSistema = "El tamaño del texto sigue el ajuste de iOS. VoiceOver se activa en los ajustes de accesibilidad de iOS."
}
