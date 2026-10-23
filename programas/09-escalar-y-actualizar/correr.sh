#!/usr/bin/env bash
# correr.sh — Lección 9: todo lo que la lección muestra, de principio a fin.
#
# Crea el clúster curso-k8s-l9 (tres nodos), le carga las tres imágenes del curso,
# lo deja en el estado de la Lección 8 (preparar.sh) y recorre la lección:
# metrics-server (que tal cual no funciona en kind), el HPA con su fórmula, el
# reparto entre nodos, la carga que lo hace subir y la ventana que lo hace bajar,
# una actualización medida CON y SIN preStop, rollout undo, el PDB frente a un
# drain (bueno y estricto) y un nodo caído medido durante 100 s. Borra el clúster.
#
# Necesita Docker, kind, kubectl (Lección 1), openssl, internet (metrics-server,
# MetalLB y Envoy Gateway se descargan de sus lanzamientos, fijados a su versión)
# y las imágenes curso-docker-revisor:1.6.0, curso-docker-revisor:1.6.1 y
# curso-docker-prueba:1.0.0.
#
# Uso:  ./correr.sh > correr.salida.txt 2>&1     (desde esta carpeta)
#
# RED. Por omisión usa la red «kind» normal de Docker (172.18.0.0/16). Para
# correr en paralelo con otros clústeres con MetalLB, se le puede dar una red propia:
#   docker network create --subnet 172.29.0.0/16 mi-red
#   RED=mi-red SUBRED=172.29.0.0/16 ./correr.sh > correr.salida.txt 2>&1
# El rango de MetalLB se calcula dentro de esa subred (x.y.255.200-x.y.255.250).
#
# 🔴 SEGURIDAD Y CONVIVENCIA:
# - kubeconfig PROPIO y temporal; antes de cada kubectl comprueba que el contexto
#   activo es kind-curso-k8s-l9 y, si no, se detiene;
# - se detiene antes de crear nada si la red no tiene la subred esperada o si
#   alguien ya contesta en la primera IP del rango (otro MetalLB con el mismo rango);
# - al salir —aunque algo falle— borra el clúster que ESTA corrida creó, sus
#   contenedores de cliente y los token.txt que generó;
# - lo único que se apaga a propósito es el contenedor de UN nodo de ESTE clúster,
#   y se vuelve a encender.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l9
CONTEXTO="kind-$CLUSTER"
RED="${RED:-kind}"
SUBRED="${SUBRED:-172.18.0.0/16}"
BASE="${SUBRED%.0.0/16}"
POOL_RANGO="$BASE.255.200-$BASE.255.250"
PRIMERA_IP="$BASE.255.200"
IMAGENES=(curso-docker-revisor:1.6.0 curso-docker-revisor:1.6.1 curso-docker-prueba:1.0.0)
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
CREADO_AQUI=no
TOKEN_CREADO_AQUI=no
TEMPORAL=""
export KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED"

limpiar() {
  docker rm -f "$CLUSTER-cliente" >/dev/null 2>&1 || true
  if [ "$CREADO_AQUI" = si ]; then
    docker start "$CLUSTER-worker" "$CLUSTER-worker2" >/dev/null 2>&1 || true
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  [ "$TOKEN_CREADO_AQUI" = si ] && rm -f token.txt punto-de-partida/token.txt
  case "$TEMPORAL" in
    /tmp/curso-k8s-l9.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
  esac
  return 0
}
trap limpiar EXIT

# --- Comprobaciones antes de crear nada -------------------------------------
if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster de kind llamado «$CLUSTER». Bórralo tú si es tuyo; este guion no lo toca." >&2
  exit 1
fi
for imagen in "${IMAGENES[@]}"; do
  docker image inspect "$imagen" >/dev/null 2>&1 || { echo "ALTO: no encuentro la imagen $imagen en tu Docker." >&2; exit 1; }
done
if [ -e token.txt ] || [ -e punto-de-partida/token.txt ]; then
  echo "ALTO: ya hay un token.txt aquí. Este guion genera el suyo y lo borra al terminar; quita el tuyo primero." >&2
  exit 1
fi
RED_REAL="$(docker network inspect "$RED" -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null || true)"
case " $RED_REAL " in
  *" $SUBRED "*) ;;
  *) echo "ALTO: la red «$RED» de Docker es «$RED_REAL», no $SUBRED. Ajusta RED y SUBRED." >&2; exit 1 ;;
esac
if docker run --rm --network "$RED" --name "$CLUSTER-cliente" "$CURL_IMAGEN" -s -o /dev/null -m 3 "http://$PRIMERA_IP/" >/dev/null 2>&1; then
  echo "ALTO: alguien ya contesta en $PRIMERA_IP (¿otro clúster con MetalLB y el mismo rango?). Espera a que termine." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l9.XXXX)"
export KUBECONFIG="$TEMPORAL/kubeconfig"
export TMPDIR="$TEMPORAL"

contexto_correcto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    exit 1
  fi
}
k() { contexto_correcto; kubectl "$@"; }
titulo() { printf '\n## %s\n' "$*"; }
# muestra "CADENA" → comprueba el contexto, imprime «$ CADENA» y la corre. Un
# código distinto de 0 se anota y no detiene el guion (hay fallos a propósito).
muestra() {
  contexto_correcto
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
fuera() {
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
cliente() { docker run --rm --network "$RED" --name "$CLUSTER-cliente" "$CURL_IMAGEN" "$@"; }
disco() {
  docker run --rm --entrypoint df "$CURL_IMAGEN" -h /etc/hostname 2>/dev/null | awk 'NR==2{print "disco de Docker: " $5 " usado"}'
}
# seguir_hpa SEGUNDOS PASO → una línea del HPA cada PASO segundos (espera visible)
seguir_hpa() {
  local t=0
  while [ "$t" -lt "$1" ]; do
    sleep "$2"; t=$((t + $2))
    printf '[+%3ds] ' "$t"; k get hpa revisor -n revisor --no-headers
  done
}
PODS='kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp'
CRON() { date '+%H:%M:%S'; }

INICIO_TOTAL=$(date +%s)
echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · red $RED ($SUBRED) · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"
echo "# $(disco)"

titulo "9.1 El clúster y el punto de partida"
printf '\n$ kind create cluster --name %s --config kind-curso.yaml\n' "$CLUSTER"
inicio=$(date +%s)
if ! kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear.log" 2>&1; then
  echo "FALLÓ kind create cluster:"; cat "$TEMPORAL/crear.log"; exit 1
fi
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
echo "(crear el clúster y esperar a que estuviera listo tardó $(( $(date +%s) - inicio )) s)"
muestra "kubectl config current-context"
muestra "kubectl get nodes -o wide | awk '{print \$1, \$2, \$5, \$6}' | column -t"
printf '\n$ kind load docker-image %s --name %s\n' "${IMAGENES[*]}" "$CLUSTER"
kind load docker-image "${IMAGENES[@]}" --name "$CLUSTER" >/dev/null 2>&1
echo "(las tres imágenes, cargadas en los tres nodos)"
fuera "docker network inspect $RED -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'"
(umask 077; openssl rand -hex 16 > token.txt)
TOKEN_CREADO_AQUI=si
fuera "ls -l token.txt | cut -c1-10"
printf '\n$ POOL_RANGO=%s ./preparar.sh\n' "$POOL_RANGO"
inicio=$(date +%s)
contexto_correcto
POOL_RANGO="$POOL_RANGO" ./preparar.sh 2>&1
echo "(preparar.sh tardó $(( $(date +%s) - inicio )) s)"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl get deployment,hpa,pdb -n revisor"
muestra "kubectl get gateway -n revisor"
IP_GW="$(k get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
fuera "docker run --rm --network $RED --name $CLUSTER-cliente curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 5 http://$IP_GW/salud"

titulo "9.2 Medir antes de escalar: metrics-server"
muestra "kubectl top nodes"
muestra "kubectl get apiservice v1beta1.metrics.k8s.io"
muestra "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml | tail -3"
echo "(espera visible: hasta 600 s a que metrics-server descargue su imagen, arranque e intente leer a los kubelet)"
for _ in $(seq 1 60); do
  k logs -n kube-system deployment/metrics-server --tail=200 2>/dev/null | grep -q 'x509' && break
  sleep 10
done
sleep 10
muestra "kubectl get deployment metrics-server -n kube-system"
muestra "kubectl logs -n kube-system deployment/metrics-server --tail=200 | grep -E 'x509|tls|certificate' | tail -1"
muestra "kubectl top nodes"
muestra "kubectl get apiservice v1beta1.metrics.k8s.io"
muestra "kubectl apply -k metrics-server | tail -3"
muestra "kubectl rollout status deployment/metrics-server -n kube-system --timeout=600s"
echo "(espera de 45 s: metrics-server mide en ventanas y necesita un par de ellas)"; sleep 45
muestra "kubectl get apiservice v1beta1.metrics.k8s.io"
muestra "kubectl top nodes"
muestra "kubectl top pods -n revisor"
muestra "kubectl describe pod -n revisor -l app=revisor | grep -E 'Requests|cpu:' | head -4"

titulo "9.5 Aplicar los cambios: autoescalador, reparto y apagado"
muestra "kubectl diff -k . | grep -E '^[+-] ' | grep -v -E 'creationTimestamp|generation|resourceVersion|uid:|managedFields'"
muestra "kubectl apply -k . | grep -E 'horizontalpod|poddisruption|deployment'"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
echo "(espera de 30 s: el HPA necesita su primera lectura de métricas)"; sleep 30
muestra "kubectl get hpa,pdb -n revisor"
muestra "$PODS"
muestra "kubectl get deployment revisor -n revisor -o jsonpath='{.spec.replicas}{\"\\n\"}'"

titulo "9.5.4 El error: el reparto sin nodeTaintsPolicy: Honor"
muestra "kubectl patch deployment/revisor -n revisor --type=json -p '[{\"op\":\"remove\",\"path\":\"/spec/template/spec/topologySpreadConstraints/0/nodeTaintsPolicy\"}]'"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl scale deployment/revisor -n revisor --replicas=3"
echo "(espera de 6 s: el planificador decide en un instante)"; sleep 6
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
PENDIENTE="$(k get pods -n revisor -l app=revisor --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}' || true)"
muestra "kubectl describe pod $PENDIENTE -n revisor | sed -n '/Events:/,\$p'"
echo
echo "# --- La corrección: volver a aplicar la carpeta (trae Honor) ---"
muestra "kubectl apply -k . | grep -E 'deployment'"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
echo "(espera de 75 s: la ventana de bajada del autoescalador es de 60 s)"; sleep 75
muestra "kubectl get deployment,hpa -n revisor"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"

titulo "9.6 Con carga, el autoescalador sube"
muestra "kubectl apply -f carga.yaml"
sleep 5
echo "(espera visible: hasta 600 s a que los Pods de carga arranquen; la primera vez descargan la imagen de curl)"
muestra "kubectl wait --for=condition=Ready pod -l app=carga -n revisor --timeout=600s"
printf '\n(un renglón del HPA cada 20 s, durante 200 s; empieza a las %s)\n' "$(CRON)"
seguir_hpa 200 20
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl top pods -n revisor -l app=revisor"
muestra "kubectl get hpa revisor -n revisor -o jsonpath='réplicas={.status.currentReplicas} deseadas={.status.desiredReplicas} cpu={.status.currentMetrics[0].resource.current.averageUtilization} % ({.status.currentMetrics[0].resource.current.averageValue}){\"\\n\"}'"
muestra "kubectl describe hpa revisor -n revisor | sed -n '/Events:/,\$p'"

titulo "9.7 Sin carga, baja, después de la ventana"
muestra "kubectl delete -f carga.yaml"
printf '\n(un renglón del HPA cada 20 s, durante 260 s; empieza a las %s)\n' "$(CRON)"
seguir_hpa 260 20
muestra "kubectl top pods -n revisor -l app=revisor"
muestra "kubectl describe hpa revisor -n revisor | sed -n '/Conditions:/,/Events:/p'"
muestra "kubectl describe hpa revisor -n revisor | sed -n '/Events:/,\$p'"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"

titulo "9.8 Quién manda sobre las réplicas"
muestra "kubectl scale deployment/revisor -n revisor --replicas=1"
echo "(espera de 40 s)"; sleep 40
muestra "kubectl get deployment,hpa -n revisor"
muestra "kubectl describe hpa revisor -n revisor | sed -n '/Events:/,\$p' | tail -3"

titulo "9.9 Actualizar y medir el corte"
k apply -n revisor -f depurar.yaml >/dev/null
muestra "kubectl wait --for=condition=Ready pod/depurar -n revisor --timeout=600s"
muestra "kubectl get pod depurar -n revisor -o wide"
muestra "$PODS"
echo
echo "# --- Sondeo base, 15 s sin tocar nada: 4 hilos, sin pausa ---"
muestra "./sondeo.sh 15 0 4"
echo
echo "# --- A. Rollout 1.6.0 -> 1.6.1 CON preStop (como está en la carpeta) ---"
printf '\n$ ./sondeo.sh 45 0 4 &   # empieza a las %s\n' "$(CRON)"
./sondeo.sh 45 0 4 > "$TEMPORAL/sondeo-a.txt" 2>&1 &
SONDEO=$!
echo "(pausa de 3 s: que el sondeo ya esté corriendo)"; sleep 3
muestra "kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:1.6.1"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
wait "$SONDEO" || true
printf '\n# resultado del sondeo (A, con preStop):\n'; cat "$TEMPORAL/sondeo-a.txt"
muestra "kubectl exec -n revisor depurar -- curl -s http://revisor/salud"
echo
echo "# --- B. El mismo rollout, de ida y vuelta, SIN preStop (se quita con un patch) ---"
muestra "kubectl patch deployment/revisor -n revisor --type=json -p '[{\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/0/lifecycle\"}]'"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
sleep 8
muestra "kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].lifecycle}{\"|\"}{.spec.template.spec.terminationGracePeriodSeconds}{\"\\n\"}'"
for ronda in 1 2 3; do
  if [ $((ronda % 2)) = 1 ]; then NUEVA=1.6.0; else NUEVA=1.6.1; fi
  printf '\n$ ./sondeo.sh 45 0 4 &   # ronda %s, empieza a las %s\n' "$ronda" "$(CRON)"
  ./sondeo.sh 45 0 4 > "$TEMPORAL/sondeo-b$ronda.txt" 2>&1 &
  SONDEO=$!
  sleep 3
  muestra "kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:$NUEVA"
  muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
  wait "$SONDEO" || true
  printf '\n# resultado del sondeo (B, ronda %s, sin preStop, hacia %s):\n' "$ronda" "$NUEVA"; cat "$TEMPORAL/sondeo-b$ronda.txt"
done
echo
echo "# --- C. Se vuelve a aplicar la carpeta: el preStop regresa ---"
muestra "kubectl apply -k . | grep -E 'deployment|horizontal'"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
for ronda in 1 2 3; do
  if [ $((ronda % 2)) = 1 ]; then NUEVA=1.6.1; else NUEVA=1.6.0; fi
  printf '\n$ ./sondeo.sh 45 0 4 &   # ronda %s, empieza a las %s\n' "$ronda" "$(CRON)"
  ./sondeo.sh 45 0 4 > "$TEMPORAL/sondeo-c$ronda.txt" 2>&1 &
  SONDEO=$!
  sleep 3
  muestra "kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:$NUEVA"
  muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
  wait "$SONDEO" || true
  printf '\n# resultado del sondeo (C, ronda %s, con preStop, hacia %s):\n' "$ronda" "$NUEVA"; cat "$TEMPORAL/sondeo-c$ronda.txt"
done

titulo "9.10 Historial y rollout undo"
muestra "kubectl annotate deployment/revisor -n revisor kubernetes.io/change-cause='ronda de pruebas de la Leccion 9' --overwrite"
muestra "kubectl rollout history deployment/revisor -n revisor"
muestra "kubectl get replicasets -n revisor -l app=revisor"
VIEJA="$(k get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].image}')"
echo "(imagen actual: $VIEJA)"
muestra "kubectl rollout undo deployment/revisor -n revisor"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
muestra "$PODS"
muestra "kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'"
echo "(espera de 12 s: que termine el preStop de los Pods viejos)"; sleep 12
muestra "$PODS"
muestra "kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'"
muestra "kubectl rollout history deployment/revisor -n revisor --revision=1 | head -14"
muestra "kubectl apply -k . | grep -E 'deployment'"

titulo "9.11 PDB y mantenimiento de un nodo"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
echo "(espera de 20 s)"; sleep 20
muestra "$PODS"
muestra "kubectl get pdb revisor -n revisor"
echo
echo "# --- El error: un PDB que no deja perder ninguna réplica ---"
muestra "kubectl apply -n revisor -f fig09_01.pdb-estricto.yaml"
muestra "kubectl get pdb revisor -n revisor"
k delete -n revisor pod depurar --wait=true >/dev/null
NODO="$(k get pods -n revisor -l app=revisor -o jsonpath='{.items[0].spec.nodeName}')"
echo "(el nodo que se va a vaciar: $NODO)"
muestra "kubectl drain $NODO --ignore-daemonsets --delete-emptydir-data --timeout=30s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'"
muestra "kubectl get nodes"
muestra "kubectl uncordon $NODO"
echo
echo "# --- La corrección: el PDB de la carpeta ---"
muestra "kubectl apply -k . | grep -E 'poddisruption'"
muestra "kubectl get pdb revisor -n revisor"
muestra "kubectl drain $NODO --ignore-daemonsets --delete-emptydir-data --timeout=120s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl uncordon $NODO"
echo "(espera de 30 s: ¿vuelve el reparto por sí solo?)"; sleep 30
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl rollout restart deployment/revisor -n revisor"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
sleep 8
muestra "kubectl get pods -n revisor -l app=revisor -o wide"

titulo "9.12 Un nodo que se cae"
k apply -n revisor -f depurar.yaml >/dev/null
k wait --for=condition=Ready pod/depurar -n revisor --timeout=600s >/dev/null
SOBREVIVE="$(k get pod depurar -n revisor -o jsonpath='{.spec.nodeName}')"
CAIDO="$(k get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | grep -v -x -- "$SOBREVIVE" | head -1)"
echo "(depurar vive en $SOBREVIVE; el nodo que se apaga es $CAIDO, que sí tiene una réplica)"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
printf '\n$ ./sondeo.sh 100 2 1 &                                     # sin reintentos, empieza a las %s\n' "$(CRON)"
./sondeo.sh 100 2 1 > "$TEMPORAL/caida-a.txt" 2>&1 &
S1=$!
printf '$ ./sondeo.sh 100 2 1 --retry 3 --retry-all-errors &       # con reintentos\n'
./sondeo.sh 100 2 1 --retry 3 --retry-all-errors > "$TEMPORAL/caida-b.txt" 2>&1 &
S2=$!
echo "(pausa de 10 s: ambos sondeos ya corren)"; sleep 10
fuera "docker stop $CAIDO"
INICIO_CAIDA=$(date +%s)
printf '(nodo apagado a las %s)\n' "$(CRON)"
LISTA_DESTINOS="kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{\"\\n\"}{end}'"
echo "(espera de 25 s: el nodo ya no contesta, pero el clúster todavía no lo sabe)"; sleep 25
printf '[+%3ds desde docker stop] ' $(( $(date +%s) - INICIO_CAIDA )); k get nodes --no-headers | awk -v n="$CAIDO" '$1==n{print $1, $2}'
muestra "$LISTA_DESTINOS"
NOTREADY=no
for _ in $(seq 1 30); do
  sleep 3
  estado="$(k get node "$CAIDO" --no-headers | awk '{print $2}')"
  if [ "$estado" = NotReady ]; then
    echo "(el nodo pasó a NotReady a los $(( $(date +%s) - INICIO_CAIDA )) s de docker stop)"; NOTREADY=si; break
  fi
done
[ "$NOTREADY" = si ] || echo "(aviso: el nodo no pasó a NotReady en 90 s)"
muestra "$LISTA_DESTINOS"
wait "$S1" || true; wait "$S2" || true
printf '\n# resultado SIN reintentos (los segundos cuentan desde el inicio del sondeo; docker stop fue en +10):\n'; cat "$TEMPORAL/caida-a.txt"
printf '\n# resultado CON reintentos de curl:\n'; cat "$TEMPORAL/caida-b.txt"
muestra "kubectl get nodes"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
fuera "docker start $CAIDO"
k wait --for=condition=Ready "node/$CAIDO" --timeout=180s >/dev/null
muestra "kubectl get nodes"
sleep 20
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
k delete -n revisor pod depurar --wait=true >/dev/null

titulo "Estado final"
muestra "kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'"
muestra "kubectl get deployment,hpa,pdb -n revisor"

titulo "Borrar el clúster"
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
inicio=$(date +%s)
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
echo "(borrar tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true
echo
echo "# $(disco)"
echo "# la corrida completa tardó $(( $(date +%s) - INICIO_TOTAL )) s"
