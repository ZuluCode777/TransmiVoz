/**
 * Genera `data/gtfs-indice.json`: el índice compacto del GTFS estático de
 * TransMilenio que usa el asistente para dar tiempos en vivo (`lib/tiempo-real.ts`).
 *
 * El GTFS.zip pesa ~119 MB y `stop_times.txt` ~570 MB: no se baja en tiempo de
 * ejecución ni se versiona. Este script lo recorre en streaming (con `unzip -p`)
 * y deja solo lo que la estimación necesita:
 *
 * - toda la red (troncal, dual, alimentador, zonal y TransMiCable): `route_id` →
 *   código y destino;
 * - por cada `route_id`, el patrón de referencia: el viaje con más paradas, con
 *   sus paradas en orden y los segundos programados desde la primera;
 * - por cada ruta y servicio, la primera y la última salida y las salidas por hora;
 * - el calendario (`calendar.txt` y `calendar_dates.txt`);
 * - todas las paradas, con nombre, estación madre y coordenadas.
 *
 * Uso:
 *   pnpm sync:gtfs-indice                  # baja el zip a una carpeta temporal propia
 *   pnpm sync:gtfs-indice ruta/GTFS.zip    # usa un zip ya descargado
 *
 * Licencia del GTFS: CC BY-SA 4.0, TransMilenio S.A. El índice es una obra
 * derivada y conserva la atribución en sus metadatos.
 */
import { execFileSync, spawn } from "node:child_process"
import { createHash } from "node:crypto"
import { createReadStream, createWriteStream, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve, sep } from "node:path"
import { createInterface } from "node:readline"
import { Readable } from "node:stream"
import { pipeline } from "node:stream/promises"
import { MAX_EVIDENCIA_DIAS, fechaCivilEnZona } from "@/lib/evidencia"
import { fechaDePublicacionDelZip, gtfsVencido } from "@/lib/gtfs-publicacion"
import type { IndiceGtfs, RutaIndice } from "@/lib/gtfs-indice"

const URL_GTFS = "https://gtfs.transmilenio.gov.co/GTFS.zip"

/** Separa una línea CSV; solo recurre al análisis con comillas si las hay. */
function campos(linea: string): string[] {
  if (!linea.includes('"')) return linea.split(",")
  const salida: string[] = []
  let actual = ""
  let entre = false
  for (let i = 0; i < linea.length; i++) {
    const c = linea[i]
    if (entre) {
      if (c === '"' && linea[i + 1] === '"') {
        actual += '"'
        i++
      } else if (c === '"') entre = false
      else actual += c
    } else if (c === '"') entre = true
    else if (c === ",") {
      salida.push(actual)
      actual = ""
    } else actual += c
  }
  salida.push(actual)
  return salida
}

/** Recorre un archivo del zip fila por fila, con las columnas por nombre. */
async function filas(zip: string, archivo: string, cada: (fila: Record<string, string>) => void): Promise<void> {
  const proceso = spawn("unzip", ["-p", zip, archivo], { stdio: ["ignore", "pipe", "inherit"] })
  const terminado = new Promise<void>((ok, mal) => {
    proceso.on("error", mal)
    proceso.on("close", (codigo) => (codigo === 0 ? ok() : mal(new Error(`unzip ${archivo}: salió con ${codigo}`))))
  })
  let columnas: string[] | null = null
  for await (const linea of createInterface({ input: proceso.stdout, crlfDelay: Infinity })) {
    if (!linea) continue
    const valores = campos(linea)
    if (!columnas) {
      columnas = valores.map((c) => c.replace(/^﻿/, ""))
      continue
    }
    const fila: Record<string, string> = {}
    columnas.forEach((nombre, i) => (fila[nombre] = valores[i] ?? ""))
    cada(fila)
  }
  await terminado
}

function segundos(hora: string): number {
  const [h, m, s] = hora.split(":").map(Number)
  return h * 3600 + m * 60 + s
}

const fechaGtfs = (aaaammdd: string) => `${aaaammdd.slice(0, 4)}-${aaaammdd.slice(4, 6)}-${aaaammdd.slice(6, 8)}`
/** HH:MM de segundos desde la medianoche; puede pasar de 24 en servicios que cruzan la medianoche. */
const horaTexto = (s: number) => `${String(Math.floor(s / 3600)).padStart(2, "0")}:${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}`

const redondear = (n: number) => Math.round(n * 1e5) / 1e5

async function sha256(archivo: string): Promise<string> {
  const hash = createHash("sha256")
  await pipeline(createReadStream(archivo), hash)
  return hash.digest("hex")
}

const argumento = process.argv[2]
let carpeta: string | null = null
let zip: string
try {
  if (argumento) {
    zip = resolve(argumento)
  } else {
    carpeta = mkdtempSync(join(tmpdir(), "visionaria-gtfs-"))
    zip = join(carpeta, "GTFS.zip")
    const respuesta = await fetch(URL_GTFS, { headers: { "User-Agent": "visionaria-indice-gtfs" } })
    if (!respuesta.ok || !respuesta.body) throw new Error(`GTFS.zip: HTTP ${respuesta.status}`)
    await pipeline(Readable.fromWeb(respuesta.body as never), createWriteStream(zip))
  }
  // Fecha de publicación: la del PROPIO zip (hora de sus entradas), nunca la del manifiesto de hoy ni la del
  // archivo en disco. Un zip viejo da una fecha vieja, y un índice vencido no se estampa como nuevo.
  const publicado = fechaDePublicacionDelZip(execFileSync("unzip", ["-l", zip], { encoding: "utf8", maxBuffer: 1 << 20 }))
  if (gtfsVencido(publicado)) throw new Error(`Este GTFS es del ${publicado}, de hace más de ${MAX_EVIDENCIA_DIAS} días: baja el vigente (sin argumento) y vuelve a correr.`)

  // routes.txt: toda la red (troncal, dual, alimentador, zonal y TransMiCable).
  const rutas = new Map<string, { codigo: string; destino: string; agencia: string }>()
  await filas(zip, "routes.txt", (f) => {
    rutas.set(f.route_id, { codigo: f.route_short_name.trim(), destino: f.route_long_name.replace(/\s+/g, " ").trim(), agencia: f.agency_id })
  })

  // trips.txt: viaje → ruta y servicio.
  const viajes = new Map<string, { ruta: string; servicio: string }>()
  await filas(zip, "trips.txt", (f) => {
    if (rutas.has(f.route_id)) viajes.set(f.trip_id, { ruta: f.route_id, servicio: f.service_id })
  })

  // frequencies.txt: TransMiCable no lista cada salida, da una cada `headway_secs`.
  const frecuencias = new Map<string, { inicio: number; fin: number; cada: number }[]>()
  await filas(zip, "frequencies.txt", (f) => {
    const lista = frecuencias.get(f.trip_id) ?? []
    lista.push({ inicio: segundos(f.start_time), fin: segundos(f.end_time), cada: Number(f.headway_secs) })
    frecuencias.set(f.trip_id, lista)
  })

  // calendar.txt y calendar_dates.txt: qué servicio corre cada día.
  const servicios: IndiceGtfs["calendario"]["servicios"] = {}
  await filas(zip, "calendar.txt", (f) => {
    servicios[f.service_id] = {
      dias: [f.sunday, f.monday, f.tuesday, f.wednesday, f.thursday, f.friday, f.saturday].map((d) => d).join(""),
      inicio: fechaGtfs(f.start_date),
      fin: fechaGtfs(f.end_date),
    }
  })
  const excepciones: IndiceGtfs["calendario"]["excepciones"] = []
  await filas(zip, "calendar_dates.txt", (f) => {
    excepciones.push([f.service_id, fechaGtfs(f.date), Number(f.exception_type)])
  })

  // stop_times.txt, pasada 1: cuántas paradas tiene cada viaje y cuándo sale. Las
  // filas de un viaje no vienen juntas ni en orden, así que hacen falta dos pasadas.
  const cuenta = new Map<string, number>()
  const salida = new Map<string, number>()
  await filas(zip, "stop_times.txt", (f) => {
    if (!viajes.has(f.trip_id)) return
    cuenta.set(f.trip_id, (cuenta.get(f.trip_id) ?? 0) + 1)
    const hora = segundos(f.departure_time || f.arrival_time)
    const previa = salida.get(f.trip_id)
    if (previa === undefined || hora < previa) salida.set(f.trip_id, hora)
  })
  // El viaje con más paradas por ruta (a igualdad, el de id menor: determinista).
  const referencia = new Map<string, string>()
  for (const [viaje, n] of cuenta) {
    const ruta = viajes.get(viaje)!.ruta
    const actual = referencia.get(ruta)
    const nActual = actual === undefined ? -1 : cuenta.get(actual)!
    if (n > nActual || (n === nActual && viaje < actual!)) referencia.set(ruta, viaje)
  }
  const viajesReferencia = new Set(referencia.values())

  // Horario por ruta y servicio: primera y última salida y salidas por hora de salida.
  const horarios = new Map<string, Record<string, { primera: number; ultima: number; porHora: number[] }>>()
  const contar = (ruta: string, servicio: string, hora: number, veces = 1) => {
    const porServicio = horarios.get(ruta) ?? {}
    const h = (porServicio[servicio] ??= { primera: hora, ultima: hora, porHora: [] })
    h.primera = Math.min(h.primera, hora)
    h.ultima = Math.max(h.ultima, hora)
    const franja = Math.floor(hora / 3600)
    while (h.porHora.length <= franja) h.porHora.push(0)
    h.porHora[franja] += veces
    horarios.set(ruta, porServicio)
  }
  for (const [viaje, { ruta, servicio }] of viajes) {
    const primera = salida.get(viaje)
    if (primera === undefined) continue
    const rangos = frecuencias.get(viaje)
    if (!rangos) {
      contar(ruta, servicio, primera)
      continue
    }
    for (const { inicio, fin, cada } of rangos) for (let t = inicio; t < fin; t += cada) contar(ruta, servicio, t)
  }

  // Pasada 2: las filas de los viajes de referencia.
  const filasViaje = new Map<string, { sec: number; parada: string; llegada: number }[]>()
  await filas(zip, "stop_times.txt", (f) => {
    if (!viajesReferencia.has(f.trip_id)) return
    const lista = filasViaje.get(f.trip_id) ?? []
    lista.push({ sec: Number(f.stop_sequence), parada: f.stop_id, llegada: segundos(f.arrival_time) })
    filasViaje.set(f.trip_id, lista)
  })

  // stops.txt: todas las paradas de la red.
  const todas = new Map<string, { nombre: string; nodo: string; tipo: string; lat: number; lng: number }>()
  await filas(zip, "stops.txt", (f) => {
    todas.set(f.stop_id, { nombre: f.stop_name.replace(/\s+/g, " ").trim(), nodo: f.parent_station, tipo: f.location_type, lat: Number(f.stop_lat), lng: Number(f.stop_lon) })
  })

  const patrones: RutaIndice[] = []
  for (const [rutaId, viaje] of [...referencia].sort((a, b) => Number(a[0]) - Number(b[0]))) {
    const ordenadas = filasViaje.get(viaje)!.sort((a, b) => a.sec - b.sec)
    const base = ordenadas[0].llegada
    const paradas: [string, number][] = []
    for (const fila of ordenadas) {
      if (!todas.has(fila.parada)) continue
      const desfase = fila.llegada - base
      if (paradas.length > 0 && desfase < paradas[paradas.length - 1][1]) throw new Error(`Horas que retroceden en el viaje ${viaje}`)
      paradas.push([fila.parada, desfase])
    }
    const r = rutas.get(rutaId)!
    if (paradas.length < 2) continue
    const horario = Object.fromEntries(
      Object.entries(horarios.get(rutaId) ?? {}).map(([servicio, h]) => [servicio, [horaTexto(h.primera), horaTexto(h.ultima), h.porHora] as [string, string, number[]]]),
    )
    patrones.push({ id: rutaId, codigo: r.codigo, destino: r.destino, agencia: r.agencia, paradas, horario })
  }

  const paradas: IndiceGtfs["paradas"] = {}
  for (const [id, p] of [...todas].sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
    paradas[id] = [p.nombre, p.nodo || (p.tipo === "1" ? id : ""), redondear(p.lat), redondear(p.lng)]
  }

  const indice: IndiceGtfs = {
    fuente: URL_GTFS,
    publicado,
    generado: fechaCivilEnZona(new Date()),
    sha256: await sha256(zip),
    licencia: "CC BY-SA 4.0",
    atribucion: "TransMilenio S.A., GTFS estático (gtfs.transmilenio.gov.co). Obra derivada: patrones de referencia y paradas, bajo CC BY-SA 4.0.",
    calendario: { servicios, excepciones },
    rutas: patrones,
    paradas,
  }
  writeFileSync(new URL("../data/gtfs-indice.json", import.meta.url), JSON.stringify(indice) + "\n")
  console.log(`Índice: ${patrones.length} rutas, ${Object.keys(paradas).length} paradas, publicado ${publicado}, sha256 ${indice.sha256}.`)
} finally {
  // Solo se borra la carpeta que este script creó, y solo si está dentro de la temporal.
  if (carpeta && resolve(carpeta).startsWith(resolve(tmpdir()) + sep)) rmSync(carpeta, { recursive: true })
}
