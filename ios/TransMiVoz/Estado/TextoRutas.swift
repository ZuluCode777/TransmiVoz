import Foundation

/// Textos de las pantallas de rutas, detalle y viaje. Cada aviso largo es una oración por `Text` (con texto muy
/// grande una oración suelta se lee y se recorre mejor que un párrafo). Ninguno ordena subir, bajar ni transbordar:
/// la guardia de contenido (`GuardiaContenido`) los revisa en `TextoRutasTests`.
enum TextoRutas {
    // MARK: Buscar rutas

    static let titulo = "Rutas y viaje"
    static let introduccionBusqueda = "Busca una ruta por su código o por el nombre de una estación."
    static let sinUbicacion = "No se envía tu ubicación."
    static let etiquetaCampo = "Ruta o estación"
    static let pistaCampo = "Escribe un código como B23 o el nombre de una estación."
    static let botonBuscar = "Buscar rutas"
    static let enlaceViaje = "Planear un viaje entre dos lugares"
    static let pistaEnlaceViaje = "Eliges el origen y el destino de una lista; no escribes una frase."
    static let consultando = "Buscando rutas…"

    // MARK: Buscar con la voz (components/voice-overlay.tsx)

    static let buscarHablando = "Buscar hablando"
    static let pistaBuscarHablando = "Abre el micrófono para decir una estación o un código de ruta. También puedes escribirlo."
    static let tituloVoz = "Comando de voz"
    static let cerrarMicrofono = "Cerrar micrófono"
    static let vozEscuchando = "Escuchando…"
    static let vozListo = "Listo"
    static let vozTocaParaHablar = "Toca para hablar"
    static let vozDetener = "Detener"
    static let vozHablarDeNuevo = "Hablar de nuevo"
    static let vozTeEscucho = "Te escucho. Di el nombre de una estación o un código de ruta."
    static let vozSinDictado = "El dictado no está disponible en esta pantalla. Cierra y escribe tu búsqueda."
    static let vozAvisoEscribir = "Si prefieres, cierra y escribe tu búsqueda."
    static let vozAvisoServidor = "Lo que dictes se envía como texto al servidor para buscar rutas. No se envía tu ubicación."
    static func vozTranscripcion(_ texto: String) -> String { "«\(texto)»" }

    // MARK: Rutas frecuentes (el botón «Rutas frecuentes» de components/partial-routes.tsx)

    static let rutasFrecuentes = "Rutas frecuentes"
    static let pistaRutasFrecuentes = "Tus rutas guardadas. Abre cada una para ver su detalle."

    static func entradaInvalida(_ motivo: MotivoEntradaInvalida) -> String {
        switch motivo {
        case .vacia: return "Escribe un código de ruta o el nombre de una estación."
        case .demasiadoLarga(let maximo): return "El texto supera \(maximo) caracteres. Acórtalo para buscar."
        }
    }

    static func resumenBusqueda(mostradas: Int, total: Int) -> String {
        if total > mostradas { return "Se muestran \(mostradas) de \(total) rutas." }
        return total == 1 ? "1 ruta encontrada" : "\(total) rutas encontradas"
    }

    static let acotarBusqueda = "Escribe más del nombre para acotar la búsqueda."

    static func sinResultados(_ consulta: String) -> String { "No encontré rutas para «\(consulta)»." }
    static let sinResultadosAyuda = "Prueba con el código de la ruta o con el nombre de otra estación."

    static let pistaDetalle = "Abre el detalle y el mapa de la ruta."

    static func etiquetaRuta(_ ruta: ResumenRuta) -> String {
        "Ruta \(ruta.codigo), de \(ruta.desde) hacia \(ruta.hacia)"
    }

    // MARK: Detalle de una ruta

    static func tituloDetalle(_ codigo: String) -> String { "Ruta \(codigo)" }
    static let cargandoDetalle = "Cargando la ruta…"
    static func trayecto(_ desde: String, _ hacia: String) -> String { "De \(desde) hacia \(hacia)" }

    /// Aviso sobre el sentido; vacío si una fuente vigente lo confirma. El orden de las estaciones solo vale con
    /// el sentido confirmado, así que sin él la pantalla lo dice y no lo da por hecho.
    static func avisoSentido(_ sentido: SentidoRuta, desde: String, hacia: String) -> [String] {
        switch sentido {
        case .confirmado:
            return []
        case .contradictorio:
            return [
                "El sentido declarado (de \(desde) hacia \(hacia)) no coincide con el orden de las estaciones del recorrido.",
                "Verifica la dirección antes de guiarte por ella.",
            ]
        case .sinConfirmar:
            return [
                "El sentido declarado (de \(desde) hacia \(hacia)) todavía no está confirmado con una fuente vigente.",
                "Verifica la dirección antes de guiarte por ella.",
            ]
        }
    }

    static let tituloHorario = "Horario"

    // MARK: Escuchar y actualización periódica

    static let escuchar = "Escuchar"
    static let pistaEscuchar = "Lee la ruta en voz alta."
    static let escuchaNoDisponible = "La voz de la app no está disponible en esta pantalla. La ruta está escrita aquí abajo."
    static let escuchaConMicrofono = "No se lee en voz alta: el micrófono está abierto."
    static let actualizacionFallida = "No se pudo actualizar esta pantalla. Lo que ves puede haber vencido: se vuelve a intentar en unos segundos."

    /// Lo que «Escuchar» dice: las mismas frases de `describe` de `route-detail.tsx`, con lo que el servidor decidió
    /// (`sentido`, `calendario`, `paradaVerificada`). Ni da órdenes de abordaje ni afirma lo que el servidor no confirma.
    static func descripcionHablada(_ detalle: DetalleRuta) -> String {
        let sentido: String
        switch detalle.sentido {
        case .confirmado:
            sentido = "de \(detalle.desde) hacia \(detalle.hacia)"
        case .contradictorio:
            sentido = "con sentido declarado de \(detalle.desde) hacia \(detalle.hacia), aún sin confirmar porque el orden de las estaciones no coincide"
        case .sinConfirmar:
            sentido = "con sentido declarado de \(detalle.desde) hacia \(detalle.hacia), todavía sin confirmar con una fuente vigente"
        }
        let cantidad = detalle.estaciones.count
        let recorrido = "Su recorrido pasa cerca de \(cantidad) \(cantidad == 1 ? "estación" : "estaciones")."
        let paradas = detalle.estaciones.contains(where: \.paradaVerificada)
            ? ""
            : " Aún no tengo confirmado en qué estaciones para, así que no uses el recorrido como paradas de abordaje."
        let operacion: String
        switch detalle.calendario {
        case .opera:
            operacion = " Según su calendario verificado, hoy tiene servicio programado; no es tiempo real, confirma el horario antes de salir."
        case .noOpera:
            operacion = " Según su calendario verificado, hoy no tiene servicio programado."
        case .sinVerificar:
            let semana = detalle.horario.entreSemana.trimmingCharacters(in: .whitespacesAndNewlines)
            operacion = semana.isEmpty
                ? " No tengo un calendario vigente verificado para confirmar si opera ahora."
                : " Su horario publicado entre semana es \(semana), pero no tengo un calendario vigente verificado para confirmar si opera ahora."
        }
        return "Ruta \(detalle.codigo), \(sentido). \(recorrido)\(paradas)\(operacion) \(detalle.catalogo.procedencia)"
    }

    static func frasesCalendario(_ calendario: CalendarioRuta) -> [String] {
        switch calendario {
        case .opera:
            return ["Según el calendario verificado, hoy tiene servicio programado.", "No es tiempo real: confirma el horario antes de salir."]
        case .noOpera:
            return ["Según el calendario verificado, hoy no tiene servicio programado."]
        case .sinVerificar:
            return ["El horario de abajo es el publicado por TransMilenio, no un calendario verificado y vigente.", "No confirma si opera ahora."]
        }
    }

    static func filaHorario(_ titulo: String, _ valor: String) -> String {
        let limpio = valor.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(titulo): \(limpio.isEmpty ? "No publicado" : limpio)"
    }

    static func tituloEstaciones(_ cantidad: Int) -> String { "Estaciones cercanas al trazado (\(cantidad))" }

    static func notaEstaciones(conVerificadas: Bool) -> [String] {
        let comun = "Son las estaciones por las que pasa el bus."
        return conVerificadas
            ? [comun, "Las marcadas como parada verificada son donde una fuente confirma que se puede subir o bajar."]
            : [comun, "Aún no hay una fuente que confirme en cuáles para: no uses esta lista como paradas de abordaje."]
    }

    static func filaEstacion(_ posicion: Int, _ nombre: String) -> String { "\(posicion). \(nombre)" }
    static let paradaVerificada = "Parada verificada"

    // MARK: Procedencia del catálogo

    static let catalogoAntiguo = "Los datos de TransMilenio no están actualizados: son una copia guardada o una consulta vencida."
    static let catalogoAntiguoAyuda = "Vuelve a consultar en unos minutos."
    static let volverAConsultar = "Volver a consultar"

    // MARK: Favoritas

    static func etiquetaGuardar(_ codigo: String) -> String { "Guardar la ruta \(codigo) en favoritas" }
    static func etiquetaQuitar(_ codigo: String) -> String { "Quitar la ruta \(codigo) de favoritas" }
    static let guardar = "Guardar"
    static let quitar = "Quitar"
    static func guardada(_ codigo: String, total: Int) -> String {
        "Guardé la ruta \(codigo) en tus favoritas. " + (total == 1 ? "Tienes 1 ruta favorita." : "Tienes \(total) rutas favoritas.")
    }

    // MARK: Mapa

    static func etiquetaMapaRuta(_ codigo: String) -> String {
        "Mapa del recorrido de la ruta \(codigo). Es una ayuda visual: el listado tiene la misma información."
    }

    static func etiquetaMapaViaje(origen: String, destino: String) -> String {
        "Mapa del viaje de \(origen) a \(destino). Es una ayuda visual: el listado tiene la misma información."
    }

    static let mapaSinCoordenadas = "El servidor no entregó coordenadas para dibujar el mapa; el listado tiene la información."
    static let mapaNecesitaConexion = "El mapa necesita conexión para mostrar las calles; el listado no."
    static let mapaModoPruebas = "Modo de pruebas: el mapa no se dibuja; el listado tiene lo mismo."

    // MARK: Viaje entre dos lugares

    static let tituloViaje = "Viaje entre dos lugares"
    static let introduccionViaje = "Elige el origen y el destino de la lista de lugares del servidor."
    static let cargandoLugares = "Cargando los lugares…"
    static let lugaresCargados = "Lugares cargados. Elige el origen y el destino."
    static let origen = "Origen"
    static let destino = "Destino"
    static let sinElegir = "Sin elegir"
    static let pistaSelector = "Abre la lista de lugares para elegir."
    static let botonPlanear = "Planear viaje"
    static let faltaElegir = "Elige el origen y el destino para planear el viaje."
    static let planeando = "Planeando el viaje…"

    static func filaSelector(_ rol: String, _ lugar: String?) -> String { "\(rol): \(lugar ?? sinElegir)" }
    static func tituloSelector(_ rol: String) -> String { "Elegir \(rol.lowercased())" }
    static let etiquetaFiltro = "Filtrar lugares"
    static func sinCoincidencias(_ filtro: String) -> String { "Ningún lugar coincide con «\(filtro)»." }
    static func lugarElegido(_ rol: String, _ lugar: String) -> String { "\(rol): \(lugar)." }

    static func tituloResultado(_ plan: PlanViaje) -> String {
        switch plan.resultado {
        case .operativo: return "Viaje de \(plan.origen) a \(plan.destino)"
        case .candidato: return "Servicio candidato de \(plan.origen) a \(plan.destino)"
        case .recorrido: return "Recorrido sin paradas confirmadas"
        case .sinRecorrido: return "Sin recorrido troncal registrado"
        case .mismoLugar: return "El origen y el destino coinciden"
        }
    }

    static func notasResultado(_ plan: PlanViaje) -> [String] {
        switch plan.resultado {
        case .operativo:
            return [
                "El servidor verificó las paradas y el sentido al consultar.",
                "No es tiempo real: confirma el horario antes de salir.",
                "Mientras ves esta pantalla, el viaje se vuelve a consultar cada 30 segundos.",
            ]
        case .candidato:
            let varias = plan.codigosCandidatos.count > 1
            return [
                "Según la programación verificada, \(varias ? "estas rutas conectan" : "esta ruta conecta") \(plan.origen) con \(plan.destino).",
                "Ahora no se puede confirmar que \(varias ? "estén" : "esté") en servicio, así que no se dan indicaciones de abordaje.",
                "Confirma el horario con TransMilenio.",
            ]
        case .recorrido:
            return [
                "Todavía no se tiene confirmado dónde para cada servicio entre \(plan.origen) y \(plan.destino), así que no se puede decir con certeza dónde subir o bajar.",
                "Estas rutas pasan cerca de los dos lugares; confirma las paradas con TransMilenio.",
            ]
        case .sinRecorrido:
            return [
                "No hay un recorrido troncal registrado que conecte \(plan.origen) con \(plan.destino).",
                "Puede existir un servicio que no está registrado: confírmalo con TransMilenio.",
            ]
        case .mismoLugar:
            return ["El origen y el destino que elegiste coinciden: ambos son \(plan.origen)."]
        }
    }

    /// «También te sirven…» de la web, solo con los códigos: la otra ruta puede abordarse en otra estación del mismo lugar y
    /// el servidor no garantiza la parada, así que no se dice dónde subir.
    static func tituloAlternativas(_ codigos: [String]) -> String {
        switch codigos.count {
        case 0: return ""
        case 1: return "También te sirve la ruta \(codigos[0])"
        default: return "También te sirven las rutas \(codigos.dropLast().joined(separator: ", ")) y \(codigos[codigos.count - 1])"
        }
    }

    static let notaAlternativas = "El servidor no confirma en qué estación se aborda cada una. Abre su detalle y confirma las paradas."
    static func etiquetaAlternativa(_ codigo: String) -> String { "Ruta \(codigo), otra ruta directa" }

    static func tituloTramo(_ posicion: Int, _ codigo: String) -> String { "Tramo \(posicion): ruta \(codigo)" }
    static let notaTransbordo = "Hay un transbordo entre los dos tramos."

    /// Un viaje operativo nombra el abordaje y el descenso de cada tramo. Un candidato no tiene tramos con paradas: la
    /// operación no está confirmada y el servidor solo manda los códigos (`rutaCandidata`).
    static func filasTramo(_ tramo: TramoPlan) -> [String] {
        ["Abordaje: \(tramo.abordaje.nombre)", "Descenso: \(tramo.descenso.nombre)", conteo(tramo)]
    }

    static func rutaCandidata(_ codigo: String) -> String { "Ruta \(codigo)" }

    static func conteo(_ tramo: TramoPlan) -> String {
        guard tramo.conteoVerificado else { return "Número de estaciones no verificado" }
        let n = tramo.estacionesRecorridas
        return "\(n) \(n == 1 ? "estación" : "estaciones") (conteo verificado)"
    }

    static let tituloRutasPorElTrazado = "Rutas que pasan cerca de los dos lugares"
}
