#!/usr/bin/env bash
# fig01_02.sh — Lección 1, sección 1.3.4: EL ERROR A PROPÓSITO. Una suma que
# no coincide, de las dos formas en que pasa de verdad.
#
#   Caso 1: el binario de OTRA versión (v1.37.0) contra la suma de v1.37.1.
#           Es lo que pasa cuando el binario y la suma se bajan en momentos o
#           con comandos distintos.
#   Caso 2: el binario correcto con UN byte de más, como uno corrupto o alterado.
#
# No instala nada. Trabaja en una carpeta nueva que le das.
#
# Uso:  ./fig01_02.sh CARPETA
set -uo pipefail   # sin -e: aquí el fallo de sha256sum es lo que se quiere ver

ARQ=amd64
DESTINO="${1:?uso: ./fig01_02.sh CARPETA}"
mkdir -p "$DESTINO"
cd "$DESTINO" || exit 1

paso() { printf '\n$ %s\n' "$*"; "$@"; local rc=$?; [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"; return 0; }

echo "## Caso 1: binario de v1.37.0, suma de v1.37.1"
paso curl -fsSLO "https://dl.k8s.io/release/v1.37.0/bin/linux/$ARQ/kubectl"
paso curl -fsSLO "https://dl.k8s.io/release/v1.37.1/bin/linux/$ARQ/kubectl.sha256"
printf '\n$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -\n'
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
rc=$?; [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"

echo
echo "## Caso 2: el binario correcto, con un byte de más"
paso curl -fsSLO "https://dl.k8s.io/release/v1.37.1/bin/linux/$ARQ/kubectl"
printf 'x' >> kubectl
printf '\n$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -\n'
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
rc=$?; [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
exit 0
