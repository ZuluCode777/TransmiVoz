import assert from "node:assert/strict"
import test from "node:test"
import snapshot from "@/data/transmilenio.json" with { type: "json" }
import { instalarFeeds } from "@/lib/fixtures-gtfs/entorno"
import { AgentReplySchema, parseIntent, respuestaSeguraParaMostrar, respuestaSinImperativos, runIntent, type ConsultaTiempoReal, type Intent } from "@/lib/local-agent"
import { intencionUsaUbicacion } from "@/lib/seleccion-interprete"
import { responderTiempoReal } from "@/lib/respuesta-tiempo-real"
import { TransmilenioDataSchema } from "@/lib/transmilenio"
import { textoAlerta } from "@/lib/respuesta-tiempo-real"

const data = TransmilenioDataSchema.parse(snapshot)
const consulta = (frase: string): ConsultaTiempoReal | null => {
  const intent = parseIntent(frase, data)
  return intent.type === "tiempo_real" ? intent.consulta : null
}

// --- Reglas: frase → consulta ------------------------------------------------------------

test("reglas: las preguntas del enunciado se vuelven consultas en vivo", () => {
  assert.deepEqual(consulta("¿Cuándo pasa el B10 por Calle 72?"), { tema: "llegadas", ruta: "B10", parada: "Calle 72" })
  assert.deepEqual(consulta("¿Dónde viene el B10?"), { tema: "buses", ruta: "B10" })
  assert.deepEqual(consulta("¿Cuántos B10 hay en vía?"), { tema: "buses", ruta: "B10" })
  assert.deepEqual(consulta("¿Hay novedades en el B10?"), { tema: "novedades", ruta: "B10", parada: undefined })
  assert.deepEqual(consulta("¿Hay desvíos en Calle 72?"), { tema: "novedades", ruta: undefined, parada: "Calle 72" })
})

test("reglas: «8 G» y «8G» son la misma ruta", () => {
  assert.deepEqual(consulta("¿Dónde viene la 8 G?"), { tema: "buses", ruta: "8 G" })
  assert.deepEqual(consulta("¿Dónde viene la 8G?"), { tema: "buses", ruta: "8 G" })
  assert.deepEqual(consulta("cuándo llega la 8 T a Calle 72"), { tema: "llegadas", ruta: "8 T", parada: "Calle 72" })
})

test("reglas: el resto de utilidades", () => {
  assert.deepEqual(consulta("¿por dónde va el bus Z32-7046?"), { tema: "bus", bus: "Z32-7046" })
  assert.deepEqual(consulta("dónde está el bus D0159"), { tema: "bus", bus: "D0159" })
  assert.deepEqual(consulta("¿cuántos buses hay en servicio?"), { tema: "sistema" })
  assert.deepEqual(consulta("¿cuántos viajes tiene hoy el B10?"), { tema: "salidas_hoy", ruta: "B10" })
  assert.deepEqual(consulta("¿cuántos viajes cancelados hay hoy?"), { tema: "cancelados", ruta: undefined })
  assert.deepEqual(consulta("viajes cancelados del B10"), { tema: "cancelados", ruta: "B10" })
  assert.deepEqual(consulta("busca la parada Virrey"), { tema: "buscar_parada", texto: "virrey" })
  assert.deepEqual(consulta("¿qué buses pasan cerca de mí?"), { tema: "paradas_cercanas" })
  assert.deepEqual(consulta("¿hay buses cerca?"), { tema: "buses_cercanos" })
  assert.deepEqual(consulta("¿están actualizados los datos en vivo?"), { tema: "estado_datos" })
  assert.deepEqual(consulta("cuándo llega el bus"), { tema: "llegadas", parada: undefined })
  assert.deepEqual(consulta("¿cuándo pasa el bus 8-1?"), { tema: "llegadas", ruta: "8-1" })
})

test("reglas: las consultas de horario, viaje y GPS conservan su intención", () => {
  for (const [frase, tipo] of [
    ["¿a qué hora pasa la H54?", "schedule"],
    ["horario de la B23", "schedule"],
    ["información de la ruta B23", "route_info"],
    ["cómo llego de Ricaurte a Calle 72", "trip"],
    ["cuál es la estación más cercana", "gps"],
    ["¿cuánto cuesta el pasaje?", "unsupported"],
  ] as const) {
    assert.equal(parseIntent(frase, data).type, tipo, frase)
  }
})

test("las consultas de cercanía usan la ubicación y las demás no", () => {
  const i = (frase: string): Intent => parseIntent(frase, data)
  assert.equal(intencionUsaUbicacion(i("¿qué buses pasan cerca de mí?")), true)
  assert.equal(intencionUsaUbicacion(i("¿hay buses cerca?")), true)
  assert.equal(intencionUsaUbicacion(i("¿dónde viene el B10?")), false)
})

test("sin red (reglas sin conexión) responde honesto y ofrece el horario", () => {
  const reply = runIntent(parseIntent("¿dónde viene el B10?", data), { data })
  assert.match(reply.reply, /No puedo consultar los datos en vivo/)
  assert.match(reply.reply, /horario publicado/)
})

// --- Respuestas con los feeds reales de la muestra -------------------------------------------

const MALAS = /prometo|garantizo|seguro que llega/i

async function preguntar(frase: string, entorno: ReturnType<typeof instalarFeeds>, opciones: { position?: { lat: number; lng: number } } = {}) {
  const intent = parseIntent(frase, data)
  assert.equal(intent.type, "tiempo_real", frase)
  const position = opciones.position && { ...opciones.position, precision: 10, hora: entorno.reloj.ms }
  const respuesta = await responderTiempoReal((intent as Extract<Intent, { type: "tiempo_real" }>).consulta, { data, context: { now: entorno.ahora(), position } })
  // Contrato: el mismo AgentReply que decodifica el iPhone, y sin órdenes de abordaje.
  assert.equal(AgentReplySchema.safeParse(respuesta).success, true, frase)
  assert.equal(respuestaSeguraParaMostrar(respuesta, data, entorno.ahora()), true, frase)
  assert.equal(respuestaSinImperativos(respuesta), true, frase)
  assert.doesNotMatch(respuesta.reply, MALAS, frase)
  return respuesta
}

test("«¿Cuándo pasa el B10 por Calle 100?»: minutos estimados, sentido y edad del dato", async () => {
  const r = await preguntar("¿Cuándo pasa el B10 por Calle 100?", instalarFeeds())
  assert.match(r.reply, /La B10 hacia Portal Norte llega a Calle 100/)
  assert.match(r.reply, /en (unos \d+ minutos|menos de un minuto|un minuto), estimado/)
  assert.match(r.reply, /Datos de hace \d+ segundos\./)
  assert.match(r.reply, /estimados y pueden variar/)
  assert.equal(r.action, "none")
})

test("«¿Cuándo pasa el B10 por Calle 72?»: la B10 no tiene esa parada y lo dice sin inventar", async () => {
  const r = await preguntar("¿Cuándo pasa el B10 por Calle 72?", instalarFeeds())
  assert.match(r.reply, /No encuentro Calle 72 en el recorrido de la B10/)
})

test("«¿Dónde viene el B10?»: buses en vía, sentido y entre qué paradas", async () => {
  const r = await preguntar("¿Dónde viene el B10?", instalarFeeds())
  assert.match(r.reply, /Hay 2 buses de la B10 en vía, hacia Portal Norte\. Uno va entre .+ y .+; otro va entre/)
  assert.match(r.reply, /Datos de hace/)
})

test("la 8 G y la 8 T se resuelven con su sentido", async () => {
  const g = await preguntar("¿Dónde viene la 8 G?", instalarFeeds())
  assert.match(g.reply, /de la 8 G en vía, hacia Guatoque/)
  const t = await preguntar("¿Dónde viene la 8T?", instalarFeeds())
  assert.match(t.reply, /de la 8 T en vía, hacia Terminal/)
})

test("un bus por su etiqueta: próximas paradas estimadas", async () => {
  const r = await preguntar("¿por dónde va el bus N0163?", instalarFeeds())
  assert.match(r.reply, /El bus N0163 va en la ruta B10 hacia Portal Norte\. Sus próximas paradas, estimadas: /)
  assert.match((await preguntar("dónde está el bus ZZ99-0000", instalarFeeds())).reply, /No veo un bus ZZ99-0000 en servicio/)
})

test("novedades: sin avisos vigentes lo dice; con avisos vigentes los lee", async () => {
  const sin = await preguntar("¿Hay novedades en el B10?", instalarFeeds())
  assert.match(sin.reply, /No hay novedades vigentes en la B10 en los avisos de TransMilenio/)
  const entorno = instalarFeeds()
  entorno.estado.alertasVigentes = true
  const con = await preguntar("¿hay novedades?", entorno)
  assert.match(con.reply, /^Hay \d+ novedades? vigentes?: /)
  assert.match(con.reply, /Confirma con TransMilenio antes de salir/)
})

test("estado del sistema, cancelados y salidas de hoy", async () => {
  const entorno = instalarFeeds()
  assert.match((await preguntar("¿cuántos buses hay en servicio?", entorno)).reply, /En este momento veo 50 buses en servicio: 36 buses de TransMilenio/)
  assert.match((await preguntar("¿cuántos viajes tiene hoy el B10?", entorno)).reply, /Hoy, para la B10: hacia Portal Norte: 186 salidas, de 04:30 a 21:30\. Es el horario programado del GTFS, no tiempo real/)
  // `tripupdates` se lee fuera de la petición: la primera vez aún no hay copia y lo dice.
  assert.match((await preguntar("¿cuántos viajes cancelados hay hoy?", entorno)).reply, /cargando la lista de viajes cancelados/)
  await new Promise((ok) => setTimeout(ok, 50))
  assert.match((await preguntar("¿cuántos viajes cancelados hay hoy?", entorno)).reply, /Hoy hay 78 viajes cancelados de 1\.498 programados\. Las rutas con más: 18-3 con 42/)
})

test("buscar parada sin tildes ni mayúsculas", async () => {
  assert.match((await preguntar("busca la parada CALLE 72", instalarFeeds())).reply, /Encontré .*Calle 72 - Areandina/)
  assert.match((await preguntar("busca la parada narnia", instalarFeeds())).reply, /No encontré una parada o estación llamada narnia/)
})

test("cerca de mí: sin ubicación abre el GPS; con ubicación habla de los buses a menos de 500 m", async () => {
  const entorno = instalarFeeds()
  const sin = await preguntar("¿hay buses cerca?", entorno)
  assert.equal(sin.action, "gps")
  const con = await preguntar("¿hay buses cerca?", entorno, { position: { lat: 4.67514, lng: -74.05911 } })
  assert.match(con.reply, /a menos de 500 metros de tu ubicación estimada: la B10 hacia Portal Norte/)
  const paradas = await preguntar("¿qué buses pasan cerca de mí?", entorno, { position: { lat: 4.67639, lng: -74.05896 } })
  assert.match(paradas.reply, /^Cerca de tu ubicación estimada: Virrey - Cendiatra, a /)
})

test("feed detenido: lo dice y no estima; da el horario publicado", async () => {
  const entorno = instalarFeeds({ segundosDespues: 400 })
  const r = await preguntar("¿Dónde viene el B10?", entorno)
  assert.match(r.reply, /no se actualizan hace 7 minutos/)
  assert.match(r.reply, /horario publicado entre semana de la B10/)
  assert.match(r.reply, /No es tiempo real/)
  assert.doesNotMatch(r.reply, /Hay \d+ buses/)
})

test("feed caído sin copia: respuesta honesta con el horario publicado", async () => {
  const entorno = instalarFeeds()
  entorno.estado.falla = true
  const r = await preguntar("¿Cuándo pasa el B10 por Calle 100?", entorno)
  assert.match(r.reply, /No pude consultar los datos en vivo de TransMilenio en este momento\./)
  assert.match(r.reply, /horario publicado entre semana de la B10/)
})

test("feed caído con copia anterior: la usa y lo avisa", async () => {
  const entorno = instalarFeeds()
  await preguntar("¿Dónde viene el B10?", entorno)
  entorno.estado.falla = true
  entorno.reloj.ms += 20_000
  const r = await preguntar("¿Dónde viene el B10?", entorno)
  assert.match(r.reply, /Hay 2 buses de la B10/)
  assert.match(r.reply, /No pude actualizar y uso la última copia\./)
  assert.match(r.reply, /Datos de hace 40 segundos\./)
})

test("índice vencido: no estima y lo dice", async () => {
  const entorno = instalarFeeds()
  entorno.reloj.ms = Date.parse("2027-01-15T10:00:00-05:00")
  const r = await preguntar("¿Dónde viene el B10?", entorno)
  assert.match(r.reply, /Mis datos de rutas y paradas están desactualizados/)
})

test("ruta o parada desconocida: no se adivina", async () => {
  const entorno = instalarFeeds()
  assert.match((await preguntar("cuándo pasa el bus 999 por Calle 100", entorno)).reply, /No encontré la ruta 999/)
  assert.match((await preguntar("¿hay novedades en el bus 999?", entorno)).reply, /No encontré la ruta 999/)
})

test("llegadas sin ruta ni estación pide el dato, sin leer feeds", async () => {
  const entorno = instalarFeeds()
  const r = await preguntar("cuándo llega el bus", entorno)
  assert.match(r.reply, /¿De qué ruta y en qué estación quieres saber\?/)
  assert.deepEqual(entorno.estado.llamadas, [])
})

test("una sola lectura de posiciones aunque lleguen varias preguntas seguidas", async () => {
  const entorno = instalarFeeds()
  await Promise.all([preguntar("¿Dónde viene el B10?", entorno), preguntar("¿Dónde viene la 8 G?", entorno), preguntar("¿cuántos buses hay en servicio?", entorno)])
  assert.equal(entorno.estado.llamadas.filter((u) => u.endsWith("positions.pb")).length, 1)
})

test("texto de alertas: un código interno no se lee; un título sí, con su efecto", () => {
  assert.equal(textoAlerta("PMTTP66CL1IDA", "DETOUR"), "un desvío")
  assert.equal(textoAlerta("GIRO PROHIBIDO/CLL73 X CRA.11/S-2", "DETOUR"), "desvío: Giro prohibido, cll73 x cra.11, s-2")
})
