# Lesson 9 — Scaling and updating, measuring every outage

Monday, 8:57 in the morning. At 9:00 the operations team does its weekly cutoff, and forty people are going to open the `revisor`'s report at almost the same moment. Last Monday something similar happened. At 9:01 the dashboard slowed down; someone raised the replicas by hand, from three to eight, to “hold out”; and forgot to lower them again. At 9:04 someone else applied an urgent fix, and for a few seconds several users saw an error on screen. Nobody knows how many. Today the head of operations asks three questions, and the meeting starts in three minutes: how many replicas does the service really need, and who decides when there are too many? How many requests are lost during an update? And what happens if one of the cluster's servers goes down? Your answer to all three, a week ago, was the same: “it should be fine”.

That sentence is the problem. In Kubernetes, “it should be fine” can be turned into a number, and this lesson is the workshop where that happens. It is not a story made up to scare you. In 2019, an engineer named Phil Pearl wrote on his blog that, when moving an API to a Google Kubernetes cluster behind an Ingress, his tests received `502` errors every now and then. Looking for the cause, he found something almost nobody was saying at the time: when a Pod shuts down, the shutdown notice and the removal of that Pod from the list of network targets happen **at the same time**, not one after the other; the step that takes the Pod off the list does not wait for the step that shuts it down. What varies is how long the news takes to reach each load balancer: according to Pearl, a lot with an Ingress and little with a Service. With that race, a request can reach a Pod that is already closing ([Phil Pearl, “Kubernetes' dirty endpoint secret and Ingress”](https://philpearl.github.io/post/k8s_ingress/), July 26, 2019). What you learn today is how to measure that race in your own cluster, how to close it with a few lines, and how not to believe a measurement more than it deserves.

This lesson has three parts. The first teaches the cluster to **scale by itself**: a consumption meter (`metrics-server`), an autoscaler that uses a formula you will be able to calculate by hand, and a spreading rule so the replicas do not pile up on one node. The second teaches how to **update and drain without surprises**: an update measured with a poller of our own, with and without the pause that closes the race, the history for going back, and a disruption budget facing the maintenance of a node. The third **breaks a server on purpose** and measures how long the outage lasts. Every figure you will see came from running the procedure, and every figure comes with what limits it.

**Time:** 2 × 45 min of reading and practice; the full run of the script takes quite a lot longer (“About the runs” says so), because the waits are part of what is taught

**What you build:** the `revisor` that scales replicas up and down with the load, spread across the two worker nodes, that is updated with a poller counting every lost request and that survives a node being shut down with a loss that is measured and explained

**What you learn:** why `metrics-server` as is does not work in kind and what the flag that fixes it changes; the `HorizontalPodAutoscaler` formula, its 10% tolerance and the window that delays scaling down; why a Deployment managed by an autoscaler carries no `replicas`; spreading across nodes with `topologySpreadConstraints` and why the control-plane node requires `nodeTaintsPolicy: Honor`; `RollingUpdate` with `maxSurge` and `maxUnavailable`; the race between shutdown and the Service's endpoints, and the `preStop` that closes it; `rollout history` and `rollout undo`, and why `rollout status` can finish while the old Pods are still answering; the `PodDisruptionBudget` and a `drain` that gets stuck on purpose; and the window of a failed node, with what shortens it and what does not

**Where you are coming from.** From [Lesson 8](08-datos-y-tareas.md): the `revisor` lives in its own namespace, `revisor`, with the closed network of [Lesson 7](07-aislar-permisos-red.md), a volume for its reports and a scheduled task. From [Lesson 5](05-salud-recursos-apagado.md) you bring what today becomes a calculation: the CPU `requests` (`50m`), which are the yardstick the autoscaler uses to measure the percentage, and the shutdown grace period, which today is tuned with a pause before the termination signal. From [Lesson 6](06-entrar-al-cluster.md) you bring the platform: MetalLB and Envoy Gateway already installed, with the “platform, wait, project” order that today is repeated in a single script. And from [Lesson 3](03-services-dns.md), the `depurar` Pod and the habit of looking at `ENDPOINTS` before blaming anyone.

**What this lesson does not do.** It does not scale **nodes**: in kind the three nodes are fixed containers, and adding or removing machines is the job of another component that a real cluster has and this lab does not. It does not scale vertically (giving each replica more CPU) or with custom metrics (requests per second, the size of a queue). It does not do blue-green or canary updates: the only strategy here is the rolling one that Kubernetes ships with. It adds no encryption. And it is not a serious load test: the lesson's load is a `curl` Job in a loop, enough to see the autoscaler react and nothing more. [Lesson 10](10-proyecto-final.md) puts everything together in two commands and lists what this is still missing to be production-ready.

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1, the `kindest/node:v1.37.0` node image pinned by its digest (Kubernetes v1.37.0), **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** and **`metrics-server` v0.9.0**, on the three-node cluster from Lesson 1, called `curso-k8s-l9` here. The machine was an ARM-based Mac with Docker Engine 29.2.1 inside a Linux virtual machine (Colima) with 6 CPUs and 16 GiB of memory, **not** Linux Mint, which is the course's reference system. And it was **shared**: while this lesson ran, other lessons of the course were running on the same machine with their own clusters, and the system load (the average shown by `uptime`) went from under 5 to over 40 during the work. That matters for reading two kinds of figures: the **times** (pulling the MetalLB images took, in earlier attempts, several minutes per node, and `preparar.sh` has long waits because of that) and the **request counts** in 9.9 and 9.12, which depend on how much CPU the poller's client received. Each section says which figure depends on what. What changes on your Mint: the architecture (`amd64` instead of `arm64`), the IPs of the Pods, the Services and the nodes, the name suffixes, the ages, the node where each replica lands and, above all, the request figures: they are yours, and they are not to be compared with the ones here. There is also a network difference worth stating. **The run of this lesson used a Docker network of its own**, `curso-k8s-red-l9`, with the subnet `172.29.0.0/16`, so it could run at the same time as other lessons that also install MetalLB without stepping on each other; that is why the nodes' IPs appear as `172.29.0.x` and the Gateway's entry point as `172.29.255.200`. On your machine, with the normal `kind` network, the IPs come out as `172.18.0.x` and the entry point as `172.18.255.200`, which is what `preparar.sh` does by default. `correr.sh` does the same if you run it with `RED=kind SUBRED=172.18.0.0/16` (its default values) and stops before creating anything if the network does not have the expected subnet. The complete walkthrough is in [`programas/09-escalar-y-actualizar/`](../programas/09-escalar-y-actualizar): `correr.sh` creates the cluster, loads the three images into it, brings it to Lesson 8's state with `preparar.sh`, goes through the lesson in order and deletes it. Its output is `correr.salida.txt`. The complete run took 1,809 seconds (30 minutes and 9 seconds): creating the cluster and waiting for it to be ready, 37 seconds; `preparar.sh`, 343; deleting the cluster, 2; the rest is the waits that the lesson teaches you to do (the load and the autoscaler's scale-down, the seven update polls, the node that is shut down). The image that does not exist in 9.10.4 is run separately, with `fig09_02.imagen-rota.sh` (its output is `fig09_02.imagen-rota.salida.txt`), on a cluster of its own, minimal, which takes about four minutes. It needs internet: the `metrics-server`, MetalLB and Envoy Gateway manifests are downloaded from their releases, pinned to their version, and their images are pulled the first time.

## By the end you will be able to

- Explain why `metrics-server` does not start as is in kind, read the `x509` in its log, apply the flag that fixes it and say why that flag is for the lab only.
- Calculate by hand how many replicas a `HorizontalPodAutoscaler` will ask for from the current replicas, the measured CPU percentage and the target, applying the 10% tolerance, and check it against the `TARGETS` column.
- Write a `HorizontalPodAutoscaler` with a floor, a ceiling and a scale-down window, and explain why the Deployment it governs no longer declares `replicas`.
- Spread the replicas across the nodes with `topologySpreadConstraints`, and explain `maxSkew`, `DoNotSchedule`, `nodeTaintsPolicy: Honor` and `matchLabelKeys`.
- Measure with a poller how many requests fail during an update, with and without `preStop`, and say what that measurement proves and what it does not.
- Use `rollout history` and `rollout undo`, look at `deletionTimestamp` before concluding that a rollback did not work, and read an update with an image that does not exist (`ErrImagePull`), checking that the service is not interrupted.
- Trigger a `drain` blocked by an overly strict `PodDisruptionBudget`, read it and fix it; shut down a node, measure the failure window and explain what shortens it and what does not.

## The why before the how

Until now, the `revisor`'s number of replicas was decided by you, written in a file. That is a good decision for learning and a bad one for a Monday at 9:00. If the load triples, nobody is typing in that file. And if the load drops, three replicas keep eating CPU and memory that other Pods could use. The first question of the lesson is, then, **who decides how many replicas are needed, with what information and with what brake?** The answer has three components. A meter, `metrics-server`, that looks at how much CPU and memory each Pod uses. A controller, the `HorizontalPodAutoscaler` (HPA), that compares what was measured with a target and adjusts the number of replicas. And a spreading rule, so the new replicas do not all land on the same machine, because three replicas on a single node go down together with that node.

The second question is **what happens to the traffic while something changes?** Many things change in a live cluster: a new version, a node going into maintenance, a node that goes down without warning. Each has a different answer, and the difference matters. An update is *planned*: Kubernetes can change replicas one at a time and wait for the new one to be ready. A maintenance is *negotiated*: you can tell the cluster how many replicas have to stay up, and the cluster respects that number when it evicts. A failure *surprises*: nobody asked permission and the cluster takes a while to find out. The lesson uses the three cases as an excuse to measure. Measure, do not guess, because each of the three answers is a number that changes with the configuration, and that number is the answer to the director.

And there is a third question, a more uncomfortable one: **how do you measure the outage without fooling yourself?** A poller that sends a few requests and sees no failure does not prove there are no failures; it proves that *that time, at that pace*, none were seen. The lesson says so each time it measures something, and it repeats the measurements where that is cheap. It is the habit that separates a report from an anecdote.

The lesson has ten parts of concepts and then the usual sections:

1. **The cluster and the starting point** (9.1): the state in which Lesson 8 ends, brought up with a script.
2. **Measure before scaling** (9.2): `metrics-server`, the flag and why.
3. **The autoscaler and its formula** (9.3): `HorizontalPodAutoscaler`, tolerance, window and why `replicas` leaves the Deployment.
4. **Spreading the replicas** (9.4): `topologySpreadConstraints`.
5. **Applying the changes** (9.5): what `kubectl diff` shows and the replica mess hidden in it.
6. **With load, the autoscaler scales up** (9.6).
7. **Without load, it scales down, after the window** (9.7).
8. **Who is in charge of the replicas** (9.8).
9. **Updating and measuring the outage** (9.9), with the poller, the `preStop` and the rollback (9.10).
10. **Maintenance and the failure of a node** (9.11 and 9.12): `PodDisruptionBudget`, `drain` and a node shut down.

This is the destination. At the end of 9.6, under load, the autoscaler has already changed the number of replicas and shows it on a single line:

```text
$ kubectl get hpa revisor -n revisor --no-headers
revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

It is one line from the run (the last of the wait in 9.6): the HPA `revisor`, which governs the Deployment `revisor`, measures `38%` against a target of `50%`, has a floor of 2 replicas, a ceiling of 6, and today is running 4.

## If you don't have the Docker course image

This lesson uses three local images: `curso-docker-revisor:1.6.0`, the `revisor` image from Lesson 2; `curso-docker-prueba:1.0.0`, the one for the service that fails on purpose; and a new one, `curso-docker-revisor:1.6.1`, which exists so that the lesson's update has something to update. The two `revisor` images come from the same `Dockerfile` and the same code: the only thing that changes is the version the service reports at its `/salud` (`"version":"1.6.0"` or `"version":"1.6.1"`), and that is precisely what lets you see, request by request, which replica answered. Check that you have them:

```text
$ docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E '^curso-docker-(revisor|prueba):'
curso-docker-revisor:1.6.1 61c70431badb
curso-docker-prueba:1.0.0 400d3fd59edc
curso-docker-revisor:1.6.0 bd1b2e7d91b8
```

(This output is from the author's machine and is not in `correr.salida.txt`. The identifiers come from it; on yours they may be different if you built the images yourself. What matters is that all three tags exist.) If you are missing `1.6.1`, build it the same way as `1.6.0`, from the Docker course repository, with the `Dockerfile` from its Lesson 10 over the `programas/revisor` folder and with `--build-arg VERSION=1.6.1`, tagging it exactly `curso-docker-revisor:1.6.1`. It is a lab image: it is there to let you see an update, it is not a new version of the service.

## The concepts

### 9.1 The cluster and the starting point

#### 9.1.1 A coexistence rule, again

This lesson installs MetalLB (through `preparar.sh`, 9.1.3), and the rule from Lesson 6 still stands: two clusters with MetalLB and the same address range, on the same Docker network, step on each other. Before creating yours, check the `kind` network and that nobody already answers on the first address of the range:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar en 172.18.255.200. Si este curl responde, hay otro
# clúster con MetalLB vivo: espera a que termine.
# Si imprime un número (200, 404…), alguien contesta; si imprime 000, nadie.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -o /dev/null -w '%{http_code}\n' -m 3 http://172.18.255.200/
kind get clusters
```

If the `kind` network does not exist yet because you have never created a cluster, create the cluster and check the network right afterwards. There is also a lab detail worth stating right now, because it changes the addresses you will see in the outputs: the run of this lesson used **a Docker network of its own**, `curso-k8s-red-l9`, with the subnet `172.29.0.0/16`, so it could run at the same time as other lessons that also install MetalLB. On your machine, with the normal `kind` network, the addresses of the range come out as `172.18.255.x`, not `172.29.255.x`; the `correr.sh` script adapts with two variables, `RED` and `SUBRED`, and has the usual brake: if the network does not have the expected subnet, it stops before creating anything.

#### 9.1.2 Creating the cluster and loading the images

From the root of the course repository:

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

The `ctx` function compares the active context with the expected one; if they match, it prints nothing, and if not, it writes “contexto equivocado: no sigo” (wrong context: I'm not continuing) and returns an error that cuts the `&&` chain. In this lesson it goes in front of every command that **changes** something (`apply`, `patch`, `scale`, `drain`, `delete`); in the outputs that follow it is left out so they fit, but in your terminal it goes in. Commands that only **read** (`get`, `top`, `describe`) do not need it, although it does no harm. `correr.sh` does the check before each command in a different way, with a function that stops by itself.

The `(umask 077; …)` makes `token.txt` be born `-rw-------`: the `077` mask removes all permissions from the group and from others, and the parentheses make the change apply only to that command. It is the care taken in Lessons 4 to 6, and it is repeated because a habit that is skipped once is no longer a habit.

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

Creating the cluster and waiting for its nodes and the `kube-system` Pods to be ready took 37 seconds, with the node image already downloaded beforehand. There are three `Ready` nodes on `v1.37.0`: one control-plane node and two worker nodes. The `INTERNAL-IP` column is each node's address on the Docker network; here it falls in `172.29.0.x` because of the run's own network, and on your machine it will fall in `172.18.0.x`. Loading the three images with `kind load` prints its usual lines (`not yet present on node … loading...`); `correr.sh` silences them and notes instead that they were loaded.

#### 9.1.3 The starting point: `preparar.sh`

Lesson 8 ends with a cluster that already has Lesson 6's platform and Lesson 8's project. To avoid repeating a few minutes of manual installation, `preparar.sh` rebuilds them with **the three steps of Lesson 6, in plain sight and in the same order**: the platform (MetalLB and Envoy Gateway), the wait with `kubectl wait` until they are ready, and finally the address range, the gateway class and the project from the `punto-de-partida/` folder. If you come from Lesson 8 with your cluster alive, you do not need it; if you are starting here, or if you already deleted it, you run:

```bash
ctx && ./preparar.sh
```

It is a **program**: `preparar.sh`. Read it before running it: it hides nothing. Each step checks the context, prints the command it is about to run and stops if it fails. It accepts one variable, `POOL_RANGO`, to change MetalLB's range if your network is not `172.18.0.0/16`. A note on the width: `infra/metallb-pool.yaml` and `preparar.sh` use `.200-.220`, while `correr.sh` calculates `.200-.250`, which is the one you see below. Here it does not matter, because only the first address of the range is used, the Gateway's.

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

It reads in three beats, the same as in Lesson 6. In **step 1**, the MetalLB and Envoy Gateway platforms are applied; their outputs are sent to `/dev/null` because they are dozens of lines of no interest. In **step 2** come the waits, all with `kubectl wait` or `rollout status` and all with a deadline: MetalLB's new types (`condition met`), the controller, a `speaker` ready on each of the three nodes, the Gateway API types, the Envoy Gateway controller. In **step 3** the address range is applied (a temporary file that `preparar.sh` generated from `infra/metallb-pool.yaml` with the range of the run's own network: that is the effect of `POOL_RANGO`), the `eg` gateway class, and finally the project from `punto-de-partida/`, with its `rollout status` and the wait for the Gateway to be `Programmed`. It all took 343 seconds; most of it spent waiting for image downloads. This is the lesson's starting point:

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

Three replicas of the `revisor`, the test service's one, no HPA or PDB yet (the last `get` does not list them because they do not exist), and a Gateway `PROGRAMMED True` on the first address of the range. The last command is the “outside” client from Lesson 6, a `curl` container connected to the Docker network, asking for `/salud` through the entry point: `{"estado":"vivo","version":"1.6.0"}`. If that answers, the platform and the project are up.

### 9.2 Measure before scaling: `metrics-server`

#### 9.2.1 What the cluster does not know yet

Before deciding how many replicas are needed, you have to know how much CPU the existing ones use. The cluster does not know that out of the box. If you ask it with `kubectl top`, the command that shows consumption:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]
```

`error: Metrics API not available`. The sentence has an exact subject. Kubernetes defines an API for the CPU and memory consumption of nodes and Pods, the **Metrics API**, and the documentation describes it like this: it offers “a basic set of metrics to support automatic scaling and similar use cases” ([Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)). But that API is only a *shape* for asking: someone has to answer. The same page says it plainly: you must deploy `metrics-server` “or an alternative adapter” to be able to use it, and its main role is to “feed resource usage metrics to the autoscaling components”. A freshly created cluster does not have it, and that is why `top` has nobody to ask.

How do you plug an answerer into the Kubernetes API? With an object you already know from Lesson 6, by kinship: a resource that teaches the `kube-apiserver` something new. Here it is not a CRD but an `APIService`, which tells the `kube-apiserver`: “the questions that arrive at `/apis/metrics.k8s.io/v1beta1`, do not answer them yourself; forward them to this Service”. Before installing anything, that object does not exist:

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
Error from server (NotFound): apiservices.apiregistration.k8s.io "v1beta1.metrics.k8s.io" not found
[código de salida: 1]
```

With `NotFound`: the `kube-apiserver` has nobody to forward to. It is the same situation as in Lesson 6 with `Gateway`, seen from another side: before the component exists, asking about it is asking the void.

#### 9.2.2 Installing `metrics-server` as it comes

The project publishes one manifest per version. The one this lesson uses is **v0.9.0**, and it is pinned in the URL, the way everything else in the course was pinned: without a pinned version, the day the latest version changes, your lab changes without warning you. It is applied as is, changing nothing, to see what happens:

```text
$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml | tail -3
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
(espera visible: hasta 600 s a que metrics-server descargue su imagen, arranque e intente leer a los kubelet)
```

The three lines you see are the last of several (`| tail -3`): a `Service`, a `Deployment` and the `APIService` that connects both with the `kube-apiserver`. About the moment of looking: the Deployment does not become ready instantly. First it has to download its image and start, and then attempt its first read. The script waits, in plain sight, until the Pod's log shows the error we want to read (up to 600 seconds, because on a slow machine the download takes a while). In your terminal, you can repeat `kubectl get deployment metrics-server -n kube-system` until you see `0/1` with a few seconds of age. It is a different kind of wait from `kubectl wait`: here you are not waiting for a condition to *arrive*, you are waiting to *give it time to fail* so you can read how.

```text
$ kubectl get deployment metrics-server -n kube-system
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   0/1     1            0           30s
```

`READY 0/1` and `AVAILABLE 0`: the Pod exists but is not ready. We follow the order from Lesson 5, which says what to look at first when something does not start: the Pod's log.

```text
$ kubectl logs -n kube-system deployment/metrics-server --tail=200 | grep -E 'x509|tls|certificate' | tail -1
E1021 23:14:05.707527       1 scraper.go:149] "Failed to scrape node" err="Get \"https://172.29.0.2:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs" node="curso-k8s-l9-control-plane"
```

It reads left to right. `E1021` is an *error*-level line from October 21. `scraper.go:149` is the place in the code that failed, and `Failed to scrape node` says what it was trying to do: “scrape” (collect) the node's metrics, which is what `metrics-server` does every few seconds, asking each `kubelet` for the CPU and memory its Pods use. The address is `https://172.29.0.2:10250/metrics/resource`: the `kubelet` of that node (the control-plane one; on your machine it will be `172.18.0.x`), by its IP, on port 10250. And the cause, at the end: `tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs`.

That sentence has to be taken apart. TLS is the encryption `metrics-server` uses to talk to the `kubelet` (HTTPS). For the encryption to be worth anything, `metrics-server` verifies the **certificate** the `kubelet` presents: it checks that an authority it trusts signed it and that the certificate claims to belong to the address it connected to. A certificate carries a list of valid names and addresses, the *Subject Alternative Names* (SANs). Here the `kubelet`'s certificate has no **IP** in that list, and `metrics-server` connected by IP: that is why it cannot validate that “`172.29.0.2`” is who it says it is. What the log proves is only that: the certificate carries no IP. The `metrics-server` README lists as a requirement that the `kubelet`'s certificate be signed by the cluster's authority ([metrics-server](https://github.com/kubernetes-sigs/metrics-server)), and in kind the nodes do not meet it as is. In a real cluster, that is fixed on the nodes; in this lab it is not attempted.

With the Pod not ready, the `metrics-server` `Service` has no endpoints, and the `APIService` reflects it:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]

$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE                  AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   False (MissingEndpoints)   30s
```

`AVAILABLE False (MissingEndpoints)`: the endpoints are missing. The Service has nobody to send the questions to because the only Pod is not ready. Now the `kubectl top` error has its complete chain: the command asks the `kube-apiserver`; this forwards to the Service; the Service has no endpoints; the only endpoint is not ready; and it is not ready because it cannot verify the `kubelet`'s certificate. Five links, and the message at the top showed only the last. It is the same craft as in Lesson 3: you go down floor by floor until you find the one that fails.

#### 9.2.3 The flag, and why it is for the lab only

`metrics-server` has an option to skip verifying the `kubelet`s' certificate: `--kubelet-insecure-tls`. Its README describes it in two short sentences worth reading slowly: “Do not verify the CA of serving certificates presented by Kubelets. For testing purposes only”. That is not said just to look good: it is a warning, and the lesson respects it. This flag is fine in a lab where the nodes are your own containers on your machine, and it is not fine in a cluster where someone else could get onto the network between `metrics-server` and a node, because without verifying the certificate there is no way to know who you are talking to.

The v0.9.0 manifest does not include the flag; it is added with a Kustomize *patch*. It is a **program**: `metrics-server/kustomization.yaml`.

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

The patch says: in the `metrics-server` Deployment in the `kube-system` namespace, add `--kubelet-insecure-tls` at the end of the first container's argument list. The `op: add` with `args/-` is the way to “append to the end” of a list in a JSON-type patch. It is applied with `-k`, like everything else:

```text
$ kubectl apply -k metrics-server | tail -3
service/metrics-server unchanged
deployment.apps/metrics-server configured
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io unchanged
```

Two objects `unchanged` (the Service and the APIService do not change) and one `configured`: the Deployment. Its template changed, so the Pod will be replaced, and this time the wait is on a condition:

```text
$ kubectl rollout status deployment/metrics-server -n kube-system --timeout=600s
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
deployment "metrics-server" successfully rolled out
(espera de 45 s: metrics-server mide en ventanas y necesita un par de ellas)
```

Then comes a pause that is not on a condition, and it is worth saying so: `metrics-server` measures in time windows and needs a couple of them before it can answer with data, so the lesson waits 45 wall-clock seconds. Instead of guessing, there is a way to check that it already answers: ask for the `APIService`, which must change to `True`.

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        98s
```

`AVAILABLE True`. Now `top` has somebody to ask:

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

The `CPU(cores)` column is in **millicores**: `1m` is one thousandth of a core, the same unit as the `requests` in Lesson 5. The documentation explains where it comes from: CPU is reported “as the average core usage”, calculated “as a rate of the cumulative CPU counter provided by the kernel” of Linux, over a time window that the API itself reports (the `window` field). It is not a snapshot of an instant, it is an average over a short window. And `CPU(%)` in `top nodes` is the percentage of the **node's** CPU, not of anybody's `request`; that is another calculation, and the one that matters to the autoscaler comes next. Look at the `revisor` Pods: a few tenths of a millicore or a few millicores of usage, against the `50m` they requested:

```text
$ kubectl describe pod -n revisor -l app=revisor | grep -E 'Requests|cpu:' | head -4
      cpu:     200m
    Requests:
      cpu:      50m
      cpu:     200m
```

(The first `cpu: 200m` is the `limit`; the `Requests` and its `cpu: 50m`, the floor. The third is the `limit` of the other container listed; the `head -4` filter cuts the output where it fits.) A Pod that uses `4m` of `50m` is at 8% of what it requested. That percentage, **usage against `requests`**, is the autoscaler's yardstick.

The `metrics-server` documentation also says what it is **not** for, and it is worth hearing before trusting it: its use cases are horizontal scaling by CPU and memory, and its README warns that it is not “an accurate source of resource usage metrics”. To look at consumption precisely, to graph it or to alert on it, other tools exist. To decide how many replicas, it is enough.

### 9.3 The autoscaler and its formula

#### 9.3.1 What it is and how often it looks

The `HorizontalPodAutoscaler` is a controller, one more of those you saw in Lesson 0 doing the same thing as always: comparing the desired state with the real one and pushing the second toward the first. The difference is what it understands by “desired state”: not a number of replicas, but a **consumption target**. “Horizontal” means that it changes the *number* of replicas, not the size of each one. The documentation says the loop runs every 15 seconds by default (`--horizontal-pod-autoscaler-sync-period`) ([Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)).

On each pass it does three things: it reads the metrics of the target's Pods, calculates how many replicas it would ask for and, if the result changes the current number, asks the Deployment for it. The part that can be calculated by hand is the second, and it is this:

```text
réplicas deseadas = ceil( réplicas actuales × (métrica actual ÷ métrica deseada) )
```

It is the formula the documentation gives: `desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]`. `ceil` is “round up”. With a CPU target of 50%: if there are 2 replicas and the average usage is 100% of what they requested, the calculation is `ceil(2 × 100 ÷ 50) = ceil(4) = 4`. If the average usage is 25%, `ceil(2 × 25 ÷ 50) = ceil(1) = 1`. The rounding up has a reason: it is better to have one Pod too many than one too few when the target is about to be exceeded.

And the “percentage”? With a target of type `Utilization`, the controller calculates usage “as a percentage of the equivalent resource request (`request`) of the containers in each Pod”, and takes the average over all the target Pods. That is why a Pod with no CPU `requests` is a Pod the autoscaler cannot measure: the documentation says that, if any container lacks the request, “the CPU utilization of the Pod is not defined and the autoscaler will not take any action for that metric”. Lesson 5 put `requests` on every container “so the scheduler knows where to place it”; today that decision serves a second purpose that was not visible then.

#### 9.3.2 The 10% tolerance

If the calculation were applied as is, the autoscaler would change the number of replicas over differences of one percentage point, and the cluster would be in perpetual adjustment. To avoid that, the controller skips any adjustment when the ratio `current metric ÷ desired metric` is “sufficiently close to 1.0”, and the documentation gives the measure: a tolerance of 0.1 by default, that is, 10% (since Kubernetes 1.37 each HPA can set its own tolerance in `behavior.scaleUp.tolerance` and `behavior.scaleDown.tolerance`; this lesson leaves the cluster's, 10%). With a target of 50%, there is an adjustment only if the measured usage falls outside 45% to 55%: the ratio has to be below 0.9 or above 1.1.

An example with numbers, to calculate it by hand before looking at the cluster. With 3 replicas and a target of 50%:

| Measured usage | Ratio | Outside 0.9 to 1.1? | `ceil(3 × ratio)` | What it does |
|---|---|---|---|---|
| 54% | 1.08 | no | — | nothing |
| 57% | 1.14 | yes | `ceil(3.42)` = 4 | scales up to 4 |
| 40% | 0.80 | yes | `ceil(2.4)` = 3 | does not change (3), but the recommendation is recorded |
| 20% | 0.40 | yes | `ceil(1.2)` = 2 | scales down to 2 (if the window allows it) |

When the cluster gives you numbers, you will check them against this table.

#### 9.3.3 The manifest

It is a **program**: `escalado.yaml`. It has two objects, the autoscaler and a disruption budget that is explained in 9.11.

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

It reads field by field:

- **`scaleTargetRef`**: whom it governs. A `Deployment` called `revisor` in the same namespace. The HPA does not touch Pods: it asks the Deployment to change its number of replicas, and the Deployment does the rest, as always.
- **`minReplicas: 2` and `maxReplicas: 6`**: the floor and the ceiling. The floor is 2 for two reasons: with a single replica, any replacement is an outage, and with two (one on each worker node) the update in 9.9 and the maintenance in 9.11 can be done without losing the service. The ceiling is 6 because of the security habit that closes this lesson: an autoscaler without a ceiling turns an avalanche of requests, or a bug in a loop, into a bill or an exhausted node.
- **`metrics`**: what it measures and against what. One resource, CPU, with an average utilization target of 50% *of the `requests`*. It is an intermediate target on purpose: if it were 90%, the autoscaler would react when the service is already almost saturated.
- **`behavior.scaleDown.stabilizationWindowSeconds: 60`**: the scale-down window, explained next.

The `behavior` field deserves a paragraph of its own. Without it, the HPA uses the documentation's default values: to **scale up**, a stabilization window of 0 seconds and a policy that allows adding up to 4 Pods or doubling the replicas every 15 seconds, whichever is larger; to **scale down**, a window of **300 seconds** (five minutes) and a policy that allows removing all the surplus replicas at once. The lesson uses 60 seconds instead of 300 so you can see the scale-down without waiting five minutes, and it says so because it is not a value to copy: in production, the long window protects against flapping (“up, down, up, down”) when the load is irregular.

What does the window do, exactly? The documentation explains it precisely: just before scaling, the controller records the recommendation of the moment, and then it “considers all recommendations within the configured window and picks the highest”. That is: to **scale down**, the HPA does not use what it sees now, but the **maximum** of what it recommended in the last 60 seconds. If 40 seconds ago it recommended 4 replicas and now it recommends 2, it stays at 4 until that recommendation of 4 leaves the window. It is a deliberate memory of the recent worst, and it is the reason why scaling down is slow and scaling up is not.

Finally, the `kubectl diff` in 9.5 will show that the HPA, when applied, comes with the default values of `scaleUp` and `scaleDown` written into the output (`selectPolicy: Max`, the 15-second policies): the server fills in what you did not write.

#### 9.3.4 Why the Deployment no longer carries `replicas`

In the Lesson 8 folder, the `revisor` Deployment said `replicas: 3`. In today's, that field is not there. It is not an oversight: it is the HPA documentation's explicit recommendation. When there is an autoscaler, the Deployment's `spec.replicas` field should be removed from the manifest, because otherwise, “each time a change is applied to that object, for example with `kubectl apply -f deployment.yaml`, Kubernetes will scale the current number of Pods to the value of `spec.replicas`”, which “can be problematic when an HPA is active, and cause *flapping*”. Two owners of the same number fight: your file says 3, the HPA has just asked for 5, and each `apply` undoes what the other did.

The documentation adds a warning that 9.5 will make visible: removing the field “can cause a one-time degradation of the number of Pods, because the default value of that key is 1”. That is, when you apply the Deployment for the first time **without** `replicas`, the cluster reads it as “go back to the default value” and proposes scaling down to a single replica. In 9.5 you will see that `replicas: 1` in the `kubectl diff`, and you will see what happens next.

### 9.4 Spreading the replicas

#### 9.4.1 The problem: nothing spreads for you

An autoscaler that scales up to four replicas does not say where it puts them; that is decided by the scheduler, which looks for the node that best fits by resources and other rules, and by default makes no effort to spread. Look at how the three replicas from the Lesson 8 folder ended up, with no spreading rule at all:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>
```

The `NODE` column says where each one is. In this run, two of the three replicas landed together on `curso-k8s-l9-worker2` and one on `curso-k8s-l9-worker`. It is not bad luck: in this run and in three earlier ones that were not kept, two of the three replicas landed together, sometimes on one node and sometimes on the other. The scheduler does not promise to spread. If the node with two replicas goes down, the service loses 67% of its capacity in one blow, and the autoscaler does not help: its job is to look at the CPU, not at the spreading.

#### 9.4.2 `topologySpreadConstraints`

Kubernetes has a component for this: **topology spread constraints**. “Topology” here means “in which part of the infrastructure each thing lives”: on which node, in which zone of a cloud, in which rack. The documentation defines the vocabulary ([Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/)): a node label, `topologyKey`, divides the nodes into **domains**, and the nodes that have the same value of that label form a single domain. The `kubernetes.io/hostname` label has a different value per node, so with it *each node is its own domain*. That is what is wanted here: spreading across nodes.

The `revisor`'s constraint is this. It is a fragment of the **program** `revisor-deployment.yaml`, inside `spec.template.spec`:

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

Each field, in order:

- **`topologyKey: kubernetes.io/hostname`**: each node is a domain, as was said.
- **`labelSelector`**: which Pods are counted in each domain. Those with `app: revisor`; the `prueba` replicas or the load Pods neither count nor get in the way.
- **`maxSkew: 1`**: the maximum **skew** allowed: the difference between the number of Pods in one domain and the number in the domain with the fewest. The documentation defines it like this: with `DoNotSchedule`, `maxSkew` “is the maximum permitted difference between the number of matching Pods in the target domain and the *global minimum*”. With `maxSkew: 1` and two worker nodes, 2 + 0 is not allowed (difference of 2), 1 + 1 is, 2 + 1 is, 3 + 1 is not.
- **`whenUnsatisfiable: DoNotSchedule`**: what to do if placing the Pod breaks the constraint. `DoNotSchedule` (the default) says “do not schedule it”: the Pod stays `Pending`. `ScheduleAnyway` says “schedule it anyway, but prefer the places that reduce the skew”: it is a preference, not a rule. This lesson uses the hard rule, because the soft one lets through exactly what you want to avoid: the constraint is there so that the spreading *is real*, and a preference does not guarantee it.
- **`nodeTaintsPolicy: Honor`**: how to treat the nodes' *taints* when calculating the skew. It is explained in 9.4.3 and checked in 9.5.4, because it is the field that seems superfluous and is not.
- **`matchLabelKeys: [pod-template-hash]`**: restricts the count to the replicas of the **same version**. The Deployment puts a label on each Pod, `pod-template-hash`, with a different value for each version of the template. The documentation says this label, which “is added automatically by the Deployment controller”, is used “to distinguish between different revisions of the same Deployment”. During an update old and new replicas coexist; without this field, the old ones would count toward the spreading of the new ones and get in the way; with it, each version is spread on its own.

#### 9.4.3 Why the control-plane node requires `Honor`

The cluster has three nodes and only two receive replicas. The control-plane node carries a *taint* (`node-role.kubernetes.io/control-plane:NoSchedule`) that prevents scheduling user Pods there. But does it count as a domain, for the calculation of the “global minimum”? It depends on `nodeTaintsPolicy`. The documentation defines the two options: `Honor` includes “nodes without taints, along with tainted nodes for which the incoming Pod has a toleration”; `Ignore` ignores the taints and includes all nodes; and if the field is empty, the behavior is equivalent to `Ignore`.

That means that, **without** `Honor`, the control-plane node enters the count as a domain with zero Pods, and the “global minimum” is 0, because that node cannot receive a replica. With that fixed zero, `maxSkew: 1` allows at most 1 Pod per domain: the third replica would have nowhere to go. It is the kind of rule that works with two replicas and breaks with the third, and that is precisely why it is an error you find in production on a Monday at 9:00. 9.5.4 triggers it so you can see it.

#### 9.4.4 What the constraint does not do

This component's documentation includes a warning in its limitations section: “there's no guarantee that the constraints remain satisfied when Pods are removed. For example, scaling down a Deployment may result in imbalanced Pods”, and it recommends tools such as the *Descheduler* to rebalance. The rule is applied **when scheduling** a new Pod, not before or after. 9.11 will show it with a maintenance that leaves the replicas together, and will also show how it is remedied without installing anything.

### 9.5 Applying the changes

#### 9.5.1 What changes, before applying

With the Lesson 9 folder ready, the first step is not to apply but to ask what is going to change. `kubectl diff -k .` sends the server the result of the `-k` and shows the difference against what is there. The command is filtered (`grep -E '^[+-] '`) to keep the lines that change and drop the metadata noise (`creationTimestamp`, `uid`, `resourceVersion`):

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

The code `1` at the end is not an error: `kubectl diff` exits with 1 when there **are** differences, and with 0 when there are none, so it can be used in a script. It reads in three blocks:

1. **`-  replicas: 3` / `+  replicas: 1`.** What was announced in 9.3.4. The file no longer says `replicas`, and the server, which brings its default value, proposes **1**. If you apply this without thinking, the `revisor` goes from three replicas to one, even if only for an instant, before the autoscaler corrects it. Here it is not serious; with 40 people connected at 9:00, it would be. It is the one-time cost of handing over control of the number of replicas, and it is worth knowing before paying it.
2. **`maxSurge: 25%` → `1` and `maxUnavailable: 25%` → `0`.** The default values of the update strategy are made explicit. They are explained in 9.9.
3. **`lifecycle` / `preStop`, `terminationGracePeriodSeconds: 10` → `15` and `topologySpreadConstraints`.** The pause before shutting down, the longer grace period that pause needs and the spreading from 9.4. And below, the new objects: the HPA (with the default values written out) and the PodDisruptionBudget.

#### 9.5.2 Applying and observing

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

Four lines: `deployment.apps/revisor configured`, the PDB and the HPA `created`, and `prueba unchanged` (what did not change is not touched). The `rollout status` shows the replacement of the replicas, because the template changed (the `preStop`, the grace period and the spreading) and so there is an orderly replacement, one at a time, as in Lesson 2. Then there is a 30-second pause in plain sight: the HPA needs its first reading of metrics before showing a number.

```text
$ kubectl get hpa,pdb -n revisor
NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          32s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     32s
```

Read the HPA's `TARGETS` column: `cpu: 2%/50%` is “current usage / target”. The usage is the average, over the Pods' `requests`, that 9.2 explained. `MINPODS 2` and `MAXPODS 6` are the floor and the ceiling, and `REPLICAS` is the current number. In the PDB, `ALLOWED DISRUPTIONS` says how many Pods can be lost voluntarily right now; it is explained in 9.11.

A reading detail: the first time the HPA is applied, if you look too soon, `TARGETS` says `cpu: <unknown>/50%`. It is not a failure: the controller does not yet have a measurement of the new Pods. The HPA's events, which are read in 9.6, keep the trace of those first seconds.

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-5xvt5   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-857qf   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.replicas}{"\n"}'
2
```

Two replicas, **one on each worker node**. The spreading was fulfilled, and the number of replicas was set by the HPA: `.spec.replicas` is 2, the floor. The most likely chain, and the one the event `Current number of replicas below Spec.MinReplicas` in 9.6 suggests, was: the `apply` left the Deployment at 1 (the default value), the HPA saw that 1 was below the floor of 2 and raised it, and the replacement spread the two replicas because of the constraint.

#### 9.5.3 The HPA's log tells what it did

The HPA leaves its decisions in the events. They are read with `describe`, which will be shown in full in 9.6 after the load, and the first line is the trace of the above: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. “The current number of replicas is below the minimum”: the HPA was not reacting to the load, but applying the floor.

#### 9.5.4 The error: spreading without `nodeTaintsPolicy: Honor`

Now the error promised in 9.4.3. It is triggered by removing only `nodeTaintsPolicy` from the live Deployment, with a patch, and asking for a third replica by hand:

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

With two replicas everything looks normal. That is what makes this error treacherous: the defect is not visible until the third arrives.

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

The third replica stays `Pending`, with no node assigned. We follow the order from Lesson 5: the `describe` of the pending Pod (the name changes in your run), events section.

```text
$ kubectl describe pod revisor-574b5b6c4c-4nwx5 -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  6s    default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match pod topology spread constraints. preemption: 0/3 nodes are available: 1 Preemption is not helpful for scheduling, 2 No preemption victims found for incoming pod.
```

Read it: `0/3 nodes are available` says that of the three nodes, none will do. And it gives the reason for each: one node has a taint the Pod does not tolerate (*untolerated taint*; it is the control-plane one), and the other two “did not match the pod topology spread constraints”. It is exactly what was announced: the control-plane node counts as a domain with zero Pods, the global minimum is 0, and placing the third replica on either of the other two would give a skew of 2.

The fix is to apply the file again, which carries `Honor`:

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

With `Honor`, the control-plane node leaves the count: three replicas in two domains, 2 + 1, skew of 1. It fits. And since `apply -k` does not carry `replicas`, the number lives in the Deployment until the HPA corrects it: after the 60-second scale-down window (in plain sight, a 75-second wait), the HPA brings the count back to 2, which is what the load calls for.

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

### 9.6 With load, the autoscaler scales up

#### 9.6.1 A load that can be switched off

To see the autoscaler work you need load, and the load has to be something you can switch off whenever you want. It is a **program**: `carga.yaml`.

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

It is a `Job`, the Lesson 8 object for tasks that finish, with four Pods in parallel (`parallelism: 4`) that endlessly repeat a request to `http://revisor/salud`. There is no pause between one and the next: each Pod asks, receives, and asks again. It reads by decisions:

- **`activeDeadlineSeconds: 600`**: whatever happens, the Job stops after 10 minutes: it has to survive the image download plus the 200 seconds of observation. A load generator with no brake is a breakdown waiting to happen; this one ends even if you forget to delete it.
- **`backoffLimit: 0`**: if a Pod fails, it is not retried. It is a lab load, not a task that matters.
- **`acceso-revisor: permitido`**: the label that Lesson 7's closed network requires in order to reach the `revisor`. Without it, the load Pods would reach nowhere, and the HPA would see no load. It is the same permission as the `depurar` Pod.
- **`limits: cpu: 200m`**: each load Pod can consume up to a fifth of a core. That puts a **ceiling on the load that can be generated**: four 200m Pods are 800m in total, and how much of that turns into `revisor` CPU depends on how many requests per second it manages to answer. It is not a performance test; it is a lever with a stop.
- **The `curl` image, pinned by its digest**, as in Lesson 3. The first time a node uses it, it downloads it from the internet; that is why the script waits (in plain sight) for the load Pods to be ready before starting to watch the clock.

#### 9.6.2 Applying, waiting, looking

```text
$ kubectl apply -f carga.yaml
job.batch/carga created
(espera visible: hasta 600 s a que los Pods de carga arranquen; la primera vez descargan la imagen de curl)
```

Then comes a wait with `kubectl wait`, for the reason above: until the load Pods are `Ready`, there is no load, and looking at the HPA earlier would be measuring silence.

```text
$ kubectl wait --for=condition=Ready pod -l app=carga -n revisor --timeout=600s
pod/carga-29s8s condition met
pod/carga-bz6zl condition met
pod/carga-nv5tb condition met
pod/carga-rnhz5 condition met
```

Now the clock runs. The script prints one HPA line every 20 seconds for 200 seconds. In your terminal, the equivalent is `kubectl get hpa revisor -n revisor --watch` (which prints a new line every time something changes), or a `get` and `sleep 20` loop like the script's. The wait is part of the lesson: the autoscaler is not instantaneous, and seeing how long it takes is what you learn.

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

Each line reads the same way: the time since the load started, the name, the target, the `TARGETS` column (`current usage / target`), the floor, the ceiling, the replicas and the HPA's age. They have to be read with the formula from 9.3 in hand.

The lines, with the formula from 9.3 applied to each:

| Time | Measured usage | Replicas | Ratio (usage ÷ 50) | Calculation | What it does |
|---|---|---|---|---|---|
| +20 s | 27% | 2 | 0.54 | — | the load is barely arriving |
| +40 s | 46% | 2 | 0.92 | within 0.9 to 1.1 | nothing: the tolerance holds it back |
| +60 s | 72% | 2 | 1.44 | `ceil(2 × 1.44)` = `ceil(2.88)` = 3 | decides to scale up to 3 |
| +80 s | 58% | 3 | 1.16 | `ceil(3 × 1.16)` = `ceil(3.48)` = 4 | decides to scale up to 4 |
| +100 s | 44% | 4 | 0.88 | `ceil(4 × 0.88)` = `ceil(3.52)` = 4 | stays at 4 |
| +120 s | 46% | 4 | 0.92 | within the tolerance | nothing |
| +140 to +200 s | 38% | 4 | 0.76 | `ceil(4 × 0.76)` = `ceil(3.04)` = 4 | stays at 4 |

There are three things to see there. **First**: the +40 second line, with 46%, does nothing even though the load is already on top of it. It is not slowness, it is the tolerance: 46% is 8% below the target, within the 10% the controller forgives. **Second**: at +60 s the usage is 72% with 2 replicas and the autoscaler decides to scale up to 3; the +80 s line already shows 3, because 20 seconds pass between one line and the next and the decision was taken in the interval. The change from 3 to 4 is separated from the first by about 30 seconds (the events below say `2m37s` ago and `2m7s` ago), probably because the new Pods have to be born and start working before their consumption counts. **Third**, and the most instructive: from +140 to +200 seconds the usage stays at 38% with 4 replicas, a ratio of 0.76 that is **outside** the tolerance on the low side, and even so the autoscaler does not scale down. The calculation explains why: `ceil(4 × 0.76)` is `ceil(3.04)`, which is 4. The rounding up keeps the fourth replica by four hundredths. The system stabilized on its own: each new replica spread the load, the average dropped from 72 to 38%, and with that average four replicas is the number the formula wants. The ceiling of 6 was not touched.

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

`kubectl top pods` shows each replica's real consumption at the instant of the query: 18, 19, 20 and 20 millicores. Against the `50m` each one requested, that is 36 to 40%. And the HPA, with its own query, says it on one line: `cpu=38 % (19m)` is “average utilization of 38%, which is equivalent to 19 millicores per Pod”. The calculation can be done by hand: (18 + 19 + 20 + 20) ÷ 4 = 19.25 millicores, which rounds to `19m`, and 19 ÷ 50 is 0.38. The `TARGETS` column is no mystery: it is this division. `réplicas=4 deseadas=4` says what has already been seen: what there is is what the formula wants.

The HPA's events are its log, and they tell the same thing in other words:

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

Read them from the bottom up, from the oldest to the newest. `SuccessfulRescale … New size: 2; reason: Current number of replicas below Spec.MinReplicas` is the first adjustment, the one from 9.5: the floor. The two `Warning`s that follow (`FailedGetResourceMetric`, `FailedComputeMetricsReplicas`) are the autoscaler saying it does not yet have metrics for the new Pods: `unable to get metrics for resource cpu: no metrics returned from resource metrics API`. They are normal in the first seconds of a Pod's life, while `metrics-server` does its first read; the `(x3 over 5m39s)` says they repeated three times. The next one, `New size: 2; reason: All metrics below target`, is not from this load: it is the HPA bringing back to 2 the third replica that 9.5.4 asked for by hand. And the last two, 30 seconds apart (`2m37s` ago and `2m7s` ago), are the decisions of this section: `New size: 3` and `New size: 4`, both with the reason `cpu resource utilization (percentage of request) above target`: consumption, measured as a percentage of the request, above the target.

### 9.7 Without load, it scales down, after the window

The Job is deleted, and the HPA is watched every 20 seconds for 260 seconds. What you are going to see is the scale-down window from 9.3.3:

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

The clock counts like this. The Job is deleted at second 0, but the +20 and +40 readings are still high (36% and 39%): the most likely reason is that the load Pods take a few seconds to finish, and `metrics-server` averages the consumption over a short window, not an instant. At +60 s the reading is already 3%, and it stays there. With 4 replicas and 3% usage, the calculation is `ceil(4 × 0.06)` = `ceil(0.24)` = 1, but the floor is 2, so what the autoscaler *wants* is 2. And yet the replicas column says 4 at +60, +80 and +100, and does not change to 2 until the +120 line. That difference is the 60-second scale-down window from 9.3.3: during that minute, the HPA does not use today's recommendation but the highest of the last 60 seconds, and it made the last recommendation of 4 replicas with the high readings from the start.

The events give the times more precisely than the table. To read them you have to subtract from the moment the `describe` was run (right at the end of the table, about 262 seconds after deleting the Job): `New size: 3` happened `2m54s` ago, that is, around +88 s, and `New size: 2` `2m39s` ago, around +103 s. That is, the scale-down happened in two steps, from 4 to 3 and 15 seconds later from 3 to 2, some 50 or 60 seconds after the last high reading. It is what you expect from a window: the recommendations from the high part leave it one at a time. (The table never shows the step at 3 because the HPA's `REPLICAS` column is updated with a delay relative to the Deployment: it is `status.currentReplicas`, which the HPA writes on its own pass, every 15 s; that is why the +100 line still says 4 even though the event for scaling down to 3 is at +88. What number the HPA sees on each pass was not measured.)

Two more `describe` objects complete the reading. The conditions table:

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

`ScalingLimited True TooFewReplicas: the desired replica count is less than the minimum replica count` is the HPA saying, in so many words, what was calculated above: what the formula asks for (1) is **less** than the floor (2), and that is why it stays at 2. `ScalingActive True ValidMetricFound` says that it can calculate, that is, that `metrics-server` is still answering. It is the table you look at when an HPA “does nothing” and you need to know whether it is because it cannot or because it does not want to. And the real consumption of the two remaining replicas:

```text
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-5b6k9   1m           6Mi             
revisor-767bdf965b-vcznx   1m           5Mi             
```

One millicore each: the load really went away. The complete events, and the replicas that remain:

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

The event `New size: 2; reason: All metrics below target` is the scale-down. And the two remaining replicas are one on each worker node: the spreading constraint from 9.4 is still satisfied after removing two Pods.

### 9.8 Who is in charge of the replicas

The Deployment has `replicas` empty in the file, but it still has a number. What happens if someone else changes it by hand? It is tested with `kubectl scale`, which writes the number of replicas into the Deployment, the same field the HPA writes:

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

Forty seconds later, the Deployment has 2 replicas again, and the HPA's last event says so: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. The HPA did not argue or ask: on its next pass it saw that the Deployment had fewer replicas than the floor, and put it back. That answers a practical question: **with an active HPA, `kubectl scale` is of little use**. If you scale below the floor, the HPA corrects you; if you scale above what the load calls for, it corrects you downward as soon as the window passes (9.5.4 showed it with the third replica: at 75 seconds the Deployment was already back at 2). To change the number of replicas with a live HPA you have to change the HPA: its `minReplicas` or its `maxReplicas`. Whoever wants two owners for the same number has the problem from 9.3.4.

### 9.9 Updating and measuring the outage

#### 9.9.1 How a Deployment updates

When you change a Deployment's Pod template (the image, a variable, a `preStop`), not all the replicas are shut down in order to turn others on. The Deployment creates a new `ReplicaSet` for the new template and moves replicas from the old one to the new one, a few at a time. The documentation describes it like this: the new state is declared by updating the template, “a new ReplicaSet is created, and the Deployment gradually scales it up while scaling down the old one, ensuring that Pods are replaced at a controlled rate” ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). Two numbers govern that pace, and they have been in the Deployment since 9.5:

- **`maxSurge`**: how many **extra** Pods can be created above the desired number during the update. The documentation: “the maximum number of Pods that can be created over the desired number of Pods”, as a number or percentage; the default is 25%.
- **`maxUnavailable`**: how many Pods can be lost, that is, be **unavailable**, during the update. Also 25% by default; the documentation clarifies that it cannot be 0 if `maxSurge` is 0 (otherwise the update could not progress).

The `revisor` sets them at `maxSurge: 1` and `maxUnavailable: 0`. It reads as a safety rule: “do not remove a replica that is answering until there is a new one ready to replace it”. With two replicas, the Deployment creates **one** new replica (the third, because of `maxSurge`), waits for it to be ready, and only then shuts down an old one; then it repeats with the other. At no moment are there fewer than two replicas available. It is the part of the update that Kubernetes knows how to do on its own, and that is why `rollout status` prints `1 out of 2 new replicas have been updated`: it counts the new ones.

But “available” is a word from the control plane. What the requests feel is something else, and the difference is called a *race*.

#### 9.9.2 The shutdown race

When the Deployment decides to remove an old replica, that replica goes through the steps that the Pod lifecycle documentation describes as the termination flow ([Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)):

1. The Pod is marked as *terminating* in the API, with a deadline (by default, 30 seconds; the `revisor`'s is 15).
2. On the node, the `kubelet` sees the mark and starts the local shutdown: if the container declares a `preStop` hook, it runs that first. Then the container runtime sends the `TERM` signal to process 1 of each container, and the process has whatever is left of the deadline to finish. If it is still alive when the deadline expires, it receives `KILL`.
3. **“At the same time as the kubelet starts the graceful shutdown of the Pod”**, the control plane evaluates whether it must remove it from the `EndpointSlice`s of the Services that use it. The documentation adds a useful detail: an endpoint representing a Pod that is shutting down is not removed immediately; it is marked as *terminating* and with `ready: false`, and the load balancers stop using it for normal traffic.

Step 2 and step 3 **do not wait for each other**. That is the race. It is Phil Pearl's observation from the scene, measured in another context: the shutdown notice reaches the process at the same moment the news “take it off the list” starts to travel, and the news has to travel: from the control plane to the `EndpointSlice`s, from there to `kube-proxy` on each node, and from there to each node's network rules. While it travels, some nodes still send requests to the old Pod. If the process has already closed its port on receiving `TERM`, those requests run into a closed door: `Connection refused`, or into silence.

The `revisor` does its part well: on receiving `TERM` it writes `recibí terminated, apagando`, finishes the requests it has in progress and exits with `apagado limpio`, with an internal deadline of 5 seconds (Lesson 5 measured it). But “finishes the ones in progress” does not include “keeps accepting new ones”. The `revisor`'s shutdown uses `Server.Shutdown`, from Go's standard library, and that function's documentation says how it works: “first closing all open listeners, then closing all idle connections, and then waiting” for active connections to finish ([Go, `net/http`](https://pkg.go.dev/net/http#Server.Shutdown)). The entry port is closed **first**. What is missing is not a defect of the `revisor`; it is time for the news to arrive.

Since Pearl wrote (2019), Kubernetes added the `serving` and `terminating` conditions to `EndpointSlice`s, and allowed `kube-proxy` to use endpoints that are terminating when none is left ready. That avoids losing traffic when *all* the endpoints are shutting down, but it does not change the fact that the shutdown notice and the removal of endpoints travel by different paths: the race still exists and is the one this lesson measures.

#### 9.9.3 The pause that closes the race: `preStop`

A `preStop` hook runs **before** the `TERM` signal. If all it does is wait a few seconds, the process keeps answering normally during that wait, while the news “take it off the list” finishes traveling. When `TERM` finally arrives, nobody sends it new traffic anymore. The `revisor` Pod has no shell (the image is minimal, from Lesson 5), so the hook cannot be an `sh -c "sleep 5"`; Kubernetes has a native wait action:

```yaml
        lifecycle:
          preStop:
            sleep:
              seconds: 5
```

That is all that was added to the Deployment. Five seconds is a choice, not a law: they have to be enough for the news to reach all the nodes of the cluster, and how long that takes depends on the size and load of the cluster. Pearl, in his case, recommended waiting longer than the time the load balancer takes to reprogram itself. The pause also counts against the shutdown deadline: the documentation says the `preStop` time is part of `terminationGracePeriodSeconds`, and that if more is needed, the deadline must be raised. That is why the Deployment went from 10 to **15 seconds**: 5 of pause, up to 5 for the `revisor`'s shutdown, and 5 of margin.

All of this is theory until it is measured. Measuring requires a tool, and the tool is a program.

#### 9.9.4 The poller

The measurement has to meet three requirements: **count** every request, not a sample; **run during** the change, not before or after; and **distinguish** which version answered and how each failure failed. It is a **program**: `sondeo.sh`.

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

It reads in parts.

- **Where it runs.** The request loop runs **inside** the `depurar` Pod from Lesson 3, the `curl` one, and is sent through the standard input of `kubectl exec -i`. That way the requests are born inside the cluster and go through the Service, like those of any internal client (for example, Lesson 8's scheduled task). **Scope:** this measurement covers the path of a client inside the cluster, that is, the Service and `kube-proxy`. It does not go through the Envoy Gateway, where outside users would come in: that component learns about endpoint changes on its own and may take more or less time than `kube-proxy`, and that path was not measured here. Pearl observed the problem with an Ingress, not a Service, and says that with Services the window is usually short. The `<<'DENTRO'` with single quotes prevents your shell from interpreting anything in that block: it is sent as is.
- **What each thread does.** A loop that, while time has not run out, requests `http://revisor/salud` with `curl -s -m 2`: silent (`-s`) and with a maximum of **2 seconds** per request (`-m 2`). `-w ' %{http_code}'` appends the HTTP code at the end, and the `echo " rc=$?"` appends `curl`'s own exit status. That second figure matters a lot, because it distinguishes **how** a request failed, and each mode tells a different story (below).
- **One line per request.** `echo "$(( $(date +%s) - inicio )) $(echo $r)"` puts on a single line the second at which it happened, the response body, the code and `curl`'s exit status. One line per request keeps the lines of the four threads from mixing: each `echo` is a single write. (The unquoted `$(echo $r)` flattens the line breaks in the body; the `revisor`'s response carries one at the end, and without that trick the line would split in two.)
- **The count.** The final `awk` groups by (code, `curl` exit status, version that answered) and prints how many there were of each, and the seconds of the first 40 failures. “Failure” is any code other than `200`, including `000`, which is what `curl` prints when it did not manage to receive an HTTP response.
- **The two failure modes you will see.** `curl` exits with **7** when it could not connect (`Failed to connect`): it reached an address where nobody is listening, or the connection was refused. It exits with **28** when time ran out (`-m 2`) with no response. Something concrete can be said about the first: somebody answered “nobody is here”. About the second, only that nobody answered in time; the cause may lie in the destination, in the network or in the client itself.

A word of honesty about the instrument: the `depurar` Pod has a CPU limit of `100m`, and four `curl` loops with no pause use it up completely. A client at its CPU ceiling can delay its own requests and produce timeouts that are not the server's fault. What is measured is the *whole* of client, network and server. That is why the baseline poll in 9.9.5 goes before any change: it measures how much noise the poller produces by itself.

#### 9.9.5 First, the noise; then, the update with `preStop`

Before changing anything, the poller is measured against a quiet cluster, to know how much noise it produces by itself. It is 15 seconds, with four threads and no pause. Then comes the first update, the manifest as it is, with the `preStop` in place. The script launches the poller in the background (`&`), waits 3 seconds for it to be running, changes the image from `1.6.0` to `1.6.1` and waits for the rollout to finish:

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

`kubectl set image` changes the image of the `revisor` container inside the `revisor` Deployment, without touching any file; it is the short path for this measurement (the security habit, below, says why it is not the path of a real project). The `rollout status` keeps count: “1 out of 2 new replicas have been updated”: of the two new replicas, one has already been updated; and then “1 old replicas are pending termination”: one old one has not finished yet. It is the `maxSurge: 1` mechanics from 9.9.1 seen from the outside: first a new replica, then an old one is removed, then another new one.

The count reads like this. The **baseline poll** made 172 requests in 15 seconds, 172 with code `200` and all from version `1.6.0`. No failures: so the instrument, at that moment, produces no visible noise. But 172 requests are too few to estimate the noise: a noise of 0.24% would expect fewer than one failure in 172 requests, so this round does not distinguish “zero” from “a few per thousand”. **Update A** made 472 requests in 45 seconds: 56 were answered by version `1.6.0` (those before the replacement and those that landed on old replicas while it progressed) and 416 by `1.6.1`, and none failed. At no moment was there a line with another code. If this were the only round, the headline would be “zero failures out of 472”. But one round is not enough, and the rest of the section exists to say why.

#### 9.9.6 The same experiment, without the pause

To know what `preStop` prevents you have to remove it and measure the same thing. It is removed with a JSON-type patch that deletes the `lifecycle` field of the first container:

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/lifecycle"}]'
deployment.apps/revisor patched
```

`op: remove` with a `path` is “delete this field”. The patch changes the Pod template, so it triggers its own replacement; the script waits for it to finish with `rollout status` and checks that the hook is gone. The check is this:

```text
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].lifecycle}{"|"}{.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
|15
```

The output is `|15`: before the bar, the content of `lifecycle`, which is **empty**; after it, the `terminationGracePeriodSeconds`, 15. (The `|` is written by the command itself between the two fields, so that the empty value can be seen.) With no hook, the Pod receives `TERM` at the very instant its shutdown begins.

With that template the update is repeated three times, going back and forth between the two versions, so that each round changes the image and there is a real replacement:

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

There are new lines, and each tells something different:

- `código 000  curl rc=7`: the HTTP code `000` is what `curl` prints when it **did not receive an HTTP response**, and `rc=7` is its own exit status: “Failed to connect to host”. Something answered “nobody is here” to the connection. It is the signature you would expect from the race in 9.9.2: a request arrived, through the Service, at a replica that had already closed its port.
- `código 000  curl rc=28`: `rc=28` is “Operation timeout”: the 2 seconds of `-m 2` passed without a response. Nobody said “no”; nobody said anything. It happens when the packet arrives at an address that no longer exists (the Pod is gone and the network still points to it) or when someone takes too long to answer. The timeout, then, has several possible causes, and one of them is the same race.
- The line **“segundos (desde el inicio) de las primeras fallas”** (seconds, from the start, of the first failures) gives the second, counted from when the poller started, at which each failed request *ended*; a `curl 28` failure was sent about 2 seconds earlier. In the three rounds without a pause, the failures fall between `+5` and `+10` seconds, except for one or two later ones. It is the moment when the old replicas shut down: the `set image` was sent 3 seconds after launching the poller.

The sum of the three rounds without `preStop`: 463 + 521 + 585 = 1,569 requests, of which 9 + 9 + 11 = 29 failed. Six were `curl 7` (2, 1 and 3) and 23 were `curl 28` (7, 8 and 8).

#### 9.9.7 With the pause again, three more rounds

The folder is applied again, which carries the `preStop`, and the update is repeated three more times:

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

#### 9.9.8 What the seven rounds say, and what they do not

Putting together all the rounds of the run:

| Variant | Rounds | Requests | Failed | `curl 7` | `curl 28` |
|---|---|---|---|---|---|
| Baseline poll, touching nothing | 1 | 172 | 0 | 0 | 0 |
| **With** `preStop` (A and C1 to C3) | 4 | 2,049 | 5 | 0 | 5 |
| **Without** `preStop` (B1 to B3) | 3 | 1,569 | 29 | 6 | 23 |

With `preStop`, 5 failures out of 2,049 requests (0.24%; 95% interval, Wilson method: 0.10 to 0.57%). Without it, 29 out of 1,569 (1.85%; 1.29 to 2.64%). The intervals do not overlap, but they assume independent requests, and here they are not (four threads sharing a client, and the four failures of round C1 are from the same instant); read them as an indication of size, not as a guarantee. What those figures allow us to say, carefully:

1. **The refused connection appeared only without the pause.** The six refused connections (`curl 7`) occurred in the rounds without `preStop`, and none in the four rounds with it. It is the effect that 9.9.2 predicts: without a pause, a replica closes its port while someone is still sending it requests. With the pause there remained five timeouts (`curl 28`) that this measurement does not let us attribute either to noise or to a residual race: that code has both possible causes.
2. **The failures cluster where expected.** In the rounds without a pause they fall in a window of some five or six seconds, the one that follows the `set image`. In the rounds with a pause, there are no failures in that window: the four of round C1 happened in the same second, `+2`, that is, when the poller was just starting (the `set image` is sent 3 seconds after launching it), and the only one of round C3 fell at `+25`, with the update already under way; we did not record when each Pod shut down, so we cannot relate it to any moment. That the four failures of C1 are simultaneous points to a slow start of the client (four threads starting at once inside a Pod with a `100m` CPU limit on a shared, loaded machine), but the measurement does not prove it: it is a hypothesis, not a conclusion.
3. **Zero is not what was measured.** Round A, the first, gave 0 out of 472; the other three rounds with a pause gave 4, 0 and 1. A lesson that said “with `preStop` no request is lost” would have picked round A and would have lied. What the measurement does support: the pause reduced the failures in the update window to a small number that is not zero either, and the rounds with a pause together gave 5 failures in 2,049 requests. We do not know how much of that is client noise: the baseline poll, of 172 requests without a failure, is too short to estimate it.
4. **This is not a statistical test.** They are seven rounds of 45 seconds, on a shared machine under heavy load, with a client that shares cores with the cluster it measures. The rounds were not alternated (first A, then the three without a pause and then the three with a pause), so the variant and the moment go together, and the machine's load changed during the work; to separate both effects you would have to alternate with and without the pause. The figures are good for comparing variants within this run; not for promising a percentage on your cluster. What is transferable is the method: count every request, distinguish how they fail, repeat, and not believe a single round.

The 5-second pause, then, closes the part of the race that a pause can close. It is not a guarantee: the hooks documentation itself says that their delivery is “at least once” and makes no further promise. And there is a source of failures that no pause touches: the loss of a node, which comes in 9.12.

### 9.10 The history and the rollback

#### 9.10.1 One ReplicaSet per version

Each time the Deployment's template changes, the Deployment creates a new `ReplicaSet`, and the old one stays there, with zero replicas, instead of being deleted. Each of those ReplicaSets keeps the template of a version: its image, its probes, its `preStop`. That is what makes going back possible, and the documentation says so bluntly: “the configuration of each Deployment revision is stored in its ReplicaSets; therefore, once an old ReplicaSet is deleted, you lose the ability to roll back to that revision”. How many are kept is decided by `.spec.revisionHistoryLimit`, which is 10 by default.

You can put a comment on each revision with an annotation, `kubernetes.io/change-cause`, which `rollout history` shows in a column. The documentation says it can be set with `kubectl annotate`, by editing the manifest or with tools that do it on their own, and that the `--record` flag, which used to fill it, is deprecated and will be removed. It is applied to the current revision:

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

The `CHANGE-CAUSE` column only has text on the current revision, because the annotation is copied to a revision when that revision is created, and the others already existed. The revision numbers need not be consecutive: here they are 1, 3, 8, 9, 12 and 13. Each time the template is identical again to that of a ReplicaSet that already existed, the Deployment **reuses** that ReplicaSet and gives it the newest revision number, so the intermediate revisions that became “the same” disappear from the list. The ReplicaSets confirm the count:

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

Six ReplicaSets, one for each distinct template that went through the Deployment in this run: with `preStop` and without it, with one version or another, with `nodeTaintsPolicy` and without it. Only one has replicas. The other five are the history.

#### 9.10.2 `rollout undo`

`rollout undo` takes the Deployment to the previous revision. It executes nothing special: it writes into the Deployment the template of the previous ReplicaSet, and the Deployment does the same gradual replacement as always, but in reverse.

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back
```

The warning (`Warning: resource deployments/revisor was previously managed with 'kubectl apply'…`) deserves to be read in full. It says that the rollback **does not update** the `last-applied-configuration` annotation, the one that stores the last state you applied with `kubectl apply`, and that this “may cause unexpected behavior on future `kubectl apply` operations”. Translated: your file says one thing, the cluster went back to another, and the next `apply -k .` will make its own comparison and may undo your rollback. `rollout undo` is a tool for putting out a fire; the real fix is to change the file and apply it. The `kubectl` documentation suggests it in the same words at the end of the warning: “consider using `kubectl apply` with your previous configuration file instead”.

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

#### 9.10.3 When it really finishes

`rollout status` said `successfully rolled out`. Is nothing left of the version you removed? Look with the column that is needed, the one the script carries in all its Pod listings:

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-5cc67d8975-qbzsl   curso-docker-revisor:1.6.1   curso-k8s-l9-worker2   2026-10-21T23:32:40Z
revisor-5cc67d8975-ttszb   curso-docker-revisor:1.6.1   curso-k8s-l9-worker    2026-10-21T23:32:37Z
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
```

Look at the `BORRANDOSE` column (“being deleted”): it is the Pod's `deletionTimestamp` field, the time (in UTC) at which the cluster ordered it to terminate. The `1.6.1` Pods have it: they are terminating, they are still in their `preStop` pause (the 15-second deadline has not yet expired), and **they are still answering**. The `1.6.0` Pods do not have it: they are the live ones now. `rollout status` finished because the Deployment already meets what was asked of it (the desired replicas of the good version are ready and the bad ones are already marked to terminate), not because the last bad Pod has finished dying. The requests show it:

```text
$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}
```

Four of the six responses say `1.6.1`: **the version you have just removed**. Only two say `1.6.0`, the one that remained. If you had concluded at that moment that the `undo` did not work, you would have been wrong. It is the same race as in 9.9.2, seen from the rollback: the removal of the endpoints takes a little while to reach everyone. Twelve seconds later, with the pause expired:

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

There is no row left with `BORRANDOSE`, and the six responses say `1.6.0`. A `rollout undo` that seems not to have worked because a request was answered by the old version is usually this: the conclusion was drawn too soon. The rule: before deciding that the rollback failed, look at `deletionTimestamp` and wait for the deadline to expire.

To see what a revision kept, `rollout history` accepts `--revision=N`, and shows the complete template of that version, image included. The script asks for the first:

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

It is the template the Deployment was born with in the Lesson 8 folder: image `1.6.0`, no `preStop`. (The output is cut to 14 lines with `head` so it fits; the rest are the `Requests`, the probes and the volumes.) To go back to it you would say `kubectl rollout undo deployment/revisor --to-revision=1`, the form the documentation gives.

And to close the circle with the discipline of the security habit, the script applies the folder again, so that the cluster and the files end up the same:

```text
$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
```

`unchanged`: the template the `undo` left is identical to the one in the file, and `apply` has nothing to do.

#### 9.10.4 The error: an image that does not exist

One of the most common reasons for a rollback is an update that went wrong, and not always because of a defect in the program but because of a typing slip: the image tag is misspelled, or points to a version nobody published. It is triggered on purpose, with a separate script that builds its own minimal cluster: **`fig09_02.imagen-rota.sh`**, a **program** that fails on purpose. It creates `curso-k8s-l9` with only what is needed (the `revisor` and the test service, without MetalLB or Envoy Gateway, which play no part), sets two replicas, launches the poller from 9.9.4 and changes the image to `curso-docker-revisor:9.9.9`, a tag that does not exist. Its output is `fig09_02.imagen-rota.salida.txt`. It is run like this, from the lesson folder:

```bash
./fig09_02.imagen-rota.sh > fig09_02.imagen-rota.salida.txt 2>&1
```

It does not have `ctx &&` in front because it creates its own cluster and the context does not exist yet; it carries its own guards (temporary kubeconfig, context checked before each `kubectl`, deletion of the cluster on exit). If you already have a `curso-k8s-l9` alive, the script stops: it does not touch yours. It takes about four minutes. The command that triggers the error is this one, and it succeeds:

```text
$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:9.9.9
deployment.apps/revisor image updated
```

`image updated`, no complaints: the `kube-apiserver` does not know whether the image exists. It is the same situation as the misspelled `selector` in Lesson 3: a valid name that points to nothing. What follows is read in order, like any failure.

**First, `rollout status`.**

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]
(espera de 10 s: que el kubelet registre el fallo de descarga)
```

It stays at “1 out of 2 new replicas have been updated” and, when the 40-second deadline it was given runs out, exits with `error: timed out waiting for the condition` and code 1. Notice that it **does not say what is wrong**: it only says it does not finish. `rollout status` waits, and the cause has to be sought elsewhere. Without a `--timeout`, it would wait until the Deployment declares that it is not progressing: the `.spec.progressDeadlineSeconds` field, which is 600 seconds by default, after which the Deployment adds a `Progressing` condition set to `False` with the reason `ProgressDeadlineExceeded` ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). The documentation warns that Kubernetes **does nothing** with a stuck Deployment except report it: it does not undo it on its own.

**Second, the Pods.**

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS         RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-6586779dc4-96dfn   0/1     ErrImagePull   0          50s   10.244.2.5   curso-k8s-l9-worker    <none>           <none>
revisor-85f8668b64-2tjx4   1/1     Running        0          60s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running        0          60s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>
```

Three Pods, not two. The two old ones (`85f8668b64`) are still `1/1 Running`. The new one (`6586779dc4`) is in `0/1 ErrImagePull`: the node tried to download the image, did not find it, and there is no container to start. It is the same state as in Lesson 2, with the same output, and it reads the same way: the next step is the `describe`.

**Third, the new Pod's events.**

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

The event `Failed to pull image "curso-docker-revisor:9.9.9"` says, with more text than fits on the page, that it could not resolve `docker.io/library/curso-docker-revisor:9.9.9`: the node looked for the tag on Docker Hub, where it does not exist, because the course's image lives only on your machine. Then `ErrImagePull`, `BackOff` and `ImagePullBackOff`: the `kubelet` retries with longer and longer waits. `(x3 over 50s)` says how many times it tried.

**Fourth, what the Deployment says.**

```text
$ kubectl get deployment revisor -n revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   2/2     1            2           60s
```

`READY 2/2`, `UP-TO-DATE 1`, `AVAILABLE 2`. “Ready: 2 of 2; up to date: 1; available: 2”. The Deployment did exactly what `maxSurge: 1` and `maxUnavailable: 0` asked of it: it created **one** new replica, waited for it to be ready so it could remove an old one, and since it never was, it removed none. The two old ones keep serving.

**And the poller, which ran during the whole jam:**

```text
# resultado del sondeo (durante toda la actualización rota):
    811  código 200  curl rc=0  versión 1.6.0
peticiones=811 fallidas=0
```

In this round none of the 811 requests failed: all were answered by version `1.6.0`, the old one, because no old replica was removed. It is a single round, but what makes the result possible is mechanical, not statistical: with `maxUnavailable: 0`, the Deployment does not remove an old replica without having a new one ready, and the new one never got to be ready. This is the concrete usefulness of `maxUnavailable: 0`: a broken update gets stuck *without removing what works*. Watch what it does not measure: since an old replica was never shut down, it proves nothing about the shutdown race either. With the default value of 25%, a four-replica Deployment would be allowed to remove one before having the new one ready, and a stumble like that could be noticed.

**The fix** is the cause, and the tool is the one from 9.10.2:

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

The `undo` takes the template to the previous one, the Pod that would not start disappears, and the image goes back to `curso-docker-revisor:1.6.0`. (Here there was no Pod of the bad version still answering, as in 9.10.3: it never got to be ready.) In a real project, the definitive fix is to correct the tag in the file and apply it; the `undo` is first aid.

### 9.11 Maintaining a node: the disruption budget

#### 9.11.1 Two kinds of disruption

Not everything that takes a Pod away from a service is the same. The Kubernetes documentation separates **involuntary disruptions**, which are “unavoidable cases” such as “a hardware failure of the machine that hosts the node”, from **voluntary** ones, which are the actions of whoever operates the system: the application owner, or the cluster administrator, who among other things can “drain a node for repair or upgrade” ([Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)). The difference matters because voluntary ones can be **negotiated**: the cluster lets you say how much you are willing to lose. Involuntary ones cannot: nobody asks a disk whether it may fail.

The tool for the negotiation is the **PodDisruptionBudget** (PDB), the second object in `escalado.yaml`. The documentation defines its two forms: `minAvailable`, the number of Pods that must remain available after an eviction, and `maxUnavailable`, the number that may be left unavailable; you declare one or the other, not both. The `revisor`'s says `minAvailable: 1`: with two replicas, one can go, and the other has to stay. Its state is read:

```text
$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     17m
```

`ALLOWED DISRUPTIONS 1` is the count the cluster keeps at this instant: two healthy replicas, minus one that has to stay up, leaves one that can be lost. If one of the two stops being healthy, that number drops to 0, and the next eviction is rejected.

#### 9.11.2 How a node is drained

`kubectl drain` is the command for “this node is going into maintenance”. It does two things, in this order: it marks the node as unschedulable (`cordon`: no new Pod arrives) and it evicts one by one the Pods running on it. The documentation ([Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)) explains that a safe eviction lets the containers terminate in an orderly way and “respects the PodDisruptionBudgets you have specified”. The discipline behind it, according to the disruptions page: `kubectl` requests each eviction through the eviction API; that request may be temporarily rejected, and the tool retries those that fail until all the node's Pods terminate or a deadline you configure (`--timeout`) runs out. The script's command carries two flags. `--ignore-daemonsets`: the documentation says it is needed when there are DaemonSet Pods (such as MetalLB's `speaker`s), which are left where they are and removed when the node leaves the cluster. `--delete-emptydir-data`: it accepts losing the data of `emptyDir` volumes, like the `revisor`'s `/datos`, which dies with the Pod anyway.

#### 9.11.3 The error: a budget with no margin

It is triggered with `fig09_01.pdb-estricto.yaml`, a **program** that fails on purpose: the same PDB, with `minAvailable: 2`.

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

It is applied **in the `revisor` namespace**, with `-n revisor`: the file does not declare a namespace, and an `apply -f` without `-n` creates the object wherever the context points (the `default` namespace), which protects nobody. It is an easy mistake to make, and it was made while preparing this lesson: forgetting the `-n revisor`. The cluster does not complain: the message was `poddisruptionbudget.policy/revisor created` instead of `configured`, the good budget in the `revisor` namespace was left intact (`ALLOWED DISRUPTIONS 1`) and the `drain` went through unhindered, as if the experiment did not exist. The clue was in the word: `created` instead of `configured`. You read the `apply` message, and you check with `get pdb -n revisor`.

```text
$ kubectl apply -n revisor -f fig09_01.pdb-estricto.yaml
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   2               N/A               0                     17m
(el nodo que se va a vaciar: curso-k8s-l9-worker2)
```

`configured`: the object already existed and now says something else. `MIN AVAILABLE 2` and, the figure that matters, `ALLOWED DISRUPTIONS 0`. With two replicas and the obligation to keep two, there is none that can be lost. Now we try to drain a node, with a short deadline so the script does not sit waiting:

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

It reads like a stage script. The node is cordoned (`cordoned`). Evictions are requested for the Pods living there, and those that are not protected go through: `prueba`, MetalLB's `controller` and the Envoy Pod that serves the entry point terminate (`evicted`). And then, over and over, every 5 seconds, this appears:

`error when evicting pods/"revisor-…" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.`

“The Pod cannot be evicted because it would violate the disruption budget.” The cluster was not wrong: it did exactly what it was asked. After 30 seconds the `drain` deadline runs out (`global timeout reached: 30s`) and the command exits with code 1. Look at what state the node was left in:

```text
$ kubectl get nodes
NAME                         STATUS                     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready                      control-plane   26m   v1.37.0
curso-k8s-l9-worker          Ready                      <none>          26m   v1.37.0
curso-k8s-l9-worker2         Ready,SchedulingDisabled   <none>          26m   v1.37.0
```

`Ready,SchedulingDisabled`: still healthy but **cordoned**. An interrupted `drain` leaves the node in that state until someone returns it with `uncordon`; otherwise, no new Pod lands there, and it is one of the ways of running out of capacity without anything being broken. The script returns it:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
```

The fix is to apply the folder again, which carries the good PDB (`minAvailable: 1`), and repeat the `drain`. Now `ALLOWED DISRUPTIONS` goes back to 1 and the eviction of the `revisor` goes through:

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

`evicted` on the first attempt, with no retries or errors. But look where the replicas ended up:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          6s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          109s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

**Both replicas ended up on the same node**, `curso-k8s-l9-worker`. The `revisor` eviction went through (the PDB allowed losing one), but the new replica was born on the only node that could receive it, and now both live together: losing that node would take the entire service with it. The most likely explanation is `Honor`: a cordoned node carries the `node.kubernetes.io/unschedulable` taint, and with `nodeTaintsPolicy: Honor` the tainted nodes (for which the Pod has no toleration) leave the spreading count. While `worker2` was cordoned, the only domain was `worker`, with skew 0, and the spreading allowed both replicas there. The constraint was met; there was nowhere else.

#### 9.11.4 Restoring the spread

The node is returned to service and we wait to see whether the cluster takes care of it by itself:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
(espera de 30 s: ¿vuelve el reparto por sí solo?)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          37s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          2m20s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

No. The two replicas are still together: nothing moved them. It is exactly the limitation in 9.4.4: the spreading constraint is evaluated **when a Pod is scheduled**, not afterwards, and the documentation says there is no guarantee that it keeps being satisfied when Pods are removed, and recommends tools such as the *Descheduler* to rebalance. Without installing anything, the remedy is to trigger a new scheduling, and `kubectl rollout restart` does that: it replaces the replicas with the same gradual procedure as an update, and each new Pod is scheduled with the constraint in place.

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

Again one replica on each worker node. The spread is maintained by a habit, not by a configuration: after a maintenance, look at `-o wide`.

### 9.12 A node that goes down

So far everything was *planned*: an update you launch, a maintenance you request. The other thing is missing: the machine that shuts off without warning. It is the director's third question. It is answered by shutting down one of the worker nodes on purpose, measuring, and asking the cluster when it found out.

#### 9.12.1 What the cluster knows, and when

A failed node sends no warning: it stops sending *heartbeats*. The “Node Status” documentation describes two forms of heartbeat: updates to the node's `.status` and `Lease` objects inside the `kube-node-lease` namespace, one per node; the `kubelet` renews its own every 10 seconds by default ([Node Status](https://kubernetes.io/docs/reference/node/node-status/)). When the heartbeats stop arriving, the node controller waits for a period, `node-monitor-grace-period`, before declaring anything. The node's `Ready` condition changes to `Unknown` if the node controller “has not heard from the node in the last `node-monitor-grace-period` (by default, **50 seconds**)”. It is the detection period, and it is the center of the section.

While those 50 seconds run, the control plane believes the node is fine. Its Pods appear as `Running` and `Ready`, its addresses are still in the `EndpointSlice`s, and the Services keep distributing requests to them. When the period expires, two different things happen:

1. The node changes to `NotReady` (`Unknown`), and the Pods that lived there stop counting as ready; their addresses are marked `ready: false` in the `EndpointSlice`s, and the Service stops using them. **Here the failure window for traffic ends.**
2. The node receives the taint `node.kubernetes.io/unreachable` with the `NoExecute` effect. The Pods that live there have, out of the box, a toleration of that taint of **300 seconds**: the “Taints and Tolerations” documentation says that Kubernetes automatically adds the `not-ready` and `unreachable` tolerations with `tolerationSeconds=300`, and that because of this Pods “remain bound to the nodes for 5 minutes after one of these problems is detected”. After that period, the Pods are evicted and the ReplicaSet creates replacements on another node. **Here the capacity window ends**, and it takes much longer than the failure one.

It is worth separating the two windows because they get confused. The **failure** window (requests that are lost) lasts from when the node goes down until the cluster finds out: about 50 seconds. The **capacity** window (service with one replica fewer) lasts 5 minutes more, until the replacements are born. This lesson measures the first, which is the one your users feel. The second was not measured, because the node is turned back on before it expires.

#### 9.12.2 The experiment

The script chooses the node it will shut down with one condition: it must be a node that **has a replica** of the `revisor` and that is **not** where the `depurar` Pod lives, which is where the requests come from (if the client's node were shut down, the measurement would die with it). With two replicas spread out, one of the two worker nodes meets it. Then it launches **two** pollers at once, with one request every 2 seconds and a single thread, for 100 seconds:

- the first, as is: `./sondeo.sh 100 2 1`;
- the second, with client retries: `./sondeo.sh 100 2 1 --retry 3 --retry-all-errors`.

`--retry 3` asks `curl` to retry up to 3 times a request that failed, and `--retry-all-errors` extends “failed” to any error, including timeouts; the `curl` manual describes the wait between retries: first one second, and then it “doubles the wait time” on each one. The manual calls `--retry-all-errors` the “sledgehammer” of retries and advises against using it by default; here it is a controlled experiment against a service that we know is safe to repeat (`GET /salud`). With an idempotent request (one that can be repeated without effects) the retries are harmless; with one that is not, they would be a risk.

Ten seconds after launching the pollers, `docker stop` stops the node's container, which is the closest thing kind has to “the machine went down”: the `kubelet` and everything running inside it cease to exist at once. The lesson waits 25 seconds and asks two things: how the cluster sees the node, and what the `EndpointSlice`s say about the `revisor`'s addresses.

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

After 25 seconds of being shut down, the node still says `Ready`. The cluster knows nothing. And the proof that it still does not know is in the endpoints:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=true nodo=curso-k8s-l9-worker
(el nodo pasó a NotReady a los 57 s de docker stop)
```

The two `revisor` endpoints appear `ready=true`, **including the one that lives on the shut-down node** (`nodo=curso-k8s-l9-worker`). Any request the Service distributes to that address goes to a Pod that no longer exists. That is the cause of the failures, written on one line.

The script queries the node's state every 3 seconds until it sees it `NotReady`, and then asks again:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=false nodo=curso-k8s-l9-worker
```

The node changed to `NotReady` 57 seconds after being shut down (the documentation's period is 50; the rest adds up to 5 seconds of the controller's cycle, `node-monitor-period`, and 3 of the script's query; also, the node's last heartbeat may have been earlier than the shutdown). And now the failed node's endpoint appears `ready=false`: the cluster stopped distributing traffic to it. That is the moment the failure window ends.

#### 9.12.3 What the pollers measured

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

A clarification about the header: the script notes “+10”, which is the pause it scheduled before shutting down the node. The printed time says the node was shut down 11 seconds after the poller started, because `docker stop` took close to a second. The calculations that follow use 11.

The poller **without retries** made 42 requests in 100 seconds, not the 50 that would fit at a pace of one every 2 seconds, because each failed request takes up the full 2 seconds of its timeout in addition to the pause. 7 failed, all with `curl 28` (timeout, not connection refused: the destination no longer existed). The seconds of the failures, counted from the start of the poller, are `+21 +25 +29 +38 +42 +60 +64`. Since `docker stop` happened at second 11 of the poller, subtracting gives how long after the shutdown each one came: from 10 to 53 seconds. The last failure, at 53 seconds after the shutdown, falls just before the observation of `NotReady` at 57: all seven failures fell between 10 and 53 seconds after the shutdown (measured at the end of each request). That no more were seen does not prove the Service had already stopped using the dead endpoint: with one request every 2 seconds and half of them landing, according to the model, on the live replica, a few in a row can succeed without anything having changed. What was measured is that the endpoint changed to `ready=false` when the node appeared `NotReady`, at 57 seconds.

That is 7 failures out of 42, 17%. That figure mixes the failure window with the rest of the poller's 100 seconds, so it does not say “the service fails one time in six”: it says what happened in this experiment. What explains the failures is that, during the window (up to 57 seconds, until the endpoint changed to `ready=false`), **one of the Service's two endpoints was dead**, and the Service distributes among its endpoints without knowing which one is dead, so a share of the requests in that period ended up at the replica that no longer existed. With two replicas and one dead node, that share would be about half; with four spread replicas, about a quarter; with ten, a tenth. That proportion (one replica out of N) is a model, not a measurement of this run: what was measured is 7 out of 42, but it is what explains why “more spread replicas” shortens the damage without shortening the time.

The poller **with retries** made 32 requests and was slower (each retry waits 1, 2 and 4 seconds before trying again). One failed, at 37 seconds, out of 32: one failure against seven in the other poller, at the cost of some responses taking longer. It is a single round, small, and with fewer requests than the other: it suggests that retries help, but it is not enough to promise how many requests are recovered. It is the second lever: **client retries**. They work because the next time `curl` asks, the Service may choose the live replica, and they do not work if the destination is the same (for example, with a single replica).

Then, the state of the cluster at the moment of bringing the node back up:

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

With the node `NotReady`, the two `revisor` Pods still appear `Running`, including the one on the shut-down node: the cluster does not evict them yet, because the 300-second toleration has not expired. And it will not evict them: the node is turned back on.

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

The node returns to `Ready`, and the Pod that lived on it is still there: the container restarted (`RESTARTS 1`), no other Pod was created, and it changed network address (`10.244.1.4` instead of `10.244.1.33`), but it is the same Pod. In this run the node returned well before the 300 seconds and its Pods stayed.

#### 9.12.4 What shortens the window and what does not

| Lever | Does it shorten? | Why |
|---|---|---|
| **More replicas, spread across nodes** | shortens the *damage*, not the time | with N spread replicas, the spreading model expects one in N on the dead one (calculation, not measurement) |
| **Client retries** | yes, for requests that are safe to repeat | the second time may hit a live replica (measured above) |
| **Lowering `node-monitor-grace-period`** (on the control plane) | yes, at the cost of false alarms | the cluster declares a node down that was merely delayed |
| **Readiness probes** | no | they are run by the `kubelet` of the failed node itself, which no longer reports anything |
| **`tolerationSeconds`** | no | it decides when Pods are replaced, not when they stop receiving traffic |

The last two rows are the ones most believed and least effective, and that is why Exercise 4 puts them to the test. A readiness probe (the `readinessProbe` from Lesson 5) takes a Pod out of the Service's endpoints when it fails, but the one asking the question is the `kubelet` of *that* node. If the whole node is shut down, there is no `kubelet` to ask or to report; the cluster can only wait for the detection period to expire. And `tolerationSeconds` is the grace period before evicting the Pods of a node already declared `unreachable`, that is, a count that starts *after* detection: the shorter it is, the sooner the Pods are replaced, but they do not take the dead endpoints out of the Service any sooner.

Lowering `node-monitor-grace-period` is the only lever that attacks the time, and it costs false alarms (it should not be lowered much: it has to be several times greater than how often the `kubelet` reports; check the flag in the `kube-controller-manager` reference for your version): a node with a ten-second network delay would be declared down, its Pods would be marked not ready and the Service would stop using them for no reason. It is a flag of the `kube-controller-manager`, which in kind lives inside the control-plane node's container; it is not something changed with `kubectl`, and this lesson does not touch it.

The director answered, with what was measured in this run: **with two replicas, seven of 42 requests (17%) were lost during the window of a failed node**, whose last failure fell 53 seconds after the shutdown and which ended when the endpoint changed to `ready=false`, at 57. From the Service's distribution we would expect about half of the requests in that window to land on the dead replica (a calculation, not a measurement). With client retries there was one failure out of 32, but a single round is not enough to promise how many are recovered. When the node returns, the cluster recovers by itself.

#### 9.12.5 After the experiment: the autoscaler's `<unknown>`

The last question of the run is whether everything ended up as the files say, and the answer has a detail that belongs to this lesson:

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

With `sin diferencias con los archivos` (no differences with the files), the cluster and the folder match: everything that was done with commands (`set image`, `patch`, `scale`, `rollout undo`) was undone or applied again. And in the HPA, `TARGETS` says `cpu: <unknown>/50%`. It is the same word that sometimes appears in the first seconds of 9.5.2, and it is worth knowing how to read it, because it is the most common question about autoscalers: **`<unknown>` means “I don't know how much the Pods consume”**, and it has three different causes:

1. **`metrics-server` is not answering.** It is the cause in 9.2. Check with `kubectl get apiservice v1beta1.metrics.k8s.io`: if it says `False`, it is the meter.
2. **The Pods have no CPU `requests`.** Without them there is nothing to calculate the percentage against, and the documentation says the autoscaler will take no action on that metric. Check with `kubectl describe pod`.
3. **The Pods are new and do not have their first reading yet.** It shows in the HPA's events (`kubectl describe hpa`) as `FailedGetResourceMetric … no metrics returned from resource metrics API`, the same warning that 9.6 showed in the first seconds of the new Pods, and it goes away on its own.

At this ending, the third is the candidate: the run brought the shut-down node back up, waited 20 seconds and captured the state; the `revisor` Pod on that node had restarted an instant earlier (`RESTARTS 1`) and did not have a reading yet. The measurement does not distinguish that cause from the first, because the `APIService` was not queried at that moment and it was not checked which node `metrics-server` was running on (if it ran on the shut-down node, it would be the first); what can be said is how to tell them apart. If it were the third, waiting a few seconds would be enough; if not, the `<unknown>` stays. The habit: faced with an `<unknown>`, first `get apiservice`, then `describe pod` looking for the `requests`, and then the clock.

## The lesson's security habit: limits on scaling, and updates that do not take the service down

The course's table of habits assigns this lesson a sentence with two halves: **limits on scaling** and **updates do not take the service down**. They are checked with the cluster in front of you.

**Limits on scaling.** An autoscaler turns *load* into *resources*: more requests, more replicas, more CPU and memory reserved. That is exactly what you want facing a Monday at 9:00, and it is exactly what an attacker, or a bug, can exploit. A client sending requests in a loop (the lesson's `carga` Job is one, on a small scale) costs the service more and more replicas. Without a ceiling, the limit is set by the whole cluster, and a misbehaving service leaves the others without resources. There are three brakes in layers, from the closest to the most general:

1. **The autoscaler's own ceiling.** `maxReplicas: 6`. With the `requests` from Lesson 5, six replicas reserve `6 × 50m = 300m` of CPU and `6 × 32Mi = 192Mi` of memory, a number you can write down and discuss, instead of “whatever there is”. In this lesson's run the autoscaler did not reach that ceiling: the load from a looping `curl` Job settled at four replicas. The ceiling is a guardrail; it was not proven to stop anything, and that distinction counts.
2. **Who can generate the load.** Lesson 7's closed network lets through to the `revisor` only the Pods with the label `acceso-revisor: permitido` and the entry point's Envoys. The `carga` Job carries that label on purpose; without it, its requests would not arrive and the autoscaler would see nothing. Whoever controls the entry point controls who can raise the CPU bill.
3. **The namespace's budget.** There are objects (`ResourceQuota`, `LimitRange`) that put a **total** cap on CPU, memory and number of Pods for a whole namespace, so that a badly configured autoscaler cannot go past it even if its own ceiling is high. Lesson 5 named them and left them out of the course; in a shared cluster they are the layer that really protects the neighbors.

There is also a habit for whoever scales with `metrics-server`: the `--kubelet-insecure-tls` flag from 9.2 exists only in this lab. It is worth writing it where whoever inherits the file will see it (the comment in `metrics-server/kustomization.yaml` says so), because a lab flag copied to another cluster is a security hole disguised as configuration.

**Updates do not take the service down.** What was done to achieve it, and how far it achieves it, is the content of 9.9 and 9.11:

| Component | What it prevents | Where it is measured |
|---|---|---|
| `maxUnavailable: 0` with `maxSurge: 1` | fewer replicas than desired during the replacement | 9.9 |
| `preStop` with `sleep` | requests reaching a replica that already closed its port | 9.9 |
| `PodDisruptionBudget` | a voluntary maintenance removing more replicas than the service can bear | 9.11 |
| spreading with `topologySpreadConstraints` | a single machine concentrating all the replicas | 9.4 and 9.11 |

Notice that the habits table's sentence says “do not take down”, not “lose nothing”. What was measured in 9.9 says how much is lost with and without each component, and that figure, with its uncertainty, is what you hand to whoever asks. A promise of “zero” that nobody measured is worse than a small figure that somebody did.

And one more discipline: the lesson updates with `kubectl set image` and `kubectl patch`, *imperative* commands, because they are the short path for measuring. In a real project, the change is written in the file, reviewed and applied with `kubectl apply -k .`, so that what runs in the cluster and what is in the repository are the same. The end of the run checks it with `kubectl diff -k .`: “sin diferencias con los archivos”.

## Common mistakes

**Leaving `replicas` in the Deployment governed by an HPA.** Each `apply` gives the number back the file's value and undoes what the autoscaler decided. It is removed from the manifest.

**An HPA over Pods with no CPU `requests`.** The percentage is measured against the `requests`; without them, the autoscaler has nothing to calculate with and does nothing.

**Copying `--kubelet-insecure-tls` to a real cluster.** It is the quick way to get `metrics-server` to start in a lab. In a cluster with more people, the solution is for the `kubelet`s' certificates to be signed by the cluster's authority.

**Believing the HPA reacts to a difference of a few points.** Within the 10% tolerance it does nothing. And when scaling down, it does not use what it sees today, but the highest thing it recommended in the window.

**A very high CPU target (90%).** By the time the autoscaler reacts, the service is already saturated, and the new replicas take time to be born.

**`ScheduleAnyway` when what you need is a guarantee.** It is a preference: the scheduler breaks it if it finds no better place.

**Topology spreading without `nodeTaintsPolicy: Honor` in a cluster with a tainted control-plane node.** It works with two replicas and leaves the third `Pending`.

**Believing the spread maintains itself.** It is applied when a Pod is scheduled; a maintenance can leave the replicas together and nothing separates them without a replacement.

**Updating without a pause before shutting down.** An old replica closes its door while the network is still sending it requests.

**Concluding “no failures” from a single short poll.** A round without failures does not prove there are none; with three rounds of each variant, what was measured in 9.9 shows that the failures appear and disappear.

**Believing `rollout status` means “nothing old is still answering”.** It finishes when the Deployment meets what was asked of it (the desired replicas of the new version are ready), not when the last old Pod has finished its `preStop`. Look at `deletionTimestamp`.

**A `PodDisruptionBudget` that does not let any replica be lost.** The `drain` keeps retrying and the maintenance does not progress. The budget has to leave margin.

**A PDB without its namespace.** An object created with `-f` and no `-n` is created wherever the context points, and a PDB in the wrong namespace protects nobody. Read the `created` message and check with `get pdb -n revisor`.

**Counting on probes to shorten the failure of a node.** They are run by the `kubelet` of the failed node; they cannot report anything.

**Trusting that the cluster finds out about a failure immediately.** There is a detection window, and the requests that fall in it are lost.

## Exercises

The first three are run in the lesson's cluster, in order and from the state it was left in after 9.12. Before each command that changes something, `ctx` must succeed. `correr.sh` goes through the lesson, not the exercises; their solutions cite what was measured in the lesson or calculate it, and say so. **Before** running or calculating each one, write in the [logbook](bitacora.md) what you think is going to happen. The fourth is written in your own words.

### Exercise 1 — The formula, by hand

With the target of 50%, `minReplicas: 2` and `maxReplicas: 6`, calculate what the autoscaler would do in each case, and say whether the tolerance stops it:

a) 2 replicas with an average usage of 63%.
b) 3 replicas with an average usage of 46%.
c) 4 replicas with an average usage of 90%.
d) 6 replicas with an average usage of 20%, one minute after the usage dropped.

Then compare (a) and (b) with the `TARGETS` column and the events in 9.6.

### Exercise 2 — Who is in charge

Without looking at 9.8, write down what number of replicas you think the Deployment will have 40 seconds after `kubectl scale deployment/revisor -n revisor --replicas=1`, and from which HPA event you will notice. Run the command and check.

### Exercise 3 — Your own poller

Run `./sondeo.sh 45 0 4` while you do `kubectl set image` between `1.6.0` and `1.6.1`, three times with the folder's `preStop`. Note per round the requests, the failures and the type of each failure (`curl 7` or `curl 28`). Remove the hook with `kubectl patch` (the command from 9.9.6) and repeat. Compare your totals with the lesson's and explain, in three sentences, why yours may differ and what conclusion they do support. To separate the effect of the pause from the effect of the moment, alternate the variants (one round with the pause, one without, another with...) instead of doing all of one and then all of the other. When you finish, go back to `apply -k .`.

### Exercise 4 — Defend the decision

A colleague says: “readiness probes already take a failed replica out of the Service, and `tolerationSeconds` is a node's detection period, so by lowering it to 5 seconds the node outage is over”. In five sentences at most, tell them what really happens when a node shuts down without warning, what each of those two settings measures, and what would shorten the window and at what price.

## Solutions

### Solution 1

It is calculation, not measurement, except where stated.

a) **2 replicas, 63%.** Ratio 1.26, outside 0.9 to 1.1. `ceil(2 × 1.26)` = `ceil(2.52)` = **3**. It scales up to 3. (In 9.6, with 72% and 2 replicas, it asked for 3 by the same rule.)

b) **3 replicas, 46%.** Ratio 0.92: within the tolerance. **It does nothing.** Even if the tolerance did not exist, `ceil(3 × 0.92)` = `ceil(2.76)` = 3, the same number. (In 9.6, with 4 replicas and 46%, it stayed at 4: the same situation.)

c) **4 replicas, 90%.** Ratio 1.8. `ceil(4 × 1.8)` = `ceil(7.2)` = 8. But `maxReplicas` is 6, so the HPA stays at **6**. It would record it in the `ScalingLimited` condition, the same one 9.7 shows for the floor, now for the ceiling; that case was not measured in this run because the load never reached the ceiling. This is the ceiling case: without `maxReplicas`, it would be 8.

d) **6 replicas, 20%, one minute after the usage dropped.** Ratio 0.4. `ceil(6 × 0.4)` = `ceil(2.4)` = 3. The calculation says 3, but the 60-second window says the **highest** recommendation of the last 60 seconds is used: if 59 seconds ago the recommendation was 6, it is still 6 for one more instant. It scales down when that recommendation leaves the window.

### Solution 2

Measured in `correr.salida.txt`:

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

**Two replicas, again.** The Deployment was at 2/2 after 40 seconds, and the HPA's last event says so: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`, from `33s` ago. The `kubectl scale` lowered the `spec.replicas` field to 1; the HPA, on its next pass, saw that 1 was less than the floor of 2 and corrected it. With a live autoscaler, the number of replicas is its own. What you change is the HPA.

### Solution 3

It depends on your machine, and that is what the exercise is about. This run's totals are in 9.9.8: with `preStop`, 5 failures out of 2,049 requests in four rounds, all `curl 28`; without it, 29 out of 1,569 in three rounds, 6 of them `curl 7`. What can be said, and what cannot:

- **Your totals will not match the ones here**, because they depend on how much CPU your client had, how loaded your machine was and how many requests each round managed to make (here there were rounds of 433 and 612 requests in the same time).
- **What should repeat** is the shape: the failures without a pause cluster in the seconds that follow the `set image`, there are refused connections (`curl 7`) only without the pause, and with the pause the rounds give few failures, with some rounds at zero and others with a few isolated ones.
- **What your measurement does not support**: an exact percentage, or the sentence “with `preStop` nothing is lost”. If one of your rounds with the pause gave zero, it does not mean the pause eliminates the failures; it means that round saw none.
- If your rounds with the pause cannot be told apart from the rounds without it, the honest conclusion is that that machine, with that client, does not have the resolution to see the difference. Not that the pause is useless.

### Solution 4

One possible answer: “When a node shuts down without warning, the cluster does not find out immediately: it waits `node-monitor-grace-period`, 50 seconds by default, for the node to report. During that time, the endpoints of the node's Pods remain marked as ready and the Service distributes requests to them that are lost; in the lesson's run 7 out of 42 were lost, and the last failure was 53 seconds after the shutdown. Readiness probes do not help because they are run by the `kubelet` of that node, which is shut down. `tolerationSeconds`, 300 seconds by default, is the period the cluster waits *after* declaring the node unreachable before replacing its Pods, so lowering it replaces the Pods sooner but does not take the dead endpoints out of the Service sooner. What does help is having more replicas spread out (by the spreading, one request in N can be expected to land on the dead one), client retries for requests that can be repeated and, at the cost of false alarms, lowering `node-monitor-grace-period` on the control plane.”

## Deleting the cluster

When you finish the exercises, delete the lesson's cluster. MetalLB, Envoy Gateway, `metrics-server`, the `depurar` Pod and everything else go with it:

```text
$ kind delete cluster --name curso-k8s-l9
Deleting cluster "curso-k8s-l9" ...
Deleted nodes: ["curso-k8s-l9-control-plane" "curso-k8s-l9-worker2" "curso-k8s-l9-worker"]
(borrar tardó 2 s)

$ kind get clusters | grep -c curso-k8s-l9
0
```

Then delete the `token.txt` files and the temporary `kubeconfig` folder, which holds the administrator credential of the cluster you have just deleted. The `rm -rf` is dangerous if the variable is empty or points elsewhere, so it is protected with a `case` that only lets it run if the path is the one `mktemp` created in 9.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 9.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l9.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt punto-de-partida/token.txt
```

Also check that no client container is left (`docker ps -a --filter name=curso-k8s-l9` must show nothing) and that the node you shut down in 9.12 was not left shut down: if you deleted the cluster with the node stopped, `kind delete cluster` removes it too. If you created a Docker network of your own to run several lessons at once, it is deleted after the cluster, and only that one: `docker network rm <your-network>`. The normal `kind` network is not touched.

## How I know I made it

- [ ] Faced with `error: Metrics API not available` you say what is missing (an answerer for the metrics API), and faced with `x509: cannot validate certificate for … because it doesn't contain any IP SANs` you say what is happening and what the flag fixes, and why it is for the lab only.
- [ ] You calculate by hand the replicas the HPA will ask for with `ceil(current × measured ÷ target)`, apply the 10% tolerance and checked it against the `TARGETS` column and the `SuccessfulRescale` events.
- [ ] You explain why the Deployment no longer carries `replicas` and what `kubectl diff` showed in `replicas: 3` → `replicas: 1`.
- [ ] You explain why the scale-down window makes scaling down slow and scaling up fast, and you saw it on the clock.
- [ ] You read the `FailedScheduling` of a spreading constraint and say why the control-plane node requires `nodeTaintsPolicy: Honor`.
- [ ] You run `./sondeo.sh`, read the three columns (code, `curl` exit status, version) and say what distinguishes a `curl 7` from a `curl 28`.
- [ ] You say, with your numbers, how much is lost in an update with and without `preStop`, and what limits your measurement has.
- [ ] You do `rollout undo`, look at `deletionTimestamp` and say why a request could be answered by the version you have just removed.
- [ ] You trigger a `drain` blocked by a PDB that leaves no margin, read it and fix it; and you say why after a maintenance the replicas can end up together.
- [ ] You shut down a node, measure the failure window, and say what shortens it (more spread replicas, client retries, a shorter detection period on the control plane) and what does not (probes, `tolerationSeconds`).
- [ ] You run `programas/09-escalar-y-actualizar/correr.sh > /tmp/mi-corrida-l9.txt 2>&1` and compare against `correr.salida.txt` (do not redirect to that file: it is the reference) what does not change: the `x509`, the `Metrics API not available` and the `MissingEndpoints`; `replicas: 3` → `replicas: 1` in the `diff`; the floor of 2 replicas, one per node; the `FailedScheduling` with `didn't match pod topology spread constraints`; the HPA that scales up on exceeding 55% and down one window later; the poller's two failure modes; the rollback with a request still answered by the removed version; the `drain` blocked by the strict PDB; and the node that changes to `NotReady` after about 50 seconds. The exact request numbers, the times, the Pod names, the IPs and the distribution of failures among rounds change on every run: they are observed, not compared.
- [ ] You trigger an update with an image that does not exist, read `ErrImagePull` and `ImagePullBackOff`, see that the Deployment stays at `UP-TO-DATE 1` with the old replicas available, and roll it back with `rollout undo`.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l9`, the `kubeconfig` temporary folder no longer exists in `/tmp`, and no `token.txt` is left.

## Summary

Answer without looking at the lesson:

1. What is missing in a freshly created cluster for `kubectl top` to work, and why does `metrics-server` not start as is in kind?
2. What is the HPA's formula, what is the percentage measured against, and what does the tolerance do?
3. What does the 60-second scale-down window do, and why does scaling up not have a similar one?
4. Why must a Deployment governed by an HPA not carry `replicas`?
5. What do `maxSkew`, `DoNotSchedule` and `nodeTaintsPolicy: Honor` say, and what happens without the last one?
6. Which two things happen at the same time when a Pod is shut down, and what does the `preStop` close?
7. What distinguishes a `curl 7` failure from a `curl 28` one?
8. What did the poller show with and without `preStop`, and what does it not prove?
9. Why can a version you have just removed with `rollout undo` still answer?
10. What is a PDB, which kind of disruptions does it apply to, and what happens to a `drain` when there is no margin?
11. How long did the cluster take to notice the failed node, and what shortens that window?
12. What happens to the service when an update points to an image that does not exist, and why?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, “Horizontal Pod Autoscaling”](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/): the `desiredReplicas` formula, the calculation against the `requests`, the 10% tolerance, the default 300-second stabilization window for scaling down, the default behavior policy and the recommendation to remove `spec.replicas` from the Deployment.
- [Kubernetes, “Pod Topology Spread Constraints”](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/): `topologyKey`, `maxSkew`, `whenUnsatisfiable`, `nodeTaintsPolicy`, `matchLabelKeys` with `pod-template-hash` and the limitation regarding Pods that are removed.
- [Kubernetes, “Pod Lifecycle”](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): a Pod's termination flow: `preStop`, `TERM` signal, deadline, `KILL`, and the parallel removal of endpoints.
- [Kubernetes, “Container Lifecycle Hooks”](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/): the three types of hook (Exec, HTTP, Sleep) and the shutdown deadline that includes the `preStop`.
- [Kubernetes, “Deployments”](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxSurge`, `maxUnavailable`, `rollout undo`, `--to-revision`, the `kubernetes.io/change-cause` annotation, `revisionHistoryLimit` and the `Available` condition.
- [Kubernetes, “Disruptions”](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/): voluntary and involuntary disruptions, the budget that does not prevent the latter but counts them, and `kubectl drain` with the eviction API.
- [Kubernetes, “Specifying a Disruption Budget for your Application”](https://kubernetes.io/docs/tasks/run-application/configure-pdb/): `minAvailable` and `maxUnavailable`.
- [Kubernetes, “Safely Drain a Node”](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/): what `kubectl drain` does and why it respects PDBs; `--ignore-daemonsets`.
- [Kubernetes, “Node Status”](https://kubernetes.io/docs/reference/node/node-status/): the `Ready` condition set to `Unknown` if the node controller has not heard from the node within `node-monitor-grace-period` (50 seconds by default) and the heartbeats with `Lease`.
- [Kubernetes, “Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): the `not-ready` and `unreachable` taints, and the 300-second tolerations that are added automatically.
- [Kubernetes, “Resource metrics pipeline”](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/): the Metrics API, `metrics-server` and `kubectl top`; CPU as a rate over a window.
- [metrics-server, README](https://github.com/kubernetes-sigs/metrics-server): the requirements (`kubelet` certificate signed by the cluster's authority), `--kubelet-insecure-tls` “for testing purposes only”, and the uses and non-uses.
- [metrics-server, v0.9.0 release notes](https://github.com/kubernetes-sigs/metrics-server/releases/tag/v0.9.0): the version the lesson uses.
- [Phil Pearl, “Kubernetes' dirty endpoint secret and Ingress”](https://philpearl.github.io/post/k8s_ingress/) (July 26, 2019): the removal of endpoints and the shutdown happen at the same time; the pause before shutting down.
- [Go, `net/http`, `Server.Shutdown`](https://pkg.go.dev/net/http#Server.Shutdown): graceful shutdown closes the open listeners first and then the idle connections.
- [Kubernetes, “Job”](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-termination-and-cleanup): `activeDeadlineSeconds` runs from when the Job is created and ends it no matter what.
- [Kubernetes, “kube-controller-manager”](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/): `--node-monitor-grace-period` (50 s) and `--node-monitor-period` (5 s).
- [curl, “man page”](https://curl.se/docs/manpage.html): `--retry`, `--retry-all-errors` and `--max-time`.
- [curl, “libcurl error codes”](https://curl.se/libcurl/c/libcurl-errors.html): codes 7 and 28.

---

**Next:** [Lesson 10 — The finished project and what changes in a real cluster](10-proyecto-final.md)
