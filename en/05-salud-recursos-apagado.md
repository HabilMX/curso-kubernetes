# Lesson 5 — Health checks, resources and graceful shutdown

Thursday, 6:40 in the evening. The test service has been down for ten minutes and the dashboard says so correctly: `FALLA codigo 503`. That is what the `revisor` exists for. But at 6:42 the dashboard stops loading. You ask for the Pods and see something you did not expect: the `revisor`'s three replicas have `RESTARTS 4`, `RESTARTS 5`, `RESTARTS 5`, and two of them say `CrashLoopBackOff`. Nobody touched the `revisor`. What someone did touch, on Tuesday, was its health check: "to make it more complete", they asked it to also ask about the test service. Now the test service is down, the `revisor`'s check fails, the cluster concludes that the `revisor` is dead and restarts it, over and over. The tool that was supposed to warn you about the problem is the problem's first victim. And at 7:00 you have to explain what happened.

The cluster did not make a mistake: it did exactly what it was told. This lesson teaches you to tell it the right thing. How the cluster knows that a container has started, that it can receive traffic, and that it is still alive, and why those three questions are different. How much CPU and memory each container gets, and what happens when it asks for too much. And what the `revisor` does in the seconds the cluster gives it when it asks it to shut down.

**Time:** 2 × 45 min

**What you build:** a `revisor` that the cluster knows how to watch: with startup, readiness, and liveness probes, with a floor and a ceiling for CPU and memory, and with a shutdown timeout made to measure; and the test service with its own probe and its own limits

**What you learn:** what each probe asks (`startupProbe`, `readinessProbe`, `livenessProbe`), who runs it, and what happens when it fails; why `/salud` queries nobody; what `requests` and `limits` are, who uses each one, and in which units they are written; the quality-of-service classes; an `OOMKilled` and a `Pending` provoked on purpose and how to read them; and what happens between `kubectl delete pod` and the Pod disappearing, with `terminationGracePeriodSeconds`

**Where you are coming from.** From [Lesson 4](04-configuracion-secretos.md): the `revisor` and the test service are applied with `kubectl apply -k .`; the list of services comes from a generated `ConfigMap` and the token from a `Secret` mounted as a file, and `/api/estados` asks for `Authorization: Bearer …`. From [Lesson 3](03-services-dns.md) you bring the `depurar` Pod, the EndpointSlices and their `ready` column, which section 3.4.3 left pending for this lesson. And from [Lesson 2](02-pods-deployments.md), that each node's `kubelet` is the one that starts containers.

**What this lesson does not do.** It does not spread the replicas across nodes or make an update lose no requests: that is [Lesson 9](09-escalar-y-actualizar.md), with `preStop`, `PodDisruptionBudget`, and autoscaling, which uses today's `requests` to calculate. It does not publish the `revisor` to the outside: that is [Lesson 6](06-entrar-al-cluster.md). And it does not set rules for a whole namespace (a maximum per container, a total per team): they are named in the lesson's security habit and are left outside the course.

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1, and the node image `kindest/node:v1.37.0` pinned by its digest, in the three-node cluster from Lesson 1, here called `curso-k8s-l5`. The machine was a Mac with an ARM processor and Docker Engine 29.2.1 inside a Linux virtual machine (Colima) with 6 CPUs and 16 GiB of memory, **not** Linux Mint, which is the course's reference system. What changes on your Mint: the architecture (`amd64` instead of `arm64`); the CPU and memory each node says it has, which in kind are those of your machine (5.6 explains it), and with them the percentages in `describe node`; the IP addresses, the random suffixes of names, the ages, which node each replica lands on, the time in the log, and the exact memory the `revisor` uses. The commands are the same. The complete walkthrough is in [`programas/05-salud-recursos-apagado/`](../programas/05-salud-recursos-apagado): `correr.sh` creates the cluster, loads the images into it, leaves everything as Lesson 4 left it, walks through the lesson in order, runs Exercises 1 to 3, and deletes the cluster. The complete run took 4 minutes and 48 seconds, and the script records how long each long step took: creating the cluster and waiting for it to be ready, 34 seconds; deleting it, 1. Its output is `correr.salida.txt`. In it, the nodes' capacity (5.6) and the error on purpose appear before the shutdown (5.7), and the security habit before the exercises, because the script runs them in that order. It uses no port on your machine.

## By the end you will be able to

- Explain with an example the difference between "it started", "it is ready", and "it is alive", and say which probe asks each thing and what the cluster does when the answer is "no".
- Write the `revisor`'s three probes and calculate, with their numbers, how long the cluster takes to react to each failure.
- Justify why the liveness probe must not ask about other services, and demonstrate it with the test service down.
- Write `requests` and `limits` in millicores and mebibytes, and say who uses each one: the scheduler, the `kubelet`, or the Linux kernel.
- Provoke an `OOMKilled` and a `Pending`, read them with `kubectl get`, `describe`, and the events, and fix them.
- Measure how long a Pod takes to shut down and explain the role of SIGTERM, SIGKILL, and `terminationGracePeriodSeconds`.

## The why before the how

Until today, the cluster knows one single thing about your containers: whether the process is running. If the process dies, the `kubelet` restarts it; you saw that in Lesson 2. But a process can be running and not serve. It can still be starting up, not yet listening on its port. It can be stuck in a deadlock, alive to the operating system and dead to its clients. It can be healthy and still not want traffic for a moment. For the cluster, today, the three cases are the same: `Running`. And Lesson 3's Service sends traffic to all three.

The lesson's first question is, then, **how does a container tell the cluster how it is doing?** The answer is **probes**: questions the `kubelet` asks the container every so often. There are three, because there are three different questions, and each negative answer has a different consequence: wait, stop sending it traffic, or restart it. Confusing them is Thursday's scene.

The second question is **how much does each one get?** Today the `revisor` does not say how much CPU or memory it needs, and the cluster puts it wherever, without counting. A container with no ceiling can eat the memory of an entire node and take all its neighbors down with it. **`requests`** say how much it needs so the scheduler can find it a place; **`limits`** say how far it can go.

The third is **how does it leave?** Every time you delete a Pod, do a *rollout*, or the cluster moves something, a container receives the order to shut down. If it obeys, it finishes what it was doing and exits. If not, the cluster waits a timeout and kills it. That timeout is written in the manifest.

The lesson has seven concept parts and then the usual sections:

1. **The lesson's cluster and what it knows today** (5.1).
2. **The lesson's manifests** (5.2), field by field.
3. **The three probes** (5.3): what each asks and when it reacts.
4. **The probes, running** (5.4): apply, look, and read them in the log.
5. **Why `/salud` queries nobody** (5.5): Thursday's scene, in reverse.
6. **`requests`, `limits`, and the nodes' capacity** (5.6).
7. **The graceful shutdown** (5.7).

This is the destination. At the end of 5.4, each `revisor` replica has its three probes, its floor and its ceiling, and a shutdown timeout of 10 seconds:

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

## If you do not have the images from the Docker course

This lesson uses the same two images as Lesson 3: `curso-docker-revisor:1.6.0` and `curso-docker-prueba:1.0.0`. Check that you have them:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

For the other one, the same command with `curso-docker-prueba:1.0.0`. If you are missing either, [Lesson 3](03-services-dns.md) says, in this same section, how to build each one from the Docker course's repository. What this lesson asks **in addition** of the two images, worth reading because each point explains a line of the manifests:

- **The `revisor` answers `GET /salud` without querying anyone**: it returns `{"estado":"vivo","version":"1.6.0"}` with code 200 as soon as it listens. The three probes ask there.
- **The `revisor` handles SIGTERM**: on receiving it, it writes `revisor: recibí terminated, apagando`, finishes the requests in progress with its own timeout of 5 seconds, and writes `revisor: apagado limpio`.
- **The test service always answers `GET /modo`**, in any mode, as long as the process lives. `GET /` is the one that answers 503 in `caido` mode. That difference decides where its probe asks.

The `curl` image of the `depurar` Pod is still public and pinned by its digest; each node downloads it from the internet the first time.

## The concepts

### 5.1 The lesson's cluster and what it knows today

#### 5.1.1 Creating the cluster

This lesson uses its own cluster, `curso-k8s-l5`, with the three-node configuration from Lesson 1. Create it like this, from the root of the course repository, with the usual care:

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

The `export` only holds in that terminal. That is why the temporary folder is saved in a variable, `L5_TMP`, and the `echo` shows you the full path: if you open another terminal (in 5.7 you will need a second one), there you repeat the `export` with **that** path, or `kubectl` will talk to another cluster. And at the end of the lesson, the same variable is what lets you delete the folder without typing the path by eye. And the rule from the earlier lessons still stands: **before every** `apply`, `delete`, `patch`, or `exec` in this lesson, `kubectl config current-context` must say `kind-curso-k8s-l5`. The script checks it on its own before each `kubectl` and stops if it does not match.

The outputs in this section are from the run of `correr.sh`, which does exactly that:

```text
$ kubectl config current-context
kind-curso-k8s-l5

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l5-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l5-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l5-worker2         Ready    <none>          15s   v1.37.0
```

`kind load` prints six `not yet present on node …, loading...` lines, two images times three nodes, as in Lesson 3.

#### 5.1.2 The starting point: what Lesson 4 left

The folder `programas/05-salud-recursos-apagado/punto-de-partida/` carries, without changing a comma, the manifests Lesson 4 ended with: its `kustomization.yaml`, the two Deployments, and the two Services. As in that lesson, the token is not versioned: it is generated on each run. This time it is copied to both folders, the starting point's and the lesson's, so both generate **the same** Secret:

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

Thirty-two hexadecimal characters and a line break: 33 bytes. As in Lesson 4, the parentheses and the `umask 077` make the file be born with permission `0600` (`-rw-------`), readable only by you, instead of the `0644` your usual mask would leave; `cp` without `-p` does not copy the original's permissions: it creates the new file with the original's mode filtered by your `umask`. Since `0600` has no permissions for group or others, the mask adds nothing to it and the copy also ends up `0600`; with a `0664` or `0755` file the result would depend on your `umask`, and `cp -p` is the option that preserves mode, owner, and dates. The first line of the block is the context check written as a command: if the context is not the lesson's, it prints "contexto equivocado" and does not continue. Use it before every change; the script does it on its own. The ConfigMap's name is the same as Lesson 4's, `revisor-config-t6cm6872fk`, because the list of services did not change. The Secret's is different on every run, because the token is new.

#### 5.1.3 What the cluster knows today

```text
$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6f4dfdb898-8p5j2   1/1     Running   0          4s
revisor-f65c6dd96-248bg   1/1     Running   0          4s
revisor-f65c6dd96-575nn   1/1     Running   0          4s
revisor-f65c6dd96-pzxpk   1/1     Running   0          4s
```

Look at the `READY` column: `1/1` at **4 seconds**. Was the `revisor` already listening on its port at that age? Surely yes, because it starts fast. But the cluster did not check: it marked the Pod ready as soon as the container started. It is what Lesson 3 anticipated in 3.4.3: without probes, "ready" means "the process exists". If the `revisor` took ten seconds to open its port, the Service would send it traffic during those ten seconds, and those requests would fail.

Now, what the Pod says about itself:

```text
$ kubectl describe pod revisor-f65c6dd96-248bg | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests'
Name:             revisor-f65c6dd96-248bg
QoS Class:                   BestEffort

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
30

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
PodReadyToStartContainers=True Initialized=True Ready=True ContainersReady=True PodScheduled=True 
```

The `grep` looked for probes, `Limits`, and `Requests`, and found none: only the name and one line, `QoS Class: BestEffort`. It is the Pod's quality-of-service class, and `BestEffort` ("whatever is possible") is what a Pod that declares nothing about CPU or memory receives. 5.6 explains what it means; a preview: it is the first one the node evicts when it runs out of memory. The shutdown timeout is `30` seconds, the default value, which nobody chose. And the Pod's conditions say `Ready=True`: it is the condition that the EndpointSlice copies into its `ready` column, and today it became true without anyone asking anything.

Three gaps: nobody checks that the `revisor` serves, nobody says how much it needs, and the shutdown timeout is an inherited number. All three are closed with this lesson's manifests.

### 5.2 The lesson's manifests

The lesson changes two files: the `revisor`'s and the test service's Deployments. The `kustomization.yaml`, the two Services, and `depurar.yaml` are the same as in Lesson 4 (the comment on the `kustomization.yaml`'s first line now says "Lecciones 4 y 5"). Both Deployments are **programs**: they are applied with `kubectl apply -k .` from `programas/05-salud-recursos-apagado/`.

#### 5.2.1 The `revisor`

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

Everything that is not new you already read in Lessons 2 to 4. What is new is three blocks and a number:

- **`terminationGracePeriodSeconds: 10`**, in the Pod template (not in the container): how many seconds the Pod has to shut down on its own before the cluster kills it. 5.7.
- **`resources`**, in the container: the floor (`requests`) and the ceiling (`limits`) of CPU and memory. 5.6.
- **`startupProbe`, `readinessProbe`, and `livenessProbe`**, in the container: the three probes. 5.3.

Notice the `port: http` in all three probes. It is the same trick as in Lesson 3 with the Service's `targetPort`: the port goes by **name**, so the number `8080` keeps living in a single place, `containerPort`. And `{path: /salud, port: http}` is one-line YAML: the braces group `httpGet`'s two fields just as if you wrote them on two indented lines. They are written like this because the three probes share the same question and what changes between them is the numbers.

#### 5.2.2 The test service

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

A single probe, the liveness one, and it points to `/modo`, **not** to `/`. The file's comment says so and 5.5 demonstrates it: `GET /` is exactly what the test service breaks on purpose in `caido` mode. If the liveness probe asked there, the cluster would restart it every time you put it in that mode, which is the opposite of what you want from a service that exists to fail. Exercise 2 tests it. It carries no startup probe because it starts in milliseconds, nor a readiness one because the course wants the `revisor` to be able to talk to it even when it is down; Exercise 1 shows you what would happen with one.

The resources are smaller than the `revisor`'s because it does less: it queries nobody and stores no reports.

### 5.3 The three probes

#### 5.3.1 Who asks and how

The [probes documentation](https://kubernetes.io/docs/concepts/workloads/pods/probes/) begins like this: a probe is "a diagnostic performed periodically by the kubelet on a container", and with its results "Kubernetes can restart unhealthy containers or stop sending traffic to containers that are not ready". Keep the two components: **the `kubelet`**, the one on the node where the Pod runs, not the control plane; and **two different reactions**, restart or stop sending traffic.

The `revisor`'s three probes use `httpGet`: the `kubelet` makes an HTTP request to the Pod's IP, at the port and path you tell it. The [guide to configuring probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) says when it counts as success: "any code greater than or equal to 200 and less than 400 indicates success. Any other code indicates failure". A response that does not arrive in time is also a failure. There are other ways to ask (running a command inside the container, opening a TCP connection, or a gRPC call), but for an HTTP server that already has its health route, the HTTP request is the one that asks what matters: not "does the process exist?", but "does it answer?". And the `revisor` has no *shell* to run commands inside, as you saw in Lesson 2.

#### 5.3.2 A probe's numbers

Each probe is tuned with five fields. The default values are from the same probes documentation:

| Field | What it is | Default |
|---|---|---|
| `initialDelaySeconds` | how long to wait before the first question | 0 s |
| `periodSeconds` | how often to ask | 10 s (minimum 1) |
| `timeoutSeconds` | how long to wait for an answer | 1 s |
| `successThreshold` | how many consecutive successes, after a failure, to go back to "fine" | 1 (for liveness and startup, it **must** be 1) |
| `failureThreshold` | how many consecutive failures to conclude "bad" | 3 |

The rule for reading them: **a probe reacts after `failureThreshold` consecutive failures, spaced `periodSeconds` apart**. A single failure does nothing. That keeps a one-second stumble from triggering a restart. The documentation puts it in these words: after a probe fails `failureThreshold` times in a row, "Kubernetes considers that the overall check has failed".

#### 5.3.3 The startup probe: "have you started yet?"

The probes documentation: startup probes "indicate whether the application within the container is started. All other probes are disabled if a startup probe is provided, until it succeeds". And if it fails altogether, "the kubelet kills the container", which is subject to its restart policy.

The `revisor`'s: `periodSeconds: 1` and `failureThreshold: 10`. It asks every second, and gives the program up to **10 attempts**, about 10 seconds, to answer the first time (1 × 10). That is the arithmetic when each attempt fails immediately; if the program is stuck and each attempt has to exhaust its `timeoutSeconds` (1 second by default), the window approaches 20. As soon as it answers, it stops asking for as long as that container lives; if the container restarts, it starts over. Unlike the other two, it only runs at startup. Why 10 seconds if the `revisor` starts in under one? Because the number is not for the good day, it is for the bad day: a loaded node, an image that reads slowly. And there is little to spare: a program that does not answer in 10 seconds has something wrong.

The guide to configuring probes explains what this probe exists for. Some programs take a long time to start, and if the liveness probe had to wait for them, it would have to be made slow and would stop detecting a deadlock in time. The solution is to separate: a startup probe with a `failureThreshold * periodSeconds` "long enough to cover the worst case startup time", and once it succeeds, "the liveness probe takes over". Its example is a program with up to 5 minutes to start (30 × 10 s). The `revisor` needs far less, but the pattern is the same.

#### 5.3.4 The readiness probe: "should I send you traffic?"

The documentation: readiness probes "determine when a container is ready to accept traffic", and if one fails, "the EndpointSlice controller removes the Pod's IP address from the EndpointSlices of all Services that match the Pod". It is Lesson 3's `ready` column, finally with content. A nuance you will see in Exercise 1: in practice, the address does not disappear from the EndpointSlice, but stays with `ready=false`, and that is enough for `kube-proxy` to stop sending it traffic. "Taking out of traffic" is the effect; "marking as not ready" is the mechanism. And something that sets it apart from the startup one: "readiness probes run on the container during its whole lifecycle".

The most important thing is what it does **not** do: it restarts nothing. The probes documentation, in the description of `failureThreshold`: with a failed readiness probe, "the kubelet continues running the container that failed and also continues to run more probes", and only sets the Pod's `Ready` condition to `false`. When the probe passes again, the Pod goes back on the list. It is the probe for "I'm fine, but not right now".

The `revisor`'s: every 5 seconds, and 2 consecutive failures take it out of the Service. In the worst case, a `revisor` that stops answering keeps receiving traffic for about **10 seconds** (2 × 5) before leaving the list.

#### 5.3.5 The liveness probe: "are you still alive?"

The documentation: liveness probes "determine when to restart a container". The example it gives is a deadlock, "where an application is running, but unable to make progress". If the container fails more times than tolerated, "the kubelet restarts that container".

It is the only one of the three that destroys something: a restart drops open connections and in-memory state. That is why the same page accompanies it with a warning, which is Thursday's scene in manual language: liveness probes "must be configured carefully to ensure that they truly indicate unrecoverable application failure", and "incorrect implementation of liveness probes can lead to cascading failures".

The `revisor`'s: every 10 seconds, and 3 consecutive failures restart it. A stuck `revisor` is restarted in about **30 seconds** (3 × 10). Slower than the readiness one on purpose: the documentation describes that pattern as the common one, the same cheap route for both and a higher `failureThreshold` on the liveness one, so the Pod looks "not ready" for a while before it is killed. That way, a passing stumble takes the Pod out of traffic (which is cheap) long before restarting it (which is expensive).

#### 5.3.6 The three together

| Probe | Question | If the answer is "no" | When it runs | In the `revisor` |
|---|---|---|---|---|
| startup | have you started yet? | waits; if the window runs out, restarts | only at startup | up to 10 s (1 s × 10) |
| readiness | should I send you traffic? | takes you out of the Service; does **not** restart | always | leaves in ~10 s (5 s × 2) |
| liveness | are you still alive? | **restarts** the container | always, after the startup one | restarts in ~30 s (10 s × 3) |

The `revisor`'s three ask the same thing, `GET /salud`. It is not redundancy: it is the same question with three consequences and three different levels of patience.

### 5.4 The probes, running

#### 5.4.1 Before applying, look at what changes

First it is checked that both folders have the same token, and then the cluster is asked what would change:

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

`kubectl diff -k .` compares what you would apply with what is there; the two `grep`s keep the lines that are **added** (they start with `+ `) and remove those that always change. First comes the test Deployment, then the `revisor`'s. Notice three things. No ConfigMap or Secret appears: the token is the same and so is the list, so their names with *hash* do not change. The fields you did not write (`scheme: HTTP`, `successThreshold: 1`, `timeoutSeconds: 1`) appear with their default value, the one in the table in 5.3.2: that is how you see what is really going to run. And exit code 1 is not an error: `kubectl diff` exits with 1 when there **are** differences, and with 0 when there are none. At the end of the lesson you will use it the other way around, to check that none is left.

About that last line, `[código de salida: 1]`: `kubectl` does not write it, the script writes it every time a command exits with a code other than 0, and you will see it in other blocks of the lesson. The script runs with `set -o pipefail`, so a pipeline's code is that of the first command that fails, here `kubectl diff`. In your terminal, without that option, `echo $?` would give you the code of the last `grep`, which is 0. To check it without a pipeline: `kubectl diff -k . >/dev/null; echo $?`, which gives `1`.

#### 5.4.2 Applying

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

Only the two Deployments change, and changing a Pod's template is a *rollout*: a new ReplicaSet (`revisor-578c8dc8d9`) that replaces the replicas one by one. The ages tell it: 12, 11, and 9 seconds, a second or two apart. And this time the replacement waited for each new replica to pass its readiness probe before removing an old one: a Deployment only counts a ready Pod as "available". Without probes, "ready" arrived before knowing anything.

The `describe` of one of the new replicas is the destination you saw at the start:

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

This is how a probe reads in `describe`: `http-get http://:http/salud` is "HTTP request to the Pod's IP (left empty, between `//` and `:`), at the port named `http`, path `/salud`"; then come the five numbers from 5.3.2, with `delay` in place of `initialDelaySeconds` and `period` in place of `periodSeconds`. The class went from `BestEffort` to `Burstable`, and the shutdown timeout from 30 to 10.

#### 5.4.3 Reading the probes in the log

Each probe is a real HTTP request, and the `revisor` writes one line for each request it serves. Its log, with the time of each line:

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

(`--timestamps` prepends to each line the time it was written, in UTC and with nanoseconds; the `sed` just trims the date and the decimals so it fits. Nobody else's log says these times: these are from this run.)

Now read it like a clock (these are minutes 45 and 46). The program started listening at `:44`. At `:45` there are **two** requests. The first is the **startup probe**, which asks every second and here needed no more than one; from that moment it does not ask again, and the other two come in. The second, in the same second, is the first **readiness** one: the probes documentation warns that, while a container is not ready, that probe can run outside its period, so the Pod becomes ready sooner. From there on there is one line every 5 seconds (`:45`, `:50`, `:55`, `:00`, `:05`): the readiness one. And between them, one every 10 (`:54`, `:04`): the **liveness** one. Exactly the manifest's `periodSeconds`. The second command confirms the result: the container started (`started` is `true`) and is ready (`ready` is `true`).

Two practical consequences. The first: at this rate, each replica writes about 18 lines per minute from probes alone, more than 25 thousand a day. If your program writes a line per request, the probes will fill its log, and it is worth knowing before looking for something there. The second: probes **cost**. Each question is work for the `kubelet` and for the program. That is why `/salud` must be cheap, and why periods are not set to one second "just in case".

### 5.5 Why `/salud` queries nobody

#### 5.5.1 Thursday's scene, in reverse

The `revisor` exists to tell you that other services are failing. If its health depended on those services, the cluster would punish it exactly when it does its job. It is checked: the `depurar` Pod from Lesson 3, the test service in `caido` mode, and 35 seconds of waiting, longer than the 30 the liveness probe takes to restart.

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

(In `correr.salida.txt` the token appears written out: the script pastes it into the command. It is a throwaway token from that run, which died with the cluster.)

Zero restarts on the four Pods, all `1/1`, and the report says what it has to say: `prueba FALLA codigo 503`. It is the opposite of Thursday's scene, and the difference is in a single design decision: `/salud` answers "I'm alive" without asking anyone anything. The comment on the manifest's first line leaves it written for whoever comes next.

Notice the test service too: `RESTARTS 0` and `1/1`, even though it has been answering 503 on `/` for more than 35 seconds. Its liveness probe asks `/modo`, which keeps answering. The cluster tells "it is failing on purpose" from "it is dead" because you asked it the right thing.

#### 5.5.2 And does the documentation not say to check dependencies?

It does, with a nuance, and it is worth reading in full. The probes documentation, in the part on when to use each one: "when your application has a strict dependency on back-end services, you can implement both a liveness and a readiness probe. The liveness probe passes when the app itself is healthy, but the readiness probe additionally checks that each required back-end service is available".

Two things. The first is the rule that never changes: **the liveness probe looks only at the application**. Even in that paragraph, the dependency goes in the readiness one, never in the liveness one. Restarting your program does not fix another team's database; it only leaves you without a program.

The second is a judgment call, and depends on what your service does. If your service cannot answer anything useful without its database, taking it out of traffic while the database is missing makes sense. The `revisor` is the opposite case: **its useful answer is precisely to say who is missing**. If its readiness probe depended on `prueba`, when `prueba` fell the `revisor`'s Service would be left without replicas and the dashboard would not load, which is the scene's symptom by another route. That is why the `revisor`'s three probes ask `/salud`, and `/salud` asks nobody. Exercise 1 lets you see that other route with the test service.

### 5.6 `requests`, `limits`, and the nodes' capacity

#### 5.6.1 Two numbers with two different owners

The [resource management documentation](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) separates them by who uses them: "when you specify the resource request for containers in a Pod, the kube-scheduler uses this information to decide which node to place the Pod on. When you specify a resource limit for a container, the kubelet enforces those limits so that the running container is not allowed to use more of that resource than the limit you set".

- **`requests` is a reservation.** The scheduler uses it when choosing a node, and the `kubelet` respects it afterwards: the same page says the `kubelet` also reserves "at least the request amount" for that container, so that, when there is competition for the CPU, the container keeps its share. On the scheduler, the same page: the scheduler makes sure that, for each resource, the sum of the requests of a node's containers is less than its capacity, and does so even if actual usage is very low: "the scheduler refuses to place a Pod on a node if the capacity check fails". The `request` is not what the container uses: it is what the node sets aside for it.
- **`limits` is a ceiling**, and it is enforced by the `kubelet` and the Linux kernel all the time.

#### 5.6.2 The units

**CPU.** The same page: "1 CPU unit is equivalent to 1 physical CPU core, or 1 virtual core" if the node is a virtual machine, and fractions are allowed: `0.1` is the same as `100m`, "which is read as one hundred millicpu". The `revisor` asks for `50m`, one twentieth of a core, and its ceiling is `200m`, one fifth. The documentation recommends the `m` form for quantities below 1, because it reads better.

**Memory.** In bytes, with suffixes. There are two families: `M`, `G` (powers of 10) and `Mi`, `Gi` (powers of 2). `32Mi` is 32 mebibytes, 33,554,432 bytes; `32M` would be 32,000,000. The course uses `Mi`. And a trap the documentation points out in so many words: "pay attention to the case of the suffixes". `400m` of memory is 0.4 **bytes**, not 400 megabytes: the lowercase `m` is "milli". A `memory: 64m` written by mistake is a ceiling of a fraction of a byte: the container cannot even start. (This was not measured in the lesson; what was measured when preparing the course is that with a ceiling of `4Mi` the `revisor` already gives `StartError`, as the comment in `memoria.yaml` says.)

#### 5.6.3 What happens on reaching the ceiling

The ceiling is not applied the same way to the two resources, and the difference is among the ones that matter most in this course. The resource management documentation:

- **CPU:** "`cpu` limits are enforced by CPU throttling". If the `revisor` wanted more than `200m`, the kernel simply does not give it: the program goes slower, but stays alive.
- **Memory:** "`memory` limits are enforced by the kernel with out of memory (OOM) kills". The memory a program already has cannot be taken away from it halfway, so, when it goes over and the kernel cannot reclaim memory elsewhere (for example, from the file cache), it kills it. The documentation calls it a "reactive" limit: it does not prevent the excess, it punishes it. This lesson's error on purpose is exactly that.

The practical rule that comes out of that: a low CPU ceiling makes your program **slow**; a low memory ceiling makes it **die**. Both are set, but the memory one is set with more margin.

#### 5.6.4 What a kind node says it has

How much fits on a node? It is asked:

```text
$ kubectl get nodes -o custom-columns='NODO:.metadata.name,CPU:.status.allocatable.cpu,MEMORIA:.status.allocatable.memory'
NODO                         CPU   MEMORIA
curso-k8s-l5-control-plane   6     16342676Ki
curso-k8s-l5-worker          6     16342676Ki
curso-k8s-l5-worker2         6     16342676Ki
```

(`custom-columns` builds a table with the fields you ask for; `allocatable` is what the node offers to Pods.)

Each node says it has 6 CPUs and about 15.6 GiB. All three are the **whole** Docker virtual machine of this run: 6 CPUs and 16 GiB. This is kind, and never forget it: its nodes are containers on the same machine, and each one sees and announces the full resources of the host. For the scheduler there are 18 CPUs; on the bare metal there are 6. On a real cluster, each node announces its own. In kind, `requests` and `limits` work the same as on a real one —the scheduler counts and the kernel cuts— but the capacity you see is a laboratory mirage. On your Mint, the numbers will be those of your computer.

What the scheduler has already set aside on a worker node:

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

`Requests` adds up what all the node's Pods ask for, yours and the system's. In this run, a `revisor` replica landed on `worker` (its `50m` and `32Mi`, and its `200m` and `64Mi` ceiling, which is the entire `Limits` column); the rest of the *requests* belong to the system Pods that run on every node, such as kind's network. The note at the top, "total limits may be over 100 percent", says something important: the scheduler does **not** count `limits`. You can promise more ceiling than there is, because it is assumed that not all of them reach their ceiling at once. What the scheduler does not let go past 100% of the allocatable capacity is the sum of `requests` when deciding where an ordinary Pod lands (the node's own static Pods do not go through it).

#### 5.6.5 How much the `revisor` really uses

The manifest's numbers are decisions. Are they close to reality? The `kubelet` talks to the node's `containerd`, and `crictl` can ask it how much each container uses (it is the same tool from Lesson 2, inside the node):

```text
$ docker exec curso-k8s-l5-worker2 crictl stats --label io.kubernetes.container.name=revisor | sed 's/^.\[2J.\[H//'
CONTAINER           NAME                CPU %               MEM                 DISK                INODES              SWAP
060935005135f       revisor             0.02                1.733MB             45.06kB             13                  0B
1be34aa64c901       revisor             0.03                1.733MB             45.06kB             13                  0B
```

(`--label` filters the containers named `revisor`; two replicas landed on `worker2`. `crictl stats` prints some screen-clearing codes at the start, and the `sed` removes them.)

Less than 2 MB of memory and the CPU almost at zero, at rest. The `32Mi` `request` is more than fifteen times that. It is not a mistake: the `revisor` grows when it builds a report and queries several services at once, and a `request` is what the program needs on its normal day under load, not at rest. But the number confirms something you will use in a moment: the `revisor` is **no good** for provoking an `OOMKilled`, because it uses almost no memory. To see it you need a program that asks for it.

On a real cluster, this measurement is done with `kubectl top`, which needs `metrics-server`. It arrives in Lesson 9, because it is what feeds autoscaling.

#### 5.6.6 The quality-of-service classes

With `requests` and `limits` the cluster classifies each Pod into one of three classes. The [QoS classes documentation](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) gives the criteria:

| Class | When | In this course |
|---|---|---|
| `Guaranteed` | every container has CPU and memory `requests` and `limits`, and in each one the `request` is **equal** to the `limit` | none |
| `Burstable` | it is not `Guaranteed`, but at least one container has some `request` or `limit` | `revisor`, `prueba`, `depurar`, `memoria` |
| `BestEffort` | no container declares anything about CPU or memory | the `revisor` in 5.1 |

And what it is for: when a node runs out of resources, "Kubernetes evicts `BestEffort` Pods on the node first, then `Burstable` Pods, and finally `Guaranteed` Pods". It adds that, when the eviction is due to lack of resources, only Pods that use more than they requested are candidates. The more detailed page on node-pressure eviction specifies it: the `kubelet` evicts first the `BestEffort` Pods and the `Burstable` ones that exceed their `request`, and the `Guaranteed` ones and the `Burstable` ones that do not exceed it are evicted last, if the above was not enough. That is, respecting your `request` puts you at the end of the line, not outside it. Another reason for the `request` to resemble actual usage. The `revisor` in 5.1 was first in line. Today it is `Burstable`, because its ceiling is higher than its floor: it can "stretch" from `50m` to `200m` if there is free CPU. To make it `Guaranteed` you would have to equalize the two numbers, and always pay the ceiling as a reservation. For a program that at rest uses 2 MB, the course prefers `Burstable`.

### 5.7 The graceful shutdown

#### 5.7.1 What happens when you delete a Pod

The [Pod lifecycle documentation](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) tells the sequence. When a Pod is requested to be deleted, the cluster records a timeout, and the node's `kubelet` starts the shutdown: it asks the container runtime to send "a TERM signal" (SIGTERM) "to process 1 inside each container", that is, to the main process, the one with PID 1. And then: "once the grace period has expired, the KILL signal is sent to any remaining processes". SIGTERM is a request ("shut down, please"); SIGKILL is not a request, it is the kernel ending the process without asking it. The default timeout is **30 seconds**, and it is changed with `terminationGracePeriodSeconds`.

At the same time something else happens, the one that connects with Lesson 3: the control plane takes the shutting-down Pod out of traffic. The same page: its endpoints are not immediately deleted from the EndpointSlice, but are marked `terminating` and "always have their ready status as false", so they receive no new traffic. (The EndpointSlices page adds an exception the course does not use: `ready` is always true in a Service with `publishNotReadyAddresses: true`.) The two things happen at the same time, not one after the other. That race between "the Pod receives SIGTERM" and "every node finds out it should no longer send it traffic" is the one Lesson 9 resolves with `preStop`. Today it is enough to know it exists.

#### 5.7.2 Seeing it

*A warning about names.* The outputs in this section and the next two come from the script's run, where the shutdown happened **after** the two errors in "The error you will see". That is why the Pod deleted here, `g9lhl`, still appears alive in the `Pending` section, and the `hfjmq` that replaces it already appears in the security habit: it is not a mistake in your cluster or in the lesson. On your machine, if you follow the lesson in the order of the text, the names will be different.

To see what the `revisor` writes in its last seconds, open a **second terminal** and prepare it like this, with the path that the `echo` in 5.1.1 printed (in the first terminal, `echo "$KUBECONFIG"` gives it to you again):

```bash
# En la SEGUNDA terminal. Pega la ruta completa; la de abajo es solo la forma.
export KUBECONFIG=/tmp/curso-k8s-l5.XXXX/kubeconfig
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
kubectl logs -f <nombre de una réplica del revisor>
```

If the check says "contexto equivocado", the path is not the right one: do not continue. With `kubectl logs -f` running there, in the first terminal delete that replica:

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

(`-f` follows the log live until the container ends; the script saves it to a file and shows its last four lines.)

`kubectl delete` waits for the Pod to truly disappear, and it took **less than a second** (the script measures in whole seconds and recorded `0 s`; in other runs it recorded 1 and 3). The last two lines of the log are the graceful shutdown: the `revisor` received `terminated` (which is what Go calls SIGTERM), stopped accepting new connections, waited for the ones it had to finish, and left on its own: `apagado limpio`. It never reached SIGKILL. And the ReplicaSet had already replaced the replica: `hfjmq`, 3 seconds old.

#### 5.7.3 Why 10 seconds

If the `revisor` left in under a second, why change the timeout from 30 to 10? Because the timeout is not for the good shutdown, it is for the **bad** one. If one day the `revisor` gets stuck and does not handle SIGTERM, the cluster kills it at 10 seconds and not at 30. During that time the Pod occupies its place: a *rollout* of three replicas that shut down badly could take minutes longer.

The number is not random either: the `revisor` gives itself 5 seconds to finish the requests in progress, and the cluster's timeout has to be **greater** than the application's, or SIGKILL interrupts it halfway through saying goodbye. 10 is double 5. When Lesson 9 adds `preStop`, which also runs inside this timeout, the number goes up to 15.

Exercise 3 shows you what happens with a process that does **not** handle SIGTERM: the `depurar` Pod.

## The error you will see

This lesson has two errors on purpose, one for each `resources` number: the memory ceiling and the CPU floor.

### OOMKilled: going over the memory ceiling

As you saw in 5.6.5, the `revisor` uses less than 2 MB; with it an `OOMKilled` cannot be seen. A bare Pod is used, `memoria.yaml`, which is a **program** that fails on purpose: it tries to store 40 MB in a *shell* variable with a ceiling of 16 MiB.

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

It is the `curl` image from `depurar`, with the same `securityContext`, and another program: `head -c 40000000 /dev/zero` produces 40 million zero bytes, `tr` turns them into letters `x`, and `a=$(…)` forces the *shell* to hold them all in memory. `restartPolicy: Never` makes it stay dead when it dies, so it can be examined.

```text
$ kubectl apply -f memoria.yaml
pod/memoria created

$ kubectl get pod memoria
NAME      READY   STATUS      RESTARTS   AGE
memoria   0/1     OOMKilled   0          20s
```

`STATUS OOMKilled`: killed for lack of memory (*Out Of Memory*). It is read in order, from the symptom to the cause.

**First, the reason and the code:**

```text
$ kubectl get pod memoria -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
OOMKilled 137
```

The exit code `137` is a Unix convention: 128 plus the number of the signal that killed the process. 137 − 128 = 9, and signal 9 is SIGKILL. Nobody asked the program to leave; the kernel ended it. But careful: a 137 says "it was killed with SIGKILL", not who or why. It may be the kernel for memory, as here, or the `kubelet` because the shutdown timeout expired, which is what Exercise 3 provokes. What separates the two cases is the reason: `OOMKilled` in one, something else in the other. Always look at the reason next to the code.

**Second, how far it got:**

```text
$ kubectl logs memoria
pidiendo 40 MB
```

It wrote its first line and never the second, `no debería llegar aquí`. It died halfway through the allocation.

**Third, the ceiling that explains it:**

```text
$ kubectl describe pod memoria | grep -E '^QoS Class:|Reason:|Exit Code:|Limits:|memory:'
      Reason:       OOMKilled
      Exit Code:    137
    Limits:
      memory:  16Mi
      memory:     16Mi
QoS Class:                    Burstable
```

`Limits: memory: 16Mi` (the second `memory: 16Mi` is from the `Requests` block, which the `grep` also catches). It asked for 40 MB against a ceiling of 16 MiB: the kernel did exactly what 5.6.3 says. The [guide to assigning memory](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) provokes the same error with another program and, in its section "Exceed a Container's memory limit", sums it up like this: a container can exceed its `request` if the node has memory, but not its `limit`.

**How to fix it.** Not with a higher ceiling "to see if that helps". The resource management documentation, in its troubleshooting section, gives the order: faced with an `OOMKilled`, the next step is to review the code looking for a memory leak; if the program behaves as you expect, then yes, raise the ceiling (and perhaps the floor). Here the program does exactly what it should do, which is to fail; it is deleted:

```text
$ kubectl delete pod memoria
pod "memoria" deleted from default namespace
```

If it were a container in a Deployment, the `kubelet` would restart it over and over, with growing waits between attempts: the lifecycle documentation gives the series, "10s, 20s, 40s, …", capped at 5 minutes. That wait is what `kubectl get pods` shows as `CrashLoopBackOff`. If you see a `CrashLoopBackOff`, look at the `RESTARTS` column and at the reason for the last termination before touching anything: it may be an `OOMKilled`, it may be a program that exits with an error, it may be a badly written liveness probe. They are three different fixes.

### Pending: asking for a floor that does not fit

The second error goes to the other number: a CPU `request` that no node can set aside. It is provoked with a direct patch to the Deployment, so the correction is to apply the file again.

Before a change like this, the context check from 5.1.2:

```bash
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
```

```text
$ kubectl patch deployment revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"50"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"50"}]'
deployment.apps/revisor patched
```

`kubectl patch --type=json` changes individual fields of a live object: here, the first container's CPU `request` and `limit` become `50`. **Fifty CPUs**, not fifty millicpu: the `m` is missing. It is a typo that is easy to make, and the cluster accepts it without complaint: `50` is a valid quantity.

**First, the symptom:**

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

Four Pods: a new ReplicaSet (`revisor-5b8f867ccf`) with one replica in `Pending`, and the three old ones intact. `Pending` means the Pod exists in the `kube-apiserver` but nobody has given it a node. And the *rollout* got stuck at "1 of 3": `rollout status` gave up after the 15 seconds you gave it.

**Second, the cause, in the Pod's events:**

```text
$ kubectl describe pod revisor-5b8f867ccf-9x42x | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  25s   default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

(`sed -n '/^Events:/,$p'` prints from the `Events:` line to the end.) The one speaking is the scheduler (`default-scheduler`), and its message reads node by node:

- `0/3 nodes are available`: none of the three nodes will do.
- `1 node(s) had untolerated taint(s)`: one has a "taint" that this Pod does not tolerate. It is the control-plane node, which by default does not receive your Pods; you saw it in Lesson 1 when Pods only landed on the worker nodes.
- `2 Insufficient cpu`: the other two do not have enough CPU. They ask for 50; each announces 6.
- `preemption: … Preemption is not helpful`: the scheduler also considered evicting lower-priority Pods to make room, and concluded it would not help. Even if it emptied a node, 50 do not fit in 6.

The resource management documentation carries this same event as its first troubleshooting case: if the scheduler cannot find a node where the Pod fits, "the Pod stays unscheduled until a place can be found", and an event is produced each time it fails. The outs it suggests are adding nodes or freeing space; the one that applies here is the third, the obvious one: ask for the right thing.

**Third, what did not break:**

```text
$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

The service keeps answering. Why did the Deployment not remove any old replica? Because of its update strategy, which Lesson 9 studies in depth: the [Deployments documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) says that, by default, `maxUnavailable` is 25% "rounding down" and `maxSurge` is 25% "rounding up". With 3 replicas: 0.75 rounds down to **0** replicas that can be missing, and 0.75 rounds up to **1** that can be extra. The Deployment created one extra and waited for it to be available before removing an old one. It never was. A stuck *rollout* is uncomfortable; one that took down the good replicas to replace them with replicas that do not fit would be an outage. This rule protects you from your own typo.

**The correction** is the usual one in this course: the file is the truth, and you apply it again.

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

The same three replicas as before, with the same ages. The template became identical again to that of the ReplicaSet `revisor-578c8dc8d9`, which already had its three replicas, so there was nothing to replace: the Deployment brought the broken ReplicaSet down to zero and the `Pending` Pod disappeared. It is the same effect you saw in Lesson 2's Solution 3.

**The order, for any Pod that is not `Running`:**

1. `kubectl get pods`: `Pending`, `OOMKilled`, `CrashLoopBackOff`?
2. If it is `Pending`, the Pod's events: what does the scheduler say about each node?
3. If it died, the reason and code of its last termination (`OOMKilled 137`, an `Error` with another code) and its log (`kubectl logs`, or `--previous` if it already restarted).
4. Before changing a number, ask whether the number is wrong or the program is wrong.

## The security habit of the lesson: every container with a floor and a ceiling

The course's habits table assigns this lesson two things: `requests` and `limits` on every container; probes do not depend on other people's services. You checked the second in 5.5. The first is checked at a glance:

```text
$ kubectl get pods -o custom-columns='POD:.metadata.name,QOS:.status.qosClass,CPU_PIDE:.spec.containers[0].resources.requests.cpu,CPU_TOPE:.spec.containers[0].resources.limits.cpu,MEM_PIDE:.spec.containers[0].resources.requests.memory,MEM_TOPE:.spec.containers[0].resources.limits.memory'
POD                        QOS         CPU_PIDE   CPU_TOPE   MEM_PIDE   MEM_TOPE
depurar                    Burstable   10m        100m       16Mi       32Mi
prueba-b896986b5-kzrmk     Burstable   10m        100m       16Mi       32Mi
revisor-578c8dc8d9-hfjmq   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-jlh4b   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-xhqt8   Burstable   50m        200m       32Mi       64Mi
```

Five Pods, five complete rows, none `<none>`, none `BestEffort`. Including `depurar`, which is "just for looking": Lesson 3 gave it a ceiling from the start, and today you know why.

Why is it a **security** habit and not just one of tidiness? Because a container with no memory ceiling is a container that can take down its neighbors. The [`LimitRange` documentation](https://kubernetes.io/docs/concepts/policy/limit-range/) begins with the sentence that explains it: "by default, containers run with unbounded compute resources on a Kubernetes cluster". A programming error (a memory leak, a loop that never ends) or an attack (someone sending enormous requests on purpose) in a container with no ceiling becomes a problem for the **whole node**: the node runs out of memory and starts evicting Pods, beginning with the `BestEffort` ones, which may belong to another team. With a ceiling, the damage stays inside the container that caused it: it dies, with an `OOMKilled` that says exactly what happened, and nobody else.

The same with CPU, with a nuance: a container with no CPU ceiling that enters an infinite loop eats all the node's free CPU and slows its neighbors. Those that declared `requests` keep their share, and that is why the floor also protects; those that declared nothing get whatever is left over. With a ceiling, the one that chokes is itself.

**What it protects against and what it does not.** Ceilings limit the damage **within a node**; they do not stop someone from creating a hundred Pods. For that a real cluster uses `ResourceQuota` (a total per namespace) and `LimitRange` (a maximum and a default value per container). This course does not install them, and names them so you know they exist. And probes are not a defense: an attacker who gets into the `revisor` is not going to break `/salud`. What they do prevent is the other half of the problem, a mistake of yours turning a small failure into a cascade.

## Common mistakes

**Putting in the liveness probe something that depends on others.** It is Thursday's scene. A downed database is not fixed by restarting its clients. The liveness probe asks about the process, and nothing else.

**Using the same patience for all three probes.** If the liveness one reacts as fast as the readiness one, a ten-second stumble restarts instead of just setting aside from traffic. The liveness one is slower.

**A liveness probe without a startup probe on a program that is slow to start.** The `kubelet` starts asking as soon as the container starts; if the program takes longer than `failureThreshold × periodSeconds`, it is restarted before it finishes starting, and again, and again. The startup probe exists for that.

**An expensive health route.** If `/salud` queries the database, builds a report, or writes to disk, every probe does it, on every replica, every few seconds. Cheap and local.

**Pointing the probe at a route that changes its code on purpose.** The test service's `GET /` is one of those: 503 in `caido` mode by design. Exercise 2 measures it.

**Containers with no `requests` or `limits`.** They end up `BestEffort`: the scheduler sets nothing aside for them, nobody puts a ceiling on them, and they are the first to leave when the node gets tight.

**Writing `memory: 64m` or `cpu: 50`.** The lowercase `m` in memory is milli-bytes; a number without `m` in CPU is whole cores. The second is this lesson's `Pending`.

**Raising the memory ceiling every time there is an `OOMKilled`.** If it is a leak, you only delay it. First you ask whether the program is right.

**Taking a kind node's capacity as real.** Each node announces your whole machine. What fits in kind does not tell you what fits in production.

**Leaving the default shutdown timeout without thinking about it.** Thirty seconds can be a lot for a program that shuts down in one, and little for one that has to finish a long job. It is chosen, and chosen greater than the program's internal timeout.

**A main process that ignores SIGTERM.** The cluster will wait the full timeout every time you shut it down. Exercise 3 measures it.

## Exercises

The first three are run in the lesson's cluster, in order and from the state it was left in after 5.7, with the `depurar` Pod still alive. Before each one, `kubectl config current-context` must say `kind-curso-k8s-l5`. `correr.sh` runs them the same way, and its output is in `correr.salida.txt`. **Before** running each one, write in the [log](bitacora.md) what you think will happen. The fourth is written in your own words.

### Exercise 1 — A readiness probe on the test service

`fig05_01.prueba-disponibilidad.yaml` is this lesson's test Deployment with a single difference: it adds a readiness probe on `GET /`, every 5 seconds, with 2 failures to leave the traffic.

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

Apply it, wait for the new Pod to be `1/1`, and put it in `caido` mode. Before looking, predict: after 15 seconds, what does the `READY` column say? And `RESTARTS`? What does the EndpointSlice of the `prueba` Service say? Ask it with `kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}'`. What detail does the `revisor`'s report give? And the hard question: does `kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano` work to fix it? If not, how do you put it back to `sano`? When you finish, apply `kubectl apply -k .` again.

### Exercise 2 — A liveness probe that asks what it should not

`fig05_02.prueba-vida-mala.yaml` is the lesson's test Deployment with a single different line: the liveness probe asks `GET /` instead of `GET /modo`.

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

Apply it, wait for it to be `1/1`, and put it in `caido` mode. Predict, with the probe's numbers: how many seconds does the first restart take, roughly? What events does the Pod leave (look for the reasons `Unhealthy` and `Killing`)? After the restart, what does `GET /modo` answer? What does the `revisor`'s report say? And explain why this is worse than it seems: what happened to the evidence? When you finish, apply `kubectl apply -k .` again.

### Exercise 3 — How long the debug Pod takes to leave (project)

In 5.7 the `revisor` shut down in under a second. Now it is `depurar`'s turn, the curl Pod from Lesson 3. Before deleting it, look at two things: its `terminationGracePeriodSeconds` (it does not declare one) and which process is number 1 inside its container (`kubectl exec depurar -- ps`). Predict how long `kubectl delete pod depurar` will take, measure it with the clock, and explain the number. Then propose two ways for it to leave faster, one in the manifest and one in the command.

### Exercise 4 — Does a fourth replica fit?

With this lesson's numbers: the `revisor` asks for `50m` of CPU and `32Mi` of memory, and in the lesson's run each worker node announced 6 CPUs (use the number from your `kubectl get nodes` if it is different). In five sentences at most: how many `revisor` replicas would fit, in theory, on one worker node, counting only CPU? Why is that number misleading in kind? Which number would the scheduler look at to decide, the `request` or the `limit`? And what QoS class would the `revisor` have if you wrote equal `requests` and `limits`, `200m` and `64Mi`, and what would you gain and what would you pay?

## Solutions

### Solution 1

Measured in `correr.salida.txt`:

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

**`READY 0/1` with `RESTARTS 0`.** The readiness probe failed twice in a row (503 on `/`) and the `kubelet` marked the Pod as not ready, without restarting it: it is exactly the difference in 5.3.4. The EndpointSlice confirms it: the address is still on the list, but with `ready=false` and `serving=false`, so nobody sends it traffic.

**The report changed its detail.** In 5.5 it said `FALLA codigo 503`: the service answered, badly. Now it says `connection refused`: with its only replica off the list, the `prueba` Service has nobody to send the connection to and refuses it instantly, the same code 7 as in Lesson 3. The `revisor` still says `FALLA`, but it lost information: you no longer know **what** the service answered, only that nobody is there.

**And you were left without a way to fix it.** The `POST /modo/sano` by the name `prueba` also goes through the Service, and is also refused (code 7). The Pod is alive and listening; what no longer exists is the path. The way out is to talk to the Pod's IP directly, which does not go through the Service: `10.244.2.10`, taken from the same EndpointSlice or from `kubectl get pods -o wide`. It answered `modo: sano`, the probe passed again, and the Pod went back to `1/1` in a few seconds. It is Lesson 3 in reverse: there you learned **not** to use Pod IPs; here you use it on purpose, once, to debug.

The general lesson: a readiness probe takes the Pod out of **all** the Service's traffic, including your administration traffic. For a service like this, whose job is to fail visibly, it is the wrong decision. That is why the lesson's manifest does not carry it.

### Solution 2

Measured in `correr.salida.txt`:

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

**27 seconds, and the container restarted.** The probe asks every 10 seconds and tolerates 3 failures: three failed questions fit in about 20 to 30 seconds, depending on where in the cycle the probe was when you changed the mode. The events tell the story in two lines: `Unhealthy … statuscode: 503` (the probe failed) and `Killing … failed liveness probe, will be restarted` (the `kubelet` killed it for that). `RESTARTS 1 (4s ago)`: the restart was 4 seconds ago. (An `Unhealthy` event repeats for each failure, but the cluster groups identical ones into a single line with a counter.)

**And here is the serious part: after the restart, `modo: sano` and the report says `OK`.** The test service keeps its mode in memory; on restarting, it starts in the default mode. The cluster "fixed" the symptom by erasing the evidence. If this were a real service with a real problem, the `revisor` would have reported the failure for 27 seconds and then everything green, and someone would conclude that it "fixed itself". And the next time it fails, the same. With the probe written properly (`/modo`), in 5.5 the service stayed in `caido` as long as you wanted and the report told the truth the whole time. This is the documentation's warning in miniature: a liveness probe that detects not an unrecoverable failure but something else ends up doing harm.

After the two exercises, the script applies `kubectl apply -k .` again and checks that the cluster is once more exactly what the files say. It is 5.4.1's `kubectl diff`, now in reverse: no differences, it exits with 0 and the message is printed.

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

Do the same in your cluster before Exercise 3: if the `diff` prints anything, some exercise was left undone.

### Solution 3

Measured in `correr.salida.txt`:

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

**32 seconds: the full timeout, plus what the SIGKILL and the cleanup take.** The manifest declares no timeout, so the default one applies, 30. The container's process number 1 is `sleep 3600`. The `kubelet` sent it SIGTERM, and `sleep` did nothing: in Linux, the process with PID 1 of a process namespace ignores the signals for which it installed no handler, and `sleep` installs none. So the cluster waited the 30 seconds and sent SIGKILL, which cannot be ignored. Meanwhile, `kubectl delete` waited. The `revisor`, by contrast, does install its SIGTERM handler (that is why it writes `recibí terminated`), and left in 1 second.

Two ways for it to leave faster:

- **In the manifest:** `terminationGracePeriodSeconds: 1` on the `depurar` Pod. It has nothing to finish in an orderly way; a short timeout takes nothing from it. (Another option is for its main process to handle SIGTERM, for example with an `sh` that installs a `trap`; it is more work for a use-and-throw-away Pod.)
- **In the command:** `kubectl delete pod depurar --wait=false`, which requests the deletion and returns immediately without waiting. The Pod takes the same time to leave; it is only you who stop waiting for it. It is what Lesson 3's script does at the end. There is also `--grace-period` in `kubectl delete` to change that deletion's timeout. Its help (`kubectl delete --help`) says that `--grace-period=1` is immediate shutdown, and that 0 is only accepted together with `--force`, which also deletes the Pod from the API without waiting for the node to confirm that the container has ended. Use it with care.

### Solution 4

One possible answer: "Counting only CPU, on a node that announces 6 CPUs (those of this run) 6,000 m / 50 m = 120 replicas fit, minus what the system Pods already ask for (in this run, the node already had `150m` set aside counting one replica). That number is misleading because in kind the three nodes announce the same complete machine: the scheduler believes there are 18 CPUs where there are 6, and the replicas on the three nodes would fight over the same cores. The scheduler decides with the `request`, never with the `limit`: limits can add up to more than 100% of a node. With equal `requests` and `limits` at `200m` and `64Mi`, the Pod would be `Guaranteed`: the last to be evicted when the node gets tight, and with its CPU always set aside. You would pay for it by reserving four times more CPU and double the memory than the `revisor` needs on its normal day, so four times fewer replicas would fit per node."

## Deleting the cluster

When you finish the exercises, delete the lesson's cluster. Leave nothing alive on the machine:

```text
$ kind delete cluster --name curso-k8s-l5
Deleting cluster "curso-k8s-l5" ...
Deleted nodes: ["curso-k8s-l5-worker" "curso-k8s-l5-control-plane" "curso-k8s-l5-worker2"]
(borrar tardó 1 s)

$ kind get clusters | grep -c curso-k8s-l5
0
```

(The line in parentheses is written by the script, which measures the deletion.) The `--name` is mandatory: without it, kind would delete the cluster called `kind`, which may belong to someone else or to another project.

What remains on your machine is the `kubeconfig`'s temporary folder and the two `token.txt` files. They are deleted like this, from `programas/05-salud-recursos-apagado`:

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

The `case` only lets through a path that starts with `/tmp/curso-k8s-l5.` and has something after it, the exact form of the one you created in 5.1.1. If `L5_TMP` is empty (for example, because you are in another terminal, where you never defined it) or holds something else, it deletes nothing and tells you why. It is the same protection `correr.sh` uses when cleaning up: an `rm -rf` that can be copied and pasted has to protect itself. If the second terminal from 5.7 is still open, close it: all you did there was the `export`. The next lesson's cluster is created from scratch, just like this one.

## How I know I succeeded

- [ ] Faced with a Pod that restarts on its own, you tell from the events whether it was a liveness probe (`Killing … failed liveness probe`), an `OOMKilled`, or the program exiting with an error.
- [ ] You write the `revisor`'s three probes and say, for each, what it asks, what happens if it fails, and how many seconds it takes to react with its numbers.
- [ ] You explain, with the output from 5.5 and the one from Exercise 2, why the liveness probe must not depend on anyone else nor on a route that fails on purpose.
- [ ] You read a `Liveness:` line from `describe` and name each number.
- [ ] You write `requests` and `limits` in millicores and mebibytes without confusing `m` with `M`, and say who uses each one.
- [ ] Faced with a `Pending`, you read the `FailedScheduling` node by node; faced with an `OOMKilled`, you find the `137` and the ceiling that explains it.
- [ ] You explain what the cluster does between `kubectl delete pod` and the Pod disappearing, and why `depurar` takes more than 30 seconds and the `revisor` less than one.
- [ ] You run `programas/05-salud-recursos-apagado/correr.sh > /tmp/mi-corrida-l5.txt 2>&1` and compare `/tmp/mi-corrida-l5.txt` against `programas/05-salud-recursos-apagado/correr.salida.txt` (do not redirect to that file: it is the reference) in what does not change between runs: three nodes `Ready` at `v1.37.0`; six `not yet present on node … loading...` lines; `33` bytes of token and `-rw-------` on the two `token.txt` files; `QoS Class: BestEffort` and `30` before the lesson; `mismo token`; the `kubectl diff` with the probes, the resources, and the two `terminationGracePeriodSeconds: 10`, and its code 1; only the Deployments `configured`; the `Limits`, `Requests`, `Liveness`, `Readiness`, and `Startup` lines with their numbers, `QoS Class: Burstable`, and `10`; in the log, a `GET /salud` line every 5 seconds and another every 10; `RESTARTS 0` on the four Pods with prueba in `caido` and `FALLA … codigo 503`; the three nodes with the same CPU and memory; `OOMKilled`, `OOMKilled 137`, and `pidiendo 40 MB`; the `Pending`, `timed out waiting for the condition`, and `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu`; `revisor: recibí terminated, apagando` and `revisor: apagado limpio`; the five rows with floor and ceiling, all `Burstable`; `0/1` with `ready=false`, `connection refused`, and code 7 in Exercise 1; `RESTARTS 1`, the events `Unhealthy … 503` and `Killing … will be restarted`, and `modo: sano` in Exercise 2; `sin diferencias con los archivos`; `30`, `sleep 3600` as PID 1, and a deletion of 30 s or a little more in Exercise 3. The IPs, the name suffixes, the ages, the log's time, the nodes' CPU and memory and their percentages, the `revisor`'s exact memory in `crictl stats`, which node each Pod lands on, the order of the `kind load` lines, and the exact seconds of the first restart in Exercise 2 change on every run: they are observed, not compared.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l5`.

## Summary

Answer without looking at the lesson:

1. What did the cluster know about the `revisor` before this lesson, and why was its Pod `1/1` at 4 seconds?
2. What does each of the three probes ask and what does the cluster do when the answer is "no"?
3. Who runs the probes, and which HTTP codes count as success?
4. With `periodSeconds: 10` and `failureThreshold: 3`, how long does a liveness probe take to react?
5. Why does `/salud` not query the test service, and why does the test service's probe ask `/modo` and not `/`?
6. Who uses the `requests` and who the `limits`? What happens to a container that exceeds its CPU ceiling, and what happens if it exceeds its memory one?
7. What is `100m` of CPU? And `100m` of memory?
8. What three QoS classes are there and in what order are Pods evicted when a node runs out of resources?
9. What does the code 137 mean?
10. What happens, in order, when you delete a Pod, and what is `terminationGracePeriodSeconds` for?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, "Liveness, Readiness, and Startup Probes"](https://kubernetes.io/docs/concepts/workloads/pods/probes/): what a probe is and that the `kubelet` runs it; what each asks and what happens on failure; that the startup one holds back the other two until it succeeds; that the readiness one removes the Pod's IP from the EndpointSlices and runs during the whole lifecycle; the warning about cascading failures; backend dependencies in the readiness probe and not the liveness one; the pattern of a higher `failureThreshold` on the liveness one; a probe's fields and their default values.
- [Kubernetes, "Configure Liveness, Readiness and Startup Probes"](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/): codes 200 to 399 as success of an HTTP probe; the startup probe with `failureThreshold * periodSeconds` to cover the worst startup, and the 30 × 10 s example.
- [Kubernetes, "Resource Management for Pods and Containers"](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/): the `request` for the scheduler and the `limit` for the `kubelet`; the CPU ceiling by throttling and the memory one by OOM kill; the CPU units (`100m`, "one hundred millicpu") and memory units (`Mi`, the lowercase `m` trap); that the scheduler adds up the `requests` and refuses even if actual usage is low; the `FailedScheduling` event and the `OOMKilled` as troubleshooting cases.
- [Kubernetes, "Pod Quality of Service Classes"](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/): the criteria for `Guaranteed`, `Burstable`, and `BestEffort`, and the order of eviction.
- [Kubernetes, "Pod Lifecycle"](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): Pod termination with TERM, the 30-second default timeout, and the KILL on expiry; the endpoints of a shutting-down Pod, marked `terminating` with `ready` as `false`; the growing wait between restarts (10 s, 20 s, 40 s… up to 5 minutes) and `CrashLoopBackOff`.
- [Kubernetes, "Assign Memory Resources to Containers and Pods"](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/): a container that exceeds its memory ceiling and ends `OOMKilled`.
- [Kubernetes, "Deployments"](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxUnavailable` and `maxSurge` at 25% by default, rounded down and up.
- [Kubernetes, "Limit Ranges"](https://kubernetes.io/docs/concepts/policy/limit-range/): that, by default, containers run with no resource limit.
- [kind, "Quick Start"](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind create cluster` and `kind load docker-image` with `--name`, and `crictl` inside a node.

---

**Next:** [Lesson 6 — Getting into the cluster](06-entrar-al-cluster.md)
