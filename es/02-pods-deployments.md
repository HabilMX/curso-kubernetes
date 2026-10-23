# Lección 2 — Pods y Deployments

Lunes, 8:50 de la mañana. A las 9:30 el equipo tiene la demostración del clúster nuevo y tu parte es la más sencilla: que el `revisor` aparezca corriendo, con tres copias. La imagen está en tu laptop desde el viernes, construida y probada con `docker run`. Escribes el manifiesto, lo aplicas, y `kubectl` responde `deployment.apps/revisor created`. Respiras. Pides los Pods y los tres dicen lo mismo: `ImagePullBackOff`. Alguien del equipo, sin levantar la vista, te dice: «bórralo y vuelve a aplicarlo». Lo haces. Mismo estado. Lo haces otra vez. Son las 9:05 y la imagen sigue ahí, en tu `docker image ls`, a dos centímetros del clúster que dice no encontrarla.

Borrar y volver a aplicar no iba a servir de nada en esta situación, porque el clúster no estaba confundido: te estaba diciendo exactamente qué le faltaba. Esta lección te enseña a escucharlo, a darle lo que pide y a entender qué objetos nacen cuando aplicas un Deployment. Así, cuando algo falle a las 9:05, sabrás dónde mirar.

**Tiempo:** 2 × 45 min

**Qué construyes:** el `revisor` corriendo en el clúster del curso, con tres réplicas que renacen cuando mueren, endurecido desde el primer manifiesto

**Qué aprendes:** por qué tu Docker y los nodos del clúster no comparten imágenes, y cómo `kind load docker-image` las lleva; el `ErrImagePull` que se provoca a propósito y cómo se lee; qué es un Pod, un ReplicaSet y un Deployment, y quién es dueño de quién; etiquetas y selectores; qué es un *rollout* y cómo se ve su historia; y el `securityContext` que lleva todo contenedor de este curso

**De dónde vienes.** De la [Lección 1](01-instalacion-primer-cluster.md): tienes `kubectl` y `kind` instalados con su suma de verificación, el límite de `inotify` ajustado y sabes crear, mirar y borrar el clúster de tres nodos del curso. De la [Lección 0](00-que-es-kubernetes.md) traes el mapa: el `kube-apiserver` guarda lo que declaras, los controladores lo persiguen, el `kube-scheduler` elige nodo y el `kubelet` arranca contenedores. Y del [curso de Docker](https://www.habil.mx/es/cursos/docker/) traes la imagen terminada del `revisor`, `curso-docker-revisor:1.6.0`.

**Qué no hace esta lección.** El `revisor` queda corriendo, pero todavía nadie le puede hablar: no hay un nombre estable para encontrarlo ni una forma de llegar a él desde tu máquina. Eso es la [Lección 3](03-services-dns.md), con los Services y el DNS del clúster. Tampoco se configura todavía desde fuera: la lista de servicios que revisa va escrita en el manifiesto y la [Lección 4](04-configuracion-secretos.md) la saca a un `ConfigMap`. Y el clúster no sabe aún si el `revisor` está sano o solo vivo: las sondas llegan en la [Lección 5](05-salud-recursos-apagado.md).

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1 y la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l2`. La máquina fue una Mac con procesador ARM y Docker Engine 29.2.1 dentro de una máquina virtual Linux (Colima), **no** Linux Mint, que es el sistema de referencia del curso. Lo que cambia en tu Mint: la arquitectura (`amd64` en lugar de `arm64`), las direcciones IP de los Pods, los sufijos al azar de los nombres de Pods y ReplicaSets, las edades y en qué nodo cae cada réplica. Los comandos son los mismos. El recorrido completo está en [`programas/02-pods-deployments/`](../programas/02-pods-deployments): `correr.sh` crea el clúster **sin** la imagen del `revisor`, recorre la lección en orden, corre los Ejercicios 1 a 3 y borra el clúster; tardó 2 minutos y 25 segundos medidos con el reloj de la terminal; el guion registra por su cuenta lo que tardó cada paso largo: crear el clúster y esperar a que estuviera listo, 34 segundos; cargar la imagen, 2; borrarlo, 1. Su salida es `correr.salida.txt`. Ahí, la parte del hábito de seguridad aparece antes que la del *rollout* (2.8), porque el guion la corre en ese orden.

## Al terminar vas a poder

- Comprobar con `crictl images` si una imagen está dentro de un nodo de kind, y cargarla con `kind load docker-image`.
- Provocar un `ErrImagePull`, leerlo con `kubectl describe` y `kubectl get events`, y decir qué significa cada renglón.
- Escribir de memoria el esqueleto de un Deployment (`replicas`, `selector`, `template`) y explicar por qué el selector y las etiquetas de la plantilla tienen que coincidir.
- Seguir con `ownerReferences` la cadena Deployment → ReplicaSet → Pod, y predecir qué pasa al borrar cada eslabón.
- Filtrar objetos con selectores de etiqueta (`-l app=revisor`, `-l 'app in (…)'`) y explicar qué es la etiqueta `pod-template-hash`.
- Leer la historia de un Deployment con `kubectl rollout history` y provocar un reinicio ordenado con `kubectl rollout restart`.
- Justificar cada línea del `securityContext` del `revisor` y reconocer el error `CreateContainerConfigError` que produce una contradicción en él.

## El porqué antes del cómo

En la Lección 0 viste un Deployment que mantenía tres copias de un contenedor que no hacía nada. Era la idea pura: declaras «quiero tres» y el clúster persigue ese número. Ahora toca la versión con un programa de verdad, y aparecen tres preguntas que el ejemplo de juguete escondía.

La primera: **¿de dónde saca el clúster la imagen?** La de la Lección 0 venía ya dentro del nodo, porque el propio Kubernetes la usa. La del `revisor` la construiste tú y vive en tu Docker. Un nodo de kind parece estar «en tu máquina», pero por dentro tiene su propio almacén de imágenes, que no es el de tu Docker. Es la causa exacta de la escena del lunes, y es lo primero que vas a ver fallar.

La segunda: **¿qué objetos existen y quién cuida a quién?** Un Deployment no corre contenedores. Crea un ReplicaSet, que crea Pods, que son los que corren. Si no ves esa cadena, «borrar un Pod» y «borrar el Deployment» parecen la misma operación, y no lo son: una se repara sola en un segundo y la otra apaga el servicio.

La tercera: **¿qué puede hacer el contenedor si alguien lo ataca?** Con `docker run` aprendiste a quitarle privilegios con `--user`, `--read-only` y `--cap-drop ALL`. En Kubernetes esas mismas decisiones se escriben en el manifiesto, en un bloque llamado `securityContext`, y este curso las pone desde el primer Deployment. No esperan a la Lección 7. La seguridad que se agrega al final se queda en una lista de pendientes; la que nace con el manifiesto viaja con él a cualquier clúster.

La lección tiene ocho partes de conceptos y después las secciones de siempre:

1. **Dos almacenes de imágenes** (2.1): tu Docker y el de cada nodo.
2. **El manifiesto del `revisor`, campo por campo** (2.2).
3. **Aplicar y no encontrar la imagen** (2.3), el error a propósito.
4. **`kind load docker-image`** (2.4) y el clúster que se recupera solo.
5. **La cadena de dueños** (2.5): Deployment, ReplicaSet y Pod.
6. **Etiquetas y selectores** (2.6).
7. **Un Pod suelto contra un Pod del Deployment** (2.7).
8. **El *rollout*** (2.8): revisiones, historia y reinicio.

Este es el destino. Al final de 2.4, el `revisor` está corriendo con tres réplicas, en un clúster que medio minuto antes no tenía su imagen:

```text
$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           32s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-697fb84f97   3         3         3       32s
```

## Si no traes la imagen del curso de Docker

Esta lección usa la imagen que entrega la Lección 10 del curso de Docker, `curso-docker-revisor:1.6.0`. Antes de seguir, comprueba que la tienes:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Si no la tienes, constrúyela desde el repositorio de ese curso, con el `Dockerfile` de su Lección 10 sobre la carpeta `programas/revisor` y con `--build-arg VERSION=1.6.0`, etiquetándola exactamente `curso-docker-revisor:1.6.0`. Si usas otra imagen de un servicio tuyo, esto es lo que el curso le pide, y conviene leerlo porque cada punto explica una decisión del manifiesto:

- **Escucha HTTP en un puerto alto**, el 8080, y responde `GET /salud` sin consultar a nadie más.
- **Corre con un usuario numérico que no es `root`**: el 65532, el usuario `nonroot` de las imágenes *distroless*. El manifiesto lo exige con `runAsNonRoot: true`.
- **Funciona con el sistema de archivos de solo lectura**, salvo una carpeta de datos (`/datos`), que el manifiesto monta aparte.
- **Trae su propia prueba de salud** como subcomando (`/revisor healthcheck`), porque la imagen no tiene *shell* ni `curl`.
- **Tiene una etiqueta fija**, nunca `:latest`. La sección 2.2.3 explica por qué eso importa en kind.
- **Se configura por variables de entorno.** El `revisor` exige `REVISOR_SERVICIOS`, con la lista de servicios que revisa, y entiende `REVISOR_PUERTO`, `REVISOR_REPORTE` y `REVISOR_TOKEN_ARCHIVO`. Una variable que no lee se ignora en silencio, así que no inventes otras.

## Los conceptos

### 2.1 Dos almacenes de imágenes

Esta lección usa su propio clúster, `curso-k8s-l2`, con la configuración de tres nodos de la Lección 1, recién creado y **sin** cargarle nada. Créalo así, desde la raíz del repositorio del curso, con el mismo cuidado que aprendiste en la Lección 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l2.XXXX)/kubeconfig"
# curso-k8s-l2 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l2 --config programas/02-pods-deployments/kind-curso.yaml
# Debe decir kind-curso-k8s-l2. Si dice otra cosa, no sigas.
kubectl config current-context
```

El `export` solo vale en esa terminal. Si abres otra, repite el `export` con la misma ruta, o `kubectl` le hablará a otro clúster. Las salidas de esta sección son de la corrida de `correr.sh`, que hace exactamente esto:

```text
$ kubectl config current-context
kind-curso-k8s-l2

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l2-control-plane   Ready    control-plane   26s   v1.37.0
curso-k8s-l2-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l2-worker2         Ready    <none>          16s   v1.37.0
```

El primer comando no es decoración. Es el hábito de la Lección 1: antes de cambiar algo, preguntar a qué clúster le hablas. En esta lección vas a crear y borrar objetos, y `kind-curso-k8s-l2` es la única respuesta que te deja seguir. Repítelo **antes de cada** `apply`, `delete`, `label` o `rollout restart` de la lección, no solo aquí. El guion lo hace solo: antes de cada `kubectl`, compara el contexto y se detiene si no es `kind-curso-k8s-l2`.

Ahora la pregunta de la escena. Tu Docker tiene la imagen; ¿la tiene el nodo? Recuerda de la Lección 0 que un nodo de kind es un contenedor que trae dentro su propio `containerd`, y ese `containerd` tiene su propio almacén de imágenes. Para preguntarle a él, se entra al nodo y se usa `crictl`, la herramienta de línea de comandos que habla con el *runtime* del nodo. La guía de inicio de kind la recomienda justo para esto ([kind, «Quick Start», sección «Loading an Image Into Your Cluster»](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)):

```text
$ docker exec curso-k8s-l2-worker crictl images | grep -c curso-docker-revisor
0
[código de salida: 1]
```

Cero. (El código de salida 1 es de `grep`, que así avisa que no encontró nada; no es un fallo del nodo.) La imagen está en tu máquina y no está en el nodo. Son dos almacenes distintos, aunque los dos vivan en la misma computadora, y nada los sincroniza.

En un clúster de verdad esto se resuelve con un **registro**: subes la imagen a un servidor de imágenes (Docker Hub, el registro de tu empresa o el de tu proveedor de nube) y cada nodo la descarga de ahí. En kind, que es un laboratorio en tu máquina, hay un atajo: copiar la imagen directo de tu Docker a cada nodo. Ese atajo es `kind load docker-image` y llega en 2.4. Primero vas a ver qué pasa sin él, porque el mensaje de error es de los que más vas a encontrar en tu vida con Kubernetes.

### 2.2 El manifiesto del `revisor`, campo por campo

Este es el manifiesto que la lección construye. Es un **programa**: se aplica solo y vive en `programas/02-pods-deployments/revisor-deployment.yaml`.

```yaml
# revisor-deployment.yaml — Lección 2: el revisor con tres réplicas que renacen.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  replicas: 3
  selector:
    matchLabels:
      app: revisor
  template:
    metadata:
      labels:
        app: revisor
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: revisor
        image: curso-docker-revisor:1.6.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8080
        env:
        - name: REVISOR_SERVICIOS
          value: "prueba http://prueba:9000/ 2s"
        # La imagen de Docker trae REVISOR_REPORTE=/datos/reporte.json: con el
        # sistema de archivos de solo lectura, /datos necesita un volumen. emptyDir
        # vive y muere con el Pod (la Lección 8 lo contrasta con un PVC).
        volumeMounts:
        - name: datos
          mountPath: /datos
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
      volumes:
      - name: datos
        emptyDir:
          sizeLimit: 10Mi
```

Parece mucho. Se lee por capas, de afuera hacia adentro, y cada capa responde una pregunta.

#### 2.2.1 Qué es y cómo se llama

Las tres primeras claves las lleva todo objeto de Kubernetes. `apiVersion: apps/v1` dice en qué grupo de la API vive el tipo: los Deployments viven en el grupo `apps`, versión `v1`, que es estable. `kind: Deployment` dice el tipo. Y `metadata` trae el nombre (`revisor`) y las etiquetas del propio Deployment (`app: revisor`). El nombre es único dentro de su espacio de nombres; las etiquetas, como verás en 2.6, no lo son, y ese es justo su valor.

#### 2.2.2 Cuántos, cuáles y con qué molde

`spec` es el estado deseado, y en un Deployment tiene tres piezas que van juntas:

- **`replicas: 3`**: cuántas copias quieres. Es el número que el clúster persigue.
- **`selector`**: cómo reconoce el Deployment a **sus** Pods. Aquí dice: «los míos son los que llevan la etiqueta `app: revisor`».
- **`template`**: el molde de cada Pod. Lleva sus propias etiquetas (`app: revisor`) y su propia `spec`, que es la de un Pod: contenedores, volúmenes y seguridad.

El selector y las etiquetas de la plantilla **tienen que coincidir**. Si el molde produjera Pods con `app: otro` y el selector buscara `app: revisor`, el Deployment crearía Pods que nunca reconocería como suyos y seguiría creando más, sin fin. Por eso el `kube-apiserver` rechaza un Deployment cuyo selector no coincide con las etiquetas de su plantilla, antes de guardarlo. La [documentación de Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) añade una advertencia que conviene tener presente desde ya: Kubernetes no impide que dos controladores tengan selectores que se traslapan, y si los tienen, «pueden entrar en conflicto y comportarse de forma inesperada». El Ejercicio 2 te muestra una versión de ese problema.

#### 2.2.3 El contenedor

Dentro de la plantilla, `containers` es una lista; en este curso siempre trae un solo contenedor. Sus campos:

- **`name: revisor`**: el nombre del contenedor dentro del Pod. Lo vas a ver en los eventos como `spec.containers{revisor}`.
- **`image: curso-docker-revisor:1.6.0`**: la imagen, con su etiqueta fija.
- **`imagePullPolicy: IfNotPresent`**: cuándo descargar la imagen. `IfNotPresent` significa «descárgala solo si no está ya en el nodo». La [documentación de imágenes](https://kubernetes.io/docs/concepts/containers/images/) define también `Always` (preguntarle al registro cada vez que arranca un contenedor; el *runtime* solo descarga las capas que le faltan, pero si el registro no responde o no tiene la imagen, falla aunque el nodo ya la tenga) y `Never` (no intentar descargarla nunca). Si omites el campo, Kubernetes lo decide según la etiqueta: con una etiqueta que no es `:latest` pone `IfNotPresent`, y con `:latest` o sin etiqueta pone `Always`. Esto es lo que hace que `:latest` sea una trampa en kind: con `Always`, el nodo intentaría ir a Docker Hub aunque ya le hubieras cargado la imagen, y fallaría. La guía de kind lo advierte: con `:latest` o sin etiqueta la política por omisión es `Always`, y pide no usar `:latest` o escribir `imagePullPolicy: IfNotPresent` (o `Never`) ([kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)). El manifiesto escribe `IfNotPresent` aunque sería el valor por omisión, para que quien lo lea no tenga que saberse la regla.
- **`ports`**: declara que el contenedor escucha en el 8080 y le da un nombre, `http`. Declararlo no publica nada ni abre ningún puerto hacia fuera: es información para quien lea el manifiesto y para los objetos que lo usen después. En la Lección 3, el Service apuntará al puerto **por su nombre**, `http`, y no por su número.
- **`env`**: las variables de entorno. Aquí va una sola, `REVISOR_SERVICIOS`, la que el `revisor` exige, con un servicio llamado `prueba` en `http://prueba:9000/` y un tiempo límite de 2 segundos. Ese servicio todavía no existe en el clúster, y no importa: el `revisor` arranca igual y lo reportará con estado `FALLA` cuando alguien le pida el reporte. En la Lección 4 esta lista sale del manifiesto y pasa a un `ConfigMap`.

#### 2.2.4 El volumen `datos`

Al final hay un volumen, `datos`, de tipo `emptyDir`, montado en `/datos`. Está ahí por una razón concreta. La imagen del curso de Docker define `REVISOR_REPORTE=/datos/reporte.json`: cada vez que alguien le pide el reporte, el `revisor` lo guarda en ese archivo. Pero el `securityContext` del contenedor (2.2.5) pone **todo** su sistema de archivos en solo lectura. Sin un volumen, el `revisor` arrancaría sin quejarse y fallaría después, la primera vez que intentara guardar un reporte: en su código, ese caso responde con un error 500 y el mensaje `no pude guardar el reporte`.

Un `emptyDir` es la forma más sencilla de dar un lugar donde escribir. La [documentación de volúmenes](https://kubernetes.io/docs/concepts/storage/volumes/) lo describe así: se crea cuando el Pod se asigna a un nodo, empieza vacío, y «cuando un Pod se quita de un nodo por cualquier razón, los datos del `emptyDir` se borran para siempre». Si el contenedor se cae y se reinicia, los datos sobreviven, porque el Pod sigue en el nodo. El `sizeLimit: 10Mi` le pone tope: un reporte pesa unos cuantos kilobytes, y un tope evita que un error llene el disco del nodo. La Lección 8 contrasta este `emptyDir` con un volumen persistente y mide qué se pierde con cada uno.

#### 2.2.5 Los dos `securityContext`

Hay dos bloques `securityContext`: uno a nivel del Pod (`template.spec.securityContext`) y otro a nivel del contenedor. El del Pod vale para todos sus contenedores; el del contenedor, solo para él. La sección «El hábito de seguridad de la lección» los desarma línea por línea, con el clúster mostrando qué hace cada uno. Por ahora basta con la idea: el contenedor corre como el usuario 65532, no puede volverse `root`, no tiene ninguna capacidad especial del núcleo, no puede escribir en su propio sistema de archivos y queda bajo el filtro de llamadas al sistema que trae el *runtime*.

### 2.3 Aplicar y no encontrar la imagen

Con el clúster recién creado y sin la imagen cargada, se aplicó el manifiesto:

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created
```

Recuerda de la Lección 0 qué significa esa respuesta: el objeto se **guardó**. No dice nada de contenedores. Veinte segundos después:

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS             RESTARTS   AGE
revisor-697fb84f97-gn68x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-qvs7x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-vq4ld   0/1     ImagePullBackOff   0          20s
```

Los tres Pods existen, cada uno ya tiene nodo, y ninguno corre: `0/1` en `READY` quiere decir «cero de un contenedor listo». El estado, `ImagePullBackOff`, es la escena del lunes. Fíjate en lo que **sí** funcionó: el Deployment creó su ReplicaSet, el ReplicaSet creó tres Pods y el `kube-scheduler` los repartió. Todo el plano de control hizo su trabajo. Lo que falló está al final de la cadena, en el `kubelet` de cada nodo, que no pudo conseguir la imagen.

La sección «El error que vas a ver» lee este error renglón por renglón. La versión corta, para seguir: el `kubelet` buscó la imagen en el nodo, no la encontró y, como la política es `IfNotPresent`, intentó descargarla. La imagen no dice de qué registro viene, así que fue a Docker Hub, donde no existe. Lo intenta otra vez, cada vez esperando un poco más. Borrar y volver a aplicar no cambia nada de eso: el Pod nuevo cae en un nodo que tampoco tiene la imagen y llega al mismo lugar.

### 2.4 `kind load docker-image`: llevar la imagen a cada nodo

El remedio es darle al nodo lo que pide:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 --name curso-k8s-l2
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-control-plane", loading...
```

`kind` sacó la imagen de tu Docker y la copió dentro de **cada** nodo del clúster, uno por renglón: «todavía no está en el nodo tal, cargando». Aparece también el nodo de control, aunque ahí no corre ningún Pod del `revisor`. kind no sabe dónde vas a usar la imagen y la pone en todos. Tardó 2 segundos, porque la imagen pesa unos 16 MB. El `--name curso-k8s-l2` es obligatorio cuando el clúster no se llama `kind`, que es el nombre por omisión. Sin él, kind buscaría un clúster que no existe, y en una máquina con varios clústeres es la forma de saber que cargas la imagen en el tuyo y no en otro.

Ahora el nodo sí la tiene:

```text
$ docker exec curso-k8s-l2-worker crictl images | grep curso-docker-revisor
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Mira el nombre con el que quedó guardada: `docker.io/library/curso-docker-revisor`. Es el nombre completo que corresponde a `curso-docker-revisor`: cuando una imagen no dice de qué registro viene, se entiende que es de Docker Hub (`docker.io`) y, si tampoco dice de qué usuario, de su espacio de imágenes oficiales (`library`). La documentación de imágenes lo explica con el ejemplo de `busybox`, que equivale a `docker.io/library/busybox:latest`. Es el mismo nombre que aparecía en el error de 2.3, y por eso ahora el `kubelet` la encuentra. (Los números parecen distintos, pero tienen explicación. `crictl` dice 3.68MB. Con Docker Engine 29, `docker image ls curso-docker-revisor:1.6.0` muestra dos columnas: `DISK USAGE` 16.2MB, lo que ocupa descomprimida en disco, y `CONTENT SIZE` 3.68MB, el contenido comprimido; `crictl` reporta esta segunda. Si tu Docker es anterior, `docker image ls` muestra una sola cifra y puede no coincidir. El identificador de `crictl`, `70e09194319be`, tampoco es el `sha256:bd1b2e7d…` de `kind load`: cada herramienta identifica la imagen con un resumen distinto. Que sea la misma lo prueban el nombre y la etiqueta, y que el `kubelet` la encuentre en el siguiente paso.)

No hace falta volver a aplicar nada. El `kubelet` seguía reintentando por su cuenta; en el siguiente intento encontró la imagen y arrancó el contenedor:

```text
$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-gn68x   1/1     Running   0          33s   10.244.1.3   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   10.244.1.2   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   10.244.2.2   curso-k8s-l2-worker    <none>           <none>
```

Esta es la lección de fondo de la escena: **el clúster se recuperó solo porque el estado deseado nunca cambió**. Seguía diciendo «tres réplicas con esta imagen». Lo único que faltaba era la imagen, y en cuanto llegó, cada pieza terminó su trabajo. Borrar y volver a aplicar habría sido, en el mejor caso, inútil.

Mira la columna `NODE`. Dos réplicas quedaron en `curso-k8s-l2-worker2` y una en `curso-k8s-l2-worker`. El Deployment cuida **cuántas** réplicas hay, no **dónde** quedan. La Lección 0 lo anticipó: el *scheduler* procura repartir, pero no lo garantiza, y en otra corrida pueden caer distinto. Si se apagara `worker2`, dos de las tres réplicas morirían a la vez. El reparto garantizado se declara con reglas propias, y el curso lo hace cuando el `revisor` tenga que sobrevivir a un nodo apagado (Lección 9). Fíjate también en la columna `IP`: cada Pod tiene la suya, y cambia cada vez que un Pod renace. Por eso nadie debe hablarle a un Pod por su IP, y por eso existe la Lección 3.

La bitácora del `revisor` confirma que el programa arrancó:

```text
$ kubectl logs deployment/revisor
Found 3 pods, using pod/revisor-697fb84f97-gn68x
revisor 1.6.0 escuchando en :8080 (1 servicio(s))
```

`kubectl logs deployment/revisor` es un atajo: elige uno de los Pods del Deployment y te muestra el suyo, y te dice cuál eligió. Es la misma línea que imprimía con `docker run` en el curso de Docker: la imagen es la misma, solo cambió quién la corre.

### 2.5 La cadena de dueños: Deployment, ReplicaSet y Pod

En la Lección 0 viste la cadena dibujada. Ahora se puede leer en el propio clúster, porque cada objeto dice quién es su dueño en un campo llamado `metadata.ownerReferences`. La [documentación de dueños y dependientes](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) lo explica así: los objetos dependientes tienen ese campo, que apunta a su dueño, y Kubernetes lo llena solo para los objetos que crean los controladores, como los ReplicaSets.

```text
$ kubectl get pod revisor-697fb84f97-gn68x -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ReplicaSet/revisor-697fb84f97

$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
Deployment/revisor

$ kubectl get deployment revisor -o jsonpath='{.metadata.ownerReferences}{"\n"}'

```

El Pod pertenece al ReplicaSet, el ReplicaSet pertenece al Deployment, y el Deployment no pertenece a nadie: su respuesta es un renglón vacío. El Deployment lo escribiste tú, y el dueño eres tú.

La opción `-o jsonpath=…` merece un momento, porque el curso la usa mucho. `kubectl get` puede devolver el objeto completo (`-o yaml`), pero casi siempre quieres un solo dato. `jsonpath` te deja pedir un campo por su ruta: `{.metadata.ownerReferences[0].kind}` significa «del objeto, entra a `metadata`, luego a `ownerReferences`, toma el primer elemento y dame su `kind`». El `{"\n"}` del final solo agrega un salto de línea.

Cada eslabón tiene un trabajo distinto:

| Objeto | Lo crea | Su trabajo | Si lo borras |
|---|---|---|---|
| **Deployment** | tú | guardar el estado deseado y administrar versiones: cuando cambias la plantilla, crea un ReplicaSet nuevo y pasa las réplicas del viejo al nuevo | se borran sus ReplicaSets y sus Pods; el servicio se apaga |
| **ReplicaSet** | el Deployment | contar: que haya tantos Pods con su plantilla exacta como dice `replicas` | el Deployment crea otro igual, pero `kubectl delete` borra en cascada sus Pods: medido, los tres Pods pasaron a `Terminating` a la vez y el reemplazo arrancó de cero, con un corte; por eso no se tocan a mano |
| **Pod** | el ReplicaSet | correr el contenedor | el ReplicaSet crea otro |

La [documentación de ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/) define su propósito en una frase: «mantener un conjunto estable de Pods réplica corriendo en todo momento». Y recomienda no usarlos directamente: «recomendamos usar Deployments en lugar de ReplicaSets directamente», salvo casos especiales. La de Deployments es todavía más tajante: «no administres ReplicaSets que pertenecen a un Deployment». En este curso nunca vas a escribir un ReplicaSet. Vas a **verlos**, porque leerlos explica lo que hace el Deployment.

¿Y el Pod? La [documentación de Pods](https://kubernetes.io/docs/concepts/workloads/pods/) lo dice sin rodeos: «rara vez vas a crear Pods individuales directamente en Kubernetes, ni siquiera Pods solitarios», porque los Pods están diseñados como entidades «relativamente efímeras y desechables». La sección 2.7 te muestra qué quiere decir «desechable» con un Pod sin dueño.

### 2.6 Etiquetas y selectores

Hasta aquí has escrito `-l app=revisor` muchas veces. Es momento de ver qué hay detrás.

Una **etiqueta** es un par clave y valor pegado a un objeto. La [documentación de etiquetas](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) las define como pares que «sirven para especificar atributos identificadores de los objetos, significativos para los usuarios», y agrega lo que las hace útiles: «a diferencia de los nombres y los UID, las etiquetas no son únicas». Muchos objetos llevan la misma. Con un **selector** de etiquetas eliges un conjunto de objetos, y según la misma página, el selector es «la primitiva central de agrupación en Kubernetes».

Así se ven las etiquetas de los Pods del `revisor`:

```text
$ kubectl get pods --show-labels
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
revisor-697fb84f97-gn68x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
```

`app=revisor` la pusiste tú, en la plantilla. Pero hay otra que no escribiste: `pod-template-hash=697fb84f97`. La puso el Deployment, y el número es el mismo sufijo que lleva el nombre del ReplicaSet. Mira el selector del ReplicaSet:

```text
$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.spec.selector}{"\n"}'
{"matchLabels":{"app":"revisor","pod-template-hash":"697fb84f97"}}
```

El ReplicaSet no busca solo `app: revisor`: busca `app: revisor` **y** `pod-template-hash: 697fb84f97`. La documentación de Deployments explica por qué: el controlador de Deployments agrega esa etiqueta a cada ReplicaSet que crea, calculada con un *hash* de la plantilla del Pod, y «esta etiqueta asegura que los ReplicaSets hijos de un Deployment no se traslapen». Cuando cambies la plantilla, en 2.8, aparecerá otro ReplicaSet con otro *hash*. Cada uno contará solo sus propios Pods, aunque todos lleven `app=revisor`. La misma página tiene un aviso en rojo: «no cambies esta etiqueta».

Los selectores tienen dos formas. La de **igualdad** es la que has usado: `app=revisor`, o `app!=revisor` para lo contrario. La de **conjuntos** pregunta por pertenencia:

```text
$ kubectl get pods -l 'app in (revisor,prueba)' -o name
pod/revisor-697fb84f97-gn68x
pod/revisor-697fb84f97-qvs7x
pod/revisor-697fb84f97-vq4ld

$ kubectl get pods -l app=prueba
No resources found in default namespace.
```

El primero pide los Pods cuya etiqueta `app` sea `revisor` o `prueba`, y como todavía no hay ningún `prueba`, devuelve solo los del `revisor`. El segundo lo confirma. Dos reglas de la documentación para no equivocarte: varios requisitos separados por coma se combinan con «y» (`app=revisor,pod-template-hash=697fb84f97` exige los dos), y **no existe** un operador «o» entre requisitos distintos. Para un «o» sobre una misma clave está `in`.

`No resources found` no es un error. Es una respuesta: no hay nada que coincida. Distinguir «no hay nada» de «algo falló» es parte de leer lo que dice el clúster.

¿Por qué el curso busca siempre por etiqueta y nunca por nombre de Pod? Porque el nombre cambia cada vez que el Pod renace, y la etiqueta no. Un comando que escribe `revisor-697fb84f97-gn68x` deja de servir en cuanto ese Pod muere. Uno que escribe `-l app=revisor` sigue funcionando a través de los reemplazos, dentro del mismo espacio de nombres y mientras ningún otro Pod use esa etiqueta (el Ejercicio 2 muestra qué pasa cuando alguno la usa). Los Services de la Lección 3 eligen sus Pods igual: por etiqueta. Eso vuelve importante lo que muestra el Ejercicio 2.

### 2.7 Un Pod suelto contra un Pod del Deployment

#### 2.7.1 El Pod suelto

Un Pod se puede crear solo, sin Deployment. Este manifiesto es un **programa** (`fig02_01.pod.yaml`). Es la misma plantilla del Deployment, pero escrita como Pod, con nombre fijo y **sin** la etiqueta `app: revisor`, para que ningún ReplicaSet lo confunda con uno de los suyos:

```yaml
# fig02_01.pod.yaml — un Pod suelto: el revisor sin Deployment que lo cuide.
# Sirve para ver qué hace un Pod por sí solo, y qué NO hace: si lo borras, nadie
# lo repone. No lleva etiqueta app: revisor a propósito, para que ningún
# ReplicaSet lo confunda con uno de los suyos.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-suelto
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: revisor
    image: curso-docker-revisor:1.6.0
    imagePullPolicy: IfNotPresent
    ports:
    - name: http
      containerPort: 8080
    env:
    - name: REVISOR_SERVICIOS
      value: "prueba http://prueba:9000/ 2s"
    volumeMounts:
    - name: datos
      mountPath: /datos
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
  volumes:
  - name: datos
    emptyDir:
      sizeLimit: 10Mi
```

Fíjate en la diferencia con el Deployment: `apiVersion: v1` (los Pods viven en el grupo central de la API, que no lleva nombre) y `kind: Pod`. Lo que en el Deployment estaba dentro de `template.spec`, aquí está directo en `spec`. Un Deployment es, en buena parte, un molde de Pod con un contador encima.

```text
$ kubectl apply -f fig02_01.pod.yaml
pod/revisor-suelto created

$ kubectl get pod revisor-suelto -o jsonpath='{.metadata.name} dueños={.metadata.ownerReferences}{"\n"}'
revisor-suelto dueños=

$ kubectl delete pod revisor-suelto
pod "revisor-suelto" deleted from default namespace

$ kubectl get pods
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-gn68x   1/1     Running   0          40s
revisor-697fb84f97-qvs7x   1/1     Running   0          40s
revisor-697fb84f97-vq4ld   1/1     Running   0          40s
```

`dueños=` vacío: nadie es dueño de este Pod. Se borró, el guion esperó cinco segundos y `revisor-suelto` ya no está. Nadie lo repuso, porque ningún controlador tenía «quiero un `revisor-suelto`» en su estado deseado.

Ojo con lo que un Pod suelto **sí** hace. Si su **proceso** se cae, el `kubelet` lo vuelve a arrancar dentro del mismo Pod, porque el campo `restartPolicy` vale `Always` por omisión ([kubernetes.io, «Pod Lifecycle»](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). Se parece a un `docker run --restart always` en una sola máquina: aguanta que el programa truene, y la columna `RESTARTS` lo cuenta. Lo que no aguanta es perder el Pod mismo. La documentación de Pods dice que un Pod se queda en su nodo «hasta que termina, se borra el objeto Pod, se desaloja por falta de recursos o el nodo falla», y la de su ciclo de vida agrega que un Pod nunca se «reprograma» a otro nodo: en su lugar, alguien puede crear uno nuevo casi idéntico. En un Pod suelto, ese alguien no existe. Si lo borran, lo desalojan o se apaga su nodo, se acabó.

#### 2.7.2 El Pod del Deployment

Ahora lo mismo con un Pod que sí tiene dueño:

```text
$ kubectl delete pod revisor-697fb84f97-gn68x
pod "revisor-697fb84f97-gn68x" deleted from default namespace

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-nrwht   1/1     Running   0          1s
revisor-697fb84f97-qvs7x   1/1     Running   0          41s
revisor-697fb84f97-vq4ld   1/1     Running   0          41s

$ kubectl get events --field-selector involvedObject.kind=ReplicaSet,reason=SuccessfulCreate -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message
OBJETO               MENSAJE
revisor-697fb84f97   Created pod: revisor-697fb84f97-vq4ld
revisor-697fb84f97   Created pod: revisor-697fb84f97-gn68x
revisor-697fb84f97   Created pod: revisor-697fb84f97-qvs7x
revisor-697fb84f97   Created pod: revisor-697fb84f97-nrwht
```

Un segundo después hay un Pod nuevo, `nrwht`, y los eventos cuentan la historia: tres creaciones al principio y una cuarta, la reposición. Es el termostato de la Lección 0, ahora con tu programa.

`-o custom-columns=…` es la hermana de `jsonpath` para tablas: le dices qué columnas quieres y de qué campo sale cada una. Se usó aquí para que cada evento cupiera en un renglón.

La comparación es la idea más importante de la lección: **el Pod corre, pero quien lo repone es su dueño.** Un Pod sin dueño reinicia su contenedor si el proceso se cae, pero el Pod mismo no renace: si se borra, se desaloja o se pierde su nodo, se acabó. Por eso, en este curso, todo lo que debe seguir corriendo vive dentro de un Deployment. Los Pods sueltos aparecen solo para depurar o para demostrar algo, y se borran al terminar.

### 2.8 El *rollout*: revisiones, historia y reinicio

#### 2.8.1 Qué es una revisión

Un **rollout** es el paso de una versión de los Pods a otra. La documentación de Deployments dice cuándo ocurre, y la regla es precisa: un *rollout* se dispara «si y solo si la plantilla del Pod del Deployment (`.spec.template`) cambia», por ejemplo sus etiquetas o su imagen. Otros cambios, como escalar de tres a cinco réplicas, no lo disparan. Cada *rollout* deja una **revisión** en la historia, y cada revisión es un ReplicaSet.

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
```

Una revisión: la que nació con el `apply`. La columna `CHANGE-CAUSE` dice `<none>` porque nadie anotó el motivo. Se puede llenar con una anotación del Deployment; el curso no lo hace, porque el motivo de cada cambio vive en el historial de Git de tus manifiestos.

#### 2.8.2 Reiniciar sin cambiar nada

A veces quieres que todos los Pods se reemplacen sin cambiar la imagen ni la configuración: por ejemplo, para que vuelvan a leer algo que cambió fuera de ellos. Borrarlos a mano funciona, pero los borras todos a la vez y el servicio se queda sin réplicas un momento. Para eso existe `kubectl rollout restart`:

```text
$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-55cc969586   3         3         3       2s
revisor-697fb84f97   0         0         0       55s
```

Lee el avance de `rollout status`: uno de tres nuevos, dos de tres, y al final «una réplica vieja pendiente de terminar». Los Pods no se reemplazaron de golpe: se fue creando uno nuevo y quitando uno viejo, por turnos. Esa es la estrategia por omisión de un Deployment, `RollingUpdate`. Sus dos perillas valen 25 % si no las tocas: `maxSurge`, cuántos Pods de más puede haber durante el cambio (se redondea hacia arriba), y `maxUnavailable`, cuántos pueden faltar (se redondea hacia abajo). Con tres réplicas, el 25 % es 0.75: `maxSurge` queda en 1 y `maxUnavailable` en 0. Dicho en simple: durante el cambio puede haber hasta cuatro Pods, y el controlador no retira ninguno viejo hasta que el nuevo esté listo, así que su plan nunca baja de tres disponibles. Es una promesa del controlador, no del universo: si un nodo cae o un proceso muere en ese momento, la cuenta baja por causas ajenas a él. Y con otro número de réplicas el redondeo cambia: con cuatro, el 25 % ya es 1 y `maxUnavailable` valdría 1. La Lección 9 vuelve a esto con carga de verdad y mide si se pierde alguna petición.

Y el resultado: un ReplicaSet nuevo, `revisor-55cc969586`, con las tres réplicas, y el viejo, `revisor-697fb84f97`, en `0 0 0`. El viejo **no se borró**: se quedó vacío, como registro de la revisión 1. La documentación dice que, por omisión, se guardan 10 ReplicaSets viejos (`revisionHistoryLimit`), y que borrar uno es perder la posibilidad de volver a esa revisión. La Lección 9 usa esa posibilidad con `rollout undo`.

¿Por qué hubo *rollout* si no cambiaste nada? Sí cambió algo:

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>


$ kubectl get deployment revisor -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
{"kubectl.kubernetes.io/restartedAt":"2026-10-21T03:55:53-06:00"}
```

`rollout restart` agregó a la plantilla una anotación con la hora del reinicio. La plantilla cambió y la regla «si y solo si» se cumplió: nueva plantilla, nuevo *hash*, nuevo ReplicaSet, revisión 2. No hay magia, solo la misma regla aplicada a un campo que pusiste sin teclearlo.

Esa anotación no está en tu archivo, y eso tiene una consecuencia. Si mañana aplicas `revisor-deployment.yaml` otra vez, `kubectl apply` no la quita, porque solo administra los campos que el archivo declara (la Lección 0 explicó la anotación `last-applied-configuration`, que es como lleva esa cuenta). El estado final de esta lección lo comprueba con `kubectl diff`, que no encuentra diferencias.

## El error que vas a ver

El error de esta lección es el de 2.3: `ErrImagePull`, que después se vuelve `ImagePullBackOff`. Se provocó a propósito y se lee en orden, porque ese orden sirve para cualquier Pod que no arranca.

**Primero, el estado.** `kubectl get pods` te dio `ImagePullBackOff` y `0/1`. La columna `STATUS` te dice **en qué etapa** se atoró el Pod. Un `Pending` a secas suele querer decir «todavía no tiene nodo» (el *scheduler* no encontró lugar; lo verás en la Lección 5). Cuando hay algo más concreto, `kubectl` muestra eso en lugar de la fase: `ImagePullBackOff` es «ya tiene nodo, y el `kubelet` de ese nodo no consigue la imagen», y `CrashLoopBackOff` sería «la imagen arrancó y el programa se cae». Un matiz: la **fase** del Pod, que es otro campo, sigue siendo `Pending` mientras se descarga la imagen. La documentación del ciclo de vida lo dice así: `Pending` incluye el tiempo de espera a que se asigne un nodo y «el tiempo de descarga de las imágenes por la red» ([kubernetes.io, «Pod Lifecycle»](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). La fase se lee con `kubectl get pod <pod> -o jsonpath='{.status.phase}'`. Solo con la columna `STATUS` ya sabes a qué pieza de la Lección 0 preguntarle.

**Segundo, los eventos.** El clúster deja constancia de cada intento:

```text
$ kubectl get events --field-selector reason=Failed -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message | head -4
OBJETO                     MENSAJE
revisor-697fb84f97-gn68x   Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
revisor-697fb84f97-gn68x   Error: ErrImagePull
revisor-697fb84f97-gn68x   Error: ImagePullBackOff
```

El primer mensaje es largo, y se lee como una cadena de «porque», de izquierda a derecha:

- `Failed to pull image "curso-docker-revisor:1.6.0"`: no pude descargar la imagen que pediste…
- `failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0"`: …que, con su nombre completo, es esta de Docker Hub…
- `failed to resolve reference`: …porque no pude encontrar esa referencia…
- `pull access denied, repository does not exist or may require authorization`: …porque Docker Hub me negó el acceso: el repositorio no existe o pide credenciales.

La pista decisiva es `docker.io/library/…`. El nodo fue a buscar tu imagen a internet. Nunca miró tu Docker, porque no puede: no es su almacén. Docker Hub dice «no existe o necesitas permiso» y no aclara cuál de las dos. Así se comportan los registros, para no revelar qué repositorios privados existen. Aquí es lo primero: no existe.

**Tercero, `describe`.** `kubectl get events` mezcla los eventos de todo el espacio de nombres. `kubectl describe pod` junta todo lo de **un** Pod, y sus eventos al final. Ojo: un evento repetido se agrupa en un solo renglón y se ordena por la **última** vez que ocurrió, así que `Pulling (x2 over 20s)` aparece después de `BackOff` aunque ocurrió primero:

```text
$ kubectl describe pod revisor-697fb84f97-gn68x | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned default/revisor-697fb84f97-gn68x to curso-k8s-l2-worker2
  Normal   BackOff    19s               kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     19s               kubelet            spec.containers{revisor}: Error: ImagePullBackOff
  Normal   Pulling    6s (x2 over 20s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
```

(El `sed` corta la salida para mostrar solo desde `Events:`; arriba de eso, `describe` trae la imagen, el nodo, los volúmenes, el `securityContext` y las condiciones del Pod.) La columna `From` dice **quién** habla, y es la que más te enseña. En orden lógico:

- `default-scheduler`, `Scheduled`: el *scheduler* asignó el Pod a `curso-k8s-l2-worker2`. Su parte salió bien.
- `kubelet`, `Pulling`: el `kubelet` de ese nodo intentó descargar la imagen. `(x2 over 20s)` quiere decir que el mismo evento pasó dos veces en 20 segundos; el clúster agrupa los repetidos en vez de escribirlos todos.
- `kubelet`, `Failed` con `ErrImagePull`: el intento falló.
- `kubelet`, `BackOff` y `Failed` con `ImagePullBackOff`: el `kubelet` decidió esperar antes del siguiente intento.

**`ErrImagePull` y `ImagePullBackOff` son el mismo problema en dos momentos.** `ErrImagePull` es el fallo de un intento. `ImagePullBackOff` es la espera entre intentos. La documentación de imágenes lo explica: la parte `BackOff` indica que Kubernetes seguirá intentando, con una espera que crece en cada intento, hasta un límite fijo de 300 segundos (5 minutos). Por eso el Pod alterna entre los dos estados mientras no le des la imagen. Y por eso la recuperación de 2.4 no fue inmediata para cualquier Pod que estuviera en medio de una espera larga: el `kubelet` toma la imagen en su siguiente intento, no antes. Si un Pod lleva mucho tiempo esperando y no quieres aguardar, borrarlo **después** de corregir la causa sí sirve: el ReplicaSet crea otro, que intenta de inmediato. Borrar **antes** de corregir es lo que hizo el equipo de la escena.

**El orden, para cualquier Pod que no arranca:** el estado (`get pods`), el `describe` del Pod (sus eventos y la columna `From`) y, si el contenedor llegó a arrancar, sus `logs`. Primero se lee y después se cambia algo. Y lo que se cambia es la causa, no el Pod.

## El hábito de seguridad de la lección: `securityContext` desde el primer manifiesto

La tabla de hábitos del curso le asigna a esta lección el `securityContext` del primer Deployment: sin `root`, sin escalada de privilegios, sin capacidades, sistema de archivos de solo lectura y perfil `seccomp`. Así quedó aplicado en el clúster:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
{"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}
{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}
```

El primer renglón es el del Pod; el segundo, el del contenedor. Línea por línea, con lo que evita cada una:

| Línea | Qué hace | Qué evita | Su equivalente en Docker |
|---|---|---|---|
| `runAsNonRoot: true` | el `kubelet` se niega a arrancar el contenedor si fuera a correr como usuario 0 | que una imagen mal hecha, o una línea mal escrita, corra como `root` sin que nadie lo note | no tiene: Docker no verifica |
| `runAsUser: 65532`, `runAsGroup: 65532` | fija el usuario y el grupo numéricos con los que corre el proceso | depender de lo que diga la imagen; el número queda escrito en el manifiesto | `--user 65532:65532` |
| `seccompProfile: RuntimeDefault` | aplica el filtro de llamadas al sistema que trae el *runtime* | que el proceso use llamadas del núcleo que un servidor HTTP nunca necesita. **Sin esta línea, Kubernetes corre el contenedor sin filtro (`Unconfined`)**, salvo que el `kubelet` tenga activada la opción `seccompDefault` | Docker aplica su perfil por omisión sin que lo pidas; Kubernetes no |
| `allowPrivilegeEscalation: false` | un proceso no puede ganar más privilegios que su padre, por ejemplo ejecutando un binario *setuid* | que alguien que entre al contenedor se vuelva `root` desde dentro | `--security-opt no-new-privileges` |
| `capabilities: drop: ["ALL"]` | quita todas las capacidades especiales del núcleo | que el proceso pueda, por ejemplo, cambiar el dueño de archivos (`CHOWN`) o abrir *sockets* crudos para fabricar paquetes de red (`NET_RAW`) | `--cap-drop ALL` |
| `readOnlyRootFilesystem: true` | monta el sistema de archivos del contenedor en solo lectura | que un atacante deje herramientas o modifique el programa | `--read-only` |

Las definiciones salen de la guía oficial [«Configure a Security Context for a Pod or Container»](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/). Sobre `allowPrivilegeEscalation`, por ejemplo, dice que «controla si un proceso puede obtener más privilegios que su proceso padre» y que activa la bandera `no_new_privs` del núcleo. Y el tutorial de `seccomp` explica la diferencia con Docker que marca la tabla: si la opción `seccompDefault` está activada, los Pods usan `RuntimeDefault` cuando no piden otro perfil; «si no, el valor por omisión es `Unconfined`» ([kubernetes.io, «Restrict a Container's Syscalls with seccomp»](https://kubernetes.io/docs/tutorials/security/seccomp/)). Por eso la línea se escribe siempre.

Hay una referencia que importa más que cualquier guía: los **Pod Security Standards**, los tres niveles de seguridad que define Kubernetes ([kubernetes.io, «Pod Security Standards»](https://kubernetes.io/docs/concepts/security/pod-security-standards/)). El más estricto, `restricted`, está pensado para «hacer cumplir las mejores prácticas actuales de endurecimiento de Pods». Exige cuatro de estas líneas: correr como no-`root` (`runAsNonRoot: true`), no permitir escalada de privilegios, quitar **todas** las capacidades (solo deja volver a agregar `NET_BIND_SERVICE`) y fijar explícitamente el perfil `seccomp` («tanto el perfil `Unconfined` como la ausencia de perfil están prohibidos»). Además, `restricted` prohíbe pedir `runAsUser: 0` (justo lo que hace `fig02_02.raiz.yaml`, más abajo) y solo permite ciertos tipos de volumen, entre ellos `emptyDir`. El manifiesto del `revisor` cumple todo eso desde hoy. Cuando la Lección 7 ponga el espacio de nombres en nivel `restricted`, el `revisor` ya estará listo, y no habrá que reescribir nada a última hora.

`readOnlyRootFilesystem` **no** lo exige `restricted`. El curso lo pone porque el `revisor` lo aguanta: su único archivo de escritura va a `/datos`, y para eso existe el `emptyDir`.

**Lo que se ve desde dentro.** La imagen del `revisor` no tiene *shell*. Se comprobó:

```text
$ kubectl exec deployment/revisor -- /revisor healthcheck
sano

$ kubectl exec deployment/revisor -- /revisor version
1.6.0

$ kubectl exec deployment/revisor -- sh -c 'id'
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "d8ccff765090d70932ea2f15a41fa34693c57f56ad0106eeb012a0a816fa701d": OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH
[código de salida: 1]
```

`kubectl exec` corre un programa dentro de un contenedor que ya está corriendo, como `docker exec`. Con `deployment/revisor`, elige uno de sus Pods. Los dos subcomandos del propio `revisor` funcionan: `healthcheck` consulta su `/salud` desde dentro y responde `sano`, y `version` dice `1.6.0`. Pero `sh` no existe: `executable file not found in $PATH`. Eso no es un defecto, es una defensa. Quien logre ejecutar algo dentro del contenedor no encuentra *shell*, ni `curl`, ni gestor de paquetes. La forma de depurar sin *shell* llega en la Lección 3: un Pod aparte, hecho para eso.

Los montajes del contenedor confirman el volumen de datos y revelan algo más:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.containers[0].volumeMounts}{"\n"}'
[{"mountPath":"/datos","name":"datos"},{"mountPath":"/var/run/secrets/kubernetes.io/serviceaccount","name":"kube-api-access-vxlgn","readOnly":true}]
```

`/datos` es tu `emptyDir`. El segundo montaje no lo escribiste: Kubernetes montó en el Pod una **credencial** para hablar con el `kube-apiserver`, la de la cuenta de servicio por omisión del espacio de nombres. El `revisor` nunca le habla al servidor de la API, así que no la necesita. Queda anotado como deuda conocida, con su lección: la Lección 7 le da al `revisor` su propia cuenta de servicio, sin permisos, y desde ahí todas las cuentas del curso llevan `automountServiceAccountToken: false`, para que esa credencial no se monte.

**La red de seguridad en acción.** `runAsNonRoot` parece redundante si ya escribiste `runAsUser: 65532`. Su valor aparece cuando alguien se equivoca. Este Pod (`fig02_02.raiz.yaml`, un **programa** que falla a propósito) pide las dos cosas a la vez: no ser `root` y ser el usuario 0, que es `root`:

```yaml
# fig02_02.raiz.yaml — FALLA A PROPÓSITO: pide correr como root (runAsUser: 0)
# y a la vez exige no ser root (runAsNonRoot: true). El kubelet se niega a
# arrancar el contenedor. Es la red de seguridad de runAsNonRoot en acción.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-raiz
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 0
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: revisor
    image: curso-docker-revisor:1.6.0
    imagePullPolicy: IfNotPresent
    env:
    - name: REVISOR_SERVICIOS
      value: "prueba http://prueba:9000/ 2s"
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

```text
$ kubectl apply -f fig02_02.raiz.yaml
pod/revisor-raiz created

$ kubectl get pod revisor-raiz
NAME           READY   STATUS                       RESTARTS   AGE
revisor-raiz   0/1     CreateContainerConfigError   0          10s

$ kubectl get events --field-selector involvedObject.name=revisor-raiz,reason=Failed -o custom-columns=MENSAJE:.message | head -2
MENSAJE
Error: container's runAsUser breaks non-root policy (pod: "revisor-raiz_default(49586352-b84d-462b-9ded-e41bb2d2123a)", container: revisor)
```

El `kube-apiserver` aceptó el Pod (`created`), porque no hay nada inválido en su forma. Quien se negó fue el `kubelet`, al ir a crear el contenedor: `CreateContainerConfigError`, «la configuración del contenedor no se puede usar», y el evento dice por qué: «el `runAsUser` del contenedor rompe la política de no-`root`». La imagen estaba en el nodo y el programa nunca llegó a correr. Esa es la función de `runAsNonRoot`: una segunda llave que no depende de que la primera esté bien escrita. El Pod se borró al terminar.

**Lo que defiende y lo que no.** El `securityContext` limita lo que puede hacer **el proceso** si alguien lo compromete: no ser `root`, no ganar privilegios, no modificar sus archivos. No defiende al `revisor` de peticiones maliciosas (eso es su código), no decide quién le puede hablar (eso es la red, Lección 7) y no protege tu máquina del nodo de kind, que, como viste en la Lección 0, es un contenedor privilegiado.

## Lo que se hace mal

**Borrar y volver a aplicar ante un error.** Es la escena del lunes. Si la causa no cambió, el Pod nuevo llega al mismo error. Primero se lee el `describe`, después se corrige la causa.

**Usar `:latest` en kind.** Con `:latest` o sin etiqueta, la política de descarga por omisión es `Always`, y el nodo intenta ir al registro aunque ya le hayas cargado la imagen. Además, `:latest` no dice qué versión corre: dos nodos pueden tener dos imágenes distintas con la misma etiqueta. Etiqueta fija y `IfNotPresent`.

**Olvidar `--name` en `kind load docker-image`.** Sin él, kind busca el clúster llamado `kind`. Si no existe, falla. Si existe y no es el tuyo, cargaste la imagen en el lugar equivocado y tu clúster sigue sin ella.

**Crear Pods sueltos para algo que debe seguir corriendo.** Un Pod sin dueño no renace. Para un servicio, siempre un Deployment.

**Poner en un Pod suelto las etiquetas de un Deployment.** Lo vas a ver en el Ejercicio 2: el Deployment no lo adopta, pero todo lo que busque por esa etiqueta lo encuentra. Es un Pod que aparece en los conteos y en el tráfico sin que nadie lo cuide.

**Editar o borrar a mano el ReplicaSet de un Deployment.** El Deployment es su dueño y lo reconstruye. La documentación lo dice con todas sus letras: no administres ReplicaSets que pertenecen a un Deployment.

**Tocar la etiqueta `pod-template-hash`.** La pone el Deployment para que sus ReplicaSets no se pisen. Cambiarla rompe esa separación.

**Quitar el `securityContext` «para que funcione».** Si un contenedor no arranca con el `securityContext` del curso, el problema casi siempre está en la imagen (corre como `root`, escribe donde no debe) y se arregla en la imagen o con un volumen, no quitándole defensas al manifiesto.

**Fiarse de `Running`.** Sin el `emptyDir`, el `revisor` también estaría `Running` y `1/1`, y fallaría en la primera petición que le pidiera guardar el reporte. `Running` quiere decir que el proceso vive, no que hace bien su trabajo. La Lección 5 le enseña al clúster a distinguirlo.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden y desde el estado en que quedó al final de 2.8. Antes de cada ejercicio, `kubectl config current-context` debe decir `kind-curso-k8s-l2`; si dice otra cosa, no sigas. `correr.sh` los corre igual, y su salida está en `correr.salida.txt`. **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — Sacar un Pod del rebaño

Elige uno de los Pods del `revisor` y cámbiale la etiqueta `app` a otro valor:

```bash
kubectl label pod <un-pod-del-revisor> app=fuera --overwrite
```

Predice: ¿cuántos Pods hay cinco segundos después? ¿El Pod que cambiaste sigue corriendo? ¿Quién es su dueño ahora? Compruébalo con `kubectl get pods -L app` (la opción `-L` agrega una columna con el valor de esa etiqueta) y con el `jsonpath` de 2.7.1, `-o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'`, que sí sirve cuando la lista de dueños está vacía (el `[0]` de 2.5 sobre una lista vacía imprime solo una barra, `/`, y sale con código 0, sin avisar que no había nada). Al terminar, borra el Pod que sacaste.

### Ejercicio 2 — El Pod que se cuela (proyecto)

`fig02_03.adoptado.yaml` es un Pod suelto, `revisor-extra`, idéntico a los del `revisor` y **con** la etiqueta `app: revisor`:

```yaml
# fig02_03.adoptado.yaml — Ejercicio 2: un Pod suelto que SÍ lleva app: revisor.
# Pregunta: el Deployment selecciona app: revisor. ¿Se queda con este Pod? ¿Borra
# uno de los suyos para seguir en tres? ¿Y qué ve quien busca por app=revisor?
apiVersion: v1
kind: Pod
metadata:
  name: revisor-extra
  labels:
    app: revisor
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: revisor
    image: curso-docker-revisor:1.6.0
    imagePullPolicy: IfNotPresent
    ports:
    - name: http
      containerPort: 8080
    env:
    - name: REVISOR_SERVICIOS
      value: "prueba http://prueba:9000/ 2s"
    volumeMounts:
    - name: datos
      mountPath: /datos
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
  volumes:
  - name: datos
    emptyDir:
      sizeLimit: 10Mi
```

Antes de aplicarlo, responde las tres preguntas de su comentario. Después aplícalo y compruébalo con `kubectl get pods -l app=revisor`, `kubectl get deployment revisor` y el selector de los ReplicaSets. Para terminar, explica qué problema causaría este Pod cuando, en la Lección 3, un Service elija sus Pods por `app: revisor`. Bórralo al terminar.

### Ejercicio 3 — Una etiqueta que no existe

`fig02_04.etiqueta-mala.yaml` es el mismo Deployment con una sola diferencia: pide la imagen `curso-docker-revisor:1.6.9`, que no existe ni en tu Docker ni en el clúster. Antes de aplicarlo, predice: ¿cuántos Pods del `revisor` quedan corriendo mientras el *rollout* está atorado? ¿Cuántos Pods nuevos intenta crear? (Pista: los números de `maxSurge` y `maxUnavailable` de 2.8.2.) Después aplícalo, espera con `kubectl rollout status deployment/revisor --timeout=40s` y mira `kubectl get pods -l app=revisor` y `kubectl get deployment revisor`. Para salir del atasco, vuelve a aplicar `revisor-deployment.yaml` y explica por qué el *rollout* termina al instante.

### Ejercicio 4 — Defiende el `securityContext`

Un compañero te propone quitar `readOnlyRootFilesystem: true` y el volumen `datos` «porque son dos cosas que mantener y el `revisor` arranca igual». En cinco frases como máximo, contéstale: qué evita esa línea, por qué el volumen existe justamente por ella, qué pasaría con el reporte si quitas solo el volumen y dejas la línea, y si quitarla rompe o no el nivel `restricted`.

## Soluciones

### Solución 1

Medido en `correr.salida.txt`:

```text
$ kubectl label pod revisor-55cc969586-6m76h app=fuera --overwrite
pod/revisor-55cc969586-6m76h labeled

$ kubectl get pods -L app
NAME                       READY   STATUS    RESTARTS   AGE   APP
revisor-55cc969586-6m76h   1/1     Running   0          8s    fuera
revisor-55cc969586-7tmfc   1/1     Running   0          7s    revisor
revisor-55cc969586-f8dk6   1/1     Running   0          6s    revisor
revisor-55cc969586-x6vfq   1/1     Running   0          5s    revisor

$ kubectl get pod revisor-55cc969586-6m76h -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=
```

**Cuatro Pods.** El que cambiaste sigue `Running`: cambiarle una etiqueta no lo detiene. Pero dejó de coincidir con el selector del ReplicaSet, así que el ReplicaSet lo **soltó** (su `ownerReferences` quedó vacío) y, como ahora contaba dos donde debía haber tres, creó uno nuevo. Quedan los tres del rebaño, más uno suelto que nadie cuida. La documentación de ReplicaSet describe esta técnica: puedes sacar Pods de un ReplicaSet cambiando sus etiquetas, por ejemplo «para depuración o recuperación de datos», y los que saques así se reemplazan solos. Es útil: dejas aparte un Pod que se porta mal para estudiarlo, sin que el servicio pierda una réplica. Pero no lo olvides ahí: el guion lo borró al terminar.

### Solución 2

Medido en `correr.salida.txt`. (`fig02_03.adoptado.yaml` declara el puerto `http`, igual que la plantilla del Deployment. El campo es informativo y no cambia ninguna de estas salidas, pero importa para el tráfico de la Lección 3: por eso el Pod es idéntico a los del Deployment.)

```text
$ kubectl apply -f fig02_03.adoptado.yaml
pod/revisor-extra created

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running   0          13s
revisor-55cc969586-f8dk6   1/1     Running   0          12s
revisor-55cc969586-x6vfq   1/1     Running   0          11s
revisor-extra              1/1     Running   0          5s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           67s

$ kubectl get pod revisor-extra -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=

$ kubectl get replicaset -l app=revisor -o custom-columns=NOMBRE:.metadata.name,DESEADOS:.spec.replicas,SELECTOR:.spec.selector.matchLabels
NOMBRE               DESEADOS   SELECTOR
revisor-55cc969586   3          map[app:revisor pod-template-hash:55cc969586]
revisor-697fb84f97   0          map[app:revisor pod-template-hash:697fb84f97]
```

Las tres respuestas:

1. **No se queda con él.** `revisor-extra` sigue sin dueño. La razón está en el selector del ReplicaSet: no busca solo `app: revisor`, busca también `pod-template-hash: 55cc969586`, y `revisor-extra` no lleva esa etiqueta. La documentación de ReplicaSet dice que un ReplicaSet adopta de inmediato a un Pod sin dueño que coincide con **su** selector, y que por eso conviene que los Pods sueltos no lleven etiquetas que coincidan con el selector de un ReplicaSet. Aquí la etiqueta `pod-template-hash` evitó la adopción.
2. **No borra ninguno de los suyos.** El Deployment dice `3/3`: para él solo existen sus tres.
3. **Quien busca por `app=revisor` ve cuatro.** `kubectl get pods -l app=revisor` lista a `revisor-extra` como si fuera una réplica más.

Ese tercer punto es el problema. Un Service, en la Lección 3, elige sus Pods por etiqueta, y por la del manifiesto, `app: revisor`, no por `pod-template-hash`, y apunta al puerto que se llama `http`. Este Pod suelto lleva las dos cosas: la etiqueta y el puerto con ese nombre. Así que este Pod, que nadie repone si muere y que nadie actualiza cuando cambias la imagen, recibiría su parte del tráfico como si fuera una réplica más. Es justo lo que la documentación quiere decir cuando advierte que los selectores que se traslapan producen comportamientos inesperados. El guion lo borró al terminar.

### Solución 3

Medido en `correr.salida.txt`:

```text
$ kubectl apply -f fig02_04.etiqueta-mala.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS         RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running        0          55s
revisor-55cc969586-f8dk6   1/1     Running        0          54s
revisor-55cc969586-x6vfq   1/1     Running        0          53s
revisor-b8b699487-fc4gn    0/1     ErrImagePull   0          41s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     1            3           109s
```

**Tres Pods viejos siguen corriendo y hay un solo Pod nuevo, atorado en `ErrImagePull`.** Con tres réplicas, `maxSurge` es 1 (puede haber un Pod de más) y `maxUnavailable` es 0 (no puede faltar ninguno). El Deployment creó un Pod nuevo y, para quitar uno viejo, esperó a que el nuevo estuviera disponible. Nunca lo estuvo, así que no quitó ninguno. `kubectl get deployment` lo resume: `READY 3/3` (el servicio sigue completo), `UP-TO-DATE 1` (solo una réplica tiene la plantilla nueva). **Aquí, un *rollout* con una imagen rota no tumba el servicio**: se atora con el servicio intacto, porque con tres réplicas `maxUnavailable` es 0. No es una ley: con cuatro réplicas el 25 % ya es 1 y el Deployment sí retiraría una réplica sana antes de saber si la nueva arranca, y si un Pod viejo cae mientras el *rollout* está atorado, la capacidad baja. `rollout status` se rindió a los 40 segundos porque se lo pediste; el Deployment, por su cuenta, esperaría 600 segundos (`progressDeadlineSeconds`, cuyo valor por omisión según la documentación es 600) antes de marcar el *rollout* como fallido con la condición `ProgressDeadlineExceeded`.

Al volver a aplicar el archivo bueno:

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           109s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-55cc969586   3         3         3       56s
replicaset.apps/revisor-697fb84f97   0         0         0       109s
replicaset.apps/revisor-b8b699487    0         0         0       41s
```

Terminó al instante porque la plantilla volvió a ser **idéntica** a la del ReplicaSet `revisor-55cc969586`: la misma imagen y la misma anotación de `restartedAt`, que `apply` no quita porque el archivo no la declara. Mismo molde, mismo *hash*, mismo ReplicaSet. El Deployment no creó uno nuevo: dejó a cero el roto, `revisor-b8b699487`, y como el bueno ya tenía sus tres réplicas, no hubo nada más que hacer. Volver a la versión anterior con `kubectl rollout undo` es la forma corta de hacer esto, y llega en la Lección 9. Aquí se hizo de la forma que enseña el curso: el archivo es la verdad, y se vuelve a aplicar.

### Solución 4

Una respuesta posible: «`readOnlyRootFilesystem` impide que alguien que entre al contenedor modifique el programa o deje herramientas, y es barato porque el `revisor` solo escribe un archivo. Justo por esa línea existe el volumen `datos`: es el único lugar donde el `revisor` puede escribir su reporte. Si quitas el volumen y dejas la línea, el `revisor` arranca y se ve `Running`, pero la primera vez que intente guardar un reporte responde 500 con `no pude guardar el reporte`. Quitar la línea no rompe el nivel `restricted`, que no la exige, pero renuncias a una defensa que no cuesta nada. Y "arranca igual" no es la prueba: lo que importa es si sigue funcionando cuando alguien lo ataca y cuando alguien le pide trabajo.»

## Borrar el clúster

Cuando termines los ejercicios, borra el clúster de la lección. No dejes nada vivo en la máquina:

```text
$ kind delete cluster --name curso-k8s-l2
Deleting cluster "curso-k8s-l2" ...
Deleted nodes: ["curso-k8s-l2-worker" "curso-k8s-l2-worker2" "curso-k8s-l2-control-plane"]

$ kind get clusters | grep -c curso-k8s-l2
0
```

El `--name` es obligatorio aquí también: sin él, kind borraría el clúster llamado `kind`, que puede ser de otra persona o de otro proyecto. Después, borra la carpeta temporal del `kubeconfig` (la que creó `mktemp`, con el prefijo `/tmp/curso-k8s-l2.`) o cierra esa terminal. El clúster de la siguiente lección se crea de cero, igual que este.

## Cómo sé que lo logré

- [ ] Ante `ImagePullBackOff`, dices qué pieza falló (el `kubelet` del nodo) y por qué el mensaje menciona `docker.io/library/…`, sin buscarlo.
- [ ] Compruebas con `docker exec <nodo> crictl images` si una imagen está en un nodo de kind, y la cargas con `kind load docker-image <imagen> --name <clúster>`.
- [ ] Escribes de memoria el esqueleto de un Deployment y explicas por qué `selector` y `template.metadata.labels` deben coincidir.
- [ ] Predices qué pasa al borrar un Pod suelto, un Pod de un Deployment y el Deployment completo.
- [ ] Explicas para qué sirve la etiqueta `pod-template-hash` y por qué el Pod del Ejercicio 2 no fue adoptado.
- [ ] Justificas cada línea del `securityContext` del `revisor` y dices cuáles exige el nivel `restricted`.
- [ ] Corres `programas/02-pods-deployments/correr.sh > /tmp/mi-corrida-l2.txt 2>&1` y comparas `/tmp/mi-corrida-l2.txt` contra `programas/02-pods-deployments/correr.salida.txt` (no redirijas a ese archivo: es la referencia) en lo que no cambia entre corridas: tres nodos `Ready` en `v1.37.0`; `0` imágenes del `revisor` en el nodo antes de cargarla; los tres Pods en `ImagePullBackOff` y el evento `pull access denied` con `docker.io/library/curso-docker-revisor:1.6.0`; los tres renglones `not yet present on node … loading...`, uno por nodo, incluido el de control; `deployment.apps/revisor 3/3`; `revisor 1.6.0 escuchando en :8080 (1 servicio(s))`; `sano` y `1.6.0`; `executable file not found in $PATH`; el `securityContext` en JSON; `CreateContainerConfigError` con `breaks non-root policy`; dos revisiones en `rollout history` y el ReplicaSet viejo en `0 0 0`; y al final `sin diferencias con el archivo`. Los sufijos de los nombres, las IP, en qué nodo cae cada Pod, las edades, el orden de los renglones de `kind load` y las veces que se repite cada renglón de `rollout status` cambian en cada corrida: se observan, no se comparan.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l2`.

## Resumen

Responde sin mirar la lección:

1. ¿Por qué un nodo de kind no ve las imágenes de tu Docker, y qué hace `kind load docker-image`?
2. ¿Qué diferencia hay entre `ErrImagePull` e `ImagePullBackOff`? ¿Cuánto llega a esperar el `kubelet` entre intentos?
3. ¿Qué tres piezas tiene la `spec` de un Deployment y qué pasa si el selector no coincide con las etiquetas de la plantilla?
4. ¿Quién es dueño de quién en la cadena Deployment, ReplicaSet y Pod, y en qué campo se lee?
5. ¿Qué hace un ReplicaSet con un Pod al que le quitas la etiqueta de su selector?
6. ¿Cuándo se dispara un *rollout*? ¿Por qué `rollout restart` dispara uno si no cambiaste nada?
7. Con tres réplicas y los valores por omisión, ¿cuántos Pods puede haber durante un *rollout* y cuántos pueden faltar?
8. ¿Qué evita `runAsNonRoot: true` que no evite ya `runAsUser: 65532`?
9. ¿Por qué el `revisor` necesita un `emptyDir` en `/datos`?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/), sección «Loading an Image Into Your Cluster»: `kind load docker-image`, la opción `--name` para clústeres con nombre, `crictl images` dentro del nodo y la advertencia sobre `:latest` y la política de descarga.
- [Kubernetes, «Images»](https://kubernetes.io/docs/concepts/containers/images/): las políticas `IfNotPresent`, `Always` y `Never`; la política por omisión según la etiqueta; Docker Hub como registro por omisión (`docker.io/library/…`); y `ImagePullBackOff`, con su espera creciente hasta 300 segundos.
- [Kubernetes, «Deployments»](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): cuándo se dispara un *rollout*; `maxSurge` y `maxUnavailable` (25 %, con su redondeo); `revisionHistoryLimit` (10); `progressDeadlineSeconds` (600) y `ProgressDeadlineExceeded`; la etiqueta `pod-template-hash`; la advertencia de no administrar los ReplicaSets de un Deployment y la de los selectores que se traslapan.
- [Kubernetes, «ReplicaSet»](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/): su propósito; la adopción de Pods sin dueño que coinciden con su selector; la recomendación de usar Deployments; y cómo sacar Pods de un ReplicaSet cambiando sus etiquetas.
- [Kubernetes, «Pods»](https://kubernetes.io/docs/concepts/workloads/pods/): por qué rara vez se crean Pods individuales y hasta cuándo se queda un Pod en su nodo.
- [Kubernetes, «Pod Lifecycle»](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): `restartPolicy` vale `Always` por omisión; la fase `Pending` incluye la descarga de imágenes; un Pod nunca se reprograma a otro nodo.
- [Kubernetes, «Restrict a Container's Syscalls with seccomp»](https://kubernetes.io/docs/tutorials/security/seccomp/): sin `seccompDefault`, el perfil por omisión es `Unconfined`.
- [Kubernetes, «Owners and Dependents»](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/): el campo `ownerReferences`.
- [Kubernetes, «Labels and Selectors»](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/): qué es una etiqueta, que no es única, los selectores de igualdad y de conjuntos, y la ausencia de un operador «o».
- [Kubernetes, «Volumes»](https://kubernetes.io/docs/concepts/storage/volumes/), sección `emptyDir`: cuándo se crea, cuándo se borra y `sizeLimit`.
- [Kubernetes, «Configure a Security Context for a Pod or Container»](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): cada campo del `securityContext` y qué controla.
- [Kubernetes, «Pod Security Standards»](https://kubernetes.io/docs/concepts/security/pod-security-standards/): el nivel `restricted` y sus reglas de no-`root`, escalada de privilegios, capacidades y `seccomp`.

---

**Siguiente:** [Lección 3 — Services y DNS](03-services-dns.md)
