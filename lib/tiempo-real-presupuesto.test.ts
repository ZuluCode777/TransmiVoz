import assert from "node:assert/strict"
import test, { mock } from "node:test"
import * as bindings from "gtfs-realtime-bindings"
import { ESPERA_MAXIMA_CLIENTE_MS } from "./consulta-agente"
import { bytesDe, CABECERA_MUESTRA } from "./fixtures-gtfs/cargar"
import { crearFuentes } from "./gtfs-rt"
import { MARGEN_CLIENTE_MS, MINIMO_PARA_MODELO_MS, PRESUPUESTO_TOTAL_MS, RESERVA_RESPUESTA_MS, crearPresupuesto } from "./presupuesto-agente"

/**
 * Presupuesto de tiempo de `/api/agent` (revisión R1, hallazgo 8): la web espera 6 s en total
 * (`ESPERA_MAXIMA_CLIENTE_MS`). Se prueba la ruta REAL con un catálogo lento, un modelo que tarda 4,4 s
 * y un feed vencido, midiendo con `performance.now()` (el reloj de `Date` está fijo en la hora de las
 * muestras para que su frescura sea la de ayer). El Ollama y la red de TransMilenio son simulados.
 */

// El módulo de Ollama lee su entorno al cargarse: se fija ANTES de importar la ruta, y se deja el modelo «cargado».
process.env.OLLAMA_MODEL = "qwen2.5:3b"
;(globalThis as { __transmivozOllama?: unknown }).__transmivozOllama = { precarga: null, cargado: true }

const rt = ((bindings as unknown as { default?: typeof bindings }).default ?? bindings).transit_realtime
const NOMBRES = { "positions.pb": "positions", "alerts.pb": "alerts", "tripupdates.pb": "tripupdates" } as const

const ahoraMuestra = (CABECERA_MUESTRA + 20) * 1000
const sim = { demoraModeloMs: 0, demoraFeedMs: 0, descargasPositions: 0, consultasModelo: 0 }
/** El catálogo de ArcGIS «cuelga» hasta que una prueba abre esta puerta; entonces falla y se usa la copia guardada. */
let abrirCatalogo: () => void = () => {}
const puertaCatalogo = new Promise<void>((ok) => (abrirCatalogo = ok))

/** Responde tras `ms` o falla si la señal se aborta, como el `fetch` real con `AbortSignal.timeout`. */
const demorar = (ms: number, senal?: AbortSignal | null) =>
  new Promise<void>((ok, no) => {
    const id = setTimeout(ok, ms)
    senal?.addEventListener("abort", () => {
      clearTimeout(id)
      no(new DOMException("aborted", "TimeoutError"))
    })
  })

const fetchSimulado = (async (url: string | URL | Request, init?: RequestInit) => {
  const direccion = String(url)
  if (direccion.endsWith("/api/chat")) {
    const cuerpo = typeof init?.body === "string" ? JSON.parse(init.body) : {}
    if (Array.isArray(cuerpo.messages) && cuerpo.messages.length === 0) return new Response(JSON.stringify({ message: { content: "" } }))
    sim.consultasModelo++
    await demorar(sim.demoraModeloMs, init?.signal)
    const contenido = JSON.stringify({ intent: "realtime", origin: "", destination: "Calle 100", routeCode: "B10" })
    return new Response(JSON.stringify({ message: { content: contenido } }))
  }
  if (direccion.endsWith("/api/tags")) return new Response(JSON.stringify({ models: [{ name: "qwen2.5:3b" }] }))
  // Todo lo demás es el catálogo de ArcGIS: lento y, al final, caído (se usa la copia guardada).
  await puertaCatalogo
  throw new Error("sin red (ArcGIS simulado)")
}) as typeof fetch

const fetchFeeds = (async (url: string) => {
  const archivo = url.split("/").pop() as keyof typeof NOMBRES
  if (archivo === "positions.pb") sim.descargasPositions++
  await demorar(sim.demoraFeedMs)
  const mensaje = rt.FeedMessage.decode(bytesDe(NOMBRES[archivo]))
  return new Response(rt.FeedMessage.encode(mensaje).finish() as BodyInit, { status: 200 })
}) as unknown as typeof fetch

async function conRuta<T>(prueba: (ruta: typeof import("../app/api/agent/route")) => Promise<T>): Promise<T> {
  const original = globalThis.fetch
  globalThis.fetch = fetchSimulado
  mock.timers.enable({ apis: ["Date"], now: ahoraMuestra })
  ;(globalThis as { __transmivozGtfsRt?: unknown }).__transmivozGtfsRt = crearFuentes({ fetchFn: fetchFeeds, ahora: () => Date.now() })
  try {
    return await prueba(await import("../app/api/agent/route"))
  } finally {
    mock.timers.reset()
    globalThis.fetch = original
  }
}

const preguntar = (ruta: typeof import("../app/api/agent/route"), message: string) =>
  ruta.POST(new Request("http://local/api/agent", { method: "POST", body: JSON.stringify({ message }) }))

/** Mide una pregunta de punta a punta. */
async function medir(ruta: typeof import("../app/api/agent/route"), message: string) {
  const t0 = performance.now()
  const respuesta = await (await preguntar(ruta, message)).json()
  return { ms: performance.now() - t0, respuesta }
}

test("el presupuesto deja margen bajo la espera de la web y reparte lo que queda", () => {
  assert.equal(PRESUPUESTO_TOTAL_MS, ESPERA_MAXIMA_CLIENTE_MS - MARGEN_CLIENTE_MS)
  assert.ok(PRESUPUESTO_TOTAL_MS <= ESPERA_MAXIMA_CLIENTE_MS - 1_000, "al menos 1 s de margen bajo los 6 s")
  let ahora = 0
  const p = crearPresupuesto(5_000, () => ahora)
  assert.equal(p.restante(), 5_000)
  assert.equal(p.para(4_500), 4_500)
  ahora = 3_000
  assert.equal(p.restante(), 2_000)
  assert.equal(p.para(4_500), 2_000 - RESERVA_RESPUESTA_MS, "el modelo solo recibe lo que queda menos la reserva")
  ahora = 4_800
  assert.ok(p.para(4_500) < MINIMO_PARA_MODELO_MS, "con tan poco, el modelo no se consulta")
  ahora = 99_000
  assert.equal(p.restante(), 0)
  assert.equal(p.para(4_500), 0)
})

test("catálogo en frío colgado + modelo de 4,4 s + feed lento: todo cabe bajo el presupuesto y los feeds corren en paralelo", { timeout: 25_000 }, async () => {
  Object.assign(sim, { demoraModeloMs: 4_400, demoraFeedMs: 3_000, descargasPositions: 0, consultasModelo: 0 })
  await conRuta(async (ruta) => {
    // «¿Dónde viene el B10?»: el modelo está cargado, así que se le consulta; pero el catálogo en frío ya se comió
    // 2,5 s, y al modelo solo le quedan 2,1 s de los 5 s: se corta y responden las reglas.
    const { ms, respuesta } = await medir(ruta, "¿Dónde viene el B10?")
    abrirCatalogo() // la consulta en vivo del catálogo falla de una vez: queda la copia guardada en memoria
    assert.ok(ms < PRESUPUESTO_TOTAL_MS, `tardó ${Math.round(ms)} ms (presupuesto ${PRESUPUESTO_TOTAL_MS}; antes se esperaban los 15 s del catálogo)`)
    assert.ok(ms >= 2_400, "esperó el arranque del catálogo antes de caer en la copia")
    assert.equal(respuesta.engine, "reglas", "el modelo no cabía en el presupuesto")
    // Los feeds se pidieron YA, no tras el catálogo y el modelo: la descarga de 3 s ya estaba lista, y fue una sola.
    // (Pedidos tras el catálogo habrían terminado a los 5,5 s, sin presupuesto para esperarlos.)
    assert.match(respuesta.reply, /Hay \d+ buses? de la B10 en vía/)
    assert.equal(sim.descargasPositions, 1)
    await new Promise((ok) => setTimeout(ok, 50))
  })
})

test("modelo de 4,4 s con el feed vencido: no hay segunda descarga en el camino de la respuesta y todo cabe bajo 6 s", { timeout: 25_000 }, async () => {
  Object.assign(sim, { demoraModeloMs: 0, demoraFeedMs: 0, descargasPositions: 0, consultasModelo: 0 })
  await conRuta(async (ruta) => {
    // Deja una copia de posiciones y la deja vencida (20 s; el TTL es de 15).
    const { fuentes } = await import("./gtfs-rt")
    await fuentes().posiciones.leer()
    sim.descargasPositions = 0
    sim.demoraModeloMs = 4_400
    // La renovación (que ya se pidió al empezar) tarda 6 s: sigue en curso cuando el modelo contesta a los 4,4 s.
    sim.demoraFeedMs = 6_000
    mock.timers.setTime(ahoraMuestra + 20_000)
    // Una frase sin palabras de transporte: las reglas no la entienden, no se adelanta ningún feed y manda el modelo.
    const { ms, respuesta } = await medir(ruta, "¿ya casi me recoge?")
    assert.equal(sim.consultasModelo, 1)
    assert.equal(respuesta.engine, "ollama")
    assert.match(respuesta.reply, /Calle 100/, "responde en vivo (con la copia que había)")
    assert.doesNotMatch(respuesta.reply, /No pude consultar/)
    assert.ok(ms < PRESUPUESTO_TOTAL_MS, `tardó ${Math.round(ms)} ms (antes: 8,3 s)`)
    assert.ok(ms < ESPERA_MAXIMA_CLIENTE_MS - 500, "y deja margen bajo los 6 s de la web")
    // La renovación sí se lanzó, aparte (y una sola).
    await demorar(2_000)
    assert.equal(sim.descargasPositions, 1, "una sola descarga: la del arranque, sin otra al responder")
  })
})
