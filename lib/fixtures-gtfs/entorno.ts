import * as bindings from "gtfs-realtime-bindings"
import { crearFuentes } from "@/lib/gtfs-rt"
import { bytesDe, CABECERA_MUESTRA } from "@/lib/fixtures-gtfs/cargar"

const rt = ((bindings as unknown as { default?: typeof bindings }).default ?? bindings).transit_realtime

/**
 * Pone en `globalThis` unas fuentes de feeds que sirven las muestras reales, con un
 * reloj fijo y sin tocar la red. Las pruebas de la ruta del asistente y de
 * `/api/tiempo-real` las usan para leer feeds de verdad sin conexión.
 */
export function instalarFeeds({ segundosDespues = 20 }: { segundosDespues?: number } = {}) {
  const reloj = { ms: (CABECERA_MUESTRA + segundosDespues) * 1000 }
  const estado = { falla: false, alertasVigentes: false, retrasosAtrasados: 0, llamadas: [] as string[] }
  const fetchFn = (async (url: string) => {
    estado.llamadas.push(url)
    if (estado.falla) throw new TypeError("fetch failed")
    const nombre = url.split("/").pop()!.replace(".pb", "") as "positions" | "alerts" | "tripupdates"
    let bytes: Uint8Array = bytesDe(nombre)
    if (nombre === "alerts" && estado.alertasVigentes) {
      // Las alertas de la muestra ya vencieron: se les da vigencia alrededor del reloj de la prueba.
      const mensaje = rt.FeedMessage.decode(bytes)
      for (const e of mensaje.entity) if (e.alert) e.alert.activePeriod = [{ start: Math.floor(reloj.ms / 1000) - 60, end: Math.floor(reloj.ms / 1000) + 3600 }]
      bytes = rt.FeedMessage.encode(mensaje).finish()
    }
    if (nombre === "tripupdates" && estado.retrasosAtrasados > 0) {
      // Un tripupdates detenido: su cabecera es de hace `retrasosAtrasados` segundos más que la de los demás.
      const mensaje = rt.FeedMessage.decode(bytes)
      mensaje.header.timestamp = Number(mensaje.header.timestamp) - estado.retrasosAtrasados
      bytes = rt.FeedMessage.encode(mensaje).finish()
    }
    return new Response(bytes as BodyInit, { status: 200, headers: { "content-type": "text/plain" } })
  }) as unknown as typeof fetch
  const almacen = globalThis as typeof globalThis & { __transmivozGtfsRt?: unknown }
  almacen.__transmivozGtfsRt = crearFuentes({ fetchFn, ahora: () => reloj.ms })
  return { reloj, estado, ahora: () => new Date(reloj.ms) }
}
