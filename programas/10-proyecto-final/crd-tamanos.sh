#!/usr/bin/env bash
# crd-tamanos.sh — Lección 10, 10.4.3: ¿cuánto pesa cada CRD de la plataforma?
# Un «kubectl apply» sin --server-side copia el objeto entero, en JSON compacto,
# dentro de la anotación kubectl.kubernetes.io/last-applied-configuration, y el
# servidor rechaza una anotación de más de 262,144 bytes. Este guion renderiza la
# plataforma, convierte cada CRD a JSON compacto y lo mide. No necesita clúster
# (sí internet: la plataforma se descarga de sus lanzamientos). Uso, desde esta
# carpeta:  ./crd-tamanos.sh > crd-tamanos.salida.txt 2>&1
set -euo pipefail
cd "$(dirname "$0")"
kubectl kustomize overlays/kind/plataforma | python3 -c '
import sys, json, yaml
LIMITE = 262144
filas = []
for doc in yaml.safe_load_all(sys.stdin):
    if doc and doc.get("kind") == "CustomResourceDefinition":
        n = len(json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode())
        filas.append((n, doc["metadata"]["name"]))
filas.sort(reverse=True)
print("CRD en la plataforma:", len(filas))
print("%8s  %s" % ("BYTES", "CRD"))
for n, nombre in filas[:6]:
    print("%8d  %s%s" % (n, nombre, "   <- pasa de %d" % LIMITE if n > LIMITE else ""))
print("pasan del límite:", sum(1 for n, _ in filas if n > LIMITE))
'
