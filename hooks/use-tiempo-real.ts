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
 * - Si una renovación falla, se conserva el último dato bueno y se marca
 *   `desactualizado`: la pantalla dice que no pudo actualizar, en vez de callar.
 * - Con `peticion` nulo no hace nada (p. ej. sin ubicación o sin estación elegida).
 */

const ESPERA_MS = 8_000

export type EstadoTiempoReal<T> = {
  estado: "inactivo" | "cargando" | "ok" | "error"
  datos: T | null
  /** Hay un dato anterior, pero la última renovación falló. */
  desactualizado: boolean
  /** Instante (ms) de la última respuesta buena. */
  actualizadoEn: number | null
}

export function useTiempoReal<S extends z.ZodType>(peticion: PeticionTiempoReal | null, esquema: S, { cadaMs = 30_000 }: { cadaMs?: number } = {}): EstadoTiempoReal<z.infer<S>> {
  const [resultado, setResultado] = useState<EstadoTiempoReal<z.infer<S>>>({ estado: "inactivo", datos: null, desactualizado: false, actualizadoEn: null })
  const esquemaRef = useRef(esquema)
  const clave = peticion ? JSON.stringify(peticion) : null

  useEffect(() => {
    if (!clave) {
      setResultado({ estado: "inactivo", datos: null, desactualizado: false, actualizadoEn: null })
      return
    }
    let vigente = true
    let controlador: AbortController | null = null
    setResultado((r) => ({ ...r, estado: r.datos ? "ok" : "cargando" }))

    async function consultar() {
      if (typeof document !== "undefined" && document.visibilityState === "hidden") return
      controlador?.abort()
      const este = (controlador = new AbortController())
      const limite = setTimeout(() => este.abort(), ESPERA_MS)
      try {
        const res = await fetch("/api/tiempo-real", { method: "POST", body: clave, headers: { "Content-Type": "application/json" }, signal: este.signal })
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const datos = esquemaRef.current.parse(await res.json())
        if (vigente) setResultado({ estado: "ok", datos, desactualizado: false, actualizadoEn: Date.now() })
      } catch {
        if (vigente) setResultado((r) => (r.datos ? { ...r, estado: "ok", desactualizado: true } : { estado: "error", datos: null, desactualizado: false, actualizadoEn: null }))
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

  return resultado
}
