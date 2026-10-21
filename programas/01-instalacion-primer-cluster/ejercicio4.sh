#!/usr/bin/env bash
# ejercicio4.sh — Lección 1, Ejercicio 4: dos clústeres en el MISMO kubeconfig.
#
# Crea curso-k8s-l1 (tres nodos) y curso-k8s-l1b (uno), mira qué contexto queda
# activo, le habla a cada uno con --context, borra solo el segundo, vuelve al
# primero y, al salir, borra lo que quede. Tarda un par de minutos.
#
# Uso:  ./ejercicio4.sh           (desde esta carpeta)
#
# 🔴 Las mismas tres protecciones de correr.sh: kubeconfig temporal propio,
# comprobación del contexto antes de hablarle al clúster y un trap que borra
# solo los clústeres que ESTA corrida creó.
set -euo pipefail
cd "$(dirname "$0")"

CURSO=curso-k8s-l1
OTRO=curso-k8s-l1b
CREADOS=()
TEMPORAL=""

limpiar() {
  local c
  for c in "${CREADOS[@]:-}"; do
    case "$c" in
      curso-k8s-l1|curso-k8s-l1b) kind delete cluster --name "$c" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true ;;
    esac
  done
  case "$TEMPORAL" in
    */curso-k8s-l1.?*) if [ -d "$TEMPORAL" ]; then rm -rf -- "$TEMPORAL"; fi ;;
  esac
}
trap limpiar EXIT

for c in "$CURSO" "$OTRO"; do
  if kind get clusters 2>/dev/null | grep -qx -- "$c"; then
    echo "ALTO: ya existe un clúster de kind llamado «$c». Este guion no lo toca." >&2
    exit 1
  fi
done

TEMPORAL="$(mktemp -d "${TMPDIR:-/tmp}/curso-k8s-l1.XXXX")"
export KUBECONFIG="$TEMPORAL/kubeconfig"

paso() {
  printf '\n$ %s\n' "$*"
  local rc=0
  "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
contexto_es() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  [ "$actual" = "$1" ] || { echo "ALTO: el contexto activo es «$actual», no «$1». No sigo." >&2; exit 1; }
}
# crear NOMBRE [ARGS] → crea el clúster sin la animación de kind y lo anota
crear() {
  local nombre="$1"; shift
  printf '\n$ kind create cluster --name %s %s\n' "$nombre" "$*"
  kind create cluster --name "$nombre" "$@" >/dev/null 2>&1
  CREADOS+=("$nombre")
  echo "(creado; se omite la animación de kind)"
}

crear "$CURSO" --config kind-curso.yaml
crear "$OTRO"

echo
echo "## 1. ¿Cuál quedó activo?"
paso kubectl config get-contexts

echo
echo "## 2. Los nodos de cada uno, con --context"
paso kubectl --context "kind-$CURSO" wait --for=condition=Ready nodes --all --timeout=240s
paso kubectl --context "kind-$CURSO" get nodes
paso kubectl --context "kind-$OTRO" wait --for=condition=Ready nodes --all --timeout=240s
paso kubectl --context "kind-$OTRO" get nodes

echo
echo "## 3. Borrar solo el segundo y volver al primero"
paso kind delete cluster --name "$OTRO"
paso kubectl config current-context
paso kubectl config get-contexts
paso kubectl config use-context "kind-$CURSO"
contexto_es "kind-$CURSO"
paso kubectl get nodes

echo
echo "## 4. Borrar el del curso y comprobar que no queda nada"
paso kind delete cluster --name "$CURSO"
paso docker ps --filter "label=io.x-k8s.kind.cluster=$CURSO" --format '{{.Names}}'
paso docker ps --filter "label=io.x-k8s.kind.cluster=$OTRO" --format '{{.Names}}'
