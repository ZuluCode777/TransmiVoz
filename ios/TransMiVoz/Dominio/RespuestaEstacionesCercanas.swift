import Foundation

/// Respuesta de la operación `estaciones-cercanas` de `POST /api/planificador` (`RespuestaEstacionesCercanasSchema` en
/// `lib/contrato-planificador.ts`, EA-25): las estaciones de TransMilenio más cercanas a una lectura de ubicación, con su
/// distancia y orientación. La app NO calcula distancia, rumbo ni giro: el servidor ordena, mide y orienta con las mismas
/// funciones que el GPS auditivo de la web (`nearestStations`, `orientarHacia`, `decisionLlegada`), y aquí solo se valida
/// y se pinta. La respuesta no repite la coordenada, la precisión ni el rumbo que se enviaron.
///
/// El decodificador es estricto en lo que el contrato fija y tolerante en lo que se añade de forma compatible:
/// - un `resultado`, un `modo` o un tipo desconocido, una coordenada fuera de rango o un texto vacío se rechazan;
/// - una clave que este cliente no conoce se ignora;
/// - `muyCerca` es opcional: si falta vale `false` (un servidor anterior no la envía).
struct RespuestaEstacionesCercanas: RespuestaPlanificador, Equatable {
    /// Estaciones que devuelve el servidor como máximo (`MAX_ESTACIONES_CERCANAS`).
    static let maximoEstaciones = 4
    static let maximoCaracteresTexto = 1_000

    /// `cercanas`, o `ubicacion-vencida` (la lectura enviada tenía más de 60 s y el servidor no la usó).
    enum Resultado: String, Decodable, Equatable, Sendable {
        case cercanas
        case ubicacionVencida = "ubicacion-vencida"
    }

    let resultado: Resultado
    /// De la más cercana a la más lejana. Vacía con `ubicacion-vencida`.
    let estaciones: [EstacionCercana]
    let catalogo: ProcedenciaCatalogo

    var esValida: Bool {
        guard catalogo.esValida, estaciones.count <= Self.maximoEstaciones,
              estaciones.allSatisfy(\.esValida) else { return false }
        return resultado == .cercanas || estaciones.isEmpty
    }
}

/// Cómo orienta el servidor hacia una estación. Lo decide él con la precisión, el rumbo y su edad: el cliente no lo
/// recalcula ni lo corrige.
enum ModoOrientacion: String, Decodable, Equatable, Sendable {
    /// Precisión suficiente y rumbo fiable: hay un giro («a tu derecha»).
    case relativa
    /// Precisión suficiente pero sin rumbo fiable: solo referencia cardinal.
    case cardinalBrujula = "cardinal-brujula"
    /// Sin precisión o con precisión insuficiente: solo referencia cardinal, nunca un giro.
    case cardinalPrecision = "cardinal-precision"
    /// La estación cae dentro del margen de error de la lectura: ninguna dirección.
    case sinDireccion = "sin-direccion"
}

struct OrientacionEstacion: Decodable, Equatable, Sendable {
    let modo: ModoOrientacion
    /// «al noreste»; `nil` solo con `sinDireccion`.
    let cardinal: String?
    /// «a tu derecha»; `nil` salvo con `relativa`.
    let relativa: String?
    /// La frase que la web dice al orientar hacia la estación.
    let indicacion: String

    var esValida: Bool {
        guard indicacion.tieneTextoDeCercanas, cardinal?.tieneTextoDeCercanas ?? true,
              relativa?.tieneTextoDeCercanas ?? true else { return false }
        // El contrato liga el giro al modo y la ausencia de dirección al margen de error.
        switch modo {
        case .relativa: return relativa != nil && cardinal != nil
        case .cardinalBrujula, .cardinalPrecision: return relativa == nil && cardinal != nil
        case .sinDireccion: return relativa == nil && cardinal == nil
        }
    }
}

struct EstacionCercana: Decodable, Equatable, Sendable {
    let nombre: String
    /// Coordenada de la ESTACIÓN (del catálogo), para el mapa. No es la de la persona.
    let coordenada: Coordenada
    /// Metros, redondeados por el servidor.
    let distanciaMetros: Int
    /// «90 metros», «1,2 kilómetros»: como la dice la web.
    let distanciaHablada: String
    let orientacion: OrientacionEstacion
    /// Decisión del servidor (`decisionLlegada` sobre la distancia sin redondear): la lectura está tan cerca de la
    /// estación que ya puede decirse «estás muy cerca». El cliente no usa ninguna distancia propia. Falta en un servidor
    /// anterior: vale `false`.
    let muyCerca: Bool

    private enum Claves: String, CodingKey {
        case nombre, coordenada, distanciaMetros, distanciaHablada, orientacion, muyCerca
    }

    init(from decoder: Decoder) throws {
        let contenedor = try decoder.container(keyedBy: Claves.self)
        nombre = try contenedor.decode(String.self, forKey: .nombre)
        coordenada = try contenedor.decode(Coordenada.self, forKey: .coordenada)
        distanciaMetros = try contenedor.decode(Int.self, forKey: .distanciaMetros)
        distanciaHablada = try contenedor.decode(String.self, forKey: .distanciaHablada)
        orientacion = try contenedor.decode(OrientacionEstacion.self, forKey: .orientacion)
        muyCerca = try contenedor.decodeIfPresent(Bool.self, forKey: .muyCerca) ?? false
    }

    init(
        nombre: String, coordenada: Coordenada, distanciaMetros: Int, distanciaHablada: String,
        orientacion: OrientacionEstacion, muyCerca: Bool = false
    ) {
        self.nombre = nombre
        self.coordenada = coordenada
        self.distanciaMetros = distanciaMetros
        self.distanciaHablada = distanciaHablada
        self.orientacion = orientacion
        self.muyCerca = muyCerca
    }

    var esValida: Bool {
        nombre.tieneTextoDeCercanas && distanciaMetros >= 0 && distanciaHablada.tieneTextoDeCercanas && orientacion.esValida
    }
}

private extension String {
    var tieneTextoDeCercanas: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && count <= RespuestaEstacionesCercanas.maximoCaracteresTexto
    }
}
