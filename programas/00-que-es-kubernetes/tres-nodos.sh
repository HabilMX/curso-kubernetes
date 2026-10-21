#!/usr/bin/env bash
# tres-nodos.sh — Lección 0, sección 0.6.3: el mismo clúster con tres nodos.
#
# Crea un clúster de kind de tres nodos llamado curso-k8s-l0, comprueba que los
# tres quedan listos y lo borra. Necesita el límite fs.inotify.max_user_instances
# en 512 (la Lección 1 lo ajusta); con 128, los nodos de trabajo no arrancan. Necesita Docker, kind y kubectl
# (la Lección 1 los instala).
#
# Uso:  ./tres-nodos.sh           (desde esta carpeta)
#
# 🔴 SEGURIDAD: este guion NO toca tu configuración de kubectl ni ningún clúster
# que no haya creado él: si ya existe uno llamado curso-k8s-l0, se detiene sin
# borrarlo. Le da a kind un
# archivo kubeconfig propio, temporal, y exporta KUBECONFIG hacia él; así, si en
# tu máquina hay otros clústeres configurados, ni se enteran. Y antes de cada
# comando de kubectl comprueba que el contexto activo es el del curso.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l0
CONTEXTO="kind-$CLUSTER"
# Solo se borra lo que este guion creó en esta corrida. La bandera se enciende
# DESPUÉS de crear el clúster con éxito y se apaga en cuanto el guion lo borra.
CREADO_AQUI=no
TEMPORAL=""

limpiar() {
  # Si algo falló a medio camino, el clúster que ESTA corrida creó no se queda vivo.
  # Un clúster con el mismo nombre que ya existía antes no se toca nunca.
  if [ "$CREADO_AQUI" = si ]; then
    case "$CLUSTER" in
      curso-k8s-*) kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true ;;
    esac
  fi
  # La carpeta temporal se borra solo si es la que creó mktemp con el prefijo del curso.
  case "$TEMPORAL" in
    /tmp/curso-k8s-l0.?*) if [ -d "$TEMPORAL" ]; then rm -rf -- "$TEMPORAL"; fi ;;
  esac
}
trap limpiar EXIT

case "$CLUSTER" in
  curso-k8s-*) ;;
  *) echo "ALTO: el clúster «$CLUSTER» no lleva el prefijo curso-k8s-. No sigo." >&2; exit 1 ;;
esac
# Si ya hay un clúster con este nombre, es de otra corrida o de otra persona: no se pisa.
if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster de kind llamado «$CLUSTER». Bórralo tú si es tuyo; este guion no lo toca." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l0.XXXX)"
export KUBECONFIG="$TEMPORAL/kubeconfig"
# kubectl diff escribe sus copias temporales aquí también, y se borran al final.
export TMPDIR="$TEMPORAL"

# Muestra el comando como lo teclearías (con sus comillas) y luego su salida.
paso() {
  printf '\n$'
  local a
  for a in "$@"; do
    case "$a" in
      *\'*) printf ' "%s"' "$a" ;;
      *[[:space:]\|\{\}\$\*]*) printf " '%s'" "$a" ;;
      *) printf ' %s' "$a" ;;
    esac
  done
  printf '\n'
  "$@"
}

# El hábito de la lección: antes de cada comando, ¿a qué clúster le hablo?
contexto_correcto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    exit 1
  fi
}
k() { contexto_correcto; paso kubectl "$@"; }

CONFIG="$TEMPORAL/tres-nodos.kind.yaml"
IMAGEN='kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5'
cat > "$CONFIG" <<FIN
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: $IMAGEN
- role: worker
  image: $IMAGEN
- role: worker
  image: $IMAGEN
FIN
paso kind create cluster --name "$CLUSTER" --config "$CONFIG" --kubeconfig "$KUBECONFIG"
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=180s
k wait --for=condition=Ready pods --all -n kube-system --timeout=180s
k get nodes
k get pods -n kube-system -l k8s-app=kube-proxy -o wide
paso kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"
CREADO_AQUI=no
