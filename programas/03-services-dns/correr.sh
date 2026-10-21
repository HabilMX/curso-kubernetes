#!/usr/bin/env bash
# correr.sh — Lección 3: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l3 (tres nodos), le carga las dos
# imágenes del curso de Docker, deja el revisor como lo dejó la Lección 2 y
# recorre la lección: Service ClusterIP, los tres puertos, EndpointSlices, el Pod
# de depuración, el DNS del clúster, el servicio de prueba, el reparto entre
# réplicas, port-forward hacia 127.0.0.1 y el selector mal escrito. Corre los
# Ejercicios 1 a 3 y borra el clúster. Tarda unos dos minutos.
#
# Necesita Docker, kind, kubectl (Lección 1) y las imágenes curso-docker-revisor:1.6.0
# y curso-docker-prueba:1.0.0 del curso de Docker en tu máquina.
#
# Uso:  ./correr.sh > mi-corrida.txt 2>&1     (desde esta carpeta)
#       Compara mi-corrida.txt con correr.salida.txt, que es la referencia: no
#       redirijas a correr.salida.txt, porque la borrarías.
#
# Usa el puerto 18080 de tu máquina para port-forward, solo en 127.0.0.1. Si lo
# tienes ocupado, córrelo con otro:  PUERTO_LOCAL=18081 ./correr.sh > mi-corrida.txt 2>&1
#
# 🔴 SEGURIDAD: le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config
# no se lee ni se toca); antes de cada kubectl comprueba que el contexto activo es
# kind-curso-k8s-l3 y se detiene si no; no pisa un clúster que ya exista con ese
# nombre; y al salir —aunque algo falle— corta el port-forward y borra el clúster
# que ESTA corrida creó.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l3
CONTEXTO="kind-$CLUSTER"
IMAGEN=curso-docker-revisor:1.6.0
IMAGEN_PRUEBA=curso-docker-prueba:1.0.0
PUERTO_LOCAL="${PUERTO_LOCAL:-18080}"
INICIO_TOTAL=$(date +%s)
CREADO_AQUI=no
TEMPORAL=""
PF=""

limpiar() {
  [ -n "$PF" ] && kill "$PF" 2>/dev/null || true
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  case "$TEMPORAL" in
    /tmp/curso-k8s-l3.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
  esac
  return 0
}
trap limpiar EXIT

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
if lsof -nP -iTCP:"$PUERTO_LOCAL" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "ALTO: el puerto $PUERTO_LOCAL de tu máquina ya está ocupado. Usa otro con PUERTO_LOCAL=…" >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l3.XXXX)"
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
# esperar_direcciones N → espera (hasta 60 s) a que el EndpointSlice del revisor
# tenga N direcciones listas. kube-proxy tarda un momento en enterarse del cambio.
esperar_direcciones() {
  local n
  for _ in $(seq 1 60); do
    n="$(k get endpointslices -l kubernetes.io/service-name=revisor \
      -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' 2>/dev/null | grep -c . || true)"
    [ "$n" = "$1" ] && { sleep 2; return 0; }
    sleep 1
  done
  echo "(aviso: el EndpointSlice no llegó a $1 direcciones listas en 60 s)"
}
# port_forward → abre el port-forward en segundo plano, solo en 127.0.0.1
port_forward() {
  contexto_correcto
  command kubectl port-forward --address 127.0.0.1 service/revisor "$PUERTO_LOCAL:80" >"$TEMPORAL/pf.log" 2>&1 &
  PF=$!
  for _ in $(seq 1 20); do grep -q Forwarding "$TEMPORAL/pf.log" 2>/dev/null && break; sleep 0.5; done
}
cortar_port_forward() { [ -n "$PF" ] && { kill "$PF" 2>/dev/null || true; wait "$PF" 2>/dev/null || true; PF=""; }; }

echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · kind $(kind version | cut -d' ' -f2) · kubectl $(command kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"

titulo "Punto de partida: el clúster y el revisor de la Lección 2"
printf '\n$ kind create cluster --name %s --config kind-curso.yaml\n' "$CLUSTER"
inicio=$(date +%s)
if ! kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear.log" 2>&1; then
  echo "FALLÓ kind create cluster:"; cat "$TEMPORAL/crear.log"; exit 1
fi
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
echo "(crear el clúster y esperar a que esté listo tardó $(( $(date +%s) - inicio )) s)"
muestra "kubectl config current-context"
muestra "kubectl get nodes"
fuera "docker image ls $IMAGEN --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'"
printf '\n$ kind load docker-image %s %s --name %s\n' "$IMAGEN" "$IMAGEN_PRUEBA" "$CLUSTER"
kind load docker-image "$IMAGEN" "$IMAGEN_PRUEBA" --name "$CLUSTER" 2>&1
muestra "kubectl apply -f revisor-deployment.yaml"
muestra "kubectl rollout status deployment/revisor --timeout=180s"

titulo "3.1 Una IP de Pod no sirve como dirección"
muestra "kubectl get pods -l app=revisor -o wide"
VICTIMA="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl delete pod $VICTIMA"
k rollout status deployment/revisor --timeout=120s >/dev/null
muestra "kubectl get pods -l app=revisor -o wide"

titulo "3.2 El Service del revisor"
muestra "kubectl apply -f revisor-service.yaml"
esperar_direcciones 3
muestra "kubectl get services"
muestra "kubectl describe service revisor"

titulo "3.3 Los tres puertos"
muestra "kubectl get service revisor -o jsonpath='port={.spec.ports[0].port} targetPort={.spec.ports[0].targetPort}{\"\\n\"}'"
muestra "kubectl get pods -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].ports[0].name}={.spec.containers[0].ports[0].containerPort}{\"\\n\"}{end}'"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].ports}{\"\\n\"}'"

titulo "3.4 Selectores y EndpointSlices"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{\"\\n\"}{end}'"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{\"\\n\"}'"
VICTIMA="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl delete pod $VICTIMA"
k rollout status deployment/revisor --timeout=120s >/dev/null
esperar_direcciones 3
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{\"\\n\"}{end}'"
muestra "kubectl get endpoints revisor"

titulo "3.5 Un Pod de depuración"
muestra "kubectl apply -f depurar.yaml"
k wait --for=condition=Ready pod/depurar --timeout=180s >/dev/null
muestra "kubectl get pod depurar -o wide"
muestra "kubectl exec depurar -- id"
muestra "kubectl exec depurar -- curl -s http://revisor/salud"
IP_SERVICIO="$(k get service revisor -o jsonpath='{.spec.clusterIP}')"
muestra "kubectl exec depurar -- curl -s http://$IP_SERVICIO/salud"

titulo "3.6 El DNS del clúster"
muestra "kubectl exec depurar -- cat /etc/resolv.conf"
muestra "kubectl get service -n kube-system kube-dns"
muestra "kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide"
muestra "kubectl exec depurar -- nslookup revisor.default.svc.cluster.local"
muestra "kubectl exec depurar -- nslookup revisor"
muestra "kubectl exec depurar -- curl -s http://revisor.default/salud"
muestra "kubectl exec depurar -- nslookup no-existe.default.svc.cluster.local"

titulo "3.7 El servicio de prueba: el revisor ya tiene a quién revisar"
muestra "kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl apply -f prueba-deployment.yaml -f prueba-service.yaml"
k rollout status deployment/prueba --timeout=120s >/dev/null
sleep 3
muestra "kubectl get services"
muestra "kubectl exec depurar -- curl -s http://prueba:9000/modo"
muestra "kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido"
muestra "kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/lento"
muestra "kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano"
muestra "kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'"

titulo "3.8 Cómo reparte un Service"
muestra "kubectl exec depurar -- sh -c 'for i in \$(seq 1 30); do curl -s -o /dev/null http://revisor/salud; done; echo 30 peticiones'"
muestra "kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /salud' | cut -d' ' -f1 | sort | uniq -c"

titulo "3.9 port-forward, solo hacia 127.0.0.1"
printf '\n$ kubectl port-forward --address 127.0.0.1 service/revisor %s:80 &\n' "$PUERTO_LOCAL"
port_forward
cat "$TEMPORAL/pf.log"
fuera "curl -s http://127.0.0.1:$PUERTO_LOCAL/salud"
fuera "curl -s 'http://127.0.0.1:$PUERTO_LOCAL/api/estados?formato=tabla'"
fuera "lsof -nP -iTCP:$PUERTO_LOCAL -sTCP:LISTEN | awk '{print \$1, \$8, \$9, \$10}'"
cortar_port_forward

titulo "Hábito de seguridad: un ClusterIP no se ve desde fuera"
fuera "docker port $CLUSTER-control-plane"
fuera "docker port $CLUSTER-worker"
fuera "docker port $CLUSTER-worker2"
fuera "curl -s -m 3 http://$IP_SERVICIO/salud"

titulo "El error: un selector que no selecciona a nadie"
muestra "kubectl apply -f fig03_01.selector-malo.yaml"
# Se espera a que el EndpointSlice quede vacío (<unset>) antes de probar: si se
# prueba en el mismo segundo, kube-proxy todavía no se entera y curl responde.
esperar_direcciones 0
muestra "kubectl exec depurar -- curl -s -m 3 -o /dev/null -w 'tardó %{time_total} s\\n' http://revisor/salud"
muestra "kubectl exec depurar -- nslookup revisor.default.svc.cluster.local"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor"
muestra "kubectl describe service revisor | grep -E '^(Selector|Endpoints):'"
muestra "kubectl get pods -l app=revisr"
muestra "kubectl get pods -l app=revisor"
muestra "kubectl apply -f revisor-service.yaml"
esperar_direcciones 3
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor"
muestra "kubectl exec depurar -- curl -s -m 3 http://revisor/salud"

titulo "Ejercicio 1: un targetPort donde nadie escucha"
muestra "kubectl apply -f fig03_02.puerto-malo.yaml"
sleep 5
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor"
muestra "kubectl exec depurar -- curl -s -m 3 http://revisor/salud"
muestra "kubectl apply -f revisor-service.yaml"
sleep 5
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor"
muestra "kubectl exec depurar -- curl -s -m 3 http://revisor/salud"

titulo "Ejercicio 2: el Pod que se cuela en el Service"
muestra "kubectl apply -f fig03_03.colado.yaml"
k wait --for=condition=Ready pod/revisor-extra --timeout=60s >/dev/null
esperar_direcciones 4
muestra "kubectl get deployment revisor"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name}{\"\\n\"}{end}'"
muestra "kubectl exec depurar -- sh -c 'for i in \$(seq 1 40); do curl -s -o /dev/null http://revisor/salud; done; echo 40 peticiones'"
muestra "kubectl logs revisor-extra | grep -c 'GET /salud'"
muestra "kubectl delete pod revisor-extra"
esperar_direcciones 3

titulo "Ejercicio 3: port-forward y un rollout"
printf '\n$ kubectl port-forward --address 127.0.0.1 service/revisor %s:80 &\n' "$PUERTO_LOCAL"
port_forward
fuera "curl -s -m 3 http://127.0.0.1:$PUERTO_LOCAL/salud"
muestra "kubectl rollout restart deployment/revisor"
muestra "kubectl rollout status deployment/revisor --timeout=180s"
sleep 3
fuera "curl -s -m 3 http://127.0.0.1:$PUERTO_LOCAL/salud"
printf '\n$ cat pf.log    (lo que escribió el port-forward)\n'; cat "$TEMPORAL/pf.log"
if kill -0 "$PF" 2>/dev/null; then echo "(el port-forward seguía vivo; se corta)"; else echo "(el port-forward ya había terminado solo)"; fi
cortar_port_forward

titulo "Cómo sé que lo logré: el estado final"
esperar_direcciones 3
muestra "kubectl diff -f revisor-deployment.yaml -f revisor-service.yaml -f prueba-deployment.yaml -f prueba-service.yaml >/dev/null && echo 'sin diferencias con los archivos'"
muestra "kubectl get deployments,services"
muestra "kubectl get endpointslices -l kubernetes.io/service-name=revisor"
muestra "kubectl exec depurar -- curl -s http://revisor/salud"
muestra "kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'"
muestra "kubectl delete pod depurar --wait=false"

titulo "Borrar el clúster"
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
inicio=$(date +%s)
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
echo "(borrar tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true
echo "(la corrida completa tardó $(( $(date +%s) - INICIO_TOTAL )) s)"
