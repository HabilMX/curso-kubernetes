# Lección 10 — El proyecto terminado y qué cambia en un clúster real

Lunes, 7:50 de la mañana. A las 9:00 hay junta con la dirección y el `revisor` es la demostración. Abres la laptop y el clúster ya no está: el fin de semana, alguien actualizó Docker, alguien más limpió imágenes y contenedores «que ya no se usaban», y `kind get clusters` te contesta con una lista vacía. Tienes los manifiestos, que están en Git, y tienes la página de la wiki que escribiste hace un mes: «Para levantarlo, `kubectl apply -k .`». Lo intentas. El primer comando te dice `no matches for kind "IPAddressPool"`. Lo repites y ahora dice `failed calling webhook`. Lo repites una tercera vez y casi todo se crea, pero el Gateway se queda sin dirección, y no sabes si es porque falta algo o porque todavía no ha pasado el tiempo. A las 8:35 tienes un clúster que *casi* funciona, una wiki que no dice el orden porque cuando la escribiste el orden «salió solo», y la sospecha incómoda de que, si te preguntan «¿puedes volver a levantarlo?», la respuesta honesta es «creo que sí, si lo repito varias veces».

Esa respuesta no es una respuesta. Un proyecto está terminado cuando cualquiera —tú dentro de seis meses, una compañera nueva, un paso automático de un *pipeline*— puede partir de un clúster vacío, correr una receta corta y llegar al mismo lugar, sin corregir nada a mano y sabiendo qué esperar entre un paso y otro. Esta es la última lección del curso y hace dos cosas. La primera: junta todo lo que construiste en las nueve anteriores en una estructura que se levanta con **dos comandos y una espera**, con **Kustomize** (una base y capas encima de ella), y lo automatiza con un guion que **no esconde el orden**. La segunda es menos cómoda y por eso es la más importante: te dice, de frente, **qué le falta a todo esto para ser algo más que un laboratorio**.

**Tiempo:** 2 × 45 min

**Qué construyes:** el `revisor` completo —las nueve lecciones juntas— organizado en una base y dos capas de Kustomize (la plataforma y el proyecto), que se levanta desde un clúster vacío con dos `kubectl apply` y una espera, y que un guion repite, borra y vuelve a repetir sin que corrijas nada a mano; además, una lista escrita de lo que le falta para correr de verdad

**Qué aprendes:** qué es una base y qué es un *overlay* en Kustomize, y cómo se lee lo que arman; por qué la plataforma (tipos nuevos, controladores y *webhooks*) va antes que el proyecto, y qué dice el clúster cuando se rompe ese orden; qué es `kubectl apply --server-side` y qué error evita; cómo esperar sin `sleep` (con `kubectl wait`) y cómo automatizar el levantamiento sin esconder el orden; la revisión final del proyecto contra el nivel `restricted`, campo por campo; las pruebas de las metas del curso (un nodo que se cae, una configuración que cambia, un Pod ajeno, un escalado que lee métricas); qué es Helm y cuándo conviene en lugar de Kustomize; y qué cambia, y qué se pierde, entre un clúster de `kind` y uno real

**De dónde vienes.** De las nueve lecciones anteriores, que ahora se leen como capas de un mismo edificio. De la [Lección 2](02-pods-deployments.md): el Deployment, el `securityContext` y las imágenes cargadas con `kind load`. De la [Lección 3](03-services-dns.md): los Services y el Pod `depurar`. De la [Lección 4](04-configuracion-secretos.md): Kustomize con generadores y el *hash* que dispara el *rollout*. De la [Lección 5](05-salud-recursos-apagado.md): las sondas, los `requests` y los `limits`. De la [Lección 6](06-entrar-al-cluster.md): MetalLB y Envoy Gateway, y la idea de que la plataforma va antes que el proyecto; esta lección convierte esa idea en la estructura de carpetas. De la [Lección 7](07-aislar-permisos-red.md): el espacio de nombres `revisor` en nivel `restricted`, las cuentas con permisos mínimos y la red cerrada. De la [Lección 8](08-datos-y-tareas.md): el volumen y el `CronJob` del reporte. De la [Lección 9](09-escalar-y-actualizar.md): `metrics-server`, el escalado automático y el apagado con `preStop`. Si alguna de las nueve te quedó a medias, la tabla de 10.2 te dice en qué archivo vive cada pieza.

**Qué no hace esta lección.** No enseña nada nuevo del `revisor`: todo lo que lleva ya lo construiste. No instala Helm ni lo corre: lo nombra, lo compara con Kustomize y te dice cuándo tendrías que usarlo. No convierte el clúster en uno de producción: eso es exactamente lo que **no** hace, y la sección 10.10 te explica por qué en cada caso. Y no repite las mediciones largas de las lecciones 6 y 9 (cuánto tarda el escalado en subir y bajar, cómo se comporta MetalLB de cerca): las usa, y manda a esas lecciones para el detalle.

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1 (`kubectl version --client` dice `Kustomize Version: v5.8.1`), la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** (con Gateway API v1.6.1) y **metrics-server v0.9.0**, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l10`. La máquina fue una Mac con procesador ARM y Docker Engine 29.2.1 dentro de una máquina virtual Linux (Colima), **no** Linux Mint, que es el sistema de referencia del curso. Lo que cambia en tu Mint: la arquitectura (`amd64` en lugar de `arm64`); las IP de los Pods, de los Services y de los nodos; los sufijos al azar de los nombres, las edades y en qué nodo cae cada réplica; y, sobre todo, los tiempos, que dependen de tu conexión (los nodos descargan de internet las imágenes de la plataforma) y de la carga de la máquina. **Una diferencia de red importa:** esta corrida usó una **red de Docker propia**, `curso-k8s-red-l10` (`172.30.0.0/16`), creada con `docker network create --subnet 172.30.0.0/16 curso-k8s-red-l10` antes del primer clúster y borrada después del último, y cada clúster se creó con la variable `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l10`. Se hizo así porque la máquina era compartida y otras lecciones también instalaban MetalLB: dos clústeres con el mismo rango en la misma red se pisan. `kind` lo avisa en la salida de creación con `WARNING: Overriding docker network…` y `Here be dragons! This is not supported currently` (la variable es experimental). En tu máquina, con la red `kind` normal (`172.18.0.0/16` en Mint), no necesitas nada de eso, y las direcciones de la puerta salen en `172.18.255.x`: cambia el rango de `overlays/kind/metallb-pool.yaml` a `172.18.255.200-172.18.255.250` (10.1.1 y 10.6.2 explican por qué) y, donde las salidas dicen `172.30.255.200`, leerás `172.18.255.200`. Los clientes «de fuera» de las salidas se conectaron a la red propia; en tu máquina, a `kind`. El recorrido completo está en [`programas/10-proyecto-final/`](../programas/10-proyecto-final): `correr.sh` crea un clúster, provoca los dos errores de 10.4 (cada uno en un clúster nuevo), crea otro y recorre 10.1 a 10.8 y los Ejercicios 1 a 3, lo borra, y termina con `probar-levantar.sh` (dos clústeres más). En total, cinco clústeres, de uno en uno, y los cinco se borraron. Su salida es `correr.salida.txt` (las tres corridas anteriores que se citan en 10.8.3 y en el Ejercicio 3 están en `corridas-preparacion/`; `psa-comprobacion.sh` y `crd-tamanos.sh`, con sus `.salida.txt`, son dos mediciones sueltas que se citan en 10.7.3 y 10.4.3); verás ahí unas líneas «espera de cupo» que son del guion esperando a que otra lección liberara un lugar de la máquina compartida. La corrida completa tardó 1,755 segundos (casi media hora), de los cuales unos 6 minutos fueron esas esperas. Crear un clúster, esperar a los nodos y cargar las imágenes tardó entre 35 y 60 segundos; la espera de la plataforma, 153 segundos en el clúster de 10.5, y en `probar-levantar.sh` el paso 2 terminó a los 234 y 250 segundos de arrancado el guion (la espera misma, unos 229 y 246); en una de las corridas de preparación, esa misma espera llegó a 881 segundos (está en `programas/10-proyecto-final/corridas-preparacion/corrida4.txt`). Necesita internet.

## Al terminar vas a poder

- Explicar con tus palabras qué es una **base** y qué es un ***overlay*** en Kustomize, abrir un `kustomization.yaml` y decir qué recursos arma, qué les cambia y cómo comprobarlo con `kubectl kustomize` sin tocar el clúster.
- Distinguir una pieza de **plataforma** (tipos nuevos, controladores, *webhooks*) de una de **proyecto**, y levantar las dos desde un clúster vacío con dos `kubectl apply --server-side -k` y una espera con `kubectl wait`, en el orden correcto.
- Reconocer y leer los dos errores de romper ese orden: el que sale de aplicar la plataforma sin `--server-side` y el que sale de juntar plataforma y proyecto en un solo comando.
- Escribir un guion de levantamiento que no esconda el orden —tres pasos con nombre, una comprobación de contexto antes de cada uno y esperas por condición, no por tiempo— y probarlo creando, borrando y recreando el clúster.
- Revisar el proyecto contra el nivel `restricted` de los *Pod Security Standards*, campo por campo y con el clúster, y explicar por qué la plataforma vive en espacios de nombres que no lo cumplen.
- Medir lo que pasa cuando se detiene un nodo de trabajo (qué falla, durante cuánto y por qué) y decir qué reduce esa ventana y qué no.
- Escribir, con tus palabras, cinco cosas por las que lo que construiste no es un clúster real y qué se haría con cada una.

## El porqué antes del cómo

Hasta ahora cada lección dejó el clúster *un poco más lejos* de donde empezó: más archivos, más piezas, más cosas que aplicar. Esa acumulación es normal mientras aprendes, y tiene un costo que no se ve hasta el lunes de la escena: nadie escribió **en un solo lugar** cómo se levanta todo. Las lecciones sí lo dicen, cada una a su manera; pero un proyecto que solo se puede reconstruir releyendo nueve lecciones no está terminado.

Hay un caso real que muestra por qué importa, y no es de Kubernetes. El 31 de enero de 2017, un ingeniero de GitLab borró por error el directorio de datos de la base de datos principal de GitLab.com: unos 300 GB, según el informe público que la empresa publicó el 10 de febrero. Lo que convierte esa historia en una lección para nosotros es lo que vino después. La empresa tenía varios mecanismos de respaldo y recuperación sobre el papel, y cuando los buscaron, el informe dice (traducido): «el proceso de encontrar y de usar los respaldos falló por completo». El respaldo diario con `pg_dump` no existía: la carpeta del almacenamiento estaba vacía, porque el programa que lo hacía era de una versión distinta a la de la base y terminaba con un error, y los correos que avisaban de ese error eran rechazados por el servidor de destino, así que nadie se enteró hasta que fue tarde. La recuperación se hizo con una copia que se había tomado seis horas antes por otra razón, y copiarla desde el entorno de pruebas tardó unas 18 horas. Se perdieron los cambios hechos entre las 17:20 y cerca de la medianoche (UTC; el informe da 23:30 en el detalle y 00:00 en el resumen) de ese día: según su estimación, cerca de 5,000 proyectos, 5,000 comentarios y 700 cuentas nuevas.

No pasó por falta de recetas. Pasó porque **nadie se había enterado de que no funcionaban**: el respaldo fallaba y nada avisaba. Una receta de recuperación que nadie ha corrido de principio a fin es una hipótesis, igual que «creo que sí, si lo repito varias veces». Por eso esta lección no se queda en escribir la receta: la **ejecuta**, la rompe a propósito, la borra y la repite en un clúster nuevo, y te enseña a hacerlo tú.

La lección tiene diez partes de conceptos y después las secciones de siempre:

1. **El clúster de la lección** (10.1): crearlo con su `kubeconfig` propio y su guarda de contexto.
2. **El mapa de la carpeta** (10.2): qué hay en `programas/10-proyecto-final/` y qué lección puso cada pieza.
3. **Kustomize: base y *overlays*** (10.3): cómo se arma, cómo se lee y cómo se comprueba.
4. **Por qué dos comandos y una espera** (10.4): los dos errores que enseñan el orden.
5. **Levantar a mano** (10.5): plataforma, espera, proyecto, y verlo funcionar desde fuera.
6. **Automatizar sin esconder el orden** (10.6): `levantar.sh` y la prueba de crear, borrar y recrear.
7. **La revisión final contra `restricted`** (10.7).
8. **Probar las metas** (10.8): el nodo que se cae, la configuración que cambia, el Pod ajeno, el escalado.
9. **Helm, en una mención** (10.9).
10. **Qué cambia en un clúster real** (10.10): la lista de lo que falta.

Este es el destino. Al final de 10.5, un clúster vacío tiene el proyecto completo, y la puerta que construiste en la Lección 6 recibe una dirección que MetalLB le repartió:

```text
$ kubectl get all,pvc,cronjob,hpa,pdb,networkpolicy,gateway,httproute -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rzh88    1/1     Running   0          82s
pod/revisor-654b5d75dc-6m6s6   1/1     Running   0          82s
pod/revisor-654b5d75dc-dq4pp   1/1     Running   0          82s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.57.22     <none>        9000/TCP   82s
service/revisor   ClusterIP   10.96.239.233   <none>        80/TCP     82s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           82s
deployment.apps/revisor   2/2     2            2           82s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       82s
replicaset.apps/revisor-654b5d75dc   2         2         2       82s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          82s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          82s

NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 82s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     82s

NAME                                                    POD-SELECTOR               AGE
networkpolicy.networking.k8s.io/acceso-revisor-salida   acceso-revisor=permitido   82s
networkpolicy.networking.k8s.io/cerrado                 <none>                     82s
networkpolicy.networking.k8s.io/dns                     <none>                     82s
networkpolicy.networking.k8s.io/prueba-entrada          app=prueba                 82s
networkpolicy.networking.k8s.io/revisor-entrada         app=revisor                82s
networkpolicy.networking.k8s.io/revisor-salida          app=revisor                82s

NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.30.255.200   True         82s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               82s
```

(Esa tabla es larga a propósito: es la prueba de que las nueve lecciones están ahí. La vas a leer renglón por renglón en 10.5.)

## Si no traes las imágenes del curso de Docker

Esta lección usa las mismas dos imágenes de las Lecciones 3 a 9: `curso-docker-revisor:1.6.0`, la del `revisor`, y `curso-docker-prueba:1.0.0`, la del servicio que falla a propósito. Comprueba que las tienes:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para la otra, el mismo comando con `curso-docker-prueba:1.0.0`. Si te falta alguna, la [Lección 3](03-services-dns.md) dice cómo construirlas desde el repositorio del curso de Docker. Esta lección no le pide nada nuevo a ninguna de las dos. Lo nuevo viene de internet: los manifiestos de MetalLB, de Envoy Gateway y de `metrics-server` se descargan de sus lanzamientos cada vez que aplicas la plataforma, y las imágenes de esos tres componentes y la de `curl` las descarga cada nodo la primera vez. Necesitas conexión.

## Los conceptos

### 10.1 El clúster de la lección

#### 10.1.1 Antes de crear: el cupo, la red y el disco

Esta lección instala **MetalLB**, como la Lección 6, y arrastra su regla de convivencia: MetalLB reparte direcciones IP de la red de Docker donde viven los nodos de `kind`, y dos clústeres con MetalLB y el mismo rango, en la misma red, anuncian las mismas direcciones y se pisan. Si trabajas solo en tu máquina, esto no te toca: tendrás un clúster a la vez. Si compartes máquina con alguien, o si tienes otro clúster del curso vivo, revisa antes de crear:

```bash
# ¿Hay otro clúster del curso vivo? Si lo hay y tiene MetalLB, espera a que termine.
kind get clusters
# Espacio de tu disco: si el uso pasa de 80 %, libera lo tuyo antes de seguir.
df -h /
# Cuánto ocupa Docker (imágenes, contenedores, volúmenes), para saber qué liberar.
docker system df
```

`kind get clusters` lista los clústeres que `kind` conoce en tu máquina. Si ves `curso-k8s-l10` y no lo creaste tú, detente: es de otra persona. `df -h /` dice qué porcentaje de tu disco está usado (la columna `Use%`); `docker system df` no da porcentajes: resume cuánto ocupan las imágenes, los contenedores y los volúmenes de Docker, y sirve para saber qué liberar. Esta lección crea varios clústeres, de uno en uno, y cada uno descarga las imágenes de la plataforma: no hay una cifra de espacio medida, así que deja holgura.

Y una nota sobre **la red** que decide el rango de direcciones, porque aparece en un archivo de esta lección. Por omisión, `kind` crea una red de Docker llamada `kind` y mete ahí todos los nodos. En Linux Mint, esa red suele ser `172.18.0.0/16`. Compruébalo:

```bash
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

El archivo `overlays/kind/metallb-pool.yaml` que trae la carpeta dice `172.30.255.200-172.30.255.250`, el rango de la red propia con la que se hicieron las corridas de esta lección (lo explica «Sobre las corridas»). Por eso, **aunque tu red sea `172.18.0.0/16`, tienes que cambiar ese rango tú**: a `172.18.255.200-172.18.255.250` si tu red es la de siempre, o con el prefijo de tu red si es otra `/16`. Es **una línea** de un archivo, y 10.6 te enseña un guion que comprueba que el rango cae dentro de la red antes de aplicar nada (si no la cambias, se detiene con un `ALTO` y te lo dice).

#### 10.1.2 Crear el clúster

Créalo desde `programas/10-proyecto-final/`, con el mismo cuidado de siempre: un `kubeconfig` temporal propio, una función que comprueba el contexto antes de cada cambio y las imágenes cargadas.

```bash
cd programas/10-proyecto-final
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L10_TMP="$(mktemp -d /tmp/curso-k8s-l10.XXXX)"
export KUBECONFIG="$L10_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: una segunda terminal la necesita
# curso-k8s-l10 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
# La guarda: devuelve error si el contexto activo no es el de esta lección.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l10 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
kind create cluster --name curso-k8s-l10 --config kind-curso.yaml
ctx && kubectl get nodes
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l10 > "$L10_TMP/cargar.log" 2>&1
```

Dos cosas que no son nuevas pero que esta lección usa más que ninguna. La primera: `ctx` es una **función de la terminal**, no un programa. Si `kubectl config current-context` no dice `kind-curso-k8s-l10`, imprime «contexto equivocado: no sigo» y devuelve un error; el `&&` hace que el comando de la derecha **no corra** cuando la función falla. Por eso, de aquí en adelante, todo comando que **cambia** algo se escribe `ctx && kubectl apply …`. Un comando que solo lee (`get`, `describe`) no la necesita, pero tampoco estorba. La segunda: el `export` solo vale en esa terminal. Si abres otra, repite el `export KUBECONFIG=…` con la ruta que imprimió el `echo`, y vuelve a definir `ctx`.

Y esta lección tiene algo que las anteriores no: **un token de mentira que el Secret generado va a leer** (Lección 4). Se crea una vez, con permisos solo para ti, y no se versiona (el `.gitignore` de la carpeta lo excluye):

```bash
(umask 077; openssl rand -hex 16 > base/token.txt)
TOKEN="$(cat base/token.txt)"
```

Los paréntesis hacen que el `umask 077` valga solo para ese comando, y el archivo nace con permiso `0600` (`-rw-------`): legible solo para ti. Lo comprobamos:

```text
$ /bin/ls -l base/token.txt | cut -d' ' -f1
-rw-------

$ wc -c < base/token.txt
      33
```

Los 33 bytes son los treinta y dos caracteres hexadecimales de `openssl rand -hex 16` más el salto de línea. Y el estado del clúster recién creado, con sus tres nodos y las dos imágenes ya adentro:

```text
$ kubectl config current-context
kind-curso-k8s-l10

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE   VERSION
curso-k8s-l10-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l10-worker          Ready    <none>          18s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          17s   v1.37.0

$ cat $L10_TMP/cargar.log
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-worker", loading...
```

Seis renglones `not yet present on node … loading...`: dos imágenes por tres nodos, incluido el de control. Pero «loading» no es una prueba de que la imagen llegó. Una comprobación que conviene volver costumbre es preguntarle a cada nodo qué imágenes tiene, con `crictl`, la herramienta del *runtime* de contenedores que ya usaste en la Lección 2:

```text
$ for n in control-plane worker worker2; do echo "-- curso-k8s-l10-$n"; docker exec curso-k8s-l10-$n crictl images | grep -E 'IMAGE|curso-docker'; done
-- curso-k8s-l10-control-plane
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
-- curso-k8s-l10-worker
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
-- curso-k8s-l10-worker2
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Cada uno de los tres nodos lista las dos imágenes, con la etiqueta que les pusiste (`1.6.0` y `1.0.0`). `crictl` les antepone `docker.io/library/` porque es el nombre que `containerd` da a una imagen sin registro, y no significa que se hayan descargado de ahí. La columna `IMAGE ID` (`70e09194319be`, `5f32d8833d958`) no coincide con la que muestra `docker image ls` en tu máquina (`bd1b2e7d91b8` para el `revisor`): son dos almacenes distintos y cada uno identifica la imagen a su manera. Lo mismo pasa con el tamaño: `crictl` dice 3.68 MB para el `revisor` y Docker, 16.2 MB; cada herramienta mide distinto y no se comparan entre sí. Lo que sí importa es que el nombre y la etiqueta estén en **cada** nodo: si falta en uno, un Pod que caiga ahí intentará bajar la imagen de internet y se quedará en `ErrImagePull`, como en la Lección 2, y esta es la consulta que lo explica.

**Un aviso sobre `kind load`.** Si la imagen la bajaste de un registro, no la cargues con `kind load docker-image repo@sha256:…`. En las pruebas del curso de Docker de esta casa (kind v0.33.0, Docker 29.2.1 con almacén containerd, procesador arm64), esa orden respondió «loading…» sin error y la imagen **sí llegó al nodo, pero sin nombre**: `docker exec <nodo> crictl images` la mostró como `docker.io/library/import-AAAA-MM-DD` con etiqueta `<none>` (el nombre de relleno que `ctr images import` le da a lo que importa sin una referencia propia; la fecha es la del reloj del nodo, en UTC), y un Pod que pidió la misma referencia con *digest* quedó en `ErrImageNeverPull`, porque en el nodo no hay ninguna imagen con ese nombre aunque su contenido esté. Ponle antes una etiqueta local (`docker tag repo@sha256:… curso-docker-revisor:1.6.0`), carga esa etiqueta y comprueba siempre con `crictl images`, **mirando también las filas `<none>`**: un filtro que solo deje pasar el nombre de tu imagen (como el `grep -E 'IMAGE|curso-docker'` de arriba) no las muestra. Es un caso medido sin fuente oficial para ese síntoma exacto; los *issues* de kind [#4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) y [#4224](https://github.com/kubernetes-sigs/kind/issues/4224) describen fallos vecinos (con error) de `kind load` con Docker reciente, la mayoría ligados al almacén de `containerd` de Docker (#3795 y #4066; el #4224 es en OrbStack). Las dos imágenes de esta lección se cargan por su etiqueta local (`curso-docker-revisor:1.6.0`, `curso-docker-prueba:1.0.0`), y la salida de arriba es la comprobación.

El clúster vacío no tiene ningún tipo de objeto que no traiga Kubernetes. Lo comprobamos, porque es el punto de partida de todo lo que sigue:

```text
$ kubectl get crd
No resources found
```

`crd` es la abreviatura de *CustomResourceDefinition*, la definición de un tipo de objeto nuevo (lo viste en la Lección 6). «No resources found» quiere decir que el clúster solo conoce los tipos con los que nace. Ni `Gateway`, ni `IPAddressPool`, ni `HTTPRoute` existen todavía. Ese vacío es el que el orden de 10.4 tiene que llenar.

### 10.2 El mapa de la carpeta

#### 10.2.1 Qué hay y qué lección lo puso

La carpeta `programas/10-proyecto-final/` tiene tres cosas: la **base** (el proyecto), los **overlays** (cómo se instala en un clúster concreto) y los **guiones** (cómo se levanta). Así se ven los archivos de las dos primeras:

```text
$ find base overlays -type f ! -name token.txt | sort
base/.gitignore
base/cuentas.yaml
base/escalado.yaml
base/gateway.yaml
base/kustomization.yaml
base/namespace.yaml
base/prueba-deployment.yaml
base/prueba-service.yaml
base/red.yaml
base/reporte.yaml
base/revisor-deployment.yaml
base/revisor-service.yaml
overlays/ejemplo-nube/kustomization.yaml
overlays/kind/gatewayclass.yaml
overlays/kind/kustomization.yaml
overlays/kind/metallb-pool.yaml
overlays/kind/plataforma/envoy-gateway/kustomization.yaml
overlays/kind/plataforma/kustomization.yaml
overlays/kind/plataforma/metallb/kustomization.yaml
overlays/kind/plataforma/metrics-server/kustomization.yaml
```

(`find` recorre las carpetas y lista archivos; el `! -name token.txt` omite el token y `sort` los ordena. Sale `.gitignore` porque `find` no esconde archivos que empiezan con punto.)

Cada archivo de la base es una lección que ya hiciste. Esta tabla es el mapa; si algo te quedó a medias, aquí está dónde mirar:

| Archivo | Qué es | De qué lección viene |
|---|---|---|
| `base/namespace.yaml` | el espacio `revisor`, en nivel `restricted` con la versión de la política fijada | 7 |
| `base/cuentas.yaml` | las cuentas de servicio sin credenciales montadas y el rol de solo lectura `observador` | 7 |
| `base/red.yaml` | las seis `NetworkPolicy`: todo cerrado y solo las aperturas necesarias | 7 |
| `base/revisor-deployment.yaml` | el `revisor`: imagen, variables, token como archivo, sondas, recursos, apagado ordenado, reparto entre nodos y `securityContext` | 2, 4, 5, 7, 9 |
| `base/revisor-service.yaml` | el nombre estable `revisor` dentro del clúster | 3 |
| `base/prueba-deployment.yaml` y `base/prueba-service.yaml` | el servicio de prueba que falla a propósito | 2, 3, 5, 7 |
| `base/gateway.yaml` | la puerta (`Gateway`) y la ruta (`HTTPRoute`) | 6 |
| `base/reporte.yaml` | el volumen del reporte y el `CronJob` que lo guarda | 8 |
| `base/escalado.yaml` | el escalado automático (`HorizontalPodAutoscaler`) y el `PodDisruptionBudget` | 9 |
| `base/kustomization.yaml` | los generadores del `ConfigMap` y del `Secret` con *hash*, y la lista de lo anterior | 4 |
| `overlays/kind/metallb-pool.yaml` | el rango de direcciones que MetalLB puede repartir | 6 |
| `overlays/kind/gatewayclass.yaml` | la clase de puerta `eg`, que atiende Envoy Gateway | 6 |
| `overlays/kind/plataforma/` | MetalLB, Envoy Gateway y `metrics-server`, cada uno en su carpeta | 6, 9 |

Faltan a propósito tres familias de archivos. El `LoadBalancer` directo de la Lección 6 (`revisor-publico`) se retiró en la 7: la única puerta hacia afuera es el Gateway. Los Pods de apoyo —`depurar`, `intruso`, `memoria`, el Job de carga— son **herramientas para mirar y para provocar**, no parte del proyecto: no tienen por qué estar en cada clúster que levantes, y por eso `depurar.yaml` e `intruso.yaml` viven en la raíz de la carpeta y no dentro de la base. Y el token: no se versiona.

#### 10.2.2 Tres preguntas para decidir dónde va cada archivo

El orden de las carpetas no es capricho. Cada archivo responde tres preguntas, en este orden:

1. **¿Lo necesita el `revisor` en cualquier clúster donde se instale?** Entonces va en la **base**. El Deployment, el Service, las reglas de red y el nivel `restricted` valen igual en `kind`, en el clúster de tu compañía o en la nube.
2. **¿Depende de *este* clúster?** Entonces va en un **overlay**. El rango de direcciones de MetalLB sale de la red de Docker de kind; en una nube no existiría, porque el proveedor da los balanceadores. Lo que depende del entorno no se mezcla con lo que no.
3. **¿Se instala una sola vez por clúster y lo usan varios proyectos?** Entonces es **plataforma**. MetalLB, Envoy Gateway y `metrics-server` no son del `revisor`: el día que publiques un segundo servicio, usará la misma clase de puerta y el mismo rango. Por eso tienen su propia carpeta y su propio comando.

Verás que la tercera pregunta no es una cuestión de gusto: es la que decide *el orden de aplicar*. La plataforma trae tipos nuevos, y el proyecto los usa. 10.4 lo demuestra.

### 10.3 Kustomize: base y *overlays*

#### 10.3.1 Una base que no sabe de nadie

Ya usaste Kustomize en la Lección 4, con generadores. Aquí se usa para lo que fue pensado: **componer**. La [documentación de Kubernetes](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) lo define así (traducido): una **base** es un directorio con un `kustomization.yaml` que contiene un conjunto de recursos y sus personalizaciones asociadas; un ***overlay*** es un directorio con un `kustomization.yaml` que se refiere a *otros* directorios de kustomización como sus bases. Y la frase que importa: «una base no sabe nada de un *overlay* y puede usarse en varios».

Este es el `kustomization.yaml` de la base. Lo conoces casi todo; el comentario de arriba es nuevo y dice lo que acabas de leer:

```yaml
# kustomization.yaml — Lección 10: la BASE del proyecto. No se aplica sola: la
# aplica un overlay (overlays/kind). Una base no sabe que existen sus overlays.
#
# El token NO se versiona: token.txt lo genera quien levanta el proyecto
# ((umask 077; openssl rand -hex 16 > base/token.txt)) y está en .gitignore. Los
# generadores agregan un hash al nombre: si cambia el contenido, cambia el
# nombre, y eso dispara el rollout del Deployment.
#
# Esta base necesita que la PLATAFORMA (MetalLB, Envoy Gateway y metrics-server)
# ya esté instalada y lista: sin sus tipos nuevos (CRD), Gateway y HTTPRoute no
# existen. Por eso el overlay se aplica DESPUÉS de overlays/kind/plataforma.
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
- gateway.yaml
- reporte.yaml
- escalado.yaml
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

Tres campos hacen todo el trabajo. `resources` es la lista de archivos que arma. `namespace: revisor` es un **transformador**: pone ese espacio de nombres en todo lo que lo admite, sin que cada archivo lo repita (por eso en `deployment.yaml` no hay `namespace:`). Y los dos **generadores** crean el `ConfigMap` y el `Secret` con el nombre más un *hash* del contenido: si el contenido cambia, el nombre cambia, y el Deployment —que el generador reescribe para que apunte al nombre nuevo— hace un *rollout* solo. Esa fue la Lección 4.

#### 10.3.2 Un overlay que solo apunta

El `kustomization.yaml` del overlay de `kind` es más corto que la base:

```yaml
# overlays/kind — Lección 10: el proyecto completo para un clúster de kind que ya
# tiene su plataforma (ver plataforma/). Dos comandos y una espera, en este orden:
#
#   kubectl apply --server-side -k overlays/kind/plataforma
#   (esperar a que MetalLB, Envoy Gateway y metrics-server estén listos)
#   kubectl apply --server-side -k overlays/kind
#
# No lleva «namespace:» a propósito: la base ya pone todo en «revisor», y el rango
# de MetalLB y la GatewayClass viven fuera de ese espacio.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
- metallb-pool.yaml
- gatewayclass.yaml
```

Tres líneas de recursos: la base (la carpeta, no un archivo), el rango de MetalLB y la clase de puerta. El overlay **no copia** nada de la base; solo la nombra. Por eso, si mañana cambias el Deployment del `revisor`, los overlays no se enteran ni tienen que enterarse. Y fíjate en lo que el comentario dice del `namespace:`: este overlay **no** lo pone, porque pondría `revisor` también al rango de MetalLB, que tiene que vivir en `metallb-system`, y la `GatewayClass` ni siquiera pertenece a un espacio (vale para todo el clúster). El transformador de la base ya se encargó de lo suyo.

Para ver lo que un overlay arma sin tocar el clúster existe `kubectl kustomize`, que **imprime** los manifiestos resultantes. Es el comando que más vas a usar al trabajar con Kustomize: arma, no aplica. Cuántos objetos, de qué tipos:

```text
$ kubectl kustomize overlays/kind | grep '^kind:' | sort | uniq -c | sort -rn
   6 kind: NetworkPolicy
   4 kind: ServiceAccount
   2 kind: Service
   2 kind: Deployment
   1 kind: Secret
   1 kind: RoleBinding
   1 kind: Role
   1 kind: PodDisruptionBudget
   1 kind: PersistentVolumeClaim
   1 kind: Namespace
   1 kind: L2Advertisement
   1 kind: IPAddressPool
   1 kind: HTTPRoute
   1 kind: HorizontalPodAutoscaler
   1 kind: GatewayClass
   1 kind: Gateway
   1 kind: CronJob
   1 kind: ConfigMap

$ kubectl kustomize overlays/kind | grep -c '^kind:'
28
```

(`grep '^kind:'` se queda con las líneas que *empiezan* con `kind:`, una por objeto; `sort | uniq -c` cuenta cuántos hay de cada tipo y el último `sort -rn` ordena de más a menos.) Es el proyecto completo: cada fila de la tabla de 10.2 tiene su parte aquí. Tres filas merecen una mirada. Los `ServiceAccount` y las `NetworkPolicy` son más de uno porque cada carga tiene su cuenta y cada apertura de red su regla. El `ConfigMap` y el `Secret` son uno de cada uno: los generadores. Y `Gateway`, `HTTPRoute`, `GatewayClass`, `IPAddressPool` y `L2Advertisement` son los objetos de **tipos que no existen en un clúster vacío**, el punto de 10.4.

Las cifras de arriba son el total que verá `kubectl apply`. Si alguna vez dudas de qué va a recibir el clúster, esta es la primera pregunta que haces, antes de aplicar: `kubectl kustomize` y cuenta.

#### 10.3.3 Cambiar sin copiar: un overlay de ejemplo

Los overlays sirven para lo que *cambia* entre entornos. Para ver qué puede cambiar una capa sin tocar la base, este archivo describe cómo se vería la misma base en un clúster de verdad. **No se aplica a nada**: solo se renderiza.

```yaml
# overlays/ejemplo-nube — Lección 10: un overlay de EJEMPLO que solo se RENDERIZA
# (kubectl kustomize); no se aplica a ningún clúster del curso. Muestra qué
# cambiaría la misma base en un clúster de verdad: la imagen sale de un registro,
# hay más réplicas y el reparto se hace por zona, no por nodo. No incluye la
# plataforma de kind (MetalLB, rango, GatewayClass): en la nube eso lo da el
# proveedor o el equipo de plataforma.
# registry.example.com es un dominio reservado para ejemplos: no existe.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
images:
- name: curso-docker-revisor
  newName: registry.example.com/equipo/revisor
  newTag: "1.6.0"
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: revisor
  patch: |-
    - op: replace
      path: /spec/minReplicas
      value: 3
    - op: replace
      path: /spec/maxReplicas
      value: 10
- target:
    kind: Deployment
    name: revisor
  patch: |-
    - op: replace
      path: /spec/template/spec/topologySpreadConstraints/0/topologyKey
      value: topology.kubernetes.io/zone
```

Hay tres herramientas de cambio, y las tres están ahí. **`images`** cambia el nombre y la etiqueta de una imagen en todo el árbol sin editar los Deployments: aquí la imagen sale de un registro en lugar de estar cargada a mano con `kind load`. **`patches`** con una lista de operaciones (`op: replace`) es un *JSON Patch* ([RFC 6902](https://www.rfc-editor.org/rfc/rfc6902.html)): dice qué objeto (`target`, por tipo y nombre), qué ruta cambiar (`path`) y el valor nuevo. Es preciso y a veces incómodo, porque la ruta se escribe con el índice de la lista (`topologySpreadConstraints/0` es la primera restricción). La [documentación](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) también ofrece el parche de *fusión estratégica* (se escribe un trozo del objeto y se mezcla), que es más legible para cambios grandes; para un número o una clave, el de operaciones es más directo. Y el dominio `registry.example.com` cuelga de `example.com`, un nombre que el [RFC 2606](https://www.rfc-editor.org/rfc/rfc2606.html) reserva para ejemplos y documentación: nadie lo puede registrar, y por eso no hay riesgo de que otra persona lo use y reciba tus imágenes.

La comparación entre el overlay de `kind` y este es la mejor forma de ver *qué* cambia:

```text
$ diff <(kubectl kustomize overlays/kind) <(kubectl kustomize overlays/ejemplo-nube)
229c229
<         image: curso-docker-revisor:1.6.0
---
>         image: registry.example.com/equipo/revisor:1.6.0
293c293
<         topologyKey: kubernetes.io/hostname
---
>         topologyKey: topology.kubernetes.io/zone
391c391
<   maxReplicas: 6
---
>   maxReplicas: 10
399c399
<   minReplicas: 2
---
>   minReplicas: 3
418,424d417
< kind: GatewayClass
< metadata:
<   name: eg
< spec:
<   controllerName: gateway.envoyproxy.io/gatewayclass-controller
< ---
< apiVersion: gateway.networking.k8s.io/v1
440,457d432
< ---
< apiVersion: metallb.io/v1beta1
< kind: IPAddressPool
< metadata:
<   name: curso
<   namespace: metallb-system
< spec:
<   addresses:
<   - 172.30.255.200-172.30.255.250
< ---
< apiVersion: metallb.io/v1beta1
< kind: L2Advertisement
< metadata:
<   name: curso
<   namespace: metallb-system
< spec:
<   ipAddressPools:
<   - curso
[código de salida: 1]
```

(`diff` compara dos textos; `<( … )` le entrega la salida de un comando como si fuera un archivo, y funciona en `bash` y en `zsh`. Los renglones con `<` son del overlay de `kind`; los que tienen `>` son del de ejemplo.) Léelo por bloques. En la primera hay un cambio de imagen: la del `revisor` sale de un registro, no de `kind load`. La segunda es la restricción de reparto: de `kubernetes.io/hostname` (reparte entre *nodos*) a `topology.kubernetes.io/zone` (reparte entre *zonas*, que en una nube son centros de datos distintos dentro de una región). Después, `maxReplicas` y `minReplicas` del escalado: de 6 a 10 y de 2 a 3. Y al final, lo que **sale** del árbol: la `GatewayClass`, el rango y el anuncio de MetalLB, que son de `kind` y no de la base. Cuatro cambios y una resta, y la base no se tocó. (Si ves `[código de salida: 1]` debajo del `diff`, no es un error: `diff` sale con 1 cuando encuentra diferencias, y con 0 cuando no.)

#### 10.3.4 Dos advertencias sobre lo que viene de internet

La carpeta `plataforma` tiene un `kustomization.yaml` por pieza, y cada uno apunta a un **archivo remoto**:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -c '^kind:'
76
```

Ese es el número de objetos que se arman a partir de tres direcciones de internet. Una pieza en concreto, `metrics-server`, lleva además un parche que ya conoces de la Lección 9:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -B1 -A1 'kubelet-insecure-tls'
        - --metric-resolution=15s
        - --kubelet-insecure-tls
        image: registry.k8s.io/metrics-server/metrics-server:v0.9.0
```

La bandera `--kubelet-insecure-tls` hace que `metrics-server` no verifique el certificado con el que cada `kubelet` se presenta. El README de `metrics-server` v0.9.0 la describe sin adornos: «para propósitos de prueba únicamente». En `kind` los certificados de los `kubelet` no están firmados por la autoridad del clúster, así que sin la bandera `metrics-server` no puede leer los nodos. En un clúster real **no se usa**: los certificados se firman bien y la bandera sobra. Es la sexta de las cosas que 10.10 anota en la lista de lo que falta.

Las dos advertencias sobre lo remoto:

- **Cada vez que aplicas, descargas.** Una dirección con la versión en la ruta (`…/v0.16.1/…`) fija *qué versión* pides, pero el contenido sigue viniendo de internet cada vez que `kustomize` arma el árbol. Sin conexión, no hay plataforma. Un equipo real suele guardar una copia de esos archivos dentro de su repositorio (o en un espejo propio), de modo que el levantamiento no dependa de un sitio ajeno ni de que un archivo remoto no cambie por debajo. Aquí no se hace para que veas de dónde sale cada pieza.
- **Fija la versión, y anótala.** Las versiones de este curso son MetalLB v0.16.1, Envoy Gateway v1.9.2 y `metrics-server` v0.9.0. No es un detalle: la [guía de instalación de Envoy Gateway](https://gateway.envoyproxy.io/docs/install/install-yaml/) explica que, al actualizarlo, hay que actualizar primero los CRD de Gateway API, y que si no se hace, las rutas TCP y UDP «se saltan en silencio» hasta que se aplican los CRD. Una versión que se mueve sin que nadie lo decida es el origen de muchas mañanas de lunes.

### 10.4 Por qué dos comandos y una espera

#### 10.4.1 Tres cosas que una instalación trae consigo

En la Lección 6 viste que MetalLB y Envoy Gateway no son «un Deployment más»: al instalarse agregan al clúster **tipos de objeto nuevos**, **controladores** que los atienden y **guardianes** que revisan lo que se crea. Antes de seguir, los tres con sus nombres exactos, porque el orden de esta lección sale de ahí.

- **Un CRD (*CustomResourceDefinition*)** es la definición de un tipo de objeto que Kubernetes no trae de fábrica. Mientras no exista, escribir un `IPAddressPool` es como escribir una palabra que el diccionario no tiene: el `kube-apiserver` contesta `no matches for kind`. Y un CRD no está «listo» al crearse. La [documentación de CRD](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) lo dice así (traducido): el servidor tarda unos segundos en crear el *endpoint* del tipo nuevo, y puedes vigilar la condición `Established` del CRD, o la lista de tipos que el servidor anuncia, para saber cuándo ya existe. Esa condición, `Established`, es la que espera `kubectl wait` en 10.5.
- **Un controlador** es un programa (un Pod) que mira los objetos de un tipo y hace que el mundo coincida con ellos: el de MetalLB reparte direcciones; el de Envoy Gateway crea el Envoy que atiende la puerta. Mientras no esté corriendo, el objeto se acepta, pero nadie lo atiende: el Gateway existe y no tiene dirección. Un Deployment está *listo* cuando su condición `Available` es verdadera.
- **Un *webhook* de admisión** es un guardián que el `kube-apiserver` consulta *antes* de guardar un objeto, para aceptarlo, rechazarlo o corregirlo. MetalLB tiene uno que valida los rangos. La [documentación de control de admisión dinámico](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) tiene una pieza que hay que conocer: si el servidor no logra hablar con el *webhook* (red, tiempo de espera, conexión rechazada), la política `failurePolicy` decide qué pasa, y **el valor por omisión es `Fail`**: se rechaza la petición. Es decir, mientras el Pod del guardián no atiende, ningún objeto de los tipos que vigila se puede guardar.

Las tres cosas llegan en el mismo momento y no están listas al mismo tiempo. Lo que tarda es lo que obliga a esperar.

#### 10.4.2 `--server-side`: por qué la plataforma se aplica distinto

Antes del orden, el segundo comando de la receta tiene una bandera que no habías usado: `kubectl apply --server-side`. Conviene entenderla antes de verla fallar.

El `kubectl apply` de siempre es *del lado del cliente* (*client-side*): `kubectl` calcula qué cambió y, para recordar «lo último que apliqué», guarda una copia de todo el manifiesto en una anotación del propio objeto, `kubectl.kubernetes.io/last-applied-configuration`. La [documentación de *Server-Side Apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) describe la otra forma (traducido): en lugar de que el cliente calcule y recuerde, el servidor sigue qué **gestor** (*field manager*) es dueño de cada campo del objeto. Es estable desde Kubernetes 1.22. Se pide con `--server-side`.

Para esta lección importan dos consecuencias. La primera: sin el copiado de «lo último que apliqué» al propio objeto, se acaba un límite. Una anotación tiene un tamaño máximo, y los CRD de Gateway API y de Envoy Gateway son enormes (describen en detalle cada campo de cada tipo). La guía oficial de instalación de Envoy Gateway, que ya citaste en la Lección 6, instala con `kubectl apply --server-side`, y en 10.4.3 vas a ver qué contesta el clúster cuando se omite. La segunda: con *Server-Side Apply*, quien aplica es un gestor con nombre, y si dos gestores tocan el mismo campo con valores distintos, el servidor avisa de un **conflicto** en lugar de pisar en silencio. Eso es lo que quieres cuando varias herramientas (tú, un controlador, un *pipeline*) tocan el mismo clúster.

Y una distinción para no confundir: `--server-side` cambia *quién calcula el cambio*, no *qué se aplica*. El proyecto se aplica igual con los dos modos; esta lección usa `--server-side` en los dos comandos para que el hábito sea uno solo.

#### 10.4.3 Primer error: la plataforma sin `--server-side`

Se aplica la plataforma «como siempre», sin la bandera, en un clúster vacío. La salida es larga, así que se guarda en un archivo y se mira por partes: primero cuánto se creó, después **solo lo que no es un «created»**:

```text
$ kubectl apply -k overlays/kind/plataforma > $L10_TMP/cliente.txt 2>&1; echo "código: $?"
código: 1

$ grep -c ' created$' $L10_TMP/cliente.txt
73

$ grep -v ' created$' $L10_TMP/cliente.txt | cut -c1-330
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "httproutes.gateway.networking.k8s.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "securitypolicies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(`> archivo 2>&1` guarda en el archivo lo que sale por la salida normal *y* por la de errores; `$?` es el código de salida del comando anterior; `grep -v` imprime las líneas que **no** coinciden; `cut -c1-330` recorta cada línea a 330 caracteres para que quepa.)

Léelo en orden. **El código de salida es 1**: el `apply` terminó con error. **Se crearon 73 objetos**, y tres líneas dicen lo que no se pudo: los CRD `envoyproxies.gateway.envoyproxy.io`, `httproutes.gateway.networking.k8s.io` y `securitypolicies.gateway.envoyproxy.io` «are invalid: `metadata.annotations: Too long: may not be more than 262144 bytes`». Son 262,144 bytes, es decir 256 KiB (256 × 1024): el tope que el `kube-apiserver` pone a las anotaciones de un objeto. Esa anotación es la copia de «lo último que apliqué» de la que habló 10.4.2, y estos tres CRD describen tantos campos que su propia definición, copiada dentro del objeto, pasa del tope. Se midió cada CRD de la plataforma convertido a JSON compacto (`programas/10-proyecto-final/crd-tamanos.sh`; su salida, `crd-tamanos.salida.txt`): `envoyproxies` pesa unos 649 mil bytes, `httproutes` unos 299 mil y `securitypolicies` unos 274 mil; el siguiente en tamaño, `backendtrafficpolicies`, ronda los 128 mil. Son exactamente los tres que fallaron y ninguno más.

Fíjate en lo que **no** hace ese mensaje: no dice «falta una bandera». Dice que un objeto no cabe, y hay que saber que la causa es la forma de aplicar. Y fíjate en el estado en que deja el clúster, que es lo grave: 73 de 76 objetos están creados, así que el clúster *parece* tener plataforma, pero le falta `httproutes`, el tipo de la ruta que usa la Lección 6, y le faltan dos tipos de Envoy Gateway. Un estado a medias que se ve casi sano es peor que uno que falla del todo. Este clúster se borró, y se creó otro para el siguiente experimento: es el método del curso.

#### 10.4.4 Segundo error: plataforma y proyecto en un solo comando

La pregunta natural es: ¿y por qué dos comandos? ¿No se puede juntar todo en uno, con la bandera? `fig10_01.todo-junto/kustomization.yaml` es un **programa que falla a propósito** (su primera línea lo advierte): una sola kustomización que contiene la plataforma y el proyecto.

```yaml
# fig10_01.todo-junto/kustomization.yaml — FALLA A PROPÓSITO (o funciona a medias):
# junta la plataforma y el proyecto en UN solo «kubectl apply». Las dos mitades
# no tienen orden de espera entre sí: el proyecto pide tipos (IPAddressPool,
# GatewayClass, Gateway, HTTPRoute) que la plataforma todavía no ha registrado.
# Se aplica con:  kubectl apply --server-side -k fig10_01.todo-junto
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../overlays/kind/plataforma
- ../overlays/kind
```

Se aplica en un clúster vacío (otro, recién creado) con la bandera correcta. Se mira lo mismo que antes: cuántos objetos entraron y qué no.

```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto1.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto1.txt
99

$ grep -v serverside-applied $L10_TMP/junto1.txt | cut -c1-330
resource mapping not found for name: "revisor" namespace: "revisor" from "fig10_01.todo-junto": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "eg" namespace: "" from "fig10_01.todo-junto": no matches for kind "GatewayClass" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "revisor" namespace: "revisor" from "fig10_01.todo-junto": no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "curso" namespace: "metallb-system" from "fig10_01.todo-junto": no matches for kind "IPAddressPool" in version "metallb.io/v1beta1"
ensure CRDs are installed first
resource mapping not found for name: "curso" namespace: "metallb-system" from "fig10_01.todo-junto": no matches for kind "L2Advertisement" in version "metallb.io/v1beta1"
ensure CRDs are installed first
```

Léelo igual. El código vuelve a ser 1, y esta vez entraron **99 objetos** de los 104 que arma el árbol (76 de la plataforma y 28 del proyecto). Los cinco que no entraron dicen lo mismo: `no matches for kind "Gateway"`, `"GatewayClass"`, `"HTTPRoute"`, `"IPAddressPool"` y `"L2Advertisement"`, cada uno con el aviso `ensure CRDs are installed first` («asegúrate de que los CRD estén instalados primero»). Compáralos con las cinco condiciones `Established` que espera 10.5.2: son los mismos cinco tipos. Entraron los Deployments, los Services, las reglas de red, el espacio de nombres y los CRD mismos, que no dependen de ningún tipo nuevo; no entró nada que sí dependa. `kubectl` resuelve **al principio**, antes de crear nada, qué tipos conoce el servidor, y con esa lista revisa los 104 objetos. Los CRD van en la lista, pero los objetos que los usan se revisan contra el catálogo que había *antes* de crearlos: por eso cinco fallan aunque sus CRD se creen en el mismo comando. Un `apply` no vuelve a preguntar a medio camino ([`mapper.go` de cli-runtime](https://github.com/kubernetes/cli-runtime/blob/master/pkg/resource/mapper.go)).

La tentación que sigue es la peor: repetir el mismo comando, sin cambiar nada y sin esperar, a ver si esta vez pasa. Se hizo, y esto fue lo que pasó:


```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto2.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto2.txt
102

$ grep -v serverside-applied $L10_TMP/junto2.txt | cut -c1-330
Error from server (InternalError): Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
Error from server (InternalError): Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
```

Hubo progreso, y es lo que hace traicionero al método. Ahora entraron **102 objetos**: los tres tipos de Gateway API ya existían, así que `Gateway`, `GatewayClass` y `HTTPRoute` pasaron. Quedan dos, el rango y su anuncio, y fallan por otra causa: `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connect: connection refused`. El tipo `IPAddressPool` ya existe, pero el guardián que MetalLB pone delante de él (10.4.1) todavía no escucha: el Pod del controlador está arrancando. Como `failurePolicy` es `Fail`, el `kube-apiserver` rechaza el objeto. `connection refused` quiere decir que la dirección del Service del guardián (la que aparece después de `dial tcp`, una IP del clúster que en tu corrida será otra) existe, pero nadie atiende detrás.

Cada reintento descubre la siguiente capa de lo que faltaba: primero los tipos, después los guardianes. Un tercer intento probablemente pasaría (no se midió, porque no tiene sentido medirlo), y entonces quedaría escrito en la wiki «repite hasta que pase». Eso es lo contrario de una receta: no dice cuántas veces, no dice qué esperar y, el día que un intento falle por una causa distinta, no habría forma de distinguirla. Lo único que cambió entre el intento 1 y el 2 fue el paso del tiempo; lo que hace falta es nombrar lo que se espera.

#### 10.4.5 Lo que enseñan los dos errores

Los dos errores son versiones del mismo hecho, y sirven para fijar tres reglas:

1. **La plataforma va primero y con `--server-side`.** Trae tipos nuevos, controladores y guardianes. Es un comando aparte porque tiene una condición de salida: «los tipos están establecidos y los controladores están arriba».
2. **Entre la plataforma y el proyecto hay una espera por condición.** No un `sleep 30`, que funciona en tu máquina y falla en una más lenta, sino `kubectl wait --for=condition=…`. La [documentación de `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) lo describe como esperar «una condición específica en uno o varios recursos» y sale con error si no llega en el tiempo que le diste (`--timeout`). En la corrida verás que, cuando se cumple, imprime `condition met`. Un `sleep` te dice «pasó tiempo»; `wait` te dice «pasó lo que yo necesitaba». Y cuando falla, falla con nombre.
3. **El proyecto va después, en su propio comando.** Todo lo que usa un tipo nuevo, un controlador o un guardián de la plataforma va aquí.

La receta queda en tres líneas: `apply` de la plataforma, `wait`, `apply` del proyecto. Es el «dos comandos y una espera» del título de la lección, y la primera meta del curso lo cuenta así: son tres pasos, y el orden es lo que los define.

También hay una razón de fondo, y no solo de este curso. La documentación de Helm, que 10.9 nombra, tiene el mismo problema y lo dice con otras palabras en sus [prácticas recomendadas sobre CRD](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) (traducido): «la declaración [del CRD] debe estar registrada antes de que se pueda usar cualquier recurso de ese tipo, y el registro a veces tarda unos segundos». No es una rareza de Kustomize ni de `kubectl`; es una propiedad de cómo Kubernetes extiende sus tipos.

### 10.5 Levantar a mano: plataforma, espera, proyecto

Ahora el camino bueno, en un clúster recién creado, con cada paso a la vista. Es el clúster de 10.1 (el de las salidas de esa sección): tres nodos, las dos imágenes cargadas, ningún CRD. Y antes de **cada** comando que cambia algo, `ctx &&`.

#### 10.5.1 Paso 1: la plataforma

```bash
ctx && kubectl apply --server-side -k overlays/kind/plataforma > "$L10_TMP/plataforma.txt"
```

Con la bandera y en un clúster vacío, todo entra. El comando imprime una línea por objeto; se guardó en un archivo y esto es lo que se ve de él:

```text
$ kubectl apply --server-side -k overlays/kind/plataforma > $L10_TMP/plataforma.txt; grep -c serverside-applied $L10_TMP/plataforma.txt
76

$ head -4 $L10_TMP/plataforma.txt
namespace/envoy-gateway-system serverside-applied
namespace/metallb-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
```

Son **76** líneas, una por objeto, y ninguna dice `Error`. `serverside-applied` quiere decir que el servidor aplicó el objeto: lo creó o lo actualizó; en un clúster vacío, todos son creaciones. Las dos primeras líneas crean los espacios de nombres `envoy-gateway-system` y `metallb-system`, y las siguientes son CRD (`backends.gateway.envoyproxy.io`, `backendtlspolicies.gateway.networking.k8s.io`…). Compara con 10.4.3: con `--server-side`, los tres CRD que no cabían entran como los demás, porque ya no se les pega la copia de «lo último que apliqué».

El clúster ya conoce los tipos nuevos, pero sus controladores todavía están arrancando. Así se ve en este instante:

```text
$ kubectl get crd | wc -l
      31

$ kubectl get pods -n metallb-system
NAME                          READY   STATUS              RESTARTS   AGE
controller-76f4cf76b7-kclm8   0/1     ContainerCreating   0          0s
speaker-cbfnt                 0/1     ContainerCreating   0          0s
speaker-dgln6                 0/1     ContainerCreating   0          0s
speaker-swc2d                 0/1     ContainerCreating   0          0s
```

El clúster ya conoce **30** tipos nuevos (`kubectl get crd | wc -l` cuenta 31 porque incluye el renglón de encabezados). Y los Pods de MetalLB, en el primer segundo, están todos en `0/1 ContainerCreating`: el `controller` y un `speaker` por nodo todavía están descargando su imagen y arrancando. Este es el instante peligroso de 10.4: los tipos existen y los guardianes no atienden. Aplicar el proyecto *ahora* daría el `connection refused` del segundo error.

#### 10.5.2 Paso 2: la espera

Cinco esperas, cada una con su condición. Las cinco juntas son «la plataforma está lista»:

```bash
ctx && kubectl wait --for=condition=Established --timeout=120s \
  crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
ctx && kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
ctx && kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
ctx && kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
ctx && kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
```

```text
$ kubectl wait --for=condition=Established --timeout=120s crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
deployment.apps/controller condition met

$ kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
deployment.apps/envoy-gateway condition met

$ kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
deployment.apps/metrics-server condition met
```

Las cinco terminan bien. La primera, de tipos, contesta de inmediato `condition met` para los cinco CRD: ya estaban establecidos. Las otras son las lentas: el `controller` de MetalLB, los tres `speaker` (el avance dice `0 of 3 updated pods are available…`, después `1 of 3`, `2 of 3`, y por fin `successfully rolled out`), el controlador de Envoy Gateway y `metrics-server`. Los nodos son nuevos y no tienen ninguna imagen: cada uno tiene que descargar de internet las de MetalLB, Envoy Gateway y `metrics-server` antes de poder arrancar los Pods. En esta corrida la espera completa duró 153 segundos; en las corridas de preparación de la lección varió desde esos 153 hasta 881 segundos (casi quince minutos), según la conexión y la carga de la máquina. Cada `kubectl wait` lleva su propio tope de 600 segundos; los 881 fueron la suma de las cinco esperas, no una sola (la salida está en `corridas-preparacion/corrida4.txt`). Si en tu conexión una sola agota los 600, el error no deshace nada: repite el mismo comando. No se separó cuánto de ese tiempo es descarga y cuánto es arranque, así que no se afirma. Lo que sí se afirma es lo que debes planear: **la espera es la parte más larga del levantamiento**, y por eso conviene que sea una espera por condición y no un tiempo fijo que alguien tenga que adivinar.

Y una espera también sirve para saber cuándo algo **no** llega. Si le pides a `kubectl wait` una condición que no se cumple, con un tope corto, se rinde con un error en lugar de colgarse. Aquí se le pide al controlador de Envoy Gateway, que está `Available`, que pase a no estarlo, y se le dan 5 segundos:

```text
$ kubectl wait --for=condition=Available=false --timeout=5s -n envoy-gateway-system deployment/envoy-gateway
error: timed out waiting for the condition on deployments/envoy-gateway
[código de salida: 1]
```

`error: timed out waiting for the condition on deployments/envoy-gateway`, y el guion anota `[código de salida: 1]`. Es el comportamiento que quieres de una espera: no se cuelga, no inventa un éxito y dice qué condición de qué objeto no llegó. Un `sleep 300` seguido de un `apply` te habría dejado sin esa información.

Léelas con la lista de tres cosas de 10.4.1 en la mano. La primera espera es de **tipos**: `Established` es la condición del CRD. Las otras cuatro son de **controladores**: `Available` para los Deployments (`controller` de MetalLB, `envoy-gateway`, `metrics-server`) y `rollout status` para el `DaemonSet` `speaker`. Un `DaemonSet` no tiene `Available`; tiene un avance de «cuántos de los Pods que debe haber están listos», y `rollout status` lo sigue hasta que son todos (uno por nodo). El *webhook* de MetalLB lo atiende el Pod `controller`: cuando está `Available`, el guardián ya contesta.

#### 10.5.3 Paso 3: el proyecto

```bash
ctx && kubectl apply --server-side -k overlays/kind
```

```text
$ kubectl apply --server-side -k overlays/kind
namespace/revisor serverside-applied
serviceaccount/observador serverside-applied
serviceaccount/prueba serverside-applied
serviceaccount/reporte serverside-applied
serviceaccount/revisor serverside-applied
role.rbac.authorization.k8s.io/observador serverside-applied
rolebinding.rbac.authorization.k8s.io/observador serverside-applied
configmap/revisor-config-t6cm6872fk serverside-applied
secret/revisor-token-fgdb694k82 serverside-applied
service/prueba serverside-applied
service/revisor serverside-applied
persistentvolumeclaim/reportes serverside-applied
deployment.apps/prueba serverside-applied
deployment.apps/revisor serverside-applied
cronjob.batch/reporte serverside-applied
poddisruptionbudget.policy/revisor serverside-applied
horizontalpodautoscaler.autoscaling/revisor serverside-applied
gateway.gateway.networking.k8s.io/revisor serverside-applied
gatewayclass.gateway.networking.k8s.io/eg serverside-applied
httproute.gateway.networking.k8s.io/revisor serverside-applied
ipaddresspool.metallb.io/curso serverside-applied
l2advertisement.metallb.io/curso serverside-applied
networkpolicy.networking.k8s.io/acceso-revisor-salida serverside-applied
networkpolicy.networking.k8s.io/cerrado serverside-applied
networkpolicy.networking.k8s.io/dns serverside-applied
networkpolicy.networking.k8s.io/prueba-entrada serverside-applied
networkpolicy.networking.k8s.io/revisor-entrada serverside-applied
networkpolicy.networking.k8s.io/revisor-salida serverside-applied
```

Son **28** líneas, y cada fila de la tabla de 10.2 está ahí: el espacio de nombres, las cuatro cuentas de servicio, el rol y su asignación, el `ConfigMap` y el `Secret` con su *hash*, los dos Services, el volumen, los dos Deployments, el `CronJob`, el `PodDisruptionBudget`, el escalado, el `Gateway` con su `HTTPRoute`, las seis reglas de red y los **tres** objetos que sólo existen por el overlay: la `GatewayClass` `eg`, el rango y el anuncio de MetalLB. Fíjate en que no salen al final sino repartidos: Kustomize ordena la salida por tipo de objeto, no por el archivo del que vienen. El nombre del `ConfigMap`, `revisor-config-t6cm6872fk`, es **el mismo** de las Lecciones 4 y 5, porque la lista de servicios es la misma: el *hash* es de su contenido. El del `Secret` cambia en cada corrida, porque el token es nuevo. Y no hay ninguna línea que empiece con `Warning`, pero esa ausencia se prueba, no se mira.

Una afirmación como «no hay advertencias» se prueba contando, y con un caso donde sí las haya (10.7 lo hace). Aquí el conteo, con `-i` para no depender de mayúsculas:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -ci warning
0
[código de salida: 1]
```

El `0` es el conteo. El `[código de salida: 1]` que anota el guion no es un fallo: `grep` sale con 1 cuando no encuentra ninguna línea, aunque con `-c` imprima el cero. Aquí significa «cero advertencias».

Después, dos esperas más: a que los Deployments estén `Available` y a que la puerta esté `Programmed` (la condición del `Gateway` que dice «ya tiene dirección y un Envoy que la atiende»):

```bash
ctx && kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
ctx && kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
```

```text
$ kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
deployment.apps/revisor condition met
deployment.apps/prueba condition met

$ kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
gateway.gateway.networking.k8s.io/revisor condition met
```

Falta una espera que `kubectl wait` no cubre bien: el escalado automático necesita unos segundos para leer sus primeras métricas, y mientras no las tenga muestra `<unknown>`. Esta vez no se resuelve con un `sleep` a ciegas sino con un ciclo corto y **visible**, que revisa cada 5 segundos hasta dos minutos y se detiene en cuanto el escalado ya tiene una métrica:

```bash
for _ in $(seq 1 24); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

Hay un `sleep`, y está bien: es la **espera de una condición con un tope**. Cada vuelta pregunta si ya pasó lo que importa. Si no pasa en 24 vueltas, el ciclo se rinde y el siguiente comando te enseña el `<unknown>` en lugar de esconderlo.

#### 10.5.4 Verlo funcionar

Todo lo que las nueve lecciones construyeron, en una sola consulta:

```text
$ kubectl get all,pvc,cronjob,hpa,pdb,networkpolicy,gateway,httproute -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rzh88    1/1     Running   0          82s
pod/revisor-654b5d75dc-6m6s6   1/1     Running   0          82s
pod/revisor-654b5d75dc-dq4pp   1/1     Running   0          82s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.57.22     <none>        9000/TCP   82s
service/revisor   ClusterIP   10.96.239.233   <none>        80/TCP     82s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           82s
deployment.apps/revisor   2/2     2            2           82s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       82s
replicaset.apps/revisor-654b5d75dc   2         2         2       82s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          82s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          82s

NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 82s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     82s

NAME                                                    POD-SELECTOR               AGE
networkpolicy.networking.k8s.io/acceso-revisor-salida   acceso-revisor=permitido   82s
networkpolicy.networking.k8s.io/cerrado                 <none>                     82s
networkpolicy.networking.k8s.io/dns                     <none>                     82s
networkpolicy.networking.k8s.io/prueba-entrada          app=prueba                 82s
networkpolicy.networking.k8s.io/revisor-entrada         app=revisor                82s
networkpolicy.networking.k8s.io/revisor-salida          app=revisor                82s

NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.30.255.200   True         82s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               82s
```

Léela por bloques, de arriba abajo.

- **Pods.** Los dos del `revisor` y el de `prueba`, los tres `1/1 Running`. Si levantas el proyecto justo en un minuto múltiplo de cinco, verás además un cuarto Pod, `reporte-…`, en `0/1 Completed`: la tarea programada de la Lección 8, que ya corrió y terminó bien (en una corrida de preparación de esta lección sí apareció; en la que se pega aquí, todavía no).
- **Services.** Los dos son `ClusterIP`, sin `EXTERNAL-IP`: ya no existe el `LoadBalancer` directo de la Lección 6. La única puerta es el Gateway.
- **Deployments y ReplicaSets.** `2/2` y `1/1`. Cada Deployment tiene un ReplicaSet con su *hash*. Si lo ves distinto en tu corrida, es normal: depende del nombre del `Secret`, que cambia con el token.
- **Escalado.** `cpu: …/50%`, `MINPODS 2`, `MAXPODS 6`, y las dos réplicas actuales. Que haya un porcentaje y no `<unknown>` quiere decir que `metrics-server` ya entregó su primera lectura; por eso se espera con el ciclo de 10.5.3.
- **CronJob.** La programación `*/5 * * * *`, sin suspender, `ACTIVE 0` y `LAST SCHEDULE <none>`: todavía no ha disparado ni una vez. Cuando dispare, aparecerá un Job con su Pod.
- **Volumen.** El PVC `reportes` está en `Pending`, y es lo correcto: en la Lección 8 viste que la clase `standard` espera al primer Pod que lo use (`WaitForFirstConsumer`) antes de crear el disco. Pasará a `Bound` cuando el `CronJob` dispare por primera vez.
- **`PodDisruptionBudget`.** `MIN AVAILABLE 1`, y `ALLOWED DISRUPTIONS 1`: con dos réplicas, el clúster puede sacar una a la vez.
- **Reglas de red.** Las seis de la Lección 7, con sus selectores.
- **Gateway.** Clase `eg`, **dirección `172.30.255.200`** (la primera del rango del overlay) y `PROGRAMMED True`. Es la dirección que MetalLB repartió. **`HTTPRoute`.** Sin nombres de sitio (`HOSTNAMES` vacío): atiende cualquiera.

Y las métricas, que son la prueba de que `metrics-server` y el escalado están conectados:

```text
$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-rzh88    1m           1Mi             
revisor-654b5d75dc-6m6s6   1m           1Mi             
revisor-654b5d75dc-dq4pp   2m           1Mi             
```

Falta lo más importante: que **alguien de fuera** llegue. La dirección de la puerta sale del propio `Gateway`, y el cliente es un contenedor de Docker conectado a la misma red que los nodos, **fuera** del clúster (el mismo truco de la Lección 6):

```bash
IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
CURL='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
docker run --rm --network kind $CURL -s -m 5 "http://$IP_GW/salud"
docker run --rm --network kind $CURL -s -m 5 -o /dev/null -w '%{http_code}\n' "http://$IP_GW/api/estados"
docker run --rm --network kind $CURL -s -m 5 -H "Authorization: Bearer $TOKEN" "http://$IP_GW/api/estados?formato=tabla"
```

(En el bloque de salida de abajo, el guion abrevia cada `docker run … curl` a `curl`, para que quepa. `$TOKEN` es la variable de 10.1.2.)

```text
$ curl -s -m 5 http://172.30.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.30.255.200/api/estados
401

$ curl -s -m 5 -H "Authorization: Bearer $TOKEN" 'http://172.30.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200
```

Las tres peticiones llegaron desde fuera del clúster a la dirección que MetalLB le dio al Gateway. `/salud` contesta sin pedir nada. `/api/estados` **sin token** da `401` (la Lección 4: el `revisor` exige `Authorization: Bearer …`). Y con el token, la tabla del reporte. Fíjate en que el token llega por la puerta en un encabezado, en texto plano: es el punto 4 de la lista de 10.10.

En tu terminal el nombre de la red es `kind` (así lo dejó el bloque de arriba). Si la corrida no usó esa red, la sección «Sobre las corridas» lo dice.

### 10.6 Automatizar sin esconder el orden

#### 10.6.1 Qué se automatiza y qué no se debe esconder

A mano, el levantamiento son tres bloques y ocho esperas. Para repetirlo en cada clúster nuevo —el tuyo mañana, el de una compañera, el de un paso automático de un *pipeline*— conviene un guion. Y aquí hay una decisión de diseño que separa un guion que ayuda de uno que estorba. Hay dos formas de escribirlo:

- **El guion que esconde el orden.** Una sola línea que «reintenta hasta que pase»: `until kubectl apply -k .; do sleep 5; done`, o un `sleep 120` entre dos aplicaciones, o un `|| true` para que nada se detenga. Funciona casi siempre y cuando falla no dice por qué: el ciclo se queda dando vueltas, o el `sleep` fue corto en la máquina lenta, o el error se tragó en silencio. En 10.4.4 viste qué hace el reintento ciego: aplica a medias y te deja a ti adivinar qué falta.
- **El guion que muestra el orden.** Los mismos tres pasos, cada uno con nombre, cada uno con su comprobación de contexto, con esperas por **condición** y con un tope de tiempo. Cuando falla, falla en un paso con nombre, con un mensaje de `kubectl` que dice qué condición no llegó. Y quien lo lee aprende el orden, que es la mitad del valor.

Este es el segundo. Se llama `levantar.sh`, vive en la carpeta de la lección y es lo que un paso de un *pipeline* llamaría tal cual:

```bash
#!/usr/bin/env bash
# levantar.sh — Lección 10: el proyecto completo en un clúster recién creado, en
# TRES pasos explícitos, sin esconder el orden. Es lo que un paso de pipeline
# haría igual: la única entrada es el contexto de kubectl que espera encontrar.
#
#   1. la plataforma: metrics-server, MetalLB y Envoy Gateway (traen tipos nuevos,
#      controladores y webhooks)
#   2. esperar a que la plataforma esté lista (tipos registrados, controladores arriba)
#   3. el proyecto
#
# Por qué hay orden: un IPAddressPool, una GatewayClass o un Gateway solo existen
# cuando su CRD ya está registrado, y MetalLB rechaza su rango si su webhook
# todavía no atiende.
#
# Requisitos: un clúster de kind con las dos imágenes cargadas (kind load
# docker-image) y su contexto activo. Uso, desde esta carpeta:
#   ./levantar.sh kind-curso-k8s-l10
set -euo pipefail
cd "$(dirname "$0")"
ESPERADO="${1:?uso: ./levantar.sh <contexto-esperado>   (por ejemplo kind-curso-k8s-l10)}"
NODO_CONTROL="${ESPERADO#kind-}-control-plane"

# Antes de CADA paso que cambia algo: ¿el contexto activo es el esperado?
contexto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  [ "$actual" = "$ESPERADO" ] || { echo "ALTO: el contexto activo es «$actual», no «$ESPERADO»." >&2; exit 1; }
}

# El token no se versiona: si falta, se genera uno nuevo (de mentira, para el curso).
[ -s base/token.txt ] || (umask 077; openssl rand -hex 16 > base/token.txt)

echo "== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?"
contexto
RANGO="$(sed -n 's/^ *- *\([0-9.]*\)-.*/\1/p' overlays/kind/metallb-pool.yaml | head -1)"
IP_NODO="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODO_CONTROL")"
echo "primer IP del rango: $RANGO · IP del nodo de control: $IP_NODO"
[ "${RANGO%.*.*}" = "${IP_NODO%.*.*}" ] || {
  echo "ALTO: el rango de overlays/kind/metallb-pool.yaml no está en la red de los nodos (se compara la red /16)." >&2; exit 1; }

echo "== 1. Plataforma"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind/plataforma)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
echo "(paso 1 terminó a los $SECONDS s)"

echo "== 2. Esperar a la plataforma"
contexto
kubectl wait --for=condition=Established --timeout=120s \
  crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
echo "(paso 2 terminó a los $SECONDS s)"

echo "== 3. Proyecto"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
kubectl get gateway revisor -n revisor
echo "(paso 3 terminó a los $SECONDS s)"
```

#### 10.6.2 El guion, línea por línea

Se lee de arriba abajo, y casi todo es algo que ya conoces con otra cara.

**`set -euo pipefail`.** Tres opciones de `bash` en una. `-e` detiene el guion al primer comando que falla. `-u` hace que usar una variable que no existe sea un error, en lugar de leerla vacía. `-o pipefail` hace que una tubería (`a | b`) falle si falla *cualquiera* de sus partes, no solo la última. Juntas son la diferencia entre un guion que se detiene donde está el problema y uno que sigue como si nada. Es la misma razón por la que `levantar.sh` usa `|| true` en un solo sitio: al leer el contexto activo, donde un fallo se acepta (el guion lo compara después y se detiene con un mensaje claro). Lo mismo en `probar-levantar.sh`, en la limpieza del clúster y en el conteo de clústeres vivos, y en los fallos a propósito de `correr.sh`: cada `|| true` está pegado a un comando concreto cuyo fallo se acepta y se dice por qué, que es lo único que «Lo que se hace mal» admite.

**`ESPERADO="${1:?uso: …}"`.** El guion **no adivina** en qué clúster está: recibe el contexto como argumento y, si falta, imprime el uso y se detiene. `${1:?mensaje}` significa «el primer argumento, y si está vacío, falla con este mensaje». Es lo contrario de un guion que usa «el clúster que esté activo»: un guion que instala MetalLB y Envoy Gateway en el contexto activo, sin preguntar, puede instalar esas cosas en el clúster equivocado.

**`contexto()`.** La función `ctx` de 10.1, pero para un guion: compara `kubectl config current-context` con `ESPERADO` y, si no coinciden, imprime «ALTO» y hace `exit 1`. Se llama **antes de cada paso**, no una sola vez al principio, porque un guion largo corre minutos y alguien (o algo) puede cambiar el contexto entre un paso y otro.

**El paso 0: la red.** Esto es nuevo y existe por una razón concreta. El rango de direcciones de MetalLB vive en `overlays/kind/metallb-pool.yaml`. Si ese rango no cae en la misma red que los nodos, MetalLB le asigna una dirección al Gateway, `kubectl` dice que todo está bien, y nadie desde fuera puede llegar a ella: el fallo es silencioso. El `sed` saca la primera dirección del rango, `docker inspect` saca la IP del nodo de control, y la comparación `${RANGO%.*.*}` (quitar los dos últimos números: `172.30.255.200` queda `172.30`) contra `${IP_NODO%.*.*}` comprueba que las dos están en la misma red `/16`. Es una comprobación sencilla —supone redes de ese tamaño, y el mensaje de error lo dice—, pero convierte un fallo mudo en un «ALTO» con causa.

**El paso 1.** Captura la salida de `kubectl apply` en una variable (`SALIDA="$(…)"`) y muestra solo el conteo de `serverside-applied`. Si `kubectl apply` falla, la asignación falla y `set -e` detiene el guion: no se llega al conteo. No se descarta la salida con `>/dev/null`: se **mide**.

**El paso 2.** Las cinco esperas de 10.5.2, sin cambios. Cada una con su tope (`--timeout`): 120 segundos para que los CRD existan, 600 (diez minutos) para los controladores, que dependen de lo que tarde tu conexión en descargar imágenes.

**El paso 3.** Aplica el proyecto y espera dos cosas: los Deployments `Available` y la puerta `Programmed`. Al final, `kubectl get gateway` imprime el resultado que quieres ver.

**`$SECONDS`.** Una variable de `bash` que cuenta los segundos desde que arrancó el guion. Cada paso reporta a los cuántos segundos terminó. No es decoración: si un paso se pone lento, lo ves, y los tiempos de este guion son los que 10.6.3 usa para decir cuánto tarda levantar el proyecto.

Lo que **no** hace es también una decisión. No crea el clúster (eso es de quien llama: tú, o un paso previo del *pipeline*). No carga las imágenes. Y no hace `curl`: comprobar que la puerta responde desde fuera necesita un cliente en la red de Docker, y eso es una prueba, no un levantamiento. Un guion que levanta y otro que prueba se pueden cambiar por separado.

Un detalle más sobre el código de salida. `levantar.sh` sale con 0 solo si **todo** el recorrido terminó; con cualquier fallo, sale con un código distinto de 0 en el paso donde ocurrió. Eso es lo único que un *pipeline* necesita saber para marcar un paso como verde o rojo, y por eso el guion lo cuida y no depende de que alguien lea el texto de la salida.

#### 10.6.3 Probarlo de verdad: crear, levantar, borrar, recrear

Un guion que nunca se ha corrido contra un clúster vacío es como el respaldo del caso de GitLab: existe y no se sabe si sirve. Se prueba con `probar-levantar.sh`: crea el clúster, corre `levantar.sh`, comprueba desde fuera que la puerta responde, **borra el clúster** y repite todo una segunda vez. Si la primera vuelta pasa por casualidad (algo que ya estaba, un caché, una espera que alcanzó), la segunda lo delata, porque parte de cero otra vez.

```bash
#!/usr/bin/env bash
# probar-levantar.sh — comprueba levantar.sh en un clúster NUEVO curso-k8s-l10, con
# un kubeconfig temporal propio, y borra el clúster al terminar. Dos vueltas: crear,
# levantar, borrar, recrear y levantar otra vez (meta 1 del curso).
#
# Uso, desde esta carpeta:   ./probar-levantar.sh
# Variables opcionales:
#   RED_DOCKER   red de Docker donde viven los nodos (por omisión «kind»). Si usas
#                otra, el rango de overlays/kind/metallb-pool.yaml debe caer en ella.
#   CUPO_MAXIMO  en una máquina compartida: antes de crear un clúster espera a que
#                haya menos de CUPO_MAXIMO clústeres «curso-k8s-*».
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=curso-k8s-l10
CONTEXTO="kind-$CLUSTER"
RED_DOCKER="${RED_DOCKER:-kind}"
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
L10_TMP="$(mktemp -d /tmp/curso-k8s-l10.XXXX)"
export KUBECONFIG="$L10_TMP/kubeconfig"

limpiar() {
  if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  rm -f base/token.txt
  case "$L10_TMP" in /tmp/curso-k8s-l10.?*) rm -rf -- "$L10_TMP" ;; esac
  return 0
}
trap limpiar EXIT

if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster llamado «$CLUSTER»; este guion no lo toca." >&2; exit 1
fi

crear() {
  if [ -n "${CUPO_MAXIMO:-}" ]; then
    until [ "$(kind get clusters 2>/dev/null | grep -c '^curso-k8s-' || true)" -lt "$CUPO_MAXIMO" ]; do
      echo "(espera de cupo: ya hay $CUPO_MAXIMO clústeres de curso; reviso en 60 s)"; sleep 60
    done
  fi
  if [ "$RED_DOCKER" = kind ]; then
    kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  else
    KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED_DOCKER" \
      kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  fi
  [ "$(kubectl config current-context)" = "$CONTEXTO" ] || { echo "ALTO: contexto equivocado" >&2; exit 1; }
  kubectl wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
  kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name "$CLUSTER" >/dev/null 2>&1
}

for vuelta in 1 2; do
  printf '\n## Vuelta %s: clúster recién creado\n' "$vuelta"
  t0=$SECONDS; crear; echo "(crear el clúster y cargar las imágenes tardó $((SECONDS - t0)) s)"
  t0=$SECONDS
  printf '\n$ ./levantar.sh %s\n' "$CONTEXTO"
  ./levantar.sh "$CONTEXTO" 2>&1
  echo "(levantar.sh tardó $((SECONDS - t0)) s)"
  IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
  printf '\n$ curl -s http://%s/salud   # desde un contenedor fuera del clúster\n' "$IP_GW"
  docker run --rm --network "$RED_DOCKER" "$CURL_IMAGEN" -s -m 5 "http://$IP_GW/salud"; echo
  rm -f base/token.txt
  kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  echo "(clúster borrado)"
done
```

Las partes que no son del levantamiento ya las has visto: el `kubeconfig` temporal, el `trap limpiar EXIT` que **borra el clúster aunque el guion falle a la mitad** (un `trap … EXIT` se ejecuta al salir del guion, sea por terminar o por un error), y la comprobación de que `curso-k8s-l10` no exista ya antes de crearlo. `limpiar` solo borra un clúster llamado exactamente `curso-k8s-l10`, y la carpeta temporal solo si su ruta empieza con `/tmp/curso-k8s-l10.` (el `case` de siempre).

Lo que sí es nuevo es `CUPO_MAXIMO`. Es para máquinas compartidas, y la corrida de esta lección la usó: antes de crear un clúster, espera a que haya menos de ese número de clústeres `curso-k8s-*` vivos. Sin la variable, no espera. En tu máquina, sola, no la necesitas.

`probar-levantar.sh` usa su propio `base/token.txt` (`levantar.sh` lo genera si no existe) y **lo borra al terminar**: si ya tienes uno, guárdalo antes o déjalo que lo regenere.

La salida completa de la prueba, con las dos vueltas:

```text
## Vuelta 1: clúster recién creado
(crear el clúster y cargar las imágenes tardó 39 s)

$ ./levantar.sh kind-curso-k8s-l10
== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?
primer IP del rango: 172.30.255.200 · IP del nodo de control: 172.30.0.4
== 1. Plataforma
objetos aplicados: 76
(paso 1 terminó a los 5 s)
== 2. Esperar a la plataforma
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
deployment.apps/controller condition met
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out
deployment.apps/envoy-gateway condition met
deployment.apps/metrics-server condition met
(paso 2 terminó a los 234 s)
== 3. Proyecto
objetos aplicados: 28
deployment.apps/revisor condition met
deployment.apps/prueba condition met
gateway.gateway.networking.k8s.io/revisor condition met
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.30.255.200   True         22s
(paso 3 terminó a los 256 s)
(levantar.sh tardó 256 s)

$ curl -s http://172.30.255.200/salud   # desde un contenedor fuera del clúster
{"estado":"vivo","version":"1.6.0"}

(clúster borrado)

## Vuelta 2: clúster recién creado
(crear el clúster y cargar las imágenes tardó 35 s)

$ ./levantar.sh kind-curso-k8s-l10
== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?
primer IP del rango: 172.30.255.200 · IP del nodo de control: 172.30.0.3
== 1. Plataforma
objetos aplicados: 76
(paso 1 terminó a los 4 s)
== 2. Esperar a la plataforma
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
deployment.apps/controller condition met
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out
deployment.apps/envoy-gateway condition met
deployment.apps/metrics-server condition met
(paso 2 terminó a los 250 s)
== 3. Proyecto
objetos aplicados: 28
deployment.apps/revisor condition met
deployment.apps/prueba condition met
gateway.gateway.networking.k8s.io/revisor condition met
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.30.255.200   True         61s
(paso 3 terminó a los 315 s)
(levantar.sh tardó 315 s)

$ curl -s http://172.30.255.200/salud   # desde un contenedor fuera del clúster
{"estado":"vivo","version":"1.6.0"}

(clúster borrado)
(la corrida completa tardó 1755 s)
```

Las dos vueltas dicen lo mismo, y es lo que se quería probar. El paso 0 confirma que el rango empieza en `172.30.255.200` y que el nodo de control está en `172.30.0.x` (la IP del nodo cambia de una vuelta a otra: `.4` y `.3`; lo único que importa es la red). El paso 1 aplica **76** objetos en unos 5 segundos. El paso 2 es el que dura: del segundo 5 al 234 en la primera vuelta y del 4 al 250 en la segunda (marcas acumuladas desde que arrancó el guion), es decir, **casi todo el levantamiento es esperar** a que los nodos bajen imágenes y arranquen la plataforma. El paso 3 aplica **28** objetos y espera: 22 segundos en la primera vuelta y 65 en la segunda (el Gateway marcaba 22 s y 61 s de edad al final: `AGE` es la edad del objeto cuando se hizo el `get`, no el tiempo hasta `Programmed`). Cada «paso N terminó a los X s» es el tiempo acumulado desde que arrancó el guion, no la duración del paso. `levantar.sh` tardó 256 y 315 segundos. En las dos vueltas la puerta tomó `172.30.255.200`, `curl` desde fuera contestó `{"estado":"vivo","version":"1.6.0"}`, y el clúster se borró. Que la segunda vuelta, partiendo de cero otra vez, pase igual es la **meta 1** del curso: reconstruir sin corregir nada a mano.

#### 10.6.4 Cómo se vería en un *pipeline*

No hace falta un *pipeline* para esta lección, pero sí saber cómo se conectaría, porque es el uso para el que está pensado el guion. Un paso de *pipeline* de cualquier herramienta se reduce a cuatro cosas, y `levantar.sh` ya las tiene todas:

1. **Una entrada explícita.** El contexto (`kind-curso-k8s-l10`) es un argumento, no una suposición. En un *pipeline* real sería el clúster al que ese paso tiene credenciales.
2. **Credenciales mínimas.** Este guion crea CRD y *webhooks*, que son objetos de todo el clúster, así que necesita permisos de administrador del clúster. En un entorno real no se le da a un *pipeline* la cuenta del administrador de todo: se le da una cuenta propia (RBAC, Lección 7) con los permisos justos para lo que instala. En `kind` no hay dos cuentas, así que el curso no lo practica, pero lo nombra.
3. **Un código de salida honesto.** 0 si todo terminó, distinto de 0 si no. Es la única información que el *pipeline* lee.
4. **Una salida que se pueda leer después.** Los tres encabezados `== 1.`, `== 2.`, `== 3.`, los conteos y los segundos por paso son lo que alguien lee a las 7:50 de un lunes cuando el paso 2 se puso rojo.

Y lo que el guion no debe volverse: un lugar donde se acumulen parches. Si un paso se rompe por una causa nueva, se arregla la causa, no se añade un `sleep`.

### 10.7 La revisión final contra `restricted`

#### 10.7.1 Qué pide `restricted`, en concreto

La Lección 2 puso el `securityContext` en el primer Deployment; la 7 puso el nivel `restricted` en el espacio de nombres. Ahora toca comprobar, con el clúster y no de memoria, que **todo** lo que está en el espacio `revisor` lo cumple. Primero, qué exige. Los *Pod Security Standards* ([documentación](https://kubernetes.io/docs/concepts/security/pod-security-standards/)) definen tres niveles; `restricted` es el más estricto y suma seis controles a los de `baseline`:

| Control de `restricted` | Qué exige (campo y valor permitido) | Dónde lo cumple el proyecto |
|---|---|---|
| Tipos de volumen | cada volumen es de un tipo permitido: `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected` o `secret` | `emptyDir` y `secret` en el `revisor`; `persistentVolumeClaim` y `secret` en el `CronJob` |
| Escalada de privilegios | `allowPrivilegeEscalation: false` en cada contenedor | el `securityContext` de cada contenedor, en los dos Deployments (`revisor` y `prueba`) y el `CronJob` |
| Ejecutar como no-`root` | `runAsNonRoot: true` (en el Pod o en cada contenedor) | el `securityContext` del Pod |
| Usuario no-`root` | `runAsUser` distinto de 0, o sin definir | 65532 en el `revisor` y `prueba`; 100 en el `CronJob` |
| *Seccomp* | `seccompProfile.type` explícito: `RuntimeDefault` o `Localhost`; ni `Unconfined` ni ausente | `RuntimeDefault`, en el `securityContext` del Pod |
| Capacidades | `capabilities.drop` incluye `ALL`; solo se puede volver a agregar `NET_BIND_SERVICE` | `drop: ["ALL"]` en cada contenedor |

(Los controles de `baseline` que `restricted` hereda —sin contenedores privilegiados, sin red del anfitrión, sin `hostPath`, sin puertos del anfitrión, entre otros— se cumplen porque ningún manifiesto del proyecto pide nada de eso.)

Y ahora, lo que **`restricted` no pide** y el proyecto hace de todas formas, para que no lo confundas con la norma:

- `readOnlyRootFilesystem: true`. Ninguno de los tres niveles lo exige. El proyecto lo pone porque un sistema de archivos que no se puede escribir limita lo que un atacante haría dentro del contenedor, y por eso el `revisor` guarda su reporte en un volumen y no en `/`.
- `requests` y `limits` (Lección 5), `automountServiceAccountToken: false` (Lección 7), el `Secret` marcado inmutable y montado como archivo (Lección 4), la red cerrada (Lección 7). Son decisiones del proyecto, no controles de `restricted`.

Distinguir las dos listas importa: «cumple `restricted`» es un hecho que el clúster te puede confirmar con una consulta (la siguiente sección), y «sigue las prácticas del curso» es un juicio que haces tú.

#### 10.7.2 Cómo lo aplica el clúster

El nivel no se enseña a cada Pod: se le dice al **espacio de nombres**, con etiquetas. Esto es lo que lleva `base/namespace.yaml`:

```yaml
# namespace.yaml — Lección 7: un espacio propio, en el nivel «restricted» de
# Pod Security Admission, con la versión de la política fijada.
apiVersion: v1
kind: Namespace
metadata:
  name: revisor
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.37
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.37
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.37
```

La [documentación de *Pod Security Admission*](https://kubernetes.io/docs/concepts/security/pod-security-admission/) define tres **modos**, cada uno con su etiqueta: `enforce` (la violación **rechaza** el Pod), `audit` (la violación deja una anotación en el registro de auditoría, pero se permite) y `warn` (la violación produce una advertencia para quien aplicó, pero se permite). Cada modo tiene además una etiqueta `…-version` que fija la política a la que venía con una versión de Kubernetes, aquí la v1.37, para que una actualización del clúster no cambie las reglas por debajo sin que lo decidas.

Un detalle que explica lo que vas a ver en 10.7.4: según la misma documentación, los modos `audit` y `warn` se aplican también a los objetos que *crean* Pods (Deployments, Jobs, CronJobs), «para ayudar a detectar violaciones temprano», pero `enforce` **no** se aplica a esos objetos, solo a los Pods que resultan. Dicho con un ejemplo: un Deployment que no cumple se *acepta* (con advertencia), y los Pods que intenta crear se *rechazan*. El Deployment queda existiendo con cero réplicas, y por eso hay que leer las advertencias de `apply` y no fiarse de que «aplicó bien».

#### 10.7.3 La revisión en el clúster

Primero, la consulta que la [documentación](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) recomienda antes de cambiar un nivel: `kubectl label --dry-run=server --overwrite`. La documentación explica que cuando una etiqueta `enforce` (o su versión) se **agrega o se cambia**, el controlador de admisión prueba cada Pod del espacio contra la política nueva y devuelve las violaciones como advertencias, y que con `--dry-run=server` esa prueba corre sin aplicar nada. Todo depende de «agrega o cambia». Lo primero que uno escribe sobre `revisor`, que ya tiene `enforce=restricted`, **no cambia nada**, y por eso (se midió, más abajo) no revisa ningún Pod:

```text
$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)

$ kubectl get namespace revisor --show-labels
NAME      STATUS   AGE   LABELS
revisor   Active   83s   kubernetes.io/metadata.name=revisor,pod-security.kubernetes.io/audit-version=v1.37,pod-security.kubernetes.io/audit=restricted,pod-security.kubernetes.io/enforce-version=v1.37,pod-security.kubernetes.io/enforce=restricted,pod-security.kubernetes.io/warn-version=v1.37,pod-security.kubernetes.io/warn=restricted
```

`namespace/revisor not labeled (server dry run)` dice una sola cosa: la etiqueta ya era esa y no hubo nada que cambiar. **No revisó ningún Pod**, así que no es evidencia de que el proyecto cumple; con cualquier Pod dentro habría dicho lo mismo. En la segunda salida están las seis etiquetas de los tres modos, cada uno con su versión `v1.37`, más la que Kubernetes pone solo (`kubernetes.io/metadata.name`).

**La consulta que sí revisa lo que ya existe.** Si el nivel y la versión se repiten, el servidor no evalúa; si **cambia** la política, sí. Entonces, para auditar un espacio que ya está en `restricted:v1.37`, se le pide una política distinta, sin aplicarla: la misma etiqueta de versión con otro valor, por ejemplo `enforce-version=v1.36`. El servidor prueba cada Pod contra `restricted` de esa versión (no de la v1.37: es una vecina, no la misma) y reporta. Como una ausencia de advertencias no vale sin un control, `psa-comprobacion.sh` lo prueba primero en un espacio de prueba, `psa-control`, con dos Pods: `viola` (no dice nada de seguridad) y `cumple` (cumple los seis controles de `restricted`). Se le pone `restricted:v1.37` de verdad y se repiten las dos consultas. Esto se corrió en un clúster `curso-k8s-l10` de tres nodos con el proyecto aplicado (el espacio `revisor`) pero sin la plataforma, que esta prueba no necesita:

```text
## El control: un espacio con un Pod que viola y otro que cumple

$ kubectl apply -f psa-control.yaml
namespace/psa-control created
pod/viola created
pod/cumple created

$ kubectl get pods -n psa-control
NAME     READY   STATUS    RESTARTS   AGE
cumple   1/1     Running   0          1s
viola    1/1     Running   0          1s

## Se le pone restricted de verdad: el servidor sí avisa, porque el nivel CAMBIA

$ kubectl label --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
Warning: existing pods in namespace "psa-control" violate the new PodSecurity enforce level "restricted:v1.37"
Warning: viola: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/psa-control labeled

## La consulta de antes: repetir el nivel que el espacio ya tiene

$ kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
namespace/psa-control not labeled (server dry run)

## La consulta que sí revisa: pedir otra versión de la política

$ kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce-version=v1.36
Warning: existing pods in namespace "psa-control" violate the new PodSecurity enforce level "restricted:v1.36"
Warning: viola: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/psa-control labeled (server dry run)

## Lo mismo sobre el espacio del proyecto

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
namespace/revisor not labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce-version=v1.36
namespace/revisor labeled (server dry run)

$ kubectl get pods -n revisor --no-headers | wc -l
       4
```

Léelo de arriba abajo. Al poner `restricted` de verdad, el servidor avisa y nombra a **`viola`** (con los cuatro controles que incumple) y no a `cumple`. Repetir el mismo nivel y la misma versión sobre `psa-control` dice `not labeled`, **con un Pod que viola dentro**: esa es la consulta que no revisa. Pedir `v1.36` sí avisa, y solo de `viola`: la consulta revisa, y distingue. Con el control a la vista, el resultado sobre `revisor` vale: repetir el nivel dice `not labeled` (sin información) y pedir `v1.36` dice `labeled (server dry run)` **sin una sola advertencia** sobre los 4 Pods del espacio (los dos del `revisor`, el de `prueba` y el que dejó el `CronJob`). Eso sí es «el servidor revisó los Pods de `revisor` y ninguno incumple `restricted`».

Una ausencia de advertencias solo vale si sabes que la herramienta sí las daría; esa comprobación (el control de arriba, y el Deployment `malo` de 10.7.5) ya está hecha. Además, la prueba campo por campo: la tabla de 10.7.1, pero leída de los Pods vivos del espacio (el jsonpath pide, por Pod, los campos que `restricted` examina):

```text
$ kubectl get pods -n revisor -o jsonpath='{range .items[*]}{.metadata.name}{" noroot="}{.spec.securityContext.runAsNonRoot}{" seccomp="}{.spec.securityContext.seccompProfile.type}{" priv-esc="}{.spec.containers[0].securityContext.allowPrivilegeEscalation}{" drop="}{.spec.containers[0].securityContext.capabilities.drop}{" ro="}{.spec.containers[0].securityContext.readOnlyRootFilesystem}{" automount="}{.spec.automountServiceAccountToken}{"\n"}{end}'
prueba-6899c74865-rzh88 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-6m6s6 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-dq4pp noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
```

Tres Pods, tres renglones idénticos: los dos del `revisor` y el de `prueba` (si el `CronJob` ya disparó, aparecería un cuarto, con los mismos valores). En cada uno: `noroot=true` (el Pod corre como no-`root`), `seccomp=RuntimeDefault`, `priv-esc=false`, `drop=["ALL"]`, y además `ro=true` y `automount=false`, que son del curso y no de `restricted`. Sólo se pidió el primer contenedor (`containers[0]`), y cada uno de estos Pods tiene uno solo. Esta consulta no sustituye al `dry-run` (que revisa todos los controles, no sólo los que escribí en el `jsonpath`); lo complementa: te deja *ver* los valores.

#### 10.7.4 Parte de la plataforma no cumple `restricted`, y está bien (con una condición)

El espacio `revisor` es el único con las etiquetas. ¿Qué diría el servidor si se las pusieras a los espacios de la plataforma? Se pregunta con la misma consulta, sin cambiar nada (`cut` recorta cada línea para que quepa). Aquí la consulta sí revisa los Pods, porque estos espacios no tienen la etiqueta y ponerla es un cambio. Otra diferencia con la consulta anterior: estos espacios no tienen una etiqueta de versión, así que el servidor compara contra la versión más reciente de la política (`restricted:latest`) y lo dice en la primera advertencia:

```text
$ kubectl label --dry-run=server --overwrite namespace envoy-gateway-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
namespace/envoy-gateway-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace metallb-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
Warning: existing pods in namespace "metallb-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: controller-76f4cf76b7-kclm8: unrestricted capabilities, seccompProfile
Warning: speaker-cbfnt (and 2 other pods): host namespaces, hostPort, probe or lifecycle host, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/metallb-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: coredns-559f6c778d-9fhdt (and 1 other pod): runAsNonRoot != true, seccompProfile
Warning: etcd-curso-k8s-l10-control-plane (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
Warning: kindnet-6qh25 (and 2 other pods): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: kube-proxy-6rwpd (and 2 other pods): host namespaces, privileged, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
namespace/kube-system labeled (server dry run)
```

Tres espacios, tres respuestas distintas:

- **`envoy-gateway-system`: sin advertencias.** Dice «labeled (server dry run)» y nada más. Los Pods de Envoy Gateway (el controlador y los Envoy que atienden la puerta) cumplen `restricted`. Es un dato que conviene saber y que no es obvio: no toda la plataforma pide privilegios.
- **`metallb-system`: sí.** El `controller` viola dos controles: «unrestricted capabilities» (conserva capacidades de Linux que `restricted` obliga a quitar) y «seccompProfile» (no declara perfil). Los tres `speaker` violan más: «host namespaces» y «hostPort» (comparten la red del nodo), «probe or lifecycle host», «runAsNonRoot != true» y las mismas capacidades y perfil. El `speaker` es el que responde a las preguntas ARP de la red (la capa 2 de 10.10, punto 5) y, para eso, tiene que ver la red del nodo y no una red propia: la advertencia «host namespaces» es el nombre técnico de esa necesidad.
- **`kube-system`: sí, y mucho.** Los dos `coredns` violan `runAsNonRoot` y el perfil `seccomp`. Los cuatro Pods del plano de control (`etcd` y sus tres compañeros) comparten la red del anfitrión y montan rutas del nodo (los «restricted volume types»). `kindnet` y `kube-proxy` comparten la red del anfitrión y conservan capacidades, y `kube-proxy` además corre como `privileged`.

(El «(and 2 other pods)» es del servidor: agrupa los Pods que violan lo mismo para no repetir el renglón.)

Eso no es un defecto del curso: es lo que pasa cuando una pieza de infraestructura necesita privilegios para hacer su trabajo (hablar con la red de los nodos, anunciar direcciones, montar rutas del nodo). El punto es doble. Primero, **los privilegios existen y están en alguna parte**: la plataforma los concentra en sus propios espacios, y el proyecto, que es lo que cambia todos los días, vive sin ellos. Segundo, esos espacios tienen una **condición**: nadie más debe poder crear Pods ahí, porque quien pueda crear un Pod en `metallb-system` o `kube-system` tiene, de hecho, los privilegios de ese espacio. En un clúster real, eso se resuelve con RBAC (quién puede crear qué donde) y con un nivel `baseline` o `privileged` *declarado* para cada espacio de plataforma —una decisión escrita, con dueño—, no con un espacio sin etiqueta. Aquí no se etiquetan, y 10.10 lo anota.

#### 10.7.5 El control positivo: un Deployment que sí viola `restricted`

Para saber que «ni una advertencia» significa algo, se prueba con un Deployment que **sí** debe producirlas. `fig10_02.deployment-malo.yaml` es un **programa que falla a propósito**: un Deployment que no dice nada de seguridad.

```yaml
# fig10_02.deployment-malo.yaml — FALLA A PROPÓSITO: un Deployment que NO cumple el
# nivel «restricted». No dice nada de seguridad: ni usuario, ni capacidades, ni
# perfil seccomp. En el espacio «revisor» el clúster avisa al aplicarlo y rechaza
# sus Pods. Se aplica con:  kubectl apply -n revisor -f fig10_02.deployment-malo.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: malo
  labels:
    app: malo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: malo
  template:
    metadata:
      labels:
        app: malo
    spec:
      containers:
      - name: malo
        image: curso-docker-prueba:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 9000
```

```text
$ kubectl apply -n revisor -f fig10_02.deployment-malo.yaml
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "malo" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/malo created

$ kubectl get deployment malo -n revisor
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
malo   0/1     0            0           8s

$ kubectl get events -n revisor --field-selector reason=FailedCreate -o custom-columns=RAZON:.reason,MENSAJE:.message | cut -c1-400 | head -3
RAZON          MENSAJE
FailedCreate   Error creating: pods "malo-89fb7566-9zgxl" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonR
FailedCreate   Error creating: pods "malo-89fb7566-wps2l" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonR
```

Tres cosas en este orden. **Al aplicar**, una `Warning` con cuatro controles violados: `allowPrivilegeEscalation != false`, `unrestricted capabilities`, `runAsNonRoot != true` y `seccompProfile`, cada uno con el campo exacto que falta (`container "malo" must set securityContext.allowPrivilegeEscalation=false`…). Y debajo, `deployment.apps/malo created`: el Deployment **sí se creó**. Segundo, el Deployment está en `READY 0/1`: no tiene ningún Pod. Tercero, los eventos del ReplicaSet: `FailedCreate`, «Error creating: pods "malo-…" is forbidden: violates PodSecurity "restricted:v1.37"», con la misma lista. Ahí actuó el modo `enforce`, y se ve que lo hizo al crear los Pods, no el Deployment.

Esto es lo que 10.7.2 anunciaba: el Deployment *se acepta* (con advertencias, por el modo `warn`) y los Pods *se rechazan* (por el modo `enforce`); el ReplicaSet registra cada rechazo como un evento `FailedCreate`. Y es la razón de leer la salida de `apply`. Se borra:

```text
$ kubectl delete -n revisor -f fig10_02.deployment-malo.yaml
deployment.apps "malo" deleted from revisor namespace
```

Con esto, la afirmación del proyecto queda en pie con un control: el proyecto no produce advertencias (conteo 0 en 10.5.3), y un Deployment que viola la política **sí** las produce. El Ejercicio 2 te pide arreglar este.

### 10.8 Probar las metas

El README del curso termina con siete metas: no «leíste las lecciones» sino «tu proyecto cumple esto». Esta sección comprueba en el clúster las que se pueden medir. Antes, el mapa, para que sepas dónde está cada una:

| Meta | Qué dice | Dónde se comprueba |
|---|---|---|
| 1 | desde un clúster recién creado, el proyecto queda funcionando en tres pasos, y se reconstruye tras borrarlo | 10.5 (a mano) y 10.6 (con el guion, dos vueltas) |
| 2 | el espacio de nombres está en `restricted` y no hay advertencias al aplicar | 10.5.3 y 10.7 |
| 3 | un nodo de trabajo se detiene y el servicio sigue respondiendo, con una ventana medida | 10.8.3 |
| 4 | cambiar la lista de servicios hace el *rollout* solo | 10.8.1 |
| 5 | con carga, el escalado sube y baja réplicas | medido en la Lección 9; 10.8.4 comprueba que sigue conectado |
| 6 | un Pod ajeno no habla con el `revisor`, y la cuenta del `revisor` no puede nada | 10.8.2 |
| 7 | sabes decir, por escrito, cinco cosas por las que esto no es producción | 10.10 y el Ejercicio 4 |

#### 10.8.1 Meta 4: cambiar la lista cambia las réplicas, sin tocar la imagen

Es la Lección 4 vista desde el final: la configuración vive fuera de la imagen. Primero, el estado antes del cambio: el ReplicaSet que tiene las réplicas y el `ConfigMap` generado con su *hash*.

```text
$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-654b5d75dc   2         2         2       92s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      92s
revisor-config-t6cm6872fk   1      92s
```

Se cambia el tiempo límite del servicio de prueba de `2s` a `1s` en la base. `sed -i.bak` edita el archivo en su lugar y deja una copia con la extensión `.bak` (la forma que funciona igual en Linux y en macOS); `diff` compara la copia con el archivo nuevo para que veas exactamente qué cambió:

```text
$ sed -i.bak 's#http://prueba:9000/ 2s#http://prueba:9000/ 1s#' base/kustomization.yaml; diff base/kustomization.yaml.bak base/kustomization.yaml
29c29
<   - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s
---
>   - REVISOR_SERVICIOS=prueba http://prueba:9000/ 1s
[código de salida: 1]
```

```bash
ctx && kubectl apply --server-side -k overlays/kind
```

Aquí el comando filtra las dos líneas que importan:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-cmb662hmbh serverside-applied
deployment.apps/revisor serverside-applied
```

Se restaura el archivo (el `.bak` se devuelve a su nombre) y se espera a que termine el *rollout*:

```text
$ mv base/kustomization.yaml.bak base/kustomization.yaml && grep REVISOR_SERVICIOS base/kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-548956488d   2         2         2       5s
revisor-654b5d75dc   0         0         0       97s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      97s
revisor-config-cmb662hmbh   1      5s
revisor-config-t6cm6872fk   1      97s
```

Lo que cambió: el `diff` muestra una sola línea, `2s` por `1s`. El `apply` aplicó dos objetos: un `ConfigMap` **nuevo**, `revisor-config-cmb662hmbh` (otro *hash*, porque el contenido es otro), y el Deployment, que el generador reescribió para apuntar a él. El *rollout* creó un ReplicaSet nuevo con las dos réplicas y dejó el viejo en `0 0 0`. Y lo que no cambió: la imagen. `curso-docker-revisor:1.6.0` no se reconstruyó, no se volvió a cargar y no se tocó. El `ConfigMap` viejo sigue en el clúster, sin que nadie lo use: es el precio de la Lección 4. `kube-root-ca.crt` no es tuyo: Kubernetes lo crea en cada espacio de nombres.

Y como el archivo vuelve a decir `2s`, el clúster tiene que volver también. **El archivo es la verdad**: si el clúster y los archivos difieren, se corrige el clúster aplicando de nuevo, no se anota «ya sé que está distinto»:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-t6cm6872fk serverside-applied
deployment.apps/revisor serverside-applied

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-548956488d   0         0         0       11s
revisor-654b5d75dc   2         2         2       103s
```

Al volver al archivo original, el `ConfigMap` que se aplica es otra vez `revisor-config-t6cm6872fk`, el de antes. Como la plantilla del Pod vuelve a ser idéntica a la del primer ReplicaSet, el Deployment **lo reutiliza**: sube el viejo de 0 a 2 y baja el que acababa de crear, en lugar de armar uno tercero. Quedan dos ReplicaSets, uno activo y uno en `0 0 0`; esos ReplicaSets vacíos son lo que `rollout undo` usa para regresar (Lección 9).

#### 10.8.2 Meta 6: la red y los permisos

Dos pruebas pequeñas, en el espacio `revisor`: un Pod **con** la etiqueta `acceso-revisor: permitido` (`depurar`) y otro **sin** ella (`intruso`). Los dos son Pods de `curl` que ya cumplen `restricted`, así que el clúster los acepta:

```bash
ctx && kubectl apply -n revisor -f depurar.yaml -f intruso.yaml
ctx && kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso --timeout=180s
```

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

El primero es el control positivo: sin él, el segundo no probaría nada, porque un `curl` que falla puede fallar por mil razones. El `depurar` llega (la red lo deja), el `intruso` no. La lectura del código es la clave. `curl` sale con **28** (*operation timed out*): pasaron los 3 segundos del `-m 3` sin respuesta. Si la red rechazara la conexión, `curl` saldría con 7 («no pude conectar»), como en la Lección 3. Una `NetworkPolicy` que no deja pasar un paquete **lo descarta sin contestar**, y el cliente se queda esperando: por eso el 28 es la huella de una red cerrada y no de un servicio caído.

Y los permisos de las cuentas, con `kubectl auth can-i`, que le pregunta al clúster si una identidad podría hacer algo, sin hacerlo:

```text
$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador
yes

$ kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]
```

Cuatro respuestas, y una tabla las resume: la cuenta `revisor` **no** puede leer Pods ni Secrets (`no`, `no`); la cuenta `observador` **sí** puede leer Pods (`yes`) y **no** puede borrarlos (`no`). El código de salida de `can-i` es 1 cuando la respuesta es `no`, y por eso el guion anota `[código de salida: 1]` sin que haya ningún fallo. La cuenta del `revisor` ni siquiera tiene credenciales montadas (`automountServiceAccountToken: false`), así que la respuesta es doble: no puede, y aunque pudiera, el Pod no tiene con qué llamar a la API.

#### 10.8.3 Meta 3: se detiene un nodo y el servicio sigue respondiendo

Esta es la prueba más cercana a lo que pasa en un clúster real, y la que más enseña. Un nodo de trabajo es un contenedor de Docker; detenerlo con `docker stop` se parece a que la máquina se apague de golpe. Se quiere saber tres cosas: ¿el servicio sigue respondiendo?, ¿falla algo mientras tanto?, ¿cuánto dura?

**Antes de predecir, los números del clúster.** La [documentación del estado de los nodos](https://kubernetes.io/docs/reference/node/node-status/) describe el mecanismo: cada `kubelet` renueva el objeto `Lease` de su nodo **cada 10 segundos** (ese es el latido), el controlador de nodos revisa los latidos **cada 5 segundos** (`node-monitor-period`), y la condición `Ready` pasa a `Unknown` si en `node-monitor-grace-period` no ha sabido nada del nodo: **50 segundos por omisión** (también como valor por omisión en la [referencia de `kube-controller-manager`](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)). Los 50 segundos se cuentan desde el **último latido que el controlador recibió**, no desde el `docker stop`: ese latido pudo llegar hasta 10 segundos antes de apagar el nodo, y el controlador solo lo nota en su siguiente revisión (hasta 5 segundos después). Hecha la suma, el clúster se entera entre unos 40 y unos 55 segundos después del `docker stop`; como el ciclo de medición arranca unos segundos más tarde, desde su reloj la ventana cae unos segundos antes. Mientras no se cumple el plazo, el clúster *no sabe* que el nodo se fue. Y la [documentación de *taints* y tolerancias](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) dice que, cuando el nodo ya es `Unknown`, los Pods no se desalojan de inmediato: por omisión toleran la mancha de «nodo inalcanzable» durante **300 segundos** (`tolerationSeconds`), y solo entonces se reponen en otro nodo.

La predicción, entonces: con dos réplicas (una por nodo de trabajo), al detener un nodo, **en promedio la mitad de las peticiones** debería fallar mientras dura esa ventana (decenas de segundos). La [documentación de Services](https://kubernetes.io/docs/reference/networking/virtual-ips/) dice que, en los modos `iptables` y `nftables`, `kube-proxy` instala reglas que por omisión eligen el Pod destino **al azar**: no es un turno estricto, así que con unas 25 peticiones la proporción real puede alejarse de la mitad. Mientras tanto, una dirección ya no contesta y el clúster todavía no lo sabe. Pasada la ventana, la réplica muerta sale de la lista de direcciones y todo debería pasar.

El experimento. Un detalle antes: la prueba del *rollout* de 10.8.1 acaba de reemplazar los Pods, y los viejos tardan unos segundos en desaparecer. Para no medir con Pods que se están yendo, se espera a que queden solo los dos vigentes (otro ciclo con tope, como el del escalado):

```bash
for _ in $(seq 1 60); do
  [ "$(kubectl get pods -n revisor -l app=revisor --no-headers | wc -l | tr -d ' ')" = 2 ] && break
  sleep 2
done
```

Y ahora sí, dónde están las réplicas, para no detener el nodo del Pod que hace de cliente:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          15s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          17s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

Se elige como víctima un nodo de trabajo que no sea el de `depurar` (el cliente que va a medir desde dentro del clúster), y se detiene su contenedor. La víctima sale de una lista de nodos de trabajo menos el del cliente; la lección usa el `case` que ya conoces para no detener nada que no sea de este clúster:

```bash
NODO_DEPURAR="$(kubectl get pod -n revisor depurar -o jsonpath='{.spec.nodeName}')"
VICTIMA="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name | sed 's#node/##' | grep -vx "$NODO_DEPURAR" | head -1)"
case "$VICTIMA" in curso-k8s-l10-*) ;; *) echo "ALTO: «$VICTIMA» no es un nodo de este clúster"; false ;; esac
docker stop "$VICTIMA"
```

```text
$ docker stop curso-k8s-l10-worker2
curso-k8s-l10-worker2
```

Y el cliente: un ciclo dentro de `depurar` que hace una petición cada 2 segundos durante 90, con un límite de 2 segundos cada una, y solo imprime cuando el resultado **cambia** (un renglón por cambio, no uno por petición):

```bash
ctx && kubectl exec -n revisor depurar -- sh -c 'inicio=$(date +%s); ok=0; mal=0; ant=""; while [ $(( $(date +%s) - inicio )) -lt 90 ]; do t=$(( $(date +%s) - inicio )); if curl -s -m 2 -o /dev/null http://revisor/salud; then r=ok; ok=$((ok+1)); else r=FALLA; mal=$((mal+1)); fi; [ "$r" != "$ant" ] && echo "[+${t}s] $r"; ant=$r; sleep 2; done; echo "bien=$ok mal=$mal"'
```

(El ciclo está escrito entre comillas simples para que el `$(…)` lo interprete el `sh` de *dentro* del Pod y no el tuyo. `date +%s` da los segundos desde 1970; la resta con `inicio` es el tiempo transcurrido; `curl -m 2` se rinde a los 2 segundos.)

```text
[+0s] FALLA
[+4s] ok
[+6s] FALLA
[+22s] ok
[+31s] FALLA
[+51s] ok
bien=24 mal=10
```

Léelo como una línea de tiempo (los renglones son *cambios*, no peticiones). Arranca fallando (`[+0s] FALLA`), vuelve a responder a los 4 segundos, falla de nuevo a los 6 y no responde hasta el 22; responde hasta el 31, falla otra vez hasta el 51, y **desde el segundo 51 todo responde** hasta el final de los 90. Al terminar: `bien=24 mal=10`, 34 peticiones, y las 10 fallas cayeron todas antes del segundo 51. Eso coincide con el mecanismo de arriba: el clúster tardó lo que tardan sus latidos y su plazo en darse cuenta. Con lo que no coincide a la perfección es con el «alternado»: hay tramos de varios segundos seguidos fallando, no una falla y un acierto por turno. Es lo que dice la documentación de Services: el destino se elige **al azar** en cada conexión, así que de vez en cuando salen varias seguidas hacia la dirección muerta. (Cada petición fallida cuesta además 2 segundos de límite, por eso en la ventana caben menos peticiones que durante el resto de la prueba.) Tampoco conviene tomar el 51 como una constante: en las otras tres corridas de preparación de la lección (guardadas en `programas/10-proyecto-final/corridas-preparacion/`), el servicio volvió a responder sin fallar a los 36, 50 y 34 segundos. Las cuatro ventanas, de 34 a 51 segundos, son lo que predice el mecanismo: dependen de qué tan viejo era el último latido cuando se detuvo el nodo (de 0 a 10 segundos), de la revisión del controlador (cada 5) y de los segundos que pasan entre el `docker stop` y el primer intento del ciclo. La [Lección 9](09-escalar-y-actualizar.md) (9.12.2) midió el mismo mecanismo desde otro ángulo: el nodo pasó a `NotReady` a los 57 segundos de apagado. Lo que se mantiene de una corrida a otra es el orden de magnitud: decenas de segundos, no minutos.

Y el estado del clúster en ese instante, **antes** de levantar el nodo:

```text
$ kubectl get nodes
NAME                          STATUS     ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready      control-plane   6m46s   v1.37.0
curso-k8s-l10-worker          Ready      <none>          6m35s   v1.37.0
curso-k8s-l10-worker2         NotReady   <none>          6m34s   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          106s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          108s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>

$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]}{" listo="}{.conditions.ready}{"\n"}{end}'
10.244.1.7 listo=true
10.244.2.7 listo=false
```

Tres datos que parecen contradecirse y no lo hacen. El nodo `curso-k8s-l10-worker2` está `NotReady`: el clúster ya lo dio por perdido. Pero el Pod que vive en él sigue apareciendo como `1/1 Running`: el clúster lo seguirá listando hasta agotar los 300 segundos de tolerancia, y sólo entonces lo repondrá en otro nodo. Y el `EndpointSlice` del Service ya marca la dirección de ese Pod (`10.244.2.7`) con `listo=false`: **dejó de recibir tráfico** aunque la lista de Pods todavía lo muestre. La lección práctica es que `READY 1/1` en `kubectl get pods` y «recibe tráfico» no son lo mismo; para saber si un Pod recibe peticiones se mira el `EndpointSlice` (Lección 3).

Se levanta el nodo y se espera a que vuelva:

```text
$ docker start curso-k8s-l10-worker2
curso-k8s-l10-worker2

$ kubectl wait --for=condition=Ready node/curso-k8s-l10-worker2 --timeout=180s
node/curso-k8s-l10-worker2 condition met

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready    control-plane   6m48s   v1.37.0
curso-k8s-l10-worker          Ready    <none>          6m37s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          6m36s   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          108s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          110s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

El cambio del contador de reinicios tarda en verse. Mira el contador un momento después de que el nodo vuelve a `Ready` (arriba, `RESTARTS`), espera a que registre el reinicio con otro ciclo con tope y vuelve a mirar:

```bash
for _ in $(seq 1 36); do
  [ "$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | grep -vc '^0$')" -ge 1 ] && break
  sleep 5
done
```

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS     AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   1 (7s ago)   113s   10.244.2.5   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0            115s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>

$ kubectl get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name}{" reinicios="}{.status.containerStatuses[0].restartCount}{" último fin: "}{.status.containerStatuses[0].lastState.terminated.reason}{" código "}{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}{end}'
revisor-654b5d75dc-qcqfz reinicios=1 último fin: Unknown código 255
revisor-654b5d75dc-xmvc5 reinicios=0 último fin:  código 
```

El nodo vuelve a `Ready`, y la primera lista de Pods engaña: sigue diciendo `RESTARTS 0` y la IP de antes (`10.244.2.7`). Unos segundos después, el contador sí cambia: el Pod `…-qcqfz` dice `1 (7s ago)` y, además, **tiene otra IP**: `10.244.2.5`. Es el mismo Pod, con el mismo nombre, pero su contenedor se reinició y su dirección cambió. La consulta de `lastState` lo explica: el último fin del contenedor fue de razón `Unknown` y código `255`, es decir, no lo mató ninguna sonda ni un `OOMKilled`; desapareció con su nodo, que se apagó entero, y nadie pudo registrar un código de salida normal. La otra réplica, la del nodo que nunca se detuvo, quedó en cero reinicios. Dos consecuencias para ti: un contador de reinicios distinto de cero **no** siempre quiere decir que algo falló en tu programa (aquí fue el nodo), y una IP de Pod no se guarda para después, que es la Lección 3 otra vez.

**Qué reduce esa ventana y qué no.** Con lo que mediste, la respuesta honesta:

- **Más réplicas, repartidas entre más nodos.** Si en lugar de dos hay seis repartidas en tres nodos, detener uno afecta a una parte menor de las peticiones. Eso es lo que el escalado y el reparto de la Lección 9 ya hacen: no acortan el tiempo, reducen la porción.
- **Reintentos en el cliente.** Una petición que falla y se repite cae, con buena probabilidad, en la otra réplica. El cliente de esta prueba no reintenta a propósito, para que veas el efecto crudo; uno real sí debería.
- **Un `node-monitor-grace-period` más corto**, en el plano de control, que acorta la ventana a cambio de más falsas alarmas (un nodo con un tropiezo de red de unos segundos se daría por perdido). En un clúster administrado, se pide al proveedor; en `kind`, no lo cambias en esta lección.

Y lo que **no** la acorta, aunque lo parezca:

- **Las sondas.** Las corre el `kubelet` del propio nodo, que es justo el que dejó de existir. Una sonda no puede reportar la falta del programa que la ejecuta.
- **`tolerationSeconds`.** Decide en cuánto tiempo se *reponen* los Pods en otro nodo, no cuándo dejan de recibir tráfico. Acortarlo repone antes, pero el tráfico seguiría yéndose a la dirección muerta hasta que el nodo se dé por perdido.

Una frase que vale como resumen: el clúster tolera que un nodo se caiga, **no que se caiga sin que nadie lo note durante decenas de segundos**. Esa es la diferencia entre «sobrevive» y «sin cortes», y por eso la meta del curso dice «con una ventana medida».

#### 10.8.4 Meta 5: el escalado sigue conectado

Medir cuánto tarda el escalado en subir y en bajar con carga ocupa 15 minutos y una lección entera: es la Lección 9, y no se repite aquí. Lo que sí se comprueba es que, en el clúster levantado desde cero, **sigue conectado a las métricas**:

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          3m32s
```

En esta corrida, justo después de reiniciar el nodo, el escalado dijo `cpu: <unknown>/50%`: perdió la lectura de las métricas. No se investigó en qué nodo corre `metrics-server` ni por qué se interrumpió; lo medido es que un nodo reiniciado dejó al escalado sin datos durante un rato. (En otras corridas de preparación de la lección no pasó: ya traía el porcentaje.) Es un ejemplo de por qué el `<unknown>` no se interpreta sin mirar qué acaba de pasar en el clúster.

Si en tu clúster dice `<unknown>`, no te alarmes todavía: es la causa de la Lección 9 y se resuelve esperando, pero con tope. El mismo ciclo de 10.5.3, que revisa cada 5 segundos hasta tres minutos:

```bash
for _ in $(seq 1 36); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: 3%/50%   2         6         2          4m33s
```

El ciclo esperó y el escalado se recuperó solo: `cpu: 3%/50%`, `MINPODS 2`, `MAXPODS 6` y dos réplicas. Entre los dos `get` pasó algo más de un minuto (la columna `AGE` va de 3m32s a 4m33s). Con esto, la meta 5 queda comprobada en lo que esta lección puede comprobar: el escalado está conectado a las métricas y sus límites son los de la base. Subir y bajar réplicas con carga es la Lección 9.

Y si el ciclo se rinde y sigue diciendo `<unknown>`, la otra causa que viste en la Lección 9 es `metrics-server` sin la bandera `--kubelet-insecure-tls` (que `kind` necesita).

### 10.9 Helm, en una mención

Hay una herramienta que verás en casi cualquier proyecto de Kubernetes y que este curso no usa: **Helm**. La [documentación de Helm](https://helm.sh/docs/intro/using_helm/) lo llama un gestor de paquetes para Kubernetes. Cuatro palabras que conviene reconocer: un **chart** es un paquete (una carpeta de plantillas de manifiestos más sus valores por omisión); los **values** son los valores que cambias para tu instalación; una **release** es una instalación concreta de un chart en un clúster; y un **repositorio** (o un registro de imágenes OCI) es donde se publican.

El ejemplo está en la guía de Envoy Gateway que ya conoces. Además de instalarlo con el `install.yaml` que usa el curso, [esa guía](https://gateway.envoyproxy.io/docs/install/install-helm/) lo instala con Helm así (el comando es el de la guía para la versión v1.9.2; **no se corrió en esta lección**):

```text
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.9.2 -n envoy-gateway-system --create-namespace
```

`eg` es el nombre de la *release*, `oci://docker.io/envoyproxy/gateway-helm` es el chart y `--version` fija su versión, con `--create-namespace` para crear el espacio donde se instala.

¿Por qué el curso usa Kustomize y no Helm? Porque compara dos ideas distintas, y para aprender conviene ver primero la más simple:

| | Kustomize | Helm |
|---|---|---|
| Idea | parte de YAML completo y **lo cambia** con capas | parte de **plantillas** con huecos y los **llena** con valores |
| Lo que lees | YAML normal; lo que ves es lo que se aplica | plantillas con lógica; para ver el resultado, `helm template` |
| Cambios entre entornos | overlays y parches | archivos de valores (`values`) |
| Qué más hace | nada: arma y entrega a `kubectl` | lleva el historial de *releases*, actualiza y puede regresar a una versión anterior |
| Viene con `kubectl` | sí (`kubectl kustomize`, `apply -k`) | no: es un programa aparte |

Una regla práctica muy usada, que aquí es una opinión y no una norma: **Kustomize para lo tuyo, Helm para lo ajeno.** Lo tuyo es YAML que escribiste y quieres leer; lo ajeno (MetalLB, Envoy Gateway, un monitoreo) suele publicarse como chart con docenas de opciones que alguien más ya pensó. Muchos equipos usan los dos: instalan la plataforma con Helm y su proyecto con Kustomize.

Y el problema de esta lección existe también ahí. Las [prácticas recomendadas de Helm sobre CRD](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) dicen que los CRD de un chart se instalan primero (viven en una carpeta especial, `crds/`), que **Helm no los actualiza ni los borra** por el peligro de perder datos, y que si un chart necesita usar los tipos que él mismo define, lo más cómodo es separarlos en dos charts que se instalan por separado. Es el mismo orden —tipos, controlador, proyecto— con otro nombre.

### 10.10 Qué cambia en un clúster real

#### 10.10.1 Lo que construiste y lo que le falta

Hay una tentación al terminar un curso: creer que lo que funciona en tu máquina está «casi» listo para correr de verdad. Esta sección existe para desarmarla con honestidad, sin dramatismo. `kind` hace bien lo que promete: probar que **entiendes** Kubernetes. Su propia página dice que fue «diseñado principalmente para probar Kubernetes mismo», aunque puede usarse para desarrollo local o integración continua. No promete un clúster que aguante lo que un servicio real exige. La [documentación de Kubernetes sobre entornos de producción](https://kubernetes.io/docs/setup/production-environment/) abre con una frase que resume la diferencia (traducido): un entorno de producción típico «tiene más requisitos que un entorno personal de aprendizaje, desarrollo o pruebas».

La lista que sigue tiene catorce cosas. No hace falta que las recuerdes todas; sí que reconozcas el patrón: casi todas son una pieza que **en `kind` existe en versión de laboratorio** y en un clúster real hay que reemplazar, reforzar o agregar. Cada una dice qué hace el curso, qué exige un clúster real, qué se haría, y de dónde sale.

**1. Un plano de control de un solo nodo.** El curso tiene un nodo de control. Si se detiene, no puedes cambiar nada, y qué más deja de funcionar no es seguro: en el Ejercicio 3, los contenedores ya iniciados siguieron corriendo, pero la puerta de entrada solo siguió respondiendo en 1 de 4 corridas. Un clúster real replica el plano de control en varios nodos y balancea la carga hacia el servidor de la API; la [documentación de entornos de producción](https://kubernetes.io/docs/setup/production-environment/) enumera justo esas piezas, y recuerda que un entorno de una sola máquina «tiene un único punto de falla». Muchos equipos prefieren un plano de control administrado por un proveedor.

**2. Un `etcd` sin respaldo probado.** Todo el estado del clúster —los objetos que aplicaste— vive en `etcd`. Si se pierde, se pierde el clúster. La [guía de operación de `etcd`](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) enseña cómo sacar una copia con `etcdctl snapshot save` y cómo revisarla con `etcdutl snapshot status`. Y aquí vuelve el caso de GitLab de la apertura: el respaldo que no se ha restaurado en un ensayo no es un respaldo. Se programa, y se **restaura de verdad** en un clúster de pruebas con una periodicidad que alguien decida.

**3. Secretos guardados sin cifrar.** Lo viste en la Lección 4: un `Secret` es base64, y dentro de `etcd` se guarda en texto claro salvo que el administrador configure el cifrado en reposo. La [guía de cifrado de datos en reposo](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) explica cómo se configura en el `kube-apiserver`, y la [lista de verificación de seguridad](https://kubernetes.io/docs/concepts/security/security-checklist/) la pide: «el cifrado en reposo está configurado para la API de Secrets». Para secretos que no deberían vivir en el clúster, la misma lista menciona inyectarlos desde un almacén externo.

**4. HTTP en texto plano.** La puerta del `revisor` habla HTTP en el puerto 80, y el token viaja en un encabezado sin cifrar (la Lección 6 lo midió). Un clúster real termina TLS en el *Gateway*: la [guía de TLS de Gateway API](https://gateway-api.sigs.k8s.io/guides/tls/) describe cómo un *listener* HTTPS termina el cifrado con un certificado. Además hay que emitirlo y renovarlo, y la lista de seguridad pregunta por el cifrado dentro del clúster (que depende del CNI o de una malla de servicios).

**5. Una dirección que MetalLB reparte en una red de Docker.** En capa 2, la [documentación de MetalLB](https://metallb.io/concepts/layer2/) lo dice: todo el tráfico de una IP va a **un solo nodo**, y desde ahí `kube-proxy` lo reparte. «En ese sentido, la capa 2 no implementa un balanceador de carga: implementa un mecanismo de *failover*.» Sus dos límites son un cuello de botella en un nodo y una conmutación potencialmente lenta. En la nube, el balanceador lo da el proveedor; en un centro de datos propio se suele usar MetalLB en modo BGP u otro balanceador.

**6. `metrics-server` con `--kubelet-insecure-tls`.** Lo viste en 10.3.4: «solo para pruebas», dice su propio README. En un clúster real los certificados de los `kubelet` se firman con la autoridad del clúster y la bandera sobra. Su README agrega algo que importa: `metrics-server` es **solo** para el escalado automático; para monitoreo se usa otra cosa.

**7. Nodos que son contenedores en tu máquina.** Los tres «nodos» comparten tu procesador, tu memoria, tu disco y tu núcleo. Si tu computadora se apaga, se apaga todo; no hay zonas de disponibilidad ni centros de datos distintos. Un clúster real reparte nodos entre zonas y reparte las réplicas entre ellas (el parche de `ejemplo-nube` de 10.3.3 cambia justamente eso, de nodos a zonas), y tiene más de uno de cada cosa que importe.

**8. Almacenamiento que vive en el nodo.** El volumen del reporte es un directorio del disco de un nodo (`local-path`, Lección 8): si el nodo se va, los datos también. Un clúster real usa almacenamiento externo con replicación y copias, y los datos tienen la misma historia de respaldo que `etcd`: hay copia, y hay un ensayo de restauración.

**9. Imágenes cargadas a mano.** Las dos imágenes del curso llegaron con `kind load docker-image`, con una etiqueta local. Un clúster real las baja de un registro. La [lista de seguridad](https://kubernetes.io/docs/concepts/security/security-checklist/) pide referirse a ellas **por huella `sha256`** (porque una etiqueta se puede mover en el registro), revisarlas con un escáner de vulnerabilidades y verificar su firma con un controlador de admisión. El curso ya fija la huella de la imagen de `curl`; las del `revisor` y la de prueba, que son locales, no.

**10. Un solo administrador y ninguna identidad.** Tu `kubeconfig` de `kind` es de administrador total; nadie más entra. Un clúster real tiene usuarios y grupos con permisos distintos, un proveedor de identidad y una revisión periódica de accesos. La lista de seguridad pide, por ejemplo, que el grupo `system:masters` no se use para autenticar personas ni componentes después del arranque, y una revisión de accesos «no más de 24 meses» entre una y otra.

**11. Observabilidad que es `kubectl logs`.** Tienes bitácora mientras el Pod existe. La [documentación de *logging*](https://kubernetes.io/docs/concepts/cluster-administration/logging/) lo explica con claridad (traducido): si un contenedor se cae, un Pod se desaloja o un nodo muere, quieres seguir viendo sus bitácoras; por eso deben tener un almacenamiento «con un ciclo de vida independiente de los nodos, los Pods y los contenedores», y Kubernetes «no proporciona una solución nativa» para eso. Falta también la parte de métricas históricas y alertas: alguien que te avise antes de que lo descubra la dirección.

**12. Actualizaciones sin plan.** El clúster del curso se crea y se borra; uno real se actualiza en caliente, durante años. La [política de versiones soportadas](https://kubernetes.io/releases/version-skew-policy/) dice que el proyecto mantiene las tres versiones menores más recientes (hoy 1.37, 1.36 y 1.35), con cerca de un año de parches, y fija cuánta diferencia puede haber entre componentes (un `kubelet` puede ir hasta tres versiones menores detrás del servidor de la API, nunca por delante). Y cada pieza de la plataforma tiene su propio orden de actualización: la guía de Envoy Gateway pide actualizar primero los CRD de Gateway API, y advierte de lo que pasa si no se hace.

**13. Sin cuotas ni límites por equipo.** La Lección 5 puso `requests` y `limits` en cada contenedor, pero nada impide a alguien crear cien Pods. La [documentación de cuotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) describe el `ResourceQuota`: restricciones al consumo total **por espacio de nombres**, y a la cantidad de objetos de cada tipo. Con varios equipos en un clúster, es lo que evita que uno se coma lo de los demás.

**14. Una plataforma sin dueño ni nivel de seguridad declarado.** 10.7.4 lo mostró: los espacios de MetalLB y de `kube-system` no cumplen `restricted` (el de Envoy Gateway sí), y aquí ninguno de los tres tiene etiqueta ni responsable. En un clúster real, cada espacio de plataforma tiene un nivel declarado y un equipo responsable, y los *webhooks* de esa plataforma son una **dependencia del clúster**: como la `failurePolicy` por omisión es `Fail` (10.4.1), si el Pod del guardián está caído, no se pueden crear los objetos que vigila. Por eso se les da más de una réplica y se vigilan como a cualquier servicio crítico.

Nada de esto vuelve inútil lo que construiste. Lo contrario: el proyecto de esta lección, la base, con todos sus objetos, **es** lo que se llevaría a un clúster real. Lo que cambia es la capa de abajo —el overlay y la plataforma—, y esa es justamente la capa que Kustomize separa.

#### 10.10.2 Las catorce, en una tabla

| # | En el curso | En un clúster real |
|---|---|---|
| 1 | un nodo de control | varios nodos de control, o uno administrado |
| 2 | `etcd` sin respaldo | copias de `etcd` con ensayos de restauración |
| 3 | `Secret` sin cifrar en `etcd` | cifrado en reposo y/o almacén externo de secretos |
| 4 | HTTP en el puerto 80 | TLS terminado en el Gateway |
| 5 | MetalLB en capa 2 sobre una red de Docker | balanceador del proveedor, o MetalLB con BGP |
| 6 | `--kubelet-insecure-tls` | certificados de `kubelet` firmados por el clúster |
| 7 | nodos que son contenedores | nodos en varias zonas, con réplicas repartidas entre ellas |
| 8 | volumen en el disco de un nodo | almacenamiento externo replicado, con copias |
| 9 | imágenes cargadas a mano | registro, huella `sha256`, escaneo y firma |
| 10 | un administrador | identidades, grupos, revisión de accesos |
| 11 | `kubectl logs` | bitácoras y métricas con almacenamiento propio y alertas |
| 12 | clúster desechable | plan de actualización por versión |
| 13 | sin cuotas | `ResourceQuota` por espacio |
| 14 | plataforma sin nivel declarado | nivel y dueño por espacio, y réplicas para los *webhooks* |

Si tuvieras que ordenar esta lista por «qué me preocuparía primero», no hay una respuesta única: depende de qué pierdes si falla. Pero un criterio razonable es empezar por lo que **no se puede reconstruir**. El proyecto sí se puede reconstruir (acabas de hacerlo, dos veces); los datos del reporte y el estado de `etcd` no. Por eso el respaldo con restauración probada (la 2 y la 8) suele ir antes que casi todo lo demás, y el cifrado y el TLS (la 3 y la 4) van junto a lo que se expone. El Ejercicio 4 te pide justo eso.

## El error que vas a ver

Esta lección tiene tres errores a propósito, y ya los viste en su sección: la plataforma aplicada sin `--server-side` (10.4.3), la plataforma y el proyecto juntos en un solo comando (10.4.4) y un Deployment que viola `restricted` (10.7.5). Los tres tienen algo en común que conviene decir con todas sus letras, porque es lo que de verdad se aprende: **ninguno es un error del clúster**. El clúster hizo exactamente lo que se le pidió y dijo claramente por qué no podía. Lo que cambió entre el intento fallido y el exitoso fue *el orden o la forma de pedir*, no el clúster.

El orden para leer cualquiera de ellos es el mismo que en las lecciones anteriores, ahora con las herramientas de esta:

1. ¿Qué dice el **código de salida** del `apply` y qué líneas **no** son un `created` o un `serverside-applied`? Ahí está el mensaje.
2. ¿El mensaje menciona un **tipo que no existe** (`no matches for kind`, `ensure CRDs are installed first`) o un **guardián que no atiende** (`failed calling webhook`)? Entonces falta esperar a la plataforma: una espera por condición, no un reintento.
3. ¿Menciona un **tamaño** o un **conflicto de gestor** (`Too long`, `conflict`)? Entonces es de la forma de aplicar: `--server-side`.
4. ¿Es una **advertencia** (`Warning: would violate PodSecurity`)? El objeto se aceptó y no va a funcionar: corrige el manifiesto.

Y antes de cambiar nada, aplicar el mismo comando una segunda vez para «ver si pasa» **no es un diagnóstico**: 10.4.4 te mostró que a veces pasa a medias y deja lo peor, un estado que parece sano y no lo es.

## El hábito de seguridad de la lección: se revisa contra la norma, y se dice lo que falta

La tabla de hábitos del curso le asigna a esta lección dos cosas: la revisión final contra el nivel `restricted` y la lista de lo que un clúster real exige. Las dos son hábitos de **no confiar en lo que parece**.

**La revisión con control.** Una consulta que dice «sin advertencias» no vale nada por sí sola, porque una herramienta que no revisa y una que revisa y no encuentra nada dicen lo mismo. Por eso 10.5.3 cuenta las advertencias (`grep -ci warning`), 10.7.5 aplica un Deployment que **sí** debe producirlas y 10.7.3 prueba la consulta de revisión en un espacio con un Pod que viola: la primera consulta que se escribió sobre `revisor` daba cero advertencias y no revisaba nada, y fue ese control el que lo mostró. Si el segundo caso no hubiera producido advertencias, el primero no habría significado nada. Es el mismo principio con el que se mide cualquier cosa: antes de creerle a un cero, enséñale algo que debería contar.

**La lista de lo que falta.** Es el segundo hábito y el más incómodo: escribir lo que *no* tienes. Un proyecto que dice «cumple `restricted`» y calla que su `etcd` no tiene respaldo da una idea falsa de qué tan protegido está. La lista de 10.10 no es una disculpa; es el documento que le permite a quien tome decisiones saber qué riesgo corre.

**Lo que defiende y lo que no.** La revisión contra `restricted` protege contra una configuración descuidada: un contenedor que arranca como `root`, que puede ganar privilegios o que conserva capacidades que no necesita. No protege contra una vulnerabilidad dentro del programa del `revisor`, contra un token que se filtra, ni contra una imagen manipulada en el camino. Y la lista de 10.10 te dice qué más haría falta, pero no lo instala: nombrar un faltante no es resolverlo.

## Lo que se hace mal

**Reintentar hasta que pase.** Es el ciclo `until kubectl apply …; do sleep 5; done`. Esconde la causa, a veces deja un estado a medias, y el día que falla de verdad se queda dando vueltas en silencio. Se espera la condición, con tope.

**Un `sleep` fijo entre la plataforma y el proyecto.** Funciona en tu máquina y falla en una más lenta o más cargada. Un `sleep` mide el reloj; `kubectl wait` mide la condición.

**Juntar plataforma y proyecto en un solo `kustomization`.** Parece más ordenado y rompe el orden (10.4.4). Las dos mitades tienen condiciones de salida distintas, y por eso son comandos distintos.

**Aplicar la plataforma sin `--server-side`.** Los CRD grandes no caben en la anotación que guarda el cliente (10.4.3). La guía oficial de Envoy Gateway ya trae la bandera.

**Un overlay que copia la base.** Si copias los archivos de la base a la carpeta del overlay «para cambiarles una línea», tienes dos copias que se van a separar. Un overlay apunta (`resources: ../../base`) y parcha.

**Un guion que usa «el clúster activo».** Instala cosas en el contexto que esté a mano, que puede no ser el tuyo. El contexto esperado se pasa como argumento y se comprueba antes de cada paso.

**`|| true` para que nada se detenga.** Un guion que no se detiene ante un error no te dice que hubo uno. Si un fallo es aceptable, se maneja ese caso y se dice cuál es.

**Decir «sin errores» sin haberlo medido.** O «sin advertencias» sin un caso que las produzca. Una afirmación de ausencia necesita un control positivo.

**Versiones sin fijar.** Una dirección que apunta a «la última versión» cambia sola. Todas las piezas de esta lección van con su versión en la ruta, y las imágenes de `curl` con su huella.

**Versionar el token.** Es de mentira, pero el hábito es el que importa: el `.gitignore` y el `umask 077`.

**Etiquetar con `enforce: restricted` un espacio de plataforma sin revisarlo.** 10.7.4 lo mostró: MetalLB y `kube-system` tienen Pods que `restricted` rechazaría. Un `dry-run` antes de la etiqueta evita romper la red de un clúster.

**Tomar `kind` por un clúster real.** Es la que 10.10 desarrolla en catorce puntos, y la que más cuesta cuando se olvida.

## Ejercicios

Los ejercicios 1 a 3 se corren en el clúster de la lección, ya levantado como lo dejó 10.8. Antes de cada uno, `ctx` (10.1.2) debe pasar. `correr.sh` los corre igual, y su salida está en `correr.salida.txt`. **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — Un overlay propio

Escribe un overlay que parta del overlay de `kind` y cambie **una sola cosa**: que el escalado automático no pase de 4 réplicas (hoy llega a 6). Sin tocar la base ni el overlay de `kind`. Antes de correrlo, predice: ¿cuántas líneas del manifiesto armado cambian, respecto de `overlays/kind`? ¿Cómo lo comprobarías **sin aplicar** nada, y cómo con el clúster pero sin cambiarlo?

### Ejercicio 2 — De «malo» a `restricted`

`fig10_02.deployment-malo.yaml` viola el nivel `restricted`. Corrígelo hasta que se aplique en el espacio `revisor` **sin una sola advertencia** y sus Pods lleguen a `Available`. Antes de empezar, predice: ¿cuáles son los controles que le faltan? Después de corregirlo, ¿qué cuenta de advertencias esperas? Pista: la lista está en 10.7.1, y la prueba positiva ya la tienes de 10.7.5.

### Ejercicio 3 — Se detiene el plano de control

En 10.8.3 detuviste un nodo de trabajo. Ahora detén el nodo de control (`docker stop curso-k8s-l10-control-plane`) durante un minuto. Predice antes, y escríbelo: ¿`kubectl get nodes` contesta? ¿Los contenedores del `revisor` siguen corriendo en los nodos de trabajo? (Sin API puedes preguntarle al nodo mismo: `docker exec <nodo> crictl ps`.) ¿Y la puerta, `http://<dirección>/salud` desde fuera del clúster, sigue respondiendo? Anota lo que veas aunque no coincida con la solución: el resultado no es siempre el mismo. Después levanta el nodo, mide cuánto tarda la API en volver y comprueba que el guardián de MetalLB contesta antes de aplicar nada. Con tus medidas, explica por qué el plano de control y los nodos de trabajo se llaman así, y qué diría la lista de 10.10 sobre el punto 1. **Un aviso:** en tu máquina, el nodo de control puede cambiar de dirección IP al reiniciarse si otro contenedor tomó la suya en la red de Docker; si eso pasa, el clúster deja de funcionar y se vuelve a crear. En el clúster de la corrida de esta lección, con una red propia y sin otros contenedores, no pasó.

### Ejercicio 4 — Defiende tu lista

Elige **cinco** de los catorce puntos de 10.10 y, en cinco líneas como máximo por punto: qué hace tu proyecto hoy, qué exigiría un clúster real y qué harías tú, con qué orden. Luego ordénalos por «qué me preocuparía primero» y defiende el primer lugar en tres frases: ¿qué se pierde si falla, y se puede reconstruir?

## Soluciones

### Solución 1

El overlay es `fig10_03.overlay-mio/kustomization.yaml`:

```yaml
# fig10_03.overlay-mio/kustomization.yaml — solución del Ejercicio 1: un overlay
# propio que parte del overlay de kind y cambia UNA cosa (el máximo de réplicas del
# HPA, de 6 a 4) sin tocar la base. Se comprueba con:
#   kubectl kustomize fig10_03.overlay-mio
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../overlays/kind
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: revisor
  patch: |-
    - op: replace
      path: /spec/maxReplicas
      value: 4
```

Medido en `correr.salida.txt`:

```text
$ kubectl kustomize fig10_03.overlay-mio | grep -n -E 'maxReplicas|minReplicas'
391:  maxReplicas: 4
399:  minReplicas: 2

$ kubectl diff --server-side -k fig10_03.overlay-mio | grep -E '^[+-] +(max|min)Replicas'
-  maxReplicas: 6
+  maxReplicas: 4
[código de salida: 1]

$ grep -c maxReplicas base/escalado.yaml
1
```

Una sola línea cambia. `kubectl kustomize` imprime el resultado sin tocar nada: `maxReplicas: 4` en la línea 391, y `minReplicas: 2` intacto en la 399. Con el clúster, `kubectl diff --server-side` compara lo que aplicarías contra lo que hay y muestra exactamente `-  maxReplicas: 6` y `+  maxReplicas: 4`; el `[código de salida: 1]` es el de `kubectl diff` cuando **hay** diferencias (0 si no las hay). Y la prueba de que la base no se tocó: `base/escalado.yaml` sigue teniendo su única línea `maxReplicas`. Para aplicarlo bastaría `kubectl apply --server-side -k fig10_03.overlay-mio`; el ejercicio no lo pide para que el clúster siga siendo lo que dicen los archivos de la lección.

### Solución 2

La corrección es `fig10_04.deployment-corregido.yaml`: el mismo Deployment con `automountServiceAccountToken: false`, el `securityContext` del Pod (no-`root`, usuario 65532, *seccomp* `RuntimeDefault`) y el del contenedor (sin escalada de privilegios, sistema de archivos de solo lectura, sin capacidades), más piso y techo de recursos.

```yaml
# fig10_04.deployment-corregido.yaml — solución del Ejercicio 2: el mismo Deployment
# de fig10_02.deployment-malo.yaml, ahora con todo lo que pide el nivel «restricted»
# (y lo que el curso pide además: sin credenciales de la API, sistema de archivos
# de solo lectura, piso y techo de recursos).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: malo
  labels:
    app: malo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: malo
  template:
    metadata:
      labels:
        app: malo
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: malo
        image: curso-docker-prueba:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 9000
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Medido en `correr.salida.txt`:

```text
$ kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml 2>&1 | grep -ci warning
0
[código de salida: 1]

$ kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml
deployment.apps/malo unchanged

$ kubectl get deployment malo -n revisor
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
malo   1/1     1            1           2s

$ kubectl delete -n revisor -f fig10_04.deployment-corregido.yaml
deployment.apps "malo" deleted from revisor namespace
```

El conteo de advertencias da **0**. Ese comando ya aplicó el Deployment (el `grep` sólo cuenta lo que `apply` imprime), y por eso el segundo `apply` dice `unchanged`: no había nada que cambiar. El Deployment llega a `1/1` y a `Available`, así que los Pods ya no se rechazan. Cada control tiene su campo: `allowPrivilegeEscalation: false` y `capabilities.drop: ["ALL"]` en el contenedor; `runAsNonRoot: true` (con `runAsUser: 65532`) y `seccompProfile.type: RuntimeDefault` en el Pod. El resto —`readOnlyRootFilesystem`, `automountServiceAccountToken: false`, piso y techo— no los pide `restricted`; los pide el curso.

### Solución 3

Medido en `correr.salida.txt`:

```text
$ kubectl get servicel2statuses -n metallb-system
NAME       ALLOCATED NODE          SERVICE NAME                     SERVICE NAMESPACE
l2-pkb9d   curso-k8s-l10-worker2   envoy-revisor-revisor-b269644b   envoy-gateway-system

# el Pod revisor-654b5d75dc-qcqfz vive en curso-k8s-l10-worker2 con la IP 10.244.2.5

$ docker stop curso-k8s-l10-control-plane
curso-k8s-l10-control-plane

$ kubectl get nodes --request-timeout=5s 2>&1 | cut -c1-200
The connection to the server 127.0.0.1:64201 was refused - did you specify the right host or port?
[código de salida: 1]

# una petición cada 2 s durante 45 s a la puerta, desde fuera del clúster (se muestran los cambios)
[+0s] ok
bien=23 mal=0

# sin API, pero con acceso al nodo: ¿los contenedores siguen corriendo y contestando?

$ docker exec curso-k8s-l10-worker2 crictl ps | grep -E 'CONTAINER|revisor'
CONTAINER           IMAGE               CREATED              STATE               NAME                ATTEMPT             POD ID              POD                                               NAMESPACE
05a1aec248153       a25150a910b03       2 minutes ago        Running             shutdown-manager    1                   50c0eb8926152       envoy-revisor-revisor-b269644b-867f46cd7d-vsnj9   envoy-gateway-system
1edc39ddbcac7       370bbc1c75d75       2 minutes ago        Running             envoy               1                   50c0eb8926152       envoy-revisor-revisor-b269644b-867f46cd7d-vsnj9   envoy-gateway-system
515dc19d2f9d1       70e09194319be       2 minutes ago        Running             revisor             1                   6515939e5a0b1       revisor-654b5d75dc-qcqfz                          revisor

$ docker exec curso-k8s-l10-worker2 curl -s -m 3 http://10.244.2.5:8080/salud
{"estado":"vivo","version":"1.6.0"}

$ docker start curso-k8s-l10-control-plane
curso-k8s-l10-control-plane
(la API volvió a contestar 59 s después de detener el nodo de control)

$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l10-control-plane condition met
node/curso-k8s-l10-worker condition met
node/curso-k8s-l10-worker2 condition met

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready    control-plane   9m8s    v1.37.0
curso-k8s-l10-worker          Ready    <none>          8m57s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          8m56s   v1.37.0

$ kubectl get servicel2statuses -n metallb-system
NAME       ALLOCATED NODE          SERVICE NAME                     SERVICE NAMESPACE
l2-pkb9d   curso-k8s-l10-worker2   envoy-revisor-revisor-b269644b   envoy-gateway-system

$ kubectl get pods -n revisor -o wide
NAME                       READY   STATUS      RESTARTS        AGE     IP            NODE                    NOMINATED NODE   READINESS GATES
depurar                    1/1     Running     0               4m4s    10.244.1.9    curso-k8s-l10-worker    <none>           <none>
intruso                    1/1     Running     0               4m4s    10.244.1.10   curso-k8s-l10-worker    <none>           <none>
prueba-6899c74865-rzh88    1/1     Running     0               5m47s   10.244.1.4    curso-k8s-l10-worker    <none>           <none>
reporte-29877095-rwc6k     0/1     Completed   0               4m7s    10.244.1.11   curso-k8s-l10-worker    <none>           <none>
revisor-654b5d75dc-qcqfz   1/1     Running     1 (2m22s ago)   4m8s    10.244.2.5    curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running     0               4m10s   10.244.1.7    curso-k8s-l10-worker    <none>           <none>

# ¿contesta ya el guardián (webhook) de MetalLB? Una prueba en seco del rango, sin aplicar nada

$ kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300
Warning: resource ipaddresspools/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation w
ipaddresspool.metallb.io/curso configured (server dry run)
Warning: resource l2advertisements/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation
l2advertisement.metallb.io/curso configured (server dry run)

# espera (hasta 3 minutos) a que el guardián de MetalLB conteste

$ kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300
Warning: resource ipaddresspools/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation w
ipaddresspool.metallb.io/curso configured (server dry run)
Warning: resource l2advertisements/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation
l2advertisement.metallb.io/curso configured (server dry run)
```

Léelo en orden. **La API no contesta**: `kubectl` se queda con `connection … was refused` contra `127.0.0.1` (el puerto que `kind` publica del nodo de control). Sin el plano de control no puedes ver, crear, cambiar ni borrar nada. **Los contenedores siguieron vivos** en las dos corridas donde se comprobó (la 5 de preparación y la de la lección): sin API, pero con acceso al nodo, `crictl ps` lista corriendo al `revisor` y a los dos contenedores de Envoy, y un `curl` desde el nodo a la IP del Pod contesta `{"estado":"vivo","version":"1.6.0"}`. Eso dice que los contenedores no se apagan solos; no dice que el servicio llegue a quien lo pide. **La puerta**, en esta corrida, respondió las 23 peticiones (`bien=23 mal=0`) durante los 45 segundos. Y aquí va una advertencia que se midió y no se explicó: en **tres corridas de preparación** de esta misma lección (guardadas en `programas/10-proyecto-final/corridas-preparacion/`: `corrida1.txt`, `corrida4.txt` y `corrida5.txt`), con el mismo ejercicio, la puerta no respondió ninguna de sus peticiones mientras el plano de control estaba detenido (`bien=0 mal=12`, 12 de 12 fallidas, en la 4 y la 5; en la 1, `curl` salió con código 7, conexión rechazada, al instante). En total, la puerta respondió en 1 de 4 corridas, aunque `ServiceL2Status` (lo midieron las dos últimas) decía que un nodo de trabajo anunciaba la dirección. No se encontró la causa. Lo honesto es una frase: en `kind`, con MetalLB y Envoy Gateway, **no des por hecho** que la puerta sobrevive sin plano de control, ni tampoco lo contrario: con 4 corridas no se puede decir más que «1 de 4». Anota lo que veas en la tuya; puede ser distinto del de esta solución. **La API volvió** 59 segundos después de detener el nodo de control.

Y una segunda lección, de la última comprobación. Cuando el nodo de control vuelve, `kubectl wait` dice que los tres nodos están `Ready`, pero eso no quiere decir que todo lo demás esté listo. En una corrida de preparación, el `kubectl diff` final falló con `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connection refused`: el guardián de MetalLB todavía no contestaba (10.4.1, otra vez). Por eso el guion pregunta al guardián con una prueba en seco del rango —`kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml`— y espera con tope a que conteste. En esta corrida contestó al primer intento: `ipaddresspool.metallb.io/curso configured (server dry run)`. Las dos líneas `Warning` que la acompañan no son de seguridad: dicen que el rango se creó con `--server-side` y no tiene la anotación `last-applied-configuration` que usa el `apply` del lado del cliente. Es la diferencia de 10.4.2, y aquí es inofensiva porque es una prueba en seco. Tras la espera, `kubectl diff --server-side -k overlays/kind` dice `sin diferencias con los archivos`.

Lo que esto dice del punto 1 de 10.10: un plano de control de un solo nodo es un punto único de falla: sin él no puedes **cambiar** nada y nadie repone ni escala; lo que ya corre puede seguir corriendo (los contenedores lo hicieron) o dejar de ser alcanzable (la puerta, 3 de 4 veces), y no se encontró de qué depende. Y por qué se llaman así: el plano de control **decide** (qué debe existir y dónde); los nodos de trabajo **ejecutan**.

### Solución 4

Una respuesta posible, para la lista de cinco: «**(2) `etcd` sin respaldo**: hoy no hay copia; un clúster real programa `etcdctl snapshot save` y *restaura de verdad* en un clúster de pruebas cada cierto tiempo, y lo hago primero porque es lo único que no puedo reconstruir con `kubectl apply`. **(8) Volumen en el disco de un nodo**: hoy el reporte vive en el nodo; en uno real, almacenamiento replicado y copias, con la misma prueba de restauración. **(3) Secretos sin cifrar**: hoy están en base64 dentro de `etcd`; configuraría el cifrado en reposo y, para secretos que no deban vivir en el clúster, un almacén externo. **(4) HTTP en el puerto 80**: terminaría TLS en el Gateway y rotaría el token, que ha viajado en texto plano. **(1) Plano de control de un nodo**: tres nodos de control o un plano administrado.» El orden de preocupación: primero lo que no se reconstruye (2 y 8), después lo que se expone (3 y 4), al final la disponibilidad (1). Defensa del primer lugar: «Si falla el `etcd` sin respaldo, pierdo el estado del clúster; el proyecto se reconstruye con dos comandos y una espera (lo probé dos veces), pero lo que el clúster sabía de sí mismo no. Y un respaldo que nunca se restauró no es una respuesta: es una hipótesis.»

## Borrar el clúster

Cuando termines, borra el clúster de la lección y lo que dejaste en tu máquina. No dejes nada vivo:

```bash
# El clúster (con su nombre: sin --name, kind borra el llamado «kind»).
kind delete cluster --name curso-k8s-l10
kind get clusters | grep -c curso-k8s-l10    # debe decir 0
# El token de la lección: es de mentira, pero un token suelto no se deja.
rm -f -- base/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 10.1.2.
case "$L10_TMP" in
  /tmp/curso-k8s-l10.?*) rm -rf -- "$L10_TMP" ;;
  *) echo "No borro «$L10_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L10_TMP
```

```text
$ kind delete cluster --name curso-k8s-l10
Deleting cluster "curso-k8s-l10" ...
Deleted nodes: ["curso-k8s-l10-worker2" "curso-k8s-l10-control-plane" "curso-k8s-l10-worker"]

$ kind get clusters | grep -c curso-k8s-l10
0
[código de salida: 1]
```

(Las líneas entre paréntesis las escribe el guion, que mide el borrado. El `grep -c` imprime `0` y sale con código 1, porque no encontró ningún clúster con ese nombre: es la respuesta que buscas.) El `case` solo deja pasar una ruta que empiece con `/tmp/curso-k8s-l10.` y tenga algo después, la forma exacta de la que creaste en 10.1.2. Si `L10_TMP` está vacía o vale otra cosa, no borra nada y te dice por qué. Si hiciste el Ejercicio 3 en una segunda terminal, ciérrala. Y si usaste una red de Docker propia (la corrida de esta lección lo hizo; tú, con la red `kind`, no), bórrala **después** del clúster y solo si la creaste tú: `docker network rm <nombre>`.

Este fue el último clúster del curso. Los de las lecciones anteriores ya los borraste, uno por lección, y con eso termina el método: crear, usar, borrar, y poder volver a crear.

## Cómo sé que lo logré

- [ ] Abres un `kustomization.yaml` y dices qué es una base, qué es un overlay, qué arma y cómo comprobarlo con `kubectl kustomize` sin aplicar nada.
- [ ] Desde un clúster vacío, levantas el proyecto con la plataforma, una espera por condición y el proyecto, y explicas por qué ese orden.
- [ ] Lees `no matches for kind … ensure CRDs are installed first` y el mensaje de un CRD demasiado grande sin `--server-side`, y dices qué los causa.
- [ ] Corres `programas/10-proyecto-final/probar-levantar.sh` y comparas su salida con `programas/10-proyecto-final/correr.salida.txt` en lo que no cambia entre corridas: la plataforma aplicada con `serverside-applied`; las cinco esperas con `condition met` o `successfully rolled out`; el proyecto con sus objetos y sin una sola línea `Warning`; el Gateway `Programmed`; `{"estado":"vivo","version":"1.6.0"}` desde fuera, en las dos vueltas; y que el clúster ya no existe al terminar. Las IP, los sufijos de los nombres, las edades y los segundos cambian en cada corrida: se observan, no se comparan.
- [ ] Sabes por qué `kubectl label --dry-run=server … enforce=restricted` sobre `revisor` (que ya lo tiene) responde `not labeled` sin revisar ningún Pod, y revisas los Pods existentes pidiendo una política distinta (`enforce-version=v1.36`), con el control del espacio `psa-control` que nombra al Pod que viola y no al que cumple.
- [ ] Detienes un nodo de trabajo, mides la ventana en la que fallan peticiones y explicas por qué dura lo que dura y qué la reduce.
- [ ] Cambias la lista de servicios y ves un `ConfigMap` nuevo y un ReplicaSet nuevo sin reconstruir la imagen.
- [ ] El `intruso` no llega al `revisor` y `depurar` sí; la cuenta `revisor` no puede ni leer Pods.
- [ ] `kubectl get hpa` muestra un porcentaje, no `<unknown>`.
- [ ] Escribes, con tus palabras, cinco cosas por las que lo que construiste no es un clúster real, qué harías con cada una y por cuál empezarías.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l10`.

## Resumen

Responde sin mirar la lección:

1. ¿Qué es una base y qué es un overlay? ¿Una base sabe de sus overlays?
2. ¿Qué diferencia hay entre una pieza de plataforma y una de proyecto, y qué tres cosas trae una plataforma?
3. ¿Qué condición espera `kubectl wait` en un CRD, y cuál en un Deployment?
4. ¿Qué cambia `--server-side` y qué error evita en la plataforma?
5. ¿Qué pasa si juntas plataforma y proyecto en un solo comando, y por qué repetirlo «a ver si pasa» no es un método?
6. ¿Por qué un guion de levantamiento recibe el contexto como argumento y lo comprueba antes de cada paso?
7. ¿Qué pide el nivel `restricted` y qué hace el proyecto además de eso?
8. ¿Por qué parte de la plataforma (MetalLB, `kube-system`) no cumple `restricted`, y qué condición pones para que eso sea aceptable?
9. Con un nodo de trabajo detenido, ¿por qué fallan peticiones durante decenas de segundos y qué no acorta esa ventana?
10. ¿Cuándo usarías Helm en lugar de Kustomize?
11. Nombra cinco cosas por las que el clúster del curso no es un clúster real y qué harías con cada una.

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Declarative Management of Kubernetes Objects Using Kustomize»](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): bases y overlays, generadores con *hash*, `patches`, `images`, y `kubectl kustomize` / `apply -k`.
- [Kubernetes, «Server-Side Apply»](https://kubernetes.io/docs/reference/using-api/server-side-apply/): gestores de campos, conflictos, y la comparación con el `apply` del lado del cliente.
- [Kubernetes, «Custom Resources»: CustomResourceDefinition](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/): la condición `Established` de un CRD.
- [Kubernetes, «Dynamic Admission Control»](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): *webhooks* de admisión y `failurePolicy` (por omisión `Fail`).
- [Kubernetes, «kubectl wait»](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): esperar una condición en uno o varios recursos.
- [Kubernetes, «Virtual IPs and Service Proxies»](https://kubernetes.io/docs/reference/networking/virtual-ips/): que `kube-proxy` elige al azar el Pod destino de un Service en los modos `iptables` y `nftables`.
- [Kubernetes, «Pod Security Standards»](https://kubernetes.io/docs/concepts/security/pod-security-standards/): los controles de `baseline` y `restricted`, campo por campo.
- [Kubernetes, «Pod Security Admission»](https://kubernetes.io/docs/concepts/security/pod-security-admission/) y [«Enforce Pod Security Standards with Namespace Labels»](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): los modos `enforce`, `audit` y `warn`, las versiones fijadas, y la prueba con `--dry-run=server`.
- [Kubernetes, «Node Status»](https://kubernetes.io/docs/reference/node/node-status/), [«kube-controller-manager»](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) y [«Taints and Tolerations»](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): los 50 segundos de `node-monitor-grace-period` y la tolerancia de 300 segundos.
- [Kubernetes, «Production environment»](https://kubernetes.io/docs/setup/production-environment/), [«Security checklist»](https://kubernetes.io/docs/concepts/security/security-checklist/), [«Encrypting Confidential Data at Rest»](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/), [«Operating etcd clusters»](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/), [«Logging Architecture»](https://kubernetes.io/docs/concepts/cluster-administration/logging/), [«Resource Quotas»](https://kubernetes.io/docs/concepts/policy/resource-quotas/) y [«Version Skew Policy»](https://kubernetes.io/releases/version-skew-policy/): lo que un clúster real exige y la política de versiones.
- [kind, *issues* #4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) y [#4224](https://github.com/kubernetes-sigs/kind/issues/4224): fallos de `kind load` con Docker 29 y el almacén de `containerd` (el aviso de 10.1.2).
- [kind](https://kind.sigs.k8s.io/): para qué fue diseñado `kind`. Y [`provider.go` de kind v0.33.0](https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provider.go): la variable `KIND_EXPERIMENTAL_DOCKER_NETWORK`, que la corrida de esta lección usó.
- [Envoy Gateway, «Install with Kubernetes YAML»](https://gateway.envoyproxy.io/docs/install/install-yaml/) y [«Install with Helm»](https://gateway.envoyproxy.io/docs/install/install-helm/): la instalación con `--server-side`, la instalación con Helm y el orden de actualización de los CRD.
- [MetalLB, «Layer 2 mode»](https://metallb.io/concepts/layer2/): cómo funciona y sus dos límites.
- [metrics-server v0.9.0, README](https://github.com/kubernetes-sigs/metrics-server/blob/v0.9.0/README.md): `--kubelet-insecure-tls` «solo para pruebas», y que es solo para el escalado automático.
- [Gateway API, «TLS»](https://gateway-api.sigs.k8s.io/guides/tls/): terminar TLS en un *listener*.
- [Helm, «Using Helm»](https://helm.sh/docs/intro/using_helm/) y [«Custom Resource Definitions»](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/): qué es un chart y cómo trata los CRD.
- [RFC 6902, «JavaScript Object Notation (JSON) Patch»](https://www.rfc-editor.org/rfc/rfc6902.html): las operaciones `op: replace` de los parches de 10.3.3.
- [RFC 2606, «Reserved Top Level DNS Names»](https://www.rfc-editor.org/rfc/rfc2606.html): `example.com` reservado para ejemplos.
- [GitLab, «Postmortem of database outage of January 31»](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): el informe público del caso de la apertura.

---

**Fin del curso.** Vuelve al [índice](README.md) o abre la [bitácora](bitacora.md) y escribe lo que quieres construir después.
