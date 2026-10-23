# Lección 8 — Datos y tareas

Lunes, 7:12 de la mañana. A las 9:00 hay reunión con el proveedor del servicio de pagos, y tu jefa te escribe un mensaje de una línea: «Necesito el reporte del viernes a las 6 de la tarde, el que mostró a `prueba` caída cuarenta minutos. Es la prueba del reclamo». Abres el clúster con la tranquilidad de quien sabe que el `revisor` guarda su reporte en un archivo, `/datos/reporte.json`. Pides los Pods y ves algo que no esperabas: las tres réplicas tienen menos de dos días. El sábado, en el mantenimiento de la madrugada, alguien vació los nodos uno por uno para actualizarlos (con `kubectl drain`, que desaloja los Pods de un nodo) y el clúster hizo lo que sabe hacer: borró los Pods viejos y el Deployment creó Pods nuevos en otros nodos. Pides el archivo. No está. Buscas en las otras dos réplicas. Tampoco. Y aunque hubiera estado, te das cuenta de algo peor mientras lo piensas: el `revisor` guarda **el último** reporte y escribe encima del anterior. El del viernes se habría perdido de todos modos con la primera consulta del sábado.

Son las 7:20. Quedan cien minutos para encontrar una forma de decir «no lo tengo» que no suene a «no lo guardé».

No es un caso raro de mala suerte. Es lo que pasa cuando se confunde un contenedor con una caja fuerte. En 2017, el equipo de GitLab publicó el relato de las horas en que perdió datos de producción y descubrió que sus mecanismos de respaldo no estaban sirviendo cuando hicieron falta: las copias diarias fallaban en silencio y el cubo donde debían estar estaba vacío, las instantáneas de disco no estaban activadas en los servidores de la base de datos y la réplica estaba rota. Su informe (las fuentes lo citan, con la liga) es un buen recordatorio de que la pregunta no es «¿tengo respaldo?», sino «¿lo he probado?». Esta lección es más modesta: no construye respaldos. Te enseña la mitad anterior, la que casi todos descubren tarde: **qué parte de lo que escribe un Pod sobrevive al propio Pod, y qué parte no**. Con esa respuesta en la mano, el reporte del viernes deja de depender de la suerte: una tarea programada le pide el reporte al `revisor` y lo guarda, con la fecha en el nombre, en un volumen que sobrevive a los Pods (mientras exista la solicitud y el nodo donde vive el disco). Ya no es un renglón que se pisa: es un archivo con nombre y fecha.

La lección tiene dos mitades que se necesitan una a la otra. La primera es el **dónde**: volúmenes que viven más que los Pods. La segunda es el **cuándo**: tareas que corren una vez, o cada cinco minutos, sin que nadie las lance. Juntas resuelven la escena: una tarea programada le pide al `revisor` su reporte cada cinco minutos y lo guarda con la fecha en el nombre, en un volumen que sobrevive a los Pods.

**Tiempo:** 2 × 45 min

**Qué construyes:** el reporte guardado y el `revisor` como tarea programada: un volumen persistente que se llama `reportes`, una tarea (`Job`) que le pide al `revisor` su reporte con el token y lo escribe con la fecha en el nombre, y un `CronJob` que la repite cada cinco minutos, con una cuenta de servicio sin permisos ni credenciales montadas

**Qué aprendes:** qué sobrevive y qué no cuando se cae un contenedor y cuando se borra un Pod (`emptyDir`); `PersistentVolume`, `PersistentVolumeClaim` y `StorageClass`, y la clase de almacenamiento de kind; por qué la solicitud espera a su primer Pod; `Job` y `CronJob` con sus reintentos, su horario y su historial; el dueño de los archivos con `fsGroup`; qué se pierde al borrar la solicitud; y un tamaño pedido que el clúster no hace respetar

**De dónde vienes.** De la Lección 7: el `revisor` y el servicio de prueba viven en un espacio de nombres propio, `revisor`, que exige el nivel `restricted` de Pod Security Admission; cada carga tiene su cuenta de servicio sin credenciales montadas; y la red está cerrada por defecto, con aperturas nombradas: al `revisor` solo entran los Pods con la etiqueta `acceso-revisor: permitido` y los Envoy de la puerta. De la [Lección 4](04-configuracion-secretos.md), el token como `Secret` montado como archivo y los nombres con *hash* que pone Kustomize. De la [Lección 5](05-salud-recursos-apagado.md), `requests` y `limits` en todo contenedor; hoy los traen también las tareas. Y de la [Lección 6](06-entrar-al-cluster.md), la plataforma (MetalLB y Envoy Gateway) que esta lección vuelve a instalar al crear su clúster, porque el punto de partida incluye el Gateway.

**Qué no hace esta lección.** No pone el reporte del `revisor` dentro del volumen persistente: el Ejercicio 2 te deja intentarlo y ver por qué el curso no lo hace (ata todas las réplicas a un solo nodo). No instala un sistema de almacenamiento de red, ni enseña `StatefulSet`, ni toma instantáneas o respaldos de un volumen: los nombra al final de «El hábito de seguridad», con una frase sobre el problema que resuelve cada uno. No escala nada (eso es la [Lección 9](09-escalar-y-actualizar.md), que parte de lo que dejas aquí) ni evalúa el proyecto completo contra un clúster real (la [Lección 10](10-proyecto-final.md)).

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1 y la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l8`. La máquina fue una Mac con procesador ARM y Docker Engine dentro de una máquina virtual Linux (Colima), **no** Linux Mint, que es el sistema de referencia del curso. **La corrida usó una red de Docker propia**, `curso-k8s-red-l8`, con la subred `172.28.0.0/16`, porque la máquina era compartida y en ese momento corrían otras lecciones con MetalLB: dos clústeres con el mismo rango de IP en la misma red se pisan. Por eso las direcciones del Gateway salen aquí en `172.28.255.x`. **En tu máquina, con la red `kind` normal que Docker crea al levantar el primer clúster, las IP salen en `172.18.255.x`** (el rango de `infra/metallb-pool.yaml` es `172.18.255.200-172.18.255.220`), y no necesitas crear ninguna red. Eso supone que tu red `kind` tiene la subred `172.18.0.0/16`; compruébalo antes con `docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'` y, si es otra, ajusta el rango del archivo. Lo demás que cambia en tu Mint: la arquitectura (`amd64` en lugar de `arm64`), los sufijos al azar de los nombres de Pods y de Jobs, las edades, en qué nodo cae cada réplica, el *uid* de cada Pod, la hora y los nombres de los volúmenes (`pvc-` y un identificador). Los comandos son los mismos. El recorrido completo está en [`programas/08-datos-y-tareas/`](../programas/08-datos-y-tareas): `correr.sh` crea el clúster, le instala la plataforma, deja todo como lo dejó la Lección 7, recorre la lección en orden, corre los Ejercicios 1 a 3 y borra el clúster; su salida es `correr.salida.txt`. La corrida completa tardó 19 minutos y 17 segundos (los tres ensayos de `concurrencyPolicy` del Ejercicio 3 suman unos ocho minutos de esperas): crear el clúster y esperar a que estuviera listo tomó 42 segundos, instalar la plataforma tomó 175 (el guion no cronometra cada paso, así que no sé cuál de las esperas fue la larga) y borrar el clúster, 4. Estos tiempos varían mucho con la carga de la máquina: en otra corrida del mismo guion, con la máquina ocupada, instalar la plataforma tomó 678 segundos y el `kubectl wait` de Envoy Gateway llegó a agotar su plazo de 300 segundos, aunque el Gateway terminó funcionando. Las esperas largas de la lección (ver pasar el horario de un `CronJob`, ver cómo un `Job` agota sus reintentos) están escritas a la vista: el guion imprime cada cuántos segundos mira y qué ve, no las esconde. No usa ningún puerto de tu máquina.

## Al terminar vas a poder

- Demostrar con la corrida qué sobrevive y qué no en un `emptyDir`: el reinicio de un contenedor sí, el borrado del Pod no.
- Explicar con tus palabras qué son un `PersistentVolume`, una `PersistentVolumeClaim` y una `StorageClass`, y por qué la solicitud del curso se queda en `Pending` hasta que aparece el primer Pod que la usa.
- Leer el estado de una solicitud de volumen, su volumen y el directorio real que lo respalda en el nodo.
- Escribir un `Job`, decir cuántas veces reintenta y con qué esperas, y leer un `BackoffLimitExceeded`.
- Escribir un `CronJob`, leer su horario de cinco campos, y explicar `concurrencyPolicy`, el historial de tareas y por qué una tarea programada debe poder correr dos veces sin dañar nada.
- Provocar y arreglar un `Permission denied` en un volumen con `fsGroup`, y decir en cuál de los volúmenes de la lección `fsGroup` cambió el grupo y en cuál no, y por qué no puedes darlo por hecho.
- Decir qué pasa con los datos al borrar una solicitud de volumen según la política de reclamación, y por qué el borrado puede quedarse en `Terminating`.

## El porqué antes del cómo

Hasta hoy, todo lo que el `revisor` escribe vive en un lugar que el clúster trata como desechable. Lo viste de pasada en la Lección 2, cuando el Deployment montó un `emptyDir` en `/datos` para que el sistema de archivos de solo lectura no impidiera guardar el reporte, y lo has usado desde entonces sin preguntarte cuánto dura. La primera pregunta de la lección es esa: **¿cuánto dura lo que escribe un Pod?** La respuesta tiene dos escalones, porque un Pod no es lo mismo que un contenedor: el contenedor puede caerse y volver (el `kubelet` lo reinicia), y el Pod puede borrarse y ser reemplazado por otro con otro nombre en otro nodo. Lo que sobrevive a lo primero no tiene por qué sobrevivir a lo segundo, y lo medimos.

La segunda pregunta es **¿cómo se guarda algo de verdad?** Kubernetes separa dos papeles que en Docker venían juntos. Quien administra el clúster decide qué almacenamiento existe (discos, carpetas, servicios de red); quien despliega una aplicación decide cuánto necesita y de qué tipo. El puente entre los dos son tres objetos con nombres parecidos y trabajos distintos, que esta lección presenta uno por uno antes de usarlos.

La tercera es **¿cómo se hace algo que no es un servicio?** Un Deployment mantiene procesos que no deben terminar. Pedirle el reporte al `revisor` cada cinco minutos es lo contrario: un proceso que arranca, hace una cosa y termina, y que el clúster debe repetir en una hora fija sin que nadie se acuerde. Para eso existen el `Job` (hacer algo hasta que salga bien o hasta rendirse) y el `CronJob` (crear Jobs con un horario).

Y hay una cuarta pregunta, menos vistosa, que decide si lo de arriba funciona: **¿quién es el dueño de lo que se escribe?** Un volumen que nace con un dueño y un permiso, y un proceso que corre como otro usuario, son una receta para un `Permission denied`. `fsGroup`, la línea de la Lección 4 que dejó pendiente su historia completa, vuelve aquí.

La lección tiene ocho partes de conceptos y después las secciones de siempre:

1. **El clúster de la lección y su punto de partida** (8.1).
2. **Qué se pierde: el `emptyDir` de hoy** (8.2).
3. **Volúmenes, solicitudes y clases** (8.3).
4. **La solicitud de volumen y su espera** (8.4).
5. **`Job`: la tarea que termina** (8.5).
6. **`CronJob`: la tarea con horario** (8.6).
7. **El dueño de los archivos: `fsGroup`** (8.7).
8. **Borrar la solicitud: ahí sí se pierde** (8.8).

Este es el destino. Al final de 8.5, una tarea corrida a mano deja un archivo con fecha en el nombre dentro de un volumen que sobrevive a su Pod, y una segunda tarea ve el archivo de la primera:

```text
$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json
```

## Si no traes las imágenes del curso de Docker

Esta lección usa las mismas dos imágenes que las anteriores: `curso-docker-revisor:1.6.0` y `curso-docker-prueba:1.0.0`. Comprueba que las tienes:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para la otra, el mismo comando con `curso-docker-prueba:1.0.0`. Si te falta alguna, la [Lección 3](03-services-dns.md) dice cómo construir cada una desde el repositorio del curso de Docker. Las tareas de esta lección usan además la imagen pública de `curl` que ya conoces de `depurar`, fijada por su huella `sha256`; cada nodo la descarga de internet la primera vez.

## Los conceptos

### 8.1 El clúster de la lección y su punto de partida

#### 8.1.1 Crear el clúster

Esta lección usa su propio clúster, `curso-k8s-l8`, con la configuración de tres nodos de la Lección 1. Las rutas `programas/08-datos-y-tareas/…` del bloque siguiente suponen que estás en la raíz del repositorio del curso. Antes de crearlo, dos precauciones que ya son costumbre: un `kubeconfig` temporal y propio, para que tu `~/.kube/config` ni se lea ni se toque, y una función que comprueba a qué clúster le estás hablando. La llamaremos `ctx` y va **delante de cada comando que cambie algo**: si el contexto no es el de la lección, devuelve un error y el comando que sigue no corre, porque está unido a ella con `&&`.

```bash
# Un kubeconfig temporal y propio. La carpeta queda guardada en una variable:
# la necesitas para abrir una segunda terminal y para borrarla al final.
L8_TMP="$(mktemp -d /tmp/curso-k8s-l8.XXXX)"
export KUBECONFIG="$L8_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta
# La guarda: el contexto debe ser el de la lección, o el comando que sigue no corre.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l8 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
# curso-k8s-l8 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l8 --config programas/08-datos-y-tareas/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l8
# El resto de la lección se trabaja desde la carpeta de sus programas.
cd programas/08-datos-y-tareas
```

(La corrida de esta lección, por lo que se dijo en «Sobre las corridas», antepuso `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l8` a `kind create cluster` para usar su red propia. Tú no lo necesitas.)

El `export` y la función `ctx` solo viven en esa terminal. Si abres otra, repites las dos líneas (`export KUBECONFIG=…` con la ruta que imprimió el `echo`, y la definición de `ctx`) o `kubectl` le hablará a otro clúster. Desde aquí, **todo bloque de código que cambie algo empieza con `ctx &&`**. En las salidas pegadas más abajo, el renglón que empieza con `$` es el comando tal como lo imprimió el guion, sin `ctx &&`: el guion comprueba el contexto antes de cada `kubectl` por su cuenta, y tú lo haces con la función.

Las salidas de esta sección vienen de la corrida de `correr.sh`, que hace exactamente eso, con la red propia que se explicó en «Sobre las corridas»:

```text
$ kubectl config current-context
kind-curso-k8s-l8

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l8-control-plane   Ready    control-plane   27s   v1.37.0
curso-k8s-l8-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l8-worker2         Ready    <none>          17s   v1.37.0
```

`kind load` imprime seis renglones `not yet present on node …, loading...`, dos imágenes por tres nodos, como en las lecciones anteriores.

#### 8.1.2 La plataforma de la Lección 6, otra vez

El punto de partida de esta lección incluye el Gateway de la Lección 6, y un Gateway necesita los tipos nuevos (CRD) de Gateway API y el controlador de Envoy Gateway. Como el clúster es nuevo, hay que instalarlos otra vez, en el mismo orden de la Lección 6: primero la plataforma, luego una espera, luego su configuración. El orden importa porque los CRD y los *webhooks* deben existir antes de los recursos que los usan.

```bash
ctx && kubectl apply -k infra/metallb
ctx && kubectl apply --server-side -k infra/envoy-gateway
# La espera: los tipos nuevos establecidos y los controladores disponibles.
ctx && kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
ctx && kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
ctx && kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
# La configuración: el rango de IP de MetalLB y la clase de puerta «eg».
ctx && kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ctx && kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
```

La salida, con el rango de la red propia de la corrida:

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ sed 's#172.18.255.200-172.18.255.220#172.28.255.200-172.28.255.250#' infra/metallb-pool.yaml | kubectl apply -f - && kubectl apply -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s | tail -1
daemon set "speaker" successfully rolled out
(la plataforma tardó 175 s)
```

Dos notas sobre esta salida. La del `sed` es solo de la corrida: cambia el rango del archivo (`172.18.255.200-220`) por el de la red propia (`172.28.255.200-250`) antes de aplicarlo. En tu máquina, con la red `kind` normal, aplicas el archivo tal cual: `kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml`. Y los 175 segundos son mucho para esto (con la máquina más cargada llegaron a 678), y el guion no cronometra cada paso: la máquina estaba ocupada con otros clústeres. En un ensayo previo de esta misma lección, el último en declararse listo fue el *speaker* de MetalLB (un Pod por nodo que anuncia las IP en la red). Si en tu máquina el `rollout status` se tarda, `kubectl get pods -n metallb-system` te dice cuántos de los tres *speakers* están listos.

#### 8.1.3 El punto de partida: la Lección 7

La carpeta `programas/08-datos-y-tareas/punto-de-partida/` trae, sin cambiar una coma, los manifiestos con los que terminó la Lección 7: el espacio de nombres `revisor` con el nivel `restricted`, las cuentas de servicio, las seis políticas de red, el `revisor` y el servicio de prueba con sus Services, el Gateway y la `kustomization.yaml`. Como en las lecciones anteriores, el token no se versiona: se genera en cada corrida, con permiso `0600`, y se copia a las dos carpetas (la del punto de partida y la de la lección) para que las dos generen **el mismo** Secret.

```bash
ctx && (umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
ctx && cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
ctx && kubectl rollout status deployment/revisor -n revisor --timeout=180s
ctx && kubectl rollout status deployment/prueba -n revisor --timeout=180s
ctx && kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
ctx && kubectl apply -n revisor -f depurar.yaml
```

```text
$ ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-hbc69k5m5c created
service/prueba created
service/revisor created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created
networkpolicy.networking.k8s.io/acceso-revisor-salida created
networkpolicy.networking.k8s.io/cerrado created
networkpolicy.networking.k8s.io/dns created
networkpolicy.networking.k8s.io/prueba-entrada created
networkpolicy.networking.k8s.io/revisor-entrada created
networkpolicy.networking.k8s.io/revisor-salida created

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met

$ kubectl apply -n revisor -f depurar.yaml
pod/depurar created
```

El nombre del `ConfigMap` es el de la Lección 4, `revisor-config-t6cm6872fk`, porque la lista de servicios no cambió; el del `Secret` cambia en cada corrida, porque el token es nuevo. Los dos `rollout status` del bloque anterior no imprimen nada aquí porque el guion los corre en silencio; en tu terminal verás `deployment "revisor" successfully rolled out` y el equivalente de `prueba`. El Pod `depurar` es el de siempre, con una diferencia que ya conoces de la Lección 7: lleva la etiqueta `acceso-revisor: permitido`, y por eso la red cerrada lo deja hablar con el `revisor`.

```text
$ kubectl get pods -n revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
depurar                    1/1     Running   0          8s    10.244.2.5   curso-k8s-l8-worker    <none>           <none>
prueba-6899c74865-9dckl    1/1     Running   0          52s   10.244.1.4   curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-g6wc5   1/1     Running   0          52s   10.244.2.4   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-rxlw6   1/1     Running   0          52s   10.244.2.3   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-wk56w   1/1     Running   0          52s   10.244.1.5   curso-k8s-l8-worker2   <none>           <none>

$ kubectl get pvc,cronjob,job -n revisor
No resources found in revisor namespace.

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Tres réplicas del `revisor`, el servicio de prueba y `depurar`. Y la última línea de `kubectl get`: no hay volúmenes, ni tareas, ni horarios. Esa es la pregunta abierta de la lección. La última salida es una petición que viene desde un contenedor de Docker fuera del clúster, en la misma red que los nodos, y llega por el Gateway: la puerta de la Lección 6 funciona en el espacio de nombres de la Lección 7 con la red cerrada. Si en tu máquina no contesta, `kubectl get gateway -n revisor` dice qué IP recibió; en la corrida fue `172.28.255.200`, y en tu red `kind` sería `172.18.255.200`.

### 8.2 Qué se pierde: el `emptyDir` de hoy

#### 8.2.1 Dónde está el archivo

Primero, que el `revisor` escriba su reporte. Cada petición a `/api/estados` arma el reporte y, antes de contestar, lo guarda en el archivo que dice la variable `REVISOR_REPORTE` de la imagen, `/datos/reporte.json`. La imagen no tiene *shell*, así que no puedes entrar a ver el archivo; pero el archivo existe en algún disco, y los nodos de kind son contenedores de Docker a los que sí puedes entrar. Se pide un reporte y se busca:

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid
POD                        NODO                   UID
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347
revisor-6b7f4d564d-wk56w   curso-k8s-l8-worker2   510c7d49-6be3-4fac-947d-18783838b9e5
```

(En el primer comando, el token se ve como `…`: el guion lo oculta en lo que imprime, y tú lo pasas con `$TOKEN`, como en las lecciones anteriores.) El `uid` es el identificador único que el clúster le da a cada Pod, y es el nombre de la carpeta donde el `kubelet` del nodo guarda lo suyo. Los volúmenes de un Pod viven en `/var/lib/kubelet/pods/<uid>/volumes/`, y los de tipo `emptyDir`, en la subcarpeta `kubernetes.io~empty-dir`. Se mira la de cada una de las tres réplicas, en el nodo donde corre:

```text
$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/961791a4-d756-4382-a1de-ae62d7bc11b1/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/29162810-cd29-4693-89bf-ed789dd8f347/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

Hay tres hallazgos en estas tres salidas, y los tres importan para lo que sigue.

**El primero: solo una de las tres réplicas tiene el archivo.** La petición a `http://revisor/` la repartió el Service a una de las tres, y esa fue la que guardó el reporte. Las otras dos tienen su `/datos` vacío. Cada réplica tiene su **propio** `emptyDir`: nada se comparte entre Pods. Si le preguntaras a «el `revisor`» cuál fue su último reporte, la respuesta dependería de cuál réplica te contesta. Eso, por sí solo, ya descalifica al `emptyDir` como lugar para una historia.

**El segundo: el dueño del directorio.** La primera columna de `ls -l` es `drwxrwsrwx`: el directorio tiene permiso de lectura, escritura y entrada para todos, y una `s` en lugar de una `x` en el lugar del grupo, que es el *setgid*. El dueño es el usuario `0` (`root`) y el grupo, el `65532`. Ese grupo no es casual: es el `fsGroup: 65532` que la Lección 4 puso en el Deployment. Para no atribuirle a `fsGroup` más de lo que hace: el permiso abierto `777` es el valor por omisión de un `emptyDir` según la documentación de volúmenes; lo que pone `fsGroup` es el grupo `65532` y el bit *setgid*. 8.7 cuenta qué hizo `fsGroup` aquí y qué no hace en otros volúmenes.

**El tercero: el archivo es del usuario del `revisor`.** `-rw------- 1 65532 65532 92`: el dueño y el grupo son el 65532, el usuario con el que corre el `revisor`, y el permiso `0600` (solo el dueño) viene de cómo el `revisor` lo crea: escribe primero un archivo temporal en la misma carpeta y luego lo renombra, para que quien lo lea vea el reporte viejo o el nuevo, nunca uno a medias. Y 92 bytes: un reporte de un solo servicio.

Con `root` en el nodo se puede leer lo que el `revisor` guardó:

```text
$ docker exec curso-k8s-l8-worker2 stat -c '%a %U:%g %n' /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
2777 root:65532 /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos

$ docker exec curso-k8s-l8-worker2 cat /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos/reporte.json
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 6
  }
]
```

El `stat` traduce el permiso a octal: `2777` es el `777` de lectura y escritura para todos más el `2` del *setgid*. Es la misma información que la `s`, en otra forma. El contenido es el reporte en JSON: el nombre del servicio, si está bien, el código HTTP y el tiempo en milisegundos.

(Las salidas de esta sección asumen que sabes entrar a un nodo con `docker exec`; es lo mismo que hiciste en la Lección 4 con el `Secret` y en la Lección 5 con `crictl`. Funciona porque en kind los nodos son contenedores. En un clúster de verdad, la carpeta existe igual, pero el nodo es una máquina a la que entras con otro mecanismo y con otros permisos.)

#### 8.2.2 Un contenedor que se cae: el `emptyDir` sobrevive

La documentación de volúmenes de Kubernetes ([enlace en las fuentes](#fuentes)) dice de `emptyDir`: el volumen se crea «cuando el Pod se asigna a un nodo»; empieza vacío; y «cuando un Pod se quita de un nodo por cualquier razón, los datos del `emptyDir` se borran permanentemente». Y agrega una nota que parece pequeña y es la mitad de la lección: «un contenedor que se cae **no** quita al Pod del nodo. Los datos de un volumen `emptyDir` están a salvo ante las caídas de contenedores».

Se comprueba. Con `crictl`, la herramienta de la Lección 5, se detiene el contenedor del `revisor` que tiene el archivo. El identificador del contenedor se busca por el `uid` del Pod, para no detener uno ajeno:

```bash
CID="$(docker exec curso-k8s-l8-worker2 crictl ps --label "io.kubernetes.pod.uid=510c7d49-6be3-4fac-947d-18783838b9e5" --name revisor -q)"
docker exec curso-k8s-l8-worker2 crictl stop "$CID"
```

```text
$ docker exec curso-k8s-l8-worker2 crictl stop a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090
a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090

(esperando 10 s a que el kubelet reinicie el contenedor)

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w
NAME                       READY   STATUS    RESTARTS      AGE
revisor-6b7f4d564d-wk56w   1/1     Running   1 (10s ago)   65s

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} {.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
Error 137

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

Se lee en orden. `RESTARTS 1 (10s ago)`: el `kubelet` vio morir al contenedor y lo reinició hace 10 segundos; el Pod sigue siendo el mismo (mismo nombre, mismo `uid`, `AGE` de 65 segundos). La última terminación fue un `Error` con el código `137`, el mismo de la Lección 5: 128 más la señal 9, la que no se puede ignorar. Y la última salida es la que importa: **el archivo está intacto**, con la misma hora (`23:24`) y los mismos 92 bytes. El contenedor nuevo montó el mismo volumen y encontró el reporte donde lo dejó el viejo.

Esto tiene una consecuencia práctica que conviene decir clara: si tu aplicación se cae y se reinicia sola, lo que guardó en un `emptyDir` lo encuentra el contenedor nuevo. Ese es el uso que la documentación propone: espacio de trabajo, puntos de control de un cálculo largo para retomarlo tras una caída. No es un lugar para lo que debe sobrevivir al Pod.

#### 8.2.3 Un Pod que se borra: el `emptyDir` se va con él

El segundo escalón. Se borra el Pod entero, no solo su contenedor, y se mira la carpeta del volumen:

```bash
ctx && kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
```

```text
$ kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
pod "revisor-6b7f4d564d-wk56w" deleted from revisor namespace

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
ls: cannot access '/var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos': No such file or directory
[código de salida: 2]

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5
containers
etc-hosts
plugins
volumes

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid,LISTO:.status.containerStatuses[0].ready
POD                        NODO                   UID                                    LISTO
revisor-6b7f4d564d-4mnvh   curso-k8s-l8-worker2   d61911b6-d777-4c4c-a159-e2a782fc69d8   true
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1   true
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347   true
```

La carpeta del volumen ya no existe: `No such file or directory`, con código de salida 2. El `kubelet` borró el volumen al retirar el Pod. La segunda salida es un matiz que conviene leer con cuidado: la carpeta del Pod todavía muestra cuatro entradas (`containers`, `etc-hosts`, `plugins` y `volumes`) unos segundos después del borrado. No investigué por qué (probablemente sea limpieza del `kubelet` que aún no terminaba); lo que importa para la lección ya pasó: la carpeta del volumen de datos no existe. Y el ReplicaSet repuso la réplica: `4mnvh` es nueva (otro nombre, otro `uid`) y esta vez cayó en el mismo nodo, `curso-k8s-l8-worker2`; el planificador reparte, pero no promete un nodo distinto. El `revisor` nuevo arrancó con su `/datos` vacío.

Con esto, el viernes por la tarde de la escena queda explicado en dos mediciones. Un reinicio del contenedor se salva. El mantenimiento del sábado no reinició contenedores: desalojó Pods, y cada Pod nuevo nació con un `emptyDir` nuevo, en un nodo que quizá no era el mismo. (Un simple reinicio del nodo es otra cosa: la documentación del ciclo de vida del Pod distingue ese caso, en que el Pod no se desaloja y el `kubelet` vuelve a levantar sus contenedores, del desalojo o la pérdida del nodo. Los Pods se reemplazan cuando alguien los borra, el nodo se vacía o se declara perdido.) Para que un dato sobreviva al Pod necesitas un volumen que **no dependa del Pod**: eso es lo que sigue.

### 8.3 Volúmenes, solicitudes y clases

#### 8.3.1 Tres objetos, tres papeles

Antes de usarlos, los tres objetos con un ejemplo de la vida diaria. Imagina un edificio de oficinas. Los **espacios de oficina** existen: alguien los construyó, tienen un tamaño y una ubicación. Una **solicitud de renta** dice «necesito una oficina de tantos metros, para trabajar una sola empresa»; no dice cuál. Y el **tipo de oficina** (con vista, sin vista, en el sótano) describe cómo se construyen y cuánto cuestan. En Kubernetes:

| En el edificio | En Kubernetes | Quién lo crea | Qué dice |
|---|---|---|---|
| el espacio de oficina | `PersistentVolume` (PV) | el administrador del clúster, o el sistema, bajo demanda | «existe un almacenamiento de este tamaño, en este lugar, con estas reglas» |
| la solicitud de renta | `PersistentVolumeClaim` (PVC) | quien despliega la aplicación | «necesito este tamaño, con este modo de acceso» |
| el tipo de oficina | `StorageClass` | el administrador del clúster | «así se crea un volumen de esta clase» |

La [documentación de volúmenes persistentes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) define los dos primeros con estas palabras: un PersistentVolume es «una pieza de almacenamiento en el clúster que ha sido aprovisionada por un administrador o aprovisionada dinámicamente usando clases de almacenamiento. Es un recurso del clúster, igual que un nodo». Y una PersistentVolumeClaim «es una solicitud de almacenamiento por parte de un usuario. Es similar a un Pod». La analogía con el Pod va más lejos de lo que parece: así como un Pod consume recursos de un nodo, una solicitud consume recursos de un volumen; y así como un Pod puede pedir CPU y memoria, una solicitud pide un tamaño y un modo de acceso.

Un detalle de nombres que confunde a quien llega: el PV **no tiene espacio de nombres** (es del clúster, como un nodo; en la salida de `kubectl api-resources --namespaced=false` aparece junto a `nodes` y `namespaces`), y la PVC **sí** (vive en `revisor`, junto a los Pods que la usan).

```text
$ kubectl api-resources --api-group='' --namespaced=false -o name | grep -E '^(persistentvolumes|nodes|namespaces)$'
namespaces
nodes
persistentvolumes
```

#### 8.3.2 Los dos caminos para tener un volumen

La misma página describe dos formas de que una solicitud encuentre su volumen:

- **Estática.** «Un administrador del clúster crea cierto número de PV.» Los PV ya existen, y una solicitud que coincide con uno (en tamaño, en modo de acceso, en clase) se une a él. Es lo que pasa con discos que alguien preparó a mano.
- **Dinámica.** «Cuando ninguno de los PV estáticos que creó el administrador coincide con la solicitud de un usuario, el clúster puede intentar aprovisionar dinámicamente un volumen para ella.» Nadie crea el PV: lo crea un programa del clúster, el *aprovisionador*, a partir de la clase que pidió la solicitud.

Y el trámite, que la documentación llama el ciclo de vida: primero el aprovisionamiento; luego la unión (*binding*): «un ciclo de control del plano de control vigila las PVC nuevas, encuentra un PV que coincida (si puede) y las une»; después el uso: «una vez que el usuario tiene una solicitud y está unida, el PV unido le pertenece mientras la necesite»; y al final la reclamación, cuando el usuario ya no la necesita. Anota una frase de esa página, porque la vas a ver cumplida: «las solicitudes se quedan sin unir indefinidamente si no existe un volumen que coincida». También la unión es de uno a uno: un PV con una solicitud, y una solicitud con un PV.

El curso usa los dos caminos, cada uno donde enseña algo. El dinámico es el camino normal y es el que usa el reporte de la lección. El estático lo usarás en 8.7 para fabricar un disco con las reglas de uno de verdad.

#### 8.3.3 La clase de kind

Este clúster ya trae una clase. Se le pregunta:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  4m31s

$ kubectl get storageclass standard -o jsonpath='{.provisioner} {.reclaimPolicy} {.volumeBindingMode} {.allowVolumeExpansion}{"\n"}'
rancher.io/local-path Delete WaitForFirstConsumer

$ kubectl get pods -n local-path-storage
NAME                                      READY   STATUS    RESTARTS   AGE
local-path-provisioner-75f7fc7dc5-xl4bd   1/1     Running   0          4m26s

$ kubectl get pv
No resources found
```

Una clase con cuatro datos que importan:

- **`standard (default)`** es su nombre, y el paréntesis dice que es la **clase por omisión**: la documentación de clases dice que, cuando una solicitud no pone `storageClassName`, «se usa la clase por omisión». El curso la nombra de todos modos en su manifiesto, porque un manifiesto que dice lo que usa se lee sin depender de una configuración del clúster.
- **`rancher.io/local-path`** es el aprovisionador. En el espacio de nombres `local-path-storage` hay un Pod, `local-path-provisioner`, que vigila las solicitudes de esta clase y les crea el volumen. La documentación del proyecto lo describe así: «ofrece una forma de que los usuarios de Kubernetes utilicen el almacenamiento local de cada nodo», y el volumen que crea es, por omisión, una carpeta del nodo, de tipo `hostPath`. Dos frases de ese mismo README, que usaremos más adelante, anótalas: no soporta límite de capacidad («la capacidad se ignora por ahora»), y la carpeta se crea con permiso `0777`.
- **`Delete`** es la **política de reclamación** de los volúmenes de esta clase: qué se hace con el volumen cuando se borra la solicitud que lo usaba. La documentación de volúmenes persistentes lo dice así: con `Delete`, el borrado quita tanto el objeto PV de Kubernetes como el almacenamiento asociado. La alternativa es `Retain`, que conserva el volumen para que un administrador lo recupere a mano. 8.8 lo mide con las dos.
- **`WaitForFirstConsumer`** es el **modo de unión**, y es el dato más importante para entender lo que sigue. La documentación de clases lo explica por contraste. Con el modo `Immediate`, que es el que se usa si no pones nada, «la unión de volúmenes y el aprovisionamiento dinámico ocurren en cuanto se crea la solicitud». Eso puede salir mal cuando el almacenamiento está atado a un lugar (un nodo, una zona), porque se crearía el volumen sin saber dónde va a correr el Pod. El remedio: el modo `WaitForFirstConsumer` «retrasará la unión y el aprovisionamiento de un PersistentVolume hasta que se cree un Pod que use la PersistentVolumeClaim». Primero se decide dónde va a correr el Pod; luego se crea el volumen **en ese lugar**.
- **`ALLOWVOLUMEEXPANSION false`** (y vacío en el `jsonpath`, porque el campo no está escrito en la clase): la clase no permite agrandar un volumen después de creado. No lo vas a necesitar aquí; si algún día un volumen se llena, esta columna decide si la salida es agrandarlo o crear otro más grande y mudar los datos.

Y el cierre de la salida: **`No resources found`** en `kubectl get pv`. No hay ningún volumen todavía. La clase existe, el aprovisionador espera, y los volúmenes se crean cuando alguien los pida y haya un Pod que los use.

### 8.4 La solicitud de volumen y su espera

#### 8.4.1 El manifiesto

La lección agrega un archivo al proyecto, `reporte.yaml`, con tres objetos: la cuenta de servicio `reporte`, la solicitud `reportes` y el `CronJob` `reporte`. Los dos primeros se leen ahora; el tercero tiene su propia sección, la 8.6, porque necesita que antes sepas qué es un Job. El archivo completo es un **programa**: `programas/08-datos-y-tareas/reporte.yaml`, y la `kustomization.yaml` de la lección lo suma a su lista de recursos.

```yaml
# reporte.yaml — Lección 8: el reporte guardado y el revisor como tarea programada.
# Cada 5 minutos, un Job le pide al revisor su reporte y lo guarda en un volumen
# persistente. El binario del revisor solo sirve HTTP (no tiene modo «una vez»),
# por eso la tarea es un curl contra su API; la lección (8.6) explica por qué.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reporte
automountServiceAccountToken: false
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reportes
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 100Mi
```

(La tercera pieza, el `CronJob`, está completa en 8.6; aquí se corta para leer primero la solicitud.) La cuenta de servicio es la costumbre de la Lección 7: una cuenta propia para la tarea, sin permisos y con `automountServiceAccountToken: false`, porque la tarea le habla al `revisor`, no a la API del clúster. La solicitud tiene cuatro líneas que importan:

- **`accessModes: [ReadWriteOnce]`** es el **modo de acceso**. Se abrevia RWO y la documentación lo define así: «el volumen puede montarse como lectura y escritura por **un solo nodo**». Esa última palabra es la que se malinterpreta: es un nodo, no un Pod. La misma página aclara que RWO «todavía puede permitir que varios Pods accedan (lean o escriban) al volumen cuando los Pods corren en el mismo nodo». Retenlo, porque el Ejercicio 2 lo usa. Existen otros modos (`ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`); con la clase de kind, el que aplica es éste: la tabla de la misma página marca que un volumen `HostPath` soporta solo `ReadWriteOnce`, y la carpeta vive en un nodo.
- **`storageClassName: standard`** nombra la clase. Escribir el nombre, aunque sea la clase por omisión, deja el manifiesto sin sorpresas en un clúster donde la clase por omisión sea otra.
- **`storage: 100Mi`** es el tamaño pedido: 100 mebibytes, la misma unidad de memoria de la Lección 5. En aritmética pura, 100 Mi alcanzan para más de un millón de reportes de 92 bytes. En un sistema de archivos real cada archivo ocupa al menos un bloque (comprobé en la máquina de Docker de la corrida que un archivo de 92 bytes ocupa 8 bloques de 512, es decir 4096 bytes, con bloques de sistema de archivos de 4096), así que 100 Mi caben unos 25,600 archivos, y con 288 reportes al día (uno cada cinco minutos) eso son unos 89 días de historial antes de tener que purgar. Habrá algo que decir más adelante sobre qué tan en serio se toma un clúster ese número.
- **No hay `volumeName`**: la solicitud no nombra un volumen. Pide una clase y un tamaño, y el sistema resolverá el resto.

Antes de aplicar, la pregunta que la Lección 5 enseñó a hacer: qué cambiaría.

```bash
kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
```

```text
$ kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
+  concurrencyPolicy: Forbid
+          schedulerName: default-scheduler
+  schedule: '*/5 * * * *'
+      storage: 100Mi
+  storageClassName: standard
[código de salida: 1]
```

El `diff` filtra solo lo que se agrega (líneas que empiezan con `+ `) y, de esas, las que nombran lo nuevo de la lección: la política de concurrencia, el horario, el tamaño y la clase. El guion imprime `[código de salida: 1]` porque corre con `pipefail` y conserva el 1 de `kubectl diff` (hay diferencias, como en la Lección 5); en tu terminal, la tubería devuelve el código de `grep` y verás 0. (El renglón de `schedulerName` lo agrega el clúster como valor por omisión; el `grep` lo atrapó por contener la palabra `schedule`.)

#### 8.4.2 Aplicar, y leer el `Pending`

```bash
ctx && kubectl apply -k .
```

```text
$ kubectl apply -k .
namespace/revisor unchanged
serviceaccount/observador unchanged
serviceaccount/prueba unchanged
serviceaccount/reporte created
serviceaccount/revisor unchanged
role.rbac.authorization.k8s.io/observador unchanged
rolebinding.rbac.authorization.k8s.io/observador unchanged
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hbc69k5m5c unchanged
service/prueba unchanged
service/revisor unchanged
persistentvolumeclaim/reportes created
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
cronjob.batch/reporte created
gateway.gateway.networking.k8s.io/revisor configured
httproute.gateway.networking.k8s.io/revisor configured
networkpolicy.networking.k8s.io/acceso-revisor-salida unchanged
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged
```

Los Deployments no cambiaron (`unchanged`): ninguna réplica se reinició. Lo nuevo son tres objetos, `serviceaccount/reporte`, `persistentvolumeclaim/reportes` y `cronjob.batch/reporte`. (Que `gateway` y `httproute` digan `configured` aparece en este `apply` y no cambia nada que se vea en el servicio; la lección no lo investiga.) Y ahora, lo que importa:

```text
$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 1s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          0s

$ kubectl describe pvc reportes -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason                Age   From                         Message
  ----    ------                ----  ----                         -------
  Normal  WaitForFirstConsumer  1s    persistentvolume-controller  waiting for first consumer to be created before binding

$ kubectl get pv
No resources found
```

`STATUS Pending`, `VOLUME` vacío, `CAPACITY` vacía. A quien viene de las lecciones anteriores, `Pending` le suena a problema (el Pod de la Lección 5 que no cabía en ningún nodo). Aquí **no lo es**, y el evento lo dice con todas sus letras: `waiting for first consumer to be created before binding`, «esperando a que se cree el primer consumidor antes de unirse». Es el modo `WaitForFirstConsumer` de 8.3.3 en acción. Todavía no hay ningún Pod que use la solicitud, así que el clúster no ha decidido en qué nodo va a correr nada, y por tanto no puede decidir en qué nodo crear la carpeta. Y `kubectl get pv` lo confirma: sin volumen.

La diferencia con el `Pending` de la Lección 5 es la que separa un diagnóstico de otro. Aquí el evento es de nivel `Normal`, lo emite `persistentvolume-controller` y dice que espera; allá era un `Warning` del planificador que decía que no había dónde. La regla para leer cualquier `Pending` es la misma de siempre: los eventos dicen quién espera y a qué. Un `Pending` con `WaitForFirstConsumer` y ningún Pod usando la solicitud es un sistema funcionando.

El `CronJob`, mientras tanto, existe y no ha corrido: `LAST SCHEDULE <none>`, `ACTIVE 0`. Su primera ejecución llegará en el siguiente múltiplo de cinco minutos del reloj. Para no esperar, 8.5 enseña a pedir una a mano.

### 8.5 `Job`: la tarea que termina

#### 8.5.1 El más pequeño que sirve

Un **`Job`** es, en las palabras de su documentación, una tarea que corre «hasta completarse y luego se detiene». Crea uno o más Pods y reintenta «hasta que un número especificado de ellos termina con éxito». Cuando se alcanza ese número, el Job está completo. Lo importante frente al Deployment es qué se considera éxito: un Pod de un Job que termina con código 0 **es** el resultado esperado; en un Deployment, ese mismo Pod sería un fallo, y el clúster lo reemplazaría.

Antes del Job de verdad, uno de práctica: `fig08_01.job-salud.yaml`, que una sola vez le pregunta a `/salud` del `revisor` y termina. Es un **programa**.

```yaml
# fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
# a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
# cerrada de la Lección 7 exige para que un Pod hable con el revisor.
apiVersion: batch/v1
kind: Job
metadata:
  name: salud
  namespace: revisor
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 120
  template:
    metadata:
      labels:
        app: salud
        acceso-revisor: permitido
    spec:
      automountServiceAccountToken: false
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: salud
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["curl", "-fsS", "-m", "5", "http://revisor/salud"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Léelo de arriba abajo; casi todo lo reconoces. `apiVersion: batch/v1` y `kind: Job`: el grupo `batch` agrupa los Jobs y los CronJobs. El `namespace: revisor` va escrito en el archivo para que el Job caiga ahí sin que tengas que acordarte de `-n`. `spec.template` es la plantilla del Pod, igual que en un Deployment, pero con dos diferencias. La primera: **no tiene selector**, porque el Job lo asigna solo (la documentación advierte que «en casi todos los casos no deberías especificarlo»). La segunda: `restartPolicy` es obligatorio y solo admite dos valores, `Never` y `OnFailure`. Con `Never`, si el contenedor falla, el Pod queda como `Failed` y el Job crea otro; con `OnFailure`, el `kubelet` reinicia el contenedor dentro del mismo Pod. El curso usa `Never`: cada intento es un Pod aparte, con su propia bitácora y su propio código de salida, y puedes leer qué pasó en cada uno. Con `OnFailure`, los intentos se encimarían en un solo Pod.

Los dos campos del Job que no son del Pod:

- **`backoffLimit: 2`**: cuántas veces reintentar antes de rendirse. La documentación dice que el valor por omisión es 6, y que los Pods fallidos se recrean «con una espera exponencial (10 s, 20 s, 40 s…) con tope de diez minutos». Aquí 2 significa: el intento original más dos reintentos, tres Pods como máximo.
- **`activeDeadlineSeconds: 120`**: un tope de tiempo para el Job completo, **sin importar cuántos Pods cree**. Cuando se cumple, el clúster termina los Pods que corren y el Job pasa a `Failed` con la razón `DeadlineExceeded`. Y la documentación precisa que este plazo tiene precedencia sobre `backoffLimit`: un Job que está reintentando no crea más Pods cuando llega el plazo, aunque no haya agotado sus intentos. Los dos topes cubren fallas distintas: uno es para «falla rápido muchas veces», el otro para «se queda colgado».

La tarea misma, `curl -fsS -m 5 http://revisor/salud`, se lee por letras. `-f` hace que curl salga con error cuando el servidor contesta 400 o más (sin esa letra, un 503 saldría con código 0, y el Job lo contaría como éxito). `-sS` es silencioso pero muestra los errores. `-m 5` es el tiempo máximo de toda la operación: 5 segundos. Y el comando se escribe como lista (`["curl", ...]`) y no como un texto para un *shell*, porque la imagen de `curl` no necesita uno para esto.

```bash
ctx && kubectl apply -f fig08_01.job-salud.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/salud --timeout=180s
```

```text
$ kubectl apply -f fig08_01.job-salud.yaml
job.batch/salud created

$ kubectl get job,pods -n revisor -l app=salud
NAME              STATUS     COMPLETIONS   DURATION   AGE
job.batch/salud   Complete   1/1           4s         4s

NAME              READY   STATUS      RESTARTS   AGE
pod/salud-svx9s   0/1     Completed   0          4s

$ kubectl logs -n revisor job/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor salud -o jsonpath='{range .status.conditions[*]}{.type} {.status}{"\n"}{end}'
SuccessCriteriaMet True
Complete True
```

El Job tardó 4 segundos y terminó con `COMPLETIONS 1/1`. El Pod quedó como `Completed` con `READY 0/1`: no es un error. El contenedor terminó bien y ya no corre, y el Pod se conserva para que puedas leer su bitácora. `kubectl logs job/salud` encuentra el Pod del Job y muestra lo que imprimió el `curl`: el JSON de `/salud`. Las condiciones del Job son dos: `SuccessCriteriaMet` (se cumplió el criterio de éxito) y `Complete` (terminó). Que haya dos y no una tiene que ver con algo que la documentación dice: desde la versión 1.31, el controlador de Jobs retrasa la condición terminal (`Complete` o `Failed`) hasta que todos los Pods del Job hayan terminado. `SuccessCriteriaMet` (y su gemela `FailureTarget`, que verás en «El error que vas a ver») son las condiciones que aparecen antes: dicen que el desenlace ya se decidió.

Se borra para dejar el espacio como estaba:

```text
$ kubectl delete -f fig08_01.job-salud.yaml
job.batch "salud" deleted from revisor namespace
```

La documentación lo dice: borrar un Job limpia los Pods que creó. Eso importa en 8.8, donde el borrado de los Jobs se vuelve parte de la maniobra.

#### 8.5.2 El reporte guardado: la primera tarea

Ahora el Job de la lección. No se escribe aparte: el `CronJob` `reporte` ya lo trae adentro, como plantilla, y `kubectl` sabe crear un Job a partir de él en cualquier momento, sin esperar el horario. Es la forma de probar una tarea programada sin quedarse mirando el reloj:

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
```

```text
$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
job.batch/reporte-manual-1 created

$ kubectl get pods -n revisor -l app=reporte -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE        READINESS GATES
reporte-manual-1-t7d8l   0/1     Pending   0          3s    <none>   <none>   curso-k8s-l8-worker   <none>

$ kubectl describe pvc reportes -n revisor | sed -n '/^Used By:/,$p'
Used By:       reporte-manual-1-t7d8l
Events:
  Type    Reason                Age              From                                                                                                Message
  ----    ------                ----             ----                                                                                                -------
  Normal  WaitForFirstConsumer  7s (x2 over 9s)  persistentvolume-controller                                                                         waiting for first consumer to be created before binding
  Normal  ExternalProvisioning  3s (x2 over 3s)  persistentvolume-controller                                                                         Waiting for a volume to be created either by the external provisioner 'rancher.io/local-path' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
  Normal  Provisioning          3s               rancher.io/local-path_local-path-provisioner-75f7fc7dc5-xl4bd_3605f90f-a3ba-46c3-a75e-a794883e9732  External provisioner is provisioning volume for claim "revisor/reportes"
```

Aquí está, en tres segundos, la historia que 8.3.3 anunció. El Pod de la tarea existe y está `Pending`, pero fíjate en la columna `NOMINATED NODE`: el planificador ya **nominó** un nodo, `curso-k8s-l8-worker`, aunque el Pod todavía no está asignado (la columna `NODE` sigue en `<none>`). Con el modo `WaitForFirstConsumer`, el planificador decide primero dónde correrá el Pod; la documentación de clases lo dice así: el volumen se selecciona o aprovisiona «conforme a la topología que especifican las restricciones de planificación del Pod». Con esa decisión tomada, el aprovisionador de la clase puede actuar. Los eventos de la solicitud cuentan lo que pasó, de arriba hacia abajo (la columna `Age` baja: 7 s, 3 s, 3 s): la solicitud esperaba un consumidor (`WaitForFirstConsumer`); apareció el Pod y el controlador se lo dejó claro al aprovisionador (`ExternalProvisioning`, que quiere decir «un aprovisionador externo debe crear el volumen»); el aprovisionador `rancher.io/local-path` empezó (`Provisioning`). La captura se hizo a los 3 segundos y por eso termina ahí; el evento siguiente, `ProvisioningSucceeded`, con el nombre del volumen creado (aquí `pvc-5fcf36b8-…`), llega un instante después (en otra corrida del mismo guion alcanzó a salir en la captura). Por eso lo de «externo»: el aprovisionador es un programa aparte, un Pod del clúster, no parte del plano de control.

El renglón de arriba, `Used By: reporte-manual-1-t7d8l`, es una novedad de esta versión: dice qué Pod usa la solicitud. Junto a él, `kubectl describe` puede mostrar una tabla `Conditions` con la condición `Unused`, y aquí hay que ser exactos sobre lo que se midió: en esta captura la tabla **no salió**: el controlador de protección todavía no había escrito la condición (la captura se hizo a los 3 segundos). Fíjate que `Used By:` ya lista al Pod aunque esté `Pending`: para esta condición, un Pod cuenta como usuario mientras no haya terminado, incluso antes de que lo asignen a un nodo; en otra corrida del mismo guion, a los 3 segundos, sí salió una condición `Unused False` con la razón `PodUsingPVC` («un Pod está usando la solicitud»). Es decir, la condición aparece según el instante en que mires, y no puedes contar con verla. Cuidado con su alcance: la documentación define `Unused` solo con Pods que no han terminado (un Pod en fase `Succeeded` o `Failed` no cuenta), mientras que la protección de borrado de 8.8 cuenta cualquier objeto Pod que use la solicitud. Un Pod `Completed` no mantiene `Unused` en `False`, pero sí puede mantener la solicitud en `Terminating`. El registro de cambios de Kubernetes v1.37 lo explica: la función `PersistentVolumeClaimUnusedSinceTime` pasó a beta y quedó activada por omisión, y las solicitudes «reportan la condición `Unused`, que indica cuánto tiempo lleva una solicitud sin usarse, para ayudar a identificar candidatas a limpieza». Es una pista útil en un clúster viejo: las solicitudes con `Unused True` desde hace meses son candidatas a revisar (puede que aún tengan Pods terminados que las mantengan protegidas).

```text
$ kubectl logs -n revisor job/reporte-manual-1
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json

$ kubectl get pvc -n revisor
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 13s

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,CLASE:.spec.storageClassName,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],RUTA:.spec.hostPath.path
NOMBRE                                     CLASE      NODO                  RUTA
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   standard   curso-k8s-l8-worker   /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
```

La bitácora de la tarea es el `ls -ln` que ella misma imprime después de guardar: un archivo, `reporte-20261021T232446Z.json`, con la fecha en el nombre (año, mes, día, `T`, hora, minuto, segundo, `Z` de UTC). Esa es la respuesta a la mitad de la escena: no se pisa nada. Dueño `100`, grupo `101`: los del usuario de la tarea, el de la imagen de `curl`.

La solicitud ya es `Bound` (unida), con el volumen `pvc-5fcf36b8-…`, 100Mi, RWO, clase `standard`. Y el volumen, mirado con las columnas que importan, tiene dos datos que merecen explicación:

- **`NODO curso-k8s-l8-worker`**: el volumen tiene una **afinidad de nodo**. Está atado a un solo nodo, el que eligió el planificador. Esto es lo que lo hace un volumen **local**: sus datos están en el disco de esa máquina, y cualquier Pod que lo use tiene que correr ahí. Si ese nodo se pierde, los datos se van con él.
- **`RUTA /var/local-path-provisioner/pvc-…_revisor_reportes`**: la carpeta real, en el nodo. El nombre sigue el patrón `<volumen>_<espacio de nombres>_<solicitud>`, y es el lugar donde se puede ir a mirar.

```text
$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
777 0:0 /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
total 12
drwxrwxrwx 2   0   0 4096 Oct 21 23:24 .
drwxr-xr-x 3   0   0 4096 Oct 21 23:24 ..
-rw-r--r-- 1 100 101   92 Oct 21 23:24 reporte-20261021T232446Z.json
```

El directorio tiene permiso `777` y dueño `0:0` (`root`). Compáralo con el del `emptyDir` de 8.2.1: allá era `2777` y el grupo `65532`. Aquí no hay *setgid* ni grupo de la tarea. **Aunque el Pod de la tarea declara `fsGroup: 101`, el directorio de este volumen no cambió de dueño.** Es el contraste con el segundo hallazgo de 8.2.1, y 8.7 lo desarrolla: lo medido aquí es que `fsGroup` no hizo nada visible en este tipo de volumen. El permiso `777` viene del aprovisionador, que según su README crea la carpeta con `mkdir -m 0777`. Por eso la tarea pudo escribir: no por su grupo, sino porque la carpeta deja entrar a cualquiera.

#### 8.5.3 El Pod terminó; el archivo sigue ahí

La prueba del volumen es que sobreviva al Pod que lo llenó. El Pod de la primera tarea ya terminó. Se lanza una segunda tarea, un Pod nuevo, con otro nombre, que no tiene nada que ver con el primero salvo que monta la misma solicitud:

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
```

```text
$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-manual-1-t7d8l   0/1     Completed   0          7s

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
job.batch/reporte-manual-2 created

$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-manual-1   Complete   1/1           7s         15s
reporte-manual-2   Complete   1/1           5s         6s
```

El segundo Pod ve **dos** archivos: el suyo, de las `23:24:51`, y el de la primera tarea, de las `23:24:46`, de un Pod que ya no está corriendo. Eso es lo que no podía hacer el `emptyDir`. La solicitud, y el volumen que la respalda, tienen un ciclo de vida independiente del de los Pods. Mientras la solicitud exista y el disco del nodo que guarda la carpeta siga íntegro, los datos se conservan aunque los Pods que los escribieron hayan terminado.

Se confirma el contenido con el nodo. El primer comando es el reporte en formato tabla que ya conoces (solo confirma que el `revisor` responde igual que antes); el segundo lee los archivos que dejaron las tareas, que guardan lo que respondió `/api/estados` en cada momento:

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ docker exec curso-k8s-l8-worker sh -c 'cat /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes/reporte-*.json | head -9'
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 5
  }
]
[
```

(El `head -9` corta la salida a nueve líneas: el primer archivo completo y el inicio del segundo.) La escena del lunes queda resuelta en su forma: el reporte del viernes a las 6 de la tarde, hora de la Ciudad de México, sería un archivo `reporte-20261017T0000…Z.json` (las 18:00 de México son las 00:00 UTC del sábado, y los segundos casi nunca son `00` porque el Pod arranca unos segundos después del horario), uno entre decenas, ninguno pisado por el siguiente.

Antes de seguir, dos preguntas que este diseño deja y que la lección contesta en su sitio. Primera: si el `CronJob` lo hace cada cinco minutos, ¿quién lo hace funcionar? Es la 8.6. Segunda: si la tarea guarda un archivo y el `revisor` también guarda `reporte.json` en su `emptyDir`, ¿por qué no guarda el `revisor` directamente en el volumen? La decisión del curso es que no, y el Ejercicio 2 te deja comprobar por qué.

### 8.6 `CronJob`: la tarea con horario

#### 8.6.1 El objeto, campo por campo

Un **`CronJob`** crea Jobs en un horario repetido. La [documentación](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) lo compara con algo que quizá ya conoces: «un objeto CronJob es como una línea de un archivo *crontab* (tabla de cron) de un sistema Unix. Ejecuta un Job periódicamente en un horario dado, escrito en formato Cron». Lo que sigue es la tercera pieza de `reporte.yaml`, la que se cortó en 8.4.1:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: reporte
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 60
      template:
        metadata:
          labels:
            app: reporte
            # la red (red.yaml) deja a estos Pods hablar con el revisor:8080
            acceso-revisor: permitido
        spec:
          serviceAccountName: reporte
          automountServiceAccountToken: false
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 100
            runAsGroup: 101
            fsGroup: 101
            seccompProfile:
              type: RuntimeDefault
          containers:
          - name: reporte
            image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
            command:
            - sh
            - -c
            - >-
              curl -fsS -m 20
              -H "Authorization: Bearer $(cat /secretos/token)"
              -o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json
              http://revisor/api/estados
              && ls -ln /datos
            resources:
              requests: {cpu: 10m, memory: 16Mi}
              limits: {cpu: 100m, memory: 32Mi}
            volumeMounts:
            - name: datos
              mountPath: /datos
            - name: token
              mountPath: /secretos
              readOnly: true
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop: ["ALL"]
          volumes:
          - name: datos
            persistentVolumeClaim:
              claimName: reportes
          - name: token
            secret:
              secretName: revisor-token
              defaultMode: 0440
```

Esto es lo nuevo, de arriba abajo:

**`schedule: "*/5 * * * *"`** es el horario, en el formato de cinco campos de cron. Según la documentación, de izquierda a derecha son: minuto (0 a 59), hora (0 a 23), día del mes (1 a 31), mes (1 a 12) y día de la semana (0 a 6, de domingo a sábado). Un asterisco quiere decir «cualquiera», y `*/5` quiere decir «cada cinco»: `*/5 * * * *` es «cada cinco minutos, a cualquier hora, cualquier día». Los ejemplos de la documentación ayudan a leer otros: `0 3 * * 1` es «los lunes a las 3 de la mañana». Y las abreviaturas `@hourly`, `@daily`, `@weekly`, `@monthly` y `@yearly` existen como atajos. El Ejercicio 4 te pide escribir dos horarios.

**¿En qué zona horaria?** La documentación lo dice claro: para un CronJob sin zona horaria, el `kube-controller-manager` interpreta el horario en su zona local, que en kind es UTC. La columna `TIMEZONE` de la salida decía `<none>`, que es justo eso. Se puede fijar con `.spec.timeZone` (por ejemplo `"America/Mexico_City"`); poner `TZ=` o `CRON_TZ=` dentro del horario no se admite y el clúster lo rechaza con un error de validación, según la documentación. En un clúster real, el curso recomienda escribir la zona; es la causa de más de un «¿por qué corrió a las 4 de la madrugada?».

**`concurrencyPolicy: Forbid`**: qué hacer si llega la hora de una ejecución nueva y la anterior sigue corriendo. Los tres valores, según la documentación: `Allow` (el valor por omisión) deja correr las dos a la vez; `Forbid` no permite ejecuciones concurrentes y salta la nueva; `Replace` reemplaza la que corre por la nueva. Para la tarea del reporte, `Forbid` es la elección prudente: dos tareas escribiendo en el mismo volumen a la vez sería más complicado de lo necesario. El Ejercicio 3 te deja ver trabajar a los tres.

**`successfulJobsHistoryLimit: 3` y `failedJobsHistoryLimit: 3`**: cuántos Jobs terminados conservar. Los valores por omisión son 3 y 1, y un valor de cero no conserva ninguno. Se conservan porque son la evidencia: sin ellos, un Job fallido desaparecería con su bitácora y nadie sabría por qué. Se acotan porque sin tope se acumularían (un Job cada 5 minutos son 288 al día).

**`jobTemplate`** es un Job completo, el que el CronJob crea cada vez. Adentro, `backoffLimit: 2` y `activeDeadlineSeconds: 60` son los de 8.5.1, con un plazo de un minuto: si la tarea se cuelga, el clúster la corta antes de que se encime con la siguiente.

**La plantilla del Pod** ya es familiar: la cuenta `reporte`, sin credenciales montadas; el `securityContext` de la Lección 7 (sin `root`, usuario 100 y grupo 101 de la imagen de `curl`); los recursos de la Lección 5. La etiqueta `acceso-revisor: permitido` es la que abre la red: sin ella el Pod no llega al `revisor`, y la sección «El error que vas a ver» lo demuestra. El volumen `datos` es la solicitud `reportes`. Y el volumen `token` monta el `Secret` de la Lección 4, como archivo, con `defaultMode: 0440`.

Una nota sobre la ruta `/secretos/token`: el archivo se llama como la **llave** del Secret, y la Lección 4 la generó con `token=token.txt` en Kustomize. Si algún día armas el Secret a mano con `kubectl create secret generic revisor-token --from-file=token.txt`, la llave será `token.txt` y el archivo `/secretos/token.txt`; para que coincida, usa `--from-file=token=token.txt`.

Una cosa que merece detenerse: el `secretName` del archivo dice `revisor-token`, sin el *hash*, igual que en el Deployment del `revisor`. Kustomize lo reescribe al armar el resultado, **también dentro de un CronJob**. Se comprueba:

```text
$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.schedule}{" "}{.spec.concurrencyPolicy}{" "}{.spec.successfulJobsHistoryLimit}{" "}{.spec.failedJobsHistoryLimit}{" "}{.spec.timeZone}{"\n"}'
*/5 * * * * Forbid 3 3

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[1].secret.secretName}{"\n"}'
revisor-token-hbc69k5m5c

$ kubectl get secret -n revisor -o name
secret/revisor-token-hbc69k5m5c
```

El campo `timeZone` salió vacío (el horario va en UTC). El nombre del Secret dentro de la plantilla del CronJob es el generado, con su *hash*: Kustomize encontró la referencia y la cambió, como hizo con el Deployment. Esto importa para los programas de la lección: los ejemplos `fig08_NN` que no pasan por Kustomize (los que se aplican con `kubectl apply -f`) no pueden referirse al Secret por su nombre base, y por eso ninguno lo monta.

La tarea misma es un `sh -c` con dos comandos unidos por `&&`: el `curl` (con cuatro opciones y una dirección) y `ls -ln /datos`. Se lee opción por opción, de izquierda a derecha: `curl -fsS -m 20` (como en el Job de práctica, pero con 20 segundos, porque armar un reporte consulta servicios y puede tardar más); `-H "Authorization: Bearer $(cat /secretos/token)"` (el encabezado con el token, que se lee del archivo montado en el momento de correr y nunca aparece escrito en el manifiesto); `-o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json` (guarda la respuesta en un archivo cuyo nombre lleva la hora UTC de ese instante, con `date -u`); y `http://revisor/api/estados`, la dirección del Service. Si el `curl` falla, el `&&` impide que siga y la tarea sale con el código de `curl`: el Job lo cuenta como fallo. Si funciona, `ls -ln /datos` imprime el listado, que es lo que viste en la bitácora de las tareas manuales.

¿Por qué un `curl` contra la API y no una tarea que ejecute al propio `revisor` una vez y termine? Porque el `revisor` es un servidor HTTP y no trae un modo «revisa una vez». Es una decisión del curso, no un truco: se prefiere aprovechar el programa tal como lo entrega el curso de Docker, sin cambiarlo. La tarea es un cliente del `revisor` como cualquier otro.

#### 8.6.2 Ver pasar el horario

El horario de verdad es de cinco minutos. Para verlo funcionar sin esperarlo, `fig08_03.cron-cada-minuto.yaml` es un CronJob que corre cada minuto (`* * * * *`) y le pregunta a `/salud`, que no pide token. Es un **programa**; su plantilla es la del Job de práctica y lo nuevo es el encabezado.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: salud-cada-minuto
  namespace: revisor
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 30
      template:
        # … la plantilla del Job de práctica (etiqueta acceso-revisor incluida), con una
        # diferencia: el comando imprime primero la hora, para poder leerla en la bitácora:
        #   command: ["sh", "-c", "date -u +%T; curl -fsS -m 5 http://revisor/salud"]
```

(El archivo completo, con la plantilla, está en la carpeta de programas.) Lo que cambia respecto a `reporte`: el horario, un historial más corto y `backoffLimit: 0`, que quiere decir «sin reintentos»: una tarea que corre cada minuto no necesita reintentarse, porque el minuto siguiente es el reintento. La espera está a la vista: el guion mira cada 10 segundos cuántos Jobs ha terminado el CronJob y se detiene cuando son dos.

```bash
ctx && kubectl apply -f fig08_03.cron-cada-minuto.yaml
```

```text
$ date -u +%H:%M:%S
23:24:56

$ kubectl get cronjob reporte -n revisor
NAME      SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
reporte   */5 * * * *   <none>     False     0        <none>          20s

$ kubectl apply -f fig08_03.cron-cada-minuto.yaml
cronjob.batch/salud-cada-minuto created

(esperando hasta 200 s a que el CronJob cree y termine 2 Job(s) «salud-cada-minuto…»; se mira cada 10 s)
  +  0 s: 0 Job(s) terminados
  + 10 s: 1 Job(s) terminados
  + 20 s: 1 Job(s) terminados
  + 30 s: 1 Job(s) terminados
  + 40 s: 1 Job(s) terminados
  + 50 s: 1 Job(s) terminados
  + 60 s: 1 Job(s) terminados
  + 70 s: 2 Job(s) terminados
```

A los 10 segundos de crearlo ya había un Job terminado: el CronJob no esperó un minuto completo, sino el siguiente **minuto del reloj** (`:25:00`), que llegó 4 segundos después de las `23:24:56`. Un horario cron no cuenta «cada 60 segundos desde que me creaste»: dispara en los instantes que su fórmula marca en el reloj. Y a los 70 segundos, el segundo (el guion mira cada 10 segundos, y el minuto siguiente llegó a los 64).

```text
$ kubectl get cronjob,jobs -n revisor
NAME                              SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte             */5 * * * *   <none>     False     0        67s             91s
cronjob.batch/salud-cada-minuto   * * * * *     <none>     False     0        7s              71s

NAME                                   STATUS     COMPLETIONS   DURATION   AGE
job.batch/reporte-29877085             Complete   1/1           4s         67s
job.batch/reporte-manual-1             Complete   1/1           7s         86s
job.batch/reporte-manual-2             Complete   1/1           5s         77s
job.batch/salud-cada-minuto-29877085   Complete   1/1           4s         67s
job.batch/salud-cada-minuto-29877086   Complete   1/1           3s         7s
```

Hay mucho que leer aquí, y todo es evidencia de que el horario funciona:

- **`cronjob.batch/reporte` también corrió, solo.** `LAST SCHEDULE 67s` y un Job nuevo, `reporte-29877085`, que nadie creó: lo creó el CronJob a las `23:25:00`, el múltiplo de cinco minutos más cercano, mientras la lección esperaba otra cosa. La tarea real del proyecto ya está trabajando.
- **Los nombres de los Jobs.** `reporte-manual-1` lo nombraste tú. `reporte-29877085` lo nombró el CronJob: su nombre, un guion y un número. El número son los **minutos transcurridos desde el 1 de enero de 1970 (UTC)**, la época de Unix: `29877085 × 60` segundos es `2026-10-21T23:25:00Z`, y `29877086`, el minuto siguiente. Es un detalle observado, no documentado, que sirve para leer una lista de Jobs de un vistazo: dos números consecutivos son dos minutos seguidos. Y de aquí sale una restricción que la documentación sí dice: el nombre de un CronJob no debe pasar de 52 caracteres, porque, según la documentación, el controlador le agrega 11 caracteres y el nombre de un Job no puede pasar de 63 (en la corrida se agregaron 9: un guion y 8 dígitos; la documentación reserva más por prudencia).
- **El CronJob de cada minuto tiene dos Jobs, `…085` y `…086`**, de minutos consecutivos, y `LAST SCHEDULE 7s`: el último fue hace 7 segundos.

```text
$ kubectl logs -n revisor -l app=salud --prefix --tail=3
[pod/salud-cada-minuto-29877085-lbt8h/salud] 23:25:01
[pod/salud-cada-minuto-29877085-lbt8h/salud] {"estado":"vivo","version":"1.6.0"}
[pod/salud-cada-minuto-29877086-j7h2l/salud] 23:26:01
[pod/salud-cada-minuto-29877086-j7h2l/salud] {"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor -l app=salud -o custom-columns=NOMBRE:.metadata.name,PROGRAMADA:.metadata.annotations.batch\\.kubernetes\\.io/cronjob-scheduled-timestamp
NOMBRE                       PROGRAMADA
salud-cada-minuto-29877085   2026-10-21T23:25:00Z
salud-cada-minuto-29877086   2026-10-21T23:26:00Z
```

Mira las horas de las bitácoras: `23:25:01` y `23:26:01`; salen de ese `date -u +%T` que el comando de `fig08_03` imprime antes del `curl`. El Job estaba programado para las `:00`, pero el Pod empezó a correr 1 segundo después en los dos casos (en otra corrida del mismo guion fueron 5 y 9: el trecho cambia con la carga). Entre el instante del horario y el instante de la ejecución hay un trecho: el CronJob crea el Job, el Job crea el Pod, el planificador lo asigna y el `kubelet` arranca el contenedor. La anotación `batch.kubernetes.io/cronjob-scheduled-timestamp`, que el CronJob escribe en cada Job desde la versión 1.32, guarda la hora **original** del horario, en formato RFC 3339 (la forma `2026-10-21T23:25:00Z` que ves en la columna `PROGRAMADA`): sirve para saber qué ejecución fue cuál aunque se hayan retrasado. La documentación lo dice con una advertencia que conviene leer entera: un CronJob crea un Job «aproximadamente una vez por cada instante de su horario», y es aproximado porque «hay circunstancias en las que se podrían crear dos Jobs, o ninguno. Kubernetes intenta evitar esas situaciones, pero no las evita por completo. Por lo tanto, los Jobs que definas deben ser **idempotentes**».

**Idempotente**, en sentido estricto, quiere decir: correrlo dos veces deja el mundo igual que correrlo una. La tarea del reporte **no** es estrictamente idempotente: si por un tropiezo corriera dos veces en el mismo minuto, dejaría dos archivos y no uno. Lo que sí es: **segura ante repeticiones**. Como la hora del nombre lleva segundos, dos ejecuciones escriben dos archivos distintos y ninguno pisa al otro (si dos Pods corrieran en el mismo segundo exacto, el segundo reemplazaría al primero con un reporte equivalente, sin corromper nada). Una tarea que sumara un contador o enviara un correo no sería segura así, y habría que protegerla de otra forma, por ejemplo con una clave única por horario. Esa es la razón de fondo de que los nombres lleven la hora y no un número consecutivo.

Se borra el CronJob de práctica, y con él sus Jobs y Pods:

```text
$ kubectl delete -f fig08_03.cron-cada-minuto.yaml
cronjob.batch "salud-cada-minuto" deleted from revisor namespace

$ kubectl get jobs,pods -n revisor -l app=salud
No resources found in revisor namespace.
```

Dos cosas más que la documentación del CronJob enseña, aunque esta lección no las corre. La primera: `.spec.suspend: true` suspende las ejecuciones siguientes sin borrar nada; las que caen mientras está suspendido cuentan como perdidas. La segunda: `startingDeadlineSeconds` dice cuántos segundos después de su hora se puede todavía crear el Job, y si se pasa, esa ejecución se salta. Sin este campo, un controlador caído un par de horas puede dejar muchas ejecuciones pendientes; la documentación explica que, si hay más de 100 perdidas desde la última, el CronJob se niega a iniciar y registra un error. En producción, con tareas importantes, conviene fijarlo.

### 8.7 El dueño de los archivos: `fsGroup`

#### 8.7.1 Lo que `fsGroup` cambió, y lo que no

Desde la Lección 4, el Deployment del `revisor` lleva `fsGroup: 65532` y el CronJob, `fsGroup: 101`. Es momento de dar la historia completa. La [guía del contexto de seguridad](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) lo explica con un ejemplo. Un Pod con `fsGroup: 2000` hace que «todos los procesos del contenedor sean también parte del grupo suplementario 2000», y «el dueño del volumen `/data/demo` y de cualquier archivo creado en ese volumen será el grupo 2000». Su salida de ejemplo es el directorio con grupo 2000 y permisos `drwxrwsrwx`, el mismo patrón que ya viste. Y en la sección de discusión: `fsGroup` aplica a los volúmenes «que soportan administración de dueños», que se modifican para que sean del grupo que indica `fsGroup` y escribibles por él.

Esas dos palabras, **que soportan**, son las que se miden aquí. Los tres volúmenes de la lección, uno al lado del otro. El último comando necesita el nombre del nodo y el `uid` de una réplica **de tu clúster**, que son otros; se obtienen así:

```bash
REV_POD="$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
REV_NODE="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.spec.nodeName}')"
REV_UID="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.metadata.uid}')"
docker exec "$REV_NODE" stat -c '%a %u:%g %n' "/var/lib/kubelet/pods/$REV_UID/volumes/kubernetes.io~empty-dir/datos"
```

La salida de la corrida, con el nodo y el `uid` de esa réplica:

```text
$ kubectl get pod -n revisor -l app=revisor -o jsonpath='{.items[0].spec.securityContext.fsGroup}{"\n"}'
65532

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.securityContext}{"\n"}'
{"fsGroup":101,"runAsGroup":101,"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}}

$ docker exec curso-k8s-l8-worker2 stat -c '%a %u:%g %n' /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
2777 0:65532 /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
```

Ahí están los dos `fsGroup` declarados (65532 en el `revisor`, 101 en la tarea). Y el `stat` del `emptyDir` de un `revisor` actual: `2777` y grupo `65532`: **en el `emptyDir`, `fsGroup` sí cambió el grupo y puso el *setgid***. En cambio, el volumen de la solicitud `reportes` (8.5.2) tenía `777 0:0` aunque su Pod declaraba `fsGroup: 101`. La razón, como lo contó el README del aprovisionador y lo confirma la medición: el aprovisionador crea una carpeta común del nodo con permiso `0777`, y la medición muestra que el `kubelet` no le cambió el grupo (la documentación solo dice que `fsGroup` actúa sobre los volúmenes «que soportan administración de dueños» y no da la lista; lo que medimos es que en este volumen no lo hizo, y que en el `emptyDir` y en el volumen `local` de 8.7.2 sí. El PV que crea este aprovisionador es de tipo `hostPath`: la columna `RUTA` de 8.5.2 sale de `spec.hostPath.path`). Tampoco hizo falta: con `777`, cualquier usuario escribe.

Esto no es un descuido del curso: es una diferencia entre la clase `standard` de kind y un disco que nace con dueño `root` y permiso `755`, como el que 8.7.2 fabrica a mano. Ahí, un contenedor que corre como usuario 100 recibe `Permission denied` al intentar escribir, **a menos que** `fsGroup` le dé el grupo del directorio. Con la clase `standard` de kind es poco probable que veas ese error, y ese es justo el peligro: un manifiesto que funciona porque la carpeta es `777` puede fallar en otro clúster por la misma razón por la que `fsGroup` existe. Un manifiesto que ya lleva `fsGroup` está más cerca de funcionar con un disco así. Por eso el curso lo escribe aunque aquí no se note.

#### 8.7.2 Un disco como los de verdad

Para ver `fsGroup` trabajando hace falta un volumen que sí lo soporte. Kubernetes tiene uno a mano: el tipo `local`, una carpeta de un nodo presentada como un disco (la documentación lo describe como «un dispositivo de almacenamiento local montado: un disco, una partición o un directorio»). A diferencia del aprovisionador de kind, aquí **tú** eres el administrador: creas la carpeta en el nodo, creas el PV que la describe, y creas la solicitud que lo reclama. Es el camino estático de 8.3.2. Se usa como ejemplo `fig08_04.disco-local.yaml`, un **programa** con dos objetos:

```yaml
# fig08_04.disco-local.yaml — Lección 8: un volumen creado a mano por «el administrador»,
# como los de un clúster real. Un PersistentVolume de tipo local (una carpeta de UN nodo,
# que hay que crear antes: mkdir -p /mnt/disco-reportes dentro del nodo curso-k8s-l8-worker)
# y la solicitud (PersistentVolumeClaim) que lo reclama. Su clase «manual» no existe como
# objeto: sirve solo de etiqueta para que la solicitud encuentre este volumen y no pida uno
# nuevo a la clase por omisión.
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disco-reportes
spec:
  capacity:
    storage: 100Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  local:
    path: /mnt/disco-reportes
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [curso-k8s-l8-worker]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: disco
  namespace: revisor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources:
    requests:
      storage: 100Mi
```

Los campos nuevos del PV: **`capacity`** es el tamaño que ofrece; **`persistentVolumeReclaimPolicy: Retain`** es la política de reclamación que 8.8 mide; **`local.path`** es la carpeta del nodo; y **`nodeAffinity`** es obligatoria en un volumen `local`: la documentación dice «debes poner un `nodeAffinity` en el PersistentVolume cuando uses volúmenes `local`. El planificador de Kubernetes usa esa afinidad para programar los Pods en el nodo correcto». Aquí dice que el volumen está en el nodo cuyo nombre es `curso-k8s-l8-worker`. La clase `manual` no existe como objeto; es solo una palabra que une los dos objetos entre sí y evita que la solicitud caiga en la clase por omisión. Que la solicitud no falle por una clase inexistente (como pasa en el Ejercicio 1) tiene una explicación: el aprovisionamiento dinámico solo se intenta cuando ningún volumen que ya existe coincide con la solicitud, y aquí el PV existía.

La carpeta del nodo se prepara primero, con permisos de `root` y modo `755`, como la dejaría un disco recién formateado, y después se aplica el archivo:

```bash
docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes
docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
ctx && kubectl apply -f fig08_04.disco-local.yaml
```

```text
$ docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
755 0:0 /mnt/disco-reportes

$ kubectl apply -f fig08_04.disco-local.yaml
persistentvolume/disco-reportes created
persistentvolumeclaim/disco created

$ kubectl get pv,pvc -n revisor
NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/disco-reportes                             100Mi      RWO            Retain           Bound    revisor/disco      manual         <unset>                          0s
persistentvolume/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound    revisor/reportes   standard       <unset>                          85s

NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/disco      Bound    disco-reportes                             100Mi      RWO            manual         <unset>                 0s
persistentvolumeclaim/reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 94s
```

El `stat` del nodo dice `755 0:0`: de `root`, y solo `root` puede escribir. El PV `disco-reportes` nace `Bound` (unido) en el mismo segundo en que existe, con política `Retain`, y la solicitud `disco` también sale `Bound` en esta captura. Ojo: el instante importa. En otras dos corridas del mismo guion la captura cayó antes de que la unión terminara: una vez con la solicitud todavía `Pending` y el volumen ya `Bound`, otra con el volumen todavía `Available`. La unión tarda una fracción de segundo; si en tu terminal ves `Pending`, repite el `get` y se completa. No hubo espera de primer consumidor: la clase `manual` no es una clase con modo de unión retardado, y el volumen ya existía. Más abajo, el volumen `pvc-5fcf36b8-…` es el de `reportes`, con la política `Delete` de su clase. En un clúster real no dejarías la clase como etiqueta suelta: la documentación pide crear una `StorageClass` para los volúmenes `local` con `volumeBindingMode: WaitForFirstConsumer`, para que la solicitud no se una a un disco de un nodo antes de saber dónde va a correr el Pod. Aquí se omite porque hay un solo PV y su afinidad decide el nodo.

Ahora, dos Pods que hacen lo mismo y solo se diferencian en una línea. Escriben un archivo en `/datos`, corriendo como el usuario 100 y el grupo 101, sin `root`. El primero, `fig08_05.escritor-sin-fsgroup.yaml`, no declara `fsGroup`:

```yaml
# fig08_05.escritor-sin-fsgroup.yaml — Lección 8: un Pod que corre sin root (usuario 100,
# grupo 101) e intenta escribir en el disco local de fig08_04, cuyo directorio es de root
# con permiso 0755. Sin fsGroup, nadie le cambia el dueño al directorio: Permission denied.
apiVersion: v1
kind: Pod
metadata:
  name: sin-fsgroup
  namespace: revisor
  labels:
    app: escritor
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
  - name: escritor
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sh", "-c", "id; ls -lnd /datos; echo hola > /datos/a.txt && ls -ln /datos"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
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
    persistentVolumeClaim:
      claimName: disco
```

El segundo, `fig08_06.escritor-con-fsgroup.yaml`, es el mismo archivo con `name: con-fsgroup` y una línea más en el `securityContext` del Pod: `fsGroup: 101`. El comando de ambos es corto: `id` imprime quién es el proceso; `ls -lnd /datos` imprime el dueño y permiso del directorio montado; y `echo hola > /datos/a.txt && ls -ln /datos` intenta escribir y, si pudo, lista.

```bash
ctx && kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
```

```text
$ kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
pod/sin-fsgroup created

$ kubectl get pod -n revisor sin-fsgroup
NAME          READY   STATUS   RESTARTS   AGE
sin-fsgroup   0/1     Error    0          4s

$ kubectl logs -n revisor sin-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxr-xr-x    2 0        0             4096 Oct 21 23:26 /datos
sh: can't create /datos/a.txt: Permission denied
```

Ése es el error que `fsGroup` evita, medido. Se lee en tres renglones: el proceso es el usuario 100, con el grupo 101 y ningún otro; el directorio es de `0:0` con `drwxr-xr-x` (solo `root` escribe: el usuario 100 cae en la categoría «otros», que tiene lectura y entrada, pero no escritura); y el `sh` lo dice sin rodeos, `can't create /datos/a.txt: Permission denied`. El Pod quedó en `Error`: el comando falló, y con `restartPolicy: Never` no se reinicia. Ahora el mismo Pod con la línea más:

```bash
ctx && kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
ctx && kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
```

```text
$ kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
pod "sin-fsgroup" deleted from revisor namespace

$ kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
pod/con-fsgroup created

$ kubectl get pod -n revisor con-fsgroup
NAME          READY   STATUS      RESTARTS   AGE
con-fsgroup   0/1     Completed   0          3s

$ kubectl logs -n revisor con-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxrwsr-x    2 0        101           4096 Oct 21 23:26 /datos
total 4
-rw-r--r--    1 100      101              5 Oct 21 23:26 a.txt

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
2775 0:101 /mnt/disco-reportes
```

`Completed`, y el archivo `a.txt` de 5 bytes (`hola` y un salto de línea) escrito. Mira el directorio en la bitácora: `drwxrwsr-x`, grupo `101`. Y en el nodo, `stat` dice `2775 0:101`: **el `kubelet` cambió el grupo de la carpeta al 101 y le dio permiso de escritura a ese grupo, con *setgid*, antes de arrancar el contenedor**. El proceso es del grupo 101, y por eso puede escribir. El dueño sigue siendo `root`; lo que cambió es el grupo. Es lo que dice la documentación: los volúmenes que soportan administración de dueños «se modifican para que sean del GID que indica `fsGroup` y escribibles por él».

El *setgid* (la `s`) tiene un efecto práctico que hace que `fsGroup` valga la pena: los archivos que se creen dentro del directorio **heredan su grupo**, el 101, y no el grupo primario del proceso que los crea. Aquí el efecto no se nota, porque el proceso ya es del grupo 101 (`runAsGroup: 101`); sí se notaría en un proceso con otro grupo primario. Y para que otro Pod del grupo 101 pueda *modificar* esos archivos, cada archivo necesitaría permiso de grupo (umask 002), cosa que esta tarea no pide: sus archivos salen `-rw-r--r--`.

Una nota de costo, que la documentación del contexto de seguridad explica: por omisión, Kubernetes cambia el dueño y los permisos de **todo el contenido** del volumen cada vez que se monta. Para un volumen con millones de archivos, eso tarda y retrasa el arranque del Pod. El campo `fsGroupChangePolicy: OnRootMismatch` pide que el cambio se haga solo si el dueño o el permiso de la raíz del volumen no coinciden con lo esperado, y evita recorrerlo cuando ya está en orden. Con volúmenes de 100 Mi no se nota; con discos grandes, sí.

#### 8.7.3 Retain: el volumen sobrevive a su solicitud

Los dos Pods ya no hacen falta. Y el disco a mano sirve, además, para ver lo que no se puede ver con `Delete`: la política `Retain`. Se borra la solicitud:

```bash
ctx && kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
ctx && kubectl delete pvc -n revisor disco
```

```text
$ kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
pod "con-fsgroup" deleted from revisor namespace

$ kubectl delete pvc -n revisor disco
persistentvolumeclaim "disco" deleted from revisor namespace

$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
disco-reportes                             100Mi      RWO            Retain           Released   revisor/disco      manual         <unset>                          11s
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound      revisor/reportes   standard       <unset>                          96s
```

La solicitud se fue; el volumen **no**. Su estado es `Released` («liberado»), que la documentación define así: «la solicitud ha sido borrada, pero el recurso de almacenamiento asociado todavía no ha sido reclamado por el clúster». Con `Retain`, el volumen se queda con su `CLAIM revisor/disco` anotado y no está disponible para otra solicitud, porque «los datos del reclamante anterior siguen en el volumen». Recuperarlo es un trabajo manual del administrador, en tres pasos que dice la documentación: borrar el PV, limpiar los datos del almacenamiento y borrar el almacenamiento asociado (o reutilizarlo con un PV nuevo). Se borra el PV y se mira el disco:

```text
$ kubectl delete pv disco-reportes
persistentvolume "disco-reportes" deleted

$ docker exec curso-k8s-l8-worker ls -ln /mnt/disco-reportes
total 4
-rw-r--r-- 1 100 101 5 Oct 21 23:26 a.txt
```

El objeto PV desapareció de Kubernetes; la carpeta del nodo, y el archivo `a.txt` que escribió el Pod, siguen ahí. Eso es `Retain`: el clúster suelta el objeto y no toca los datos. Es la política que se escoge para datos que no deben desaparecer por un `kubectl delete` equivocado, a cambio de un trabajo de limpieza manual. (La carpeta vive dentro del contenedor del nodo, así que `kind delete cluster` se la lleva. Si quisieras que unos datos sobrevivan al clúster entero, la [configuración de kind](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts) permite montar una carpeta de tu máquina dentro de un nodo con `extraMounts`; el curso no lo hace.)

### 8.8 Borrar la solicitud: ahí sí se pierde

La política de la clase `standard` es `Delete`. Se mide qué pasa con la solicitud `reportes`, la que guarda los reportes de la lección. Primero se mira la política, luego se pide el borrado **sin esperar** (`--wait=false`), porque lo que sigue puede quedarse esperando:

```bash
ctx && kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
ctx && kubectl delete pvc -n revisor reportes --wait=false
```

```text
$ kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
Delete

$ kubectl delete pvc -n revisor reportes --wait=false
persistentvolumeclaim "reportes" deleted from revisor namespace

$ kubectl get pvc -n revisor
NAME       STATUS        VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Terminating   pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 111s

$ kubectl get pvc -n revisor reportes -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}{"\n"}'
["kubernetes.io/pvc-protection"] 2026-10-21T23:26:21Z

$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-29877085-6q87g   0/1     Completed   0          86s
reporte-manual-1-t7d8l   0/1     Completed   0          105s
reporte-manual-2-4hmmf   0/1     Completed   0          96s
```

`Terminating`: pidió que se borre y no se borra. El comando devolvió el control porque tenía `--wait=false`; sin esa opción, `kubectl delete` se habría quedado esperando. La explicación está en `finalizers: ["kubernetes.io/pvc-protection"]`, que es una *marca* que impide que un objeto desaparezca hasta que algo la quite. La documentación llama a esta función **protección de objetos de almacenamiento en uso**, y su propósito es «asegurar que las solicitudes en uso activo por un Pod, y los volúmenes unidos a solicitudes, no se quiten del sistema, ya que esto podría resultar en pérdida de datos». Y define qué es «en uso activo»: **una solicitud está en uso cuando existe un objeto Pod que la usa.** Si la borras en ese caso, «el borrado se pospone hasta que ninguno la use».

Mira la última salida: tres Pods `Completed`. Terminaron hace tiempo y ya no corren, pero **existen como objetos** (se conservaron para leer su bitácora), y cada uno declara en sus volúmenes la solicitud `reportes`. Para la protección, siguen usándola. La solicitud espera a que esos Pods dejen de existir. La salida no es forzar el borrado, sino quitar a quienes la sostienen: borrar los Jobs, que se llevan sus Pods.

```bash
ctx && kubectl delete jobs -n revisor --all
```

```text
$ kubectl delete jobs -n revisor --all
job.batch "reporte-29877085" deleted from revisor namespace
job.batch "reporte-manual-1" deleted from revisor namespace
job.batch "reporte-manual-2" deleted from revisor namespace

$ kubectl get pvc,pv
No resources found

$ docker exec curso-k8s-l8-worker ls -la /var/local-path-provisioner/
total 8
drwxr-xr-x  2 root root 4096 Oct 21 23:26 .
drwxr-xr-x 12 root root 4096 Oct 21 23:24 ..
```

En cuanto los Pods se fueron, el borrado de la solicitud avanzó: ya no hay solicitud ni volumen (`No resources found`), y la carpeta del nodo, `pvc-5fcf36b8-…_revisor_reportes`, **desapareció con todos sus reportes**. El directorio `/var/local-path-provisioner/` quedó vacío. Es la política `Delete` en acción: se borra la solicitud, se borra el volumen y se borra el almacenamiento. En el borrado de la corrida no se alcanzó a ver el estado intermedio `Released` del volumen dinámico (el guion miró 8 segundos después de borrar los Jobs y para entonces el volumen ya no existía; no sé en cuánto tiempo exacto desapareció); el de 8.7.3, con `Retain`, sí lo mostró.

Recrear la solicitud y pedir una tarea nueva muestra lo que queda: nada del pasado.

```bash
ctx && kubectl apply -k . | grep persistentvolumeclaim
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
```

```text
$ kubectl apply -k . | grep persistentvolumeclaim
persistentvolumeclaim/reportes created

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
job.batch/reporte-manual-3 created

$ kubectl logs -n revisor job/reporte-manual-3
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
```

Un solo archivo: el de ahora. Los reportes del pasado no están. Con esto, la regla de la sección queda en una frase para cuando algún día lo hagas sin querer: **con la política `Delete`, los datos viven lo que viva la solicitud y el borrado de la solicitud se lleva los datos; con `Retain`, sobreviven a ella y alguien tiene que limpiarlos** (8.7.3). La política es de la clase, no de quien borra: por eso conviene saber cuál es la clase antes de borrar nada que se llame `pvc`.

## El error que vas a ver

Esta lección tiene dos errores a propósito. El segundo ya lo viste en 8.7.2: el `Permission denied` del Pod que escribe en un volumen de `root` sin `fsGroup`. El primero es el de una tarea que nunca llega al `revisor`.

### BackoffLimitExceeded: un Job que no puede salir

`fig08_02.job-sin-etiqueta.yaml` es el Job de práctica de 8.5.1 con **una** diferencia: le falta la etiqueta `acceso-revisor: permitido`. Es el error que se comete al copiar una plantilla y olvidar una línea que no se ve.

```bash
diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
ctx && kubectl apply -f fig08_02.job-sin-etiqueta.yaml
```

El `diff` no lo corre el guion (no toca el clúster); esta es su salida, corrida en la carpeta de programas. Además de los comentarios del encabezado y del nombre, la única diferencia de contenido es la línea de la etiqueta:

```text
$ diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
1,3c1,4
< # fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
< # a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
< # cerrada de la Lección 7 exige para que un Pod hable con el revisor.
---
> # fig08_02.job-sin-etiqueta.yaml — Lección 8: el MISMO Job de fig08_01, sin la etiqueta
> # acceso-revisor. La red cerrada de la Lección 7 no lo deja salir hacia el revisor: curl se
> # rinde a los 5 s (código 28), el Job reintenta dos veces y termina Failed con
> # BackoffLimitExceeded.
7c8
<   name: salud
---
>   name: salud-sin-etiqueta
16d16
<         acceso-revisor: permitido
```

Un Job así no falla de inmediato. Reintenta, con las esperas que 8.5.1 contó, y la lección lo mira a la vista, cada 15 segundos:

```text
$ kubectl apply -f fig08_02.job-sin-etiqueta.yaml
job.batch/salud-sin-etiqueta created

(esperando hasta 150 s a que el Job agote sus reintentos; se mira cada 15 s)
  + 15 s: 1 fallidos,  activos, condiciones:
  + 30 s: 2 fallidos,  activos, condiciones:
  + 45 s: 2 fallidos, 1 activos, condiciones:
  + 60 s: 3 fallidos,  activos, condiciones: FailureTarget=True Failed=True

$ kubectl get job,pods -n revisor -l app=salud
NAME                           STATUS   COMPLETIONS   DURATION   AGE
job.batch/salud-sin-etiqueta   Failed   0/1           61s        61s

NAME                           READY   STATUS   RESTARTS   AGE
pod/salud-sin-etiqueta-9bnv9   0/1     Error    0          61s
pod/salud-sin-etiqueta-svs9r   0/1     Error    0          44s
pod/salud-sin-etiqueta-tr95q   0/1     Error    0          19s
```

**Primero, el estado.** A los 61 segundos, el Job está `Failed` y tiene tres Pods, los tres `Error`. Son exactamente los que dijo `backoffLimit: 2`: el original y dos reintentos. Las edades (`61s`, `44s`, `19s` desde que se crearon, leídas al revés) cuentan la espera creciente de la documentación: el segundo Pod nació 17 segundos después del primero (5 de `curl` más 10 de espera) y el tercero 25 después del segundo (5 más 20). No son segundos redondos porque el clúster agrega unos de más al crear Pods.

**Segundo, la bitácora, porque el contenedor sí corrió.**

```text
$ kubectl logs -n revisor job/salud-sin-etiqueta
Found 3 pods, using pod/salud-sin-etiqueta-9bnv9
curl: (28) Connection timed out after 5000 milliseconds

$ kubectl get pods -n revisor -l app=salud -o custom-columns=POD:.metadata.name,CODIGO:.status.containerStatuses[0].state.terminated.exitCode,RAZON:.status.containerStatuses[0].state.terminated.reason
POD                        CODIGO   RAZON
salud-sin-etiqueta-9bnv9   28       Error
salud-sin-etiqueta-svs9r   28       Error
salud-sin-etiqueta-tr95q   28       Error
```

`kubectl logs job/…` avisa que hay tres Pods y que muestra uno. El mensaje de `curl` es el que conoces de la Lección 7: **código 28**, «la conexión expiró». La red cerrada no deja salir a un Pod sin la etiqueta de acceso hacia el `revisor`, y no contesta con un rechazo: simplemente no contesta, y `curl` espera sus 5 segundos (`-m 5`) y se rinde. Los tres Pods terminaron con código 28. Es la misma falla de «la entrada abierta que no entra» de la Lección 7, vista desde una tarea.

**Tercero, el Job: por qué se rindió.**

```text
$ kubectl get job -n revisor salud-sin-etiqueta -o jsonpath='{range .status.conditions[*]}{.type} {.status} {.reason}: {.message}{"\n"}{end}'
FailureTarget True BackoffLimitExceeded: Job has reached the specified backoff limit
Failed True BackoffLimitExceeded: Job has reached the specified backoff limit

$ kubectl describe job -n revisor salud-sin-etiqueta | sed -n '/^Events:/,$p'
Events:
  Type     Reason                Age   From            Message
  ----     ------                ----  ----            -------
  Normal   SuccessfulCreate      62s   job-controller  Created pod: salud-sin-etiqueta-9bnv9
  Normal   SuccessfulCreate      45s   job-controller  Created pod: salud-sin-etiqueta-svs9r
  Normal   SuccessfulCreate      20s   job-controller  Created pod: salud-sin-etiqueta-tr95q
  Warning  BackoffLimitExceeded  10s   job-controller  Job has reached the specified backoff limit
```

`BackoffLimitExceeded` («se excedió el límite de reintentos») es la razón del fallo, tal como la documentación lista las causas por las que un Job falla: «el número de fallas de Pods excedió el `.spec.backoffLimit`». Los eventos, de arriba abajo, son la historia en cuatro renglones: tres creaciones y la rendición.

**Cuarto, la causa, que el Job no sabe decir.** Nada de lo anterior dice *por qué* el `curl` expira. Eso lo dice la comparación con lo que sí funciona. `depurar`, que en 8.1 hablaba bien con el `revisor`, lleva una etiqueta que este Job no tiene:

```text
$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          3m36s   acceso-revisor=permitido,app=depurar
```

`acceso-revisor=permitido` es la etiqueta que las políticas de red de la Lección 7 piden. El Job de la Lección, el `CronJob` real, la lleva en su plantilla, con un comentario que lo explica; este no. **La corrección** es la de siempre: el archivo es la verdad. Se agrega la línea al manifiesto y se vuelve a aplicar; aquí, simplemente, se borra el experimento:

```text
$ kubectl delete -f fig08_02.job-sin-etiqueta.yaml
job.batch "salud-sin-etiqueta" deleted from revisor namespace
```

Dos lecciones de este error. **La primera**: un Job que falla dice que falló, no por qué; la causa está en la bitácora de sus Pods (`curl: (28)`) y en lo que sabes de la red. **La segunda**: una tarea programada que falla a las 3 de la madrugada no despierta a nadie. El `CronJob` conserva los últimos tres Jobs fallidos (`failedJobsHistoryLimit: 3`) justo para que alguien, al día siguiente, pueda ir a leer qué les pasó. Sin vigilancia, una tarea que falla en silencio durante semanas produce lo contrario de lo que prometía: la sensación de que hay un respaldo donde no lo hay. Es la lección del relato de GitLab que abrió la lección, en pequeño.

El orden para una tarea que no funcionó: `kubectl get jobs` (¿`Failed`?); los Pods del Job (`kubectl get pods -l …`) y el código de salida de cada uno; la bitácora (`kubectl logs job/…`); y, si el Job no creó ni un Pod, los eventos del propio Job (`kubectl describe job`). Antes de cambiar nada, saber si falló una vez, siempre, o a veces.

## El hábito de seguridad de la lección: los datos con su dueño

La tabla de hábitos del curso le asigna a esta lección dos cosas: el `ServiceAccount` sin credenciales montadas si no las necesita, y los datos con su dueño. Las dos se comprueban en el clúster.

**La cuenta de servicio de la tarea.** La tarea le habla al `revisor` por HTTP; no le habla a la API del clúster. No necesita una credencial para eso, y por tanto no se le monta:

```text
$ kubectl get serviceaccount reporte -n revisor -o jsonpath='{.automountServiceAccountToken}{"\n"}'
false

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.automountServiceAccountToken}{" "}{.spec.jobTemplate.spec.template.spec.containers[0].env}{"\n"}'
false

$ kubectl get pods -n revisor -l app=reporte -o custom-columns=POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name
POD                      CUENTA    AUTOMOUNT   VOLUMENES
reporte-manual-3-2657n   reporte   false       datos,token

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/api/estados
401
```

`false` en la cuenta, `false` en la plantilla del CronJob, y `env` vacío (el segundo valor de la segunda salida es nada: la tarea no recibe variables con secretos). Los volúmenes del Pod de la tarea son dos y se llaman `datos` y `token`: **ninguno es la credencial de la API**. Si alguien lograra ejecutar código dentro de la tarea, no encontraría un token del clúster que robar. Y el token del `revisor` va como archivo de solo lectura con `0440`, no como variable de entorno: es lo que la Lección 4 enseñó. La última salida es la prueba de que el `revisor` sigue pidiéndolo: sin token, `401`.

**Los datos con su dueño.** Las tres piezas que se midieron:

- **El grupo del volumen lo pone `fsGroup`**, no un permiso abierto. En un disco real, la solución a un `Permission denied` es dar el grupo, no `chmod 777`. En 8.7.2 el volumen era de `root` con `755`, y con una línea quedó en `2775 0:101`: de `root`, grupo 101, escribible solo por ese grupo (y legible por todos).
- **El proceso corre sin `root`** y el archivo que crea es suyo: `-rw-r--r-- 1 100 101` en la tarea; `-rw------- 1 65532 65532` en el `revisor`. Cada escritor deja su marca, y se puede saber quién escribió qué.
- **El token no llega al volumen de datos.** La tarea lee el token de `/secretos`, un volumen de solo lectura, y escribe solo en `/datos`. Mantener separadas la entrada y la salida impide que un error de la tarea escriba el secreto en un lugar donde se conserve.

**El tamaño que el clúster no hace respetar.** Falta una sorpresa, la de la sección 8.4.1, donde se comentó que habría algo que decir sobre qué tan en serio se toma un clúster el número `100Mi`. El volumen pidió 100 mebibytes y el clúster dijo `CAPACITY 100Mi`. Se prueba con un Job, `fig08_07.llenar-el-volumen.yaml`, que escribe 150 millones de bytes (unos 143 MiB) en ese mismo volumen:

```bash
ctx && kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
ctx && kubectl apply -f fig08_07.llenar-el-volumen.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/llenar --timeout=180s
ctx && kubectl logs -n revisor job/llenar
ctx && kubectl delete -f fig08_07.llenar-el-volumen.yaml
```

(El `wait` evita pedir la bitácora antes de que el Pod termine de escribir; el guion lo corre sin imprimirlo.)

```text
$ kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
100Mi 100Mi

$ kubectl apply -f fig08_07.llenar-el-volumen.yaml
job.batch/llenar created

$ kubectl logs -n revisor job/llenar
total 146496
-rw-r--r--    1 100      101      150000000 Oct 21 23:27 grande.bin
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
/dev/root                57.1G     48.4G      8.6G  85% /datos

$ kubectl delete -f fig08_07.llenar-el-volumen.yaml
job.batch "llenar" deleted from revisor namespace
```

El Job terminó sin error y `ls` muestra `grande.bin` de **150000000 bytes** en un volumen que pidió y recibió 100Mi. Y el `df` de adentro del Pod enseña el motivo: el «volumen» `/datos` aparece como `/dev/root`, de 57.1 GB, con el 85 % usado: es el disco del nodo, que en kind es el de la máquina de Docker, no un trozo de 100 Mi (el nombre del dispositivo y el tamaño cambian en tu máquina). Es exactamente lo que el README del aprovisionador anunció («la capacidad se ignora por ahora»): el número de `storage` decide con qué PV se une la solicitud, pero la clase de kind no limita lo que se escribe.

Este es un hallazgo de laboratorio que conviene no olvidar: **con la clase de kind, lo que pides no es lo que obtienes; en otros almacenamientos depende del sistema, y conviene medirlo**. En un clúster real, el almacenamiento de verdad sí tiene tamaño y se llena (con un error `No space left on device` que tumba a la aplicación a media escritura), y un espacio de nombres sin cuota puede crear solicitudes de cualquier tamaño. La cuota de almacenamiento (`ResourceQuota`, con `requests.storage`) pone un máximo por espacio de nombres, como se comentó en la Lección 5 para la CPU y la memoria; el curso la nombra y no la instala.

**Lo que defiende y lo que no.** Estas costumbres protegen que la tarea no tenga más poder del que necesita, que el token no se filtre al disco, y que los archivos tengan un dueño identificable. No protegen los datos: un `Delete` los borra (8.8), un nodo caído los vuelve inaccesibles (el volumen está en un solo disco), y nadie los respalda. Lo que cuida los datos de verdad es la fila que la lección 10 pone en la lista de lo que falta para producción: almacenamiento replicado fuera del nodo, instantáneas de volumen y respaldos que se **prueben** restaurando. Una frase sobre cada uno, para que sepas qué problema resuelve: un `StatefulSet` es el objeto para aplicaciones con estado, cuyos Pods tienen identidad estable y un volumen propio cada uno (el curso no lo usa); una instantánea de volumen es una copia del volumen en un instante, que sirve para volver atrás; y un respaldo probado es la copia que alguien ya restauró en otro lugar y comprobó, que es justo lo que le faltó al relato de GitLab del principio.

## Lo que se hace mal

**Guardar en un `emptyDir` lo que debe sobrevivir al Pod.** Lo viste en 8.2.3: el contenedor se salva de una caída, el Pod no se salva de un borrado, y vaciar un nodo (`drain`), una evicción o un nodo declarado perdido borran Pods; un reinicio del nodo no necesariamente, pero tampoco conviene apostar a ello. Un `emptyDir` es para espacio de trabajo, no para historia.

**Creer que `Pending` en una solicitud es un error.** Con `WaitForFirstConsumer`, una solicitud sin Pod se queda `Pending` correctamente. Se lee el evento antes de actuar.

**Poner `storage: 100Mi` y creer que ahí termina.** En kind, el tamaño no se hace cumplir (lo mide «El hábito de seguridad»). En producción, el disco se llena. Hay que vigilar el uso, con alertas, antes de que llegue al tope.

**Borrar una solicitud (`pvc`) sin saber la política de la clase.** Con `Delete`, se borran los datos. Con `Retain`, se conservan y alguien debe limpiarlos. Se mira `RECLAIMPOLICY` antes.

**Borrar un PV a mano para «liberar» una solicitud atorada.** La solicitud en `Terminating` espera a los Pods que la usan; el PV tiene su propia protección. Forzar finalizadores (`kubectl patch … finalizers`) saltándose la protección es la forma de dañar datos en uso. Se encuentra y se borra lo que la sostiene (en esta lección, los Jobs).

**Usar `chmod 777` o un volumen abierto para que «ya escriba».** Es lo que hace el aprovisionador de kind, y por eso rara vez se nota el problema. En un disco de verdad el remedio es `fsGroup` y un usuario sin `root`, no abrir el directorio a todos.

**Escribir una tarea que no soporta correr dos veces.** La documentación lo avisa: el CronJob puede crear dos Jobs o ninguno. Una tarea que suma, envía o cobra sin protección es un duplicado esperando.

**Dejar `concurrencyPolicy: Allow` por omisión en una tarea que escribe en un volumen compartido.** Dos tareas a la vez en la misma carpeta, y una tarea lenta que se encima con la siguiente, pueden acumular Pods sin que nadie lo note. `Forbid` o `Replace` dicen explícitamente qué quieres.

**Un Job sin `backoffLimit` ni `activeDeadlineSeconds`.** El valor por omisión de reintentos es 6 y el tiempo no tiene tope: una tarea colgada se queda colgada. Se ponen los dos en las tareas de verdad, con números que se puedan justificar (los Jobs de práctica de la lección, que duran segundos, no los llevan todos).

**Un CronJob sin historial o con un historial enorme.** Sin historial (`0`), no hay evidencia de lo que falló. Con un número muy grande, se acumulan Jobs y Pods por miles. Se escoge un número pequeño y se revisa.

**Dar a la tarea una cuenta de servicio con permisos «por si acaso».** La tarea que solo habla HTTP no necesita credencial de la API. `automountServiceAccountToken: false` y una cuenta propia sin permisos.

**Poner el token en el comando o en una variable de entorno de la tarea.** Se lee del archivo montado en el momento de correr, como hace la tarea de la lección.

**Olvidar la zona horaria de un CronJob.** Sin `timeZone`, el horario es el del controlador (UTC en kind). «Todos los días a las 3» no es lo que crees si estás a seis horas de UTC.

**Guardar el reporte de todas las réplicas en un volumen `ReadWriteOnce` local.** El Ejercicio 2 lo prueba: ata todas las réplicas a un solo nodo.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden y desde el estado en que quedó después del «hábito de seguridad». Antes de cada uno, la función `ctx` debe darte éxito (`ctx && echo ok`). **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — Una clase de almacenamiento que no existe

`fig08_08.pvc-clase-inexistente.yaml` crea una solicitud de volumen que pide la clase `rapido` (que este clúster no tiene) y un Pod, `lector`, que la usa. Aplícalo. Antes de mirar, predice: ¿en qué estado queda la solicitud? ¿En cuál, el Pod? ¿Qué evento crees que da cada uno, y quién lo emite? Compruébalo con `kubectl get pvc rapido -n revisor`, `kubectl get pod lector -n revisor` y los `describe` de los dos. Y la pregunta difícil: ¿cuánto tiempo esperarías antes de concluir que no se va a resolver solo? Al terminar, bórralo con `kubectl delete -f fig08_08.pvc-clase-inexistente.yaml`.

### Ejercicio 2 — El reporte del `revisor`, en el volumen

La decisión del curso es que el `revisor` guarde su `reporte.json` en el `emptyDir` y que la tarea guarde los suyos en el volumen. Compruébalo con un cambio de una línea. Con `kubectl patch`, reemplaza el volumen `datos` del Deployment del `revisor` (el primero de la lista, `/spec/template/spec/volumes/0`) por uno que use la solicitud `reportes`:

```bash
ctx && kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
```

Predice: ¿arrancan las tres réplicas? ¿En qué nodo cae cada una? ¿Qué dice `kubectl get pv` del volumen? Pide un reporte con `depurar` y busca el archivo en el nodo. Después, deshaz el cambio con `kubectl apply -k .` (el archivo es la verdad) y comprueba dónde quedan las réplicas. Explica en cinco frases por qué esto no es lo que quieres para el proyecto, y qué se pierde de lo que la Lección 9 va a pedir.

### Ejercicio 3 — Una tarea que tarda más que su horario

`fig08_09.cron-lento.yaml` es un CronJob que corre cada minuto (`* * * * *`) con `concurrencyPolicy: Forbid`, y cuya tarea tarda **100 segundos** (`sleep 100`). Predice, antes de aplicarlo: a los 2 minutos y medio, ¿cuántos Jobs habrá corriendo a la vez? ¿Se crearán los de los minutos intermedios? ¿Qué evento deja el CronJob cuando salta uno? Aplícalo, mira cada 35 segundos durante unos 210 segundos (la primera tarea tarda cerca de dos minutos y hay que ver cómo termina) con `kubectl get cronjob lento -n revisor` y `kubectl get jobs -n revisor` y lee `kubectl describe cronjob lento -n revisor`. Después, borra el CronJob (`ctx && kubectl delete -f fig08_09.cron-lento.yaml`), espera al inicio de un minuto y vuelve a crearlo con la política cambiada sin tocar el archivo: `sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -`; repite con `Replace`. Así el archivo queda intacto para la corrida de `correr.sh`. Compara: ¿qué ves con cada valor? Al terminar, bórralo con `ctx && kubectl delete -f fig08_09.cron-lento.yaml`: si lo dejas, sigue creando un Job por minuto, y `kubectl diff -k .` no lo detecta porque no es parte de los archivos de la lección.

### Ejercicio 4 — Dos horarios

En cinco frases como máximo, escribe tu respuesta a esto. (a) El horario cron de una tarea que corre **los días de entre semana a las 7:30 de la mañana, hora de la Ciudad de México**, y qué campo de la especificación del CronJob necesitas además del horario. (b) El horario de una tarea que corre **cada dos horas en punto**. (c) Qué ocurre con una ejecución programada para las 3:00 si el controlador de CronJobs estuvo caído de las 2:50 a las 3:20 y el CronJob tiene `startingDeadlineSeconds: 600`; y qué cambia si no lo tiene. (d) Por qué la tarea del reporte puede correr dos veces en el mismo minuto sin dañar nada.

## Soluciones

### Solución 1

Medido en `correr.salida.txt`:

```text
$ kubectl apply -f fig08_08.pvc-clase-inexistente.yaml
persistentvolumeclaim/rapido created
pod/lector created

$ kubectl get pvc rapido -n revisor
NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
rapido   Pending                                      rapido         <unset>                 12s

$ kubectl get pod lector -n revisor
NAME     READY   STATUS    RESTARTS   AGE
lector   0/1     Pending   0          12s

$ kubectl describe pvc rapido -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason              Age               From                         Message
  ----     ------              ----              ----                         -------
  Warning  ProvisioningFailed  6s (x2 over 12s)  persistentvolume-controller  storageclass.storage.k8s.io "rapido" not found

$ kubectl describe pod lector -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  13s   default-scheduler  0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
```

**Los dos están `Pending`, pero por razones de distinto dueño.** La solicitud lo está porque el `persistentvolume-controller` busca la clase `rapido`, no la encuentra, y emite un `Warning` con la causa exacta: `storageclass.storage.k8s.io "rapido" not found`. A diferencia del `Pending` de 8.4, éste es de nivel `Warning` y no dice «esperando»: dice que algo no existe. El Pod lo está porque el planificador, que lo ve con una solicitud sin unir, responde `0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims`: ningún nodo sirve mientras la solicitud no esté unida. (El mensaje termina con un `not found` suelto, tal como lo imprimió el clúster de la corrida; el texto de los eventos cambia entre versiones, y lo que debes leer es la causa en el evento de la solicitud.)

La lectura es la de siempre: el Pod `Pending` no es el problema, es el síntoma. La causa está un objeto más abajo, en la solicitud, y su evento dice qué clase falta. La corrección es escribir una clase que exista (`kubectl get storageclass` da la lista) o crear la que falta. Sobre cuánto esperar: nada de esto se resuelve solo. La solicitud sin clase se queda `Pending` «indefinidamente», como dice la documentación de volúmenes persistentes para una solicitud sin volumen que coincida, hasta que alguien cree la clase; no hay tiempo de espera ni error final. Un `Pending` con `ProvisioningFailed` no es una espera, es un aviso.

### Solución 2

Medido en `correr.salida.txt`:

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
deployment.apps/revisor patched

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-6d9bd59b8b-5wnrq   1/1     Running   0          7s    10.244.2.24   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-sjjkr   1/1     Running   0          10s   10.244.2.23   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-z7sc9   1/1     Running   0          12s   10.244.2.22   curso-k8s-l8-worker   <none>           <none>

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
NOMBRE                                     NODO
pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   curso-k8s-l8-worker

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40_revisor_reportes
total 146508
drwxrwxrwx 2     0     0      4096 Oct 21 23:28 .
drwxr-xr-x 3     0     0      4096 Oct 21 23:26 ..
-rw-r--r-- 1   100   101 150000000 Oct 21 23:27 grande.bin
-rw-r--r-- 1   100   101        92 Oct 21 23:26 reporte-20261021T232640Z.json
-rw------- 1 65532 65532        93 Oct 21 23:28 reporte.json

$ kubectl apply -k . | grep -E 'deployment|persistentvolumeclaim'
persistentvolumeclaim/reportes unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-6b7f4d564d-mgzwr   1/1     Running       0          2s    10.244.1.9    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-nxzdj   1/1     Running       0          7s    10.244.1.8    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-tk4tr   1/1     Running       0          5s    10.244.2.25   curso-k8s-l8-worker    <none>           <none>
revisor-6d9bd59b8b-5wnrq   1/1     Terminating   0          15s   10.244.2.24   curso-k8s-l8-worker    <none>           <none>
```

**Las tres réplicas arrancan, y las tres caen en el mismo nodo**: `curso-k8s-l8-worker`, el que tiene el volumen. El planificador no pudo repartirlas porque el PV tiene una afinidad de nodo (8.5.2): cualquier Pod que use la solicitud debe correr donde está el disco. Y fueron las tres porque ese modo, `ReadWriteOnce`, es «un nodo», no «un Pod»: varios Pods en el mismo nodo pueden montar el volumen a la vez. La documentación lo dice, y aquí se vio. El `reporte.json` del `revisor` aparece en la misma carpeta de los reportes de la tarea, junto a `grande.bin` (el 150 MB de «el hábito de seguridad», todavía ahí porque el volumen es el mismo) y el archivo con fecha de la tarea 3.

Se deshace con `kubectl apply -k .`: las réplicas vuelven al `emptyDir` y se reparten otra vez en los dos nodos de trabajo (`worker` y `worker2`). Lo que se vería mal en el proyecto, en cinco frases: (1) todas las réplicas quedan en un solo nodo, porque el volumen está en un solo disco; (2) si ese nodo cae, el `revisor` completo queda sin sitio donde correr, porque los Pods no pueden irse a otro nodo con su volumen; (3) las tres réplicas escribirían el **mismo** `reporte.json`, pisándose entre sí, que es peor que antes; (4) el reparto de réplicas por nodos que la Lección 9 necesita para escalar y para actualizar midiendo cada corte desaparece; (5) lo que el reporte necesita es historia con nombre y fecha, y eso ya lo hace la tarea.

### Solución 3

Medido en `correr.salida.txt`. Primero `Forbid` (el guion espera al inicio de un minuto del reloj antes de aplicar cada variante, para que la primera tarea caiga en el siguiente `:00`):

```text
$ kubectl apply -f fig08_09.cron-lento.yaml
cronjob.batch/lento created

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:30:45
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        45s             105s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Running    0/1           45s        45s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:31:56
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        56s             2m56s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Complete   1/1           103s       117s
lento-29877091     Running    0/1           14s        14s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age                From                Message
  ----    ------            ----               ----                -------
  Normal  SuccessfulCreate  2m32s              cronjob-controller  Created job lento-29877090
  Normal  SawCompletedJob   49s                cronjob-controller  Saw completed job: lento-29877090, condition: Complete
  Normal  SuccessfulCreate  49s                cronjob-controller  Created job lento-29877091
  Normal  JobAlreadyActive  32s (x4 over 92s)  cronjob-controller  Not starting job because prior execution is running and concurrency policy is Forbid
```

**Con `Forbid`, un solo Job a la vez, y los minutos intermedios no se crean.** El primer Job, `lento-29877090`, nació a las `23:30:00` y tardó 103 segundos (100 de `sleep` más lo que tarda arrancar y terminar). Mientras corría, llegaron los horarios de `23:31:00` y no se creó nada: el CronJob dejó `ACTIVE 1` y siguió con el mismo. Cuando el Job terminó, a las `23:31:43` más o menos, el CronJob lo vio (`SawCompletedJob`) y creó **otro** de inmediato, `lento-29877091`. Fíjate en el nombre del segundo: `…091` es el de las `23:31:00`, no el de las `23:32:00`. La razón está en la documentación: cuando termina la ejecución anterior, `startingDeadlineSeconds` (que aquí no se fijó, y por tanto no tiene tope) todavía cuenta, y la ejecución de las `23:31:00` que se había saltado se crea al fin. (En `correr.salida.txt` hay una captura más, a los 35 segundos de aplicar, que todavía no tiene ningún Job: el CronJob se creó a las `23:29:00` y su primer horario fue el de las `23:30:00`; por eso `lento-29877090` es del minuto siguiente.)

El evento que dejan los horarios saltados es `JobAlreadyActive`, con el mensaje `Not starting job because prior execution is running and concurrency policy is Forbid` («no se inicia el Job porque la ejecución anterior sigue corriendo y la política de concurrencia es Forbid»), y el contador `x4 over 92s` dice cuántas veces ocurrió en el rato que miraste. La documentación agrega una consecuencia: una ejecución saltada por `Forbid` cuenta como perdida.

Ahora la misma tarea con `Allow`, el valor por omisión, y después con `Replace`. Los dos son mediciones, no aritmética:

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Allow

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:35:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     2        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877094     Running    0/1           81s        81s
lento-29877095     Running    0/1           21s        21s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877094-mt8vs   1/1     Running   0          81s
lento-29877095-hqn7d   1/1     Running   0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877094
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877095
```

**Con `Allow`, dos Jobs corren a la vez.** El primero (`lento-29877094`) empezó a las `23:34:00`; a las `23:35:00` llegó el segundo (`lento-29877095`) sin esperar a que el primero terminara, y la captura muestra `ACTIVE 2`, dos Jobs `Running` y dos Pods `Running` al mismo tiempo, con 81 y 21 segundos de vida. Los eventos son solo `SuccessfulCreate`, uno por horario: no hay `JobAlreadyActive`, porque nada se salta. Como la tarea dura 100 segundos y el horario es de 60, en régimen siempre hay entre uno y dos activos (esto último sale de la aritmética; lo medido es el primer solape). Con una tarea que escribe en un volumen compartido, esos dos Pods escribirían a la vez: por eso 8.6 elige `Forbid` para el reporte.

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Replace/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Replace

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:37:46
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        46s             106s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877097     Running    0/1           46s        46s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877097-n8cpx   1/1     Running   0          46s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:38:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877098     Running    0/1           21s        21s
NAME                   READY   STATUS        RESTARTS   AGE
lento-29877097-n8cpx   1/1     Terminating   0          81s
lento-29877098-g6cvv   1/1     Running       0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877097
  Normal  SuccessfulDelete  21s   cronjob-controller  Deleted job lento-29877097
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877098
```

**Con `Replace`, el Job en curso se borra y se empieza otro, y ninguno llega a terminar.** El primero (`lento-29877097`) empezó a las `23:37:00`; a las `23:38:00` el CronJob lo **borró** (`SuccessfulDelete`) y creó `lento-29877098` en su lugar. En la última captura el Pod viejo está `Terminating` y el nuevo `Running` con 21 segundos. El primer Job vivió 60 segundos, menos de los 100 que necesita, y no llegó a terminar. Eso se midió una vez (el primer reemplazo); que los siguientes repitan lo mismo sale de que el horario sigue siendo de 60 segundos y la tarea de 100. `Replace` es el valor para tareas cuyo último resultado es el único que importa y que se pueden reiniciar sin daño, y el incorrecto para una que necesita sus 100 segundos completos.

Las tres políticas son una respuesta a «qué pasa cuando la tarea es más lenta que su horario», y la respuesta correcta es la que describe lo que tu tarea necesita, no el valor por omisión.

### Solución 4

Una respuesta posible: «(a) `30 7 * * 1-5`, que es minuto 30, hora 7, cualquier día del mes, cualquier mes, de lunes (1) a viernes (5); y además `timeZone: "America/Mexico_City"` en la especificación, porque sin él el horario se interpreta en la zona del controlador, UTC en kind, y la tarea correría a la 1:30 de la madrugada. (b) `0 */2 * * *`: minuto 0 de cada segunda hora. (c) Con `startingDeadlineSeconds: 600`, a las 3:20 el CronJob ve que la ejecución de las 3:00 se retrasó 1200 segundos, más del plazo de 600, y la salta, porque ya es demasiado tarde para ella; con el campo sin fijar, no hay plazo y la crea en cuanto el controlador vuelve, a las 3:20, con 20 minutos de retraso, salvo que se hayan acumulado más de 100 ejecuciones perdidas, en cuyo caso se niega a empezar. (d) Porque es segura ante repeticiones: el nombre del archivo lleva la fecha con segundos y cada ejecución escribe un archivo distinto, así que dos ejecuciones dejan dos archivos y no se corrompe ni se pierde nada (no es idempotente en sentido estricto: el resultado no es el mismo que con una sola).»

## Borrar el clúster

Antes de borrar, el estado final. Primero se retira el Pod `depurar`, que no es parte de los archivos de la lección (`ctx && kubectl delete pod depurar -n revisor --wait=false`); por eso, en la salida de abajo, aparece `Terminating` en la lista de Pods. Si la cadena de la lección se siguió en orden y los experimentos se deshicieron, el clúster debe ser exactamente lo que dicen los archivos. Es el `kubectl diff` de la Lección 5, ahora al revés: sin diferencias, sale con 0.

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Bound    pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   100Mi      RWO            standard       <unset>                 12m

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        3m53s           14m

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-29877090   Complete   1/1           4s         8m53s
reporte-29877095   Complete   1/1           4s         3m53s
reporte-manual-3   Complete   1/1           8s         12m

$ kubectl get pods -n revisor
NAME                       READY   STATUS        RESTARTS   AGE
depurar                    1/1     Terminating   0          14m
prueba-6899c74865-9dckl    1/1     Running       0          15m
reporte-29877090-8ms5h     0/1     Completed     0          8m53s
reporte-29877095-wbx85     0/1     Completed     0          3m53s
reporte-manual-3-2657n     0/1     Completed     0          12m
revisor-6b7f4d564d-mgzwr   1/1     Running       0          10m
revisor-6b7f4d564d-nxzdj   1/1     Running       0          10m
revisor-6b7f4d564d-tk4tr   1/1     Running       0          10m

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

La solicitud `reportes` está unida, el `CronJob` `reporte` está programado y ya corrió solo (los Jobs `reporte-29877090` y `reporte-29877095`, de las `23:30` y las `23:35`, los creó él), y la puerta del Gateway sigue contestando desde fuera. Ese es el estado con el que empieza la Lección 9. (El único Pod `Terminating` es `depurar`, que se borró justo antes de esta comprobación; los Pods `lento-…` del Ejercicio 3 ya no están porque el guion esperó a que desaparecieran antes de medir.)

Cuando termines, borra el clúster de la lección. No dejes nada vivo en la máquina:

```text
$ kind delete cluster --name curso-k8s-l8
Deleting cluster "curso-k8s-l8" ...
Deleted nodes: ["curso-k8s-l8-worker2" "curso-k8s-l8-control-plane" "curso-k8s-l8-worker"]
(borrar tardó 4 s)

$ kind get clusters | grep -c curso-k8s-l8
0
```

(La línea entre paréntesis la escribe el guion, que mide el borrado.) El `--name` es obligatorio: sin él, kind borraría el clúster llamado `kind`, que puede ser de otra persona o de otro proyecto. Con el clúster se va la carpeta `/mnt/disco-reportes` del nodo y los volúmenes que quedaran: todo vivía dentro de los contenedores de los nodos.

Quedan en tu máquina la carpeta temporal del `kubeconfig` y los dos `token.txt`. Se borran así, desde `programas/08-datos-y-tareas`:

```bash
# Los dos tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 8.1.1.
case "$L8_TMP" in
  /tmp/curso-k8s-l8.?*) rm -rf -- "$L8_TMP" ;;
  *) echo "No borro «$L8_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L8_TMP
unset -f ctx
```

El `case` solo deja pasar una ruta que empiece con `/tmp/curso-k8s-l8.` y tenga algo después, la forma exacta de la que creaste en 8.1.1. Si `L8_TMP` está vacía (por ejemplo, porque estás en otra terminal, donde nunca la definiste) o vale otra cosa, no borra nada y te dice por qué. Es la misma protección que usa `correr.sh` al limpiar: un `rm -rf` que se puede copiar y pegar tiene que protegerse solo. Si tu `correr.sh` usó la red propia de las notas de la corrida, esa red (`docker network rm curso-k8s-red-l8`) también la borras tú, y solo esa.

## Cómo sé que lo logré

- [ ] Explicas, con la medición de 8.2, qué sobrevive a la caída de un contenedor y qué no sobrevive al borrado de un Pod, y por qué.
- [ ] Distingues `PersistentVolume`, `PersistentVolumeClaim` y `StorageClass`, y dices quién crea cada uno.
- [ ] Lees `Pending` en una solicitud con `WaitForFirstConsumer` y sabes que no es un error, y lees `ProvisioningFailed` con una clase inexistente y sabes que sí lo es.
- [ ] Escribes un `Job` con `backoffLimit` y `activeDeadlineSeconds` y dices cuántos Pods como máximo crea y con qué esperas.
- [ ] Lees un horario cron de cinco campos y escribes el de «cada cinco minutos» y el de «lunes a viernes a las 7:30».
- [ ] Dices qué hace `Forbid` frente a `Allow` y `Replace`, y por qué la tarea del reporte debe poder correr dos veces.
- [ ] Provocas y arreglas un `Permission denied` en un volumen con `fsGroup`, y dices en qué volumen de la lección `fsGroup` cambió el grupo y en cuál no.
- [ ] Dices qué se pierde al borrar una solicitud con política `Delete` y qué con `Retain`, y por qué un borrado se queda en `Terminating`.
- [ ] Corres `programas/08-datos-y-tareas/correr.sh > /tmp/mi-corrida-l8.txt 2>&1` y comparas `/tmp/mi-corrida-l8.txt` contra `programas/08-datos-y-tareas/correr.salida.txt` (no redirijas a ese archivo: es la referencia) en lo que no cambia entre corridas: tres nodos `Ready` en `v1.37.0`; seis renglones `not yet present on node … loading...`; `-rw-------` en los dos `token.txt`; en el `emptyDir`, el directorio `2777` con grupo `65532` y un solo `reporte.json` de unos 92 bytes en una de las tres réplicas (93 si el tiempo medido tiene dos dígitos); `RESTARTS 1` y `Error 137` tras detener el contenedor, con el archivo intacto; la carpeta del volumen que ya no existe tras borrar el Pod; la clase `standard (default)` con `rancher.io/local-path`, `Delete` y `WaitForFirstConsumer`; `No resources found` en `kubectl get pv`; la solicitud `Pending` con el evento `waiting for first consumer to be created before binding`; el Job `salud` con `Complete` y `{"estado":"vivo","version":"1.6.0"}`; el Pod de la tarea `Pending` con un nodo nominado y el evento `Provisioning` (`ProvisioningSucceeded` llega un instante después y puede o no caer en la captura); la solicitud `Bound`, `100Mi`, `RWO`, `standard`; el volumen atado a un nodo, con la ruta `/var/local-path-provisioner/pvc-…_revisor_reportes` y permiso `777 0:0`; un archivo `reporte-…Z.json` en la primera tarea y dos en la segunda; Jobs de CronJob con nombre `<cronjob>-<número>` de ocho dígitos y la anotación `cronjob-scheduled-timestamp` en `:00`; `Permission denied` y `755 0:0` sin `fsGroup`, `Completed` y `2775 0:101` con él; `Released` con `Retain`; `Terminating` con el finalizador `kubernetes.io/pvc-protection` hasta borrar los Jobs; `BackoffLimitExceeded` con tres Pods en `Error`, código `28`; `150000000` bytes escritos en un volumen de `100Mi`; `ProvisioningFailed … "rapido" not found`; las tres réplicas del `revisor` en un solo nodo; `JobAlreadyActive … concurrency policy is Forbid`; y `sin diferencias con los archivos`. Las IP, los sufijos de los nombres, los `uid`, las edades, el nodo que recibe el volumen, los segundos exactos, el identificador de cada `pvc-…` y la hora de los archivos cambian en cada corrida: se observan, no se comparan.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l8`.

## Resumen

Responde sin mirar la lección:

1. ¿Qué sobrevive a la caída de un contenedor y qué no sobrevive al borrado de un Pod, en un `emptyDir`?
2. ¿Qué papel tiene cada uno de estos tres objetos: `PersistentVolume`, `PersistentVolumeClaim`, `StorageClass`?
3. ¿Por qué la solicitud `reportes` se queda en `Pending` al aplicarla, y cuándo deja de estarlo?
4. ¿Qué significa `ReadWriteOnce`, y qué consecuencia tiene sobre dónde pueden correr los Pods que usan el volumen?
5. ¿En qué se parece y en qué se diferencia un `Job` de un Deployment?
6. ¿Cuántos Pods crea como máximo un Job con `backoffLimit: 2`, y con qué esperas entre ellos?
7. ¿Qué dicen los cinco campos de `*/5 * * * *`? ¿En qué zona horaria corren si no pones `timeZone`?
8. ¿Qué hace `concurrencyPolicy: Forbid` y qué evento deja?
9. ¿Qué quiere decir que una tarea sea idempotente, y por qué importa en un CronJob?
10. ¿Qué hace `fsGroup`, en qué volumen de la lección cambió algo y en cuál no?
11. ¿Por qué una solicitud puede quedarse `Terminating`? ¿Cómo se resuelve sin forzar nada?
12. ¿Qué diferencia hay entre `Delete` y `Retain`?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Persistent Volumes»](https://kubernetes.io/docs/concepts/storage/persistent-volumes/): las definiciones de `PersistentVolume` y `PersistentVolumeClaim`; el aprovisionamiento estático y el dinámico; la unión de uno a uno y que una solicitud sin volumen que coincida espera indefinidamente; la protección de objetos de almacenamiento en uso y su definición de «en uso»; las políticas de reclamación `Retain` y `Delete`; las fases `Bound` y `Released`; los modos de acceso y la definición de `ReadWriteOnce` (un nodo, varios Pods).
- [Kubernetes, «Storage Classes»](https://kubernetes.io/docs/concepts/storage/storage-classes/): qué es una clase; la clase por omisión; la política de reclamación por omisión (`Delete`); el modo de unión `Immediate` frente a `WaitForFirstConsumer`.
- [Kubernetes, «Volumes»](https://kubernetes.io/docs/concepts/storage/volumes/): `emptyDir` (se crea al asignar el Pod a un nodo, se borra al quitar el Pod, sobrevive a la caída de un contenedor, el permiso `0777` por omisión) y el volumen `local` (solo estático, `nodeAffinity` obligatoria).
- [Kubernetes, «Jobs»](https://kubernetes.io/docs/concepts/workloads/controllers/job/): la definición de Job; `restartPolicy` `Never` u `OnFailure`; `backoffLimit` (6 por omisión) y la espera exponencial; `activeDeadlineSeconds` y su precedencia; las causas de fallo (`BackoffLimitExceeded`, `DeadlineExceeded`); las condiciones terminales retrasadas desde la 1.31; que el mismo programa puede arrancar dos veces.
- [Kubernetes, «CronJob»](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/): el formato cron de cinco campos; la zona horaria y `.spec.timeZone`; `concurrencyPolicy`; los límites de historial (3 y 1 por omisión); `startingDeadlineSeconds` y el tope de 100 ejecuciones perdidas; `suspend`; el nombre de 52 caracteres como máximo; la anotación `cronjob-scheduled-timestamp` desde la 1.32; el aviso de que los Jobs deben ser idempotentes.
- [Kubernetes, «Configure a Security Context for a Pod or Container»](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` y el grupo del volumen; los volúmenes «que soportan administración de dueños»; `fsGroupChangePolicy`.
- [Kubernetes v1.37, registro de cambios](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.37.md): la condición `Unused` de las solicitudes de volumen (`PersistentVolumeClaimUnusedSinceTime`, beta y activada desde la 1.37).
- [Local Path Provisioner (Rancher), README](https://github.com/rancher/local-path-provisioner): el aprovisionador que usa la clase `standard` de kind; el volumen como carpeta `hostPath` del nodo; que la capacidad se ignora; el permiso `0777` de la carpeta; el borrado del contenido al borrar el volumen.
- [kind, «Configuration»](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts): los montajes extra (`extraMounts`), la forma de pasar almacenamiento de tu máquina a un nodo de kind para que los datos persistan más allá del contenedor del nodo.
- [Kubernetes, «StatefulSets»](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/): identidad de red estable y almacenamiento estable por Pod (`volumeClaimTemplates`).
- [Kubernetes, «Volume Snapshots»](https://kubernetes.io/docs/concepts/storage/volume-snapshots/): las instantáneas de volumen.
- [Kubernetes, «Resource Quotas»](https://kubernetes.io/docs/concepts/policy/resource-quotas/): `requests.storage`, la suma máxima de almacenamiento que pueden pedir las solicitudes de un espacio de nombres.
- [GitLab, «Postmortem of database outage of January 31»](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): el relato público, de febrero de 2017, de una pérdida de datos de producción y de los mecanismos de respaldo que no estaban sirviendo (una copia diaria que fallaba en silencio, instantáneas no activadas en los servidores de la base, una réplica rota): la razón para probar los respaldos en vez de suponerlos.

---

**Siguiente:** [Lección 9 — Escalar y actualizar, midiendo cada corte](09-escalar-y-actualizar.md)
