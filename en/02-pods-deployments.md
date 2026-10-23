# Lesson 2 — Pods and Deployments

Monday, 8:50 in the morning. At 9:30 the team has the demo of the new cluster and your part is the simplest one: the `revisor` has to show up running, with three copies. The image has been on your laptop since Friday, built and tested with `docker run`. You write the manifest, apply it, and `kubectl` answers `deployment.apps/revisor created`. You breathe out. You ask for the Pods and all three say the same thing: `ImagePullBackOff`. Someone on the team, without looking up, tells you: "delete it and apply it again". You do. Same state. You do it once more. It is 9:05 and the image is still there, in your `docker image ls`, two centimeters from the cluster that says it cannot find it.

Deleting and applying again was never going to help in this situation, because the cluster was not confused: it was telling you exactly what it was missing. This lesson teaches you to listen to it, to give it what it asks for, and to understand which objects are born when you apply a Deployment. That way, when something fails at 9:05, you will know where to look.

**Time:** 2 × 45 min

**What you build:** the `revisor` running in the course cluster, with three replicas that come back to life when they die, hardened from the very first manifest

**What you learn:** why your Docker and the cluster's nodes do not share images, and how `kind load docker-image` carries them over; the `ErrImagePull` that is provoked on purpose and how to read it; what a Pod, a ReplicaSet, and a Deployment are, and who owns whom; labels and selectors; what a *rollout* is and how to see its history; and the `securityContext` that every container in this course carries

**Where you are coming from.** From [Lesson 1](01-instalacion-primer-cluster.md): you have `kubectl` and `kind` installed with their checksums verified, the `inotify` limit adjusted, and you know how to create, inspect, and delete the course's three-node cluster. From [Lesson 0](00-que-es-kubernetes.md) you bring the map: the `kube-apiserver` stores what you declare, the controllers chase it, the `kube-scheduler` picks a node, and the `kubelet` starts containers. And from the [Docker course](https://www.habil.mx/en/courses/docker/) you bring the finished `revisor` image, `curso-docker-revisor:1.6.0`.

**What this lesson does not do.** The `revisor` ends up running, but nobody can talk to it yet: there is no stable name to find it by and no way to reach it from your machine. That is [Lesson 3](03-services-dns.md), with Services and the cluster's DNS. Nor is it configured from outside yet: the list of services it checks is written in the manifest and [Lesson 4](04-configuracion-secretos.md) moves it out into a `ConfigMap`. And the cluster does not yet know whether the `revisor` is healthy or merely alive: probes arrive in [Lesson 5](05-salud-recursos-apagado.md).

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1, and the node image `kindest/node:v1.37.0` pinned by its digest, in the three-node cluster from Lesson 1, here called `curso-k8s-l2`. The machine was a Mac with an ARM processor and Docker Engine 29.2.1 inside a Linux virtual machine (Colima), **not** Linux Mint, which is the course's reference system. What changes on your Mint: the architecture (`amd64` instead of `arm64`), the Pods' IP addresses, the random suffixes in the names of Pods and ReplicaSets, the ages, and which node each replica lands on. The commands are the same. The complete walkthrough is in [`programas/02-pods-deployments/`](../programas/02-pods-deployments): `correr.sh` creates the cluster **without** the `revisor` image, walks through the lesson in order, runs Exercises 1 to 3, and deletes the cluster; it took 2 minutes and 25 seconds measured with the terminal's clock; the script records on its own how long each long step took: creating the cluster and waiting for it to be ready, 34 seconds; loading the image, 2; deleting it, 1. Its output is `correr.salida.txt`. In it, the security habit part appears before the *rollout* part (2.8), because the script runs them in that order.

## By the end you will be able to

- Check with `crictl images` whether an image is inside a kind node, and load it with `kind load docker-image`.
- Provoke an `ErrImagePull`, read it with `kubectl describe` and `kubectl get events`, and say what each line means.
- Write from memory the skeleton of a Deployment (`replicas`, `selector`, `template`) and explain why the selector and the template's labels have to match.
- Follow the Deployment → ReplicaSet → Pod chain with `ownerReferences`, and predict what happens when each link is deleted.
- Filter objects with label selectors (`-l app=revisor`, `-l 'app in (…)'`) and explain what the `pod-template-hash` label is.
- Read a Deployment's history with `kubectl rollout history` and trigger an orderly restart with `kubectl rollout restart`.
- Justify each line of the `revisor`'s `securityContext` and recognize the `CreateContainerConfigError` that a contradiction in it produces.

## The why before the how

In Lesson 0 you saw a Deployment that kept three copies of a container that did nothing. It was the pure idea: you declare "I want three" and the cluster chases that number. Now comes the version with a real program, and three questions appear that the toy example hid.

The first: **where does the cluster get the image from?** The one in Lesson 0 came already inside the node, because Kubernetes itself uses it. The `revisor`'s you built yourself and it lives in your Docker. A kind node seems to be "on your machine", but inside it has its own image store, which is not your Docker's. It is the exact cause of Monday's scene, and it is the first thing you are going to see fail.

The second: **which objects exist and who looks after whom?** A Deployment does not run containers. It creates a ReplicaSet, which creates Pods, which are what run. If you do not see that chain, "deleting a Pod" and "deleting the Deployment" look like the same operation, and they are not: one repairs itself in a second and the other shuts the service down.

The third: **what can the container do if someone attacks it?** With `docker run` you learned to take away its privileges with `--user`, `--read-only`, and `--cap-drop ALL`. In Kubernetes those same decisions are written in the manifest, in a block called `securityContext`, and this course puts them in from the first Deployment. They do not wait for Lesson 7. Security added at the end stays on a to-do list; security that is born with the manifest travels with it to any cluster.

The lesson has eight concept parts and then the usual sections:

1. **Two image stores** (2.1): your Docker and each node's.
2. **The `revisor`'s manifest, field by field** (2.2).
3. **Applying and not finding the image** (2.3), the error on purpose.
4. **`kind load docker-image`** (2.4) and the cluster that recovers on its own.
5. **The chain of owners** (2.5): Deployment, ReplicaSet, and Pod.
6. **Labels and selectors** (2.6).
7. **A bare Pod versus a Deployment's Pod** (2.7).
8. **The *rollout*** (2.8): revisions, history, and restart.

This is the destination. At the end of 2.4, the `revisor` is running with three replicas, in a cluster that half a minute earlier did not have its image:

```text
$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           32s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-697fb84f97   3         3         3       32s
```

## If you do not have the image from the Docker course

This lesson uses the image delivered by Lesson 10 of the Docker course, `curso-docker-revisor:1.6.0`. Before continuing, check that you have it:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

If you do not have it, build it from that course's repository, with the `Dockerfile` from its Lesson 10 over the `programas/revisor` folder and with `--build-arg VERSION=1.6.0`, tagging it exactly `curso-docker-revisor:1.6.0`. If you use another image of a service of your own, this is what the course asks of it, and it is worth reading because each point explains a decision in the manifest:

- **It listens for HTTP on a high port**, 8080, and answers `GET /salud` without querying anyone else.
- **It runs as a numeric user that is not `root`**: 65532, the `nonroot` user of *distroless* images. The manifest requires it with `runAsNonRoot: true`.
- **It works with a read-only file system**, except for a data folder (`/datos`), which the manifest mounts separately.
- **It carries its own health check** as a subcommand (`/revisor healthcheck`), because the image has no *shell* or `curl`.
- **It has a fixed tag**, never `:latest`. Section 2.2.3 explains why that matters in kind.
- **It is configured through environment variables.** The `revisor` requires `REVISOR_SERVICIOS`, with the list of services it checks, and understands `REVISOR_PUERTO`, `REVISOR_REPORTE`, and `REVISOR_TOKEN_ARCHIVO`. A variable it does not read is silently ignored, so do not make up others.

## The concepts

### 2.1 Two image stores

This lesson uses its own cluster, `curso-k8s-l2`, with the three-node configuration from Lesson 1, freshly created and with **nothing** loaded into it. Create it like this, from the root of the course repository, with the same care you learned in Lesson 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l2.XXXX)/kubeconfig"
# curso-k8s-l2 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l2 --config programas/02-pods-deployments/kind-curso.yaml
# Debe decir kind-curso-k8s-l2. Si dice otra cosa, no sigas.
kubectl config current-context
```

The `export` only holds in that terminal. If you open another one, repeat the `export` with the same path, or `kubectl` will talk to another cluster. The outputs in this section come from the run of `correr.sh`, which does exactly this:

```text
$ kubectl config current-context
kind-curso-k8s-l2

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l2-control-plane   Ready    control-plane   26s   v1.37.0
curso-k8s-l2-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l2-worker2         Ready    <none>          16s   v1.37.0
```

The first command is not decoration. It is the habit from Lesson 1: before changing anything, ask which cluster you are talking to. In this lesson you are going to create and delete objects, and `kind-curso-k8s-l2` is the only answer that lets you continue. Repeat it **before every** `apply`, `delete`, `label`, or `rollout restart` in the lesson, not just here. The script does it on its own: before each `kubectl`, it compares the context and stops if it is not `kind-curso-k8s-l2`.

Now the scene's question. Your Docker has the image; does the node? Recall from Lesson 0 that a kind node is a container that carries its own `containerd` inside, and that `containerd` has its own image store. To ask it, you enter the node and use `crictl`, the command-line tool that talks to the node's runtime. kind's quick start guide recommends it for exactly this ([kind, "Quick Start", section "Loading an Image Into Your Cluster"](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)):

```text
$ docker exec curso-k8s-l2-worker crictl images | grep -c curso-docker-revisor
0
[código de salida: 1]
```

Zero. (The exit code 1 comes from `grep`, which is how it warns that it found nothing; it is not a node failure.) The image is on your machine and it is not on the node. They are two different stores, even though both live on the same computer, and nothing synchronizes them.

In a real cluster this is solved with a **registry**: you push the image to an image server (Docker Hub, your company's registry, or your cloud provider's) and each node downloads it from there. In kind, which is a laboratory on your machine, there is a shortcut: copy the image straight from your Docker into each node. That shortcut is `kind load docker-image` and it arrives in 2.4. First you will see what happens without it, because the error message is one of those you will meet most in your life with Kubernetes.

### 2.2 The `revisor`'s manifest, field by field

This is the manifest the lesson builds. It is a **program**: it applies on its own and lives in `programas/02-pods-deployments/revisor-deployment.yaml`.

```yaml
# revisor-deployment.yaml — Lección 2: el revisor con tres réplicas que renacen.
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
          value: "prueba http://prueba:9000/ 2s"
        # La imagen de Docker trae REVISOR_REPORTE=/datos/reporte.json: con el
        # sistema de archivos de solo lectura, /datos necesita un volumen. emptyDir
        # vive y muere con el Pod (la Lección 8 lo contrasta con un PVC).
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
        emptyDir:
          sizeLimit: 10Mi
```

It looks like a lot. It is read in layers, from the outside in, and each layer answers a question.

#### 2.2.1 What it is and what it is called

The first three keys are carried by every Kubernetes object. `apiVersion: apps/v1` says which API group the type lives in: Deployments live in the `apps` group, version `v1`, which is stable. `kind: Deployment` says the type. And `metadata` carries the name (`revisor`) and the Deployment's own labels (`app: revisor`). The name is unique within its namespace; labels, as you will see in 2.6, are not, and that is precisely their value.

#### 2.2.2 How many, which ones, and from what template

`spec` is the desired state, and in a Deployment it has three components that go together:

- **`replicas: 3`**: how many copies you want. It is the number the cluster chases.
- **`selector`**: how the Deployment recognizes **its** Pods. Here it says: "mine are the ones that carry the label `app: revisor`".
- **`template`**: the template for each Pod. It carries its own labels (`app: revisor`) and its own `spec`, which is a Pod's: containers, volumes, and security.

The selector and the template's labels **have to match**. If the template produced Pods with `app: otro` and the selector looked for `app: revisor`, the Deployment would create Pods it would never recognize as its own and would keep creating more, endlessly. That is why the `kube-apiserver` rejects a Deployment whose selector does not match its template's labels, before storing it. The [Deployments documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) adds a warning worth keeping in mind from now on: Kubernetes does not stop two controllers from having overlapping selectors, and if they do, "they might conflict and behave unexpectedly". Exercise 2 shows you a version of that problem.

#### 2.2.3 The container

Inside the template, `containers` is a list; in this course it always has a single container. Its fields:

- **`name: revisor`**: the container's name within the Pod. You will see it in events as `spec.containers{revisor}`.
- **`image: curso-docker-revisor:1.6.0`**: the image, with its fixed tag.
- **`imagePullPolicy: IfNotPresent`**: when to pull the image. `IfNotPresent` means "pull it only if it is not already on the node". The [images documentation](https://kubernetes.io/docs/concepts/containers/images/) also defines `Always` (ask the registry every time a container starts; the runtime only downloads the layers it is missing, but if the registry does not answer or does not have the image, it fails even though the node already has it) and `Never` (never try to pull it). If you omit the field, Kubernetes decides based on the tag: with a tag that is not `:latest` it sets `IfNotPresent`, and with `:latest` or no tag it sets `Always`. This is what makes `:latest` a trap in kind: with `Always`, the node would try to go to Docker Hub even though you had already loaded the image into it, and it would fail. The kind guide warns about it: with `:latest` or no tag the default policy is `Always`, and it asks you not to use `:latest` or to write `imagePullPolicy: IfNotPresent` (or `Never`) ([kind, "Quick Start"](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)). The manifest writes `IfNotPresent` even though it would be the default value, so whoever reads it does not have to know the rule.
- **`ports`**: declares that the container listens on 8080 and gives it a name, `http`. Declaring it publishes nothing and opens no port to the outside: it is information for whoever reads the manifest and for the objects that use it later. In Lesson 3, the Service will point to the port **by its name**, `http`, and not by its number.
- **`env`**: the environment variables. There is just one here, `REVISOR_SERVICIOS`, the one the `revisor` requires, with a service called `prueba` at `http://prueba:9000/` and a time limit of 2 seconds. That service does not exist in the cluster yet, and it does not matter: the `revisor` starts anyway and will report it with status `FALLA` when someone asks it for the report. In Lesson 4 this list leaves the manifest and moves to a `ConfigMap`.

#### 2.2.4 The `datos` volume

At the end there is a volume, `datos`, of type `emptyDir`, mounted at `/datos`. It is there for a concrete reason. The Docker course's image defines `REVISOR_REPORTE=/datos/reporte.json`: every time someone asks it for the report, the `revisor` saves it to that file. But the container's `securityContext` (2.2.5) makes **all** of its file system read-only. Without a volume, the `revisor` would start without complaint and fail later, the first time it tried to save a report: in its code, that case answers with a 500 error and the message `no pude guardar el reporte`.

An `emptyDir` is the simplest way to give it somewhere to write. The [volumes documentation](https://kubernetes.io/docs/concepts/storage/volumes/) describes it like this: it is created when the Pod is assigned to a node, starts empty, and "when a Pod is removed from a node for any reason, the data in the `emptyDir` is deleted permanently". If the container crashes and restarts, the data survives, because the Pod stays on the node. The `sizeLimit: 10Mi` puts a cap on it: a report weighs a few kilobytes, and a cap keeps a bug from filling the node's disk. Lesson 8 contrasts this `emptyDir` with a persistent volume and measures what is lost with each.

#### 2.2.5 The two `securityContext`s

There are two `securityContext` blocks: one at the Pod level (`template.spec.securityContext`) and another at the container level. The Pod's applies to all its containers; the container's, only to it. The section "The security habit of the lesson" takes them apart line by line, with the cluster showing what each one does. For now the idea is enough: the container runs as user 65532, cannot become `root`, has no special kernel capability, cannot write to its own file system, and is under the system-call filter that the runtime provides.

### 2.3 Applying and not finding the image

With the cluster freshly created and the image not loaded, the manifest was applied:

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created
```

Recall from Lesson 0 what that response means: the object was **stored**. It says nothing about containers. Twenty seconds later:

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS             RESTARTS   AGE
revisor-697fb84f97-gn68x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-qvs7x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-vq4ld   0/1     ImagePullBackOff   0          20s
```

The three Pods exist, each one already has a node, and none is running: `0/1` under `READY` means "zero of one container ready". The status, `ImagePullBackOff`, is Monday's scene. Notice what **did** work: the Deployment created its ReplicaSet, the ReplicaSet created three Pods, and the `kube-scheduler` spread them out. The whole control plane did its job. What failed is at the end of the chain, in each node's `kubelet`, which could not get the image.

The section "The error you will see" reads this error line by line. The short version, to keep going: the `kubelet` looked for the image on the node, did not find it, and, since the policy is `IfNotPresent`, tried to pull it. The image does not say which registry it comes from, so it went to Docker Hub, where it does not exist. It tries again, each time waiting a little longer. Deleting and applying again changes none of that: the new Pod lands on a node that does not have the image either and ends up in the same place.

### 2.4 `kind load docker-image`: carrying the image to each node

The remedy is to give the node what it asks for:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 --name curso-k8s-l2
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-control-plane", loading...
```

`kind` took the image out of your Docker and copied it inside **each** node of the cluster, one per line: "not yet on such-and-such node, loading". The control-plane node also appears, even though no `revisor` Pod runs there. kind does not know where you are going to use the image and puts it on all of them. It took 2 seconds, because the image weighs about 16 MB. The `--name curso-k8s-l2` is mandatory when the cluster is not called `kind`, which is the default name. Without it, kind would look for a cluster that does not exist, and on a machine with several clusters it is the way to be sure you are loading the image into yours and not another.

Now the node does have it:

```text
$ docker exec curso-k8s-l2-worker crictl images | grep curso-docker-revisor
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Look at the name it was stored under: `docker.io/library/curso-docker-revisor`. It is the full name corresponding to `curso-docker-revisor`: when an image does not say which registry it comes from, it is understood to be from Docker Hub (`docker.io`) and, if it does not say which user either, from its space of official images (`library`). The images documentation explains it with the example of `busybox`, which is equivalent to `docker.io/library/busybox:latest`. It is the same name that appeared in the 2.3 error, and that is why the `kubelet` now finds it. (The numbers look different, but there is an explanation. `crictl` says 3.68MB. With Docker Engine 29, `docker image ls curso-docker-revisor:1.6.0` shows two columns: `DISK USAGE` 16.2MB, what it takes up uncompressed on disk, and `CONTENT SIZE` 3.68MB, the compressed content; `crictl` reports the second. If your Docker is older, `docker image ls` shows a single figure and it may not match. The `crictl` identifier, `70e09194319be`, is not the `sha256:bd1b2e7d…` from `kind load` either: each tool identifies the image with a different digest. That it is the same image is proven by the name and the tag, and by the `kubelet` finding it in the next step.)

There is no need to apply anything again. The `kubelet` kept retrying on its own; on the next attempt it found the image and started the container:

```text
$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-gn68x   1/1     Running   0          33s   10.244.1.3   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   10.244.1.2   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   10.244.2.2   curso-k8s-l2-worker    <none>           <none>
```

This is the scene's underlying lesson: **the cluster recovered by itself because the desired state never changed**. It still said "three replicas with this image". The only thing missing was the image, and as soon as it arrived, each component finished its job. Deleting and applying again would have been, at best, useless.

Look at the `NODE` column. Two replicas ended up on `curso-k8s-l2-worker2` and one on `curso-k8s-l2-worker`. The Deployment takes care of **how many** replicas there are, not **where** they end up. Lesson 0 anticipated it: the *scheduler* tries to spread them out, but does not guarantee it, and on another run they may land differently. If `worker2` went down, two of the three replicas would die at once. A guaranteed spread is declared with its own rules, and the course does that when the `revisor` has to survive a node shutting down (Lesson 9). Notice also the `IP` column: each Pod has its own, and it changes every time a Pod is reborn. That is why nobody should talk to a Pod by its IP, and why Lesson 3 exists.

The `revisor`'s log confirms that the program started:

```text
$ kubectl logs deployment/revisor
Found 3 pods, using pod/revisor-697fb84f97-gn68x
revisor 1.6.0 escuchando en :8080 (1 servicio(s))
```

`kubectl logs deployment/revisor` is a shortcut: it picks one of the Deployment's Pods and shows you its log, and tells you which one it picked. It is the same line it printed with `docker run` in the Docker course: the image is the same, only who runs it changed.

### 2.5 The chain of owners: Deployment, ReplicaSet, and Pod

In Lesson 0 you saw the chain drawn. Now it can be read in the cluster itself, because each object says who its owner is in a field called `metadata.ownerReferences`. The [owners and dependents documentation](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) explains it this way: dependent objects have that field, which points to their owner, and Kubernetes fills it in automatically for objects created by controllers, such as ReplicaSets.

```text
$ kubectl get pod revisor-697fb84f97-gn68x -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ReplicaSet/revisor-697fb84f97

$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
Deployment/revisor

$ kubectl get deployment revisor -o jsonpath='{.metadata.ownerReferences}{"\n"}'

```

The Pod belongs to the ReplicaSet, the ReplicaSet belongs to the Deployment, and the Deployment belongs to no one: its answer is an empty line. You wrote the Deployment, and you are its owner.

The `-o jsonpath=…` option deserves a moment, because the course uses it a lot. `kubectl get` can return the complete object (`-o yaml`), but you almost always want a single value. `jsonpath` lets you ask for a field by its path: `{.metadata.ownerReferences[0].kind}` means "from the object, go into `metadata`, then into `ownerReferences`, take the first element, and give me its `kind`". The `{"\n"}` at the end just adds a line break.

Each link has a different job:

| Object | Created by | Its job | If you delete it |
|---|---|---|---|
| **Deployment** | you | store the desired state and manage versions: when you change the template, it creates a new ReplicaSet and moves the replicas from the old one to the new one | its ReplicaSets and its Pods are deleted; the service shuts down |
| **ReplicaSet** | the Deployment | count: make sure there are as many Pods with its exact template as `replicas` says | the Deployment creates an identical one, but `kubectl delete` deletes its Pods in cascade: measured, the three Pods went to `Terminating` at once and the replacement started from zero, with an outage; that is why they are not touched by hand |
| **Pod** | the ReplicaSet | run the container | the ReplicaSet creates another |

The [ReplicaSet documentation](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/) defines its purpose in one sentence: "to maintain a stable set of replica Pods running at any given time". And it recommends not using them directly: "we recommend using Deployments instead of directly using ReplicaSets", except in special cases. The Deployments one is even more blunt: "do not manage ReplicaSets owned by a Deployment". In this course you will never write a ReplicaSet. You will **see** them, because reading them explains what the Deployment does.

And the Pod? The [Pods documentation](https://kubernetes.io/docs/concepts/workloads/pods/) says it plainly: "you'll rarely create individual Pods directly in Kubernetes—even singleton Pods", because Pods are designed as "relatively ephemeral, disposable entities". Section 2.7 shows you what "disposable" means with a Pod that has no owner.

### 2.6 Labels and selectors

So far you have written `-l app=revisor` many times. It is time to see what is behind it.

A **label** is a key-value pair attached to an object. The [labels documentation](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) defines them as pairs "intended to be used to specify identifying attributes of objects that are meaningful and relevant to users", and adds what makes them useful: "unlike names and UIDs, labels do not provide uniqueness". Many objects carry the same one. With a label **selector** you choose a set of objects, and according to the same page, the selector is "the core grouping primitive in Kubernetes".

This is what the `revisor` Pods' labels look like:

```text
$ kubectl get pods --show-labels
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
revisor-697fb84f97-gn68x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
```

`app=revisor` you put there yourself, in the template. But there is another one you did not write: `pod-template-hash=697fb84f97`. The Deployment added it, and the number is the same suffix the ReplicaSet's name carries. Look at the ReplicaSet's selector:

```text
$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.spec.selector}{"\n"}'
{"matchLabels":{"app":"revisor","pod-template-hash":"697fb84f97"}}
```

The ReplicaSet does not look only for `app: revisor`: it looks for `app: revisor` **and** `pod-template-hash: 697fb84f97`. The Deployments documentation explains why: the Deployment controller adds that label to every ReplicaSet it creates, computed from a *hash* of the Pod template, and "this label ensures that child ReplicaSets of a Deployment do not overlap". When you change the template, in 2.8, another ReplicaSet with another *hash* will appear. Each one will count only its own Pods, even though they all carry `app=revisor`. The same page has a red warning: "do not change this label".

Selectors come in two forms. The **equality** form is the one you have used: `app=revisor`, or `app!=revisor` for the opposite. The **set** form asks about membership:

```text
$ kubectl get pods -l 'app in (revisor,prueba)' -o name
pod/revisor-697fb84f97-gn68x
pod/revisor-697fb84f97-qvs7x
pod/revisor-697fb84f97-vq4ld

$ kubectl get pods -l app=prueba
No resources found in default namespace.
```

The first asks for the Pods whose `app` label is `revisor` or `prueba`, and since there is no `prueba` yet, it returns only the `revisor` ones. The second confirms it. Two rules from the documentation so you do not get it wrong: several requirements separated by a comma are combined with "and" (`app=revisor,pod-template-hash=697fb84f97` requires both), and there is **no** "or" operator between different requirements. For an "or" over the same key there is `in`.

`No resources found` is not an error. It is an answer: nothing matches. Telling "there is nothing" apart from "something failed" is part of reading what the cluster says.

Why does the course always search by label and never by Pod name? Because the name changes every time the Pod is reborn, and the label does not. A command that writes `revisor-697fb84f97-gn68x` stops working as soon as that Pod dies. One that writes `-l app=revisor` keeps working across replacements, within the same namespace and as long as no other Pod uses that label (Exercise 2 shows what happens when one does). The Services in Lesson 3 choose their Pods the same way: by label. That makes what Exercise 2 shows important.

### 2.7 A bare Pod versus a Deployment's Pod

#### 2.7.1 The bare Pod

A Pod can be created on its own, without a Deployment. This manifest is a **program** (`fig02_01.pod.yaml`). It is the Deployment's same template, but written as a Pod, with a fixed name and **without** the `app: revisor` label, so that no ReplicaSet mistakes it for one of its own:

```yaml
# fig02_01.pod.yaml — un Pod suelto: el revisor sin Deployment que lo cuide.
# Sirve para ver qué hace un Pod por sí solo, y qué NO hace: si lo borras, nadie
# lo repone. No lleva etiqueta app: revisor a propósito, para que ningún
# ReplicaSet lo confunda con uno de los suyos.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-suelto
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
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
      value: "prueba http://prueba:9000/ 2s"
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
    emptyDir:
      sizeLimit: 10Mi
```

Notice the difference from the Deployment: `apiVersion: v1` (Pods live in the API's core group, which carries no name) and `kind: Pod`. What in the Deployment was inside `template.spec` is here directly in `spec`. A Deployment is, in large part, a Pod template with a counter on top.

```text
$ kubectl apply -f fig02_01.pod.yaml
pod/revisor-suelto created

$ kubectl get pod revisor-suelto -o jsonpath='{.metadata.name} dueños={.metadata.ownerReferences}{"\n"}'
revisor-suelto dueños=

$ kubectl delete pod revisor-suelto
pod "revisor-suelto" deleted from default namespace

$ kubectl get pods
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-gn68x   1/1     Running   0          40s
revisor-697fb84f97-qvs7x   1/1     Running   0          40s
revisor-697fb84f97-vq4ld   1/1     Running   0          40s
```

`dueños=` empty: nobody owns this Pod. It was deleted, the script waited five seconds, and `revisor-suelto` is gone. Nobody put it back, because no controller had "I want a `revisor-suelto`" in its desired state.

Watch what a bare Pod **does** do. If its **process** crashes, the `kubelet` starts it again inside the same Pod, because the `restartPolicy` field is `Always` by default ([kubernetes.io, "Pod Lifecycle"](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). It resembles a `docker run --restart always` on a single machine: it withstands the program crashing, and the `RESTARTS` column counts it. What it does not withstand is losing the Pod itself. The Pods documentation says a Pod stays on its node "until the Pod finishes execution, the Pod object is deleted, the Pod is evicted for lack of resources, or the node fails", and the lifecycle one adds that a Pod is never "rescheduled" to a different node: instead, someone can create a new, almost identical one. For a bare Pod, that someone does not exist. If it is deleted, evicted, or its node goes down, that is the end.

#### 2.7.2 The Deployment's Pod

Now the same with a Pod that does have an owner:

```text
$ kubectl delete pod revisor-697fb84f97-gn68x
pod "revisor-697fb84f97-gn68x" deleted from default namespace

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-nrwht   1/1     Running   0          1s
revisor-697fb84f97-qvs7x   1/1     Running   0          41s
revisor-697fb84f97-vq4ld   1/1     Running   0          41s

$ kubectl get events --field-selector involvedObject.kind=ReplicaSet,reason=SuccessfulCreate -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message
OBJETO               MENSAJE
revisor-697fb84f97   Created pod: revisor-697fb84f97-vq4ld
revisor-697fb84f97   Created pod: revisor-697fb84f97-gn68x
revisor-697fb84f97   Created pod: revisor-697fb84f97-qvs7x
revisor-697fb84f97   Created pod: revisor-697fb84f97-nrwht
```

One second later there is a new Pod, `nrwht`, and the events tell the story: three creations at the start and a fourth, the replacement. It is Lesson 0's thermostat, now with your program.

`-o custom-columns=…` is `jsonpath`'s sister for tables: you tell it which columns you want and which field each one comes from. It was used here so that each event fit on one line.

The comparison is the most important idea in the lesson: **the Pod runs, but whoever replaces it is its owner.** A Pod without an owner restarts its container if the process crashes, but the Pod itself is not reborn: if it is deleted, evicted, or its node is lost, that is the end. That is why, in this course, everything that must keep running lives inside a Deployment. Bare Pods appear only to debug or to demonstrate something, and are deleted when done.

### 2.8 The *rollout*: revisions, history, and restart

#### 2.8.1 What a revision is

A **rollout** is the move from one version of the Pods to another. The Deployments documentation says when it happens, and the rule is precise: a *rollout* is triggered "if and only if the Deployment's Pod template (that is, `.spec.template`) is changed", for example its labels or its image. Other changes, such as scaling from three to five replicas, do not trigger it. Each *rollout* leaves a **revision** in the history, and each revision is a ReplicaSet.

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
```

One revision: the one born with the `apply`. The `CHANGE-CAUSE` column says `<none>` because nobody recorded the reason. It can be filled in with a Deployment annotation; the course does not do so, because the reason for each change lives in the Git history of your manifests.

#### 2.8.2 Restarting without changing anything

Sometimes you want all the Pods to be replaced without changing the image or the configuration: for example, so they read again something that changed outside them. Deleting them by hand works, but you delete them all at once and the service is left without replicas for a moment. That is what `kubectl rollout restart` is for:

```text
$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

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
revisor-55cc969586   3         3         3       2s
revisor-697fb84f97   0         0         0       55s
```

Read the progress from `rollout status`: one of three new, two of three, and at the end "one old replica pending termination". The Pods were not replaced all at once: a new one was created and an old one removed, in turns. That is a Deployment's default strategy, `RollingUpdate`. Its two knobs are 25% if you do not touch them: `maxSurge`, how many extra Pods there can be during the change (rounded up), and `maxUnavailable`, how many can be missing (rounded down). With three replicas, 25% is 0.75: `maxSurge` ends up at 1 and `maxUnavailable` at 0. Put simply: during the change there can be up to four Pods, and the controller does not remove an old one until the new one is ready, so its plan never drops below three available. It is a promise of the controller, not of the universe: if a node goes down or a process dies at that moment, the count drops for reasons beyond its control. And with another number of replicas the rounding changes: with four, 25% is already 1 and `maxUnavailable` would be 1. Lesson 9 returns to this with real load and measures whether any request is lost.

And the result: a new ReplicaSet, `revisor-55cc969586`, with the three replicas, and the old one, `revisor-697fb84f97`, at `0 0 0`. The old one was **not deleted**: it was left empty, as a record of revision 1. The documentation says that, by default, 10 old ReplicaSets are kept (`revisionHistoryLimit`), and that deleting one means losing the ability to go back to that revision. Lesson 9 uses that ability with `rollout undo`.

Why was there a *rollout* if you changed nothing? Something did change:

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>


$ kubectl get deployment revisor -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
{"kubectl.kubernetes.io/restartedAt":"2026-10-21T03:55:53-06:00"}
```

`rollout restart` added to the template an annotation with the time of the restart. The template changed and the "if and only if" rule was met: new template, new *hash*, new ReplicaSet, revision 2. There is no magic, just the same rule applied to a field you set without typing it.

That annotation is not in your file, and that has a consequence. If tomorrow you apply `revisor-deployment.yaml` again, `kubectl apply` does not remove it, because it only manages the fields the file declares (Lesson 0 explained the `last-applied-configuration` annotation, which is how it keeps that count). This lesson's final state checks it with `kubectl diff`, which finds no differences.

## The error you will see

This lesson's error is the one from 2.3: `ErrImagePull`, which later becomes `ImagePullBackOff`. It was provoked on purpose and is read in order, because that order works for any Pod that does not start.

**First, the status.** `kubectl get pods` gave you `ImagePullBackOff` and `0/1`. The `STATUS` column tells you **at which stage** the Pod got stuck. A bare `Pending` usually means "it does not have a node yet" (the *scheduler* found no room; you will see it in Lesson 5). When there is something more concrete, `kubectl` shows that instead of the phase: `ImagePullBackOff` is "it already has a node, and that node's `kubelet` cannot get the image", and `CrashLoopBackOff` would be "the image started and the program crashes". One nuance: the Pod's **phase**, which is another field, is still `Pending` while the image downloads. The lifecycle documentation puts it this way: `Pending` includes the time waiting for a node to be assigned and "time spent downloading container images over the network" ([kubernetes.io, "Pod Lifecycle"](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). The phase is read with `kubectl get pod <pod> -o jsonpath='{.status.phase}'`. From the `STATUS` column alone you already know which component from Lesson 0 to ask.

**Second, the events.** The cluster keeps a record of every attempt:

```text
$ kubectl get events --field-selector reason=Failed -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message | head -4
OBJETO                     MENSAJE
revisor-697fb84f97-gn68x   Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
revisor-697fb84f97-gn68x   Error: ErrImagePull
revisor-697fb84f97-gn68x   Error: ImagePullBackOff
```

The first message is long, and it reads as a chain of "because", from left to right:

- `Failed to pull image "curso-docker-revisor:1.6.0"`: I could not pull the image you asked for…
- `failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0"`: …which, with its full name, is this one on Docker Hub…
- `failed to resolve reference`: …because I could not find that reference…
- `pull access denied, repository does not exist or may require authorization`: …because Docker Hub denied me access: the repository does not exist or asks for credentials.

The decisive clue is `docker.io/library/…`. The node went looking for your image on the internet. It never looked at your Docker, because it cannot: it is not its store. Docker Hub says "it does not exist or you need permission" and does not clarify which of the two. That is how registries behave, so as not to reveal which private repositories exist. Here it is the first: it does not exist.

**Third, `describe`.** `kubectl get events` mixes the events of the whole namespace. `kubectl describe pod` gathers everything about **one** Pod, and its events at the end. Careful: a repeated event is grouped into a single line and sorted by the **last** time it occurred, so `Pulling (x2 over 20s)` appears after `BackOff` even though it happened first:

```text
$ kubectl describe pod revisor-697fb84f97-gn68x | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned default/revisor-697fb84f97-gn68x to curso-k8s-l2-worker2
  Normal   BackOff    19s               kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     19s               kubelet            spec.containers{revisor}: Error: ImagePullBackOff
  Normal   Pulling    6s (x2 over 20s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
```

(The `sed` cuts the output to show only from `Events:`; above that, `describe` brings the image, the node, the volumes, the `securityContext`, and the Pod's conditions.) The `From` column says **who** is speaking, and it is the one that teaches you the most. In logical order:

- `default-scheduler`, `Scheduled`: the *scheduler* assigned the Pod to `curso-k8s-l2-worker2`. Its part went fine.
- `kubelet`, `Pulling`: that node's `kubelet` tried to pull the image. `(x2 over 20s)` means the same event happened twice in 20 seconds; the cluster groups repeated ones instead of writing them all out.
- `kubelet`, `Failed` with `ErrImagePull`: the attempt failed.
- `kubelet`, `BackOff` and `Failed` with `ImagePullBackOff`: the `kubelet` decided to wait before the next attempt.

**`ErrImagePull` and `ImagePullBackOff` are the same problem at two moments.** `ErrImagePull` is the failure of one attempt. `ImagePullBackOff` is the wait between attempts. The images documentation explains it: the `BackOff` part indicates that Kubernetes will keep trying, with a wait that grows on each attempt, up to a fixed limit of 300 seconds (5 minutes). That is why the Pod alternates between the two states as long as you do not give it the image. And that is why the recovery in 2.4 was not immediate for any Pod in the middle of a long wait: the `kubelet` picks up the image on its next attempt, not before. If a Pod has been waiting a long time and you do not want to wait, deleting it **after** fixing the cause does work: the ReplicaSet creates another, which tries immediately. Deleting **before** fixing it is what the team in the scene did.

**The order, for any Pod that does not start:** the status (`get pods`), the Pod's `describe` (its events and the `From` column) and, if the container managed to start, its `logs`. First you read, then you change something. And what you change is the cause, not the Pod.

## The security habit of the lesson: `securityContext` from the first manifest

The course's habits table assigns this lesson the first Deployment's `securityContext`: no `root`, no privilege escalation, no capabilities, read-only file system, and a `seccomp` profile. This is how it ended up applied in the cluster:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
{"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}
{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}
```

The first line is the Pod's; the second, the container's. Line by line, with what each one prevents:

| Line | What it does | What it prevents | Docker equivalent |
|---|---|---|---|
| `runAsNonRoot: true` | the `kubelet` refuses to start the container if it were to run as user 0 | a badly built image, or a badly written line, running as `root` without anyone noticing | none: Docker does not check |
| `runAsUser: 65532`, `runAsGroup: 65532` | sets the numeric user and group the process runs as | depending on what the image says; the number is written in the manifest | `--user 65532:65532` |
| `seccompProfile: RuntimeDefault` | applies the system-call filter that the runtime provides | the process using kernel calls that an HTTP server never needs. **Without this line, Kubernetes runs the container with no filter (`Unconfined`)**, unless the `kubelet` has the `seccompDefault` option enabled | Docker applies its default profile without you asking; Kubernetes does not |
| `allowPrivilegeEscalation: false` | a process cannot gain more privileges than its parent, for example by running a *setuid* binary | someone who gets into the container becoming `root` from inside | `--security-opt no-new-privileges` |
| `capabilities: drop: ["ALL"]` | removes all of the kernel's special capabilities | the process being able to, for example, change file ownership (`CHOWN`) or open raw *sockets* to forge network packets (`NET_RAW`) | `--cap-drop ALL` |
| `readOnlyRootFilesystem: true` | mounts the container's file system read-only | an attacker leaving tools behind or modifying the program | `--read-only` |

The definitions come from the official guide ["Configure a Security Context for a Pod or Container"](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/). On `allowPrivilegeEscalation`, for example, it says it "controls whether a process can gain more privileges than its parent process" and that it sets the kernel's `no_new_privs` flag. And the `seccomp` tutorial explains the difference from Docker that the table marks: if the `seccompDefault` option is enabled, Pods use `RuntimeDefault` when they ask for no other profile; "otherwise the default is `Unconfined`" ([kubernetes.io, "Restrict a Container's Syscalls with seccomp"](https://kubernetes.io/docs/tutorials/security/seccomp/)). That is why the line is always written.

There is a reference that matters more than any guide: the **Pod Security Standards**, the three security levels that Kubernetes defines ([kubernetes.io, "Pod Security Standards"](https://kubernetes.io/docs/concepts/security/pod-security-standards/)). The strictest, `restricted`, is described as a "heavily restricted policy, following current Pod hardening best practices". It requires four of these lines: running as non-`root` (`runAsNonRoot: true`), not allowing privilege escalation, dropping **all** capabilities (it only allows adding back `NET_BIND_SERVICE`), and explicitly setting the `seccomp` profile ("both the `Unconfined` profile and the absence of a profile are prohibited"). In addition, `restricted` forbids requesting `runAsUser: 0` (exactly what `fig02_02.raiz.yaml` does, further below) and only allows certain volume types, `emptyDir` among them. The `revisor`'s manifest meets all of that from today. When Lesson 7 puts the namespace at the `restricted` level, the `revisor` will already be ready, and nothing will have to be rewritten at the last minute.

`readOnlyRootFilesystem` is **not** required by `restricted`. The course includes it because the `revisor` can take it: its only write goes to `/datos`, and that is what the `emptyDir` is for.

**What is seen from inside.** The `revisor` image has no *shell*. It was checked:

```text
$ kubectl exec deployment/revisor -- /revisor healthcheck
sano

$ kubectl exec deployment/revisor -- /revisor version
1.6.0

$ kubectl exec deployment/revisor -- sh -c 'id'
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "d8ccff765090d70932ea2f15a41fa34693c57f56ad0106eeb012a0a816fa701d": OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH
[código de salida: 1]
```

`kubectl exec` runs a program inside a container that is already running, like `docker exec`. With `deployment/revisor`, it picks one of its Pods. The `revisor`'s own two subcommands work: `healthcheck` queries its `/salud` from inside and answers `sano`, and `version` says `1.6.0`. But `sh` does not exist: `executable file not found in $PATH`. That is not a defect, it is a defense. Whoever manages to execute something inside the container finds no *shell*, no `curl`, and no package manager. The way to debug without a *shell* arrives in Lesson 3: a separate Pod, made for that.

The container's mounts confirm the data volume and reveal something more:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.containers[0].volumeMounts}{"\n"}'
[{"mountPath":"/datos","name":"datos"},{"mountPath":"/var/run/secrets/kubernetes.io/serviceaccount","name":"kube-api-access-vxlgn","readOnly":true}]
```

`/datos` is your `emptyDir`. The second mount you did not write: Kubernetes mounted into the Pod a **credential** for talking to the `kube-apiserver`, that of the namespace's default service account. The `revisor` never talks to the API server, so it does not need it. It is recorded as known debt, with its lesson: Lesson 7 gives the `revisor` its own service account, with no permissions, and from then on all the course's accounts carry `automountServiceAccountToken: false`, so that credential is not mounted.

**The safety net in action.** `runAsNonRoot` seems redundant if you already wrote `runAsUser: 65532`. Its value appears when someone makes a mistake. This Pod (`fig02_02.raiz.yaml`, a **program** that fails on purpose) asks for both things at once: not to be `root` and to be user 0, which is `root`:

```yaml
# fig02_02.raiz.yaml — FALLA A PROPÓSITO: pide correr como root (runAsUser: 0)
# y a la vez exige no ser root (runAsNonRoot: true). El kubelet se niega a
# arrancar el contenedor. Es la red de seguridad de runAsNonRoot en acción.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-raiz
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 0
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: revisor
    image: curso-docker-revisor:1.6.0
    imagePullPolicy: IfNotPresent
    env:
    - name: REVISOR_SERVICIOS
      value: "prueba http://prueba:9000/ 2s"
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

```text
$ kubectl apply -f fig02_02.raiz.yaml
pod/revisor-raiz created

$ kubectl get pod revisor-raiz
NAME           READY   STATUS                       RESTARTS   AGE
revisor-raiz   0/1     CreateContainerConfigError   0          10s

$ kubectl get events --field-selector involvedObject.name=revisor-raiz,reason=Failed -o custom-columns=MENSAJE:.message | head -2
MENSAJE
Error: container's runAsUser breaks non-root policy (pod: "revisor-raiz_default(49586352-b84d-462b-9ded-e41bb2d2123a)", container: revisor)
```

The `kube-apiserver` accepted the Pod (`created`), because there is nothing invalid in its shape. The one that refused was the `kubelet`, when going to create the container: `CreateContainerConfigError`, "the container's configuration cannot be used", and the event says why: "the container's `runAsUser` breaks the non-`root` policy". The image was on the node and the program never got to run. That is the function of `runAsNonRoot`: a second key that does not depend on the first being written correctly. The Pod was deleted when done.

**What it protects against and what it does not.** The `securityContext` limits what **the process** can do if someone compromises it: not being `root`, not gaining privileges, not modifying its files. It does not protect the `revisor` from malicious requests (that is its code), it does not decide who can talk to it (that is the network, Lesson 7), and it does not protect your machine from the kind node, which, as you saw in Lesson 0, is a privileged container.

## Common mistakes

**Deleting and applying again in the face of an error.** It is Monday's scene. If the cause did not change, the new Pod reaches the same error. First you read the `describe`, then you fix the cause.

**Using `:latest` in kind.** With `:latest` or no tag, the default pull policy is `Always`, and the node tries to go to the registry even though you already loaded the image into it. Besides, `:latest` does not say which version runs: two nodes can have two different images with the same tag. Fixed tag and `IfNotPresent`.

**Forgetting `--name` in `kind load docker-image`.** Without it, kind looks for the cluster called `kind`. If it does not exist, it fails. If it exists and is not yours, you loaded the image in the wrong place and your cluster is still without it.

**Creating bare Pods for something that must keep running.** A Pod without an owner is not reborn. For a service, always a Deployment.

**Putting a Deployment's labels on a bare Pod.** You will see it in Exercise 2: the Deployment does not adopt it, but everything that searches by that label finds it. It is a Pod that shows up in counts and in traffic without anyone looking after it.

**Editing or deleting a Deployment's ReplicaSet by hand.** The Deployment is its owner and rebuilds it. The documentation says it in so many words: do not manage ReplicaSets owned by a Deployment.

**Touching the `pod-template-hash` label.** The Deployment sets it so its ReplicaSets do not step on each other. Changing it breaks that separation.

**Removing the `securityContext` "to make it work".** If a container does not start with the course's `securityContext`, the problem is almost always in the image (it runs as `root`, it writes where it should not) and is fixed in the image or with a volume, not by stripping defenses from the manifest.

**Trusting `Running`.** Without the `emptyDir`, the `revisor` would also be `Running` and `1/1`, and would fail on the first request that asked it to save the report. `Running` means the process is alive, not that it does its job well. Lesson 5 teaches the cluster to tell the difference.

## Exercises

The first three are run in the lesson's cluster, in order and from the state it was left in at the end of 2.8. Before each exercise, `kubectl config current-context` must say `kind-curso-k8s-l2`; if it says anything else, do not continue. `correr.sh` runs them the same way, and its output is in `correr.salida.txt`. **Before** running each one, write in the [log](bitacora.md) what you think will happen. The fourth is written in your own words.

### Exercise 1 — Take a Pod out of the flock

Choose one of the `revisor`'s Pods and change its `app` label to another value:

```bash
kubectl label pod <un-pod-del-revisor> app=fuera --overwrite
```

Predict: how many Pods are there five seconds later? Is the Pod you changed still running? Who is its owner now? Check it with `kubectl get pods -L app` (the `-L` option adds a column with that label's value) and with the `jsonpath` from 2.7.1, `-o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'`, which does work when the list of owners is empty (the `[0]` from 2.5 on an empty list prints just a slash, `/`, and exits with code 0, without warning that there was nothing). When you finish, delete the Pod you took out.

### Exercise 2 — The Pod that sneaks in (project)

`fig02_03.adoptado.yaml` is a bare Pod, `revisor-extra`, identical to the `revisor`'s and **with** the label `app: revisor`:

```yaml
# fig02_03.adoptado.yaml — Ejercicio 2: un Pod suelto que SÍ lleva app: revisor.
# Pregunta: el Deployment selecciona app: revisor. ¿Se queda con este Pod? ¿Borra
# uno de los suyos para seguir en tres? ¿Y qué ve quien busca por app=revisor?
apiVersion: v1
kind: Pod
metadata:
  name: revisor-extra
  labels:
    app: revisor
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
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
      value: "prueba http://prueba:9000/ 2s"
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
    emptyDir:
      sizeLimit: 10Mi
```

Before applying it, answer the three questions in its comment. Then apply it and check it with `kubectl get pods -l app=revisor`, `kubectl get deployment revisor`, and the ReplicaSets' selector. To finish, explain what problem this Pod would cause when, in Lesson 3, a Service chooses its Pods by `app: revisor`. Delete it when done.

### Exercise 3 — A tag that does not exist

`fig02_04.etiqueta-mala.yaml` is the same Deployment with a single difference: it asks for the image `curso-docker-revisor:1.6.9`, which exists neither in your Docker nor in the cluster. Before applying it, predict: how many `revisor` Pods are left running while the *rollout* is stuck? How many new Pods does it try to create? (Hint: the `maxSurge` and `maxUnavailable` numbers from 2.8.2.) Then apply it, wait with `kubectl rollout status deployment/revisor --timeout=40s`, and look at `kubectl get pods -l app=revisor` and `kubectl get deployment revisor`. To get out of the jam, apply `revisor-deployment.yaml` again and explain why the *rollout* finishes instantly.

### Exercise 4 — Defend the `securityContext`

A colleague proposes removing `readOnlyRootFilesystem: true` and the `datos` volume "because they are two things to maintain and the `revisor` starts anyway". In five sentences at most, answer them: what that line prevents, why the volume exists precisely because of it, what would happen to the report if you remove only the volume and keep the line, and whether removing it breaks the `restricted` level or not.

## Solutions

### Solution 1

Measured in `correr.salida.txt`:

```text
$ kubectl label pod revisor-55cc969586-6m76h app=fuera --overwrite
pod/revisor-55cc969586-6m76h labeled

$ kubectl get pods -L app
NAME                       READY   STATUS    RESTARTS   AGE   APP
revisor-55cc969586-6m76h   1/1     Running   0          8s    fuera
revisor-55cc969586-7tmfc   1/1     Running   0          7s    revisor
revisor-55cc969586-f8dk6   1/1     Running   0          6s    revisor
revisor-55cc969586-x6vfq   1/1     Running   0          5s    revisor

$ kubectl get pod revisor-55cc969586-6m76h -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=
```

**Four Pods.** The one you changed is still `Running`: changing a label does not stop it. But it stopped matching the ReplicaSet's selector, so the ReplicaSet **released** it (its `ownerReferences` ended up empty) and, since it now counted two where there should be three, created a new one. What remains are the three of the flock, plus one loose that nobody looks after. The ReplicaSet documentation describes this technique: you can remove Pods from a ReplicaSet by changing their labels, for example "for debugging and data recovery", and the ones you take out that way are replaced automatically. It is useful: you set aside a misbehaving Pod to study it, without the service losing a replica. But do not forget it there: the script deleted it when done.

### Solution 2

Measured in `correr.salida.txt`. (`fig02_03.adoptado.yaml` declares the `http` port, just like the Deployment's template. The field is informational and changes none of these outputs, but it matters for Lesson 3's traffic: that is why the Pod is identical to the Deployment's.)

```text
$ kubectl apply -f fig02_03.adoptado.yaml
pod/revisor-extra created

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running   0          13s
revisor-55cc969586-f8dk6   1/1     Running   0          12s
revisor-55cc969586-x6vfq   1/1     Running   0          11s
revisor-extra              1/1     Running   0          5s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           67s

$ kubectl get pod revisor-extra -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=

$ kubectl get replicaset -l app=revisor -o custom-columns=NOMBRE:.metadata.name,DESEADOS:.spec.replicas,SELECTOR:.spec.selector.matchLabels
NOMBRE               DESEADOS   SELECTOR
revisor-55cc969586   3          map[app:revisor pod-template-hash:55cc969586]
revisor-697fb84f97   0          map[app:revisor pod-template-hash:697fb84f97]
```

The three answers:

1. **It does not take it in.** `revisor-extra` still has no owner. The reason is in the ReplicaSet's selector: it does not look only for `app: revisor`, it also looks for `pod-template-hash: 55cc969586`, and `revisor-extra` does not carry that label. The ReplicaSet documentation says a ReplicaSet immediately adopts an ownerless Pod that matches **its** selector, and that is why bare Pods should not carry labels that match a ReplicaSet's selector. Here the `pod-template-hash` label prevented the adoption.
2. **It deletes none of its own.** The Deployment says `3/3`: for it, only its three exist.
3. **Whoever searches by `app=revisor` sees four.** `kubectl get pods -l app=revisor` lists `revisor-extra` as if it were one more replica.

That third point is the problem. A Service, in Lesson 3, chooses its Pods by label, and by the manifest's, `app: revisor`, not by `pod-template-hash`, and it points to the port named `http`. This bare Pod carries both things: the label and the port with that name. So this Pod, which nobody replaces if it dies and nobody updates when you change the image, would receive its share of the traffic as if it were one more replica. It is exactly what the documentation means when it warns that overlapping selectors produce unexpected behavior. The script deleted it when done.

### Solution 3

Measured in `correr.salida.txt`:

```text
$ kubectl apply -f fig02_04.etiqueta-mala.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS         RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running        0          55s
revisor-55cc969586-f8dk6   1/1     Running        0          54s
revisor-55cc969586-x6vfq   1/1     Running        0          53s
revisor-b8b699487-fc4gn    0/1     ErrImagePull   0          41s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     1            3           109s
```

**Three old Pods keep running and there is a single new Pod, stuck in `ErrImagePull`.** With three replicas, `maxSurge` is 1 (there can be one extra Pod) and `maxUnavailable` is 0 (none can be missing). The Deployment created a new Pod and, to remove an old one, waited for the new one to be available. It never was, so it removed none. `kubectl get deployment` sums it up: `READY 3/3` (the service is still complete), `UP-TO-DATE 1` (only one replica has the new template). **Here, a *rollout* with a broken image does not bring the service down**: it gets stuck with the service intact, because with three replicas `maxUnavailable` is 0. It is not a law: with four replicas 25% is already 1 and the Deployment would indeed remove a healthy replica before knowing whether the new one starts, and if an old Pod falls while the *rollout* is stuck, the capacity drops. `rollout status` gave up after 40 seconds because you asked it to; the Deployment, on its own, would wait 600 seconds (`progressDeadlineSeconds`, whose default value according to the documentation is 600) before marking the *rollout* as failed with the `ProgressDeadlineExceeded` condition.

When applying the good file again:

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           109s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-55cc969586   3         3         3       56s
replicaset.apps/revisor-697fb84f97   0         0         0       109s
replicaset.apps/revisor-b8b699487    0         0         0       41s
```

It finished instantly because the template was **identical** again to that of the ReplicaSet `revisor-55cc969586`: the same image and the same `restartedAt` annotation, which `apply` does not remove because the file does not declare it. Same template, same *hash*, same ReplicaSet. The Deployment did not create a new one: it brought the broken one, `revisor-b8b699487`, down to zero, and since the good one already had its three replicas, there was nothing more to do. Going back to the previous version with `kubectl rollout undo` is the short way to do this, and it arrives in Lesson 9. Here it was done the way the course teaches: the file is the truth, and you apply it again.

### Solution 4

One possible answer: "`readOnlyRootFilesystem` prevents someone who gets into the container from modifying the program or leaving tools behind, and it is cheap because the `revisor` writes only one file. It is precisely because of that line that the `datos` volume exists: it is the only place where the `revisor` can write its report. If you remove the volume and keep the line, the `revisor` starts and looks `Running`, but the first time it tries to save a report it answers 500 with `no pude guardar el reporte`. Removing the line does not break the `restricted` level, which does not require it, but you give up a defense that costs nothing. And 'it starts anyway' is not the test: what matters is whether it keeps working when someone attacks it and when someone asks it for work."

## Deleting the cluster

When you finish the exercises, delete the lesson's cluster. Leave nothing alive on the machine:

```text
$ kind delete cluster --name curso-k8s-l2
Deleting cluster "curso-k8s-l2" ...
Deleted nodes: ["curso-k8s-l2-worker" "curso-k8s-l2-worker2" "curso-k8s-l2-control-plane"]

$ kind get clusters | grep -c curso-k8s-l2
0
```

The `--name` is mandatory here too: without it, kind would delete the cluster called `kind`, which may belong to someone else or to another project. Then, delete the `kubeconfig`'s temporary folder (the one `mktemp` created, with the prefix `/tmp/curso-k8s-l2.`) or close that terminal. The next lesson's cluster is created from scratch, just like this one.

## How I know I succeeded

- [ ] Faced with `ImagePullBackOff`, you say which component failed (the node's `kubelet`) and why the message mentions `docker.io/library/…`, without looking it up.
- [ ] You check with `docker exec <node> crictl images` whether an image is on a kind node, and you load it with `kind load docker-image <image> --name <cluster>`.
- [ ] You write from memory a Deployment's skeleton and explain why `selector` and `template.metadata.labels` must match.
- [ ] You predict what happens when you delete a bare Pod, a Deployment's Pod, and the whole Deployment.
- [ ] You explain what the `pod-template-hash` label is for and why the Pod in Exercise 2 was not adopted.
- [ ] You justify each line of the `revisor`'s `securityContext` and say which ones the `restricted` level requires.
- [ ] You run `programas/02-pods-deployments/correr.sh > /tmp/mi-corrida-l2.txt 2>&1` and compare `/tmp/mi-corrida-l2.txt` against `programas/02-pods-deployments/correr.salida.txt` (do not redirect to that file: it is the reference) in what does not change between runs: three nodes `Ready` at `v1.37.0`; `0` `revisor` images on the node before loading it; the three Pods in `ImagePullBackOff` and the `pull access denied` event with `docker.io/library/curso-docker-revisor:1.6.0`; the three `not yet present on node … loading...` lines, one per node, including the control-plane one; `deployment.apps/revisor 3/3`; `revisor 1.6.0 escuchando en :8080 (1 servicio(s))`; `sano` and `1.6.0`; `executable file not found in $PATH`; the `securityContext` in JSON; `CreateContainerConfigError` with `breaks non-root policy`; two revisions in `rollout history` and the old ReplicaSet at `0 0 0`; and at the end `sin diferencias con el archivo`. The name suffixes, the IPs, which node each Pod lands on, the ages, the order of the `kind load` lines, and the number of times each `rollout status` line repeats change on every run: they are observed, not compared.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l2`.

## Summary

Answer without looking at the lesson:

1. Why does a kind node not see your Docker's images, and what does `kind load docker-image` do?
2. What is the difference between `ErrImagePull` and `ImagePullBackOff`? How long does the `kubelet` end up waiting between attempts?
3. What three components does a Deployment's `spec` have, and what happens if the selector does not match the template's labels?
4. Who owns whom in the Deployment, ReplicaSet, and Pod chain, and in which field is it read?
5. What does a ReplicaSet do with a Pod whose selector label you remove?
6. When is a *rollout* triggered? Why does `rollout restart` trigger one if you changed nothing?
7. With three replicas and the default values, how many Pods can there be during a *rollout* and how many can be missing?
8. What does `runAsNonRoot: true` prevent that `runAsUser: 65532` does not already prevent?
9. Why does the `revisor` need an `emptyDir` at `/datos`?

## Sources

All consulted on October 21, 2026.

- [kind, "Quick Start"](https://kind.sigs.k8s.io/docs/user/quick-start/), section "Loading an Image Into Your Cluster": `kind load docker-image`, the `--name` option for named clusters, `crictl images` inside the node, and the warning about `:latest` and the pull policy.
- [Kubernetes, "Images"](https://kubernetes.io/docs/concepts/containers/images/): the `IfNotPresent`, `Always`, and `Never` policies; the default policy depending on the tag; Docker Hub as the default registry (`docker.io/library/…`); and `ImagePullBackOff`, with its growing wait up to 300 seconds.
- [Kubernetes, "Deployments"](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): when a *rollout* is triggered; `maxSurge` and `maxUnavailable` (25%, with their rounding); `revisionHistoryLimit` (10); `progressDeadlineSeconds` (600) and `ProgressDeadlineExceeded`; the `pod-template-hash` label; the warning not to manage a Deployment's ReplicaSets and the one about overlapping selectors.
- [Kubernetes, "ReplicaSet"](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/): its purpose; the adoption of ownerless Pods that match its selector; the recommendation to use Deployments; and how to remove Pods from a ReplicaSet by changing their labels.
- [Kubernetes, "Pods"](https://kubernetes.io/docs/concepts/workloads/pods/): why individual Pods are rarely created and how long a Pod stays on its node.
- [Kubernetes, "Pod Lifecycle"](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): `restartPolicy` is `Always` by default; the `Pending` phase includes image downloads; a Pod is never rescheduled to another node.
- [Kubernetes, "Restrict a Container's Syscalls with seccomp"](https://kubernetes.io/docs/tutorials/security/seccomp/): without `seccompDefault`, the default profile is `Unconfined`.
- [Kubernetes, "Owners and Dependents"](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/): the `ownerReferences` field.
- [Kubernetes, "Labels and Selectors"](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/): what a label is, that it is not unique, the equality and set selectors, and the absence of an "or" operator.
- [Kubernetes, "Volumes"](https://kubernetes.io/docs/concepts/storage/volumes/), `emptyDir` section: when it is created, when it is deleted, and `sizeLimit`.
- [Kubernetes, "Configure a Security Context for a Pod or Container"](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): each `securityContext` field and what it controls.
- [Kubernetes, "Pod Security Standards"](https://kubernetes.io/docs/concepts/security/pod-security-standards/): the `restricted` level and its rules on non-`root`, privilege escalation, capabilities, and `seccomp`.

---

**Next:** [Lesson 3 — Services and DNS](03-services-dns.md)
