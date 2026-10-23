#!/usr/bin/env bash
# correr.sh — Lección 10: todo lo que la lección muestra, de principio a fin.
#
# Crea clústeres de kind llamados curso-k8s-l10 (tres nodos), de uno en uno, y
# recorre la lección: la plataforma aplicada sin --server-side (y por qué falla),
# plataforma y proyecto juntos en un solo comando (y por qué no), el orden bueno
# con sus esperas visibles, la revisión contra «restricted», las pruebas de las
# metas (nodo caído, cambio de configuración, Pod ajeno), los ejercicios y, al
# final, probar-levantar.sh: crear, levantar, borrar, recrear y levantar otra vez.
#
# Necesita Docker, kind, kubectl (Lección 1), openssl, internet (los manifiestos
# de MetalLB, Envoy Gateway y metrics-server se descargan de sus lanzamientos,
# fijados a su versión) y las imágenes curso-docker-revisor:1.6.0 y
# curso-docker-prueba:1.0.0.
#
# Uso:  ./correr.sh > correr.salida.txt 2>&1     (desde esta carpeta)
#
# 🔴 SEGURIDAD Y CONVIVENCIA:
# - le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config no se lee ni
#   se toca) y, antes de cada kubectl, comprueba que el contexto activo es
#   kind-curso-k8s-l10; si no, se detiene;
# - RED PROPIA: esta corrida se hizo en una máquina compartida donde otras
#   lecciones también instalan MetalLB. Para no pisarse, crea su propia red de
#   Docker (curso-k8s-red-l10, 172.30.0.0/16) y el rango de MetalLB va DENTRO de
#   ella. Con la red «kind» de siempre, deja RED_DOCKER=kind (el valor por omisión
#   cuando no usas red propia es el de la sección 10.1) y cambia el rango de
#   overlays/kind/metallb-pool.yaml a 172.18.255.200-172.18.255.250;
# - el guion se detiene antes de crear nada si la red no es la esperada, y borra
#   al final SOLO lo que creó él: sus clústeres curso-k8s-l10 y, después, su red;
# - MetalLB, Envoy Gateway y metrics-server se instalan DENTRO de cada clúster y
#   se van con él. No usa Cloud Provider KIND, que actúa sobre todos los clústeres;
# - antes de CADA clúster espera a que haya menos de 3 clústeres «curso-k8s-*»;
# - solo detiene (docker stop) contenedores cuyo nombre empieza con curso-k8s-l10-.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l10
CONTEXTO="kind-$CLUSTER"
RED_DOCKER="${RED_DOCKER:-curso-k8s-red-l10}"
SUBRED="${SUBRED:-172.30.0.0/16}"
CUPO_MAXIMO=3
IMAGENES=(curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0)
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
RED_CREADA_AQUI=no
TOKEN_CREADO_AQUI=no
L10_TMP=""

limpiar() {
  docker rm -f "$CLUSTER-cliente" >/dev/null 2>&1 || true
  if [ -n "$L10_TMP" ] && kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  if [ "$RED_CREADA_AQUI" = si ]; then
    docker network rm "$RED_DOCKER" >/dev/null 2>&1 || true
  fi
  [ "$TOKEN_CREADO_AQUI" = si ] && rm -f base/token.txt
  case "$L10_TMP" in
    /tmp/curso-k8s-l10.?*) [ -d "$L10_TMP" ] && rm -rf -- "$L10_TMP" ;;
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
  docker image inspect "$imagen" >/dev/null 2>&1 \
    || { echo "ALTO: no encuentro la imagen $imagen en tu Docker. Constrúyela con el curso de Docker." >&2; exit 1; }
done
[ ! -e base/token.txt ] \
  || { echo "ALTO: ya hay un base/token.txt. Este guion genera el suyo y lo borra al terminar; quita el tuyo primero." >&2; exit 1; }

# La red: si no existe, se crea; si existe, tiene que ser la esperada y estar vacía.
if docker network inspect "$RED_DOCKER" >/dev/null 2>&1; then
  ACTUAL="$(docker network inspect "$RED_DOCKER" -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}')"
  USADA="$(docker network inspect "$RED_DOCKER" -f '{{len .Containers}}')"
  [ "$ACTUAL" = "$SUBRED " ] && [ "$USADA" = 0 ] \
    || { echo "ALTO: la red «$RED_DOCKER» existe pero es «$ACTUAL» con $USADA contenedores; no es la esperada ($SUBRED, vacía)." >&2; exit 1; }
elif [ "$RED_DOCKER" = kind ]; then
  : # la red «kind» la crea kind al crear el primer clúster
else
  docker network create --subnet "$SUBRED" "$RED_DOCKER" >/dev/null
  RED_CREADA_AQUI=si
fi

L10_TMP="$(mktemp -d /tmp/curso-k8s-l10.XXXX)"
export KUBECONFIG="$L10_TMP/kubeconfig"
export TMPDIR="$L10_TMP"

# --- Ayudas -----------------------------------------------------------------
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
# código distinto de 0 se anota y NO detiene el guion (hay fallos a propósito).
muestra() {
  contexto_correcto
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# paso "CADENA" → igual, pero si falla el guion SE DETIENE (el camino bueno).
paso() {
  contexto_correcto
  printf '\n$ %s\n' "$*"
  eval "$@" 2>&1
}
# fuera "CADENA" → para comandos que no son kubectl (docker)
fuera() {
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# cliente ARGS → curl desde un contenedor de Docker en la red de los nodos: un
# cliente de verdad, FUERA del clúster. Se borra solo (--rm).
cliente() { docker run --rm --network "$RED_DOCKER" --name "$CLUSTER-cliente" "$CURL_IMAGEN" "$@"; }
desde_fuera() {
  printf '\n$ curl %s\n' "$1"
  local rc=0
  eval "cliente $1" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}

esperar_cupo() {
  until [ "$(kind get clusters 2>/dev/null | grep -c '^curso-k8s-' || true)" -lt "$CUPO_MAXIMO" ]; do
    echo "(espera de cupo: ya hay $CUPO_MAXIMO clústeres de curso; reviso en 60 s)"
    sleep 60
  done
}

# disco → no crea nada mientras el disco de la máquina de Docker pase de 80 %:
# espera (revisa cada 60 s) a que otro carril libere espacio. No borra nada ajeno.
disco() {
  local uso
  while :; do
    uso="$(docker run --rm --entrypoint df "$CURL_IMAGEN" -P /etc/hostname 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')"
    if [ -n "$uso" ] && [ "$uso" -gt 80 ]; then
      echo "(espera de disco: está al ${uso} % y el tope es 80 %; reviso en 60 s)"; sleep 60
    else
      break
    fi
  done
  echo "(disco de Docker: ${uso:-?} %)"
}

# crear_cluster → clúster de tres nodos listo, con las dos imágenes cargadas
crear_cluster() {
  esperar_cupo
  disco
  local t0=$SECONDS
  if [ "$RED_DOCKER" = kind ]; then
    kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$L10_TMP/crear.log" 2>&1 || { cat "$L10_TMP/crear.log" >&2; exit 1; }
  else
    KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED_DOCKER" \
      kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$L10_TMP/crear.log" 2>&1 || { cat "$L10_TMP/crear.log" >&2; exit 1; }
  fi
  contexto_correcto
  kubectl wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
  kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
  kind load docker-image --name "$CLUSTER" "${IMAGENES[@]}" >"$L10_TMP/cargar.log" 2>&1
  echo "(crear el clúster, esperar a los nodos y cargar las imágenes tardó $((SECONDS - t0)) s)"
}
borrar_cluster() {
  local t0=$SECONDS
  kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  echo "(borrar el clúster tardó $((SECONDS - t0)) s)"
}

INICIO=$SECONDS
echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · red de Docker $RED_DOCKER ($SUBRED) · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"

# El token (de mentira) que el Secret generado va a leer. Un Secret no se versiona.
(umask 077; openssl rand -hex 16 > base/token.txt)
TOKEN_CREADO_AQUI=si
TOKEN="$(cat base/token.txt)"

# ============================================================================
titulo "10.1 La red y el cupo"
fuera "docker network inspect $RED_DOCKER -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'"
fuera "kind get clusters | grep -c '^curso-k8s-'"
fuera "/bin/ls -l base/token.txt | cut -d' ' -f1"
fuera "wc -c < base/token.txt"

# ============================================================================
titulo "10.4 Primer error: la plataforma sin --server-side"
crear_cluster
muestra "cat \$L10_TMP/crear.log"
muestra "kubectl get nodes"
muestra "kubectl get crd"
muestra "kubectl apply -k overlays/kind/plataforma > \$L10_TMP/cliente.txt 2>&1; echo \"código: \$?\""
muestra "grep -c ' created\$' \$L10_TMP/cliente.txt"
muestra "grep -v ' created\$' \$L10_TMP/cliente.txt | cut -c1-330"
borrar_cluster

# ============================================================================
titulo "10.4 Segundo error: plataforma y proyecto en un solo comando"
crear_cluster
muestra "kubectl apply --server-side -k fig10_01.todo-junto > \$L10_TMP/junto1.txt 2>&1; echo \"código: \$?\""
muestra "grep -c serverside-applied \$L10_TMP/junto1.txt"
muestra "grep -v serverside-applied \$L10_TMP/junto1.txt | cut -c1-330"
printf '\n# se repite el mismo comando, sin esperar nada entre uno y otro\n'
muestra "kubectl apply --server-side -k fig10_01.todo-junto > \$L10_TMP/junto2.txt 2>&1; echo \"código: \$?\""
muestra "grep -c serverside-applied \$L10_TMP/junto2.txt"
muestra "grep -v serverside-applied \$L10_TMP/junto2.txt | cut -c1-330"
borrar_cluster

# ============================================================================
titulo "10.1 El clúster de la lección"
crear_cluster
muestra "cat \$L10_TMP/crear.log"
muestra "kubectl config current-context"
muestra "kubectl get nodes"
muestra "cat \$L10_TMP/cargar.log"
muestra "for n in control-plane worker worker2; do echo \"-- $CLUSTER-\$n\"; docker exec $CLUSTER-\$n crictl images | grep -E 'IMAGE|curso-docker'; done"
muestra "kubectl get crd"

titulo "10.2 El mapa de la carpeta"
muestra "find base overlays -type f ! -name token.txt | sort"

titulo "10.3 Kustomize: base, overlays y lo que sale"
muestra "kubectl kustomize overlays/kind | grep '^kind:' | sort | uniq -c | sort -rn"
muestra "kubectl kustomize overlays/kind | grep -c '^kind:'"
muestra "diff <(kubectl kustomize overlays/kind) <(kubectl kustomize overlays/ejemplo-nube)"
muestra "kubectl kustomize overlays/kind/plataforma | grep -c '^kind:'"
muestra "kubectl kustomize overlays/kind/plataforma | grep -B1 -A1 'kubelet-insecure-tls'"

titulo "10.5 Levantar a mano: 1. la plataforma"
paso "kubectl apply --server-side -k overlays/kind/plataforma > \$L10_TMP/plataforma.txt; grep -c serverside-applied \$L10_TMP/plataforma.txt"
muestra "head -4 \$L10_TMP/plataforma.txt"
muestra "kubectl get crd | wc -l"
muestra "kubectl get pods -n metallb-system"

titulo "10.5 Levantar a mano: 2. la espera"
SEGUNDOS_ESPERA=$SECONDS
paso "kubectl wait --for=condition=Established --timeout=120s crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io"
paso "kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller"
paso "kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker"
paso "kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway"
paso "kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server"
echo "(la espera tardó $((SECONDS - SEGUNDOS_ESPERA)) s)"
printf '\n# y cuando la condición NO llega: una espera con tope corto sobre algo que no va a pasar\n'
muestra "kubectl wait --for=condition=Available=false --timeout=5s -n envoy-gateway-system deployment/envoy-gateway"

titulo "10.5 Levantar a mano: 3. el proyecto"
paso "kubectl apply --server-side -k overlays/kind"
muestra "kubectl apply --server-side -k overlays/kind 2>&1 | grep -ci warning"
paso "kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba"
if ! paso "kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor"; then
  echo "== DIAGNÓSTICO: el Gateway no llegó a Programmed"
  kubectl describe gateway revisor -n revisor 2>&1 | tail -40
  kubectl get pods -A 2>&1 | grep -v -E 'Running|Completed'
  kubectl get events -A --sort-by=.lastTimestamp 2>&1 | tail -25 | cut -c1-300
  kubectl get svc -n envoy-gateway-system 2>&1
  exit 1
fi
printf '\n# espera (hasta 2 minutos) a que el HPA lea las métricas\n'
for _ in $(seq 1 24); do
  [ -n "$(k get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}' 2>/dev/null)" ] && break
  sleep 5
done
muestra "kubectl get all,pvc,cronjob,hpa,pdb,networkpolicy,gateway,httproute -n revisor"
muestra "kubectl top pods -n revisor"
IP_GW="$(k get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
desde_fuera "-s -m 5 http://$IP_GW/salud"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/api/estados"
desde_fuera "-s -m 5 -H \"Authorization: Bearer \$TOKEN\" 'http://$IP_GW/api/estados?formato=tabla'"

titulo "10.7 Revisión contra restricted"
muestra "kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted"
muestra "kubectl get namespace revisor --show-labels"
muestra "kubectl get pods -n revisor -o jsonpath='{range .items[*]}{.metadata.name}{\" noroot=\"}{.spec.securityContext.runAsNonRoot}{\" seccomp=\"}{.spec.securityContext.seccompProfile.type}{\" priv-esc=\"}{.spec.containers[0].securityContext.allowPrivilegeEscalation}{\" drop=\"}{.spec.containers[0].securityContext.capabilities.drop}{\" ro=\"}{.spec.containers[0].securityContext.readOnlyRootFilesystem}{\" automount=\"}{.spec.automountServiceAccountToken}{\"\\n\"}{end}'"
for ns in envoy-gateway-system metallb-system kube-system; do
  muestra "kubectl label --dry-run=server --overwrite namespace $ns pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300"
done
muestra "kubectl apply -n revisor -f fig10_02.deployment-malo.yaml"
sleep 8
muestra "kubectl get deployment malo -n revisor"
muestra "kubectl get events -n revisor --field-selector reason=FailedCreate -o custom-columns=RAZON:.reason,MENSAJE:.message | cut -c1-400 | head -3"
muestra "kubectl delete -n revisor -f fig10_02.deployment-malo.yaml"

titulo "10.8 Meta 4: cambiar la lista de servicios hace el rollout solo"
muestra "kubectl get replicaset -n revisor -l app=revisor"
muestra "kubectl get configmap -n revisor"
muestra "sed -i.bak 's#http://prueba:9000/ 2s#http://prueba:9000/ 1s#' base/kustomization.yaml; diff base/kustomization.yaml.bak base/kustomization.yaml"
muestra "kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'"
muestra "mv base/kustomization.yaml.bak base/kustomization.yaml && grep REVISOR_SERVICIOS base/kustomization.yaml"
paso "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
muestra "kubectl get replicaset -n revisor -l app=revisor"
muestra "kubectl get configmap -n revisor"
printf '\n# se vuelve a lo que dicen los archivos\n'
muestra "kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'"
paso "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
muestra "kubectl get replicaset -n revisor -l app=revisor"

titulo "10.8 Meta 6: un Pod ajeno no habla con el revisor; la cuenta del revisor no puede nada"
paso "kubectl apply -n revisor -f depurar.yaml -f intruso.yaml"
paso "kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso --timeout=180s"
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud"
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud"
muestra "kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor"
muestra "kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:revisor"
muestra "kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador"
muestra "kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador"

titulo "10.8 Meta 3: se detiene un nodo de trabajo y el servicio sigue respondiendo"
printf '\n# espera (hasta 2 minutos) a que queden solo los dos Pods vigentes del revisor\n'
for _ in $(seq 1 60); do
  [ "$(k get pods -n revisor -l app=revisor --no-headers 2>/dev/null | wc -l | tr -d ' ')" = 2 ] && break
  sleep 2
done
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
NODO_DEPURAR="$(k get pod -n revisor depurar -o jsonpath='{.spec.nodeName}')"
VICTIMA="$(k get nodes -l '!node-role.kubernetes.io/control-plane' -o name | sed 's#node/##' | grep -vx "$NODO_DEPURAR" | head -1)"
case "$VICTIMA" in "$CLUSTER"-*) ;; *) echo "ALTO: la víctima «$VICTIMA» no es un nodo de este clúster." >&2; exit 1 ;; esac
fuera "docker stop $VICTIMA"
printf '\n# una petición cada 2 s durante 90 s, con límite de 2 s cada una (se muestran los cambios)\n'
contexto_correcto
kubectl exec -n revisor depurar -- sh -c 'inicio=$(date +%s); ok=0; mal=0; ant=""; while [ $(( $(date +%s) - inicio )) -lt 90 ]; do t=$(( $(date +%s) - inicio )); if curl -s -m 2 -o /dev/null http://revisor/salud; then r=ok; ok=$((ok+1)); else r=FALLA; mal=$((mal+1)); fi; [ "$r" != "$ant" ] && echo "[+${t}s] $r"; ant=$r; sleep 2; done; echo "bien=$ok mal=$mal"' 2>&1 || true
muestra "kubectl get nodes"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]}{\" listo=\"}{.conditions.ready}{\"\\n\"}{end}'"
fuera "docker start $VICTIMA"
paso "kubectl wait --for=condition=Ready node/$VICTIMA --timeout=180s"
muestra "kubectl get nodes"
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
printf '\n# espera (hasta 3 minutos) a que el contenedor del nodo reiniciado registre su reinicio\n'
for _ in $(seq 1 36); do
  [ "$(k get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | grep -vc '^0$' || true)" -ge 1 ] && break
  sleep 5
done
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name}{\" reinicios=\"}{.status.containerStatuses[0].restartCount}{\" último fin: \"}{.status.containerStatuses[0].lastState.terminated.reason}{\" código \"}{.status.containerStatuses[0].lastState.terminated.exitCode}{\"\\n\"}{end}'"

titulo "10.8 Meta 5: el escalado lee métricas"
muestra "kubectl get hpa -n revisor"
printf '\n# espera (hasta 3 minutos) a que el escalado vuelva a leer métricas\n'
for _ in $(seq 1 36); do
  [ -n "$(k get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}' 2>/dev/null)" ] && break
  sleep 5
done
muestra "kubectl get hpa -n revisor"

titulo "Ejercicio 1: un overlay propio"
muestra "kubectl kustomize fig10_03.overlay-mio | grep -n -E 'maxReplicas|minReplicas'"
muestra "kubectl diff --server-side -k fig10_03.overlay-mio | grep -E '^[+-] +(max|min)Replicas'"
muestra "grep -c maxReplicas base/escalado.yaml"

titulo "Ejercicio 2: de «malo» a «restricted»"
muestra "kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml 2>&1 | grep -ci warning"
muestra "kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml"
paso "kubectl wait -n revisor --for=condition=Available deployment/malo --timeout=120s"
muestra "kubectl get deployment malo -n revisor"
muestra "kubectl delete -n revisor -f fig10_04.deployment-corregido.yaml"
paso "kubectl wait --for=delete pod -l app=malo -n revisor --timeout=120s"

titulo "Ejercicio 3: se detiene el plano de control"
muestra "kubectl get servicel2statuses -n metallb-system"
POD_REVISOR="$(k get pods -n revisor -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
POD_IP="$(k get pod -n revisor "$POD_REVISOR" -o jsonpath='{.status.podIP}')"
POD_NODO="$(k get pod -n revisor "$POD_REVISOR" -o jsonpath='{.spec.nodeName}')"
case "$POD_NODO" in "$CLUSTER"-*) ;; *) echo "ALTO: nodo «$POD_NODO» ajeno" >&2; exit 1 ;; esac
printf '\n# el Pod %s vive en %s con la IP %s\n' "$POD_REVISOR" "$POD_NODO" "$POD_IP"
fuera "docker stop $CLUSTER-control-plane"
SEG0=$SECONDS
muestra "kubectl get nodes --request-timeout=5s 2>&1 | cut -c1-200"
printf '\n# una petición cada 2 s durante 45 s a la puerta, desde fuera del clúster (se muestran los cambios)\n'
docker run --rm --network "$RED_DOCKER" --name "$CLUSTER-cliente" --entrypoint sh "$CURL_IMAGEN" -c 'inicio=$(date +%s); ok=0; mal=0; ant=""; while [ $(( $(date +%s) - inicio )) -lt 45 ]; do t=$(( $(date +%s) - inicio )); if curl -s -m 2 -o /dev/null http://'"$IP_GW"'/salud; then r=ok; ok=$((ok+1)); else r=FALLA; mal=$((mal+1)); fi; [ "$r" != "$ant" ] && echo "[+${t}s] $r"; ant=$r; sleep 2; done; echo "bien=$ok mal=$mal"' 2>&1 || true
printf '\n# sin API, pero con acceso al nodo: ¿los contenedores siguen corriendo y contestando?\n'
fuera "docker exec $POD_NODO crictl ps | grep -E 'CONTAINER|revisor'"
fuera "docker exec $POD_NODO curl -s -m 3 http://$POD_IP:8080/salud"
fuera "docker start $CLUSTER-control-plane"
for _ in $(seq 1 60); do
  kubectl get nodes --request-timeout=5s >/dev/null 2>&1 && break
  sleep 5
done
echo "(la API volvió a contestar $((SECONDS - SEG0)) s después de detener el nodo de control)"
paso "kubectl wait --for=condition=Ready nodes --all --timeout=240s"
muestra "kubectl get nodes"
muestra "kubectl get servicel2statuses -n metallb-system"
muestra "kubectl get pods -n revisor -o wide"
printf '\n# ¿contesta ya el guardián (webhook) de MetalLB? Una prueba en seco del rango, sin aplicar nada\n'
muestra "kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300"
printf '\n# espera (hasta 3 minutos) a que el guardián de MetalLB conteste\n'
for _ in $(seq 1 36); do
  k apply --dry-run=server -f overlays/kind/metallb-pool.yaml >/dev/null 2>&1 && break
  sleep 5
done
muestra "kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300"

titulo "El proyecto sigue siendo lo que dicen los archivos"
muestra "kubectl delete -n revisor pod depurar intruso --wait=false"
sleep 5
muestra "kubectl diff --server-side -k overlays/kind > /dev/null && echo 'sin diferencias con los archivos'"
echo "(la corrida de la lección, sin contar probar-levantar.sh, tardó $((SECONDS - INICIO)) s)"

titulo "Borrar el clúster"
SEG0=$SECONDS
fuera "kind delete cluster --name $CLUSTER"
echo "(borrar el clúster tardó $((SECONDS - SEG0)) s)"
fuera "kind get clusters | grep -c $CLUSTER"

# ============================================================================
titulo "10.6 probar-levantar.sh: crear, levantar, borrar, recrear y levantar otra vez"
rm -f base/token.txt
TOKEN_CREADO_AQUI=no
RED_DOCKER="$RED_DOCKER" CUPO_MAXIMO="$CUPO_MAXIMO" ./probar-levantar.sh 2>&1
echo "(la corrida completa tardó $((SECONDS - INICIO)) s)"
