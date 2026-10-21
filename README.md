# Curso de Kubernetes con kind — despliega, configura, escala y protege un servicio en tu propia máquina

**Por Dorian Chávez, fundador de Hábil y arquitecto de integración.**

**Cada manifiesto de este curso trae su salida esperada y se aplica a un clúster real de `kind` para comprobarla.**

> El curso se escribe primero en español. Las traducciones (inglés, francés, portugués de Brasil y búlgaro) llegan después, con su propio registro.

## Dónde está el contenido

- **[Español — el curso completo](es/README.md)** ← empieza aquí

## Para quién es

Quien ya hizo el [**curso de Docker**](https://www.habil.mx/es/cursos/docker/) de esta casa, o quien ya empaqueta servicios en contenedores con soltura: sabes construir una imagen, correrla, darle un volumen y levantar varias con Compose. Nivel intermedio. No se supone que hayas tocado Kubernetes ni que tengas un clúster: el curso te da uno, local, que se crea y se destruye en minutos.

Si nunca has usado Docker, empieza por el [curso de Docker](https://www.habil.mx/es/cursos/docker/): este curso toma como punto de partida la imagen que ese curso construye y no la vuelve a explicar.

## El proyecto que crece

El **`revisor`**, el mismo de los cursos de [Go](https://www.habil.mx/es/cursos/go/), [Rust](https://www.habil.mx/es/cursos/rust/), [TypeScript](https://www.habil.mx/es/cursos/typescript/) y [Docker](https://www.habil.mx/es/cursos/docker/) de esta casa: un servidor HTTP que consulta una lista de servicios **a la vez** y entrega un reporte. Es el servidor en Go que el curso de Docker empaqueta (puerto 8080, `GET /salud`, `GET /api/estados`, configuración por variables de entorno y un subcomando `healthcheck`). Llega aquí como una imagen ya construida; el trabajo de este curso es **hacerlo vivir en un clúster**: que renazca si se cae, que se encuentre por nombre, que se configure sin reconstruirse, que se publique hacia afuera, que tenga permisos mínimos, que guarde su reporte, que corra también como tarea programada y que escale cuando hay carga. Al final todo se levanta con dos `kubectl apply -k` —la plataforma y el proyecto— y una espera entre los dos.

Se repite el proyecto y no se inventa otro porque ves el mismo problema resuelto con otra herramienta, y de esa comparación se aprende más que de empezar de nuevo. Lo que cambia es dónde y cómo corre, no qué hace.

## Las lecciones

Numeración única y continua: «Lección N», de la 0 a la 10.

| # | Lección | Qué construyes | Qué aprendes |
|---|---|---|---|
| 0 | Qué es Kubernetes y qué NO es kind | nada todavía (lectura) | el plano de control y los nodos; declarar el estado deseado y dejar que el clúster lo alcance; el mapa de Docker a Kubernetes; qué prueba kind y qué no |
| 1 | Instalar kubectl y kind; tu primer clúster | el clúster del curso: un nodo de control y dos de trabajo | kubectl y kind con versión fijada y suma de verificación; el ajuste de `inotify`; contextos y `kubeconfig`; crear, mirar, borrar y recrear |
| 2 | Pods y Deployments | el `revisor` corriendo, con réplicas que renacen | `kind load docker-image`; el `ErrImagePull` que se provoca a propósito; Pod, ReplicaSet, Deployment; etiquetas; `rollout`; `securityContext` desde el primer manifiesto |
| 3 | Services y DNS | el `revisor` encontrable por nombre | `ClusterIP`; selectores y `EndpointSlice`; `port`, `targetPort` y `containerPort`; DNS del clúster; `port-forward`; un Pod de depuración |
| 4 | Configuración y secretos | el `revisor` configurado sin reconstruir | `ConfigMap` como variables de entorno (el `revisor` solo lee variables) y `Secret` como archivo (por qué base64 no es cifrado); Kustomize con generadores y el *hash* que dispara el rollout |
| 5 | Salud, recursos y apagado ordenado | un `revisor` que el clúster sabe vigilar | sondas de arranque, de disponibilidad y de vida; por qué `/salud` no consulta a nadie; `requests` y `limits`; `OOMKilled` y `Pending` a propósito; `terminationGracePeriodSeconds` |
| 6 | Entrar al clúster | el `revisor` publicado hacia afuera | `LoadBalancer` con MetalLB y Gateway API con Envoy Gateway, instalados dentro del clúster; por qué no Cloud Provider KIND en una máquina compartida (actúa sobre todos los clústeres de kind); `Ingress` como API congelada; por qué no `ingress-nginx`; qué se expone y por dónde |
| 7 | Aislar: espacios, permisos y red | un espacio de nombres propio con reglas | `Namespace`; Pod Security Admission en nivel `restricted`; `ServiceAccount` y RBAC mínimo con `auth can-i`; `NetworkPolicy` de «todo cerrado» y las aperturas necesarias (si el CNI de kind no la aplica, el curso instala Calico y lo dice) |
| 8 | Datos y tareas | el reporte guardado y el `revisor` como tarea programada | `PersistentVolumeClaim` y la clase de almacenamiento de kind; `Job` y `CronJob`; el dueño de los archivos con `fsGroup`; qué se pierde al borrar un Pod |
| 9 | Escalar y actualizar sin cortes | el `revisor` que sube y baja réplicas con la carga | `metrics-server`; `HorizontalPodAutoscaler` y su fórmula; la ventana de bajada; `RollingUpdate`; `PodDisruptionBudget`; `rollout undo` |
| 10 | El proyecto terminado y qué cambia en un clúster real | todo con dos `kubectl apply -k` (plataforma y proyecto) y una espera | Kustomize con base y *overlays*; revisión contra el nivel `restricted`; Helm como mención; qué le falta a esto para ser producción |

Lo que la tabla promete por lección es lo que la lección trae.

## Dos criterios que atraviesan todo el curso

**La seguridad no es una lección, es una costumbre.** La lección 7 junta los permisos y la red porque ahí se estudian por sí mismos, pero el resto del curso ya los practica desde el primer manifiesto:

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
| 9 | límites al escalado; las actualizaciones no tumban el servicio |
| 10 | revisión final contra el nivel `restricted` y lista de lo que un clúster real exige |

**Solo se enseña lo vigente, y lo que se retiró se nombra para reconocerlo.** `ingress-nginx` dejó de recibir mantenimiento en marzo de 2026 y los tutoriales de hace dos años todavía lo enseñan; `Ingress` es una API congelada y Gateway API es su sucesora. El curso dice cuál es cuál. Y cada versión se da con su fecha: las de este curso se midieron el 7 de octubre de 2026 (Kubernetes 1.37.1; kind v0.33.0, cuyo nodo por defecto es 1.37.0). Lo que depende de una pieza externa (MetalLB, Envoy Gateway, la aplicación de `NetworkPolicy`, `metrics-server` en kind) se verifica en vivo al escribir cada lección y no se afirma antes.

## La plantilla de cada lección

Igual en todas:

1. **Encabezado:** «Lección N — título», tiempo (90 min o 2 × 45) y «Al terminar vas a poder…» (3 a 7 objetivos).
2. **El porqué antes del cómo:** qué problema resuelve el concepto, con un ejemplo del `revisor`.
3. **Los conceptos**, uno por sección: explicación, manifiesto mínimo aplicable y manifiesto en el `revisor`.
4. **El error que vas a ver:** el estado o el mensaje real del clúster (`ImagePullBackOff`, `Pending`, `CrashLoopBackOff`…), qué significa y cómo se lee con `describe`. Primero se provoca, después se corrige.
5. **El hábito de seguridad de la lección:** qué se endurece aquí y qué evita.
6. **Lo que se hace mal** (antipatrones), con el porqué.
7. **Ejercicios** (2 a 4), de menor a mayor, con sus **soluciones** aparte.
8. **Cómo sé que lo logré:** medible; tal comando da tal salida.
9. **Fuentes:** documentación oficial y especificaciones, con enlace.

## Cómo se organizan los programas

Cada programa es una carpeta `programas/NN-nombre/` con los manifiestos que la lección construye, una forma de aplicarlos y comprobarlos de principio a fin y su salida esperada. Como las salidas de Kubernetes cambian en cada corrida (sufijos aleatorios en los nombres de los Pods, edades, direcciones IP), la lección marca cuáles líneas son estables y solo esas se comparan. Los programas que a propósito fallan traen el estado o el mensaje que la lección enseña a leer. **Las lecciones son la fuente:** los programas se extraen de sus bloques de código.

## La profundidad se mide

Cada lección tiene al menos 3,000 palabras de explicación (lo que está fuera de los bloques de código), con piso de 3,000 por lección y mediana del curso de 4,000, como las de los cursos de Go, Rust y TypeScript. Se cuentan palabras y no líneas porque las líneas se inflan.

## Qué es un programa y qué es un fragmento

**No todo bloque de código de este curso es un programa completo.** Un **programa** se aplica solo, de principio a fin: vive en su carpeta de `programas/` y trae su corrida real (el comando y la salida). Cada uno se comprueba contra un clúster de verdad. Un **fragmento** es una ilustración (cuatro líneas de un manifiesto para explicar un campo, por ejemplo) que no pretende aplicarse por sí sola, y por eso no se verifica; se reconoce porque su bloque no está marcado como programa.

## Lo que este curso NO es

Un curso de producción. Un clúster de `kind` es para aprender y para probar: sus nodos son contenedores en tu máquina, no tiene balanceador de carga real, ni discos confiables, ni alta disponibilidad. La lección 10 termina diciéndote, de frente, qué le falta a lo que construiste para correr de verdad.

## Reglas del repositorio

- **Licencia CC BY-SA 4.0:** el material es público y se puede reusar citando la fuente.
- **Multiidioma:** `es/` es el original; las traducciones se agregan después en carpetas hermanas.
- Los secretos que aparecen en el curso son de mentira, generados para el ejercicio, y nunca de un servicio real.
- Sin emojis en los títulos de las lecciones.
