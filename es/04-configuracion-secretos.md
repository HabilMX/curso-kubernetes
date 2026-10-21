# Lección 4 — Configuración y secretos

Miércoles, 6:40 de la tarde. Mañana a las 8 empieza la revisión de seguridad del proyecto y te toca preparar el repositorio. Abres el historial y lo ves: hace tres semanas alguien agregó el token del `revisor` al manifiesto del Deployment, en una línea `REVISOR_TOKEN`, «solo para probar». Ya no está en la versión de hoy, pero sigue en el historial de Git, donde lo puede leer cualquiera que haya clonado el repositorio. Mientras lo piensas llega otro mensaje: el equipo de pagos quiere que el `revisor` vigile también su servicio, y para agregarlo a la lista hay que editar el mismo Deployment: no hace falta reconstruir la imagen, pero sí tocar otra vez el archivo donde vivió el token. Alguien propone resolver lo primero con un Secret «que ya viene en base64, así que está protegido». Son las 6:55 y tienes dos problemas que parecen uno.

No son uno. El primero es **dónde vive un dato que no debe verse**; el segundo es **cómo cambias la configuración de un servicio sin tocar su receta**. Kubernetes tiene un objeto para cada uno, y esta lección te enseña a usarlos sin creerles más de lo que prometen: un `ConfigMap` no es secreto, un `Secret` no está cifrado, y ninguno de los dos hace que tu programa se entere solo de que algo cambió.

**Tiempo:** 2 × 45 min

**Qué construyes:** el `revisor` configurado sin reconstruir la imagen: la lista de servicios sale del Deployment y vive en un `ConfigMap`; el token de acceso vive en un `Secret` que se monta como archivo y no se puede editar; y un cambio en la lista dispara solo un *rollout*

**Qué aprendes:** `ConfigMap` como variables de entorno (el `revisor` solo lee variables) y por qué cambiarlo a mano no reinicia a nadie; `Secret` como archivo, quién puede leerlo y por qué base64 no es cifrado; `fsGroup` y el dueño de los archivos montados; Kustomize con `configMapGenerator` y `secretGenerator`, y el *hash* que dispara el *rollout*; los Secrets inmutables

**De dónde vienes.** De la [Lección 3](03-services-dns.md): el `revisor` tiene tres réplicas detrás de un Service llamado `revisor`, el servicio de prueba que falla a propósito vive detrás de otro llamado `prueba`, y sabes usar un Pod de depuración con `curl` (`depurar`) para hablarle al `revisor` desde dentro del clúster. De la [Lección 2](02-pods-deployments.md) traes la cadena Deployment → ReplicaSet → Pod y la regla que importa aquí más que nunca: un *rollout* ocurre **si y solo si cambia la plantilla del Pod**. Y del [curso de Docker](https://www.habil.mx/es/cursos/docker/) traes una costumbre: el token del `revisor` se le da por archivo (`REVISOR_TOKEN_ARCHIVO`), nunca por variable, porque una variable se lee con `docker inspect`.

**Qué no hace esta lección.** No cifra los Secrets dentro del clúster: eso se configura en el `kube-apiserver` de un clúster real y la [Lección 10](10-proyecto-final.md) lo pone en la lista de lo que le falta a esto para ser producción. Tampoco decide **quién** puede leer los Secrets con permisos finos: aquí vas a ver que tú puedes, y la [Lección 7](07-aislar-permisos-red.md) da a cada programa su propia cuenta y permisos mínimos. Y el clúster todavía no sabe distinguir un `revisor` que arrancó de uno que puede atender; en esta lección vas a ver qué cuesta eso, y las sondas llegan en la [Lección 5](05-salud-recursos-apagado.md).

**Sobre las corridas.** Todas las salidas de esta lección se obtuvieron el 21 de octubre de 2026 con `kind` v0.33.0, `kubectl` v1.37.1 (que trae dentro Kustomize v5.8.1) y la imagen de nodo `kindest/node:v1.37.0` fijada por su huella, en el clúster de tres nodos de la Lección 1, al que aquí se le llama `curso-k8s-l4`. La máquina fue una Mac con procesador ARM y Docker Engine 29.2.1 dentro de una máquina virtual Linux (Colima), **no** Linux Mint, que es el sistema de referencia del curso. Lo que cambia en tu Mint: la arquitectura, los sufijos al azar de Pods y ReplicaSets, las IP, las edades, el nodo donde cae cada réplica, el tamaño que reporta `tmpfs` y, sobre todo, **el token y el nombre del Secret**, que son nuevos en cada corrida (el nombre del ConfigMap, en cambio, debe salirte idéntico: `revisor-config-t6cm6872fk`). Un detalle más: `wc -c` de macOS rellena el número con espacios a la izquierda (`      33`) y el de Linux no (`33`). El recorrido completo está en [`programas/04-configuracion-secretos/`](../programas/04-configuracion-secretos): `correr.sh` crea el clúster, le carga las dos imágenes del curso, lo deja como terminó la Lección 3, recorre la lección en orden, corre los Ejercicios 1 a 3 (el 3, en un espacio de nombres desechable que borra al terminar) y borra el clúster. Tardó 2 minutos y 43 segundos; crear el clúster y esperar a que estuviera listo fueron 42 segundos, y borrarlo, 4. Su salida es `correr.salida.txt`. El guion genera su propio token, lo borra al terminar y deja `kustomization.yaml` como estaba, aunque se detenga a la mitad; y si `kind create cluster` falla, se detiene ahí con código 1, en vez de seguir sobre un clúster que no existe.

## Al terminar vas a poder

- Sacar una variable de entorno de un Deployment a un `ConfigMap` y leer en `kubectl describe pod` de dónde sale cada variable.
- Demostrar con el reporte del `revisor` que cambiar un `ConfigMap` a mano no cambia las variables de los Pods que ya corren, y explicar por qué.
- Escribir una `kustomization.yaml` con `configMapGenerator` y `secretGenerator`, ver con `kubectl kustomize` lo que va a generar y aplicarla con `kubectl apply -k`.
- Predecir el nombre que tendrá un ConfigMap generado después de un cambio, y comprobar con `kubectl diff -k` que ese cambio dispara un *rollout*.
- Montar un `Secret` como archivo con `defaultMode: 0440` y `fsGroup`, y localizar ese archivo en el nodo, en un `tmpfs`.
- Decodificar un Secret con `base64 -d` para demostrar que base64 no es cifrado, y cambiar el contenido de un Secret inmutable de la única forma posible: con otro Secret.
- Reconocer el `permission denied` de un Secret ilegible y el `couldn't find key` de una llave mal escrita, y decir cuál de los dos tumba el servicio y por qué.

## El porqué antes del cómo

Hasta la Lección 3, la lista de servicios que revisa el `revisor` estaba escrita dentro del Deployment, en una línea `value: "prueba http://prueba:9000/ 2s"`. Funciona, pero junta dos cosas que cambian a ritmos distintos. La **receta** del servicio (qué imagen, cuántas réplicas, qué seguridad) cambia poco y la cuida quien opera el clúster. La **configuración** (qué servicios revisar, con qué tiempo límite) cambia seguido y a veces la pide otro equipo. Si viven en el mismo archivo, cada cambio de la lista es un cambio de la receta, con su revisión y su riesgo. La [documentación de ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) lo pone así: un ConfigMap te permite «separar la configuración específica del ambiente de tus imágenes de contenedor, para que tus aplicaciones sean fácilmente portables».

El token es otro asunto. No es configuración que alguien quiera leer: es una llave. Escrito en el Deployment, viaja con el manifiesto a Git, a cada copia del repositorio y a cada pantalla donde alguien haga `kubectl get deployment -o yaml`. Kubernetes tiene un objeto aparte para esto, el **Secret**, y esta lección te muestra con salidas reales qué protege y qué no. Porque el Secret tiene una fama que no se ganó: mucha gente cree que, como sus datos aparecen en base64, están cifrados. No lo están, y lo vas a comprobar con un solo comando.

Y hay una tercera pregunta, la más sutil: **¿cuándo se entera el programa de que su configuración cambió?** El `revisor` lee sus variables de entorno una sola vez, al arrancar. Kubernetes no reinicia a nadie porque cambió un ConfigMap. Si no ves eso, vas a cambiar la configuración, vas a ver el objeto cambiado en el clúster y vas a creer que ya quedó, cuando los Pods siguen trabajando con la lista vieja. La solución de esta lección es una herramienta que ya traes dentro de `kubectl`, Kustomize, y un truco tan simple que parece trampa: cambiarle el **nombre** al ConfigMap cada vez que cambia su contenido.

La lección tiene siete partes de conceptos y después las secciones de siempre:

1. **La configuración escrita en el Deployment** (4.1): el punto de partida.
2. **Un ConfigMap escrito a mano** (4.2) y cómo se conecta a una variable.
3. **Cambiar un ConfigMap no reinicia a nadie** (4.3), medido.
4. **El token como Secret, y por qué como archivo** (4.4).
5. **Kustomize: los generadores y el *hash*** (4.5).
6. **base64 no es cifrado** (4.6).
7. **Cambiar la lista dispara el *rollout*** (4.7).

Este es el destino. Al final de 4.5, el `revisor` se configura desde fuera, y cada objeto lleva en su nombre la huella de su contenido:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

## Los conceptos

### 4.0 El clúster, como terminó la Lección 3

Esta lección usa su propio clúster, `curso-k8s-l4`, con la configuración de tres nodos de la Lección 1, recién creado. Créalo así, desde la raíz del repositorio del curso, con el mismo cuidado que aprendiste en la Lección 1, y cárgale las dos imágenes del curso de Docker:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l4.XXXX)/kubeconfig"
# curso-k8s-l4 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l4 --config programas/04-configuracion-secretos/kind-curso.yaml
# Debe decir kind-curso-k8s-l4. Si dice otra cosa, no sigas.
kubectl config current-context
kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l4
# El resto de la lección se trabaja desde la carpeta de sus programas.
cd programas/04-configuracion-secretos
```

El `export` solo vale en esa terminal. Si abres otra, repite el `export` con la misma ruta, o `kubectl` le hablará a otro clúster. Y si `kind create cluster` falla, no sigas: lee su mensaje, porque todo lo que venga después supondría un clúster que no existe.

Luego se le aplica lo que dejó la Lección 3. Los archivos están en la carpeta de programas de esta lección: el Deployment de partida, en `punto-de-partida/revisor-deployment.yaml`, y los dos Services, el Deployment de `prueba` y el Pod `depurar`, sin cambios. Las salidas de esta sección son de la corrida de `correr.sh`, que hace exactamente esto:

```text
$ kubectl config current-context
kind-curso-k8s-l4

$ kubectl apply -f punto-de-partida/revisor-deployment.yaml -f revisor-service.yaml -f prueba-deployment.yaml -f prueba-service.yaml -f depurar.yaml
deployment.apps/revisor created
service/revisor created
deployment.apps/prueba created
service/prueba created
pod/depurar created

$ kubectl get deployment,service
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           9s
deployment.apps/revisor   3/3     3            3           9s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/kubernetes   ClusterIP   10.96.0.1      <none>        443/TCP    46s
service/prueba       ClusterIP   10.96.199.61   <none>        9000/TCP   9s
service/revisor      ClusterIP   10.96.4.106    <none>        80/TCP     9s
```

Como siempre, el primer comando pregunta a qué clúster le hablas. En esta lección vas a crear y borrar Secrets, y `kind-curso-k8s-l4` es la única respuesta que te deja seguir. **Repite `kubectl config current-context` antes de cada comando que cambia algo** (`apply`, `patch`, `delete`, `rollout restart`) y antes de cada ejercicio: el guion lo hace antes de cada `kubectl`, y tú también. Para no llenar la lección de renglones iguales, solo se muestra en los puntos donde más importa.

### 4.1 La configuración escrita dentro del Deployment

Así está hoy la configuración del `revisor`:

```text
$ kubectl get deployment revisor -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
[{"name":"REVISOR_SERVICIOS","value":"prueba http://prueba:9000/ 2s"}]

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

Una variable, con el valor escrito ahí mismo (`value`). Y `/api/estados` responde a cualquiera que lo pida: el `revisor` todavía no tiene token, así que no lo exige. Esa tabla es tu **instrumento de medición** en toda la lección. El `revisor` no tiene *shell*, así que no puedes entrar a ver sus variables con `env`; pero su reporte lista exactamente los servicios que leyó de `REVISOR_SERVICIOS` al arrancar. Si la tabla dice `prueba` y nada más, el `revisor` está trabajando con esa lista, diga lo que diga cualquier objeto del clúster.

Una pregunta para guardar: ¿qué tendrías que hacer para agregar un servicio a la lista? Editar este Deployment. Eso cambia su plantilla, así que dispara un *rollout* (la regla de la Lección 2). Funciona. El problema no es técnico, es de quién toca qué.

### 4.2 Un ConfigMap escrito a mano

#### 4.2.1 El objeto

Un **ConfigMap** es, según su documentación, «un objeto de la API que se usa para guardar datos no confidenciales en pares de llave y valor». Las dos palabras que importan son **no confidenciales**: la misma página trae un aviso en recuadro, «ConfigMap no ofrece secreto ni cifrado», y te manda a usar un Secret si el dato es confidencial. Y otra advertencia: lo que guardes en un ConfigMap no puede pasar de 1 MiB. Es para configuración, no para archivos grandes.

Este es el primero, escrito a mano. Es un **programa**: `programas/04-configuracion-secretos/fig04_01.configmap.yaml`.

```yaml
# fig04_01.configmap.yaml — Lección 4, sección 4.2: un ConfigMap escrito a mano.
# Guarda la lista de servicios que el revisor revisa, fuera del Deployment. Tiene
# un nombre FIJO (revisor-config): la sección 4.3 muestra por qué eso es un
# problema y la 4.5 lo resuelve con el generador de Kustomize.
apiVersion: v1
kind: ConfigMap
metadata:
  name: revisor-config
  labels:
    app: revisor
data:
  REVISOR_SERVICIOS: "prueba http://prueba:9000/ 2s"
```

Se lee igual que cualquier objeto: `apiVersion: v1` (el grupo central de la API, como los Pods), `kind: ConfigMap`, un nombre y una etiqueta. Lo nuevo es `data`: un mapa de llaves y valores, todos texto. Aquí hay una sola llave, `REVISOR_SERVICIOS`, y se llama igual que la variable a propósito: así nadie tiene que traducir entre dos nombres.

```text
$ kubectl apply -f fig04_01.configmap.yaml
configmap/revisor-config created

$ kubectl get configmap revisor-config -o jsonpath='{.data}{"\n"}'
{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s"}
```

(Antes de ese `apply`, `kubectl config current-context` dijo `kind-curso-k8s-l4`.) Hasta aquí el ConfigMap existe, pero nadie lo usa. Un ConfigMap no hace nada por sí solo: es un dato guardado en el clúster, esperando que un Pod lo pida.

#### 4.2.2 De ConfigMap a variable

La documentación da cuatro formas de usar un ConfigMap desde un Pod: como argumentos del comando del contenedor, como **variables de entorno**, como **archivos** en un volumen de solo lectura, o leyéndolo con código que hable con la API de Kubernetes. El `revisor` decide por ti cuál sirve: solo lee variables de entorno (`REVISOR_SERVICIOS`, `REVISOR_PUERTO`, `REVISOR_REPORTE` y `REVISOR_TOKEN_ARCHIVO`). Un archivo con la lista no le serviría de nada, porque no lo buscaría. Por eso, en este curso, **el ConfigMap va como variable**.

Este Deployment (`fig04_02.revisor-con-configmap.yaml`, otro **programa**) es el de la Lección 3 con una sola diferencia. Donde antes decía `value: "prueba http://prueba:9000/ 2s"`, ahora dice de dónde sacar el valor:

```yaml
        env:
        - name: REVISOR_SERVICIOS
          valueFrom:
            configMapKeyRef:
              name: revisor-config
              key: REVISOR_SERVICIOS
```

Léelo como una frase: la variable `REVISOR_SERVICIOS` toma su valor (`valueFrom`) de la llave `REVISOR_SERVICIOS` del ConfigMap llamado `revisor-config`. El resto del archivo no cambia, y lo puedes comprobar tú con `diff punto-de-partida/revisor-deployment.yaml fig04_02.revisor-con-configmap.yaml`.

Existe otra forma, `envFrom`, que convierte **todas** las llaves de un ConfigMap en variables de una vez. Es cómoda, pero esconde qué variables recibe el contenedor: tendrías que ir a ver el ConfigMap para saberlo. Con un programa que ignora en silencio las variables que no conoce, como el `revisor`, prefiere `configMapKeyRef`: cada variable escrita y con nombre en el Deployment.

```text
$ kubectl apply -f fig04_02.revisor-con-configmap.yaml
deployment.apps/revisor configured

$ kubectl describe pod revisor-66db8c7755-6mwlw | sed -n '/Environment:/,/Mounts:/p'
    Environment:
      REVISOR_SERVICIOS:  <set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>  Optional: false
    Mounts:

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

`configured`: cambió la plantilla, así que hubo *rollout* y hay Pods nuevos. `kubectl describe pod` muestra la variable y, en vez de su valor, **de dónde sale**: «puesta con la llave `REVISOR_SERVICIOS` del ConfigMap `revisor-config`». `Optional: false` quiere decir que, si ese ConfigMap o esa llave no existen, el contenedor no arranca. Lo vas a provocar en el Ejercicio 1. La tabla sigue igual que antes, como debe: misma lista, otro lugar.

### 4.3 Cambiar un ConfigMap no reinicia a nadie

Ahora el pedido de la escena: agregar un servicio. Para no depender de nada fuera del clúster, el «servicio nuevo» es el mismo `prueba` con otro nombre, `lento`, y un tiempo límite más corto, de medio segundo. Lo que importa es que aparezca un renglón nuevo en la tabla.

Antes de cambiar nada, comprueba el contexto (`kubectl config current-context` → `kind-curso-k8s-l4`) y mira los ReplicaSets. El de arriba es el de `fig04_02`; el de abajo, el de la Lección 3, en `0 0 0`:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       3s
revisor-697fb84f97   0         0         0       12s

$ kubectl patch configmap revisor-config -p '{"data":{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms"}}'
configmap/revisor-config patched
(30 s después)
```

`kubectl patch` cambia solo los campos que le das. Aquí le dio a la llave una lista con dos servicios separados por coma. El clúster dice `patched`: el ConfigMap cambió. Treinta segundos después:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       34s
revisor-697fb84f97   0         0         0       43s

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           4ms  200
```

Ni un ReplicaSet nuevo, y la tabla sigue diciendo solo `prueba`. **El ConfigMap cambió y el `revisor` no se enteró.** No es un retraso que se arregle esperando: así va a seguir hasta que el Pod renazca.

La razón tiene dos mitades, y conviene ver las dos.

**La mitad de Kubernetes.** Una variable de entorno se fija cuando el contenedor arranca. Así funcionan las variables en Linux: el proceso recibe su entorno al nacer y nadie se lo cambia después desde fuera. La documentación de ConfigMaps lo dice sin rodeos: «los ConfigMaps consumidos como variables de entorno no se actualizan automáticamente y requieren reiniciar el Pod». Y el Deployment no tiene por qué reiniciar nada: su plantilla dice «toma la variable del ConfigMap `revisor-config`», y eso no cambió. Cambió el contenido del ConfigMap, no la plantilla, así que la regla «si y solo si» de la Lección 2 no se cumple. No hay *rollout*.

**La mitad del `revisor`.** Aunque Kubernetes pudiera cambiarle la variable, no serviría: el `revisor` lee su configuración una sola vez, al arrancar. Su código (`cmd/revisor/config.go`, del curso de Docker) arma la lista en una función que se llama al principio y nunca más.

¿Y si el ConfigMap se montara como archivo? La documentación dice que entonces sí se actualiza solo, «eventualmente», con el retraso de la sincronización del `kubelet`. Pero eso solo ayuda a un programa que vuelva a leer el archivo, y el `revisor` no lo hace. Muchos programas reales tampoco. Por eso la pregunta correcta nunca es «¿cambió el ConfigMap?», sino «¿el programa ya está corriendo con la configuración nueva?». Y esa pregunta se contesta con el programa, no con el ConfigMap: aquí, con la tabla.

La salida a mano es la de la Lección 2:

```text
$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
lento     OK           1ms  200
prueba    OK           2ms  200

$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>
```

Ahora sí: dos servicios. `rollout restart` agregó la anotación `restartedAt` a la plantilla, la plantilla cambió y los Pods nuevos leyeron la lista nueva al nacer. Revisión 3.

Funciona, pero depende de que alguien **se acuerde** de reiniciar. Y fíjate en lo que no queda en ningún lado: la historia del Deployment dice que hubo tres revisiones, pero ninguna dice que la tercera fue por un cambio de lista. Si mañana alguien hace `rollout undo` para volver a la revisión 2, vuelve a la plantilla de la revisión 2, que apunta al mismo ConfigMap `revisor-config`… que ya tiene la lista nueva. No hay forma de volver a la configuración vieja, porque la configuración vieja ya no existe. La sección 4.5 resuelve las dos cosas con una sola idea.

### 4.4 El token: un Secret, y como archivo

#### 4.4.1 Qué es un Secret

Un **Secret**, según su [documentación](https://kubernetes.io/docs/concepts/configuration/secret/), es «un objeto que contiene una pequeña cantidad de datos sensibles, como una contraseña, un token o una llave». Se parece mucho a un ConfigMap: también es un mapa de llaves y valores, también tiene un tope de 1 MiB, y también se usa como variable o como archivo. Las diferencias están en el trato que le da el clúster:

- **Solo viaja a los nodos que lo necesitan.** Un Secret se envía a un nodo solo si un Pod de ese nodo lo pide.
- **En el nodo, vive en memoria.** El `kubelet` guarda la copia en un `tmpfs`, un sistema de archivos en RAM, «para que el dato confidencial no se escriba en almacenamiento durable»; y la borra cuando se va el Pod que la usaba. El `tmpfs` lo vas a ver en 4.5.6.
- **Se puede tratar aparte en los permisos.** Una regla de RBAC (Lección 7) puede dejar leer ConfigMaps y no Secrets.

Y una cosa que **no** hace: cifrar. La misma página abre con un aviso en recuadro que conviene leer completo: «Los Secrets de Kubernetes se guardan, por omisión, sin cifrar en el almacén de datos del servidor de la API (etcd). Cualquiera con acceso a la API puede leer o modificar un Secret, y también cualquiera con acceso a etcd. Además, cualquiera autorizado a crear un Pod en un espacio de nombres puede usar ese acceso para leer cualquier Secret de ese espacio de nombres». La sección 4.6 lo pone a prueba.

#### 4.4.2 El token se genera, no se escribe

El token del `revisor` no es un valor que se elige, ni uno que se copia de un documento. Se genera, al azar, cada vez que hace falta uno nuevo:

```text
$ (umask 077; openssl rand -hex 16 > token.txt)

$ ls -l token.txt | cut -d' ' -f1
-rw-------

$ wc -c < token.txt
      33

$ cat .gitignore
token.txt

$ git check-ignore -v token.txt
programas/04-configuracion-secretos/.gitignore:1:token.txt	token.txt
```

`openssl rand -hex 16` pide 16 bytes al azar y los escribe en hexadecimal: 32 caracteres, más el salto de línea que agrega al final. Por eso `wc -c` cuenta 33. Los paréntesis y el `umask 077` cambian la máscara de permisos **solo para ese comando**: el archivo nace con permiso `0600` (`-rw-------`), que solo tú puedes leer, en vez del `0644` que dejaría tu máscara habitual, legible para cualquier usuario de la máquina. Es el mismo token que dentro del Pod va a tener `0440`: se cuida igual en tu máquina que en el clúster. Ese salto de línea no estorba: el `revisor`, al leer el archivo, le quita los espacios y saltos de las orillas (`strings.TrimSpace`, en su código).

Los dos últimos comandos son el hábito de esta lección. `.gitignore` dice que `token.txt` **no** entra al repositorio, y `git check-ignore -v` lo confirma, diciendo qué archivo y qué renglón lo excluyen. La escena empezó con un token en el historial de Git, y esta es la forma de que no vuelva a pasar: el archivo existe en tu máquina, el clúster lo recibe, y Git nunca lo ve. Si trabajas fuera de un repositorio, `git check-ignore` te dirá que no es un repositorio; la regla sigue valiendo para el día que lo sea.

#### 4.4.3 ¿Por qué como archivo y no como variable?

Un Secret se puede pasar como variable de entorno (con `secretKeyRef`, gemelo de `configMapKeyRef`). Este curso no lo hace, y no por gusto:

- **Una variable se hereda.** Todo proceso que lance el contenedor recibe una copia de su entorno. Un archivo no se copia a cada proceso hijo: hay que ir a abrirlo a propósito, y solo puede abrirlo quien tenga permiso.
- **Una variable se imprime sin querer.** En un volcado de errores, en un `env` de depuración, en la bitácora de un programa que, al fallar, escribe «arranqué con esta configuración». La [guía de buenas prácticas de Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) le pide a cada aplicación que, después de leer el Secret, evite «registrar el dato en claro».
- **El `revisor` mismo lo pide.** Si recibe el token en `REVISOR_TOKEN`, arranca, pero escribe en su bitácora un aviso: `el token llegó por REVISOR_TOKEN: cualquiera con docker inspect lo puede leer; usa REVISOR_TOKEN_ARCHIVO`. Su programa ya votó.

Así que el `revisor` recibe dos cosas: el Secret montado como archivo en `/secretos/token`, y una variable normal, no secreta, que le dice dónde buscarlo: `REVISOR_TOKEN_ARCHIVO=/secretos/token`. La ruta no es un secreto; el contenido, sí.

### 4.5 Kustomize: los generadores y el *hash*

#### 4.5.1 La idea: el nombre cambia cuando cambia el contenido

Recuerda los dos problemas de 4.3: el cambio de ConfigMap no disparaba un *rollout*, y no había forma de volver a la configuración vieja. Los dos vienen del mismo lugar: el ConfigMap tiene un **nombre fijo**, así que la plantilla del Deployment nunca cambia, aunque cambie lo que hay dentro.

Ahora imagina que el ConfigMap se llamara distinto según su contenido: `revisor-config-t6cm6872fk` con una lista, `revisor-config-7fbkh2926f` con otra. Cambiar la lista crearía **otro** ConfigMap, y el Deployment tendría que apuntar al nombre nuevo. Su plantilla cambiaría, y la regla de la Lección 2 haría el resto: *rollout*. Y el ConfigMap viejo seguiría ahí, intacto, para que una revisión vieja del Deployment apunte a él.

Hacer eso a mano sería un tormento: calcular un nombre, escribirlo en dos lugares, no equivocarte nunca. Para eso está **Kustomize**, que viene dentro de `kubectl` desde la versión 1.14 (`kubectl kustomize` y `kubectl apply -k`); en este curso es la v5.8.1, la que trae `kubectl` v1.37.1. La [guía de Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) lo explica en una frase: los ConfigMaps y Secrets generados «llevan un sufijo con el *hash* de su contenido. Esto asegura que se genere un ConfigMap o Secret nuevo cuando cambia el contenido». Y Kustomize no solo genera el nombre: busca en tus manifiestos todas las referencias a `revisor-config` y les pone el nombre nuevo.

#### 4.5.2 La `kustomization.yaml`

Kustomize lee un archivo llamado `kustomization.yaml` en una carpeta. Este es el de la lección, un **programa**:

```yaml
# kustomization.yaml — Lección 4. Se aplica con: kubectl apply -k .
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
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

Tres bloques:

- **`resources`**: los manifiestos que ya conoces, tal cual. Kustomize los lee, los ajusta y los entrega juntos. `depurar.yaml` no está en la lista a propósito: es una herramienta de depuración, no parte del servicio.
- **`configMapGenerator`**: «genera un ConfigMap llamado `revisor-config`, con esta llave y este valor». `literals` es para valores escritos ahí mismo, con la forma `LLAVE=valor`. La lista de servicios ya no está en el Deployment: está aquí, en un renglón que se puede revisar solo.
- **`secretGenerator`**: «genera un Secret llamado `revisor-token`, con una llave `token` cuyo contenido es el del archivo `token.txt`». La forma `token=token.txt` separa el nombre de la llave (a la izquierda) del archivo de donde sale (a la derecha). Sin el `token=`, la llave se llamaría como el archivo, `token.txt`. Y `options: immutable: true` marca el Secret como inmutable; la sección «El hábito de seguridad» explica por qué.

Fíjate en lo que **no** está en este archivo: el token. La `kustomization.yaml` sí va al repositorio, y solo dice de dónde sacarlo.

#### 4.5.3 El Deployment final

El Deployment de la lección es `revisor-deployment.yaml`, un **programa**. Respecto a `fig04_02` cambian tres cosas: el token montado como archivo, la variable que dice dónde está, y una línea nueva en el `securityContext` del Pod:

```yaml
# revisor-deployment.yaml — Lección 4: la configuración llega de un ConfigMap
# (por variable) y el token de un Secret (por archivo, inmutable).
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

Recórrelo de abajo hacia arriba, siguiendo el viaje del token:

- **El volumen `token`**, de tipo `secret`, toma el Secret `revisor-token` y convierte cada llave en un archivo. El Secret tiene una llave, `token`, así que el volumen tendrá un archivo, `token`.
- **`defaultMode: 0440`**: los permisos de ese archivo. `0440` en octal es «el dueño puede leer, el grupo puede leer, los demás nada, y nadie escribe». Si no lo pones, la [guía para distribuir credenciales](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) dice que se usa `0644`, que deja leer a todos. Aquí no hay más usuarios dentro del contenedor, pero el permiso mínimo no cuesta nada.
- **El montaje** pone ese volumen en `/secretos`, con `readOnly: true`. Así, el archivo queda en `/secretos/token`.
- **La variable `REVISOR_TOKEN_ARCHIVO`** le dice al `revisor` esa ruta. Es un `value` normal: la ruta no es secreta.
- **`fsGroup: 65532`**, arriba, en el `securityContext` del Pod. Es la línea más corta y la que más cuesta entender, así que tiene su propia explicación en 4.5.6.

Fíjate en `name: revisor-config` y `secretName: revisor-token`: aquí van **sin** *hash*. Los escribes así, con el nombre base, y Kustomize los cambia al nombre generado al armar el resultado. Si escribieras el nombre con *hash*, lo tendrías que cambiar a mano en cada cambio de lista, que es justo lo que se quería evitar.

#### 4.5.4 Ver antes de aplicar

`kubectl kustomize .` arma el resultado y lo imprime, **sin** tocar el clúster. Es la forma de ver qué va a pasar:

```text
$ kubectl kustomize . | grep -E '^  name: revisor-(config|token)'
  name: revisor-config-t6cm6872fk
  name: revisor-token-bh266kt42m

$ kubectl kustomize . | grep -B4 -A3 '^kind: Secret'
apiVersion: v1
data:
  token: NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK
immutable: true
kind: Secret
metadata:
  name: revisor-token-bh266kt42m
type: Opaque
```

Ahí están los nombres generados: `revisor-config-t6cm6872fk` y `revisor-token-bh266kt42m`. El sufijo del ConfigMap depende solo de su contenido, así que en tu máquina debe salir el mismo, `t6cm6872fk`. El del Secret depende del token, que es nuevo en cada corrida; el tuyo será otro.

Y ahí está el Secret como lo va a recibir el clúster. `type: Opaque` es el tipo genérico, «datos cualesquiera». `immutable: true` viene de las `options`. Y en `data`, la llave `token` con un valor que no se parece a tu token. Guarda esa cadena: en 4.6 la vas a desarmar.

#### 4.5.5 Aplicar

Comprueba el contexto y aplica:

```text
$ kubectl config current-context
kind-curso-k8s-l4

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

`apply -k .` es `apply` con Kustomize: arma la carpeta y aplica el resultado. Kustomize ordena los objetos para que el ConfigMap y el Secret se creen **antes** que el Deployment que los usa. Los Services y `prueba` no cambiaron (`unchanged`). El `revisor` sí (`configured`): su plantilla ahora apunta a nombres nuevos y monta un volumen nuevo.

Ahora mira qué quedó en el clúster. Para los Secrets se usa un **selector de campo** (`--field-selector`), que filtra por un campo del objeto y no por sus etiquetas: `type!=kubernetes.io/service-account-token` deja fuera los Secrets de tipo «token de cuenta de servicio», si los hubiera, para ver solo los tuyos:

```text
$ kubectl get configmap
NAME                        DATA   AGE
kube-root-ca.crt            1      77s
revisor-config              1      41s
revisor-config-t6cm6872fk   1      4s

$ kubectl get secret --field-selector type!=kubernetes.io/service-account-token
NAME                       TYPE     DATA   AGE
revisor-token-bh266kt42m   Opaque   1      4s

$ kubectl delete configmap revisor-config
configmap "revisor-config" deleted from default namespace
```

Tres ConfigMaps. `kube-root-ca.crt` lo pone Kubernetes en cada espacio de nombres, con el certificado del clúster; no es tuyo. `revisor-config-t6cm6872fk` es el generado. Y `revisor-config`, el que escribiste a mano en 4.2, **sigue ahí**. `kubectl apply` crea y actualiza lo que le das; no borra lo que no le das. Nadie lo usa ya, así que se borró a mano. Recuerda esto en 4.7 y en el Ejercicio 2: cada cambio deja atrás el objeto anterior.

Ahora el Pod por dentro:

```text
$ kubectl describe pod revisor-f6dd4cb4d-cg7tb | sed -n '/Environment:/,/Conditions:/p'
    Environment:
      REVISOR_SERVICIOS:      <set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config-t6cm6872fk'>  Optional: false
      REVISOR_TOKEN_ARCHIVO:  /secretos/token
    Mounts:
      /datos from datos (rw)
      /secretos from token (ro)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-2gqd7 (ro)
Conditions:
```

`config map 'revisor-config-t6cm6872fk'`: el Deployment ya apunta al nombre con *hash*, aunque en tu archivo escribiste `revisor-config`. Kustomize lo cambió al armar. Y en `Mounts`, `/secretos from token (ro)`: el Secret montado, solo lectura. El tercer montaje es la credencial de la cuenta de servicio que la Lección 2 dejó anotada como deuda; la Lección 7 la quita.

¿Y el `revisor`? Ahora tiene token, así que lo exige:

```text
$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' http://revisor/api/estados
401

$ kubectl exec depurar -- curl -s http://revisor/api/estados
{"error":"falta el token o no es válido"}

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200

$ kubectl exec deployment/revisor -- /revisor healthcheck
sano
```

Sin token, `401` y un mensaje claro. Con el encabezado `Authorization: Bearer …`, la tabla. Fíjate en las comillas del tercer comando: `$(cat token.txt)` está entre comillas dobles, así que tu *shell* lo sustituye **en tu máquina**, antes de mandar el comando al Pod. El token nunca aparece escrito en tu historial de comandos, solo el `cat`. Sí aparece, mientras dura el comando, como argumento del proceso: en un `ps` de tu máquina y dentro de `depurar`. Para un ejercicio local basta; en un clúster compartido, el token no se pasa por la línea de comandos. Y `/salud` (la que consulta `healthcheck`) no pide token, a propósito: las sondas de la Lección 5 la van a llamar sin credenciales.

La tabla volvió a decir solo `prueba`, y eso también es correcto: la lista de la `kustomization.yaml` tiene un solo servicio. El `lento` que agregaste a mano en 4.3 vivía en el ConfigMap que acabas de borrar.

#### 4.5.6 El Secret, visto desde el nodo

¿Dónde está físicamente el archivo `/secretos/token`? El `revisor` no tiene *shell* para ir a mirarlo, pero el nodo de kind sí, y el `kubelet` guarda los volúmenes de cada Pod en una carpeta con el identificador (`uid`) del Pod. Para este Pod, en el nodo `curso-k8s-l4-worker`:

```text
$ docker exec curso-k8s-l4-worker ls -ln /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 65532 33 Oct 21 13:27 token

$ docker exec curso-k8s-l4-worker sh -c 'mount | grep a415d22b-9837-4123-a7d9-82b1baf9435a | grep -E "secret/token "'
tmpfs on /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token type tmpfs (rw,relatime,size=16342676k,inode64,noswap)
```

El nombre del nodo y el `uid` del Pod salen de `kubectl get pod <pod> -o jsonpath='{.spec.nodeName}'` y `'{.metadata.uid}'`; el guion los busca solo. Dos cosas que comprobar con tus ojos:

- **`-r--r----- 1 0 65532 33 … token`**: el archivo tiene los permisos `0440` que pediste (`r--r-----`), mide 33 bytes (tu token con su salto de línea), su dueño es el usuario `0` (`root`) y su grupo es el **65532**. Ese grupo lo puso `fsGroup`.
- **`tmpfs`**: la carpeta del volumen es un sistema de archivos en memoria, como promete la documentación. El token no se escribió en el disco del nodo.

La carpeta `..data` es un detalle de cómo el `kubelet` actualiza los volúmenes de Secrets: el archivo `token` que ve el contenedor es un enlace a `..data/token`, y cuando el Secret cambia, el `kubelet` prepara una carpeta nueva y cambia el enlace de un golpe. Con un Secret inmutable, como este, eso no va a pasar nunca.

Ahora junta el renglón de `ls` con el `securityContext`. El `revisor` corre como usuario 65532 y grupo 65532. El archivo es de `root` y del grupo 65532, con permiso de lectura para el grupo. El `revisor` lo lee **por ser del grupo**. Sin `fsGroup`, el grupo del archivo sería otro y el `revisor` no tendría por dónde leerlo. La [guía del `securityContext`](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) describe `fsGroup` así: los procesos del contenedor se vuelven parte de ese grupo como grupo adicional, y «los volúmenes que admiten administración de dueños se modifican para que sean del GID que indica `fsGroup`». La sección «El error que vas a ver» te enseña qué pasa si te lo saltas, y no es lo que esperarías.

### 4.6 base64 no es cifrado

Toma la cadena que viste en el Secret y la del clúster:

```text
$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}{"\n"}'
NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK

$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}' | base64 -d
433c7adfa6fc6fc3d03676b7f5c2339e

$ cat token.txt
433c7adfa6fc6fc3d03676b7f5c2339e
```

(El `grep revisor-token | xargs` encuentra el Secret aunque su nombre cambie en cada corrida.) Un comando, sin llave, sin contraseña, sin nada que adivinar: `base64 -d` devuelve el token completo, idéntico al archivo. **base64 no es cifrado.** Es una **codificación**: una forma de escribir cualquier secuencia de bytes usando solo letras, números, `+` y `/`, más un `=` de relleno al final cuando hace falta (como el `eA==` de más adelante), para que quepa en un archivo de texto como un YAML. Cifrar quiere decir que, sin una llave, no se puede leer. Codificar quiere decir que se puede leer con una tabla pública. La guía de buenas prácticas lo dice en una línea: «la codificación base64 **no** es un método de cifrado; no da ninguna confidencialidad adicional sobre el texto plano». Y avisa del error de la escena: si guardas un manifiesto de Secret en un repositorio, «el secreto queda al alcance de todos los que puedan leer el manifiesto».

¿Por qué existe entonces el base64? Porque un Secret puede guardar cualquier cosa, también datos binarios, como un certificado o una llave, y un YAML es texto. El base64 es el sobre que permite meter bytes en un archivo de texto. No es una caja fuerte.

¿Quién puede hacer lo que acabas de hacer?

```text
$ kubectl auth can-i get secrets
yes
```

`kubectl auth can-i` le pregunta al clúster si **tú** puedes hacer algo, sin hacerlo. Tú puedes, porque el `kubeconfig` que te dio kind es de administrador. En un clúster real, eso lo controla RBAC, y la Lección 7 lo practica. Pero la documentación de Secrets advierte de una puerta trasera: quien puede crear un Pod en un espacio de nombres puede montar en él cualquier Secret de ese espacio y leerlo desde dentro, aunque no tenga permiso para `get secrets`. Por eso los Secrets de un servicio viven en el espacio de nombres de ese servicio, y no en uno compartido con otros (Lección 7).

Y una más, que no se ve desde aquí: dentro del clúster, el Secret se guarda en `etcd` **sin cifrar**, salvo que el administrador active el cifrado en reposo del `kube-apiserver`. La guía de buenas prácticas lo pone como la primera recomendación: «deberías configurar el cifrado de los datos de tus Secrets en etcd». En kind no se hace; la Lección 10 lo anota en la lista de lo que falta para producción.

Lo que sí te da un Secret, comparado con escribir el token en el Deployment, es esto: el token no está en tu manifiesto ni en Git; viaja solo a los nodos que lo usan y ahí vive en memoria; y se puede dar permiso de leer Deployments sin dar permiso de leer Secrets. Es bastante. Solo no es cifrado.

### 4.7 Cambiar la lista dispara el *rollout*

Ahora sí, el pedido de la escena, con la herramienta completa. Antes del cambio, los ReplicaSets del `revisor` (cuatro revisiones: la de la Lección 3, la de `fig04_02`, la del `rollout restart` y la de `apply -k`):

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   0         0         0       43s
revisor-697fb84f97   0         0         0       52s
revisor-99546b58f    0         0         0       9s
revisor-f6dd4cb4d    3         3         3       6s
```

El cambio se hace **en la `kustomization.yaml`**, no en el clúster (y antes de aplicarlo, otra vez `kubectl config current-context`). Abre el archivo y agrega el servicio al final de la lista, separado por una coma:

```text
$ grep REVISOR_SERVICIOS kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
```

Antes de aplicar, pregúntale al clúster qué cambiaría. `kubectl diff -k .` compara lo que Kustomize armaría con lo que hay en el clúster; aquí se filtró para ver solo los renglones que importan:

```text
$ kubectl diff -k . | grep -E '^[-+] .*(REVISOR_SERVICIOS|name: revisor-config)'
-              name: revisor-config-t6cm6872fk
+              name: revisor-config-7fbkh2926f
+  REVISOR_SERVICIOS: prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
+  name: revisor-config-7fbkh2926f
[código de salida: 1]
```

Léelo renglón por renglón. Los dos primeros son del **Deployment**: su referencia pasa de `revisor-config-t6cm6872fk` a `revisor-config-7fbkh2926f`. Los dos últimos son de un **ConfigMap nuevo**, con la lista nueva y el nombre nuevo. Esos dos primeros renglones son el *rollout*, anunciado antes de que pase: la plantilla del Pod cambia. (El código de salida 1 es de `kubectl diff`, que así avisa que **sí** encontró diferencias. No es un error.)

Con el mismo contenido, el mismo nombre: tu `7fbkh2926f` debe ser idéntico a este. Aplicar:

```text
$ kubectl apply -k .
configmap/revisor-config-7fbkh2926f created
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

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
revisor-66db8c7755   0         0         0       46s
revisor-697fb84f97   0         0         0       55s
revisor-769ff55c9c   3         3         3       3s
revisor-99546b58f    0         0         0       12s
revisor-f6dd4cb4d    0         0         0       9s

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
lento     OK           1ms  200
prueba    OK           1ms  200
```

Un ConfigMap nuevo (`created`), el Secret sin cambios (`unchanged`: el token no cambió, ni su nombre), un ReplicaSet nuevo, `revisor-769ff55c9c`, que tomó las tres réplicas por turnos, y la tabla con dos servicios. **Nadie tuvo que acordarse de reiniciar nada.** Es la meta 4 del curso: cambias la lista y el clúster hace el *rollout* por sí solo, sin reconstruir la imagen.

Y la vuelta atrás, que en 4.3 era imposible, aquí es trivial. Se devolvió la `kustomization.yaml` a su lista original y se aplicó:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

`revisor-config-t6cm6872fk unchanged`: el ConfigMap de la lista original **nunca se fue**. Kustomize calculó el mismo nombre para el mismo contenido, el Deployment volvió a apuntar a él y su plantilla volvió a ser idéntica a la del ReplicaSet `revisor-f6dd4cb4d`. Cada configuración tiene su propio objeto, y cada revisión del Deployment apunta a la suya.

El precio de esto ya lo viste en 4.5.5: `revisor-config-7fbkh2926f` se quedó en el clúster, sin nadie que lo use. Con el tiempo se juntan. Es un precio pequeño (cada uno pesa unos bytes) y se paga a cambio de poder volver atrás; la forma de limpiarlos con orden es parte de lo que la Lección 10 deja para un clúster real.

## El error que vas a ver

El error de esta lección aparece justo cuando crees que terminaste: el Secret existe, el montaje está bien escrito, la ruta es correcta… y el `revisor` no arranca. Se provocó a propósito quitándole al Deployment la línea `fsGroup` con un `patch`, después de comprobar el contexto:

```text
$ kubectl patch deployment revisor --type=json -p='[{"op":"remove","path":"/spec/template/spec/securityContext/fsGroup"}]'
deployment.apps/revisor patched
```

(`--type=json` permite operaciones precisas como `remove`, sobre una ruta exacta del objeto. Es la forma de quitar **una** línea sin reescribir el archivo.) Veinticinco segundos después, se lee en el orden de siempre.

**Primero, el estado.**

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS   RESTARTS      AGE
revisor-7ffcfb7646-2lsmc   0/1     Error    2 (23s ago)   24s
revisor-7ffcfb7646-k4s2b   0/1     Error    2 (23s ago)   25s
revisor-7ffcfb7646-th42g   0/1     Error    2 (24s ago)   25s
```

`Error` y `RESTARTS 2`: el contenedor **sí arrancó**, y el programa terminó con error; el `kubelet` lo reinició y volvió a terminar. Es un estado distinto de los de la Lección 2. No es `ImagePullBackOff` (la imagen está) ni `CreateContainerConfigError` (la configuración se pudo armar). Es el programa el que se cae. En unos segundos más, el estado pasa a `CrashLoopBackOff`: la [documentación del ciclo de vida de un Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) explica que el `kubelet` reinicia con una espera que crece (10 s, 20 s, 40 s…) hasta un tope de 300 s, y que `CrashLoopBackOff` es el nombre de esa espera. `Error` y `CrashLoopBackOff` se alternan: uno es «se cayó», el otro es «espero antes de volver a intentar».

**Segundo, los `logs`**, porque si el programa arrancó, el programa tiene algo que decir:

```text
$ kubectl logs revisor-7ffcfb7646-2lsmc
revisor: leyendo el token de REVISOR_TOKEN_ARCHIVO: open /secretos/token: permission denied
```

Un renglón, y lo dice todo: el `revisor` fue a leer el archivo que le indicaba `REVISOR_TOKEN_ARCHIVO`, el sistema operativo le negó el permiso (`permission denied`), y el `revisor` se negó a arrancar sin su token. Ese «negarse» es una decisión de su código, y es la correcta: un `revisor` que arrancara sin token dejaría `/api/estados` abierto a cualquiera.

¿Por qué no lo pudo leer? Míralo en el nodo, igual que en 4.5.6, ahora para uno de los Pods que fallan:

```text
$ docker exec curso-k8s-l4-worker2 ls -ln /var/lib/kubelet/pods/c26f312f-6841-4911-bea8-6f14513b4a11/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 0 33 Oct 21 13:28 token
```

Compáralo con el de 4.5.6, `-r--r----- 1 0 65532`. Los permisos son los mismos, `0440`, y el dueño también, `root`. Lo que cambió es el **grupo**: con `fsGroup` era el 65532 y el `revisor` lo leía por ser del grupo; sin `fsGroup` es el `0`, el de `root`. El usuario 65532 no es ni el dueño ni del grupo, y para él `0440` es «nada».

**Tercero, `describe`**, para confirmar quién habla:

```text
$ kubectl describe pod revisor-7ffcfb7646-2lsmc | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  24s                default-scheduler  Successfully assigned default/revisor-7ffcfb7646-2lsmc to curso-k8s-l4-worker2
  Normal   Pulled     11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container image "curso-docker-revisor:1.6.0" already present on machine and can be accessed by the pod
  Normal   Created    11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container created
  Normal   Started    11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container started
  Warning  BackOff    10s (x2 over 22s)  kubelet            spec.containers{revisor}: Back-off restarting failed container revisor in pod revisor-7ffcfb7646-2lsmc_default(c26f312f-6841-4911-bea8-6f14513b4a11)
```

Todo `Normal` hasta `Started`, tres veces (`x3`): la imagen estaba, el contenedor se creó y arrancó. El único `Warning` es `BackOff`, «espero antes de reiniciar el contenedor que falló». Los eventos no dicen **por qué** falló, porque el clúster no lo sabe: el programa se cayó por su cuenta. Por eso, cuando el contenedor llegó a arrancar, los `logs` van antes que el `describe`. En la Lección 2, con `ImagePullBackOff`, era al revés: no había programa que hablara, y la respuesta estaba en los eventos.

**Y ahora lo que no esperabas:**

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   0/3     3            0           83s
```

`0/3`. **No queda ni una réplica sana.** En el Ejercicio 3 de la Lección 2, una imagen rota dejó el *rollout* atorado con el servicio intacto: tres Pods viejos vivos y uno nuevo fallando. Aquí, los tres Pods viejos ya no están. ¿Qué cambió, si la estrategia es la misma (`maxSurge` 1, `maxUnavailable` 0)?

La diferencia es **cuándo** falla el Pod nuevo. Con la imagen rota, el contenedor nunca arrancaba, así que el Pod nunca estuvo listo y el Deployment nunca quitó uno viejo. Aquí, el contenedor **sí arranca**, y vive unos milisegundos antes de leer el token y caerse. Para el Deployment, eso basta. Sin una sonda que pregunte «¿ya puedes atender?», Kubernetes da por listo a un contenedor en cuanto arranca. La [documentación de Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) define cuándo un Pod nuevo cuenta como disponible: cuando está listo, sin que se le caiga ningún contenedor, durante al menos `minReadySeconds`, que por omisión es **cero**. Cada Pod nuevo estuvo «listo» un instante, el Deployment lo contó, quitó uno viejo, y así tres veces. El *rollout* terminó con éxito… sobre tres Pods que no funcionan.

Esto es lo más importante de la sección, y no es un defecto de Kubernetes: **el clúster solo sabe lo que tú le enseñas a preguntar.** Un `revisor` que arranca no es un `revisor` que puede atender. La Lección 5 le da al Deployment una sonda de disponibilidad, y con ella este mismo error deja tres réplicas viejas vivas, como en la Lección 2.

**La salida** es la de siempre en este curso: el archivo es la verdad, y se vuelve a aplicar.

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
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
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

`apply -k` devolvió la línea `fsGroup` y la plantilla volvió a ser la de antes del `patch`. Fíjate en que el *rollout* de regreso también fue por turnos: aquí sí, los Pods nuevos leen el token, siguen vivos y el Deployment avanza sobre Pods que funcionan.

**El orden, para un Pod que arranca y se cae:** el estado (`get pods`: `Error` o `CrashLoopBackOff`, con `RESTARTS` subiendo), los `logs` (lo que dijo el programa antes de caerse; si el contenedor ya se reinició, `kubectl logs --previous` muestra los del intento anterior) y, al final, el `describe`. Y antes de concluir que «no pasó nada grave», `kubectl get deployment`: cuántas réplicas quedan **de verdad** atendiendo.

## El hábito de seguridad de la lección: el Secret no se versiona, se monta como archivo y se marca inmutable

La tabla de hábitos del curso le asigna a esta lección tres reglas sobre el Secret. Las tres ya las viste funcionando; aquí van juntas, con lo que defiende cada una.

**No se versiona.** El token vive en `token.txt`, que `.gitignore` deja fuera del repositorio, y la `kustomization.yaml` solo dice de dónde leerlo. Lo que va a Git es la receta, nunca el valor. Es la respuesta directa a la escena: un secreto que entra a Git una vez se queda en el historial para siempre, aunque lo borres en la versión siguiente, y la única reparación real es cambiarlo.

**Se monta como archivo**, con `defaultMode: 0440`, `readOnly: true` y `fsGroup` para que lo lea solo el grupo del `revisor`. Viviendo en un `tmpfs`, no toca el disco del nodo. Y no se hereda a otros procesos ni aparece en un listado de variables.

**Se marca inmutable.** Con `immutable: true`, el clúster se niega a cambiar el contenido del Secret:

```text
$ kubectl get secret -o name | grep revisor-token | xargs -I{} kubectl patch {} -p '{"data":{"token":"eA=="}}'
The Secret "revisor-token-bh266kt42m" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]
```

`eA==` es la letra `x` en base64: el intento era cambiar el token por una sola letra. El `kube-apiserver` lo rechazó antes de guardarlo: «prohibido: el campo es inmutable cuando `immutable` está puesto». La [documentación de Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) da dos razones para usarlo. La primera, que te protege de «actualizaciones accidentales (o no deseadas) que podrían causar caídas de las aplicaciones». La segunda es de rendimiento: el `kubelet` no necesita vigilar los Secrets inmutables, y en un clúster con miles de ellos eso le quita carga al `kube-apiserver`. Y una advertencia que hay que saberse: la marca **no tiene vuelta**. «Una vez que un Secret o un ConfigMap se marca como inmutable, no es posible revertir el cambio ni modificar el contenido de `data`. Solo puedes borrar el Secret y volverlo a crear».

¿Entonces cómo se cambia el token? Con **otro** Secret. Y eso, con Kustomize, ya lo tienes: un token nuevo da un *hash* nuevo, un nombre nuevo, y el Deployment pasa a montar el Secret nuevo con un *rollout*. Ningún Pod ve cambiar su archivo a medio camino; cada Pod nace con un token y muere con él. El Ejercicio 2 lo hace. El generador y la marca inmutable están hechos el uno para el otro: el generador nunca quiere modificar un Secret, siempre crea otro.

**Lo que defiende y lo que no.** Estas tres reglas cuidan el token **fuera** del clúster (Git) y **en el nodo** (memoria, permisos). No lo cuidan **dentro** del `kube-apiserver`: quien tenga permiso de leer Secrets, o de crear Pods en el espacio de nombres, lo lee con `base64 -d`, como hiciste en 4.6. Eso lo defienden los permisos (Lección 7) y el cifrado en reposo de un clúster real (Lección 10).

## Lo que se hace mal

**Creer que base64 protege algo.** Es una codificación, no un cifrado. Un manifiesto de Secret con su `data` en un repositorio es el secreto publicado. Lo viste en 4.6: un `base64 -d`.

**Versionar el Secret «porque así se reconstruye el clúster solo».** Lo que se reconstruye es lo que está en Git, y eso incluye al que no debía ver el token. El token se genera o se trae de un lugar hecho para guardar secretos (un gestor de secretos, en un clúster real), y Git guarda solo de dónde sacarlo.

**Cambiar un ConfigMap a mano y dar por hecho que el programa ya lo sabe.** Si el programa lo lee como variable, no se entera hasta que el Pod renace. Lo mediste en 4.3: el ConfigMap decía dos servicios y el `revisor` seguía reportando uno. La prueba de que un cambio llegó es el comportamiento del programa, no el objeto.

**Escribir en el Deployment el nombre con *hash*.** `name: revisor-config-t6cm6872fk` escrito a mano deja de servir en el siguiente cambio de lista. Se escribe el nombre base y Kustomize lo traduce.

**Desactivar el *hash* para que el nombre se vea limpio.** `disableNameSuffixHash: true` existe, y te regresa al problema de 4.3: el cambio de contenido no cambia la plantilla, y no hay *rollout*. Lo vas a comprobar en el Ejercicio 3.

**Dar el token por variable de entorno «porque es más fácil».** Se hereda, se imprime sin querer, y el propio `revisor` te avisa en su bitácora que no lo hagas.

**Quitar `fsGroup`, o poner `defaultMode: 0444`, «para que lo pueda leer».** `fsGroup` es la forma correcta de que el `revisor` lea el archivo **por ser de su grupo**. Abrir el archivo a todos funciona, pero renuncias al permiso mínimo. Y si quitas `fsGroup` sin entender, ya viste lo que cuesta.

**Fiarse de `successfully rolled out`.** Sin sondas, un *rollout* puede terminar con éxito sobre Pods que se caen al leer su configuración. Antes de dar algo por bueno, `kubectl get deployment` y una petición de verdad.

**Olvidar que `apply` no borra.** Cada cambio con generadores deja atrás el ConfigMap o el Secret anterior, y un ConfigMap escrito a mano que ya nadie usa también se queda. No hacen daño, pero un Secret viejo que nadie usa sigue siendo un Secret: un token viejo legible. Los Secrets que ya no sirven se borran.

## Ejercicios

Los tres primeros se corren en el clúster de la lección, en orden, desde el estado en que quedó al final de «El hábito de seguridad», y desde la carpeta `programas/04-configuracion-secretos`. **Antes de cada ejercicio, `kubectl config current-context` debe decir `kind-curso-k8s-l4`; si dice otra cosa, no sigas.** `correr.sh` los corre igual, y su salida está en `correr.salida.txt`. **Antes** de correr cada uno, escribe en la [bitácora](bitacora.md) qué crees que va a pasar. El cuarto se escribe con tus palabras.

### Ejercicio 1 — Una llave que no existe

Cambia, con un `patch`, la llave que el Deployment busca en el ConfigMap, como si te hubieras equivocado al escribirla (`REVISOR_SERVICIO`, sin la S final):

```bash
kubectl patch deployment revisor --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key","value":"REVISOR_SERVICIO"}]'
```

Predice: ¿en qué estado queda el Pod nuevo? ¿Arranca el contenedor? ¿Cuántas réplicas viejas siguen atendiendo, y por qué esta vez no se repite el `0/3` de «El error que vas a ver»? Compruébalo con `kubectl get pods -l app=revisor` y con los eventos `Failed` del Pod nuevo. Para salir, vuelve a aplicar la `kustomization.yaml`.

### Ejercicio 2 — Rotar el token (proyecto)

Alguien vio el token en una pantalla compartida y hay que cambiarlo. Antes de generar el nuevo, guarda el viejo en una variable de tu terminal, `VIEJO="$(cat token.txt)"`, para poder probarlo después. Genera el nuevo con `(umask 077; openssl rand -hex 16 > token.txt)` y aplica `kubectl apply -k .`. Antes de aplicar, predice: ¿se modifica el Secret que había, o aparece otro? ¿Hay *rollout*? ¿Qué responde el `revisor` a una petición con el token **viejo**, y qué a una con el nuevo? Compruébalo con `kubectl get secret -o name | grep revisor-token` y con dos `curl` desde `depurar`, uno con `-H "Authorization: Bearer $VIEJO"` y otro con `-H "Authorization: Bearer $(cat token.txt)"`. Para terminar, explica qué tendrías que hacer con el Secret viejo, y por qué.

### Ejercicio 3 — Sin el *hash*

Copia la carpeta de la lección a otro lugar, agrega al final de la copia de `kustomization.yaml` estas dos líneas y mira el resultado con `kubectl kustomize` (sin aplicarlo):

```yaml
generatorOptions:
  disableNameSuffixHash: true
```

Predice antes: ¿cómo se van a llamar el ConfigMap y el Secret? ¿A qué nombre va a apuntar el Deployment? Después, sin correrlo, contesta: si con esta opción cambias la lista y aplicas, ¿hay *rollout*? ¿Qué parte de la lección acabas de repetir? Y, como el Secret es inmutable, ¿qué crees que pasaría al rotar el token con esta opción?

### Ejercicio 4 — Defiende el archivo

Un compañero propone pasar el token con `secretKeyRef`, como variable de entorno, «porque es una línea y no un volumen, y el Secret es igual de secreto en los dos casos». En cinco frases como máximo, contéstale: en qué tiene razón, qué riesgo agrega la variable que el archivo no tiene, qué dice el propio `revisor` cuando recibe el token por variable, y qué habría que agregar al Deployment para que el archivo se pueda leer sin abrirlo a todos.

## Soluciones

### Solución 1

Medido en `correr.salida.txt`:

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS                       RESTARTS   AGE
revisor-84564b6875-ssrsx   0/1     CreateContainerConfigError   0          15s
revisor-f6dd4cb4d-6nrc8    1/1     Running                      0          17s
revisor-f6dd4cb4d-9sjs2    1/1     Running                      0          17s
revisor-f6dd4cb4d-s5h4z    1/1     Running                      0          18s

$ kubectl get events --field-selector involvedObject.name=revisor-84564b6875-ssrsx,reason=Failed -o custom-columns=MENSAJE:.message | head -2
MENSAJE
Error: couldn't find key REVISOR_SERVICIO in ConfigMap default/revisor-config-t6cm6872fk
```

El Pod nuevo queda en **`CreateContainerConfigError`**, el mismo estado del `runAsNonRoot` de la Lección 2: el `kubelet` no pudo armar la configuración del contenedor y **no lo arrancó**. El evento dice exactamente qué faltó: la llave `REVISOR_SERVICIO` en el ConfigMap `default/revisor-config-t6cm6872fk`. Es lo que anunciaba `Optional: false` en el `describe` de 4.2.

**Las tres réplicas viejas siguen atendiendo.** La diferencia con el `0/3` del `fsGroup` es el momento del fallo. Aquí el contenedor nunca arrancó, así que el Pod nuevo nunca estuvo listo, ni un instante, y con `maxUnavailable: 0` el Deployment no quitó ningún Pod viejo. Con el `fsGroup`, el contenedor arrancaba, estaba «listo» unos milisegundos y se caía, y eso le bastó al Deployment para avanzar. La lección de fondo: **un error que impide arrancar es más seguro que uno que arranca y se cae**, mientras no tengas sondas.

Al volver a aplicar la `kustomization.yaml`, la plantilla volvió a la de `revisor-f6dd4cb4d` y el Pod roto desapareció:

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           103s
```

### Solución 2

Medido en `correr.salida.txt`:

```text
$ kubectl get secret -o name | grep revisor-token
secret/revisor-token-bh266kt42m

$ VIEJO="$(cat token.txt)"

$ (umask 077; openssl rand -hex 16 > token.txt)

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-ttgcdb7g7c created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get secret -o name | grep revisor-token
secret/revisor-token-bh266kt42m
secret/revisor-token-ttgcdb7g7c
```

```text
(con el token VIEJO)

$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $VIEJO" http://revisor/api/estados
401

(con el token NUEVO)

$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat token.txt)" http://revisor/api/estados
200
```

`VIEJO` es una variable de tu terminal: el token no queda escrito en tu historial, solo el nombre `$VIEJO`. (No lo guardes en otro archivo, como `token.viejo`: `.gitignore` solo excluye `token.txt`.)

**Aparece otro Secret**, `revisor-token-ttgcdb7g7c`; el viejo no se toca, y no se podría: es inmutable. El token nuevo cambió el *hash*, el *hash* cambió el nombre, el nombre cambió la plantilla del Deployment, y hubo *rollout* (`deployment.apps/revisor configured`, y `rollout status` con los mismos turnos de 4.7). El ConfigMap no cambió (`unchanged`). Al terminar, el token viejo da `401` y el nuevo `200`: los Pods nuevos nacieron con el archivo nuevo, y los viejos, que conocían el token viejo, ya no existen.

**El Secret viejo hay que borrarlo** (`kubectl delete secret revisor-token-bh266kt42m`). Ningún Pod lo usa, pero sigue en el clúster, y cualquiera con permiso de leer Secrets puede sacar de él, con `base64 -d`, un token que alguien vio en una pantalla. Si quisieras poder volver a la revisión anterior del Deployment, ese Secret tendría que existir; pero un token comprometido es justo el que **no** quieres poder volver a usar. Rotar no termina cuando funciona el nuevo: termina cuando el viejo ya no sirve en ningún lado.

### Solución 3

Medido en `correr.salida.txt`, sobre una copia en una carpeta temporal:

```text
$ tail -2 $TEMPORAL/sin-hash/kustomization.yaml
generatorOptions:
  disableNameSuffixHash: true

$ kubectl kustomize $TEMPORAL/sin-hash | grep -E '^  name: revisor-(config|token)|name: revisor-(config|token)$'
  name: revisor-config
  name: revisor-token
              name: revisor-config
```

El ConfigMap se llama `revisor-config` y el Secret `revisor-token`, a secas, y el Deployment apunta a `revisor-config` (el tercer renglón, con más sangría, es su `configMapKeyRef`). Nombres limpios, y **ningún *rollout*** cuando cambie la lista: el ConfigMap conserva su nombre, la plantilla del Deployment no cambia, y la regla «si y solo si» no se cumple. Acabas de repetir la sección 4.3, solo que con Kustomize: el objeto cambia y el `revisor` sigue con la lista vieja hasta que alguien se acuerde del `rollout restart`.

Con el Secret es peor, y se midió. El guion armó una carpeta aparte con **solo** el Secret, inmutable y sin *hash*, en un espacio de nombres desechable, `sin-hash`. Lo aplicó, cambió el token de esa copia y lo volvió a aplicar:

```text
$ kubectl create namespace sin-hash
namespace/sin-hash created

$ kubectl apply -k $TEMPORAL/rotar
secret/revisor-token created

(token nuevo en la copia)

$ kubectl apply -k $TEMPORAL/rotar
The Secret "revisor-token" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]

$ kubectl delete namespace sin-hash
namespace "sin-hash" deleted
```

Como el nombre ya no cambia, `apply -k` intentó **modificar** el Secret que ya existía, y el clúster se negó con el mismo `field is immutable` de «El hábito de seguridad». Para rotar el token tendrías que borrar el Secret a mano antes de aplicar, y mientras tanto los Pods que se reiniciaran no encontrarían su token. Desactivar el *hash* y marcar inmutable son dos decisiones que se contradicen. El *hash* es lo que hace que la inmutabilidad sea práctica. (Borrar el espacio de nombres `sin-hash` se llevó ese Secret con él.)

### Solución 4

Una respuesta posible: «Tienes razón en que el Secret guarda el mismo dato de las dos formas, y en que en `etcd` está igual de expuesto. Pero una variable se hereda a todo proceso que lance el contenedor y aparece en cualquier volcado del entorno o bitácora que imprima la configuración, mientras que un archivo de solo lectura en `tmpfs` no se copia a cada proceso: hay que ir a abrirlo a propósito, y solo puede abrirlo quien tenga permiso. El propio `revisor`, si recibe el token en `REVISOR_TOKEN`, escribe en su bitácora que cualquiera con `docker inspect` lo puede leer y que use `REVISOR_TOKEN_ARCHIVO`. Para leer el archivo sin abrirlo a todos, el Deployment necesita `defaultMode: 0440` y `fsGroup: 65532` en el `securityContext` del Pod, que hace al grupo del `revisor` dueño del archivo. Son tres líneas más que la variable, y las vale.»

## Borrar el clúster

Cuando termines los ejercicios, borra el clúster de la lección. No dejes nada vivo en la máquina:

```text
$ kind delete cluster --name curso-k8s-l4
Deleting cluster "curso-k8s-l4" ...
Deleted nodes: ["curso-k8s-l4-control-plane" "curso-k8s-l4-worker2" "curso-k8s-l4-worker"]

$ kind get clusters | grep -c curso-k8s-l4
0
```

El `--name` es obligatorio aquí también: sin él, kind borraría el clúster llamado `kind`, que puede ser de otra persona o de otro proyecto. Con el clúster se van sus Secrets, sus ConfigMaps y la copia del token que vivía en el `tmpfs` de cada nodo.

Quedan dos cosas en tu máquina, y las dos se borran:

```bash
# El token de la lección: ya no lo usa nadie, y un token suelto no se deja.
rm -f token.txt
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 4.0.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l4.*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

El `case` solo deja pasar una ruta que empiece con `/tmp/curso-k8s-l4.` y termine en `/kubeconfig`, la forma exacta de la que creaste en 4.0; entonces `dirname` le quita el nombre del archivo y `rm -rf` borra esa carpeta y nada más. Si tu terminal apunta a otra parte (por ejemplo, a tu `~/.kube/config`, porque abriste otra terminal y no repetiste el `export`), no borra nada y te dice por qué. Es la misma protección que usa `correr.sh` al limpiar: un `rm -rf` que se puede copiar y pegar tiene que protegerse solo. Cerrar esa terminal también deja de usar el `kubeconfig` temporal. El clúster de la siguiente lección se crea de cero, igual que este.

## Cómo sé que lo logré

- [ ] Explicas, con la tabla del `revisor` como prueba, por qué cambiar un ConfigMap a mano no cambió la lista de servicios de los Pods que ya corrían.
- [ ] Lees en `kubectl describe pod` de qué ConfigMap y qué llave sale cada variable, y qué significa `Optional: false`.
- [ ] Escribes de memoria una `kustomization.yaml` con `resources`, `configMapGenerator` (con `literals`) y `secretGenerator` (con `files: - token=token.txt`), y explicas qué hace el `token=`.
- [ ] Predices, antes de aplicar, que un cambio de lista produce un ConfigMap con otro nombre y un ReplicaSet nuevo, y lo compruebas con `kubectl diff -k .`.
- [ ] Decodificas un Secret con `base64 -d` y explicas en dos frases la diferencia entre codificar y cifrar.
- [ ] Explicas qué hace `fsGroup` con el archivo del Secret, y reconoces el `permission denied` de su ausencia en los `logs`.
- [ ] Explicas por qué el error del `fsGroup` dejó el Deployment en `0/3` y el de la llave mal escrita no.
- [ ] Rotas el token con un Secret nuevo y sabes qué hacer con el viejo.
- [ ] Corres `programas/04-configuracion-secretos/correr.sh > /tmp/mi-corrida-l4.txt 2>&1` y comparas `/tmp/mi-corrida-l4.txt` contra `programas/04-configuracion-secretos/correr.salida.txt` (no redirijas a ese archivo: es la referencia) en lo que no cambia entre corridas: tres nodos `Ready` en `v1.37.0`; la tabla con `prueba OK … 200`; `<set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>`; la tabla que **no** muestra `lento` 30 s después del `patch` y sí después del `rollout restart`; `-rw-------` para `token.txt` y `wc -c` en 33; `token.txt` en `.gitignore`; `revisor-config-t6cm6872fk` como nombre generado; `immutable: true`; `401` sin token, `{"error":"falta el token o no es válido"}` y la tabla con token; `-r--r----- 1 0 65532 33 … token` sobre un `tmpfs`; el token idéntico después de `base64 -d`; `revisor-config-7fbkh2926f` en el `diff` y un ReplicaSet nuevo con `lento` en la tabla; `permission denied` en los `logs`, el archivo como `-r--r----- 1 0 0` y el Deployment en `0/3` sin `fsGroup`; `field is immutable when \`immutable\` is set`; `couldn't find key REVISOR_SERVICIO`; dos Secrets después de rotar, `401` con el viejo y `200` con el nuevo; los nombres sin sufijo del Ejercicio 3 y su `field is immutable` al rotar; y al final `sin diferencias con la kustomization`. El token, el nombre del Secret, los sufijos de Pods y ReplicaSets, las IP, los `uid`, el nodo de cada Pod, las edades, los tiempos de la tabla y las veces que se repite cada renglón de `rollout status` cambian en cada corrida: se observan, no se comparan.
- [ ] Al terminar, `kind get clusters` ya no muestra `curso-k8s-l4`, en la carpeta de la lección no quedó ningún `token.txt` y no queda ninguna carpeta `/tmp/curso-k8s-l4.*`.

## Resumen

Responde sin mirar la lección:

1. ¿Qué es un ConfigMap y qué dice su documentación sobre guardar datos confidenciales en él?
2. ¿Por qué cambiar un ConfigMap que se usa como variable no cambia lo que hace el `revisor`? Da las dos razones: la de Kubernetes y la del programa.
3. ¿Qué hace `configMapKeyRef`, y por qué este curso lo prefiere a `envFrom`?
4. ¿Qué agrega Kustomize al nombre de un ConfigMap generado, y cómo eso convierte un cambio de contenido en un *rollout*?
5. ¿Por qué, al volver a la lista original en 4.7, el ConfigMap salió `unchanged` y no `created`?
6. ¿Qué diferencia hay entre codificar y cifrar? ¿Qué es base64?
7. ¿Quién puede leer un Secret en un clúster, además de quien tiene permiso de `get secrets`?
8. ¿Qué hace `fsGroup` con el archivo de un Secret montado, y qué pasó al quitarlo?
9. ¿Por qué el error del `fsGroup` dejó el servicio sin réplicas y el de la llave mal escrita no?
10. ¿Qué no se puede hacer con un Secret inmutable, y cómo se cambia entonces su contenido?

## Fuentes

Todas consultadas el 21 de octubre de 2026.

- [Kubernetes, «ConfigMaps»](https://kubernetes.io/docs/concepts/configuration/configmap/): la definición; que no ofrece secreto ni cifrado; el tope de 1 MiB; las cuatro formas de usarlo desde un Pod; que los ConfigMaps montados como archivo se actualizan «eventualmente» y los usados como variables «no se actualizan automáticamente y requieren reiniciar el Pod»; y los ConfigMaps inmutables.
- [Kubernetes, «Configure a Pod to Use a ConfigMap»](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/): `configMapKeyRef`, `envFrom` y las referencias opcionales.
- [Kubernetes, «Secrets»](https://kubernetes.io/docs/concepts/configuration/secret/): la definición; el aviso de que se guardan sin cifrar en etcd y de que quien puede crear un Pod puede leer los Secrets de su espacio de nombres; el tope de 1 MiB; la actualización «eventualmente consistente» de los volúmenes; la copia en `tmpfs` en el nodo; y los Secrets inmutables, sus dos ventajas y que la marca no se puede revertir.
- [Kubernetes, «Good practices for Kubernetes Secrets»](https://kubernetes.io/docs/concepts/security/secrets-good-practices/): el cifrado en reposo; el acceso mínimo; que base64 no es un método de cifrado; que un manifiesto de Secret en un repositorio expone el secreto; y que la aplicación no debe registrar el dato en claro.
- [Kubernetes, «Distribute Credentials Securely Using Secrets»](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/): `defaultMode` y su valor por omisión, `0644`.
- [Kubernetes, «Declarative Management of Kubernetes Objects Using Kustomize»](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): Kustomize dentro de `kubectl` desde la 1.14; `configMapGenerator` y `secretGenerator`; el sufijo con el *hash* del contenido y `generatorOptions` con `disableNameSuffixHash`.
- [Kubernetes, «Configure a Security Context for a Pod or Container»](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` como grupo adicional de los procesos y como dueño de los volúmenes que admiten administración de dueños.
- [Kubernetes, «Deployments»](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `minReadySeconds` y cuándo un Pod nuevo cuenta como disponible.
- [Kubernetes, «Pod Lifecycle»](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): la espera creciente entre reinicios (10 s, 20 s, 40 s… hasta 300 s) y el estado `CrashLoopBackOff`.

---

**Siguiente:** [Lección 5 — Salud, recursos y apagado ordenado](05-salud-recursos-apagado.md)
