# Lesson 7 — Isolating: namespaces, permissions and network

Friday, 5:50 in the afternoon. The data team has spent two weeks asking for a place to test their service, and your kind cluster has plenty of room. You told them yes. At 5:58 someone on the security team, who reviews what gets published before the weekend, sends you three questions in a row. One: “can one of their Pods read the `revisor`'s token?”. Two: “can it talk to the `revisor` without going through the entry point you published?”. Three: “can it ask the cluster API for the list of Secrets?”. You know the `revisor` runs as non-`root`, with probes, with limits and behind a named entry point. But those three questions are not about the `revisor`. They are about **what surrounds the `revisor`**, and you do not have a single measured answer. It is 6:00. The data team has already pasted their first Pod into the `default` namespace, which is where everything of yours lives.

The history of cloud security has many versions of this afternoon. On February 20, 2018, the security firm RedLock reported that it had found Tesla with a Kubernetes administration console left open, unprotected. According to RedLock itself, whoever got in that way found access credentials to an Amazon Web Services data bucket and put the cluster to work mining cryptocurrency. Tesla replied that the impact appeared to be limited to engineering test vehicles and that it fixed the problem within hours. The news report that tells the story is in this lesson's sources. That open door is not what this lesson studies. What it teaches is the question that comes **after** any open door, whether through carelessness or through another team's mistake: once inside, how far can whatever got in reach?

Until today, in your cluster, the answer is “as far as it likes”. This lesson puts walls around it, in four layers, and teaches you to **measure** each one with the most modest attacker there is: a Pod with `curl` that should not be able to do anything. The first decides **where each thing lives** (the namespace). The second decides **what is allowed to be created** (Pod Security Admission). The third decides **who can do what with the API** (service accounts and RBAC), and the fourth, **who can talk to whom** (network policies). When you finish, the three questions from 5:58 will have an answer with a command next to it.

**Time:** 2 × 45 min

**What you build:** a namespace of its own, `revisor`, with rules: the whole project lives there, the cluster rejects any Pod that does not meet the `restricted` level, each program has its own service account with no permissions and no mounted credentials (except a read-only account for looking), and the network is default-deny with six policies that open only what is needed

**What you learn:** what a namespace is and what it does **not** isolate; Pod Security Admission with its three modes and three levels, and how to read its rejections; `ServiceAccount`, `Role` and `RoleBinding` with minimal permissions and how to check them with `kubectl auth can-i`, with an impersonated request and from inside a Pod; `NetworkPolicy`: the model (open until a policy selects the Pod, and rules add up), who enforces them on kind (it is measured), what breaks with default-deny and what each of the six openings is for, removing them one by one; and how a route from another namespace attaches to the entry point (`allowedRoutes` and `ReferenceGrant`)

**Where you are coming from.** From [Lesson 6](06-entrar-al-cluster.md): the `revisor` runs with three replicas and the test service with one, with probes, `requests` and `limits`; MetalLB and Envoy Gateway are installed inside the cluster; the entry point is a `Gateway` called `revisor` with its `HTTPRoute`; and there is a direct `LoadBalancer` Service, `revisor-publico`, which this lesson removes. Everything lives in the `default` namespace. From [Lesson 5](05-salud-recursos-apagado.md) you bring the fact that probes are run by the node's `kubelet`, a detail that today decides whether the closed network takes the Pods down or not. From [Lesson 3](03-services-dns.md), the `depurar` Pod, the cluster DNS and the fact that a name lookup is network traffic like any other. And from [Lesson 2](02-pods-deployments.md), the `securityContext` that, since the first manifest, meets the `restricted` level without your having known it: today the cluster starts to demand it.

**What this lesson does not do.** It does not encrypt traffic: the entry point still speaks plain HTTP, and inside the cluster the Pods do not encrypt what they say to each other either. It does not install another network add-on: the course planned to install Calico if kind's network did not enforce policies, and section 7.5 measures that it does enforce them, so there is no need. It does not limit how many resources a namespace can create (`ResourceQuota` and `LimitRange`, which [Lesson 5](05-salud-recursos-apagado.md) named) nor install admission policies of its own. It does not store data or schedule tasks: that is [Lesson 8](08-datos-y-tareas.md), which will need two things from this lesson, a service account with no credentials for the task and the label `acceso-revisor: permitido` so that the task can talk to the `revisor`. And neither is it a security audit of a real cluster: the security-habit section says, with measurements, what this protects against and what it does not.

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1, the `kindest/node:v1.37.0` node image pinned by its digest, **MetalLB v0.16.1** and **Envoy Gateway v1.9.2**, on the three-node cluster from Lesson 1, called `curso-k8s-l7` here. The machine was an ARM-based Mac (`arm64`) with Docker Engine 29.2.1 inside an Ubuntu 24.04.4 virtual machine (Colima). The first line of `correr.salida.txt` records what the script can measure: `Docker 29.2.1 en Ubuntu 24.04.4 LTS (arm64)`; the script cannot see that the host machine is a Mac with Colima. It was **not** Linux Mint, which is the course's reference system. **This run used a Docker network of its own**, `curso-k8s-red-l7`, with the subnet `172.27.0.0/16`, because other lessons, each with its own MetalLB, were running at the same time on the same machine, and two MetalLBs with the same range on the same network step on each other (you saw this in Lesson 6). That is why the addresses of the nodes and of the entry point appear here as `172.27.…`. On your Mint, with the normal `kind` network, the entry point receives `172.18.255.200` and the nodes hang off `172.18.0.0/16`; the rest of the outputs do not change. `correr.sh` does both things: with the default `kind` network, and with a network of its own if you tell it which one with `CURSO_RED` and `CURSO_SUBRED`; in both cases it checks that the subnet is exactly the one you expect and stops if it is not (with a network of its own, before creating the cluster; with the `kind` network, right after creating it). Everything else that changes on your machine: the architecture, the name suffixes, the ages, each Pod's node, the Secret's name (the token is new on every run) and the milliseconds. The full tour is in [`programas/07-aislar-permisos-red/`](../programas/07-aislar-permisos-red): `correr.sh` creates the cluster, loads the two images into it, installs Lesson 6's platform, leaves everything as that lesson left it, goes through this one in order, runs Exercises 1 to 3 and deletes the cluster. The complete run took 26 minutes and 9 seconds, long because the machine was loaded with other clusters and because the lesson waits for the network; creating the cluster and waiting for it to be ready took 39 seconds, installing the platform 411 and deleting it 1, and Docker's disk was at 79 % at the start and at 77 % at the end. The waits for the installation and for the entry point (`speaker`, `Programmed`, the `viejo` Pod) carry generous timeouts (480, 360 and 300 seconds) because on a loaded machine the images take a while to download; if on yours a wait times out, do not go on blindly: repeat it, and look with `kubectl get pods -A` at what is missing. Its output is `correr.salida.txt`; it needs internet (the MetalLB and Envoy Gateway manifests are downloaded from their releases, pinned to their version). The waits are in plain sight: where the script waits, the output says so with a `kubectl wait`, a `rollout status` or a `sleep`. It uses port 18087 on your machine for a `port-forward` and stops before starting if that port is already taken.

## By the end you will be able to

- Explain what a namespace isolates (names and the scope of permissions) and what it does not (the network), and demonstrate it with a Pod in one namespace talking to a Service in another.
- Move the project from `default` to a namespace of its own with `kubectl apply -k`, and tell what lives inside a namespace from what applies to the whole cluster.
- Put a namespace at the `restricted` level with its labels, pin the policy version, and read line by line the rejection of a Pod that does not comply.
- Trigger a Deployment that gets created but ends up with no Pods because of Pod Security Admission, and find the reason in the ReplicaSet's events.
- Write a read-only `Role` and `RoleBinding`, check what they allow and what they deny with `kubectl auth can-i` and with a real request from a Pod, and explain why the `revisor` carries no mounted credentials.
- Close a namespace's network with a policy, measure what breaks (including DNS and the entry point), open only what is needed and say, for each of six policies, what would stop working if it were missing.
- Explain under what condition a default-deny `NetworkPolicy` protects anything, and check it in your cluster.
- Attach a route from another namespace to the entry point, and tell `allowedRoutes` (who may attach to the Gateway) from `ReferenceGrant` (who may be the destination of a route).

## The why before the how

Imagine an office building with a single long hallway and all the doors unlocked. Someone put signs on the doors (`datos`, `finanzas`, `revisor`) and it looks tidy. But a sign locks nothing: anyone who enters the building can open any door. That is your cluster today. The namespaces you already know are the signs. This lesson gives it keys, a set of house rules and doors with locks, and it does so in layers, because each layer answers a different question and fails in a different way:

1. **Where does each thing live?** The **namespace**. It groups objects, lets two teams use the same name without colliding, and is the unit to which permissions and rules are attached. It is not a network wall: that is measured in 7.5.
2. **What is allowed to be created?** **Pod Security Admission**. It is a guard at the door of the `kube-apiserver` that checks every Pod that wants to be born in a namespace and rejects it if it does not meet the level that namespace demands. It protects against the badly written Pod, not against the Pod that is already running.
3. **Who can do what with the API?** **Service accounts and RBAC**. Every program that runs in the cluster has an identity, and every identity has a list (empty by default) of verbs it may apply to certain objects.
4. **Who can talk to whom?** **Network policies**. Today every Pod can talk to every Pod. A policy changes that Pod by Pod, and it only works if the cluster's network enforces them.

The layers complement each other because they protect against different things. PSA prevents someone (or a slip of yours) from creating a container with more privileges than it should have. RBAC limits what a program does **with the API**. The network limits what it does **with the other Pods**. And the namespace is the place where all three apply. If one is missing, the others do not cover for it: a `restricted` Pod with no network policy can still talk to everyone, and a closed network with a generous service account lets a compromised Pod ask the API for everything that permission reaches.

The lesson has five parts of concepts and then the usual sections:

1. **The lesson's cluster** (7.1), with Lesson 6's platform and the starting point.
2. **A namespace of its own** (7.2): what it is, what it contains and the move.
3. **Pod Security Admission** (7.3): modes, levels, labels and the rejection you learn to read.
4. **Service accounts and minimal permissions** (7.4): `ServiceAccount`, `Role`, `RoleBinding`, `auth can-i`, and a real request from inside a Pod.
5. **The network** (7.5): the model, who enforces it, with no rules, default-deny, the openings and what each one is for.

This is the destination. At the end of 7.5, a Pod with the right label can talk to the `revisor`, a Pod without it cannot, and both answers come from commands you can repeat:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

## If you do not have the images from the Docker course

This lesson uses the same two images as Lessons 3 to 6: `curso-docker-revisor:1.6.0` and `curso-docker-prueba:1.0.0`. Check that you have them:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

For the other one, the same command with `curso-docker-prueba:1.0.0`. If either is missing, [Lesson 3](03-services-dns.md) explains how to build both from the Docker course repository. This lesson asks nothing new of either one. The support Pods (`depurar`, `intruso` and `lector`) use the `curl` image pinned by its digest, as in the earlier lessons; each node downloads it from the internet the first time.

## The concepts

### 7.1 The lesson's cluster

#### 7.1.1 Create it, with the context guard

This lesson creates its own cluster, `curso-k8s-l7`, with the three-node configuration from Lesson 1. Until now, in the earlier lessons, the context check was a line you copied in front of every command. Today it becomes a function, so that it is short and you do not forget it. Create it like this, from the root of the course repository:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L7_TMP="$(mktemp -d /tmp/curso-k8s-l7.XXXX)"
export KUBECONFIG="$L7_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: si abres otra terminal, la necesitas

# La guarda: se escribe una vez y va delante de cada comando que cambia algo.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l7 ] || { echo "contexto equivocado: no sigo"; return 1; }; }

# curso-k8s-l7 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l7 --config programas/07-aislar-permisos-red/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l7

# Desde aquí, todo se ejecuta dentro de la carpeta de la lección:
cd programas/07-aislar-permisos-red
```

The `ctx` function does one thing: it compares `kubectl`'s active context with `kind-curso-k8s-l7`. If they match, it prints nothing and exits successfully, and the `&&` lets the next command through. If they do not match, it prints “contexto equivocado: no sigo” (wrong context: I am not continuing) and exits with an error, and the `&&` **cuts the chain**: the command that changes something does not run. From here on, **every command in this lesson that changes something** (`apply`, `delete`, `patch`, `label`, `run`, an `exec` that deletes…) is written like this: `ctx && kubectl apply -k .`. In the outputs that follow, the line that starts with `$` shows only the `kubectl` command, without the `ctx &&`, so that it fits; the `correr.sh` script makes the same check before **every** `kubectl`, reads included, and stops if the context is not the lesson's. The reason for so much care you know from Lesson 1: a `delete -k` in the wrong context would delete objects from another cluster, and this lesson deletes and recreates quite a few.

Two coexistence checks, the same ones as in Lesson 6 (with a network of its own they are done before creating the cluster; with the default `kind` network, which is born with the first cluster, right after creating it): the `kind` network must be `172.18.0.0/16` (MetalLB's range comes from it) and nobody must already answer at `172.18.255.200`. If another cluster of yours with MetalLB is alive, wait for it to finish. `correr.sh` does them and stops if they fail; in this run it did them against the network of its own, `curso-k8s-red-l7`, which the “About the runs” section explains.

```text
$ kubectl config current-context
kind-curso-k8s-l7

$ kubectl get nodes -o wide | awk '{print $1, $2, $3, $6}' | column -t
NAME                        STATUS  ROLES          INTERNAL-IP
curso-k8s-l7-control-plane  Ready   control-plane  172.27.0.4
curso-k8s-l7-worker         Ready   <none>         172.27.0.2
curso-k8s-l7-worker2        Ready   <none>         172.27.0.3
```

The three nodes live on the Docker network of the run (`172.27.0.x`; on your Mint, `172.18.0.x`). `kubectl wait` and `kubectl get` change nothing, so they do not need the guard; everything else does.

#### 7.1.2 Lesson 6's platform, in three steps

Lesson 6 left two installations that do not belong to the `revisor` but to the cluster: MetalLB and Envoy Gateway. This lesson needs them because the project includes a `Gateway`. They are installed just as there, in the order you learned: platform, wait, project. The commands are the same as in section 6.9, and the output shows each wait:

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=480s | tail -1
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io crd/referencegrants.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
(en esta corrida el rango del archivo se cambió a 172.27.255.200-172.27.255.250, dentro de la red curso-k8s-red-l7)
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met
```

Two things you already know and one that changed. You already know that you have to wait for MetalLB's `controller` before giving it the range (the *webhook* has to be listening) and that the range and the `eg` class are applied last. What changed is the wait for the CRDs: this time it includes `referencegrants.gateway.networking.k8s.io`, a Gateway API type that Exercise 3 uses and that comes in the same bundle that Envoy Gateway installed.

About the parenthetical line of `kubectl apply -f infra/metallb-pool.yaml`: the course's file carries the range `172.18.255.200-172.18.255.220`, the one for your Mint. In this run, `correr.sh` changed that range, **with `sed` and on the fly**, to `172.27.255.200-172.27.255.250`, which falls inside the network of its own. That is the only change: the repository's file was not touched. On your machine it is applied as is.

#### 7.1.3 The starting point: Lesson 6, in `default`

The `punto-de-partida/` folder brings, without changing a comma, the manifests Lesson 6 ended with. You are already in the lesson's folder. The token is a dummy and is not versioned; it is generated on every run with the `umask` you already know, so that it is born with `0600` permissions, and it is copied into the lesson's folder because both `kustomization.yaml` files ask for it:

```bash
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
```

The parentheses and the `umask 077` are the habit from Lesson 4: the file is created closed from the first byte, not created open and closed afterwards. Now, with the `revisor`, `prueba`, the public Service and the entry point in `default`, this is what the cluster knows about the “before” state:

```text
$ /bin/ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=360s
gateway.gateway.networking.k8s.io/revisor condition met
```

With the nine objects created and the entry point `Programmed`, the state is Lesson 6's. Four readings of the “before” remain, the ones that will change by the end of the lesson:

```text
$ kubectl get namespaces
NAME                   STATUS   AGE
default                Active   11m
envoy-gateway-system   Active   11m
kube-node-lease        Active   11m
kube-public            Active   11m
kube-system            Active   11m
local-path-storage     Active   11m
metallb-system         Active   11m

$ kubectl get namespace default --show-labels
NAME      STATUS   AGE   LABELS
default   Active   11m   kubernetes.io/metadata.name=default

$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.serviceAccountName} | {.items[0].spec.automountServiceAccountToken} | {.items[0].spec.volumes[*].name}{"\n"}'
default |  | datos token kube-api-access-5q29h

$ kubectl auth can-i --list --as=system:serviceaccount:default:default | head -4
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
```

They read like this. The namespaces are the usual ones plus the two for the platform (`envoy-gateway-system` and `metallb-system`); `default` has no label other than the one the system gives it, `kubernetes.io/metadata.name`: no rules. The third command asks the `revisor`'s first replica (`.items[0]`; the three are equal because they come from the same template) three things: which account it runs with (`default`), whether it asked not to have credentials mounted (the `automountServiceAccountToken` field appears **empty**, that is, it said nothing) and which volumes it has: `datos`, `token` (the Secret from Lesson 4) and a third one with a random name, `kube-api-access-…`. That third one is the one nobody asked for: **the cluster mounted a credential for talking to the API into the `revisor`**, and the `revisor` does not talk to the API. It is the first thing this lesson removes. And the last command lists what the `default` account can do: almost nothing (create reviews about itself, which are “what can I do?” questions), but “almost nothing” is not the same as “nothing”, and 7.4 measures the difference.


### 7.2 A namespace of its own

#### 7.2.1 What it is and what it is not

A **namespace** is a named group inside the cluster. The [namespaces documentation](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) puts it in one sentence: namespaces “provide a mechanism for isolating groups of resources within a single cluster”, and resource names have to be unique **within** a namespace, not across namespaces. That has three practical consequences, which are the ones that matter today:

- **Names do not collide.** The data team can have its own Service called `revisor` in its namespace without stepping on yours. And DNS reflects it: what Lesson 3 called plain `revisor` is really `revisor.<namespace>.svc.cluster.local`, and from another namespace you have to write it in full.
- **Permissions have a scope.** A `Role` (7.4) applies within one namespace. Granting permission over the Pods of `revisor` does not grant permission over those of `default`.
- **Rules attach to a namespace.** The Pod Security Admission labels (7.3) and the network policies (7.5) apply to the namespace where they live.

What it does **not** do, even though the name and the tutorials suggest it: it does not close the network. The same page does not mention network isolation, because there is none: a Pod in one namespace can talk to a Service in another just by writing its full name. 7.5.3 measures it, and that is why the fourth layer exists.

Not everything lives inside a namespace. You can ask the cluster, which knows which types belong to one and which apply to the whole cluster:

```text
$ kubectl api-resources --namespaced=false -o name | grep -E '^(nodes|namespaces|persistentvolumes|storageclasses|clusterroles|clusterrolebindings|gatewayclasses\.)'
namespaces
nodes
persistentvolumes
gatewayclasses.gateway.networking.k8s.io
clusterrolebindings.rbac.authorization.k8s.io
clusterroles.rbac.authorization.k8s.io
storageclasses.storage.k8s.io

$ kubectl api-resources --namespaced=true -o name | grep -E '^(pods|services|secrets|serviceaccounts|roles|rolebindings|networkpolicies)(\.|$)'
pods
secrets
serviceaccounts
services
networkpolicies.networking.k8s.io
rolebindings.rbac.authorization.k8s.io
roles.rbac.authorization.k8s.io
```

The first list, types **without** a namespace: the namespaces themselves, the nodes, the persistent volumes, the storage classes, the cluster-scoped roles (`clusterroles`) and their bindings, and the `GatewayClass` you created in Lesson 6. The second, types **with** a namespace: the Pods, the Services, the Secrets, the service accounts and, in the RBAC and network groups, this lesson's `roles`, `rolebindings` and `networkpolicies`. The rule for remembering it: what describes **a workload** lives in a namespace; what describes **the infrastructure everyone shares** does not. That is why the `eg` `GatewayClass` does not move today, and why MetalLB and Envoy Gateway, which are platform, stay in `metallb-system` and `envoy-gateway-system`. Only the project moves.

#### 7.2.2 What changes in the manifests

The move comes down to a few changes, almost all in the `kustomization.yaml`. Read it in full, with its comment:

```yaml
# kustomization.yaml — Lección 7. Se aplica con: kubectl apply -k .
# Todo va al espacio de nombres «revisor» (namespace: revisor, abajo), que nace
# aquí mismo (namespace.yaml) en el nivel «restricted» de Pod Security.
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Requiere la infraestructura de la Lección 6 (MetalLB y Envoy Gateway) ya
# instalada: sin sus CRD, Gateway y HTTPRoute no existen.
# revisor-publico.yaml (el LoadBalancer directo de la 6) ya no está: desde la
# Lección 7 la única puerta es el Gateway. El estado de la Lección 6 vive en
# punto-de-partida/, y se retira con: kubectl delete -k punto-de-partida
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

The new line that does the most is `namespace: revisor`. Kustomize applies it as a transformation: to **every** namespaced object that appears in `resources` it writes `metadata.namespace: revisor`, without your repeating it in each file. That is why the Deployments, the Services and the `Gateway` did not change a letter of their `metadata`. The other changes are three new files in the list: `namespace.yaml` (the namespace itself, with its labels, 7.3), `cuentas.yaml` (the accounts and permissions, 7.4) and `red.yaml` (the six policies, 7.5). And the two Deployments now declare their service account and ask the cluster not to mount credentials into them:

```yaml
    spec:
      serviceAccountName: revisor
      automountServiceAccountToken: false
```

(It is a fragment: two lines from `revisor-deployment.yaml`, which 7.4 explains. The one for `prueba` says `prueba`.) Also notice what is **not** in the list: `revisor-publico.yaml`, Lesson 6's direct `LoadBalancer`. Its own comment announced it: from today the only way out to the outside is the `Gateway`. The file is kept in `punto-de-partida/` for reference.

#### 7.2.3 The move

A new namespace does not “move” objects; the objects of one namespace cannot be transferred to another. They are **deleted from one and created in the other**. First Lesson 6's state is removed with the same `kustomization` that created it, and then this lesson's is applied. The token stays: it is the same file for both, and that is why the generated Secret keeps its name.

```bash
ctx && kubectl delete -k punto-de-partida
rm -f -- punto-de-partida/token.txt
ctx && kubectl apply -k .
```

```text
$ kubectl delete -k punto-de-partida
configmap "revisor-config-t6cm6872fk" deleted from default namespace
secret "revisor-token-mgc44f554f" deleted from default namespace
service "prueba" deleted from default namespace
service "revisor" deleted from default namespace
service "revisor-publico" deleted from default namespace
deployment.apps "prueba" deleted from default namespace
deployment.apps "revisor" deleted from default namespace
gateway.gateway.networking.k8s.io "revisor" deleted from default namespace
httproute.gateway.networking.k8s.io "revisor" deleted from default namespace

$ kubectl apply -k .
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
service/prueba created
service/revisor created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created
networkpolicy.networking.k8s.io/acceso-revisor-salida created
networkpolicy.networking.k8s.io/cerrado created
networkpolicy.networking.k8s.io/dns created
networkpolicy.networking.k8s.io/prueba-entrada created
networkpolicy.networking.k8s.io/revisor-entrada created
networkpolicy.networking.k8s.io/revisor-salida created

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba -n revisor --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Read the first two blocks from top to bottom. The `delete -k` deletes nine objects, and each line says **where** it deletes them from (`from default namespace`). The `apply -k` creates twenty: the namespace (`namespace/revisor`), the three accounts, the `Role` and its `RoleBinding`, the ConfigMap and the Secret with the usual hash, the two Services, the two Deployments, the entry point and the route, and the six network policies. Notice the order: the namespace comes out first. Kustomize emits the objects with namespaces first, and that is why you did not need two steps. With the types from a new platform, like `Gateway` in Lesson 6, the wait is still yours: there it is not a matter of the list's order but of the type existing.

Did everything end up where it should?

```text
$ kubectl get namespace revisor -o go-template='{{range $k, $v := .metadata.labels}}{{$k}}={{$v}}{{"\n"}}{{end}}'
kubernetes.io/metadata.name=revisor
pod-security.kubernetes.io/audit=restricted
pod-security.kubernetes.io/audit-version=v1.37
pod-security.kubernetes.io/enforce=restricted
pod-security.kubernetes.io/enforce-version=v1.37
pod-security.kubernetes.io/warn=restricted
pod-security.kubernetes.io/warn-version=v1.37

$ kubectl get all -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rgh68    1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          2m52s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.130.233   <none>        9000/TCP   2m52s
service/revisor   ClusterIP   10.96.146.219   <none>        80/TCP     2m52s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           2m52s
deployment.apps/revisor   3/3     3            3           2m52s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       2m52s
replicaset.apps/revisor-5d6fd4d6bd   3         3         3       2m52s

$ kubectl get all -n default
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   14m

$ kubectl get gateway,httproute -n revisor
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.27.255.200   True         2m52s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               2m52s

$ kubectl wait --for=condition=Available deployment -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=revisor --timeout=180s
deployment.apps/envoy-revisor-revisor-b269644b condition met

$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-gateway-5fc4949dcb-k6s46                    1/1     Running   0          14m
pod/envoy-revisor-revisor-b269644b-867f46cd7d-rbkcf   2/2     Running   0          2m52s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-gateway                    ClusterIP      10.96.130.219   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   14m
service/envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       2m52s
```

`default` was left with a single thing, the `kubernetes` Service that the cluster creates by itself: the namespace is clean. The whole project is in `revisor`, and the entry point is served from `envoy-gateway-system`, a third namespace: **the entry point does not live where the project lives**. Make a note of it, because the network policy in 7.5 has to let it through, and that is done with a `namespaceSelector`. And a check from outside the cluster, as in Lesson 6, to see that the move did not close the entry point:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

One last decision in the lesson. With the project already moved, the script removes the six network policies:

```text
$ kubectl delete -n revisor -f red.yaml
networkpolicy.networking.k8s.io "cerrado" deleted from revisor namespace
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace
networkpolicy.networking.k8s.io "prueba-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace
```

It is not a mistake nor proof that they do not work. It is to study **one layer at a time**. The six policies are in the `kustomization.yaml` because the project's final state includes them, but if they were in place while you study Pod Security and RBAC, every practice Pod would be born unable to talk to the API, and you would not know whether what you see is caused by one layer or another. They come back in 7.5, with their explanation.

### 7.3 Pod Security Admission

#### 7.3.1 What it is: a guard at the door of the `kube-apiserver`

When you run `kubectl apply`, your request goes through a chain of controls before being stored. One of them is called **admission**. The [Pod Security Admission documentation](https://kubernetes.io/docs/concepts/security/pod-security-admission/) describes it: it is a controller that checks every Pod about to be created against a **standard** (the *Pod Security Standards*), and decides according to a label on the namespace where it would be born. It installs nothing: it comes with the `kube-apiserver`. It is configured **with labels on the namespace**, and those labels have three parts:

- **The mode**, which says what to do about a violation. There are three: `enforce` (“policy violations will cause the pod to be rejected”), `audit` (“policy violations will trigger the addition of an audit annotation to the event recorded in the audit log, but are otherwise allowed”) and `warn` (“policy violations will trigger a user-facing warning, but are otherwise allowed”). A namespace can use one, two or all three, even with different levels.
- **The level**, which says how much is demanded. The [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) define three. `privileged` is “unrestricted” and deliberately open. `baseline` aims to “ease adoption for common containerized workloads” while preventing known privilege escalations. `restricted` is a “heavily restricted” policy, following current Pod hardening best practices.
- **The version** (optional), which pins which edition of the standard the Pod is compared against. Each Kubernetes version can fine-tune what `baseline` and `restricted` ask for; with `latest` the standard moves with the cluster, and with `v1.37` it stays fixed.

The label has this form: `pod-security.kubernetes.io/<MODE>: <LEVEL>` and, separately, `pod-security.kubernetes.io/<MODE>-version: <VERSION>`. See how the lesson's namespace ended up with all three:

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

The `revisor` namespace uses **all three modes at the same level**, `restricted`, and all three pinned to `v1.37`. The three together make sense: `enforce` is the one that protects (it rejects), `warn` is the one that notifies you **when you apply** a Deployment, before it fails (7.3.4), and `audit` leaves a trace in the `kube-apiserver`'s audit log, which the course neither enables nor measures. The documentation's guide to applying these levels to a namespace shows the same division of roles: `enforce` at the level you already meet, and `audit` and `warn` at the level you want to reach, to see what would fail before demanding it.

#### 7.3.2 The three levels, measured

Before the lesson's namespace, the three levels face to face. Two test namespaces are created, one `privileged` and one `baseline`, and each one (and `revisor`) is asked to accept two Pods, without creating them: `--dry-run=server` sends the complete request to the `kube-apiserver`, which validates it with all its admission controls and stores nothing. The first Pod asks for `hostNetwork: true`, that is, to use the node's network instead of its own, something `baseline` already forbids. The second is a `curl` Pod written without a `securityContext`, as in any tutorial.

```text
$ kubectl create namespace nivel-privileged
namespace/nivel-privileged created

$ kubectl create namespace nivel-baseline
namespace/nivel-baseline created

$ kubectl label namespace nivel-privileged pod-security.kubernetes.io/enforce=privileged
namespace/nivel-privileged labeled

$ kubectl label namespace nivel-baseline pod-security.kubernetes.io/enforce=baseline
namespace/nivel-baseline labeled

$ kubectl wait --for=create serviceaccount/default -n nivel-privileged --timeout=60s
serviceaccount/default condition met

$ kubectl wait --for=create serviceaccount/default -n nivel-baseline --timeout=60s
serviceaccount/default condition met
```

The `kubectl wait --for=create` is a wait you may not have expected: each new namespace receives its `default` account a few moments **after** it is born, a controller creates it, and a Pod requested before the account exists is rejected for another reason (`serviceaccount "default" not found`). In one of this lesson's test runs (with no saved output), without that wait, the six tests below failed with that message and not with the security one. That is why today the wait is in plain sight.

```text
--- espacio nivel-privileged ---
$ kubectl run hostnet -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
pod/hostnet created (server dry run)

$ kubectl run sinreglas -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio nivel-baseline ---

$ kubectl run hostnet -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true)
[código de salida: 1]

$ kubectl run sinreglas -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio revisor ---

$ kubectl run hostnet -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "restricted:v1.37": host namespaces (hostNetwork=true), allowPrivilegeEscalation != false (container "hostnet" must set securityContext.allowPrivilegeEscalation=false), unrestrict
[código de salida: 1]

$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinr
[código de salida: 1]
```

The outputs are trimmed to 260 characters with `cut` so that they fit; you see the complete message in 7.3.3. Read them as a table:

| Namespace | `hostNetwork: true` | Pod without `securityContext` |
|---|---|---|
| `nivel-privileged` | created (`server dry run`) | created |
| `nivel-baseline` | **rejected**: `host namespaces (hostNetwork=true)` | created |
| `revisor` (`restricted`) | **rejected**, and with more reasons | **rejected** |

Three things. First: `baseline` stops what is known to be dangerous (sharing the node's network) and lets a normal Pod through, written carelessly. `restricted` also asks for good practices, and that is why the same simple Pod that `baseline` accepts is rejected here. Second: `nivel-baseline`'s message says `"baseline:latest"`, with no version. Since that namespace did not pin `enforce-version`, the standard is the cluster version's, **whichever it is**; `revisor`'s says `"restricted:v1.37"`, pinned. If the cluster is upgraded, the first can start rejecting what it used to accept; the second does not change until you change the label. Third: the script deletes the two test namespaces when it finishes (`kubectl delete namespace`), which deletes everything they held along with them.

```text
$ kubectl delete namespace nivel-privileged nivel-baseline
namespace "nivel-privileged" deleted
namespace "nivel-baseline" deleted
```

#### 7.3.3 `restricted`, read line by line

The practice Pod that was rejected twice above is a normal `curl` Pod. Now untrimmed, in the lesson's namespace:

```text
$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never -- sleep 60
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinreglas" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "sinreglas" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "sinreglas" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
[código de salida: 1]

$ kubectl get pods -n revisor -l run=sinreglas
No resources found in revisor namespace.
```

The message has the form “Pod X cannot be created: it violates PodSecurity "restricted:v1.37": ” followed by a comma-separated list, and each element is a rule that was not met, with the field that fixes it in parentheses. Four:

1. `allowPrivilegeEscalation != false`: the container must declare `securityContext.allowPrivilegeEscalation=false`. Without that line, a process inside could gain more privileges than its parent process (for example, by running a program with the *setuid* bit).
2. `unrestricted capabilities`: it must declare `securityContext.capabilities.drop=["ALL"]`. Linux *capabilities* are little pieces of what only `root` used to do; a container that asks for nothing receives a default set, and `restricted` demands that all of it be dropped.
3. `runAsNonRoot != true`: the Pod or the container must declare `runAsNonRoot=true`. It is not enough that the image *belongs* to a normal user: the manifest must **say** that it requires it, so that the cluster rejects an image that one day switches to `root`.
4. `seccompProfile`: it must declare `seccompProfile.type` as `RuntimeDefault` or `Localhost`. `seccomp` is the filter for calls to the kernel; the *runtime*'s profile blocks the most dangerous ones.

And it was not rejected for a fifth one, `readOnlyRootFilesystem`, which the course sets from Lesson 2: it is good practice, but the `restricted` level does **not** require it. That is the difference between what the cluster imposes and what you impose on yourself. Each line of that list is one of the four that the `revisor`'s `securityContext` has carried since Lesson 2; that is why the `revisor` and `prueba` were born without trouble in this very namespace. And `get pods` confirms it: `No resources found`. The rejection happens **before** creation: the Pod does not exist, not even in an error state.

#### 7.3.4 What can (and cannot) be hardened: `kube-system` and the `dry-run`

Why not put `restricted` on every namespace, without thinking about it? The same `--dry-run=server` that you used with the Pods is useful for seeing what would happen with a **label**: it computes against the Pods that already exist and warns, without changing anything. It is tried with two namespaces:

```text
$ kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: coredns-559f6c778d-q8k29 (and 1 other pod): runAsNonRoot != true, seccompProfile
Warning: etcd-curso-k8s-l7-control-plane (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
Warning: kindnet-82j5f (and 2 other pods): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: kube-proxy-d6hbh (and 2 other pods): host namespaces, privileged, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
namespace/kube-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

With `kube-system` there are four warnings, one per group of Pods, and all of them start with `Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"`: CoreDNS declares neither `runAsNonRoot` nor `seccompProfile`; `etcd`, `kindnet` and `kube-proxy` use the node's network (`host namespaces`) and ask for `hostPath` volumes (`restricted volume types`), and `kube-proxy` is also *privileged*. They ask for them because their job is to touch the node. That is why **a level is not applied because it is fashionable**: it is measured first, and there are namespaces (the system ones) where `restricted` does not fit. And the same `--dry-run` on `revisor` says `namespace/revisor not labeled (server dry run)` without a single warning: the project already meets what it demands.

And what about the Pods that were already running when the label is set? The documentation says that, when an `enforce` label is added or changed, the controller tests every Pod in the namespace against the new policy and returns the violations as warnings. It does not say what happens to the Pod. It is measured with a test namespace: it is born without labels, receives a Pod that does not meet `restricted`, and **afterwards** `enforce=restricted` is set on it.

```text
$ kubectl create namespace nivel-previo
namespace/nivel-previo created

$ kubectl wait --for=create serviceaccount/default -n nivel-previo --timeout=60s
serviceaccount/default condition met

$ kubectl run viejo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600
pod/viejo created

$ kubectl wait --for=condition=Ready pod/viejo -n nivel-previo --timeout=300s
pod/viejo condition met

$ kubectl label namespace nivel-previo pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "nivel-previo" violate the new PodSecurity enforce level "restricted:latest"
Warning: viejo: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/nivel-previo labeled

$ kubectl get pod viejo -n nivel-previo
NAME    READY   STATUS    RESTARTS   AGE
viejo   1/1     Running   0          21s

$ kubectl run nuevo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600 2>&1 | cut -c1-200
Error from server (Forbidden): pods "nuevo" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nuevo" must set securityContext.allowPrivilegeEscalati
[código de salida: 1]

$ kubectl delete namespace nivel-previo
namespace "nivel-previo" deleted
```

The `label` line carries the controller's warning, which names the `viejo` Pod and the rules it violates. And the `get pod` that follows leaves it `Running`: **the label informed and did not evict**. The `nuevo` Pod, requested with the same manifest, is rejected. Setting `enforce` does not clean a namespace; it closes the door for whatever arrives from that moment on. An old Pod that violates the level stays until it is recreated (for example, with a `rollout restart`), and then it can no longer be born. It is an operations trap: in a namespace with `enforce`, a restart can take down a Deployment that had been working for months, if its template never met the level.

Another test of the same kind, this time with the `warn` mode. The `kube-apiserver` is asked, without applying the change, to remove a line from the `revisor` (the `seccomp` profile) and say what it thinks:

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/securityContext/seccompProfile"}]' --dry-run=server
Warning: would violate PodSecurity "restricted:v1.37": seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/revisor patched

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}{"\n"}'
RuntimeDefault
```

The patch **is accepted** (`deployment.apps/revisor patched`, but it is `--dry-run=server`: nothing was saved) and it comes with a one-line warning: `would violate PodSecurity "restricted:v1.37": seccompProfile …`. That is `warn`: it warns whoever applies, without rejecting. The second command confirms that the Deployment still says `RuntimeDefault`. And that difference, “warns” against “rejects”, is the next error.

### The error you will see

This lesson's error is one of the most baffling, because the command comes out **fine** and the service does not appear. It is triggered with `fig07_01.sin-reglas.yaml`, a **program** that fails on purpose: a `revisor` Deployment written as in a tutorial, without a `securityContext`.

```yaml
# fig07_01.sin-reglas.yaml — FALLA A PROPÓSITO: un Deployment del revisor escrito
# como en un tutorial cualquiera, SIN securityContext. La imagen ya corre sin ser
# root (usuario 65532), pero el manifiesto no lo DECLARA. En el espacio «revisor»
# (nivel restricted) el Deployment se crea con una advertencia y sus Pods no
# nacen: el ReplicaSet registra FailedCreate. Se borra con kubectl delete -f.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sinreglas
  labels:
    app: sinreglas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sinreglas
  template:
    metadata:
      labels:
        app: sinreglas
    spec:
      containers:
      - name: revisor
        image: curso-docker-revisor:1.6.0
        imagePullPolicy: IfNotPresent
        env:
        - name: REVISOR_SERVICIOS
          value: "prueba http://prueba:9000/ 2s"
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
```

The image does run as non-`root` (user 65532), but the manifest does not declare it, and that is what the `restricted` level checks. It is applied in the lesson's namespace:

```text
$ kubectl apply -n revisor -f fig07_01.sin-reglas.yaml
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/sinreglas created

$ kubectl wait --for=condition=ReplicaFailure deployment/sinreglas -n revisor --timeout=120s
deployment.apps/sinreglas condition met

$ kubectl get deployment sinreglas -n revisor
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
sinreglas   0/1     0            0           1s

$ kubectl get replicaset -n revisor -l app=sinreglas
NAME                   DESIRED   CURRENT   READY   AGE
sinreglas-7c585c788d   1         0         0       1s

$ kubectl get pods -n revisor -l app=sinreglas
No resources found in revisor namespace.

$ kubectl describe replicaset -n revisor -l app=sinreglas | sed -n '/^Events:/,$p' | head -4
Events:
  Type     Reason        Age   From                   Message
  ----     ------        ----  ----                   -------
  Warning  FailedCreate  2s    replicaset-controller  Error creating: pods "sinreglas-7c585c788d-47khh" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Read it in order, from symptom to cause.

**First, what `apply` said.** Two lines: a warning (`Warning: would violate PodSecurity "restricted:v1.37": …`) and `deployment.apps/sinreglas created`. **It was created.** The Deployment is an object, not a Pod, and violates nothing. The warning is the `warn` mode, which does check the Pod template that the Deployment carries inside, to notify you in advance. If your terminal or your *pipeline* does not show warnings, here the notice slipped past you. This is what the documentation says: the `audit` and `warn` modes also apply to workload resources, but **`enforce` does not**: it applies only to the resulting Pods.

**Second, the symptom.** `kubectl wait` waits for an uncommon condition, `ReplicaFailure`, which the Deployment sets when its ReplicaSet cannot create replicas, and it finds it instantly. Then: `READY 0/1`, `UP-TO-DATE 0`, `AVAILABLE 0`. The ReplicaSet exists and asks for 1 Pod, `DESIRED 1`, but has `CURRENT 0`. And `get pods` says `No resources found`. The Deployment never failed out loud; it simply has no Pods.

**Third, the cause.** It is in the ReplicaSet's events, not in the Deployment's nor in the Pod's (which does not exist): `Warning FailedCreate … replicaset-controller Error creating: pods "sinreglas-…" is forbidden: violates PodSecurity "restricted:v1.37": …`. It is the same message as in 7.3.3, but now the controller receives it, which records it and retries. That is why you have to look at the **ReplicaSet**.

**The fix.** You fix the manifest, not the namespace: a `securityContext` like the one in the `revisor` and the test service, with the four lines from 7.3.3. Here, since the Deployment is not going to be used, it is deleted.

```text
$ kubectl delete -n revisor -f fig07_01.sin-reglas.yaml
deployment.apps "sinreglas" deleted from revisor namespace
```

**The order, when a Deployment has no Pods:**

1. `kubectl get deployment`: `READY 0/N`?
2. `kubectl get replicaset -l app=…`: `CURRENT` lower than `DESIRED`?
3. `kubectl describe replicaset`: the events, `FailedCreate`, and the full reason.
4. If it says `PodSecurity`, you do not lower the namespace's level; you fix the manifest.


### 7.4 Service accounts and minimal permissions

#### 7.4.1 What a service account is

When you run `kubectl get pods`, the API knows who you are from your `kubeconfig`. When a **program running inside the cluster** talks to the API (a controller, a deployment tool, a service that needs to know which other Pods exist), the API also needs to know who it is. That identity is called a **service account** (*ServiceAccount*). The [documentation](https://kubernetes.io/docs/concepts/security/service-accounts/) defines it as “a type of non-human account that, in Kubernetes, provides a distinct identity in a Kubernetes cluster”. It has three properties that matter here:

- **It is a namespaced object**, like a Pod. It is called `revisor` in the `revisor` namespace, and its full name for RBAC has the form `system:serviceaccount:<namespace>:<account>`, which for the `revisor` account in the `revisor` namespace becomes `system:serviceaccount:revisor:revisor` (the name repeats because they coincide). You will write it in 7.4.3.
- **Every namespace is born with one called `default`.** The cluster creates it by itself (section 7.3.2 just waited for it) and assigns it to every Pod that does not ask for another. By default it has no permissions beyond basic API discovery.
- **By default, the cluster mounts its credentials into every Pod.** The same page: “by default, Kubernetes provides the Pod with the credentials for an assigned ServiceAccount”. Since version 1.22 they are a short-lived token that renews itself, delivered as a projected volume; before, it was a long-lived Secret. That is the `kube-api-access-…` volume you saw in 7.1.3: the Pod can read its token from a file and present itself to the API with it.

The fact in the last point is the important one. **If a program inside a Pod is compromised, its first question is “what can I do with the token I have?”**, and that credential is mounted even though the program never uses it. For the `revisor` and for `prueba`, which do not talk to the API, it is a risk with no benefit at all. That is why the lesson's two Deployments declare `automountServiceAccountToken: false`. The [service accounts guide](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) explains that it can be disabled on the account or on the Pod, and that if both say something, the Pod wins.

#### 7.4.2 The permissions: `Role` and `RoleBinding`

A freshly created account can do nothing. Permissions are added with two objects. The [RBAC documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (role-based access control) separates them like this: a `Role` “contains rules that represent a set of permissions”, and permissions are **purely additive**: there are no “deny” rules. A `Role` “always sets permissions within a particular namespace”. Its relative `ClusterRole` is the same but without a namespace, for resources that do not have one (nodes, for example) or to repeat a set of rules across several namespaces. A `RoleBinding` is the glue: it “grants the permissions defined in a role to a set of subjects” (users, groups or service accounts), within a namespace. Two objects and not one because the role is written once and can be bound to many accounts.

Each rule in a `Role` has three parts: `apiGroups` (the API group: `""` is the core, where Pods and Services live; `apps` is where Deployments live), `resources` (the types) and `verbs` (what can be done: `get` to read one, `list` to list, `watch` to keep listening for changes, and the ones that modify, `create`, `update`, `patch` and `delete`). Read it in `cuentas.yaml`, in full:

```yaml
# cuentas.yaml — Lección 7: cada carga con su cuenta, y ninguna con permisos que
# no necesita. El revisor y prueba no le hablan a la API: cero permisos y sin
# credenciales montadas. «observador» puede mirar y nada más.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: revisor
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prueba
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: observador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: observador
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: observador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: observador
subjects:
- kind: ServiceAccount
  name: observador
  namespace: revisor
```

Three accounts and a pair of permission objects. `revisor` and `prueba` are accounts **with no permissions**: no `RoleBinding` mentions them, and both carry `automountServiceAccountToken: false` at the account level too. `observador` is the read account: the `observador` `Role` gives it `get`, `list` and `watch`, only those three verbs, on Pods, their logs (`pods/log`, a subresource), Services and core events, and on Deployments and ReplicaSets in the `apps` group. Notice what is **not** there: Secrets (the `revisor`'s token is a Secret), `create`, `update`, `patch`, `delete`, `exec` (`pods/exec` is another subresource, and it is not listed) and anything outside the namespace. The design rule is “what it needs, and nothing more”, and it is written by naming each resource, with no wildcards (`*`), because a wildcard includes whatever the cluster adds one day.

The `RoleBinding` says **to whom** it is granted: the `observador` account in the `revisor` namespace. Even so, no Deployment in the lesson uses this account. It exists so that you can see what “read-only” means with a real account, and for Exercise 2.

```text
$ kubectl get serviceaccounts -n revisor
NAME         AGE
default      5m2s
observador   5m2s
prueba       5m2s
revisor      5m2s

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name'
POD                        CUENTA    AUTOMOUNT   VOLUMENES
prueba-6899c74865-rgh68    prueba    false       <none>
revisor-5d6fd4d6bd-6kb4k   revisor   false       datos,token
revisor-5d6fd4d6bd-jdmx8   revisor   false       datos,token
revisor-5d6fd4d6bd-pj8r9   revisor   false       datos,token
```

It reads like this: four accounts, not three. The fourth, `default`, was created by the cluster itself. And the Pod table says, for each one, which account it runs with, that `AUTOMOUNT` is `false` and which volumes it has: `datos` and `token` in the `revisor`, none in `prueba`, and **neither has the `kube-api-access-…` from 7.1.3**. Compared with the “before”, that volume disappeared.

```text
$ kubectl get role,rolebinding -n revisor -o wide
NAME                                        CREATED AT
role.rbac.authorization.k8s.io/observador   2026-10-21T22:52:57Z

NAME                                               ROLE              AGE    USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/observador   Role/observador   5m3s                    revisor/observador

$ kubectl describe role observador -n revisor
Name:         observador
Labels:       <none>
Annotations:  <none>
PolicyRule:
  Resources         Non-Resource URLs  Resource Names  Verbs
  ---------         -----------------  --------------  -----
  events            []                 []              [get list watch]
  pods/log          []                 []              [get list watch]
  pods              []                 []              [get list watch]
  services          []                 []              [get list watch]
  deployments.apps  []                 []              [get list watch]
  replicasets.apps  []                 []              [get list watch]
```

#### 7.4.3 Asking without trying: `kubectl auth can-i`

How do you know what an account can do? You ask the API with `kubectl auth can-i`, which answers `yes` or `no`. To ask about **another** identity you use `--as`, which makes `kubectl` impersonate that identity in the request; the service account is written with its full name, `system:serviceaccount:<namespace>:<account>`. (Impersonating is a permission you have as the administrator of your kind cluster; a normal user of a real cluster would not have it.) First the `revisor`, which should be able to do nothing, and the `observador`, which should be able to read:

```text
$ kubectl auth can-i --list -n revisor --as=system:serviceaccount:revisor:revisor | head -5
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
clustertrustbundles.certificates.k8s.io         []                                     []               [get list watch]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador
yes

$ kubectl auth can-i get pods --subresource=log -n revisor --as=system:serviceaccount:revisor:observador
yes
```

The `revisor`'s list is not empty, and that has to be read carefully. The four lines are permissions that almost every identity receives by default. Three are *reviews about oneself*: `selfsubjectreviews` (who am I?, which according to `kubectl explain` returns the user information the `kube-apiserver` has about whoever asks), `selfsubjectaccessreviews` (can I do this?, which is the question `can-i` itself asks) and `selfsubjectrulesreviews` (which actions can I take in this namespace?). The fourth, `clustertrustbundles`, are bundles of public root certificates; the type's description says that all service accounts can read them by default. The roles that grant the first three come with the cluster (`system:basic-user`, which the documentation describes as read-only access to basic information about oneself, bound to the `system:authenticated` group). None of them is a permission over **your** objects. The question that matters, `get pods`, answers `no`, with exit code 1: `kubectl auth can-i` returns 0 when the answer is `yes` and 1 when it is `no`, and that makes it usable in a script. The `observador` answers `yes` to reading Pods and to reading their logs (`--subresource=log`). Now what it should **not** be able to do:

```text
$ kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get pods -n default --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]
```

Three `no`s: it cannot delete Pods (the `Role` does not include `delete`), it cannot read Secrets (they are not in the list) and it cannot read Pods in `default` (the `Role` and the `RoleBinding` live in `revisor`; a namespace role does not cross into another). It is direct proof that the namespace is the unit of permissions, even though it is not the unit of the network.

`can-i` asks; the real request confirms. With `--as`, `kubectl` performs the operation as if it were that account:

```text
$ kubectl get deployments -n revisor --as=system:serviceaccount:revisor:observador
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
prueba    1/1     1            1           5m5s
revisor   3/3     3            3           5m5s

$ kubectl delete pod -n revisor -l app=prueba --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): pods "prueba-6899c74865-rgh68" is forbidden: User "system:serviceaccount:revisor:observador" cannot delete resource "pods" in API group "" in the namespace "revisor"
[código de salida: 1]

$ kubectl get secrets -n revisor --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"
[código de salida: 1]
```

Listing Deployments works. Deleting a Pod and listing Secrets give `Error from server (Forbidden)`, and the full message is worth reading, because it has the shape of RBAC errors and it is what you will see the day something fails: `secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"`. Who (`User "system:serviceaccount:revisor:observador"`), which verb and on what (`cannot list resource "secrets"`), in which API group (`""`, the core) and in which namespace. With those five pieces you know exactly which rule to add if the permission was legitimate, or what to leave as it is if it was not. One detail: the verb in the second message is `list`, not `get`; you asked for “all the Secrets” and that is `list`. Reading one by name is `get`. The two verbs are separate on purpose.

#### 7.4.4 The same thing, from inside a Pod

So far everything was tested by impersonating from your terminal. The test that most resembles an attack is missing: a program **inside** a Pod, with whatever the Pod has at hand. Three support Pods are used, all of them `curl`: `depurar` (the one from Lesson 3, with the label `acceso-revisor: permitido` that the network will need), `intruso` (the same but **without** that label; it is the data team's Pod from the scene) and `lector`, a new one that carries the `observador` account **with the token mounted**. All three meet `restricted`, like anything born in this namespace. Read `fig07_04.lector.yaml`:

```yaml
# fig07_04.lector.yaml — un Pod que SÍ lleva credenciales: usa la cuenta «observador»
# y pide que se le monte su token (automountServiceAccountToken: true). Sirve para
# ver, desde dentro de un Pod, lo que el RBAC de cuentas.yaml permite y lo que no.
# Cumple «restricted». Se aplica con: kubectl apply -n revisor -f fig07_04.lector.yaml
apiVersion: v1
kind: Pod
metadata:
  name: lector
  labels:
    app: lector
spec:
  restartPolicy: Never
  serviceAccountName: observador
  automountServiceAccountToken: true
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: lector
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

It is a deliberate exception to the rule in 7.4.1: `automountServiceAccountToken: true`, which is the default value written out loud. It exists to show what a mounted token allows. Read it against the `intruso` list, which uses the `default` account **without** a token (`depurar` and `intruso` declare it turned off):

```text
$ kubectl apply -n revisor -f depurar.yaml -f intruso.yaml -f fig07_04.lector.yaml
pod/depurar created
pod/intruso created
pod/lector created

$ kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso pod/lector --timeout=180s
pod/depurar condition met
pod/intruso condition met
pod/lector condition met

$ kubectl exec -n revisor lector -- /bin/ls /var/run/secrets/kubernetes.io/serviceaccount
ca.crt
namespace
token
```

The `lector` has three files in `/var/run/secrets/kubernetes.io/serviceaccount`: `ca.crt` (the certificate with which to recognize the API), `namespace` (its namespace) and `token` (its credential). With them, `curl` presents itself to the API with the header `Authorization: Bearer <token>`. The address is `https://kubernetes.default.svc`, the name of the `kubernetes` Service in `default`, which is the API's entry point for Pods. Four requests:

```text
$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 200

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "secrets %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets'
secrets 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods-default %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/default/pods'
pods-default 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets | grep -E "message|code"'
  "message": "secrets is forbidden: User \"system:serviceaccount:revisor:observador\" cannot list resource \"secrets\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

One `200` and three `403`s. With the `observador` token, the `lector` **can** list the Pods in `revisor` (the permission we gave it), and it **cannot** list the Secrets in the same namespace or the Pods in `default`. The fourth block is the same Secrets request with the raw response filtered: it is the API's error JSON, with the same message you saw with `--as`. This is what RBAC promises, but seen from the side of the attacker: a stolen `observador` token has the reach of the `Role` and not one resource more. That is why the `Role` is written short.

And now the Pod that has **no** token:

```text
$ kubectl exec -n revisor intruso -- sh -c '/bin/ls /var/run/secrets/kubernetes.io; echo código=$?' 2>&1
ls: /var/run/secrets/kubernetes.io: No such file or directory
código=1

$ kubectl exec -n revisor intruso -- sh -c 'curl -s -k https://kubernetes.default.svc/api/v1/namespaces/revisor/pods | grep -E "message|code"'
  "message": "pods is forbidden: User \"system:anonymous\" cannot list resource \"pods\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

The directory does not exist: `ls: /var/run/secrets/kubernetes.io: No such file or directory`. The `intruso` does not even have a credential to present. If it talks to the API anyway (`curl -k`, which does not verify the certificate, only for this test), the API receives it as `system:anonymous`, the identity of whoever does not identify themselves, and answers `403`: `pods is forbidden: User "system:anonymous" cannot list resource "pods"`. Zero permissions and zero credentials; that is the state you want for every Pod that does not talk to the API. (The fact that the API answers a `403` means that the `intruso` **did reach** the API: the only thing stopping it here is RBAC. What would stop it from even arriving is the network, and 7.5 measures that.)


### 7.5 The network: open until someone closes it

#### 7.5.1 The model, before touching anything

The [network policies documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/) describes the model with three sentences worth learning by heart, because everything else follows from them:

- **By default, a Pod is not isolated.** “By default, a pod is non-isolated for egress; all outbound connections are allowed”, and the same for ingress: “all inbound connections are allowed”. This is the state your Pods are in today.
- **A Pod becomes isolated when a policy selects it.** “A pod is isolated for egress if there is any NetworkPolicy that both selects the pod and has `Egress` in its `policyTypes`”, and equivalently for ingress with `Ingress`. The two directions are isolated separately. A policy that only says `Ingress` does not touch egress.
- **Policies add up.** “Network policies do not conflict; they are additive.” If several policies apply to a Pod in one direction, what is allowed is the **union** of what each one allows. The order does not matter. And there is no “deny” rule: what no policy allows is forbidden, but only for Pods that are already isolated.

A policy has four parts: a `podSelector` (which Pods **in the namespace** it applies to; `{}` means all), some `policyTypes` (whether it isolates ingress, egress or both), and `ingress` and `egress` lists of what is **allowed**, each with a `from` or a `to` (from where or to where) and some `ports`. And the `from` or the `to` can be three things: a `podSelector` (Pods in **this** namespace), a `namespaceSelector` (all the Pods in the chosen namespaces) or, together in the same element, both (chosen Pods in chosen namespaces). A detail that bites: `from` is a list, and each element of the list is an alternative (an **or**); what goes inside a single element is combined with **and**.

And the condition that matters most: the documentation itself warns that “you must be using a networking solution which supports NetworkPolicy” and that “creating a NetworkPolicy resource without a controller that implements it will have no effect”. The cluster stores your policy without complaint, and the traffic keeps flowing. It is a silent failure. That is why the course plan said “if kind's network add-on does not enforce it, another one is installed”. It is measured, not assumed.

#### 7.5.2 Who enforces them on kind?

kind's nodes use by default a network add-on called `kindnetd` (the [kind configuration](https://kind.sigs.k8s.io/docs/user/configuration/) describes it as a simple networking implementation built on standard CNI plugins; *CNI* is the interface Kubernetes uses to ask an add-on to provide networking to Pods). The cluster is asked what is running:

```text
$ kubectl get daemonset -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kindnet      3         3         3       3            3           kubernetes.io/os=linux   17m
kube-proxy   3         3         3       3            3           kubernetes.io/os=linux   17m

$ kubectl get daemonset kindnet -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
docker.io/kindest/kindnetd:v20260820-69b56db7
```

There is a `kindnet` DaemonSet with one Pod per node, and its image is `kindest/kindnetd:v20260820-69b56db7`. Knowing which one it is does not say whether it enforces policies. The release notes for [kind v0.24.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0) announce, among their main points, “network policy support using `sigs.k8s.io/kube-network-policies`”. That is what the paper says. What matters is what your cluster measures, and to measure it you need a control: two `curl` Pods that are on nobody's list.

```text
$ kubectl apply -n default -f intruso.yaml
pod/intruso created

$ kubectl wait -n default --for=condition=Ready pod/intruso --timeout=180s
pod/intruso condition met

$ kubectl get pods -A -l 'app in (depurar,intruso,lector)' -L acceso-revisor
NAMESPACE   NAME      READY   STATUS    RESTARTS   AGE   ACCESO-REVISOR
default     intruso   1/1     Running   0          1s    
revisor     depurar   1/1     Running   0          14s   permitido
revisor     intruso   1/1     Running   0          14s   
revisor     lector    1/1     Running   0          13s   
```

There is an `intruso` in `revisor` and another in `default`: the one in the namespace of its own is the data team's Pod from the scene; the one in `default` is any other team in the cluster. Both were born without the `acceso-revisor` label. `depurar` does have it (`permitido`); `intruso` and `lector` do not, and the table says so with the empty column. That matters in 7.5.4.

#### 7.5.3 With no rules: what the namespace does NOT isolate

With the six policies removed (7.2.3), this is what the `revisor` `intruso` can do, and what the `default` one can do:

```text
$ kubectl get networkpolicy -n revisor
No resources found in revisor namespace.

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://prueba:9000/
sano

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez
ok

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

Four answers are read, and all four are bad news:

1. The `intruso` talks to the `revisor` and receives its `/salud`. Without the token it cannot ask for the report (it gets `401`), but it arrived.
2. It talks to `prueba:9000`, which is not its own, and receives `sano`, the test service's mode. With a `POST` to `/modo/caido` it could set it to `caido`: the test service **has no authentication** and the network does not protect it.
3. It talks to the cluster API, at `/livez`, and it answers `ok`. That health path answers without credentials on purpose (the RBAC documentation calls it non-sensitive information, the `system:public-info-viewer` role), so the answer is not a defect of the API. What matters is something else: any Pod has a **network route** all the way to the `kube-apiserver` (through the `kubernetes` Service, port 443), and nobody took it away.
4. The `default` `intruso` reaches the `revisor` in `revisor` by writing the Service's full name, `revisor.revisor.svc.cluster.local`. **Two different namespaces, and not a single wall between them.** This is what the namespaces documentation does not claim and what many people assume.

It is the answer to the second question of 5:58, and it is not the one you wanted: yes, a Pod from the data team can talk to the `revisor` without going through the entry point.

#### 7.5.4 Default-deny

The first policy closes everything, with no openings. It is a short **program**:

```yaml
# fig07_02.cerrado.yaml — la primera regla de red.yaml, sola: cierra la entrada
# y la salida de TODOS los Pods del espacio donde se aplica, sin ninguna apertura.
# Se aplica con -n revisor para ver qué se rompe (hasta el DNS), y después se
# completa con red.yaml. No forma parte de la kustomization.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

`podSelector: {}` selects all the Pods in the namespace, and `policyTypes: [Ingress, Egress]` isolates them in both directions. Since there are no `ingress` or `egress` lists, nothing is allowed. It is applied and the same thing as before is measured:

```text
$ kubectl apply -n revisor -f fig07_02.cerrado.yaml
networkpolicy.networking.k8s.io/cerrado created

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- timeout 8 nslookup revisor.revisor.svc.cluster.local
;; connection timed out; no servers could be reached

command terminated with exit code 1
[código de salida: 1]

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Everything stopped working, and it is worth separating three signals that look alike. `command terminated with exit code 28` is `curl`'s code for **timeout**: there was no response in the 3 seconds you gave it with `-m 3`. A `curl` against a policy that drops packets does not receive a rejection, only silence. It is different from `connection refused` (code 7, where someone answers “there is nothing here”, which you saw in Lessons 3 and 5) and from a `403` (where someone who did hear you tells you no). There are three kinds of “no” and they are told apart by the code. Second signal: `depurar`, the Pod **with** the label, does not get through either. You have not opened anything yet. Third: the `nslookup` also timed out, `;; connection timed out; no servers could be reached`. **A name lookup is network traffic** that leaves the Pod toward the cluster DNS, and the `cerrado` policy closed that too. With egress closed, the Pods in the namespace cannot ask who `revisor` is.

Between the `apply` and the tests there is an 8-second wait (`$ sleep 8`, in plain sight in the full output of `correr.salida.txt`); 7.5.7 measures how long a policy takes to be programmed and that is where the margin comes from.

There are more effects, which are measured with three commands from your machine and one from the Pod that reads the API:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
000
[código de salida: 28]

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ sleep 3
Forwarding from 127.0.0.1:18087 -> 8080

$ curl -s -m 8 -H 'Authorization: Bearer …' 'http://127.0.0.1:18087/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     1.998s  se acabo el tiempo de espera

$ kubectl exec -n revisor lector -- sh -c 'curl -s -m 3 -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 000
command terminated with exit code 28
[código de salida: 28]
```

The entry point stopped letting traffic in: the outside client receives `000` and code 28. The `cerrado` policy isolates the ingress of **all** the Pods in the namespace, the `revisor` included, and Envoy's Pods (which live in another namespace) were left without permission to talk to it. The `port-forward`, on the other hand, **keeps working**: the tunnel opened and the `revisor` answered. (The [`port-forward` guide](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) does not describe which path it travels; it does say something useful for this lesson: access to `port-forward` is controlled by RBAC, with the `create` permission on `pods/portforward`, so whoever has it gets into the Pod even if the network is closed.) But what the `revisor` answers is no longer the full report: the table says `prueba FALLA` with the detail `se acabo el tiempo de espera` (the wait timed out), because the `revisor` cannot go out to ask `prueba`. The `revisor`'s own egress is closed as well. And the `lector`, the Pod with a valid token, no longer reaches the API: `pods 000`, code 28. **The closed network protects the API from whoever has permission.** RBAC says what you *may* ask for; the network says where you *get to*. Both have to say yes.

A reasonable doubt at this point: if everything is closed, shouldn't the probes fail? They do not. The probes are run by the node's `kubelet` (Lesson 5), and the network policies documentation says that, when a Pod is isolated for ingress, “the only connections allowed into the pod are those from the pod's node and those allowed by the ingress of some NetworkPolicy”. The node's own traffic is outside the filter. It is verified with the six rules in place, 45 seconds later, in 7.5.5.

#### 7.5.5 The necessary openings

Now the other five policies, which together with `cerrado` make up `red.yaml`. Read them one by one before applying them; each has a comment saying whom it opens to and why:

```yaml
# red.yaml — Lección 7: todo cerrado por defecto, y solo las aperturas necesarias.
# ⚠️ Que el clúster APLIQUE estas reglas depende de la red (CNI). kindnet, la red
# de kind desde la v0.24.0, sí las aplica: la Lección 7 lo mide con intruso y
# depurar. Con un CNI que no las aplique, estos objetos se guardan y no hacen nada.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# Todos pueden preguntarle al DNS del clúster (si no, ningún nombre resuelve).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
---
# El revisor sale solo hacia prueba:9000.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-salida
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: prueba
    ports:
    - {protocol: TCP, port: 9000}
---
# prueba solo recibe del revisor.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prueba-entrada
spec:
  podSelector:
    matchLabels:
      app: prueba
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 9000}
---
# Al revisor solo entran los Pods marcados «acceso-revisor: permitido» y los
# Envoy de la puerta (Lección 6), que viven en el espacio envoy-gateway-system.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-entrada
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          acceso-revisor: permitido
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: envoy-gateway-system
    ports:
    - {protocol: TCP, port: 8080}
---
# …y esos mismos Pods pueden SALIR hacia el revisor:8080. Con «cerrado» también
# la salida está prohibida: abrir solo la entrada del revisor no basta (medido).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: acceso-revisor-salida
spec:
  podSelector:
    matchLabels:
      acceso-revisor: permitido
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 8080}
```

In order:

- **`cerrado`**: the one above. With `podSelector: {}` and both types, it leaves all the Pods in the namespace with no ingress and no egress.
- **`dns`**: opens the **egress** of all the Pods toward DNS. The destination is written with both conditions together in a single element (`namespaceSelector` **and** `podSelector`): the Pods with the label `k8s-app: kube-dns` in the `kube-system` namespace. The ports are 53 over UDP and over TCP. The namespace is selected with the label `kubernetes.io/metadata.name`, which the cluster sets by itself on every namespace, with its name; the documentation warns that you cannot write a namespace's name directly in a policy and that this label exists for that.
- **`revisor-salida`**: the `revisor`'s **egress** toward the Pods with `app: prueba`, only to port 9000. It is the only thing the `revisor` needs from the network: to query `prueba`.
- **`prueba-entrada`**: the **ingress** to `prueba`, only from the `app: revisor` Pods, and only to 9000. The `revisor`'s egress policy and `prueba`'s ingress policy are two halves of the same door: for traffic to pass, both directions have to say yes.
- **`revisor-entrada`**: the **ingress** to the `revisor`, on port 8080, from two origins (two `from` elements, that is, one **or** the other): the Pods with the label `acceso-revisor: permitido` (in this namespace) and **all the Pods** in the `envoy-gateway-system` namespace, where Lesson 6's entry point lives.
- **`acceso-revisor-salida`**: the **egress** of the Pods with the label `acceso-revisor: permitido` toward the `revisor`, port 8080. It is the partner of the previous one. It exists because of a lesson that a first version of this network paid for: opening only the `revisor`'s ingress is not enough, because `cerrado` also closes the egress of whoever wants to talk to it.

Two observations before applying them. The label `acceso-revisor: permitido` acts as a **key**: whoever carries it can talk to the `revisor`, and anyone with permission to create Pods in the namespace can put it on a Pod. That is why the label is not a secret but an agreement, and 7.5.8 comments on it. And the policies use port `8080`, the container's, **not** the Service's 80. This is not a decision specific to this cluster: the [API reference](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/) defines a policy's `port` field as “a numerical or named port on a pod”. The Service has already chosen a replica and translated the port before the policy looks at the packet; the policy sees the final destination. Here it was measured that kindnet honors this (otherwise `depurar` would not have gotten through), and on another cluster it is worth measuring the same, because what is being checked is that the add-on enforces the API, not which port wins.

```text
$ kubectl apply -n revisor -f red.yaml
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns created
networkpolicy.networking.k8s.io/revisor-salida created
networkpolicy.networking.k8s.io/prueba-entrada created
networkpolicy.networking.k8s.io/revisor-entrada created
networkpolicy.networking.k8s.io/acceso-revisor-salida created

$ kubectl get networkpolicy -n revisor
NAME                    POD-SELECTOR               AGE
acceso-revisor-salida   acceso-revisor=permitido   8s
cerrado                 <none>                     50s
dns                     <none>                     8s
prueba-entrada          app=prueba                 8s
revisor-entrada         app=revisor                8s
revisor-salida          app=revisor                8s

$ kubectl describe networkpolicy revisor-entrada -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     app=revisor
  Allowing ingress traffic:
    To Port: 8080/TCP
    From:
      PodSelector: acceso-revisor=permitido
    From:
      NamespaceSelector: kubernetes.io/metadata.name=envoy-gateway-system
  Not affecting egress traffic
  Policy Types: Ingress

$ kubectl describe networkpolicy cerrado -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Allowing egress traffic:
    <none> (Selected pods are isolated for egress connectivity)
  Policy Types: Ingress, Egress
```

`cerrado` came out `unchanged` (it was already there) and the other five `created`. The `describe` of `revisor-entrada` reads it in plain language: “allowing ingress traffic on port 8080/TCP, from (PodSelector: `acceso-revisor=permitido`) and from (NamespaceSelector: `kubernetes.io/metadata.name=envoy-gateway-system`); not affecting egress; policy type: Ingress”. The two `From:` entries are the two alternatives. And the one for `cerrado` repeats, in other words, what you already knew: “Pods selected: isolated for ingress and for egress”.

Now the test, with the same commands as always:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor depurar -- curl -s -m 3 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           9ms  200

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://prueba:9000/
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez

command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- nslookup revisor.revisor.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.revisor.svc.cluster.local
Address: 10.96.146.219

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Six results, one per question:

- **`depurar` (with the label) reaches the `revisor`** and receives its `/salud`, and with the token it receives the full report: `prueba OK`. This means the `revisor` can go out to `prueba` again and `prueba` accepts it. Those are the two halves.
- **`intruso` (without the label) does not get through**: code 28. The answer to the second question of 5:58 is now “no”.
- **`depurar` does not reach `prueba:9000`**: code 28. The label opens the path to the `revisor`, not to the test service. A Pod with the `revisor`'s key is not a Pod with the key to everything.
- **`intruso` does not reach the API**: `curl` times out. The third question now has a wall before RBAC.
- **DNS answers**: the `intruso` resolves `revisor.revisor.svc.cluster.local` to the Service's IP. A Pod without a key can ask for names (the `dns` rule is for everyone) and receives an answer, but it cannot connect to what it finds. That DNS works does not mean the path is open.
- **The `default` `intruso` does not get through either**: the Service's full name no longer helps it.

And the legitimate routes that might have broken:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ curl -s -m 5 http://127.0.0.1:18087/salud   # por port-forward
{"estado":"vivo","version":"1.6.0"}
```

The entry point answers again from outside, because `revisor-entrada` admits the Pods in `envoy-gateway-system`. And the `port-forward` keeps working. Now, with all the rules in place, a 45-second wait, the length of a few rounds of Lesson 5's probes, and a look at the Pods:

```text
$ sleep 45

$ kubectl get pods -n revisor -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-6899c74865-rgh68    1/1     Running   0          7m15s
revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          7m15s
```

`RESTARTS 0` on all four, `1/1`. The closed network did **not** take the probes down, and the reason is the one in the documentation you just read: the `kubelet` runs them, from the node.

#### 7.5.6 What each rule is for: remove one, measure, put it back

Reading a policy says what it *should* do. To know what it does, you take it away from the cluster, **one at a time**, and measure four things from the same place: `depurar` asks the `revisor` for `/salud`; `depurar` asks it for the report (which forces the `revisor` to go out to `prueba`); `depurar` resolves the `revisor`'s name; and the outside client asks it for `/salud` through the entry point. Then `red.yaml` is applied again and you move on to the next. This table's `nslookup` is done with an `sh -c` that prints the last useful line, or `sin respuesta` (no answer), so that it fits on one line.

```text
$ kubectl delete networkpolicy dns -n revisor
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/salud
000
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- sh -c 'r=$(timeout 8 nslookup revisor.revisor.svc.cluster.local 2>&1 | grep -E "^Address: [0-9]|timed out" | tail -1); echo "${r:-sin respuesta}"'
;; connection timed out; no servers could be reached

$ curl -s -m 4 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
200
```

That is the first one: without `dns`, the name `revisor` does not resolve, so the request to `/salud` and the one for the report time out (code 28) and so does the `nslookup`. The entry point, on the other hand, answers `200`: what was measured is that Envoy reaches the `revisor` even though DNS is closed to the namespace's Pods; how Envoy finds the replicas is Envoy Gateway's business and the course did not measure it. The other four read the same way. The full table:

| Rule removed | `depurar` → `/salud` | `depurar` → report | Resolve the name | From outside, `/salud` |
|---|---|---|---|---|
| `dns` | 28 (timeout) | 28 | timeout | 200 |
| `revisor-salida` | 200 | `prueba FALLA`, timeout | answers | 200 |
| `prueba-entrada` | 200 | `prueba FALLA`, timeout | answers | 200 |
| `revisor-entrada` | 28 | 28 | answers | **000** (28) |
| `acceso-revisor-salida` | 28 | 28 | answers | 200 |
| (all six in place) | 200 | `prueba OK` | answers | 200 |

Each row tells something different. Removing `revisor-entrada` is the only one that takes the entry point down, because it is the one that lets Envoy through. Removing `acceso-revisor-salida` leaves `depurar` with no way out, but the entry point carries on (in this cluster nobody created policies in Envoy's namespace, so its egress is not closed). Removing `revisor-salida` or `prueba-entrada` produces **the same symptom**, `prueba FALLA` by timeout, with different causes: in one case the `revisor` cannot go out, in the other `prueba` cannot receive. And a symptom like that does not say which of the two policies is missing. It is the kind of failure for which `describe networkpolicy` is used.

The complete blocks of the five tests, with their commands, are in `correr.salida.txt`. Here is the stretch that has a story, the one for `revisor-salida`. In an earlier run, which was not saved, this row came out `prueba OK` even without the rule. It could not be repeated (in this run it came out `FALLA` the first time) and we do not know the cause. There are two possible explanations and neither was verified. One: a connection that was already open stayed alive with the rule removed; the network policies documentation leaves that case to each add-on (“it is implementation-defined” whether the change takes effect on an existing connection) and recommends not modifying policies in a way that affects them. Another: the policy was not yet programmed, which is what 7.5.7 measures. That is why the script waits, and here it also **restarts the `revisor`**, so that the test opens a new connection:

```text
$ kubectl delete networkpolicy revisor-salida -n revisor
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.001s  se acabo el tiempo de espera

$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 3 new replicas have been updated...
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

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera
```

Both reports say `prueba FALLA`: the one from before the restart and the one from after. In this run the restart did not change the result (the report already said `FALLA` before); it is a precaution of the method, not proof of the cause.

The moral is about method, and it is worth more than the table. **A result that says “it still works” after removing a rule does not prove the rule was unnecessary.** It may be an old connection, a cache, or a test that does not ask what you think. A network test must open a new connection every time.

### The error you will see (the second one)

The second error is the one that wastes the most time with network policies. It looks like the scene, but in miniature: you have a policy that **opens** the `revisor`'s ingress, you have a Pod with the right label, and the Pod does not get through. It is triggered by deleting the last policy, `acceso-revisor-salida`, which is the ingress's partner:

```text
$ kubectl delete networkpolicy acceso-revisor-salida -n revisor
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl get networkpolicy -n revisor
NAME              POD-SELECTOR   AGE
cerrado           <none>         41s
dns               <none>         41s
prueba-entrada    app=prueba     41s
revisor-entrada   app=revisor    41s
revisor-salida    app=revisor    41s

$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          7m38s   acceso-revisor=permitido,app=depurar
```

It is read in this order. **First, the symptom:** code 28, timeout; the Pod has the label `acceso-revisor=permitido` and the `revisor-entrada` policy exists. Everything you look at says it should get through. **Second, the policy list:** `cerrado`, `dns`, `prueba-entrada`, `revisor-entrada` and `revisor-salida` are there; `acceso-revisor-salida` is missing. **Third, the principle:** an ingress policy opens one side of the door. The Pod that wants to get in is isolated for **egress** by `cerrado`, and nothing opens it. This network's first version, which opened only the ingress, left `depurar` unable to get out. **The fix** is the file, as always: `kubectl apply -k .` recreates the missing one, and `depurar` gets through again.

```text
$ kubectl apply -k . | grep networkpolicy
networkpolicy.networking.k8s.io/acceso-revisor-salida created
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

**The order, when a Pod does not reach another with network policies:**

1. `kubectl exec … curl -m 3`: which code? 28 is network silence; 7 is that nobody is there; 4xx or 5xx means it did arrive.
2. `kubectl get networkpolicy -n <namespace>` in the namespace of **both** ends.
3. For each end, which policies select it and for which direction? Either the caller's egress or the receiver's ingress is missing.
4. Does the name resolve? If not, `dns`.
5. Is the label on the Pod, or on the Deployment but **not** in the Pod template?

#### 7.5.7 Policies are not applied instantly

So far, every time the script changes a policy, it waits before asking: those are the `sleep 8`s you see in the outputs. They are not decoration, and this section tells where the eight comes from. A three-second wait was not enough in one of this lesson's test runs (that run's output was not saved): with the six policies already in place, the `intruso` asked the API for `/livez` and received `ok`, whereas in the other runs that same question timed out. Nothing was broken: the question was asked **before the network finished learning** the new policies. It was measured on purpose. The script repeats this sequence six times: it deletes the six policies, waits one second, applies them again and, from that moment, asks the API six times from the `intruso`, with a maximum of one second per question, noting how many seconds have passed and what code it received:

```text
$ for ciclo in 1 2 3 4 5 6; do   # borrar las seis, esperar 1 s, volver a aplicarlas y preguntar seis veces a la API desde el intruso
ciclo 1: +0s:200 +0s:200 +0s:200 +2s:000 +3s:000 +6s:000
ciclo 2: +2s:000 +3s:000 +5s:000 +6s:000 +7s:000 +9s:000
ciclo 3: +0s:200 +1s:200 +1s:200 +2s:000 +7s:000 +10s:000
ciclo 4: +5s:000 +6s:000 +9s:000 +12s:000 +17s:000 +20s:000
ciclo 5: +6s:000 +9s:000 +12s:000 +15s:000 +19s:000 +23s:000
ciclo 6: +3s:000 +6s:000 +9s:000 +12s:000 +13s:000 +15s:000
```

It reads like this: `+1s:200` is “one second after applying, the API answered (200)”, and `000` is “it did not answer” (the time ran out). In cycles 1 and 3, the first questions get an answer and the following ones no longer do: the last answer arrived between 0 and 1 seconds after the `apply`, and the first unanswered question, at 2 seconds (with a maximum of one second per question, and with what each `kubectl exec` adds, the clock's imprecision is about that size). In cycles 2, 4, 5 and 6 the first question already goes out at 2, 5, 6 and 3 seconds, because on this loaded machine each `kubectl exec` took seconds to start, and it already finds the network closed. In no cycle did a question get through after the first unanswered one. The `kubectl apply` had already finished and the `NetworkPolicy` object already existed in the API: what was missing was for the network add-on, on each node, to read it and turn it into rules. That conversion takes seconds and, in the meantime, the Pod stays open. With what was measured here, the window is about 2 seconds at most (in an earlier run, which was not saved, up to 3 were seen); eight seconds is a chosen margin, two and a half to four times that, and not a result. After the script's eight seconds, the same question timed out, and in this run none of the eight-second waits showed otherwise:

```text
$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -o /dev/null -w '%{http_code}\n' https://kubernetes.default.svc/livez
000
command terminated with exit code 28
[código de salida: 28]
```

Limits of this measurement: six cycles, a loaded machine, a single effect measured (that `cerrado` closes the `intruso`'s egress; the six policies are applied together) and only the “closing” direction; the “opening” direction (deleting a policy, which is what the `sleep 8`s of 7.5.6 do) was not measured. Three practical consequences, which are what justify an entire section:

1. **A network test run too early gives a false “it does get through”.** It is the same method defect as in 7.5.6, in the opposite direction. After changing policies, wait and measure more than once. The network policies documentation does not promise a speed of enforcement: the only thing it says is that the effect on existing connections is implementation-defined. The time measured here belongs to this machine, with three kind nodes loaded with other clusters, and is not a property of the add-on.
2. **Changing a policy is an operation with a window.** Deleting the policies and applying them again (the cycle in this very section, or a `kubectl delete -f red.yaml` followed by a `kubectl apply -f red.yaml`) leaves the Pods open during the window, in a cluster where the policies are the only thing closing them. To change a policy on a live cluster, you create the new one **before** removing the old one; you do not delete it in order to recreate it.
3. **Creation order matters.** If a Pod is born before the policies that close it are programmed, it is born open for a moment. In 7.2.3 you saw that `kubectl apply -k` created the six policies **after** the Deployments (the order of the `resources` list does not govern: Kustomize emits the objects in its own order), so the `revisor`'s first replicas could have been born open for a few seconds (this is a deduction from the order of the lines, not a measurement of a newborn Pod). In a real cluster, a namespace's policies are applied first and you wait, and then the project goes in.

#### 7.5.8 What this network does not protect against

This network is better than no network, and it is worth saying exactly how much better.

- **The `acceso-revisor` label is set by whoever creates the Pod.** Anyone with permission to create Pods in `revisor` can hand themselves the key. The policy protects against Pods that **do not** know the label exists, not against someone with access to the namespace. The layer that guards this is RBAC: in a real cluster, creating Pods in `revisor` is a permission handed out sparingly. Exercise 1 also shows that the label is worthless in the wrong namespace.
- **`revisor-entrada` trusts the entire entry point namespace.** It admits **all** the Pods in `envoy-gateway-system`. If that namespace hosts something else, that gets in too. The policy is only as strict as whoever controls that namespace.
- **It encrypts nothing.** An authorized Pod speaks plain HTTP with the `revisor`. The network says who can arrive, not that what travels is protected.
- **`hostNetwork` Pods and node traffic.** The documentation says that the behavior of policies with `hostNetwork` Pods is undefined and that the most common outcome is that the add-on ignores them and treats their traffic as node traffic. And traffic from the node to its Pods (the probes) is not blocked. The `port-forward` is not stopped by the policy either, and the `port-forward` guide warns that it can bypass network controls: that one is guarded by RBAC (`create` on `pods/portforward`). That is why 7.3's `restricted` level, which forbids `hostNetwork`, and the network complement each other.
- **There is no default policy for the whole cluster.** The same page lists as an API limitation that you cannot apply default policies to all namespaces or Pods. `cerrado` has to be written in each namespace, and a new namespace is born open.
- **It only works because the add-on enforces them.** In this run it was measured that kindnet enforces them. On another cluster it has to be measured the same way: the cluster stores the policies without complaint even if nobody makes them take effect.


## The lesson's security habit: namespace of its own, `restricted` level, minimal permissions and default-deny network

The course's habit table assigns this lesson four things in a single line: namespace of its own, `restricted` level, minimal permissions, default-deny network. Each one is checked with a command, and the most honest check is the one that looks for what is missing, not for what is left over. The inventory:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       13m

$ kubectl apply -k . 2>&1 | grep -c -i warning || true
0

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken'
POD                       CUENTA       AUTOMOUNT
depurar                   default      false
intruso                   default      false
lector                    observador   true
prueba-6899c74865-rgh68   prueba       false
revisor-d86b5794d-5fspg   revisor      false
revisor-d86b5794d-hx92n   revisor      false
revisor-d86b5794d-tmq5g   revisor      false
```

Read it as four questions. **What is published to the outside?** A single `LoadBalancer`-type Service in the entire cluster: Envoy's, in `envoy-gateway-system`, with the IP MetalLB gave it. Lesson 6's `revisor-publico` no longer exists, and the only entry point is the named one. **Does the project meet the level its namespace demands?** Applying the `kustomization` again produces not a single warning (`0` lines with `warning`), and the `--dry-run=server` test of the final state (in “How I know I made it”) says `not labeled`. **Who has credentials?** Only `lector`, the Pod from the 7.4.4 practice, which asked for them on purpose (`AUTOMOUNT true`); the `revisor`, `prueba`, `depurar` and `intruso` say `false`. **Is the network closed?** Six policies in `revisor`, and 7.5 measured what each one opens.

Why are these **security** habits and not just tidiness? Because each layer closes a specific path that was measured open. A namespace with `restricted` stops the data team (or your own slip) before a Pod with excess privileges exists. An account with no permissions and no token leaves a compromised container with nothing to present to the API (the `intruso` in 7.4.4 did not even have a file). And the closed network turns “any Pod talks to any Pod” into a short list that can be read, reviewed and argued over, which is the lesson's most valuable change: the attack surface went from implicit to written down.

**What it protects against and what it does not.** The lesson measured this, one by one:

| Layer | Protects against | Does not protect against |
|---|---|---|
| Namespace | name collisions; scope of permissions | traffic between Pods (7.5.3: they reached each other across namespaces) |
| Pod Security `restricted` | creating Pods with privileges, `root`, `hostNetwork` | Pods that were already running (7.3.4); someone with permission to change the namespace's label |
| Account with no token or permissions | credential theft from a Pod that does not need them | a Pod that does need them and is compromised (the `lector`: it reaches what its `Role` reaches) |
| Closed network | lateral movement between Pods; access to the API from Pods without a key | whoever can set the label; node traffic; the contents of what travels (plain HTTP) |

And the full picture, so that this is not read as a production recipe: missing are encryption in transit, a resource cap per namespace (`ResourceQuota`, `LimitRange`), encryption of the Secrets inside the cluster, auditing of the `kube-apiserver` and the management of who has permission to touch this namespace. Lesson 10 gathers the list of what the whole project still lacks to run for real.

## Common mistakes

**Believing that a namespace isolates the network.** It looks like it does, because the signs are everywhere. 7.5.3 measured it: a Pod in `default` reached the `revisor` Service by writing its full name.

**Applying a network policy and not checking that the add-on enforces it.** The cluster stores the object without complaint and the traffic stays the same. You test it with a keyless Pod that must fail, not by reading the manifest.

**Closing ingress and forgetting egress.** `cerrado` isolates both directions, and opening only the destination's ingress leaves the caller unable to get out. They are two halves of a single permission. It is the lesson's second error.

**Closing egress and forgetting DNS.** Without the `dns` rule, names do not resolve and the symptom looks like “the network is broken” when only the name lookups are missing.

**Concluding from a “it still works”.** An already-open connection can survive a policy change, and the documentation leaves it to each add-on. A network test opens a new connection every time.

**Setting `enforce` and believing the namespace is now clean.** The label rejects what arrives, it does not evict what is already running. And the old Pod that violates the level dies at a rollout: the day you recreate it, it can no longer be born.

**Leaving `enforce` without a version.** `restricted:latest` changes when the cluster is upgraded. Pin the version (`enforce-version`) and raise it on purpose.

**Looking only at the `enforce` mode.** A Deployment that violates the policy **gets created**, with a warning that almost nobody reads, and ends up with no Pods. The `warn` mode's warnings are read, or redirected to a log that someone reviews.

**Granting permissions with wildcards (`*`).** The RBAC documentation warns about it: a wildcard on resources or verbs also grants whatever the cluster adds one day. You name each resource and each verb.

**Leaving the token mounted for an account that does not use it.** It is a credential in every replica, with no benefit. `automountServiceAccountToken: false`, on the account or on the Pod.

**Giving the `acceso-revisor` label to any Pod “to make it work”.** Every Pod with the key is one more Pod that can talk to the `revisor`. The key is given to whoever needs it, and you ask why.

**Trusting an entire namespace as a source.** `revisor-entrada` accepts all the Pods in `envoy-gateway-system`. It is a reasonable decision as long as that namespace belongs only to the platform, and it stops being one the day something else lives there.

## Exercises

The first three are run in the lesson's cluster, in order and from the state it was left in after 7.5. Before each one, `ctx` must let the chain through. `correr.sh` runs them the same way, and its output is in `correr.salida.txt`. **Before** running each one, write in the [log](bitacora.md) what you think is going to happen. The fourth is written in your own words.

### Exercise 1 — The right label in the wrong namespace

Apply `depurar.yaml` in the `default` namespace, with `ctx && kubectl apply -n default -f depurar.yaml`. It is the same manifest, with the same label `acceso-revisor: permitido`. Before looking, predict: can that Pod talk to the `revisor` using the full name, `http://revisor.revisor.svc.cluster.local/salud`? And the `depurar` in the `revisor` namespace? Explain the difference in the words of 7.5.5: what does the `revisor-entrada` policy select, and from **which namespace**? When you finish, delete the Pod in `default`.

### Exercise 2 — An account that can only restart the `revisor`

`fig07_03.reiniciador.yaml` creates an account, a `Role` and a `RoleBinding`:

```yaml
# fig07_03.reiniciador.yaml — Ejercicio 2: una cuenta que puede reiniciar el
# revisor y NADA más. rollout restart necesita leer el Deployment (get) y
# cambiarle una anotación (patch); resourceNames lo limita a UN Deployment.
# Se aplica con: kubectl apply -n revisor -f fig07_03.reiniciador.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reiniciador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: reiniciador
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["revisor"]
  verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: reiniciador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: reiniciador
subjects:
- kind: ServiceAccount
  name: reiniciador
  namespace: revisor
```

`kubectl rollout restart` needs to read the Deployment (`get`) and change an annotation on it (`patch`). Apply it with `ctx && kubectl apply -n revisor -f fig07_03.reiniciador.yaml` and predict, before running anything: can the account restart the `revisor`? And `prueba`? Can it **list** Deployments? Check your three predictions with `kubectl auth can-i … --as=system:serviceaccount:revisor:reiniciador` and then with a real `kubectl rollout restart`. Why does `can-i list deployments` answer differently from `can-i patch deployment/revisor`? When you finish, delete what you created with `ctx && kubectl delete -n revisor -f fig07_03.reiniciador.yaml`.

### Exercise 3 — A route that comes from another namespace (project)

The entry point lives in `revisor`. Another team, in `default`, wants to publish a route of its own through that same entry point. `fig07_05.ruta-ajena.yaml` is its `HTTPRoute`:

```yaml
# fig07_05.ruta-ajena.yaml — Ejercicio 3: una HTTPRoute que vive en el espacio
# «default» y pide colgarse del Gateway «revisor», que vive en «revisor».
# Pregunta: ¿la acepta el Gateway? ¿Qué dice su estado? Se aplica con:
#   kubectl apply -n default -f fig07_05.ruta-ajena.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ajena
spec:
  parentRefs:
  - name: revisor
    namespace: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /ajena
    backendRefs:
    - name: revisor
      namespace: revisor
      port: 80
```

Before starting, two different permissions that are worth not confusing. `allowedRoutes`, inside the `Gateway`'s `listeners`, says **who may attach to the entry point**: by default (`from: Same`) only the routes from the same namespace as the `Gateway`; `All` and `Selector` open the entry point to other namespaces. `ReferenceGrant` lives in the **destination**'s namespace and says **who may point at its Services**: a route from another namespace cannot use a Service in `revisor` as a destination unless the owner of that namespace allows it. The first is granted by the entry point's owner; the second, by the Service's owner. The reference pages: [`ReferenceGrant`](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/), the [API reference](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) and the [cross-namespace routing guide](https://gateway-api.sigs.k8s.io/guides/multiple-ns/).

Apply it in `default`. Read its status with `kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'`. There are **two** different problems in that status. Before looking at yours, predict which they are, which object each one depends on and who has to grant each permission: the entry point's owner, the Service's owner or the team that writes the route? Fix first the one that comes from the entry point (the hint: `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces`) and then the other with `fig07_06.referencegrant.yaml`:

```yaml
# fig07_06.referencegrant.yaml — Ejercicio 3: el permiso que da el DUEÑO del Service.
# Vive en el espacio «revisor» (el del Service destino) y dice: las HTTPRoute del
# espacio «default» pueden usar como destino los Service de este espacio.
# Se aplica con: kubectl apply -n revisor -f fig07_06.referencegrant.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: rutas-de-default
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: default
  to:
  - group: ""
    kind: Service
    name: revisor
```

Check at the end that `GET /ajena` through the entry point reaches the `revisor` (the response is a `404` from the `revisor`, not from the entry point: how do you prove it with its log?), and undo everything you changed, the `Gateway` included.

### Exercise 4 — Defend the design

In five sentences at most, answer: (1) Why did this lesson not install Calico, and what evidence backs that up? (2) What would happen to the probes if `kindnet` enforced the policies but node traffic were also blocked? (3) Which of the six policies would you change if the data team needed a service of **its own** in the `revisor` namespace that also receives traffic from the entry point? (4) What is missing for `acceso-revisor: permitido` to be a protection and not just an agreement? (5) The `dns` policy opens egress to the `k8s-app: kube-dns` Pods in `kube-system`; what would happen to name resolution if CoreDNS moved to another namespace?

## Solutions

### Solution 1

Measured in `correr.salida.txt`:

```text
$ kubectl apply -n default -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -n default --show-labels
NAME      READY   STATUS    RESTARTS   AGE   LABELS
depurar   1/1     Running   0          6s    acceso-revisor=permitido,app=depurar

$ kubectl exec -n default depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

The Pod in `default` has the label, and still **code 28**. The `depurar` in `revisor` answers. The `revisor-entrada` policy does not select “the Pods with the label” in the abstract: in its `from` list, the `podSelector` without a `namespaceSelector` refers to the Pods **in the namespace where the policy lives**, that is, `revisor`. The label in another namespace does not count. The list's second element (`namespaceSelector`), on the other hand, picks whole namespaces, and that is why Envoy gets in. For the Pod in `default` to get in, you would have to add an element with `namespaceSelector` and `podSelector` **together**: the Pods with that label, in that namespace. Notice also that the long name did resolve (the `dns` rule is open for everyone); what failed was the connection.

### Solution 2

Measured in `correr.salida.txt`:

```text
$ kubectl apply -n revisor -f fig07_03.reiniciador.yaml
serviceaccount/reiniciador created
role.rbac.authorization.k8s.io/reiniciador created
rolebinding.rbac.authorization.k8s.io/reiniciador created

$ kubectl auth can-i patch deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
yes

$ kubectl auth can-i patch deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl auth can-i list deployments -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl rollout restart deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
deployment.apps/revisor restarted

$ kubectl rollout restart deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
Error from server (Forbidden): deployments.apps "prueba" is forbidden: User "system:serviceaccount:revisor:reiniciador" cannot get resource "deployments" in API group "apps" in the namespace "revisor"
[código de salida: 1]
```

`patch` on `deployment/revisor` answers `yes`, on `prueba` `no`: the `Role` names the Deployment with `resourceNames: ["revisor"]`. The `revisor`'s restart works (`restarted`) and the one for `prueba` gives a `Forbidden` saying `cannot get resource "deployments"`: `rollout restart` begins by reading the Deployment, and that read is already forbidden. `list deployments` answers `no` for the simplest reason: the `Role` grants only `get` and `patch`, and `list` is another verb. That `get` is limited to a name does not turn `get` into `list`: reading one by name and listing are separate permissions (you saw it in 7.4.3 with the Secrets). And even if the `Role` added `list`, the RBAC documentation warns that restricting `list` or `watch` with `resourceNames` forces the client to send `--field-selector=metadata.name=revisor`: a bare `kubectl get deployments` would still answer `no`. That account can restart one service and cannot see the others. It is the minimal permission the lesson describes, and it is the example of why `resourceNames` is written instead of granting `patch` on all Deployments.

### Solution 3

Measured in `correr.salida.txt`:

```text
$ kubectl get gateway revisor -n revisor -o jsonpath='{.spec.listeners[0].allowedRoutes}{"\n"}'
{"namespaces":{"from":"Same"}}

$ kubectl apply -n default -f fig07_05.ruta-ajena.yaml
httproute.gateway.networking.k8s.io/ajena created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=False NotAllowedByListeners: No listeners included by this parent ref allowed this attachment.
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

The `Gateway` says `{"namespaces":{"from":"Same"}}`: **only routes from its own namespace**. You did not write it; it is the type's default value (`kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` says “restricted to the Gateway's namespace by default”). And the route in `default` comes out with two conditions false, from two different mechanisms:

- **`Accepted=False NotAllowedByListeners`**: the Gateway's *listener* does not admit routes from `default`. It is decided by the entry point's owner, with `allowedRoutes`, **on the Gateway**.
- **`ResolvedRefs=False RefNotPermitted`**: the route points at a Service in another namespace, `revisor/revisor`, and no `ReferenceGrant` allows it. It is decided by the owner of the **destination**, with an object in **its** namespace.

The route's status sums it up in two lines: crossing namespaces when **attaching** to a Gateway is governed by the Gateway; crossing namespaces when **pointing** at a Service is governed by whoever owns the Service (`kubectl explain referencegrant.spec` describes it as the namespaces and types that are trusted to reference the `to` resources). They are two permissions with two owners, and the status keeps them apart: `Accepted` answers to the Gateway's listener (`allowedRoutes`) and `ResolvedRefs` answers to the `ReferenceGrant`. A `ReferenceGrant` talks about what a route may **point at**; whether a route may **attach** to someone else's Gateway is a matter for `allowedRoutes`. The first is fixed by labeling the route's namespace and telling the listener to accept the namespaces with that label:

```text
$ kubectl label namespace default acceso-puerta=permitido
namespace/default labeled

$ kubectl patch gateway revisor -n revisor --type=json -p '[{"op":"add","path":"/spec/listeners/0/allowedRoutes","value":{"namespaces":{"from":"Selector","selector":{"matchLabels":{"acceso-puerta":"permitido"}}}}}]'
gateway.gateway.networking.k8s.io/revisor patched

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

`Accepted` turned `True`; `ResolvedRefs` is still `RefNotPermitted`: the first permission does not fix the second. The destination's permission is the `ReferenceGrant`, which lives in the Service's namespace (`revisor`) and names whose references it accepts:

```text
$ kubectl apply -n revisor -f fig07_06.referencegrant.yaml
referencegrant.gateway.networking.k8s.io/rutas-de-default created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=True ResolvedRefs: Resolved all the Object references for the Route
```

Both conditions true. And the proof that the route reaches the `revisor`:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/ajena   # desde fuera del clúster
404

$ kubectl logs -n revisor -l app=revisor --tail=-1 | grep -E 'GET /ajena'
revisor: GET /ajena 404 0s
```

The outside client receives `404`. That `404` is **not from the entry point**: the `revisor`'s log has the line `GET /ajena 404`, that is, the request reached a `revisor` replica, which does not know that route. (If the entry point had found no route, the `404` would not appear in the `revisor`'s log.) The network policy did not get in the way because the destination is the `revisor` itself, and `revisor-entrada` already admits Envoy's Pods: the two layers, routes and network, both said yes. They are different layers, and both have to say it. That `Same` is the default value documented by the [Gateway API reference](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) for `allowedRoutes.namespaces.from`, and the cluster confirmed it with the first command; the [cross-namespace routing guide](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) explains how to open it up with `Selector` or `All`.

The script undoes everything: it deletes the route, the `ReferenceGrant`, the label on `default` and the `allowedRoutes` field you added to the `Gateway`; the final state's `kubectl diff -k .` confirms that the cluster went back to what the files say.

### Solution 4

One possible answer: “(1) Because kindnet enforced the policies: with `cerrado` alone, the `intruso` and the Pod with the label stopped getting through (code 28), and with all six only what they said was opened; that is the measurement the course plan left pending. (2) The probes would fail: the `kubelet` runs them from the node and they would be blocked, the readiness probe would take all the replicas out of the list and the liveness probe would restart them; the documentation says node traffic is allowed, and this lesson measured `RESTARTS 0`. (3) None of the six: a new policy would be added, `entrada` for that service, with the same `namespaceSelector` as the entry point; policies add up and you do not edit other people's. (4) That whoever can create Pods in `revisor` cannot give themselves the label: RBAC that limits who creates or changes Pods in the namespace, or an admission policy that validates the label. (5) The egress to DNS would stop matching the new DNS Pods and names would stop resolving, with the same symptom as removing the `dns` rule in 7.5.6: the `nslookup` times out and `curl` by name fails with 28, while the entry point keeps answering, as in that row of the table.”

## Deleting the cluster

When you finish the exercises, delete the lesson's cluster. Leave nothing alive on the machine:

```text
$ kind delete cluster --name curso-k8s-l7
Deleting cluster "curso-k8s-l7" ...
Deleted nodes: ["curso-k8s-l7-worker2" "curso-k8s-l7-worker" "curso-k8s-l7-control-plane"]

$ kind get clusters | grep -c curso-k8s-l7
0

# disco de Docker: 77% usado
# la corrida completa tardó 1569 s
```

(The parenthetical line is written by the script, which measures the deletion.) The `--name` is mandatory: without it, kind would delete the cluster called `kind`, which may belong to someone else.

What remains on your machine is the temporary `kubeconfig` folder and `token.txt` (you deleted the one in `punto-de-partida/` in 7.2.3; the `rm` below includes it in case you did not). They are deleted like this, from `programas/07-aislar-permisos-red`:

```bash
# Los tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 7.1.1.
case "$L7_TMP" in
  /tmp/curso-k8s-l7.?*) rm -rf -- "$L7_TMP" ;;
  *) echo "No borro «$L7_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L7_TMP
unset -f ctx
```

The `case` only lets through a path that starts with `/tmp/curso-k8s-l7.` and has something after it, the exact form of the one you created in 7.1.1. If `L7_TMP` is empty (because you are in another terminal where you never defined it) or holds something else, it deletes nothing and tells you why. It is the same protection `correr.sh` uses when cleaning up. The last line removes the `ctx` function from your terminal.

If on this machine you ran the lesson with a Docker network of its own (`correr.sh`'s `CURSO_RED` variable), that network is also yours and you delete it, **after** the cluster and only if you created it for this: `docker network rm curso-k8s-red-l7`. With the usual `kind` network there is nothing to delete: it belongs to all your clusters. The next lesson's cluster is created from scratch, just like this one.

## How I know I made it

Before the checkboxes, the final state as the run left it, copied from `correr.salida.txt`. First the exercises' Pods are deleted and the cluster is asked whether anything differs from the project's files, and then the entry point is looked at from outside and the 7.3 test is repeated:

```text
$ kubectl delete -n revisor pod depurar intruso lector --wait=false
pod "depurar" deleted from revisor namespace
pod "intruso" deleted from revisor namespace
pod "lector" deleted from revisor namespace

$ kubectl delete -n default pod intruso --wait=false
pod "intruso" deleted from default namespace

$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/api/estados   # desde fuera del clúster
401

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

They read like this. `sin diferencias con los archivos` (no differences from the files) means the exercises were undone: the cluster is exactly what the files say. The `401` is the `revisor` behind its entry point: the entry point answers, but `/api/estados` asks for the token and from outside you do not carry it. And `not labeled (server dry run)` with no warnings closes 7.3: asking again for the `restricted` level on `revisor` changes nothing because it already has it, and no existing Pod violates it.

- [ ] You state, with a command, what a namespace does **not** isolate: a Pod in `default` reaches `revisor.revisor.svc.cluster.local` if there are no policies.
- [ ] Faced with a Deployment with `READY 0/1` and no Pods, you go to the ReplicaSet and find `FailedCreate … violates PodSecurity`; and you know why `apply` did not fail.
- [ ] You read a `restricted` rejection and name the four rules and the `securityContext` line that fixes each one.
- [ ] You write a `Role` and a `RoleBinding` without wildcards, and test what is allowed and what is denied with `kubectl auth can-i … --as=…`, with a real request and from inside a Pod.
- [ ] You explain why the `revisor` has no token mounted and the `lector` does, and what the `lector` reaches with its own.
- [ ] You tell `exit code 28` (network silence), `7` (nobody listening) and `403` (it did arrive and was denied) apart.
- [ ] You say, for each of the six policies, what breaks if it is missing, and why `revisor-salida` and `prueba-entrada` produce the same symptom.
- [ ] You run `programas/07-aislar-permisos-red/correr.sh > /tmp/mi-corrida-l7.txt 2>&1` and compare `/tmp/mi-corrida-l7.txt` against `programas/07-aislar-permisos-red/correr.salida.txt` (do not redirect to that file: it is the reference) on what does not change between runs: three `Ready` nodes (the node version is pinned by `kind-curso.yaml` through its digest); `-rw-------` on both `token.txt` files; the seven labels on the `revisor` namespace with `restricted` and `v1.37`; `default` with only the `kubernetes` Service; the rejection `violates PodSecurity "restricted:v1.37"` with its four rules; `baseline:latest` rejects `hostNetwork` and accepts the simple Pod; `namespace/revisor not labeled (server dry run)`; the ReplicaFailure of `sinreglas`; in the `can-i`s, `no` for the `revisor`, `yes` to reading Pods and logs with `observador` and `no` to deleting, to reading Secrets and to reading in `default`; `pods 200`, `secrets 403`, `pods-default 403` and the missing directory in `intruso`; with no rules, the tests answer; with `cerrado`, they give 28 and `000` from outside; with all six, `depurar` gets through and `intruso` does not; and the five rows of the 7.5.6 table. The IPs, the name suffixes, the ages, the Secret's name, the milliseconds and the startup times change on every run: they are observed, not compared.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l7`.

## Summary

Answer without looking at the lesson:

1. Which two things does a namespace isolate and which does it not? What did 7.5.3 measure to demonstrate it?
2. What are the three modes and the three levels of Pod Security Admission, and how are they written on the namespace?
3. Why does a Deployment that violates `restricted` get created and end up with no Pods? Where is the reason?
4. What does a `Role` add and what does a `RoleBinding` add? What does it mean that permissions are additive?
5. What does `kubectl auth can-i … --as=system:serviceaccount:NAMESPACE:ACCOUNT` do and what exit code does it return with `no`?
6. Why does the `revisor` declare `automountServiceAccountToken: false`, and what is measured with the `lector`, which has it set to `true`?
7. When is a Pod isolated for ingress? What happens if two policies select it?
8. What condition does a `NetworkPolicy` need in order to have any effect, and how was it checked on kind?
9. What do `exit code 28`, `exit code 7` and `403` mean?
10. Why does `acceso-revisor-salida` exist? And why `dns`?
11. What does `allowedRoutes` cover and what does `ReferenceGrant` cover?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, “Namespaces”](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/): namespaces as a mechanism for isolating groups of resources, unique names per namespace, namespaced and non-namespaced objects, the `kube-system` namespace, and the automatic label `kubernetes.io/metadata.name`.
- [Kubernetes, “Pod Security Admission”](https://kubernetes.io/docs/concepts/security/pod-security-admission/): the three modes (`enforce`, `audit`, `warn`), the three levels, the syntax of the labels with and without a version, and that `enforce` applies to Pods and not to workloads.
- [Kubernetes, “Pod Security Standards”](https://kubernetes.io/docs/concepts/security/pod-security-standards/): the definitions of `privileged`, `baseline` and `restricted`.
- [Kubernetes, “Enforce Pod Security Standards with Namespace Labels”](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): how to set the labels on a new namespace and on an existing one, the `--dry-run=server`, and that when `enforce` is added the controller tests the existing Pods and returns warnings.
- [Kubernetes, “Service Accounts”](https://kubernetes.io/docs/concepts/security/service-accounts/): what a service account is, each namespace's `default` account, the automatic mounting of credentials and the short-lived tokens since 1.22.
- [Kubernetes, “Configure Service Accounts for Pods”](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/): how to disable mounting on the account and on the Pod, and that the Pod takes precedence.
- [Kubernetes, “Using RBAC Authorization”](https://kubernetes.io/docs/reference/access-authn-authz/rbac/): `Role` and `ClusterRole`, `RoleBinding`, that permissions are purely additive, the default roles (`system:basic-user`, `system:discovery`), the risk of wildcards and the restrictions by `resourceNames`.
- [Kubernetes, “Network Policies”](https://kubernetes.io/docs/concepts/services-networking/network-policies/): the isolation model (non-isolated until a policy selects the Pod, and additive policies), the requirement of an add-on that enforces them, node traffic, `hostNetwork`, the API's limits, and the impact on existing connections.
- [Kubernetes, “Use Port Forwarding to Access Applications in a Cluster”](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/): that `port-forward` is authorized by RBAC with `create` on `pods/portforward`.
- [kind, “Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/): the default network add-on (`kindnetd`) and how to disable it.
- [kind, release notes for v0.24.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0): the network policy support with `sigs.k8s.io/kube-network-policies`.
- [Gateway API, “Cross-Namespace routing”](https://gateway-api.sigs.k8s.io/guides/multiple-ns/): routes that attach to a Gateway in another namespace with `allowedRoutes`.
- [Gateway API, “ReferenceGrant”](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): the destination namespace's permission for a route to point at its Service; the `from` and `to` fields, and that it only authorizes references to resources in its own namespace.
- [Gateway API, API reference (spec)](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/): `RouteNamespaces` and its default value, `from: Same`. The same was read in the cluster itself with `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` and `kubectl explain referencegrant.spec`, and the route's `RefNotPermitted` status confirms it.
- [CyberScoop, “Tesla falls victim to cryptomining scheme, minor breach”](https://cyberscoop.com/tesla-cryptomining-redlock-cloud-breach/) (February 20, 2018): the case the lesson opens with, based on RedLock's report.

---

**Next:** [Lesson 8 — Data and tasks](08-datos-y-tareas.md)
