#!/usr/bin/env bash
# psa-comprobacion.sh — Lección 10, 10.7.3: ¿qué consulta SÍ revisa los Pods que
# ya existen en un espacio? Mide dos cosas, cada una con su control:
#   1. repetir el nivel que el espacio YA tiene no revisa ningún Pod (aunque haya
#      uno que viola): Pod Security Admission solo evalúa los Pods cuando la
#      política del espacio CAMBIA;
#   2. pedir una política distinta (otra versión del mismo nivel) sí los revisa,
#      y el servidor nombra solo al Pod que viola.
# Requisitos: un clúster de kind con la imagen curso-docker-prueba:1.0.0 cargada y
# el proyecto aplicado (espacio «revisor»). No cambia nada del proyecto: crea y
# borra su propio espacio, psa-control. Uso, desde esta carpeta:
#   ./psa-comprobacion.sh kind-curso-k8s-l10 > psa-comprobacion.salida.txt 2>&1
set -euo pipefail
cd "$(dirname "$0")"
ESPERADO="${1:?uso: ./psa-comprobacion.sh <contexto-esperado>}"
ACTUAL="$(kubectl config current-context 2>/dev/null || true)"
[ "$ACTUAL" = "$ESPERADO" ] || { echo "ALTO: el contexto activo es «$ACTUAL», no «$ESPERADO»." >&2; exit 1; }
muestra() { printf '\n$ %s\n' "$*"; local rc=0; eval "$@" 2>&1 || rc=$?; [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"; return 0; }
trap 'kubectl delete namespace psa-control --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT

echo "## El control: un espacio con un Pod que viola y otro que cumple"
muestra "kubectl apply -f psa-control.yaml"
kubectl wait --for=condition=Ready pod/viola pod/cumple -n psa-control --timeout=120s >/dev/null
muestra "kubectl get pods -n psa-control"
echo
echo "## Se le pone restricted de verdad: el servidor sí avisa, porque el nivel CAMBIA"
muestra "kubectl label --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37"

echo
echo "## La consulta de antes: repetir el nivel que el espacio ya tiene"
muestra "kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37"

echo
echo "## La consulta que sí revisa: pedir otra versión de la política"
muestra "kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce-version=v1.36"

echo
echo "## Lo mismo sobre el espacio del proyecto"
muestra "kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37"
muestra "kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce-version=v1.36"
muestra "kubectl get pods -n revisor --no-headers | wc -l"
