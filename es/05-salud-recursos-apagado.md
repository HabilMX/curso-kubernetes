# Lección 5 — Salud, recursos y apagado ordenado

Jueves, 6:40 de la tarde. El servicio de prueba lleva diez minutos caído y el tablero lo dice bien: `FALLA codigo 503`. Para eso existe el `revisor`. Pero a las 6:42 el tablero deja de cargar. Pides los Pods y ves algo que no esperabas: las tres réplicas del `revisor` tienen `RESTARTS 4`, `RESTARTS 5`, `RESTARTS 5`, y dos de ellas dicen `CrashLoopBackOff`. Nadie tocó el `revisor`. Lo que alguien sí tocó, el martes, fue su comprobación de salud: «para que sea más completa», le pidió que preguntara también por el servicio de prueba. Ahora el servicio de prueba está caído, la comprobación del `revisor` falla, el clúster concluye que el `revisor` está muerto y lo reinicia, una y otra vez. La herramienta que te tenía que avisar del problema es la primera víctima del problema. Y a las 7:00 tienes que explicar qué pasó.

El clúster no se equivocó: hizo exactamente lo que le dijeron. Esta lección te enseña a decirle lo correcto. Cómo sabe el clúster que un contenedor arrancó, que puede recibir tráfico y que sigue vivo, y por qué esas tres preguntas son distintas. Cuánta CPU y memoria le toca a cada contenedor, y qué pasa cuando pide de más. Y qué hace el `revisor` en los segundos que le da el clúster cuando le pide que se apague.

**Tiempo:** 2 × 45 min

**Qué construyes:** un `revisor` que el clúster sabe vigilar: con sondas de arranque, de disponibilidad y de vida, con un piso y un techo de CPU y memoria, y con un plazo de apagado a su medida; y el servicio de prueba con su propia sonda y sus propios límites

**Qué aprendes:** qué pregunta cada sonda (`startupProbe`, `readinessProbe`, `livenessProbe`), quién la hace y qué pasa cuando falla; por qué `/salud` no consulta a nadie; qué son `requests` y `limits`, quién usa cada uno y en qué unidades se escriben; las clases de calidad de servicio; un `OOMKilled` y un `Pending` provocados a propósito y cómo se leen; y qué pasa entre `kubectl delete pod` y que el Pod desaparezca, con `terminationGracePeriodSeconds`

**De dónde vienes.** De la [Lección 4](04-configuracion-secretos.md): el `revisor` y el servicio de prueba se aplican con `kubectl apply -k .`; la lista de servicios llega de un `ConfigMap` generado y el token de un `Secret` montado como archivo, y `/api/estados` pide `Authorization: Bearer …`. De la [Lección 3](03-services-dns.md) traes el Pod `depurar`, los EndpointSlices y su columna `ready`, que la sección 3.4.3 dejó pendiente para esta lección. Y de la [Lección 2](02-pods-deployments.md), que el `kubelet` de cada nodo es el que arranca contenedores.

**Qué no hace esta lección.** No reparte las réplicas entre nodos ni hace que una actualización no pierda peticiones: eso es la [Lección 9](09-escalar-y-actualizar.md), con `preStop`, `PodDisruptionBudget` y el escalado automático, que usa los `requests` de hoy para calcular. No publica el `revisor` hacia afuera: eso es la [Lección 6](06-entrar-al-cluster.md). Y no pone reglas para todo un espacio de nombres (un máximo por contenedor, un total por equipo): se nombran en el hábito de seguridad de la lección y quedan fuera del curso.

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1 y la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l5`. La máquina fue una Mac con procesador ARM y Docker Engine 29.2.1 dentro de una máquina virtual Linux (Colima) con 6 CPU y 16 GiB de memoria, **no** Linux Mint, que es el sistema de referencia del curso. Lo que cambia en tu Mint: la arquitectura (`amd64` en lugar de `arm64`); la CPU y la memoria que cada nodo dice tener, que en kind son las de tu máquina (5.6 lo explica), y con ellas los porcentajes de `describe node`; las direcciones IP, los sufijos al azar de los nombres, las edades, en qué nodo cae cada réplica, la hora de la bitácora y la memoria exacta que usa el `revisor`. Los comandos son los mismos. El recorrido completo está en [`programas/05-salud-recursos-apagado/`](../programas/05-salud-recursos-apagado): `correr.sh` crea el clúster, le carga las imágenes, deja todo como lo dejó la Lección 4, recorre la lección en orden, corre los Ejercicios 1 a 3 y borra el clúster. La corrida completa tardó 4 minutos y 48 segundos, y el guion registra lo que tardó cada paso largo: crear el clúster y esperar a que estuviera listo, 34 segundos; borrarlo, 1. Su salida es `correr.salida.txt`. Ahí, la capacidad de los nodos (5.6) y el error a propósito aparecen antes que el apagado (5.7), y el hábito de seguridad antes que los ejercicios, porque el guion los corre en ese orden. No usa ningún puerto de tu máquina.

## Al terminar vas a poder

- Explicar con un ejemplo la diferencia entre «arrancó», «está listo» y «está vivo», y decir qué sonda pregunta cada cosa y qué hace el clúster cuando la respuesta es «no».
- Escribir las tres sondas del `revisor` y calcular, con sus números, cuánto tarda el clúster en reaccionar a cada falla.
- Justificar por qué la sonda de vida no debe preguntar por otros servicios, y demostrarlo con el servicio de prueba caído.
- Escribir `requests` y `limits` en milicores y en mebibytes, y decir quién usa cada uno: el planificador, el `kubelet` o el núcleo de Linux.
- Provocar un `OOMKilled` y un `Pending`, leerlos con `kubectl get`, `describe` y los eventos, y corregirlos.
- Medir cuánto tarda un Pod en apagarse y explicar el papel de SIGTERM, SIGKILL y `terminationGracePeriodSeconds`.

## El porqué antes del cómo

Hasta hoy, el clúster sabe una sola cosa de tus contenedores: si el proceso está corriendo. Si el proceso muere, el `kubelet` lo reinicia; eso lo viste en la Lección 2. Pero un proceso puede estar corriendo y no servir. Puede estar arrancando todavía, sin escuchar en su puerto. Puede estar trabado en un bloqueo, vivo para el sistema operativo y muerto para sus clientes. Puede estar sano y, aun así, no querer tráfico por un momento. Para el clúster, hoy, los tres casos son iguales: `Running`. Y el Service de la Lección 3 les manda tráfico a los tres.

La primera pregunta de la lección es, entonces, **¿cómo le cuenta un contenedor al clúster cómo está?** La respuesta son las **sondas** (*probes*): preguntas que el `kubelet` le hace al contenedor cada cierto tiempo. Hay tres, porque hay tres preguntas distintas, y cada respuesta negativa tiene una consecuencia distinta: esperar, dejar de mandarle tráfico o reiniciarlo. Confundirlas es la escena del jueves.

La segunda pregunta es **¿cuánto le toca a cada uno?** Hoy el `revisor` no dice cuánta CPU ni cuánta memoria necesita, y el clúster lo pone donde sea, sin contar. Un contenedor sin techo puede comerse la memoria de un nodo entero y llevarse a todos sus vecinos. Los **`requests`** dicen cuánto necesita para que el planificador le busque lugar; los **`limits`** dicen hasta dónde puede llegar.

La tercera es **¿cómo se va?** Cada vez que borras un Pod, haces un *rollout* o el clúster mueve algo, un contenedor recibe la orden de apagarse. Si la atiende, termina lo que estaba haciendo y sale. Si no, el clúster espera un plazo y lo mata. Ese plazo se escribe en el manifiesto.

La lección tiene siete partes de conceptos y después las secciones de siempre:

1. **El clúster de la lección y lo que sabe hoy** (5.1).
2. **Los manifiestos de la lección** (5.2), campo por campo.
3. **Las tres sondas** (5.3): qué pregunta cada una y cuándo reacciona.
4. **Las sondas, en marcha** (5.4): aplicar, mirar y leerlas en la bitácora.
5. **Por qué `/salud` no consulta a nadie** (5.5): la escena del jueves, al revés.
6. **`requests`, `limits` y la capacidad de los nodos** (5.6).
7. **El apagado ordenado** (5.7).

Este es el destino. Al final de 5.4, cada réplica del `revisor` tiene sus tres sondas, su piso y su techo, y un plazo de apagado de 10 segundos:

```text
$ kubectl describe pod revisor-578c8dc8d9-g9lhl | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests|cpu:|memory:'
Name:             revisor-578c8dc8d9-g9lhl
    Limits:
      cpu:     200m
      memory:  64Mi
    Requests:
      cpu:      50m
      memory:   32Mi
    Liveness:   http-get http://:http/salud delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
    Readiness:  http-get http://:http/salud delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=2
    Startup:    http-get http://:http/salud delay=0s timeout=1s period=1s successThreshold=1 failureThreshold=10
QoS Class:                   Burstable
```

## Si no traes las imágenes del curso de Docker

Esta lección usa las mismas dos imágenes que la Lección 3: `curso-docker-revisor:1.6.0` y `curso-docker-prueba:1.0.0`. Comprueba que las tienes:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para la otra, el mismo comando con `curso-docker-prueba:1.0.0`. Si te falta alguna, la [Lección 3](03-services-dns.md) dice, en esta misma sección, cómo construir cada una desde el repositorio del curso de Docker. Lo que esta lección le pide **además** a las dos imágenes, y conviene leerlo porque cada punto explica una línea de los manifiestos:

- **El `revisor` responde `GET /salud` sin consultar a nadie**: devuelve `{"estado":"vivo","version":"1.6.0"}` con código 200 en cuanto escucha. Las tres sondas preguntan ahí.
- **El `revisor` atiende SIGTERM**: al recibirlo escribe `revisor: recibí terminated, apagando`, termina las peticiones en curso con un plazo propio de 5 segundos y escribe `revisor: apagado limpio`.
- **El servicio de prueba responde `GET /modo` siempre**, en cualquier modo, mientras el proceso viva. `GET /` es el que responde 503 en modo `caido`. Esa diferencia decide a dónde pregunta su sonda.

La imagen de `curl` del Pod `depurar` sigue siendo pública y fijada por su huella; cada nodo la descarga de internet la primera vez.

## Los conceptos

### 5.1 El clúster de la lección y lo que sabe hoy

#### 5.1.1 Crear el clúster

Esta lección usa su propio clúster, `curso-k8s-l5`, con la configuración de tres nodos de la Lección 1. Créalo así, desde la raíz del repositorio del curso, con el mismo cuidado de siempre:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L5_TMP="$(mktemp -d /tmp/curso-k8s-l5.XXXX)"
export KUBECONFIG="$L5_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: la segunda terminal de 5.7 la necesita
# curso-k8s-l5 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l5 --config programas/05-salud-recursos-apagado/kind-curso.yaml
# Debe decir kind-curso-k8s-l5. Si dice otra cosa, no sigas.
kubectl config current-context
kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l5
```

El `export` solo vale en esa terminal. Por eso la carpeta temporal queda guardada en una variable, `L5_TMP`, y el `echo` te enseña la ruta completa: si abres otra terminal (en 5.7 vas a necesitar una segunda), ahí repites el `export` con **esa** ruta, o `kubectl` le hablará a otro clúster. Y al final de la lección, la misma variable es la que te deja borrar la carpeta sin escribir la ruta a ojo. Y la regla de las lecciones anteriores sigue en pie: **antes de cada** `apply`, `delete`, `patch` o `exec` de esta lección, `kubectl config current-context` debe decir `kind-curso-k8s-l5`. El guion lo comprueba solo antes de cada `kubectl` y se detiene si no coincide.

Las salidas de esta sección son de la corrida de `correr.sh`, que hace exactamente eso:

```text
$ kubectl config current-context
kind-curso-k8s-l5

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l5-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l5-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l5-worker2         Ready    <none>          15s   v1.37.0
```

`kind load` imprime seis renglones `not yet present on node …, loading...`, dos imágenes por tres nodos, como en la Lección 3.

#### 5.1.2 El punto de partida: lo que dejó la Lección 4

La carpeta `programas/05-salud-recursos-apagado/punto-de-partida/` trae, sin cambiar una coma, los manifiestos con los que terminó la Lección 4: su `kustomization.yaml`, los dos Deployments y los dos Services. Como en esa lección, el token no se versiona: se genera en cada corrida. Esta vez se copia a las dos carpetas, la del punto de partida y la de la lección, para que las dos generen **el mismo** Secret:

```bash
cd programas/05-salud-recursos-apagado
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
ls -l punto-de-partida/token.txt token.txt  # los dos: -rw-------
TOKEN="$(cat token.txt)"
```

```text
$ ls -l punto-de-partida/token.txt token.txt | cut -d' ' -f1
-rw-------
-rw-------

$ wc -c < punto-de-partida/token.txt
      33

$ kubectl apply -k punto-de-partida
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-hct4cckkgd created
service/prueba created
service/revisor created
deployment.apps/prueba created
deployment.apps/revisor created
```

Treinta y dos caracteres hexadecimales y un salto de línea: 33 bytes. Como en la Lección 4, los paréntesis y el `umask 077` hacen que el archivo nazca con permiso `0600` (`-rw-------`), legible solo para ti, en lugar del `0644` que dejaría tu máscara habitual; `cp` sin `-p` no copia los permisos del original: crea el archivo nuevo con el modo del original filtrado por tu `umask`. Como `0600` ya no tiene permisos para grupo ni otros, la máscara no le agrega nada y la copia también queda en `0600`; con un archivo `0664` o `0755` el resultado dependería de tu `umask`, y `cp -p` es la opción que conserva modo, dueño y fechas. La primera línea del bloque es la comprobación de contexto escrita como comando: si el contexto no es el de la lección, imprime «contexto equivocado» y no sigue. Úsala antes de cada cambio; el guion lo hace solo. El nombre del ConfigMap es el mismo de la Lección 4, `revisor-config-t6cm6872fk`, porque la lista de servicios no cambió. El del Secret es otro en cada corrida, porque el token es nuevo.

#### 5.1.3 Lo que el clúster sabe hoy

```text
$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6f4dfdb898-8p5j2   1/1     Running   0          4s
revisor-f65c6dd96-248bg   1/1     Running   0          4s
revisor-f65c6dd96-575nn   1/1     Running   0          4s
revisor-f65c6dd96-pzxpk   1/1     Running   0          4s
```

Mira la columna `READY`: `1/1` a los **4 segundos**. ¿El `revisor` ya escuchaba en su puerto a esa edad? Seguramente sí, porque arranca rápido. Pero el clúster no lo comprobó: marcó el Pod como listo en cuanto el contenedor arrancó. Es lo que la Lección 3 anticipó en 3.4.3: sin sondas, «listo» quiere decir «el proceso existe». Si el `revisor` tardara diez segundos en abrir su puerto, el Service le mandaría tráfico durante esos diez segundos, y esas peticiones fallarían.

Ahora, lo que el Pod dice de sí mismo:

```text
$ kubectl describe pod revisor-f65c6dd96-248bg | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests'
Name:             revisor-f65c6dd96-248bg
QoS Class:                   BestEffort

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
30

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
PodReadyToStartContainers=True Initialized=True Ready=True ContainersReady=True PodScheduled=True 
```

El `grep` buscó sondas, `Limits` y `Requests`, y no encontró ninguno: solo el nombre y una línea, `QoS Class: BestEffort`. Es la clase de calidad de servicio del Pod, y `BestEffort` («lo que se pueda») es la que recibe un Pod que no declara nada de CPU ni de memoria. 5.6 explica qué significa; adelanto: es el primero al que el nodo saca cuando se queda sin memoria. El plazo de apagado es `30` segundos, el valor por omisión, que nadie eligió. Y las condiciones del Pod dicen `Ready=True`: es la condición que el EndpointSlice copia en su columna `ready`, y hoy se volvió verdadera sin que nadie preguntara nada.

Tres huecos: nadie comprueba que el `revisor` sirve, nadie dice cuánto necesita, y el plazo de apagado es un número heredado. Los tres se cierran con los manifiestos de esta lección.

### 5.2 Los manifiestos de la lección

La lección cambia dos archivos: los Deployments del `revisor` y del servicio de prueba. El `kustomization.yaml`, los dos Services y `depurar.yaml` son los mismos de la Lección 4 (el comentario de la primera línea del `kustomization.yaml` dice ahora «Lecciones 4 y 5»). Los dos Deployments son **programas**: se aplican con `kubectl apply -k .` desde `programas/05-salud-recursos-apagado/`.

#### 5.2.1 El `revisor`

```yaml
# revisor-deployment.yaml — Lección 5: sondas, recursos y apagado ordenado.
# /salud no consulta a nadie: si dependiera de «prueba», una caída de prueba
# reiniciaría el revisor, que no tiene la culpa.
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
      terminationGracePeriodSeconds: 10
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        fsGroup: 65532
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
          valueFrom:
            configMapKeyRef:
              name: revisor-config
              key: REVISOR_SERVICIOS
        - name: REVISOR_TOKEN_ARCHIVO
          value: /secretos/token
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
          limits:
            cpu: 200m
            memory: 64Mi
        startupProbe:
          httpGet: {path: /salud, port: http}
          periodSeconds: 1
          failureThreshold: 10
        readinessProbe:
          httpGet: {path: /salud, port: http}
          periodSeconds: 5
          failureThreshold: 2
        livenessProbe:
          httpGet: {path: /salud, port: http}
          periodSeconds: 10
          failureThreshold: 3
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
        emptyDir:
          sizeLimit: 10Mi
      - name: token
        secret:
          secretName: revisor-token
          defaultMode: 0440
```

Todo lo que no es nuevo ya lo leíste en las Lecciones 2 a 4. Lo nuevo son tres bloques y un número:

- **`terminationGracePeriodSeconds: 10`**, en la plantilla del Pod (no en el contenedor): cuántos segundos tiene el Pod para apagarse por su cuenta antes de que el clúster lo mate. 5.7.
- **`resources`**, en el contenedor: el piso (`requests`) y el techo (`limits`) de CPU y memoria. 5.6.
- **`startupProbe`, `readinessProbe` y `livenessProbe`**, en el contenedor: las tres sondas. 5.3.

Fíjate en el `port: http` de las tres sondas. Es el mismo truco de la Lección 3 con el `targetPort` del Service: el puerto va por **nombre**, así que el número `8080` sigue viviendo en un solo lugar, `containerPort`. Y `{path: /salud, port: http}` es YAML de una línea: las llaves agrupan los dos campos de `httpGet` igual que si los escribieras en dos renglones con sangría. Se escriben así porque las tres sondas comparten la misma pregunta y lo que cambia entre ellas son los números.

#### 5.2.2 El servicio de prueba

```yaml
# prueba-deployment.yaml — Lección 5: el servicio de prueba también se vigila
# y tiene sus límites. La sonda de vida usa GET /modo y NO GET /: en modo «caido»
# GET / responde 503 a propósito, y el clúster no debe matarlo por eso.
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
      terminationGracePeriodSeconds: 10
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
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
        livenessProbe:
          httpGet: {path: /modo, port: http}
          periodSeconds: 10
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Una sola sonda, la de vida, y apunta a `/modo`, **no** a `/`. El comentario del archivo lo dice y 5.5 lo demuestra: `GET /` es justo lo que el servicio de prueba rompe a propósito en modo `caido`. Si la sonda de vida preguntara ahí, el clúster lo reiniciaría cada vez que lo pongas en ese modo, que es lo contrario de lo que quieres de un servicio que existe para fallar. El Ejercicio 2 lo prueba. No lleva sonda de arranque porque arranca en milisegundos, ni de disponibilidad porque el curso quiere que el `revisor` le pueda hablar aunque esté caído; el Ejercicio 1 te enseña qué pasaría con ella.

Los recursos son menores que los del `revisor` porque hace menos: no consulta a nadie ni guarda reportes.

### 5.3 Las tres sondas

#### 5.3.1 Quién pregunta y cómo

La [documentación de sondas](https://kubernetes.io/docs/concepts/workloads/pods/probes/) empieza así: una sonda es «un diagnóstico que el `kubelet` realiza periódicamente sobre un contenedor», y con sus resultados «Kubernetes puede reiniciar contenedores no sanos o dejar de mandar tráfico a contenedores que no están listos». Retén las dos piezas: **el `kubelet`**, el del nodo donde corre el Pod, no el plano de control; y **dos reacciones distintas**, reiniciar o dejar de mandar tráfico.

Las tres sondas del `revisor` usan `httpGet`: el `kubelet` hace una petición HTTP a la IP del Pod, al puerto y a la ruta que le digas. La [guía para configurar sondas](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) dice cuándo cuenta como éxito: «cualquier código mayor o igual que 200 y menor que 400 indica éxito. Cualquier otro código indica falla». Una respuesta que no llega a tiempo también es falla. Hay otras formas de preguntar (ejecutar un comando dentro del contenedor, abrir una conexión TCP o una llamada gRPC), pero para un servidor HTTP que ya tiene su ruta de salud, la petición HTTP es la que pregunta lo que importa: no «¿existe el proceso?», sino «¿contesta?». Y el `revisor` no tiene *shell* para ejecutar comandos dentro, como viste en la Lección 2.

#### 5.3.2 Los números de una sonda

Cada sonda se ajusta con cinco campos. Los valores por omisión son de la misma documentación de sondas:

| Campo | Qué es | Por omisión |
|---|---|---|
| `initialDelaySeconds` | cuánto esperar antes de la primera pregunta | 0 s |
| `periodSeconds` | cada cuánto preguntar | 10 s (mínimo 1) |
| `timeoutSeconds` | cuánto esperar una respuesta | 1 s |
| `successThreshold` | cuántos éxitos seguidos, después de una falla, para volver a «bien» | 1 (para vida y arranque, **debe** ser 1) |
| `failureThreshold` | cuántas fallas seguidas para concluir «mal» | 3 |

La regla para leerlos: **una sonda reacciona después de `failureThreshold` fallas seguidas, separadas por `periodSeconds`**. Una falla aislada no hace nada. Eso evita que un tropiezo de un segundo dispare un reinicio. La documentación lo dice con estas palabras: después de que una sonda falla `failureThreshold` veces seguidas, «Kubernetes considera que la comprobación completa falló».

#### 5.3.3 La sonda de arranque: «¿ya arrancaste?»

La documentación de sondas: las de arranque «verifican si la aplicación dentro de un contenedor ya arrancó. Si hay una sonda de arranque, Kubernetes no ejecuta las sondas de vida ni de disponibilidad hasta que la de arranque tenga éxito». Y si falla del todo, «el `kubelet` mata el contenedor», que queda sujeto a su política de reinicio.

La del `revisor`: `periodSeconds: 1` y `failureThreshold: 10`. Pregunta cada segundo, y le da al programa hasta **10 intentos**, unos 10 segundos, para contestar la primera vez (1 × 10). Es la cuenta cuando cada intento falla de inmediato; si el programa está trabado y cada intento tiene que agotar su `timeoutSeconds` (1 segundo por omisión), el plazo se acerca a 20. En cuanto contesta, deja de preguntar mientras ese contenedor viva; si el contenedor se reinicia, vuelve a empezar. A diferencia de las otras dos, solo corre al arrancar. ¿Por qué 10 segundos si el `revisor` arranca en menos de uno? Porque el número no es para el día bueno, es para el día malo: un nodo cargado, una imagen que se lee lento. Y sobra poco: un programa que no contesta en 10 segundos algo tiene.

La guía para configurar sondas explica para qué existe esta sonda. Hay programas que tardan en arrancar, y si la sonda de vida tuviera que esperarlos, habría que hacerla lenta y dejaría de detectar a tiempo un bloqueo. La solución es separar: una sonda de arranque con un `failureThreshold * periodSeconds` «lo bastante largo para cubrir el peor caso de arranque», y una vez que tiene éxito, «la sonda de vida toma el control». Su ejemplo es un programa con hasta 5 minutos para arrancar (30 × 10 s). El `revisor` necesita mucho menos, pero el patrón es el mismo.

#### 5.3.4 La sonda de disponibilidad: «¿te mando tráfico?»

La documentación: las sondas de disponibilidad «determinan cuándo un contenedor está listo para aceptar tráfico», y si una falla, «el controlador de EndpointSlices quita la IP del Pod de los EndpointSlices de todos los Services que coinciden con el Pod». Es la columna `ready` de la Lección 3, por fin con contenido. Un matiz que vas a ver en el Ejercicio 1: en la práctica, la dirección no desaparece del EndpointSlice, sino que se queda con `ready=false`, y eso basta para que `kube-proxy` deje de mandarle tráfico. «Quitar del tráfico» es el efecto; «marcar como no lista» es el mecanismo. Y algo que la distingue de la de arranque: «las sondas de disponibilidad corren en el contenedor durante todo su ciclo de vida».

Lo más importante es lo que **no** hace: no reinicia nada. La documentación de sondas, en la descripción de `failureThreshold`: con una sonda de disponibilidad fallida, «el `kubelet` sigue corriendo el contenedor que falló y sigue haciendo más sondas», y solo pone la condición `Ready` del Pod en `false`. Cuando la sonda vuelve a pasar, el Pod vuelve a la lista. Es la sonda para «estoy bien, pero ahora no».

La del `revisor`: cada 5 segundos, y 2 fallas seguidas lo sacan del Service. En el peor caso, un `revisor` que deja de contestar sigue recibiendo tráfico unos **10 segundos** (2 × 5) antes de salir de la lista.

#### 5.3.5 La sonda de vida: «¿sigues vivo?»

La documentación: las sondas de vida «determinan cuándo reiniciar un contenedor». El ejemplo que da es un bloqueo (*deadlock*), «donde una aplicación está corriendo pero no puede avanzar». Si el contenedor falla más veces de las toleradas, «el `kubelet` reinicia ese contenedor».

Es la única de las tres que destruye algo: un reinicio tira las conexiones abiertas y el estado en memoria. Por eso la misma página la acompaña de una advertencia, que es la escena del jueves en lenguaje de manual: las sondas de vida «deben configurarse con cuidado para asegurar que de verdad indican una falla irrecuperable de la aplicación», y «una implementación incorrecta de las sondas de vida puede provocar fallas en cascada».

La del `revisor`: cada 10 segundos, y 3 fallas seguidas lo reinician. Un `revisor` trabado se reinicia en unos **30 segundos** (3 × 10). Más lenta que la de disponibilidad a propósito: la documentación describe ese patrón como el común, la misma ruta barata para las dos y un `failureThreshold` mayor en la de vida, para que el Pod se vea «no listo» un rato antes de que se le mate. Así, un tropiezo pasajero saca al Pod del tráfico (que es barato) mucho antes de reiniciarlo (que es caro).

#### 5.3.6 Las tres juntas

| Sonda | Pregunta | Si la respuesta es «no» | Cuándo corre | En el `revisor` |
|---|---|---|---|---|
| arranque | ¿ya arrancaste? | espera; si se acaba el plazo, reinicia | solo al arrancar | hasta 10 s (1 s × 10) |
| disponibilidad | ¿te mando tráfico? | te saca del Service; **no** reinicia | siempre | sale en ~10 s (5 s × 2) |
| vida | ¿sigues vivo? | **reinicia** el contenedor | siempre, después de la de arranque | reinicia en ~30 s (10 s × 3) |

Las tres del `revisor` preguntan lo mismo, `GET /salud`. No es redundancia: es la misma pregunta con tres consecuencias y tres paciencias distintas.

### 5.4 Las sondas, en marcha

#### 5.4.1 Antes de aplicar, mirar qué cambia

Primero se comprueba que las dos carpetas tienen el mismo token, y después se le pregunta al clúster qué cambiaría:

```text
$ diff punto-de-partida/token.txt token.txt && echo 'mismo token'
mismo token

$ kubectl diff -k . | grep -E '^\+ ' | grep -vE 'generation|resourceVersion|uid:|creationTimestamp'
+        livenessProbe:
+          failureThreshold: 3
+          httpGet:
+            path: /modo
+            port: http
+            scheme: HTTP
+          periodSeconds: 10
+          successThreshold: 1
+          timeoutSeconds: 1
+        resources:
+          limits:
+            cpu: 100m
+            memory: 32Mi
+          requests:
+            cpu: 10m
+            memory: 16Mi
+      terminationGracePeriodSeconds: 10
+        livenessProbe:
+          failureThreshold: 3
+          httpGet:
+            path: /salud
+            port: http
+            scheme: HTTP
+          periodSeconds: 10
+          successThreshold: 1
+          timeoutSeconds: 1
+        readinessProbe:
+          failureThreshold: 2
+          httpGet:
+            path: /salud
+            port: http
+            scheme: HTTP
+          periodSeconds: 5
+          successThreshold: 1
+          timeoutSeconds: 1
+        resources:
+          limits:
+            cpu: 200m
+            memory: 64Mi
+          requests:
+            cpu: 50m
+            memory: 32Mi
+        startupProbe:
+          failureThreshold: 10
+          httpGet:
+            path: /salud
+            port: http
+            scheme: HTTP
+          periodSeconds: 1
+          successThreshold: 1
+          timeoutSeconds: 1
+      terminationGracePeriodSeconds: 10
[código de salida: 1]
```

`kubectl diff -k .` compara lo que aplicarías con lo que hay; los dos `grep` se quedan con las líneas que se **agregan** (empiezan con `+ `) y quitan las que cambian siempre. Primero viene el Deployment de prueba, después el del `revisor`. Fíjate en tres cosas. Ningún ConfigMap ni Secret aparece: el token es el mismo y la lista también, así que sus nombres con *hash* no cambian. Los campos que no escribiste (`scheme: HTTP`, `successThreshold: 1`, `timeoutSeconds: 1`) aparecen con su valor por omisión, el de la tabla de 5.3.2: así se ve lo que de verdad va a correr. Y el código de salida 1 no es un error: `kubectl diff` sale con 1 cuando **hay** diferencias, y con 0 cuando no. Al final de la lección lo vas a usar al revés, para comprobar que no queda ninguna.

Sobre esa última línea, `[código de salida: 1]`: no la escribe `kubectl`, la escribe el guion cada vez que un comando sale con un código distinto de 0, y la vas a ver en otros bloques de la lección. El guion corre con `set -o pipefail`, así que el código de una tubería es el del primer comando que falla, aquí `kubectl diff`. En tu terminal, sin esa opción, `echo $?` te daría el código del último `grep`, que es 0. Para comprobarlo sin tubería: `kubectl diff -k . >/dev/null; echo $?`, que da `1`.

#### 5.4.2 Aplicar

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hct4cckkgd unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba configured
deployment.apps/revisor configured

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-g9lhl   1/1     Running   0          11s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          9s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          12s
```

Solo los dos Deployments cambian, y cambiar la plantilla de un Pod es un *rollout*: un ReplicaSet nuevo (`revisor-578c8dc8d9`) que reemplaza las réplicas una por una. Las edades lo cuentan: 12, 11 y 9 segundos, una o dos de diferencia entre una y otra. Y esta vez el reemplazo esperó a que cada réplica nueva pasara su sonda de disponibilidad antes de retirar una vieja: un Deployment cuenta como «disponible» solo a un Pod listo. Sin sondas, «listo» llegaba antes de saber nada.

El `describe` de una de las réplicas nuevas es el destino que viste al principio:

```text
$ kubectl describe pod revisor-578c8dc8d9-g9lhl | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests|cpu:|memory:'
Name:             revisor-578c8dc8d9-g9lhl
    Limits:
      cpu:     200m
      memory:  64Mi
    Requests:
      cpu:      50m
      memory:   32Mi
    Liveness:   http-get http://:http/salud delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
    Readiness:  http-get http://:http/salud delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=2
    Startup:    http-get http://:http/salud delay=0s timeout=1s period=1s successThreshold=1 failureThreshold=10
QoS Class:                   Burstable

$ kubectl get pod revisor-578c8dc8d9-g9lhl -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
10
```

Así se lee una sonda en `describe`: `http-get http://:http/salud` es «petición HTTP a la IP del Pod (va vacía, entre `//` y `:`), al puerto llamado `http`, ruta `/salud`»; después vienen los cinco números de 5.3.2, con `delay` en lugar de `initialDelaySeconds` y `period` en lugar de `periodSeconds`. La clase pasó de `BestEffort` a `Burstable`, y el plazo de apagado de 30 a 10.

#### 5.4.3 Leer las sondas en la bitácora

Cada sonda es una petición HTTP de verdad, y el `revisor` escribe una línea por cada petición que atiende. Su bitácora, con la hora de cada línea:

```text
$ kubectl logs --timestamps revisor-578c8dc8d9-g9lhl | head -9 | sed -E 's/^[0-9-]+T([0-9:]+)\.[0-9]+Z/\1/'
13:45:44 revisor 1.6.0 escuchando en :8080 (1 servicio(s))
13:45:45 revisor: GET /salud 200 0s
13:45:45 revisor: GET /salud 200 0s
13:45:50 revisor: GET /salud 200 0s
13:45:54 revisor: GET /salud 200 0s
13:45:55 revisor: GET /salud 200 0s
13:46:00 revisor: GET /salud 200 0s
13:46:04 revisor: GET /salud 200 0s
13:46:05 revisor: GET /salud 200 0s

$ kubectl get pod revisor-578c8dc8d9-g9lhl -o jsonpath='{.status.startTime} {.status.containerStatuses[0].started} {.status.containerStatuses[0].ready}{"\n"}'
2026-10-21T13:45:43Z true true
```

(`--timestamps` antepone a cada línea la hora en que se escribió, en UTC y con nanosegundos; el `sed` solo recorta la fecha y los decimales para que quepa. La bitácora de nadie más dice estas horas: esas son las de esta corrida.)

Ahora léela como un reloj (son minutos 45 y 46). El programa empezó a escuchar a las `:44`. A las `:45` hay **dos** peticiones. La primera es la **sonda de arranque**, que pregunta cada segundo y aquí no necesitó más de una; desde ese momento ya no vuelve a preguntar, y entran las otras dos. La segunda, en el mismo segundo, es la primera de **disponibilidad**: la documentación de sondas avisa que, mientras un contenedor no está listo, esa sonda puede correr fuera de su periodo, para que el Pod quede listo antes. Desde ahí hay una línea cada 5 segundos (`:45`, `:50`, `:55`, `:00`, `:05`): la de disponibilidad. Y entre ellas, una cada 10 (`:54`, `:04`): la de **vida**. Exactamente los `periodSeconds` del manifiesto. El segundo comando confirma el resultado: el contenedor arrancó (`started` en `true`) y está listo (`ready` en `true`).

Dos consecuencias prácticas. La primera: a este ritmo, cada réplica escribe unas 18 líneas por minuto solo de sondas, más de 25 mil al día. Si tu programa escribe una línea por petición, las sondas van a llenar su bitácora, y conviene saberlo antes de buscar algo ahí. La segunda: las sondas **cuestan**. Cada pregunta es trabajo del `kubelet` y del programa. Por eso `/salud` debe ser barata, y por eso los periodos no se ponen en un segundo «por si acaso».

### 5.5 Por qué `/salud` no consulta a nadie

#### 5.5.1 La escena del jueves, al revés

El `revisor` existe para decirte que otros servicios fallan. Si su salud dependiera de esos servicios, el clúster lo castigaría justo cuando hace su trabajo. Se comprueba: el Pod `depurar` de la Lección 3, el servicio de prueba en modo `caido`, y 35 segundos de espera, más que los 30 que tarda la sonda de vida en reiniciar.

```text
$ kubectl apply -f depurar.yaml
pod/depurar created

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-b896986b5-kzrmk     1/1     Running   0          92s
revisor-578c8dc8d9-g9lhl   1/1     Running   0          91s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          89s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          92s

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $TOKEN" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  codigo 503

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano
modo: sano
```

(En `correr.salida.txt` el token aparece escrito: el guion lo pega en el comando. Es un token de mentira de esa corrida, que murió con el clúster.)

Cero reinicios en los cuatro Pods, todos `1/1`, y el reporte dice lo que tiene que decir: `prueba FALLA codigo 503`. Es lo contrario de la escena del jueves, y la diferencia está en una sola decisión de diseño: `/salud` contesta «estoy vivo» sin preguntarle nada a nadie. El comentario de la primera línea del manifiesto lo deja escrito para quien venga después.

Fíjate también en el servicio de prueba: `RESTARTS 0` y `1/1`, aunque lleva más de 35 segundos respondiendo 503 en `/`. Su sonda de vida pregunta por `/modo`, que sigue contestando. El clúster distingue «está fallando a propósito» de «está muerto» porque le preguntaste lo correcto.

#### 5.5.2 ¿Y la documentación no dice que se revisen las dependencias?

Lo dice, con matiz, y conviene leerlo entero. La documentación de sondas, en la parte de cuándo usar cada una: «cuando tu aplicación tiene una dependencia estricta de servicios de *backend*, puedes implementar una sonda de vida y una de disponibilidad. La sonda de vida pasa cuando la aplicación en sí está sana, pero la de disponibilidad comprueba además que cada servicio de *backend* requerido esté disponible».

Dos cosas. La primera es la regla que nunca cambia: **la sonda de vida mira solo a la aplicación**. Incluso en ese párrafo, la dependencia va en la de disponibilidad, nunca en la de vida. Reiniciar tu programa no arregla la base de datos de otro equipo; solo te deja sin programa.

La segunda es un criterio, y depende de qué hace tu servicio. Si tu servicio no puede responder nada útil sin su base de datos, sacarlo del tráfico mientras ella falta tiene sentido. El `revisor` es el caso opuesto: **su respuesta útil es justamente decir quién falta**. Si su sonda de disponibilidad dependiera de `prueba`, al caer `prueba` el Service del `revisor` se quedaría sin réplicas y el tablero no cargaría, que es el síntoma de la escena por otra vía. Por eso las tres sondas del `revisor` preguntan a `/salud`, y `/salud` no pregunta a nadie. El Ejercicio 1 te deja ver esa otra vía con el servicio de prueba.

### 5.6 `requests`, `limits` y la capacidad de los nodos

#### 5.6.1 Dos números con dos dueños distintos

La [documentación de gestión de recursos](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) los separa por quién los usa: «cuando especificas el *request* de un recurso para los contenedores de un Pod, el `kube-scheduler` usa esa información para decidir en qué nodo poner el Pod. Cuando especificas un *limit* para un contenedor, el `kubelet` hace cumplir esos límites para que el contenedor no use más de ese recurso que el límite que fijaste».

- **`requests` es una reserva.** El planificador la usa al elegir nodo, y el `kubelet` la respeta después: la misma página dice que el `kubelet` también aparta «al menos la cantidad del *request*» para ese contenedor, así que, cuando hay competencia por la CPU, el contenedor conserva su parte. Sobre el planificador, la misma página: el planificador se asegura de que, para cada recurso, la suma de los *requests* de los contenedores de un nodo sea menor que su capacidad, y lo hace aunque el uso real sea muy bajo: «el planificador se niega a poner un Pod en un nodo si la comprobación de capacidad falla». El `request` no es lo que el contenedor usa: es lo que el nodo le aparta.
- **`limits` es un techo**, y lo hacen cumplir el `kubelet` y el núcleo de Linux todo el tiempo.

#### 5.6.2 Las unidades

**CPU.** La misma página: «1 unidad de CPU equivale a 1 núcleo físico de CPU, o a 1 núcleo virtual» si el nodo es una máquina virtual, y se admiten fracciones: `0.1` es lo mismo que `100m`, «que se lee como cien milicpu». El `revisor` pide `50m`, la vigésima parte de un núcleo, y su techo es `200m`, la quinta parte. La documentación recomienda la forma con `m` para cantidades menores que 1, porque se lee mejor.

**Memoria.** En bytes, con sufijos. Hay dos familias: `M`, `G` (potencias de 10) y `Mi`, `Gi` (potencias de 2). `32Mi` son 32 mebibytes, 33,554,432 bytes; `32M` serían 32,000,000. El curso usa `Mi`. Y una trampa que la documentación señala con todas sus letras: «presta atención a las mayúsculas de los sufijos». `400m` de memoria son 0.4 **bytes**, no 400 megas: la `m` minúscula es «mili». Un `memory: 64m` escrito por error es un techo de una fracción de byte: el contenedor no puede ni arrancar. (Esto no se midió en la lección; lo que sí se midió al preparar el curso es que con un techo de `4Mi` el `revisor` ya da `StartError`, como dice el comentario de `memoria.yaml`.)

#### 5.6.3 Qué pasa al llegar al techo

El techo no se aplica igual a los dos recursos, y la diferencia es de las que más importan en este curso. La documentación de gestión de recursos:

- **CPU:** «los límites de `cpu` se aplican estrangulando la CPU». Si el `revisor` quisiera más de `200m`, el núcleo simplemente no se la da: el programa va más lento, pero sigue vivo.
- **Memoria:** «los límites de `memory` los aplica el núcleo con muertes por falta de memoria (OOM)». La memoria que un programa ya tiene no se le puede quitar a medias, así que, cuando se pasa y el núcleo no puede recuperar memoria de otro lado (por ejemplo, de la caché de archivos), lo mata. La documentación lo llama un límite «reactivo»: no evita el exceso, lo castiga. El error a propósito de esta lección es exactamente eso.

La regla práctica que sale de ahí: un techo de CPU bajo hace a tu programa **lento**; un techo de memoria bajo lo hace **morir**. Los dos se ponen, pero el de memoria se pone con más margen.

#### 5.6.4 Lo que un nodo de kind dice tener

¿Cuánto cabe en un nodo? Se le pregunta:

```text
$ kubectl get nodes -o custom-columns='NODO:.metadata.name,CPU:.status.allocatable.cpu,MEMORIA:.status.allocatable.memory'
NODO                         CPU   MEMORIA
curso-k8s-l5-control-plane   6     16342676Ki
curso-k8s-l5-worker          6     16342676Ki
curso-k8s-l5-worker2         6     16342676Ki
```

(`custom-columns` arma una tabla con los campos que le pidas; `allocatable` es lo que el nodo ofrece a los Pods.)

Cada nodo dice tener 6 CPU y unos 15.6 GiB. Son, los tres, **toda** la máquina virtual de Docker de esta corrida: 6 CPU y 16 GiB. Esto es kind, y no lo olvides nunca: sus nodos son contenedores en la misma máquina, y cada uno ve y anuncia los recursos completos del anfitrión. Para el planificador hay 18 CPU; en el metal hay 6. En un clúster real, cada nodo anuncia lo suyo. En kind, `requests` y `limits` funcionan igual que en uno real —el planificador cuenta y el núcleo corta—, pero la capacidad que ves es un espejismo de laboratorio. En tu Mint, los números serán los de tu computadora.

Lo que el planificador ya apartó en un nodo de trabajo:

```text
$ kubectl describe node curso-k8s-l5-worker | sed -n '/^Allocated resources:/,/^Events:/p' | head -8
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests   Limits
  --------           --------   ------
  cpu                150m (2%)  200m (3%)
  memory             82Mi (0%)  64Mi (0%)
  ephemeral-storage  0 (0%)     0 (0%)
  hugepages-1Gi      0 (0%)     0 (0%)
```

`Requests` suma lo que piden todos los Pods del nodo, los tuyos y los del sistema. En esta corrida, en `worker` cayó una réplica del `revisor` (sus `50m` y `32Mi`, y sus `200m` y `64Mi` de techo, que son toda la columna `Limits`); el resto de los *requests* son de los Pods del sistema que corren en cada nodo, como la red de kind. La nota del principio, «los límites totales pueden pasar del 100 %», dice algo importante: el planificador **no** cuenta los `limits`. Puedes prometer más techo del que hay, porque se supone que no todos llegan a su techo a la vez. Lo que el planificador no deja pasar del 100 % de la capacidad asignable es la suma de `requests` al decidir dónde cae un Pod ordinario (los Pods estáticos del propio nodo no pasan por él).

#### 5.6.5 Cuánto usa de verdad el `revisor`

Los números del manifiesto son decisiones. ¿Están cerca de la realidad? El `kubelet` habla con el `containerd` del nodo, y `crictl` le puede preguntar cuánto usa cada contenedor (es la misma herramienta de la Lección 2, dentro del nodo):

```text
$ docker exec curso-k8s-l5-worker2 crictl stats --label io.kubernetes.container.name=revisor | sed 's/^.\[2J.\[H//'
CONTAINER           NAME                CPU %               MEM                 DISK                INODES              SWAP
060935005135f       revisor             0.02                1.733MB             45.06kB             13                  0B
1be34aa64c901       revisor             0.03                1.733MB             45.06kB             13                  0B
```

(`--label` filtra los contenedores que se llaman `revisor`; en `worker2` cayeron dos réplicas. `crictl stats` imprime al principio unos códigos para limpiar la pantalla, y el `sed` los quita.)

Menos de 2 MB de memoria y la CPU casi en cero, en reposo. El `request` de `32Mi` es más de quince veces eso. No es un error: el `revisor` crece cuando arma un reporte y consulta varios servicios a la vez, y un `request` es lo que el programa necesita en su día normal con carga, no en reposo. Pero el número confirma algo que vas a usar en un momento: el `revisor` **no sirve** para provocar un `OOMKilled`, porque casi no usa memoria. Para verlo hace falta un programa que la pida.

En un clúster real, esta medición se hace con `kubectl top`, que necesita `metrics-server`. Llega en la Lección 9, porque es la que alimenta el escalado automático.

#### 5.6.6 Las clases de calidad de servicio

Con `requests` y `limits` el clúster clasifica cada Pod en una de tres clases. La [documentación de clases de QoS](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) da los criterios:

| Clase | Cuándo | En este curso |
|---|---|---|
| `Guaranteed` | todo contenedor tiene `requests` y `limits` de CPU y de memoria, y en cada uno el `request` es **igual** al `limit` | ninguno |
| `Burstable` | no es `Guaranteed`, pero al menos un contenedor tiene algún `request` o `limit` | `revisor`, `prueba`, `depurar`, `memoria` |
| `BestEffort` | ningún contenedor declara nada de CPU ni de memoria | el `revisor` de 5.1 |

Y para qué sirve: cuando un nodo se queda sin recursos, «Kubernetes saca primero a los Pods `BestEffort` de ese nodo, después a los `Burstable` y al final a los `Guaranteed`». Y agrega que, cuando el desalojo es por falta de recursos, solo son candidatos los Pods que usan más de lo que pidieron. La página más detallada de desalojo por presión del nodo lo precisa: el `kubelet` saca primero a los `BestEffort` y a los `Burstable` que exceden su `request`, y los `Guaranteed` y los `Burstable` que no lo exceden se desalojan al final, si lo anterior no bastó. Es decir, respetar tu `request` te pone al final de la fila, no fuera de ella. Otra razón para que el `request` se parezca al uso real. El `revisor` de 5.1 era el primero de la fila. Hoy es `Burstable`, porque su techo es mayor que su piso: puede «estirarse» de `50m` a `200m` si hay CPU libre. Para hacerlo `Guaranteed` tendrías que igualar los dos números, y pagar siempre el techo como reserva. Para un programa que en reposo usa 2 MB, el curso prefiere `Burstable`.

### 5.7 El apagado ordenado

#### 5.7.1 Qué pasa cuando borras un Pod

La [documentación del ciclo de vida de un Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) cuenta la secuencia. Al pedir que se borre un Pod, el clúster anota un plazo, y el `kubelet` del nodo empieza el apagado: le pide al *runtime* del contenedor que mande «una señal TERM» (SIGTERM) «al proceso 1 dentro de cada contenedor», es decir, al proceso principal, el que tiene el PID 1. Y después: «una vez que el plazo vence, se manda la señal KILL a los procesos que queden». SIGTERM es una petición («apágate, por favor»); SIGKILL no es una petición, es el núcleo terminando el proceso sin preguntarle. El plazo por omisión es de **30 segundos**, y se cambia con `terminationGracePeriodSeconds`.

Al mismo tiempo pasa otra cosa, la que conecta con la Lección 3: el plano de control saca al Pod que se apaga del tráfico. La misma página: sus *endpoints* no se borran de inmediato del EndpointSlice, pero quedan marcados como `terminating` y «siempre tienen su estado `ready` en `false`», así que no reciben tráfico nuevo. (La página de EndpointSlices agrega una excepción que el curso no usa: `ready` es siempre verdadero en un Service con `publishNotReadyAddresses: true`.) Las dos cosas ocurren a la vez, no una después de la otra. Esa carrera entre «el Pod recibe SIGTERM» y «todos los nodos se enteran de que ya no deben mandarle tráfico» es la que la Lección 9 resuelve con `preStop`. Hoy basta con saber que existe.

#### 5.7.2 Verlo

*Un aviso sobre los nombres.* Las salidas de esta sección y de las dos siguientes vienen de la corrida del guion, donde el apagado ocurrió **después** de los dos errores de «El error que vas a ver». Por eso el Pod que aquí se borra, `g9lhl`, todavía aparece vivo en la sección de `Pending`, y el `hfjmq` que lo repone ya aparece en el hábito de seguridad: no es un error de tu clúster ni de la lección. En tu máquina, si sigues la lección en el orden del texto, los nombres serán otros.

Para ver lo que el `revisor` escribe en sus últimos segundos, abre una **segunda terminal** y prepárala así, con la ruta que imprimió el `echo` de 5.1.1 (en la primera terminal, `echo "$KUBECONFIG"` te la vuelve a dar):

```bash
# En la SEGUNDA terminal. Pega la ruta completa; la de abajo es solo la forma.
export KUBECONFIG=/tmp/curso-k8s-l5.XXXX/kubeconfig
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
kubectl logs -f <nombre de una réplica del revisor>
```

Si la comprobación dice «contexto equivocado», la ruta no es la buena: no sigas. Con `kubectl logs -f` corriendo ahí, en la primera terminal borra esa réplica:

```text
$ kubectl delete pod revisor-578c8dc8d9-g9lhl
pod "revisor-578c8dc8d9-g9lhl" deleted from default namespace
(el borrado tardó 0 s)

$ kubectl logs -f revisor-578c8dc8d9-g9lhl   # lo que se alcanzó a leer, en otra terminal
revisor: GET /salud 200 0s
revisor: GET /salud 200 0s
revisor: recibí terminated, apagando
revisor: apagado limpio

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-hfjmq   1/1     Running   0          3s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          2m23s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          2m26s
```

(`-f` sigue la bitácora en vivo hasta que el contenedor termina; el guion la guarda en un archivo y muestra sus cuatro últimas líneas.)

`kubectl delete` espera a que el Pod de verdad desaparezca, y tardó **menos de un segundo** (el guion mide en segundos enteros y anotó `0 s`; en otras corridas anotó 1 y 3). Las dos últimas líneas de la bitácora son el apagado ordenado: el `revisor` recibió `terminated` (así llama Go a SIGTERM), dejó de aceptar conexiones nuevas, esperó a que terminaran las que tenía y salió por su cuenta: `apagado limpio`. Nunca llegó al SIGKILL. Y el ReplicaSet ya había repuesto la réplica: `hfjmq`, de 3 segundos.

#### 5.7.3 Por qué 10 segundos

Si el `revisor` se fue en menos de un segundo, ¿para qué cambiar el plazo de 30 a 10? Porque el plazo no es para el apagado bueno, es para el **malo**. Si un día el `revisor` se traba y no atiende SIGTERM, el clúster lo mata a los 10 segundos y no a los 30. Durante ese tiempo el Pod ocupa su lugar: un *rollout* de tres réplicas que se apagan mal podría tardar minutos de más.

El número tampoco es al azar: el `revisor` se da a sí mismo 5 segundos para terminar las peticiones en curso, y el plazo del clúster tiene que ser **mayor** que el de la aplicación, o el SIGKILL la interrumpe a media despedida. 10 es el doble de 5. Cuando la Lección 9 agregue `preStop`, que también corre dentro de este plazo, el número sube a 15.

El Ejercicio 3 te enseña lo que pasa con un proceso que **no** atiende SIGTERM: el Pod `depurar`.

## El error que vas a ver

Esta lección tiene dos errores a propósito, uno por cada número de `resources`: el techo de memoria y el piso de CPU.

### OOMKilled: pasarse del techo de memoria

Como viste en 5.6.5, el `revisor` usa menos de 2 MB; con él no se puede ver un `OOMKilled`. Se usa un Pod suelto, `memoria.yaml`, que es un **programa** que falla a propósito: intenta guardar 40 MB en una variable de *shell* con un techo de 16 MiB.

```yaml
# memoria.yaml — Lección 5: el OOMKilled a propósito.
# El revisor en reposo usa menos de 5 MiB (medido: con un límite de 5Mi corre
# sin problema, y con 4Mi ni siquiera arranca: StartError). Para ver un
# OOMKilled de verdad hace falta un proceso que PIDA memoria: este Pod intenta
# guardar 40 MB en una variable con un límite de 16 MiB.
apiVersion: v1
kind: Pod
metadata:
  name: memoria
  labels:
    app: memoria
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
  - name: memoria
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sh", "-c", "echo 'pidiendo 40 MB'; a=$(head -c 40000000 /dev/zero | tr '\\000' x); echo 'no debería llegar aquí'"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 16Mi}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

Es la imagen de `curl` de `depurar`, con el mismo `securityContext`, y otro programa: `head -c 40000000 /dev/zero` produce 40 millones de bytes en cero, `tr` los convierte en letras `x`, y `a=$(…)` obliga al *shell* a guardarlos todos en memoria. `restartPolicy: Never` hace que, al morir, se quede muerto para poder mirarlo.

```text
$ kubectl apply -f memoria.yaml
pod/memoria created

$ kubectl get pod memoria
NAME      READY   STATUS      RESTARTS   AGE
memoria   0/1     OOMKilled   0          20s
```

`STATUS OOMKilled`: muerto por falta de memoria (*Out Of Memory*). Se lee en orden, del síntoma a la causa.

**Primero, la razón y el código:**

```text
$ kubectl get pod memoria -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
OOMKilled 137
```

El código de salida `137` es una convención de Unix: 128 más el número de la señal que mató al proceso. 137 − 128 = 9, y la señal 9 es SIGKILL. Nadie le pidió al programa que se fuera; el núcleo lo terminó. Pero ojo: un 137 dice «lo mataron con SIGKILL», no quién ni por qué. Puede ser el núcleo por memoria, como aquí, o el `kubelet` porque venció el plazo de apagado, que es lo que provoca el Ejercicio 3. Lo que separa los dos casos es la razón: `OOMKilled` en uno, otra cosa en el otro. Mira siempre la razón junto al código.

**Segundo, hasta dónde llegó:**

```text
$ kubectl logs memoria
pidiendo 40 MB
```

Escribió su primera línea y nunca la segunda, `no debería llegar aquí`. Murió a media asignación.

**Tercero, el techo que lo explica:**

```text
$ kubectl describe pod memoria | grep -E '^QoS Class:|Reason:|Exit Code:|Limits:|memory:'
      Reason:       OOMKilled
      Exit Code:    137
    Limits:
      memory:  16Mi
      memory:     16Mi
QoS Class:                    Burstable
```

`Limits: memory: 16Mi` (el segundo `memory: 16Mi` es el del bloque `Requests`, que el `grep` también atrapa). Pidió 40 MB contra un techo de 16 MiB: el núcleo hizo exactamente lo que dice 5.6.3. La [guía de asignar memoria](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) provoca el mismo error con otro programa y, en su sección «Exceed a Container's memory limit», lo resume así: un contenedor puede pasar de su `request` si el nodo tiene memoria, pero no de su `limit`.

**Cómo se corrige.** No con un techo más alto «a ver si así». La documentación de gestión de recursos, en su sección de solución de problemas, dice el orden: ante un `OOMKilled`, el siguiente paso es revisar el código en busca de una fuga de memoria; si el programa se comporta como esperas, entonces sí, sube el techo (y quizá el piso). Aquí el programa hace justo lo que debe hacer, que es fallar; se borra:

```text
$ kubectl delete pod memoria
pod "memoria" deleted from default namespace
```

Si fuera un contenedor de un Deployment, el `kubelet` lo reiniciaría una y otra vez, con esperas crecientes entre intentos: la documentación del ciclo de vida da la serie, «10 s, 20 s, 40 s, …», con un tope de 5 minutos. Esa espera es lo que `kubectl get pods` muestra como `CrashLoopBackOff`. Si ves un `CrashLoopBackOff`, mira la columna `RESTARTS` y la razón de la última terminación antes de tocar nada: puede ser un `OOMKilled`, puede ser un programa que sale con error, puede ser una sonda de vida mal escrita. Son tres arreglos distintos.

### Pending: pedir un piso que no cabe

El segundo error va al otro número: un `request` de CPU que ningún nodo puede apartar. Se provoca con un parche directo al Deployment, para que la corrección sea volver a aplicar el archivo.

Antes de un cambio así, la comprobación de contexto de 5.1.2:

```bash
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
```

```text
$ kubectl patch deployment revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"50"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"50"}]'
deployment.apps/revisor patched
```

`kubectl patch --type=json` cambia campos sueltos de un objeto vivo: aquí, el `request` y el `limit` de CPU del primer contenedor pasan a `50`. **Cincuenta CPU**, no cincuenta milicpu: falta la `m`. Es un error de dedo fácil de cometer, y el clúster lo acepta sin quejarse: `50` es una cantidad válida.

**Primero, el síntoma:**

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-g9lhl   1/1     Running   0          2m3s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          2m1s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          2m4s
revisor-5b8f867ccf-9x42x   0/1     Pending   0          10s

$ kubectl rollout status deployment/revisor --timeout=15s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]
```

Cuatro Pods: un ReplicaSet nuevo (`revisor-5b8f867ccf`) con una réplica en `Pending`, y las tres viejas intactas. `Pending` quiere decir que el Pod existe en el `kube-apiserver` pero nadie le ha dado nodo. Y el *rollout* se quedó atorado en «1 de 3»: `rollout status` se rindió a los 15 segundos que le diste.

**Segundo, la causa, en los eventos del Pod:**

```text
$ kubectl describe pod revisor-5b8f867ccf-9x42x | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  25s   default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

(`sed -n '/^Events:/,$p'` imprime desde el renglón `Events:` hasta el final.) Quien habla es el planificador (`default-scheduler`), y su mensaje se lee nodo por nodo:

- `0/3 nodes are available`: ninguno de los tres nodos sirve.
- `1 node(s) had untolerated taint(s)`: uno tiene una «mancha» (*taint*) que este Pod no tolera. Es el nodo de control, que por omisión no recibe tus Pods; lo viste en la Lección 1 cuando los Pods solo caían en los nodos de trabajo.
- `2 Insufficient cpu`: los otros dos no tienen CPU suficiente. Piden 50; cada uno anuncia 6.
- `preemption: … Preemption is not helpful`: el planificador también consideró sacar Pods de menor prioridad para hacer lugar, y concluyó que no ayudaría. Aunque vaciara un nodo, 50 no caben en 6.

La documentación de gestión de recursos trae este mismo evento como su primer caso de solución de problemas: si el planificador no encuentra un nodo donde quepa el Pod, «el Pod se queda sin asignar hasta que se encuentre un lugar», y se produce un evento cada vez que falla. Las salidas que sugiere son agregar nodos o liberar espacio; la que aplica aquí es la tercera, la obvia: pedir lo correcto.

**Tercero, lo que no se rompió:**

```text
$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

El servicio sigue respondiendo. ¿Por qué el Deployment no retiró ninguna réplica vieja? Por su estrategia de actualización, que la Lección 9 estudia a fondo: la [documentación de Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) dice que, por omisión, `maxUnavailable` es 25 % «redondeando hacia abajo» y `maxSurge` es 25 % «redondeando hacia arriba». Con 3 réplicas: 0.75 baja a **0** réplicas que pueden faltar, y 0.75 sube a **1** que puede sobrar. El Deployment creó una nueva de más y se quedó esperando a que estuviera disponible para retirar una vieja. Nunca lo estuvo. Un *rollout* atorado es incómodo; uno que tumbara las réplicas buenas para reemplazarlas por réplicas que no caben sería un apagón. Esta regla te protege de tu propio error de dedo.

**La corrección** es la de siempre en este curso: el archivo es la verdad, y se vuelve a aplicar.

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hct4cckkgd unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-g9lhl   1/1     Running   0          2m19s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          2m17s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          2m20s
```

Las mismas tres réplicas de antes, con sus mismas edades. La plantilla volvió a ser idéntica a la del ReplicaSet `revisor-578c8dc8d9`, que ya tenía sus tres réplicas, así que no hubo nada que reemplazar: el Deployment dejó en cero al ReplicaSet roto y el Pod `Pending` desapareció. Es el mismo efecto que viste en la Solución 3 de la Lección 2.

**El orden, para cualquier Pod que no está `Running`:**

1. `kubectl get pods`: ¿`Pending`, `OOMKilled`, `CrashLoopBackOff`?
2. Si es `Pending`, los eventos del Pod: ¿qué dice el planificador de cada nodo?
3. Si murió, la razón y el código de su última terminación (`OOMKilled 137`, un `Error` con otro código) y su bitácora (`kubectl logs`, o `--previous` si ya se reinició).
4. Antes de cambiar un número, preguntar si el número está mal o el programa está mal.

## El hábito de seguridad de la lección: todo contenedor con piso y techo

La tabla de hábitos del curso le asigna a esta lección dos cosas: `requests` y `limits` en todo contenedor; las sondas no dependen de servicios ajenos. La segunda la comprobaste en 5.5. La primera se comprueba de un vistazo:

```text
$ kubectl get pods -o custom-columns='POD:.metadata.name,QOS:.status.qosClass,CPU_PIDE:.spec.containers[0].resources.requests.cpu,CPU_TOPE:.spec.containers[0].resources.limits.cpu,MEM_PIDE:.spec.containers[0].resources.requests.memory,MEM_TOPE:.spec.containers[0].resources.limits.memory'
POD                        QOS         CPU_PIDE   CPU_TOPE   MEM_PIDE   MEM_TOPE
depurar                    Burstable   10m        100m       16Mi       32Mi
prueba-b896986b5-kzrmk     Burstable   10m        100m       16Mi       32Mi
revisor-578c8dc8d9-hfjmq   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-jlh4b   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-xhqt8   Burstable   50m        200m       32Mi       64Mi
```

Cinco Pods, cinco filas completas, ninguna `<none>`, ninguno `BestEffort`. Incluido `depurar`, que es «solo para mirar»: la Lección 3 le puso techo desde el principio, y hoy sabes por qué.

¿Por qué es un hábito de **seguridad** y no solo de orden? Porque un contenedor sin techo de memoria es un contenedor que puede tumbar a sus vecinos. La [documentación de `LimitRange`](https://kubernetes.io/docs/concepts/policy/limit-range/) empieza con la frase que lo explica: «por omisión, los contenedores corren con recursos de cómputo sin límite en un clúster de Kubernetes». Un error de programación (una fuga de memoria, un ciclo que no termina) o un ataque (alguien que manda peticiones enormes a propósito) en un contenedor sin techo se convierte en un problema del **nodo entero**: el nodo se queda sin memoria y empieza a sacar Pods, empezando por los `BestEffort`, que pueden ser de otro equipo. Con un techo, el daño se queda dentro del contenedor que lo causó: muere él, con un `OOMKilled` que dice exactamente qué pasó, y nadie más.

Lo mismo con la CPU, con un matiz: un contenedor sin techo de CPU que entra en un ciclo infinito se come toda la CPU libre del nodo y vuelve lentos a sus vecinos. Los que declararon `requests` conservan su parte, y por eso el piso también protege; los que no declararon nada se quedan con lo que sobre. Con techo, el que se ahoga es él.

**Lo que defiende y lo que no.** Los techos limitan el daño **dentro de un nodo**; no impiden que alguien cree cien Pods. Para eso un clúster real usa `ResourceQuota` (un total por espacio de nombres) y `LimitRange` (un máximo y un valor por omisión por contenedor). Este curso no los instala, y los nombra para que sepas que existen. Y las sondas no son una defensa: un atacante que entra al `revisor` no va a romper `/salud`. Lo que sí evitan es la otra mitad del problema, que un error tuyo convierta una falla pequeña en una caída en cadena.

## Lo que se hace mal

**Poner en la sonda de vida algo que depende de otros.** Es la escena del jueves. Una base de datos caída no se arregla reiniciando a sus clientes. La sonda de vida pregunta por el proceso, y nada más.

**Usar la misma paciencia para las tres sondas.** Si la de vida reacciona tan rápido como la de disponibilidad, un tropiezo de diez segundos reinicia en lugar de solo apartar del tráfico. La de vida va más lenta.

**Una sonda de vida sin sonda de arranque en un programa lento para arrancar.** El `kubelet` empieza a preguntar en cuanto el contenedor arranca; si el programa tarda más que `failureThreshold × periodSeconds`, se reinicia antes de terminar de arrancar, y otra vez, y otra. La sonda de arranque existe para eso.

**Una ruta de salud cara.** Si `/salud` consulta la base de datos, arma un reporte o escribe en disco, cada sonda lo hace, en cada réplica, cada pocos segundos. Barata y local.

**Apuntar la sonda a una ruta que cambia de código a propósito.** El `GET /` del servicio de prueba es de esos: 503 en modo `caido` por diseño. El Ejercicio 2 lo mide.

**Contenedores sin `requests` ni `limits`.** Quedan `BestEffort`: el planificador no les aparta nada, nadie les pone techo y son los primeros en salir cuando el nodo aprieta.

**Escribir `memory: 64m` o `cpu: 50`.** La `m` minúscula en memoria son milibytes; un número sin `m` en CPU son núcleos completos. El segundo es el `Pending` de esta lección.

**Subir el techo de memoria cada vez que hay un `OOMKilled`.** Si es una fuga, solo la retrasas. Primero se pregunta si el programa está bien.

**Tomar la capacidad de un nodo de kind como real.** Cada nodo anuncia toda tu máquina. Lo que cabe en kind no te dice lo que cabe en producción.

**Dejar el plazo de apagado por omisión sin pensarlo.** Treinta segundos puede ser mucho para un programa que se apaga en uno, y poco para uno que tiene que terminar un trabajo largo. Se elige, y se elige mayor que el plazo interno del programa.

**Un proceso principal que ignora SIGTERM.** El clúster esperará el plazo completo cada vez que lo apagues. El Ejercicio 3 lo mide.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden y desde el estado en que quedó después de 5.7, con el Pod `depurar` todavía vivo. Antes de cada uno, `kubectl config current-context` debe decir `kind-curso-k8s-l5`. `correr.sh` los corre igual, y su salida está en `correr.salida.txt`. **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — Una sonda de disponibilidad en el servicio de prueba

`fig05_01.prueba-disponibilidad.yaml` es el Deployment de prueba de esta lección con una sola diferencia: agrega una sonda de disponibilidad a `GET /`, cada 5 segundos, con 2 fallas para salir del tráfico.

```yaml
# fig05_01.prueba-disponibilidad.yaml — Ejercicio 1: el servicio de prueba con una
# sonda de DISPONIBILIDAD a GET / (la que responde 503 en modo «caido»).
# Pregunta: al ponerlo en «caido», ¿se reinicia? ¿Sigue recibiendo tráfico?
# ¿Qué dice el reporte del revisor? Se deshace con: kubectl apply -k .
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
      terminationGracePeriodSeconds: 10
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
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
        readinessProbe:
          httpGet: {path: /, port: http}
          periodSeconds: 5
          failureThreshold: 2
        livenessProbe:
          httpGet: {path: /modo, port: http}
          periodSeconds: 10
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Aplícalo, espera a que el Pod nuevo esté `1/1` y ponlo en modo `caido`. Antes de mirar, predice: a los 15 segundos, ¿qué dice la columna `READY`? ¿Y `RESTARTS`? ¿Qué dice el EndpointSlice del Service `prueba`? Pregúntalo con `kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}'`. ¿Qué detalle da el reporte del `revisor`? Y la pregunta difícil: ¿funciona `kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano` para arreglarlo? Si no, ¿cómo lo devuelves a `sano`? Al terminar, vuelve a aplicar `kubectl apply -k .`.

### Ejercicio 2 — Una sonda de vida que pregunta lo que no debe

`fig05_02.prueba-vida-mala.yaml` es el Deployment de prueba de la lección con una sola línea distinta: la sonda de vida pregunta a `GET /` en lugar de `GET /modo`.

```yaml
# fig05_02.prueba-vida-mala.yaml — Ejercicio 2: el servicio de prueba con su sonda
# de VIDA apuntando a GET / en lugar de GET /modo. Es el error de la escena en
# pequeño: la sonda de vida pregunta algo que no dice si el proceso está vivo.
# Pregunta: en modo «caido», ¿cuánto tarda en reiniciarse? Después del reinicio,
# ¿en qué modo está? Se deshace con: kubectl apply -k .
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
      terminationGracePeriodSeconds: 10
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
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
        livenessProbe:
          httpGet: {path: /, port: http}
          periodSeconds: 10
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Aplícalo, espera a que esté `1/1` y ponlo en modo `caido`. Predice, con los números de la sonda: ¿cuántos segundos tarda el primer reinicio, más o menos? ¿Qué eventos deja el Pod (busca las razones `Unhealthy` y `Killing`)? Después del reinicio, ¿qué contesta `GET /modo`? ¿Qué dice el reporte del `revisor`? Y explica por qué esto es peor de lo que parece: ¿qué le pasó a la evidencia? Al terminar, vuelve a aplicar `kubectl apply -k .`.

### Ejercicio 3 — Cuánto tarda en irse el Pod de depuración (proyecto)

En 5.7 el `revisor` se apagó en menos de un segundo. Ahora le toca a `depurar`, el Pod de curl de la Lección 3. Antes de borrarlo, mira dos cosas: su `terminationGracePeriodSeconds` (no lo declara) y qué proceso es el número 1 dentro de su contenedor (`kubectl exec depurar -- ps`). Predice cuánto va a tardar `kubectl delete pod depurar`, mídelo con el reloj y explica el número. Después propón dos formas de que se vaya más rápido, una en el manifiesto y otra en el comando.

### Ejercicio 4 — ¿Cabe una cuarta réplica?

Con los números de esta lección: el `revisor` pide `50m` de CPU y `32Mi` de memoria, y en la corrida de la lección cada nodo de trabajo anunciaba 6 CPU (usa el número de tu `kubectl get nodes` si es otro). En cinco frases como máximo: ¿cuántas réplicas del `revisor` cabrían, en teoría, en un nodo de trabajo, contando solo la CPU? ¿Por qué ese número es engañoso en kind? ¿Qué número miraría el planificador para decidir, el `request` o el `limit`? ¿Y qué clase de QoS tendría el `revisor` si escribieras `requests` y `limits` iguales, `200m` y `64Mi`, y qué ganarías y qué pagarías?

## Soluciones

### Solución 1

Medido en `correr.salida.txt`:

```text
$ kubectl apply -f fig05_01.prueba-disponibilidad.yaml
deployment.apps/prueba configured

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl get pods -l app=prueba
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6fd58ccd6d-z29zj   0/1     Running   0          19s

$ kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}'
10.244.2.10 prueba-6fd58ccd6d-z29zj ready=false serving=false

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $TOKEN" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  no responde: Get "http://prueba:9000/": dial tcp 10.96.222.53:9000: connect: connection refused

$ kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano
command terminated with exit code 7
[código de salida: 7]

$ kubectl exec depurar -- curl -s -X POST http://10.244.2.10:9000/modo/sano
modo: sano

$ kubectl get pods -l app=prueba
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6fd58ccd6d-z29zj   1/1     Running   0          23s
```

**`READY 0/1` con `RESTARTS 0`.** La sonda de disponibilidad falló dos veces seguidas (503 en `/`) y el `kubelet` marcó el Pod como no listo, sin reiniciarlo: es exactamente la diferencia de 5.3.4. El EndpointSlice lo confirma: la dirección sigue en la lista, pero con `ready=false` y `serving=false`, así que nadie le manda tráfico.

**El reporte cambió de detalle.** En 5.5 decía `FALLA codigo 503`: el servicio contestaba, mal. Ahora dice `connection refused`: con su única réplica fuera de la lista, el Service `prueba` no tiene a quién mandar la conexión y la rechaza al instante, el mismo código 7 de la Lección 3. El `revisor` sigue diciendo `FALLA`, pero perdió información: ya no sabes **qué** respondió el servicio, solo que no hay nadie.

**Y te quedaste sin puerta para arreglarlo.** El `POST /modo/sano` por el nombre `prueba` también pasa por el Service, y también se rechaza (código 7). El Pod está vivo y escuchando; lo que ya no existe es el camino. La salida es hablarle a la IP del Pod directamente, que no pasa por el Service: `10.244.2.10`, tomada del mismo EndpointSlice o de `kubectl get pods -o wide`. Contestó `modo: sano`, la sonda volvió a pasar y el Pod regresó a `1/1` en unos segundos. Es la Lección 3 al revés: allá aprendiste a **no** usar IPs de Pods; aquí la usas a propósito, una vez, para depurar.

La lección general: una sonda de disponibilidad saca al Pod de **todo** el tráfico del Service, incluido el tuyo de administración. Para un servicio como este, cuyo trabajo es fallar de forma visible, es la decisión equivocada. Por eso el manifiesto de la lección no la lleva.

### Solución 2

Medido en `correr.salida.txt`:

```text
$ kubectl apply -f fig05_02.prueba-vida-mala.yaml
deployment.apps/prueba configured

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido
(el primer reinicio llegó 27 s después de ponerlo en «caido»)

$ kubectl get pods -l app=prueba
NAME                      READY   STATUS    RESTARTS     AGE
prueba-7dd568849d-hllzl   1/1     Running   1 (4s ago)   34s

$ kubectl get events --field-selector involvedObject.name=prueba-7dd568849d-hllzl -o custom-columns=RAZON:.reason,MENSAJE:.message | grep -E 'RAZON|Unhealthy|Killing'
RAZON       MENSAJE
Unhealthy   Liveness probe failed: HTTP probe failed with statuscode: 503
Killing     Container prueba failed liveness probe, will be restarted

$ kubectl exec depurar -- curl -s http://prueba:9000/modo
modo: sano

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $TOKEN" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

**27 segundos, y el contenedor se reinició.** La sonda pregunta cada 10 segundos y tolera 3 fallas: tres preguntas fallidas caben en unos 20 a 30 segundos, según en qué punto del ciclo estaba la sonda cuando cambiaste el modo. Los eventos cuentan la historia en dos renglones: `Unhealthy … statuscode: 503` (la sonda falló) y `Killing … failed liveness probe, will be restarted` (el `kubelet` lo mató por eso). `RESTARTS 1 (4s ago)`: el reinicio fue hace 4 segundos. (Un evento `Unhealthy` se repite por cada falla, pero el clúster agrupa los iguales en un solo renglón con un contador.)

**Y aquí está lo grave: después del reinicio, `modo: sano` y el reporte dice `OK`.** El servicio de prueba guarda su modo en memoria; al reiniciarse, arranca en el modo por omisión. El clúster «arregló» el síntoma borrando la evidencia. Si esto fuera un servicio de verdad con un problema de verdad, el `revisor` habría reportado la falla 27 segundos y luego todo verde, y alguien concluiría que «se compuso solo». Y la siguiente vez que falle, lo mismo. Con la sonda bien escrita (`/modo`), en 5.5 el servicio se quedó en `caido` todo lo que quisiste y el reporte dijo la verdad todo el tiempo. Esto es la advertencia de la documentación en pequeño: una sonda de vida que no detecta una falla irrecuperable sino otra cosa termina haciendo daño.

Después de los dos ejercicios, el guion vuelve a aplicar `kubectl apply -k .` y comprueba que el clúster es otra vez exactamente lo que dicen los archivos. Es el `kubectl diff` de 5.4.1, ahora al revés: sin diferencias, sale con 0 y se imprime el mensaje.

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-b896986b5-57pgj     1/1     Running   0          5s
revisor-578c8dc8d9-hfjmq   1/1     Running   0          70s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          3m30s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          3m33s
```

Haz lo mismo en tu clúster antes del Ejercicio 3: si el `diff` imprime algo, algún ejercicio quedó sin deshacer.

### Solución 3

Medido en `correr.salida.txt`:

```text
$ kubectl get pod depurar -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
30

$ kubectl exec depurar -- ps
PID   USER     TIME  COMMAND
    1 curl_use  0:00 sleep 3600
  109 curl_use  0:00 ps

$ kubectl delete pod depurar
pod "depurar" deleted from default namespace
(el borrado tardó 32 s)
```

**32 segundos: el plazo completo, más lo que tardan el SIGKILL y la limpieza.** El manifiesto no declara plazo, así que vale el de omisión, 30. El proceso número 1 del contenedor es `sleep 3600`. El `kubelet` le mandó SIGTERM, y `sleep` no hizo nada: en Linux, el proceso con PID 1 de un espacio de procesos ignora las señales para las que no instaló un manejador, y `sleep` no instala ninguno. Así que el clúster esperó los 30 segundos y mandó SIGKILL, que no se puede ignorar. Mientras tanto, `kubectl delete` esperaba. El `revisor`, en cambio, sí instala su manejador de SIGTERM (por eso escribe `recibí terminated`), y se fue en 1 segundo.

Dos formas de que se vaya más rápido:

- **En el manifiesto:** `terminationGracePeriodSeconds: 1` en el Pod `depurar`. No tiene nada que terminar con orden; un plazo corto no le quita nada. (Otra opción es que su proceso principal atienda SIGTERM, por ejemplo con un `sh` que instale un `trap`; es más trabajo para un Pod de usar y tirar.)
- **En el comando:** `kubectl delete pod depurar --wait=false`, que pide el borrado y regresa de inmediato sin esperar. El Pod tarda lo mismo en irse; solo tú dejas de esperarlo. Es lo que hace el guion de la Lección 3 al final. Existe también `--grace-period` en `kubectl delete` para cambiar el plazo de ese borrado. Su ayuda (`kubectl delete --help`) dice que `--grace-period=1` es el apagado inmediato, y que el 0 solo se acepta junto con `--force`, que además borra el Pod de la API sin esperar a que el nodo confirme que el contenedor terminó. Úsalo con cuidado.

### Solución 4

Una respuesta posible: «Contando solo la CPU, en un nodo que anuncia 6 CPU (los de esta corrida) caben 6,000 m / 50 m = 120 réplicas, menos lo que ya piden los Pods del sistema (en esta corrida, el nodo ya tenía `150m` apartados contando una réplica). Ese número es engañoso porque en kind los tres nodos anuncian la misma máquina completa: el planificador cree que hay 18 CPU donde hay 6, y las réplicas de los tres nodos se pelearían por los mismos núcleos. El planificador decide con el `request`, nunca con el `limit`: los límites pueden sumar más del 100 % de un nodo. Con `requests` y `limits` iguales en `200m` y `64Mi`, el Pod sería `Guaranteed`: el último en ser desalojado cuando el nodo aprieta, y con su CPU siempre apartada. Lo pagarías reservando cuatro veces más CPU y el doble de memoria de lo que el `revisor` necesita en su día normal, así que cabrían cuatro veces menos réplicas por nodo.»

## Borrar el clúster

Cuando termines los ejercicios, borra el clúster de la lección. No dejes nada vivo en la máquina:

```text
$ kind delete cluster --name curso-k8s-l5
Deleting cluster "curso-k8s-l5" ...
Deleted nodes: ["curso-k8s-l5-worker" "curso-k8s-l5-control-plane" "curso-k8s-l5-worker2"]
(borrar tardó 1 s)

$ kind get clusters | grep -c curso-k8s-l5
0
```

(La línea entre paréntesis la escribe el guion, que mide el borrado.) El `--name` es obligatorio: sin él, kind borraría el clúster llamado `kind`, que puede ser de otra persona o de otro proyecto.

Quedan en tu máquina la carpeta temporal del `kubeconfig` y los dos `token.txt`. Se borran así, desde `programas/05-salud-recursos-apagado`:

```bash
# Los dos tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 5.1.1.
case "$L5_TMP" in
  /tmp/curso-k8s-l5.?*) rm -rf -- "$L5_TMP" ;;
  *) echo "No borro «$L5_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L5_TMP
```

El `case` solo deja pasar una ruta que empiece con `/tmp/curso-k8s-l5.` y tenga algo después, la forma exacta de la que creaste en 5.1.1. Si `L5_TMP` está vacía (por ejemplo, porque estás en otra terminal, donde nunca la definiste) o vale otra cosa, no borra nada y te dice por qué. Es la misma protección que usa `correr.sh` al limpiar: un `rm -rf` que se puede copiar y pegar tiene que protegerse solo. Si la segunda terminal de 5.7 sigue abierta, ciérrala: ahí solo hiciste el `export`. El clúster de la siguiente lección se crea de cero, igual que este.

## Cómo sé que lo logré

- [ ] Ante un Pod que se reinicia solo, distingues con los eventos si fue una sonda de vida (`Killing … failed liveness probe`), un `OOMKilled` o el programa que salió con error.
- [ ] Escribes las tres sondas del `revisor` y dices, para cada una, qué pregunta, qué pasa si falla y cuántos segundos tarda en reaccionar con sus números.
- [ ] Explicas, con la salida de 5.5 y la del Ejercicio 2, por qué la sonda de vida no debe depender de nadie más ni de una ruta que falla a propósito.
- [ ] Lees una línea `Liveness:` de `describe` y nombras cada número.
- [ ] Escribes `requests` y `limits` en milicores y mebibytes sin confundir `m` con `M`, y dices quién usa cada uno.
- [ ] Ante un `Pending`, lees el `FailedScheduling` nodo por nodo; ante un `OOMKilled`, encuentras el `137` y el techo que lo explica.
- [ ] Explicas qué hace el clúster entre `kubectl delete pod` y que el Pod desaparezca, y por qué `depurar` tarda más de 30 segundos y el `revisor` menos de uno.
- [ ] Corres `programas/05-salud-recursos-apagado/correr.sh > /tmp/mi-corrida-l5.txt 2>&1` y comparas `/tmp/mi-corrida-l5.txt` contra `programas/05-salud-recursos-apagado/correr.salida.txt` (no redirijas a ese archivo: es la referencia) en lo que no cambia entre corridas: tres nodos `Ready` en `v1.37.0`; seis renglones `not yet present on node … loading...`; `33` bytes de token y `-rw-------` en los dos `token.txt`; `QoS Class: BestEffort` y `30` antes de la lección; `mismo token`; el `kubectl diff` con las sondas, los recursos y los dos `terminationGracePeriodSeconds: 10`, y su código 1; solo los Deployments `configured`; las líneas `Limits`, `Requests`, `Liveness`, `Readiness` y `Startup` con sus números, `QoS Class: Burstable` y `10`; en la bitácora, una línea de `GET /salud` cada 5 segundos y otra cada 10; `RESTARTS 0` en los cuatro Pods con prueba en `caido` y `FALLA … codigo 503`; los tres nodos con la misma CPU y memoria; `OOMKilled`, `OOMKilled 137` y `pidiendo 40 MB`; el `Pending`, `timed out waiting for the condition` y `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu`; `revisor: recibí terminated, apagando` y `revisor: apagado limpio`; las cinco filas con piso y techo, todas `Burstable`; `0/1` con `ready=false`, `connection refused` y código 7 en el Ejercicio 1; `RESTARTS 1`, los eventos `Unhealthy … 503` y `Killing … will be restarted` y `modo: sano` en el Ejercicio 2; `sin diferencias con los archivos`; `30`, `sleep 3600` como PID 1 y un borrado de 30 s o poco más en el Ejercicio 3. Las IP, los sufijos de los nombres, las edades, la hora de la bitácora, la CPU y la memoria de los nodos y sus porcentajes, la memoria exacta del `revisor` en `crictl stats`, en qué nodo cae cada Pod, el orden de los renglones de `kind load` y los segundos exactos del primer reinicio en el Ejercicio 2 cambian en cada corrida: se observan, no se comparan.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l5`.

## Resumen

Responde sin mirar la lección:

1. ¿Qué sabía el clúster del `revisor` antes de esta lección, y por qué su Pod estaba `1/1` a los 4 segundos?
2. ¿Qué pregunta cada una de las tres sondas y qué hace el clúster cuando la respuesta es «no»?
3. ¿Quién ejecuta las sondas, y qué códigos HTTP cuentan como éxito?
4. Con `periodSeconds: 10` y `failureThreshold: 3`, ¿cuánto tarda en reaccionar una sonda de vida?
5. ¿Por qué `/salud` no consulta al servicio de prueba, y por qué la sonda del servicio de prueba pregunta a `/modo` y no a `/`?
6. ¿Quién usa los `requests` y quién los `limits`? ¿Qué le pasa a un contenedor que se pasa de su techo de CPU, y qué le pasa si se pasa del de memoria?
7. ¿Qué es `100m` de CPU? ¿Y `100m` de memoria?
8. ¿Qué tres clases de QoS hay y en qué orden se desaloja a los Pods cuando un nodo se queda sin recursos?
9. ¿Qué significa el código 137?
10. ¿Qué pasa, en orden, cuando borras un Pod, y para qué sirve `terminationGracePeriodSeconds`?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «Liveness, Readiness, and Startup Probes»](https://kubernetes.io/docs/concepts/workloads/pods/probes/): qué es una sonda y que la ejecuta el `kubelet`; qué pregunta cada una y qué pasa al fallar; que la de arranque detiene a las otras dos hasta tener éxito; que la de disponibilidad saca la IP del Pod de los EndpointSlices y corre todo el ciclo de vida; la advertencia sobre las fallas en cascada; las dependencias de *backend* en la de disponibilidad y no en la de vida; el patrón de un `failureThreshold` mayor en la de vida; los campos de una sonda y sus valores por omisión.
- [Kubernetes, «Configure Liveness, Readiness and Startup Probes»](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/): los códigos de 200 a 399 como éxito de una sonda HTTP; la sonda de arranque con `failureThreshold * periodSeconds` para cubrir el peor arranque, y el ejemplo de 30 × 10 s.
- [Kubernetes, «Resource Management for Pods and Containers»](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/): el `request` para el planificador y el `limit` para el `kubelet`; el techo de CPU por estrangulamiento y el de memoria por muerte OOM; las unidades de CPU (`100m`, «cien milicpu») y de memoria (`Mi`, la trampa de la `m` minúscula); que el planificador suma los `requests` y se niega aunque el uso real sea bajo; el evento `FailedScheduling` y el `OOMKilled` como casos de solución de problemas.
- [Kubernetes, «Pod Quality of Service Classes»](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/): los criterios de `Guaranteed`, `Burstable` y `BestEffort`, y el orden de desalojo.
- [Kubernetes, «Pod Lifecycle»](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): la terminación de un Pod con TERM, el plazo de 30 segundos por omisión y el KILL al vencer; los *endpoints* que se apagan, marcados `terminating` y con `ready` en `false`; la espera creciente entre reinicios (10 s, 20 s, 40 s… hasta 5 minutos) y `CrashLoopBackOff`.
- [Kubernetes, «Assign Memory Resources to Containers and Pods»](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/): un contenedor que se pasa de su techo de memoria y termina `OOMKilled`.
- [Kubernetes, «Deployments»](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxUnavailable` y `maxSurge` de 25 % por omisión, redondeados hacia abajo y hacia arriba.
- [Kubernetes, «Limit Ranges»](https://kubernetes.io/docs/concepts/policy/limit-range/): que, por omisión, los contenedores corren sin límite de recursos.
- [kind, «Quick Start»](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind create cluster` y `kind load docker-image` con `--name`, y `crictl` dentro de un nodo.

---

**Siguiente:** [Lección 6 — Entrar al clúster](06-entrar-al-cluster.md)
