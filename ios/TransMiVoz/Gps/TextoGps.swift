import ContratoBLE
import Foundation

/// Textos de la pantalla «Mapa y GPS». Los de orientación (distancia hablada, referencia cardinal, giro, frase) los escribe
/// el servidor con las mismas funciones que la web: aquí solo se arman las frases de alrededor, con las palabras de la
/// web (`components/auditory-gps.tsx`) donde existen.
enum TextoGps {
    static let titulo = "Mapa y GPS"
    static let subtitulo = "Te oriento por voz hacia la estación más cercana"
    static let activar = "Activar mi ubicación"
    static let detener = "Detener la ubicación"
    static let repetir = "Repetir indicación"
    /// «La app dijo» (EA-02 §5): todo lo que esta pantalla dice por voz, en texto, con su «Repetir». Distinto de «Repetir
    /// indicación», que pide otra consulta y dice la dirección del servidor.
    static let appDijo = "La app dijo"
    static let repetirLoDicho = "Repetir"
    static let repetirLoDichoEtiqueta = "Repetir lo que dijo la app"
    static let actualizar = "Actualizar estaciones"
    static let orientarme = "Oriéntame por voz"
    static let abrirAjustes = "Abrir Ajustes"
    static let encabezadoEstaciones = "Estaciones cercanas"
    static let etiquetaMapa = "Mapa con tu ubicación y las estaciones cercanas"
    static let tuUbicacion = "Tú estás aquí"
    static let orientando = "Orientando"
    static let mapaModoPruebas = "Modo de pruebas: ubicación sintética, sin GPS real, y el mapa no se dibuja. El listado está completo."
    static let mapaNecesitaConexion = "Sin conexión el mapa no baja las calles: quedan tu ubicación y las estaciones sobre un fondo vacío."

    /// Qué hace la pantalla con la ubicación, dicho antes de pedir el permiso del sistema. Es cierto y completo: lo que se
    /// envía, a quién y qué no se hace.
    static let privacidad =
        "Uso tu ubicación solo mientras esta pantalla está abierta y tú la activas. Envío al servidor de TransMiVoz tu ubicación, qué tan precisa es, cuánto hace que se midió y, si tu iPhone tiene brújula, hacia dónde apunta, para ordenar las estaciones y calcular distancias, orientación y cercanía aproximadas; no la guardo ni la registro, ni a ella ni a esos datos, y no la sigo en segundo plano. Al salir de la pantalla o bloquear el iPhone, se detiene."

    static let activando = "Activando ubicación. Por favor acepta el permiso."
    static let yaActiva = "La ubicación ya está activa."
    static let buscando = "Buscando tu ubicación. Puede tardar unos segundos."
    static let sinSenal = "Todavía no hay señal de ubicación. Sigo buscando."
    static let detenida = "Ubicación detenida."
    static let consultando = "Buscando las estaciones más cercanas."
    static let esperaUnMomento = "Espera unos segundos antes de pedir otra actualización."
    static let ubicacionVencida =
        "Tu ubicación ya no está actualizada. Espera una lectura nueva o toca «Detener la ubicación» y vuelve a activarla."
    static let sinEstaciones =
        "No tengo estaciones de TransMilenio cargadas en este momento. Tu ubicación sí está activa; vuelve a intentarlo cuando se carguen las estaciones."
    static let permisoDenegado =
        "No diste permiso de ubicación. Puedes activarlo en Ajustes y volver a tocar «Activar mi ubicación»."
    static let permisoRestringido =
        "La ubicación está restringida en este iPhone (por ejemplo, por un control parental). No se puede activar desde la app."
    static let noDisponible = "Esta versión de la app no puede pedir la ubicación."
    static let rumboNoDisponible = "Este iPhone no tiene brújula: no envío rumbo al servidor."
    static let rumboSinLectura =
        "Todavía no hay una lectura de brújula con el norte verdadero: no envío rumbo al servidor."
    static let abrirEnMapas = "Abrir en Mapas"
    static let notaMapas =
        "Ruta a pie aproximada hasta el punto de la estación en la app Mapas, que parte de donde estás; la accesibilidad del acceso no está verificada."
    static let vozOcupada = "Suena otro aviso: lo que ibas a oír queda en pantalla. Vuelve a pedirlo cuando termine."
    static let limiteDeOrientacion = "Es una orientación aproximada: la accesibilidad del acceso no está verificada."

    static func ubicacionLista(_ estacion: EstacionCercana) -> String {
        "Ubicación lista. La estación más cercana es \(estacion.nombre), a \(distancia(estacion))."
    }

    static func actualizada(_ estacion: EstacionCercana) -> String {
        "Estaciones actualizadas. La más cercana es \(estacion.nombre), a \(distancia(estacion))."
    }

    static func orientandoHacia(_ estacion: EstacionCercana) -> String {
        "Te oriento hacia \(estacion.nombre). \(estacion.orientacion.indicacion) \(limiteDeOrientacion)"
    }

    /// El aviso de la web: lo dice una sola vez por estación elegida, solo si el servidor la marca `muyCerca`. El punto es
    /// una referencia aproximada: no promete llegada ni un acceso accesible.
    static func muyCerca(_ estacion: EstacionCercana) -> String {
        "Estás muy cerca de \(estacion.nombre), a unos \(estacion.distanciaHablada). Busca el acceso de la estación; el punto es una referencia aproximada, no un acceso verificado."
    }

    /// Lo que dice la web al abrir la ruta en Google Maps, con la app Mapas del sistema.
    static func abriMapas(_ nombre: String) -> String {
        "Abrí una ruta a pie aproximada hacia \(nombre) en Mapas. La accesibilidad del acceso no está verificada."
    }

    static func fueraDeLasMasCercanas(_ nombre: String) -> String {
        "\(nombre) ya no está entre las estaciones más cercanas. Elige otra de la lista."
    }

    /// «90 metros al suroeste»; sin la referencia cardinal si la estación cae dentro del margen de error de la lectura.
    static func distancia(_ estacion: EstacionCercana) -> String {
        guard let cardinal = estacion.orientacion.cardinal else { return estacion.distanciaHablada }
        return "\(estacion.distanciaHablada) \(cardinal)"
    }

    /// La fila de la lista: «A 90 metros al suroeste».
    static func filaDistancia(_ estacion: EstacionCercana) -> String { "A \(distancia(estacion))" }

    static func precision(metros: Double) -> String {
        "Precisión de tu ubicación: unos \(Int(metros.rounded())) metros."
    }

    static let precisionDesconocida = "Tu ubicación no informa su precisión."

    /// Antigüedad de la lectura vigente, junto a la precisión. Nunca pasa de 59 s: a los 60 s la lectura vence y no se muestra.
    static func edad(milisegundos: Milisegundos) -> String {
        let segundos = Int(milisegundos / 1_000)
        guard segundos >= 1 else { return "Lectura de ubicación de hace menos de un segundo." }
        return "Lectura de ubicación de hace \(segundos) \(segundos == 1 ? "segundo" : "segundos")."
    }

    /// Cómo salió la última frase de «La app dijo»: si se oyó o por qué no. El texto está en pantalla en todos los casos.
    static func resultadoVoz(_ resultado: ResultadoLocucion) -> String {
        switch resultado {
        case .hablada:
            return "Se dijo en voz alta."
        case .anunciada:
            return "La voz de la app está apagada o no hay auriculares: se anunció con VoiceOver."
        case .ocupada:
            return "No se dijo en voz alta: suena otro aviso de la app y no se le corta. Pulsa Repetir cuando termine."
        case .silenciada:
            return "No se dijo en voz alta: la voz de la app está apagada o no hay una salida de audio privada. El texto está aquí."
        }
    }
}
