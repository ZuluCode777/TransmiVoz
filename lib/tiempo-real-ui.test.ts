import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test, { mock } from "node:test"
import vm from "node:vm"
import * as jsx from "react/jsx-runtime"
import ts from "typescript"
import * as contrato from "./contrato-tiempo-real"
import * as geo from "./geo"
import * as textos from "./texto-tiempo-real"

/**
 * Los componentes de datos en vivo (`components/en-vivo.tsx`), ejecutados con dobles
 * mínimos de React y del hook de consulta, sin navegador. Cubre lo que decide la
 * pantalla para quien usa lector de pantalla: qué texto lleva cada valor («en vivo»,
 * «estimado», «datos de hace N segundos»), que haya UNA región viva `polite` por
 * bloque, que no anuncie en cada renovación, y los avisos de error y de fuente detenida.
 */

type Elemento = { type: unknown; props: Record<string, unknown> }
const raiz = process.cwd()

function compilar(archivo: string, dobles: Record<string, unknown>) {
  const salida = ts.transpileModule(readFileSync(`${raiz}/${archivo}`, "utf8"), {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
  }).outputText
  const require = (nombre: string) => {
    if (nombre === "react/jsx-runtime") return jsx
    if (nombre === "@/lib/contrato-tiempo-real") return contrato
    if (nombre === "@/lib/geo") return geo
    if (nombre === "@/lib/texto-tiempo-real") return textos
    if (nombre in dobles) return dobles[nombre]
    if (nombre === "lucide-react") return new Proxy({}, { get: (_o, n) => function Icono() { void n } })
    throw new Error(`Import no previsto: ${nombre}`)
  }
  const modulo = { exports: {} as Record<string, unknown> }
  vm.runInNewContext(`(function(require,module,exports){${salida}\n})`, { Date, setTimeout, clearTimeout })(require, modulo, modulo.exports)
  return modulo.exports
}

function nodos(el: unknown, pred: (n: Elemento) => boolean): Elemento[] {
  if (!el || typeof el !== "object") return []
  if (Array.isArray(el)) return el.flatMap((n) => nodos(n, pred))
  const e = el as Elemento
  if (typeof e.type === "function") return nodos((e.type as (p: object) => unknown)(e.props), pred) // expande componentes propios (Encabezado)
  return [...(pred(e) ? [e] : []), ...nodos(e.props?.children, pred)]
}
function texto(el: unknown): string {
  if (Array.isArray(el)) return el.map(texto).join("")
  if (typeof el === "string" || typeof el === "number") return String(el)
  if (el && typeof el === "object") {
    const e = el as Elemento
    return typeof e.type === "function" ? texto((e.type as (p: object) => unknown)(e.props)) : texto(e.props?.children)
  }
  return ""
}

/** Monta con `useState`/`useEffect`/`useRef` de verdad; los efectos corren tras cada render. */
function montar(exportado: string, props: object, dobles: Record<string, unknown>) {
  const estados: unknown[] = []
  const refs: { current: unknown }[] = []
  const efectos: { deps: unknown[]; limpieza?: void | (() => void) }[] = []
  let arbol: unknown
  let hu = 0
  let hr = 0
  let he = 0
  let pendientes: (() => void)[] = []
  const react = {
    useState: (inicial: unknown) => {
      const i = hu++
      if (!(i in estados)) estados[i] = inicial
      return [estados[i], (v: unknown) => { estados[i] = v; render() }]
    },
    useRef: (inicial: unknown) => (refs[hr] ??= { current: inicial }) && refs[hr++],
    useEffect: (fn: () => void | (() => void), deps: unknown[]) => {
      const i = he++
      const previo = efectos[i]
      if (previo && deps.every((d, k) => d === previo.deps[k])) return
      pendientes.push(() => {
        if (typeof previo?.limpieza === "function") previo.limpieza()
        efectos[i] = { deps }
        efectos[i].limpieza = fn()
      })
    },
  }
  const modulo = compilar("components/en-vivo.tsx", { ...dobles, react })
  const componente = modulo[exportado] as (p: object) => unknown
  function render() {
    hu = 0
    hr = 0
    he = 0
    arbol = componente(props)
    const lista = pendientes
    pendientes = []
    lista.forEach((f) => f())
  }
  render()
  return { arbol: () => arbol, redibujar: render, desmontar: () => efectos.forEach((e) => typeof e.limpieza === "function" && e.limpieza()) }
}

const meta = { edadDatosS: 40, detenido: false, copiaObsoleta: false, retrasos: "disponibles", indicePublicado: "2026-11-17", feeds: { posiciones: null, alertas: null, retrasos: null } }
const llegada = (extra: object = {}) => ({
  rutaId: "10075", codigo: "B10", destino: "Portal Norte", sistema: "troncal", paradaId: "61177", paradaNombre: "Calle 100",
  segundos: 240, origen: "en-vivo", bus: "N0163", retraso: null, edad: 40, adicional: false, ...extra,
})

/** Dobles: el hook devuelve lo que la prueba fije; la voz anota lo que se le pide decir. */
function entorno(resultado: object) {
  const estado = { resultado, dicho: [] as string[] }
  return {
    estado,
    dobles: {
      "@/hooks/use-tiempo-real": { useTiempoReal: () => estado.resultado },
      "@/hooks/use-speech": { useSpeech: () => ({ speak: (t: string) => estado.dicho.push(t) }) },
    },
  }
}
const ok = (datos: object, extra: object = {}) => ({ estado: "ok", datos, actualizadoEn: 1, ...extra })

test("llegadas: dice «en vivo», «estimado», minutos, sentido y la edad del dato", () => {
  const e = entorno(ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada(), llegada({ segundos: 840, bus: null, origen: "programado", retraso: 300 })] }))
  const m = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, e.dobles)
  const t = texto(m.arbol())
  assert.match(t, /En vivo · estimado/)
  assert.match(t, /B10 hacia Portal Norte: llega en unos 4 minutos, estimado\. Bus N0163/)
  assert.match(t, /según la programación, llegaría en unos 14 minutos, estimado, con unos 5 minutos de retraso reportado/)
  assert.match(t, /Datos de hace 40 segundos/)
  m.desmontar()
})

test("región viva: una sola `polite` por bloque, sin ser la lista visible", () => {
  const e = entorno(ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada()] }))
  const m = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, e.dobles)
  const vivas = nodos(m.arbol(), (n) => n.props["aria-live"] === "polite")
  assert.equal(vivas.length, 1)
  assert.equal(vivas[0].props.role, "status")
  assert.match(String(vivas[0].props.className), /sr-only/)
  assert.deepEqual(nodos(vivas[0], (n) => n.type === "ul"), [], "la lista no es región viva")
  m.desmontar()
})

test("región viva: anuncia una vez, y un cambio solo pasado un minuto", () => {
  mock.timers.enable({ apis: ["setTimeout", "Date"], now: 1_000_000 })
  try {
    const e = entorno(ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada({ segundos: 240 })] }))
    const m = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, e.dobles)
    const viva = () => texto(nodos(m.arbol(), (n) => n.props["aria-live"] === "polite")[0])
    assert.equal(viva(), "")
    mock.timers.tick(1)
    assert.match(viva(), /llega a Calle 100 en unos 4 minutos, estimado/)
    // Cambia la frase a los 20 s: no se anuncia todavía.
    e.estado.resultado = ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada({ segundos: 120 })] })
    mock.timers.tick(20_000)
    m.redibujar()
    mock.timers.tick(20_000)
    assert.match(viva(), /en unos 4 minutos/, "sigue la frase anterior")
    mock.timers.tick(40_000)
    assert.match(viva(), /en unos 2 minutos/, "pasado el minuto, anuncia el cambio")
    m.desmontar()
  } finally {
    mock.timers.reset()
  }
})

test("llegadas: un botón dice el resumen con la voz de la app", () => {
  const e = entorno(ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada()] }))
  const m = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, e.dobles)
  const [boton] = nodos(m.arbol(), (n) => n.type === "button")
  assert.match(String(boton.props["aria-label"]), /^Escuchar: Llegadas a Calle 100/)
  ;(boton.props.onClick as () => void)()
  assert.deepEqual(e.estado.dicho, ["La B10 hacia Portal Norte llega a Calle 100 en unos 4 minutos, estimado. Datos de hace 40 segundos."])
  m.desmontar()
})

test("llegadas: sin datos, con la fuente detenida y con copia anterior, lo dice en texto", () => {
  const sin = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, entorno({ estado: "error", datos: null, actualizadoEn: null }).dobles)
  assert.match(texto(sin.arbol()), /No pude consultar los datos en vivo ahora\. Confirma el horario con TransMilenio/)
  const detenida = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, entorno(ok({ operacion: "llegadas", meta: { ...meta, detenido: true, edadDatosS: 900 }, parada: "Calle 100", ruta: "B10", motivo: "feed-detenido", llegadas: [] })).dobles)
  assert.match(texto(detenida.arbol()), /no se están actualizando, así que no estimo llegadas/)
  const vieja = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, entorno(ok({ operacion: "llegadas", meta: { ...meta, copiaObsoleta: true }, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada()] })).dobles)
  assert.match(texto(vieja.arbol()), /no pude actualizar; muestro la última copia/)
  const noPasa = montar("LlegadasEnVivo", { parada: "Calle 72", ruta: "B10" }, entorno(ok({ operacion: "llegadas", meta, parada: "Calle 72", ruta: "B10", motivo: "ruta-no-pasa-por-parada", llegadas: [] })).dobles)
  assert.match(texto(noPasa.arbol()), /No encuentro Calle 72 en el recorrido de la B10/)
  for (const m of [sin, detenida, vieja, noPasa]) m.desmontar()
})

test("buses en vía: cuántos, hacia dónde y entre qué paradas, con la edad de cada reporte", () => {
  const bus = (id: string, anterior: string | null, siguiente: string | null) => ({ id, etiqueta: id, rutaId: "10075", codigo: "B10", destino: "Portal Norte", lat: 4.6, lng: -74, edad: 42, anterior, siguiente, retraso: null })
  const e = entorno(ok({ operacion: "buses-ruta", meta, ruta: "B10", destinos: ["Portal Norte"], buses: [bus("N0163", "Calle 85", "Calle 100"), bus("M10492", null, null)], sinUbicar: 1 }))
  const m = montar("BusesEnVivo", { ruta: "B10" }, e.dobles)
  const t = texto(m.arbol())
  assert.match(t, /2 buses de la B10 en vía hacia Portal Norte/)
  assert.match(t, /Bus N0163: va entre Calle 85 y Calle 100, hace 42 segundos/)
  assert.match(t, /Bus M10492: no pude ubicarlo en su recorrido/)
  assert.equal(nodos(m.arbol(), (n) => n.props["aria-live"] === "polite").length, 1)
  m.desmontar()
})

test("paradas cercanas: nombre, distancia y llegadas estimadas, o que no hay llegadas", () => {
  const e = entorno(ok({
    operacion: "paradas-cercanas", meta,
    paradas: [
      { id: "2302", nombre: "Virrey - Cendiatra", lat: 4.67, lng: -74.05, distancia: 120, llegadas: [llegada({ paradaNombre: "Virrey" })] },
      { id: "9", nombre: "Otra parada", lat: 4.67, lng: -74.05, distancia: 640, llegadas: [] },
    ],
  }))
  const m = montar("ParadasCercanasEnVivo", { lat: 4.676, lng: -74.059 }, e.dobles)
  const t = texto(m.arbol())
  assert.match(t, /Virrey - Cendiatra/)
  assert.match(t, /B10 hacia Portal Norte: llega en unos 4 minutos, estimado/)
  assert.match(t, /Sin llegadas que pueda estimar ahora/)
  assert.match(t, /Datos de hace 40 segundos/)
  m.desmontar()
})

test("el texto de estado lo dice todo en palabras", () => {
  const { textoEstado } = compilar("components/en-vivo.tsx", { react: {}, "@/hooks/use-speech": {}, "@/hooks/use-tiempo-real": {} }) as { textoEstado: (m: object | null) => string }
  assert.equal(textoEstado(meta), "Datos de hace 40 segundos")
  assert.equal(textoEstado({ ...meta, detenido: true }), "Los datos en vivo no se están actualizando")
  assert.equal(textoEstado({ ...meta, copiaObsoleta: true }), "Datos de hace 40 segundos; no pude actualizar; muestro la última copia")
  assert.equal(textoEstado(null), "")
})

// ── Integración en las pantallas ──

const fuente = (archivo: string) => readFileSync(`${raiz}/${archivo}`, "utf8")

test("las pantallas usan los componentes en vivo y conservan sus notas de «no es tiempo real»", () => {
  const ruta = fuente("components/route-detail.tsx")
  assert.match(ruta, /<BusesEnVivo ruta=\{route\.code\} \/>/)
  assert.match(ruta, /<LlegadasEnVivo parada=\{espera\} ruta=\{route\.code\} \/>/)
  assert.match(ruta, /<label htmlFor="espera-en-vivo"/, "el selector tiene etiqueta visible")
  assert.match(ruta, /No es tiempo real; confirma el horario antes de salir/)
  assert.match(ruta, /Horario programado/)

  const viaje = fuente("components/trip-view.tsx")
  assert.match(viaje, /\{prescriptible && \(\s*<>[^]*?<LlegadasEnVivo key=\{[^]*?\} parada=\{leg\.board\} ruta=\{leg\.routeCode\}/, "solo con el plan verificado")
  assert.match(viaje, /horario programado, que no es tiempo real/)

  const gps = fuente("components/auditory-gps.tsx")
  assert.match(gps, /<ParadasCercanasEnVivo lat=\{Number\(ubicacionActual\.lat\.toFixed\(3\)\)\}/, "la coordenada se redondea")
})

test("las pantallas no mienten: no dicen que no hay tiempo real en las partes que ahora lo tienen", () => {
  assert.doesNotMatch(fuente("components/trip-view.tsx"), /No tengo los horarios en tiempo real/)
})

test("el texto de los componentes en vivo no baja de `text-base` ni usa texto pequeño", () => {
  assert.doesNotMatch(fuente("components/en-vivo.tsx"), /text-(xs|sm)\b/)
})

// ── Revisión R1 ──

test("R1·1 el resumen hablado dice el origen: una llegada solo programada no se anuncia como bus en vivo", () => {
  const e = entorno(ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada({ origen: "programado", bus: null, retraso: 300, segundos: 1200 })] }))
  const m = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, e.dobles)
  const [boton] = nodos(m.arbol(), (n) => n.type === "button")
  ;(boton.props.onClick as () => void)()
  assert.equal(e.estado.dicho[0], "Según la programación, la B10 hacia Portal Norte llegaría a Calle 100 en unos 20 minutos, estimado, con unos 5 minutos de retraso reportado, sin bus en vivo confirmado. Datos de hace 40 segundos.")
  assert.doesNotMatch(e.estado.dicho[0], /^La B10 hacia Portal Norte llega/)
  m.desmontar()
})

test("R1·1 el resumen hablado dice la edad y el estado del dato, y un feed detenido no se anuncia como «no hay buses»", () => {
  const detenida = entorno(ok({ operacion: "llegadas", meta: { ...meta, detenido: true, edadDatosS: 900 }, parada: "Calle 100", ruta: "B10", motivo: "feed-detenido", llegadas: [] }))
  const a = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, detenida.dobles)
  ;(nodos(a.arbol(), (n) => n.type === "button")[0].props.onClick as () => void)()
  assert.equal(detenida.estado.dicho[0], "No estimo llegadas a Calle 100. Los datos en vivo no se están actualizando.")
  assert.doesNotMatch(detenida.estado.dicho[0], /No veo buses/)

  const sinBuses = entorno(ok({ operacion: "llegadas", meta: { ...meta, copiaObsoleta: true, retrasos: "detenido" }, parada: "Calle 100", ruta: "B10", motivo: "sin-buses", llegadas: [] }))
  const b = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, sinBuses.dobles)
  ;(nodos(b.arbol(), (n) => n.type === "button")[0].props.onClick as () => void)()
  assert.equal(sinBuses.estado.dicho[0], "No veo buses de la B10 que lleguen a Calle 100 ahora. Datos de hace 40 segundos; no pude actualizar; muestro la última copia; los retrasos y cancelaciones no se actualizan y no los incluyo.")

  const busesDetenidos = entorno(ok({ operacion: "buses-ruta", meta: { ...meta, detenido: true, edadDatosS: 900 }, ruta: "B10", destinos: ["Portal Norte"], buses: [], sinUbicar: 0 }))
  const c = montar("BusesEnVivo", { ruta: "B10" }, busesDetenidos.dobles)
  ;(nodos(c.arbol(), (n) => n.type === "button")[0].props.onClick as () => void)()
  assert.equal(busesDetenidos.estado.dicho[0], "No puedo decir cuántos buses de la B10 hay. Los datos en vivo no se están actualizando.")
  assert.match(texto(c.arbol()), /No puedo decir cuántos buses de la B10 hay/, "la pantalla dice lo mismo que la voz")
  for (const m of [a, b, c]) m.desmontar()
})

// El hook real, con React y la red simulados.
function montarHook(peticion0: object | null) {
  const estados: unknown[] = []
  const refs: { current: unknown }[] = []
  const efectos: { deps: unknown[]; limpieza?: void | (() => void) }[] = []
  let hu = 0
  let hr = 0
  let he = 0
  let pendientes: (() => void)[] = []
  let peticion = peticion0
  let resultado: { estado: string; datos: unknown; actualizadoEn: unknown } = undefined as never
  /** Todo lo que devolvió el hook, render por render: el primero tras un cambio es lo que alcanza a pintarse. */
  const historial: (typeof resultado)[] = []
  const peticiones: { cuerpo: string; resolver: (r: Response | Error) => void }[] = []
  const react = {
    useState: (inicial: unknown) => {
      const i = hu++
      if (!(i in estados)) estados[i] = inicial
      return [estados[i], (v: unknown) => { estados[i] = typeof v === "function" ? (v as (x: unknown) => unknown)(estados[i]) : v; render() }]
    },
    useRef: (inicial: unknown) => (refs[hr] ??= { current: inicial }) && refs[hr++],
    useEffect: (fn: () => void | (() => void), deps: unknown[]) => {
      const i = he++
      const previo = efectos[i]
      if (previo && deps.every((d, k) => d === previo.deps[k])) return
      pendientes.push(() => {
        if (typeof previo?.limpieza === "function") previo.limpieza()
        efectos[i] = { deps }
        efectos[i].limpieza = fn()
      })
    },
  }
  const fetchDoble = (_url: string, init: { body: string; signal: AbortSignal }) =>
    new Promise<Response>((resolver, rechazar) => {
      peticiones.push({ cuerpo: init.body, resolver: (r) => (r instanceof Error ? rechazar(r) : resolver(r)) })
    })
  const manejadores: (() => void)[] = []
  const documento = { visibilityState: "visible", addEventListener: (_e: string, f: () => void) => manejadores.push(f), removeEventListener() {} }
  const salida = ts.transpileModule(readFileSync(`${raiz}/hooks/use-tiempo-real.ts`, "utf8"), { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText
  const modulo = { exports: {} as { useTiempoReal: (p: object | null, e: { parse: (x: unknown) => unknown }, o?: object) => typeof resultado } }
  vm.runInNewContext(`(function(require,module,exports){${salida}\n})`, { fetch: fetchDoble, document: documento, setTimeout, clearTimeout, setInterval, clearInterval, AbortController, JSON, Date })(
    (n: string) => (n === "react" ? react : (() => { throw new Error(n) })()),
    modulo,
    modulo.exports,
  )
  const esquema = { parse: (x: unknown) => x }
  function render() {
    hu = 0
    hr = 0
    he = 0
    resultado = modulo.exports.useTiempoReal(peticion, esquema)
    historial.push(resultado)
    const lista = pendientes
    pendientes = []
    lista.forEach((f) => f())
  }
  render()
  return {
    resultado: () => resultado,
    historial,
    peticiones,
    /** Dispara otra consulta de la misma petición, como el intervalo o volver a la pestaña. */
    renovar: () => manejadores.forEach((f) => f()),
    cambiar: (p: object | null) => { peticion = p; render() },
    desmontar: () => efectos.forEach((e) => typeof e.limpieza === "function" && e.limpieza()),
  }
}
const json = (x: unknown) => new Response(JSON.stringify(x))
const esperar = () => new Promise((ok) => setImmediate(ok))

test("R1·3 el dato va atado a su consulta: al cambiar de estación se descarta al instante y una respuesta tardía de la anterior no entra", async () => {
  const calle100 = { operacion: "llegadas", parada: "Calle 100", ruta: "B10" }
  const calle72 = { operacion: "llegadas", parada: "Calle 72", ruta: "8 G" }
  const h = montarHook(calle100)
  h.peticiones[0].resolver(json({ minutos: "Calle 100" }))
  await esperar()
  assert.deepEqual(h.resultado().datos, { minutos: "Calle 100" })
  assert.equal(h.resultado().estado, "ok")

  const antes = h.historial.length
  h.cambiar(calle72)
  // El PRIMER render tras el cambio es el que alcanza a pintarse y a anunciarse: no puede traer los minutos de Calle 100.
  assert.equal(h.historial[antes].datos, null, "antes: un render con los minutos de la estación anterior")
  assert.equal(h.historial[antes].estado, "cargando")
  assert.equal(h.resultado().datos, null)
  assert.equal(h.resultado().estado, "cargando")

  // Una respuesta que llega tarde de la consulta anterior se ignora.
  h.peticiones[0].resolver(json({ minutos: "Calle 100 (tarde)" }))
  await esperar()
  assert.equal(h.resultado().datos, null)

  h.peticiones[1].resolver(json({ minutos: "Calle 72" }))
  await esperar()
  assert.deepEqual(h.resultado().datos, { minutos: "Calle 72" })
  h.desmontar()
})

test("R1·3 si la consulta falla, el dato anterior se retira (ni siquiera el de la misma consulta)", async () => {
  const h = montarHook({ operacion: "llegadas", parada: "Calle 100", ruta: "B10" })
  h.peticiones[0].resolver(json({ minutos: 4 }))
  await esperar()
  assert.deepEqual(h.resultado().datos, { minutos: 4 })
  // La renovación de la misma consulta (intervalo, o volver a la pestaña) falla.
  h.renovar()
  h.peticiones[1].resolver(new Error("HTTP 500"))
  await esperar()
  assert.equal(h.resultado().datos, null)
  assert.equal(h.resultado().estado, "error")
  h.desmontar()
})

test("R1·3 la región viva se vacía al cambiar de consulta: el aviso de otra estación no se queda", () => {
  mock.timers.enable({ apis: ["setTimeout", "Date"], now: 1_000_000 })
  try {
    const e = entorno(ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada()] }))
    const m = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, e.dobles)
    mock.timers.tick(1)
    const viva = () => texto(nodos(m.arbol(), (n) => n.props["aria-live"] === "polite")[0])
    assert.match(viva(), /Calle 100/)
    // Llega la otra consulta: el hook aún no tiene dato para ella.
    e.estado.resultado = { estado: "cargando", datos: null, actualizadoEn: null }
    m.redibujar()
    m.redibujar()
    assert.equal(viva(), "", "antes quedaba anunciado el dato de la estación anterior")
    m.desmontar()
  } finally {
    mock.timers.reset()
  }
})

// ── Revisión R2 ──

import { readdirSync } from "node:fs"

test("R2·1 el GPS distingue lo programado de lo confirmado, en la lista y en la voz", () => {
  const programada = llegada({ origen: "programado", bus: null, codigo: "8", destino: "Guatoque", segundos: 360 })
  const vivaAdemas = llegada({ codigo: "B10", segundos: 120 })
  const e = entorno(ok({
    operacion: "paradas-cercanas", meta,
    paradas: [
      { id: "1", nombre: "Calle 72 - Areandina", lat: 4.6, lng: -74, distancia: 80, llegadas: [programada] },
      { id: "2", nombre: "Calle 85", lat: 4.6, lng: -74, distancia: 400, llegadas: [vivaAdemas] },
    ],
  }))
  const m = montar("ParadasCercanasEnVivo", { lat: 4.676, lng: -74.059 }, e.dobles)
  const t = texto(m.arbol())
  assert.match(t, /8 hacia Guatoque: según la programación, llegaría en unos 6 minutos, estimado, sin bus en vivo confirmado/, "antes: «en unos 6 minutos, estimado» bajo «En vivo»")
  assert.match(t, /B10 hacia Portal Norte: llega en unos 4 minutos|B10 hacia Portal Norte: llega en unos 2 minutos/)
  ;(nodos(m.arbol(), (n) => n.type === "button")[0].props.onClick as () => void)()
  assert.match(e.estado.dicho[0], /Calle 72 - Areandina, a .*: según la programación, la 8 hacia Guatoque llegaría en unos 6 minutos, estimado, sin bus en vivo confirmado/)
  assert.match(e.estado.dicho[0], /Calle 85, a .*: la B10 hacia Portal Norte llega en unos 2 minutos, estimado/)
  m.desmontar()
})

test("R2·1 una sola fuente dice una llegada: ningún componente ni respuesta repite «llegaría» o «sin bus en vivo confirmado»", () => {
  const archivos = ["components", "lib", "hooks"].flatMap((d) => readdirSync(`${raiz}/${d}`).filter((f) => /\.tsx?$/.test(f) && !/\.test\./.test(f)).map((f) => `${d}/${f}`))
  const dueños = archivos.filter((f) => /llegaría|sin bus en vivo confirmado/.test(readFileSync(`${raiz}/${f}`, "utf8")))
  assert.deepEqual(dueños, ["lib/texto-tiempo-real.ts"])
})
