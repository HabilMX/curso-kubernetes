# Lección 6 — Entrar al clúster

Jueves, 4:40 de la tarde. El equipo de operación quiere ver el reporte del `revisor` desde su propio tablero, que corre en otra máquina, fuera del clúster, y la presentación con la dirección es a las 5:30. En el chat del equipo ya hay dos propuestas. La primera: «cámbiale el Service a `NodePort` y les pasas la IP de un nodo». La segunda viene con un enlace a un tutorial de hace dos años: «instala `ingress-nginx`, son tres comandos». Las dos funcionan esta tarde. La primera deja el `revisor` abierto en un puerto al azar de **todos** los nodos, sin que nadie lo haya decidido por escrito. La segunda instala un componente que dejó de recibir parches de seguridad en marzo de 2026. Y hay una tercera tentación, la del README de kind: un programa que se corre en tu máquina y le da balanceadores a tus clústeres… a **todos** tus clústeres de kind, incluidos los de tus compañeros si comparten la máquina.

Esta lección te enseña a abrir una puerta hacia el clúster sin esos atajos: un `LoadBalancer` con MetalLB y una puerta con nombre con Gateway API y Envoy Gateway, los dos instalados **dentro** de tu clúster, para que se vayan con él cuando lo borres. Y te enseña algo que vale para todo lo que instales en Kubernetes de aquí en adelante: hay piezas que son **plataforma** y piezas que son **proyecto**, y la plataforma tiene que estar lista antes de que el proyecto la use.

**Tiempo:** 2 × 45 min

**Qué construyes:** el `revisor` publicado hacia afuera del clúster, primero con un Service `LoadBalancer` que recibe la IP `172.18.255.200` y después por una puerta nombrada, el Gateway `revisor`, con su ruta hacia el Service de siempre

**Qué aprendes:** por qué un `LoadBalancer` se queda en `<pending>` en kind y qué abre aunque esté pendiente (un `NodePort` en cada nodo); qué hace MetalLB en capa 2 y por qué su rango sale de la red `kind` de Docker; qué son los recursos personalizados (CRD) y los *webhooks* de admisión, y por qué obligan a instalar en orden; Gateway API con sus tres piezas, `GatewayClass`, `Gateway` y `HTTPRoute`, servidas por Envoy Gateway; por qué no se usa Cloud Provider KIND en una máquina compartida; `Ingress` como API congelada y por qué no `ingress-nginx`; y qué queda expuesto, por dónde y sin qué (cifrado en tránsito)

**De dónde vienes.** De la [Lección 5](05-salud-recursos-apagado.md): el `revisor` corre con tres réplicas, con sus sondas de arranque, de disponibilidad y de vida, con `requests` y `limits`, con su `ConfigMap` como variables y su token como archivo, todo aplicado con `kubectl apply -k .`. El servicio de prueba también se vigila. De la [Lección 3](03-services-dns.md) traes la regla de que todo nace como `ClusterIP` y nada se publica porque sí, y el orden para diagnosticar un Service que no responde: el código de `curl`, el nombre, la columna `ENDPOINTS`. Hoy esa regla se rompe por primera vez, a propósito y por escrito.

**Qué no hace esta lección.** No pone cifrado: la puerta habla HTTP plano en el puerto 80, y la sección del hábito de seguridad lo mide y lo dice. No cierra todavía quién le habla a quién **dentro** del clúster: eso es la [Lección 7](07-aislar-permisos-red.md), que además retira el `LoadBalancer` directo y deja el Gateway como la única puerta. No te da un nombre de dominio ni un balanceador de verdad de un proveedor de nube: las IP que reparte MetalLB aquí solo existen en la red `kind` de Docker de tu máquina. Y el `revisor` sigue en el espacio de nombres `default`; la mudanza a su propio espacio es de la Lección 7.

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1, la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, **MetalLB v0.16.1** y **Envoy Gateway v1.9.2** (que trae Gateway API v1.6.1), en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l6`. La máquina fue una Mac con procesador ARM y Docker Engine 29.2.1 dentro de una máquina virtual Linux (Colima), **no** Linux Mint, que es el sistema de referencia del curso. Lo que cambia en tu Mint: la arquitectura, las IP de los Pods, de los Services y de los nodos (`172.18.0.2` a `.4`, en otro orden), los `NodePort` que el clúster elige al azar, los sufijos de los nombres, las edades y el nodo desde donde MetalLB anuncia cada IP. Las dos IP de MetalLB, `172.18.255.200` y `172.18.255.201`, **sí** deben salirte idénticas si tu red `kind` es `172.18.0.0/16`. Y hay una diferencia que importa: en la Mac, la red `kind` vive dentro de la máquina virtual y tu terminal no la alcanza (lo verás en el hábito de seguridad: código 28); en Linux, Docker conecta tu máquina a esa red, así que en tu Mint `curl http://172.18.255.200/salud` desde tu terminal debería responder. Para que el ejemplo sea el mismo en los dos sistemas, el «cliente de fuera» de esta lección es un contenedor de Docker conectado a la red `kind`, fuera del clúster. El recorrido completo está en [`programas/06-entrar-al-cluster/`](../programas/06-entrar-al-cluster): `correr.sh` crea el clúster, le carga las dos imágenes, recorre la lección en orden, corre los Ejercicios 1 a 3 y borra el clúster. Al final repite, en un clúster nuevo, los tres pasos de 6.9 con `levantar.sh`. La corrida completa, con los dos clústeres, tardó 15 minutos y 20 segundos (920 segundos): crear el primer clúster y esperar a que estuviera listo fueron 40 segundos, crear el segundo, 46, borrar el primero, 1, y `levantar.sh` tardó 266. Su salida es `correr.salida.txt`. Necesita internet: los manifiestos de MetalLB y de Envoy Gateway se descargan de sus lanzamientos, fijados a su versión, y sus imágenes se descargan la primera vez.

## Al terminar vas a poder

- Explicar por qué un Service `LoadBalancer` se queda en `<pending>` en kind, y demostrar con `curl` que aun así ya abrió un `NodePort` en cada nodo.
- Instalar MetalLB dentro de un clúster, darle un rango de IP sacado de la red `kind` y leer en los eventos del Service quién asignó la IP y desde qué nodo se anuncia.
- Distinguir una pieza de **plataforma** (CRD, controladores, *webhooks*) de una pieza de **proyecto**, y aplicarlas en tres pasos: plataforma, espera con `kubectl wait`, proyecto.
- Reconocer los errores de aplicar fuera de orden: `no matches for kind … ensure CRDs are installed first` y `failed calling webhook … connection refused`.
- Escribir un `Gateway` y una `HTTPRoute` para el `revisor`, y leer su estado (`PROGRAMMED`, `Accepted`, `ResolvedRefs`).
- Provocar una ruta hacia un Service que no existe, reconocerla por `ResolvedRefs=False BackendNotFound` y por el `500` de la puerta, y corregirla.
- Decir qué queda expuesto después de esta lección, por qué puerta, y qué le falta (cifrado en tránsito), y explicar por qué no Cloud Provider KIND ni `ingress-nginx`.

## El porqué antes del cómo

Hasta ahora, todo lo que le habló al `revisor` estaba **dentro** del clúster: el Pod `depurar`, el propio `revisor` consultando a `prueba`, las sondas del `kubelet`. Tú entrabas por un túnel temporal, `port-forward`, que dura lo que dura tu comando y le habla a un solo Pod. Eso basta para mirar. No basta para el tablero de operación de la escena, que necesita una dirección estable, que sobreviva a los *rollouts*, que reparta entre réplicas y que no dependa de que tu laptop esté encendida.

Kubernetes tiene tres formas de abrir esa dirección, de la más tosca a la más fina:

1. **`NodePort`**: el clúster abre un puerto alto (entre 30000 y 32767) en **todos** los nodos, y lo que llegue ahí va al Service. Funciona, pero el cliente tiene que saberse la IP de un nodo y un número que el clúster eligió.
2. **`LoadBalancer`**: lo mismo que `NodePort`, más un balanceador **fuera** del clúster, con su propia IP, que reparte entre los nodos. En una nube, ese balanceador lo crea el proveedor. En kind no hay nube, y por eso el Service se queda esperando.
3. **Una puerta de entrada de capa 7** (HTTP): un solo punto que recibe el tráfico y decide, por la ruta o por el nombre del sitio, a qué Service va cada petición. La forma vigente de declararla es **Gateway API**. La forma vieja, `Ingress`, sigue existiendo y está congelada.

En kind, las opciones 2 y 3 necesitan algo que el clúster no trae: alguien que reparta direcciones IP y alguien que atienda la puerta. Este curso instala los dos **dentro** del clúster. **MetalLB** reparte las IP. **Envoy Gateway** atiende la puerta. Cada uno se instala con sus propios tipos de objeto (recursos personalizados) y sus propios guardianes (*webhooks*), y de ahí sale la lección más útil de hoy, la que vas a usar en todo clúster real: la plataforma va primero, se espera a que esté lista, y después va el proyecto. No es una manía. Es lo que el clúster te exige, y lo vas a ver exigirlo.

La lección tiene ocho partes de conceptos y después las secciones de siempre:

1. **El clúster de la lección** (6.1), con su `kubeconfig` propio.
2. **El proyecto antes que la plataforma** (6.2): lo que falla y por qué.
3. **Un `LoadBalancer` sin nadie que reparta direcciones** (6.3), y el `NodePort` que ya abrió.
4. **MetalLB** (6.4): el rango, la capa 2 y el *webhook* que todavía no escucha.
5. **Por qué no Cloud Provider KIND** (6.5).
6. **Envoy Gateway y Gateway API** (6.6): la plataforma de la puerta.
7. **La puerta del `revisor`** (6.7): `Gateway` y `HTTPRoute`.
8. **`Ingress` y `ingress-nginx`** (6.8): lo que se retiró, para reconocerlo.

Y al final de los conceptos, **el orden** (6.9), escrito en tres pasos.

Este es el destino. Al final de 6.7, un cliente que no es parte del clúster le pide el reporte al `revisor` por la puerta nombrada:

```text
$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200
```

## Si no traes la imagen del curso de Docker

Esta lección usa las mismas dos imágenes de las Lecciones 3 a 5: `curso-docker-revisor:1.6.0`, la del `revisor`, y `curso-docker-prueba:1.0.0`, la del servicio que falla a propósito. Comprueba que las tienes:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Si te falta alguna, la [Lección 3](03-services-dns.md) dice, en esta misma sección, cómo construir las dos desde el repositorio del curso de Docker. Esta lección no le pide nada nuevo a ninguna de las dos imágenes. Lo nuevo viene de fuera: las imágenes de MetalLB y de Envoy, que no se cargan con `kind load` sino que cada nodo descarga de internet la primera vez, como la de `curl` en la Lección 3.

## Los conceptos

### 6.1 El clúster de la lección

#### 6.1.1 Antes de crear: una regla de convivencia

Esta es la primera lección del curso que instala **MetalLB**, y MetalLB tiene una particularidad que obliga a una regla nueva. Va a tomar direcciones IP de la red `kind` de Docker, la red que comparten **todos** los clústeres de kind de tu máquina. Si dos clústeres con MetalLB y el mismo rango corren a la vez, los dos anuncian las mismas direcciones y se pisan: unas peticiones llegan a uno y otras al otro. Por eso, antes de crear tu clúster, comprueba dos cosas:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar ya en 172.18.255.200. Si este curl responde algo,
# hay otro clúster con MetalLB vivo: espera a que termine.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 3 http://172.18.255.200/
```

La red `kind` la crea kind la primera vez que crea un clúster, así que el primer comando falla si nunca has creado uno; en ese caso, crea el clúster y compruébala justo después, antes de instalar nada. En la corrida de esta lección la red salió así:

```text
$ docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
fc00:f853:ccd:e793::/64 172.18.0.0/16 
```

Dos subredes: una IPv6 y la IPv4 `172.18.0.0/16`, que es la que importa. Si la tuya es otra (por ejemplo `172.19.0.0/16`, porque en tu máquina ya había otra red con la `172.18`), tendrás que cambiar el rango de `infra/metallb-pool.yaml` para que caiga dentro de la tuya, y todas las IP de esta lección te saldrán distintas. Hay una tercera comprobación, la más barata: `kind get clusters`. Si ves otro clúster vivo que no es tuyo, pregúntale a su dueño si usa MetalLB y con qué rango antes de seguir; el `curl` solo ve a quien contesta HTTP en el puerto 80 de la `.200`, y un MetalLB ajeno con otro puerto o con otras direcciones del rango (`.201` a `.220`) pasaría sin que lo notes. `correr.sh` hace las dos primeras y se detiene antes de crear nada si alguna falla; si la red `kind` no existe todavía, también se detiene, porque no puede leer su rango. En ese caso crea tú un clúster cualquiera de prueba, mira la red y bórralo, o crea la red a mano con la misma subred.

#### 6.1.2 Crear, comprobar, cargar

Desde la raíz del repositorio del curso, con el mismo cuidado de siempre:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta se queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l6.XXXX)/kubeconfig"
# curso-k8s-l6 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l6 --config programas/06-entrar-al-cluster/kind-curso.yaml
# Debe decir kind-curso-k8s-l6. Si dice otra cosa, no sigas.
kubectl config current-context
# Una guarda que se detiene sola (la de la Lección 5, con el nombre de este clúster).
# Va delante de cada comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l6
cd programas/06-entrar-al-cluster
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

La función `ctx` compara el contexto activo con el que esperas. Si coincide, no imprime nada y devuelve éxito; si no, escribe «contexto equivocado: no sigo» y devuelve un error, y el `&&` hace que el comando que sigue **no se ejecute**. Es la diferencia entre mirar el contexto «a ojo», que depende de que estés atento, y una guarda que te detiene aunque vayas con prisa. Hoy vas a instalar componentes que crean decenas de objetos en el clúster, incluidos objetos que valen para todo el clúster y no para un espacio de nombres; aplicarlos en el contexto equivocado sería instalarlos en el clúster de otra persona. Por eso, **delante de cada** `apply`, `delete` o `patch` de esta lección va `ctx &&`. En las salidas que siguen se omite para que quepan, pero en tu terminal va siempre. (`correr.sh` hace lo mismo en cada comando.)

El `(umask 077; …)` merece su explicación. El `umask` es la máscara que le dice a tu shell qué permisos **quitarle** a todo archivo nuevo; con la habitual (`022`), `token.txt` nacería `-rw-r--r--`, legible por cualquier usuario de la máquina. Con `077`, nace `-rw-------`: solo tú. Los paréntesis hacen que el cambio de máscara valga solo para ese comando y no se quede en tu terminal. Es el mismo cuidado de las Lecciones 4 y 5, y pesa más hoy, porque esta lección habla de máquinas compartidas.

```text
$ kubectl config current-context
kind-curso-k8s-l6

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l6-control-plane  Ready   v1.37.0  172.18.0.4
curso-k8s-l6-worker         Ready   v1.37.0  172.18.0.3
curso-k8s-l6-worker2        Ready   v1.37.0  172.18.0.2
```

La columna nueva es `INTERNAL-IP`: la dirección de cada nodo **en la red `kind`** de Docker. Recuerda de la Lección 0 que un nodo de kind es un contenedor; esta es la IP de ese contenedor. Las tres caen al principio de `172.18.0.0/16`, porque Docker reparte desde abajo. Guárdalas en la memoria: en 6.3 un cliente de fuera va a entrar por ellas.

`kind load` imprime sus seis renglones de siempre, `not yet present on node … loading...`, dos imágenes por tres nodos. Están en `correr.salida.txt`.

#### 6.1.3 El cliente de fuera

Para probar desde fuera del clúster, esta lección usa un contenedor de `curl` conectado a la red `kind`, con el nombre `curso-k8s-l6-cliente` y `--rm` para que se borre solo al terminar cada petición. Es un cliente de verdad: no es un Pod, el clúster no lo conoce, no pasa por el DNS del clúster ni por `kube-proxy` de su lado. Ve la red como la vería una máquina conectada al mismo segmento que los nodos. Para no escribir la línea completa cada vez, define una función en tu terminal:

```bash
afuera() {
  docker run --rm --network kind --name curso-k8s-l6-cliente \
    curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 "$@"
}
# Uso:  afuera -s -m 5 http://172.18.255.200/salud
```

En las salidas de esta lección, **los renglones que empiezan con `$ curl` corren así**, desde ese contenedor, salvo uno de la sección del hábito de seguridad, que corre en tu terminal a propósito y lo dice. En Linux Mint puedes usar `curl` directo desde tu terminal si prefieres; el resultado debe ser el mismo.

Una advertencia para la máquina compartida: cuando pasas el token con `-H "Authorization: Bearer $(cat token.txt)"`, el token queda como **argumento del comando**, y mientras el comando corre cualquier usuario de la máquina lo ve en la lista de procesos (`ps`). Para el token de mentira de este curso está bien; con un token real, se pasa desde un archivo (`-H @archivo`, que `curl` acepta desde la versión 7.55) o por la entrada estándar, nunca escrito en la línea.

### 6.2 El proyecto antes que la plataforma

#### 6.2.1 Lo que trae la carpeta

La carpeta de esta lección trae lo mismo que dejó la Lección 5 —los dos Deployments, los dos Services, el generador del `ConfigMap` y el del `Secret`— y dos archivos nuevos. La `kustomization.yaml` ya los menciona. Es un **programa**: `programas/06-entrar-al-cluster/kustomization.yaml`.

```yaml
# kustomization.yaml — Lecciones 4 a 6. Se aplica con: kubectl apply -k .
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Antes de esta kustomization van las piezas de infra/ (MetalLB y Envoy Gateway):
# sin sus CRD, Gateway y HTTPRoute no existen. Ver correr.sh para el orden.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
- revisor-publico.yaml
- gateway.yaml
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
```

Los dos renglones nuevos de `resources` son `revisor-publico.yaml` (6.3) y `gateway.yaml` (6.7). El comentario de arriba ya avisa lo que vas a comprobar ahora: «antes de esta kustomization van las piezas de `infra/`». Haz lo que haría cualquiera con prisa a las 4:40: ignora el aviso y aplica.

#### 6.2.2 Aplicar sin plataforma

```text
$ kubectl get crd
No resources found

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
[código de salida: 1]
```

Lee la salida en dos mitades. Arriba, siete objetos `created`: todo lo que el clúster ya sabía qué era. Los nombres de los generados son los de la Lección 4: `revisor-config-t6cm6872fk`, idéntico en tu corrida porque la lista no cambió, y `revisor-token-…`, distinto porque tu token es nuevo. Abajo, dos objetos que el clúster **no reconoce**: «no encuentro el tipo `Gateway` en la versión `gateway.networking.k8s.io/v1`», y la sugerencia, en inglés, «asegúrate de instalar primero los CRD». `kubectl` aplicó lo que pudo, se saltó lo que no, y salió con código 1. Un guion con `set -e` se detendría aquí; uno sin él seguiría como si nada, y eso es peor.

El primer comando, `kubectl get crd`, ya lo anunciaba: `No resources found`. Este clúster no tiene **ningún** recurso personalizado. Y la prueba directa:

```text
$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME   SHORTNAMES   APIVERSION   NAMESPACED   KIND
```

Solo encabezados. El grupo `gateway.networking.k8s.io` no existe en este clúster.

#### 6.2.3 Qué es un CRD

Hasta ahora, todos los tipos que usaste —`Pod`, `Deployment`, `Service`, `ConfigMap`, `Secret`— vienen **dentro** de Kubernetes: el `kube-apiserver` los conoce desde que arranca. `Gateway` y `HTTPRoute` no. La [documentación de recursos personalizados](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) lo dice así: un recurso personalizado «es una extensión de la API de Kubernetes que no necesariamente está disponible en una instalación por omisión». Y explica cómo se agrega uno: con un objeto `CustomResourceDefinition` (CRD). «Definir un objeto CRD crea un recurso personalizado nuevo, con el nombre y el esquema que especifiques. La API de Kubernetes sirve y guarda tu recurso personalizado.»

O sea: un CRD es un objeto que le **enseña** al `kube-apiserver` un tipo nuevo. Mientras no exista el CRD de `Gateway`, un manifiesto con `kind: Gateway` es, para el clúster, texto que no significa nada. Es el primer motivo del orden: **los tipos tienen que existir antes que los objetos de esos tipos**.

La [página de Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) de Kubernetes lo dice de su propio caso: Gateway API «es un complemento (*add-on*) que contiene tipos de API» y sus especificaciones «están definidas como recursos personalizados». No viene con Kubernetes. Alguien tiene que instalarla, y en este curso la instala Envoy Gateway (6.6).

Fíjate en lo que **sí** se creó: el `revisor` y `prueba` están corriendo, con sus Services, y entre ellos `revisor-publico`. Es exactamente el punto de partida que esta lección necesita: lo de la Lección 5, más una puerta pedida y todavía sin abrir.

### 6.3 Un `LoadBalancer` sin nadie que reparta direcciones

#### 6.3.1 El manifiesto

Es un **programa**: `revisor-publico.yaml`.

```yaml
# revisor-publico.yaml — Lección 6: un Service LoadBalancer. Su EXTERNAL-IP la
# reparte MetalLB (infra/metallb-pool.yaml); sin MetalLB se queda en <pending>.
# En la Lección 7 se retira: la única puerta que queda es el Gateway.
apiVersion: v1
kind: Service
metadata:
  name: revisor-publico
  labels:
    app: revisor
spec:
  type: LoadBalancer
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

Es el Service de la Lección 3 con dos diferencias: se llama `revisor-publico` y su `type` es `LoadBalancer`. Mismo selector, mismo `port: 80`, mismo `targetPort: http`. No reemplaza al `revisor` `ClusterIP`: los dos existen a la vez y eligen los mismos Pods. El de dentro sigue siendo para los clientes de dentro; este es la puerta hacia afuera. Que sean dos objetos y no uno con el tipo cambiado es una decisión: el día que quieras cerrar la puerta (la Lección 7 lo hace), borras `revisor-publico` y nada de lo de dentro se entera.

#### 6.3.2 `<pending>`

```text
$ kubectl get services
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes        ClusterIP      10.96.0.1       <none>        443/TCP        36s
prueba            ClusterIP      10.96.248.146   <none>        9000/TCP       7s
revisor           ClusterIP      10.96.157.248   <none>        80/TCP         7s
revisor-publico   LoadBalancer   10.96.115.79    <pending>     80:30808/TCP   7s
```

`EXTERNAL-IP <pending>`: el Service pidió una IP externa y nadie se la ha dado. La [documentación de Services](https://kubernetes.io/docs/concepts/services-networking/service/) explica de quién es ese trabajo: «en proveedores de nube que admiten balanceadores externos, poner el campo `type` en `LoadBalancer` aprovisiona un balanceador para tu Service. La creación real del balanceador ocurre de forma asíncrona, y la información del balanceador aprovisionado se publica en el campo `.status.loadBalancer` del Service». En kind no hay proveedor de nube. El campo se queda vacío y `kubectl` lo muestra como `<pending>`, para siempre, sin un solo error:

```text
$ kubectl describe service revisor-publico | grep -E '^(Type|LoadBalancer Ingress|Port|NodePort|Endpoints|Events):'
Type:                     LoadBalancer
Port:                     http  80/TCP
NodePort:                 http  30808/TCP
Endpoints:                10.244.2.3:8080,10.244.1.2:8080,10.244.2.4:8080
Events:                   <none>
```

No hay renglón `LoadBalancer Ingress` (ahí iría la IP) y no hay eventos: nadie intentó nada, así que nadie falló. Es el tipo de estado que confunde, porque nada está rojo. La única pista es la palabra `<pending>`.

#### 6.3.3 Lo que sí abrió: un `NodePort` en cada nodo

Mira otra vez la columna `PORT(S)`: `80:30808/TCP`. Y en `describe`, `NodePort: http 30808/TCP`. El Service pidió un balanceador que no llegó, pero algo sí llegó: un **puerto en los nodos**. La misma documentación lo explica: «para implementar un Service de `type: LoadBalancer`, Kubernetes normalmente empieza haciendo los cambios equivalentes a pedir un Service de `type: NodePort`. Después, el `cloud-controller-manager` configura el balanceador externo para que reenvíe el tráfico a ese puerto del nodo». Un `LoadBalancer` es un `NodePort` **más** alguien de fuera. Aquí falta ese alguien, pero el `NodePort` ya está abierto. Se comprueba desde el cliente de fuera, contra la IP de un nodo de trabajo y contra la del nodo de control:

```text
$ curl -s -m 5 http://172.18.0.3:30808/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 http://172.18.0.4:30808/salud
{"estado":"vivo","version":"1.6.0"}
```

Las dos responden. `172.18.0.3` es `worker`; `172.18.0.4` es el nodo de **control**, donde no corre ninguna réplica del `revisor`. Y aun así contesta: el `kube-proxy` de cada nodo, incluido el de control, escucha en el 30808 y reenvía a una réplica, esté donde esté. Esto es lo que la primera propuesta de la escena hubiera dejado abierto, y es lo que **ya** está abierto aunque la IP externa nunca llegue.

La documentación dice cómo evitarlo: con `spec.allocateLoadBalancerNodePorts: false`, que «solo debe usarse con implementaciones de balanceador que mandan el tráfico directo a los Pods en lugar de usar puertos de nodo». Su valor por omisión es `true`. MetalLB en capa 2, el que instala esta lección, entrega el tráfico a un nodo y deja que `kube-proxy` lo reparta, así que este curso no lo apaga; pero lo nombra, porque «qué se expone» incluye este puerto, y la sección del hábito de seguridad lo cuenta.

### 6.4 MetalLB: quien reparte las direcciones, dentro del clúster

#### 6.4.1 Qué es

MetalLB es un balanceador para clústeres que no viven en una nube: los de un centro de datos propio, los de tu casa y los de kind. Su [guía de instalación](https://metallb.io/installation/) describe sus dos piezas: el `controller`, un Deployment, «el controlador de todo el clúster que se encarga de asignar las direcciones IP»; y el `speaker`, un DaemonSet (un Pod por nodo), «el componente que habla los protocolos que elijas para que los Services sean alcanzables». El primero decide qué IP le toca a cada Service. El segundo hace que esa IP exista en la red.

En esta lección MetalLB trabaja en **capa 2**. Su [guía de configuración](https://metallb.io/configuration/) lo explica en una frase: «funciona respondiendo directamente a las peticiones ARP de tu red local, para darles a los clientes la dirección MAC de la máquina». ARP es la pregunta que hace un equipo en una red local para saber quién tiene una IP: «¿quién tiene `172.18.255.200`?». Ninguna máquina tiene esa IP configurada. Pero el `speaker` de un nodo contesta «yo», y desde ese momento el tráfico hacia esa IP llega a ese nodo, donde `kube-proxy` lo reparte entre las réplicas. Es un truco honesto: no hay un aparato balanceador, hay un nodo que se hace cargo de la dirección.

#### 6.4.2 Instalar: los CRD y el *webhook*

La instalación es un manifiesto del lanzamiento v0.16.1, el que da la guía oficial, fijado a su versión. Este curso lo envuelve en una kustomization para poder aplicarlo con `-k` como todo lo demás. Es un **programa**: `infra/metallb/kustomization.yaml`.

```yaml
# MetalLB v0.16.1 (modo nativo, capa 2), instalado SOLO en este clúster.
# Es la versión que indica la guía oficial de instalación (metallb.io/installation).
# Se aplica antes que todo lo demás de la Lección 6: kubectl apply -k infra/metallb
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
```

La guía dice algo que vale la pena leer antes de aplicar: sin configuración, «los componentes de MetalLB arrancan, pero se quedan quietos» hasta que les das un rango. Así que son dos pasos: instalar y dar el rango. Haz lo que haría cualquiera con prisa, otra vez: los dos seguidos.

```text
$ kubectl apply -k infra/metallb | tail -5
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply -f infra/metallb-pool.yaml
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
[código de salida: 1]
```

Un error distinto al de 6.2. Esta vez el tipo **sí** existe —el `apply` de MetalLB creó sus CRD en el mismo instante—, y aun así el clúster rechazó los dos objetos. Léelo de derecha a izquierda: `connect: connection refused` contra `10.96.93.252:443`; esa IP es la del Service `metallb-webhook-service` que acababa de crearse (`created`, en el renglón dos de la salida anterior); y lo que fallaba era «llamar al *webhook* `ipaddresspoolvalidationwebhook.metallb.io`».

Un ***webhook* de admisión** es otro guardián que la plataforma le agrega al `kube-apiserver`. La [documentación de controladores de admisión extensibles](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) los define así: «los *webhooks* de admisión son llamadas HTTP que reciben peticiones de admisión y hacen algo con ellas». Los de validación «pueden rechazar peticiones para hacer cumplir políticas propias». MetalLB instala uno para revisar que un rango esté bien escrito antes de aceptarlo. El `kube-apiserver`, antes de guardar tu `IPAddressPool`, le pregunta al *webhook*. Pero el Pod que contesta esa pregunta, el `controller`, todavía estaba arrancando. Nadie escuchaba en el 443. ¿Y qué hace el `kube-apiserver` cuando no puede preguntar? Eso lo decide un campo del *webhook*, `failurePolicy`. La misma página lo dice: con `failurePolicy: Fail`, que es el valor por omisión, «un error al llamar al *webhook* hace que la admisión falle y la petición se rechace». MetalLB lo escribe explícitamente en sus seis *webhooks* (se puede comprobar, y la corrida lo comprueba abajo): mejor rechazar que dejar pasar un objeto sin revisar.

Ese es el segundo motivo del orden: **los guardianes tienen que estar escuchando antes de que llegue lo que van a revisar**. La política del *webhook* de MetalLB se lee en el propio clúster; hay un valor por cada uno de sus seis guardianes:

```text
$ kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Fail Fail Fail Fail Fail Fail
```

Seis `Fail`: ninguno deja pasar un objeto si no puede revisarlo. Y no basta con que el CRD exista:

```text
$ kubectl get crd -o name | grep metallb.io
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io
```

Nueve tipos nuevos, todos del grupo `metallb.io`. Varios son para el otro modo de MetalLB, BGP, que este curso no usa. Los dos de hoy son `ipaddresspools` y `l2advertisements`.

#### 6.4.3 Esperar, con `kubectl wait`

La corrección no es reintentar hasta que pase. Es **esperar a una condición** y después aplicar:

```text
$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl apply -f infra/metallb-pool.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
```

La [referencia de `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) lo describe: el comando «toma varios recursos y espera hasta que la condición indicada aparezca en el campo `Status` de cada uno». `condition=Available` en un Deployment quiere decir que tiene la disponibilidad **mínima** que permite su estrategia de actualización (la documentación de Deployments la define así). Con el `controller` de MetalLB, que tiene una sola réplica, eso es lo mismo que «su única réplica está lista»; «lista» en el sentido de la Lección 5, el de las sondas de disponibilidad. Con un Deployment de tres réplicas y `maxUnavailable` de 25 %, `Available` llegaría con menos réplicas listas que las que pide: no lo leas como «todas». En esta corrida, en cuanto el `controller` estuvo `Available`, el *webhook* ya contestaba. Para el DaemonSet se usa `rollout status`, el mismo comando de la Lección 2, que espera a que haya un `speaker` listo en cada uno de los tres nodos. Con `--timeout`, ninguna espera es infinita: si algo no llega, el comando falla y lo sabes.

Mismo archivo, sin cambiar una coma, y esta vez `created`. El archivo nunca estuvo mal. Estaba adelantado.

```text
$ kubectl get pods -n metallb-system -o wide | awk '{print $1, $2, $3, $6, $7}' | column -t
NAME                         READY  STATUS   IP          NODE
controller-76f4cf76b7-hpzjj  1/1    Running  10.244.1.3  curso-k8s-l6-worker
speaker-455xp                1/1    Running  172.18.0.3  curso-k8s-l6-worker
speaker-jvbvh                1/1    Running  172.18.0.2  curso-k8s-l6-worker2
speaker-xctwr                1/1    Running  172.18.0.4  curso-k8s-l6-control-plane
```

Un `controller` con IP de la red de Pods (`10.244.`) y tres `speaker`, uno por nodo, con la IP **del nodo** (`172.18.0.`). Eso último no es casualidad: el `speaker` tiene que contestar ARP en la red `kind`, así que corre con la red del nodo, no con la red de Pods.

#### 6.4.4 El rango

Es un **programa**: `infra/metallb-pool.yaml`.

```yaml
# metallb-pool.yaml — las IP que MetalLB puede repartir a los Services LoadBalancer.
# Salen de la red «kind» de Docker (en la máquina de las corridas, 172.18.0.0/16;
# compruébala con: docker network inspect kind). Se toma el final del rango, lejos
# de las IP que Docker da a los nodos.
# ⚠️ Dos clústeres de kind con MetalLB y el MISMO rango en la misma red se pisan
# (los dos anuncian las mismas IP): en una máquina compartida, un rango por clúster.
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: curso
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: curso
  namespace: metallb-system
spec:
  ipAddressPools:
  - curso
```

Dos objetos, dos decisiones:

- **`IPAddressPool`** dice **qué** direcciones puede repartir: de la `172.18.255.200` a la `172.18.255.220`, veintiuna. La guía de configuración: «todas las IP asignadas mediante `IPAddressPool` contribuyen al conjunto de IP que MetalLB usa para asignar IP a los Services». Por qué esas: tienen que estar **dentro** de la red `kind` (si no, nadie en esa red preguntaría por ellas) y **lejos** de las que Docker reparte a los contenedores, que empiezan desde abajo (`172.18.0.2`, `.3`, `.4`). El final de la red es el lugar más seguro.
- **`L2Advertisement`** dice **cómo** se anuncian: en capa 2, por ARP. La guía: «para anunciar la IP que sale de un `IPAddressPool`, hay que asociarle una instancia de `L2Advertisement`». Sin este segundo objeto, MetalLB asignaría la IP y nadie contestaría por ella.

```text
$ kubectl get ipaddresspool,l2advertisement -n metallb-system
NAME                             AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ipaddresspool.metallb.io/curso   true          false             ["172.18.255.200-172.18.255.220"]

NAME                               IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
l2advertisement.metallb.io/curso   ["curso"]                                  
```

`AUTO ASSIGN true`: MetalLB toma IP de este rango para cualquier `LoadBalancer` que las pida, sin que el Service tenga que nombrar el rango.

#### 6.4.5 La primera IP

```text
$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.115.79   172.18.255.200   80:30808/TCP   119s
```

`172.18.255.200`, la primera del rango. El Service llevaba casi dos minutos en `<pending>`; nadie lo volvió a aplicar. MetalLB, al tener rango, buscó los `LoadBalancer` sin IP y les dio una. Es otra vez el termostato de la Lección 0: el estado deseado estaba escrito desde 6.2, y en cuanto hubo quien lo persiguiera, se alcanzó. El `NodePort` sigue siendo `30808`: la IP externa se montó **encima** del puerto de nodo, como dice la documentación.

¿Quién lo hizo y desde dónde? Lo dicen los eventos del Service, que en 6.3 estaban vacíos:

```text
$ kubectl get events --field-selector involvedObject.name=revisor-publico --sort-by=.lastTimestamp | awk '{$1=""; print}' | sed 's/^ //'
SEEN TYPE REASON OBJECT MESSAGE
Normal IPAllocated service/revisor-publico Assigned IP ["172.18.255.200"]
Normal nodeAssigned service/revisor-publico announcing from node "curso-k8s-l6-worker2" with protocol "layer2"
```

(`awk` quita la columna de la edad para que quepa; la cabecera conserva su nombre.) Dos eventos, los dos de MetalLB: `IPAllocated`, del `controller`, que eligió la IP; y `nodeAssigned`, del `speaker`, que dice desde qué nodo la anuncia: `curso-k8s-l6-worker2`, por capa 2. En tu corrida el nodo puede ser otro. Ese nodo es, desde ahora, la puerta física de `172.18.255.200`: si se cae, otro `speaker` toma el anuncio.

Y la prueba que importa, desde fuera:

```text
$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           7ms  200
```

Una dirección estable, en el puerto 80, sin número raro, que reparte entre las tres réplicas y que sigue ahí aunque los Pods cambien. Lo que el tablero de la escena necesitaba. (Los `…` sustituyen el token en las salidas publicadas; en tu terminal va el contenido de `token.txt`, con `-H "Authorization: Bearer $(cat token.txt)"`.)

### 6.5 Por qué no Cloud Provider KIND

Si buscas «LoadBalancer en kind», la primera respuesta es la de kind mismo. Su [guía de LoadBalancer](https://kind.sigs.k8s.io/docs/user/loadbalancer/) recomienda **Cloud Provider KIND**, y su [guía de Ingress](https://kind.sigs.k8s.io/docs/user/ingress/) dice que, desde la v0.9.0, ese programa «soporta Ingress de forma nativa» y que Gateway API «también está soportada de forma nativa». Es una herramienta seria, del mismo grupo que mantiene kind. ¿Por qué este curso no la usa?

Por **dónde corre** y **sobre qué actúa**. La guía de kind lo dice: Cloud Provider KIND «corre como un binario independiente en tu máquina y se conecta a tu clúster de kind», y «requiere privilegios para abrir puertos en el sistema y para conectarse al *runtime* de contenedores». Su [README](https://github.com/kubernetes-sigs/cloud-provider-kind) es más preciso: «`cloud-provider-kind` va a vigilar **todos** tus clústeres de kind», y su controlador de Gateway API «viene activado por omisión». El README no describe ninguna opción para limitarse a uno.

En tu laptop personal, con un solo clúster, eso no importa. En una máquina compartida —la de un laboratorio, la de un equipo que corre pruebas en paralelo, o la tuya si tienes un clúster de otro proyecto— importa mucho: un proceso que tú lanzaste para tu lección empezaría a crear balanceadores, CRD y una `GatewayClass` en clústeres que no son tuyos, sin que sus dueños lo pidieran. Este curso tiene una regla desde la Lección 1: no tocar lo que no es tuyo, ni otro contexto, ni otro clúster. Cloud Provider KIND la rompe por diseño.

MetalLB y Envoy Gateway, en cambio, son objetos **dentro** del clúster. Se instalan con `kubectl` en tu contexto, viven en sus espacios de nombres (`metallb-system`, `envoy-gateway-system`) y desaparecen con `kind delete cluster`. El precio es el que viste en 6.1: el rango de MetalLB sale de la red `kind`, que sí es compartida, y por eso dos clústeres con el mismo rango no deben correr a la vez. Es un precio que se controla con una comprobación de una línea. Lo otro no se controla.

### 6.6 Envoy Gateway y Gateway API: la plataforma de la puerta

#### 6.6.1 Las tres piezas de Gateway API

Un `LoadBalancer` es una puerta por Service: cada uno con su IP. Si mañana publicas cinco servicios, son cinco IP, y ninguna sabe nada de HTTP: no puede decidir por la ruta, ni por el nombre del sitio, ni poner un cifrado común. Gateway API resuelve eso con **una** puerta que entiende HTTP y reglas que dicen qué entra y a dónde va. La [página de Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) de Kubernetes describe sus tres piezas:

| Pieza | Qué es, según la documentación | En este curso |
|---|---|---|
| `GatewayClass` | «define un conjunto de puertas con una configuración común, administradas por un controlador que implementa la clase» | `eg`, la de Envoy Gateway |
| `Gateway` | «define una instancia de infraestructura que maneja tráfico, como un balanceador de la nube» | `revisor`: escucha HTTP en el 80 |
| `HTTPRoute` | «define reglas específicas de HTTP para llevar tráfico de un *listener* del Gateway a una representación de *endpoints* de red», que «a menudo se representan con un Service» | `revisor`: todo lo que llegue va al Service `revisor` |

La misma página explica por qué son tres y no uno: Gateway API está «orientada a roles». La `GatewayClass` es del **proveedor de infraestructura**; el `Gateway`, del **operador del clúster**, que se ocupa de «políticas, acceso a la red y permisos»; la `HTTPRoute`, del **desarrollador de la aplicación**, que se ocupa de su Service. En tu clúster eres los tres, pero los archivos ya quedan separados así: `infra/gatewayclass.yaml` es plataforma, `gateway.yaml` es proyecto.

#### 6.6.2 Instalar con `--server-side`, y por qué

Envoy Gateway trae en un solo archivo los CRD de Gateway API y los suyos. Su [guía de instalación](https://gateway.envoyproxy.io/docs/install/install-yaml/) lo dice: «el manifiesto `install.yaml` incluye los CRD de Gateway API y los CRD de Envoy Gateway». Este curso lo envuelve igual que a MetalLB. Es un **programa**: `infra/envoy-gateway/kustomization.yaml`.

```yaml
# Envoy Gateway v1.9.2, instalado SOLO en este clúster. Trae los CRD de Gateway API
# (bundle v1.6.1) y los suyos. Su guía oficial lo instala con server-side apply:
#   kubectl apply --server-side -k infra/envoy-gateway
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/envoyproxy/gateway/releases/download/v1.9.2/install.yaml
```

La guía oficial lo instala con `kubectl apply --server-side`. ¿Qué pasa sin esa bandera? Se puede preguntar sin cambiar nada, con `--dry-run=server`, que manda todo al `kube-apiserver` para que lo valide y no guarda nada:

```text
$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -c 'Too long'
3

$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -m 1 'Too long' | sed 's/.*\(The CustomResourceDefinition\)/\1/'
Error from server (Invalid): error when creating "infra/envoy-gateway": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(En `correr.salida.txt`, debajo de cada uno de estos dos comandos aparece `[código de salida: 1]`. Es el código del `kubectl apply`, cuyo intento rechazó el `kube-apiserver`. El guion corre con `pipefail`, que hace que una tubería falle si falla cualquiera de sus comandos. En tu terminal, sin `pipefail`, la tubería devuelve el código de `grep`, que es 0, y no verás ese renglón.) Tres CRD rechazados, con el mismo motivo: «`metadata.annotations`: demasiado largo; no puede pasar de 262144 bytes». La causa está en cómo funciona el `apply` de siempre, el que usaste desde la Lección 2. Ese `apply` guarda en cada objeto una anotación, `kubectl.kubernetes.io/last-applied-configuration`, con **una copia completa** del manifiesto que aplicaste, para poder calcular la diferencia la próxima vez. Con un Deployment, esa copia pesa unos kilobytes. Con el CRD de `EnvoyProxy`, cuyo esquema describe cientos de campos, la copia pasa del tope de 256 KiB que el `kube-apiserver` acepta para todas las anotaciones de un objeto.

`--server-side` cambia quién lleva la cuenta. La [documentación de *server-side apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) lo explica: ofrece «un mecanismo para que el plano de control de tu clúster lleve el registro de los cambios a los campos de un objeto», y lo compara con la anotación de `kubectl`: en lugar de guardar «el último estado aplicado», registra qué campos maneja cada quien, en `metadata.managedFields`. Sin copia del manifiesto, sin anotación gigante.

```text
$ kubectl apply --server-side -k infra/envoy-gateway | tail -4
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl get crd -o name | grep -c gateway.networking.k8s.io
10

$ kubectl get crd -o name | grep -c gateway.envoyproxy.io
8
```

Cada renglón dice `serverside-applied` en lugar de `created`. Los cuatro últimos ya cuentan la historia de esta lección: una política de validación de admisión (`safe-upgrades`, «actualizaciones seguras», por su nombre), un `Job` llamado `certgen` que, por su nombre, genera certificados, y otro *webhook*, esta vez de los que **modifican** objetos (`mutatingwebhookconfiguration`). Otra vez guardianes. Pero no todos bloquean: este declara `failurePolicy: Ignore`, o sea que si no contesta, el `kube-apiserver` deja pasar la petición. Cuál es cuál se lee en el manifiesto, no se supone (la corrida lo muestra abajo). Diez CRD de Gateway API y ocho de Envoy Gateway. Hay más, y se miden:

```text
$ kubectl get crd -o name | grep gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io

$ kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.annotations.gateway\.networking\.k8s\.io/channel} {.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}{end}' | grep 'gateway.networking.k8s.io ' | column -t
backendtlspolicies.gateway.networking.k8s.io  experimental  v1.6.1
gatewayclasses.gateway.networking.k8s.io      experimental  v1.6.1
gateways.gateway.networking.k8s.io            experimental  v1.6.1
grpcroutes.gateway.networking.k8s.io          experimental  v1.6.1
httproutes.gateway.networking.k8s.io          experimental  v1.6.1
listenersets.gateway.networking.k8s.io        experimental  v1.6.1
referencegrants.gateway.networking.k8s.io     experimental  v1.6.1
tcproutes.gateway.networking.k8s.io           experimental  v1.6.1
tlsroutes.gateway.networking.k8s.io           experimental  v1.6.1
udproutes.gateway.networking.k8s.io           experimental  v1.6.1

$ kubectl get mutatingwebhookconfiguration envoy-gateway-topology-injector.envoy-gateway-system -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Ignore
```

Tres cosas se leen ahí. Diez CRD de `gateway.networking.k8s.io`, **todos** del canal `experimental` y del paquete `v1.6.1` de Gateway API (el canal estándar sería solo lo estable; el experimental trae además campos y versiones en prueba). Tres CRD más, del grupo `gateway.networking.x-k8s.io`, que el `grep -c` de arriba no contaba: la `x` es de experimental. Y un *webhook* de mutación con `failurePolicy: Ignore`. El `column -t` solo alinea la tabla. En total, entonces: diez más tres de Gateway API y ocho de Envoy Gateway.

#### 6.6.3 Esperar, otra vez, y la clase

Antes de usar los tipos nuevos, se espera a que estén **establecidos**, y antes de pedir una puerta, a que el controlador esté disponible:

```text
$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met
```

`Established` es la condición que el `kube-apiserver` le pone a un CRD cuando ya sirve el tipo nuevo. Un CRD recién creado puede tardar un momento en estarlo; esperar a la condición es preguntarle al clúster en vez de adivinar. Aquí ya lo estaban: `condition met` de inmediato. El segundo `wait` es igual al que usaste con el `controller` de MetalLB, ahora con el controlador de Envoy Gateway.

Ahora la clase. Es un **programa**: `infra/gatewayclass.yaml`.

```yaml
# gatewayclass.yaml — «eg»: la clase de puerta que atiende Envoy Gateway.
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

Una `GatewayClass` es corta: un nombre, `eg`, y el controlador que la atiende. El `controllerName` no es un adorno: es la firma con la que el controlador de Envoy Gateway reconoce las clases que le tocan. Si escribieras otro, la clase existiría y nadie la aceptaría.

```text
$ kubectl apply -f infra/gatewayclass.yaml
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl get gatewayclass
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       0s

$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME                 SHORTNAMES   APIVERSION                     NAMESPACED   KIND
backendtlspolicies   btlspolicy   gateway.networking.k8s.io/v1   true         BackendTLSPolicy
gatewayclasses       gc           gateway.networking.k8s.io/v1   false        GatewayClass
gateways             gtw          gateway.networking.k8s.io/v1   true         Gateway
grpcroutes                        gateway.networking.k8s.io/v1   true         GRPCRoute
httproutes                        gateway.networking.k8s.io/v1   true         HTTPRoute
listenersets         lset         gateway.networking.k8s.io/v1   true         ListenerSet
referencegrants      refgrant     gateway.networking.k8s.io/v1   true         ReferenceGrant
tcproutes                         gateway.networking.k8s.io/v1   true         TCPRoute
tlsroutes                         gateway.networking.k8s.io/v1   true         TLSRoute
udproutes                         gateway.networking.k8s.io/v1   true         UDPRoute
```

Entre el `apply` y el `get` va un tercer `wait`, esta vez por la condición `Accepted` de la clase: el controlador tarda unos segundos en reconocerla, y sin esa espera tu `get` podría mostrar `ACCEPTED Unknown`. `ACCEPTED True`: Envoy Gateway reconoció la clase como suya. Y el mismo `api-resources` que en 6.2 daba solo encabezados ahora da diez tipos, que `api-resources` muestra en `v1`. Ojo con esa palabra: es la versión **preferida** que sirve el clúster, no una garantía de que todo sea estable. El `install.yaml` de Envoy Gateway instala los CRD del canal **experimental** de Gateway API (lo dice la anotación `gateway.networking.k8s.io/channel: experimental` de cada CRD, y la corrida la lee arriba), que trae, además de lo estable, campos y versiones en prueba, y tres tipos más del grupo `gateway.networking.x-k8s.io`. Los tres que usa esta lección, `GatewayClass`, `Gateway` y `HTTPRoute`, son estables. En un clúster real se decide a propósito qué canal se instala. Hoy usas tres. `GRPCRoute`, `TCPRoute` y `UDPRoute` son rutas para otros protocolos; `TLSRoute` y `BackendTLSPolicy` son, respectivamente, dejar pasar el cifrado sin abrirlo y cifrar el tramo de la puerta al Service, cosas que esta lección no pone. `ReferenceGrant` es el permiso que da el dueño de un espacio de nombres para que algo de **otro** espacio apunte a sus objetos: por ejemplo, una ruta que manda tráfico a un Service ajeno, o un Gateway que usa un certificado guardado en un `Secret` ajeno. En este curso la ruta y el Service viven siempre en el mismo espacio, así que no lo vas a necesitar. Que una ruta se cuelgue de un Gateway de **otro** espacio no se decide con `ReferenceGrant`, sino con el campo `allowedRoutes` del *listener* del Gateway; la [documentación de Gateway](https://kubernetes.io/docs/concepts/services-networking/gateway/) lo dice así: «por omisión, un Gateway solo acepta rutas del mismo espacio de nombres». Fíjate en la columna `NAMESPACED`: `gatewayclasses` es `false`, porque una clase vale para todo el clúster. Es plataforma.

### 6.7 La puerta del `revisor`

#### 6.7.1 El manifiesto

Es un **programa**: `gateway.yaml`.

```yaml
# gateway.yaml — Lección 6: Gateway API, la sucesora de Ingress.
# La puerta (Gateway «revisor», clase «eg» de Envoy Gateway) recibe una IP de
# MetalLB; la ruta (HTTPRoute) manda todo al Service revisor. Solo HTTP: el
# cifrado en tránsito es lo que la lección dice que falta.
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: revisor
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisor
      port: 80
```

Dos objetos en un archivo, separados por `---`. Se leen así:

- **El `Gateway`** pide una puerta de la clase `eg` con un *listener* (una oreja): `http`, protocolo `HTTP`, puerto `80`. No dice nada de IP: la IP la pide Envoy Gateway a quien la reparta, que en este clúster es MetalLB.
- **La `HTTPRoute`** se cuelga de esa puerta con `parentRefs: [revisor]` y tiene una regla: lo que empiece con `/` (`PathPrefix`), o sea, todo, va al Service `revisor` en su puerto `80`. Fíjate en el destino: el `revisor` `ClusterIP` de la Lección 3, no `revisor-publico`. La puerta entra al clúster y desde ahí usa el Service de dentro, con su EndpointSlice y su reparto.

La [referencia de `HTTPRoute`](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) dice además que, si no escribes `matches`, el valor por omisión es justo este, un prefijo `/`, «que tiene el efecto de coincidir con toda petición HTTP». El curso lo escribe de todos modos, por la misma razón que escribió `type: ClusterIP`: para que la decisión «todo pasa» quede a la vista. El Ejercicio 2 la cambia.

#### 6.7.2 Aplicar, ahora sí

El mismo comando de 6.2, con la plataforma en su lugar:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bmkbmd25cg unchanged
service/prueba unchanged
service/revisor unchanged
service/revisor-publico unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Siete `unchanged` y dos `created`. Nada se reinició: el `Secret` conservó su nombre porque `token.txt` es el mismo de 6.2, y el Deployment no tuvo motivo para un *rollout*. `apply` es declarativo, y aplicarlo dos veces es seguro: lo que ya estaba, se queda. Por eso la corrección del error de orden no fue «borrar todo y empezar de nuevo», sino instalar lo que faltaba y volver a aplicar lo mismo.

El `wait` espera a la condición `Programmed` del Gateway: que el controlador ya configuró la infraestructura que lo atiende.

```text
$ kubectl get gateway,httproute
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.18.255.201   True         113s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               113s

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

El Gateway tiene dirección, `172.18.255.201`, la segunda del rango de MetalLB (la primera ya era de `revisor-publico`), y `PROGRAMMED True`. La ruta tiene dos condiciones, que vas a usar en «El error que vas a ver»: `Accepted=True`, la puerta la aceptó como suya; y `ResolvedRefs=True`, todo lo que nombra (el Service `revisor` y su puerto) existe.

#### 6.7.3 Quién atiende la puerta

Un `Gateway` es una declaración. Alguien tiene que hacerla real:

```text
$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-default-revisor-4e6f5d7f-55b49857bd-25dqk   2/2     Running   0          113s
pod/envoy-gateway-5fc4949dcb-f8jss                    1/1     Running   0          5m44s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
service/envoy-gateway                    ClusterIP      10.96.233.233   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   5m45s
```

Dos Pods. `envoy-gateway` es el **controlador**: lee tus `Gateway` y tus `HTTPRoute` y traduce. `envoy-default-revisor-…` es el **proxy**, el Envoy que de verdad recibe las peticiones; su nombre junta el espacio de nombres del Gateway (`default`) y su nombre (`revisor`). Lo creó el controlador cuando apareció tu Gateway, con un Service propio **de tipo `LoadBalancer`**, y ese es el que recibió `172.18.255.201` de MetalLB. Las dos plataformas de esta lección trabajan juntas sin conocerse: Envoy Gateway pide un `LoadBalancer`, MetalLB se lo da.

Vistos todos los `LoadBalancer` del clúster:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
default                revisor-publico                  LoadBalancer   10.96.115.79    172.18.255.200   80:30808/TCP                                       8m21s
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
```

Dos puertas hacia el `revisor`: la directa, `.200`, y la nombrada, `.201`. Guarda esta tabla para el hábito de seguridad.

#### 6.7.4 Entrar

```text
$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados
401

$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|server|content-type)"
HTTP/1.1 200 OK
content-type: application/json
```

Las tres respuestas que importan: `/salud` contesta, `/api/estados` con el token da la tabla, y sin token da `401`. Ese `401` lo da el **`revisor`**, no la puerta: el Gateway deja pasar todo y el `revisor` sigue exigiendo su token como desde la Lección 4. La bitácora del `revisor` lo confirma:

```text
$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /api/estados'
[pod/revisor-5674f7c4cc-bhbvp/revisor] revisor: GET /api/estados 200 17ms
[pod/revisor-5674f7c4cc-pbc9f/revisor] revisor: GET /api/estados 200 8ms
[pod/revisor-5674f7c4cc-w7hgf/revisor] revisor: GET /api/estados 401 1ms
```

(`kubectl logs -l` junta las bitácoras de las tres réplicas, agrupadas por Pod y no por hora, así que el orden de los renglones no es el de las peticiones.) Hasta ese momento hubo tres peticiones a `/api/estados`: la de 6.4.5 por la `.200`, la de arriba con token por la puerta y la de arriba sin token. Aparecen las tres, y lo que sí se puede afirmar es lo que dice el `401`: lo escribió un `revisor` en su bitácora, o sea que lo dio él y no la puerta. Cuál réplica atendió cada una no se deduce de esta salida; de repartir se encarga lo de siempre, el Service `revisor`, no la puerta.

El último `curl` de arriba pidió los encabezados con `-i`: `HTTP/1.1 200 OK`. Uno más, que la sección del hábito de seguridad retoma: es HTTP/1.1 en el puerto 80, sin cifrar.

### 6.8 `Ingress`, la API congelada, y por qué no `ingress-nginx`

Vas a encontrar `Ingress` en casi todo tutorial de Kubernetes anterior a 2024. Es el abuelo de lo que acabas de hacer: un objeto que dice «tal ruta va a tal Service», atendido por un controlador. Sigue existiendo, y la [documentación de Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) dice su estado con todas las letras: «la API de Ingress está congelada»; «ya no se está desarrollando y no recibirá más cambios ni actualizaciones». Y la recomendación: «el proyecto Kubernetes recomienda usar Gateway en lugar de Ingress». Ojo con lo que **no** dice: no está obsoleta en el sentido de que la vayan a quitar. La misma página aclara que es una API estable, sujeta a las garantías de las API estables, y que el proyecto «no tiene planes de quitar Ingress de Kubernetes». Congelada quiere decir: funciona, no crece. Lo que le falta (rutas para otros protocolos, roles separados, reglas más finas) no le va a llegar. Gateway API nació para eso.

`ingress-nginx` es otra cosa: no una API, sino **un controlador** de Ingress, el más popular durante años, el de la segunda propuesta de la escena. En noviembre de 2025, el [blog de Kubernetes](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) anunció su retiro: «en marzo de 2026 se detendrá el mantenimiento de Ingress NGINX y el proyecto se retirará. Después de esa fecha no habrá más versiones, ni correcciones de errores, ni actualizaciones para resolver las vulnerabilidades de seguridad que se descubran». Las instalaciones existentes siguen funcionando y los artefactos siguen descargables, dice el mismo anuncio. Por eso el tutorial de hace dos años sigue «funcionando» esta tarde. Pero un componente que recibe tráfico de fuera y ya no recibe parches de seguridad es exactamente lo que no se instala hoy. El anuncio recomienda migrar a Gateway API o a otro controlador.

Tres nombres, tres cosas distintas:

| Nombre | Qué es | Estado |
|---|---|---|
| `Ingress` | una API de Kubernetes | congelada: funciona, no crece |
| `ingress-nginx` | un controlador que atiende `Ingress` | retirado desde marzo de 2026: sin parches |
| Gateway API | la API sucesora de `Ingress` | vigente; la usa este curso |

El Ejercicio 3 te deja ver un `Ingress` en este clúster, y qué le pasa cuando nadie lo atiende.

### 6.9 El orden: plataforma, espera, proyecto

Junta lo que viste. En 6.2, el proyecto antes que la plataforma: `no matches for kind`. En 6.4, el rango antes que el guardián: `failed calling webhook … connection refused`. En 6.6, el proyecto tampoco habría podido pedir su Gateway antes de que existiera la clase `eg`. En los tres casos, el archivo estaba bien. Lo que estaba mal era el momento.

Así se levanta lo de esta lección desde un clúster vacío, en tres pasos. No es un fragmento escrito de memoria: es el programa `levantar.sh`, y se corrió de verdad. `correr.sh` borra el clúster de los ejercicios, crea **otro** igual, con las dos imágenes cargadas y sin un solo recurso personalizado (`kubectl get crd` da `No resources found`), y ejecuta `levantar.sh` sin corregir nada a mano:

```bash
#!/usr/bin/env bash
# levantar.sh — Lección 6, sección 6.9: la plataforma y el proyecto, desde un
# clúster recién creado, en tres pasos y en este orden:
#   1. la plataforma: los tipos nuevos (CRD), sus controladores y sus guardianes;
#   2. la espera: tipos establecidos y controladores listos (kubectl wait);
#   3. la configuración de la plataforma (rango y clase) y después el proyecto.
#
# Uso, desde esta carpeta y con el clúster curso-k8s-l6 recién creado, las dos
# imágenes cargadas y token.txt generado:   ./levantar.sh
#
# 🔴 Antes de CADA cambio, ctx comprueba que el contexto activo es
# kind-curso-k8s-l6 y, si no, el guion se detiene: MetalLB y Envoy Gateway crean
# objetos que valen para todo el clúster, y aplicarlos en otro sería instalarlos
# en el clúster de otra persona.
set -euo pipefail
cd "$(dirname "$0")"

ctx() { [ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo" >&2; return 1; }; }
# paso CADENA → comprueba el contexto, imprime «$ CADENA» y la corre. Si falla, se detiene.
paso() { ctx; printf '\n$ %s\n' "$*"; eval "$@"; }

[ -f token.txt ] || { echo "falta token.txt: (umask 077; openssl rand -hex 16 > token.txt)" >&2; exit 1; }

echo "## Paso 1: la plataforma"
paso "kubectl apply -k infra/metallb"
paso "kubectl apply --server-side -k infra/envoy-gateway"

echo
echo "## Paso 2: la espera"
paso "kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
paso "kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s"
paso "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"

echo
echo "## Paso 3: la configuración de la plataforma, y el proyecto"
paso "kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml"
paso "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
paso "kubectl apply -k ."
paso "kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s"
```

La función `paso` hace tres cosas: comprueba el contexto con `ctx` (y se detiene si no es `kind-curso-k8s-l6`: MetalLB y Envoy Gateway crean objetos que valen para todo el clúster), imprime el comando con `$` y lo corre. Con `set -euo pipefail`, el primer error detiene el guion, así que una corrida sin interrupciones es la prueba de que el orden funciona.

El rango y la clase van en el **paso 3** y no en el 1 por lo que viste: el rango necesita que el *webhook* de MetalLB conteste (6.4.2) y la clase necesita que su CRD esté establecido (6.6.3). El README del curso los llama «tres pasos» aunque el bloque tenga más de tres comandos: los pasos son de **orden**, no de número de comandos. (En la Lección 10, los dos `apply` de plataforma del paso 1 se juntan en uno.) Esta es la salida de esa corrida:

```text
$ kubectl get crd
No resources found

$ ./levantar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb
namespace/metallb-system created
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io created
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io created
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io created
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io created
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io created
serviceaccount/controller created
serviceaccount/speaker created
role.rbac.authorization.k8s.io/controller created
role.rbac.authorization.k8s.io/pod-lister created
clusterrole.rbac.authorization.k8s.io/metallb-system:controller created
clusterrole.rbac.authorization.k8s.io/metallb-system:speaker created
rolebinding.rbac.authorization.k8s.io/controller created
rolebinding.rbac.authorization.k8s.io/pod-lister created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:controller created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:speaker created
configmap/metallb-excludel2 created
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway
namespace/envoy-gateway-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/clienttrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyextensionpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoypatchpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyproxies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutefilters.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/listenersets.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/securitypolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tcproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/udproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io serverside-applied
serviceaccount/eg-gateway-helm-certgen serverside-applied
serviceaccount/envoy-gateway serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-role serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-role serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-rolebinding serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-rolebinding serverside-applied
configmap/envoy-gateway-config serverside-applied
service/envoy-gateway serverside-applied
deployment.apps/envoy-gateway serverside-applied
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
(levantar.sh tardó 266 s)
```

Léela por pasos. Paso 1: un `created` por cada objeto de MetalLB y un `serverside-applied` por cada objeto de Envoy Gateway; el segundo manda de una vez los diez más tres CRD de Gateway API y los ocho de Envoy. Paso 2: cinco esperas, y todas terminan en `condition met` o `successfully rolled out`; el `speaker` va de 0 a 3 pods disponibles. Paso 3: el rango y la clase se crean juntos, la clase se espera hasta `Accepted`, el proyecto se crea completo (nueve `created`, sin un solo `no matches for kind`) y el Gateway llega a `Programmed`. Ningún error, y ningún `sleep`. Después, `correr.sh` comprueba lo que importa:

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         82s

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.165.26   172.18.255.200   80:31214/TCP   82s
(espera: la puerta ya contesta 200 en http://172.18.255.201/salud)

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}


$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

El Gateway y el `LoadBalancer` recibieron otra vez `172.18.255.201` y `.200`, en ese orden, la puerta contesta `/salud` y la tabla del reporte, y la `.200` también. (El Service de este clúster nuevo trae otro `NodePort`, `31214`, y el Gateway tardó `82s` en existir, porque el `kubectl apply` y las esperas del paso 3 corren antes de este `get`.) Con esto, la meta de la lección queda cumplida: un clúster nuevo, tres pasos, nada corregido a mano.

Tres ideas que vas a reconocer en la Lección 10, cuando todo el proyecto se levante con dos `apply -k` y una espera:

- **La plataforma se instala una vez por clúster; el proyecto, cada vez que cambia.** MetalLB y Envoy Gateway no son del `revisor`: el día que publiques un segundo servicio, usará la misma clase `eg` y el mismo rango.
- **La espera no es un `sleep`.** Un `sleep 30` funciona en tu máquina y falla en una más lenta. `kubectl wait` pregunta por la condición y falla con claridad si no llega en el tiempo que le diste.
- **El orden no se esconde.** Si lo automatizas (un guion, un paso de un *pipeline*), los tres pasos siguen ahí, con nombre, cada uno con su comprobación de contexto (`ctx`). Un guion que «reintenta hasta que pase» esconde la causa; uno que espera la condición la nombra.

## El error que vas a ver

El error de esta lección es el más común con Gateway API, y se parece al selector mal escrito de la Lección 3: una ruta que apunta a un Service que no existe. Se provoca con `fig06_01.ruta-mala.yaml`, un **programa** que falla a propósito: la misma `HTTPRoute`, con una letra de menos en el destino.

```yaml
# fig06_01.ruta-mala.yaml — FALLA A PROPÓSITO: la misma ruta del revisor con una
# letra de menos en el Service de destino (revisr). El Gateway la acepta, pero no
# encuentra a quién mandarle el tráfico: ResolvedRefs=False BackendNotFound, y la
# puerta responde 500. Se corrige volviendo a aplicar la kustomization (apply -k .).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisr
      port: 80
```

```text
$ kubectl apply -f fig06_01.ruta-mala.yaml
httproute.gateway.networking.k8s.io/revisor configured
```

`configured`, sin quejas. Igual que con el selector de la Lección 3, el `kube-apiserver` no puede saber que querías escribir `revisor`: `revisr` es un nombre válido. Se lee en orden.

**Primero, el síntoma**, desde fuera:

```text
$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|content-length)"
HTTP/1.1 500 Internal Server Error
content-length: 0
```

`500` y cuerpo vacío. Fíjate en lo que **no** es. No es un código de `curl` (6, 7 o 28): la conexión se hizo, alguien contestó. Y no es el `revisor`: el `revisor` nunca contesta con un cuerpo vacío. Quien contestó fue Envoy, la puerta, diciendo «no tengo a quién mandarte». La [especificación de Gateway API v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/) lo exige así: si todas las referencias de una regla son inválidas y la regla no tiene filtros, «todo el tráfico que coincida con esta regla DEBE recibir un código 500».

**Segundo, la puerta.** Si contestó, la puerta está bien:

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         2m1s
```

`PROGRAMMED True`, misma dirección. El problema está detrás.

**Tercero, las condiciones de la ruta.** Es el paso decisivo, el equivalente de la columna `ENDPOINTS` de la Lección 3:

```text
$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=False BackendNotFound

$ kubectl get httproute revisor -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].message}{"\n"}'
Failed to process route rule 0 backendRef 0: service default/revisr not found.
```

Dos condiciones, y aquí está la trampa: `Accepted=True`. La puerta aceptó la ruta. Quien mire solo esa condición, o solo `kubectl get httproute` (que no muestra ninguna), concluye que todo está bien. La que dice la verdad es la segunda: `ResolvedRefs=False`, motivo `BackendNotFound`. Y el mensaje, en inglés, no deja dudas: «falló al procesar la regla 0, referencia 0: no se encontró el Service `default/revisr`». (`.status.parents[0]` es el estado de la ruta respecto a su primera puerta; una ruta puede colgarse de varias, y cada una le pone sus condiciones.)

**Cuarto, la confirmación:**

```text
$ kubectl get service revisr
Error from server (NotFound): services "revisr" not found
[código de salida: 1]
```

**La corrección** es la causa, no la puerta: volver a aplicar el archivo bueno, que aquí es la kustomization completa.

```text
$ kubectl apply -k . | grep httproute
httproute.gateway.networking.k8s.io/revisor configured

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}
```

Como en la Lección 3, primero se mira que el estado esté bien (`ResolvedRefs=True`) y después se prueba. Entre que aplicas la ruta y que Envoy recibe su configuración nueva pasa un momento: si tu primer `curl` todavía da el código de antes (`200` después de la ruta mala, `500` después de la buena), repítelo. `correr.sh` espera a que la puerta conteste el código esperado antes de mostrar el `curl`, y lo anota en la salida como `(espera: la puerta ya contesta 500 …)`.

**El orden, para cualquier puerta que no responde bien:**

1. ¿Qué devuelve `curl`? Un código de `curl` (7, 28) es la red o la IP; un código HTTP (`404`, `500`) es que la puerta contestó.
2. ¿El Gateway tiene `ADDRESS` y `PROGRAMMED True`? Si no tiene dirección, mira MetalLB y su rango.
3. ¿La ruta tiene `Accepted=True` **y** `ResolvedRefs=True`? Lee las dos, y el `message` de la que esté en `False`.
4. Si todo eso está bien, baja un piso: el Service de destino y su EndpointSlice, con el orden de la Lección 3.

## El hábito de seguridad de la lección: se expone lo mínimo, por una puerta nombrada, y se dice qué falta

La tabla de hábitos del curso le asigna a esta lección tres cosas. Se comprueban con el clúster delante.

**Qué quedó expuesto.** Todo lo que recibe tráfico de fuera del clúster:

```text
$ kubectl get services -A -o custom-columns='ESPACIO:.metadata.namespace,NOMBRE:.metadata.name,TIPO:.spec.type,IP-EXTERNA:.status.loadBalancer.ingress[0].ip,NODEPORT:.spec.ports[*].nodePort' | grep -E 'ESPACIO|LoadBalancer|NodePort'
ESPACIO                NOMBRE                           TIPO           IP-EXTERNA       NODEPORT
default                revisor-publico                  LoadBalancer   172.18.255.200   30808
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   172.18.255.201   30581
```

Escrito como inventario, que es como se debe poder decir en voz alta:

| Puerta | Dirección | Qué deja pasar | Quién decide |
|---|---|---|---|
| `revisor-publico` | `172.18.255.200:80` | **todo** el `revisor`, sin reglas | nadie: es un `LoadBalancer` directo |
| su `NodePort` | `30808` en **cada** nodo | lo mismo | nadie |
| el Gateway `revisor` | `172.18.255.201:80` | lo que diga la `HTTPRoute` | la ruta, un archivo versionado |
| su `NodePort` | `30581` en cada nodo | lo mismo que el Gateway | la ruta |

Hoy hay **dos** puertas hacia el mismo servicio, y eso es una lección en sí: la directa se salta cualquier regla que pongas en la nombrada. El Ejercicio 2 lo mide: cuando la ruta del Gateway solo deja pasar `/salud`, la `.200` sigue entregando el reporte completo. Por eso «una puerta nombrada» es el hábito, y por eso la Lección 7 retira `revisor-publico` y deja el Gateway como la única entrada. Los `NodePort` siguen ahí por la razón de 6.3.3; en un clúster real, lo normal es que la red de los nodos no sea alcanzable desde fuera, y que un cortafuegos lo asegure.

**Qué no quedó expuesto.** Los nodos de kind siguen sin publicar nada hacia tu máquina, salvo el puerto de la API:

```text
$ docker port curso-k8s-l6-control-plane
6443/tcp -> 127.0.0.1:59736

$ docker port curso-k8s-l6-worker
```

Y desde tu terminal, en la Mac de las corridas, la IP del Gateway no existe:

```text
$ curl -s -m 3 http://172.18.255.201/salud
[código de salida: 28]
```

Este `curl` sí corrió en la terminal de la Mac, no en el contenedor. Código 28: se acabó el tiempo. La red `kind` vive dentro de la máquina virtual de Colima, y la Mac no tiene ruta hacia ella. En tu Linux Mint es distinto: Docker conecta tu máquina a la red `kind`, así que ahí la `.201` debería contestar desde tu terminal. Otra computadora de tu red no la alcanza: con las reglas que Docker pone por omisión (desde Docker Engine 28, que bloquea el acceso por enrutamiento directo a las redes de los contenedores), la red `kind` solo es visible desde tu propia máquina. Pero «tu máquina» incluye a todos sus usuarios: en una máquina compartida, cualquiera que tenga sesión en ella puede pedirle el reporte a `.200` o a `.201`, o a los `NodePort` de los tres nodos, y quien tenga `root` puede leer el token que viaja sin cifrar (por ejemplo, mirando el puente de Docker con `tcpdump`). Eso es lo que este laboratorio publica: poco, y solo hacia dentro de la máquina, pero no es «nadie».

**Qué falta: el cifrado.**

```text
$ curl -s -m 5 https://172.18.255.201/salud
[código de salida: 7]

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados -H 'Authorization: Bearer token-inventado'
401
```

Por `https`, código 7: nadie escucha en el 443, porque el Gateway solo tiene un *listener* `HTTP` en el 80. Y el segundo comando recuerda lo que viaja por esa puerta: el token del `revisor`, en un encabezado, **en texto plano**. Cualquiera que pueda mirar la red entre el cliente y la puerta lo lee. El `revisor` rechaza el token inventado (`401`), pero no puede hacer nada contra alguien que copió el bueno. La pieza que falta es un segundo *listener* en el Gateway, con `protocol: HTTPS`, puerto 443 y un `tls.certificateRefs` que apunte a un `Secret` con el certificado. La `HTTPRoute` no cambia. (`TLSRoute` y `BackendTLSPolicy`, de la lista de 6.6.3, son otras cosas: dejar pasar el cifrado sin abrirlo y cifrar el tramo de la puerta al Service.) Este curso no lo pone porque un certificado de verdad necesita un nombre de dominio de verdad, que un laboratorio en kind no tiene. Pero lo dice, que es el hábito: **una puerta sin cifrado se publica sabiendo que no lo tiene**, y en un clúster real no se publica así. La Lección 10 lo pone en la lista de lo que le falta a esto para ser producción.

## Lo que se hace mal

**Cambiar un Service a `NodePort` «para que lo vean».** Abre un puerto al azar en todos los nodos, sin nombre y sin reglas. Es la primera propuesta de la escena.

**Olvidar que todo `LoadBalancer` es también un `NodePort`.** Aunque la IP externa nunca llegue, el puerto de nodo ya está abierto (6.3.3).

**Instalar `ingress-nginx` porque lo dice un tutorial.** Sin parches de seguridad desde marzo de 2026. Y `Ingress`, la API, está congelada: lo nuevo se escribe con Gateway API.

**Correr Cloud Provider KIND en una máquina compartida.** Vigila todos los clústeres de kind de la máquina, no solo el tuyo.

**Aplicar el proyecto antes que la plataforma, y «arreglarlo» repitiendo el comando hasta que pase.** Funciona a veces y esconde la causa. Se instala la plataforma, se espera la condición con `kubectl wait` y después se aplica el proyecto.

**Esperar con `sleep`.** Un número de segundos que basta en tu máquina no basta en otra. Se espera a la condición, con `--timeout`.

**Instalar Envoy Gateway sin `--server-side`.** Tres de sus CRD no caben en la anotación del `apply` de siempre.

**Mirar solo `Accepted` en una ruta.** `Accepted=True` con `ResolvedRefs=False` es una ruta aceptada que no lleva a ningún lado. Se leen las dos condiciones.

**Elegir el rango de MetalLB al azar.** Tiene que caer en la red `kind`, lejos de las IP de los nodos, y no repetirse en dos clústeres vivos a la vez.

**Dejar dos puertas hacia el mismo servicio.** La que no tiene reglas se salta las reglas de la otra (Ejercicio 2).

**Publicar con HTTP plano sin decirlo.** El token viaja legible. Si un laboratorio no puede poner cifrado, por lo menos lo escribe en su lista de pendientes.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden y desde el estado en que quedó después de corregir el error. Antes de cada ejercicio, `kubectl config current-context` debe decir `kind-curso-k8s-l6`. `correr.sh` los corre igual, y su salida está en `correr.salida.txt`. **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — Soltar una dirección y volver a pedirla

Borra el Service `revisor-publico` con `kubectl delete service revisor-publico`. Predice: ¿qué responde `curl -s -m 3 http://172.18.255.200/salud` desde el cliente de fuera? ¿Qué `LoadBalancer` quedan en el clúster? Ahora vuelve a aplicar la kustomization con `kubectl apply -k .`: ¿qué IP recibe el Service nuevo, la `.200` que se liberó o la `.202`, la siguiente que nunca se usó? ¿Y su `NodePort`, es el mismo de antes? Compruébalo y explica.

### Ejercicio 2 — La puerta, reducida a lo mínimo

`fig06_02.solo-salud.yaml` es la misma `HTTPRoute` con una regla más estrecha: solo `GET` a `/salud`, exacto.

```yaml
# fig06_02.solo-salud.yaml — Ejercicio 2: la ruta del revisor, reducida a lo
# mínimo. Solo deja pasar GET /salud, exacto. Pregunta: ¿qué responde la puerta a
# /api/estados, con token y sin token? Se deshace con apply -k . (gateway.yaml).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: Exact
        value: /salud
      method: GET
    backendRefs:
    - name: revisor
      port: 80
```

Aplícalo y predice el código HTTP de cada una de estas cinco peticiones, todas desde el cliente de fuera: `GET /salud` por el Gateway; `GET /api/estados?formato=tabla` **con** el token, por el Gateway; `GET /salud/` (con diagonal al final) por el Gateway; `POST /salud` por el Gateway; y `GET /api/estados?formato=tabla` con el token, por `172.18.255.200`. Compruébalo con `curl -s -o /dev/null -w '%{http_code}\n'`. ¿Quién contesta cada `404`: Envoy o el `revisor`? ¿Qué dice la última respuesta sobre tener dos puertas? Al terminar, vuelve a aplicar `kubectl apply -k .`.

### Ejercicio 3 — Un `Ingress` que nadie atiende

`fig06_03.ingress.yaml` es un `Ingress` que manda todo al Service `revisor`, como la ruta de 6.7:

```yaml
# fig06_03.ingress.yaml — Ejercicio 3: un Ingress, la API congelada. El clúster
# lo acepta (la API existe desde siempre), pero en este clúster no hay ningún
# controlador de Ingress. Pregunta: ¿qué dirección recibe? ¿Quién la atiende?
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: revisor
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: revisor
            port:
              name: http
```

Antes de aplicarlo, corre `kubectl get ingressclass`. Predice: ¿el clúster acepta el `Ingress` o lo rechaza como rechazó el `Gateway` en 6.2? Si lo acepta, ¿qué dirección tendrá a los 15 segundos? Aplícalo, compruébalo con `kubectl get ingress revisor` y con `kubectl describe ingress revisor`, y explica la diferencia con 6.2 en dos frases. Bórralo al terminar.

### Ejercicio 4 — Defiende la decisión

Un compañero te dice: «la guía de kind recomienda Cloud Provider KIND, es un solo binario y te da LoadBalancer, Ingress y Gateway API sin instalar nada en el clúster. ¿Para qué tanto MetalLB y Envoy Gateway?». En cinco frases como máximo, contéstale: dónde corre Cloud Provider KIND, sobre qué clústeres actúa, qué pasaría en una máquina compartida, qué precio paga la solución del curso y cómo se controla ese precio.

## Soluciones

### Solución 1

Medido en `correr.salida.txt`:

```text
$ kubectl delete service revisor-publico
service "revisor-publico" deleted from default namespace

$ curl -s -m 3 http://172.18.255.200/salud
[código de salida: 28]

$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       2m18s

$ kubectl apply -k . | grep revisor-publico
service/revisor-publico created

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.129.166   172.18.255.200   80:31622/TCP   5s

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

**Sin el Service, `curl` no conecta**: sale con 28 (se acabó el tiempo) o, según tu sistema, con 7 (no pudo conectar; en Linux, «No route to host» cuando la pregunta ARP queda sin respuesta). Los dos dicen lo mismo: nadie contesta por `172.18.255.200`. No hay quien rechace con un HTTP, porque ningún `speaker` anuncia ya esa IP, la pregunta ARP queda sin respuesta y el paquete no tiene a dónde ir. Al borrar el Service, MetalLB **soltó** la dirección. Queda un solo `LoadBalancer`, el del Gateway, que no se enteró de nada: sigue en `.201`.

**El Service nuevo recibe otra vez la `.200`**, no la `.202`. MetalLB reparte la primera libre de su rango, y la `.200` volvió a estar libre. Pero es un objeto nuevo: otra `CLUSTER-IP` (`10.96.129.166` en lugar de `10.96.115.79`) y **otro `NodePort`** (`31622` en lugar de `30808`). La IP externa salió igual porque así funciona el reparto de MetalLB, no porque Kubernetes la recuerde. Si entre el borrado y la creación otro Service hubiera pedido una IP, se habría quedado con la `.200`, y tu Service con otra. Por eso, si una IP externa tiene que ser fija (porque está en un DNS o en la configuración de un cortafuegos), se pide por escrito en el Service, con la anotación `metallb.io/loadBalancerIPs: 172.18.255.200` (la [guía de uso de MetalLB](https://metallb.io/usage/) la prefiere sobre `spec.loadBalancerIP`, que está en camino de retirarse), y no se confía en el azar del orden.

### Solución 2

Medido en `correr.salida.txt`:

```text
$ kubectl apply -f fig06_02.solo-salud.yaml
httproute.gateway.networking.k8s.io/revisor configured

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud
200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud/
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -X POST http://172.18.255.201/salud
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
200
```

**`200`, `404`, `404`, `404` y `200`.** Por el Gateway solo pasa exactamente `GET /salud`. `/api/estados` no coincide con ninguna regla, ni con token: el token ni siquiera llega al `revisor`, porque **Envoy** contesta `404` antes. `/salud/` tampoco, porque `Exact` es exacto: una diagonal de más es otra ruta. Y `POST /salud` no coincide por el método. Los tres `404` son de la puerta: ninguna regla lleva esas peticiones al `revisor`, así que Envoy contesta por su cuenta.

**El quinto es el que importa:** por `172.18.255.200`, el `LoadBalancer` directo, el reporte sale completo, `200`. La regla que acabas de poner en la puerta nombrada no protege nada mientras exista otra puerta sin reglas. Es el argumento de la Lección 7 para retirar `revisor-publico`: reducir lo expuesto solo sirve si hay **una** sola entrada.

Al volver a aplicar la kustomization, la ruta regresa a `PathPrefix /` y `/api/estados` sin token vuelve a dar `401`, esta vez del `revisor`.

### Solución 3

Medido en `correr.salida.txt`:

```text
$ kubectl get ingressclass
No resources found

$ kubectl apply -f fig06_03.ingress.yaml
ingress.networking.k8s.io/revisor created

$ kubectl get ingress revisor
NAME      CLASS    HOSTS   ADDRESS   PORTS   AGE
revisor   <none>   *                 80      16s

$ kubectl describe ingress revisor | grep -E '^(Ingress Class|Address|Events):'
Address:          
Ingress Class:    <none>
Events:       <none>

$ kubectl delete -f fig06_03.ingress.yaml
ingress.networking.k8s.io "revisor" deleted from default namespace
```

**El clúster lo acepta, y nadie lo atiende.** A diferencia de `Gateway` en 6.2, el tipo `Ingress` viene dentro de Kubernetes, en el grupo `networking.k8s.io`: no hace falta ningún CRD para crearlo. Pero un `Ingress` es una declaración, igual que un `Gateway`, y sin un controlador que la lea no pasa nada: no hay `IngressClass` (`No resources found`), la columna `CLASS` dice `<none>`, `ADDRESS` está vacía y no hay un solo evento. Es el `<pending>` de 6.3 con otra cara: ningún error, ningún resultado. Envoy Gateway, el controlador que sí está instalado, atiende Gateway API y no este `Ingress`. Las dos frases: «`Gateway` no existía como tipo y el clúster lo rechazó; `Ingress` existe como tipo y el clúster lo guardó, pero nadie lo convierte en una puerta. Un objeto aceptado no es un objeto atendido».

### Solución 4

Una respuesta posible: «Cloud Provider KIND corre como un programa en tu máquina, fuera de los clústeres, con permisos para abrir puertos y hablar con Docker. Su propio README dice que vigila todos tus clústeres de kind, y no describe una opción para limitarse a uno; además, su controlador de Gateway API viene activado. En una máquina compartida, el programa que lancé para mi lección tocaría clústeres de otras personas sin que lo pidieran. MetalLB y Envoy Gateway viven dentro de mi clúster y se borran con él; el precio es que el rango de IP de MetalLB sale de la red kind, que sí es compartida. Ese precio se controla comprobando, antes de crear el clúster, que nadie contesta ya en la primera IP del rango, y corriendo un solo clúster con MetalLB a la vez.»

## Borrar el clúster

Cuando termines los ejercicios, borra el clúster de la lección. Con él se van MetalLB, Envoy Gateway, sus CRD y sus IP:

```text
$ kind delete cluster --name curso-k8s-l6
Deleting cluster "curso-k8s-l6" ...
Deleted nodes: ["curso-k8s-l6-control-plane" "curso-k8s-l6-worker" "curso-k8s-l6-worker2"]

$ kind get clusters | grep -c curso-k8s-l6
0
```

Después, borra `token.txt` y la carpeta temporal del `kubeconfig`, que guarda la credencial de administrador del clúster que acabas de borrar. El `rm -rf` es peligroso si la variable está vacía o apunta a otro lado, así que va protegido con un `case` que solo lo deja correr si la ruta es la que creó `mktemp` en 6.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 6.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l6.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt
```

Cerrar la terminal deja de usar ese `kubeconfig`, pero no lo borra: sin el `case`, la credencial se quedaría en `/tmp`. Comprueba además que no quedó ningún contenedor de cliente: `docker ps -a --filter name=curso-k8s-l6` no debe mostrar nada. Desde este momento, `172.18.255.200` vuelve a estar libre para el siguiente clúster que la necesite.

## Cómo sé que lo logré

- [ ] Explicas por qué `revisor-publico` se quedó en `<pending>` y demuestras con `curl` contra la IP de un nodo que su `NodePort` ya estaba abierto.
- [ ] Instalas MetalLB, le das el rango `172.18.255.200-172.18.255.220` y lees en los eventos del Service quién asignó la IP (`IPAllocated`) y desde qué nodo se anuncia (`nodeAssigned`).
- [ ] Ante `no matches for kind … ensure CRDs are installed first` dices qué falta (un CRD) y ante `failed calling webhook … connection refused` dices qué esperar (el controlador que contesta el *webhook*).
- [ ] Escribes de memoria los tres pasos: plataforma, `kubectl wait`, proyecto; y explicas por qué un `sleep` no es una espera.
- [ ] Explicas qué son `GatewayClass`, `Gateway` y `HTTPRoute`, a qué rol corresponde cada una y quién crea el Pod `envoy-default-revisor-…`.
- [ ] Ante un `500` de la puerta, revisas el Gateway, las dos condiciones de la ruta y el `message`, y encuentras un `BackendNotFound`.
- [ ] Haces el inventario de lo expuesto (las dos IP, los dos `NodePort`, el 6443 en `127.0.0.1`) y dices qué falta: cifrado.
- [ ] Explicas en una frase cada uno: por qué no Cloud Provider KIND, qué quiere decir que `Ingress` esté congelada y por qué no `ingress-nginx`.
- [ ] Corres `programas/06-entrar-al-cluster/correr.sh > /tmp/mi-corrida-l6.txt 2>&1` y comparas contra `correr.salida.txt` (no redirijas a ese archivo: es la referencia) lo que no cambia entre corridas: tres nodos `Ready` en `v1.37.0`; la red `172.18.0.0/16`; `No resources found` en los CRD; siete `created` y los dos `no matches for kind` de `Gateway` y `HTTPRoute`; `revisor-publico` en `<pending>` y `/salud` por el `NodePort` de dos nodos; el `failed calling webhook … connection refused` del primer intento con el rango (puede no salirte si tu máquina es más rápida que el arranque de MetalLB, y eso también enseña algo); nueve CRD de `metallb.io`; `ipaddresspool.metallb.io/curso created` al segundo intento; un `controller` y tres `speaker`; **`172.18.255.200`** en `revisor-publico`, con `IPAllocated` y `nodeAssigned … layer2`; `3` renglones `Too long` y el tope de `262144 bytes`; `10` CRD de Gateway API y `8` de Envoy Gateway; la `GatewayClass` `eg` con `ACCEPTED True` y diez tipos en `api-resources`; siete `unchanged` y dos `created`; el Gateway en **`172.18.255.201`** con `PROGRAMMED True`; `Accepted=True` y `ResolvedRefs=True`; un Pod `envoy-default-revisor-…` con `2/2`; `/salud` y la tabla por la puerta, y `401` sin token; con la ruta mala, `ResolvedRefs=False BackendNotFound`, `service default/revisr not found` y `HTTP/1.1 500`; el código 7 por `https`; en el Ejercicio 1, un código de `curl` (28 o 7) y la `.200` de vuelta; en el Ejercicio 2, `200 404 404 404 200`; en el Ejercicio 3, `Address` vacía; y al final `sin diferencias con los archivos`. Las IP de Pods, Services y nodos, los `NodePort`, los sufijos, las edades, el nodo que anuncia la IP, el orden de los renglones de `kind load` y las veces que se repite cada renglón de `rollout status` cambian en cada corrida: se observan, no se comparan.
- [ ] Desde un clúster recién creado, sin un solo recurso personalizado, corres `./levantar.sh` y llega hasta `Programmed` sin un error y sin corregir nada a mano; y dices por qué el rango y la clase van en el paso 3.
- [ ] Lees la salida de `kubectl get crd` de 6.6.2 y dices tres cosas: que los CRD de Gateway API son del canal `experimental`, que hay tres más de `x-k8s.io`, y que el *webhook* de Envoy es `Ignore` y los de MetalLB `Fail`.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l6`, la carpeta temporal del `kubeconfig` ya no existe en `/tmp`, y nadie contesta en `172.18.255.200`.

## Resumen

Responde sin mirar la lección:

1. ¿Por qué un `LoadBalancer` se queda en `<pending>` en kind? ¿Qué sí abre aunque se quede así?
2. ¿Qué hacen el `controller` y el `speaker` de MetalLB, y qué quiere decir «capa 2»?
3. ¿Por qué el rango de MetalLB sale de la red `kind`, y por qué del final?
4. ¿Qué es un CRD, y qué error da aplicar un objeto cuyo CRD no existe?
5. ¿Qué es un *webhook* de admisión, y qué hace el `kube-apiserver` cuando no puede llamarlo, según su `failurePolicy`? ¿Qué valor tienen los de MetalLB y qué valor tiene el de mutación de Envoy Gateway?
6. ¿Cuáles son los tres pasos para levantar plataforma y proyecto, y qué espera exactamente cada `kubectl wait` de esta lección?
7. ¿Por qué Envoy Gateway se instala con `--server-side`?
8. ¿Qué rol tiene cada una de las tres piezas de Gateway API, y quién crea el Pod que de verdad recibe las peticiones?
9. ¿Qué diferencia hay entre `Ingress`, `ingress-nginx` y Gateway API, y en qué estado está cada uno?
10. ¿Qué queda expuesto al terminar esta lección, y qué le falta a la puerta?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Service»](https://kubernetes.io/docs/concepts/services-networking/service/): el tipo `LoadBalancer`, aprovisionado por el proveedor de nube de forma asíncrona y publicado en `.status.loadBalancer`; su implementación sobre un `NodePort`; `allocateLoadBalancerNodePorts` y su valor por omisión `true`.
- [Kubernetes, «Gateway API»](https://kubernetes.io/docs/concepts/services-networking/gateway/): Gateway API como complemento definido con recursos personalizados; `GatewayClass`, `Gateway` y `HTTPRoute`; el diseño orientado a roles.
- [Kubernetes, «Ingress»](https://kubernetes.io/docs/concepts/services-networking/ingress/): la API de Ingress congelada, sin planes de quitarla; la recomendación de usar Gateway.
- [Kubernetes, blog, «Ingress NGINX Retirement: What You Need to Know»](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) (11 de noviembre de 2025): el fin del mantenimiento en marzo de 2026, sin versiones, correcciones ni parches de seguridad después; las instalaciones existentes siguen funcionando; la recomendación de migrar a Gateway API.
- [Kubernetes, «Custom Resources»](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/): qué es un recurso personalizado y qué crea un `CustomResourceDefinition`.
- [Kubernetes, «Dynamic Admission Control»](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): qué son los *webhooks* de admisión, de validación y de mutación; `failurePolicy` con `Fail` por omisión.
- [Kubernetes, «Deployments»](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): la condición `Available` como disponibilidad mínima según la estrategia de actualización.
- [Gateway API, «ReferenceGrant»](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): el permiso para referencias entre espacios de nombres; la unión ruta-Gateway entre espacios se decide en los *listeners* (`allowedRoutes`).
- [MetalLB, «Usage»](https://metallb.io/usage/): la anotación `metallb.io/loadBalancerIPs` para pedir una IP concreta.
- [Docker, «Docker Engine 28: hardening container networking by default»](https://www.docker.com/blog/docker-engine-28-hardening-container-networking-by-default/) y [«Port publishing and mapping»](https://docs.docker.com/engine/network/port-publishing/): por qué otra máquina de tu red no alcanza la red de los contenedores.
- [Kubernetes, «kubectl wait»](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): esperar una condición en el `Status` de uno o varios recursos; la bandera `--for`.
- [Kubernetes, «Server-Side Apply»](https://kubernetes.io/docs/reference/using-api/server-side-apply/): el plano de control lleva el registro de qué campos maneja cada quien; la comparación con la anotación `last-applied-configuration`.
- [kind, «LoadBalancer»](https://kind.sigs.k8s.io/docs/user/loadbalancer/): Cloud Provider KIND como binario independiente en tu máquina, con privilegios para abrir puertos y hablar con el *runtime* de contenedores.
- [kind, «Ingress»](https://kind.sigs.k8s.io/docs/user/ingress/): el soporte nativo de Ingress y Gateway API en Cloud Provider KIND.
- [Cloud Provider KIND, README](https://github.com/kubernetes-sigs/cloud-provider-kind): vigila todos los clústeres de kind; su controlador de Gateway API viene activado por omisión.
- [MetalLB, «Installation»](https://metallb.io/installation/): el manifiesto `metallb-native.yaml` de la v0.16.1; el `controller` y el `speaker`; los componentes quietos hasta que se configuran.
- [MetalLB, «Configuration»](https://metallb.io/configuration/): `IPAddressPool`, `L2Advertisement` y su asociación; la capa 2 respondiendo a ARP.
- [Envoy Gateway, «Install with Kubernetes YAML»](https://gateway.envoyproxy.io/docs/install/install-yaml/): `kubectl apply --server-side` con el `install.yaml` de la v1.9.2; el manifiesto trae los CRD de Gateway API y los de Envoy Gateway.
- [Gateway API, «HTTPRoute»](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/): sin `matches`, el prefijo `/` coincide con toda petición; cada `match` es independiente.
- [Gateway API, especificación v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/): las referencias inválidas de una regla y el código 500 obligatorio.
- [curl, «libcurl error codes»](https://curl.se/libcurl/c/libcurl-errors.html): los códigos 7 y 28.

---

**Siguiente:** [Lección 7 — Aislar: espacios, permisos y red](07-aislar-permisos-red.md)
