import { diaSemanaDeFecha, fechaCivilEnZona, instanteLocal } from "@/lib/evidencia"
import { distanceMeters } from "@/lib/geo"
import { FEED_DETENIDO_S, RETRASO_VIEJO_S, VEHICULO_VIEJO_S, type AlertaRt, type Alertas, type Lectura, type Posiciones, type Retrasos, type Vehiculo, type ViajeRt } from "@/lib/gtfs-rt"
import type { IndiceGtfs, RutaIndice } from "@/lib/gtfs-indice"
import { normalize } from "@/lib/text"

/**
 * Cálculos puros sobre los feeds en vivo y el índice estático: sin red, sin
 * reloj propio (todo recibe `ahora`) y sin texto hablado, para probarlos con
 * muestras reales y para que los usen igual el asistente y `/api/tiempo-real`.
 *
 * Medido el 17/11/2026 contra el feed en vivo: el `stop_id` y el
 * `current_stop_sequence` de `positions.pb` NO corresponden a la posición del
 * bus (mediana de 6 km entre la parada que dicen y el bus; solo 23 % de los
 * `stop_id` pertenecen al patrón de su `route_id`), mientras que la latitud y
 * longitud sí caen sobre el trazado de su ruta (mediana de 3 m). Por eso el bus
 * se ubica por geometría sobre las paradas de su patrón y las llegadas se
 * estiman con los tiempos programados entre paradas. Idea tomada de
 * PRestrepo2312/transmilenio-mcp (MIT), reescrita aquí.
 */

/** Más lejos que esto de la línea de paradas de su ruta, un bus no se puede ubicar. */
export const DISTANCIA_MAXIMA_AL_TRAZADO_M = 400
/** Un bus que ya pasó la parada hace menos de esto aún se dice «ahora». */
const TOLERANCIA_PASO_S = 30
/** Las salidas programadas que se añaden a las llegadas en vivo no pasan de esta ventana. */
export const HORIZONTE_PROGRAMADO_S = 3600

export const SISTEMAS: Record<string, string> = {
  "1": "troncal",
  "2": "alimentador",
  "3": "zonal urbano",
  "4": "zonal complementario",
  "5": "zonal especial",
  "6": "dual",
  "7": "TransMiCable",
}

export type Instantanea = {
  /** Instante de la consulta, en ms. */
  ahora: number
  indice: IndiceGtfs
  posiciones: Lectura<Posiciones> | null
  alertas: Lectura<Alertas> | null
  /** Última copia buena de `tripupdates.pb`; `null` si aún no hay. */
  retrasos: Lectura<Retrasos> | null
}

const ahoraS = (i: Instantanea) => i.ahora / 1000

/** ¿Está detenida la fuente? Cabecera con más de `FEED_DETENIDO_S`. */
export const cabeceraVieja = (cabecera: number, ahoraMs: number) => ahoraMs / 1000 - cabecera > FEED_DETENIDO_S

// --- Patrones y proyección -------------------------------------------------

type PuntoPatron = { id: string; lat: number; lng: number; off: number }
const patrones = new WeakMap<RutaIndice, PuntoPatron[]>()

/** Paradas del patrón de referencia de una ruta, con coordenadas y segundos programados. */
export function patronDe(indice: IndiceGtfs, ruta: RutaIndice): PuntoPatron[] {
  let patron = patrones.get(ruta)
  if (!patron) {
    patron = ruta.paradas.flatMap(([id, off]) => {
      const p = indice.paradas[id]
      return p ? [{ id, lat: p[2], lng: p[3], off }] : []
    })
    patrones.set(ruta, patron)
  }
  return patron
}

export type Ubicacion = {
  /** Segundos programados desde la primera parada hasta donde está el bus. */
  off: number
  /** Índice de la parada anterior (ya pasada) en el patrón. */
  anterior: number
  /** Metros del bus a la línea de paradas. */
  distancia: number
}

/** Ubica un punto sobre la línea que une las paradas del patrón; `null` si queda demasiado lejos. */
export function proyectar(patron: PuntoPatron[], lat: number, lng: number): Ubicacion | null {
  if (patron.length < 2) return null
  const kx = Math.cos((lat * Math.PI) / 180) * 111_320
  const ky = 110_574
  let mejor: Ubicacion | null = null
  for (let i = 0; i < patron.length - 1; i++) {
    const ax = (patron[i].lng - lng) * kx
    const ay = (patron[i].lat - lat) * ky
    const vx = (patron[i + 1].lng - patron[i].lng) * kx
    const vy = (patron[i + 1].lat - patron[i].lat) * ky
    const largo = vx * vx + vy * vy
    const t = largo === 0 ? 0 : Math.max(0, Math.min(1, -(ax * vx + ay * vy) / largo))
    const distancia = Math.hypot(ax + t * vx, ay + t * vy)
    if (!mejor || distancia < mejor.distancia) {
      mejor = { off: patron[i].off + t * (patron[i + 1].off - patron[i].off), anterior: i, distancia }
    }
  }
  return mejor && mejor.distancia <= DISTANCIA_MAXIMA_AL_TRAZADO_M ? mejor : null
}

// --- Buses frescos -----------------------------------------------------------

/** Buses cuyo propio reporte tiene menos de `VEHICULO_VIEJO_S`; ninguno si el feed está detenido. */
export function busesVigentes(i: Instantanea): Vehiculo[] {
  if (!i.posiciones || cabeceraVieja(i.posiciones.datos.cabecera, i.ahora)) return []
  return i.posiciones.datos.vehiculos.filter((v) => ahoraS(i) - v.ts <= VEHICULO_VIEJO_S)
}

export function rutaDeIndice(indice: IndiceGtfs, rutaId: string): RutaIndice | undefined {
  return rutaPorId(indice).get(rutaId)
}
const porId = new WeakMap<IndiceGtfs, Map<string, RutaIndice>>()
function rutaPorId(indice: IndiceGtfs): Map<string, RutaIndice> {
  let mapa = porId.get(indice)
  if (!mapa) porId.set(indice, (mapa = new Map(indice.rutas.map((r) => [r.id, r]))))
  return mapa
}

/** Texto de la dirección de una ruta: «hacia X», o «entre X y Y» en las zonales que traen los dos extremos. */
export function textoDestino(destino: string): string {
  const [a, b] = destino.split("||").map((x) => x.trim())
  return b ? `entre ${a} y ${b}` : `hacia ${a}`
}

// --- Retraso ------------------------------------------------------------------

/**
 * Retraso reportado de un bus, en segundos. Primero por el `trip_id` exacto (casi
 * nunca coincide entre feeds); si no, el viaje más reciente del mismo bus y la misma
 * ruta, siempre que su dato no tenga más de `RETRASO_VIEJO_S`. Un viaje cancelado
 * no cuenta. `null` si no hay dato fiable.
 */
export function retrasoDeBus(retrasos: Retrasos | undefined, bus: Vehiculo, ahoraSeg: number): number | null {
  if (!retrasos) return null
  const exacto = retrasos.porViaje.get(bus.tripId)
  if (exacto && exacto.rel !== "CANCELED" && exacto.retraso !== null) return exacto.retraso
  const propios = retrasos.porVehiculo.get(bus.id)?.filter((v) => v.rel !== "CANCELED" && v.retraso !== null && v.rutaId === bus.rutaId && ahoraSeg - v.ts <= RETRASO_VIEJO_S)
  if (!propios?.length) return null
  return propios.reduce((a, b) => (b.ts > a.ts ? b : a)).retraso
}

/** ¿El viaje del bus está cancelado según `tripupdates.pb`? Solo se sabe cuando el `trip_id` coincide. */
const viajeCancelado = (retrasos: Retrasos | undefined, bus: Vehiculo) => retrasos?.porViaje.get(bus.tripId)?.rel === "CANCELED"

const viajesPorRuta = new WeakMap<Retrasos, Map<string, ViajeRt[]>>()
/** Viajes de `tripupdates` de una ruta (se indexan la primera vez que se piden). */
function viajesDeRuta(retrasos: Retrasos, rutaId: string): ViajeRt[] {
  let mapa = viajesPorRuta.get(retrasos)
  if (!mapa) {
    mapa = new Map()
    for (const v of retrasos.porViaje.values()) {
      const lista = mapa.get(v.rutaId)
      if (lista) lista.push(v)
      else mapa.set(v.rutaId, [v])
    }
    viajesPorRuta.set(retrasos, mapa)
  }
  return mapa.get(rutaId) ?? []
}

// --- Llegadas a una parada -----------------------------------------------------

export type Llegada = {
  rutaId: string
  codigo: string
  destino: string
  sistema: string
  paradaId: string
  paradaNombre: string
  /** Segundos hasta la llegada, ya descontada la edad del dato. */
  segundos: number
  /** `en-vivo`: bus ubicado por su posición. `programado`: salida aún no iniciada, con su retraso reportado. */
  origen: "en-vivo" | "programado"
  /** Etiqueta del bus (`Z32-7046`), si se conoce. */
  bus: string | null
  /** Retraso reportado en segundos (negativo: adelantado); `null` si no hay dato. */
  retraso: number | null
  /** Segundos desde el reporte del bus; 0 en las programadas. */
  edad: number
  /** ¿Es un viaje añadido (`ADDED`) y no del horario base? */
  adicional: boolean
}

export type OpcionesLlegadas = {
  /** `stop_id` o ids de estación que forman la parada consultada. */
  paradas: ReadonlySet<string>
  /** Si se da, solo estas rutas (`route_id`). */
  rutas?: readonly string[]
  max?: number
}

/** Rutas (patrones) que pasan por una parada o estación; si se dan `rutas`, solo entre ellas. */
export function rutasPorParada(indice: IndiceGtfs, paradas: ReadonlySet<string>, rutas?: readonly string[]): RutaIndice[] {
  const candidatas = rutas ? rutas.flatMap((id) => rutaDeIndice(indice, id) ?? []) : indice.rutas
  return candidatas.filter((r) => patronDe(indice, r).some((p) => coincide(indice, p.id, paradas)))
}

/** Nombre para decir en voz alta: el de la estación madre si la hay (los andenes se llaman «Calle 85 B - 4 ó 6»). */
export function nombreParada(indice: IndiceGtfs, stopId: string): string {
  const parada = indice.paradas[stopId]
  const madre = parada?.[1] ? indice.paradas[parada[1]] : undefined
  return madre?.[0] ?? parada?.[0] ?? stopId
}

const coincide = (indice: IndiceGtfs, stopId: string, ids: ReadonlySet<string>) => ids.has(stopId) || ids.has(indice.paradas[stopId]?.[1] ?? "\0")

/**
 * Próximas llegadas a una parada o estación, de una ruta o de todas.
 *
 * - En vivo: cada bus ubicado antes de la parada en el patrón de su ruta llega en
 *   `desfase(parada) − desfase(bus) − edad del reporte` segundos programados. Los
 *   buses de un viaje cancelado se descartan. El retraso reportado se muestra.
 * - Programadas: los viajes que aún no salieron (`inicio` futuro) de `tripupdates`,
 *   ya corregidos con su retraso (`inicio + desfase + retraso`); incluyen los
 *   añadidos (`ADDED`) y excluyen los cancelados. Un viaje de un bus que ya está
 *   en vivo en esa ruta y llega casi a la misma hora no se cuenta dos veces.
 */
export function llegadasEnParada(i: Instantanea, { paradas, rutas, max = 6 }: OpcionesLlegadas): Llegada[] {
  const { indice } = i
  const ahora = ahoraS(i)
  const buses = busesVigentes(i)
  const retrasos = i.retrasos?.datos
  const candidatas = rutas ? rutas.flatMap((id) => rutaDeIndice(indice, id) ?? []) : indice.rutas
  const salida: Llegada[] = []
  for (const ruta of candidatas) {
    const patron = patronDe(indice, ruta)
    const objetivo = patron.findIndex((p) => coincide(indice, p.id, paradas))
    if (objetivo < 0) continue
    const parada = patron[objetivo]
    const nombre = nombreParada(indice, parada.id)
    const base = { rutaId: ruta.id, codigo: ruta.codigo, destino: ruta.destino, sistema: SISTEMAS[ruta.agencia] ?? "otro", paradaId: parada.id, paradaNombre: nombre }
    const enVivo: Llegada[] = []
    for (const bus of buses) {
      if (bus.rutaId !== ruta.id || viajeCancelado(retrasos, bus)) continue
      const u = proyectar(patron, bus.lat, bus.lng)
      if (!u) continue
      const edad = Math.max(0, Math.round(ahora - bus.ts))
      const segundos = parada.off - u.off - edad
      if (segundos < -TOLERANCIA_PASO_S) continue
      enVivo.push({ ...base, segundos: Math.max(0, Math.round(segundos)), origen: "en-vivo", bus: bus.etiqueta || null, retraso: retrasoDeBus(retrasos, bus, ahora), edad, adicional: retrasos?.porViaje.get(bus.tripId)?.rel === "ADDED" })
    }
    salida.push(...enVivo)
    if (!retrasos) continue
    const idsEnVivo = new Set(buses.filter((b) => b.rutaId === ruta.id).map((b) => b.id))
    for (const viaje of viajesDeRuta(retrasos, ruta.id)) {
      if (viaje.rel === "CANCELED" || viaje.inicio <= ahora) continue
      const llegada = viaje.inicio + parada.off + (viaje.retraso ?? 0) - ahora
      if (llegada < 0 || llegada > HORIZONTE_PROGRAMADO_S) continue
      if (viaje.vehiculoId && idsEnVivo.has(viaje.vehiculoId) && enVivo.some((v) => Math.abs(v.segundos - llegada) < 300)) continue
      salida.push({ ...base, segundos: Math.round(llegada), origen: "programado", bus: null, retraso: viaje.retraso, edad: 0, adicional: viaje.rel === "ADDED" })
    }
  }
  return salida.sort((a, b) => a.segundos - b.segundos).slice(0, max)
}

// --- Buses de una ruta -----------------------------------------------------------

export type BusEnVia = {
  id: string
  etiqueta: string
  rutaId: string
  codigo: string
  destino: string
  lat: number
  lng: number
  edad: number
  /** Parada que acaba de pasar y la siguiente, por geometría; `null` si no se pudo ubicar. */
  anterior: string | null
  siguiente: string | null
  retraso: number | null
}

function ubicarBus(i: Instantanea, bus: Vehiculo, ruta: RutaIndice | undefined): BusEnVia {
  const base: BusEnVia = {
    id: bus.id,
    etiqueta: bus.etiqueta,
    rutaId: bus.rutaId,
    codigo: ruta?.codigo ?? "",
    destino: ruta?.destino ?? "",
    lat: bus.lat,
    lng: bus.lng,
    edad: Math.max(0, Math.round(ahoraS(i) - bus.ts)),
    anterior: null,
    siguiente: null,
    retraso: retrasoDeBus(i.retrasos?.datos, bus, ahoraS(i)),
  }
  if (!ruta) return base
  const patron = patronDe(i.indice, ruta)
  const u = proyectar(patron, bus.lat, bus.lng)
  if (!u) return base
  const nombre = (idx: number) => nombreParada(i.indice, patron[idx].id)
  return { ...base, anterior: nombre(u.anterior), siguiente: nombre(Math.min(u.anterior + 1, patron.length - 1)) }
}

/** Buses en vía de unas rutas, con su ubicación entre paradas. */
export function busesDeRutas(i: Instantanea, rutas: readonly string[]): { buses: BusEnVia[]; sinUbicar: number } {
  const ids = new Set(rutas)
  const buses = busesVigentes(i)
    .filter((b) => ids.has(b.rutaId))
    .map((b) => ubicarBus(i, b, rutaDeIndice(i.indice, b.rutaId)))
  return { buses, sinUbicar: buses.filter((b) => b.siguiente === null).length }
}

// --- Próximas paradas de un bus ---------------------------------------------------

export type ParadaDeBus = { id: string; nombre: string; segundos: number }

/** Busca un bus por `vehicle.label` (sin importar mayúsculas ni guiones) o por `vehicle.id`. */
export function buscarBus(i: Instantanea, referencia: string): Vehiculo | undefined {
  const clave = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "")
  const buscada = clave(referencia)
  if (!buscada) return undefined
  return busesVigentes(i).find((b) => clave(b.etiqueta) === buscada || b.id === referencia.trim())
}

/** Las siguientes `max` paradas de un bus con los segundos estimados hasta cada una. */
export function proximasParadasDeBus(i: Instantanea, bus: Vehiculo, max = 5): ParadaDeBus[] | null {
  const ruta = rutaDeIndice(i.indice, bus.rutaId)
  if (!ruta) return null
  const patron = patronDe(i.indice, ruta)
  const u = proyectar(patron, bus.lat, bus.lng)
  if (!u) return null
  const edad = Math.max(0, Math.round(ahoraS(i) - bus.ts))
  return patron
    .slice(u.anterior + 1)
    .map((p) => ({ id: p.id, nombre: nombreParada(i.indice, p.id), segundos: Math.max(0, Math.round(p.off - u.off - edad)) }))
    .slice(0, max)
}

// --- Cercanía -----------------------------------------------------------------------

export type ParadaCercana = { id: string; nombre: string; lat: number; lng: number; distancia: number }

/**
 * Paradas o estaciones cerca de un punto. Las paradas con estación madre se
 * agrupan en la estación; las sueltas (zonales) cuentan por sí mismas.
 */
export function paradasCercanas(indice: IndiceGtfs, punto: { lat: number; lng: number }, { radioM = 800, max = 5 }: { radioM?: number; max?: number } = {}): ParadaCercana[] {
  const encontradas: ParadaCercana[] = []
  for (const [id, [nombre, nodo, lat, lng]] of Object.entries(indice.paradas)) {
    if (nodo !== "" && nodo !== id) continue
    const distancia = distanceMeters(punto, { lat, lng })
    if (distancia <= radioM) encontradas.push({ id, nombre, lat, lng, distancia })
  }
  return encontradas.sort((a, b) => a.distancia - b.distancia).slice(0, max)
}

/** Buses a menos de `radioM` metros de un punto. */
export function busesCercanos(i: Instantanea, punto: { lat: number; lng: number }, { radioM = 500, max = 10 }: { radioM?: number; max?: number } = {}): (BusEnVia & { distancia: number })[] {
  return busesVigentes(i)
    .map((b) => ({ b, distancia: distanceMeters(punto, b) }))
    .filter((x) => x.distancia <= radioM)
    .sort((a, b) => a.distancia - b.distancia)
    .slice(0, max)
    .map(({ b, distancia }) => ({ ...ubicarBus(i, b, rutaDeIndice(i.indice, b.rutaId)), distancia }))
}

// --- Búsqueda de paradas ---------------------------------------------------------------

export type ParadaEncontrada = { id: string; nombre: string; lat: number; lng: number }

/**
 * Busca estaciones y paradas por nombre sin importar mayúsculas ni tildes (usa
 * `normalize`): todas las palabras de la búsqueda deben estar en el nombre, y salen
 * primero las que lo empiezan igual.
 */
export function buscarParadas(indice: IndiceGtfs, consulta: string, max = 8): ParadaEncontrada[] {
  const q = normalize(consulta)
  const palabras = q.split(" ").filter(Boolean)
  if (palabras.length === 0) return []
  const encontradas: { p: ParadaEncontrada; rango: number }[] = []
  for (const [id, [nombre, nodo, lat, lng]] of Object.entries(indice.paradas)) {
    if (nodo !== "" && nodo !== id) continue
    const n = normalize(nombre)
    // Cada palabra empieza una palabra del nombre («72» no está en «172»).
    const nombrePalabras = n.split(" ")
    if (!palabras.every((w) => nombrePalabras.some((p) => p.startsWith(w)))) continue
    encontradas.push({ p: { id, nombre, lat, lng }, rango: n === q ? 0 : n.startsWith(q) ? 1 : 2 })
  }
  return encontradas.sort((a, b) => a.rango - b.rango || a.p.nombre.length - b.p.nombre.length).slice(0, max).map((x) => x.p)
}

// --- Alertas -------------------------------------------------------------------------------

export type AlertaVigente = { id: string; titulo: string; descripcion: string; efecto: string; rutas: string[]; paradas: string[]; desde: number; hasta: number | null }

const activa = (a: AlertaRt, ahora: number) => a.periodos.length === 0 || a.periodos.some(([ini, fin]) => ini <= ahora && (fin === null || ahora <= fin))

/** Alertas vigentes (según `active_period`) de unas rutas o paradas; sin filtro, todas las vigentes. */
export function alertasVigentes(i: Instantanea, filtro: { rutas?: readonly string[]; paradas?: ReadonlySet<string> } = {}): AlertaVigente[] {
  if (!i.alertas) return []
  const ahora = ahoraS(i)
  const hayFiltro = filtro.rutas !== undefined || filtro.paradas !== undefined
  return i.alertas.datos.alertas
    .filter((a) => activa(a, ahora))
    .filter((a) => !hayFiltro || (filtro.rutas?.some((r) => a.rutas.includes(r)) ?? false) || (filtro.paradas ? a.paradas.some((p) => coincide(i.indice, p, filtro.paradas!)) : false))
    .map((a) => ({
      id: a.id,
      titulo: a.titulo,
      descripcion: a.descripcion,
      efecto: a.efecto,
      rutas: a.rutas,
      paradas: a.paradas,
      desde: Math.min(...a.periodos.map(([ini]) => ini), ahora),
      hasta: a.periodos.some(([, fin]) => fin === null) ? null : Math.max(...a.periodos.map(([, fin]) => fin ?? 0)),
    }))
}

// --- Estado del sistema -------------------------------------------------------------------

export type EstadoSistema = {
  total: number
  porSistema: Record<string, number>
  /** Troncal + dual + alimentador vs. zonal (SITP urbano, complementario, especial). */
  grupos: { transmilenio: number; zonal: number; cable: number; otros: number }
}

/** Buses en servicio ahora por sistema (según la agencia de la ruta de cada bus). */
export function estadoSistema(i: Instantanea): EstadoSistema {
  const porSistema: Record<string, number> = {}
  const grupos = { transmilenio: 0, zonal: 0, cable: 0, otros: 0 }
  const buses = busesVigentes(i)
  for (const bus of buses) {
    const agencia = rutaDeIndice(i.indice, bus.rutaId)?.agencia ?? ""
    const sistema = SISTEMAS[agencia] ?? "sin clasificar"
    porSistema[sistema] = (porSistema[sistema] ?? 0) + 1
    if (["1", "2", "6"].includes(agencia)) grupos.transmilenio++
    else if (["3", "4", "5"].includes(agencia)) grupos.zonal++
    else if (agencia === "7") grupos.cable++
    else grupos.otros++
  }
  return { total: buses.length, porSistema, grupos }
}

// --- Horario programado (GTFS estático) ------------------------------------------------------

/** `service_id` que corren en una fecha AAAA-MM-DD de Bogotá: calendario base más excepciones. */
export function serviciosDelDia(indice: IndiceGtfs, fecha: string): string[] {
  const dia = diaSemanaDeFecha(fecha)
  if (dia === null) return []
  const activos = new Set(
    Object.entries(indice.calendario.servicios)
      .filter(([, s]) => s.inicio <= fecha && fecha <= s.fin && s.dias[dia] === "1")
      .map(([id]) => id),
  )
  for (const [servicio, dia2, tipo] of indice.calendario.excepciones) {
    if (dia2 !== fecha) continue
    if (tipo === 1) activos.add(servicio)
    else if (tipo === 2) activos.delete(servicio)
  }
  return [...activos]
}

export type HorarioDeRuta = {
  rutaId: string
  codigo: string
  destino: string
  /** Salidas programadas hoy; 0 si hoy no corre. */
  salidasHoy: number
  primera: string | null
  ultima: string | null
  /** Salidas por hora de salida (índice = hora, desde 00). */
  porHora: number[]
}

/** Salidas programadas hoy de unas rutas: total, por hora y primera y última. */
export function horarioDeRutas(indice: IndiceGtfs, rutas: readonly string[], ahoraMs: number): HorarioDeRuta[] {
  const servicios = serviciosDelDia(indice, fechaCivilEnZona(new Date(ahoraMs)))
  return rutas.flatMap((id) => {
    const ruta = rutaDeIndice(indice, id)
    if (!ruta) return []
    const horas = servicios.flatMap((s) => (ruta.horario[s] ? [ruta.horario[s]] : []))
    const porHora: number[] = []
    for (const [, , cuenta] of horas) cuenta.forEach((n, h) => (porHora[h] = (porHora[h] ?? 0) + n))
    return [
      {
        rutaId: ruta.id,
        codigo: ruta.codigo,
        destino: ruta.destino,
        salidasHoy: porHora.reduce((a, b) => a + b, 0),
        primera: horas.length ? horas.map((h) => h[0]).sort()[0] : null,
        ultima: horas.length ? horas.map((h) => h[1]).sort().at(-1)! : null,
        porHora: Array.from(porHora, (n) => n ?? 0),
      },
    ]
  })
}

// --- Cancelados hoy -----------------------------------------------------------------------------

export type CanceladosHoy = { total: number; viajesDelDia: number; porRuta: { rutaId: string; codigo: string; destino: string; cancelados: number }[] }

/** Viajes cancelados hoy según `tripupdates.pb`, en total y por ruta (sin guardar nada). `null` si aún no hay copia. */
export function canceladosHoy(i: Instantanea, rutas?: readonly string[]): CanceladosHoy | null {
  if (!i.retrasos) return null
  const hoy = fechaCivilEnZona(new Date(i.ahora))
  const filtro = rutas ? new Set(rutas) : null
  const cuenta = new Map<string, number>()
  let total = 0
  let delDia = 0
  for (const v of i.retrasos.datos.porViaje.values()) {
    if (instanteLocal(new Date(v.inicio * 1000)).fecha !== hoy) continue
    if (filtro && !filtro.has(v.rutaId)) continue
    delDia++
    if (v.rel !== "CANCELED") continue
    total++
    cuenta.set(v.rutaId, (cuenta.get(v.rutaId) ?? 0) + 1)
  }
  const porRuta = [...cuenta]
    .map(([rutaId, cancelados]) => ({ rutaId, codigo: rutaDeIndice(i.indice, rutaId)?.codigo ?? rutaId, destino: rutaDeIndice(i.indice, rutaId)?.destino ?? "", cancelados }))
    .sort((a, b) => b.cancelados - a.cancelados)
  return { total, viajesDelDia: delDia, porRuta }
}
