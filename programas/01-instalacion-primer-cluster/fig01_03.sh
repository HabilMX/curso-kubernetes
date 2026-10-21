#!/usr/bin/env bash
# fig01_03.sh — Lección 1, sección 1.3.5: comprobar e instalar los binarios que
# bajó fig01_01.sh en un Ubuntu 24.04 para amd64 (la base de Linux Mint 22),
# DENTRO DE UN CONTENEDOR DESECHABLE.
#
# Sirve para ver la instalación completa sin tocar tu sistema: el contenedor se
# borra al salir (--rm) y con él los binarios «instalados». En tu Mint, los
# mismos dos «install» se corren con sudo (la lección lo dice).
#
# Uso:  ./fig01_03.sh CARPETA     (la misma que le diste a fig01_01.sh)
#
# Los archivos entran al contenedor por un tar en la entrada estándar, sin
# montar carpetas: así funciona aunque Docker corra en una máquina virtual que
# no ve tus carpetas temporales.
set -euo pipefail

ORIGEN="${1:?uso: ./fig01_03.sh CARPETA}"
cd "$ORIGEN"

tar cf - kubectl kubectl.sha256 kind-linux-amd64 kind-linux-amd64.sha256sum |
docker run --rm -i --platform linux/amd64 --name curso-k8s-l1-mint ubuntu:24.04 bash -c '
set -e
mkdir /d && cd /d && tar xf -
. /etc/os-release
echo "# $PRETTY_NAME, $(uname -m), $(sha256sum --version | head -1)"
echo; echo "\$ echo \"\$(cat kubectl.sha256)  kubectl\" | sha256sum --check"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
echo; echo "\$ sha256sum --check kind-linux-amd64.sha256sum"
sha256sum --check kind-linux-amd64.sha256sum
echo; echo "\$ install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
echo "\$ install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind"
install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind
echo; echo "\$ ls -l /usr/local/bin/kubectl /usr/local/bin/kind"
ls -l /usr/local/bin/kubectl /usr/local/bin/kind
echo; echo "\$ command -v kubectl kind"; command -v kubectl kind
echo; echo "\$ kubectl version --client"; kubectl version --client
echo; echo "\$ kind version"; kind version
'
