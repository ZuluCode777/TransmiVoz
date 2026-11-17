#if DEBUG
import Foundation

/// Metro y estaciones cercanas SIMULADOS para las pruebas de interfaz (con `-PRUEBAS_UI_SIMULADAS`): sin red ni
/// credenciales, con datos inventados y rotulados «[SIMULADO]». No reproducen ninguna regla del servidor: cada respuesta es
/// un guion fijo que elige un argumento de arranque, y las pruebas comprueban lo que la pantalla hace con ese guion.
///
/// Metro: por defecto el catálogo completo (16 estaciones); `-PRUEBAS_UI_METRO_ANTIGUO` responde 400 (un servidor anterior),
/// `-PRUEBAS_UI_METRO_SIN_RED` falla por la red y `-PRUEBAS_UI_METRO_LENTO` tarda en responder.
///
/// Estaciones cercanas: por defecto, cuatro estaciones con giro (`relativa`); `-PRUEBAS_UI_GPS_CARDINAL` las da solo con
/// referencia cardinal, `-PRUEBAS_UI_GPS_MUY_CERCA` marca la primera `muyCerca`, `-PRUEBAS_UI_GPS_FALLA` falla por la red y
/// `-PRUEBAS_UI_GPS_VACIA` no trae estaciones.
extension ClientePlanificadorSimulado {
    private static var argumentos: [String] { ProcessInfo.processInfo.arguments }

    func metroLinea1() async throws -> RespuestaMetro {
        if Self.argumentos.contains("-PRUEBAS_UI_METRO_ANTIGUO") { throw ErrorConsulta.peticionRechazada }
        if Self.argumentos.contains("-PRUEBAS_UI_METRO_SIN_RED") { throw ErrorConsulta.sinConexion }
        if Self.argumentos.contains("-PRUEBAS_UI_METRO_LENTO") { try await Task.sleep(nanoseconds: 60_000_000_000) }
        return Self.metroSimulado
    }

    func estacionesCercanas(_ lectura: LecturaParaEnviar) async throws -> RespuestaEstacionesCercanas {
        let argumentos = Self.argumentos
        if argumentos.contains("-PRUEBAS_UI_GPS_FALLA") { throw ErrorConsulta.sinConexion }
        let catalogo = ProcedenciaCatalogo(procedencia: "[SIMULADO] Datos de prueba.", antiguo: false)
        if argumentos.contains("-PRUEBAS_UI_GPS_VACIA") {
            return RespuestaEstacionesCercanas(resultado: .cercanas, estaciones: [], catalogo: catalogo)
        }
        let cardinal = argumentos.contains("-PRUEBAS_UI_GPS_CARDINAL")
        let muyCerca = argumentos.contains("-PRUEBAS_UI_GPS_MUY_CERCA")
        let datos: [(String, Double, Double, Int, String, String, String)] = [
            ("Estación Ejemplo Centro", 4.6504, -74.0851, 40, "40 metros", "al norte", "de frente"),
            ("Estación Ejemplo Norte", 4.7000, -74.0800, 5_600, "5,6 kilómetros", "al norte", "de frente"),
            ("Estación Ejemplo Sur", 4.6000, -74.0900, 5_500, "5,5 kilómetros", "al sur", "hacia atrás"),
            ("Estación Ejemplo Oriente", 4.6500, -74.0300, 5_900, "5,9 kilómetros", "al este", "a tu derecha"),
        ]
        let estaciones = datos.enumerated().map { indice, d in
            let orientacion = OrientacionEstacion(
                modo: cardinal ? .cardinalBrujula : .relativa, cardinal: d.5, relativa: cardinal ? nil : d.6,
                indicacion: cardinal
                    ? "[SIMULADO] \(d.0) está a \(d.4) \(d.5) (referencia aproximada)."
                    : "[SIMULADO] \(d.0) está a \(d.4) \(d.6).")
            return EstacionCercana(
                nombre: d.0, coordenada: Coordenada(latitud: d.1, longitud: d.2), distanciaMetros: d.3,
                distanciaHablada: d.4, orientacion: orientacion, muyCerca: muyCerca && indice == 0)
        }
        return RespuestaEstacionesCercanas(resultado: .cercanas, estaciones: estaciones, catalogo: catalogo)
    }

    /// Catálogo del Metro inventado: 16 estaciones sobre una línea recta en una ciudad de ejemplo. Nada coincide con el real.
    private static let metroSimulado: RespuestaMetro = {
        let lado = 0.0006
        let estaciones = (1...16).map { n -> EstacionMetro in
            let id = String(format: "E%02d", n)
            let lat = 4.60 + Double(n - 1) * 0.008
            let lng = -74.14 + Double(n - 1) * 0.004
            let nombre: String? = n == 7 ? nil : "Estación de ejemplo \(n)"
            let mostrado = nombre ?? "nombre pendiente"
            let etiqueta = "\(id) · \(mostrado): huella ilustrativa del proyecto; no es una entrada"
            return EstacionMetro(
                numero: n, id: id, nombre: nombre, nombreMostrado: mostrado, nombreEstado: n == 7 ? .pendiente : .anunciado,
                corredor: "[SIMULADO] Corredor de ejemplo \(n)",
                descripcionNombre: "[SIMULADO] El nombre de la estación \(n) es inventado.",
                nombreTecnico: "Nombre técnico de referencia: EJEMPLO-\(n) (archivo inventado).",
                conexion: "[SIMULADO] Conexión futura de ejemplo. Hoy no hay transbordos habilitados.",
                avisoUbicacion: "No tengo ubicación exacta ni accesos validados.",
                enElMapa: "En el mapa: huella ilustrativa del proyecto; no es una entrada.",
                etiquetaHuella: etiqueta, fuentes: ["F1"],
                huella: [
                    Coordenada(latitud: lat - lado, longitud: lng - lado), Coordenada(latitud: lat - lado, longitud: lng + lado),
                    Coordenada(latitud: lat + lado, longitud: lng + lado), Coordenada(latitud: lat + lado, longitud: lng - lado),
                    Coordenada(latitud: lat - lado, longitud: lng - lado),
                ])
        }
        return RespuestaMetro(
            linea: LineaMetro(
                nombre: "Línea 1", subtitulo: "Línea 1 · en construcción · sin servicio",
                estado: "en construcción y sin servicio comercial",
                horizonte: "[SIMULADO] La previsión de apertura es inventada y es solo una previsión.", servicioComercial: false),
            textoEstado: "[SIMULADO] Metro de ejemplo, Línea 1: en construcción y sin servicio comercial. Solo consulta: no planeo viajes en Metro. Datos de prueba al 1 de enero de 2026.",
            mapa: MapaMetro(
                rotulo: "Metro Línea 1 · proyecto futuro, sin servicio",
                aviso: "[SIMULADO] El mapa es una ilustración de un proyecto futuro: no es una ruta en servicio.",
                atribucion: "[SIMULADO] Trazado y huellas inventados para pruebas. Licencia de ejemplo. Dato de prueba del 01-01-2022.",
                atribucionCorta: "[SIMULADO] Datos inventados", entidad: "Entidad de ejemplo", publicador: "Publicador de ejemplo",
                licencia: "Licencia de ejemplo", licenciaUrl: "https://servidor.ejemplo/licencia",
                fechaDato: "2022-01-01", consultado: "2026-01-01", cambios: ["[SIMULADO] Trazado simplificado."],
                trazado: estaciones.map { Coordenada(latitud: 4.60 + Double($0.numero - 1) * 0.008, longitud: -74.14 + Double($0.numero - 1) * 0.004) }),
            estaciones: estaciones,
            linea2: LineaDosMetro(titulo: "Línea 2 · en contratación · 11 estaciones proyectadas", texto: "[SIMULADO] Ficha de contexto inventada, sin estaciones."),
            corte: CorteMetro(fecha: "2026-01-01", hablada: "1 de enero de 2026"),
            atribucion: "[SIMULADO] Atribución inventada de los identificadores.",
            fuentes: [FuenteMetro(
                id: "F1", entidad: "Entidad de ejemplo", titulo: "Documento de ejemplo", fecha: "2026-01-01",
                url: "https://servidor.ejemplo/fuente", texto: "F1 · Entidad de ejemplo: Documento de ejemplo (2026-01-01)")])
    }()
}
#endif
