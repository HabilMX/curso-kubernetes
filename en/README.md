# Kubernetes course with kind — deploy, configure, scale and protect a service on your own machine

**By Dorian Chávez, founder of Hábil and integration architect.**

**Who it is for:** anyone who has already taken our [Docker course](https://www.habil.mx/en/courses/docker/), or who packages services into containers fluently: you build images, run them, give them volumes and bring them up together with Compose. Intermediate level. You are not expected to have touched Kubernetes or to have a cluster: the course gives you a local one that is created and destroyed in minutes. Every concept is explained as it comes up, along with why it exists, not just how it is written.

**What you will know by the end:** how to deploy a service in a Kubernetes cluster and operate it (configure it, monitor it, publish it, limit it, store its data, scale it and update it without downtime); read what the cluster tells you when something fails (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) instead of deleting and trying again; and explain, plainly, how far your local cluster is from a production one.

**Where it comes from:** this course continues our [**Docker**](https://www.habil.mx/en/courses/docker/) course and uses its finished `revisor` image as its starting point. If you did not take that course, you need an image of an HTTP service that can report whether it is alive and that runs without being `root`; [Lesson 2](02-pods-deployments.md) tells you exactly what requirements it must meet.

**What you need before you start:** a computer with Linux Mint 22.x, Docker Engine running and administrator privileges (`sudo`). [Lesson 1](01-instalacion-primer-cluster.md) installs `kubectl` and `kind` and creates the cluster.

## The project you will build

The **`revisor`**: the HTTP server that queries a list of services **at once** and delivers its report, the same one from our [Go](https://www.habil.mx/en/courses/go/), [Rust](https://www.habil.mx/en/courses/rust/), [TypeScript](https://www.habil.mx/en/courses/typescript/) and [Docker](https://www.habil.mx/en/courses/docker/) courses; its server is written in Go and listens on port 8080 (`GET /salud`, `GET /api/estados`, configuration via environment variables, `healthcheck` subcommand). Here you no longer code it or package it: you **make it live in a cluster**. You deploy it with several replicas, make it discoverable by name, configure it without rebuilding the image, teach the cluster how to monitor it, publish it to the outside, isolate it with minimal permissions and a closed network, give it a place to store its report, turn it into a scheduled task and make it scale with load. At the end everything comes up with two `kubectl apply -k` commands—the platform and the project—and a wait between them.

It comes with the **test service that fails on purpose** from the Docker course (healthy, slow or down), because you truly understand a cluster when something breaks and you see what it does.

## The eleven lessons

| Lesson | | What you build | What you learn |
|---|---|---|---|
| 0 | [What Kubernetes is and what kind is NOT](00-que-es-kubernetes.md) | nothing yet (reading) | the control plane and the nodes; declaring the desired state and letting the cluster reach it; the map from Docker to Kubernetes; what kind tests and what it does not |
| 1 | [Installing kubectl and kind; your first cluster](01-instalacion-primer-cluster.md) | the course cluster: one control-plane node and two worker nodes | `kubectl` and `kind` with pinned version and checksum; the `inotify` adjustment; contexts and `kubeconfig`; creating, inspecting, deleting and recreating |
| 2 | [Pods and Deployments](02-pods-deployments.md) | the `revisor` running, with replicas that come back to life | `kind load docker-image`; the `ErrImagePull` triggered on purpose; Pod, ReplicaSet and Deployment; labels; `rollout`; `securityContext` from the first manifest |
| 3 | [Services and DNS](03-services-dns.md) | the `revisor` discoverable by name | `ClusterIP`; selectors and `EndpointSlice`; `port`, `targetPort` and `containerPort`; the cluster DNS; `port-forward`; a debugging Pod |
| 4 | [Configuration and secrets](04-configuracion-secretos.md) | the `revisor` configured without rebuilding | `ConfigMap` as environment variables (the `revisor` only reads variables) and `Secret` as a file, and why base64 is not encryption; Kustomize with generators and the *hash* that triggers the rollout |
| 5 | [Health checks, resources and graceful shutdown](05-salud-recursos-apagado.md) | a `revisor` the cluster knows how to monitor | startup, readiness and liveness probes; why `/salud` does not query anyone; `requests` and `limits`; `OOMKilled` and `Pending` on purpose; the shutdown grace period |
| 6 | [Getting into the cluster](06-entrar-al-cluster.md) | the `revisor` published to the outside | `LoadBalancer` with MetalLB and Gateway API with Envoy Gateway, installed inside the cluster; why not Cloud Provider KIND on a shared machine (it acts on every kind cluster); `Ingress` as a frozen API; why not `ingress-nginx`; what is exposed and through which entry point |
| 7 | [Isolating: namespaces, permissions and network](07-aislar-permisos-red.md) | its own namespace with rules | `Namespace`; Pod Security Admission at the `restricted` level; `ServiceAccount` and minimal RBAC with `auth can-i`; default-deny `NetworkPolicy` and its exceptions (if kind's CNI does not enforce it, the course installs Calico and says so) |
| 8 | [Data and tasks](08-datos-y-tareas.md) | the saved report and the `revisor` as a scheduled task | `PersistentVolumeClaim` and kind's storage class; `Job` and `CronJob`; file ownership with `fsGroup`; what is lost when deleting a Pod |
| 9 | [Scaling and updating without downtime](09-escalar-y-actualizar.md) | the `revisor` that scales replicas up and down with load | `metrics-server`; `HorizontalPodAutoscaler` and its formula; the scale-down window; `RollingUpdate`; `PodDisruptionBudget`; `rollout undo` |
| 10 | [The finished project and what changes in a real cluster](10-proyecto-final.md) | everything with two `kubectl apply -k` (platform and project) and a wait | Kustomize with base and *overlays*; review against the `restricted` level; Helm as a mention; what it lacks to be production-ready |

At the end of each lesson there are exercises with their solutions. And the [logbook](bitacora.md) is yours: write down there what was hard for you.

## Three principles that run through the whole course

**Security is not a lesson, it is a habit.** Lesson 7 brings together permissions, namespaces and network because that is where they are studied in depth, but the rest of the course already practices them from the first manifest:

| Lesson | The habit that is built |
|---|---|
| 0 | knowing what a local cluster protects against and what it does not |
| 1 | binaries with checksums; pinned node image; checking the context before every command that changes something |
| 2 | `securityContext` in the first Deployment: non-`root`, no privilege escalation, no capabilities, read-only filesystem, `seccomp` profile |
| 3 | `ClusterIP` by default; nothing is published without a reason; `port-forward` only to `127.0.0.1` |
| 4 | a `Secret` is not encrypted: it is not versioned, it is mounted as a file and marked immutable |
| 5 | `requests` and `limits` on every container; probes do not depend on external services |
| 6 | expose the minimum, through a named entry point, and state what is missing (encryption in transit) |
| 7 | a dedicated namespace, `restricted` level, minimal permissions, network closed by default |
| 8 | the `ServiceAccount` without mounted credentials if it does not need them; data with its owner |
| 9 | scaling limits; updates do not bring down the service |
| 10 | final review against the `restricted` level and the list of what a real cluster requires |

**Read before deleting.** When something does not start, the beginner's reflex is to delete it and apply it again. Here the reflex is different: `describe`, `logs`, `get events`. Each lesson deliberately triggers a typical failure and teaches you the order in which to read it, because that order is the craft.

**Only what is current is taught, and what has been retired is named so you can recognize it.** `ingress-nginx` stopped receiving maintenance in March 2026 and tutorials from two years ago still teach it; `Ingress` is a frozen API and Gateway API is its successor. The course tells you which is which. And every version is given with its date: the ones in this course were measured on October 7, 2026 (Kubernetes 1.37.1; kind v0.33.0, whose default node is 1.37.0). Anything that depends on an external component (MetalLB, Envoy Gateway, `NetworkPolicy` enforcement, `metrics-server` in kind) is verified live when writing each lesson and is not claimed beforehand.

## How you know you are done

The course does not end when you have read lesson 10, but when your project meets these seven things. They are design goals: they are measured and adjusted as the lessons are written, and each lesson repeats its own once measured.

1. **From a freshly created cluster, the `revisor` ends up running in three steps, always in the same order:** a `kubectl apply -k` for the platform (MetalLB and Envoy Gateway, with their CRDs), a `kubectl wait` until it is ready, and the project's `kubectl apply -k`. The order matters because CRDs and *webhooks* have to exist before the resources that use them. And `kind delete cluster` followed by the same three steps rebuilds it without you fixing anything by hand.
2. **The `revisor`'s namespace is at the `restricted` level** of Pod Security Admission and triggers no warnings when applied.
3. **You stop the container of a worker node** (`docker stop`) and the service keeps responding through the replica on the other node, **with a measured window**: for about 50 s—the time the cluster takes to declare the node lost (`node-monitor-grace-period`, 50 s by default)—the requests that land on the dead replica fail (measured with 2 replicas: 8 of 36). You can say what shortens or softens that window (replicas spread across more nodes, client retries, a shorter detection period in the control plane) and what does not (probes, which the failed node itself runs, nor `tolerationSeconds`, which only decides when the Pods are replaced). And an update with `preStop` loses no requests at all (measured: 0 of 819). When you bring the node back up, the cluster recovers on its own.
4. **You change the list of services in the `ConfigMap`** and the cluster performs the rollout on its own, without you rebuilding the image.
5. **Under load, `kubectl get hpa --watch` shows the replicas scale up, and minutes later scale down**, and you can explain why scaling down takes as long as it does.
6. **A Pod unrelated to the `revisor` cannot talk to it** (the `NetworkPolicy` blocks it; goal subject to the cluster enforcing it) and the `revisor`'s service account **cannot do anything it does not need** (`kubectl auth can-i` proves it to you).
7. **You can state, in writing, five reasons why what you built is not production-ready**, and what would be done about each one in a real cluster.
