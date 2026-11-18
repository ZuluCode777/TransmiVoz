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
import type { Meta, PeticionTiempoReal } from "@/lib/contrato-tiempo-real"
import { indiceVigente } from "@/lib/gtfs-indice"
import { saludDeFeeds } from "@/lib/gtfs-rt"
import { normalize } from "@/lib/text"
import { cuandoLlega, enTiempo, frasesLlegada, haceTiempo, mayuscula, plural, textoDestino } from "@/lib/texto-tiempo-real"
import { necesidadesDe, tomarContexto, type Necesidades } from "@/lib/instantanea-servidor"
import { busesCercanos, buscarParadas, cabeceraVieja, canceladosHoy, estadoSistema, horarioDeRutas, type Llegada } from "@/lib/tiempo-real"
import { RESERVA_RESPUESTA_MS } from "@/lib/presupuesto-agente"
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

/**
 * Operación de `/api/tiempo-real` que contesta cada tema. Los feeds que lee un tema son EXACTAMENTE los de su
 * operación (`necesidadesDe`): así el asistente y el endpoint filtran con los mismos datos y dan los mismos números.
 */
const OPERACION: Record<Exclude<ConsultaTiempoReal["tema"], "estado_datos">, PeticionTiempoReal["operacion"]> = {
  llegadas: "llegadas",
  buses: "buses-ruta",
  bus: "proximas-paradas-bus",
  paradas_cercanas: "paradas-cercanas",
  buses_cercanos: "buses-cercanos",
  sistema: "estado-sistema",
  novedades: "alertas",
  cancelados: "cancelados-hoy",
  buscar_parada: "buscar-paradas",
  salidas_hoy: "horario-ruta",
}

/**
 * Feeds que conviene pedir YA, solo por la letra de la frase y antes de cargar el catálogo o de que el
 * modelo la interprete (que es cuando aún no se sabe el tema). Pedir de más cuesta poco: una lectura
 * por feed cada 15 s, compartida. `null` si la frase no parece de tiempo real.
 */
export function necesidadesPorTexto(texto: string): Necesidades | null {
  const t = normalize(texto)
  if (!/\b(bus|buses|ruta|llega|llegan|pasa|pasan|viene|vienen|cuando|cuanto|cuantos|donde|novedad|novedades|desvio|desvios|cancelado|cancelados|servicio|cerca|parada|vivo|tiempo real|alerta|alertas|aviso|avisos|cierre|bloqueo)\b|\b[a-z]{1,2}\d{2}\b|\b\d \w\b/.test(t)) return null
  const alertas = /\b(novedad|novedades|desvio|desvios|alerta|alertas|aviso|avisos|cierre|cierres|bloqueo|bloqueos)\b/.test(t)
  return { posiciones: !alertas, alertas, retrasos: true }
}

/** Qué feeds lee un tema (para adelantar su lectura mientras el modelo interpreta la frase). */
export function necesidadesDeConsulta(consulta: ConsultaTiempoReal): Necesidades {
  // Sin ruta ni estación solo se pide el dato que falta: no se lee ningún feed.
  if (consulta.tema === "llegadas" && !consulta.ruta && !consulta.parada) return { posiciones: false, alertas: false, retrasos: false }
  // El estado de los datos mira los tres feeds, para poder decir de cada uno si responde.
  if (consulta.tema === "estado_datos") return { posiciones: true, alertas: true, retrasos: true }
  return necesidadesDe(OPERACION[consulta.tema])
}

const edadDato = (meta: Meta) => (meta.edadDatosS === null ? "" : ` Datos de ${haceTiempo(meta.edadDatosS)}.`)
const avisoCopia = (meta: Meta) => (meta.copiaObsoleta ? " No pude actualizar y uso la última copia." : "")

/** Avisos que acompañan a toda respuesta en vivo: edad del dato, copia vieja y retrasos sin cargar. */
function cierre(meta: Meta, { retrasos = false }: { retrasos?: boolean } = {}): string {
  const estadoRetrasos =
    meta.retrasos === "detenido"
      ? ` Los retrasos y cancelaciones no se actualizan ${haceTiempo(meta.feeds.retrasos?.edadS ?? 0)}; no los incluyo.`
      : retrasos && meta.retrasos === "sin-datos"
        ? " Aún no tengo los retrasos reportados."
        : ""
  const sinRetrasos = estadoRetrasos
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

/** Agrupa por ruta y sentido, en el orden de la primera llegada de cada grupo. */
function porRutaYSentido(llegadas: Llegada[]): Llegada[][] {
  const grupos = new Map<string, Llegada[]>()
  for (const l of llegadas) grupos.set(`${l.codigo}|${l.destino}`, [...(grupos.get(`${l.codigo}|${l.destino}`) ?? []), l])
  return [...grupos.values()]
}

/** «La B10 hacia Portal Norte», «la 8 hacia Guatoque». */
const nombreServicio = (l: Llegada, etiqueta?: string) => `la ${etiqueta ?? l.codigo} ${textoDestino(l.destino)}`

/** Frase de un grupo: la primera llegada con bus en vivo y la siguiente; la programada, aparte y rotulada como tal. */
function frasesDeGrupo(grupo: Llegada[], parada: string, etiqueta?: string): string {
  const vivas = grupo.filter((l) => l.origen === "en-vivo")
  const programadas = grupo.filter((l) => l.origen === "programado")
  const servicio = (l: Llegada) => nombreServicio(l, etiqueta)
  const partes: string[] = []
  if (vivas.length > 0) partes.push(`${frasesLlegada(vivas[0], servicio(vivas[0]), parada)}${vivas[1] ? `; el siguiente, ${enTiempo(vivas[1].segundos)}` : ""}`)
  if (programadas.length > 0) {
    const [primera] = programadas
    partes.push(vivas.length > 0 ? `según la programación, otro ${cuandoLlega(primera)}` : frasesLlegada(primera, servicio(primera), parada))
  }
  return partes.join("; ")
}

function textoLlegadas(llegadas: Llegada[], parada: string, etiquetaRuta?: string): string {
  const grupos = porRutaYSentido(llegadas)
  if (etiquetaRuta) return `${grupos.map((g) => mayuscula(frasesDeGrupo(g, parada, etiquetaRuta))).join(". ")}.`
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

/** Texto de una consulta que no se pudo resolver: ruta o parada desconocida, o parada ambigua con sus opciones. */
function textoFalla(r: { error: string; opciones?: string[] }, consulta: { ruta?: string; parada?: string }): string {
  if (r.error === "ruta-desconocida") return `No encontré la ruta ${consulta.ruta} en los datos de TransMilenio.`
  if (r.error === "ruta-ambigua") return `Hay más de un servicio con el código ${consulta.ruta}: ${lista(r.opciones ?? [])}. ¿Cuál quieres? Dime el sistema, por ejemplo «${consulta.ruta} troncal» o «${consulta.ruta} zonal».`
  if (r.error === "parada-ambigua") return `Encontré varias paradas que se parecen a ${consulta.parada}: ${lista(r.opciones ?? [])}. ¿Cuál quieres? Dime el nombre completo.`
  return `No encontré la parada ${consulta.parada}.`
}

/** «Ojo: el código C25 también existe en zonal urbano; hablo del servicio troncal.» Los sistemas no se mezclan, y se dice. */
const notaSistema = (r: { sistema: string | null; tambienEn: string[] }, dicho: string | undefined) => {
  if (!dicho || !r.sistema || r.tambienEn.length === 0) return ""
  // Pedida por `route_id` («12756») no hay un código que nombrar: se habla de la línea.
  if (/^\d{4,6}$/.test(dicho)) return ` Ojo: ese servicio es del sistema ${r.sistema}; la misma línea también existe en ${lista(r.tambienEn)}.`
  const codigo = dicho.replace(/\s*\(?\b(?:troncal|dual|alimentadora?|zonal(?: urbano| complementario| especial)?|urbano|complementario|especial|transmicable|cable)\b\)?\s*$/i, "")
  return ` Ojo: el código ${codigo} también existe en ${lista(r.tambienEn)}; hablo del servicio ${r.sistema}.`
}

const lista = (partes: string[]) => (partes.length > 1 ? `${partes.slice(0, -1).join(", ")} y ${partes.at(-1)}` : (partes[0] ?? ""))
const ayudaLlegadas = "¿De qué ruta y en qué estación quieres saber? Por ejemplo: cuándo pasa el B10 por Calle 72."

export type Resuelto = { reply: string; action?: "none" | "gps"; steps?: AgentStep[] }

/** Resuelve una consulta con un contexto ya armado (feeds + índice); `responderTiempoReal` lo arma y lo llama. */
export async function resolverTiempoReal(consulta: ConsultaTiempoReal, ctx: Contexto, context: AgentContext): Promise<Resuelto> {
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
        if (!buses.ok) return { reply: textoFalla(buses, consulta) }
        return { reply: `${resumenBuses(buses, consulta.ruta!)} Dime en qué estación quieres saber cuándo llega, por ejemplo Calle 72.${cierre(buses.meta)}`, steps: paso }
      }
      // Con o sin ruta: sin ruta se listan los servicios que llegan a la estación, agrupados por ruta y sentido.
      const r = consultarLlegadas(ctx, { parada: consulta.parada, ruta: consulta.ruta, max: consulta.ruta ? 6 : 12 })
      if (!r.ok) return { reply: textoFalla(r, consulta), steps: paso }
      if (r.motivo === "ruta-no-pasa-por-parada") {
        return { reply: `No encuentro ${r.parada} en el recorrido de la ${consulta.ruta} que tengo; puede que no pare ahí. Confirma con TransMilenio.`, steps: paso }
      }
      if (r.llegadas.length === 0) {
        return { reply: `No veo buses ${consulta.ruta ? `de la ${consulta.ruta} ` : ""}que lleguen a ${r.parada} en este momento.${consulta.ruta ? salidasHoyFrase(ctx, consulta.ruta) : ""}${notaSistema(r, consulta.ruta)}${cierre(r.meta)}`, steps: paso }
      }
      return { reply: `${textoLlegadas(r.llegadas, r.parada, consulta.ruta)} Son tiempos estimados y pueden variar.${notaSistema(r, consulta.ruta)}${cierre(r.meta, { retrasos: true })}`, steps: paso }
    }

    case "buses": {
      const r = consultarBusesRuta(ctx, { ruta: consulta.ruta })
      if (!r.ok) return { reply: textoFalla(r, consulta), steps: paso }
      return { reply: `${resumenBuses(r, consulta.ruta)}${r.buses.length === 0 ? salidasHoyFrase(ctx, consulta.ruta) : ""}${notaSistema(r, consulta.ruta)}${cierre(r.meta)}`, steps: paso }
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
        const llegadas = grupos.length ? `: ${grupos.map((g) => frasesLlegada(g[0], nombreServicio(g[0]))).join("; ")}` : ", sin llegadas que pueda estimar ahora"
        return `${p.nombre}, a ${spokenDistance(p.distancia)}${llegadas}`
      })
      return { reply: `Cerca de tu ubicación estimada: ${partes.join(". ")}. Son tiempos estimados.${cierre(r.meta)}`, steps: paso }
    }

    case "novedades": {
      const r = consultarAlertas(ctx, { ruta: consulta.ruta, parada: consulta.parada })
      const sobre = [consulta.ruta ? `la ${consulta.ruta}` : null, r.ok && r.parada ? `la estación ${r.parada}` : null].filter(Boolean).join(" y ")
      if (!r.ok) return { reply: textoFalla(r, consulta), steps: paso }
      if (r.alertas.length === 0) return { reply: `No hay novedades vigentes${sobre ? ` en ${sobre}` : ""} en los avisos de TransMilenio.${notaSistema(r, consulta.ruta)}${cierre(r.meta)}`, steps: paso }
      const mostradas = r.alertas.slice(0, 3).map((a) => textoAlerta(a.titulo, a.efecto))
      const resto = r.alertas.length - mostradas.length
      return {
        reply: `Hay ${plural(r.alertas.length, "novedad vigente", "novedades vigentes")}${sobre ? ` en ${sobre}` : ""}: ${mostradas.join("; ")}${resto > 0 ? `; y ${resto} más` : ""}. Confirma con TransMilenio antes de salir.${notaSistema(r, consulta.ruta)}${cierre(r.meta)}`,
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
      const res = resolverRuta(consulta.ruta, ctx)
      if (res.tipo !== "ok") return { reply: textoFalla(res.tipo === "ambigua" ? { error: "ruta-ambigua", opciones: res.opciones } : { error: "ruta-desconocida" }, consulta), steps: paso }
      const horarios = horarioDeRutas(i.indice, res.rutas.map((r) => r.id), i.ahora)
      const partes = horarios.map((h) => (h.salidasHoy === 0 ? `${textoDestino(h.destino)}: hoy no tiene salidas programadas` : `${textoDestino(h.destino)}: ${plural(h.salidasHoy, "salida", "salidas")}, de ${h.primera} a ${h.ultima}`))
      return { reply: `Hoy, para la ${consulta.ruta}: ${partes.join("; ")}. Es el horario programado del GTFS, no tiempo real.${notaSistema(res, consulta.ruta)}`, steps: paso }
    }

    case "cancelados": {
      const res = consulta.ruta ? resolverRuta(consulta.ruta, ctx) : undefined
      if (res && res.tipo !== "ok") return { reply: textoFalla(res.tipo === "ambigua" ? { error: "ruta-ambigua", opciones: res.opciones } : { error: "ruta-desconocida" }, consulta), steps: paso }
      const c = canceladosHoy(i, res?.rutas.map((r) => r.id))
      if (!c) {
        if (meta.retrasos === "detenido") return { reply: `La lista de viajes cancelados no se actualiza ${haceTiempo(meta.feeds.retrasos?.edadS ?? 0)}, así que no puedo decir cuántos hay hoy.` }
        return { reply: "Todavía estoy cargando la lista de viajes cancelados de hoy. Pregúntame de nuevo en un minuto." }
      }
      if (consulta.ruta) {
        return { reply: `Hoy hay ${plural(c.total, "viaje cancelado", "viajes cancelados")} de la ${consulta.ruta}, de ${c.viajesDelDia.toLocaleString("es-CO")} programados.${notaSistema(res!, consulta.ruta)}`, steps: paso }
      }
      // Un mismo código tiene varios `route_id` (ida, vuelta, variantes): se suman.
      const porCodigo = new Map<string, number>()
      for (const r of c.porRuta) porCodigo.set(r.codigo, (porCodigo.get(r.codigo) ?? 0) + r.cancelados)
      const peores = [...porCodigo].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([codigo, n]) => `${codigo} con ${n}`)
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
  const res = resolverRuta(ruta, ctx)
  if (res.tipo !== "ok") return ""
  const h = horarioDeRutas(ctx.i.indice, res.rutas.map((r) => r.id), ctx.i.ahora).find((x) => x.salidasHoy > 0)
  return h ? ` Hoy tiene salidas programadas de ${h.primera} a ${h.ultima}.` : " Según el GTFS, hoy no tiene salidas programadas."
}

/**
 * Responde una pregunta en vivo. Lee solo los feeds que el tema necesita (con tope de
 * espera) y nunca falla: ante cualquier error responde con un aviso honesto. El texto
 * pasa por la guardia de órdenes de abordaje antes de salir.
 */
export async function responderTiempoReal(
  consulta: ConsultaTiempoReal,
  {
    data,
    context = {},
    engine = "reglas",
    presupuestoMs,
  }: {
    data: TransmilenioData
    context?: AgentContext
    engine?: AgentEngine
    /** Lo que queda del presupuesto de la petición: los feeds no esperan más que eso (ver `lib/presupuesto-agente.ts`). */
    presupuestoMs?: number
  },
): Promise<AgentReply> {
  let resuelto: Resuelto
  try {
    const ctx = await tomarContexto(data, necesidadesDeConsulta(consulta), context.now?.getTime(), presupuestoMs === undefined ? undefined : Math.max(0, presupuestoMs - RESERVA_RESPUESTA_MS))
    resuelto = await resolverTiempoReal(consulta, ctx, context)
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
