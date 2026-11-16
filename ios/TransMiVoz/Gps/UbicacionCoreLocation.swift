import ContratoBLE
import CoreLocation
import Foundation

/// Ubicación y brújula reales con CoreLocation, SOLO «al usar la app»:
/// - pide `requestWhenInUseAuthorization` (nunca «siempre»), sin `allowsBackgroundLocationUpdates` ni modo de fondo;
/// - empieza a escuchar en `iniciar()` y suelta todo en `detener()`; después de `detener()` no entrega nada más;
/// - el rumbo es el VERDADERO (`trueHeading`), válido solo si no es negativo; el magnético no se usa;
/// - ningún evento se guarda, se registra ni se imprime: solo se traducen y se entregan.
///
/// Sin la descripción de uso (`NSLocationWhenInUseUsageDescription`) el sistema no mostraría el aviso y la app esperaría
/// para siempre: se detecta y se dice como `noDisponible`. Sin verificar en un iPhone real.
@MainActor
final class UbicacionCoreLocation: NSObject, ProveedorUbicacion, CLLocationManagerDelegate {
    var alEvento: ((EventoUbicacion) -> Void)?
    var rumboDisponible: Bool { CLLocationManager.headingAvailable() }

    private let gestor: CLLocationManager
    private let reloj: RelojMonotonico
    /// Solo entre `iniciar()` y `detener()`: lo que llegue fuera de ese intervalo se descarta.
    private var activo = false
    private var escuchando = false

    init(gestor: CLLocationManager = CLLocationManager(), reloj: @escaping RelojMonotonico = RelojDelSistema.ahora) {
        self.gestor = gestor
        self.reloj = reloj
        super.init()
        gestor.delegate = self
        gestor.desiredAccuracy = kCLLocationAccuracyBest
        // Una lectura nueva por cada ~5 grados: el rumbo se guarda, no se envía.
        gestor.headingFilter = 5
        gestor.headingOrientation = .portrait
        gestor.activityType = .fitness
        gestor.pausesLocationUpdatesAutomatically = true
    }

    func iniciar() {
        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
            alEvento?(.permiso(.noDisponible))
            return
        }
        activo = true
        aplicarEstado(gestor.authorizationStatus, pedirSiHaceFalta: true)
    }

    func detener() {
        activo = false
        escuchando = false
        gestor.stopUpdatingLocation()
        gestor.stopUpdatingHeading()
    }

    private func aplicarEstado(_ estado: CLAuthorizationStatus, pedirSiHaceFalta: Bool) {
        guard activo else { return }
        switch estado {
        case .notDetermined:
            alEvento?(.permiso(.porPreguntar))
            if pedirSiHaceFalta { gestor.requestWhenInUseAuthorization() }
        case .authorizedWhenInUse, .authorizedAlways:
            alEvento?(.permiso(.concedido))
            empezarAEscuchar()
        case .denied:
            alEvento?(.permiso(.denegado))
        case .restricted:
            alEvento?(.permiso(.restringido))
        @unknown default:
            alEvento?(.permiso(.denegado))
        }
    }

    private func empezarAEscuchar() {
        guard !escuchando else { return }
        escuchando = true
        gestor.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { gestor.startUpdatingHeading() }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ gestor: CLLocationManager) {
        let estado = gestor.authorizationStatus
        Task { @MainActor in self.aplicarEstado(estado, pedirSiHaceFalta: false) }
    }

    nonisolated func locationManager(_ gestor: CLLocationManager, didUpdateLocations locaciones: [CLLocation]) {
        // Solo la última: las anteriores del mismo lote ya no son «ahora».
        guard let ultima = locaciones.last else { return }
        // Una coordenada con precisión negativa no es válida (CoreLocation lo documenta): no se entrega.
        guard ultima.horizontalAccuracy >= 0 else { return }
        let edad = max(0, Date().timeIntervalSince(ultima.timestamp))
        let latitud = ultima.coordinate.latitude
        let longitud = ultima.coordinate.longitude
        let precision = ultima.horizontalAccuracy
        Task { @MainActor in
            guard self.activo else { return }
            let capturada = self.reloj() - Milisegundos(edad * 1000)
            self.alEvento?(.posicion(PosicionMedida(
                latitud: latitud, longitud: longitud, precision: precision, capturadaMs: capturada)))
        }
    }

    nonisolated func locationManager(_ gestor: CLLocationManager, didUpdateHeading rumbo: CLHeading) {
        // `trueHeading` es negativo si no es válido (sin lectura de ubicación): sin él no hay rumbo, aunque haya magnético.
        let grados = rumbo.trueHeading
        let calidad = rumbo.headingAccuracy
        let edad = max(0, Date().timeIntervalSince(rumbo.timestamp))
        Task { @MainActor in
            guard self.activo else { return }
            guard grados >= 0 else {
                self.alEvento?(.rumbo(nil))
                return
            }
            let capturado = self.reloj() - Milisegundos(edad * 1000)
            self.alEvento?(.rumbo(RumboMedido(
                gradosVerdaderos: grados, calidad: calidad >= 0 ? calidad : nil, capturadoMs: capturado)))
        }
    }

    nonisolated func locationManager(_ gestor: CLLocationManager, didFailWithError error: Error) {
        // `locationUnknown` es transitorio y el sistema sigue intentando. Un permiso negado llega por
        // `locationManagerDidChangeAuthorization`: aquí solo se avisa de que no hay señal.
        Task { @MainActor in
            guard self.activo else { return }
            self.alEvento?(.sinSenal)
        }
    }

    /// El sistema no debe mostrar el aviso de calibración de la brújula encima de la pantalla.
    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ gestor: CLLocationManager) -> Bool { false }
}
