# Lección 9 — Escalar y actualizar, midiendo cada corte

Lunes, 8:57 de la mañana. A las 9:00 el equipo de operación hace su corte semanal y cuarenta personas van a abrir, casi a la vez, el reporte del `revisor`. El lunes pasado pasó algo parecido. A las 9:01 el tablero se puso lento; alguien subió las réplicas a mano, de tres a ocho, para «aguantar»; y se le olvidó bajarlas. A las 9:04 otra persona aplicó una corrección urgente, y durante unos segundos varios usuarios vieron un error en pantalla. Nadie sabe cuántos. Hoy el director de operación hace tres preguntas, y la reunión empieza en tres minutos: ¿cuántas réplicas necesita el servicio de verdad y quién decide cuándo sobran?, ¿cuántas peticiones se pierden cuando se actualiza?, y ¿qué pasa si se cae uno de los servidores del clúster? Tu respuesta de hace una semana a las tres era la misma: «debería estar bien».

Esa frase es el problema. En Kubernetes, «debería estar bien» se puede convertir en un número, y esta lección es el taller donde se hace. No es un cuento inventado para asustar. En 2019, un ingeniero llamado Phil Pearl contó en su blog que, al mover una API a un clúster de Kubernetes de Google detrás de un Ingress, sus pruebas recibían errores `502` de vez en cuando. Al buscar la causa encontró algo que casi nadie decía en ese momento: cuando un Pod se apaga, el aviso de apagado y el retiro de ese Pod de la lista de destinos de la red ocurren **al mismo tiempo**, no uno después del otro; el paso que saca al Pod de la lista no espera al paso que lo apaga. Lo que varía es cuánto tarda la noticia en llegar a cada balanceador: según Pearl, en un Ingress mucho y en un Service poco. Con esa carrera, una petición puede llegar a un Pod que ya está cerrando ([Phil Pearl, «Kubernetes' dirty endpoint secret and Ingress»](https://philpearl.github.io/post/k8s_ingress/), 26 de julio de 2019). Lo que hoy aprendes es cómo medir esa carrera en tu propio clúster, cómo cerrarla con unos pocos renglones, y cómo no creerle a una medición más de lo que merece.

Esta lección tiene tres partes. La primera enseña al clúster a **escalar solo**: un medidor de consumo (`metrics-server`), un autoescalador que usa una fórmula que vas a poder calcular a mano, y una regla de reparto para que las réplicas no se amontonen en un nodo. La segunda enseña a **actualizar y desalojar sin sorpresas**: una actualización medida con un sondeo propio, con y sin la pausa que cierra la carrera, el historial para volver atrás, y un presupuesto de interrupciones frente al mantenimiento de un nodo. La tercera **rompe un servidor a propósito** y mide cuánto dura el corte. Cada cifra que verás salió de correr el procedimiento, y cada cifra viene con lo que la limita.

**Tiempo:** 2 × 45 min de lectura y práctica; la corrida completa del guion toma bastante más (lo dice «Sobre las corridas»), porque las esperas son parte de lo que se enseña

**Qué construyes:** el `revisor` que sube y baja réplicas con la carga, repartido entre los dos nodos de trabajo, que se actualiza con un sondeo contando cada petición perdida y que sobrevive a un nodo apagado con una pérdida medida y explicada

**Qué aprendes:** por qué `metrics-server` tal cual no funciona en kind y qué cambia la bandera que lo arregla; la fórmula del `HorizontalPodAutoscaler`, su tolerancia del 10 % y la ventana que retrasa la bajada; por qué un Deployment gestionado por un autoescalador no lleva `replicas`; el reparto entre nodos con `topologySpreadConstraints` y por qué el nodo de control exige `nodeTaintsPolicy: Honor`; `RollingUpdate` con `maxSurge` y `maxUnavailable`; la carrera entre el apagado y los destinos del Service, y el `preStop` que la cierra; `rollout history` y `rollout undo`, y por qué `rollout status` puede terminar mientras los Pods viejos todavía contestan; el `PodDisruptionBudget` y un `drain` que se atora a propósito; y la ventana de un nodo caído, con lo que la acorta y lo que no

**De dónde vienes.** De la [Lección 8](08-datos-y-tareas.md): el `revisor` vive en su propio espacio de nombres, `revisor`, con la red cerrada de la [Lección 7](07-aislar-permisos-red.md), un volumen para sus reportes y una tarea programada. De la [Lección 5](05-salud-recursos-apagado.md) traes lo que hoy se vuelve cálculo: los `requests` de CPU (`50m`), que son la vara con la que el autoescalador mide el porcentaje, y el plazo de apagado, que hoy se afina con una pausa antes de la señal de terminar. De la [Lección 6](06-entrar-al-cluster.md) traes la plataforma: MetalLB y Envoy Gateway ya instalados, con el orden «plataforma, espera, proyecto» que hoy se repite en un solo guion. Y de la [Lección 3](03-services-dns.md), el Pod `depurar` y el hábito de mirar `ENDPOINTS` antes de culpar a nadie.

**Qué no hace esta lección.** No escala **nodos**: en kind los tres nodos son contenedores fijos, y agregar o quitar máquinas es trabajo de otra pieza que un clúster real trae y este laboratorio no. No escala en vertical (darle más CPU a cada réplica) ni con métricas propias (peticiones por segundo, tamaño de una cola). No hace actualizaciones azul-verde ni canarias: la única estrategia aquí es la gradual que trae Kubernetes. No pone cifrado. Y no es una prueba de carga seria: la carga de la lección es un Job de `curl` en bucle, suficiente para ver al autoescalador reaccionar y nada más. La [Lección 10](10-proyecto-final.md) junta todo en dos comandos y lista lo que le falta a esto para ser producción.

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1, la imagen de nodo `kindest/node:v1.37.0` fijada por su huella (Kubernetes v1.37.0), **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** y **`metrics-server` v0.9.0**, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l9`. La máquina fue una Mac con procesador ARM y Docker Engine 29.2.1 dentro de una máquina virtual Linux (Colima) con 6 CPU y 16 GiB de memoria, **no** Linux Mint, que es el sistema de referencia del curso. Y estaba **compartida**: mientras corría esta lección corrían, en la misma máquina, otras lecciones del curso con sus propios clústeres, y la carga del sistema (el promedio que muestra `uptime`) pasó de menos de 5 a más de 40 durante el trabajo. Eso importa para leer dos tipos de cifras: los **tiempos** (descargar las imágenes de MetalLB tardó, en intentos anteriores, varios minutos por nodo, y `preparar.sh` lleva esperas largas por eso) y los **conteos de peticiones** de 9.9 y 9.12, que dependen de cuánta CPU recibió el cliente del sondeo. Cada sección dice qué cifra depende de qué. Lo que cambia en tu Mint: la arquitectura (`amd64` en lugar de `arm64`), las IP de los Pods, de los Services y de los nodos, los sufijos de los nombres, las edades, el nodo donde cae cada réplica y, sobre todo, las cifras de peticiones: son tuyas, no se comparan con las de aquí. Hay además una diferencia de red que conviene decir. **La corrida de esta lección usó una red de Docker propia**, `curso-k8s-red-l9`, con la subred `172.29.0.0/16`, para poder correr al mismo tiempo que otras lecciones que también instalan MetalLB sin pisarse; por eso las IP de los nodos salen en `172.29.0.x` y la puerta del Gateway en `172.29.255.200`. En tu máquina, con la red `kind` normal, las IP salen en `172.18.0.x` y la puerta en `172.18.255.200`, que es lo que `preparar.sh` hace por omisión. `correr.sh` hace lo mismo si lo corres con `RED=kind SUBRED=172.18.0.0/16` (son sus valores por omisión) y se detiene antes de crear nada si la red no tiene la subred esperada. El recorrido completo está en [`programas/09-escalar-y-actualizar/`](../programas/09-escalar-y-actualizar): `correr.sh` crea el clúster, le carga las tres imágenes, lo deja en el estado de la Lección 8 con `preparar.sh`, recorre la lección en orden y lo borra. Su salida es `correr.salida.txt`. La corrida completa tardó 1,809 segundos (30 minutos con 9 segundos): crear el clúster y esperar a que estuviera listo, 37 segundos; `preparar.sh`, 343; borrar el clúster, 2; el resto son las esperas que la lección enseña a hacer (la carga y la bajada del autoescalador, los siete sondeos de actualización, el nodo apagado). La imagen que no existe de 9.10.4 se corre aparte, con `fig09_02.imagen-rota.sh` (su salida es `fig09_02.imagen-rota.salida.txt`), en un clúster propio y mínimo que tarda unos cuatro minutos. Necesita internet: los manifiestos de `metrics-server`, MetalLB y Envoy Gateway se descargan de sus lanzamientos, fijados a su versión, y sus imágenes se descargan la primera vez.

## Al terminar vas a poder

- Explicar por qué `metrics-server` no arranca tal cual en kind, leer el `x509` de su bitácora, aplicar la bandera que lo arregla y decir por qué esa bandera es solo de laboratorio.
- Calcular a mano cuántas réplicas pedirá un `HorizontalPodAutoscaler` a partir de las réplicas actuales, el porcentaje de CPU medido y la meta, aplicando la tolerancia del 10 %, y comprobarlo contra la columna `TARGETS`.
- Escribir un `HorizontalPodAutoscaler` con piso, techo y ventana de bajada, y explicar por qué el Deployment que gobierna ya no declara `replicas`.
- Repartir las réplicas entre los nodos con `topologySpreadConstraints`, y explicar `maxSkew`, `DoNotSchedule`, `nodeTaintsPolicy: Honor` y `matchLabelKeys`.
- Medir con un sondeo cuántas peticiones fallan durante una actualización, con y sin `preStop`, y decir qué prueba esa medición y qué no.
- Usar `rollout history` y `rollout undo`, mirar `deletionTimestamp` antes de concluir que una vuelta atrás no funcionó, y leer una actualización con una imagen que no existe (`ErrImagePull`), comprobando que el servicio no se interrumpe.
- Provocar un `drain` bloqueado por un `PodDisruptionBudget` demasiado estricto, leerlo y corregirlo; apagar un nodo, medir la ventana de falla y explicar qué la acorta y qué no.

## El porqué antes del cómo

Hasta ahora, el número de réplicas del `revisor` lo decidías tú, escrito en un archivo. Es una buena decisión para aprender, y una mala para un lunes a las 9:00. Si la carga se triplica, nadie está escribiendo en ese archivo. Y si la carga baja, tres réplicas siguen comiendo CPU y memoria que otros Pods podrían usar. La primera pregunta de la lección es, entonces, **¿quién decide cuántas réplicas hacen falta, con qué información y con qué freno?** La respuesta tiene tres piezas. Un medidor, `metrics-server`, que mira cuánta CPU y memoria usa cada Pod. Un controlador, el `HorizontalPodAutoscaler` (HPA), que compara lo medido con una meta y ajusta el número de réplicas. Y una regla de reparto, para que las réplicas nuevas no caigan todas en la misma máquina, porque tres réplicas en un solo nodo se caen juntas con ese nodo.

La segunda pregunta es **¿qué le pasa al tráfico mientras algo cambia?** Cambian muchas cosas en un clúster vivo: una versión nueva, un nodo que se va a mantenimiento, un nodo que se cae sin avisar. Cada una tiene una respuesta distinta, y la diferencia importa. Una actualización se *planea*: Kubernetes puede ir cambiando réplicas de una en una y esperar a que la nueva esté lista. Un mantenimiento se *negocia*: puedes decirle al clúster cuántas réplicas tienen que seguir en pie, y el clúster respeta ese número al desalojar. Una caída *sorprende*: nadie pidió permiso y el clúster tarda en enterarse. La lección usa los tres casos como excusa para medir. Mide, no adivines, porque cada una de las tres respuestas es un número que cambia con la configuración, y ese número es la respuesta al director.

Y hay una tercera pregunta, más incómoda: **¿cómo se mide el corte sin engañarte?** Un sondeo que manda unas cuantas peticiones y no ve ninguna falla no demuestra que no hay fallas; demuestra que *esa vez, con ese ritmo*, no se vieron. La lección lo dice cada vez que mide algo, y repite las mediciones donde cuesta poco. Es el hábito que separa un reporte de una anécdota.

La lección tiene diez partes de conceptos y después las secciones de siempre:

1. **El clúster y el punto de partida** (9.1): el estado con el que termina la Lección 8, levantado con un guion.
2. **Medir antes de escalar** (9.2): `metrics-server`, la bandera y por qué.
3. **El autoescalador y su fórmula** (9.3): `HorizontalPodAutoscaler`, tolerancia, ventana y por qué sale `replicas` del Deployment.
4. **Repartir las réplicas** (9.4): `topologySpreadConstraints`.
5. **Aplicar los cambios** (9.5): lo que muestra `kubectl diff` y el desorden de réplicas que se esconde ahí.
6. **Con carga, el autoescalador sube** (9.6).
7. **Sin carga, baja, después de la ventana** (9.7).
8. **Quién manda sobre las réplicas** (9.8).
9. **Actualizar y medir el corte** (9.9), con el sondeo, el `preStop` y la vuelta atrás (9.10).
10. **Mantenimiento y caída de un nodo** (9.11 y 9.12): `PodDisruptionBudget`, `drain` y un nodo apagado.

Este es el destino. Al final de 9.6, con carga, el autoescalador ya cambió el número de réplicas y lo muestra en una sola línea:

```text
$ kubectl get hpa revisor -n revisor --no-headers
revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

Es un renglón de la corrida (el último de la espera de 9.6): el HPA `revisor`, que gobierna al Deployment `revisor`, mide `38 %` contra una meta de `50 %`, tiene un piso de 2 réplicas, un techo de 6 y hoy lleva 4.

## Si no traes la imagen del curso de Docker

Esta lección usa tres imágenes locales: `curso-docker-revisor:1.6.0`, la del `revisor` de la Lección 2; `curso-docker-prueba:1.0.0`, la del servicio que falla a propósito; y una nueva, `curso-docker-revisor:1.6.1`, que sirve para que la actualización de la lección tenga algo que actualizar. Las dos del `revisor` salen del mismo `Dockerfile` y del mismo código: lo único que cambia es la versión que el servicio dice en su `/salud` (`"version":"1.6.0"` o `"version":"1.6.1"`), y eso es justo lo que permite ver, petición por petición, qué réplica contestó. Comprueba que las tienes:

```text
$ docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E '^curso-docker-(revisor|prueba):'
curso-docker-revisor:1.6.1 61c70431badb
curso-docker-prueba:1.0.0 400d3fd59edc
curso-docker-revisor:1.6.0 bd1b2e7d91b8
```

(Esta salida es de la máquina del autor y no está en `correr.salida.txt`. Los identificadores salen de ella; en la tuya pueden ser otros si construiste las imágenes por tu cuenta. Lo que importa es que existan las tres etiquetas.) Si te falta la `1.6.1`, constrúyela igual que la `1.6.0`, desde el repositorio del curso de Docker, con el `Dockerfile` de su Lección 10 sobre la carpeta `programas/revisor` y con `--build-arg VERSION=1.6.1`, etiquetándola exactamente `curso-docker-revisor:1.6.1`. Es una imagen de laboratorio: sirve para ver una actualización, no es una versión nueva del servicio.

## Los conceptos

### 9.1 El clúster y el punto de partida

#### 9.1.1 Una regla de convivencia, otra vez

Esta lección instala MetalLB (a través de `preparar.sh`, 9.1.3), y la regla de la Lección 6 sigue en pie: dos clústeres con MetalLB y el mismo rango de direcciones, en la misma red de Docker, se pisan. Antes de crear el tuyo, comprueba la red `kind` y que nadie conteste ya en la primera dirección del rango:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar en 172.18.255.200. Si este curl responde, hay otro
# clúster con MetalLB vivo: espera a que termine.
# Si imprime un número (200, 404…), alguien contesta; si imprime 000, nadie.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -o /dev/null -w '%{http_code}\n' -m 3 http://172.18.255.200/
kind get clusters
```

Si la red `kind` todavía no existe porque nunca has creado un clúster, crea el clúster y comprueba la red justo después. Hay además un detalle de laboratorio que conviene decir desde ya, porque cambia las direcciones que verás en las salidas: la corrida de esta lección usó **una red de Docker propia**, `curso-k8s-red-l9`, con la subred `172.29.0.0/16`, para poder correr al mismo tiempo que otras lecciones que también instalan MetalLB. En tu máquina, con la red `kind` normal, las direcciones del rango salen en `172.18.255.x`, no en `172.29.255.x`; el guion `correr.sh` se adapta con dos variables, `RED` y `SUBRED`, y trae el freno de siempre: si la red no tiene la subred esperada, se detiene antes de crear nada.

#### 9.1.2 Crear el clúster y cargar las imágenes

Desde la raíz del repositorio del curso:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l9.XXXX)/kubeconfig"
# curso-k8s-l9 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l9 --config programas/09-escalar-y-actualizar/kind-curso.yaml
# Debe decir kind-curso-k8s-l9. Si dice otra cosa, no sigas.
kubectl config current-context
# La guarda de siempre, con el nombre de este clúster. Va delante de cada
# comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-revisor:1.6.1 curso-docker-prueba:1.0.0 --name curso-k8s-l9
cd programas/09-escalar-y-actualizar
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

La función `ctx` compara el contexto activo con el esperado; si coincide, no imprime nada, y si no, escribe «contexto equivocado: no sigo» y devuelve un error que corta la cadena `&&`. En esta lección va delante de cada comando que **cambia** algo (`apply`, `patch`, `scale`, `drain`, `delete`); en las salidas que siguen se omite para que quepan, pero en tu terminal va. Los comandos que solo **leen** (`get`, `top`, `describe`) no la necesitan, aunque no estorba. `correr.sh` hace la comprobación antes de cada comando de otra forma, con una función que se detiene sola.

El `(umask 077; …)` hace que `token.txt` nazca `-rw-------`: la máscara `077` le quita todos los permisos al grupo y a los demás, y los paréntesis hacen que el cambio valga solo para ese comando. Es el cuidado de las Lecciones 4 a 6, y se repite porque un hábito que se omite una vez ya no es un hábito.

```text
$ kind create cluster --name curso-k8s-l9 --config kind-curso.yaml
(crear el clúster y esperar a que estuviera listo tardó 37 s)

$ kubectl config current-context
kind-curso-k8s-l9

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l9-control-plane  Ready   v1.37.0  172.29.0.2
curso-k8s-l9-worker         Ready   v1.37.0  172.29.0.4
curso-k8s-l9-worker2        Ready   v1.37.0  172.29.0.3
```

Crear el clúster y esperar a que sus nodos y los Pods de `kube-system` estuvieran listos tardó 37 segundos, con la imagen del nodo ya descargada de antes. Son tres nodos `Ready` en `v1.37.0`: un nodo de control y dos de trabajo. La columna `INTERNAL-IP` es la dirección de cada nodo en la red de Docker; aquí cae en `172.29.0.x` por la red propia de la corrida, y en tu máquina caerá en `172.18.0.x`. Cargar las tres imágenes con `kind load` imprime sus renglones de siempre (`not yet present on node … loading...`); `correr.sh` los silencia y en su lugar anota que quedaron cargadas.

#### 9.1.3 El punto de partida: `preparar.sh`

La Lección 8 termina con un clúster que ya trae la plataforma de la Lección 6 y el proyecto de la Lección 8. Para no repetir unos minutos de instalación a mano, `preparar.sh` los rehace con los **tres pasos de la Lección 6, a la vista y en el mismo orden**: la plataforma (MetalLB y Envoy Gateway), la espera con `kubectl wait` hasta que estén listos, y por último el rango de direcciones, la clase de puerta y el proyecto de la carpeta `punto-de-partida/`. Si vienes de la Lección 8 con tu clúster vivo, no lo necesitas; si empiezas aquí, o si ya lo borraste, lo corres:

```bash
ctx && ./preparar.sh
```

Es un **programa**: `preparar.sh`. Léelo antes de correrlo: no esconde nada. Cada paso comprueba el contexto, imprime el comando que va a correr y se detiene si falla. Acepta una variable, `POOL_RANGO`, para cambiar el rango de MetalLB si tu red no es la `172.18.0.0/16`. Una nota sobre el ancho: `infra/metallb-pool.yaml` y `preparar.sh` traen `.200-.220`, mientras que `correr.sh` calcula `.200-.250`, que es el que se ve abajo. Aquí no importa, porque solo se usa la primera dirección del rango, la del Gateway.

```text
$ POOL_RANGO=172.29.255.200-172.29.255.250 ./preparar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb >/dev/null

$ kubectl apply --server-side -k infra/envoy-gateway >/dev/null

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=1200s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=1200s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=1200s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f /tmp/curso-k8s-l9.wJDg/metallb-pool.Xbdv -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k punto-de-partida >/dev/null

$ kubectl rollout status deployment/revisor deployment/prueba -n revisor --timeout=600s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=1200s
gateway.gateway.networking.k8s.io/revisor condition met
(preparar.sh tardó 343 s)
```

Se lee en tres tiempos, los mismos de la Lección 6. En el **paso 1** se aplican la plataforma de MetalLB y la de Envoy Gateway; sus salidas se mandan a `/dev/null` porque son decenas de renglones sin interés. En el **paso 2** vienen las esperas, todas con `kubectl wait` o `rollout status` y todas con plazo: los tipos nuevos de MetalLB (`condition met`), el controlador, un `speaker` listo en cada uno de los tres nodos, los tipos de Gateway API, el controlador de Envoy Gateway. En el **paso 3** se aplica el rango de direcciones (un archivo temporal que `preparar.sh` generó a partir de `infra/metallb-pool.yaml` con el rango de la red propia: es el efecto de `POOL_RANGO`), la clase de puerta `eg`, y por fin el proyecto de `punto-de-partida/`, con su `rollout status` y la espera de que el Gateway esté `Programmed`. Todo tardó 343 segundos; la mayor parte, esperando las descargas de imágenes. Este es el punto de partida de la lección:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           22s
deployment.apps/revisor   3/3     3            3           22s

$ kubectl get gateway -n revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.29.255.200   True         22s

$ docker run --rm --network curso-k8s-red-l9 --name curso-k8s-l9-cliente curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 5 http://172.29.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

Tres réplicas del `revisor`, la del servicio de prueba, ningún HPA ni PDB todavía (el último `get` no los lista porque no existen), y un Gateway `PROGRAMMED True` en la primera dirección del rango. El último comando es el cliente «de fuera» de la Lección 6, un contenedor de `curl` conectado a la red de Docker, pidiendo `/salud` por la puerta: `{"estado":"vivo","version":"1.6.0"}`. Si eso contesta, la plataforma y el proyecto están en pie.

### 9.2 Medir antes de escalar: `metrics-server`

#### 9.2.1 Lo que el clúster todavía no sabe

Antes de decidir cuántas réplicas hacen falta, hay que saber cuánta CPU usan las que existen. El clúster no lo sabe de fábrica. Si se lo preguntas con `kubectl top`, el comando que muestra consumo:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]
```

`error: Metrics API not available`: «la API de métricas no está disponible». La frase tiene un sujeto exacto. Kubernetes define una API para el consumo de CPU y memoria de nodos y Pods, la **Metrics API**, y la documentación la describe así: ofrece «un conjunto básico de métricas para soportar el escalado automático y casos parecidos» ([Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)). Pero esa API es solo una *forma* de preguntar: alguien tiene que contestar. La misma página lo dice sin adornos: hay que desplegar `metrics-server` «o un adaptador alternativo» para poder usarla, y su papel principal es «alimentar con métricas de uso de recursos a los componentes de autoescalado». Un clúster recién creado no lo trae, y por eso `top` no tiene a quién preguntarle.

¿Cómo se enchufa un contestador a la API de Kubernetes? Con un objeto que ya conoces de la Lección 6, por parentesco: un recurso que le enseña algo nuevo al `kube-apiserver`. Aquí no es un CRD sino un `APIService`, que le dice al `kube-apiserver`: «las preguntas que lleguen a `/apis/metrics.k8s.io/v1beta1` no las contestes tú; reenvíalas a este Service». Antes de instalar nada, ese objeto no existe:

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
Error from server (NotFound): apiservices.apiregistration.k8s.io "v1beta1.metrics.k8s.io" not found
[código de salida: 1]
```

Con `NotFound`: el `kube-apiserver` no tiene a quién reenviar. Es la misma situación de la Lección 6 con `Gateway`, vista desde otro lado: antes de que exista la pieza, preguntar por ella es preguntar al vacío.

#### 9.2.2 Instalar `metrics-server` tal cual viene

El proyecto publica un manifiesto por versión. La que usa esta lección es la **v0.9.0**, y se fija en la URL, como se fijó todo lo demás en el curso: sin versión fija, el día que cambie la última versión, tu laboratorio cambia sin avisarte. Se aplica tal cual, sin cambiar nada, para ver qué pasa:

```text
$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml | tail -3
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
(espera visible: hasta 600 s a que metrics-server descargue su imagen, arranque e intente leer a los kubelet)
```

Los tres renglones que se ven son los últimos de varios (`| tail -3`): un `Service`, un `Deployment` y el `APIService` que conecta a ambos con el `kube-apiserver`. Sobre el momento de mirar: el Deployment no queda listo al instante. Primero tiene que descargar su imagen y arrancar, y después intentar su primera lectura. El guion espera, a la vista, hasta que la bitácora del Pod muestre el error que se quiere leer (hasta 600 segundos, porque en una máquina lenta la descarga tarda). En tu terminal, puedes repetir `kubectl get deployment metrics-server -n kube-system` hasta que veas `0/1` con unos segundos de edad. Es una espera de otro tipo que `kubectl wait`: aquí no se espera a que *llegue* una condición, se espera para *darle tiempo a fallar* y poder leer cómo.

```text
$ kubectl get deployment metrics-server -n kube-system
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   0/1     1            0           30s
```

`READY 0/1` y `AVAILABLE 0`: el Pod existe pero no está listo. Se sigue el orden de la Lección 5, que dice qué mirar primero cuando algo no arranca: la bitácora del Pod.

```text
$ kubectl logs -n kube-system deployment/metrics-server --tail=200 | grep -E 'x509|tls|certificate' | tail -1
E1021 23:14:05.707527       1 scraper.go:149] "Failed to scrape node" err="Get \"https://172.29.0.2:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs" node="curso-k8s-l9-control-plane"
```

Se lee de izquierda a derecha. `E1021` es una línea de nivel *error* del 21 de octubre. `scraper.go:149` es el lugar del código que falló, y `Failed to scrape node` dice qué intentaba hacer: «raspar» (recoger) las métricas del nodo, que es lo que hace `metrics-server` cada pocos segundos, preguntándole a cada `kubelet` por la CPU y la memoria que usan sus Pods. La dirección es `https://172.29.0.2:10250/metrics/resource`: el `kubelet` de ese nodo (el de control; en tu máquina será `172.18.0.x`), por su IP, en el puerto 10250. Y la causa, al final: `tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs`.

Hay que desarmar esa frase. TLS es el cifrado con el que `metrics-server` le habla al `kubelet` (HTTPS). Para que el cifrado valga, `metrics-server` verifica el **certificado** que el `kubelet` le presenta: comprueba que lo firmó una autoridad en la que confía y que el certificado dice ser de la dirección a la que se conectó. Un certificado lleva una lista de nombres y direcciones válidas, los *Subject Alternative Names* (SAN). Aquí el certificado del `kubelet` no trae ninguna **IP** en esa lista, y `metrics-server` se conectó por IP: por eso no puede validar que «`172.29.0.2`» sea quien dice ser. Lo que la bitácora demuestra es solo eso: el certificado no trae ninguna IP. El README de `metrics-server` pone como requisito que el certificado del `kubelet` esté firmado por la autoridad del clúster ([metrics-server](https://github.com/kubernetes-sigs/metrics-server)), y en kind los nodos no lo cumplen tal cual. En un clúster real, eso se arregla en los nodos; en este laboratorio no se intenta.

Con el Pod sin listo, el `Service` de `metrics-server` no tiene destinos, y el `APIService` lo refleja:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]

$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE                  AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   False (MissingEndpoints)   30s
```

`AVAILABLE False (MissingEndpoints)`: «faltan destinos». El Service no tiene a quién mandar las preguntas porque el único Pod no está listo. Ahora el error de `kubectl top` tiene su cadena completa: el comando pregunta al `kube-apiserver`; este reenvía al Service; el Service no tiene destinos; el único destino no está listo; y no está listo porque no puede verificar el certificado del `kubelet`. Cinco eslabones, y el mensaje de arriba solo mostraba el último. Es el mismo oficio de la Lección 3: se baja de piso en piso hasta encontrar el que falla.

#### 9.2.3 La bandera, y por qué solo es de laboratorio

`metrics-server` tiene una opción para no verificar el certificado de los `kubelet`: `--kubelet-insecure-tls`. Su README la describe en dos frases cortas que conviene leer despacio: «Do not verify the CA of serving certificates presented by Kubelets. For testing purposes only» («No verifica la autoridad de los certificados que presentan los kubelet. Solo para pruebas»). No es una forma de decirlo para quedar bien: es una advertencia, y la lección la respeta. Esta bandera vale en un laboratorio donde los nodos son contenedores tuyos en tu máquina, y no vale en un clúster donde alguien más podría ponerse en la red entre `metrics-server` y un nodo, porque sin verificar el certificado no hay forma de saber con quién se está hablando.

El manifiesto de la v0.9.0 no trae la bandera; se le agrega con una *parcha* de Kustomize. Es un **programa**: `metrics-server/kustomization.yaml`.

```yaml
# metrics-server — Lección 9. Versión fijada (v0.9.0). En kind, el certificado de
# cada kubelet no trae ninguna IP y metrics-server no lo acepta sin
# --kubelet-insecure-tls. Eso SOLO vale en un clúster de laboratorio.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
patches:
- target:
    kind: Deployment
    name: metrics-server
    namespace: kube-system
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --kubelet-insecure-tls
```

La parcha dice: en el Deployment `metrics-server` del espacio `kube-system`, agrega al final de la lista de argumentos del primer contenedor, `--kubelet-insecure-tls`. El `op: add` con `args/-` es la forma de «agregar al final» de una lista en una parcha de tipo JSON. Se aplica con `-k`, como todo lo demás:

```text
$ kubectl apply -k metrics-server | tail -3
service/metrics-server unchanged
deployment.apps/metrics-server configured
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io unchanged
```

Dos objetos `unchanged` (el Service y el APIService no cambian) y uno `configured`: el Deployment. Cambió su plantilla, así que habrá un reemplazo del Pod, y esta vez la espera sí es de condición:

```text
$ kubectl rollout status deployment/metrics-server -n kube-system --timeout=600s
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
deployment "metrics-server" successfully rolled out
(espera de 45 s: metrics-server mide en ventanas y necesita un par de ellas)
```

Después viene una pausa que no es de condición y conviene decirlo: `metrics-server` mide por ventanas de tiempo y necesita un par de ellas antes de poder contestar con datos, así que la lección espera 45 segundos de reloj. En vez de adivinar, hay una forma de comprobar que ya contesta: preguntar por el `APIService`, que debe pasar a `True`.

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        98s
```

`AVAILABLE True`. Ahora `top` tiene a quién preguntar:

```text
$ kubectl top nodes
NAME                         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
curso-k8s-l9-control-plane   139m         2%       974Mi           6%          
curso-k8s-l9-worker          92m          1%       272Mi           1%          
curso-k8s-l9-worker2         53m          0%       316Mi           1%          

$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-cgzkw    1m           1Mi             
revisor-67b97d67c9-fnpdj   1m           1Mi             
revisor-67b97d67c9-jfdw4   1m           1Mi             
revisor-67b97d67c9-tqffn   1m           1Mi             
```

La columna `CPU(cores)` está en **milicores**: `1m` es una milésima de un núcleo, la misma unidad de los `requests` de la Lección 5. La documentación explica de dónde sale: la CPU se reporta «como el uso promedio de núcleos», calculado «como una tasa sobre un contador acumulado de CPU que da el núcleo» de Linux, en una ventana de tiempo que la propia API informa (campo `window`). No es una foto de un instante, es un promedio de una ventana corta. Y `CPU(%)` en `top nodes` es el porcentaje de la CPU **del nodo**, no del `request` de nadie; eso es otra cuenta, y la que importa al autoescalador es la que sigue. Mira los Pods del `revisor`: algunas décimas de milicore o unos cuantos milicores de uso, contra los `50m` que pidieron:

```text
$ kubectl describe pod -n revisor -l app=revisor | grep -E 'Requests|cpu:' | head -4
      cpu:     200m
    Requests:
      cpu:      50m
      cpu:     200m
```

(El primer `cpu: 200m` es el `limit`; el `Requests` y su `cpu: 50m`, el piso. El tercero es el `limit` del otro contenedor listado; el filtro `head -4` corta la salida donde cabe.) Un Pod que usa `4m` de `50m` está al 8 % de lo que pidió. Ese porcentaje, el de **uso contra `requests`**, es la vara del autoescalador.

La documentación de `metrics-server` también dice para qué **no** sirve, y vale oírlo antes de confiar: sus casos de uso son el escalado horizontal por CPU y memoria, y su README advierte que no es «una fuente exacta del uso de recursos». Para mirar el consumo con precisión, para graficarlo o para alertar, existen otras herramientas. Para decidir cuántas réplicas, basta.

### 9.3 El autoescalador y su fórmula

#### 9.3.1 Qué es y cada cuánto mira

El `HorizontalPodAutoscaler` es un controlador, uno más de los que viste en la Lección 0 haciendo lo mismo de siempre: comparar el estado deseado con el real y empujar el segundo hacia el primero. La diferencia es qué entiende por «estado deseado»: no un número de réplicas, sino una **meta de consumo**. «Horizontal» quiere decir que cambia el *número* de réplicas, no el tamaño de cada una. La documentación dice que el bucle corre cada 15 segundos por omisión (`--horizontal-pod-autoscaler-sync-period`) ([Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)).

En cada vuelta hace tres cosas: lee las métricas de los Pods del objetivo, calcula cuántas réplicas pediría, y, si el resultado cambia el número actual, se lo pide al Deployment. La parte que se puede calcular a mano es la segunda, y es esta:

```text
réplicas deseadas = ceil( réplicas actuales × (métrica actual ÷ métrica deseada) )
```

Es la fórmula que da la documentación: `desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]`. `ceil` es «redondear hacia arriba». Con una meta de CPU del 50 %: si hay 2 réplicas y el promedio de uso es del 100 % de lo que pidieron, la cuenta es `ceil(2 × 100 ÷ 50) = ceil(4) = 4`. Si el uso promedio es del 25 %, `ceil(2 × 25 ÷ 50) = ceil(1) = 1`. El redondeo hacia arriba tiene una razón: es preferible un Pod de más que uno de menos cuando la meta queda a punto de rebasarse.

¿Y el «porcentaje»? Con una meta de tipo `Utilization`, el controlador calcula el uso «como un porcentaje de la solicitud (`request`) equivalente de los contenedores de cada Pod», y toma el promedio de todos los Pods objetivo. Por eso un Pod sin `requests` de CPU es un Pod que el autoescalador no puede medir: la documentación dice que, si algún contenedor no tiene la solicitud, «la utilización de CPU del Pod no queda definida y el autoescalador no hará nada con esa métrica». La Lección 5 puso `requests` en todo contenedor «para que el planificador sepa dónde ponerlo»; hoy esa decisión sirve para una segunda cosa que entonces no se veía.

#### 9.3.2 La tolerancia del 10 %

Si el cálculo se aplicara tal cual, el autoescalador cambiaría el número de réplicas por diferencias de un punto porcentual, y el clúster estaría en perpetuo ajuste. Para evitarlo, el controlador se salta cualquier ajuste cuando la razón `métrica actual ÷ métrica deseada` está «suficientemente cerca de 1.0», y la documentación da la medida: una tolerancia de 0.1 por omisión, es decir, del 10 % (desde Kubernetes 1.37 cada HPA puede fijar su propia tolerancia en `behavior.scaleUp.tolerance` y `behavior.scaleDown.tolerance`; esta lección deja la del clúster, el 10 %). Con una meta de 50 %, hay ajuste solo si el uso medido cae fuera de 45 % a 55 %: la razón tiene que ser menor que 0.9 o mayor que 1.1.

Un ejemplo con números, para calcularlo a mano antes de ver el clúster. Con 3 réplicas y una meta del 50 %:

| Uso medido | Razón | ¿Fuera de 0.9 a 1.1? | `ceil(3 × razón)` | Qué hace |
|---|---|---|---|---|
| 54 % | 1.08 | no | — | nada |
| 57 % | 1.14 | sí | `ceil(3.42)` = 4 | sube a 4 |
| 40 % | 0.80 | sí | `ceil(2.4)` = 3 | no cambia (3), pero se anota la recomendación |
| 20 % | 0.40 | sí | `ceil(1.2)` = 2 | baja a 2 (si la ventana lo permite) |

Cuando el clúster te dé números, los comprobarás contra esta tabla.

#### 9.3.3 El manifiesto

Es un **programa**: `escalado.yaml`. Trae dos objetos, el autoescalador y un presupuesto de interrupciones que se explica en 9.11.

```yaml
# escalado.yaml — Lección 9: réplicas según la carga, con límites, y al menos
# una disponible durante un mantenimiento.
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: revisor
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: revisor
  minReplicas: 2
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: revisor
```

Se lee campo por campo:

- **`scaleTargetRef`**: a quién gobierna. Un `Deployment` llamado `revisor` del mismo espacio de nombres. El HPA no toca Pods: le pide al Deployment que cambie su número de réplicas, y el Deployment hace el resto, como siempre.
- **`minReplicas: 2` y `maxReplicas: 6`**: el piso y el techo. El piso es 2 por dos razones: con una sola réplica, cualquier reemplazo es un corte, y con dos (una en cada nodo de trabajo) la actualización de 9.9 y el mantenimiento de 9.11 se pueden hacer sin perder el servicio. El techo es 6 por el hábito de seguridad que cierra esta lección: un autoescalador sin techo convierte una avalancha de peticiones, o un error en un bucle, en una factura o en un nodo agotado.
- **`metrics`**: qué mide y contra qué. Un recurso, la CPU, con una meta de utilización promedio del 50 % *de los `requests`*. Es una meta intermedia a propósito: si fuera del 90 %, el autoescalador reaccionaría cuando el servicio ya está casi saturado.
- **`behavior.scaleDown.stabilizationWindowSeconds: 60`**: la ventana de bajada, que se explica a continuación.

El campo `behavior` merece un párrafo propio. Sin él, el HPA usa los valores por omisión de la documentación: para **subir**, una ventana de estabilización de 0 segundos y una política que permite sumar hasta 4 Pods o duplicar las réplicas cada 15 segundos, la que sea mayor; para **bajar**, una ventana de **300 segundos** (cinco minutos) y una política que permite quitar todas las réplicas sobrantes de golpe. La lección usa 60 segundos en lugar de 300 para que puedas ver la bajada sin esperar cinco minutos, y lo dice porque no es un valor para copiar: en producción, la ventana larga protege contra el vaivén («subo, bajo, subo, bajo») cuando la carga es irregular.

¿Qué hace la ventana, exactamente? La documentación lo explica con precisión: justo antes de escalar, el controlador anota la recomendación del momento, y luego «considera todas las recomendaciones dentro de la ventana configurada y elige la más alta». O sea: para **bajar**, el HPA no usa lo que ve ahora, sino el **máximo** de lo que recomendó en los últimos 60 segundos. Si hace 40 segundos recomendaba 4 réplicas y ahora recomienda 2, sigue en 4 hasta que esa recomendación de 4 salga de la ventana. Es una memoria deliberada de lo peor reciente, y es la razón por la que la bajada es lenta y la subida no.

Por último, el `kubectl diff` de 9.5 va a mostrar que el HPA, al aplicarse, trae escritos en la salida los valores por omisión de `scaleUp` y `scaleDown` (`selectPolicy: Max`, las políticas de 15 segundos): el servidor completa lo que no escribiste.

#### 9.3.4 Por qué el Deployment ya no lleva `replicas`

En la carpeta de la Lección 8, el Deployment del `revisor` decía `replicas: 3`. En la de hoy, ese campo no está. No es un descuido: es la recomendación explícita de la documentación del HPA. Cuando hay un autoescalador, el campo `spec.replicas` del Deployment debería quitarse del manifiesto, porque si no, «cada vez que se aplica un cambio a ese objeto, por ejemplo con `kubectl apply -f deployment.yaml`, Kubernetes escalará el número actual de Pods al valor de `spec.replicas`», lo que «puede ser problemático cuando un HPA está activo, y causar *vaivén*». Dos dueños de un mismo número se pelean: tu archivo dice 3, el HPA acaba de pedir 5, y cada `apply` desbarata lo que el otro hizo.

La documentación agrega un aviso que 9.5 va a hacer visible: quitar el campo «puede causar una degradación única del número de Pods, porque el valor por omisión de esa clave es 1». Es decir, al aplicar por primera vez el Deployment **sin** `replicas`, el clúster lo lee como «vuelve al valor por omisión» y propone bajar a una sola réplica. En 9.5 verás ese `replicas: 1` en el `kubectl diff`, y verás qué pasa luego.

### 9.4 Repartir las réplicas

#### 9.4.1 El problema: nada reparte por ti

Un autoescalador que sube a cuatro réplicas no dice dónde las pone; eso lo decide el planificador (*scheduler*), que busca el nodo que mejor encaje por recursos y otras reglas, y por omisión no se esfuerza en repartir. Mira cómo quedaron las tres réplicas de la carpeta de la Lección 8, sin ninguna regla de reparto:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>
```

La columna `NODE` dice dónde está cada una. En esta corrida, dos de las tres réplicas cayeron juntas en `curso-k8s-l9-worker2` y una en `curso-k8s-l9-worker`. No es mala suerte: en esta corrida y en tres anteriores que no se conservaron, dos de las tres réplicas cayeron juntas, unas veces en un nodo y otras en el otro. El planificador no promete repartir. Si el nodo con dos réplicas se cae, el servicio pierde el 67 % de su capacidad de un golpe, y el autoescalador no ayuda: su trabajo es mirar la CPU, no el reparto.

#### 9.4.2 `topologySpreadConstraints`

Kubernetes tiene una pieza para esto: las **restricciones de dispersión por topología**. «Topología» aquí quiere decir «en qué parte de la infraestructura vive cada cosa»: en qué nodo, en qué zona de una nube, en qué rack. La documentación define el vocabulario ([Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/)): una etiqueta de nodo, `topologyKey`, divide los nodos en **dominios**, y los nodos que tienen el mismo valor de esa etiqueta forman un mismo dominio. La etiqueta `kubernetes.io/hostname` tiene un valor distinto por nodo, así que con ella *cada nodo es su propio dominio*. Eso es lo que se quiere aquí: repartir entre nodos.

La restricción del `revisor` es esta. Es un fragmento del **programa** `revisor-deployment.yaml`, dentro de `spec.template.spec`:

```yaml
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        nodeTaintsPolicy: Honor
        labelSelector:
          matchLabels:
            app: revisor
        matchLabelKeys:
        - pod-template-hash
```

Cada campo, en orden:

- **`topologyKey: kubernetes.io/hostname`**: cada nodo es un dominio, como se dijo.
- **`labelSelector`**: qué Pods se cuentan en cada dominio. Los que tienen `app: revisor`; las réplicas de `prueba` o los Pods de carga no cuentan, ni estorban.
- **`maxSkew: 1`**: la **asimetría** (*skew*) máxima permitida: la diferencia entre el número de Pods de un dominio y el del dominio con menos. La documentación lo define así: con `DoNotSchedule`, `maxSkew` «es la diferencia máxima permitida entre el número de Pods coincidentes en el dominio objetivo y el *mínimo global*». Con `maxSkew: 1` y dos nodos de trabajo, 2 + 0 no se permite (diferencia de 2), 1 + 1 sí, 2 + 1 sí, 3 + 1 no.
- **`whenUnsatisfiable: DoNotSchedule`**: qué hacer si colocar el Pod rompe la restricción. `DoNotSchedule` (el valor por omisión) dice «no lo programes»: el Pod queda `Pending`. `ScheduleAnyway` dice «prográmalo igual, pero prefiriendo los lugares que reduzcan la asimetría»: es una preferencia, no una regla. Esta lección usa la regla dura, porque la suave deja pasar justo lo que se quiere evitar: la restricción es para que el reparto *sea cierto*, y una preferencia no lo garantiza.
- **`nodeTaintsPolicy: Honor`**: cómo tratar las *manchas* (*taints*) de los nodos al calcular la asimetría. Se explica en 9.4.3 y se comprueba en 9.5.4, porque es el campo que parece sobrar y no sobra.
- **`matchLabelKeys: [pod-template-hash]`**: restringe el conteo a las réplicas de la **misma versión**. El Deployment pone en cada Pod una etiqueta, `pod-template-hash`, con un valor distinto por cada versión de la plantilla. La documentación dice que esa etiqueta, que «agrega automáticamente el controlador del Deployment», sirve «para distinguir entre revisiones distintas de un mismo Deployment». Durante una actualización conviven réplicas viejas y nuevas; sin este campo, las viejas contarían para el reparto de las nuevas y estorbarían; con él, cada versión se reparte por su cuenta.

#### 9.4.3 Por qué el nodo de control exige `Honor`

El clúster tiene tres nodos y solo dos reciben réplicas. El nodo de control lleva una *mancha* (`node-role.kubernetes.io/control-plane:NoSchedule`) que impide programar Pods de usuario ahí. Pero ¿cuenta como dominio, para el cálculo del «mínimo global»? Depende de `nodeTaintsPolicy`. La documentación define las dos opciones: `Honor` incluye «los nodos sin manchas, junto con los nodos manchados para los cuales el Pod entrante tiene una tolerancia»; `Ignore` ignora las manchas y incluye a todos los nodos; y si el campo está vacío, el comportamiento equivale a `Ignore`.

Eso significa que, **sin** `Honor`, el nodo de control entra en la cuenta como un dominio con cero Pods, y el «mínimo global» es 0, porque ese nodo no puede recibir una réplica. Con ese cero fijo, `maxSkew: 1` permite como mucho 1 Pod por dominio: la tercera réplica no tendría dónde ir. Es el tipo de regla que funciona con dos réplicas y se rompe con la tercera, y por eso mismo es un error que se encuentra en producción un lunes a las 9:00. 9.5.4 lo provoca para que lo veas.

#### 9.4.4 Lo que la restricción no hace

La documentación de esta pieza trae una advertencia en su sección de limitaciones: «no hay garantía de que las restricciones se sigan cumpliendo cuando se quitan Pods. Por ejemplo, reducir un Deployment puede dejar los Pods desbalanceados», y recomienda herramientas como el *Descheduler* para rebalancear. La regla se aplica **al programar** un Pod nuevo, no antes ni después. 9.11 lo va a mostrar con un mantenimiento que deja las réplicas juntas, y mostrará también cómo se remedia sin instalar nada.

### 9.5 Aplicar los cambios

#### 9.5.1 Qué cambia, antes de aplicar

Con la carpeta de la Lección 9 lista, el primer paso no es aplicar sino preguntar qué va a cambiar. `kubectl diff -k .` manda al servidor el resultado del `-k` y muestra la diferencia contra lo que hay. El comando se filtra (`grep -E '^[+-] '`) para quedarse con los renglones que cambian y quitar el ruido de metadatos (`creationTimestamp`, `uid`, `resourceVersion`):

```text
$ kubectl diff -k . | grep -E '^[+-] ' | grep -v -E 'creationTimestamp|generation|resourceVersion|uid:|managedFields'
-  replicas: 3
+  replicas: 1
-      maxSurge: 25%
-      maxUnavailable: 25%
+      maxSurge: 1
+      maxUnavailable: 0
+        lifecycle:
+          preStop:
+            sleep:
+              seconds: 5
-      terminationGracePeriodSeconds: 10
+      terminationGracePeriodSeconds: 15
+      topologySpreadConstraints:
+      - labelSelector:
+          matchLabels:
+            app: revisor
+        matchLabelKeys:
+        - pod-template-hash
+        maxSkew: 1
+        nodeTaintsPolicy: Honor
+        topologyKey: kubernetes.io/hostname
+        whenUnsatisfiable: DoNotSchedule
+  name: revisor
+  namespace: revisor
+  behavior:
+    scaleDown:
+      policies:
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 60
+    scaleUp:
+      policies:
+      - periodSeconds: 15
+        type: Pods
+        value: 4
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 0
+  maxReplicas: 6
+  metrics:
+  - resource:
+      name: cpu
+      target:
+        averageUtilization: 50
+        type: Utilization
+    type: Resource
+  minReplicas: 2
+  scaleTargetRef:
+    apiVersion: apps/v1
+    kind: Deployment
+    name: revisor
+  currentMetrics: null
+  desiredReplicas: 0
+  name: revisor
+  namespace: revisor
+  minAvailable: 1
+  selector:
+    matchLabels:
+      app: revisor
+  currentHealthy: 0
+  desiredHealthy: 0
+  disruptionsAllowed: 0
+  expectedPods: 0
[código de salida: 1]
```

El código `1` al final no es un error: `kubectl diff` sale con 1 cuando **hay** diferencias, y con 0 cuando no las hay, para poder usarse en un guion. Se lee en tres bloques:

1. **`-  replicas: 3` / `+  replicas: 1`.** Lo anunciado en 9.3.4. El archivo ya no dice `replicas`, y el servidor, que trae su valor por omisión, propone **1**. Si aplicas esto sin pensar, el `revisor` pasa de tres réplicas a una, aunque sea un instante, antes de que el autoescalador lo corrija. Aquí no es grave; con 40 personas conectadas a las 9:00, sí lo sería. Es el costo único de entregar el control del número de réplicas, y conviene saberlo antes de pagarlo.
2. **`maxSurge: 25%` → `1` y `maxUnavailable: 25%` → `0`.** Los valores por omisión de la estrategia de actualización se vuelven explícitos. Se explican en 9.9.
3. **`lifecycle` / `preStop`, `terminationGracePeriodSeconds: 10` → `15` y `topologySpreadConstraints`.** La pausa antes de apagar, el plazo más largo que esa pausa necesita y el reparto de 9.4. Y debajo, los objetos nuevos: el HPA (con los valores por omisión escritos) y el PodDisruptionBudget.

#### 9.5.2 Aplicar y observar

```text
$ kubectl apply -k . | grep -E 'horizontalpod|poddisruption|deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
poddisruptionbudget.policy/revisor created
horizontalpodautoscaler.autoscaling/revisor created

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
(espera de 30 s: el HPA necesita su primera lectura de métricas)
```

Cuatro renglones: `deployment.apps/revisor configured`, el PDB y el HPA `created`, y `prueba unchanged` (lo que no cambió no se toca). El `rollout status` muestra el reemplazo de las réplicas, porque cambiaron la plantilla (el `preStop`, el plazo y el reparto) y por eso hay un reemplazo ordenado, de una en una, como en la Lección 2. Después hay una pausa de 30 segundos a la vista: el HPA necesita su primera lectura de métricas antes de mostrar un número.

```text
$ kubectl get hpa,pdb -n revisor
NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          32s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     32s
```

Lee la columna `TARGETS` del HPA: `cpu: 2%/50%` es «uso actual / meta». El uso es el promedio, sobre los `requests` de los Pods, que 9.2 explicó. `MINPODS 2` y `MAXPODS 6` son el piso y el techo, y `REPLICAS` es el número actual. En el PDB, `ALLOWED DISRUPTIONS` dice cuántos Pods se pueden perder voluntariamente ahora mismo; se explica en 9.11.

Un detalle de lectura: la primera vez que se aplica el HPA, si lo miras demasiado pronto, `TARGETS` dice `cpu: <unknown>/50%`. No es una falla: el controlador todavía no tiene una medición de los Pods nuevos. Los eventos del HPA, que se leen en 9.6, guardan el rastro de esos primeros segundos.

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-5xvt5   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-857qf   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.replicas}{"\n"}'
2
```

Dos réplicas, **una en cada nodo de trabajo**. El reparto se cumplió, y el número de réplicas lo puso el HPA: `.spec.replicas` vale 2, el piso. La cadena más probable, y la que el evento `Current number of replicas below Spec.MinReplicas` de 9.6 sugiere, fue: el `apply` dejó el Deployment en 1 (el valor por omisión), el HPA vio que 1 estaba por debajo del piso de 2 y lo subió, y el reemplazo repartió las dos réplicas por la restricción.

#### 9.5.3 La bitácora del HPA cuenta lo que hizo

El HPA deja sus decisiones en los eventos. Se lee con `describe`, que se mostrará completo en 9.6 después de la carga, y el primer renglón es el rastro de lo de arriba: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. «El número actual de réplicas está por debajo del mínimo»: el HPA no estaba reaccionando a la carga, sino aplicando el piso.

#### 9.5.4 El error: el reparto sin `nodeTaintsPolicy: Honor`

Ahora el error prometido en 9.4.3. Se provoca quitando solamente `nodeTaintsPolicy` del Deployment vivo, con una parcha, y pidiendo una tercera réplica a mano:

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/topologySpreadConstraints/0/nodeTaintsPolicy"}]'
deployment.apps/revisor patched

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running       0          6s    10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running       0          3s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5xvt5   1/1     Terminating   0          38s   10.244.2.8   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-857qf   1/1     Terminating   0          38s   10.244.1.8   curso-k8s-l9-worker    <none>           <none>
```

Con dos réplicas todo parece normal. Es lo que hace traicionero a este error: el defecto no se ve hasta que llega la tercera.

```text
$ kubectl scale deployment/revisor -n revisor --replicas=3
deployment.apps/revisor scaled
(espera de 6 s: el planificador decide en un instante)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running   0          12s   10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-4nwx5   0/1     Pending   0          6s    <none>       <none>                 <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running   0          9s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
```

La tercera réplica queda `Pending`, sin nodo asignado. Se sigue el orden de la Lección 5: el `describe` del Pod pendiente (el nombre cambia en tu corrida), sección de eventos.

```text
$ kubectl describe pod revisor-574b5b6c4c-4nwx5 -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  6s    default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match pod topology spread constraints. preemption: 0/3 nodes are available: 1 Preemption is not helpful for scheduling, 2 No preemption victims found for incoming pod.
```

Léelo: `0/3 nodes are available` dice que de los tres nodos, ninguno sirve. Y da el motivo de cada uno: un nodo tiene una mancha que el Pod no tolera (*untolerated taint*; es el de control), y los otros dos «no coinciden con las restricciones de dispersión por topología» (*didn't match pod topology spread constraints*). Es justo lo anunciado: el nodo de control cuenta como dominio con cero Pods, el mínimo global es 0, y poner la tercera réplica en cualquiera de los otros dos daría una asimetría de 2.

La corrección es volver a aplicar el archivo, que trae `Honor`:

```text
# --- La corrección: volver a aplicar la carpeta (trae Honor) ---

$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Terminating   0          18s   10.244.1.9    curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Terminating   0          15s   10.244.2.9    curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running       0          6s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-76td2   1/1     Running       0          2s    10.244.1.11   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running       0          4s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
(espera de 75 s: la ventana de bajada del autoescalador es de 60 s)
```

Con `Honor`, el nodo de control sale de la cuenta: tres réplicas en dos dominios, 2 + 1, asimetría de 1. Cabe. Y como `apply -k` no trae `replicas`, el número vive en el Deployment hasta que el HPA lo corrige: tras la ventana de bajada de 60 segundos (a la vista, 75 de espera), el HPA devuelve la cuenta a 2, que es lo que la carga pide.

```text
$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           4m11s
deployment.apps/revisor   2/2     2            2           4m11s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          2m5s

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          82s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          80s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

### 9.6 Con carga, el autoescalador sube

#### 9.6.1 Una carga que se puede apagar

Para ver al autoescalador trabajar hace falta carga, y la carga tiene que poder apagarse cuando tú quieras. Es un **programa**: `carga.yaml`.

```yaml
# carga.yaml — Lección 9: genera carga contra el revisor para ver subir el HPA.
# No forma parte del proyecto: se aplica con -f, se observa y se borra.
apiVersion: batch/v1
kind: Job
metadata:
  name: carga
  namespace: revisor
spec:
  parallelism: 4
  backoffLimit: 0
  activeDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app: carga
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
      - name: carga
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["sh", "-c", "while true; do curl -s -o /dev/null http://revisor/salud; done"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 200m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Es un `Job`, el objeto de la Lección 8 para tareas que terminan, con cuatro Pods en paralelo (`parallelism: 4`) que repiten sin parar una petición a `http://revisor/salud`. No hay pausa entre una y otra: cada Pod pide, recibe, y vuelve a pedir. Se lee por decisiones:

- **`activeDeadlineSeconds: 600`**: pase lo que pase, el Job se detiene a los 10 minutos: tiene que sobrevivir a la descarga de la imagen más los 200 segundos de observación. Un generador de carga sin freno es una avería en espera; este termina aunque te olvides de borrarlo.
- **`backoffLimit: 0`**: si un Pod falla, no se reintenta. Es una carga de laboratorio, no una tarea que importe.
- **`acceso-revisor: permitido`**: la etiqueta que la red cerrada de la Lección 7 exige para llegar al `revisor`. Sin ella, los Pods de carga no llegarían a ningún lado, y el HPA no vería ninguna carga. Es el mismo permiso del Pod `depurar`.
- **`limits: cpu: 200m`**: cada Pod de carga puede consumir hasta una quinta parte de un núcleo. Eso pone un **techo a la carga que se puede generar**: cuatro Pods de 200m son 800m en total, y cuánto de eso se convierte en CPU del `revisor` depende de cuántas peticiones por segundo alcanza a contestar. No es una prueba de rendimiento; es una palanca con tope.
- **La imagen de `curl`, fijada por su huella**, igual que en la Lección 3. La primera vez que un nodo la usa, la descarga de internet; por eso el guion espera (a la vista) a que los Pods de carga estén listos antes de empezar a mirar el reloj.

#### 9.6.2 Aplicar, esperar, mirar

```text
$ kubectl apply -f carga.yaml
job.batch/carga created
(espera visible: hasta 600 s a que los Pods de carga arranquen; la primera vez descargan la imagen de curl)
```

Después viene una espera con `kubectl wait`, por la razón de arriba: hasta que los Pods de carga están `Ready`, no hay carga, y mirar el HPA antes sería medir el silencio.

```text
$ kubectl wait --for=condition=Ready pod -l app=carga -n revisor --timeout=600s
pod/carga-29s8s condition met
pod/carga-bz6zl condition met
pod/carga-nv5tb condition met
pod/carga-rnhz5 condition met
```

Ahora el tiempo corre. El guion imprime una línea del HPA cada 20 segundos durante 200 segundos. En tu terminal, el equivalente es `kubectl get hpa revisor -n revisor --watch` (que imprime una línea nueva cada vez que cambia algo), o un bucle de `get` y `sleep 20` como el del guion. La espera es parte de la lección: el autoescalador no es instantáneo, y ver cuánto tarda es lo que se aprende.

```text
(un renglón del HPA cada 20 s, durante 200 s; empieza a las 17:18:00)
[+ 20s] revisor   Deployment/revisor   cpu: 27%/50%   2     6     2     2m50s
[+ 40s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     2     3m10s
[+ 60s] revisor   Deployment/revisor   cpu: 72%/50%   2     6     2     3m30s
[+ 80s] revisor   Deployment/revisor   cpu: 58%/50%   2     6     3     3m51s
[+100s] revisor   Deployment/revisor   cpu: 44%/50%   2     6     4     4m11s
[+120s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     4     4m31s
[+140s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     4m51s
[+160s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m11s
[+180s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m31s
[+200s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

Cada renglón se lee igual: el tiempo desde que empezó la carga, el nombre, el objetivo, la columna `TARGETS` (`uso actual / meta`), el piso, el techo, las réplicas y la edad del HPA. Hay que leerlos con la fórmula de 9.3 en la mano.

Los renglones, con la fórmula de 9.3 aplicada a cada uno:

| Tiempo | Uso medido | Réplicas | Razón (uso ÷ 50) | Cuenta | Qué hace |
|---|---|---|---|---|---|
| +20 s | 27 % | 2 | 0.54 | — | la carga apenas llega |
| +40 s | 46 % | 2 | 0.92 | dentro de 0.9 a 1.1 | nada: la tolerancia lo detiene |
| +60 s | 72 % | 2 | 1.44 | `ceil(2 × 1.44)` = `ceil(2.88)` = 3 | decide subir a 3 |
| +80 s | 58 % | 3 | 1.16 | `ceil(3 × 1.16)` = `ceil(3.48)` = 4 | decide subir a 4 |
| +100 s | 44 % | 4 | 0.88 | `ceil(4 × 0.88)` = `ceil(3.52)` = 4 | se queda en 4 |
| +120 s | 46 % | 4 | 0.92 | dentro de la tolerancia | nada |
| +140 a +200 s | 38 % | 4 | 0.76 | `ceil(4 × 0.76)` = `ceil(3.04)` = 4 | se queda en 4 |

Hay tres cosas que ver ahí. **Primera**: el renglón de +40 segundos, con 46 %, no hace nada aunque la carga ya está encima. No es lentitud, es la tolerancia: 46 % es un 8 % por debajo de la meta, dentro del 10 % que el controlador perdona. **Segunda**: a +60 s el uso es de 72 % con 2 réplicas y el autoescalador decide subir a 3; el renglón de +80 s ya muestra 3, porque entre un renglón y otro pasan 20 segundos y la decisión se tomó en el intervalo. El cambio de 3 a 4 está separado del primero por unos 30 segundos (los eventos de abajo dicen hace `2m37s` y hace `2m7s`), probablemente porque los Pods nuevos tienen que nacer y empezar a trabajar antes de que su consumo cuente. **Tercera**, y es la más instructiva: de +140 a +200 segundos el uso se queda en 38 % con 4 réplicas, una razón de 0.76 que está **fuera** de la tolerancia por debajo, y aun así el autoescalador no baja. La cuenta explica por qué: `ceil(4 × 0.76)` es `ceil(3.04)`, que es 4. El redondeo hacia arriba mantiene la cuarta réplica por cuatro centésimas. El sistema se estabilizó solo: cada réplica nueva repartió la carga, el promedio bajó de 72 a 38 %, y con ese promedio cuatro réplicas son el número que la fórmula quiere. El techo de 6 no se tocó.

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-4q7wh   1/1     Running   0          2m5s    10.244.2.13   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running   0          5m9s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-pchj4   1/1     Running   0          2m36s   10.244.1.14   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          5m7s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-4q7wh   18m          6Mi             
revisor-767bdf965b-5b6k9   19m          7Mi             
revisor-767bdf965b-pchj4   20m          7Mi             
revisor-767bdf965b-vcznx   20m          6Mi             
$ kubectl get hpa revisor -n revisor -o jsonpath='réplicas={.status.currentReplicas} deseadas={.status.desiredReplicas} cpu={.status.currentMetrics[0].resource.current.averageUtilization} % ({.status.currentMetrics[0].resource.current.averageValue}){"\n"}'
réplicas=4 deseadas=4 cpu=38 % (19m)
```

`kubectl top pods` muestra el consumo real de cada réplica en el instante de la consulta: 18, 19, 20 y 20 milicores. Contra los `50m` que cada una pidió, son 36 a 40 %. Y el HPA, con su propia consulta, lo dice en una línea: `cpu=38 % (19m)` es «utilización promedio del 38 %, que equivale a 19 milicores por Pod». La cuenta se puede hacer a mano: (18 + 19 + 20 + 20) ÷ 4 = 19.25 milicores, que redondea a `19m`, y 19 ÷ 50 es 0.38. La columna `TARGETS` no es un misterio: es esta división. `réplicas=4 deseadas=4` dice lo que ya se vio: lo que hay es lo que la fórmula quiere.

Los eventos del HPA son su bitácora, y cuentan lo mismo con otras palabras:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                    From                       Message
  ----     ------                        ----                   ----                       -------
  Normal   SuccessfulRescale             5m54s                  horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             4m39s                  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             2m37s                  horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m7s                   horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
```

Léelos de abajo hacia arriba, del más viejo al más nuevo. `SuccessfulRescale … New size: 2; reason: Current number of replicas below Spec.MinReplicas` es el primer ajuste, el de 9.5: el piso. Los dos `Warning` que siguen (`FailedGetResourceMetric`, `FailedComputeMetricsReplicas`) son el autoescalador diciendo que todavía no tiene métricas de los Pods nuevos: `unable to get metrics for resource cpu: no metrics returned from resource metrics API`. Son normales en los primeros segundos de vida de un Pod, mientras `metrics-server` hace su primera lectura; el `(x3 over 5m39s)` dice que se repitieron tres veces. El siguiente, `New size: 2; reason: All metrics below target`, no es de esta carga: es el HPA devolviendo a 2 la tercera réplica que 9.5.4 pidió a mano. Y los dos últimos, con 30 segundos de diferencia (hace `2m37s` y hace `2m7s`), son las decisiones de esta sección: `New size: 3` y `New size: 4`, los dos con el motivo `cpu resource utilization (percentage of request) above target`: el consumo, medido como porcentaje de la solicitud, por encima de la meta.

### 9.7 Sin carga, baja, después de la ventana

Se borra el Job, y se mira el HPA cada 20 segundos durante 260 segundos. Lo que se va a ver es la ventana de bajada de 9.3.3:

```text
$ kubectl delete -f carga.yaml
job.batch "carga" deleted from revisor namespace

(un renglón del HPA cada 20 s, durante 260 s; empieza a las 17:21:25)
[+ 20s] revisor   Deployment/revisor   cpu: 36%/50%   2     6     4     6m15s
[+ 40s] revisor   Deployment/revisor   cpu: 39%/50%   2     6     4     6m35s
[+ 60s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     6m55s
[+ 80s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     4     7m15s
[+100s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     7m35s
[+120s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     7m56s
[+140s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     8m16s
[+160s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m36s
[+180s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m56s
[+200s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     9m16s
[+220s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     2     9m36s
[+240s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     9m56s
[+260s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     10m
```

El reloj cuenta así. Se borra el Job en el segundo 0, pero la lectura de +20 y la de +40 siguen altas (36 % y 39 %): lo más probable es que los Pods de carga tarden unos segundos en terminar, y `metrics-server` promedia el consumo de una ventana corta, no de un instante. A +60 s la lectura ya es de 3 %, y se queda ahí. Con 4 réplicas y 3 % de uso, la cuenta es `ceil(4 × 0.06)` = `ceil(0.24)` = 1, pero el piso es 2, así que lo que el autoescalador *quiere* es 2. Y sin embargo la columna de réplicas dice 4 en +60, +80 y +100, y no pasa a 2 hasta el renglón de +120. Esa diferencia es la ventana de bajada de 60 segundos de 9.3.3: durante ese minuto, el HPA no usa la recomendación de hoy sino la más alta de los últimos 60 segundos, y la última recomendación de 4 réplicas la hizo con las lecturas altas del principio.

Los eventos dan las horas con más precisión que la tabla. Para leerlos hay que restar a partir del momento en que se corrió el `describe` (justo al terminar la tabla, unos 262 segundos después de borrar el Job): `New size: 3` ocurrió hace `2m54s`, es decir, alrededor de +88 s, y `New size: 2` hace `2m39s`, alrededor de +103 s. O sea que la bajada ocurrió en dos escalones, de 4 a 3 y 15 segundos después de 3 a 2, a unos 50 o 60 segundos de la última lectura alta. Es lo que se espera de una ventana: las recomendaciones de la parte alta van saliendo de ella de una en una. (La tabla nunca muestra el escalón de 3 porque la columna `REPLICAS` del HPA se actualiza con retraso respecto del Deployment: es `status.currentReplicas`, que el HPA escribe en su propia vuelta, cada 15 s; por eso el renglón de +100 todavía dice 4 aunque el evento de bajar a 3 es de +88. Qué número ve el HPA en cada vuelta no se midió.)

Dos objetos más de `describe` completan la lectura. La tabla de condiciones:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Conditions:/,/Events:/p'
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScaledToZero    False   NotScaledToZero   the HPA controller did not scale the workload to zero
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
Events:
```

`ScalingLimited True TooFewReplicas: the desired replica count is less than the minimum replica count` es el HPA diciendo, con todas las letras, lo que se calculó arriba: lo que la fórmula pide (1) es **menos** que el piso (2), y por eso se queda en 2. `ScalingActive True ValidMetricFound` dice que sí puede calcular, es decir, que `metrics-server` sigue contestando. Es la tabla que se mira cuando un HPA «no hace nada» y hay que saber si es porque no puede o porque no quiere. Y el consumo real de las dos réplicas que quedan:

```text
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-5b6k9   1m           6Mi             
revisor-767bdf965b-vcznx   1m           5Mi             
```

Un milicore cada una: la carga se fue de verdad. Los eventos completos, y las réplicas que quedan:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                   From                       Message
  ----     ------                        ----                  ----                       -------
  Normal   SuccessfulRescale             10m                   horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       9m17s (x3 over 10m)   horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  9m17s (x3 over 10m)   horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             7m                    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             6m30s                 horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m54s                 horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             2m39s (x2 over 9m2s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          9m33s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          9m31s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

El evento `New size: 2; reason: All metrics below target` («todas las métricas debajo de la meta») es la bajada. Y las dos réplicas que quedan son una en cada nodo de trabajo: la restricción de reparto de 9.4 sigue cumplida después de quitar dos Pods.

### 9.8 Quién manda sobre las réplicas

El Deployment tiene `replicas` vacío en el archivo, pero sigue teniendo un número. ¿Qué pasa si alguien más lo cambia a mano? Se prueba con `kubectl scale`, que escribe el número de réplicas en el Deployment, el mismo campo que escribe el HPA:

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

Cuarenta segundos después, el Deployment tiene otra vez 2 réplicas, y el último evento del HPA lo dice: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. El HPA no discutió ni preguntó: en su siguiente vuelta vio que el Deployment tenía menos réplicas que el piso, y lo devolvió. Eso contesta una pregunta práctica: **con un HPA activo, `kubectl scale` sirve de poco**. Si bajas por debajo del piso, el HPA te corrige; si subes por encima de lo que la carga pide, te corrige a la baja en cuanto pasa la ventana (9.5.4 lo mostró con la tercera réplica: a los 75 segundos el Deployment ya estaba de vuelta en 2). Para cambiar el número de réplicas con un HPA vivo hay que cambiar el HPA: su `minReplicas` o su `maxReplicas`. Quien quiera dos dueños para el mismo número tiene el problema de 9.3.4.

### 9.9 Actualizar y medir el corte

#### 9.9.1 Cómo actualiza un Deployment

Cuando cambias la plantilla de Pods de un Deployment (la imagen, una variable, un `preStop`), no se apagan todas las réplicas para encender otras. El Deployment crea un `ReplicaSet` nuevo para la plantilla nueva y va moviendo réplicas del viejo al nuevo, de pocas en pocas. La documentación lo describe así: se declara el estado nuevo actualizando la plantilla, «se crea un ReplicaSet nuevo, y el Deployment lo va escalando mientras reduce el viejo, asegurando que los Pods se reemplacen a un ritmo controlado» ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). Dos números gobiernan ese ritmo, y están en el Deployment desde 9.5:

- **`maxSurge`**: cuántos Pods **de más** se pueden crear por encima del número deseado durante la actualización. La documentación: «el número máximo de Pods que se pueden crear por encima del número deseado de Pods», como número o porcentaje; el valor por omisión es 25 %.
- **`maxUnavailable`**: cuántos Pods se pueden perder, es decir, estar **no disponibles**, durante la actualización. Por omisión también 25 %; la documentación aclara que no puede ser 0 si `maxSurge` es 0 (si no, la actualización no podría avanzar).

El `revisor` los fija en `maxSurge: 1` y `maxUnavailable: 0`. Se lee como una regla de seguridad: «no quites una réplica que contesta hasta que haya otra nueva lista para sustituirla». Con dos réplicas, el Deployment crea **una** réplica nueva (la tercera, por el `maxSurge`), espera a que esté lista, y solo entonces apaga una vieja; luego repite con la otra. En ningún momento hay menos de dos réplicas disponibles. Es la parte de la actualización que Kubernetes sabe hacer solo, y por eso `rollout status` imprime `1 out of 2 new replicas have been updated`: va contando las nuevas.

Pero «disponible» es una palabra del plano de control. Lo que sienten las peticiones es otra cosa, y la diferencia se llama *carrera*.

#### 9.9.2 La carrera del apagado

Cuando el Deployment decide quitar una réplica vieja, esa réplica recorre los pasos que la documentación del ciclo de vida de un Pod describe como el flujo de terminación ([Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)):

1. El Pod se marca como *terminando* en la API, con un plazo (por omisión, 30 segundos; el del `revisor` es de 15).
2. En el nodo, el `kubelet` ve la marca y empieza el apagado local: si el contenedor declara un gancho `preStop`, lo corre primero. Después, el entorno de ejecución de contenedores le manda la señal `TERM` al proceso 1 de cada contenedor, y el proceso tiene lo que quede del plazo para terminar. Si sigue vivo al vencer el plazo, recibe `KILL`.
3. **«Al mismo tiempo que el kubelet empieza el apagado ordenado del Pod»**, el plano de control evalúa si hay que sacarlo de los `EndpointSlice` de los Services que lo usan. La documentación agrega un detalle útil: un destino que representa un Pod que se está apagando no se retira de inmediato; se marca como *terminando* y con `ready: false`, y los balanceadores dejan de usarlo para tráfico normal.

El paso 2 y el paso 3 **no se esperan uno al otro**. Esa es la carrera. Es la observación de Phil Pearl de la escena, medida en otro contexto: el aviso de apagado le llega al proceso en el mismo momento en que empieza a correr la noticia «sácalo de la lista», y la noticia tiene que viajar: del plano de control a los `EndpointSlice`, de ahí a `kube-proxy` en cada nodo, y de ahí a las reglas de red de cada nodo. Mientras viaja, algunos nodos todavía envían peticiones al Pod viejo. Si el proceso ya cerró su puerto al recibir `TERM`, esas peticiones se encuentran con una puerta cerrada: `Connection refused`, o con silencio.

El `revisor` hace bien su parte: al recibir `TERM` escribe `recibí terminated, apagando`, termina las peticiones que tiene en curso y sale con `apagado limpio`, con un plazo interno de 5 segundos (la Lección 5 lo midió). Pero «termina las que tiene en curso» no incluye «sigue aceptando nuevas». El apagado del `revisor` usa `Server.Shutdown`, de la biblioteca estándar de Go, y la documentación de esa función dice cómo trabaja: «primero cierra todos los puertos abiertos, luego cierra todas las conexiones inactivas, y luego espera» a que las conexiones activas terminen ([Go, `net/http`](https://pkg.go.dev/net/http#Server.Shutdown)). El puerto de entrada se cierra **primero**. Lo que falta no es un defecto del `revisor`; es tiempo para que la noticia llegue.

Desde que Pearl escribió (2019), Kubernetes añadió a los `EndpointSlice` las condiciones `serving` y `terminating`, y permitió que `kube-proxy` use destinos que están terminando cuando no queda ninguno listo. Eso evita perder tráfico cuando *todos* los destinos se están apagando, pero no cambia que el aviso de apagado y el retiro de destinos viajen por caminos distintos: la carrera sigue existiendo y es la que mide esta lección.

#### 9.9.3 La pausa que cierra la carrera: `preStop`

Un gancho `preStop` corre **antes** de la señal `TERM`. Si lo único que hace es esperar unos segundos, el proceso sigue contestando con normalidad durante esa espera, mientras la noticia de «sácalo de la lista» termina de viajar. Cuando por fin llega `TERM`, ya nadie le manda tráfico nuevo. El Pod del `revisor` no tiene shell (la imagen es mínima, de la Lección 5), así que el gancho no puede ser un `sh -c "sleep 5"`; Kubernetes trae una acción de espera nativa:

```yaml
        lifecycle:
          preStop:
            sleep:
              seconds: 5
```

Eso es todo lo que se agregó al Deployment. Cinco segundos es una elección, no una ley: tienen que alcanzar para que la noticia llegue a todos los nodos del clúster, y cuánto tarda eso depende del tamaño y la carga del clúster. Pearl, en su caso, recomendaba esperar más que el tiempo que tarda el balanceador en reprogramarse. La pausa también cuenta contra el plazo de apagado: la documentación dice que el tiempo del `preStop` forma parte del `terminationGracePeriodSeconds`, y que si hace falta más, hay que subir el plazo. Por eso el Deployment pasó de 10 a **15 segundos**: 5 de pausa, hasta 5 de apagado del `revisor`, y 5 de margen.

Todo esto es teoría hasta que se mide. Medir exige una herramienta, y la herramienta es un programa.

#### 9.9.4 El sondeo

La medición tiene que cumplir tres cosas: **contar** cada petición, no una muestra; **correr durante** el cambio, no antes ni después; y **distinguir** qué versión contestó y de qué manera falló cada falla. Es un **programa**: `sondeo.sh`.

```bash
#!/usr/bin/env bash
# sondeo.sh — Lección 9: mide cuántas peticiones se pierden mientras haces algo.
#
# Uso:  ./sondeo.sh DURACION PAUSA HILOS [argumentos de curl]
#   DURACION  segundos que dura el sondeo
#   PAUSA     segundos entre una petición y la siguiente, en cada hilo (0 = sin pausa)
#   HILOS     cuántos ciclos de peticiones corren a la vez
#   lo demás  se le pasa a curl (por ejemplo: --retry 3 --retry-all-errors)
#
# Las peticiones salen del Pod «depurar» (curl dentro del clúster) hacia
# http://revisor/salud, es decir, por el Service, como cualquier cliente de dentro.
# Cada petición deja una línea «segundo cuerpo código rc=salida-de-curl». Al final se cuenta.
#
# 🔴 Antes de hablarle al clúster comprueba que el contexto activo es
# kind-curso-k8s-l9 y, si no, se detiene.
set -euo pipefail

[ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo" >&2; exit 1; }
[ "$#" -ge 3 ] || { echo "uso: $0 DURACION PAUSA HILOS [argumentos de curl]" >&2; exit 2; }
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
EXTRA="$*"

# Este guion corre DENTRO de depurar (por la entrada estándar de kubectl exec).
kubectl exec -i -n revisor depurar -- sh -s -- "$DURACION" "$PAUSA" "$HILOS" $EXTRA <<'DENTRO' |
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
inicio=$(date +%s); fin=$((inicio + DURACION))
for h in $(seq 1 "$HILOS"); do
  (
    while [ "$(date +%s)" -lt "$fin" ]; do
      r=$(curl -s -m 2 -w ' %{http_code}' "$@" http://revisor/salud; echo " rc=$?")
      echo "$(( $(date +%s) - inicio )) $(echo $r)"
      [ "$PAUSA" = 0 ] || sleep "$PAUSA"
    done
  ) &
done
wait
DENTRO
awk '
  { rc = $NF; code = $(NF - 1); v = "-"
    if (match($0, /"version":"[0-9.]+"/)) v = substr($0, RSTART + 11, RLENGTH - 12)
    n++; cuenta[code " " rc " " v]++
    if (code != "200") { f++; if (nf < 40) { seg[nf++] = $1 } } }
  END {
    printf "peticiones=%d fallidas=%d\n", n, f
    for (k in cuenta) { split(k, a, " "); printf "  %5d  código %s  curl %s  versión %s\n", cuenta[k], a[1], a[2], a[3] }
    if (f > 0) { printf "  segundos (desde el inicio) de las primeras fallas:"; for (i = 0; i < nf; i++) printf " +%s", seg[i]; printf "\n" }
  }' | sort
```

Se lee por partes.

- **Dónde corre.** El ciclo de peticiones corre **dentro** del Pod `depurar` de la Lección 3, el de `curl`, que se manda por la entrada estándar de `kubectl exec -i`. Así las peticiones nacen dentro del clúster y pasan por el Service, igual que las de cualquier cliente interno (por ejemplo, la tarea programada de la Lección 8). **Alcance:** esta medición cubre la ruta de un cliente dentro del clúster, es decir, el Service y `kube-proxy`. No pasa por la Gateway de Envoy, por donde entrarían los usuarios de fuera: esa pieza se entera de los cambios de destinos por su cuenta y puede tardar más o menos que `kube-proxy`, y esa ruta no se midió aquí. Pearl observó el problema en un Ingress, no en un Service, y dice que en los Service la ventana suele ser corta. El `<<'DENTRO'` con comillas simples impide que tu shell interprete nada de ese bloque: se manda tal cual.
- **Qué hace cada hilo.** Un ciclo que, mientras no se acabe el tiempo, pide `http://revisor/salud` con `curl -s -m 2`: silencioso (`-s`) y con un máximo de **2 segundos** por petición (`-m 2`). `-w ' %{http_code}'` le agrega al final el código HTTP, y el `echo " rc=$?"` agrega la salida del propio `curl`. Esa segunda cifra importa mucho, porque distingue **cómo** falló una petición, y cada modo cuenta una historia distinta (más abajo).
- **Una línea por petición.** `echo "$(( $(date +%s) - inicio )) $(echo $r)"` junta, en un solo renglón, el segundo en el que ocurrió, el cuerpo de la respuesta, el código y la salida de `curl`. Un renglón por petición evita que las líneas de los cuatro hilos se mezclen: cada `echo` es una sola escritura. (El `$(echo $r)` sin comillas aplana los saltos de línea del cuerpo; la respuesta del `revisor` trae uno al final, y sin ese truco la línea se partiría en dos.)
- **El conteo.** El `awk` final agrupa por (código, salida de `curl`, versión que contestó) e imprime cuántas hubo de cada una, y los segundos de las primeras 40 fallas. «Falla» es cualquier código distinto de `200`, incluido `000`, que es lo que `curl` imprime cuando no llegó a recibir una respuesta HTTP.
- **Los dos modos de falla que vas a ver.** `curl` sale con **7** cuando no pudo conectarse (`Failed to connect`): llegó a una dirección donde nadie escucha, o la conexión fue rechazada. Sale con **28** cuando se acabó el tiempo (`-m 2`) sin respuesta. Del primero se puede decir algo concreto: alguien contestó «aquí no hay nadie». Del segundo, solo que nadie contestó a tiempo; la causa puede estar en el destino, en la red o en el propio cliente.

Una advertencia de honestidad sobre el instrumento: el Pod `depurar` tiene un límite de CPU de `100m`, y cuatro ciclos de `curl` sin pausa lo ocupan por completo. Un cliente al tope de su CPU puede retrasar sus propias peticiones y producir tiempos de espera que no son culpa del servidor. Lo que se mide es el *conjunto* cliente, red y servidor. Por eso el sondeo base de 9.9.5 va antes de cualquier cambio: mide qué ruido produce el sondeo por sí mismo.

#### 9.9.5 Primero, el ruido; después, la actualización con `preStop`

Antes de cambiar nada se mide el sondeo contra un clúster quieto, para saber cuánto ruido produce por sí solo. Son 15 segundos, con cuatro hilos y sin pausa. Después viene la primera actualización, la del manifiesto tal como está, con el `preStop` puesto. El guion lanza el sondeo en segundo plano (`&`), espera 3 segundos a que ya esté corriendo, cambia la imagen de `1.6.0` a `1.6.1` y espera a que el despliegue termine:

```text
$ ./sondeo.sh 15 0 4
    172  código 200  curl rc=0  versión 1.6.0
peticiones=172 fallidas=0

$ ./sondeo.sh 45 0 4 &   # empieza a las 17:26:44
(pausa de 3 s: que el sondeo ya esté corriendo)

$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:1.6.1
deployment.apps/revisor image updated

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

# resultado del sondeo (A, con preStop):
     56  código 200  curl rc=0  versión 1.6.0
    416  código 200  curl rc=0  versión 1.6.1
peticiones=472 fallidas=0
```

`kubectl set image` cambia la imagen del contenedor `revisor` dentro del Deployment `revisor`, sin tocar ningún archivo; es el camino corto para esta medición (el hábito de seguridad, más abajo, dice por qué no es el camino de un proyecto real). El `rollout status` va contando: «1 out of 2 new replicas have been updated»: de las dos réplicas nuevas, una ya se actualizó; y después «1 old replicas are pending termination»: una vieja todavía no termina. Es la mecánica de `maxSurge: 1` de 9.9.1 vista desde fuera: primero una réplica nueva, luego se retira una vieja, luego otra nueva.

El conteo se lee así. El **sondeo base** hizo 172 peticiones en 15 segundos, 172 con código `200` y todas las de la versión `1.6.0`. Sin fallas: así que el instrumento, en ese momento, no produce ruido visible. Pero 172 peticiones son pocas para estimar el ruido: un ruido de 0.24 % esperaría menos de una falla en 172 peticiones, así que esta ronda no distingue «cero» de «unas pocas por mil». La **actualización A** hizo 472 peticiones en 45 segundos: 56 las contestó la versión `1.6.0` (las anteriores al reemplazo y las que cayeron en réplicas viejas mientras avanzaba) y 416 la `1.6.1`, y ninguna falló. En ningún momento hubo un renglón con otro código. Si esta fuera la única ronda, el titular sería «cero fallas de 472». Pero una ronda no basta, y el resto de la sección existe para decir por qué.

#### 9.9.6 El mismo experimento, sin la pausa

Para saber qué evita el `preStop` hay que quitarlo y medir lo mismo. Se quita con una parcha de tipo JSON que borra el campo `lifecycle` del primer contenedor:

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/lifecycle"}]'
deployment.apps/revisor patched
```

`op: remove` con una `path` es «borra este campo». La parcha cambia la plantilla de Pods, así que provoca su propio reemplazo; el guion espera a que termine con `rollout status` y comprueba que el gancho ya no está. La comprobación es esta:

```text
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].lifecycle}{"|"}{.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
|15
```

La salida es `|15`: antes de la barra, el contenido de `lifecycle`, que está **vacío**; después, el `terminationGracePeriodSeconds`, 15. (El `|` lo escribe el propio comando entre los dos campos, para poder ver el vacío.) Sin gancho, el Pod recibe `TERM` en el mismo instante en que empieza su apagado.

Con esa plantilla se repite la actualización tres veces, yendo y viniendo entre las dos versiones, para que cada ronda cambie de imagen y haya un reemplazo de verdad:

```text
# resultado del sondeo (B, ronda 1, sin preStop, hacia 1.6.0):
      2  código 000  curl rc=7  versión -
      7  código 000  curl rc=28  versión -
     51  código 200  curl rc=0  versión 1.6.1
    403  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +7 +7 +9 +9 +9 +9 +30
peticiones=463 fallidas=9

# resultado del sondeo (B, ronda 2, sin preStop, hacia 1.6.1):
      1  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
     47  código 200  curl rc=0  versión 1.6.0
    465  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +5 +7 +7 +8 +9 +9 +10 +10 +16
peticiones=521 fallidas=9

# resultado del sondeo (B, ronda 3, sin preStop, hacia 1.6.0):
      3  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
    105  código 200  curl rc=0  versión 1.6.1
    469  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +5 +7 +7 +8 +8 +9 +10 +10 +10
peticiones=585 fallidas=11
```

Hay renglones nuevos, y cada uno cuenta algo distinto:

- `código 000  curl rc=7`: el código HTTP `000` es lo que `curl` imprime cuando **no recibió respuesta HTTP**, y `rc=7` es su propia salida: «Failed to connect to host». Alguien contestó «aquí no hay nadie» a la conexión. Es la firma que se esperaría de la carrera de 9.9.2: una petición llegó, por el Service, a una réplica que ya había cerrado su puerto.
- `código 000  curl rc=28`: `rc=28` es «Operation timeout»: pasaron los 2 segundos de `-m 2` sin respuesta. Nadie dijo «no»; nadie dijo nada. Pasa cuando el paquete llega a una dirección que ya no existe (el Pod ya desapareció y la red todavía lo apunta) o cuando alguien tarda demasiado en contestar. El tiempo agotado, entonces, tiene varias causas posibles, y una de ellas es la misma carrera.
- La línea **«segundos (desde el inicio) de las primeras fallas»** da el segundo, contado desde que arrancó el sondeo, en que *terminó* cada petición fallida; una falla `curl 28` se envió unos 2 segundos antes. En las tres rondas sin pausa, las fallas caen entre `+5` y `+10` segundos, salvo una o dos más tardías. Es el momento en que las réplicas viejas se apagan: el `set image` se mandó 3 segundos después de lanzar el sondeo.

La suma de las tres rondas sin `preStop`: 463 + 521 + 585 = 1,569 peticiones, de las que fallaron 9 + 9 + 11 = 29. Seis fueron `curl 7` (2, 1 y 3) y 23 fueron `curl 28` (7, 8 y 8).

#### 9.9.7 Con la pausa otra vez, tres rondas más

Se vuelve a aplicar la carpeta, que trae el `preStop`, y se repite la actualización tres veces más:

```text
$ kubectl apply -k . | grep -E 'deployment|horizontal'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
horizontalpodautoscaler.autoscaling/revisor unchanged
```

```text
# resultado del sondeo (C, ronda 1, con preStop, hacia 1.6.1):
      4  código 000  curl rc=28  versión -
     57  código 200  curl rc=0  versión 1.6.0
    471  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +2 +2 +2 +2
peticiones=532 fallidas=4

# resultado del sondeo (C, ronda 2, con preStop, hacia 1.6.0):
     97  código 200  curl rc=0  versión 1.6.1
    515  código 200  curl rc=0  versión 1.6.0
peticiones=612 fallidas=0

# resultado del sondeo (C, ronda 3, con preStop, hacia 1.6.1):
      1  código 000  curl rc=28  versión -
     72  código 200  curl rc=0  versión 1.6.0
    360  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +25
peticiones=433 fallidas=1
```

#### 9.9.8 Qué dicen las siete rondas, y qué no

Juntando todas las rondas de la corrida:

| Variante | Rondas | Peticiones | Fallidas | `curl 7` | `curl 28` |
|---|---|---|---|---|---|
| Sondeo base, sin tocar nada | 1 | 172 | 0 | 0 | 0 |
| **Con** `preStop` (A y C1 a C3) | 4 | 2,049 | 5 | 0 | 5 |
| **Sin** `preStop` (B1 a B3) | 3 | 1,569 | 29 | 6 | 23 |

Con `preStop`, 5 fallas de 2,049 peticiones (0.24 %; intervalo del 95 %, método de Wilson: 0.10 a 0.57 %). Sin él, 29 de 1,569 (1.85 %; 1.29 a 2.64 %). Los intervalos no se solapan, pero suponen peticiones independientes, y aquí no lo son (cuatro hilos que comparten cliente, y las cuatro fallas de la ronda C1 son del mismo instante); léelos como una indicación del tamaño, no como una garantía. Lo que esas cifras permiten decir, con cuidado:

1. **La conexión rechazada solo apareció sin la pausa.** Las seis conexiones rechazadas (`curl 7`) ocurrieron en las rondas sin `preStop`, y ninguna en las cuatro rondas con él. Es el efecto que predice 9.9.2: sin pausa, una réplica cierra su puerto mientras alguien todavía le manda peticiones. Con pausa quedaron cinco tiempos agotados (`curl 28`) que esta medición no permite atribuir ni al ruido ni a una carrera residual: ese código tiene ambas causas posibles.
2. **Las fallas se agrupan donde se espera.** En las rondas sin pausa caen en una ventana de unos cinco o seis segundos, la que sigue al `set image`. En las rondas con pausa, no hay fallas en esa ventana: las cuatro de la ronda C1 ocurrieron en el mismo segundo, `+2`, es decir, cuando el sondeo apenas arrancaba (el `set image` se manda 3 segundos después de lanzarlo), y la única de la ronda C3 cayó en `+25`, ya con la actualización en marcha; no registramos cuándo se apagó cada Pod, así que no podemos relacionarla con ningún momento. Que las cuatro fallas de C1 sean simultáneas apunta a un arranque lento del cliente (cuatro hilos que empiezan a la vez dentro de un Pod con un límite de `100m` de CPU en una máquina compartida y cargada), pero la medición no lo demuestra: es una hipótesis, no una conclusión.
3. **Cero no es lo que se midió.** La ronda A, la primera, dio 0 de 472; las otras tres rondas con pausa dieron 4, 0 y 1. Una lección que dijera «con `preStop` no se pierde ninguna petición» habría escogido la ronda A y habría mentido. Lo que sí sostiene la medición: la pausa redujo las fallas de la ventana de actualización a un número pequeño que tampoco es cero, y las rondas con pausa dieron en conjunto 5 fallas en 2,049 peticiones. No sabemos cuánto de eso es ruido del cliente: el sondeo base, de 172 peticiones sin falla, es demasiado corto para estimarlo.
4. **Esto no es una prueba estadística.** Son siete rondas de 45 segundos, en una máquina compartida con mucha carga, con un cliente que comparte los núcleos con el clúster que mide. Las rondas no se alternaron (primero la A, luego las tres sin pausa y luego las tres con pausa), así que la variante y el momento van juntos, y la carga de la máquina cambió durante el trabajo; para separar ambos efectos habría que alternar con y sin pausa. Las cifras sirven para comparar variantes dentro de esta corrida; no para prometer un porcentaje en tu clúster. Lo que sí es transferible es el método: contar todas las peticiones, distinguir cómo fallan, repetir, y no creerle a una sola ronda.

La pausa de 5 segundos, entonces, cierra la parte de la carrera que se puede cerrar con una pausa. No es una garantía: la propia documentación de los ganchos dice que su entrega es «al menos una vez» y que no hay más promesa. Y hay una fuente de fallas que ninguna pausa toca: la caída de un nodo, que viene en 9.12.

### 9.10 El historial y la vuelta atrás

#### 9.10.1 Un ReplicaSet por versión

Cada vez que la plantilla del Deployment cambia, el Deployment crea un `ReplicaSet` nuevo, y el viejo se queda ahí, con cero réplicas, en lugar de borrarse. Cada uno de esos ReplicaSet guarda la plantilla de una versión: su imagen, sus sondas, su `preStop`. Es lo que hace posible volver atrás, y la documentación lo dice sin rodeos: «la configuración de cada revisión del Deployment se guarda en sus ReplicaSet; por lo tanto, una vez que se borra un ReplicaSet viejo, se pierde la capacidad de volver a esa revisión». Cuántos se conservan lo decide `.spec.revisionHistoryLimit`, que vale 10 por omisión.

Puedes ponerle un comentario a cada revisión con una anotación, `kubernetes.io/change-cause`, que `rollout history` muestra en una columna. La documentación dice que se puede poner con `kubectl annotate`, editando el manifiesto o con herramientas que lo hagan solas, y que la bandera `--record`, que antes lo llenaba, está obsoleta y se va a retirar. Se aplica a la revisión actual:

```text
$ kubectl annotate deployment/revisor -n revisor kubernetes.io/change-cause='ronda de pruebas de la Leccion 9' --overwrite
deployment.apps/revisor annotated

$ kubectl rollout history deployment/revisor -n revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
3         <none>
8         <none>
9         <none>
12        <none>
13        ronda de pruebas de la Leccion 9
```

La columna `CHANGE-CAUSE` solo tiene texto en la revisión actual, porque la anotación se copia a una revisión cuando esa revisión se crea, y las demás ya existían. Los números de revisión no tienen por qué ser consecutivos: aquí son 1, 3, 8, 9, 12 y 13. Cada vez que la plantilla vuelve a ser idéntica a la de un ReplicaSet que ya existía, el Deployment **reutiliza** ese ReplicaSet y le da el número de revisión más nuevo, de modo que las revisiones intermedias que pasaron a ser «la misma» desaparecen de la lista. Los ReplicaSet confirman la cuenta:

```text
$ kubectl get replicasets -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-574b5b6c4c   0         0         0       16m
revisor-5978745747   0         0         0       4m33s
revisor-5cc67d8975   2         2         2       5m33s
revisor-67b97d67c9   0         0         0       18m
revisor-767bdf965b   0         0         0       16m
revisor-7f759cd976   0         0         0       4m51s
(imagen actual: curso-docker-revisor:1.6.1)
```

Seis ReplicaSet, uno por cada plantilla distinta que pasó por el Deployment en esta corrida: con `preStop` y sin él, con una versión o con otra, con `nodeTaintsPolicy` y sin él. Solo uno tiene réplicas. Los otros cinco son el historial.

#### 9.10.2 `rollout undo`

`rollout undo` lleva el Deployment a la revisión anterior. No ejecuta nada especial: escribe en el Deployment la plantilla del ReplicaSet anterior, y el Deployment hace el mismo reemplazo gradual de siempre, pero al revés.

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back
```

El aviso (`Warning: resource deployments/revisor was previously managed with 'kubectl apply'…`) merece leerse completo. Dice que la vuelta atrás **no actualiza** la anotación `last-applied-configuration`, la que guarda el último estado que aplicaste con `kubectl apply`, y que eso «puede causar un comportamiento inesperado en futuros `kubectl apply`». Traducido: tu archivo dice una cosa, el clúster volvió a otra, y el siguiente `apply -k .` va a hacer su propia comparación y puede deshacer tu vuelta atrás. `rollout undo` es una herramienta para apagar un incendio; el arreglo de verdad es cambiar el archivo y aplicarlo. La documentación de `kubectl` lo sugiere con las mismas palabras al final del aviso: «considera usar `kubectl apply` con tu configuración anterior».

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

#### 9.10.3 Cuándo termina de verdad

`rollout status` dijo `successfully rolled out`. ¿Ya no queda nada de la versión que quitaste? Se mira con la columna que hace falta, la que el guion lleva en todos sus listados de Pods:

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-5cc67d8975-qbzsl   curso-docker-revisor:1.6.1   curso-k8s-l9-worker2   2026-10-21T23:32:40Z
revisor-5cc67d8975-ttszb   curso-docker-revisor:1.6.1   curso-k8s-l9-worker    2026-10-21T23:32:37Z
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
```

Mira la columna `BORRANDOSE`: es el campo `deletionTimestamp` del Pod, la hora (en UTC) a la que el clúster le ordenó terminar. Los Pods de `1.6.1` la tienen: están terminando, siguen en su pausa de `preStop` (el plazo de 15 segundos todavía no vence), y **siguen contestando**. Los Pods de `1.6.0` no la tienen: son los vivos de ahora. `rollout status` terminó porque el Deployment ya cumple lo que se le pidió (las réplicas deseadas de la versión buena están listas y las malas ya se marcaron para terminar), no porque el último Pod malo haya acabado de morir. Las peticiones lo muestran:

```text
$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}
```

Cuatro de las seis respuestas dicen `1.6.1`: **la versión que acabas de quitar**. Solo dos dicen `1.6.0`, la que quedó. Si hubieras concluido en ese momento que el `undo` no funcionó, te habrías equivocado. Es la misma carrera de 9.9.2, vista desde la vuelta atrás: el retiro de los destinos tarda un poco en llegar a todos. Doce segundos después, con la pausa vencida:

```text
(espera de 12 s: que termine el preStop de los Pods viejos)

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>

$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}
```

Ya no queda ninguna fila con `BORRANDOSE`, y las seis respuestas dicen `1.6.0`. Un `rollout undo` que parece no haber funcionado porque una petición contestó la versión vieja suele ser esto: se concluyó demasiado pronto. La regla: antes de decidir que la vuelta atrás falló, mira `deletionTimestamp` y espera a que se venza el plazo.

Para ver qué guardaba una revisión, `rollout history` acepta `--revision=N`, y muestra la plantilla completa de esa versión, la imagen incluida. El guion pide la primera:

```text
$ kubectl rollout history deployment/revisor -n revisor --revision=1 | head -14
deployment.apps/revisor with revision #1
Pod Template:
  Labels:	app=revisor
	pod-template-hash=67b97d67c9
  Service Account:	revisor
  Containers:
   revisor:
    Image:	curso-docker-revisor:1.6.0
    Port:	8080/TCP (http)
    Host Port:	0/TCP (http)
    Limits:
      cpu:	200m
      memory:	64Mi
    Requests:
```

Es la plantilla con la que nació el Deployment en la carpeta de la Lección 8: imagen `1.6.0`, sin `preStop`. (La salida se corta en 14 renglones con `head` para que quepa; el resto son los `Requests`, las sondas y los volúmenes.) Para volver a ella habría que decir `kubectl rollout undo deployment/revisor --to-revision=1`, la forma que trae la documentación.

Y para cerrar el círculo con la disciplina del hábito de seguridad, el guion vuelve a aplicar la carpeta, de modo que el clúster y los archivos queden iguales:

```text
$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
```

`unchanged`: la plantilla que dejó el `undo` es idéntica a la del archivo, y `apply` no tiene nada que hacer.

#### 9.10.4 El error: una imagen que no existe

Una de las razones más comunes para una vuelta atrás es una actualización que salió mal, y no siempre por un defecto del programa sino por un descuido de escritura: la etiqueta de la imagen está mal escrita, o apunta a una versión que nadie publicó. Se provoca a propósito, con un guion aparte que arma su propio clúster mínimo: **`fig09_02.imagen-rota.sh`**, un **programa** que falla a propósito. Crea `curso-k8s-l9` solo con lo que hace falta (el `revisor` y la prueba, sin MetalLB ni Envoy Gateway, que no intervienen), pone dos réplicas, lanza el sondeo de 9.9.4 y cambia la imagen a `curso-docker-revisor:9.9.9`, una etiqueta que no existe. Su salida es `fig09_02.imagen-rota.salida.txt`. Se corre así, desde la carpeta de la lección:

```bash
./fig09_02.imagen-rota.sh > fig09_02.imagen-rota.salida.txt 2>&1
```

No lleva `ctx &&` delante porque crea su propio clúster y el contexto todavía no existe; trae sus propias guardas (kubeconfig temporal, contexto comprobado antes de cada `kubectl`, borrado del clúster al salir). Si ya tienes vivo un `curso-k8s-l9`, el guion se detiene: no toca el tuyo. Tarda unos cuatro minutos. El comando que provoca el error es este, y sale bien:

```text
$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:9.9.9
deployment.apps/revisor image updated
```

`image updated`, sin quejas: el `kube-apiserver` no sabe si la imagen existe. Es la misma situación del `selector` mal escrito de la Lección 3: un nombre válido que apunta a nada. Lo que sigue se lee en orden, como cualquier fallo.

**Primero, `rollout status`.**

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]
(espera de 10 s: que el kubelet registre el fallo de descarga)
```

Se queda en «1 out of 2 new replicas have been updated» y, al agotarse el plazo de 40 segundos que se le dio, sale con `error: timed out waiting for the condition` y código 1. Fíjate en que **no dice qué está mal**: solo dice que no termina. `rollout status` espera, y la causa hay que buscarla en otra parte. Sin un `--timeout`, esperaría hasta que el Deployment declare que no progresa: el campo `.spec.progressDeadlineSeconds`, que vale 600 segundos por omisión, después de los cuales el Deployment agrega una condición `Progressing` en `False` con la razón `ProgressDeadlineExceeded` ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). La documentación advierte que Kubernetes **no hace nada** con un Deployment atascado salvo reportarlo: no lo deshace solo.

**Segundo, los Pods.**

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS         RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-6586779dc4-96dfn   0/1     ErrImagePull   0          50s   10.244.2.5   curso-k8s-l9-worker    <none>           <none>
revisor-85f8668b64-2tjx4   1/1     Running        0          60s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running        0          60s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>
```

Tres Pods, no dos. Los dos viejos (`85f8668b64`) siguen `1/1 Running`. El nuevo (`6586779dc4`) está en `0/1 ErrImagePull`: el nodo intentó descargar la imagen, no la encontró, y no hay contenedor que arrancar. Es el mismo estado de la Lección 2, con la misma salida, y se lee igual: el siguiente paso es el `describe`.

**Tercero, los eventos del Pod nuevo.**

```text
$ kubectl describe pod revisor-6586779dc4-96dfn -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  50s                default-scheduler  Successfully assigned revisor/revisor-6586779dc4-96dfn to curso-k8s-l9-worker
  Normal   Pulling    13s (x3 over 50s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:9.9.9": failed to pull and unpack image "docker.io/library/curso-docker-revisor:9.9.9": failed to resolve reference "docker.io/library/curso-docker-revisor:9.9.9": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
  Normal   BackOff    2s (x3 over 49s)   kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     2s (x3 over 49s)   kubelet            spec.containers{revisor}: Error: ImagePullBackOff
```

El evento `Failed to pull image "curso-docker-revisor:9.9.9"` dice, con más texto del que cabe en la página, que no pudo resolver `docker.io/library/curso-docker-revisor:9.9.9`: el nodo buscó la etiqueta en Docker Hub, donde no existe, porque la imagen del curso vive solo en tu máquina. Después `ErrImagePull`, `BackOff` y `ImagePullBackOff`: el `kubelet` reintenta con esperas cada vez más largas. `(x3 over 50s)` dice cuántas veces lo intentó.

**Cuarto, lo que dice el Deployment.**

```text
$ kubectl get deployment revisor -n revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   2/2     1            2           60s
```

`READY 2/2`, `UP-TO-DATE 1`, `AVAILABLE 2`. «Listas: 2 de 2; actualizadas: 1; disponibles: 2». El Deployment hizo exactamente lo que `maxSurge: 1` y `maxUnavailable: 0` le pedían: creó **una** réplica nueva, esperó a que estuviera lista para poder retirar una vieja, y como nunca lo estuvo, no retiró ninguna. Las dos viejas siguen sirviendo.

**Y el sondeo, que corrió durante todo el atasco:**

```text
# resultado del sondeo (durante toda la actualización rota):
    811  código 200  curl rc=0  versión 1.6.0
peticiones=811 fallidas=0
```

En esta ronda ninguna de las 811 peticiones falló: todas las contestó la versión `1.6.0`, la vieja, porque ninguna réplica vieja se retiró. Es una sola ronda, pero lo que hace posible el resultado es mecánico, no estadístico: con `maxUnavailable: 0`, el Deployment no retira una réplica vieja sin tener lista una nueva, y la nueva nunca llegó a estar lista. Esta es la utilidad concreta de `maxUnavailable: 0`: una actualización rota se queda atascada *sin quitar lo que funciona*. Ojo con lo que no mide: como nunca se apagó una réplica vieja, tampoco prueba nada sobre la carrera del apagado. Con el valor por omisión del 25 %, un Deployment de cuatro réplicas se permitiría quitar una antes de tener lista la nueva, y un tropiezo así podría notarse.

**La corrección** es la causa, y la herramienta es la de 9.10.2:

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-85f8668b64-2tjx4   1/1     Running   0          65s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running   0          65s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curso-docker-revisor:1.6.0
```

El `undo` lleva la plantilla a la anterior, el Pod que no arrancaba desaparece, y la imagen vuelve a `curso-docker-revisor:1.6.0`. (Aquí no hubo ningún Pod de la versión mala que siguiera contestando, como en 9.10.3: nunca llegó a estar listo.) En un proyecto real, la corrección definitiva es arreglar la etiqueta en el archivo y aplicarlo; el `undo` es el primer auxilio.

### 9.11 Mantenimiento de un nodo: el presupuesto de interrupciones

#### 9.11.1 Dos clases de interrupción

No todo lo que le quita un Pod a un servicio es igual. La documentación de Kubernetes separa las **interrupciones involuntarias**, que son «casos inevitables» como «una falla de hardware de la máquina que sostiene el nodo», de las **voluntarias**, que son las acciones de quien opera el sistema: la persona dueña de la aplicación, o el administrador del clúster, que entre otras cosas puede «vaciar un nodo para repararlo o actualizarlo» ([Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)). La diferencia importa porque sobre las voluntarias se puede **negociar**: el clúster te deja decir cuánto estás dispuesto a perder. Sobre las involuntarias no: nadie le pregunta a un disco si puede fallar.

La herramienta de la negociación es el **PodDisruptionBudget** (PDB), el segundo objeto de `escalado.yaml`. La documentación define sus dos formas: `minAvailable`, el número de Pods que tienen que seguir disponibles después de un desalojo, y `maxUnavailable`, el número que puede quedar no disponible; se declara una u otra, no las dos. El del `revisor` dice `minAvailable: 1`: con dos réplicas, una puede irse, y la otra tiene que quedarse. Se lee su estado:

```text
$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     17m
```

`ALLOWED DISRUPTIONS 1` es la cuenta que el clúster lleva en este instante: dos réplicas sanas, menos una que tienen que seguir en pie, deja una que se puede perder. Si una de las dos deja de estar sana, ese número baja a 0, y el siguiente desalojo se rechaza.

#### 9.11.2 Cómo se vacía un nodo

`kubectl drain` es la orden de «este nodo va a mantenimiento». Hace dos cosas, en este orden: lo marca como no programable (`cordon`: ningún Pod nuevo llega) y desaloja uno por uno los Pods que corren en él. La documentación ([Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)) explica que un desalojo seguro permite que los contenedores terminen con orden y «respeta los PodDisruptionBudget que hayas especificado». La disciplina que hay detrás, según la página de interrupciones: `kubectl` pide cada desalojo por la API de desalojo; esa petición puede ser rechazada temporalmente, y la herramienta reintenta las que fallan hasta que todos los Pods del nodo terminan o se agota un plazo que tú configuras (`--timeout`). El comando del guion lleva dos banderas. `--ignore-daemonsets`: la documentación dice que hace falta cuando hay Pods de un DaemonSet (como los `speaker` de MetalLB), que se dejan donde están y se retiran cuando el nodo sale del clúster. `--delete-emptydir-data`: acepta perder los datos de los volúmenes `emptyDir`, como el `/datos` del `revisor`, que de todos modos muere con el Pod.

#### 9.11.3 El error: un presupuesto sin margen

Se provoca con `fig09_01.pdb-estricto.yaml`, un **programa** que falla a propósito: el mismo PDB, con `minAvailable: 2`.

```yaml
# fig09_01.pdb-estricto.yaml — FALLA A PROPÓSITO: un PodDisruptionBudget que no deja
# perder NI UNA réplica (minAvailable: 2 con solo 2 réplicas). Mientras exista,
# «kubectl drain» no puede desalojar ningún Pod del revisor y se queda reintentando.
# Se deshace con: kubectl apply -k .   (escalado.yaml trae el PDB bueno)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: revisor
```

Se aplica **en el espacio de nombres del `revisor`**, con `-n revisor`: el archivo no declara espacio, y un `apply -f` sin `-n` crea el objeto donde apunte el contexto (el espacio `default`), que no protege a nadie. Es un error fácil de cometer, y se cometió al preparar esta lección: olvidar el `-n revisor`. El clúster no se queja: el mensaje fue `poddisruptionbudget.policy/revisor created` en lugar de `configured`, el presupuesto bueno del espacio `revisor` quedó intacto (`ALLOWED DISRUPTIONS 1`) y el `drain` pasó sin trabas, como si el experimento no existiera. La pista estaba en la palabra: `created` en vez de `configured`. Se lee el mensaje del `apply`, y se comprueba con `get pdb -n revisor`.

```text
$ kubectl apply -n revisor -f fig09_01.pdb-estricto.yaml
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   2               N/A               0                     17m
(el nodo que se va a vaciar: curso-k8s-l9-worker2)
```

`configured`: el objeto ya existía y ahora dice otra cosa. `MIN AVAILABLE 2` y, la cifra que importa, `ALLOWED DISRUPTIONS 0`. Con dos réplicas y la obligación de conservar dos, no hay ninguna que se pueda perder. Ahora se intenta vaciar un nodo, con un plazo corto para que el guion no se quede esperando:

```text
$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=30s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/prueba-6899c74865-cgzkw
evicting pod metallb-system/controller-76f4cf76b7-m9mlh
evicting pod revisor/revisor-767bdf965b-58sd9
evicting pod envoy-gateway-system/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/controller-76f4cf76b7-m9mlh evicted
pod/prueba-6899c74865-cgzkw evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
There are pending pods in node "curso-k8s-l9-worker2" when an error occurred: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
pod/revisor-767bdf965b-58sd9
error: unable to drain node "curso-k8s-l9-worker2" due to error: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s, continuing command...
There are pending nodes to be drained:
 curso-k8s-l9-worker2
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
[código de salida: 1]
```

Se lee como un guion de teatro. El nodo se acordona (`cordoned`). Se piden desalojos de los Pods que viven ahí, y salen los que no están protegidos: `prueba`, el `controller` de MetalLB y el Pod de Envoy que atiende la puerta terminan (`evicted`). Y entonces aparece, una y otra vez, cada 5 segundos:

`error when evicting pods/"revisor-…" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.`

«No se puede desalojar el Pod porque violaría el presupuesto de interrupciones». El clúster no se equivocó: hizo exactamente lo que se le pidió. A los 30 segundos se acaba el plazo del `drain` (`global timeout reached: 30s`) y el comando sale con código 1. Observa en qué quedó el nodo:

```text
$ kubectl get nodes
NAME                         STATUS                     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready                      control-plane   26m   v1.37.0
curso-k8s-l9-worker          Ready                      <none>          26m   v1.37.0
curso-k8s-l9-worker2         Ready,SchedulingDisabled   <none>          26m   v1.37.0
```

`Ready,SchedulingDisabled`: sigue sano pero **acordonado**. Un `drain` interrumpido deja el nodo en ese estado hasta que alguien lo regrese con `uncordon`; si no, ningún Pod nuevo cae ahí, y es una de las maneras de quedarse sin capacidad sin que nada esté roto. El guion lo regresa:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
```

La corrección es volver a aplicar la carpeta, que trae el PDB bueno (`minAvailable: 1`), y repetir el `drain`. Ahora `ALLOWED DISRUPTIONS` vuelve a 1 y el desalojo del `revisor` pasa:

```text
# --- La corrección: el PDB de la carpeta ---

$ kubectl apply -k . | grep -E 'poddisruption'
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     18m

$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=120s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/revisor-767bdf965b-58sd9
pod/revisor-767bdf965b-58sd9 evicted
node/curso-k8s-l9-worker2 drained
```

`evicted` en el primer intento, sin reintentos ni errores. Pero mira dónde quedaron las réplicas:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          6s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          109s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

**Las dos réplicas quedaron en el mismo nodo**, `curso-k8s-l9-worker`. El desalojo del `revisor` pasó (el PDB permitió perder una), pero la réplica nueva nació en el único nodo que podía recibirla, y ahora las dos viven juntas: la pérdida de ese nodo se llevaría el servicio entero. Lo más probable es que lo explique `Honor`: un nodo acordonado lleva la mancha `node.kubernetes.io/unschedulable`, y con `nodeTaintsPolicy: Honor` los nodos manchados (para los que el Pod no tiene tolerancia) salen de la cuenta del reparto. Mientras `worker2` estuvo acordonado, el único dominio era `worker`, con asimetría 0, y el reparto permitió ambas réplicas ahí. La restricción se cumplió; no hubo dónde más.

#### 9.11.4 Regresar el reparto

Se regresa el nodo al servicio y se espera a ver si el clúster se encarga solo:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
(espera de 30 s: ¿vuelve el reparto por sí solo?)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          37s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          2m20s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

No. Las dos réplicas siguen juntas: nada las movió. Es exactamente la limitación de 9.4.4: la restricción de reparto se evalúa **al programar un Pod**, no después, y la documentación dice que no hay garantía de que se siga cumpliendo cuando se retiran Pods, y recomienda herramientas como el *Descheduler* para rebalancear. Sin instalar nada, el remedio es provocar una programación nueva, y `kubectl rollout restart` lo hace: reemplaza las réplicas con el mismo procedimiento gradual de una actualización, y cada Pod nuevo se programa con la restricción puesta.

```text
$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          12s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          10s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

De nuevo una réplica en cada nodo de trabajo. El reparto se mantiene con un hábito, no con una configuración: después de un mantenimiento, se mira `-o wide`.

### 9.12 Un nodo que se cae

Hasta aquí todo fue *planeado*: una actualización que tú lanzas, un mantenimiento que tú pides. Falta lo otro: la máquina que se apaga sin avisar. Es la tercera pregunta del director. Se contesta apagando uno de los nodos de trabajo a propósito, midiendo, y preguntándole al clúster cuándo se enteró.

#### 9.12.1 Qué sabe el clúster, y cuándo

Un nodo caído no manda aviso: deja de mandar *latidos*. La documentación de «Node Status» describe dos formas de latido: las actualizaciones del `.status` del nodo y unos objetos `Lease` (arrendamientos) dentro del espacio `kube-node-lease`, uno por nodo; el `kubelet` renueva el suyo cada 10 segundos por omisión ([Node Status](https://kubernetes.io/docs/reference/node/node-status/)). Cuando los latidos dejan de llegar, el controlador de nodos espera un plazo, `node-monitor-grace-period`, antes de declarar nada. La condición `Ready` del nodo pasa a `Unknown` si el controlador de nodos «no ha sabido del nodo en los últimos `node-monitor-grace-period` (por omisión, **50 segundos**)». Es el plazo de detección, y es el centro de la sección.

Mientras esos 50 segundos corren, el plano de control cree que el nodo está bien. Sus Pods figuran como `Running` y `Ready`, sus direcciones siguen en los `EndpointSlice`, y los Services les siguen repartiendo peticiones. Cuando el plazo vence, ocurren dos cosas distintas:

1. El nodo pasa a `NotReady` (`Unknown`), y los Pods que vivían ahí dejan de contar como listos; sus direcciones se marcan `ready: false` en los `EndpointSlice`, y el Service deja de usarlas. **Aquí termina la ventana de falla para el tráfico.**
2. El nodo recibe la mancha `node.kubernetes.io/unreachable` con efecto `NoExecute`. Los Pods que viven ahí tienen, de fábrica, una tolerancia a esa mancha de **300 segundos**: la documentación de «Taints and Tolerations» dice que Kubernetes agrega solo las tolerancias de `not-ready` y `unreachable` con `tolerationSeconds=300`, y que por eso los Pods «permanecen unidos a los nodos durante 5 minutos después de detectarse uno de estos problemas». Pasado ese plazo, los Pods se desalojan y el ReplicaSet crea reemplazos en otro nodo. **Aquí termina la ventana de capacidad**, y tarda mucho más que la de falla.

Conviene separar las dos ventanas porque se confunden. La de **falla** (peticiones que se pierden) dura desde que el nodo cae hasta que el clúster se entera: unos 50 segundos. La de **capacidad** (servicio con una réplica menos) dura 5 minutos más, hasta que los reemplazos nacen. Esta lección mide la primera, que es la que sienten tus usuarios. La segunda no se midió, porque el nodo se vuelve a encender antes de que venza.

#### 9.12.2 El experimento

El guion elige el nodo que va a apagar con una condición: tiene que ser un nodo que **tenga una réplica** del `revisor` y que **no** sea donde vive el Pod `depurar`, que es desde donde salen las peticiones (si se apagara el nodo del cliente, la medición moriría con él). Con dos réplicas repartidas, uno de los dos nodos de trabajo cumple. Después lanza **dos** sondeos a la vez, con una petición cada 2 segundos y un solo hilo, durante 100 segundos:

- el primero, tal cual: `./sondeo.sh 100 2 1`;
- el segundo, con reintentos del cliente: `./sondeo.sh 100 2 1 --retry 3 --retry-all-errors`.

`--retry 3` le pide a `curl` que reintente hasta 3 veces una petición que falló, y `--retry-all-errors` extiende «falló» a cualquier error, incluidos los tiempos de espera; el manual de `curl` describe la espera entre reintentos: primero un segundo, y luego «duplica el tiempo de espera» en cada uno. El manual llama a `--retry-all-errors` el «mazo» de los reintentos y desaconseja usarlo por omisión; aquí es un experimento controlado contra un servicio que sabemos que es seguro repetir (`GET /salud`). Con una petición idempotente (que se puede repetir sin efectos) los reintentos son inocuos; con una que no lo es, serían un riesgo.

Diez segundos después de lanzar los sondeos, `docker stop` detiene el contenedor del nodo, que es lo más parecido que tiene kind a «se cayó la máquina»: el `kubelet` y todo lo que corre dentro dejan de existir de golpe. La lección espera 25 segundos y pregunta dos cosas: cómo ve el clúster el nodo, y qué dicen los `EndpointSlice` de las direcciones del `revisor`.

```text
$ ./sondeo.sh 100 2 1 &                                     # sin reintentos, empieza a las 17:34:53
$ ./sondeo.sh 100 2 1 --retry 3 --retry-all-errors &       # con reintentos
(pausa de 10 s: ambos sondeos ya corren)

$ docker stop curso-k8s-l9-worker
curso-k8s-l9-worker
(nodo apagado a las 17:35:04)
(espera de 25 s: el nodo ya no contesta, pero el clúster todavía no lo sabe)
[+ 25s desde docker stop] curso-k8s-l9-worker Ready
```

A los 25 segundos de apagado, el nodo todavía dice `Ready`. El clúster no sabe nada. Y la prueba de que sigue sin saberlo está en los destinos:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=true nodo=curso-k8s-l9-worker
(el nodo pasó a NotReady a los 57 s de docker stop)
```

Los dos destinos del `revisor` figuran `ready=true`, **incluido el que vive en el nodo apagado** (`nodo=curso-k8s-l9-worker`). Cualquier petición que el Service le reparta a esa dirección va a un Pod que ya no existe. Esa es la causa de las fallas, escrita en una línea.

El guion consulta cada 3 segundos el estado del nodo hasta verlo `NotReady`, y entonces pregunta de nuevo:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=false nodo=curso-k8s-l9-worker
```

El nodo pasó a `NotReady` a los 57 segundos de apagado (el plazo de la documentación es de 50; el resto suma hasta 5 segundos del ciclo del controlador, `node-monitor-period`, y 3 de la consulta del guion; además, el último latido del nodo pudo ser anterior al apagado). Y ahora el destino del nodo caído figura `ready=false`: el clúster dejó de repartirle tráfico. Ese es el momento en que acaba la ventana de falla.

#### 9.12.3 Lo que midieron los sondeos

```text
# resultado SIN reintentos (los segundos cuentan desde el inicio del sondeo; docker stop fue en +10):
      7  código 000  curl rc=28  versión -
     35  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +21 +25 +29 +38 +42 +60 +64
peticiones=42 fallidas=7

# resultado CON reintentos de curl:
      1  código 000  curl rc=28  versión -
     31  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +37
peticiones=32 fallidas=1
```

Una aclaración sobre el encabezado: el guion anota «+10», que es la pausa que programó antes de apagar el nodo. La hora impresa dice que el nodo quedó apagado 11 segundos después de arrancar el sondeo, porque `docker stop` tardó cerca de un segundo. Los cálculos que siguen usan 11.

El sondeo **sin reintentos** hizo 42 peticiones en 100 segundos, no las 50 que cabrían en un ritmo de una cada 2 segundos, porque cada petición que falla ocupa los 2 segundos completos de su tiempo de espera además de la pausa. Fallaron 7, todas con `curl 28` (tiempo agotado, no conexión rechazada: el destino ya no existía). Los segundos de las fallas, contados desde el inicio del sondeo, son `+21 +25 +29 +38 +42 +60 +64`. Como `docker stop` se dio en el segundo 11 del sondeo, restando se obtiene cuánto tardó cada una después del apagado: de 10 a 53 segundos. La última falla, a los 53 segundos del apagado, cae justo antes de la observación de `NotReady` a los 57: las siete fallas cayeron entre 10 y 53 segundos después del apagado (medido al terminar cada petición). Que no se vieran más no prueba que el Service ya hubiera dejado de usar el destino muerto: con una petición cada 2 segundos y la mitad de ellas cayendo, según el modelo, en la réplica viva, unas cuantas seguidas pueden acertar sin que nada haya cambiado. Lo que sí se midió es que el destino pasó a `ready=false` cuando el nodo figuró `NotReady`, a los 57 segundos.

Eso son 7 fallas de 42, el 17 %. Esa cifra mezcla la ventana de falla con el resto de los 100 segundos del sondeo, así que no dice «el servicio falla una de cada seis veces»: dice lo que pasó en este experimento. Lo que explica las fallas es que, durante la ventana (hasta 57 segundos, hasta que el destino pasó a `ready=false`), **uno de los dos destinos del Service estaba muerto**, y el Service reparte entre sus destinos sin saber cuál está muerto, así que una parte de las peticiones de ese periodo iba a parar a la réplica que ya no existía. Con dos réplicas y un nodo muerto, esa parte sería de alrededor de la mitad; con cuatro réplicas repartidas, sería de alrededor de una cuarta parte; con diez, de una décima. Esa proporción (una réplica sobre N) es un modelo, no una medición de esta corrida: lo medido es 7 de 42, pero es lo que explica por qué «más réplicas repartidas» acorta el daño sin acortar el tiempo.

El sondeo **con reintentos** hizo 32 peticiones y fue más lento (cada reintento espera 1, 2 y 4 segundos antes de intentarlo otra vez). Falló una, a los 37 segundos, de 32: una falla frente a siete del otro sondeo, a cambio de que algunas respuestas tardaran más. Es una sola ronda, de tamaño pequeño y con menos peticiones que la otra: sugiere que los reintentos ayudan, pero no alcanza para prometer cuántas peticiones se recuperan. Es la segunda palanca: **reintentos en el cliente**. Funcionan porque la siguiente vez que `curl` pregunta, el Service puede escoger la réplica viva, y no funcionan si el destino es el mismo (por ejemplo, con una sola réplica).

Después, el estado del clúster en el momento de levantar el nodo:

```text
$ kubectl get nodes
NAME                         STATUS     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready      control-plane   29m   v1.37.0
curso-k8s-l9-worker          NotReady   <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready      <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          114s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          112s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

Con el nodo `NotReady`, los dos Pods del `revisor` siguen figurando `Running`, incluido el del nodo apagado: el clúster todavía no los desaloja, porque la tolerancia de 300 segundos no ha vencido. Y no los desalojará: el nodo se vuelve a encender.

```text
$ docker start curso-k8s-l9-worker
curso-k8s-l9-worker

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready    control-plane   29m   v1.37.0
curso-k8s-l9-worker          Ready    <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready    <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS      AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0             2m16s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   1 (21s ago)   2m14s   10.244.1.4    curso-k8s-l9-worker    <none>           <none>
```

El nodo vuelve a `Ready`, y el Pod que vivía en él sigue ahí: se reinició el contenedor (`RESTARTS 1`), no se creó otro Pod, y cambió de dirección de red (`10.244.1.4` en lugar de `10.244.1.33`), pero es el mismo Pod. En esta corrida el nodo regresó mucho antes de los 300 segundos y sus Pods se quedaron.

#### 9.12.4 Qué acorta la ventana y qué no

| Palanca | ¿Acorta? | Por qué |
|---|---|---|
| **Más réplicas, repartidas entre nodos** | acorta el *daño*, no el tiempo | con N réplicas repartidas, el modelo del reparto espera una de cada N en la muerta (cálculo, no medición) |
| **Reintentos en el cliente** | sí, para peticiones seguras de repetir | la segunda vez puede tocar una réplica viva (medido arriba) |
| **Bajar `node-monitor-grace-period`** (en el plano de control) | sí, a cambio de falsas alarmas | el clúster declara caído a un nodo que solo se retrasó |
| **Las sondas de disponibilidad** | no | las corre el `kubelet` del propio nodo caído, que ya no reporta nada |
| **`tolerationSeconds`** | no | decide cuándo se reponen los Pods, no cuándo dejan de recibir tráfico |

Las dos últimas filas son las que más se creen y las que menos funcionan, y por eso el Ejercicio 4 las pone a prueba. Una sonda de disponibilidad (la `readinessProbe` de la Lección 5) saca un Pod de los destinos del Service cuando falla, pero quien hace la pregunta es el `kubelet` de *ese* nodo. Si el nodo entero está apagado, no hay `kubelet` que pregunte ni que reporte; el clúster solo puede esperar a que se venza el plazo de detección. Y `tolerationSeconds` es el plazo de gracia antes de desalojar los Pods de un nodo ya declarado `unreachable`, o sea, una cuenta que empieza *después* de la detección: mientras más corto, antes se reponen los Pods, pero no sacan antes a los destinos muertos del Service.

Bajar `node-monitor-grace-period` es la única palanca que ataca el tiempo, y cuesta falsas alarmas (no conviene bajarlo mucho: tiene que ser varias veces mayor que la frecuencia con la que el `kubelet` reporta; revisa la bandera en la referencia del `kube-controller-manager` de tu versión): un nodo con un retraso de red de diez segundos se declararía caído, sus Pods se marcarían como no listos y el Service dejaría de usarlos sin razón. Es una bandera del `kube-controller-manager`, que en kind vive dentro del contenedor del nodo de control; no es algo que se cambie con `kubectl`, y esta lección no lo toca.

Contestado el director, con lo medido en esta corrida: **con dos réplicas, siete de 42 peticiones (el 17 %) se perdieron durante la ventana de un nodo caído**, cuya última falla cayó 53 segundos después del apagado y que acabó cuando el destino pasó a `ready=false`, a los 57. Por el reparto del Service esperaríamos que alrededor de la mitad de las peticiones de esa ventana cayera en la réplica muerta (es un cálculo, no una medición). Con reintentos en el cliente hubo una falla de 32, pero una sola ronda no basta para prometer cuántas se recuperan. Cuando el nodo regresa, el clúster se recompone solo.

#### 9.12.5 Después del experimento: el `<unknown>` del autoescalador

La última pregunta de la corrida es si todo quedó como los archivos dicen, y la respuesta tiene un detalle que pertenece a esta lección:

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           24m
deployment.apps/revisor   2/2     2            2           24m

NAME                                          REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          21m

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     21m
```

Con `sin diferencias con los archivos`, el clúster y la carpeta coinciden: todo lo que se hizo con comandos (`set image`, `patch`, `scale`, `rollout undo`) se deshizo o se volvió a aplicar. Y en el HPA, `TARGETS` dice `cpu: <unknown>/50%`. Es la misma palabra que sale a veces en los primeros segundos de 9.5.2, y conviene saber leerla, porque es la pregunta más común sobre autoescaladores: **`<unknown>` significa «no sé cuánto consumen los Pods»**, y tiene tres causas distintas:

1. **`metrics-server` no contesta.** Es la causa de 9.2. Se comprueba con `kubectl get apiservice v1beta1.metrics.k8s.io`: si dice `False`, es el medidor.
2. **Los Pods no tienen `requests` de CPU.** Sin ellos no hay contra qué calcular el porcentaje, y la documentación dice que el autoescalador no hará nada con esa métrica. Se comprueba con `kubectl describe pod`.
3. **Los Pods son nuevos y todavía no tienen su primera lectura.** Se ve en los eventos del HPA (`kubectl describe hpa`) como `FailedGetResourceMetric … no metrics returned from resource metrics API`, el mismo aviso que 9.6 mostró en los primeros segundos de los Pods nuevos, y se quita solo.

En este final, la tercera es la candidata: la corrida levantó el nodo apagado, esperó 20 segundos y capturó el estado; el Pod del `revisor` de ese nodo se reinició un instante antes (`RESTARTS 1`) y aún no tenía lectura. La medición no distingue esa causa de la primera, porque no se consultó el `APIService` en ese momento ni se comprobó en qué nodo corría `metrics-server` (si corría en el nodo apagado, sería la primera); lo que sí se puede decir es cómo distinguirlas. Si fuera la tercera, bastaría esperar unos segundos; si no, el `<unknown>` se queda. El hábito: ante un `<unknown>`, primero `get apiservice`, luego `describe pod` buscando los `requests`, y luego el reloj.

## El hábito de seguridad de la lección: límites al escalado, y actualizaciones que no tumban el servicio

La tabla de hábitos del curso le asigna a esta lección una frase con dos mitades: **límites al escalado** y **las actualizaciones no tumban el servicio**. Se comprueban con el clúster delante.

**Límites al escalado.** Un autoescalador convierte *carga* en *recursos*: más peticiones, más réplicas, más CPU y memoria reservadas. Eso es justo lo que se quiere frente a un lunes a las 9:00, y es justo lo que un atacante, o un error, puede aprovechar. Un cliente que manda peticiones en bucle (el Job `carga` de la lección es uno, a escala pequeña) le cuesta al servicio cada vez más réplicas. Sin techo, el límite lo pone el clúster entero, y un servicio mal portado deja sin recursos a los demás. Hay tres frenos en capas, de lo más cercano a lo más general:

1. **El techo del propio autoescalador.** `maxReplicas: 6`. Con los `requests` de la Lección 5, seis réplicas reservan `6 × 50m = 300m` de CPU y `6 × 32Mi = 192Mi` de memoria, un número que puedes escribir y discutir, en lugar de «lo que haya». En la corrida de esta lección el autoescalador no llegó a ese techo: la carga de un Job de `curl` en bucle se contuvo en cuatro réplicas. El techo es una barandilla; no se probó que detenga nada, y esa distinción cuenta.
2. **Quién puede generar la carga.** La red cerrada de la Lección 7 deja pasar hacia el `revisor` únicamente a los Pods con la etiqueta `acceso-revisor: permitido` y a los Envoy de la puerta. El Job `carga` lleva esa etiqueta a propósito; sin ella, sus peticiones no llegarían y el autoescalador no vería nada. Quien controla la puerta controla quién puede subir la factura de CPU.
3. **El presupuesto del espacio de nombres.** Existen objetos (`ResourceQuota`, `LimitRange`) que ponen un tope **total** de CPU, memoria y número de Pods a todo un espacio de nombres, de modo que un autoescalador mal configurado no pueda pasarse de ahí aunque su propio techo sea alto. La Lección 5 los nombró y los dejó fuera del curso; en un clúster compartido son la capa que de verdad protege a los vecinos.

Hay además un hábito para quien escala con `metrics-server`: la bandera `--kubelet-insecure-tls` de 9.2 existe solo en este laboratorio. Conviene escribirlo donde lo vea quien herede el archivo (el comentario de `metrics-server/kustomization.yaml` lo dice), porque una bandera de laboratorio que se copia a otro clúster es un hueco de seguridad con apariencia de configuración.

**Las actualizaciones no tumban el servicio.** Lo que se hizo para cumplirlo, y qué tanto lo cumple, es el contenido de 9.9 y de 9.11:

| Pieza | Qué impide | Dónde se mide |
|---|---|---|
| `maxUnavailable: 0` con `maxSurge: 1` | que haya menos réplicas que las deseadas durante el reemplazo | 9.9 |
| `preStop` con `sleep` | que lleguen peticiones a una réplica que ya cerró su puerta | 9.9 |
| `PodDisruptionBudget` | que un mantenimiento voluntario saque más réplicas de las que el servicio aguanta | 9.11 |
| reparto con `topologySpreadConstraints` | que una sola máquina concentre todas las réplicas | 9.4 y 9.11 |

Fíjate en que la frase de la tabla de hábitos dice «no tumban», no «no pierden nada». Lo medido en 9.9 dice cuánto se pierde con y sin cada pieza, y esa cifra, con su incertidumbre, es lo que se le entrega a quien pregunta. Una promesa de «cero» que nadie midió es peor que una cifra pequeña que sí.

Y una disciplina más: la lección actualiza con `kubectl set image` y `kubectl patch`, comandos *imperativos*, porque son el camino corto para medir. En un proyecto real, el cambio se escribe en el archivo, se revisa y se aplica con `kubectl apply -k .`, para que lo que corre en el clúster y lo que está en el repositorio sean lo mismo. El final de la corrida lo comprueba con `kubectl diff -k .`: «sin diferencias con los archivos».

## Lo que se hace mal

**Dejar `replicas` en el Deployment que gobierna un HPA.** Cada `apply` le devuelve al número el valor del archivo y desbarata lo que el autoescalador decidió. Se quita del manifiesto.

**Un HPA sobre Pods sin `requests` de CPU.** El porcentaje se mide contra los `requests`; sin ellos, el autoescalador no tiene con qué calcular y no hace nada.

**Copiar `--kubelet-insecure-tls` a un clúster real.** Es la salida rápida para que `metrics-server` arranque en un laboratorio. En un clúster con más gente, la solución es que los certificados de los `kubelet` estén firmados por la autoridad del clúster.

**Creer que el HPA reacciona a una diferencia de unos puntos.** Dentro del 10 % de tolerancia no hace nada. Y al bajar, no usa lo que ve hoy, sino lo más alto que recomendó en la ventana.

**Una meta de CPU muy alta (90 %).** Cuando el autoescalador reacciona, el servicio ya está saturado, y las réplicas nuevas tardan en nacer.

**`ScheduleAnyway` cuando lo que se necesita es una garantía.** Es una preferencia: el planificador la rompe si no encuentra mejor lugar.

**Un reparto por topología sin `nodeTaintsPolicy: Honor` en un clúster con un nodo de control manchado.** Funciona con dos réplicas y deja la tercera `Pending`.

**Creer que el reparto se mantiene solo.** Se aplica al programar un Pod; un mantenimiento puede dejar las réplicas juntas y nada las separa sin un reemplazo.

**Actualizar sin una pausa antes de apagar.** Una réplica vieja cierra su puerta mientras la red todavía le manda peticiones.

**Concluir «sin fallas» de un solo sondeo corto.** Una ronda sin fallas no demuestra que no las haya; con tres rondas de cada variante, lo medido en 9.9 muestra que las fallas aparecen y desaparecen.

**Creer que `rollout status` significa «ya no queda nada viejo contestando».** Termina cuando el Deployment cumple lo que se le pidió (las réplicas deseadas de la versión nueva están listas), no cuando el último Pod viejo acabó su `preStop`. Se mira `deletionTimestamp`.

**Un `PodDisruptionBudget` que no deja perder ninguna réplica.** El `drain` se queda reintentando y el mantenimiento no avanza. El presupuesto tiene que dejar margen.

**Un PDB sin su espacio de nombres.** Un objeto con `-f` y sin `-n` se crea donde apunte el contexto, y un PDB en el espacio equivocado protege a nadie. Se lee el mensaje `created` y se comprueba con `get pdb -n revisor`.

**Contar con las sondas para acortar la caída de un nodo.** Las corre el `kubelet` del nodo caído; no pueden reportar nada.

**Confiar en que el clúster se entera de inmediato de una caída.** Hay una ventana de detección, y las peticiones que caen en ella se pierden.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden y con el estado en que quedó tras 9.12. Antes de cada comando que cambia algo, `ctx` debe dar éxito. `correr.sh` recorre la lección, no los ejercicios; sus soluciones citan lo medido en la lección o lo calculan, y lo dicen. **Antes** de correr o calcular cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — La fórmula, a mano

Con la meta del 50 %, `minReplicas: 2` y `maxReplicas: 6`, calcula qué haría el autoescalador en cada caso, y di si la tolerancia lo detiene:

a) 2 réplicas con un uso promedio del 63 %.
b) 3 réplicas con un uso promedio del 46 %.
c) 4 réplicas con un uso promedio del 90 %.
d) 6 réplicas con un uso promedio del 20 %, un minuto después de que el uso bajó.

Después compara (a) y (b) con la columna `TARGETS` y los eventos de 9.6.

### Ejercicio 2 — Quién manda

Sin mirar 9.8, escribe qué número de réplicas crees que tendrá el Deployment 40 segundos después de `kubectl scale deployment/revisor -n revisor --replicas=1`, y de qué evento del HPA te darás cuenta. Corre el comando y compruébalo.

### Ejercicio 3 — Tu propio sondeo

Corre `./sondeo.sh 45 0 4` mientras haces `kubectl set image` entre `1.6.0` y `1.6.1`, tres veces con el `preStop` de la carpeta. Anota por ronda las peticiones, las fallas y el tipo de cada falla (`curl 7` o `curl 28`). Quita el gancho con `kubectl patch` (el comando de 9.9.6) y repite. Compara tus totales con los de la lección y explica, en tres frases, por qué los tuyos pueden diferir y qué conclusión sí sostienen. Para separar el efecto de la pausa del efecto del momento, alterna las variantes (una ronda con pausa, una sin, otra con...) en lugar de hacer todas las de una y luego todas las de la otra. Al terminar, vuelve a `apply -k .`.

### Ejercicio 4 — Defiende la decisión

Un compañero dice: «las sondas de disponibilidad ya sacan a una réplica caída del Service, y `tolerationSeconds` es el plazo de detección de un nodo, así que con bajarlo a 5 segundos el corte del nodo se acaba». En cinco frases como máximo, dile qué pasa en realidad cuando un nodo se apaga sin avisar, qué mide cada uno de esos dos ajustes, y qué sí acortaría la ventana y a qué precio.

## Soluciones

### Solución 1

Es cálculo, no medición, salvo donde se dice.

a) **2 réplicas, 63 %.** Razón 1.26, fuera de 0.9 a 1.1. `ceil(2 × 1.26)` = `ceil(2.52)` = **3**. Sube a 3. (En 9.6, con 72 % y 2 réplicas, pidió 3 por la misma regla.)

b) **3 réplicas, 46 %.** Razón 0.92: dentro de la tolerancia. **No hace nada.** Aunque no existiera la tolerancia, `ceil(3 × 0.92)` = `ceil(2.76)` = 3, el mismo número. (En 9.6, con 4 réplicas y 46 %, se quedó en 4: la misma situación.)

c) **4 réplicas, 90 %.** Razón 1.8. `ceil(4 × 1.8)` = `ceil(7.2)` = 8. Pero `maxReplicas` es 6, así que el HPA se queda en **6**. Lo anotaría en la condición `ScalingLimited`, la misma que 9.7 muestra por el piso, ahora por el techo; ese caso no se midió en esta corrida porque la carga nunca llegó al techo. Este es el caso del techo: sin `maxReplicas`, serían 8.

d) **6 réplicas, 20 %, un minuto después de que bajó el uso.** Razón 0.4. `ceil(6 × 0.4)` = `ceil(2.4)` = 3. La cuenta dice 3, pero la ventana de 60 segundos dice que se usa la recomendación **más alta** de los últimos 60 segundos: si hace 59 segundos la recomendación era de 6, sigue siendo 6 un instante más. Baja cuando esa recomendación sale de la ventana.

### Solución 2

Medido en `correr.salida.txt`:

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

**Dos réplicas, otra vez.** El Deployment quedó en 2/2 a los 40 segundos, y el último evento del HPA lo dice: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`, de hace `33s`. El `kubectl scale` bajó el campo `spec.replicas` a 1; el HPA, en su siguiente vuelta, vio que 1 era menos que el piso de 2 y lo corrigió. Con un autoescalador vivo, el número de réplicas es suyo. Lo que se cambia es el HPA.

### Solución 3

Depende de tu máquina, y en eso consiste el ejercicio. Los totales de esta corrida están en 9.9.8: con `preStop`, 5 fallas de 2,049 peticiones en cuatro rondas, todas `curl 28`; sin él, 29 de 1,569 en tres rondas, 6 de ellas `curl 7`. Lo que se puede decir, y lo que no:

- **Tus totales no van a coincidir con los de aquí**, porque dependen de cuánta CPU tuvo tu cliente, de cuán cargada estaba tu máquina y de cuántas peticiones alcanzó a hacer cada ronda (aquí hubo rondas de 433 y de 612 peticiones en el mismo tiempo).
- **Lo que sí debe repetirse** es la forma: las fallas sin pausa se agrupan en los segundos que siguen al `set image`, hay conexiones rechazadas (`curl 7`) solo sin pausa, y con pausa las rondas dan pocas fallas, con rondas en cero y otras con algunas aisladas.
- **Lo que tu medición no sostiene**: un porcentaje exacto, ni la frase «con `preStop` no se pierde nada». Si una de tus rondas con pausa dio cero, no significa que la pausa elimine las fallas; significa que esa ronda no vio ninguna.
- Si tus rondas con pausa no se distinguen de las rondas sin ella, la conclusión honesta es que esa máquina, con ese cliente, no tiene resolución para ver la diferencia. No que la pausa no sirva.

### Solución 4

Una respuesta posible: «Cuando un nodo se apaga sin avisar, el clúster no se entera de inmediato: espera `node-monitor-grace-period`, 50 segundos por omisión, a que el nodo reporte. Durante ese tiempo, los destinos de los Pods del nodo siguen marcados como listos y el Service les reparte peticiones que se pierden; en la corrida de la lección se perdieron 7 de 42, y la última falla fue 53 segundos después del apagado. Las sondas de disponibilidad no ayudan porque las hace el `kubelet` de ese nodo, que está apagado. `tolerationSeconds`, de 300 segundos por omisión, es el plazo que espera el clúster *después* de declarar el nodo inalcanzable antes de reponer sus Pods, así que bajarlo repone antes los Pods pero no saca antes a los destinos muertos del Service. Lo que sí ayuda es tener más réplicas repartidas (por el reparto, cabe esperar que caiga en la muerta una petición de cada N), reintentos en el cliente para peticiones que se pueden repetir, y, a costa de falsas alarmas, bajar `node-monitor-grace-period` en el plano de control.»

## Borrar el clúster

Cuando termines los ejercicios, borra el clúster de la lección. Con él se van MetalLB, Envoy Gateway, `metrics-server`, el Pod `depurar` y todo lo demás:

```text
$ kind delete cluster --name curso-k8s-l9
Deleting cluster "curso-k8s-l9" ...
Deleted nodes: ["curso-k8s-l9-control-plane" "curso-k8s-l9-worker2" "curso-k8s-l9-worker"]
(borrar tardó 2 s)

$ kind get clusters | grep -c curso-k8s-l9
0
```

Después borra los `token.txt` y la carpeta temporal del `kubeconfig`, que guarda la credencial de administrador del clúster que acabas de borrar. El `rm -rf` es peligroso si la variable está vacía o apunta a otro lado, así que va protegido con un `case` que solo lo deja correr si la ruta es la que creó `mktemp` en 9.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 9.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l9.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt punto-de-partida/token.txt
```

Comprueba además que no quedó ningún contenedor de cliente (`docker ps -a --filter name=curso-k8s-l9` no debe mostrar nada) y que el nodo que apagaste en 9.12 no quedó apagado: si borraste el clúster con el nodo detenido, `kind delete cluster` también lo quita. Si creaste una red de Docker propia para correr varias lecciones a la vez, se borra después del clúster, y solo esa: `docker network rm <tu-red>`. La red `kind` normal no se toca.

## Cómo sé que lo logré

- [ ] Ante `error: Metrics API not available` dices qué falta (un contestador de la API de métricas), y ante `x509: cannot validate certificate for … because it doesn't contain any IP SANs` dices qué pasa y qué arregla la bandera, y por qué es solo de laboratorio.
- [ ] Calculas a mano las réplicas que pedirá el HPA con `ceil(actuales × medida ÷ meta)`, aplicas la tolerancia del 10 % y lo comprobaste contra la columna `TARGETS` y los eventos `SuccessfulRescale`.
- [ ] Explicas por qué el Deployment ya no lleva `replicas` y qué mostró `kubectl diff` en `replicas: 3` → `replicas: 1`.
- [ ] Explicas por qué la ventana de bajada hace lenta la bajada y rápida la subida, y lo viste en el reloj.
- [ ] Lees el `FailedScheduling` de una restricción de reparto y dices por qué el nodo de control exige `nodeTaintsPolicy: Honor`.
- [ ] Corres `./sondeo.sh`, lees las tres columnas (código, salida de `curl`, versión) y dices qué distingue un `curl 7` de un `curl 28`.
- [ ] Dices, con tus números, cuánto se pierde en una actualización con y sin `preStop`, y qué límites tiene tu medición.
- [ ] Haces `rollout undo`, miras `deletionTimestamp` y dices por qué una petición pudo contestar con la versión que acabas de quitar.
- [ ] Provocas un `drain` bloqueado por un PDB que no deja margen, lo lees y lo corriges; y dices por qué tras un mantenimiento las réplicas pueden quedar juntas.
- [ ] Apagas un nodo, mides la ventana de falla, y dices qué la acorta (más réplicas repartidas, reintentos del cliente, un plazo de detección menor en el plano de control) y qué no (las sondas, `tolerationSeconds`).
- [ ] Corres `programas/09-escalar-y-actualizar/correr.sh > /tmp/mi-corrida-l9.txt 2>&1` y comparas contra `correr.salida.txt` (no redirijas a ese archivo: es la referencia) lo que no cambia: el `x509`, el `Metrics API not available` y el `MissingEndpoints`; `replicas: 3` → `replicas: 1` en el `diff`; el piso de 2 réplicas, una por nodo; el `FailedScheduling` con `didn't match pod topology spread constraints`; el HPA que sube al rebasar el 55 % y baja una ventana después; los dos modos de falla del sondeo; la vuelta atrás con una petición que aún contesta la versión quitada; el `drain` bloqueado por el PDB estricto; y el nodo que pasa a `NotReady` después de unos 50 segundos. Los números exactos de peticiones, los tiempos, los nombres de los Pods, las IP y el reparto de fallas entre rondas cambian en cada corrida: se observan, no se comparan.
- [ ] Provocas una actualización con una imagen que no existe, lees `ErrImagePull` y `ImagePullBackOff`, ves que el Deployment queda `UP-TO-DATE 1` con las réplicas viejas disponibles, y la regresas con `rollout undo`.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l9`, la carpeta temporal del `kubeconfig` ya no existe en `/tmp`, y no quedó ningún `token.txt`.

## Resumen

Responde sin mirar la lección:

1. ¿Qué falta en un clúster recién creado para que `kubectl top` funcione, y por qué `metrics-server` no arranca tal cual en kind?
2. ¿Cuál es la fórmula del HPA, contra qué se mide el porcentaje, y qué hace la tolerancia?
3. ¿Qué hace la ventana de bajada de 60 segundos, y por qué la subida no tiene una parecida?
4. ¿Por qué un Deployment gobernado por un HPA no debe llevar `replicas`?
5. ¿Qué dicen `maxSkew`, `DoNotSchedule` y `nodeTaintsPolicy: Honor`, y qué pasa sin el último?
6. ¿Qué dos cosas ocurren al mismo tiempo cuando se apaga un Pod, y qué cierra el `preStop`?
7. ¿Qué distingue una falla `curl 7` de una `curl 28`?
8. ¿Qué mostró el sondeo con y sin `preStop`, y qué no demuestra?
9. ¿Por qué puede contestar una versión que acabas de quitar con `rollout undo`?
10. ¿Qué es un PDB, a qué tipo de interrupciones aplica, y qué pasa con un `drain` cuando no hay margen?
11. ¿Cuánto tardó en notar el clúster el nodo caído, y qué acorta esa ventana?
12. ¿Qué pasa con el servicio cuando una actualización apunta a una imagen que no existe, y por qué?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Horizontal Pod Autoscaling»](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/): la fórmula `desiredReplicas`, el cálculo contra los `requests`, la tolerancia del 10 %, la ventana de estabilización de 300 segundos por omisión para bajar, la política de comportamiento por omisión y la recomendación de quitar `spec.replicas` del Deployment.
- [Kubernetes, «Pod Topology Spread Constraints»](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/): `topologyKey`, `maxSkew`, `whenUnsatisfiable`, `nodeTaintsPolicy`, `matchLabelKeys` con `pod-template-hash` y la limitación sobre Pods que se retiran.
- [Kubernetes, «Pod Lifecycle»](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): el flujo de terminación de un Pod: `preStop`, señal `TERM`, plazo, `KILL`, y el retiro de los destinos en paralelo.
- [Kubernetes, «Container Lifecycle Hooks»](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/): los tres tipos de gancho (Exec, HTTP, Sleep) y el plazo de apagado que incluye al `preStop`.
- [Kubernetes, «Deployments»](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxSurge`, `maxUnavailable`, `rollout undo`, `--to-revision`, la anotación `kubernetes.io/change-cause`, `revisionHistoryLimit` y la condición `Available`.
- [Kubernetes, «Disruptions»](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/): interrupciones voluntarias e involuntarias, el presupuesto que no evita las segundas pero las cuenta, y `kubectl drain` con la API de desalojo.
- [Kubernetes, «Specifying a Disruption Budget for your Application»](https://kubernetes.io/docs/tasks/run-application/configure-pdb/): `minAvailable` y `maxUnavailable`.
- [Kubernetes, «Safely Drain a Node»](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/): qué hace `kubectl drain` y por qué respeta los PDB; `--ignore-daemonsets`.
- [Kubernetes, «Node Status»](https://kubernetes.io/docs/reference/node/node-status/): la condición `Ready` en `Unknown` si el controlador de nodos no sabe del nodo en `node-monitor-grace-period` (50 segundos por omisión) y los latidos con `Lease`.
- [Kubernetes, «Taints and Tolerations»](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): las manchas `not-ready` y `unreachable`, y las tolerancias de 300 segundos que se agregan solas.
- [Kubernetes, «Resource metrics pipeline»](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/): la Metrics API, `metrics-server` y `kubectl top`; la CPU como tasa en una ventana.
- [metrics-server, README](https://github.com/kubernetes-sigs/metrics-server): los requisitos (certificado del `kubelet` firmado por la autoridad del clúster), `--kubelet-insecure-tls` «solo para pruebas», y los usos y no usos.
- [metrics-server, notas de la v0.9.0](https://github.com/kubernetes-sigs/metrics-server/releases/tag/v0.9.0): la versión que usa la lección.
- [Phil Pearl, «Kubernetes' dirty endpoint secret and Ingress»](https://philpearl.github.io/post/k8s_ingress/) (26 de julio de 2019): el retiro de destinos y el apagado ocurren al mismo tiempo; la pausa antes de apagar.
- [Go, `net/http`, `Server.Shutdown`](https://pkg.go.dev/net/http#Server.Shutdown): el apagado ordenado cierra primero los puertos abiertos y luego las conexiones inactivas.
- [Kubernetes, «Job»](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-termination-and-cleanup): `activeDeadlineSeconds` corre desde que se crea el Job y lo termina pase lo que pase.
- [Kubernetes, «kube-controller-manager»](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/): `--node-monitor-grace-period` (50 s) y `--node-monitor-period` (5 s).
- [curl, «man page»](https://curl.se/docs/manpage.html): `--retry`, `--retry-all-errors` y `--max-time`.
- [curl, «libcurl error codes»](https://curl.se/libcurl/c/libcurl-errors.html): los códigos 7 y 28.

---

**Siguiente:** [Lección 10 — El proyecto terminado y qué cambia en un clúster real](10-proyecto-final.md)
