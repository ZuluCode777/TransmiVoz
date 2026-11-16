import MapKit
import SwiftUI

/// Mapa de «Mapa y GPS» (MapKit): «Tú estás aquí» y las estaciones cercanas que entregó el servidor, con la elegida marcada
/// aparte. Es una ayuda visual: todo lo que dibuja está también en el listado de la misma pantalla (nombre, distancia y
/// referencia). La posición de la persona se dibuja desde la lectura de la app, no con la capa de ubicación de MapKit (que
/// escucharía por su cuenta y no respetaría «Detener la ubicación»). No se mueve ni se acerca (`interactionModes: []`).
struct MapaGpsVista: View {
    struct Marca: Equatable, Identifiable {
        let id: Int
        let titulo: String
        let coordenada: Coordenada
        let elegida: Bool
    }

    let usuario: Coordenada?
    let estaciones: [Marca]
    /// En las pruebas de interfaz el mapa no se dibuja: la lectura es sintética y la auditoría no distingue el contenido de MapKit.
    let modoPruebas: Bool

    @State private var camara: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if modoPruebas {
                Text(TextoGps.mapaModoPruebas)
                    .foregroundStyle(.textoSecundario)
                    .accessibilityIdentifier("gps-mapa")
            } else if let encuadre {
                Map(position: $camara, interactionModes: []) {
                    if let usuario {
                        Marker(TextoGps.tuUbicacion, systemImage: "person.fill", coordinate: punto(usuario))
                            .tint(.blue)
                    }
                    ForEach(estaciones) { marca in
                        Marker(marca.titulo, coordinate: punto(marca.coordenada))
                            .tint(marca.elegida ? .pink : .indigo)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear { camara = .region(region(encuadre)) }
                .onChange(of: encuadre) { _, nuevo in camara = .region(region(nuevo)) }
                // Una sola pieza para VoiceOver: la lista que sigue dice cada estación con su distancia.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TextoGps.etiquetaMapa)
                .accessibilityIdentifier("gps-mapa")
                Text(TextoGps.mapaNecesitaConexion)
                    .font(.footnote)
                    .foregroundStyle(.textoSecundario)
            }
        }
    }

    private var encuadre: EncuadreMapa? {
        EncuadreMapa.ajustar((usuario.map { [$0] } ?? []) + estaciones.map(\.coordenada))
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
