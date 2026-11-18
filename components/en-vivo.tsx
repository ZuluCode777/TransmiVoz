"use client"

import { useEffect, useRef, useState } from "react"
import { Radio, Volume2 } from "lucide-react"
import { useSpeech } from "@/hooks/use-speech"
import { useTiempoReal } from "@/hooks/use-tiempo-real"
import { RespuestaBusesRutaSchema, RespuestaLlegadasSchema, RespuestaParadasCercanasSchema, type Meta } from "@/lib/contrato-tiempo-real"
import { spokenDistance } from "@/lib/geo"
import { enTiempo, haceTiempo, plural, textoDestino, textoRetraso } from "@/lib/texto-tiempo-real"

/**
 * Datos EN VIVO de TransMilenio dentro de las pantallas (ruta, viaje, GPS).
 *
 * Reglas de accesibilidad de todo lo de este archivo:
 * - Todo valor es texto legible (nada va solo en color ni en el mapa).
 * - Lo vivo dice siempre «en vivo», «estimado» y «datos de hace N segundos»; lo
 *   programado de la pantalla sigue diciendo «no es tiempo real».
 * - Una región `aria-live="polite"` por bloque, que cambia a lo sumo una vez por
 *   minuto y solo cuando la frase cambia (no en cada renovación de 30 s). La lista
 *   visible no es región viva: no se lee sola.
 * - Un botón «Escuchar» dice el resumen con la voz de la app, bajo demanda.
 */

/** Cada cuánto, como mínimo, la región viva puede anunciar un cambio. */
const ANUNCIO_MINIMO_MS = 60_000

/** Anuncia `texto` en una región viva, sin repetir y sin más de uno por `ANUNCIO_MINIMO_MS`. */
export function useAnuncioEspaciado(texto: string): string {
  const [anuncio, setAnuncio] = useState("")
  const ultimo = useRef(0)
  useEffect(() => {
    if (!texto || texto === anuncio) return
    const espera = Math.max(0, ultimo.current + ANUNCIO_MINIMO_MS - Date.now())
    const id = setTimeout(() => {
      ultimo.current = Date.now()
      setAnuncio(texto)
    }, espera)
    return () => clearTimeout(id)
  }, [texto, anuncio])
  return anuncio
}

/** Estado de los datos, en texto: edad, fuente detenida y copia anterior. */
export function textoEstado(meta: Meta | null, desactualizado: boolean): string {
  if (!meta) return ""
  const partes: string[] = []
  if (meta.detenido) partes.push("Los datos en vivo no se están actualizando")
  else if (meta.edadDatosS !== null) partes.push(`Datos de ${haceTiempo(meta.edadDatosS)}`)
  if (meta.copiaObsoleta || desactualizado) partes.push("no pude actualizar; muestro la última copia")
  return partes.join("; ")
}

function Encabezado({ titulo, resumen }: { titulo: string; resumen: string }) {
  const { speak } = useSpeech()
  return (
    <div className="flex items-start justify-between gap-3">
      <h3 className="flex items-center gap-2 text-xl font-bold">
        <Radio className="size-6 shrink-0 text-brand-ink" aria-hidden="true" />
        {titulo}
        <span className="rounded-full border-3 border-border px-2 py-0.5 text-base font-semibold">En vivo · estimado</span>
      </h3>
      {resumen && (
        <button
          type="button"
          onClick={() => speak(resumen)}
          aria-label={`Escuchar: ${titulo}`}
          className="flex size-12 shrink-0 items-center justify-center rounded-2xl border-3 border-border bg-card transition active:scale-95"
        >
          <Volume2 className="size-6 text-brand-ink" aria-hidden="true" />
        </button>
      )}
    </div>
  )
}

const caja = "mt-6 flex flex-col gap-2"
const nota = "text-base text-muted-foreground"

/** Próximas llegadas de una ruta a una estación (la del catálogo y su nombre tal como están en la app). */
export function LlegadasEnVivo({ parada, ruta }: { parada: string; ruta: string }) {
  const r = useTiempoReal({ operacion: "llegadas", parada, ruta, max: 4 }, RespuestaLlegadasSchema)
  const llegadas = r.datos?.llegadas ?? []
  const resumen =
    r.datos === null
      ? ""
      : llegadas.length === 0
        ? `No veo buses de la ${ruta} que lleguen a ${parada} ahora.`
        : `La ${ruta} ${textoDestino(llegadas[0].destino)} llega a ${parada} ${enTiempo(llegadas[0].segundos)}, estimado${textoRetraso(llegadas[0].retraso)}.`
  const anuncio = useAnuncioEspaciado(resumen)
  return (
    <section aria-label={`Llegadas en vivo de la ${ruta} a ${parada}`} className={caja}>
      <Encabezado titulo={`Llegadas a ${parada}`} resumen={resumen} />
      <p role="status" aria-live="polite" className="sr-only">
        {anuncio}
      </p>
      {r.estado === "cargando" && <p className={nota}>Consultando los buses en vivo.</p>}
      {r.estado === "error" && <p className="rounded-2xl border-3 border-fail bg-card p-4 text-lg font-bold">No pude consultar los datos en vivo ahora. Confirma el horario con TransMilenio.</p>}
      {r.datos && r.datos.motivo === "ruta-no-pasa-por-parada" && <p className="rounded-2xl border-3 border-border bg-card p-4 text-lg">No encuentro {r.datos.parada} en el recorrido de la {ruta} que tengo; puede que no pare ahí.</p>}
      {r.datos && r.datos.motivo === "feed-detenido" && <p className="rounded-2xl border-3 border-border bg-card p-4 text-lg">Los datos en vivo de TransMilenio no se están actualizando, así que no estimo llegadas.</p>}
      {r.datos && !r.datos.motivo && (
        <ul className="flex flex-col gap-2">
          {llegadas.map((l, i) => (
            <li key={`${l.rutaId}-${i}`} className="rounded-2xl border-3 border-border bg-card p-4 text-lg">
              <span className="font-bold">
                {l.codigo} {textoDestino(l.destino)}
              </span>
              {": "}
              {l.origen === "en-vivo" ? "llega" : "según la programación, llegaría"} {enTiempo(l.segundos)}, estimado{textoRetraso(l.retraso)}
              {l.bus ? `. Bus ${l.bus}` : ""}
            </li>
          ))}
        </ul>
      )}
      {r.datos && r.datos.motivo === "sin-buses" && <p className="rounded-2xl border-3 border-border bg-card p-4 text-lg">No veo buses de la {ruta} que lleguen a {parada} ahora.</p>}
      <p className={nota}>{r.datos ? textoEstado(r.datos.meta, r.desactualizado) : ""}</p>
    </section>
  )
}

/** Buses en vía de una ruta y por dónde van. */
export function BusesEnVivo({ ruta }: { ruta: string }) {
  const r = useTiempoReal({ operacion: "buses-ruta", ruta }, RespuestaBusesRutaSchema)
  const buses = r.datos?.buses ?? []
  const sentido = r.datos && r.datos.destinos.length === 1 ? ` ${textoDestino(r.datos.destinos[0])}` : ""
  const resumen = r.datos === null ? "" : buses.length === 0 ? `No veo buses de la ${ruta} en vía ahora.` : `${plural(buses.length, "bus", "buses")} de la ${ruta} en vía${sentido}.`
  const anuncio = useAnuncioEspaciado(resumen)
  return (
    <section aria-label={`Buses en vivo de la ${ruta}`} className={caja}>
      <Encabezado titulo="Buses en vía" resumen={resumen} />
      <p role="status" aria-live="polite" className="sr-only">
        {anuncio}
      </p>
      {r.estado === "cargando" && <p className={nota}>Consultando los buses en vivo.</p>}
      {r.estado === "error" && <p className="rounded-2xl border-3 border-fail bg-card p-4 text-lg font-bold">No pude consultar los datos en vivo ahora.</p>}
      {r.datos && <p className="text-lg">{resumen}</p>}
      {buses.length > 0 && (
        <ul className="flex flex-col gap-2">
          {buses.slice(0, 5).map((b) => (
            <li key={b.id} className="rounded-2xl border-3 border-border bg-card p-4 text-lg">
              <span className="font-bold">Bus {b.etiqueta || b.id}</span>
              {": "}
              {b.anterior && b.siguiente ? (b.anterior === b.siguiente ? `está en ${b.anterior}` : `va entre ${b.anterior} y ${b.siguiente}`) : "no pude ubicarlo en su recorrido"}
              {`, ${haceTiempo(b.edad)}`}
            </li>
          ))}
        </ul>
      )}
      {buses.length > 5 && <p className={nota}>Y {buses.length - 5} más.</p>}
      <p className={nota}>{r.datos ? textoEstado(r.datos.meta, r.desactualizado) : ""}</p>
    </section>
  )
}

/** Paradas cerca de una coordenada, con sus próximas llegadas. */
export function ParadasCercanasEnVivo({ lat, lng }: { lat: number; lng: number }) {
  const r = useTiempoReal({ operacion: "paradas-cercanas", lat, lng, radio: 800, max: 3, conLlegadas: true }, RespuestaParadasCercanasSchema, { cadaMs: 30_000 })
  const paradas = r.datos?.paradas ?? []
  const frase = (p: (typeof paradas)[number]) => {
    const [l] = p.llegadas ?? []
    return `${p.nombre}, a ${spokenDistance(p.distancia)}${l ? `: la ${l.codigo} ${textoDestino(l.destino)} ${enTiempo(l.segundos)}, estimado` : ""}`
  }
  const resumen = r.datos === null ? "" : paradas.length === 0 ? "No encuentro paradas a menos de 800 metros." : `Cerca de ti: ${paradas.map(frase).join(". ")}.`
  const anuncio = useAnuncioEspaciado(resumen)
  return (
    <section aria-label="Paradas cercanas con llegadas en vivo" className={caja}>
      <Encabezado titulo="Buses que llegan cerca" resumen={resumen} />
      <p role="status" aria-live="polite" className="sr-only">
        {anuncio}
      </p>
      {r.estado === "cargando" && <p className={nota}>Consultando los buses en vivo.</p>}
      {r.estado === "error" && <p className="rounded-2xl border-3 border-fail bg-card p-4 text-lg font-bold">No pude consultar los datos en vivo ahora.</p>}
      {r.datos && paradas.length === 0 && <p className="rounded-2xl border-3 border-border bg-card p-4 text-lg">No encuentro paradas a menos de 800 metros de tu ubicación estimada.</p>}
      <ul className="flex flex-col gap-3">
        {paradas.map((p) => (
          <li key={p.id} className="rounded-2xl border-3 border-border bg-card p-4">
            <p className="text-lg font-bold">{p.nombre}</p>
            <p className={nota}>A {spokenDistance(p.distancia)}</p>
            {(p.llegadas ?? []).length === 0 ? (
              <p className="text-lg">Sin llegadas que pueda estimar ahora.</p>
            ) : (
              <ul className="mt-1 flex flex-col gap-1">
                {(p.llegadas ?? []).slice(0, 3).map((l, i) => (
                  <li key={`${l.rutaId}-${i}`} className="text-lg">
                    <span className="font-bold">
                      {l.codigo} {textoDestino(l.destino)}
                    </span>
                    {`: ${enTiempo(l.segundos)}, estimado${textoRetraso(l.retraso)}`}
                  </li>
                ))}
              </ul>
            )}
          </li>
        ))}
      </ul>
      <p className={nota}>{r.datos ? textoEstado(r.datos.meta, r.desactualizado) : ""}</p>
    </section>
  )
}
