import Foundation

/// Cotas de la entrada del planificador (`POST /api/planificador`). Son las de `lib/contrato-planificador.ts`: la
/// prueba `lib/ea25-planificador.test.ts` lee este archivo y las compara. El servidor cuenta unidades UTF-16
/// (`String.length`), igual que `utf16.count`.
enum EntradaPlanificador {
    static let maximoConsulta = 80
    static let maximoCodigo = 12
    static let maximoLugar = 80
    static let maximoBytesCuerpo = 1_000
    /// Cotas de `estaciones-cercanas`: radio de precisión (m) y edad de las lecturas (ms).
    static let maximoPrecisionMetros = 100_000.0
    static let maximaEdadLecturaMs = 600_000
}

/// Brújula respecto al NORTE GEOGRÁFICO, para el giro relativo de `estaciones-cercanas`. Sin ella el servidor nunca da un
/// giro. El cliente solo la manda si el sistema da un rumbo verdadero válido: no inventa uno ni usa el magnético.
struct RumboParaEnviar: Equatable, Sendable {
    /// 0…360 respecto al norte verdadero.
    let grados: Double
    /// Cota de error en grados (`headingAccuracy`); `nil` si el sistema no la da o es negativa: el servidor la trata como no fiable.
    let calidad: Double?
    /// Milisegundos desde que se midió.
    let edadMs: Int
}

/// Lectura de ubicación que viaja en el CUERPO del POST (nunca en la URL). Su descripción oculta los valores: una lectura
/// que se imprime sin querer (un fallo de prueba, un volcado) no deja la coordenada en ningún registro.
struct LecturaParaEnviar: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let latitud: Double
    let longitud: Double
    /// Radio de precisión en metros; `nil` si el sistema no lo da. Sin él el servidor solo da referencia cardinal.
    let precision: Double?
    /// Milisegundos desde que se capturó la lectura.
    let edadMs: Int
    let rumbo: RumboParaEnviar?

    var description: String { "LecturaParaEnviar(…)" }
    var debugDescription: String { description }

    /// Dentro de las cotas del contrato: lo que el servidor rechazaría con 400 no se envía.
    var esValida: Bool {
        latitud.isFinite && longitud.isFinite && (-90.0...90.0).contains(latitud) && (-180.0...180.0).contains(longitud)
            && (precision.map { $0.isFinite && (0...EntradaPlanificador.maximoPrecisionMetros).contains($0) } ?? true)
            && (0...EntradaPlanificador.maximaEdadLecturaMs).contains(edadMs)
            && (rumbo.map { rumbo in
                rumbo.grados.isFinite && (0.0...360.0).contains(rumbo.grados)
                    && (rumbo.calidad.map { $0.isFinite && (-1.0...360.0).contains($0) } ?? true)
                    && (0...EntradaPlanificador.maximaEdadLecturaMs).contains(rumbo.edadMs)
            } ?? true)
    }
}

/// Petición al planificador. La selección de origen y destino viaja como DATOS (nombres exactos de la lista de
/// lugares del servidor), nunca como una frase que el servidor deba interpretar.
enum PeticionPlanificador: Equatable, Sendable {
    case buscarRutas(consulta: String)
    case detalleRuta(codigo: String)
    case listarLugares
    case planearViaje(origen: String, destino: String)
    /// Metro de la Línea 1 (catálogo educativo, sin servicio): no lleva datos.
    case metroLinea1
    /// Las estaciones más cercanas a una lectura de ubicación.
    case estacionesCercanas(LecturaParaEnviar)

    /// La petición con los textos recortados, o `.peticionRechazada` si alguno queda vacío o pasa la cota: no se
    /// envía lo que el servidor rechazaría con 400. La pantalla da sus propios mensajes antes de llegar aquí.
    func validada() -> Result<PeticionPlanificador, ErrorConsulta> {
        func limpiar(_ texto: String, maximo: Int) -> String? {
            let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            return limpio.isEmpty || limpio.utf16.count > maximo ? nil : limpio
        }
        switch self {
        case .buscarRutas(let consulta):
            guard let consulta = limpiar(consulta, maximo: EntradaPlanificador.maximoConsulta) else {
                return .failure(.peticionRechazada)
            }
            return .success(.buscarRutas(consulta: consulta))
        case .detalleRuta(let codigo):
            guard let codigo = limpiar(codigo, maximo: EntradaPlanificador.maximoCodigo) else {
                return .failure(.peticionRechazada)
            }
            return .success(.detalleRuta(codigo: codigo))
        case .listarLugares:
            return .success(self)
        case .planearViaje(let origen, let destino):
            guard let origen = limpiar(origen, maximo: EntradaPlanificador.maximoLugar),
                  let destino = limpiar(destino, maximo: EntradaPlanificador.maximoLugar) else {
                return .failure(.peticionRechazada)
            }
            return .success(.planearViaje(origen: origen, destino: destino))
        case .metroLinea1:
            return .success(self)
        case .estacionesCercanas(let lectura):
            return lectura.esValida ? .success(self) : .failure(.peticionRechazada)
        }
    }
}

extension PeticionPlanificador: Encodable {
    private enum Claves: String, CodingKey {
        case operacion, consulta, codigo, origen, destino, lat, lng, precision, edadMs, rumbo
    }

    private enum ClavesRumbo: String, CodingKey {
        case grados, calidad, edadMs
    }

    func encode(to encoder: Encoder) throws {
        var contenedor = encoder.container(keyedBy: Claves.self)
        switch self {
        case .buscarRutas(let consulta):
            try contenedor.encode("buscar-rutas", forKey: .operacion)
            try contenedor.encode(consulta, forKey: .consulta)
        case .detalleRuta(let codigo):
            try contenedor.encode("detalle-ruta", forKey: .operacion)
            try contenedor.encode(codigo, forKey: .codigo)
        case .listarLugares:
            try contenedor.encode("listar-lugares", forKey: .operacion)
        case .planearViaje(let origen, let destino):
            try contenedor.encode("planear-viaje", forKey: .operacion)
            try contenedor.encode(origen, forKey: .origen)
            try contenedor.encode(destino, forKey: .destino)
        case .metroLinea1:
            try contenedor.encode("metro-linea-1", forKey: .operacion)
        case .estacionesCercanas(let lectura):
            try contenedor.encode("estaciones-cercanas", forKey: .operacion)
            try contenedor.encode(lectura.latitud, forKey: .lat)
            try contenedor.encode(lectura.longitud, forKey: .lng)
            // Los opcionales ausentes no viajan: el servidor los toma como «sin precisión» o «sin rumbo».
            try contenedor.encodeIfPresent(lectura.precision, forKey: .precision)
            try contenedor.encode(lectura.edadMs, forKey: .edadMs)
            if let rumbo = lectura.rumbo {
                var anidado = contenedor.nestedContainer(keyedBy: ClavesRumbo.self, forKey: .rumbo)
                try anidado.encode(rumbo.grados, forKey: .grados)
                try anidado.encodeIfPresent(rumbo.calidad, forKey: .calidad)
                try anidado.encode(rumbo.edadMs, forKey: .edadMs)
            }
        }
    }
}
