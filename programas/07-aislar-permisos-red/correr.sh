#!/usr/bin/env bash
# correr.sh — Lección 7: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l7 (tres nodos), le carga las dos
# imágenes del curso, le instala la plataforma de la Lección 6 (MetalLB y Envoy
# Gateway, DENTRO del clúster) y aplica el punto de partida (lo que dejó la
# Lección 6, en el espacio default). Después recorre la lección: la mudanza al
# espacio revisor, Pod Security Admission, las cuentas de servicio y RBAC con
# auth can-i, y la red: sin reglas, con todo cerrado y con las aperturas, una por
# una. Provoca los dos errores, corre los Ejercicios 1 a 3 y borra el clúster.
#
# Necesita Docker, kind, kubectl (Lección 1), openssl, internet (los manifiestos
# de MetalLB y Envoy Gateway se descargan de sus lanzamientos, fijados a su
# versión) y las imágenes curso-docker-revisor:1.6.0 y curso-docker-prueba:1.0.0.
#
# Uso:  ./correr.sh > /tmp/mi-corrida-l7.txt 2>&1     (desde esta carpeta)
#
# RED DE DOCKER. Por omisión usa la red «kind» (172.18.0.0/16) y el rango de
# MetalLB de infra/metallb-pool.yaml. Si en tu máquina corren otros clústeres con
# MetalLB a la vez, dale al tuyo una red propia, creada ANTES por ti:
#   docker network create --subnet 172.27.0.0/16 curso-k8s-red-l7
#   CURSO_RED=curso-k8s-red-l7 CURSO_SUBRED=172.27.0.0/16 ./correr.sh > …
# El guion NO crea ni borra redes: comprueba que la red exista y que su subred sea
# exactamente la que dices, y si no, se detiene antes de crear nada. Con una red
# propia, el rango de MetalLB pasa a PREFIJO.255.200-PREFIJO.255.250.
#
# 🔴 SEGURIDAD Y CONVIVENCIA:
# - le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config no se lee ni
#   se toca) y, antes de cada kubectl, comprueba que el contexto activo es
#   kind-curso-k8s-l7; si no, se detiene;
# - MetalLB y Envoy Gateway se instalan DENTRO de este clúster y se van con él;
# - se detiene antes de crear nada si la red no es la esperada, si alguien ya
#   contesta en PREFIJO.255.200 (otro clúster con MetalLB y el mismo rango) o si ya
#   hay tres clústeres de curso;
# - el cliente «de fuera» es un contenedor curso-k8s-l7-cliente en esa red, que
#   se borra solo (--rm);
# - el port-forward que abre lo cierra por su PID, y solo ese;
# - al salir —aunque algo falle— borra el clúster que ESTA corrida creó, los
#   token.txt que generó y la carpeta temporal (solo si tiene la forma exacta de
#   la que creó mktemp).
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l7
CONTEXTO="kind-$CLUSTER"
IMAGENES=(curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0)
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
RED="${CURSO_RED:-kind}"
SUBRED="${CURSO_SUBRED:-172.18.0.0/16}"
PREF="${SUBRED%.0.0/16}"
CREADO_AQUI=no
TOKEN_CREADO_AQUI=no
TEMPORAL=""
PF=""

limpiar() {
  [ -n "$PF" ] && kill "$PF" 2>/dev/null || true
  docker rm -f "$CLUSTER-cliente" >/dev/null 2>&1 || true
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  if [ "$TOKEN_CREADO_AQUI" = si ]; then
    rm -f -- token.txt punto-de-partida/token.txt
  fi
  case "$TEMPORAL" in
    /tmp/curso-k8s-l7.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
  esac
  return 0
}
trap limpiar EXIT

# --- Comprobaciones antes de crear nada -------------------------------------
if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster de kind llamado «$CLUSTER». Bórralo tú si es tuyo; este guion no lo toca." >&2
  exit 1
fi
OTROS="$(kind get clusters 2>/dev/null | grep -c '^curso-k8s-l' || true)"
if [ "$OTROS" -ge 3 ]; then
  echo "ALTO: ya hay $OTROS clústeres de curso vivos (el tope es 3 a la vez). Espera a que baje." >&2
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
# verificar_red: la red de Docker existe y su subred es EXACTAMENTE la esperada.
verificar_red() {
  local real
  real="$(docker network inspect "$RED" -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null || true)"
  case " $real " in
    *" $SUBRED "*) ;;
    *) echo "ALTO: la red de Docker «$RED» es «$real», no $SUBRED. Ajusta CURSO_RED/CURSO_SUBRED y infra/metallb-pool.yaml." >&2; exit 1 ;;
  esac
}
if docker network inspect "$RED" >/dev/null 2>&1; then
  verificar_red
elif [ "$RED" != kind ]; then
  echo "ALTO: la red «$RED» no existe. Créala tú antes: docker network create --subnet $SUBRED $RED" >&2
  exit 1
fi   # (la red «kind» nace con el primer clúster; se verifica después de crearlo)
if [ "$RED" != kind ]; then
  export KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED"
  if docker run --rm --network "$RED" --name "$CLUSTER-cliente" "$CURL_IMAGEN" -s -o /dev/null -m 3 "http://$PREF.255.200/" >/dev/null 2>&1; then
    echo "ALTO: alguien ya contesta en $PREF.255.200 (¿otro clúster con MetalLB y el mismo rango?)." >&2
    exit 1
  fi
elif docker network inspect kind >/dev/null 2>&1; then
  if docker run --rm --network kind --name "$CLUSTER-cliente" "$CURL_IMAGEN" -s -o /dev/null -m 3 "http://$PREF.255.200/" >/dev/null 2>&1; then
    echo "ALTO: alguien ya contesta en $PREF.255.200 (¿otro clúster con MetalLB y el mismo rango?). Espera a que termine." >&2
    exit 1
  fi
fi
if lsof -nP -iTCP:18087 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "ALTO: el puerto 18087 de esta máquina ya está ocupado por otro proceso. No sigo." >&2
  exit 1
fi
USO="$(docker run --rm --entrypoint df "$CURL_IMAGEN" -P /etc/hostname 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')"
if [ -n "$USO" ] && [ "$USO" -gt 80 ]; then
  echo "ALTO: el disco de Docker está al ${USO} % (más de 80 %). No sigo." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l7.XXXX)"
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
# espera N → una espera VISIBLE: se imprime y se hace
espera() { printf '\n$ sleep %s\n' "$1"; sleep "$1"; }
# cliente ARGS → curl desde un contenedor de Docker en la red de los nodos: un
# cliente de verdad, FUERA del clúster. Se borra solo (--rm).
cliente() { docker run --rm --network "$RED" --name "$CLUSTER-cliente" "$CURL_IMAGEN" "$@"; }
desde_fuera() {
  printf '\n$ curl %s   # desde fuera del clúster\n' "$1"
  local rc=0
  eval "cliente $1" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
disco() {
  docker run --rm --entrypoint df "$CURL_IMAGEN" -h /etc/hostname 2>/dev/null | awk 'NR==2{print "disco de Docker: " $5 " usado"}'
}
# estado_ruta ESPACIO RUTA → las condiciones de una HTTPRoute, una por línea
estado_ruta() {
  muestra "kubectl get httproute $2 -n $1 -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{\"\\n\"}{end}'"
}
NSL='r=$(timeout 8 nslookup revisor.revisor.svc.cluster.local 2>&1 | grep -E "^Address: [0-9]|timed out" | tail -1); echo "${r:-sin respuesta}"'
# sondeo → los cuatro sondeos de la red, con el comando visible
sondeo() {
  muestra "kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\\n' http://revisor/salud"
  oculta "kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
  muestra "kubectl exec -n revisor depurar -- sh -c '$NSL'"
  desde_fuera "-s -m 4 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/salud"
}

INICIO_TOTAL=$(date +%s)
echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · red de Docker $RED ($SUBRED) · Docker $(docker version --format '{{.Server.Version}}') en $(docker info --format '{{.OperatingSystem}}') ($(uname -m)) · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"
echo "# $(disco)"

# =============================================================================
titulo "7.1 El clúster de la lección"
printf '\n$ kind create cluster --name %s --config kind-curso.yaml\n' "$CLUSTER"
inicio=$(date +%s)
if ! kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear.log" 2>&1; then
  echo "FALLÓ kind create cluster:"; cat "$TEMPORAL/crear.log"
  if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then CREADO_AQUI=si; fi
  exit 1
fi
CREADO_AQUI=si
verificar_red
muestra "kubectl wait --for=condition=Ready nodes --all --timeout=240s"
muestra "kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=240s"
echo "(crear el clúster y esperar a que estuviera listo tardó $(( $(date +%s) - inicio )) s)"
muestra "kubectl config current-context"
muestra "kubectl get nodes -o wide | awk '{print \$1, \$2, \$3, \$6}' | column -t"
printf '\n$ kind load docker-image %s --name %s\n' "${IMAGENES[*]}" "$CLUSTER"
kind load docker-image "${IMAGENES[@]}" --name "$CLUSTER" 2>&1

titulo "7.1.2 La plataforma de la Lección 6, en tres pasos"
inicio=$(date +%s)
muestra "kubectl apply -k infra/metallb | tail -2"
muestra "kubectl apply --server-side -k infra/envoy-gateway | tail -1"
muestra "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
muestra "kubectl rollout status daemonset/speaker -n metallb-system --timeout=480s | tail -1"
muestra "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io crd/referencegrants.gateway.networking.k8s.io --timeout=120s"
muestra "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"
if [ "$PREF" = 172.18 ]; then
  muestra "kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml"
else
  # red propia: el MISMO archivo, con el rango movido a la subred de esta corrida
  printf '\n$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml\n'
  printf '(en esta corrida el rango del archivo se cambió a %s.255.200-%s.255.250, dentro de la red %s)\n' "$PREF" "$PREF" "$RED"
  contexto_correcto
  { sed "s#172\.18\.255\.200-172\.18\.255\.220#$PREF.255.200-$PREF.255.250#" infra/metallb-pool.yaml; echo '---'; cat infra/gatewayclass.yaml; } | kubectl apply -f - 2>&1
fi
muestra "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
echo "(la plataforma tardó $(( $(date +%s) - inicio )) s)"

titulo "7.1.3 El punto de partida: la Lección 6, en default"
printf '\n$ (umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)\n$ cp punto-de-partida/token.txt token.txt\n'
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
TOKEN_CREADO_AQUI=si
cp punto-de-partida/token.txt token.txt
TOKEN="$(cat token.txt)"
muestra "/bin/ls -l token.txt punto-de-partida/token.txt | awk '{print \$1, \$NF}'"
muestra "kubectl apply -k punto-de-partida"
muestra "kubectl rollout status deployment/revisor --timeout=180s"
muestra "kubectl rollout status deployment/prueba --timeout=180s"
muestra "kubectl wait --for=condition=Programmed gateway/revisor --timeout=360s"
muestra "kubectl get namespaces"
muestra "kubectl get namespace default --show-labels"
muestra "kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.serviceAccountName} | {.items[0].spec.automountServiceAccountToken} | {.items[0].spec.volumes[*].name}{\"\\n\"}'"
muestra "kubectl auth can-i --list --as=system:serviceaccount:default:default | head -4"

# =============================================================================
titulo "7.2 Un espacio de nombres propio: la mudanza"
muestra "kubectl api-resources --namespaced=false -o name | grep -E '^(nodes|namespaces|persistentvolumes|storageclasses|clusterroles|clusterrolebindings|gatewayclasses\\.)'"
muestra "kubectl api-resources --namespaced=true -o name | grep -E '^(pods|services|secrets|serviceaccounts|roles|rolebindings|networkpolicies)(\\.|\$)'"
muestra "kubectl delete -k punto-de-partida"
printf '\n$ rm -f -- punto-de-partida/token.txt\n'; rm -f -- punto-de-partida/token.txt
muestra "kubectl apply -k ."
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
muestra "kubectl rollout status deployment/prueba -n revisor --timeout=180s"
muestra "kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s"
muestra "kubectl get namespace revisor -o go-template='{{range \$k, \$v := .metadata.labels}}{{\$k}}={{\$v}}{{\"\\n\"}}{{end}}'"
muestra "kubectl get all -n revisor"
muestra "kubectl get all -n default"
muestra "kubectl get gateway,httproute -n revisor"
muestra "kubectl wait --for=condition=Available deployment -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=revisor --timeout=180s"
muestra "kubectl get pods,services -n envoy-gateway-system"
IP_GW="$(k get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo
printf '\n(las seis reglas de red se retiran para estudiar cada capa por separado; vuelven en 7.5)\n'
muestra "kubectl delete -n revisor -f red.yaml"

# =============================================================================
titulo "7.3 Pod Security Admission"
titulo "7.3.2 Los tres niveles, en dos espacios de prueba"
muestra "kubectl create namespace nivel-privileged"
muestra "kubectl create namespace nivel-baseline"
muestra "kubectl label namespace nivel-privileged pod-security.kubernetes.io/enforce=privileged"
muestra "kubectl label namespace nivel-baseline pod-security.kubernetes.io/enforce=baseline"
muestra "kubectl wait --for=create serviceaccount/default -n nivel-privileged --timeout=60s"
muestra "kubectl wait --for=create serviceaccount/default -n nivel-baseline --timeout=60s"
for n in nivel-privileged nivel-baseline revisor; do
  printf '\n--- espacio %s ---\n' "$n"
  muestra "kubectl run hostnet -n $n --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{\"spec\":{\"hostNetwork\":true}}' -- sleep 5 2>&1 | cut -c1-260"
  muestra "kubectl run sinreglas -n $n --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260"
done
muestra "kubectl delete namespace nivel-privileged nivel-baseline"

titulo "7.3.4 (a) Poner enforce en un espacio que ya tiene Pods"
muestra "kubectl create namespace nivel-previo"
muestra "kubectl wait --for=create serviceaccount/default -n nivel-previo --timeout=60s"
muestra "kubectl run viejo -n nivel-previo --image=$CURL_IMAGEN --restart=Never -- sleep 3600"
muestra "kubectl wait --for=condition=Ready pod/viejo -n nivel-previo --timeout=300s"
muestra "kubectl label namespace nivel-previo pod-security.kubernetes.io/enforce=restricted"
muestra "kubectl get pod viejo -n nivel-previo"
muestra "kubectl run nuevo -n nivel-previo --image=$CURL_IMAGEN --restart=Never -- sleep 3600 2>&1 | cut -c1-200"
muestra "kubectl delete namespace nivel-previo"

titulo "7.3.3 y 7.3.4 (b) El espacio revisor, en restricted"
muestra "kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never -- sleep 60"
muestra "kubectl get pods -n revisor -l run=sinreglas"
muestra "kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted"
muestra "kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted"
muestra "kubectl patch deployment revisor -n revisor --type=json -p '[{\"op\":\"remove\",\"path\":\"/spec/template/spec/securityContext/seccompProfile\"}]' --dry-run=server"
muestra "kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}{\"\\n\"}'"

titulo "El error 1: un Deployment sin Pods"
muestra "kubectl apply -n revisor -f fig07_01.sin-reglas.yaml"
muestra "kubectl wait --for=condition=ReplicaFailure deployment/sinreglas -n revisor --timeout=120s"
muestra "kubectl get deployment sinreglas -n revisor"
muestra "kubectl get replicaset -n revisor -l app=sinreglas"
muestra "kubectl get pods -n revisor -l app=sinreglas"
muestra "kubectl describe replicaset -n revisor -l app=sinreglas | sed -n '/^Events:/,\$p' | head -4"
muestra "kubectl delete -n revisor -f fig07_01.sin-reglas.yaml"

# =============================================================================
titulo "7.4 Cuentas de servicio y permisos mínimos"
muestra "kubectl get serviceaccounts -n revisor"
muestra "kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name'"
muestra "kubectl get role,rolebinding -n revisor -o wide"
muestra "kubectl describe role observador -n revisor"
muestra "kubectl auth can-i --list -n revisor --as=system:serviceaccount:revisor:revisor | head -5"
muestra "kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor"
muestra "kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador"
muestra "kubectl auth can-i get pods --subresource=log -n revisor --as=system:serviceaccount:revisor:observador"
muestra "kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador"
muestra "kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:observador"
muestra "kubectl auth can-i get pods -n default --as=system:serviceaccount:revisor:observador"
muestra "kubectl get deployments -n revisor --as=system:serviceaccount:revisor:observador"
muestra "kubectl delete pod -n revisor -l app=prueba --as=system:serviceaccount:revisor:observador"
muestra "kubectl get secrets -n revisor --as=system:serviceaccount:revisor:observador"

titulo "7.4.4 Lo mismo, desde dentro de un Pod"
muestra "kubectl apply -n revisor -f depurar.yaml -f intruso.yaml -f fig07_04.lector.yaml"
muestra "kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso pod/lector --timeout=180s"
S=/var/run/secrets/kubernetes.io/serviceaccount
muestra "kubectl exec -n revisor lector -- /bin/ls $S"
for r in pods secrets; do
  muestra "kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w \"$r %{http_code}\\n\" --cacert $S/ca.crt -H \"Authorization: Bearer \$(cat $S/token)\" https://kubernetes.default.svc/api/v1/namespaces/revisor/$r'"
done
muestra "kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w \"pods-default %{http_code}\\n\" --cacert $S/ca.crt -H \"Authorization: Bearer \$(cat $S/token)\" https://kubernetes.default.svc/api/v1/namespaces/default/pods'"
muestra "kubectl exec -n revisor lector -- sh -c 'curl -s --cacert $S/ca.crt -H \"Authorization: Bearer \$(cat $S/token)\" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets | grep -E \"message|code\"'"
muestra "kubectl exec -n revisor intruso -- sh -c '/bin/ls /var/run/secrets/kubernetes.io; echo código=\$?' 2>&1"
muestra "kubectl exec -n revisor intruso -- sh -c 'curl -s -k https://kubernetes.default.svc/api/v1/namespaces/revisor/pods | grep -E \"message|code\"'"

# =============================================================================
titulo "7.5.2 ¿Quién aplica las NetworkPolicy?"
muestra "kubectl get daemonset -n kube-system"
muestra "kubectl get daemonset kindnet -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"
muestra "kubectl apply -n default -f intruso.yaml"
muestra "kubectl wait -n default --for=condition=Ready pod/intruso --timeout=180s"
muestra "kubectl get pods -A -l 'app in (depurar,intruso,lector)' -L acceso-revisor"

titulo "7.5.3 Sin reglas"
muestra "kubectl get networkpolicy -n revisor"
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud"
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 http://prueba:9000/"
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\\n' https://kubernetes.default.svc/livez"
muestra "kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud"

titulo "7.5.4 Todo cerrado"
muestra "kubectl apply -n revisor -f fig07_02.cerrado.yaml"
espera 8
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud"
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud"
muestra "kubectl exec -n revisor intruso -- timeout 8 nslookup revisor.revisor.svc.cluster.local"
muestra "kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/salud"
contexto_correcto
printf '\n$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &\n'
kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 >"$TEMPORAL/pf.log" 2>&1 &
PF=$!
espera 3
cat "$TEMPORAL/pf.log"
printf '\n$ curl -s -m 8 -H '"'"'Authorization: Bearer …'"'"' '"'"'http://127.0.0.1:18087/api/estados?formato=tabla'"'"'\n'
curl -s -m 8 -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:18087/api/estados?formato=tabla' || echo "[código de salida: $?]"
kill "$PF" 2>/dev/null || true; wait "$PF" 2>/dev/null || true; PF=""
muestra "kubectl exec -n revisor lector -- sh -c 'curl -s -m 3 -o /dev/null -w \"pods %{http_code}\\n\" --cacert $S/ca.crt -H \"Authorization: Bearer \$(cat $S/token)\" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'"

titulo "7.5.5 Las aperturas necesarias"
muestra "kubectl apply -n revisor -f red.yaml"
espera 8
muestra "kubectl get networkpolicy -n revisor"
muestra "kubectl describe networkpolicy revisor-entrada -n revisor | sed -n '/^Spec:/,\$p'"
muestra "kubectl describe networkpolicy cerrado -n revisor | sed -n '/^Spec:/,\$p'"
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud"
oculta "kubectl exec -n revisor depurar -- curl -s -m 3 -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud"
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 http://prueba:9000/"
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\\n' https://kubernetes.default.svc/livez"
muestra "kubectl exec -n revisor intruso -- nslookup revisor.revisor.svc.cluster.local"
muestra "kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud"
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo
contexto_correcto
printf '\n$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &\n'
kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 >"$TEMPORAL/pf.log" 2>&1 &
PF=$!
espera 3
printf '\n$ curl -s -m 5 http://127.0.0.1:18087/salud   # por port-forward\n'
curl -s -m 5 http://127.0.0.1:18087/salud || echo "[código de salida: $?]"; echo
kill "$PF" 2>/dev/null || true; wait "$PF" 2>/dev/null || true; PF=""
printf '\n(se espera a que pasen varias vueltas de las sondas con la red cerrada)\n'
espera 45
muestra "kubectl get pods -n revisor -l 'app in (revisor,prueba)'"

titulo "7.5.6 Para qué sirve cada regla: se quita una, se mide, se devuelve"
for regla in dns revisor-salida prueba-entrada revisor-entrada acceso-revisor-salida; do
  printf '\n### Sin la regla «%s»\n' "$regla"
  muestra "kubectl delete networkpolicy $regla -n revisor"
  espera 8
  sondeo
  if [ "$regla" = revisor-salida ]; then
    printf '\n(para descartar que el revisor siga usando una conexión que ya tenía abierta con prueba, se reinicia y se vuelve a preguntar)\n'
    muestra "kubectl rollout restart deployment/revisor -n revisor"
    muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
    espera 3
    oculta "kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer $TOKEN' 'http://revisor/api/estados?formato=tabla'"
  fi
  muestra "kubectl apply -n revisor -f red.yaml | grep -v unchanged"
  espera 8
done
printf '\n### Con las seis\n'
sondeo

titulo "7.5.7 Las políticas no se aplican al instante"
printf '\n$ for ciclo in 1 2 3 4 5 6; do   # borrar las seis, esperar 1 s, volver a aplicarlas y preguntar seis veces a la API desde el intruso\n'
for ciclo in 1 2 3 4 5 6; do
  k delete -n revisor -f red.yaml >/dev/null
  sleep 1
  k apply -n revisor -f red.yaml >/dev/null
  t0=$(date +%s); r=""
  for i in 1 2 3 4 5 6; do
    code="$(k exec -n revisor intruso -- curl -s -m 1 -k -o /dev/null -w '%{http_code}' https://kubernetes.default.svc/livez 2>/dev/null || true)"
    r="$r +$(( $(date +%s) - t0 ))s:${code:-000}"
  done
  echo "ciclo $ciclo:$r"
done
espera 8
muestra "kubectl exec -n revisor intruso -- curl -s -m 3 -k -o /dev/null -w '%{http_code}\\n' https://kubernetes.default.svc/livez"

titulo "El error 2: la entrada abierta que no entra"
muestra "kubectl delete networkpolicy acceso-revisor-salida -n revisor"
espera 8
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud"
muestra "kubectl get networkpolicy -n revisor"
muestra "kubectl get pod depurar -n revisor --show-labels"
muestra "kubectl apply -k . | grep networkpolicy"
espera 8
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud"

# =============================================================================
titulo "Hábito de seguridad: el inventario"
muestra "kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'"
muestra "kubectl apply -k . 2>&1 | grep -c -i warning || true"
muestra "kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken'"

# =============================================================================
titulo "Ejercicio 1: la etiqueta correcta en el espacio equivocado"
muestra "kubectl apply -n default -f depurar.yaml"
muestra "kubectl wait -n default --for=condition=Ready pod/depurar --timeout=180s"
muestra "kubectl get pod depurar -n default --show-labels"
muestra "kubectl exec -n default depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud"
muestra "kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud"
muestra "kubectl delete pod depurar -n default --wait=false"

titulo "Ejercicio 2: una cuenta que solo reinicia el revisor"
muestra "kubectl apply -n revisor -f fig07_03.reiniciador.yaml"
muestra "kubectl auth can-i patch deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador"
muestra "kubectl auth can-i patch deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador"
muestra "kubectl auth can-i list deployments -n revisor --as=system:serviceaccount:revisor:reiniciador"
muestra "kubectl rollout restart deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador"
muestra "kubectl rollout restart deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s | tail -1"
muestra "kubectl delete -n revisor -f fig07_03.reiniciador.yaml"

titulo "Ejercicio 3: una ruta que viene de otro espacio"
muestra "kubectl get gateway revisor -n revisor -o jsonpath='{.spec.listeners[0].allowedRoutes}{\"\\n\"}'"
muestra "kubectl apply -n default -f fig07_05.ruta-ajena.yaml"
espera 5
estado_ruta default ajena
muestra "kubectl label namespace default acceso-puerta=permitido"
muestra "kubectl patch gateway revisor -n revisor --type=json -p '[{\"op\":\"add\",\"path\":\"/spec/listeners/0/allowedRoutes\",\"value\":{\"namespaces\":{\"from\":\"Selector\",\"selector\":{\"matchLabels\":{\"acceso-puerta\":\"permitido\"}}}}}]'"
espera 5
estado_ruta default ajena
muestra "kubectl apply -n revisor -f fig07_06.referencegrant.yaml"
espera 5
estado_ruta default ajena
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/ajena"
muestra "kubectl logs -n revisor -l app=revisor --tail=-1 | grep -E 'GET /ajena'"
printf '\n(se deshace todo lo del ejercicio)\n'
muestra "kubectl delete -n default httproute ajena"
muestra "kubectl delete -n revisor referencegrant rutas-de-default"
muestra "kubectl label namespace default acceso-puerta-"
muestra "kubectl patch gateway revisor -n revisor --type=json -p '[{\"op\":\"remove\",\"path\":\"/spec/listeners/0/allowedRoutes\"}]'"

# =============================================================================
titulo "Cómo sé que lo logré: el estado final"
muestra "kubectl delete -n revisor pod depurar intruso lector --wait=false"
muestra "kubectl delete -n default pod intruso --wait=false"
muestra "kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'"
muestra "kubectl get deployments,services,gateway,httproute,networkpolicy -n revisor"
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/api/estados"
muestra "kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted"

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
