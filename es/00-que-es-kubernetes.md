# Lección 0 — Qué es Kubernetes y qué NO es kind

Viernes, 11:40 de la noche. El `revisor` lleva tres semanas corriendo en un solo servidor, levantado con un `docker run --restart always` que alguien tecleó una tarde y nunca escribió en ningún lado. A esa hora el servidor se apaga: una fuente de poder que se rinde. El contenedor muere con él, y con él muere el *daemon* de Docker, el único que sabía reiniciarlo. El lunes a las nueve, el equipo de operación necesita el reporte de estados para la junta semanal y la página está en blanco. Alguien tiene que despertar, conseguir otra máquina, acordarse de las variables de entorno exactas, del puerto, del volumen, de la versión de la imagen… y todo eso estaba en el historial de la terminal del servidor que ya no enciende.

El problema no fue el contenedor. Fue que **nadie, salvo una persona dormida, sabía cómo debía estar el servicio**. Esta lección trata de la herramienta que existe para que eso lo sepa el sistema, y no tú a las tres de la mañana.

**Tiempo:** 90 min

**Qué construyes:** nada todavía. Es una lección de lectura: aquí se arma el mapa mental con el que el resto del curso se vuelve predecible

**Qué aprendes:** qué problema resuelve Kubernetes que Docker solo no resuelve; el plano de control y los nodos, pieza por pieza; declarar el estado deseado y dejar que el clúster lo alcance (el bucle de control); el mapa de Docker a Kubernetes; qué es kind, qué prueba un clúster de kind y qué no prueba; y qué defiende un clúster local y qué no

**De dónde vienes.** Del [curso de Docker](https://www.habil.mx/es/cursos/docker/) de esta casa, o de una práctica equivalente: sabes construir una imagen, correrla con `docker run`, darle variables de entorno, un puerto y un volumen, y levantar varias juntas con Compose. Traes, además, el `revisor` ya empaquetado: un servidor en Go que escucha en el puerto 8080, responde `GET /salud` y `GET /api/estados`, y se configura por variables de entorno. Lo que no traes es el mapa de **cómo piensa un clúster**, que es distinto del de Docker y que explica por qué los comandos de las lecciones siguientes son como son.

**Qué no hace esta lección.** No instala nada (eso es la [Lección 1](01-instalacion-primer-cluster.md)) y no despliega el `revisor` (eso empieza en la [Lección 2](02-pods-deployments.md)). Trae un recorrido real por un clúster de kind, con sus salidas, para que veas con tus ojos lo que la lección afirma. No hace falta que entiendas cada renglón de cada salida todavía: lo que importa es **qué cuentan**. Si quieres repetir el recorrido, hazlo después de la Lección 1, cuando ya tengas `kubectl` y `kind`.

**Sobre las corridas.** Las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1 y la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, sobre Docker Engine 29.2.1. La máquina fue una Mac con procesador ARM, con Docker dentro de una máquina virtual Linux (Colima), **no** Linux Mint, que es el sistema de referencia del curso. Lo que cambia en tu Mint: la columna `KERNEL-VERSION` dirá tu núcleo y `amd64` en lugar de `arm64`, las direcciones IP y los puertos serán otros, y los nombres de los Pods llevarán otros sufijos al azar. Todo lo demás debe coincidir. Hubo una diferencia más, y es instructiva: en esa máquina un clúster de **tres** nodos no arrancó, porque el límite de vigilancia de archivos del sistema estaba en 128 y se agotó (la sección 0.6.3 lo cuenta). Por eso el recorrido usa **un solo nodo**; el clúster de tres nodos del curso llega en la Lección 1, que primero ajusta ese límite. El recorrido completo está en [`programas/00-que-es-kubernetes/`](../programas/00-que-es-kubernetes): `recorrido.sh` lo corre de principio a fin en unos dos minutos y `recorrido.salida.txt` es su salida; `ejercicio3.sh` y `ejercicio3.salida.txt` hacen lo mismo con el Ejercicio 3.

## Al terminar vas a poder

- Explicar con un ejemplo por qué `docker run --restart always` no basta para mantener vivo un servicio cuando la máquina que lo corre se cae.
- Nombrar las piezas del plano de control (`kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`) y las de cada nodo (`kubelet`, `kube-proxy`, el *runtime* de contenedores), y decir qué hace cada una en una frase.
- Describir paso a paso qué ocurre en el clúster entre un `kubectl apply` y un contenedor corriendo.
- Distinguir una orden (`kubectl scale`) de una declaración (`kubectl apply -f`) y predecir qué pasa cuando se mezclan.
- Traducir cinco conceptos de Docker a su equivalente en Kubernetes, y nombrar uno que no tiene equivalente.
- Decir qué es kind, qué demuestra un clúster de kind y qué no demuestra.
- Leer el error `The connection to the server localhost:8080 was refused` y decir qué significa.

## El porqué antes del cómo

Con Docker aprendiste a responder la pregunta «¿cómo corro este programa?». La respuesta es una imagen y un `docker run`. Es una gran respuesta, y Kubernetes no la cambia: las imágenes que construiste en el curso de Docker son exactamente las que va a correr el clúster.

Pero hay otra pregunta, que aparece en cuanto un servicio importa: **«¿quién se encarga de que siga corriendo?»**. Con Docker, la respuesta es el *daemon* de esa máquina, y solo mientras esa máquina viva. La documentación de Docker lo deja claro: las políticas de reinicio, como `always` o `unless-stopped`, se aplican a los contenedores de ese *daemon* ([Docker, «Start containers automatically»](https://docs.docker.com/engine/containers/start-containers-automatically/)). Si la máquina desaparece, no queda nadie que recuerde que ahí corría algo.

Kubernetes responde la segunda pregunta. Le dices **cómo debe estar** tu servicio —«tres copias del `revisor`, con esta imagen, con esta configuración»— y él se encarga de que esté así, en las máquinas que tenga, aunque alguna se caiga. Eso cambia tu trabajo: dejas de dar órdenes («arranca esto», «reinicia aquello») y pasas a escribir **descripciones** del estado que quieres, que el clúster persigue sin descanso.

Hay una segunda razón para empezar por la lectura y no por la instalación. Kubernetes tiene muchas piezas con nombres raros, y los mensajes que te va a dar en las lecciones siguientes (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) mencionan esas piezas. Si no sabes quién es el *scheduler*, un Pod `Pending` es un misterio; si lo sabes, es una pista. Y una tercera: en este curso vas a usar **kind**, un clúster que vive dentro de Docker en tu máquina. Es una herramienta excelente para aprender, pero si no sabes qué es, vas a creer que tu clúster local demuestra cosas que no demuestra.

La lección tiene ocho partes, en este orden:

1. **El problema que resuelve Kubernetes** (0.1).
2. **Declarar en vez de ordenar: el bucle de control** (0.2), con un clúster real que repara lo que rompes.
3. **Las piezas: el plano de control y los nodos** (0.3), vistas por dentro.
4. **Una orden contra una declaración** (0.4): qué pasa cuando las mezclas.
5. **El mapa de Docker a Kubernetes** (0.5).
6. **Qué es kind y qué NO es** (0.6): lo que tu clúster local demuestra y lo que no.
7. **Las versiones** (0.7): cuáles usa el curso y por qué.
8. **Lo que viene en el resto del curso** (0.8).

Con ese destino en mente, esto es lo que verás en la sección 0.2. Se borró uno de tres Pods y, un segundo después, el clúster ya había creado otro en su lugar sin que nadie se lo pidiera. Esa es la idea central de toda la lección:

```text
$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

## Los conceptos

### 0.1 El problema que resuelve Kubernetes

#### 0.1.1 De «correr un contenedor» a «mantener un servicio»

Un contenedor es un proceso con su propio sistema de archivos y su propia red, en **una** máquina. Un servicio que la gente usa necesita más que eso:

- Que haya **varias copias**, para que la caída de una no deje a nadie sin servicio.
- Que esas copias estén en **máquinas distintas**, para que la caída de una máquina tampoco.
- Que, si una copia muere, **alguien la reponga** sin esperar a una persona.
- Que los demás programas lo **encuentren por nombre**, aunque sus copias cambien de máquina y de dirección.
- Que su configuración se pueda **cambiar sin reconstruir** la imagen.
- Que una versión nueva **reemplace a la vieja sin cortar** el servicio.

Con Docker y Compose puedes resolver algunas de estas cosas en una sola máquina. Ninguna en varias. Kubernetes es la herramienta que resuelve las seis, en un grupo de máquinas al que llama **clúster**.

La definición oficial es esta: Kubernetes es «una plataforma portable, extensible y de código abierto para administrar cargas de trabajo y servicios en contenedores, que facilita tanto la configuración declarativa como la automatización» ([kubernetes.io, «Overview»](https://kubernetes.io/docs/concepts/overview/)). Fíjate en la palabra *declarativa*: es la que importa, y la sección 0.2 la explica.

Dos datos para que no te tomen por sorpresa. El nombre viene del griego y significa «timonel» o «piloto», y la abreviatura **K8s** sale de contar las ocho letras que hay entre la «K» y la «s». Google liberó el proyecto como código abierto en 2014 (las tres cosas, en la misma página oficial).

#### 0.1.2 Lo que Kubernetes no es

La misma página oficial dedica una sección a lo que Kubernetes **no** hace, y conviene leerla antes de empezar porque evita expectativas falsas. Entre otras cosas, Kubernetes no construye tu aplicación ni despliega código fuente (la imagen la traes tú, como en el curso de Docker), no trae bases de datos ni colas de mensajes incluidas, y no impone una solución de bitácoras ni de monitoreo. Y la frase que más vale la pena: Kubernetes «no es un mero sistema de orquestación». Orquestar, en sentido técnico, es ejecutar un flujo definido: «primero A, luego B, luego C». Kubernetes, en cambio, es «un conjunto de procesos de control independientes y combinables que llevan continuamente el estado actual hacia el estado deseado».

Esa última frase es el resumen de esta lección. El resto la desarma.

### 0.2 Declarar en vez de ordenar: el bucle de control

#### 0.2.1 El termostato

La documentación de Kubernetes explica su idea central con un aparato que conoces: un termostato ([kubernetes.io, «Controllers»](https://kubernetes.io/docs/concepts/architecture/controller/)). Cuando fijas la temperatura en 22 grados, le estás diciendo al termostato tu **estado deseado**. La temperatura que hay en el cuarto es el **estado actual**. El termostato prende o apaga el clima para acercar el actual al deseado. No le dices «prende el clima diez minutos»; le dices «quiero 22», y él decide qué hacer, una y otra vez, mientras esté encendido.

Eso es un **bucle de control**: un ciclo que no termina, que observa, compara y corrige. En Kubernetes, a cada uno de esos bucles se le llama **controlador**: «los controladores son bucles de control que vigilan el estado de tu clúster y luego hacen o piden cambios donde hace falta. Cada controlador intenta llevar el estado actual del clúster más cerca del estado deseado».

La consecuencia práctica es la que viste en la escena inicial, al revés. Con Docker, el conocimiento de cómo debía estar el `revisor` vivía en la memoria de una persona. Con Kubernetes vive **en el clúster**, escrito, y un programa lo compara con la realidad todo el tiempo.

#### 0.2.2 Un estado deseado, escrito en un archivo

En Kubernetes, el estado deseado se escribe en un **manifiesto**: un archivo YAML que describe un objeto. Este es el primer manifiesto del curso. Pide tres copias de un contenedor:

```yaml
# fig00_02.deployment.yaml — un estado deseado: «quiero tres copias de este contenedor».
# La imagen es `pause`, un contenedor que no hace nada más que esperar; viene ya
# dentro del nodo de kind, así que no se descarga nada. El `revisor` llega en la
# Lección 2; aquí solo importa ver qué hace el clúster con lo que declaras.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: espera
spec:
  replicas: 3
  selector:
    matchLabels:
      app: espera
  template:
    metadata:
      labels:
        app: espera
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65535
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: espera
        image: registry.k8s.io/pause:3.10
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

No hace falta entenderlo entero; la Lección 2 lo desarma campo por campo. Por ahora, tres cosas. `kind: Deployment` dice qué tipo de objeto es: un **Deployment** es la forma normal de pedir «mantén corriendo N copias de este contenedor». `replicas: 3` es el estado deseado: tres copias. Y `template` es el molde de cada copia: qué imagen usa y con qué etiqueta (`app: espera`) se le reconoce. Los dos bloques `securityContext` dicen que el contenedor corre sin ser `root`, sin poder ganar privilegios y con su sistema de archivos de solo lectura; están aquí porque en este curso todo manifiesto los lleva desde el primero, y la Lección 2 explica cada uno.

La imagen, `registry.k8s.io/pause`, es un contenedor diminuto que no hace nada más que esperar. Se eligió porque ya viene dentro del nodo de kind (el propio Kubernetes la usa por dentro), así que el ejemplo no depende de descargar nada de internet.

#### 0.2.3 Lo que hace el clúster con tu declaración

El manifiesto se entrega al clúster con `kubectl apply -f`. Esto es lo que respondió el clúster del recorrido:

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera created

$ kubectl rollout status deployment/espera --timeout=90s
Waiting for deployment "espera" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 2 of 3 updated replicas are available...
deployment "espera" successfully rolled out
```

Lee la primera respuesta con cuidado: `deployment.apps/espera created`. No dice «tres contenedores arrancados». Dice que se **guardó** el objeto Deployment. En ese instante no había ningún contenedor corriendo; había una descripción. El segundo comando, `rollout status`, se queda esperando y va contando: cero de tres disponibles, una, dos, y al final «terminado». Entre el primer renglón y el último, el clúster estuvo trabajando para que la realidad alcanzara lo que declaraste.

Ahora mira lo que quedó:

```text
$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/3     3            3           1s

$ kubectl get replicaset -l app=espera
NAME                DESIRED   CURRENT   READY   AGE
espera-68b9d575f7   3         3         3       1s

$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-9gbtr   1/1     Running   0          1s
espera-68b9d575f7-cprg7   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          1s
```

Pediste **un** objeto y hay **tres tipos** de objeto. Es una cadena, y conviene verla así desde el primer día:

```text
Deployment espera            «quiero 3 copias de este molde»
   └── ReplicaSet espera-68b9d575f7       «hay que tener 3 Pods con este molde exacto»
         ├── Pod espera-68b9d575f7-9gbtr
         ├── Pod espera-68b9d575f7-cprg7
         └── Pod espera-68b9d575f7-gsrlf
```

El **Deployment** es lo que tú escribes. El **ReplicaSet** lo crea el Deployment, y su único trabajo es contar: que haya tantos Pods como dice `replicas`. El sufijo `68b9d575f7` identifica el molde; cuando cambies la imagen, en la Lección 2, aparecerá otro ReplicaSet con otro sufijo, y así es como Kubernetes cambia de versión sin cortar. Y el **Pod** es la unidad que de verdad corre: la documentación lo define como «la unidad desplegable más pequeña» de Kubernetes, «un grupo de uno o más contenedores, con almacenamiento y red compartidos» ([kubernetes.io, «Pods»](https://kubernetes.io/docs/concepts/workloads/pods/)). Casi siempre, un Pod tiene un solo contenedor; en este curso, siempre.

Fíjate también en los nombres de los Pods: el sufijo final (`9gbtr`, `cprg7`…) es aleatorio. En tu corrida serán otros. Por eso, en este curso, nunca se escribe a mano el nombre de un Pod: se le busca por su etiqueta, con `-l app=espera`.

#### 0.2.4 Romper algo a propósito

Ahora la prueba del termostato. Se borró uno de los tres Pods, a mano, como si se hubiera muerto:

```text
$ kubectl delete pod espera-68b9d575f7-9gbtr
pod "espera-68b9d575f7-9gbtr" deleted from default namespace

$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

Siguen siendo tres. El `9gbtr` ya no está, y hay uno nuevo, `fjx8v`, con un segundo de edad. Nadie lo pidió. El ReplicaSet vio que el estado actual (dos Pods) no coincidía con el deseado (tres) y creó uno. El clúster deja constancia de lo que hace en sus **eventos**, y ahí se ve la historia completa:

```text
$ kubectl get events --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp
LAST SEEN   TYPE     REASON             OBJECT                         MESSAGE
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-9gbtr
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-gsrlf
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-cprg7
1s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-fjx8v
```

Cuatro creaciones: las tres del principio y la reposición. Los eventos son la primera cosa que se mira cuando algo no sale como esperabas, y el curso los usa en cada lección.

Esto tiene una consecuencia que cambia la forma de trabajar: **en Kubernetes, borrar un Pod no apaga nada**. Si quieres que haya menos copias, cambias el estado deseado. Si quieres que no haya ninguna, borras el Deployment. Borrar el Pod solo provoca que nazca otro.

#### 0.2.5 Y cuando lo que se cae es una máquina

La escena del principio no era un contenedor que muere: era una máquina que se apaga. Kubernetes también lo cubre, pero conviene saber **cuánto tarda**, porque no es instantáneo. Cuando un nodo deja de responder, el clúster lo marca como no disponible, y los Pods que corrían en él se quedan asignados ahí un tiempo antes de que se repongan en otro nodo. Ese tiempo viene escrito en cada Pod. Se leyó del Pod del recorrido:

```text
[{"effect":"NoExecute","key":"node.kubernetes.io/not-ready","operator":"Exists","tolerationSeconds":300},{"effect":"NoExecute","key":"node.kubernetes.io/unreachable","operator":"Exists","tolerationSeconds":300}]
```

Son 300 segundos. La documentación lo confirma: Kubernetes agrega esas dos tolerancias automáticamente, y significan que los Pods «permanecen asignados a los nodos durante 5 minutos después de que se detecta uno de esos problemas» ([kubernetes.io, «Taints and Tolerations»](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)). La espera existe para no mover todo por un corte de red de diez segundos.

¿Entonces el servicio está caído cinco minutos? No, si hiciste lo que este curso enseña: **tener varias réplicas repartidas en nodos distintos**. Mientras las del nodo caído esperan su reposición, las de los otros nodos siguen atendiendo. Ojo con una suposición cómoda: el Deployment cuida **cuántas** réplicas hay, no **dónde** quedan. Por omisión, el `kube-scheduler` *procura* repartirlas entre nodos, pero si no puede las amontona en uno (la documentación dice que actúa como si tuviera la regla `whenUnsatisfiable: ScheduleAnyway`, «programa de todos modos»). Para **exigir** el reparto, el manifiesto tiene que declararlo con `topologySpreadConstraints` o con anti-afinidad ([kubernetes.io, «Pod Topology Spread Constraints»](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)); el manifiesto de esta lección no lo hace, y el curso vuelve a esto cuando el `revisor` tenga que sobrevivir a un nodo apagado. Esa es una de las metas del curso: detener un nodo de trabajo y que el `revisor` siga respondiendo.

### 0.3 Las piezas: el plano de control y los nodos

#### 0.3.1 Dos tipos de máquina

Un clúster tiene dos tipos de máquina, que Kubernetes llama **nodos**:

- El **plano de control** (*control plane*): las máquinas donde vive el «cerebro». Guardan el estado deseado, deciden dónde corre cada cosa y ejecutan los controladores.
- Los **nodos de trabajo** (*worker nodes*): las máquinas donde corren tus contenedores.

En un clúster de producción, el plano de control suele estar en tres máquinas dedicadas, para que la caída de una no lo detenga. En el clúster de esta lección hay **un solo nodo** que hace las dos cosas; en el de la Lección 1 habrá uno de control y dos de trabajo.

#### 0.3.2 Las piezas, una por una

Las definiciones salen de la página oficial de componentes ([kubernetes.io, «Kubernetes Components»](https://kubernetes.io/docs/concepts/overview/components/)); la columna de la derecha es la traducción a lo que ves en el curso.

| Pieza | Dónde vive | Qué hace, según la documentación | Lo que significa para ti |
|---|---|---|---|
| `kube-apiserver` | plano de control | «el servidor que expone la API HTTP de Kubernetes» | es la única puerta: `kubectl` le habla a él, y las demás piezas también |
| `etcd` | plano de control | «almacén de clave y valor, consistente y de alta disponibilidad, para todos los datos del servidor de la API» | aquí queda escrito tu manifiesto; si se pierde `etcd`, se pierde el estado deseado |
| `kube-scheduler` | plano de control | «busca Pods que todavía no están asignados a un nodo y asigna cada uno a un nodo adecuado» | decide **dónde** corre cada Pod; cuando no encuentra lugar, el Pod se queda `Pending` (Lección 5) |
| `kube-controller-manager` | plano de control | «ejecuta controladores para implementar el comportamiento de la API de Kubernetes» | aquí viven los termostatos: el de Deployments, el de ReplicaSets, el de nodos… |
| `cloud-controller-manager` | plano de control, opcional | «se integra con los proveedores de nube subyacentes» | en kind no existe; por eso un `LoadBalancer` necesita ayuda (Lección 6) |
| `kubelet` | cada nodo | «se asegura de que los Pods estén corriendo, incluidos sus contenedores» | el agente de cada máquina: recibe Pods y los hace realidad |
| `kube-proxy` | cada nodo, opcional | «mantiene reglas de red en los nodos para implementar los Services» | dirige el tráfico que llega a la dirección y el puerto de un Service hacia los Pods que lo atienden en ese momento; el nombre del Service lo resuelve el DNS del clúster, no él (Lección 3) |
| *runtime* de contenedores | cada nodo | «el software responsable de correr contenedores» | en kind es `containerd`, no Docker |

#### 0.3.3 Verlas en el clúster

Todo eso no es teoría: se puede ver. Los componentes del plano de control corren como Pods en un espacio de nombres reservado, `kube-system`:

```text
$ kubectl get pods -n kube-system
NAME                                                 READY   STATUS    RESTARTS   AGE
coredns-559f6c778d-gg7jc                             1/1     Running   0          15s
coredns-559f6c778d-wcmct                             1/1     Running   0          15s
etcd-curso-k8s-l0-control-plane                      1/1     Running   0          23s
kindnet-2cfgd                                        1/1     Running   0          15s
kube-apiserver-curso-k8s-l0-control-plane            1/1     Running   0          22s
kube-controller-manager-curso-k8s-l0-control-plane   1/1     Running   0          22s
kube-proxy-cnp6z                                     1/1     Running   0          15s
kube-scheduler-curso-k8s-l0-control-plane            1/1     Running   0          22s
```

Ahí están cuatro de las piezas de la tabla: `etcd`, `kube-apiserver`, `kube-controller-manager` y `kube-scheduler`, cada una con el nombre del nodo pegado al final. Está `kube-proxy`. Y hay tres que la tabla no menciona: `coredns` (dos copias), que es el DNS interno del clúster y el que hace que un Pod encuentre a otro por nombre (Lección 3); y `kindnet`, la red entre Pods que kind instala por omisión. Kubernetes no trae una red propia: la pone un complemento que se llama CNI, y cada instalación elige el suyo. La [guía de configuración de kind](https://kind.sigs.k8s.io/docs/user/configuration/) llama al suyo `kindnetd` y explica cómo cambiarlo; la Lección 7 vuelve a esto, porque de la red depende que una `NetworkPolicy` se aplique o no.

Falta una pieza en la lista: el `kubelet`. No es un Pod. Es un programa normal del nodo, y se ve mirando los procesos **dentro** del nodo:

```text
$ docker exec curso-k8s-l0-control-plane sh -c "ps -eo comm | grep -E '^(kubelet|containerd|kube-|etcd)' | sort"
containerd
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
etcd
kube-apiserver
kube-controller
kube-proxy
kube-scheduler
kubelet
```

`kubelet` y `containerd` son procesos del nodo. Los demás (`etcd`, `kube-apiserver`, etc.) son contenedores que `containerd` arrancó, y cada `containerd-shim` es un pequeño proceso auxiliar que vigila contenedores. En esta corrida hay nueve, uno por Pod, porque el *shim* de `runc` agrupa en un mismo proceso los contenedores de un mismo Pod; pero esa relación la decide el *runtime*, así que no cuentes Pods contando *shims* ([containerd, «Runtime v2»](https://github.com/containerd/containerd/blob/main/docs/runtime-v2.md)). (El nombre `kube-controller` aparece cortado porque `ps` muestra solo los primeros quince caracteres del nombre del programa.)

#### 0.3.4 El huevo y la gallina

Aquí hay un acertijo. Casi todos los Pods nacen igual: un controlador (el de ReplicaSets, por ejemplo) los escribe en el `kube-apiserver`, el `kube-scheduler` encuentra los que todavía no tienen nodo y elige uno para cada Pod, y el `kubelet` de ese nodo los arranca. El `kube-scheduler` no crea Pods: los asigna ([kubernetes.io, «Kubernetes Scheduler»](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)). Pero el `kube-apiserver` es, él mismo, un Pod. ¿Quién arrancó el Pod del servidor de la API antes de que existiera el servidor de la API?

La respuesta está en una carpeta del nodo:

```text
$ docker exec curso-k8s-l0-control-plane ls /etc/kubernetes/manifests
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

Son cuatro manifiestos, uno por pieza del plano de control. El `kubelet` lee esa carpeta directamente, sin preguntarle a nadie, y arranca lo que encuentre. A estos Pods se les llama **Pods estáticos**: los administra el `kubelet` a partir de archivos, no el servidor de la API ([kubernetes.io, «Create static Pods»](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)). Lo que ves con `kubectl get pods -n kube-system` es un reflejo de ellos que el `kubelet` publica en la API para que puedas verlos. Por eso sus nombres terminan con el nombre del nodo, y por eso no tienen el sufijo aleatorio de los Pods que crea un ReplicaSet.

No vas a tocar esa carpeta en este curso. Pero ahora sabes por qué el plano de control «se levanta solo», y qué preguntar si algún día no lo hace.

#### 0.3.5 El viaje completo de un `kubectl apply`

Con las piezas a la vista, este es el recorrido de lo que pasó en 0.2.3, de punta a punta:

1. `kubectl` lee `fig00_02.deployment.yaml` y lo envía al **`kube-apiserver`**, por HTTPS.
2. El `kube-apiserver` revisa quién eres y si tienes permiso, valida el objeto y lo guarda en **`etcd`**. Responde `deployment.apps/espera created`. Hasta aquí no hay ni un contenedor.
3. El controlador de Deployments, dentro del **`kube-controller-manager`**, ve un Deployment nuevo sin ReplicaSet y crea uno.
4. El controlador de ReplicaSets ve un ReplicaSet que pide tres Pods y no tiene ninguno, y crea tres objetos Pod, todavía sin nodo asignado.
5. El **`kube-scheduler`** ve tres Pods sin nodo, elige uno para cada uno y lo anota en el Pod.
6. El **`kubelet`** del nodo elegido ve que tiene Pods asignados, le pide a **`containerd`** que arranque los contenedores, y reporta su estado al `kube-apiserver`.
7. `kubectl rollout status`, que estaba preguntando, ve los tres Pods disponibles y escribe `successfully rolled out`.

Observa que ninguna pieza le da órdenes a otra. Cada una vigila los objetos que le interesan y actúa cuando el estado actual no coincide con el deseado. Si una pieza se cae un rato, al volver encuentra lo pendiente y lo hace. Por eso el diseño aguanta fallas: no hay una cadena de llamadas que se rompa a la mitad.

### 0.4 Una orden contra una declaración

#### 0.4.1 Las dos maneras de hablarle al clúster

`kubectl` te permite trabajar de dos maneras, y la documentación las distingue con cuidado ([kubernetes.io, «Kubernetes Object Management»](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/)):

- **Órdenes** (*imperative commands*): le dices al clúster qué hacer, con un verbo. `kubectl create deployment`, `kubectl scale`, `kubectl delete`. Son rápidas, y la documentación las recomienda «para empezar o para una tarea de una sola vez». Su problema: no dejan registro. Lo único que sabe cómo está el objeto es el propio clúster.
- **Declaraciones** (*declarative object configuration*): escribes un archivo con el estado deseado y lo entregas con `kubectl apply -f`. El archivo se guarda en Git, se revisa antes de aplicarse, y si el clúster se pierde, se vuelve a aplicar y todo queda igual.

Este curso usa declaraciones para todo lo que importa. Las órdenes aparecen solo para mirar (`get`, `describe`, `logs`) y para experimentos que se tiran.

#### 0.4.2 Qué pasa cuando se mezclan

La documentación tiene una advertencia breve y seria: «un objeto de Kubernetes debe administrarse con una sola técnica; mezclar técnicas en el mismo objeto produce un comportamiento indefinido». En el recorrido se mezclaron a propósito, para que veas uno de esos comportamientos. Primero, una orden: subir de tres a cinco copias.

```text
$ kubectl scale deployment espera --replicas=5
deployment.apps/espera scaled

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/5     5            3           3s
```

El clúster obedeció: ahora quiere cinco (`3/5` significa «tres listas de cinco deseadas»; las otras dos están arrancando). Pero el archivo `fig00_02.deployment.yaml` sigue diciendo `replicas: 3`. Ahora el clúster y el archivo **no coinciden**, y nada te avisa. Para verlo existe `kubectl diff`, que compara el archivo con lo que hay en el clúster sin cambiar nada:

```text
$ kubectl diff -f fig00_02.deployment.yaml
@@ -6,14 +6,14 @@
     kubectl.kubernetes.io/last-applied-configuration: |
       {"apiVersion":"apps/v1","kind":"Deployment","metadata":{"annotations":{},"name":"espera","namespace":"default"},"spec":{"replicas":3,"selector":{"matchLabels":{"app":"espera"}},"template":{"metadata":{"labels":{"app":"espera"}},"spec":{"containers":[{"image":"registry.k8s.io/pause:3.10","name":"espera","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}}],"securityContext":{"runAsNonRoot":true,"runAsUser":65535,"seccompProfile":{"type":"RuntimeDefault"}}}}}}
   creationTimestamp: "2026-10-21T07:52:14Z"
-  generation: 2
+  generation: 3
   name: espera
   namespace: default
   resourceVersion: "587"
   uid: 0e26d2f6-3277-4f4f-9dc0-592b883974f8
 spec:
   progressDeadlineSeconds: 600
-  replicas: 5
+  replicas: 3
   revisionHistoryLimit: 10
   selector:
     matchLabels:
```

(Se omitieron los tres primeros renglones de la salida, que solo nombran dos archivos temporales con rutas que cambian en cada corrida; están completos en `recorrido.salida.txt`.)

Es un *diff* como el de Git: el renglón con `-` es lo que hay en el clúster, el renglón con `+` es lo que quedaría si aplicaras el archivo. El dato que importa es `-  replicas: 5` / `+  replicas: 3`: si aplicas el archivo, **se pierden las dos copias** que agregó la orden. El renglón de `generation` es un contador que sube cada vez que cambia el estado deseado; y la anotación larga, `last-applied-configuration`, es la copia que `kubectl apply` guarda del último archivo que aplicaste, para saber qué campos son «suyos». (Un detalle útil: `kubectl diff` sale con código 1 cuando encuentra diferencias, según su propia ayuda; no es un fallo, es la respuesta.)

Se aplicó el archivo:

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera configured

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/3     3            3           4s
```

De vuelta a tres. Ganó el archivo, porque `replicas` es un campo que el archivo declara. La lección no es «las órdenes son malas»; es que **si tienes un archivo, el archivo es la verdad**, y una orden que lo contradice dura hasta el próximo `apply`. Imagina que esa orden la dio otra persona, de noche, para aguantar un pico de carga, y que por la mañana tú aplicas el archivo sin mirar. Por eso, en este curso, antes de aplicar sobre algo que ya existe se mira `kubectl diff`.

### 0.5 El mapa de Docker a Kubernetes

Casi todo lo que sabes de Docker tiene un equivalente en Kubernetes. No es idéntico, pero el mapa te ahorra la mitad del curso:

| En Docker | En Kubernetes | Dónde se ve en el curso |
|---|---|---|
| una imagen | la **misma** imagen | Lección 2 (`kind load docker-image`) |
| `docker run` de un contenedor | un **Pod** (y casi nunca solo: dentro de un Deployment) | Lección 2 |
| `--restart always` | el **Deployment** y su ReplicaSet, que reponen los Pods que faltan en un nodo donde quepan | Lección 2 |
| `docker compose up --scale revisor=3` | `replicas: 3` en el Deployment | Lección 2 |
| `-p 8080:8080` | un **Service**, y `kubectl port-forward` para probar desde tu máquina | Lección 3 |
| el nombre del servicio en la red de Compose | el **DNS del clúster**: `revisor.<espacio>.svc` | Lección 3 |
| `-e` y `--env-file` | **ConfigMap** y **Secret** | Lección 4 |
| `HEALTHCHECK` en el Dockerfile | **sondas** de arranque, de disponibilidad y de vida | Lección 5 |
| `--memory` y `--cpus` | `resources.requests` y `resources.limits` | Lección 5 |
| `--user`, `--read-only`, `--cap-drop ALL` | `securityContext` | Lección 2 |
| un volumen con nombre | un **PersistentVolumeClaim** | Lección 8 |
| un contenedor que corre y termina | un **Job**; programado, un **CronJob** | Lección 8 |
| el archivo `compose.yaml` | manifiestos YAML, juntos con **Kustomize** | Lecciones 4 y 10 |

Y hay cosas que **no tienen equivalente** en Docker, porque solo tienen sentido cuando hay varias máquinas y varias personas: el *scheduler* que elige máquina; los **Namespaces**, que separan equipos o proyectos dentro del mismo clúster; los permisos por cuenta de servicio (**RBAC**); las políticas de red entre Pods; y el escalado automático con la carga. Esas son las Lecciones 7 y 9.

Una pregunta que siempre sale: si los nodos no usan Docker, ¿sirven las imágenes que construiste con Docker? Sí. Kubernetes dejó de hablar directamente con Docker Engine en la versión 1.24 ([kubernetes.io, contexto histórico de dockershim](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/)), pero eso no tocó las imágenes. El blog oficial lo explica así: «la imagen que produce Docker no es en realidad una imagen específica de Docker: es una imagen OCI», y `containerd` sabe descargarla y correrla ([kubernetes.io, «Don't Panic: Kubernetes and Docker»](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/)). El recorrido lo confirma: la columna `CONTAINER-RUNTIME` del nodo dice `containerd://2.3.4`.

### 0.6 Qué es kind y qué NO es

#### 0.6.1 Kubernetes dentro de Docker

**kind** son las siglas de *Kubernetes IN Docker*. Su página lo describe en una frase: «una herramienta para correr clústeres locales de Kubernetes usando "nodos" que son contenedores de Docker», y agrega que «fue diseñada principalmente para probar el propio Kubernetes, pero puede usarse para desarrollo local o integración continua» ([kind.sigs.k8s.io](https://kind.sigs.k8s.io/)).

Lo de «nodos que son contenedores» se ve sin trucos. Desde Kubernetes, el clúster tiene un nodo:

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l0-control-plane   Ready    control-plane   25s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

Y desde Docker, ese mismo nodo es un contenedor:

```text
$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l0 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l0-control-plane   kindest/node:v1.37.0   127.0.0.1:60004->6443/tcp
```

El mismo nombre, `curso-k8s-l0-control-plane`. La imagen `kindest/node` trae dentro un sistema Debian completo, con `systemd`, el `kubelet` y `containerd`: es una «máquina» de mentira, hecha contenedor. Dentro de ella, `containerd` corre los contenedores de tus Pods. Son contenedores dentro de un contenedor. (El filtro `--filter label=...` se usó para listar solo los contenedores de este clúster; si en tu máquina hay otros contenedores, no aparecen.)

Fíjate en dos columnas de `get nodes`. `OS-IMAGE` dice Debian, aunque tu sistema sea Mint: es el sistema **de la imagen del nodo**. Pero `KERNEL-VERSION` dice el núcleo **de la máquina que corre Docker**, porque los contenedores no traen núcleo propio: todos usan el del anfitrión. Esa columna es la primera pista de lo que kind no es.

#### 0.6.2 Lo que un clúster de kind demuestra y lo que no

kind corre el Kubernetes de verdad: el mismo `kube-apiserver`, el mismo `etcd`, el mismo *scheduler*, instalados con `kubeadm`, la herramienta oficial ([diseño de kind](https://kind.sigs.k8s.io/docs/design/initial/)). Entre sus metas de diseño está pasar todas las pruebas de conformidad de Kubernetes. Todo lo que aprendas de la **API** —Deployments, Services, ConfigMaps, sondas, permisos— vale igual en un clúster de producción.

Lo que no es igual es **lo que hay debajo**. Esta tabla es la que conviene tener a mano durante el curso:

| Lo que pruebas en kind | ¿Lo demuestra? | Por qué |
|---|---|---|
| Que tus manifiestos son válidos y hacen lo que crees | **Sí** | es la misma API y el mismo código de Kubernetes |
| Que tus Pods renacen cuando mueren | **Sí** | el controlador es el mismo |
| Que tus permisos (RBAC) y el nivel `restricted` funcionan | **Sí** | los aplica el `kube-apiserver`, igual que en producción |
| Que tu servicio sobrevive a la caída de una máquina | **En parte** | `docker stop` a un nodo se parece, pero los tres «nodos» comparten tu máquina, tu disco y tu núcleo: si se cae tu computadora, se cae todo |
| Que tu `NetworkPolicy` corta el tráfico | **Depende** | la aplica la red (CNI), no Kubernetes; la Lección 7 lo mide en vivo |
| Que tu servicio aguanta tal carga | **No** | los nodos se reparten tu procesador y tu memoria; los números no se trasladan a otra máquina |
| Que un `LoadBalancer` te da una IP pública | **No** | kind no trae balanceador; hace falta una pieza aparte ([Cloud Provider KIND](https://kind.sigs.k8s.io/docs/user/loadbalancer/)), y la Lección 6 lo verifica |
| Que tus datos están a salvo | **No** | el almacenamiento por omisión de kind (un aprovisionador llamado `local-path-provisioner`, que kind instala al crear el clúster) guarda los datos en el propio nodo, que es un contenedor de tu máquina; la Lección 8 mide qué se pierde y cuándo |
| Que el plano de control tolera fallas | **No** en este curso | kind permite varios nodos de control, pero en una sola máquina eso prueba la configuración, no la tolerancia real |

Resumen honesto: **kind demuestra que entiendes Kubernetes; no demuestra que tu sistema esté listo para producción.** La Lección 10 termina, precisamente, con la lista de lo que falta.

#### 0.6.3 Un ejemplo real de «comparten tu máquina»

Lo de «los nodos comparten tu núcleo» no es un detalle académico, y la preparación de esta lección lo demostró sin quererlo. La primera vez se intentó crear el clúster con tres nodos, como el de la Lección 1. `kind` dijo que todo había salido bien, incluido el renglón `✓ Joining worker nodes`. Pero `kubectl get nodes` mostraba un solo nodo, y el Pod de `kube-proxy` estaba en estado `Error`. Su bitácora decía:

```text
"command failed" err="failed complete: fsnotify watcher init: too many open files"
```

Y el `kubelet` de los nodos de trabajo, dentro de su contenedor, se detenía con:

```text
"Failed to start cAdvisor" err="inotify_init: too many open files"
```

La causa: los programas de Linux que vigilan cambios en archivos usan un recurso del **núcleo** llamado `inotify`, y el núcleo tiene un límite de cuántos vigilantes puede abrir cada usuario. En esa máquina estaba en 128 (`fs.inotify.max_user_instances = 128`). Cada nodo de kind arranca su propio `kubelet` y su propio `kube-proxy`, todos contra **el mismo núcleo**, y entre los tres agotaron el límite. Con un solo nodo, alcanzó.

La guía de problemas conocidos de kind describe exactamente esto: Ubuntu trae ese límite en 128, «lo cual no basta para crear un clúster con muchos nodos», y recomienda subirlo a 512 ([kind, «Known Issues»](https://kind.sigs.k8s.io/docs/user/known-issues/)). Linux Mint 22 se basa en Ubuntu 24.04 ([Linux Mint, notas de la versión 22](https://www.linuxmint.com/rel_wilma.php)), así que en tu máquina es probable que pase lo mismo. Por eso la Lección 1 ajusta ese límite **antes** de crear el clúster del curso. Y por eso esta lección usa un solo nodo.

La prueba de que esa era la causa: en la misma máquina se subió el límite a 512 y se volvió a crear el clúster de tres nodos, sin cambiar nada más. Esta vez los tres quedaron listos, cada uno con su `kube-proxy` corriendo (el guion es `tres-nodos.sh` y su salida completa, `tres-nodos.salida.txt`):

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l0-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l0-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l0-worker2         Ready    <none>          19s   v1.37.0
```

Dos lecciones salen de aquí. La primera: tres «máquinas» de kind son tres procesos en una sola máquina, y comparten sus límites. La segunda, más general: **un comando que dice «✓» no prueba que el sistema quedó bien**. Se mira el estado (`kubectl get nodes`, `kubectl get pods -A`) antes de dar algo por hecho.

### 0.7 Las versiones

Kubernetes saca una versión menor aproximadamente **tres veces al año** ([kubernetes.io, «Kubernetes Release Cycle»](https://kubernetes.io/releases/release/)), y mantiene a la vez las tres más recientes, cada una con alrededor de **un año** de correcciones ([kubernetes.io, «Releases»](https://kubernetes.io/releases/)). Esto es lo que publicaba esa página el 21 de octubre de 2026:

| Versión menor | Último parche | Fin de soporte |
|---|---|---|
| **1.37** | 1.37.1 | 28 de octubre de 2027 |
| 1.36 | 1.36.5 | 28 de junio de 2027 |
| 1.35 | 1.35.9 | 28 de febrero de 2027 |
| 1.34 | 1.34.12 | 27 de octubre de 2026 |

(La misma página dice que se mantienen «las tres más recientes» y a la vez lista la 1.34 con su fecha de fin; a esa fecha le quedaban seis días.)

El curso usa **Kubernetes 1.37**, la más reciente. Hay dos números distintos que conviene no confundir:

- **El clúster corre 1.37.0.** Es la versión que trae la imagen de nodo por omisión de kind v0.33.0. En `kubectl get nodes` aparece en la columna `VERSION`: `v1.37.0`.
- **`kubectl` es 1.37.1.** Es la herramienta de tu máquina. La política oficial dice que `kubectl` funciona con un servidor de la API hasta **una versión menor** más vieja o más nueva ([kubernetes.io, «Version Skew Policy»](https://kubernetes.io/releases/version-skew-policy/)): con un clúster 1.37, sirven `kubectl` 1.36, 1.37 y 1.38. La diferencia de parche no importa.

Y una más: **la imagen del nodo se fija por su huella**. Las notas de la versión v0.33.0 de kind publican, para cada versión de Kubernetes, la imagen con su huella `sha256`, y dicen que hay que usarla para obtener la imagen construida para esa versión de kind ([kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). Por eso el archivo de configuración del recorrido la escribe completa:

```yaml
# fig00_01.kind.yaml — el clúster de prueba de la Lección 0.
# Un solo nodo, que hace a la vez de plano de control y de nodo de trabajo.
# La imagen del nodo va fijada por su huella (sha256), copiada de las notas de la
# versión v0.33.0 de kind. El clúster del curso (tres nodos) llega en la Lección 1.
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

Una etiqueta como `v1.37.0` la puede mover quien publica la imagen; una huella, no. Si alguien sustituyera la imagen por otra, la huella dejaría de coincidir y la descarga fallaría. Es el mismo hábito que la Lección 1 aplica a los binarios de `kubectl` y `kind`.

### 0.8 Lo que viene en el resto del curso

Todo lo anterior se pone en práctica en las lecciones siguientes. Cada una agrega una pieza al `revisor` en el clúster:

| Lección | Qué se agrega | Qué idea de esta lección pone a trabajar |
|---|---|---|
| 1 | Instalas `kubectl` y `kind` y creas el clúster de tres nodos | el ajuste de `inotify` de 0.6.3; contextos y el hábito de comprobarlos |
| 2 | El `revisor` como Deployment | la cadena Deployment, ReplicaSet y Pod de 0.2.3 |
| 3 | Un Service y su nombre en el DNS | `kube-proxy` y `coredns` de 0.3.3 |
| 4 | Configuración sin reconstruir | el mapa de `-e` a ConfigMap de 0.5 |
| 5 | Sondas, recursos y apagado ordenado | el `kubelet` vigilando y el *scheduler* que deja un Pod `Pending` |
| 6 | Publicar hacia afuera | el `LoadBalancer` que kind no trae (0.6.2) |
| 7 | Espacios, permisos y red | la red que depende del CNI (0.3.3 y 0.6.2) |
| 8 | Datos y tareas | el almacenamiento que vive en el propio nodo (0.6.2) |
| 9 | Escalar y actualizar sin cortes | otro controlador, el que ajusta `replicas` por ti |
| 10 | Todo en un solo `kubectl apply -k` | el archivo como verdad (0.4) |

## El error que vas a ver

Esta lección tiene un error principal, que vas a ver en cuanto algo no esté conectado, y un error **sin mensaje**, que es más peligroso.

**El error principal: `The connection to the server localhost:8080 was refused`.** Al final del recorrido se borró el clúster y se intentó usarlo:

```text
$ kubectl config current-context
error: current-context is not set

$ kubectl get nodes
E1021 01:52:19.535319   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.535953   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.536970   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.537419   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.538619   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
```

Se lee de abajo hacia arriba, porque el último renglón es el resumen: «se rechazó la conexión al servidor `localhost:8080`; ¿indicaste el anfitrión o el puerto correctos?». Los cinco renglones con `E1021` son reintentos, uno por intento de descubrir qué tipos de objeto existen; dicen lo mismo y se pueden ignorar.

La pista está en el primer comando: **no hay contexto activo**. Un **contexto** es la entrada del archivo de configuración de `kubectl` (el `kubeconfig`) que dice a qué clúster hablarle y con qué credencial. `kind` agregó uno al crear el clúster y lo quitó al borrarlo. Sin contexto, `kubectl` no sabe a dónde ir y prueba una dirección por omisión, `localhost:8080`, donde no hay nadie. El mensaje no quiere decir «tu clúster se cayó»: quiere decir **«no sé cuál es tu clúster»**. Se arregla dándole un contexto, que en este curso es siempre el que crea `kind` (Lección 1).

**El error sin mensaje: el contexto equivocado.** Ahora imagina lo contrario: sí hay contexto, pero no es el que crees. Tu computadora tiene configurado un clúster del trabajo, de la escuela o de un proyecto anterior, y ese es el activo. Tecleas `kubectl delete deployment revisor` pensando en tu kind. El clúster responde `deployment.apps "revisor" deleted`, sin error, sin advertencia. Lo borraste **en otro lado**.

Ese error no se puede leer porque no produce mensaje. Solo se previene, con un hábito: **antes de cada comando que cambia algo, `kubectl config current-context`**. En el recorrido, la respuesta fue esta, y solo después de verla se siguió:

```text
$ kubectl config current-context
kind-curso-k8s-l0
```

El guion `recorrido.sh` lo hace solo: antes de cada `kubectl`, compara el contexto activo con `kind-curso-k8s-l0`, y si no coincide, se detiene. Además, le da a kind un archivo `kubeconfig` propio y temporal, de modo que tu configuración de siempre ni se toca. Y solo borra lo que creó él mismo: si al empezar ya existe un clúster llamado `curso-k8s-l0`, se detiene sin tocarlo, y si falla a medio camino, al salir borra únicamente el clúster que esa corrida alcanzó a crear. La Lección 1 te enseña a hacer lo mismo a mano.

## El hábito de seguridad de la lección: qué defiende un clúster local y qué no

La tabla de hábitos del curso le asigna a esta lección uno solo: **saber qué defiende un clúster local y qué no**. El recorrido miró tres cosas.

**Primera: el servidor de la API solo escucha en tu propia máquina.**

```text
$ docker inspect curso-k8s-l0-control-plane --format 'privilegiado={{.HostConfig.Privileged}}  puerto_api={{json .NetworkSettings.Ports}}'
privilegiado=true  puerto_api={"6443/tcp":[{"HostIp":"127.0.0.1","HostPort":"60004"}]}
```

El puerto 6443 del nodo, donde atiende el `kube-apiserver`, se publica en `127.0.0.1`: la dirección que solo es alcanzable desde tu propia computadora. Nadie en tu red puede hablarle a tu clúster. La guía de configuración de kind dice que se puede cambiar, y lo desaconseja con fuerza: recomienda dejar `127.0.0.1` «por razones de seguridad» y «no exponer kind a nada que no sea la interfaz de bucle local» ([kind, «Configuration»](https://kind.sigs.k8s.io/docs/user/configuration/)). Lo defiende: el acceso desde afuera.

**Segunda: tu `kubeconfig` es la llave maestra.**

```text
$ kubectl auth whoami
ATTRIBUTE                                           VALUE
Username                                            kubernetes-admin
Groups                                              [kubeadm:cluster-admins system:authenticated]
```

(El renglón `Extra` con la huella de la credencial se omitió aquí; está en `recorrido.salida.txt`.) El usuario con el que trabajas es `kubernetes-admin`, del grupo `kubeadm:cluster-admins`: **administrador total** del clúster. La credencial vive en el `kubeconfig`, en los campos `client-certificate-data` y `client-key-data`, que `kubectl config view` oculta con `DATA+OMITTED` precisamente porque son secretos. En un clúster local el daño posible es menor, pero el `kubeconfig` sigue siendo una credencial de administrador, y en uno de verdad equivale a la contraseña de administrador: en los dos casos no se copia a un chat ni se sube a un repositorio. La Lección 7 crea una cuenta con permisos mínimos para el `revisor`, porque el `revisor` no debe tener esta llave.

**Tercera: el nodo es un contenedor privilegiado.** El mismo `docker inspect` dice `privilegiado=true`. Para que un contenedor pueda hacerse pasar por una máquina completa, con su `systemd` y su propio `containerd`, necesita casi todos los poderes del anfitrión. Eso quiere decir que **kind no es una frontera de seguridad**: un clúster de kind no aísla de tu computadora lo que corra dentro. Lo que no defiende: tu máquina frente a lo que metas en el clúster. Por eso, en este curso, en kind solo corren imágenes que conoces: la del `revisor`, la del servicio de prueba y las oficiales de Kubernetes.

Las tres juntas dan la regla: un clúster de kind está bien protegido **hacia afuera** y no protege nada **hacia adentro**. Es un laboratorio, no una caja fuerte.

## Lo que se hace mal

**Borrar un Pod para «apagar» algo.** El ReplicaSet lo repone en un segundo, como viste en 0.2.4. Para apagar, se cambia el estado deseado (`replicas: 0`) o se borra el Deployment.

**Dar órdenes sobre algo que se administra con archivos.** Un `kubectl scale` o un `kubectl edit` sobre un objeto que vive en Git dura hasta el siguiente `apply`, y la siguiente persona que aplique no sabrá que existió. Si el cambio vale, se hace en el archivo.

**Aplicar sin mirar `kubectl diff`.** Es la única forma de saber qué va a cambiar antes de que cambie. Cuesta un comando.

**No comprobar el contexto.** Es el error sin mensaje de «El error que vas a ver». En una máquina con un solo clúster parece innecesario; en cuanto hay dos, es la diferencia entre un experimento y un incidente.

**Creer que kind demuestra producción.** Que tu servicio aguante en kind la caída de un «nodo» no dice nada de cómo aguanta la caída de una máquina real, ni la carga real, ni un disco real. Kind demuestra que entiendes la API.

**Fiarse de la palomita verde.** `kind create cluster` dijo `✓ Joining worker nodes` con dos nodos que nunca llegaron a unirse (0.6.3). Después de crear algo, se mira su estado.

**Escribir a mano el nombre de un Pod.** El sufijo es aleatorio y cambia cada vez que el Pod renace. Se busca por etiqueta (`-l app=...`).

**Copiar un tutorial sin mirar la fecha.** Kubernetes cambia tres veces al año. Lo que se retiró sigue en internet: tutoriales que instalan Docker dentro de los nodos (dockershim se quitó en la 1.24) o que usan `ingress-nginx`, que el proyecto Kubernetes retiró en marzo de 2026: sin versiones nuevas ni correcciones de seguridad ([kubernetes.io, «Ingress NGINX Retirement»](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)). La Lección 6 explica qué se usa en su lugar.

## Ejercicios

Los ejercicios de esta lección no requieren un clúster. El primero y el segundo se contestan leyendo las salidas de la lección; el tercero se contesta **antes** de correr nada y se comprueba después de la Lección 1 con `ejercicio3.sh`; el cuarto se escribe con tus palabras. Anota tus respuestas en la [bitácora](bitacora.md) antes de mirar las soluciones.

### Ejercicio 1 — La noche del viernes (proyecto)

Vuelve a la escena del principio. Para cada una de estas cosas que se perdieron con el servidor, di qué objeto o pieza de Kubernetes la habría guardado o resuelto, usando el mapa de 0.5:

1. Que hubiera tres copias del `revisor` y no una.
2. Que, al caerse la máquina, alguien levantara las copias en otra.
3. Las variables de entorno con la lista de servicios a revisar.
4. El puerto por el que se le habla.
5. «Cómo estaba levantado», que vivía en el historial de una terminal.

### Ejercicio 2 — ¿Quién lo hizo?

Para cada uno de estos hechos del recorrido, di qué pieza de 0.3 es la responsable:

1. Se guardó el Deployment `espera` y `kubectl` respondió `created`.
2. Apareció el ReplicaSet `espera-68b9d575f7`.
3. Cada uno de los tres Pods quedó asignado al nodo `curso-k8s-l0-control-plane`.
4. Los contenedores de los Pods arrancaron dentro del nodo.
5. Al borrar `espera-68b9d575f7-9gbtr`, apareció `espera-68b9d575f7-fjx8v`.
6. El Pod `kube-apiserver-curso-k8s-l0-control-plane` existía antes de que hubiera un servidor de la API que lo creara.

### Ejercicio 3 — Predice antes de correr

Sin correr nada, predice qué responde el clúster en cada caso. Después de la Lección 1, compruébalo con `programas/00-que-es-kubernetes/ejercicio3.sh`, que crea un clúster de prueba, corre los cuatro casos y lo borra.

1. El Deployment `espera` tiene `replicas: 3`. Borras **los tres** Pods con `kubectl delete pods -l app=espera`. ¿Cuántos Pods hay diez segundos después?
2. Corres `kubectl scale deployment espera --replicas=1` y luego `kubectl apply -f fig00_02.deployment.yaml`. ¿Cuántas réplicas quedan?
3. Corres `kubectl delete deployment espera`. ¿Qué pasa con el ReplicaSet y con los Pods?
4. Borras el clúster con `kind delete cluster --name curso-k8s-l0` y corres `kubectl get pods`. ¿Qué mensaje esperas?

### Ejercicio 4 — Kind en cinco frases

Una compañera te pregunta: «si en mi laptop el `revisor` en kind sobrevive a que apague un nodo, ¿ya puedo decir que en producción también sobrevive?». Contéstale en cinco frases como máximo, usando las palabras *contenedor*, *núcleo*, *API* y *producción*. Sin mirar la lección.

## Soluciones

### Solución 1

1. **Tres copias:** el campo `replicas: 3` de un **Deployment**; el **ReplicaSet** que crea es el que cuenta que sean tres.
2. **Levantarlas en otra máquina:** el **ReplicaSet** repone los Pods que faltan, el **`kube-scheduler`** elige un nodo vivo para cada uno y el **`kubelet`** de ese nodo los arranca. Con la espera de 300 segundos de 0.2.5, salvo que haya réplicas en otros nodos que sigan atendiendo mientras tanto.
3. **Las variables de entorno:** un **ConfigMap** (y un **Secret** si alguna es confidencial), Lección 4.
4. **El puerto:** un **Service**, Lección 3.
5. **«Cómo estaba levantado»:** el **manifiesto**, guardado en un archivo y en Git, y aplicado con `kubectl apply`. Es la respuesta que más importa: el conocimiento deja de vivir en una persona o en una terminal y queda escrito. El clúster lo guarda en `etcd`, y tú en tu repositorio, así que se puede reconstruir aunque se pierda el clúster entero.

### Solución 2

1. El **`kube-apiserver`**, que valida el objeto y lo guarda en **`etcd`**.
2. El controlador de Deployments, dentro del **`kube-controller-manager`**.
3. El **`kube-scheduler`**. (En un clúster de un solo nodo no hay mucho que elegir, pero la decisión la toma él igual.)
4. El **`kubelet`** del nodo, que se lo pide al *runtime*, **`containerd`**.
5. El controlador de ReplicaSets, dentro del **`kube-controller-manager`**. Lo dejó escrito en el evento `SuccessfulCreate`.
6. El **`kubelet`**, a partir del archivo `/etc/kubernetes/manifests/kube-apiserver.yaml`: es un **Pod estático** (0.3.4).

### Solución 3

Las cuatro se midieron con `ejercicio3.sh`; su salida completa está en `ejercicio3.salida.txt`.

1. **Tres.** El ReplicaSet ve cero Pods donde debe haber tres y crea tres nuevos, con sufijos nuevos. Borrar todos no cambia el estado deseado. En la corrida, los tres borrados fueron `khb2n`, `phxml` y `srfng`, y diez segundos después había tres distintos: `kcvgl`, `qbnbx` y `qz6pc`.
2. **Tres.** La orden bajó a una, pero `replicas: 3` está en el archivo, y `apply` lo vuelve a imponer, igual que en 0.4.2 con el cinco. Si antes del `apply` corres `kubectl diff -f fig00_02.deployment.yaml`, ves `-  replicas: 1` / `+  replicas: 3`.
3. **Se borran los tres niveles.** El ReplicaSet le pertenece al Deployment y los Pods al ReplicaSet; al borrar al dueño, Kubernetes borra lo que depende de él. Cinco segundos después, `kubectl get replicaset,pods -l app=espera` respondió `No resources found in default namespace.` Aquí sí se apaga el servicio, porque desaparece el estado deseado.
4. `The connection to the server localhost:8080 was refused - did you specify the right host or port?`, precedido de varios renglones `E…` de reintentos. Kind quitó el contexto al borrar el clúster, y sin contexto `kubectl` prueba `localhost:8080`. Ojo: el guion usa un `kubeconfig` propio en el que solo existía el clúster del curso. Si en el tuyo hay otros clústeres configurados, la respuesta depende de cuál quede activo, y podrías estar hablándole a otro sin saberlo: por eso se comprueba con `kubectl config current-context` y no se supone.

### Solución 4

Una respuesta posible: «No todavía. En kind, cada nodo es un *contenedor* en tu laptop, así que los tres nodos comparten tu disco, tu memoria y tu *núcleo*: apagar uno se parece a perder una máquina, pero si se cae tu laptop se cae todo. Lo que sí demostraste es que tu configuración de la *API* es correcta: las réplicas, su reparto y su reposición funcionan igual en cualquier Kubernetes. Para afirmarlo de *producción* falta probarlo en máquinas separadas de verdad, con su red, sus discos y su carga. Kind demuestra que lo entiendes; producción se demuestra en producción».

## Cómo sé que lo logré

- [ ] Explicas, con la escena del viernes, por qué `--restart always` no basta cuando la máquina se cae.
- [ ] Dibujas de memoria el plano de control y un nodo, con sus siete piezas, y dices qué hace cada una en una frase.
- [ ] Cuentas los siete pasos de 0.3.5, del `kubectl apply` al contenedor corriendo.
- [ ] Sabes por qué el `kube-apiserver` puede ser un Pod sin que nadie le pida a la API que lo cree.
- [ ] Ante `kubectl scale` seguido de `kubectl apply`, predices qué número de réplicas queda.
- [ ] Traduces al menos cinco conceptos de Docker a Kubernetes y nombras uno sin equivalente.
- [ ] Dices dos cosas que un clúster de kind demuestra y tres que no.
- [ ] Ante `The connection to the server localhost:8080 was refused`, dices qué significa sin buscarlo.
- [ ] Después de la Lección 1, corres `programas/00-que-es-kubernetes/recorrido.sh` y compruebas contra `recorrido.salida.txt` lo que no cambia entre corridas: un nodo `Ready`; el Deployment en `3/3` y su ReplicaSet con `3` deseados, `3` actuales y `3` listos; tres Pods `Running` después de borrar uno; el `diff` que muestra `replicas: 5` contra `replicas: 3`; el usuario `kubernetes-admin`; y el error final `localhost:8080`. Los nombres generados, las edades, las IP, los puertos, los eventos, el avance de `kind` y de `rollout` y las rutas temporales cambian en cada corrida: se observan, no se comparan.

## Resumen

Responde sin mirar la lección:

1. ¿Qué pregunta responde Docker y qué pregunta responde Kubernetes?
2. ¿Qué es un bucle de control? Explícalo con el termostato.
3. ¿Qué diferencia hay entre un Deployment, un ReplicaSet y un Pod?
4. ¿Qué responde `kubectl apply` cuando crea un Deployment, y por qué esa respuesta no quiere decir que haya contenedores corriendo?
5. ¿Cuánto espera Kubernetes antes de reponer los Pods de un nodo que dejó de responder? ¿Por qué no espera cero?
6. ¿Qué es un Pod estático y quién lo arranca?
7. ¿Qué pasa si das una orden que contradice tu archivo y luego aplicas el archivo?
8. ¿Qué tiene que ver el núcleo de tu máquina con que un clúster de tres nodos de kind no arranque?
9. ¿Qué defiende un clúster de kind y qué no?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Overview»](https://kubernetes.io/docs/concepts/overview/): la definición de Kubernetes, el origen del nombre, la abreviatura K8s, el año en que se liberó y la lista de lo que Kubernetes no es.
- [Kubernetes, «Controllers»](https://kubernetes.io/docs/concepts/architecture/controller/): el bucle de control, el termostato y el estado deseado contra el actual.
- [Kubernetes, «Kubernetes Components»](https://kubernetes.io/docs/concepts/overview/components/): las piezas del plano de control y de los nodos, de donde salen las definiciones de la tabla de 0.3.2.
- [Kubernetes, «Pods»](https://kubernetes.io/docs/concepts/workloads/pods/): la definición de Pod y por qué casi nunca se crean solos.
- [Kubernetes, «Create static Pods»](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/): los Pods estáticos que el `kubelet` lee de una carpeta.
- [Kubernetes, «Taints and Tolerations»](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): las tolerancias automáticas de 300 segundos.
- [Kubernetes, «Kubernetes Object Management»](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/): órdenes contra declaraciones, y la advertencia de no mezclarlas.
- [Kubernetes, «Releases»](https://kubernetes.io/releases/) y [«Kubernetes Release Cycle»](https://kubernetes.io/releases/release/): las versiones vigentes, su fin de soporte y el ritmo de tres por año.
- [Kubernetes, «Version Skew Policy»](https://kubernetes.io/releases/version-skew-policy/): qué versiones de `kubectl` sirven con qué servidor.
- [Kubernetes, «Dockershim: The Historical Context»](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/) y [«Don't Panic: Kubernetes and Docker»](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/): por qué los nodos ya no usan Docker y por qué tus imágenes siguen sirviendo.
- [Docker, «Start containers automatically»](https://docs.docker.com/engine/containers/start-containers-automatically/): las políticas de reinicio de Docker.
- [kind](https://kind.sigs.k8s.io/), [su diseño inicial](https://kind.sigs.k8s.io/docs/design/initial/), [«Configuration»](https://kind.sigs.k8s.io/docs/user/configuration/), [«Known Issues»](https://kind.sigs.k8s.io/docs/user/known-issues/) y [«LoadBalancer»](https://kind.sigs.k8s.io/docs/user/loadbalancer/): qué es kind, para qué se diseñó, la dirección del servidor de la API, la red por omisión, el límite de `inotify` y el balanceador que no trae.
- [Kubernetes, «Ingress NGINX Retirement: What You Need to Know»](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/): el retiro de `ingress-nginx` en marzo de 2026.
- [kind v0.33.0, notas de la versión](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0): la imagen de nodo por omisión y su huella.
- [Linux Mint 22, notas de la versión](https://www.linuxmint.com/rel_wilma.php): Mint 22 se basa en Ubuntu 24.04.

---

**Siguiente:** [Lección 1 — Instalar kubectl y kind; tu primer clúster](01-instalacion-primer-cluster.md)
