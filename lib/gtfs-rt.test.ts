import assert from "node:assert/strict"
import test from "node:test"
import { crearFuentes, decodificarAlertas, decodificarPosiciones, decodificarRetrasos, epocaBogota, saludDeFeeds } from "@/lib/gtfs-rt"
import * as bindings from "gtfs-realtime-bindings"
import { bytesDe, CABECERA_MUESTRA } from "@/lib/fixtures-gtfs/cargar"

const rt = ((bindings as unknown as { default?: typeof bindings }).default ?? bindings).transit_realtime
const NOMBRES = { "positions.pb": "positions", "alerts.pb": "alerts", "tripupdates.pb": "tripupdates" } as const

/** Fetch simulado que sirve las muestras reales como `text/plain` (como el servidor real) y cuenta las lecturas. */
function red() {
  const llamadas: { url: string; headers: Record<string, string> }[] = []
  let falla: string | null = null
  let cuerpoRaro: string | null = null
  const fetchFn = (async (url: string, init?: RequestInit) => {
    llamadas.push({ url, headers: init?.headers as Record<string, string> })
    if (falla) throw new Error(falla)
    if (cuerpoRaro) return new Response(cuerpoRaro, { status: 200, headers: { "content-type": "text/html" } })
    const archivo = url.split("/").pop() as keyof typeof NOMBRES
    return new Response(bytesDe(NOMBRES[archivo]), { status: 200, headers: { "content-type": "text/plain" } })
  }) as unknown as typeof fetch
  return {
    fetchFn,
    llamadas,
    fallar: (mensaje: string | null) => (falla = mensaje),
    cuerpoRaro: (cuerpo: string | null) => (cuerpoRaro = cuerpo),
  }
}

test("decodifica las muestras reales con el paquete oficial", () => {
  const posiciones = decodificarPosiciones(rt.FeedMessage.decode(bytesDe("positions")))
  assert.equal(posiciones.cabecera, CABECERA_MUESTRA)
  assert.equal(posiciones.datos.vehiculos.length, 50)
  const bus = posiciones.datos.vehiculos.find((v) => v.rutaId === "10075")!
  assert.match(bus.etiqueta, /^\w+$/)
  assert.ok(bus.lat > 4 && bus.lat < 5 && bus.lng < -73 && bus.lng > -75)
  assert.ok(bus.ts > 1_700_000_000)

  const alertas = decodificarAlertas(rt.FeedMessage.decode(bytesDe("alerts"))).datos.alertas
  assert.ok(alertas.length > 0)
  assert.ok(alertas.every((a) => a.efecto === "DETOUR" && a.titulo !== "" && a.periodos.length === 1))

  const retrasos = decodificarRetrasos(rt.FeedMessage.decode(bytesDe("tripupdates"))).datos
  const relaciones = [...retrasos.porViaje.values()].reduce<Record<string, number>>((c, v) => ({ ...c, [v.rel]: (c[v.rel] ?? 0) + 1 }), {})
  assert.deepEqual(relaciones, { SCHEDULED: 1401, ADDED: 19, CANCELED: 78 })
  assert.ok(retrasos.porVehiculo.size > 0)
})

test("epocaBogota: fecha y hora de Bogotá (UTC-5) y horas pasadas de 24", () => {
  assert.equal(epocaBogota("20261117", "20:24:28"), Date.parse("2026-11-17T20:24:28-05:00") / 1000)
  assert.equal(epocaBogota("20261117", "24:30:00"), Date.parse("2026-11-18T00:30:00-05:00") / 1000)
  assert.equal(epocaBogota("basura", "20:24:28"), null)
})

test("caché: una sola lectura por feed y TTL, aunque lleguen varias consultas a la vez", async () => {
  const { fetchFn, llamadas } = red()
  let reloj = 1_000_000
  const { posiciones } = crearFuentes({ fetchFn, ahora: () => reloj })
  const [a, b, c] = await Promise.all([posiciones.leer(), posiciones.leer(), posiciones.leer()])
  assert.equal(llamadas.length, 1)
  assert.equal(a, b)
  assert.equal(b, c)
  reloj += 14_000
  await posiciones.leer()
  assert.equal(llamadas.length, 1, "dentro de los 15 s no se vuelve a pedir")
  reloj += 2_000
  await posiciones.leer()
  assert.equal(llamadas.length, 2, "vencido el TTL se pide otra vez")
})

test("la petición lleva un User-Agent amable, sin datos personales", async () => {
  const { fetchFn, llamadas } = red()
  await crearFuentes({ fetchFn }).alertas.leer()
  const agente = llamadas[0].headers["User-Agent"]
  assert.ok(agente.length > 10)
  assert.doesNotMatch(agente, /@|nicolas|zuloaga|visionaria/i)
  assert.equal(llamadas[0].url, "https://gtfs.transmilenio.gov.co/alerts.pb")
})

test("si la lectura falla y hay copia anterior, se devuelve esa copia marcada como obsoleta", async () => {
  const red1 = red()
  let reloj = 1_000_000
  const { posiciones } = crearFuentes({ fetchFn: red1.fetchFn, ahora: () => reloj })
  const buena = await posiciones.leer()
  assert.equal(buena.obsoleto, false)
  red1.fallar("ECONNRESET https://gtfs.transmilenio.gov.co/positions.pb")
  reloj += 20_000
  const vieja = await posiciones.leer()
  assert.equal(vieja.obsoleto, true)
  assert.equal(vieja.datos, buena.datos)
  const salud = posiciones.salud()
  assert.equal(salud.obsoleto, true)
  assert.ok(salud.ultimoError)
  red1.fallar(null)
  reloj += 5_000
  assert.equal((await posiciones.leer()).obsoleto, false, "al volver la red se recupera")
})

test("sin copia anterior, un fallo se propaga", async () => {
  const r = red()
  r.fallar("sin red")
  await assert.rejects(crearFuentes({ fetchFn: r.fetchFn }).posiciones.leer(), /positions/)
})

test("un cuerpo que no es protobuf de TransMilenio (la página de un proxy) cuenta como fallo", async () => {
  const r = red()
  r.cuerpoRaro("<html>Acceso denegado</html>")
  await assert.rejects(crearFuentes({ fetchFn: r.fetchFn }).alertas.leer())
})

test("salud: la cabecera de más de 300 s deja el feed detenido", async () => {
  const { fetchFn } = red()
  let reloj = (CABECERA_MUESTRA + 100) * 1000
  const fuentes = crearFuentes({ fetchFn, ahora: () => reloj })
  await fuentes.posiciones.leer()
  assert.equal(fuentes.posiciones.salud().detenido, false)
  assert.equal(fuentes.posiciones.salud().edadCabeceraS, 100)
  reloj = (CABECERA_MUESTRA + 301) * 1000
  assert.equal(fuentes.posiciones.salud().detenido, true)
  assert.equal(saludDeFeeds(fuentes)[2].conCopia, false)
})

test("tripupdates: no se espera en la petición; en frío no hay copia y después la hay", async () => {
  const r = red()
  let reloj = 1_000_000
  const { retrasos } = crearFuentes({ fetchFn: r.fetchFn, ahora: () => reloj })
  assert.equal(retrasos.leerSinEsperar(), null, "arranque en frío: responde sin retrasos")
  assert.equal(r.llamadas.length, 1, "pero lanzó el refresco")
  assert.equal(retrasos.leerSinEsperar(), null, "sin lanzar otro mientras el primero sigue en curso")
  assert.equal(r.llamadas.length, 1)
  await new Promise((ok) => setTimeout(ok, 20))
  const copia = retrasos.leerSinEsperar()
  assert.ok(copia && copia.datos.total > 1000)
  assert.equal(r.llamadas.length, 1)
  reloj += 61_000
  assert.equal(retrasos.leerSinEsperar(), copia, "vencido el TTL de 60 s usa la copia y refresca aparte")
  assert.equal(r.llamadas.length, 2)
})

// ── Revisión R1 ──

test("R1·7 reintento: tras un fallo, tres consultas seguidas son UNA descarga; pasada la espera, otra", async () => {
  const r = red()
  r.fallar("sin red")
  let reloj = 1_000_000
  const { posiciones } = crearFuentes({ fetchFn: r.fetchFn, ahora: () => reloj })
  for (let n = 0; n < 3; n++) await assert.rejects(posiciones.leer())
  assert.equal(r.llamadas.length, 1, "antes: tres descargas fallidas seguidas")
  reloj += 4_999
  await assert.rejects(posiciones.leer())
  assert.equal(r.llamadas.length, 1, "dentro de los 5 s de espera no se reintenta")
  reloj += 1
  await assert.rejects(posiciones.leer())
  assert.equal(r.llamadas.length, 2, "cumplida la espera, un intento más")
  r.fallar(null)
  reloj += 5_000
  assert.equal((await posiciones.leer()).obsoleto, false, "al volver la red se recupera y se borra la espera")
})

test("R1·7 con copia anterior y la fuente caída, las consultas usan la copia sin volver a pedir durante la espera", async () => {
  const r = red()
  let reloj = 1_000_000
  const { posiciones, retrasos } = crearFuentes({ fetchFn: r.fetchFn, ahora: () => reloj })
  await posiciones.leer()
  r.fallar("sin red")
  reloj += 20_000
  for (let n = 0; n < 3; n++) assert.equal((await posiciones.leer()).obsoleto, true)
  assert.equal(r.llamadas.length, 2, "una lectura buena y un solo intento fallido")
  // tripupdates espera más (30 s) por su peso.
  assert.equal(retrasos.leerSinEsperar(), null)
  await new Promise((ok) => setTimeout(ok, 20))
  assert.equal(r.llamadas.filter((l) => l.url.endsWith("tripupdates.pb")).length, 1)
  retrasos.leerSinEsperar()
  reloj += 29_000
  retrasos.leerSinEsperar()
  assert.equal(r.llamadas.filter((l) => l.url.endsWith("tripupdates.pb")).length, 1, "dentro de los 30 s no se vuelve a pedir")
})

/** Fetch que responde con las muestras, pero tarda `demoraMs` y anota cuántas descargas se lanzaron. */
function redLenta(demoraMs: number) {
  const estado = { llamadas: 0 }
  const fetchFn = (async (url: string) => {
    estado.llamadas++
    await new Promise((ok) => setTimeout(ok, demoraMs))
    const archivo = url.split("/").pop() as keyof typeof NOMBRES
    return new Response(bytesDe(NOMBRES[archivo]), { status: 200 })
  }) as unknown as typeof fetch
  return { fetchFn, estado }
}

test("R1·8 con presupuesto: copia vencida y poco margen → usa la copia YA y renueva aparte; sin copia, espera solo el presupuesto", async () => {
  const lenta = redLenta(300)
  let reloj = 1_000_000
  const { posiciones } = crearFuentes({ fetchFn: lenta.fetchFn, ahora: () => reloj })
  // Sin copia: solo se espera el presupuesto (50 ms) y, como no llegó nada, falla.
  const t0 = performance.now()
  await assert.rejects(posiciones.leer(50))
  assert.ok(performance.now() - t0 < 200, `esperó ${Math.round(performance.now() - t0)} ms con 50 de presupuesto`)
  // La descarga siguió y deja copia.
  await new Promise((ok) => setTimeout(ok, 400))
  assert.equal(lenta.estado.llamadas, 1)
  // Copia vencida y presupuesto menor que la espera de descarga (3,5 s): responde con la copia al instante.
  reloj += 20_000
  const t1 = performance.now()
  const copia = await posiciones.leer(1_000)
  assert.ok(performance.now() - t1 < 100, "no espera la descarga")
  assert.ok(copia.datos.vehiculos.length > 0)
  assert.equal(lenta.estado.llamadas, 2, "pero la renovación se lanzó")
  await new Promise((ok) => setTimeout(ok, 400))
  assert.equal(lenta.estado.llamadas, 2, "una sola renovación aunque llegaran más consultas")
})
