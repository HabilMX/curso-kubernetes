#!/usr/bin/env bash
# fig01_01.sh — Lección 1, sección 1.3: descargar kubectl y kind con la versión
# FIJADA y comprobar su suma sha256 ANTES de instalarlos.
#
# Solo descarga y comprueba: no instala nada ni pide sudo. Los dos binarios
# quedan en la carpeta que le des, listos para el «sudo install» de la lección.
#
# Uso:  ./fig01_01.sh CARPETA        (una carpeta nueva y vacía, por ejemplo ~/descargas-k8s)
#
# Descarga los binarios de Linux para amd64, los de Linux Mint en un equipo
# Intel o AMD. Si tu equipo es ARM, cambia ARQ=arm64.
set -euo pipefail

KUBECTL_VERSION=v1.37.1
KIND_VERSION=v0.33.0
ARQ=amd64

DESTINO="${1:?uso: ./fig01_01.sh CARPETA}"
mkdir -p "$DESTINO"
cd "$DESTINO"

# Muestra el comando como lo teclearías y luego lo corre.
paso() { printf '\n$ %s\n' "$*"; "$@"; }

echo "# kubectl $KUBECTL_VERSION y kind $KIND_VERSION para linux/$ARQ"

# kubectl: el binario y su suma salen de dl.k8s.io, con la MISMA versión.
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl"
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl.sha256"
paso cat kubectl.sha256; echo
# El archivo .sha256 de kubectl trae solo la suma; se le pega el nombre del
# archivo, como lo pide la guía oficial. El «-» final dice «lee la lista de la
# entrada»: en Linux es opcional, y con él el guion corre igual en macOS.
printf '\n$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -\n'
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -

# kind: el binario y su suma salen del lanzamiento en GitHub. El .sha256sum de
# kind ya trae «suma  nombre», así que se comprueba directo.
paso curl -fsSLo "kind-linux-$ARQ" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ"
paso curl -fsSLo "kind-linux-$ARQ.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ.sha256sum"
paso cat "kind-linux-$ARQ.sha256sum"
paso sha256sum --check "kind-linux-$ARQ.sha256sum"

# Lo que quedó: dos binarios comprobados. wc -c da su tamaño en bytes, para
# compararlo con el de la lección.
paso wc -c kubectl "kind-linux-$ARQ"
