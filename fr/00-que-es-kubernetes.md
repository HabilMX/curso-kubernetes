# Leçon 0 — Ce qu'est Kubernetes et ce que kind n'est PAS

Vendredi, 23 h 40. Le `revisor` tourne depuis trois semaines sur un seul serveur, lancé avec un `docker run --restart always` que quelqu'un a tapé un après-midi sans jamais l'écrire nulle part. À cette heure-là, le serveur s'éteint : une alimentation qui rend l'âme. Le conteneur meurt avec lui, et avec lui meurt le *daemon* de Docker, le seul qui savait le redémarrer. Le lundi à neuf heures, l'équipe d'exploitation a besoin du rapport d'état pour la réunion hebdomadaire et la page est blanche. Quelqu'un doit se réveiller, trouver une autre machine, se souvenir des variables d'environnement exactes, du port, du volume, de la version de l'image… et tout cela se trouvait dans l'historique du terminal du serveur qui ne s'allume plus.

Le problème n'était pas le conteneur. C'était que **personne, sauf quelqu'un qui dormait, ne savait dans quel état devait être le service**. Cette leçon porte sur l'outil qui existe pour que ce soit le système qui le sache, et pas toi à trois heures du matin.

**Durée :** 90 min

**Ce que tu construis :** rien pour l'instant. C'est une leçon de lecture : on y dresse la carte mentale grâce à laquelle le reste du cours devient prévisible

**Ce que tu apprends :** quel problème résout Kubernetes que Docker seul ne résout pas ; le plan de contrôle et les nœuds, pièce par pièce ; déclarer l'état souhaité et laisser le cluster l'atteindre (la boucle de contrôle) ; la carte de Docker à Kubernetes ; ce qu'est kind, ce que prouve un cluster kind et ce qu'il ne prouve pas ; et ce qu'un cluster local défend et ce qu'il ne défend pas

**D'où tu viens.** Du [cours de Docker](https://www.habil.mx/fr/cours/docker/) de Hábil, ou d'une pratique équivalente : tu sais construire une image, l'exécuter avec `docker run`, lui donner des variables d'environnement, un port et un volume, et en lancer plusieurs ensemble avec Compose. Tu apportes en outre le `revisor` déjà empaqueté : un serveur en Go qui écoute sur le port 8080, répond à `GET /salud` et `GET /api/estados`, et se configure par variables d'environnement. Ce que tu n'apportes pas, c'est la carte de **la façon dont pense un cluster**, qui est différente de celle de Docker et qui explique pourquoi les commandes des leçons suivantes sont ce qu'elles sont.

**Ce que cette leçon ne fait pas.** Elle n'installe rien (c'est la [Leçon 1](01-instalacion-primer-cluster.md)) et ne déploie pas le `revisor` (cela commence à la [Leçon 2](02-pods-deployments.md)). Elle propose un parcours réel dans un cluster kind, avec ses sorties, pour que tu voies de tes yeux ce que la leçon affirme. Il n'est pas nécessaire de comprendre chaque ligne de chaque sortie pour l'instant : ce qui compte, c'est **ce qu'elles racontent**. Si tu veux répéter le parcours, fais-le après la Leçon 1, quand tu auras `kubectl` et `kind`.

**À propos des exécutions.** Les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1 et l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, sur Docker Engine 29.2.1. La machine était un Mac à processeur ARM, avec Docker dans une machine virtuelle Linux (Colima), **pas** Linux Mint, qui est le système de référence du cours. Ce qui change sur ta Mint : la colonne `KERNEL-VERSION` indiquera ton noyau et `amd64` au lieu de `arm64`, les adresses IP et les ports seront différents, et les noms des Pods porteront d'autres suffixes aléatoires. Tout le reste doit être identique. Il y a eu une différence de plus, et elle est instructive : sur cette machine, un cluster de **trois** nœuds n'a pas démarré, parce que la limite de surveillance de fichiers du système était à 128 et s'est épuisée (la section 0.6.3 le raconte). C'est pourquoi le parcours utilise **un seul nœud** ; le cluster de trois nœuds du cours arrive dans la Leçon 1, qui ajuste d'abord cette limite. Le parcours complet se trouve dans [`programas/00-que-es-kubernetes/`](../programas/00-que-es-kubernetes) : `recorrido.sh` l'exécute du début à la fin en environ deux minutes et `recorrido.salida.txt` est sa sortie ; `ejercicio3.sh` et `ejercicio3.salida.txt` font de même avec l'Exercice 3.

## À la fin, tu seras capable de

- Expliquer à l'aide d'un exemple pourquoi `docker run --restart always` ne suffit pas à maintenir un service en vie lorsque la machine qui l'exécute tombe en panne.
- Nommer les pièces du plan de contrôle (`kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`) et celles de chaque nœud (`kubelet`, `kube-proxy`, le *runtime* de conteneurs), et dire ce que fait chacune en une phrase.
- Décrire étape par étape ce qui se passe dans le cluster entre un `kubectl apply` et un conteneur en cours d'exécution.
- Distinguer un ordre (`kubectl scale`) d'une déclaration (`kubectl apply -f`) et prédire ce qui se passe quand on les mélange.
- Traduire cinq concepts de Docker en leur équivalent dans Kubernetes, et en nommer un qui n'a pas d'équivalent.
- Dire ce qu'est kind, ce que démontre un cluster kind et ce qu'il ne démontre pas.
- Lire l'erreur `The connection to the server localhost:8080 was refused` et dire ce qu'elle signifie.

## Le pourquoi avant le comment

Avec Docker, tu as appris à répondre à la question « comment est-ce que j'exécute ce programme ? ». La réponse est une image et un `docker run`. C'est une excellente réponse, et Kubernetes ne la change pas : les images que tu as construites dans le cours de Docker sont exactement celles que le cluster va exécuter.

Mais il y a une autre question, qui apparaît dès qu'un service compte : **« qui se charge de faire en sorte qu'il continue de tourner ? »**. Avec Docker, la réponse est le *daemon* de cette machine, et seulement tant que cette machine est en vie. La documentation de Docker est claire : les politiques de redémarrage, comme `always` ou `unless-stopped`, s'appliquent aux conteneurs de ce *daemon* ([Docker, « Start containers automatically »](https://docs.docker.com/engine/containers/start-containers-automatically/)). Si la machine disparaît, il ne reste personne pour se souvenir que quelque chose y tournait.

Kubernetes répond à la seconde question. Tu lui dis **dans quel état doit être** ton service — « trois copies du `revisor`, avec cette image, avec cette configuration » — et il se charge de faire en sorte qu'il en soit ainsi, sur les machines dont il dispose, même si l'une d'elles tombe en panne. Cela change ton travail : tu cesses de donner des ordres (« démarre ceci », « redémarre cela ») et tu passes à l'écriture de **descriptions** de l'état que tu veux, que le cluster poursuit sans relâche.

Il y a une deuxième raison de commencer par la lecture et non par l'installation. Kubernetes comporte beaucoup de pièces aux noms étranges, et les messages qu'il va te donner dans les leçons suivantes (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) mentionnent ces pièces. Si tu ne sais pas qui est le *scheduler*, un Pod `Pending` est un mystère ; si tu le sais, c'est un indice. Et une troisième : dans ce cours, tu vas utiliser **kind**, un cluster qui vit à l'intérieur de Docker sur ta machine. C'est un excellent outil pour apprendre, mais si tu ne sais pas ce qu'il est, tu vas croire que ton cluster local démontre des choses qu'il ne démontre pas.

La leçon comporte huit parties, dans cet ordre :

1. **Le problème que résout Kubernetes** (0.1).
2. **Déclarer au lieu d'ordonner : la boucle de contrôle** (0.2), avec un vrai cluster qui répare ce que tu casses.
3. **Les pièces : le plan de contrôle et les nœuds** (0.3), vues de l'intérieur.
4. **Un ordre contre une déclaration** (0.4) : ce qui se passe quand tu les mélanges.
5. **La carte de Docker à Kubernetes** (0.5).
6. **Ce qu'est kind et ce qu'il n'est PAS** (0.6) : ce que ton cluster local démontre et ce qu'il ne démontre pas.
7. **Les versions** (0.7) : lesquelles utilise le cours et pourquoi.
8. **Ce qui vient dans le reste du cours** (0.8).

Avec ce plan en tête, voici ce que tu verras à la section 0.2. On a supprimé l'un des trois Pods et, une seconde plus tard, le cluster en avait déjà créé un autre à sa place sans que personne ne le lui demande. C'est l'idée centrale de toute la leçon :

```text
$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

## Les concepts

### 0.1 Le problème que résout Kubernetes

#### 0.1.1 De « exécuter un conteneur » à « maintenir un service »

Un conteneur est un processus avec son propre système de fichiers et son propre réseau, sur **une** machine. Un service que les gens utilisent a besoin de plus que cela :

- Qu'il y ait **plusieurs copies**, pour que la panne de l'une ne prive personne de service.
- Que ces copies soient sur des **machines distinctes**, pour que la panne d'une machine non plus.
- Que, si une copie meurt, **quelqu'un la remplace** sans attendre une personne.
- Que les autres programmes le **trouvent par son nom**, même si ses copies changent de machine et d'adresse.
- Que sa configuration puisse **changer sans reconstruire** l'image.
- Qu'une nouvelle version **remplace l'ancienne sans couper** le service.

Avec Docker et Compose, tu peux résoudre certaines de ces choses sur une seule machine. Aucune sur plusieurs. Kubernetes est l'outil qui résout les six, sur un groupe de machines qu'il appelle **cluster**.

La définition officielle est la suivante : Kubernetes est « une plateforme portable, extensible et open source permettant de gérer des charges de travail et des services conteneurisés, qui facilite aussi bien la configuration déclarative que l'automatisation » ([kubernetes.io, « Overview »](https://kubernetes.io/docs/concepts/overview/)). Remarque le mot *déclarative* : c'est celui qui compte, et la section 0.2 l'explique.

Deux précisions, pour qu'elles ne te prennent pas par surprise. Le nom vient du grec et signifie « timonier » ou « pilote », et l'abréviation **K8s** vient du compte des huit lettres qu'il y a entre le « K » et le « s ». Google a publié le projet en open source en 2014 (ces trois précisions figurent sur la même page officielle).

#### 0.1.2 Ce que Kubernetes n'est pas

La même page officielle consacre une section à ce que Kubernetes **ne fait pas**, et il vaut mieux la lire avant de commencer parce qu'elle évite les fausses attentes. Entre autres choses, Kubernetes ne construit pas ton application et ne déploie pas de code source (c'est toi qui apportes l'image, comme dans le cours de Docker), il n'inclut ni bases de données ni files de messages, et il n'impose pas de solution de journaux ni de surveillance. Et la phrase la plus importante : Kubernetes « n'est pas un simple système d'orchestration ». Orchestrer, au sens technique, c'est exécuter un flux défini : « d'abord A, puis B, puis C ». Kubernetes, en revanche, est « un ensemble de processus de contrôle indépendants et combinables qui amènent continuellement l'état actuel vers l'état souhaité ».

Cette dernière phrase est le résumé de cette leçon. La suite la démonte pièce par pièce.

### 0.2 Déclarer au lieu d'ordonner : la boucle de contrôle

#### 0.2.1 Le thermostat

La documentation de Kubernetes explique son idée centrale à l'aide d'un appareil que tu connais : un thermostat ([kubernetes.io, « Controllers »](https://kubernetes.io/docs/concepts/architecture/controller/)). Quand tu règles la température sur 22 degrés, tu indiques au thermostat ton **état souhaité**. La température qu'il fait dans la pièce est l'**état actuel**. Le thermostat allume ou éteint le chauffage ou la climatisation pour rapprocher l'état actuel de l'état souhaité. Tu ne lui dis pas « allume le chauffage dix minutes » ; tu lui dis « je veux 22 », et il décide quoi faire, encore et encore, tant qu'il est allumé.

C'est une **boucle de contrôle** : un cycle sans fin, qui observe, compare et corrige. Dans Kubernetes, chacune de ces boucles s'appelle un **contrôleur** : « les contrôleurs sont des boucles de contrôle qui surveillent l'état de ton cluster, puis effectuent ou demandent des modifications là où c'est nécessaire. Chaque contrôleur essaie de rapprocher l'état actuel du cluster de l'état souhaité ».

La conséquence pratique est celle que tu as vue dans la scène initiale, à l'envers. Avec Docker, la connaissance de l'état dans lequel devait être le `revisor` vivait dans la mémoire d'une personne. Avec Kubernetes, elle vit **dans le cluster**, par écrit, et un programme la compare en permanence avec la réalité.

#### 0.2.2 Un état souhaité, écrit dans un fichier

Dans Kubernetes, l'état souhaité s'écrit dans un **manifeste** : un fichier YAML qui décrit un objet. Voici le premier manifeste du cours. Il demande trois copies d'un conteneur :

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

Il n'est pas nécessaire de le comprendre en entier ; la Leçon 2 le démonte champ par champ. Pour l'instant, trois choses. `kind: Deployment` indique quel type d'objet c'est : un **Deployment** est la façon normale de demander « maintiens en cours d'exécution N copies de ce conteneur ». `replicas: 3` est l'état souhaité : trois copies. Et `template` est le moule de chaque copie : quelle image elle utilise et avec quelle étiquette (`app: espera`) on la reconnaît. Les deux blocs `securityContext` disent que le conteneur s'exécute sans être `root`, sans pouvoir gagner de privilèges et avec son système de fichiers en lecture seule ; ils sont ici parce que, dans ce cours, tout manifeste les comporte dès le premier, et la Leçon 2 explique chacun d'eux.

L'image, `registry.k8s.io/pause`, est un minuscule conteneur qui ne fait rien d'autre qu'attendre. Elle a été choisie parce qu'elle se trouve déjà à l'intérieur du nœud de kind (Kubernetes lui-même l'utilise en interne), de sorte que l'exemple ne dépend d'aucun téléchargement depuis internet.

#### 0.2.3 Ce que fait le cluster de ta déclaration

Le manifeste est remis au cluster avec `kubectl apply -f`. Voici ce qu'a répondu le cluster du parcours :

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera created

$ kubectl rollout status deployment/espera --timeout=90s
Waiting for deployment "espera" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 2 of 3 updated replicas are available...
deployment "espera" successfully rolled out
```

Lis attentivement la première réponse : `deployment.apps/espera created`. Elle ne dit pas « trois conteneurs démarrés ». Elle dit que l'objet Deployment a été **enregistré**. À cet instant, aucun conteneur ne tournait ; il y avait une description. La seconde commande, `rollout status`, attend et compte au fur et à mesure : zéro sur trois disponibles, une, deux, et à la fin « terminé ». Entre la première ligne et la dernière, le cluster a travaillé pour que la réalité rejoigne ce que tu as déclaré.

Maintenant, regarde ce qui en résulte :

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

Tu as demandé **un** objet et il y a **trois types** d'objet. C'est une chaîne, et il vaut mieux la voir ainsi dès le premier jour :

```text
Deployment espera            «quiero 3 copias de este molde»
   └── ReplicaSet espera-68b9d575f7       «hay que tener 3 Pods con este molde exacto»
         ├── Pod espera-68b9d575f7-9gbtr
         ├── Pod espera-68b9d575f7-cprg7
         └── Pod espera-68b9d575f7-gsrlf
```

Le **Deployment** est ce que tu écris. Le **ReplicaSet** est créé par le Deployment, et son seul travail est de compter : qu'il y ait autant de Pods que le dit `replicas`. Le suffixe `68b9d575f7` identifie le moule ; quand tu changeras l'image, dans la Leçon 2, un autre ReplicaSet apparaîtra avec un autre suffixe, et c'est ainsi que Kubernetes change de version sans coupure. Et le **Pod** est l'unité qui s'exécute vraiment : la documentation le définit comme « la plus petite unité déployable » de Kubernetes, « un groupe d'un ou plusieurs conteneurs, partageant le stockage et le réseau » ([kubernetes.io, « Pods »](https://kubernetes.io/docs/concepts/workloads/pods/)). Presque toujours, un Pod contient un seul conteneur ; dans ce cours, toujours.

Remarque aussi les noms des Pods : le suffixe final (`9gbtr`, `cprg7`…) est aléatoire. Lors de ton exécution, ce seront d'autres suffixes. C'est pourquoi, dans ce cours, on n'écrit jamais manuellement le nom d'un Pod : on le cherche par son étiquette, avec `-l app=espera`.

#### 0.2.4 Casser quelque chose exprès

Voici maintenant le test du thermostat. On a supprimé l'un des trois Pods, manuellement, comme s'il était mort :

```text
$ kubectl delete pod espera-68b9d575f7-9gbtr
pod "espera-68b9d575f7-9gbtr" deleted from default namespace

$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

Ils sont toujours trois. Le `9gbtr` n'est plus là, et il y en a un nouveau, `fjx8v`, âgé d'une seconde. Personne ne l'a demandé. Le ReplicaSet a vu que l'état actuel (deux Pods) ne correspondait pas à l'état souhaité (trois) et en a créé un. Le cluster garde une trace de ce qu'il fait dans ses **événements**, et on y voit toute l'histoire :

```text
$ kubectl get events --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp
LAST SEEN   TYPE     REASON             OBJECT                         MESSAGE
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-9gbtr
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-gsrlf
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-cprg7
1s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-fjx8v
```

Quatre créations : les trois du début et le remplacement. Les événements sont la première chose que l'on regarde quand quelque chose ne se passe pas comme prévu, et le cours les utilise dans chaque leçon.

Cela a une conséquence qui change la façon de travailler : **dans Kubernetes, supprimer un Pod n'arrête rien**. Si tu veux qu'il y ait moins de copies, tu changes l'état souhaité. Si tu n'en veux aucune, tu supprimes le Deployment. Supprimer le Pod fait seulement naître un autre Pod.

#### 0.2.5 Et quand c'est une machine qui tombe en panne

La scène du début n'était pas un conteneur qui meurt : c'était une machine qui s'éteint. Kubernetes couvre cela aussi, mais il vaut mieux savoir **combien de temps cela prend**, parce que ce n'est pas instantané. Quand un nœud cesse de répondre, le cluster le marque comme indisponible, et les Pods qui y tournaient y restent assignés un certain temps avant d'être remplacés sur un autre nœud. Ce temps est inscrit dans chaque Pod. On l'a lu sur le Pod du parcours :

```text
[{"effect":"NoExecute","key":"node.kubernetes.io/not-ready","operator":"Exists","tolerationSeconds":300},{"effect":"NoExecute","key":"node.kubernetes.io/unreachable","operator":"Exists","tolerationSeconds":300}]
```

Ce sont 300 secondes. La documentation le confirme : Kubernetes ajoute ces deux tolérances automatiquement, et elles signifient que les Pods « restent assignés aux nœuds pendant 5 minutes après la détection de l'un de ces problèmes » ([kubernetes.io, « Taints and Tolerations »](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)). Cette attente existe pour éviter de tout déplacer à cause d'une coupure réseau de dix secondes.

Alors le service est en panne pendant cinq minutes ? Non, si tu as fait ce que ce cours enseigne : **avoir plusieurs répliques réparties sur des nœuds distincts**. Pendant que celles du nœud en panne attendent leur remplacement, celles des autres nœuds continuent de répondre. Attention à une hypothèse trop commode : le Deployment veille à **combien** de répliques il y a, pas à **où** elles se trouvent. Par défaut, le `kube-scheduler` *s'efforce* de les répartir entre les nœuds, mais s'il ne le peut pas, il les entasse sur un seul (la documentation dit qu'il agit comme s'il avait la règle `whenUnsatisfiable: ScheduleAnyway`, « planifie quand même »). Pour **exiger** la répartition, le manifeste doit le déclarer avec `topologySpreadConstraints` ou avec de l'anti-affinité ([kubernetes.io, « Pod Topology Spread Constraints »](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)) ; le manifeste de cette leçon ne le fait pas, et le cours y revient lorsque le `revisor` devra survivre à un nœud éteint. C'est l'un des objectifs du cours : arrêter un nœud de travail et que le `revisor` continue de répondre.

### 0.3 Les pièces : le plan de contrôle et les nœuds

#### 0.3.1 Deux types de machine

Un cluster comporte deux types de machine, que Kubernetes appelle **nœuds** :

- Le **plan de contrôle** (*control plane*) : les machines où vit le « cerveau ». Elles gardent l'état souhaité, décident où s'exécute chaque chose et exécutent les contrôleurs.
- Les **nœuds de travail** (*worker nodes*) : les machines où s'exécutent tes conteneurs.

Dans un cluster de production, le plan de contrôle se trouve généralement sur trois machines dédiées, pour que la panne de l'une ne l'arrête pas. Dans le cluster de cette leçon, il y a **un seul nœud** qui fait les deux choses ; dans celui de la Leçon 1, il y en aura un de contrôle et deux de travail.

#### 0.3.2 Les pièces, une par une

Les définitions proviennent de la page officielle des composants ([kubernetes.io, « Kubernetes Components »](https://kubernetes.io/docs/concepts/overview/components/)) ; la colonne de droite est la traduction en ce que tu vois dans le cours.

| Pièce | Où elle vit | Ce qu'elle fait, selon la documentation | Ce que cela signifie pour toi |
|---|---|---|---|
| `kube-apiserver` | plan de contrôle | « le serveur qui expose l'API HTTP de Kubernetes » | c'est le seul point d'entrée : `kubectl` lui parle, et les autres pièces aussi |
| `etcd` | plan de contrôle | « magasin clé-valeur cohérent et hautement disponible pour toutes les données du serveur d'API » | c'est ici qu'est inscrit ton manifeste ; si `etcd` est perdu, l'état souhaité est perdu |
| `kube-scheduler` | plan de contrôle | « cherche les Pods qui ne sont pas encore assignés à un nœud et assigne chacun à un nœud approprié » | décide **où** s'exécute chaque Pod ; quand il ne trouve pas de place, le Pod reste `Pending` (Leçon 5) |
| `kube-controller-manager` | plan de contrôle | « exécute des contrôleurs pour implémenter le comportement de l'API de Kubernetes » | c'est ici que vivent les thermostats : celui des Deployments, celui des ReplicaSets, celui des nœuds… |
| `cloud-controller-manager` | plan de contrôle, optionnel | « s'intègre aux fournisseurs cloud sous-jacents » | dans kind, il n'existe pas ; c'est pourquoi un `LoadBalancer` a besoin d'aide (Leçon 6) |
| `kubelet` | chaque nœud | « s'assure que les Pods s'exécutent, y compris leurs conteneurs » | l'agent de chaque machine : il reçoit des Pods et en fait une réalité |
| `kube-proxy` | chaque nœud, optionnel | « maintient des règles réseau sur les nœuds pour implémenter les Services » | dirige le trafic qui arrive à l'adresse et au port d'un Service vers les Pods qui le servent à ce moment-là ; le nom du Service est résolu par le DNS du cluster, pas par lui (Leçon 3) |
| *runtime* de conteneurs | chaque nœud | « le logiciel chargé d'exécuter les conteneurs » | dans kind, c'est `containerd`, pas Docker |

#### 0.3.3 Les voir dans le cluster

Tout cela n'est pas de la théorie : cela se voit. Les composants du plan de contrôle tournent sous forme de Pods dans un espace de noms réservé, `kube-system` :

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

On y retrouve quatre des pièces du tableau : `etcd`, `kube-apiserver`, `kube-controller-manager` et `kube-scheduler`, chacune avec le nom du nœud collé à la fin. Il y a `kube-proxy`. Et il y en a trois que le tableau ne mentionne pas : `coredns` (deux copies), qui est le DNS interne du cluster et celui qui permet à un Pod d'en trouver un autre par son nom (Leçon 3) ; et `kindnet`, le réseau entre Pods que kind installe par défaut. Kubernetes n'apporte pas son propre réseau : c'est une extension appelée CNI qui le fournit, et chaque installation choisit la sienne. Le [guide de configuration de kind](https://kind.sigs.k8s.io/docs/user/configuration/) appelle le sien `kindnetd` et explique comment le remplacer ; la Leçon 7 y revient, parce que c'est du réseau que dépend le fait qu'une `NetworkPolicy` soit appliquée ou non.

Il manque une pièce dans la liste : le `kubelet`. Ce n'est pas un Pod. C'est un programme normal du nœud, et on le voit en regardant les processus **à l'intérieur** du nœud :

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

`kubelet` et `containerd` sont des processus du nœud. Les autres (`etcd`, `kube-apiserver`, etc.) sont des conteneurs que `containerd` a démarrés, et chaque `containerd-shim` est un petit processus auxiliaire qui surveille des conteneurs. Dans cette exécution, il y en a neuf, un par Pod, parce que le *shim* de `runc` regroupe dans un même processus les conteneurs d'un même Pod ; mais cette relation est décidée par le *runtime*, donc ne compte pas les Pods en comptant les *shims* ([containerd, « Runtime v2 »](https://github.com/containerd/containerd/blob/main/docs/runtime-v2.md)). (Le nom `kube-controller` apparaît coupé parce que `ps` n'affiche que les quinze premiers caractères du nom du programme.)

#### 0.3.4 L'œuf et la poule

Voici une énigme. Presque tous les Pods naissent de la même façon : un contrôleur (celui des ReplicaSets, par exemple) les inscrit dans le `kube-apiserver`, le `kube-scheduler` trouve ceux qui n'ont pas encore de nœud et en choisit un pour chaque Pod, et le `kubelet` de ce nœud les démarre. Le `kube-scheduler` ne crée pas de Pods : il les assigne ([kubernetes.io, « Kubernetes Scheduler »](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)). Mais le `kube-apiserver` est, lui-même, un Pod. Qui a démarré le Pod du serveur d'API avant que le serveur d'API n'existe ?

La réponse se trouve dans un dossier du nœud :

```text
$ docker exec curso-k8s-l0-control-plane ls /etc/kubernetes/manifests
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

Ce sont quatre manifestes, un par pièce du plan de contrôle. Le `kubelet` lit ce dossier directement, sans rien demander à personne, et démarre ce qu'il y trouve. Ces Pods sont appelés **Pods statiques** : c'est le `kubelet` qui les gère à partir de fichiers, et non le serveur d'API ([kubernetes.io, « Create static Pods »](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)). Ce que tu vois avec `kubectl get pods -n kube-system` est un reflet d'eux que le `kubelet` publie dans l'API pour que tu puisses les voir. C'est pourquoi leurs noms se terminent par le nom du nœud, et c'est pourquoi ils n'ont pas le suffixe aléatoire des Pods créés par un ReplicaSet.

Tu ne vas pas toucher à ce dossier dans ce cours. Mais tu sais maintenant pourquoi le plan de contrôle « démarre tout seul », et quelle question poser si un jour il ne le fait pas.

#### 0.3.5 Le voyage complet d'un `kubectl apply`

Avec les pièces sous les yeux, voici le parcours de ce qui s'est passé en 0.2.3, de bout en bout :

1. `kubectl` lit `fig00_02.deployment.yaml` et l'envoie au **`kube-apiserver`**, par HTTPS.
2. Le `kube-apiserver` vérifie qui tu es et si tu as la permission, valide l'objet et l'enregistre dans **`etcd`**. Il répond `deployment.apps/espera created`. Jusqu'ici, il n'y a pas un seul conteneur.
3. Le contrôleur de Deployments, à l'intérieur du **`kube-controller-manager`**, voit un nouveau Deployment sans ReplicaSet et en crée un.
4. Le contrôleur de ReplicaSets voit un ReplicaSet qui demande trois Pods et n'en a aucun, et crée trois objets Pod, encore sans nœud assigné.
5. Le **`kube-scheduler`** voit trois Pods sans nœud, en choisit un pour chacun et l'inscrit dans le Pod.
6. Le **`kubelet`** du nœud choisi voit qu'il a des Pods assignés, demande à **`containerd`** de démarrer les conteneurs, et rapporte leur état au `kube-apiserver`.
7. `kubectl rollout status`, qui interrogeait l'API, voit les trois Pods disponibles et écrit `successfully rolled out`.

Observe qu'aucune pièce ne donne d'ordres à une autre. Chacune surveille les objets qui l'intéressent et agit quand l'état actuel ne correspond pas à l'état souhaité. Si une pièce tombe en panne un moment, à son retour elle trouve ce qui est en attente et le fait. C'est pourquoi cette conception résiste aux pannes : il n'y a pas de chaîne d'appels qui se rompe au milieu.

### 0.4 Un ordre contre une déclaration

#### 0.4.1 Les deux façons de parler au cluster

`kubectl` te permet de travailler de deux façons, et la documentation les distingue avec soin ([kubernetes.io, « Kubernetes Object Management »](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/)) :

- **Ordres** (*imperative commands*) : tu dis au cluster quoi faire, avec un verbe. `kubectl create deployment`, `kubectl scale`, `kubectl delete`. Ils sont rapides, et la documentation les recommande « pour commencer ou pour une tâche ponctuelle ». Leur problème : ils ne laissent pas de trace. Le seul qui sache dans quel état se trouve l'objet est le cluster lui-même.
- **Déclarations** (*declarative object configuration*) : tu écris un fichier contenant l'état souhaité et tu le remets avec `kubectl apply -f`. Le fichier est conservé dans Git, relu avant d'être appliqué, et si le cluster est perdu, on l'applique de nouveau et tout redevient identique.

Ce cours utilise des déclarations pour tout ce qui compte. Les ordres n'apparaissent que pour regarder (`get`, `describe`, `logs`) et pour des expériences que l'on jette.

#### 0.4.2 Ce qui se passe quand on les mélange

La documentation comporte un avertissement bref et sérieux : « un objet Kubernetes doit être géré avec une seule technique ; mélanger les techniques sur le même objet produit un comportement indéfini ». Dans le parcours, on les a mélangées exprès, pour que tu voies l'un de ces comportements. D'abord, un ordre : passer de trois à cinq copies.

```text
$ kubectl scale deployment espera --replicas=5
deployment.apps/espera scaled

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/5     5            3           3s
```

Le cluster a obéi : il en veut maintenant cinq (`3/5` signifie « trois prêtes sur cinq souhaitées » ; les deux autres sont en train de démarrer). Mais le fichier `fig00_02.deployment.yaml` dit toujours `replicas: 3`. Maintenant, le cluster et le fichier **ne concordent plus**, et rien ne t'en avertit. Pour le voir, il existe `kubectl diff`, qui compare le fichier avec ce qu'il y a dans le cluster sans rien changer :

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

(Les trois premières lignes de la sortie ont été omises, car elles ne font que nommer deux fichiers temporaires avec des chemins qui changent à chaque exécution ; elles figurent au complet dans `recorrido.salida.txt`.)

C'est un *diff* comme celui de Git : la ligne avec `-` est ce qu'il y a dans le cluster, la ligne avec `+` est ce qu'il resterait si tu appliquais le fichier. L'information qui compte est `-  replicas: 5` / `+  replicas: 3` : si tu appliques le fichier, **les deux copies ajoutées par l'ordre sont perdues**. La ligne `generation` est un compteur qui augmente chaque fois que change l'état souhaité ; et la longue annotation, `last-applied-configuration`, est la copie que `kubectl apply` garde du dernier fichier que tu as appliqué, pour savoir quels champs sont « les siens ». (Un détail utile : `kubectl diff` renvoie le code de sortie 1 quand il trouve des différences, selon sa propre aide ; ce n'est pas un échec, c'est la réponse.)

On a appliqué le fichier :

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera configured

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/3     3            3           4s
```

Retour à trois. C'est le fichier qui a gagné, parce que `replicas` est un champ que le fichier déclare. La leçon n'est pas « les ordres sont mauvais » ; c'est que **si tu as un fichier, le fichier est la vérité**, et qu'un ordre qui le contredit dure jusqu'au prochain `apply`. Imagine que cet ordre ait été donné par une autre personne, de nuit, pour encaisser un pic de charge, et que le matin tu appliques le fichier sans regarder. C'est pourquoi, dans ce cours, avant d'appliquer sur quelque chose qui existe déjà, on regarde `kubectl diff`.

### 0.5 La carte de Docker à Kubernetes

Presque tout ce que tu sais de Docker a un équivalent dans Kubernetes. Ce n'est pas identique, mais la carte t'économise la moitié du cours :

| Dans Docker | Dans Kubernetes | Où on le voit dans le cours |
|---|---|---|
| une image | la **même** image | Leçon 2 (`kind load docker-image`) |
| `docker run` d'un conteneur | un **Pod** (et presque jamais seul : à l'intérieur d'un Deployment) | Leçon 2 |
| `--restart always` | le **Deployment** et son ReplicaSet, qui remplacent les Pods manquants sur un nœud où ils tiennent | Leçon 2 |
| `docker compose up --scale revisor=3` | `replicas: 3` dans le Deployment | Leçon 2 |
| `-p 8080:8080` | un **Service**, et `kubectl port-forward` pour tester depuis ta machine | Leçon 3 |
| le nom du service dans le réseau de Compose | le **DNS du cluster** : `revisor.<espacio>.svc` | Leçon 3 |
| `-e` et `--env-file` | **ConfigMap** et **Secret** | Leçon 4 |
| `HEALTHCHECK` dans le Dockerfile | **probes** de démarrage (*startup*), de disponibilité (*readiness*) et de vivacité (*liveness*) | Leçon 5 |
| `--memory` et `--cpus` | `resources.requests` et `resources.limits` | Leçon 5 |
| `--user`, `--read-only`, `--cap-drop ALL` | `securityContext` | Leçon 2 |
| un volume nommé | un **PersistentVolumeClaim** | Leçon 8 |
| un conteneur qui s'exécute et se termine | un **Job** ; planifié, un **CronJob** | Leçon 8 |
| le fichier `compose.yaml` | des manifestes YAML, assemblés avec **Kustomize** | Leçons 4 et 10 |

Et il y a des choses qui **n'ont pas d'équivalent** dans Docker, parce qu'elles n'ont de sens que lorsqu'il y a plusieurs machines et plusieurs personnes : le *scheduler* qui choisit la machine ; les **Namespaces**, qui séparent des équipes ou des projets au sein du même cluster ; les permissions par compte de service (**RBAC**) ; les politiques réseau entre Pods ; et la mise à l'échelle automatique selon la charge. Ce sont les Leçons 7 et 9.

Une question qui revient toujours : si les nœuds n'utilisent pas Docker, les images que tu as construites avec Docker fonctionnent-elles ? Oui. Kubernetes a cessé de parler directement à Docker Engine dans la version 1.24 ([kubernetes.io, contexte historique de dockershim](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/)), mais cela n'a pas touché aux images. Le blog officiel l'explique ainsi : « l'image que produit Docker n'est pas en réalité une image propre à Docker : c'est une image OCI », et `containerd` sait la télécharger et l'exécuter ([kubernetes.io, « Don't Panic: Kubernetes and Docker »](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/)). Le parcours le confirme : la colonne `CONTAINER-RUNTIME` du nœud indique `containerd://2.3.4`.

### 0.6 Ce qu'est kind et ce qu'il n'est PAS

#### 0.6.1 Kubernetes à l'intérieur de Docker

**kind** est le sigle de *Kubernetes IN Docker*. Son site le décrit en une phrase : « un outil permettant d'exécuter des clusters locaux de Kubernetes en utilisant des "nœuds" qui sont des conteneurs Docker », et ajoute qu'« il a été conçu principalement pour tester Kubernetes lui-même, mais peut être utilisé pour le développement local ou l'intégration continue » ([kind.sigs.k8s.io](https://kind.sigs.k8s.io/)).

Cette histoire de « nœuds qui sont des conteneurs » se voit sans artifice. Vu de Kubernetes, le cluster a un nœud :

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l0-control-plane   Ready    control-plane   25s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

Et vu de Docker, ce même nœud est un conteneur :

```text
$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l0 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l0-control-plane   kindest/node:v1.37.0   127.0.0.1:60004->6443/tcp
```

Le même nom, `curso-k8s-l0-control-plane`. L'image `kindest/node` embarque un système Debian complet, avec `systemd`, le `kubelet` et `containerd` : c'est une fausse « machine », transformée en conteneur. À l'intérieur d'elle, `containerd` exécute les conteneurs de tes Pods. Ce sont des conteneurs dans un conteneur. (Le filtre `--filter label=...` a été utilisé pour ne lister que les conteneurs de ce cluster ; s'il y a d'autres conteneurs sur ta machine, ils n'apparaissent pas.)

Remarque deux colonnes de `get nodes`. `OS-IMAGE` indique Debian, même si ton système est Mint : c'est le système **de l'image du nœud**. Mais `KERNEL-VERSION` indique le noyau **de la machine qui exécute Docker**, parce que les conteneurs n'apportent pas leur propre noyau : tous utilisent celui de l'hôte. Cette colonne est le premier indice de ce que kind n'est pas.

#### 0.6.2 Ce qu'un cluster kind démontre et ce qu'il ne démontre pas

kind exécute le vrai Kubernetes : le même `kube-apiserver`, le même `etcd`, le même *scheduler*, installés avec `kubeadm`, l'outil officiel ([conception de kind](https://kind.sigs.k8s.io/docs/design/initial/)). Parmi ses objectifs de conception figure le passage de tous les tests de conformité de Kubernetes. Tout ce que tu apprendras de l'**API** — Deployments, Services, ConfigMaps, *probes*, permissions — vaut tout autant dans un cluster de production.

Ce qui n'est pas identique, c'est **ce qu'il y a en dessous**. Ce tableau est celui qu'il vaut mieux garder sous la main pendant le cours :

| Ce que tu testes dans kind | Est-ce que cela le démontre ? | Pourquoi |
|---|---|---|
| Que tes manifestes sont valides et font ce que tu crois | **Oui** | c'est la même API et le même code de Kubernetes |
| Que tes Pods renaissent quand ils meurent | **Oui** | le contrôleur est le même |
| Que tes permissions (RBAC) et le niveau `restricted` fonctionnent | **Oui** | ils sont appliqués par le `kube-apiserver`, comme en production |
| Que ton service survit à la panne d'une machine | **En partie** | un `docker stop` sur un nœud y ressemble, mais les trois « nœuds » partagent ta machine, ton disque et ton noyau : si ton ordinateur tombe en panne, tout s'arrête |
| Que ta `NetworkPolicy` coupe le trafic | **Cela dépend** | elle est appliquée par le réseau (CNI), pas par Kubernetes ; la Leçon 7 le mesure en direct |
| Que ton service encaisse telle charge | **Non** | les nœuds se partagent ton processeur et ta mémoire ; les chiffres ne se transposent pas à une autre machine |
| Qu'un `LoadBalancer` te donne une IP publique | **Non** | kind n'inclut pas d'équilibreur de charge ; il faut une pièce à part ([Cloud Provider KIND](https://kind.sigs.k8s.io/docs/user/loadbalancer/)), et la Leçon 6 le vérifie |
| Que tes données sont en sécurité | **Non** | le stockage par défaut de kind (un provisionneur appelé `local-path-provisioner`, que kind installe à la création du cluster) garde les données dans le nœud lui-même, qui est un conteneur de ta machine ; la Leçon 8 mesure ce qui se perd et quand |
| Que le plan de contrôle tolère les pannes | **Non** dans ce cours | kind permet plusieurs nœuds de contrôle, mais sur une seule machine cela teste la configuration, pas la tolérance réelle |

Résumé honnête : **kind démontre que tu comprends Kubernetes ; il ne démontre pas que ton système est prêt pour la production.** La Leçon 10 se termine, précisément, par la liste de ce qu'il manque.

#### 0.6.3 Un exemple réel de « ils partagent ta machine »

L'affirmation « les nœuds partagent ton noyau » n'est pas un détail académique, et la préparation de cette leçon l'a démontré sans le vouloir. La première fois, on a essayé de créer le cluster avec trois nœuds, comme celui de la Leçon 1. `kind` a dit que tout s'était bien passé, y compris la ligne `✓ Joining worker nodes`. Mais `kubectl get nodes` n'affichait qu'un seul nœud, et le Pod de `kube-proxy` était à l'état `Error`. Son journal disait :

```text
"command failed" err="failed complete: fsnotify watcher init: too many open files"
```

Et le `kubelet` des nœuds de travail, à l'intérieur de son conteneur, s'arrêtait avec :

```text
"Failed to start cAdvisor" err="inotify_init: too many open files"
```

La cause : les programmes Linux qui surveillent les modifications de fichiers utilisent une ressource du **noyau** appelée `inotify`, et le noyau a une limite sur le nombre de surveillants que chaque utilisateur peut ouvrir. Sur cette machine, elle était à 128 (`fs.inotify.max_user_instances = 128`). Chaque nœud de kind démarre son propre `kubelet` et son propre `kube-proxy`, tous contre **le même noyau**, et à eux trois ils ont épuisé la limite. Avec un seul nœud, cela a suffi.

Le guide des problèmes connus de kind décrit exactement cela : Ubuntu fixe cette limite à 128, « ce qui ne suffit pas pour créer un cluster avec beaucoup de nœuds », et recommande de la monter à 512 ([kind, « Known Issues »](https://kind.sigs.k8s.io/docs/user/known-issues/)). Linux Mint 22 est basé sur Ubuntu 24.04 ([Linux Mint, notes de la version 22](https://www.linuxmint.com/rel_wilma.php)), il est donc probable qu'il se passe la même chose sur ta machine. C'est pourquoi la Leçon 1 ajuste cette limite **avant** de créer le cluster du cours. Et c'est pourquoi cette leçon utilise un seul nœud.

La preuve que c'était bien la cause : sur la même machine, on a monté la limite à 512 et on a recréé le cluster de trois nœuds, sans rien changer d'autre. Cette fois, les trois ont été prêts, chacun avec son `kube-proxy` en cours d'exécution (le script est `tres-nodos.sh` et sa sortie complète, `tres-nodos.salida.txt`) :

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l0-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l0-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l0-worker2         Ready    <none>          19s   v1.37.0
```

Deux leçons se dégagent de cela. La première : trois « machines » de kind sont trois processus sur une seule machine, et ils en partagent les limites. La seconde, plus générale : **une commande qui affiche « ✓ » ne prouve pas que le système est en bon état**. On regarde l'état (`kubectl get nodes`, `kubectl get pods -A`) avant de tenir quoi que ce soit pour acquis.

### 0.7 Les versions

Kubernetes sort une version mineure environ **trois fois par an** ([kubernetes.io, « Kubernetes Release Cycle »](https://kubernetes.io/releases/release/)), et maintient en même temps les trois plus récentes, chacune avec environ **un an** de correctifs ([kubernetes.io, « Releases »](https://kubernetes.io/releases/)). Voici ce que publiait cette page le 21 octobre 2026 :

| Version mineure | Dernier correctif | Fin de support |
|---|---|---|
| **1.37** | 1.37.1 | 28 octobre 2027 |
| 1.36 | 1.36.5 | 28 juin 2027 |
| 1.35 | 1.35.9 | 28 février 2027 |
| 1.34 | 1.34.12 | 27 octobre 2026 |

(La même page dit que « les trois plus récentes » sont maintenues et liste en même temps la 1.34 avec sa date de fin ; à cette date, il lui restait six jours.)

Le cours utilise **Kubernetes 1.37**, la plus récente. Il y a deux numéros différents qu'il vaut mieux ne pas confondre :

- **Le cluster exécute 1.37.0.** C'est la version qu'apporte l'image de nœud par défaut de kind v0.33.0. Dans `kubectl get nodes`, elle apparaît dans la colonne `VERSION` : `v1.37.0`.
- **`kubectl` est en 1.37.1.** C'est l'outil de ta machine. La politique officielle dit que `kubectl` fonctionne avec un serveur d'API jusqu'à **une version mineure** plus ancienne ou plus récente ([kubernetes.io, « Version Skew Policy »](https://kubernetes.io/releases/version-skew-policy/)) : avec un cluster 1.37, `kubectl` 1.36, 1.37 et 1.38 conviennent. La différence de correctif n'a pas d'importance.

Et un point de plus : **l'image du nœud est figée par son empreinte**. Les notes de la version v0.33.0 de kind publient, pour chaque version de Kubernetes, l'image avec son empreinte `sha256`, et indiquent qu'il faut l'utiliser pour obtenir l'image construite pour cette version de kind ([kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). C'est pourquoi le fichier de configuration du parcours l'écrit en entier :

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

Un tag comme `v1.37.0` peut être déplacée par qui publie l'image ; une empreinte, non. Si quelqu'un remplaçait l'image par une autre, l'empreinte cesserait de correspondre et le téléchargement échouerait. C'est la même habitude que la Leçon 1 applique aux binaires de `kubectl` et de `kind`.

### 0.8 Ce qui vient dans le reste du cours

Tout ce qui précède est mis en pratique dans les leçons suivantes. Chacune ajoute une pièce au `revisor` dans le cluster :

| Leçon | Ce qui s'ajoute | Quelle idée de cette leçon elle met au travail |
|---|---|---|
| 1 | Tu installes `kubectl` et `kind` et tu crées le cluster de trois nœuds | l'ajustement d'`inotify` de 0.6.3 ; les contextes et l'habitude de les vérifier |
| 2 | Le `revisor` comme Deployment | la chaîne Deployment, ReplicaSet et Pod de 0.2.3 |
| 3 | Un Service et son nom dans le DNS | `kube-proxy` et `coredns` de 0.3.3 |
| 4 | Configuration sans reconstruire | la carte de `-e` à ConfigMap de 0.5 |
| 5 | *Probes*, ressources et arrêt propre | le `kubelet` qui surveille et le *scheduler* qui laisse un Pod `Pending` |
| 6 | Publier vers l'extérieur | le `LoadBalancer` que kind n'inclut pas (0.6.2) |
| 7 | Espaces de noms, permissions et réseau | le réseau qui dépend du CNI (0.3.3 et 0.6.2) |
| 8 | Données et tâches | le stockage qui vit dans le nœud lui-même (0.6.2) |
| 9 | Mettre à l'échelle et mettre à jour sans coupure | un autre contrôleur, celui qui ajuste `replicas` pour toi |
| 10 | Tout en un seul `kubectl apply -k` | le fichier comme vérité (0.4) |

## L'erreur que tu vas voir

Cette leçon comporte une erreur principale, que tu vas voir dès que quelque chose ne sera pas connecté, et une erreur **sans message**, qui est plus dangereuse.

**L'erreur principale : `The connection to the server localhost:8080 was refused`.** À la fin du parcours, on a supprimé le cluster et on a essayé de l'utiliser :

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

Elle se lit de bas en haut, parce que la dernière ligne est le résumé : « la connexion au serveur `localhost:8080` a été refusée ; as-tu indiqué le bon hôte ou le bon port ? ». Les cinq lignes avec `E1021` sont des nouvelles tentatives, une par tentative de découvrir quels types d'objet existent ; elles disent la même chose et peuvent être ignorées.

L'indice se trouve dans la première commande : **il n'y a pas de contexte actif**. Un **contexte** est l'entrée du fichier de configuration de `kubectl` (le `kubeconfig`) qui indique à quel cluster parler et avec quel identifiant. `kind` en a ajouté un en créant le cluster et l'a retiré en le supprimant. Sans contexte, `kubectl` ne sait pas où aller et essaie une adresse par défaut, `localhost:8080`, où il n'y a personne. Le message ne veut pas dire « ton cluster est en panne » : il veut dire **« je ne sais pas quel est ton cluster »**. On le corrige en lui donnant un contexte, qui dans ce cours est toujours celui que crée `kind` (Leçon 1).

**L'erreur sans message : le mauvais contexte.** Imagine maintenant l'inverse : il y a bien un contexte, mais ce n'est pas celui que tu crois. Ton ordinateur a configuré un cluster de ton travail, de ton école ou d'un projet précédent, et c'est lui qui est actif. Tu tapes `kubectl delete deployment revisor` en pensant à ton kind. Le cluster répond `deployment.apps "revisor" deleted`, sans erreur, sans avertissement. Tu l'as supprimé **ailleurs**.

Cette erreur ne peut pas se lire parce qu'elle ne produit aucun message. On ne peut que la prévenir, avec une habitude : **avant chaque commande qui modifie quelque chose, `kubectl config current-context`**. Dans le parcours, la réponse a été celle-ci, et ce n'est qu'après l'avoir vue que l'on a continué :

```text
$ kubectl config current-context
kind-curso-k8s-l0
```

Le script `recorrido.sh` le fait tout seul : avant chaque `kubectl`, il compare le contexte actif avec `kind-curso-k8s-l0`, et s'il ne correspond pas, il s'arrête. De plus, il donne à kind un fichier `kubeconfig` propre et temporaire, de sorte qu'il ne touche même pas à ta configuration habituelle. Et il ne supprime que ce qu'il a créé lui-même : si au départ il existe déjà un cluster appelé `curso-k8s-l0`, il s'arrête sans y toucher, et s'il échoue à mi-chemin, en sortant il supprime uniquement le cluster que cette exécution a eu le temps de créer. La Leçon 1 t'apprend à faire la même chose manuellement.

## L'habitude de sécurité de la leçon : ce qu'un cluster local défend et ce qu'il ne défend pas

Le tableau des habitudes du cours en attribue une seule à cette leçon : **savoir ce qu'un cluster local défend et ce qu'il ne défend pas**. Le parcours a regardé trois choses.

**Première : le serveur d'API n'écoute que sur ta propre machine.**

```text
$ docker inspect curso-k8s-l0-control-plane --format 'privilegiado={{.HostConfig.Privileged}}  puerto_api={{json .NetworkSettings.Ports}}'
privilegiado=true  puerto_api={"6443/tcp":[{"HostIp":"127.0.0.1","HostPort":"60004"}]}
```

Le port 6443 du nœud, où répond le `kube-apiserver`, est publié sur `127.0.0.1` : l'adresse qui n'est joignable que depuis ton propre ordinateur. Personne sur ton réseau ne peut parler à ton cluster. Le guide de configuration de kind dit qu'on peut le changer, et le déconseille fortement : il recommande de laisser `127.0.0.1` « pour des raisons de sécurité » et de « ne pas exposer kind à autre chose que l'interface de bouclage locale » ([kind, « Configuration »](https://kind.sigs.k8s.io/docs/user/configuration/)). Ce qu'il défend : l'accès depuis l'extérieur.

**Deuxième : ton `kubeconfig` est le passe-partout.**

```text
$ kubectl auth whoami
ATTRIBUTE                                           VALUE
Username                                            kubernetes-admin
Groups                                              [kubeadm:cluster-admins system:authenticated]
```

(La ligne `Extra` contenant l'empreinte de l'identifiant a été omise ici ; elle figure dans `recorrido.salida.txt`.) L'utilisateur avec lequel tu travailles est `kubernetes-admin`, du groupe `kubeadm:cluster-admins` : **administrateur total** du cluster. L'identifiant vit dans le `kubeconfig`, dans les champs `client-certificate-data` et `client-key-data`, que `kubectl config view` masque avec `DATA+OMITTED` précisément parce que ce sont des secrets. Dans un cluster local, les dégâts possibles sont moindres, mais le `kubeconfig` reste un identifiant d'administrateur, et dans un vrai cluster il équivaut au mot de passe d'administrateur : dans les deux cas, on ne le copie pas dans une messagerie et on ne le pousse pas dans un dépôt. La Leçon 7 crée un compte aux permissions minimales pour le `revisor`, parce que le `revisor` ne doit pas avoir cette clé.

**Troisième : le nœud est un conteneur privilégié.** Le même `docker inspect` indique `privilegiado=true`. Pour qu'un conteneur puisse se faire passer pour une machine complète, avec son `systemd` et son propre `containerd`, il a besoin de presque tous les pouvoirs de l'hôte. Cela veut dire que **kind n'est pas une frontière de sécurité** : un cluster kind n'isole pas de ton ordinateur ce qui s'exécute dedans. Ce qu'il ne défend pas : ta machine face à ce que tu mets dans le cluster. C'est pourquoi, dans ce cours, seules des images que tu connais tournent dans kind : celle du `revisor`, celle du service de test et les images officielles de Kubernetes.

Les trois ensemble donnent la règle : un cluster kind est bien protégé **vers l'extérieur** et ne protège rien **vers l'intérieur**. C'est un laboratoire, pas un coffre-fort.

## Ce qui se fait de travers

**Supprimer un Pod pour « éteindre » quelque chose.** Le ReplicaSet le remplace en une seconde, comme tu l'as vu en 0.2.4. Pour éteindre, on change l'état souhaité (`replicas: 0`) ou on supprime le Deployment.

**Donner des ordres sur quelque chose qui est géré avec des fichiers.** Un `kubectl scale` ou un `kubectl edit` sur un objet qui vit dans Git dure jusqu'au prochain `apply`, et la personne suivante qui appliquera ne saura pas qu'il a existé. Si le changement vaut la peine, on le fait dans le fichier.

**Appliquer sans regarder `kubectl diff`.** C'est la seule façon de savoir ce qui va changer avant que cela ne change. Cela coûte une commande.

**Ne pas vérifier le contexte.** C'est l'erreur sans message de « L'erreur que tu vas voir ». Sur une machine avec un seul cluster, cela paraît inutile ; dès qu'il y en a deux, c'est la différence entre une expérience et un incident.

**Croire que kind démontre la production.** Que ton service encaisse dans kind la panne d'un « nœud » ne dit rien sur la façon dont il encaisse la panne d'une vraie machine, ni la charge réelle, ni un vrai disque. Kind démontre que tu comprends l'API.

**Se fier à la coche verte.** `kind create cluster` a dit `✓ Joining worker nodes` avec deux nœuds qui n'ont jamais réussi à rejoindre le cluster (0.6.3). Après avoir créé quelque chose, on regarde son état.

**Écrire manuellement le nom d'un Pod.** Le suffixe est aléatoire et change chaque fois que le Pod renaît. On cherche par étiquette (`-l app=...`).

**Copier un tutoriel sans regarder la date.** Kubernetes change trois fois par an. Ce qui a été retiré reste sur internet : des tutoriels qui installent Docker à l'intérieur des nœuds (dockershim a été retiré dans la 1.24) ou qui utilisent `ingress-nginx`, que le projet Kubernetes a retiré en mars 2026 : sans nouvelles versions ni correctifs de sécurité ([kubernetes.io, « Ingress NGINX Retirement »](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)). La Leçon 6 explique ce qu'on utilise à sa place.

## Exercices

Les exercices de cette leçon ne demandent pas de cluster. On répond au premier et au deuxième en lisant les sorties de la leçon ; au troisième **avant** d'exécuter quoi que ce soit, et on le vérifie après la Leçon 1 avec `ejercicio3.sh` ; le quatrième s'écrit avec tes propres mots. Note tes réponses dans le [journal de bord](bitacora.md) avant de regarder les solutions.

### Exercice 1 — La nuit du vendredi (projet)

Reviens à la scène du début. Pour chacune de ces choses qui ont été perdues avec le serveur, dis quel objet ou quelle pièce de Kubernetes l'aurait conservée ou résolue, en utilisant la carte de 0.5 :

1. Qu'il y ait trois copies du `revisor` et non une seule.
2. Que, lorsque la machine tombe en panne, quelqu'un relance les copies sur une autre.
3. Les variables d'environnement contenant la liste des services à vérifier.
4. Le port par lequel on lui parle.
5. « Comment il avait été lancé », qui vivait dans l'historique d'un terminal.

### Exercice 2 — Qui l'a fait ?

Pour chacun de ces faits du parcours, dis quelle pièce de 0.3 est responsable :

1. Le Deployment `espera` a été enregistré et `kubectl` a répondu `created`.
2. Le ReplicaSet `espera-68b9d575f7` est apparu.
3. Chacun des trois Pods a été assigné au nœud `curso-k8s-l0-control-plane`.
4. Les conteneurs des Pods ont démarré à l'intérieur du nœud.
5. À la suppression de `espera-68b9d575f7-9gbtr`, `espera-68b9d575f7-fjx8v` est apparu.
6. Le Pod `kube-apiserver-curso-k8s-l0-control-plane` existait avant qu'il n'y ait un serveur d'API pour le créer.

### Exercice 3 — Prédis avant d'exécuter

Sans rien exécuter, prédis ce que répond le cluster dans chaque cas. Après la Leçon 1, vérifie-le avec `programas/00-que-es-kubernetes/ejercicio3.sh`, qui crée un cluster de test, exécute les quatre cas et le supprime.

1. Le Deployment `espera` a `replicas: 3`. Tu supprimes **les trois** Pods avec `kubectl delete pods -l app=espera`. Combien de Pods y a-t-il dix secondes plus tard ?
2. Tu exécutes `kubectl scale deployment espera --replicas=1` puis `kubectl apply -f fig00_02.deployment.yaml`. Combien de répliques reste-t-il ?
3. Tu exécutes `kubectl delete deployment espera`. Que se passe-t-il avec le ReplicaSet et avec les Pods ?
4. Tu supprimes le cluster avec `kind delete cluster --name curso-k8s-l0` et tu exécutes `kubectl get pods`. Quel message attends-tu ?

### Exercice 4 — Kind en cinq phrases

Une collègue te demande : « si sur mon ordinateur portable le `revisor` dans kind survit à l'extinction d'un nœud, est-ce que je peux déjà dire qu'en production il survit aussi ? ». Réponds-lui en cinq phrases au maximum, en utilisant les mots *conteneur*, *noyau*, *API* et *production*. Sans regarder la leçon.

## Solutions

### Solution 1

1. **Trois copies :** le champ `replicas: 3` d'un **Deployment** ; le **ReplicaSet** qu'il crée est celui qui compte qu'il y en ait trois.
2. **Les relancer sur une autre machine :** le **ReplicaSet** remplace les Pods manquants, le **`kube-scheduler`** choisit un nœud en vie pour chacun et le **`kubelet`** de ce nœud les démarre. Avec l'attente de 300 secondes de 0.2.5, sauf s'il y a des répliques sur d'autres nœuds qui continuent de répondre entre-temps.
3. **Les variables d'environnement :** un **ConfigMap** (et un **Secret** si l'une d'elles est confidentielle), Leçon 4.
4. **Le port :** un **Service**, Leçon 3.
5. **« Comment il avait été lancé » :** le **manifeste**, enregistré dans un fichier et dans Git, et appliqué avec `kubectl apply`. C'est la réponse qui compte le plus : la connaissance cesse de vivre dans une personne ou dans un terminal et reste écrite. Le cluster la garde dans `etcd`, et toi dans ton dépôt, de sorte qu'on peut tout reconstruire même si le cluster entier est perdu.

### Solution 2

1. Le **`kube-apiserver`**, qui valide l'objet et l'enregistre dans **`etcd`**.
2. Le contrôleur de Deployments, à l'intérieur du **`kube-controller-manager`**.
3. Le **`kube-scheduler`**. (Dans un cluster d'un seul nœud, il n'y a pas grand-chose à choisir, mais c'est quand même lui qui prend la décision.)
4. Le **`kubelet`** du nœud, qui le demande au *runtime*, **`containerd`**.
5. Le contrôleur de ReplicaSets, à l'intérieur du **`kube-controller-manager`**. Il l'a laissé par écrit dans l'événement `SuccessfulCreate`.
6. Le **`kubelet`**, à partir du fichier `/etc/kubernetes/manifests/kube-apiserver.yaml` : c'est un **Pod statique** (0.3.4).

### Solution 3

Les quatre ont été mesurées avec `ejercicio3.sh` ; sa sortie complète se trouve dans `ejercicio3.salida.txt`.

1. **Trois.** Le ReplicaSet voit zéro Pod là où il doit y en avoir trois et en crée trois nouveaux, avec de nouveaux suffixes. Les supprimer tous ne change pas l'état souhaité. Lors de l'exécution, les trois supprimés étaient `khb2n`, `phxml` et `srfng`, et dix secondes plus tard il y en avait trois différents : `kcvgl`, `qbnbx` et `qz6pc`.
2. **Trois.** L'ordre est descendu à une, mais `replicas: 3` est dans le fichier, et `apply` l'impose de nouveau, comme en 0.4.2 avec cinq. Si avant l'`apply` tu exécutes `kubectl diff -f fig00_02.deployment.yaml`, tu vois `-  replicas: 1` / `+  replicas: 3`.
3. **Les trois niveaux sont supprimés.** Le ReplicaSet appartient au Deployment et les Pods au ReplicaSet ; quand on supprime le propriétaire, Kubernetes supprime ce qui dépend de lui. Cinq secondes plus tard, `kubectl get replicaset,pods -l app=espera` a répondu `No resources found in default namespace.` Ici, le service s'arrête bel et bien, parce que l'état souhaité disparaît.
4. `The connection to the server localhost:8080 was refused - did you specify the right host or port?`, précédé de plusieurs lignes `E…` de nouvelles tentatives. Kind a retiré le contexte en supprimant le cluster, et sans contexte `kubectl` essaie `localhost:8080`. Attention : le script utilise son propre `kubeconfig` dans lequel seul le cluster du cours existait. Si dans le tien d'autres clusters sont configurés, la réponse dépend de celui qui reste actif, et tu pourrais parler à un autre sans le savoir : c'est pourquoi on vérifie avec `kubectl config current-context` et on ne suppose pas.

### Solution 4

Une réponse possible : « Pas encore. Dans kind, chaque nœud est un *conteneur* sur ton ordinateur portable, donc les trois nœuds partagent ton disque, ta mémoire et ton *noyau* : en éteindre un ressemble à la perte d'une machine, mais si ton ordinateur portable tombe en panne, tout s'arrête. Ce que tu as bien démontré, c'est que ta configuration de l'*API* est correcte : les répliques, leur répartition et leur remplacement fonctionnent de la même façon dans n'importe quel Kubernetes. Pour l'affirmer de la *production*, il reste à le tester sur de vraies machines séparées, avec leur réseau, leurs disques et leur charge. Kind démontre que tu le comprends ; la production se démontre en production ».

## Comment savoir que j'ai réussi

- [ ] Tu expliques, avec la scène du vendredi, pourquoi `--restart always` ne suffit pas lorsque la machine tombe en panne.
- [ ] Tu dessines de mémoire le plan de contrôle et un nœud, avec leurs sept pièces, et tu dis ce que fait chacune en une phrase.
- [ ] Tu racontes les sept étapes de 0.3.5, du `kubectl apply` au conteneur en cours d'exécution.
- [ ] Tu sais pourquoi le `kube-apiserver` peut être un Pod sans que personne ne demande à l'API de le créer.
- [ ] Face à `kubectl scale` suivi de `kubectl apply`, tu prédis quel nombre de répliques il reste.
- [ ] Tu traduis au moins cinq concepts de Docker vers Kubernetes et tu en nommes un sans équivalent.
- [ ] Tu dis deux choses qu'un cluster kind démontre et trois qu'il ne démontre pas.
- [ ] Face à `The connection to the server localhost:8080 was refused`, tu dis ce que cela signifie sans le chercher.
- [ ] Après la Leçon 1, tu exécutes `programas/00-que-es-kubernetes/recorrido.sh` et tu vérifies par rapport à `recorrido.salida.txt` ce qui ne change pas d'une exécution à l'autre : un nœud `Ready` ; le Deployment à `3/3` et son ReplicaSet avec `3` souhaités, `3` actuels et `3` prêts ; trois Pods `Running` après en avoir supprimé un ; le `diff` qui montre `replicas: 5` contre `replicas: 3` ; l'utilisateur `kubernetes-admin` ; et l'erreur finale `localhost:8080`. Les noms générés, les âges, les IP, les ports, les événements, la progression de `kind` et de `rollout` et les chemins temporaires changent à chaque exécution : on les observe, on ne les compare pas.

## Résumé

Réponds sans regarder la leçon :

1. À quelle question répond Docker et à quelle question répond Kubernetes ?
2. Qu'est-ce qu'une boucle de contrôle ? Explique-le avec le thermostat.
3. Quelle différence y a-t-il entre un Deployment, un ReplicaSet et un Pod ?
4. Que répond `kubectl apply` quand il crée un Deployment, et pourquoi cette réponse ne veut-elle pas dire qu'il y a des conteneurs en cours d'exécution ?
5. Combien de temps Kubernetes attend-il avant de remplacer les Pods d'un nœud qui a cessé de répondre ? Pourquoi n'attend-il pas zéro ?
6. Qu'est-ce qu'un Pod statique et qui le démarre ?
7. Que se passe-t-il si tu donnes un ordre qui contredit ton fichier puis que tu appliques le fichier ?
8. Quel rapport le noyau de ta machine a-t-il avec le fait qu'un cluster de trois nœuds de kind ne démarre pas ?
9. Que défend un cluster kind et que ne défend-il pas ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Overview »](https://kubernetes.io/docs/concepts/overview/) : la définition de Kubernetes, l'origine du nom, l'abréviation K8s, l'année de sa publication et la liste de ce que Kubernetes n'est pas.
- [Kubernetes, « Controllers »](https://kubernetes.io/docs/concepts/architecture/controller/) : la boucle de contrôle, le thermostat et l'état souhaité face à l'état actuel.
- [Kubernetes, « Kubernetes Components »](https://kubernetes.io/docs/concepts/overview/components/) : les pièces du plan de contrôle et des nœuds, d'où proviennent les définitions du tableau de 0.3.2.
- [Kubernetes, « Pods »](https://kubernetes.io/docs/concepts/workloads/pods/) : la définition de Pod et pourquoi on ne les crée presque jamais seuls.
- [Kubernetes, « Create static Pods »](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) : les Pods statiques que le `kubelet` lit depuis un dossier.
- [Kubernetes, « Taints and Tolerations »](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) : les tolérances automatiques de 300 secondes.
- [Kubernetes, « Kubernetes Object Management »](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/) : ordres contre déclarations, et l'avertissement de ne pas les mélanger.
- [Kubernetes, « Releases »](https://kubernetes.io/releases/) et [« Kubernetes Release Cycle »](https://kubernetes.io/releases/release/) : les versions en vigueur, leur fin de support et le rythme de trois par an.
- [Kubernetes, « Version Skew Policy »](https://kubernetes.io/releases/version-skew-policy/) : quelles versions de `kubectl` fonctionnent avec quel serveur.
- [Kubernetes, « Dockershim: The Historical Context »](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/) et [« Don't Panic: Kubernetes and Docker »](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/) : pourquoi les nœuds n'utilisent plus Docker et pourquoi tes images continuent de fonctionner.
- [Docker, « Start containers automatically »](https://docs.docker.com/engine/containers/start-containers-automatically/) : les politiques de redémarrage de Docker.
- [kind](https://kind.sigs.k8s.io/), [sa conception initiale](https://kind.sigs.k8s.io/docs/design/initial/), [« Configuration »](https://kind.sigs.k8s.io/docs/user/configuration/), [« Known Issues »](https://kind.sigs.k8s.io/docs/user/known-issues/) et [« LoadBalancer »](https://kind.sigs.k8s.io/docs/user/loadbalancer/) : ce qu'est kind, pourquoi il a été conçu, l'adresse du serveur d'API, le réseau par défaut, la limite d'`inotify` et l'équilibreur de charge qu'il n'inclut pas.
- [Kubernetes, « Ingress NGINX Retirement: What You Need to Know »](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) : le retrait d'`ingress-nginx` en mars 2026.
- [kind v0.33.0, notes de la version](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0) : l'image de nœud par défaut et son empreinte.
- [Linux Mint 22, notes de la version](https://www.linuxmint.com/rel_wilma.php) : Mint 22 est basé sur Ubuntu 24.04.

---

**Suivante :** [Leçon 1 — Installer kubectl et kind ; ton premier cluster](01-instalacion-primer-cluster.md)
