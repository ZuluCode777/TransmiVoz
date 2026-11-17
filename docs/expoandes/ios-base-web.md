# iPhone: base visual de la web (Inicio, paleta, letra y componentes)

Issue [#51](https://github.com/ZuluCode777/proyecto-1-APP/issues/51), parte de la renovación visual del iPhone: la app SwiftUI debe parecerse lo más posible a la web de Render, con sus colores. Esta entrega es **la base**; otras tareas llevan después cada pantalla y cada función que le falta al iPhone, apoyadas en lo de aquí.

Todo lo de este documento es **software sin compilar donde se escribió** (no había Xcode): el código SwiftUI y UIKit lo compila por primera vez la CI de macOS. Lo que sí se ejecutó en Linux: la lógica sin SwiftUI (`ModoApp`, `TextoInicio`, 12 pruebas en `swift:6.2` con `-swift-version 5`) y la conversión de colores. **Nada se vio en un simulador ni en un iPhone.**

## Paleta

`ios/TransMiVoz/Vistas/Tema.swift`, `enum Paleta`. Un `Color` por token de `app/globals.css`, con el mismo nombre en camelCase (`--brand-soft` es `Paleta.brandSoft`), dinámico: claro es `:root`; oscuro es `.fluor` (el «Alto contraste» de la web: negro con neón). **La web elige `.fluor` con un interruptor; el iPhone sigue la apariencia del sistema hasta que la persona elige** con el interruptor «Alto contraste (colores fluorescentes)» de Ajustes ▸ Preferencias (`AltoContrasteModelo`, guardado con la clave y los valores de la web: `transmivoz-fluor` = `on` | `off`). Desde entonces manda su elección (`RaizVista` fija `preferredColorScheme`); sin elección no se guarda nada. Los tokens que `.fluor` no cambia valen lo mismo en oscuro, como en la web.

Los valores `oklch` se pasaron a sRGB con la reducción de croma de CSS Color 4 (JND 0,02). Con esos hex se midieron los contrastes que declara el CSS: 17,9:1 negro sobre lima, de 7,96 a 19,6:1 sobre los neones, 7,5:1 sobre el rojo de Emergencia, 7,2:1 el blanco sobre el rojo oscuro. `PaletaTests` los vuelve a medir en la CI. En un iPhone, Safari pinta en Display P3 los `oklch` que salen de sRGB (más saturados); aquí quedan recortados a sRGB, algo menos saturados (diferencia visual no medida).

| Token web | Swift | Claro | Oscuro (`.fluor`) |
| --- | --- | --- | --- |
| `--background` | `Paleta.background` | `#FFFFFF` | `#000000` (`oklch(0 0 0)`) |
| `--foreground` | `Paleta.foreground` | `#000000` | `#FBF400` (`oklch(0.94 0.22 108)`) |
| `--card` | `Paleta.card` | `#CCFF00` | `#010101` (`oklch(0.06 0 0)`) |
| `--card-foreground` | `Paleta.cardForeground` | `#000000` | `#FBF400` (`oklch(0.94 0.22 108)`) |
| `--popover` | `Paleta.popover` | `#FFFFFF` (`oklch(1 0 0)`) | `#FFFFFF` = claro |
| `--popover-foreground` | `Paleta.popoverForeground` | `#0A0A0A` (`oklch(0.145 0 0)`) | `#0A0A0A` = claro |
| `--muted` | `Paleta.muted` | `#F2F2F2` | `#030303` (`oklch(0.1 0 0)`) |
| `--muted-foreground` | `Paleta.mutedForeground` | `#000000` | `#CAE412` (`oklch(0.87 0.2 118)`) |
| `--bar` | `Paleta.bar` | `#CCFF00` | `#010101` (`oklch(0.06 0 0)`) |
| `--brand` | `Paleta.brand` | `#FF6EFF` | `#36F555` (`oklch(0.85 0.25 145)`) |
| `--brand-foreground` | `Paleta.brandForeground` | `#000000` | `#000000` (`oklch(0 0 0)`) |
| `--brand-soft` | `Paleta.brandSoft` | `#FFFFFF` | `#001400` (`oklch(0.16 0.09 145)`) |
| `--brand-ink` | `Paleta.brandInk` | `#000000` | `#36F555` (`oklch(0.85 0.25 145)`) |
| `--fill-switch` | `Paleta.fillSwitch` | `#00FFFF` | `#010101` (`oklch(0.06 0 0)`) |
| `--fill-agent` | `Paleta.fillAgent` | `#FF6EFF` | `#010101` (`oklch(0.06 0 0)`) |
| `--fill-routes` | `Paleta.fillRoutes` | `#FFFF00` | `#010101` (`oklch(0.06 0 0)`) |
| `--fill-map` | `Paleta.fillMap` | `#D07BFF` | `#010101` (`oklch(0.06 0 0)`) |
| `--fill-lens` | `Paleta.fillLens` | `#39FF14` | `#010101` (`oklch(0.06 0 0)`) |
| `--sos` | `Paleta.sos` | `#FF6B5A` | `#B3000D` (`oklch(0.48 0.2 27)`) |
| `--sos-foreground` | `Paleta.sosForeground` | `#000000` | `#FFFFFF` (`oklch(1 0 0)`) |
| `--sos-border` | `Paleta.sosBorder` | `#000000` | `#B3000D` (`oklch(0.48 0.2 27)`) |
| `--ok` | `Paleta.ok` | `#005E26` (`oklch(0.42 0.12 150)`) | `#36F555` (`oklch(0.85 0.25 145)`) |
| `--fail` | `Paleta.fail` | `#A9000D` (`oklch(0.46 0.19 27)`) | `#FF7B74` (`oklch(0.75 0.2 25)`) |
| `--destructive` | `Paleta.destructive` | `#E7000B` (`oklch(0.577 0.245 27.325)`) | `#E7000B` = claro |
| `--border` | `Paleta.border` | `#000000` | `#FBF400` (`oklch(0.94 0.22 108)`) |
| `--input` | `Paleta.input` | `#000000` | `#FBF400` (`oklch(0.94 0.22 108)`) |
| `--ring` | `Paleta.ring` | `#000000` | `#A7FB0F` (`oklch(0.9 0.24 130)`) |
| `--primary` | `Paleta.primary` | `#171717` (`oklch(0.205 0 0)`) | `#171717` = claro |
| `--primary-foreground` | `Paleta.primaryForeground` | `#FAFAFA` (`oklch(0.985 0 0)`) | `#FAFAFA` = claro |
| `--secondary` | `Paleta.secondary` | `#F5F5F5` (`oklch(0.97 0 0)`) | `#F5F5F5` = claro |
| `--secondary-foreground` | `Paleta.secondaryForeground` | `#171717` (`oklch(0.205 0 0)`) | `#171717` = claro |
| `--accent` | `Paleta.accent` | `#F2F2F2` | `#F2F2F2` = claro |
| `--accent-foreground` | `Paleta.accentForeground` | `#000000` | `#000000` = claro |
| `--chart-1` | `Paleta.chart1` | `#D4D4D4` (`oklch(0.87 0 0)`) | `#D4D4D4` = claro |
| `--chart-2` | `Paleta.chart2` | `#737373` (`oklch(0.556 0 0)`) | `#737373` = claro |
| `--chart-3` | `Paleta.chart3` | `#525252` (`oklch(0.439 0 0)`) | `#525252` = claro |
| `--chart-4` | `Paleta.chart4` | `#404040` (`oklch(0.371 0 0)`) | `#404040` = claro |
| `--chart-5` | `Paleta.chart5` | `#262626` (`oklch(0.269 0 0)`) | `#262626` = claro |
| `--sidebar` | `Paleta.sidebar` | `#FAFAFA` (`oklch(0.985 0 0)`) | `#FAFAFA` = claro |
| `--sidebar-foreground` | `Paleta.sidebarForeground` | `#0A0A0A` (`oklch(0.145 0 0)`) | `#0A0A0A` = claro |
| `--sidebar-primary` | `Paleta.sidebarPrimary` | `#171717` (`oklch(0.205 0 0)`) | `#171717` = claro |
| `--sidebar-primary-foreground` | `Paleta.sidebarPrimaryForeground` | `#FAFAFA` (`oklch(0.985 0 0)`) | `#FAFAFA` = claro |
| `--sidebar-accent` | `Paleta.sidebarAccent` | `#F5F5F5` (`oklch(0.97 0 0)`) | `#F5F5F5` = claro |
| `--sidebar-accent-foreground` | `Paleta.sidebarAccentForeground` | `#171717` (`oklch(0.205 0 0)`) | `#171717` = claro |
| `--sidebar-border` | `Paleta.sidebarBorder` | `#E5E5E5` (`oklch(0.922 0 0)`) | `#E5E5E5` = claro |
| `--sidebar-ring` | `Paleta.sidebarRing` | `#A1A1A1` (`oklch(0.708 0 0)`) | `#A1A1A1` = claro |

Medidas (`enum Tema`): `radio` 10 (`--radius`), `radioXL` 14, `radio2XL` 18 (tarjetas, botones, baldosas), `radio3XL` 22, `borde` 3 (`border-3`), `bordeEmergencia` 5 (`border-5`), `objetivoMinimo` 44.

`AccentColor` del catálogo de recursos sigue ahí y `EstilosAccesiblesTests` lo sigue midiendo, pero ninguna pantalla depende ya de él: el [pase visual](#pase-visual-de-tamaño-estándar-16112026) pasó todos los botones, campos, enlaces y textos secundarios a la paleta.

## Letra

`Vistas/Tipografia.swift`. Plus Jakarta Sans, como la web, en cuatro pesos estáticos (regular, semibold, bold, extrabold: los que usa la web) en `TransMiVoz/Fuentes/`, con su licencia SIL OFL 1.1 (`OFL.txt`, copiada del repositorio original `tokotype/PlusJakartaSans`). Se registran en `Info-TransMiVoz.plist` (`UIAppFonts`) y, como respaldo, con `Tipografia.registrar()` al arrancar (`TransMiVozApp.init`): así no depende de cómo Xcode copie las fuentes al paquete. Si ninguna funciona, `Font.custom` cae en la letra del sistema y la app sigue legible.

Uso: `.font(.jakarta(.bold, .lg))` es `font-bold text-lg`. Tamaños `sm 14, base 16, lg 18, xl 20, xl2 24, xl3 30` (los de Tailwind), cada uno ligado a un estilo de Dynamic Type (`relativeTo`), así que escalan hasta el texto más grande. Las barras del sistema (navegación y pestañas) **no** usan esta letra a propósito: sus textos escalan por su cuenta y una letra propia los estropea.

## Componentes (`Vistas/ComponentesWeb.swift`)

| Web | Swift | Notas |
| --- | --- | --- |
| `AppHeader` | `EncabezadoApp` (`View`) y `FichaBusBarra` | Fila fija sobre el área desplazable de la raíz de una pestaña (`VStack(spacing: 0) { EncabezadoApp(alAbrirMenu:, alAbrirAvisos:); … }`): menú de modo a la izquierda, «TransMiVoz» al centro, campana a la derecha, cada botón de 48×48 pt reales. **No va en la barra de navegación**: en iOS 26 la barra limita cada control a 36 pt y no escala el texto (medido en la CI). La barra del sistema queda encima con la ficha del bus (`FichaBusBarra`, decorativa). Hoy solo la usa Inicio. |
| `ScreenHeader` | `EncabezadoPantalla(titulo:, subtitulo:, simbolo:, alVolver:)` | La banda con ficha, título y subtítulo, al principio del contenido. `alVolver` solo para donde no hay barra de navegación (hojas); en una pantalla empujada el botón «atrás» del sistema hace de «Volver». |
| Tarjeta (`rounded-2xl border-3 bg-card p-4`) | `.tarjetaWeb(relleno:, tinta:)` | Modificador de vista. |
| Botón principal / secundario | `.buttonStyle(EstiloBotonPrimario())` / `EstiloBotonSecundario()` | `font-bold text-lg`, 3 pt, a todo el ancho, mínimo 56 pt (`compacto: true`: 48 pt, para pantallas con muchos controles seguidos, como la sesión del accesorio). No disponible: borde discontinuo y colores de `EstilosAccesibles` (contraste ≥ 4,5:1, no solo tono). `.accion(prominente:disponible:compacta:)` elige el estilo y bloquea con el mismo valor. |
| Acción destructiva | `EstiloBotonPeligro` | «Quitar», «Olvidar clave»: `bg-sos text-sos-foreground` (7,5:1 en claro, 7,2:1 en oscuro). |
| Pantalla (`bg-background text-foreground`) | `.pantallaWeb()` | Fondo, tinta y `tint` de la paleta. Va en el área desplazable de cada pantalla, antes de `navigationTitle`. |
| Campo de texto | `.campoWeb()` | El campo del sistema (su área táctil y su foco) con el contorno de 3 pt de la paleta y al menos 44 pt. |
| Espera | `ProgresoWeb(texto:)` | `ProgressView` con el rótulo en la tinta de la pantalla (el del sistema lo atenúa). |
| Enlace de texto | `.enlaceWeb()` | Tinta de la pantalla y subrayado: no depende del color. |
| Píldora «Volver» | `EstiloBotonPildora` | Usada por `EncabezadoPantalla`. |
| Baldosa de `PartialHome` | `BaldosaWeb(titulo:, pista:, simbolo:, relleno:, tinta:, colorBorde:, anchoBorde:, identificador:, accion:)` | Botón de 72 pt como mínimo; VoiceOver lee el título y, tras una pausa, la pista. Con el texto más grande pierde el ícono y la flecha (decorativos) para que quepa entera. |
| `ModeMenu` | `MenuModoVista` | Hoja que abre `RaizVista`. |

Íconos (lucide a SF Symbols): Menu `line.3.horizontal`, Bell `bell`, Bus `bus`, Bot `bubble.left.and.text.bubble.right` (el de la pestaña Consulta), Map `map`, TrainFront `tram`, ScanText `text.viewfinder`, PhoneCall `phone.fill`, ShieldAlert `exclamationmark.shield`, ChevronRight `chevron.right`, ArrowLeft `arrow.left`, Eye `eye`, EyeOff `eye.slash`, Check `checkmark`.

## Estructura de la app

Cinco pestañas, en este orden (`RaizVista`, `PestanaRaiz`): **Inicio** (la de partida), Sesión, Consulta, Avisos, Ajustes. La lupa ya no tiene pestaña.

- **Inicio** (`InicioVista`, `NavigationStack` propia): `EncabezadoApp` en una fila fija bajo la barra de navegación, la banda «¿Qué necesitas?» y las seis baldosas de `OpcionInicio`, en el orden de la web: Asistente, Rutas, Mapa y GPS, Metro de Bogotá, Lupa y Emergencia al final (contorno de 5 pt, rojo, letra negra en claro y blanca en oscuro).
- Qué abre cada baldosa: **Asistente** cambia a la pestaña Consulta; **Rutas** empuja `RutasVista`; **Lupa** empuja `LupaVista` (sin su propia `NavigationStack`: la lupa conserva el ciclo de vida de la cámara, se suelta al salir o al cambiar de pestaña); **Mapa y GPS**, **Metro de Bogotá** y **Emergencia** empujan `GpsAuditivoVista`, `MetroVista` y `EmergenciaVista`.
- **La campana** de la cabecera abre la pestaña Avisos. **El menú** (botón de la izquierda) abre `MenuModoVista`.
- **Modo** (`ModoApp`, `ModoAppModelo`, `EntornoApp.modo`): Baja visión (`parcial`) o Ceguera total (`total`), guardado en `UserDefaults` con la clave y los valores de la web (`transmivoz-mode` = `parcial` | `total`). Elegir un modo cierra el menú, vuelve a Inicio y lo anuncia («Modo baja visión activado.»). Hoy solo cambia el Inicio: Baja visión muestra las baldosas y Ceguera total muestra `AgenteTotalVista`. **Ese es el gancho del Inicio de voz.** En las pruebas de interfaz el modo parte siempre de Baja visión y no persiste.
- **Barras**: `AparienciaApp.aplicar()` (UIKit, al arrancar) pinta las barras de navegación y de pestañas con `bar`, la letra y los íconos con `foreground` y el filo con `border`. El contorno de las barras es el filo de 1 px del sistema, no los 3 px de la web.
- **Cabecera en el resto de pantallas**: la web la muestra siempre. Hoy solo Inicio la lleva; las demás pestañas conservan su barra de navegación con título (solo pintada con la paleta). Añadirla a otra raíz de pestaña es poner `EncabezadoApp(…)` como fila fija sobre su contenido; en las pantallas empujadas manda el botón «atrás» del sistema.

## Para las tareas que siguen

- **Mapa y GPS, Metro, Emergencia, Ceguera total**: reemplazan **el archivo entero** (`GpsAuditivoVista`, `MetroVista`, `EmergenciaVista`, `AgenteTotalVista`). Cada uno trae una sola línea provisional en `textoProvisional` que **no debe llegar a `main`**. Conserven el título de navegación (las pruebas de Inicio abren cada pantalla por él: «Mapa y GPS», «Metro de Bogotá», «Emergencia»).
- **Cablear una pantalla nueva**: en `InicioVista.pantalla(_:)` (un caso más en `DestinoInicio`), o con `pestana = …` si es una pestaña.
- **Restilar una pantalla existente**: `.pantallaWeb()`, colores de `Paleta`, y armarla con `EncabezadoPantalla`, `.tarjetaWeb()`, `.campoWeb()` y los estilos de botón. Mantener los `accessibilityIdentifier`. Antes de añadir tarjetas, márgenes o letra más ancha a una pantalla con auditoría de una sola posición, leer «Alto de las pantallas» del pase visual.
- **No cambiar** los ayudantes, tolerancias ni grupos de auditoría de `TransMiVozUITests.swift`.

## Pruebas

- `PaletaTests` (CI): los contrastes de cada par letra/fondo en claro y oscuro (≥ 7:1, incluido el texto secundario sobre la pantalla y sobre las tarjetas), el contorno y el foco (≥ 3:1), que el texto secundario es el token opaco de la paleta y algunos hex.
- `ModoAppModeloTests`, `AltoContrasteModeloTests`, `TextoInicioTests`: lógica sin SwiftUI (también corren en Linux; 20 de 20 el 16/11/2026, con el ajuste de siempre para las clases `@MainActor`).
- `TransMiVozInicioUITests`: pestañas (cinco, Inicio primera y seleccionada, sin Lupa), cabecera, seis baldosas (orden, título, 44 pt, tocables), cada baldosa abre lo suyo, el menú de modo (cambia el Inicio, marca el activo, se cierra), la campana, y la auditoría de accesibilidad de Inicio y del menú. `TransMiVozInicioTextoGrandeUITests`: Inicio con `AccessibilityXXXL`, cada baldosa entera a la vista y auditada.
- Pruebas existentes cambiadas por la navegación (sin tocar ayudantes, tolerancias ni grupos de auditoría): las del accesorio abren primero la pestaña Sesión (antes era la primera) con el nuevo `abrirSesion`; las de la lupa la abren desde la baldosa de Inicio y «volver a la lupa» es volver a la pestaña Inicio.

## Pase visual de tamaño estándar (16/11/2026)

Un solo pase sobre la integración funcional (`integracion/feria-13-11`, `4a6871f`). Parte de la ejecución de iOS de esa cabeza (run `43990196510`: 807 pruebas unitarias en verde y 26 fallos en 183 pruebas de interfaz, 25 casos). Nada de esto se compiló ni se vio donde se escribió: ver «Sin verificar».

### Qué fallaba y qué se cambió

| Fallo en la CI | Causa | Cambio |
| --- | --- | --- |
| Contraste («failed» o «nearly passed») de `boton-buscar`, `boton-abrir-ajustes`, `elegir-…`, `boton-sesion-accesorio`, `boton-reconectar`, `boton-permiso-continuar` / `-ahora-no` (Bluetooth), `boton-actualizar-anuncios` (Avisos y Anuncios), `boton-permiso-camara-…`, `boton-abrir-ajustes-camara` (lupa), `boton-aplicar` (servidor), `boton-sesion` (sesión simulada), `metro-reintentar` | Los estilos del sistema (`.borderedProminent`, `.bordered`) pintan con el color de acento, que ya no era el azul oscuro medido | Todos pasan a los estilos de la casa: `accion(prominente:disponible:compacta:)` ya no usa estilos del sistema; `EstiloBotonPeligro` para lo destructivo. Lo mismo en las pantallas sin fallo propio (Favoritas, detalle de ruta, Metro, GPS, lupa). |
| `metro-licencia` «nearly passed» | Enlace con el color de acento | `.enlaceWeb()` y `tint` de la paleta en la raíz |
| Cabecera: `boton-menu-modo` medía 36 pt; «TransMiVoz» y «Cerrar menú» no escalaban (Dynamic Type) | La barra de navegación de iOS 26 limita cada control a 36 pt y no escala su texto | `EncabezadoApp` es una fila fija del contenido (48×48 pt reales); «Cerrar menú» es una píldora del contenido de la hoja |
| `agente-total-campo` medía 22 pt | El marco de 44 pt rodeaba el campo, no lo agrandaba | El campo mismo tiene letra `text-xl` y dos renglones como mínimo |
| `agente-total-motor` no existía | El identificador de la tarjeta de pasos pisaba el de sus hijos | La tarjeta es un contenedor de accesibilidad |
| «Actualizar» del GPS no decía «Espera unos segundos» | La prueba tardaba más de los 10 s del límite de ritmo en llegar al botón (había que desplazar) | Con la ubicación en uso, «Detener», «Repetir indicación» y «Actualizar» van juntos arriba, a la vista sin desplazar; la explicación de privacidad va primero antes de activar y al final después. Depende del tiempo de la CI: solo una ejecución lo confirma. |

Además: fondo y tinta de la paleta en todas las pantallas (`.pantallaWeb()`), texto secundario opaco (`muted-foreground`), campos con el contorno de la paleta, esperas con su rótulo en la tinta de la pantalla, tarjetas de anuncios en `muted`, filas de rutas como tarjetas, interruptores en `ok`, y el interruptor «Alto contraste».

### Alto de las pantallas

La auditoría nativa de contraste también mide los nodos que quedan **bajo** el área desplazable (entre su borde, 775 pt en el Simulator iPhone 17, y el final de la pantalla): los mide sobre la barra de pestañas y fallan. Por eso una auditoría de una sola posición solo pasa si la pantalla **cabe entera**; las largas usan las fases con contraste diferido (`FaseAuditada`, `AuditoriaFase`, `RecorridoAuditado`). El pase visual respeta ese margen: no añade tarjetas ni cambia la letra del cuerpo, los campos conservan su alto y la sesión del accesorio usa los botones compactos (48 pt) para que «Reconectar» siga entero a la vista en la posición de arriba.

### Pruebas que cambiaron de método (sin aflojar ninguna aserción)

Van en un commit aparte, para poder revisarlas o revertirlas solas. No se tocó ningún umbral, plazo, reintento, filtro ni omisión.

- **Ocho auditorías de pantallas más largas que la vista** dejan de auditar una sola posición y recorren la pantalla entera con `auditarPantallaLarga` (`RecorridoAuditado`, que ya usaba el asistente de voz con el texto más grande): `agente-total-reposo` y `-respuesta`, `-escuchando`, `-sin-permiso`, `metro-listo`, `gps-activo`, `gps-denegado`, `gps-error` y `rutas-resultados`. En la ejecución de `4a6871f` sus hallazgos de contraste eran nodos bajo el área desplazable (por ejemplo «agente-total-enlace-gps» en y 747…803 y «procedencia-catalogo» en y 843…859, con la vista en 116…775): el sistema los mide sobre la barra de pestañas, así que una pantalla que no cabe entera no puede pasar en una sola posición con ningún color. Es la regla de las fases de Inicio, el accesorio, Emergencia y Diagnóstico: el contraste de un nodo recortado se difiere y ese mismo nodo debe medirse entero y sin problema en otra posición, o la prueba falla; un problema de un nodo entero a la vista, o de otro tipo, falla en el acto. Ahora se audita toda la pantalla, no solo su comienzo.
- `RecorridoAuditado` toma como borde superior de la vista el mayor entre la barra de navegación y el área desplazable (como `FaseAuditada`): bajo la barra de Inicio está la fila fija de la cabecera.
- `testLosControlesMidenAlMenos44Puntos` (GPS) visita los mismos siete controles en el orden de la pantalla: su `exponer` solo desplaza hacia delante y «gps-mapas-0» está por encima de «gps-orientar-3».
- **Riesgo conocido:** en `gps-activo` y `gps-error` la línea de antigüedad cambia de texto cada segundo; si el recorrido la mide recortada, su deuda (identificador y etiqueta) no se salda con otra etiqueta y la prueba fallará. No se relajó esa identidad: lo dirá la ejecución nativa.

### Lo que NO hizo

- **Los diseños con el texto muy grande (`AccessibilityXXXL`) siguen pendientes por decisión del dueño.** No se repararon, Dynamic Type sigue activo y las doce clases `…TextoGrandeUITests` siguen fuera de la CI (ver [ios-ci.md](ios-ci.md)).
- La letra del cuerpo sigue siendo la del sistema; Plus Jakarta Sans queda en cabeceras, baldosas y botones.
- Los mapas (`MapaRecorridoVista`, `MapaGpsVista`, `MapaMetroVista`) conservan sus colores de MapKit; no se dibuja el Metro en los mapas de ruta, viaje ni GPS.
- Ninguna función, texto hablado, permiso ni regla de voz cambió.

## Sin verificar

**Del pase visual:** nada de SwiftUI se compiló ni se ejecutó donde se escribió (Linux, sin Xcode): solo el análisis sintáctico de todo el Swift y las pruebas de `ModoApp`. Quedan por demostrar en la CI de macOS la compilación, que cada control restilado pase la auditoría nativa, la medida real de los botones de la cabecera, que la ficha del bus quepa en la barra, el interruptor «Alto contraste» (`preferredColorScheme` sobre las barras de UIKit) y las ocho auditorías recorridas. La paleta oscura no la recorre ninguna prueba de interfaz. Ni VoiceOver ni un iPhone.

**De la base:** todo SwiftUI y UIKit de esta entrega hasta que corra la CI de macOS y, después, un iPhone: la compilación, la letra registrada (`UIAppFonts` con `INFOPLIST_FILE` mezclado con las claves generadas, y su respaldo), el aspecto de las barras con Liquid Glass de iOS 26, el título central de la barra con el texto más grande, el ciclo de vida de la cámara de la lupa al cambiar de pestaña con la lupa empujada, y las auditorías de accesibilidad nuevas. VoiceOver real no se probó.
