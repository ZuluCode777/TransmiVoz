import { MAX_EVIDENCIA_DIAS, fechaCivilEnZona } from "@/lib/evidencia"

/**
 * Fecha de publicación de un GTFS, sacada del PROPIO archivo que se procesa y no de lo que diga el portal hoy.
 *
 * El portal regenera `GTFS.zip` cada día y estampa en cada entrada la hora de generación (UTC). Un zip viejo
 * conserva su fecha de entonces: con ella, un índice hecho de un archivo vencido nace vencido y la guardia de
 * `MAX_EVIDENCIA_DIAS` lo detecta. Tomar la fecha del manifiesto actual (como hacía la primera versión) hacía
 * pasar por nuevo un índice viejo.
 *
 * Entrada: la salida de `unzip -l`. Se rechaza todo lo que no se puede comprobar: sin las tablas principales,
 * con entradas de fechas muy distintas (un zip armado a mano o mezclado) o con fecha en el futuro.
 */

const TABLAS = ["routes.txt", "stops.txt", "trips.txt", "stop_times.txt"]
/** Las entradas de una misma generación se escriben con minutos de diferencia; más que esto, no son de una misma. */
const DISPERSION_MAXIMA_MS = 2 * 60 * 60 * 1000
const LINEA = /^\s*\d+\s+(\d{2})-(\d{2})-(\d{4})\s+(\d{2}):(\d{2})\s+(\S+)\s*$/

export function fechaDePublicacionDelZip(listado: string, ahora: Date = new Date()): string {
  const entradas = listado.split("\n").flatMap((linea) => {
    const m = LINEA.exec(linea)
    return m ? [{ nombre: m[6], instante: Date.UTC(Number(m[3]), Number(m[1]) - 1, Number(m[2]), Number(m[4]), Number(m[5])) }] : []
  })
  const faltan = TABLAS.filter((t) => !entradas.some((e) => e.nombre === t))
  if (faltan.length > 0) throw new Error(`El zip no trae ${faltan.join(", ")} (o no se pudo leer su listado): no se puede comprobar su fecha.`)
  const instantes = entradas.map((e) => e.instante)
  const ultimo = Math.max(...instantes)
  if (ultimo - Math.min(...instantes) > DISPERSION_MAXIMA_MS) throw new Error("Las entradas del zip son de fechas muy distintas: no es una sola generación del GTFS.")
  if (ultimo > ahora.getTime() + 24 * 60 * 60 * 1000) throw new Error("El zip dice haberse generado en el futuro: no se puede comprobar su fecha.")
  // La hora de las entradas es UTC; el sistema opera en Bogotá.
  return fechaCivilEnZona(new Date(ultimo))
}

/** ¿El GTFS ya pasó la vigencia de la evidencia? (el índice nacería vencido). */
export const gtfsVencido = (publicado: string, ahora: Date = new Date()) =>
  (Date.parse(`${fechaCivilEnZona(ahora)}T00:00:00Z`) - Date.parse(`${publicado}T00:00:00Z`)) / 86_400_000 > MAX_EVIDENCIA_DIAS
