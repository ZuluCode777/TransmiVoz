import Foundation

/// Huella de una estación del Metro: un POLÍGONO ilustrativo del diseño de 2022. No es una entrada, una parada ni un
/// transbordo, y por eso no hay un punto por estación (un centroide lo presentaría como acceso).
struct HuellaMetro: Equatable, Identifiable, Sendable {
    /// E01–E16.
    let id: String
    /// Lo que dice la huella: número, nombre y «no es una entrada».
    let etiqueta: String
    let anillo: [Coordenada]
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

    /// Todo lo que se dibuja, para encuadrar el mapa.
    var coordenadas: [Coordenada] { trazado + huellas.flatMap(\.anillo) }
}
