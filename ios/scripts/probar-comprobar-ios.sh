#!/usr/bin/env bash
# Autocomprobación de comprobar-ios.sh: lo que no necesita Xcode. Corre en Linux y
# en macOS (bash 3.2). Comprueba que el script no borra nada, que nunca pisa
# evidencia previa y que, sin herramientas de Apple, falla en vez de aprobar.
#
# Uso:  ios/scripts/probar-comprobar-ios.sh
#
# Crea una carpeta temporal con `mktemp -d` y NO la borra (esta autocomprobación
# tampoco borra nada): el sistema limpia el directorio temporal.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$AQUI/comprobar-ios.sh"
RAIZ="$(cd "$AQUI/../.." && pwd)"
TEMPORAL="$(mktemp -d)"
fallos=0
total=0

comprobar() { # descripción, y luego el comando que debe salir con 0
  local descripcion="$1"; shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then echo "ok    $descripcion"; else echo "FALLA $descripcion" >&2; fallos=$((fallos + 1)); fi
}
debe_fallar() { # descripción, y luego el comando que debe salir distinto de 0
  local descripcion="$1"; shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then echo "FALLA $descripcion (salió con 0)" >&2; fallos=$((fallos + 1)); else echo "ok    $descripcion"; fi
}

sin_borrados() { ! grep -nE '(^|[;&|(` ])(rm|unlink|rmdir|shred)( |$)|find .*-delete' "$SCRIPT"; }
comprobar "el script no contiene ningún borrado (rm, unlink, rmdir, shred, find -delete)" sin_borrados

# Con `source` solo quedan definidas las funciones: no se ejecuta ningún paso.
cargar() { env SALIDA="$TEMPORAL/fija" bash -c 'source "$1" && declare -F sin_pisar >/dev/null' _ "$SCRIPT"; }
comprobar "cargar con source solo define funciones" cargar

sin_pisar_en() { env SALIDA="$TEMPORAL/fija" bash -c 'source "$1" && sin_pisar "$2"' _ "$SCRIPT" "$1"; }
debe_fallar "sin_pisar falla si la ruta ya existe" sin_pisar_en "$SCRIPT"
comprobar "sin_pisar acepta una ruta que no existe" sin_pisar_en "$TEMPORAL/no-existe"

salida_por_defecto() { env -u SALIDA bash -c 'source "$1" && echo "$SALIDA"' _ "$SCRIPT"; }
primera="$(salida_por_defecto)"; segunda="$(salida_por_defecto)"
total=$((total + 1))
if [ "$primera" != "$segunda" ] && [ "${primera#"$RAIZ/ios/salida/"}" != "$primera" ]; then
  echo "ok    la salida por defecto es una carpeta nueva por ejecución ($primera)"
else
  echo "FALLA la salida por defecto no es única: «$primera» / «$segunda»" >&2; fallos=$((fallos + 1))
fi

usar_salida_fija() { [ "$(env SALIDA="$TEMPORAL/fija" bash -c 'source "$1" && echo "$SALIDA"' _ "$SCRIPT")" = "$TEMPORAL/fija" ]; }
comprobar "una SALIDA explícita se respeta" usar_salida_fija

# OMITIR_PRUEBAS: en la CI omite solo las clases dedicadas al texto MUY grande; en local, nada; definida y vacía, nada
# también en la CI.
omitidas_con() { env -u OMITIR_PRUEBAS "$@" bash -c 'source "$1" && printf %s "$OMITIR_PRUEBAS"' _ "$SCRIPT"; }
texto_muy_grande="$(env -u OMITIR_PRUEBAS bash -c 'source "$1" && printf %s "$OMITIR_TEXTO_MUY_GRANDE"' _ "$SCRIPT")"
omite_texto_muy_grande_en_ci() { [ -n "$texto_muy_grande" ] && [ "$(omitidas_con CI=true SALIDA="$TEMPORAL/fija")" = "$texto_muy_grande" ]; }
comprobar "en la CI se omiten solo las clases dedicadas al texto muy grande" omite_texto_muy_grande_en_ci
no_omite_en_local() { [ -z "$(omitidas_con -u CI SALIDA="$TEMPORAL/fija")" ]; }
comprobar "en local no se omite ninguna prueba" no_omite_en_local
vacia_no_omite() { [ -z "$(env CI=true OMITIR_PRUEBAS= SALIDA="$TEMPORAL/fija" bash -c 'source "$1" && printf %s "$OMITIR_PRUEBAS"' _ "$SCRIPT")" ]; }
comprobar "OMITIR_PRUEBAS vacía no omite nada en la CI" vacia_no_omite
# La lista es estrecha: cada entrada es una CLASE (no una prueba suelta ni un objetivo entero), se llama «…TextoGrandeUITests»
# y existe de verdad en ios/TransMiVozUITests (un nombre mal escrito no omitiría nada y la prueba volvería a fallar en la CI).
lista_estrecha() {
  local entrada clase
  for entrada in $texto_muy_grande; do
    [ "$(printf %s "$entrada" | tr -cd / | wc -c | tr -d ' ')" = 1 ] || { echo "no es una clase: $entrada" >&2; return 1; }
    [ "${entrada%%/*}" = "TransMiVozUITests" ] || { echo "objetivo inesperado: $entrada" >&2; return 1; }
    clase="${entrada#*/}"
    case "$clase" in *TextoGrandeUITests) ;; *) echo "no es de texto grande: $entrada" >&2; return 1 ;; esac
    grep -Eq "^(final )?class $clase\b" "$RAIZ"/ios/TransMiVozUITests/*.swift || { echo "no existe: $clase" >&2; return 1; }
  done
}
comprobar "las clases omitidas existen y son solo de texto muy grande" lista_estrecha
# Y ninguna clase de texto muy grande queda fuera sin decirlo: una clase nueva con «TextoGrandeUITests» debe agregarse a la lista
# (o a esta excepción, con su razón).
sin_clase_olvidada() {
  local clase
  for clase in $(grep -hEo "^(final )?class [A-Za-z0-9_]*TextoGrandeUITests" "$RAIZ"/ios/TransMiVozUITests/*.swift | awk '{print $NF}'); do
    case " $texto_muy_grande " in *"/$clase "*) ;; *) echo "falta en OMITIR_TEXTO_MUY_GRANDE: $clase" >&2; return 1 ;; esac
  done
}
comprobar "toda clase «…TextoGrandeUITests» está en la lista de omitidas" sin_clase_olvidada

# El uso (sin argumentos) sale con 2 y no crea carpetas.
env SALIDA="$TEMPORAL/uso" "$SCRIPT" >/dev/null 2>&1; codigo=$?
total=$((total + 1))
if [ "$codigo" = 2 ] && [ ! -e "$TEMPORAL/uso" ]; then echo "ok    sin argumentos: uso, código 2 y sin crear carpeta"; else echo "FALLA sin argumentos (código $codigo)" >&2; fallos=$((fallos + 1)); fi

# Evidencia previa: el paso falla ANTES de ejecutar herramientas y no la toca.
mkdir -p "$TEMPORAL/previa"
echo "evidencia previa" > "$TEMPORAL/previa/herramientas.txt"
env SALIDA="$TEMPORAL/previa" "$SCRIPT" herramientas >"$TEMPORAL/previa.log" 2>&1; codigo=$?
total=$((total + 1))
if [ "$codigo" != 0 ] && grep -q "Ya existe" "$TEMPORAL/previa.log" && [ "$(cat "$TEMPORAL/previa/herramientas.txt")" = "evidencia previa" ]; then
  echo "ok    un resultado previo hace fallar el paso y queda intacto"
else
  echo "FALLA el paso no protegió la evidencia previa (código $codigo)" >&2; fallos=$((fallos + 1))
fi

# Sin herramientas de Apple (Linux) los pasos deben FALLAR, no aprobar.
if ! command -v xcodebuild >/dev/null 2>&1; then
  for paso in herramientas compilar-simulador pruebas-simulador compilar-dispositivo; do
    debe_fallar "sin Xcode el paso «$paso» falla" env SALIDA="$TEMPORAL/sin-xcode" "$SCRIPT" "$paso"
  done
fi

echo "$((total - fallos)) de $total comprobaciones correctas (temporal: $TEMPORAL)"
[ "$fallos" = 0 ]
