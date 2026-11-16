# EA-25 · iPhone: Metro de Bogotá y Mapa y GPS (funcionalidad)

Issue [#51](https://github.com/ZuluCode777/proyecto-1-APP/issues/51), parte de #26. Reemplaza las dos pantallas provisionales de la base visual ([ios-base-web.md](ios-base-web.md)) por las funciones de la web: `components/metro-list.tsx` y `components/auditory-gps.tsx`. Es **solo funcionalidad**: el diseño de estas dos pantallas queda para la pasada visual final (usan los componentes compartidos tal cual, sin estilo propio).

Los contratos de servidor son los de PR #104 (`feat/contratos-paridad-iphone`, contrato verificado en `28465696`): ver [ea-25-paridad-ios.md](ea-25-paridad-ios.md) en esa rama. **Todo lo de este documento es software**: lo que no usa SwiftUI, MapKit ni CoreLocation se compiló y se probó en Linux; el resto no se compiló ni se ejecutó donde se escribió (sin Xcode) y lo compila por primera vez la CI de macOS. No hay prueba en un iPhone, con VoiceOver ni con CoreLocation real.

## Metro de Bogotá

`Vistas/MetroVista.swift`, `Metro/` (`MetroModelo`, `CapaMetro`, `MapaMetroVista`, `TextoMetro`) y `Dominio/RespuestaMetro.swift`.

- Pide `{"operacion":"metro-linea-1"}` por el mismo transporte del planificador (`ClientePlanificadorHTTP`: HTTPS, Basic, sin redirecciones, plazo de 12 s, cotas de cuerpo y de respuesta, clasificación de estados). Una sola petición vigente; se pide al abrir la pantalla y no hay sondeo ni reintentos automáticos (el catálogo solo cambia con un despliegue). Salir de la pantalla descarta la petición en curso: su respuesta tardía no se aplica.
- La pantalla **dice primero y siempre que la Línea 1 está en construcción y sin servicio comercial** (el subtítulo es literal de la web y se ve también mientras carga o si falla). Con el catálogo muestra: la nota de estado (`textoEstado`), el mapa del proyecto con su **rótulo, aviso y atribución completa junto al mapa** y el enlace a la licencia (solo `https`), las 16 estaciones (E01–E16, cada una se abre con su ficha), la Línea 2 y las fuentes y fechas (solo se abren enlaces `https`).
- El decodificador es estricto: exige 16 estaciones con `id` y `numero` coherentes, huellas de 4 a 100 puntos, trazado de 2 a 500, textos no vacíos de hasta 1.500 caracteres, fechas `AAAA-MM-DD`, coordenadas en rango y **`servicioComercial: false`** (un `true` es una respuesta incompatible). Una clave que el cliente no conoce se ignora.
- **No hay punto por estación** (EA-24): la huella es un polígono ilustrativo y no se dibuja ningún marcador, centroide ni acceso. El trazado va punteado y fino. El mapa es MapKit, una sola pieza para VoiceOver, sin interacción; el listado de estaciones es completo y no depende de él. «Ver su huella en el mapa» (en la ficha) resalta una huella y dice su etiqueta, porque tocar un polígono no está en MapKit de SwiftUI con certeza y la huella no es un punto tocable.
- **Estados:** cargando (con el texto «proyecto en construcción y sin servicio»), listo, error con «Reintentar», y un servidor anterior que responde **400** a la operación: texto propio («versión anterior del servidor: pide que lo actualicen») en vez de un fallo genérico. `E07` conserva «nombre pendiente»: no se inventa un nombre.
- `CapaMetro` es la geometría pura (rótulo, atribución corta, trazado, huellas) para otro mapa. **EA-24 prohíbe dibujar el Metro en los mapas de ruta, de viaje y del GPS** (sería presentar un proyecto sin servicio como transporte de hoy): quien la integre allí debe decidirlo de forma explícita y conservar rótulo, trazado punteado y atribución.
- Diferencias con la web: la web **dice el estado en voz** al entrar; el iPhone no (VoiceOver lee la nota, y una voz que se dispara sola al abrir estorbaría a quien lo usa). Las fichas son `DisclosureGroup`, no `<details>`. Los enlaces de licencia y fuentes los abre el sistema.

## Mapa y GPS

`Vistas/GpsAuditivoVista.swift`, `Gps/` (`GpsAuditivoModelo`, `Ubicacion` y `UbicacionCoreLocation`, `Locutor` y `LocutorControlVoz`, `MapaGpsVista`, `TextoGps`) y `Dominio/RespuestaEstacionesCercanas.swift`.

**El servidor decide todo lo de transporte.** `{"operacion":"estaciones-cercanas","lat","lng","precision","edadMs","rumbo":{"grados","calidad","edadMs"}}` devuelve hasta 4 estaciones con nombre, coordenada de la estación, distancia (entera y hablada) y orientación (`modo`, `cardinal`, `relativa`, `indicacion`), más `muyCerca` y el catálogo. La app no calcula distancia, rumbo, giro ni cercanía, no tiene ningún umbral de distancia ni de precisión para orientar, y no copia reglas de `lib/ubicacion.ts`.

### Qué manda la app

- La lectura **en el cuerpo del POST**, nunca en la URL. `precision` solo si el sistema la da y cabe en el contrato (una precisión negativa o desmedida no se manda: el servidor la toma como desconocida y solo da referencia cardinal). `edadMs` desde que se capturó la lectura (reloj monotónico, no la hora de pared).
- `rumbo` solo si el sistema da un **rumbo verdadero** (`trueHeading` no negativo; el magnético no se usa): `grados`, `calidad` (`headingAccuracy`, omitida si es negativa) y su edad. Sin él, o con una lectura de más de 600 s, no se manda: nunca hay un giro inventado.
- Una lectura de **más de 60 s** está vencida: no se manda ni se presenta como actual (las estaciones se borran, el mapa deja de mostrar «Tú estás aquí» y se dice con las palabras de la web). El servidor también devuelve `ubicacion-vencida` sin estaciones, y la pantalla lo trata igual. Una lectura vencida que el sistema entrega primero (la guardada) se descarta.
- Una coordenada con precisión negativa (CoreLocation: coordenada no válida) no se entrega al modelo.

### Ciclo de vida

- **La persona manda**: nada se pide ni se escucha al abrir la pantalla. «Activar mi ubicación» pide el permiso «al usar la app» y empieza a escuchar; «Detener la ubicación» suelta todo. Una explicación (qué se envía, a quién, que no se guarda ni se registra, que no se sigue en segundo plano) está antes del botón.
- **Al irse, se detiene y no se reanuda sola**: salir de la pantalla (`onDisappear`) y pasar a segundo plano (`scenePhase == .background`; `.inactive` no, porque se espera que el aviso de permiso del sistema deje la app inactiva un momento: **sin verificar**) cancelan la petición, sueltan CoreLocation, cortan la voz propia y borran posición, rumbo y estaciones. Volver a la pantalla no activa nada. No hay modo de fondo, ni `allowsBackgroundLocationUpdates`, ni permiso «siempre».
- **Estados**: pidiendo permiso, denegado (con «Abrir Ajustes»), restringido, no disponible (falta la descripción de uso en el proyecto: ver [lo que falta cablear](#lo-que-falta-cablear)), buscando, sin señal, activo (con la precisión en texto), vencida y error de red con «Reintentar». Con permiso revocado en caliente se suelta todo. Sin brújula (`headingAvailable`) o sin lectura de rumbo verdadero, la pantalla lo dice en texto.
- **Peticiones acotadas** (el servidor comparte 60 por minuto entre todos los teléfonos y las seis operaciones): ningún evento del sensor pide nada. Se pide con la primera lectura vigente de la sesión, con «Actualizar estaciones», «Repetir indicación» y «Oriéntame por voz», y **como mucho una cada 10 s** (6 por minuto por teléfono: tres teléfonos no pasan de 18). Una respuesta de menos de 10 s se vuelve a decir sin pedir otra, salvo que se hiciera sin brújula y ya haya brújula. Solo hay una en curso: pedir otra cosa mientras tanto cambia lo que la respuesta dirá, no crea otra petición. Un fallo no se reintenta solo. Los 10 s son una propuesta de software sin medir.

### Voz y orientación (igual que la web)

- Una sola voz: `ControlVoz`, el dueño del audio y de la sesión de audio de la app (el de los avisos del accesorio y la respuesta hablada de la consulta). **No hay otro sintetizador ni otra `AVAudioSession`.** Cada locución es de prioridad rutina: un aviso del accesorio la gana, y la propia solo se corta si sigue siendo la última (`locuciones`). Con VoiceOver activo, ruta de audio no privada o la voz apagada, `ControlVoz` calla y el texto se anuncia con VoiceOver; ante un aviso más importante o una interrupción no se anuncia nada más.
- Primera respuesta: «Ubicación lista. La estación más cercana es X, a 90 metros al suroeste.» «Oriéntame por voz» elige la estación (queda marcada «Orientando» en texto, no solo en color) y dice «Te oriento hacia X. {indicación del servidor} Es una orientación aproximada: la accesibilidad del acceso no está verificada.» «Repetir indicación» dice la indicación del servidor de la estación elegida o de la más cercana. La lista muestra, por estación, la distancia, la referencia cardinal y la frase que dice la web (que ya trae los límites: «tu ubicación es imprecisa», «sin brújula fiable», «dentro del margen de error»).
- **Aviso de cercanía** («Estás muy cerca de X, a unos N metros. Busca el acceso de la estación; el punto es una referencia aproximada, no un acceso verificado.»): **solo con `muyCerca: true` del servidor**, solo para la estación que la persona eligió, **una vez** por elección (elegir otra y volver a elegir la rearma) y no cambia con la brújula. El campo es opcional: su ausencia vale `false`. Sin ninguna regla ni umbral local. No promete llegada ni un acceso accesible; **no se inventa ningún cruce seguro** ni una ruta peatonal.
- **Diferencia con la web: el seguimiento continuo.** La web reevalúa la cercanía a cada lectura del navegador; el iPhone la evalúa cada vez que se pide una consulta (primera, actualizar, repetir, orientar), porque pedir en cada lectura rompería el tope compartido. Para avisar sin que la persona toque nada hace falta un sondeo acotado mientras haya una estación elegida; es una decisión de presupuesto de peticiones (propuesta: una cada 20 s, ≤ 3 por minuto por teléfono) que **no se implementó**.
- No hay «Abrir en Google Maps»: la web arma una URL con la posición de la persona, y aquí la posición nunca va en una URL. Se puede ofrecer «Abrir en Mapas» con solo la coordenada de la estación (catálogo) como destino; no se hizo.

### Privacidad

La posición, el rumbo y las estaciones viven solo en memoria mientras la ubicación está activa y se borran al detener, al vencer o al irse. Nada se guarda ni se registra; `PosicionMedida` y `LecturaParaEnviar` ocultan sus valores al imprimirse y sus pruebas lo comprueban. El servidor documenta que no registra, no guarda ni reenvía la coordenada (ver el contrato en PR #104); lo que esta app no controla son los registros de la plataforma y de la red delante del servidor, y que cuatro distancias a estaciones conocidas bastan a quien las vea para estimar dónde está la persona.

### Pruebas de interfaz

Con `-PRUEBAS_UI_SIMULADAS`: planificador y ubicación sintéticos (`Simulacion/ClientePlanificadorSimuladoParidad.swift`, `Simulacion/UbicacionSintetica.swift`; datos inventados «[SIMULADO]»; el mapa no se dibuja y se rotula). Argumentos del Metro: `-PRUEBAS_UI_METRO_ANTIGUO` (responde 400), `_SIN_RED`, `_LENTO`. Del GPS: `-PRUEBAS_UI_GPS_PERMISO_CONCEDIDO`, `_PERMISO_DENEGADO`, `_PERMISO_RESTRINGIDO`, `_SIN_SENAL`, `_IMPRECISA`, `_SIN_BRUJULA`, `_SIN_RUMBO`, `_VENCE` (la lectura llega con 59,5 s), `_CARDINAL`, `_MUY_CERCA`, `_FALLA`, `_VACIA`. Archivo propio: `TransMiVozUITests/TransMiVozParidadUITests.swift` (recorridos, 44 pt, auditoría completa de accesibilidad sin filtros y con `AccessibilityXXXL`). **Escritas y sin ejecutar**: el mapa de MapKit, VoiceOver y el aviso real de permiso no los cubren.

## Lo que falta cablear

Fuera de lo que tocan estas pantallas (raíz, Inicio, `EntornoApp` y `project.pbxproj` son de otra tarea):

1. **Descripción de uso de ubicación (necesaria).** En `ios/TransMiVoz.xcodeproj/project.pbxproj`, en los ajustes de compilación del objetivo `TransMiVoz`, **Debug y Release** (junto a `INFOPLIST_KEY_NSCameraUsageDescription`, líneas 358 y 388 hoy), añadir:
   `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "TransMiVoz usa tu ubicación solo mientras la pantalla «Mapa y GPS» está abierta y tú la activas, para decirte qué estaciones están cerca. La app no la guarda ni la registra; se envía al servidor de TransMiVoz solo para ordenar las estaciones.";`
   Ninguna clave de segundo plano (`UIBackgroundModes`) ni `NSLocationAlwaysAndWhenInUseUsageDescription`. **Sin la clave**, `UbicacionCoreLocation` lo detecta (`Bundle.main.object(forInfoDictionaryKey:)`) y la pantalla dice «Esta versión de la app no puede pedir la ubicación»: no se queda esperando un aviso que nunca sale.
2. **La voz.** `InicioVista.pantalla(_:)` abre `GpsAuditivoVista()`, que sin `ControlVoz` solo anuncia con VoiceOver. Para hablar por la voz de la app: guardar la `voz` de `EntornoApp.crear()` como propiedad (`let voz: ControlVoz?`) y abrir `GpsAuditivoVista(voz: entorno.voz)`.
3. **Opcional.** Si `onDisappear` no se dispara al cambiar de pestaña con la pantalla empujada (la base lo teme para la lupa), subir `GpsAuditivoModelo` a `EntornoApp` y llamar a `suspender()` en el `onChange(of: pestana)` de `InicioVista`. El productor de «GPS impreciso» de `CentroAvisos` también cabe ahí.

## Pruebas y evidencia

| Qué | Dónde corrió | Resultado |
| --- | --- | --- |
| 132 pruebas de XCTest de lo que no usa SwiftUI (decodificación de las dos respuestas, cliente HTTP simulado, modelos del Metro y del GPS, y las de rutas que ya existían) | Linux, `swift:6.2`, paquete de prueba con los mismos archivos (`swift test`) | 0 fallos. No es la CI de macOS |
| Fixtures de `FixturesParidad.swift` contra los esquemas reales de zod (`RespuestaMetroSchema`, `RespuestaEstacionesCercanasSchema`, `PeticionPlanificadorSchema`) | Node, rama del contrato en `28465696` | Todas válidas |
| El catálogo REAL del Metro volcado de esa rama (31 KB, 16 estaciones, 157 puntos) con el decodificador de Swift | Linux, prueba no incluida en el repositorio | Decodifica y valida |
| Pruebas de TypeScript de la rama del contrato que leen estos archivos Swift (`ea25-paridad`, `ea25-planificador`, `ea17`, `ea26`) | Node | 72 de 72 |
| Mutaciones de la lógica del GPS (sin intervalo, aviso sin «una vez», aviso sin estación elegida, reintento automático, enviar lectura vencida, precisión negativa) | Linux | Cada una hace fallar al menos una prueba |

**Sin verificar**: la compilación de SwiftUI, MapKit y CoreLocation; `UbicacionCoreLocation` y `LocutorControlVoz` (no corren en Linux); las pruebas de interfaz y sus auditorías; que `onDisappear` salte al cambiar de pestaña; el comportamiento de `trueHeading` y de la lectura guardada del sistema; la voz real y VoiceOver; y todo en un iPhone.
