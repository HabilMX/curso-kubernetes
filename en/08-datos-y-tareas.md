# Lesson 8 — Data and tasks

Monday, 7:12 in the morning. At 9:00 there is a meeting with the payments service provider, and your boss sends you a one-line message: “I need Friday's report from 6 in the evening, the one that showed `prueba` down for forty minutes. It's the proof for the claim.” You open the cluster with the calm of someone who knows the `revisor` keeps its report in a file, `/datos/reporte.json`. You list the Pods and see something you did not expect: all three replicas are less than two days old. On Saturday, during the early-morning maintenance, someone drained the nodes one by one to upgrade them (with `kubectl drain`, which evicts the Pods from a node) and the cluster did what it knows how to do: it deleted the old Pods and the Deployment created new Pods on other nodes. You ask for the file. It is not there. You look in the other two replicas. Not there either. And even if it had been, you realize something worse as you think it through: the `revisor` keeps **the latest** report and writes over the previous one. Friday's would have been lost anyway with the first query on Saturday.

It is 7:20. You have a hundred minutes to find a way to say “I don't have it” that does not sound like “I didn't save it”.

This is not a freak case of bad luck. It is what happens when a container is mistaken for a safe. In 2017, the GitLab team published the account of the hours in which it lost production data and discovered that its backup mechanisms were not working when they were needed: the daily copies were failing silently and the bucket where they should have been was empty, disk snapshots were not enabled on the database servers, and the replica was broken. Its report (the sources cite it, with the link) is a good reminder that the question is not “do I have a backup?” but “have I tested it?”. This lesson is more modest: it does not build backups. It teaches you the earlier half, the one almost everyone discovers late: **which part of what a Pod writes survives the Pod itself, and which part does not**. With that answer in hand, Friday's report stops depending on luck: a scheduled task asks the `revisor` for its report and saves it, with the date in the name, in a volume that outlives the Pods (as long as the claim exists and the node where the disk lives does). It is no longer a line that gets overwritten: it is a file with a name and a date.

The lesson has two halves that need each other. The first is the **where**: volumes that live longer than Pods. The second is the **when**: tasks that run once, or every five minutes, without anyone launching them. Together they resolve the scene: a scheduled task asks the `revisor` for its report every five minutes and saves it with the date in the name, in a volume that outlives the Pods.

**Time:** 2 × 45 min

**What you build:** the saved report and the `revisor` as a scheduled task: a persistent volume called `reportes`, a task (`Job`) that asks the `revisor` for its report using the token and writes it with the date in the name, and a `CronJob` that repeats it every five minutes, with a service account that has no permissions and no mounted credentials

**What you learn:** what survives and what does not when a container crashes and when a Pod is deleted (`emptyDir`); `PersistentVolume`, `PersistentVolumeClaim` and `StorageClass`, and kind's storage class; why the claim waits for its first Pod; `Job` and `CronJob` with their retries, their schedule and their history; file ownership with `fsGroup`; what is lost when the claim is deleted; and a requested size that the cluster does not enforce

**Where you are coming from.** From Lesson 7: the `revisor` and the test service live in a namespace of their own, `revisor`, which requires the `restricted` level of Pod Security Admission; each workload has its service account with no mounted credentials; and the network is closed by default, with named openings: only Pods with the label `acceso-revisor: permitido` and the entry point's Envoy proxies can reach the `revisor`. From [Lesson 4](04-configuracion-secretos.md), the token as a `Secret` mounted as a file and the names with a *hash* that Kustomize adds. From [Lesson 5](05-salud-recursos-apagado.md), `requests` and `limits` on every container; today the tasks carry them too. And from [Lesson 6](06-entrar-al-cluster.md), the platform (MetalLB and Envoy Gateway) that this lesson installs again when it creates its cluster, because the starting point includes the Gateway.

**What this lesson does not do.** It does not put the `revisor`'s report inside the persistent volume: Exercise 2 lets you try it and see why the course does not do it (it ties all the replicas to a single node). It does not install a network storage system, nor teach `StatefulSet`, nor take snapshots or backups of a volume: it names them at the end of “The security habit”, with a sentence about the problem each one solves. It does not scale anything (that is [Lesson 9](09-escalar-y-actualizar.md), which starts from what you leave here) nor evaluate the complete project against a real cluster ([Lesson 10](10-proyecto-final.md)).

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1 and the `kindest/node:v1.37.0` node image pinned by its digest, on the three-node cluster from Lesson 1, called `curso-k8s-l8` here. The machine was an ARM-based Mac with Docker Engine inside a Linux virtual machine (Colima), **not** Linux Mint, which is the course's reference system. **The run used a Docker network of its own**, `curso-k8s-red-l8`, with the subnet `172.28.0.0/16`, because the machine was shared and other lessons using MetalLB were running at that moment: two clusters with the same IP range on the same network step on each other. That is why the Gateway's addresses appear here as `172.28.255.x`. **On your machine, with the normal `kind` network that Docker creates when the first cluster comes up, the IPs come out as `172.18.255.x`** (the range in `infra/metallb-pool.yaml` is `172.18.255.200-172.18.255.220`), and you do not need to create any network. That assumes your `kind` network has the subnet `172.18.0.0/16`; check it first with `docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'` and, if it is different, adjust the range in the file. The rest of what changes on your Mint: the architecture (`amd64` instead of `arm64`), the random suffixes of Pod and Job names, the ages, which node each replica lands on, each Pod's *uid*, the time and the names of the volumes (`pvc-` and an identifier). The commands are the same. The complete walkthrough is in [`programas/08-datos-y-tareas/`](../programas/08-datos-y-tareas): `correr.sh` creates the cluster, installs the platform on it, leaves everything as Lesson 7 left it, goes through the lesson in order, runs Exercises 1 to 3 and deletes the cluster; its output is `correr.salida.txt`. The complete run took 19 minutes and 17 seconds (the three `concurrencyPolicy` trials in Exercise 3 add up to about eight minutes of waiting): creating the cluster and waiting for it to be ready took 42 seconds, installing the platform took 175 (the script does not time each step, so I do not know which of the waits was the long one) and deleting the cluster, 4. These times vary a lot with the machine's load: in another run of the same script, with the machine busy, installing the platform took 678 seconds and Envoy Gateway's `kubectl wait` ran out its 300-second deadline, although the Gateway ended up working. The lesson's long waits (watching a `CronJob`'s schedule go by, watching a `Job` exhaust its retries) are written in plain sight: the script prints how often it looks and what it sees, it does not hide them. It uses no port on your machine.

## By the end you will be able to

- Show with the run what survives and what does not in an `emptyDir`: a container restart does, deleting the Pod does not.
- Explain in your own words what a `PersistentVolume`, a `PersistentVolumeClaim` and a `StorageClass` are, and why the course's claim stays `Pending` until the first Pod that uses it appears.
- Read the state of a volume claim, its volume and the real directory that backs it on the node.
- Write a `Job`, say how many times it retries and with what waits, and read a `BackoffLimitExceeded`.
- Write a `CronJob`, read its five-field schedule, and explain `concurrencyPolicy`, the job history and why a scheduled task must be able to run twice without damaging anything.
- Trigger and fix a `Permission denied` on a volume with `fsGroup`, and say in which of the lesson's volumes `fsGroup` changed the group and in which it did not, and why you cannot take it for granted.
- Say what happens to the data when a volume claim is deleted depending on the reclaim policy, and why the deletion can get stuck in `Terminating`.

## The why before the how

Until today, everything the `revisor` writes lives in a place that the cluster treats as disposable. You saw it in passing in Lesson 2, when the Deployment mounted an `emptyDir` at `/datos` so that the read-only file system would not prevent saving the report, and you have used it since then without asking how long it lasts. The first question of the lesson is that one: **how long does what a Pod writes last?** The answer has two steps, because a Pod is not the same as a container: the container can crash and come back (the `kubelet` restarts it), and the Pod can be deleted and replaced by another with another name on another node. What survives the first does not have to survive the second, and we measure it.

The second question is **how do you save something for real?** Kubernetes separates two roles that came together in Docker. Whoever administers the cluster decides what storage exists (disks, folders, network services); whoever deploys an application decides how much it needs and of what type. The bridge between the two is three objects with similar names and different jobs, which this lesson introduces one by one before using them.

The third is **how do you do something that is not a service?** A Deployment keeps processes that must not end. Asking the `revisor` for its report every five minutes is the opposite: a process that starts, does one thing and ends, and that the cluster must repeat at a fixed time without anyone remembering. That is what the `Job` (do something until it goes well or until it gives up) and the `CronJob` (create Jobs on a schedule) are for.

And there is a fourth question, less eye-catching, that decides whether the above works: **who owns what gets written?** A volume that is born with an owner and a permission, and a process that runs as another user, are a recipe for a `Permission denied`. `fsGroup`, the line from Lesson 4 whose full story was left pending, comes back here.

The lesson has eight parts of concepts and then the usual sections:

1. **The lesson's cluster and its starting point** (8.1).
2. **What is lost: today's `emptyDir`** (8.2).
3. **Volumes, claims and classes** (8.3).
4. **The volume claim and its wait** (8.4).
5. **`Job`: the task that ends** (8.5).
6. **`CronJob`: the task with a schedule** (8.6).
7. **The owner of the files: `fsGroup`** (8.7).
8. **Deleting the claim: that is where it is lost** (8.8).

This is the destination. At the end of 8.5, a task run by hand leaves a file with the date in its name inside a volume that outlives its Pod, and a second task sees the first one's file:

```text
$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json
```

## If you do not have the images from the Docker course

This lesson uses the same two images as the previous ones: `curso-docker-revisor:1.6.0` and `curso-docker-prueba:1.0.0`. Check that you have them:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

For the other one, the same command with `curso-docker-prueba:1.0.0`. If you are missing one, [Lesson 3](03-services-dns.md) says how to build each one from the Docker course repository. The lesson's tasks also use the public `curl` image you already know from `depurar`, pinned by its `sha256` digest; each node downloads it from the internet the first time.

## The concepts

### 8.1 The lesson's cluster and its starting point

#### 8.1.1 Creating the cluster

This lesson uses its own cluster, `curso-k8s-l8`, with the three-node configuration from Lesson 1. The `programas/08-datos-y-tareas/…` paths in the next block assume you are at the root of the course repository. Before creating it, two precautions that are already routine: a temporary `kubeconfig` of your own, so that your `~/.kube/config` is neither read nor touched, and a function that checks which cluster you are talking to. We will call it `ctx` and it goes **in front of every command that changes something**: if the context is not the lesson's, it returns an error and the command that follows does not run, because it is joined to it with `&&`.

```bash
# Un kubeconfig temporal y propio. La carpeta queda guardada en una variable:
# la necesitas para abrir una segunda terminal y para borrarla al final.
L8_TMP="$(mktemp -d /tmp/curso-k8s-l8.XXXX)"
export KUBECONFIG="$L8_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta
# La guarda: el contexto debe ser el de la lección, o el comando que sigue no corre.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l8 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
# curso-k8s-l8 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l8 --config programas/08-datos-y-tareas/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l8
# El resto de la lección se trabaja desde la carpeta de sus programas.
cd programas/08-datos-y-tareas
```

(The lesson's run, as said in “About the runs”, prepended `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l8` to `kind create cluster` to use its own network. You do not need it.)

The `export` and the `ctx` function only live in that terminal. If you open another, you repeat the two lines (`export KUBECONFIG=…` with the path that the `echo` printed, and the definition of `ctx`) or `kubectl` will talk to another cluster. From here on, **every code block that changes something starts with `ctx &&`**. In the outputs pasted below, the line that starts with `$` is the command as the script printed it, without `ctx &&`: the script checks the context before each `kubectl` on its own, and you do it with the function.

The outputs in this section come from the run of `correr.sh`, which does exactly that, with the network of its own explained in “About the runs”:

```text
$ kubectl config current-context
kind-curso-k8s-l8

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l8-control-plane   Ready    control-plane   27s   v1.37.0
curso-k8s-l8-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l8-worker2         Ready    <none>          17s   v1.37.0
```

`kind load` prints six `not yet present on node …, loading...` lines, two images times three nodes, as in the previous lessons.

#### 8.1.2 The Lesson 6 platform, again

This lesson's starting point includes the Gateway from Lesson 6, and a Gateway needs the new Gateway API types (CRDs) and the Envoy Gateway controller. Since the cluster is new, they have to be installed again, in the same order as in Lesson 6: first the platform, then a wait, then its configuration. The order matters because the CRDs and the *webhooks* must exist before the resources that use them.

```bash
ctx && kubectl apply -k infra/metallb
ctx && kubectl apply --server-side -k infra/envoy-gateway
# La espera: los tipos nuevos establecidos y los controladores disponibles.
ctx && kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
ctx && kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
ctx && kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
# La configuración: el rango de IP de MetalLB y la clase de puerta «eg».
ctx && kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ctx && kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
```

The output, with the range of the run's own network:

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ sed 's#172.18.255.200-172.18.255.220#172.28.255.200-172.28.255.250#' infra/metallb-pool.yaml | kubectl apply -f - && kubectl apply -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s | tail -1
daemon set "speaker" successfully rolled out
(la plataforma tardó 175 s)
```

Two notes about this output. The one about `sed` applies only to the run: it changes the file's range (`172.18.255.200-220`) to that of the own network (`172.28.255.200-250`) before applying it. On your machine, with the normal `kind` network, you apply the file as it is: `kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml`. And the 175 seconds are a lot for this (with the machine under more load they reached 678), and the script does not time each step: the machine was busy with other clusters. In an earlier trial of this same lesson, the last one to declare itself ready was MetalLB's *speaker* (one Pod per node that announces the IPs on the network). If on your machine the `rollout status` takes long, `kubectl get pods -n metallb-system` tells you how many of the three *speakers* are ready.

#### 8.1.3 The starting point: Lesson 7

The folder `programas/08-datos-y-tareas/punto-de-partida/` brings, without changing a comma, the manifests Lesson 7 ended with: the `revisor` namespace with the `restricted` level, the service accounts, the six network policies, the `revisor` and the test service with their Services, the Gateway and the `kustomization.yaml`. As in the previous lessons, the token is not versioned: it is generated on every run, with permission `0600`, and copied to the two folders (the starting point's and the lesson's) so that both generate **the same** Secret.

```bash
ctx && (umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
ctx && cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
ctx && kubectl rollout status deployment/revisor -n revisor --timeout=180s
ctx && kubectl rollout status deployment/prueba -n revisor --timeout=180s
ctx && kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
ctx && kubectl apply -n revisor -f depurar.yaml
```

```text
$ ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-hbc69k5m5c created
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

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met

$ kubectl apply -n revisor -f depurar.yaml
pod/depurar created
```

The `ConfigMap`'s name is the one from Lesson 4, `revisor-config-t6cm6872fk`, because the list of services did not change; the `Secret`'s changes on every run, because the token is new. The two `rollout status` commands in the previous block print nothing here because the script runs them silently; in your terminal you will see `deployment "revisor" successfully rolled out` and the equivalent for `prueba`. The `depurar` Pod is the usual one, with one difference you already know from Lesson 7: it carries the label `acceso-revisor: permitido`, and that is why the closed network lets it talk to the `revisor`.

```text
$ kubectl get pods -n revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
depurar                    1/1     Running   0          8s    10.244.2.5   curso-k8s-l8-worker    <none>           <none>
prueba-6899c74865-9dckl    1/1     Running   0          52s   10.244.1.4   curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-g6wc5   1/1     Running   0          52s   10.244.2.4   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-rxlw6   1/1     Running   0          52s   10.244.2.3   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-wk56w   1/1     Running   0          52s   10.244.1.5   curso-k8s-l8-worker2   <none>           <none>

$ kubectl get pvc,cronjob,job -n revisor
No resources found in revisor namespace.

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Three replicas of the `revisor`, the test service and `depurar`. And the last line of `kubectl get`: there are no volumes, no tasks, no schedules. That is the lesson's open question. The last output is a request coming from a Docker container outside the cluster, on the same network as the nodes, and it arrives through the Gateway: Lesson 6's entry point works in Lesson 7's namespace with the closed network. If on your machine it does not answer, `kubectl get gateway -n revisor` tells you which IP it received; in the run it was `172.28.255.200`, and on your `kind` network it would be `172.18.255.200`.

### 8.2 What is lost: today's `emptyDir`

#### 8.2.1 Where the file is

First, let the `revisor` write its report. Every request to `/api/estados` builds the report and, before answering, saves it to the file named by the image's `REVISOR_REPORTE` variable, `/datos/reporte.json`. The image has no *shell*, so you cannot go in and look at the file; but the file exists on some disk, and kind's nodes are Docker containers that you can enter. A report is requested and looked for:

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid
POD                        NODO                   UID
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347
revisor-6b7f4d564d-wk56w   curso-k8s-l8-worker2   510c7d49-6be3-4fac-947d-18783838b9e5
```

(In the first command, the token shows as `…`: the script hides it in what it prints, and you pass it with `$TOKEN`, as in the previous lessons.) The `uid` is the unique identifier the cluster gives each Pod, and it is the name of the folder where the node's `kubelet` keeps its things. A Pod's volumes live in `/var/lib/kubelet/pods/<uid>/volumes/`, and those of type `emptyDir` in the subfolder `kubernetes.io~empty-dir`. We look at the one for each of the three replicas, on the node where it runs:

```text
$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/961791a4-d756-4382-a1de-ae62d7bc11b1/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/29162810-cd29-4693-89bf-ed789dd8f347/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

There are three findings in these three outputs, and all three matter for what follows.

**The first: only one of the three replicas has the file.** The request to `http://revisor/` was distributed by the Service to one of the three, and that one saved the report. The other two have an empty `/datos`. Each replica has its **own** `emptyDir`: nothing is shared between Pods. If you asked “the `revisor`” what its last report was, the answer would depend on which replica answers you. That alone already disqualifies the `emptyDir` as a place for a history.

**The second: the owner of the directory.** The first column of `ls -l` is `drwxrwsrwx`: the directory has read, write and entry permission for everyone, and an `s` instead of an `x` in the group's place, which is the *setgid*. The owner is user `0` (`root`) and the group is `65532`. That group is no coincidence: it is the `fsGroup: 65532` that Lesson 4 put in the Deployment. So as not to credit `fsGroup` with more than it does: the open `777` permission is the default value of an `emptyDir` according to the volumes documentation; what `fsGroup` sets is the group `65532` and the *setgid* bit. 8.7 tells what `fsGroup` did here and what it does not do on other volumes.

**The third: the file belongs to the `revisor`'s user.** `-rw------- 1 65532 65532 92`: the owner and the group are 65532, the user the `revisor` runs as, and the `0600` permission (owner only) comes from how the `revisor` creates it: it first writes a temporary file in the same folder and then renames it, so that whoever reads it sees the old report or the new one, never a half-written one. And 92 bytes: a report for a single service.

With `root` on the node you can read what the `revisor` saved:

```text
$ docker exec curso-k8s-l8-worker2 stat -c '%a %U:%g %n' /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
2777 root:65532 /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos

$ docker exec curso-k8s-l8-worker2 cat /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos/reporte.json
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 6
  }
]
```

`stat` translates the permission to octal: `2777` is the read-and-write-for-everyone `777` plus the `2` of the *setgid*. It is the same information as the `s`, in another form. The content is the report in JSON: the service's name, whether it is up, the HTTP code and the time in milliseconds.

(The outputs in this section assume you know how to enter a node with `docker exec`; it is the same thing you did in Lesson 4 with the `Secret` and in Lesson 5 with `crictl`. It works because in kind the nodes are containers. In a real cluster, the folder exists just the same, but the node is a machine you enter by another mechanism and with other permissions.)

#### 8.2.2 A container that crashes: the `emptyDir` survives

The Kubernetes volumes documentation ([link in the sources](#sources)) says of `emptyDir`: the volume is created “when a Pod is assigned to a node”; it starts empty; and “when a Pod is removed from a node for any reason, the data in the `emptyDir` is deleted permanently”. And it adds a note that seems small and is half of the lesson: “a container crashing does **not** remove a Pod from a node. The data in an `emptyDir` volume is safe across container crashes”.

We check it. With `crictl`, the tool from Lesson 5, the `revisor` container that has the file is stopped. The container's identifier is looked up by the Pod's `uid`, so as not to stop someone else's:

```bash
CID="$(docker exec curso-k8s-l8-worker2 crictl ps --label "io.kubernetes.pod.uid=510c7d49-6be3-4fac-947d-18783838b9e5" --name revisor -q)"
docker exec curso-k8s-l8-worker2 crictl stop "$CID"
```

```text
$ docker exec curso-k8s-l8-worker2 crictl stop a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090
a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090

(esperando 10 s a que el kubelet reinicie el contenedor)

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w
NAME                       READY   STATUS    RESTARTS      AGE
revisor-6b7f4d564d-wk56w   1/1     Running   1 (10s ago)   65s

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} {.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
Error 137

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

Read it in order. `RESTARTS 1 (10s ago)`: the `kubelet` saw the container die and restarted it 10 seconds ago; the Pod is still the same one (same name, same `uid`, `AGE` of 65 seconds). The last termination was an `Error` with code `137`, the same as in Lesson 5: 128 plus signal 9, the one that cannot be ignored. And the last output is the one that matters: **the file is intact**, with the same time (`23:24`) and the same 92 bytes. The new container mounted the same volume and found the report where the old one left it.

This has a practical consequence worth stating clearly: if your application crashes and restarts on its own, what it saved in an `emptyDir` is found by the new container. That is the use the documentation proposes: scratch space, checkpoints of a long computation to resume it after a crash. It is not a place for what must outlive the Pod.

#### 8.2.3 A Pod that is deleted: the `emptyDir` goes with it

The second step. The whole Pod is deleted, not just its container, and the volume's folder is examined:

```bash
ctx && kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
```

```text
$ kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
pod "revisor-6b7f4d564d-wk56w" deleted from revisor namespace

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
ls: cannot access '/var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos': No such file or directory
[código de salida: 2]

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5
containers
etc-hosts
plugins
volumes

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid,LISTO:.status.containerStatuses[0].ready
POD                        NODO                   UID                                    LISTO
revisor-6b7f4d564d-4mnvh   curso-k8s-l8-worker2   d61911b6-d777-4c4c-a159-e2a782fc69d8   true
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1   true
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347   true
```

The volume's folder no longer exists: `No such file or directory`, with exit code 2. The `kubelet` deleted the volume when it removed the Pod. The second output is a nuance worth reading carefully: the Pod's folder still shows four entries (`containers`, `etc-hosts`, `plugins` and `volumes`) a few seconds after the deletion. I did not investigate why (it is probably `kubelet` cleanup that had not finished yet); what matters for the lesson has already happened: the data volume's folder does not exist. And the ReplicaSet replaced the replica: `4mnvh` is new (another name, another `uid`) and this time it landed on the same node, `curso-k8s-l8-worker2`; the scheduler spreads Pods out, but does not promise a different node. The new `revisor` started with an empty `/datos`.

With this, the Friday afternoon of the scene is explained in two measurements. A container restart is survived. Saturday's maintenance did not restart containers: it evicted Pods, and each new Pod was born with a new `emptyDir`, on a node that perhaps was not the same. (A simple node reboot is something else: the Pod lifecycle documentation distinguishes that case, in which the Pod is not evicted and the `kubelet` brings its containers back up, from eviction or the loss of the node. Pods are replaced when someone deletes them, when the node is drained or when it is declared lost.) For data to survive the Pod you need a volume that **does not depend on the Pod**: that is what comes next.

### 8.3 Volumes, claims and classes

#### 8.3.1 Three objects, three roles

Before using them, the three objects with an everyday example. Imagine an office building. The **office spaces** exist: someone built them, they have a size and a location. A **rental request** says “I need an office of so many square meters, for a single company to work in”; it does not say which one. And the **office type** (with a view, without a view, in the basement) describes how they are built and how much they cost. In Kubernetes:

| In the building | In Kubernetes | Who creates it | What it says |
|---|---|---|---|
| the office space | `PersistentVolume` (PV) | the cluster administrator, or the system, on demand | “storage of this size exists, in this place, with these rules” |
| the rental request | `PersistentVolumeClaim` (PVC) | whoever deploys the application | “I need this size, with this access mode” |
| the office type | `StorageClass` | the cluster administrator | “this is how a volume of this class is created” |

The [persistent volumes documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) defines the first two with these words: a PersistentVolume is “a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using storage classes. It is a resource in the cluster just like a node is a cluster resource”. And a PersistentVolumeClaim “is a request for storage by a user. It is similar to a Pod”. The analogy with the Pod goes further than it seems: just as a Pod consumes node resources, a claim consumes volume resources; and just as a Pod can request CPU and memory, a claim requests a size and an access mode.

A naming detail that confuses newcomers: the PV **has no namespace** (it belongs to the cluster, like a node; in the output of `kubectl api-resources --namespaced=false` it appears next to `nodes` and `namespaces`), and the PVC **does** (it lives in `revisor`, next to the Pods that use it).

```text
$ kubectl api-resources --api-group='' --namespaced=false -o name | grep -E '^(persistentvolumes|nodes|namespaces)$'
namespaces
nodes
persistentvolumes
```

#### 8.3.2 The two ways to get a volume

The same page describes two ways for a claim to find its volume:

- **Static.** “A cluster administrator creates a number of PVs.” The PVs already exist, and a claim that matches one (in size, in access mode, in class) binds to it. It is what happens with disks that someone prepared by hand.
- **Dynamic.** “When none of the static PVs the administrator created match a user's PersistentVolumeClaim, the cluster may try to dynamically provision a volume specially for the PVC.” Nobody creates the PV: a cluster program, the *provisioner*, creates it from the class the claim asked for.

And the procedure, which the documentation calls the lifecycle: first provisioning; then binding: “a control loop in the control plane watches for new PVCs, finds a matching PV (if possible), and binds them together”; then use: “once the user has a claim and that claim is bound, the bound PV belongs to the user for as long as they need it”; and at the end reclaiming, when the user no longer needs it. Note down one sentence from that page, because you will see it fulfilled: “claims will remain unbound indefinitely if a matching volume does not exist”. Binding is also one-to-one: one PV with one claim, and one claim with one PV.

The course uses both ways, each where it teaches something. The dynamic one is the normal way and is the one the lesson's report uses. The static one you will use in 8.7 to fabricate a disk with the rules of a real one.

#### 8.3.3 kind's class

This cluster already comes with a class. We ask it:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  4m31s

$ kubectl get storageclass standard -o jsonpath='{.provisioner} {.reclaimPolicy} {.volumeBindingMode} {.allowVolumeExpansion}{"\n"}'
rancher.io/local-path Delete WaitForFirstConsumer

$ kubectl get pods -n local-path-storage
NAME                                      READY   STATUS    RESTARTS   AGE
local-path-provisioner-75f7fc7dc5-xl4bd   1/1     Running   0          4m26s

$ kubectl get pv
No resources found
```

A class with four facts that matter:

- **`standard (default)`** is its name, and the parenthesis says it is the **default class**: the classes documentation says that, when a claim does not set `storageClassName`, “the default class is used”. The course names it in its manifest anyway, because a manifest that says what it uses can be read without depending on a cluster setting.
- **`rancher.io/local-path`** is the provisioner. In the `local-path-storage` namespace there is a Pod, `local-path-provisioner`, that watches the claims of this class and creates their volume. The project's documentation describes it like this: “provides a way for the Kubernetes users to utilize the local storage in each node”, and the volume it creates is, by default, a folder on the node, of type `hostPath`. Two sentences from that same README, which we will use later, note them down: it does not support a capacity limit (“the capacity is ignored for now”), and the folder is created with permission `0777`.
- **`Delete`** is the **reclaim policy** for the volumes of this class: what is done with the volume when the claim that used it is deleted. The persistent volumes documentation puts it this way: with `Delete`, deletion removes both the PV object from Kubernetes and the associated storage. The alternative is `Retain`, which keeps the volume so that an administrator can recover it by hand. 8.8 measures it with both.
- **`WaitForFirstConsumer`** is the **binding mode**, and it is the most important fact for understanding what follows. The classes documentation explains it by contrast. With the `Immediate` mode, which is the one used if you set nothing, “volume binding and dynamic provisioning occur as soon as the PersistentVolumeClaim is created”. That can go wrong when the storage is tied to a place (a node, a zone), because the volume would be created without knowing where the Pod will run. The remedy: the `WaitForFirstConsumer` mode “will delay the binding and provisioning of a PersistentVolume until a Pod using the PersistentVolumeClaim is created”. First it is decided where the Pod will run; then the volume is created **in that place**.
- **`ALLOWVOLUMEEXPANSION false`** (and empty in the `jsonpath`, because the field is not written in the class): the class does not allow enlarging a volume after it is created. You will not need it here; if a volume ever fills up, this column decides whether the way out is to enlarge it or to create a bigger one and move the data.

And the end of the output: **`No resources found`** in `kubectl get pv`. There is no volume yet. The class exists, the provisioner waits, and volumes are created when someone requests them and there is a Pod that uses them.

### 8.4 The volume claim and its wait

#### 8.4.1 The manifest

The lesson adds a file to the project, `reporte.yaml`, with three objects: the service account `reporte`, the claim `reportes` and the `CronJob` `reporte`. The first two are read now; the third has its own section, 8.6, because it needs you to know what a Job is first. The complete file is a **program**: `programas/08-datos-y-tareas/reporte.yaml`, and the lesson's `kustomization.yaml` adds it to its list of resources.

```yaml
# reporte.yaml — Lección 8: el reporte guardado y el revisor como tarea programada.
# Cada 5 minutos, un Job le pide al revisor su reporte y lo guarda en un volumen
# persistente. El binario del revisor solo sirve HTTP (no tiene modo «una vez»),
# por eso la tarea es un curl contra su API; la lección (8.6) explica por qué.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reporte
automountServiceAccountToken: false
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reportes
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 100Mi
```

(The third piece, the `CronJob`, is complete in 8.6; here it is cut off so we read the claim first.) The service account is the habit from Lesson 7: an account of its own for the task, without permissions and with `automountServiceAccountToken: false`, because the task talks to the `revisor`, not to the cluster API. The claim has four lines that matter:

- **`accessModes: [ReadWriteOnce]`** is the **access mode**. It is abbreviated RWO and the documentation defines it like this: “the volume can be mounted as read-write by **a single node**”. That last word is the one that gets misread: it is one node, not one Pod. The same page clarifies that RWO “can still allow multiple pods to access (read from or write to) that volume when the pods are running on the same node”. Hold on to it, because Exercise 2 uses it. Other modes exist (`ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`); with kind's class, the one that applies is this one: the table on the same page marks that a `HostPath` volume supports only `ReadWriteOnce`, and the folder lives on one node.
- **`storageClassName: standard`** names the class. Writing the name, even though it is the default class, leaves the manifest free of surprises in a cluster where the default class is another one.
- **`storage: 100Mi`** is the requested size: 100 mebibytes, the same unit of memory as in Lesson 5. In pure arithmetic, 100 Mi is enough for more than a million 92-byte reports. In a real file system each file occupies at least one block (I checked on the run's Docker machine that a 92-byte file occupies 8 blocks of 512, that is 4096 bytes, with file system blocks of 4096), so 100 Mi holds about 25,600 files, and with 288 reports a day (one every five minutes) that is about 89 days of history before having to purge. There will be something to say later about how seriously a cluster takes that number.
- **There is no `volumeName`**: the claim does not name a volume. It asks for a class and a size, and the system will resolve the rest.

Before applying, the question Lesson 5 taught you to ask: what would change.

```bash
kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
```

```text
$ kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
+  concurrencyPolicy: Forbid
+          schedulerName: default-scheduler
+  schedule: '*/5 * * * *'
+      storage: 100Mi
+  storageClassName: standard
[código de salida: 1]
```

The `diff` filters only what is added (lines that start with `+ `) and, of those, the ones that name what is new in the lesson: the concurrency policy, the schedule, the size and the class. The script prints `[código de salida: 1]` because it runs with `pipefail` and keeps the 1 from `kubectl diff` (there are differences, as in Lesson 5); in your terminal, the pipeline returns `grep`'s code and you will see 0. (The `schedulerName` line is added by the cluster as a default value; the `grep` caught it because it contains the word `schedule`.)

#### 8.4.2 Applying, and reading the `Pending`

```bash
ctx && kubectl apply -k .
```

```text
$ kubectl apply -k .
namespace/revisor unchanged
serviceaccount/observador unchanged
serviceaccount/prueba unchanged
serviceaccount/reporte created
serviceaccount/revisor unchanged
role.rbac.authorization.k8s.io/observador unchanged
rolebinding.rbac.authorization.k8s.io/observador unchanged
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hbc69k5m5c unchanged
service/prueba unchanged
service/revisor unchanged
persistentvolumeclaim/reportes created
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
cronjob.batch/reporte created
gateway.gateway.networking.k8s.io/revisor configured
httproute.gateway.networking.k8s.io/revisor configured
networkpolicy.networking.k8s.io/acceso-revisor-salida unchanged
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged
```

The Deployments did not change (`unchanged`): no replica restarted. What is new is three objects, `serviceaccount/reporte`, `persistentvolumeclaim/reportes` and `cronjob.batch/reporte`. (That `gateway` and `httproute` say `configured` appears in this `apply` and changes nothing visible in the service; the lesson does not investigate it.) And now, what matters:

```text
$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 1s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          0s

$ kubectl describe pvc reportes -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason                Age   From                         Message
  ----    ------                ----  ----                         -------
  Normal  WaitForFirstConsumer  1s    persistentvolume-controller  waiting for first consumer to be created before binding

$ kubectl get pv
No resources found
```

`STATUS Pending`, `VOLUME` empty, `CAPACITY` empty. To someone coming from the previous lessons, `Pending` sounds like a problem (the Pod in Lesson 5 that did not fit on any node). Here it **is not one**, and the event says so in so many words: `waiting for first consumer to be created before binding`. It is the `WaitForFirstConsumer` mode from 8.3.3 in action. There is no Pod yet that uses the claim, so the cluster has not decided on which node anything will run, and therefore cannot decide on which node to create the folder. And `kubectl get pv` confirms it: no volume.

The difference from Lesson 5's `Pending` is what separates one diagnosis from another. Here the event is at the `Normal` level, it is emitted by `persistentvolume-controller` and it says it is waiting; there it was a `Warning` from the scheduler that said there was nowhere to go. The rule for reading any `Pending` is the same as always: the events say who is waiting and for what. A `Pending` with `WaitForFirstConsumer` and no Pod using the claim is a system working.

The `CronJob`, meanwhile, exists and has not run: `LAST SCHEDULE <none>`, `ACTIVE 0`. Its first run will arrive at the next multiple of five minutes on the clock. So as not to wait, 8.5 teaches how to request one by hand.

### 8.5 `Job`: the task that ends

#### 8.5.1 The smallest that works

A **`Job`** is, in the words of its documentation, a task that runs “until completion and then stops”. It creates one or more Pods and retries “until a specified number of them successfully terminate”. When that number is reached, the Job is complete. What matters compared to a Deployment is what counts as success: a Job's Pod that exits with code 0 **is** the expected result; in a Deployment, that same Pod would be a failure, and the cluster would replace it.

Before the real Job, a practice one: `fig08_01.job-salud.yaml`, which asks the `revisor`'s `/salud` once and ends. It is a **program**.

```yaml
# fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
# a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
# cerrada de la Lección 7 exige para que un Pod hable con el revisor.
apiVersion: batch/v1
kind: Job
metadata:
  name: salud
  namespace: revisor
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 120
  template:
    metadata:
      labels:
        app: salud
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
      - name: salud
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["curl", "-fsS", "-m", "5", "http://revisor/salud"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Read it from top to bottom; you recognize almost everything. `apiVersion: batch/v1` and `kind: Job`: the `batch` group holds Jobs and CronJobs. The `namespace: revisor` is written in the file so that the Job lands there without you having to remember `-n`. `spec.template` is the Pod template, just as in a Deployment, but with two differences. The first: **it has no selector**, because the Job assigns it on its own (the documentation warns that “in almost all cases you should not specify it”). The second: `restartPolicy` is mandatory and accepts only two values, `Never` and `OnFailure`. With `Never`, if the container fails, the Pod is left as `Failed` and the Job creates another; with `OnFailure`, the `kubelet` restarts the container inside the same Pod. The course uses `Never`: each attempt is a separate Pod, with its own log and its own exit code, and you can read what happened in each one. With `OnFailure`, the attempts would pile up in a single Pod.

The two Job fields that are not about the Pod:

- **`backoffLimit: 2`**: how many times to retry before giving up. The documentation says the default value is 6, and that failed Pods are recreated “with an exponential back-off delay (10s, 20s, 40s ...) capped at ten minutes”. Here 2 means: the original attempt plus two retries, three Pods at most.
- **`activeDeadlineSeconds: 120`**: a time cap for the whole Job, **no matter how many Pods it creates**. When it is reached, the cluster terminates the running Pods and the Job goes to `Failed` with the reason `DeadlineExceeded`. And the documentation specifies that this deadline takes precedence over `backoffLimit`: a Job that is retrying does not create more Pods when the deadline arrives, even if it has not used up its attempts. The two caps cover different failures: one is for “fails fast many times”, the other for “hangs”.

The task itself, `curl -fsS -m 5 http://revisor/salud`, is read letter by letter. `-f` makes curl exit with an error when the server answers 400 or above (without that letter, a 503 would exit with code 0, and the Job would count it as a success). `-sS` is silent but shows errors. `-m 5` is the maximum time for the whole operation: 5 seconds. And the command is written as a list (`["curl", ...]`) and not as text for a *shell*, because the `curl` image does not need one for this.

```bash
ctx && kubectl apply -f fig08_01.job-salud.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/salud --timeout=180s
```

```text
$ kubectl apply -f fig08_01.job-salud.yaml
job.batch/salud created

$ kubectl get job,pods -n revisor -l app=salud
NAME              STATUS     COMPLETIONS   DURATION   AGE
job.batch/salud   Complete   1/1           4s         4s

NAME              READY   STATUS      RESTARTS   AGE
pod/salud-svx9s   0/1     Completed   0          4s

$ kubectl logs -n revisor job/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor salud -o jsonpath='{range .status.conditions[*]}{.type} {.status}{"\n"}{end}'
SuccessCriteriaMet True
Complete True
```

The Job took 4 seconds and ended with `COMPLETIONS 1/1`. The Pod was left as `Completed` with `READY 0/1`: that is not an error. The container finished well and no longer runs, and the Pod is kept so you can read its log. `kubectl logs job/salud` finds the Job's Pod and shows what `curl` printed: the JSON from `/salud`. The Job's conditions are two: `SuccessCriteriaMet` (the success criterion was met) and `Complete` (it finished). That there are two and not one has to do with something the documentation says: since version 1.31, the Job controller delays the terminal condition (`Complete` or `Failed`) until all of the Job's Pods have finished. `SuccessCriteriaMet` (and its twin `FailureTarget`, which you will see in “The error you will see”) are the conditions that appear earlier: they say the outcome has already been decided.

It is deleted to leave the space as it was:

```text
$ kubectl delete -f fig08_01.job-salud.yaml
job.batch "salud" deleted from revisor namespace
```

The documentation says it: deleting a Job cleans up the Pods it created. That matters in 8.8, where deleting the Jobs becomes part of the maneuver.

#### 8.5.2 The saved report: the first task

Now the lesson's Job. It is not written separately: the `reporte` `CronJob` already carries it inside, as a template, and `kubectl` knows how to create a Job from it at any time, without waiting for the schedule. It is the way to test a scheduled task without staring at the clock:

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
```

```text
$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
job.batch/reporte-manual-1 created

$ kubectl get pods -n revisor -l app=reporte -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE        READINESS GATES
reporte-manual-1-t7d8l   0/1     Pending   0          3s    <none>   <none>   curso-k8s-l8-worker   <none>

$ kubectl describe pvc reportes -n revisor | sed -n '/^Used By:/,$p'
Used By:       reporte-manual-1-t7d8l
Events:
  Type    Reason                Age              From                                                                                                Message
  ----    ------                ----             ----                                                                                                -------
  Normal  WaitForFirstConsumer  7s (x2 over 9s)  persistentvolume-controller                                                                         waiting for first consumer to be created before binding
  Normal  ExternalProvisioning  3s (x2 over 3s)  persistentvolume-controller                                                                         Waiting for a volume to be created either by the external provisioner 'rancher.io/local-path' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
  Normal  Provisioning          3s               rancher.io/local-path_local-path-provisioner-75f7fc7dc5-xl4bd_3605f90f-a3ba-46c3-a75e-a794883e9732  External provisioner is provisioning volume for claim "revisor/reportes"
```

Here, in three seconds, is the story that 8.3.3 announced. The task's Pod exists and is `Pending`, but look at the `NOMINATED NODE` column: the scheduler has already **nominated** a node, `curso-k8s-l8-worker`, although the Pod is not yet assigned (the `NODE` column is still `<none>`). With the `WaitForFirstConsumer` mode, the scheduler decides first where the Pod will run; the classes documentation puts it this way: the volume is selected or provisioned “according to the topology specified by the Pod's scheduling constraints”. With that decision made, the class's provisioner can act. The claim's events tell what happened, from top to bottom (the `Age` column goes down: 7 s, 3 s, 3 s): the claim was waiting for a consumer (`WaitForFirstConsumer`); the Pod appeared and the controller made it clear to the provisioner (`ExternalProvisioning`, which means “an external provisioner must create the volume”); the `rancher.io/local-path` provisioner started (`Provisioning`). The capture was taken at 3 seconds and that is why it ends there; the next event, `ProvisioningSucceeded`, with the name of the volume created (here `pvc-5fcf36b8-…`), arrives an instant later (in another run of the same script it made it into the capture). That is why “external”: the provisioner is a separate program, a Pod in the cluster, not part of the control plane.

The line above, `Used By: reporte-manual-1-t7d8l`, is new in this version: it says which Pod uses the claim. Next to it, `kubectl describe` can show a `Conditions` table with the `Unused` condition, and here we must be exact about what was measured: in this capture the table **did not appear**: the protection controller had not yet written the condition (the capture was taken at 3 seconds). Notice that `Used By:` already lists the Pod even though it is `Pending`: for this condition, a Pod counts as a user as long as it has not finished, even before it is assigned to a node; in another run of the same script, at 3 seconds, an `Unused False` condition did appear, with the reason `PodUsingPVC` (“a Pod is using the claim”). That is, the condition appears depending on the instant you look, and you cannot count on seeing it. Mind its scope: the documentation defines `Unused` only with Pods that have not finished (a Pod in phase `Succeeded` or `Failed` does not count), whereas the deletion protection in 8.8 counts any Pod object that uses the claim. A `Completed` Pod does not keep `Unused` at `False`, but it can keep the claim in `Terminating`. The Kubernetes v1.37 changelog explains it: the `PersistentVolumeClaimUnusedSinceTime` feature graduated to beta and is enabled by default, and claims “report the `Unused` condition, which indicates how long a claim has been unused, to help identify candidates for cleanup”. It is a useful clue in an old cluster: claims with `Unused True` for months are candidates for review (they may still have finished Pods keeping them protected).

```text
$ kubectl logs -n revisor job/reporte-manual-1
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json

$ kubectl get pvc -n revisor
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 13s

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,CLASE:.spec.storageClassName,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],RUTA:.spec.hostPath.path
NOMBRE                                     CLASE      NODO                  RUTA
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   standard   curso-k8s-l8-worker   /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
```

The task's log is the `ls -ln` it prints itself after saving: one file, `reporte-20261021T232446Z.json`, with the date in the name (year, month, day, `T`, hour, minute, second, `Z` for UTC). That is the answer to half of the scene: nothing gets overwritten. Owner `100`, group `101`: those of the task's user, the one from the `curl` image.

The claim is now `Bound`, with the volume `pvc-5fcf36b8-…`, 100Mi, RWO, class `standard`. And the volume, viewed with the columns that matter, has two facts that deserve an explanation:

- **`NODO curso-k8s-l8-worker`**: the volume has a **node affinity**. It is tied to a single node, the one the scheduler chose. This is what makes it a **local** volume: its data is on that machine's disk, and any Pod that uses it has to run there. If that node is lost, the data goes with it.
- **`RUTA /var/local-path-provisioner/pvc-…_revisor_reportes`**: the real folder, on the node. The name follows the pattern `<volume>_<namespace>_<claim>`, and it is the place you can go to look.

```text
$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
777 0:0 /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
total 12
drwxrwxrwx 2   0   0 4096 Oct 21 23:24 .
drwxr-xr-x 3   0   0 4096 Oct 21 23:24 ..
-rw-r--r-- 1 100 101   92 Oct 21 23:24 reporte-20261021T232446Z.json
```

The directory has permission `777` and owner `0:0` (`root`). Compare it with the `emptyDir`'s in 8.2.1: there it was `2777` and the group `65532`. Here there is no *setgid* and no task group. **Although the task's Pod declares `fsGroup: 101`, this volume's directory did not change owner.** It is the contrast with the second finding of 8.2.1, and 8.7 develops it: what is measured here is that `fsGroup` did nothing visible on this type of volume. The `777` permission comes from the provisioner, which according to its README creates the folder with `mkdir -m 0777`. That is why the task could write: not because of its group, but because the folder lets anyone in.

#### 8.5.3 The Pod ended; the file is still there

The proof of the volume is that it survives the Pod that filled it. The first task's Pod has already finished. A second task is launched, a new Pod, with another name, that has nothing to do with the first except that it mounts the same claim:

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
```

```text
$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-manual-1-t7d8l   0/1     Completed   0          7s

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
job.batch/reporte-manual-2 created

$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-manual-1   Complete   1/1           7s         15s
reporte-manual-2   Complete   1/1           5s         6s
```

The second Pod sees **two** files: its own, from `23:24:51`, and the first task's, from `23:24:46`, from a Pod that is no longer running. That is what the `emptyDir` could not do. The claim, and the volume that backs it, have a lifecycle independent of the Pods'. As long as the claim exists and the disk of the node that holds the folder stays intact, the data is kept even though the Pods that wrote it have ended.

The content is confirmed from the node. The first command is the report in the table format you already know (it only confirms that the `revisor` answers the same as before); the second reads the files the tasks left, which store what `/api/estados` answered at each moment:

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ docker exec curso-k8s-l8-worker sh -c 'cat /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes/reporte-*.json | head -9'
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 5
  }
]
[
```

(The `head -9` cuts the output to nine lines: the first complete file and the beginning of the second.) Monday's scene is resolved in form: Friday's 6 p.m. report, Mexico City time, would be a file `reporte-20261017T0000…Z.json` (18:00 in Mexico is 00:00 UTC on Saturday, and the seconds are almost never `00` because the Pod starts a few seconds after the scheduled time), one among dozens, none overwritten by the next.

Before going on, two questions this design leaves and that the lesson answers in its own place. First: if the `CronJob` does it every five minutes, who makes it work? That is 8.6. Second: if the task saves a file and the `revisor` also saves `reporte.json` in its `emptyDir`, why does the `revisor` not save directly to the volume? The course's decision is that it does not, and Exercise 2 lets you check why.

### 8.6 `CronJob`: the task with a schedule

#### 8.6.1 The object, field by field

A **`CronJob`** creates Jobs on a repeating schedule. The [documentation](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) compares it to something you may already know: “one CronJob object is like one line of a *crontab* (cron table) file on a Unix system. It runs a Job periodically on a given schedule, written in Cron format”. What follows is the third piece of `reporte.yaml`, the one that was cut off in 8.4.1:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: reporte
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 60
      template:
        metadata:
          labels:
            app: reporte
            # la red (red.yaml) deja a estos Pods hablar con el revisor:8080
            acceso-revisor: permitido
        spec:
          serviceAccountName: reporte
          automountServiceAccountToken: false
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 100
            runAsGroup: 101
            fsGroup: 101
            seccompProfile:
              type: RuntimeDefault
          containers:
          - name: reporte
            image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
            command:
            - sh
            - -c
            - >-
              curl -fsS -m 20
              -H "Authorization: Bearer $(cat /secretos/token)"
              -o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json
              http://revisor/api/estados
              && ls -ln /datos
            resources:
              requests: {cpu: 10m, memory: 16Mi}
              limits: {cpu: 100m, memory: 32Mi}
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
            persistentVolumeClaim:
              claimName: reportes
          - name: token
            secret:
              secretName: revisor-token
              defaultMode: 0440
```

This is what is new, from top to bottom:

**`schedule: "*/5 * * * *"`** is the schedule, in cron's five-field format. According to the documentation, from left to right they are: minute (0 to 59), hour (0 to 23), day of the month (1 to 31), month (1 to 12) and day of the week (0 to 6, Sunday to Saturday). An asterisk means “any”, and `*/5` means “every five”: `*/5 * * * *` is “every five minutes, at any hour, any day”. The documentation's examples help in reading others: `0 3 * * 1` is “Mondays at 3 in the morning”. And the abbreviations `@hourly`, `@daily`, `@weekly`, `@monthly` and `@yearly` exist as shortcuts. Exercise 4 asks you to write two schedules.

**In what time zone?** The documentation says it clearly: for a CronJob without a time zone, the `kube-controller-manager` interprets the schedule in its local time zone, which in kind is UTC. The `TIMEZONE` column of the output said `<none>`, which is exactly that. It can be set with `.spec.timeZone` (for example `"America/Mexico_City"`); putting `TZ=` or `CRON_TZ=` inside the schedule is not supported and the cluster rejects it with a validation error, according to the documentation. In a real cluster, the course recommends writing the zone; it is the cause of more than one “why did it run at 4 in the morning?”.

**`concurrencyPolicy: Forbid`**: what to do if the time for a new run arrives and the previous one is still running. The three values, according to the documentation: `Allow` (the default) lets both run at once; `Forbid` does not allow concurrent runs and skips the new one; `Replace` replaces the running one with the new one. For the report task, `Forbid` is the prudent choice: two tasks writing to the same volume at once would be more complicated than necessary. Exercise 3 lets you watch all three work.

**`successfulJobsHistoryLimit: 3` and `failedJobsHistoryLimit: 3`**: how many finished Jobs to keep. The default values are 3 and 1, and a value of zero keeps none. They are kept because they are the evidence: without them, a failed Job would disappear with its log and nobody would know why. They are capped because without a limit they would pile up (a Job every 5 minutes is 288 a day).

**`jobTemplate`** is a complete Job, the one the CronJob creates each time. Inside, `backoffLimit: 2` and `activeDeadlineSeconds: 60` are the ones from 8.5.1, with a one-minute deadline: if the task hangs, the cluster cuts it off before it overlaps with the next one.

**The Pod template** is already familiar: the `reporte` account, with no mounted credentials; Lesson 7's `securityContext` (non-`root`, user 100 and group 101 from the `curl` image); Lesson 5's resources. The label `acceso-revisor: permitido` is the one that opens the network: without it the Pod does not reach the `revisor`, and the section “The error you will see” demonstrates it. The `datos` volume is the `reportes` claim. And the `token` volume mounts Lesson 4's `Secret`, as a file, with `defaultMode: 0440`.

A note about the path `/secretos/token`: the file is named after the Secret's **key**, and Lesson 4 generated it with `token=token.txt` in Kustomize. If someday you build the Secret by hand with `kubectl create secret generic revisor-token --from-file=token.txt`, the key will be `token.txt` and the file `/secretos/token.txt`; to make it match, use `--from-file=token=token.txt`.

One thing worth pausing on: the file's `secretName` says `revisor-token`, without the *hash*, the same as in the `revisor`'s Deployment. Kustomize rewrites it when building the result, **also inside a CronJob**. It is checked:

```text
$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.schedule}{" "}{.spec.concurrencyPolicy}{" "}{.spec.successfulJobsHistoryLimit}{" "}{.spec.failedJobsHistoryLimit}{" "}{.spec.timeZone}{"\n"}'
*/5 * * * * Forbid 3 3

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[1].secret.secretName}{"\n"}'
revisor-token-hbc69k5m5c

$ kubectl get secret -n revisor -o name
secret/revisor-token-hbc69k5m5c
```

The `timeZone` field came out empty (the schedule is in UTC). The Secret's name inside the CronJob's template is the generated one, with its *hash*: Kustomize found the reference and changed it, as it did with the Deployment. This matters for the lesson's programs: the `fig08_NN` examples that do not go through Kustomize (the ones applied with `kubectl apply -f`) cannot refer to the Secret by its base name, and that is why none of them mounts it.

The task itself is an `sh -c` with two commands joined by `&&`: the `curl` (with four options and an address) and `ls -ln /datos`. It is read option by option, from left to right: `curl -fsS -m 20` (as in the practice Job, but with 20 seconds, because building a report queries services and can take longer); `-H "Authorization: Bearer $(cat /secretos/token)"` (the header with the token, which is read from the mounted file at run time and never appears written in the manifest); `-o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json` (saves the response in a file whose name carries the UTC time of that instant, with `date -u`); and `http://revisor/api/estados`, the Service's address. If the `curl` fails, the `&&` prevents it from continuing and the task exits with `curl`'s code: the Job counts it as a failure. If it works, `ls -ln /datos` prints the listing, which is what you saw in the manual tasks' log.

Why a `curl` against the API and not a task that runs the `revisor` itself once and ends? Because the `revisor` is an HTTP server and does not have a “check once” mode. It is a course decision, not a trick: we prefer to use the program as the Docker course delivers it, without changing it. The task is a client of the `revisor` like any other.

#### 8.6.2 Watching the schedule go by

The real schedule is five minutes. To see it work without waiting for it, `fig08_03.cron-cada-minuto.yaml` is a CronJob that runs every minute (`* * * * *`) and asks `/salud`, which needs no token. It is a **program**; its template is the practice Job's and what is new is the header.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: salud-cada-minuto
  namespace: revisor
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 30
      template:
        # … la plantilla del Job de práctica (etiqueta acceso-revisor incluida), con una
        # diferencia: el comando imprime primero la hora, para poder leerla en la bitácora:
        #   command: ["sh", "-c", "date -u +%T; curl -fsS -m 5 http://revisor/salud"]
```

(The complete file, with the template, is in the programs folder.) What changes compared with `reporte`: the schedule, a shorter history and `backoffLimit: 0`, which means “no retries”: a task that runs every minute does not need to be retried, because the next minute is the retry. The wait is in plain sight: the script looks every 10 seconds at how many Jobs the CronJob has finished and stops when there are two.

```bash
ctx && kubectl apply -f fig08_03.cron-cada-minuto.yaml
```

```text
$ date -u +%H:%M:%S
23:24:56

$ kubectl get cronjob reporte -n revisor
NAME      SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
reporte   */5 * * * *   <none>     False     0        <none>          20s

$ kubectl apply -f fig08_03.cron-cada-minuto.yaml
cronjob.batch/salud-cada-minuto created

(esperando hasta 200 s a que el CronJob cree y termine 2 Job(s) «salud-cada-minuto…»; se mira cada 10 s)
  +  0 s: 0 Job(s) terminados
  + 10 s: 1 Job(s) terminados
  + 20 s: 1 Job(s) terminados
  + 30 s: 1 Job(s) terminados
  + 40 s: 1 Job(s) terminados
  + 50 s: 1 Job(s) terminados
  + 60 s: 1 Job(s) terminados
  + 70 s: 2 Job(s) terminados
```

Ten seconds after creating it there was already a finished Job: the CronJob did not wait a full minute, but the next **minute on the clock** (`:25:00`), which arrived 4 seconds after `23:24:56`. A cron schedule does not count “every 60 seconds since you created me”: it fires at the instants its formula marks on the clock. And at 70 seconds, the second (the script looks every 10 seconds, and the next minute arrived at 64).

```text
$ kubectl get cronjob,jobs -n revisor
NAME                              SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte             */5 * * * *   <none>     False     0        67s             91s
cronjob.batch/salud-cada-minuto   * * * * *     <none>     False     0        7s              71s

NAME                                   STATUS     COMPLETIONS   DURATION   AGE
job.batch/reporte-29877085             Complete   1/1           4s         67s
job.batch/reporte-manual-1             Complete   1/1           7s         86s
job.batch/reporte-manual-2             Complete   1/1           5s         77s
job.batch/salud-cada-minuto-29877085   Complete   1/1           4s         67s
job.batch/salud-cada-minuto-29877086   Complete   1/1           3s         7s
```

There is a lot to read here, and all of it is evidence that the schedule works:

- **`cronjob.batch/reporte` also ran, on its own.** `LAST SCHEDULE 67s` and a new Job, `reporte-29877085`, that nobody created: the CronJob created it at `23:25:00`, the nearest multiple of five minutes, while the lesson was waiting for something else. The project's real task is already working.
- **The Jobs' names.** `reporte-manual-1` you named yourself. `reporte-29877085` was named by the CronJob: its name, a hyphen and a number. The number is the **minutes elapsed since January 1, 1970 (UTC)**, the Unix epoch: `29877085 × 60` seconds is `2026-10-21T23:25:00Z`, and `29877086`, the next minute. It is an observed detail, not a documented one, that helps read a list of Jobs at a glance: two consecutive numbers are two minutes in a row. And from here comes a restriction that the documentation does state: a CronJob's name must not exceed 52 characters, because, according to the documentation, the controller appends 11 characters and a Job's name cannot exceed 63 (in the run 9 were added: a hyphen and 8 digits; the documentation reserves more to be safe).
- **The every-minute CronJob has two Jobs, `…085` and `…086`**, from consecutive minutes, and `LAST SCHEDULE 7s`: the last one was 7 seconds ago.

```text
$ kubectl logs -n revisor -l app=salud --prefix --tail=3
[pod/salud-cada-minuto-29877085-lbt8h/salud] 23:25:01
[pod/salud-cada-minuto-29877085-lbt8h/salud] {"estado":"vivo","version":"1.6.0"}
[pod/salud-cada-minuto-29877086-j7h2l/salud] 23:26:01
[pod/salud-cada-minuto-29877086-j7h2l/salud] {"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor -l app=salud -o custom-columns=NOMBRE:.metadata.name,PROGRAMADA:.metadata.annotations.batch\\.kubernetes\\.io/cronjob-scheduled-timestamp
NOMBRE                       PROGRAMADA
salud-cada-minuto-29877085   2026-10-21T23:25:00Z
salud-cada-minuto-29877086   2026-10-21T23:26:00Z
```

Look at the times in the logs: `23:25:01` and `23:26:01`; they come from the `date -u +%T` that the `fig08_03` command prints before the `curl`. The Job was scheduled for `:00`, but the Pod started running 1 second later in both cases (in another run of the same script it was 5 and 9: the gap changes with load). Between the instant of the schedule and the instant of the run there is a gap: the CronJob creates the Job, the Job creates the Pod, the scheduler assigns it and the `kubelet` starts the container. The annotation `batch.kubernetes.io/cronjob-scheduled-timestamp`, which the CronJob has written on every Job since version 1.32, keeps the **original** time of the schedule, in RFC 3339 format (the `2026-10-21T23:25:00Z` form you see in the `PROGRAMADA` column): it is used to know which run was which even if they were delayed. The documentation says it with a warning that deserves to be read in full: a CronJob creates a Job “approximately once per execution time of its schedule”, and it is approximate because “there are circumstances in which two Jobs might be created, or no Job might be created. Kubernetes tries to avoid these situations, but does not completely prevent them. Therefore, the Jobs that you define should be **idempotent**”.

**Idempotent**, in the strict sense, means: running it twice leaves the world the same as running it once. The report task is **not** strictly idempotent: if through some hiccup it ran twice in the same minute, it would leave two files and not one. What it is: **safe under repetition**. Since the name's time carries seconds, two runs write two different files and neither overwrites the other (if two Pods ran in the exact same second, the second would replace the first with an equivalent report, without corrupting anything). A task that incremented a counter or sent an email would not be safe like this, and it would have to be protected another way, for example with a unique key per scheduled time. That is the underlying reason the names carry the time and not a sequential number.

The practice CronJob is deleted, and with it its Jobs and Pods:

```text
$ kubectl delete -f fig08_03.cron-cada-minuto.yaml
cronjob.batch "salud-cada-minuto" deleted from revisor namespace

$ kubectl get jobs,pods -n revisor -l app=salud
No resources found in revisor namespace.
```

Two more things that the CronJob documentation teaches, although this lesson does not run them. The first: `.spec.suspend: true` suspends the following runs without deleting anything; the ones that fall while it is suspended count as missed. The second: `startingDeadlineSeconds` says how many seconds after its time the Job can still be created, and if that is exceeded, that run is skipped. Without this field, a controller that is down for a couple of hours can leave many runs pending; the documentation explains that, if more than 100 have been missed since the last one, the CronJob refuses to start and logs an error. In production, with important tasks, it is wise to set it.

### 8.7 The owner of the files: `fsGroup`

#### 8.7.1 What `fsGroup` changed, and what it did not

Since Lesson 4, the `revisor`'s Deployment carries `fsGroup: 65532` and the CronJob, `fsGroup: 101`. It is time to give the complete story. The [security context guide](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) explains it with an example. A Pod with `fsGroup: 2000` makes “all processes of the container also part of the supplementary group ID 2000”, and “the owner for volume `/data/demo` and any files created in that volume will be Group ID 2000”. Its example output is the directory with group 2000 and permissions `drwxrwsrwx`, the same pattern you have already seen. And in the discussion section: `fsGroup` applies to volumes that “support ownership management”, which are modified to be owned by the group that `fsGroup` indicates and writable by it.

Those two words, **support ownership management**, are what is measured here. The lesson's three volumes, side by side. The last command needs the node name and the `uid` of a replica **in your cluster**, which are different ones; they are obtained like this:

```bash
REV_POD="$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
REV_NODE="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.spec.nodeName}')"
REV_UID="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.metadata.uid}')"
docker exec "$REV_NODE" stat -c '%a %u:%g %n' "/var/lib/kubelet/pods/$REV_UID/volumes/kubernetes.io~empty-dir/datos"
```

The run's output, with the node and the `uid` of that replica:

```text
$ kubectl get pod -n revisor -l app=revisor -o jsonpath='{.items[0].spec.securityContext.fsGroup}{"\n"}'
65532

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.securityContext}{"\n"}'
{"fsGroup":101,"runAsGroup":101,"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}}

$ docker exec curso-k8s-l8-worker2 stat -c '%a %u:%g %n' /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
2777 0:65532 /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
```

There are the two declared `fsGroup`s (65532 in the `revisor`, 101 in the task). And the `stat` of a current `revisor`'s `emptyDir`: `2777` and group `65532`: **in the `emptyDir`, `fsGroup` did change the group and set the *setgid***. In contrast, the volume of the `reportes` claim (8.5.2) had `777 0:0` even though its Pod declared `fsGroup: 101`. The reason, as told by the provisioner's README and confirmed by the measurement: the provisioner creates an ordinary node folder with permission `0777`, and the measurement shows that the `kubelet` did not change its group (the documentation only says that `fsGroup` acts on volumes that “support ownership management” and does not give the list; what we measured is that on this volume it did not, and that on the `emptyDir` and on 8.7.2's `local` volume it did. The PV this provisioner creates is of type `hostPath`: the `RUTA` column in 8.5.2 comes from `spec.hostPath.path`). It was not needed either: with `777`, any user writes.

This is not an oversight of the course: it is a difference between kind's `standard` class and a disk that is born with owner `root` and permission `755`, like the one 8.7.2 fabricates by hand. There, a container running as user 100 gets `Permission denied` when trying to write, **unless** `fsGroup` gives it the directory's group. With kind's `standard` class you are unlikely to see that error, and that is exactly the danger: a manifest that works because the folder is `777` can fail in another cluster for the very reason `fsGroup` exists. A manifest that already carries `fsGroup` is closer to working with a disk like that. That is why the course writes it even though it is not noticeable here.

#### 8.7.2 A disk like real ones

To see `fsGroup` at work you need a volume that does support it. Kubernetes has one at hand: the `local` type, a node folder presented as a disk (the documentation describes it as “a mounted local storage device such as a disk, partition or directory”). Unlike kind's provisioner, here **you** are the administrator: you create the folder on the node, you create the PV that describes it, and you create the claim that claims it. It is the static path from 8.3.2. The example used is `fig08_04.disco-local.yaml`, a **program** with two objects:

```yaml
# fig08_04.disco-local.yaml — Lección 8: un volumen creado a mano por «el administrador»,
# como los de un clúster real. Un PersistentVolume de tipo local (una carpeta de UN nodo,
# que hay que crear antes: mkdir -p /mnt/disco-reportes dentro del nodo curso-k8s-l8-worker)
# y la solicitud (PersistentVolumeClaim) que lo reclama. Su clase «manual» no existe como
# objeto: sirve solo de etiqueta para que la solicitud encuentre este volumen y no pida uno
# nuevo a la clase por omisión.
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disco-reportes
spec:
  capacity:
    storage: 100Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  local:
    path: /mnt/disco-reportes
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [curso-k8s-l8-worker]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: disco
  namespace: revisor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources:
    requests:
      storage: 100Mi
```

The PV's new fields: **`capacity`** is the size it offers; **`persistentVolumeReclaimPolicy: Retain`** is the reclaim policy that 8.8 measures; **`local.path`** is the node folder; and **`nodeAffinity`** is mandatory on a `local` volume: the documentation says “you must set a PersistentVolume `nodeAffinity` when using `local` volumes. The Kubernetes scheduler uses the PersistentVolume `nodeAffinity` to schedule these Pods to the correct node”. Here it says the volume is on the node whose name is `curso-k8s-l8-worker`. The `manual` class does not exist as an object; it is just a word that ties the two objects to each other and keeps the claim from falling into the default class. That the claim does not fail because of a nonexistent class (as happens in Exercise 1) has an explanation: dynamic provisioning is only attempted when no volume that already exists matches the claim, and here the PV existed.

The node's folder is prepared first, with `root` permissions and mode `755`, as a freshly formatted disk would leave it, and then the file is applied:

```bash
docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes
docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
ctx && kubectl apply -f fig08_04.disco-local.yaml
```

```text
$ docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
755 0:0 /mnt/disco-reportes

$ kubectl apply -f fig08_04.disco-local.yaml
persistentvolume/disco-reportes created
persistentvolumeclaim/disco created

$ kubectl get pv,pvc -n revisor
NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/disco-reportes                             100Mi      RWO            Retain           Bound    revisor/disco      manual         <unset>                          0s
persistentvolume/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound    revisor/reportes   standard       <unset>                          85s

NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/disco      Bound    disco-reportes                             100Mi      RWO            manual         <unset>                 0s
persistentvolumeclaim/reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 94s
```

The node's `stat` says `755 0:0`: owned by `root`, and only `root` can write. The PV `disco-reportes` is born `Bound` in the same second it exists, with policy `Retain`, and the claim `disco` also comes out `Bound` in this capture. Careful: the instant matters. In two other runs of the same script the capture fell before the binding finished: once with the claim still `Pending` and the volume already `Bound`, another time with the volume still `Available`. Binding takes a fraction of a second; if in your terminal you see `Pending`, repeat the `get` and it completes. There was no first-consumer wait: the `manual` class is not a class with delayed binding mode, and the volume already existed. Further down, the volume `pvc-5fcf36b8-…` is the one for `reportes`, with its class's `Delete` policy. In a real cluster you would not leave the class as a loose label: the documentation asks you to create a `StorageClass` for `local` volumes with `volumeBindingMode: WaitForFirstConsumer`, so that the claim does not bind to a disk on a node before knowing where the Pod will run. Here it is omitted because there is a single PV and its affinity decides the node.

Now, two Pods that do the same thing and differ only in one line. They write a file in `/datos`, running as user 100 and group 101, non-`root`. The first, `fig08_05.escritor-sin-fsgroup.yaml`, does not declare `fsGroup`:

```yaml
# fig08_05.escritor-sin-fsgroup.yaml — Lección 8: un Pod que corre sin root (usuario 100,
# grupo 101) e intenta escribir en el disco local de fig08_04, cuyo directorio es de root
# con permiso 0755. Sin fsGroup, nadie le cambia el dueño al directorio: Permission denied.
apiVersion: v1
kind: Pod
metadata:
  name: sin-fsgroup
  namespace: revisor
  labels:
    app: escritor
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
  - name: escritor
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sh", "-c", "id; ls -lnd /datos; echo hola > /datos/a.txt && ls -ln /datos"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
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
    persistentVolumeClaim:
      claimName: disco
```

The second, `fig08_06.escritor-con-fsgroup.yaml`, is the same file with `name: con-fsgroup` and one more line in the Pod's `securityContext`: `fsGroup: 101`. The command in both is short: `id` prints who the process is; `ls -lnd /datos` prints the mounted directory's owner and permission; and `echo hola > /datos/a.txt && ls -ln /datos` tries to write and, if it could, lists.

```bash
ctx && kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
```

```text
$ kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
pod/sin-fsgroup created

$ kubectl get pod -n revisor sin-fsgroup
NAME          READY   STATUS   RESTARTS   AGE
sin-fsgroup   0/1     Error    0          4s

$ kubectl logs -n revisor sin-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxr-xr-x    2 0        0             4096 Oct 21 23:26 /datos
sh: can't create /datos/a.txt: Permission denied
```

That is the error `fsGroup` prevents, measured. It is read in three lines: the process is user 100, with group 101 and no other; the directory belongs to `0:0` with `drwxr-xr-x` (only `root` writes: user 100 falls in the “others” category, which has read and entry but not write); and `sh` says it bluntly, `can't create /datos/a.txt: Permission denied`. The Pod ended in `Error`: the command failed, and with `restartPolicy: Never` it is not restarted. Now the same Pod with the extra line:

```bash
ctx && kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
ctx && kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
```

```text
$ kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
pod "sin-fsgroup" deleted from revisor namespace

$ kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
pod/con-fsgroup created

$ kubectl get pod -n revisor con-fsgroup
NAME          READY   STATUS      RESTARTS   AGE
con-fsgroup   0/1     Completed   0          3s

$ kubectl logs -n revisor con-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxrwsr-x    2 0        101           4096 Oct 21 23:26 /datos
total 4
-rw-r--r--    1 100      101              5 Oct 21 23:26 a.txt

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
2775 0:101 /mnt/disco-reportes
```

`Completed`, and the file `a.txt` of 5 bytes (`hola` and a newline) written. Look at the directory in the log: `drwxrwsr-x`, group `101`. And on the node, `stat` says `2775 0:101`: **the `kubelet` changed the folder's group to 101 and gave that group write permission, with *setgid*, before starting the container**. The process belongs to group 101, and that is why it can write. The owner is still `root`; what changed is the group. It is what the documentation says: volumes that support ownership management “are modified to be owned by the GID specified in `fsGroup` and writable by it”.

The *setgid* (the `s`) has a practical effect that makes `fsGroup` worthwhile: the files created inside the directory **inherit its group**, 101, and not the primary group of the process that creates them. Here the effect is not noticeable, because the process already belongs to group 101 (`runAsGroup: 101`); it would be noticeable in a process with another primary group. And for another Pod of group 101 to be able to *modify* those files, each file would need group permission (umask 002), which this task does not ask for: its files come out `-rw-r--r--`.

A note on cost, which the security context documentation explains: by default, Kubernetes changes the owner and permissions of **all the content** of the volume every time it is mounted. For a volume with millions of files, that takes time and delays the Pod's start. The field `fsGroupChangePolicy: OnRootMismatch` asks for the change to be made only if the owner or permission of the volume's root do not match what is expected, and avoids walking it when it is already in order. With 100 Mi volumes you do not notice; with large disks, you do.

#### 8.7.3 Retain: the volume survives its claim

The two Pods are no longer needed. And the manual disk also serves to see what cannot be seen with `Delete`: the `Retain` policy. The claim is deleted:

```bash
ctx && kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
ctx && kubectl delete pvc -n revisor disco
```

```text
$ kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
pod "con-fsgroup" deleted from revisor namespace

$ kubectl delete pvc -n revisor disco
persistentvolumeclaim "disco" deleted from revisor namespace

$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
disco-reportes                             100Mi      RWO            Retain           Released   revisor/disco      manual         <unset>                          11s
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound      revisor/reportes   standard       <unset>                          96s
```

The claim is gone; the volume is **not**. Its state is `Released`, which the documentation defines like this: “the claim has been deleted, but the associated storage resource is not yet reclaimed by the cluster”. With `Retain`, the volume keeps its `CLAIM revisor/disco` noted and is not available for another claim, because “the previous claimant's data remains on the volume”. Recovering it is a manual job for the administrator, in three steps that the documentation gives: delete the PV, clean up the data on the storage and delete the associated storage (or reuse it with a new PV). The PV is deleted and the disk is examined:

```text
$ kubectl delete pv disco-reportes
persistentvolume "disco-reportes" deleted

$ docker exec curso-k8s-l8-worker ls -ln /mnt/disco-reportes
total 4
-rw-r--r-- 1 100 101 5 Oct 21 23:26 a.txt
```

The PV object disappeared from Kubernetes; the node's folder, and the `a.txt` file the Pod wrote, are still there. That is `Retain`: the cluster lets go of the object and does not touch the data. It is the policy chosen for data that must not disappear because of a mistaken `kubectl delete`, in exchange for a manual cleanup job. (The folder lives inside the node's container, so `kind delete cluster` takes it away. If you wanted some data to survive the entire cluster, [kind's configuration](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts) lets you mount a folder from your machine inside a node with `extraMounts`; the course does not do this.)

### 8.8 Deleting the claim: that is where it is lost

The `standard` class's policy is `Delete`. We measure what happens with the `reportes` claim, the one that stores the lesson's reports. First the policy is looked at, then deletion is requested **without waiting** (`--wait=false`), because what follows may end up waiting:

```bash
ctx && kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
ctx && kubectl delete pvc -n revisor reportes --wait=false
```

```text
$ kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
Delete

$ kubectl delete pvc -n revisor reportes --wait=false
persistentvolumeclaim "reportes" deleted from revisor namespace

$ kubectl get pvc -n revisor
NAME       STATUS        VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Terminating   pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 111s

$ kubectl get pvc -n revisor reportes -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}{"\n"}'
["kubernetes.io/pvc-protection"] 2026-10-21T23:26:21Z

$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-29877085-6q87g   0/1     Completed   0          86s
reporte-manual-1-t7d8l   0/1     Completed   0          105s
reporte-manual-2-4hmmf   0/1     Completed   0          96s
```

`Terminating`: it asked to be deleted and it is not deleted. The command returned control because it had `--wait=false`; without that option, `kubectl delete` would have stayed waiting. The explanation is in `finalizers: ["kubernetes.io/pvc-protection"]`, which is a *mark* that prevents an object from disappearing until something removes it. The documentation calls this feature **storage object in use protection**, and its purpose is “to ensure that PersistentVolumeClaims in active use by a Pod and PersistentVolume that are bound to PersistentVolumeClaims are not removed from the system, as this may result in data loss”. And it defines what “in active use” is: **a claim is in use when a Pod object that uses it exists.** If you delete it in that case, “the PersistentVolumeClaim removal is postponed until the PersistentVolumeClaim is no longer actively used by any Pods”.

Look at the last output: three `Completed` Pods. They finished a while ago and no longer run, but they **exist as objects** (they were kept so you could read their log), and each one declares the `reportes` claim in its volumes. For the protection, they are still using it. The claim waits for those Pods to stop existing. The way out is not to force the deletion, but to remove those who hold it up: delete the Jobs, which take their Pods with them.

```bash
ctx && kubectl delete jobs -n revisor --all
```

```text
$ kubectl delete jobs -n revisor --all
job.batch "reporte-29877085" deleted from revisor namespace
job.batch "reporte-manual-1" deleted from revisor namespace
job.batch "reporte-manual-2" deleted from revisor namespace

$ kubectl get pvc,pv
No resources found

$ docker exec curso-k8s-l8-worker ls -la /var/local-path-provisioner/
total 8
drwxr-xr-x  2 root root 4096 Oct 21 23:26 .
drwxr-xr-x 12 root root 4096 Oct 21 23:24 ..
```

As soon as the Pods were gone, the claim's deletion moved forward: there is no claim and no volume (`No resources found`), and the node's folder, `pvc-5fcf36b8-…_revisor_reportes`, **disappeared along with all its reports**. The `/var/local-path-provisioner/` directory was left empty. That is the `Delete` policy in action: the claim is deleted, the volume is deleted and the storage is deleted. In the run's deletion, the intermediate `Released` state of the dynamic volume was not seen (the script looked 8 seconds after deleting the Jobs and by then the volume no longer existed; I do not know in exactly how much time it disappeared); the one in 8.7.3, with `Retain`, did show it.

Recreating the claim and requesting a new task shows what remains: nothing from the past.

```bash
ctx && kubectl apply -k . | grep persistentvolumeclaim
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
```

```text
$ kubectl apply -k . | grep persistentvolumeclaim
persistentvolumeclaim/reportes created

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
job.batch/reporte-manual-3 created

$ kubectl logs -n revisor job/reporte-manual-3
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
```

A single file: the current one. The past reports are not there. With this, the section's rule comes down to one sentence for when you someday do it by accident: **with the `Delete` policy, the data lives as long as the claim lives and deleting the claim takes the data with it; with `Retain`, it survives it and someone has to clean it up** (8.7.3). The policy belongs to the class, not to whoever deletes: that is why it pays to know which class it is before deleting anything called `pvc`.

## The error you will see

This lesson has two errors on purpose. You already saw the second one in 8.7.2: the `Permission denied` of the Pod that writes to a `root` volume without `fsGroup`. The first is that of a task that never reaches the `revisor`.

### BackoffLimitExceeded: a Job that cannot get out

`fig08_02.job-sin-etiqueta.yaml` is the practice Job from 8.5.1 with **one** difference: it is missing the label `acceso-revisor: permitido`. It is the mistake you make when you copy a template and forget a line that cannot be seen.

```bash
diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
ctx && kubectl apply -f fig08_02.job-sin-etiqueta.yaml
```

The script does not run the `diff` (it does not touch the cluster); this is its output, run in the programs folder. Besides the comments in the header and the name, the only difference in content is the label line:

```text
$ diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
1,3c1,4
< # fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
< # a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
< # cerrada de la Lección 7 exige para que un Pod hable con el revisor.
---
> # fig08_02.job-sin-etiqueta.yaml — Lección 8: el MISMO Job de fig08_01, sin la etiqueta
> # acceso-revisor. La red cerrada de la Lección 7 no lo deja salir hacia el revisor: curl se
> # rinde a los 5 s (código 28), el Job reintenta dos veces y termina Failed con
> # BackoffLimitExceeded.
7c8
<   name: salud
---
>   name: salud-sin-etiqueta
16d16
<         acceso-revisor: permitido
```

A Job like this does not fail right away. It retries, with the waits that 8.5.1 described, and the lesson watches it in plain sight, every 15 seconds:

```text
$ kubectl apply -f fig08_02.job-sin-etiqueta.yaml
job.batch/salud-sin-etiqueta created

(esperando hasta 150 s a que el Job agote sus reintentos; se mira cada 15 s)
  + 15 s: 1 fallidos,  activos, condiciones:
  + 30 s: 2 fallidos,  activos, condiciones:
  + 45 s: 2 fallidos, 1 activos, condiciones:
  + 60 s: 3 fallidos,  activos, condiciones: FailureTarget=True Failed=True

$ kubectl get job,pods -n revisor -l app=salud
NAME                           STATUS   COMPLETIONS   DURATION   AGE
job.batch/salud-sin-etiqueta   Failed   0/1           61s        61s

NAME                           READY   STATUS   RESTARTS   AGE
pod/salud-sin-etiqueta-9bnv9   0/1     Error    0          61s
pod/salud-sin-etiqueta-svs9r   0/1     Error    0          44s
pod/salud-sin-etiqueta-tr95q   0/1     Error    0          19s
```

**First, the state.** At 61 seconds, the Job is `Failed` and has three Pods, all three `Error`. They are exactly what `backoffLimit: 2` said: the original and two retries. The ages (`61s`, `44s`, `19s` since they were created, read backwards) tell the growing wait from the documentation: the second Pod was born 17 seconds after the first (5 of `curl` plus 10 of waiting) and the third 25 after the second (5 more 20). They are not round seconds because the cluster adds a few extra when creating Pods.

**Second, the log, because the container did run.**

```text
$ kubectl logs -n revisor job/salud-sin-etiqueta
Found 3 pods, using pod/salud-sin-etiqueta-9bnv9
curl: (28) Connection timed out after 5000 milliseconds

$ kubectl get pods -n revisor -l app=salud -o custom-columns=POD:.metadata.name,CODIGO:.status.containerStatuses[0].state.terminated.exitCode,RAZON:.status.containerStatuses[0].state.terminated.reason
POD                        CODIGO   RAZON
salud-sin-etiqueta-9bnv9   28       Error
salud-sin-etiqueta-svs9r   28       Error
salud-sin-etiqueta-tr95q   28       Error
```

`kubectl logs job/…` warns that there are three Pods and that it shows one. The `curl` message is the one you know from Lesson 7: **code 28**, “connection timed out”. The closed network does not let a Pod without the access label out toward the `revisor`, and it does not answer with a rejection: it simply does not answer, and `curl` waits its 5 seconds (`-m 5`) and gives up. All three Pods ended with code 28. It is the same failure of “the open entry that does not let anyone in” from Lesson 7, seen from a task.

**Third, the Job: why it gave up.**

```text
$ kubectl get job -n revisor salud-sin-etiqueta -o jsonpath='{range .status.conditions[*]}{.type} {.status} {.reason}: {.message}{"\n"}{end}'
FailureTarget True BackoffLimitExceeded: Job has reached the specified backoff limit
Failed True BackoffLimitExceeded: Job has reached the specified backoff limit

$ kubectl describe job -n revisor salud-sin-etiqueta | sed -n '/^Events:/,$p'
Events:
  Type     Reason                Age   From            Message
  ----     ------                ----  ----            -------
  Normal   SuccessfulCreate      62s   job-controller  Created pod: salud-sin-etiqueta-9bnv9
  Normal   SuccessfulCreate      45s   job-controller  Created pod: salud-sin-etiqueta-svs9r
  Normal   SuccessfulCreate      20s   job-controller  Created pod: salud-sin-etiqueta-tr95q
  Warning  BackoffLimitExceeded  10s   job-controller  Job has reached the specified backoff limit
```

`BackoffLimitExceeded` (“the retry limit was exceeded”) is the reason for the failure, just as the documentation lists the causes for which a Job fails: “the number of Pod failures exceeded the `.spec.backoffLimit`”. The events, from top to bottom, are the story in four lines: three creations and the surrender.

**Fourth, the cause, which the Job cannot tell.** Nothing above says *why* the `curl` times out. The comparison with what does work says that. `depurar`, which in 8.1 talked fine with the `revisor`, carries a label that this Job does not have:

```text
$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          3m36s   acceso-revisor=permitido,app=depurar
```

`acceso-revisor=permitido` is the label the network policies from Lesson 7 ask for. The lesson's Job, the real `CronJob`, carries it in its template, with a comment that explains it; this one does not. **The fix** is the usual one: the file is the truth. The line is added to the manifest and it is applied again; here, the experiment is simply deleted:

```text
$ kubectl delete -f fig08_02.job-sin-etiqueta.yaml
job.batch "salud-sin-etiqueta" deleted from revisor namespace
```

Two lessons from this error. **The first**: a Job that fails says that it failed, not why; the cause is in its Pods' log (`curl: (28)`) and in what you know about the network. **The second**: a scheduled task that fails at 3 in the morning wakes nobody up. The `CronJob` keeps the last three failed Jobs (`failedJobsHistoryLimit: 3`) precisely so that someone, the next day, can go and read what happened to them. Without monitoring, a task that fails silently for weeks produces the opposite of what it promised: the feeling that there is a backup where there is none. It is the lesson of the GitLab account that opened the lesson, in miniature.

The order for a task that did not work: `kubectl get jobs` (`Failed`?); the Job's Pods (`kubectl get pods -l …`) and the exit code of each one; the log (`kubectl logs job/…`); and, if the Job did not create even one Pod, the Job's own events (`kubectl describe job`). Before changing anything, know whether it failed once, always, or sometimes.

## The lesson's security habit: data with its owner

The course's table of habits assigns this lesson two things: the `ServiceAccount` without mounted credentials if it does not need them, and data with its owner. Both are checked in the cluster.

**The task's service account.** The task talks to the `revisor` over HTTP; it does not talk to the cluster API. It does not need a credential for that, and therefore none is mounted:

```text
$ kubectl get serviceaccount reporte -n revisor -o jsonpath='{.automountServiceAccountToken}{"\n"}'
false

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.automountServiceAccountToken}{" "}{.spec.jobTemplate.spec.template.spec.containers[0].env}{"\n"}'
false

$ kubectl get pods -n revisor -l app=reporte -o custom-columns=POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name
POD                      CUENTA    AUTOMOUNT   VOLUMENES
reporte-manual-3-2657n   reporte   false       datos,token

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/api/estados
401
```

`false` on the account, `false` in the CronJob's template, and `env` empty (the second value of the second output is nothing: the task receives no variables with secrets). The task Pod's volumes are two and are called `datos` and `token`: **neither is the API credential**. If someone managed to run code inside the task, they would not find a cluster token to steal. And the `revisor`'s token goes as a read-only file with `0440`, not as an environment variable: it is what Lesson 4 taught. The last output is the proof that the `revisor` still asks for it: without a token, `401`.

**Data with its owner.** The three pieces that were measured:

- **The volume's group is set by `fsGroup`**, not by an open permission. On a real disk, the solution to a `Permission denied` is to give the group, not `chmod 777`. In 8.7.2 the volume belonged to `root` with `755`, and with one line it ended up as `2775 0:101`: owned by `root`, group 101, writable only by that group (and readable by everyone).
- **The process runs non-`root`** and the file it creates is its own: `-rw-r--r-- 1 100 101` in the task; `-rw------- 1 65532 65532` in the `revisor`. Each writer leaves its mark, and you can tell who wrote what.
- **The token does not reach the data volume.** The task reads the token from `/secretos`, a read-only volume, and writes only to `/datos`. Keeping input and output separate prevents a task mistake from writing the secret in a place where it is kept.

**The size that the cluster does not enforce.** One surprise is missing, the one from section 8.4.1, where it was said there would be something to say about how seriously a cluster takes the `100Mi` number. The volume requested 100 mebibytes and the cluster said `CAPACITY 100Mi`. It is tested with a Job, `fig08_07.llenar-el-volumen.yaml`, which writes 150 million bytes (about 143 MiB) to that same volume:

```bash
ctx && kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
ctx && kubectl apply -f fig08_07.llenar-el-volumen.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/llenar --timeout=180s
ctx && kubectl logs -n revisor job/llenar
ctx && kubectl delete -f fig08_07.llenar-el-volumen.yaml
```

(The `wait` avoids asking for the log before the Pod finishes writing; the script runs it without printing it.)

```text
$ kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
100Mi 100Mi

$ kubectl apply -f fig08_07.llenar-el-volumen.yaml
job.batch/llenar created

$ kubectl logs -n revisor job/llenar
total 146496
-rw-r--r--    1 100      101      150000000 Oct 21 23:27 grande.bin
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
/dev/root                57.1G     48.4G      8.6G  85% /datos

$ kubectl delete -f fig08_07.llenar-el-volumen.yaml
job.batch "llenar" deleted from revisor namespace
```

The Job ended without error and `ls` shows `grande.bin` of **150000000 bytes** on a volume that requested and received 100Mi. And the `df` from inside the Pod shows the reason: the “volume” `/datos` appears as `/dev/root`, of 57.1 GB, 85 % used: it is the node's disk, which in kind is the Docker machine's, not a 100 Mi slice (the device name and size change on your machine). It is exactly what the provisioner's README announced (“the capacity is ignored for now”): the `storage` number decides which PV the claim binds with, but kind's class does not limit what is written.

This is a lab finding worth not forgetting: **with kind's class, what you ask for is not what you get; on other storage it depends on the system, and it is worth measuring**. In a real cluster, real storage does have a size and fills up (with a `No space left on device` error that takes the application down mid-write), and a namespace without a quota can create claims of any size. The storage quota (`ResourceQuota`, with `requests.storage`) sets a maximum per namespace, as mentioned in Lesson 5 for CPU and memory; the course names it and does not install it.

**What it protects against and what it does not.** These habits protect that the task does not have more power than it needs, that the token does not leak to disk, and that files have an identifiable owner. They do not protect the data: a `Delete` erases it (8.8), a node that is down makes it inaccessible (the volume is on a single disk), and nobody backs it up. What really takes care of the data is the row that lesson 10 puts in the list of what is missing for production: replicated storage outside the node, volume snapshots and backups that are **tested** by restoring. One sentence about each, so you know what problem it solves: a `StatefulSet` is the object for stateful applications, whose Pods have a stable identity and a volume of their own each (the course does not use it); a volume snapshot is a copy of the volume at an instant, used to go back; and a tested backup is the copy that someone has already restored elsewhere and verified, which is exactly what the GitLab account at the beginning lacked.

## Common mistakes

**Saving in an `emptyDir` what must outlive the Pod.** You saw it in 8.2.3: the container survives a crash, the Pod does not survive a deletion, and draining a node (`drain`), an eviction or a node declared lost delete Pods; a node reboot does not necessarily, but it is not wise to bet on it either. An `emptyDir` is for scratch space, not for history.

**Believing that `Pending` on a claim is an error.** With `WaitForFirstConsumer`, a claim without a Pod correctly stays `Pending`. Read the event before acting.

**Putting `storage: 100Mi` and believing that is the end of it.** In kind, the size is not enforced (“The security habit” measures it). In production, the disk fills up. You have to watch usage, with alerts, before it reaches the cap.

**Deleting a claim (`pvc`) without knowing the class's policy.** With `Delete`, the data is erased. With `Retain`, it is kept and someone must clean it up. Look at `RECLAIMPOLICY` first.

**Deleting a PV by hand to “free” a stuck claim.** A claim in `Terminating` is waiting for the Pods that use it; the PV has its own protection. Forcing finalizers (`kubectl patch … finalizers`) to skip the protection is the way to damage data in use. You find and delete what holds it up (in this lesson, the Jobs).

**Using `chmod 777` or an open volume to make it “just write”.** It is what kind's provisioner does, and that is why the problem is rarely noticed. On a real disk the remedy is `fsGroup` and a non-`root` user, not opening the directory to everyone.

**Writing a task that does not support running twice.** The documentation warns about it: the CronJob can create two Jobs or none. A task that adds up, sends or charges without protection is a duplicate waiting to happen.

**Leaving `concurrencyPolicy: Allow` by default on a task that writes to a shared volume.** Two tasks at once in the same folder, and a slow task that overlaps with the next, can pile up Pods without anyone noticing. `Forbid` or `Replace` say explicitly what you want.

**A Job without `backoffLimit` or `activeDeadlineSeconds`.** The default number of retries is 6 and time has no cap: a hung task stays hung. Set both on real tasks, with numbers you can justify (the lesson's practice Jobs, which last seconds, do not all carry them).

**A CronJob without history or with an enormous history.** Without history (`0`), there is no evidence of what failed. With a very large number, Jobs and Pods pile up by the thousands. Choose a small number and review it.

**Giving the task a service account with permissions “just in case”.** A task that only speaks HTTP does not need an API credential. `automountServiceAccountToken: false` and an account of its own without permissions.

**Putting the token in the command or in an environment variable of the task.** It is read from the mounted file at run time, as the lesson's task does.

**Forgetting a CronJob's time zone.** Without `timeZone`, the schedule is the controller's (UTC in kind). “Every day at 3” is not what you think if you are six hours from UTC.

**Saving every replica's report on a local `ReadWriteOnce` volume.** Exercise 2 tests it: it ties all the replicas to a single node.

## Exercises

The first three are run in the lesson's cluster, in order and from the state it was left in after “the security habit”. Before each one, the `ctx` function must give you success (`ctx && echo ok`). **Before** running each one, write in the [logbook](bitacora.md) what you think is going to happen. The fourth is written in your own words.

### Exercise 1 — A storage class that does not exist

`fig08_08.pvc-clase-inexistente.yaml` creates a volume claim that asks for the class `rapido` (which this cluster does not have) and a Pod, `lector`, that uses it. Apply it. Before looking, predict: what state is the claim left in? And the Pod? What event do you think each gives, and who emits it? Check it with `kubectl get pvc rapido -n revisor`, `kubectl get pod lector -n revisor` and the `describe` of both. And the hard question: how long would you wait before concluding that it will not resolve itself? When you finish, delete it with `kubectl delete -f fig08_08.pvc-clase-inexistente.yaml`.

### Exercise 2 — The `revisor`'s report, on the volume

The course's decision is that the `revisor` saves its `reporte.json` in the `emptyDir` and that the task saves its own on the volume. Check it with a one-line change. With `kubectl patch`, replace the `datos` volume of the `revisor`'s Deployment (the first in the list, `/spec/template/spec/volumes/0`) with one that uses the `reportes` claim:

```bash
ctx && kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
```

Predict: do the three replicas start? On which node does each one land? What does `kubectl get pv` say about the volume? Request a report with `depurar` and look for the file on the node. Then undo the change with `kubectl apply -k .` (the file is the truth) and check where the replicas end up. Explain in five sentences why this is not what you want for the project, and what is lost of what Lesson 9 is going to ask for.

### Exercise 3 — A task that takes longer than its schedule

`fig08_09.cron-lento.yaml` is a CronJob that runs every minute (`* * * * *`) with `concurrencyPolicy: Forbid`, and whose task takes **100 seconds** (`sleep 100`). Predict, before applying it: at two and a half minutes, how many Jobs will be running at once? Will the ones for the intermediate minutes be created? What event does the CronJob leave when it skips one? Apply it, look every 35 seconds for about 210 seconds (the first task takes close to two minutes and you have to see how it ends) with `kubectl get cronjob lento -n revisor` and `kubectl get jobs -n revisor` and read `kubectl describe cronjob lento -n revisor`. Then delete the CronJob (`ctx && kubectl delete -f fig08_09.cron-lento.yaml`), wait for the start of a minute and create it again with the policy changed without touching the file: `sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -`; repeat with `Replace`. That way the file stays intact for the `correr.sh` run. Compare: what do you see with each value? When you finish, delete it with `ctx && kubectl delete -f fig08_09.cron-lento.yaml`: if you leave it, it keeps creating a Job per minute, and `kubectl diff -k .` does not detect it because it is not part of the lesson's files.

### Exercise 4 — Two schedules

In five sentences at most, write your answer to this. (a) The cron schedule of a task that runs **on weekdays at 7:30 in the morning, Mexico City time**, and which field of the CronJob specification you need besides the schedule. (b) The schedule of a task that runs **every two hours on the hour**. (c) What happens to a run scheduled for 3:00 if the CronJob controller was down from 2:50 to 3:20 and the CronJob has `startingDeadlineSeconds: 600`; and what changes if it does not have it. (d) Why the report task can run twice in the same minute without damaging anything.

## Solutions

### Solution 1

Measured in `correr.salida.txt`:

```text
$ kubectl apply -f fig08_08.pvc-clase-inexistente.yaml
persistentvolumeclaim/rapido created
pod/lector created

$ kubectl get pvc rapido -n revisor
NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
rapido   Pending                                      rapido         <unset>                 12s

$ kubectl get pod lector -n revisor
NAME     READY   STATUS    RESTARTS   AGE
lector   0/1     Pending   0          12s

$ kubectl describe pvc rapido -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason              Age               From                         Message
  ----     ------              ----              ----                         -------
  Warning  ProvisioningFailed  6s (x2 over 12s)  persistentvolume-controller  storageclass.storage.k8s.io "rapido" not found

$ kubectl describe pod lector -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  13s   default-scheduler  0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
```

**Both are `Pending`, but for reasons with different owners.** The claim is because the `persistentvolume-controller` looks for the class `rapido`, does not find it, and emits a `Warning` with the exact cause: `storageclass.storage.k8s.io "rapido" not found`. Unlike the `Pending` in 8.4, this one is at the `Warning` level and does not say “waiting”: it says that something does not exist. The Pod is because the scheduler, which sees it with an unbound claim, answers `0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims`: no node will do while the claim is not bound. (The message ends with a loose `not found`, just as the run's cluster printed it; the text of events changes between versions, and what you should read is the cause in the claim's event.)

The reading is the usual one: the `Pending` Pod is not the problem, it is the symptom. The cause is one object further down, in the claim, and its event says which class is missing. The fix is to write a class that exists (`kubectl get storageclass` gives the list) or create the one that is missing. As for how long to wait: none of this resolves itself. The claim without a class stays `Pending` “indefinitely”, as the persistent volumes documentation says for a claim without a matching volume, until someone creates the class; there is no timeout or final error. A `Pending` with `ProvisioningFailed` is not a wait, it is a warning.

### Solution 2

Measured in `correr.salida.txt`:

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
deployment.apps/revisor patched

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-6d9bd59b8b-5wnrq   1/1     Running   0          7s    10.244.2.24   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-sjjkr   1/1     Running   0          10s   10.244.2.23   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-z7sc9   1/1     Running   0          12s   10.244.2.22   curso-k8s-l8-worker   <none>           <none>

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
NOMBRE                                     NODO
pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   curso-k8s-l8-worker

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40_revisor_reportes
total 146508
drwxrwxrwx 2     0     0      4096 Oct 21 23:28 .
drwxr-xr-x 3     0     0      4096 Oct 21 23:26 ..
-rw-r--r-- 1   100   101 150000000 Oct 21 23:27 grande.bin
-rw-r--r-- 1   100   101        92 Oct 21 23:26 reporte-20261021T232640Z.json
-rw------- 1 65532 65532        93 Oct 21 23:28 reporte.json

$ kubectl apply -k . | grep -E 'deployment|persistentvolumeclaim'
persistentvolumeclaim/reportes unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-6b7f4d564d-mgzwr   1/1     Running       0          2s    10.244.1.9    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-nxzdj   1/1     Running       0          7s    10.244.1.8    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-tk4tr   1/1     Running       0          5s    10.244.2.25   curso-k8s-l8-worker    <none>           <none>
revisor-6d9bd59b8b-5wnrq   1/1     Terminating   0          15s   10.244.2.24   curso-k8s-l8-worker    <none>           <none>
```

**The three replicas start, and all three land on the same node**: `curso-k8s-l8-worker`, the one that has the volume. The scheduler could not spread them because the PV has a node affinity (8.5.2): any Pod that uses the claim must run where the disk is. And all three did because that mode, `ReadWriteOnce`, is “one node”, not “one Pod”: several Pods on the same node can mount the volume at once. The documentation says it, and here it was seen. The `revisor`'s `reporte.json` appears in the same folder as the task's reports, next to `grande.bin` (the 150 MB from “the security habit”, still there because the volume is the same) and the task's dated file from task 3.

It is undone with `kubectl apply -k .`: the replicas go back to the `emptyDir` and are spread again across the two worker nodes (`worker` and `worker2`). What would look bad in the project, in five sentences: (1) all the replicas end up on a single node, because the volume is on a single disk; (2) if that node goes down, the entire `revisor` is left with nowhere to run, because the Pods cannot move to another node with their volume; (3) the three replicas would write the **same** `reporte.json`, overwriting each other, which is worse than before; (4) the spreading of replicas across nodes that Lesson 9 needs to scale and to update while measuring each outage disappears; (5) what the report needs is history with a name and a date, and the task already does that.

### Solution 3

Measured in `correr.salida.txt`. First `Forbid` (the script waits for the start of a clock minute before applying each variant, so that the first task falls on the next `:00`):

```text
$ kubectl apply -f fig08_09.cron-lento.yaml
cronjob.batch/lento created

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:30:45
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        45s             105s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Running    0/1           45s        45s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:31:56
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        56s             2m56s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Complete   1/1           103s       117s
lento-29877091     Running    0/1           14s        14s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age                From                Message
  ----    ------            ----               ----                -------
  Normal  SuccessfulCreate  2m32s              cronjob-controller  Created job lento-29877090
  Normal  SawCompletedJob   49s                cronjob-controller  Saw completed job: lento-29877090, condition: Complete
  Normal  SuccessfulCreate  49s                cronjob-controller  Created job lento-29877091
  Normal  JobAlreadyActive  32s (x4 over 92s)  cronjob-controller  Not starting job because prior execution is running and concurrency policy is Forbid
```

**With `Forbid`, a single Job at a time, and the intermediate minutes are not created.** The first Job, `lento-29877090`, was born at `23:30:00` and took 103 seconds (100 of `sleep` plus what it takes to start and finish). While it ran, the schedule times of `23:31:00` arrived and nothing was created: the CronJob left `ACTIVE 1` and carried on with the same one. When the Job finished, at about `23:31:43`, the CronJob saw it (`SawCompletedJob`) and created **another** immediately, `lento-29877091`. Notice the second one's name: `…091` is that of `23:31:00`, not that of `23:32:00`. The reason is in the documentation: when the previous run ends, `startingDeadlineSeconds` (which was not set here, and therefore has no cap) still counts, and the `23:31:00` run that had been skipped is finally created. (In `correr.salida.txt` there is one more capture, at 35 seconds after applying, that still has no Job: the CronJob was created at `23:29:00` and its first schedule time was `23:30:00`; that is why `lento-29877090` belongs to the next minute.)

The event left by the skipped schedule times is `JobAlreadyActive`, with the message `Not starting job because prior execution is running and concurrency policy is Forbid`, and the counter `x4 over 92s` says how many times it happened in the while you were looking. The documentation adds a consequence: a run skipped by `Forbid` counts as missed.

Now the same task with `Allow`, the default value, and then with `Replace`. Both are measurements, not arithmetic:

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Allow

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:35:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     2        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877094     Running    0/1           81s        81s
lento-29877095     Running    0/1           21s        21s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877094-mt8vs   1/1     Running   0          81s
lento-29877095-hqn7d   1/1     Running   0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877094
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877095
```

**With `Allow`, two Jobs run at once.** The first (`lento-29877094`) began at `23:34:00`; at `23:35:00` the second (`lento-29877095`) arrived without waiting for the first to finish, and the capture shows `ACTIVE 2`, two `Running` Jobs and two `Running` Pods at the same time, with 81 and 21 seconds of life. The events are only `SuccessfulCreate`, one per schedule time: there is no `JobAlreadyActive`, because nothing is skipped. Since the task lasts 100 seconds and the schedule is 60, in steady state there are always between one and two active (this last part comes from arithmetic; what was measured is the first overlap). With a task that writes to a shared volume, those two Pods would write at the same time: that is why 8.6 chooses `Forbid` for the report.

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Replace/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Replace

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:37:46
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        46s             106s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877097     Running    0/1           46s        46s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877097-n8cpx   1/1     Running   0          46s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:38:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877098     Running    0/1           21s        21s
NAME                   READY   STATUS        RESTARTS   AGE
lento-29877097-n8cpx   1/1     Terminating   0          81s
lento-29877098-g6cvv   1/1     Running       0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877097
  Normal  SuccessfulDelete  21s   cronjob-controller  Deleted job lento-29877097
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877098
```

**With `Replace`, the running Job is deleted and another is started, and none gets to finish.** The first (`lento-29877097`) began at `23:37:00`; at `23:38:00` the CronJob **deleted** it (`SuccessfulDelete`) and created `lento-29877098` in its place. In the last capture the old Pod is `Terminating` and the new one `Running` with 21 seconds. The first Job lived 60 seconds, less than the 100 it needs, and did not get to finish. That was measured once (the first replacement); that the following ones repeat the same comes from the schedule still being 60 seconds and the task 100. `Replace` is the value for tasks whose latest result is the only one that matters and that can be restarted without harm, and the wrong one for a task that needs its full 100 seconds.

The three policies are an answer to “what happens when the task is slower than its schedule”, and the right answer is the one that describes what your task needs, not the default value.

### Solution 4

One possible answer: “(a) `30 7 * * 1-5`, which is minute 30, hour 7, any day of the month, any month, from Monday (1) to Friday (5); and also `timeZone: "America/Mexico_City"` in the specification, because without it the schedule is interpreted in the controller's zone, UTC in kind, and the task would run at 1:30 in the morning. (b) `0 */2 * * *`: minute 0 of every second hour. (c) With `startingDeadlineSeconds: 600`, at 3:20 the CronJob sees that the 3:00 run was delayed 1200 seconds, more than the deadline of 600, and skips it, because it is already too late for it; with the field unset, there is no deadline and it creates it as soon as the controller returns, at 3:20, 20 minutes late, unless more than 100 missed runs have accumulated, in which case it refuses to start. (d) Because it is safe under repetition: the file name carries the date with seconds and each run writes a different file, so two runs leave two files and nothing is corrupted or lost (it is not idempotent in the strict sense: the result is not the same as with a single one).”

## Deleting the cluster

Before deleting, the final state. First the `depurar` Pod is removed, which is not part of the lesson's files (`ctx && kubectl delete pod depurar -n revisor --wait=false`); that is why, in the output below, `Terminating` appears in the Pod list. If the lesson's chain was followed in order and the experiments were undone, the cluster must be exactly what the files say. It is Lesson 5's `kubectl diff`, now the other way around: no differences, it exits with 0.

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Bound    pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   100Mi      RWO            standard       <unset>                 12m

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        3m53s           14m

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-29877090   Complete   1/1           4s         8m53s
reporte-29877095   Complete   1/1           4s         3m53s
reporte-manual-3   Complete   1/1           8s         12m

$ kubectl get pods -n revisor
NAME                       READY   STATUS        RESTARTS   AGE
depurar                    1/1     Terminating   0          14m
prueba-6899c74865-9dckl    1/1     Running       0          15m
reporte-29877090-8ms5h     0/1     Completed     0          8m53s
reporte-29877095-wbx85     0/1     Completed     0          3m53s
reporte-manual-3-2657n     0/1     Completed     0          12m
revisor-6b7f4d564d-mgzwr   1/1     Running       0          10m
revisor-6b7f4d564d-nxzdj   1/1     Running       0          10m
revisor-6b7f4d564d-tk4tr   1/1     Running       0          10m

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

The `reportes` claim is bound, the `reporte` `CronJob` is scheduled and has already run on its own (the Jobs `reporte-29877090` and `reporte-29877095`, from `23:30` and `23:35`, were created by it), and the Gateway's entry point still answers from outside. That is the state Lesson 9 starts with. (The only `Terminating` Pod is `depurar`, which was deleted just before this check; the Exercise 3 `lento-…` Pods are no longer there because the script waited for them to disappear before measuring.)

When you finish, delete the lesson's cluster. Do not leave anything alive on the machine:

```text
$ kind delete cluster --name curso-k8s-l8
Deleting cluster "curso-k8s-l8" ...
Deleted nodes: ["curso-k8s-l8-worker2" "curso-k8s-l8-control-plane" "curso-k8s-l8-worker"]
(borrar tardó 4 s)

$ kind get clusters | grep -c curso-k8s-l8
0
```

(The line in parentheses is written by the script, which measures the deletion.) The `--name` is mandatory: without it, kind would delete the cluster called `kind`, which may belong to someone else or to another project. With the cluster goes the node's `/mnt/disco-reportes` folder and any volumes that remained: everything lived inside the nodes' containers.

What remains on your machine is the `kubeconfig` temporary folder and the two `token.txt` files. They are deleted like this, from `programas/08-datos-y-tareas`:

```bash
# Los dos tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 8.1.1.
case "$L8_TMP" in
  /tmp/curso-k8s-l8.?*) rm -rf -- "$L8_TMP" ;;
  *) echo "No borro «$L8_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L8_TMP
unset -f ctx
```

The `case` only lets through a path that starts with `/tmp/curso-k8s-l8.` and has something after it, the exact form of the one you created in 8.1.1. If `L8_TMP` is empty (for example, because you are in another terminal, where you never defined it) or has any other value, it deletes nothing and tells you why. It is the same protection `correr.sh` uses when cleaning up: an `rm -rf` that can be copied and pasted has to protect itself. If your `correr.sh` used the own network from the run notes, that network (`docker network rm curso-k8s-red-l8`) you also delete yourself, and only that one.

## How I know I made it

- [ ] You explain, with the measurement from 8.2, what survives a container crash and what does not survive the deletion of a Pod, and why.
- [ ] You tell `PersistentVolume`, `PersistentVolumeClaim` and `StorageClass` apart, and say who creates each one.
- [ ] You read `Pending` on a claim with `WaitForFirstConsumer` and know it is not an error, and you read `ProvisioningFailed` with a nonexistent class and know that it is.
- [ ] You write a `Job` with `backoffLimit` and `activeDeadlineSeconds` and say how many Pods at most it creates and with what waits.
- [ ] You read a five-field cron schedule and write the one for “every five minutes” and the one for “Monday to Friday at 7:30”.
- [ ] You say what `Forbid` does compared with `Allow` and `Replace`, and why the report task must be able to run twice.
- [ ] You trigger and fix a `Permission denied` on a volume with `fsGroup`, and say on which of the lesson's volumes `fsGroup` changed the group and on which it did not.
- [ ] You say what is lost when deleting a claim with the `Delete` policy and what with `Retain`, and why a deletion stays in `Terminating`.
- [ ] You run `programas/08-datos-y-tareas/correr.sh > /tmp/mi-corrida-l8.txt 2>&1` and compare `/tmp/mi-corrida-l8.txt` against `programas/08-datos-y-tareas/correr.salida.txt` (do not redirect to that file: it is the reference) on what does not change between runs: three `Ready` nodes at `v1.37.0`; six `not yet present on node … loading...` lines; `-rw-------` on the two `token.txt` files; in the `emptyDir`, the `2777` directory with group `65532` and a single `reporte.json` of about 92 bytes in one of the three replicas (93 if the measured time has two digits); `RESTARTS 1` and `Error 137` after stopping the container, with the file intact; the volume folder that no longer exists after deleting the Pod; the `standard (default)` class with `rancher.io/local-path`, `Delete` and `WaitForFirstConsumer`; `No resources found` in `kubectl get pv`; the `Pending` claim with the event `waiting for first consumer to be created before binding`; the `salud` Job with `Complete` and `{"estado":"vivo","version":"1.6.0"}`; the task Pod `Pending` with a nominated node and the `Provisioning` event (`ProvisioningSucceeded` arrives an instant later and may or may not land in the capture); the claim `Bound`, `100Mi`, `RWO`, `standard`; the volume tied to a node, with the path `/var/local-path-provisioner/pvc-…_revisor_reportes` and permission `777 0:0`; one `reporte-…Z.json` file in the first task and two in the second; CronJob Jobs named `<cronjob>-<number>` with eight digits and the `cronjob-scheduled-timestamp` annotation at `:00`; `Permission denied` and `755 0:0` without `fsGroup`, `Completed` and `2775 0:101` with it; `Released` with `Retain`; `Terminating` with the `kubernetes.io/pvc-protection` finalizer until the Jobs are deleted; `BackoffLimitExceeded` with three Pods in `Error`, code `28`; `150000000` bytes written to a `100Mi` volume; `ProvisioningFailed … "rapido" not found`; the three `revisor` replicas on a single node; `JobAlreadyActive … concurrency policy is Forbid`; and `sin diferencias con los archivos`. The IPs, the name suffixes, the `uid`s, the ages, the node that receives the volume, the exact seconds, each `pvc-…` identifier and the files' time change on every run: they are observed, not compared.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l8`.

## Summary

Answer without looking at the lesson:

1. What survives a container crash and what does not survive the deletion of a Pod, in an `emptyDir`?
2. What role does each of these three objects have: `PersistentVolume`, `PersistentVolumeClaim`, `StorageClass`?
3. Why does the `reportes` claim stay `Pending` when you apply it, and when does it stop being so?
4. What does `ReadWriteOnce` mean, and what consequence does it have on where the Pods that use the volume can run?
5. How is a `Job` similar to and different from a Deployment?
6. How many Pods at most does a Job with `backoffLimit: 2` create, and with what waits between them?
7. What do the five fields of `*/5 * * * *` say? In what time zone do they run if you do not set `timeZone`?
8. What does `concurrencyPolicy: Forbid` do and what event does it leave?
9. What does it mean for a task to be idempotent, and why does it matter in a CronJob?
10. What does `fsGroup` do, on which of the lesson's volumes did it change something and on which not?
11. Why can a claim stay `Terminating`? How is it resolved without forcing anything?
12. What is the difference between `Delete` and `Retain`?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, “Persistent Volumes”](https://kubernetes.io/docs/concepts/storage/persistent-volumes/): the definitions of `PersistentVolume` and `PersistentVolumeClaim`; static and dynamic provisioning; one-to-one binding and that a claim without a matching volume waits indefinitely; storage object in use protection and its definition of “in use”; the `Retain` and `Delete` reclaim policies; the `Bound` and `Released` phases; the access modes and the definition of `ReadWriteOnce` (one node, several Pods).
- [Kubernetes, “Storage Classes”](https://kubernetes.io/docs/concepts/storage/storage-classes/): what a class is; the default class; the default reclaim policy (`Delete`); the `Immediate` binding mode versus `WaitForFirstConsumer`.
- [Kubernetes, “Volumes”](https://kubernetes.io/docs/concepts/storage/volumes/): `emptyDir` (created when the Pod is assigned to a node, deleted when the Pod is removed, survives a container crash, the default `0777` permission) and the `local` volume (static only, mandatory `nodeAffinity`).
- [Kubernetes, “Jobs”](https://kubernetes.io/docs/concepts/workloads/controllers/job/): the definition of Job; `restartPolicy` `Never` or `OnFailure`; `backoffLimit` (6 by default) and the exponential back-off; `activeDeadlineSeconds` and its precedence; the causes of failure (`BackoffLimitExceeded`, `DeadlineExceeded`); the terminal conditions delayed since 1.31; that the same program may start twice.
- [Kubernetes, “CronJob”](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/): the five-field cron format; the time zone and `.spec.timeZone`; `concurrencyPolicy`; the history limits (3 and 1 by default); `startingDeadlineSeconds` and the cap of 100 missed runs; `suspend`; the 52-character maximum name; the `cronjob-scheduled-timestamp` annotation since 1.32; the warning that Jobs must be idempotent.
- [Kubernetes, “Configure a Security Context for a Pod or Container”](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` and the volume's group; volumes that “support ownership management”; `fsGroupChangePolicy`.
- [Kubernetes v1.37, changelog](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.37.md): the `Unused` condition of volume claims (`PersistentVolumeClaimUnusedSinceTime`, beta and enabled since 1.37).
- [Local Path Provisioner (Rancher), README](https://github.com/rancher/local-path-provisioner): the provisioner used by kind's `standard` class; the volume as a node `hostPath` folder; that the capacity is ignored; the folder's `0777` permission; the deletion of the contents when the volume is deleted.
- [kind, “Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts): extra mounts (`extraMounts`), the way to pass storage from your machine to a kind node so that the data persists beyond the node's container.
- [Kubernetes, “StatefulSets”](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/): stable network identity and stable storage per Pod (`volumeClaimTemplates`).
- [Kubernetes, “Volume Snapshots”](https://kubernetes.io/docs/concepts/storage/volume-snapshots/): volume snapshots.
- [Kubernetes, “Resource Quotas”](https://kubernetes.io/docs/concepts/policy/resource-quotas/): `requests.storage`, the maximum total storage that the claims of a namespace can request.
- [GitLab, “Postmortem of database outage of January 31”](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): the public account, from February 2017, of a production data loss and of the backup mechanisms that were not working (a daily copy that failed silently, snapshots not enabled on the database servers, a broken replica): the reason to test backups instead of assuming them.

---

**Next:** [Lesson 9 — Scaling and updating, measuring every outage](09-escalar-y-actualizar.md)
