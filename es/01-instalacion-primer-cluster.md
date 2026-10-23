# Lección 1 — Instalar kubectl y kind; tu primer clúster

Martes, 8:20 de la mañana. A las diez tienes que enseñar el `revisor` corriendo en un clúster, y tu laptop no tiene ni `kubectl`. Buscas «instalar kind» y el primer blog te da dos líneas: un `curl` a una dirección que termina en `latest` y un `sudo mv`. Las copias. Un compañero te pasa por chat «el kubectl que me funciona a mí», un archivo sin versión ni origen. Lo usas también. A las 8:50, `kind create cluster` imprime una columna de palomitas verdes, incluida `✓ Joining worker nodes`. Respiras. A las 9:30, el primer Deployment se queda a medias y descubres que tu clúster de tres nodos tiene uno solo. No sabes qué versión de cada herramienta tienes, ni de dónde salió el binario del chat, ni por qué dos nodos que «se unieron» no existen. Y faltan treinta minutos.

Nada de eso fue mala suerte. Fueron tres decisiones que nadie tomó: qué versión instalar, cómo saber que el binario es el que dice ser y qué límite del sistema hay que subir antes de crear el clúster. Esta lección las toma por ti, una por una, y te deja un clúster que sabes crear, mirar, borrar y volver a crear en menos de medio minuto, una vez que la imagen del nodo ya está en tu disco (la primera vez hay que descargarla, y eso depende de tu conexión).

**Tiempo:** 90 min

**Qué construyes:** el clúster del curso. Un nodo de control y dos de trabajo, creado con `kind` desde un archivo de configuración que fija la imagen del nodo por su huella. Antes, `kubectl` y `kind` instalados con su versión fijada y su suma comprobada, y el límite de `inotify` medido y ajustado. Los programas están en [`programas/01-instalacion-primer-cluster/`](../programas/01-instalacion-primer-cluster).

**Qué aprendes:** qué instalas y dónde corre cada pieza; por qué se fija la versión en lugar de bajar «la última»; qué es una suma `sha256`, cómo se comprueba y qué hacer cuando no coincide; qué es `inotify`, cómo se mide y por qué un clúster de tres nodos lo agota; qué es un `kubeconfig` y qué es un contexto; cómo crear, mirar, borrar y recrear el clúster, y cómo recuperar el contexto si lo pierdes

**De dónde vienes.** De la [Lección 0](00-que-es-kubernetes.md) traes el mapa. Un clúster tiene un plano de control y nodos de trabajo. `kubectl` le habla al `kube-apiserver`, y nada más. kind arma un clúster con nodos que son contenedores de Docker, todos sobre el mismo núcleo de tu máquina. Y viste dos avisos que aquí se vuelven práctica: con un límite de `inotify` de 128, un clúster de tres nodos no arranca aunque kind diga que sí, y sin contexto `kubectl` no sabe a quién hablarle. Del [curso de Docker](https://www.habil.mx/es/cursos/docker/) traes Docker Engine instalado en tu Linux Mint y tu usuario en el grupo `docker`.

**Qué no hace esta lección.** No despliega nada en el clúster: el `revisor` llega en la [Lección 2](02-pods-deployments.md). No instala Docker: eso lo hizo la Lección 1 del curso de Docker. No usa gestores de paquetes (`apt`, `snap`, Homebrew) para `kubectl` ni para `kind`, y en 1.2 se dice por qué. No explica todavía los objetos que ves en `kube-system`: solo los mira.

**Sobre las corridas.** Las salidas se obtuvieron el 21 de octubre de 2026 en una Mac con procesador ARM, con Docker Engine 29.2.1 dentro de una máquina virtual Ubuntu 24.04.4 que levanta Colima. **No** en Linux Mint, que es el sistema de referencia del curso. Para que sepas de dónde viene cada salida, cada una lleva una de estas etiquetas:

| Etiqueta | Qué significa |
|---|---|
| **Corrida real · Mac** | Se corrió en la Mac. Los binarios de Linux se descargaron y su suma se comprobó ahí, en una carpeta temporal que se borró al terminar. El clúster también se creó desde la Mac. |
| **Corrida real · Ubuntu 24.04 amd64** | Se corrió en un contenedor desechable de Ubuntu 24.04 para `amd64`, la base de Linux Mint 22 en un equipo Intel o AMD. Ahí se comprobaron las sumas con el `sha256sum` de GNU, como en tu Mint, y se instalaron y ejecutaron los binarios. El contenedor se borró al salir. |
| **Corrida real · máquina virtual** | Se corrió dentro de la máquina virtual de Colima, que es donde vive el núcleo que usa Docker en la Mac. Ahí se midió `inotify`. |
| **Corrida real · contenedor sin privilegios** | Se corrió en un contenedor desechable que no puede cambiar el núcleo. Ahí se probaron las protecciones del ajuste de `inotify`, sin ajustar nada. |

Lo que cambia en tu Mint. Los `install` y el ajuste de `inotify` llevan `sudo` y cambian tu sistema de verdad (en la Mac no se cambió nada). La columna `KERNEL-VERSION` dirá tu núcleo y `amd64`. Las direcciones IP, el puerto del servidor de la API y los sufijos de los Pods serán otros. Hay una diferencia más, y es instructiva. En la Mac, `kind version` dice `go1.27.0 darwin/arm64`: ese `kind` lo compiló Homebrew, no el proyecto, y por eso cambia el compilador. Es justo lo que esta lección evita en tu Mint: el tuyo será el binario oficial, comprobado por su suma, y dirá `go1.26.7 linux/amd64`, como en la corrida en Ubuntu de 1.3.5.

## Al terminar vas a poder

- Descargar `kubectl` v1.37.1 y `kind` v0.33.0 de su origen oficial, comprobar su suma `sha256` y reconocer el mensaje `FAILED` cuando no coincide.
- Medir los límites de `inotify` de tu núcleo con `sysctl`, ajustarlos de forma persistente con un archivo en `/etc/sysctl.d/` y explicar por qué tres nodos de kind los agotan.
- Crear el clúster del curso con un `kubeconfig` temporal propio y comprobar con `kubectl get nodes` que los tres nodos están `Ready`, sin fiarte de las palomitas.
- Leer un `kubeconfig` con `kubectl config view --minify` y decir qué clúster, qué usuario y qué contexto contiene.
- Comprobar el contexto activo antes de un comando y cambiarlo con `use-context` o con `--context`.
- Borrar el clúster, recrearlo y recuperar su contexto con `kind export kubeconfig` si lo perdiste.

## El porqué antes del cómo

Instalar dos programas parece lo más aburrido del curso. No lo es, porque en esta lección se decide **qué software corre con tu usuario y con `sudo` en tu máquina**, y eso tiene consecuencias.

`kubectl` va a tener en sus manos la credencial de administrador de tu clúster. Viste en la Lección 0 que el usuario de kind es `kubernetes-admin`, del grupo `kubeadm:cluster-admins`. `kind`, por su parte, crea contenedores privilegiados en tu Docker. Un binario alterado de cualquiera de los dos tendría acceso a tu clúster entero y a tu máquina. Por eso no basta con «algo que se llame `kubectl` y funcione». Tiene que ser **el** `kubectl` que publicó el proyecto Kubernetes, en la versión que pediste. La suma de verificación es la forma de comprobarlo en un segundo.

La segunda razón es la reproducibilidad. Si tu compañera y tú instalan «la última», cada una tiene la que era la última el día que la bajó. Dentro de tres meses, una salida del curso no coincide con la tuya y nadie sabe por qué. Kubernetes saca una versión menor unas tres veces al año ([kubernetes.io, «Kubernetes Release Cycle»](https://kubernetes.io/releases/release/)). Fijar la versión convierte «a mí sí me funciona» en algo que se puede comparar.

La tercera es la que viste en la escena: **un clúster de kind de tres nodos depende de un límite del núcleo** que en Ubuntu y en Mint viene bajo. Si no lo subes antes, kind no te avisa. Te dice que todo salió bien.

La lección va en este orden:

1. **Qué vas a instalar** y dónde corre cada pieza (1.1).
2. **Fijar la versión** (1.2).
3. **Descargar y comprobar la suma**, con el error a propósito (1.3).
4. **El ajuste de `inotify`**: medir, ajustar y ver cuánto consume el clúster (1.4).
5. **El archivo del clúster**, con la imagen fijada (1.5).
6. **Crear el clúster** con un `kubeconfig` propio (1.6).
7. **Contextos y `kubeconfig`** (1.7).
8. **Mirar el clúster** (1.8).
9. **Borrar, recrear y recuperar** (1.9).

Este es el destino, el último comando de la lección, después de borrar el clúster y crearlo otra vez en 26 segundos:

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

## Los conceptos

### 1.1 Qué vas a instalar

#### 1.1.1 Las piezas

| Pieza | Qué es | Dónde corre | ¿La instalas aquí? |
|---|---|---|---|
| Docker Engine | el motor que corre los contenedores | tu Mint | no, ya la tienes del curso de Docker |
| `kind` | un programa que crea y borra clústeres hechos de contenedores | tu Mint | **sí**, un solo binario |
| imagen `kindest/node` | la «máquina» de cada nodo: Debian con `systemd`, `kubelet` y `containerd` | dentro de Docker | no, `kind` la descarga la primera vez |
| `kubectl` | el cliente que le habla al `kube-apiserver` | tu Mint | **sí**, un solo binario |
| el clúster | tres contenedores con Kubernetes dentro | dentro de Docker | lo **creas** con `kind` |

Las dos cosas que instalas son **un archivo cada una**. Ni `kubectl` ni `kind` traen bibliotecas, servicios ni demonios. Son binarios de Go que se copian a una carpeta del `PATH` y ya. Por eso la instalación es corta, y por eso conviene hacerla a mano: ves exactamente qué entra a tu sistema.

#### 1.1.2 Por qué no con `apt` o `snap`

Ubuntu, y por lo tanto Mint, ofrece `kubectl` por `snap`, y hay repositorios de `apt` del proyecto Kubernetes. Funcionan, pero tienen un problema para este curso: **deciden la versión por ti** y la actualizan cuando les toca. Un `snap` se actualiza solo en segundo plano. Un repositorio de `apt` te sube de versión en el siguiente `apt upgrade`. En un curso donde cada salida se compara con la tuya, quieres que la versión cambie **cuando tú lo decidas**. La página oficial de instalación de `kubectl` ofrece el binario directo como primera opción, y es el que se usa aquí ([kubernetes.io, «Install and Set Up kubectl on Linux»](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)). La guía rápida de kind hace lo mismo con el binario del lanzamiento ([kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/)).

### 1.2 Fijar la versión

#### 1.2.1 Las versiones del curso

| Herramienta | Versión | De dónde |
|---|---|---|
| `kubectl` | **v1.37.1** | `dl.k8s.io`, el sitio de descargas del proyecto Kubernetes |
| `kind` | **v0.33.0** | el lanzamiento v0.33.0 en GitHub (`kubernetes-sigs/kind`) |
| imagen del nodo | `kindest/node:v1.37.0` con su huella | las notas de la versión v0.33.0 de kind |

La guía oficial de `kubectl` usa un truco: pregunta cuál es la versión estable en `https://dl.k8s.io/release/stable.txt` y baja esa. El 21 de octubre de 2026 ese archivo decía `v1.37.1`, la misma del curso. Pero **mañana puede decir otra**, y el comando de la guía bajaría otra sin avisarte. Por eso los programas de esta lección escriben la versión completa en la dirección, sin preguntar.

#### 1.2.2 ¿Por qué `kubectl` 1.37.1 con un clúster 1.37.0?

Son dos números distintos y la Lección 0 ya los separó. El clúster corre lo que trae la imagen del nodo, `v1.37.0`. `kubectl` es la herramienta de tu máquina. La política oficial es clara: «debes usar una versión de `kubectl` que esté dentro de una versión menor de diferencia con tu clúster. Por ejemplo, un cliente v1.37 puede comunicarse con planos de control v1.36, v1.37 y v1.38» ([kubernetes.io, «Install and Set Up kubectl on Linux»](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/); [«Version Skew Policy»](https://kubernetes.io/releases/version-skew-policy/)). El parche, el tercer número, no cuenta para esa regla.

### 1.3 Descargar y comprobar la suma

#### 1.3.1 Qué es una suma `sha256`

Una suma `sha256` es un número de 256 bits, que se escribe con 64 caracteres hexadecimales (del `0` al `9` y de la `a` a la `f`), y que se calcula a partir de **todos** los bytes de un archivo. Tiene dos propiedades que la vuelven útil. Siempre da lo mismo para el mismo archivo. Y si cambia un solo byte, sale un número completamente distinto, sin parecido con el anterior. No hay forma práctica de fabricar otro archivo que dé la misma suma.

El proyecto publica, junto a cada binario, su suma. Tú bajas los dos, calculas la suma del binario que te llegó y la comparas con la publicada. Si coinciden, el archivo que tienes es, byte por byte, el que el proyecto publicó con esa suma. Si no, algo cambió en el camino: una descarga cortada, un espejo desactualizado, un archivo de otra versión o uno alterado. En cualquiera de esos casos **no se instala**.

Hay que ser honesto con lo que la suma no demuestra. El binario y su suma salen del mismo sitio. Si alguien controlara `dl.k8s.io` y cambiara los dos, coincidirían. La suma te protege de las corrupciones y de las descargas cortadas **entre** el sitio oficial y tu disco, y de mezclar versiones o archivos sin darte cuenta: si lo que quedó en tu disco coincide con la suma, es lo que el sitio publicó. No te protege de un binario que venga de un sitio que no es el oficial: el «`kubectl` que me funciona a mí» que llega por chat no trae suma, o trae una que no puedes contrastar con nada. Por eso el origen importa tanto como la suma.

#### 1.3.2 El programa que descarga y comprueba

`fig01_01.sh` hace la descarga y la comprobación de los dos binarios, con la versión escrita en el propio guion. No instala nada ni pide `sudo`. Deja los archivos en la carpeta que le digas.

```bash
#!/usr/bin/env bash
# fig01_01.sh — Lección 1, sección 1.3: descargar kubectl y kind con la versión
# FIJADA y comprobar su suma sha256 ANTES de instalarlos.
#
# Solo descarga y comprueba: no instala nada ni pide sudo. Los dos binarios
# quedan en la carpeta que le des, listos para el «sudo install» de la lección.
#
# Uso:  ./fig01_01.sh CARPETA        (una carpeta nueva y vacía, por ejemplo ~/descargas-k8s)
#
# Descarga los binarios de Linux para amd64, los de Linux Mint en un equipo
# Intel o AMD. Si tu equipo es ARM, cambia ARQ=arm64.
set -euo pipefail

KUBECTL_VERSION=v1.37.1
KIND_VERSION=v0.33.0
ARQ=amd64

DESTINO="${1:?uso: ./fig01_01.sh CARPETA}"
mkdir -p "$DESTINO"
cd "$DESTINO"

# Muestra el comando como lo teclearías y luego lo corre.
paso() { printf '\n$ %s\n' "$*"; "$@"; }

echo "# kubectl $KUBECTL_VERSION y kind $KIND_VERSION para linux/$ARQ"

# kubectl: el binario y su suma salen de dl.k8s.io, con la MISMA versión.
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl"
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl.sha256"
paso cat kubectl.sha256; echo
# El archivo .sha256 de kubectl trae solo la suma; se le pega el nombre del
# archivo, como lo pide la guía oficial. El «-» final dice «lee la lista de la
# entrada»: en Linux es opcional, y con él el guion corre igual en macOS.
printf '\n$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -\n'
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -

# kind: el binario y su suma salen del lanzamiento en GitHub. El .sha256sum de
# kind ya trae «suma  nombre», así que se comprueba directo.
paso curl -fsSLo "kind-linux-$ARQ" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ"
paso curl -fsSLo "kind-linux-$ARQ.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ.sha256sum"
paso cat "kind-linux-$ARQ.sha256sum"
paso sha256sum --check "kind-linux-$ARQ.sha256sum"

# Lo que quedó: dos binarios comprobados. wc -c da su tamaño en bytes, para
# compararlo con el de la lección.
paso wc -c kubectl "kind-linux-$ARQ"
```

Tres detalles, de arriba abajo:

- **`set -euo pipefail`** hace que el guion se detenga en el primer comando que falle. Si la suma no coincide, `sha256sum` sale con código 1 y el guion se para ahí, antes de descargar `kind` y antes del `wc -c` final.
- **`curl -fsSL`**: `-f` hace que un error del servidor (un 404 porque escribiste mal la versión) sea un fallo y no un archivo de error guardado con el nombre del binario. `-L` sigue las redirecciones, que GitHub usa en todas sus descargas. `-sS` calla la barra de progreso pero deja ver los errores.
- **Dos formatos de suma.** El `kubectl.sha256` del proyecto Kubernetes trae solo los 64 caracteres. Por eso la guía oficial arma la línea «suma, dos espacios, nombre» con `echo` y se la pasa a `sha256sum --check`. El `.sha256sum` de kind ya trae la línea completa, y `sha256sum --check` lo lee directo.

#### 1.3.3 La corrida

**Corrida real · Mac** (la carpeta temporal se borró al terminar):

```text
# kubectl v1.37.1 y kind v0.33.0 para linux/amd64

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ cat kubectl.sha256
65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
kubectl: OK

$ curl -fsSLo kind-linux-amd64 https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64

$ curl -fsSLo kind-linux-amd64.sha256sum https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64.sha256sum

$ cat kind-linux-amd64.sha256sum
aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d  kind-linux-amd64

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ wc -c kubectl kind-linux-amd64
 61886626 kubectl
 10530942 kind-linux-amd64
 72417568 total
```

Lo que importa son los dos `OK`. Anota también las dos sumas: si dentro de un mes bajas otra vez los mismos binarios con las mismas versiones, deben salir **exactamente** estas. Si salen otras, no es la misma versión o no es el mismo archivo. El `wc -c` del final dijo que `kubectl` pesa 61,886,626 bytes y `kind` 10,530,942.

La guía rápida de kind da el comando de descarga del binario, pero no menciona la suma ([kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/)). El lanzamiento v0.33.0 sí publica un `.sha256sum` para cada binario (Linux `amd64` y `arm64`, macOS y Windows), y se ve en la lista de archivos de [su página de lanzamiento](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0). Que la guía no lo pida no quiere decir que no haga falta. Este curso lo pide.

#### 1.3.4 El error a propósito: `FAILED`

`fig01_02.sh` provoca el fallo de las dos formas en que pasa de verdad. En el primer caso, el binario es de **otra versión**, v1.37.0, y la suma de v1.37.1. Es lo que te pasa cuando bajas el binario con el comando de `stable.txt` un día y la suma con otro, o cuando copias la dirección de un tutorial y la suma de otro. En el segundo, el binario es el correcto, pero con **un byte de más** al final, como uno que se corrompió o que alguien tocó. **Corrida real · Mac** (`fig01_02.error-esperado.txt`):

```text
## Caso 1: binario de v1.37.0, suma de v1.37.1

$ curl -fsSLO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]

## Caso 2: el binario correcto, con un byte de más

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]
```

Se lee así: `kubectl: FAILED` es el veredicto sobre ese archivo, y la advertencia dice cuántos de los archivos revisados no coincidieron (aquí, uno de uno). El código de salida 1 es lo que detiene a `set -e` en un guion. La guía oficial muestra el veredicto primero y la advertencia después, que es lo que verás en la terminal de tu Mint. La salida de arriba viene del `sha256sum` de macOS, que imprimió la advertencia antes. Las dos líneas viajan por canales distintos (la salida normal y la de errores), así que, cuando las capturas en un archivo, su orden puede cambiar. Lo que no cambia es el `FAILED` y el código de salida 1.

Fíjate en lo que **no** te dice el mensaje: no distingue «otra versión» de «archivo alterado». Los dos casos se ven idénticos. Y es correcto que sea así: a ti no te toca averiguar cuál de los dos fue, sino no instalar. Lo que haces ante un `FAILED`: borras el binario y su suma, compruebas que las dos direcciones digan la misma versión y bajas los dos otra vez. Si vuelve a fallar con la misma versión, no instalas nada y averiguas de dónde estás descargando.

#### 1.3.5 Instalar

En tu Mint, la instalación son dos comandos, el de la guía oficial de `kubectl` y su equivalente para `kind`:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
sudo install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind
```

(En un equipo ARM, el archivo de kind se llama `kind-linux-arm64`, los dos binarios son otros y sus sumas también: compáralas con las que publica cada lanzamiento, no con las de esta lección.)

`install` hace en un paso lo que harían `cp`, `chown` y `chmod`. Copia el archivo, lo deja con dueño `root` (`-o root -g root`) y con permiso `0755`: todos pueden ejecutarlo, solo `root` puede cambiarlo. Eso último importa. Un binario en tu `PATH` que tu usuario puede sobrescribir es un binario que cualquier programa que corra como tú puede reemplazar. La guía rápida de kind usa `chmod +x` y `sudo mv`. El resultado es casi el mismo, pero el archivo queda con tu usuario como dueño. `install` es más limpio, y por eso el curso lo usa para los dos. `/usr/local/bin` es la carpeta que Linux reserva para los programas que instalas tú a mano, fuera del gestor de paquetes. Ya está en el `PATH` de Mint.

Como en la Mac no se instaló nada, `fig01_03.sh` hace la instalación completa **dentro de un contenedor desechable** de Ubuntu 24.04 para `amd64`, con los mismos archivos que bajó `fig01_01.sh`. Los archivos entran por un `tar` en la entrada estándar, sin montar carpetas. Dentro del contenedor ya eres `root`, así que los `install` van sin `sudo`. **Corrida real · Ubuntu 24.04 amd64** (`fig01_03.salida.txt`):

```text
# Ubuntu 24.04.5 LTS, x86_64, sha256sum (GNU coreutils) 9.4

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: OK

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
$ install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind

$ ls -l /usr/local/bin/kubectl /usr/local/bin/kind
-rwxr-xr-x 1 root root 10530942 Oct 21 09:53 /usr/local/bin/kind
-rwxr-xr-x 1 root root 61886626 Oct 21 09:53 /usr/local/bin/kubectl

$ command -v kubectl kind
/usr/local/bin/kubectl
/usr/local/bin/kind

$ kubectl version --client
Client Version: v1.37.1
Kustomize Version: v5.8.1

$ kind version
kind v0.33.0 go1.26.7 linux/amd64
```

Aquí la comprobación usa el comando de la guía **letra por letra**, sin el `-` final, y el `sha256sum` de GNU dice `OK` igual. Después, tres comprobaciones que vas a repetir en tu Mint:

- **`ls -l`**: los permisos `-rwxr-xr-x`, el dueño `root root` y el tamaño, que debe ser el mismo que viste al descargar.
- **`command -v kubectl kind`**: qué archivo corre de verdad cuando tecleas el nombre. Si tenías otro `kubectl` instalado antes (por `snap`, por ejemplo), aquí ves cuál gana. Lo correcto es `/usr/local/bin/kubectl`.
- **`kubectl version --client`** y **`kind version`**: las versiones que pediste. `--client` le dice a `kubectl` que no busque un clúster, porque todavía no hay. `Kustomize Version: v5.8.1` es la herramienta de la Lección 4, que viene **dentro** de `kubectl` y no se instala aparte.

Un aviso que salió de la propia Mac de las corridas. Ahí, en la terminal interactiva, `type kubectl` respondió `kubectl: aliased to kubecolor`: un alias que alguien configuró para colorear la salida. Los guiones no ven los alias de tu terminal, así que corrían el `kubectl` real, pero lo que tecleabas a mano pasaba por otro programa. `command -v` no siempre revela un alias; `type kubectl` sí. Si tu salida no se parece a la del curso, empieza por ahí.

### 1.4 El ajuste de `inotify`

#### 1.4.1 Qué es `inotify`

Muchos programas necesitan enterarse de que un archivo cambió sin estar leyéndolo cada segundo. Linux les da un mecanismo para eso: «la API de `inotify` ofrece un mecanismo para vigilar eventos del sistema de archivos» ([man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html)). Un programa abre una **instancia** de `inotify` y le agrega **vigilancias**, una por archivo o carpeta. El núcleo le avisa cuando algo cambia.

Cada instancia y cada vigilancia ocupan memoria del núcleo, así que el núcleo pone dos topes, **por usuario**:

- `fs.inotify.max_user_instances`: «un límite superior al número de instancias de `inotify` que se pueden crear por usuario real».
- `fs.inotify.max_user_watches`: lo mismo para las vigilancias.

En un nodo de Kubernetes, el `kubelet`, `kube-proxy`, `containerd` y los componentes del plano de control vigilan archivos todo el tiempo: certificados, manifiestos, configuraciones, los registros de los contenedores. En una máquina normal, un nodo es una máquina. En kind, **tres nodos son tres contenedores sobre el mismo núcleo**, y casi todos sus procesos corren como el mismo usuario, `root`. Los tres se reparten un solo tope.

La guía de problemas conocidos de kind lo dice así: los límites «se definen con las variables del sistema `fs.inotify.max_user_watches` y `fs.inotify.max_user_instances`. Por ejemplo, en Ubuntu valen 8192 y 128 respectivamente, lo cual no basta para crear un clúster con muchos nodos» ([kind, «Known Issues»](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files)). Y da los valores que recomienda: 524288 vigilancias y 512 instancias.

#### 1.4.2 Medir antes de tocar

El ajuste se hace **antes** de crear el clúster, y se empieza por medir. `fig01_04.sh` sin argumentos solo lee; con `--ajustar` cambia tu sistema, y lo vemos en 1.4.3:

```bash
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
```

Lo nuevo está en dos comandos de la medición. El primero **cuenta las instancias abiertas**. Cada instancia es un descriptor de archivo de algún proceso, y en `/proc/<pid>/fd/` ese descriptor aparece como un enlace a `anon_inode:inotify`. `find ... -lname` busca exactamente esos enlaces. Sin `sudo` solo puedes mirar los descriptores de tus propios procesos; con `sudo` ves los de todos los usuarios, aunque el tope se cuenta por usuario. El segundo, el `grep`, busca **dónde quedó escrito** el valor, en todas las carpetas que el sistema lee al arrancar. Busca líneas que empiecen con `fs.inotify`, que son las que fijan un valor, y no los comentarios que solo mencionan la palabra.

En la Mac, el núcleo que usa Docker es el de la máquina virtual de Colima, así que ahí se midió. **Corrida real · máquina virtual** (`fig01_04.salida.txt`, solo medición, sin ajustar):

```text
# máquina virtual de Colima: Ubuntu 24.04.4 LTS, núcleo 6.8.0-100-generic
## sin sudo

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
3

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).

## con sudo (solo mide)

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
110

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).
```

Esa máquina ya tenía 512 instancias, y vigilancias de sobra. La diferencia entre 3 y 110 instancias es la de «sin `sudo`» y «con `sudo`»: el usuario normal tenía 3 abiertas, y el sistema entero 110, con un clúster de kind de otra lección corriendo en ese momento. Ese número cambia con todo lo que esté corriendo. Lo que se compara es el tope.

Y fíjate en el `grep`: **ningún archivo** de las carpetas que se leen al arrancar fija `inotify`. El 512 está vivo en el núcleo, pero no escrito. La Lección 0 cuenta que esa misma máquina estaba en 128 y que se subió a 512 para su prueba; el `grep` muestra que se subió sin dejar archivo. Si es así, el día que la máquina virtual se reinicie vuelve al valor de omisión, y el siguiente clúster de tres nodos falla sin explicación. La medición dice cuánto vale hoy; el `grep` dice cuánto valdrá después de reiniciar. Hay que mirar las dos cosas, y por eso el guion las mira juntas.

En tu Mint recién instalada, lo más probable es que veas `max_user_instances = 128` y el guion diga `FALTA AJUSTAR`. Linux Mint 22 se basa en Ubuntu 24.04 ([Linux Mint, notas de la versión 22](https://www.linuxmint.com/rel_wilma.php)), y Ubuntu trae 128. Las vigilancias, en cambio, pueden salirte altas: en la máquina virtual de las corridas, también un Ubuntu 24.04, el núcleo daba 1048576, muy por encima de las 8192 que menciona la guía de kind. En núcleos recientes ese valor depende de la memoria de la máquina, así que lo que casi siempre falta son las instancias.

#### 1.4.3 Ajustar, y que dure

La guía de kind da dos formas. La **temporal**, que vale hasta que reinicies:

```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

Y la **persistente**: escribir las dos líneas en `/etc/sysctl.conf`. El curso hace lo persistente con una variante: en lugar de editar `/etc/sysctl.conf`, pone un archivo propio en `/etc/sysctl.d/`. Este es el archivo, `99-kind-inotify.conf`:

```ini
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

¿Por qué un archivo aparte? Porque «al arrancar, `systemd-sysctl.service` lee los archivos de configuración» de `/etc/sysctl.d/*.conf`, entre otras carpetas ([man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html)). Tienes en un solo archivo, con su comentario, qué cambiaste y por qué, y para deshacerlo lo borras y reinicias.

Pero hay una trampa en el orden. La misma página dice que todos los archivos se ordenan por su nombre, sin importar en qué carpeta estén, y que si dos fijan lo mismo **gana el que va después**. El `99-` deja el archivo del curso casi al final. Casi, porque Ubuntu, y con él Mint, trae otro. Medido en la máquina virtual de las corridas:

```text
$ ls /etc/sysctl.d/
10-bufferbloat.conf
10-console-messages.conf
10-ipv6-privacy.conf
10-kernel-hardening.conf
10-magic-sysrq.conf
10-map-count.conf
10-network-security.conf
10-ptrace.conf
10-zeropage.conf
99-cloudimg-ipv6.conf
99-lima.conf
99-sysctl.conf
README.sysctl

$ ls -l /etc/sysctl.d/99-sysctl.conf
lrwxrwxrwx 1 root root 14 Nov 25  2025 /etc/sysctl.d/99-sysctl.conf -> ../sysctl.conf
```

`99-sysctl.conf` es un enlace a `/etc/sysctl.conf`, y `99-sysctl.conf` va después de `99-kind-inotify.conf` en orden alfabético (la `s` va después de la `k`). Así que **si alguien puso un valor de `inotify` en `/etc/sysctl.conf`, ese valor gana** al reiniciar, y el del curso no sirve de nada. Por eso `--ajustar` revisa `/etc/sysctl.conf` y te avisa, y por eso la medición busca en todas las carpetas.

En tu Mint, el ajuste es `sudo ./fig01_04.sh --ajustar`. **Antes de correrlo con `sudo`, léelo completo, junto con `99-kind-inotify.conf`.** Es el mismo hábito que con los binarios: todo lo que corre como `root` lo leíste antes. Lo que vas a encontrar en `ajustar`:

1. **No baja tus vigilancias.** Si tu núcleo ya tiene más de 524288, el archivo que instala va sin la línea `max_user_watches`, y solo sube las instancias. Sin esta protección, el ajuste de kind te **quitaría** vigilancias.
2. **No pisa un archivo que ya existe.** Si `/etc/sysctl.d/99-kind-inotify.conf` existe con otro contenido, te muestra la diferencia y se detiene.
3. Copia el archivo con dueño `root` y permiso `0644`, lo carga en ese momento con `sysctl --load` (sin esperar a reiniciar), te avisa si `/etc/sysctl.conf` también fija `inotify` y vuelve a medir. Debe terminar en `LISTO`.

El ajuste de verdad no se corrió en la máquina de las corridas: ya tenía 512, y era una máquina compartida donde no tocaba cambiar nada. Lo que sí se probó son las dos protecciones, en un contenedor desechable **sin privilegios**, donde `/proc/sys` es de solo lectura y `sysctl` no puede cambiar el núcleo de nadie. **Corrida real · contenedor sin privilegios** (`fig01_04.prueba-ajustar.txt`):

```text
$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.

$ sysctl --load=/etc/sysctl.d/99-kind-inotify.conf
sysctl: permission denied on key "fs.inotify.max_user_instances"
[código de salida: 1]

$ cat /etc/sysctl.d/99-kind-inotify.conf
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_instances = 512

$ echo otro > /etc/sysctl.d/99-kind-inotify.conf

$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.
ALTO: ya existe /etc/sysctl.d/99-kind-inotify.conf con otro contenido. No lo piso:
1c1,5
< otro
---
> # /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
> # kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
> # Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
> # arranca: el kubelet de los nodos de trabajo cae con «too many open files».
> fs.inotify.max_user_instances = 512
[código de salida: 1]
```

La primera corrida vio 1048576 vigilancias e instaló el archivo **sin** la línea de vigilancias: el `cat` lo demuestra. El `permission denied` es lo esperado en un contenedor sin privilegios; en tu Mint, con `sudo`, `sysctl --load` responde con las líneas que cargó. La segunda corrida encontró un archivo con otro contenido y se detuvo sin tocarlo.

#### 1.4.4 Cuánto consume un clúster

Con el clúster creado (1.6), el guion de la lección mira el límite **desde dentro** de cada nodo, y cuenta las instancias que abre cada uno. **Corrida real · Mac**, extracto de `correr.salida.txt`:

```text
$ docker exec curso-k8s-l1-control-plane cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker2 cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-control-plane sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
45

$ docker exec curso-k8s-l1-worker sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18

$ docker exec curso-k8s-l1-worker2 sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18
```

Los tres nodos dicen 512: no tienen un límite propio, ven **el del núcleo de la máquina**. Es la misma pista que la columna `KERNEL-VERSION` de la Lección 0, ahora con un número que importa. Y el conteo: 45 instancias en el nodo de control y 18 en cada nodo de trabajo. Son 81, con el clúster **vacío**, recién creado, sin un solo Pod tuyo. Casi todas son de procesos de `root`, y el tope es por usuario: a esas 81 se suman las que `root` ya tiene abiertas en tu propia máquina, que puedes contar con el `find` de `fig01_04.sh` corrido con `sudo`. Con un tope de 128, el margen es poco. Lo que pasa en el arranque, cuando los tres nodos levantan sus procesos a la vez, no se midió aquí; la Lección 0 vio el resultado: los nodos de trabajo no llegaron. Con 512 hay lugar de sobra para este clúster y para otro más.

### 1.5 El archivo del clúster

`kind create cluster` sin más crea un clúster de un solo nodo llamado `kind`, con la imagen de nodo por omisión de esa versión de kind. El curso necesita tres nodos, un nombre propio y la imagen fijada, y eso se escribe en un archivo:

```yaml
# kind-curso.yaml — el clúster del curso: un nodo de control y dos de trabajo,
# con la imagen del nodo fijada por su huella (notas de la versión v0.33.0 de kind).
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

Se lee de arriba abajo. `kind: Cluster` y `apiVersion: kind.x-k8s.io/v1alpha4` dicen que es la configuración de un clúster de kind. Parece un manifiesto de Kubernetes, pero no lo es: este archivo lo lee `kind`, nunca el clúster. `nodes` es la lista de nodos, uno por renglón con `role`: `control-plane` para el plano de control y `worker` para los de trabajo. Es la misma forma que usa la guía rápida de kind para un clúster «de tres nodos (dos de trabajo)» ([kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/)).

Y cada nodo lleva su `image` **con huella**. Es el mismo hábito que la suma de los binarios, aplicado a una imagen. La etiqueta `v1.37.0` es un nombre que quien publica la imagen puede mover a otra. La huella `sha256:a1ed…` es la suma del contenido. La guía de kind lo pide así: «usa la suma `sha256` de la versión de Kubernetes que quieras», tal como la publican las notas de cada lanzamiento ([kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/); [kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). Si alguien sustituye la imagen, Docker no la acepta, porque la huella deja de coincidir.

El nombre del clúster no va en el archivo, va en la orden: `--name curso-k8s-l1`. Así el mismo archivo sirve para crear clústeres con otros nombres.

La orden busca `kind-curso.yaml` por la ruta que le des. Los comandos de esta lección dan por hecho que estás dentro de `programas/01-instalacion-primer-cluster/`, donde vive el archivo. Si copias el archivo a otra carpeta, corre la orden desde ahí o escribe la ruta completa en `--config`.

### 1.6 Crear el clúster

#### 1.6.1 Un `kubeconfig` propio para el curso

Antes de crear nada, una decisión de seguridad. Cuando kind crea un clúster, **escribe en tu `kubeconfig`** la dirección del clúster y la credencial de administrador, y lo deja como contexto activo. Si no le dices otra cosa, ese archivo es `~/.kube/config`. Si en ese archivo ya hay un clúster del trabajo o de otro curso, kind cambia el contexto activo sin preguntarte.

Por eso, en este curso, kind escribe en un archivo **temporal y propio**. A mano, en tu terminal, es así:

```bash
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l1.XXXX)/kubeconfig"
```

`mktemp -d` crea una carpeta con un nombre que nadie más tiene. `export KUBECONFIG=…` hace que `kind` y `kubectl` usen ese archivo **en esta terminal**, y en ninguna otra. Tu `~/.kube/config` ni se lee ni se toca. Cierras la terminal y tu configuración de siempre sigue igual que antes.

Lo que **no** se va al cerrar la terminal: el clúster, que sigue corriendo, y la carpeta temporal, con la credencial de administrador dentro. Además, al cerrar pierdes la ruta del `KUBECONFIG`. Por eso, en el camino a mano, antes de cerrar:

```bash
kind delete cluster --name curso-k8s-l1
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp arriba.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l1.*/kubeconfig) rm -r -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

El `case` solo deja pasar una ruta con la forma exacta de la que creó `mktemp`; si tu `KUBECONFIG` apunta a otra parte, por ejemplo a tu `~/.kube/config` porque abriste otra terminal y no repetiste el `export`, no borra nada y te dice por qué, en lugar de llevarse tu carpeta `~/.kube` entera.

Si ya cerraste, `kind get clusters` te dice qué quedó vivo, y `ls -d /tmp/curso-k8s-l1.*` qué carpetas quedaron. El guion de la lección, `correr.sh`, hace todo esto solo: crea su carpeta temporal y, al salir, borra el clúster y la carpeta.

#### 1.6.2 El guion de la lección

`correr.sh` recorre todo lo que queda de la lección: crea el clúster, lo mira, juega con los contextos, provoca los errores, lo borra, lo recrea y, al salir, lo borra otra vez. Su cabecera explica sus tres protecciones, y son las mismas que vas a usar en todo el curso:

```bash
# 🔴 SEGURIDAD, las tres protecciones de la lección:
#   1. KUBECONFIG apunta a un archivo TEMPORAL propio: tu ~/.kube/config ni se
#      lee ni se toca, y tus otros clústeres no se enteran.
#   2. Antes de cada kubectl que le habla al clúster, se comprueba que el
#      contexto activo es kind-curso-k8s-l1; si no, el guion se detiene.
#   3. Un trap borra al salir el clúster que ESTA corrida creó y el temporal,
#      aunque el guion falle a la mitad. Si al empezar ya existe un clúster
#      llamado curso-k8s-l1, se detiene sin tocarlo.
```

La tercera merece una explicación. `trap limpiar EXIT` le dice a Bash: «cuando este guion termine, por la razón que sea, corre `limpiar`». Si un comando falla a la mitad y `set -e` detiene el guion, `limpiar` corre igual y borra el clúster. Así no te queda un clúster olvidado gastando memoria. Pero `limpiar` solo borra si la variable `CREADO_AQUI` dice `si`, y esa variable se enciende **solo si el `kind create cluster` de esta corrida terminó bien**. Si ya había un `curso-k8s-l1` de antes, el guion se detiene al principio y no lo toca: ese clúster no es suyo. Y si otro proceso lo creó un instante después de esa comprobación, el `create` del guion falla con `node(s) already exist`, el guion se detiene y la variable sigue en `no`: tampoco lo toca.

La segunda protección es una función corta, la misma de la Lección 0:

```bash
contexto_correcto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    return 1
  fi
}
k() { contexto_correcto || exit 1; paso kubectl "$@"; }
```

Cada `kubectl` que le habla al clúster pasa por `k`, que primero pregunta el contexto. Los `kubectl config`, que solo leen o editan el archivo `kubeconfig` sin hablarle a ningún clúster, pasan por otra función, `kc`, sin comprobación. No la necesitan, y en la sección 1.7 el guion cambia de contexto a propósito.

#### 1.6.3 La creación

Antes de crear nada, el guion mira el `kubeconfig` temporal. Está vacío: no hay contextos ni contexto activo.

```text
$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]
```

Y crea el clúster. **Corrida real · Mac:**

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
 • Ensuring node image (kindest/node:v1.37.0) 🖼️  ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
 • Preparing nodes 📦 📦 📦   ...
 ✓ Preparing nodes 📦 📦 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
 • Joining worker nodes 🚜  ...
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-curso-k8s-l1"
You can now use your cluster with:

kubectl cluster-info --context kind-curso-k8s-l1

Have a nice day! 👋
(crear tardó 23 s)
```

Cada par de renglones es un paso. *Ensuring node image* busca la imagen del nodo y, si no está, la descarga; la primera vez en tu Mint este paso tarda lo que tarde bajar la imagen, y las siguientes es instantáneo. *Preparing nodes* crea los tres contenedores (un 📦 por nodo). *Writing configuration* escribe la configuración de `kubeadm`, la herramienta oficial que arma el clúster. *Starting control-plane* arranca el plano de control. *Installing CNI* pone la red entre Pods, `kindnet`. *Installing StorageClass* pone el almacenamiento por omisión. *Joining worker nodes* une los dos nodos de trabajo. Al final, `Set kubectl context to "kind-curso-k8s-l1"` es el renglón que más te importa en esta lección: kind escribió el contexto en tu `kubeconfig` (el temporal) y lo dejó activo. La frase de despedida cambia al azar en cada corrida.

Con la imagen ya descargada, crear tardó 23 segundos. Y ahora, la lección de la Lección 0: **la palomita no es la prueba**. La prueba tiene dos partes. La primera es esperar a que los nodos digan `Ready`:

```text
$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met
```

`kubectl wait` se queda esperando hasta que todos los nodos (`--all`) cumplan la condición `Ready`, o hasta que pasen 240 segundos. Pero tiene un punto ciego: espera a los nodos que **existen**. En el fallo de la Lección 0, los nodos de trabajo nunca llegaron a registrarse; ahí `kubectl wait --all` habría esperado a uno, habría dicho `condition met` una sola vez y habría terminado sin error. Por eso la segunda parte es **contar**:

```text
$ kubectl get nodes --no-headers | wc -l
3
```

`--no-headers` quita el renglón de títulos y `wc -l` cuenta los renglones que quedan: uno por nodo. Tiene que decir 3. El guion no se fía de leerlo: si no es 3, se detiene con `ALTO: el clúster tiene N nodos, no 3`. (En `correr.sh`, la espera y la cuenta van después de mirar el `kubeconfig`, en la sección 5 de su salida; aquí se cuentan juntas porque son la misma prueba.)

### 1.7 Contextos y `kubeconfig`

#### 1.7.1 Qué hay en un `kubeconfig`

La documentación lo define así: «un archivo que se usa para configurar el acceso a clústeres se llama archivo *kubeconfig*. Es una forma genérica de referirse a los archivos de configuración; no quiere decir que exista un archivo llamado `kubeconfig`» ([kubernetes.io, «Organizing Cluster Access Using kubeconfig Files»](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). Por omisión, `kubectl` busca uno llamado `config` en `$HOME/.kube`.

Un `kubeconfig` tiene tres listas y un puntero:

- **`clusters`**: a qué dirección hablarle y con qué certificado reconocer al servidor.
- **`users`**: con qué credencial presentarte.
- **`contexts`**: combinaciones con nombre de un clúster, un usuario y, opcionalmente, un espacio de nombres. La documentación: «cada contexto tiene tres parámetros: clúster, espacio de nombres y usuario. Por omisión, `kubectl` usa los parámetros del *contexto actual* para comunicarse con el clúster».
- **`current-context`**: el puntero. Cuál de los contextos usa `kubectl` cuando no le dices otro.

El guion lo mira justo después de crear el clúster:

```text
$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   

$ kubectl config view --minify
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://127.0.0.1:54589
  name: kind-curso-k8s-l1
contexts:
- context:
    cluster: kind-curso-k8s-l1
    user: kind-curso-k8s-l1
  name: kind-curso-k8s-l1
current-context: kind-curso-k8s-l1
kind: Config
users:
- name: kind-curso-k8s-l1
  user:
    client-certificate-data: DATA+OMITTED
    client-key-data: DATA+OMITTED

$ stat -c %A "$KUBECONFIG"
-rw-------
```

Cuatro cosas que leer:

- **El nombre del contexto es `kind-` más el nombre del clúster.** kind siempre los nombra así: el clúster `curso-k8s-l1` da el contexto `kind-curso-k8s-l1`, y el clúster por omisión `kind` da `kind-kind`. El clúster y el usuario del `kubeconfig` llevan el mismo nombre.
- **`get-contexts`** es la tabla corta. El asterisco de `CURRENT` marca el activo. `AUTHINFO` es el usuario. `NAMESPACE` vacío quiere decir `default`.
- **`view --minify`** muestra solo lo que usa el contexto activo. La dirección del servidor es `https://127.0.0.1:54589`: el puerto alto que Docker publicó en tu máquina para el `kube-apiserver` del nodo de control, en `127.0.0.1` por omisión. kind permite cambiar esa dirección con `networking.apiServerAddress`, pero su documentación desaconseja exponerlo a algo que no sea la interfaz local, y este curso no lo cambia. Los tres campos `DATA+OMITTED` son el certificado del servidor y **la credencial de administrador**. `kubectl` los oculta porque son secretos. Están completos en el archivo.
- **`stat -c %A`** da los permisos del archivo: `-rw-------`, solo tu usuario puede leerlo. kind lo crea así porque contiene esa credencial. Si alguna vez copias un `kubeconfig` a otro lado, conserva esos permisos. (En tu Mint, `ls -l "$KUBECONFIG"` dice lo mismo, junto con tu nombre de usuario.)

La documentación agrega una advertencia que vale para siempre: «usa solo archivos `kubeconfig` de fuentes confiables. Un archivo `kubeconfig` hecho a propósito podría provocar la ejecución de código malicioso o exponer archivos. Si tienes que usar uno que no es de confianza, revísalo con cuidado antes, como revisarías un guion de *shell*». Un `kubeconfig` puede pedir que se ejecute un programa para obtener la credencial: por eso se lee antes de usarlo.

#### 1.7.2 Dos contextos, y el error sin mensaje

La Lección 0 describió el error más peligroso de `kubectl`: hablarle al clúster equivocado, sin que nada te avise. El guion lo arma a propósito, solo dentro del `kubeconfig` temporal. Agrega un segundo contexto, `otro`, con una credencial de mentira y una dirección donde no hay nadie, `127.0.0.1:1`, y lo deja activo:

```text
$ kubectl config set-cluster otro --server=https://127.0.0.1:1
Cluster "otro" set.

$ kubectl config set-credentials nadie --token=token-de-mentira
User "nadie" set.

$ kubectl config set-context otro --cluster=otro --user=nadie
Context "otro" created.

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   
          otro                otro                nadie               

$ kubectl config use-context otro
Switched to context "otro".
```

Fíjate en el orden. Los tres `set-…` arman un clúster, un usuario y un contexto que los junta, en ese orden. `get-contexts` muestra los dos contextos, con el asterisco todavía en el de kind. `use-context otro` mueve el puntero. A partir de ahí, cualquier `kubectl` sin más va a `otro`. Lo que dice la comprobación:

```text
$ (la comprobación del contexto, antes de un kubectl get nodes)
ALTO: el contexto activo es «otro», no «kind-curso-k8s-l1». No sigo.
[el guion NO corre kubectl get nodes: se detuvo a tiempo]

(Sin la comprobación, kubectl le habla a «otro»:)
```

Y lo que pasa si no compruebas:

```text
$ kubectl get nodes --request-timeout=5s
E1021 07:11:02.007697   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.007948   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009279   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009582   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.010566   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
The connection to the server 127.0.0.1:1 was refused - did you specify the right host or port?
[código de salida: 1]
```

Los renglones que empiezan con `E1021 … memcache.go:381` los escribe el propio cliente de `kubectl`, no el clúster: la `E` es el nivel de error, `1021` el mes y el día, y `memcache.go` es el código con el que `kubectl` guarda en memoria la lista de recursos que ofrece un servidor. Antes de ejecutar tu comando, `kubectl` le pregunta al servidor qué recursos tiene, y aquí esa pregunta falló cinco veces porque no había nadie escuchando. Es ruido repetido, y lo que importa es el último renglón.

Aquí hubo suerte, porque `otro` no existe y el error es ruidoso. Lee el último renglón: dice **a qué servidor** intentó hablarle, `127.0.0.1:1`, y no es el de tu clúster, que estaba en `127.0.0.1:54589`. Si `otro` fuera un clúster de verdad, la respuesta habría sido una lista de nodos ajenos, sin un solo error. El ejercicio de leer **a quién** le hablaste es el mismo en los dos casos.

Hay una forma de no depender del puntero: decirle a cada comando a qué contexto va, con `--context`.

```text
$ kubectl --context kind-curso-k8s-l1 get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

Con `otro` activo, este comando le habló a kind, porque la bandera manda sobre el `current-context` del archivo. Según la documentación, el contexto se elige con «el primer acierto» de esta cadena: primero la bandera `--context`, después el `current-context` de los archivos ([kubernetes.io, «Organizing Cluster Access…»](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). En guiones que se comparten, poner `--context` en cada comando es una protección tan buena como comprobar el contexto antes. El curso usa la comprobación porque, además, te enseña el hábito.

El guion deja todo como estaba: vuelve a `kind-curso-k8s-l1` con `use-context` y borra el contexto, el clúster y el usuario de mentira con `delete-context`, `delete-cluster` y `delete-user`. Cada uno respondió `deleted … from /tmp/curso-k8s-l1.LWx1/kubeconfig`. Ese renglón también te dice **qué archivo** se modificó, y ahí se ve que fue el temporal.

#### 1.7.3 `KUBECONFIG` como lista

Una cosa más que conviene saber, aunque el curso no la use. `KUBECONFIG` puede tener **varios archivos**, separados por dos puntos en Linux. `kubectl` los junta en uno. Para los valores que se repiten, gana el primer archivo que los define. En particular, gana el `current-context` del primer archivo que lo tiene ([kubernetes.io, «Organizing Cluster Access…»](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). Y cuando `kubectl` crea un valor nuevo, lo escribe en el primer archivo de la lista que exista ([kubernetes.io, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/)). Es útil y es una trampa: con dos archivos en la lista, un `use-context` puede cambiar un archivo que no esperabas. Con un solo archivo temporal por clúster, como en este curso, no hay dudas.

### 1.8 Mirar el clúster

Con el contexto comprobado, el guion mira el clúster desde cuatro lados. Primero, desde Kubernetes:

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l1-control-plane   Ready    control-plane   31s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker          Ready    <none>          16s   v1.37.0   172.18.0.6    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0   172.18.0.7    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

Tres nodos `Ready`, versión `v1.37.0`, con el runtime `containerd://2.3.4`. El de control es 15 segundos más viejo que los otros dos: se creó primero y los de trabajo se unieron después. La columna `ROLES` dice `control-plane` para uno y `<none>` para los de trabajo. No es un error: `ROLES` sale de las etiquetas `node-role.kubernetes.io/…` de cada nodo, y al crear el clúster solo el nodo de control recibe una (`control-plane`). `INTERNAL-IP` son direcciones de la red `kind` de Docker, `172.18.0.x`, que en tu máquina serán otras. Y `KERNEL-VERSION` dice el núcleo de la máquina que corre Docker, el mismo para los tres.

```text
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:54589
CoreDNS is running at https://127.0.0.1:54589/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

`cluster-info` responde la pregunta «¿a qué le estoy hablando?» con la dirección del servidor. Es la misma de `view --minify`. Si alguna vez dudas de tu contexto, este comando te dice la dirección real.

Segundo, desde kind y desde Docker:

```text
$ kind get nodes --name curso-k8s-l1
curso-k8s-l1-worker
curso-k8s-l1-control-plane
curso-k8s-l1-worker2

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l1-worker          kindest/node:v1.37.0   
curso-k8s-l1-control-plane   kindest/node:v1.37.0   127.0.0.1:54589->6443/tcp
curso-k8s-l1-worker2         kindest/node:v1.37.0   
```

`kind get nodes --name` lista los contenedores de **ese** clúster, sin un orden fijo. Existe también `kind get clusters`, que lista todos los clústeres de kind de tu máquina: es útil para saber si hay otros, pero no lo uses para decidir qué borrar sin leer cada nombre. `docker ps` con el filtro de la etiqueta `io.x-k8s.kind.cluster` muestra los mismos tres contenedores. Solo uno publica puerto: el de control, `127.0.0.1:54589->6443/tcp`. Ese es el camino de `kubectl` al `kube-apiserver`, que escucha en el 6443 dentro del nodo. Los de trabajo no publican nada, y nadie fuera de tu máquina puede hablarle a tu clúster.

Tercero, lo que corre dentro, sin tocar nada:

```text
$ kubectl get pods -n kube-system -o wide
NAME                                                 READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-27jlk                             1/1     Running   0          23s   10.244.0.4   curso-k8s-l1-control-plane   <none>           <none>
coredns-559f6c778d-fd4kh                             1/1     Running   0          23s   10.244.0.2   curso-k8s-l1-control-plane   <none>           <none>
etcd-curso-k8s-l1-control-plane                      1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-n44qw                                        1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kindnet-rf64g                                        1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-xsc6h                                        1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-apiserver-curso-k8s-l1-control-plane            1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-controller-manager-curso-k8s-l1-control-plane   1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-proxy-hxjzg                                     1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kube-proxy-jp497                                     1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-proxy-m4r92                                     1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-scheduler-curso-k8s-l1-control-plane            1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
```

Son las piezas de la Lección 0, ahora repartidas en tres nodos. La columna `NODE` lo cuenta. El plano de control (`etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`) vive solo en el nodo de control. `kube-proxy` y `kindnet` hay **uno por nodo**, tres de cada uno: son las piezas que cada máquina necesita para la red. Y la columna `IP` tiene dos tipos de dirección. Los Pods del sistema que usan la red del nodo tienen la `172.18.0.x` de su nodo. Los dos `coredns` tienen `10.244.0.x`, direcciones de la red **de Pods** que puso `kindnet`. La Lección 3 vuelve a esto.

Cuarto, el almacenamiento que kind instaló:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  29s
```

Una clase de almacenamiento, `standard`, marcada como la de omisión. Guarda los datos en el disco del propio nodo. Es el renglón `Installing StorageClass` de la creación, y la Lección 8 la usa.

### 1.9 Borrar, recrear y recuperar

#### 1.9.1 Perder el contexto

Pasa más de lo que crees: alguien limpia su `kubeconfig`, o borra un contexto pensando en otro. El clúster sigue vivo, pero `kubectl` ya no sabe llegar a él. El guion lo provoca:

```text
$ kubectl config delete-context kind-curso-k8s-l1
warning: this removed your active context, use "kubectl config use-context" to select a different one
deleted context kind-curso-k8s-l1 from /tmp/curso-k8s-l1.LWx1/kubeconfig

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE
```

`kubectl` avisa que borraste el contexto **activo**. La tabla queda vacía. El clúster no se enteró: sus tres contenedores siguen corriendo. Lo que se perdió es el camino. kind sabe reconstruirlo, porque el clúster guarda su propia configuración:

```text
$ kind export kubeconfig --name curso-k8s-l1
Set kubectl context to "kind-curso-k8s-l1"

$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

`kind export kubeconfig` vuelve a escribir el contexto del clúster en el `kubeconfig` que indique `KUBECONFIG` y lo deja activo. Su hermano, `kind get kubeconfig --name curso-k8s-l1`, no escribe nada: según su propia ayuda, «imprime el kubeconfig del clúster» en la pantalla. Un `kubeconfig` impreso es una credencial impresa, así que ese comando no se corre con alguien mirando ni se pega en un chat.

#### 1.9.2 Borrar

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
Deleted nodes: ["curso-k8s-l1-worker" "curso-k8s-l1-control-plane" "curso-k8s-l1-worker2"]
(borrar tardó 1 s)

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'
```

Un segundo. Borrar un clúster de kind es borrar tres contenedores, y kind además quita del `kubeconfig` lo que había escrito: el contexto ya no existe y el puntero quedó vacío. Si ahora corrieras `kubectl get nodes`, verías el error `localhost:8080` que la Lección 0 te enseñó a leer. `docker ps` con el filtro no devuelve nada.

**Siempre con `--name`.** Sin él, kind borra el clúster que se llama `kind`, el de omisión: «si omites `--name`, kind usará el nombre de contexto por omisión, `kind`, y borrará ese clúster» ([kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/)). Si tienes un clúster `kind` de otro curso, se va.

Y una rareza útil: borrar un clúster que **no existe** no es un error. El guion lo hace a propósito, justo después de borrarlo:

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
```

Sin `Deleted nodes` y sin error. La guía de kind lo explica: «por diseño, pedir borrar un clúster que no existe no devuelve un error». Por eso puedes ponerlo al principio de un guion, «por si acaso». Pero también quiere decir que si escribes mal el nombre, kind no te avisa: dice `Deleting cluster` y no borra nada. El renglón `Deleted nodes` es la prueba de que borró algo.

#### 1.9.3 Recrear

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
…
Set kubectl context to "kind-curso-k8s-l1"
…
(recrear tardó 26 s)

$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met

$ kubectl get nodes --no-headers | wc -l
3

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

(Se omitieron los pasos intermedios de kind, iguales a los de 1.6.3; están completos en `correr.salida.txt`.)

Veintiséis segundos, y el clúster está como nuevo, con sus tres nodos contados. Esto cambia tu forma de trabajar en el resto del curso. Un clúster que se rehace en medio minuto **no se repara**: si lo dejaste en un estado que no entiendes, lo borras y lo recreas. Lo que no se pierde es lo que está en archivos: `kind-curso.yaml` y, desde la Lección 2, tus manifiestos. Es la idea de la Lección 0 llevada al clúster entero: el archivo es la verdad.

Al terminar, el guion sale y el `trap` borra el clúster recreado y la carpeta temporal. En la máquina de las corridas, después de salir, `docker ps` no mostraba ningún contenedor de `curso-k8s-l1` y la carpeta `/tmp/curso-k8s-l1.*` ya no existía.

## El error que vas a ver

Esta lección tiene tres errores con mensaje y uno sin mensaje.

**1. `ERROR: failed to create cluster: node(s) already exist`.** Crear un clúster con un nombre que ya existe:

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "curso-k8s-l1"
[código de salida: 1]
```

Se lee literal: ya hay nodos, es decir, contenedores, de un clúster con ese nombre. kind no lo reemplaza ni lo repara. Antes de hacer nada, pregúntate **de quién es**. Si es tuyo, de una corrida anterior que se quedó viva, `kind delete cluster --name curso-k8s-l1` y vuelves a crear. Si no sabes de quién es, no lo borras: es el caso de una máquina compartida, y por eso el guion del curso se detiene en lugar de borrarlo.

**2. `kubectl: FAILED`.** Lo viste en 1.3.4: la suma del binario no coincide con la publicada. No se instala. Se baja otra vez el binario **y** su suma, con la misma versión en las dos direcciones.

**3. `The connection to the server 127.0.0.1:1 was refused`.** Lo viste en 1.7.2: `kubectl` le habló a un servidor donde no hay nadie. El dato está en la dirección del último renglón. Compárala con la de `kubectl cluster-info` de tu clúster: si no coinciden, tu contexto no es el que crees. Si la dirección es `localhost:8080`, no hay contexto activo (Lección 0).

**4. El error sin mensaje: los nodos que nunca llegaron.** Con `max_user_instances = 128`, kind imprime todas sus palomitas, incluida `✓ Joining worker nodes`, y aun así los nodos de trabajo no se unen. Los registros dicen `inotify_init: too many open files`. Ese error **no se reprodujo en esta lección**: hacerlo exigía bajar el límite de una máquina compartida donde otros clústeres corrían en ese momento, y bajarlo los habría tumbado. Ya lo midió la Lección 0, en 0.6.3, con sus mensajes reales. Aquí se previene: se mide y se ajusta antes (1.4), y después de crear se espera a `Ready` con `kubectl wait` y se **cuentan** los nodos con `kubectl get nodes --no-headers | wc -l`, porque `wait` solo espera a los que existen (1.6.3). Si la cuenta no da 3, las pistas que dejó la Lección 0 son dos: `kubectl get pods -n kube-system` muestra algún `kube-proxy` en `Error`, y `kubectl logs -n kube-system` de ese Pod dice `too many open files`. Entonces se borra el clúster, se mide y se ajusta `inotify` (1.4) y se crea otra vez.

## El hábito de seguridad de la lección

La tabla de hábitos del curso le asigna a esta lección tres:

**Binarios con suma de verificación.** Lo que corre con tu usuario y con `sudo` se baja del origen oficial, con la versión escrita y la suma comprobada antes de instalar. Un binario sin origen ni suma, como el que llega por chat, no se instala, aunque «funcione». Y se instala con dueño `root` y permiso `0755`, para que ningún programa que corra como tú pueda reemplazarlo.

**La imagen del nodo fijada.** La imagen de cada nodo va por su huella, no por su etiqueta. Es el mismo hábito que la suma, aplicado a lo que Docker descarga.

**Comprobar el contexto antes de cada comando que cambia algo.** Un `kubeconfig` temporal y propio para el curso, para que kind no cambie tu contexto de siempre. `kubectl config current-context` antes de actuar, o `--context` en cada comando. Y el `kubeconfig` tratado como lo que es, una credencial de administrador: permisos `600`, nunca en un chat ni en un repositorio, y solo de fuentes en las que confías.

Lo que evitan los tres juntos es lo de la escena: no saber qué corre en tu máquina, ni contra qué clúster.

## Lo que se hace mal

**Bajar «la última».** Un `curl` a `latest` o a `stable.txt` te da hoy una versión y mañana otra. Las salidas del curso dejan de coincidir y no sabes por qué. Se escribe la versión.

**Bajar el binario y la suma por separado, con comandos distintos.** Es el caso 1 de 1.3.4: dos versiones mezcladas y un `FAILED` que parece un ataque. Se bajan juntos, con la misma versión escrita una sola vez.

**Saltarse la suma «porque es el sitio oficial».** La suma comprueba lo que llegó a tu disco, no lo que hay en el servidor. Una descarga cortada pesa menos, corre a veces y falla de formas raras. La suma cuesta un comando.

**`sudo mv` de un binario de tu usuario.** Queda en el `PATH` con tu usuario como dueño, y cualquier programa que corra como tú puede reemplazarlo. `install -o root -g root -m 0755`.

**Subir `inotify` con `sysctl` y olvidarlo.** Funciona hasta el siguiente reinicio. Después el clúster falla y ya nadie recuerda por qué. El ajuste va en un archivo de `/etc/sysctl.d/`, con un comentario.

**Crear el clúster en tu `~/.kube/config` de siempre.** kind cambia tu contexto activo sin preguntar. El siguiente `kubectl` que teclees en otra ventana, pensando en el clúster del trabajo, le va a hablar al de kind, o al revés. Un `KUBECONFIG` temporal por clúster.

**`kind delete cluster` sin `--name`.** Borra el clúster `kind`, que puede no ser el tuyo. Y como borrar uno que no existe no da error, un nombre mal escrito tampoco te avisa. Se lee el renglón `Deleted nodes`.

**Reparar un clúster de kind.** Si lo dejaste en un estado que no entiendes, lo borras y lo recreas en medio minuto. Lo que importa vive en archivos.

## Ejercicios

Los ejercicios 1 y 2 se contestan con las salidas de la lección. El 3 necesita tu Mint con `kubectl` y `kind` instalados. El 4 necesita el clúster. Anota tus respuestas en la [bitácora](bitacora.md) antes de mirar las soluciones.

### Ejercicio 1 — ¿Qué pasó con este binario?

Una compañera corrió esto y te pide ayuda:

```text
$ curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256
$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

1. Da una causa probable que **no** sea un ataque, y explica cómo la comprobarías.
2. ¿Qué cambiarías en los dos comandos para que esto no pase?
3. ¿Instala el binario mientras lo averigua? ¿Por qué?

### Ejercicio 2 — Lee el `kubeconfig`

Con la salida de `kubectl config view --minify` de 1.7.1, contesta:

1. ¿Qué dirección y qué puerto usa `kubectl` para llegarle al clúster? ¿Dónde más aparece ese puerto en la lección?
2. ¿Cómo se llaman el clúster, el usuario y el contexto, y qué relación tienen con el nombre que le diste a kind?
3. ¿Qué hay detrás de `DATA+OMITTED`, y por qué `kubectl` lo esconde?
4. Si alguien te manda su `kubeconfig` por chat «para que veas mi clúster», ¿qué haces antes de usarlo?

### Ejercicio 3 — Predice y mide `inotify`

Sin correr nada, predice qué dirá `./fig01_04.sh` en tu Mint recién instalada, antes de cualquier ajuste. Después, córrelo. Ajusta con `sudo ./fig01_04.sh --ajustar` y córrelo otra vez sin argumentos. Luego contesta:

1. ¿Coincidió tu predicción? ¿Qué valores salieron antes y después?
2. ¿Dónde quedó escrito el ajuste, y qué comando te lo demuestra?
3. Si reinicias la máquina, ¿qué valor esperas, y por qué?

### Ejercicio 4 — Dos clústeres, dos contextos (proyecto)

En una terminal con `KUBECONFIG` temporal (1.6.1), crea el clúster del curso con `kind-curso.yaml`. En **el mismo** `KUBECONFIG`, crea otro clúster de un solo nodo con `kind create cluster --name curso-k8s-l1b` (sin archivo de configuración). Luego:

1. ¿Cuál quedó como contexto activo? Predícelo antes de mirar con `kubectl config get-contexts`.
2. Sin cambiar el contexto activo, muestra los nodos de **cada** clúster.
3. Borra **solo** `curso-k8s-l1b` y comprueba que el clúster del curso sigue vivo y que puedes volver a hablarle.
4. Al terminar, borra el clúster del curso y comprueba con `docker ps` que no quedó ningún contenedor de ninguno de los dos.

Cuando lo hayas hecho a mano, compara con `programas/01-instalacion-primer-cluster/ejercicio4.sh`, que hace los cuatro pasos con las protecciones de `correr.sh`, y con su salida, `ejercicio4.salida.txt`. (El segundo clúster usa la imagen de nodo por omisión de kind v0.33.0, sin huella: es un clúster de usar y tirar, no el del curso.)

## Soluciones

### Solución 1

1. **Dos versiones distintas.** El binario salió de lo que dijera `stable.txt` en ese momento, y la suma está fija en v1.37.1. Si `stable.txt` ya dice otra versión, son archivos de versiones distintas y la suma no puede coincidir. Se comprueba con `curl -L -s https://dl.k8s.io/release/stable.txt`: si no dice `v1.37.1`, ahí está la causa. Otra causa posible es una descarga cortada; `ls -l kubectl` contra el tamaño esperado (61,886,626 bytes para v1.37.1 en `amd64`) lo muestra.
2. Escribir la versión **una vez**, en una variable, y usarla en las dos direcciones, como `fig01_01.sh`: `KUBECTL_VERSION=v1.37.1`, y `…/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl` y `…/kubectl.sha256`.
3. **No.** Un `FAILED` no dice si el archivo es de otra versión o si está alterado; los dos casos se ven iguales (1.3.4). Hasta que una suma diga `OK`, el binario no entra a `/usr/local/bin`.

### Solución 2

1. `https://127.0.0.1:54589`. El mismo puerto aparece en `kubectl cluster-info` y en la columna `PORTS` de `docker ps`: `127.0.0.1:54589->6443/tcp`, el puerto que Docker publicó en tu máquina para el `kube-apiserver`, que dentro del nodo escucha en el 6443. En tu corrida será otro.
2. Los tres se llaman `kind-curso-k8s-l1`: `kind-` más el nombre que le diste con `--name`. kind siempre los nombra así.
3. El certificado con el que `kubectl` reconoce al servidor (`certificate-authority-data`) y **la credencial de administrador** del clúster (`client-certificate-data` y `client-key-data`). `kubectl` los oculta porque quien tenga esos datos es administrador del clúster.
4. Lo lees completo antes de usarlo, como un guion: la documentación advierte que un `kubeconfig` hecho a propósito puede ejecutar código. Lo usas en un `KUBECONFIG` temporal, no lo mezclas con el tuyo, y le recuerdas a quien te lo mandó que acaba de compartir una credencial.

### Solución 3

1. Lo esperable en Mint 22, basada en Ubuntu 24.04: `fs.inotify.max_user_instances = 128` y `FALTA AJUSTAR`. Las vigilancias dependen de tu sistema y de tu memoria, así que pueden salir distintas de las 8192 que menciona la guía de kind para Ubuntu. Después de ajustar: 512 instancias, al menos 524288 vigilancias y `LISTO`. En la máquina virtual de las corridas, también un Ubuntu 24.04, las vigilancias ya eran 1048576. Si tu primera medición ya dijo `LISTO`, alguien lo ajustó antes; busca dónde con la pregunta 2.
2. En `/etc/sysctl.d/99-kind-inotify.conf`. Lo demuestran `cat /etc/sysctl.d/99-kind-inotify.conf` y `grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/`, que debe encontrar las líneas de ese archivo (dos, o solo la de instancias si tus vigilancias ya eran más altas) y ninguna en otro. Si aparece otra en `/etc/sysctl.conf`, esa gana al reiniciar (1.4.3).
3. 512 instancias, y vigilancias de al menos 524288: al arrancar, `systemd-sysctl` lee `/etc/sysctl.d/*.conf` y aplica el archivo, salvo que `/etc/sysctl.conf` fije otro valor. Si lo hubieras subido solo con `sudo sysctl …`, volvería a 128, como habría pasado con la máquina virtual de las corridas.

### Solución 4

Las cuatro respuestas se midieron con `ejercicio4.sh` (`ejercicio4.salida.txt`).

1. **`kind-curso-k8s-l1b`**, el último que se creó: kind deja activo el contexto del clúster que acaba de crear. `get-contexts` muestra los dos, con el asterisco en `kind-curso-k8s-l1b`. Esta es exactamente la trampa del contexto: el clúster del curso sigue ahí, pero ya no es al que le hablas.
2. Con `--context`, que manda sobre el contexto activo:

   ```bash
   kubectl --context kind-curso-k8s-l1 get nodes
   kubectl --context kind-curso-k8s-l1b get nodes
   ```

   El primero muestra tres nodos y el segundo uno, `curso-k8s-l1b-control-plane`, con `ROLES control-plane` y `v1.37.0`.
3. `kind delete cluster --name curso-k8s-l1b`. Debe decir `Deleted nodes: ["curso-k8s-l1b-control-plane"]`. kind quita su contexto del `kubeconfig`, y el puntero queda vacío porque ese era el activo. `kubectl config get-contexts` muestra solo `kind-curso-k8s-l1`, sin asterisco. `kubectl config use-context kind-curso-k8s-l1` y `kubectl get nodes` muestran los tres nodos del curso.
4. `kind delete cluster --name curso-k8s-l1` y luego `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` y lo mismo con `curso-k8s-l1b`. Las dos respuestas deben estar vacías, y en la corrida lo estuvieron.

## Cómo sé que lo logré

- [ ] `kubectl version --client` dice `Client Version: v1.37.1` y `Kustomize Version: v5.8.1`, y `kind version` dice `kind v0.33.0 go1.26.7 linux/amd64`.
- [ ] `command -v kubectl kind` dice `/usr/local/bin/kubectl` y `/usr/local/bin/kind`, y `ls -l` los muestra con dueño `root root` y permisos `-rwxr-xr-x`.
- [ ] Corres `./fig01_01.sh` en una carpeta nueva y obtienes `kubectl: OK` y `kind-linux-amd64: OK`, con las dos sumas de 1.3.3 (en un equipo ARM, las del lanzamiento para `arm64`).
- [ ] `./fig01_04.sh` termina en `LISTO`, su `grep` encuentra las líneas de `/etc/sysctl.d/99-kind-inotify.conf` y ninguna en `/etc/sysctl.conf`.
- [ ] Corres `./correr.sh` y compruebas contra `correr.salida.txt` lo que no cambia entre corridas: el `kubeconfig` vacío al principio; los tres nodos `Ready` y contados (`3`) con `v1.37.0`, `Debian GNU/Linux 13 (trixie)` y `containerd://2.3.4`, con `ROLES <none>` en los de trabajo; un solo contenedor que publica puerto, `127.0.0.1:<puerto>->6443/tcp`; la clase `standard (default)`; `512` en los tres nodos; el `ALTO` de la comprobación con el contexto `otro`; el error `node(s) already exist`; el contexto recuperado con `kind export kubeconfig`; `error: current-context is not set` después de borrar; y tres nodos `Ready` después de recrear. Las edades, las IP, el puerto, los sufijos de los Pods, el orden de los nodos en `kind get nodes` y `docker ps`, la frase de despedida de kind, los tiempos, los conteos de `inotify` y la ruta temporal cambian en cada corrida: se observan, no se comparan.
- [ ] Al terminar `correr.sh`, `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` no devuelve nada.

## Resumen

Responde sin mirar la lección:

1. ¿Por qué el curso instala `kubectl` y `kind` como binarios y no con `apt` o `snap`?
2. ¿Qué demuestra una suma `sha256` que coincide, y qué no demuestra?
3. ¿Qué dos causas comunes producen `kubectl: FAILED`, y qué haces en los dos casos?
4. ¿Qué es `inotify`, y por qué tres nodos de kind lo agotan cuando un nodo solo no?
5. ¿Cuál es la diferencia entre `sudo sysctl fs.inotify.max_user_instances=512` y un archivo en `/etc/sysctl.d/`?
6. ¿Qué tres listas y qué puntero tiene un `kubeconfig`?
7. ¿Para qué sirve exportar `KUBECONFIG` hacia un archivo temporal antes de crear el clúster?
8. ¿Qué gana cuando hay `--context` en el comando y otro `current-context` en el archivo?
9. ¿Qué responde kind si borras un clúster que no existe, y por qué eso es a la vez cómodo y peligroso?
10. Perdiste el contexto, pero el clúster sigue vivo. ¿Con qué comando lo recuperas?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Install and Set Up kubectl on Linux»](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/): la descarga del binario y de su suma, la comprobación con `sha256sum --check` y sus mensajes `OK` y `FAILED`, el `install -o root -g root -m 0755` y la regla de una versión menor de diferencia.
- [Kubernetes, «Version Skew Policy»](https://kubernetes.io/releases/version-skew-policy/) y [«Kubernetes Release Cycle»](https://kubernetes.io/releases/release/): qué versiones de `kubectl` sirven con qué clúster, y el ritmo de versiones.
- [Kubernetes, «Organizing Cluster Access Using kubeconfig Files»](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/): qué es un `kubeconfig`, qué es un contexto, `KUBECONFIG` como lista, las reglas para juntar archivos, cómo se elige el contexto y la advertencia sobre archivos de fuentes no confiables.
- [Kubernetes, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/): los subcomandos de `kubectl config` y el orden en que `kubectl` carga los archivos.
- [kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/): la instalación desde el binario del lanzamiento, la creación con `--name` y con archivo de configuración, la imagen por su suma `sha256`, el borrado sin `--name` y que borrar un clúster inexistente no es un error.
- [kind, «Known Issues», «Pod errors due to too many open files»](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files): los límites de `inotify`, los valores de Ubuntu y los recomendados.
- [kind v0.33.0, página del lanzamiento](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0): los binarios con su `.sha256sum` y la imagen de nodo `kindest/node:v1.37.0` con su huella.
- [man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html): qué es `inotify` y qué limitan `max_user_instances` y `max_user_watches`.
- [man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html): las carpetas que se leen al arrancar y el orden en que se aplican.
- [Linux Mint 22, notas de la versión](https://www.linuxmint.com/rel_wilma.php): Mint 22 se basa en Ubuntu 24.04.

---

**Anterior:** [Lección 0 — Qué es Kubernetes y qué NO es kind](00-que-es-kubernetes.md) · **Siguiente:** [Lección 2 — Pods y Deployments](02-pods-deployments.md)
