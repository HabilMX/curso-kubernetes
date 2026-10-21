#!/usr/bin/env bash
# correr.sh — Lección 2: todo lo que la lección muestra, de principio a fin.
#
# Crea un clúster de kind llamado curso-k8s-l2 (tres nodos), SIN la imagen del
# revisor cargada; provoca el ErrImagePull, carga la imagen, despliega el revisor,
# recorre Pod, ReplicaSet, Deployment, etiquetas, securityContext y rollout, corre
# los ejercicios 1 a 3 y borra el clúster. Tarda unos tres minutos.
#
# Necesita Docker, kind, kubectl (Lección 1) y la imagen curso-docker-revisor:1.6.0
# del curso de Docker en tu máquina (docker image ls curso-docker-revisor).
#
# Uso:  ./correr.sh > correr.salida.txt 2>&1     (desde esta carpeta)
#
# 🔴 SEGURIDAD: le da a kind un kubeconfig PROPIO y temporal (tu ~/.kube/config
# no se lee ni se toca); antes de cada kubectl comprueba que el contexto activo es
# kind-curso-k8s-l2 y se detiene si no; no pisa un clúster que ya exista con ese
# nombre; y al salir —aunque algo falle— borra el clúster que ESTA corrida creó.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l2
CONTEXTO="kind-$CLUSTER"
IMAGEN=curso-docker-revisor:1.6.0
CREADO_AQUI=no
TEMPORAL=""

limpiar() {
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  case "$TEMPORAL" in
    /tmp/curso-k8s-l2.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
  esac
  return 0
}
trap limpiar EXIT

if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster de kind llamado «$CLUSTER». Bórralo tú si es tuyo; este guion no lo toca." >&2
  exit 1
fi
if ! docker image inspect "$IMAGEN" >/dev/null 2>&1; then
  echo "ALTO: no encuentro la imagen $IMAGEN en tu Docker. Constrúyela con el curso de Docker (Lección 10)." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d /tmp/curso-k8s-l2.XXXX)"
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

echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"

titulo "2.1 El clúster, sin la imagen del revisor"
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
fuera "docker exec $CLUSTER-worker crictl images | grep -c curso-docker-revisor"

titulo "2.3 El error a propósito: la imagen no está en el clúster"
muestra "kubectl apply -f revisor-deployment.yaml"
sleep 20
muestra "kubectl get pods -l app=revisor"
muestra "kubectl get events --field-selector reason=Failed -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message | head -4"
VICTIMA="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl describe pod $VICTIMA | sed -n '/^Events:/,\$p'"

titulo "2.4 kind load docker-image y el clúster se recupera solo"
printf '\n$ kind load docker-image %s --name %s\n' "$IMAGEN" "$CLUSTER"
inicio=$(date +%s)
kind load docker-image "$IMAGEN" --name "$CLUSTER" 2>&1
echo "(cargar la imagen en los tres nodos tardó $(( $(date +%s) - inicio )) s)"
fuera "docker exec $CLUSTER-worker crictl images | grep curso-docker-revisor"
muestra "kubectl rollout status deployment/revisor --timeout=180s"
muestra "kubectl get deployment,replicaset -l app=revisor"
muestra "kubectl get pods -l app=revisor -o wide"
muestra "kubectl logs deployment/revisor"

titulo "2.5 La cadena de dueños: Deployment → ReplicaSet → Pod"
POD="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
RS="$(k get rs -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl get pod $POD -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{\"\\n\"}'"
muestra "kubectl get replicaset $RS -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{\"\\n\"}'"
muestra "kubectl get deployment revisor -o jsonpath='{.metadata.ownerReferences}{\"\\n\"}'"

titulo "2.6 Etiquetas y selectores"
muestra "kubectl get pods --show-labels"
muestra "kubectl get replicaset $RS -o jsonpath='{.spec.selector}{\"\\n\"}'"
muestra "kubectl get pods -l 'app in (revisor,prueba)' -o name"
muestra "kubectl get pods -l app=prueba"

titulo "2.7 Un Pod suelto no renace"
muestra "kubectl apply -f fig02_01.pod.yaml"
k wait --for=condition=Ready pod/revisor-suelto --timeout=60s >/dev/null
muestra "kubectl get pod revisor-suelto -o jsonpath='{.metadata.name} dueños={.metadata.ownerReferences}{\"\\n\"}'"
muestra "kubectl delete pod revisor-suelto"
sleep 5
muestra "kubectl get pods"

titulo "2.7 Un Pod del Deployment sí renace"
VICTIMA="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl delete pod $VICTIMA"
k rollout status deployment/revisor --timeout=120s >/dev/null
muestra "kubectl get pods -l app=revisor"
muestra "kubectl get events --field-selector involvedObject.kind=ReplicaSet,reason=SuccessfulCreate -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message"

titulo "Hábito de seguridad: lo que el contenedor no puede hacer"
muestra "kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.securityContext}{\"\\n\"}{.items[0].spec.containers[0].securityContext}{\"\\n\"}'"
muestra "kubectl exec deployment/revisor -- /revisor healthcheck"
muestra "kubectl exec deployment/revisor -- /revisor version"
muestra "kubectl exec deployment/revisor -- sh -c 'id'"
muestra "kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.containers[0].volumeMounts}{\"\\n\"}'"

titulo "Hábito de seguridad: runAsNonRoot contra runAsUser: 0"
muestra "kubectl apply -f fig02_02.raiz.yaml"
sleep 10
muestra "kubectl get pod revisor-raiz"
muestra "kubectl get events --field-selector involvedObject.name=revisor-raiz,reason=Failed -o custom-columns=MENSAJE:.message | head -2"
muestra "kubectl delete pod revisor-raiz"

titulo "2.8 rollout: historia y reinicio"
VIEJO="$(k get rs -l app=revisor -o jsonpath='{.items[0].metadata.labels.pod-template-hash}')"
muestra "kubectl rollout history deployment/revisor"
muestra "kubectl rollout restart deployment/revisor"
muestra "kubectl rollout status deployment/revisor --timeout=180s"
muestra "kubectl get replicaset -l app=revisor"
muestra "kubectl rollout history deployment/revisor"
muestra "kubectl get deployment revisor -o jsonpath='{.spec.template.metadata.annotations}{\"\\n\"}'"
# Los Pods del ReplicaSet viejo tardan unos segundos en irse: se espera a que se vayan.
k wait --for=delete pod -l "app=revisor,pod-template-hash=$VIEJO" --timeout=90s >/dev/null 2>&1 || true

titulo "Ejercicio 1: quitarle la etiqueta a un Pod"
SUELTO="$(k get pods -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
muestra "kubectl label pod $SUELTO app=fuera --overwrite"
sleep 5
muestra "kubectl get pods -L app"
muestra "kubectl get pod $SUELTO -o jsonpath='dueños={.metadata.ownerReferences}{\"\\n\"}'"
muestra "kubectl delete pod $SUELTO"
k rollout status deployment/revisor --timeout=120s >/dev/null

titulo "Ejercicio 2: un Pod suelto con la etiqueta del Deployment"
muestra "kubectl get pods -l app=revisor"
muestra "kubectl apply -f fig02_03.adoptado.yaml"
k wait --for=condition=Ready pod/revisor-extra --timeout=60s >/dev/null
sleep 5
muestra "kubectl get pods -l app=revisor"
muestra "kubectl get deployment revisor"
muestra "kubectl get pod revisor-extra -o jsonpath='dueños={.metadata.ownerReferences}{\"\\n\"}'"
muestra "kubectl get replicaset -l app=revisor -o custom-columns=NOMBRE:.metadata.name,DESEADOS:.spec.replicas,SELECTOR:.spec.selector.matchLabels"
muestra "kubectl delete pod revisor-extra"

titulo "Ejercicio 3: una etiqueta de imagen que no existe"
muestra "kubectl apply -f fig02_04.etiqueta-mala.yaml"
muestra "kubectl rollout status deployment/revisor --timeout=40s"
muestra "kubectl get pods -l app=revisor"
muestra "kubectl get deployment revisor"
muestra "kubectl apply -f revisor-deployment.yaml"
muestra "kubectl rollout status deployment/revisor --timeout=180s"
muestra "kubectl get deployment,replicaset -l app=revisor"

titulo "Cómo sé que lo logré: el estado final"
muestra "kubectl diff -f revisor-deployment.yaml && echo 'sin diferencias con el archivo'"
muestra "kubectl get deployment revisor"
muestra "kubectl exec deployment/revisor -- /revisor healthcheck"

titulo "Borrar el clúster"
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
inicio=$(date +%s)
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
echo "(borrar tardó $(( $(date +%s) - inicio )) s)"
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true
