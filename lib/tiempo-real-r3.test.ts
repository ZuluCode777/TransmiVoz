import assert from "node:assert/strict"
import test, { mock } from "node:test"
import snapshot from "@/data/transmilenio.json" with { type: "json" }
import { PeticionTiempoRealSchema } from "@/lib/contrato-tiempo-real"
import { ejecutarConsulta, resolverParada, resolverRuta, type Contexto } from "@/lib/consulta-tiempo-real"
import { instantaneaDeMuestra } from "@/lib/fixtures-gtfs/cargar"
import { instalarFeeds } from "@/lib/fixtures-gtfs/entorno"
import { IndiceGtfsSchema } from "@/lib/gtfs-indice"
import { indiceGtfs } from "@/lib/instantanea-servidor"
import { parseIntent, type ConsultaTiempoReal } from "@/lib/local-agent"
import { parseIntentWithOllama } from "@/lib/ollama"
import { resolverTiempoReal, responderTiempoReal } from "@/lib/respuesta-tiempo-real"
import { TransmilenioDataSchema } from "@/lib/transmilenio"

/**
 * Revisión R3. Hallazgo 1: la parada que dijo la persona llega ENTERA al resolver (reglas y modelo).
 * Hallazgo 2: el sistema o el `route_id` pedido llega hasta el resolver (endpoint, reglas, modelo) y las
 * ambigüedades conservan sus opciones en todos los consumidores. (El hallazgo 3 está en `tiempo-real-ui.test.ts`.)
 */

const data = TransmilenioDataSchema.parse(snapshot)
const consulta = (frase: string): ConsultaTiempoReal | null => {
  const intent = parseIntent(frase, data)
  return intent.type === "tiempo_real" ? intent.consulta : null
}
const parada = (frase: string) => {
  const c = consulta(frase)
  return c && "parada" in c ? c.parada : undefined
}
const contextoReal = (): Contexto => ({ data, i: { ...instantaneaDeMuestra(), indice: indiceGtfs() } })

// ── 1 · Identidad explícita de la parada ───────────────────────────────────────

test("R3·1 «Terminal del Transporte Salitre» y «Br. El Virrey» llegan enteras, con cualquier preposición", () => {
  assert.equal(parada("¿Hay novedades en Terminal del Transporte Salitre?"), "terminal del transporte salitre", "antes quedaba «Terminal» (la estación BRT 2502)")
  assert.equal(parada("¿Hay novedades sobre Br. El Virrey?"), "br el virrey", "antes quedaba «Virrey» por no reconocer «sobre»")
  assert.equal(parada("¿Hay novedades de Br. El Virrey?"), "br el virrey")
  assert.equal(parada("¿Hay novedades en la parada Br. El Virrey?"), "br el virrey")
  assert.equal(parada("¿Hay novedades acerca de Terminal del Transporte Salitre?"), "terminal del transporte salitre")
  assert.equal(parada("¿Cuándo pasa la ruta CB144 por Terminal del Transporte Salitre?"), "terminal del transporte salitre")
  assert.equal(parada("¿Cuándo pasa un bus hasta Terminal del Transporte Salitre?"), "terminal del transporte salitre")
})

test("R3·1 nombres con «de», «del», «la», «Br.», «Pq.» y «Av.» se conservan completos", () => {
  assert.equal(parada("¿Cuándo pasa la ruta CB144 por Centro de Convenciones?"), "centro de convenciones")
  assert.equal(parada("¿Hay desvíos en Pq. Público Plazuelas del Virrey?"), "pq publico plazuelas del virrey")
  assert.equal(parada("¿Hay novedades en Br. La Liberia?"), "br la liberia")
  assert.equal(parada("¿Hay novedades en Av. Ciudad de Quito?"), "avenida ciudad de quito")
  assert.equal(parada("¿Hay novedades en Av. 68?"), "AV. 68", "una estación del catálogo dicha completa sigue siendo la del catálogo")
})

test("R3·1 solo se quitan los cierres conversacionales reconocidos", () => {
  for (const cierre of ["por favor", "hoy", "ahora", "ahora mismo", "en este momento", "gracias", "hacia el norte", "esta tarde"]) {
    assert.equal(parada(`¿Cuándo pasa el B10 por Calle 100 ${cierre}?`), "Calle 100", cierre)
    assert.equal(parada(`¿Hay novedades en Terminal del Transporte Salitre ${cierre}?`), "terminal del transporte salitre", cierre)
  }
})

test("R3·1 sin preposición, una estación que sigue con «del…» no se corta; y una que forma parte de «Br. …» no se toma", () => {
  assert.equal(parada("hay novedades Terminal del Transporte Salitre"), "terminal del transporte salitre")
  assert.equal(parada("hay novedades Calle 100"), "Calle 100")
  assert.notEqual(parada("hay novedades Br. El Virrey"), "Virrey", "«Virrey» es parte de «Br. El Virrey»")
})

test("R3·1 de punta a punta: «Terminal del Transporte Salitre» es la parada 50425, no la estación 2502 a 15 km", async () => {
  const r = resolverParada("terminal del transporte salitre", contextoReal())
  assert.equal(r.tipo, "ok")
  if (r.tipo === "ok") {
    assert.ok(r.parada.ids.has("50425"))
    assert.ok(!r.parada.ids.has("2502"))
  }
  const entorno = instalarFeeds()
  const respuesta = await responderTiempoReal(consulta("¿Hay novedades en Terminal del Transporte Salitre?")!, { data, context: { now: entorno.ahora() } })
  assert.match(respuesta.reply, /estación Terminal del Transporte Salitre/)
  const sobre = await responderTiempoReal(consulta("¿Hay novedades sobre Br. El Virrey?")!, { data, context: { now: entorno.ahora() } })
  assert.match(sobre.reply, /estación Br\. El Virrey/)
  assert.doesNotMatch(sobre.reply, /Cendiatra/)
})

function conModelo(contenido: object, prueba: () => Promise<void>) {
  return async () => {
    const original = globalThis.fetch
    globalThis.fetch = (async () => new Response(JSON.stringify({ message: { content: JSON.stringify(contenido) } }))) as typeof fetch
    try {
      await prueba()
    } finally {
      globalThis.fetch = original
    }
  }
}

test(
  "R3·1 el modelo: aunque dé bien (o truncado) el destino, manda el nombre entero que dijo la persona",
  conModelo({ intent: "realtime", origin: "", destination: "Terminal", routeCode: "" }, async () => {
    assert.deepEqual(await parseIntentWithOllama("¿Hay novedades en Terminal del Transporte Salitre?", data), {
      type: "tiempo_real",
      consulta: { tema: "novedades", ruta: undefined, parada: "terminal del transporte salitre" },
    })
    assert.deepEqual(await parseIntentWithOllama("¿Hay novedades sobre Br. El Virrey?", data), {
      type: "tiempo_real",
      consulta: { tema: "novedades", ruta: undefined, parada: "br el virrey" },
    })
    // Sin preposición, el modelo completa el nombre que la regla solo vio a medias.
    // (abajo, con otro modelo: «Terminal Salitre»)
    assert.deepEqual(await parseIntentWithOllama("hay novedades terminal del transporte salitre", data), {
      type: "tiempo_real",
      consulta: { tema: "novedades", ruta: undefined, parada: "terminal del transporte salitre" },
    })
  }),
)

test(
  "R3·1 el modelo completa un nombre que la regla vio a medias (sin preposición ni «del»)",
  conModelo({ intent: "realtime", origin: "", destination: "Terminal Salitre", routeCode: "" }, async () => {
    // Las reglas, sin preposición, ven solo la estación «Terminal»; el modelo da el nombre entero que dijo la persona.
    assert.deepEqual(await parseIntentWithOllama("cuándo llega el bus Terminal Salitre", data), {
      type: "tiempo_real",
      consulta: { tema: "llegadas", ruta: undefined, parada: "terminal salitre" },
    })
  }),
)

// ── 2 · Sistema o route_id pedidos, y ambigüedades con sus opciones ───────────────────────────

test("R3·2 «C25 zonal», «C25 (zonal urbano)» y el route_id 12756 llegan hasta el resolver desde las reglas", () => {
  assert.deepEqual(consulta("¿Dónde viene la C25 zonal?"), { tema: "buses", ruta: "C25 zonal" })
  assert.deepEqual(consulta("¿Cuándo pasa la C25 (zonal urbano) por Calle 72?"), { tema: "llegadas", ruta: "C25 zonal urbano", parada: "Calle 72" })
  assert.deepEqual(consulta("¿Dónde viene la ruta 12756?"), { tema: "buses", ruta: "12756" })
  assert.deepEqual(consulta("¿Hay novedades en la C25 troncal?"), { tema: "novedades", ruta: "C25 troncal", parada: undefined })
  assert.deepEqual(consulta("¿Dónde viene la C25?"), { tema: "buses", ruta: "C25" }, "sin pedir sistema, nada cambia")
})

test(
  "R3·2 el modelo no pierde el sistema: su «C25» se une al «zonal» que dijo la persona",
  conModelo({ intent: "realtime", origin: "", destination: "", routeCode: "C25" }, async () => {
    assert.deepEqual(await parseIntentWithOllama("¿Dónde viene la C25 zonal?", data), { type: "tiempo_real", consulta: { tema: "buses", ruta: "C25 zonal" } })
    assert.deepEqual(await parseIntentWithOllama("dime dónde viene la ruta 12756", data), { type: "tiempo_real", consulta: { tema: "buses", ruta: "12756" } })
  }),
)

test("R3·2 el resolver entiende el sistema en la frase, en el parámetro y el route_id, sin mezclar", () => {
  const ctx = contextoReal()
  const ids = (r: ReturnType<typeof resolverRuta>) => (r.tipo === "ok" ? r.rutas.map((x) => x.id).sort() : r.tipo)
  for (const dicho of ["C25 zonal", "C25 (zonal urbano)", "C25 zonal urbano", "12756"]) {
    const r = resolverRuta(dicho, ctx)
    assert.equal(r.tipo, "ok", dicho)
    if (dicho === "12756") assert.deepEqual(ids(r), ["12756"])
    else assert.deepEqual(ids(r), ["12756", "12757"], dicho)
    if (r.tipo === "ok") {
      assert.equal(r.sistema, "zonal urbano")
      assert.deepEqual(r.tambienEn, ["troncal"], "dice que existe también en el troncal")
    }
  }
  assert.deepEqual(ids(resolverRuta("C25 troncal", ctx)), ["10073"])
  assert.deepEqual(ids(resolverRuta("C25", ctx)), ["10073"], "sin pedirlo, el troncal (y se avisa del zonal)")
  assert.deepEqual(ids(resolverRuta("C25", ctx, "zonal")), ["12756", "12757"], "por parámetro")
  assert.equal(resolverRuta("C25 zonal complementario", ctx).tipo, "desconocida", "no existe en ese sistema")
  assert.equal(resolverRuta("B10 zonal", ctx).tipo, "desconocida")
  assert.equal(resolverRuta("12756", ctx, "troncal").tipo, "desconocida", "el route_id es de otro sistema")
  assert.equal(resolverRuta("99999", ctx).tipo, "desconocida")
})

test("R3·2 el endpoint (zod) acepta y conserva `sistema` y rutas por route_id, y rechaza uno que no existe", () => {
  const buena = PeticionTiempoRealSchema.parse({ operacion: "buses-ruta", ruta: "C25", sistema: "zonal urbano" })
  assert.equal("sistema" in buena && buena.sistema, "zonal urbano", "antes el schema descartaba `sistema`")
  for (const op of ["llegadas", "alertas", "horario-ruta", "cancelados-hoy"] as const) {
    const p = PeticionTiempoRealSchema.parse({ operacion: op, ruta: "C25", sistema: "zonal", ...(op === "llegadas" ? { parada: "Calle 72" } : {}) })
    assert.equal("sistema" in p && p.sistema, "zonal", op)
  }
  assert.equal(PeticionTiempoRealSchema.safeParse({ operacion: "buses-ruta", ruta: "C25", sistema: "submarino" }).success, false)
  assert.equal(PeticionTiempoRealSchema.safeParse({ operacion: "buses-ruta", ruta: "12756" }).success, true)
})

test("R3·2 la C25 zonal se cuenta, se lista y se dice como zonal, no como la troncal", () => {
  const ctx = contextoReal()
  const zonal = ejecutarConsulta(ctx, { operacion: "buses-ruta", ruta: "C25", sistema: "zonal urbano" })
  assert.equal(zonal.estado, 200)
  const cuerpo = zonal.cuerpo as { sistema: string; tambienEn: string[]; destinos: string[] }
  assert.equal(cuerpo.sistema, "zonal urbano")
  assert.deepEqual(cuerpo.tambienEn, ["troncal"])
  assert.deepEqual(cuerpo.destinos.sort(), ["Engativá || Unicentro", "Engativá || Unicentro Ciclovía"])
  const porId = ejecutarConsulta(ctx, { operacion: "horario-ruta", ruta: "12756" })
  assert.equal(porId.estado, 200)
  assert.deepEqual((porId.cuerpo as { horarios: { rutaId: string }[] }).horarios.map((h) => h.rutaId), ["12756"])
  // El sistema pedido llega a TODAS las operaciones con ruta, no solo a buses-ruta.
  for (const peticion of [
    { operacion: "llegadas", parada: "Calle 72", ruta: "C25", sistema: "zonal urbano" },
    { operacion: "alertas", ruta: "C25", sistema: "zonal urbano" },
    { operacion: "horario-ruta", ruta: "C25", sistema: "zonal urbano" },
    { operacion: "cancelados-hoy", ruta: "C25", sistema: "zonal urbano" },
  ] as const) {
    const r = ejecutarConsulta(ctx, peticion)
    assert.equal((r.cuerpo as { sistema: string }).sistema, "zonal urbano", peticion.operacion)
  }
  const troncal = ejecutarConsulta(ctx, { operacion: "buses-ruta", ruta: "C25" })
  assert.deepEqual((troncal.cuerpo as { destinos: string[] }).destinos, ["Portal Suba"])
})

test("R3·2 el asistente contesta sobre la C25 zonal cuando se la piden explícitamente", async () => {
  const entorno = instalarFeeds()
  const r = await responderTiempoReal(consulta("¿Dónde viene la C25 zonal?")!, { data, context: { now: entorno.ahora() } })
  assert.match(r.reply, /de la C25 zonal en vía|buses de la C25 zonal/)
  assert.match(r.reply, /Ojo: el código C25 también existe en troncal; hablo del servicio zonal urbano\./)
  assert.doesNotMatch(r.reply, /Portal Suba/)
  const id = await responderTiempoReal(consulta("¿cuántos viajes tiene hoy la ruta 12756?")!, { data, context: { now: entorno.ahora() } })
  assert.match(id.reply, /^Hoy, para la 12756: entre Engativá y Unicentro: \d+ salidas/)
  assert.match(id.reply, /Ojo: ese servicio es del sistema zonal urbano; la misma línea también existe en troncal\./)
})

/** Un índice con un código que existe en DOS sistemas zonales y en ninguno troncal: el único camino al 409 `ruta-ambigua`. */
function contextoAmbiguo(): Contexto {
  const base = contextoReal()
  const ruta = (id: string, agencia: string, destino: string) => ({ id, codigo: "Z9", destino, agencia, paradas: [["A", 0], ["B", 60]] as [string, number][], horario: {} })
  const indice = IndiceGtfsSchema.parse({ ...base.i.indice, rutas: [ruta("90001", "3", "Norte"), ruta("90002", "4", "Sur")] })
  return { ...base, i: { ...base.i, indice } }
}
const OPCIONES = ["Z9 (zonal urbano)", "Z9 (zonal complementario)"]

test("R3·2 la ambigüedad de ruta conserva sus opciones en el endpoint, para cada operación", () => {
  const ctx = contextoAmbiguo()
  for (const peticion of [
    { operacion: "buses-ruta", ruta: "Z9" },
    { operacion: "llegadas", parada: "Calle 100", ruta: "Z9" },
    { operacion: "alertas", ruta: "Z9" },
    { operacion: "horario-ruta", ruta: "Z9" },
    { operacion: "cancelados-hoy", ruta: "Z9" },
  ] as const) {
    const r = ejecutarConsulta(ctx, peticion)
    assert.equal(r.estado, 409, peticion.operacion)
    assert.deepEqual(r.cuerpo, { error: "ruta-ambigua", opciones: OPCIONES }, peticion.operacion)
  }
  // Y pidiendo el sistema se resuelve.
  assert.equal(ejecutarConsulta(ctx, { operacion: "buses-ruta", ruta: "Z9", sistema: "zonal complementario" }).estado, 200)
  assert.equal(ejecutarConsulta(ctx, { operacion: "buses-ruta", ruta: "Z9 zonal urbano" }).estado, 200)
})

test("R3·2 el asistente DICE las opciones de una ruta ambigua en cada consulta (antes: «no encontré la ruta»)", async () => {
  const ctx = contextoAmbiguo()
  const preguntas: ConsultaTiempoReal[] = [
    { tema: "buses", ruta: "Z9" },
    { tema: "llegadas", ruta: "Z9" }, // sin estación: dónde está la ruta
    { tema: "llegadas", ruta: "Z9", parada: "Calle 100" },
    { tema: "novedades", ruta: "Z9" },
    { tema: "salidas_hoy", ruta: "Z9" },
    { tema: "cancelados", ruta: "Z9" },
  ]
  for (const q of preguntas) {
    const { reply } = await resolverTiempoReal(q, ctx, {})
    assert.match(reply, /Hay más de un servicio con el código Z9: Z9 \(zonal urbano\) y Z9 \(zonal complementario\)\. ¿Cuál quieres\?/, q.tema + " " + JSON.stringify(q))
    assert.doesNotMatch(reply, /No encontré la ruta/, q.tema)
  }
})

test("R3·2 la ambigüedad de parada también conserva sus opciones (endpoint y asistente)", async () => {
  const ctx = contextoReal()
  const r = ejecutarConsulta(ctx, { operacion: "alertas", parada: "Plazuelas" })
  assert.equal(r.estado, 409)
  assert.equal((r.cuerpo as { error: string }).error, "parada-ambigua")
  const opciones = (r.cuerpo as { opciones: string[] }).opciones
  assert.ok(opciones.length >= 2)
  const { reply } = await resolverTiempoReal({ tema: "novedades", parada: "Plazuelas" }, ctx, {})
  for (const o of opciones) assert.ok(reply.includes(o), `falta «${o}»`)
})

void mock

// ── Revisión final ────────────────────────────────────────────────────────────

import { necesidadesDe } from "@/lib/instantanea-servidor"

test("RF·1 sin preposición, «hay novedades Br. El Virrey» conserva la parada completa y filtra por ella", async () => {
  assert.equal(parada("hay novedades Br. El Virrey"), "br el virrey", "antes: sin parada, y las alertas de TODA la red")
  assert.equal(parada("hay desvíos Pq. El Virrey"), "pq el virrey")
  assert.equal(parada("hay novedades Terminal del Transporte Salitre"), "terminal del transporte salitre")
  assert.equal(parada("hay novedades Calle 100"), "Calle 100")
  // La parada resuelta es la de verdad (no la estación «Virrey» a 20 km), y el filtro existe: alertas de TODA la red no.
  const r = resolverParada(parada("hay novedades Br. El Virrey")!, contextoReal())
  assert.equal(r.tipo, "ok")
  if (r.tipo === "ok") {
    assert.equal(r.parada.nombre, "Br. El Virrey")
    assert.ok(!r.parada.ids.has("2302"))
  }
  const entorno = instalarFeeds()
  entorno.estado.alertasVigentes = true // toda alerta de la muestra está vigente: sin filtro saldrían todas
  const filtrada = await responderTiempoReal(consulta("hay novedades Br. El Virrey")!, { data, context: { now: entorno.ahora() } })
  assert.match(filtrada.reply, /^No hay novedades vigentes en la estación Br\. El Virrey/, "con el filtro de parada no hay ninguna: antes devolvía las de toda la red")
})

test(
  "RF·1 el modelo da «Virrey» truncado: se rechaza y se conserva «Br. El Virrey», aunque las reglas no sacaran nombre",
  conModelo({ intent: "realtime", origin: "", destination: "Virrey", routeCode: "" }, async () => {
    for (const frase of ["cuándo llega un bus Br. El Virrey", "dime cuándo llega un bus Pq. El Virrey"]) {
      const intent = await parseIntentWithOllama(frase, data)
      assert.deepEqual(intent, { type: "tiempo_real", consulta: { tema: "llegadas", ruta: undefined, parada: frase.includes("Pq.") ? "pq el virrey" : "br el virrey" } }, frase)
    }
    assert.deepEqual(await parseIntentWithOllama("hay novedades por el Virrey", data), { type: "tiempo_real", consulta: { tema: "novedades", ruta: undefined, parada: "Virrey" } }, "sin prefijo, «Virrey» es correcto")
  }),
)

test("RF·2 el calificador de ruta al final no es parte de la parada («Virrey de la ruta B10»)", async () => {
  assert.deepEqual(consulta("¿Hay novedades en la estación Virrey de la ruta B10?"), { tema: "novedades", ruta: "B10", parada: "Virrey" })
  assert.deepEqual(consulta("¿Hay novedades en Calle 100 del B10?"), { tema: "novedades", ruta: "B10", parada: "Calle 100" })
  assert.deepEqual(consulta("¿Hay novedades en Calle 100 de la B10?"), { tema: "novedades", ruta: "B10", parada: "Calle 100" })
  assert.deepEqual(consulta("¿Cuándo pasa la 8 G por Calle 72 de la ruta 8 G?"), { tema: "llegadas", ruta: "8 G", parada: "Calle 72" })
  assert.deepEqual(consulta("¿Hay novedades en Calle 100 del servicio CB144?"), { tema: "novedades", ruta: "CB144", parada: "Calle 100" })
  // Los «de/del» que son del nombre real no se tocan.
  assert.equal(parada("¿Hay novedades en Plazuelas del Virrey?"), "plazuelas del virrey")
  assert.equal(parada("¿Hay novedades en Centro de Convenciones de la ruta B10?"), "centro de convenciones")
  assert.equal(parada("¿Hay novedades en Terminal del Transporte Salitre?"), "terminal del transporte salitre")
  const entorno = instalarFeeds()
  const r = await responderTiempoReal(consulta("¿Hay novedades en la estación Virrey de la ruta B10?")!, { data, context: { now: entorno.ahora() } })
  assert.doesNotMatch(r.reply, /No encontré la parada/, "antes: «No encontré la parada virrey de la ruta b10»")
  assert.match(r.reply, /en la B10 y la estación Virrey/)
})

test(
  "RF·3 el destino del modelo con cierre pegado («Calle 100 hoy») no pisa el resultado limpio de las reglas",
  conModelo({ intent: "realtime", origin: "", destination: "Calle 100 hoy", routeCode: "B10" }, async () => {
    for (const cierre of ["hoy", "por favor", "hacia el norte", "ahora mismo", "esta tarde"]) {
      const intent = await parseIntentWithOllama(`¿Cuándo pasa el B10 por Calle 100 ${cierre}?`, data)
      assert.deepEqual(intent, { type: "tiempo_real", consulta: { tema: "llegadas", ruta: "B10", parada: "Calle 100" } }, cierre)
    }
  }),
)

test(
  "RF·3 y cuando solo el modelo da la estación, también sale limpia",
  conModelo({ intent: "realtime", origin: "", destination: "Calle 100 por favor", routeCode: "B10" }, async () => {
    assert.deepEqual(await parseIntentWithOllama("B10 cuándo llega Calle 100 por favor", data), { type: "tiempo_real", consulta: { tema: "llegadas", ruta: "B10", parada: "Calle 100" } })
  }),
)

void necesidadesDe
