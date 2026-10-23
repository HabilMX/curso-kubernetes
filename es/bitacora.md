# Bitácora

Esto es tuyo. Es lo que vuelve el curso *tu* curso.

**Qué anotar:** lo que no entendiste a la primera · el estado o el error del clúster que no supiste leer · lo que creías de Kubernetes y resultó distinto · lo que te sorprendió · los números que mediste (tiempos, réplicas).

**Por qué importa:** en dos semanas no vas a recordar qué te costó. Y lo que te costó es exactamente lo que hay que repasar.

---

## Lección 0 — Qué es Kubernetes y qué NO es kind

_fecha:_

- Con mis palabras, qué hace un Deployment:
- La pieza de Docker que no encontré equivalente directo en Kubernetes:
- Lo que me sorprendió:

## Lección 1 — Instalar kubectl y kind; tu primer clúster

_fecha:_

- Versiones que me salieron (`kubectl version --client`, `kind version`):
- Qué contexto estaba activo antes y después de crear el clúster:
- Tiempo en crear el clúster: ____ s. En borrarlo y recrearlo: ____ s

## Lección 2 — Pods y Deployments

_fecha:_

- El `ErrImagePull` que provoqué y qué decía `describe pod`:
- Qué hice para que la imagen cargada se usara de verdad:
- Qué me rechazó el clúster de mi `securityContext` y por qué:

## Lección 3 — Services y DNS

_fecha:_

- Un Service que no tenía endpoints y por qué:
- Los tres puertos de mi cadena (`port`, `targetPort`, `containerPort`) y quién es quién:

## Lección 4 — Configuración y secretos

_fecha:_

- Lo que vi al decodificar mi `Secret`:
- Qué pasó con los Pods cuando cambié el `ConfigMap` por variable y cuando lo cambié por archivo:
- Con Kustomize, cuánto tardó el rollout:

## Lección 5 — Salud, recursos y apagado ordenado

_fecha:_

- Una sonda que rompí a propósito y qué estado vi:
- Un `OOMKilled` o un `Pending`: cómo lo leí en `describe`:
- Segundos que tarda en apagarse un Pod de mi `revisor`: ____

## Lección 6 — Entrar al clúster

_fecha:_

- Cómo llegué desde mi navegador al `revisor` y por dónde pasó la petición:
- Qué me falta para que esa puerta sea segura de verdad:

## Lección 7 — Aislar: espacios, permisos y red

_fecha:_

- Un manifiesto que el nivel `restricted` me rechazó y qué le faltaba:
- Un `kubectl auth can-i` que me sorprendió:
- Qué dejó de funcionar al cerrar la red y qué abrí para recuperarlo:

## Lección 8 — Datos y tareas

_fecha:_

- Qué se perdió y qué no al borrar el Pod con y sin volumen:
- Cuántas veces corrió mi `CronJob` y cómo lo comprobé:

## Lección 9 — Escalar y actualizar, midiendo cada corte

_fecha:_

- El `<unknown>` del HPA: por qué salió y cómo lo resolví:
- Réplicas al subir la carga: ____ → al bajarla: ____ ; tiempo de bajada: ____ min
- Qué pasó cuando actualicé con una imagen rota y cómo regresé:

## Lección 10 — El proyecto terminado y qué cambia en un clúster real

_fecha:_

- Las cinco cosas por las que mi clúster no es producción:
- La que más me preocuparía primero y por qué:

---

## Lo que quiero construir después

_La lista de cosas que se te ocurran mientras avanzas. Es la mejor señal de que el curso funcionó._

-
