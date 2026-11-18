import * as bindings from "gtfs-realtime-bindings"

/**
 * Cliente de los feeds GTFS Realtime de TransMilenio S.A. (solo servidor).
 *
 * Son tres, sin llave ni autenticación, en protobuf `FeedMessage` (el servidor
 * los marca `text/plain`, pero el cuerpo es binario). Se decodifican con el
 * paquete oficial de MobilityData, `gtfs-realtime-bindings`.
 *
 * - `positions.pb` (~550 KB, ~4.500 buses) y `alerts.pb` (~130 KB): se leen con
 *   espera acotada y una copia en memoria de `TTL_MS`. Una sola petición por
 *   feed y TTL, lleguen las consultas que lleguen. Si la lectura falla y hay una
 *   copia anterior, se devuelve esa copia marcada como obsoleta.
 * - `tripupdates.pb` (~8,8 MB, todos los viajes del día): no se espera en la
 *   petición. Se reduce al decodificar a un mapa compacto y se refresca aparte;
 *   quien consulta usa la última copia buena, o ninguna si aún no hay.
 *
 * Reglas de frescura de la fuente: un feed cuya cabecera tiene más de
 * `FEED_DETENIDO_S` segundos está detenido, y un bus cuyo propio reporte tiene
 * más de `VEHICULO_VIEJO_S` no cuenta.
 */

const { transit_realtime: rt } = ((bindings as unknown as { default?: typeof bindings }).default ?? bindings) as typeof bindings

export const URL_BASE_RT = "https://gtfs.transmilenio.gov.co"
/** Más allá de esto la cabecera del feed ya no es de ahora. */
export const FEED_DETENIDO_S = 300
/** Un bus que no reporta hace más de esto no se cuenta. */
export const VEHICULO_VIEJO_S = 300
/** Un reporte de retraso más viejo que esto no se usa para describir un bus. */
export const RETRASO_VIEJO_S = 900
const USER_AGENT = "asistente-accesible-gtfs-rt/1.0 (app de accesibilidad para TransMilenio)"

export type FeedId = "positions" | "alerts" | "tripupdates"

export type Vehiculo = {
  id: string
  /** `vehicle.label`, p. ej. `Z32-7046`. */
  etiqueta: string
  rutaId: string
  tripId: string
  lat: number
  lng: number
  /** Hora del reporte del propio bus, en segundos de época. */
  ts: number
}

export type AlertaRt = {
  id: string
  rutas: string[]
  paradas: string[]
  efecto: string
  causa: string
  titulo: string
  descripcion: string
  /** `[inicio, fin]` en segundos de época; `fin` nulo si no tiene. */
  periodos: [number, number | null][]
}

export type ScheduleRel = "SCHEDULED" | "ADDED" | "CANCELED" | "OTRO"

export type ViajeRt = {
  tripId: string
  rutaId: string
  /** Salida programada del viaje, en segundos de época. */
  inicio: number
  rel: ScheduleRel
  /** Segundos de retraso (negativo: adelantado); nulo si el feed no lo trae. */
  retraso: number | null
  vehiculoId: string
  /** Última hora de este dato, en segundos de época. */
  ts: number
}

export type Posiciones = { cabecera: number; vehiculos: Vehiculo[] }
export type Alertas = { cabecera: number; alertas: AlertaRt[] }
export type Retrasos = {
  cabecera: number
  porViaje: Map<string, ViajeRt>
  porVehiculo: Map<string, ViajeRt[]>
  total: number
}

/** Una lectura de un feed: los datos, cuándo se leyeron y si son una copia vieja tras un fallo. */
export type Lectura<T> = {
  datos: T
  /** Instante (ms) en que se leyó del servidor. */
  leidoEn: number
  /** `true` si la última lectura falló y estos datos son de una anterior. */
  obsoleto: boolean
}

export type SaludFeed = {
  feed: FeedId
  /** ¿Hay alguna copia en memoria? */
  conCopia: boolean
  /** Segundos desde que se leyó la copia, o `null`. */
  edadLecturaS: number | null
  /** Segundos desde la hora que dice la cabecera del feed, o `null`. */
  edadCabeceraS: number | null
  /** Cabecera con más de `FEED_DETENIDO_S`: la fuente dejó de actualizar. */
  detenido: boolean
  /** La última lectura falló y se sirve una copia anterior. */
  obsoleto: boolean
  /** Último error, solo el nombre (sin direcciones). */
  ultimoError: string | null
  entidades: number
}

type Dependencias = {
  fetchFn?: typeof fetch
  ahora?: () => number
}

type Meta = { ultimoError: string | null; entidades: number; cabecera: number | null }

type Fuente<T> = {
  /** Espera la lectura (con la copia al día si no venció el TTL). Falla si no hay ni copia. */
  leer(): Promise<Lectura<T>>
  /** No espera: devuelve la última copia buena (o `null`) y lanza el refresco si venció. */
  leerSinEsperar(): Lectura<T> | null
  salud(): SaludFeed
}

function crearFuente<T>(opciones: {
  feed: FeedId
  ttlMs: number
  timeoutMs: number
  maxBytes: number
  decodificar: (mensaje: bindings.transit_realtime.FeedMessage) => { datos: T; cabecera: number; entidades: number }
  deps?: Dependencias
}): Fuente<T> {
  const { feed, ttlMs, timeoutMs, maxBytes, decodificar } = opciones
  const fetchFn = opciones.deps?.fetchFn ?? fetch
  const ahora = opciones.deps?.ahora ?? Date.now
  let copia: Lectura<T> | null = null
  let enCurso: Promise<void> | null = null
  const meta: Meta = { ultimoError: null, entidades: 0, cabecera: null }

  async function descargar(): Promise<void> {
    try {
      const respuesta = await fetchFn(`${URL_BASE_RT}/${feed}.pb`, {
        headers: { "User-Agent": USER_AGENT, Accept: "application/x-protobuf, application/octet-stream, */*" },
        signal: AbortSignal.timeout(timeoutMs),
        cache: "no-store",
        redirect: "error",
      })
      if (!respuesta.ok) throw new Error(`HTTP ${respuesta.status}`)
      const largo = Number(respuesta.headers.get("content-length") ?? 0)
      if (largo > maxBytes) throw new Error("respuesta demasiado grande")
      const bytes = new Uint8Array(await respuesta.arrayBuffer())
      if (bytes.byteLength > maxBytes) throw new Error("respuesta demasiado grande")
      const { datos, cabecera, entidades } = decodificar(rt.FeedMessage.decode(bytes))
      copia = { datos, leidoEn: ahora(), obsoleto: false }
      meta.ultimoError = null
      meta.entidades = entidades
      meta.cabecera = cabecera
    } catch (error) {
      // Solo el nombre del error: el de `fetch` trae la dirección en `cause`.
      meta.ultimoError = error instanceof Error ? (error.name === "Error" ? error.message : error.name) : "fallo"
      if (copia) copia = { ...copia, obsoleto: true }
    }
  }

  /** Una sola lectura a la vez por feed. */
  const iniciar = (): Promise<void> => (enCurso ??= descargar().finally(() => (enCurso = null)))
  const vigente = () => copia !== null && ahora() - copia.leidoEn < ttlMs

  return {
    async leer() {
      if (!vigente()) await iniciar()
      if (!copia) throw new Error(`feed ${feed}: ${meta.ultimoError ?? "sin datos"}`)
      return copia
    },
    leerSinEsperar() {
      if (!vigente()) void iniciar()
      return copia
    },
    salud() {
      const edadCabeceraS = meta.cabecera === null ? null : Math.max(0, Math.round(ahora() / 1000 - meta.cabecera))
      return {
        feed,
        conCopia: copia !== null,
        edadLecturaS: copia ? Math.round((ahora() - copia.leidoEn) / 1000) : null,
        edadCabeceraS,
        detenido: edadCabeceraS !== null && edadCabeceraS > FEED_DETENIDO_S,
        obsoleto: copia?.obsoleto ?? false,
        ultimoError: meta.ultimoError,
        entidades: meta.entidades,
      }
    },
  }
}

const numero = (valor: unknown): number => Number(valor ?? 0)

export function decodificarPosiciones(mensaje: bindings.transit_realtime.FeedMessage) {
  const vehiculos: Vehiculo[] = []
  for (const entidad of mensaje.entity) {
    const v = entidad.vehicle
    if (!v?.position || !v.trip?.routeId) continue
    vehiculos.push({
      id: v.vehicle?.id || entidad.id,
      etiqueta: v.vehicle?.label ?? "",
      rutaId: v.trip.routeId,
      tripId: v.trip.tripId ?? "",
      lat: v.position.latitude,
      lng: v.position.longitude,
      ts: numero(v.timestamp),
    })
  }
  const cabecera = numero(mensaje.header.timestamp)
  return { datos: { cabecera, vehiculos } satisfies Posiciones, cabecera, entidades: vehiculos.length }
}

/** Texto en español de un `TranslatedString`, o el primero que haya. */
function texto(traduccion: bindings.transit_realtime.ITranslatedString | null | undefined): string {
  const lista = traduccion?.translation ?? []
  return (lista.find((t) => t.language === "es") ?? lista[0])?.text ?? ""
}

const EFECTOS = rt.Alert.Effect
const CAUSAS = rt.Alert.Cause

export function decodificarAlertas(mensaje: bindings.transit_realtime.FeedMessage) {
  const alertas: AlertaRt[] = []
  for (const entidad of mensaje.entity) {
    const a = entidad.alert
    if (!a) continue
    alertas.push({
      id: entidad.id,
      rutas: [...new Set((a.informedEntity ?? []).map((e) => e.routeId).filter((x): x is string => !!x))],
      paradas: [...new Set((a.informedEntity ?? []).map((e) => e.stopId).filter((x): x is string => !!x))],
      efecto: EFECTOS[a.effect ?? 0] ?? "UNKNOWN_EFFECT",
      causa: CAUSAS[a.cause ?? 0] ?? "UNKNOWN_CAUSE",
      titulo: texto(a.headerText),
      descripcion: texto(a.descriptionText),
      periodos: (a.activePeriod ?? []).map((p): [number, number | null] => [numero(p.start), p.end ? numero(p.end) : null]),
    })
  }
  const cabecera = numero(mensaje.header.timestamp)
  return { datos: { cabecera, alertas } satisfies Alertas, cabecera, entidades: alertas.length }
}

const RELACION = rt.TripDescriptor.ScheduleRelationship
const relacion = (valor: number | null | undefined): ScheduleRel =>
  valor === RELACION.CANCELED ? "CANCELED" : valor === RELACION.ADDED ? "ADDED" : !valor ? "SCHEDULED" : "OTRO"

/** Segundos de época de una fecha `AAAAMMDD` y una hora `HH:MM:SS` de Bogotá (UTC-5, sin horario de verano). */
export function epocaBogota(fecha: string, hora: string): number | null {
  const f = /^(\d{4})(\d{2})(\d{2})$/.exec(fecha)
  const h = /^(\d{1,2}):(\d{2}):(\d{2})$/.exec(hora)
  if (!f || !h) return null
  return Date.UTC(Number(f[1]), Number(f[2]) - 1, Number(f[3])) / 1000 + Number(h[1]) * 3600 + Number(h[2]) * 60 + Number(h[3]) + 5 * 3600
}

/**
 * Reduce `tripupdates.pb` (84.000 viajes) a lo que usa la estimación y descarta el
 * `FeedMessage` decodificado: viaje → retraso y relación con el horario, y los
 * viajes de cada bus. Los viajes de este feed casi no comparten `trip_id` con los
 * de `positions.pb` (medido: ~5 %), por eso también se indexan por bus.
 */
export function decodificarRetrasos(mensaje: bindings.transit_realtime.FeedMessage) {
  const porViaje = new Map<string, ViajeRt>()
  const porVehiculo = new Map<string, ViajeRt[]>()
  for (const entidad of mensaje.entity) {
    const t = entidad.tripUpdate
    if (!t?.trip?.tripId || !t.trip.routeId) continue
    const inicio = epocaBogota(t.trip.startDate ?? "", t.trip.startTime ?? "")
    if (inicio === null) continue
    const viaje: ViajeRt = {
      tripId: t.trip.tripId,
      rutaId: t.trip.routeId,
      inicio,
      rel: relacion(t.trip.scheduleRelationship),
      retraso: typeof t.delay === "number" ? t.delay : null,
      vehiculoId: t.vehicle?.id ?? "",
      ts: numero(t.timestamp),
    }
    porViaje.set(viaje.tripId, viaje)
    if (viaje.vehiculoId) {
      const lista = porVehiculo.get(viaje.vehiculoId)
      if (lista) lista.push(viaje)
      else porVehiculo.set(viaje.vehiculoId, [viaje])
    }
  }
  const cabecera = numero(mensaje.header.timestamp)
  return { datos: { cabecera, porViaje, porVehiculo, total: porViaje.size } satisfies Retrasos, cabecera, entidades: porViaje.size }
}

/** TTL de la copia de posiciones y alertas: una lectura por feed y TTL (el feed se regenera cada 26–75 s). */
export const TTL_POSICIONES_MS = 15_000
/** `tripupdates.pb` se regenera igual de lento y pesa 8,8 MB: se refresca cada 60 s, fuera de la petición. */
export const TTL_RETRASOS_MS = 60_000
/**
 * Espera máxima por `positions.pb` y `alerts.pb`. La web espera 6 s en total
 * (`ESPERA_MAXIMA_CLIENTE_MS`) y el modelo hasta 4,5 s, con el que la lectura corre
 * en paralelo (ver `app/api/agent/route.ts`): 3,5 s dejan margen para estimar.
 */
export const ESPERA_FEED_MS = 3_500

export function crearFuentes(deps?: Dependencias) {
  return {
    posiciones: crearFuente<Posiciones>({ feed: "positions", ttlMs: TTL_POSICIONES_MS, timeoutMs: ESPERA_FEED_MS, maxBytes: 4_000_000, decodificar: decodificarPosiciones, deps }),
    alertas: crearFuente<Alertas>({ feed: "alerts", ttlMs: TTL_POSICIONES_MS, timeoutMs: ESPERA_FEED_MS, maxBytes: 2_000_000, decodificar: decodificarAlertas, deps }),
    retrasos: crearFuente<Retrasos>({ feed: "tripupdates", ttlMs: TTL_RETRASOS_MS, timeoutMs: 30_000, maxBytes: 40_000_000, decodificar: decodificarRetrasos, deps }),
  }
}

/**
 * Las fuentes viven en `globalThis`: Next compila una copia de cada módulo para
 * `instrumentation.ts` y otra para cada ruta, y con variables del módulo no
 * compartirían la caché (mismo motivo que el estado de `lib/ollama.ts`).
 */
const almacen = globalThis as typeof globalThis & { __transmivozGtfsRt?: ReturnType<typeof crearFuentes> }
/** Las fuentes compartidas del servidor. Es una función para que las pruebas puedan poner las suyas en `globalThis`. */
export const fuentes = (): ReturnType<typeof crearFuentes> => (almacen.__transmivozGtfsRt ??= crearFuentes())

/** Salud de los tres feeds, para el diagnóstico y para decirle a la persona si el dato es confiable. */
export function saludDeFeeds(origen: ReturnType<typeof crearFuentes> = fuentes()): SaludFeed[] {
  return [origen.posiciones.salud(), origen.alertas.salud(), origen.retrasos.salud()]
}

/** Segundos de edad de una lectura respecto de `ahoraMs`. */
export const edadS = (lectura: Lectura<unknown>, ahoraMs: number) => Math.max(0, Math.round((ahoraMs - lectura.leidoEn) / 1000))

/** ¿La cabecera del feed es de hace más de `FEED_DETENIDO_S`? */
export const feedDetenido = (cabecera: number, ahoraMs: number) => ahoraMs / 1000 - cabecera > FEED_DETENIDO_S
