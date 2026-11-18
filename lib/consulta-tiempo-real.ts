import { distanceMeters } from "@/lib/geo"
import { findPlaces, type TransmilenioData } from "@/lib/routes"
import { estacionesGtfsDeLugar, indiceVigente, rutasGtfsDeRuta, type IndiceGtfs, type RutaIndice } from "@/lib/gtfs-indice"
import { saludDeFeeds, type SaludFeed } from "@/lib/gtfs-rt"
import { normalize } from "@/lib/text"
import {
  type EstadoFeed,
  type Meta,
  type PeticionTiempoReal,
  type RespuestaBusesRuta,
  type RespuestaLlegadas,
  type RespuestaParadasCercanas,
} from "@/lib/contrato-tiempo-real"
import {
  alertasVigentes,
  buscarBus,
  buscarParadas,
  busesCercanos,
  busesDeRutas,
  canceladosHoy,
  cabeceraVieja,
  estadoSistema,
  horarioDeRutas,
  paradasExactas,
  llegadasEnParada,
  paradasCercanas,
  proximasParadasDeBus,
  rutaDeIndice,
  rutasPorParada,
  type AlertaVigente,
  type CanceladosHoy,
  type EstadoSistema,
  type HorarioDeRuta,
  type Instantanea,
  type ParadaDeBus,
  type ParadaEncontrada,
} from "@/lib/tiempo-real"

/**
 * Resolución de las consultas en vivo: del nombre o código que dijo la persona a
 * los ids del GTFS, y de ahí a las funciones de `lib/tiempo-real.ts`. Es la capa
 * que comparten el asistente (`lib/respuesta-tiempo-real.ts`) y `/api/tiempo-real`.
 *
 * Los códigos y los nombres salen primero del catálogo de ArcGIS (`TransmilenioData`)
 * y, si ahí no están, del índice GTFS, que cubre toda la red. Un código o una
 * parada que no se puede enlazar con claridad devuelve `null`: nada se adivina.
 */

export type Contexto = {
  data: TransmilenioData
  i: Instantanea
  /** Estado de los feeds al construir la instantánea (para `meta`). */
  salud?: SaludFeed[]
}

export type Error503 = "indice-vencido" | "feed-no-disponible"

/** Ids de GTFS de una ruta escrita como el catálogo («8 G», «B10») o como el GTFS («8-1», «166»). */
export function resolverRuta(codigo: string, { data, i }: Pick<Contexto, "data" | "i">): RutaIndice[] {
  const limpio = codigo.replace(/\s+/g, "").toUpperCase()
  const catalogada = data.routes.find((r) => r.code.replace(/\s+/g, "").toUpperCase() === limpio)
  if (catalogada) {
    const enlazadas = rutasGtfsDeRuta(catalogada, data, i.indice)
    if (enlazadas.length > 0) return enlazadas
  }
  const directas = i.indice.rutas.filter((r) => r.codigo.replace(/\s+/g, "").toUpperCase() === limpio)
  // Los códigos se repiten entre sistemas (C25 troncal y C25 de otro operador): gana el troncal o dual.
  const troncales = directas.filter((r) => r.agencia === "1" || r.agencia === "6")
  return troncales.length > 0 ? troncales : directas
}

export type ParadaResuelta = { nombre: string; ids: Set<string> }
export type ResolucionParada = { tipo: "ok"; parada: ParadaResuelta } | { tipo: "ambigua"; opciones: string[] } | { tipo: "desconocida" }

/** Paradas del mismo nombre a menos de esto una de otra son la misma estación (andenes, sentidos). */
const MISMA_ZONA_M = 1_500

/** Varias paradas del mismo nombre: una sola estación si están juntas; si no, hay que preguntar cuál. */
function unificar(lista: ParadaEncontrada[]): ResolucionParada {
  const [primera] = lista
  if (lista.every((p) => distanceMeters(primera, p) <= MISMA_ZONA_M)) return { tipo: "ok", parada: { nombre: primera.nombre, ids: new Set(lista.map((p) => p.id)) } }
  return { tipo: "ambigua", opciones: [`${primera.nombre} (hay varias con ese nombre, en distintas zonas)`] }
}

/**
 * Una estación o parada por nombre, sin adivinar:
 * 1. el nombre EXACTO de un lugar del catálogo (agrupa los andenes de una estación);
 * 2. el nombre EXACTO de una parada del GTFS («Br. El Virrey» es esa parada, no la estación «Virrey»);
 * 3. la búsqueda aproximada, solo si todo lo que encuentra es un único nombre. Si encuentra varios
 *    nombres distintos devuelve la ambigüedad con las opciones, para preguntar cuál.
 */
export function resolverParada(nombre: string, { data, i }: Pick<Contexto, "data" | "i">): ResolucionParada {
  const q = normalize(nombre)
  const [lugar] = findPlaces(nombre, data)
  if (lugar && normalize(lugar.name) === q) {
    const ids = [...estacionesGtfsDeLugar(lugar)].filter((id) => i.indice.paradas[id])
    if (ids.length > 0) return { tipo: "ok", parada: { nombre: lugar.name, ids: new Set(ids) } }
  }
  const exactas = paradasExactas(i.indice, nombre)
  if (exactas.length > 0) return unificar(exactas)
  const candidatas = buscarParadas(i.indice, nombre, 12)
  const nombres = [...new Set(candidatas.map((p) => normalize(p.nombre)))]
  if (nombres.length === 0) return { tipo: "desconocida" }
  if (nombres.length === 1) return unificar(candidatas)
  const opciones = [...new Map(candidatas.map((p) => [normalize(p.nombre), p.nombre])).values()].slice(0, 4)
  return { tipo: "ambigua", opciones }
}

/** Estado de una lectura de feed. */
const estadoDe = (lectura: { datos: { cabecera: number }; obsoleto: boolean } | null, ahoraMs: number): EstadoFeed | null =>
  lectura && {
    edadS: Math.max(0, Math.round(ahoraMs / 1000 - lectura.datos.cabecera)),
    detenido: cabeceraVieja(lectura.datos.cabecera, ahoraMs),
    copiaObsoleta: lectura.obsoleto,
  }

/**
 * `meta` de una respuesta: la edad y el estado de CADA feed leído. `edadDatosS` y `detenido` son los del
 * feed principal de la consulta (posiciones, si no avisos, si no retrasos); `copiaObsoleta` es verdadero si
 * cualquiera de los leídos es una copia anterior; `retrasos` dice por separado si `tripupdates` sirve.
 */
export function metaDe({ i }: Pick<Contexto, "i" | "salud">): Meta {
  const feeds = { posiciones: estadoDe(i.posiciones, i.ahora), alertas: estadoDe(i.alertas, i.ahora), retrasos: estadoDe(i.retrasos, i.ahora) }
  const principal = feeds.posiciones ?? feeds.alertas ?? feeds.retrasos
  return {
    edadDatosS: principal?.edadS ?? null,
    detenido: principal?.detenido ?? false,
    copiaObsoleta: Object.values(feeds).some((f) => f?.copiaObsoleta),
    retrasos: !feeds.retrasos ? "sin-datos" : feeds.retrasos.detenido ? "detenido" : "disponibles",
    indicePublicado: i.indice.publicado,
    feeds,
  }
}

type Falla = { ok: false; estado: 400 | 404 | 409 | 503; error: string; opciones?: string[] }
export type Resultado<T> = ({ ok: true } & T) | Falla
const falla = (estado: Falla["estado"], error: string, opciones?: string[]): Falla => ({ ok: false, estado, error, ...(opciones ? { opciones } : {}) })
/** Falla de una resolución de parada que no dio `ok`. */
const fallaDeParada = (r: Exclude<ResolucionParada, { tipo: "ok" }>): Falla => (r.tipo === "ambigua" ? falla(409, "parada-ambigua", r.opciones) : falla(404, "parada-desconocida"))

export function consultarLlegadas(ctx: Contexto, { parada, ruta, max = 6 }: { parada: string; ruta?: string; max?: number }): Resultado<RespuestaLlegadas> {
  const resolucion = resolverParada(parada, ctx)
  if (resolucion.tipo !== "ok") return fallaDeParada(resolucion)
  const lugar = resolucion.parada
  const rutas = ruta ? resolverRuta(ruta, ctx) : undefined
  if (ruta && rutas!.length === 0) return falla(404, "ruta-desconocida")
  const meta = metaDe(ctx)
  const base = { ok: true as const, operacion: "llegadas" as const, meta, parada: lugar.nombre, ruta: ruta ?? null }
  if (rutas && rutasPorParada(ctx.i.indice, lugar.ids, rutas.map((r) => r.id)).length === 0) return { ...base, motivo: "ruta-no-pasa-por-parada", llegadas: [] }
  if (meta.detenido) return { ...base, motivo: "feed-detenido", llegadas: [] }
  const llegadas = llegadasEnParada(ctx.i, { paradas: lugar.ids, rutas: rutas?.map((r) => r.id), max })
  return { ...base, motivo: llegadas.length === 0 ? "sin-buses" : null, llegadas }
}

export function consultarBusesRuta(ctx: Contexto, { ruta }: { ruta: string }): Resultado<RespuestaBusesRuta> {
  const rutas = resolverRuta(ruta, ctx)
  if (rutas.length === 0) return falla(404, "ruta-desconocida")
  const { buses, sinUbicar } = busesDeRutas(ctx.i, rutas.map((r) => r.id))
  return { ok: true, operacion: "buses-ruta", meta: metaDe(ctx), ruta, destinos: [...new Set(rutas.map((r) => r.destino))], buses, sinUbicar }
}

export function consultarProximasParadasBus(ctx: Contexto, { bus, max = 5 }: { bus: string; max?: number }): Resultado<{ operacion: "proximas-paradas-bus"; meta: Meta; bus: { id: string; etiqueta: string; codigo: string; destino: string; edad: number }; paradas: ParadaDeBus[] }> {
  const encontrado = buscarBus(ctx.i, bus)
  if (!encontrado) return falla(404, "bus-desconocido")
  const paradas = proximasParadasDeBus(ctx.i, encontrado, max)
  if (!paradas) return falla(404, "bus-sin-ubicar")
  const ruta = rutaDeIndice(ctx.i.indice, encontrado.rutaId)
  return {
    ok: true,
    operacion: "proximas-paradas-bus",
    meta: metaDe(ctx),
    bus: { id: encontrado.id, etiqueta: encontrado.etiqueta, codigo: ruta?.codigo ?? "", destino: ruta?.destino ?? "", edad: Math.max(0, Math.round(ctx.i.ahora / 1000 - encontrado.ts)) },
    paradas,
  }
}

export function consultarParadasCercanas(ctx: Contexto, { lat, lng, radio, max = 3, conLlegadas }: { lat: number; lng: number; radio?: number; max?: number; conLlegadas?: boolean }): RespuestaParadasCercanas & { ok: true } {
  const paradas = paradasCercanas(ctx.i.indice, { lat, lng }, { radioM: radio, max })
  return {
    ok: true,
    operacion: "paradas-cercanas",
    meta: metaDe(ctx),
    paradas: paradas.map((p) => (conLlegadas && !metaDe(ctx).detenido ? { ...p, llegadas: llegadasEnParada(ctx.i, { paradas: new Set([p.id]), max: 3 }) } : p)),
  }
}

export function consultarAlertas(ctx: Contexto, { ruta, parada }: { ruta?: string; parada?: string }): Resultado<{ operacion: "alertas"; meta: Meta; parada: string | null; alertas: (Omit<AlertaVigente, "rutas" | "paradas"> & { rutas: string[] })[] }> {
  const rutas = ruta ? resolverRuta(ruta, ctx) : undefined
  if (ruta && rutas!.length === 0) return falla(404, "ruta-desconocida")
  const resolucion = parada ? resolverParada(parada, ctx) : undefined
  if (resolucion && resolucion.tipo !== "ok") return fallaDeParada(resolucion)
  const lugar = resolucion?.parada
  const vigentes = alertasVigentes(ctx.i, { rutas: rutas?.map((r) => r.id), paradas: lugar?.ids })
  return {
    ok: true,
    operacion: "alertas",
    meta: metaDe(ctx),
    parada: lugar?.nombre ?? null,
    alertas: vigentes.map(({ paradas: _paradas, rutas: ids, ...resto }) => ({ ...resto, rutas: [...new Set(ids.map((id) => rutaDeIndice(ctx.i.indice, id)?.codigo ?? id))] })),
  }
}

export type CuerpoTiempoReal =
  | (RespuestaLlegadas)
  | (RespuestaBusesRuta)
  | (RespuestaParadasCercanas)
  | { operacion: "proximas-paradas-bus"; meta: Meta; bus: unknown; paradas: ParadaDeBus[] }
  | { operacion: "buses-cercanos"; meta: Meta; buses: unknown[] }
  | { operacion: "alertas"; meta: Meta; parada: string | null; alertas: unknown[] }
  | { operacion: "buscar-paradas"; meta: Meta; paradas: ParadaEncontrada[] }
  | { operacion: "estado-sistema"; meta: Meta; sistema: EstadoSistema }
  | { operacion: "horario-ruta"; meta: Meta; horarios: HorarioDeRuta[] }
  | { operacion: "cancelados-hoy"; meta: Meta; cancelados: CanceladosHoy | null }
  | { operacion: "salud-feeds"; meta: Meta; feeds: SaludFeed[] }

const sinOk = <T extends { ok: true }>(r: T): Omit<T, "ok"> => {
  const { ok: _ok, ...resto } = r
  return resto
}

/** Ejecuta una petición validada. El índice vencido bloquea todo lo que usa nombres y recorridos. */
export function ejecutarConsulta(ctx: Contexto, p: PeticionTiempoReal): { estado: 200; cuerpo: CuerpoTiempoReal } | { estado: Falla["estado"]; cuerpo: { error: string; opciones?: string[] } } {
  const vencida = (e: Falla) => ({ estado: e.estado, cuerpo: { error: e.error, ...(e.opciones ? { opciones: e.opciones } : {}) } })
  if (p.operacion === "salud-feeds") return { estado: 200, cuerpo: { operacion: "salud-feeds", meta: metaDe(ctx), feeds: ctx.salud ?? saludDeFeeds() } }
  if (!indiceVigente(ctx.i.indice, new Date(ctx.i.ahora))) return { estado: 503, cuerpo: { error: "indice-vencido" } }
  const listo = <T extends { ok: true }>(r: Resultado<T>) => (r.ok ? { estado: 200 as const, cuerpo: sinOk(r) as unknown as CuerpoTiempoReal } : vencida(r))
  const meta = metaDe(ctx)
  switch (p.operacion) {
    case "llegadas":
      return listo(consultarLlegadas(ctx, p))
    case "buses-ruta":
      return listo(consultarBusesRuta(ctx, p))
    case "proximas-paradas-bus":
      return listo(consultarProximasParadasBus(ctx, p))
    case "paradas-cercanas":
      return listo(consultarParadasCercanas(ctx, p))
    case "alertas":
      return listo(consultarAlertas(ctx, p))
    case "buses-cercanos":
      return { estado: 200, cuerpo: { operacion: "buses-cercanos", meta, buses: busesCercanos(ctx.i, p, { radioM: p.radio, max: p.max }) } }
    case "buscar-paradas":
      return { estado: 200, cuerpo: { operacion: "buscar-paradas", meta, paradas: buscarParadas(ctx.i.indice, p.consulta, p.max) } }
    case "estado-sistema":
      return { estado: 200, cuerpo: { operacion: "estado-sistema", meta, sistema: estadoSistema(ctx.i) } }
    case "horario-ruta": {
      const rutas = resolverRuta(p.ruta, ctx)
      if (rutas.length === 0) return { estado: 404, cuerpo: { error: "ruta-desconocida" } }
      return { estado: 200, cuerpo: { operacion: "horario-ruta", meta, horarios: horarioDeRutas(ctx.i.indice, rutas.map((r) => r.id), ctx.i.ahora) } }
    }
    case "cancelados-hoy": {
      const rutas = p.ruta ? resolverRuta(p.ruta, ctx) : undefined
      if (p.ruta && rutas!.length === 0) return { estado: 404, cuerpo: { error: "ruta-desconocida" } }
      return { estado: 200, cuerpo: { operacion: "cancelados-hoy", meta, cancelados: canceladosHoy(ctx.i, rutas?.map((r) => r.id)) } }
    }
  }
}

export type { IndiceGtfs }
