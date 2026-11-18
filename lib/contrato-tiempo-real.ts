import { z } from "zod"

/**
 * Contrato de `POST /api/tiempo-real`: los servicios en vivo de TransMilenio
 * (llegadas, buses, paradas cercanas, alertas…) como JSON para la web y para un
 * cliente nativo futuro. Detrás del mismo HTTP Basic que el resto de la app
 * (el `proxy` cubre la ruta) y con su propio límite de peticiones.
 *
 * Privacidad: una coordenada llega en el cuerpo (nunca en la URL), se usa para
 * calcular y no se guarda, no se registra y no se devuelve. El manejador no
 * registra ninguna petición.
 */

export const MAXIMO_BYTES_CUERPO = 1_000
export const MAX_TEXTO = 80
/** Límites por minuto: una sola clave para todos (ver `claveCliente`). Las lecturas de feeds ya están en caché. */
export const LIMITE_TIEMPO_REAL = 60
export const VENTANA_TIEMPO_REAL_MS = 60_000
export const MAX_RADIO_M = 5_000
export const MAX_RESULTADOS = 20

const texto = z.string().trim().min(1).max(MAX_TEXTO)
const coordenada = { lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180) }
const radio = z.number().positive().max(MAX_RADIO_M)
const maximo = z.number().int().min(1).max(MAX_RESULTADOS)

export const PeticionTiempoRealSchema = z.discriminatedUnion("operacion", [
  /** Próximas llegadas a una parada o estación, de una ruta o de todas. */
  z.object({ operacion: z.literal("llegadas"), parada: texto, ruta: texto.optional(), max: maximo.optional() }),
  /** Buses en vía de una ruta (código del catálogo o del GTFS), con su ubicación. */
  z.object({ operacion: z.literal("buses-ruta"), ruta: texto }),
  /** Siguientes paradas de un bus, por `vehicle.label` o `vehicle.id`. */
  z.object({ operacion: z.literal("proximas-paradas-bus"), bus: texto, max: maximo.optional() }),
  /** Paradas o estaciones cerca de un punto; con `conLlegadas`, las próximas llegadas de cada una. */
  z.object({ operacion: z.literal("paradas-cercanas"), ...coordenada, radio: radio.optional(), max: maximo.optional(), conLlegadas: z.boolean().optional() }),
  /** Buses a menos de `radio` metros de un punto. */
  z.object({ operacion: z.literal("buses-cercanos"), ...coordenada, radio: radio.optional(), max: maximo.optional() }),
  /** Alertas vigentes de una ruta y/o una parada; sin filtro, todas las vigentes. */
  z.object({ operacion: z.literal("alertas"), ruta: texto.optional(), parada: texto.optional() }),
  /** Búsqueda de paradas por nombre, sin importar tildes ni mayúsculas. */
  z.object({ operacion: z.literal("buscar-paradas"), consulta: texto, max: maximo.optional() }),
  /** Buses en servicio ahora por sistema. */
  z.object({ operacion: z.literal("estado-sistema") }),
  /** Salidas programadas hoy de una ruta, por hora, y su primera y última. */
  z.object({ operacion: z.literal("horario-ruta"), ruta: texto }),
  /** Viajes cancelados hoy, en total y por ruta (sin guardar historial). */
  z.object({ operacion: z.literal("cancelados-hoy"), ruta: texto.optional() }),
  /** Edad de cada feed, si se detuvo y si se sirve una copia vieja. */
  z.object({ operacion: z.literal("salud-feeds") }),
])
export type PeticionTiempoReal = z.infer<typeof PeticionTiempoRealSchema>

/** Una llegada, para el cliente. */
export const LlegadaSchema = z.object({
  rutaId: z.string(),
  codigo: z.string(),
  destino: z.string(),
  sistema: z.string(),
  paradaId: z.string(),
  paradaNombre: z.string(),
  segundos: z.number(),
  origen: z.enum(["en-vivo", "programado"]),
  bus: z.string().nullable(),
  retraso: z.number().nullable(),
  edad: z.number(),
  adicional: z.boolean(),
})

export const BusEnViaSchema = z.object({
  id: z.string(),
  etiqueta: z.string(),
  rutaId: z.string(),
  codigo: z.string(),
  destino: z.string(),
  lat: z.number(),
  lng: z.number(),
  edad: z.number(),
  anterior: z.string().nullable(),
  siguiente: z.string().nullable(),
  retraso: z.number().nullable(),
})

/** Estado de un feed concreto, para que cada fuente diga si es fiable por su cuenta. */
export const EstadoFeedSchema = z.object({
  /** Segundos desde la hora de la cabecera del feed. */
  edadS: z.number().nullable(),
  /** Cabecera con más de 300 s: esa fuente dejó de actualizar. */
  detenido: z.boolean(),
  /** Se sirve una copia anterior porque la última lectura falló. */
  copiaObsoleta: z.boolean(),
})
export type EstadoFeed = z.infer<typeof EstadoFeedSchema>

export const MetaSchema = z.object({
  /** Segundos desde la hora que dice la cabecera de `positions.pb`; `null` si no hay lectura. */
  edadDatosS: z.number().nullable(),
  /** La cabecera tiene más de 300 s: la fuente dejó de actualizar. */
  detenido: z.boolean(),
  /** Se sirve una copia anterior porque la última lectura falló. */
  copiaObsoleta: z.boolean(),
  /**
   * Retrasos y cancelados (`tripupdates`): `disponibles`, `sin-datos` (aún no hay copia) o
   * `detenido` (su cabecera tiene más de 300 s: no se usan ni para corregir ni para cancelar).
   */
  retrasos: z.enum(["disponibles", "sin-datos", "detenido"]),
  /** Fecha de publicación del GTFS estático del que salen nombres y recorridos. */
  indicePublicado: z.string(),
  /** Estado de cada feed que esta respuesta leyó (`null`: no se leyó o no hay copia). */
  feeds: z.object({ posiciones: EstadoFeedSchema.nullable(), alertas: EstadoFeedSchema.nullable(), retrasos: EstadoFeedSchema.nullable() }),
})
export type Meta = z.infer<typeof MetaSchema>

export const RespuestaLlegadasSchema = z.object({
  operacion: z.literal("llegadas"),
  meta: MetaSchema,
  parada: z.string(),
  ruta: z.string().nullable(),
  /** Sistema del servicio consultado («troncal») y otros sistemas donde el mismo código existe, que NO se mezclan. */
  sistema: z.string().nullable(),
  tambienEn: z.array(z.string()),
  /** Por qué no hay llegadas, si no las hay. */
  motivo: z.enum(["ruta-no-pasa-por-parada", "sin-buses", "feed-detenido"]).nullable(),
  llegadas: z.array(LlegadaSchema),
})
export type RespuestaLlegadas = z.infer<typeof RespuestaLlegadasSchema>

export const RespuestaBusesRutaSchema = z.object({
  operacion: z.literal("buses-ruta"),
  meta: MetaSchema,
  ruta: z.string(),
  sistema: z.string().nullable(),
  tambienEn: z.array(z.string()),
  destinos: z.array(z.string()),
  buses: z.array(BusEnViaSchema),
  sinUbicar: z.number(),
})
export type RespuestaBusesRuta = z.infer<typeof RespuestaBusesRutaSchema>

export const ParadaCercanaSchema = z.object({
  id: z.string(),
  nombre: z.string(),
  lat: z.number(),
  lng: z.number(),
  distancia: z.number(),
  llegadas: z.array(LlegadaSchema).optional(),
})
export const RespuestaParadasCercanasSchema = z.object({
  operacion: z.literal("paradas-cercanas"),
  meta: MetaSchema,
  paradas: z.array(ParadaCercanaSchema),
})
export type RespuestaParadasCercanas = z.infer<typeof RespuestaParadasCercanasSchema>
