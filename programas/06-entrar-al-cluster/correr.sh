#!/usr/bin/env bash
# correr.sh — Lección 6: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l6 (tres nodos), le carga las dos
# imágenes del curso y recorre la lección: el proyecto aplicado ANTES que la
# plataforma (y por qué falla), el LoadBalancer en <pending>, el NodePort que
# todo LoadBalancer abre, MetalLB y su webhook, Envoy Gateway con --server-side,
# la GatewayClass, el Gateway y la HTTPRoute, la ruta rota a propósito, lo que se
# ve y lo que no se ve desde fuera. Corre los Ejercicios 1 a 3 y borra el clúster.
#
# Necesita Docker, kind, kubectl (Lección 1), openssl, internet (los manifiestos
# de MetalLB y Envoy Gateway se descargan de sus lanzamientos, fijados a su
# versión) y las imágenes curso-docker-revisor:1.6.0 y curso-docker-prueba:1.0.0.
#
# Uso:  ./correr.sh > correr.salida.txt 2>&1     (desde esta carpeta)
#
# 🔴 SEGURIDAD Y CONVIVENCIA:
# - le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config no se lee ni
#   se toca) y, antes de cada kubectl, comprueba que el contexto activo es
#   kind-curso-k8s-l6; si no, se detiene;
# - MetalLB y Envoy Gateway se instalan DENTRO de este clúster y se van con él.
#   No usa Cloud Provider KIND, que actúa sobre todos los clústeres de kind;
# - se detiene antes de crear nada si la red «kind» no es 172.18.0.0/16 o si
#   alguien ya contesta en 172.18.255.200 (otro clúster con MetalLB y el mismo
#   rango: los dos anunciarían las mismas IP y se pisarían);
# - los clientes «de fuera» son contenedores curso-k8s-l6-cliente-* en la red
#   kind, que se borran solos;
# - al salir —aunque algo falle— borra el clúster que ESTA corrida creó y el
#   token.txt que generó. Si «kind create cluster» falla, se detiene con código 1.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l6
CONTEXTO="kind-$CLUSTER"
IMAGENES=(curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0)
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
CREADO_AQUI=no
TOKEN_CREADO_AQUI=no
TEMPORAL=""

limpiar() {
  docker rm -f "$CLUSTER-cliente" >/dev/null 2>&1 || true
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  [ "$TOKEN_CREADO_AQUI" = si ] && rm -f token.txt
  case "$TEMPORAL" in
    /tmp/curso-k8s-l6.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
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
if [ -e token.txt ]; then
  echo "ALTO: ya hay un token.txt en esta carpeta. Este guion genera el suyo y lo borra al terminar; quita el tuyo primero." >&2
  exit 1
fi
RED="$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null || true)"
case " $RED " in
  *" 172.18.0.0/16 "*) ;;
  *) echo "ALTO: la red «kind» de Docker es «$RED», no 172.18.0.0/16. Ajusta el rango de infra/metallb-pool.yaml." >&2; exit 1 ;;
esac
if docker run --rm --network kind --name "$CLUSTER-cliente" "$CURL_IMAGEN" -s -o /dev/null -m 3 http://172.18.255.200/ >/dev/null 2>&1; then
  echo "ALTO: alguien ya contesta en 172.18.255.200 (¿otro clúster con MetalLB y el mismo rango?). Espera a que termine." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l6.XXXX)"
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
# fuera "CADENA" → igual que muestra, para comandos que no son kubectl
fuera() {
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# cliente ARGS → curl desde un contenedor de Docker en la red «kind»: un cliente
# de verdad, FUERA del clúster. Se borra solo (--rm).
cliente() { docker run --rm --network kind --name "$CLUSTER-cliente" "$CURL_IMAGEN" "$@"; }
# desde_fuera "ARGS" → imprime el curl como lo escribiría el alumno y lo corre
desde_fuera() {
  printf '\n$ curl %s\n' "$1"
  local rc=0
  eval "cliente $1" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}
# esperar_direcciones SERVICE N → espera (hasta 90 s) a que el EndpointSlice del
# Service tenga N direcciones listas. Primero la lista llena; después la prueba.
esperar_direcciones() {
  local n
  for _ in $(seq 1 90); do
    n="$(k get endpointslices -l "kubernetes.io/service-name=$1" \
      -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | grep -c . || true)"
    [ "$n" = "$2" ] && { echo "(espera: el EndpointSlice de $1 ya tiene $2 direcciones listas)"; return 0; }
    sleep 1
  done
  echo "(aviso: el EndpointSlice de $1 no llegó a $2 direcciones listas en 90 s)"
}
# esperar_codigo URL CODIGO → espera (hasta 60 s) a que la puerta conteste CODIGO.
# Envoy recibe su configuración un momento después de que la ruta cambia.
esperar_codigo() {
  local c
  for _ in $(seq 1 60); do
    c="$(cliente -s -o /dev/null -m 3 -w '%{http_code}' "$1" 2>/dev/null || true)"
    [ "$c" = "$2" ] && { echo "(espera: la puerta ya contesta $2 en $1)"; return 0; }
    sleep 1
  done
  echo "(aviso: $1 no contestó $2 en 60 s; contestó «$c»)"
}
disco() {
  docker run --rm --entrypoint df "$CURL_IMAGEN" -h /etc/hostname 2>/dev/null | awk 'NR==2{print "disco de Docker: " $5 " usado"}'
}

INICIO_TOTAL=$(date +%s)
echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"
echo "# $(disco)"

titulo "6.0 El clúster de la lección"
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
kind load docker-image "${IMAGENES[@]}" --name "$CLUSTER" 2>&1
fuera "docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'"

titulo "6.1 El proyecto antes que la plataforma"
(umask 077; openssl rand -hex 16 > token.txt)
TOKEN_CREADO_AQUI=si
TOKEN="$(cat token.txt)"
printf '\n$ (umask 077; openssl rand -hex 16 > token.txt)\n'
fuera "ls -l token.txt | cut -c1-10"
muestra "kubectl get crd"
muestra "kubectl apply -k ."
k rollout status deployment/revisor --timeout=180s >/dev/null
k rollout status deployment/prueba --timeout=180s >/dev/null
muestra "kubectl api-resources --api-group=gateway.networking.k8s.io"

titulo "6.2 Un LoadBalancer sin nadie que reparta direcciones"
echo "(pausa de 5 s)"; sleep 5
muestra "kubectl get services"
muestra "kubectl describe service revisor-publico | grep -E '^(Type|LoadBalancer Ingress|Port|NodePort|Endpoints|Events):'"
NODEPORT="$(k get service revisor-publico -o jsonpath='{.spec.ports[0].nodePort}')"
IP_WORKER="$(k get node "$CLUSTER-worker" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
IP_CONTROL="$(k get node "$CLUSTER-control-plane" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
esperar_direcciones revisor-publico 3
desde_fuera "-s -m 5 http://$IP_WORKER:$NODEPORT/salud"; echo
desde_fuera "-s -m 5 http://$IP_CONTROL:$NODEPORT/salud"; echo

titulo "6.3 MetalLB: quien reparte las direcciones, dentro del clúster"
muestra "kubectl apply -k infra/metallb | tail -5"
muestra "kubectl apply -f infra/metallb-pool.yaml"
muestra "kubectl get crd -o name | grep metallb.io"
muestra "kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o jsonpath='{.webhooks[*].failurePolicy}{\"\\n\"}'"
muestra "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
muestra "kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s"
muestra "kubectl apply -f infra/metallb-pool.yaml"
muestra "kubectl get pods -n metallb-system -o wide | awk '{print \$1, \$2, \$3, \$6, \$7}' | column -t"
muestra "kubectl get ipaddresspool,l2advertisement -n metallb-system"
echo "(pausa de 3 s)"; sleep 3
muestra "kubectl get service revisor-publico"
muestra "kubectl get events --field-selector involvedObject.name=revisor-publico --sort-by=.lastTimestamp | awk '{\$1=\"\"; print}' | sed 's/^ //'"
IP_LB="$(k get service revisor-publico -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
desde_fuera "-s -m 5 http://$IP_LB/salud"; echo
desde_fuera "-s -m 5 -H 'Authorization: Bearer $TOKEN' 'http://$IP_LB/api/estados?formato=tabla'" | sed "s/$TOKEN/…/"

titulo "6.4 Envoy Gateway: la plataforma de la puerta"
muestra "kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -c 'Too long'"
muestra "kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -m 1 'Too long' | sed 's/.*\\(The CustomResourceDefinition\\)/\\1/'"
muestra "kubectl apply --server-side -k infra/envoy-gateway | tail -4"
muestra "kubectl get crd -o name | grep -c gateway.networking.k8s.io"
muestra "kubectl get crd -o name | grep -c gateway.envoyproxy.io"
muestra "kubectl get crd -o name | grep gateway.networking.x-k8s.io"
muestra "kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.annotations.gateway\.networking\.k8s\.io/channel} {.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{\"\\n\"}{end}' | grep 'gateway.networking.k8s.io ' | column -t"
muestra "kubectl get mutatingwebhookconfiguration envoy-gateway-topology-injector.envoy-gateway-system -o jsonpath='{.webhooks[*].failurePolicy}{\"\\n\"}'"
muestra "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
muestra "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"
muestra "kubectl apply -f infra/gatewayclass.yaml"
muestra "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
muestra "kubectl get gatewayclass"
muestra "kubectl api-resources --api-group=gateway.networking.k8s.io"

titulo "6.5 El proyecto, ahora sí"
muestra "kubectl apply -k ."
muestra "kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s"
muestra "kubectl get gateway,httproute"
muestra "kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{\"\\n\"}{end}'"
muestra "kubectl get pods,services -n envoy-gateway-system"
muestra "kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'"
IP_GW="$(k get gateway revisor -o jsonpath='{.status.addresses[0].value}')"
esperar_codigo "http://$IP_GW/salud" 200
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo
desde_fuera "-s -m 5 -H 'Authorization: Bearer $TOKEN' 'http://$IP_GW/api/estados?formato=tabla'" | sed "s/$TOKEN/…/"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/api/estados"
printf '\n$ curl -s -m 5 -i http://%s/salud | grep -iE "^(HTTP|server|content-type)"\n' "$IP_GW"
cliente -s -m 5 -i "http://$IP_GW/salud" | tr -d '\r' | grep -iE '^(HTTP|server|content-type)' || true
muestra "kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /api/estados'"

titulo "El error: una ruta hacia un Service que no existe"
muestra "kubectl apply -f fig06_01.ruta-mala.yaml"
esperar_codigo "http://$IP_GW/salud" 500
printf '\n$ curl -s -m 5 -i http://%s/salud | grep -iE "^(HTTP|content-length)"\n' "$IP_GW"
cliente -s -m 5 -i "http://$IP_GW/salud" | tr -d '\r' | grep -iE '^(HTTP|content-length)' || true
muestra "kubectl get gateway revisor"
muestra "kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{\"\\n\"}{end}'"
muestra "kubectl get httproute revisor -o jsonpath='{.status.parents[0].conditions[?(@.type==\"ResolvedRefs\")].message}{\"\\n\"}'"
muestra "kubectl get service revisr"
muestra "kubectl apply -k . | grep httproute"
esperar_codigo "http://$IP_GW/salud" 200
muestra "kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{\"\\n\"}{end}'"
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo

titulo "Hábito de seguridad: qué se expone y por dónde"
muestra "kubectl get services -A -o custom-columns='ESPACIO:.metadata.namespace,NOMBRE:.metadata.name,TIPO:.spec.type,IP-EXTERNA:.status.loadBalancer.ingress[0].ip,NODEPORT:.spec.ports[*].nodePort' | grep -E 'ESPACIO|LoadBalancer|NodePort'"
fuera "docker port $CLUSTER-control-plane"
fuera "docker port $CLUSTER-worker"
fuera "curl -s -m 3 http://$IP_GW/salud"
desde_fuera "-s -m 5 https://$IP_GW/salud"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/api/estados -H 'Authorization: Bearer token-inventado'"

titulo "Ejercicio 1: soltar una dirección y volver a pedirla"
muestra "kubectl delete service revisor-publico"
echo "(pausa de 3 s)"; sleep 3
desde_fuera "-s -m 3 http://$IP_LB/salud"
muestra "kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'"
muestra "kubectl apply -k . | grep revisor-publico"
echo "(pausa de 5 s)"; sleep 5
muestra "kubectl get service revisor-publico"
esperar_direcciones revisor-publico 3
IP_LB2="$(k get service revisor-publico -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
desde_fuera "-s -m 5 http://$IP_LB2/salud"; echo

titulo "Ejercicio 2: la puerta, reducida a lo mínimo"
muestra "kubectl logs -l app=revisor --tail=-1 | grep -c -E 'GET /api/estados|GET /salud/ |POST /salud'"
muestra "kubectl apply -f fig06_02.solo-salud.yaml"
esperar_codigo "http://$IP_GW/api/estados" 404
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/salud"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' -H 'Authorization: Bearer $TOKEN' 'http://$IP_GW/api/estados?formato=tabla'" | sed "s/$TOKEN/…/"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/salud/"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' -X POST http://$IP_GW/salud"
muestra "kubectl logs -l app=revisor --tail=-1 | grep -c -E 'GET /api/estados|GET /salud/ |POST /salud'"
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' -H 'Authorization: Bearer $TOKEN' 'http://$IP_LB2/api/estados?formato=tabla'" | sed "s/$TOKEN/…/"
muestra "kubectl apply -k . | grep httproute"
esperar_codigo "http://$IP_GW/api/estados" 401
desde_fuera "-s -m 5 -o /dev/null -w '%{http_code}\\n' http://$IP_GW/api/estados"

titulo "Ejercicio 3: un Ingress que nadie atiende"
muestra "kubectl get ingressclass"
muestra "kubectl apply -f fig06_03.ingress.yaml"
echo "(pausa de 15 s)"; sleep 15
muestra "kubectl get ingress revisor"
muestra "kubectl describe ingress revisor | grep -E '^(Ingress Class|Address|Events):'"
muestra "kubectl delete -f fig06_03.ingress.yaml"

titulo "Cómo sé que lo logré: el estado final"
esperar_direcciones revisor 3
muestra "kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'"
muestra "kubectl get deployments,services,gateway,httproute"
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo
desde_fuera "-s -m 5 -H 'Authorization: Bearer $TOKEN' 'http://$IP_GW/api/estados?formato=tabla'" | sed "s/$TOKEN/…/"

titulo "Borrar el clúster"
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
inicio=$(date +%s)
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
echo "(borrar tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true

titulo "6.9 Los tres pasos, en un clúster nuevo (meta 1)"
printf '\n$ kind create cluster --name %s --config kind-curso.yaml\n' "$CLUSTER"
inicio=$(date +%s)
if ! kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear2.log" 2>&1; then
  echo "FALLÓ kind create cluster:"; cat "$TEMPORAL/crear2.log"; exit 1
fi
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
echo "(crear el clúster otra vez y esperar a que estuviera listo tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind load docker-image %s --name %s\n' "${IMAGENES[*]}" "$CLUSTER"
kind load docker-image "${IMAGENES[@]}" --name "$CLUSTER" >/dev/null 2>&1
echo "(las dos imágenes, cargadas en los tres nodos)"
muestra "kubectl get crd"
printf '\n$ ./levantar.sh\n'
inicio=$(date +%s)
contexto_correcto
rc=0; ./levantar.sh 2>&1 || rc=$?
[ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
echo "(levantar.sh tardó $(( $(date +%s) - inicio )) s)"
muestra "kubectl get gateway revisor"
muestra "kubectl get service revisor-publico"
esperar_codigo "http://$IP_GW/salud" 200
desde_fuera "-s -m 5 http://$IP_GW/salud"; echo
desde_fuera "-s -m 5 -H 'Authorization: Bearer $TOKEN' 'http://$IP_GW/api/estados?formato=tabla'" | sed "s/$TOKEN/…/"
desde_fuera "-s -m 5 http://$IP_LB/salud"; echo
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true

echo
echo "# $(disco)"
echo "# la corrida completa tardó $(( $(date +%s) - INICIO_TOTAL )) s"
