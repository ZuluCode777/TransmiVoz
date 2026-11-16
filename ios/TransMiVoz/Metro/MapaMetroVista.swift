import MapKit
import SwiftUI

/// Mapa ilustrativo del Metro de la Línea 1 (MapKit): el trazado simplificado, punteado y fino (nunca con el aspecto de una
/// ruta en servicio), y las 16 huellas como polígonos ilustrativos. NO hay marcadores: una huella no es una entrada ni una
/// parada, y un punto en su centro la presentaría como tal. El rótulo y la atribución van como texto junto al mapa
/// (`MetroVista`); todo lo que se dibuja está también, completo, en el listado de estaciones.
/// No se mueve ni se acerca (`interactionModes: []`): no atrapa el desplazamiento de la pantalla con una mano.
struct MapaMetroVista: View {
    let capa: CapaMetro
    /// Huella que la persona eligió «ver en el mapa»; se dibuja más gruesa y más opaca, y su etiqueta se dice aparte.
    let resaltada: String?
    /// En las pruebas de interfaz el mapa no se dibuja (la auditoría no distingue su contenido y el Simulator no baja calles).
    let modoPruebas: Bool
    /// La persona tocó una huella (como en la web, dice qué estación es). Lo hace el padre: resalta y la anuncia.
    var alTocarHuella: (HuellaMetro) -> Void = { _ in }
    /// La persona tocó el trazado (como en la web, repite el rótulo).
    var alTocarTrazado: () -> Void = {}

    /// Distancia en puntos de pantalla a la que un toque cuenta como «sobre el trazado» (línea fina: se necesita margen).
    private static let margenDeToque = 22.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modoPruebas {
                Text(TextoMetro.mapaModoPruebas)
                    .foregroundStyle(.textoSecundario)
                    .accessibilityIdentifier("metro-mapa")
            } else if let encuadre = EncuadreMapa.ajustar(capa.coordenadas) {
                MapReader { proxy in
                    Map(initialPosition: .region(region(encuadre)), interactionModes: []) {
                        MapPolyline(coordinates: capa.trazado.map(punto))
                            .stroke(Color.indigo, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        ForEach(capa.huellas) { huella in
                            MapPolygon(coordinates: huella.anillo.map(punto))
                                .stroke(huella.id == resaltada ? Color.pink : Color.indigo, lineWidth: huella.id == resaltada ? 4 : 1.5)
                                .foregroundStyle((huella.id == resaltada ? Color.pink : Color.indigo).opacity(huella.id == resaltada ? 0.5 : 0.25))
                        }
                    }
                    // Como la web: tocar una huella dice cuál es y tocar el trazado repite el rótulo. Los toques de quien usa
                    // VoiceOver van por la lista de estaciones (el mapa es una sola pieza).
                    .onTapGesture(coordinateSpace: .local) { toque in tocar(toque, con: proxy) }
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // Una sola pieza para VoiceOver: el listado de estaciones ya dice todo lo que dibuja.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TextoMetro.etiquetaMapa(rotulo: capa.rotulo))
                .accessibilityIdentifier("metro-mapa")
                Text(TextoMetro.mapaNecesitaConexion)
                    .font(.footnote)
                    .foregroundStyle(.textoSecundario)
            }
        }
    }

    /// Una huella tiene prioridad sobre el trazado: se busca primero dentro de un polígono y, si no, cerca de la línea.
    private func tocar(_ toque: CGPoint, con proxy: MapProxy) {
        if let sitio = proxy.convert(toque, from: .local),
           let huella = capa.huella(en: Coordenada(latitud: sitio.latitude, longitud: sitio.longitude)) {
            alTocarHuella(huella)
            return
        }
        let enPantalla = capa.trazado.compactMap { coordenada -> (x: Double, y: Double)? in
            proxy.convert(CLLocationCoordinate2D(latitude: coordenada.latitud, longitude: coordenada.longitud), to: .local)
                .map { (x: Double($0.x), y: Double($0.y)) }
        }
        if let distancia = GeometriaDeToque.distancia(del: (x: Double(toque.x), y: Double(toque.y)), alTrazado: enPantalla),
           distancia <= Self.margenDeToque {
            alTocarTrazado()
        }
    }

    private func punto(_ coordenada: Coordenada) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordenada.latitud, longitude: coordenada.longitud)
    }

    private func region(_ encuadre: EncuadreMapa) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: encuadre.latitudCentro, longitude: encuadre.longitudCentro),
            span: MKCoordinateSpan(latitudeDelta: encuadre.deltaLatitud, longitudeDelta: encuadre.deltaLongitud))
    }
}
