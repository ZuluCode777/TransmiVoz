import Foundation
#if canImport(MapKit)
import MapKit
#endif

/// Abre la ruta a pie hacia una estación en la app Mapas del sistema (equivalente a «Abrir en Google Maps» de la web).
/// SOLO recibe el destino: el nombre y la coordenada de la ESTACIÓN, que son del catálogo. La posición de la persona no pasa
/// por aquí, no va en ninguna URL ni se registra: la app Mapas parte de donde está la persona por su cuenta.
@MainActor
protocol AbridorMapas: AnyObject {
    func abrirRutaAPie(haciaEstacion nombre: String, en coordenada: Coordenada)
}

/// Mapas del sistema con MapKit (`MKMapItem.openInMaps`, modo a pie). Sin dependencias nuevas. En las pruebas de interfaz
/// (`-PRUEBAS_UI_SIMULADAS`) no abre nada: no se sale de la app bajo la prueba. Sin verificar en un iPhone.
@MainActor
final class AbridorMapasSistema: AbridorMapas {
    nonisolated init() {}

    func abrirRutaAPie(haciaEstacion nombre: String, en coordenada: Coordenada) {
        #if canImport(MapKit)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PRUEBAS_UI_SIMULADAS") { return }
        #endif
        let destino = MKMapItem(
            placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordenada.latitud, longitude: coordenada.longitud)))
        destino.name = nombre
        destino.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        #endif
    }
}
