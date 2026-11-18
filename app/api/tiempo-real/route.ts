import {
  LIMITE_TIEMPO_REAL,
  MAXIMO_BYTES_CUERPO,
  PeticionTiempoRealSchema,
  VENTANA_TIEMPO_REAL_MS,
} from "@/lib/contrato-tiempo-real"
import { ejecutarConsulta } from "@/lib/consulta-tiempo-real"
import { leerCuerpoLimitado } from "@/lib/cuerpo-peticion"
import { claveCliente } from "@/lib/identidad-cliente"
import { necesidadesDe, tomarContexto } from "@/lib/instantanea-servidor"
import { createRateLimiter } from "@/lib/rate-limit"
import { getTransmilenioData } from "@/lib/transmilenio-data"

/**
 * Servicios en vivo de TransMilenio como JSON (contrato en `lib/contrato-tiempo-real.ts`).
 *
 * Pasa por el `proxy` (HTTP Basic), como `/api/planificador`: el `matcher` solo
 * deja fuera `/api/agent`. Tiene su propio límite de peticiones; las lecturas de los
 * feeds ya están en caché (15 s), así que cada petición cuesta cálculo, no red.
 * La coordenada de las operaciones de cercanía llega en el cuerpo, se usa y se
 * descarta: este manejador no registra ninguna petición.
 */
const limite = createRateLimiter({ limit: LIMITE_TIEMPO_REAL, windowMs: VENTANA_TIEMPO_REAL_MS })

export async function POST(req: Request) {
  const cuerpo = await leerCuerpoLimitado({ cuerpo: req.body, maximoBytes: MAXIMO_BYTES_CUERPO })
  if (cuerpo.kind === "excedido") return Response.json({ error: "cuerpo-demasiado-grande" }, { status: 413 })
  if (cuerpo.kind === "error") return Response.json({ error: "peticion-ilegible" }, { status: 400 })

  let json: unknown
  try {
    json = JSON.parse(cuerpo.texto)
  } catch {
    return Response.json({ error: "peticion-invalida" }, { status: 400 })
  }
  const peticion = PeticionTiempoRealSchema.safeParse(json)
  if (!peticion.success) return Response.json({ error: "peticion-invalida" }, { status: 400 })

  const { allowed, retryAfterSeconds } = limite(claveCliente())
  if (!allowed) return Response.json({ error: "demasiadas-peticiones" }, { status: 429, headers: { "Retry-After": String(retryAfterSeconds) } })

  const necesita = necesidadesDe(peticion.data.operacion)
  const ctx = await tomarContexto(await getTransmilenioData(), necesita)
  // Sin ninguna lectura de un feed que la consulta necesita (ni copia anterior), no hay nada que estimar.
  if ((necesita.posiciones && !ctx.i.posiciones) || (necesita.alertas && !ctx.i.alertas)) {
    return Response.json({ error: "feed-no-disponible" }, { status: 503, headers: { "Retry-After": "15" } })
  }
  const resultado = ejecutarConsulta(ctx, peticion.data)
  return Response.json(resultado.cuerpo, { status: resultado.estado })
}
