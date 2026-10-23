#!/usr/bin/env bash
# levantar.sh — Lección 6, sección 6.9: la plataforma y el proyecto, desde un
# clúster recién creado, en tres pasos y en este orden:
#   1. la plataforma: los tipos nuevos (CRD), sus controladores y sus guardianes;
#   2. la espera: tipos establecidos y controladores listos (kubectl wait);
#   3. la configuración de la plataforma (rango y clase) y después el proyecto.
#
# Uso, desde esta carpeta y con el clúster curso-k8s-l6 recién creado, las dos
# imágenes cargadas y token.txt generado:   ./levantar.sh
#
# 🔴 Antes de CADA cambio, ctx comprueba que el contexto activo es
# kind-curso-k8s-l6 y, si no, el guion se detiene: MetalLB y Envoy Gateway crean
# objetos que valen para todo el clúster, y aplicarlos en otro sería instalarlos
# en el clúster de otra persona.
set -euo pipefail
cd "$(dirname "$0")"

ctx() { [ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo" >&2; return 1; }; }
# paso CADENA → comprueba el contexto, imprime «$ CADENA» y la corre. Si falla, se detiene.
paso() { ctx; printf '\n$ %s\n' "$*"; eval "$@"; }

[ -f token.txt ] || { echo "falta token.txt: (umask 077; openssl rand -hex 16 > token.txt)" >&2; exit 1; }

echo "## Paso 1: la plataforma"
paso "kubectl apply -k infra/metallb"
paso "kubectl apply --server-side -k infra/envoy-gateway"

echo
echo "## Paso 2: la espera"
paso "kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
paso "kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s"
paso "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"

echo
echo "## Paso 3: la configuración de la plataforma, y el proyecto"
paso "kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml"
paso "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
paso "kubectl apply -k ."
paso "kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s"
