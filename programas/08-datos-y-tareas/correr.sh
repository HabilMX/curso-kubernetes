#!/usr/bin/env bash
# correr.sh — Lección 8: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l8 (tres nodos), le carga las dos imágenes
# del curso, le instala la plataforma de la Lección 6 (MetalLB y Envoy Gateway, DENTRO
# del clúster) y aplica el punto de partida (lo que dejó la Lección 7, en el espacio
# revisor). Después recorre la lección: qué se pierde con un emptyDir, el volumen
# persistente y su espera, el Job, el CronJob, el dueño de los archivos con fsGroup,
# borrar y recrear el volumen, los dos errores a propósito, el tamaño que el clúster no
# respeta y los Ejercicios 1 a 3. Al final borra el clúster.
#
# Necesita Docker, kind, kubectl (Lección 1), openssl, internet (los manifiestos de
# MetalLB y Envoy Gateway se descargan de sus lanzamientos, fijados a su versión) y las
# imágenes curso-docker-revisor:1.6.0 y curso-docker-prueba:1.0.0.
#
# Uso, desde esta carpeta:
#   ./correr.sh > mi-corrida.txt 2>&1                       (red «kind» normal)
#   RED_DOCKER=curso-k8s-red-l8 ./correr.sh > ... 2>&1      (red propia, ver abajo)
#
# 🔴 SEGURIDAD Y CONVIVENCIA:
# - le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config no se lee ni se
#   toca) y, antes de cada kubectl, comprueba que el contexto activo es
#   kind-curso-k8s-l8; si no, se detiene;
# - MetalLB y Envoy Gateway se instalan DENTRO de este clúster y se van con él;
# - la red de Docker donde corre el clúster es RED_DOCKER (por omisión «kind», cuya
#   subred debe ser 172.18.0.0/16 y cuyo rango de MetalLB es 172.18.255.200-220). Para
#   correr en paralelo con otro clúster que también use MetalLB, se crea antes una red
#   propia con otra subred y se pasa su nombre:
#     docker network create --subnet 172.28.0.0/16 curso-k8s-red-l8
#   Entonces el rango es 172.28.255.200-250. El guion se DETIENE si la subred de la red
#   no es la esperada, o si alguien ya contesta en la primera IP del rango (otro clúster
#   con MetalLB y el mismo rango: los dos anunciarían las mismas IP y se pisarían);
# - NO crea ni borra redes de Docker: eso lo hace quien lo corre;
# - se detiene si el disco de Docker pasa de 80 %;
# - el cliente «de fuera» es un contenedor curso-k8s-l8-cliente que se borra solo (--rm);
# - al salir —aunque algo falle— borra el clúster que ESTA corrida creó, los token.txt
#   que generó y la carpeta temporal (solo si tiene la forma exacta de la que creó mktemp).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l8
CONTEXTO="kind-$CLUSTER"
IMAGENES=(curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0)
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
RED_DOCKER="${RED_DOCKER:-kind}"
CREADO_AQUI=no
TOKEN_CREADO_AQUI=no
TEMPORAL=""

limpiar() {
  docker rm -f "$CLUSTER-cliente" >/dev/null 2>&1 || true
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  if [ "$TOKEN_CREADO_AQUI" = si ]; then
    rm -f -- token.txt punto-de-partida/token.txt
  fi
  case "$TEMPORAL" in
    /tmp/curso-k8s-l8.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
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
  if ! docker image inspect "$imagen" >/dev/null 2>&1; then
    echo "ALTO: no encuentro la imagen $imagen en tu Docker. Constrúyela con el curso de Docker." >&2
    exit 1
  fi
done
if [ -e token.txt ] || [ -e punto-de-partida/token.txt ]; then
  echo "ALTO: ya hay un token.txt en esta carpeta o en punto-de-partida/. Este guion genera el suyo y lo borra al terminar; quita el tuyo primero." >&2
  exit 1
fi
case "$RED_DOCKER" in
  kind)               SUBRED_ESPERADA=172.18.0.0/16; RANGO=172.18.255.200-172.18.255.220; PRIMERA_IP=172.18.255.200 ;;
  curso-k8s-red-l8)   SUBRED_ESPERADA=172.28.0.0/16; RANGO=172.28.255.200-172.28.255.250; PRIMERA_IP=172.28.255.200 ;;
  *) echo "ALTO: no conozco la red «$RED_DOCKER». Usa «kind» o «curso-k8s-red-l8»." >&2; exit 1 ;;
esac
RED="$(docker network inspect "$RED_DOCKER" -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null || true)"
case " $RED " in
  *" $SUBRED_ESPERADA "*) ;;
  *) echo "ALTO: la red «$RED_DOCKER» de Docker es «$RED», no $SUBRED_ESPERADA. Ajusta el rango de MetalLB o usa otra red." >&2; exit 1 ;;
esac
if docker run --rm --network "$RED_DOCKER" --name "$CLUSTER-cliente" "$CURL_IMAGEN" -s -o /dev/null -m 3 "http://$PRIMERA_IP/" >/dev/null 2>&1; then
  echo "ALTO: alguien ya contesta en $PRIMERA_IP (¿otro clúster con MetalLB y el mismo rango?). Espera a que termine." >&2
  exit 1
fi
USO="$(docker run --rm --entrypoint df "$CURL_IMAGEN" -P /etc/hostname 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')"
if [ -n "$USO" ] && [ "$USO" -gt 80 ]; then
  echo "ALTO: el disco de Docker está al ${USO} % (más de 80 %). No sigo." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l8.XXXX)"
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
# k ARGS → comprueba el contexto y corre kubectl sin mostrar el comando
k() { contexto_correcto; kubectl "$@"; }
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
# oculta "CADENA" → como muestra, pero cambia el token por «…» en lo impreso
oculta() {
  contexto_correcto
  printf '\n$ %s\n' "${1//$TOKEN/…}"
  local rc=0 salida
  salida="$(eval "$1" 2>&1)" || rc=$?
  printf '%s\n' "${salida//$TOKEN/…}"
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# cliente ARGS → curl desde un contenedor de Docker en la red del clúster: un cliente
# de verdad, FUERA del clúster. Se borra solo (--rm).
cliente() { docker run --rm --network "$RED_DOCKER" --name "$CLUSTER-cliente" "$CURL_IMAGEN" "$@"; }
desde_fuera() {
  printf '\n$ curl %s   # desde fuera del clúster\n' "$1"
  local rc=0
  eval "cliente $1" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# esperar_codigo URL CODIGO → espera (hasta 60 s) a que la puerta conteste CODIGO
esperar_codigo() {
  local c=""
  for _ in $(seq 1 60); do
    c="$(cliente -s -o /dev/null -m 3 -w '%{http_code}' "$1" 2>/dev/null || true)"
    [ "$c" = "$2" ] && return 0
    sleep 1
  done
  echo "(aviso: $1 no contestó $2 en 60 s; contestó «$c»)"
}
# esperar_jobs PREFIJO N SEGUNDOS → espera, mostrando cada 10 s lo que va pasando, a que
# haya N Jobs con ese prefijo terminados con éxito (los crea el CronJob solo)
esperar_jobs() {
  local prefijo="$1" n="$2" tope="$3" t=0 hechos=0
  printf '\n(esperando hasta %s s a que el CronJob cree y termine %s Job(s) «%s…»; se mira cada 10 s)\n' "$tope" "$n" "$prefijo"
  while [ "$t" -lt "$tope" ]; do
    hechos="$(k get jobs -n revisor -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.succeeded}{"\n"}{end}' | awk -v p="$prefijo" 'index($1,p)==1 && $2==1' | wc -l | tr -d ' ')"
    printf '  +%3s s: %s Job(s) terminados\n' "$t" "$hechos"
    [ "$hechos" -ge "$n" ] && return 0
    sleep 10; t=$((t + 10))
  done
  echo "(aviso: no se llegó a $n Job(s) en $tope s)"
}
disco() {
  docker run --rm --entrypoint df "$CURL_IMAGEN" -h /etc/hostname 2>/dev/null | awk 'NR==2{print "disco de Docker: " $5 " usado"}'
}

INICIO_TOTAL=$(date +%s)
echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · red $RED_DOCKER ($RED) · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"
echo "# $(disco)"

# =============================================================================
titulo "8.1 El clúster de la lección"
printf '\n$ KIND_EXPERIMENTAL_DOCKER_NETWORK=%s kind create cluster --name %s --config kind-curso.yaml\n' "$RED_DOCKER" "$CLUSTER"
inicio=$(date +%s)
if ! KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED_DOCKER" kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear.log" 2>&1; then
  echo "FALLÓ kind create cluster:"; cat "$TEMPORAL/crear.log"; exit 1
fi
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
echo "(crear el clúster y esperar a que estuviera listo tardó $(( $(date +%s) - inicio )) s)"
muestra "kubectl config current-context"
muestra "kubectl get nodes"
printf '\n$ kind load docker-image %s --name %s\n' "${IMAGENES[*]}" "$CLUSTER"
kind load docker-image "${IMAGENES[@]}" --name "$CLUSTER" 2>&1

titulo "8.1.2 La plataforma de la Lección 6, en tres pasos"
inicio=$(date +%s)
muestra "kubectl apply -k infra/metallb | tail -2"
muestra "kubectl apply --server-side -k infra/envoy-gateway | tail -1"
muestra "kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
muestra "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
muestra "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"
# El rango sale de infra/metallb-pool.yaml (172.18.255.200-220, la red «kind»); con una
# red propia se cambia con sed antes de aplicarlo.
if [ "$RED_DOCKER" = kind ]; then
  muestra "kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml"
else
  muestra "sed 's#172.18.255.200-172.18.255.220#$RANGO#' infra/metallb-pool.yaml | kubectl apply -f - && kubectl apply -f infra/gatewayclass.yaml"
fi
muestra "kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s | tail -1"
k wait --for=condition=Accepted gatewayclass/eg --timeout=120s >/dev/null
echo "(la plataforma tardó $(( $(date +%s) - inicio )) s)"

titulo "8.1.3 El punto de partida: la Lección 7, en el espacio revisor"
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
TOKEN_CREADO_AQUI=si
cp punto-de-partida/token.txt token.txt
TOKEN="$(cat token.txt)"
printf '\n$ (umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)\n$ cp punto-de-partida/token.txt token.txt\n'
muestra "ls -l token.txt punto-de-partida/token.txt | awk '{print \$1, \$NF}'"
muestra "kubectl apply -k punto-de-partida"
k rollout status deployment/revisor -n revisor --timeout=180s >/dev/null
k rollout status deployment/prueba -n revisor --timeout=180s >/dev/null
muestra "kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s"
muestra "kubectl apply -n revisor -f depurar.yaml"
k wait -n revisor --for=condition=Ready pod/depurar --timeout=180s >/dev/null
muestra "kubectl get pods -n revisor -o wide"
muestra "kubectl get pvc,cronjob,job -n revisor"
IP_GW="$(k get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
esperar_codigo "http://$IP_GW/salud" 200
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo

# =============================================================================
titulo "8.2 Qué se pierde: el emptyDir de hoy"
oculta "kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid"
mapfile -t FILAS < <(k get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName} {.metadata.uid}{"\n"}{end}')
POD_CON="" ; NODO_CON="" ; UID_CON=""
for fila in "${FILAS[@]}"; do
  set -- $fila
  ruta="/var/lib/kubelet/pods/$3/volumes/kubernetes.io~empty-dir/datos"
  muestra "docker exec $2 ls -lan $ruta"
  if docker exec "$2" test -f "$ruta/reporte.json"; then POD_CON="$1"; NODO_CON="$2"; UID_CON="$3"; fi
done
RUTA_CON="/var/lib/kubelet/pods/$UID_CON/volumes/kubernetes.io~empty-dir/datos"
echo
echo "(el Pod que atendió la petición fue $POD_CON, en el nodo $NODO_CON)"
muestra "docker exec $NODO_CON stat -c '%a %U:%g %n' $RUTA_CON"
muestra "docker exec $NODO_CON cat $RUTA_CON/reporte.json"

titulo "8.2.2 Un contenedor que se cae: el emptyDir sobrevive"
CID="$(docker exec "$NODO_CON" crictl ps --label "io.kubernetes.pod.uid=$UID_CON" --name revisor -q)"
muestra "docker exec $NODO_CON crictl stop $CID"
printf '\n(esperando 10 s a que el kubelet reinicie el contenedor)\n'
sleep 10
muestra "kubectl get pod -n revisor $POD_CON"
muestra "kubectl get pod -n revisor $POD_CON -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} {.status.containerStatuses[0].lastState.terminated.exitCode}{\"\\n\"}'"
muestra "docker exec $NODO_CON ls -lan $RUTA_CON"

titulo "8.2.3 Un Pod que se borra: el emptyDir se va con él"
muestra "kubectl delete pod -n revisor $POD_CON"
muestra "docker exec $NODO_CON ls $RUTA_CON"
muestra "docker exec $NODO_CON ls /var/lib/kubelet/pods/$UID_CON"
k rollout status deployment/revisor -n revisor --timeout=180s >/dev/null
muestra "kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid,LISTO:.status.containerStatuses[0].ready"

# =============================================================================
titulo "8.3 Volúmenes, solicitudes y clases"
muestra "kubectl api-resources --api-group='' --namespaced=false -o name | grep -E '^(persistentvolumes|nodes|namespaces)\$'"
muestra "kubectl get storageclass"
muestra "kubectl get storageclass standard -o jsonpath='{.provisioner} {.reclaimPolicy} {.volumeBindingMode} {.allowVolumeExpansion}{\"\\n\"}'"
muestra "kubectl get pods -n local-path-storage"
muestra "kubectl get pv"

titulo "8.4 La solicitud de volumen y su espera"
muestra "kubectl diff -k . | grep -E '^\\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'"
muestra "kubectl apply -k ."
muestra "kubectl get pvc,cronjob -n revisor"
muestra "kubectl describe pvc reportes -n revisor | sed -n '/^Events:/,\$p'"
muestra "kubectl get pv"

# =============================================================================
titulo "8.5 Job: la tarea que termina"
muestra "kubectl apply -f fig08_01.job-salud.yaml"
k wait -n revisor --for=condition=Complete job/salud --timeout=180s >/dev/null
muestra "kubectl get job,pods -n revisor -l app=salud"
muestra "kubectl logs -n revisor job/salud"
muestra "kubectl get job -n revisor salud -o jsonpath='{range .status.conditions[*]}{.type} {.status}{\"\\n\"}{end}'"
muestra "kubectl delete -f fig08_01.job-salud.yaml"

titulo "8.5.2 El reporte guardado: la primera tarea"
muestra "kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1"
sleep 3
muestra "kubectl get pods -n revisor -l app=reporte -o wide"
muestra "kubectl describe pvc reportes -n revisor | sed -n '/^Used By:/,\$p'"
k wait -n revisor --for=condition=Complete job/reporte-manual-1 --timeout=180s >/dev/null
muestra "kubectl logs -n revisor job/reporte-manual-1"
muestra "kubectl get pvc -n revisor"
muestra "kubectl get pv -o custom-columns=NOMBRE:.metadata.name,CLASE:.spec.storageClassName,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],RUTA:.spec.hostPath.path"
RUTA_PV="$(k get pv -o jsonpath='{.items[0].spec.hostPath.path}')"
NODO_PV="$(k get pv -o jsonpath='{.items[0].spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}')"
muestra "docker exec $NODO_PV stat -c '%a %u:%g %n' $RUTA_PV"
muestra "docker exec $NODO_PV ls -lan $RUTA_PV"

titulo "8.5.3 El Pod de la tarea terminó; el archivo sigue ahí"
muestra "kubectl get pods -n revisor -l app=reporte"
sleep 2
muestra "kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2"
k wait -n revisor --for=condition=Complete job/reporte-manual-2 --timeout=180s >/dev/null
muestra "kubectl logs -n revisor job/reporte-manual-2"
muestra "kubectl get jobs -n revisor"
oculta "kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
muestra "docker exec $NODO_PV sh -c 'cat $RUTA_PV/reporte-*.json | head -9'"

# =============================================================================
titulo "8.6 CronJob: la tarea con horario"
muestra "kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.schedule}{\" \"}{.spec.concurrencyPolicy}{\" \"}{.spec.successfulJobsHistoryLimit}{\" \"}{.spec.failedJobsHistoryLimit}{\" \"}{.spec.timeZone}{\"\\n\"}'"
muestra "kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[1].secret.secretName}{\"\\n\"}'"
muestra "kubectl get secret -n revisor -o name"
muestra "date -u +%H:%M:%S"
muestra "kubectl get cronjob reporte -n revisor"
muestra "kubectl apply -f fig08_03.cron-cada-minuto.yaml"
esperar_jobs salud-cada-minuto 2 200
muestra "kubectl get cronjob,jobs -n revisor"
muestra "kubectl logs -n revisor -l app=salud --prefix --tail=3"
muestra "kubectl get job -n revisor -l app=salud -o custom-columns=NOMBRE:.metadata.name,PROGRAMADA:.metadata.annotations.batch\\\\.kubernetes\\\\.io/cronjob-scheduled-timestamp"
muestra "kubectl delete -f fig08_03.cron-cada-minuto.yaml"
muestra "kubectl get jobs,pods -n revisor -l app=salud"

# =============================================================================
titulo "8.7 El dueño de los archivos: fsGroup"
muestra "kubectl get pod -n revisor -l app=revisor -o jsonpath='{.items[0].spec.securityContext.fsGroup}{\"\\n\"}'"
muestra "kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.securityContext}{\"\\n\"}'"
echo
echo "(el directorio de emptyDir de 8.2 y el del volumen de 8.5, uno junto al otro:)"
echo "(emptyDir:  $(docker exec "$NODO_CON" stat -c '%a %u:%g' "$RUTA_CON" 2>/dev/null || echo 'ya no existe, ese Pod se borró'))"
echo "(PVC local-path: $(docker exec "$NODO_PV" stat -c '%a %u:%g' "$RUTA_PV"))"
NODO_NUEVO="$(k get pods -n revisor -l app=revisor -o jsonpath='{.items[0].spec.nodeName}')"
UID_NUEVO="$(k get pods -n revisor -l app=revisor -o jsonpath='{.items[0].metadata.uid}')"
muestra "docker exec $NODO_NUEVO stat -c '%a %u:%g %n' /var/lib/kubelet/pods/$UID_NUEVO/volumes/kubernetes.io~empty-dir/datos"

titulo "8.7.2 Un disco como los de verdad"
muestra "docker exec $CLUSTER-worker mkdir -p /mnt/disco-reportes"
muestra "docker exec $CLUSTER-worker stat -c '%a %u:%g %n' /mnt/disco-reportes"
muestra "kubectl apply -f fig08_04.disco-local.yaml"
muestra "kubectl get pv,pvc -n revisor"
muestra "kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml"
k wait -n revisor --for=jsonpath='{.status.phase}'=Failed pod/sin-fsgroup --timeout=120s >/dev/null
muestra "kubectl get pod -n revisor sin-fsgroup"
muestra "kubectl logs -n revisor sin-fsgroup"
muestra "kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml"
muestra "kubectl apply -f fig08_06.escritor-con-fsgroup.yaml"
k wait -n revisor --for=jsonpath='{.status.phase}'=Succeeded pod/con-fsgroup --timeout=120s >/dev/null
muestra "kubectl get pod -n revisor con-fsgroup"
muestra "kubectl logs -n revisor con-fsgroup"
muestra "docker exec $CLUSTER-worker stat -c '%a %u:%g %n' /mnt/disco-reportes"
muestra "kubectl delete -f fig08_06.escritor-con-fsgroup.yaml"
muestra "kubectl delete pvc -n revisor disco"
sleep 3
muestra "kubectl get pv"
muestra "kubectl delete pv disco-reportes"
muestra "docker exec $CLUSTER-worker ls -ln /mnt/disco-reportes"

# =============================================================================
titulo "8.8 Borrar la solicitud: ahí sí se pierde"
muestra "kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{\"\\n\"}'"
printf '\n$ kubectl delete pvc -n revisor reportes --wait=false\n'
k delete pvc -n revisor reportes --wait=false 2>&1
sleep 5
muestra "kubectl get pvc -n revisor"
muestra "kubectl get pvc -n revisor reportes -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}{\"\\n\"}'"
muestra "kubectl get pods -n revisor -l app=reporte"
muestra "kubectl delete jobs -n revisor --all"
sleep 8
muestra "kubectl get pvc,pv"
muestra "docker exec $NODO_PV ls -la /var/local-path-provisioner/"
muestra "kubectl apply -k . | grep persistentvolumeclaim"
muestra "kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3"
k wait -n revisor --for=condition=Complete job/reporte-manual-3 --timeout=180s >/dev/null
muestra "kubectl logs -n revisor job/reporte-manual-3"
RUTA_PV="$(k get pv -o jsonpath='{.items[0].spec.hostPath.path}')"
NODO_PV="$(k get pv -o jsonpath='{.items[0].spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}')"

# =============================================================================
titulo "El error 1: un Job sin la etiqueta de la red"
muestra "kubectl apply -f fig08_02.job-sin-etiqueta.yaml"
printf '\n(esperando hasta 150 s a que el Job agote sus reintentos; se mira cada 15 s)\n'
t=0
while [ "$t" -lt 150 ]; do
  sleep 15; t=$((t + 15))
  estado="$(k get job -n revisor salud-sin-etiqueta -o jsonpath='{.status.failed} fallidos, {.status.active} activos, condiciones: {range .status.conditions[*]}{.type}={.status} {end}' 2>&1)"
  printf '  +%3s s: %s\n' "$t" "$estado"
  case "$estado" in *Failed=True*) break ;; esac
done
muestra "kubectl get job,pods -n revisor -l app=salud"
muestra "kubectl logs -n revisor job/salud-sin-etiqueta"
muestra "kubectl get pods -n revisor -l app=salud -o custom-columns=POD:.metadata.name,CODIGO:.status.containerStatuses[0].state.terminated.exitCode,RAZON:.status.containerStatuses[0].state.terminated.reason"
muestra "kubectl get job -n revisor salud-sin-etiqueta -o jsonpath='{range .status.conditions[*]}{.type} {.status} {.reason}: {.message}{\"\\n\"}{end}'"
muestra "kubectl describe job -n revisor salud-sin-etiqueta | sed -n '/^Events:/,\$p'"
muestra "kubectl get pod depurar -n revisor --show-labels"
muestra "kubectl delete -f fig08_02.job-sin-etiqueta.yaml"

# =============================================================================
titulo "Hábito de seguridad: los datos con su dueño"
muestra "kubectl get serviceaccount reporte -n revisor -o jsonpath='{.automountServiceAccountToken}{\"\\n\"}'"
muestra "kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.automountServiceAccountToken}{\" \"}{.spec.jobTemplate.spec.template.spec.containers[0].env}{\"\\n\"}'"
muestra "kubectl get pods -n revisor -l app=reporte -o custom-columns=POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name"
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\\n' http://revisor/api/estados"

titulo "El tamaño pedido: 100Mi contra 150 MB"
muestra "kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{\"\\n\"}'"
muestra "kubectl apply -f fig08_07.llenar-el-volumen.yaml"
k wait -n revisor --for=condition=Complete job/llenar --timeout=180s >/dev/null
muestra "kubectl logs -n revisor job/llenar"
muestra "kubectl delete -f fig08_07.llenar-el-volumen.yaml"
muestra "docker exec $NODO_PV df -h /var/local-path-provisioner | tail -1"

# =============================================================================
titulo "Ejercicio 1: una clase de almacenamiento que no existe"
muestra "kubectl apply -f fig08_08.pvc-clase-inexistente.yaml"
sleep 12
muestra "kubectl get pvc rapido -n revisor"
muestra "kubectl get pod lector -n revisor"
muestra "kubectl describe pvc rapido -n revisor | sed -n '/^Events:/,\$p'"
muestra "kubectl describe pod lector -n revisor | sed -n '/^Events:/,\$p'"
muestra "kubectl delete -f fig08_08.pvc-clase-inexistente.yaml"

titulo "Ejercicio 2: el reporte del revisor, en el PVC"
muestra "kubectl config current-context"
muestra "kubectl patch deployment revisor -n revisor --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/volumes/0\",\"value\":{\"name\":\"datos\",\"persistentVolumeClaim\":{\"claimName\":\"reportes\"}}}]'"
k rollout status deployment/revisor -n revisor --timeout=180s >/dev/null
sleep 5
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl get pv -o custom-columns=NOMBRE:.metadata.name,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]"
oculta "kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
muestra "docker exec $NODO_PV ls -lan $RUTA_PV"
muestra "kubectl apply -k . | grep -E 'deployment|persistentvolumeclaim'"
k rollout status deployment/revisor -n revisor --timeout=180s >/dev/null
muestra "kubectl get pods -n revisor -l app=revisor -o wide"

titulo "Ejercicio 3: una tarea que tarda más que su horario"
# Se espera al inicio del minuto para que el primer horario caiga justo al aplicar.
sleep $(( 60 - 10#$(date +%S) ))
muestra "kubectl apply -f fig08_09.cron-lento.yaml"
printf '\n(esperando 210 s para ver pasar tres horarios y el final del primer Job; se mira cada 35 s)\n'
for _ in 1 2 3 4 5 6; do
  sleep 35
  printf '\n$ date -u +%%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E \047NAME|lento\047\n'
  date -u +%T
  k get cronjob lento -n revisor 2>&1
  k get jobs -n revisor 2>&1 | grep -E 'NAME|lento'
done
muestra "kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,\$p'"
muestra "kubectl delete -f fig08_09.cron-lento.yaml"

for politica in Allow Replace; do
  titulo "Ejercicio 3, variante: la misma tarea con concurrencyPolicy: $politica"
  sleep $(( 60 - 10#$(date +%S) ))
  muestra "sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: $politica/' fig08_09.cron-lento.yaml | kubectl apply -f -"
  muestra "kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{\"\\n\"}'"
  printf '\n(esperando 140 s con %s; se mira cada 35 s)\n' "$politica"
  for _ in 1 2 3 4; do
    sleep 35
    printf '\n$ date -u +%%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E \047NAME|lento\047; kubectl get pods -n revisor -l app=lento\n'
    date -u +%T
    k get cronjob lento -n revisor 2>&1
    k get jobs -n revisor 2>&1 | grep -E 'NAME|lento'
    k get pods -n revisor -l app=lento 2>&1
  done
  muestra "kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,\$p'"
  muestra "kubectl delete cronjob lento -n revisor"
  k wait --for=delete pod -n revisor -l app=lento --timeout=120s >/dev/null 2>&1 || true
done

titulo "Lección 0, §0.2.5: las tolerancias que Kubernetes agrega solo"
muestra "kubectl get pod -n revisor -l app=revisor -o jsonpath='{.items[0].spec.tolerations}{\"\\n\"}'"

# =============================================================================
titulo "Cómo sé que lo logré: el estado final"
k delete pod -n revisor depurar --wait=false >/dev/null
muestra "kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'"
muestra "kubectl get pvc,cronjob -n revisor"
muestra "kubectl get jobs -n revisor"
muestra "kubectl get pods -n revisor"
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo

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
