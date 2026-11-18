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

const meta = { edadDatosS: 40, detenido: false, copiaObsoleta: false, retrasos: "disponibles", indicePublicado: "2026-11-17" }
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
const ok = (datos: object, extra: object = {}) => ({ estado: "ok", datos, desactualizado: false, actualizadoEn: 1, ...extra })

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
  assert.deepEqual(e.estado.dicho, ["La B10 hacia Portal Norte llega a Calle 100 en unos 4 minutos, estimado."])
  m.desmontar()
})

test("llegadas: sin datos, con la fuente detenida y con copia anterior, lo dice en texto", () => {
  const sin = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, entorno({ estado: "error", datos: null, desactualizado: false, actualizadoEn: null }).dobles)
  assert.match(texto(sin.arbol()), /No pude consultar los datos en vivo ahora\. Confirma el horario con TransMilenio/)
  const detenida = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, entorno(ok({ operacion: "llegadas", meta: { ...meta, detenido: true, edadDatosS: 900 }, parada: "Calle 100", ruta: "B10", motivo: "feed-detenido", llegadas: [] })).dobles)
  assert.match(texto(detenida.arbol()), /no se están actualizando, así que no estimo llegadas/)
  const vieja = montar("LlegadasEnVivo", { parada: "Calle 100", ruta: "B10" }, entorno(ok({ operacion: "llegadas", meta, parada: "Calle 100", ruta: "B10", motivo: null, llegadas: [llegada()] }, { desactualizado: true })).dobles)
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
  assert.match(t, /B10 hacia Portal Norte: en unos 4 minutos, estimado/)
  assert.match(t, /Sin llegadas que pueda estimar ahora/)
  assert.match(t, /Datos de hace 40 segundos/)
  m.desmontar()
})

test("el texto de estado lo dice todo en palabras", () => {
  const { textoEstado } = compilar("components/en-vivo.tsx", { react: {}, "@/hooks/use-speech": {}, "@/hooks/use-tiempo-real": {} }) as { textoEstado: (m: object | null, d: boolean) => string }
  assert.equal(textoEstado(meta, false), "Datos de hace 40 segundos")
  assert.equal(textoEstado({ ...meta, detenido: true }, false), "Los datos en vivo no se están actualizando")
  assert.equal(textoEstado({ ...meta, copiaObsoleta: true }, false), "Datos de hace 40 segundos; no pude actualizar; muestro la última copia")
  assert.equal(textoEstado(null, false), "")
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
