#!/usr/bin/env bash
# AUTOPRUEBA del medidor de profundidad: comprueba que la compuerta SABE FALLAR.
#
# Por qué existe: una compuerta que nunca se vio en rojo no está comprobada. En
# esta casa ya se midieron tres que decían verde sin mirar lo que exigían —un
# indicador de índices que reportaba en verde su propia alarma, un verificador de
# accesibilidad que no comprueba el criterio que cita, y un canario de CI roto por
# la misma causa que venía a vigilar—. Un medidor que solo se ejerce contra
# lecciones que cumplen no demuestra nada: demuestra que no se quejó.
#
# Qué hace: arma dos cursos de mentira en una carpeta temporal y exige que el
# medidor los juzgue bien.
#   1. CONTROL POSITIVO (el que importa): lecciones deliberadamente cortas ⇒ el
#      medidor TIENE que salir con código 1. Si sale 0, la compuerta está ciega.
#   2. CONTROL NEGATIVO: lecciones deliberadamente largas ⇒ código 0. Si sale 1,
#      la compuerta rechaza lo bueno y nadie va a confiar en ella.
#   3. SIN LECCIONES: carpeta sin archivos numerados ⇒ código 2, «no pudo medir».
#      Un repo sin contenido no debe salir en verde ni en rojo: debe decir que no
#      midió. Es la diferencia entre «cumple» y «no había nada que contar».
#
# Uso:  herramientas/autoprueba-medir-profundidad.sh
# Sale 0 si el medidor se comporta en los tres casos; 1 en cuanto uno falle.
#
# La carpeta temporal se borra siempre, también si la autoprueba se interrumpe.
set -uo pipefail
cd "$(dirname "$0")/.."

MEDIDOR="herramientas/medir-profundidad.sh"
[ -x "$MEDIDOR" ] || { echo "✗ no encuentro $MEDIDOR o no es ejecutable"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/autoprueba-profundidad.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

# --- los tres cursos de mentira -----------------------------------------------
mkdir -p "$TMP/corto" "$TMP/largo" "$TMP/vacio"

# 40 palabras por lección: muy por debajo del piso de 3,000.
for n in 00 01 02; do
  printf '# Lección %s\n\n' "$n" > "$TMP/corto/$n-leccion.md"
  for _ in $(seq 1 8); do printf 'palabra palabra palabra palabra palabra\n' >> "$TMP/corto/$n-leccion.md"; done
done

# ~6,000 palabras por lección: por encima del piso y de la mediana.
for n in 00 01 02; do
  printf '# Lección %s\n\n' "$n" > "$TMP/largo/$n-leccion.md"
  for _ in $(seq 1 600); do printf 'palabra palabra palabra palabra palabra palabra palabra palabra palabra palabra\n' >> "$TMP/largo/$n-leccion.md"; done
done

# Sin lecciones numeradas: solo los archivos que un curso vacío sí tiene.
printf '# Curso\n' > "$TMP/vacio/README.md"
printf '# Bitácora\n' > "$TMP/vacio/bitacora.md"

# --- los tres veredictos -------------------------------------------------------
fallas=0
comprobar() { # nombre, carpeta, código esperado
  local nombre="$1" carpeta="$2" esperado="$3" obtenido=0
  "$MEDIDOR" "$carpeta" >"$TMP/salida-$nombre.txt" 2>&1 || obtenido=$?
  if [ "$obtenido" -eq "$esperado" ]; then
    echo "  ✅ $nombre: código $obtenido, el esperado"
  else
    echo "  ✗ $nombre: esperaba código $esperado y dio $obtenido"
    sed 's/^/      /' "$TMP/salida-$nombre.txt" | tail -12
    fallas=$((fallas+1))
  fi
}

echo "Autoprueba del medidor de profundidad — ¿sabe fallar?"
echo
comprobar "control-positivo (lecciones cortas, debe RECHAZAR)" "$TMP/corto"  1
comprobar "control-negativo (lecciones largas, debe ACEPTAR)"  "$TMP/largo"  0
comprobar "sin lecciones (debe decir que NO MIDIÓ)"            "$TMP/vacio"  2
echo
if [ "$fallas" -ne 0 ]; then
  echo "NO se puede confiar en el medidor: $fallas de 3 comprobaciones fallaron."
  exit 1
fi
echo "El medidor acepta lo que cumple, rechaza lo que no y avisa cuando no hay nada que medir."
