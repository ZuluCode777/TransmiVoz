import Foundation

/// Respuesta de la operación `metro-linea-1` de `POST /api/planificador` (`lib/contrato-metro.ts`, EA-25): lo que
/// muestran la pantalla «Metro de Bogotá» de la web y su capa del mapa. Es el catálogo EDUCATIVO de un proyecto
/// futuro, sin servicio: no usa rutas, GPS ni planificador de TransMilenio, y no lleva `catalogo`.
///
/// Igual que el resto de respuestas del planificador, el decodificador es estricto en la frontera: una coordenada fuera
/// de rango, un texto vacío o desmedido, un número de estaciones distinto de 16 o `servicioComercial: true` se rechazan
/// como incompatibles. La app NO decide nada del Metro: pinta lo que el servidor dice, con su rótulo y su atribución.
/// Reglas de EA-24 que el contrato conserva y que aquí no se rompen:
/// - una huella es un POLÍGONO ilustrativo; no existe un punto por estación (un centroide parecería una entrada), ni
///   accesos peatonales, ni geometría de la Línea 2;
/// - el rótulo, el aviso y la atribución con licencia y fecha se muestran junto al mapa.
struct RespuestaMetro: RespuestaPlanificador, Equatable {
    /// Cotas del servidor (`lib/contrato-metro.ts`).
    static let numeroEstaciones = 16
    static let maximoPuntosTrazado = 500
    static let minimoPuntosHuella = 4
    static let maximoPuntosHuella = 100
    static let maximoTexto = 1_500
    static let maximoFuentes = 30
    static let maximoCambios = 10

    let linea: LineaMetro
    /// Nota de estado de la pantalla: estado, límites, aviso del mapa y fecha de corte.
    let textoEstado: String
    let mapa: MapaMetro
    let estaciones: [EstacionMetro]
    let linea2: LineaDosMetro
    let corte: CorteMetro
    /// Atribución de los identificadores y nombres técnicos reutilizados.
    let atribucion: String
    let fuentes: [FuenteMetro]

    var esValida: Bool {
        linea.esValida && textoEstado.esTextoDeMetro && mapa.esValido
            && estaciones.count == Self.numeroEstaciones
            && estaciones.enumerated().allSatisfy { indice, estacion in estacion.esValida(posicion: indice + 1) }
            && linea2.esValida && corte.esValido && atribucion.esTextoDeMetro
            && fuentes.count <= Self.maximoFuentes && fuentes.allSatisfy(\.esValida)
    }
}

private extension String {
    /// No vacío ni desmedido, como `Texto` en el esquema del servidor.
    var esTextoDeMetro: Bool {
        !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && count <= RespuestaMetro.maximoTexto
    }

    /// `AAAA-MM-DD`, como el esquema del servidor.
    var esFechaIso: Bool { range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
}

struct LineaMetro: Decodable, Equatable, Sendable {
    let nombre: String
    /// Encabezado de la pantalla: «Línea 1 · en construcción · sin servicio».
    let subtitulo: String
    let estado: String
    /// La previsión de apertura. Es una previsión, no una fecha de servicio.
    let horizonte: String
    /// Siempre `false`: la Línea 1 no tiene servicio comercial.
    let servicioComercial: Bool

    var esValida: Bool {
        nombre.esTextoDeMetro && subtitulo.esTextoDeMetro && estado.esTextoDeMetro && horizonte.esTextoDeMetro
            && !servicioComercial
    }
}

struct MapaMetro: Decodable, Equatable, Sendable {
    /// Rótulo fijo del marco del mapa: siempre visible.
    let rotulo: String
    let aviso: String
    /// Atribución completa con licencia, fecha y cambios, junto al mapa.
    let atribucion: String
    /// Forma corta para el control de atribución del propio mapa.
    let atribucionCorta: String
    let entidad: String
    let publicador: String
    let licencia: String
    let licenciaUrl: String
    /// Fecha del dato (diseño de 2022) y de la consulta, `AAAA-MM-DD`.
    let fechaDato: String
    let consultado: String
    let cambios: [String]
    /// Trazado SIMPLIFICADO de la Línea 1: una ilustración, no una ruta en servicio.
    let trazado: [Coordenada]

    var esValido: Bool {
        [rotulo, aviso, atribucion, atribucionCorta, entidad, publicador, licencia, licenciaUrl].allSatisfy(\.esTextoDeMetro)
            && fechaDato.esFechaIso && consultado.esFechaIso
            && cambios.count <= RespuestaMetro.maximoCambios && cambios.allSatisfy(\.esTextoDeMetro)
            && (2...RespuestaMetro.maximoPuntosTrazado).contains(trazado.count)
    }
}

enum EstadoNombreMetro: String, Decodable, Equatable, Sendable {
    case votado, anunciado, pendiente
}

struct EstacionMetro: Decodable, Equatable, Sendable, Identifiable {
    let numero: Int
    /// Identificador oficial del archivo de estaciones, E01–E16.
    let id: String
    /// `nil` si el nombre público está pendiente (E07).
    let nombre: String?
    /// El nombre tal como lo dice la web: «nombre pendiente» si no hay.
    let nombreMostrado: String
    let nombreEstado: EstadoNombreMetro
    let corredor: String
    let descripcionNombre: String
    let nombreTecnico: String
    /// Conexión FUTURA con TransMilenio como previsión; nunca habilita un transbordo.
    let conexion: String
    let avisoUbicacion: String
    let enElMapa: String
    /// Lo que dice la huella: número, nombre y «no es una entrada».
    let etiquetaHuella: String
    /// Ids de `fuentes` que respaldan la estación.
    let fuentes: [String]
    /// Anillo del polígono ilustrativo. No es un acceso, una parada ni un transbordo.
    let huella: [Coordenada]

    func esValida(posicion: Int) -> Bool {
        numero == posicion && id == String(format: "E%02d", posicion)
            && (nombre?.esTextoDeMetro ?? true) && nombreMostrado.esTextoDeMetro
            && [corredor, descripcionNombre, nombreTecnico, conexion, avisoUbicacion, enElMapa, etiquetaHuella]
                .allSatisfy(\.esTextoDeMetro)
            && fuentes.count <= RespuestaMetro.maximoFuentes
            && (RespuestaMetro.minimoPuntosHuella...RespuestaMetro.maximoPuntosHuella).contains(huella.count)
    }
}

struct LineaDosMetro: Decodable, Equatable, Sendable {
    let titulo: String
    let texto: String

    var esValida: Bool { titulo.esTextoDeMetro && texto.esTextoDeMetro }
}

struct CorteMetro: Decodable, Equatable, Sendable {
    /// Fecha de corte del catálogo, `AAAA-MM-DD`.
    let fecha: String
    let hablada: String

    var esValido: Bool { fecha.esFechaIso && hablada.esTextoDeMetro }
}

struct FuenteMetro: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let entidad: String
    let titulo: String
    let fecha: String
    let url: String
    /// La línea que muestra la web: «F1 · entidad: título (fecha)».
    let texto: String

    var esValida: Bool { [id, entidad, titulo, fecha, url, texto].allSatisfy(\.esTextoDeMetro) }

    /// El enlace solo se abre si es HTTPS: lo que el servidor manda no decide a qué esquema salta la app.
    var enlace: URL? {
        guard let direccion = URL(string: url), direccion.scheme?.lowercased() == "https", direccion.host != nil else { return nil }
        return direccion
    }
}
