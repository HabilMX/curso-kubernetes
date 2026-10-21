#!/usr/bin/env bash
# correr.sh — Lección 1: el clúster del curso, de principio a fin.
#
# Crea el clúster curso-k8s-l1 (un nodo de control y dos de trabajo), lo mira,
# juega con los contextos, provoca los errores de la lección, lo borra, lo
# recrea y, al salir, lo borra otra vez. Tarda un par de minutos.
#
# Necesita: Docker, kind v0.33.0, kubectl v1.37.1 (secciones 1.3 y 1.5) y los
# límites de inotify ajustados (sección 1.4, fig01_04.sh).
#
# Uso:  ./correr.sh               (desde esta carpeta)
#
# 🔴 SEGURIDAD, las tres protecciones de la lección:
#   1. KUBECONFIG apunta a un archivo TEMPORAL propio: tu ~/.kube/config ni se
#      lee ni se toca, y tus otros clústeres no se enteran.
#   2. Antes de cada kubectl que le habla al clúster, se comprueba que el
#      contexto activo es kind-curso-k8s-l1; si no, el guion se detiene.
#   3. Un trap borra al salir el clúster que ESTA corrida creó y el temporal,
#      aunque el guion falle a la mitad. Si al empezar ya existe un clúster
#      llamado curso-k8s-l1, se detiene sin tocarlo.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER=curso-k8s-l1
CONTEXTO="kind-$CLUSTER"
CREADO_AQUI=no
TEMPORAL=""

limpiar() {
  if [ "$CREADO_AQUI" = si ]; then
    case "$CLUSTER" in
      curso-k8s-*) kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true ;;
    esac
  fi
  case "$TEMPORAL" in
    */curso-k8s-l1.?*) if [ -d "$TEMPORAL" ]; then rm -rf -- "$TEMPORAL"; fi ;;
  esac
}
trap limpiar EXIT

case "$CLUSTER" in
  curso-k8s-*) ;;
  *) echo "ALTO: el clúster «$CLUSTER» no lleva el prefijo curso-k8s-. No sigo." >&2; exit 1 ;;
esac
if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster de kind llamado «$CLUSTER». Bórralo tú si es tuyo; este guion no lo toca." >&2
  exit 1
fi

TEMPORAL="$(mktemp -d "${TMPDIR:-/tmp}/curso-k8s-l1.XXXX")"
export KUBECONFIG="$TEMPORAL/kubeconfig"

# Muestra el comando como lo teclearías y luego lo corre. Un código de salida
# distinto de 0 se anota y no detiene el guion: varios errores son a propósito.
paso() {
  printf '\n$'
  local a rc=0
  for a in "$@"; do
    case "$a" in
      *\'*) printf ' "%s"' "$a" ;;
      *[[:space:]\|\{\}\$\*]*) printf " '%s'" "$a" ;;
      *) printf ' %s' "$a" ;;
    esac
  done
  printf '\n'
  "$@" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && echo "[código de salida: $rc]"
  return 0
}

# El hábito de la lección: antes de hablarle al clúster, ¿a cuál le hablo?
contexto_correcto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    return 1
  fi
}
k() { contexto_correcto || exit 1; paso kubectl "$@"; }
# kubectl config solo lee o edita el kubeconfig temporal: no le habla a ningún
# clúster, así que no necesita (ni podría pasar) la comprobación del contexto.
kc() { paso kubectl config "$@"; }

segundos() { date +%s; }

# crear VERBO → kind create cluster, mostrando el comando. El clúster se marca
# como propio SOLO si ESTE create terminó bien: si falló (por ejemplo, porque
# otro proceso creó uno con el mismo nombre un instante antes), el trap no lo
# toca y el guion se detiene.
crear() {
  local inicio fin
  printf '\n$ kind create cluster --name %s --config kind-curso.yaml\n' "$CLUSTER"
  inicio=$(segundos)
  if kind create cluster --name "$CLUSTER" --config kind-curso.yaml 2>&1; then
    CREADO_AQUI=si
  else
    echo "ALTO: kind create cluster falló; no toco ningún clúster." >&2
    exit 1
  fi
  fin=$(segundos)
  echo "($1 tardó $((fin-inicio)) s)"
}

# kubectl wait solo espera a los nodos que EXISTEN: si dos nunca se registraron,
# espera a uno y termina sin error. Por eso, además, se cuentan.
tres_nodos() {
  contexto_correcto || exit 1
  local n
  printf '\n$ kubectl get nodes --no-headers | wc -l\n'
  n="$(kubectl get nodes --no-headers | wc -l | tr -d ' ')"
  echo "$n"
  [ "$n" -eq 3 ] || { echo "ALTO: el clúster tiene $n nodos, no 3." >&2; exit 1; }
}

echo "# corrida: $(date '+%Y-%m-%d %H:%M %Z') · kubeconfig temporal propio"

echo
echo "=== 1. Las herramientas ==="
paso kind version
paso kubectl version --client

echo
echo "=== 2. Antes del clúster: el kubeconfig está vacío ==="
kc get-contexts
kc current-context

echo
echo "=== 3. Crear el clúster ==="
paso cat kind-curso.yaml
crear "crear"

echo
echo "=== 4. Contextos y kubeconfig ==="
kc current-context
kc get-contexts
kc view --minify
# Los permisos del archivo (sin el nombre de tu usuario, que no viene al caso)
printf '\n$ stat -c %%A "$KUBECONFIG"\n'
if stat -c %A "$KUBECONFIG" >/dev/null 2>&1; then stat -c %A "$KUBECONFIG"; else stat -f %Sp "$KUBECONFIG"; fi

echo
echo "=== 5. Mirar el clúster ==="
# El ✓ de kind no basta: se espera a que los nodos digan Ready.
k wait --for=condition=Ready nodes --all --timeout=240s
tres_nodos
k get nodes -o wide
k cluster-info
paso kind get nodes --name "$CLUSTER"
paso docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER" --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
k wait --for=condition=Ready pods --all -n kube-system --timeout=240s
k get pods -n kube-system -o wide
k get storageclass

echo
echo "=== 6. inotify: los tres nodos comparten el núcleo ==="
for nodo in "$CLUSTER-control-plane" "$CLUSTER-worker" "$CLUSTER-worker2"; do
  paso docker exec "$nodo" cat /proc/sys/fs/inotify/max_user_instances
done
for nodo in "$CLUSTER-control-plane" "$CLUSTER-worker" "$CLUSTER-worker2"; do
  paso docker exec "$nodo" sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
done

echo
echo "=== 7. Dos contextos: cambiar de clúster sin querer ==="
# Un segundo contexto de mentira, «otro», que apunta a un puerto donde no hay
# nadie (127.0.0.1:1), con una credencial de mentira. Vive solo en el
# kubeconfig temporal y se borra al terminar la sección.
kc set-cluster otro --server=https://127.0.0.1:1
kc set-credentials nadie --token=token-de-mentira
kc set-context otro --cluster=otro --user=nadie
kc get-contexts
kc use-context otro
printf '\n$ (la comprobación del contexto, antes de un kubectl get nodes)\n'
contexto_correcto 2>&1 || echo "[el guion NO corre kubectl get nodes: se detuvo a tiempo]"
printf '\n(Sin la comprobación, kubectl le habla a «otro»:)\n'
paso kubectl get nodes --request-timeout=5s
paso kubectl --context "$CONTEXTO" get nodes
kc use-context "$CONTEXTO"
kc delete-context otro
kc delete-cluster otro
kc delete-user nadie

echo
echo "=== 8. El error de la lección: crear lo que ya existe ==="
paso kind create cluster --name "$CLUSTER" --config kind-curso.yaml

echo
echo "=== 9. Perder el contexto y recuperarlo ==="
kc delete-context "$CONTEXTO"
kc get-contexts
paso kind export kubeconfig --name "$CLUSTER"
kc current-context
k get nodes

echo
echo "=== 10. Borrar y recrear ==="
inicio=$(segundos)
paso kind delete cluster --name "$CLUSTER"
fin=$(segundos)
CREADO_AQUI=no
echo "(borrar tardó $((fin-inicio)) s)"
kc current-context
kc get-contexts
paso docker ps --filter "label=io.x-k8s.kind.cluster=$CLUSTER" --format '{{.Names}}'
paso kind delete cluster --name "$CLUSTER"

crear "recrear"
k wait --for=condition=Ready nodes --all --timeout=240s
tres_nodos
k get nodes

echo
echo "=== 11. Al salir, el trap borra el clúster ==="
