#!/usr/bin/env bash
# fig09_02.imagen-rota.sh — Lección 9, sección 9.10.4: una actualización con una
# imagen que NO existe. Con maxUnavailable: 0, las réplicas viejas siguen
# contestando mientras la nueva no arranca; rollout undo lo regresa.
#
# Crea el clúster curso-k8s-l9 (lo borra al terminar), aplica SOLO el Deployment y
# el Service del revisor (sin MetalLB ni Envoy Gateway: no hacen falta), y provoca
# el error. No lleva el HPA: el número de réplicas lo pone el propio guion.
#
# Uso:  ./fig09_02.imagen-rota.sh > fig09_02.imagen-rota.salida.txt 2>&1
# RED y SUBRED funcionan igual que en correr.sh (por omisión, la red «kind»).
#
# 🔴 Mismas protecciones que correr.sh: kubeconfig propio y temporal, contexto
# comprobado antes de cada kubectl, y el clúster y el token se borran al salir.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l9
CONTEXTO="kind-$CLUSTER"
RED="${RED:-kind}"
SUBRED="${SUBRED:-172.18.0.0/16}"
IMAGENES=(curso-docker-revisor:1.6.0 curso-docker-revisor:1.6.1 curso-docker-prueba:1.0.0)
CREADO_AQUI=no
TEMPORAL=""
export KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED"

limpiar() {
  if [ "$CREADO_AQUI" = si ]; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  case "$TEMPORAL" in
    /tmp/curso-k8s-l9.?*) [ -d "$TEMPORAL" ] && rm -rf -- "$TEMPORAL" ;;
  esac
  return 0
}
trap limpiar EXIT

if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster de kind llamado «$CLUSTER». Bórralo tú si es tuyo; este guion no lo toca." >&2
  exit 1
fi
for imagen in "${IMAGENES[@]}"; do
  docker image inspect "$imagen" >/dev/null 2>&1 || { echo "ALTO: no encuentro la imagen $imagen en tu Docker." >&2; exit 1; }
done
RED_REAL="$(docker network inspect "$RED" -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null || true)"
case " $RED_REAL " in
  *" $SUBRED "*) ;;
  *) echo "ALTO: la red «$RED» de Docker es «$RED_REAL», no $SUBRED. Ajusta RED y SUBRED." >&2; exit 1 ;;
esac

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
muestra() {
  contexto_correcto
  printf '\n$ %s\n' "$*"
  local rc=0
  eval "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}

echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · clúster $CLUSTER · red $RED ($SUBRED) · kind $(kind version | cut -d' ' -f2) · kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(v[^"]*\)".*/\1/p' | head -1)"

titulo "El clúster, con solo lo que hace falta"
kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >"$TEMPORAL/crear.log" 2>&1 || { cat "$TEMPORAL/crear.log"; exit 1; }
CREADO_AQUI=si
k wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s >/dev/null
kind load docker-image "${IMAGENES[@]}" --name "$CLUSTER" >/dev/null 2>&1
# Una kustomization mínima, en una carpeta temporal: el revisor y su Service, con su
# ConfigMap y su Secret generados, y la prueba. Sin Gateway, sin HPA.
BASE="$TEMPORAL/base"; mkdir -p "$BASE"
cp namespace.yaml cuentas.yaml red.yaml revisor-deployment.yaml revisor-service.yaml prueba-deployment.yaml prueba-service.yaml depurar.yaml "$BASE/"
(umask 077; openssl rand -hex 16 > "$BASE/token.txt")
cat > "$BASE/kustomization.yaml" <<'KUS'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: revisor
resources:
- namespace.yaml
- cuentas.yaml
- red.yaml
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
- depurar.yaml
configMapGenerator:
- name: revisor-config
  literals:
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s
secretGenerator:
- name: revisor-token
  files:
  - token=token.txt
  options:
    immutable: true
KUS
k apply -k "$BASE" >/dev/null
k scale deployment/revisor -n revisor --replicas=2 >/dev/null
k rollout status deployment/revisor -n revisor --timeout=300s >/dev/null
k wait --for=condition=Ready pod/depurar -n revisor --timeout=600s >/dev/null
muestra "kubectl get pods -n revisor -l app=revisor -o wide"

titulo "Actualizar a una imagen que no existe, con el sondeo corriendo"
printf '\n$ ./sondeo.sh 45 0 4 &   # empieza a las %s\n' "$(date '+%H:%M:%S')"
./sondeo.sh 45 0 4 > "$TEMPORAL/sondeo.txt" 2>&1 &
SONDEO=$!
echo "(pausa de 3 s: que el sondeo ya esté corriendo)"; sleep 3
muestra "kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:9.9.9"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=40s"
echo "(espera de 10 s: que el kubelet registre el fallo de descarga)"; sleep 10
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
NUEVO="$(k get pods -n revisor -l app=revisor --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ -n "$NUEVO" ] || NUEVO="$(k get pods -n revisor -l app=revisor -o jsonpath='{range .items[?(@.status.containerStatuses[0].ready==false)]}{.metadata.name}{"\n"}{end}' | head -1)"
muestra "kubectl describe pod $NUEVO -n revisor | sed -n '/Events:/,\$p'"
muestra "kubectl get deployment revisor -n revisor"
wait "$SONDEO" || true
printf '\n# resultado del sondeo (durante toda la actualización rota):\n'; cat "$TEMPORAL/sondeo.txt"

titulo "Volver atrás"
muestra "kubectl rollout undo deployment/revisor -n revisor"
muestra "kubectl rollout status deployment/revisor -n revisor --timeout=180s"
sleep 5
muestra "kubectl get pods -n revisor -l app=revisor -o wide"
muestra "kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].image}{\"\\n\"}'"

titulo "Borrar el clúster"
printf '\n$ kind delete cluster --name %s\n' "$CLUSTER"
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" 2>&1
CREADO_AQUI=no
printf '\n$ kind get clusters | grep -c %s\n' "$CLUSTER"
kind get clusters 2>/dev/null | grep -c -- "$CLUSTER" || true
