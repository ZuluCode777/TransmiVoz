/**
 * Frases de tiempo para decir en voz alta y para pantalla, sin dependencias del
 * servidor: las usan el asistente (`lib/respuesta-tiempo-real.ts`) y los componentes
 * de la web (`components/en-vivo.tsx`), para que digan lo mismo con las mismas palabras.
 */

export const plural = (n: number, uno: string, varios: string) => `${n.toLocaleString("es-CO")} ${n === 1 ? uno : varios}`

/** «en unos 4 minutos», «en menos de un minuto». */
export function enTiempo(segundos: number): string {
  if (segundos < 60) return "en menos de un minuto"
  const m = Math.round(segundos / 60)
  return m === 1 ? "en un minuto" : `en unos ${m} minutos`
}

/** «hace 40 segundos», «hace 3 minutos». */
export function haceTiempo(segundos: number): string {
  if (segundos < 90) return `hace ${plural(Math.max(1, Math.round(segundos)), "segundo", "segundos")}`
  return `hace ${plural(Math.round(segundos / 60), "minuto", "minutos")}`
}

/** Dirección de una ruta: «hacia X», o «entre X y Y» en las zonales que traen los dos extremos. */
export function textoDestino(destino: string): string {
  const [a, b] = destino.split("||").map((x) => x.trim())
  return b ? `entre ${a} y ${b}` : `hacia ${a}`
}

/** Retraso reportado, solo si es notable (3 minutos o más): «con unos 3 minutos de retraso reportado». */
export function textoRetraso(retrasoS: number | null): string {
  if (retrasoS === null || Math.abs(retrasoS) < 180) return ""
  return `, con unos ${Math.round(Math.abs(retrasoS) / 60)} minutos de ${retrasoS > 0 ? "retraso" : "adelanto"} reportado`
}

export const mayuscula = (texto: string) => texto.charAt(0).toUpperCase() + texto.slice(1)

/** Lo mínimo de una llegada para decirla: de dónde sale el dato, cuánto falta y su retraso. */
export type LlegadaDicha = { origen: "en-vivo" | "programado"; segundos: number; retraso: number | null }

/** «en unos 4 minutos, estimado, con unos 3 minutos de retraso reportado». */
export const cuandoLlega = (l: LlegadaDicha) => `${enTiempo(l.segundos)}, estimado${textoRetraso(l.retraso)}`

const SIN_BUS_EN_VIVO = ", sin bus en vivo confirmado"

/**
 * ÚNICO lugar que dice una llegada, en voz y en pantalla (asistente, detalle de ruta, plan de viaje y GPS):
 * una llegada con un bus ubicado «llega»; una que solo sale del horario programado (con su retraso) dice
 * que es «según la programación» y que no hay bus en vivo confirmado. Así ninguna pantalla puede anunciar
 * como bus en vivo lo que no lo es.
 */
export function predicadoLlegada(l: LlegadaDicha, parada?: string): string {
  const a = parada ? ` a ${parada}` : ""
  return l.origen === "en-vivo" ? `llega${a} ${cuandoLlega(l)}` : `según la programación, llegaría${a} ${cuandoLlega(l)}${SIN_BUS_EN_VIVO}`
}

/** Frase completa de una llegada: «la B10 hacia Portal Norte llega a Calle 100 en…» o «según la programación, la B10… llegaría…». */
export function frasesLlegada(l: LlegadaDicha, servicio: string, parada?: string): string {
  const a = parada ? ` a ${parada}` : ""
  return l.origen === "en-vivo" ? `${servicio} ${predicadoLlegada(l, parada)}` : `según la programación, ${servicio} llegaría${a} ${cuandoLlega(l)}${SIN_BUS_EN_VIVO}`
}
