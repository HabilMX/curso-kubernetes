#!/usr/bin/env bash
# correr.sh — Lección 5: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l5 (tres nodos), le carga las dos
# imágenes del curso de Docker, deja el revisor y el servicio de prueba como los
# dejó la Lección 4 (carpeta punto-de-partida/) y recorre la lección: lo que el
# clúster sabe sin sondas, las tres sondas, la capacidad de los nodos, requests y
# limits, el OOMKilled y el Pending a propósito, y el apagado ordenado. Corre los
# Ejercicios 1 a 3 y borra el clúster. Tarda unos cinco minutos.
#
# Necesita Docker, kind, kubectl (Lección 1), openssl y las imágenes
# curso-docker-revisor:1.6.0 y curso-docker-prueba:1.0.0 del curso de Docker.
#
# Uso:  ./correr.sh > /tmp/mi-corrida-l5.txt 2>&1     (desde esta carpeta)
#
# No usa ningún puerto de tu máquina.
#
# 🔴 SEGURIDAD: le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config
# no se lee ni se toca); antes de cada kubectl comprueba que el contexto activo es
# kind-curso-k8s-l5 y se detiene si no; no pisa un clúster que ya exista con ese
# nombre; y al salir —aunque algo falle— borra el clúster y los token.txt que
# ESTA corrida creó, y nada más.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l5
CONTEXTO="kind-$CLUSTER"
IMAGEN=curso-docker-revisor:1.6.0
IMAGEN_PRUEBA=curso-docker-prueba:1.0.0
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
CREADO_AQUI=no
TEMPORAL=""
TOKENS_CREADOS=()
LOGS=""

limpiar() {
  [ -n "$LOGS" ] && kill "$LOGS" 2>/dev/null || true
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  local t
  for t in "${TOKENS_CREADOS[@]+"${TOKENS_CREADOS[@]}"}"; do rm -f -- "$t"; done
  case "$TEMPORAL" in
    /tmp/curso-k8s-l5.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
  esac
  return 0
}
trap limpiar EXIT

# ── Comprobaciones antes de crear nada ──────────────────────────────────────
if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster de kind llamado «$CLUSTER». Bórralo tú si es tuyo; este guion no lo toca." >&2
  exit 1
fi
for i in "$IMAGEN" "$IMAGEN_PRUEBA"; do
  if ! docker image inspect "$i" >/dev/null 2>&1; then
    echo "ALTO: no encuentro la imagen $i en tu Docker. Constrúyela con el curso de Docker." >&2
    exit 1
  fi
done
for t in token.txt punto-de-partida/token.txt; do
  if [ -e "$t" ]; then
    echo "ALTO: ya existe $t. Es de otra corrida o tuyo; bórralo tú y vuelve a correr." >&2
    exit 1
  fi
done
USO="$(docker run --rm --entrypoint df "$CURL_IMAGEN" -P /etc/hostname 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')"
if [ -n "$USO" ] && [ "$USO" -gt 80 ]; then
  echo "ALTO: el disco de Docker está al ${USO} % (más de 80 %). No sigo." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l5.XXXX)"
export KUBECONFIG="$TEMPORAL/kubeconfig"
export TMPDIR="$TEMPORAL"

contexto_correcto() {
  local actual
  actual="$(command kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    exit 1
  fi
}
# k ARGS → comprueba el contexto y corre kubectl sin mostrar el comando
k() { contexto_correcto; command kubectl "$@"; }
titulo() { printf '\n## %s\n' "$*"; }
# muestra "CADENA" → comprueba el contexto, imprime «$ CADENA» y la corre.
# Un código distinto de 0 se anota y no detiene el guion (hay fallos a propósito).
muestra() {
  contexto_correcto
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# fuera "CADENA" → igual que muestra, para comandos que no son kubectl
fuera() {
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# esperar_listos SERVICIO N → espera (hasta 90 s) a que el EndpointSlice del
# Service tenga EXACTAMENTE N direcciones listas. Primero la lista, luego la prueba.
esperar_listos() {
  local n
  for _ in $(seq 1 90); do
    n="$(k get endpointslices -l kubernetes.io/service-name="$1" \
      -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | grep -c . || true)"
    [ "$n" = "$2" ] && { sleep 2; return 0; }
    sleep 1
  done
  echo "(aviso: el EndpointSlice de $1 no llegó a $2 direcciones listas en 90 s)"
}
# esperar_pods APP N → espera (hasta 90 s) a que queden EXACTAMENTE N Pods con
# app=APP, todos Running y sin borrarse (los viejos del rollout ya se fueron)
esperar_pods() {
  local total vivos
  for _ in $(seq 1 90); do
    total="$(k get pods -l app="$1" --no-headers 2>/dev/null | grep -c . || true)"
    vivos="$(k get pods -l app="$1" -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.deletionTimestamp}{"|"}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -cx '|true' || true)"
    [ "$total" = "$2" ] && [ "$vivos" = "$2" ] && return 0
    sleep 1
  done
  echo "(aviso: no quedaron $2 Pods $1 listos en 90 s)"
}
nuevo_token() {
  (umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
  TOKENS_CREADOS+=("$PWD/punto-de-partida/token.txt")
  cp punto-de-partida/token.txt token.txt
  TOKENS_CREADOS+=("$PWD/token.txt")
  TOKEN="$(cat token.txt)"
}

echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · kind $(kind version | cut -d' ' -f2) · kubectl $(command kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"
INICIO_TOTAL=$(date +%s)

titulo "Punto de partida: el clúster y lo que dejó la Lección 4"
printf '\n$ kind create cluster --name %s --config kind-curso.yaml\n' "$CLUSTER"
inicio=$(date +%s)
if ! kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear.log" 2>&1; then
  echo "FALLÓ kind create cluster:"; cat "$TEMPORAL/crear.log"
  # kind pudo dejar nodos a medias: si el clúster quedó registrado, es de esta corrida
  if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then CREADO_AQUI=si; fi
  exit 1
fi
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
echo "(crear el clúster y esperar a que esté listo tardó $(( $(date +%s) - inicio )) s)"
muestra "kubectl config current-context"
muestra "kubectl get nodes"
printf '\n$ kind load docker-image %s %s --name %s\n' "$IMAGEN" "$IMAGEN_PRUEBA" "$CLUSTER"
kind load docker-image "$IMAGEN" "$IMAGEN_PRUEBA" --name "$CLUSTER" 2>&1
nuevo_token
fuera "ls -l punto-de-partida/token.txt token.txt | cut -d' ' -f1"
fuera "wc -c < punto-de-partida/token.txt"
muestra "kubectl apply -k punto-de-partida"
k rollout status deployment/revisor --timeout=180s >/dev/null
k rollout status deployment/prueba --timeout=180s >/dev/null
esperar_pods revisor 3
esperar_listos revisor 3

titulo "5.1 Lo que el clúster sabe hoy"
muestra "kubectl get pods -l 'app in (revisor,prueba)'"
POD="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl describe pod $POD | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests'"
muestra "kubectl get pod $POD -o jsonpath='{.spec.terminationGracePeriodSeconds}{\"\\n\"}'"
muestra "kubectl get pod $POD -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{\"\\n\"}'"

titulo "5.2 Sondas, recursos y plazo de apagado: kubectl apply -k ."
muestra "diff punto-de-partida/token.txt token.txt && echo 'mismo token'"
muestra "kubectl diff -k . | grep -E '^\\+ ' | grep -vE 'generation|resourceVersion|uid:|creationTimestamp'"
muestra "kubectl apply -k ."
k rollout status deployment/revisor --timeout=180s >/dev/null
k rollout status deployment/prueba --timeout=180s >/dev/null
esperar_pods revisor 3
esperar_pods prueba 1
esperar_listos revisor 3
sleep 3
muestra "kubectl get pods -l app=revisor"
POD="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl describe pod $POD | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests|cpu:|memory:'"
muestra "kubectl get pod $POD -o jsonpath='{.spec.terminationGracePeriodSeconds}{\"\\n\"}'"

titulo "5.4 Las sondas, en la bitácora del revisor"
sleep 20
muestra "kubectl logs --timestamps $POD | head -9 | sed -E 's/^[0-9-]+T([0-9:]+)\\.[0-9]+Z/\\1/'"
muestra "kubectl get pod $POD -o jsonpath='{.status.startTime} {.status.containerStatuses[0].started} {.status.containerStatuses[0].ready}{\"\\n\"}'"

titulo "5.5 /salud no consulta a nadie: prueba caído no reinicia al revisor"
muestra "kubectl apply -f depurar.yaml"
k wait --for=condition=Ready pod/depurar --timeout=180s >/dev/null
esperar_listos prueba 1
muestra "kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido"
sleep 35
muestra "kubectl get pods -l 'app in (revisor,prueba)'"
muestra "kubectl exec depurar -- curl -s -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano"

titulo "5.6 La capacidad de los nodos"
muestra "kubectl get nodes -o custom-columns='NODO:.metadata.name,CPU:.status.allocatable.cpu,MEMORIA:.status.allocatable.memory'"
muestra "kubectl describe node $CLUSTER-worker | sed -n '/^Allocated resources:/,/^Events:/p' | head -8"
NODO_REVISOR="$(k get pod "$POD" -o jsonpath='{.spec.nodeName}')"
fuera "docker exec $NODO_REVISOR crictl stats --label io.kubernetes.container.name=revisor | sed 's/^.\[2J.\[H//'"

titulo "El error a propósito: OOMKilled"
muestra "kubectl apply -f memoria.yaml"
sleep 20
muestra "kubectl get pod memoria"
muestra "kubectl get pod memoria -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}{\"\\n\"}'"
muestra "kubectl logs memoria"
muestra "kubectl describe pod memoria | grep -E '^QoS Class:|Reason:|Exit Code:|Limits:|memory:'"
muestra "kubectl delete pod memoria"

titulo "El error a propósito: Pending"
muestra "kubectl patch deployment revisor --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/cpu\",\"value\":\"50\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/limits/cpu\",\"value\":\"50\"}]'"
sleep 10
muestra "kubectl get pods -l app=revisor"
muestra "kubectl rollout status deployment/revisor --timeout=15s"
PENDIENTE="$(k get pods -l app=revisor --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl describe pod $PENDIENTE | sed -n '/^Events:/,\$p'"
muestra "kubectl exec depurar -- curl -s http://revisor/salud"
muestra "kubectl apply -k ."
k rollout status deployment/revisor --timeout=180s >/dev/null
esperar_pods revisor 3
muestra "kubectl get pods -l app=revisor"

titulo "5.7 Apagado ordenado: lo que el revisor escribe al recibir SIGTERM"
esperar_listos revisor 3
POD="$(k get pods -l app=revisor --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
contexto_correcto
command kubectl logs -f "$POD" > "$TEMPORAL/apagado.log" 2>&1 &
LOGS=$!
sleep 1
inicio=$(date +%s)
muestra "kubectl delete pod $POD"
fin=$(date +%s)
wait "$LOGS" 2>/dev/null || true
LOGS=""
echo "(el borrado tardó $((fin-inicio)) s)"
printf '\n$ kubectl logs -f %s   # lo que se alcanzó a leer, en otra terminal\n' "$POD"; tail -4 "$TEMPORAL/apagado.log"
esperar_pods revisor 3
muestra "kubectl get pods -l app=revisor"

titulo "Hábito de seguridad: requests y limits en todo contenedor"
muestra "kubectl get pods -o custom-columns='POD:.metadata.name,QOS:.status.qosClass,CPU_PIDE:.spec.containers[0].resources.requests.cpu,CPU_TOPE:.spec.containers[0].resources.limits.cpu,MEM_PIDE:.spec.containers[0].resources.requests.memory,MEM_TOPE:.spec.containers[0].resources.limits.memory'"

titulo "Ejercicio 1: una sonda de disponibilidad en prueba"
muestra "kubectl apply -f fig05_01.prueba-disponibilidad.yaml"
k rollout status deployment/prueba --timeout=120s >/dev/null
esperar_pods prueba 1
esperar_listos prueba 1
muestra "kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido"
sleep 15
muestra "kubectl get pods -l app=prueba"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{\"\\n\"}{end}'"
muestra "kubectl exec depurar -- curl -s -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano"
IP_PRUEBA="$(k get pods -l app=prueba -o jsonpath='{.items[0].status.podIP}')"
muestra "kubectl exec depurar -- curl -s -X POST http://$IP_PRUEBA:9000/modo/sano"
esperar_listos prueba 1
muestra "kubectl get pods -l app=prueba"
muestra "kubectl apply -k ."
k rollout status deployment/prueba --timeout=120s >/dev/null
esperar_pods prueba 1
esperar_listos prueba 1

titulo "Ejercicio 2: una sonda de vida que pregunta lo que no debe"
muestra "kubectl apply -f fig05_02.prueba-vida-mala.yaml"
k rollout status deployment/prueba --timeout=120s >/dev/null
esperar_pods prueba 1
esperar_listos prueba 1
muestra "kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido"
inicio=$(date +%s)
for _ in $(seq 1 120); do
  r="$(k get pods -l app=prueba -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)"
  [ "${r:-0}" -ge 1 ] && break
  sleep 1
done
echo "(el primer reinicio llegó $(( $(date +%s) - inicio )) s después de ponerlo en «caido»)"
esperar_listos prueba 1
muestra "kubectl get pods -l app=prueba"
PRUEBA="$(k get pods -l app=prueba -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl get events --field-selector involvedObject.name=$PRUEBA -o custom-columns=RAZON:.reason,MENSAJE:.message | grep -E 'RAZON|Unhealthy|Killing'"
muestra "kubectl exec depurar -- curl -s http://prueba:9000/modo"
muestra "kubectl exec depurar -- curl -s -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl apply -k ."
k rollout status deployment/prueba --timeout=120s >/dev/null
esperar_pods prueba 1
esperar_listos prueba 1

titulo "Cómo sé que lo logré: el estado final"
muestra "kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'"
muestra "kubectl get pods -l 'app in (revisor,prueba)'"
muestra "kubectl exec depurar -- curl -s -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"

titulo "Ejercicio 3: cuánto tarda en irse el Pod de depuración"
muestra "kubectl get pod depurar -o jsonpath='{.spec.terminationGracePeriodSeconds}{\"\\n\"}'"
muestra "kubectl exec depurar -- ps"
inicio=$(date +%s)
muestra "kubectl delete pod depurar"
echo "(el borrado tardó $(( $(date +%s) - inicio )) s)"

titulo "Borrar el clúster"
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
inicio=$(date +%s)
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
echo "(borrar tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true
echo "(la corrida completa tardó $(( $(date +%s) - INICIO_TOTAL )) s)"
