import indiceJson from "@/data/gtfs-indice.json" with { type: "json" }
import type { PeticionTiempoReal } from "@/lib/contrato-tiempo-real"
import { IndiceGtfsSchema, type IndiceGtfs } from "@/lib/gtfs-indice"
import { fuentes, saludDeFeeds } from "@/lib/gtfs-rt"
import type { Contexto } from "@/lib/consulta-tiempo-real"
import type { Instantanea } from "@/lib/tiempo-real"
import type { TransmilenioData } from "@/lib/routes"

/**
 * Une los feeds en vivo con el índice estático para una consulta (solo servidor).
 * Lee solo los feeds que la consulta necesita:
 *
 * - `positions` y `alerts` se esperan (con tope de 3,5 s y caché de 15 s); si la
 *   lectura falla y no hay copia, el feed queda en `null`.
 * - `tripupdates` (8,8 MB) nunca se espera: se usa la última copia buena, o ninguna
 *   en el arranque en frío, y se lanza su refresco aparte.
 */

let indice: IndiceGtfs | null = null
export const indiceGtfs = (): IndiceGtfs => (indice ??= IndiceGtfsSchema.parse(indiceJson))

export type Necesidades = { posiciones: boolean; alertas: boolean; retrasos: boolean }

export function necesidadesDe(operacion: PeticionTiempoReal["operacion"]): Necesidades {
  switch (operacion) {
    case "llegadas":
    case "buses-ruta":
    case "proximas-paradas-bus":
    case "paradas-cercanas":
    case "buses-cercanos":
    case "estado-sistema":
      return { posiciones: true, alertas: false, retrasos: true }
    case "alertas":
      return { posiciones: false, alertas: true, retrasos: false }
    case "cancelados-hoy":
      return { posiciones: false, alertas: false, retrasos: true }
    case "buscar-paradas":
    case "horario-ruta":
      return { posiciones: false, alertas: false, retrasos: false }
    case "salud-feeds":
      return { posiciones: false, alertas: false, retrasos: true }
  }
}

/** Lanza la lectura de `tripupdates` sin esperarla: la primera pregunta real ya la encuentra lista. */
export function precalentarRetrasos(): void {
  fuentes().retrasos.leerSinEsperar()
}

/**
 * Adelanta la lectura de los feeds de una consulta que el modelo aún está
 * interpretando: corre en paralelo con él (hasta 4,5 s) en vez de después, así la
 * espera total de la web (6 s) alcanza. La caché de 15 s la comparte con la consulta.
 */
export function precalentarFeeds(necesita: Necesidades): void {
  if (necesita.posiciones) void fuentes().posiciones.leer().catch(() => undefined)
  if (necesita.alertas) void fuentes().alertas.leer().catch(() => undefined)
  if (necesita.retrasos) precalentarRetrasos()
}

export async function tomarInstantanea(necesita: Necesidades, ahora: number = Date.now(), presupuestoMs?: number): Promise<Instantanea> {
  const leer = <T,>(quiere: boolean, lectura: () => Promise<T>) => (quiere ? lectura().catch(() => null) : Promise.resolve(null))
  const [posiciones, alertas] = await Promise.all([leer(necesita.posiciones, () => fuentes().posiciones.leer(presupuestoMs)), leer(necesita.alertas, () => fuentes().alertas.leer(presupuestoMs))])
  return { ahora, indice: indiceGtfs(), posiciones, alertas, retrasos: necesita.retrasos ? fuentes().retrasos.leerSinEsperar() : null }
}

/** Contexto completo para resolver una consulta. */
export async function tomarContexto(data: TransmilenioData, necesita: Necesidades, ahora?: number, presupuestoMs?: number): Promise<Contexto> {
  const i = await tomarInstantanea(necesita, ahora, presupuestoMs)
  return { data, i, salud: saludDeFeeds() }
}
