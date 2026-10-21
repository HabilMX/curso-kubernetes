#!/usr/bin/env bash
# correr.sh — Lección 4: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l4 (tres nodos), le carga las dos
# imágenes del curso, lo deja como terminó la Lección 3 (revisor y prueba con sus
# Services, más el Pod depurar) y recorre la lección: el ConfigMap escrito a mano
# y por qué no basta, el token como Secret montado en archivo, Kustomize con sus
# generadores, base64, el cambio de configuración que dispara el rollout, el error
# del fsGroup y el Secret inmutable. Corre los Ejercicios 1 a 3 y borra el clúster.
#
# Necesita Docker, kind, kubectl (Lección 1), openssl y las imágenes
# curso-docker-revisor:1.6.0 y curso-docker-prueba:1.0.0 del curso de Docker.
#
# Uso:  ./correr.sh > correr.salida.txt 2>&1     (desde esta carpeta)
#
# 🔴 SEGURIDAD: le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config
# no se lee ni se toca); antes de cada kubectl comprueba que el contexto activo es
# kind-curso-k8s-l4 y se detiene si no; no pisa un clúster que ya exista con ese
# nombre; y al salir —aunque algo falle— borra el clúster que ESTA corrida creó,
# borra token.txt y deja kustomization.yaml como estaba.
#
# 🔴 Si «kind create cluster» falla, el guion lo dice y se DETIENE con código 1:
# un clúster que no se creó no es un clúster en el que se pueda seguir.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l4
CONTEXTO="kind-$CLUSTER"
IMAGENES=(curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0)
CREADO_AQUI=no
TEMPORAL=""
TOKEN_CREADO_AQUI=no

limpiar() {
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  # La kustomization se cambia en 4.7 y en el Ejercicio 2 se rota el token: se
  # deja todo como estaba, aunque el guion se haya detenido a la mitad.
  if [ -n "$TEMPORAL" ] && [ -f "$TEMPORAL/kustomization.original" ]; then
    cp "$TEMPORAL/kustomization.original" kustomization.yaml
  fi
  [ "$TOKEN_CREADO_AQUI" = si ] && rm -f token.txt
  case "$TEMPORAL" in
    /tmp/curso-k8s-l4.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
  esac
  return 0
}
trap limpiar EXIT

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

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l4.XXXX)"
export KUBECONFIG="$TEMPORAL/kubeconfig"
export TMPDIR="$TEMPORAL"
cp kustomization.yaml "$TEMPORAL/kustomization.original"

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
# esperar_revisor → espera el rollout y, además, a que se vayan los Pods viejos
# (rollout status termina mientras los viejos todavía se están apagando).
esperar_revisor() {
  k rollout status deployment/revisor --timeout=180s >/dev/null
  local i
  for i in $(seq 1 90); do
    [ "$(k get pods -l app=revisor --no-headers 2>/dev/null | wc -l | tr -d ' ')" = 3 ] && return 0
    sleep 1
  done
  echo "ALTO: los Pods viejos del revisor no terminaron en 90 s." >&2; exit 1
}
# tabla → el reporte del revisor visto desde el Pod depurar, con el token si lo hay
tabla() {
  if [ -n "${TOKEN:-}" ]; then
    muestra "kubectl exec depurar -- curl -s -H \"Authorization: Bearer \$(cat token.txt)\" 'http://revisor/api/estados?formato=tabla'"
  else
    muestra "kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'"
  fi
}

INICIO_TOTAL=$(date +%s)
echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"

titulo "4.0 El clúster, como terminó la Lección 3"
printf '\n$ kind create cluster --name %s --config kind-curso.yaml\n' "$CLUSTER"
inicio=$(date +%s)
if ! kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear.log" 2>&1; then
  echo "FALLÓ kind create cluster:"; cat "$TEMPORAL/crear.log"; exit 1
fi
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
echo "(crear el clúster y esperar a que esté listo tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind load docker-image %s --name %s\n' "${IMAGENES[*]}" "$CLUSTER"
kind load docker-image "${IMAGENES[@]}" --name "$CLUSTER" >/dev/null 2>&1
echo "(cargadas en los tres nodos)"
muestra "kubectl config current-context"
muestra "kubectl get nodes"
muestra "kubectl apply -f punto-de-partida/revisor-deployment.yaml -f revisor-service.yaml -f prueba-deployment.yaml -f prueba-service.yaml -f depurar.yaml"
esperar_revisor
k rollout status deployment/prueba --timeout=180s >/dev/null
k wait --for=condition=Ready pod/depurar --timeout=180s >/dev/null
muestra "kubectl get deployment,service"

titulo "4.1 La configuración escrita dentro del Deployment"
muestra "kubectl get deployment revisor -o jsonpath='{.spec.template.spec.containers[0].env}{\"\\n\"}'"
tabla

titulo "4.2 Un ConfigMap escrito a mano"
muestra "kubectl apply -f fig04_01.configmap.yaml"
muestra "kubectl get configmap revisor-config -o jsonpath='{.data}{\"\\n\"}'"
muestra "kubectl apply -f fig04_02.revisor-con-configmap.yaml"
esperar_revisor
POD="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl describe pod $POD | sed -n '/Environment:/,/Mounts:/p'"
tabla

titulo "4.3 Cambiar el ConfigMap a mano: los Pods no se enteran"
muestra "kubectl get replicaset -l app=revisor"
muestra "kubectl patch configmap revisor-config -p '{\"data\":{\"REVISOR_SERVICIOS\":\"prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms\"}}'"
sleep 30
echo "(30 s después)"
muestra "kubectl get replicaset -l app=revisor"
tabla
muestra "kubectl rollout restart deployment/revisor"
esperar_revisor
tabla
muestra "kubectl rollout history deployment/revisor"

titulo "4.4 El token: se genera y no se versiona"
printf '\n$ (umask 077; openssl rand -hex 16 > token.txt)\n'
(umask 077; openssl rand -hex 16 > token.txt)
TOKEN_CREADO_AQUI=si
fuera "ls -l token.txt | cut -d' ' -f1"
TOKEN="$(cat token.txt)"
fuera "wc -c < token.txt"
fuera "cat .gitignore"
fuera "git check-ignore -v token.txt"

titulo "4.5 Kustomize: los generadores y el hash"
fuera "cat kustomization.yaml"
muestra "kubectl kustomize . | grep -E '^  name: revisor-(config|token)'"
muestra "kubectl kustomize . | grep -B4 -A3 '^kind: Secret'"
muestra "kubectl apply -k ."
esperar_revisor
muestra "kubectl get configmap"
muestra "kubectl get secret --field-selector type!=kubernetes.io/service-account-token"
muestra "kubectl delete configmap revisor-config"
muestra "kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.immutable}{\"\\n\"}'"
POD="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl describe pod $POD | sed -n '/Environment:/,/Conditions:/p'"
muestra "kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' http://revisor/api/estados"
muestra "kubectl exec depurar -- curl -s http://revisor/api/estados"
tabla
muestra "kubectl exec deployment/revisor -- /revisor healthcheck"

titulo "4.5 El Secret, visto desde el nodo"
NODO="$(k get pod "$POD" -o jsonpath='{.spec.nodeName}')"
UIDPOD="$(k get pod "$POD" -o jsonpath='{.metadata.uid}')"
printf '\n(Pod %s, en el nodo %s)\n' "$POD" "$NODO"
fuera "docker exec $NODO ls -ln /var/lib/kubelet/pods/$UIDPOD/volumes/kubernetes.io~secret/token/..data/"
fuera "docker exec $NODO sh -c 'mount | grep $UIDPOD | grep -E \"secret/token \"'"

titulo "4.6 base64 no es cifrado"
muestra "kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}{\"\\n\"}'"
muestra "kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}' | base64 -d"
fuera "cat token.txt"
muestra "kubectl auth can-i get secrets"

titulo "4.7 Cambiar la lista en la kustomization dispara el rollout"
muestra "kubectl get replicaset -l app=revisor"
sed 's#REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s#REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms#' \
  "$TEMPORAL/kustomization.original" > kustomization.yaml
fuera "grep REVISOR_SERVICIOS kustomization.yaml"
muestra "kubectl diff -k . | grep -E '^[-+] .*(REVISOR_SERVICIOS|name: revisor-config)'"
muestra "kubectl apply -k ."
muestra "kubectl rollout status deployment/revisor --timeout=180s"
esperar_revisor
muestra "kubectl get replicaset -l app=revisor"
tabla
cp "$TEMPORAL/kustomization.original" kustomization.yaml
muestra "kubectl apply -k ."
esperar_revisor
tabla

titulo "El error que vas a ver: sin fsGroup, el revisor no puede leer su token"
muestra "kubectl patch deployment revisor --type=json -p='[{\"op\":\"remove\",\"path\":\"/spec/template/spec/securityContext/fsGroup\"}]'"
sleep 25
muestra "kubectl get pods -l app=revisor"
MALO="$(k get pods -l app=revisor --no-headers | awk '$2 != "1/1" {print $1; exit}')"
muestra "kubectl logs $MALO"
muestra "kubectl describe pod $MALO | sed -n '/^Events:/,\$p'"
NODO="$(k get pod "$MALO" -o jsonpath='{.spec.nodeName}')"
UIDPOD="$(k get pod "$MALO" -o jsonpath='{.metadata.uid}')"
printf '\n(Pod %s, en el nodo %s)\n' "$MALO" "$NODO"
fuera "docker exec $NODO ls -ln /var/lib/kubelet/pods/$UIDPOD/volumes/kubernetes.io~secret/token/..data/"
muestra "kubectl get deployment revisor"
muestra "kubectl apply -k ."
muestra "kubectl rollout status deployment/revisor --timeout=180s"
esperar_revisor

titulo "Hábito de seguridad: un Secret inmutable no se edita"
muestra "kubectl get secret -o name | grep revisor-token | xargs -I{} kubectl patch {} -p '{\"data\":{\"token\":\"eA==\"}}'"

titulo "Ejercicio 1: una llave que no existe en el ConfigMap"
muestra "kubectl patch deployment revisor --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key\",\"value\":\"REVISOR_SERVICIO\"}]'"
sleep 15
muestra "kubectl get pods -l app=revisor"
MALO="$(k get pods -l app=revisor --no-headers | awk '$2 != "1/1" {print $1; exit}')"
muestra "kubectl get events --field-selector involvedObject.name=$MALO,reason=Failed -o custom-columns=MENSAJE:.message | head -2"
muestra "kubectl apply -k ."
esperar_revisor
muestra "kubectl get deployment revisor"

titulo "Ejercicio 2: rotar el token"
muestra "kubectl get secret -o name | grep revisor-token"
printf '\n$ VIEJO="$(cat token.txt)"\n'
VIEJO="$(cat token.txt)"
printf '\n$ (umask 077; openssl rand -hex 16 > token.txt)\n'
(umask 077; openssl rand -hex 16 > token.txt)
TOKEN="$(cat token.txt)"
muestra "kubectl apply -k ."
muestra "kubectl rollout status deployment/revisor --timeout=180s"
esperar_revisor
muestra "kubectl get secret -o name | grep revisor-token"
printf '\n(con el token VIEJO)\n'
muestra "kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H \"Authorization: Bearer \$VIEJO\" http://revisor/api/estados"
printf '\n(con el token NUEVO)\n'
muestra "kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H \"Authorization: Bearer \$(cat token.txt)\" http://revisor/api/estados"

titulo "Ejercicio 3: sin el hash"
mkdir "$TEMPORAL/sin-hash"
cp kustomization.yaml token.txt revisor-deployment.yaml revisor-service.yaml prueba-deployment.yaml prueba-service.yaml "$TEMPORAL/sin-hash/"
printf 'generatorOptions:\n  disableNameSuffixHash: true\n' >> "$TEMPORAL/sin-hash/kustomization.yaml"
fuera "tail -2 \$TEMPORAL/sin-hash/kustomization.yaml"
muestra "kubectl kustomize \$TEMPORAL/sin-hash | grep -E '^  name: revisor-(config|token)|name: revisor-(config|token)\$'"

titulo "Ejercicio 3: rotar el token sin el hash (en un espacio de nombres desechable)"
# Solo el Secret, en el espacio de nombres sin-hash, que se borra al terminar:
# lo mínimo para medir qué pasa al cambiar un Secret inmutable de nombre fijo.
mkdir "$TEMPORAL/rotar"
cp token.txt "$TEMPORAL/rotar/token.txt"
cat > "$TEMPORAL/rotar/kustomization.yaml" <<'EOF'
namespace: sin-hash
secretGenerator:
- name: revisor-token
  files:
  - token=token.txt
  options:
    immutable: true
generatorOptions:
  disableNameSuffixHash: true
EOF
muestra "kubectl create namespace sin-hash"
muestra "kubectl apply -k \$TEMPORAL/rotar"
(umask 077; openssl rand -hex 16 > "$TEMPORAL/rotar/token.txt")
printf '\n(token nuevo en la copia)\n'
muestra "kubectl apply -k \$TEMPORAL/rotar"
muestra "kubectl delete namespace sin-hash"

titulo "Cómo sé que lo logré: el estado final"
muestra "kubectl diff -k . && echo 'sin diferencias con la kustomization'"
muestra "kubectl get deployment revisor"
muestra "kubectl exec deployment/revisor -- /revisor healthcheck"
k delete pod depurar --wait=false >/dev/null

titulo "Borrar el clúster"
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
inicio=$(date +%s)
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
echo "(borrar tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true
echo "(la corrida completa tardó $(( $(date +%s) - INICIO_TOTAL )) s)"
