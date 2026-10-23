# Lesson 6 — Getting into the cluster

Thursday, 4:40 in the afternoon. The operations team wants to see the `revisor` report from its own dashboard, which runs on another machine, outside the cluster, and the presentation to management is at 5:30. In the team chat there are already two proposals. The first: “change the Service to `NodePort` and give them a node's IP”. The second comes with a link to a tutorial from two years ago: “install `ingress-nginx`, it's three commands”. Both work this afternoon. The first leaves the `revisor` open on a random port on **all** the nodes, without anyone having decided it in writing. The second installs a component that stopped receiving security patches in March 2026. And there is a third temptation, the one in kind's README: a program that you run on your machine and that gives load balancers to your clusters… to **all** your kind clusters, including your colleagues' if you share the machine.

This lesson teaches you to open a way into the cluster without those shortcuts: a `LoadBalancer` with MetalLB and a named entry point with Gateway API and Envoy Gateway, both installed **inside** your cluster, so that they go away with it when you delete it. And it teaches you something that holds for everything you install on Kubernetes from now on: some components are **platform** and some are **project**, and the platform has to be ready before the project uses it.

**Time:** 2 × 45 min

**What you build:** the `revisor` published outside the cluster, first with a `LoadBalancer` Service that receives the IP `172.18.255.200` and then through a named entry point, the `revisor` Gateway, with its route to the usual Service

**What you learn:** why a `LoadBalancer` stays at `<pending>` on kind and what it opens even while pending (a `NodePort` on every node); what MetalLB does in layer 2 and why its range comes from Docker's `kind` network; what custom resources (CRDs) and admission *webhooks* are, and why they force you to install in order; Gateway API with its three components, `GatewayClass`, `Gateway` and `HTTPRoute`, served by Envoy Gateway; why Cloud Provider KIND is not used on a shared machine; `Ingress` as a frozen API and why not `ingress-nginx`; and what ends up exposed, through where and without what (encryption in transit)

**Where you are coming from.** From [Lesson 5](05-salud-recursos-apagado.md): the `revisor` runs with three replicas, with its startup, readiness and liveness probes, with `requests` and `limits`, with its `ConfigMap` as variables and its token as a file, all applied with `kubectl apply -k .`. The test service is also monitored. From [Lesson 3](03-services-dns.md) you bring the rule that everything is born as `ClusterIP` and nothing is published just because, and the order for diagnosing a Service that does not respond: the `curl` code, the name, the `ENDPOINTS` column. Today that rule is broken for the first time, on purpose and in writing.

**What this lesson does not do.** It does not add encryption: the entry point speaks plain HTTP on port 80, and the security-habit section measures it and says so. It does not yet close off who talks to whom **inside** the cluster: that is [Lesson 7](07-aislar-permisos-red.md), which also removes the direct `LoadBalancer` and leaves the Gateway as the only entry point. It does not give you a domain name or a real load balancer from a cloud provider: the IPs MetalLB hands out here exist only on Docker's `kind` network on your machine. And the `revisor` stays in the `default` namespace; the move to a namespace of its own belongs to Lesson 7.

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1, the `kindest/node:v1.37.0` node image pinned by its digest, **MetalLB v0.16.1** and **Envoy Gateway v1.9.2** (which brings Gateway API v1.6.1), on the three-node cluster from Lesson 1, called `curso-k8s-l6` here. The machine was an ARM-based Mac with Docker Engine 29.2.1 inside a Linux virtual machine (Colima), **not** Linux Mint, which is the course's reference system. What changes on your Mint: the architecture, the IPs of the Pods, the Services and the nodes (`172.18.0.2` to `.4`, in a different order), the `NodePort`s that the cluster picks at random, the name suffixes, the ages and the node from which MetalLB announces each IP. The two MetalLB IPs, `172.18.255.200` and `172.18.255.201`, **should** come out identical for you if your `kind` network is `172.18.0.0/16`. And there is one difference that matters: on the Mac, the `kind` network lives inside the virtual machine and your terminal cannot reach it (you will see it in the security habit: code 28); on Linux, Docker connects your machine to that network, so on your Mint `curl http://172.18.255.200/salud` from your terminal should respond. So that the example is the same on both systems, this lesson's “outside client” is a Docker container connected to the `kind` network, outside the cluster. The full tour is in [`programas/06-entrar-al-cluster/`](../programas/06-entrar-al-cluster): `correr.sh` creates the cluster, loads the two images into it, goes through the lesson in order, runs Exercises 1 to 3 and deletes the cluster. At the end it repeats, on a new cluster, the three steps of 6.9 with `levantar.sh`. The complete run, with both clusters, took 15 minutes and 20 seconds (920 seconds): creating the first cluster and waiting for it to be ready took 40 seconds, creating the second, 46, deleting the first, 1, and `levantar.sh` took 266. Its output is `correr.salida.txt`. It needs internet: the MetalLB and Envoy Gateway manifests are downloaded from their releases, pinned to their version, and their images are downloaded the first time.

## By the end you will be able to

- Explain why a `LoadBalancer` Service stays at `<pending>` on kind, and show with `curl` that it has nevertheless already opened a `NodePort` on every node.
- Install MetalLB inside a cluster, give it an IP range taken from the `kind` network, and read in the Service's events who assigned the IP and from which node it is announced.
- Tell a **platform** component (CRDs, controllers, *webhooks*) from a **project** component, and apply them in three steps: platform, wait with `kubectl wait`, project.
- Recognize the errors of applying out of order: `no matches for kind … ensure CRDs are installed first` and `failed calling webhook … connection refused`.
- Write a `Gateway` and an `HTTPRoute` for the `revisor`, and read their status (`PROGRAMMED`, `Accepted`, `ResolvedRefs`).
- Trigger a route to a Service that does not exist, recognize it by `ResolvedRefs=False BackendNotFound` and by the gateway's `500`, and fix it.
- Say what is exposed after this lesson, through which entry point, and what it lacks (encryption in transit), and explain why not Cloud Provider KIND or `ingress-nginx`.

## The why before the how

Until now, everything that talked to the `revisor` was **inside** the cluster: the `depurar` Pod, the `revisor` itself querying `prueba`, the `kubelet`'s probes. You came in through a temporary tunnel, `port-forward`, which lasts as long as your command and talks to a single Pod. That is enough for looking. It is not enough for the operations dashboard in the scene, which needs a stable address, one that survives *rollouts*, that spreads load across replicas and that does not depend on your laptop being powered on.

Kubernetes has three ways of opening that address, from the crudest to the finest:

1. **`NodePort`**: the cluster opens a high port (between 30000 and 32767) on **all** the nodes, and whatever arrives there goes to the Service. It works, but the client has to know a node's IP and a number that the cluster chose.
2. **`LoadBalancer`**: the same as `NodePort`, plus a load balancer **outside** the cluster, with its own IP, that spreads traffic across the nodes. In a cloud, that load balancer is created by the provider. On kind there is no cloud, and that is why the Service is left waiting.
3. **A layer 7 (HTTP) entry point**: a single point that receives the traffic and decides, by path or by site name, which Service each request goes to. The current way to declare it is **Gateway API**. The old way, `Ingress`, still exists and is frozen.

On kind, options 2 and 3 need something the cluster does not bring: someone to hand out IP addresses and someone to serve the entry point. This course installs both **inside** the cluster. **MetalLB** hands out the IPs. **Envoy Gateway** serves the entry point. Each one is installed with its own object types (custom resources) and its own gatekeepers (*webhooks*), and from that comes today's most useful lesson, the one you will use on every real cluster: the platform goes first, you wait for it to be ready, and then the project goes. It is not a whim. It is what the cluster demands of you, and you are going to see it demand it.

The lesson has eight parts of concepts and then the usual sections:

1. **The lesson's cluster** (6.1), with its own `kubeconfig`.
2. **The project before the platform** (6.2): what fails and why.
3. **A `LoadBalancer` with nobody to hand out addresses** (6.3), and the `NodePort` it already opened.
4. **MetalLB** (6.4): the range, layer 2 and the *webhook* that is not listening yet.
5. **Why not Cloud Provider KIND** (6.5).
6. **Envoy Gateway and Gateway API** (6.6): the entry point's platform.
7. **The `revisor`'s entry point** (6.7): `Gateway` and `HTTPRoute`.
8. **`Ingress` and `ingress-nginx`** (6.8): what was retired, so you can recognize it.

And at the end of the concepts, **the order** (6.9), written in three steps.

This is the destination. At the end of 6.7, a client that is not part of the cluster asks the `revisor` for the report through the named entry point:

```text
$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200
```

## If you do not have the image from the Docker course

This lesson uses the same two images as Lessons 3 to 5: `curso-docker-revisor:1.6.0`, the `revisor`'s, and `curso-docker-prueba:1.0.0`, the one for the service that fails on purpose. Check that you have them:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

If you are missing either one, [Lesson 3](03-services-dns.md) says, in this very section, how to build both from the Docker course repository. This lesson asks nothing new of either image. What is new comes from outside: the MetalLB and Envoy images, which are not loaded with `kind load` but are downloaded from the internet by each node the first time, like the `curl` one in Lesson 3.

## The concepts

### 6.1 The lesson's cluster

#### 6.1.1 Before creating: a rule for coexistence

This is the first lesson in the course that installs **MetalLB**, and MetalLB has a particularity that requires a new rule. It is going to take IP addresses from Docker's `kind` network, the network shared by **all** the kind clusters on your machine. If two clusters with MetalLB and the same range run at the same time, both announce the same addresses and step on each other: some requests reach one and some reach the other. So, before creating your cluster, check two things:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar ya en 172.18.255.200. Si este curl responde algo,
# hay otro clúster con MetalLB vivo: espera a que termine.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 3 http://172.18.255.200/
```

kind creates the `kind` network the first time it creates a cluster, so the first command fails if you have never created one; in that case, create the cluster and check it right afterwards, before installing anything. In this lesson's run the network looked like this:

```text
$ docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
fc00:f853:ccd:e793::/64 172.18.0.0/16 
```

Two subnets: one IPv6 and the IPv4 `172.18.0.0/16`, which is the one that matters. If yours is different (for example `172.19.0.0/16`, because on your machine another network already had the `172.18`), you will have to change the range in `infra/metallb-pool.yaml` so that it falls inside yours, and all the IPs in this lesson will come out different for you. There is a third check, the cheapest one: `kind get clusters`. If you see another live cluster that is not yours, ask its owner whether it uses MetalLB and with what range before continuing; the `curl` only sees whoever answers HTTP on port 80 of `.200`, and someone else's MetalLB with another port or with other addresses from the range (`.201` to `.220`) would slip by without you noticing. `correr.sh` does the first two and stops before creating anything if either fails; if the `kind` network does not exist yet, it also stops, because it cannot read its range. In that case, create any test cluster yourself, look at the network and delete it, or create the network by hand with the same subnet.

#### 6.1.2 Creating, checking, loading

From the root of the course repository, with the same care as always:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta se queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l6.XXXX)/kubeconfig"
# curso-k8s-l6 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l6 --config programas/06-entrar-al-cluster/kind-curso.yaml
# Debe decir kind-curso-k8s-l6. Si dice otra cosa, no sigas.
kubectl config current-context
# Una guarda que se detiene sola (la de la Lección 5, con el nombre de este clúster).
# Va delante de cada comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l6
cd programas/06-entrar-al-cluster
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

The `ctx` function compares the active context with the one you expect. If it matches, it prints nothing and returns success; if not, it writes “contexto equivocado: no sigo” (“wrong context: I am not continuing”) and returns an error, and the `&&` makes the command that follows **not run**. It is the difference between eyeballing the context, which depends on you paying attention, and a guard that stops you even when you are in a hurry. Today you will install components that create dozens of objects in the cluster, including objects that apply to the whole cluster and not to a namespace; applying them in the wrong context would mean installing them in someone else's cluster. That is why **in front of every** `apply`, `delete` or `patch` in this lesson goes `ctx &&`. In the outputs that follow it is left out so they fit, but in your terminal it always goes. (`correr.sh` does the same on every command.)

The `(umask 077; …)` deserves an explanation. The `umask` is the mask that tells your shell which permissions to **remove** from every new file; with the usual one (`022`), `token.txt` would be born `-rw-r--r--`, readable by any user on the machine. With `077`, it is born `-rw-------`: only you. The parentheses make the mask change apply only to that command and not stay in your terminal. It is the same care as in Lessons 4 and 5, and it weighs more today, because this lesson talks about shared machines.

```text
$ kubectl config current-context
kind-curso-k8s-l6

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l6-control-plane  Ready   v1.37.0  172.18.0.4
curso-k8s-l6-worker         Ready   v1.37.0  172.18.0.3
curso-k8s-l6-worker2        Ready   v1.37.0  172.18.0.2
```

The new column is `INTERNAL-IP`: each node's address **on Docker's `kind` network**. Remember from Lesson 0 that a kind node is a container; this is that container's IP. All three fall at the beginning of `172.18.0.0/16`, because Docker hands them out from the bottom. Keep them in mind: in 6.3 an outside client is going to come in through them.

`kind load` prints its usual six lines, `not yet present on node … loading...`, two images times three nodes. They are in `correr.salida.txt`.

#### 6.1.3 The outside client

To test from outside the cluster, this lesson uses a `curl` container connected to the `kind` network, named `curso-k8s-l6-cliente` and with `--rm` so that it deletes itself after each request. It is a real client: it is not a Pod, the cluster does not know it, it does not go through the cluster's DNS or through `kube-proxy` on its side. It sees the network the way a machine connected to the same segment as the nodes would. So that you do not type the full line every time, define a function in your terminal:

```bash
afuera() {
  docker run --rm --network kind --name curso-k8s-l6-cliente \
    curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 "$@"
}
# Uso:  afuera -s -m 5 http://172.18.255.200/salud
```

In this lesson's outputs, **the lines that start with `$ curl` run this way**, from that container, except one in the security-habit section, which runs in your terminal on purpose and says so. On Linux Mint you can use `curl` directly from your terminal if you prefer; the result should be the same.

A warning for the shared machine: when you pass the token with `-H "Authorization: Bearer $(cat token.txt)"`, the token becomes a **command argument**, and while the command runs any user on the machine sees it in the process list (`ps`). For this course's dummy token it is fine; with a real token, it is passed from a file (`-H @file`, which `curl` accepts since version 7.55) or through standard input, never written on the line.

### 6.2 The project before the platform

#### 6.2.1 What the folder brings

This lesson's folder brings the same as Lesson 5 left—the two Deployments, the two Services, the `ConfigMap` generator and the `Secret` one—and two new files. The `kustomization.yaml` already mentions them. It is a **program**: `programas/06-entrar-al-cluster/kustomization.yaml`.

```yaml
# kustomization.yaml — Lecciones 4 a 6. Se aplica con: kubectl apply -k .
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Antes de esta kustomization van las piezas de infra/ (MetalLB y Envoy Gateway):
# sin sus CRD, Gateway y HTTPRoute no existen. Ver correr.sh para el orden.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
- revisor-publico.yaml
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

The two new lines in `resources` are `revisor-publico.yaml` (6.3) and `gateway.yaml` (6.7). The comment at the top already warns about what you are about to verify: “Antes de esta kustomization van las piezas de infra/” (“the components in `infra/` go before this kustomization”). Do what anyone in a hurry at 4:40 would do: ignore the warning and apply.

#### 6.2.2 Applying without the platform

```text
$ kubectl get crd
No resources found

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
[código de salida: 1]
```

Read the output in two halves. Above, seven `created` objects: everything the cluster already knew what it was. The names of the generated ones are those from Lesson 4: `revisor-config-t6cm6872fk`, identical in your run because the list did not change, and `revisor-token-…`, different because your token is new. Below, two objects that the cluster **does not recognize**: `no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"`, followed by the suggestion `ensure CRDs are installed first`. `kubectl` applied what it could, skipped what it could not, and exited with code 1. A script with `set -e` would stop here; one without it would carry on as if nothing had happened, and that is worse.

The first command, `kubectl get crd`, already announced it: `No resources found`. This cluster has **no** custom resources at all. And the direct proof:

```text
$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME   SHORTNAMES   APIVERSION   NAMESPACED   KIND
```

Only headers. The `gateway.networking.k8s.io` group does not exist in this cluster.

#### 6.2.3 What a CRD is

Until now, all the types you used—`Pod`, `Deployment`, `Service`, `ConfigMap`, `Secret`—come **inside** Kubernetes: the `kube-apiserver` knows them from the moment it starts. `Gateway` and `HTTPRoute` do not. The [custom resources documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) puts it this way: a custom resource “is an extension of the Kubernetes API that is not necessarily available in a default Kubernetes installation”. And it explains how one is added: with a `CustomResourceDefinition` (CRD) object. “Defining a CRD object creates a new custom resource with a name and schema that you specify. The Kubernetes API serves and handles the storage of your custom resource.”

In other words: a CRD is an object that **teaches** the `kube-apiserver` a new type. As long as the `Gateway` CRD does not exist, a manifest with `kind: Gateway` is, to the cluster, text that means nothing. This is the first reason for the order: **types have to exist before the objects of those types**.

Kubernetes's [Gateway API page](https://kubernetes.io/docs/concepts/services-networking/gateway/) says it about its own case: Gateway API is “an add-on containing API kinds” and its specifications “are defined as custom resources”. It does not come with Kubernetes. Someone has to install it, and in this course Envoy Gateway installs it (6.6).

Notice what **was** created: the `revisor` and `prueba` are running, with their Services, and among them `revisor-publico`. It is exactly the starting point this lesson needs: what you had from Lesson 5, plus an entry point that was requested and is still unopened.

### 6.3 A `LoadBalancer` with nobody to hand out addresses

#### 6.3.1 The manifest

It is a **program**: `revisor-publico.yaml`.

```yaml
# revisor-publico.yaml — Lección 6: un Service LoadBalancer. Su EXTERNAL-IP la
# reparte MetalLB (infra/metallb-pool.yaml); sin MetalLB se queda en <pending>.
# En la Lección 7 se retira: la única puerta que queda es el Gateway.
apiVersion: v1
kind: Service
metadata:
  name: revisor-publico
  labels:
    app: revisor
spec:
  type: LoadBalancer
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

It is the Service from Lesson 3 with two differences: it is called `revisor-publico` and its `type` is `LoadBalancer`. Same selector, same `port: 80`, same `targetPort: http`. It does not replace the `ClusterIP` `revisor`: both exist at the same time and select the same Pods. The inside one is still for the inside clients; this one is the way in from outside. That they are two objects and not one with the type changed is a decision: the day you want to close that way in (Lesson 7 does it), you delete `revisor-publico` and nothing inside notices.

#### 6.3.2 `<pending>`

```text
$ kubectl get services
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes        ClusterIP      10.96.0.1       <none>        443/TCP        36s
prueba            ClusterIP      10.96.248.146   <none>        9000/TCP       7s
revisor           ClusterIP      10.96.157.248   <none>        80/TCP         7s
revisor-publico   LoadBalancer   10.96.115.79    <pending>     80:30808/TCP   7s
```

`EXTERNAL-IP <pending>`: the Service asked for an external IP and nobody has given it one. The [Services documentation](https://kubernetes.io/docs/concepts/services-networking/service/) explains whose job that is: “On cloud providers which support external load balancers, setting the type field to LoadBalancer provisions a load balancer for your Service. The actual creation of the load balancer happens asynchronously, and information about the provisioned balancer is published in the Service's .status.loadBalancer field.” On kind there is no cloud provider. The field stays empty and `kubectl` shows it as `<pending>`, forever, without a single error:

```text
$ kubectl describe service revisor-publico | grep -E '^(Type|LoadBalancer Ingress|Port|NodePort|Endpoints|Events):'
Type:                     LoadBalancer
Port:                     http  80/TCP
NodePort:                 http  30808/TCP
Endpoints:                10.244.2.3:8080,10.244.1.2:8080,10.244.2.4:8080
Events:                   <none>
```

There is no `LoadBalancer Ingress` line (that is where the IP would go) and there are no events: nobody tried anything, so nobody failed. It is the kind of state that confuses, because nothing is red. The only clue is the word `<pending>`.

#### 6.3.3 What it did open: a `NodePort` on every node

Look again at the `PORT(S)` column: `80:30808/TCP`. And in `describe`, `NodePort: http 30808/TCP`. The Service asked for a load balancer that did not arrive, but something did arrive: a **port on the nodes**. The same documentation explains it: “To implement a Service of type: LoadBalancer, Kubernetes typically starts off by making the changes that are equivalent to you requesting a Service of type: NodePort. The cloud-controller-manager component then configures the external load balancer to forward traffic to that assigned node port.” A `LoadBalancer` is a `NodePort` **plus** someone on the outside. Here that someone is missing, but the `NodePort` is already open. You verify it from the outside client, against the IP of a worker node and against that of the control-plane node:

```text
$ curl -s -m 5 http://172.18.0.3:30808/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 http://172.18.0.4:30808/salud
{"estado":"vivo","version":"1.6.0"}
```

Both respond. `172.18.0.3` is `worker`; `172.18.0.4` is the **control-plane** node, where no replica of the `revisor` runs. And yet it answers: each node's `kube-proxy`, including the control-plane one, listens on 30808 and forwards to a replica, wherever it is. This is what the scene's first proposal would have left open, and it is what is **already** open even if the external IP never arrives.

The documentation says how to avoid it: with `spec.allocateLoadBalancerNodePorts: false`, which “should only be used for load balancer implementations that route traffic directly to pods as opposed to using node ports”. Its default value is `true`. MetalLB in layer 2, the one this lesson installs, delivers the traffic to a node and lets `kube-proxy` spread it, so this course does not disable it; but it names it, because “what is exposed” includes this port, and the security-habit section covers it.

### 6.4 MetalLB: the one that hands out the addresses, inside the cluster

#### 6.4.1 What it is

MetalLB is a load balancer for clusters that do not live in a cloud: those in your own data center, those at your home, and kind's. Its [installation guide](https://metallb.io/installation/) describes its two components: the `controller`, a Deployment, “the cluster-wide controller that handles IP address assignments”; and the `speaker`, a DaemonSet (one Pod per node), “the component that speaks the protocol(s) of your choice to make the services reachable”. The first decides which IP each Service gets. The second makes that IP exist on the network.

In this lesson MetalLB works in **layer 2**. Its [configuration guide](https://metallb.io/configuration/) explains it in one sentence: “It works by responding to ARP requests on your local network directly, to give the machine's MAC address to clients.” ARP is the question that a machine asks on a local network to find out who has an IP: “who has `172.18.255.200`?”. No machine has that IP configured. But a node's `speaker` answers “me”, and from that moment the traffic for that IP reaches that node, where `kube-proxy` spreads it across the replicas. It is an honest trick: there is no balancer appliance, there is a node that takes charge of the address.

#### 6.4.2 Installing: the CRDs and the *webhook*

The installation is a manifest from the v0.16.1 release, the one the official guide gives, pinned to its version. This course wraps it in a kustomization so that it can be applied with `-k` like everything else. It is a **program**: `infra/metallb/kustomization.yaml`.

```yaml
# MetalLB v0.16.1 (modo nativo, capa 2), instalado SOLO en este clúster.
# Es la versión que indica la guía oficial de instalación (metallb.io/installation).
# Se aplica antes que todo lo demás de la Lección 6: kubectl apply -k infra/metallb
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
```

The guide says something worth reading before applying: without configuration, “MetalLB's components will still start, but will remain idle until you start deploying resources”, that is, until you give them a range. So there are two steps: install and give the range. Do what anyone in a hurry would do, again: the two back to back.

```text
$ kubectl apply -k infra/metallb | tail -5
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply -f infra/metallb-pool.yaml
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
[código de salida: 1]
```

A different error from the one in 6.2. This time the type **does** exist—MetalLB's `apply` created its CRDs at that same moment—and yet the cluster rejected the two objects. Read it from right to left: `connect: connection refused` against `10.96.93.252:443`; that IP is the one of the `metallb-webhook-service` Service that had just been created (`created`, on line two of the previous output); and what was failing was `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io"`.

An ***admission webhook*** is another gatekeeper that the platform adds to the `kube-apiserver`. The [extensible admission controllers documentation](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) defines them this way: “Admission webhooks are HTTP callbacks that receive admission requests and do something with them.” The validating ones “can reject requests to enforce custom policies”. MetalLB installs one to check that a range is well written before accepting it. The `kube-apiserver`, before saving your `IPAddressPool`, asks the *webhook*. But the Pod that answers that question, the `controller`, was still starting up. Nobody was listening on 443. And what does the `kube-apiserver` do when it cannot ask? That is decided by a field of the *webhook*, `failurePolicy`. The same page says it: with `failurePolicy: Fail`, which is the default value, “an error calling the webhook causes the admission to fail and the API request to be rejected”. MetalLB writes it explicitly in its six *webhooks* (you can check, and the run checks it below): better to reject than to let an unchecked object through.

That is the second reason for the order: **the gatekeepers have to be listening before what they are going to check arrives**. The policy of MetalLB's *webhook* can be read in the cluster itself; there is one value for each of its six gatekeepers:

```text
$ kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Fail Fail Fail Fail Fail Fail
```

Six `Fail`: none lets an object through if it cannot check it. And it is not enough for the CRD to exist:

```text
$ kubectl get crd -o name | grep metallb.io
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io
```

Nine new types, all in the `metallb.io` group. Several are for MetalLB's other mode, BGP, which this course does not use. The two for today are `ipaddresspools` and `l2advertisements`.

#### 6.4.3 Waiting, with `kubectl wait`

The fix is not to retry until it passes. It is to **wait for a condition** and then apply:

```text
$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl apply -f infra/metallb-pool.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
```

The [`kubectl wait` reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) describes it: the command “takes multiple resources and waits until the specified condition is seen in the Status field of every given resource”. `condition=Available` on a Deployment means that it has the **minimum** availability that its update strategy allows (the Deployments documentation defines it that way). With MetalLB's `controller`, which has a single replica, that is the same as “its only replica is ready”; “ready” in the sense of Lesson 5, that of the readiness probes. With a three-replica Deployment and a `maxUnavailable` of 25%, `Available` would arrive with fewer ready replicas than it asks for: do not read it as “all”. In this run, as soon as the `controller` was `Available`, the *webhook* was already answering. For the DaemonSet you use `rollout status`, the same command as in Lesson 2, which waits until there is a ready `speaker` on each of the three nodes. With `--timeout`, no wait is infinite: if something does not arrive, the command fails and you know it.

Same file, without changing a comma, and this time `created`. The file was never wrong. It was early.

```text
$ kubectl get pods -n metallb-system -o wide | awk '{print $1, $2, $3, $6, $7}' | column -t
NAME                         READY  STATUS   IP          NODE
controller-76f4cf76b7-hpzjj  1/1    Running  10.244.1.3  curso-k8s-l6-worker
speaker-455xp                1/1    Running  172.18.0.3  curso-k8s-l6-worker
speaker-jvbvh                1/1    Running  172.18.0.2  curso-k8s-l6-worker2
speaker-xctwr                1/1    Running  172.18.0.4  curso-k8s-l6-control-plane
```

A `controller` with a Pod-network IP (`10.244.`) and three `speaker`s, one per node, with the **node's** IP (`172.18.0.`). That last part is no accident: the `speaker` has to answer ARP on the `kind` network, so it runs on the node's network, not on the Pod network.

#### 6.4.4 The range

It is a **program**: `infra/metallb-pool.yaml`.

```yaml
# metallb-pool.yaml — las IP que MetalLB puede repartir a los Services LoadBalancer.
# Salen de la red «kind» de Docker (en la máquina de las corridas, 172.18.0.0/16;
# compruébala con: docker network inspect kind). Se toma el final del rango, lejos
# de las IP que Docker da a los nodos.
# ⚠️ Dos clústeres de kind con MetalLB y el MISMO rango en la misma red se pisan
# (los dos anuncian las mismas IP): en una máquina compartida, un rango por clúster.
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: curso
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: curso
  namespace: metallb-system
spec:
  ipAddressPools:
  - curso
```

Two objects, two decisions:

- **`IPAddressPool`** says **which** addresses it can hand out: from `172.18.255.200` to `172.18.255.220`, twenty-one. The configuration guide: “All the IPs allocated via IPAddressPools contribute to the pool of IPs that MetalLB uses to assign IPs to services.” Why those: they have to be **inside** the `kind` network (otherwise nobody on that network would ask for them) and **far** from the ones Docker hands out to containers, which start from the bottom (`172.18.0.2`, `.3`, `.4`). The end of the network is the safest place.
- **`L2Advertisement`** says **how** they are announced: in layer 2, by ARP. The guide: “In order to advertise the IP coming from an IPAddressPool, an L2Advertisement instance must be associated to the IPAddressPool.” Without this second object, MetalLB would assign the IP and nobody would answer for it.

```text
$ kubectl get ipaddresspool,l2advertisement -n metallb-system
NAME                             AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ipaddresspool.metallb.io/curso   true          false             ["172.18.255.200-172.18.255.220"]

NAME                               IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
l2advertisement.metallb.io/curso   ["curso"]                                  
```

`AUTO ASSIGN true`: MetalLB takes IPs from this range for any `LoadBalancer` that asks for them, without the Service having to name the range.

#### 6.4.5 The first IP

```text
$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.115.79   172.18.255.200   80:30808/TCP   119s
```

`172.18.255.200`, the first in the range. The Service had been at `<pending>` for almost two minutes; nobody applied it again. MetalLB, once it had a range, looked for the `LoadBalancer`s without an IP and gave them one. It is the thermostat from Lesson 0 again: the desired state had been written since 6.2, and as soon as there was someone to pursue it, it was reached. The `NodePort` is still `30808`: the external IP was set up **on top of** the node port, as the documentation says.

Who did it, and from where? The Service's events say so, which in 6.3 were empty:

```text
$ kubectl get events --field-selector involvedObject.name=revisor-publico --sort-by=.lastTimestamp | awk '{$1=""; print}' | sed 's/^ //'
SEEN TYPE REASON OBJECT MESSAGE
Normal IPAllocated service/revisor-publico Assigned IP ["172.18.255.200"]
Normal nodeAssigned service/revisor-publico announcing from node "curso-k8s-l6-worker2" with protocol "layer2"
```

(`awk` removes the age column so that it fits; the header keeps its name.) Two events, both from MetalLB: `IPAllocated`, from the `controller`, which chose the IP; and `nodeAssigned`, from the `speaker`, which says from which node it announces it: `curso-k8s-l6-worker2`, in layer 2. In your run the node may be a different one. That node is, from now on, the physical entry point of `172.18.255.200`: if it goes down, another `speaker` takes over the announcement.

And the test that matters, from the outside:

```text
$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           7ms  200
```

A stable address, on port 80, with no odd number, that spreads load across the three replicas and that is still there even if the Pods change. What the scene's dashboard needed. (The `…` stand in for the token in the published outputs; in your terminal goes the content of `token.txt`, with `-H "Authorization: Bearer $(cat token.txt)"`.)

### 6.5 Why not Cloud Provider KIND

If you search for “LoadBalancer on kind”, the first answer is kind's own. Its [LoadBalancer guide](https://kind.sigs.k8s.io/docs/user/loadbalancer/) recommends **Cloud Provider KIND**, and its [Ingress guide](https://kind.sigs.k8s.io/docs/user/ingress/) says that, since v0.9.0, that program “natively supports Ingress” and that Gateway API “is also natively supported”. It is a serious tool, from the same group that maintains kind. Why does this course not use it?

Because of **where it runs** and **what it acts on**. kind's guide says so: Cloud Provider KIND “runs as a standalone binary in your host and connects to your KIND cluster”, and “requires privileges to open ports on the system and to connect to the container runtime”. Its [README](https://github.com/kubernetes-sigs/cloud-provider-kind) is more precise: “The cloud-provider-kind will monitor **all** your KIND clusters”, and its Gateway API controller “is enabled by default”. The README does not describe any option to limit itself to one.

On your personal laptop, with a single cluster, that does not matter. On a shared machine—a lab's, a team's that runs tests in parallel, or yours if you have a cluster from another project—it matters a lot: a process that you launched for your lesson would start creating load balancers, CRDs and a `GatewayClass` on clusters that are not yours, without their owners having asked for it. This course has had a rule since Lesson 1: do not touch what is not yours, neither another context nor another cluster. Cloud Provider KIND breaks it by design.

MetalLB and Envoy Gateway, by contrast, are objects **inside** the cluster. They are installed with `kubectl` in your context, they live in their namespaces (`metallb-system`, `envoy-gateway-system`) and they disappear with `kind delete cluster`. The price is the one you saw in 6.1: MetalLB's range comes from the `kind` network, which is shared, and that is why two clusters with the same range must not run at the same time. It is a price that is controlled with a one-line check. The other thing is not controlled.

### 6.6 Envoy Gateway and Gateway API: the entry point's platform

#### 6.6.1 The three components of Gateway API

A `LoadBalancer` is one entry point per Service: each with its own IP. If tomorrow you publish five services, that is five IPs, and none of them knows anything about HTTP: it cannot decide by path, or by site name, or provide a common encryption. Gateway API solves that with **one** entry point that understands HTTP and rules that say what comes in and where it goes. Kubernetes's [Gateway API page](https://kubernetes.io/docs/concepts/services-networking/gateway/) describes its three components:

| Component | What it is, according to the documentation | In this course |
|---|---|---|
| `GatewayClass` | “Defines a set of gateways with common configuration and managed by a controller that implements the class” | `eg`, Envoy Gateway's |
| `Gateway` | “Defines an instance of traffic handling infrastructure, such as cloud load balancer” | `revisor`: listens for HTTP on 80 |
| `HTTPRoute` | “Defines HTTP-specific rules for mapping traffic from a Gateway listener to a representation of backend network endpoints”, endpoints that “are often represented as a Service” | `revisor`: everything that arrives goes to the `revisor` Service |

The same page explains why there are three and not one: Gateway API is “role-oriented”. The `GatewayClass` belongs to the **infrastructure provider**; the `Gateway`, to the **cluster operator**, who is concerned with “policies, network access, application permissions”; the `HTTPRoute`, to the **application developer**, who is concerned with their Service. On your cluster you are all three, but the files are already separated that way: `infra/gatewayclass.yaml` is platform, `gateway.yaml` is project.

#### 6.6.2 Installing with `--server-side`, and why

Envoy Gateway brings the Gateway API CRDs and its own in a single file. Its [installation guide](https://gateway.envoyproxy.io/docs/install/install-yaml/) says so: “The install.yaml manifest includes Gateway API CRDs and Envoy Gateway CRDs.” This course wraps it the same way as MetalLB. It is a **program**: `infra/envoy-gateway/kustomization.yaml`.

```yaml
# Envoy Gateway v1.9.2, instalado SOLO en este clúster. Trae los CRD de Gateway API
# (bundle v1.6.1) y los suyos. Su guía oficial lo instala con server-side apply:
#   kubectl apply --server-side -k infra/envoy-gateway
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/envoyproxy/gateway/releases/download/v1.9.2/install.yaml
```

The official guide installs it with `kubectl apply --server-side`. What happens without that flag? You can ask without changing anything, with `--dry-run=server`, which sends everything to the `kube-apiserver` to be validated and saves nothing:

```text
$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -c 'Too long'
3

$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -m 1 'Too long' | sed 's/.*\(The CustomResourceDefinition\)/\1/'
Error from server (Invalid): error when creating "infra/envoy-gateway": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(In `correr.salida.txt`, below each of these two commands `[código de salida: 1]` (“exit code: 1”) appears. It is the exit code of `kubectl apply`, whose attempt the `kube-apiserver` rejected. The script runs with `pipefail`, which makes a pipeline fail if any of its commands fails. In your terminal, without `pipefail`, the pipeline returns the exit code of `grep`, which is 0, and you will not see that line.) Three CRDs rejected, for the same reason: `metadata.annotations: Too long: may not be more than 262144 bytes`. The cause is in how the usual `apply` works, the one you have used since Lesson 2. That `apply` stores in each object an annotation, `kubectl.kubernetes.io/last-applied-configuration`, with **a complete copy** of the manifest you applied, so it can compute the difference next time. With a Deployment, that copy weighs a few kilobytes. With the `EnvoyProxy` CRD, whose schema describes hundreds of fields, the copy exceeds the 256 KiB cap that the `kube-apiserver` accepts for all of an object's annotations.

`--server-side` changes who keeps the books. The [*server-side apply* documentation](https://kubernetes.io/docs/reference/using-api/server-side-apply/) explains it: it provides “an optional mechanism for your cluster's control plane to track changes to an object's fields”, and it contrasts it with `kubectl`'s annotation: instead of storing “a user's last applied state”, it records which fields each party manages, in `metadata.managedFields`. No copy of the manifest, no giant annotation.

```text
$ kubectl apply --server-side -k infra/envoy-gateway | tail -4
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl get crd -o name | grep -c gateway.networking.k8s.io
10

$ kubectl get crd -o name | grep -c gateway.envoyproxy.io
8
```

Every line says `serverside-applied` instead of `created`. The last four already tell the story of this lesson: an admission validation policy (`safe-upgrades`, as its name says), a `Job` called `certgen` that, going by its name, generates certificates, and another *webhook*, this time one of the kind that **modifies** objects (`mutatingwebhookconfiguration`). Gatekeepers again. But not all of them block: this one declares `failurePolicy: Ignore`, meaning that if it does not answer, the `kube-apiserver` lets the request through. Which is which is read in the manifest, not assumed (the run shows it below). Ten Gateway API CRDs and eight Envoy Gateway ones. There are more, and they are measured:

```text
$ kubectl get crd -o name | grep gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io

$ kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.annotations.gateway\.networking\.k8s\.io/channel} {.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}{end}' | grep 'gateway.networking.k8s.io ' | column -t
backendtlspolicies.gateway.networking.k8s.io  experimental  v1.6.1
gatewayclasses.gateway.networking.k8s.io      experimental  v1.6.1
gateways.gateway.networking.k8s.io            experimental  v1.6.1
grpcroutes.gateway.networking.k8s.io          experimental  v1.6.1
httproutes.gateway.networking.k8s.io          experimental  v1.6.1
listenersets.gateway.networking.k8s.io        experimental  v1.6.1
referencegrants.gateway.networking.k8s.io     experimental  v1.6.1
tcproutes.gateway.networking.k8s.io           experimental  v1.6.1
tlsroutes.gateway.networking.k8s.io           experimental  v1.6.1
udproutes.gateway.networking.k8s.io           experimental  v1.6.1

$ kubectl get mutatingwebhookconfiguration envoy-gateway-topology-injector.envoy-gateway-system -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Ignore
```

Three things can be read there. Ten `gateway.networking.k8s.io` CRDs, **all** of them from the `experimental` channel and from Gateway API's `v1.6.1` bundle (the standard channel would be only what is stable; the experimental one also brings fields and versions under test). Three more CRDs, from the `gateway.networking.x-k8s.io` group, which the `grep -c` above did not count: the `x` is for experimental. And a mutating *webhook* with `failurePolicy: Ignore`. The `column -t` only aligns the table. In total, then: ten plus three from Gateway API and eight from Envoy Gateway.

#### 6.6.3 Waiting again, and the class

Before using the new types, you wait for them to be **established**, and before asking for an entry point, for the controller to be available:

```text
$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met
```

`Established` is the condition the `kube-apiserver` sets on a CRD when it already serves the new type. A newly created CRD can take a moment to become so; waiting for the condition is asking the cluster instead of guessing. Here they already were: `condition met` immediately. The second `wait` is the same as the one you used with MetalLB's `controller`, now with Envoy Gateway's controller.

Now the class. It is a **program**: `infra/gatewayclass.yaml`.

```yaml
# gatewayclass.yaml — «eg»: la clase de puerta que atiende Envoy Gateway.
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

A `GatewayClass` is short: a name, `eg`, and the controller that serves it. The `controllerName` is not decoration: it is the signature with which Envoy Gateway's controller recognizes the classes that are its own. If you wrote another one, the class would exist and nobody would accept it.

```text
$ kubectl apply -f infra/gatewayclass.yaml
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl get gatewayclass
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       0s

$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME                 SHORTNAMES   APIVERSION                     NAMESPACED   KIND
backendtlspolicies   btlspolicy   gateway.networking.k8s.io/v1   true         BackendTLSPolicy
gatewayclasses       gc           gateway.networking.k8s.io/v1   false        GatewayClass
gateways             gtw          gateway.networking.k8s.io/v1   true         Gateway
grpcroutes                        gateway.networking.k8s.io/v1   true         GRPCRoute
httproutes                        gateway.networking.k8s.io/v1   true         HTTPRoute
listenersets         lset         gateway.networking.k8s.io/v1   true         ListenerSet
referencegrants      refgrant     gateway.networking.k8s.io/v1   true         ReferenceGrant
tcproutes                         gateway.networking.k8s.io/v1   true         TCPRoute
tlsroutes                         gateway.networking.k8s.io/v1   true         TLSRoute
udproutes                         gateway.networking.k8s.io/v1   true         UDPRoute
```

Between the `apply` and the `get` goes a third `wait`, this time for the class's `Accepted` condition: the controller takes a few seconds to recognize it, and without that wait your `get` could show `ACCEPTED Unknown`. `ACCEPTED True`: Envoy Gateway recognized the class as its own. And the same `api-resources` that in 6.2 gave only headers now gives ten types, which `api-resources` shows at `v1`. Careful with that word: it is the **preferred** version that the cluster serves, not a guarantee that everything is stable. Envoy Gateway's `install.yaml` installs the CRDs from Gateway API's **experimental** channel (each CRD's `gateway.networking.k8s.io/channel: experimental` annotation says so, and the run reads it above), which brings, besides what is stable, fields and versions under test, and three more types from the `gateway.networking.x-k8s.io` group. The three that this lesson uses, `GatewayClass`, `Gateway` and `HTTPRoute`, are stable. On a real cluster you choose on purpose which channel to install. Today you use three. `GRPCRoute`, `TCPRoute` and `UDPRoute` are routes for other protocols; `TLSRoute` and `BackendTLSPolicy` are, respectively, letting encryption pass through without opening it and encrypting the leg from the gateway to the Service, things this lesson does not set up. `ReferenceGrant` is the permission that the owner of a namespace gives so that something in **another** namespace can point to its objects: for example, a route that sends traffic to someone else's Service, or a Gateway that uses a certificate stored in someone else's `Secret`. In this course the route and the Service always live in the same namespace, so you will not need it. Whether a route can attach to a Gateway in **another** namespace is not decided with `ReferenceGrant`, but with the `allowedRoutes` field of the Gateway's *listener*; the [Gateway documentation](https://kubernetes.io/docs/concepts/services-networking/gateway/) puts it this way: “By default, a Gateway only accepts Routes from the same namespace.” Notice the `NAMESPACED` column: `gatewayclasses` is `false`, because a class applies to the whole cluster. It is platform.

### 6.7 The `revisor`'s entry point

#### 6.7.1 The manifest

It is a **program**: `gateway.yaml`.

```yaml
# gateway.yaml — Lección 6: Gateway API, la sucesora de Ingress.
# La puerta (Gateway «revisor», clase «eg» de Envoy Gateway) recibe una IP de
# MetalLB; la ruta (HTTPRoute) manda todo al Service revisor. Solo HTTP: el
# cifrado en tránsito es lo que la lección dice que falta.
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: revisor
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisor
      port: 80
```

Two objects in one file, separated by `---`. They read like this:

- **The `Gateway`** asks for an entry point of the `eg` class with a *listener* (an “ear”): `http`, protocol `HTTP`, port `80`. It says nothing about IPs: Envoy Gateway asks for the IP from whoever hands them out, which in this cluster is MetalLB.
- **The `HTTPRoute`** attaches to that entry point with `parentRefs: [revisor]` and has one rule: whatever starts with `/` (`PathPrefix`), that is, everything, goes to the `revisor` Service on its port `80`. Notice the destination: the `ClusterIP` `revisor` from Lesson 3, not `revisor-publico`. The gateway enters the cluster and from there uses the inside Service, with its EndpointSlice and its load spreading.

The [`HTTPRoute` reference](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) also says that, if you do not write `matches`, the default value is exactly this, a `/` prefix, “which has the effect of matching every HTTP request”. The course writes it anyway, for the same reason it wrote `type: ClusterIP`: so that the “everything goes through” decision is in plain view. Exercise 2 changes it.

#### 6.7.2 Applying, this time for real

The same command as in 6.2, with the platform in place:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bmkbmd25cg unchanged
service/prueba unchanged
service/revisor unchanged
service/revisor-publico unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Seven `unchanged` and two `created`. Nothing restarted: the `Secret` kept its name because `token.txt` is the same one as in 6.2, and the Deployment had no reason for a *rollout*. `apply` is declarative, and applying it twice is safe: what was already there stays. That is why the fix for the ordering error was not “delete everything and start over”, but installing what was missing and applying the same thing again.

The `wait` waits for the Gateway's `Programmed` condition: that the controller has already configured the infrastructure that serves it.

```text
$ kubectl get gateway,httproute
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.18.255.201   True         113s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               113s

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

The Gateway has an address, `172.18.255.201`, the second in MetalLB's range (the first already belonged to `revisor-publico`), and `PROGRAMMED True`. The route has two conditions, which you will use in “The error you will see”: `Accepted=True`, the gateway accepted it as its own; and `ResolvedRefs=True`, everything it names (the `revisor` Service and its port) exists.

#### 6.7.3 Who serves the entry point

A `Gateway` is a declaration. Someone has to make it real:

```text
$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-default-revisor-4e6f5d7f-55b49857bd-25dqk   2/2     Running   0          113s
pod/envoy-gateway-5fc4949dcb-f8jss                    1/1     Running   0          5m44s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
service/envoy-gateway                    ClusterIP      10.96.233.233   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   5m45s
```

Two Pods. `envoy-gateway` is the **controller**: it reads your `Gateway` and `HTTPRoute` and translates. `envoy-default-revisor-…` is the **proxy**, the Envoy that actually receives the requests; its name joins the Gateway's namespace (`default`) and its name (`revisor`). The controller created it when your Gateway appeared, with a Service of its own **of type `LoadBalancer`**, and that is the one that received `172.18.255.201` from MetalLB. The two platforms in this lesson work together without knowing each other: Envoy Gateway asks for a `LoadBalancer`, MetalLB gives it one.

Here are all the cluster's `LoadBalancer`s:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
default                revisor-publico                  LoadBalancer   10.96.115.79    172.18.255.200   80:30808/TCP                                       8m21s
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
```

Two entry points to the `revisor`: the direct one, `.200`, and the named one, `.201`. Keep this table for the security habit.

#### 6.7.4 Getting in

```text
$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados
401

$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|server|content-type)"
HTTP/1.1 200 OK
content-type: application/json
```

The three answers that matter: `/salud` responds, `/api/estados` with the token gives the table, and without a token it gives `401`. That `401` comes from the **`revisor`**, not from the gateway: the Gateway lets everything through and the `revisor` keeps demanding its token as it has since Lesson 4. The `revisor`'s log confirms it:

```text
$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /api/estados'
[pod/revisor-5674f7c4cc-bhbvp/revisor] revisor: GET /api/estados 200 17ms
[pod/revisor-5674f7c4cc-pbc9f/revisor] revisor: GET /api/estados 200 8ms
[pod/revisor-5674f7c4cc-w7hgf/revisor] revisor: GET /api/estados 401 1ms
```

(`kubectl logs -l` merges the logs of the three replicas, grouped by Pod and not by time, so the order of the lines is not the order of the requests.) Up to that point there were three requests to `/api/estados`: the one in 6.4.5 through `.200`, the one above with a token through the gateway and the one above without a token. All three appear, and what can be stated is what the `401` says: a `revisor` wrote it in its log, which means it gave it and not the gateway. Which replica served each one cannot be deduced from this output; spreading the load is handled by the usual thing, the `revisor` Service, not the gateway.

The last `curl` above asked for the headers with `-i`: `HTTP/1.1 200 OK`. One more, which the security-habit section picks up again: it is HTTP/1.1 on port 80, unencrypted.

### 6.8 `Ingress`, the frozen API, and why not `ingress-nginx`

You will find `Ingress` in almost every Kubernetes tutorial from before 2024. It is the grandfather of what you have just done: an object that says “this path goes to that Service”, served by a controller. It still exists, and the [Ingress documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/) states its status in so many words: “The Ingress API has been frozen”; it “is no longer being developed, and will have no further changes or updates made to it”. And the recommendation: “The Kubernetes project recommends using Gateway instead of Ingress.” Watch out for what it does **not** say: it is not deprecated in the sense that it is going to be removed. The same page makes clear that it is a stable API, subject to the stability guarantees of generally available APIs, and that the project “has no plans to remove Ingress from Kubernetes”. Frozen means: it works, it does not grow. What it lacks (routes for other protocols, separate roles, finer rules) is not going to arrive. Gateway API was born for that.

`ingress-nginx` is something else: not an API, but an Ingress **controller**, the most popular one for years, the one in the scene's second proposal. In November 2025, the [Kubernetes blog](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) announced its retirement: “In March 2026, Ingress NGINX maintenance will be halted, and the project will be retired. After that time, there will be no further releases, no bugfixes, and no updates to resolve any security vulnerabilities that may be discovered.” Existing installations keep working and the artifacts remain downloadable, says the same announcement. That is why the tutorial from two years ago still “works” this afternoon. But a component that receives traffic from outside and no longer receives security patches is exactly what you do not install today. The announcement recommends migrating to Gateway API or to another controller.

Three names, three different things:

| Name | What it is | Status |
|---|---|---|
| `Ingress` | a Kubernetes API | frozen: it works, it does not grow |
| `ingress-nginx` | a controller that serves `Ingress` | retired since March 2026: no patches |
| Gateway API | the API that succeeds `Ingress` | current; this course uses it |

Exercise 3 lets you see an `Ingress` on this cluster, and what happens to it when nobody serves it.

### 6.9 The order: platform, wait, project

Put together what you saw. In 6.2, the project before the platform: `no matches for kind`. In 6.4, the range before the gatekeeper: `failed calling webhook … connection refused`. In 6.6, the project could not have asked for its Gateway before the `eg` class existed either. In all three cases, the file was right. What was wrong was the timing.

This is how what is in this lesson is set up from an empty cluster, in three steps. It is not a fragment written from memory: it is the `levantar.sh` program, and it was really run. `correr.sh` deletes the exercises' cluster, creates **another** identical one, with the two images loaded and without a single custom resource (`kubectl get crd` gives `No resources found`), and runs `levantar.sh` without fixing anything by hand:

```bash
#!/usr/bin/env bash
# levantar.sh — Lección 6, sección 6.9: la plataforma y el proyecto, desde un
# clúster recién creado, en tres pasos y en este orden:
#   1. la plataforma: los tipos nuevos (CRD), sus controladores y sus guardianes;
#   2. la espera: tipos establecidos y controladores listos (kubectl wait);
#   3. la configuración de la plataforma (rango y clase) y después el proyecto.
#
# Uso, desde esta carpeta y con el clúster curso-k8s-l6 recién creado, las dos
# imágenes cargadas y token.txt generado:   ./levantar.sh
#
# 🔴 Antes de CADA cambio, ctx comprueba que el contexto activo es
# kind-curso-k8s-l6 y, si no, el guion se detiene: MetalLB y Envoy Gateway crean
# objetos que valen para todo el clúster, y aplicarlos en otro sería instalarlos
# en el clúster de otra persona.
set -euo pipefail
cd "$(dirname "$0")"

ctx() { [ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo" >&2; return 1; }; }
# paso CADENA → comprueba el contexto, imprime «$ CADENA» y la corre. Si falla, se detiene.
paso() { ctx; printf '\n$ %s\n' "$*"; eval "$@"; }

[ -f token.txt ] || { echo "falta token.txt: (umask 077; openssl rand -hex 16 > token.txt)" >&2; exit 1; }

echo "## Paso 1: la plataforma"
paso "kubectl apply -k infra/metallb"
paso "kubectl apply --server-side -k infra/envoy-gateway"

echo
echo "## Paso 2: la espera"
paso "kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
paso "kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s"
paso "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"

echo
echo "## Paso 3: la configuración de la plataforma, y el proyecto"
paso "kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml"
paso "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
paso "kubectl apply -k ."
paso "kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s"
```

The `paso` function does three things: it checks the context with `ctx` (and stops if it is not `kind-curso-k8s-l6`: MetalLB and Envoy Gateway create objects that apply to the whole cluster), prints the command with `$` and runs it. With `set -euo pipefail`, the first error stops the script, so a run without interruptions is the proof that the order works.

The range and the class go in **step 3** and not in step 1 because of what you saw: the range needs MetalLB's *webhook* to answer (6.4.2) and the class needs its CRD to be established (6.6.3). The course README calls them “three steps” even though the block has more than three commands: the steps are about **order**, not about the number of commands. (In Lesson 10, the two platform `apply`s of step 1 are merged into one.) This is the output of that run:

```text
$ kubectl get crd
No resources found

$ ./levantar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb
namespace/metallb-system created
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io created
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io created
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io created
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io created
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io created
serviceaccount/controller created
serviceaccount/speaker created
role.rbac.authorization.k8s.io/controller created
role.rbac.authorization.k8s.io/pod-lister created
clusterrole.rbac.authorization.k8s.io/metallb-system:controller created
clusterrole.rbac.authorization.k8s.io/metallb-system:speaker created
rolebinding.rbac.authorization.k8s.io/controller created
rolebinding.rbac.authorization.k8s.io/pod-lister created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:controller created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:speaker created
configmap/metallb-excludel2 created
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway
namespace/envoy-gateway-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/clienttrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyextensionpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoypatchpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyproxies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutefilters.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/listenersets.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/securitypolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tcproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/udproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io serverside-applied
serviceaccount/eg-gateway-helm-certgen serverside-applied
serviceaccount/envoy-gateway serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-role serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-role serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-rolebinding serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-rolebinding serverside-applied
configmap/envoy-gateway-config serverside-applied
service/envoy-gateway serverside-applied
deployment.apps/envoy-gateway serverside-applied
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
(levantar.sh tardó 266 s)
```

Read it step by step. Step 1: a `created` for each MetalLB object and a `serverside-applied` for each Envoy Gateway object; the second one sends all at once the ten plus three Gateway API CRDs and Envoy's eight. Step 2: five waits, and all of them end in `condition met` or `successfully rolled out`; the `speaker` goes from 0 to 3 available pods. Step 3: the range and the class are created together, the class is waited on until `Accepted`, the project is created in full (nine `created`, without a single `no matches for kind`) and the Gateway reaches `Programmed`. No errors, and no `sleep`. Afterwards, `correr.sh` checks what matters:

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         82s

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.165.26   172.18.255.200   80:31214/TCP   82s
(espera: la puerta ya contesta 200 en http://172.18.255.201/salud)

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}


$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

The Gateway and the `LoadBalancer` again received `172.18.255.201` and `.200`, respectively, the gateway answers `/salud` and the report table, and so does `.200`. (This new cluster's Service has another `NodePort`, `31214`, and the Gateway took `82s` to exist, because the `kubectl apply` and the waits of step 3 run before this `get`.) With this, the lesson's goal is met: a new cluster, three steps, nothing fixed by hand.

Three ideas you will recognize in Lesson 10, when the whole project is set up with two `apply -k` and one wait:

- **The platform is installed once per cluster; the project, every time it changes.** MetalLB and Envoy Gateway do not belong to the `revisor`: the day you publish a second service, it will use the same `eg` class and the same range.
- **A wait is not a `sleep`.** A `sleep 30` works on your machine and fails on a slower one. `kubectl wait` asks for the condition and fails clearly if it does not arrive in the time you gave it.
- **The order is not hidden.** If you automate it (a script, a step in a *pipeline*), the three steps are still there, with names, each with its context check (`ctx`). A script that “retries until it passes” hides the cause; one that waits for the condition names it.

## The error you will see

This lesson's error is the most common one with Gateway API, and it resembles the mistyped selector from Lesson 3: a route that points to a Service that does not exist. It is triggered with `fig06_01.ruta-mala.yaml`, a **program** that fails on purpose: the same `HTTPRoute`, with one letter missing in the destination.

```yaml
# fig06_01.ruta-mala.yaml — FALLA A PROPÓSITO: la misma ruta del revisor con una
# letra de menos en el Service de destino (revisr). El Gateway la acepta, pero no
# encuentra a quién mandarle el tráfico: ResolvedRefs=False BackendNotFound, y la
# puerta responde 500. Se corrige volviendo a aplicar la kustomization (apply -k .).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisr
      port: 80
```

```text
$ kubectl apply -f fig06_01.ruta-mala.yaml
httproute.gateway.networking.k8s.io/revisor configured
```

`configured`, with no complaints. As with the selector in Lesson 3, the `kube-apiserver` cannot know you meant to write `revisor`: `revisr` is a valid name. Read it in order.

**First, the symptom**, from the outside:

```text
$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|content-length)"
HTTP/1.1 500 Internal Server Error
content-length: 0
```

`500` and an empty body. Notice what it is **not**. It is not a `curl` code (6, 7 or 28): the connection was made, someone answered. And it is not the `revisor`: the `revisor` never answers with an empty body. The one that answered was Envoy, the gateway, saying “I have nobody to send you to”. The [Gateway API v1.6 specification](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/) demands it: if all the references in a rule are invalid and the rule has no filters, “all traffic which matches this rule MUST receive a 500 status code”.

**Second, the gateway.** If it answered, the gateway is fine:

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         2m1s
```

`PROGRAMMED True`, same address. The problem is behind it.

**Third, the route's conditions.** This is the decisive step, the equivalent of the `ENDPOINTS` column from Lesson 3:

```text
$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=False BackendNotFound

$ kubectl get httproute revisor -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].message}{"\n"}'
Failed to process route rule 0 backendRef 0: service default/revisr not found.
```

Two conditions, and here is the trap: `Accepted=True`. The gateway accepted the route. Whoever looks only at that condition, or only at `kubectl get httproute` (which shows none), concludes that everything is fine. The one that tells the truth is the second: `ResolvedRefs=False`, reason `BackendNotFound`. And the message leaves no doubt: `Failed to process route rule 0 backendRef 0: service default/revisr not found.` (`.status.parents[0]` is the route's status with respect to its first gateway; a route can attach to several, and each one puts its own conditions on it.)

**Fourth, the confirmation:**

```text
$ kubectl get service revisr
Error from server (NotFound): services "revisr" not found
[código de salida: 1]
```

**The fix** is the cause, not the gateway: apply the good file again, which here is the full kustomization.

```text
$ kubectl apply -k . | grep httproute
httproute.gateway.networking.k8s.io/revisor configured

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}
```

As in Lesson 3, you first check that the status is right (`ResolvedRefs=True`) and then you test. Between applying the route and Envoy receiving its new configuration a moment passes: if your first `curl` still gives the earlier code (`200` after the bad route, `500` after the good one), repeat it. `correr.sh` waits until the gateway answers the expected code before showing the `curl`, and notes it in the output as `(espera: la puerta ya contesta 500 …)` (“wait: the gateway already answers 500 …”).

**The order, for any entry point that does not respond well:**

1. What does `curl` return? A `curl` code (7, 28) is the network or the IP; an HTTP code (`404`, `500`) means the gateway answered.
2. Does the Gateway have an `ADDRESS` and `PROGRAMMED True`? If it has no address, look at MetalLB and its range.
3. Does the route have `Accepted=True` **and** `ResolvedRefs=True`? Read both, and the `message` of the one that is `False`.
4. If all of that is fine, go down one floor: the destination Service and its EndpointSlice, with the order from Lesson 3.

## The security habit of the lesson: expose the minimum, through a named entry point, and say what is missing

The course's habits table assigns three things to this lesson. They are checked with the cluster in front of you.

**What ended up exposed.** Everything that receives traffic from outside the cluster:

```text
$ kubectl get services -A -o custom-columns='ESPACIO:.metadata.namespace,NOMBRE:.metadata.name,TIPO:.spec.type,IP-EXTERNA:.status.loadBalancer.ingress[0].ip,NODEPORT:.spec.ports[*].nodePort' | grep -E 'ESPACIO|LoadBalancer|NodePort'
ESPACIO                NOMBRE                           TIPO           IP-EXTERNA       NODEPORT
default                revisor-publico                  LoadBalancer   172.18.255.200   30808
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   172.18.255.201   30581
```

Written as an inventory, which is how it should be possible to say it out loud:

| Entry point | Address | What it lets through | Who decides |
|---|---|---|---|
| `revisor-publico` | `172.18.255.200:80` | **all** of the `revisor`, without rules | nobody: it is a direct `LoadBalancer` |
| its `NodePort` | `30808` on **each** node | the same | nobody |
| the `revisor` Gateway | `172.18.255.201:80` | whatever the `HTTPRoute` says | the route, a versioned file |
| its `NodePort` | `30581` on each node | the same as the Gateway | the route |

Today there are **two** entry points to the same service, and that is a lesson in itself: the direct one skips any rule you put on the named one. Exercise 2 measures it: when the Gateway's route only lets `/salud` through, `.200` still hands over the full report. That is why “a named entry point” is the habit, and why Lesson 7 removes `revisor-publico` and leaves the Gateway as the only way in. The `NodePort`s are still there for the reason in 6.3.3; on a real cluster, the normal thing is for the nodes' network not to be reachable from outside, and for a firewall to ensure it.

**What did not end up exposed.** kind's nodes still publish nothing toward your machine, except the API port:

```text
$ docker port curso-k8s-l6-control-plane
6443/tcp -> 127.0.0.1:59736

$ docker port curso-k8s-l6-worker
```

And from your terminal, on the runs' Mac, the Gateway's IP does not exist:

```text
$ curl -s -m 3 http://172.18.255.201/salud
[código de salida: 28]
```

This `curl` did run in the Mac's terminal, not in the container. Code 28: it timed out. The `kind` network lives inside the Colima virtual machine, and the Mac has no route to it. On your Linux Mint it is different: Docker connects your machine to the `kind` network, so there `.201` should answer from your terminal. Another computer on your network does not reach it: with the rules Docker sets by default (since Docker Engine 28, which blocks direct-routing access to the containers' networks), the `kind` network is visible only from your own machine. But “your machine” includes all its users: on a shared machine, anyone with a session on it can ask `.200` or `.201`, or the `NodePort`s of the three nodes, for the report, and whoever has `root` can read the token that travels unencrypted (for example, by watching the Docker bridge with `tcpdump`). That is what this lab publishes: little, and only toward the inside of the machine, but it is not “nobody”.

**What is missing: encryption.**

```text
$ curl -s -m 5 https://172.18.255.201/salud
[código de salida: 7]

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados -H 'Authorization: Bearer token-inventado'
401
```

Over `https`, code 7: nobody is listening on 443, because the Gateway only has an `HTTP` *listener* on 80. And the second command recalls what travels through that entry point: the `revisor`'s token, in a header, **in plain text**. Anyone who can watch the network between the client and the gateway reads it. The `revisor` rejects the made-up token (`401`), but it can do nothing against someone who copied the real one. The missing component is a second *listener* on the Gateway, with `protocol: HTTPS`, port 443 and a `tls.certificateRefs` pointing to a `Secret` with the certificate. The `HTTPRoute` does not change. (`TLSRoute` and `BackendTLSPolicy`, from the list in 6.6.3, are other things: letting encryption pass through without opening it and encrypting the leg from the gateway to the Service.) This course does not add it because a real certificate needs a real domain name, which a lab on kind does not have. But it says so, which is the habit: **an entry point without encryption is published knowing that it lacks it**, and on a real cluster it is not published that way. Lesson 10 puts it on the list of what this is missing to be production-ready.

## Common mistakes

**Changing a Service to `NodePort` “so they can see it”.** It opens a random port on all the nodes, with no name and no rules. It is the scene's first proposal.

**Forgetting that every `LoadBalancer` is also a `NodePort`.** Even if the external IP never arrives, the node port is already open (6.3.3).

**Installing `ingress-nginx` because a tutorial says so.** No security patches since March 2026. And `Ingress`, the API, is frozen: new work is written with Gateway API.

**Running Cloud Provider KIND on a shared machine.** It watches all the kind clusters on the machine, not just yours.

**Applying the project before the platform, and “fixing it” by repeating the command until it passes.** It works sometimes and hides the cause. You install the platform, wait for the condition with `kubectl wait` and then apply the project.

**Waiting with `sleep`.** A number of seconds that is enough on your machine is not enough on another. You wait for the condition, with `--timeout`.

**Installing Envoy Gateway without `--server-side`.** Three of its CRDs do not fit in the usual `apply` annotation.

**Looking only at `Accepted` on a route.** `Accepted=True` with `ResolvedRefs=False` is an accepted route that leads nowhere. You read both conditions.

**Picking MetalLB's range at random.** It has to fall inside the `kind` network, far from the nodes' IPs, and must not be repeated in two live clusters at once.

**Leaving two entry points to the same service.** The one with no rules skips the other's rules (Exercise 2).

**Publishing over plain HTTP without saying so.** The token travels readable. If a lab cannot add encryption, it should at least write it down on its to-do list.

## Exercises

The first three are run on the lesson's cluster, in order and from the state it was left in after fixing the error. Before each exercise, `kubectl config current-context` must say `kind-curso-k8s-l6`. `correr.sh` runs them the same way, and its output is in `correr.salida.txt`. **Before** running each one, write in the [logbook](bitacora.md) what you think is going to happen. The fourth is written in your own words.

### Exercise 1 — Releasing an address and asking for it again

Delete the `revisor-publico` Service with `kubectl delete service revisor-publico`. Predict: what does `curl -s -m 3 http://172.18.255.200/salud` answer from the outside client? Which `LoadBalancer`s are left in the cluster? Now apply the kustomization again with `kubectl apply -k .`: which IP does the new Service receive, the `.200` that was freed or the `.202`, the next one that was never used? And its `NodePort`, is it the same as before? Check and explain.

### Exercise 2 — The entry point, reduced to the minimum

`fig06_02.solo-salud.yaml` is the same `HTTPRoute` with a narrower rule: only `GET` to `/salud`, exact.

```yaml
# fig06_02.solo-salud.yaml — Ejercicio 2: la ruta del revisor, reducida a lo
# mínimo. Solo deja pasar GET /salud, exacto. Pregunta: ¿qué responde la puerta a
# /api/estados, con token y sin token? Se deshace con apply -k . (gateway.yaml).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: Exact
        value: /salud
      method: GET
    backendRefs:
    - name: revisor
      port: 80
```

Apply it and predict the HTTP code of each of these five requests, all from the outside client: `GET /salud` through the Gateway; `GET /api/estados?formato=tabla` **with** the token, through the Gateway; `GET /salud/` (with a trailing slash) through the Gateway; `POST /salud` through the Gateway; and `GET /api/estados?formato=tabla` with the token, through `172.18.255.200`. Check it with `curl -s -o /dev/null -w '%{http_code}\n'`. Who answers each `404`: Envoy or the `revisor`? What does the last answer say about having two entry points? When you finish, apply `kubectl apply -k .` again.

### Exercise 3 — An `Ingress` that nobody serves

`fig06_03.ingress.yaml` is an `Ingress` that sends everything to the `revisor` Service, like the route in 6.7:

```yaml
# fig06_03.ingress.yaml — Ejercicio 3: un Ingress, la API congelada. El clúster
# lo acepta (la API existe desde siempre), pero en este clúster no hay ningún
# controlador de Ingress. Pregunta: ¿qué dirección recibe? ¿Quién la atiende?
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: revisor
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: revisor
            port:
              name: http
```

Before applying it, run `kubectl get ingressclass`. Predict: does the cluster accept the `Ingress` or reject it as it rejected the `Gateway` in 6.2? If it accepts it, what address will it have after 15 seconds? Apply it, check it with `kubectl get ingress revisor` and with `kubectl describe ingress revisor`, and explain the difference from 6.2 in two sentences. Delete it when you finish.

### Exercise 4 — Defend the decision

A colleague tells you: “kind's guide recommends Cloud Provider KIND, it is a single binary and it gives you LoadBalancer, Ingress and Gateway API without installing anything in the cluster. Why all that MetalLB and Envoy Gateway?”. In five sentences at most, answer them: where Cloud Provider KIND runs, which clusters it acts on, what would happen on a shared machine, what price the course's solution pays and how that price is controlled.

## Solutions

### Solution 1

Measured in `correr.salida.txt`:

```text
$ kubectl delete service revisor-publico
service "revisor-publico" deleted from default namespace

$ curl -s -m 3 http://172.18.255.200/salud
[código de salida: 28]

$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       2m18s

$ kubectl apply -k . | grep revisor-publico
service/revisor-publico created

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.129.166   172.18.255.200   80:31622/TCP   5s

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

**Without the Service, `curl` does not connect**: it exits with 28 (timed out) or, depending on your system, with 7 (could not connect; on Linux, “No route to host” when the ARP question goes unanswered). Both say the same thing: nobody answers for `172.18.255.200`. There is nobody to reject it with an HTTP response, because no `speaker` announces that IP any more, the ARP question goes unanswered and the packet has nowhere to go. When the Service was deleted, MetalLB **released** the address. A single `LoadBalancer` is left, the Gateway's, which noticed nothing: it is still on `.201`.

**The new Service receives `.200` again**, not `.202`. MetalLB hands out the first free one in its range, and `.200` was free again. But it is a new object: another `CLUSTER-IP` (`10.96.129.166` instead of `10.96.115.79`) and **another `NodePort`** (`31622` instead of `30808`). The external IP came out the same because that is how MetalLB's allocation works, not because Kubernetes remembers it. If between the deletion and the creation another Service had asked for an IP, it would have kept `.200`, and your Service would have gotten another. That is why, if an external IP has to be fixed (because it is in a DNS or in a firewall's configuration), it is requested in writing in the Service, with the annotation `metallb.io/loadBalancerIPs: 172.18.255.200` (the [MetalLB usage guide](https://metallb.io/usage/) prefers it over `spec.loadBalancerIP`, which is on its way to being deprecated), and you do not trust the luck of the order.

### Solution 2

Measured in `correr.salida.txt`:

```text
$ kubectl apply -f fig06_02.solo-salud.yaml
httproute.gateway.networking.k8s.io/revisor configured

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud
200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud/
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -X POST http://172.18.255.201/salud
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
200
```

**`200`, `404`, `404`, `404` and `200`.** Only exactly `GET /salud` gets through the Gateway. `/api/estados` matches no rule, not even with a token: the token does not even reach the `revisor`, because **Envoy** answers `404` first. `/salud/` does not either, because `Exact` is exact: an extra slash is another path. And `POST /salud` does not match because of the method. The three `404`s come from the gateway: no rule takes those requests to the `revisor`, so Envoy answers on its own.

**The fifth is the one that matters:** through `172.18.255.200`, the direct `LoadBalancer`, the full report comes out, `200`. The rule you have just put on the named entry point protects nothing as long as another entry point without rules exists. It is Lesson 7's argument for removing `revisor-publico`: reducing what is exposed only works if there is **one** single way in.

When the kustomization is applied again, the route goes back to `PathPrefix /` and `/api/estados` without a token gives `401` again, this time from the `revisor`.

### Solution 3

Measured in `correr.salida.txt`:

```text
$ kubectl get ingressclass
No resources found

$ kubectl apply -f fig06_03.ingress.yaml
ingress.networking.k8s.io/revisor created

$ kubectl get ingress revisor
NAME      CLASS    HOSTS   ADDRESS   PORTS   AGE
revisor   <none>   *                 80      16s

$ kubectl describe ingress revisor | grep -E '^(Ingress Class|Address|Events):'
Address:          
Ingress Class:    <none>
Events:       <none>

$ kubectl delete -f fig06_03.ingress.yaml
ingress.networking.k8s.io "revisor" deleted from default namespace
```

**The cluster accepts it, and nobody serves it.** Unlike `Gateway` in 6.2, the `Ingress` type comes inside Kubernetes, in the `networking.k8s.io` group: no CRD is needed to create it. But an `Ingress` is a declaration, just like a `Gateway`, and without a controller to read it nothing happens: there is no `IngressClass` (`No resources found`), the `CLASS` column says `<none>`, `ADDRESS` is empty and there is not a single event. It is the `<pending>` of 6.3 with another face: no error, no result. Envoy Gateway, the controller that is installed, serves Gateway API and not this `Ingress`. The two sentences: “`Gateway` did not exist as a type and the cluster rejected it; `Ingress` exists as a type and the cluster stored it, but nobody turns it into an entry point. An accepted object is not a served object.”

### Solution 4

One possible answer: “Cloud Provider KIND runs as a program on your machine, outside the clusters, with permissions to open ports and talk to Docker. Its own README says it monitors all your kind clusters, and it does not describe an option to limit itself to one; besides, its Gateway API controller is enabled. On a shared machine, the program I launched for my lesson would touch other people's clusters without them having asked for it. MetalLB and Envoy Gateway live inside my cluster and are deleted with it; the price is that MetalLB's IP range comes from the kind network, which is shared. That price is controlled by checking, before creating the cluster, that nobody already answers on the first IP of the range, and by running only one cluster with MetalLB at a time.”

## Deleting the cluster

When you finish the exercises, delete the lesson's cluster. With it go MetalLB, Envoy Gateway, their CRDs and their IPs:

```text
$ kind delete cluster --name curso-k8s-l6
Deleting cluster "curso-k8s-l6" ...
Deleted nodes: ["curso-k8s-l6-control-plane" "curso-k8s-l6-worker" "curso-k8s-l6-worker2"]

$ kind get clusters | grep -c curso-k8s-l6
0
```

Then delete `token.txt` and the `kubeconfig`'s temporary folder, which holds the administrator credential of the cluster you have just deleted. The `rm -rf` is dangerous if the variable is empty or points elsewhere, so it is protected with a `case` that only lets it run if the path is the one `mktemp` created in 6.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 6.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l6.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt
```

Closing the terminal stops using that `kubeconfig`, but does not delete it: without the `case`, the credential would stay in `/tmp`. Also check that no client container was left: `docker ps -a --filter name=curso-k8s-l6` must show nothing. From this moment, `172.18.255.200` is free again for the next cluster that needs it.

## How I know I got it

- [ ] You explain why `revisor-publico` stayed at `<pending>` and show with `curl` against a node's IP that its `NodePort` was already open.
- [ ] You install MetalLB, give it the range `172.18.255.200-172.18.255.220` and read in the Service's events who assigned the IP (`IPAllocated`) and from which node it is announced (`nodeAssigned`).
- [ ] Faced with `no matches for kind … ensure CRDs are installed first` you say what is missing (a CRD), and faced with `failed calling webhook … connection refused` you say what to wait for (the controller that answers the *webhook*).
- [ ] You write the three steps from memory: platform, `kubectl wait`, project; and you explain why a `sleep` is not a wait.
- [ ] You explain what `GatewayClass`, `Gateway` and `HTTPRoute` are, which role each one corresponds to, and who creates the `envoy-default-revisor-…` Pod.
- [ ] Faced with a `500` from the gateway, you check the Gateway, the route's two conditions and the `message`, and find a `BackendNotFound`.
- [ ] You make the inventory of what is exposed (the two IPs, the two `NodePort`s, 6443 on `127.0.0.1`) and say what is missing: encryption.
- [ ] You explain in one sentence each: why not Cloud Provider KIND, what it means that `Ingress` is frozen, and why not `ingress-nginx`.
- [ ] You run `programas/06-entrar-al-cluster/correr.sh > /tmp/mi-corrida-l6.txt 2>&1` and compare against `correr.salida.txt` (do not redirect to that file: it is the reference) what does not change between runs: three `Ready` nodes on `v1.37.0`; the `172.18.0.0/16` network; `No resources found` for the CRDs; seven `created` and the two `no matches for kind` for `Gateway` and `HTTPRoute`; `revisor-publico` at `<pending>` and `/salud` through the `NodePort` of two nodes; the `failed calling webhook … connection refused` of the first attempt with the range (it may not appear for you if your machine is faster than MetalLB's startup, and that teaches something too); nine `metallb.io` CRDs; `ipaddresspool.metallb.io/curso created` on the second attempt; one `controller` and three `speaker`s; **`172.18.255.200`** on `revisor-publico`, with `IPAllocated` and `nodeAssigned … layer2`; `3` `Too long` lines and the `262144 bytes` cap; `10` Gateway API CRDs and `8` Envoy Gateway ones; the `eg` `GatewayClass` with `ACCEPTED True` and ten types in `api-resources`; seven `unchanged` and two `created`; the Gateway at **`172.18.255.201`** with `PROGRAMMED True`; `Accepted=True` and `ResolvedRefs=True`; an `envoy-default-revisor-…` Pod with `2/2`; `/salud` and the table through the gateway, and `401` without a token; with the bad route, `ResolvedRefs=False BackendNotFound`, `service default/revisr not found` and `HTTP/1.1 500`; code 7 over `https`; in Exercise 1, a `curl` code (28 or 7) and `.200` back; in Exercise 2, `200 404 404 404 200`; in Exercise 3, an empty `Address`; and at the end `sin diferencias con los archivos` (“no differences from the files”). The IPs of Pods, Services and nodes, the `NodePort`s, the suffixes, the ages, the node that announces the IP, the order of the `kind load` lines and the number of times each `rollout status` line repeats change on every run: they are observed, not compared.
- [ ] From a freshly created cluster, with not a single custom resource, you run `./levantar.sh` and it reaches `Programmed` without an error and without fixing anything by hand; and you say why the range and the class go in step 3.
- [ ] You read the output of `kubectl get crd` in 6.6.2 and say three things: that the Gateway API CRDs are from the `experimental` channel, that there are three more from `x-k8s.io`, and that Envoy's *webhook* is `Ignore` and MetalLB's are `Fail`.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l6`, the `kubeconfig`'s temporary folder no longer exists in `/tmp`, and nobody answers on `172.18.255.200`.

## Summary

Answer without looking at the lesson:

1. Why does a `LoadBalancer` stay at `<pending>` on kind? What does it open even if it stays that way?
2. What do MetalLB's `controller` and `speaker` do, and what does “layer 2” mean?
3. Why does MetalLB's range come from the `kind` network, and why from the end of it?
4. What is a CRD, and what error does applying an object whose CRD does not exist give?
5. What is an admission *webhook*, and what does the `kube-apiserver` do when it cannot call it, according to its `failurePolicy`? What value do MetalLB's have and what value does Envoy Gateway's mutating one have?
6. What are the three steps for bringing up platform and project, and what exactly does each `kubectl wait` in this lesson wait for?
7. Why is Envoy Gateway installed with `--server-side`?
8. What role does each of Gateway API's three components have, and who creates the Pod that actually receives the requests?
9. What is the difference between `Ingress`, `ingress-nginx` and Gateway API, and what status is each one in?
10. What is exposed at the end of this lesson, and what does the entry point lack?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, “Service”](https://kubernetes.io/docs/concepts/services-networking/service/): the `LoadBalancer` type, provisioned asynchronously by the cloud provider and published in `.status.loadBalancer`; its implementation on top of a `NodePort`; `allocateLoadBalancerNodePorts` and its default value `true`.
- [Kubernetes, “Gateway API”](https://kubernetes.io/docs/concepts/services-networking/gateway/): Gateway API as an add-on defined with custom resources; `GatewayClass`, `Gateway` and `HTTPRoute`; the role-oriented design.
- [Kubernetes, “Ingress”](https://kubernetes.io/docs/concepts/services-networking/ingress/): the frozen Ingress API, with no plans to remove it; the recommendation to use Gateway.
- [Kubernetes, blog, “Ingress NGINX Retirement: What You Need to Know”](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) (November 11, 2025): the end of maintenance in March 2026, with no releases, fixes or security patches afterwards; existing installations keep working; the recommendation to migrate to Gateway API.
- [Kubernetes, “Custom Resources”](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/): what a custom resource is and what a `CustomResourceDefinition` creates.
- [Kubernetes, “Dynamic Admission Control”](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): what admission *webhooks* are, validating and mutating; `failurePolicy` with `Fail` by default.
- [Kubernetes, “Deployments”](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): the `Available` condition as minimum availability according to the update strategy.
- [Gateway API, “ReferenceGrant”](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): the permission for cross-namespace references; the route-to-Gateway binding across namespaces is decided in the *listeners* (`allowedRoutes`).
- [MetalLB, “Usage”](https://metallb.io/usage/): the `metallb.io/loadBalancerIPs` annotation for requesting a specific IP.
- [Docker, “Docker Engine 28: hardening container networking by default”](https://www.docker.com/blog/docker-engine-28-hardening-container-networking-by-default/) and [“Port publishing and mapping”](https://docs.docker.com/engine/network/port-publishing/): why another machine on your network does not reach the containers' network.
- [Kubernetes, “kubectl wait”](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): waiting for a condition in the `Status` of one or more resources; the `--for` flag.
- [Kubernetes, “Server-Side Apply”](https://kubernetes.io/docs/reference/using-api/server-side-apply/): the control plane keeps track of which fields each party manages; the comparison with the `last-applied-configuration` annotation.
- [kind, “LoadBalancer”](https://kind.sigs.k8s.io/docs/user/loadbalancer/): Cloud Provider KIND as a standalone binary on your machine, with privileges to open ports and talk to the container runtime.
- [kind, “Ingress”](https://kind.sigs.k8s.io/docs/user/ingress/): native Ingress and Gateway API support in Cloud Provider KIND.
- [Cloud Provider KIND, README](https://github.com/kubernetes-sigs/cloud-provider-kind): it monitors all kind clusters; its Gateway API controller is enabled by default.
- [MetalLB, “Installation”](https://metallb.io/installation/): the `metallb-native.yaml` manifest of v0.16.1; the `controller` and the `speaker`; the components idle until they are configured.
- [MetalLB, “Configuration”](https://metallb.io/configuration/): `IPAddressPool`, `L2Advertisement` and their association; layer 2 responding to ARP.
- [Envoy Gateway, “Install with Kubernetes YAML”](https://gateway.envoyproxy.io/docs/install/install-yaml/): `kubectl apply --server-side` with the v1.9.2 `install.yaml`; the manifest brings the Gateway API CRDs and Envoy Gateway's.
- [Gateway API, “HTTPRoute”](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/): without `matches`, the `/` prefix matches every request; each `match` is independent.
- [Gateway API, v1.6 specification](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/): a rule's invalid references and the mandatory 500 code.
- [curl, “libcurl error codes”](https://curl.se/libcurl/c/libcurl-errors.html): codes 7 and 28.

---

**Next:** [Lesson 7 — Isolating: namespaces, permissions and network](07-aislar-permisos-red.md)
