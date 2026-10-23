# Lección 3 — Services y DNS

Martes, 10:20 de la mañana. A las 11:00 el área de operación revisa el tablero y quiere ver el reporte del `revisor` en verde. Ayer, para salir del paso, un compañero copió la IP de un Pod del servicio de prueba, `10.244.1.3`, y la pegó en la lista de servicios que revisa el `revisor`. Funcionó toda la tarde. Esta mañana el reporte dice `FALLA` en todos los renglones, y nadie tocó nada. O eso creen: en la noche alguien reinició los Pods para aplicar un cambio, los Pods renacieron y ninguno volvió con la IP de ayer. La dirección que pegó tu compañero ahora no es de nadie, o peor, es de otro Pod que no tiene nada que ver. Faltan cuarenta minutos y la pregunta no es qué IP pegar ahora, sino cómo dejar de pegar IPs.

Kubernetes ya resolvió ese problema, y la solución tiene dos piezas: un **Service**, que es un nombre y una dirección que no cambian aunque los Pods de detrás cambien todo el tiempo, y el **DNS del clúster**, que convierte ese nombre en esa dirección para cualquier Pod que pregunte. Esta lección te enseña a escribir el primero, a interrogar al segundo y a leer qué pasa cuando un Service no encuentra a nadie a quién mandar tráfico.

**Tiempo:** 2 × 45 min

**Qué construyes:** el `revisor` encontrable por nombre dentro del clúster, y su compañero, el servicio de prueba, encontrable también, de modo que el reporte por fin revisa a alguien de verdad

**Qué aprendes:** qué es un Service de tipo `ClusterIP` y por qué es el tipo por omisión; cómo un selector de etiquetas decide a qué Pods llega el tráfico y dónde queda escrita esa decisión (`EndpointSlice`); la cadena de tres puertos, `port`, `targetPort` y `containerPort`; cómo resuelve nombres el DNS del clúster y por qué `revisor` a secas funciona; `kubectl port-forward` hacia `127.0.0.1`; y un Pod de depuración para mirar desde dentro cuando la imagen no tiene *shell*

**De dónde vienes.** De la [Lección 2](02-pods-deployments.md): el `revisor` corre con tres réplicas en un Deployment, con su `securityContext` completo y un `emptyDir` en `/datos`. Sabes que cada Pod tiene su IP y que esa IP cambia cada vez que el Pod renace, y viste que la imagen del `revisor` no trae *shell* ni `curl`. De la [Lección 0](00-que-es-kubernetes.md) traes dos nombres que hasta ahora eran solo nombres: `kube-proxy`, que hay uno por nodo, y `coredns`, que corre en el nodo de control. En esta lección los dos se ponen a trabajar.

**Qué no hace esta lección.** El `revisor` queda encontrable **dentro** del clúster y, para ti, por un túnel temporal (`port-forward`). No queda publicado hacia afuera: un `LoadBalancer` y una puerta de entrada con Gateway API son la [Lección 6](06-entrar-al-cluster.md). Tampoco se cierra todavía quién le puede hablar a quién: hoy cualquier Pod del clúster llega al `revisor`, y la [Lección 7](07-aislar-permisos-red.md) pone la red en «todo cerrado». Y el Service manda tráfico a cualquier Pod que esté corriendo, sano o no: decirle al clúster cuándo un Pod está listo para recibir tráfico es trabajo de las sondas de la [Lección 5](05-salud-recursos-apagado.md).

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1 y la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l3`. La máquina fue una Mac con procesador ARM y Docker Engine 29.2.1 dentro de una máquina virtual Linux (Colima), **no** Linux Mint, que es el sistema de referencia del curso. Lo que cambia en tu Mint: la arquitectura (`amd64` en lugar de `arm64`), las direcciones IP de los Pods y de los Services, los sufijos al azar de los nombres, las edades, en qué nodo cae cada réplica, el puerto que Docker le da al nodo de control y cuántas peticiones le tocan a cada réplica en 3.8. Los comandos son los mismos. El recorrido completo está en [`programas/03-services-dns/`](../programas/03-services-dns): `correr.sh` crea el clúster, le carga las imágenes, deja el `revisor` como lo dejó la Lección 2, recorre la lección en orden, corre los Ejercicios 1 a 3 y borra el clúster; tardó 2 minutos y 16 segundos (la última línea de la salida lo dice: `la corrida completa tardó 136 s`), de los cuales crear el clúster y esperar a que estuviera listo fueron 46 segundos. Su salida es `correr.salida.txt`. Ahí, la sección del hábito de seguridad aparece antes que la del error, porque el guion la corre en ese orden. El `port-forward` usa el puerto `18080` de tu máquina; si lo tienes ocupado, el guion se detiene antes de crear nada y te dice cómo elegir otro (`PUERTO_LOCAL=18081 ./correr.sh …`). En la máquina donde se escribió esta lección corrían a la vez los clústeres de otras lecciones, y para no chocar con ellos el guion se corrió con `PUERTO_LOCAL=18300`; en `correr.salida.txt` y en esta lección el número se reescribió a `18080`, el que vas a usar tú. Es lo único que se tocó de la salida.

## Al terminar vas a poder

- Explicar con un ejemplo por qué ningún programa debe guardar la IP de un Pod, y qué le da a cambio un Service.
- Escribir de memoria un Service `ClusterIP` con su `selector` y su lista de `ports`, y seguir la cadena `port` → `targetPort` → `containerPort` en un caso concreto.
- Encontrar el `EndpointSlice` de un Service con `-l kubernetes.io/service-name=…` y decir, con él en la mano, a qué Pods llega el tráfico.
- Resolver el nombre de un Service desde un Pod de depuración y explicar cada línea de su `/etc/resolv.conf`, incluidos los `NXDOMAIN` que imprime `nslookup`.
- Abrir un `port-forward` que escuche solo en `127.0.0.1` y decir cuándo se rompe.
- Provocar un Service sin endpoints, reconocerlo por `<unset>` y por el código 7 de `curl`, y corregirlo.

## El porqué antes del cómo

En la Lección 2 dejaste tres réplicas del `revisor` corriendo, y la sección 2.4 terminó con una advertencia: cada Pod tiene su IP, y esa IP cambia cada vez que el Pod renace. Es la escena del martes. Un Pod es desechable por diseño. El ReplicaSet lo repone cuando muere, y el repuesto es **otro** Pod, con otro nombre y otra dirección. Si los clientes guardan la dirección de un Pod, cada reposición los deja hablando con nadie.

Hay una segunda razón, y es más sutil. Aunque los Pods no murieran nunca, tienes **tres**. ¿A cuál le habla el cliente? Si elige uno, los otros dos sobran. Si quieres que reparta, tendrías que darle la lista completa al cliente y mantenérsela al día. Eso es lo que hacía Compose en el curso de Docker, de forma escondida: un nombre de servicio que la red de Compose resolvía a sus contenedores. En Kubernetes, la misma idea tiene nombre propio y manifiesto propio.

Un **Service** responde a las dos preguntas a la vez. Te da una IP virtual que no cambia mientras el Service exista, y detrás de ella, la lista viva de Pods que la atienden. La lista no la escribes tú: la escribe un controlador, a partir de una regla que sí escribes, el **selector**. Y para que nadie tenga que saberse esa IP virtual, el **DNS del clúster** le pone nombre: `revisor`, o con nombre completo, `revisor.default.svc.cluster.local`.

La lección tiene nueve partes de conceptos y después las secciones de siempre:

1. **Una IP de Pod no sirve como dirección** (3.1): lo que cambia cuando un Pod renace.
2. **El Service del `revisor`** (3.2), campo por campo.
3. **Los tres puertos** (3.3): `port`, `targetPort` y `containerPort`.
4. **Selectores y `EndpointSlice`** (3.4): dónde queda escrita la lista de Pods.
5. **Un Pod de depuración** (3.5), porque el `revisor` no tiene *shell*.
6. **El DNS del clúster** (3.6).
7. **El servicio de prueba** (3.7): el `revisor` por fin revisa a alguien.
8. **Cómo reparte un Service** (3.8).
9. **`port-forward`** (3.9): un túnel desde tu máquina, solo hacia `127.0.0.1`.

Este es el destino. Al final de 3.7, un Pod cualquiera del clúster le pide el reporte al `revisor` por su nombre, y el `revisor` encuentra al servicio de prueba también por su nombre:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

## Si no traes la imagen del curso de Docker

Esta lección usa dos imágenes del curso de Docker: la del `revisor`, `curso-docker-revisor:1.6.0`, que entrega su Lección 10, y la del servicio que falla a propósito, `curso-docker-prueba:1.0.0`. Antes de seguir, comprueba que tienes las dos:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para la otra, el mismo comando con `curso-docker-prueba:1.0.0`. Si te falta la del `revisor`, constrúyela desde el repositorio de ese curso, con el `Dockerfile` de su Lección 10 sobre la carpeta `programas/revisor` y con `--build-arg VERSION=1.6.0`, etiquetándola exactamente `curso-docker-revisor:1.6.0`. Si te falta la de prueba, constrúyela desde la carpeta `programas/servicio-prueba` de ese mismo repositorio, etiquetada `curso-docker-prueba:1.0.0`. La [Lección 2](02-pods-deployments.md) trae, en esta misma sección, la lista de lo que el curso le pide a una imagen tuya si prefieres usar otra.

Lo que esta lección le pide **además** al servicio de prueba, y conviene leerlo porque cada punto explica una línea de su manifiesto:

- **Escucha HTTP en el puerto 9000** y responde `GET /` con `200` cuando está sano, con `503` cuando está caído y tarde cuando está lento.
- **Cambia de modo con `POST /modo/sano`, `POST /modo/lento` y `POST /modo/caido`**, y dice en qué modo está con `GET /modo`. Así puedes romperlo desde fuera sin reconstruir nada.
- **Corre como el usuario 65532**, sin `root`, y **aguanta el sistema de archivos de solo lectura** sin volumen: no escribe nada en disco.

Y las dos se cargan al clúster como en la Lección 2, con `kind load docker-image` y el nombre del clúster. Se pueden cargar las dos en un solo comando:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l3
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker2", loading...
```

Seis renglones: dos imágenes por tres nodos. (En tu corrida el orden de los renglones puede ser otro.) El Pod de depuración de 3.5 usa una tercera imagen, `curlimages/curl`, que **no** se carga: es pública, va fijada por su huella `sha256` y el nodo donde caiga el Pod la descarga de Docker Hub la primera vez. Necesitas internet para ese paso.

## Los conceptos

### 3.1 Una IP de Pod no sirve como dirección

Esta lección usa su propio clúster, `curso-k8s-l3`, con la configuración de tres nodos de la Lección 1, recién creado. Créalo así, desde la raíz del repositorio del curso, con el mismo cuidado que aprendiste en la Lección 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l3.XXXX)/kubeconfig"
# curso-k8s-l3 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l3 --config programas/03-services-dns/kind-curso.yaml
# Debe decir kind-curso-k8s-l3. Si dice otra cosa, no sigas.
kubectl config current-context
```

El `export` solo vale en esa terminal. Si abres otra (en 3.9 vas a querer una para el `port-forward`), repite el `export` con la misma ruta, o `kubectl` le hablará a otro clúster. Después carga las dos imágenes, como se vio arriba, y aplica el Deployment de la Lección 2 tal cual, sin cambiar una coma; desde aquí los comandos se corren dentro de `programas/03-services-dns/` (entra con `cd programas/03-services-dns`, o `kubectl apply -f revisor-deployment.yaml` dirá que la ruta no existe). Las salidas son de la corrida de `correr.sh`, que hace exactamente esto:

```text
$ kubectl config current-context
kind-curso-k8s-l3

$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-82d87   1/1     Running   0          1s    10.244.1.2   curso-k8s-l3-worker2   <none>           <none>
revisor-697fb84f97-drv5h   1/1     Running   0          1s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          1s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
```

El primer comando es el hábito de siempre: antes de cambiar algo, preguntar a qué clúster le hablas. Repítelo **antes de cada** `apply`, `delete`, `rollout restart` o `port-forward` de la lección, no solo aquí; el guion lo hace solo, antes de cada `kubectl`, y se detiene si la respuesta no es `kind-curso-k8s-l3`. Ahora mira la columna `IP`. Las tres direcciones empiezan con `10.244.`: es la red de Pods que kind arma por omisión. Su [guía de configuración](https://kind.sigs.k8s.io/docs/user/configuration/) lo dice así: «por omisión, kind usa la subred de Pods `10.244.0.0/16` para IPv4». Cada nodo recibe un pedazo de esa red: en esta corrida, los Pods de `worker2` están en `10.244.1.x` y los de `worker` en `10.244.2.x` (qué pedazo le toca a cada nodo cambia de una corrida a otra).

Ahora la escena del martes, en pequeño. Se borra uno:

```text
$ kubectl delete pod revisor-697fb84f97-82d87
pod "revisor-697fb84f97-82d87" deleted from default namespace

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-drv5h   1/1     Running   0          2s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          2s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-z79jh   1/1     Running   0          1s    10.244.1.3   curso-k8s-l3-worker2   <none>           <none>
```

El ReplicaSet lo repuso en un segundo, como en la Lección 2 (si listas los Pods justo después de borrar, quizá veas el viejo en `Terminating` y el nuevo en `ContainerCreating`; espera unos segundos o corre `kubectl rollout status deployment/revisor`, y quedarán tres). Pero el Pod nuevo, `z79jh`, no es el que murió: otro nombre y otra IP (`10.244.1.3` en lugar de `10.244.1.2`). Fíjate en que cayó en el **mismo** nodo, `worker2`, y aun así la dirección cambió: no hace falta que el Pod se mude para que su IP sea otra. En otra corrida puede caer además en otro nodo. La dirección `10.244.1.2` ya no es de nadie. Si un programa la tenía guardada, desde este segundo le habla a una dirección vacía. Y si dentro de un rato otro Pod nace en `worker2`, puede recibir justo esa dirección, y el programa le hablaría a un desconocido sin enterarse.

No es un defecto de kind ni de este clúster: es el diseño. Los Pods son, en palabras de la [documentación de Pods](https://kubernetes.io/docs/concepts/workloads/pods/), entidades «relativamente efímeras y desechables». Lo que tiene que ser estable no es el Pod, es el **acceso** al conjunto de Pods. Eso es un Service.

### 3.2 El Service del `revisor`

La [documentación de Services](https://kubernetes.io/docs/concepts/services-networking/service/) lo define en una frase: un Service es «un método para exponer una aplicación de red que corre como uno o más Pods en tu clúster». Y precisa qué guarda: cada Service «define un conjunto lógico de *endpoints* (normalmente esos *endpoints* son Pods) junto con una política sobre cómo hacer accesibles esos Pods».

Este es el del `revisor`. Es un **programa**: se aplica solo y vive en `programas/03-services-dns/revisor-service.yaml`.

```yaml
# revisor-service.yaml — Lección 3: un nombre estable para las réplicas del revisor.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

Es mucho más corto que el Deployment, y se lee igual, de afuera hacia adentro.

#### 3.2.1 Qué es y cómo se llama

`apiVersion: v1` y `kind: Service`: los Services viven en el grupo central de la API, el mismo de los Pods, que no lleva nombre. `metadata.name: revisor` es el nombre del Service, y no es un detalle: **ese nombre es el que vas a escribir en las URL**. El DNS del clúster (3.6) lo convierte en dirección. Por eso el Service se llama igual que el Deployment, aunque no tiene por qué: el Deployment se llama `revisor` para ti, y el Service se llama `revisor` para los clientes. La etiqueta `app: revisor` del propio Service es, como en el Deployment, para que lo encuentres con `-l app=revisor`; no decide nada del tráfico.

#### 3.2.2 Qué tipo de Service

`type: ClusterIP` dice qué clase de dirección recibe. La documentación de Services describe este tipo así: «expone el Service en una IP interna del clúster. Elegir este valor hace que el Service sea alcanzable solo desde dentro del clúster. Es el valor por omisión que se usa si no especificas un `type`». El manifiesto lo escribe aunque sea el valor por omisión, por la misma razón que la Lección 2 escribió `IfNotPresent`: para que quien lo lea no tenga que saberse la regla, y para que la decisión de **no** publicar quede a la vista. La misma página dice cómo se publica algo hacia internet: «con un Ingress o un Gateway». Eso es la Lección 6. Hoy, a propósito, nada sale.

#### 3.2.3 A quién le manda tráfico

`selector: {app: revisor}` es la regla: «mis Pods son los que llevan la etiqueta `app: revisor`». Es la misma etiqueta que el Deployment pone en su plantilla, y por eso el Service encuentra las tres réplicas. Fíjate en lo que **no** dice: no menciona el Deployment, ni el ReplicaSet, ni el `pod-template-hash`. El Service no sabe que existe un Deployment. Elige Pods por etiqueta y nada más. El Ejercicio 2 te muestra la consecuencia, la que la Lección 2 te dejó anunciada.

#### 3.2.4 Por dónde

`ports` es una lista; aquí trae un solo puerto, llamado `http`. `port: 80` es el puerto **del Service**: el que usan los clientes. `targetPort: http` es el puerto **del Pod** al que se reenvía el tráfico, y no va como número sino por **nombre**. La sección 3.3 sigue esta cadena con el clúster delante.

#### 3.2.5 Aplicarlo y mirarlo

```text
$ kubectl apply -f revisor-service.yaml
service/revisor created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   41s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP    2s
```

Dos Services. El tuyo, `revisor`, recibió la IP `10.96.144.175`. Es de otra red, `10.96.`, distinta de la de los Pods: la guía de kind dice que, por omisión, usa «la subred de Services `10.96.0.0/16` para IPv4». El otro, `kubernetes`, no lo creaste tú: es el Service del propio `kube-apiserver`, en la primera dirección de esa red, para que los Pods que necesiten hablarle a la API lo encuentren por nombre como a cualquier otro. `EXTERNAL-IP <none>`: no hay dirección hacia afuera, como se pidió.

`kubectl describe` junta todo lo del Service:

```text
$ kubectl describe service revisor
Name:                     revisor
Namespace:                default
Labels:                   app=revisor
Annotations:              <none>
Selector:                 app=revisor
Type:                     ClusterIP
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.96.144.175
IPs:                      10.96.144.175
Port:                     http  80/TCP
TargetPort:               http/TCP
Endpoints:                10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

Los renglones que importan hoy:

- `Selector: app=revisor`: la regla que escribiste.
- `IP: 10.96.144.175`: la dirección estable. La documentación la llama *cluster IP* y explica que «la usa el mecanismo de direcciones IP virtuales». No pertenece a ninguna máquina ni a ningún Pod; 3.8 cuenta quién la hace funcionar.
- `Port: http 80/TCP` y `TargetPort: http/TCP`: los dos extremos de la cadena de puertos.
- `Endpoints: 10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080`: **las tres réplicas**, con su IP y su puerto real. Compáralas con la segunda tabla de 3.1: son exactamente las de los tres Pods vivos, incluida la `10.244.1.3` del Pod que acaba de nacer. La `10.244.1.2` del Pod borrado no aparece. Nadie la quitó a mano.
- `Session Affinity: None`: cada conexión puede ir a cualquier réplica; 3.8 lo mide.

Esa lista de `Endpoints` es la respuesta a la escena: el cliente usa `10.96.144.175`, que no cambia, y el clúster mantiene al día a quién le corresponde de verdad.

### 3.3 Los tres puertos

En la escena de Docker había un puerto que importaba: el `-p 8080:8080` de `docker run`. Aquí hay tres, y cada uno lo declara un objeto distinto. Confundirlos es de los errores más comunes al empezar, así que vale la pena seguirlos con el clúster delante.

```text
$ kubectl get service revisor -o jsonpath='port={.spec.ports[0].port} targetPort={.spec.ports[0].targetPort}{"\n"}'
port=80 targetPort=http

$ kubectl get pods -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].ports[0].name}={.spec.containers[0].ports[0].containerPort}{"\n"}{end}'
revisor-697fb84f97-drv5h http=8080
revisor-697fb84f97-nq74v http=8080
revisor-697fb84f97-z79jh http=8080

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].ports}{"\n"}'
[{"name":"http","port":8080,"protocol":"TCP"}]
```

(El segundo `jsonpath` usa `{range .items[*]}…{end}`, que repite lo de en medio para cada Pod de la lista. Es la forma de pedir un dato de varios objetos a la vez.)

Así se lee la cadena, del cliente al programa:

| Puerto | Dónde se declara | Valor en el `revisor` | Quién lo usa |
|---|---|---|---|
| `port` | el Service | `80` | el cliente: `http://revisor/…` va al 80, el puerto por omisión de HTTP |
| `targetPort` | el Service | `http` (un nombre) | el clúster, para saber a qué puerto del Pod reenviar |
| `containerPort` | la plantilla del Pod, con su nombre | `http` = `8080` | quien busca el nombre `http` en el Pod; el programa escucha en el 8080 por su cuenta |

El tercer comando muestra cómo se resolvió el nombre: el `EndpointSlice` (3.4) ya trae el número, `8080`, que sacó de los Pods. La documentación de Services describe las dos piezas que hacen esto posible. La primera: «un Service puede mapear cualquier `port` de entrada a un `targetPort`. Por omisión, y por comodidad, el `targetPort` vale lo mismo que el campo `port`». La segunda: «las definiciones de puertos de los Pods tienen nombres, y puedes referirte a esos nombres en el atributo `targetPort` de un Service».

¿Por qué el curso usa el nombre y no el número? Porque así el número vive en **un solo lugar**, la plantilla del Pod. Si un día el `revisor` escucha en otro puerto, cambias `containerPort` en el Deployment y el Service sigue funcionando sin tocarlo. Con `targetPort: 8080`, tendrías que acordarte de cambiar dos archivos, y el día que se te olvide uno, el Service manda tráfico a un puerto donde nadie escucha. El Ejercicio 1 te enseña exactamente cómo se ve eso.

Una aclaración que evita una confusión frecuente: la Lección 2 dijo que `containerPort` **no publica nada**. Sigue siendo cierto. El programa escucha en el 8080 aunque no lo declares. Declararlo con nombre sirve para que el Service pueda apuntarle por ese nombre, y para que quien lea el manifiesto sepa dónde escucha.

¿Y el 80 del Service? No lo abre el `revisor` ni ningún otro proceso: es parte de la dirección virtual del Service. El programa sigue escuchando en su 8080, con todas las restricciones de la Lección 2, y el clúster traduce. Así los clientes escriben `http://revisor/` sin número, y nadie tuvo que cambiar el puerto del programa para lograrlo.

### 3.4 Selectores y `EndpointSlice`

#### 3.4.1 Dónde queda escrita la lista

La lista de `Endpoints` que mostró `describe` no está guardada en el Service. Vive en otro objeto, un **EndpointSlice**. La [documentación de EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) lo resume: «los EndpointSlices llevan la cuenta de las direcciones IP de los *endpoints* de un *backend*. Normalmente están asociados a un Service, y los *endpoints* suelen ser Pods».

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.2.3,10.244.1.3   3s
```

Fíjate en cómo se buscó: no por nombre (`revisor-6jh2f` lleva un sufijo al azar, como un Pod), sino por la etiqueta `kubernetes.io/service-name=revisor`. La misma página explica por qué existe esa etiqueta: cada EndpointSlice lleva una referencia a su dueño y «una etiqueta `kubernetes.io/service-name` que permite buscar fácilmente todos los EndpointSlices que pertenecen a un Service». Es la misma idea de la Lección 2: se busca por etiqueta, nunca por un nombre que cambia.

¿Por qué «todos»? Porque un Service puede tener varios. La documentación dice que, por omisión, el plano de control crea EndpointSlices «de no más de 100 *endpoints* cada uno». Con tres réplicas cabe todo en uno; con trescientas habría al menos tres. Por eso la tabla de arriba es una lista, aunque hoy tenga un solo renglón.

Con `jsonpath` se ve cada *endpoint* por dentro, y su dueño:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.2.3 revisor-697fb84f97-drv5h curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{"\n"}'
Service/revisor
```

Cada renglón dice qué dirección, de qué Pod (`targetRef`), en qué nodo y si está listo. Y el dueño del EndpointSlice es el Service, con el mismo campo `ownerReferences` de la Lección 2. Es la misma cadena de dueños: si borras el Service, se va su EndpointSlice.

#### 3.4.2 Quién la escribe

Nadie la escribe a mano. La documentación de depuración de Services lo cuenta así: «dentro de Kubernetes hay un bucle de control que evalúa el selector de cada Service y guarda el resultado en uno o más objetos EndpointSlice» ([«Debug Services»](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)). Es el termostato de la Lección 0 otra vez, con otro estado deseado: «este Service manda tráfico a los Pods que coinciden con su selector». Cuando el conjunto de Pods cambia, el controlador corrige la lista.

Se ve borrando otro Pod:

```text
$ kubectl delete pod revisor-697fb84f97-drv5h
pod "revisor-697fb84f97-drv5h" deleted from default namespace

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true
10.244.1.4 revisor-697fb84f97-mjbff curso-k8s-l3-worker2 ready=true
```

El Pod `drv5h` y su `10.244.2.3` salieron de la lista, y entró el Pod nuevo, `mjbff`, con `10.244.1.4`. Mismo EndpointSlice, contenido nuevo. El Service no cambió en nada: su IP sigue siendo `10.96.144.175`. Esa es toda la idea.

#### 3.4.3 Qué significa `ready=true`

La columna `ready` es la que decide si un *endpoint* recibe tráfico. La documentación de EndpointSlices dice que la condición `serving` indica que el *endpoint* está atendiendo y que, para un Pod, «corresponde a la condición `Ready` del Pod»; y que `ready` es, en esencia, «`serving` y no `terminating`». Traducido: un Pod recibe tráfico mientras esté listo y no se esté apagando.

Hoy, «listo» quiere decir poco: el `revisor` no tiene sondas, así que su Pod se marca listo en cuanto el contenedor arranca, aunque el programa todavía no escuche. Por eso es la Lección 5 la que completa esta columna: con una sonda de disponibilidad, el Pod solo se marca listo cuando `/salud` responde, y el Service deja de mandarle tráfico si deja de responder.

#### 3.4.4 `Endpoints`, la API vieja

Vas a encontrar en tutoriales el comando `kubectl get endpoints`. Todavía funciona, pero mira lo que dice:

```text
$ kubectl get endpoints revisor
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS                                         AGE
revisor   10.244.1.3:8080,10.244.1.4:8080,10.244.2.2:8080   6s
```

`Endpoints` es la API anterior, y el propio servidor te avisa: «obsoleta desde la v1.33; usa EndpointSlice». La documentación de Services la marca igual («Deprecated since Kubernetes v1.33») y da las razones: no sirve para clústeres con IPv4 e IPv6 a la vez, no trae la información que piden funciones nuevas, y «trunca la lista de *endpoints* si es demasiado larga para caber en un solo objeto». Este curso usa EndpointSlice. `Endpoints` está obsoleta, no retirada: sigue funcionando, como acabas de ver, pero ya no es la API que se recomienda. Se nombra aquí para que la reconozcas cuando la veas, que es la regla del curso para lo obsoleto y lo retirado: se nombra para reconocerlo, no se enseña.

### 3.5 Un Pod de depuración

#### 3.5.1 Por qué hace falta

Para probar el Service necesitas un cliente **dentro** del clúster, porque un `ClusterIP` solo es alcanzable desde ahí. El candidato obvio sería el propio `revisor`, pero en la Lección 2 viste que su imagen no tiene *shell* ni `curl`: `kubectl exec deployment/revisor -- sh` falla con `executable file not found in $PATH`. Eso es una defensa, y el curso no la va a quitar para depurar. La salida es otra: un Pod aparte, hecho para mirar, que se crea cuando hace falta y se borra al terminar.

Es un **programa**: `programas/03-services-dns/depurar.yaml`.

```yaml
# depurar.yaml — Lección 3: un Pod de depuración con curl, que se borra al terminar.
# Ya cumple el nivel «restricted» (Lección 7), para que sirva igual en el espacio
# de nombres revisor. La imagen va fijada por su huella.
apiVersion: v1
kind: Pod
metadata:
  name: depurar
  labels:
    app: depurar
    acceso-revisor: permitido
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: depurar
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

#### 3.5.2 Campo por campo

Es un Pod suelto, a propósito: en la Lección 2 aprendiste que un Pod sin dueño no renace, y aquí eso es justo lo que quieres. Cuando lo borres, se queda borrado. Lo demás:

- **La imagen** es `curlimages/curl`, una imagen pequeña con `curl` y las herramientas básicas de Alpine Linux (`sh`, `nslookup`, `cat`), que vienen de BusyBox. Va fijada por su huella `sha256`, no solo por su etiqueta `8.22.0`. Una etiqueta se puede mover a otra imagen en el registro; una huella no. Como esta imagen sí se descarga de internet, la huella identifica por su contenido el manifiesto de la imagen, así que tu clúster descargará las mismas capas que se probaron aquí aunque alguien mueva la etiqueta `8.22.0` en el registro.
- **`imagePullPolicy` no está escrito.** A diferencia del `revisor`, este manifiesto no lo declara: con una etiqueta que no es `:latest`, el valor por omisión es `IfNotPresent`, el mismo que la Lección 2 escribió a la vista. Aquí se deja el valor por omisión.
- **`command: ["sleep", "3600"]`** reemplaza el programa de la imagen, que sería un `curl` que termina enseguida, por una espera de una hora. Así el Pod se queda vivo y le puedes mandar comandos con `kubectl exec`. Con `restartPolicy: Never`, cuando pase la hora el Pod termina y no se reinicia.
- **El `securityContext`** es el mismo patrón del `revisor`, con el usuario 100 y el grupo 101, los que trae la imagen de curl. Que un Pod sea «solo para depurar» no es excusa para que corra como `root`: un Pod de depuración olvidado es justo el que alguien encuentra después.
- **`resources`** pone un piso y un techo de CPU y memoria. Se explican en la Lección 5; aquí están porque un Pod de apoyo no debe poder comerse el nodo.
- **`automountServiceAccountToken: false`** evita que se monte la credencial de la API que la Lección 2 encontró en el `revisor`. `curl` no la necesita. La Lección 7 lo generaliza.
- **La etiqueta `acceso-revisor: permitido`** no hace nada todavía. En la Lección 7, cuando la red se cierre, será la llave que deja a este Pod hablar con el `revisor`. Va desde hoy para que el mismo archivo sirva en las dos lecciones.

#### 3.5.3 Primer contacto

```text
$ kubectl apply -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -o wide
NAME      READY   STATUS    RESTARTS   AGE   IP           NODE                  NOMINATED NODE   READINESS GATES
depurar   1/1     Running   0          29s   10.244.2.4   curso-k8s-l3-worker   <none>           <none>

$ kubectl exec depurar -- id
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)

$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec depurar -- curl -s http://10.96.144.175/salud
{"estado":"vivo","version":"1.6.0"}
```

`id` confirma el usuario 100. Y las dos últimas peticiones son el corazón de la lección. La primera usa el **nombre** del Service, sin puerto (el 80 es el de HTTP por omisión) y sin saber nada de los Pods. La segunda usa la IP del Service. Las dos llegan a una réplica del `revisor`, que contesta su `/salud` con la versión `1.6.0`. Nadie escribió una IP de Pod en ningún lado. Que el nombre `revisor` se convirtiera en `10.96.144.175` es trabajo del DNS del clúster, y eso es lo que sigue.

### 3.6 El DNS del clúster

#### 3.6.1 Quién responde

Todo Pod sabe a quién preguntarle por nombres porque el `kubelet` le escribe un `/etc/resolv.conf` al crearlo:

```text
$ kubectl exec depurar -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

Tres renglones. El del medio dice a quién preguntar: `10.96.0.10`. Esa dirección está en la red de Services, y no es casualidad:

```text
$ kubectl get service -n kube-system kube-dns
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   74s

$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-cf8pv   1/1     Running   0          65s   10.244.0.2   curso-k8s-l3-control-plane   <none>           <none>
coredns-559f6c778d-h2hgl   1/1     Running   0          65s   10.244.0.4   curso-k8s-l3-control-plane   <none>           <none>
```

El DNS del clúster es, él mismo, **un Service con su selector**: `kube-dns`, en el espacio de nombres `kube-system`, puerto 53 (el de DNS), que manda las preguntas a los dos Pods de `coredns` que viste en la Lección 0. Exactamente el patrón que acabas de escribir para el `revisor`. Si mañana uno de los `coredns` se cae, su Service sigue en `10.96.0.10` y el otro contesta. Kubernetes usa sus propias piezas para resolver su propio problema.

(`-n kube-system` le dice a `kubectl` en qué espacio de nombres buscar. Hasta ahora todo ha vivido en `default`. Los espacios de nombres se estudian en la Lección 7.)

#### 3.6.2 El nombre completo de un Service

La [documentación de DNS para Services y Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) da la forma del nombre: un Service normal recibe un registro con un nombre de la forma `mi-servicio.mi-espacio.svc.dominio-del-cluster`, que «resuelve a la *cluster IP* del Service». Para el tuyo:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

Se lee de izquierda a derecha, de lo particular a lo general:

| Parte | Qué es |
|---|---|
| `revisor` | el nombre del Service |
| `default` | el espacio de nombres donde vive |
| `svc` | que es un Service (y no otra cosa) |
| `cluster.local` | el dominio del clúster, el de omisión |

Y la respuesta, `10.96.144.175`, es la IP del Service, la de 3.2. El DNS no te da las IP de los Pods: te da la dirección estable, y de repartir se encarga el Service.

#### 3.6.3 Por qué `revisor` a secas funciona

En 3.5 escribiste `http://revisor/salud`, no el nombre completo, y funcionó. Lo hace posible el primer renglón de `resolv.conf`, `search`. La documentación de DNS lo explica: las consultas «se pueden expandir usando el `/etc/resolv.conf` del Pod» y «los valores de la opción `search` se usan para expandir las consultas». Quien expande no es el Pod sino la biblioteca de DNS del programa que pregunta. Cuando `curl` pregunta por `revisor`, su biblioteca le agrega, uno por uno, los dominios de `search`: `revisor.default.svc.cluster.local`, `revisor.svc.cluster.local` y `revisor.cluster.local`, y se detiene en el primero que responde. Aquí el primero ya responde. En 3.6.4 verás que el `nslookup` de esta imagen no se detiene: los pregunta todos a la vez.

El tercer renglón, `options ndots:5`, decide **cuándo** se usa esa lista. La guía de depuración de Services lo dice así: la línea `options` «debe poner `ndots` lo bastante alto para que tu biblioteca de DNS considere las rutas de búsqueda», y Kubernetes lo pone en 5 por omisión, «lo bastante alto para cubrir todos los nombres que genera». En la práctica: un nombre con menos de cinco puntos se prueba primero con la lista `search`. `revisor` no tiene ninguno, así que se expande. Por eso también funciona la forma intermedia, con el espacio de nombres:

```text
$ kubectl exec depurar -- curl -s http://revisor.default/salud
{"estado":"vivo","version":"1.6.0"}
```

`revisor.default` más `svc.cluster.local`, el segundo elemento de `search`, da el nombre completo. La documentación lo pone como regla: las consultas que no dicen espacio de nombres «se limitan al espacio de nombres del Pod»; para llegar a un Service de otro espacio, se escribe el espacio en el nombre. Hoy todo vive en `default` y no se nota. Desde la Lección 7, cuando el `revisor` se mude a su propio espacio, `revisor.revisor` será la forma de alcanzarlo desde fuera de él.

#### 3.6.4 Los `NXDOMAIN` que no son un error

Ahora pregúntale a `nslookup` por el nombre corto:

```text
$ kubectl exec depurar -- nslookup revisor
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find revisor.cluster.local: NXDOMAIN

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175

** server can't find revisor.svc.cluster.local: NXDOMAIN


** server can't find revisor.cluster.local: NXDOMAIN

** server can't find revisor.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

Parece un desastre: cuatro «no encuentro» y un código de salida 1. Léelo despacio. En medio de ellos está la respuesta correcta: `revisor.default.svc.cluster.local` es `10.96.144.175`. Los cuatro `NXDOMAIN` (*non-existent domain*, «ese nombre no existe») son las **otras** expansiones de la lista `search`: `revisor.svc.cluster.local` y `revisor.cluster.local` no existen, y es verdad, no existen. Salen dos veces cada una porque el `nslookup` de esta imagen, el de BusyBox, pregunta por cada nombre dos cosas: su dirección IPv4 (registro `A`) y su dirección IPv6 (registro `AAAA`). Al nombre completo, que sí existe, también le preguntó las dos; como el Service no tiene dirección IPv6, esa segunda pregunta vuelve sin registros, y eso no se imprime como error (un nombre que existe pero no tiene ese tipo de registro es distinto de uno que no existe). Imprime cada fallo y, si hubo alguno, termina con código 1 aunque haya encontrado la respuesta. El orden de los renglones cambia de una corrida a otra, porque las preguntas salen a la vez: en otra corrida de esta misma lección, la respuesta salió al final, después de los cuatro `NXDOMAIN`.

`curl` no se queja de nada de esto porque solo le importa encontrar **una** dirección, y la encontró. La lección práctica: con `nslookup`, pregunta por el nombre completo; en esta imagen sale limpio, como viste en 3.6.2. Ojo con por qué: no es que la regla lo garantice. Con `ndots:5`, hasta `revisor.default.svc.cluster.local` (cuatro puntos) cuenta como «corto» para una biblioteca que respete la regla al pie de la letra, y es justo el costo conocido de `ndots:5`: consultas de más incluso con el nombre completo. Que salga limpio es el comportamiento medido de este `nslookup`. Para que un nombre sea absoluto y no se expanda nunca, termínalo en punto: `revisor.default.svc.cluster.local.` Y si ves `NXDOMAIN` con el nombre corto, busca el renglón `Name:` antes de alarmarte.

Para comparar, así se ve un nombre que de verdad no existe:

```text
$ kubectl exec depurar -- nslookup no-existe.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

Sin renglón `Name:` y sin `Address:` al final. Esa ausencia es la diferencia, no los `NXDOMAIN`.

### 3.7 El servicio de prueba: el `revisor` por fin revisa a alguien

Desde la Lección 2, el `revisor` tiene escrito en su manifiesto `REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s`. Esa línea ya era una promesa sobre esta lección: le pide que revise un servicio llamado `prueba` en `http://prueba:9000/`, con 2 segundos de límite. Esa URL usa un **nombre**, no una IP. Mira qué pasa hoy, antes de que ese nombre exista:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        4ms  no responde: Get "http://prueba:9000/": dial tcp: lookup prueba on 10.96.0.10:53: no such host
```

El `revisor` hace bien su trabajo: dice que `prueba` falla, y por qué. `lookup prueba on 10.96.0.10:53: no such host`: le preguntó al DNS del clúster (la `10.96.0.10` de 3.6) por `prueba` y el DNS respondió que no existe. No hay Pod, no hay Service, no hay nombre.

Estos son los dos manifiestos del servicio de prueba. Los dos son **programas**: `prueba-deployment.yaml` y `prueba-service.yaml`.

```yaml
# prueba-deployment.yaml — Lección 3: el servicio que falla a propósito.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prueba
  labels:
    app: prueba
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prueba
  template:
    metadata:
      labels:
        app: prueba
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: prueba
        image: curso-docker-prueba:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 9000
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

```yaml
# prueba-service.yaml — Lección 3: el nombre «prueba» que el revisor consulta.
apiVersion: v1
kind: Service
metadata:
  name: prueba
  labels:
    app: prueba
spec:
  type: ClusterIP
  selector:
    app: prueba
  ports:
  - name: http
    port: 9000
    targetPort: http
```

El Deployment es el patrón de la Lección 2, con el mismo `securityContext` y **una** réplica: es un servicio de prueba, no hace falta más. No lleva volumen, porque no escribe nada en disco. El Service tiene una diferencia con el del `revisor` que vale la pena notar: aquí `port` es `9000`, igual que el del contenedor, porque así lo pide la URL que el `revisor` ya tiene escrita (`http://prueba:9000/`). El `targetPort` sigue siendo por nombre. La regla no es «el Service siempre en el 80»: el puerto del Service es el que tus clientes esperan.

```text
$ kubectl apply -f prueba-deployment.yaml -f prueba-service.yaml
deployment.apps/prueba created
service/prueba created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP    79s
prueba       ClusterIP   10.96.236.7     <none>        9000/TCP   3s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP     40s

$ kubectl exec depurar -- curl -s http://prueba:9000/modo
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

`OK`, en 1 milisegundo, con código `200`. No se reinició el `revisor`, no se cambió su configuración, no se le dio ninguna IP. Su manifiesto decía `prueba` desde el principio; lo único que cambió es que ahora ese nombre existe. Cada vez que el `revisor` arma su reporte, vuelve a preguntar por el nombre. Esto es lo que la escena del martes necesitaba: la configuración dice **a quién**, no **dónde está**.

Ahora se rompe a propósito, en sus tres modos:

```text
$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  codigo 503

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/lento
modo: lento

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

Cada modo cuenta algo distinto. En `caido`, `prueba` contesta, pero con `503`: el `revisor` dice `FALLA codigo 503`. En `lento`, `prueba` tarda más que los 2 segundos que le da la lista, y el `revisor` se rinde a los `2.002s` con `se acabo el tiempo de espera`. (El estado `LENTO` del `revisor` es para un servicio que responde bien pero tarda más de 1 segundo **sin** pasarse del límite; aquí se pasó.) Y en `sano`, todo vuelve a `OK`. Los tres casos pasaron por el Service y por el DNS del clúster, y el `revisor` los distinguió.

Con esto, el `revisor` hace dentro del clúster lo mismo que hacía en Compose en el curso de Docker. La tabla de traducción de la Lección 0 lo anticipaba: el nombre del servicio en la red de Compose se vuelve el DNS del clúster.

### 3.8 Cómo reparte un Service

#### 3.8.1 Medirlo

El Service tiene tres réplicas detrás. ¿Las usa a las tres? Se mide con treinta peticiones y la bitácora del `revisor`, que escribe una línea por cada petición que atiende:

```text
$ kubectl exec depurar -- sh -c 'for i in $(seq 1 30); do curl -s -o /dev/null http://revisor/salud; done; echo 30 peticiones'
30 peticiones

$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /salud' | cut -d' ' -f1 | sort | uniq -c
   6 [pod/revisor-697fb84f97-mjbff/revisor]
  13 [pod/revisor-697fb84f97-nq74v/revisor]
  14 [pod/revisor-697fb84f97-z79jh/revisor]
```

El segundo comando junta varias herramientas, y vale la pena desarmarlo:

- `kubectl logs -l app=revisor` pide la bitácora de **todos** los Pods con esa etiqueta, no de uno;
- `--prefix` antepone a cada renglón el Pod de donde salió;
- `--tail=-1` pide la bitácora completa (con selector de etiqueta, `kubectl logs` muestra por omisión solo los últimos renglones de cada Pod);
- `grep` se queda con las líneas de `/salud`, `cut` con el prefijo, y `sort | uniq -c` cuenta cuántas hay de cada Pod.

Las tres réplicas recibieron tráfico. Suman 33 y no 30 porque las tres peticiones a `/salud` de 3.5 y 3.6 también están en la bitácora. Y el reparto no es parejo: 14, 13 y 6. No tiene por qué serlo.

#### 3.8.2 Quién hace el trabajo

La IP de un Service no la tiene ninguna máquina. La [referencia de IP virtuales](https://kubernetes.io/docs/reference/networking/virtual-ips/) dice quién la hace funcionar: «el componente `kube-proxy` es responsable de implementar un mecanismo de IP virtual para los Services». `kube-proxy` corre en cada nodo (los tres que viste en la Lección 1), lee los EndpointSlices y escribe reglas en la red del nodo. Cuando un paquete sale hacia `10.96.144.175:80`, esas reglas lo desvían a la IP y al puerto de un Pod real, por ejemplo `10.244.1.4:8080`.

¿Cómo elige el Pod? La misma referencia dice que el modo por omisión en Linux, para Kubernetes 1.37, es `iptables`, y que en ese modo las reglas, «por omisión, eligen un Pod de *backend* al azar». Al azar, no por turnos. En treinta tiradas, un reparto de 14, 13 y 6 es perfectamente posible. Con muchas más peticiones, cada réplica se acercaría a un tercio. Y el `Session Affinity: None` de `describe` es lo que permite ese azar: la referencia explica que, si quieres que un mismo cliente vaya siempre al mismo Pod, puedes poner `sessionAffinity: ClientIP`, y que el valor por omisión es `None`. El `revisor` no guarda nada entre peticiones, así que no lo necesita.

Esto tiene una consecuencia que conviene saber desde ya: el Service reparte **conexiones**, no peticiones. Cada `curl` del ciclo abre una conexión nueva, y por eso cada uno cae donde le toca. Un cliente que reutiliza una sola conexión para muchas peticiones le habla siempre al mismo Pod mientras esa conexión viva.

### 3.9 `port-forward`: un túnel desde tu máquina

Todo lo anterior pasó **dentro** del clúster. ¿Y tú, desde tu terminal? La IP `10.96.144.175` no sirve fuera del clúster (la sección del hábito de seguridad lo comprueba). Para probar desde tu máquina sin publicar nada existe `kubectl port-forward`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &
Forwarding from 127.0.0.1:18080 -> 8080

$ curl -s http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s 'http://127.0.0.1:18080/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK            0s  200
```

Se lee así: escucha en el puerto `18080` de tu máquina, solo en la dirección `127.0.0.1`, y reenvía lo que llegue al puerto `80` del Service `revisor`. El `&` final lo deja corriendo en segundo plano, para que puedas usar la misma terminal. Mientras corra, cada vez que le hagas una petición `kubectl` imprimirá `Handling connection for 18080` en esa terminal: es normal. Lo cortas con `kill %1` o trayéndolo al frente con `fg` y `Ctrl+C`. Si prefieres dejarlo en una terminal aparte, recuerda lo de 3.1: en esa terminal nueva, primero el mismo `export KUBECONFIG=…` y `kubectl config current-context`, que debe decir `kind-curso-k8s-l3`.

Lee bien su primera línea: `Forwarding from 127.0.0.1:18080 -> 8080`. No dice `-> 80`. `kubectl` tradujo el `80` del Service a su `targetPort` y este al `8080` del Pod, y abrió el túnel **directo a un Pod**. La [referencia de `kubectl port-forward`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/) lo dice desde su primera frase: «reenvía uno o más puertos locales a un Pod». Y agrega: cuando le das un recurso como un Deployment o un Service, `kubectl` elige un Pod; «si hay varios Pods que coinciden, se elige uno automáticamente. La sesión de reenvío termina cuando el Pod elegido termina, y hay que volver a correr el comando». O sea: `port-forward service/revisor` **no** reparte como el Service. Usa el Service solo para encontrar un Pod. El Ejercicio 3 te muestra qué pasa cuando ese Pod se va.

¿Y `--address 127.0.0.1`? La referencia dice que el valor por omisión de `--address` es `localhost`, con el que `kubectl` intenta escuchar en `127.0.0.1` y en `::1` (la dirección de tu propia máquina en IPv6). El curso escribe `127.0.0.1`: una sola dirección, a la vista, por la misma razón por la que escribe `type: ClusterIP`. La decisión de no abrir el túnel a la red queda escrita, y nadie tiene que saberse el valor por omisión. La misma referencia trae, entre sus ejemplos, `--address 0.0.0.0`, que escucha «en todas las direcciones». Eso convertiría tu laptop en una puerta hacia ese Pod para cualquiera en tu red, sin contraseña y con tus credenciales del clúster detrás. Se comprueba qué abrió el túnel:

```text
$ lsof -nP -iTCP:18080 -sTCP:LISTEN | awk '{print $1, $8, $9, $10}'
COMMAND NODE NAME 
kubectl TCP 127.0.0.1:18080 (LISTEN)
```

Un solo proceso, `kubectl`, escuchando en `127.0.0.1:18080` y en ningún otro lado. (`lsof` lista quién tiene abierto un puerto; `awk` se queda con cuatro columnas para que quepa. En Linux Mint funciona igual; también puedes usar `ss -ltnp | grep 18080`.)

Un `port-forward` es para probar, no para servir. Vive mientras viva tu comando y tu sesión, depende de tus credenciales del clúster y se rompe cuando el Pod que eligió se va. Publicar el `revisor` de verdad, por una puerta con nombre, es la Lección 6.

## El error que vas a ver

El error de esta lección es de los más comunes con Services, y la propia guía de depuración lo menciona como tal: un Service cuyo selector no selecciona a nadie. Se provoca con `fig03_01.selector-malo.yaml`, un **programa** que falla a propósito: el mismo Service del `revisor`, con una letra de menos.

```yaml
# fig03_01.selector-malo.yaml — FALLA A PROPÓSITO: el mismo Service del revisor
# con una letra de menos en el selector (revisr). Se aplica encima del bueno, el
# Service se queda sin a quién mandar tráfico y curl sale con código 7. Se
# corrige volviendo a aplicar revisor-service.yaml.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisr
  ports:
  - name: http
    port: 80
    targetPort: http
```

Antes de aplicarlo, `kubectl config current-context` debe decir `kind-curso-k8s-l3`.

```text
$ kubectl apply -f fig03_01.selector-malo.yaml
service/revisor configured
```

`configured`: el `kube-apiserver` aceptó el cambio sin quejarse, y tiene razón. Un selector `app: revisr` es perfectamente válido; simplemente no coincide con nada. Kubernetes no puede saber que querías escribir `revisor`.

**Dale al clúster un momento.** Antes de probar, mira que el EndpointSlice ya esté vacío: `kubectl get endpointslices -l kubernetes.io/service-name=revisor` debe decir `<unset>` en la columna `ENDPOINTS`. Si pruebas en el mismo segundo del `apply`, `kube-proxy` todavía no se entera del cambio, el `curl` responde como si nada y vas a creer que el error «no salió». El guion hace justo eso: espera a que la lista se vacíe y solo entonces prueba. Después, se lee en orden, como en la Lección 2.

**Primero, el síntoma.** Desde el Pod de depuración, pidiéndole a `curl` que diga cuánto tardó:

```text
$ kubectl exec depurar -- curl -s -m 3 -o /dev/null -w 'tardó %{time_total} s\n' http://revisor/salud
tardó 0.001120 s
command terminated with exit code 7
[código de salida: 7]
```

(`-o /dev/null` tira la respuesta, que aquí no hay, y `-w` le pide a `curl` que escriba al final el tiempo total de la petición.) `-m 3` le pone un límite de 3 segundos, para que no espere sin fin; no hizo falta: tardó una milésima de segundo. El código 7 es, según la [lista de errores de curl](https://curl.se/libcurl/c/libcurl-errors.html), «no se pudo conectar con el *host*» (*Failed to connect() to host or proxy*). No es el 6, «no se pudo resolver el *host*»: el nombre sí se resolvió. Y no es el 28, «se acabó el tiempo»: la conexión no se quedó esperando, alguien la rechazó de inmediato. Esa distinción ya te dice dónde mirar.

**Segundo, el DNS.** Si el nombre se resolvió, el DNS no es el problema. Se comprueba:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

El nombre sigue existiendo y sigue dando la misma IP. El Service está ahí. Lo que no hay es nadie detrás.

**Tercero, los *endpoints*.** Este es el paso decisivo:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS     ENDPOINTS   AGE
revisor-6jh2f   IPv4          <unset>   <unset>     51s

$ kubectl describe service revisor | grep -E '^(Selector|Endpoints):'
Selector:                 app=revisr
Endpoints:                
```

`ENDPOINTS <unset>`: el EndpointSlice sigue existiendo, pero vacío, sin direcciones y sin puertos. `describe` lo confirma con un `Endpoints:` en blanco y, un renglón arriba, enseña la causa: `Selector: app=revisr`. La guía de depuración de Services lo dice casi con estas palabras: si la lista de *endpoints* está vacía, «revisa que el campo `spec.selector` de tu Service de verdad seleccione los valores de `metadata.labels` de tus Pods. Un error común es tener una errata».

**Cuarto, el selector contra las etiquetas.** Se comprueba con el mismo selector, que es justo la herramienta de la Lección 2:

```text
$ kubectl get pods -l app=revisr
No resources found in default namespace.

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-mjbff   1/1     Running   0          48s
revisor-697fb84f97-nq74v   1/1     Running   0          53s
revisor-697fb84f97-z79jh   1/1     Running   0          52s
```

Cero Pods con `app=revisr`, tres con `app=revisor`, los tres `Running`. Los Pods están perfectos. El Service busca a otros.

**Por qué el código 7 y no un tiempo de espera.** Con la lista vacía, `kube-proxy` no tiene a dónde mandar la conexión. Lo medido es el código, 7, y el tiempo, una milésima de segundo: la conexión no esperó hasta el límite de 3 segundos, se rechazó en cuanto salió. (En el modo `iptables`, `kube-proxy` pone una regla de rechazo para los Services sin *endpoints*. Es el comportamiento observado en esta corrida, no algo que la documentación prometa.) Es la misma señal del Ejercicio 1, por una causa distinta: ahí el Service sí tiene a quién mandar tráfico, pero al puerto equivocado. Lo que separa un caso del otro es la columna `ENDPOINTS`.

**La corrección** es la causa, no el Pod: volver a aplicar el archivo bueno.

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   53s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

Las tres direcciones volvieron al mismo EndpointSlice (`revisor-6jh2f`, cuya edad siguió contando: no se borró ni se creó otro), y el `revisor` contesta. Fíjate en el orden de la corrección: el guion esperó a ver las tres direcciones en el EndpointSlice antes de probar con `curl`. Es el mismo aviso del principio, al revés: entre que aplicas el Service corregido y que cada `kube-proxy` actualiza sus reglas pasa un momento, y una prueba hecha justo en ese instante puede fallar todavía aunque el arreglo ya esté hecho. Primero se mira que la lista esté llena; después se prueba.

**El orden, para cualquier Service que no responde:**

1. ¿Qué código da `curl`? El 6 es el nombre, el 7 es rechazo y el 28 es silencio.
2. ¿Resuelve el nombre completo?
3. ¿Tiene direcciones su EndpointSlice?
4. Si no tiene, ¿coincide su `Selector` con las etiquetas de los Pods (`get pods -l …`)?
5. Si tiene, ¿el puerto de la columna `PORTS` es donde el programa escucha?

## El hábito de seguridad de la lección: nada se publica porque sí

La tabla de hábitos del curso le asigna a esta lección tres cosas: por defecto `ClusterIP`; nada se publica porque sí; `port-forward` solo hacia `127.0.0.1`. Se comprueban las tres con el clúster delante.

**Un `ClusterIP` no se ve desde tu máquina.** Desde tu terminal, fuera del clúster, la misma IP que el Pod de depuración usó sin problema:

```text
$ curl -s -m 3 http://10.96.144.175/salud
[código de salida: 28]
```

Código 28: «se acabó el tiempo de espera». Tu máquina no tiene una ruta propia hacia `10.96.0.0/16`: el paquete sale por tu ruta por omisión, hacia tu módem o la red de tu oficina, que no saben nada del clúster, y nadie contesta. (Si tu red usa direcciones `10.96.x.x`, podrías obtener otra respuesta, de una máquina que no tiene nada que ver con el clúster; con más razón, esa IP no es tuya fuera de él.) La `10.96.144.175` solo tiene sentido en las reglas que `kube-proxy` escribe **dentro** de los nodos.

**Los nodos no publican nada del `revisor`.** Cada nodo de kind es un contenedor de Docker, y Docker dice qué puertos publica cada uno:

```text
$ docker port curso-k8s-l3-control-plane
6443/tcp -> 127.0.0.1:59190

$ docker port curso-k8s-l3-worker

$ docker port curso-k8s-l3-worker2
```

El nodo de control publica un solo puerto, el `6443` del `kube-apiserver`, y solo hacia `127.0.0.1` (el número de tu lado lo elige kind al azar; en tu máquina será otro). Es la puerta por la que habla tu `kubectl`, y la Lección 1 la vio. Los dos nodos de trabajo, donde corre el `revisor`, no publican **nada**: sus renglones salen vacíos. No hay ningún camino desde tu red hacia el puerto 8080 del `revisor`. Así debe ser hasta la Lección 6, que abre una puerta con nombre y dice qué cruza por ella.

**El túnel solo escucha en tu máquina.** Ya lo viste en 3.9: `kubectl` escuchando en `127.0.0.1:18080` y en ningún otro lado.

Por qué importa: cada camino abierto hacia un servicio es un camino que alguien puede usar. En un clúster real, el reflejo de «lo cambio a `NodePort` para probar» o «le pongo `--address 0.0.0.0` para que mi compañero lo vea» deja abierto lo que nadie recuerda cerrar. La regla del curso es la inversa: todo nace cerrado, cada apertura es una decisión escrita en un manifiesto y tiene su lección.

**Lo que defiende y lo que no.** Un `ClusterIP` impide que el `revisor` se alcance desde **fuera** del clúster. No impide nada **dentro**: cualquier Pod de cualquier espacio de nombres puede hablarle, como lo hizo `depurar`, que no tiene nada que ver con el `revisor`. Tampoco cifra el tráfico entre Pods: va en HTTP plano por la red de Pods. Cerrar quién le habla a quién es trabajo de las `NetworkPolicy` de la Lección 7. Lo del cifrado se discute en la Lección 6.

## Lo que se hace mal

**Guardar la IP de un Pod en la configuración.** Es la escena del martes. Funciona hasta que el Pod renace. Siempre el nombre del Service.

**Guardar la IP del Service en vez de su nombre.** Es estable mientras el Service exista, pero si lo borras y lo vuelves a crear recibe otra. El nombre sobrevive a eso; la IP no.

**Escribir `targetPort` como número cuando el contenedor tiene nombre.** Funciona hoy y obliga a mantener el mismo número en dos archivos. El día que cambie uno, el Service manda tráfico a un puerto donde nadie escucha (Ejercicio 1).

**Cambiar a `NodePort` o `LoadBalancer` «para probar».** Para probar está `port-forward`, que no abre nada a la red. Publicar es una decisión de la Lección 6, no un atajo.

**Abrir `port-forward` con `--address 0.0.0.0`.** Expone el puerto de ese Pod a cualquiera que alcance tu máquina, sin contraseña, usando tus credenciales del clúster, mientras el comando viva.

**Usar `port-forward` como si fuera un Service.** Le habla a **un** Pod, no reparte y se cae cuando ese Pod se va (Ejercicio 3). Sirve para mirar, no para servir.

**Abrir otra terminal y olvidar el `export KUBECONFIG`.** En la terminal nueva, `kubectl` le habla al clúster que diga tu `~/.kube/config`, que puede ser cualquier otro. Primero el `export`, después `kubectl config current-context`, y solo entonces el comando.

**Alarmarse con los `NXDOMAIN` de `nslookup`.** Con el nombre corto, son las expansiones de `search` que no existen. Busca el renglón `Name:`, o pregunta por el nombre completo.

**Darle a un Pod suelto las etiquetas del selector de un Service.** El Deployment no lo adopta, pero el Service sí lo usa, y le manda tráfico (Ejercicio 2).

**Probar justo después de cambiar el Service y sacar conclusiones.** Tanto al romperlo como al corregirlo: primero la columna `ENDPOINTS`; después, `curl`.

**Quitarle el `securityContext` al Pod de depuración «porque es temporal».** Lo temporal se olvida, y un Pod `root` olvidado es una puerta. El de este curso ya cumple el nivel `restricted`.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden y desde el estado en que quedó después de corregir el error. Antes de cada ejercicio, `kubectl config current-context` debe decir `kind-curso-k8s-l3`; si dice otra cosa, no sigas. `correr.sh` los corre igual, y su salida está en `correr.salida.txt`. **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — Un `targetPort` donde nadie escucha

`fig03_02.puerto-malo.yaml` es el mismo Service del `revisor` con el selector bien y una sola diferencia: `targetPort: 8081`, un número, en lugar de `http`.

```yaml
# fig03_02.puerto-malo.yaml — Ejercicio 1: el selector está bien, pero el
# targetPort apunta a un número donde el revisor no escucha (8081 en lugar del
# 8080 que se llama «http»). Pregunta: ¿el Service tiene endpoints? ¿Responde?
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: 8081
```

Antes de aplicarlo, predice: ¿cuántas direcciones tendrá el EndpointSlice? ¿Qué dirá su columna `PORTS`? ¿Qué código dará `curl -s -m 3 http://revisor/salud` desde `depurar`? Después aplícalo, espera unos segundos a que la columna `PORTS` cambie (el guion espera cinco), comprueba, y explica en qué se parece y en qué se distingue este fallo del de «El error que vas a ver». Al terminar, vuelve a aplicar `revisor-service.yaml`.

### Ejercicio 2 — El Pod que se cuela en el Service

`fig03_03.colado.yaml` es el `revisor-extra` del Ejercicio 2 de la Lección 2: un Pod suelto, idéntico a las réplicas, **con** la etiqueta `app: revisor` y con su puerto llamado `http`. En la Lección 2 viste que el Deployment no lo adopta. Ahora hay un Service que elige por `app: revisor`.

Predice: ¿cuántas réplicas dice el Deployment? ¿Cuántas direcciones tiene el EndpointSlice del `revisor`? Si mandas 40 peticiones a `http://revisor/salud`, ¿cuántas le tocan a `revisor-extra`, más o menos? Aplícalo, compruébalo con `kubectl get deployment revisor`, con el `jsonpath` de 3.4 (dirección y `targetRef.name`) y con `kubectl logs revisor-extra | grep -c 'GET /salud'` después del ciclo de 3.8 con 40 peticiones. Después explica qué pasaría con ese Pod el día que cambies la imagen del Deployment. Al terminar, comprueba el contexto y bórralo: `kubectl delete pod revisor-extra`.

### Ejercicio 3 — El túnel y el *rollout*

Abre otra vez el `port-forward` de 3.9 y comprueba que `curl -s -m 3 http://127.0.0.1:18080/salud` responde. Predice: si ahora corres `kubectl rollout restart deployment/revisor` y esperas a que termine, ¿el mismo `curl` sigue respondiendo? Hazlo, y lee lo que escribió el `port-forward` en su terminal. Explica qué pasó con la frase de la referencia de `kubectl port-forward` que cita 3.9.

### Ejercicio 4 — Los cuatro `NXDOMAIN`

Una compañera corre `kubectl exec depurar -- nslookup revisor`, ve cuatro renglones `server can't find … NXDOMAIN` y el código de salida 1, y concluye que «el DNS del clúster está roto». En cinco frases como máximo, contéstale: de dónde salen esos nombres, por qué cada uno aparece dos veces, por qué el código es 1, cómo se reconoce en la misma salida que el nombre sí se resolvió, y qué comando le darías para comprobarlo sin ruido.

## Soluciones

### Solución 1

Medido en `correr.salida.txt`:

```text
$ kubectl apply -f fig03_02.puerto-malo.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8081    10.244.2.2,10.244.1.4,10.244.1.3   59s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 7
[código de salida: 7]
```

**Tres direcciones, puerto `8081`, y `curl` con código 7.** El selector está bien, así que el EndpointSlice tiene las tres réplicas. Pero su columna `PORTS` dice `8081`: con un número, el clúster no busca nada en el Pod, toma el número tal cual. La conexión llega a la IP correcta de un Pod real, a un puerto donde el `revisor` no escucha, y el Pod la rechaza: código 7, «no se pudo conectar».

Se parece al error de la lección en el síntoma: el mismo código 7. Se distingue en la columna `ENDPOINTS`: allá estaba en `<unset>` (no hay a quién), aquí está llena (hay a quién, por el puerto equivocado). Por eso el orden de diagnóstico mira primero las direcciones y después el puerto. La guía de depuración de Services lo pregunta tal cual: «¿el `targetPort` es correcto para tus Pods?». Y es el argumento a favor de `targetPort: http`: con el nombre, este error no se puede escribir sin cambiar también el Deployment.

Al volver a aplicar el bueno:

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   64s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

`PORTS 8080`: el nombre `http` se resolvió otra vez al puerto de los Pods.

### Solución 2

Medido en `correr.salida.txt`:

```text
$ kubectl apply -f fig03_03.colado.yaml
pod/revisor-extra created

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           69s

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v
10.244.1.4 revisor-697fb84f97-mjbff
10.244.1.3 revisor-697fb84f97-z79jh
10.244.2.6 revisor-extra

$ kubectl exec depurar -- sh -c 'for i in $(seq 1 40); do curl -s -o /dev/null http://revisor/salud; done; echo 40 peticiones'
40 peticiones

$ kubectl logs revisor-extra | grep -c 'GET /salud'
12

$ kubectl delete pod revisor-extra
pod "revisor-extra" deleted from default namespace
```

**El Deployment dice `3/3`, el Service tiene cuatro direcciones y a `revisor-extra` le tocaron 12 de 40.** El Deployment no lo cuenta, por lo que viste en la Lección 2: su ReplicaSet busca también `pod-template-hash`. El Service sí, porque busca solo `app: revisor`, y `revisor-extra` la lleva. Para el Service es una réplica más: aparece en su EndpointSlice y recibe su parte del tráfico al azar. Con cuatro *endpoints*, lo esperado son unas 10 de 40, y 12 está cerca. En tu corrida será otro número, y no importa cuál: lo que importa es que no es cero.

El día que cambies la imagen del Deployment, el *rollout* reemplaza las tres réplicas y `revisor-extra` se queda con la imagen vieja, porque no es de nadie. El Service le seguiría mandando su parte del tráfico, y parte de tus usuarios verían la versión anterior sin que ningún `kubectl get deployment` te lo avise. Es la advertencia de la Lección 2 sobre los selectores que se traslapan, ahora con tráfico de verdad.

### Solución 3

Medido en `correr.salida.txt`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &

$ curl -s -m 3 http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ curl -s -m 3 http://127.0.0.1:18080/salud
[código de salida: 52]
```

(La salida de `rollout status` está recortada: en `correr.salida.txt` cada renglón se repite varias veces, como en la Lección 2.) Y lo que escribió el `port-forward`:

```text
Forwarding from 127.0.0.1:18080 -> 8080
Handling connection for 18080
Handling connection for 18080
E1021 07:23:02.902759   47411 portforward.go:549] "An error occurred forwarding" err="error forwarding port 8080 to pod 0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb, uid : network namespace for sandbox \"0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb\" is closed" localPort=18080 remotePort=8080
error: lost connection to pod
```

**El `curl` después del *rollout* falla con 52**, que en la lista de errores de curl es «el servidor no devolvió nada». El túnel no iba al Service: iba a **un** Pod, elegido al abrirlo. `rollout restart` reemplazó los tres Pods, incluido ese. La siguiente conexión llegó al túnel, el túnel intentó reenviarla a un Pod cuya red ya estaba cerrada (`network namespace for sandbox … is closed`) y `kubectl` se rindió: `error: lost connection to pod`. Es exactamente lo que dice la referencia: «la sesión de reenvío termina cuando el Pod elegido termina, y hay que volver a correr el comando». El Service, mientras tanto, conservó su dirección y su selector para los clientes de dentro del clúster: el que se cayó fue tu túnel. Esta lección no midió si un cliente interno pierde alguna petición durante el *rollout*: el `revisor` todavía no tiene sondas de disponibilidad ni apagado ordenado, y eso llega en la Lección 5; la Lección 9 lo mide con carga de verdad. Por eso `port-forward` es para mirar, y por eso no sirve para publicar nada.

### Solución 4

Una respuesta posible: «Esos nombres son las otras expansiones de la lista `search` de `/etc/resolv.conf`: a `revisor` se le agrega cada dominio de la lista, y `revisor.svc.cluster.local` y `revisor.cluster.local` de verdad no existen. Cada uno sale dos veces porque el `nslookup` de BusyBox pregunta por la dirección IPv4 y por la IPv6 de cada nombre. Imprime cada fallo y termina con código 1 si hubo alguno, aunque haya encontrado la respuesta. La prueba de que sí se resolvió está en la misma salida: el renglón `Name: revisor.default.svc.cluster.local` con su `Address`. Para comprobarlo sin ruido: `kubectl exec depurar -- nslookup revisor.default.svc.cluster.local`, que en esta imagen sale limpio.»

## Borrar el clúster

Cuando termines los ejercicios, borra el clúster de la lección. No dejes nada vivo en la máquina. Si dejaste un `port-forward` abierto en otra terminal, córtalo antes con `Ctrl+C`.

```text
$ kind delete cluster --name curso-k8s-l3
Deleting cluster "curso-k8s-l3" ...
Deleted nodes: ["curso-k8s-l3-control-plane" "curso-k8s-l3-worker" "curso-k8s-l3-worker2"]

$ kind get clusters | grep -c curso-k8s-l3
0
```

El `--name` es obligatorio aquí también: sin él, kind borraría el clúster llamado `kind`, que puede ser de otra persona o de otro proyecto. Después, borra la carpeta temporal del `kubeconfig` (la que creó `mktemp`, con el prefijo `/tmp/curso-k8s-l3.`; ahí está la credencial de administrador del clúster) o cierra esa terminal. El clúster de la siguiente lección se crea de cero, igual que este.

## Cómo sé que lo logré

- [ ] Explicas, con la salida de 3.1 delante, por qué la IP de un Pod no sirve como dirección, y qué cambia cuando el cliente usa el nombre de un Service.
- [ ] Escribes de memoria un Service `ClusterIP` con `selector` y `ports`, y en el del `revisor` dices cuál es `port`, cuál `targetPort`, cuál `containerPort` y qué valor tiene cada uno.
- [ ] Encuentras el EndpointSlice de cualquier Service con `kubectl get endpointslices -l kubernetes.io/service-name=<nombre>` y dices, por sus direcciones, a qué Pods llega el tráfico.
- [ ] Explicas cada renglón del `/etc/resolv.conf` de un Pod y por qué `revisor`, `revisor.default` y `revisor.default.svc.cluster.local` llevan al mismo lugar.
- [ ] Ante un `curl` con código 7 contra un Service, revisas en orden el nombre, la columna `ENDPOINTS` y el puerto, y distingues un selector mal escrito de un `targetPort` mal escrito.
- [ ] Abres un `port-forward` que escucha solo en `127.0.0.1`, lo compruebas con `lsof` (o `ss` en Linux Mint) y dices por qué se cae con un *rollout*.
- [ ] Corres `programas/03-services-dns/correr.sh > /tmp/mi-corrida-l3.txt 2>&1` y comparas `/tmp/mi-corrida-l3.txt` contra `programas/03-services-dns/correr.salida.txt` (no redirijas a ese archivo: es la referencia) en lo que no cambia entre corridas: tres nodos `Ready` en `v1.37.0`; seis renglones `not yet present on node … loading...`; el Service `revisor` como `ClusterIP` en `80/TCP` con `EXTERNAL-IP <none>`; `TargetPort: http/TCP` y tres `Endpoints` en el `8080`; el EndpointSlice con `PORTS 8080`, tres direcciones y dueño `Service/revisor`; el aviso `v1 Endpoints is deprecated in v1.33+`; `uid=100(curl_user)`; `{"estado":"vivo","version":"1.6.0"}` por nombre y por IP; el `resolv.conf` con sus tres renglones; `kube-dns` en `10.96.0.10`; `lookup prueba … no such host` antes de crear el servicio de prueba, y después `OK … 200`, `FALLA … codigo 503` y `FALLA … se acabo el tiempo de espera`; las tres réplicas con alguna petición en 3.8; `Forwarding from 127.0.0.1:18080 -> 8080` y `kubectl TCP 127.0.0.1:18080 (LISTEN)`; el código 28 desde tu máquina; los dos nodos de trabajo sin puertos publicados; código 7 con el selector malo, en milésimas de segundo, y `<unset>` en su EndpointSlice; `PORTS 8081` y código 7 en el Ejercicio 1; cuatro direcciones con `revisor-extra` en el Ejercicio 2; el código 52 y `lost connection to pod` en el Ejercicio 3; `sin diferencias con los archivos`; y al final `0` clústeres `curso-k8s-l3` y la línea `la corrida completa tardó … s`. Las IP, los sufijos de los nombres, las edades, el puerto que publica el nodo de control, en qué nodo cae cada Pod, el orden de los renglones de `kind load` y de los de `nslookup`, el reparto exacto de peticiones, los tiempos y las veces que se repite cada renglón de `rollout status` cambian en cada corrida: se observan, no se comparan. Si usaste otro puerto con `PUERTO_LOCAL`, verás ese número en lugar del `18080`.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l3`.

## Resumen

Responde sin mirar la lección:

1. ¿Por qué no se debe guardar la IP de un Pod en la configuración de otro programa? ¿Qué cambió en el Pod de 3.1 además de la IP?
2. ¿Qué hace un Service de tipo `ClusterIP`, desde dónde se alcanza y por qué es el tipo por omisión que este curso escribe de todos modos?
3. En el Service del `revisor`, ¿qué es `port`, qué es `targetPort` y de dónde sale el `8080`? ¿Por qué `targetPort` va por nombre?
4. ¿Qué objeto guarda la lista de Pods de un Service, quién la escribe y con qué etiqueta lo encuentras?
5. ¿Qué es `kube-dns`, en qué IP está y por qué se parece tanto a tu Service?
6. ¿Qué tres renglones tiene el `/etc/resolv.conf` de un Pod y qué hace cada uno?
7. ¿Cómo elige `kube-proxy` a qué réplica manda una conexión, en el modo por omisión?
8. ¿Qué códigos de `curl` distinguen «no resolvió el nombre», «rechazó la conexión» y «no contestó a tiempo»?
9. ¿A cuántos Pods le habla `kubectl port-forward service/revisor`, y qué le pasa con un *rollout*?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Service»](https://kubernetes.io/docs/concepts/services-networking/service/): qué es un Service; el tipo `ClusterIP` como valor por omisión y alcanzable solo desde dentro del clúster; `targetPort` igual a `port` por omisión; los puertos con nombre; la *cluster IP*; la API `Endpoints`, obsoleta desde la v1.33, y por qué.
- [Kubernetes, «EndpointSlices»](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/): qué guarda un EndpointSlice; la etiqueta `kubernetes.io/service-name` y la referencia a su dueño; el tope de 100 *endpoints* por EndpointSlice; las condiciones `serving`, `terminating` y `ready`.
- [Kubernetes, «DNS for Services and Pods»](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): la forma del nombre de un Service; las consultas sin espacio de nombres limitadas al del Pod; el `/etc/resolv.conf` con `search` y `ndots:5`.
- [Kubernetes, «Debug Services»](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/): el bucle de control que llena los EndpointSlices; el selector con errata como error común; las preguntas sobre `targetPort`; y por qué `ndots` vale 5.
- [Kubernetes, «Virtual IPs and Service Proxies»](https://kubernetes.io/docs/reference/networking/virtual-ips/): `kube-proxy` como responsable de las IP virtuales; `iptables` como modo por omisión en Kubernetes 1.37 y la elección del Pod al azar; `sessionAffinity` y su valor por omisión `None`.
- [Kubernetes, «kubectl port-forward»](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/): que reenvía a un Pod; la elección automática de un Pod y el fin de la sesión cuando ese Pod termina; `--address` y su valor por omisión `localhost`; el ejemplo con `0.0.0.0`.
- [Kubernetes, «Pods»](https://kubernetes.io/docs/concepts/workloads/pods/): los Pods como entidades efímeras y desechables.
- [kind, «Configuration»](https://kind.sigs.k8s.io/docs/user/configuration/): las subredes por omisión de Pods (`10.244.0.0/16`) y de Services (`10.96.0.0/16`), y `kindnetd` como red por omisión.
- [kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind load docker-image` con `--name`.
- [curl, «libcurl error codes»](https://curl.se/libcurl/c/libcurl-errors.html): el significado de los códigos de salida 6, 7, 28 y 52.

---

**Siguiente:** [Lección 4 — Configuración y secretos](04-configuracion-secretos.md)
