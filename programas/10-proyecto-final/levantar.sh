#!/usr/bin/env bash
# levantar.sh — Lección 10: el proyecto completo en un clúster recién creado, en
# TRES pasos explícitos, sin esconder el orden. Es lo que un paso de pipeline
# haría igual: la única entrada es el contexto de kubectl que espera encontrar.
#
#   1. la plataforma: metrics-server, MetalLB y Envoy Gateway (traen tipos nuevos,
#      controladores y webhooks)
#   2. esperar a que la plataforma esté lista (tipos registrados, controladores arriba)
#   3. el proyecto
#
# Por qué hay orden: un IPAddressPool, una GatewayClass o un Gateway solo existen
# cuando su CRD ya está registrado, y MetalLB rechaza su rango si su webhook
# todavía no atiende.
#
# Requisitos: un clúster de kind con las dos imágenes cargadas (kind load
# docker-image) y su contexto activo. Uso, desde esta carpeta:
#   ./levantar.sh kind-curso-k8s-l10
set -euo pipefail
cd "$(dirname "$0")"
ESPERADO="${1:?uso: ./levantar.sh <contexto-esperado>   (por ejemplo kind-curso-k8s-l10)}"
NODO_CONTROL="${ESPERADO#kind-}-control-plane"

# Antes de CADA paso que cambia algo: ¿el contexto activo es el esperado?
contexto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  [ "$actual" = "$ESPERADO" ] || { echo "ALTO: el contexto activo es «$actual», no «$ESPERADO»." >&2; exit 1; }
}

# El token no se versiona: si falta, se genera uno nuevo (de mentira, para el curso).
[ -s base/token.txt ] || (umask 077; openssl rand -hex 16 > base/token.txt)

echo "== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?"
contexto
RANGO="$(sed -n 's/^ *- *\([0-9.]*\)-.*/\1/p' overlays/kind/metallb-pool.yaml | head -1)"
IP_NODO="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODO_CONTROL")"
echo "primer IP del rango: $RANGO · IP del nodo de control: $IP_NODO"
[ "${RANGO%.*.*}" = "${IP_NODO%.*.*}" ] || {
  echo "ALTO: el rango de overlays/kind/metallb-pool.yaml no está en la red de los nodos (se compara la red /16)." >&2; exit 1; }

echo "== 1. Plataforma"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind/plataforma)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
echo "(paso 1 terminó a los $SECONDS s)"

echo "== 2. Esperar a la plataforma"
contexto
kubectl wait --for=condition=Established --timeout=120s \
  crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
echo "(paso 2 terminó a los $SECONDS s)"

echo "== 3. Proyecto"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
kubectl get gateway revisor -n revisor
echo "(paso 3 terminó a los $SECONDS s)"
