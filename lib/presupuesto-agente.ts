import { ESPERA_MAXIMA_CLIENTE_MS } from "@/lib/consulta-agente"

/**
 * Presupuesto de tiempo de UNA petición a `/api/agent`. La web espera
 * `ESPERA_MAXIMA_CLIENTE_MS` (6 s) y el iPhone 12 s; el servidor se da menos que la web
 * para que la respuesta llegue antes de que el cliente se rinda. Todo lo que espera
 * (catálogo, modelo, feeds) se mide contra el mismo reloj y se recorta a lo que queda.
 *
 * Mide con `performance.now()` (monótono): no depende de `Date`.
 */

/** Margen que se deja bajo la espera de la web. */
export const MARGEN_CLIENTE_MS = 1_000
export const PRESUPUESTO_TOTAL_MS = ESPERA_MAXIMA_CLIENTE_MS - MARGEN_CLIENTE_MS
/** Lo que se reserva, al final, para armar y enviar la respuesta una vez conocidos los datos. */
export const RESERVA_RESPUESTA_MS = 400
/** Con menos que esto de presupuesto no se consulta al modelo: contestan las reglas. */
export const MINIMO_PARA_MODELO_MS = 500

export type Presupuesto = {
  /** Milisegundos que quedan (nunca negativos). */
  restante(): number
  /** Cuánto puede esperar un paso que termina de usar `max`, dejando la reserva de respuesta (y lo que pida `reservaMs`). */
  para(max: number, reservaMs?: number): number
}

export function crearPresupuesto(totalMs: number = PRESUPUESTO_TOTAL_MS, reloj: () => number = () => performance.now()): Presupuesto {
  const inicio = reloj()
  const restante = () => Math.max(0, totalMs - (reloj() - inicio))
  return {
    restante,
    para: (max, reservaMs = 0) => Math.max(0, Math.min(max, restante() - RESERVA_RESPUESTA_MS - reservaMs)),
  }
}
