# Lesson 3 — Services and DNS

Tuesday, 10:20 in the morning. At 11:00 the operations team reviews the dashboard and wants to see the `revisor`'s report green. Yesterday, to get by, a colleague copied the IP of a test-service Pod, `10.244.1.3`, and pasted it into the list of services the `revisor` checks. It worked all afternoon. This morning the report says `FALLA` on every row, and nobody touched anything. Or so they think: during the night someone restarted the Pods to apply a change, the Pods were reborn, and none came back with yesterday's IP. The address your colleague pasted now belongs to nobody, or worse, to another Pod that has nothing to do with it. Forty minutes are left and the question is not which IP to paste now, but how to stop pasting IPs.

Kubernetes already solved that problem, and the solution has two components: a **Service**, which is a name and an address that do not change even though the Pods behind it change all the time, and the **cluster DNS**, which turns that name into that address for any Pod that asks. This lesson teaches you to write the first, to interrogate the second, and to read what happens when a Service finds nobody to send traffic to.

**Time:** 2 × 45 min

**What you build:** the `revisor` findable by name inside the cluster, and its companion, the test service, findable too, so that the report finally checks someone real

**What you learn:** what a `ClusterIP` Service is and why it is the default type; how a label selector decides which Pods traffic reaches and where that decision is written down (`EndpointSlice`); the chain of three ports, `port`, `targetPort`, and `containerPort`; how the cluster DNS resolves names and why a bare `revisor` works; `kubectl port-forward` to `127.0.0.1`; and a debug Pod for looking from inside when the image has no *shell*

**Where you are coming from.** From [Lesson 2](02-pods-deployments.md): the `revisor` runs with three replicas in a Deployment, with its complete `securityContext` and an `emptyDir` at `/datos`. You know that each Pod has its IP and that this IP changes every time the Pod is reborn, and you saw that the `revisor` image has neither *shell* nor `curl`. From [Lesson 0](00-que-es-kubernetes.md) you bring two names that until now were just names: `kube-proxy`, of which there is one per node, and `coredns`, which runs on the control-plane node. In this lesson both get to work.

**What this lesson does not do.** The `revisor` ends up findable **inside** the cluster and, for you, through a temporary tunnel (`port-forward`). It is not published to the outside: a `LoadBalancer` and an entry point with the Gateway API are [Lesson 6](06-entrar-al-cluster.md). Nor is it settled yet who can talk to whom: today any Pod in the cluster reaches the `revisor`, and [Lesson 7](07-aislar-permisos-red.md) puts the network in default-deny. And the Service sends traffic to any Pod that is running, healthy or not: telling the cluster when a Pod is ready to receive traffic is the job of the probes in [Lesson 5](05-salud-recursos-apagado.md).

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1, and the node image `kindest/node:v1.37.0` pinned by its digest, in the three-node cluster from Lesson 1, here called `curso-k8s-l3`. The machine was a Mac with an ARM processor and Docker Engine 29.2.1 inside a Linux virtual machine (Colima), **not** Linux Mint, which is the course's reference system. What changes on your Mint: the architecture (`amd64` instead of `arm64`), the IP addresses of Pods and Services, the random suffixes in names, the ages, which node each replica lands on, the port Docker gives the control-plane node, and how many requests go to each replica in 3.8. The commands are the same. The complete walkthrough is in [`programas/03-services-dns/`](../programas/03-services-dns): `correr.sh` creates the cluster, loads the images into it, leaves the `revisor` as Lesson 2 left it, walks through the lesson in order, runs Exercises 1 to 3, and deletes the cluster; it took 2 minutes and 16 seconds (the last line of the output says so: `la corrida completa tardó 136 s`), of which creating the cluster and waiting for it to be ready was 46 seconds. Its output is `correr.salida.txt`. In it, the security habit section appears before the error one, because the script runs them in that order. The `port-forward` uses port `18080` of your machine; if you have it taken, the script stops before creating anything and tells you how to choose another (`PUERTO_LOCAL=18081 ./correr.sh …`). On the machine where this lesson was written, the clusters of other lessons were running at the same time, and so as not to collide with them the script was run with `PUERTO_LOCAL=18300`; in `correr.salida.txt` and in this lesson the number was rewritten to `18080`, the one you will use. It is the only thing that was touched in the output.

## By the end you will be able to

- Explain with an example why no program should store a Pod's IP, and what a Service gives in exchange.
- Write from memory a `ClusterIP` Service with its `selector` and its list of `ports`, and follow the `port` → `targetPort` → `containerPort` chain in a concrete case.
- Find a Service's `EndpointSlice` with `-l kubernetes.io/service-name=…` and say, with it in hand, which Pods traffic reaches.
- Resolve a Service's name from a debug Pod and explain each line of its `/etc/resolv.conf`, including the `NXDOMAIN`s that `nslookup` prints.
- Open a `port-forward` that listens only on `127.0.0.1` and say when it breaks.
- Provoke a Service without endpoints, recognize it by `<unset>` and by `curl`'s code 7, and fix it.

## The why before the how

In Lesson 2 you left three replicas of the `revisor` running, and section 2.4 ended with a warning: each Pod has its IP, and that IP changes every time the Pod is reborn. It is Tuesday's scene. A Pod is disposable by design. The ReplicaSet replaces it when it dies, and the replacement is **another** Pod, with another name and another address. If clients store a Pod's address, every replacement leaves them talking to nobody.

There is a second reason, and it is subtler. Even if Pods never died, you have **three**. Which one does the client talk to? If it picks one, the other two are idle. If you want it to spread the load, you would have to give the client the complete list and keep it up to date. That is what Compose did in the Docker course, in a hidden way: a service name that Compose's network resolved to its containers. In Kubernetes, the same idea has its own name and its own manifest.

A **Service** answers both questions at once. It gives you a virtual IP that does not change as long as the Service exists, and behind it, the live list of Pods that serve it. You do not write the list: a controller writes it, from a rule that you do write, the **selector**. And so that nobody has to remember that virtual IP, the **cluster DNS** gives it a name: `revisor`, or with its full name, `revisor.default.svc.cluster.local`.

The lesson has nine concept parts and then the usual sections:

1. **A Pod's IP is no good as an address** (3.1): what changes when a Pod is reborn.
2. **The `revisor`'s Service** (3.2), field by field.
3. **The three ports** (3.3): `port`, `targetPort`, and `containerPort`.
4. **Selectors and `EndpointSlice`** (3.4): where the list of Pods is written down.
5. **A debug Pod** (3.5), because the `revisor` has no *shell*.
6. **The cluster DNS** (3.6).
7. **The test service** (3.7): the `revisor` finally checks someone.
8. **How a Service spreads load** (3.8).
9. **`port-forward`** (3.9): a tunnel from your machine, only to `127.0.0.1`.

This is the destination. At the end of 3.7, any Pod in the cluster asks the `revisor` for the report by its name, and the `revisor` finds the test service by its name too:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

## If you do not have the image from the Docker course

This lesson uses two images from the Docker course: the `revisor`'s, `curso-docker-revisor:1.6.0`, delivered by its Lesson 10, and that of the service that fails on purpose, `curso-docker-prueba:1.0.0`. Before continuing, check that you have both:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

For the other one, the same command with `curso-docker-prueba:1.0.0`. If you are missing the `revisor`'s, build it from that course's repository, with the `Dockerfile` from its Lesson 10 over the `programas/revisor` folder and with `--build-arg VERSION=1.6.0`, tagging it exactly `curso-docker-revisor:1.6.0`. If you are missing the test one, build it from the `programas/servicio-prueba` folder of that same repository, tagged `curso-docker-prueba:1.0.0`. [Lesson 2](02-pods-deployments.md) carries, in this same section, the list of what the course asks of an image of your own if you prefer to use another.

What this lesson asks **in addition** of the test service, worth reading because each point explains a line of its manifest:

- **It listens for HTTP on port 9000** and answers `GET /` with `200` when it is healthy, with `503` when it is down, and late when it is slow.
- **It switches mode with `POST /modo/sano`, `POST /modo/lento`, and `POST /modo/caido`**, and says which mode it is in with `GET /modo`. That way you can break it from outside without rebuilding anything.
- **It runs as user 65532**, without `root`, and **it withstands a read-only file system** without a volume: it writes nothing to disk.

And both are loaded into the cluster as in Lesson 2, with `kind load docker-image` and the cluster name. Both can be loaded in a single command:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l3
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker2", loading...
```

Six lines: two images times three nodes. (In your run the order of the lines may be different.) The debug Pod in 3.5 uses a third image, `curlimages/curl`, which is **not** loaded: it is public, it is pinned by its `sha256` digest, and the node where the Pod lands downloads it from Docker Hub the first time. You need internet for that step.

## The concepts

### 3.1 A Pod's IP is no good as an address

This lesson uses its own cluster, `curso-k8s-l3`, with the three-node configuration from Lesson 1, freshly created. Create it like this, from the root of the course repository, with the same care you learned in Lesson 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l3.XXXX)/kubeconfig"
# curso-k8s-l3 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l3 --config programas/03-services-dns/kind-curso.yaml
# Debe decir kind-curso-k8s-l3. Si dice otra cosa, no sigas.
kubectl config current-context
```

The `export` only holds in that terminal. If you open another one (in 3.9 you will want one for the `port-forward`), repeat the `export` with the same path, or `kubectl` will talk to another cluster. Then load the two images, as seen above, and apply the Lesson 2 Deployment as is, without changing a comma; from here on the commands are run inside `programas/03-services-dns/` (enter with `cd programas/03-services-dns`, or `kubectl apply -f revisor-deployment.yaml` will say the path does not exist). The outputs are from the run of `correr.sh`, which does exactly this:

```text
$ kubectl config current-context
kind-curso-k8s-l3

$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-82d87   1/1     Running   0          1s    10.244.1.2   curso-k8s-l3-worker2   <none>           <none>
revisor-697fb84f97-drv5h   1/1     Running   0          1s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          1s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
```

The first command is the usual habit: before changing anything, ask which cluster you are talking to. Repeat it **before every** `apply`, `delete`, `rollout restart`, or `port-forward` in the lesson, not just here; the script does it on its own, before each `kubectl`, and stops if the answer is not `kind-curso-k8s-l3`. Now look at the `IP` column. The three addresses start with `10.244.`: it is the Pod network that kind sets up by default. Its [configuration guide](https://kind.sigs.k8s.io/docs/user/configuration/) puts it this way: "by default, kind uses `10.244.0.0/16` as the pod subnet for IPv4". Each node receives a piece of that network: in this run, the Pods of `worker2` are in `10.244.1.x` and those of `worker` in `10.244.2.x` (which piece goes to each node changes from one run to another).

Now Tuesday's scene, in miniature. One is deleted:

```text
$ kubectl delete pod revisor-697fb84f97-82d87
pod "revisor-697fb84f97-82d87" deleted from default namespace

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-drv5h   1/1     Running   0          2s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          2s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-z79jh   1/1     Running   0          1s    10.244.1.3   curso-k8s-l3-worker2   <none>           <none>
```

The ReplicaSet replaced it within a second, as in Lesson 2 (if you list the Pods right after deleting, you may see the old one in `Terminating` and the new one in `ContainerCreating`; wait a few seconds or run `kubectl rollout status deployment/revisor`, and there will be three). But the new Pod, `z79jh`, is not the one that died: another name and another IP (`10.244.1.3` instead of `10.244.1.2`). Notice that it landed on the **same** node, `worker2`, and the address changed anyway: the Pod does not need to move for its IP to be different. On another run it may also land on another node. The address `10.244.1.2` now belongs to nobody. If a program had it stored, from this second on it is talking to an empty address. And if a while from now another Pod is born on `worker2`, it may receive exactly that address, and the program would be talking to a stranger without realizing it.

It is not a defect of kind or of this cluster: it is the design. Pods are, in the words of the [Pods documentation](https://kubernetes.io/docs/concepts/workloads/pods/), "relatively ephemeral, disposable entities". What has to be stable is not the Pod, it is the **access** to the set of Pods. That is a Service.

### 3.2 The `revisor`'s Service

The [Services documentation](https://kubernetes.io/docs/concepts/services-networking/service/) defines it in one sentence: a Service is "a method for exposing a network application that is running as one or more Pods in your cluster". And it specifies what it stores: each Service "defines a logical set of endpoints (usually these endpoints are Pods) along with a policy about how to make those pods accessible".

This is the `revisor`'s. It is a **program**: it applies on its own and lives in `programas/03-services-dns/revisor-service.yaml`.

```yaml
# revisor-service.yaml — Lección 3: un nombre estable para las réplicas del revisor.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

It is much shorter than the Deployment, and it reads the same way, from the outside in.

#### 3.2.1 What it is and what it is called

`apiVersion: v1` and `kind: Service`: Services live in the API's core group, the same as Pods, which carries no name. `metadata.name: revisor` is the Service's name, and it is no minor detail: **that name is what you will write in URLs**. The cluster DNS (3.6) turns it into an address. That is why the Service is called the same as the Deployment, although it does not have to be: the Deployment is called `revisor` for you, and the Service is called `revisor` for the clients. The Service's own `app: revisor` label is, as in the Deployment, so you can find it with `-l app=revisor`; it decides nothing about traffic.

#### 3.2.2 What type of Service

`type: ClusterIP` says what kind of address it receives. The Services documentation describes this type like this: "exposes the Service on a cluster-internal IP. Choosing this value makes the Service only reachable from within the cluster. This is the default that is used if you don't explicitly specify a `type`". The manifest writes it even though it is the default value, for the same reason Lesson 2 wrote `IfNotPresent`: so that whoever reads it does not have to know the rule, and so that the decision **not** to publish stays in plain view. The same page says how something is published to the internet: "with an Ingress or a Gateway". That is Lesson 6. Today, on purpose, nothing goes out.

#### 3.2.3 Who it sends traffic to

`selector: {app: revisor}` is the rule: "my Pods are the ones that carry the label `app: revisor`". It is the same label the Deployment puts in its template, and that is why the Service finds the three replicas. Notice what it does **not** say: it does not mention the Deployment, or the ReplicaSet, or the `pod-template-hash`. The Service does not know a Deployment exists. It chooses Pods by label and nothing else. Exercise 2 shows you the consequence, the one Lesson 2 left announced for you.

#### 3.2.4 Through which port

`ports` is a list; here it carries a single port, named `http`. `port: 80` is the **Service's** port: the one clients use. `targetPort: http` is the **Pod's** port that traffic is forwarded to, and it is given not as a number but by **name**. Section 3.3 follows this chain with the cluster in front of you.

#### 3.2.5 Applying it and looking at it

```text
$ kubectl apply -f revisor-service.yaml
service/revisor created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   41s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP    2s
```

Two Services. Yours, `revisor`, received the IP `10.96.144.175`. It is from another network, `10.96.`, different from the Pods': the kind guide says that, by default, it uses "`10.96.0.0/16` as the service subnet for IPv4". The other, `kubernetes`, you did not create: it is the `kube-apiserver`'s own Service, at the first address of that network, so that Pods that need to talk to the API find it by name like any other. `EXTERNAL-IP <none>`: there is no address to the outside, as requested.

`kubectl describe` gathers everything about the Service:

```text
$ kubectl describe service revisor
Name:                     revisor
Namespace:                default
Labels:                   app=revisor
Annotations:              <none>
Selector:                 app=revisor
Type:                     ClusterIP
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.96.144.175
IPs:                      10.96.144.175
Port:                     http  80/TCP
TargetPort:               http/TCP
Endpoints:                10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

The lines that matter today:

- `Selector: app=revisor`: the rule you wrote.
- `IP: 10.96.144.175`: the stable address. The documentation calls it the *cluster IP* and explains that it is "used by the virtual IP address mechanism". It belongs to no machine and no Pod; 3.8 tells who makes it work.
- `Port: http 80/TCP` and `TargetPort: http/TCP`: the two ends of the port chain.
- `Endpoints: 10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080`: **the three replicas**, with their IP and their real port. Compare them with the second table in 3.1: they are exactly those of the three live Pods, including the `10.244.1.3` of the Pod that was just born. The `10.244.1.2` of the deleted Pod does not appear. Nobody removed it by hand.
- `Session Affinity: None`: each connection can go to any replica; 3.8 measures it.

That `Endpoints` list is the answer to the scene: the client uses `10.96.144.175`, which does not change, and the cluster keeps up to date who it really corresponds to.

### 3.3 The three ports

In the Docker scene there was one port that mattered: the `-p 8080:8080` of `docker run`. Here there are three, and each is declared by a different object. Confusing them is among the most common mistakes when starting out, so it is worth following them with the cluster in front of you.

```text
$ kubectl get service revisor -o jsonpath='port={.spec.ports[0].port} targetPort={.spec.ports[0].targetPort}{"\n"}'
port=80 targetPort=http

$ kubectl get pods -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].ports[0].name}={.spec.containers[0].ports[0].containerPort}{"\n"}{end}'
revisor-697fb84f97-drv5h http=8080
revisor-697fb84f97-nq74v http=8080
revisor-697fb84f97-z79jh http=8080

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].ports}{"\n"}'
[{"name":"http","port":8080,"protocol":"TCP"}]
```

(The second `jsonpath` uses `{range .items[*]}…{end}`, which repeats what is in the middle for each Pod in the list. It is the way to ask for a value from several objects at once.)

This is how the chain reads, from the client to the program:

| Port | Where it is declared | Value in the `revisor` | Who uses it |
|---|---|---|---|
| `port` | the Service | `80` | the client: `http://revisor/…` goes to 80, HTTP's default port |
| `targetPort` | the Service | `http` (a name) | the cluster, to know which Pod port to forward to |
| `containerPort` | the Pod template, with its name | `http` = `8080` | whoever looks up the name `http` in the Pod; the program listens on 8080 on its own |

The third command shows how the name was resolved: the `EndpointSlice` (3.4) already carries the number, `8080`, which it took from the Pods. The Services documentation describes the two components that make this possible. The first: "a Service can map any incoming `port` to a `targetPort`. By default and for convenience, the `targetPort` is set to the same value as the `port` field". The second: "port definitions in Pods have names, and you can reference these names in the `targetPort` attribute of a Service".

Why does the course use the name and not the number? Because that way the number lives in **a single place**, the Pod template. If one day the `revisor` listens on another port, you change `containerPort` in the Deployment and the Service keeps working without touching it. With `targetPort: 8080`, you would have to remember to change two files, and the day you forget one, the Service sends traffic to a port where nobody is listening. Exercise 1 teaches you exactly what that looks like.

A clarification that avoids a frequent confusion: Lesson 2 said that `containerPort` **publishes nothing**. That is still true. The program listens on 8080 even if you do not declare it. Declaring it with a name serves so the Service can point to it by that name, and so whoever reads the manifest knows where it listens.

And the Service's 80? It is not opened by the `revisor` or by any other process: it is part of the Service's virtual address. The program keeps listening on its 8080, with all the restrictions from Lesson 2, and the cluster translates. That way clients write `http://revisor/` without a number, and nobody had to change the program's port to achieve it.

### 3.4 Selectors and `EndpointSlice`

#### 3.4.1 Where the list is written down

The `Endpoints` list that `describe` showed is not stored in the Service. It lives in another object, an **EndpointSlice**. The [EndpointSlices documentation](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) sums it up: "EndpointSlices track the IP addresses of the endpoints of a backend. They are typically associated with a Service, and the endpoints are usually Pods".

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.2.3,10.244.1.3   3s
```

Notice how it was looked up: not by name (`revisor-6jh2f` carries a random suffix, like a Pod), but by the label `kubernetes.io/service-name=revisor`. The same page explains why that label exists: each EndpointSlice carries a reference to its owner and "a `kubernetes.io/service-name` label that enables simple lookups of all EndpointSlices belonging to a Service". It is the same idea as in Lesson 2: you search by label, never by a name that changes.

Why "all"? Because a Service can have several. The documentation says that, by default, the control plane creates EndpointSlices "with no more than 100 endpoints each". With three replicas everything fits in one; with three hundred there would be at least three. That is why the table above is a list, even though today it has a single row.

With `jsonpath` each *endpoint* is seen from the inside, and its owner:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.2.3 revisor-697fb84f97-drv5h curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{"\n"}'
Service/revisor
```

Each line says which address, of which Pod (`targetRef`), on which node, and whether it is ready. And the EndpointSlice's owner is the Service, with the same `ownerReferences` field from Lesson 2. It is the same chain of owners: if you delete the Service, its EndpointSlice goes with it.

#### 3.4.2 Who writes it

Nobody writes it by hand. The Services debugging documentation tells it this way: "inside Kubernetes there is a control loop that evaluates the selector of every Service and saves the results into one or more EndpointSlice objects" (["Debug Services"](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)). It is Lesson 0's thermostat again, with another desired state: "this Service sends traffic to the Pods that match its selector". When the set of Pods changes, the controller corrects the list.

It can be seen by deleting another Pod:

```text
$ kubectl delete pod revisor-697fb84f97-drv5h
pod "revisor-697fb84f97-drv5h" deleted from default namespace

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true
10.244.1.4 revisor-697fb84f97-mjbff curso-k8s-l3-worker2 ready=true
```

The Pod `drv5h` and its `10.244.2.3` left the list, and the new Pod, `mjbff`, came in with `10.244.1.4`. Same EndpointSlice, new content. The Service did not change at all: its IP is still `10.96.144.175`. That is the whole idea.

#### 3.4.3 What `ready=true` means

The `ready` column is the one that decides whether an *endpoint* receives traffic. The EndpointSlices documentation says the `serving` condition indicates the *endpoint* is serving and that, for a Pod, it "corresponds to the Pod's `Ready` condition"; and that `ready` is, in essence, "`serving` and not `terminating`". Translated: a Pod receives traffic while it is ready and is not shutting down.

Today, "ready" means little: the `revisor` has no probes, so its Pod is marked ready as soon as the container starts, even though the program is not yet listening. That is why Lesson 5 completes this column: with a readiness probe, the Pod is only marked ready when `/salud` answers, and the Service stops sending it traffic if it stops answering.

#### 3.4.4 `Endpoints`, the old API

In tutorials you will find the command `kubectl get endpoints`. It still works, but look at what it says:

```text
$ kubectl get endpoints revisor
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS                                         AGE
revisor   10.244.1.3:8080,10.244.1.4:8080,10.244.2.2:8080   6s
```

`Endpoints` is the earlier API, and the server itself warns you: "deprecated in v1.33+; use EndpointSlice". The Services documentation marks it the same way ("Deprecated since Kubernetes v1.33") and gives the reasons: it does not work for clusters with IPv4 and IPv6 at the same time, it does not carry the information that new features require, and it "truncates the list of endpoints if it is too long to fit in a single object". This course uses EndpointSlice. `Endpoints` is deprecated, not removed: it still works, as you just saw, but it is no longer the recommended API. It is named here so you recognize it when you see it, which is the course's rule for the deprecated and the removed: they are named to be recognized, not taught.

### 3.5 A debug Pod

#### 3.5.1 Why it is needed

To test the Service you need a client **inside** the cluster, because a `ClusterIP` is only reachable from there. The obvious candidate would be the `revisor` itself, but in Lesson 2 you saw that its image has neither *shell* nor `curl`: `kubectl exec deployment/revisor -- sh` fails with `executable file not found in $PATH`. That is a defense, and the course is not going to remove it in order to debug. The way out is another: a separate Pod, made for looking, which is created when needed and deleted when done.

It is a **program**: `programas/03-services-dns/depurar.yaml`.

```yaml
# depurar.yaml — Lección 3: un Pod de depuración con curl, que se borra al terminar.
# Ya cumple el nivel «restricted» (Lección 7), para que sirva igual en el espacio
# de nombres revisor. La imagen va fijada por su huella.
apiVersion: v1
kind: Pod
metadata:
  name: depurar
  labels:
    app: depurar
    acceso-revisor: permitido
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
  - name: depurar
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

#### 3.5.2 Field by field

It is a bare Pod, on purpose: in Lesson 2 you learned that a Pod without an owner is not reborn, and here that is exactly what you want. When you delete it, it stays deleted. The rest:

- **The image** is `curlimages/curl`, a small image with `curl` and the basic tools of Alpine Linux (`sh`, `nslookup`, `cat`), which come from BusyBox. It is pinned by its `sha256` digest, not just by its `8.22.0` tag. A tag can be moved to another image in the registry; a digest cannot. Since this image is downloaded from the internet, the digest identifies the image's manifest by its content, so your cluster will download the same layers that were tested here even if someone moves the `8.22.0` tag in the registry.
- **`imagePullPolicy` is not written.** Unlike the `revisor`, this manifest does not declare it: with a tag that is not `:latest`, the default value is `IfNotPresent`, the same one Lesson 2 wrote in plain view. Here the default value is left.
- **`command: ["sleep", "3600"]`** replaces the image's program, which would be a `curl` that ends right away, with a one-hour wait. That way the Pod stays alive and you can send it commands with `kubectl exec`. With `restartPolicy: Never`, when the hour passes the Pod ends and is not restarted.
- **The `securityContext`** is the same pattern as the `revisor`'s, with user 100 and group 101, the ones the curl image carries. A Pod being "only for debugging" is no excuse to run as `root`: a forgotten debug Pod is exactly the one someone finds later.
- **`resources`** sets a floor and a ceiling for CPU and memory. They are explained in Lesson 5; they are here because a support Pod must not be able to eat the node.
- **`automountServiceAccountToken: false`** keeps the API credential that Lesson 2 found in the `revisor` from being mounted. `curl` does not need it. Lesson 7 generalizes it.
- **The label `acceso-revisor: permitido`** does nothing yet. In Lesson 7, when the network is closed, it will be the key that lets this Pod talk to the `revisor`. It goes in from today so the same file works in both lessons.

#### 3.5.3 First contact

```text
$ kubectl apply -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -o wide
NAME      READY   STATUS    RESTARTS   AGE   IP           NODE                  NOMINATED NODE   READINESS GATES
depurar   1/1     Running   0          29s   10.244.2.4   curso-k8s-l3-worker   <none>           <none>

$ kubectl exec depurar -- id
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)

$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec depurar -- curl -s http://10.96.144.175/salud
{"estado":"vivo","version":"1.6.0"}
```

`id` confirms user 100. And the last two requests are the heart of the lesson. The first uses the Service's **name**, without a port (80 is HTTP's default) and without knowing anything about the Pods. The second uses the Service's IP. Both reach a replica of the `revisor`, which answers its `/salud` with version `1.6.0`. Nobody wrote a Pod IP anywhere. That the name `revisor` became `10.96.144.175` is the cluster DNS's work, and that is what comes next.

### 3.6 The cluster DNS

#### 3.6.1 Who answers

Every Pod knows whom to ask for names because the `kubelet` writes it an `/etc/resolv.conf` when creating it:

```text
$ kubectl exec depurar -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

Three lines. The middle one says whom to ask: `10.96.0.10`. That address is in the Services network, and it is no coincidence:

```text
$ kubectl get service -n kube-system kube-dns
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   74s

$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-cf8pv   1/1     Running   0          65s   10.244.0.2   curso-k8s-l3-control-plane   <none>           <none>
coredns-559f6c778d-h2hgl   1/1     Running   0          65s   10.244.0.4   curso-k8s-l3-control-plane   <none>           <none>
```

The cluster DNS is, itself, **a Service with its selector**: `kube-dns`, in the `kube-system` namespace, port 53 (DNS's), which sends the queries to the two `coredns` Pods you saw in Lesson 0. Exactly the pattern you just wrote for the `revisor`. If tomorrow one of the `coredns` goes down, its Service stays at `10.96.0.10` and the other answers. Kubernetes uses its own components to solve its own problem.

(`-n kube-system` tells `kubectl` which namespace to look in. Until now everything has lived in `default`. Namespaces are studied in Lesson 7.)

#### 3.6.2 A Service's full name

The [DNS for Services and Pods documentation](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) gives the shape of the name: a normal Service gets a record with a name of the form `my-svc.my-namespace.svc.cluster-domain.example`, which "resolves to the cluster IP of the Service". For yours:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

It reads from left to right, from the specific to the general:

| Part | What it is |
|---|---|
| `revisor` | the Service's name |
| `default` | the namespace it lives in |
| `svc` | that it is a Service (and not something else) |
| `cluster.local` | the cluster's domain, the default one |

And the answer, `10.96.144.175`, is the Service's IP, the one from 3.2. The DNS does not give you the Pods' IPs: it gives you the stable address, and spreading the load is the Service's job.

#### 3.6.3 Why a bare `revisor` works

In 3.5 you wrote `http://revisor/salud`, not the full name, and it worked. What makes it possible is the first line of `resolv.conf`, `search`. The DNS documentation explains it: queries "can be expanded using the Pod's `/etc/resolv.conf`" and "the values of the `search` option are used to expand queries". The one doing the expanding is not the Pod but the DNS library of the program asking. When `curl` asks for `revisor`, its library appends, one by one, the `search` domains: `revisor.default.svc.cluster.local`, `revisor.svc.cluster.local`, and `revisor.cluster.local`, and stops at the first one that answers. Here the first already answers. In 3.6.4 you will see that this image's `nslookup` does not stop: it asks all of them at once.

The third line, `options ndots:5`, decides **when** that list is used. The Services debugging guide puts it this way: the `options` line "should set `ndots` high enough that your DNS client library considers search paths at all", and Kubernetes sets it to 5 by default, "high enough to cover all of the DNS names it generates". In practice: a name with fewer than five dots is first tried with the `search` list. `revisor` has none, so it is expanded. That is why the intermediate form, with the namespace, also works:

```text
$ kubectl exec depurar -- curl -s http://revisor.default/salud
{"estado":"vivo","version":"1.6.0"}
```

`revisor.default` plus `svc.cluster.local`, the second element of `search`, gives the full name. The documentation states it as a rule: queries that do not say a namespace "are limited to the Pod's namespace"; to reach a Service in another namespace, you write the namespace in the name. Today everything lives in `default` and it is not noticeable. From Lesson 7 on, when the `revisor` moves to its own namespace, `revisor.revisor` will be the way to reach it from outside it.

#### 3.6.4 The `NXDOMAIN`s that are not an error

Now ask `nslookup` for the short name:

```text
$ kubectl exec depurar -- nslookup revisor
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find revisor.cluster.local: NXDOMAIN

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175

** server can't find revisor.svc.cluster.local: NXDOMAIN


** server can't find revisor.cluster.local: NXDOMAIN

** server can't find revisor.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

It looks like a disaster: four "I can't find it" and an exit code of 1. Read it slowly. In the middle of them is the right answer: `revisor.default.svc.cluster.local` is `10.96.144.175`. The four `NXDOMAIN`s (*non-existent domain*, "that name does not exist") are the **other** expansions of the `search` list: `revisor.svc.cluster.local` and `revisor.cluster.local` do not exist, and that is true, they do not exist. Each comes out twice because this image's `nslookup`, BusyBox's, asks two things for each name: its IPv4 address (an `A` record) and its IPv6 address (an `AAAA` record). For the full name, which does exist, it also asked both; since the Service has no IPv6 address, that second question comes back with no records, and that is not printed as an error (a name that exists but has no record of that type is different from one that does not exist). It prints each failure and, if there was any, ends with code 1 even though it found the answer. The order of the lines changes from one run to another, because the queries go out at the same time: in another run of this same lesson, the answer came out last, after the four `NXDOMAIN`s.

`curl` complains about none of this because it only cares about finding **one** address, and it found it. The practical lesson: with `nslookup`, ask for the full name; in this image it comes out clean, as you saw in 3.6.2. Mind why: it is not that the rule guarantees it. With `ndots:5`, even `revisor.default.svc.cluster.local` (four dots) counts as "short" for a library that follows the rule to the letter, and that is precisely the known cost of `ndots:5`: extra queries even with the full name. That it comes out clean is the measured behavior of this `nslookup`. For a name to be absolute and never expanded, end it with a dot: `revisor.default.svc.cluster.local.` And if you see `NXDOMAIN` with the short name, look for the `Name:` line before getting alarmed.

For comparison, this is what a name that truly does not exist looks like:

```text
$ kubectl exec depurar -- nslookup no-existe.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

No `Name:` line and no `Address:` at the end. That absence is the difference, not the `NXDOMAIN`s.

### 3.7 The test service: the `revisor` finally checks someone

Since Lesson 2, the `revisor` has `REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s` written in its manifest. That line was already a promise about this lesson: it asks it to check a service called `prueba` at `http://prueba:9000/`, with a 2-second limit. That URL uses a **name**, not an IP. See what happens today, before that name exists:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        4ms  no responde: Get "http://prueba:9000/": dial tcp: lookup prueba on 10.96.0.10:53: no such host
```

The `revisor` does its job well: it says that `prueba` fails, and why. `lookup prueba on 10.96.0.10:53: no such host`: it asked the cluster DNS (the `10.96.0.10` from 3.6) about `prueba` and the DNS answered that it does not exist. There is no Pod, no Service, no name.

These are the two manifests of the test service. Both are **programs**: `prueba-deployment.yaml` and `prueba-service.yaml`.

```yaml
# prueba-deployment.yaml — Lección 3: el servicio que falla a propósito.
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
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

```yaml
# prueba-service.yaml — Lección 3: el nombre «prueba» que el revisor consulta.
apiVersion: v1
kind: Service
metadata:
  name: prueba
  labels:
    app: prueba
spec:
  type: ClusterIP
  selector:
    app: prueba
  ports:
  - name: http
    port: 9000
    targetPort: http
```

The Deployment is Lesson 2's pattern, with the same `securityContext` and **one** replica: it is a test service, no more is needed. It carries no volume, because it writes nothing to disk. The Service has a difference from the `revisor`'s that is worth noting: here `port` is `9000`, the same as the container's, because that is what the URL the `revisor` already has written (`http://prueba:9000/`) asks for. The `targetPort` is still by name. The rule is not "the Service always on 80": the Service's port is the one your clients expect.

```text
$ kubectl apply -f prueba-deployment.yaml -f prueba-service.yaml
deployment.apps/prueba created
service/prueba created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP    79s
prueba       ClusterIP   10.96.236.7     <none>        9000/TCP   3s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP     40s

$ kubectl exec depurar -- curl -s http://prueba:9000/modo
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

`OK`, in 1 millisecond, with code `200`. The `revisor` was not restarted, its configuration was not changed, no IP was given to it. Its manifest said `prueba` from the start; the only thing that changed is that now that name exists. Every time the `revisor` builds its report, it asks for the name again. This is what Tuesday's scene needed: the configuration says **who**, not **where it is**.

Now it is broken on purpose, in its three modes:

```text
$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  codigo 503

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/lento
modo: lento

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

Each mode tells something different. In `caido`, `prueba` answers, but with `503`: the `revisor` says `FALLA codigo 503`. In `lento`, `prueba` takes longer than the 2 seconds the list gives it, and the `revisor` gives up at `2.002s` with `se acabo el tiempo de espera`. (The `revisor`'s `LENTO` status is for a service that answers fine but takes more than 1 second **without** exceeding the limit; here it exceeded it.) And in `sano`, everything goes back to `OK`. All three cases went through the Service and through the cluster DNS, and the `revisor` told them apart.

With this, the `revisor` does inside the cluster the same thing it did in Compose in the Docker course. The translation table from Lesson 0 anticipated it: the service name on Compose's network becomes the cluster DNS.

### 3.8 How a Service spreads load

#### 3.8.1 Measuring it

The Service has three replicas behind it. Does it use all three? It is measured with thirty requests and the `revisor`'s log, which writes one line for each request it serves:

```text
$ kubectl exec depurar -- sh -c 'for i in $(seq 1 30); do curl -s -o /dev/null http://revisor/salud; done; echo 30 peticiones'
30 peticiones

$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /salud' | cut -d' ' -f1 | sort | uniq -c
   6 [pod/revisor-697fb84f97-mjbff/revisor]
  13 [pod/revisor-697fb84f97-nq74v/revisor]
  14 [pod/revisor-697fb84f97-z79jh/revisor]
```

The second command combines several tools, and it is worth taking apart:

- `kubectl logs -l app=revisor` asks for the log of **all** the Pods with that label, not of one;
- `--prefix` prepends to each line the Pod it came from;
- `--tail=-1` asks for the complete log (with a label selector, `kubectl logs` shows by default only the last lines of each Pod);
- `grep` keeps the `/salud` lines, `cut` the prefix, and `sort | uniq -c` counts how many there are from each Pod.

All three replicas received traffic. They add up to 33 and not 30 because the three requests to `/salud` from 3.5 and 3.6 are also in the log. And the spread is not even: 14, 13, and 6. It does not have to be.

#### 3.8.2 Who does the work

A Service's IP is held by no machine. The [virtual IPs reference](https://kubernetes.io/docs/reference/networking/virtual-ips/) says who makes it work: "the `kube-proxy` component is responsible for implementing a virtual IP mechanism for Services". `kube-proxy` runs on every node (the three you saw in Lesson 1), reads the EndpointSlices, and writes rules into the node's network. When a packet goes out toward `10.96.144.175:80`, those rules divert it to the IP and port of a real Pod, for example `10.244.1.4:8080`.

How does it choose the Pod? The same reference says that the default mode on Linux, for Kubernetes 1.37, is `iptables`, and that in that mode the rules, "by default, pick a backend Pod at random". At random, not in turns. Over thirty draws, a spread of 14, 13, and 6 is perfectly possible. With many more requests, each replica would approach a third. And the `Session Affinity: None` in `describe` is what allows that randomness: the reference explains that, if you want the same client to always go to the same Pod, you can set `sessionAffinity: ClientIP`, and that the default value is `None`. The `revisor` stores nothing between requests, so it does not need it.

This has a consequence worth knowing from now on: the Service spreads **connections**, not requests. Each `curl` in the loop opens a new connection, and that is why each one lands wherever it happens to. A client that reuses a single connection for many requests always talks to the same Pod for as long as that connection lives.

### 3.9 `port-forward`: a tunnel from your machine

Everything so far happened **inside** the cluster. And you, from your terminal? The IP `10.96.144.175` is no use outside the cluster (the security habit section verifies it). To test from your machine without publishing anything there is `kubectl port-forward`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &
Forwarding from 127.0.0.1:18080 -> 8080

$ curl -s http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s 'http://127.0.0.1:18080/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK            0s  200
```

It reads like this: listen on port `18080` of your machine, only on the address `127.0.0.1`, and forward whatever arrives to port `80` of the `revisor` Service. The final `&` leaves it running in the background, so you can use the same terminal. While it runs, each time you make a request `kubectl` will print `Handling connection for 18080` in that terminal: that is normal. You stop it with `kill %1` or by bringing it to the foreground with `fg` and `Ctrl+C`. If you prefer to leave it in a separate terminal, remember what you learned in 3.1: in that new terminal, first the same `export KUBECONFIG=…` and `kubectl config current-context`, which must say `kind-curso-k8s-l3`.

Read its first line carefully: `Forwarding from 127.0.0.1:18080 -> 8080`. It does not say `-> 80`. `kubectl` translated the Service's `80` to its `targetPort` and that to the Pod's `8080`, and opened the tunnel **directly to a Pod**. The [`kubectl port-forward` reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/) says it from its first sentence: "forward one or more local ports to a pod". And it adds: when you give it a resource such as a Deployment or a Service, `kubectl` picks a Pod; "if there are multiple pods matching the criteria, a pod is automatically selected. Forwarding connections terminate when the selected pod terminates, and rerun of the command is needed". That is: `port-forward service/revisor` does **not** spread load like the Service. It uses the Service only to find a Pod. Exercise 3 shows you what happens when that Pod goes away.

And `--address 127.0.0.1`? The reference says the default value of `--address` is `localhost`, with which `kubectl` tries to listen on `127.0.0.1` and on `::1` (your own machine's address in IPv6). The course writes `127.0.0.1`: a single address, in plain view, for the same reason it writes `type: ClusterIP`. The decision not to open the tunnel to the network is written down, and nobody has to know the default value. The same reference carries, among its examples, `--address 0.0.0.0`, which listens "on all addresses". That would turn your laptop into an entry point to that Pod for anyone on your network, with no password and with your cluster credentials behind it. What opened the tunnel is checked:

```text
$ lsof -nP -iTCP:18080 -sTCP:LISTEN | awk '{print $1, $8, $9, $10}'
COMMAND NODE NAME 
kubectl TCP 127.0.0.1:18080 (LISTEN)
```

A single process, `kubectl`, listening on `127.0.0.1:18080` and nowhere else. (`lsof` lists who has a port open; `awk` keeps four columns so it fits. On Linux Mint it works the same; you can also use `ss -ltnp | grep 18080`.)

A `port-forward` is for testing, not for serving. It lives as long as your command and your session live, it depends on your cluster credentials, and it breaks when the Pod it chose goes away. Publishing the `revisor` for real, through a named entry point, is Lesson 6.

## The error you will see

This lesson's error is one of the most common with Services, and the debugging guide itself mentions it as such: a Service whose selector selects nobody. It is provoked with `fig03_01.selector-malo.yaml`, a **program** that fails on purpose: the same `revisor` Service, with one letter missing.

```yaml
# fig03_01.selector-malo.yaml — FALLA A PROPÓSITO: el mismo Service del revisor
# con una letra de menos en el selector (revisr). Se aplica encima del bueno, el
# Service se queda sin a quién mandar tráfico y curl sale con código 7. Se
# corrige volviendo a aplicar revisor-service.yaml.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisr
  ports:
  - name: http
    port: 80
    targetPort: http
```

Before applying it, `kubectl config current-context` must say `kind-curso-k8s-l3`.

```text
$ kubectl apply -f fig03_01.selector-malo.yaml
service/revisor configured
```

`configured`: the `kube-apiserver` accepted the change without complaint, and it is right. A selector `app: revisr` is perfectly valid; it just matches nothing. Kubernetes cannot know that you meant to write `revisor`.

**Give the cluster a moment.** Before testing, check that the EndpointSlice is already empty: `kubectl get endpointslices -l kubernetes.io/service-name=revisor` must say `<unset>` in the `ENDPOINTS` column. If you test in the same second as the `apply`, `kube-proxy` has not yet found out about the change, the `curl` answers as if nothing happened, and you will think the error "didn't happen". The script does exactly that: it waits for the list to empty and only then tests. After that, it is read in order, as in Lesson 2.

**First, the symptom.** From the debug Pod, asking `curl` to say how long it took:

```text
$ kubectl exec depurar -- curl -s -m 3 -o /dev/null -w 'tardó %{time_total} s\n' http://revisor/salud
tardó 0.001120 s
command terminated with exit code 7
[código de salida: 7]
```

(`-o /dev/null` throws away the response, which there is none of here, and `-w` asks `curl` to write the total time of the request at the end.) `-m 3` puts a 3-second limit on it, so it does not wait endlessly; it was not needed: it took a thousandth of a second. Code 7 is, according to the [list of curl errors](https://curl.se/libcurl/c/libcurl-errors.html), "couldn't connect to host" (*Failed to connect() to host or proxy*). It is not 6, "couldn't resolve host": the name did resolve. And it is not 28, "timeout": the connection did not sit waiting, someone rejected it immediately. That distinction already tells you where to look.

**Second, the DNS.** If the name resolved, the DNS is not the problem. It is checked:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

The name still exists and still gives the same IP. The Service is there. What is missing is anyone behind it.

**Third, the *endpoints*.** This is the decisive step:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS     ENDPOINTS   AGE
revisor-6jh2f   IPv4          <unset>   <unset>     51s

$ kubectl describe service revisor | grep -E '^(Selector|Endpoints):'
Selector:                 app=revisr
Endpoints:                
```

`ENDPOINTS <unset>`: the EndpointSlice still exists, but empty, with no addresses and no ports. `describe` confirms it with a blank `Endpoints:` and, one line above, shows the cause: `Selector: app=revisr`. The Services debugging guide says it almost in these words: if the endpoints list is empty, "check that the `spec.selector` field of your Service actually selects `metadata.labels` values on your Pods. A common mistake is to have a typo".

**Fourth, the selector against the labels.** It is checked with the same selector, which is precisely Lesson 2's tool:

```text
$ kubectl get pods -l app=revisr
No resources found in default namespace.

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-mjbff   1/1     Running   0          48s
revisor-697fb84f97-nq74v   1/1     Running   0          53s
revisor-697fb84f97-z79jh   1/1     Running   0          52s
```

Zero Pods with `app=revisr`, three with `app=revisor`, all three `Running`. The Pods are perfect. The Service is looking for others.

**Why code 7 and not a timeout.** With the list empty, `kube-proxy` has nowhere to send the connection. What was measured is the code, 7, and the time, a thousandth of a second: the connection did not wait until the 3-second limit, it was rejected as soon as it went out. (In `iptables` mode, `kube-proxy` puts in a reject rule for Services without *endpoints*. It is the behavior observed in this run, not something the documentation promises.) It is the same signal as in Exercise 1, for a different cause: there the Service does have someone to send traffic to, but at the wrong port. What separates one case from the other is the `ENDPOINTS` column.

**The correction** is the cause, not the Pod: apply the good file again.

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   53s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

The three addresses came back to the same EndpointSlice (`revisor-6jh2f`, whose age kept counting: it was not deleted nor was another created), and the `revisor` answers. Notice the order of the correction: the script waited to see the three addresses in the EndpointSlice before testing with `curl`. It is the same warning as at the start, in reverse: between applying the corrected Service and each `kube-proxy` updating its rules, a moment passes, and a test done right at that instant may still fail even though the fix is already in. First you check that the list is full; then you test.

**The order, for any Service that does not respond:**

1. What code does `curl` give? 6 is the name, 7 is rejection, and 28 is silence.
2. Does the full name resolve?
3. Does its EndpointSlice have addresses?
4. If it does not, does its `Selector` match the Pods' labels (`get pods -l …`)?
5. If it does, is the port in the `PORTS` column where the program listens?

## The security habit of the lesson: nothing is published just because

The course's habits table assigns this lesson three things: `ClusterIP` by default; nothing is published just because; `port-forward` only to `127.0.0.1`. All three are verified with the cluster in front of you.

**A `ClusterIP` is not visible from your machine.** From your terminal, outside the cluster, the same IP the debug Pod used without trouble:

```text
$ curl -s -m 3 http://10.96.144.175/salud
[código de salida: 28]
```

Code 28: "timeout". Your machine has no route of its own to `10.96.0.0/16`: the packet goes out through your default route, toward your modem or your office network, which know nothing about the cluster, and nobody answers. (If your network uses `10.96.x.x` addresses, you could get another response, from a machine that has nothing to do with the cluster; all the more reason that IP is not yours outside of it.) The `10.96.144.175` only makes sense in the rules `kube-proxy` writes **inside** the nodes.

**The nodes publish nothing of the `revisor`.** Each kind node is a Docker container, and Docker says which ports each one publishes:

```text
$ docker port curso-k8s-l3-control-plane
6443/tcp -> 127.0.0.1:59190

$ docker port curso-k8s-l3-worker

$ docker port curso-k8s-l3-worker2
```

The control-plane node publishes a single port, the `kube-apiserver`'s `6443`, and only to `127.0.0.1` (the number on your side is chosen at random by kind; on your machine it will be another). It is the entry point through which your `kubectl` talks, and Lesson 1 saw it. The two worker nodes, where the `revisor` runs, publish **nothing**: their lines come out empty. There is no path from your network to the `revisor`'s port 8080. That is how it should be until Lesson 6, which opens a named entry point and says what crosses through it.

**The tunnel only listens on your machine.** You already saw it in 3.9: `kubectl` listening on `127.0.0.1:18080` and nowhere else.

Why it matters: every open path to a service is a path someone can use. In a real cluster, the reflex of "I'll change it to `NodePort` to test" or "I'll add `--address 0.0.0.0` so my colleague can see it" leaves open what nobody remembers to close. The course's rule is the reverse: everything is born closed, each opening is a decision written in a manifest and has its lesson.

**What it protects against and what it does not.** A `ClusterIP` keeps the `revisor` from being reached from **outside** the cluster. It prevents nothing **inside**: any Pod in any namespace can talk to it, as `depurar` did, which has nothing to do with the `revisor`. Nor does it encrypt traffic between Pods: it goes in plain HTTP over the Pod network. Closing who talks to whom is the job of the `NetworkPolicy` objects in Lesson 7. Encryption is discussed in Lesson 6.

## Common mistakes

**Storing a Pod's IP in the configuration.** It is Tuesday's scene. It works until the Pod is reborn. Always the Service's name.

**Storing the Service's IP instead of its name.** It is stable as long as the Service exists, but if you delete it and create it again it receives another. The name survives that; the IP does not.

**Writing `targetPort` as a number when the container has a name.** It works today and forces you to keep the same number in two files. The day one changes, the Service sends traffic to a port where nobody is listening (Exercise 1).

**Switching to `NodePort` or `LoadBalancer` "to test".** For testing there is `port-forward`, which opens nothing to the network. Publishing is a decision for Lesson 6, not a shortcut.

**Opening `port-forward` with `--address 0.0.0.0`.** It exposes that Pod's port to anyone who can reach your machine, with no password, using your cluster credentials, for as long as the command lives.

**Using `port-forward` as if it were a Service.** It talks to **one** Pod, does not spread load, and drops when that Pod goes away (Exercise 3). It is for looking, not for serving.

**Opening another terminal and forgetting the `export KUBECONFIG`.** In the new terminal, `kubectl` talks to whichever cluster your `~/.kube/config` says, which may be any other. First the `export`, then `kubectl config current-context`, and only then the command.

**Getting alarmed by `nslookup`'s `NXDOMAIN`s.** With the short name, they are the `search` expansions that do not exist. Look for the `Name:` line, or ask for the full name.

**Giving a bare Pod the labels of a Service's selector.** The Deployment does not adopt it, but the Service does use it, and sends it traffic (Exercise 2).

**Testing right after changing the Service and drawing conclusions.** Both when breaking it and when fixing it: first the `ENDPOINTS` column; then, `curl`.

**Removing the debug Pod's `securityContext` "because it's temporary".** What is temporary gets forgotten, and a forgotten `root` Pod is a way in for an attacker. This course's already meets the `restricted` level.

## Exercises

The first three are run in the lesson's cluster, in order and from the state it was left in after fixing the error. Before each exercise, `kubectl config current-context` must say `kind-curso-k8s-l3`; if it says anything else, do not continue. `correr.sh` runs them the same way, and its output is in `correr.salida.txt`. **Before** running each one, write in the [log](bitacora.md) what you think will happen. The fourth is written in your own words.

### Exercise 1 — A `targetPort` where nobody is listening

`fig03_02.puerto-malo.yaml` is the same `revisor` Service with the selector right and a single difference: `targetPort: 8081`, a number, instead of `http`.

```yaml
# fig03_02.puerto-malo.yaml — Ejercicio 1: el selector está bien, pero el
# targetPort apunta a un número donde el revisor no escucha (8081 en lugar del
# 8080 que se llama «http»). Pregunta: ¿el Service tiene endpoints? ¿Responde?
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: 8081
```

Before applying it, predict: how many addresses will the EndpointSlice have? What will its `PORTS` column say? What code will `curl -s -m 3 http://revisor/salud` give from `depurar`? Then apply it, wait a few seconds for the `PORTS` column to change (the script waits five), check, and explain how this failure resembles and how it differs from the one in "The error you will see". When you finish, apply `revisor-service.yaml` again.

### Exercise 2 — The Pod that sneaks into the Service

`fig03_03.colado.yaml` is Lesson 2's Exercise 2 `revisor-extra`: a bare Pod, identical to the replicas, **with** the label `app: revisor` and with its port named `http`. In Lesson 2 you saw that the Deployment does not adopt it. Now there is a Service that selects by `app: revisor`.

Predict: how many replicas does the Deployment say? How many addresses does the `revisor`'s EndpointSlice have? If you send 40 requests to `http://revisor/salud`, roughly how many go to `revisor-extra`? Apply it, check with `kubectl get deployment revisor`, with the `jsonpath` from 3.4 (address and `targetRef.name`), and with `kubectl logs revisor-extra | grep -c 'GET /salud'` after the 3.8 loop with 40 requests. Then explain what would happen to that Pod the day you change the Deployment's image. When you finish, check the context and delete it: `kubectl delete pod revisor-extra`.

### Exercise 3 — The tunnel and the *rollout*

Open the `port-forward` from 3.9 again and check that `curl -s -m 3 http://127.0.0.1:18080/salud` answers. Predict: if you now run `kubectl rollout restart deployment/revisor` and wait for it to finish, does the same `curl` keep answering? Do it, and read what the `port-forward` wrote in its terminal. Explain what happened using the sentence from the `kubectl port-forward` reference that 3.9 quotes.

### Exercise 4 — The four `NXDOMAIN`s

A colleague runs `kubectl exec depurar -- nslookup revisor`, sees four `server can't find … NXDOMAIN` lines and exit code 1, and concludes that "the cluster DNS is broken". In five sentences at most, answer her: where those names come from, why each appears twice, why the code is 1, how to tell from the same output that the name did resolve, and which command you would give her to check it without noise.

## Solutions

### Solution 1

Measured in `correr.salida.txt`:

```text
$ kubectl apply -f fig03_02.puerto-malo.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8081    10.244.2.2,10.244.1.4,10.244.1.3   59s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 7
[código de salida: 7]
```

**Three addresses, port `8081`, and `curl` with code 7.** The selector is right, so the EndpointSlice has the three replicas. But its `PORTS` column says `8081`: with a number, the cluster looks nothing up in the Pod, it takes the number as is. The connection reaches the correct IP of a real Pod, at a port where the `revisor` does not listen, and the Pod rejects it: code 7, "couldn't connect".

It resembles the lesson's error in the symptom: the same code 7. It differs in the `ENDPOINTS` column: there it was `<unset>` (there is no one), here it is full (there is someone, at the wrong port). That is why the diagnostic order looks at the addresses first and then at the port. The Services debugging guide asks it just so: "is the `targetPort` correct for your Pods?". And it is the argument in favor of `targetPort: http`: with the name, this error cannot be written without also changing the Deployment.

When applying the good one again:

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   64s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

`PORTS 8080`: the name `http` resolved again to the Pods' port.

### Solution 2

Measured in `correr.salida.txt`:

```text
$ kubectl apply -f fig03_03.colado.yaml
pod/revisor-extra created

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           69s

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v
10.244.1.4 revisor-697fb84f97-mjbff
10.244.1.3 revisor-697fb84f97-z79jh
10.244.2.6 revisor-extra

$ kubectl exec depurar -- sh -c 'for i in $(seq 1 40); do curl -s -o /dev/null http://revisor/salud; done; echo 40 peticiones'
40 peticiones

$ kubectl logs revisor-extra | grep -c 'GET /salud'
12

$ kubectl delete pod revisor-extra
pod "revisor-extra" deleted from default namespace
```

**The Deployment says `3/3`, the Service has four addresses, and `revisor-extra` got 12 of 40.** The Deployment does not count it, for what you saw in Lesson 2: its ReplicaSet also looks for `pod-template-hash`. The Service does, because it looks only for `app: revisor`, and `revisor-extra` carries it. For the Service it is one more replica: it appears in its EndpointSlice and receives its share of the traffic at random. With four *endpoints*, the expected value is about 10 of 40, and 12 is close. In your run it will be another number, and it does not matter which: what matters is that it is not zero.

The day you change the Deployment's image, the *rollout* replaces the three replicas and `revisor-extra` keeps the old image, because it belongs to nobody. The Service would keep sending it its share of the traffic, and some of your users would see the previous version without any `kubectl get deployment` warning you. It is Lesson 2's warning about overlapping selectors, now with real traffic.

### Solution 3

Measured in `correr.salida.txt`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &

$ curl -s -m 3 http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ curl -s -m 3 http://127.0.0.1:18080/salud
[código de salida: 52]
```

(The `rollout status` output is trimmed: in `correr.salida.txt` each line repeats several times, as in Lesson 2.) And what the `port-forward` wrote:

```text
Forwarding from 127.0.0.1:18080 -> 8080
Handling connection for 18080
Handling connection for 18080
E1021 07:23:02.902759   47411 portforward.go:549] "An error occurred forwarding" err="error forwarding port 8080 to pod 0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb, uid : network namespace for sandbox \"0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb\" is closed" localPort=18080 remotePort=8080
error: lost connection to pod
```

**The `curl` after the *rollout* fails with 52**, which in curl's error list is "empty reply from server". The tunnel was not going to the Service: it was going to **one** Pod, chosen when it was opened. `rollout restart` replaced the three Pods, that one included. The next connection reached the tunnel, the tunnel tried to forward it to a Pod whose network was already closed (`network namespace for sandbox … is closed`), and `kubectl` gave up: `error: lost connection to pod`. It is exactly what the reference says: "forwarding connections terminate when the selected pod terminates, and rerun of the command is needed". The Service, meanwhile, kept its address and its selector for the clients inside the cluster: what dropped was your tunnel. This lesson did not measure whether an internal client loses any request during the *rollout*: the `revisor` does not yet have readiness probes or an orderly shutdown, and that arrives in Lesson 5; Lesson 9 measures it with real load. That is why `port-forward` is for looking, and why it is no good for publishing anything.

### Solution 4

One possible answer: "Those names are the other expansions of the `search` list in `/etc/resolv.conf`: each domain on the list is appended to `revisor`, and `revisor.svc.cluster.local` and `revisor.cluster.local` really do not exist. Each comes out twice because BusyBox's `nslookup` asks for the IPv4 address and the IPv6 address of each name. It prints each failure and ends with code 1 if there was any, even though it found the answer. The proof that it did resolve is in the same output: the line `Name: revisor.default.svc.cluster.local` with its `Address`. To check it without noise: `kubectl exec depurar -- nslookup revisor.default.svc.cluster.local`, which in this image comes out clean."

## Deleting the cluster

When you finish the exercises, delete the lesson's cluster. Leave nothing alive on the machine. If you left a `port-forward` open in another terminal, stop it first with `Ctrl+C`.

```text
$ kind delete cluster --name curso-k8s-l3
Deleting cluster "curso-k8s-l3" ...
Deleted nodes: ["curso-k8s-l3-control-plane" "curso-k8s-l3-worker" "curso-k8s-l3-worker2"]

$ kind get clusters | grep -c curso-k8s-l3
0
```

The `--name` is mandatory here too: without it, kind would delete the cluster called `kind`, which may belong to someone else or to another project. Then, delete the `kubeconfig`'s temporary folder (the one `mktemp` created, with the prefix `/tmp/curso-k8s-l3.`; the cluster's administrator credential is in there) or close that terminal. The next lesson's cluster is created from scratch, just like this one.

## How I know I succeeded

- [ ] You explain, with the output from 3.1 in front of you, why a Pod's IP is no good as an address, and what changes when the client uses a Service's name.
- [ ] You write from memory a `ClusterIP` Service with `selector` and `ports`, and in the `revisor`'s you say which is `port`, which is `targetPort`, which is `containerPort`, and what value each has.
- [ ] You find any Service's EndpointSlice with `kubectl get endpointslices -l kubernetes.io/service-name=<name>` and say, from its addresses, which Pods traffic reaches.
- [ ] You explain each line of a Pod's `/etc/resolv.conf` and why `revisor`, `revisor.default`, and `revisor.default.svc.cluster.local` lead to the same place.
- [ ] Faced with a `curl` with code 7 against a Service, you check in order the name, the `ENDPOINTS` column, and the port, and you tell a misspelled selector from a misspelled `targetPort`.
- [ ] You open a `port-forward` that listens only on `127.0.0.1`, verify it with `lsof` (or `ss` on Linux Mint), and say why it drops with a *rollout*.
- [ ] You run `programas/03-services-dns/correr.sh > /tmp/mi-corrida-l3.txt 2>&1` and compare `/tmp/mi-corrida-l3.txt` against `programas/03-services-dns/correr.salida.txt` (do not redirect to that file: it is the reference) in what does not change between runs: three nodes `Ready` at `v1.37.0`; six `not yet present on node … loading...` lines; the `revisor` Service as `ClusterIP` on `80/TCP` with `EXTERNAL-IP <none>`; `TargetPort: http/TCP` and three `Endpoints` on `8080`; the EndpointSlice with `PORTS 8080`, three addresses, and owner `Service/revisor`; the warning `v1 Endpoints is deprecated in v1.33+`; `uid=100(curl_user)`; `{"estado":"vivo","version":"1.6.0"}` by name and by IP; the `resolv.conf` with its three lines; `kube-dns` at `10.96.0.10`; `lookup prueba … no such host` before creating the test service, and after it `OK … 200`, `FALLA … codigo 503`, and `FALLA … se acabo el tiempo de espera`; the three replicas with some request in 3.8; `Forwarding from 127.0.0.1:18080 -> 8080` and `kubectl TCP 127.0.0.1:18080 (LISTEN)`; code 28 from your machine; the two worker nodes with no published ports; code 7 with the bad selector, in thousandths of a second, and `<unset>` in its EndpointSlice; `PORTS 8081` and code 7 in Exercise 1; four addresses with `revisor-extra` in Exercise 2; code 52 and `lost connection to pod` in Exercise 3; `sin diferencias con los archivos`; and at the end `0` `curso-k8s-l3` clusters and the line `la corrida completa tardó … s`. The IPs, the name suffixes, the ages, the port the control-plane node publishes, which node each Pod lands on, the order of the `kind load` and `nslookup` lines, the exact spread of requests, the timings, and the number of times each `rollout status` line repeats change on every run: they are observed, not compared. If you used another port with `PUERTO_LOCAL`, you will see that number instead of `18080`.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l3`.

## Summary

Answer without looking at the lesson:

1. Why should a Pod's IP not be stored in another program's configuration? What changed in the Pod in 3.1 besides the IP?
2. What does a `ClusterIP` Service do, from where is it reachable, and why is it the default type that this course writes anyway?
3. In the `revisor`'s Service, what is `port`, what is `targetPort`, and where does the `8080` come from? Why is `targetPort` given by name?
4. Which object stores a Service's list of Pods, who writes it, and with which label do you find it?
5. What is `kube-dns`, at which IP is it, and why does it look so much like your Service?
6. What three lines does a Pod's `/etc/resolv.conf` have and what does each do?
7. How does `kube-proxy` choose which replica to send a connection to, in the default mode?
8. Which `curl` codes distinguish "did not resolve the name", "refused the connection", and "did not answer in time"?
9. How many Pods does `kubectl port-forward service/revisor` talk to, and what happens to it with a *rollout*?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, "Service"](https://kubernetes.io/docs/concepts/services-networking/service/): what a Service is; the `ClusterIP` type as the default and reachable only from inside the cluster; `targetPort` equal to `port` by default; named ports; the *cluster IP*; the `Endpoints` API, deprecated since v1.33, and why.
- [Kubernetes, "EndpointSlices"](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/): what an EndpointSlice stores; the `kubernetes.io/service-name` label and the reference to its owner; the cap of 100 *endpoints* per EndpointSlice; the `serving`, `terminating`, and `ready` conditions.
- [Kubernetes, "DNS for Services and Pods"](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): the shape of a Service's name; queries without a namespace limited to the Pod's; the `/etc/resolv.conf` with `search` and `ndots:5`.
- [Kubernetes, "Debug Services"](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/): the control loop that fills the EndpointSlices; the misspelled selector as a common mistake; the questions about `targetPort`; and why `ndots` is 5.
- [Kubernetes, "Virtual IPs and Service Proxies"](https://kubernetes.io/docs/reference/networking/virtual-ips/): `kube-proxy` as responsible for virtual IPs; `iptables` as the default mode in Kubernetes 1.37 and the random choice of Pod; `sessionAffinity` and its default value `None`.
- [Kubernetes, "kubectl port-forward"](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/): that it forwards to a Pod; the automatic choice of a Pod and the end of the session when that Pod terminates; `--address` and its default value `localhost`; the example with `0.0.0.0`.
- [Kubernetes, "Pods"](https://kubernetes.io/docs/concepts/workloads/pods/): Pods as ephemeral, disposable entities.
- [kind, "Configuration"](https://kind.sigs.k8s.io/docs/user/configuration/): the default subnets for Pods (`10.244.0.0/16`) and Services (`10.96.0.0/16`), and `kindnetd` as the default network.
- [kind, "Quick Start"](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind load docker-image` with `--name`.
- [curl, "libcurl error codes"](https://curl.se/libcurl/c/libcurl-errors.html): the meaning of the exit codes 6, 7, 28, and 52.

---

**Next:** [Lesson 4 — Configuration and secrets](04-configuracion-secretos.md)
