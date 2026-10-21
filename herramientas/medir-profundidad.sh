#!/usr/bin/env bash
# Mide la profundidad de cada lección del curso, para que ACEPTADO o RECHAZADO
# sea reproducible y no una discusión. Quien revisa y quien escribe corren el
# MISMO comando y obtienen el MISMO número.
#
# Uso:  herramientas/medir-profundidad.sh [carpeta]     (por omisión: es)
#
# Sale con código 0 si cumple y con 1 si no cumple (2 si no pudo medir).
#
# Qué cuenta como «palabra de explicación»: una palabra que está FUERA de un
# bloque de código cercado con ``` y FUERA de un bloque de código sangrado
# (cuatro espacios o tabulador, tras una línea en blanco y fuera de una lista).
# Los comentarios HTML <!-- --> tampoco cuentan. Se define aquí a propósito: sin
# una definición única, dos personas cuentan distinto y el criterio deja de ser
# un criterio.
#
# 🔴 POR QUÉ PALABRAS Y NO LÍNEAS. La primera versión contaba LÍNEAS no vacías de
# explicación (piso 150, mediana 250). Se engaña: quien escribe una frase por
# línea infla el conteo sin explicar más. Medido el 02-oct-2026 en una prueba de
# la Lección 2: tenía muchas líneas y solo 2,996 palabras de explicación, contra
# unas 4,350 de la lección equivalente de Go. Una línea puede traer tres
# palabras o cien; la palabra no se infla con el formato.
#
# 🔴 POR QUÉ SIGUEN SIENDO VARAS ABSOLUTAS (y no «la mitad de la mediana del
# curso»): un criterio relativo se muerde la cola. Medido en Go el 29-sep-2026,
# sus tres lecciones flacas bajaban la mediana y entonces pasaban. Garantiza
# uniformidad, no profundidad. Las varas se calibraron con el curso de Go,
# medido con ESTE MISMO criterio de palabras: lecciones de 3,269 a 5,098
# palabras de explicación, mediana cercana a 4,330.
#
#   PISO      = 3,000 palabras de explicación por lección (ninguna por debajo)
#   MEDIANA   = 4,000 palabras de explicación para el curso completo
#
# Las dos se pueden cambiar por variable de entorno, pero **se cambian a la vista
# y se dice por qué**, no en silencio.
set -uo pipefail
cd "$(dirname "$0")/.."

DIR="${1:-es}"
PISO="${PISO:-3000}"
MEDIANA_MIN="${MEDIANA_MIN:-4000}"

[ -d "$DIR" ] || { echo "no existe la carpeta $DIR"; exit 2; }

python3 - "$DIR" "$PISO" "$MEDIANA_MIN" <<'PY'
import glob, os, re, statistics, sys

dir_, piso, med_min = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])

LISTA = re.compile(r'^\s*([-*+]|\d+[.)])\s')

def vallas_desbalanceadas(ruta):
    """Líneas que EMPIEZAN con ``` si su conteo es impar; [] si es par.
    Un conteo impar vuelve falso el número de palabras (secciones enteras se
    contarían como código), así que no se mide."""
    inicio = [i for i, l in enumerate(open(ruta, encoding="utf-8"), 1)
              if l.strip().startswith("```")]
    return inicio if len(inicio) % 2 else []

def contar(ruta):
    """Devuelve (palabras_explicacion, palabras_codigo)."""
    exp = cod = 0
    dentro = False
    comentario = False
    prev_blanca = True
    en_lista = False
    en_sangrado = False
    for linea in open(ruta, encoding="utf-8"):
        s = linea.strip()
        if s.startswith("```"):
            dentro = not dentro
            prev_blanca = False
            continue
        n = len(s.split())
        if dentro:
            cod += n
            continue
        if comentario:
            if "-->" in s:
                comentario = False
            continue
        if s.startswith("<!--"):
            if "-->" not in s:
                comentario = True
            continue
        if not s:
            prev_blanca = True
            en_sangrado = False
            continue
        sangrada = linea.startswith("    ") or linea.startswith("\t")
        if sangrada and (en_sangrado or (prev_blanca and not en_lista)):
            en_sangrado = True
            cod += n
            prev_blanca = False
            continue
        if not sangrada:
            en_lista = bool(LISTA.match(linea))
        en_sangrado = False
        prev_blanca = False
        exp += n
    return exp, cod

archivos = sorted(f for f in glob.glob(os.path.join(dir_, "*.md"))
                  if os.path.basename(f)[:1].isdigit())
if not archivos:
    print(f"no hay lecciones numeradas en {dir_}/")
    raise SystemExit(2)

rotos = {os.path.basename(f): vallas_desbalanceadas(f) for f in archivos}
rotos = {k: v for k, v in rotos.items() if v}
if rotos:
    print("  número IMPAR de vallas de código; el conteo sería falso, no se corre:")
    for nombre, lineas in rotos.items():
        print(f"     - {nombre}: {len(lineas)} vallas, en las líneas {lineas}")
    raise SystemExit(2)

filas = [(os.path.basename(f), *contar(f)) for f in archivos]
mediana = statistics.median([e for _, e, _ in filas])

print(f"  {'lección':<34}{'explicación':>13}{'código':>9}   veredicto")
fallan = []
for nombre, exp, cod in filas:
    ok = exp >= piso
    if not ok:
        fallan.append((nombre, exp))
    print(f"  {nombre:<34}{exp:>13}{cod:>9}   {'ok' if ok else 'POR DEBAJO DEL PISO'}")

print()
print(f"  piso exigido por lección : {piso} palabras de explicación")
print(f"  mediana del curso        : {mediana:.0f}  (mínimo exigido: {med_min})")

problemas = 0
if fallan:
    problemas += 1
    print()
    print(f"  {len(fallan)} lección(es) por debajo del piso:")
    for n, e in fallan:
        print(f"     - {n}: {e} palabras; le faltan {piso - e}")
if mediana < med_min:
    problemas += 1
    print()
    print(f"  la mediana del curso ({mediana:.0f}) está por debajo del mínimo ({med_min}).")
    print("  Ninguna lección falla sola, pero el conjunto no llega a la profundidad pedida.")

print()
if problemas:
    print("  NO cumple la paridad de profundidad.")
    raise SystemExit(1)
print("  Cumple la paridad de profundidad.")
PY
