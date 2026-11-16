import Foundation

/// PROVISIONAL: el modelo del GPS lo crea UNA vez `EntornoApp` y vive en `ServiciosRutas.gps` (`let gps: GpsAuditivoModelo`),
/// con la `ControlVoz` de la app y la ubicación real. Esta rama no toca `EntornoApp` ni `ServiciosRutas`, así que le da a las
/// pantallas el mismo `servicios.gps` con un único modelo por proceso y, sin `ControlVoz` a mano, la voz de VoiceOver.
/// **Al integrar, se borra este archivo entero**: la propiedad guardada de `ServiciosRutas` lo sustituye sin cambiar ninguna vista.
extension ServiciosRutas {
    @MainActor var gps: GpsAuditivoModelo { GpsProvisional.modelo(para: self) }
}

@MainActor
private enum GpsProvisional {
    private static var unico: GpsAuditivoModelo?

    static func modelo(para servicios: ServiciosRutas) -> GpsAuditivoModelo {
        if let unico { return unico }
        let proveedor: ProveedorUbicacion
        #if DEBUG
        proveedor = servicios.modoPruebas
            ? UbicacionSintetica(argumentos: ProcessInfo.processInfo.arguments) : UbicacionCoreLocation()
        #else
        proveedor = UbicacionCoreLocation()
        #endif
        let nuevo = GpsAuditivoModelo(
            cliente: servicios.cliente, proveedor: proveedor, locutor: LocutorControlVoz(voz: nil))
        unico = nuevo
        return nuevo
    }
}
