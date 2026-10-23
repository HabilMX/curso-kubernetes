# Lesson 10 — The finished project and what changes in a real cluster

Monday, 7:50 in the morning. At 9:00 there is a meeting with management and the `revisor` is the demo. You open your laptop and the cluster is gone: over the weekend, somebody updated Docker, somebody else cleaned up images and containers “that were no longer in use”, and `kind get clusters` answers with an empty list. You have the manifests, which are in Git, and you have the wiki page you wrote a month ago: “To bring it up, `kubectl apply -k .`”. You try it. The first command tells you `no matches for kind "IPAddressPool"`. You repeat it and now it says `failed calling webhook`. You repeat it a third time and almost everything is created, but the Gateway is left without an address, and you do not know whether something is missing or whether the time simply has not passed yet. By 8:35 you have a cluster that *almost* works, a wiki that does not state the order because when you wrote it the order “just worked out”, and the uncomfortable suspicion that, if someone asks “can you bring it up again?”, the honest answer is “I think so, if I repeat it a few times”.

That answer is not an answer. A project is finished when anyone (you in six months, a new colleague, an automated *pipeline* step) can start from an empty cluster, run a short recipe and end up in the same place, without fixing anything by hand and knowing what to expect between one step and the next. This is the last lesson of the course and it does two things. The first: it gathers everything you built in the previous nine into a structure that comes up with **two commands and a wait**, using **Kustomize** (a base and layers on top of it), and automates it with a script that **does not hide the order**. The second is less comfortable and therefore the more important: it tells you, plainly, **what all this still lacks to be more than a lab**.

**Time:** 2 × 45 min

**What you build:** the complete `revisor` (the nine lessons together) organized into one base and two Kustomize layers (the platform and the project), which comes up from an empty cluster with two `kubectl apply` commands and a wait, and which a script repeats, deletes and repeats again without you fixing anything by hand; plus a written list of what it still lacks to run for real

**What you learn:** what a base and an *overlay* are in Kustomize, and how to read what they assemble; why the platform (new types, controllers and *webhooks*) goes before the project, and what the cluster says when that order is broken; what `kubectl apply --server-side` is and which error it avoids; how to wait without `sleep` (with `kubectl wait`) and how to automate the bring-up without hiding the order; the project's final review against the `restricted` level, field by field; the tests of the course goals (a node that goes down, a configuration that changes, a foreign Pod, an autoscaling that reads metrics); what Helm is and when it is preferable to Kustomize; and what changes, and what is lost, between a `kind` cluster and a real one

**Where you are coming from.** From the previous nine lessons, which now read as layers of one building. From [Lesson 2](02-pods-deployments.md): the Deployment, the `securityContext` and the images loaded with `kind load`. From [Lesson 3](03-services-dns.md): the Services and the `depurar` Pod. From [Lesson 4](04-configuracion-secretos.md): Kustomize with generators and the *hash* that triggers the *rollout*. From [Lesson 5](05-salud-recursos-apagado.md): the probes, the `requests` and the `limits`. From [Lesson 6](06-entrar-al-cluster.md): MetalLB and Envoy Gateway, and the idea that the platform goes before the project; this lesson turns that idea into the folder structure. From [Lesson 7](07-aislar-permisos-red.md): the `revisor` namespace at the `restricted` level, the accounts with minimal permissions and the closed network. From [Lesson 8](08-datos-y-tareas.md): the volume and the report `CronJob`. From [Lesson 9](09-escalar-y-actualizar.md): `metrics-server`, automatic scaling and the shutdown with `preStop`. If any of the nine was left half-done, the table in 10.2 tells you in which file each piece lives.

**What this lesson does not do.** It teaches nothing new about the `revisor`: everything it contains you have already built. It does not install Helm or run it: it names it, compares it with Kustomize and tells you when you would have to use it. It does not turn the cluster into a production one: that is exactly what it does **not** do, and section 10.10 explains why in each case. And it does not repeat the long measurements of lessons 6 and 9 (how long scaling takes to go up and down, how MetalLB behaves up close): it uses them, and points you to those lessons for the detail.

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1 (`kubectl version --client` says `Kustomize Version: v5.8.1`), the `kindest/node:v1.37.0` node image pinned by its digest, **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** (with Gateway API v1.6.1) and **metrics-server v0.9.0**, on the three-node cluster from Lesson 1, called `curso-k8s-l10` here. The machine was an ARM-based Mac with Docker Engine 29.2.1 inside a Linux virtual machine (Colima), **not** Linux Mint, which is the course's reference system. What changes on your Mint: the architecture (`amd64` instead of `arm64`); the IPs of the Pods, the Services and the nodes; the random suffixes in the names, the ages and which node each replica lands on; and, above all, the times, which depend on your connection (the nodes download the platform images from the internet) and on the load of the machine. **One network difference matters:** this run used a **Docker network of its own**, `curso-k8s-red-l10` (`172.30.0.0/16`), created with `docker network create --subnet 172.30.0.0/16 curso-k8s-red-l10` before the first cluster and deleted after the last one, and each cluster was created with the variable `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l10`. It was done this way because the machine was shared and other lessons were also installing MetalLB: two clusters with the same range on the same network step on each other. `kind` warns about it in the creation output with `WARNING: Overriding docker network…` and `Here be dragons! This is not supported currently` (the variable is experimental). On your machine, with the normal `kind` network (`172.18.0.0/16` on Mint), you need none of that, and the entry point's addresses come out as `172.18.255.x`: change the range in `overlays/kind/metallb-pool.yaml` to `172.18.255.200-172.18.255.250` (10.1.1 and 10.6.2 explain why) and, where the outputs say `172.30.255.200`, you will read `172.18.255.200`. The “outside” clients in the outputs connected to the dedicated network; on your machine, to `kind`. The complete walkthrough is in [`programas/10-proyecto-final/`](../programas/10-proyecto-final): `correr.sh` creates a cluster, triggers the two errors of 10.4 (each in a new cluster), creates another one and goes through 10.1 to 10.8 and Exercises 1 to 3, deletes it, and finishes with `probar-levantar.sh` (two more clusters). In total, five clusters, one at a time, and all five were deleted. Its output is `correr.salida.txt` (the three earlier runs cited in 10.8.3 and in Exercise 3 are in `corridas-preparacion/`; `psa-comprobacion.sh` and `crd-tamanos.sh`, with their `.salida.txt` files, are two standalone measurements cited in 10.7.3 and 10.4.3); you will see some “espera de cupo” (waiting for a slot) lines there, which are the script waiting for another lesson to free a place on the shared machine. The complete run took 1,755 seconds (almost half an hour), of which about 6 minutes were those waits. Creating a cluster, waiting for the nodes and loading the images took between 35 and 60 seconds; the platform wait took 153 seconds in the cluster of 10.5, and in `probar-levantar.sh` step 2 finished 234 and 250 seconds after the script started (the wait itself, about 229 and 246); in one of the preparation runs, that same wait reached 881 seconds (it is in `programas/10-proyecto-final/corridas-preparacion/corrida4.txt`). It needs internet.

## By the end you will be able to

- Explain in your own words what a **base** and an ***overlay*** are in Kustomize, open a `kustomization.yaml` and say which resources it assembles, what it changes in them and how to check it with `kubectl kustomize` without touching the cluster.
- Tell a **platform** piece (new types, controllers, *webhooks*) from a **project** piece, and bring both up from an empty cluster with two `kubectl apply --server-side -k` commands and a wait with `kubectl wait`, in the right order.
- Recognize and read the two errors you get from breaking that order: the one from applying the platform without `--server-side` and the one from putting platform and project into a single command.
- Write a bring-up script that does not hide the order (three named steps, a context check before each one and waits on a condition, not on time) and test it by creating, deleting and recreating the cluster.
- Review the project against the `restricted` level of the *Pod Security Standards*, field by field and with the cluster, and explain why the platform lives in namespaces that do not meet it.
- Measure what happens when a worker node is stopped (what fails, for how long and why) and say what shortens that window and what does not.
- Write, in your own words, five reasons why what you built is not a real cluster and what would be done about each one.

## The why before the how

Until now each lesson left the cluster *a little further* from where it started: more files, more pieces, more things to apply. That accumulation is normal while you are learning, and it has a cost that is not visible until the Monday in the opening scene: nobody wrote **in a single place** how to bring everything up. The lessons do say it, each in its own way; but a project that can only be rebuilt by rereading nine lessons is not finished.

There is a real case that shows why it matters, and it is not about Kubernetes. On January 31, 2017, a GitLab engineer mistakenly deleted the data directory of GitLab.com's main database: about 300 GB, according to the public report the company published on February 10. What turns that story into a lesson for us is what came afterwards. On paper, the company had several backup and recovery mechanisms, and when they went looking for them, the report says (translated): “the process of finding and using the backups failed completely”. The daily `pg_dump` backup did not exist: the storage folder was empty, because the program that made it was from a different version than the database and ended with an error, and the emails that warned about that error were rejected by the destination server, so nobody found out until it was too late. Recovery was done with a copy taken six hours earlier for another reason, and copying it from the staging environment took about 18 hours. The changes made between 17:20 and around midnight (UTC; the report gives 23:30 in the detail and 00:00 in the summary) of that day were lost: by their estimate, about 5,000 projects, 5,000 comments and 700 new accounts.

It did not happen for lack of recipes. It happened because **nobody had noticed they did not work**: the backup was failing and nothing warned anyone. A recovery recipe that nobody has run from start to finish is a hypothesis, just like “I think so, if I repeat it a few times”. That is why this lesson does not stop at writing the recipe: it **runs** it, breaks it on purpose, deletes it and repeats it on a new cluster, and teaches you to do it yourself.

The lesson has ten parts of concepts and then the usual sections:

1. **The lesson's cluster** (10.1): creating it with its own `kubeconfig` and its context guard.
2. **The folder map** (10.2): what is in `programas/10-proyecto-final/` and which lesson put in each piece.
3. **Kustomize: base and *overlays*** (10.3): how it is assembled, how it is read and how it is checked.
4. **Why two commands and a wait** (10.4): the two errors that teach the order.
5. **Bringing it up by hand** (10.5): platform, wait, project, and seeing it work from the outside.
6. **Automating without hiding the order** (10.6): `levantar.sh` and the create, delete and recreate test.
7. **The final review against `restricted`** (10.7).
8. **Testing the goals** (10.8): the node that goes down, the configuration that changes, the foreign Pod, the scaling.
9. **Helm, in a mention** (10.9).
10. **What changes in a real cluster** (10.10): the list of what is missing.

This is the destination. At the end of 10.5, an empty cluster has the complete project, and the entry point you built in Lesson 6 receives an address that MetalLB handed out to it:

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

(That table is long on purpose: it is the proof that the nine lessons are all there. You will read it row by row in 10.5.)

## If you don't have the Docker course images

This lesson uses the same two images as Lessons 3 to 9: `curso-docker-revisor:1.6.0`, the `revisor`'s, and `curso-docker-prueba:1.0.0`, the one for the service that fails on purpose. Check that you have them:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

For the other one, the same command with `curso-docker-prueba:1.0.0`. If either is missing, [Lesson 3](03-services-dns.md) tells you how to build them from the Docker course repository. This lesson asks nothing new of either image. What is new comes from the internet: the MetalLB, Envoy Gateway and `metrics-server` manifests are downloaded from their releases every time you apply the platform, and the images of those three components and the `curl` one are downloaded by each node the first time. You need a connection.

## The concepts

### 10.1 The lesson's cluster

#### 10.1.1 Before creating: the slot, the network and the disk

This lesson installs **MetalLB**, like Lesson 6, and it brings along its rule of coexistence: MetalLB hands out IP addresses from the Docker network where the `kind` nodes live, and two clusters with MetalLB and the same range, on the same network, announce the same addresses and step on each other. If you work alone on your machine, this does not concern you: you will have one cluster at a time. If you share the machine with someone, or if you have another course cluster alive, check before creating:

```bash
# ¿Hay otro clúster del curso vivo? Si lo hay y tiene MetalLB, espera a que termine.
kind get clusters
# Espacio de tu disco: si el uso pasa de 80 %, libera lo tuyo antes de seguir.
df -h /
# Cuánto ocupa Docker (imágenes, contenedores, volúmenes), para saber qué liberar.
docker system df
```

`kind get clusters` lists the clusters `kind` knows about on your machine. If you see `curso-k8s-l10` and you did not create it, stop: it belongs to someone else. `df -h /` tells you what percentage of your disk is used (the `Use%` column); `docker system df` does not give percentages: it summarizes how much space Docker's images, containers and volumes take up, and it is used to find out what to free. This lesson creates several clusters, one at a time, and each downloads the platform images: there is no measured figure for the space, so leave some headroom.

And a note about **the network**, which decides the address range, because it shows up in a file of this lesson. By default, `kind` creates a Docker network called `kind` and puts all the nodes there. On Linux Mint, that network is usually `172.18.0.0/16`. Check it:

```bash
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

The `overlays/kind/metallb-pool.yaml` file that comes with the folder says `172.30.255.200-172.30.255.250`, the range of the dedicated network with which this lesson's runs were made (“About the runs” explains it). That is why, **even if your network is `172.18.0.0/16`, you have to change that range yourself**: to `172.18.255.200-172.18.255.250` if your network is the usual one, or with your network's prefix if it is another `/16`. It is **one line** in one file, and 10.6 shows you a script that checks that the range falls inside the network before applying anything (if you do not change it, it stops with an `ALTO` and tells you so).

#### 10.1.2 Creating the cluster

Create it from `programas/10-proyecto-final/`, with the same care as always: a temporary `kubeconfig` of your own, a function that checks the context before every change, and the images loaded.

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

Two things that are not new but that this lesson uses more than any other. The first: `ctx` is a **shell function**, not a program. If `kubectl config current-context` does not say `kind-curso-k8s-l10`, it prints “contexto equivocado: no sigo” (“wrong context: I am not continuing”) and returns an error; the `&&` makes the command on the right **not run** when the function fails. That is why, from here on, every command that **changes** something is written `ctx && kubectl apply …`. A command that only reads (`get`, `describe`) does not need it, but it does not get in the way either. The second: the `export` only applies in that terminal. If you open another one, repeat the `export KUBECONFIG=…` with the path the `echo` printed, and define `ctx` again.

And this lesson has something the earlier ones do not: **a dummy token that the generated Secret is going to read** (Lesson 4). It is created once, with permissions for you only, and it is not versioned (the folder's `.gitignore` excludes it):

```bash
(umask 077; openssl rand -hex 16 > base/token.txt)
TOKEN="$(cat base/token.txt)"
```

The parentheses make the `umask 077` apply only to that command, and the file is born with permission `0600` (`-rw-------`): readable only by you. We check it:

```text
$ /bin/ls -l base/token.txt | cut -d' ' -f1
-rw-------

$ wc -c < base/token.txt
      33
```

The 33 bytes are the thirty-two hexadecimal characters from `openssl rand -hex 16` plus the line break. And the state of the freshly created cluster, with its three nodes and the two images already inside:

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

Six `not yet present on node … loading...` lines: two images times three nodes, the control-plane one included. But “loading” is not proof that the image arrived. A check worth turning into a habit is asking each node which images it has, with `crictl`, the container *runtime* tool you already used in Lesson 2:

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

Each of the three nodes lists the two images, with the tag you gave them (`1.6.0` and `1.0.0`). `crictl` prefixes them with `docker.io/library/` because that is the name `containerd` gives to an image without a registry, and it does not mean they were downloaded from there. The `IMAGE ID` column (`70e09194319be`, `5f32d8833d958`) does not match the one `docker image ls` shows on your machine (`bd1b2e7d91b8` for the `revisor`): they are two different stores and each identifies the image in its own way. The same goes for the size: `crictl` says 3.68 MB for the `revisor` and Docker says 16.2 MB; each tool measures differently and they are not compared with each other. What does matter is that the name and the tag are on **every** node: if it is missing on one, a Pod that lands there will try to pull the image from the internet and will stay in `ErrImagePull`, as in Lesson 2, and this is the query that explains it.

**A warning about `kind load`.** If you pulled the image from a registry, do not load it with `kind load docker-image repo@sha256:…`. In the tests of Hábil's Docker course (kind v0.33.0, Docker 29.2.1 with the containerd image store, arm64 processor), that command answered “loading…” without an error and the image **did reach the node, but without a name**: `docker exec <node> crictl images` showed it as `docker.io/library/import-YYYY-MM-DD` with tag `<none>` (the placeholder name that `ctr images import` gives to whatever it imports without a reference of its own; the date is the node clock's, in UTC), and a Pod that asked for the same reference with a *digest* ended up in `ErrImageNeverPull`, because the node has no image with that name even though its content is there. Give it a local tag first (`docker tag repo@sha256:… curso-docker-revisor:1.6.0`), load that tag and always check with `crictl images`, **looking at the `<none>` rows too**: a filter that only lets your image's name through (like the `grep -E 'IMAGE|curso-docker'` above) does not show them. This is a measured case with no official source for that exact symptom; the kind *issues* [#4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) and [#4224](https://github.com/kubernetes-sigs/kind/issues/4224) describe neighboring failures (with an error) of `kind load` with recent Docker, most of them tied to Docker's `containerd` image store (#3795 and #4066; #4224 is on OrbStack). The two images in this lesson are loaded by their local tag (`curso-docker-revisor:1.6.0`, `curso-docker-prueba:1.0.0`), and the output above is the check.

The empty cluster has no object types other than those Kubernetes ships with. We check it, because it is the starting point for everything that follows:

```text
$ kubectl get crd
No resources found
```

`crd` is the abbreviation of *CustomResourceDefinition*, the definition of a new object type (you saw it in Lesson 6). “No resources found” means the cluster only knows the types it was born with. Neither `Gateway`, nor `IPAddressPool`, nor `HTTPRoute` exist yet. That emptiness is what the order in 10.4 has to fill.

### 10.2 The folder map

#### 10.2.1 What is there and which lesson put it there

The `programas/10-proyecto-final/` folder has three things: the **base** (the project), the **overlays** (how it is installed on a specific cluster) and the **scripts** (how it is brought up). This is how the files of the first two look:

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

(`find` walks the folders and lists files; `! -name token.txt` leaves out the token and `sort` orders them. `.gitignore` shows up because `find` does not hide files that start with a dot.)

Each file in the base is a lesson you have already done. This table is the map; if something was left half-done, here is where to look:

| File | What it is | Which lesson it comes from |
|---|---|---|
| `base/namespace.yaml` | the `revisor` namespace, at the `restricted` level with the policy version pinned | 7 |
| `base/cuentas.yaml` | the service accounts with no mounted credentials and the read-only role `observador` | 7 |
| `base/red.yaml` | the six `NetworkPolicy` objects: everything closed and only the necessary openings | 7 |
| `base/revisor-deployment.yaml` | the `revisor`: image, variables, token as a file, probes, resources, graceful shutdown, spreading across nodes and `securityContext` | 2, 4, 5, 7, 9 |
| `base/revisor-service.yaml` | the stable name `revisor` inside the cluster | 3 |
| `base/prueba-deployment.yaml` and `base/prueba-service.yaml` | the test service that fails on purpose | 2, 3, 5, 7 |
| `base/gateway.yaml` | the entry point (`Gateway`) and the route (`HTTPRoute`) | 6 |
| `base/reporte.yaml` | the report volume and the `CronJob` that stores it | 8 |
| `base/escalado.yaml` | automatic scaling (`HorizontalPodAutoscaler`) and the `PodDisruptionBudget` | 9 |
| `base/kustomization.yaml` | the generators of the `ConfigMap` and the `Secret` with a *hash*, and the list of all the above | 4 |
| `overlays/kind/metallb-pool.yaml` | the range of addresses MetalLB may hand out | 6 |
| `overlays/kind/gatewayclass.yaml` | the `eg` entry-point class, served by Envoy Gateway | 6 |
| `overlays/kind/plataforma/` | MetalLB, Envoy Gateway and `metrics-server`, each in its own folder | 6, 9 |

Three families of files are missing on purpose. Lesson 6's direct `LoadBalancer` (`revisor-publico`) was retired in Lesson 7: the only way out to the world is the Gateway. The support Pods (`depurar`, `intruso`, `memoria`, the load Job) are **tools for looking and for provoking**, not part of the project: there is no reason for them to be in every cluster you bring up, and that is why `depurar.yaml` and `intruso.yaml` live at the root of the folder and not inside the base. And the token: it is not versioned.

#### 10.2.2 Three questions to decide where each file goes

The order of the folders is not a whim. Each file answers three questions, in this order:

1. **Does the `revisor` need it in any cluster where it is installed?** Then it goes in the **base**. The Deployment, the Service, the network rules and the `restricted` level apply equally in `kind`, in your company's cluster or in the cloud.
2. **Does it depend on *this* cluster?** Then it goes in an **overlay**. MetalLB's address range comes from kind's Docker network; in a cloud it would not exist, because the provider supplies the load balancers. What depends on the environment is not mixed with what does not.
3. **Is it installed once per cluster and used by several projects?** Then it is **platform**. MetalLB, Envoy Gateway and `metrics-server` do not belong to the `revisor`: the day you publish a second service, it will use the same entry-point class and the same range. That is why they have their own folder and their own command.

You will see that the third question is not a matter of taste: it is the one that decides *the order of applying*. The platform brings new types, and the project uses them. 10.4 demonstrates it.

### 10.3 Kustomize: base and *overlays*

#### 10.3.1 A base that knows nothing about anyone

You already used Kustomize in Lesson 4, with generators. Here it is used for what it was designed for: **composing**. The [Kubernetes documentation](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) defines it this way (translated): a **base** is a directory with a `kustomization.yaml` that contains a set of resources and their associated customizations; an ***overlay*** is a directory with a `kustomization.yaml` that refers to *other* kustomization directories as its bases. And the sentence that matters: “a base has no knowledge of an overlay and can be used in multiple overlays”.

This is the base's `kustomization.yaml`. You know almost all of it; the comment at the top is new and says what you have just read:

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

Three fields do all the work. `resources` is the list of files it assembles. `namespace: revisor` is a **transformer**: it puts that namespace on everything that accepts one, without each file repeating it (that is why there is no `namespace:` in `deployment.yaml`). And the two **generators** create the `ConfigMap` and the `Secret` with the name plus a *hash* of the content: if the content changes, the name changes, and the Deployment (which the generator rewrites to point at the new name) does a *rollout* by itself. That was Lesson 4.

#### 10.3.2 An overlay that only points

The `kustomization.yaml` of the `kind` overlay is shorter than the base's:

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

Three lines of resources: the base (the folder, not a file), MetalLB's range and the entry-point class. The overlay **does not copy** anything from the base; it only names it. That is why, if tomorrow you change the `revisor`'s Deployment, the overlays do not find out and do not need to. And note what the comment says about `namespace:`: this overlay does **not** set it, because it would also put `revisor` on MetalLB's range, which has to live in `metallb-system`, and the `GatewayClass` does not even belong to a namespace (it applies to the whole cluster). The base's transformer already took care of its own part.

To see what an overlay assembles without touching the cluster there is `kubectl kustomize`, which **prints** the resulting manifests. It is the command you will use most when working with Kustomize: it assembles, it does not apply. How many objects, of which types:

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

(`grep '^kind:'` keeps the lines that *start* with `kind:`, one per object; `sort | uniq -c` counts how many there are of each type and the final `sort -rn` orders them from most to fewest.) It is the complete project: every row of the table in 10.2 has its part here. Three rows deserve a look. The `ServiceAccount` and `NetworkPolicy` objects are more than one because each workload has its account and each network opening its rule. The `ConfigMap` and the `Secret` are one of each: the generators. And `Gateway`, `HTTPRoute`, `GatewayClass`, `IPAddressPool` and `L2Advertisement` are the objects of **types that do not exist in an empty cluster**, the point of 10.4.

The figures above are the total `kubectl apply` will see. If you ever doubt what the cluster is going to receive, this is the first question you ask, before applying: `kubectl kustomize` and count.

#### 10.3.3 Changing without copying: an example overlay

Overlays are for what *changes* between environments. To see what a layer can change without touching the base, this file describes how the same base would look in a real cluster. **It is not applied to anything**: it is only rendered.

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

There are three tools for change, and all three are there. **`images`** changes an image's name and tag across the whole tree without editing the Deployments: here the image comes from a registry instead of being loaded by hand with `kind load`. **`patches`** with a list of operations (`op: replace`) is a *JSON Patch* ([RFC 6902](https://www.rfc-editor.org/rfc/rfc6902.html)): it says which object (`target`, by type and name), which path to change (`path`) and the new value. It is precise and sometimes awkward, because the path is written with the list index (`topologySpreadConstraints/0` is the first constraint). The [documentation](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) also offers the *strategic merge* patch (you write a piece of the object and it is merged in), which is more readable for large changes; for a number or a key, the operations patch is more direct. And the domain `registry.example.com` hangs off `example.com`, a name that [RFC 2606](https://www.rfc-editor.org/rfc/rfc2606.html) reserves for examples and documentation: nobody can register it, so there is no risk of another person using it and receiving your images.

Comparing the `kind` overlay with this one is the best way to see *what* changes:

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

(`diff` compares two texts; `<( … )` hands it a command's output as if it were a file, and it works in `bash` and in `zsh`. Lines with `<` are from the `kind` overlay; those with `>` are from the example one.) Read it in blocks. In the first there is an image change: the `revisor`'s image comes from a registry, not from `kind load`. The second is the spreading constraint: from `kubernetes.io/hostname` (spreads across *nodes*) to `topology.kubernetes.io/zone` (spreads across *zones*, which in a cloud are different data centers within a region). Then, `maxReplicas` and `minReplicas` of the scaling: from 6 to 10 and from 2 to 3. And at the end, what **leaves** the tree: the `GatewayClass`, the range and MetalLB's announcement, which belong to `kind` and not to the base. Four changes and one subtraction, and the base was not touched. (If you see `[código de salida: 1]` below the `diff`, it is not an error: `diff` exits with 1 when it finds differences, and with 0 when it does not.)

#### 10.3.4 Two warnings about what comes from the internet

The `plataforma` folder has one `kustomization.yaml` per piece, and each points to a **remote file**:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -c '^kind:'
76
```

That is the number of objects assembled from three internet addresses. One piece in particular, `metrics-server`, also carries a patch you already know from Lesson 9:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -B1 -A1 'kubelet-insecure-tls'
        - --metric-resolution=15s
        - --kubelet-insecure-tls
        image: registry.k8s.io/metrics-server/metrics-server:v0.9.0
```

The `--kubelet-insecure-tls` flag makes `metrics-server` skip verifying the certificate each `kubelet` presents. The `metrics-server` README for v0.9.0 describes it without ornament: “for testing purposes only”. In `kind` the `kubelet` certificates are not signed by the cluster's authority, so without the flag `metrics-server` cannot read the nodes. In a real cluster it is **not used**: the certificates are properly signed and the flag is unnecessary. It is the sixth of the things 10.10 records in the list of what is missing.

The two warnings about remote files:

- **Every time you apply, you download.** An address with the version in the path (`…/v0.16.1/…`) pins *which version* you ask for, but the content still comes from the internet every time `kustomize` assembles the tree. Without a connection, there is no platform. A real team usually keeps a copy of those files inside its repository (or on a mirror of its own), so that the bring-up does not depend on someone else's site or on a remote file not changing underneath you. Here it is not done so that you can see where each piece comes from.
- **Pin the version, and write it down.** The versions in this course are MetalLB v0.16.1, Envoy Gateway v1.9.2 and `metrics-server` v0.9.0. It is not a detail: the [Envoy Gateway installation guide](https://gateway.envoyproxy.io/docs/install/install-yaml/) explains that, when upgrading, the Gateway API CRDs must be updated first, and that if this is not done, TCP and UDP routes are “silently skipped” until the CRDs are applied. A version that moves without anyone deciding it is the origin of many Monday mornings.

### 10.4 Why two commands and a wait

#### 10.4.1 Three things an installation brings with it

In Lesson 6 you saw that MetalLB and Envoy Gateway are not “just another Deployment”: when installed they add to the cluster **new object types**, **controllers** that serve them and **guards** that check what is created. Before going on, the three with their exact names, because this lesson's order comes from there.

- **A CRD (*CustomResourceDefinition*)** is the definition of an object type that Kubernetes does not ship with. As long as it does not exist, writing an `IPAddressPool` is like writing a word the dictionary does not have: the `kube-apiserver` answers `no matches for kind`. And a CRD is not “ready” when it is created. The [CRD documentation](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) puts it this way (translated): the server takes a few seconds to create the endpoint for the new type, and you can watch the CRD's `Established` condition, or the list of types the server announces, to know when it exists. That condition, `Established`, is the one `kubectl wait` waits for in 10.5.
- **A controller** is a program (a Pod) that watches the objects of a type and makes the world match them: MetalLB's hands out addresses; Envoy Gateway's creates the Envoy that serves the entry point. While it is not running, the object is accepted, but nobody serves it: the Gateway exists and has no address. A Deployment is *ready* when its `Available` condition is true.
- **An admission *webhook*** is a guard that the `kube-apiserver` consults *before* saving an object, to accept it, reject it or fix it. MetalLB has one that validates the ranges. The [dynamic admission control documentation](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) has a piece you need to know: if the server cannot talk to the *webhook* (network, timeout, connection refused), the `failurePolicy` setting decides what happens, and **the default value is `Fail`**: the request is rejected. That is, while the guard's Pod is not serving, no object of the types it watches can be saved.

The three things arrive at the same moment and are not ready at the same time. What takes time is what forces the wait.

#### 10.4.2 `--server-side`: why the platform is applied differently

Before the order, the recipe's second command has a flag you had not used: `kubectl apply --server-side`. It is worth understanding before seeing it fail.

The usual `kubectl apply` is *client-side*: `kubectl` calculates what changed and, to remember “the last thing I applied”, stores a copy of the whole manifest in an annotation on the object itself, `kubectl.kubernetes.io/last-applied-configuration`. The [*Server-Side Apply* documentation](https://kubernetes.io/docs/reference/using-api/server-side-apply/) describes the other way (translated): instead of the client calculating and remembering, the server tracks which **manager** (*field manager*) owns each field of the object. It has been stable since Kubernetes 1.22. You request it with `--server-side`.

Two consequences matter for this lesson. The first: without copying “the last thing I applied” into the object itself, a limit goes away. An annotation has a maximum size, and the Gateway API and Envoy Gateway CRDs are enormous (they describe every field of every type in detail). The official Envoy Gateway installation guide, which you already cited in Lesson 6, installs with `kubectl apply --server-side`, and in 10.4.3 you will see what the cluster answers when it is omitted. The second: with *Server-Side Apply*, whoever applies is a named manager, and if two managers touch the same field with different values, the server reports a **conflict** instead of silently overwriting. That is what you want when several tools (you, a controller, a *pipeline*) touch the same cluster.

And a distinction not to confuse: `--server-side` changes *who calculates the change*, not *what is applied*. The project is applied the same with both modes; this lesson uses `--server-side` in both commands so that the habit is just one.

#### 10.4.3 First error: the platform without `--server-side`

The platform is applied “as usual”, without the flag, on an empty cluster. The output is long, so it is saved to a file and examined in parts: first how much was created, then **only what is not a “created”**:

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

(`> file 2>&1` saves to the file what comes out of the normal output *and* of the error output; `$?` is the exit code of the previous command; `grep -v` prints the lines that do **not** match; `cut -c1-330` trims each line to 330 characters so that it fits.)

Read it in order. **The exit code is 1**: the `apply` ended with an error. **73 objects were created**, and three lines say what could not be done: the CRDs `envoyproxies.gateway.envoyproxy.io`, `httproutes.gateway.networking.k8s.io` and `securitypolicies.gateway.envoyproxy.io` “are invalid: `metadata.annotations: Too long: may not be more than 262144 bytes`”. That is 262,144 bytes, i.e. 256 KiB (256 × 1024): the limit the `kube-apiserver` puts on an object's annotations. That annotation is the “last thing I applied” copy that 10.4.2 talked about, and these three CRDs describe so many fields that their own definition, copied inside the object, exceeds the limit. Each platform CRD was measured converted to compact JSON (`programas/10-proyecto-final/crd-tamanos.sh`; its output, `crd-tamanos.salida.txt`): `envoyproxies` weighs about 649 thousand bytes, `httproutes` about 299 thousand and `securitypolicies` about 274 thousand; the next in size, `backendtrafficpolicies`, is around 128 thousand. They are exactly the three that failed and no others.

Notice what that message does **not** do: it does not say “a flag is missing”. It says an object does not fit, and you have to know that the cause is the way of applying. And notice the state it leaves the cluster in, which is the serious part: 73 of 76 objects are created, so the cluster *looks* like it has a platform, but it lacks `httproutes`, the type of the route used by Lesson 6, and it lacks two Envoy Gateway types. A half-done state that looks almost healthy is worse than one that fails completely. This cluster was deleted, and another was created for the next experiment: that is the course's method.

#### 10.4.4 Second error: platform and project in a single command

The natural question is: why two commands? Can't everything be put into one, with the flag? `fig10_01.todo-junto/kustomization.yaml` is a **program that fails on purpose** (its first line warns about it): a single kustomization that contains the platform and the project.

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

It is applied on an empty cluster (another one, freshly created) with the right flag. The same things are examined as before: how many objects went in and which did not.

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

Read it the same way. The code is 1 again, and this time **99 objects** went in out of the 104 the tree assembles (76 from the platform and 28 from the project). The five that did not go in say the same thing: `no matches for kind "Gateway"`, `"GatewayClass"`, `"HTTPRoute"`, `"IPAddressPool"` and `"L2Advertisement"`, each with the warning `ensure CRDs are installed first`. Compare them with the five `Established` conditions that 10.5.2 waits for: they are the same five types. The Deployments, the Services, the network rules, the namespace and the CRDs themselves went in, since they depend on no new type; nothing that does depend on one went in. `kubectl` resolves **at the start**, before creating anything, which types the server knows, and with that list it checks all 104 objects. The CRDs are on the list, but the objects that use them are checked against the catalog as it was *before* creating them: that is why five fail even though their CRDs are created in the same command. An `apply` does not ask again halfway through ([`mapper.go` in cli-runtime](https://github.com/kubernetes/cli-runtime/blob/master/pkg/resource/mapper.go)).

The temptation that follows is the worst one: repeat the same command, without changing anything and without waiting, to see if it works this time. It was done, and this is what happened:

```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto2.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto2.txt
102

$ grep -v serverside-applied $L10_TMP/junto2.txt | cut -c1-330
Error from server (InternalError): Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
Error from server (InternalError): Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
```

There was progress, and that is what makes the method treacherous. Now **102 objects** went in: the three Gateway API types already existed, so `Gateway`, `GatewayClass` and `HTTPRoute` went through. Two remain, the range and its announcement, and they fail for another cause: `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connect: connection refused`. The `IPAddressPool` type already exists, but the guard that MetalLB puts in front of it (10.4.1) is not listening yet: the controller's Pod is starting. Since `failurePolicy` is `Fail`, the `kube-apiserver` rejects the object. `connection refused` means that the address of the guard's Service (the one that appears after `dial tcp`, a cluster IP that will be a different one in your run) exists, but nobody is answering behind it.

Each retry uncovers the next layer of what was missing: first the types, then the guards. A third attempt would probably go through (it was not measured, because there is no point in measuring it), and then “repeat until it works” would end up written on the wiki. That is the opposite of a recipe: it does not say how many times, it does not say what to expect and, the day an attempt fails for a different cause, there would be no way to tell it apart. The only thing that changed between attempt 1 and 2 was the passage of time; what is needed is to name what is being waited for.

#### 10.4.5 What the two errors teach

The two errors are versions of the same fact, and they serve to fix three rules:

1. **The platform goes first and with `--server-side`.** It brings new types, controllers and guards. It is a separate command because it has an exit condition: “the types are established and the controllers are up”.
2. **Between the platform and the project there is a wait on a condition.** Not a `sleep 30`, which works on your machine and fails on a slower one, but `kubectl wait --for=condition=…`. The [`kubectl wait` documentation](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) describes it as waiting for “a specific condition on one or many resources” and it exits with an error if the condition does not arrive within the time you gave it (`--timeout`). In the run you will see that, when it is met, it prints `condition met`. A `sleep` tells you “time has passed”; `wait` tells you “what I needed has happened”. And when it fails, it fails with a name.
3. **The project goes afterwards, in its own command.** Everything that uses a new type, a controller or a guard from the platform goes here.

The recipe comes down to three lines: `apply` the platform, `wait`, `apply` the project. It is the “two commands and a wait” of the lesson's title, and the course's first goal counts it that way: three steps, and the order is what defines them.

There is also an underlying reason, and not only for this course. Helm's documentation, which 10.9 names, has the same problem and puts it in other words in its [best practices on CRDs](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) (translated): “the declaration [of the CRD] must be registered before any resources of that CRD kind can be used, and the registration process sometimes takes a few seconds”. It is not a peculiarity of Kustomize or `kubectl`; it is a property of how Kubernetes extends its types.

### 10.5 Bringing it up by hand: platform, wait, project

Now the good path, on a freshly created cluster, with every step in view. It is the cluster of 10.1 (the one in that section's outputs): three nodes, the two images loaded, no CRDs. And before **every** command that changes something, `ctx &&`.

#### 10.5.1 Step 1: the platform

```bash
ctx && kubectl apply --server-side -k overlays/kind/plataforma > "$L10_TMP/plataforma.txt"
```

With the flag and on an empty cluster, everything goes in. The command prints one line per object; it was saved to a file and this is what is seen of it:

```text
$ kubectl apply --server-side -k overlays/kind/plataforma > $L10_TMP/plataforma.txt; grep -c serverside-applied $L10_TMP/plataforma.txt
76

$ head -4 $L10_TMP/plataforma.txt
namespace/envoy-gateway-system serverside-applied
namespace/metallb-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
```

There are **76** lines, one per object, and none says `Error`. `serverside-applied` means the server applied the object: it created it or updated it; on an empty cluster, they are all creations. The first two lines create the namespaces `envoy-gateway-system` and `metallb-system`, and the following ones are CRDs (`backends.gateway.envoyproxy.io`, `backendtlspolicies.gateway.networking.k8s.io`…). Compare with 10.4.3: with `--server-side`, the three CRDs that did not fit go in like the others, because the “last thing I applied” copy is no longer attached to them.

The cluster already knows the new types, but their controllers are still starting. This is how it looks at this instant:

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

The cluster already knows **30** new types (`kubectl get crd | wc -l` counts 31 because it includes the header row). And the MetalLB Pods, in the first second, are all at `0/1 ContainerCreating`: the `controller` and one `speaker` per node are still downloading their image and starting. This is the dangerous instant from 10.4: the types exist and the guards are not serving. Applying the project *now* would give the `connection refused` of the second error.

#### 10.5.2 Step 2: the wait

Five waits, each with its condition. The five together are “the platform is ready”:

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

All five finish well. The first, for types, answers `condition met` immediately for the five CRDs: they were already established. The others are the slow ones: MetalLB's `controller`, the three `speaker` Pods (the progress says `0 of 3 updated pods are available…`, then `1 of 3`, `2 of 3`, and finally `successfully rolled out`), the Envoy Gateway controller and `metrics-server`. The nodes are new and have no images: each one has to download MetalLB's, Envoy Gateway's and `metrics-server`'s from the internet before the Pods can start. In this run the complete wait lasted 153 seconds; in the lesson's preparation runs it ranged from those 153 up to 881 seconds (almost fifteen minutes), depending on the connection and the load on the machine. Each `kubectl wait` carries its own 600-second limit; the 881 were the sum of the five waits, not a single one (the output is in `corridas-preparacion/corrida4.txt`). If on your connection a single one exhausts the 600, the error undoes nothing: repeat the same command. It was not separated how much of that time is download and how much is startup, so it is not claimed. What is claimed is what you should plan for: **the wait is the longest part of the bring-up**, and that is why it should be a wait on a condition and not a fixed time that somebody has to guess.

And a wait is also used to know when something does **not** arrive. If you ask `kubectl wait` for a condition that is not met, with a short limit, it gives up with an error instead of hanging. Here the Envoy Gateway controller, which is `Available`, is asked to stop being so, and it is given 5 seconds:

```text
$ kubectl wait --for=condition=Available=false --timeout=5s -n envoy-gateway-system deployment/envoy-gateway
error: timed out waiting for the condition on deployments/envoy-gateway
[código de salida: 1]
```

`error: timed out waiting for the condition on deployments/envoy-gateway`, and the script notes `[código de salida: 1]`. It is the behavior you want from a wait: it does not hang, it does not invent a success and it says which condition of which object did not arrive. A `sleep 300` followed by an `apply` would have left you without that information.

Read them with the list of three things from 10.4.1 in hand. The first wait is for **types**: `Established` is the CRD's condition. The other four are for **controllers**: `Available` for the Deployments (MetalLB's `controller`, `envoy-gateway`, `metrics-server`) and `rollout status` for the `speaker` `DaemonSet`. A `DaemonSet` has no `Available`; it has a progress of “how many of the Pods that should exist are ready”, and `rollout status` follows it until they all are (one per node). MetalLB's *webhook* is served by the `controller` Pod: when it is `Available`, the guard already answers.

#### 10.5.3 Step 3: the project

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

There are **28** lines, and every row of the table in 10.2 is there: the namespace, the four service accounts, the role and its binding, the `ConfigMap` and the `Secret` with their *hash*, the two Services, the volume, the two Deployments, the `CronJob`, the `PodDisruptionBudget`, the scaling, the `Gateway` with its `HTTPRoute`, the six network rules and the **three** objects that exist only because of the overlay: the `eg` `GatewayClass`, the range and MetalLB's announcement. Notice that they do not come out at the end but spread throughout: Kustomize orders the output by object type, not by the file they come from. The `ConfigMap`'s name, `revisor-config-t6cm6872fk`, is **the same** as in Lessons 4 and 5, because the list of services is the same: the *hash* is of its content. The `Secret`'s changes on every run, because the token is new. And there is no line that starts with `Warning`, but that absence is proved, not eyeballed.

A statement like “there are no warnings” is proved by counting, and with a case where there are some (10.7 does that). Here is the count, with `-i` so as not to depend on capitalization:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -ci warning
0
[código de salida: 1]
```

The `0` is the count. The `[código de salida: 1]` that the script notes is not a failure: `grep` exits with 1 when it finds no lines, even though with `-c` it prints the zero. Here it means “zero warnings”.

Then, two more waits: for the Deployments to be `Available` and for the entry point to be `Programmed` (the `Gateway` condition that says “it now has an address and an Envoy serving it”):

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

One wait is missing that `kubectl wait` does not cover well: the automatic scaling needs a few seconds to read its first metrics, and until it has them it shows `<unknown>`. This time it is not solved with a blind `sleep` but with a short, **visible** loop, which checks every 5 seconds for up to two minutes and stops as soon as the scaling has a metric:

```bash
for _ in $(seq 1 24); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

There is a `sleep`, and that is fine: it is the **wait for a condition with a limit**. Each iteration asks whether the thing that matters has happened. If it does not happen within 24 iterations, the loop gives up and the next command shows you the `<unknown>` instead of hiding it.

#### 10.5.4 Seeing it work

Everything the nine lessons built, in a single query:

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

Read it in blocks, from top to bottom.

- **Pods.** The two for the `revisor` and the one for `prueba`, all three `1/1 Running`. If you bring the project up right on a minute that is a multiple of five, you will also see a fourth Pod, `reporte-…`, at `0/1 Completed`: the scheduled task from Lesson 8, which has already run and finished well (in one of this lesson's preparation runs it did appear; in the one pasted here, not yet).
- **Services.** Both are `ClusterIP`, with no `EXTERNAL-IP`: Lesson 6's direct `LoadBalancer` no longer exists. The only entry point is the Gateway.
- **Deployments and ReplicaSets.** `2/2` and `1/1`. Each Deployment has a ReplicaSet with its *hash*. If you see it differently in your run, that is normal: it depends on the `Secret`'s name, which changes with the token.
- **Scaling.** `cpu: …/50%`, `MINPODS 2`, `MAXPODS 6`, and the two current replicas. That there is a percentage and not `<unknown>` means `metrics-server` has already delivered its first reading; that is why it is waited for with the loop from 10.5.3.
- **CronJob.** The schedule `*/5 * * * *`, not suspended, `ACTIVE 0` and `LAST SCHEDULE <none>`: it has not fired even once yet. When it fires, a Job with its Pod will appear.
- **Volume.** The PVC `reportes` is `Pending`, and that is correct: in Lesson 8 you saw that the `standard` class waits for the first Pod that uses it (`WaitForFirstConsumer`) before creating the disk. It will turn `Bound` when the `CronJob` fires for the first time.
- **`PodDisruptionBudget`.** `MIN AVAILABLE 1`, and `ALLOWED DISRUPTIONS 1`: with two replicas, the cluster can take one out at a time.
- **Network rules.** The six from Lesson 7, with their selectors.
- **Gateway.** Class `eg`, **address `172.30.255.200`** (the first in the overlay's range) and `PROGRAMMED True`. It is the address MetalLB handed out. **`HTTPRoute`.** No host names (`HOSTNAMES` empty): it serves any.

And the metrics, which are the proof that `metrics-server` and the scaling are connected:

```text
$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-rzh88    1m           1Mi             
revisor-654b5d75dc-6m6s6   1m           1Mi             
revisor-654b5d75dc-dq4pp   2m           1Mi             
```

The most important thing is missing: that **someone from outside** gets in. The entry point's address comes from the `Gateway` itself, and the client is a Docker container connected to the same network as the nodes, **outside** the cluster (the same trick as Lesson 6):

```bash
IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
CURL='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
docker run --rm --network kind $CURL -s -m 5 "http://$IP_GW/salud"
docker run --rm --network kind $CURL -s -m 5 -o /dev/null -w '%{http_code}\n' "http://$IP_GW/api/estados"
docker run --rm --network kind $CURL -s -m 5 -H "Authorization: Bearer $TOKEN" "http://$IP_GW/api/estados?formato=tabla"
```

(In the output block below, the script abbreviates each `docker run … curl` to `curl`, so that it fits. `$TOKEN` is the variable from 10.1.2.)

```text
$ curl -s -m 5 http://172.30.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.30.255.200/api/estados
401

$ curl -s -m 5 -H "Authorization: Bearer $TOKEN" 'http://172.30.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200
```

The three requests arrived from outside the cluster at the address MetalLB gave the Gateway. `/salud` answers without asking for anything. `/api/estados` **without a token** gives `401` (Lesson 4: the `revisor` demands `Authorization: Bearer …`). And with the token, the report table. Notice that the token comes in through the entry point in a header, in plain text: it is point 4 in the list in 10.10.

On your terminal the network's name is `kind` (that is how the block above left it). If the run did not use that network, “About the runs” says so.

### 10.6 Automating without hiding the order

#### 10.6.1 What is automated and what must not be hidden

By hand, the bring-up is three blocks and eight waits. To repeat it on every new cluster (yours tomorrow, a colleague's, a *pipeline*'s automated step) a script is convenient. And here there is a design decision that separates a script that helps from one that gets in the way. There are two ways to write it:

- **The script that hides the order.** A single line that “retries until it works”: `until kubectl apply -k .; do sleep 5; done`, or a `sleep 120` between two applies, or a `|| true` so that nothing stops. It works almost always and when it fails it does not say why: the loop keeps spinning, or the `sleep` was too short on the slow machine, or the error was swallowed silently. In 10.4.4 you saw what the blind retry does: it applies partially and leaves you to guess what is missing.
- **The script that shows the order.** The same three steps, each with a name, each with its context check, with waits on a **condition** and with a time limit. When it fails, it fails at a named step, with a `kubectl` message saying which condition did not arrive. And whoever reads it learns the order, which is half the value.

This is the second kind. It is called `levantar.sh`, lives in the lesson's folder and is what a *pipeline* step would call as is:

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

#### 10.6.2 The script, line by line

Read it from top to bottom, and almost everything is something you already know in another guise.

**`set -euo pipefail`.** Three `bash` options in one. `-e` stops the script at the first command that fails. `-u` makes using a variable that does not exist an error, instead of reading it as empty. `-o pipefail` makes a pipeline (`a | b`) fail if *any* of its parts fails, not just the last. Together they are the difference between a script that stops where the problem is and one that goes on as if nothing had happened. It is the same reason `levantar.sh` uses `|| true` in only one place: when reading the active context, where a failure is accepted (the script compares afterwards and stops with a clear message). The same in `probar-levantar.sh`, in the cluster cleanup and in the count of live clusters, and in the deliberate failures of `correr.sh`: each `|| true` is attached to a specific command whose failure is accepted and the reason is stated, which is the only thing “Common mistakes” allows.

**`ESPERADO="${1:?uso: …}"`.** The script **does not guess** which cluster it is on: it receives the context as an argument and, if it is missing, prints the usage and stops. `${1:?message}` means “the first argument, and if it is empty, fail with this message”. It is the opposite of a script that uses “whichever cluster is active”: a script that installs MetalLB and Envoy Gateway on the active context, without asking, can install those things on the wrong cluster.

**`contexto()`.** The `ctx` function from 10.1, but for a script: it compares `kubectl config current-context` with `ESPERADO` and, if they do not match, prints “ALTO” and does `exit 1`. It is called **before every step**, not just once at the start, because a long script runs for minutes and somebody (or something) can change the context between one step and the next.

**Step 0: the network.** This is new and exists for a concrete reason. MetalLB's address range lives in `overlays/kind/metallb-pool.yaml`. If that range does not fall on the same network as the nodes, MetalLB assigns an address to the Gateway, `kubectl` says everything is fine, and nobody from outside can reach it: the failure is silent. The `sed` extracts the first address in the range, `docker inspect` extracts the control-plane node's IP, and the comparison `${RANGO%.*.*}` (removing the last two numbers: `172.30.255.200` becomes `172.30`) against `${IP_NODO%.*.*}` checks that both are on the same `/16` network. It is a simple check (it assumes networks of that size, and the error message says so), but it turns a mute failure into an “ALTO” with a cause.

**Step 1.** It captures the output of `kubectl apply` in a variable (`SALIDA="$(…)"`) and shows only the count of `serverside-applied`. If `kubectl apply` fails, the assignment fails and `set -e` stops the script: the count is never reached. The output is not discarded with `>/dev/null`: it is **measured**.

**Step 2.** The five waits from 10.5.2, unchanged. Each with its limit (`--timeout`): 120 seconds for the CRDs to exist, 600 (ten minutes) for the controllers, which depend on how long your connection takes to download images.

**Step 3.** It applies the project and waits for two things: the Deployments `Available` and the entry point `Programmed`. At the end, `kubectl get gateway` prints the result you want to see.

**`$SECONDS`.** A `bash` variable that counts the seconds since the script started. Each step reports at how many seconds it finished. It is not decoration: if a step gets slow, you see it, and this script's timings are the ones 10.6.3 uses to say how long bringing up the project takes.

What it does **not** do is also a decision. It does not create the cluster (that is up to the caller: you, or an earlier *pipeline* step). It does not load the images. And it does not run `curl`: checking that the entry point answers from outside needs a client on the Docker network, and that is a test, not a bring-up. A script that brings up and another that tests can be changed separately.

One more detail about the exit code. `levantar.sh` exits with 0 only if **the whole** run finished; on any failure, it exits with a non-zero code at the step where it happened. That is all a *pipeline* needs to know to mark a step green or red, and that is why the script takes care of it and does not depend on anyone reading the output text.

#### 10.6.3 Testing it for real: create, bring up, delete, recreate

A script that has never been run against an empty cluster is like the backup in the GitLab case: it exists and nobody knows whether it works. It is tested with `probar-levantar.sh`: it creates the cluster, runs `levantar.sh`, checks from outside that the entry point answers, **deletes the cluster** and repeats everything a second time. If the first round passes by chance (something that was already there, a cache, a wait that happened to be enough), the second betrays it, because it starts from zero again.

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

The parts that are not about the bring-up you have already seen: the temporary `kubeconfig`, the `trap limpiar EXIT` that **deletes the cluster even if the script fails halfway** (a `trap … EXIT` runs when the script exits, whether by finishing or by an error), and the check that `curso-k8s-l10` does not already exist before creating it. `limpiar` only deletes a cluster named exactly `curso-k8s-l10`, and the temporary folder only if its path starts with `/tmp/curso-k8s-l10.` (the usual `case`).

What is new is `CUPO_MAXIMO`. It is for shared machines, and this lesson's run used it: before creating a cluster, it waits until there are fewer than that number of live `curso-k8s-*` clusters. Without the variable, it does not wait. On your machine, alone, you do not need it.

`probar-levantar.sh` uses its own `base/token.txt` (`levantar.sh` generates it if it does not exist) and **deletes it when it finishes**: if you already have one, save it first or let it regenerate it.

The complete output of the test, with both rounds:

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

Both rounds say the same thing, and that is what was meant to be tested. Step 0 confirms that the range starts at `172.30.255.200` and that the control-plane node is at `172.30.0.x` (the node's IP changes from one round to the other: `.4` and `.3`; the only thing that matters is the network). Step 1 applies **76** objects in about 5 seconds. Step 2 is the one that lasts: from second 5 to 234 in the first round and from 4 to 250 in the second (marks accumulated since the script started), that is, **almost the whole bring-up is waiting** for the nodes to pull images and start the platform. Step 3 applies **28** objects and waits: 22 seconds in the first round and 65 in the second (the Gateway showed 22 s and 61 s of age at the end: `AGE` is the object's age when the `get` was done, not the time until `Programmed`). Each “paso N terminó a los X s” (“step N finished at X s”) is the time accumulated since the script started, not the duration of the step. `levantar.sh` took 256 and 315 seconds. In both rounds the entry point took `172.30.255.200`, `curl` from outside answered `{"estado":"vivo","version":"1.6.0"}`, and the cluster was deleted. That the second round, starting from zero again, passes just the same is the course's **goal 1**: rebuilding without fixing anything by hand.

#### 10.6.4 How it would look in a *pipeline*

You do not need a *pipeline* for this lesson, but you should know how it would be connected, because it is the use the script is designed for. A *pipeline* step in any tool comes down to four things, and `levantar.sh` already has them all:

1. **An explicit input.** The context (`kind-curso-k8s-l10`) is an argument, not an assumption. In a real *pipeline* it would be the cluster that step has credentials for.
2. **Minimal credentials.** This script creates CRDs and *webhooks*, which are cluster-wide objects, so it needs cluster administrator permissions. In a real environment you do not give a *pipeline* the account of the administrator of everything: you give it an account of its own (RBAC, Lesson 7) with just the permissions for what it installs. In `kind` there are not two accounts, so the course does not practice it, but it names it.
3. **An honest exit code.** 0 if everything finished, non-zero if not. It is the only information the *pipeline* reads.
4. **Output that can be read afterwards.** The three headings `== 1.`, `== 2.`, `== 3.`, the counts and the seconds per step are what someone reads at 7:50 on a Monday when step 2 turned red.

And what the script must not become: a place where patches accumulate. If a step breaks for a new cause, you fix the cause, you do not add a `sleep`.

### 10.7 The final review against `restricted`

#### 10.7.1 What `restricted` asks for, specifically

Lesson 2 put the `securityContext` in the first Deployment; Lesson 7 put the `restricted` level on the namespace. Now it is time to check, with the cluster and not from memory, that **everything** in the `revisor` namespace meets it. First, what it demands. The *Pod Security Standards* ([documentation](https://kubernetes.io/docs/concepts/security/pod-security-standards/)) define three levels; `restricted` is the strictest and adds six controls to those of `baseline`:

| `restricted` control | What it requires (field and allowed value) | Where the project meets it |
|---|---|---|
| Volume types | every volume is of an allowed type: `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected` or `secret` | `emptyDir` and `secret` in the `revisor`; `persistentVolumeClaim` and `secret` in the `CronJob` |
| Privilege escalation | `allowPrivilegeEscalation: false` on every container | each container's `securityContext`, in the two Deployments (`revisor` and `prueba`) and the `CronJob` |
| Running as non-`root` | `runAsNonRoot: true` (at the Pod or on each container) | the Pod's `securityContext` |
| Non-`root` user | `runAsUser` other than 0, or unset | 65532 in the `revisor` and `prueba`; 100 in the `CronJob` |
| *Seccomp* | explicit `seccompProfile.type`: `RuntimeDefault` or `Localhost`; neither `Unconfined` nor absent | `RuntimeDefault`, in the Pod's `securityContext` |
| Capabilities | `capabilities.drop` includes `ALL`; only `NET_BIND_SERVICE` may be added back | `drop: ["ALL"]` on every container |

(The `baseline` controls that `restricted` inherits (no privileged containers, no host network, no `hostPath`, no host ports, among others) are met because no manifest in the project asks for any of that.)

And now, what **`restricted` does not ask for** and the project does anyway, so that you do not confuse it with the standard:

- `readOnlyRootFilesystem: true`. None of the three levels requires it. The project sets it because a filesystem that cannot be written to limits what an attacker could do inside the container, and that is why the `revisor` stores its report on a volume and not on `/`.
- `requests` and `limits` (Lesson 5), `automountServiceAccountToken: false` (Lesson 7), the `Secret` marked immutable and mounted as a file (Lesson 4), the closed network (Lesson 7). These are the project's decisions, not `restricted` controls.

Telling the two lists apart matters: “meets `restricted`” is a fact the cluster can confirm with a query (the next section), and “follows the course's practices” is a judgment you make.

#### 10.7.2 How the cluster applies it

The level is not taught to each Pod: it is told to the **namespace**, with labels. This is what `base/namespace.yaml` carries:

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

The [*Pod Security Admission* documentation](https://kubernetes.io/docs/concepts/security/pod-security-admission/) defines three **modes**, each with its label: `enforce` (a violation **rejects** the Pod), `audit` (a violation leaves an annotation in the audit log, but is allowed) and `warn` (a violation produces a warning for whoever applied, but is allowed). Each mode also has a `…-version` label that pins the policy to the one that shipped with a Kubernetes version, here v1.37, so that a cluster upgrade does not change the rules underneath you without your deciding it.

A detail that explains what you will see in 10.7.4: according to the same documentation, the `audit` and `warn` modes also apply to the objects that *create* Pods (Deployments, Jobs, CronJobs), “to help catch violations early”, but `enforce` does **not** apply to those objects, only to the resulting Pods. Put as an example: a Deployment that does not comply is *accepted* (with a warning), and the Pods it tries to create are *rejected*. The Deployment ends up existing with zero replicas, and that is why you have to read `apply`'s warnings and not trust that it “applied fine”.

#### 10.7.3 The review in the cluster

First, the query that the [documentation](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) recommends before changing a level: `kubectl label --dry-run=server --overwrite`. The documentation explains that when an `enforce` label (or its version) is **added or changed**, the admission controller tests every Pod in the namespace against the new policy and returns the violations as warnings, and that with `--dry-run=server` that test runs without applying anything. Everything depends on “added or changed”. The first thing one writes about `revisor`, which already has `enforce=restricted`, **changes nothing**, and so (measured, below) it reviews no Pod:

```text
$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)

$ kubectl get namespace revisor --show-labels
NAME      STATUS   AGE   LABELS
revisor   Active   83s   kubernetes.io/metadata.name=revisor,pod-security.kubernetes.io/audit-version=v1.37,pod-security.kubernetes.io/audit=restricted,pod-security.kubernetes.io/enforce-version=v1.37,pod-security.kubernetes.io/enforce=restricted,pod-security.kubernetes.io/warn-version=v1.37,pod-security.kubernetes.io/warn=restricted
```

`namespace/revisor not labeled (server dry run)` says only one thing: the label was already that and there was nothing to change. It **did not review any Pod**, so it is not evidence that the project complies; with any Pod inside it would have said the same. In the second output are the six labels of the three modes, each with its `v1.37` version, plus the one Kubernetes sets by itself (`kubernetes.io/metadata.name`).

**The query that does review what already exists.** If the level and the version are repeated, the server does not evaluate; if the policy **changes**, it does. So, to audit a namespace that is already at `restricted:v1.37`, a different policy is requested, without applying it: the same version label with another value, for example `enforce-version=v1.36`. The server tests each Pod against `restricted` of that version (not v1.37: it is a neighbor, not the same one) and reports. Since an absence of warnings is worthless without a control, `psa-comprobacion.sh` tests it first in a test namespace, `psa-control`, with two Pods: `viola` (says nothing about security) and `cumple` (meets the six `restricted` controls). `restricted:v1.37` is set on it for real and both queries are repeated. This was run on a three-node `curso-k8s-l10` cluster with the project applied (the `revisor` namespace) but without the platform, which this test does not need:

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

Read it from top to bottom. When `restricted` is really set, the server warns and names **`viola`** (with the four controls it fails) and not `cumple`. Repeating the same level and the same version on `psa-control` says `not labeled`, **with a Pod that violates inside**: that is the query that does not review. Asking for `v1.36` does warn, and only about `viola`: the query reviews, and it tells them apart. With the control in view, the result on `revisor` counts: repeating the level says `not labeled` (no information) and asking for `v1.36` says `labeled (server dry run)` **without a single warning** over the 4 Pods in the namespace (the two of the `revisor`, the `prueba` one and the one the `CronJob` left). That is what “the server reviewed the `revisor` Pods and none violates `restricted`” looks like.

An absence of warnings is only worth something if you know the tool would give them; that check (the control above, and the `malo` Deployment from 10.7.5) is already done. In addition, the field-by-field proof: the table in 10.7.1, but read from the namespace's live Pods (the jsonpath asks, per Pod, for the fields that `restricted` examines):

```text
$ kubectl get pods -n revisor -o jsonpath='{range .items[*]}{.metadata.name}{" noroot="}{.spec.securityContext.runAsNonRoot}{" seccomp="}{.spec.securityContext.seccompProfile.type}{" priv-esc="}{.spec.containers[0].securityContext.allowPrivilegeEscalation}{" drop="}{.spec.containers[0].securityContext.capabilities.drop}{" ro="}{.spec.containers[0].securityContext.readOnlyRootFilesystem}{" automount="}{.spec.automountServiceAccountToken}{"\n"}{end}'
prueba-6899c74865-rzh88 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-6m6s6 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-dq4pp noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
```

Three Pods, three identical rows: the two of the `revisor` and the `prueba` one (if the `CronJob` had already fired, a fourth would appear, with the same values). In each: `noroot=true` (the Pod runs as non-`root`), `seccomp=RuntimeDefault`, `priv-esc=false`, `drop=["ALL"]`, and also `ro=true` and `automount=false`, which belong to the course and not to `restricted`. Only the first container (`containers[0]`) was requested, and each of these Pods has just one. This query does not replace the `dry-run` (which reviews all the controls, not just the ones I wrote in the `jsonpath`); it complements it: it lets you *see* the values.

#### 10.7.4 Part of the platform does not meet `restricted`, and that is fine (with one condition)

The `revisor` namespace is the only one with the labels. What would the server say if you put them on the platform's namespaces? The same query is used, changing nothing (`cut` trims each line so that it fits). Here the query does review the Pods, because these namespaces do not have the label and adding it is a change. Another difference from the previous query: these namespaces have no version label, so the server compares against the most recent version of the policy (`restricted:latest`) and says so in the first warning:

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

Three namespaces, three different answers:

- **`envoy-gateway-system`: no warnings.** It says “labeled (server dry run)” and nothing else. The Envoy Gateway Pods (the controller and the Envoys that serve the entry point) meet `restricted`. It is worth knowing and it is not obvious: not all of the platform asks for privileges.
- **`metallb-system`: yes.** The `controller` violates two controls: “unrestricted capabilities” (it keeps Linux capabilities that `restricted` forces you to drop) and “seccompProfile” (it declares no profile). The three `speaker` Pods violate more: “host namespaces” and “hostPort” (they share the node's network), “probe or lifecycle host”, “runAsNonRoot != true” and the same capabilities and profile. The `speaker` is the one that answers the network's ARP questions (the layer 2 in 10.10, point 5) and, for that, it has to see the node's network and not a network of its own: the “host namespaces” warning is the technical name of that need.
- **`kube-system`: yes, and a lot.** Both `coredns` Pods violate `runAsNonRoot` and the `seccomp` profile. The four control-plane Pods (`etcd` and its three companions) share the host's network and mount node paths (the “restricted volume types”). `kindnet` and `kube-proxy` share the host's network and keep capabilities, and `kube-proxy` also runs as `privileged`.

(The “(and 2 other pods)” comes from the server: it groups the Pods that violate the same thing so as not to repeat the row.)

That is not a defect of the course: it is what happens when a piece of infrastructure needs privileges to do its job (talk to the nodes' network, announce addresses, mount node paths). The point is twofold. First, **the privileges exist and they are somewhere**: the platform concentrates them in its own namespaces, and the project, which is what changes every day, lives without them. Second, those namespaces come with a **condition**: nobody else should be able to create Pods there, because whoever can create a Pod in `metallb-system` or `kube-system` has, in effect, that namespace's privileges. In a real cluster, that is solved with RBAC (who can create what where) and with a `baseline` or `privileged` level *declared* for each platform namespace (a written decision, with an owner), not with an unlabeled namespace. Here they are not labeled, and 10.10 notes it.

#### 10.7.5 The positive control: a Deployment that does violate `restricted`

To know that “not a single warning” means something, it is tested with a Deployment that **should** produce them. `fig10_02.deployment-malo.yaml` is a **program that fails on purpose**: a Deployment that says nothing about security.

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

Three things in this order. **On applying**, a `Warning` with four violated controls: `allowPrivilegeEscalation != false`, `unrestricted capabilities`, `runAsNonRoot != true` and `seccompProfile`, each with the exact field that is missing (`container "malo" must set securityContext.allowPrivilegeEscalation=false`…). And below, `deployment.apps/malo created`: the Deployment **was** created. Second, the Deployment is at `READY 0/1`: it has no Pod. Third, the ReplicaSet's events: `FailedCreate`, “Error creating: pods "malo-…" is forbidden: violates PodSecurity "restricted:v1.37"”, with the same list. That is where the `enforce` mode acted, and you can see it did so when creating the Pods, not the Deployment.

This is what 10.7.2 announced: the Deployment *is accepted* (with warnings, by the `warn` mode) and the Pods *are rejected* (by the `enforce` mode); the ReplicaSet records each rejection as a `FailedCreate` event. And it is the reason to read `apply`'s output. It is deleted:

```text
$ kubectl delete -n revisor -f fig10_02.deployment-malo.yaml
deployment.apps "malo" deleted from revisor namespace
```

With this, the project's claim stands with a control: the project produces no warnings (count 0 in 10.5.3), and a Deployment that violates the policy **does** produce them. Exercise 2 asks you to fix this one.

### 10.8 Testing the goals

The course README ends with seven goals: not “you read the lessons” but “your project meets this”. This section checks on the cluster the ones that can be measured. First, the map, so you know where each one is:

| Goal | What it says | Where it is checked |
|---|---|---|
| 1 | from a freshly created cluster, the project ends up running in three steps, and it is rebuilt after deleting it | 10.5 (by hand) and 10.6 (with the script, two rounds) |
| 2 | the namespace is at `restricted` and there are no warnings when applying | 10.5.3 and 10.7 |
| 3 | a worker node is stopped and the service keeps responding, with a measured window | 10.8.3 |
| 4 | changing the list of services does the *rollout* by itself | 10.8.1 |
| 5 | under load, the scaling adds and removes replicas | measured in Lesson 9; 10.8.4 checks that it is still connected |
| 6 | a foreign Pod does not talk to the `revisor`, and the `revisor`'s account can do nothing | 10.8.2 |
| 7 | you can state, in writing, five reasons why this is not production-ready | 10.10 and Exercise 4 |

#### 10.8.1 Goal 4: changing the list changes the replicas, without touching the image

It is Lesson 4 seen from the end: the configuration lives outside the image. First, the state before the change: the ReplicaSet that has the replicas and the generated `ConfigMap` with its *hash*.

```text
$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-654b5d75dc   2         2         2       92s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      92s
revisor-config-t6cm6872fk   1      92s
```

The test service's timeout is changed from `2s` to `1s` in the base. `sed -i.bak` edits the file in place and leaves a copy with the `.bak` extension (the form that works the same on Linux and macOS); `diff` compares the copy with the new file so that you see exactly what changed:

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

Here the command filters the two lines that matter:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-cmb662hmbh serverside-applied
deployment.apps/revisor serverside-applied
```

The file is restored (the `.bak` is moved back to its name) and the *rollout* is awaited:

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

What changed: the `diff` shows a single line, `2s` for `1s`. The `apply` applied two objects: a **new** `ConfigMap`, `revisor-config-cmb662hmbh` (another *hash*, because the content is different), and the Deployment, which the generator rewrote to point to it. The *rollout* created a new ReplicaSet with the two replicas and left the old one at `0 0 0`. And what did not change: the image. `curso-docker-revisor:1.6.0` was not rebuilt, not reloaded and not touched. The old `ConfigMap` is still in the cluster, used by nobody: that is the price of Lesson 4. `kube-root-ca.crt` is not yours: Kubernetes creates it in every namespace.

And since the file says `2s` again, the cluster has to go back too. **The file is the truth**: if the cluster and the files differ, the cluster is corrected by applying again, not by noting “I know it is different”:

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

On returning to the original file, the `ConfigMap` that is applied is once more `revisor-config-t6cm6872fk`, the earlier one. Since the Pod template is identical again to that of the first ReplicaSet, the Deployment **reuses it**: it raises the old one from 0 to 2 and lowers the one it had just created, instead of building a third. Two ReplicaSets remain, one active and one at `0 0 0`; those empty ReplicaSets are what `rollout undo` uses to go back (Lesson 9).

#### 10.8.2 Goal 6: the network and the permissions

Two small tests, in the `revisor` namespace: a Pod **with** the label `acceso-revisor: permitido` (`depurar`) and another **without** it (`intruso`). Both are `curl` Pods that already meet `restricted`, so the cluster accepts them:

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

The first is the positive control: without it, the second would prove nothing, because a `curl` that fails can fail for a thousand reasons. The `depurar` gets through (the network allows it), the `intruso` does not. Reading the code is the key. `curl` exits with **28** (*operation timed out*): the 3 seconds of `-m 3` passed without a response. If the network rejected the connection, `curl` would exit with 7 (“failed to connect”), as in Lesson 3. A `NetworkPolicy` that does not let a packet through **drops it without answering**, and the client keeps waiting: that is why the 28 is the fingerprint of a closed network and not of a downed service.

And the accounts' permissions, with `kubectl auth can-i`, which asks the cluster whether an identity could do something, without doing it:

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

Four answers, and a table summarizes them: the `revisor` account **cannot** read Pods or Secrets (`no`, `no`); the `observador` account **can** read Pods (`yes`) and **cannot** delete them (`no`). `can-i`'s exit code is 1 when the answer is `no`, and that is why the script notes `[código de salida: 1]` even though nothing failed. The `revisor`'s account does not even have credentials mounted (`automountServiceAccountToken: false`), so the answer is double: it cannot, and even if it could, the Pod has nothing to call the API with.

#### 10.8.3 Goal 3: a node is stopped and the service keeps responding

This is the test closest to what happens in a real cluster, and the one that teaches the most. A worker node is a Docker container; stopping it with `docker stop` resembles the machine suddenly powering off. Three things are to be learned: does the service keep responding? Does anything fail in the meantime? For how long?

**Before predicting, the cluster's numbers.** The [node status documentation](https://kubernetes.io/docs/reference/node/node-status/) describes the mechanism: each `kubelet` renews its node's `Lease` object **every 10 seconds** (that is the heartbeat), the node controller checks the heartbeats **every 5 seconds** (`node-monitor-period`), and the `Ready` condition turns `Unknown` if within `node-monitor-grace-period` it has heard nothing from the node: **50 seconds by default** (also as a default value in the [`kube-controller-manager` reference](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)). The 50 seconds are counted from the **last heartbeat the controller received**, not from the `docker stop`: that heartbeat may have arrived up to 10 seconds before the node was shut down, and the controller only notices it on its next check (up to 5 seconds later). Adding it up, the cluster finds out between about 40 and about 55 seconds after the `docker stop`; since the measuring loop starts a few seconds later, from its clock the window falls a few seconds earlier. Until the deadline is met, the cluster *does not know* the node is gone. And the [taints and tolerations documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) says that, once the node is `Unknown`, the Pods are not evicted right away: by default they tolerate the “node unreachable” taint for **300 seconds** (`tolerationSeconds`), and only then are they replaced on another node.

The prediction, then: with two replicas (one per worker node), when one node is stopped, **on average half of the requests** should fail while that window lasts (tens of seconds). The [Services documentation](https://kubernetes.io/docs/reference/networking/virtual-ips/) says that, in `iptables` and `nftables` modes, `kube-proxy` installs rules that by default pick the destination Pod **at random**: it is not a strict turn, so with about 25 requests the real proportion can drift from half. Meanwhile, one address no longer answers and the cluster does not know yet. Once the window passes, the dead replica leaves the list of addresses and everything should go through.

The experiment. One detail first: the *rollout* test from 10.8.1 has just replaced the Pods, and the old ones take a few seconds to disappear. So as not to measure with Pods that are leaving, we wait until only the two current ones remain (another loop with a limit, like the scaling one):

```bash
for _ in $(seq 1 60); do
  [ "$(kubectl get pods -n revisor -l app=revisor --no-headers | wc -l | tr -d ' ')" = 2 ] && break
  sleep 2
done
```

And now, where the replicas are, so as not to stop the node of the Pod acting as the client:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          15s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          17s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

A worker node that is not `depurar`'s (the client that will measure from inside the cluster) is chosen as the victim, and its container is stopped. The victim comes from a list of worker nodes minus the client's; the lesson uses the `case` you already know so as not to stop anything that is not from this cluster:

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

And the client: a loop inside `depurar` that makes one request every 2 seconds for 90, with a 2-second limit on each, and prints only when the result **changes** (one row per change, not one per request):

```bash
ctx && kubectl exec -n revisor depurar -- sh -c 'inicio=$(date +%s); ok=0; mal=0; ant=""; while [ $(( $(date +%s) - inicio )) -lt 90 ]; do t=$(( $(date +%s) - inicio )); if curl -s -m 2 -o /dev/null http://revisor/salud; then r=ok; ok=$((ok+1)); else r=FALLA; mal=$((mal+1)); fi; [ "$r" != "$ant" ] && echo "[+${t}s] $r"; ant=$r; sleep 2; done; echo "bien=$ok mal=$mal"'
```

(The loop is written between single quotes so that the `$(…)` is interpreted by the `sh` *inside* the Pod and not by yours. `date +%s` gives the seconds since 1970; the subtraction with `inicio` is the elapsed time; `curl -m 2` gives up after 2 seconds.)

```text
[+0s] FALLA
[+4s] ok
[+6s] FALLA
[+22s] ok
[+31s] FALLA
[+51s] ok
bien=24 mal=10
```

Read it as a timeline (the rows are *changes*, not requests). It starts failing (`[+0s] FALLA`), answers again at 4 seconds, fails again at 6 and does not answer until 22; it answers until 31, fails again until 51, and **from second 51 everything answers** until the end of the 90. At the end: `bien=24 mal=10`, 34 requests, and the 10 failures all fell before second 51. That matches the mechanism above: the cluster took as long as its heartbeats and its deadline take to notice. What it does not match perfectly is the “alternating”: there are stretches of several seconds in a row failing, not one failure and one success per turn. That is what the Services documentation says: the destination is chosen **at random** on each connection, so now and then several in a row go to the dead address. (Each failed request also costs 2 seconds of limit, which is why fewer requests fit in the window than during the rest of the test.) Nor is it advisable to take the 51 as a constant: in the other three preparation runs of the lesson (stored in `programas/10-proyecto-final/corridas-preparacion/`), the service answered without failing again at 36, 50 and 34 seconds. The four windows, from 34 to 51 seconds, are what the mechanism predicts: they depend on how old the last heartbeat was when the node was stopped (from 0 to 10 seconds), on the controller's check (every 5) and on the seconds that pass between the `docker stop` and the loop's first attempt. [Lesson 9](09-escalar-y-actualizar.md) (9.12.2) measured the same mechanism from another angle: the node turned `NotReady` 57 seconds after being shut down. What holds from one run to the next is the order of magnitude: tens of seconds, not minutes.

And the cluster's state at that instant, **before** bringing the node back:

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

Three facts that seem to contradict each other and do not. The node `curso-k8s-l10-worker2` is `NotReady`: the cluster has already given it up for lost. But the Pod that lives on it still shows as `1/1 Running`: the cluster will keep listing it until the 300 seconds of tolerance run out, and only then will it replace it on another node. And the Service's `EndpointSlice` already marks that Pod's address (`10.244.2.7`) with `listo=false`: it **stopped receiving traffic** even though the list of Pods still shows it. The practical lesson is that `READY 1/1` in `kubectl get pods` and “receives traffic” are not the same thing; to know whether a Pod receives requests you look at the `EndpointSlice` (Lesson 3).

The node is brought back and we wait for it to return:

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

The change in the restart counter takes a while to show. Look at the counter a moment after the node returns to `Ready` (above, `RESTARTS`), wait for it to register the restart with another loop with a limit and look again:

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

The node returns to `Ready`, and the first list of Pods is misleading: it still says `RESTARTS 0` and the earlier IP (`10.244.2.7`). A few seconds later, the counter does change: the Pod `…-qcqfz` says `1 (7s ago)` and, in addition, **has another IP**: `10.244.2.5`. It is the same Pod, with the same name, but its container restarted and its address changed. The `lastState` query explains it: the container's last end had reason `Unknown` and code `255`, that is, no probe or `OOMKilled` killed it; it disappeared with its node, which was shut down entirely, and nobody could record a normal exit code. The other replica, on the node that was never stopped, stayed at zero restarts. Two consequences for you: a non-zero restart counter does **not** always mean something failed in your program (here it was the node), and a Pod IP is not saved for later, which is Lesson 3 again.

**What shortens that window and what does not.** With what you measured, the honest answer:

- **More replicas, spread across more nodes.** If instead of two there are six spread across three nodes, stopping one affects a smaller share of the requests. That is what Lesson 9's scaling and spreading already do: they do not shorten the time, they reduce the portion.
- **Retries in the client.** A request that fails and is repeated lands, with good probability, on the other replica. This test's client does not retry on purpose, so that you see the raw effect; a real one should.
- **A shorter `node-monitor-grace-period`**, in the control plane, which shortens the window at the cost of more false alarms (a node with a network hiccup of a few seconds would be given up for lost). On a managed cluster, you ask the provider; in `kind`, you do not change it in this lesson.

And what does **not** shorten it, even though it seems to:

- **The probes.** They are run by the `kubelet` of the node itself, which is precisely the one that ceased to exist. A probe cannot report the absence of the program that runs it.
- **`tolerationSeconds`.** It decides how long until the Pods are *replaced* on another node, not when they stop receiving traffic. Shortening it replaces them sooner, but traffic would keep going to the dead address until the node is given up for lost.

A sentence that works as a summary: the cluster tolerates a node going down, **not going down without anyone noticing for tens of seconds**. That is the difference between “survives” and “no cuts”, and that is why the course goal says “with a measured window”.

#### 10.8.4 Goal 5: the scaling is still connected

Measuring how long the scaling takes to go up and to go down under load takes 15 minutes and an entire lesson: it is Lesson 9, and it is not repeated here. What is checked is that, on the cluster brought up from scratch, **it is still connected to the metrics**:

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          3m32s
```

In this run, right after restarting the node, the scaling said `cpu: <unknown>/50%`: it lost the metrics reading. It was not investigated which node `metrics-server` runs on or why it was interrupted; what was measured is that a restarted node left the scaling without data for a while. (In other preparation runs of the lesson it did not happen: it already showed the percentage.) It is an example of why the `<unknown>` is not interpreted without looking at what has just happened in the cluster.

If in your cluster it says `<unknown>`, do not panic yet: it is the cause from Lesson 9 and it is solved by waiting, but with a limit. The same loop as 10.5.3, which checks every 5 seconds for up to three minutes:

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

The loop waited and the scaling recovered by itself: `cpu: 3%/50%`, `MINPODS 2`, `MAXPODS 6` and two replicas. A bit more than a minute passed between the two `get` commands (the `AGE` column goes from 3m32s to 4m33s). With this, goal 5 is checked in what this lesson can check: the scaling is connected to the metrics and its limits are those of the base. Scaling replicas up and down under load is Lesson 9.

And if the loop gives up and still says `<unknown>`, the other cause you saw in Lesson 9 is `metrics-server` without the `--kubelet-insecure-tls` flag (which `kind` needs).

### 10.9 Helm, in a mention

There is a tool you will see in almost any Kubernetes project and that this course does not use: **Helm**. The [Helm documentation](https://helm.sh/docs/intro/using_helm/) calls it a package manager for Kubernetes. Four words worth recognizing: a **chart** is a package (a folder of manifest templates plus their default values); the **values** are the values you change for your installation; a **release** is a specific installation of a chart in a cluster; and a **repository** (or an OCI image registry) is where they are published.

The example is in the Envoy Gateway guide you already know. Besides installing it with the `install.yaml` the course uses, [that guide](https://gateway.envoyproxy.io/docs/install/install-helm/) installs it with Helm like this (the command is the guide's for version v1.9.2; **it was not run in this lesson**):

```text
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.9.2 -n envoy-gateway-system --create-namespace
```

`eg` is the *release* name, `oci://docker.io/envoyproxy/gateway-helm` is the chart and `--version` pins its version, with `--create-namespace` to create the namespace where it is installed.

Why does the course use Kustomize and not Helm? Because it compares two different ideas, and for learning it is best to see the simpler one first:

| | Kustomize | Helm |
|---|---|---|
| Idea | starts from complete YAML and **changes it** with layers | starts from **templates** with gaps and **fills them in** with values |
| What you read | plain YAML; what you see is what is applied | templates with logic; to see the result, `helm template` |
| Changes between environments | overlays and patches | value files (`values`) |
| What else it does | nothing: it assembles and hands over to `kubectl` | keeps the history of *releases*, upgrades and can roll back to an earlier version |
| Comes with `kubectl` | yes (`kubectl kustomize`, `apply -k`) | no: it is a separate program |

A widely used rule of thumb, which here is an opinion and not a standard: **Kustomize for what is yours, Helm for what is someone else's.** What is yours is YAML you wrote and want to read; what is someone else's (MetalLB, Envoy Gateway, a monitoring stack) is usually published as a chart with dozens of options that someone else has already thought through. Many teams use both: they install the platform with Helm and their project with Kustomize.

And this lesson's problem exists there too. [Helm's best practices on CRDs](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) say that a chart's CRDs are installed first (they live in a special folder, `crds/`), that **Helm neither upgrades nor deletes them** because of the danger of losing data, and that if a chart needs to use the types it defines itself, the most convenient thing is to split them into two charts that are installed separately. It is the same order (types, controller, project) under another name.

### 10.10 What changes in a real cluster

#### 10.10.1 What you built and what it lacks

There is a temptation at the end of a course: believing that what works on your machine is “almost” ready to run for real. This section exists to defuse it honestly, without drama. `kind` does well what it promises: proving that you **understand** Kubernetes. Its own page says it was “primarily designed for testing Kubernetes itself”, although it can be used for local development or continuous integration. It does not promise a cluster that holds up to what a real service demands. The [Kubernetes documentation on production environments](https://kubernetes.io/docs/setup/production-environment/) opens with a sentence that sums up the difference (translated): a typical production environment “has more requirements than a personal learning, development, or test environment”.

The list that follows has fourteen items. You do not need to remember them all; but you should recognize the pattern: almost all of them are a piece that **exists in `kind` in a lab version** and that in a real cluster must be replaced, reinforced or added. Each one says what the course does, what a real cluster demands, what would be done, and where that comes from.

**1. A single-node control plane.** The course has one control-plane node. If it stops, you cannot change anything, and what else stops working is not certain: in Exercise 3, the containers that had already started kept running, but the entry point only kept responding in 1 of 4 runs. A real cluster replicates the control plane on several nodes and balances the load toward the API server; the [production environments documentation](https://kubernetes.io/docs/setup/production-environment/) lists exactly those pieces, and reminds you that a single-machine environment “has a single point of failure”. Many teams prefer a control plane managed by a provider.

**2. An `etcd` without a tested backup.** The entire state of the cluster (the objects you applied) lives in `etcd`. If it is lost, the cluster is lost. The [`etcd` operation guide](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) shows how to take a copy with `etcdctl snapshot save` and how to check it with `etcdutl snapshot status`. And here the GitLab case from the opening comes back: a backup that has not been restored in a rehearsal is not a backup. It is scheduled, and it is **really restored** on a test cluster at a frequency that somebody decides.

**3. Secrets stored unencrypted.** You saw it in Lesson 4: a `Secret` is base64, and inside `etcd` it is stored in clear text unless the administrator configures encryption at rest. The [guide to encrypting data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) explains how it is configured in the `kube-apiserver`, and the [security checklist](https://kubernetes.io/docs/concepts/security/security-checklist/) asks for it: “encryption at rest is configured for the Secrets API”. For secrets that should not live in the cluster, the same list mentions injecting them from an external store.

**4. Plain-text HTTP.** The `revisor`'s entry point speaks HTTP on port 80, and the token travels in an unencrypted header (Lesson 6 measured it). A real cluster terminates TLS at the *Gateway*: the [Gateway API TLS guide](https://gateway-api.sigs.k8s.io/guides/tls/) describes how an HTTPS *listener* terminates the encryption with a certificate. In addition, it has to be issued and renewed, and the security checklist asks about encryption inside the cluster (which depends on the CNI or on a service mesh).

**5. An address that MetalLB hands out on a Docker network.** In layer 2, the [MetalLB documentation](https://metallb.io/concepts/layer2/) says it: all the traffic for an IP goes to **a single node**, and from there `kube-proxy` spreads it. “In that sense, layer 2 does not implement a load balancer: it implements a failover mechanism.” Its two limits are a bottleneck on one node and potentially slow failover. In the cloud, the provider supplies the load balancer; in your own data center, MetalLB in BGP mode or another load balancer is usually used.

**6. `metrics-server` with `--kubelet-insecure-tls`.** You saw it in 10.3.4: “for testing purposes only”, says its own README. In a real cluster the `kubelet` certificates are signed with the cluster's authority and the flag is unnecessary. Its README adds something that matters: `metrics-server` is **only** for automatic scaling; for monitoring, something else is used.

**7. Nodes that are containers on your machine.** The three “nodes” share your processor, your memory, your disk and your kernel. If your computer shuts down, everything shuts down; there are no availability zones or distinct data centers. A real cluster spreads nodes across zones and spreads the replicas among them (the `ejemplo-nube` patch in 10.3.3 changes exactly that, from nodes to zones), and has more than one of everything that matters.

**8. Storage that lives on the node.** The report volume is a directory on a node's disk (`local-path`, Lesson 8): if the node goes, so does the data. A real cluster uses external storage with replication and copies, and the data has the same backup story as `etcd`: there is a copy, and there is a restore rehearsal.

**9. Images loaded by hand.** The course's two images arrived with `kind load docker-image`, with a local tag. A real cluster pulls them from a registry. The [security checklist](https://kubernetes.io/docs/concepts/security/security-checklist/) asks to refer to them **by `sha256` digest** (because a tag can be moved in the registry), to scan them with a vulnerability scanner and to verify their signature with an admission controller. The course already pins the digest of the `curl` image; those of the `revisor` and the test one, which are local, are not.

**10. A single administrator and no identity.** Your `kind` `kubeconfig` is full administrator; nobody else gets in. A real cluster has users and groups with different permissions, an identity provider and a periodic review of access. The security checklist asks, for example, that the `system:masters` group not be used to authenticate people or components after bootstrap, and a review of access “no more than 24 months” apart.

**11. Observability that is `kubectl logs`.** You have a log while the Pod exists. The [logging documentation](https://kubernetes.io/docs/concepts/cluster-administration/logging/) explains it clearly (translated): if a container crashes, a Pod is evicted or a node dies, you want to keep seeing their logs; that is why they must have storage “with a lifecycle independent of nodes, Pods, or containers”, and Kubernetes “does not provide a native solution” for that. The part about historical metrics and alerts is also missing: someone to warn you before management finds out.

**12. Upgrades without a plan.** The course cluster is created and deleted; a real one is upgraded live, for years. The [supported versions policy](https://kubernetes.io/releases/version-skew-policy/) says the project maintains the three most recent minor versions (today 1.37, 1.36 and 1.35), with about a year of patches, and sets how much difference there can be between components (a `kubelet` may be up to three minor versions behind the API server, never ahead). And each piece of the platform has its own upgrade order: the Envoy Gateway guide asks to update the Gateway API CRDs first, and warns about what happens if that is not done.

**13. No quotas or limits per team.** Lesson 5 put `requests` and `limits` on every container, but nothing prevents someone from creating a hundred Pods. The [quotas documentation](https://kubernetes.io/docs/concepts/policy/resource-quotas/) describes the `ResourceQuota`: restrictions on total consumption **per namespace**, and on the number of objects of each type. With several teams in one cluster, it is what keeps one from eating what belongs to the others.

**14. A platform with no owner and no declared security level.** 10.7.4 showed it: the MetalLB and `kube-system` namespaces do not meet `restricted` (Envoy Gateway's does), and here none of the three has a label or an owner. In a real cluster, each platform namespace has a declared level and a responsible team, and that platform's *webhooks* are a **cluster dependency**: since the default `failurePolicy` is `Fail` (10.4.1), if the guard's Pod is down, the objects it watches cannot be created. That is why they are given more than one replica and are watched like any critical service.

None of this makes what you built useless. Quite the opposite: this lesson's project, the base, with all its objects, **is** what would be taken to a real cluster. What changes is the layer underneath (the overlay and the platform), and that is precisely the layer Kustomize separates.

#### 10.10.2 The fourteen, in one table

| # | In the course | In a real cluster |
|---|---|---|
| 1 | one control-plane node | several control-plane nodes, or a managed one |
| 2 | `etcd` with no backup | `etcd` copies with restore rehearsals |
| 3 | `Secret` unencrypted in `etcd` | encryption at rest and/or an external secret store |
| 4 | HTTP on port 80 | TLS terminated at the Gateway |
| 5 | MetalLB in layer 2 over a Docker network | the provider's load balancer, or MetalLB with BGP |
| 6 | `--kubelet-insecure-tls` | `kubelet` certificates signed by the cluster |
| 7 | nodes that are containers | nodes across several zones, with replicas spread among them |
| 8 | volume on a node's disk | replicated external storage, with copies |
| 9 | images loaded by hand | registry, `sha256` digest, scanning and signing |
| 10 | one administrator | identities, groups, access review |
| 11 | `kubectl logs` | logs and metrics with their own storage and alerts |
| 12 | disposable cluster | upgrade plan per version |
| 13 | no quotas | `ResourceQuota` per namespace |
| 14 | platform with no declared level | level and owner per namespace, and replicas for the *webhooks* |

If you had to order this list by “what would worry me first”, there is no single answer: it depends on what you lose if it fails. But a reasonable criterion is to start with what **cannot be rebuilt**. The project can be rebuilt (you have just done it, twice); the report's data and the state of `etcd` cannot. That is why the backup with a proven restore (items 2 and 8) usually comes before almost everything else, and encryption and TLS (items 3 and 4) go alongside what is exposed. Exercise 4 asks you for exactly that.

## The error you will see

This lesson has three deliberate errors, and you already saw them in their section: the platform applied without `--server-side` (10.4.3), the platform and the project together in a single command (10.4.4) and a Deployment that violates `restricted` (10.7.5). The three have something in common worth stating in so many words, because it is what is really learned: **none is a cluster error**. The cluster did exactly what it was asked and said clearly why it could not. What changed between the failed attempt and the successful one was *the order or the way of asking*, not the cluster.

The order for reading any of them is the same as in the earlier lessons, now with this lesson's tools:

1. What does the `apply`'s **exit code** say, and which lines are **not** a `created` or a `serverside-applied`? The message is there.
2. Does the message mention a **type that does not exist** (`no matches for kind`, `ensure CRDs are installed first`) or a **guard that is not serving** (`failed calling webhook`)? Then you need to wait for the platform: a wait on a condition, not a retry.
3. Does it mention a **size** or a **manager conflict** (`Too long`, `conflict`)? Then it is about the way of applying: `--server-side`.
4. Is it a **warning** (`Warning: would violate PodSecurity`)? The object was accepted and it is not going to work: fix the manifest.

And before changing anything, applying the same command a second time to “see if it works” **is not a diagnosis**: 10.4.4 showed you that sometimes it half works and leaves the worst, a state that looks healthy and is not.

## The lesson's security habit: review against the standard, and say what is missing

The course's table of habits assigns this lesson two things: the final review against the `restricted` level and the list of what a real cluster demands. Both are habits of **not trusting what looks right**.

**The review with a control.** A query that says “no warnings” is worth nothing by itself, because a tool that does not review and one that reviews and finds nothing say the same thing. That is why 10.5.3 counts the warnings (`grep -ci warning`), 10.7.5 applies a Deployment that **does** have to produce them and 10.7.3 tests the review query in a namespace with a Pod that violates: the first query written against `revisor` gave zero warnings and reviewed nothing, and it was that control that showed it. If the second case had not produced warnings, the first would have meant nothing. It is the same principle by which anything is measured: before believing a zero, show it something that should count.

**The list of what is missing.** It is the second habit and the most uncomfortable: writing down what you *do not* have. A project that says “meets `restricted`” and stays silent about its `etcd` having no backup gives a false idea of how protected it is. The list in 10.10 is not an apology; it is the document that lets whoever makes decisions know what risk they are running.

**What it protects against and what it does not.** The review against `restricted` protects against careless configuration: a container that starts as `root`, that can gain privileges or that keeps capabilities it does not need. It does not protect against a vulnerability inside the `revisor`'s program, against a token that leaks, or against an image tampered with along the way. And the list in 10.10 tells you what else would be needed, but does not install it: naming a gap is not solving it.

## Common mistakes

**Retrying until it passes.** It is the `until kubectl apply …; do sleep 5; done` loop. It hides the cause, sometimes leaves a half-done state, and the day it really fails it keeps spinning in silence. You wait for the condition, with a limit.

**A fixed `sleep` between the platform and the project.** It works on your machine and fails on a slower or busier one. A `sleep` measures the clock; `kubectl wait` measures the condition.

**Putting platform and project in a single `kustomization`.** It looks tidier and breaks the order (10.4.4). The two halves have different exit conditions, and that is why they are different commands.

**Applying the platform without `--server-side`.** Large CRDs do not fit in the annotation the client stores (10.4.3). Envoy Gateway's official guide already carries the flag.

**An overlay that copies the base.** If you copy the base's files into the overlay's folder “to change one line”, you have two copies that are going to drift apart. An overlay points (`resources: ../../base`) and patches.

**A script that uses “the active cluster”.** It installs things on whichever context is at hand, which may not be yours. The expected context is passed as an argument and checked before each step.

**`|| true` so that nothing stops.** A script that does not stop at an error does not tell you there was one. If a failure is acceptable, you handle that case and say which one it is.

**Saying “no errors” without having measured it.** Or “no warnings” without a case that produces them. A claim of absence needs a positive control.

**Unpinned versions.** An address that points to “the latest version” changes by itself. Every piece in this lesson carries its version in the path, and the `curl` images their digest.

**Versioning the token.** It is a dummy, but the habit is what matters: the `.gitignore` and the `umask 077`.

**Labeling a platform namespace with `enforce: restricted` without reviewing it.** 10.7.4 showed it: MetalLB and `kube-system` have Pods that `restricted` would reject. A `dry-run` before the label avoids breaking a cluster's network.

**Mistaking `kind` for a real cluster.** It is the one 10.10 develops in fourteen points, and the one that costs the most when forgotten.

## Exercises

Exercises 1 to 3 are run on the lesson's cluster, already brought up as 10.8 left it. Before each one, `ctx` (10.1.2) must pass. `correr.sh` runs them the same way, and its output is in `correr.salida.txt`. **Before** running each one, write in the [logbook](bitacora.md) what you think is going to happen. The fourth is written in your own words.

### Exercise 1 — An overlay of your own

Write an overlay that starts from the `kind` overlay and changes **one single thing**: that the automatic scaling does not go above 4 replicas (today it reaches 6). Without touching the base or the `kind` overlay. Before running it, predict: how many lines of the assembled manifest change, compared with `overlays/kind`? How would you check it **without applying** anything, and how with the cluster but without changing it?

### Exercise 2 — From “bad” to `restricted`

`fig10_02.deployment-malo.yaml` violates the `restricted` level. Fix it until it applies in the `revisor` namespace **without a single warning** and its Pods reach `Available`. Before starting, predict: which controls is it missing? After fixing it, what warning count do you expect? Hint: the list is in 10.7.1, and you already have the positive test from 10.7.5.

### Exercise 3 — The control plane is stopped

In 10.8.3 you stopped a worker node. Now stop the control-plane node (`docker stop curso-k8s-l10-control-plane`) for one minute. Predict beforehand, and write it down: does `kubectl get nodes` answer? Do the `revisor`'s containers keep running on the worker nodes? (Without the API you can ask the node itself: `docker exec <node> crictl ps`.) And the entry point, `http://<address>/salud` from outside the cluster, does it keep responding? Note what you see even if it does not match the solution: the result is not always the same. Then bring the node back, measure how long the API takes to return and check that MetalLB's guard answers before applying anything. With your measurements, explain why the control plane and the worker nodes are called that, and what the list in 10.10 would say about point 1. **A warning:** on your machine, the control-plane node may change IP address when it restarts if another container took its address on the Docker network; if that happens, the cluster stops working and is created again. On the cluster of this lesson's run, with a network of its own and no other containers, it did not happen.

### Exercise 4 — Defend your list

Choose **five** of the fourteen points in 10.10 and, in five lines at most per point: what your project does today, what a real cluster would demand and what you would do, in what order. Then order them by “what would worry me first” and defend first place in three sentences: what is lost if it fails, and can it be rebuilt?

## Solutions

### Solution 1

The overlay is `fig10_03.overlay-mio/kustomization.yaml`:

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

Measured in `correr.salida.txt`:

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

A single line changes. `kubectl kustomize` prints the result without touching anything: `maxReplicas: 4` on line 391, and `minReplicas: 2` intact on 399. With the cluster, `kubectl diff --server-side` compares what you would apply against what is there and shows exactly `-  maxReplicas: 6` and `+  maxReplicas: 4`; the `[código de salida: 1]` is `kubectl diff`'s when there **are** differences (0 if there are none). And the proof that the base was not touched: `base/escalado.yaml` still has its single `maxReplicas` line. To apply it, `kubectl apply --server-side -k fig10_03.overlay-mio` would be enough; the exercise does not ask for it so that the cluster remains what the lesson's files say.

### Solution 2

The fix is `fig10_04.deployment-corregido.yaml`: the same Deployment with `automountServiceAccountToken: false`, the Pod's `securityContext` (non-`root`, user 65532, *seccomp* `RuntimeDefault`) and the container's (no privilege escalation, read-only filesystem, no capabilities), plus resource floor and ceiling.

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

Measured in `correr.salida.txt`:

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

The warning count is **0**. That command had already applied the Deployment (the `grep` only counts what `apply` prints), which is why the second `apply` says `unchanged`: there was nothing to change. The Deployment reaches `1/1` and `Available`, so its Pods are no longer rejected. Each control has its field: `allowPrivilegeEscalation: false` and `capabilities.drop: ["ALL"]` on the container; `runAsNonRoot: true` (with `runAsUser: 65532`) and `seccompProfile.type: RuntimeDefault` on the Pod. The rest (`readOnlyRootFilesystem`, `automountServiceAccountToken: false`, floor and ceiling) is not asked for by `restricted`; the course asks for it.

### Solution 3

Measured in `correr.salida.txt`:

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

Read it in order. **The API does not answer**: `kubectl` is left with `connection … was refused` against `127.0.0.1` (the port that `kind` publishes from the control-plane node). Without the control plane you cannot see, create, change or delete anything. **The containers stayed alive** in the two runs where it was checked (preparation run 5 and the lesson's): without the API, but with access to the node, `crictl ps` lists the `revisor` and the two Envoy containers running, and a `curl` from the node to the Pod's IP answers `{"estado":"vivo","version":"1.6.0"}`. That says the containers do not shut down by themselves; it does not say the service reaches whoever asks for it. **The entry point**, in this run, answered all 23 requests (`bien=23 mal=0`) during the 45 seconds. And here is a warning that was measured and not explained: in **three preparation runs** of this same lesson (stored in `programas/10-proyecto-final/corridas-preparacion/`: `corrida1.txt`, `corrida4.txt` and `corrida5.txt`), with the same exercise, the entry point answered none of its requests while the control plane was stopped (`bien=0 mal=12`, 12 of 12 failed, in 4 and 5; in 1, `curl` exited with code 7, connection refused, instantly). In total, the entry point answered in 1 of 4 runs, even though `ServiceL2Status` (measured in the last two) said that a worker node was announcing the address. The cause was not found. The honest thing is one sentence: in `kind`, with MetalLB and Envoy Gateway, **do not take for granted** that the entry point survives without a control plane, nor the opposite: with 4 runs nothing more can be said than “1 of 4”. Note what you see in yours; it may differ from this solution's. **The API came back** 59 seconds after the control-plane node was stopped.

And a second lesson, from the last check. When the control-plane node returns, `kubectl wait` says the three nodes are `Ready`, but that does not mean everything else is ready. In a preparation run, the final `kubectl diff` failed with `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connection refused`: MetalLB's guard was not answering yet (10.4.1, once again). That is why the script asks the guard with a dry run of the range, `kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml`, and waits with a limit for it to answer. In this run it answered on the first attempt: `ipaddresspool.metallb.io/curso configured (server dry run)`. The two `Warning` lines that accompany it are not about security: they say the range was created with `--server-side` and does not have the `last-applied-configuration` annotation that client-side `apply` uses. It is the difference from 10.4.2, and here it is harmless because it is a dry run. After the wait, `kubectl diff --server-side -k overlays/kind` says `sin diferencias con los archivos` (no differences from the files).

What this says about point 1 of 10.10: a single-node control plane is a single point of failure: without it you cannot **change** anything and nobody replaces or scales; what is already running can keep running (the containers did) or stop being reachable (the entry point, 3 times out of 4), and it was not found what that depends on. And why they are called that: the control plane **decides** (what must exist and where); the worker nodes **execute**.

### Solution 4

One possible answer, for the list of five: “**(2) `etcd` without a backup**: today there is no copy; a real cluster schedules `etcdctl snapshot save` and *really restores* on a test cluster every so often, and I do it first because it is the only thing I cannot rebuild with `kubectl apply`. **(8) Volume on a node's disk**: today the report lives on the node; in a real one, replicated storage and copies, with the same restore test. **(3) Unencrypted secrets**: today they are base64 inside `etcd`; I would configure encryption at rest and, for secrets that should not live in the cluster, an external store. **(4) HTTP on port 80**: I would terminate TLS at the Gateway and rotate the token, which has traveled in plain text. **(1) One-node control plane**: three control-plane nodes or a managed plane.” The order of concern: first what cannot be rebuilt (2 and 8), then what is exposed (3 and 4), last availability (1). Defense of first place: “If an `etcd` with no backup fails, I lose the cluster's state; the project is rebuilt with two commands and a wait (I tested it twice), but what the cluster knew about itself is not. And a backup that was never restored is not an answer: it is a hypothesis.”

## Deleting the cluster

When you finish, delete the lesson's cluster and what you left on your machine. Leave nothing alive:

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

(The lines in parentheses are written by the script, which measures the deletion. The `grep -c` prints `0` and exits with code 1, because it found no cluster with that name: it is the answer you are looking for.) The `case` only lets through a path that starts with `/tmp/curso-k8s-l10.` and has something after it, the exact form of the one you created in 10.1.2. If `L10_TMP` is empty or holds anything else, it deletes nothing and tells you why. If you did Exercise 3 in a second terminal, close it. And if you used a Docker network of your own (this lesson's run did; you, with the `kind` network, will not), delete it **after** the cluster and only if you created it: `docker network rm <name>`.

This was the last cluster of the course. You already deleted those of the earlier lessons, one per lesson, and that completes the method: create, use, delete, and be able to create again.

## How I know I made it

- [ ] You open a `kustomization.yaml` and say what a base is, what an overlay is, what it assembles and how to check it with `kubectl kustomize` without applying anything.
- [ ] From an empty cluster, you bring the project up with the platform, a wait on a condition and the project, and you explain why that order.
- [ ] You read `no matches for kind … ensure CRDs are installed first` and the message for a CRD that is too large without `--server-side`, and say what causes them.
- [ ] You run `programas/10-proyecto-final/probar-levantar.sh` and compare its output with `programas/10-proyecto-final/correr.salida.txt` in what does not change between runs: the platform applied with `serverside-applied`; the five waits with `condition met` or `successfully rolled out`; the project with its objects and without a single `Warning` line; the Gateway `Programmed`; `{"estado":"vivo","version":"1.6.0"}` from outside, in both rounds; and that the cluster no longer exists at the end. The IPs, the name suffixes, the ages and the seconds change on every run: they are observed, not compared.
- [ ] You know why `kubectl label --dry-run=server … enforce=restricted` on `revisor` (which already has it) answers `not labeled` without reviewing any Pod, and you review the existing Pods by asking for a different policy (`enforce-version=v1.36`), with the control from the `psa-control` namespace that names the Pod that violates and not the one that complies.
- [ ] You stop a worker node, measure the window in which requests fail and explain why it lasts as long as it does and what reduces it.
- [ ] You change the list of services and see a new `ConfigMap` and a new ReplicaSet without rebuilding the image.
- [ ] The `intruso` does not reach the `revisor` and `depurar` does; the `revisor` account cannot even read Pods.
- [ ] `kubectl get hpa` shows a percentage, not `<unknown>`.
- [ ] You write, in your own words, five reasons why what you built is not a real cluster, what you would do about each and which one you would start with.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l10`.

## Summary

Answer without looking at the lesson:

1. What is a base and what is an overlay? Does a base know about its overlays?
2. What is the difference between a platform piece and a project piece, and what three things does a platform bring?
3. What condition does `kubectl wait` wait for on a CRD, and which on a Deployment?
4. What does `--server-side` change and what error does it avoid on the platform?
5. What happens if you put platform and project in a single command, and why is repeating it “to see if it works” not a method?
6. Why does a bring-up script receive the context as an argument and check it before each step?
7. What does the `restricted` level ask for and what does the project do beyond that?
8. Why does part of the platform (MetalLB, `kube-system`) not meet `restricted`, and what condition do you set for that to be acceptable?
9. With a worker node stopped, why do requests fail for tens of seconds and what does not shorten that window?
10. When would you use Helm instead of Kustomize?
11. Name five reasons why the course cluster is not a real cluster and what you would do about each.

## Sources

All consulted on October 21, 2026.

- [Kubernetes, “Declarative Management of Kubernetes Objects Using Kustomize”](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): bases and overlays, generators with a *hash*, `patches`, `images`, and `kubectl kustomize` / `apply -k`.
- [Kubernetes, “Server-Side Apply”](https://kubernetes.io/docs/reference/using-api/server-side-apply/): field managers, conflicts, and the comparison with client-side `apply`.
- [Kubernetes, “Custom Resources”: CustomResourceDefinition](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/): a CRD's `Established` condition.
- [Kubernetes, “Dynamic Admission Control”](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): admission *webhooks* and `failurePolicy` (default `Fail`).
- [Kubernetes, “kubectl wait”](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): waiting for a condition on one or many resources.
- [Kubernetes, “Virtual IPs and Service Proxies”](https://kubernetes.io/docs/reference/networking/virtual-ips/): that `kube-proxy` picks a Service's destination Pod at random in `iptables` and `nftables` modes.
- [Kubernetes, “Pod Security Standards”](https://kubernetes.io/docs/concepts/security/pod-security-standards/): the `baseline` and `restricted` controls, field by field.
- [Kubernetes, “Pod Security Admission”](https://kubernetes.io/docs/concepts/security/pod-security-admission/) and [“Enforce Pod Security Standards with Namespace Labels”](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): the `enforce`, `audit` and `warn` modes, the pinned versions, and the test with `--dry-run=server`.
- [Kubernetes, “Node Status”](https://kubernetes.io/docs/reference/node/node-status/), [“kube-controller-manager”](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) and [“Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): the 50 seconds of `node-monitor-grace-period` and the 300-second toleration.
- [Kubernetes, “Production environment”](https://kubernetes.io/docs/setup/production-environment/), [“Security checklist”](https://kubernetes.io/docs/concepts/security/security-checklist/), [“Encrypting Confidential Data at Rest”](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/), [“Operating etcd clusters”](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/), [“Logging Architecture”](https://kubernetes.io/docs/concepts/cluster-administration/logging/), [“Resource Quotas”](https://kubernetes.io/docs/concepts/policy/resource-quotas/) and [“Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/): what a real cluster demands and the versions policy.
- [kind, *issues* #4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) and [#4224](https://github.com/kubernetes-sigs/kind/issues/4224): `kind load` failures with Docker 29 and the `containerd` image store (the warning in 10.1.2).
- [kind](https://kind.sigs.k8s.io/): what `kind` was designed for. And [`provider.go` in kind v0.33.0](https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provider.go): the `KIND_EXPERIMENTAL_DOCKER_NETWORK` variable, which this lesson's run used.
- [Envoy Gateway, “Install with Kubernetes YAML”](https://gateway.envoyproxy.io/docs/install/install-yaml/) and [“Install with Helm”](https://gateway.envoyproxy.io/docs/install/install-helm/): installation with `--server-side`, installation with Helm and the CRD upgrade order.
- [MetalLB, “Layer 2 mode”](https://metallb.io/concepts/layer2/): how it works and its two limits.
- [metrics-server v0.9.0, README](https://github.com/kubernetes-sigs/metrics-server/blob/v0.9.0/README.md): `--kubelet-insecure-tls` “for testing purposes only”, and that it is only for automatic scaling.
- [Gateway API, “TLS”](https://gateway-api.sigs.k8s.io/guides/tls/): terminating TLS at a *listener*.
- [Helm, “Using Helm”](https://helm.sh/docs/intro/using_helm/) and [“Custom Resource Definitions”](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/): what a chart is and how it treats CRDs.
- [RFC 6902, “JavaScript Object Notation (JSON) Patch”](https://www.rfc-editor.org/rfc/rfc6902.html): the `op: replace` operations of the patches in 10.3.3.
- [RFC 2606, “Reserved Top Level DNS Names”](https://www.rfc-editor.org/rfc/rfc2606.html): `example.com` reserved for examples.
- [GitLab, “Postmortem of database outage of January 31”](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): the public report of the opening case.

---

**End of the course.** Go back to the [index](README.md) or open the [logbook](bitacora.md) and write down what you want to build next.
