import Foundation

/// Textos propios de la pantalla «Metro de Bogotá». Los del catálogo (estado, límites, atribución, fichas) los escribe el
/// servidor y la app los muestra tal cual; aquí solo están los de la propia pantalla.
enum TextoMetro {
    static let titulo = "Metro de Bogotá"
    /// Mientras el servidor no responde, la app no sabe nada del Metro: solo repite lo único que es cierto siempre.
    static let cargando = "Cargando el Metro de Bogotá. Es un proyecto en construcción y sin servicio."
    static let encabezadoMapa = "Mapa del proyecto"
    static let encabezadoEstaciones = "Estaciones de la Línea 1"
    static let etiquetaListaEstaciones = "Estaciones de la Línea 1 del Metro, de E01 a E16"
    static let encabezadoLinea2 = "Línea 2"
    static let encabezadoFuentes = "Fuentes y fechas"
    static let reintentar = "Reintentar"
    static let verEnElMapa = "Ver su huella en el mapa"
    static let quitarResalte = "Quitar el resalte del mapa"
    static let servidorNoConfigurado = "Falta la dirección del servidor. Abre la pestaña Ajustes y escribe la dirección HTTPS."
    static let mapaModoPruebas = "Modo de pruebas: el mapa no se dibuja. El listado de estaciones está completo."
    static let mapaNecesitaConexion = "Sin conexión el mapa no baja las calles: queda el trazado y las huellas sobre un fondo vacío."

    /// Servidor sin la operación: responde 400 a lo que no conoce. No es un fallo de la red ni de la clave.
    static let servidorAnterior =
        "Este servidor todavía no tiene el Metro de la Línea 1 (respondió 400). Es una versión anterior del servidor: pide que lo actualicen. Sin él no puedo mostrar el listado."

    static let repetirEstado = "Repetir el estado en voz alta"
    static let vozOcupada = "Suena otro aviso: el estado queda en pantalla. Vuelve a pulsar «Repetir» cuando termine."
    static let vozApagada =
        "La voz de la app no está activa (VoiceOver activo, sin auriculares o apagada en Preferencias): el estado queda en pantalla y VoiceOver lo lee."
    static let toqueEnElMapa = "Toca una huella del mapa para saber qué estación es; la lista de abajo tiene todas."

    static func etiquetaMapa(rotulo: String) -> String { "Mapa ilustrativo. \(rotulo)" }

    static func huellaResaltada(_ etiqueta: String) -> String { "Resaltada en el mapa: \(etiqueta)." }

    /// Qué decir de un fallo al pedir el Metro. El 400 de un servidor anterior tiene su propio texto; el resto es de `ErrorConsulta`.
    static func mensaje(de error: ErrorConsulta) -> String {
        error == .peticionRechazada ? servidorAnterior : "\(error.mensaje) \(error.recuperacion)"
    }
}
