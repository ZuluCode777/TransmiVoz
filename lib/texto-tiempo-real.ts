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
