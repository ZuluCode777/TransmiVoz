# Muestras de los feeds GTFS Realtime

Recortes REALES de los feeds de TransMilenio S.A. del 2026-11-17 ~20:39 (hora de
Bogotá), para pruebas sin red. Se tomaron de `https://gtfs.transmilenio.gov.co/`
(`positions.pb`, `alerts.pb`, `tripupdates.pb`) y se recortaron a las rutas B10, 8
(Guatoque y Terminal), H54, B23, TransMiCable y cuatro zonales/alimentadoras, con
`FeedMessage.encode` de `gtfs-realtime-bindings`. La cabecera es la original
(`timestamp` 1794965936). `indice.json` es el recorte de `data/gtfs-indice.json`
para esas rutas y sus paradas.

Datos de TransMilenio S.A., GTFS bajo CC BY-SA 4.0.
