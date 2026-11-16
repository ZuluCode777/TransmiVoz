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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modoPruebas {
                Text(TextoMetro.mapaModoPruebas)
                    .foregroundStyle(.textoSecundario)
                    .accessibilityIdentifier("metro-mapa")
            } else if let encuadre = EncuadreMapa.ajustar(capa.coordenadas) {
                Map(initialPosition: .region(region(encuadre)), interactionModes: []) {
                    MapPolyline(coordinates: capa.trazado.map(punto))
                        .stroke(Color.indigo, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    ForEach(capa.huellas) { huella in
                        MapPolygon(coordinates: huella.anillo.map(punto))
                            .stroke(huella.id == resaltada ? Color.pink : Color.indigo, lineWidth: huella.id == resaltada ? 4 : 1.5)
                            .foregroundStyle((huella.id == resaltada ? Color.pink : Color.indigo).opacity(huella.id == resaltada ? 0.5 : 0.25))
                    }
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

    private func punto(_ coordenada: Coordenada) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordenada.latitud, longitude: coordenada.longitud)
    }

    private func region(_ encuadre: EncuadreMapa) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: encuadre.latitudCentro, longitude: encuadre.longitudCentro),
            span: MKCoordinateSpan(latitudeDelta: encuadre.deltaLatitud, longitudeDelta: encuadre.deltaLongitud))
    }
}
