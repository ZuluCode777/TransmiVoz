"use client"

import { useEffect, useRef, useState } from "react"
import type { z } from "zod"
import type { PeticionTiempoReal } from "@/lib/contrato-tiempo-real"

/**
 * Consulta periódica a `/api/tiempo-real` para una pantalla.
 *
 * - Una petición al montar y otra cada `cadaMs` (30 s: el feed se regenera cada
 *   26–75 s y el servidor lo guarda 15 s), solo con la pestaña visible.
 * - Cada respuesta se valida con el esquema del contrato; lo que no cuadra es un
 *   error, nunca un dato a medias.
 * - El dato va atado a la consulta que lo trajo: al cambiar de consulta (otra estación) se
 *   descarta al instante, y si una renovación falla también se retira. Nada de minutos viejos
 *   en pantalla ni anunciados para otro lugar.
 * - Con `peticion` nulo no hace nada (p. ej. sin ubicación o sin estación elegida).
 */

const ESPERA_MS = 8_000

export type EstadoTiempoReal<T> = {
  estado: "inactivo" | "cargando" | "ok" | "error"
  datos: T | null
  /** Instante (ms) de la última respuesta buena. */
  actualizadoEn: number | null
}

/** Lo que guarda el hook: el dato SIEMPRE va atado a la consulta que lo trajo. */
type Guardado<T> = { clave: string | null; estado: EstadoTiempoReal<T>["estado"]; datos: T | null; actualizadoEn: number | null }

export function useTiempoReal<S extends z.ZodType>(peticion: PeticionTiempoReal | null, esquema: S, { cadaMs = 30_000 }: { cadaMs?: number } = {}): EstadoTiempoReal<z.infer<S>> {
  const [guardado, setGuardado] = useState<Guardado<z.infer<S>>>({ clave: null, estado: "inactivo", datos: null, actualizadoEn: null })
  const esquemaRef = useRef(esquema)
  const clave = peticion ? JSON.stringify(peticion) : null

  useEffect(() => {
    if (!clave) {
      setGuardado({ clave: null, estado: "inactivo", datos: null, actualizadoEn: null })
      return
    }
    let vigente = true
    let controlador: AbortController | null = null
    // Otra consulta (otra estación, otra ruta): lo anterior no vale para ella.
    setGuardado((g) => (g.clave === clave ? g : { clave, estado: "cargando", datos: null, actualizadoEn: null }))

    async function consultar() {
      if (typeof document !== "undefined" && document.visibilityState === "hidden") return
      controlador?.abort()
      const este = (controlador = new AbortController())
      const limite = setTimeout(() => este.abort(), ESPERA_MS)
      try {
        const res = await fetch("/api/tiempo-real", { method: "POST", body: clave, headers: { "Content-Type": "application/json" }, signal: este.signal })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const datos = esquemaRef.current.parse(await res.json())
        if (vigente) setGuardado({ clave, estado: "ok", datos, actualizadoEn: Date.now() })
      } catch {
        // Si la renovación falla, el dato anterior se retira: nunca se muestran ni se anuncian minutos que ya no se pudieron confirmar.
        if (vigente) setGuardado({ clave, estado: "error", datos: null, actualizadoEn: null })
      } finally {
        clearTimeout(limite)
      }
    }

    void consultar()
    const id = setInterval(() => void consultar(), cadaMs)
    const alVolver = () => {
      if (document.visibilityState === "visible") void consultar()
    }
    document.addEventListener("visibilitychange", alVolver)
    return () => {
      vigente = false
      clearInterval(id)
      controlador?.abort()
      document.removeEventListener("visibilitychange", alVolver)
    }
  }, [clave, cadaMs])

  // Aun en el render en que cambia la consulta (antes de que corra el efecto) no se devuelve el dato de la anterior.
  if (!clave) return { estado: "inactivo", datos: null, actualizadoEn: null }
  if (guardado.clave !== clave) return { estado: "cargando", datos: null, actualizadoEn: null }
  return { estado: guardado.estado, datos: guardado.datos, actualizadoEn: guardado.actualizadoEn }
}
