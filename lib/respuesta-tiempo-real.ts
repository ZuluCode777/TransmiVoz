import { spokenDistance } from "@/lib/geo"
import { contieneImperativoDeViaje, type AgentContext, type AgentEngine, type AgentReply, type AgentStep, type ConsultaTiempoReal } from "@/lib/local-agent"
import type { TransmilenioData } from "@/lib/routes"
import {
  consultarAlertas,
  consultarBusesRuta,
  consultarLlegadas,
  consultarParadasCercanas,
  consultarProximasParadasBus,
  metaDe,
  resolverRuta,
  type Contexto,
} from "@/lib/consulta-tiempo-real"
import type { Meta } from "@/lib/contrato-tiempo-real"
import { indiceVigente } from "@/lib/gtfs-indice"
import { saludDeFeeds } from "@/lib/gtfs-rt"
import { tomarContexto, type Necesidades } from "@/lib/instantanea-servidor"
import { busesCercanos, buscarParadas, cabeceraVieja, canceladosHoy, estadoSistema, horarioDeRutas, textoDestino, type Llegada } from "@/lib/tiempo-real"
import { ubicacionVigente } from "@/lib/ubicacion"

/**
 * Respuestas HABLADAS de las preguntas en vivo, con la misma forma `AgentReply` que
 * el resto del asistente (el iPhone la decodifica igual: no cambia ningún cliente).
 *
 * Reglas del texto, porque lo escuchan personas ciegas o con baja visión:
 * - Corto y en español hablado. Siempre «estimado», en minutos, y la edad del dato
 *   («datos de hace 40 segundos»).
 * - Nunca promete: dice «estimado» y que puede variar; no da órdenes de abordaje.
 * - Si el feed está detenido, falla o tarda, lo dice y ofrece el horario publicado.
 */

const NECESIDADES: Record<ConsultaTiempoReal["tema"], Necesidades> = {
  llegadas: { posiciones: true, alertas: false, retrasos: true },
  buses: { posiciones: true, alertas: false, retrasos: true },
  bus: { posiciones: true, alertas: false, retrasos: true },
  paradas_cercanas: { posiciones: true, alertas: false, retrasos: true },
  buses_cercanos: { posiciones: true, alertas: false, retrasos: true },
  sistema: { posiciones: true, alertas: false, retrasos: false },
  novedades: { posiciones: false, alertas: true, retrasos: false },
  cancelados: { posiciones: false, alertas: false, retrasos: true },
  buscar_parada: { posiciones: false, alertas: false, retrasos: false },
  salidas_hoy: { posiciones: false, alertas: false, retrasos: false },
  estado_datos: { posiciones: true, alertas: true, retrasos: true },
}

/** Qué feeds lee un tema (para adelantar su lectura mientras el modelo interpreta la frase). */
export function necesidadesDeConsulta(consulta: ConsultaTiempoReal): Necesidades {
  // Sin ruta ni estación solo se pide el dato que falta: no se lee ningún feed.
  if (consulta.tema === "llegadas" && !consulta.ruta && !consulta.parada) return { posiciones: false, alertas: false, retrasos: false }
  return NECESIDADES[consulta.tema]
}

const plural = (n: number, uno: string, varios: string) => `${n.toLocaleString("es-CO")} ${n === 1 ? uno : varios}`

/** «en unos 4 minutos», «en menos de un minuto». */
export function enTiempo(segundos: number): string {
  if (segundos < 60) return "en menos de un minuto"
  const m = Math.round(segundos / 60)
  return m === 1 ? "en un minuto" : `en unos ${m} minutos`
}

/** «hace 40 segundos», «hace 3 minutos». */
export function haceTiempo(segundos: number): string {
  if (segundos < 90) return `hace ${plural(Math.max(1, Math.round(segundos)), "segundo", "segundos")}`
  return `hace ${plural(Math.round(segundos / 60), "minuto", "minutos")}`
}

const edadDato = (meta: Meta) => (meta.edadDatosS === null ? "" : ` Datos de ${haceTiempo(meta.edadDatosS)}.`)
const avisoCopia = (meta: Meta) => (meta.copiaObsoleta ? " No pude actualizar y uso la última copia." : "")

/** Avisos que acompañan a toda respuesta en vivo: edad del dato, copia vieja y retrasos sin cargar. */
function cierre(meta: Meta, { retrasos = false }: { retrasos?: boolean } = {}): string {
  const sinRetrasos = retrasos && meta.retrasos === "sin-datos" ? " Aún no tengo los retrasos reportados." : ""
  return `${avisoCopia(meta)}${sinRetrasos}${edadDato(meta)}`
}

const rutaDelCatalogo = (codigo: string, data: TransmilenioData) =>
  data.routes.find((r) => r.code.replace(/\s+/g, "").toUpperCase() === codigo.replace(/\s+/g, "").toUpperCase())

/** Lo que sí hay cuando no hay datos en vivo: el horario publicado de la ruta, aclarado como tal. */
function horarioDeRespaldo(codigo: string | undefined, data: TransmilenioData): string {
  const ruta = codigo ? rutaDelCatalogo(codigo, data) : undefined
  const entreSemana = ruta?.schedule.weekday.replace(/\.\s*$/, "")
  return entreSemana ? ` Lo que tengo es el horario publicado entre semana de la ${ruta!.code}: ${entreSemana}. No es tiempo real.` : ""
}

/** Una llegada hablada: «en unos 4 minutos» y, si el retraso reportado es notable, «con unos 3 minutos de retraso reportado». */
function llegadaHablada(l: Llegada): string {
  const retraso = l.retraso !== null && Math.abs(l.retraso) >= 180 ? `, con unos ${Math.round(Math.abs(l.retraso) / 60)} minutos de ${l.retraso > 0 ? "retraso" : "adelanto"} reportado` : ""
  return `${enTiempo(l.segundos)}${retraso}`
}

/** Agrupa por ruta y sentido, en el orden de la primera llegada de cada grupo. */
function porRutaYSentido(llegadas: Llegada[]): Llegada[][] {
  const grupos = new Map<string, Llegada[]>()
  for (const l of llegadas) grupos.set(`${l.codigo}|${l.destino}`, [...(grupos.get(`${l.codigo}|${l.destino}`) ?? []), l])
  return [...grupos.values()]
}

/** «La B10 hacia Portal Norte», «la 8 hacia Guatoque». */
const nombreServicio = (l: Llegada) => `la ${l.codigo} ${textoDestino(l.destino)}`

/** Frase de un grupo: la primera llegada en vivo y la siguiente; las programadas, aparte y rotuladas. */
function frasesDeGrupo(grupo: Llegada[], parada: string): string {
  const vivas = grupo.filter((l) => l.origen === "en-vivo")
  const programadas = grupo.filter((l) => l.origen === "programado")
  const partes: string[] = []
  if (vivas.length > 0) {
    partes.push(`${nombreServicio(vivas[0])} llega a ${parada} ${llegadaHablada(vivas[0])}, estimado${vivas[1] ? `; el siguiente, ${enTiempo(vivas[1].segundos)}` : ""}`)
  }
  if (programadas.length > 0) {
    const [primera] = programadas
    partes.push(vivas.length > 0 ? `según la programación, otro ${llegadaHablada(primera)}` : `${nombreServicio(primera)}: la próxima salida programada llegaría ${llegadaHablada(primera)}, sin bus en vivo confirmado`)
  }
  return partes.join("; ")
}

function textoLlegadas(llegadas: Llegada[], parada: string, conRuta: boolean): string {
  const grupos = porRutaYSentido(llegadas)
  if (conRuta) return `${grupos.map((g) => mayuscula(frasesDeGrupo(g, parada))).join(". ")}.`
  const mostrados = grupos.slice(0, 3).map((g) => frasesDeGrupo(g, parada))
  const resto = grupos.length - mostrados.length
  return `En ${parada}, tiempos estimados: ${mostrados.join("; ")}${resto > 0 ? `; y ${plural(resto, "servicio más", "servicios más")}` : ""}.`
}

/** Aviso en español de una alerta: el título del feed, o el efecto si el título es un código. */
export function textoAlerta(titulo: string, efecto: string): string {
  const EFECTOS: Record<string, string> = {
    NO_SERVICE: "sin servicio",
    REDUCED_SERVICE: "servicio reducido",
    SIGNIFICANT_DELAYS: "demoras importantes",
    DETOUR: "desvío",
    ADDITIONAL_SERVICE: "servicio adicional",
    MODIFIED_SERVICE: "servicio modificado",
    STOP_MOVED: "parada trasladada",
    ACCESSIBILITY_ISSUE: "problema de accesibilidad",
  }
  const etiqueta = EFECTOS[efecto] ?? "novedad"
  const limpio = titulo.replace(/[/_|]+/g, ", ").replace(/\s+/g, " ").replace(/(,\s*)+/g, ", ").trim()
  // Un título sin espacios («PMTTP66CL1IDA») es un código interno, no algo que leer en voz alta.
  if (!/\s/.test(limpio) || limpio.length < 6) return `un ${etiqueta}`
  return `${etiqueta}: ${limpio.charAt(0) + limpio.slice(1).toLowerCase()}`
}

const mayuscula = (texto: string) => texto.charAt(0).toUpperCase() + texto.slice(1)
const lista = (partes: string[]) => (partes.length > 1 ? `${partes.slice(0, -1).join(", ")} y ${partes.at(-1)}` : (partes[0] ?? ""))
const ayudaLlegadas = "¿De qué ruta y en qué estación quieres saber? Por ejemplo: cuándo pasa el B10 por Calle 72."

type Resuelto = { reply: string; action?: "none" | "gps"; steps?: AgentStep[] }

async function resolver(consulta: ConsultaTiempoReal, ctx: Contexto, context: AgentContext): Promise<Resuelto> {
  const { data, i } = ctx
  const meta = metaDe(ctx)
  const necesita = necesidadesDeConsulta(consulta)
  const consultaRuta = "ruta" in consulta ? consulta.ruta : undefined

  if (!indiceVigente(i.indice, new Date(i.ahora))) {
    return { reply: `Mis datos de rutas y paradas están desactualizados, así que no estimo llegadas ni buses.${horarioDeRespaldo(consultaRuta, data)}` }
  }
  if ((necesita.posiciones && !i.posiciones) || (necesita.alertas && !i.alertas)) {
    return { reply: `No pude consultar los datos en vivo de TransMilenio en este momento.${horarioDeRespaldo(consultaRuta, data)}` }
  }
  const detenido = necesita.posiciones && meta.detenido
  if (detenido && consulta.tema !== "estado_datos") {
    return { reply: `Los datos en vivo de TransMilenio no se actualizan ${haceTiempo(meta.edadDatosS ?? 0)}, así que no estimo llegadas ni buses.${horarioDeRespaldo(consultaRuta, data)}` }
  }
  if (necesita.alertas && i.alertas && cabeceraVieja(i.alertas.datos.cabecera, i.ahora) && consulta.tema === "novedades") {
    return { reply: `Los avisos de TransMilenio no se actualizan ${haceTiempo(i.ahora / 1000 - i.alertas.datos.cabecera)}, así que no puedo confirmar novedades. Confirma con TransMilenio.` }
  }
  const paso: AgentStep[] = [{ label: "Consulté los datos en vivo de TransMilenio", detail: meta.edadDatosS === null ? undefined : `datos de ${haceTiempo(meta.edadDatosS)}` }]

  switch (consulta.tema) {
    case "llegadas": {
      if (!consulta.ruta && !consulta.parada) return { reply: ayudaLlegadas }
      if (!consulta.parada) {
        // Sin estación se dice dónde está la ruta y se pide la estación.
        const buses = consultarBusesRuta(ctx, { ruta: consulta.ruta! })
        if (!buses.ok) return { reply: `No encontré la ruta ${consulta.ruta} en los datos de TransMilenio.` }
        return { reply: `${resumenBuses(buses, consulta.ruta!)} Dime en qué estación quieres saber cuándo llega, por ejemplo Calle 72.${cierre(buses.meta)}`, steps: paso }
      }
      if (!consulta.ruta) {
        return { reply: `Dime de qué ruta quieres saber la llegada a ${consulta.parada}, por ejemplo B10.` }
      }
      const r = consultarLlegadas(ctx, { parada: consulta.parada, ruta: consulta.ruta })
      if (!r.ok) {
        return { reply: r.error === "ruta-desconocida" ? `No encontré la ruta ${consulta.ruta} en los datos de TransMilenio.` : `No encontré la parada ${consulta.parada}.`, steps: paso }
      }
      if (r.motivo === "ruta-no-pasa-por-parada") {
        return { reply: `No encuentro ${r.parada} en el recorrido de la ${consulta.ruta} que tengo; puede que no pare ahí. Confirma con TransMilenio.`, steps: paso }
      }
      if (r.llegadas.length === 0) {
        return { reply: `No veo buses de la ${consulta.ruta} que lleguen a ${r.parada} en este momento.${salidasHoyFrase(ctx, consulta.ruta)}${cierre(r.meta)}`, steps: paso }
      }
      return { reply: `${textoLlegadas(r.llegadas, r.parada, true)} Son tiempos estimados y pueden variar.${cierre(r.meta, { retrasos: true })}`, steps: paso }
    }

    case "buses": {
      const r = consultarBusesRuta(ctx, { ruta: consulta.ruta })
      if (!r.ok) return { reply: `No encontré la ruta ${consulta.ruta} en los datos de TransMilenio.`, steps: paso }
      return { reply: `${resumenBuses(r, consulta.ruta)}${r.buses.length === 0 ? salidasHoyFrase(ctx, consulta.ruta) : ""}${cierre(r.meta)}`, steps: paso }
    }

    case "bus": {
      const r = consultarProximasParadasBus(ctx, { bus: consulta.bus })
      if (!r.ok) {
        return { reply: r.error === "bus-sin-ubicar" ? `Encontré el bus ${consulta.bus}, pero no puedo ubicarlo sobre su recorrido.` : `No veo un bus ${consulta.bus} en servicio ahora.`, steps: paso }
      }
      const paradas = r.paradas.slice(0, 4).map((p) => `${p.nombre} ${enTiempo(p.segundos)}`)
      return {
        reply: `El bus ${r.bus.etiqueta} va en la ruta ${r.bus.codigo} ${textoDestino(r.bus.destino)}. ${paradas.length ? `Sus próximas paradas, estimadas: ${lista(paradas)}.` : "Está llegando al final de su recorrido."}${cierre(r.meta)}`,
        steps: paso,
      }
    }

    case "paradas_cercanas":
    case "buses_cercanos": {
      const posicion = ubicacionVigente(context.position, i.ahora)
      if (!posicion) {
        return { reply: "Para saber qué buses hay cerca necesito tu ubicación. Abro el GPS auditivo para que la compartas.", action: "gps" }
      }
      if (consulta.tema === "buses_cercanos") {
        const cerca = busesCercanos(i, posicion, { radioM: 500, max: 4 })
        if (cerca.length === 0) return { reply: `No veo buses a menos de 500 metros de tu ubicación estimada.${cierre(meta)}`, steps: paso }
        return {
          reply: `Hay ${plural(cerca.length, "bus", "buses")} a menos de 500 metros de tu ubicación estimada: ${lista(cerca.map((b) => `la ${b.codigo || "ruta sin identificar"} ${b.destino ? textoDestino(b.destino) : ""}, a ${spokenDistance(b.distancia)}`.replace(/\s+,/g, ",")))}.${cierre(meta)}`,
          steps: paso,
        }
      }
      const r = consultarParadasCercanas(ctx, { lat: posicion.lat, lng: posicion.lng, radio: 800, max: 2, conLlegadas: true })
      if (r.paradas.length === 0) return { reply: `No encuentro paradas a menos de 800 metros de tu ubicación estimada.${cierre(meta)}`, steps: paso }
      const partes = r.paradas.map((p) => {
        const grupos = porRutaYSentido(p.llegadas ?? []).slice(0, 2)
        const llegadas = grupos.length ? `: ${grupos.map((g) => `${nombreServicio(g[0])} ${llegadaHablada(g[0])}`).join("; ")}` : ", sin llegadas que pueda estimar ahora"
        return `${p.nombre}, a ${spokenDistance(p.distancia)}${llegadas}`
      })
      return { reply: `Cerca de tu ubicación estimada: ${partes.join(". ")}. Son tiempos estimados.${cierre(r.meta)}`, steps: paso }
    }

    case "novedades": {
      const r = consultarAlertas(ctx, { ruta: consulta.ruta, parada: consulta.parada })
      const sobre = [consulta.ruta ? `la ${consulta.ruta}` : null, consulta.parada ? `la estación ${consulta.parada}` : null].filter(Boolean).join(" y ")
      if (!r.ok) {
        return { reply: r.error === "ruta-desconocida" ? `No encontré la ruta ${consulta.ruta} en los datos de TransMilenio.` : `No encontré la parada ${consulta.parada}.`, steps: paso }
      }
      if (r.alertas.length === 0) return { reply: `No hay novedades vigentes${sobre ? ` en ${sobre}` : ""} en los avisos de TransMilenio.${cierre(r.meta)}`, steps: paso }
      const mostradas = r.alertas.slice(0, 3).map((a) => textoAlerta(a.titulo, a.efecto))
      const resto = r.alertas.length - mostradas.length
      return {
        reply: `Hay ${plural(r.alertas.length, "novedad vigente", "novedades vigentes")}${sobre ? ` en ${sobre}` : ""}: ${mostradas.join("; ")}${resto > 0 ? `; y ${resto} más` : ""}. Confirma con TransMilenio antes de salir.${cierre(r.meta)}`,
        steps: paso,
      }
    }

    case "buscar_parada": {
      const encontradas = buscarParadas(i.indice, consulta.texto, 4)
      if (encontradas.length === 0) return { reply: `No encontré una parada o estación llamada ${consulta.texto}.`, steps: paso }
      return { reply: `Encontré ${lista(encontradas.map((p) => p.nombre))}.`, steps: paso }
    }

    case "sistema": {
      const s = estadoSistema(i)
      if (s.total === 0) return { reply: `No veo buses reportando en este momento.${cierre(meta)}`, steps: paso }
      const g = s.grupos
      const partes = [`${plural(g.transmilenio, "bus", "buses")} de TransMilenio (troncal, dual y alimentador)`, `${plural(g.zonal, "zonal", "zonales")}`]
      if (g.cable > 0) partes.push(`${plural(g.cable, "cabina", "cabinas")} de TransMiCable`)
      return { reply: `En este momento veo ${plural(s.total, "bus", "buses")} en servicio: ${lista(partes)}.${cierre(meta)}`, steps: paso }
    }

    case "salidas_hoy": {
      const rutas = resolverRuta(consulta.ruta, ctx)
      if (rutas.length === 0) return { reply: `No encontré la ruta ${consulta.ruta} en los datos de TransMilenio.`, steps: paso }
      const horarios = horarioDeRutas(i.indice, rutas.map((r) => r.id), i.ahora)
      const partes = horarios.map((h) => (h.salidasHoy === 0 ? `${textoDestino(h.destino)}: hoy no tiene salidas programadas` : `${textoDestino(h.destino)}: ${plural(h.salidasHoy, "salida", "salidas")}, de ${h.primera} a ${h.ultima}`))
      return { reply: `Hoy, para la ${consulta.ruta}: ${partes.join("; ")}. Es el horario programado del GTFS, no tiempo real.`, steps: paso }
    }

    case "cancelados": {
      const rutas = consulta.ruta ? resolverRuta(consulta.ruta, ctx) : undefined
      if (consulta.ruta && rutas!.length === 0) return { reply: `No encontré la ruta ${consulta.ruta} en los datos de TransMilenio.`, steps: paso }
      const c = canceladosHoy(i, rutas?.map((r) => r.id))
      if (!c) return { reply: "Todavía estoy cargando la lista de viajes cancelados de hoy. Pregúntame de nuevo en un minuto." }
      if (consulta.ruta) {
        return { reply: `Hoy hay ${plural(c.total, "viaje cancelado", "viajes cancelados")} de la ${consulta.ruta}, de ${c.viajesDelDia.toLocaleString("es-CO")} programados.`, steps: paso }
      }
      const peores = c.porRuta.slice(0, 3).map((r) => `${r.codigo} con ${r.cancelados}`)
      return { reply: `Hoy hay ${plural(c.total, "viaje cancelado", "viajes cancelados")} de ${c.viajesDelDia.toLocaleString("es-CO")} programados.${peores.length ? ` Las rutas con más: ${lista(peores)}.` : ""}`, steps: paso }
    }

    case "estado_datos": {
      const nombres: Record<string, string> = { positions: "las posiciones", alerts: "los avisos", tripupdates: "los retrasos" }
      const partes = saludDeFeeds().map((f) =>
        !f.conCopia ? `${nombres[f.feed]}: sin datos todavía` : `${nombres[f.feed]}: ${f.detenido ? "detenidos, " : ""}${haceTiempo(f.edadCabeceraS ?? 0)}${f.obsoleto ? ", copia anterior" : ""}`,
      )
      return { reply: `Estado de los datos en vivo: ${partes.join("; ")}.`, steps: paso }
    }
  }
}

/** «Hay 2 buses de la B10 en vía, hacia Portal Norte. Uno va entre X y Y…» */
function resumenBuses(r: { buses: { etiqueta: string; destino: string; anterior: string | null; siguiente: string | null }[]; destinos: string[]; sinUbicar: number }, ruta: string): string {
  if (r.buses.length === 0) return `No veo buses de la ${ruta} en vía en este momento.`
  const donde = (b: (typeof r.buses)[number]) => (b.anterior && b.siguiente ? (b.anterior === b.siguiente ? `está en ${b.anterior}` : `va entre ${b.anterior} y ${b.siguiente}`) : "no pude ubicarlo")
  const sentido = r.destinos.length === 1 ? `, ${textoDestino(r.destinos[0])}` : ""
  const detalle = r.buses.slice(0, 3).map((b, n) => `${n === 0 ? "Uno" : "otro"} ${donde(b)}`)
  const resto = r.buses.length - detalle.length
  return `Hay ${plural(r.buses.length, "bus", "buses")} de la ${ruta} en vía${sentido}. ${detalle.join("; ")}${resto > 0 ? `; y ${resto} más` : ""}.`
}

/** «Hoy tiene 186 salidas programadas, de 04:30 a 21:30.» para explicar por qué no hay buses. */
function salidasHoyFrase(ctx: Contexto, ruta: string): string {
  const rutas = resolverRuta(ruta, ctx)
  const h = horarioDeRutas(ctx.i.indice, rutas.map((r) => r.id), ctx.i.ahora).find((x) => x.salidasHoy > 0)
  return h ? ` Hoy tiene salidas programadas de ${h.primera} a ${h.ultima}.` : rutas.length ? " Según el GTFS, hoy no tiene salidas programadas." : ""
}

/**
 * Responde una pregunta en vivo. Lee solo los feeds que el tema necesita (con tope de
 * espera) y nunca falla: ante cualquier error responde con un aviso honesto. El texto
 * pasa por la guardia de órdenes de abordaje antes de salir.
 */
export async function responderTiempoReal(
  consulta: ConsultaTiempoReal,
  { data, context = {}, engine = "reglas" }: { data: TransmilenioData; context?: AgentContext; engine?: AgentEngine },
): Promise<AgentReply> {
  let resuelto: Resuelto
  try {
    const ctx = await tomarContexto(data, necesidadesDeConsulta(consulta), context.now?.getTime())
    resuelto = await resolver(consulta, ctx, context)
  } catch (error) {
    console.warn("[tiempo-real] error al responder:", error instanceof Error ? error.name : "desconocido")
    resuelto = { reply: "No pude consultar los datos en vivo de TransMilenio en este momento. Inténtalo de nuevo en unos segundos." }
  }
  const { reply, action = "none", steps = [] } = resuelto
  if (contieneImperativoDeViaje(reply)) {
    return { reply: "No puedo darte esa información en vivo de forma segura ahora. Confirma con TransMilenio.", action: "none", steps: [], engine }
  }
  return { reply, action, steps, engine }
}
