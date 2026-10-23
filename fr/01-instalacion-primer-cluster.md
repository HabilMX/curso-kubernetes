# Leçon 1 — Installer kubectl et kind ; ton premier cluster

Mardi, 8 h 20 du matin. À dix heures, tu dois montrer le `revisor` en train de tourner dans un cluster, et ton ordinateur portable n'a même pas `kubectl`. Tu cherches « installer kind » et le premier blog te donne deux lignes : un `curl` vers une adresse qui se termine par `latest` et un `sudo mv`. Tu les copies. Un collègue t'envoie par messagerie « le kubectl qui marche chez moi », un fichier sans version ni origine. Tu l'utilises aussi. À 8 h 50, `kind create cluster` affiche une colonne de coches vertes, y compris `✓ Joining worker nodes`. Tu respires. À 9 h 30, le premier Deployment reste bloqué à mi-chemin et tu découvres que ton cluster de trois nœuds n'en a qu'un seul. Tu ne sais pas quelle version de chaque outil tu as, ni d'où vient le binaire de la messagerie, ni pourquoi deux nœuds qui « ont rejoint » le cluster n'existent pas. Et il reste trente minutes.

Rien de tout cela n'était de la malchance. C'étaient trois décisions que personne n'a prises : quelle version installer, comment savoir que le binaire est bien celui qu'il prétend être et quelle limite du système il faut relever avant de créer le cluster. Cette leçon les prend à ta place, une par une, et te laisse un cluster que tu sais créer, regarder, supprimer et recréer en moins d'une demi-minute, une fois que l'image du nœud est déjà sur ton disque (la première fois, il faut la télécharger, et cela dépend de ta connexion).

**Durée :** 90 min

**Ce que tu construis :** le cluster du cours. Un nœud de contrôle et deux nœuds de travail, créé avec `kind` à partir d'un fichier de configuration qui fige l'image du nœud par son empreinte. Avant cela, `kubectl` et `kind` installés avec leur version figée et leur somme de contrôle vérifiée, et la limite d'`inotify` mesurée et ajustée. Les programmes se trouvent dans [`programas/01-instalacion-primer-cluster/`](../programas/01-instalacion-primer-cluster).

**Ce que tu apprends :** ce que tu installes et où tourne chaque pièce ; pourquoi on fige la version au lieu de télécharger « la dernière » ; ce qu'est une somme `sha256`, comment on la vérifie et que faire quand elle ne correspond pas ; ce qu'est `inotify`, comment on le mesure et pourquoi un cluster de trois nœuds l'épuise ; ce qu'est un `kubeconfig` et ce qu'est un contexte ; comment créer, regarder, supprimer et recréer le cluster, et comment récupérer le contexte si tu le perds

**D'où tu viens.** De la [Leçon 0](00-que-es-kubernetes.md), tu apportes la carte. Un cluster a un plan de contrôle et des nœuds de travail. `kubectl` parle au `kube-apiserver`, et à rien d'autre. kind monte un cluster avec des nœuds qui sont des conteneurs Docker, tous sur le même noyau de ta machine. Et tu as vu deux avertissements qui deviennent ici de la pratique : avec une limite d'`inotify` à 128, un cluster de trois nœuds ne démarre pas, même si kind affirme que oui, et sans contexte, `kubectl` ne sait pas à qui parler. Du [cours de Docker](https://www.habil.mx/fr/cours/docker/), tu apportes Docker Engine installé sur ton Linux Mint et ton utilisateur dans le groupe `docker`.

**Ce que cette leçon ne fait pas.** Elle ne déploie rien dans le cluster : le `revisor` arrive dans la [Leçon 2](02-pods-deployments.md). Elle n'installe pas Docker : c'est ce qu'a fait la Leçon 1 du cours de Docker. Elle n'utilise pas de gestionnaires de paquets (`apt`, `snap`, Homebrew) pour `kubectl` ni pour `kind`, et la section 1.2 explique pourquoi. Elle n'explique pas encore les objets que tu vois dans `kube-system` : elle se contente de les regarder.

**À propos des exécutions.** Les sorties ont été obtenues le 21 octobre 2026 sur un Mac à processeur ARM, avec Docker Engine 29.2.1 dans une machine virtuelle Ubuntu 24.04.4 que démarre Colima. **Pas** sur Linux Mint, qui est le système de référence du cours. Pour que tu saches d'où vient chaque sortie, chacune porte l'une de ces étiquettes :

| Étiquette | Ce qu'elle signifie |
|---|---|
| **Exécution réelle · Mac** | Exécuté sur le Mac. Les binaires Linux y ont été téléchargés et leur somme de contrôle y a été vérifiée, dans un dossier temporaire supprimé à la fin. Le cluster a lui aussi été créé depuis le Mac. |
| **Exécution réelle · Ubuntu 24.04 amd64** | Exécuté dans un conteneur jetable Ubuntu 24.04 pour `amd64`, la base de Linux Mint 22 sur une machine Intel ou AMD. Les sommes de contrôle y ont été vérifiées avec le `sha256sum` de GNU, comme sur ton Mint, et les binaires y ont été installés et exécutés. Le conteneur a été supprimé à la sortie. |
| **Exécution réelle · machine virtuelle** | Exécuté dans la machine virtuelle de Colima, qui est l'endroit où vit le noyau qu'utilise Docker sur le Mac. C'est là qu'on a mesuré `inotify`. |
| **Exécution réelle · conteneur non privilégié** | Exécuté dans un conteneur jetable qui ne peut pas modifier le noyau. C'est là qu'on a testé les protections de l'ajustement d'`inotify`, sans rien ajuster. |

Ce qui change sur ton Mint. Les `install` et l'ajustement d'`inotify` passent par `sudo` et modifient réellement ton système (sur le Mac, rien n'a été modifié). La colonne `KERNEL-VERSION` indiquera ton noyau et `amd64`. Les adresses IP, le port du serveur d'API et les suffixes des Pods seront différents. Il y a une différence de plus, et elle est instructive. Sur le Mac, `kind version` affiche `go1.27.0 darwin/arm64` : ce `kind` a été compilé par Homebrew, pas par le projet, et c'est pourquoi le compilateur change. C'est exactement ce que cette leçon évite sur ton Mint : le tien sera le binaire officiel, vérifié par sa somme de contrôle, et affichera `go1.26.7 linux/amd64`, comme dans l'exécution sur Ubuntu de 1.3.5.

## À la fin, tu seras capable de

- Télécharger `kubectl` v1.37.1 et `kind` v0.33.0 depuis leur origine officielle, vérifier leur somme `sha256` et reconnaître le message `FAILED` quand elle ne correspond pas.
- Mesurer les limites d'`inotify` de ton noyau avec `sysctl`, les ajuster de façon persistante avec un fichier dans `/etc/sysctl.d/` et expliquer pourquoi trois nœuds de kind les épuisent.
- Créer le cluster du cours avec un `kubeconfig` temporaire dédié et vérifier avec `kubectl get nodes` que les trois nœuds sont `Ready`, sans te fier aux coches.
- Lire un `kubeconfig` avec `kubectl config view --minify` et dire quel cluster, quel utilisateur et quel contexte il contient.
- Vérifier le contexte actif avant une commande et le changer avec `use-context` ou avec `--context`.
- Supprimer le cluster, le recréer et récupérer son contexte avec `kind export kubeconfig` si tu l'as perdu.

## Le pourquoi avant le comment

Installer deux programmes semble être la partie la plus ennuyeuse du cours. Elle ne l'est pas, parce que c'est dans cette leçon que se décide **quel logiciel tourne avec ton utilisateur et avec `sudo` sur ta machine**, et cela a des conséquences.

`kubectl` va avoir entre les mains l'identifiant d'administrateur de ton cluster. Tu as vu dans la Leçon 0 que l'utilisateur de kind est `kubernetes-admin`, du groupe `kubeadm:cluster-admins`. `kind`, de son côté, crée des conteneurs privilégiés dans ton Docker. Un binaire altéré de l'un ou de l'autre aurait accès à ton cluster entier et à ta machine. C'est pourquoi il ne suffit pas d'avoir « quelque chose qui s'appelle `kubectl` et qui fonctionne ». Il faut que ce soit **le** `kubectl` publié par le projet Kubernetes, dans la version que tu as demandée. La somme de contrôle est le moyen de le vérifier en une seconde.

La deuxième raison est la reproductibilité. Si ta collègue et toi installez « la dernière », chacune a celle qui était la dernière le jour où elle l'a téléchargée. Dans trois mois, une sortie du cours ne correspond plus à la tienne et personne ne sait pourquoi. Kubernetes sort une version mineure environ trois fois par an ([kubernetes.io, « Kubernetes Release Cycle »](https://kubernetes.io/releases/release/)). Figer la version transforme « chez moi, ça marche » en quelque chose que l'on peut comparer.

La troisième est celle que tu as vue dans la scène : **un cluster kind de trois nœuds dépend d'une limite du noyau** qui, sur Ubuntu et sur Mint, est basse par défaut. Si tu ne la relèves pas avant, kind ne te prévient pas. Il te dit que tout s'est bien passé.

La leçon suit cet ordre :

1. **Ce que tu vas installer** et où tourne chaque pièce (1.1).
2. **Figer la version** (1.2).
3. **Télécharger et vérifier la somme de contrôle**, avec l'erreur provoquée exprès (1.3).
4. **L'ajustement d'`inotify`** : mesurer, ajuster et voir ce que consomme le cluster (1.4).
5. **Le fichier du cluster**, avec l'image figée (1.5).
6. **Créer le cluster** avec un `kubeconfig` dédié (1.6).
7. **Contextes et `kubeconfig`** (1.7).
8. **Regarder le cluster** (1.8).
9. **Supprimer, recréer et récupérer** (1.9).

Voici la destination, la dernière commande de la leçon, après avoir supprimé le cluster et l'avoir recréé en 26 secondes :

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

## Les concepts

### 1.1 Ce que tu vas installer

#### 1.1.1 Les pièces

| Pièce | Ce que c'est | Où elle tourne | L'installes-tu ici ? |
|---|---|---|---|
| Docker Engine | le moteur qui exécute les conteneurs | ton Mint | non, tu l'as déjà grâce au cours de Docker |
| `kind` | un programme qui crée et supprime des clusters faits de conteneurs | ton Mint | **oui**, un seul binaire |
| image `kindest/node` | la « machine » de chaque nœud : Debian avec `systemd`, `kubelet` et `containerd` | dans Docker | non, `kind` la télécharge la première fois |
| `kubectl` | le client qui parle au `kube-apiserver` | ton Mint | **oui**, un seul binaire |
| le cluster | trois conteneurs avec Kubernetes à l'intérieur | dans Docker | tu le **crées** avec `kind` |

Les deux choses que tu installes sont **un fichier chacune**. Ni `kubectl` ni `kind` n'apportent de bibliothèques, de services ou de *daemons*. Ce sont des binaires Go que l'on copie dans un dossier du `PATH`, et c'est tout. C'est pourquoi l'installation est courte, et c'est pourquoi il vaut mieux la faire manuellement : tu vois exactement ce qui entre dans ton système.

#### 1.1.2 Pourquoi pas avec `apt` ou `snap`

Ubuntu, et donc Mint, propose `kubectl` via `snap`, et il existe des dépôts `apt` du projet Kubernetes. Ils fonctionnent, mais ils posent un problème pour ce cours : **ils choisissent la version à ta place** et la mettent à jour selon leur propre calendrier. Un `snap` se met à jour tout seul en arrière-plan. Un dépôt `apt` te fait changer de version au prochain `apt upgrade`. Dans un cours où chaque sortie est comparée à la tienne, tu veux que la version change **quand tu le décides**. La page officielle d'installation de `kubectl` propose le binaire direct comme première option, et c'est celui qu'on utilise ici ([kubernetes.io, « Install and Set Up kubectl on Linux »](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)). Le guide de démarrage rapide de kind fait de même avec le binaire publié pour chaque version ([kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/)).

### 1.2 Figer la version

#### 1.2.1 Les versions du cours

| Outil | Version | D'où |
|---|---|---|
| `kubectl` | **v1.37.1** | `dl.k8s.io`, le site de téléchargement du projet Kubernetes |
| `kind` | **v0.33.0** | la version v0.33.0 publiée sur GitHub (`kubernetes-sigs/kind`) |
| image du nœud | `kindest/node:v1.37.0` avec son empreinte | les notes de la version v0.33.0 de kind |

Le guide officiel de `kubectl` utilise une astuce : il demande quelle est la version stable à `https://dl.k8s.io/release/stable.txt` et télécharge celle-là. Le 21 octobre 2026, ce fichier indiquait `v1.37.1`, la même que celle du cours. Mais **demain, il peut en indiquer une autre**, et la commande du guide en téléchargerait une autre sans te prévenir. C'est pourquoi les programmes de cette leçon écrivent la version complète dans l'adresse, sans rien demander.

#### 1.2.2 Pourquoi `kubectl` 1.37.1 avec un cluster 1.37.0 ?

Ce sont deux numéros différents, et la Leçon 0 les a déjà distingués. Le cluster exécute ce qu'apporte l'image du nœud, `v1.37.0`. `kubectl` est l'outil de ta machine. La politique officielle est claire : « tu dois utiliser une version de `kubectl` dont l'écart avec ton cluster ne dépasse pas une version mineure. Par exemple, un client v1.37 peut communiquer avec des plans de contrôle v1.36, v1.37 et v1.38 » ([kubernetes.io, « Install and Set Up kubectl on Linux »](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) ; [« Version Skew Policy »](https://kubernetes.io/releases/version-skew-policy/)). Le correctif, le troisième numéro, ne compte pas pour cette règle.

### 1.3 Télécharger et vérifier la somme de contrôle

#### 1.3.1 Ce qu'est une somme `sha256`

Une somme `sha256` est un nombre de 256 bits, qui s'écrit avec 64 caractères hexadécimaux (de `0` à `9` et de `a` à `f`), et qui se calcule à partir de **tous** les octets d'un fichier. Elle a deux propriétés qui la rendent utile. Elle donne toujours le même résultat pour le même fichier. Et si un seul octet change, on obtient un nombre complètement différent, sans ressemblance avec le précédent. Il n'existe aucun moyen pratique de fabriquer un autre fichier qui donne la même somme.

Le projet publie, à côté de chaque binaire, sa somme de contrôle. Tu télécharges les deux, tu calcules la somme du binaire que tu as reçu et tu la compares avec celle qui est publiée. Si elles correspondent, le fichier que tu as est, octet par octet, celui que le projet a publié avec cette somme. Sinon, quelque chose a changé en chemin : un téléchargement interrompu, un miroir pas à jour, un fichier d'une autre version ou un fichier altéré. Dans tous ces cas, **on n'installe pas**.

Il faut être honnête sur ce que la somme ne démontre pas. Le binaire et sa somme viennent du même site. Si quelqu'un contrôlait `dl.k8s.io` et changeait les deux, ils correspondraient. La somme te protège des corruptions et des téléchargements interrompus **entre** le site officiel et ton disque, ainsi que des mélanges de versions ou de fichiers dont tu ne te rendrais pas compte : si ce qui se trouve sur ton disque correspond à la somme, c'est ce que le site a publié. Elle ne te protège pas d'un binaire qui vient d'un site qui n'est pas le site officiel : le « `kubectl` qui marche chez moi » arrivé par messagerie n'a pas de somme, ou en a une que tu ne peux confronter à rien. C'est pourquoi l'origine compte autant que la somme.

#### 1.3.2 Le programme qui télécharge et vérifie

`fig01_01.sh` effectue le téléchargement et la vérification des deux binaires, avec la version écrite dans le script lui-même. Il n'installe rien et ne demande pas `sudo`. Il laisse les fichiers dans le dossier que tu lui indiques.

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

Trois détails, de haut en bas :

- **`set -euo pipefail`** fait que le script s'arrête à la première commande qui échoue. Si la somme ne correspond pas, `sha256sum` se termine avec le code 1 et le script s'arrête là, avant de télécharger `kind` et avant le `wc -c` final.
- **`curl -fsSL`** : `-f` fait qu'une erreur du serveur (un 404 parce que tu as mal écrit la version) devient un échec, et non un fichier d'erreur enregistré sous le nom du binaire. `-L` suit les redirections, que GitHub utilise pour tous ses téléchargements. `-sS` fait taire la barre de progression mais laisse voir les erreurs.
- **Deux formats de somme.** Le `kubectl.sha256` du projet Kubernetes ne contient que les 64 caractères. C'est pourquoi le guide officiel construit la ligne « somme, deux espaces, nom » avec `echo` et la passe à `sha256sum --check`. Le `.sha256sum` de kind contient déjà la ligne complète, et `sha256sum --check` le lit directement.

#### 1.3.3 L'exécution

**Exécution réelle · Mac** (le dossier temporaire a été supprimé à la fin) :

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

Ce qui compte, ce sont les deux `OK`. Note aussi les deux sommes : si dans un mois tu télécharges de nouveau les mêmes binaires dans les mêmes versions, tu dois obtenir **exactement** celles-ci. Si tu en obtiens d'autres, ce n'est pas la même version ou ce n'est pas le même fichier. Le `wc -c` final a indiqué que `kubectl` pèse 61 886 626 octets et `kind` 10 530 942.

Le guide de démarrage rapide de kind donne la commande de téléchargement du binaire, mais ne mentionne pas la somme de contrôle ([kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/)). La version v0.33.0 publie pourtant un `.sha256sum` pour chaque binaire (Linux `amd64` et `arm64`, macOS et Windows), et on le voit dans la liste des fichiers de [sa page de publication](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0). Que le guide ne le demande pas ne veut pas dire que ce n'est pas nécessaire. Ce cours le demande.

#### 1.3.4 L'erreur provoquée exprès : `FAILED`

`fig01_02.sh` provoque l'échec des deux façons dont il se produit réellement. Dans le premier cas, le binaire est d'**une autre version**, v1.37.0, et la somme de v1.37.1. C'est ce qui t'arrive quand tu télécharges le binaire avec la commande de `stable.txt` un jour et la somme un autre jour, ou quand tu copies l'adresse depuis un tutoriel et la somme depuis un autre. Dans le second, le binaire est le bon, mais avec **un octet de trop** à la fin, comme un fichier corrompu ou modifié par quelqu'un. **Exécution réelle · Mac** (`fig01_02.error-esperado.txt`) :

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

Cela se lit ainsi : `kubectl: FAILED` est le verdict sur ce fichier, et l'avertissement indique combien des fichiers vérifiés ne correspondaient pas (ici, un sur un). C'est le code de sortie 1 qui fait s'arrêter un script sous `set -e`. Le guide officiel montre d'abord le verdict, puis l'avertissement, et c'est ce que tu verras dans le terminal de ton Mint. La sortie ci-dessus vient du `sha256sum` de macOS, qui a affiché l'avertissement en premier. Les deux lignes passent par des canaux différents (la sortie standard et la sortie d'erreur), donc, quand tu les captures dans un fichier, leur ordre peut changer. Ce qui ne change pas, c'est le `FAILED` et le code de sortie 1.

Remarque ce que le message ne te dit **pas** : il ne distingue pas « une autre version » d'un « fichier altéré ». Les deux cas paraissent identiques. Et il est juste qu'il en soit ainsi : ce n'est pas à toi de découvrir lequel des deux s'est produit, mais de ne pas installer. Ce que tu fais face à un `FAILED` : tu supprimes le binaire et sa somme, tu vérifies que les deux adresses indiquent la même version et tu télécharges les deux de nouveau. Si l'échec se reproduit avec la même version, tu n'installes rien et tu cherches d'où tu es en train de télécharger.

#### 1.3.5 Installer

Sur ton Mint, l'installation tient en deux commandes, celle du guide officiel de `kubectl` et son équivalent pour `kind` :

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
sudo install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind
```

(Sur une machine ARM, le fichier de kind s'appelle `kind-linux-arm64`, les deux binaires sont différents et leurs sommes aussi : compare-les avec celles que publie chaque version, pas avec celles de cette leçon.)

`install` fait en une étape ce que feraient `cp`, `chown` et `chmod`. Il copie le fichier, lui donne `root` comme propriétaire (`-o root -g root`) et les permissions `0755` : tout le monde peut l'exécuter, seul `root` peut le modifier. Ce dernier point compte. Un binaire de ton `PATH` que ton utilisateur peut écraser est un binaire que n'importe quel programme qui s'exécute sous ton identité peut remplacer. Le guide de démarrage rapide de kind utilise `chmod +x` et `sudo mv`. Le résultat est presque le même, mais le fichier garde ton utilisateur comme propriétaire. `install` est plus propre, et c'est pourquoi le cours l'utilise pour les deux. `/usr/local/bin` est le dossier que Linux réserve aux programmes que tu installes toi-même manuellement, en dehors du gestionnaire de paquets. Il est déjà dans le `PATH` de Mint.

Comme rien n'a été installé sur le Mac, `fig01_03.sh` fait l'installation complète **dans un conteneur jetable** Ubuntu 24.04 pour `amd64`, avec les mêmes fichiers que ceux qu'a téléchargés `fig01_01.sh`. Les fichiers entrent par un `tar` sur l'entrée standard, sans monter de dossiers. Dans le conteneur, tu es déjà `root`, donc les `install` se font sans `sudo`. **Exécution réelle · Ubuntu 24.04 amd64** (`fig01_03.salida.txt`) :

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

Ici, la vérification utilise la commande du guide **à la lettre**, sans le `-` final, et le `sha256sum` de GNU affiche tout de même `OK`. Ensuite, trois vérifications que tu vas répéter sur ton Mint :

- **`ls -l`** : les permissions `-rwxr-xr-x`, le propriétaire `root root` et la taille, qui doit être la même que celle que tu as vue au téléchargement.
- **`command -v kubectl kind`** : quel fichier s'exécute réellement quand tu tapes le nom. Si tu avais un autre `kubectl` installé auparavant (via `snap`, par exemple), tu vois ici lequel l'emporte. La bonne réponse est `/usr/local/bin/kubectl`.
- **`kubectl version --client`** et **`kind version`** : les versions que tu as demandées. `--client` dit à `kubectl` de ne pas chercher de cluster, parce qu'il n'y en a pas encore. `Kustomize Version: v5.8.1` est l'outil de la Leçon 4, qui est fourni **dans** `kubectl` et ne s'installe pas séparément.

Un avertissement venu du Mac des exécutions lui-même. Là, dans le terminal interactif, `type kubectl` a répondu `kubectl: aliased to kubecolor` : un alias que quelqu'un avait configuré pour colorer la sortie. Les scripts ne voient pas les alias de ton terminal, donc ils exécutaient le vrai `kubectl`, mais ce que tu tapais manuellement passait par un autre programme. `command -v` ne révèle pas toujours un alias ; `type kubectl`, si. Si ta sortie ne ressemble pas à celle du cours, commence par là.

### 1.4 L'ajustement d'`inotify`

#### 1.4.1 Ce qu'est `inotify`

Beaucoup de programmes ont besoin de savoir qu'un fichier a changé sans le relire toutes les secondes. Linux leur fournit un mécanisme pour cela : « l'API `inotify` fournit un mécanisme pour surveiller les événements des systèmes de fichiers » ([man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html)). Un programme ouvre une **instance** d'`inotify` et lui ajoute des **surveillances** (*watches*), une par fichier ou par dossier. Le noyau le prévient quand quelque chose change.

Chaque instance et chaque surveillance occupent de la mémoire du noyau, si bien que le noyau impose deux plafonds, **par utilisateur** :

- `fs.inotify.max_user_instances` : « une limite supérieure au nombre d'instances `inotify` qui peuvent être créées par identifiant d'utilisateur réel ».
- `fs.inotify.max_user_watches` : la même chose pour les surveillances.

Sur un nœud Kubernetes, le `kubelet`, `kube-proxy`, `containerd` et les composants du plan de contrôle surveillent des fichiers en permanence : certificats, manifestes, configurations, journaux des conteneurs. Dans un cluster ordinaire, un nœud est une machine. Dans kind, **trois nœuds sont trois conteneurs sur le même noyau**, et presque tous leurs processus s'exécutent sous le même utilisateur, `root`. Les trois se partagent un seul plafond.

Le guide des problèmes connus de kind le formule ainsi : les limites « sont définies par les variables système `fs.inotify.max_user_watches` et `fs.inotify.max_user_instances`. Par exemple, sur Ubuntu, elles valent respectivement 8192 et 128, ce qui ne suffit pas pour créer un cluster avec de nombreux nœuds » ([kind, « Known Issues »](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files)). Et il donne les valeurs qu'il recommande : 524288 surveillances et 512 instances.

#### 1.4.2 Mesurer avant de toucher

L'ajustement se fait **avant** de créer le cluster, et on commence par mesurer. `fig01_04.sh` sans arguments se contente de lire ; avec `--ajustar`, il modifie ton système, et on le voit en 1.4.3 :

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

La nouveauté se trouve dans deux commandes de la mesure. La première **compte les instances ouvertes**. Chaque instance est un descripteur de fichier d'un processus, et dans `/proc/<pid>/fd/` ce descripteur apparaît comme un lien vers `anon_inode:inotify`. `find ... -lname` cherche exactement ces liens. Sans `sudo`, tu ne peux regarder que les descripteurs de tes propres processus ; avec `sudo`, tu vois ceux de tous les utilisateurs, même si le plafond se compte par utilisateur. La seconde, le `grep`, cherche **où la valeur a été écrite**, dans tous les dossiers que le système lit au démarrage. Elle cherche les lignes qui commencent par `fs.inotify`, qui sont celles qui fixent une valeur, et non les commentaires qui ne font que mentionner le mot.

Sur le Mac, le noyau qu'utilise Docker est celui de la machine virtuelle de Colima, c'est donc là qu'on a mesuré. **Exécution réelle · machine virtuelle** (`fig01_04.salida.txt`, mesure seulement, sans ajustement) :

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

Cette machine avait déjà 512 instances, et des surveillances à revendre. La différence entre 3 et 110 instances, c'est celle qui existe entre « sans `sudo` » et « avec `sudo` » : l'utilisateur normal en avait 3 ouvertes, et le système entier 110, avec un cluster kind d'une autre leçon qui tournait à ce moment-là. Ce nombre change avec tout ce qui est en cours d'exécution. Ce que l'on compare, c'est le plafond.

Et regarde le `grep` : **aucun fichier** des dossiers lus au démarrage ne fixe `inotify`. Le 512 est actif dans le noyau, mais il n'est écrit nulle part. La Leçon 0 raconte que cette même machine était à 128 et qu'on l'a montée à 512 pour son test ; le `grep` montre qu'on l'a montée sans laisser de fichier. Dans ce cas, le jour où la machine virtuelle redémarrera, elle reviendra à la valeur par défaut, et le prochain cluster de trois nœuds échouera sans explication. La mesure dit combien vaut la limite aujourd'hui ; le `grep` dit combien elle vaudra après un redémarrage. Il faut regarder les deux, et c'est pourquoi le script les regarde ensemble.

Sur ton Mint fraîchement installé, le plus probable est que tu voies `max_user_instances = 128` et que le script dise `FALTA AJUSTAR`. Linux Mint 22 est basé sur Ubuntu 24.04 ([Linux Mint, notes de la version 22](https://www.linuxmint.com/rel_wilma.php)), et Ubuntu est livré avec 128. Les surveillances, en revanche, peuvent être élevées chez toi : dans la machine virtuelle des exécutions, elle aussi un Ubuntu 24.04, le noyau donnait 1048576, bien au-dessus des 8192 que mentionne le guide de kind. Sur les noyaux récents, cette valeur dépend de la mémoire de la machine, si bien que ce qui manque presque toujours, ce sont les instances.

#### 1.4.3 Ajuster, et pour de bon

Le guide de kind propose deux façons. La **temporaire**, valable jusqu'à ton prochain redémarrage :

```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

Et la **persistante** : écrire les deux lignes dans `/etc/sysctl.conf`. Le cours fait la version persistante avec une variante : au lieu de modifier `/etc/sysctl.conf`, il place un fichier à lui dans `/etc/sysctl.d/`. Voici ce fichier, `99-kind-inotify.conf` :

```ini
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

Pourquoi un fichier à part ? Parce qu'« au démarrage, `systemd-sysctl.service` lit les fichiers de configuration » de `/etc/sysctl.d/*.conf`, entre autres dossiers ([man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html)). Tu as dans un seul fichier, avec son commentaire, ce que tu as changé et pourquoi, et pour l'annuler, tu le supprimes et tu redémarres.

Mais il y a un piège dans l'ordre. La même page dit que tous les fichiers sont triés par leur nom, quel que soit le dossier où ils se trouvent, et que si deux fichiers fixent la même chose, **c'est celui qui vient après qui l'emporte**. Le `99-` place le fichier du cours presque à la fin. Presque, parce qu'Ubuntu, et Mint avec lui, en fournit un autre. Mesuré dans la machine virtuelle des exécutions :

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

`99-sysctl.conf` est un lien vers `/etc/sysctl.conf`, et `99-sysctl.conf` vient après `99-kind-inotify.conf` dans l'ordre alphabétique (le `s` vient après le `k`). Donc, **si quelqu'un a mis une valeur d'`inotify` dans `/etc/sysctl.conf`, c'est cette valeur qui l'emporte** au redémarrage, et celle du cours ne sert à rien. C'est pourquoi `--ajustar` vérifie `/etc/sysctl.conf` et te prévient, et c'est pourquoi la mesure cherche dans tous les dossiers.

Sur ton Mint, l'ajustement se fait avec `sudo ./fig01_04.sh --ajustar`. **Avant de l'exécuter avec `sudo`, lis-le en entier, ainsi que `99-kind-inotify.conf`.** C'est la même habitude qu'avec les binaires : tout ce qui s'exécute en tant que `root`, tu l'as lu avant. Ce que tu vas trouver dans `ajustar` :

1. **Il ne baisse pas tes surveillances.** Si ton noyau en a déjà plus de 524288, le fichier qu'il installe ne contient pas la ligne `max_user_watches`, et il ne relève que les instances. Sans cette protection, l'ajustement de kind te **retirerait** des surveillances.
2. **Il n'écrase pas un fichier qui existe déjà.** Si `/etc/sysctl.d/99-kind-inotify.conf` existe avec un autre contenu, il te montre la différence et s'arrête.
3. Il copie le fichier avec `root` comme propriétaire et les permissions `0644`, le charge immédiatement avec `sysctl --load` (sans attendre un redémarrage), te prévient si `/etc/sysctl.conf` fixe aussi `inotify` et mesure de nouveau. Il doit se terminer par `LISTO`.

Le véritable ajustement n'a pas été appliqué sur la machine des exécutions : elle avait déjà 512, et c'était une machine partagée sur laquelle il n'y avait pas lieu de modifier quoi que ce soit. Ce qui a bien été testé, ce sont les deux protections, dans un conteneur jetable **non privilégié**, où `/proc/sys` est en lecture seule et où `sysctl` ne peut modifier le noyau de personne. **Exécution réelle · conteneur non privilégié** (`fig01_04.prueba-ajustar.txt`) :

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

La première exécution a vu 1048576 surveillances et a installé le fichier **sans** la ligne des surveillances : le `cat` le démontre. Le `permission denied` est attendu dans un conteneur non privilégié ; sur ton Mint, avec `sudo`, `sysctl --load` répond avec les lignes qu'il a chargées. La seconde exécution a trouvé un fichier avec un autre contenu et s'est arrêtée sans y toucher.

#### 1.4.4 Ce que consomme un cluster

Une fois le cluster créé (1.6), le script de la leçon regarde la limite **depuis l'intérieur** de chaque nœud, et compte les instances qu'ouvre chacun d'eux. **Exécution réelle · Mac**, extrait de `correr.salida.txt` :

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

Les trois nœuds indiquent 512 : ils n'ont pas de limite propre, ils voient **celle du noyau de la machine**. C'est le même indice que la colonne `KERNEL-VERSION` de la Leçon 0, cette fois avec un nombre qui compte. Et le décompte : 45 instances sur le nœud de contrôle et 18 sur chaque nœud de travail. Cela fait 81, avec le cluster **vide**, tout juste créé, sans un seul Pod à toi. Presque toutes appartiennent à des processus de `root`, et le plafond est par utilisateur : à ces 81 s'ajoutent celles que `root` a déjà ouvertes sur ta propre machine, que tu peux compter avec le `find` de `fig01_04.sh` exécuté avec `sudo`. Avec un plafond de 128, la marge est faible. Ce qui se passe au démarrage, quand les trois nœuds lancent leurs processus en même temps, n'a pas été mesuré ici ; la Leçon 0 en a vu le résultat : les nœuds de travail ne sont jamais arrivés. Avec 512, il y a largement la place pour ce cluster et pour un autre encore.

### 1.5 Le fichier du cluster

`kind create cluster` tout court crée un cluster d'un seul nœud appelé `kind`, avec l'image de nœud par défaut de cette version de kind. Le cours a besoin de trois nœuds, d'un nom à lui et de l'image figée, et cela s'écrit dans un fichier :

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

Il se lit de haut en bas. `kind: Cluster` et `apiVersion: kind.x-k8s.io/v1alpha4` disent qu'il s'agit de la configuration d'un cluster kind. Cela ressemble à un manifeste Kubernetes, mais ce n'en est pas un : ce fichier est lu par `kind`, jamais par le cluster. `nodes` est la liste des nœuds, un par entrée avec `role` : `control-plane` pour le plan de contrôle et `worker` pour les nœuds de travail. C'est la même forme que celle qu'utilise le guide de démarrage rapide de kind pour un cluster « de trois nœuds (deux de travail) » ([kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/)).

Et chaque nœud porte son `image` **avec son empreinte**. C'est la même habitude que la somme de contrôle des binaires, appliquée à une image. Le tag `v1.37.0` est un nom que celui qui publie l'image peut déplacer vers une autre. L'empreinte `sha256:a1ed…` est la somme du contenu. Le guide de kind le demande ainsi : « utilise la somme `sha256` de la version de Kubernetes que tu veux », telle que la publient les notes de chaque version ([kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/) ; [kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). Si quelqu'un remplace l'image par une autre, Docker ne l'accepte pas, parce que l'empreinte ne correspond plus.

Le nom du cluster ne figure pas dans le fichier, il va dans la commande : `--name curso-k8s-l1`. Ainsi, le même fichier permet de créer des clusters avec d'autres noms.

La commande cherche `kind-curso.yaml` au chemin que tu lui donnes. Les commandes de cette leçon supposent que tu te trouves dans `programas/01-instalacion-primer-cluster/`, où se trouve le fichier. Si tu copies le fichier dans un autre dossier, lance la commande depuis ce dossier ou écris le chemin complet dans `--config`.

### 1.6 Créer le cluster

#### 1.6.1 Un `kubeconfig` dédié au cours

Avant de créer quoi que ce soit, une décision de sécurité. Quand kind crée un cluster, **il écrit dans ton `kubeconfig`** l'adresse du cluster et l'identifiant d'administrateur, et en fait le contexte actif. Si tu ne lui dis rien d'autre, ce fichier est `~/.kube/config`. Si ce fichier contient déjà un cluster de ton travail ou d'un autre cours, kind change le contexte actif sans te demander ton avis.

C'est pourquoi, dans ce cours, kind écrit dans un fichier **temporaire et dédié**. Manuellement, dans ton terminal, cela donne ceci :

```bash
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l1.XXXX)/kubeconfig"
```

`mktemp -d` crée un dossier avec un nom que personne d'autre n'a. `export KUBECONFIG=…` fait que `kind` et `kubectl` utilisent ce fichier **dans ce terminal**, et dans aucun autre. Ton `~/.kube/config` n'est ni lu ni touché. Tu fermes le terminal et ta configuration habituelle reste exactement comme avant.

Ce qui ne disparaît **pas** quand tu fermes le terminal : le cluster, qui continue de tourner, et le dossier temporaire, avec l'identifiant d'administrateur à l'intérieur. De plus, en fermant, tu perds le chemin du `KUBECONFIG`. C'est pourquoi, si tu fais tout manuellement, avant de fermer :

```bash
kind delete cluster --name curso-k8s-l1
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp arriba.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l1.*/kubeconfig) rm -r -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

Le `case` ne laisse passer qu'un chemin ayant exactement la forme de celui qu'a créé `mktemp` ; si ton `KUBECONFIG` pointe ailleurs, par exemple vers ton `~/.kube/config` parce que tu as ouvert un autre terminal et que tu n'as pas répété l'`export`, il ne supprime rien et te dit pourquoi, au lieu d'emporter ton dossier `~/.kube` tout entier.

Si tu as déjà fermé, `kind get clusters` te dit ce qui est resté en vie, et `ls -d /tmp/curso-k8s-l1.*` quels dossiers sont restés. Le script de la leçon, `correr.sh`, fait tout cela tout seul : il crée son dossier temporaire et, en sortant, supprime le cluster et le dossier.

#### 1.6.2 Le script de la leçon

`correr.sh` parcourt tout le reste de la leçon : il crée le cluster, le regarde, joue avec les contextes, provoque les erreurs, le supprime, le recrée et, en sortant, le supprime de nouveau. Son en-tête explique ses trois protections, et ce sont les mêmes que tu vas utiliser dans tout le cours :

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

La troisième mérite une explication. `trap limpiar EXIT` dit à Bash : « quand ce script se termine, pour quelque raison que ce soit, exécute `limpiar` ». Si une commande échoue en cours de route et que `set -e` arrête le script, `limpiar` s'exécute quand même et supprime le cluster. Ainsi, il ne te reste pas un cluster oublié qui consomme de la mémoire. Mais `limpiar` ne supprime que si la variable `CREADO_AQUI` vaut `si`, et cette variable n'est activée **que si le `kind create cluster` de cette exécution s'est bien terminé**. S'il existait déjà un `curso-k8s-l1` auparavant, le script s'arrête au début et n'y touche pas : ce cluster n'est pas le sien. Et si un autre processus l'a créé un instant après cette vérification, le `create` du script échoue avec `node(s) already exist`, le script s'arrête et la variable reste à `no` : il n'y touche pas non plus.

La deuxième protection est une fonction courte, la même que dans la Leçon 0 :

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

Chaque `kubectl` qui parle au cluster passe par `k`, qui demande d'abord le contexte. Les `kubectl config`, qui se contentent de lire ou de modifier le fichier `kubeconfig` sans parler à aucun cluster, passent par une autre fonction, `kc`, sans vérification. Ils n'en ont pas besoin, et dans la section 1.7, le script change de contexte exprès.

#### 1.6.3 La création

Avant de créer quoi que ce soit, le script regarde le `kubeconfig` temporaire. Il est vide : il n'y a ni contextes ni contexte actif.

```text
$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]
```

Puis il crée le cluster. **Exécution réelle · Mac :**

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

Chaque paire de lignes correspond à une étape. *Ensuring node image* cherche l'image du nœud et, si elle n'est pas là, la télécharge ; la première fois sur ton Mint, cette étape prend le temps qu'il faut pour télécharger l'image, et les fois suivantes, elle est instantanée. *Preparing nodes* crée les trois conteneurs (un 📦 par nœud). *Writing configuration* écrit la configuration de `kubeadm`, l'outil officiel qui monte le cluster. *Starting control-plane* démarre le plan de contrôle. *Installing CNI* installe le réseau entre Pods, `kindnet`. *Installing StorageClass* installe le stockage par défaut. *Joining worker nodes* intègre les deux nœuds de travail au cluster. À la fin, `Set kubectl context to "kind-curso-k8s-l1"` est la ligne qui compte le plus pour toi dans cette leçon : kind a écrit le contexte dans ton `kubeconfig` (le temporaire) et l'a rendu actif. La phrase d'au revoir change au hasard à chaque exécution.

Avec l'image déjà téléchargée, la création a pris 23 secondes. Et maintenant, l'enseignement de la Leçon 0 : **la coche n'est pas la preuve**. La preuve comporte deux parties. La première consiste à attendre que les nœuds indiquent `Ready` :

```text
$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met
```

`kubectl wait` attend jusqu'à ce que tous les nœuds (`--all`) remplissent la condition `Ready`, ou jusqu'à ce que 240 secondes se soient écoulées. Mais il a un angle mort : il attend les nœuds qui **existent**. Dans l'échec de la Leçon 0, les nœuds de travail ne se sont jamais enregistrés ; dans ce cas, `kubectl wait --all` aurait attendu un seul nœud, aurait dit `condition met` une seule fois et se serait terminé sans erreur. C'est pourquoi la seconde partie consiste à **compter** :

```text
$ kubectl get nodes --no-headers | wc -l
3
```

`--no-headers` retire la ligne des titres et `wc -l` compte les lignes restantes : une par nœud. Le résultat doit être 3. Le script ne se contente pas de l'afficher : si ce n'est pas 3, il s'arrête avec `ALTO: el clúster tiene N nodos, no 3`. (Dans `correr.sh`, l'attente et le décompte viennent après l'examen du `kubeconfig`, dans la section 5 de sa sortie ; ici, on les présente ensemble parce qu'ils forment une seule et même preuve.)

### 1.7 Contextes et `kubeconfig`

#### 1.7.1 Ce que contient un `kubeconfig`

La documentation le définit ainsi : « un fichier utilisé pour configurer l'accès aux clusters est appelé fichier *kubeconfig*. C'est une manière générique de désigner les fichiers de configuration ; cela ne veut pas dire qu'il existe un fichier nommé `kubeconfig` » ([kubernetes.io, « Organizing Cluster Access Using kubeconfig Files »](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). Par défaut, `kubectl` en cherche un nommé `config` dans `$HOME/.kube`.

Un `kubeconfig` contient trois listes et un pointeur :

- **`clusters`** : à quelle adresse parler et avec quel certificat reconnaître le serveur.
- **`users`** : avec quel identifiant te présenter.
- **`contexts`** : des combinaisons nommées d'un cluster, d'un utilisateur et, éventuellement, d'un espace de noms. La documentation : « chaque contexte a trois paramètres : cluster, espace de noms et utilisateur. Par défaut, `kubectl` utilise les paramètres du *contexte courant* pour communiquer avec le cluster ».
- **`current-context`** : le pointeur. Lequel des contextes `kubectl` utilise quand tu ne lui en indiques pas un autre.

Le script le regarde juste après avoir créé le cluster :

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

Quatre choses à lire :

- **Le nom du contexte est `kind-` suivi du nom du cluster.** kind les nomme toujours ainsi : le cluster `curso-k8s-l1` donne le contexte `kind-curso-k8s-l1`, et le cluster par défaut `kind` donne `kind-kind`. Le cluster et l'utilisateur du `kubeconfig` portent le même nom.
- **`get-contexts`** est le tableau court. L'astérisque de `CURRENT` marque le contexte actif. `AUTHINFO` est l'utilisateur. Un `NAMESPACE` vide veut dire `default`.
- **`view --minify`** n'affiche que ce qu'utilise le contexte actif. L'adresse du serveur est `https://127.0.0.1:54589` : le port élevé que Docker a publié sur ta machine pour le `kube-apiserver` du nœud de contrôle, sur `127.0.0.1` par défaut. kind permet de changer cette adresse avec `networking.apiServerAddress`, mais sa documentation déconseille de l'exposer à autre chose que l'interface locale, et ce cours ne la change pas. Les trois champs `DATA+OMITTED` sont le certificat du serveur et **l'identifiant d'administrateur**. `kubectl` les masque parce que ce sont des secrets. Ils figurent en entier dans le fichier.
- **`stat -c %A`** donne les permissions du fichier : `-rw-------`, seul ton utilisateur peut le lire. kind le crée ainsi parce qu'il contient cet identifiant. Si un jour tu copies un `kubeconfig` ailleurs, conserve ces permissions. (Sur ton Mint, `ls -l "$KUBECONFIG"` dit la même chose, avec ton nom d'utilisateur.)

La documentation ajoute un avertissement qui vaut pour toujours : « n'utilise que des fichiers `kubeconfig` provenant de sources fiables. Un fichier `kubeconfig` spécialement conçu pourrait entraîner l'exécution de code malveillant ou exposer des fichiers. Si tu dois en utiliser un qui n'est pas digne de confiance, examine-le d'abord attentivement, comme tu le ferais pour un script *shell* ». Un `kubeconfig` peut demander l'exécution d'un programme pour obtenir l'identifiant : c'est pourquoi on le lit avant de l'utiliser.

#### 1.7.2 Deux contextes, et l'erreur sans message

La Leçon 0 a décrit l'erreur la plus dangereuse de `kubectl` : parler au mauvais cluster, sans que rien ne te prévienne. Le script la provoque exprès, uniquement dans le `kubeconfig` temporaire. Il ajoute un second contexte, `otro`, avec un identifiant factice et une adresse où il n'y a personne, `127.0.0.1:1`, et en fait le contexte actif :

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

Remarque l'ordre. Les trois `set-…` construisent un cluster, un utilisateur et un contexte qui les réunit, dans cet ordre. `get-contexts` montre les deux contextes, avec l'astérisque encore sur celui de kind. `use-context otro` déplace le pointeur. À partir de là, n'importe quel `kubectl` sans autre précision va vers `otro`. Voici ce que dit la vérification :

```text
$ (la comprobación del contexto, antes de un kubectl get nodes)
ALTO: el contexto activo es «otro», no «kind-curso-k8s-l1». No sigo.
[el guion NO corre kubectl get nodes: se detuvo a tiempo]

(Sin la comprobación, kubectl le habla a «otro»:)
```

Et ce qui se passe si tu ne vérifies pas :

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

Les lignes qui commencent par `E1021 … memcache.go:381` sont écrites par le client `kubectl` lui-même, pas par le cluster : le `E` est le niveau d'erreur, `1021` le mois et le jour, et `memcache.go` est le code avec lequel `kubectl` garde en mémoire la liste des ressources qu'offre un serveur. Avant d'exécuter ta commande, `kubectl` demande au serveur quelles ressources il possède, et ici cette question a échoué cinq fois parce que personne n'écoutait. C'est du bruit répété, et ce qui compte, c'est la dernière ligne.

Ici, on a eu de la chance, parce qu'`otro` n'existe pas et que l'erreur est bruyante. Lis la dernière ligne : elle dit **à quel serveur** il a essayé de parler, `127.0.0.1:1`, et ce n'est pas celui de ton cluster, qui était à `127.0.0.1:54589`. Si `otro` était un vrai cluster, la réponse aurait été une liste de nœuds qui ne sont pas les tiens, sans une seule erreur. L'exercice qui consiste à lire **à qui** tu as parlé est le même dans les deux cas.

Il existe un moyen de ne pas dépendre du pointeur : indiquer à chaque commande vers quel contexte elle va, avec `--context`.

```text
$ kubectl --context kind-curso-k8s-l1 get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

Avec `otro` actif, cette commande a parlé à kind, parce que l'option l'emporte sur le `current-context` du fichier. Selon la documentation, le contexte est choisi d'après « la première correspondance » de cette chaîne : d'abord l'option `--context`, ensuite le `current-context` des fichiers ([kubernetes.io, « Organizing Cluster Access… »](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). Dans des scripts partagés, mettre `--context` dans chaque commande est une protection aussi bonne que de vérifier le contexte avant. Le cours utilise la vérification parce qu'en plus, elle t'enseigne l'habitude.

Le script remet tout comme avant : il revient à `kind-curso-k8s-l1` avec `use-context` et supprime le contexte, le cluster et l'utilisateur factices avec `delete-context`, `delete-cluster` et `delete-user`. Chacun a répondu `deleted … from /tmp/curso-k8s-l1.LWx1/kubeconfig`. Cette ligne te dit aussi **quel fichier** a été modifié, et on y voit que c'était le temporaire.

#### 1.7.3 `KUBECONFIG` comme liste

Une chose de plus qu'il vaut mieux savoir, même si le cours ne l'utilise pas. `KUBECONFIG` peut contenir **plusieurs fichiers**, séparés par des deux-points sous Linux. `kubectl` les fusionne en un seul. Pour les valeurs qui se répètent, c'est le premier fichier qui les définit qui l'emporte. En particulier, le `current-context` retenu est celui du premier fichier qui en définit un ([kubernetes.io, « Organizing Cluster Access… »](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). Et quand `kubectl` crée une nouvelle valeur, il l'écrit dans le premier fichier de la liste qui existe ([kubernetes.io, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/)). C'est utile, et c'est un piège : avec deux fichiers dans la liste, un `use-context` peut modifier un fichier auquel tu ne t'attendais pas. Avec un seul fichier temporaire par cluster, comme dans ce cours, aucun doute possible.

### 1.8 Regarder le cluster

Une fois le contexte vérifié, le script regarde le cluster sous quatre angles. Premièrement, depuis Kubernetes :

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l1-control-plane   Ready    control-plane   31s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker          Ready    <none>          16s   v1.37.0   172.18.0.6    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0   172.18.0.7    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

Trois nœuds `Ready`, en version `v1.37.0`, avec le *runtime* `containerd://2.3.4`. Celui de contrôle a 15 secondes de plus que les deux autres : il a été créé en premier, et les nœuds de travail l'ont rejoint ensuite. La colonne `ROLES` indique `control-plane` pour l'un et `<none>` pour les nœuds de travail. Ce n'est pas une erreur : `ROLES` provient des étiquettes `node-role.kubernetes.io/…` de chaque nœud, et à la création du cluster, seul le nœud de contrôle en reçoit une (`control-plane`). `INTERNAL-IP` contient des adresses du réseau `kind` de Docker, `172.18.0.x`, qui seront différentes sur ta machine. Et `KERNEL-VERSION` indique le noyau de la machine qui exécute Docker, le même pour les trois.

```text
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:54589
CoreDNS is running at https://127.0.0.1:54589/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

`cluster-info` répond à la question « à quoi suis-je en train de parler ? » avec l'adresse du serveur. C'est la même que celle de `view --minify`. Si un jour tu as un doute sur ton contexte, cette commande te donne l'adresse réelle.

Deuxièmement, depuis kind et depuis Docker :

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

`kind get nodes --name` liste les conteneurs de **ce** cluster, sans ordre fixe. Il existe aussi `kind get clusters`, qui liste tous les clusters kind de ta machine : c'est utile pour savoir s'il y en a d'autres, mais ne t'en sers pas pour décider quoi supprimer sans lire chaque nom. `docker ps` avec le filtre sur le label `io.x-k8s.kind.cluster` montre les trois mêmes conteneurs. Un seul publie un port : celui de contrôle, `127.0.0.1:54589->6443/tcp`. C'est le chemin de `kubectl` vers le `kube-apiserver`, qui écoute sur le 6443 à l'intérieur du nœud. Les nœuds de travail ne publient rien, et personne en dehors de ta machine ne peut parler à ton cluster.

Troisièmement, ce qui tourne à l'intérieur, sans rien toucher :

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

Ce sont les pièces de la Leçon 0, désormais réparties sur trois nœuds. La colonne `NODE` le raconte. Le plan de contrôle (`etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`) vit uniquement sur le nœud de contrôle. De `kube-proxy` et de `kindnet`, il y en a **un par nœud**, trois de chacun : ce sont les pièces dont chaque machine a besoin pour le réseau. Et la colonne `IP` contient deux types d'adresse. Les Pods système qui utilisent le réseau du nœud ont l'adresse `172.18.0.x` de leur nœud. Les deux `coredns` ont des adresses `10.244.0.x`, celles du réseau **des Pods** qu'a mis en place `kindnet`. La Leçon 3 y revient.

Quatrièmement, le stockage que kind a installé :

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  29s
```

Une classe de stockage, `standard`, marquée comme celle par défaut. Elle garde les données sur le disque du nœud lui-même. C'est la ligne `Installing StorageClass` de la création, et la Leçon 8 l'utilise.

### 1.9 Supprimer, recréer et récupérer

#### 1.9.1 Perdre le contexte

Cela arrive plus souvent que tu ne le crois : quelqu'un fait le ménage dans son `kubeconfig`, ou supprime un contexte en pensant à un autre. Le cluster est toujours en vie, mais `kubectl` ne sait plus comment l'atteindre. Le script provoque cette situation :

```text
$ kubectl config delete-context kind-curso-k8s-l1
warning: this removed your active context, use "kubectl config use-context" to select a different one
deleted context kind-curso-k8s-l1 from /tmp/curso-k8s-l1.LWx1/kubeconfig

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE
```

`kubectl` t'avertit que tu as supprimé le contexte **actif**. Le tableau est vide. Le cluster ne s'est rendu compte de rien : ses trois conteneurs tournent toujours. Ce qui a été perdu, c'est le chemin. kind sait le reconstruire, parce que le cluster garde sa propre configuration :

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

`kind export kubeconfig` réécrit le contexte du cluster dans le `kubeconfig` qu'indique `KUBECONFIG` et le rend actif. Son frère, `kind get kubeconfig --name curso-k8s-l1`, n'écrit rien : selon sa propre aide, il « affiche le kubeconfig du cluster » à l'écran. Un `kubeconfig` affiché est un identifiant affiché, donc cette commande ne s'exécute pas devant quelqu'un et sa sortie ne se colle pas dans une messagerie.

#### 1.9.2 Supprimer

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

Une seconde. Supprimer un cluster kind, c'est supprimer trois conteneurs, et kind retire en plus du `kubeconfig` ce qu'il y avait écrit : le contexte n'existe plus et le pointeur est resté vide. Si tu exécutais maintenant `kubectl get nodes`, tu verrais l'erreur `localhost:8080` que la Leçon 0 t'a appris à lire. `docker ps` avec le filtre ne renvoie rien.

**Toujours avec `--name`.** Sans cette option, kind supprime le cluster qui s'appelle `kind`, celui par défaut : « si tu omets `--name`, kind utilisera le nom de contexte par défaut, `kind`, et supprimera ce cluster » ([kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/)). Si tu as un cluster `kind` d'un autre cours, il disparaît.

Et une bizarrerie utile : supprimer un cluster qui **n'existe pas** n'est pas une erreur. Le script le fait exprès, juste après l'avoir supprimé :

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
```

Sans `Deleted nodes` et sans erreur. Le guide de kind l'explique : « par conception, demander la suppression d'un cluster qui n'existe pas ne renvoie pas d'erreur ». C'est pourquoi tu peux le mettre au début d'un script, « au cas où ». Mais cela veut aussi dire que si tu écris mal le nom, kind ne te prévient pas : il dit `Deleting cluster` et ne supprime rien. La ligne `Deleted nodes` est la preuve qu'il a supprimé quelque chose.

#### 1.9.3 Recréer

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

(Les étapes intermédiaires de kind, identiques à celles de 1.6.3, ont été omises ; elles figurent au complet dans `correr.salida.txt`.)

Vingt-six secondes, et le cluster est comme neuf, avec ses trois nœuds comptés. Cela change ta façon de travailler pour le reste du cours. Un cluster qui se refait en une demi-minute **ne se répare pas** : si tu l'as laissé dans un état que tu ne comprends pas, tu le supprimes et tu le recrées. Ce qui ne se perd pas, c'est ce qui se trouve dans des fichiers : `kind-curso.yaml` et, à partir de la Leçon 2, tes manifestes. C'est l'idée de la Leçon 0 appliquée au cluster entier : le fichier est la vérité.

À la fin, le script se termine et le `trap` supprime le cluster recréé et le dossier temporaire. Sur la machine des exécutions, après la sortie, `docker ps` ne montrait aucun conteneur de `curso-k8s-l1` et le dossier `/tmp/curso-k8s-l1.*` n'existait plus.

## L'erreur que tu vas voir

Cette leçon comporte trois erreurs avec message et une sans message.

**1. `ERROR: failed to create cluster: node(s) already exist`.** Créer un cluster avec un nom qui existe déjà :

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "curso-k8s-l1"
[código de salida: 1]
```

Cela se lit au pied de la lettre : il existe déjà des nœuds, c'est-à-dire des conteneurs, d'un cluster portant ce nom. kind ne le remplace pas et ne le répare pas. Avant de faire quoi que ce soit, demande-toi **à qui il appartient**. S'il est à toi, vestige d'une exécution précédente restée en vie, tu lances `kind delete cluster --name curso-k8s-l1` et tu le recrées. Si tu ne sais pas à qui il appartient, tu ne le supprimes pas : c'est le cas d'une machine partagée, et c'est pourquoi le script du cours s'arrête au lieu de le supprimer.

**2. `kubectl: FAILED`.** Tu l'as vu en 1.3.4 : la somme du binaire ne correspond pas à celle qui est publiée. On n'installe pas. On télécharge de nouveau le binaire **et** sa somme, avec la même version dans les deux adresses.

**3. `The connection to the server 127.0.0.1:1 was refused`.** Tu l'as vu en 1.7.2 : `kubectl` a parlé à un serveur où il n'y a personne. L'indice se trouve dans l'adresse de la dernière ligne. Compare-la avec celle de `kubectl cluster-info` de ton cluster : si elles ne correspondent pas, ton contexte n'est pas celui que tu crois. Si l'adresse est `localhost:8080`, il n'y a pas de contexte actif (Leçon 0).

**4. L'erreur sans message : les nœuds qui ne sont jamais arrivés.** Avec `max_user_instances = 128`, kind affiche toutes ses coches, y compris `✓ Joining worker nodes`, et pourtant les nœuds de travail ne rejoignent pas le cluster. Les journaux disent `inotify_init: too many open files`. Cette erreur **n'a pas été reproduite dans cette leçon** : il aurait fallu abaisser la limite d'une machine partagée sur laquelle d'autres clusters tournaient à ce moment-là, et l'abaisser les aurait fait planter. La Leçon 0 l'a déjà mesurée, en 0.6.3, avec ses vrais messages. Ici, on la prévient : on mesure et on ajuste avant (1.4), et après la création, on attend `Ready` avec `kubectl wait` et on **compte** les nœuds avec `kubectl get nodes --no-headers | wc -l`, parce que `wait` n'attend que ceux qui existent (1.6.3). Si le compte n'est pas 3, les indices laissés par la Leçon 0 sont au nombre de deux : `kubectl get pods -n kube-system` montre un `kube-proxy` à l'état `Error`, et `kubectl logs -n kube-system` de ce Pod dit `too many open files`. On supprime alors le cluster, on mesure et on ajuste `inotify` (1.4), et on le crée de nouveau.

## L'habitude de sécurité de la leçon

Le tableau des habitudes du cours en attribue trois à cette leçon :

**Binaires avec somme de contrôle.** Ce qui s'exécute avec ton utilisateur et avec `sudo` se télécharge depuis l'origine officielle, avec la version écrite et la somme vérifiée avant l'installation. Un binaire sans origine ni somme, comme celui qui arrive par messagerie, ne s'installe pas, même s'il « fonctionne ». Et il s'installe avec `root` comme propriétaire et les permissions `0755`, pour qu'aucun programme qui s'exécute sous ton identité ne puisse le remplacer.

**L'image du nœud figée.** L'image de chaque nœud est désignée par son empreinte, pas par son tag. C'est la même habitude que la somme de contrôle, appliquée à ce que télécharge Docker.

**Vérifier le contexte avant chaque commande qui modifie quelque chose.** Un `kubeconfig` temporaire dédié au cours, pour que kind ne change pas ton contexte habituel. `kubectl config current-context` avant d'agir, ou `--context` dans chaque commande. Et le `kubeconfig` traité comme ce qu'il est, un identifiant d'administrateur : permissions `600`, jamais dans une messagerie ni dans un dépôt, et seulement s'il provient de sources en qui tu as confiance.

Ce que les trois évitent ensemble, c'est la scène du début : ne pas savoir ce qui tourne sur ta machine, ni contre quel cluster.

## Ce qui se fait de travers

**Télécharger « la dernière ».** Un `curl` vers `latest` ou vers `stable.txt` te donne une version aujourd'hui et une autre demain. Les sorties du cours ne correspondent plus et tu ne sais pas pourquoi. On écrit la version.

**Télécharger le binaire et la somme séparément, avec des commandes différentes.** C'est le cas 1 de 1.3.4 : deux versions mélangées et un `FAILED` qui ressemble à une attaque. On les télécharge ensemble, avec la même version écrite une seule fois.

**Sauter la somme de contrôle « parce que c'est le site officiel ».** La somme vérifie ce qui est arrivé sur ton disque, pas ce qu'il y a sur le serveur. Un téléchargement interrompu pèse moins lourd, s'exécute parfois et échoue de façons étranges. La somme coûte une commande.

**Un `sudo mv` d'un binaire appartenant à ton utilisateur.** Il se retrouve dans le `PATH` avec ton utilisateur comme propriétaire, et n'importe quel programme qui s'exécute sous ton identité peut le remplacer. `install -o root -g root -m 0755`.

**Relever `inotify` avec `sysctl` et l'oublier.** Cela fonctionne jusqu'au prochain redémarrage. Ensuite, le cluster échoue et plus personne ne se souvient pourquoi. L'ajustement va dans un fichier de `/etc/sysctl.d/`, avec un commentaire.

**Créer le cluster dans ton `~/.kube/config` habituel.** kind change ton contexte actif sans demander. Le prochain `kubectl` que tu taperas dans une autre fenêtre, en pensant au cluster de ton travail, va parler à celui de kind, ou l'inverse. Un `KUBECONFIG` temporaire par cluster.

**`kind delete cluster` sans `--name`.** Il supprime le cluster `kind`, qui n'est peut-être pas le tien. Et comme supprimer un cluster qui n'existe pas ne provoque pas d'erreur, un nom mal écrit ne te prévient pas non plus. On lit la ligne `Deleted nodes`.

**Réparer un cluster kind.** Si tu l'as laissé dans un état que tu ne comprends pas, tu le supprimes et tu le recrées en une demi-minute. Ce qui compte vit dans des fichiers.

## Exercices

On répond aux exercices 1 et 2 avec les sorties de la leçon. Le 3 nécessite ton Mint avec `kubectl` et `kind` installés. Le 4 nécessite le cluster. Note tes réponses dans le [journal de bord](bitacora.md) avant de regarder les solutions.

### Exercice 1 — Qu'est-il arrivé à ce binaire ?

Une collègue a exécuté ceci et te demande de l'aide :

```text
$ curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256
$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

1. Donne une cause probable qui ne soit **pas** une attaque, et explique comment tu la vérifierais.
2. Que changerais-tu dans les deux commandes pour que cela n'arrive pas ?
3. Installe-t-elle le binaire pendant qu'elle cherche la cause ? Pourquoi ?

### Exercice 2 — Lis le `kubeconfig`

Avec la sortie de `kubectl config view --minify` de 1.7.1, réponds :

1. Quelle adresse et quel port `kubectl` utilise-t-il pour atteindre le cluster ? À quel autre endroit de la leçon ce port apparaît-il ?
2. Comment s'appellent le cluster, l'utilisateur et le contexte, et quel rapport ont-ils avec le nom que tu as donné à kind ?
3. Qu'y a-t-il derrière `DATA+OMITTED`, et pourquoi `kubectl` le cache-t-il ?
4. Si quelqu'un t'envoie son `kubeconfig` par messagerie « pour que tu voies mon cluster », que fais-tu avant de l'utiliser ?

### Exercice 3 — Prédis et mesure `inotify`

Sans rien exécuter, prédis ce que dira `./fig01_04.sh` sur ton Mint fraîchement installé, avant tout ajustement. Ensuite, exécute-le. Ajuste avec `sudo ./fig01_04.sh --ajustar` et exécute-le de nouveau sans arguments. Puis réponds :

1. Ta prédiction était-elle juste ? Quelles valeurs as-tu obtenues avant et après ?
2. Où l'ajustement a-t-il été écrit, et quelle commande te le démontre ?
3. Si tu redémarres la machine, quelle valeur attends-tu, et pourquoi ?

### Exercice 4 — Deux clusters, deux contextes (projet)

Dans un terminal avec un `KUBECONFIG` temporaire (1.6.1), crée le cluster du cours avec `kind-curso.yaml`. Dans **le même** `KUBECONFIG`, crée un autre cluster d'un seul nœud avec `kind create cluster --name curso-k8s-l1b` (sans fichier de configuration). Ensuite :

1. Lequel est resté comme contexte actif ? Prédis-le avant de regarder avec `kubectl config get-contexts`.
2. Sans changer le contexte actif, affiche les nœuds de **chaque** cluster.
3. Supprime **uniquement** `curso-k8s-l1b` et vérifie que le cluster du cours est toujours en vie et que tu peux de nouveau lui parler.
4. À la fin, supprime le cluster du cours et vérifie avec `docker ps` qu'il ne reste aucun conteneur de l'un ou de l'autre.

Quand tu l'auras fait manuellement, compare avec `programas/01-instalacion-primer-cluster/ejercicio4.sh`, qui fait les quatre étapes avec les protections de `correr.sh`, et avec sa sortie, `ejercicio4.salida.txt`. (Le second cluster utilise l'image de nœud par défaut de kind v0.33.0, sans empreinte : c'est un cluster jetable, pas celui du cours.)

## Solutions

### Solution 1

1. **Deux versions différentes.** Le binaire vient de ce qu'indiquait `stable.txt` à ce moment-là, et la somme est figée sur v1.37.1. Si `stable.txt` indique déjà une autre version, ce sont des fichiers de versions différentes et la somme ne peut pas correspondre. On le vérifie avec `curl -L -s https://dl.k8s.io/release/stable.txt` : s'il n'affiche pas `v1.37.1`, la cause est là. Une autre cause possible est un téléchargement interrompu ; `ls -l kubectl` comparé à la taille attendue (61 886 626 octets pour v1.37.1 en `amd64`) le montre.
2. Écrire la version **une seule fois**, dans une variable, et l'utiliser dans les deux adresses, comme `fig01_01.sh` : `KUBECTL_VERSION=v1.37.1`, puis `…/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl` et `…/kubectl.sha256`.
3. **Non.** Un `FAILED` ne dit pas si le fichier est d'une autre version ou s'il est altéré ; les deux cas paraissent identiques (1.3.4). Tant qu'une somme n'a pas affiché `OK`, le binaire n'entre pas dans `/usr/local/bin`.

### Solution 2

1. `https://127.0.0.1:54589`. Le même port apparaît dans `kubectl cluster-info` et dans la colonne `PORTS` de `docker ps` : `127.0.0.1:54589->6443/tcp`, le port que Docker a publié sur ta machine pour le `kube-apiserver`, qui écoute sur le 6443 à l'intérieur du nœud. Lors de ton exécution, ce sera un autre port.
2. Les trois s'appellent `kind-curso-k8s-l1` : `kind-` suivi du nom que tu lui as donné avec `--name`. kind les nomme toujours ainsi.
3. Le certificat avec lequel `kubectl` reconnaît le serveur (`certificate-authority-data`) et **l'identifiant d'administrateur** du cluster (`client-certificate-data` et `client-key-data`). `kubectl` les masque parce que quiconque possède ces données est administrateur du cluster.
4. Tu le lis en entier avant de l'utiliser, comme un script : la documentation avertit qu'un `kubeconfig` spécialement conçu peut exécuter du code. Tu l'utilises dans un `KUBECONFIG` temporaire, tu ne le mélanges pas avec le tien, et tu rappelles à la personne qui te l'a envoyé qu'elle vient de partager un identifiant.

### Solution 3

1. Ce à quoi il faut s'attendre sur Mint 22, basé sur Ubuntu 24.04 : `fs.inotify.max_user_instances = 128` et `FALTA AJUSTAR`. Les surveillances dépendent de ton système et de ta mémoire, elles peuvent donc différer des 8192 que mentionne le guide de kind pour Ubuntu. Après l'ajustement : 512 instances, au moins 524288 surveillances et `LISTO`. Dans la machine virtuelle des exécutions, elle aussi un Ubuntu 24.04, les surveillances étaient déjà à 1048576. Si ta première mesure a déjà affiché `LISTO`, quelqu'un a fait l'ajustement avant toi ; cherche où avec la question 2.
2. Dans `/etc/sysctl.d/99-kind-inotify.conf`. La preuve : `cat /etc/sysctl.d/99-kind-inotify.conf` et `grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/`, qui doit trouver les lignes de ce fichier (deux, ou seulement celle des instances si tes surveillances étaient déjà plus élevées) et aucune dans un autre. S'il en apparaît une autre dans `/etc/sysctl.conf`, c'est elle qui l'emporte au redémarrage (1.4.3).
3. 512 instances, et au moins 524288 surveillances : au démarrage, `systemd-sysctl` lit `/etc/sysctl.d/*.conf` et applique le fichier, sauf si `/etc/sysctl.conf` fixe une autre valeur. Si tu l'avais seulement relevé avec `sudo sysctl …`, il reviendrait à 128, comme cela se serait produit avec la machine virtuelle des exécutions.

### Solution 4

Les quatre réponses ont été mesurées avec `ejercicio4.sh` (`ejercicio4.salida.txt`).

1. **`kind-curso-k8s-l1b`**, le dernier créé : kind rend actif le contexte du cluster qu'il vient de créer. `get-contexts` montre les deux, avec l'astérisque sur `kind-curso-k8s-l1b`. C'est exactement le piège du contexte : le cluster du cours est toujours là, mais ce n'est plus à lui que tu parles.
2. Avec `--context`, qui l'emporte sur le contexte actif :

   ```bash
   kubectl --context kind-curso-k8s-l1 get nodes
   kubectl --context kind-curso-k8s-l1b get nodes
   ```

   La première commande affiche trois nœuds et la seconde un seul, `curso-k8s-l1b-control-plane`, avec `ROLES control-plane` et `v1.37.0`.
3. `kind delete cluster --name curso-k8s-l1b`. La commande doit afficher `Deleted nodes: ["curso-k8s-l1b-control-plane"]`. kind retire son contexte du `kubeconfig`, et le pointeur reste vide parce que c'était le contexte actif. `kubectl config get-contexts` ne montre que `kind-curso-k8s-l1`, sans astérisque. `kubectl config use-context kind-curso-k8s-l1` puis `kubectl get nodes` montrent les trois nœuds du cours.
4. `kind delete cluster --name curso-k8s-l1`, puis `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` et la même chose avec `curso-k8s-l1b`. Les deux réponses doivent être vides, et lors de l'exécution, elles l'ont été.

## Comment savoir que j'ai réussi

- [ ] `kubectl version --client` affiche `Client Version: v1.37.1` et `Kustomize Version: v5.8.1`, et `kind version` affiche `kind v0.33.0 go1.26.7 linux/amd64`.
- [ ] `command -v kubectl kind` affiche `/usr/local/bin/kubectl` et `/usr/local/bin/kind`, et `ls -l` les montre avec le propriétaire `root root` et les permissions `-rwxr-xr-x`.
- [ ] Tu exécutes `./fig01_01.sh` dans un nouveau dossier et tu obtiens `kubectl: OK` et `kind-linux-amd64: OK`, avec les deux sommes de 1.3.3 (sur une machine ARM, celles publiées pour `arm64`).
- [ ] `./fig01_04.sh` se termine par `LISTO`, son `grep` trouve les lignes de `/etc/sysctl.d/99-kind-inotify.conf` et aucune dans `/etc/sysctl.conf`.
- [ ] Tu exécutes `./correr.sh` et tu vérifies par rapport à `correr.salida.txt` ce qui ne change pas d'une exécution à l'autre : le `kubeconfig` vide au début ; les trois nœuds `Ready` et comptés (`3`) avec `v1.37.0`, `Debian GNU/Linux 13 (trixie)` et `containerd://2.3.4`, avec `ROLES <none>` pour les nœuds de travail ; un seul conteneur qui publie un port, `127.0.0.1:<port>->6443/tcp` ; la classe `standard (default)` ; `512` sur les trois nœuds ; l'`ALTO` de la vérification avec le contexte `otro` ; l'erreur `node(s) already exist` ; le contexte récupéré avec `kind export kubeconfig` ; `error: current-context is not set` après la suppression ; et trois nœuds `Ready` après la recréation. Les âges, les IP, le port, les suffixes des Pods, l'ordre des nœuds dans `kind get nodes` et `docker ps`, la phrase d'au revoir de kind, les durées, les décomptes d'`inotify` et le chemin temporaire changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] À la fin de `correr.sh`, `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` ne renvoie rien.

## Résumé

Réponds sans regarder la leçon :

1. Pourquoi le cours installe-t-il `kubectl` et `kind` sous forme de binaires et non avec `apt` ou `snap` ?
2. Que démontre une somme `sha256` qui correspond, et que ne démontre-t-elle pas ?
3. Quelles sont les deux causes courantes de `kubectl: FAILED`, et que fais-tu dans les deux cas ?
4. Qu'est-ce qu'`inotify`, et pourquoi trois nœuds de kind l'épuisent-ils alors qu'un seul nœud ne l'épuise pas ?
5. Quelle est la différence entre `sudo sysctl fs.inotify.max_user_instances=512` et un fichier dans `/etc/sysctl.d/` ?
6. Quelles trois listes et quel pointeur contient un `kubeconfig` ?
7. À quoi sert-il d'exporter `KUBECONFIG` vers un fichier temporaire avant de créer le cluster ?
8. Qu'est-ce qui l'emporte quand il y a `--context` dans la commande et un autre `current-context` dans le fichier ?
9. Que répond kind si tu supprimes un cluster qui n'existe pas, et pourquoi est-ce à la fois pratique et dangereux ?
10. Tu as perdu le contexte, mais le cluster est toujours en vie. Avec quelle commande le récupères-tu ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Install and Set Up kubectl on Linux »](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) : le téléchargement du binaire et de sa somme de contrôle, la vérification avec `sha256sum --check` et ses messages `OK` et `FAILED`, l'`install -o root -g root -m 0755` et la règle d'une version mineure d'écart au plus.
- [Kubernetes, « Version Skew Policy »](https://kubernetes.io/releases/version-skew-policy/) et [« Kubernetes Release Cycle »](https://kubernetes.io/releases/release/) : quelles versions de `kubectl` fonctionnent avec quel cluster, et le rythme des versions.
- [Kubernetes, « Organizing Cluster Access Using kubeconfig Files »](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) : ce qu'est un `kubeconfig`, ce qu'est un contexte, `KUBECONFIG` comme liste, les règles de fusion des fichiers, la façon dont le contexte est choisi et l'avertissement sur les fichiers de sources non fiables.
- [Kubernetes, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/) : les sous-commandes de `kubectl config` et l'ordre dans lequel `kubectl` charge les fichiers.
- [kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/) : l'installation à partir du binaire publié, la création avec `--name` et avec un fichier de configuration, l'image désignée par sa somme `sha256`, la suppression sans `--name` et le fait que supprimer un cluster inexistant n'est pas une erreur.
- [kind, « Known Issues », « Pod errors due to too many open files »](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files) : les limites d'`inotify`, les valeurs d'Ubuntu et celles qui sont recommandées.
- [kind v0.33.0, page de la version](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0) : les binaires avec leur `.sha256sum` et l'image de nœud `kindest/node:v1.37.0` avec son empreinte.
- [man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html) : ce qu'est `inotify` et ce que limitent `max_user_instances` et `max_user_watches`.
- [man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html) : les dossiers lus au démarrage et l'ordre dans lequel ils sont appliqués.
- [Linux Mint 22, notes de la version](https://www.linuxmint.com/rel_wilma.php) : Mint 22 est basé sur Ubuntu 24.04.

---

**Précédente :** [Leçon 0 — Ce qu'est Kubernetes et ce que kind n'est PAS](00-que-es-kubernetes.md) · **Suivante :** [Leçon 2 — Pods et Deployments](02-pods-deployments.md)
