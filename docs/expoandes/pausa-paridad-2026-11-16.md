# Punto de guardado de la paridad del iPhone — 16 de noviembre de 2026

El usuario pidió detener el trabajo, registrar el estado y guardar los cambios antes de cerrar el portátil. Después pidió reanudar. Este punto de guardado conserva el trabajo interrumpido; no declara terminada ni aprobada la integración.

## Reglas vigentes

- Respuestas al usuario en inglés; contenido del repositorio, commits y PR en español.
- Sonnet xhigh termina las funciones. Un único Fable hará el rediseño completo del iPhone después de terminar e integrar la funcionalidad, con los colores y las relaciones de contraste de la web de Render como referencia. No iniciar Fable antes.
- Luna revisa Standards y Spec en una sola tarea por ronda. Máximo tres rondas por PR; si la tercera tiene bloqueos, esperar la decisión del usuario. No iniciar una cuarta ronda.
- No fusionar en `main` ni desplegar Render como parte de este guardado. El usuario hace el despliegue.
- Instalación prevista en tres iPhones el martes 17. La compilación de respaldo instalada es `431dee0`, con vigencia aproximada hasta el 20 de noviembre.
- Conservar voz compartida, prioridad de alertas físicas, política de salida privada, auditorías de accesibilidad y reglas de transporte en el servidor.

## Cambios conservados

La rama `integracion/feria-13-11` estaba en `5c0ff096e821d731f79c699f0f8aebdd6e761666`, con 36 commits locales aún sin publicar. Ya contiene las ramas funcionales y el arreglo de ciclo de voz `0091e0d`. Se guardan también el permiso de ubicación al usar la app en Debug y Release (`project.pbxproj`) y `InfoPlistUbicacionTests.swift`, que estaban sin commit al interrumpir. La prueba nueva todavía requiere ejecución en Xcode.

| PR | Rama | Cabeza guardada | Revisión |
| --- | --- | --- | --- |
| [#104](https://github.com/ZuluCode777/proyecto-1-APP/pull/104) | `feat/contratos-paridad-iphone` | `28465696b6d587f3953a8f0276bdb181dd6e6e69` | Luna R2 CLEAN; dos rondas usadas |
| [#105](https://github.com/ZuluCode777/proyecto-1-APP/pull/105) | `feat/ios-base-web` | `d7129a24507eecfc367d480f01258343867e3e26` | Fable detenido; contar intento antiguo como R1 |
| [#107](https://github.com/ZuluCode777/proyecto-1-APP/pull/107) | `feat/ios-avisos-ajustes-web` | `3cef60ef2e7dc205e31cef9ea3847a5f6641dde6` | Luna R1 NOT CLEAN; dos bloqueos |
| [#108](https://github.com/ZuluCode777/proyecto-1-APP/pull/108) | `feat/ios-rutas-web` | `f7b6c830a03de04be97b525961a763e3b4408134` | Luna R2 CLEAN; dos rondas usadas |
| [#109](https://github.com/ZuluCode777/proyecto-1-APP/pull/109) | `feat/ios-voz-web` | `e96afccf97fec1344dded3de906df6e6838fb762` | Luna R1 NOT CLEAN; arreglo en integración sin revisar |
| [#110](https://github.com/ZuluCode777/proyecto-1-APP/pull/110) | `feat/ios-sesion-lupa-web` | `ae4b76981a5902b00de6b76abfa0641806bcec2d` | Sin revisión todavía |

Las seis ramas funcionales estaban limpias y publicadas al comprobar el guardado. El checkout principal sigue en `feat/ea15-ios-ble-audio`; sus carpetas no rastreadas `.claude/worktrees/` y `docs/logos/` son ajenas a este punto de guardado y se conservan sin añadirlas.

## Bloqueos y conexiones pendientes

1. **#107, texto y repetición de Emergencia.** EA-02 §5 (`prototipos/ea-02/especificacion-accesibilidad.md`) exige que todo lo hablado aparezca en «La app dijo», con «Repetir». La introducción de Emergencia aún no cumple. Usar la misma `ControlVoz` compartida.
2. **#107, diagnóstico de voz.** El archivo correcto es `ios/TransMiVoz/Diagnostico/DiagnosticoServidor.swift`, `SondaVoz`: puede devolver éxito después de cortar por plazo o ser reemplazada por una alerta. Solo debe aprobar cuando su frase completa terminó. Reutilizar `locuciones`, `ultimaSeOyoEntera` y `ultimaLocucionCortada`; nunca cortar una alerta ajena. Añadir pruebas de fin completo, reemplazo, plazo y cancelación. El nombre `DiagnosticoSondas.swift` del informe del revisor era incorrecto para este hallazgo.
3. **#109, ciclo de pestañas.** `0091e0d` en integración intenta cancelar solo la respuesta propia al dejar Inicio y conservarla al abrir automáticamente un destino. Revisar el arreglo y su regresión en Luna R2, junto con la inyección real de `entorno.consulta`, la retirada del fallback provisional y los textos obsoletos de favoritos/GPS.
4. **#108, conexiones.** Verificar dictado y voz compartidos en las tres factorías de `EntornoApp`, destinos reales y ausencia de omisiones funcionales. El decodificador ya rechaza `alternativas: null` y `[]`; admite el campo ausente para servidores anteriores.
5. **#110, conexiones y alcance.** Conectar GPS a la voz compartida, validar suspensión al ocultarse/cambiar de pestaña/ir a segundo plano y conservar solo permiso de ubicación al usar la app. El cliente no implementa reglas de distancia o giro: consume `muyCerca` del servidor.
6. **Metro.** El informe de #110 señala que EA-24 prohíbe superponer el Metro en mapas de rutas, viajes y GPS. Comprobar la especificación antes de aplicar la petición antigua del integrador de dibujarlo allí. Conservar la vista Metro, lista completa, atribución y advertencia de obra/sin servicio.
7. **Paridad GPS por revisar.** #110 no tiene seguimiento periódico de llegada; comprueba proximidad al consultar. Tampoco habla el estado inicial del Metro fuera de VoiceOver ni abre Google Maps. Evaluar contra requisitos antes de dar la funcionalidad por terminada; no añadir sondeos o exposición de ubicación sin comprobar alcance y presupuesto compartido.

## Evidencia y límites

- #104: 646 pruebas, TypeScript, compilación y verificación 9/9 aprobadas según el implementador; Luna R2 limpia. Sin despliegue.
- #108: 73 pruebas Swift aprobadas tras reproducir y corregir `null` y arreglo vacío; Luna R2 limpia.
- #109: 74 pruebas Swift en su rama; todavía falta revisión del arreglo integrado.
- #107: 38 pruebas Swift en su rama; los dos hallazgos posteriores siguen abiertos.
- #110: 132 pruebas Swift Linux, incluidos 41 casos GPS; fixtures validados contra esquemas reales de #104 y 72 pruebas TypeScript relacionadas. SwiftUI, MapKit, CoreLocation e interfaz no quedan validados por esa evidencia.
- Al reanudar, GitHub mostraba fallo de iOS en #110, #109 y #108, y cancelación en #107. Investigar registros antes de afirmar compilación o pruebas verdes. Las verificaciones web y de herramientas estaban verdes.
- #105 tenía 25 fallos entre 129 pruebas de interfaz, incluidos contraste, AX5 y navegación. Registro recuperado: `/tmp/expoandes-pr105-ios-fallos.log`. Los fallos visuales corresponden al pase Fable; no deben impedir terminar primero la funcionalidad.
- No se validaron iPhone físico, VoiceOver, cámara, GPS ni rutas reales de audio en esta sesión. No marcar esas pruebas como aprobadas.

## Reanudación

Continuar con el integrador Sonnet existente en esta rama, resolver los bloqueos funcionales y los fallos reales de compilación, publicar un PR borrador hacia `feat/ios-base-web` y revisar con Luna sin exceder los contadores. Solo después preparar el pase único de Fable sobre la funcionalidad integrada. No fusionar todavía en `main` ni declarar listo el build para la feria.
