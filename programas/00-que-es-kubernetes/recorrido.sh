#!/usr/bin/env bash
# recorrido.sh — Lección 0: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l0, lo recorre, provoca el error de la
# lección y lo borra. Tarda unos dos minutos. Necesita Docker, kind y kubectl
# (la Lección 1 los instala).
#
# Uso:  ./recorrido.sh            (desde esta carpeta)
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

echo "=== 1. Crear el clúster ==="
paso kind create cluster --name "$CLUSTER" --config fig00_01.kind.yaml --kubeconfig "$KUBECONFIG"
CREADO_AQUI=si
paso kubectl config current-context
# El clúster recién creado tarda unos segundos en estar listo: se espera, no se adivina.
k wait --for=condition=Ready nodes --all --timeout=180s
k wait --for=condition=Ready pods --all -n kube-system --timeout=180s

echo
echo "=== 2. Los nodos son contenedores ==="
k get nodes -o wide
paso docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER" --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'

echo
echo "=== 3. El plano de control, por dentro ==="
k get pods -n kube-system
paso docker exec "$CLUSTER-control-plane" ls /etc/kubernetes/manifests
paso docker exec "$CLUSTER-control-plane" sh -c "ps -eo comm | grep -E '^(kubelet|containerd|kube-|etcd)' | sort"

echo
echo "=== 4. Declarar un estado deseado ==="
k apply -f fig00_02.deployment.yaml
k rollout status deployment/espera --timeout=90s
k get deployment espera
k get replicaset -l app=espera
k get pods -l app=espera

echo
echo "=== 5. Borrar un Pod y ver qué hace el clúster ==="
contexto_correcto
VICTIMA="$(kubectl get pods -l app=espera -o jsonpath='{.items[0].metadata.name}')"
k delete pod "$VICTIMA"
k get pods -l app=espera
k get events --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp

echo
echo "=== 6. Una orden contra una declaración ==="
k scale deployment espera --replicas=5
k get deployment espera
contexto_correcto
printf '\n$ kubectl diff -f fig00_02.deployment.yaml\n'
# kubectl diff sale con 1 cuando HAY diferencias: aquí es lo esperado, no un fallo.
kubectl diff -f fig00_02.deployment.yaml || true
k apply -f fig00_02.deployment.yaml
k rollout status deployment/espera --timeout=90s
k get deployment espera

echo
echo "=== 7. Qué defiende un clúster local y qué no ==="
k auth whoami
k config view --minify
paso docker inspect "$CLUSTER-control-plane" --format 'privilegiado={{.HostConfig.Privileged}}  puerto_api={{json .NetworkSettings.Ports}}'

echo
echo "=== 8. Borrar todo ==="
k delete -f fig00_02.deployment.yaml
paso kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"
CREADO_AQUI=no

echo
echo "=== 9. El error de la lección: kubectl sin clúster ==="
# Ya no hay contexto: kind lo quitó al borrar. Este kubeconfig es el temporal del
# guion, así que el comando no puede alcanzar ningún otro clúster tuyo.
printf '\n$ kubectl config current-context\n'
kubectl config current-context || true
printf '\n$ kubectl get nodes\n'
kubectl get nodes 2>&1 || true
