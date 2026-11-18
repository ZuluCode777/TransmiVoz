import { SISTEMAS_PEDIBLES } from "@/lib/contrato-tiempo-real"
import { distanceMeters } from "@/lib/geo"
import { findPlaces, type TransmilenioData } from "@/lib/routes"
import { AGENCIAS_DEL_CATALOGO, SISTEMAS, estacionesGtfsDeLugar, indiceVigente, rutasGtfsDeRuta, type IndiceGtfs, type RutaIndice } from "@/lib/gtfs-indice"
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

export type RutaResuelta =
  | { tipo: "ok"; rutas: RutaIndice[]; sistema: string; tambienEn: string[] }
  | { tipo: "ambigua"; opciones: string[] }
  | { tipo: "desconocida" }

const sistemaDe = (r: RutaIndice) => SISTEMAS[r.agencia] ?? "otro"
const claveDeCodigo = (codigo: string) => codigo.replace(/\s+/g, "").toUpperCase()

const SUFIJO_DE_SISTEMA = /^(.*?)[\s(]*\b(troncal|dual|alimentadora?|zonal(?: urbano| complementario| especial)?|urbano|complementario|especial|transmicable|cable)\b[\s)]*$/i

/**
 * Ids de GTFS de una ruta escrita como el catálogo («8 G», «B10») o como el GTFS («8-1», «166»), dentro de UN
 * sistema. Se puede pedir el sistema con la frase («C25 zonal», «C25 (zonal urbano)»), con el parámetro
 * `sistema` o con el `route_id` («12756»). Sin pedirlo: un código del catálogo se enlaza solo con troncales y
 * duales; uno que no es del catálogo y existe en varios sistemas se resuelve al troncal/dual si lo hay —y se dice
 * que existe también en los otros (`tambienEn`)— y, si no, se pregunta. Los sistemas nunca se mezclan.
 */
export function resolverRuta(codigo: string, { data, i }: Pick<Contexto, "data" | "i">, sistemaPedido?: string): RutaResuelta {
  const pedido = SUFIJO_DE_SISTEMA.exec(codigo.trim())
  const sinSistema = (pedido ? pedido[1] : codigo).trim()
  const sistema = sistemaPedido ?? pedido?.[2]
  const agencias = sistema ? SISTEMAS_PEDIBLES[sistema.toLowerCase()] : undefined
  if (sistema && !agencias) return { tipo: "desconocida" }

  const limpio = claveDeCodigo(sinSistema)
  const delMismoCodigo = i.indice.rutas.filter((r) => claveDeCodigo(r.codigo) === limpio)
  const resolver = (rutas: RutaIndice[]): RutaResuelta => {
    const sistemaResuelto = sistemaDe(rutas[0])
    // Los otros sistemas donde existe el mismo código (también cuando se pidió por `route_id`).
    const mismos = i.indice.rutas.filter((r) => r.codigo === rutas[0].codigo)
    const tambienEn = [...new Set(mismos.map(sistemaDe).filter((s) => s !== sistemaResuelto && !rutas.some((r) => sistemaDe(r) === s)))]
    return { tipo: "ok", rutas, sistema: sistemaResuelto, tambienEn }
  }
  const preguntar = (rutas: RutaIndice[]): RutaResuelta => ({ tipo: "ambigua", opciones: [...new Set(rutas.map(sistemaDe))].map((s) => `${sinSistema} (${s})`) })

  // Un `route_id` del GTFS (4 a 6 cifras) es una ruta concreta, de su sistema.
  const porId = /^\d{4,6}$/.test(sinSistema) ? rutaDeIndice(i.indice, sinSistema) : undefined
  if (porId) return !agencias || agencias.includes(porId.agencia) ? resolver([porId]) : { tipo: "desconocida" }

  if (agencias) {
    const delSistema = delMismoCodigo.filter((r) => agencias.includes(r.agencia))
    if (delSistema.length === 0) return { tipo: "desconocida" }
    const catalogada = data.routes.find((r) => claveDeCodigo(r.code) === limpio)
    if (catalogada && delSistema.every((r) => AGENCIAS_DEL_CATALOGO.has(r.agencia))) {
      const enlazadas = rutasGtfsDeRuta(catalogada, data, i.indice).filter((r) => agencias.includes(r.agencia))
      if (enlazadas.length > 0) return resolver(enlazadas)
    }
    return new Set(delSistema.map(sistemaDe)).size > 1 ? preguntar(delSistema) : resolver(delSistema)
  }

  const catalogada = data.routes.find((r) => claveDeCodigo(r.code) === limpio)
  if (catalogada) {
    const enlazadas = rutasGtfsDeRuta(catalogada, data, i.indice)
    if (enlazadas.length > 0) return resolver(enlazadas)
  }
  if (delMismoCodigo.length === 0) return { tipo: "desconocida" }
  const sistemas = new Set(delMismoCodigo.map(sistemaDe))
  if (sistemas.size === 1) return resolver(delMismoCodigo)
  const delCatalogo = delMismoCodigo.filter((r) => AGENCIAS_DEL_CATALOGO.has(r.agencia))
  if (delCatalogo.length > 0 && new Set(delCatalogo.map(sistemaDe)).size === 1) return resolver(delCatalogo)
  return preguntar(delMismoCodigo)
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
const fallaDeRuta = (r: Exclude<RutaResuelta, { tipo: "ok" }>): Falla => (r.tipo === "ambigua" ? falla(409, "ruta-ambigua", r.opciones) : falla(404, "ruta-desconocida"))
const fallaDeParada = (r: Exclude<ResolucionParada, { tipo: "ok" }>): Falla => (r.tipo === "ambigua" ? falla(409, "parada-ambigua", r.opciones) : falla(404, "parada-desconocida"))

export function consultarLlegadas(ctx: Contexto, { parada, ruta, sistema, max = 6 }: { parada: string; ruta?: string; sistema?: string; max?: number }): Resultado<RespuestaLlegadas> {
  const resolucion = resolverParada(parada, ctx)
  if (resolucion.tipo !== "ok") return fallaDeParada(resolucion)
  const lugar = resolucion.parada
  const resRuta = ruta ? resolverRuta(ruta, ctx, sistema) : undefined
  if (resRuta && resRuta.tipo !== "ok") return fallaDeRuta(resRuta)
  const rutas = resRuta?.rutas
  const meta = metaDe(ctx)
  const base = { ok: true as const, operacion: "llegadas" as const, meta, parada: lugar.nombre, ruta: ruta ?? null, sistema: resRuta?.sistema ?? null, tambienEn: resRuta?.tambienEn ?? [] }
  if (rutas && rutasPorParada(ctx.i.indice, lugar.ids, rutas.map((r) => r.id)).length === 0) return { ...base, motivo: "ruta-no-pasa-por-parada", llegadas: [] }
  if (meta.detenido) return { ...base, motivo: "feed-detenido", llegadas: [] }
  const llegadas = llegadasEnParada(ctx.i, { paradas: lugar.ids, rutas: rutas?.map((r) => r.id), max })
  return { ...base, motivo: llegadas.length === 0 ? "sin-buses" : null, llegadas }
}

export function consultarBusesRuta(ctx: Contexto, { ruta, sistema }: { ruta: string; sistema?: string }): Resultado<RespuestaBusesRuta> {
  const res = resolverRuta(ruta, ctx, sistema)
  if (res.tipo !== "ok") return fallaDeRuta(res)
  const rutas = res.rutas
  const { buses, sinUbicar } = busesDeRutas(ctx.i, rutas.map((r) => r.id))
  return { ok: true, operacion: "buses-ruta", meta: metaDe(ctx), ruta, sistema: res.sistema, tambienEn: res.tambienEn, destinos: [...new Set(rutas.map((r) => r.destino))], buses, sinUbicar }
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

export function consultarAlertas(ctx: Contexto, { ruta, sistema, parada }: { ruta?: string; sistema?: string; parada?: string }): Resultado<{ operacion: "alertas"; meta: Meta; parada: string | null; sistema: string | null; tambienEn: string[]; alertas: (Omit<AlertaVigente, "rutas" | "paradas"> & { rutas: string[] })[] }> {
  const resRuta = ruta ? resolverRuta(ruta, ctx, sistema) : undefined
  if (resRuta && resRuta.tipo !== "ok") return fallaDeRuta(resRuta)
  const rutas = resRuta?.rutas
  const resolucion = parada ? resolverParada(parada, ctx) : undefined
  if (resolucion && resolucion.tipo !== "ok") return fallaDeParada(resolucion)
  const lugar = resolucion?.parada
  const vigentes = alertasVigentes(ctx.i, { rutas: rutas?.map((r) => r.id), paradas: lugar?.ids })
  return {
    ok: true,
    operacion: "alertas",
    meta: metaDe(ctx),
    parada: lugar?.nombre ?? null,
    sistema: resRuta?.sistema ?? null,
    tambienEn: resRuta?.tambienEn ?? [],
    alertas: vigentes.map(({ paradas: _paradas, rutas: ids, ...resto }) => ({ ...resto, rutas: [...new Set(ids.map((id) => rutaDeIndice(ctx.i.indice, id)?.codigo ?? id))] })),
  }
}

export type CuerpoTiempoReal =
  | (RespuestaLlegadas)
  | (RespuestaBusesRuta)
  | (RespuestaParadasCercanas)
  | { operacion: "proximas-paradas-bus"; meta: Meta; bus: unknown; paradas: ParadaDeBus[] }
  | { operacion: "buses-cercanos"; meta: Meta; buses: unknown[] }
  | { operacion: "alertas"; meta: Meta; parada: string | null; sistema: string | null; tambienEn: string[]; alertas: unknown[] }
  | { operacion: "buscar-paradas"; meta: Meta; paradas: ParadaEncontrada[] }
  | { operacion: "estado-sistema"; meta: Meta; sistema: EstadoSistema }
  | { operacion: "horario-ruta"; meta: Meta; sistema: string; tambienEn: string[]; horarios: HorarioDeRuta[] }
  | { operacion: "cancelados-hoy"; meta: Meta; sistema: string | null; tambienEn: string[]; cancelados: CanceladosHoy | null }
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
      const res = resolverRuta(p.ruta, ctx, p.sistema)
      if (res.tipo !== "ok") return vencida(fallaDeRuta(res))
      return { estado: 200, cuerpo: { operacion: "horario-ruta", meta, sistema: res.sistema, tambienEn: res.tambienEn, horarios: horarioDeRutas(ctx.i.indice, res.rutas.map((r) => r.id), ctx.i.ahora) } }
    }
    case "cancelados-hoy": {
      const res = p.ruta ? resolverRuta(p.ruta, ctx, p.sistema) : undefined
      if (res && res.tipo !== "ok") return vencida(fallaDeRuta(res))
      return { estado: 200, cuerpo: { operacion: "cancelados-hoy", meta, sistema: res?.sistema ?? null, tambienEn: res?.tambienEn ?? [], cancelados: canceladosHoy(ctx.i, res?.rutas.map((r) => r.id)) } }
    }
  }
}

export type { IndiceGtfs }
