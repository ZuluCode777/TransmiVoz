import assert from "node:assert/strict"
import test from "node:test"
import snapshot from "../data/transmilenio.json" with { type: "json" }
import { parseIntentWithOllama } from "./ollama"
import { TransmilenioDataSchema } from "./transmilenio"

const data = TransmilenioDataSchema.parse(snapshot)

/** Simula la respuesta de Ollama con el JSON que "devolvería" el modelo. */
function withModelOutput(content: unknown, run: () => Promise<void>) {
  return async () => {
    const original = globalThis.fetch
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ message: { content: typeof content === "string" ? content : JSON.stringify(content) } }))
    try {
      await run()
    } finally {
      globalThis.fetch = original
    }
  }
}

const extraction = (fields: Record<string, string>) => ({ intent: "trip", origin: "", destination: "", routeCode: "", ...fields })

test(
  "traduce la salida del modelo a una intención con nombres de los datos",
  withModelOutput(extraction({ origin: "ricaurte", destination: "universidad nacional" }), async () => {
    assert.deepEqual(await parseIntentWithOllama("…", data), {
      type: "trip",
      origin: "Ricaurte",
      destination: "Universidad Nacional",
    })
  }),
)

test(
  "si el modelo nombra un origen que no existe, vuelve a las reglas",
  withModelOutput(extraction({ origin: "Narnia", destination: "Ricaurte" }), async () => {
    assert.equal(await parseIntentWithOllama("…", data), null)
  }),
)

test(
  "si el modelo inventa una ruta, vuelve a las reglas",
  withModelOutput(extraction({ intent: "schedule", routeCode: "Z999" }), async () => {
    assert.equal(await parseIntentWithOllama("…", data), null)
  }),
)

test(
  "si el modelo no devuelve JSON, vuelve a las reglas",
  withModelOutput("no es json", async () => {
    assert.equal(await parseIntentWithOllama("…", data), null)
  }),
)

test(
  "realtime: el modelo aporta ruta y estación (validadas) y el tema sale de la frase",
  withModelOutput(extraction({ intent: "realtime", routeCode: "b10", destination: "calle 100" }), async () => {
    assert.deepEqual(await parseIntentWithOllama("¿cuándo pasa el B10 por la 100?", data), {
      type: "tiempo_real",
      consulta: { tema: "llegadas", ruta: "B10", parada: "Calle 100" },
    })
    // Una frase de novedades conserva su tema aunque el modelo la llame realtime.
    assert.deepEqual(await parseIntentWithOllama("¿hay desvíos en el B10?", data), {
      type: "tiempo_real",
      consulta: { tema: "novedades", ruta: "B10", parada: "Calle 100" },
    })
    // «dónde viene el B10» es dónde está la ruta, no una llegada a una estación.
    assert.deepEqual(await parseIntentWithOllama("dónde viene el B10", { ...data }), {
      type: "tiempo_real",
      consulta: { tema: "buses", ruta: "B10" },
    })
  }),
)

test(
  "realtime: una ruta o estación inventada por el modelo no llega a la consulta",
  withModelOutput(extraction({ intent: "realtime", routeCode: "Z999", destination: "Narnia" }), async () => {
    assert.deepEqual(await parseIntentWithOllama("cuándo llega el bus", data), { type: "tiempo_real", consulta: { tema: "llegadas", ruta: undefined, parada: undefined } })
  }),
)

test(
  "R1·8 la espera que recibe del presupuesto puede ser fraccionaria (AbortSignal.timeout exige un entero)",
  withModelOutput(extraction({ intent: "greeting" }), async () => {
    assert.deepEqual(await parseIntentWithOllama("hola", data, 2_073.505213), { type: "greeting" })
  }),
)
