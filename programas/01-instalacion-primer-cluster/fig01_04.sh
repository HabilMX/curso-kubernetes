#!/usr/bin/env bash
# fig01_04.sh — Lección 1, sección 1.4: MEDIR los límites de inotify del núcleo
# y, solo si se lo pides, AJUSTARLOS como pide la guía de kind.
#
# Uso:  ./fig01_04.sh                → solo mide. No cambia nada.
#       sudo ./fig01_04.sh --ajustar → copia 99-kind-inotify.conf a /etc/sysctl.d/
#                                      y lo carga. Cambia tu sistema: LÉELO ANTES,
#                                      a él y a 99-kind-inotify.conf.
#
# Corre en la máquina donde corre Docker: en Linux Mint, tu propia máquina.
set -euo pipefail
cd "$(dirname "$0")"

MINIMO_INSTANCIAS=512
MINIMO_VIGILANCIAS=524288
ARCHIVO=99-kind-inotify.conf
DESTINO=/etc/sysctl.d/$ARCHIVO

medir() {
  printf '\n$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches\n'
  sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches

  # Cuántas instancias de inotify están abiertas AHORA. Cada una es un
  # descriptor que apunta a «anon_inode:inotify». Sin sudo solo ves las de tus
  # procesos; con sudo, las de todos los usuarios (el límite es por usuario).
  printf '\n$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l\n'
  # (find se queja de las carpetas que no puede leer: eso no es un fallo aquí)
  { find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null || true; } | wc -l | tr -d ' '

  # ¿Quedó escrito en algún archivo, o solo vale hasta reiniciar? Se buscan las
  # líneas que FIJAN un valor (empiezan con fs.inotify), no los comentarios, en
  # todas las carpetas que lee el sistema al arrancar (sysctl.d(5)).
  printf "\n\$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/\n"
  grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/ 2>/dev/null \
    || echo "(ninguna: lo que mide sysctl vale hasta el próximo reinicio)"

  local inst vig
  inst="$(cat /proc/sys/fs/inotify/max_user_instances)"
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  echo
  if [ "$inst" -ge "$MINIMO_INSTANCIAS" ] && [ "$vig" -ge "$MINIMO_VIGILANCIAS" ]; then
    echo "LISTO: instancias $inst (mínimo $MINIMO_INSTANCIAS) y vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
  else
    echo "FALTA AJUSTAR: instancias $inst (mínimo $MINIMO_INSTANCIAS), vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
    echo "Lee este guion y $ARCHIVO, y luego corre: sudo ./fig01_04.sh --ajustar"
  fi
}

ajustar() {
  [ "$(id -u)" -eq 0 ] || { echo "ALTO: --ajustar necesita sudo." >&2; exit 1; }

  # 1. No BAJAR las vigilancias. En núcleos recientes el valor por omisión
  #    depende de la memoria y puede pasar de 524288; en ese caso se instala el
  #    archivo SIN la línea de vigilancias, y solo se suben las instancias.
  local vig contenido
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  contenido="$(mktemp)"
  if [ "$vig" -gt "$MINIMO_VIGILANCIAS" ]; then
    echo "Tus vigilancias ya son $vig, más que $MINIMO_VIGILANCIAS: no se tocan."
    grep -v '^fs.inotify.max_user_watches' "$ARCHIVO" > "$contenido"
  else
    cat "$ARCHIVO" > "$contenido"
  fi

  # 2. No pisar un archivo que ya existe con otro contenido.
  if [ -e "$DESTINO" ] && ! cmp -s "$contenido" "$DESTINO"; then
    echo "ALTO: ya existe $DESTINO con otro contenido. No lo piso:" >&2
    diff "$DESTINO" "$contenido" >&2 || true
    rm -f "$contenido"
    exit 1
  fi

  # Un archivo propio en /etc/sysctl.d/, en vez de editar /etc/sysctl.conf: se ve
  # de un vistazo qué se cambió y por qué, y se quita borrando un archivo.
  install -o root -g root -m 0644 "$contenido" "$DESTINO"
  rm -f "$contenido"
  printf '\n$ sysctl --load=%s\n' "$DESTINO"
  sysctl --load="$DESTINO"

  # 3. Avisar si /etc/sysctl.conf fija inotify: en Ubuntu y Mint se aplica
  #    DESPUÉS (por 99-sysctl.conf) y su valor ganaría al reiniciar.
  if grep -q '^fs.inotify' /etc/sysctl.conf 2>/dev/null; then
    echo "AVISO: /etc/sysctl.conf también fija inotify y se aplica después de $ARCHIVO:" >&2
    grep -n '^fs.inotify' /etc/sysctl.conf >&2
  fi
  medir
}

case "${1:-}" in
  "") medir ;;
  --ajustar) ajustar ;;
  *) echo "uso: ./fig01_04.sh [--ajustar]" >&2; exit 2 ;;
esac
