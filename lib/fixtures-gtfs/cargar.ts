import { readFileSync } from "node:fs"
import * as bindings from "gtfs-realtime-bindings"
import { decodificarAlertas, decodificarPosiciones, decodificarRetrasos } from "@/lib/gtfs-rt"
import { IndiceGtfsSchema, type IndiceGtfs } from "@/lib/gtfs-indice"
import type { Instantanea } from "@/lib/tiempo-real"

/** Carga de las muestras reales de los feeds para las pruebas (ver README.md de esta carpeta). */
const rt = ((bindings as unknown as { default?: typeof bindings }).default ?? bindings).transit_realtime
const carpeta = new URL("./", import.meta.url)

export const bytesDe = (nombre: "positions" | "alerts" | "tripupdates") => new Uint8Array(readFileSync(new URL(`${nombre}.pb`, carpeta)))
export const indiceDeMuestra = (): IndiceGtfs => IndiceGtfsSchema.parse(JSON.parse(readFileSync(new URL("indice.json", carpeta), "utf8")))

/** Instante de las muestras: la hora de su cabecera. */
export const CABECERA_MUESTRA = 1794965936

/** Instantánea con los tres feeds de la muestra, `segundosDespues` de su cabecera. */
export function instantaneaDeMuestra(segundosDespues = 20): Instantanea {
  const decodificar = (n: "positions" | "alerts" | "tripupdates") => rt.FeedMessage.decode(bytesDe(n))
  const ahora = (CABECERA_MUESTRA + segundosDespues) * 1000
  const lectura = <T>(datos: T) => ({ datos, leidoEn: ahora, obsoleto: false })
  return {
    ahora,
    indice: indiceDeMuestra(),
    posiciones: lectura(decodificarPosiciones(decodificar("positions")).datos),
    alertas: lectura(decodificarAlertas(decodificar("alerts")).datos),
    retrasos: lectura(decodificarRetrasos(decodificar("tripupdates")).datos),
  }
}
