import { z } from "zod"
import { fechaEvidenciaVigente } from "@/lib/evidencia"
import type { BusRoute, Place, TransmilenioData } from "@/lib/routes"
import { contentWords } from "@/lib/text"

/**
 * Índice compacto del GTFS estático de TransMilenio (`data/gtfs-indice.json`),
 * generado por `pnpm sync:gtfs-indice`. Sirve para dar sentido a los feeds en
 * vivo, que solo traen ids numéricos: `route_id` → código público y destino,
 * `stop_id` → nombre y estación, y por cada `route_id` el patrón de referencia
 * (paradas en orden con los segundos programados desde la primera).
 *
 * Fuente: GTFS oficial de TransMilenio S.A., CC BY-SA 4.0 (ver `atribucion`).
 * Caduca igual que la evidencia de paradas: `MAX_EVIDENCIA_DIAS` sobre la fecha
 * de publicación del GTFS. Un índice vencido no se usa para estimar nada.
 */

export const RutaIndiceSchema = z.object({
  /** `route_id` del GTFS: es el que traen los feeds en vivo. */
  id: z.string(),
  /** `route_short_name`: «B10», o solo el número para las rutas «8 G», «8 T»… */
  codigo: z.string(),
  /** `route_long_name`: hacia dónde va. */
  destino: z.string(),
  agencia: z.string(),
  /** Patrón de referencia: `[stop_id, segundos desde la primera parada]`. */
  paradas: z.array(z.tuple([z.string(), z.number()])).min(2),
  /**
   * Por `service_id`: `[primera salida, última salida, salidas por hora de salida]`
   * (HH:MM; la hora puede pasar de 24). Las salidas por hora empiezan a las 00.
   */
  horario: z.record(z.string(), z.tuple([z.string(), z.string(), z.array(z.number())])),
})
export type RutaIndice = z.infer<typeof RutaIndiceSchema>

/** Sistema de cada agencia del GTFS. */
export const SISTEMAS: Record<string, string> = {
  "1": "troncal",
  "2": "alimentador",
  "3": "zonal urbano",
  "4": "zonal complementario",
  "5": "zonal especial",
  "6": "dual",
  "7": "TransMiCable",
}
/** Las agencias que son del catálogo de ArcGIS (rutas troncales y duales): solo con ellas se enlaza un código del catálogo. */
export const AGENCIAS_DEL_CATALOGO: ReadonlySet<string> = new Set(["1", "6"])

export const IndiceGtfsSchema = z.object({
  fuente: z.string(),
  /** Fecha (AAAA-MM-DD) de publicación del GTFS del que sale. */
  publicado: z.string(),
  generado: z.string(),
  sha256: z.string(),
  licencia: z.string(),
  atribucion: z.string(),
  calendario: z.object({
    /** `dias`: dom..sáb como «0111110». */
    servicios: z.record(z.string(), z.object({ dias: z.string().regex(/^[01]{7}$/), inicio: z.string(), fin: z.string() })),
    /** `[service_id, fecha, 1 = se agrega | 2 = se quita]`. */
    excepciones: z.array(z.tuple([z.string(), z.string(), z.number()])),
  }),
  rutas: z.array(RutaIndiceSchema),
  /** `stop_id` → `[nombre, estación madre ("" si no tiene), lat, lng]`. */
  paradas: z.record(z.string(), z.tuple([z.string(), z.string(), z.number(), z.number()])),
})
export type IndiceGtfs = z.infer<typeof IndiceGtfsSchema>

/** ¿El índice sigue vigente? Misma guardia que la evidencia de paradas. */
export function indiceVigente(indice: IndiceGtfs, ahora: Date): boolean {
  return fechaEvidenciaVigente(indice.publicado, ahora)
}

/** Id de estación del GTFS a partir del id del catálogo («09122» → «9122»). */
const idEstacionGtfs = (idCatalogo: string) => idCatalogo.replace(/^0+(?=\d)/, "")

/** Ids de estación del GTFS que forman un lugar del catálogo. */
export function estacionesGtfsDeLugar(place: Place): Set<string> {
  return new Set(place.stations.map((s) => idEstacionGtfs(s.id)))
}

/** Estación madre de una parada del índice (la propia parada si es una estación). */
export function estacionDeParada(indice: IndiceGtfs, stopId: string): string | undefined {
  return indice.paradas[stopId]?.[1] || undefined
}

/** Palabras en común entre dos nombres de destino. */
function coincidencias(a: string, b: string): number {
  const palabras = new Set(contentWords(a))
  return contentWords(b).filter((p) => palabras.has(p)).length
}

/**
 * `route_id` del GTFS de una ruta del catálogo. El código del catálogo es el
 * `route_short_name` sin espacios («B10»); las rutas numeradas («8 G», «8 T»)
 * comparten el número en el GTFS («8») y se distinguen por su destino: una
 * pareja de `route_id` se reparte entre las rutas hermanas del catálogo según
 * el destino que se parece, y si queda una de cada lado se emparejan. Sin
 * coincidencia clara devuelve vacío: ninguna adivinanza.
 */
export function rutasGtfsDeRuta(ruta: BusRoute, data: TransmilenioData, indice: IndiceGtfs): RutaIndice[] {
  // Solo troncales y duales: el mismo código existe en el sistema zonal con otros servicios (C25, C15…) y no se mezcla.
  const delCatalogo = indice.rutas.filter((r) => AGENCIAS_DEL_CATALOGO.has(r.agencia))
  const exactas = delCatalogo.filter((r) => r.codigo === ruta.code)
  if (exactas.length > 0) {
    // Y, entre las del mismo sistema, las que más se parecen a los extremos del catálogo (ida, vuelta y variantes);
    // sin ninguna coincidencia no se descarta nada.
    const puntaje = (r: RutaIndice) => Math.max(coincidencias(ruta.to, r.destino), coincidencias(ruta.from, r.destino))
    const mejor = Math.max(...exactas.map(puntaje))
    return mejor > 0 ? exactas.filter((r) => puntaje(r) === mejor) : exactas
  }
  const numerada = /^(\d+)\s?[A-Z]$/.exec(ruta.code)
  if (!numerada) return []
  const candidatas = delCatalogo.filter((r) => r.codigo === numerada[1])
  const hermanas = data.routes.filter((r) => new RegExp(`^${numerada[1]}\\s?[A-Z]$`).test(r.code))
  const pares = hermanas
    .flatMap((h) => candidatas.map((c) => ({ h, c, puntaje: coincidencias(h.to, c.destino) })))
    .filter((p) => p.puntaje > 0)
    .sort((a, b) => b.puntaje - a.puntaje)
  const asignadas = new Map<BusRoute, RutaIndice>()
  const usadas = new Set<RutaIndice>()
  for (const { h, c } of pares) {
    if (!asignadas.has(h) && !usadas.has(c)) {
      asignadas.set(h, c)
      usadas.add(c)
    }
  }
  const hermanasLibres = hermanas.filter((h) => !asignadas.has(h))
  const candidatasLibres = candidatas.filter((c) => !usadas.has(c))
  if (hermanasLibres.length === 1 && candidatasLibres.length === 1) asignadas.set(hermanasLibres[0], candidatasLibres[0])
  const propia = asignadas.get(ruta)
  return propia ? [propia] : []
}
