#!/usr/bin/env bash
# preparar.sh — Lección 9, sección 9.1: deja un clúster recién creado en el estado
# con el que termina la Lección 8: la plataforma (MetalLB y Envoy Gateway) y el
# proyecto de punto-de-partida/. Son los tres pasos de la Lección 6, en el mismo
# orden y con las esperas a la vista:
#   1. la plataforma  ·  2. la espera  ·  3. el rango, la clase y el proyecto
#
# Uso, desde esta carpeta, con el clúster curso-k8s-l9 recién creado, las tres
# imágenes cargadas y token.txt generado:   ./preparar.sh
#
# POOL_RANGO (opcional) cambia el rango de MetalLB. Por omisión es el de la red
# «kind» normal, 172.18.255.200-172.18.255.220; si tu red kind no es 172.18.0.0/16
# o usas una red propia, pásalo:   POOL_RANGO=172.29.255.200-172.29.255.250 ./preparar.sh
#
# 🔴 Antes de CADA cambio, ctx comprueba que el contexto activo es
# kind-curso-k8s-l9 y, si no, el guion se detiene.
set -euo pipefail
cd "$(dirname "$0")"

ctx() { [ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo" >&2; return 1; }; }
paso() { ctx; printf '\n$ %s\n' "$*"; eval "$@"; }

[ -f token.txt ] || { echo "falta token.txt: (umask 077; openssl rand -hex 16 > token.txt)" >&2; exit 1; }
POOL="infra/metallb-pool.yaml"
if [ -n "${POOL_RANGO:-}" ]; then
  POOL="$(mktemp "${TMPDIR:-/tmp}/metallb-pool.XXXX")"
  sed "s#172.18.255.200-172.18.255.220#${POOL_RANGO}#" infra/metallb-pool.yaml > "$POOL"
fi
# El punto de partida usa el MISMO token, para que el Secret tenga el mismo nombre.
(umask 077; cp token.txt punto-de-partida/token.txt)

echo "## Paso 1: la plataforma"
paso "kubectl apply -k infra/metallb >/dev/null"
paso "kubectl apply --server-side -k infra/envoy-gateway >/dev/null"

echo
echo "## Paso 2: la espera"
paso "kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=1200s"
paso "kubectl rollout status daemonset/speaker -n metallb-system --timeout=1200s"
paso "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=1200s"

echo
echo "## Paso 3: la configuración de la plataforma, y el proyecto"
paso "kubectl apply -f $POOL -f infra/gatewayclass.yaml"
paso "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
paso "kubectl apply -k punto-de-partida >/dev/null"
paso "kubectl rollout status deployment/revisor deployment/prueba -n revisor --timeout=600s"
paso "kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=1200s"
[ "$POOL" = infra/metallb-pool.yaml ] || rm -f "$POOL"
