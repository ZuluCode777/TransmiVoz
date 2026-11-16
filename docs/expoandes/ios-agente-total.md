# iPhone: asistente de voz de «Ceguera total» (`AgenteTotalVista`)

Issue [#51](https://github.com/ZuluCode777/proyecto-1-APP/issues/51). Es la versión del iPhone de `components/total-agent.tsx`: el Inicio del modo «Ceguera total», con el micrófono como control principal. Esta entrega es **funcional**: el aspecto usa solo los componentes de la base (`ComponentesWeb`) y lo rediseña después otra tarea.

**Sin verificar donde se escribió** (no hay Xcode): la lógica sin SwiftUI (`AgenteTotalModelo`, `ConsultaModelo`) compila y pasa 74 pruebas en `swift:6.2` con `-swift-version 5` (29 nuevas de `AgenteTotalModeloTests`, más `ConsultaModeloTests` y `ConsultaVozTests`). Nada de SwiftUI ni de las pruebas de interfaz se ha compilado ni ejecutado; tampoco VoiceOver, el micrófono ni el audio reales.

## Qué hace

| Web (`total-agent.tsx`) | iPhone |
| --- | --- |
| Toda la zona es el botón de hablar | Botón grande `agente-total-microfono`. Tocar empieza el dictado; tocar otra vez **termina y envía** (el dictado no corta solo por silencio). Con VoiceOver, el «toque mágico» hace lo mismo desde cualquier punto. |
| Cancelar tocando de nuevo | Botón «Cancelar» (`agente-total-cancelar`) mientras escucha o piensa; tocar el micrófono mientras prepara el dictado o piensa también cancela. |
| «Te escucho.» | Solo vibra al empezar a escuchar (`DictadoModelo`): nada suena sobre un micrófono abierto. |
| Saludo al abrir | Se dice una vez por visita **sin VoiceOver**; con VoiceOver se lee la pantalla sola. |
| Subtítulo, «Pensando…» | `agente-total-estado`; «Pensando…» se anuncia por VoiceOver y no se dice en voz alta. |
| Responde hablando y mostrando | Toda respuesta (escrita o dictada) se dice por `ControlVoz`; si no suena, se anuncia por VoiceOver; si suena, no se repite por VoiceOver. |
| «Lo que hice» y «Motor» | `agente-total-pasos`, `agente-total-motor`. Un viaje no muestra pasos. |
| Aviso de privacidad | `agente-total-privacidad-0…2`, con lo que hace el iPhone: el dictado puede ir a Apple y **no se envía la ubicación**. |
| Escribir y enviar | `agente-total-campo` y `agente-total-enviar`; el campo se vacía al enviar si la pregunta salió. |
| Errores recuperables | Se dicen con su recuperación; «Reintentar» (`agente-total-reintentar`) donde `ErrorConsulta.admiteReintento`. |
| Navegar según la acción | `search` → rutas de la estación; `frequent` → Favoritas; `gps` → Mapa y GPS; `route` → detalle de la ruta. Se abren solas y la voz de esa respuesta sigue sonando. `trip` no abre nada: se presenta como información (sus tramos) y ofrece «Planear un viaje entre dos lugares». |
| Otras pantallas | «Otras pantallas»: Buscar rutas, Rutas frecuentes, Mapa y GPS. Son las que la web alcanza desde el asistente; Lupa, Metro y Emergencia no se ofrecen en este modo, como en la web. |

Aclaración de EA-19 intacta: «salgo desde Ricaurte» deja `agente-total-origen-pendiente` («Olvidar origen» disponible) y la pregunta siguiente lleva ese origen, porque es la misma `ConsultaModelo`.

Esta pantalla siempre pregunta por el transporte de hoy (`escenario = .transporte`): no tiene el selector del Metro.

## Cómo está armado

- `Estado/AgenteTotalModelo.swift`: el estado que ve la persona (`fase`, `titulo`, `subtitulo`, `respuesta`, `puedeReintentar`, `destino`, `aviso`), la política de voz y la navegación. Sin SwiftUI y probado.
- `Vistas/AgenteTotalContenido.swift`: la pantalla; es **el único archivo que hay que rediseñar**. Lleva las pantallas a las que navega en la pila de Inicio con `navigationDestination(item:)`.
- `Vistas/AgenteTotalVista.swift`: la entrada que usa `InicioVista`.
- `Estado/ConsultaModelo.swift` (cambio pequeño): `decir(_:)` (voz de la app con las guardas de la respuesta hablada), `callar()` y `lecturaAutomatica` (la pantalla de voz la apaga mientras está a la vista para no leer dos veces una respuesta dictada).
- `Vistas/ConsultaVista.swift` (cambios mínimos, sin rediseño): las respuestas pedidas desde el asistente no las anuncia la pestaña Consulta (`visible`), y los botones del sistema (`.bordered`, `.borderedProminent`), que fallaban la auditoría de contraste de la CI (`boton-escenario`, «Enviar», «Reintentar», los del dictado), pasan a `EstiloBotonPildora`, `EstiloBotonPrimario` y `EstiloBotonSecundario` de la base.

## Dependencias de integración (lo que no es de este PR)

1. **`InicioVista.swift`**: `case .total: AgenteTotalVista()` → `case .total: AgenteTotalVista(consulta: entorno.consulta)`. Mientras no se haga, la pantalla es el marcador provisional de la base y las pruebas de interfaz nuevas **se saltan** con ese motivo. Al hacerlo, borrar `AgenteTotalVista.textoProvisional`, su rama y el `nil` por defecto: esa línea no debe llegar a `main`.
2. **`TransMiVozUITests.swift:2298`** (`testElMenuDeModoCambiaElInicioYSeCierra`): espera `provisional-agente-total`. Tras el punto 1 debe esperar `agente-total-microfono`.
3. **Firmas que usa el asistente**: `GpsAuditivoVista()` (sin argumentos; la tarea de Mapa y GPS la reemplaza), `FavoritasVista(modelo:)`, `RutasVista(servicios:consultaInicial:)`, `DetalleRutaVista(servicios:codigo:)` y `ViajeVista(servicios:)`. Si una tarea las cambia, `AgenteTotalContenido.pantalla(_:)` es el único sitio que hay que ajustar.
4. **`AccionAgente.limite`** (`Dominio/PresentacionRespuesta.swift`): dice que la app no tiene «rutas frecuentes» ni GPS auditivo. El asistente no lo dice cuando abre la pantalla, pero la pestaña Consulta sí (y `testAccionSinPantallaInformaElLimiteYNoNavega` lo exige). Cuando Mapa y GPS exista de verdad, ese texto es falso: decisión del dueño, fuera de este PR.

## Decisiones y límites abiertos

- **Voz sin VoiceOver y sin auriculares**: `ControlVoz` (y `SintetizadorSistema`) solo hablan por una ruta privada. Por el altavoz, con VoiceOver apagado, la pantalla se ve y vibra, pero **no habla**. Una persona ciega usa VoiceOver y entonces todo se anuncia; con auriculares habla la app. Permitir el altavoz solo para esta pantalla exige cambiar `ControlVoz` / `SintetizadorSistema` (no son de esta tarea) y es una decisión de privacidad del dueño.
- **Sin corte por silencio**: el segundo toque es «terminé». La web corta sola; el reconocedor de iOS de esta app no (límite de EA-19).
- **No se vuelve a escuchar solo** tras una pregunta de aclaración: hay que tocar el micrófono otra vez (la web tampoco lo hace).
- **Respuestas con ubicación**: la web manda la ubicación en «dónde estoy»; el iPhone no manda ninguna. No se añadió transporte.
- El «toque mágico» de VoiceOver (`accessibilityAction(.magicTap)` en el contenedor) no está comprobado.
- Pruebas de interfaz: `TransMiVozAgenteTotalUITests.swift` (funcionales y auditoría a tamaño normal y con `AccessibilityXXXL`). Los ayudantes de `TransMiVozUITests.swift` son `private` a ese archivo, así que el archivo nuevo trae los suyos, con la misma auditoría completa y sin excepciones; el contraste de un nodo recortado por una barra se difiere y debe medirse entero y limpio en otra posición del recorrido.
