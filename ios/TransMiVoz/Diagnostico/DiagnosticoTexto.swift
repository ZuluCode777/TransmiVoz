import Foundation

/// Estado de un permiso del sistema, ya traducido (micrófono, reconocimiento de voz, cámara). Solo se lee: el diagnóstico
/// nunca provoca el aviso de permiso del sistema.
enum PermisoDiagnostico: Equatable, Sendable {
    case porPreguntar, concedido, denegado, restringido
}

/// Qué pasó al intentar decir la frase de prueba por la voz compartida de la app (`ControlVoz`).
enum HablaDiagnostico: Equatable, Sendable {
    /// La frase propia sonó entera: nadie la cortó ni la reemplazó (`ControlVoz.ultimaSeOyoEntera`). Es lo único que cuenta como éxito.
    case dichaEntera
    /// Empezó pero no terminó: otro aviso la reemplazó, una llamada o el sistema la cortó, o la prueba se canceló.
    case interrumpida
    /// Seguía sonando al vencer el tope: se cortó (solo la propia).
    case noTerminoATiempo
    /// La app solo habla por auriculares: por el altavoz no suena (política de `ControlVoz`).
    case rutaNoPrivada
    /// La voz propia de la app está apagada (VoiceOver activo, o la persona la apagó): la regla de `ControlVoz.permitida`.
    case vozApagada
    /// Ya suena otra locución de la app (un aviso del accesorio, la respuesta de la consulta): no se la corta ni se la tapa.
    case otraVozSonando
    /// El sistema no dejó activar el audio (llamada u otra app en curso).
    case sesionNoDisponible
}

/// Textos del diagnóstico (web: `components/diagnostics.tsx`). Cada resultado dice con palabras si salió bien, falta algo o
/// falló: el color y el ícono de la pantalla nunca son la única señal. Ningún texto lleva la clave, la dirección del
/// servidor ni datos de la persona.
enum DiagnosticoTexto {
    static let titulo = "Diagnóstico"
    static let subtitulo = "Pruebas en vivo"
    /// Una frase por párrafo: con el texto más grande cada una cabe entera en el área visible.
    static let explicacion = [
        "Comprueba en vivo, en este iPhone, que cada función de TransMiVoz responde.",
    ]
    static let probarTodo = "Probar todo"
    static let probar = "Probar"
    static let notas = [
        "Cada prueba corre al tocar «Probar».",
        "Solo lee el estado de los permisos: no los pide.",
        "No guarda audio ni imagen y no muestra la clave del servidor.",
    ]

    static let sinProbar = "Sin probar"
    static let probando = "Probando…"
    static let sinRespuesta = "La prueba no respondió a tiempo."
    static let sinSonda = "La prueba no está disponible en este iPhone."

    /// La frase que la prueba de voz dice en voz alta (la de la web).
    static let fraseDeVoz = "Prueba de voz de TransMiVoz."
    /// La pregunta que la prueba del asistente le hace al servidor (la de la web).
    static let preguntaDelAsistente = "cómo llego de Portal Usme a Molinos"

    static func resumen(correctas: Int, total: Int) -> String { "\(correctas) de \(total) correctas" }

    static func titulo(_ prueba: PruebaDiagnostico) -> String {
        switch prueba {
        case .servidor: return "Servidor"
        case .asistente: return "Asistente"
        case .planificador: return "Rutas y viaje"
        case .voz: return "Voz de la app"
        case .reconocimiento: return "Reconocimiento de voz"
        case .microfono: return "Micrófono"
        case .camara: return "Cámara"
        case .bluetooth: return "Bluetooth"
        }
    }

    /// Qué demuestra la prueba, en palabras de quien la mira (`proves` de la web).
    static func demuestra(_ prueba: PruebaDiagnostico) -> String {
        switch prueba {
        case .servidor: return "La app llega al servidor que escribiste en Ajustes y recibe respuesta."
        case .asistente: return "El asistente entiende una consulta de viaje y responde."
        case .planificador: return "La búsqueda de rutas y el viaje entre dos lugares reciben la lista de lugares del servidor."
        case .voz: return "La app puede hablar en español."
        case .reconocimiento: return "El iPhone puede entender lo que dices."
        case .microfono: return "La app puede escuchar."
        case .camara: return "La lupa puede usar la cámara."
        case .bluetooth: return "La app puede buscar el accesorio de proximidad."
        }
    }

    static func etiqueta(_ estado: EstadoPrueba) -> String {
        switch estado {
        case .correcto: return "Correcto"
        case .atencion: return "Atención"
        case .fallo: return "Falló"
        }
    }

    /// La línea de una fila: «Sin probar», «Probando…» o «Correcto: …» / «Atención: …» / «Falló: …».
    static func linea(_ fila: FilaDiagnostico) -> String {
        switch fila {
        case .sinProbar: return sinProbar
        case .probando: return probando
        case .terminada(let resultado): return "\(etiqueta(resultado.estado)): \(resultado.detalle)"
        }
    }

    /// La línea de una fila partida en frases, para que con el texto más grande cada una quepa entera en pantalla. La primera
    /// lleva el estado («Correcto: …»); juntas dicen lo mismo que `linea`.
    static func lineas(_ fila: FilaDiagnostico) -> [String] {
        let completa = linea(fila)
        let partes = completa.components(separatedBy: ". ")
        return partes.enumerated().map { posicion, parte in posicion < partes.count - 1 ? parte + "." : parte }
    }

    // MARK: Servidor y asistente (por los clientes de la app)

    /// Un error de los clientes HTTP, con el mensaje y la recuperación que ya tienen. Sin dirección del servidor no hay nada
    /// que probar: es «atención», no un servidor caído. Cualquier otro error es un fallo.
    static func falloDeServidor(_ error: Error) -> ResultadoPrueba {
        let consulta = (error as? ErrorConsulta) ?? .sinConexion
        let estado: EstadoPrueba = consulta == .servidorNoConfigurado ? .atencion : .fallo
        return ResultadoPrueba(estado: estado, detalle: "\(consulta.mensaje) \(consulta.recuperacion)")
    }

    static func servidor(_ respuesta: AnunciosRespuesta) -> ResultadoPrueba {
        let anuncios = respuesta.anuncios.count == 1 ? "1 anuncio" : "\(respuesta.anuncios.count) anuncios"
        return ResultadoPrueba(
            estado: .correcto,
            detalle: "El servidor respondió. Fuente de anuncios: \(TextoAnuncios.etiqueta(respuesta.fuente.estado)). \(anuncios).")
    }

    static func asistente(_ respuesta: RespuestaAgente) -> ResultadoPrueba {
        let motor = respuesta.motor == .ollama ? "el modelo de lenguaje" : "las reglas del servidor"
        return ResultadoPrueba(estado: .correcto, detalle: "El asistente respondió con \(motor). El texto de la respuesta no se muestra aquí.")
    }

    /// El planificador: la lista de lugares respondió. Sin lugares, o con un catálogo antiguo, el servidor llegó pero las
    /// rutas no son confiables: «atención». La frase de procedencia es la que da el servidor, tal cual.
    static func planificador(_ lista: ListaLugares) -> ResultadoPrueba {
        let cuantos = lista.lugares.count == 1 ? "1 lugar" : "\(lista.lugares.count) lugares"
        if lista.lugares.isEmpty {
            return ResultadoPrueba(estado: .atencion, detalle: "El planificador respondió, pero sin lugares. \(lista.catalogo.procedencia)")
        }
        if lista.catalogo.antiguo {
            return ResultadoPrueba(estado: .atencion, detalle: "El planificador respondió con \(cuantos), pero el catálogo está antiguo. \(lista.catalogo.procedencia)")
        }
        return ResultadoPrueba(estado: .correcto, detalle: "El planificador respondió con \(cuantos). \(lista.catalogo.procedencia)")
    }

    /// Un servidor sin el planificador contesta 404 sin el cuerpo del contrato (`ClientePlanificadorHTTP`): no es «el servidor
    /// falló» sino que le falta el endpoint. El resto de errores son los de siempre.
    static func falloDelPlanificador(_ error: Error) -> ResultadoPrueba {
        if (error as? ErrorConsulta) == .errorDelServidor(estado: 404) {
            return ResultadoPrueba(estado: .fallo, detalle: "El servidor no tiene el planificador de rutas (404). Avisa a quien lo administra: puede estar desactualizado.")
        }
        return falloDeServidor(error)
    }

    // MARK: Voz y permisos (el estado lo lee `DiagnosticoSondas`)

    static func voz(vocesEnEspanol: Int, habla: HablaDiagnostico) -> ResultadoPrueba {
        let voces = vocesEnEspanol == 0
            ? "Sin voz en español instalada: usa la voz por defecto."
            : (vocesEnEspanol == 1 ? "1 voz en español." : "\(vocesEnEspanol) voces en español.")
        switch habla {
        case .dichaEntera:
            return ResultadoPrueba(estado: vocesEnEspanol == 0 ? .atencion : .correcto, detalle: "\(voces) La frase terminó entera: debiste oír «Prueba de voz».")
        case .interrumpida:
            return ResultadoPrueba(
                estado: .atencion,
                detalle: "\(voces) La frase se interrumpió antes de terminar (otro aviso, una llamada o el sistema la cortó). Vuelve a probar.")
        case .noTerminoATiempo:
            return ResultadoPrueba(estado: .atencion, detalle: "\(voces) La frase no terminó a tiempo y se cortó. Vuelve a probar.")
        case .rutaNoPrivada:
            return ResultadoPrueba(
                estado: .atencion,
                detalle: "\(voces) La voz está lista, pero la app solo habla por auriculares y ahora la salida es el altavoz. Conecta auriculares y vuelve a probar.")
        case .vozApagada:
            return ResultadoPrueba(
                estado: .atencion,
                detalle: "\(voces) La voz de la app está apagada (VoiceOver activo o apagada en Preferencias), así que no se dijo la frase. Enciéndela y vuelve a probar.")
        case .otraVozSonando:
            return ResultadoPrueba(estado: .atencion, detalle: "\(voces) Suena otro aviso de la app y no se le corta. Vuelve a probar cuando termine.")
        case .sesionNoDisponible:
            return ResultadoPrueba(estado: .fallo, detalle: "\(voces) El iPhone no dejó activar el audio (una llamada u otra app lo está usando).")
        }
    }

    static func reconocimiento(permiso: PermisoDiagnostico, capacidad: CapacidadReconocimiento) -> ResultadoPrueba {
        switch permiso {
        case .denegado:
            return ResultadoPrueba(estado: .fallo, detalle: "Permiso de reconocimiento de voz denegado. Actívalo en Ajustes de iOS, en TransMiVoz.")
        case .restringido:
            return ResultadoPrueba(estado: .fallo, detalle: "Reconocimiento de voz restringido en este iPhone.")
        case .porPreguntar, .concedido:
            break
        }
        let declarado: String
        switch capacidad {
        case .noDisponible:
            return ResultadoPrueba(estado: .fallo, detalle: "El iPhone no ofrece ahora reconocimiento de voz en español (sin conexión o restringido).")
        case .local(let idioma):
            declarado = "Reconocimiento en el iPhone (\(idioma))."
        case .remoto(let idioma):
            declarado = "El audio se envía a Apple para reconocerlo (\(idioma))."
        }
        if permiso == .porPreguntar {
            return ResultadoPrueba(estado: .atencion, detalle: "Todavía no diste el permiso de reconocimiento de voz; se pide al dictar en Consulta. \(declarado)")
        }
        return ResultadoPrueba(estado: .correcto, detalle: "Permiso concedido. \(declarado)")
    }

    static func microfono(_ permiso: PermisoDiagnostico) -> ResultadoPrueba {
        switch permiso {
        case .concedido: return ResultadoPrueba(estado: .correcto, detalle: "Permiso concedido.")
        case .porPreguntar:
            return ResultadoPrueba(estado: .atencion, detalle: "Todavía no diste el permiso del micrófono; se pide al dictar en Consulta.")
        case .denegado:
            return ResultadoPrueba(estado: .fallo, detalle: "Permiso del micrófono denegado. Actívalo en Ajustes de iOS, en TransMiVoz.")
        case .restringido:
            return ResultadoPrueba(estado: .fallo, detalle: "Micrófono restringido en este iPhone.")
        }
    }

    static func camara(_ permiso: PermisoDiagnostico, hayCamara: Bool) -> ResultadoPrueba {
        guard hayCamara else {
            return ResultadoPrueba(estado: .fallo, detalle: "Este iPhone no tiene una cámara trasera disponible (en el Simulator no hay cámara).")
        }
        switch permiso {
        case .concedido: return ResultadoPrueba(estado: .correcto, detalle: "Permiso concedido. Hay cámara trasera.")
        case .porPreguntar:
            return ResultadoPrueba(estado: .atencion, detalle: "Todavía no diste el permiso de la cámara; se pide al abrir la lupa. Hay cámara trasera.")
        case .denegado:
            return ResultadoPrueba(estado: .fallo, detalle: "Permiso de la cámara denegado. Actívalo en Ajustes de iOS, en TransMiVoz.")
        case .restringido:
            return ResultadoPrueba(estado: .fallo, detalle: "Cámara restringida en este iPhone.")
        }
    }

    /// Prefijo de lo que sale de una sonda sintética de las pruebas de interfaz: nunca se confunde con una lectura real.
    static func simulado(_ resultado: ResultadoPrueba) -> ResultadoPrueba {
        ResultadoPrueba(estado: resultado.estado, detalle: "[SIMULADO] \(resultado.detalle)")
    }
}
