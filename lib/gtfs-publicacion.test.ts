import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import { fechaDePublicacionDelZip, gtfsVencido } from "./gtfs-publicacion"

/** Listado real de `unzip -l GTFS.zip` del 2026-11-17 (recortado a lo que lee la función). */
const LISTADO = (fecha = "11-17-2026", hora = "09:18") => `Archive:  GTFS.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
     1760  ${fecha} ${hora}   calendar_dates.txt
    57595  ${fecha} ${hora}   routes.txt
   648374  ${fecha} ${hora}   stops.txt
  5908793  ${fecha} ${hora}   trips.txt
572305388  ${fecha} 09:19   stop_times.txt
---------                     -------
623836027                     5 files
`
const AHORA = new Date("2026-11-18T10:00:00-05:00")

test("R2·6 la fecha sale de las entradas del propio zip (hora UTC → día de Bogotá)", () => {
  assert.equal(fechaDePublicacionDelZip(LISTADO(), AHORA), "2026-11-17")
  // 02:30 UTC del 18 es 21:30 del 17 en Bogotá.
  assert.equal(fechaDePublicacionDelZip(LISTADO("11-18-2026", "02:30").replace("09:19", "02:31"), AHORA), "2026-11-17")
})

test("R2·6 un zip viejo da su fecha vieja: regenerar el índice no lo hace pasar por nuevo", () => {
  const viejo = LISTADO("09-01-2026", "09:18").replace("09:19", "09:19")
  assert.equal(fechaDePublicacionDelZip(viejo, AHORA), "2026-09-01")
  assert.equal(gtfsVencido("2026-09-01", AHORA), true, "más de 31 días: el índice nacería vencido y el script se niega a estamparlo")
  assert.equal(gtfsVencido("2026-11-17", AHORA), false)
  assert.equal(gtfsVencido("2026-10-18", AHORA), false)
  assert.equal(gtfsVencido("2026-10-17", AHORA), true)
})

test("R2·6 lo que no se puede comprobar se rechaza", () => {
  assert.throws(() => fechaDePublicacionDelZip("", AHORA), /no trae routes\.txt/)
  assert.throws(() => fechaDePublicacionDelZip("Archive: x.zip\nbasura", AHORA), /no se puede comprobar/)
  assert.throws(() => fechaDePublicacionDelZip(LISTADO().replace("routes.txt", "rutas.txt"), AHORA), /no trae routes\.txt/)
  // Entradas de días distintos: un zip armado a mano o mezclado.
  assert.throws(() => fechaDePublicacionDelZip(LISTADO().replace("09:19   stop_times", "09:19   stop_times").replace("11-17-2026 09:19   stop_times", "11-10-2026 09:19   stop_times"), AHORA), /fechas muy distintas/)
  // Fecha en el futuro.
  assert.throws(() => fechaDePublicacionDelZip(LISTADO("12-30-2026"), AHORA), /en el futuro/)
})

test("R2·6 el script no toma la fecha del manifiesto ni del archivo en disco", () => {
  const script = readFileSync("scripts/sync-gtfs-indice.ts", "utf8")
  assert.doesNotMatch(script, /manifest|mtime|statSync/)
  assert.match(script, /fechaDePublicacionDelZip\(execFileSync\("unzip", \["-l", zip\]/)
  assert.match(script, /if \(gtfsVencido\(publicado\)\) throw/)
})

test("R2·6 el listado real del GTFS.zip descargado se lee (si está a mano)", { skip: !process.env.LISTADO_GTFS }, () => {
  assert.equal(fechaDePublicacionDelZip(readFileSync(process.env.LISTADO_GTFS!, "utf8"), new Date("2026-11-18T10:00:00-05:00")), "2026-11-17")
})
