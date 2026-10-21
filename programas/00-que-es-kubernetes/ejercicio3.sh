#!/usr/bin/env bash
# ejercicio3.sh — Lección 0: comprueba las predicciones del Ejercicio 3.
#
# Crea un clúster de kind llamado curso-k8s-l0, corre los cuatro casos del
# ejercicio y lo borra. Tarda unos dos minutos. Necesita Docker, kind y kubectl
# (la Lección 1 los instala).
#
# Uso:  ./ejercicio3.sh           (desde esta carpeta)
#
# Contesta el ejercicio ANTES de correrlo: el chiste es comparar.
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

paso kind create cluster --name "$CLUSTER" --config fig00_01.kind.yaml --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=180s
k apply -f fig00_02.deployment.yaml
k rollout status deployment/espera --timeout=90s

echo
echo "=== Caso 1. Borrar los tres Pods ==="
k delete pods -l app=espera
sleep 10
k get pods -l app=espera

echo
echo "=== Caso 2. Una orden a 1 y luego el archivo ==="
k scale deployment espera --replicas=1
contexto_correcto
printf '\n$ kubectl diff -f fig00_02.deployment.yaml | grep -E "^[-+] +replicas"\n'
kubectl diff -f fig00_02.deployment.yaml | grep -E '^[-+] +replicas' || true
k apply -f fig00_02.deployment.yaml
k rollout status deployment/espera --timeout=90s
k get deployment espera

echo
echo "=== Caso 3. Borrar el Deployment ==="
k delete deployment espera
sleep 5
k get replicaset,pods -l app=espera

echo
echo "=== Caso 4. kubectl sin clúster ==="
paso kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"
CREADO_AQUI=no
printf '\n$ kubectl get pods\n'
kubectl get pods 2>&1 || true
