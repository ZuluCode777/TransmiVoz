import Foundation

/// Huella de una estación del Metro: un POLÍGONO ilustrativo del diseño de 2022. No es una entrada, una parada ni un
/// transbordo, y por eso no hay un punto por estación (un centroide lo presentaría como acceso).
struct HuellaMetro: Equatable, Identifiable, Sendable {
    /// E01–E16.
    let id: String
    /// Lo que dice la huella: número, nombre y «no es una entrada».
    let etiqueta: String
    let anillo: [Coordenada]

    /// ¿El punto cae dentro del polígono? Solo para decir a qué huella tocó la persona (no es una regla de transporte ni una
    /// entrada: la huella es ilustrativa).
    func contiene(_ punto: Coordenada) -> Bool {
        var dentro = false
        var anterior = anillo.count - 1
        for actual in anillo.indices {
            let a = anillo[actual], b = anillo[anterior]
            if (a.latitud > punto.latitud) != (b.latitud > punto.latitud),
               punto.longitud < (b.longitud - a.longitud) * (punto.latitud - a.latitud) / (b.latitud - a.latitud) + a.longitud {
                dentro.toggle()
            }
            anterior = actual
        }
        return dentro
    }
}

/// Distancias en pantalla para saber si un toque cayó sobre el trazado (en puntos de pantalla, no en metros).
enum GeometriaDeToque {
    /// Distancia del punto al segmento `a`-`b`.
    static func distancia(del punto: (x: Double, y: Double), alSegmento a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let largo2 = dx * dx + dy * dy
        guard largo2 > 0 else { return ((punto.x - a.x) * (punto.x - a.x) + (punto.y - a.y) * (punto.y - a.y)).squareRoot() }
        let t = max(0, min(1, ((punto.x - a.x) * dx + (punto.y - a.y) * dy) / largo2))
        let px = a.x + t * dx, py = a.y + t * dy
        return ((punto.x - px) * (punto.x - px) + (punto.y - py) * (punto.y - py)).squareRoot()
    }

    /// Menor distancia del punto a una poligonal.
    static func distancia(del punto: (x: Double, y: Double), alTrazado trazado: [(x: Double, y: Double)]) -> Double? {
        guard trazado.count >= 2 else { return nil }
        return zip(trazado, trazado.dropFirst()).map { distancia(del: punto, alSegmento: $0, $1) }.min()
    }
}

/// Lo que el mapa dibuja del Metro (EA-24): el trazado simplificado y las 16 huellas, con el rótulo y la atribución que
/// van a la vista junto al mapa. Se arma con los MISMOS datos que el listado de estaciones; el listado es la
/// representación completa y no depende del mapa. Es geometría pura (sin MapKit) para que otro mapa pueda reutilizarla.
///
/// Regla de EA-24: la capa del Metro NO se dibuja en los mapas de ruta, de viaje ni del GPS de TransMilenio (sería
/// presentar un proyecto sin servicio como transporte de hoy). Quien la integre en otro mapa debe decidirlo de forma
/// explícita y conservar el rótulo, el trazado punteado y la atribución.
struct CapaMetro: Equatable, Sendable {
    /// Rótulo fijo del marco del mapa: no se tapa con otros controles.
    let rotulo: String
    /// Forma corta para el control de atribución del propio mapa.
    let atribucionCorta: String
    /// Trazado SIMPLIFICADO: una ilustración, no una ruta en servicio. Se dibuja punteado y fino.
    let trazado: [Coordenada]
    let huellas: [HuellaMetro]

    init(_ respuesta: RespuestaMetro) {
        rotulo = respuesta.mapa.rotulo
        atribucionCorta = respuesta.mapa.atribucionCorta
        trazado = respuesta.mapa.trazado
        huellas = respuesta.estaciones.map { HuellaMetro(id: $0.id, etiqueta: $0.etiquetaHuella, anillo: $0.huella) }
    }

    /// La huella que contiene el punto, si la hay (para «al tocar una huella, dice cuál es»).
    func huella(en punto: Coordenada) -> HuellaMetro? { huellas.first { $0.contiene(punto) } }

    /// Todo lo que se dibuja, para encuadrar el mapa.
    var coordenadas: [Coordenada] { trazado + huellas.flatMap(\.anillo) }
}
