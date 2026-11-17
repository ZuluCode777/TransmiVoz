# Presencia del radar por USB — 17 de noviembre de 2026

## Cambio y límites

Sobre la base `ea87ce8`, se añadió un diagnóstico al firmware real. Imprime `valor=1` o `valor=0` solo al observar un contador nuevo de tramas válidas, con salud 0 y edad máxima de 500 ms. Las fallas se rotulan `valor=desconocido`, nunca 0. El terminal conserva registros históricos, no una garantía de presencia actual.

El diagnóstico no consume la UART ni la conexión BLE. La salida USB se descarta si no cabe y usa espera de transmisión cero para no bloquear la adquisición cuando no hay lector. No cambia emparejamiento, contrato, caducidad, configuración del radar ni audio del iPhone.

## Evidencia obtenida

- Sonnet implementó el cambio. Luna R1 detectó la posible espera de USB; tras corregirla, R2 quedó limpia. Dos rondas de tres utilizadas.
- `make -C firmware probar`: 1 054 y 626 comprobaciones, sin fallos.
- `bash firmware/pruebas/probar_enlace.sh`: 21 228, 585 y 1 019 837 comprobaciones, y guardia del sketch sin fallos.
- Una sonda temporal compiló la función real con el intérprete y un doble de puerto serie: presencia repetida, ausencia, falta de espacio USB, observación vencida, arranque y tramas inválidas; sin fallos. No sustituye al ensayo de la placa.
- Compilación ESP32-S3, núcleo instalado `esp32:esp32@3.3.12`, `FlashSize=16M,CDCOnBoot=cdc`: 603 073 bytes de programa y 28 600 de RAM global.
- Tipos TypeScript, 646 pruebas web y compilación web aprobados. La primera verificación sin servidor local falló; contra el candidato local aislado pasó 9 de 9, con cámara, micrófono y ubicación simulados.
- Se respaldó por ROM el intervalo `0x0…0x14ffff`, incluidos NVS y la aplicación activa. La lectura mediante stub fallaba en el sector `0x2f000`; la lectura ROM completó el respaldo. No se atribuye esa diferencia a una avería del radar.
- Se escribió solo la aplicación en `0x10000`, fuera de NVS (`0x9000`, tamaño `0x5000`), y se verificó por lectura ROM. La clave se provisionó fuera del repositorio y no se cambió la política de vínculos.
- Captura física USB: `valor=1` en `t=235304` y `t=236304`; `valor=0` desde `t=236505`, con edad 0 y salud 0 en la telemetría. Esto acredita que se observaron ambos estados, no una medida controlada de alcance o latencia.
- Se comprobó el comando Linux de [firmware/README.md](../../../firmware/README.md#terminal-de-presencia-usb). El reloj continuó al abrirlo; no se observó reinicio. Solo puede haber un lector serie.

## Pendiente

El iPhone informó antes detecciones y una falla al volver del bloqueo. El cambio USB no corrige la suspensión ni acredita recuperación, estabilidad prolongada, seguridad del enlace frente a suplantación o pruebas G1/G2/B2. Tampoco se verificó aquí el SHA de la aplicación instalada ni la política de voz de esa instalación. La ventana declarada por Información es 0–300 mm. No se cierran #41 ni #46.
