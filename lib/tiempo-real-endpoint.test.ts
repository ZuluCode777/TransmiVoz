import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test, { mock } from "node:test"
import { pathToFileURL } from "node:url"
import { conEntorno } from "./ea10-entorno-pruebas"
import { decidirAccesoDeEntorno, respuestaDeDecision } from "./autenticacion"
import {
  LIMITE_TIEMPO_REAL,
  MAXIMO_BYTES_CUERPO,
  PeticionTiempoRealSchema,
  RespuestaBusesRutaSchema,
  RespuestaLlegadasSchema,
  RespuestaParadasCercanasSchema,
} from "./contrato-tiempo-real"
import { instalarFeeds } from "./fixtures-gtfs/entorno"

/**
 * `POST /api/tiempo-real`: acceso (HTTP Basic por el `proxy`), validación con zod,
 * límite de peticiones y respuestas con los feeds reales de la muestra, sin red.
 * El reloj se fija en la hora de las muestras para que su frescura sea la de ayer.
 */

const raiz = pathToFileURL(process.cwd() + "/")
let caso = 0

async function conEndpoint(opciones: { segundosDespues?: number } = {}) {
  const entorno = instalarFeeds(opciones)
  // ArcGIS cae (se usa la copia del catálogo) y el reloj queda fijo en la hora de las muestras.
  const fetchSimulado = mock.method(globalThis, "fetch", async () => {
    throw new Error("sin red (prueba de tiempo real)")
  })
  mock.timers.enable({ apis: ["Date"], now: entorno.reloj.ms })
  const modulo: typeof import("../app/api/tiempo-real/route") = await import(new URL(`app/api/tiempo-real/route.ts?caso=${caso++}`, raiz).href)
  return {
    entorno,
    modulo,
    restaurar: () => {
      mock.timers.reset()
      fetchSimulado.mock.restore()
    },
  }
}

const post = (cuerpo: unknown, crudo = false) =>
  new Request("http://local/api/tiempo-real", { method: "POST", body: crudo ? String(cuerpo) : JSON.stringify(cuerpo) })

async function consultar(cuerpo: unknown, opciones?: { segundosDespues?: number }) {
  const e = await conEndpoint(opciones)
  try {
    const res = await e.modulo.POST(post(cuerpo))
    return { status: res.status, json: await res.json(), res }
  } finally {
    e.restaurar()
  }
}

// ── Acceso ──

/** Lo mismo que hace `ea10-proxy-matcher.test.ts`: `proxy.ts` no se puede cargar en Node, así que se lee su matcher. */
const literal = /matcher:\s*\[("(?:[^"\\]|\\.)*")\]/.exec(readFileSync("proxy.ts", "utf8"))?.[1]
const matcher: string = JSON.parse(literal!)
const credencialesBasic = (c: string) => `Basic ${Buffer.from(c).toString("base64")}`

test("acceso: /api/tiempo-real pasa por el proxy, así que exige HTTP Basic como el resto de la app", async () => {
  assert.equal(new RegExp(`^${matcher}$`).test("/api/tiempo-real"), true, "no está excluida del proxy")
  await conEntorno({ nodeEnv: "production", clave: "clave-de-prueba" }, () => {
    // La misma decisión que aplica el `proxy` a esa ruta.
    const estado = (autorizacion: string | null) => {
      const decision = decidirAccesoDeEntorno({ autorizacion })
      return decision.kind === "permitido" ? 200 : respuestaDeDecision(decision).estado
    }
    assert.equal(estado(null), 401, "sin credencial")
    assert.equal(estado(credencialesBasic("x:incorrecta")), 401, "credencial incorrecta")
    assert.equal(estado(credencialesBasic("x:clave-de-prueba")), 200, "credencial correcta")
  })
  await conEntorno({ nodeEnv: "production", clave: "" }, () => {
    const sinClave = decidirAccesoDeEntorno({ autorizacion: null })
    assert.equal(sinClave.kind === "permitido" ? 200 : respuestaDeDecision(sinClave).estado, 503, "en producción sin clave la app no se abre")
  })
})

test("el endpoint solo acepta POST", async () => {
  const e = await conEndpoint()
  try {
    assert.equal((e.modulo as Record<string, unknown>).GET, undefined)
  } finally {
    e.restaurar()
  }
})

// ── Validación ──

test("validación: el esquema rechaza lo que no es una operación válida", () => {
  const malas: unknown[] = [
    {},
    { operacion: "borrar-todo" },
    { operacion: "llegadas" },
    { operacion: "llegadas", parada: "" },
    { operacion: "llegadas", parada: "x".repeat(81) },
    { operacion: "llegadas", parada: "Calle 100", max: 0 },
    { operacion: "llegadas", parada: "Calle 100", max: 21 },
    { operacion: "llegadas", parada: 5 },
    { operacion: "paradas-cercanas", lat: 91, lng: 0 },
    { operacion: "paradas-cercanas", lat: 0, lng: -181 },
    { operacion: "paradas-cercanas", lat: "4.6", lng: -74 },
    { operacion: "paradas-cercanas", lat: 4.6, lng: -74, radio: 5_001 },
    { operacion: "paradas-cercanas", lat: 4.6, lng: -74, radio: -1 },
    { operacion: "buses-cercanos", lat: 4.6 },
    { operacion: "buscar-paradas" },
    "llegadas",
    null,
  ]
  for (const mala of malas) assert.equal(PeticionTiempoRealSchema.safeParse(mala).success, false, JSON.stringify(mala))
  for (const buena of [
    { operacion: "estado-sistema" },
    { operacion: "llegadas", parada: "Calle 100", ruta: "B10", max: 3 },
    { operacion: "paradas-cercanas", lat: 4.6, lng: -74.07, radio: 800, conLlegadas: true },
  ]) {
    assert.equal(PeticionTiempoRealSchema.safeParse(buena).success, true, JSON.stringify(buena))
  }
})

test("validación: JSON inválido y esquema inválido → 400; cuerpo enorme → 413", async () => {
  const e = await conEndpoint()
  try {
    assert.equal((await e.modulo.POST(post("{no es json", true))).status, 400)
    assert.deepEqual(await (await e.modulo.POST(post({ operacion: "borrar-todo" }))).json(), { error: "peticion-invalida" })
    const grande = await e.modulo.POST(post({ operacion: "buscar-paradas", consulta: "a".repeat(MAXIMO_BYTES_CUERPO + 10) }))
    assert.equal(grande.status, 413)
  } finally {
    e.restaurar()
  }
})

test("ruta, parada o bus desconocidos → 404 sin adivinar", async () => {
  assert.deepEqual((await consultar({ operacion: "buses-ruta", ruta: "ZZ999" })).json, { error: "ruta-desconocida" })
  assert.deepEqual((await consultar({ operacion: "llegadas", parada: "Narnia", ruta: "B10" })).json, { error: "parada-desconocida" })
  assert.deepEqual((await consultar({ operacion: "proximas-paradas-bus", bus: "ZZ99-0000" })).json, { error: "bus-desconocido" })
  assert.equal((await consultar({ operacion: "horario-ruta", ruta: "ZZ999" })).status, 404)
})

// ── Respuestas ──

test("llegadas: minutos, sentido, retraso y edad del dato, con el esquema del contrato", async () => {
  const { status, json } = await consultar({ operacion: "llegadas", parada: "Calle 100", ruta: "B10", max: 3 })
  assert.equal(status, 200)
  const r = RespuestaLlegadasSchema.parse(json)
  assert.equal(r.motivo, null)
  assert.ok(r.llegadas.length >= 1 && r.llegadas.length <= 3)
  assert.ok(r.llegadas.every((l) => l.codigo === "B10" && l.destino === "Portal Norte"))
  assert.equal(r.meta.edadDatosS, 20)
  assert.equal(r.meta.detenido, false)
  assert.equal(r.meta.copiaObsoleta, false)
  assert.equal(r.meta.indicePublicado, "2026-11-17")
})

test("llegadas: una ruta que no pasa por la parada lo dice con su motivo", async () => {
  const { json } = await consultar({ operacion: "llegadas", parada: "Calle 72", ruta: "B10" })
  assert.equal(RespuestaLlegadasSchema.parse(json).motivo, "ruta-no-pasa-por-parada")
})

test("buses de una ruta, sin importar cómo se escriba el código", async () => {
  for (const ruta of ["8 G", "8g", "8G"]) {
    const r = RespuestaBusesRutaSchema.parse((await consultar({ operacion: "buses-ruta", ruta })).json)
    assert.deepEqual(r.destinos, ["Guatoque"], ruta)
    assert.ok(r.buses.length > 0 && r.buses.every((b) => b.rutaId === "13307"), ruta)
  }
})

test("paradas cercanas con sus próximas llegadas; la coordenada de la persona no vuelve en la respuesta", async () => {
  const e = await conEndpoint()
  const registros: string[] = []
  const espias = (["log", "info", "warn", "error", "debug"] as const).map((n) => mock.method(console, n, (...a: unknown[]) => void registros.push(a.join(" "))))
  try {
    const res = await e.modulo.POST(post({ operacion: "paradas-cercanas", lat: 4.67639123, lng: -74.05896456, radio: 400, max: 3, conLlegadas: true }))
    const texto = await res.text()
    const r = RespuestaParadasCercanasSchema.parse(JSON.parse(texto))
    assert.ok(r.paradas.some((p) => p.nombre === "Virrey - Cendiatra"))
    assert.ok(r.paradas.every((p) => p.llegadas !== undefined))
    assert.doesNotMatch(texto, /4\.67639123|74\.05896456/)
    assert.deepEqual(registros.filter((l) => /4\.676|74\.058/.test(l)), [], "no registra la coordenada")
  } finally {
    for (const espia of espias) espia.mock.restore()
    e.restaurar()
  }
})

test("el resto de operaciones responden 200 con su forma", async () => {
  const casos: [unknown, (j: any) => void][] = [
    [{ operacion: "buscar-paradas", consulta: "CALLE 72" }, (j) => assert.ok(j.paradas.some((p: { nombre: string }) => p.nombre === "Calle 72 - Areandina"))],
    [{ operacion: "estado-sistema" }, (j) => assert.equal(j.sistema.total, 50)],
    [{ operacion: "horario-ruta", ruta: "B10" }, (j) => assert.equal(j.horarios[0].primera, "04:30")],
    [{ operacion: "alertas", ruta: "B10" }, (j) => assert.deepEqual(j.alertas, [])],
    [{ operacion: "buses-cercanos", lat: 4.67514, lng: -74.05911, radio: 200 }, (j) => assert.ok(j.buses.length >= 1)],
    [{ operacion: "proximas-paradas-bus", bus: "N0163" }, (j) => assert.ok(j.paradas.length >= 1 && j.bus.codigo === "B10")],
    [{ operacion: "cancelados-hoy" }, (j) => assert.ok(j.cancelados === null || j.cancelados.total >= 0)],
    [{ operacion: "salud-feeds" }, (j) => assert.equal(j.feeds.length, 3)],
  ]
  for (const [cuerpo, verificar] of casos) {
    const { status, json } = await consultar(cuerpo)
    assert.equal(status, 200, JSON.stringify(cuerpo))
    assert.ok(json.meta, "toda respuesta trae meta")
    verificar(json)
  }
})

// ── Fuentes caídas, detenidas o vencidas ──

test("feed caído sin copia → 503 con Retry-After; el horario, que no usa feeds, sigue", async () => {
  const e = await conEndpoint()
  try {
    e.entorno.estado.falla = true
    const res = await e.modulo.POST(post({ operacion: "buses-ruta", ruta: "B10" }))
    assert.equal(res.status, 503)
    assert.equal(res.headers.get("Retry-After"), "15")
    assert.deepEqual(await res.json(), { error: "feed-no-disponible" })
    assert.equal((await e.modulo.POST(post({ operacion: "horario-ruta", ruta: "B10" }))).status, 200)
  } finally {
    e.restaurar()
  }
})

test("feed detenido (cabecera de más de 300 s): meta.detenido y ningún bus", async () => {
  const { json } = await consultar({ operacion: "buses-ruta", ruta: "B10" }, { segundosDespues: 400 })
  assert.equal(json.meta.detenido, true)
  assert.deepEqual(json.buses, [])
})

test("índice vencido → 503 indice-vencido; salud-feeds sigue respondiendo", async () => {
  const e = await conEndpoint()
  try {
    mock.timers.reset()
    mock.timers.enable({ apis: ["Date"], now: Date.parse("2027-01-15T10:00:00-05:00") })
    assert.deepEqual(await (await e.modulo.POST(post({ operacion: "estado-sistema" }))).json(), { error: "indice-vencido" })
    assert.equal((await e.modulo.POST(post({ operacion: "salud-feeds" }))).status, 200)
  } finally {
    e.restaurar()
  }
})

// ── Límite de peticiones ──

test(`límite: la petición ${LIMITE_TIEMPO_REAL + 1} del minuto → 429 con Retry-After`, async () => {
  const e = await conEndpoint()
  try {
    for (let n = 0; n < LIMITE_TIEMPO_REAL; n++) assert.equal((await e.modulo.POST(post({ operacion: "buscar-paradas", consulta: "calle" }))).status, 200)
    const res = await e.modulo.POST(post({ operacion: "buscar-paradas", consulta: "calle" }))
    assert.equal(res.status, 429)
    assert.ok(Number(res.headers.get("Retry-After")) >= 1)
    assert.deepEqual(await res.json(), { error: "demasiadas-peticiones" })
  } finally {
    e.restaurar()
  }
})

// ── Revisión R1 ──

test("R1·2 una parada ambigua → 409 con las opciones; una exacta del GTFS se resuelve", async () => {
  const ambigua = await consultar({ operacion: "llegadas", parada: "Pq. El Virrey" })
  assert.equal(ambigua.status, 409)
  assert.equal(ambigua.json.error, "parada-ambigua")
  assert.ok(Array.isArray(ambigua.json.opciones) && ambigua.json.opciones.length >= 1)
  const parecidas = await consultar({ operacion: "alertas", parada: "Plazuelas" })
  assert.equal(parecidas.status, 409)
  assert.ok(parecidas.json.opciones.length >= 2)
  const exacta = await consultar({ operacion: "alertas", parada: "Br. El Virrey" })
  assert.equal(exacta.status, 200)
  assert.equal(exacta.json.parada, "Br. El Virrey")
})

test("R1·6 meta dice el estado de CADA feed: con tripupdates detenido y posiciones al día, no lo esconde", async () => {
  const e = await conEndpoint()
  try {
    e.entorno.estado.retrasosAtrasados = 400
    const pedir = async () => (await e.modulo.POST(post({ operacion: "llegadas", parada: "Calle 100", ruta: "B10" }))).json()
    const primera = await pedir() // arranca la lectura de tripupdates, que no se espera
    assert.equal(primera.meta.retrasos, "sin-datos")
    assert.equal(primera.meta.feeds.retrasos, null)
    await new Promise((ok) => setTimeout(ok, 50))
    const { meta } = RespuestaLlegadasSchema.parse(await pedir())
    assert.equal(meta.detenido, false, "las posiciones están al día")
    assert.equal(meta.retrasos, "detenido")
    assert.deepEqual(meta.feeds.posiciones, { edadS: 20, detenido: false, copiaObsoleta: false })
    assert.equal(meta.feeds.retrasos?.detenido, true)
    assert.equal(meta.feeds.retrasos?.edadS, 420)
    assert.equal(meta.feeds.alertas, null, "las alertas no se leyeron")
    const cancelados = await (await e.modulo.POST(post({ operacion: "cancelados-hoy" }))).json()
    assert.equal(cancelados.cancelados, null, "no se cuentan cancelados con un feed detenido")
    assert.equal(cancelados.meta.retrasos, "detenido")
  } finally {
    e.restaurar()
  }
})
