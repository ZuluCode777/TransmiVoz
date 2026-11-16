import Foundation

extension AccionAgente {
    /// Límite de esta app ante la acción. Las pantallas que la web abre con `frequent`, `gps` y `search` existen en el iPhone
    /// (rutas frecuentes, «Mapa y GPS» y las rutas de la estación), pero Consulta no navega sola: ofrece el botón y el límite
    /// lo dice, para que lo que se lee («Voy a abrir…») no prometa lo que no ocurre. El asistente de voz de Ceguera total sí las
    /// abre y no lee este texto. `nil` si la acción no abre nada o si el iPhone ya ofrece su pantalla sin promesa
    /// previa (la ruta ofrece su detalle con el mapa, EA-25).
    var limite: String? {
        switch self {
        case .ninguna:
            return nil
        case .frecuentes:
            return "Esta app no abre sola la lista de rutas frecuentes: toca «Ver mis rutas frecuentes» para verla."
        case .gps:
            return "Esta app no abre sola «Mapa y GPS»: toca «Abrir Mapa y GPS». Solo usa tu ubicación si la activas allí. Para un viaje, escribe desde qué estación sales y a cuál vas."
        case .busqueda:
            return "Esta app no abre sola las rutas de la estación: toca «Ver las rutas que pasan por la estación»."
        case .ruta:
            return nil
        case .viaje:
            return "Esta app no da órdenes de abordaje. El servidor devolvió un recorrido; se muestra solo como información, sin verificar paradas ni sentido."
        }
    }
}

extension RespuestaAgente {
    /// Fecha y procedencia del catálogo cuando el texto que se muestra no las trae: el de un viaje no
    /// se muestra y el aviso seguro de la guardia sustituye al del servidor.
    var procedenciaAparte: String? {
        guard let catalogo else { return nil }
        if case .viaje = accion { return catalogo.procedencia }
        return texto.contains(catalogo.procedencia) ? nil : catalogo.procedencia
    }
}

extension RespuestaAgente {
    /// Lo que se lee en voz alta: lo mismo que la pantalla presenta como respuesta, sin los pasos. Un viaje no lee el texto
    /// del servidor (la pantalla tampoco lo muestra: puede traer órdenes de abordaje sin verificar) sino el aviso de la app.
    /// El límite de la acción se lee siempre que lo hay: «Voy a abrir el GPS auditivo» sin él prometería una navegación que Consulta no hace.
    var textoHablado: String {
        var partes: [String] = []
        if case .viaje = accion {} else { partes.append(texto) }
        if let limite = accion.limite { partes.append(limite) }
        if let procedencia = procedenciaAparte { partes.append(procedencia) }
        if catalogo?.antiguo == true { partes.append("Los datos de TransMilenio son antiguos.") }
        return partes.joined(separator: " ")
    }
}
