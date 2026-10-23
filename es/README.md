# Curso de Kubernetes con kind — despliega, configura, escala y protege un servicio en tu propia máquina

**Por Dorian Chávez, fundador de Hábil y arquitecto de integración.**

**Para quién es:** quien ya llevó el [curso de Docker](https://www.habil.mx/es/cursos/docker/) de esta casa, o quien empaqueta servicios en contenedores con soltura: construyes imágenes, las corres, les das volúmenes y las levantas juntas con Compose. Nivel intermedio. No se supone que hayas tocado Kubernetes ni que tengas un clúster: el curso te da uno, local, que se crea y se destruye en minutos. Cada concepto se explica cuando aparece, y se explica por qué existe, no solo cómo se escribe.

**Qué vas a terminar sabiendo:** desplegar un servicio en un clúster de Kubernetes y operarlo —configurarlo, vigilarlo, publicarlo, limitarlo, guardarle sus datos, escalarlo y actualizarlo midiendo cada corte—; leer lo que el clúster te dice cuando algo falla (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) en vez de borrar y volver a intentar; y explicar, sin adornos, qué distancia hay entre tu clúster local y uno de producción.

**Dónde viene de:** este curso continúa el de [**Docker**](https://www.habil.mx/es/cursos/docker/) de esta casa y usa como punto de partida su imagen terminada del `revisor`. Si no hiciste ese curso, necesitas una imagen de un servicio HTTP que sepa decir si está vivo y que corra sin ser `root`; la [Lección 2](02-pods-deployments.md) te dice exactamente qué debe cumplir.

**Lo que necesitas antes de empezar:** una computadora con Linux Mint 22.x, Docker Engine funcionando y permiso de administrador (`sudo`). La [Lección 1](01-instalacion-primer-cluster.md) instala `kubectl` y `kind` y crea el clúster.

## El proyecto que vas a construir

El **`revisor`**: el servidor HTTP que consulta una lista de servicios **a la vez** y entrega su reporte, el mismo de los cursos de [Go](https://www.habil.mx/es/cursos/go/), [Rust](https://www.habil.mx/es/cursos/rust/), [TypeScript](https://www.habil.mx/es/cursos/typescript/) y [Docker](https://www.habil.mx/es/cursos/docker/) de esta casa; su servidor está escrito en Go y atiende en el puerto 8080 (`GET /salud`, `GET /api/estados`, configuración por variables de entorno, subcomando `healthcheck`). Aquí ya no lo programas ni lo empaquetas: lo **haces vivir en un clúster**. Lo despliegas con varias réplicas, lo vuelves encontrable por nombre, lo configuras sin reconstruir la imagen, le enseñas al clúster a vigilarlo, lo publicas hacia afuera, lo aíslas con permisos mínimos y una red cerrada, le das un lugar donde guardar su reporte, lo conviertes en tarea programada y haces que escale con la carga. Al final todo se levanta con dos `kubectl apply -k` —la plataforma y el proyecto— y una espera entre los dos.

Va acompañado del **servicio de prueba que falla a propósito** del curso de Docker (sano, lento o caído), porque un clúster se entiende de verdad cuando algo se rompe y ves qué hace.

## Las once lecciones

| Lección | | Qué construyes | Qué aprendes |
|---|---|---|---|
| 0 | [Qué es Kubernetes y qué NO es kind](00-que-es-kubernetes.md) | nada todavía (lectura) | el plano de control y los nodos; declarar el estado deseado y dejar que el clúster lo alcance; el mapa de Docker a Kubernetes; qué prueba kind y qué no |
| 1 | [Instalar kubectl y kind; tu primer clúster](01-instalacion-primer-cluster.md) | el clúster del curso: un nodo de control y dos de trabajo | `kubectl` y `kind` con versión fijada y suma de verificación; el ajuste de `inotify`; contextos y `kubeconfig`; crear, mirar, borrar y recrear |
| 2 | [Pods y Deployments](02-pods-deployments.md) | el `revisor` corriendo, con réplicas que renacen | `kind load docker-image`; el `ErrImagePull` que se provoca a propósito; Pod, ReplicaSet y Deployment; etiquetas; `rollout`; `securityContext` desde el primer manifiesto |
| 3 | [Services y DNS](03-services-dns.md) | el `revisor` encontrable por nombre | `ClusterIP`; selectores y `EndpointSlice`; `port`, `targetPort` y `containerPort`; el DNS del clúster; `port-forward`; un Pod de depuración |
| 4 | [Configuración y secretos](04-configuracion-secretos.md) | el `revisor` configurado sin reconstruir | `ConfigMap` como variables de entorno (el `revisor` solo lee variables) y `Secret` como archivo, y por qué base64 no es cifrado; Kustomize con generadores y el *hash* que dispara el rollout |
| 5 | [Salud, recursos y apagado ordenado](05-salud-recursos-apagado.md) | un `revisor` que el clúster sabe vigilar | sondas de arranque, de disponibilidad y de vida; por qué `/salud` no consulta a nadie; `requests` y `limits`; `OOMKilled` y `Pending` a propósito; el plazo de apagado |
| 6 | [Entrar al clúster](06-entrar-al-cluster.md) | el `revisor` publicado hacia afuera | `LoadBalancer` con MetalLB y Gateway API con Envoy Gateway, instalados dentro del clúster; por qué no Cloud Provider KIND en una máquina compartida (actúa sobre todos los clústeres de kind); `Ingress` como API congelada; por qué no `ingress-nginx`; qué se expone y por dónde |
| 7 | [Aislar: espacios, permisos y red](07-aislar-permisos-red.md) | un espacio de nombres propio con reglas | `Namespace`; Pod Security Admission en nivel `restricted`; `ServiceAccount` y RBAC mínimo con `auth can-i`; `NetworkPolicy` de «todo cerrado» y sus aperturas (se mide que kindnet, el CNI que trae kind, las aplica; no hace falta instalar otro) |
| 8 | [Datos y tareas](08-datos-y-tareas.md) | el reporte guardado y el `revisor` como tarea programada | `PersistentVolumeClaim` y la clase de almacenamiento de kind; `Job` y `CronJob`; el dueño de los archivos con `fsGroup`; qué se pierde al borrar un Pod |
| 9 | [Escalar y actualizar, midiendo cada corte](09-escalar-y-actualizar.md) | el `revisor` que sube y baja réplicas con la carga | `metrics-server`; `HorizontalPodAutoscaler` y su fórmula; la ventana de bajada; reparto con `topologySpreadConstraints`; `RollingUpdate` y `preStop` medidos con un sondeo; `rollout undo`; `PodDisruptionBudget` y `drain`; la ventana de un nodo caído |
| 10 | [El proyecto terminado y qué cambia en un clúster real](10-proyecto-final.md) | todo con dos `kubectl apply -k` (plataforma y proyecto) y una espera | Kustomize con base y *overlays*; revisión contra el nivel `restricted`; Helm como mención; qué le falta a esto para ser producción |

Al final de cada lección hay ejercicios con sus soluciones. Y la [bitácora](bitacora.md) es tuya: anota ahí lo que te costó.

## Tres criterios que atraviesan todo el curso

**La seguridad no es una lección, es una costumbre.** La lección 7 junta permisos, espacios y red porque ahí se estudian por sí mismos, pero el resto del curso ya los practica desde el primer manifiesto:

| Lección | El hábito que se instala |
|---|---|
| 0 | saber qué defiende un clúster local y qué no |
| 1 | binarios con suma de verificación; la imagen del nodo fijada; comprobar el contexto antes de cada comando que cambia algo |
| 2 | `securityContext` en el primer Deployment: sin `root`, sin escalada de privilegios, sin capacidades, sistema de archivos de solo lectura, perfil `seccomp` |
| 3 | por defecto `ClusterIP`; nada se publica porque sí; `port-forward` solo hacia `127.0.0.1` |
| 4 | un `Secret` no es cifrado: no se versiona, se monta como archivo y se marca inmutable |
| 5 | `requests` y `limits` en todo contenedor; las sondas no dependen de servicios ajenos |
| 6 | se expone lo mínimo, por una puerta nombrada, y se dice qué falta (cifrado en tránsito) |
| 7 | espacio propio, nivel `restricted`, permisos mínimos, red cerrada por defecto |
| 8 | el `ServiceAccount` sin credenciales montadas si no las necesita; los datos con su dueño |
| 9 | límites al escalado; las actualizaciones mantienen el servicio arriba, con las pocas fallas medidas y explicadas |
| 10 | revisión final contra el nivel `restricted` y la lista de lo que un clúster real exige |

**Se lee antes de borrar.** Cuando algo no arranca, el reflejo del principiante es borrarlo y volver a aplicarlo. Aquí el reflejo es otro: `describe`, `logs`, `get events`. Cada lección provoca a propósito un fallo típico y te enseña el orden para leerlo, porque ese orden es el oficio.

**Solo se enseña lo vigente, y lo que se retiró se nombra para reconocerlo.** `ingress-nginx` dejó de recibir mantenimiento en marzo de 2026 y los tutoriales de hace dos años todavía lo enseñan; `Ingress` es una API congelada y Gateway API es su sucesora. El curso dice cuál es cuál. Y cada versión se da con su fecha: las de este curso se midieron el 7 de octubre de 2026 (Kubernetes 1.37.1; kind v0.33.0, cuyo nodo por defecto es 1.37.0). Lo que depende de una pieza externa (MetalLB, Envoy Gateway, la aplicación de `NetworkPolicy`, `metrics-server` en kind) se verifica en vivo al escribir cada lección y no se afirma antes.

## Cómo sabes que terminaste

El curso no se acaba cuando leíste la lección 10, sino cuando tu proyecto cumple estas siete cosas. Son metas de diseño: se miden y se ajustan al escribir las lecciones, y cada lección repite la que le toca ya medida.

1. **Desde un clúster recién creado, el `revisor` queda funcionando en tres pasos, siempre en el mismo orden:** un `kubectl apply -k` de la plataforma (MetalLB y Envoy Gateway, con sus CRD), un `kubectl wait` hasta que esté lista y el `kubectl apply -k` del proyecto. Hay orden porque los CRD y los *webhooks* tienen que existir antes que los recursos que los usan. Y `kind delete cluster` seguido de los mismos tres pasos lo reconstruye sin que corrijas nada a mano.
2. **El espacio de nombres del `revisor` está en el nivel `restricted`** de Pod Security Admission y no recibe ni una advertencia al aplicar.
3. **Detienes el contenedor de un nodo de trabajo** (`docker stop`) y el servicio sigue respondiendo con la réplica del otro nodo, **con una ventana medida**: durante decenas de segundos —lo que tarda el clúster en dar el nodo por perdido (`node-monitor-grace-period`, 50 s por omisión): en las cuatro rondas de la lección 10 el servicio volvió a responder entre 34 y 51 s después de detener el nodo, y en la lección 9 el nodo pasó a `NotReady` a los 57 s— fallan las peticiones que caen en la réplica muerta (medido en una ronda, con 2 réplicas: 7 de 42 peticiones fallaron, y la última falla cayó 53 s después del apagado). Sabes decir qué acorta o suaviza esa ventana (más réplicas repartidas, reintentos en el cliente, un plazo de detección menor en el plano de control) y qué no (las sondas, que las corre el propio nodo caído, ni `tolerationSeconds`, que solo decide cuándo se reponen los Pods). Y una actualización con `preStop` reduce los cortes pero no los garantiza en cero: en cuatro rondas midió 0, 4, 0 y 1 fallas, 5 de 2,049 peticiones en total, contra 29 de 1,569 sin `preStop` en tres rondas (medido desde dentro del clúster, por el Service y `kube-proxy`, no por la puerta de entrada; con cuatro hilos de `curl` en una máquina compartida y sin alternar las rondas). Cuando levantas el nodo, el clúster se recompone solo.
4. **Cambias la lista de servicios en el `ConfigMap`** y el clúster hace el rollout por sí solo, sin que reconstruyas la imagen.
5. **Con carga, `kubectl get hpa --watch` muestra las réplicas subir, y minutos después bajar**, y puedes explicar por qué la bajada tarda lo que tarda.
6. **Un Pod ajeno al `revisor` no puede hablarle** (la `NetworkPolicy` lo corta; meta sujeta a que el clúster la aplique) y la cuenta de servicio del `revisor` **no puede hacer nada que no necesite** (`kubectl auth can-i` te lo demuestra).
7. **Sabes decir, por escrito, cinco cosas por las que lo que construiste no es producción**, y qué se haría con cada una en un clúster real.
