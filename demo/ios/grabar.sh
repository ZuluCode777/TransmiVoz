#!/usr/bin/env bash
# Graba en el iOS Simulator los recorridos de `demo/ios/DemoVideosUITests.swift`.
#
# 1. Elige el Simulator (nombre y versión mayor de iOS, como ios/scripts/comprobar-ios.sh), lo arranca y, si se da
#    DEMO_CA, instala esa autoridad para que la app confíe en el HTTPS del backend de grabación.
# 2. Copia la clase de demostración a ios/TransMiVozUITests/ (solo en esta copia de trabajo) y compila para pruebas.
# 3. Por cada recorrido: empieza a grabar la pantalla, lo ejecuta con `test-without-building` y deja de grabar.
#
# Por cada recorrido deja en $DEMO_SALIDA (por defecto demo/salida/crudo-iphone):
#   <id>.mov             la grabación de la pantalla, sin sonido
#   <id>.eventos.jsonl   los subtítulos que anotó el recorrido, con la hora de reloj
#   <id>.json            hora de inicio de la grabación y estado de xcodebuild (lo lee demo/componer.py)
#   <id>.xcodebuild.log  la salida de xcodebuild
#   capturas/<id>-NN-<qué>.png  capturas de pantalla de los momentos clave, para usarlas como fotos
# Termina con código 1 si algún recorrido falló; los demás se graban igual.
#
# Variables: SIMULADOR_NOMBRE (iPhone 17), IOS_MAYOR_ESPERADO (26), DEMO_ORIGEN, DEMO_CLAVE, DEMO_CA, DEMO_SOLO y
# DEMO_TAMANO_TEXTO (por defecto accessibility-large: el 2.º de los 5 tamaños de accesibilidad de iOS). Un recorrido
# puede pedir otro tamaño en la lista del final; el pie de su video dice cuál.
#
# El Simulator se configura como lo tendría una persona con baja visión: letra grande de accesibilidad y contraste
# aumentado. Es configuración del teléfono, no de la app: la app es la misma de la rama.
set -euo pipefail

raiz="$(cd "$(dirname "$0")/../.." && pwd)"
salida="${DEMO_SALIDA:-$raiz/demo/salida/crudo-iphone}"
derivados="${DEMO_DERIVADOS:-${RUNNER_TEMP:-/tmp}/demo-derivados}"
nombre="${SIMULADOR_NOMBRE:-iPhone 17}"
mayor="${IOS_MAYOR_ESPERADO:-26}"
origen="${DEMO_ORIGEN:-https://localhost:8443}"
clave="${DEMO_CLAVE:-}"
mkdir -p "$salida"

udid="$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
nombre, mayor = sys.argv[1], sys.argv[2]
mejor = None
for runtime, equipos in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m or m.group(1) != mayor:
        continue
    for equipo in equipos:
        if equipo["name"] == nombre and equipo.get("isAvailable", True):
            clave = (int(m.group(2)), equipo["udid"])
            mejor = max(mejor, clave) if mejor else clave
if not mejor:
    sys.exit(f"No hay un Simulator «{nombre}» con iOS {mayor}.")
print(mejor[1])
' "$nombre" "$mayor")"
echo "Simulator: $nombre ($udid)"

xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" appearance light || true

# Letra grande y contraste aumentado en todo el Simulator; la app recibe además el mismo tamaño al arrancar.
contraste=""
if xcrun simctl ui "$udid" increase_contrast enabled && xcrun simctl ui "$udid" increase_contrast 2>&1 | grep -qw enabled; then
  contraste=" y contraste aumentado"
  echo "Contraste aumentado: activado"
else
  echo "No se pudo activar el contraste aumentado: el video no lo dirá."
fi

# Fija el tamaño de letra del Simulator y deja en `categoria` el de la app y en `configuracion` el pie del video. Casi
# todos los recorridos usan DEMO_TAMANO_TEXTO; uno puede pedir otro (ver la lista de `grabar` al final).
usar_tamano() {
  local tam="$1" descripcion
  case "$tam" in
    extra-extra-extra-large) categoria=UICTContentSizeCategoryXXXL; descripcion="Letra en el mayor tamaño estándar (sin los de accesibilidad)" ;;
    accessibility-medium) categoria=UICTContentSizeCategoryAccessibilityM; descripcion="Letra grande de accesibilidad (1.º de 5 tamaños)" ;;
    accessibility-large) categoria=UICTContentSizeCategoryAccessibilityL; descripcion="Letra grande de accesibilidad (2.º de 5 tamaños)" ;;
    accessibility-extra-large) categoria=UICTContentSizeCategoryAccessibilityXL; descripcion="Letra grande de accesibilidad (3.º de 5 tamaños)" ;;
    accessibility-extra-extra-large) categoria=UICTContentSizeCategoryAccessibilityXXL; descripcion="Letra grande de accesibilidad (4.º de 5 tamaños)" ;;
    accessibility-extra-extra-extra-large) categoria=UICTContentSizeCategoryAccessibilityXXXL; descripcion="Letra grande de accesibilidad (5.º de 5 tamaños)" ;;
    *) echo "Tamaño de letra desconocido: $tam"; exit 2 ;;
  esac
  xcrun simctl ui "$udid" content_size "$tam" || echo "simctl no cambió el tamaño del sistema; la app lo recibe igual al arrancar."
  configuracion="${descripcion}${contraste} en el iPhone"
}
tamano="${DEMO_TAMANO_TEXTO:-accessibility-large}"
usar_tamano "$tamano"
echo "Tamaño de letra del Simulator: $(xcrun simctl ui "$udid" content_size 2>&1)"
xcrun simctl status_bar "$udid" override --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
if [ -n "${DEMO_CA:-}" ]; then
  xcrun simctl keychain "$udid" add-root-cert "$DEMO_CA"
  echo "Autoridad de grabación instalada en el Simulator."
fi

copia="$raiz/ios/TransMiVozUITests/DemoVideosUITests.swift"
cp "$raiz/demo/ios/DemoVideosUITests.swift" "$copia"
# La copia solo hace falta para compilar; no se deja en la carpeta de pruebas del proyecto.
trap 'rm -f "$copia"' EXIT
destino="platform=iOS Simulator,id=$udid"
comunes=(-project "$raiz/ios/TransMiVoz.xcodeproj" -scheme TransMiVoz -configuration Debug -destination "$destino" -derivedDataPath "$derivados")

echo "Compilando para pruebas…"
if ! xcodebuild build-for-testing "${comunes[@]}" > "$salida/compilar.log" 2>&1; then
  grep -E "error:|\*\* BUILD" "$salida/compilar.log" | head -40 || true
  echo "La compilación falló: ver compilar.log"
  exit 1
fi
grep -E "\*\* TEST BUILD" "$salida/compilar.log" || true

# En una grabación, las consultas de la app al backend no llegaban durante los primeros minutos tras arrancar el
# Simulator (el registro del proxy no las vio) y luego sí. Antes de grabar se abre el backend en Safari del Simulator
# hasta que el proxy registra la visita: así se sabe que el Simulator ya llega por HTTPS.
registro_proxy="${DEMO_REGISTRO_PROXY:-${RUNNER_TEMP:-/tmp}/demo-https/proxy.log}"
if [ -f "$registro_proxy" ]; then
  echo "Comprobando que el Simulator llega al backend por HTTPS…"
  desde="$(date +%s)"
  listo=""
  for intento in $(seq 1 40); do
    xcrun simctl openurl "$udid" "$origen/?calentar=$intento" 2>/dev/null || true
    for _ in $(seq 1 15); do
      if grep -q "calentar=" "$registro_proxy"; then listo=si; break; fi
      sleep 1
    done
    [ -n "$listo" ] && break
  done
  if [ -n "$listo" ]; then
    echo "El Simulator llega al backend (tras $(( $(date +%s) - desde )) s)."
  else
    echo "El Simulator no llegó al backend en 10 minutos; se graba igual."
  fi
  xcrun simctl terminate "$udid" com.apple.mobilesafari 2>/dev/null || true
  sleep 2
fi

capturas="$salida/capturas"
mkdir -p "$capturas"

# Si el Simulator no dejó escribir las capturas en la carpeta, salen de los adjuntos del resultado de xcodebuild.
extraer_capturas() {
  local id="$1" adjuntos="$salida/adjuntos-$1"
  compgen -G "$capturas/$id-*.png" > /dev/null && return 0
  [ -d "$salida/$id.xcresult" ] || return 0
  rm -rf "$adjuntos"
  if xcrun xcresulttool export attachments --path "$salida/$id.xcresult" --output-path "$adjuntos" > /dev/null 2>&1; then
    python3 - "$adjuntos" "$capturas" "$id" <<'EOF' || true
import json, re, shutil, sys
from pathlib import Path
origen, destino, ident = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
manifiesto = origen / "manifest.json"
for prueba in (json.loads(manifiesto.read_text()) if manifiesto.exists() else []):
    for adjunto in prueba.get("attachments", []):
        nombre = adjunto.get("suggestedHumanReadableName", "")
        archivo = origen / adjunto.get("exportedFileName", "")
        if not nombre.startswith(ident) or not archivo.is_file():
            continue
        base = re.sub(r"(_\d+)?_[0-9A-Fa-f-]{36}$", "", nombre.rsplit(".", 1)[0])
        shutil.copy(archivo, destino / f"{base}{archivo.suffix or '.png'}")
EOF
  fi
  rm -rf "$adjuntos"
}

fallos=()
pendientes=()
grabar() {
  local id="$1" prueba="$2" tam="${3:-$tamano}"
  if [ -n "${DEMO_SOLO:-}" ] && [[ ",$DEMO_SOLO," != *",$id,"* ]]; then return 0; fi
  local video="$salida/$id.mov" eventos="$salida/$id.eventos.jsonl" registro="$salida/$id.grabacion.log"
  rm -f "$eventos" "$video" "$capturas/$id-"*.png
  rm -rf "$salida/$id.xcresult"
  usar_tamano "$tam"
  echo "▶ $id ($prueba)"
  local antes
  antes="$(python3 -c 'import time; print(time.time())')"
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$video" > "$registro" 2>&1 &
  local pid=$!
  # La hora de inicio alinea los subtítulos: es cuando simctl avisa que empezó a grabar.
  local inicio=""
  for _ in $(seq 1 100); do
    if grep -q "Recording started" "$registro" 2>/dev/null; then
      inicio="$(python3 -c 'import time; print(time.time())')"
      break
    fi
    sleep 0.1
  done
  if [ -z "$inicio" ]; then
    echo "  (simctl no avisó del inicio; se estima un segundo después de lanzarlo)"
    inicio="$(python3 -c "print($antes + 1.0)")"
  fi
  local estado=0
  TEST_RUNNER_DEMO_EVENTOS="$eventos" TEST_RUNNER_DEMO_ORIGEN="$origen" TEST_RUNNER_DEMO_CLAVE="$clave" \
  TEST_RUNNER_DEMO_CATEGORIA_TEXTO="$categoria" TEST_RUNNER_DEMO_ID="$id" TEST_RUNNER_DEMO_CAPTURAS="$capturas" \
    xcodebuild test-without-building "${comunes[@]}" -parallel-testing-enabled NO \
      -only-testing:"TransMiVozUITests/DemoVideosUITests/$prueba" \
      -resultBundlePath "$salida/$id.xcresult" > "$salida/$id.xcodebuild.log" 2>&1 || estado=$?
  sleep 1
  # La hora en que se detiene la grabación y la duración del video dan el inicio real de sus cuadros: simctl avisa
  # «Recording started» unos segundos antes del primer cuadro, y sin esto los subtítulos van detrás de la imagen.
  local fin_grabacion
  fin_grabacion="$(python3 -c 'import time; print(time.time())')"
  kill -INT "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  # Si el Simulator no dejó escribir el archivo, los eventos están también en el registro de xcodebuild.
  if [ ! -s "$eventos" ]; then
    grep -o 'DEMO_EVENTO {.*}' "$salida/$id.xcodebuild.log" | sed 's/^DEMO_EVENTO //' | awk '!visto[$0]++' > "$eventos" || true
  fi
  extraer_capturas "$id"
  python3 - "$salida/$id.json" "$id" "$inicio" "$estado" "$configuracion" "$fin_grabacion" <<'EOF'
import json, sys
ruta, ident, inicio, estado, configuracion = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
fin_grabacion = float(sys.argv[6])
from datetime import datetime, timedelta, timezone
# Hora de Bogotá (UTC-5, sin horario de verano): de ella dependen el horario y el calendario que da el servidor.
bogota = timezone(timedelta(hours=-5))
json.dump({
    "id": ident, "plataforma": "iphone", "video": f"{ident}.mov", "eventos": f"{ident}.eventos.jsonl",
    "grabacion_epoch": inicio, "fin_grabacion_epoch": fin_grabacion, "estado": estado, "configuracion": configuracion,
    "grabado": datetime.fromtimestamp(inicio, bogota).isoformat(timespec="seconds"),
}, open(ruta, "w"), ensure_ascii=False, indent=2)
EOF
  if [ "$estado" -ne 0 ]; then
    fallos+=("$id")
    pendientes+=("$id:$prueba:$tam")
    echo "  ✗ $id: xcodebuild terminó con $estado"
    grep -E "error:|failed|Fallo|XCTAssert" "$salida/$id.xcodebuild.log" | head -20 || true
  else
    echo "  ✓ $id ($(wc -l < "$eventos" | tr -d ' ') eventos, $(compgen -G "$capturas/$id-*.png" | wc -l | tr -d ' ') capturas)"
  fi
}

grabar iphone-01-consulta-recorrido testDemo01ConsultaRecorrido
grabar iphone-02-consulta-horario testDemo02ConsultaHorario
grabar iphone-03-consulta-viaje testDemo03ConsultaViaje
grabar iphone-04-metro-estaciones testDemo04MetroEstaciones
grabar iphone-05-metro-estacion testDemo05MetroEstacion
grabar iphone-06-sesion-accesorio testDemo06SesionConAccesorio
grabar iphone-07-lupa testDemo07Lupa
grabar iphone-08-ajustes testDemo08Ajustes
grabar iphone-09-rutas-detalle testDemo09RutasYDetalle
grabar iphone-10-viaje testDemo10Viaje
# Dos turnos en la misma Consulta: con los tamaños de accesibilidad el campo no se reutiliza de forma fiable.
grabar iphone-11-aclaracion testDemo11Aclaracion extra-extra-extra-large
grabar iphone-12-avisos testDemo12Avisos

# Un segundo intento para cada recorrido que falló, al final, cuando ya pasaron unos minutos.
if [ "${#pendientes[@]}" -gt 0 ]; then
  echo "Segundo intento: ${fallos[*]}"
  repetir=("${pendientes[@]}")
  fallos=()
  pendientes=()
  for trio in "${repetir[@]}"; do
    IFS=: read -r id_repetir prueba_repetir tam_repetir <<< "$trio"
    grabar "$id_repetir" "$prueba_repetir" "$tam_repetir"
  done
fi

if [ "${#fallos[@]}" -gt 0 ]; then
  echo "Fallaron: ${fallos[*]}"
  exit 1
fi
echo "Todos los recorridos del iPhone se grabaron."
