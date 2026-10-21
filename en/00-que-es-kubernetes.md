# Lesson 0 — What Kubernetes is and what kind is NOT

Friday, 11:40 at night. The `revisor` has been running for three weeks on a single server, started with a `docker run --restart always` that someone typed one afternoon and never wrote down anywhere. That night the server shuts down: a power supply fails. The container dies with it, and with it dies the Docker *daemon*, the only thing that knew how to restart it. On Monday at nine, the operations team needs the status report for the weekly meeting and the page is blank. Someone has to wake up, get another machine, remember the exact environment variables, the port, the volume, the image version… and all of that was in the terminal history of the server that will no longer boot.

The problem was not the container. It was that **nobody, except a sleeping person, knew how the service was supposed to be**. This lesson is about the tool that exists so that the system knows that, and not you at three in the morning.

**Time:** 90 min

**What you build:** nothing yet. It is a reading lesson: here you build the mental map that makes the rest of the course predictable

**What you learn:** what problem Kubernetes solves that Docker alone does not; the control plane and the nodes, component by component; declaring the desired state and letting the cluster reach it (the control loop); the map from Docker to Kubernetes; what kind is, what a kind cluster proves and what it does not prove; and what a local cluster protects against and what it does not

**Where you are coming from.** From our [Docker course](https://www.habil.mx/en/courses/docker/), or from equivalent practice: you know how to build an image, run it with `docker run`, give it environment variables, a port and a volume, and bring several up together with Compose. You also bring the `revisor` already packaged: a server in Go that listens on port 8080, answers `GET /salud` and `GET /api/estados`, and is configured through environment variables. What you do not bring is the map of **how a cluster thinks**, which is different from Docker's and which explains why the commands in the following lessons are the way they are.

**What this lesson does not do.** It does not install anything (that is [Lesson 1](01-instalacion-primer-cluster.md)) and it does not deploy the `revisor` (that starts in [Lesson 2](02-pods-deployments.md)). It includes a real tour through a kind cluster, with its outputs, so that you can see with your own eyes what the lesson claims. You do not need to understand every line of every output yet: what matters is **what they tell you**. If you want to repeat the tour, do it after Lesson 1, once you have `kubectl` and `kind`.

**About the runs.** The outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1 and the node image `kindest/node:v1.37.0` pinned by its digest, on Docker Engine 29.2.1. The machine was an ARM Mac, with Docker inside a Linux virtual machine (Colima), **not** Linux Mint, which is the course's reference system. What changes on your Mint: the `KERNEL-VERSION` column will show your kernel and `amd64` instead of `arm64`, the IP addresses and ports will be different, and the Pod names will carry different random suffixes. Everything else should match. There was one more difference, and it is instructive: on that machine a **three**-node cluster did not start, because the system's file-watching limit was set to 128 and ran out (section 0.6.3 tells the story). That is why the tour uses **a single node**; the course's three-node cluster arrives in Lesson 1, which adjusts that limit first. The full tour is in [`programas/00-que-es-kubernetes/`](../programas/00-que-es-kubernetes): `recorrido.sh` runs it from start to finish in about two minutes and `recorrido.salida.txt` is its output; `ejercicio3.sh` and `ejercicio3.salida.txt` do the same for Exercise 3.

## By the end you will be able to

- Explain with an example why `docker run --restart always` is not enough to keep a service alive when the machine running it goes down.
- Name the components of the control plane (`kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`) and those of each node (`kubelet`, `kube-proxy`, the container *runtime*), and say what each one does in one sentence.
- Describe step by step what happens in the cluster between a `kubectl apply` and a running container.
- Tell an imperative command (`kubectl scale`) from a declaration (`kubectl apply -f`) and predict what happens when they are mixed.
- Translate five Docker concepts to their equivalent in Kubernetes, and name one that has no equivalent.
- Say what kind is, what a kind cluster proves and what it does not prove.
- Read the error `The connection to the server localhost:8080 was refused` and say what it means.

## The why before the how

With Docker you learned to answer the question “how do I run this program?”. The answer is an image and a `docker run`. It is a great answer, and Kubernetes does not change it: the images you built in the Docker course are the exact ones the cluster is going to run.

But there is another question, which shows up as soon as a service matters: **“who makes sure it keeps running?”**. With Docker, the answer is that machine's *daemon*, and only while that machine lives. Docker's documentation makes it clear: restart policies, such as `always` or `unless-stopped`, apply to the containers of that *daemon* ([Docker, “Start containers automatically”](https://docs.docker.com/engine/containers/start-containers-automatically/)). If the machine disappears, nobody is left who remembers that something was running there.

Kubernetes answers the second question. You tell it **how your service should be**—“three copies of the `revisor`, with this image, with this configuration”—and it makes sure it stays that way, on whatever machines it has, even if one goes down. That changes your job: you stop issuing imperative commands (“start this”, “restart that”) and start writing **descriptions** of the state you want, which the cluster pursues tirelessly.

There is a second reason to start with reading rather than installation. Kubernetes has many components with odd names, and the messages it will give you in the following lessons (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) mention those components. If you do not know who the *scheduler* is, a `Pending` Pod is a mystery; if you do, it is a clue. And a third: in this course you are going to use **kind**, a cluster that lives inside Docker on your machine. It is an excellent tool for learning, but if you do not know what it is, you will believe your local cluster proves things it does not prove.

The lesson has eight parts, in this order:

1. **The problem Kubernetes solves** (0.1).
2. **Declaring instead of commanding: the control loop** (0.2), with a real cluster that repairs what you break.
3. **The components: the control plane and the nodes** (0.3), seen from the inside.
4. **An imperative command versus a declaration** (0.4): what happens when you mix them.
5. **The map from Docker to Kubernetes** (0.5).
6. **What kind is and what it is NOT** (0.6): what your local cluster proves and what it does not.
7. **The versions** (0.7): which ones the course uses and why.
8. **What comes in the rest of the course** (0.8).

With that destination in mind, this is what you will see in section 0.2. One of three Pods was deleted and, one second later, the cluster had already created another in its place without anyone asking it to. That is the central idea of the whole lesson:

```text
$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

## The concepts

### 0.1 The problem Kubernetes solves

#### 0.1.1 From “running a container” to “maintaining a service”

A container is a process with its own filesystem and its own network, on **one** machine. A service that people use needs more than that:

- **Several copies**, so that one going down does not leave anyone without service.
- Those copies on **different machines**, so that a machine going down does not either.
- **Someone to replace** a copy if it dies, without waiting for a person.
- A way for other programs to **find it by name**, even if its copies change machine and address.
- Configuration that is **changeable without rebuilding** the image.
- A way for a new version to **replace the old one without cutting off** the service.

With Docker and Compose you can solve some of these things on a single machine. None across several. Kubernetes is the tool that solves all six, on a group of machines it calls a **cluster**.

The official definition is this: Kubernetes is “a portable, extensible, open source platform for managing containerized workloads and services, that facilitates both declarative configuration and automation” ([kubernetes.io, “Overview”](https://kubernetes.io/docs/concepts/overview/)). Notice the word *declarative*: it is the one that matters, and section 0.2 explains it.

Two facts so they do not catch you by surprise. The name comes from Greek and means “helmsman” or “pilot”, and the abbreviation **K8s** comes from counting the eight letters between the “K” and the “s”. Google open-sourced the project in 2014 (all three facts, on the same official page).

#### 0.1.2 What Kubernetes is not

The same official page devotes a section to what Kubernetes does **not** do, and it pays to read it before starting because it prevents false expectations. Among other things, Kubernetes does not build your application or deploy source code (you bring the image yourself, as in the Docker course), does not include databases or message queues, and does not impose a logging or monitoring solution. And the sentence most worth remembering: Kubernetes “is not a mere orchestration system”. To orchestrate, in the technical sense, is to execute a defined workflow: “first A, then B, then C”. Kubernetes, by contrast, is “a set of independent, composable control processes that continuously drive the current state towards the provided desired state”.

That last sentence is the summary of this lesson. The rest takes it apart.

### 0.2 Declaring instead of commanding: the control loop

#### 0.2.1 The thermostat

Kubernetes's documentation explains its central idea with a device you know: a thermostat ([kubernetes.io, “Controllers”](https://kubernetes.io/docs/concepts/architecture/controller/)). When you set the temperature to 22 degrees, you are telling the thermostat your **desired state**. The actual temperature in the room is the **current state**. The thermostat turns the heating or cooling on or off to bring the current state closer to the desired one. You do not tell it “turn the air on for ten minutes”; you tell it “I want 22”, and it decides what to do, over and over, for as long as it is on.

That is a **control loop**: a non-terminating loop that watches, compares and corrects. In Kubernetes, each of those loops is called a **controller**: “controllers are control loops that watch the state of your cluster, then make or request changes where needed. Each controller tries to move the current cluster state closer to the desired state”.

The practical consequence is the one you saw in the opening scene, in reverse. With Docker, the knowledge of how the `revisor` was supposed to be lived in a person's memory. With Kubernetes it lives **in the cluster**, written down, and a program compares it against reality all the time.

#### 0.2.2 A desired state, written in a file

In Kubernetes, the desired state is written in a **manifest**: a YAML file that describes an object. This is the first manifest of the course. It asks for three copies of a container:

```yaml
# fig00_02.deployment.yaml — un estado deseado: «quiero tres copias de este contenedor».
# La imagen es `pause`, un contenedor que no hace nada más que esperar; viene ya
# dentro del nodo de kind, así que no se descarga nada. El `revisor` llega en la
# Lección 2; aquí solo importa ver qué hace el clúster con lo que declaras.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: espera
spec:
  replicas: 3
  selector:
    matchLabels:
      app: espera
  template:
    metadata:
      labels:
        app: espera
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65535
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: espera
        image: registry.k8s.io/pause:3.10
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

You do not need to understand all of it; Lesson 2 takes it apart field by field. For now, three things. `kind: Deployment` says what kind of object it is: a **Deployment** is the standard way of asking “keep N copies of this container running”. `replicas: 3` is the desired state: three copies. And `template` is the blueprint for each copy: which image it uses and with which label (`app: espera`) it is recognized. The two `securityContext` blocks say that the container runs without being `root`, without being able to gain privileges and with its root filesystem read-only; they are here because in this course every manifest carries them from the very first one, and Lesson 2 explains each.

The image, `registry.k8s.io/pause`, is a tiny container that does nothing but wait. It was chosen because it already comes inside the kind node (Kubernetes itself uses it internally), so the example does not depend on downloading anything from the internet.

#### 0.2.3 What the cluster does with your declaration

The manifest is handed to the cluster with `kubectl apply -f`. This is what the cluster from the tour responded:

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera created

$ kubectl rollout status deployment/espera --timeout=90s
Waiting for deployment "espera" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 2 of 3 updated replicas are available...
deployment "espera" successfully rolled out
```

Read the first response carefully: `deployment.apps/espera created`. It does not say “three containers started”. It says the Deployment object was **saved**. At that instant there was not a single container running; there was a description. The second command, `rollout status`, waits and counts: zero of three available, one, two, and at the end “successfully rolled out”. Between the first line and the last, the cluster was working so that reality would reach what you declared.

Now look at what was left:

```text
$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/3     3            3           1s

$ kubectl get replicaset -l app=espera
NAME                DESIRED   CURRENT   READY   AGE
espera-68b9d575f7   3         3         3       1s

$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-9gbtr   1/1     Running   0          1s
espera-68b9d575f7-cprg7   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          1s
```

You asked for **one** object and there are **three kinds** of object. It is a chain, and it pays to see it that way from day one:

```text
Deployment espera            «quiero 3 copias de este molde»
   └── ReplicaSet espera-68b9d575f7       «hay que tener 3 Pods con este molde exacto»
         ├── Pod espera-68b9d575f7-9gbtr
         ├── Pod espera-68b9d575f7-cprg7
         └── Pod espera-68b9d575f7-gsrlf
```

The **Deployment** is what you write. The **ReplicaSet** is created by the Deployment, and its only job is to count: to make sure there are as many Pods as `replicas` says. The suffix `68b9d575f7` identifies the blueprint; when you change the image in Lesson 2, another ReplicaSet with another suffix will appear, and that is how Kubernetes changes versions without cutting off service. And the **Pod** is the unit that actually runs: the documentation defines it as “the smallest deployable units of computing” in Kubernetes, “a group of one or more containers, with shared storage and network resources” ([kubernetes.io, “Pods”](https://kubernetes.io/docs/concepts/workloads/pods/)). Almost always, a Pod has a single container; in this course, always.

Notice also the names of the Pods: the final suffix (`9gbtr`, `cprg7`…) is random. On your run they will be different. That is why, in this course, a Pod's name is never typed by hand: you look it up by its label, with `-l app=espera`.

#### 0.2.4 Breaking something on purpose

Now the thermostat test. One of the three Pods was deleted by hand, as if it had died:

```text
$ kubectl delete pod espera-68b9d575f7-9gbtr
pod "espera-68b9d575f7-9gbtr" deleted from default namespace

$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

There are still three. `9gbtr` is gone, and there is a new one, `fjx8v`, one second old. Nobody asked for it. The ReplicaSet saw that the current state (two Pods) did not match the desired one (three) and created one. The cluster keeps a record of what it does in its **events**, and there you can see the whole story:

```text
$ kubectl get events --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp
LAST SEEN   TYPE     REASON             OBJECT                         MESSAGE
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-9gbtr
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-gsrlf
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-cprg7
1s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-fjx8v
```

Four creations: the three from the beginning and the replacement. Events are the first thing you look at when something does not turn out as expected, and the course uses them in every lesson.

This has a consequence that changes how you work: **in Kubernetes, deleting a Pod does not shut anything down**. If you want fewer copies, you change the desired state. If you want none, you delete the Deployment. Deleting the Pod only causes another one to be born.

#### 0.2.5 And when what goes down is a machine

The opening scene was not a container dying: it was a machine shutting down. Kubernetes covers that too, but it pays to know **how long it takes**, because it is not instantaneous. When a node stops responding, the cluster marks it as unavailable, and the Pods that were running on it stay bound there for a while before being replaced on another node. That time is written into every Pod. It was read from the Pod in the tour:

```text
[{"effect":"NoExecute","key":"node.kubernetes.io/not-ready","operator":"Exists","tolerationSeconds":300},{"effect":"NoExecute","key":"node.kubernetes.io/unreachable","operator":"Exists","tolerationSeconds":300}]
```

It is 300 seconds. The documentation confirms it: Kubernetes adds those two tolerations automatically, and they mean that Pods “remain bound to nodes for 5 minutes after one of these problems is detected” ([kubernetes.io, “Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)). The wait exists so that everything is not moved over a ten-second network hiccup.

So is the service down for five minutes? Not if you did what this course teaches: **having several replicas spread across different nodes**. While the ones on the downed node wait for their replacement, the ones on the other nodes keep serving requests. Watch out for a comfortable assumption: the Deployment watches over **how many** replicas there are, not **where** they end up. By default, the `kube-scheduler` *tries* to spread them across nodes, but if it cannot, it piles them onto one (the documentation says it acts as if it had the rule `whenUnsatisfiable: ScheduleAnyway`). To **require** the spread, the manifest has to declare it with `topologySpreadConstraints` or with anti-affinity ([kubernetes.io, “Pod Topology Spread Constraints”](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)); this lesson's manifest does not do so, and the course comes back to this when the `revisor` has to survive a node being shut down. That is one of the goals of the course: stopping a worker node and having the `revisor` keep responding.

### 0.3 The components: the control plane and the nodes

#### 0.3.1 Two kinds of machine

A cluster has two kinds of machine, which Kubernetes calls **nodes**:

- The **control plane**: the machines where the “brain” lives. They store the desired state, decide where each thing runs and execute the controllers.
- The **worker nodes**: the machines where your containers run.

In a production cluster, the control plane is usually on three dedicated machines, so that one going down does not stop it. In this lesson's cluster there is **a single node** that does both jobs; in Lesson 1's there will be one control-plane node and two worker nodes.

#### 0.3.2 The components, one by one

The definitions come from the official components page ([kubernetes.io, “Kubernetes Components”](https://kubernetes.io/docs/concepts/overview/components/)); the right-hand column translates them to what you see in the course.

| Component | Where it lives | What it does, according to the documentation | What it means for you |
|---|---|---|---|
| `kube-apiserver` | control plane | “the server that exposes the Kubernetes HTTP API” | it is the only entry point: `kubectl` talks to it, and so do all the other components |
| `etcd` | control plane | “consistent and highly-available key value store for all API server data” | your manifest is written here; if `etcd` is lost, the desired state is lost |
| `kube-scheduler` | control plane | “looks for Pods not yet bound to a node, and assigns each Pod to a suitable node” | decides **where** each Pod runs; when it finds no room, the Pod stays `Pending` (Lesson 5) |
| `kube-controller-manager` | control plane | “runs controllers to implement Kubernetes API behavior” | the thermostats live here: the one for Deployments, the one for ReplicaSets, the one for nodes… |
| `cloud-controller-manager` | control plane, optional | “integrates with underlying cloud providers” | in kind it does not exist; that is why a `LoadBalancer` needs help (Lesson 6) |
| `kubelet` | each node | “ensures that Pods are running, including their containers” | the agent on each machine: it receives Pods and makes them real |
| `kube-proxy` | each node, optional | “maintains network rules on nodes to implement Services” | directs traffic arriving at a Service's address and port to the Pods serving it at that moment; the Service's name is resolved by the cluster's DNS, not by it (Lesson 3) |
| container *runtime* | each node | “software that is responsible for running containers” | in kind it is `containerd`, not Docker |

#### 0.3.3 Seeing them in the cluster

All of that is not theory: you can see it. The control-plane components run as Pods in a reserved namespace, `kube-system`:

```text
$ kubectl get pods -n kube-system
NAME                                                 READY   STATUS    RESTARTS   AGE
coredns-559f6c778d-gg7jc                             1/1     Running   0          15s
coredns-559f6c778d-wcmct                             1/1     Running   0          15s
etcd-curso-k8s-l0-control-plane                      1/1     Running   0          23s
kindnet-2cfgd                                        1/1     Running   0          15s
kube-apiserver-curso-k8s-l0-control-plane            1/1     Running   0          22s
kube-controller-manager-curso-k8s-l0-control-plane   1/1     Running   0          22s
kube-proxy-cnp6z                                     1/1     Running   0          15s
kube-scheduler-curso-k8s-l0-control-plane            1/1     Running   0          22s
```

There are four of the components from the table: `etcd`, `kube-apiserver`, `kube-controller-manager` and `kube-scheduler`, each with the node's name appended to the end. There is `kube-proxy`. And there are three that the table does not mention: `coredns` (two copies), which is the cluster's internal DNS and what lets one Pod find another by name (Lesson 3); and `kindnet`, the Pod-to-Pod network that kind installs by default. Kubernetes does not come with its own network: a plugin called a CNI provides it, and each installation chooses its own. The [kind configuration guide](https://kind.sigs.k8s.io/docs/user/configuration/) calls its own `kindnetd` and explains how to change it; Lesson 7 comes back to this, because whether a `NetworkPolicy` is enforced or not depends on the network.

One component is missing from the list: the `kubelet`. It is not a Pod. It is a regular program on the node, and you can see it by looking at the processes **inside** the node:

```text
$ docker exec curso-k8s-l0-control-plane sh -c "ps -eo comm | grep -E '^(kubelet|containerd|kube-|etcd)' | sort"
containerd
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
etcd
kube-apiserver
kube-controller
kube-proxy
kube-scheduler
kubelet
```

`kubelet` and `containerd` are node processes. The others (`etcd`, `kube-apiserver`, etc.) are containers that `containerd` started, and each `containerd-shim` is a small helper process that watches over containers. In this run there are nine, one per Pod, because the `runc` *shim* groups the containers of the same Pod into a single process; but that relationship is decided by the *runtime*, so do not count Pods by counting *shims* ([containerd, “Runtime v2”](https://github.com/containerd/containerd/blob/main/docs/runtime-v2.md)). (The name `kube-controller` appears cut off because `ps` shows only the first fifteen characters of the program name.)

#### 0.3.4 The chicken and the egg

Here is a riddle. Almost all Pods are born the same way: a controller (the ReplicaSet one, for instance) writes them to the `kube-apiserver`, the `kube-scheduler` finds the ones that do not have a node yet and picks one for each Pod, and that node's `kubelet` starts them. The `kube-scheduler` does not create Pods: it assigns them ([kubernetes.io, “Kubernetes Scheduler”](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)). But the `kube-apiserver` is itself a Pod. Who started the API server's Pod before the API server existed?

The answer is in a folder on the node:

```text
$ docker exec curso-k8s-l0-control-plane ls /etc/kubernetes/manifests
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

There are four manifests, one per component of the control plane. The `kubelet` reads that folder directly, without asking anyone, and starts whatever it finds. These Pods are called **static Pods**: the `kubelet` manages them from files, not the API server ([kubernetes.io, “Create static Pods”](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)). What you see with `kubectl get pods -n kube-system` is a mirror of them that the `kubelet` publishes to the API so that you can see them. That is why their names end with the node's name, and why they do not have the random suffix of Pods created by a ReplicaSet.

You will not touch that folder in this course. But now you know why the control plane “starts itself”, and what to ask if one day it does not.

#### 0.3.5 The full journey of a `kubectl apply`

With the components in view, this is the journey of what happened in 0.2.3, from end to end:

1. `kubectl` reads `fig00_02.deployment.yaml` and sends it to the **`kube-apiserver`**, over HTTPS.
2. The `kube-apiserver` checks who you are and whether you have permission, validates the object and saves it in **`etcd`**. It answers `deployment.apps/espera created`. Up to here there is not a single container.
3. The Deployment controller, inside the **`kube-controller-manager`**, sees a new Deployment with no ReplicaSet and creates one.
4. The ReplicaSet controller sees a ReplicaSet that asks for three Pods and has none, and creates three Pod objects, still with no node assigned.
5. The **`kube-scheduler`** sees three Pods with no node, picks one for each and records it on the Pod.
6. The **`kubelet`** on the chosen node sees that it has Pods assigned, asks **`containerd`** to start the containers, and reports their status to the `kube-apiserver`.
7. `kubectl rollout status`, which was polling, sees the three available Pods and writes `successfully rolled out`.

Notice that no component gives orders to another. Each one watches the objects it cares about and acts when the current state does not match the desired one. If a component goes down for a while, when it comes back it finds what is pending and does it. That is why the design withstands failures: there is no chain of calls that breaks halfway through.

### 0.4 An imperative command versus a declaration

#### 0.4.1 The two ways of talking to the cluster

`kubectl` lets you work in two ways, and the documentation distinguishes them carefully ([kubernetes.io, “Kubernetes Object Management”](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/)):

- **Imperative commands**: you tell the cluster what to do, with a verb. `kubectl create deployment`, `kubectl scale`, `kubectl delete`. They are fast, and the documentation recommends them “for getting started or for a one-off task”. Their problem: they leave no record. The only thing that knows how the object is configured is the cluster itself.
- **Declarations** (*declarative object configuration*): you write a file with the desired state and hand it over with `kubectl apply -f`. The file is saved in Git, reviewed before being applied, and if the cluster is lost, you apply it again and everything is back the way it was.

This course uses declarations for everything that matters. Imperative commands appear only for looking (`get`, `describe`, `logs`) and for throwaway experiments.

#### 0.4.2 What happens when they are mixed

The documentation has a short, stern warning: “a Kubernetes object should be managed using only one technique. Mixing and matching techniques for the same object results in undefined behavior”. In the tour they were mixed on purpose, so that you can see one of those behaviors. First, an imperative command: scaling up from three to five copies.

```text
$ kubectl scale deployment espera --replicas=5
deployment.apps/espera scaled

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/5     5            3           3s
```

The cluster obeyed: now it wants five (`3/5` means “three ready out of five desired”; the other two are starting). But the file `fig00_02.deployment.yaml` still says `replicas: 3`. Now the cluster and the file **do not match**, and nothing warns you. To see it, there is `kubectl diff`, which compares the file against what is in the cluster without changing anything:

```text
$ kubectl diff -f fig00_02.deployment.yaml
@@ -6,14 +6,14 @@
     kubectl.kubernetes.io/last-applied-configuration: |
       {"apiVersion":"apps/v1","kind":"Deployment","metadata":{"annotations":{},"name":"espera","namespace":"default"},"spec":{"replicas":3,"selector":{"matchLabels":{"app":"espera"}},"template":{"metadata":{"labels":{"app":"espera"}},"spec":{"containers":[{"image":"registry.k8s.io/pause:3.10","name":"espera","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}}],"securityContext":{"runAsNonRoot":true,"runAsUser":65535,"seccompProfile":{"type":"RuntimeDefault"}}}}}}
   creationTimestamp: "2026-10-21T07:52:14Z"
-  generation: 2
+  generation: 3
   name: espera
   namespace: default
   resourceVersion: "587"
   uid: 0e26d2f6-3277-4f4f-9dc0-592b883974f8
 spec:
   progressDeadlineSeconds: 600
-  replicas: 5
+  replicas: 3
   revisionHistoryLimit: 10
   selector:
     matchLabels:
```

(The first three lines of output were omitted; they only name two temporary files whose paths change on every run, and they are complete in `recorrido.salida.txt`.)

It is a *diff* like Git's: the line with `-` is what is in the cluster, the line with `+` is what would be left if you applied the file. The detail that matters is `-  replicas: 5` / `+  replicas: 3`: if you apply the file, **the two copies added by the command are lost**. The `generation` line is a counter that goes up every time the desired state changes; and the long annotation, `last-applied-configuration`, is the copy that `kubectl apply` saves of the last file you applied, so it knows which fields are “its own”. (A useful detail: `kubectl diff` exits with code 1 when it finds differences, according to its own help text; it is not a failure, it is the answer.)

The file was applied:

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera configured

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/3     3            3           4s
```

Back to three. The file won, because `replicas` is a field that the file declares. The lesson is not “imperative commands are bad”; it is that **if you have a file, the file is the truth**, and a command that contradicts it lasts until the next `apply`. Imagine that someone else ran that command at night to weather a traffic spike, and in the morning you apply the file without looking. That is why, in this course, before applying over something that already exists you look at `kubectl diff`.

### 0.5 The map from Docker to Kubernetes

Almost everything you know from Docker has an equivalent in Kubernetes. It is not identical, but the map saves you half the course:

| In Docker | In Kubernetes | Where you see it in the course |
|---|---|---|
| an image | the **same** image | Lesson 2 (`kind load docker-image`) |
| `docker run` of a container | a **Pod** (and almost never alone: inside a Deployment) | Lesson 2 |
| `--restart always` | the **Deployment** and its ReplicaSet, which replace missing Pods on a node where they fit | Lesson 2 |
| `docker compose up --scale revisor=3` | `replicas: 3` in the Deployment | Lesson 2 |
| `-p 8080:8080` | a **Service**, and `kubectl port-forward` to test from your machine | Lesson 3 |
| the service name on Compose's network | the **cluster DNS**: `revisor.<namespace>.svc` | Lesson 3 |
| `-e` and `--env-file` | **ConfigMap** and **Secret** | Lesson 4 |
| `HEALTHCHECK` in the Dockerfile | startup, readiness and liveness **probes** | Lesson 5 |
| `--memory` and `--cpus` | `resources.requests` and `resources.limits` | Lesson 5 |
| `--user`, `--read-only`, `--cap-drop ALL` | `securityContext` | Lesson 2 |
| a named volume | a **PersistentVolumeClaim** | Lesson 8 |
| a container that runs and exits | a **Job**; on a schedule, a **CronJob** | Lesson 8 |
| the `compose.yaml` file | YAML manifests, put together with **Kustomize** | Lessons 4 and 10 |

And there are things that **have no equivalent** in Docker, because they only make sense when there are several machines and several people: the *scheduler* that picks a machine; **Namespaces**, which separate teams or projects inside the same cluster; permissions per service account (**RBAC**); network policies between Pods; and automatic scaling with load. Those are Lessons 7 and 9.

A question that always comes up: if the nodes do not use Docker, do the images you built with Docker still work? Yes. Kubernetes stopped talking directly to Docker Engine in version 1.24 ([kubernetes.io, historical context of dockershim](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/)), but that did not touch images. The official blog explains it like this: “the image that Docker produces isn't really a Docker-specific image—it's an OCI (Open Container Initiative) image”, and `containerd` knows how to pull and run it ([kubernetes.io, “Don't Panic: Kubernetes and Docker”](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/)). The tour confirms it: the node's `CONTAINER-RUNTIME` column says `containerd://2.3.4`.

### 0.6 What kind is and what it is NOT

#### 0.6.1 Kubernetes inside Docker

**kind** stands for *Kubernetes IN Docker*. Its page describes it in one sentence: “a tool for running local Kubernetes clusters using Docker container ‘nodes’”, and adds that it “was primarily designed for testing Kubernetes itself, but may be used for local development or CI” ([kind.sigs.k8s.io](https://kind.sigs.k8s.io/)).

The “nodes that are containers” part can be seen with no tricks. From Kubernetes, the cluster has one node:

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l0-control-plane   Ready    control-plane   25s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

And from Docker, that same node is a container:

```text
$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l0 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l0-control-plane   kindest/node:v1.37.0   127.0.0.1:60004->6443/tcp
```

The same name, `curso-k8s-l0-control-plane`. The `kindest/node` image carries a complete Debian system inside, with `systemd`, the `kubelet` and `containerd`: it is a simulated “machine”, packaged as a container. Inside it, `containerd` runs the containers of your Pods. They are containers inside a container. (The `--filter label=...` filter was used to list only the containers of this cluster; if there are other containers on your machine, they do not show up.)

Look at two columns of `get nodes`. `OS-IMAGE` says Debian, even if your system is Mint: it is the system **of the node image**. But `KERNEL-VERSION` shows the kernel **of the machine running Docker**, because containers do not bring their own kernel: they all use the host's. That column is the first clue to what kind is not.

#### 0.6.2 What a kind cluster proves and what it does not

kind runs real Kubernetes: the same `kube-apiserver`, the same `etcd`, the same *scheduler*, installed with `kubeadm`, the official tool ([kind design](https://kind.sigs.k8s.io/docs/design/initial/)). Among its design goals is passing all of Kubernetes's conformance tests. Everything you learn about the **API**—Deployments, Services, ConfigMaps, probes, permissions—holds true the same way in a production cluster.

What is not the same is **what lies underneath**. This table is the one worth keeping handy during the course:

| What you test in kind | Does it prove it? | Why |
|---|---|---|
| That your manifests are valid and do what you think | **Yes** | it is the same API and the same Kubernetes code |
| That your Pods are reborn when they die | **Yes** | the controller is the same |
| That your permissions (RBAC) and the `restricted` level work | **Yes** | the `kube-apiserver` enforces them, just like in production |
| That your service survives a machine going down | **In part** | `docker stop` on a node looks similar, but all three “nodes” share your machine, your disk and your kernel: if your computer goes down, everything goes down |
| That your `NetworkPolicy` blocks traffic | **It depends** | the network (CNI) enforces it, not Kubernetes; Lesson 7 measures it live |
| That your service handles a given load | **No** | the nodes share your processor and your memory; the numbers do not carry over to another machine |
| That a `LoadBalancer` gives you a public IP | **No** | kind does not come with a load balancer; a separate component is needed ([Cloud Provider KIND](https://kind.sigs.k8s.io/docs/user/loadbalancer/)), and Lesson 6 verifies it |
| That your data is safe | **No** | kind's default storage (a provisioner called `local-path-provisioner`, which kind installs when creating the cluster) stores data inside the node itself, which is a container on your machine; Lesson 8 measures what is lost and when |
| That the control plane tolerates failures | **No** in this course | kind allows several control-plane nodes, but on a single machine that tests the configuration, not real fault tolerance |

Honest summary: **kind proves that you understand Kubernetes; it does not prove that your system is ready for production.** Lesson 10 ends, precisely, with the list of what is missing.

#### 0.6.3 A real example of “they share your machine”

The “nodes share your kernel” point is not an academic detail, and preparing this lesson proved it unintentionally. The first time, we tried to create the cluster with three nodes, like the one in Lesson 1. `kind` said everything had gone fine, including the line `✓ Joining worker nodes`. But `kubectl get nodes` showed a single node, and the `kube-proxy` Pod was in `Error` state. Its log said:

```text
"command failed" err="failed complete: fsnotify watcher init: too many open files"
```

And the `kubelet` on the worker nodes, inside its container, was stopping with:

```text
"Failed to start cAdvisor" err="inotify_init: too many open files"
```

The cause: Linux programs that watch for file changes use a **kernel** resource called `inotify`, and the kernel has a limit on how many watchers each user can open. On that machine it was set to 128 (`fs.inotify.max_user_instances = 128`). Each kind node starts its own `kubelet` and its own `kube-proxy`, all against **the same kernel**, and between the three of them they exhausted the limit. With a single node, it was enough.

Kind's known-issues guide describes this exact problem: Ubuntu ships with that limit set to 128, “which is insufficient to create a cluster with many nodes”, and recommends raising it to 512 ([kind, “Known Issues”](https://kind.sigs.k8s.io/docs/user/known-issues/)). Linux Mint 22 is based on Ubuntu 24.04 ([Linux Mint, release notes for 22](https://www.linuxmint.com/rel_wilma.php)), so the same thing is likely to happen on your machine. That is why Lesson 1 adjusts that limit **before** creating the course's cluster. And that is why this lesson uses a single node.

The proof that this was the cause: on the same machine the limit was raised to 512 and the three-node cluster was created again, without changing anything else. This time all three became ready, each with its `kube-proxy` running (the script is `tres-nodos.sh` and its full output is `tres-nodos.salida.txt`):

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l0-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l0-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l0-worker2         Ready    <none>          19s   v1.37.0
```

Two lessons come out of this. The first: three kind “machines” are three processes on a single machine, and they share its limits. The second, more general: **a command that prints “✓” does not prove that the system ended up healthy**. You check the state (`kubectl get nodes`, `kubectl get pods -A`) before taking anything for granted.

### 0.7 The versions

Kubernetes releases a minor version roughly **three times a year** ([kubernetes.io, “Kubernetes Release Cycle”](https://kubernetes.io/releases/release/)), and maintains the three most recent ones at a time, each with about **one year** of fixes ([kubernetes.io, “Releases”](https://kubernetes.io/releases/)). This is what that page published on October 21, 2026:

| Minor version | Latest patch | End of support |
|---|---|---|
| **1.37** | 1.37.1 | October 28, 2027 |
| 1.36 | 1.36.5 | June 28, 2027 |
| 1.35 | 1.35.9 | February 28, 2027 |
| 1.34 | 1.34.12 | October 27, 2026 |

(The same page says that “the most recent three minor releases” are maintained while also listing 1.34 with its end-of-life date; on that date it had six days left.)

The course uses **Kubernetes 1.37**, the latest. There are two different numbers you should not confuse:

- **The cluster runs 1.37.0.** It is the version that comes in the default node image of kind v0.33.0. In `kubectl get nodes` it appears in the `VERSION` column: `v1.37.0`.
- **`kubectl` is 1.37.1.** It is the tool on your machine. The official policy says that `kubectl` works with an API server up to **one minor version** older or newer ([kubernetes.io, “Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/)): with a 1.37 cluster, `kubectl` 1.36, 1.37 and 1.38 work. The patch difference does not matter.

And one more: **the node image is pinned by its digest**. The release notes for kind v0.33.0 publish, for each Kubernetes version, the image with its `sha256` digest, and state that you should use it to get the image built for that release of kind ([kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). That is why the tour's configuration file writes it in full:

```yaml
# fig00_01.kind.yaml — el clúster de prueba de la Lección 0.
# Un solo nodo, que hace a la vez de plano de control y de nodo de trabajo.
# La imagen del nodo va fijada por su huella (sha256), copiada de las notas de la
# versión v0.33.0 de kind. El clúster del curso (tres nodos) llega en la Lección 1.
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

A tag like `v1.37.0` can be moved by whoever publishes the image; a digest cannot. If someone replaced the image with another, the digest would stop matching and the download would fail. It is the same habit Lesson 1 applies to the `kubectl` and `kind` binaries.

### 0.8 What comes in the rest of the course

All of the above is put into practice in the following lessons. Each one adds a piece to the `revisor` in the cluster:

| Lesson | What is added | Which idea from this lesson it puts to work |
|---|---|---|
| 1 | You install `kubectl` and `kind` and create the three-node cluster | the `inotify` adjustment from 0.6.3; contexts and the habit of checking them |
| 2 | The `revisor` as a Deployment | the Deployment, ReplicaSet and Pod chain from 0.2.3 |
| 3 | A Service and its name in DNS | `kube-proxy` and `coredns` from 0.3.3 |
| 4 | Configuration without rebuilding | the map from `-e` to ConfigMap from 0.5 |
| 5 | Probes, resources and graceful shutdown | the `kubelet` watching and the *scheduler* leaving a Pod `Pending` |
| 6 | Publishing to the outside | the `LoadBalancer` that kind does not include (0.6.2) |
| 7 | Namespaces, permissions and network | the network that depends on the CNI (0.3.3 and 0.6.2) |
| 8 | Data and tasks | storage that lives inside the node itself (0.6.2) |
| 9 | Scaling and updating without downtime | another controller, the one that adjusts `replicas` for you |
| 10 | Everything in a single `kubectl apply -k` | the file as the truth (0.4) |

## The error you will see

This lesson has one main error, which you will see as soon as something is not connected, and one **silent** error, which is more dangerous.

**The main error: `The connection to the server localhost:8080 was refused`.** At the end of the tour the cluster was deleted and an attempt was made to use it:

```text
$ kubectl config current-context
error: current-context is not set

$ kubectl get nodes
E1021 01:52:19.535319   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.535953   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.536970   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.537419   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.538619   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
```

It reads from bottom to top, because the last line is the summary: “the connection to the server `localhost:8080` was refused — did you specify the right host or port?”. The five lines with `E1021` are retries, one per attempt to discover what object types exist; they say the same thing and can be ignored.

The clue is in the first command: **there is no active context**. A **context** is the entry in `kubectl`'s configuration file (the `kubeconfig`) that says which cluster to talk to and with which credential. `kind` added one when creating the cluster and removed it when deleting it. Without a context, `kubectl` does not know where to go and tries a default address, `localhost:8080`, where nobody is listening. The message does not mean “your cluster went down”: it means **“I do not know which cluster is yours”**. It is fixed by giving it a context, which in this course is always the one `kind` creates (Lesson 1).

**The silent error: the wrong context.** Now imagine the opposite: there is a context, but it is not the one you think. Your computer has a cluster configured from work, from school or from a previous project, and that is the active one. You type `kubectl delete deployment revisor` thinking of your kind cluster. The cluster answers `deployment.apps "revisor" deleted`, with no error, no warning. You deleted it **somewhere else**.

That error cannot be read because it produces no message. It can only be prevented, with a habit: **before every command that changes something, `kubectl config current-context`**. In the tour, the answer was this, and only after seeing it did we continue:

```text
$ kubectl config current-context
kind-curso-k8s-l0
```

The `recorrido.sh` script does it on its own: before every `kubectl`, it compares the active context against `kind-curso-k8s-l0`, and if it does not match, it stops. In addition, it gives kind its own temporary `kubeconfig` file, so your usual configuration is not even touched. And it only deletes what it created itself: if a cluster named `curso-k8s-l0` already exists when it starts, it stops without touching it, and if it fails halfway through, on exit it deletes only the cluster that run managed to create. Lesson 1 teaches you how to do the same by hand.

## The security habit of the lesson: what a local cluster protects against and what it does not

The course's table of habits assigns a single one to this lesson: **knowing what a local cluster protects against and what it does not**. The tour looked at three things.

**First: the API server only listens on your own machine.**

```text
$ docker inspect curso-k8s-l0-control-plane --format 'privilegiado={{.HostConfig.Privileged}}  puerto_api={{json .NetworkSettings.Ports}}'
privilegiado=true  puerto_api={"6443/tcp":[{"HostIp":"127.0.0.1","HostPort":"60004"}]}
```

Port 6443 of the node, where the `kube-apiserver` listens, is published on `127.0.0.1`: the address reachable only from your own computer. Nobody on your network can talk to your cluster. Kind's configuration guide says this can be changed, and strongly advises against it: it recommends leaving `127.0.0.1` “for security reasons” and “not exposing kind to anything other than the local loopback interface” ([kind, “Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/)). What it protects against: access from outside.

**Second: your `kubeconfig` is the master key.**

```text
$ kubectl auth whoami
ATTRIBUTE                                           VALUE
Username                                            kubernetes-admin
Groups                                              [kubeadm:cluster-admins system:authenticated]
```

(The `Extra` line with the credential's fingerprint was omitted here; it is in `recorrido.salida.txt`.) The user you work with is `kubernetes-admin`, from the `kubeadm:cluster-admins` group: **full administrator** of the cluster. The credential lives in the `kubeconfig`, in the `client-certificate-data` and `client-key-data` fields, which `kubectl config view` hides with `DATA+OMITTED` precisely because they are secrets. In a local cluster the potential damage is smaller, but the `kubeconfig` is still an administrator credential, and in a real cluster it is equivalent to the administrator password: in both cases you do not paste it into a chat or commit it to a repository. Lesson 7 creates an account with minimal permissions for the `revisor`, because the `revisor` must not hold this key.

**Third: the node is a privileged container.** The same `docker inspect` says `privilegiado=true`. For a container to pose as a complete machine, with its own `systemd` and its own `containerd`, it needs almost all of the host's powers. That means **kind is not a security boundary**: a kind cluster does not isolate your computer from whatever runs inside it. What it does not protect: your machine from what you put into the cluster. That is why, in this course, only images you know run in kind: the `revisor`'s, the test service's and the official Kubernetes ones.

All three together give the rule: a kind cluster is well protected **toward the outside** and protects nothing **toward the inside**. It is a laboratory, not a safe.

## Common mistakes

**Deleting a Pod to “shut down” something.** The ReplicaSet replaces it in a second, as you saw in 0.2.4. To shut it down, you change the desired state (`replicas: 0`) or delete the Deployment.

**Running imperative commands on something managed with files.** A `kubectl scale` or a `kubectl edit` on an object that lives in Git lasts until the next `apply`, and the next person who applies will not know it existed. If the change is worth keeping, you make it in the file.

**Applying without looking at `kubectl diff`.** It is the only way to know what is going to change before it changes. It costs one command.

**Not checking the context.** It is the silent error from “The error you will see”. On a machine with a single cluster it seems unnecessary; as soon as there are two, it is the difference between an experiment and an incident.

**Believing that kind proves production readiness.** That your service withstands a “node” going down in kind says nothing about how it withstands a real machine going down, or real load, or a real disk. Kind proves that you understand the API.

**Trusting the green checkmark.** `kind create cluster` printed `✓ Joining worker nodes` with two nodes that never managed to join (0.6.3). After creating something, you look at its state.

**Typing a Pod's name by hand.** The suffix is random and changes every time the Pod is reborn. You look it up by label (`-l app=...`).

**Copying a tutorial without looking at the date.** Kubernetes changes three times a year. What was retired stays on the internet: tutorials that install Docker inside the nodes (dockershim was removed in 1.24) or that use `ingress-nginx`, which the Kubernetes project retired in March 2026: no new releases and no security fixes ([kubernetes.io, “Ingress NGINX Retirement”](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)). Lesson 6 explains what is used instead.

## Exercises

The exercises in this lesson do not require a cluster. The first and second are answered by reading the outputs in the lesson; the third is answered **before** running anything and checked after Lesson 1 with `ejercicio3.sh`; the fourth is written in your own words. Write down your answers in the [logbook](bitacora.md) before looking at the solutions.

### Exercise 1 — Friday night (project)

Go back to the opening scene. For each of these things that were lost with the server, say which Kubernetes object or component would have saved or solved it, using the map in 0.5:

1. Having three copies of the `revisor` instead of one.
2. Having someone bring the copies up on another machine when the first one went down.
3. The environment variables with the list of services to check.
4. The port through which it is reached.
5. “How it was started”, which lived in a terminal's history.

### Exercise 2 — Who did it?

For each of these facts from the tour, say which component from 0.3 is responsible:

1. The Deployment `espera` was saved and `kubectl` answered `created`.
2. The ReplicaSet `espera-68b9d575f7` appeared.
3. Each of the three Pods was assigned to the node `curso-k8s-l0-control-plane`.
4. The Pods' containers started inside the node.
5. When `espera-68b9d575f7-9gbtr` was deleted, `espera-68b9d575f7-fjx8v` appeared.
6. The Pod `kube-apiserver-curso-k8s-l0-control-plane` existed before there was an API server to create it.

### Exercise 3 — Predict before running

Without running anything, predict what the cluster answers in each case. After Lesson 1, check it with `programas/00-que-es-kubernetes/ejercicio3.sh`, which creates a test cluster, runs the four cases and deletes it.

1. The Deployment `espera` has `replicas: 3`. You delete **all three** Pods with `kubectl delete pods -l app=espera`. How many Pods are there ten seconds later?
2. You run `kubectl scale deployment espera --replicas=1` and then `kubectl apply -f fig00_02.deployment.yaml`. How many replicas are left?
3. You run `kubectl delete deployment espera`. What happens to the ReplicaSet and to the Pods?
4. You delete the cluster with `kind delete cluster --name curso-k8s-l0` and run `kubectl get pods`. What message do you expect?

### Exercise 4 — Kind in five sentences

A colleague asks you: “if on my laptop the `revisor` in kind survives me shutting down a node, can I already say that in production it survives too?”. Answer her in five sentences at most, using the words *container*, *kernel*, *API* and *production*. Without looking at the lesson.

## Solutions

### Solution 1

1. **Three copies:** the `replicas: 3` field of a **Deployment**; the **ReplicaSet** it creates is the one that counts to make sure there are three.
2. **Bringing them up on another machine:** the **ReplicaSet** replaces the missing Pods, the **`kube-scheduler`** picks a live node for each one and that node's **`kubelet`** starts them. With the 300-second wait from 0.2.5, unless there are replicas on other nodes that keep serving requests in the meantime.
3. **The environment variables:** a **ConfigMap** (and a **Secret** if any of them is confidential), Lesson 4.
4. **The port:** a **Service**, Lesson 3.
5. **“How it was started”:** the **manifest**, saved in a file and in Git, and applied with `kubectl apply`. It is the answer that matters most: the knowledge stops living in a person or in a terminal and stays written down. The cluster saves it in `etcd`, and you save it in your repository, so it can be rebuilt even if the entire cluster is lost.

### Solution 2

1. The **`kube-apiserver`**, which validates the object and saves it in **`etcd`**.
2. The Deployment controller, inside the **`kube-controller-manager`**.
3. The **`kube-scheduler`**. (In a single-node cluster there is not much to choose from, but it still makes the decision.)
4. The node's **`kubelet`**, which asks the *runtime*, **`containerd`**, to do it.
5. The ReplicaSet controller, inside the **`kube-controller-manager`**. It left a record of it in the `SuccessfulCreate` event.
6. The **`kubelet`**, from the file `/etc/kubernetes/manifests/kube-apiserver.yaml`: it is a **static Pod** (0.3.4).

### Solution 3

All four were measured with `ejercicio3.sh`; its full output is in `ejercicio3.salida.txt`.

1. **Three.** The ReplicaSet sees zero Pods where there must be three and creates three new ones, with new suffixes. Deleting all of them does not change the desired state. In the run, the three deleted ones were `khb2n`, `phxml` and `srfng`, and ten seconds later there were three different ones: `kcvgl`, `qbnbx` and `qz6pc`.
2. **Three.** The imperative command scaled it down to one, but `replicas: 3` is in the file, and `apply` enforces it again, just like in 0.4.2 with five. If before the `apply` you run `kubectl diff -f fig00_02.deployment.yaml`, you see `-  replicas: 1` / `+  replicas: 3`.
3. **All three levels are deleted.** The ReplicaSet belongs to the Deployment and the Pods belong to the ReplicaSet; when you delete the owner, Kubernetes deletes what depends on it. Five seconds later, `kubectl get replicaset,pods -l app=espera` answered `No resources found in default namespace.` Here the service really is shut down, because the desired state disappears.
4. `The connection to the server localhost:8080 was refused - did you specify the right host or port?`, preceded by several `E…` retry lines. Kind removed the context when deleting the cluster, and without a context `kubectl` tries `localhost:8080`. Watch out: the script uses its own `kubeconfig` in which only the course's cluster existed. If you have other clusters configured in yours, the answer depends on which one remains active, and you could be talking to another cluster without knowing it: that is why you check with `kubectl config current-context` instead of assuming.

### Solution 4

One possible answer: “Not yet. In kind, each node is a *container* on your laptop, so all three nodes share your disk, your memory and your *kernel*: shutting one down looks like losing a machine, but if your laptop goes down, everything goes down. What you did prove is that your *API* configuration is right: the replicas, their spread and their replacement work the same in any Kubernetes. To claim it for *production*, you still need to test it on genuinely separate machines, with their own network, disks and load. Kind proves that you understand it; production is proved in production.”

## How I know I got it

- [ ] You explain, using the Friday night scene, why `--restart always` is not enough when the machine goes down.
- [ ] You draw from memory the control plane and a node, with their seven components, and say what each one does in one sentence.
- [ ] You recount the seven steps of 0.3.5, from `kubectl apply` to the running container.
- [ ] You know why the `kube-apiserver` can be a Pod without anyone asking the API to create it.
- [ ] Given `kubectl scale` followed by `kubectl apply`, you predict what number of replicas is left.
- [ ] You translate at least five Docker concepts to Kubernetes and name one with no equivalent.
- [ ] You state two things a kind cluster proves and three that it does not.
- [ ] Given `The connection to the server localhost:8080 was refused`, you say what it means without looking it up.
- [ ] After Lesson 1, you run `programas/00-que-es-kubernetes/recorrido.sh` and check against `recorrido.salida.txt` what does not change between runs: one `Ready` node; the Deployment at `3/3` and its ReplicaSet with `3` desired, `3` current and `3` ready; three `Running` Pods after deleting one; the `diff` showing `replicas: 5` against `replicas: 3`; the user `kubernetes-admin`; and the final `localhost:8080` error. The generated names, ages, IPs, ports, events, the progress of `kind` and `rollout`, and the temporary paths change on every run: you observe them, you do not compare them.

## Summary

Answer without looking at the lesson:

1. Which question does Docker answer and which question does Kubernetes answer?
2. What is a control loop? Explain it with the thermostat.
3. What is the difference between a Deployment, a ReplicaSet and a Pod?
4. What does `kubectl apply` answer when it creates a Deployment, and why does that answer not mean there are containers running?
5. How long does Kubernetes wait before replacing the Pods of a node that stopped responding? Why does it not wait zero?
6. What is a static Pod and who starts it?
7. What happens if you run an imperative command that contradicts your file and then apply the file?
8. What does your machine's kernel have to do with a three-node kind cluster failing to start?
9. What does a kind cluster protect against, and what does it not?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, “Overview”](https://kubernetes.io/docs/concepts/overview/): the definition of Kubernetes, the origin of the name, the abbreviation K8s, the year it was released and the list of what Kubernetes is not.
- [Kubernetes, “Controllers”](https://kubernetes.io/docs/concepts/architecture/controller/): the control loop, the thermostat and the desired state versus the current state.
- [Kubernetes, “Kubernetes Components”](https://kubernetes.io/docs/concepts/overview/components/): the components of the control plane and of the nodes, where the definitions in the table in 0.3.2 come from.
- [Kubernetes, “Pods”](https://kubernetes.io/docs/concepts/workloads/pods/): the definition of a Pod and why they are almost never created on their own.
- [Kubernetes, “Create static Pods”](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/): the static Pods that the `kubelet` reads from a folder.
- [Kubernetes, “Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): the automatic 300-second tolerations.
- [Kubernetes, “Kubernetes Object Management”](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/): imperative commands versus declarations, and the warning not to mix them.
- [Kubernetes, “Releases”](https://kubernetes.io/releases/) and [“Kubernetes Release Cycle”](https://kubernetes.io/releases/release/): the current versions, their end of support and the three-per-year rhythm.
- [Kubernetes, “Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/): which versions of `kubectl` work with which server.
- [Kubernetes, “Dockershim: The Historical Context”](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/) and [“Don't Panic: Kubernetes and Docker”](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/): why nodes no longer use Docker and why your images still work.
- [Docker, “Start containers automatically”](https://docs.docker.com/engine/containers/start-containers-automatically/): Docker's restart policies.
- [kind](https://kind.sigs.k8s.io/), [its initial design](https://kind.sigs.k8s.io/docs/design/initial/), [“Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/), [“Known Issues”](https://kind.sigs.k8s.io/docs/user/known-issues/) and [“LoadBalancer”](https://kind.sigs.k8s.io/docs/user/loadbalancer/): what kind is, what it was designed for, the API server address, the default network, the `inotify` limit and the load balancer it does not include.
- [Kubernetes, “Ingress NGINX Retirement: What You Need to Know”](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/): the retirement of `ingress-nginx` in March 2026.
- [kind v0.33.0, release notes](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0): the default node image and its digest.
- [Linux Mint 22, release notes](https://www.linuxmint.com/rel_wilma.php): Mint 22 is based on Ubuntu 24.04.

---

**Next:** [Lesson 1 — Installing kubectl and kind; your first cluster](01-instalacion-primer-cluster.md)
