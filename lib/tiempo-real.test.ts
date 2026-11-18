import assert from "node:assert/strict"
import test from "node:test"
import type { Posiciones, Retrasos, ViajeRt } from "@/lib/gtfs-rt"
import { IndiceGtfsSchema, indiceVigente, rutasGtfsDeRuta, type IndiceGtfs } from "@/lib/gtfs-indice"
import {
  alertasVigentes,
  buscarBus,
  buscarParadas,
  busesCercanos,
  busesDeRutas,
  busesVigentes,
  canceladosHoy,
  estadoSistema,
  horarioDeRutas,
  llegadasEnParada,
  retrasosUsables,
  paradasCercanas,
  proximasParadasDeBus,
  serviciosDelDia,
  textoDestino,
  type Instantanea,
} from "@/lib/tiempo-real"
import { CABECERA_MUESTRA, instantaneaDeMuestra } from "@/lib/fixtures-gtfs/cargar"
import snapshot from "@/data/transmilenio.json" with { type: "json" }
import indiceJson from "@/data/gtfs-indice.json" with { type: "json" }
import { TransmilenioDataSchema } from "@/lib/transmilenio"

/**
 * Índice sintético en línea recta sobre el ecuador (1° de longitud ≈ 111,32 km): tres
 * paradas, A (0 s), B (300 s) y C (600 s), a 0,009° ≈ 1 km una de otra. Así la
 * posición de un bus y los segundos esperados se calculan a mano.
 */
const ID = (n: string) => n
const GRADOS_POR_KM = 1 / 111.32
function indiceLinea(): IndiceGtfs {
  const p = (nombre: string, km: number): [string, string, number, number] => [nombre, "", 0, km * GRADOS_POR_KM]
  return IndiceGtfsSchema.parse({
    fuente: "x", publicado: "2026-11-17", generado: "2026-11-17", sha256: "x", licencia: "x", atribucion: "x",
    calendario: { servicios: {}, excepciones: [] },
    rutas: [{ id: "R1", codigo: "T1", destino: "Fin", agencia: "1", paradas: [["A", 0], ["B", 300], ["C", 600]], horario: {} }],
    paradas: { A: p("Alfa", 0), B: p("Beta", 1), C: p("Gama", 2) },
  })
}
const AHORA = 1_800_000_000
function conBus(opciones: { km: number; hace?: number; tripId?: string; cabeceraHace?: number; retrasos?: ViajeRt[] }): Instantanea {
  const posiciones: Posiciones = {
    cabecera: AHORA - (opciones.cabeceraHace ?? 5),
    vehiculos: [{ id: "V1", etiqueta: "Z1-0001", rutaId: "R1", tripId: opciones.tripId ?? "T-X", lat: 0, lng: opciones.km * GRADOS_POR_KM, ts: AHORA - (opciones.hace ?? 10) }],
  }
  const retrasos: Retrasos = { cabecera: AHORA, porViaje: new Map(), porVehiculo: new Map(), total: 0 }
  for (const v of opciones.retrasos ?? []) {
    retrasos.porViaje.set(v.tripId, v)
    if (v.vehiculoId) retrasos.porVehiculo.set(v.vehiculoId, [...(retrasos.porVehiculo.get(v.vehiculoId) ?? []), v])
  }
  const l = <T>(datos: T) => ({ datos, leidoEn: AHORA * 1000, obsoleto: false })
  return { ahora: AHORA * 1000, indice: indiceLinea(), posiciones: l(posiciones), alertas: null, retrasos: l(retrasos) }
}
const viaje = (extra: Partial<ViajeRt>): ViajeRt => ({ tripId: "T1", rutaId: "R1", inicio: AHORA + 600, rel: "SCHEDULED", retraso: 0, vehiculoId: "", ts: AHORA, ...extra })

test("estimación: un bus a medio camino entre A y B llega a B en 150 s menos la edad del reporte", () => {
  // km 0,5 = mitad de A→B (300 s): faltan 150 s; el reporte tiene 10 s → 140 s.
  const [llegada] = llegadasEnParada(conBus({ km: 0.5 }), { paradas: new Set([ID("B")]) })
  assert.equal(llegada.segundos, 140)
  assert.equal(llegada.origen, "en-vivo")
  assert.equal(llegada.bus, "Z1-0001")
  // La parada siguiente: 150 + 300 − 10.
  assert.equal(llegadasEnParada(conBus({ km: 0.5 }), { paradas: new Set(["C"]) })[0].segundos, 440)
})

test("estimación: un bus que ya pasó la parada no llega a ella", () => {
  assert.deepEqual(llegadasEnParada(conBus({ km: 1.5 }), { paradas: new Set(["B"]) }), [])
})

test("estimación: la edad del reporte se descuenta", () => {
  assert.equal(llegadasEnParada(conBus({ km: 0.5, hace: 60 }), { paradas: new Set(["B"]) })[0].segundos, 90)
})

test("frescura: un bus con reporte de más de 300 s no cuenta", () => {
  // A la parada C aún le faltan 570 s: aun descontando la edad llegaría; solo la regla de los 300 s lo descarta.
  assert.deepEqual(llegadasEnParada(conBus({ km: 0.1, hace: 301 }), { paradas: new Set(["C"]) }), [])
  assert.equal(llegadasEnParada(conBus({ km: 0.1, hace: 300 }), { paradas: new Set(["C"]) }).length, 1)
  assert.equal(busesVigentes(conBus({ km: 0.5, hace: 301 })).length, 0)
  assert.equal(busesVigentes(conBus({ km: 0.5, hace: 300 })).length, 1)
})

test("frescura: un feed con la cabecera de más de 300 s está detenido y no da buses", () => {
  assert.equal(busesVigentes(conBus({ km: 0.5, cabeceraHace: 301 })).length, 0)
  assert.equal(busesVigentes(conBus({ km: 0.5, cabeceraHace: 300 })).length, 1)
})

test("un bus a más de 400 m de la línea de su ruta no se ubica", () => {
  const i = conBus({ km: 0.5 })
  i.posiciones!.datos.vehiculos[0].lat = 0.0045 // ≈ 500 m al norte
  assert.deepEqual(llegadasEnParada(i, { paradas: new Set(["B"]) }), [])
  assert.equal(busesDeRutas(i, ["R1"]).sinUbicar, 1)
})

test("cancelados: el bus de un viaje cancelado se descarta; las salidas programadas canceladas no cuentan", () => {
  const cancelado = viaje({ tripId: "T-CANC", rel: "CANCELED", vehiculoId: "V1" })
  assert.deepEqual(llegadasEnParada(conBus({ km: 0.5, tripId: "T-CANC", retrasos: [cancelado] }), { paradas: new Set(["B"]) }), [])
  const soloProgramada = llegadasEnParada(conBus({ km: 5, retrasos: [viaje({ tripId: "P1", rel: "CANCELED" })] }), { paradas: new Set(["B"]) })
  assert.deepEqual(soloProgramada, [])
})

test("retraso: una salida programada se corrige con su retraso y un viaje añadido cuenta", () => {
  const i = conBus({ km: 5, retrasos: [viaje({ tripId: "P1", inicio: AHORA + 600, retraso: 120 }), viaje({ tripId: "A1", rel: "ADDED", inicio: AHORA + 900, retraso: 0 })] })
  const [primera, segunda] = llegadasEnParada(i, { paradas: new Set(["B"]) })
  // salida + desfase de B (300 s) + retraso: 600 + 300 + 120.
  assert.equal(primera.segundos, 1020)
  assert.equal(primera.origen, "programado")
  assert.equal(primera.retraso, 120)
  assert.equal(segunda.adicional, true)
  assert.equal(segunda.segundos, 1200)
})

test("retraso: el retraso de un bus en vivo se muestra con el viaje más reciente del mismo bus y ruta", () => {
  const reciente = viaje({ tripId: "R-NEW", vehiculoId: "V1", retraso: 200, ts: AHORA - 30, inicio: AHORA - 3000 })
  const viejo = viaje({ tripId: "R-OLD", vehiculoId: "V1", retraso: 900, ts: AHORA - 2000, inicio: AHORA - 6000 })
  assert.equal(llegadasEnParada(conBus({ km: 0.5, retrasos: [viejo, reciente] }), { paradas: new Set(["B"]) })[0].retraso, 200)
  // Un dato de más de 900 s no se usa.
  assert.equal(llegadasEnParada(conBus({ km: 0.5, retrasos: [viejo] }), { paradas: new Set(["B"]) })[0].retraso, null)
})

test("sin copia de tripupdates se estima igual, sin retraso", () => {
  const i = conBus({ km: 0.5 })
  i.retrasos = null
  const [llegada] = llegadasEnParada(i, { paradas: new Set(["B"]) })
  assert.equal(llegada.segundos, 140)
  assert.equal(llegada.retraso, null)
})

test("próximas paradas de un bus, por etiqueta o por id, sin importar guiones ni mayúsculas", () => {
  const i = conBus({ km: 0.5 })
  const bus = buscarBus(i, "z1 0001")!
  assert.equal(bus.id, "V1")
  assert.equal(buscarBus(i, "V1")?.etiqueta, "Z1-0001")
  assert.deepEqual(proximasParadasDeBus(i, bus, 5)!.map((p) => [p.nombre, p.segundos]), [["Beta", 140], ["Gama", 440]])
  assert.equal(buscarBus(i, "no existe"), undefined)
})

test("muestras reales: ubicación entre paradas y llegadas de la B10", () => {
  const i = instantaneaDeMuestra()
  const { buses, sinUbicar } = busesDeRutas(i, ["10075"])
  assert.equal(buses.length, 2)
  assert.equal(sinUbicar, 0)
  assert.ok(buses.every((b) => b.codigo === "B10" && b.destino === "Portal Norte" && b.siguiente))
  const llegadas = llegadasEnParada(i, { paradas: new Set(["2300"]), rutas: ["10075"], max: 3 })
  assert.ok(llegadas.length >= 1)
  assert.ok(llegadas.every((l) => l.codigo === "B10" && l.paradaNombre.startsWith("Calle 100")))
  assert.deepEqual([...llegadas].sort((a, b) => a.segundos - b.segundos), llegadas)
})

test("muestras reales: estado del sistema por sistema y cancelados del día", () => {
  const i = instantaneaDeMuestra()
  const sistema = estadoSistema(i)
  assert.equal(sistema.total, 50)
  assert.equal(sistema.porSistema.troncal, 27)
  assert.equal(sistema.grupos.transmilenio + sistema.grupos.zonal + sistema.grupos.cable + sistema.grupos.otros, 50)
  const cancelados = canceladosHoy(i)!
  assert.equal(cancelados.total, 78)
  assert.equal(cancelados.porRuta[0].codigo, "18-3")
  assert.equal(canceladosHoy(i, ["10075"])!.total, 5)
  i.retrasos = null
  assert.equal(canceladosHoy(i), null)
})

test("muestras reales: buses cercanos a un punto", () => {
  const i = instantaneaDeMuestra()
  const [bus] = busesDeRutas(i, ["10075"]).buses
  const cerca = busesCercanos(i, { lat: bus.lat, lng: bus.lng }, { radioM: 100 })
  assert.ok(cerca.some((b) => b.id === bus.id && b.distancia < 1))
  assert.deepEqual(busesCercanos(i, { lat: 0, lng: 0 }, { radioM: 500 }), [])
})

test("alertas: solo las vigentes según active_period, por ruta o por parada", () => {
  const i = instantaneaDeMuestra()
  const [primera] = i.alertas!.datos.alertas
  const dentro = { ...i, ahora: (primera.periodos[0][0] + 1) * 1000 }
  const todas = alertasVigentes(dentro)
  assert.ok(todas.some((a) => a.id === primera.id))
  assert.equal(alertasVigentes(i).length, 0, "las alertas de la muestra ya vencieron a la hora de la cabecera")
  assert.ok(alertasVigentes(dentro, { rutas: [primera.rutas[0]] }).some((a) => a.id === primera.id))
  assert.equal(alertasVigentes(dentro, { rutas: ["no-existe"] }).length, 0)
  assert.ok(alertasVigentes(dentro, { paradas: new Set([primera.paradas[0]]) }).some((a) => a.id === primera.id))
})

test("búsqueda de paradas sin tildes ni mayúsculas", () => {
  const indice = instantaneaDeMuestra().indice
  const a = buscarParadas(indice, "CALLE 72")
  assert.ok(a.some((p) => p.nombre === "Calle 72 - Areandina"))
  assert.deepEqual(buscarParadas(indice, "calle   72").map((p) => p.id), a.map((p) => p.id))
  assert.deepEqual(buscarParadas(indice, ""), [])
  assert.deepEqual(buscarParadas(indice, "narnia"), [])
})

test("paradas cercanas: agrupa por estación y ordena por distancia", () => {
  const cerca = paradasCercanas(indiceReal, { lat: 4.6786, lng: -74.0576 }, { radioM: 500, max: 30 })
  assert.deepEqual(cerca.map((p) => p.distancia), cerca.map((p) => p.distancia).sort((a, b) => a - b))
  // La estación aparece una sola vez (no sus andenes) y con su nombre.
  assert.equal(cerca.filter((p) => p.nombre === "Virrey - Cendiatra").length, 1)
  assert.deepEqual(paradasCercanas(indiceReal, { lat: 0, lng: 0 }), [])
})

test("calendario: el festivo corre el servicio de domingo y la salida por hora cuenta", () => {
  const indice = instantaneaDeMuestra().indice
  assert.ok(serviciosDelDia(indice, "2026-11-17").includes("1"))
  assert.ok(!serviciosDelDia(indice, "2026-11-17").includes("4"))
  const festivo = serviciosDelDia(indice, "2026-11-16")
  assert.ok(festivo.includes("4") && !festivo.includes("1"))
  const [h] = horarioDeRutas(indice, ["10075"], Date.parse("2026-11-17T15:00:00-05:00"))
  assert.equal(h.primera, "04:30")
  assert.equal(h.ultima, "21:30")
  assert.equal(h.salidasHoy, h.porHora.reduce((a, b) => a + b, 0))
  assert.ok(h.salidasHoy > 100)
  const [dom] = horarioDeRutas(indice, ["10075"], Date.parse("2026-11-16T15:00:00-05:00"))
  assert.ok(dom.salidasHoy < h.salidasHoy)
})

test("dirección hablada: «hacia X» o «entre X y Y»", () => {
  assert.equal(textoDestino("Portal Norte"), "hacia Portal Norte")
  assert.equal(textoDestino("Germania || Est. Terminal Norte"), "entre Germania y Est. Terminal Norte")
})

// --- Mapeo de ids del catálogo a ids del GTFS -------------------------------------------------

const indiceReal = IndiceGtfsSchema.parse(indiceJson)
const catalogo = TransmilenioDataSchema.parse(snapshot)
const idsDe = (codigo: string) => {
  const ruta = catalogo.routes.find((r) => r.code === codigo)!
  return rutasGtfsDeRuta(ruta, catalogo, indiceReal).map((r) => r.id)
}

test("ids: el código del catálogo se vuelve el route_id del GTFS", () => {
  assert.deepEqual(idsDe("B10"), ["10075"])
  assert.deepEqual(idsDe("H54"), ["14045"])
  assert.deepEqual(idsDe("B12").sort(), ["14075", "14078"])
})

test("ids: «8 G» y «8 T» comparten el número en el GTFS y se separan por su destino", () => {
  assert.deepEqual(idsDe("8 G"), ["13307"]) // hacia Guatoque
  assert.deepEqual(idsDe("8 T"), ["13308"]) // hacia Terminal
  assert.deepEqual(idsDe("1 P"), ["14042"]) // hacia Portal El Dorado
  assert.deepEqual(idsDe("1 U"), ["14043"]) // hacia Universidades
})

test("ids: sin destino en común, la pareja restante se asigna entre sí (5 C / 5 P)", () => {
  assert.deepEqual(idsDe("5 C"), ["12841"]) // Calle 22 → Portal Américas
  assert.deepEqual(idsDe("5 P"), ["12639"]) // Portal Américas → Calle 22 (Av. Jiménez)
})

test("ids: un código que el GTFS ya no publica no se adivina", () => {
  assert.deepEqual(idsDe("B12GS"), [])
  assert.deepEqual(idsDe("L82"), [])
})

test("el índice caduca como la evidencia: más de 31 días desde su publicación no sirve", () => {
  const indice = instantaneaDeMuestra().indice
  assert.equal(indiceVigente(indice, new Date("2026-11-17T12:00:00-05:00")), true)
  assert.equal(indiceVigente(indice, new Date("2026-12-18T12:00:00-05:00")), true)
  assert.equal(indiceVigente(indice, new Date("2026-12-19T12:00:00-05:00")), false)
  assert.equal(indiceVigente({ ...indice, publicado: "2026-11-30" }, new Date("2026-11-17T12:00:00-05:00")), false, "no puede ser del futuro")
})

test("el índice commiteado cumple el esquema y trae la atribución CC BY-SA 4.0", () => {
  const indice = indiceReal
  assert.match(indice.licencia, /CC BY-SA 4\.0/)
  assert.match(indice.atribucion, /TransMilenio S\.A\./)
  assert.match(indice.sha256, /^[0-9a-f]{64}$/)
  assert.ok(indice.rutas.length > 1000)
  assert.deepEqual(new Set(indice.rutas.map((r) => r.agencia)), new Set(["1", "2", "3", "4", "5", "6", "7"]))
})

void CABECERA_MUESTRA

test("cancelados de hoy: 100.000 viajes se cuentan sin pasar de medio segundo (en vivo eran 84.000)", () => {
  const i = conBus({ km: 0.5 })
  const inicioDia = Date.parse("2027-01-10T00:00:00-05:00") / 1000
  const porViaje = new Map<string, ViajeRt>()
  for (let n = 0; n < 100_000; n++) {
    // Los pares son de hoy y los impares de ayer; uno de cada diez (siempre par), cancelado.
    porViaje.set(`V${n}`, viaje({ tripId: `V${n}`, inicio: inicioDia + (n % 2 === 0 ? 3600 : -3600) + (n % 3600), rel: n % 10 === 0 ? "CANCELED" : "SCHEDULED" }))
  }
  i.ahora = Date.parse("2027-01-10T12:00:00-05:00")
  i.retrasos = { datos: { cabecera: i.ahora / 1000, porViaje, porVehiculo: new Map(), total: porViaje.size }, leidoEn: i.ahora, obsoleto: false }
  const t0 = performance.now()
  const c = canceladosHoy(i)!
  assert.ok(performance.now() - t0 < 500, `tardó ${Math.round(performance.now() - t0)} ms`)
  assert.equal(c.viajesDelDia, 50_000)
  assert.equal(c.total, 10_000)
})

// ── Revisión R1 ──────────────────────────────────────────────────────────────

/** Triángulo circular de 1 km de lado: sale de A, pasa por B y C y vuelve a A (como un patrón circular real). */
function indiceCircular(): IndiceGtfs {
  const p = (nombre: string, kmEste: number, kmNorte: number): [string, string, number, number] => [nombre, "", kmNorte * GRADOS_POR_KM, kmEste * GRADOS_POR_KM]
  return IndiceGtfsSchema.parse({
    fuente: "x", publicado: "2026-11-17", generado: "2026-11-17", sha256: "x", licencia: "x", atribucion: "x",
    calendario: { servicios: {}, excepciones: [] },
    rutas: [{ id: "R1", codigo: "C1", destino: "Terminal", agencia: "1", paradas: [["A", 0], ["B", 40], ["C", 80], ["A", 129]], horario: {} }],
    paradas: { A: p("Terminal", 0, 0), B: p("Beta", 1, 0), C: p("Gama", 1, 1) },
  })
}

test("R1·4 patrón circular: el bus que viene de vuelta llega a su terminal por la última aparición, no se pierde en la primera", () => {
  const i = conBus({ km: 0 })
  i.indice = indiceCircular()
  // A mitad de la vuelta C → A (diagonal): faltan 129 − 104,5 = 24,5 s; el reporte tiene 10 s.
  i.posiciones!.datos.vehiculos[0].lat = 0.5 * GRADOS_POR_KM
  i.posiciones!.datos.vehiculos[0].lng = 0.5 * GRADOS_POR_KM
  const [llegada] = llegadasEnParada(i, { paradas: new Set(["A"]) })
  assert.ok(llegada, "antes tomaba solo la primera aparición de A (desfase 0) y descartaba al bus")
  assert.equal(llegada.segundos, 15)
  assert.equal(llegada.origen, "en-vivo")
})

test("R1·5 el retraso corrige la salida ANTES de decidir si ya salió: salida de hace 60 s con 600 s de retraso sigue por salir", () => {
  const i = conBus({ km: 5, retrasos: [viaje({ tripId: "TARDE", inicio: AHORA - 60, retraso: 600 }), viaje({ tripId: "YA", inicio: AHORA - 60, retraso: 0 })] })
  const llegadas = llegadasEnParada(i, { paradas: new Set(["B"]) })
  // Sale en AHORA + 540; llega a B (300 s) a los 840 s. La de retraso 0 ya salió y no cuenta.
  assert.deepEqual(llegadas.map((l) => [l.segundos, l.origen]), [[840, "programado"]])
})

test("R1·6 un tripupdates detenido (cabecera de más de 300 s) no corrige llegadas ni cancela buses ni cuenta cancelados", () => {
  const retrasos = [viaje({ tripId: "T-CANC", rel: "CANCELED", vehiculoId: "V1" }), viaje({ tripId: "P1", inicio: AHORA + 600 })]
  const fresco = conBus({ km: 0.5, tripId: "T-CANC", retrasos })
  assert.equal(busesVigentes(fresco).length, 0, "con el feed al día, el viaje cancelado se descarta")
  assert.notEqual(canceladosHoy(fresco), null)

  const detenido = conBus({ km: 0.5, tripId: "T-CANC", retrasos })
  detenido.retrasos!.datos.cabecera = AHORA - 301
  assert.equal(busesVigentes(detenido).length, 1, "un feed detenido no cancela buses")
  assert.deepEqual(llegadasEnParada(detenido, { paradas: new Set(["B"]) }).map((l) => l.origen), ["en-vivo"], "ni añade salidas programadas")
  assert.equal(canceladosHoy(detenido), null)
  assert.equal(retrasosUsables(detenido), undefined)
  detenido.retrasos!.datos.cabecera = AHORA - 300
  assert.ok(retrasosUsables(detenido), "a los 300 s todavía sirve")
})

test("R1·9 un viaje cancelado se excluye en UN solo lugar: llegadas, buses en vía, próximas paradas, cercanía y estado del sistema", () => {
  const i = conBus({ km: 0.5, tripId: "T-CANC", retrasos: [viaje({ tripId: "T-CANC", rel: "CANCELED", vehiculoId: "V1" })] })
  assert.deepEqual(busesVigentes(i), [])
  assert.equal(estadoSistema(i).total, 0)
  assert.deepEqual(busesDeRutas(i, ["R1"]), { buses: [], sinUbicar: 0 })
  assert.equal(buscarBus(i, "Z1-0001"), undefined, "no se puede pedir las paradas de un bus cancelado")
  assert.deepEqual(busesCercanos(i, { lat: 0, lng: 0.5 * GRADOS_POR_KM }, { radioM: 500 }), [])
  assert.deepEqual(llegadasEnParada(i, { paradas: new Set(["B"]) }), [])
  // Sin el viaje cancelado el mismo bus sí cuenta en todo.
  const ok = conBus({ km: 0.5 })
  assert.equal(estadoSistema(ok).total, 1)
  assert.equal(busesDeRutas(ok, ["R1"]).buses.length, 1)
  assert.ok(buscarBus(ok, "Z1-0001"))
})

// ── Revisión R2 ──

test("R2·3 el retraso de un bus (en vía y cercanos) solo sale de un tripupdates al día", () => {
  const reciente = viaje({ tripId: "R-NEW", vehiculoId: "V1", retraso: 138, ts: AHORA - 30, inicio: AHORA - 3000 })
  const al_dia = conBus({ km: 0.5, retrasos: [reciente] })
  assert.equal(busesDeRutas(al_dia, ["R1"]).buses[0].retraso, 138)
  assert.equal(busesCercanos(al_dia, { lat: 0, lng: 0.5 * GRADOS_POR_KM })[0].retraso, 138)
  const detenido = conBus({ km: 0.5, retrasos: [reciente] })
  detenido.retrasos!.datos.cabecera = AHORA - 400
  assert.equal(busesDeRutas(detenido, ["R1"]).buses[0].retraso, null, "antes devolvía 138 con la cabecera de hace 400 s")
  assert.equal(busesCercanos(detenido, { lat: 0, lng: 0.5 * GRADOS_POR_KM })[0].retraso, null)
  assert.equal(llegadasEnParada(detenido, { paradas: new Set(["B"]) })[0].retraso, null)
})
