# Lección 7 — Aislar: espacios, permisos y red

Viernes, 5:50 de la tarde. El equipo de datos lleva dos semanas pidiendo un lugar donde probar su servicio, y tu clúster de kind tiene espacio de sobra. Les dijiste que sí. A las 5:58 alguien del equipo de seguridad, que revisa lo que se publica antes del fin de semana, te escribe tres preguntas seguidas. Una: «¿un Pod de ellos puede leer el token del `revisor`?». Dos: «¿puede hablarle al `revisor` sin pasar por la puerta que tú publicaste?». Tres: «¿puede pedirle a la API del clúster la lista de Secrets?». Tú sabes que el `revisor` corre sin ser `root`, con sondas, con límites y detrás de una puerta con nombre. Pero esas tres preguntas no son sobre el `revisor`. Son sobre **lo que rodea al `revisor`**, y no tienes ni una respuesta medida. Son las 6:00. El equipo de datos ya pegó su primer Pod en el espacio `default`, que es donde vive todo lo tuyo.

La historia de la seguridad en la nube tiene muchas versiones de esta tarde. El 20 de febrero de 2018, la empresa de seguridad RedLock contó que había encontrado a Tesla con una consola de administración de Kubernetes abierta, sin protección. Según la propia RedLock, quien entró por ahí encontró credenciales de acceso a un depósito de datos de Amazon Web Services y puso a trabajar al clúster minando criptomonedas. Tesla respondió que el impacto parecía limitado a vehículos de prueba de ingeniería y que lo corrigió en cuestión de horas. La nota periodística que lo cuenta está en las fuentes de esta lección. Esa puerta abierta no es la que estudia esta lección. Lo que enseña es la pregunta que viene **después** de cualquier puerta abierta, por descuido o por error de otro equipo: una vez adentro, ¿hasta dónde llega lo que entró?

Hasta hoy, en tu clúster, la respuesta es «hasta donde llegue». Esta lección le pone paredes, en cuatro capas, y te enseña a **medir** cada una con el atacante más modesto que existe: un Pod con `curl` que no debería poder nada. La primera decide **dónde vive cada cosa** (el espacio de nombres). La segunda decide **qué se permite crear** (Pod Security Admission). La tercera decide **quién puede hacer qué con la API** (cuentas de servicio y RBAC), y la cuarta, **quién puede hablarle a quién** (las políticas de red). Cuando termines, las tres preguntas de las 5:58 tendrán respuesta con un comando al lado.

**Tiempo:** 2 × 45 min

**Qué construyes:** un espacio de nombres propio, `revisor`, con reglas: todo el proyecto vive ahí, el clúster rechaza cualquier Pod que no cumpla el nivel `restricted`, cada programa tiene su cuenta de servicio sin permisos y sin credenciales montadas (salvo una cuenta de solo lectura para mirar), y la red está cerrada por defecto con seis políticas que abren solo lo necesario

**Qué aprendes:** qué es un espacio de nombres y qué **no** aísla; Pod Security Admission con sus tres modos y sus tres niveles, y cómo se leen sus rechazos; `ServiceAccount`, `Role` y `RoleBinding` con permisos mínimos y cómo comprobarlos con `kubectl auth can-i`, con una petición suplantada y desde dentro de un Pod; `NetworkPolicy`: el modelo (abierto hasta que una política selecciona al Pod, y las reglas se suman), quién las aplica en kind (se mide), qué se rompe con «todo cerrado» y para qué sirve cada una de las seis aperturas, quitándolas una por una; y cómo una ruta de otro espacio se cuelga de la puerta (`allowedRoutes` y `ReferenceGrant`)

**De dónde vienes.** De la [Lección 6](06-entrar-al-cluster.md): el `revisor` corre con tres réplicas y el servicio de prueba con una, con sondas, `requests` y `limits`; MetalLB y Envoy Gateway están instalados dentro del clúster; la puerta es un `Gateway` llamado `revisor` con su `HTTPRoute`; y hay un `Service` `LoadBalancer` directo, `revisor-publico`, que esta lección retira. Todo vive en el espacio `default`. De la [Lección 5](05-salud-recursos-apagado.md) traes que las sondas las hace el `kubelet` del nodo, un dato que hoy decide si la red cerrada tumba o no los Pods. De la [Lección 3](03-services-dns.md), el Pod `depurar`, el DNS del clúster y que una consulta de nombre es tráfico de red como cualquier otro. Y de la [Lección 2](02-pods-deployments.md), el `securityContext` que desde el primer manifiesto cumple, sin que lo supieras, el nivel `restricted`: hoy el clúster empieza a exigirlo.

**Qué no hace esta lección.** No cifra el tráfico: la puerta sigue hablando HTTP plano, y dentro del clúster los Pods tampoco cifran lo que se dicen. No instala otro complemento de red: el curso planeaba instalar Calico si la red de kind no aplicaba las políticas, y la sección 7.5 mide que sí las aplica, así que no hace falta. No limita cuántos recursos puede crear un espacio de nombres (`ResourceQuota` y `LimitRange`, que la [Lección 5](05-salud-recursos-apagado.md) nombró) ni instala políticas de admisión propias. No guarda datos ni programa tareas: eso es la [Lección 8](08-datos-y-tareas.md), que va a necesitar de esta lección dos cosas, una cuenta de servicio sin credenciales para la tarea y la etiqueta `acceso-revisor: permitido` para que la tarea pueda hablarle al `revisor`. Y tampoco es una auditoría de seguridad de un clúster real: la sección del hábito de seguridad dice, con medidas, lo que esto defiende y lo que no.

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1, la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, **MetalLB v0.16.1** y **Envoy Gateway v1.9.2**, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l7`. La máquina fue una Mac con procesador ARM (`arm64`) y Docker Engine 29.2.1 dentro de una máquina virtual Ubuntu 24.04.4 (Colima). La primera línea de `correr.salida.txt` registra lo que el guion puede medir: `Docker 29.2.1 en Ubuntu 24.04.4 LTS (arm64)`; que la máquina anfitriona sea una Mac con Colima no lo ve el guion. **No** fue Linux Mint, que es el sistema de referencia del curso. **Esta corrida usó una red de Docker propia**, `curso-k8s-red-l7`, con la subred `172.27.0.0/16`, porque en la misma máquina corrían a la vez otras lecciones con su propio MetalLB y dos MetalLB con el mismo rango en la misma red se pisan (lo viste en la Lección 6). Por eso las direcciones de los nodos y de la puerta salen aquí como `172.27.…`. En tu Mint, con la red `kind` normal, la puerta recibe `172.18.255.200` y los nodos cuelgan de `172.18.0.0/16`; el resto de las salidas no cambia. `correr.sh` hace las dos cosas: con la red `kind` por omisión, y con una red propia si le dices cuál con `CURSO_RED` y `CURSO_SUBRED`; en los dos casos comprueba que la subred sea exactamente la que esperas y se detiene si no lo es (con una red propia, antes de crear el clúster; con la red `kind`, justo después de crearlo). Lo demás que cambia en tu máquina: la arquitectura, los sufijos de los nombres, las edades, el nodo de cada Pod, el nombre del Secret (el token es nuevo en cada corrida) y los milisegundos. El recorrido completo está en [`programas/07-aislar-permisos-red/`](../programas/07-aislar-permisos-red): `correr.sh` crea el clúster, le carga las dos imágenes, instala la plataforma de la Lección 6, deja todo como lo dejó esa lección, recorre esta en orden, corre los Ejercicios 1 a 3 y borra el clúster. La corrida completa tardó 26 minutos y 9 segundos, larga porque la máquina estaba cargada con otros clústeres y porque la lección espera a la red; crear el clúster y esperar a que estuviera listo fueron 39 segundos, instalar la plataforma 411 y borrarlo 1, y el disco de Docker estaba al 79 % al empezar y al 77 % al terminar. Las esperas de la instalación y de la puerta (`speaker`, `Programmed`, el Pod `viejo`) llevan plazos holgados (480, 360 y 300 segundos) porque en una máquina cargada las imágenes tardan en bajar; si en la tuya una espera agota su plazo, no sigas a ciegas: repítela, y mira con `kubectl get pods -A` qué falta. Su salida es `correr.salida.txt`; necesita internet (los manifiestos de MetalLB y de Envoy Gateway se descargan de sus lanzamientos, fijados a su versión). Las esperas están a la vista: donde el guion espera, la salida lo dice con un `kubectl wait`, un `rollout status` o un `sleep`. Usa el puerto 18087 de tu máquina para un `port-forward` y se detiene antes de empezar si ese puerto ya está ocupado.

## Al terminar vas a poder

- Explicar qué aísla un espacio de nombres (los nombres y el alcance de los permisos) y qué no (la red), y demostrarlo con un Pod de un espacio que le habla a un Service de otro.
- Mudar el proyecto de `default` a un espacio propio con `kubectl apply -k`, y distinguir lo que vive dentro de un espacio de lo que vale para todo el clúster.
- Poner un espacio de nombres en el nivel `restricted` con sus etiquetas, fijar la versión de la política, y leer renglón por renglón el rechazo de un Pod que no la cumple.
- Provocar un Deployment que se crea pero se queda sin Pods por Pod Security Admission, y encontrar el motivo en los eventos del ReplicaSet.
- Escribir un `Role` y un `RoleBinding` de solo lectura, comprobar lo que permiten y lo que niegan con `kubectl auth can-i` y con una petición real desde un Pod, y explicar por qué el `revisor` no lleva credenciales montadas.
- Cerrar la red de un espacio con una política, medir qué se rompe (incluido el DNS y la puerta), abrir solo lo necesario y decir, para cada una de seis políticas, qué dejaría de funcionar si falta.
- Explicar con qué condición una `NetworkPolicy` «cerrada por defecto» protege algo, y comprobarla en tu clúster.
- Colgar una ruta de otro espacio de la puerta, y distinguir `allowedRoutes` (quién puede colgarse del Gateway) de `ReferenceGrant` (quién puede ser destino de una ruta).

## El porqué antes del cómo

Imagina un edificio de oficinas con un solo pasillo largo y todas las puertas sin llave. Alguien puso rótulos en las puertas (`datos`, `finanzas`, `revisor`) y se ve ordenado. Pero el rótulo no cierra nada: cualquiera que entre al edificio puede abrir cualquier puerta. Eso es hoy tu clúster. Los espacios de nombres que ya conoces son los rótulos. Esta lección le pone llaves, un reglamento y puertas con cerradura, y lo hace por capas, porque cada capa responde una pregunta distinta y falla de una manera distinta:

1. **¿Dónde vive cada cosa?** El **espacio de nombres** (*namespace*). Agrupa objetos, hace que dos equipos puedan usar el mismo nombre sin chocar y es la unidad a la que se le pegan permisos y reglas. No es una pared de red: se mide en 7.5.
2. **¿Qué se permite crear?** **Pod Security Admission**. Es un guardia en la puerta del `kube-apiserver` que revisa cada Pod que quiere nacer en un espacio y lo rechaza si no cumple el nivel que ese espacio exige. Protege contra el Pod mal escrito, no contra el Pod que ya está corriendo.
3. **¿Quién puede hacer qué con la API?** **Cuentas de servicio y RBAC**. Cada programa que corre en el clúster tiene una identidad, y cada identidad tiene una lista (por omisión, vacía) de verbos que puede aplicar a ciertos objetos.
4. **¿Quién puede hablarle a quién?** **Políticas de red**. Hoy todo Pod puede hablarle a todo Pod. Una política cambia eso Pod por Pod, y solo funciona si la red del clúster las aplica.

Las capas se complementan porque protegen contra cosas distintas. PSA evita que alguien (o un descuido tuyo) cree un contenedor con privilegios de más. RBAC limita lo que hace un programa **con la API**. La red limita lo que hace **con los demás Pods**. Y el espacio de nombres es el lugar donde las tres se aplican. Si falta una, las otras no la cubren: un Pod `restricted` sin política de red sigue pudiendo hablarle a todos, y una red cerrada con una cuenta de servicio generosa deja que un Pod comprometido le pida a la API todo lo que ese permiso alcance.

La lección tiene cinco partes de conceptos y después las secciones de siempre:

1. **El clúster de la lección** (7.1), con la plataforma de la Lección 6 y el punto de partida.
2. **Un espacio de nombres propio** (7.2): qué es, qué contiene y la mudanza.
3. **Pod Security Admission** (7.3): modos, niveles, etiquetas y el rechazo que se aprende a leer.
4. **Cuentas de servicio y permisos mínimos** (7.4): `ServiceAccount`, `Role`, `RoleBinding`, `auth can-i`, y una petición real desde dentro de un Pod.
5. **La red** (7.5): el modelo, quién la aplica, sin reglas, todo cerrado, las aperturas y para qué sirve cada una.

Este es el destino. Al final de 7.5, un Pod con la etiqueta correcta puede hablarle al `revisor`, un Pod sin ella no, y las dos respuestas salen de comandos que puedes repetir:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

## Si no traes las imágenes del curso de Docker

Esta lección usa las mismas dos imágenes de las Lecciones 3 a 6: `curso-docker-revisor:1.6.0` y `curso-docker-prueba:1.0.0`. Comprueba que las tienes:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para la otra, el mismo comando con `curso-docker-prueba:1.0.0`. Si te falta alguna, la [Lección 3](03-services-dns.md) dice cómo construir las dos desde el repositorio del curso de Docker. Esta lección no le pide nada nuevo a ninguna de las dos. Los Pods de apoyo (`depurar`, `intruso` y `lector`) usan la imagen de `curl` fijada por su huella, como en las lecciones anteriores; cada nodo la descarga de internet la primera vez.

## Los conceptos

### 7.1 El clúster de la lección

#### 7.1.1 Crear, con la guarda de contexto

Esta lección crea su propio clúster, `curso-k8s-l7`, con la configuración de tres nodos de la Lección 1. Hasta aquí, en las lecciones anteriores, la comprobación del contexto era un renglón que copiabas delante de cada comando. Hoy se vuelve una función, para que sea corta y no se te olvide. Créalo así, desde la raíz del repositorio del curso:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L7_TMP="$(mktemp -d /tmp/curso-k8s-l7.XXXX)"
export KUBECONFIG="$L7_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: si abres otra terminal, la necesitas

# La guarda: se escribe una vez y va delante de cada comando que cambia algo.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l7 ] || { echo "contexto equivocado: no sigo"; return 1; }; }

# curso-k8s-l7 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l7 --config programas/07-aislar-permisos-red/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l7

# Desde aquí, todo se ejecuta dentro de la carpeta de la lección:
cd programas/07-aislar-permisos-red
```

La función `ctx` hace una sola cosa: compara el contexto activo de `kubectl` con `kind-curso-k8s-l7`. Si coincide, no imprime nada y termina bien, y el `&&` deja pasar al comando que sigue. Si no coincide, imprime «contexto equivocado: no sigo» y termina con error, y el `&&` **corta la cadena**: el comando que cambia algo no se ejecuta. A partir de aquí, **todo comando de esta lección que cambia algo** (`apply`, `delete`, `patch`, `label`, `run`, `exec` que borra…) se escribe así: `ctx && kubectl apply -k .`. En las salidas que siguen, el renglón que empieza con `$` muestra solo el comando de `kubectl`, sin el `ctx &&`, para que quepa; el guion `correr.sh` hace la misma comprobación antes de **cada** `kubectl`, incluidas las lecturas, y se detiene si el contexto no es el de la lección. La razón de tanto cuidado la conoces desde la Lección 1: un `delete -k` en el contexto equivocado borraría objetos de otro clúster, y esta lección borra y recrea bastantes.

Dos comprobaciones de convivencia, las mismas de la Lección 6 (con una red propia se hacen antes de crear el clúster; con la red `kind` por omisión, que nace con el primer clúster, justo después de crearlo): la red `kind` debe ser `172.18.0.0/16` (de ahí sale el rango de MetalLB) y nadie debe contestar ya en `172.18.255.200`. Si otro clúster tuyo con MetalLB está vivo, espera a que termine. `correr.sh` las hace y se detiene si fallan; en esta corrida las hizo contra la red propia, `curso-k8s-red-l7`, que la sección «Sobre las corridas» explica.

```text
$ kubectl config current-context
kind-curso-k8s-l7

$ kubectl get nodes -o wide | awk '{print $1, $2, $3, $6}' | column -t
NAME                        STATUS  ROLES          INTERNAL-IP
curso-k8s-l7-control-plane  Ready   control-plane  172.27.0.4
curso-k8s-l7-worker         Ready   <none>         172.27.0.2
curso-k8s-l7-worker2        Ready   <none>         172.27.0.3
```

Los tres nodos viven en la red de Docker de la corrida (`172.27.0.x`; en tu Mint, `172.18.0.x`). `kubectl wait` y `kubectl get` no cambian nada, así que no necesitan la guarda; todo lo demás sí.

#### 7.1.2 La plataforma de la Lección 6, en tres pasos

La Lección 6 dejó dos instalaciones que no son del `revisor` sino del clúster: MetalLB y Envoy Gateway. Esta lección las necesita porque el proyecto incluye un `Gateway`. Se instalan igual que allá, con el orden que aprendiste: plataforma, espera, proyecto. Los comandos son los mismos de la sección 6.9, y la salida muestra cada espera:

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=480s | tail -1
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io crd/referencegrants.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
(en esta corrida el rango del archivo se cambió a 172.27.255.200-172.27.255.250, dentro de la red curso-k8s-red-l7)
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met
```

Dos cosas que ya sabes y una que cambió. Ya sabes que hay que esperar al `controller` de MetalLB antes de darle el rango (el *webhook* tiene que escuchar) y que el rango y la clase `eg` se aplican al final. Lo que cambió es la espera de los CRD: esta vez incluye `referencegrants.gateway.networking.k8s.io`, un tipo de Gateway API que el Ejercicio 3 usa y que viene en el mismo paquete que instaló Envoy Gateway.

Sobre el renglón entre paréntesis de `kubectl apply -f infra/metallb-pool.yaml`: el archivo del curso trae el rango `172.18.255.200-172.18.255.220`, el de tu Mint. En esta corrida, `correr.sh` cambió ese rango, **con `sed` y sobre la marcha**, a `172.27.255.200-172.27.255.250`, que cae dentro de la red propia. Es el único cambio: el archivo del repositorio no se tocó. En tu máquina se aplica tal cual.

#### 7.1.3 El punto de partida: la Lección 6, en `default`

La carpeta `punto-de-partida/` trae, sin cambiar una coma, los manifiestos con los que terminó la Lección 6. Ya estás en la carpeta de la lección. El token es de mentira y no se versiona; se genera en cada corrida con el `umask` que ya conoces, para que nazca con permiso `0600`, y se copia a la carpeta de la lección porque la `kustomization.yaml` de las dos lo pide:

```bash
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
```

Los paréntesis y el `umask 077` son la costumbre de la Lección 4: el archivo se crea cerrado desde el primer byte, no se crea abierto y se cierra después. Ahora, con el `revisor`, `prueba`, el `Service` público y la puerta en `default`, esto es lo que el clúster sabe del estado «antes»:

```text
$ /bin/ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=360s
gateway.gateway.networking.k8s.io/revisor condition met
```

Con los nueve objetos creados y la puerta `Programmed`, el estado es el de la Lección 6. Faltan cuatro lecturas del «antes», las que van a cambiar al final de la lección:

```text
$ kubectl get namespaces
NAME                   STATUS   AGE
default                Active   11m
envoy-gateway-system   Active   11m
kube-node-lease        Active   11m
kube-public            Active   11m
kube-system            Active   11m
local-path-storage     Active   11m
metallb-system         Active   11m

$ kubectl get namespace default --show-labels
NAME      STATUS   AGE   LABELS
default   Active   11m   kubernetes.io/metadata.name=default

$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.serviceAccountName} | {.items[0].spec.automountServiceAccountToken} | {.items[0].spec.volumes[*].name}{"\n"}'
default |  | datos token kube-api-access-5q29h

$ kubectl auth can-i --list --as=system:serviceaccount:default:default | head -4
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
```

Se leen así. Los espacios de nombres son los de siempre más los dos de la plataforma (`envoy-gateway-system` y `metallb-system`); `default` no tiene más etiqueta que la que le pone el sistema, `kubernetes.io/metadata.name`: ninguna regla. El tercer comando pregunta, a la primera réplica del `revisor` (`.items[0]`; las tres son iguales porque salen de la misma plantilla), tres cosas: con qué cuenta corre (`default`), si pidió que no le montaran credenciales (el campo `automountServiceAccountToken` aparece **vacío**, o sea, no dijo nada) y qué volúmenes tiene: `datos`, `token` (el Secret de la Lección 4) y un tercero con nombre aleatorio, `kube-api-access-…`. Ese tercero es el que nadie pidió: **el clúster le montó al `revisor` una credencial para hablar con la API**, y el `revisor` no habla con la API. Es la primera cosa que esta lección quita. Y el último comando lista lo que la cuenta `default` puede hacer: casi nada (crear revisiones sobre sí misma, que son preguntas de «¿qué puedo hacer yo?»), pero no es lo mismo «casi nada» que «nada», y 7.4 mide la diferencia.


### 7.2 Un espacio de nombres propio

#### 7.2.1 Qué es y qué no es

Un **espacio de nombres** (*namespace*) es un grupo con nombre dentro del clúster. La [documentación de espacios de nombres](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) lo dice en una frase: los espacios de nombres «proporcionan un mecanismo para aislar grupos de recursos dentro de un solo clúster», y los nombres de los recursos tienen que ser únicos **dentro** de un espacio, no entre espacios. Eso trae tres consecuencias prácticas, que son las que importan hoy:

- **Los nombres no chocan.** El equipo de datos puede tener su propio Service llamado `revisor` en su espacio sin pisar el tuyo. Y el DNS lo refleja: lo que la Lección 3 llamó `revisor` a secas es en realidad `revisor.<espacio>.svc.cluster.local`, y desde otro espacio hay que escribirlo completo.
- **Los permisos tienen alcance.** Un `Role` (7.4) vale dentro de un espacio. Dar permiso sobre los Pods de `revisor` no da permiso sobre los de `default`.
- **Las reglas se pegan a un espacio.** Las etiquetas de Pod Security Admission (7.3) y las políticas de red (7.5) se aplican al espacio donde viven.

Lo que **no** hace, aunque el nombre y los tutoriales lo sugieran: no cierra la red. La misma página no menciona aislamiento de red, porque no existe: un Pod de un espacio le puede hablar a un Service de otro con solo escribir su nombre completo. 7.5.3 lo mide, y por eso la cuarta capa existe.

No todo vive dentro de un espacio. Lo puedes preguntar al clúster, que sabe cuáles tipos pertenecen a uno y cuáles valen para todo:

```text
$ kubectl api-resources --namespaced=false -o name | grep -E '^(nodes|namespaces|persistentvolumes|storageclasses|clusterroles|clusterrolebindings|gatewayclasses\.)'
namespaces
nodes
persistentvolumes
gatewayclasses.gateway.networking.k8s.io
clusterrolebindings.rbac.authorization.k8s.io
clusterroles.rbac.authorization.k8s.io
storageclasses.storage.k8s.io

$ kubectl api-resources --namespaced=true -o name | grep -E '^(pods|services|secrets|serviceaccounts|roles|rolebindings|networkpolicies)(\.|$)'
pods
secrets
serviceaccounts
services
networkpolicies.networking.k8s.io
rolebindings.rbac.authorization.k8s.io
roles.rbac.authorization.k8s.io
```

La primera lista, tipos **sin** espacio: los propios espacios de nombres, los nodos, los volúmenes persistentes, las clases de almacenamiento, los roles de alcance de clúster (`clusterroles`) y sus enlaces, y la `GatewayClass` que creaste en la Lección 6. La segunda, tipos **con** espacio: los Pods, los Services, los Secrets, las cuentas de servicio y, en el grupo de RBAC y de red, los `roles`, los `rolebindings` y las `networkpolicies` de esta lección. La regla para recordarlo: lo que describe **una carga de trabajo** vive en un espacio; lo que describe **la infraestructura que todas comparten** no. Por eso la `GatewayClass` `eg` no se muda hoy, y por eso MetalLB y Envoy Gateway, que son plataforma, siguen en `metallb-system` y `envoy-gateway-system`. Solo se muda el proyecto.

#### 7.2.2 Lo que cambia en los manifiestos

La mudanza se reduce a pocos cambios, casi todos en la `kustomization.yaml`. Léela completa, con su comentario:

```yaml
# kustomization.yaml — Lección 7. Se aplica con: kubectl apply -k .
# Todo va al espacio de nombres «revisor» (namespace: revisor, abajo), que nace
# aquí mismo (namespace.yaml) en el nivel «restricted» de Pod Security.
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Requiere la infraestructura de la Lección 6 (MetalLB y Envoy Gateway) ya
# instalada: sin sus CRD, Gateway y HTTPRoute no existen.
# revisor-publico.yaml (el LoadBalancer directo de la 6) ya no está: desde la
# Lección 7 la única puerta es el Gateway. El estado de la Lección 6 vive en
# punto-de-partida/, y se retira con: kubectl delete -k punto-de-partida
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

La línea nueva que más hace es `namespace: revisor`. Kustomize la aplica como una transformación: a **todo** objeto con espacio que aparece en `resources` le escribe `metadata.namespace: revisor`, sin que lo repitas en cada archivo. Por eso los Deployments, los Services y el `Gateway` no cambiaron una letra de su `metadata`. Los otros cambios son tres archivos nuevos en la lista: `namespace.yaml` (el espacio mismo, con sus etiquetas, 7.3), `cuentas.yaml` (las cuentas y los permisos, 7.4) y `red.yaml` (las seis políticas, 7.5). Y los dos Deployments declaran ahora su cuenta de servicio y le piden al clúster que no les monte credenciales:

```yaml
    spec:
      serviceAccountName: revisor
      automountServiceAccountToken: false
```

(Es un fragmento: son dos líneas de `revisor-deployment.yaml`, que 7.4 explica. El de `prueba` dice `prueba`.) Fíjate también en lo que **no** está en la lista: `revisor-publico.yaml`, el `LoadBalancer` directo de la Lección 6. Su propio comentario lo anunciaba: desde hoy la única puerta hacia afuera es el `Gateway`. El archivo se conserva en `punto-de-partida/` como referencia.

#### 7.2.3 La mudanza

Un espacio nuevo no «mueve» objetos; los objetos de un espacio no se pueden pasar a otro. Se **borran de uno y se crean en el otro**. Primero se retira el estado de la Lección 6 con el mismo `kustomization` que lo creó, y después se aplica la de esta lección. El token se queda: es el mismo archivo para las dos, y por eso el Secret generado conserva su nombre.

```bash
ctx && kubectl delete -k punto-de-partida
rm -f -- punto-de-partida/token.txt
ctx && kubectl apply -k .
```

```text
$ kubectl delete -k punto-de-partida
configmap "revisor-config-t6cm6872fk" deleted from default namespace
secret "revisor-token-mgc44f554f" deleted from default namespace
service "prueba" deleted from default namespace
service "revisor" deleted from default namespace
service "revisor-publico" deleted from default namespace
deployment.apps "prueba" deleted from default namespace
deployment.apps "revisor" deleted from default namespace
gateway.gateway.networking.k8s.io "revisor" deleted from default namespace
httproute.gateway.networking.k8s.io "revisor" deleted from default namespace

$ kubectl apply -k .
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
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

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba -n revisor --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Lee los dos primeros bloques de arriba abajo. El `delete -k` borra nueve objetos, y cada renglón dice **de dónde** los borra (`from default namespace`). El `apply -k` crea veinte: el espacio (`namespace/revisor`), las tres cuentas, el `Role` y su `RoleBinding`, el ConfigMap y el Secret con el hash de siempre, los dos Services, los dos Deployments, la puerta y la ruta, y las seis políticas de red. Fíjate en el orden: el espacio sale primero. Kustomize entrega los objetos con los espacios de nombres primero, y por eso no necesitaste dos pasos. Con los tipos de una plataforma nueva, como `Gateway` en la Lección 6, la espera sigue siendo tuya: ahí no es un asunto de orden de la lista sino de que el tipo exista.

¿Quedó todo donde debía?

```text
$ kubectl get namespace revisor -o go-template='{{range $k, $v := .metadata.labels}}{{$k}}={{$v}}{{"\n"}}{{end}}'
kubernetes.io/metadata.name=revisor
pod-security.kubernetes.io/audit=restricted
pod-security.kubernetes.io/audit-version=v1.37
pod-security.kubernetes.io/enforce=restricted
pod-security.kubernetes.io/enforce-version=v1.37
pod-security.kubernetes.io/warn=restricted
pod-security.kubernetes.io/warn-version=v1.37

$ kubectl get all -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rgh68    1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          2m52s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.130.233   <none>        9000/TCP   2m52s
service/revisor   ClusterIP   10.96.146.219   <none>        80/TCP     2m52s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           2m52s
deployment.apps/revisor   3/3     3            3           2m52s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       2m52s
replicaset.apps/revisor-5d6fd4d6bd   3         3         3       2m52s

$ kubectl get all -n default
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   14m

$ kubectl get gateway,httproute -n revisor
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.27.255.200   True         2m52s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               2m52s

$ kubectl wait --for=condition=Available deployment -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=revisor --timeout=180s
deployment.apps/envoy-revisor-revisor-b269644b condition met

$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-gateway-5fc4949dcb-k6s46                    1/1     Running   0          14m
pod/envoy-revisor-revisor-b269644b-867f46cd7d-rbkcf   2/2     Running   0          2m52s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-gateway                    ClusterIP      10.96.130.219   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   14m
service/envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       2m52s
```

`default` quedó con una sola cosa, el Service `kubernetes` que el clúster crea solo: el espacio está limpio. Todo el proyecto está en `revisor`, y la puerta lo atiende desde `envoy-gateway-system`, un tercer espacio: **la puerta no vive donde vive el proyecto**. Anótalo, porque la política de red de 7.5 tiene que dejarla pasar y eso se hace con una `namespaceSelector`. Y una comprobación desde fuera del clúster, como en la Lección 6, para ver que la mudanza no cerró la puerta:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Una última decisión de la lección. Con el proyecto ya mudado, el guion retira las seis políticas de red:

```text
$ kubectl delete -n revisor -f red.yaml
networkpolicy.networking.k8s.io "cerrado" deleted from revisor namespace
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace
networkpolicy.networking.k8s.io "prueba-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace
```

No es un error ni una prueba de que no sirven. Es para estudiar **una capa a la vez**. Las seis políticas están en la `kustomization.yaml` porque el estado final del proyecto las lleva, pero si estuvieran puestas mientras estudias Pod Security y RBAC, cada Pod de práctica nacería sin poder hablar con la API, y no sabrías si lo que ves lo causa una capa u otra. Vuelven en 7.5, con su explicación.

### 7.3 Pod Security Admission

#### 7.3.1 Qué es: un guardia en la puerta del `kube-apiserver`

Cuando haces `kubectl apply`, tu petición pasa por una cadena de controles antes de guardarse. Uno de ellos se llama **admisión**. La [documentación de Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) lo describe: es un controlador que revisa cada Pod que va a crearse contra un **estándar** (los *Pod Security Standards*), y decide según una etiqueta del espacio de nombres donde nacería. No instala nada: viene con el `kube-apiserver`. Se configura **con etiquetas del espacio**, y esas etiquetas tienen tres partes:

- **El modo**, que dice qué hacer con una violación. Hay tres: `enforce` («los Pods que violan la política se rechazan»), `audit` («se agrega una anotación al registro de auditoría, pero el Pod se permite») y `warn` («el usuario recibe una advertencia, pero el Pod se permite»). Un espacio puede usar uno, dos o los tres, y hasta con niveles distintos.
- **El nivel**, que dice cuánto se exige. Los [estándares de seguridad de Pods](https://kubernetes.io/docs/concepts/security/pod-security-standards/) definen tres. `privileged` es «deliberadamente abierto y completamente sin restricciones». `baseline` busca «facilitar la adopción para cargas de trabajo comunes» y a la vez impedir las escaladas de privilegios conocidas. `restricted` es una política «muy restringida», que sigue las prácticas actuales de endurecimiento.
- **La versión** (opcional), que fija a qué edición del estándar se compara el Pod. Cada versión de Kubernetes puede afinar lo que `baseline` y `restricted` piden; con `latest` el estándar se mueve con el clúster, y con `v1.37` queda fijo.

La etiqueta tiene esta forma: `pod-security.kubernetes.io/<MODO>: <NIVEL>` y, aparte, `pod-security.kubernetes.io/<MODO>-version: <VERSIÓN>`. Mira cómo quedó el espacio de la lección con las tres:

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

El espacio `revisor` usa **los tres modos al mismo nivel**, `restricted`, y los tres fijados a `v1.37`. Los tres juntos tienen sentido: `enforce` es el que protege (rechaza), `warn` es el que te avisa **al aplicar** un Deployment, antes de que falle (7.3.4), y `audit` deja huella en el registro de auditoría del `kube-apiserver`, que el curso no activa ni mide. La guía de la documentación para aplicar estos niveles a un espacio muestra el mismo reparto de papeles: `enforce` en el nivel que ya cumples y `audit` y `warn` en el nivel al que quieres llegar, para ver qué fallaría antes de exigirlo.

#### 7.3.2 Los tres niveles, medidos

Antes del espacio de la lección, los tres niveles frente a frente. Se crean dos espacios de prueba, uno `privileged` y uno `baseline`, y a cada uno (y a `revisor`) se le pide que acepte dos Pods, sin crearlos: `--dry-run=server` manda la petición completa al `kube-apiserver`, que la valida con todos sus controles de admisión y no guarda nada. El primer Pod pide `hostNetwork: true`, o sea, usar la red del nodo en lugar de la suya, algo que `baseline` ya prohíbe. El segundo es un Pod de `curl` escrito sin `securityContext`, como en un tutorial cualquiera.

```text
$ kubectl create namespace nivel-privileged
namespace/nivel-privileged created

$ kubectl create namespace nivel-baseline
namespace/nivel-baseline created

$ kubectl label namespace nivel-privileged pod-security.kubernetes.io/enforce=privileged
namespace/nivel-privileged labeled

$ kubectl label namespace nivel-baseline pod-security.kubernetes.io/enforce=baseline
namespace/nivel-baseline labeled

$ kubectl wait --for=create serviceaccount/default -n nivel-privileged --timeout=60s
serviceaccount/default condition met

$ kubectl wait --for=create serviceaccount/default -n nivel-baseline --timeout=60s
serviceaccount/default condition met
```

El `kubectl wait --for=create` es una espera que quizá no esperabas: cada espacio nuevo recibe su cuenta `default` unos instantes **después** de nacer, la crea un controlador, y un Pod pedido antes de que exista la cuenta se rechaza por otra razón (`serviceaccount "default" not found`). En una de las corridas de prueba de esta lección (sin salida guardada), sin esa espera, las seis pruebas de abajo fallaron con ese mensaje y no con el de seguridad. Por eso hoy la espera está a la vista.

```text
--- espacio nivel-privileged ---
$ kubectl run hostnet -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
pod/hostnet created (server dry run)

$ kubectl run sinreglas -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio nivel-baseline ---

$ kubectl run hostnet -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true)
[código de salida: 1]

$ kubectl run sinreglas -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio revisor ---

$ kubectl run hostnet -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "restricted:v1.37": host namespaces (hostNetwork=true), allowPrivilegeEscalation != false (container "hostnet" must set securityContext.allowPrivilegeEscalation=false), unrestrict
[código de salida: 1]

$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinr
[código de salida: 1]
```

Las salidas están recortadas a 260 caracteres con `cut` para que quepan; el mensaje completo lo ves en 7.3.3. Léelas como una tabla:

| Espacio | `hostNetwork: true` | Pod sin `securityContext` |
|---|---|---|
| `nivel-privileged` | creado (`server dry run`) | creado |
| `nivel-baseline` | **rechazado**: `host namespaces (hostNetwork=true)` | creado |
| `revisor` (`restricted`) | **rechazado**, y con más motivos | **rechazado** |

Tres cosas. Primera: `baseline` frena lo que se sabe peligroso (compartir la red del nodo) y deja pasar un Pod normal, escrito sin cuidado. `restricted` pide además las buenas prácticas, y por eso el mismo Pod sencillo que `baseline` acepta aquí se rechaza. Segunda: el mensaje de `nivel-baseline` dice `"baseline:latest"`, sin versión. Como ese espacio no fijó `enforce-version`, el estándar es el de la versión del clúster, **la que sea**; el de `revisor` dice `"restricted:v1.37"`, fijado. Si el clúster se actualiza, el primero puede empezar a rechazar lo que antes aceptaba; el segundo no cambia hasta que cambies la etiqueta. Tercera: el guion borra los dos espacios de prueba al terminar (`kubectl delete namespace`), que borra con ellos todo lo que tuvieran.

```text
$ kubectl delete namespace nivel-privileged nivel-baseline
namespace "nivel-privileged" deleted
namespace "nivel-baseline" deleted
```

#### 7.3.3 `restricted`, leído renglón por renglón

El Pod de práctica que se rechazó dos veces arriba es un Pod de `curl` normal. Ahora sin recortes, en el espacio de la lección:

```text
$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never -- sleep 60
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinreglas" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "sinreglas" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "sinreglas" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
[código de salida: 1]

$ kubectl get pods -n revisor -l run=sinreglas
No resources found in revisor namespace.
```

El mensaje tiene la forma «el Pod X no se puede crear: viola PodSecurity "restricted:v1.37": » seguida de una lista separada por comas, y cada elemento es una regla incumplida con el campo que la arregla entre paréntesis. Cuatro:

1. `allowPrivilegeEscalation != false`: el contenedor debe declarar `securityContext.allowPrivilegeEscalation=false`. Sin esa línea, un proceso dentro podría ganar más privilegios que su proceso padre (por ejemplo, ejecutando un programa con el bit *setuid*).
2. `unrestricted capabilities`: debe declarar `securityContext.capabilities.drop=["ALL"]`. Las *capabilities* de Linux son pedacitos de lo que antes solo hacía `root`; un contenedor sin pedir nada recibe un conjunto por omisión, y `restricted` exige quitarlo todo.
3. `runAsNonRoot != true`: el Pod o el contenedor debe declarar `runAsNonRoot=true`. No basta que la imagen *sea* de un usuario normal: el manifiesto debe **decir** que lo exige, para que el clúster rechace una imagen que un día cambie a `root`.
4. `seccompProfile`: debe declarar `seccompProfile.type` como `RuntimeDefault` o `Localhost`. `seccomp` es el filtro de llamadas al núcleo; el perfil del *runtime* bloquea las más peligrosas.

Y no se rechazó por una quinta, `readOnlyRootFilesystem`, que el curso pone desde la Lección 2: es buena práctica, pero **no** la exige el nivel `restricted`. Es la diferencia entre lo que el clúster impone y lo que tú te impones. Cada línea de esa lista es una de las cuatro que el `securityContext` del `revisor` lleva desde la Lección 2; por eso el `revisor` y `prueba` nacieron sin problema en este mismo espacio. Y el `get pods` lo confirma: `No resources found`. El rechazo es **antes** de crear: el Pod no existe, ni en estado de error.

#### 7.3.4 Qué se puede (y qué no) endurecer: `kube-system` y el `dry-run`

¿Por qué no poner `restricted` en todos los espacios, sin pensarlo? El mismo `--dry-run=server` que usaste con los Pods sirve para ver qué pasaría con una **etiqueta**: calcula contra los Pods que ya existen y avisa, sin cambiar nada. Se prueba con dos espacios:

```text
$ kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: coredns-559f6c778d-q8k29 (and 1 other pod): runAsNonRoot != true, seccompProfile
Warning: etcd-curso-k8s-l7-control-plane (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
Warning: kindnet-82j5f (and 2 other pods): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: kube-proxy-d6hbh (and 2 other pods): host namespaces, privileged, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
namespace/kube-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

Con `kube-system` hay cuatro advertencias, una por grupo de Pods, y todas empiezan con `Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"`: CoreDNS no declara `runAsNonRoot` ni `seccompProfile`; `etcd`, `kindnet` y `kube-proxy` usan la red del nodo (`host namespaces`) y piden volúmenes de tipo `hostPath` (`restricted volume types`), y `kube-proxy` además es *privileged*. Lo piden porque su trabajo es tocar el nodo. Por eso **un nivel no se aplica por moda**: se mide primero, y hay espacios (los del sistema) donde `restricted` no cabe. Y el mismo `--dry-run` en `revisor` dice `namespace/revisor not labeled (server dry run)` sin una sola advertencia: el proyecto ya cumple lo que exige.

¿Y los Pods que ya corrían cuando se pone la etiqueta? La documentación dice que, al agregar o cambiar una etiqueta `enforce`, el controlador prueba cada Pod del espacio contra la política nueva y devuelve las violaciones como advertencias. No dice qué le pasa al Pod. Se mide con un espacio de prueba: nace sin etiquetas, recibe un Pod que no cumple `restricted`, y **después** se le pone `enforce=restricted`.

```text
$ kubectl create namespace nivel-previo
namespace/nivel-previo created

$ kubectl wait --for=create serviceaccount/default -n nivel-previo --timeout=60s
serviceaccount/default condition met

$ kubectl run viejo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600
pod/viejo created

$ kubectl wait --for=condition=Ready pod/viejo -n nivel-previo --timeout=300s
pod/viejo condition met

$ kubectl label namespace nivel-previo pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "nivel-previo" violate the new PodSecurity enforce level "restricted:latest"
Warning: viejo: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/nivel-previo labeled

$ kubectl get pod viejo -n nivel-previo
NAME    READY   STATUS    RESTARTS   AGE
viejo   1/1     Running   0          21s

$ kubectl run nuevo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600 2>&1 | cut -c1-200
Error from server (Forbidden): pods "nuevo" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nuevo" must set securityContext.allowPrivilegeEscalati
[código de salida: 1]

$ kubectl delete namespace nivel-previo
namespace "nivel-previo" deleted
```

El renglón del `label` trae la advertencia del controlador, que nombra al Pod `viejo` y las reglas que viola. Y el `get pod` que sigue lo deja `Running`: **la etiqueta informó y no desalojó**. El Pod `nuevo`, pedido con el mismo manifiesto, se rechaza. Poner `enforce` no limpia un espacio; cierra la puerta para lo que llegue desde ese momento. Un Pod viejo que viola el nivel se queda hasta que se recree (por ejemplo, con un `rollout restart`), y entonces ya no puede nacer. Es una trampa de operación: en un espacio con `enforce`, un reinicio puede tumbar un Deployment que llevaba meses funcionando, si su plantilla nunca cumplió el nivel.

Otra prueba del mismo estilo, esta vez con el modo `warn`. Se le pide al `kube-apiserver`, sin aplicar el cambio, que quite una línea del `revisor` (el perfil `seccomp`) y diga qué opina:

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/securityContext/seccompProfile"}]' --dry-run=server
Warning: would violate PodSecurity "restricted:v1.37": seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/revisor patched

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}{"\n"}'
RuntimeDefault
```

El parche **se acepta** (`deployment.apps/revisor patched`, pero es `--dry-run=server`: no se guardó) y viene con una advertencia en una sola línea: `would violate PodSecurity "restricted:v1.37": seccompProfile …`. Eso es `warn`: avisa al que aplica, sin rechazar. El segundo comando confirma que el Deployment sigue diciendo `RuntimeDefault`. Y esa diferencia, «avisa» frente a «rechaza», es el siguiente error.

### El error que vas a ver

El error de esta lección es de los que más desconciertan, porque el comando sale **bien** y el servicio no aparece. Se provoca con `fig07_01.sin-reglas.yaml`, un **programa** que falla a propósito: un Deployment del `revisor` escrito como en un tutorial, sin `securityContext`.

```yaml
# fig07_01.sin-reglas.yaml — FALLA A PROPÓSITO: un Deployment del revisor escrito
# como en un tutorial cualquiera, SIN securityContext. La imagen ya corre sin ser
# root (usuario 65532), pero el manifiesto no lo DECLARA. En el espacio «revisor»
# (nivel restricted) el Deployment se crea con una advertencia y sus Pods no
# nacen: el ReplicaSet registra FailedCreate. Se borra con kubectl delete -f.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sinreglas
  labels:
    app: sinreglas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sinreglas
  template:
    metadata:
      labels:
        app: sinreglas
    spec:
      containers:
      - name: revisor
        image: curso-docker-revisor:1.6.0
        imagePullPolicy: IfNotPresent
        env:
        - name: REVISOR_SERVICIOS
          value: "prueba http://prueba:9000/ 2s"
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
```

La imagen sí corre sin ser `root` (usuario 65532), pero el manifiesto no lo declara, y eso es lo que el nivel `restricted` revisa. Se aplica en el espacio de la lección:

```text
$ kubectl apply -n revisor -f fig07_01.sin-reglas.yaml
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/sinreglas created

$ kubectl wait --for=condition=ReplicaFailure deployment/sinreglas -n revisor --timeout=120s
deployment.apps/sinreglas condition met

$ kubectl get deployment sinreglas -n revisor
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
sinreglas   0/1     0            0           1s

$ kubectl get replicaset -n revisor -l app=sinreglas
NAME                   DESIRED   CURRENT   READY   AGE
sinreglas-7c585c788d   1         0         0       1s

$ kubectl get pods -n revisor -l app=sinreglas
No resources found in revisor namespace.

$ kubectl describe replicaset -n revisor -l app=sinreglas | sed -n '/^Events:/,$p' | head -4
Events:
  Type     Reason        Age   From                   Message
  ----     ------        ----  ----                   -------
  Warning  FailedCreate  2s    replicaset-controller  Error creating: pods "sinreglas-7c585c788d-47khh" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Se lee en orden, del síntoma a la causa.

**Primero, lo que dijo `apply`.** Dos renglones: una advertencia (`Warning: would violate PodSecurity "restricted:v1.37": …`) y `deployment.apps/sinreglas created`. **Se creó.** El Deployment es un objeto, no un Pod, y no viola nada. La advertencia es el modo `warn`, que sí revisa la plantilla de Pod que el Deployment lleva dentro, para avisarte antes. Si tu terminal o tu *pipeline* no muestra las advertencias, aquí se te pasó el aviso. Esto es lo que dice la documentación: los modos `audit` y `warn` se aplican también a los recursos de carga de trabajo, pero **`enforce` no**: solo se aplica a los Pods resultantes.

**Segundo, el síntoma.** El `kubectl wait` espera una condición poco común, `ReplicaFailure`, que el Deployment activa cuando su ReplicaSet no puede crear réplicas, y la encuentra al instante. Después: `READY 0/1`, `UP-TO-DATE 0`, `AVAILABLE 0`. El ReplicaSet existe y pide 1 Pod, `DESIRED 1`, pero tiene `CURRENT 0`. Y `get pods` dice `No resources found`. El Deployment nunca falló en voz alta; simplemente no tiene Pods.

**Tercero, la causa.** Está en los eventos del ReplicaSet, no en los del Deployment ni en los del Pod (que no existe): `Warning FailedCreate … replicaset-controller Error creating: pods "sinreglas-…" is forbidden: violates PodSecurity "restricted:v1.37": …`. Es el mismo mensaje de 7.3.3, pero ahora lo recibe el controlador, que lo registra y lo reintenta. Por eso hay que buscar en el **ReplicaSet**.

**La corrección.** Se arregla el manifiesto, no el espacio: un `securityContext` como el del `revisor` y el servicio de prueba, con las cuatro líneas de 7.3.3. Aquí, como el Deployment no se va a usar, se borra.

```text
$ kubectl delete -n revisor -f fig07_01.sin-reglas.yaml
deployment.apps "sinreglas" deleted from revisor namespace
```

**El orden, cuando un Deployment no tiene Pods:**

1. `kubectl get deployment`: ¿`READY 0/N`?
2. `kubectl get replicaset -l app=…`: ¿`CURRENT` menor que `DESIRED`?
3. `kubectl describe replicaset`: los eventos, `FailedCreate`, y el motivo completo.
4. Si dice `PodSecurity`, no se baja el nivel del espacio; se arregla el manifiesto.


### 7.4 Cuentas de servicio y permisos mínimos

#### 7.4.1 Qué es una cuenta de servicio

Cuando tú haces `kubectl get pods`, la API sabe quién eres por tu `kubeconfig`. Cuando un **programa que corre dentro del clúster** le habla a la API (un controlador, una herramienta de despliegue, un servicio que necesita saber qué otros Pods existen), la API también necesita saber quién es. Esa identidad se llama **cuenta de servicio** (*ServiceAccount*). La [documentación](https://kubernetes.io/docs/concepts/security/service-accounts/) la define como «un tipo de cuenta no humana que, en Kubernetes, da una identidad distinta dentro del clúster». Tiene tres propiedades que importan aquí:

- **Es un objeto con espacio**, como un Pod. Se llama `revisor` en el espacio `revisor`, y su nombre completo para RBAC tiene la forma `system:serviceaccount:<espacio>:<cuenta>`, que para la cuenta `revisor` del espacio `revisor` queda `system:serviceaccount:revisor:revisor` (el nombre se repite porque coinciden). Lo vas a escribir en 7.4.3.
- **Todo espacio nace con una llamada `default`.** El clúster la crea solo (la sección 7.3.2 acaba de esperarla) y se la asigna a todo Pod que no pida otra. Por omisión no tiene permisos más allá del descubrimiento básico de la API.
- **Por omisión, el clúster monta sus credenciales en cada Pod.** La misma página: «por omisión, Kubernetes le da al Pod las credenciales de la cuenta asignada». Desde la versión 1.22 son un token de vida corta que se renueva solo, entregado como un volumen proyectado; antes era un Secret de larga vida. Eso es el volumen `kube-api-access-…` que viste en 7.1.3: el Pod puede leer su token en un archivo y presentarse con él ante la API.

El hecho del último punto es el importante. **Si un programa dentro de un Pod está comprometido, su primera pregunta es «¿qué puedo hacer con el token que tengo?»**, y esa credencial está montada aunque el programa nunca la use. Para el `revisor` y para `prueba`, que no le hablan a la API, es un riesgo sin ningún beneficio. Por eso los dos Deployments de la lección declaran `automountServiceAccountToken: false`. La [guía de cuentas de servicio](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) explica que se puede desactivar en la cuenta o en el Pod, y que si los dos dicen algo, manda el Pod.

#### 7.4.2 Los permisos: `Role` y `RoleBinding`

Una cuenta recién creada no puede nada. Los permisos se agregan con dos objetos. La [documentación de RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (control de acceso basado en roles) los separa así: un `Role` «contiene reglas que representan un conjunto de permisos», y los permisos son **puramente aditivos**: no hay reglas de «negar». Un `Role` «siempre fija permisos dentro de un espacio de nombres». Su pariente `ClusterRole` es lo mismo pero sin espacio, para recursos que no lo tienen (los nodos, por ejemplo) o para repetir un conjunto de reglas en varios espacios. Un `RoleBinding` es el pegamento: «otorga los permisos definidos en un rol a un conjunto de sujetos» (usuarios, grupos o cuentas de servicio), dentro de un espacio. Dos objetos y no uno porque el rol se escribe una vez y se puede ligar a muchas cuentas.

Cada regla de un `Role` tiene tres partes: `apiGroups` (el grupo de la API: `""` es el núcleo, donde viven los Pods y los Services; `apps` es donde viven los Deployments), `resources` (los tipos) y `verbs` (qué se puede hacer: `get` leer uno, `list` listar, `watch` quedarse escuchando cambios, y los que modifican, `create`, `update`, `patch` y `delete`). Léelo en `cuentas.yaml`, completo:

```yaml
# cuentas.yaml — Lección 7: cada carga con su cuenta, y ninguna con permisos que
# no necesita. El revisor y prueba no le hablan a la API: cero permisos y sin
# credenciales montadas. «observador» puede mirar y nada más.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: revisor
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prueba
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: observador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: observador
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: observador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: observador
subjects:
- kind: ServiceAccount
  name: observador
  namespace: revisor
```

Tres cuentas y un par de objetos de permisos. `revisor` y `prueba` son cuentas **sin permisos**: ningún `RoleBinding` las menciona, y ambas llevan `automountServiceAccountToken: false` también a nivel de cuenta. `observador` es la cuenta de lectura: el `Role` `observador` le da `get`, `list` y `watch`, solo esos tres verbos, sobre Pods, sus bitácoras (`pods/log`, un subrecurso), Services y eventos del núcleo, y sobre Deployments y ReplicaSets del grupo `apps`. Fíjate en lo que **no** está: Secrets (el token del `revisor` es un Secret), `create`, `update`, `patch`, `delete`, `exec` (`pods/exec` es otro subrecurso, y no se lista) y cualquier cosa fuera del espacio. La regla de diseño es «lo que necesita, y nada más», y se escribe nombrando cada recurso, sin comodines (`*`), porque un comodín incluye lo que un día agregue el clúster.

El `RoleBinding` dice a **quién** se le da: la cuenta `observador` del espacio `revisor`. Aun así, esta cuenta no la usa ningún Deployment de la lección. Existe para que se vea qué significa «solo lectura» con una cuenta de verdad, y para el Ejercicio 2.

```text
$ kubectl get serviceaccounts -n revisor
NAME         AGE
default      5m2s
observador   5m2s
prueba       5m2s
revisor      5m2s

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name'
POD                        CUENTA    AUTOMOUNT   VOLUMENES
prueba-6899c74865-rgh68    prueba    false       <none>
revisor-5d6fd4d6bd-6kb4k   revisor   false       datos,token
revisor-5d6fd4d6bd-jdmx8   revisor   false       datos,token
revisor-5d6fd4d6bd-pj8r9   revisor   false       datos,token
```

Se lee así: cuatro cuentas, no tres. La cuarta, `default`, la creó el clúster solo. Y la tabla de Pods dice, para cada uno, con qué cuenta corre, que `AUTOMOUNT` es `false` y qué volúmenes tiene: `datos` y `token` en el `revisor`, ninguno en `prueba`, y **ninguno de los dos tiene el `kube-api-access-…` de 7.1.3**. Comparado con el «antes», ese volumen desapareció.

```text
$ kubectl get role,rolebinding -n revisor -o wide
NAME                                        CREATED AT
role.rbac.authorization.k8s.io/observador   2026-10-21T22:52:57Z

NAME                                               ROLE              AGE    USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/observador   Role/observador   5m3s                    revisor/observador

$ kubectl describe role observador -n revisor
Name:         observador
Labels:       <none>
Annotations:  <none>
PolicyRule:
  Resources         Non-Resource URLs  Resource Names  Verbs
  ---------         -----------------  --------------  -----
  events            []                 []              [get list watch]
  pods/log          []                 []              [get list watch]
  pods              []                 []              [get list watch]
  services          []                 []              [get list watch]
  deployments.apps  []                 []              [get list watch]
  replicasets.apps  []                 []              [get list watch]
```

#### 7.4.3 Preguntar sin probar: `kubectl auth can-i`

¿Cómo sabes lo que una cuenta puede hacer? Se le pregunta a la API con `kubectl auth can-i`, que contesta `yes` o `no`. Para preguntar por **otra** identidad se usa `--as`, que hace que `kubectl` suplante a esa identidad en la petición; la cuenta de servicio se escribe con su nombre completo, `system:serviceaccount:<espacio>:<cuenta>`. (Suplantar es un permiso que tú tienes como administrador de tu clúster de kind; un usuario normal de un clúster real no lo tendría.) Primero el `revisor`, que no debe poder nada, y el `observador`, que debe poder leer:

```text
$ kubectl auth can-i --list -n revisor --as=system:serviceaccount:revisor:revisor | head -5
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
clustertrustbundles.certificates.k8s.io         []                                     []               [get list watch]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador
yes

$ kubectl auth can-i get pods --subresource=log -n revisor --as=system:serviceaccount:revisor:observador
yes
```

La lista del `revisor` no está vacía, y eso hay que leerlo con cuidado. Los cuatro renglones son permisos que casi toda identidad recibe por omisión. Tres son *revisiones sobre uno mismo*: `selfsubjectreviews` (¿quién soy?, según `kubectl explain`, devuelve la información de usuario que el `kube-apiserver` tiene de quien pregunta), `selfsubjectaccessreviews` (¿puedo hacer esto?, que es la pregunta que hace el propio `can-i`) y `selfsubjectrulesreviews` (¿qué acciones puedo hacer en este espacio?). El cuarto, `clustertrustbundles`, son paquetes de certificados raíz públicos; la descripción del tipo dice que todas las cuentas de servicio los pueden leer por omisión. Los roles que dan los primeros tres vienen con el clúster (`system:basic-user`, que la documentación describe como acceso de solo lectura a información básica sobre uno mismo, ligado al grupo `system:authenticated`). Ninguno es un permiso sobre **tus** objetos. La pregunta que importa, `get pods`, contesta `no`, con código de salida 1: `kubectl auth can-i` devuelve 0 cuando la respuesta es `yes` y 1 cuando es `no`, y eso sirve para usarla en un guion. El `observador` contesta `yes` a leer Pods y a leer sus bitácoras (`--subresource=log`). Ahora lo que **no** debe poder:

```text
$ kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get pods -n default --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]
```

Tres `no`: no puede borrar Pods (el `Role` no incluye `delete`), no puede leer Secrets (no está en la lista) y no puede leer Pods de `default` (el `Role` y el `RoleBinding` viven en `revisor`; un rol de espacio no cruza a otro). Es la prueba directa de que el espacio de nombres sí es la unidad de los permisos, aunque no lo sea de la red.

`can-i` pregunta; la petición de verdad confirma. Con `--as`, `kubectl` hace la operación como si fuera esa cuenta:

```text
$ kubectl get deployments -n revisor --as=system:serviceaccount:revisor:observador
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
prueba    1/1     1            1           5m5s
revisor   3/3     3            3           5m5s

$ kubectl delete pod -n revisor -l app=prueba --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): pods "prueba-6899c74865-rgh68" is forbidden: User "system:serviceaccount:revisor:observador" cannot delete resource "pods" in API group "" in the namespace "revisor"
[código de salida: 1]

$ kubectl get secrets -n revisor --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"
[código de salida: 1]
```

Listar Deployments funciona. Borrar un Pod y listar Secrets dan `Error from server (Forbidden)`, y vale la pena leer el mensaje completo, porque tiene la forma de los errores de RBAC y es lo que vas a ver el día que algo falle: `secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"`. Quién (`User "system:serviceaccount:revisor:observador"`), qué verbo y sobre qué (`cannot list resource "secrets"`), en qué grupo de la API (`""`, el núcleo) y en qué espacio. Con esas cinco piezas sabes exactamente qué regla agregar si el permiso era legítimo, o qué dejar como está si no. Un detalle: el verbo del segundo mensaje es `list`, no `get`; pediste «todos los Secrets» y eso es `list`. Leer uno por nombre es `get`. Los dos verbos están separados a propósito.

#### 7.4.4 Lo mismo, desde dentro de un Pod

Hasta aquí todo se probó suplantando desde tu terminal. Falta la prueba que más se parece a un ataque: un programa **dentro** de un Pod, con lo que el Pod tiene a la mano. Se usan tres Pods de apoyo, todos de `curl`: `depurar` (el de la Lección 3, con la etiqueta `acceso-revisor: permitido` que la red va a necesitar), `intruso` (igual pero **sin** esa etiqueta; es el Pod del equipo de datos de la escena) y `lector`, uno nuevo que lleva la cuenta `observador` **con el token montado**. Los tres cumplen `restricted`, como cualquier cosa que nazca en este espacio. Lee `fig07_04.lector.yaml`:

```yaml
# fig07_04.lector.yaml — un Pod que SÍ lleva credenciales: usa la cuenta «observador»
# y pide que se le monte su token (automountServiceAccountToken: true). Sirve para
# ver, desde dentro de un Pod, lo que el RBAC de cuentas.yaml permite y lo que no.
# Cumple «restricted». Se aplica con: kubectl apply -n revisor -f fig07_04.lector.yaml
apiVersion: v1
kind: Pod
metadata:
  name: lector
  labels:
    app: lector
spec:
  restartPolicy: Never
  serviceAccountName: observador
  automountServiceAccountToken: true
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: lector
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

Es una excepción deliberada a la regla de 7.4.1: `automountServiceAccountToken: true`, que es el valor por omisión escrito en voz alta. Existe para mostrar lo que un token montado permite. Léelo contra la lista de `intruso`, que usa la cuenta `default` **sin** token (`depurar` y `intruso` lo declaran apagado):

```text
$ kubectl apply -n revisor -f depurar.yaml -f intruso.yaml -f fig07_04.lector.yaml
pod/depurar created
pod/intruso created
pod/lector created

$ kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso pod/lector --timeout=180s
pod/depurar condition met
pod/intruso condition met
pod/lector condition met

$ kubectl exec -n revisor lector -- /bin/ls /var/run/secrets/kubernetes.io/serviceaccount
ca.crt
namespace
token
```

El `lector` tiene tres archivos en `/var/run/secrets/kubernetes.io/serviceaccount`: `ca.crt` (el certificado con el que reconocer a la API), `namespace` (su espacio) y `token` (su credencial). Con ellos, `curl` se presenta ante la API con el encabezado `Authorization: Bearer <token>`. La dirección es `https://kubernetes.default.svc`, el nombre del Service `kubernetes` de `default`, que es la puerta de la API para los Pods. Cuatro peticiones:

```text
$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 200

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "secrets %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets'
secrets 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods-default %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/default/pods'
pods-default 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets | grep -E "message|code"'
  "message": "secrets is forbidden: User \"system:serviceaccount:revisor:observador\" cannot list resource \"secrets\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

Un `200` y tres `403`. Con el token de `observador`, el `lector` **sí** puede listar los Pods de `revisor` (el permiso que le dimos), y **no** puede listar los Secrets del mismo espacio ni los Pods de `default`. El cuarto bloque es la misma petición de Secrets con la respuesta cruda filtrada: es el JSON de error de la API, con el mismo mensaje que viste con `--as`. Esto es lo que RBAC promete, pero visto desde el lado de quien ataca: un token robado de `observador` tiene el alcance del `Role` y ni un recurso más. Por eso el `Role` se escribe corto.

Y ahora el Pod que **no** tiene token:

```text
$ kubectl exec -n revisor intruso -- sh -c '/bin/ls /var/run/secrets/kubernetes.io; echo código=$?' 2>&1
ls: /var/run/secrets/kubernetes.io: No such file or directory
código=1

$ kubectl exec -n revisor intruso -- sh -c 'curl -s -k https://kubernetes.default.svc/api/v1/namespaces/revisor/pods | grep -E "message|code"'
  "message": "pods is forbidden: User \"system:anonymous\" cannot list resource \"pods\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

El directorio no existe: `ls: /var/run/secrets/kubernetes.io: No such file or directory`. El `intruso` no tiene ni siquiera una credencial que presentar. Si le habla a la API de todas formas (`curl -k`, que no verifica el certificado, solo para esta prueba), la API lo recibe como `system:anonymous`, la identidad de quien no se identifica, y le contesta `403`: `pods is forbidden: User "system:anonymous" cannot list resource "pods"`. Cero permisos y cero credenciales; es el estado que quieres para todo Pod que no le hable a la API. (Que la API conteste un `403` quiere decir que el `intruso` **sí llegó** a la API: lo único que lo frena aquí es RBAC. Lo que impediría que llegue siquiera es la red, y 7.5 lo mide.)


### 7.5 La red: abierta hasta que alguien la cierra

#### 7.5.1 El modelo, antes de tocar nada

La [documentación de políticas de red](https://kubernetes.io/docs/concepts/services-networking/network-policies/) describe el modelo con tres frases que conviene aprender de memoria, porque de ellas sale todo lo demás:

- **Por omisión, un Pod no está aislado.** «Por omisión, un Pod no está aislado para la salida; se permiten todas las conexiones salientes», y lo mismo para la entrada: «se permiten todas las conexiones entrantes». Este es el estado en que están hoy tus Pods.
- **Un Pod se aísla cuando una política lo selecciona.** «Un Pod está aislado para la salida si hay alguna `NetworkPolicy` que lo selecciona y tiene `Egress` en su `policyTypes`», y de forma equivalente para la entrada con `Ingress`. Las dos direcciones se aíslan por separado. Una política que solo dice `Ingress` no toca la salida.
- **Las políticas se suman.** «Las políticas de red no entran en conflicto; son aditivas.» Si varias políticas aplican a un Pod en una dirección, lo permitido es la **unión** de lo que cada una permite. El orden no importa. Y no existe una regla de «negar»: lo que ninguna permite está prohibido, pero solo para los Pods que ya están aislados.

Una política tiene cuatro partes: un `podSelector` (a qué Pods **del espacio** se aplica; `{}` significa todos), unos `policyTypes` (si aísla la entrada, la salida o las dos), y listas `ingress` y `egress` de lo que se **permite**, cada una con un `from` o un `to` (de dónde o hacia dónde) y unos `ports`. Y el `from` o el `to` pueden ser tres cosas: un `podSelector` (Pods de **este** espacio), un `namespaceSelector` (todos los Pods de los espacios elegidos) o, juntos en el mismo elemento, ambos (Pods elegidos de espacios elegidos). Un detalle que muerde: el `from` es una lista, y cada elemento de la lista es una alternativa (una **o**); lo que va dentro de un mismo elemento se combina con **y**.

Y la condición que importa más: la propia documentación advierte que «los clústeres deben usar un complemento de red que soporte `NetworkPolicy`» y que «crear un recurso `NetworkPolicy` sin un controlador que lo implemente no tiene efecto». El clúster guarda tu política sin quejarse, y el tráfico sigue pasando. Es una falla silenciosa. Por eso el plan del curso decía «si el complemento de red de kind no la aplica, se instala otro». Se mide, no se supone.

#### 7.5.2 ¿Quién las aplica en kind?

Los nodos de kind usan por omisión un complemento de red llamado `kindnetd` (la [configuración de kind](https://kind.sigs.k8s.io/docs/user/configuration/) lo describe como una implementación simple de red basada en complementos CNI estándar; *CNI* es la interfaz con la que Kubernetes le pide a un complemento que dé red a los Pods). Se le pregunta al clúster qué corre:

```text
$ kubectl get daemonset -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kindnet      3         3         3       3            3           kubernetes.io/os=linux   17m
kube-proxy   3         3         3       3            3           kubernetes.io/os=linux   17m

$ kubectl get daemonset kindnet -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
docker.io/kindest/kindnetd:v20260820-69b56db7
```

Hay un DaemonSet `kindnet` con un Pod por nodo, y su imagen es `kindest/kindnetd:v20260820-69b56db7`. Saber cuál es no dice si aplica políticas. Las notas de la versión [v0.24.0 de kind](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0) anuncian, entre sus puntos principales, «soporte de políticas de red usando `sigs.k8s.io/kube-network-policies`». Eso es lo que dice el papel. Lo que importa es lo que mide tu clúster, y para medirlo hace falta un testigo: dos Pods de `curl` que no están en la lista de nadie.

```text
$ kubectl apply -n default -f intruso.yaml
pod/intruso created

$ kubectl wait -n default --for=condition=Ready pod/intruso --timeout=180s
pod/intruso condition met

$ kubectl get pods -A -l 'app in (depurar,intruso,lector)' -L acceso-revisor
NAMESPACE   NAME      READY   STATUS    RESTARTS   AGE   ACCESO-REVISOR
default     intruso   1/1     Running   0          1s    
revisor     depurar   1/1     Running   0          14s   permitido
revisor     intruso   1/1     Running   0          14s   
revisor     lector    1/1     Running   0          13s   
```

Hay un `intruso` en `revisor` y otro en `default`: el del espacio propio es el Pod del equipo de datos de la escena; el de `default` es otro equipo cualquiera del clúster. Los dos nacieron sin la etiqueta `acceso-revisor`. `depurar` sí la tiene (`permitido`); `intruso` y `lector` no, y la tabla lo dice con la columna vacía. Eso importa en 7.5.4.

#### 7.5.3 Sin reglas: lo que el espacio de nombres NO aísla

Con las seis políticas retiradas (7.2.3), esto es lo que puede hacer el `intruso` de `revisor`, y lo que puede hacer el de `default`:

```text
$ kubectl get networkpolicy -n revisor
No resources found in revisor namespace.

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://prueba:9000/
sano

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez
ok

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

Se leen cuatro respuestas y las cuatro son malas noticias:

1. El `intruso` le habla al `revisor` y recibe su `/salud`. Sin el token no puede pedir el reporte (da `401`), pero llegó.
2. Le habla a `prueba:9000`, que no es de él, y recibe `sano`, el modo del servicio de prueba. Con un `POST` a `/modo/caido` lo podría poner en `caido`: el servicio de prueba **no tiene autenticación** y la red no lo protege.
3. Le habla a la API del clúster, a `/livez`, y contesta `ok`. Ese camino de salud responde sin credenciales a propósito (la documentación de RBAC lo llama información no sensible, el rol `system:public-info-viewer`), así que la respuesta no es un defecto de la API. Lo que importa es otra cosa: un Pod cualquiera tiene **ruta de red** hasta el `kube-apiserver` (por el Service `kubernetes`, puerto 443), y nadie se la quitó.
4. El `intruso` de `default` alcanza al `revisor` de `revisor` escribiendo el nombre completo del Service, `revisor.revisor.svc.cluster.local`. **Dos espacios de nombres distintos, y ni una pared entre ellos.** Esto es lo que la documentación de espacios de nombres no afirma y lo que muchos asumen.

Es la respuesta a la segunda pregunta de las 5:58, y no es la que querías: sí, un Pod del equipo de datos puede hablarle al `revisor` sin pasar por la puerta.

#### 7.5.4 Todo cerrado

La primera política cierra todo, sin ninguna apertura. Es un **programa** corto:

```yaml
# fig07_02.cerrado.yaml — la primera regla de red.yaml, sola: cierra la entrada
# y la salida de TODOS los Pods del espacio donde se aplica, sin ninguna apertura.
# Se aplica con -n revisor para ver qué se rompe (hasta el DNS), y después se
# completa con red.yaml. No forma parte de la kustomization.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

`podSelector: {}` selecciona todos los Pods del espacio, y `policyTypes: [Ingress, Egress]` los aísla en las dos direcciones. Como no hay listas `ingress` ni `egress`, no se permite nada. Se aplica y se mide lo mismo de antes:

```text
$ kubectl apply -n revisor -f fig07_02.cerrado.yaml
networkpolicy.networking.k8s.io/cerrado created

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- timeout 8 nslookup revisor.revisor.svc.cluster.local
;; connection timed out; no servers could be reached

command terminated with exit code 1
[código de salida: 1]

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Todo dejó de funcionar, y conviene separar tres señales que se parecen. `command terminated with exit code 28` es el código de `curl` para **tiempo agotado**: no hubo respuesta en los 3 segundos que le diste con `-m 3`. Un `curl` contra una política que descarta paquetes no recibe un rechazo, solo silencio. Es distinto de `connection refused` (código 7, que te contesta alguien que dice «aquí no hay nada» y que viste en las Lecciones 3 y 5) y de un `403` (que contesta alguien que sí te escuchó y te dijo que no). Hay tres tipos de «no» y se distinguen por el código. Segunda señal: `depurar`, el Pod **con** la etiqueta, tampoco llega. Todavía no abriste nada. Tercera: el `nslookup` también agotó el tiempo, `;; connection timed out; no servers could be reached`. **La consulta de nombres es tráfico de red** que sale del Pod hacia el DNS del clúster, y la política `cerrado` también cerró eso. Con la salida cerrada, los Pods del espacio no pueden preguntar quién es `revisor`.

Entre el `apply` y las pruebas hay una espera de 8 segundos (`$ sleep 8`, a la vista en la salida completa de `correr.salida.txt`); 7.5.7 mide cuánto tarda una política en programarse y de ahí sale el margen.

Hay más efectos, que se miden con tres comandos desde tu máquina y uno desde el Pod que lee la API:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
000
[código de salida: 28]

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ sleep 3
Forwarding from 127.0.0.1:18087 -> 8080

$ curl -s -m 8 -H 'Authorization: Bearer …' 'http://127.0.0.1:18087/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     1.998s  se acabo el tiempo de espera

$ kubectl exec -n revisor lector -- sh -c 'curl -s -m 3 -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 000
command terminated with exit code 28
[código de salida: 28]
```

La puerta dejó de entrar: el cliente de fuera recibe `000` y código 28. La política `cerrado` aísla la entrada de **todos** los Pods del espacio, incluido el `revisor`, y los Pods de Envoy (que viven en otro espacio) quedaron sin permiso para hablarle. El `port-forward`, en cambio, **sigue funcionando**: se abrió el túnel y el `revisor` contestó. (La [guía de `port-forward`](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) no describe por qué camino viaja; sí dice algo útil para esta lección: el acceso a `port-forward` lo controla RBAC, con el permiso `create` sobre `pods/portforward`, así que quien lo tenga entra al Pod aunque la red esté cerrada.) Pero lo que el `revisor` contesta ya no es el reporte completo: la tabla dice `prueba FALLA` con el detalle `se acabo el tiempo de espera`, porque el `revisor` no puede salir a preguntarle a `prueba`. La salida del propio `revisor` también está cerrada. Y el `lector`, el Pod con token válido, ya no llega a la API: `pods 000`, código 28. **La red cerrada protege a la API de quien tiene permiso.** RBAC dice qué *puedes* pedir; la red dice a dónde *llegas*. Las dos tienen que decir que sí.

Una duda razonable en este punto: si todo está cerrado, ¿no deberían fallar las sondas? No fallan. Las sondas las ejecuta el `kubelet` del nodo (Lección 5), y la documentación de políticas de red dice que, cuando un Pod está aislado para la entrada, «las únicas conexiones permitidas hacia el Pod son las que vienen del nodo del Pod y las que permite la lista `ingress` de alguna política». El tráfico del propio nodo queda fuera del filtro. Se verifica con las seis reglas puestas, 45 segundos después, en 7.5.5.

#### 7.5.5 Las aperturas necesarias

Ahora las otras cinco políticas, que juntas con `cerrado` forman `red.yaml`. Léelas una por una antes de aplicarlas; cada una tiene un comentario que dice a quién abre y por qué:

```yaml
# red.yaml — Lección 7: todo cerrado por defecto, y solo las aperturas necesarias.
# ⚠️ Que el clúster APLIQUE estas reglas depende de la red (CNI). kindnet, la red
# de kind desde la v0.24.0, sí las aplica: la Lección 7 lo mide con intruso y
# depurar. Con un CNI que no las aplique, estos objetos se guardan y no hacen nada.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# Todos pueden preguntarle al DNS del clúster (si no, ningún nombre resuelve).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
---
# El revisor sale solo hacia prueba:9000.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-salida
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: prueba
    ports:
    - {protocol: TCP, port: 9000}
---
# prueba solo recibe del revisor.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prueba-entrada
spec:
  podSelector:
    matchLabels:
      app: prueba
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 9000}
---
# Al revisor solo entran los Pods marcados «acceso-revisor: permitido» y los
# Envoy de la puerta (Lección 6), que viven en el espacio envoy-gateway-system.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-entrada
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          acceso-revisor: permitido
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: envoy-gateway-system
    ports:
    - {protocol: TCP, port: 8080}
---
# …y esos mismos Pods pueden SALIR hacia el revisor:8080. Con «cerrado» también
# la salida está prohibida: abrir solo la entrada del revisor no basta (medido).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: acceso-revisor-salida
spec:
  podSelector:
    matchLabels:
      acceso-revisor: permitido
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 8080}
```

En orden:

- **`cerrado`**: la de arriba. Con `podSelector: {}` y los dos tipos, deja a todos los Pods del espacio sin entrada ni salida.
- **`dns`**: abre la **salida** de todos los Pods hacia el DNS. El destino se escribe con las dos condiciones juntas en un solo elemento (`namespaceSelector` **y** `podSelector`): los Pods con la etiqueta `k8s-app: kube-dns` del espacio `kube-system`. Los puertos son 53 sobre UDP y sobre TCP. El espacio se selecciona con la etiqueta `kubernetes.io/metadata.name`, que el clúster pone solo en todo espacio, con su nombre; la documentación advierte que no se puede escribir el nombre de un espacio directamente en una política y que esa etiqueta existe para eso.
- **`revisor-salida`**: la **salida** del `revisor` hacia los Pods con `app: prueba`, solo al puerto 9000. Es lo único que el `revisor` necesita de la red: consultar a `prueba`.
- **`prueba-entrada`**: la **entrada** a `prueba`, solo desde los Pods `app: revisor`, y solo al 9000. La política de salida del `revisor` y la de entrada de `prueba` son dos mitades de una misma puerta: para que el tráfico pase, las dos direcciones tienen que decir que sí.
- **`revisor-entrada`**: la **entrada** al `revisor`, al puerto 8080, desde dos orígenes (dos elementos de `from`, o sea, uno **o** el otro): los Pods con la etiqueta `acceso-revisor: permitido` (de este espacio) y **todos los Pods** del espacio `envoy-gateway-system`, donde vive la puerta de la Lección 6.
- **`acceso-revisor-salida`**: la **salida** de los Pods con la etiqueta `acceso-revisor: permitido` hacia el `revisor`, puerto 8080. Es la pareja de la anterior. Existe por una lección que costó una primera versión de esta red: abrir solo la entrada del `revisor` no basta, porque `cerrado` también cierra la salida de quien quiere hablarle.

Dos observaciones antes de aplicarlas. La etiqueta `acceso-revisor: permitido` hace de **llave**: quien la lleve puede hablarle al `revisor`, y se la pone a un Pod quien tenga permiso de crear Pods en el espacio. Por eso la etiqueta no es un secreto sino un acuerdo, y 7.5.8 la comenta. Y las políticas usan el puerto `8080`, el del contenedor, **no** el 80 del Service. No es una decisión de este clúster: la [referencia de la API](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/) define el campo `port` de una política como «un puerto numérico o con nombre de un Pod». El Service ya eligió réplica y tradujo el puerto antes de que la política mire el paquete; la política ve el destino final. Aquí se midió que kindnet lo cumple (si no, `depurar` no habría llegado), y en otro clúster vale medirlo igual, porque lo que se comprueba es que el complemento aplique la API, no cuál puerto manda.

```text
$ kubectl apply -n revisor -f red.yaml
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns created
networkpolicy.networking.k8s.io/revisor-salida created
networkpolicy.networking.k8s.io/prueba-entrada created
networkpolicy.networking.k8s.io/revisor-entrada created
networkpolicy.networking.k8s.io/acceso-revisor-salida created

$ kubectl get networkpolicy -n revisor
NAME                    POD-SELECTOR               AGE
acceso-revisor-salida   acceso-revisor=permitido   8s
cerrado                 <none>                     50s
dns                     <none>                     8s
prueba-entrada          app=prueba                 8s
revisor-entrada         app=revisor                8s
revisor-salida          app=revisor                8s

$ kubectl describe networkpolicy revisor-entrada -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     app=revisor
  Allowing ingress traffic:
    To Port: 8080/TCP
    From:
      PodSelector: acceso-revisor=permitido
    From:
      NamespaceSelector: kubernetes.io/metadata.name=envoy-gateway-system
  Not affecting egress traffic
  Policy Types: Ingress

$ kubectl describe networkpolicy cerrado -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Allowing egress traffic:
    <none> (Selected pods are isolated for egress connectivity)
  Policy Types: Ingress, Egress
```

`cerrado` salió `unchanged` (ya estaba) y las otras cinco `created`. El `describe` de `revisor-entrada` lo lee en lenguaje llano: «permitiendo tráfico de entrada al puerto 8080/TCP, desde (PodSelector: `acceso-revisor=permitido`) y desde (NamespaceSelector: `kubernetes.io/metadata.name=envoy-gateway-system`); sin afectar la salida; tipo de política: Ingress». Los dos `From:` son las dos alternativas. Y el de `cerrado` repite, con otras palabras, lo que ya sabías: «Pods seleccionados: aislados para entrada y para salida».

Ahora la prueba, con los mismos comandos de siempre:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor depurar -- curl -s -m 3 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           9ms  200

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://prueba:9000/
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez

command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- nslookup revisor.revisor.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.revisor.svc.cluster.local
Address: 10.96.146.219

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Seis resultados, uno por pregunta:

- **`depurar` (con la etiqueta) llega al `revisor`** y recibe su `/salud`, y con el token recibe el reporte completo: `prueba OK`. Esto quiere decir que el `revisor` volvió a poder salir hacia `prueba` y que `prueba` lo acepta. Son las dos mitades.
- **`intruso` (sin la etiqueta) no llega**: código 28. La respuesta a la segunda pregunta de las 5:58 ya es «no».
- **`depurar` no llega a `prueba:9000`**: código 28. La etiqueta abre el camino hacia el `revisor`, no hacia el servicio de prueba. Un Pod con la llave del `revisor` no es un Pod con la llave de todo.
- **`intruso` no llega a la API**: `curl` se agota. La tercera pregunta ya tiene una pared antes de RBAC.
- **El DNS responde**: el `intruso` resuelve `revisor.revisor.svc.cluster.local` a la IP del Service. Un Pod sin llave puede preguntar por nombres (la regla `dns` es para todos) y recibe respuesta, pero no puede conectarse a lo que encuentra. Que el DNS funcione no quiere decir que el camino esté abierto.
- **El `intruso` de `default` tampoco llega**: el nombre completo del Service ya no le sirve.

Y las rutas legítimas que podrían haberse roto:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ curl -s -m 5 http://127.0.0.1:18087/salud   # por port-forward
{"estado":"vivo","version":"1.6.0"}
```

La puerta responde otra vez desde fuera, porque `revisor-entrada` admite a los Pods de `envoy-gateway-system`. Y el `port-forward` sigue funcionando. Ahora, con todas las reglas puestas, una espera de 45 segundos, la de unas cuantas vueltas de las sondas de la Lección 5, y un vistazo a los Pods:

```text
$ sleep 45

$ kubectl get pods -n revisor -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-6899c74865-rgh68    1/1     Running   0          7m15s
revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          7m15s
```

`RESTARTS 0` en los cuatro, `1/1`. La red cerrada **no** tumbó las sondas, y la razón es la de la documentación que acabas de leer: las hace el `kubelet`, desde el nodo.

#### 7.5.6 Para qué sirve cada regla: se quita una, se mide, se devuelve

Leer una política dice qué *debería* hacer. Para saber qué hace se le quita al clúster, **una a la vez**, y se miden cuatro cosas desde el mismo lugar: `depurar` le pide `/salud` al `revisor`; `depurar` le pide el reporte (que obliga al `revisor` a salir hacia `prueba`); `depurar` resuelve el nombre del `revisor`; y el cliente de fuera le pide `/salud` por la puerta. Después se vuelve a aplicar `red.yaml` y se pasa a la siguiente. El `nslookup` de esta tabla se hace con un `sh -c` que imprime la última línea útil, o `sin respuesta`, para que quepa en un renglón.

```text
$ kubectl delete networkpolicy dns -n revisor
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/salud
000
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- sh -c 'r=$(timeout 8 nslookup revisor.revisor.svc.cluster.local 2>&1 | grep -E "^Address: [0-9]|timed out" | tail -1); echo "${r:-sin respuesta}"'
;; connection timed out; no servers could be reached

$ curl -s -m 4 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
200
```

Esa es la primera: sin `dns`, el nombre `revisor` no se resuelve, así que la petición a `/salud` y la del reporte se agotan (código 28) y el `nslookup` también. La puerta, en cambio, responde `200`: lo que se midió es que Envoy llega al `revisor` aunque el DNS esté cerrado para los Pods del espacio; cómo encuentra Envoy las réplicas es asunto de Envoy Gateway y el curso no lo midió. Las otras cuatro se leen igual. La tabla completa:

| Regla quitada | `depurar` → `/salud` | `depurar` → reporte | Resolver el nombre | Desde fuera, `/salud` |
|---|---|---|---|---|
| `dns` | 28 (agotado) | 28 | agotado | 200 |
| `revisor-salida` | 200 | `prueba FALLA`, agotado | responde | 200 |
| `prueba-entrada` | 200 | `prueba FALLA`, agotado | responde | 200 |
| `revisor-entrada` | 28 | 28 | responde | **000** (28) |
| `acceso-revisor-salida` | 28 | 28 | responde | 200 |
| (las seis puestas) | 200 | `prueba OK` | responde | 200 |

Cada fila cuenta algo distinto. Quitar `revisor-entrada` es la única que tumba la puerta, porque es la que deja pasar a Envoy. Quitar `acceso-revisor-salida` deja a `depurar` sin salida, pero la puerta sigue (en este clúster nadie creó políticas en el espacio de Envoy, así que no tiene la salida cerrada). Quitar `revisor-salida` o `prueba-entrada` produce **el mismo síntoma**, `prueba FALLA` por tiempo agotado, con causas distintas: en un caso el `revisor` no puede salir, en el otro `prueba` no puede recibir. Y un síntoma así no dice cuál de las dos políticas falta. Es el tipo de fallo para el que `describe networkpolicy` sirve.

Los bloques completos de las cinco pruebas, con sus comandos, están en `correr.salida.txt`. Aquí va el tramo que tiene una historia, el de `revisor-salida`. En una corrida anterior, que no se guardó, esta fila salió `prueba OK` aun sin la regla. No se pudo repetir (en esta corrida salió `FALLA` a la primera) y no sabemos la causa. Hay dos explicaciones posibles y ninguna se comprobó. Una: una conexión que ya estaba abierta siguió viva con la regla quitada; la documentación de políticas de red deja ese caso a cada complemento («queda definido por la implementación» si el cambio surte efecto sobre una conexión existente) y recomienda no modificar políticas de forma que las afecte. Otra: la política aún no estaba programada, que es lo que mide 7.5.7. Por eso el guion espera, y aquí además **reinicia el `revisor`**, para que la prueba abra una conexión nueva:

```text
$ kubectl delete networkpolicy revisor-salida -n revisor
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.001s  se acabo el tiempo de espera

$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 3 new replicas have been updated...
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

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera
```

Los dos reportes dicen `prueba FALLA`: el de antes de reiniciar y el de después. En esta corrida el reinicio no cambió el resultado (el reporte ya decía `FALLA` antes); es una precaución del método, no una prueba de la causa.

La moraleja es de método, y vale más que la tabla. **Un resultado que dice «sigue funcionando» después de quitar una regla no prueba que la regla sobraba.** Puede ser una conexión vieja, una caché, o una prueba que no pregunta lo que crees. Una prueba de red debe abrir una conexión nueva cada vez.

### El error que vas a ver (el segundo)

El segundo error es el que más tiempo hace perder con las políticas de red. Se parece a la escena, pero en pequeño: tienes una política que **abre** la entrada del `revisor`, tienes un Pod con la etiqueta correcta, y el Pod no llega. Se provoca borrando la última política, `acceso-revisor-salida`, que es la pareja de la entrada:

```text
$ kubectl delete networkpolicy acceso-revisor-salida -n revisor
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl get networkpolicy -n revisor
NAME              POD-SELECTOR   AGE
cerrado           <none>         41s
dns               <none>         41s
prueba-entrada    app=prueba     41s
revisor-entrada   app=revisor    41s
revisor-salida    app=revisor    41s

$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          7m38s   acceso-revisor=permitido,app=depurar
```

Se lee en este orden. **Primero, el síntoma:** código 28, tiempo agotado; el Pod tiene la etiqueta `acceso-revisor=permitido` y la política `revisor-entrada` existe. Todo lo que miras dice que debería pasar. **Segundo, la lista de políticas:** están `cerrado`, `dns`, `prueba-entrada`, `revisor-entrada` y `revisor-salida`; falta `acceso-revisor-salida`. **Tercero, el principio:** una política de entrada abre un lado de la puerta. El Pod que quiere llegar está aislado para la **salida** por `cerrado`, y nada se la abre. La primera versión de esta red, que abría solo la entrada, dejó a `depurar` sin poder salir. **La corrección** es el archivo, como siempre: `kubectl apply -k .` vuelve a crear la que falta, y `depurar` vuelve a llegar.

```text
$ kubectl apply -k . | grep networkpolicy
networkpolicy.networking.k8s.io/acceso-revisor-salida created
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

**El orden, cuando un Pod no llega a otro con políticas de red:**

1. `kubectl exec … curl -m 3`: ¿qué código? 28 es silencio de red; 7 es que no hay nadie; 4xx o 5xx es que sí llegó.
2. `kubectl get networkpolicy -n <espacio>` en el espacio de **los dos** extremos.
3. Para cada extremo, ¿qué políticas lo seleccionan y para qué dirección? Falta la salida del que llama o la entrada del que recibe.
4. ¿Se resuelve el nombre? Si no, `dns`.
5. ¿La etiqueta está en el Pod, o en el Deployment pero **no** en la plantilla del Pod?

#### 7.5.7 Las políticas no se aplican al instante

Hasta aquí, cada vez que el guion cambia una política, espera antes de preguntar: son los `sleep 8` que ves en las salidas. No son decoración, y esta sección cuenta de dónde sale el ocho. Una espera de tres segundos no bastó en una de las corridas de prueba de esta lección (de esa corrida no se guardó la salida): con las seis políticas ya puestas, el `intruso` le pidió `/livez` a la API y recibió `ok`, mientras que en las demás corridas esa misma pregunta se agotaba. Nada estaba roto: la pregunta se hizo **antes de que la red terminara de aprender** las políticas nuevas. Se midió a propósito. El guion repite seis veces esta secuencia: borra las seis políticas, espera un segundo, las vuelve a aplicar y, desde ese momento, le pregunta a la API seis veces desde el `intruso`, con un tiempo máximo de un segundo por pregunta, anotando cuántos segundos han pasado y qué código recibió:

```text
$ for ciclo in 1 2 3 4 5 6; do   # borrar las seis, esperar 1 s, volver a aplicarlas y preguntar seis veces a la API desde el intruso
ciclo 1: +0s:200 +0s:200 +0s:200 +2s:000 +3s:000 +6s:000
ciclo 2: +2s:000 +3s:000 +5s:000 +6s:000 +7s:000 +9s:000
ciclo 3: +0s:200 +1s:200 +1s:200 +2s:000 +7s:000 +10s:000
ciclo 4: +5s:000 +6s:000 +9s:000 +12s:000 +17s:000 +20s:000
ciclo 5: +6s:000 +9s:000 +12s:000 +15s:000 +19s:000 +23s:000
ciclo 6: +3s:000 +6s:000 +9s:000 +12s:000 +13s:000 +15s:000
```

Se lee así: `+1s:200` es «un segundo después de aplicar, la API contestó (200)», y `000` es «no contestó» (el tiempo se agotó). En los ciclos 1 y 3, las primeras preguntas obtienen respuesta y las siguientes ya no: la última respuesta llegó entre 0 y 1 segundos después del `apply`, y la primera pregunta sin respuesta, a los 2 segundos (con un máximo de un segundo por pregunta, y con lo que suma cada `kubectl exec`, la imprecisión del reloj es de ese tamaño). En los ciclos 2, 4, 5 y 6 la primera pregunta ya sale a los 2, 5, 6 y 3 segundos, porque en esta máquina cargada cada `kubectl exec` tardó segundos en arrancar, y ya encuentra la red cerrada. En ningún ciclo volvió a pasar una pregunta después de la primera sin respuesta. El `kubectl apply` ya había terminado y el objeto `NetworkPolicy` ya existía en la API: lo que faltaba era que el complemento de red, en cada nodo, lo leyera y lo convirtiera en reglas. Esa conversión toma segundos y, mientras tanto, el Pod sigue abierto. Con lo medido aquí, la ventana es de unos 2 segundos como máximo (en una corrida anterior, que no se guardó, se vio hasta 3); ocho segundos son un margen elegido, de dos y media a cuatro veces eso, y no un resultado. Pasados los ocho segundos del guion, la misma pregunta se agotó, y en esta corrida ninguna de las esperas de ocho segundos mostró lo contrario:

```text
$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -o /dev/null -w '%{http_code}\n' https://kubernetes.default.svc/livez
000
command terminated with exit code 28
[código de salida: 28]
```

Límites de esta medición: seis ciclos, una máquina cargada, un solo efecto medido (que `cerrado` le cierre la salida al `intruso`; las seis políticas se aplican juntas) y solo la dirección «cerrar»; la dirección «abrir» (borrar una política, que es lo que hacen los `sleep 8` de 7.5.6) no se midió. Tres consecuencias prácticas, que son lo que justifica una sección entera:

1. **Una prueba de red hecha demasiado pronto da un falso «sí llega».** Es el mismo defecto de método de 7.5.6 en sentido contrario. Después de cambiar políticas, espera y mide más de una vez. La documentación de políticas de red no promete una velocidad de aplicación: lo único que dice es que el efecto sobre conexiones ya existentes queda definido por la implementación. El tiempo que se midió aquí es de esta máquina, con tres nodos de kind cargados con otros clústeres, y no un dato del complemento.
2. **Cambiar una política es una operación con una ventana.** Borrar las políticas y volver a aplicarlas (el ciclo de esta misma sección, o un `kubectl delete -f red.yaml` seguido de un `kubectl apply -f red.yaml`) deja a los Pods abiertos durante la ventana, en un clúster donde las políticas son lo único que los cierra. Para cambiar una política en un clúster vivo, se crea la nueva **antes** de quitar la vieja; no se borra para recrearla.
3. **El orden de creación importa.** Si un Pod nace antes de que las políticas que lo cierran estén programadas, nace abierto un momento. En 7.2.3 viste que `kubectl apply -k` creó las seis políticas **después** de los Deployments (el orden de la lista de `resources` no manda: Kustomize entrega los objetos en su propio orden), así que las primeras réplicas del `revisor` pudieron nacer abiertas unos segundos (es una deducción del orden de las líneas, no una medición de un Pod recién nacido). En un clúster real, las políticas de un espacio se aplican primero y se espera, y después va el proyecto.

#### 7.5.8 Lo que esta red no defiende

Esta red es mejor que no tener red, y conviene decir con exactitud cuánto mejor.

- **La etiqueta `acceso-revisor` la pone quien crea el Pod.** Cualquier persona con permiso de crear Pods en `revisor` se puede dar la llave a sí misma. La política protege contra Pods que **no** saben que existe la etiqueta, no contra quien tiene acceso al espacio. La capa que cuida esto es RBAC: en un clúster real, crear Pods en `revisor` es un permiso que se da con cuentagotas. El Ejercicio 1 muestra, además, que la etiqueta no sirve de nada en el espacio equivocado.
- **`revisor-entrada` confía en el espacio entero de la puerta.** Admite a **todos** los Pods de `envoy-gateway-system`. Si ese espacio aloja otra cosa, ésa también entra. La política es tan estricta como lo sea quien controla ese espacio.
- **No cifra nada.** Un Pod autorizado habla HTTP plano con el `revisor`. La red dice quién puede llegar, no que lo que viaja vaya protegido.
- **Los Pods con `hostNetwork` y el tráfico del nodo.** La documentación dice que el comportamiento de las políticas con Pods en `hostNetwork` es indefinido y que lo más común es que el complemento los ignore y trate su tráfico como tráfico del nodo. Y el tráfico del nodo hacia sus Pods (las sondas) no se bloquea. El `port-forward` tampoco lo detiene la política, y la guía de `port-forward` avisa de que puede saltarse los controles de red: a ése lo cuida RBAC (`create` sobre `pods/portforward`). Por eso el nivel `restricted` de 7.3, que prohíbe `hostNetwork`, y la red se complementan.
- **No hay política por omisión para todo el clúster.** La misma página lista como límite del API que no se pueden aplicar políticas por omisión a todos los espacios o Pods. `cerrado` hay que escribirla en cada espacio, y un espacio nuevo nace abierto.
- **Solo funciona porque el complemento las aplica.** En esta corrida se midió que kindnet las aplica. En otro clúster hay que medirlo igual: el clúster guarda las políticas sin quejarse aunque nadie las haga cumplir.


## El hábito de seguridad de la lección: espacio propio, nivel `restricted`, permisos mínimos y red cerrada por defecto

La tabla de hábitos del curso le asigna a esta lección cuatro cosas en una sola línea: espacio propio, nivel `restricted`, permisos mínimos, red cerrada por defecto. Cada una se comprueba con un comando, y la comprobación más honesta es la que busca lo que falta, no lo que sobra. El inventario:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       13m

$ kubectl apply -k . 2>&1 | grep -c -i warning || true
0

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken'
POD                       CUENTA       AUTOMOUNT
depurar                   default      false
intruso                   default      false
lector                    observador   true
prueba-6899c74865-rgh68   prueba       false
revisor-d86b5794d-5fspg   revisor      false
revisor-d86b5794d-hx92n   revisor      false
revisor-d86b5794d-tmq5g   revisor      false
```

Léelo como cuatro preguntas. **¿Qué está publicado hacia afuera?** Un solo Service de tipo `LoadBalancer` en todo el clúster: el de Envoy, en `envoy-gateway-system`, con la IP que le dio MetalLB. El `revisor-publico` de la Lección 6 ya no existe, y la única puerta es la nombrada. **¿El proyecto cumple el nivel que exige su espacio?** Volver a aplicar la `kustomization` no produce ni una advertencia (`0` renglones con `warning`), y la prueba con `--dry-run=server` del estado final (en «Cómo sé que lo logré») dice `not labeled`. **¿Quién tiene credenciales?** Solo `lector`, el Pod de la práctica de 7.4.4, que las pidió a propósito (`AUTOMOUNT true`); el `revisor`, `prueba`, `depurar` e `intruso` dicen `false`. **¿La red está cerrada?** Seis políticas en `revisor`, y 7.5 midió qué abre cada una.

¿Por qué son hábitos de **seguridad** y no solo de orden? Porque cada capa cierra un camino concreto que se midió abierto. Un espacio con `restricted` frena al equipo de datos (o a tu propio descuido) antes de que un Pod con privilegios de más exista. Una cuenta sin permisos y sin token deja a un contenedor comprometido sin nada que presentar ante la API (el `intruso` de 7.4.4 no tenía ni un archivo). Y la red cerrada convierte «cualquier Pod le habla a cualquier Pod» en una lista corta que se puede leer, revisar y discutir, que es el cambio más valioso de la lección: la superficie pasó de implícita a escrita.

**Lo que defiende y lo que no.** Esto lo midió la lección, de una en una:

| Capa | Defiende contra | No defiende contra |
|---|---|---|
| Espacio de nombres | choques de nombres; alcance de permisos | tráfico entre Pods (7.5.3: se alcanzaron entre espacios) |
| Pod Security `restricted` | crear Pods con privilegios, `root`, `hostNetwork` | Pods que ya corrían (7.3.4); alguien con permiso de cambiar la etiqueta del espacio |
| Cuenta sin token ni permisos | robo de credenciales de un Pod que no las necesita | un Pod que sí las necesita y está comprometido (el `lector`: alcanza lo que su `Role` alcanza) |
| Red cerrada | movimiento lateral entre Pods; acceso a la API desde Pods sin llave | quien puede poner la etiqueta; el tráfico del nodo; el contenido de lo que viaja (HTTP plano) |

Y el panorama completo, para que no se lea esto como una receta de producción: faltan el cifrado en tránsito, un tope de recursos por espacio (`ResourceQuota`, `LimitRange`), el cifrado de los Secrets dentro del clúster, la auditoría del `kube-apiserver` y la gestión de quién tiene permiso de tocar este espacio. La Lección 10 junta la lista de lo que le falta a todo el proyecto para correr de verdad.

## Lo que se hace mal

**Creer que un espacio de nombres aísla la red.** Lo parece, porque los rótulos están en todas partes. 7.5.3 lo midió: un Pod de `default` alcanzó el Service de `revisor` escribiendo su nombre completo.

**Aplicar una política de red y no comprobar que el complemento la cumple.** El clúster guarda el objeto sin quejarse y el tráfico sigue igual. Se prueba con un Pod sin llave que debe fallar, no con la lectura del manifiesto.

**Cerrar la entrada y olvidar la salida.** `cerrado` aísla las dos direcciones, y abrir solo la entrada del destino deja al que llama sin poder salir. Son dos mitades de un solo permiso. Es el segundo error de la lección.

**Cerrar la salida y olvidar el DNS.** Sin la regla `dns`, los nombres no se resuelven y el síntoma parece que «la red está rota» cuando solo faltan las consultas de nombres.

**Concluir por un «sigue funcionando».** Una conexión ya abierta puede sobrevivir al cambio de una política, y la documentación lo deja a decisión de cada complemento. Una prueba de red abre una conexión nueva cada vez.

**Poner `enforce` y creer que el espacio quedó limpio.** La etiqueta rechaza lo que llegue, no desaloja lo que ya corre. Y el Pod viejo que viola el nivel muere de un rollout: el día que lo recrees, ya no nace.

**Dejar `enforce` sin versión.** `restricted:latest` cambia cuando el clúster se actualiza. Fija la versión (`enforce-version`) y súbela a propósito.

**Mirar solo el modo `enforce`.** Un Deployment que viola la política **se crea**, con una advertencia que casi nadie lee, y se queda sin Pods. Las advertencias del modo `warn` se leen, o se redirigen a un registro que alguien revise.

**Darle permisos con comodines (`*`).** La documentación de RBAC lo advierte: un comodín en recursos o verbos concede también lo que un día agregue el clúster. Se nombra cada recurso y cada verbo.

**Dejar montado el token de una cuenta que no lo usa.** Es una credencial en cada réplica, sin ningún beneficio. `automountServiceAccountToken: false`, en la cuenta o en el Pod.

**Dar la etiqueta `acceso-revisor` a cualquier Pod «para que funcione».** Cada Pod con la llave es un Pod más que puede hablarle al `revisor`. La llave se da a quien lo necesita, y se pregunta por qué.

**Confiar en todo un espacio de nombres como origen.** `revisor-entrada` acepta a todos los Pods de `envoy-gateway-system`. Es una decisión razonable mientras ese espacio sea solo de la plataforma, y deja de serlo el día que otra cosa viva ahí.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden y desde el estado en que quedó después de 7.5. Antes de cada uno, `ctx` debe dejar pasar la cadena. `correr.sh` los corre igual, y su salida está en `correr.salida.txt`. **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — La etiqueta correcta en el espacio equivocado

Aplica `depurar.yaml` en el espacio `default`, con `ctx && kubectl apply -n default -f depurar.yaml`. Es el mismo manifiesto, con la misma etiqueta `acceso-revisor: permitido`. Antes de mirar, predice: ¿puede ese Pod hablarle al `revisor` con el nombre completo, `http://revisor.revisor.svc.cluster.local/salud`? ¿Y el `depurar` del espacio `revisor`? Explica la diferencia con las palabras de 7.5.5: ¿qué selecciona la política `revisor-entrada` y de **qué espacio**? Al terminar, borra el Pod de `default`.

### Ejercicio 2 — Una cuenta que solo reinicia el `revisor`

`fig07_03.reiniciador.yaml` crea una cuenta, un `Role` y un `RoleBinding`:

```yaml
# fig07_03.reiniciador.yaml — Ejercicio 2: una cuenta que puede reiniciar el
# revisor y NADA más. rollout restart necesita leer el Deployment (get) y
# cambiarle una anotación (patch); resourceNames lo limita a UN Deployment.
# Se aplica con: kubectl apply -n revisor -f fig07_03.reiniciador.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reiniciador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: reiniciador
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["revisor"]
  verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: reiniciador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: reiniciador
subjects:
- kind: ServiceAccount
  name: reiniciador
  namespace: revisor
```

`kubectl rollout restart` necesita leer el Deployment (`get`) y cambiarle una anotación (`patch`). Aplícalo con `ctx && kubectl apply -n revisor -f fig07_03.reiniciador.yaml` y predice, antes de correr nada: ¿puede la cuenta reiniciar el `revisor`? ¿Y `prueba`? ¿Puede **listar** los Deployments? Comprueba tus tres predicciones con `kubectl auth can-i … --as=system:serviceaccount:revisor:reiniciador` y después con `kubectl rollout restart` de verdad. ¿Por qué `can-i list deployments` contesta distinto a `can-i patch deployment/revisor`? Al terminar, borra lo que creaste con `ctx && kubectl delete -n revisor -f fig07_03.reiniciador.yaml`.

### Ejercicio 3 — Una ruta que viene de otro espacio (proyecto)

La puerta vive en `revisor`. Otro equipo, en `default`, quiere publicar una ruta propia por esa misma puerta. `fig07_05.ruta-ajena.yaml` es su `HTTPRoute`:

```yaml
# fig07_05.ruta-ajena.yaml — Ejercicio 3: una HTTPRoute que vive en el espacio
# «default» y pide colgarse del Gateway «revisor», que vive en «revisor».
# Pregunta: ¿la acepta el Gateway? ¿Qué dice su estado? Se aplica con:
#   kubectl apply -n default -f fig07_05.ruta-ajena.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ajena
spec:
  parentRefs:
  - name: revisor
    namespace: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /ajena
    backendRefs:
    - name: revisor
      namespace: revisor
      port: 80
```

Antes de empezar, dos permisos distintos que conviene no confundir. `allowedRoutes`, dentro del `listeners` del `Gateway`, dice **quién puede colgarse de la puerta**: por omisión (`from: Same`) solo las rutas del mismo espacio que el `Gateway`; `All` y `Selector` abren la puerta a otros espacios. `ReferenceGrant` vive en el espacio del **destino** y dice **quién puede apuntar a sus Services**: una ruta de otro espacio no puede usar como destino un Service de `revisor` si el dueño de ese espacio no lo permite. El primero lo da el dueño de la puerta; el segundo, el dueño del Service. Las páginas de referencia: [`ReferenceGrant`](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/), la [referencia de la API](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) y la [guía de rutas entre espacios](https://gateway-api.sigs.k8s.io/guides/multiple-ns/).

Aplícala en `default`. Lee su estado con `kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'`. Hay **dos** problemas distintos en ese estado. Antes de mirar el tuyo, predice cuáles son, de qué objeto depende cada uno y quién tiene que dar cada permiso: ¿el dueño de la puerta, el dueño del Service o el equipo que escribe la ruta? Arregla primero el que sale de la puerta (la pista: `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces`) y luego el otro con `fig07_06.referencegrant.yaml`:

```yaml
# fig07_06.referencegrant.yaml — Ejercicio 3: el permiso que da el DUEÑO del Service.
# Vive en el espacio «revisor» (el del Service destino) y dice: las HTTPRoute del
# espacio «default» pueden usar como destino los Service de este espacio.
# Se aplica con: kubectl apply -n revisor -f fig07_06.referencegrant.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: rutas-de-default
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: default
  to:
  - group: ""
    kind: Service
    name: revisor
```

Comprueba al final que `GET /ajena` por la puerta llega al `revisor` (la respuesta es un `404` del `revisor`, no de la puerta: ¿cómo lo demuestras con su bitácora?), y deshaz todo lo que cambiaste, incluido el `Gateway`.

### Ejercicio 4 — Defiende el diseño

En cinco frases como máximo, contesta: (1) ¿por qué esta lección no instaló Calico, y qué prueba lo respalda? (2) ¿Qué pasaría con las sondas si `kindnet` aplicara las políticas pero el tráfico del nodo también se bloqueara? (3) ¿Qué política de las seis cambiarías si el equipo de datos necesitara un servicio **propio** en el espacio `revisor` que también reciba tráfico de la puerta? (4) ¿Qué falta para que `acceso-revisor: permitido` sea una protección y no solo un acuerdo? (5) La política `dns` abre la salida a los Pods `k8s-app: kube-dns` de `kube-system`; ¿qué pasaría con la resolución de nombres si CoreDNS se mudara a otro espacio?

## Soluciones

### Solución 1

Medido en `correr.salida.txt`:

```text
$ kubectl apply -n default -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -n default --show-labels
NAME      READY   STATUS    RESTARTS   AGE   LABELS
depurar   1/1     Running   0          6s    acceso-revisor=permitido,app=depurar

$ kubectl exec -n default depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

El Pod de `default` tiene la etiqueta, y aun así **código 28**. El `depurar` de `revisor` contesta. La política `revisor-entrada` no selecciona «los Pods con la etiqueta» a secas: en su lista `from`, el `podSelector` sin `namespaceSelector` se refiere a los Pods **del espacio donde vive la política**, o sea `revisor`. La etiqueta en otro espacio no cuenta. El segundo elemento de la lista (`namespaceSelector`), en cambio, elige espacios completos, y por eso entra Envoy. Para que el Pod de `default` entrara habría que agregar un elemento con `namespaceSelector` y `podSelector` **juntos**: los Pods con esa etiqueta, de ese espacio. Fíjate también en que el nombre largo sí se resolvió (la regla `dns` está abierta para todos); lo que falló fue la conexión.

### Solución 2

Medido en `correr.salida.txt`:

```text
$ kubectl apply -n revisor -f fig07_03.reiniciador.yaml
serviceaccount/reiniciador created
role.rbac.authorization.k8s.io/reiniciador created
rolebinding.rbac.authorization.k8s.io/reiniciador created

$ kubectl auth can-i patch deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
yes

$ kubectl auth can-i patch deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl auth can-i list deployments -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl rollout restart deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
deployment.apps/revisor restarted

$ kubectl rollout restart deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
Error from server (Forbidden): deployments.apps "prueba" is forbidden: User "system:serviceaccount:revisor:reiniciador" cannot get resource "deployments" in API group "apps" in the namespace "revisor"
[código de salida: 1]
```

`patch` sobre `deployment/revisor` contesta `yes`, sobre `prueba` `no`: el `Role` nombra al Deployment con `resourceNames: ["revisor"]`. El reinicio del `revisor` funciona (`restarted`) y el de `prueba` da un `Forbidden` que dice `cannot get resource "deployments"`: `rollout restart` empieza leyendo el Deployment, y esa lectura ya está prohibida. `list deployments` contesta `no` por la razón más simple: el `Role` solo otorga `get` y `patch`, y `list` es otro verbo. Que `get` esté limitado a un nombre no convierte a `get` en `list`: leer uno por nombre y listar son permisos separados (lo viste en 7.4.3 con los Secrets). Y aunque el `Role` agregara `list`, la documentación de RBAC avisa que restringir `list` o `watch` con `resourceNames` obliga al cliente a mandar `--field-selector=metadata.name=revisor`: un `kubectl get deployments` a secas seguiría dando `no`. Esa cuenta puede reiniciar un servicio y no puede ver los demás. Es el permiso mínimo que describe la lección, y es el ejemplo de por qué se escribe `resourceNames` en lugar de dar `patch` sobre todos los Deployments.

### Solución 3

Medido en `correr.salida.txt`:

```text
$ kubectl get gateway revisor -n revisor -o jsonpath='{.spec.listeners[0].allowedRoutes}{"\n"}'
{"namespaces":{"from":"Same"}}

$ kubectl apply -n default -f fig07_05.ruta-ajena.yaml
httproute.gateway.networking.k8s.io/ajena created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=False NotAllowedByListeners: No listeners included by this parent ref allowed this attachment.
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

El `Gateway` dice `{"namespaces":{"from":"Same"}}`: **solo rutas de su propio espacio**. No lo escribiste tú; es el valor por omisión del tipo (`kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` dice «restringido al espacio de este Gateway por omisión»). Y la ruta de `default` sale con dos condiciones en falso, de dos mecanismos distintos:

- **`Accepted=False NotAllowedByListeners`**: el *oyente* (`listener`) del Gateway no admite rutas de `default`. Lo decide el dueño de la puerta, con `allowedRoutes`, **en el Gateway**.
- **`ResolvedRefs=False RefNotPermitted`**: la ruta apunta a un Service de otro espacio, `revisor/revisor`, y ningún `ReferenceGrant` lo permite. Lo decide el dueño del **destino**, con un objeto en **su** espacio.

El estado de la ruta lo resume en dos renglones: cruzar espacios al **colgarse** de un Gateway lo gobierna el Gateway; cruzar espacios al **apuntar** a un Service lo gobierna quien es dueño del Service (`kubectl explain referencegrant.spec` lo describe como los espacios y tipos de confianza que pueden referenciar los recursos de `to`). Son dos permisos con dos dueños, y el estado los separa: `Accepted` responde al oyente del Gateway (`allowedRoutes`) y `ResolvedRefs` responde al `ReferenceGrant`. Un `ReferenceGrant` habla de a quién puede **apuntar** una ruta; que una ruta pueda **colgarse** de un Gateway ajeno es asunto de `allowedRoutes`. Se arregla el primero etiquetando el espacio de la ruta y diciéndole al oyente que acepte los espacios con esa etiqueta:

```text
$ kubectl label namespace default acceso-puerta=permitido
namespace/default labeled

$ kubectl patch gateway revisor -n revisor --type=json -p '[{"op":"add","path":"/spec/listeners/0/allowedRoutes","value":{"namespaces":{"from":"Selector","selector":{"matchLabels":{"acceso-puerta":"permitido"}}}}}]'
gateway.gateway.networking.k8s.io/revisor patched

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

`Accepted` pasó a `True`; `ResolvedRefs` sigue en `RefNotPermitted`: el primer permiso no arregla el segundo. El permiso del destino es el `ReferenceGrant`, que vive en el espacio del Service (`revisor`) y nombra de quién acepta referencias:

```text
$ kubectl apply -n revisor -f fig07_06.referencegrant.yaml
referencegrant.gateway.networking.k8s.io/rutas-de-default created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=True ResolvedRefs: Resolved all the Object references for the Route
```

Las dos condiciones en verdad. Y la prueba de que la ruta llega al `revisor`:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/ajena   # desde fuera del clúster
404

$ kubectl logs -n revisor -l app=revisor --tail=-1 | grep -E 'GET /ajena'
revisor: GET /ajena 404 0s
```

El cliente de fuera recibe `404`. Ese `404` **no es de la puerta**: la bitácora del `revisor` tiene el renglón `GET /ajena 404`, o sea, la petición llegó a una réplica del `revisor`, que no conoce esa ruta. (Si la puerta no hubiera encontrado ruta, el `404` no aparecería en la bitácora del `revisor`.) La política de red no estorbó porque el destino es el propio `revisor`, y `revisor-entrada` ya admite a los Pods de Envoy: las dos capas, la de rutas y la de red, dijeron que sí. Son capas distintas, y las dos tienen que decirlo. Ese `Same` es el valor por omisión que documenta la [referencia de la API de Gateway API](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) para `allowedRoutes.namespaces.from`, y el clúster lo confirmó con el primer comando; la [guía de rutas entre espacios](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) explica cómo abrirlo con `Selector` o `All`.

El guion deshace todo: borra la ruta, el `ReferenceGrant`, la etiqueta de `default` y el campo `allowedRoutes` que agregaste al `Gateway`; el `kubectl diff -k .` del estado final confirma que el clúster volvió a lo que dicen los archivos.

### Solución 4

Una respuesta posible: «(1) Porque kindnet aplicó las políticas: con `cerrado` solo, el `intruso` y el Pod con la etiqueta dejaron de llegar (código 28), y con las seis se abrió únicamente lo que decían; esa es la medición que el plan del curso dejó pendiente. (2) Las sondas fallarían: el `kubelet` las hace desde el nodo y quedarían bloqueadas, la sonda de disponibilidad sacaría de la lista a todas las réplicas y la de vida las reiniciaría; la documentación dice que el tráfico del nodo se permite, y esta lección midió `RESTARTS 0`. (3) Ninguna de las seis: se agregaría una política nueva, `entrada` para ese servicio, con el mismo `namespaceSelector` de la puerta; las políticas se suman y no se editan las ajenas. (4) Que quien pueda crear Pods en `revisor` no pueda ponerse la etiqueta: RBAC que limite quién crea o cambia Pods en el espacio, o una política de admisión que valide la etiqueta. (5) La salida a DNS dejaría de coincidir con los Pods nuevos de DNS y los nombres dejarían de resolverse, con el mismo síntoma que quitar la regla `dns` en 7.5.6: el `nslookup` se agota y `curl` por nombre falla con 28, mientras la puerta sigue respondiendo, como en esa fila de la tabla.»

## Borrar el clúster

Cuando termines los ejercicios, borra el clúster de la lección. No dejes nada vivo en la máquina:

```text
$ kind delete cluster --name curso-k8s-l7
Deleting cluster "curso-k8s-l7" ...
Deleted nodes: ["curso-k8s-l7-worker2" "curso-k8s-l7-worker" "curso-k8s-l7-control-plane"]

$ kind get clusters | grep -c curso-k8s-l7
0

# disco de Docker: 77% usado
# la corrida completa tardó 1569 s
```

(La línea entre paréntesis la escribe el guion, que mide el borrado.) El `--name` es obligatorio: sin él, kind borraría el clúster llamado `kind`, que puede ser de otra persona.

Quedan en tu máquina la carpeta temporal del `kubeconfig` y `token.txt` (el de `punto-de-partida/` lo borraste en 7.2.3; el `rm` de abajo lo incluye por si no lo hiciste). Se borran así, desde `programas/07-aislar-permisos-red`:

```bash
# Los tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 7.1.1.
case "$L7_TMP" in
  /tmp/curso-k8s-l7.?*) rm -rf -- "$L7_TMP" ;;
  *) echo "No borro «$L7_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L7_TMP
unset -f ctx
```

El `case` solo deja pasar una ruta que empiece con `/tmp/curso-k8s-l7.` y tenga algo después, la forma exacta de la que creaste en 7.1.1. Si `L7_TMP` está vacía (porque estás en otra terminal donde nunca la definiste) o vale otra cosa, no borra nada y te dice por qué. Es la misma protección que usa `correr.sh` al limpiar. La última línea quita la función `ctx` de tu terminal.

Si en esta máquina corriste la lección con una red de Docker propia (la variable `CURSO_RED` de `correr.sh`), esa red también es tuya y la borras tú, **después** del clúster y solo si la creaste tú para esto: `docker network rm curso-k8s-red-l7`. Con la red `kind` de siempre no hay nada que borrar: es de todos tus clústeres. El clúster de la siguiente lección se crea de cero, igual que este.

## Cómo sé que lo logré

Antes de las casillas, el estado final tal como lo dejó la corrida, copiado de `correr.salida.txt`. Primero se borran los Pods de los ejercicios y se pregunta al clúster si algo difiere de los archivos del proyecto, y después se mira la puerta desde fuera y se repite la prueba de 7.3:

```text
$ kubectl delete -n revisor pod depurar intruso lector --wait=false
pod "depurar" deleted from revisor namespace
pod "intruso" deleted from revisor namespace
pod "lector" deleted from revisor namespace

$ kubectl delete -n default pod intruso --wait=false
pod "intruso" deleted from default namespace

$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/api/estados   # desde fuera del clúster
401

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

Se leen así. `sin diferencias con los archivos` quiere decir que los ejercicios se deshicieron: el clúster es exactamente lo que dicen los archivos. El `401` es el `revisor` detrás de su puerta: la puerta responde, pero `/api/estados` pide el token y desde fuera no lo llevas. Y `not labeled (server dry run)` sin advertencias cierra 7.3: pedir otra vez el nivel `restricted` para `revisor` no cambia nada porque ya lo tiene, y ningún Pod existente lo incumple.

- [ ] Dices, con un comando, qué **no** aísla un espacio de nombres: un Pod de `default` alcanza `revisor.revisor.svc.cluster.local` si no hay políticas.
- [ ] Ante un Deployment con `READY 0/1` y sin Pods, vas al ReplicaSet y encuentras `FailedCreate … violates PodSecurity`; y sabes por qué `apply` no falló.
- [ ] Lees un rechazo de `restricted` y nombras las cuatro reglas y la línea del `securityContext` que arregla cada una.
- [ ] Escribes un `Role` y un `RoleBinding` sin comodines, y pruebas lo permitido y lo negado con `kubectl auth can-i … --as=…`, con una petición real y desde un Pod.
- [ ] Explicas por qué el `revisor` no lleva token montado y el `lector` sí, y qué alcanza el `lector` con el suyo.
- [ ] Distingues `exit code 28` (silencio de red), `7` (nadie escucha) y `403` (sí llegó y se le negó).
- [ ] Dices, para cada una de las seis políticas, qué se rompe si falta, y por qué `revisor-salida` y `prueba-entrada` producen el mismo síntoma.
- [ ] Corres `programas/07-aislar-permisos-red/correr.sh > /tmp/mi-corrida-l7.txt 2>&1` y comparas `/tmp/mi-corrida-l7.txt` contra `programas/07-aislar-permisos-red/correr.salida.txt` (no redirijas a ese archivo: es la referencia) en lo que no cambia entre corridas: tres nodos `Ready` (la versión del nodo la fija `kind-curso.yaml` por su huella); `-rw-------` en los dos `token.txt`; las siete etiquetas del espacio `revisor` con `restricted` y `v1.37`; `default` con solo el Service `kubernetes`; el rechazo `violates PodSecurity "restricted:v1.37"` con sus cuatro reglas; `baseline:latest` rechaza `hostNetwork` y acepta el Pod sencillo; `namespace/revisor not labeled (server dry run)`; la ReplicaFailure de `sinreglas`; en los `can-i`, `no` para el `revisor`, `yes` al leer Pods y bitácoras con `observador` y `no` al borrar, al leer Secrets y al leer en `default`; `pods 200`, `secrets 403`, `pods-default 403` y el directorio ausente en `intruso`; sin reglas, las pruebas responden; con `cerrado`, dan 28 y `000` desde fuera; con las seis, `depurar` llega y `intruso` no; y las cinco filas de la tabla de 7.5.6. Las IP, los sufijos de los nombres, las edades, el nombre del Secret, los milisegundos y los tiempos de arranque cambian en cada corrida: se observan, no se comparan.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l7`.

## Resumen

Responde sin mirar la lección:

1. ¿Qué dos cosas aísla un espacio de nombres y qué una no? ¿Qué midió 7.5.3 para demostrarlo?
2. ¿Cuáles son los tres modos y los tres niveles de Pod Security Admission, y cómo se escriben en el espacio?
3. ¿Por qué un Deployment que viola `restricted` se crea y se queda sin Pods? ¿Dónde está el motivo?
4. ¿Qué agrega un `Role` y qué agrega un `RoleBinding`? ¿Qué quiere decir que los permisos son aditivos?
5. ¿Qué hace `kubectl auth can-i … --as=system:serviceaccount:ESPACIO:CUENTA` y qué código de salida devuelve con `no`?
6. ¿Por qué el `revisor` declara `automountServiceAccountToken: false`, y qué se mide con el `lector` que lo tiene en `true`?
7. ¿Cuándo está aislado un Pod para la entrada? ¿Qué pasa si dos políticas lo seleccionan?
8. ¿Qué condición necesita una `NetworkPolicy` para tener efecto, y cómo se comprobó en kind?
9. ¿Qué significan `exit code 28`, `exit code 7` y `403`?
10. ¿Por qué `acceso-revisor-salida` existe? ¿Y por qué `dns`?
11. ¿Qué cubre `allowedRoutes` y qué cubre `ReferenceGrant`?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Namespaces»](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/): los espacios como mecanismo para aislar grupos de recursos, nombres únicos por espacio, objetos con y sin espacio, el espacio `kube-system`, y la etiqueta automática `kubernetes.io/metadata.name`.
- [Kubernetes, «Pod Security Admission»](https://kubernetes.io/docs/concepts/security/pod-security-admission/): los tres modos (`enforce`, `audit`, `warn`), los tres niveles, la sintaxis de las etiquetas con y sin versión, y que `enforce` se aplica a los Pods y no a las cargas de trabajo.
- [Kubernetes, «Pod Security Standards»](https://kubernetes.io/docs/concepts/security/pod-security-standards/): las definiciones de `privileged`, `baseline` y `restricted`.
- [Kubernetes, «Enforce Pod Security Standards with Namespace Labels»](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): cómo poner las etiquetas en un espacio nuevo y en uno existente, el `--dry-run=server`, y que al agregar `enforce` el controlador prueba los Pods existentes y devuelve advertencias.
- [Kubernetes, «Service Accounts»](https://kubernetes.io/docs/concepts/security/service-accounts/): qué es una cuenta de servicio, la cuenta `default` de cada espacio, el montaje automático de credenciales y los tokens de vida corta desde la 1.22.
- [Kubernetes, «Configure Service Accounts for Pods»](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/): cómo desactivar el montaje en la cuenta y en el Pod, y que el Pod tiene precedencia.
- [Kubernetes, «Using RBAC Authorization»](https://kubernetes.io/docs/reference/access-authn-authz/rbac/): `Role` y `ClusterRole`, `RoleBinding`, que los permisos son puramente aditivos, los roles por omisión (`system:basic-user`, `system:discovery`), el riesgo de los comodines y las restricciones por `resourceNames`.
- [Kubernetes, «Network Policies»](https://kubernetes.io/docs/concepts/services-networking/network-policies/): el modelo de aislamiento (no aislado hasta que una política selecciona al Pod, y políticas aditivas), el requisito de un complemento que las aplique, el tráfico del nodo, `hostNetwork`, los límites de la API, y el impacto en conexiones existentes.
- [Kubernetes, «Use Port Forwarding to Access Applications in a Cluster»](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/): que `port-forward` lo autoriza RBAC con `create` sobre `pods/portforward`.
- [kind, «Configuration»](https://kind.sigs.k8s.io/docs/user/configuration/): el complemento de red por omisión (`kindnetd`) y cómo desactivarlo.
- [kind, notas de la versión v0.24.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0): el soporte de políticas de red con `sigs.k8s.io/kube-network-policies`.
- [Gateway API, «Cross-Namespace routing»](https://gateway-api.sigs.k8s.io/guides/multiple-ns/): rutas que se cuelgan de un Gateway de otro espacio con `allowedRoutes`.
- [Gateway API, «ReferenceGrant»](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): el permiso del espacio destino para que una ruta apunte a su Service; los campos `from` y `to`, y que solo autoriza referencias hacia recursos de su propio espacio.
- [Gateway API, referencia de la API (spec)](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/): `RouteNamespaces` y su valor por omisión, `from: Same`. Lo mismo se leyó en el propio clúster con `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` y `kubectl explain referencegrant.spec`, y el estado `RefNotPermitted` de la ruta lo confirma.
- [CyberScoop, «Tesla falls victim to cryptomining scheme, minor breach»](https://cyberscoop.com/tesla-cryptomining-redlock-cloud-breach/) (20 de febrero de 2018): el caso con el que abre la lección, a partir del reporte de RedLock.

---

**Siguiente:** [Lección 8 — Datos y tareas](08-datos-y-tareas.md)
