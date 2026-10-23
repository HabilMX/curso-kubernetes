# Lesson 4 — Configuration and secrets

Wednesday, 6:40 in the evening. Tomorrow at 8 the project's security review starts and it falls to you to prepare the repository. You open the history and there it is: three weeks ago someone added the `revisor`'s token to the Deployment manifest, in a `REVISOR_TOKEN` line, "just to test". It is no longer in today's version, but it is still in the Git history, where anyone who has cloned the repository can read it. While you think about it, another message arrives: the payments team wants the `revisor` to watch their service too, and to add it to the list the same Deployment has to be edited: there is no need to rebuild the image, but the file where the token once lived has to be touched again. Someone proposes solving the first problem with a Secret "which already comes in base64, so it's protected". It is 6:55 and you have two problems that look like one.

They are not one. The first is **where a value that must not be seen lives**; the second is **how you change a service's configuration without touching its recipe**. Kubernetes has an object for each, and this lesson teaches you to use them without believing them more than they promise: a `ConfigMap` is not secret, a `Secret` is not encrypted, and neither makes your program find out on its own that something changed.

**Time:** 2 × 45 min

**What you build:** the `revisor` configured without rebuilding the image: the list of services leaves the Deployment and lives in a `ConfigMap`; the access token lives in a `Secret` that is mounted as a file and cannot be edited; and a change to the list triggers a *rollout* on its own

**What you learn:** `ConfigMap` as environment variables (the `revisor` only reads variables) and why changing it by hand restarts nobody; `Secret` as a file, who can read it, and why base64 is not encryption; `fsGroup` and the owner of mounted files; Kustomize with `configMapGenerator` and `secretGenerator`, and the *hash* that triggers the *rollout*; immutable Secrets

**Where you are coming from.** From [Lesson 3](03-services-dns.md): the `revisor` has three replicas behind a Service called `revisor`, the test service that fails on purpose lives behind another called `prueba`, and you know how to use a debug Pod with `curl` (`depurar`) to talk to the `revisor` from inside the cluster. From [Lesson 2](02-pods-deployments.md) you bring the Deployment → ReplicaSet → Pod chain and the rule that matters here more than ever: a *rollout* happens **if and only if the Pod template changes**. And from the [Docker course](https://www.habil.mx/en/courses/docker/) you bring a habit: the `revisor`'s token is given to it by file (`REVISOR_TOKEN_ARCHIVO`), never by variable, because a variable can be read with `docker inspect`.

**What this lesson does not do.** It does not encrypt Secrets inside the cluster: that is configured on a real cluster's `kube-apiserver`, and [Lesson 10](10-proyecto-final.md) puts it on the list of what this setup is missing to be production-ready. Nor does it decide **who** can read Secrets with fine-grained permissions: here you will see that you can, and [Lesson 7](07-aislar-permisos-red.md) gives each program its own account and minimal permissions. And the cluster still cannot tell a `revisor` that has started from one that can serve; in this lesson you will see what that costs, and probes arrive in [Lesson 5](05-salud-recursos-apagado.md).

**About the runs.** All the outputs in this lesson were obtained on October 21, 2026 with `kind` v0.33.0, `kubectl` v1.37.1 (which carries Kustomize v5.8.1 inside), and the node image `kindest/node:v1.37.0` pinned by its digest, in the three-node cluster from Lesson 1, here called `curso-k8s-l4`. The machine was a Mac with an ARM processor and Docker Engine 29.2.1 inside a Linux virtual machine (Colima), **not** Linux Mint, which is the course's reference system. What changes on your Mint: the architecture, the random suffixes of Pods and ReplicaSets, the IPs, the ages, the node where each replica lands, the size `tmpfs` reports and, above all, **the token and the Secret's name**, which are new on every run (the ConfigMap's name, by contrast, should come out identical for you: `revisor-config-t6cm6872fk`). One more detail: macOS's `wc -c` pads the number with spaces on the left (`      33`) and Linux's does not (`33`). The complete walkthrough is in [`programas/04-configuracion-secretos/`](../programas/04-configuracion-secretos): `correr.sh` creates the cluster, loads the course's two images into it, leaves it as Lesson 3 ended, walks through the lesson in order, runs Exercises 1 to 3 (the 3rd, in a disposable namespace that it deletes when done), and deletes the cluster. It took 2 minutes and 43 seconds; creating the cluster and waiting for it to be ready was 42 seconds, and deleting it, 4. Its output is `correr.salida.txt`. The script generates its own token, deletes it when done, and leaves `kustomization.yaml` as it was, even if it stops halfway; and if `kind create cluster` fails, it stops right there with code 1, instead of continuing on a cluster that does not exist.

## By the end you will be able to

- Move an environment variable out of a Deployment into a `ConfigMap` and read in `kubectl describe pod` where each variable comes from.
- Demonstrate with the `revisor`'s report that changing a `ConfigMap` by hand does not change the variables of Pods that are already running, and explain why.
- Write a `kustomization.yaml` with `configMapGenerator` and `secretGenerator`, see with `kubectl kustomize` what it is going to generate, and apply it with `kubectl apply -k`.
- Predict that a change in a generated ConfigMap's content gives its name a different suffix (and that the same earlier content gives back exactly the same name), and check with `kubectl diff -k` that this name change triggers a *rollout*.
- Mount a `Secret` as a file with `defaultMode: 0440` and `fsGroup`, and locate that file on the node, in a `tmpfs`.
- Decode a Secret with `base64 -d` to demonstrate that base64 is not encryption, and change the content of an immutable Secret in the only possible way: with another Secret.
- Recognize the `permission denied` of an unreadable Secret and the `couldn't find key` of a misspelled key, and say which of the two brings the service down and why.

## The why before the how

Until Lesson 3, the list of services the `revisor` checks was written inside the Deployment, in a line `value: "prueba http://prueba:9000/ 2s"`. It works, but it mixes two things that change at different paces. The service's **recipe** (which image, how many replicas, what security) changes little and is looked after by whoever operates the cluster. The **configuration** (which services to check, with what time limit) changes often and is sometimes requested by another team. If they live in the same file, every change to the list is a change to the recipe, with its review and its risk. The [ConfigMaps documentation](https://kubernetes.io/docs/concepts/configuration/configmap/) puts it this way: a ConfigMap lets you "decouple environment-specific configuration from your container images, so that your applications are easily portable".

The token is another matter. It is not configuration that anyone wants to read: it is a key. Written in the Deployment, it travels with the manifest to Git, to every copy of the repository, and to every screen where someone runs `kubectl get deployment -o yaml`. Kubernetes has a separate object for this, the **Secret**, and this lesson shows you with real outputs what it protects and what it does not. Because the Secret has a reputation it did not earn: many people believe that, since its data appears in base64, it is encrypted. It is not, and you will check it with a single command.

And there is a third question, the subtlest: **when does the program find out that its configuration changed?** The `revisor` reads its environment variables only once, at startup. Kubernetes restarts nobody because a ConfigMap changed. If you do not see that, you will change the configuration, you will see the changed object in the cluster, and you will believe it is done, when the Pods are still working with the old list. This lesson's solution is a tool you already carry inside `kubectl`, Kustomize, and a trick so simple it looks like cheating: changing the ConfigMap's **name** every time its content changes.

The lesson has seven concept parts and then the usual sections:

1. **Configuration written in the Deployment** (4.1): the starting point.
2. **A handwritten ConfigMap** (4.2) and how it is connected to a variable.
3. **Changing a ConfigMap restarts nobody** (4.3), measured.
4. **The token as a Secret, and why as a file** (4.4).
5. **Kustomize: generators and the *hash*** (4.5).
6. **base64 is not encryption** (4.6).
7. **Changing the list triggers the *rollout*** (4.7).

This is the destination. At the end of 4.5, the `revisor` is configured from outside, and each object carries in its name the fingerprint of its content:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

## The concepts

### 4.0 The cluster, as Lesson 3 left it

This lesson uses its own cluster, `curso-k8s-l4`, with the three-node configuration from Lesson 1, freshly created. Create it like this, from the root of the course repository, with the same care you learned in Lesson 1, and load the Docker course's two images into it:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l4.XXXX)/kubeconfig"
# curso-k8s-l4 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l4 --config programas/04-configuracion-secretos/kind-curso.yaml
# Debe decir kind-curso-k8s-l4. Si dice otra cosa, no sigas.
kubectl config current-context
kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l4
# El resto de la lección se trabaja desde la carpeta de sus programas.
cd programas/04-configuracion-secretos
```

The `export` only holds in that terminal. If you open another one, repeat the `export` with the same path, or `kubectl` will talk to another cluster. And if `kind create cluster` fails, do not continue: read its message, because everything that follows would assume a cluster that does not exist.

Then what Lesson 3 left is applied to it. The files are in this lesson's programs folder: the starting Deployment, in `punto-de-partida/revisor-deployment.yaml`, and the two Services, the `prueba` Deployment, and the `depurar` Pod, unchanged. The outputs in this section are from the run of `correr.sh`, which does exactly this:

```text
$ kubectl config current-context
kind-curso-k8s-l4

$ kubectl apply -f punto-de-partida/revisor-deployment.yaml -f revisor-service.yaml -f prueba-deployment.yaml -f prueba-service.yaml -f depurar.yaml
deployment.apps/revisor created
service/revisor created
deployment.apps/prueba created
service/prueba created
pod/depurar created

$ kubectl get deployment,service
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           9s
deployment.apps/revisor   3/3     3            3           9s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/kubernetes   ClusterIP   10.96.0.1      <none>        443/TCP    46s
service/prueba       ClusterIP   10.96.199.61   <none>        9000/TCP   9s
service/revisor      ClusterIP   10.96.4.106    <none>        80/TCP     9s
```

As always, the first command asks which cluster you are talking to. In this lesson you are going to create and delete Secrets, and `kind-curso-k8s-l4` is the only answer that lets you continue. **Repeat `kubectl config current-context` before every command that changes something** (`apply`, `patch`, `delete`, `rollout restart`) and before each exercise: the script does it before each `kubectl`, and so should you. So as not to fill the lesson with identical lines, it is only shown at the points where it matters most.

### 4.1 Configuration written inside the Deployment

This is how the `revisor`'s configuration stands today:

```text
$ kubectl get deployment revisor -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
[{"name":"REVISOR_SERVICIOS","value":"prueba http://prueba:9000/ 2s"}]

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

One variable, with its value written right there (`value`). And `/api/estados` answers anyone who asks: the `revisor` has no token yet, so it does not require one. That table is your **measuring instrument** throughout the lesson. The `revisor` has no *shell*, so you cannot go in and look at its variables with `env`; but its report lists exactly the services it read from `REVISOR_SERVICIOS` at startup. If the table says `prueba` and nothing else, the `revisor` is working with that list, no matter what any object in the cluster says.

A question to keep: what would you have to do to add a service to the list? Edit this Deployment. That changes its template, so it triggers a *rollout* (the rule from Lesson 2). It works. The problem is not technical, it is about who touches what.

### 4.2 A handwritten ConfigMap

#### 4.2.1 The object

A **ConfigMap** is, according to its documentation, "an API object used to store non-confidential data in key-value pairs". The two words that matter are **non-confidential**: the same page carries a boxed warning, "ConfigMap does not provide secrecy or encryption", and sends you to use a Secret if the data is confidential. And another warning: what you store in a ConfigMap cannot exceed 1 MiB. It is for configuration, not for large files.

This is the first one, handwritten. It is a **program**: `programas/04-configuracion-secretos/fig04_01.configmap.yaml`.

```yaml
# fig04_01.configmap.yaml — Lección 4, sección 4.2: un ConfigMap escrito a mano.
# Guarda la lista de servicios que el revisor revisa, fuera del Deployment. Tiene
# un nombre FIJO (revisor-config): la sección 4.3 muestra por qué eso es un
# problema y la 4.5 lo resuelve con el generador de Kustomize.
apiVersion: v1
kind: ConfigMap
metadata:
  name: revisor-config
  labels:
    app: revisor
data:
  REVISOR_SERVICIOS: "prueba http://prueba:9000/ 2s"
```

It reads like any object: `apiVersion: v1` (the API's core group, like Pods), `kind: ConfigMap`, a name and a label. What is new is `data`: a map of keys and values, all text. Here there is a single key, `REVISOR_SERVICIOS`, and it is called the same as the variable on purpose: that way nobody has to translate between two names.

```text
$ kubectl apply -f fig04_01.configmap.yaml
configmap/revisor-config created

$ kubectl get configmap revisor-config -o jsonpath='{.data}{"\n"}'
{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s"}
```

(Before that `apply`, `kubectl config current-context` said `kind-curso-k8s-l4`.) So far the ConfigMap exists, but nobody uses it. A ConfigMap does nothing on its own: it is data stored in the cluster, waiting for a Pod to ask for it.

#### 4.2.2 From ConfigMap to variable

The documentation gives four ways of using a ConfigMap from a Pod: as arguments to the container's command, as **environment variables**, as **files** in a read-only volume, or by reading it with code that talks to the Kubernetes API. The `revisor` decides for you which one works: it only reads environment variables (`REVISOR_SERVICIOS`, `REVISOR_PUERTO`, `REVISOR_REPORTE`, and `REVISOR_TOKEN_ARCHIVO`). A file with the list would be of no use to it, because it would not look for it. That is why, in this course, **the ConfigMap goes as a variable**.

This Deployment (`fig04_02.revisor-con-configmap.yaml`, another **program**) is Lesson 3's with a single difference. Where it used to say `value: "prueba http://prueba:9000/ 2s"`, it now says where to get the value from:

```yaml
        env:
        - name: REVISOR_SERVICIOS
          valueFrom:
            configMapKeyRef:
              name: revisor-config
              key: REVISOR_SERVICIOS
```

Read it as a sentence: the variable `REVISOR_SERVICIOS` takes its value (`valueFrom`) from the key `REVISOR_SERVICIOS` of the ConfigMap called `revisor-config`. The rest of the file does not change, and you can verify it yourself with `diff punto-de-partida/revisor-deployment.yaml fig04_02.revisor-con-configmap.yaml`.

Another form exists, `envFrom`, which turns **all** of a ConfigMap's keys into variables at once. It is convenient, but it hides which variables the container receives: you would have to go look at the ConfigMap to find out. Since the `revisor` silently ignores the variables it does not know, `configMapKeyRef` is the better fit here: each variable is written out, with its name, in the Deployment.

```text
$ kubectl apply -f fig04_02.revisor-con-configmap.yaml
deployment.apps/revisor configured

$ kubectl describe pod revisor-66db8c7755-6mwlw | sed -n '/Environment:/,/Mounts:/p'
    Environment:
      REVISOR_SERVICIOS:  <set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>  Optional: false
    Mounts:

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

`configured`: the template changed, so there was a *rollout* and there are new Pods. `kubectl describe pod` shows the variable and, instead of its value, **where it comes from**: "set to the key `REVISOR_SERVICIOS` of ConfigMap `revisor-config`". `Optional: false` means that, if that ConfigMap or that key does not exist, the container does not start. You will provoke it in Exercise 1. The table stays the same as before, as it should: same list, another place.

### 4.3 Changing a ConfigMap restarts nobody

Now the scene's request: adding a service. So as not to depend on anything outside the cluster, the "new service" is the same `prueba` under another name, `lento`, and a shorter time limit, half a second. What matters is that a new row appears in the table.

Before changing anything, check the context (`kubectl config current-context` → `kind-curso-k8s-l4`) and look at the ReplicaSets. The top one is `fig04_02`'s; the bottom one, Lesson 3's, at `0 0 0`:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       3s
revisor-697fb84f97   0         0         0       12s

$ kubectl patch configmap revisor-config -p '{"data":{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms"}}'
configmap/revisor-config patched
(30 s después)
```

`kubectl patch` changes only the fields you give it. Here it gave the key a list with two services separated by a comma. The cluster says `patched`: the ConfigMap changed. Thirty seconds later:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       34s
revisor-697fb84f97   0         0         0       43s

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           4ms  200
```

Not a single new ReplicaSet, and the table still says only `prueba`. **The ConfigMap changed and the `revisor` did not find out.** It is not a delay that waiting fixes: it will stay like this until the Pod is reborn.

The reason has two halves, and it is worth seeing both.

**Kubernetes' half.** An environment variable is fixed when the container starts. That is how variables work in Linux: the process receives its environment at birth and nobody changes it afterwards from outside. The ConfigMaps documentation says it bluntly: "ConfigMaps consumed as environment variables are not updated automatically and require a pod restart". And the Deployment has no reason to restart anything: its template says "take the variable from the ConfigMap `revisor-config`", and that did not change. What changed was the ConfigMap's content, not the template, so Lesson 2's "if and only if" rule is not met. There is no *rollout*.

**The `revisor`'s half.** Even if Kubernetes could change the variable for it, it would not help: the `revisor` reads its configuration only once, at startup. Its code (`cmd/revisor/config.go`, from the Docker course) builds the list in a function that is called at the beginning and never again.

And if the ConfigMap were mounted as a file? The documentation says that then it does update on its own, "eventually", with the `kubelet`'s sync delay. But that only helps a program that reads the file again, and the `revisor` does not. Many real programs do not either. That is why the right question is never "did the ConfigMap change?", but "is the program already running with the new configuration?". And that question is answered with the program, not with the ConfigMap: here, with the table.

The manual way out is the one from Lesson 2:

```text
$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
lento     OK           1ms  200
prueba    OK           2ms  200

$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>
```

Now it does: two services. `rollout restart` added the `restartedAt` annotation to the template, the template changed, and the new Pods read the new list at birth. Revision 3.

It works, but it depends on someone **remembering** to restart. And notice what is not recorded anywhere: the Deployment's history says there were three revisions, but none says the third was due to a change of the list. If tomorrow someone runs `rollout undo` to go back to revision 2, it goes back to revision 2's template, which points to the same ConfigMap `revisor-config`… which already has the new list. There is no way to go back to the old configuration, because the old configuration no longer exists. Section 4.5 solves both things with a single idea.

### 4.4 The token: a Secret, and as a file

#### 4.4.1 What a Secret is

A **Secret**, according to its [documentation](https://kubernetes.io/docs/concepts/configuration/secret/), is "an object that contains a small amount of sensitive data such as a password, a token, or a key". It is very similar to a ConfigMap: it is also a map of keys and values, it also has a cap of 1 MiB, and it is also used as a variable or as a file. The differences are in the treatment the cluster gives it:

- **It only travels to the nodes that need it.** A Secret is sent to a node only if a Pod on that node asks for it.
- **On the node, if you mount it as a file, it lives in memory.** The `kubelet` keeps the copy in a `tmpfs`, a file system in RAM, "so the confidential data is not written to durable storage"; and deletes it when the Pod that used it goes away. That protection belongs to the volume: if the Secret is consumed as an environment variable, there is no `tmpfs` involved, because the value travels in the process definition that the runtime receives. You will see the `tmpfs` in 4.5.6.
- **It can be treated separately in permissions.** An RBAC rule (Lesson 7) can allow reading ConfigMaps and not Secrets.

And one thing it does **not** do: encrypt. The same page opens with a boxed warning worth reading in full: "Kubernetes Secrets are, by default, stored unencrypted in the API server's underlying data store (etcd). Anyone with API access can retrieve or modify a Secret, and so can anyone with access to etcd. Additionally, anyone who is authorized to create a Pod in a namespace can use that access to read any Secret in that namespace". Section 4.6 puts it to the test.

#### 4.4.2 The token is generated, not written

The `revisor`'s token is not a value that is chosen, nor one that is copied from a document. It is generated, at random, every time a new one is needed:

```text
$ (umask 077; openssl rand -hex 16 > token.txt)

$ ls -l token.txt | cut -d' ' -f1
-rw-------

$ wc -c < token.txt
      33

$ cat .gitignore
token.txt

$ git check-ignore -v token.txt
programas/04-configuracion-secretos/.gitignore:1:token.txt	token.txt
```

`openssl rand -hex 16` asks for 16 random bytes and writes them in hexadecimal: 32 characters, plus the line break it adds at the end. That is why `wc -c` counts 33. The parentheses and the `umask 077` change the permission mask **only for that command**: the file is born with permission `0600` (`-rw-------`), which only you can read, instead of the `0644` that your usual mask would leave, readable by any user on the machine. It is the same token that inside the Pod will have `0440`: it is looked after the same on your machine as in the cluster. That line break is no obstacle: the `revisor`, when reading the file, strips the whitespace and line breaks at its edges (`strings.TrimSpace`, in its code).

The last two commands are this lesson's habit. `.gitignore` says that `token.txt` does **not** go into the repository, and `git check-ignore -v` confirms it, saying which file and which line exclude it. The scene began with a token in the Git history, and this is the way to keep it from happening again: the file exists on your machine, the cluster receives it, and Git never sees it. If you work outside a repository, `git check-ignore` will tell you it is not a repository; the rule still holds for the day it is.

#### 4.4.3 Why as a file and not as a variable?

A Secret can be passed as an environment variable (with `secretKeyRef`, twin of `configMapKeyRef`). This course does not do it, and not out of whim:

- **A variable is inherited.** Every process the container launches receives a copy of its environment. A file is not copied to each child process: it has to be opened on purpose, and only someone with permission can open it.
- **A variable gets printed by accident.** In an error dump, in a debugging `env`, in the log of a program that, when failing, writes "I started with this configuration". The [Secrets good practices guide](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) asks each application, after reading the Secret, to avoid "logging the secret data in clear text".
- **The `revisor` itself asks for it.** If it receives the token in `REVISOR_TOKEN`, it starts, but writes a warning in its log: `el token llegó por REVISOR_TOKEN: cualquiera con docker inspect lo puede leer; usa REVISOR_TOKEN_ARCHIVO`. The program itself has already taken a side.

So the `revisor` receives two things: the Secret mounted as a file at `/secretos/token`, and a normal, non-secret variable that tells it where to look: `REVISOR_TOKEN_ARCHIVO=/secretos/token`. The path is not a secret; the content is.

### 4.5 Kustomize: generators and the *hash*

#### 4.5.1 The idea: the name changes when the content changes

Recall the two problems from 4.3: the ConfigMap change did not trigger a *rollout*, and there was no way to go back to the old configuration. Both come from the same place: the ConfigMap has a **fixed name**, so the Deployment's template never changes, even though what is inside changes.

Now imagine the ConfigMap were named differently according to its content: `revisor-config-t6cm6872fk` with one list, `revisor-config-7fbkh2926f` with another. Changing the list would create **another** ConfigMap, and the Deployment would have to point to the new name. Its template would change, and Lesson 2's rule would do the rest: *rollout*. And the old ConfigMap would still be there, intact, for an old revision of the Deployment to point to. That has a cost: Kustomize does not delete the old ones, so they pile up. In the course it does not matter, because in the end you delete the whole cluster; in one that lives for months, you would have to clean up by hand (`kubectl delete configmap <name>`) those that no revision keeps anymore, and the same with Secrets.

Doing that by hand would be torture: computing a name, writing it in two places, never making a mistake. That is what **Kustomize** is for, which comes inside `kubectl` since version 1.14 (`kubectl kustomize` and `kubectl apply -k`); in this course it is v5.8.1, the one that comes with `kubectl` v1.37.1. The [Kustomize guide](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) explains it in one sentence: the generated ConfigMaps and Secrets "have a name suffix appended by hashing the contents. This ensures that a new ConfigMap or Secret is generated when the contents are changed". And Kustomize does not just generate the name: it knows the fields of Kubernetes objects that point to a ConfigMap or a Secret (`configMapKeyRef`, `secretKeyRef`, `envFrom`, the `volumes`) and puts the new name in them. It is not a text replacement: a mention of `revisor-config` in an annotation or in a field of an extended resource is not updated on its own.

#### 4.5.2 The `kustomization.yaml`

Kustomize reads a file called `kustomization.yaml` in a folder. This is the lesson's, a **program**:

```yaml
# kustomization.yaml — Lección 4. Se aplica con: kubectl apply -k .
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
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

Three blocks:

- **`resources`**: the manifests you already know, as they are. Kustomize reads them, adjusts them, and hands them over together. `depurar.yaml` is not on the list on purpose: it is a debugging tool, not part of the service.
- **`configMapGenerator`**: "generate a ConfigMap called `revisor-config`, with this key and this value". `literals` is for values written right there, in the form `KEY=value`. The list of services is no longer in the Deployment: it is here, on a line that can be reviewed on its own.
- **`secretGenerator`**: "generate a Secret called `revisor-token`, with a key `token` whose content is that of the file `token.txt`". The form `token=token.txt` separates the key's name (on the left) from the file it comes from (on the right). Without the `token=`, the key would be named like the file, `token.txt`. And `options: immutable: true` marks the Secret as immutable; the "security habit" section explains why.

Notice what is **not** in this file: the token. The `kustomization.yaml` does go into the repository, and it only says where to get it from.

#### 4.5.3 The final Deployment

The lesson's Deployment is `revisor-deployment.yaml`, a **program**. Compared with `fig04_02`, three things change: the token mounted as a file, the variable that says where it is, and a new line in the Pod's `securityContext`:

```yaml
# revisor-deployment.yaml — Lección 4: la configuración llega de un ConfigMap
# (por variable) y el token de un Secret (por archivo, inmutable).
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

Walk through it from the bottom up, following the token's journey:

- **The `token` volume**, of type `secret`, takes the Secret `revisor-token` and turns each key into a file. The Secret has one key, `token`, so the volume will have one file, `token`.
- **`defaultMode: 0440`**: the permissions of that file. `0440` in octal is "the owner can read, the group can read, others nothing, and nobody writes". If you do not set it, the [guide to distributing credentials](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) says `0644` is used, which lets everyone read. There are no other users inside the container here, but the minimum permission costs nothing.
- **The mount** puts that volume at `/secretos`, with `readOnly: true`. That way, the file ends up at `/secretos/token`.
- **The variable `REVISOR_TOKEN_ARCHIVO`** tells the `revisor` that path. It is a normal `value`: the path is not secret.
- **`fsGroup: 65532`**, at the top, in the Pod's `securityContext`. It is the shortest line and the hardest to understand, so it has its own explanation in 4.5.6.

Notice `name: revisor-config` and `secretName: revisor-token`: here they go **without** the *hash*. You write them like this, with the base name, and Kustomize changes them to the generated name when assembling the result. If you wrote the name with the *hash*, you would have to change it by hand on every change of the list, which is exactly what was meant to be avoided.

#### 4.5.4 Seeing before applying

`kubectl kustomize .` assembles the result and prints it, **without** touching the cluster. It is the way to see what is going to happen:

```text
$ kubectl kustomize . | grep -E '^  name: revisor-(config|token)'
  name: revisor-config-t6cm6872fk
  name: revisor-token-bh266kt42m

$ kubectl kustomize . | grep -B4 -A3 '^kind: Secret'
apiVersion: v1
data:
  token: NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK
immutable: true
kind: Secret
metadata:
  name: revisor-token-bh266kt42m
type: Opaque
```

There are the generated names: `revisor-config-t6cm6872fk` and `revisor-token-bh266kt42m`. The ConfigMap's suffix depends only on its content, so on your machine the same one should come out, `t6cm6872fk`. The Secret's depends on the token, which is new on every run; yours will be another.

And there is the Secret as the cluster will receive it. `type: Opaque` is the generic type, "arbitrary data". `immutable: true` comes from the `options`. And in `data`, the key `token` with a value that does not look like your token. Keep that string: in 4.6 you are going to take it apart.

#### 4.5.5 Applying

Check the context and apply:

```text
$ kubectl config current-context
kind-curso-k8s-l4

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

`apply -k .` is `apply` with Kustomize: it assembles the folder and applies the result. Kustomize orders the objects so that the ConfigMap and the Secret are created **before** the Deployment that uses them. The Services and `prueba` did not change (`unchanged`). The `revisor` did (`configured`): its template now points to new names and mounts a new volume.

Now look at what is left in the cluster. For Secrets a **field selector** (`--field-selector`) is used, which filters by a field of the object and not by its labels: `type!=kubernetes.io/service-account-token` leaves out Secrets of the "service account token" type, if there were any, so you see only yours:

```text
$ kubectl get configmap
NAME                        DATA   AGE
kube-root-ca.crt            1      77s
revisor-config              1      41s
revisor-config-t6cm6872fk   1      4s

$ kubectl get secret --field-selector type!=kubernetes.io/service-account-token
NAME                       TYPE     DATA   AGE
revisor-token-bh266kt42m   Opaque   1      4s

$ kubectl delete configmap revisor-config
configmap "revisor-config" deleted from default namespace
```

Three ConfigMaps. `kube-root-ca.crt` is put by Kubernetes in every namespace, with the cluster's certificate; it is not yours. `revisor-config-t6cm6872fk` is the generated one. And `revisor-config`, the one you wrote by hand in 4.2, **is still there**. `kubectl apply` creates and updates what you give it; it does not delete what you do not give it. Nobody uses it anymore, so it was deleted by hand. Remember this in 4.7 and in Exercise 2: every change leaves the previous object behind.

Now the Pod from the inside:

```text
$ kubectl describe pod revisor-f6dd4cb4d-cg7tb | sed -n '/Environment:/,/Conditions:/p'
    Environment:
      REVISOR_SERVICIOS:      <set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config-t6cm6872fk'>  Optional: false
      REVISOR_TOKEN_ARCHIVO:  /secretos/token
    Mounts:
      /datos from datos (rw)
      /secretos from token (ro)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-2gqd7 (ro)
Conditions:
```

`config map 'revisor-config-t6cm6872fk'`: the Deployment now points to the name with the *hash*, even though in your file you wrote `revisor-config`. Kustomize changed it when assembling. And in `Mounts`, `/secretos from token (ro)`: the Secret mounted, read-only. The third mount is the service account credential that Lesson 2 recorded as debt; Lesson 7 removes it.

And the `revisor`? It now has a token, so it requires one:

```text
$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' http://revisor/api/estados
401

$ kubectl exec depurar -- curl -s http://revisor/api/estados
{"error":"falta el token o no es válido"}

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200

$ kubectl exec deployment/revisor -- /revisor healthcheck
sano
```

Without a token, `401` and a clear message. With the `Authorization: Bearer …` header, the table. Notice the quotes in the third command: `$(cat token.txt)` is between double quotes, so your *shell* substitutes it **on your machine**, before sending the command to the Pod. The token never appears written in your command history, only the `cat`. It does appear, while the command runs, as a process argument: in a `ps` on your machine and inside `depurar`. For a local exercise that is enough; on a shared cluster, the token is not passed on the command line. And `/salud` (the one `healthcheck` queries) asks for no token, on purpose: the probes in Lesson 5 will call it without credentials.

The table went back to saying only `prueba`, and that is also correct: the list in the `kustomization.yaml` has a single service. The `lento` that you added by hand in 4.3 lived in the ConfigMap you just deleted.

#### 4.5.6 The Secret, seen from the node

Where is the file `/secretos/token` physically? The `revisor` has no *shell* to go look at it, but the kind node does, and the `kubelet` keeps each Pod's volumes in a folder with the Pod's identifier (`uid`). For this Pod, on the node `curso-k8s-l4-worker`:

```text
$ docker exec curso-k8s-l4-worker ls -ln /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 65532 33 Oct 21 13:27 token

$ docker exec curso-k8s-l4-worker sh -c 'mount | grep a415d22b-9837-4123-a7d9-82b1baf9435a | grep -E "secret/token "'
tmpfs on /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token type tmpfs (rw,relatime,size=16342676k,inode64,noswap)
```

The node's name and the Pod's `uid` come from `kubectl get pod <pod> -o jsonpath='{.spec.nodeName}'` and `'{.metadata.uid}'`; the script finds them on its own. Two things to check with your own eyes:

- **`-r--r----- 1 0 65532 33 … token`**: the file has the `0440` permissions you asked for (`r--r-----`), is 33 bytes (your token with its line break), its owner is user `0` (`root`), and its group is **65532**. That group was set by `fsGroup`.
- **`tmpfs`**: the volume's folder is a file system in memory, as the documentation promises. The token was not written to the node's disk.

The `..data` folder is a detail of how the `kubelet` updates Secret volumes: the `token` file the container sees is a link to `..data/token`, and when the Secret changes, the `kubelet` prepares a new folder and switches the link in one stroke. With an immutable Secret, like this one, that will never happen.

Now put the `ls` line together with the `securityContext`. The `revisor` runs as user 65532 and group 65532. The file belongs to `root` and to group 65532, with read permission for the group. The `revisor` reads it **by belonging to the group**. Without `fsGroup`, the file's group would be another and the `revisor` would have no way to read it. The [`securityContext` guide](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) describes `fsGroup` this way: the container's processes become part of that group as a supplementary group, and "volumes that support ownership management are modified to be owned and writable by the GID specified in `fsGroup`". The section "The error you will see" shows you what happens if you skip it, and it is not what you would expect.

### 4.6 base64 is not encryption

Take the string you saw in the Secret and the one from the cluster:

```text
$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}{"\n"}'
NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK

$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}' | base64 -d
433c7adfa6fc6fc3d03676b7f5c2339e

$ cat token.txt
433c7adfa6fc6fc3d03676b7f5c2339e
```

(The `grep revisor-token | xargs` finds the Secret even though its name changes on every run.) One command, no key, no password, nothing to guess: `base64 -d` returns the complete token, identical to the file. **base64 is not encryption.** It is an **encoding**: a way of writing any sequence of bytes using only letters, numbers, `+`, and `/`, plus a padding `=` at the end when needed (like the `eA==` further on), so that it fits in a text file such as a YAML. Encrypting means that, without a key, it cannot be read. Encoding means that it can be read with a public table. The good practices guide says it in one line: "base64 encoding is **not** an encryption method; it provides no additional confidentiality over plain text". And it warns about the scene's mistake: if you store a Secret manifest in a repository, "the secret is exposed to everyone who can read the manifest".

Why does base64 exist, then? Because a Secret can store anything, binary data too, like a certificate or a key, and a YAML is text. base64 is the envelope that lets you put bytes into a text file. It is not a safe.

Who can do what you just did?

```text
$ kubectl auth can-i get secrets
yes
```

`kubectl auth can-i` asks the cluster whether **you** can do something, without doing it. You can, because the `kubeconfig` kind gave you is an administrator's. On a real cluster, RBAC controls that, and Lesson 7 practices it. But the Secrets documentation warns about a back door: whoever can create a Pod in a namespace can mount any Secret of that namespace in it and read it from inside, even without permission for `get secrets`. That is why a service's Secrets live in that service's namespace, and not in one shared with others (Lesson 7).

And one more, which cannot be seen from here: inside the cluster, the Secret is stored in `etcd` **unencrypted**, unless the administrator enables encryption at rest in the `kube-apiserver`. The good practices guide puts it as the first recommendation: "you should configure encryption at rest for Secret data in etcd". In kind it is not done; Lesson 10 notes it in the list of what is missing for production.

What a Secret does give you, compared with writing the token in the Deployment, is this: the token is not in your manifest or in Git; it travels only to the nodes that use it and lives in memory there; and permission to read Deployments can be granted without granting permission to read Secrets. That is quite a lot. It just is not encryption.

### 4.7 Changing the list triggers the *rollout*

Now yes, the scene's request, with the complete tool. Before the change, the `revisor`'s ReplicaSets (four revisions: Lesson 3's, `fig04_02`'s, the `rollout restart` one, and the `apply -k` one):

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   0         0         0       43s
revisor-697fb84f97   0         0         0       52s
revisor-99546b58f    0         0         0       9s
revisor-f6dd4cb4d    3         3         3       6s
```

The change is made **in the `kustomization.yaml`**, not in the cluster (and before applying it, again `kubectl config current-context`). Open the file and add the service at the end of the list, separated by a comma:

```text
$ grep REVISOR_SERVICIOS kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
```

Before applying, ask the cluster what would change. `kubectl diff -k .` compares what Kustomize would assemble with what is in the cluster; here it was filtered to show only the lines that matter:

```text
$ kubectl diff -k . | grep -E '^[-+] .*(REVISOR_SERVICIOS|name: revisor-config)'
-              name: revisor-config-t6cm6872fk
+              name: revisor-config-7fbkh2926f
+  REVISOR_SERVICIOS: prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
+  name: revisor-config-7fbkh2926f
[código de salida: 1]
```

Read it line by line. The first two are the **Deployment**'s: its reference goes from `revisor-config-t6cm6872fk` to `revisor-config-7fbkh2926f`. The last two are of a **new ConfigMap**, with the new list and the new name. Those first two lines are the *rollout*, announced before it happens: the Pod template changes. (The exit code 1 comes from `kubectl diff`, which is how it warns that it **did** find differences. It is not an error.)

With the same content, the same name: your `7fbkh2926f` must be identical to this one. Applying:

```text
$ kubectl apply -k .
configmap/revisor-config-7fbkh2926f created
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

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
revisor-66db8c7755   0         0         0       46s
revisor-697fb84f97   0         0         0       55s
revisor-769ff55c9c   3         3         3       3s
revisor-99546b58f    0         0         0       12s
revisor-f6dd4cb4d    0         0         0       9s

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
lento     OK           1ms  200
prueba    OK           1ms  200
```

A new ConfigMap (`created`), the Secret unchanged (`unchanged`: the token did not change, nor did its name), a new ReplicaSet, `revisor-769ff55c9c`, which took over the three replicas in turns, and the table with two services. **Nobody had to remember to restart anything.** It is the course's goal 4: you change the list, apply with `kubectl apply -k .`, and the cluster does the *rollout* on its own, without rebuilding the image and without you having to remember to restart the Deployment. Nothing watches your files: without the `apply`, the cluster does not even find out that you changed the list.

And going back, which in 4.3 was impossible, here is trivial. The `kustomization.yaml` was returned to its original list and applied:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

`revisor-config-t6cm6872fk unchanged`: the original list's ConfigMap **never went away**. Kustomize computed the same name for the same content, the Deployment pointed to it again, and its template was identical once more to that of the ReplicaSet `revisor-f6dd4cb4d`. Each configuration has its own object, and each Deployment revision points to its own.

The price of this you already saw in 4.5.5: `revisor-config-7fbkh2926f` stayed in the cluster, with nobody using it. Over time they pile up. It is a small price (each weighs a few bytes) and it is paid in exchange for being able to go back; the orderly way to clean them up is part of what Lesson 10 leaves for a real cluster.

## The error you will see

This lesson's error appears right when you think you are done: the Secret exists, the mount is correctly written, the path is correct… and the `revisor` does not start. It was provoked on purpose by removing the `fsGroup` line from the Deployment with a `patch`, after checking the context:

```text
$ kubectl patch deployment revisor --type=json -p='[{"op":"remove","path":"/spec/template/spec/securityContext/fsGroup"}]'
deployment.apps/revisor patched
```

(`--type=json` allows precise operations such as `remove`, on an exact path of the object. It is the way to remove **one** line without rewriting the file.) Twenty-five seconds later, it is read in the usual order.

**First, the status.**

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS   RESTARTS      AGE
revisor-7ffcfb7646-2lsmc   0/1     Error    2 (23s ago)   24s
revisor-7ffcfb7646-k4s2b   0/1     Error    2 (23s ago)   25s
revisor-7ffcfb7646-th42g   0/1     Error    2 (24s ago)   25s
```

`Error` and `RESTARTS 2`: the container **did start**, and the program ended with an error; the `kubelet` restarted it and it ended again. It is a different state from those in Lesson 2. It is not `ImagePullBackOff` (the image is there) nor `CreateContainerConfigError` (the configuration could be built). It is the program that crashes. In a few more seconds, the status turns into `CrashLoopBackOff`: the [Pod lifecycle documentation](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) explains that the `kubelet` restarts with a growing wait (10 s, 20 s, 40 s…) up to a cap of 300 s, and that `CrashLoopBackOff` is the name of that wait. `Error` and `CrashLoopBackOff` alternate: one is "it crashed", the other is "I wait before trying again".

**Second, the `logs`**, because if the program started, the program has something to say:

```text
$ kubectl logs revisor-7ffcfb7646-2lsmc
revisor: leyendo el token de REVISOR_TOKEN_ARCHIVO: open /secretos/token: permission denied
```

One line, and it says it all: the `revisor` went to read the file that `REVISOR_TOKEN_ARCHIVO` pointed it to, the operating system denied it permission (`permission denied`), and the `revisor` refused to start without its token. That "refusing" is a decision in its code, and it is the right one: a `revisor` that started without a token would leave `/api/estados` open to anyone.

Why could it not read it? Look at it on the node, just like in 4.5.6, now for one of the Pods that fail:

```text
$ docker exec curso-k8s-l4-worker2 ls -ln /var/lib/kubelet/pods/c26f312f-6841-4911-bea8-6f14513b4a11/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 0 33 Oct 21 13:28 token
```

Compare it with 4.5.6's, `-r--r----- 1 0 65532`. The permissions are the same, `0440`, and so is the owner, `root`. What changed is the **group**: with `fsGroup` it was 65532 and the `revisor` read it by belonging to the group; without `fsGroup` it is `0`, `root`'s. User 65532 is neither the owner nor in the group, and for it `0440` means "nothing".

**Third, `describe`**, to confirm who is speaking:

```text
$ kubectl describe pod revisor-7ffcfb7646-2lsmc | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  24s                default-scheduler  Successfully assigned default/revisor-7ffcfb7646-2lsmc to curso-k8s-l4-worker2
  Normal   Pulled     11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container image "curso-docker-revisor:1.6.0" already present on machine and can be accessed by the pod
  Normal   Created    11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container created
  Normal   Started    11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container started
  Warning  BackOff    10s (x2 over 22s)  kubelet            spec.containers{revisor}: Back-off restarting failed container revisor in pod revisor-7ffcfb7646-2lsmc_default(c26f312f-6841-4911-bea8-6f14513b4a11)
```

All `Normal` up to `Started`, three times (`x3`): the image was there, the container was created and started. The only `Warning` is `BackOff`, "I wait before restarting the container that failed". The events do not say **why** it failed, because the cluster does not know: the program crashed on its own. That is why, when the container did manage to start, the `logs` come before the `describe`. In Lesson 2, with `ImagePullBackOff`, it was the other way around: there was no program to speak, and the answer was in the events.

**And now what you did not expect:**

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   0/3     3            0           83s
```

`0/3`. **Not a single healthy replica is left.** In Lesson 2's Exercise 3, a broken image left the *rollout* stuck with the service intact: three old Pods alive and one new one failing. Here, the three old Pods are gone. What changed, if the strategy is the same (`maxSurge` 1, `maxUnavailable` 0)?

The difference is **when** the new Pod fails. With the broken image, the container never started, so the Pod was never ready and the Deployment never removed an old one. Here, the container **does** start, and lives a few milliseconds before reading the token and crashing. For the Deployment, that is enough. Without a probe asking "can you serve yet?", Kubernetes considers a container ready as soon as it starts. The [Deployments documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) defines when a new Pod counts as available: when it is ready, with none of its containers crashing, for at least `minReadySeconds`, which by default is **zero**. Each new Pod was "ready" for an instant, the Deployment counted it and removed an old one. In this run it happened three times, and the three Pods that remained do not work. How far the change advances depends on how many new Pods manage to count as ready before crashing: in a repetition of this same experiment, the *rollout* stopped halfway, with two healthy old Pods and `AVAILABLE 2`, and `kubectl rollout status` timed out with `error: timed out waiting for the condition`. What does not change is the cause. And in no case would `kubectl rollout status` have said `successfully rolled out` with `AVAILABLE 0`: that message requires all replicas to be available. The damage was already done before the command could warn.

This is the most important point of the section, and it is not a defect of Kubernetes: **the cluster only knows what you teach it to ask.** A `revisor` that starts is not a `revisor` that can serve. Lesson 5 gives the Deployment a readiness probe, and with it this same error leaves three old replicas alive, as in Lesson 2.

**The way out** is the usual one in this course: the file is the truth, and you apply it again.

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
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
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

`apply -k` put the `fsGroup` line back and the template went back to what it was before the `patch`. Notice that the *rollout* back was also in turns: this time, yes, the new Pods read the token, stay alive, and the Deployment advances over Pods that work.

**The order, for a Pod that starts and crashes:** the status (`get pods`: `Error` or `CrashLoopBackOff`, with `RESTARTS` going up), the `logs` (what the program said before crashing; if the container has already restarted, `kubectl logs --previous` shows those of the previous attempt) and, at the end, the `describe`. And before concluding that "nothing serious happened", `kubectl get deployment`: how many replicas are **really** serving.

## The security habit of the lesson: the Secret is not versioned, is mounted as a file, and is marked immutable

The course's habits table assigns this lesson three rules about the Secret. You have already seen all three working; here they are together, with what each protects against.

**It is not versioned.** The token lives in `token.txt`, which `.gitignore` keeps out of the repository, and the `kustomization.yaml` only says where to read it from. What goes to Git is the recipe, never the value. It is the direct answer to the scene: a secret that enters Git once stays in the history forever, even if you delete it in the next version, and the only real repair is to change it.

**It is mounted as a file**, with `defaultMode: 0440`, `readOnly: true`, and `fsGroup` so that only the `revisor`'s group reads it. Living in a `tmpfs`, it does not touch the node's disk. And it is not inherited by other processes or shown in a listing of variables.

**It is marked immutable.** With `immutable: true`, the cluster refuses to change the Secret's content:

```text
$ kubectl get secret -o name | grep revisor-token | xargs -I{} kubectl patch {} -p '{"data":{"token":"eA=="}}'
The Secret "revisor-token-bh266kt42m" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]
```

`eA==` is the letter `x` in base64: the attempt was to change the token to a single letter. The `kube-apiserver` rejected it before storing it: "forbidden: the field is immutable when `immutable` is set". The [Secrets documentation](https://kubernetes.io/docs/concepts/configuration/secret/) gives two reasons to use it. The first, that it protects you from "accidental (or unwanted) updates that could cause applications outages". The second is about performance: the `kubelet` does not need to watch immutable Secrets, and on a cluster with thousands of them that takes load off the `kube-apiserver`. And a warning you need to know: the mark **cannot be undone**. "Once a Secret or ConfigMap is marked as immutable, it is not possible to revert this change nor to mutate the contents of the `data` field. You can only delete and recreate the Secret".

So how is the token changed? With **another** Secret. And that, with Kustomize, you already have: a new token gives a new *hash*, a new name, and the Deployment moves to mounting the new Secret with a *rollout*. No Pod sees its file change halfway; each Pod is born with one token and dies with it. Exercise 2 does it. The generator and the immutable mark are made for each other: the generator never wants to modify a Secret, it always creates another.

**What it protects against and what it does not.** These three rules look after the token **outside** the cluster (Git) and **on the node** (memory, permissions). They do not look after it **inside** the `kube-apiserver`: whoever has permission to read Secrets, or to create Pods in the namespace, reads it with `base64 -d`, as you did in 4.6. That is defended by permissions (Lesson 7) and by encryption at rest on a real cluster (Lesson 10).

## Common mistakes

**Believing that base64 protects anything.** It is an encoding, not encryption. A Secret manifest with its `data` in a repository is the secret published. You saw it in 4.6: one `base64 -d`.

**Versioning the Secret "so the cluster rebuilds itself".** What gets rebuilt is what is in Git, and that includes whoever should not have seen the token. The token is generated or brought from a place made for storing secrets (a secrets manager, on a real cluster), and Git stores only where to get it from.

**Changing a ConfigMap by hand and assuming the program already knows.** If the program reads it as a variable, it does not find out until the Pod is reborn. You measured it in 4.3: the ConfigMap said two services and the `revisor` kept reporting one. The proof that a change arrived is the program's behavior, not the object.

**Writing the name with the *hash* in the Deployment.** `name: revisor-config-t6cm6872fk` written by hand stops working at the next change of the list. You write the base name and Kustomize translates it.

**Turning off the *hash* so the name looks clean.** `disableNameSuffixHash: true` exists, and it takes you back to the problem in 4.3: the content change does not change the template, and there is no *rollout*. You will check it in Exercise 3.

**Giving the token as an environment variable "because it's easier".** It is inherited, it gets printed by accident, and the `revisor` itself warns you in its log not to do so.

**Removing `fsGroup`, or setting `defaultMode: 0444`, "so it can read it".** `fsGroup` is the right way for the `revisor` to read the file **by belonging to its group**. Opening the file to everyone works, but you give up the minimum permission. And if you remove `fsGroup` without understanding, you have seen what it costs.

**Believing that a *rollout* in progress protects your service.** Without probes, the Deployment counts as ready a Pod that has barely started and removes a healthy old Pod for each new one, even though the new one crashes when reading its configuration. Before taking anything as good, `kubectl get deployment` (check that `AVAILABLE` equals the desired replicas) and a real request.

**Forgetting that `apply` does not delete.** Every change with generators leaves the previous ConfigMap or Secret behind, and a handwritten ConfigMap that nobody uses anymore also stays. They do no harm, but an old Secret that nobody uses is still a Secret: a readable old token. Secrets that are no longer useful get deleted.

## Exercises

The first three are run in the lesson's cluster, in order, from the state it was left in at the end of "The security habit", and from the `programas/04-configuracion-secretos` folder. **Before each exercise, `kubectl config current-context` must say `kind-curso-k8s-l4`; if it says anything else, do not continue.** `correr.sh` runs them the same way, and its output is in `correr.salida.txt`. **Before** running each one, write in the [log](bitacora.md) what you think will happen. The fourth is written in your own words.

### Exercise 1 — A key that does not exist

With a `patch`, change the key the Deployment looks for in the ConfigMap, as if you had made a mistake writing it (`REVISOR_SERVICIO`, without the final S):

```bash
kubectl patch deployment revisor --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key","value":"REVISOR_SERVICIO"}]'
```

Predict: what state does the new Pod end up in? Does the container start? How many old replicas keep serving, and why is the `0/3` from "The error you will see" not repeated this time? Check it with `kubectl get pods -l app=revisor` and with the new Pod's `Failed` events. To get out, apply the `kustomization.yaml` again.

### Exercise 2 — Rotate the token (project)

Someone saw the token on a shared screen and it has to be changed. Before generating the new one, save the old one in a variable in your terminal, `VIEJO="$(cat token.txt)"`, so you can test it later. Generate the new one with `(umask 077; openssl rand -hex 16 > token.txt)` and apply `kubectl apply -k .`. Before applying, predict: is the existing Secret modified, or does another appear? Is there a *rollout*? What does the `revisor` answer to a request with the **old** token, and what to one with the new? Check it with `kubectl get secret -o name | grep revisor-token` and with two `curl`s from `depurar`, one with `-H "Authorization: Bearer $VIEJO"` and another with `-H "Authorization: Bearer $(cat token.txt)"`. To finish, explain what you would have to do with the old Secret, and why.

### Exercise 3 — Without the *hash*

Copy the lesson's folder to another place, add these two lines at the end of the copy of `kustomization.yaml`, and look at the result with `kubectl kustomize` (without applying it):

```yaml
generatorOptions:
  disableNameSuffixHash: true
```

Predict first: what will the ConfigMap and the Secret be called? Which name will the Deployment point to? Then, without running it, answer: if with this option you change the list and apply, is there a *rollout*? Which part of the lesson did you just repeat? And, since the Secret is immutable, what do you think would happen when rotating the token with this option?

### Exercise 4 — Defend the file

A colleague proposes passing the token with `secretKeyRef`, as an environment variable, "because it's one line and not a volume, and the Secret is just as secret in both cases". In five sentences at most, answer him: where he is right, what risk the variable adds that the file does not have, what the `revisor` itself says when it receives the token by variable, and what would have to be added to the Deployment so the file can be read without opening it to everyone.

## Solutions

### Solution 1

Measured in `correr.salida.txt`:

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS                       RESTARTS   AGE
revisor-84564b6875-ssrsx   0/1     CreateContainerConfigError   0          15s
revisor-f6dd4cb4d-6nrc8    1/1     Running                      0          17s
revisor-f6dd4cb4d-9sjs2    1/1     Running                      0          17s
revisor-f6dd4cb4d-s5h4z    1/1     Running                      0          18s

$ kubectl get events --field-selector involvedObject.name=revisor-84564b6875-ssrsx,reason=Failed -o custom-columns=MENSAJE:.message | head -2
MENSAJE
Error: couldn't find key REVISOR_SERVICIO in ConfigMap default/revisor-config-t6cm6872fk
```

The new Pod ends up in **`CreateContainerConfigError`**, the same state as the `runAsNonRoot` one in Lesson 2: the `kubelet` could not build the container's configuration and **did not start it**. The event says exactly what was missing: the key `REVISOR_SERVICIO` in the ConfigMap `default/revisor-config-t6cm6872fk`. It is what `Optional: false` announced in 4.2's `describe`.

**The three old replicas keep serving.** The difference from the `fsGroup`'s `0/3` is the moment of failure. Here the container never started, so the new Pod was never ready, not even for an instant, and with `maxUnavailable: 0` the Deployment removed no old Pod. With the `fsGroup`, the container started, was "ready" for a few milliseconds, and crashed, and that was enough for the Deployment to advance. The underlying lesson: **an error that prevents starting is safer than one that starts and crashes**, as long as you have no probes.

When applying the `kustomization.yaml` again, the template went back to that of `revisor-f6dd4cb4d` and the broken Pod disappeared:

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           103s
```

### Solution 2

Measured in `correr.salida.txt`:

```text
$ kubectl get secret -o name | grep revisor-token
secret/revisor-token-bh266kt42m

$ VIEJO="$(cat token.txt)"

$ (umask 077; openssl rand -hex 16 > token.txt)

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-ttgcdb7g7c created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get secret -o name | grep revisor-token
secret/revisor-token-bh266kt42m
secret/revisor-token-ttgcdb7g7c
```

```text
(con el token VIEJO)

$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $VIEJO" http://revisor/api/estados
401

(con el token NUEVO)

$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat token.txt)" http://revisor/api/estados
200
```

`VIEJO` is a variable in your terminal: the token is not written in your history, only the name `$VIEJO`. (Do not save it in another file, such as `token.viejo`: `.gitignore` only excludes `token.txt`.)

**Another Secret appears**, `revisor-token-ttgcdb7g7c`; the old one is not touched, and it could not be: it is immutable. The new token changed the *hash*, the *hash* changed the name, the name changed the Deployment's template, and there was a *rollout* (`deployment.apps/revisor configured`, and `rollout status` with the same turns as 4.7). The ConfigMap did not change (`unchanged`). When it finished, the old token gives `401` and the new one `200`: the new Pods were born with the new file, and the old ones, which knew the old token, no longer exist.

**The old Secret has to be deleted** (`kubectl delete secret revisor-token-bh266kt42m`). No Pod uses it, but it is still in the cluster, and anyone with permission to read Secrets can pull from it, with `base64 -d`, a token that someone saw on a screen. If you wanted to be able to go back to the Deployment's previous revision, that Secret would have to exist; but a compromised token is precisely the one you do **not** want to be able to use again. Rotating does not end when the new one works: it ends when the old one is no longer good anywhere.

### Solution 3

Measured in `correr.salida.txt`, on a copy in a temporary folder:

```text
$ tail -2 $TEMPORAL/sin-hash/kustomization.yaml
generatorOptions:
  disableNameSuffixHash: true

$ kubectl kustomize $TEMPORAL/sin-hash | grep -E '^  name: revisor-(config|token)|name: revisor-(config|token)$'
  name: revisor-config
  name: revisor-token
              name: revisor-config
```

The ConfigMap is called `revisor-config` and the Secret `revisor-token`, plain, and the Deployment points to `revisor-config` (the third line, with more indentation, is its `configMapKeyRef`). Clean names, and **no *rollout*** when the list changes: the ConfigMap keeps its name, the Deployment's template does not change, and the "if and only if" rule is not met. You just repeated section 4.3, only with Kustomize: the object changes and the `revisor` stays with the old list until someone remembers the `rollout restart`.

With the Secret it is worse, and it was measured. The script assembled a separate folder with **only** the Secret, immutable and without a *hash*, in a disposable namespace, `sin-hash`. It applied it, changed that copy's token, and applied it again:

```text
$ kubectl create namespace sin-hash
namespace/sin-hash created

$ kubectl apply -k $TEMPORAL/rotar
secret/revisor-token created

(token nuevo en la copia)

$ kubectl apply -k $TEMPORAL/rotar
The Secret "revisor-token" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]

$ kubectl delete namespace sin-hash
namespace "sin-hash" deleted
```

Since the name no longer changes, `apply -k` tried to **modify** the Secret that already existed, and the cluster refused with the same `field is immutable` as in "The security habit". To rotate the token you would have to delete the Secret by hand before applying, and in the meantime the Pods that restarted would not find their token. Turning off the *hash* and marking immutable are two decisions that contradict each other. The *hash* is what makes immutability practical. (Deleting the `sin-hash` namespace took that Secret with it.)

### Solution 4

One possible answer: "You are right that the Secret stores the same data both ways, and that in `etcd` it is just as exposed. But a variable is inherited by every process the container launches and shows up in any environment dump or log that prints the configuration, whereas a read-only file in `tmpfs` is not copied to each process: it has to be opened on purpose, and only someone with permission can open it. The `revisor` itself, if it receives the token in `REVISOR_TOKEN`, writes in its log that anyone with `docker inspect` can read it and that you should use `REVISOR_TOKEN_ARCHIVO`. To read the file without opening it to everyone, the Deployment needs `defaultMode: 0440` and `fsGroup: 65532` in the Pod's `securityContext`, which makes the `revisor`'s group the file's group. They are three more lines than the variable, and they are worth it."

## Deleting the cluster

When you finish the exercises, delete the lesson's cluster. Leave nothing alive on the machine:

```text
$ kind delete cluster --name curso-k8s-l4
Deleting cluster "curso-k8s-l4" ...
Deleted nodes: ["curso-k8s-l4-control-plane" "curso-k8s-l4-worker2" "curso-k8s-l4-worker"]

$ kind get clusters | grep -c curso-k8s-l4
0
```

The `--name` is mandatory here too: without it, kind would delete the cluster called `kind`, which may belong to someone else or to another project. With the cluster go its Secrets, its ConfigMaps, and the copy of the token that lived in each node's `tmpfs`.

Two things remain on your machine, and both get deleted:

```bash
# El token de la lección: ya no lo usa nadie, y un token suelto no se deja.
rm -f token.txt
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 4.0.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l4.*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

The `case` only lets through a path that starts with `/tmp/curso-k8s-l4.` and ends in `/kubeconfig`, the exact form of the one you created in 4.0; then `dirname` strips the file name and `rm -rf` deletes that folder and nothing else. If your terminal points elsewhere (for example, to your `~/.kube/config`, because you opened another terminal and did not repeat the `export`), it deletes nothing and tells you why. It is the same protection `correr.sh` uses when cleaning up: an `rm -rf` that can be copied and pasted has to protect itself. Closing that terminal also stops using the temporary `kubeconfig`. The next lesson's cluster is created from scratch, just like this one.

## How I know I succeeded

- [ ] You explain, with the `revisor`'s table as evidence, why changing a ConfigMap by hand did not change the list of services of the Pods that were already running.
- [ ] You read in `kubectl describe pod` which ConfigMap and which key each variable comes from, and what `Optional: false` means.
- [ ] You write from memory a `kustomization.yaml` with `resources`, `configMapGenerator` (with `literals`), and `secretGenerator` (with `files: - token=token.txt`), and explain what the `token=` does.
- [ ] You predict, before applying, that a change to the list produces a ConfigMap with another name and a new ReplicaSet, and you verify it with `kubectl diff -k .`.
- [ ] You decode a Secret with `base64 -d` and explain in two sentences the difference between encoding and encrypting.
- [ ] You explain what `fsGroup` does to the Secret's file, and you recognize the `permission denied` of its absence in the `logs`.
- [ ] You explain why the `fsGroup` error left the Deployment at `0/3` and the misspelled key did not.
- [ ] You rotate the token with a new Secret and know what to do with the old one.
- [ ] You run `programas/04-configuracion-secretos/correr.sh > /tmp/mi-corrida-l4.txt 2>&1` and compare `/tmp/mi-corrida-l4.txt` against `programas/04-configuracion-secretos/correr.salida.txt` (do not redirect to that file: it is the reference) in what does not change between runs: three nodes `Ready` at `v1.37.0`; the table with `prueba OK … 200`; `<set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>`; the table that does **not** show `lento` 30 s after the `patch` and does after the `rollout restart`; `-rw-------` for `token.txt` and `wc -c` at 33; `token.txt` in `.gitignore`; `revisor-config-t6cm6872fk` as the generated name; `immutable: true`; `401` without a token, `{"error":"falta el token o no es válido"}` and the table with a token; `-r--r----- 1 0 65532 33 … token` on a `tmpfs`; the token identical after `base64 -d`; `revisor-config-7fbkh2926f` in the `diff` and a new ReplicaSet with `lento` in the table; `permission denied` in the `logs`, the file as `-r--r----- 1 0 0` and the Deployment at `0/3` without `fsGroup`; ``field is immutable when `immutable` is set``; `couldn't find key REVISOR_SERVICIO`; two Secrets after rotating, `401` with the old one and `200` with the new one; the suffixless names in Exercise 3 and its `field is immutable` when rotating; and at the end `sin diferencias con la kustomization`. The token, the Secret's name, the suffixes of Pods and ReplicaSets, the IPs, the `uid`s, each Pod's node, the ages, the table's timings, and the number of times each `rollout status` line repeats change on every run: they are observed, not compared.
- [ ] When you finish, `kind get clusters` no longer shows `curso-k8s-l4`, no `token.txt` was left in the lesson's folder, and no `/tmp/curso-k8s-l4.*` folder is left.

## Summary

Answer without looking at the lesson:

1. What is a ConfigMap and what does its documentation say about storing confidential data in it?
2. Why does changing a ConfigMap used as a variable not change what the `revisor` does? Give both reasons: Kubernetes' and the program's.
3. What does `configMapKeyRef` do, and why does this course prefer it to `envFrom`?
4. What does Kustomize append to a generated ConfigMap's name, and how does that turn a content change into a *rollout*?
5. Why, when going back to the original list in 4.7, did the ConfigMap come out `unchanged` and not `created`?
6. What is the difference between encoding and encrypting? What is base64?
7. Who can read a Secret in a cluster, besides whoever has `get secrets` permission?
8. What does `fsGroup` do to a mounted Secret's file, and what happened when it was removed?
9. Why did the `fsGroup` error leave the service without replicas and the misspelled key did not?
10. What cannot be done with an immutable Secret, and how is its content changed then?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, "ConfigMaps"](https://kubernetes.io/docs/concepts/configuration/configmap/): the definition; that it offers no secrecy or encryption; the 1 MiB cap; the four ways of using it from a Pod; that ConfigMaps mounted as files are updated "eventually" and those used as variables "are not updated automatically and require a pod restart"; and immutable ConfigMaps.
- [Kubernetes, "Configure a Pod to Use a ConfigMap"](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/): `configMapKeyRef`, `envFrom`, and optional references.
- [Kubernetes, "Secrets"](https://kubernetes.io/docs/concepts/configuration/secret/): the definition; the warning that they are stored unencrypted in etcd and that whoever can create a Pod can read the Secrets of its namespace; the 1 MiB cap; the "eventually consistent" update of volumes; the copy in `tmpfs` on the node; and immutable Secrets, their two advantages, and that the mark cannot be reverted.
- [Kubernetes, "Good practices for Kubernetes Secrets"](https://kubernetes.io/docs/concepts/security/secrets-good-practices/): encryption at rest; least privilege access; that base64 is not an encryption method; that a Secret manifest in a repository exposes the secret; and that the application must not log the data in clear text.
- [Kubernetes, "Distribute Credentials Securely Using Secrets"](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/): `defaultMode` and its default value, `0644`.
- [Kubernetes, "Declarative Management of Kubernetes Objects Using Kustomize"](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): Kustomize inside `kubectl` since 1.14; `configMapGenerator` and `secretGenerator`; the content *hash* suffix and `generatorOptions` with `disableNameSuffixHash`.
- [Kubernetes, "Configure a Security Context for a Pod or Container"](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` as a supplementary group of the processes and as the owner of volumes that support ownership management.
- [Kubernetes, "Deployments"](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `minReadySeconds` and when a new Pod counts as available.
- [Kubernetes, "Pod Lifecycle"](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): the growing wait between restarts (10 s, 20 s, 40 s… up to 300 s) and the `CrashLoopBackOff` state.

---

**Next:** [Lesson 5 — Health checks, resources and graceful shutdown](05-salud-recursos-apagado.md)
