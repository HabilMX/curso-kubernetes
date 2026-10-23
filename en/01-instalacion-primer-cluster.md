# Lesson 1 — Installing kubectl and kind; your first cluster

Tuesday, 8:20 in the morning. At ten you have to show the `revisor` running on a cluster, and your laptop does not even have `kubectl`. You search for “install kind” and the first blog post gives you two lines: a `curl` to a URL ending in `latest` and a `sudo mv`. You copy them. A coworker sends you “the kubectl that works for me” over chat, a file with no version and no origin. You use that too. At 8:50, `kind create cluster` prints a column of green check marks, including `✓ Joining worker nodes`. You breathe. At 9:30, the first Deployment hangs halfway and you discover that your three-node cluster has only one. You do not know which version of each tool you have, nor where the binary from the chat came from, nor why two nodes that “joined” do not exist. And there are thirty minutes left.

None of that was bad luck. It was three decisions that nobody made: which version to install, how to know that the binary is what it claims to be, and which system limit has to be raised before creating the cluster. This lesson makes them for you, one by one, and leaves you with a cluster you know how to create, inspect, delete and create again in less than half a minute, once the node image is already on your disk (the first time it has to be downloaded, and that depends on your connection).

**Time:** 90 min

**What you build:** the course cluster. One control-plane node and two worker nodes, created with `kind` from a configuration file that pins the node image by its digest. Before that, `kubectl` and `kind` installed with their version pinned and their checksum verified, and the `inotify` limit measured and adjusted. The programs are in [`programas/01-instalacion-primer-cluster/`](../programas/01-instalacion-primer-cluster).

**What you learn:** what you install and where each component runs; why the version is pinned instead of downloading “the latest”; what a `sha256` checksum is, how it is verified and what to do when it does not match; what `inotify` is, how it is measured and why a three-node cluster exhausts it; what a `kubeconfig` is and what a context is; how to create, inspect, delete and recreate the cluster, and how to recover the context if you lose it

**Where you are coming from.** From [Lesson 0](00-que-es-kubernetes.md) you bring the map. A cluster has a control plane and worker nodes. `kubectl` talks to the `kube-apiserver`, and nothing else. kind builds a cluster out of nodes that are Docker containers, all on the same kernel of your machine. And you saw two warnings that become practice here: with an `inotify` limit of 128, a three-node cluster does not start even if kind says it does, and without a context `kubectl` does not know whom to talk to. From our [Docker course](https://www.habil.mx/en/courses/docker/) you bring Docker Engine installed on your Linux Mint and your user in the `docker` group.

**What this lesson does not do.** It does not deploy anything on the cluster: the `revisor` arrives in [Lesson 2](02-pods-deployments.md). It does not install Docker: that was done in Lesson 1 of the Docker course. It does not use package managers (`apt`, `snap`, Homebrew) for `kubectl` or `kind`, and 1.2 says why. It does not yet explain the objects you see in `kube-system`: it only looks at them.

**About the runs.** The outputs were obtained on October 21, 2026 on an ARM-based Mac, with Docker Engine 29.2.1 inside an Ubuntu 24.04.4 virtual machine started by Colima. **Not** on Linux Mint, which is the course's reference system. So that you know where each output comes from, each one carries one of these labels:

| Label | What it means |
|---|---|
| **Real run · Mac** | Run on the Mac. The Linux binaries were downloaded and their checksum verified there, in a temporary folder that was deleted at the end. The cluster was also created from the Mac. |
| **Real run · Ubuntu 24.04 amd64** | Run in a disposable Ubuntu 24.04 container for `amd64`, the base of Linux Mint 22 on an Intel or AMD machine. There the checksums were verified with GNU's `sha256sum`, as on your Mint, and the binaries were installed and executed. The container was deleted on exit. |
| **Real run · virtual machine** | Run inside the Colima virtual machine, which is where the kernel that Docker uses on the Mac lives. `inotify` was measured there. |
| **Real run · unprivileged container** | Run in a disposable container that cannot change the kernel. The safeguards of the `inotify` adjustment were tested there, without adjusting anything. |

What changes on your Mint. The `install` commands and the `inotify` adjustment use `sudo` and really change your system (on the Mac nothing was changed). The `KERNEL-VERSION` column will show your kernel and `amd64`. The IP addresses, the API server's port and the Pod suffixes will be different. There is one more difference, and it is instructive. On the Mac, `kind version` says `go1.27.0 darwin/arm64`: that `kind` was compiled by Homebrew, not by the project, and that is why the compiler changes. It is exactly what this lesson avoids on your Mint: yours will be the official binary, verified by its checksum, and it will say `go1.26.7 linux/amd64`, as in the Ubuntu run in 1.3.5.

## By the end you will be able to

- Download `kubectl` v1.37.1 and `kind` v0.33.0 from their official source, verify their `sha256` checksum, and recognize the `FAILED` message when it does not match.
- Measure your kernel's `inotify` limits with `sysctl`, adjust them persistently with a file in `/etc/sysctl.d/`, and explain why three kind nodes exhaust them.
- Create the course cluster with a temporary `kubeconfig` of your own and check with `kubectl get nodes` that all three nodes are `Ready`, without trusting the check marks.
- Read a `kubeconfig` with `kubectl config view --minify` and say which cluster, which user and which context it contains.
- Check the active context before a command and change it with `use-context` or with `--context`.
- Delete the cluster, recreate it and recover its context with `kind export kubeconfig` if you lost it.

## The why before the how

Installing two programs seems like the most boring part of the course. It is not, because in this lesson you decide **what software runs under your user and with `sudo` on your machine**, and that has consequences.

`kubectl` is going to hold your cluster's administrator credential in its hands. You saw in Lesson 0 that kind's user is `kubernetes-admin`, from the `kubeadm:cluster-admins` group. `kind`, for its part, creates privileged containers in your Docker. A tampered binary of either one would have access to your entire cluster and to your machine. That is why “something called `kubectl` that works” is not enough. It has to be **the** `kubectl` that the Kubernetes project published, in the version you asked for. The checksum is the way to verify that in a second.

The second reason is reproducibility. If your colleague and you both install “the latest”, each of you has whatever was the latest on the day you downloaded it. Three months from now, an output in the course does not match yours and nobody knows why. Kubernetes ships a minor release about three times a year ([kubernetes.io, “Kubernetes Release Cycle”](https://kubernetes.io/releases/release/)). Pinning the version turns “it works for me” into something that can be compared.

The third is the one you saw in the scene: **a three-node kind cluster depends on a kernel limit** that comes set low on Ubuntu and on Mint. If you do not raise it first, kind does not warn you. It tells you everything went fine.

The lesson goes in this order:

1. **What you are going to install** and where each component runs (1.1).
2. **Pinning the version** (1.2).
3. **Downloading and verifying the checksum**, with the deliberate error (1.3).
4. **The `inotify` adjustment**: measure, adjust and see how much the cluster consumes (1.4).
5. **The cluster file**, with the image pinned (1.5).
6. **Creating the cluster** with a `kubeconfig` of your own (1.6).
7. **Contexts and `kubeconfig`** (1.7).
8. **Inspecting the cluster** (1.8).
9. **Deleting, recreating and recovering** (1.9).

This is the destination, the last command of the lesson, after deleting the cluster and creating it again in 26 seconds:

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

## The concepts

### 1.1 What you are going to install

#### 1.1.1 The components

| Component | What it is | Where it runs | Do you install it here? |
|---|---|---|---|
| Docker Engine | the engine that runs the containers | your Mint | no, you already have it from the Docker course |
| `kind` | a program that creates and deletes clusters made of containers | your Mint | **yes**, a single binary |
| `kindest/node` image | each node's “machine”: Debian with `systemd`, `kubelet` and `containerd` | inside Docker | no, `kind` downloads it the first time |
| `kubectl` | the client that talks to the `kube-apiserver` | your Mint | **yes**, a single binary |
| the cluster | three containers with Kubernetes inside | inside Docker | you **create** it with `kind` |

The two things you install are **one file each**. Neither `kubectl` nor `kind` ships libraries, services or daemons. They are Go binaries that you copy to a folder in the `PATH` and that is it. That is why the installation is short, and why it is a good idea to do it by hand: you see exactly what enters your system.

#### 1.1.2 Why not with `apt` or `snap`

Ubuntu, and therefore Mint, offers `kubectl` through `snap`, and there are `apt` repositories from the Kubernetes project. They work, but they have a problem for this course: **they decide the version for you** and update it on their own schedule. A `snap` updates itself in the background. An `apt` repository bumps your version on the next `apt upgrade`. In a course where every output is compared with yours, you want the version to change **when you decide**. The official `kubectl` installation page offers the direct binary as the first option, and it is the one used here ([kubernetes.io, “Install and Set Up kubectl on Linux”](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)). The kind quick start does the same with the release binary ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)).

### 1.2 Pinning the version

#### 1.2.1 The course versions

| Tool | Version | Where from |
|---|---|---|
| `kubectl` | **v1.37.1** | `dl.k8s.io`, the Kubernetes project's download site |
| `kind` | **v0.33.0** | the v0.33.0 release on GitHub (`kubernetes-sigs/kind`) |
| node image | `kindest/node:v1.37.0` with its digest | the kind v0.33.0 release notes |

The official `kubectl` guide uses a trick: it asks which version is the stable one at `https://dl.k8s.io/release/stable.txt` and downloads that one. On October 21, 2026 that file said `v1.37.1`, the same as the course's. But **tomorrow it may say something else**, and the guide's command would download a different version without warning you. That is why the programs in this lesson write the full version in the URL, without asking.

#### 1.2.2 Why `kubectl` 1.37.1 with a 1.37.0 cluster?

They are two different numbers and Lesson 0 already separated them. The cluster runs what the node image brings, `v1.37.0`. `kubectl` is the tool on your machine. The official policy is clear: “You must use a kubectl version that is within one minor version difference of your cluster. For example, a v1.37 client can communicate with v1.36, v1.37, and v1.38 control planes” ([kubernetes.io, “Install and Set Up kubectl on Linux”](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/); [“Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/)). The patch, the third number, does not count for that rule.

### 1.3 Downloading and verifying the checksum

#### 1.3.1 What a `sha256` checksum is

A `sha256` checksum is a 256-bit number, written as 64 hexadecimal characters (from `0` to `9` and from `a` to `f`), and computed from **all** the bytes of a file. It has two properties that make it useful. It always gives the same result for the same file. And if a single byte changes, a completely different number comes out, with no resemblance to the previous one. There is no practical way to fabricate another file that gives the same checksum.

The project publishes, next to each binary, its checksum. You download both, compute the checksum of the binary that reached you and compare it with the published one. If they match, the file you have is, byte for byte, the one the project published with that checksum. If not, something changed along the way: a truncated download, an outdated mirror, a file from another version or a tampered one. In any of those cases, **you do not install it**.

We have to be honest about what the checksum does not prove. The binary and its checksum come from the same place. If someone controlled `dl.k8s.io` and changed both, they would match. The checksum protects you from corruption and truncated downloads **between** the official site and your disk, and from mixing versions or files without noticing: if what ended up on your disk matches the checksum, it is what the site published. It does not protect you from a binary that comes from a site that is not the official one: the “`kubectl` that works for me” that arrives by chat has no checksum, or has one you cannot check against anything. That is why the origin matters as much as the checksum.

#### 1.3.2 The program that downloads and verifies

`fig01_01.sh` downloads and verifies the two binaries, with the version written in the script itself. It installs nothing and does not ask for `sudo`. It leaves the files in the folder you tell it.

```bash
#!/usr/bin/env bash
# fig01_01.sh — Lección 1, sección 1.3: descargar kubectl y kind con la versión
# FIJADA y comprobar su suma sha256 ANTES de instalarlos.
#
# Solo descarga y comprueba: no instala nada ni pide sudo. Los dos binarios
# quedan en la carpeta que le des, listos para el «sudo install» de la lección.
#
# Uso:  ./fig01_01.sh CARPETA        (una carpeta nueva y vacía, por ejemplo ~/descargas-k8s)
#
# Descarga los binarios de Linux para amd64, los de Linux Mint en un equipo
# Intel o AMD. Si tu equipo es ARM, cambia ARQ=arm64.
set -euo pipefail

KUBECTL_VERSION=v1.37.1
KIND_VERSION=v0.33.0
ARQ=amd64

DESTINO="${1:?uso: ./fig01_01.sh CARPETA}"
mkdir -p "$DESTINO"
cd "$DESTINO"

# Muestra el comando como lo teclearías y luego lo corre.
paso() { printf '\n$ %s\n' "$*"; "$@"; }

echo "# kubectl $KUBECTL_VERSION y kind $KIND_VERSION para linux/$ARQ"

# kubectl: el binario y su suma salen de dl.k8s.io, con la MISMA versión.
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl"
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl.sha256"
paso cat kubectl.sha256; echo
# El archivo .sha256 de kubectl trae solo la suma; se le pega el nombre del
# archivo, como lo pide la guía oficial. El «-» final dice «lee la lista de la
# entrada»: en Linux es opcional, y con él el guion corre igual en macOS.
printf '\n$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -\n'
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -

# kind: el binario y su suma salen del lanzamiento en GitHub. El .sha256sum de
# kind ya trae «suma  nombre», así que se comprueba directo.
paso curl -fsSLo "kind-linux-$ARQ" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ"
paso curl -fsSLo "kind-linux-$ARQ.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ.sha256sum"
paso cat "kind-linux-$ARQ.sha256sum"
paso sha256sum --check "kind-linux-$ARQ.sha256sum"

# Lo que quedó: dos binarios comprobados. wc -c da su tamaño en bytes, para
# compararlo con el de la lección.
paso wc -c kubectl "kind-linux-$ARQ"
```

Three details, from top to bottom:

- **`set -euo pipefail`** makes the script stop at the first command that fails. If the checksum does not match, `sha256sum` exits with code 1 and the script stops there, before downloading `kind` and before the final `wc -c`.
- **`curl -fsSL`**: `-f` makes a server error (a 404 because you mistyped the version) a failure and not an error page saved under the binary's name. `-L` follows redirects, which GitHub uses on all its downloads. `-sS` silences the progress bar but still lets you see errors.
- **Two checksum formats.** The Kubernetes project's `kubectl.sha256` contains only the 64 characters. That is why the official guide builds the line “checksum, two spaces, name” with `echo` and passes it to `sha256sum --check`. kind's `.sha256sum` already contains the full line, and `sha256sum --check` reads it directly.

#### 1.3.3 The run

**Real run · Mac** (the temporary folder was deleted at the end):

```text
# kubectl v1.37.1 y kind v0.33.0 para linux/amd64

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ cat kubectl.sha256
65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
kubectl: OK

$ curl -fsSLo kind-linux-amd64 https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64

$ curl -fsSLo kind-linux-amd64.sha256sum https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64.sha256sum

$ cat kind-linux-amd64.sha256sum
aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d  kind-linux-amd64

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ wc -c kubectl kind-linux-amd64
 61886626 kubectl
 10530942 kind-linux-amd64
 72417568 total
```

What matters are the two `OK`s. Write down the two checksums as well: if a month from now you download the same binaries again with the same versions, **exactly** these must come out. If others come out, it is not the same version or not the same file. The final `wc -c` said that `kubectl` weighs 61,886,626 bytes and `kind` 10,530,942.

The kind quick start gives the command to download the binary, but it does not mention the checksum ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)). The v0.33.0 release does publish a `.sha256sum` for each binary (Linux `amd64` and `arm64`, macOS and Windows), and you can see it in the file list on [its release page](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0). That the guide does not ask for it does not mean it is not needed. This course asks for it.

#### 1.3.4 The deliberate error: `FAILED`

`fig01_02.sh` triggers the failure in the two ways in which it really happens. In the first case, the binary is from **another version**, v1.37.0, and the checksum is from v1.37.1. It is what happens to you when you download the binary with the `stable.txt` command one day and the checksum another day, or when you copy the URL from one tutorial and the checksum from another. In the second, the binary is the right one, but with **one extra byte** at the end, like one that got corrupted or that someone touched. **Real run · Mac** (`fig01_02.error-esperado.txt`):

```text
## Caso 1: binario de v1.37.0, suma de v1.37.1

$ curl -fsSLO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]

## Caso 2: el binario correcto, con un byte de más

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]
```

It reads like this: `kubectl: FAILED` is the verdict on that file, and the warning says how many of the checked files did not match (here, one out of one). Exit code 1 is what stops `set -e` in a script. The official guide shows the verdict first and the warning afterwards, which is what you will see in your Mint's terminal. The output above comes from macOS's `sha256sum`, which printed the warning first. The two lines travel through different channels (standard output and standard error), so when you capture them in a file their order may change. What does not change is the `FAILED` and exit code 1.

Notice what the message does **not** tell you: it does not distinguish “another version” from “tampered file”. The two cases look identical. And it is right that it is that way: it is not up to you to find out which of the two it was, but to not install. What you do when you see a `FAILED`: delete the binary and its checksum, check that both URLs name the same version, and download both again. If it fails again with the same version, you install nothing and find out where you are downloading from.

#### 1.3.5 Installing

On your Mint, the installation is two commands, the one from the official `kubectl` guide and its equivalent for `kind`:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
sudo install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind
```

(On an ARM machine, kind's file is called `kind-linux-arm64`, the two binaries are different and so are their checksums: compare them with the ones each release publishes, not with the ones in this lesson.)

`install` does in one step what `cp`, `chown` and `chmod` would do. It copies the file, leaves it owned by `root` (`-o root -g root`) with permission `0755`: everyone can run it, only `root` can change it. That last part matters. A binary in your `PATH` that your user can overwrite is a binary that any program running as you can replace. The kind quick start uses `chmod +x` and `sudo mv`. The result is almost the same, but the file ends up owned by your user. `install` is cleaner, and that is why the course uses it for both. `/usr/local/bin` is the folder Linux reserves for programs you install yourself by hand, outside the package manager. It is already in Mint's `PATH`.

Since nothing was installed on the Mac, `fig01_03.sh` does the full installation **inside a disposable container** of Ubuntu 24.04 for `amd64`, with the same files that `fig01_01.sh` downloaded. The files go in through a `tar` on standard input, without mounting folders. Inside the container you are already `root`, so the `install` commands go without `sudo`. **Real run · Ubuntu 24.04 amd64** (`fig01_03.salida.txt`):

```text
# Ubuntu 24.04.5 LTS, x86_64, sha256sum (GNU coreutils) 9.4

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: OK

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
$ install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind

$ ls -l /usr/local/bin/kubectl /usr/local/bin/kind
-rwxr-xr-x 1 root root 10530942 Oct 21 09:53 /usr/local/bin/kind
-rwxr-xr-x 1 root root 61886626 Oct 21 09:53 /usr/local/bin/kubectl

$ command -v kubectl kind
/usr/local/bin/kubectl
/usr/local/bin/kind

$ kubectl version --client
Client Version: v1.37.1
Kustomize Version: v5.8.1

$ kind version
kind v0.33.0 go1.26.7 linux/amd64
```

Here the check uses the guide's command **letter by letter**, without the final `-`, and GNU's `sha256sum` says `OK` all the same. Then, three checks that you will repeat on your Mint:

- **`ls -l`**: the `-rwxr-xr-x` permissions, the `root root` owner and the size, which must be the same as the one you saw on download.
- **`command -v kubectl kind`**: which file really runs when you type the name. If you had another `kubectl` installed before (through `snap`, for example), here you see which one wins. The right answer is `/usr/local/bin/kubectl`.
- **`kubectl version --client`** and **`kind version`**: the versions you asked for. `--client` tells `kubectl` not to look for a cluster, because there is none yet. `Kustomize Version: v5.8.1` is the tool from Lesson 4, which comes **inside** `kubectl` and is not installed separately.

A warning that came from the runs' own Mac. There, in the interactive terminal, `type kubectl` answered `kubectl: aliased to kubecolor`: an alias that someone configured to color the output. Scripts do not see your terminal's aliases, so they ran the real `kubectl`, but what you typed by hand went through another program. `command -v` does not always reveal an alias; `type kubectl` does. If your output does not look like the course's, start there.

### 1.4 The `inotify` adjustment

#### 1.4.1 What `inotify` is

Many programs need to find out that a file changed without reading it every second. Linux gives them a mechanism for that: “The inotify API provides a mechanism for monitoring filesystem events” ([man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html)). A program opens an `inotify` **instance** and adds **watches** to it, one per file or folder. The kernel notifies it when something changes.

Each instance and each watch takes up kernel memory, so the kernel sets two caps, **per user**:

- `fs.inotify.max_user_instances`: “an upper limit on the number of inotify instances that can be created per real user ID”.
- `fs.inotify.max_user_watches`: the same for watches.

On a Kubernetes node, the `kubelet`, `kube-proxy`, `containerd` and the control plane components watch files all the time: certificates, manifests, configurations, the containers' logs. On a normal machine, a node is a machine. In kind, **three nodes are three containers on the same kernel**, and almost all their processes run as the same user, `root`. The three share a single cap.

kind's known-issues guide puts it like this: “Resource limits are defined by fs.inotify.max_user_watches and fs.inotify.max_user_instances system variables. For example, in Ubuntu these default to 8192 and 128 respectively, which is not enough to create a cluster with many nodes” ([kind, “Known Issues”](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files)). And it gives the values it recommends: 524288 watches and 512 instances.

#### 1.4.2 Measure before touching

The adjustment is made **before** creating the cluster, and you start by measuring. `fig01_04.sh` without arguments only reads; with `--ajustar` it changes your system, and we see that in 1.4.3:

```bash
#!/usr/bin/env bash
# fig01_04.sh — Lección 1, sección 1.4: MEDIR los límites de inotify del núcleo
# y, solo si se lo pides, AJUSTARLOS como pide la guía de kind.
#
# Uso:  ./fig01_04.sh                → solo mide. No cambia nada.
#       sudo ./fig01_04.sh --ajustar → copia 99-kind-inotify.conf a /etc/sysctl.d/
#                                      y lo carga. Cambia tu sistema: LÉELO ANTES,
#                                      a él y a 99-kind-inotify.conf.
#
# Corre en la máquina donde corre Docker: en Linux Mint, tu propia máquina.
set -euo pipefail
cd "$(dirname "$0")"

MINIMO_INSTANCIAS=512
MINIMO_VIGILANCIAS=524288
ARCHIVO=99-kind-inotify.conf
DESTINO=/etc/sysctl.d/$ARCHIVO

medir() {
  printf '\n$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches\n'
  sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches

  # Cuántas instancias de inotify están abiertas AHORA. Cada una es un
  # descriptor que apunta a «anon_inode:inotify». Sin sudo solo ves las de tus
  # procesos; con sudo, las de todos los usuarios (el límite es por usuario).
  printf '\n$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l\n'
  # (find se queja de las carpetas que no puede leer: eso no es un fallo aquí)
  { find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null || true; } | wc -l | tr -d ' '

  # ¿Quedó escrito en algún archivo, o solo vale hasta reiniciar? Se buscan las
  # líneas que FIJAN un valor (empiezan con fs.inotify), no los comentarios, en
  # todas las carpetas que lee el sistema al arrancar (sysctl.d(5)).
  printf "\n\$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/\n"
  grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/ 2>/dev/null \
    || echo "(ninguna: lo que mide sysctl vale hasta el próximo reinicio)"

  local inst vig
  inst="$(cat /proc/sys/fs/inotify/max_user_instances)"
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  echo
  if [ "$inst" -ge "$MINIMO_INSTANCIAS" ] && [ "$vig" -ge "$MINIMO_VIGILANCIAS" ]; then
    echo "LISTO: instancias $inst (mínimo $MINIMO_INSTANCIAS) y vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
  else
    echo "FALTA AJUSTAR: instancias $inst (mínimo $MINIMO_INSTANCIAS), vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
    echo "Lee este guion y $ARCHIVO, y luego corre: sudo ./fig01_04.sh --ajustar"
  fi
}

ajustar() {
  [ "$(id -u)" -eq 0 ] || { echo "ALTO: --ajustar necesita sudo." >&2; exit 1; }

  # 1. No BAJAR las vigilancias. En núcleos recientes el valor por omisión
  #    depende de la memoria y puede pasar de 524288; en ese caso se instala el
  #    archivo SIN la línea de vigilancias, y solo se suben las instancias.
  local vig contenido
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  contenido="$(mktemp)"
  if [ "$vig" -gt "$MINIMO_VIGILANCIAS" ]; then
    echo "Tus vigilancias ya son $vig, más que $MINIMO_VIGILANCIAS: no se tocan."
    grep -v '^fs.inotify.max_user_watches' "$ARCHIVO" > "$contenido"
  else
    cat "$ARCHIVO" > "$contenido"
  fi

  # 2. No pisar un archivo que ya existe con otro contenido.
  if [ -e "$DESTINO" ] && ! cmp -s "$contenido" "$DESTINO"; then
    echo "ALTO: ya existe $DESTINO con otro contenido. No lo piso:" >&2
    diff "$DESTINO" "$contenido" >&2 || true
    rm -f "$contenido"
    exit 1
  fi

  # Un archivo propio en /etc/sysctl.d/, en vez de editar /etc/sysctl.conf: se ve
  # de un vistazo qué se cambió y por qué, y se quita borrando un archivo.
  install -o root -g root -m 0644 "$contenido" "$DESTINO"
  rm -f "$contenido"
  printf '\n$ sysctl --load=%s\n' "$DESTINO"
  sysctl --load="$DESTINO"

  # 3. Avisar si /etc/sysctl.conf fija inotify: en Ubuntu y Mint se aplica
  #    DESPUÉS (por 99-sysctl.conf) y su valor ganaría al reiniciar.
  if grep -q '^fs.inotify' /etc/sysctl.conf 2>/dev/null; then
    echo "AVISO: /etc/sysctl.conf también fija inotify y se aplica después de $ARCHIVO:" >&2
    grep -n '^fs.inotify' /etc/sysctl.conf >&2
  fi
  medir
}

case "${1:-}" in
  "") medir ;;
  --ajustar) ajustar ;;
  *) echo "uso: ./fig01_04.sh [--ajustar]" >&2; exit 2 ;;
esac
```

What is new is in two of the measurement commands. The first one **counts the open instances**. Each instance is a file descriptor of some process, and in `/proc/<pid>/fd/` that descriptor appears as a link to `anon_inode:inotify`. `find ... -lname` looks for exactly those links. Without `sudo` you can only look at the descriptors of your own processes; with `sudo` you see those of all users, although the cap is counted per user. The second one, the `grep`, looks for **where the value was written**, in all the folders the system reads at boot. It looks for lines that start with `fs.inotify`, which are the ones that set a value, and not the comments that merely mention the word.

On the Mac, the kernel Docker uses is the Colima virtual machine's, so that is where it was measured. **Real run · virtual machine** (`fig01_04.salida.txt`, measurement only, without adjusting):

```text
# máquina virtual de Colima: Ubuntu 24.04.4 LTS, núcleo 6.8.0-100-generic
## sin sudo

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
3

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).

## con sudo (solo mide)

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
110

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).
```

That machine already had 512 instances, and plenty of watches. The difference between 3 and 110 instances is the one between “without `sudo`” and “with `sudo`”: the normal user had 3 open, and the whole system 110, with a kind cluster from another lesson running at that moment. That number changes with everything that is running. What you compare is the cap.

And look at the `grep`: **no file** in the folders read at boot sets `inotify`. The 512 is alive in the kernel, but not written down. Lesson 0 says that this same machine was at 128 and that it was raised to 512 for its test; the `grep` shows that it was raised without leaving a file. If so, the day the virtual machine restarts it goes back to the default value, and the next three-node cluster fails with no explanation. The measurement says what the value is today; the `grep` says what it will be after a restart. You have to look at both, and that is why the script looks at them together.

On a freshly installed Mint, you will most likely see `max_user_instances = 128` and the script will say `FALTA AJUSTAR` (“adjustment needed”). Linux Mint 22 is based on Ubuntu 24.04 ([Linux Mint, release notes for 22](https://www.linuxmint.com/rel_wilma.php)), and Ubuntu ships 128. The watches, on the other hand, may come out high: on the virtual machine used for the runs, also an Ubuntu 24.04, the kernel gave 1048576, far above the 8192 mentioned by the kind guide. On recent kernels that value depends on the machine's memory, so what is almost always missing are the instances.

#### 1.4.3 Adjust it, and make it last

The kind guide gives two ways. The **temporary** one, which holds until you restart:

```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

And the **persistent** one: writing the two lines into `/etc/sysctl.conf`. The course does the persistent one with a variation: instead of editing `/etc/sysctl.conf`, it puts a file of its own in `/etc/sysctl.d/`. This is the file, `99-kind-inotify.conf`:

```ini
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

Why a separate file? Because “At boot, systemd-sysctl.service(8) reads configuration files from the above directories”, and `/etc/sysctl.d/*.conf` is one of them ([man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html)). You have in a single file, with its comment, what you changed and why, and to undo it you delete it and restart.

But there is a trap in the order. The same page says that all files are sorted by name, regardless of which folder they are in, and that if two set the same thing, **the one that comes later wins**. The `99-` leaves the course's file almost at the end. Almost, because Ubuntu, and Mint with it, ships another one. Measured on the virtual machine used for the runs:

```text
$ ls /etc/sysctl.d/
10-bufferbloat.conf
10-console-messages.conf
10-ipv6-privacy.conf
10-kernel-hardening.conf
10-magic-sysrq.conf
10-map-count.conf
10-network-security.conf
10-ptrace.conf
10-zeropage.conf
99-cloudimg-ipv6.conf
99-lima.conf
99-sysctl.conf
README.sysctl

$ ls -l /etc/sysctl.d/99-sysctl.conf
lrwxrwxrwx 1 root root 14 Nov 25  2025 /etc/sysctl.d/99-sysctl.conf -> ../sysctl.conf
```

`99-sysctl.conf` is a link to `/etc/sysctl.conf`, and `99-sysctl.conf` comes after `99-kind-inotify.conf` in alphabetical order (the `s` comes after the `k`). So **if someone put an `inotify` value in `/etc/sysctl.conf`, that value wins** on restart, and the course's one is useless. That is why `--ajustar` checks `/etc/sysctl.conf` and warns you, and why the measurement searches all the folders.

On your Mint, the adjustment is `sudo ./fig01_04.sh --ajustar`. **Before running it with `sudo`, read it in full, together with `99-kind-inotify.conf`.** It is the same habit as with the binaries: everything that runs as `root` you read first. What you will find in `ajustar`:

1. **It does not lower your watches.** If your kernel already has more than 524288, the file it installs goes without the `max_user_watches` line, and it only raises the instances. Without this safeguard, kind's adjustment would **take away** watches from you.
2. **It does not overwrite a file that already exists.** If `/etc/sysctl.d/99-kind-inotify.conf` exists with other content, it shows you the difference and stops.
3. It copies the file with owner `root` and permission `0644`, loads it right then with `sysctl --load` (without waiting for a restart), warns you if `/etc/sysctl.conf` also sets `inotify`, and measures again. It must end in `LISTO` (“ready”).

The real adjustment was not run on the runs' machine: it already had 512, and it was a shared machine where nothing should be changed. What was tested are the two safeguards, in a disposable **unprivileged** container, where `/proc/sys` is read-only and `sysctl` cannot change anyone's kernel. **Real run · unprivileged container** (`fig01_04.prueba-ajustar.txt`):

```text
$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.

$ sysctl --load=/etc/sysctl.d/99-kind-inotify.conf
sysctl: permission denied on key "fs.inotify.max_user_instances"
[código de salida: 1]

$ cat /etc/sysctl.d/99-kind-inotify.conf
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_instances = 512

$ echo otro > /etc/sysctl.d/99-kind-inotify.conf

$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.
ALTO: ya existe /etc/sysctl.d/99-kind-inotify.conf con otro contenido. No lo piso:
1c1,5
< otro
---
> # /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
> # kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
> # Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
> # arranca: el kubelet de los nodos de trabajo cae con «too many open files».
> fs.inotify.max_user_instances = 512
[código de salida: 1]
```

The first run saw 1048576 watches and installed the file **without** the watches line: the `cat` shows it. The `permission denied` is expected in an unprivileged container; on your Mint, with `sudo`, `sysctl --load` replies with the lines it loaded. The second run found a file with other content and stopped without touching it.

#### 1.4.4 How much a cluster consumes

With the cluster created (1.6), the lesson's script looks at the limit **from inside** each node, and counts the instances each one opens. **Real run · Mac**, excerpt from `correr.salida.txt`:

```text
$ docker exec curso-k8s-l1-control-plane cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker2 cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-control-plane sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
45

$ docker exec curso-k8s-l1-worker sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18

$ docker exec curso-k8s-l1-worker2 sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18
```

The three nodes say 512: they have no limit of their own, they see **the machine kernel's**. It is the same clue as the `KERNEL-VERSION` column in Lesson 0, now with a number that matters. And the count: 45 instances on the control-plane node and 18 on each worker node. That makes 81, with the cluster **empty**, freshly created, without a single Pod of yours. Almost all of them belong to `root` processes, and the cap is per user: to those 81 you add the ones `root` already has open on your own machine, which you can count with the `find` in `fig01_04.sh` run with `sudo`. With a cap of 128, the margin is small. What happens at startup, when the three nodes bring up their processes at the same time, was not measured here; Lesson 0 saw the result: the worker nodes did not arrive. With 512 there is plenty of room for this cluster and for one more.

### 1.5 The cluster file

`kind create cluster` on its own creates a single-node cluster called `kind`, with the default node image of that kind version. The course needs three nodes, a name of its own and the image pinned, and that is written in a file:

```yaml
# kind-curso.yaml — el clúster del curso: un nodo de control y dos de trabajo,
# con la imagen del nodo fijada por su huella (notas de la versión v0.33.0 de kind).
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

It reads from top to bottom. `kind: Cluster` and `apiVersion: kind.x-k8s.io/v1alpha4` say that it is the configuration of a kind cluster. It looks like a Kubernetes manifest, but it is not: this file is read by `kind`, never by the cluster. `nodes` is the list of nodes, one per line with `role`: `control-plane` for the control plane and `worker` for the worker nodes. It is the same form the kind quick start uses for a “three node (two workers) cluster” ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)).

And each node carries its `image` **with a digest**. It is the same habit as the binaries' checksum, applied to an image. The tag `v1.37.0` is a name that whoever publishes the image can move to another one. The digest `sha256:a1ed…` is the checksum of the content. The kind guide asks for it this way: “Please use the sha256 shasum for your desired kubernetes version”, as published in each release's notes ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/); [kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). If someone substitutes the image, Docker does not accept it, because the digest no longer matches.

The cluster's name is not in the file, it is in the command: `--name curso-k8s-l1`. That way the same file can be used to create clusters with other names.

The command looks for `kind-curso.yaml` at the path you give it. The commands in this lesson assume you are inside `programas/01-instalacion-primer-cluster/`, where the file lives. If you copy the file to another folder, run the command from there or write the full path in `--config`.

### 1.6 Creating the cluster

#### 1.6.1 A `kubeconfig` of your own for the course

Before creating anything, a security decision. When kind creates a cluster, it **writes into your `kubeconfig`** the cluster's address and the administrator credential, and leaves it as the active context. If you tell it nothing else, that file is `~/.kube/config`. If that file already has a cluster from work or from another course, kind changes the active context without asking you.

That is why, in this course, kind writes to a **temporary file of its own**. By hand, in your terminal, it goes like this:

```bash
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l1.XXXX)/kubeconfig"
```

`mktemp -d` creates a folder with a name nobody else has. `export KUBECONFIG=…` makes `kind` and `kubectl` use that file **in this terminal**, and in no other. Your `~/.kube/config` is neither read nor touched. You close the terminal and your usual configuration stays just as it was before.

What does **not** go away when you close the terminal: the cluster, which keeps running, and the temporary folder, with the administrator credential inside. In addition, when you close you lose the `KUBECONFIG` path. That is why, on the by-hand route, before closing:

```bash
kind delete cluster --name curso-k8s-l1
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp arriba.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l1.*/kubeconfig) rm -r -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

The `case` only lets through a path with the exact shape of the one `mktemp` created; if your `KUBECONFIG` points somewhere else, for example to your `~/.kube/config` because you opened another terminal and did not repeat the `export`, it deletes nothing and tells you why, instead of taking your entire `~/.kube` folder with it.

If you already closed, `kind get clusters` tells you what was left alive, and `ls -d /tmp/curso-k8s-l1.*` which folders were left. The lesson's script, `correr.sh`, does all this on its own: it creates its temporary folder and, on exit, deletes the cluster and the folder.

#### 1.6.2 The lesson's script

`correr.sh` goes through everything that is left of the lesson: it creates the cluster, inspects it, plays with the contexts, triggers the errors, deletes it, recreates it and, on exit, deletes it again. Its header explains its three safeguards, and they are the same ones you will use throughout the course:

```bash
# 🔴 SEGURIDAD, las tres protecciones de la lección:
#   1. KUBECONFIG apunta a un archivo TEMPORAL propio: tu ~/.kube/config ni se
#      lee ni se toca, y tus otros clústeres no se enteran.
#   2. Antes de cada kubectl que le habla al clúster, se comprueba que el
#      contexto activo es kind-curso-k8s-l1; si no, el guion se detiene.
#   3. Un trap borra al salir el clúster que ESTA corrida creó y el temporal,
#      aunque el guion falle a la mitad. Si al empezar ya existe un clúster
#      llamado curso-k8s-l1, se detiene sin tocarlo.
```

The third deserves an explanation. `trap limpiar EXIT` tells Bash: “when this script ends, for whatever reason, run `limpiar`”. If a command fails halfway and `set -e` stops the script, `limpiar` runs anyway and deletes the cluster. That way you are not left with a forgotten cluster using up memory. But `limpiar` only deletes if the variable `CREADO_AQUI` says `si`, and that variable is set to `si` **only if this run's `kind create cluster` finished successfully**. If there was already a `curso-k8s-l1` from before, the script stops at the beginning and does not touch it: that cluster is not its own. And if another process created it an instant after that check, the script's `create` fails with `node(s) already exist`, the script stops and the variable remains at `no`: it does not touch it either.

The second safeguard is a short function, the same one from Lesson 0:

```bash
contexto_correcto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    return 1
  fi
}
k() { contexto_correcto || exit 1; paso kubectl "$@"; }
```

Every `kubectl` that talks to the cluster goes through `k`, which first checks the context. The `kubectl config` commands, which only read or edit the `kubeconfig` file without talking to any cluster, go through another function, `kc`, without a check. They do not need one, and in section 1.7 the script changes context on purpose.

#### 1.6.3 The creation

Before creating anything, the script looks at the temporary `kubeconfig`. It is empty: there are no contexts and no active context.

```text
$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]
```

And it creates the cluster. **Real run · Mac:**

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
 • Ensuring node image (kindest/node:v1.37.0) 🖼️  ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
 • Preparing nodes 📦 📦 📦   ...
 ✓ Preparing nodes 📦 📦 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
 • Joining worker nodes 🚜  ...
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-curso-k8s-l1"
You can now use your cluster with:

kubectl cluster-info --context kind-curso-k8s-l1

Have a nice day! 👋
(crear tardó 23 s)
```

Each pair of lines is a step. *Ensuring node image* looks for the node image and, if it is not there, downloads it; the first time on your Mint this step takes as long as the image takes to download, and the following times it is instant. *Preparing nodes* creates the three containers (one 📦 per node). *Writing configuration* writes the `kubeadm` configuration, the official tool that builds the cluster. *Starting control-plane* starts the control plane. *Installing CNI* sets up the network between Pods, `kindnet`. *Installing StorageClass* sets up the default storage. *Joining worker nodes* joins the two worker nodes. At the end, `Set kubectl context to "kind-curso-k8s-l1"` is the line that matters most to you in this lesson: kind wrote the context into your `kubeconfig` (the temporary one) and left it active. The farewell phrase changes randomly on every run.

With the image already downloaded, creating took 23 seconds. And now, the lesson from Lesson 0: **the check mark is not the proof**. The proof has two parts. The first is to wait for the nodes to say `Ready`:

```text
$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met
```

`kubectl wait` keeps waiting until all the nodes (`--all`) meet the `Ready` condition, or until 240 seconds pass. But it has a blind spot: it waits for the nodes that **exist**. In the failure in Lesson 0, the worker nodes never got to register; there `kubectl wait --all` would have waited for one, would have said `condition met` a single time and would have finished without error. That is why the second part is **counting**:

```text
$ kubectl get nodes --no-headers | wc -l
3
```

`--no-headers` removes the header line and `wc -l` counts the lines that remain: one per node. It has to say 3. The script does not rely on anyone reading it: if it is not 3, it stops with `ALTO: el clúster tiene N nodos, no 3` (“STOP: the cluster has N nodes, not 3”). (In `correr.sh`, the wait and the count come after looking at the `kubeconfig`, in section 5 of its output; here they are told together because they are the same proof.)

### 1.7 Contexts and `kubeconfig`

#### 1.7.1 What is in a `kubeconfig`

The documentation defines it this way: “A file that is used to configure access to clusters is called a *kubeconfig file*. This is a generic way of referring to configuration files. It does not mean that there is a file named `kubeconfig`” ([kubernetes.io, “Organizing Cluster Access Using kubeconfig Files”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). By default, `kubectl` looks for one called `config` in `$HOME/.kube`.

A `kubeconfig` has three lists and a pointer:

- **`clusters`**: which address to talk to and with which certificate to recognize the server.
- **`users`**: which credential to present yourself with.
- **`contexts`**: named combinations of a cluster, a user and, optionally, a namespace. The documentation: “Each context has three parameters: cluster, namespace, and user. By default, the kubectl command-line tool uses parameters from the current context to communicate with the cluster.”
- **`current-context`**: the pointer. Which of the contexts `kubectl` uses when you do not tell it another.

The script looks at it right after creating the cluster:

```text
$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   

$ kubectl config view --minify
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://127.0.0.1:54589
  name: kind-curso-k8s-l1
contexts:
- context:
    cluster: kind-curso-k8s-l1
    user: kind-curso-k8s-l1
  name: kind-curso-k8s-l1
current-context: kind-curso-k8s-l1
kind: Config
users:
- name: kind-curso-k8s-l1
  user:
    client-certificate-data: DATA+OMITTED
    client-key-data: DATA+OMITTED

$ stat -c %A "$KUBECONFIG"
-rw-------
```

Four things to read:

- **The context name is `kind-` plus the cluster name.** kind always names them this way: the `curso-k8s-l1` cluster gives the `kind-curso-k8s-l1` context, and the default cluster `kind` gives `kind-kind`. The cluster and the user in the `kubeconfig` carry the same name.
- **`get-contexts`** is the short table. The asterisk in `CURRENT` marks the active one. `AUTHINFO` is the user. An empty `NAMESPACE` means `default`.
- **`view --minify`** shows only what the active context uses. The server address is `https://127.0.0.1:54589`: the high port that Docker published on your machine for the control-plane node's `kube-apiserver`, on `127.0.0.1` by default. kind lets you change that address with `networking.apiServerAddress`, but its documentation advises against exposing it to anything other than the local interface, and this course does not change it. The three `DATA+OMITTED` fields are the server's certificate and **the administrator credential**. `kubectl` hides them because they are secrets. They are complete in the file.
- **`stat -c %A`** gives the file's permissions: `-rw-------`, only your user can read it. kind creates it that way because it contains that credential. If you ever copy a `kubeconfig` somewhere else, keep those permissions. (On your Mint, `ls -l "$KUBECONFIG"` says the same, together with your username.)

The documentation adds a warning that holds forever: “Only use kubeconfig files from trusted sources. Using a specially-crafted kubeconfig file could result in malicious code execution or file exposure. If you must use an untrusted kubeconfig file, inspect it carefully first, much as you would a shell script.” A `kubeconfig` can ask for a program to be executed to obtain the credential: that is why it is read before it is used.

#### 1.7.2 Two contexts, and the error without a message

Lesson 0 described the most dangerous error in `kubectl`: talking to the wrong cluster, with nothing warning you. The script sets it up on purpose, only inside the temporary `kubeconfig`. It adds a second context, `otro`, with a fake credential and an address where nobody is listening, `127.0.0.1:1`, and leaves it active:

```text
$ kubectl config set-cluster otro --server=https://127.0.0.1:1
Cluster "otro" set.

$ kubectl config set-credentials nadie --token=token-de-mentira
User "nadie" set.

$ kubectl config set-context otro --cluster=otro --user=nadie
Context "otro" created.

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   
          otro                otro                nadie               

$ kubectl config use-context otro
Switched to context "otro".
```

Notice the order. The three `set-…` commands build a cluster, a user and a context that joins them, in that order. `get-contexts` shows the two contexts, with the asterisk still on kind's. `use-context otro` moves the pointer. From then on, any plain `kubectl` goes to `otro`. What the check says:

```text
$ (la comprobación del contexto, antes de un kubectl get nodes)
ALTO: el contexto activo es «otro», no «kind-curso-k8s-l1». No sigo.
[el guion NO corre kubectl get nodes: se detuvo a tiempo]

(Sin la comprobación, kubectl le habla a «otro»:)
```

And what happens if you do not check:

```text
$ kubectl get nodes --request-timeout=5s
E1021 07:11:02.007697   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.007948   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009279   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009582   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.010566   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
The connection to the server 127.0.0.1:1 was refused - did you specify the right host or port?
[código de salida: 1]
```

The lines that start with `E1021 … memcache.go:381` are written by the `kubectl` client itself, not by the cluster: the `E` is the error level, `1021` is the month and day, and `memcache.go` is the code with which `kubectl` caches in memory the list of resources a server offers. Before running your command, `kubectl` asks the server which resources it has, and here that question failed five times because nobody was listening. It is repeated noise, and what matters is the last line.

Here you got lucky, because `otro` does not exist and the error is noisy. Read the last line: it says **which server** it tried to talk to, `127.0.0.1:1`, and that is not your cluster's, which was at `127.0.0.1:54589`. If `otro` were a real cluster, the answer would have been a list of someone else's nodes, without a single error. The exercise of reading **whom** you talked to is the same in both cases.

There is a way not to depend on the pointer: telling each command which context it goes to, with `--context`.

```text
$ kubectl --context kind-curso-k8s-l1 get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

With `otro` active, this command talked to kind, because the flag takes precedence over the file's `current-context`. According to the documentation, the context is chosen by “the first hit in this chain”: first the `--context` flag, then the `current-context` of the files ([kubernetes.io, “Organizing Cluster Access…”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). In scripts that are shared, putting `--context` on every command is as good a safeguard as checking the context beforehand. The course uses the check because, in addition, it teaches you the habit.

The script leaves everything as it was: it goes back to `kind-curso-k8s-l1` with `use-context` and deletes the fake context, cluster and user with `delete-context`, `delete-cluster` and `delete-user`. Each one answered `deleted … from /tmp/curso-k8s-l1.LWx1/kubeconfig`. That line also tells you **which file** was modified, and there you can see that it was the temporary one.

#### 1.7.3 `KUBECONFIG` as a list

One more thing worth knowing, even though the course does not use it. `KUBECONFIG` can hold **several files**, separated by colons on Linux. `kubectl` merges them into one. For values that repeat, the first file that defines them wins. In particular, the `current-context` of the first file that has one wins ([kubernetes.io, “Organizing Cluster Access…”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). And when `kubectl` creates a new value, it writes it in the first file of the list that exists ([kubernetes.io, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/)). It is useful and it is a trap: with two files in the list, a `use-context` can change a file you did not expect. With a single temporary file per cluster, as in this course, there are no doubts.

### 1.8 Inspecting the cluster

With the context verified, the script inspects the cluster from four sides. First, from Kubernetes:

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l1-control-plane   Ready    control-plane   31s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker          Ready    <none>          16s   v1.37.0   172.18.0.6    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0   172.18.0.7    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

Three `Ready` nodes, version `v1.37.0`, with the `containerd://2.3.4` runtime. The control-plane node is 15 seconds older than the other two: it was created first and the workers joined afterwards. The `ROLES` column says `control-plane` for one and `<none>` for the workers. It is not an error: `ROLES` comes from each node's `node-role.kubernetes.io/…` labels, and when the cluster is created only the control-plane node receives one (`control-plane`). `INTERNAL-IP` are addresses from Docker's `kind` network, `172.18.0.x`, which will be different on your machine. And `KERNEL-VERSION` shows the kernel of the machine that runs Docker, the same for all three.

```text
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:54589
CoreDNS is running at https://127.0.0.1:54589/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

`cluster-info` answers the question “what am I talking to?” with the server's address. It is the same one as in `view --minify`. If you ever doubt your context, this command tells you the real address.

Second, from kind and from Docker:

```text
$ kind get nodes --name curso-k8s-l1
curso-k8s-l1-worker
curso-k8s-l1-control-plane
curso-k8s-l1-worker2

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l1-worker          kindest/node:v1.37.0   
curso-k8s-l1-control-plane   kindest/node:v1.37.0   127.0.0.1:54589->6443/tcp
curso-k8s-l1-worker2         kindest/node:v1.37.0   
```

`kind get nodes --name` lists the containers of **that** cluster, in no fixed order. There is also `kind get clusters`, which lists all the kind clusters on your machine: it is useful for finding out whether there are others, but do not use it to decide what to delete without reading each name. `docker ps` with the `io.x-k8s.kind.cluster` label filter shows the same three containers. Only one publishes a port: the control-plane one, `127.0.0.1:54589->6443/tcp`. That is `kubectl`'s path to the `kube-apiserver`, which listens on 6443 inside the node. The workers publish nothing, and nobody outside your machine can talk to your cluster.

Third, what runs inside, without touching anything:

```text
$ kubectl get pods -n kube-system -o wide
NAME                                                 READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-27jlk                             1/1     Running   0          23s   10.244.0.4   curso-k8s-l1-control-plane   <none>           <none>
coredns-559f6c778d-fd4kh                             1/1     Running   0          23s   10.244.0.2   curso-k8s-l1-control-plane   <none>           <none>
etcd-curso-k8s-l1-control-plane                      1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-n44qw                                        1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kindnet-rf64g                                        1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-xsc6h                                        1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-apiserver-curso-k8s-l1-control-plane            1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-controller-manager-curso-k8s-l1-control-plane   1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-proxy-hxjzg                                     1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kube-proxy-jp497                                     1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-proxy-m4r92                                     1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-scheduler-curso-k8s-l1-control-plane            1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
```

These are the components from Lesson 0, now spread across three nodes. The `NODE` column tells it. The control plane (`etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`) lives only on the control-plane node. There is **one `kube-proxy` and one `kindnet` per node**, three of each: they are the components each machine needs for networking. And the `IP` column has two kinds of address. The system Pods that use the node's network have their node's `172.18.0.x`. The two `coredns` have `10.244.0.x`, addresses from the **Pod network** that `kindnet` set up. Lesson 3 comes back to this.

Fourth, the storage that kind installed:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  29s
```

One storage class, `standard`, marked as the default. It stores the data on the node's own disk. It is the `Installing StorageClass` line from the creation, and Lesson 8 uses it.

### 1.9 Deleting, recreating and recovering

#### 1.9.1 Losing the context

It happens more than you think: someone cleans up their `kubeconfig`, or deletes a context thinking of another one. The cluster is still alive, but `kubectl` no longer knows how to reach it. The script triggers it:

```text
$ kubectl config delete-context kind-curso-k8s-l1
warning: this removed your active context, use "kubectl config use-context" to select a different one
deleted context kind-curso-k8s-l1 from /tmp/curso-k8s-l1.LWx1/kubeconfig

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE
```

`kubectl` warns that you deleted the **active** context. The table is left empty. The cluster did not notice: its three containers keep running. What was lost is the path. kind knows how to rebuild it, because the cluster keeps its own configuration:

```text
$ kind export kubeconfig --name curso-k8s-l1
Set kubectl context to "kind-curso-k8s-l1"

$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

`kind export kubeconfig` writes the cluster's context again into the `kubeconfig` that `KUBECONFIG` indicates and leaves it active. Its sibling, `kind get kubeconfig --name curso-k8s-l1`, writes nothing: according to its own help, it “Prints cluster kubeconfig” to the screen. A printed `kubeconfig` is a printed credential, so that command is not run with someone watching and is not pasted into a chat.

#### 1.9.2 Deleting

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
Deleted nodes: ["curso-k8s-l1-worker" "curso-k8s-l1-control-plane" "curso-k8s-l1-worker2"]
(borrar tardó 1 s)

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'
```

One second. Deleting a kind cluster means deleting three containers, and kind also removes from the `kubeconfig` what it had written: the context no longer exists and the pointer is left empty. If you ran `kubectl get nodes` now, you would see the `localhost:8080` error that Lesson 0 taught you to read. `docker ps` with the filter returns nothing.

**Always with `--name`.** Without it, kind deletes the cluster called `kind`, the default one: “If the flag --name is not specified, kind will use the default cluster context name kind and delete that cluster” ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)). If you have a `kind` cluster from another course, it is gone.

And a useful oddity: deleting a cluster that **does not exist** is not an error. The script does it on purpose, right after deleting it:

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
```

No `Deleted nodes` and no error. The kind guide explains it: “By design, requesting to delete a cluster that does not exist will not return an error.” That is why you can put it at the start of a script, “just in case”. But it also means that if you mistype the name, kind does not warn you: it says `Deleting cluster` and deletes nothing. The `Deleted nodes` line is the proof that it deleted something.

#### 1.9.3 Recreating

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
…
Set kubectl context to "kind-curso-k8s-l1"
…
(recrear tardó 26 s)

$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met

$ kubectl get nodes --no-headers | wc -l
3

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

(kind's intermediate steps were omitted, identical to those in 1.6.3; they are complete in `correr.salida.txt`.)

Twenty-six seconds, and the cluster is as good as new, with its three nodes counted. This changes the way you work in the rest of the course. A cluster that is rebuilt in half a minute **is not repaired**: if you left it in a state you do not understand, you delete it and recreate it. What is not lost is what is in files: `kind-curso.yaml` and, from Lesson 2 on, your manifests. It is the idea of Lesson 0 taken to the whole cluster: the file is the truth.

At the end, the script exits and the `trap` deletes the recreated cluster and the temporary folder. On the runs' machine, after exiting, `docker ps` showed no `curso-k8s-l1` container and the `/tmp/curso-k8s-l1.*` folder no longer existed.

## The error you will see

This lesson has three errors with a message and one without.

**1. `ERROR: failed to create cluster: node(s) already exist`.** Creating a cluster with a name that already exists:

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "curso-k8s-l1"
[código de salida: 1]
```

It reads literally: there are already nodes, that is, containers, of a cluster with that name. kind neither replaces nor repairs it. Before doing anything, ask yourself **whose it is**. If it is yours, from a previous run that was left alive, `kind delete cluster --name curso-k8s-l1` and you create it again. If you do not know whose it is, you do not delete it: it is the case of a shared machine, and that is why the course's script stops instead of deleting it.

**2. `kubectl: FAILED`.** You saw it in 1.3.4: the binary's checksum does not match the published one. It is not installed. You download the binary **and** its checksum again, with the same version in both URLs.

**3. `The connection to the server 127.0.0.1:1 was refused`.** You saw it in 1.7.2: `kubectl` talked to a server where nobody is listening. The clue is in the address on the last line. Compare it with the one from `kubectl cluster-info` of your cluster: if they do not match, your context is not the one you think it is. If the address is `localhost:8080`, there is no active context (Lesson 0).

**4. The error without a message: the nodes that never arrived.** With `max_user_instances = 128`, kind prints all its check marks, including `✓ Joining worker nodes`, and yet the worker nodes do not join. The logs say `inotify_init: too many open files`. That error **was not reproduced in this lesson**: doing so required lowering the limit on a shared machine where other clusters were running at that moment, and lowering it would have brought them down. Lesson 0 already measured it, in 0.6.3, with its real messages. Here it is prevented: you measure and adjust beforehand (1.4), and after creating you wait for `Ready` with `kubectl wait` and **count** the nodes with `kubectl get nodes --no-headers | wc -l`, because `wait` only waits for those that exist (1.6.3). If the count is not 3, the clues left by Lesson 0 are two: `kubectl get pods -n kube-system` shows some `kube-proxy` in `Error`, and `kubectl logs -n kube-system` of that Pod says `too many open files`. Then you delete the cluster, measure and adjust `inotify` (1.4) and create it again.

## The security habit of the lesson

The course's habits table assigns three to this lesson:

**Binaries with a checksum.** What runs under your user and with `sudo` is downloaded from the official source, with the version written out and the checksum verified before installing. A binary with no origin and no checksum, like the one that arrives by chat, is not installed, even if it “works”. And it is installed with owner `root` and permission `0755`, so that no program running as you can replace it.

**The pinned node image.** Each node's image goes by its digest, not by its tag. It is the same habit as the checksum, applied to what Docker downloads.

**Checking the context before every command that changes something.** A temporary `kubeconfig` of your own for the course, so that kind does not change your usual context. `kubectl config current-context` before acting, or `--context` on every command. And the `kubeconfig` treated as what it is, an administrator credential: `600` permissions, never in a chat or in a repository, and only from sources you trust.

What the three together prevent is what was in the scene: not knowing what runs on your machine, nor against which cluster.

## Common mistakes

**Downloading “the latest”.** A `curl` to `latest` or to `stable.txt` gives you one version today and another tomorrow. The course outputs stop matching and you do not know why. You write the version.

**Downloading the binary and the checksum separately, with different commands.** It is case 1 of 1.3.4: two mixed versions and a `FAILED` that looks like an attack. You download them together, with the same version written only once.

**Skipping the checksum “because it is the official site”.** The checksum verifies what reached your disk, not what is on the server. A truncated download weighs less, runs sometimes and fails in odd ways. The checksum costs one command.

**`sudo mv` of a binary owned by your user.** It ends up in the `PATH` with your user as owner, and any program running as you can replace it. Use `install -o root -g root -m 0755`.

**Raising `inotify` with `sysctl` and forgetting about it.** It works until the next restart. Afterwards the cluster fails and nobody remembers why. The adjustment goes in a file in `/etc/sysctl.d/`, with a comment.

**Creating the cluster in your usual `~/.kube/config`.** kind changes your active context without asking. The next `kubectl` you type in another window, thinking of the work cluster, will talk to kind's, or the other way around. A temporary `KUBECONFIG` per cluster.

**`kind delete cluster` without `--name`.** It deletes the `kind` cluster, which may not be yours. And since deleting one that does not exist gives no error, a mistyped name does not warn you either. You read the `Deleted nodes` line.

**Repairing a kind cluster.** If you left it in a state you do not understand, you delete it and recreate it in half a minute. What matters lives in files.

## Exercises

Exercises 1 and 2 are answered with the lesson's outputs. Exercise 3 needs your Mint with `kubectl` and `kind` installed. Exercise 4 needs the cluster. Write your answers in the [logbook](bitacora.md) before looking at the solutions.

### Exercise 1 — What happened with this binary?

A colleague ran this and asks you for help:

```text
$ curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256
$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

1. Give a probable cause that is **not** an attack, and explain how you would verify it.
2. What would you change in the two commands so that this does not happen?
3. Is the binary installed while this is being investigated? Why?

### Exercise 2 — Read the `kubeconfig`

Using the output of `kubectl config view --minify` from 1.7.1, answer:

1. What address and what port does `kubectl` use to reach the cluster? Where else does that port appear in the lesson?
2. What are the cluster, the user and the context called, and how do they relate to the name you gave kind?
3. What is behind `DATA+OMITTED`, and why does `kubectl` hide it?
4. If someone sends you their `kubeconfig` by chat “so you can see my cluster”, what do you do before using it?

### Exercise 3 — Predict and measure `inotify`

Without running anything, predict what `./fig01_04.sh` will say on your freshly installed Mint, before any adjustment. Then run it. Adjust with `sudo ./fig01_04.sh --ajustar` and run it again without arguments. Then answer:

1. Did your prediction match? What values came out before and after?
2. Where was the adjustment written, and which command proves it to you?
3. If you restart the machine, what value do you expect, and why?

### Exercise 4 — Two clusters, two contexts (project)

In a terminal with a temporary `KUBECONFIG` (1.6.1), create the course cluster with `kind-curso.yaml`. In **the same** `KUBECONFIG`, create another single-node cluster with `kind create cluster --name curso-k8s-l1b` (without a configuration file). Then:

1. Which one ended up as the active context? Predict it before checking with `kubectl config get-contexts`.
2. Without changing the active context, show the nodes of **each** cluster.
3. Delete **only** `curso-k8s-l1b` and verify that the course cluster is still alive and that you can talk to it again.
4. When you finish, delete the course cluster and verify with `docker ps` that no container from either of the two was left.

When you have done it by hand, compare with `programas/01-instalacion-primer-cluster/ejercicio4.sh`, which does the four steps with the safeguards of `correr.sh`, and with its output, `ejercicio4.salida.txt`. (The second cluster uses kind v0.33.0's default node image, without a digest: it is a throwaway cluster, not the course's.)

## Solutions

### Solution 1

1. **Two different versions.** The binary came from whatever `stable.txt` said at that moment, and the checksum is fixed at v1.37.1. If `stable.txt` now says another version, they are files from different versions and the checksum cannot match. You check it with `curl -L -s https://dl.k8s.io/release/stable.txt`: if it does not say `v1.37.1`, there is the cause. Another possible cause is a truncated download; `ls -l kubectl` against the expected size (61,886,626 bytes for v1.37.1 on `amd64`) shows it.
2. Write the version **once**, in a variable, and use it in both URLs, as `fig01_01.sh` does: `KUBECTL_VERSION=v1.37.1`, and `…/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl` and `…/kubectl.sha256`.
3. **No.** A `FAILED` does not say whether the file is from another version or tampered with; the two cases look the same (1.3.4). Until a checksum says `OK`, the binary does not enter `/usr/local/bin`.

### Solution 2

1. `https://127.0.0.1:54589`. The same port appears in `kubectl cluster-info` and in the `PORTS` column of `docker ps`: `127.0.0.1:54589->6443/tcp`, the port that Docker published on your machine for the `kube-apiserver`, which listens on 6443 inside the node. In your run it will be a different one.
2. All three are called `kind-curso-k8s-l1`: `kind-` plus the name you gave it with `--name`. kind always names them this way.
3. The certificate with which `kubectl` recognizes the server (`certificate-authority-data`) and the cluster's **administrator credential** (`client-certificate-data` and `client-key-data`). `kubectl` hides them because whoever has that data is an administrator of the cluster.
4. You read it in full before using it, like a script: the documentation warns that a specially crafted `kubeconfig` can execute code. You use it in a temporary `KUBECONFIG`, you do not mix it with yours, and you remind whoever sent it to you that they have just shared a credential.

### Solution 3

1. What to expect on Mint 22, based on Ubuntu 24.04: `fs.inotify.max_user_instances = 128` and `FALTA AJUSTAR`. The watches depend on your system and your memory, so they may come out different from the 8192 that the kind guide mentions for Ubuntu. After adjusting: 512 instances, at least 524288 watches and `LISTO`. On the virtual machine used for the runs, also an Ubuntu 24.04, the watches were already 1048576. If your first measurement already said `LISTO`, someone adjusted it before; find where with question 2.
2. In `/etc/sysctl.d/99-kind-inotify.conf`. `cat /etc/sysctl.d/99-kind-inotify.conf` and `grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/` prove it; the latter must find the lines of that file (two, or only the instances one if your watches were already higher) and none in any other. If another one shows up in `/etc/sysctl.conf`, that one wins on restart (1.4.3).
3. 512 instances, and watches of at least 524288: at boot, `systemd-sysctl` reads `/etc/sysctl.d/*.conf` and applies the file, unless `/etc/sysctl.conf` sets another value. If you had raised it only with `sudo sysctl …`, it would go back to 128, as would have happened with the virtual machine used for the runs.

### Solution 4

All four answers were measured with `ejercicio4.sh` (`ejercicio4.salida.txt`).

1. **`kind-curso-k8s-l1b`**, the last one created: kind leaves active the context of the cluster it has just created. `get-contexts` shows both, with the asterisk on `kind-curso-k8s-l1b`. This is exactly the context trap: the course cluster is still there, but it is no longer the one you are talking to.
2. With `--context`, which takes precedence over the active context:

   ```bash
   kubectl --context kind-curso-k8s-l1 get nodes
   kubectl --context kind-curso-k8s-l1b get nodes
   ```

   The first shows three nodes and the second one, `curso-k8s-l1b-control-plane`, with `ROLES control-plane` and `v1.37.0`.
3. `kind delete cluster --name curso-k8s-l1b`. It must say `Deleted nodes: ["curso-k8s-l1b-control-plane"]`. kind removes its context from the `kubeconfig`, and the pointer is left empty because that was the active one. `kubectl config get-contexts` shows only `kind-curso-k8s-l1`, with no asterisk. `kubectl config use-context kind-curso-k8s-l1` and `kubectl get nodes` show the course's three nodes.
4. `kind delete cluster --name curso-k8s-l1` and then `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` and the same with `curso-k8s-l1b`. Both answers must be empty, and in the run they were.

## How I know I got it

- [ ] `kubectl version --client` says `Client Version: v1.37.1` and `Kustomize Version: v5.8.1`, and `kind version` says `kind v0.33.0 go1.26.7 linux/amd64`.
- [ ] `command -v kubectl kind` says `/usr/local/bin/kubectl` and `/usr/local/bin/kind`, and `ls -l` shows them with owner `root root` and `-rwxr-xr-x` permissions.
- [ ] You run `./fig01_01.sh` in a new folder and get `kubectl: OK` and `kind-linux-amd64: OK`, with the two checksums from 1.3.3 (on an ARM machine, the ones from the release for `arm64`).
- [ ] `./fig01_04.sh` ends in `LISTO`, its `grep` finds the lines of `/etc/sysctl.d/99-kind-inotify.conf` and none in `/etc/sysctl.conf`.
- [ ] You run `./correr.sh` and check against `correr.salida.txt` what does not change between runs: the empty `kubeconfig` at the start; the three `Ready` nodes, counted (`3`), with `v1.37.0`, `Debian GNU/Linux 13 (trixie)` and `containerd://2.3.4`, with `ROLES <none>` on the workers; a single container that publishes a port, `127.0.0.1:<port>->6443/tcp`; the `standard (default)` class; `512` on all three nodes; the check's `ALTO` with the `otro` context; the `node(s) already exist` error; the context recovered with `kind export kubeconfig`; `error: current-context is not set` after deleting; and three `Ready` nodes after recreating. The ages, the IPs, the port, the Pod suffixes, the order of the nodes in `kind get nodes` and `docker ps`, kind's farewell phrase, the timings, the `inotify` counts and the temporary path change on every run: they are observed, not compared.
- [ ] When `correr.sh` finishes, `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` returns nothing.

## Summary

Answer without looking at the lesson:

1. Why does the course install `kubectl` and `kind` as binaries and not with `apt` or `snap`?
2. What does a matching `sha256` checksum prove, and what does it not prove?
3. What two common causes produce `kubectl: FAILED`, and what do you do in both cases?
4. What is `inotify`, and why do three kind nodes exhaust it when a single node does not?
5. What is the difference between `sudo sysctl fs.inotify.max_user_instances=512` and a file in `/etc/sysctl.d/`?
6. What three lists and what pointer does a `kubeconfig` have?
7. What is exporting `KUBECONFIG` to a temporary file before creating the cluster used for?
8. What wins when there is `--context` in the command and a different `current-context` in the file?
9. What does kind answer if you delete a cluster that does not exist, and why is that both convenient and dangerous?
10. You lost the context, but the cluster is still alive. With what command do you recover it?

## Sources

All consulted on October 21, 2026.

- [Kubernetes, “Install and Set Up kubectl on Linux”](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/): downloading the binary and its checksum, the check with `sha256sum --check` and its `OK` and `FAILED` messages, the `install -o root -g root -m 0755` and the one-minor-version rule.
- [Kubernetes, “Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/) and [“Kubernetes Release Cycle”](https://kubernetes.io/releases/release/): which `kubectl` versions work with which cluster, and the release cadence.
- [Kubernetes, “Organizing Cluster Access Using kubeconfig Files”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/): what a `kubeconfig` is, what a context is, `KUBECONFIG` as a list, the rules for merging files, how the context is chosen and the warning about files from untrusted sources.
- [Kubernetes, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/): the `kubectl config` subcommands and the order in which `kubectl` loads files.
- [kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/): installing from the release binary, creation with `--name` and with a configuration file, the image by its `sha256` sum, deletion without `--name` and that deleting a nonexistent cluster is not an error.
- [kind, “Known Issues”, “Pod errors due to too many open files”](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files): the `inotify` limits, Ubuntu's values and the recommended ones.
- [kind v0.33.0, release page](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0): the binaries with their `.sha256sum` and the `kindest/node:v1.37.0` node image with its digest.
- [man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html): what `inotify` is and what `max_user_instances` and `max_user_watches` limit.
- [man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html): the folders read at boot and the order in which they are applied.
- [Linux Mint 22, release notes](https://www.linuxmint.com/rel_wilma.php): Mint 22 is based on Ubuntu 24.04.

---

**Previous:** [Lesson 0 — What Kubernetes is and what kind is NOT](00-que-es-kubernetes.md) · **Next:** [Lesson 2 — Pods and Deployments](02-pods-deployments.md)
