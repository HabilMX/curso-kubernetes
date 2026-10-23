# Leçon 2 — Pods et Deployments

Lundi, 8 h 50 du matin. À 9 h 30, l'équipe a la démonstration du nouveau cluster, et ta part est la plus simple : que le `revisor` apparaisse en cours d'exécution, avec trois copies. L'image est sur ton portable depuis vendredi, construite et testée avec `docker run`. Tu écris le manifeste, tu l'appliques, et `kubectl` répond `deployment.apps/revisor created`. Tu respires. Tu demandes les Pods et les trois disent la même chose : `ImagePullBackOff`. Quelqu'un de l'équipe, sans lever les yeux, te dit : « supprime-le et réapplique-le ». Tu le fais. Même état. Tu le refais. Il est 9 h 05 et l'image est toujours là, dans ton `docker image ls`, à deux centimètres du cluster qui dit ne pas la trouver.

Supprimer et réappliquer ne pouvait servir à rien dans cette situation, parce que le cluster n'était pas perdu : il te disait exactement ce qui lui manquait. Cette leçon t'apprend à l'écouter, à lui donner ce qu'il demande et à comprendre quels objets naissent quand tu appliques un Deployment. Ainsi, quand quelque chose échouera à 9 h 05, tu sauras où regarder.

**Durée :** 2 × 45 min

**Ce que tu construis :** le `revisor` en cours d'exécution dans le cluster du cours, avec trois répliques qui renaissent quand elles meurent, durci dès le premier manifeste

**Ce que tu apprends :** pourquoi ton Docker et les nœuds du cluster ne partagent pas leurs images, et comment `kind load docker-image` les y amène ; l'`ErrImagePull` que l'on provoque à dessein et comment on le lit ; ce que sont un Pod, un ReplicaSet et un Deployment, et qui est propriétaire de qui ; les étiquettes et les sélecteurs ; ce qu'est un *rollout* (déploiement progressif) et à quoi ressemble son historique ; et le `securityContext` que porte tout conteneur de ce cours

**D'où tu viens.** De la [Leçon 1](01-instalacion-primer-cluster.md) : tu as `kubectl` et `kind` installés avec leur somme de contrôle, la limite d'`inotify` ajustée, et tu sais créer, regarder et supprimer le cluster de trois nœuds du cours. De la [Leçon 0](00-que-es-kubernetes.md), tu apportes la carte : le `kube-apiserver` enregistre ce que tu déclares, les contrôleurs le poursuivent, le `kube-scheduler` choisit un nœud et le `kubelet` démarre les conteneurs. Et du [cours de Docker](https://www.habil.mx/fr/cours/docker/), tu apportes l'image terminée du `revisor`, `curso-docker-revisor:1.6.0`.

**Ce que cette leçon ne fait pas.** Le `revisor` reste en cours d'exécution, mais personne ne peut encore lui parler : il n'y a ni nom stable pour le trouver ni moyen de l'atteindre depuis ta machine. C'est la [Leçon 3](03-services-dns.md), avec les Services et le DNS du cluster. On ne le configure pas non plus encore de l'extérieur : la liste des services qu'il vérifie est écrite dans le manifeste, et la [Leçon 4](04-configuracion-secretos.md) la sort dans un `ConfigMap`. Et le cluster ne sait pas encore si le `revisor` est sain ou seulement vivant : les probes arrivent dans la [Leçon 5](05-salud-recursos-apagado.md).

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1 et l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, dans le cluster de trois nœuds de la Leçon 1, que l'on appelle ici `curso-k8s-l2`. La machine était un Mac à processeur ARM avec Docker Engine 29.2.1 dans une machine virtuelle Linux (Colima), **pas** Linux Mint, qui est le système de référence du cours. Ce qui change sur ton Mint : l'architecture (`amd64` au lieu de `arm64`), les adresses IP des Pods, les suffixes aléatoires des noms de Pods et de ReplicaSets, les âges et le nœud où atterrit chaque réplique. Les commandes sont les mêmes. Le parcours complet se trouve dans [`programas/02-pods-deployments/`](../programas/02-pods-deployments) : `correr.sh` crée le cluster **sans** l'image du `revisor`, parcourt la leçon dans l'ordre, exécute les Exercices 1 à 3 et supprime le cluster ; il a duré 2 minutes et 25 secondes, mesurées avec l'horloge du terminal ; le script enregistre de lui-même la durée de chaque étape longue : créer le cluster et attendre qu'il soit prêt, 34 secondes ; charger l'image, 2 ; le supprimer, 1. Sa sortie est `correr.salida.txt`. Dans ce fichier, la partie de l'habitude de sécurité apparaît avant celle du *rollout* (2.8), parce que le script les exécute dans cet ordre.

## À la fin, tu seras capable de

- Vérifier avec `crictl images` si une image se trouve dans un nœud de kind, et la charger avec `kind load docker-image`.
- Provoquer un `ErrImagePull`, le lire avec `kubectl describe` et `kubectl get events`, et dire ce que signifie chaque ligne.
- Écrire de mémoire le squelette d'un Deployment (`replicas`, `selector`, `template`) et expliquer pourquoi le sélecteur et les étiquettes du modèle doivent coïncider.
- Suivre avec `ownerReferences` la chaîne Deployment → ReplicaSet → Pod, et prédire ce qui se passe quand on supprime chaque maillon.
- Filtrer des objets avec des sélecteurs d'étiquettes (`-l app=revisor`, `-l 'app in (…)'`) et expliquer ce qu'est l'étiquette `pod-template-hash`.
- Lire l'historique d'un Deployment avec `kubectl rollout history` et provoquer un redémarrage ordonné avec `kubectl rollout restart`.
- Justifier chaque ligne du `securityContext` du `revisor` et reconnaître l'erreur `CreateContainerConfigError` que produit une contradiction dans celui-ci.

## Le pourquoi avant le comment

Dans la Leçon 0, tu as vu un Deployment qui maintenait trois copies d'un conteneur qui ne faisait rien. C'était l'idée pure : tu déclares « j'en veux trois » et le cluster poursuit ce nombre. Voici maintenant la version avec un vrai programme, et trois questions apparaissent que l'exemple jouet cachait.

La première : **d'où le cluster tire-t-il l'image ?** Celle de la Leçon 0 se trouvait déjà dans le nœud, parce que Kubernetes lui-même l'utilise. Celle du `revisor`, c'est toi qui l'as construite, et elle vit dans ton Docker. Un nœud de kind semble être « sur ta machine », mais à l'intérieur il a son propre magasin d'images, qui n'est pas celui de ton Docker. C'est la cause exacte de la scène du lundi, et c'est la première chose que tu vas voir échouer.

La deuxième : **quels objets existent et qui veille sur qui ?** Un Deployment n'exécute pas de conteneurs. Il crée un ReplicaSet, qui crée des Pods, qui sont ceux qui s'exécutent. Si tu ne vois pas cette chaîne, « supprimer un Pod » et « supprimer le Deployment » semblent être la même opération, et ils ne le sont pas : l'une se répare toute seule en une seconde et l'autre arrête le service.

La troisième : **que peut faire le conteneur si quelqu'un l'attaque ?** Avec `docker run`, tu as appris à lui retirer des privilèges avec `--user`, `--read-only` et `--cap-drop ALL`. Dans Kubernetes, ces mêmes décisions s'écrivent dans le manifeste, dans un bloc appelé `securityContext`, et ce cours les met dès le premier Deployment. Elles n'attendent pas la Leçon 7. La sécurité que l'on ajoute à la fin reste dans une liste de choses à faire ; celle qui naît avec le manifeste voyage avec lui vers n'importe quel cluster.

La leçon comporte huit parties de concepts, puis les sections habituelles :

1. **Deux magasins d'images** (2.1) : ton Docker et celui de chaque nœud.
2. **Le manifeste du `revisor`, champ par champ** (2.2).
3. **Appliquer et ne pas trouver l'image** (2.3), l'erreur à dessein.
4. **`kind load docker-image`** (2.4) et le cluster qui se rétablit tout seul.
5. **La chaîne des propriétaires** (2.5) : Deployment, ReplicaSet et Pod.
6. **Étiquettes et sélecteurs** (2.6).
7. **Un Pod isolé contre un Pod du Deployment** (2.7).
8. **Le *rollout*** (2.8) : révisions, historique et redémarrage.

Voici la destination. À la fin de 2.4, le `revisor` est en cours d'exécution avec trois répliques, dans un cluster qui, une demi-minute plus tôt, n'avait pas son image :

```text
$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           32s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-697fb84f97   3         3         3       32s
```

## Si tu n'as pas l'image du cours de Docker

Cette leçon utilise l'image que livre la Leçon 10 du cours de Docker, `curso-docker-revisor:1.6.0`. Avant de continuer, vérifie que tu l'as :

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Si tu ne l'as pas, construis-la depuis le dépôt de ce cours, avec le `Dockerfile` de sa Leçon 10 sur le dossier `programas/revisor` et avec `--build-arg VERSION=1.6.0`, en la taguant exactement `curso-docker-revisor:1.6.0`. Si tu utilises une autre image d'un service à toi, voici ce que le cours lui demande, et il vaut la peine de le lire, car chaque point explique une décision du manifeste :

- **Elle écoute en HTTP sur un port élevé**, le 8080, et répond à `GET /salud` sans interroger personne d'autre.
- **Elle s'exécute avec un utilisateur numérique qui n'est pas `root`** : le 65532, l'utilisateur `nonroot` des images *distroless*. Le manifeste l'exige avec `runAsNonRoot: true`.
- **Elle fonctionne avec le système de fichiers en lecture seule**, sauf un dossier de données (`/datos`), que le manifeste monte à part.
- **Elle embarque son propre contrôle de santé (health check)** sous forme de sous-commande (`/revisor healthcheck`), parce que l'image n'a ni *shell* ni `curl`.
- **Elle a un tag fixe**, jamais `:latest`. La section 2.2.3 explique pourquoi cela compte dans kind.
- **Elle se configure par des variables d'environnement.** Le `revisor` exige `REVISOR_SERVICIOS`, avec la liste des services qu'il vérifie, et comprend `REVISOR_PUERTO`, `REVISOR_REPORTE` et `REVISOR_TOKEN_ARCHIVO`. Une variable qu'il ne lit pas est ignorée en silence : n'en invente donc pas d'autres.

## Les concepts

### 2.1 Deux magasins d'images

Cette leçon utilise son propre cluster, `curso-k8s-l2`, avec la configuration à trois nœuds de la Leçon 1, tout juste créé et **sans** rien y charger. Crée-le ainsi, depuis la racine du dépôt du cours, avec le même soin que celui que tu as appris dans la Leçon 1 :

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l2.XXXX)/kubeconfig"
# curso-k8s-l2 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l2 --config programas/02-pods-deployments/kind-curso.yaml
# Debe decir kind-curso-k8s-l2. Si dice otra cosa, no sigas.
kubectl config current-context
```

L'`export` ne vaut que dans ce terminal. Si tu en ouvres un autre, répète l'`export` avec le même chemin, ou `kubectl` parlera à un autre cluster. Les sorties de cette section proviennent de l'exécution de `correr.sh`, qui fait exactement cela :

```text
$ kubectl config current-context
kind-curso-k8s-l2

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l2-control-plane   Ready    control-plane   26s   v1.37.0
curso-k8s-l2-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l2-worker2         Ready    <none>          16s   v1.37.0
```

La première commande n'est pas de la décoration. C'est l'habitude de la Leçon 1 : avant de changer quoi que ce soit, demander à quel cluster tu parles. Dans cette leçon, tu vas créer et supprimer des objets, et `kind-curso-k8s-l2` est la seule réponse qui te permette de continuer. Répète-la **avant chaque** `apply`, `delete`, `label` ou `rollout restart` de la leçon, pas seulement ici. Le script le fait tout seul : avant chaque `kubectl`, il compare le contexte et s'arrête s'il n'est pas `kind-curso-k8s-l2`.

Maintenant, la question de la scène. Ton Docker a l'image ; le nœud l'a-t-il ? Rappelle-toi, de la Leçon 0, qu'un nœud de kind est un conteneur qui embarque son propre `containerd`, et que ce `containerd` a son propre magasin d'images. Pour l'interroger, on entre dans le nœud et on utilise `crictl`, l'outil en ligne de commande qui parle au *runtime* du nœud. Le guide de démarrage de kind le recommande précisément pour cela ([kind, « Quick Start », section « Loading an Image Into Your Cluster »](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)) :

```text
$ docker exec curso-k8s-l2-worker crictl images | grep -c curso-docker-revisor
0
[código de salida: 1]
```

Zéro. (Le code de sortie 1 vient de `grep`, qui signale ainsi qu'il n'a rien trouvé ; ce n'est pas une panne du nœud.) L'image est sur ta machine et elle n'est pas dans le nœud. Ce sont deux magasins distincts, même si les deux vivent sur le même ordinateur, et rien ne les synchronise.

Dans un vrai cluster, cela se résout avec un **registre** : tu pousses l'image vers un serveur d'images (Docker Hub, le registre de ton entreprise ou celui de ton fournisseur cloud) et chaque nœud la télécharge de là. Dans kind, qui est un laboratoire sur ta machine, il existe un raccourci : copier l'image directement de ton Docker vers chaque nœud. Ce raccourci, c'est `kind load docker-image`, et il arrive en 2.4. Voyons d'abord ce qui se passe sans lui, parce que le message d'erreur est de ceux que tu rencontreras le plus dans ta vie avec Kubernetes.

### 2.2 Le manifeste du `revisor`, champ par champ

Voici le manifeste que construit la leçon. C'est un **programme** : il s'applique tel quel et se trouve dans `programas/02-pods-deployments/revisor-deployment.yaml`.

```yaml
# revisor-deployment.yaml — Lección 2: el revisor con tres réplicas que renacen.
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
          value: "prueba http://prueba:9000/ 2s"
        # La imagen de Docker trae REVISOR_REPORTE=/datos/reporte.json: con el
        # sistema de archivos de solo lectura, /datos necesita un volumen. emptyDir
        # vive y muere con el Pod (la Lección 8 lo contrasta con un PVC).
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
        emptyDir:
          sizeLimit: 10Mi
```

Cela semble beaucoup. On le lit par couches, de l'extérieur vers l'intérieur, et chaque couche répond à une question.

#### 2.2.1 Ce que c'est et comment ça s'appelle

Les trois premières clés, tout objet Kubernetes les porte. `apiVersion: apps/v1` dit dans quel groupe de l'API vit le type : les Deployments vivent dans le groupe `apps`, version `v1`, qui est stable. `kind: Deployment` dit le type. Et `metadata` apporte le nom (`revisor`) et les étiquettes du Deployment lui-même (`app: revisor`). Le nom est unique au sein de son espace de noms ; les étiquettes, comme tu le verras en 2.6, ne le sont pas, et c'est justement ce qui fait leur valeur.

#### 2.2.2 Combien, lesquels et avec quel moule

`spec` est l'état souhaité, et dans un Deployment elle comporte trois éléments qui vont ensemble :

- **`replicas: 3`** : combien de copies tu veux. C'est le nombre que le cluster poursuit.
- **`selector`** : comment le Deployment reconnaît **ses** Pods. Ici il dit : « les miens sont ceux qui portent l'étiquette `app: revisor` ».
- **`template`** : le moule de chaque Pod. Il porte ses propres étiquettes (`app: revisor`) et sa propre `spec`, qui est celle d'un Pod : conteneurs, volumes et sécurité.

Le sélecteur et les étiquettes du modèle **doivent coïncider**. Si le moule produisait des Pods avec `app: otro` et que le sélecteur cherchait `app: revisor`, le Deployment créerait des Pods qu'il ne reconnaîtrait jamais comme siens et continuerait d'en créer d'autres, sans fin. C'est pourquoi le `kube-apiserver` rejette un Deployment dont le sélecteur ne coïncide pas avec les étiquettes de son modèle, avant de l'enregistrer. La [documentation des Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) ajoute un avertissement qu'il convient d'avoir en tête dès maintenant : Kubernetes n'empêche pas deux contrôleurs d'avoir des sélecteurs qui se chevauchent, et s'ils en ont, « ils peuvent entrer en conflit et se comporter de façon inattendue ». L'Exercice 2 te montre une version de ce problème.

#### 2.2.3 Le conteneur

Dans le modèle, `containers` est une liste ; dans ce cours, elle contient toujours un seul conteneur. Ses champs :

- **`name: revisor`** : le nom du conteneur dans le Pod. Tu le verras dans les événements sous la forme `spec.containers{revisor}`.
- **`image: curso-docker-revisor:1.6.0`** : l'image, avec son tag fixe.
- **`imagePullPolicy: IfNotPresent`** : quand télécharger l'image. `IfNotPresent` signifie « ne la télécharge que si elle n'est pas déjà dans le nœud ». La [documentation des images](https://kubernetes.io/docs/concepts/containers/images/) définit aussi `Always` (interroger le registre à chaque démarrage d'un conteneur ; le *runtime* ne télécharge que les couches qui lui manquent, mais si le registre ne répond pas ou n'a pas l'image, cela échoue même si le nœud l'a déjà) et `Never` (ne jamais essayer de la télécharger). Si tu omets le champ, Kubernetes le décide d'après le tag : avec un tag qui n'est pas `:latest`, il met `IfNotPresent`, et avec `:latest` ou sans tag, il met `Always`. C'est ce qui fait de `:latest` un piège dans kind : avec `Always`, le nœud essaierait d'aller sur Docker Hub même si tu lui avais déjà chargé l'image, et il échouerait. Le guide de kind l'avertit : avec `:latest` ou sans tag, la politique par défaut est `Always`, et il demande de ne pas utiliser `:latest` ou d'écrire `imagePullPolicy: IfNotPresent` (ou `Never`) ([kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)). Le manifeste écrit `IfNotPresent` bien que ce soit la valeur par défaut, pour que celui qui le lit n'ait pas à connaître la règle.
- **`ports`** : déclare que le conteneur écoute sur le 8080 et lui donne un nom, `http`. Le déclarer ne publie rien et n'ouvre aucun port vers l'extérieur : c'est une information pour qui lit le manifeste et pour les objets qui l'utiliseront ensuite. Dans la Leçon 3, le Service pointera vers le port **par son nom**, `http`, et non par son numéro.
- **`env`** : les variables d'environnement. Il y en a une seule ici, `REVISOR_SERVICIOS`, celle que le `revisor` exige, avec un service appelé `prueba` à l'adresse `http://prueba:9000/` et un délai maximal de 2 secondes. Ce service n'existe pas encore dans le cluster, et cela n'a pas d'importance : le `revisor` démarre quand même et le signalera avec l'état `FALLA` quand quelqu'un lui demandera le rapport. Dans la Leçon 4, cette liste sort du manifeste et passe dans un `ConfigMap`.

#### 2.2.4 Le volume `datos`

À la fin, il y a un volume, `datos`, de type `emptyDir`, monté sur `/datos`. Il est là pour une raison concrète. L'image du cours de Docker définit `REVISOR_REPORTE=/datos/reporte.json` : chaque fois que quelqu'un lui demande le rapport, le `revisor` l'enregistre dans ce fichier. Mais le `securityContext` du conteneur (2.2.5) met **tout** son système de fichiers en lecture seule. Sans volume, le `revisor` démarrerait sans se plaindre et échouerait ensuite, la première fois qu'il tenterait d'enregistrer un rapport : dans son code, ce cas répond par une erreur 500 et le message `no pude guardar el reporte`.

Un `emptyDir` est la façon la plus simple de donner un endroit où écrire. La [documentation des volumes](https://kubernetes.io/docs/concepts/storage/volumes/) le décrit ainsi : il est créé quand le Pod est assigné à un nœud, il commence vide, et « quand un Pod est retiré d'un nœud pour quelque raison que ce soit, les données de l'`emptyDir` sont supprimées définitivement ». Si le conteneur plante et redémarre, les données survivent, parce que le Pod reste sur le nœud. Le `sizeLimit: 10Mi` lui met un plafond : un rapport pèse quelques kilo-octets, et un plafond évite qu'une erreur remplisse le disque du nœud. La Leçon 8 compare cet `emptyDir` à un volume persistant et mesure ce qui se perd avec chacun.

#### 2.2.5 Les deux `securityContext`

Il y a deux blocs `securityContext` : l'un au niveau du Pod (`template.spec.securityContext`) et l'autre au niveau du conteneur. Celui du Pod vaut pour tous ses conteneurs ; celui du conteneur, seulement pour lui. La section « L'habitude de sécurité de la leçon » les démonte ligne par ligne, avec le cluster qui montre ce que fait chacun. Pour l'instant, l'idée suffit : le conteneur s'exécute comme l'utilisateur 65532, ne peut pas devenir `root`, n'a aucune capacité spéciale du noyau, ne peut pas écrire dans son propre système de fichiers et reste soumis au filtre d'appels système qu'apporte le *runtime*.

### 2.3 Appliquer et ne pas trouver l'image

Avec le cluster tout juste créé et sans l'image chargée, on a appliqué le manifeste :

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created
```

Rappelle-toi, de la Leçon 0, ce que signifie cette réponse : l'objet a été **enregistré**. Elle ne dit rien des conteneurs. Vingt secondes plus tard :

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS             RESTARTS   AGE
revisor-697fb84f97-gn68x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-qvs7x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-vq4ld   0/1     ImagePullBackOff   0          20s
```

Les trois Pods existent, chacun a déjà un nœud, et aucun ne s'exécute : `0/1` dans `READY` veut dire « zéro conteneur sur un prêt ». L'état, `ImagePullBackOff`, c'est la scène du lundi. Remarque ce qui, lui, a **fonctionné** : le Deployment a créé son ReplicaSet, le ReplicaSet a créé trois Pods et le `kube-scheduler` les a répartis. Tout le plan de contrôle a fait son travail. Ce qui a échoué se trouve au bout de la chaîne, dans le `kubelet` de chaque nœud, qui n'a pas pu obtenir l'image.

La section « L'erreur que tu vas voir » lit cette erreur ligne par ligne. La version courte, pour avancer : le `kubelet` a cherché l'image dans le nœud, ne l'a pas trouvée et, comme la politique est `IfNotPresent`, a essayé de la télécharger. L'image ne dit pas de quel registre elle vient, donc il est allé sur Docker Hub, où elle n'existe pas. Il réessaie, chaque fois en attendant un peu plus. Supprimer et réappliquer ne change rien à tout cela : le nouveau Pod atterrit sur un nœud qui n'a pas non plus l'image et arrive au même endroit.

### 2.4 `kind load docker-image` : amener l'image dans chaque nœud

Le remède consiste à donner au nœud ce qu'il demande :

```text
$ kind load docker-image curso-docker-revisor:1.6.0 --name curso-k8s-l2
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-control-plane", loading...
```

`kind` a sorti l'image de ton Docker et l'a copiée dans **chaque** nœud du cluster, un par ligne : « pas encore dans tel nœud, chargement ». Le nœud de contrôle apparaît aussi, bien qu'aucun Pod du `revisor` n'y tourne. kind ne sait pas où tu vas utiliser l'image et la met partout. Cela a pris 2 secondes, parce que l'image pèse environ 16 Mo. Le `--name curso-k8s-l2` est obligatoire quand le cluster ne s'appelle pas `kind`, qui est le nom par défaut. Sans lui, kind chercherait un cluster qui n'existe pas, et sur une machine qui a plusieurs clusters, c'est ce qui te garantit que tu charges l'image dans le tien et non dans un autre.

Maintenant, le nœud l'a bien :

```text
$ docker exec curso-k8s-l2-worker crictl images | grep curso-docker-revisor
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Regarde le nom sous lequel elle a été enregistrée : `docker.io/library/curso-docker-revisor`. C'est le nom complet qui correspond à `curso-docker-revisor` : quand une image ne dit pas de quel registre elle vient, on comprend qu'elle vient de Docker Hub (`docker.io`) et, si elle ne dit pas non plus de quel utilisateur, de son espace d'images officielles (`library`). La documentation des images l'explique avec l'exemple de `busybox`, qui équivaut à `docker.io/library/busybox:latest`. C'est le même nom que celui qui apparaissait dans l'erreur de 2.3, et c'est pourquoi le `kubelet` la trouve maintenant. (Les nombres semblent différents, mais il y a une explication. `crictl` indique 3.68MB. Avec Docker Engine 29, `docker image ls curso-docker-revisor:1.6.0` affiche deux colonnes : `DISK USAGE` 16.2MB, ce qu'elle occupe décompressée sur le disque, et `CONTENT SIZE` 3.68MB, le contenu compressé ; `crictl` rapporte la seconde. Si ton Docker est plus ancien, `docker image ls` affiche une seule valeur et elle peut ne pas coïncider. L'identifiant de `crictl`, `70e09194319be`, n'est pas non plus le `sha256:bd1b2e7d…` de `kind load` : chaque outil identifie l'image avec un condensé différent. Que ce soit la même image, c'est prouvé par le nom et le tag, et par le fait que le `kubelet` la trouve à l'étape suivante.)

Il n'y a rien à réappliquer. Le `kubelet` continuait de réessayer de lui-même ; à la tentative suivante, il a trouvé l'image et a démarré le conteneur :

```text
$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-gn68x   1/1     Running   0          33s   10.244.1.3   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   10.244.1.2   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   10.244.2.2   curso-k8s-l2-worker    <none>           <none>
```

Voici la leçon de fond de la scène : **le cluster s'est rétabli tout seul parce que l'état souhaité n'a jamais changé**. Il disait toujours « trois répliques avec cette image ». La seule chose qui manquait était l'image, et dès qu'elle est arrivée, chaque pièce a terminé son travail. Supprimer et réappliquer aurait été, au mieux, inutile.

Regarde la colonne `NODE`. Deux répliques se sont retrouvées sur `curso-k8s-l2-worker2` et une sur `curso-k8s-l2-worker`. Le Deployment veille à **combien** de répliques il y a, pas à **où** elles se trouvent. La Leçon 0 l'avait annoncé : le *scheduler* s'efforce de répartir, mais ne le garantit pas, et lors d'une autre exécution elles peuvent atterrir autrement. Si `worker2` s'arrêtait, deux des trois répliques mourraient en même temps. La répartition garantie se déclare avec des règles propres, et le cours le fait quand le `revisor` devra survivre à un nœud arrêté (Leçon 9). Remarque aussi la colonne `IP` : chaque Pod a la sienne, et elle change chaque fois qu'un Pod renaît. C'est pourquoi personne ne doit parler à un Pod par son IP, et c'est pourquoi la Leçon 3 existe.

Le journal du `revisor` confirme que le programme a démarré :

```text
$ kubectl logs deployment/revisor
Found 3 pods, using pod/revisor-697fb84f97-gn68x
revisor 1.6.0 escuchando en :8080 (1 servicio(s))
```

`kubectl logs deployment/revisor` est un raccourci : il choisit l'un des Pods du Deployment, t'affiche le sien et te dit lequel il a choisi. C'est la même ligne que celle qu'il imprimait avec `docker run` dans le cours de Docker : l'image est la même, seul a changé celui qui l'exécute.

### 2.5 La chaîne des propriétaires : Deployment, ReplicaSet et Pod

Dans la Leçon 0, tu as vu la chaîne dessinée. Maintenant, on peut la lire dans le cluster lui-même, parce que chaque objet dit qui est son propriétaire dans un champ appelé `metadata.ownerReferences`. La [documentation des propriétaires et dépendants](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) l'explique ainsi : les objets dépendants ont ce champ, qui pointe vers leur propriétaire, et Kubernetes le remplit tout seul pour les objets que créent les contrôleurs, comme les ReplicaSets.

```text
$ kubectl get pod revisor-697fb84f97-gn68x -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ReplicaSet/revisor-697fb84f97

$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
Deployment/revisor

$ kubectl get deployment revisor -o jsonpath='{.metadata.ownerReferences}{"\n"}'

```

Le Pod appartient au ReplicaSet, le ReplicaSet appartient au Deployment, et le Deployment n'appartient à personne : sa réponse est une ligne vide. Le Deployment, c'est toi qui l'as écrit, et le propriétaire, c'est toi.

L'option `-o jsonpath=…` mérite un instant, parce que le cours l'utilise beaucoup. `kubectl get` peut renvoyer l'objet complet (`-o yaml`), mais presque toujours tu ne veux qu'une seule donnée. `jsonpath` te laisse demander un champ par son chemin : `{.metadata.ownerReferences[0].kind}` signifie « dans l'objet, entre dans `metadata`, puis dans `ownerReferences`, prends le premier élément et donne-moi son `kind` ». Le `{"\n"}` final ajoute simplement un saut de ligne.

Chaque maillon a un travail différent :

| Objet | Qui le crée | Son travail | Si tu le supprimes |
|---|---|---|---|
| **Deployment** | toi | conserver l'état souhaité et gérer les versions : quand tu changes le modèle, il crée un nouveau ReplicaSet et passe les répliques de l'ancien au nouveau | ses ReplicaSets et ses Pods sont supprimés ; le service s'arrête |
| **ReplicaSet** | le Deployment | compter : qu'il y ait autant de Pods avec son modèle exact que le dit `replicas` | le Deployment en crée un autre identique, mais `kubectl delete` supprime en cascade ses Pods : mesuré, les trois Pods sont passés à `Terminating` en même temps et le remplacement a démarré de zéro, avec une coupure ; c'est pourquoi on n'y touche pas manuellement |
| **Pod** | le ReplicaSet | exécuter le conteneur | le ReplicaSet en crée un autre |

La [documentation de ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/) définit son objectif en une phrase : « maintenir un ensemble stable de Pods répliques en cours d'exécution à tout moment ». Et elle déconseille de les utiliser directement : « nous recommandons d'utiliser des Deployments plutôt que des ReplicaSets directement », sauf cas particuliers. Celle des Deployments est encore plus tranchée : « ne gère pas les ReplicaSets qui appartiennent à un Deployment ». Dans ce cours, tu n'écriras jamais de ReplicaSet. Tu vas les **voir**, parce que les lire explique ce que fait le Deployment.

Et le Pod ? La [documentation des Pods](https://kubernetes.io/docs/concepts/workloads/pods/) le dit sans détour : « tu créeras rarement des Pods individuels directement dans Kubernetes, pas même des Pods seuls », parce que les Pods sont conçus comme des entités « relativement éphémères et jetables ». La section 2.7 te montre ce que veut dire « jetable » avec un Pod sans propriétaire.

### 2.6 Étiquettes et sélecteurs

Jusqu'ici, tu as écrit `-l app=revisor` bien des fois. Il est temps de voir ce qu'il y a derrière.

Une **étiquette** est une paire clé-valeur collée à un objet. La [documentation des étiquettes](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) les définit comme des paires qui « servent à spécifier des attributs identifiants des objets, significatifs pour les utilisateurs », et ajoute ce qui les rend utiles : « contrairement aux noms et aux UID, les étiquettes ne sont pas uniques ». Beaucoup d'objets portent la même. Avec un **sélecteur** d'étiquettes, tu choisis un ensemble d'objets, et selon la même page, le sélecteur est « la primitive de regroupement centrale dans Kubernetes ».

Voici à quoi ressemblent les étiquettes des Pods du `revisor` :

```text
$ kubectl get pods --show-labels
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
revisor-697fb84f97-gn68x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
```

`app=revisor`, c'est toi qui l'as mise, dans le modèle. Mais il y en a une autre que tu n'as pas écrite : `pod-template-hash=697fb84f97`. C'est le Deployment qui l'a mise, et le nombre est le même suffixe que celui du nom du ReplicaSet. Regarde le sélecteur du ReplicaSet :

```text
$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.spec.selector}{"\n"}'
{"matchLabels":{"app":"revisor","pod-template-hash":"697fb84f97"}}
```

Le ReplicaSet ne cherche pas seulement `app: revisor` : il cherche `app: revisor` **et** `pod-template-hash: 697fb84f97`. La documentation des Deployments explique pourquoi : le contrôleur de Deployments ajoute cette étiquette à chaque ReplicaSet qu'il crée, calculée avec un *hash* du modèle du Pod, et « cette étiquette garantit que les ReplicaSets enfants d'un Deployment ne se chevauchent pas ». Quand tu changeras le modèle, en 2.8, un autre ReplicaSet apparaîtra avec un autre *hash*. Chacun ne comptera que ses propres Pods, même si tous portent `app=revisor`. La même page contient un avertissement en rouge : « ne change pas cette étiquette ».

Les sélecteurs ont deux formes. Celle d'**égalité** est celle que tu as utilisée : `app=revisor`, ou `app!=revisor` pour le contraire. Celle d'**ensembles** interroge l'appartenance :

```text
$ kubectl get pods -l 'app in (revisor,prueba)' -o name
pod/revisor-697fb84f97-gn68x
pod/revisor-697fb84f97-qvs7x
pod/revisor-697fb84f97-vq4ld

$ kubectl get pods -l app=prueba
No resources found in default namespace.
```

Le premier demande les Pods dont l'étiquette `app` vaut `revisor` ou `prueba`, et comme il n'y a encore aucun `prueba`, il ne renvoie que ceux du `revisor`. Le second le confirme. Deux règles de la documentation pour ne pas te tromper : plusieurs exigences séparées par une virgule se combinent avec un « et » (`app=revisor,pod-template-hash=697fb84f97` exige les deux), et il **n'existe pas** d'opérateur « ou » entre des exigences différentes. Pour un « ou » sur une même clé, il y a `in`.

`No resources found` n'est pas une erreur. C'est une réponse : rien ne correspond. Distinguer « il n'y a rien » de « quelque chose a échoué » fait partie de la lecture de ce que dit le cluster.

Pourquoi le cours cherche-t-il toujours par étiquette et jamais par nom de Pod ? Parce que le nom change chaque fois que le Pod renaît, et l'étiquette non. Une commande qui écrit `revisor-697fb84f97-gn68x` cesse de servir dès que ce Pod meurt. Une commande qui écrit `-l app=revisor` continue de fonctionner à travers les remplacements, dans le même espace de noms et tant qu'aucun autre Pod n'utilise cette étiquette (l'Exercice 2 montre ce qui se passe quand l'un d'eux l'utilise). Les Services de la Leçon 3 choisissent leurs Pods de la même façon : par étiquette. Cela rend important ce que montre l'Exercice 2.

### 2.7 Un Pod isolé contre un Pod du Deployment

#### 2.7.1 Le Pod isolé

Un Pod peut être créé seul, sans Deployment. Ce manifeste est un **programme** (`fig02_01.pod.yaml`). C'est le même modèle que celui du Deployment, mais écrit comme un Pod, avec un nom fixe et **sans** l'étiquette `app: revisor`, pour qu'aucun ReplicaSet ne le confonde avec l'un des siens :

```yaml
# fig02_01.pod.yaml — un Pod suelto: el revisor sin Deployment que lo cuide.
# Sirve para ver qué hace un Pod por sí solo, y qué NO hace: si lo borras, nadie
# lo repone. No lleva etiqueta app: revisor a propósito, para que ningún
# ReplicaSet lo confunda con uno de los suyos.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-suelto
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
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
      value: "prueba http://prueba:9000/ 2s"
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
    emptyDir:
      sizeLimit: 10Mi
```

Remarque la différence avec le Deployment : `apiVersion: v1` (les Pods vivent dans le groupe central de l'API, qui ne porte pas de nom) et `kind: Pod`. Ce qui, dans le Deployment, se trouvait dans `template.spec` est ici directement dans `spec`. Un Deployment est, en grande partie, un moule de Pod avec un compteur dessus.

```text
$ kubectl apply -f fig02_01.pod.yaml
pod/revisor-suelto created

$ kubectl get pod revisor-suelto -o jsonpath='{.metadata.name} dueños={.metadata.ownerReferences}{"\n"}'
revisor-suelto dueños=

$ kubectl delete pod revisor-suelto
pod "revisor-suelto" deleted from default namespace

$ kubectl get pods
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-gn68x   1/1     Running   0          40s
revisor-697fb84f97-qvs7x   1/1     Running   0          40s
revisor-697fb84f97-vq4ld   1/1     Running   0          40s
```

`dueños=` vide : personne n'est propriétaire de ce Pod. Il a été supprimé, le script a attendu cinq secondes et `revisor-suelto` n'est plus là. Personne ne l'a remplacé, parce qu'aucun contrôleur n'avait « je veux un `revisor-suelto` » dans son état souhaité.

Attention à ce qu'un Pod isolé fait **bel et bien**. Si son **processus** plante, le `kubelet` le redémarre à l'intérieur du même Pod, parce que le champ `restartPolicy` vaut `Always` par défaut ([kubernetes.io, « Pod Lifecycle »](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). Cela ressemble à un `docker run --restart always` sur une seule machine : il résiste à un plantage du programme, et la colonne `RESTARTS` le compte. Ce qu'il ne supporte pas, c'est de perdre le Pod lui-même. La documentation des Pods dit qu'un Pod reste sur son nœud « jusqu'à ce qu'il se termine, que l'objet Pod soit supprimé, qu'il soit évincé par manque de ressources ou que le nœud tombe en panne », et celle de son cycle de vie ajoute qu'un Pod n'est jamais « reprogrammé » sur un autre nœud : à la place, quelqu'un peut en créer un nouveau presque identique. Pour un Pod isolé, ce quelqu'un n'existe pas. S'il est supprimé, évincé ou si son nœud s'arrête, c'est fini.

#### 2.7.2 Le Pod du Deployment

Maintenant la même chose avec un Pod qui, lui, a un propriétaire :

```text
$ kubectl delete pod revisor-697fb84f97-gn68x
pod "revisor-697fb84f97-gn68x" deleted from default namespace

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-nrwht   1/1     Running   0          1s
revisor-697fb84f97-qvs7x   1/1     Running   0          41s
revisor-697fb84f97-vq4ld   1/1     Running   0          41s

$ kubectl get events --field-selector involvedObject.kind=ReplicaSet,reason=SuccessfulCreate -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message
OBJETO               MENSAJE
revisor-697fb84f97   Created pod: revisor-697fb84f97-vq4ld
revisor-697fb84f97   Created pod: revisor-697fb84f97-gn68x
revisor-697fb84f97   Created pod: revisor-697fb84f97-qvs7x
revisor-697fb84f97   Created pod: revisor-697fb84f97-nrwht
```

Une seconde plus tard, il y a un nouveau Pod, `nrwht`, et les événements racontent l'histoire : trois créations au début et une quatrième, le remplacement. C'est le thermostat de la Leçon 0, maintenant avec ton programme.

`-o custom-columns=…` est la sœur de `jsonpath` pour les tableaux : tu lui dis quelles colonnes tu veux et de quel champ sort chacune. Elle a été utilisée ici pour que chaque événement tienne sur une ligne.

La comparaison est l'idée la plus importante de la leçon : **le Pod s'exécute, mais c'est son propriétaire qui le remplace.** Un Pod sans propriétaire redémarre son conteneur si le processus plante, mais le Pod lui-même ne renaît pas : s'il est supprimé, évincé ou si son nœud est perdu, c'est fini. C'est pourquoi, dans ce cours, tout ce qui doit continuer de tourner vit dans un Deployment. Les Pods isolés n'apparaissent que pour déboguer ou pour démontrer quelque chose, et on les supprime ensuite.

### 2.8 Le *rollout* : révisions, historique et redémarrage

#### 2.8.1 Ce qu'est une révision

Un **rollout** est le passage d'une version des Pods à une autre. La documentation des Deployments dit quand il se produit, et la règle est précise : un *rollout* se déclenche « si et seulement si le modèle de Pod du Deployment (`.spec.template`) change », par exemple ses étiquettes ou son image. D'autres changements, comme passer de trois à cinq répliques, ne le déclenchent pas. Chaque *rollout* laisse une **révision** dans l'historique, et chaque révision est un ReplicaSet.

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
```

Une révision : celle qui est née avec l'`apply`. La colonne `CHANGE-CAUSE` indique `<none>` parce que personne n'a noté le motif. On peut la remplir avec une annotation du Deployment ; le cours ne le fait pas, parce que le motif de chaque changement vit dans l'historique Git de tes manifestes.

#### 2.8.2 Redémarrer sans rien changer

Parfois, tu veux que tous les Pods soient remplacés sans changer l'image ni la configuration : par exemple, pour qu'ils relisent quelque chose qui a changé en dehors d'eux. Les supprimer manuellement fonctionne, mais tu les supprimes tous à la fois et le service se retrouve un instant sans répliques. C'est pour cela que `kubectl rollout restart` existe :

```text
$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

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
revisor-55cc969586   3         3         3       2s
revisor-697fb84f97   0         0         0       55s
```

Lis l'avancement de `rollout status` : un nouveau sur trois, deux sur trois, et à la fin « une ancienne réplique en attente de terminaison ». Les Pods n'ont pas été remplacés d'un coup : on a créé un nouveau Pod et retiré un ancien, tour à tour. C'est la stratégie par défaut d'un Deployment, `RollingUpdate`. Ses deux réglages valent 25 % si tu n'y touches pas : `maxSurge`, combien de Pods en plus peut-il y avoir pendant le changement (arrondi à l'entier supérieur), et `maxUnavailable`, combien peuvent manquer (arrondi à l'entier inférieur). Avec trois répliques, 25 % font 0,75 : `maxSurge` vaut 1 et `maxUnavailable` 0. Dit simplement : pendant le changement, il peut y avoir jusqu'à quatre Pods, et le contrôleur ne retire aucun ancien Pod avant que le nouveau soit prêt, si bien que son plan ne descend jamais sous trois disponibles. C'est une promesse du contrôleur, pas de l'univers : si un nœud tombe ou si un processus meurt à ce moment-là, le compte baisse pour des causes qui lui sont étrangères. Et avec un autre nombre de répliques, l'arrondi change : avec quatre, 25 % font déjà 1 et `maxUnavailable` vaudrait 1. La Leçon 9 y revient avec une vraie charge et mesure si une requête se perd.

Et le résultat : un nouveau ReplicaSet, `revisor-55cc969586`, avec les trois répliques, et l'ancien, `revisor-697fb84f97`, à `0 0 0`. L'ancien **n'a pas été supprimé** : il est resté vide, comme trace de la révision 1. La documentation dit que, par défaut, 10 anciens ReplicaSets sont conservés (`revisionHistoryLimit`), et qu'en supprimer un, c'est perdre la possibilité de revenir à cette révision. La Leçon 9 utilise cette possibilité avec `rollout undo`.

Pourquoi y a-t-il eu un *rollout* si tu n'as rien changé ? Quelque chose a bien changé :

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>


$ kubectl get deployment revisor -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
{"kubectl.kubernetes.io/restartedAt":"2026-10-21T03:55:53-06:00"}
```

`rollout restart` a ajouté au modèle une annotation avec l'heure du redémarrage. Le modèle a changé et la règle « si et seulement si » s'est appliquée : nouveau modèle, nouveau *hash*, nouveau ReplicaSet, révision 2. Il n'y a pas de magie, seulement la même règle appliquée à un champ que tu as mis sans le taper.

Cette annotation n'est pas dans ton fichier, et cela a une conséquence. Si demain tu appliques de nouveau `revisor-deployment.yaml`, `kubectl apply` ne la retire pas, parce qu'il ne gère que les champs que le fichier déclare (la Leçon 0 a expliqué l'annotation `last-applied-configuration`, qui est la façon dont il tient ce compte). L'état final de cette leçon le vérifie avec `kubectl diff`, qui ne trouve aucune différence.

## L'erreur que tu vas voir

L'erreur de cette leçon est celle de 2.3 : `ErrImagePull`, qui devient ensuite `ImagePullBackOff`. Elle a été provoquée à dessein et se lit dans l'ordre, parce que cet ordre vaut pour n'importe quel Pod qui ne démarre pas.

**D'abord, l'état.** `kubectl get pods` t'a donné `ImagePullBackOff` et `0/1`. La colonne `STATUS` te dit **à quelle étape** le Pod s'est bloqué. Un `Pending` tout court veut généralement dire « il n'a pas encore de nœud » (le *scheduler* n'a pas trouvé de place ; tu le verras dans la Leçon 5). Quand il y a quelque chose de plus concret, `kubectl` affiche cela à la place de la phase : `ImagePullBackOff` signifie « il a déjà un nœud, et le `kubelet` de ce nœud n'arrive pas à obtenir l'image », et `CrashLoopBackOff` signifierait « l'image a démarré et le programme plante ». Une nuance : la **phase** du Pod, qui est un autre champ, reste `Pending` pendant le téléchargement de l'image. La documentation du cycle de vie le dit ainsi : `Pending` inclut le temps d'attente de l'assignation à un nœud et « le temps de téléchargement des images par le réseau » ([kubernetes.io, « Pod Lifecycle »](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). La phase se lit avec `kubectl get pod <pod> -o jsonpath='{.status.phase}'`. Rien qu'avec la colonne `STATUS`, tu sais déjà à quelle pièce de la Leçon 0 poser la question.

**Ensuite, les événements.** Le cluster garde une trace de chaque tentative :

```text
$ kubectl get events --field-selector reason=Failed -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message | head -4
OBJETO                     MENSAJE
revisor-697fb84f97-gn68x   Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
revisor-697fb84f97-gn68x   Error: ErrImagePull
revisor-697fb84f97-gn68x   Error: ImagePullBackOff
```

Le premier message est long, et se lit comme une chaîne de « parce que », de gauche à droite :

- `Failed to pull image "curso-docker-revisor:1.6.0"` : je n'ai pas pu télécharger l'image que tu as demandée…
- `failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0"` : …qui, avec son nom complet, est celle-ci de Docker Hub…
- `failed to resolve reference` : …parce que je n'ai pas pu trouver cette référence…
- `pull access denied, repository does not exist or may require authorization` : …parce que Docker Hub m'a refusé l'accès : le dépôt n'existe pas ou demande des identifiants.

L'indice décisif est `docker.io/library/…`. Le nœud est allé chercher ton image sur internet. Il n'a jamais regardé ton Docker, parce qu'il ne le peut pas : ce n'est pas son magasin. Docker Hub dit « il n'existe pas ou tu as besoin d'une permission » et ne précise pas laquelle des deux. C'est ainsi que se comportent les registres, pour ne pas révéler quels dépôts privés existent. Ici, c'est la première : il n'existe pas.

**Troisièmement, `describe`.** `kubectl get events` mélange les événements de tout l'espace de noms. `kubectl describe pod` rassemble tout ce qui concerne **un** Pod, avec ses événements à la fin. Attention : un événement répété est regroupé sur une seule ligne et classé selon la **dernière** fois où il s'est produit, si bien que `Pulling (x2 over 20s)` apparaît après `BackOff` alors qu'il s'est produit en premier :

```text
$ kubectl describe pod revisor-697fb84f97-gn68x | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned default/revisor-697fb84f97-gn68x to curso-k8s-l2-worker2
  Normal   BackOff    19s               kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     19s               kubelet            spec.containers{revisor}: Error: ImagePullBackOff
  Normal   Pulling    6s (x2 over 20s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
```

(Le `sed` coupe la sortie pour n'afficher qu'à partir de `Events:` ; au-dessus, `describe` apporte l'image, le nœud, les volumes, le `securityContext` et les conditions du Pod.) La colonne `From` dit **qui** parle, et c'est celle qui t'apprend le plus. Dans l'ordre logique :

- `default-scheduler`, `Scheduled` : le *scheduler* a assigné le Pod à `curso-k8s-l2-worker2`. Sa part s'est bien passée.
- `kubelet`, `Pulling` : le `kubelet` de ce nœud a essayé de télécharger l'image. `(x2 over 20s)` veut dire que le même événement s'est produit deux fois en 20 secondes ; le cluster regroupe les événements répétés au lieu de tous les écrire.
- `kubelet`, `Failed` avec `ErrImagePull` : la tentative a échoué.
- `kubelet`, `BackOff` et `Failed` avec `ImagePullBackOff` : le `kubelet` a décidé d'attendre avant la tentative suivante.

**`ErrImagePull` et `ImagePullBackOff` sont le même problème à deux moments.** `ErrImagePull` est l'échec d'une tentative. `ImagePullBackOff` est l'attente entre les tentatives. La documentation des images l'explique : la partie `BackOff` indique que Kubernetes continuera d'essayer, avec une attente qui grandit à chaque tentative, jusqu'à une limite fixe de 300 secondes (5 minutes). C'est pourquoi le Pod alterne entre les deux états tant que tu ne lui donnes pas l'image. Et c'est pourquoi le rétablissement de 2.4 n'a pas été immédiat pour un Pod qui se trouvait au milieu d'une longue attente : le `kubelet` prend l'image à sa tentative suivante, pas avant. Si un Pod attend depuis longtemps et que tu ne veux pas patienter, le supprimer **après** avoir corrigé la cause fonctionne bien : le ReplicaSet en crée un autre, qui essaie aussitôt. Le supprimer **avant** de corriger, c'est ce qu'a fait l'équipe de la scène.

**L'ordre, pour n'importe quel Pod qui ne démarre pas :** l'état (`get pods`), le `describe` du Pod (ses événements et la colonne `From`) et, si le conteneur a fini par démarrer, ses `logs`. D'abord on lit, ensuite on change quelque chose. Et ce que l'on change, c'est la cause, pas le Pod.

## L'habitude de sécurité de la leçon : `securityContext` dès le premier manifeste

Le tableau des habitudes du cours attribue à cette leçon le `securityContext` du premier Deployment : pas de `root`, pas d'élévation de privilèges, pas de capacités, système de fichiers en lecture seule et profil `seccomp`. Voici comment cela a été appliqué dans le cluster :

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
{"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}
{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}
```

La première ligne est celle du Pod ; la seconde, celle du conteneur. Ligne par ligne, avec ce qu'évite chacune :

| Ligne | Ce qu'elle fait | Ce qu'elle évite | Son équivalent dans Docker |
|---|---|---|---|
| `runAsNonRoot: true` | le `kubelet` refuse de démarrer le conteneur s'il devait s'exécuter comme l'utilisateur 0 | qu'une image mal faite, ou une ligne mal écrite, s'exécute en `root` sans que personne s'en aperçoive | aucun : Docker ne vérifie pas |
| `runAsUser: 65532`, `runAsGroup: 65532` | fixe l'utilisateur et le groupe numériques avec lesquels le processus s'exécute | de dépendre de ce que dit l'image ; le nombre reste écrit dans le manifeste | `--user 65532:65532` |
| `seccompProfile: RuntimeDefault` | applique le filtre d'appels système qu'apporte le *runtime* | que le processus utilise des appels du noyau dont un serveur HTTP n'a jamais besoin. **Sans cette ligne, Kubernetes exécute le conteneur sans filtre (`Unconfined`)**, sauf si le `kubelet` a activé l'option `seccompDefault` | Docker applique son profil par défaut sans que tu le demandes ; Kubernetes, non |
| `allowPrivilegeEscalation: false` | un processus ne peut pas gagner plus de privilèges que son parent, par exemple en exécutant un binaire *setuid* | que quelqu'un qui entre dans le conteneur devienne `root` de l'intérieur | `--security-opt no-new-privileges` |
| `capabilities: drop: ["ALL"]` | retire toutes les capacités (capabilities) spéciales du noyau | que le processus puisse, par exemple, changer le propriétaire de fichiers (`CHOWN`) ou ouvrir des *sockets* bruts pour fabriquer des paquets réseau (`NET_RAW`) | `--cap-drop ALL` |
| `readOnlyRootFilesystem: true` | monte le système de fichiers du conteneur en lecture seule | qu'un attaquant laisse des outils ou modifie le programme | `--read-only` |

Les définitions viennent du guide officiel [« Configure a Security Context for a Pod or Container »](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/). À propos d'`allowPrivilegeEscalation`, par exemple, il dit qu'il « contrôle si un processus peut obtenir plus de privilèges que son processus parent » et qu'il active le drapeau `no_new_privs` du noyau. Et le tutoriel sur `seccomp` explique la différence avec Docker que souligne le tableau : si l'option `seccompDefault` est activée, les Pods utilisent `RuntimeDefault` quand ils ne demandent pas d'autre profil ; « sinon, la valeur par défaut est `Unconfined` » ([kubernetes.io, « Restrict a Container's Syscalls with seccomp »](https://kubernetes.io/docs/tutorials/security/seccomp/)). C'est pourquoi la ligne s'écrit toujours.

Il y a une référence qui compte plus que n'importe quel guide : les **Pod Security Standards**, les trois niveaux de sécurité que définit Kubernetes ([kubernetes.io, « Pod Security Standards »](https://kubernetes.io/docs/concepts/security/pod-security-standards/)). Le plus strict, `restricted`, est conçu pour « faire respecter les bonnes pratiques actuelles de durcissement (hardening) des Pods ». Il exige quatre de ces lignes : s'exécuter en non-`root` (`runAsNonRoot: true`), ne pas autoriser l'élévation de privilèges, retirer **toutes** les capacités (il permet seulement de rajouter `NET_BIND_SERVICE`) et fixer explicitement le profil `seccomp` (« le profil `Unconfined` comme l'absence de profil sont interdits »). De plus, `restricted` interdit de demander `runAsUser: 0` (exactement ce que fait `fig02_02.raiz.yaml`, plus bas) et n'autorise que certains types de volume, dont `emptyDir`. Le manifeste du `revisor` respecte tout cela dès aujourd'hui. Quand la Leçon 7 mettra l'espace de noms au niveau `restricted`, le `revisor` sera déjà prêt, et il n'y aura rien à réécrire à la dernière minute.

`readOnlyRootFilesystem` n'est **pas** exigé par `restricted`. Le cours le met parce que le `revisor` le supporte : son unique fichier en écriture va dans `/datos`, et c'est pour cela que l'`emptyDir` existe.

**Ce que l'on voit de l'intérieur.** L'image du `revisor` n'a pas de *shell*. Cela a été vérifié :

```text
$ kubectl exec deployment/revisor -- /revisor healthcheck
sano

$ kubectl exec deployment/revisor -- /revisor version
1.6.0

$ kubectl exec deployment/revisor -- sh -c 'id'
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "d8ccff765090d70932ea2f15a41fa34693c57f56ad0106eeb012a0a816fa701d": OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH
[código de salida: 1]
```

`kubectl exec` exécute un programme dans un conteneur déjà en cours d'exécution, comme `docker exec`. Avec `deployment/revisor`, il choisit l'un de ses Pods. Les deux sous-commandes du `revisor` lui-même fonctionnent : `healthcheck` interroge son `/salud` de l'intérieur et répond `sano`, et `version` dit `1.6.0`. Mais `sh` n'existe pas : `executable file not found in $PATH`. Ce n'est pas un défaut, c'est une défense. Celui qui parvient à exécuter quelque chose dans le conteneur ne trouve ni *shell*, ni `curl`, ni gestionnaire de paquets. La façon de déboguer sans *shell* arrive dans la Leçon 3 : un Pod à part, fait pour cela.

Les montages du conteneur confirment le volume de données et révèlent autre chose :

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.containers[0].volumeMounts}{"\n"}'
[{"mountPath":"/datos","name":"datos"},{"mountPath":"/var/run/secrets/kubernetes.io/serviceaccount","name":"kube-api-access-vxlgn","readOnly":true}]
```

`/datos` est ton `emptyDir`. Le second montage, tu ne l'as pas écrit : Kubernetes a monté dans le Pod un **identifiant** pour parler au `kube-apiserver`, celui du compte de service par défaut de l'espace de noms. Le `revisor` ne parle jamais au serveur de l'API, donc il n'en a pas besoin. C'est noté comme dette connue, avec sa leçon : la Leçon 7 donne au `revisor` son propre compte de service, sans permissions, et à partir de là tous les comptes du cours portent `automountServiceAccountToken: false`, pour que cet identifiant ne soit pas monté.

**Le filet de sécurité à l'œuvre.** `runAsNonRoot` semble redondant si tu as déjà écrit `runAsUser: 65532`. Sa valeur apparaît quand quelqu'un se trompe. Ce Pod (`fig02_02.raiz.yaml`, un **programme** qui échoue à dessein) demande les deux choses à la fois : ne pas être `root` et être l'utilisateur 0, qui est `root` :

```yaml
# fig02_02.raiz.yaml — FALLA A PROPÓSITO: pide correr como root (runAsUser: 0)
# y a la vez exige no ser root (runAsNonRoot: true). El kubelet se niega a
# arrancar el contenedor. Es la red de seguridad de runAsNonRoot en acción.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-raiz
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 0
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: revisor
    image: curso-docker-revisor:1.6.0
    imagePullPolicy: IfNotPresent
    env:
    - name: REVISOR_SERVICIOS
      value: "prueba http://prueba:9000/ 2s"
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

```text
$ kubectl apply -f fig02_02.raiz.yaml
pod/revisor-raiz created

$ kubectl get pod revisor-raiz
NAME           READY   STATUS                       RESTARTS   AGE
revisor-raiz   0/1     CreateContainerConfigError   0          10s

$ kubectl get events --field-selector involvedObject.name=revisor-raiz,reason=Failed -o custom-columns=MENSAJE:.message | head -2
MENSAJE
Error: container's runAsUser breaks non-root policy (pod: "revisor-raiz_default(49586352-b84d-462b-9ded-e41bb2d2123a)", container: revisor)
```

Le `kube-apiserver` a accepté le Pod (`created`), parce qu'il n'y a rien d'invalide dans sa forme. Celui qui a refusé, c'est le `kubelet`, au moment de créer le conteneur : `CreateContainerConfigError`, « la configuration du conteneur est inutilisable », et l'événement dit pourquoi : « le `runAsUser` du conteneur enfreint la politique de non-`root` ». L'image était dans le nœud et le programme n'a jamais fini par s'exécuter. C'est la fonction de `runAsNonRoot` : une seconde clé qui ne dépend pas de la bonne écriture de la première. Le Pod a été supprimé à la fin.

**Ce qu'il défend et ce qu'il ne défend pas.** Le `securityContext` limite ce que peut faire **le processus** si quelqu'un le compromet : ne pas être `root`, ne pas gagner de privilèges, ne pas modifier ses fichiers. Il ne défend pas le `revisor` contre des requêtes malveillantes (cela, c'est son code), il ne décide pas qui peut lui parler (cela, c'est le réseau, Leçon 7) et il ne protège pas ta machine du nœud de kind qui, comme tu l'as vu dans la Leçon 0, est un conteneur privilégié.

## Ce qui se fait de travers

**Supprimer et réappliquer face à une erreur.** C'est la scène du lundi. Si la cause n'a pas changé, le nouveau Pod arrive à la même erreur. D'abord on lit le `describe`, ensuite on corrige la cause.

**Utiliser `:latest` dans kind.** Avec `:latest` ou sans tag, la politique de téléchargement par défaut est `Always`, et le nœud essaie d'aller au registre même si tu lui as déjà chargé l'image. De plus, `:latest` ne dit pas quelle version s'exécute : deux nœuds peuvent avoir deux images différentes avec le même tag. Tag fixe et `IfNotPresent`.

**Oublier `--name` dans `kind load docker-image`.** Sans lui, kind cherche le cluster appelé `kind`. S'il n'existe pas, cela échoue. S'il existe et que ce n'est pas le tien, tu as chargé l'image au mauvais endroit et ton cluster est toujours sans elle.

**Créer des Pods isolés pour quelque chose qui doit continuer de tourner.** Un Pod sans propriétaire ne renaît pas. Pour un service, toujours un Deployment.

**Mettre sur un Pod isolé les étiquettes d'un Deployment.** Tu le verras dans l'Exercice 2 : le Deployment ne l'adopte pas, mais tout ce qui cherche par cette étiquette le trouve. C'est un Pod qui apparaît dans les comptes et dans le trafic sans que personne ne veille sur lui.

**Modifier ou supprimer manuellement le ReplicaSet d'un Deployment.** Le Deployment en est le propriétaire et le reconstruit. La documentation le dit en toutes lettres : ne gère pas les ReplicaSets qui appartiennent à un Deployment.

**Toucher à l'étiquette `pod-template-hash`.** C'est le Deployment qui la met pour que ses ReplicaSets ne se marchent pas dessus. La changer casse cette séparation.

**Retirer le `securityContext` « pour que ça marche ».** Si un conteneur ne démarre pas avec le `securityContext` du cours, le problème vient presque toujours de l'image (elle s'exécute en `root`, elle écrit là où elle ne doit pas) et se règle dans l'image ou avec un volume, pas en retirant des défenses au manifeste.

**Se fier à `Running`.** Sans l'`emptyDir`, le `revisor` serait lui aussi `Running` et `1/1`, et échouerait à la première requête qui lui demanderait d'enregistrer le rapport. `Running` veut dire que le processus est vivant, pas qu'il fait bien son travail. La Leçon 5 apprend au cluster à faire la différence.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre et depuis l'état où elle s'est terminée à la fin de 2.8. Avant chaque exercice, `kubectl config current-context` doit dire `kind-curso-k8s-l2` ; s'il dit autre chose, ne continue pas. `correr.sh` les exécute de la même façon, et sa sortie se trouve dans `correr.salida.txt`. **Avant** d'exécuter chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes propres mots.

### Exercice 1 — Sortir un Pod du troupeau

Choisis l'un des Pods du `revisor` et change son étiquette `app` pour une autre valeur :

```bash
kubectl label pod <un-pod-del-revisor> app=fuera --overwrite
```

Prédis : combien y a-t-il de Pods cinq secondes plus tard ? Le Pod que tu as modifié continue-t-il de s'exécuter ? Qui est son propriétaire maintenant ? Vérifie-le avec `kubectl get pods -L app` (l'option `-L` ajoute une colonne avec la valeur de cette étiquette) et avec le `jsonpath` de 2.7.1, `-o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'`, qui fonctionne bien quand la liste des propriétaires est vide (le `[0]` de 2.5 sur une liste vide n'imprime qu'une barre, `/`, et sort avec le code 0, sans signaler qu'il n'y avait rien). À la fin, supprime le Pod que tu as sorti.

### Exercice 2 — Le Pod qui se glisse (projet)

`fig02_03.adoptado.yaml` est un Pod isolé, `revisor-extra`, identique à ceux du `revisor` et **avec** l'étiquette `app: revisor` :

```yaml
# fig02_03.adoptado.yaml — Ejercicio 2: un Pod suelto que SÍ lleva app: revisor.
# Pregunta: el Deployment selecciona app: revisor. ¿Se queda con este Pod? ¿Borra
# uno de los suyos para seguir en tres? ¿Y qué ve quien busca por app=revisor?
apiVersion: v1
kind: Pod
metadata:
  name: revisor-extra
  labels:
    app: revisor
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
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
      value: "prueba http://prueba:9000/ 2s"
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
    emptyDir:
      sizeLimit: 10Mi
```

Avant de l'appliquer, réponds aux trois questions de son commentaire. Ensuite, applique-le et vérifie avec `kubectl get pods -l app=revisor`, `kubectl get deployment revisor` et le sélecteur des ReplicaSets. Pour finir, explique quel problème ce Pod causerait quand, dans la Leçon 3, un Service choisira ses Pods par `app: revisor`. Supprime-le à la fin.

### Exercice 3 — Un tag qui n'existe pas

`fig02_04.etiqueta-mala.yaml` est le même Deployment avec une seule différence : il demande l'image `curso-docker-revisor:1.6.9`, qui n'existe ni dans ton Docker ni dans le cluster. Avant de l'appliquer, prédis : combien de Pods du `revisor` restent en cours d'exécution pendant que le *rollout* est bloqué ? Combien de nouveaux Pods essaie-t-il de créer ? (Indice : les valeurs de `maxSurge` et `maxUnavailable` de 2.8.2.) Ensuite, applique-le, attends avec `kubectl rollout status deployment/revisor --timeout=40s` et regarde `kubectl get pods -l app=revisor` et `kubectl get deployment revisor`. Pour sortir de l'impasse, réapplique `revisor-deployment.yaml` et explique pourquoi le *rollout* se termine instantanément.

### Exercice 4 — Défends le `securityContext`

Un collègue te propose de retirer `readOnlyRootFilesystem: true` et le volume `datos` « parce que ce sont deux choses à maintenir et que le `revisor` démarre quand même ». En cinq phrases au maximum, réponds-lui : ce qu'évite cette ligne, pourquoi le volume existe justement à cause d'elle, ce qui arriverait au rapport si tu retires seulement le volume et laisses la ligne, et si la retirer casse ou non le niveau `restricted`.

## Solutions

### Solution 1

Mesuré dans `correr.salida.txt` :

```text
$ kubectl label pod revisor-55cc969586-6m76h app=fuera --overwrite
pod/revisor-55cc969586-6m76h labeled

$ kubectl get pods -L app
NAME                       READY   STATUS    RESTARTS   AGE   APP
revisor-55cc969586-6m76h   1/1     Running   0          8s    fuera
revisor-55cc969586-7tmfc   1/1     Running   0          7s    revisor
revisor-55cc969586-f8dk6   1/1     Running   0          6s    revisor
revisor-55cc969586-x6vfq   1/1     Running   0          5s    revisor

$ kubectl get pod revisor-55cc969586-6m76h -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=
```

**Quatre Pods.** Celui que tu as modifié reste `Running` : lui changer une étiquette ne l'arrête pas. Mais il a cessé de coïncider avec le sélecteur du ReplicaSet, donc le ReplicaSet l'a **lâché** (son `ownerReferences` est devenu vide) et, comme il en comptait maintenant deux là où il devait y en avoir trois, il en a créé un nouveau. Il reste les trois du troupeau, plus un isolé dont personne ne s'occupe. La documentation de ReplicaSet décrit cette technique : on peut sortir des Pods d'un ReplicaSet en changeant leurs étiquettes, par exemple « pour le débogage ou la récupération de données », et ceux que tu sors ainsi sont remplacés automatiquement. C'est utile : tu mets de côté un Pod qui se comporte mal pour l'étudier, sans que le service perde une réplique. Mais ne l'oublie pas là : le script l'a supprimé à la fin.

### Solution 2

Mesuré dans `correr.salida.txt`. (`fig02_03.adoptado.yaml` déclare le port `http`, comme le modèle du Deployment. Le champ est informatif et ne change aucune de ces sorties, mais il compte pour le trafic de la Leçon 3 : c'est pourquoi le Pod est identique à ceux du Deployment.)

```text
$ kubectl apply -f fig02_03.adoptado.yaml
pod/revisor-extra created

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running   0          13s
revisor-55cc969586-f8dk6   1/1     Running   0          12s
revisor-55cc969586-x6vfq   1/1     Running   0          11s
revisor-extra              1/1     Running   0          5s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           67s

$ kubectl get pod revisor-extra -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=

$ kubectl get replicaset -l app=revisor -o custom-columns=NOMBRE:.metadata.name,DESEADOS:.spec.replicas,SELECTOR:.spec.selector.matchLabels
NOMBRE               DESEADOS   SELECTOR
revisor-55cc969586   3          map[app:revisor pod-template-hash:55cc969586]
revisor-697fb84f97   0          map[app:revisor pod-template-hash:697fb84f97]
```

Les trois réponses :

1. **Il ne le garde pas.** `revisor-extra` reste sans propriétaire. La raison se trouve dans le sélecteur du ReplicaSet : il ne cherche pas seulement `app: revisor`, il cherche aussi `pod-template-hash: 55cc969586`, et `revisor-extra` ne porte pas cette étiquette. La documentation de ReplicaSet dit qu'un ReplicaSet adopte aussitôt un Pod sans propriétaire qui coïncide avec **son** sélecteur, et que c'est pourquoi il convient que les Pods isolés ne portent pas d'étiquettes qui coïncident avec le sélecteur d'un ReplicaSet. Ici, l'étiquette `pod-template-hash` a évité l'adoption.
2. **Il n'en supprime aucun des siens.** Le Deployment dit `3/3` : pour lui, seuls ses trois existent.
3. **Celui qui cherche par `app=revisor` en voit quatre.** `kubectl get pods -l app=revisor` liste `revisor-extra` comme s'il était une réplique de plus.

Ce troisième point est le problème. Un Service, dans la Leçon 3, choisit ses Pods par étiquette, et par celle du manifeste, `app: revisor`, et non par `pod-template-hash`, et il pointe vers le port qui s'appelle `http`. Ce Pod isolé porte les deux : l'étiquette et le port portant ce nom. Donc ce Pod, que personne ne remplace s'il meurt et que personne ne met à jour quand tu changes l'image, recevrait sa part du trafic comme s'il était une réplique de plus. C'est exactement ce que veut dire la documentation quand elle avertit que les sélecteurs qui se chevauchent produisent des comportements inattendus. Le script l'a supprimé à la fin.

### Solution 3

Mesuré dans `correr.salida.txt` :

```text
$ kubectl apply -f fig02_04.etiqueta-mala.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS         RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running        0          55s
revisor-55cc969586-f8dk6   1/1     Running        0          54s
revisor-55cc969586-x6vfq   1/1     Running        0          53s
revisor-b8b699487-fc4gn    0/1     ErrImagePull   0          41s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     1            3           109s
```

**Trois anciens Pods continuent de s'exécuter et il n'y a qu'un seul nouveau Pod, bloqué en `ErrImagePull`.** Avec trois répliques, `maxSurge` vaut 1 (il peut y avoir un Pod en plus) et `maxUnavailable` vaut 0 (aucun ne peut manquer). Le Deployment a créé un nouveau Pod et, pour en retirer un ancien, a attendu que le nouveau soit disponible. Il ne l'a jamais été, donc il n'en a retiré aucun. `kubectl get deployment` le résume : `READY 3/3` (le service reste complet), `UP-TO-DATE 1` (une seule réplique a le nouveau modèle). **Ici, un *rollout* avec une image cassée ne fait pas tomber le service** : il se bloque avec le service intact, parce qu'avec trois répliques `maxUnavailable` vaut 0. Ce n'est pas une loi : avec quatre répliques, 25 % font déjà 1 et le Deployment retirerait bien une réplique saine avant de savoir si la nouvelle démarre, et si un ancien Pod tombe pendant que le *rollout* est bloqué, la capacité baisse. `rollout status` a abandonné au bout de 40 secondes parce que tu le lui as demandé ; le Deployment, de son côté, attendrait 600 secondes (`progressDeadlineSeconds`, dont la valeur par défaut selon la documentation est 600) avant de marquer le *rollout* comme échoué avec la condition `ProgressDeadlineExceeded`.

En réappliquant le bon fichier :

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           109s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-55cc969586   3         3         3       56s
replicaset.apps/revisor-697fb84f97   0         0         0       109s
replicaset.apps/revisor-b8b699487    0         0         0       41s
```

Il s'est terminé instantanément parce que le modèle est redevenu **identique** à celui du ReplicaSet `revisor-55cc969586` : la même image et la même annotation `restartedAt`, que `apply` ne retire pas parce que le fichier ne la déclare pas. Même moule, même *hash*, même ReplicaSet. Le Deployment n'en a pas créé de nouveau : il a ramené à zéro celui qui était cassé, `revisor-b8b699487`, et comme le bon avait déjà ses trois répliques, il n'y avait rien d'autre à faire. Revenir à la version précédente avec `kubectl rollout undo` est la façon courte de faire cela, et elle arrive dans la Leçon 9. Ici, on l'a fait de la façon qu'enseigne le cours : le fichier est la vérité, et on le réapplique.

### Solution 4

Une réponse possible : « `readOnlyRootFilesystem` empêche quelqu'un qui entre dans le conteneur de modifier le programme ou de laisser des outils, et c'est peu coûteux parce que le `revisor` n'écrit qu'un seul fichier. C'est justement à cause de cette ligne que le volume `datos` existe : c'est le seul endroit où le `revisor` peut écrire son rapport. Si tu retires le volume et laisses la ligne, le `revisor` démarre et apparaît `Running`, mais la première fois qu'il essaie d'enregistrer un rapport, il répond 500 avec `no pude guardar el reporte`. Retirer la ligne ne casse pas le niveau `restricted`, qui ne l'exige pas, mais tu renonces à une défense qui ne coûte rien. Et "il démarre quand même" n'est pas la preuve : ce qui compte, c'est de savoir s'il continue de fonctionner quand quelqu'un l'attaque et quand quelqu'un lui demande du travail. »

## Supprimer le cluster

Quand tu as fini les exercices, supprime le cluster de la leçon. Ne laisse rien en vie sur la machine :

```text
$ kind delete cluster --name curso-k8s-l2
Deleting cluster "curso-k8s-l2" ...
Deleted nodes: ["curso-k8s-l2-worker" "curso-k8s-l2-worker2" "curso-k8s-l2-control-plane"]

$ kind get clusters | grep -c curso-k8s-l2
0
```

Le `--name` est obligatoire ici aussi : sans lui, kind supprimerait le cluster appelé `kind`, qui peut appartenir à quelqu'un d'autre ou à un autre projet. Ensuite, supprime le dossier temporaire du `kubeconfig` (celui qu'a créé `mktemp`, avec le préfixe `/tmp/curso-k8s-l2.`) ou ferme ce terminal. Le cluster de la leçon suivante est créé de zéro, comme celui-ci.

## Comment savoir que j'ai réussi

- [ ] Face à `ImagePullBackOff`, tu dis quelle pièce a échoué (le `kubelet` du nœud) et pourquoi le message mentionne `docker.io/library/…`, sans le chercher.
- [ ] Tu vérifies avec `docker exec <nœud> crictl images` si une image se trouve dans un nœud de kind, et tu la charges avec `kind load docker-image <image> --name <cluster>`.
- [ ] Tu écris de mémoire le squelette d'un Deployment et tu expliques pourquoi `selector` et `template.metadata.labels` doivent coïncider.
- [ ] Tu prédis ce qui se passe en supprimant un Pod isolé, un Pod d'un Deployment et le Deployment entier.
- [ ] Tu expliques à quoi sert l'étiquette `pod-template-hash` et pourquoi le Pod de l'Exercice 2 n'a pas été adopté.
- [ ] Tu justifies chaque ligne du `securityContext` du `revisor` et tu dis lesquelles exige le niveau `restricted`.
- [ ] Tu exécutes `programas/02-pods-deployments/correr.sh > /tmp/mi-corrida-l2.txt 2>&1` et tu compares `/tmp/mi-corrida-l2.txt` à `programas/02-pods-deployments/correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) sur ce qui ne change pas d'une exécution à l'autre : trois nœuds `Ready` en `v1.37.0` ; `0` image du `revisor` dans le nœud avant de la charger ; les trois Pods en `ImagePullBackOff` et l'événement `pull access denied` avec `docker.io/library/curso-docker-revisor:1.6.0` ; les trois lignes `not yet present on node … loading...`, une par nœud, y compris celui de contrôle ; `deployment.apps/revisor 3/3` ; `revisor 1.6.0 escuchando en :8080 (1 servicio(s))` ; `sano` et `1.6.0` ; `executable file not found in $PATH` ; le `securityContext` en JSON ; `CreateContainerConfigError` avec `breaks non-root policy` ; deux révisions dans `rollout history` et l'ancien ReplicaSet à `0 0 0` ; et à la fin `sin diferencias con el archivo`. Les suffixes des noms, les IP, le nœud où atterrit chaque Pod, les âges, l'ordre des lignes de `kind load` et le nombre de répétitions de chaque ligne de `rollout status` changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l2`.

## Résumé

Réponds sans regarder la leçon :

1. Pourquoi un nœud de kind ne voit-il pas les images de ton Docker, et que fait `kind load docker-image` ?
2. Quelle différence y a-t-il entre `ErrImagePull` et `ImagePullBackOff` ? Combien de temps le `kubelet` attend-il au maximum entre deux tentatives ?
3. Quels sont les trois éléments de la `spec` d'un Deployment, et que se passe-t-il si le sélecteur ne coïncide pas avec les étiquettes du modèle ?
4. Qui est propriétaire de qui dans la chaîne Deployment, ReplicaSet et Pod, et dans quel champ le lit-on ?
5. Que fait un ReplicaSet d'un Pod dont tu retires l'étiquette de son sélecteur ?
6. Quand un *rollout* se déclenche-t-il ? Pourquoi `rollout restart` en déclenche-t-il un si tu n'as rien changé ?
7. Avec trois répliques et les valeurs par défaut, combien de Pods peut-il y avoir pendant un *rollout* et combien peuvent manquer ?
8. Que fait `runAsNonRoot: true` que `runAsUser: 65532` ne fait pas déjà ?
9. Pourquoi le `revisor` a-t-il besoin d'un `emptyDir` dans `/datos` ?

## Sources

Toutes consultées le 21 octobre 2026.

- [kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/), section « Loading an Image Into Your Cluster » : `kind load docker-image`, l'option `--name` pour les clusters nommés, `crictl images` dans le nœud et l'avertissement sur `:latest` et la politique de téléchargement.
- [Kubernetes, « Images »](https://kubernetes.io/docs/concepts/containers/images/) : les politiques `IfNotPresent`, `Always` et `Never` ; la politique par défaut selon le tag ; Docker Hub comme registre par défaut (`docker.io/library/…`) ; et `ImagePullBackOff`, avec son attente croissante jusqu'à 300 secondes.
- [Kubernetes, « Deployments »](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) : quand un *rollout* se déclenche ; `maxSurge` et `maxUnavailable` (25 %, avec leur arrondi) ; `revisionHistoryLimit` (10) ; `progressDeadlineSeconds` (600) et `ProgressDeadlineExceeded` ; l'étiquette `pod-template-hash` ; l'avertissement de ne pas gérer les ReplicaSets d'un Deployment et celui des sélecteurs qui se chevauchent.
- [Kubernetes, « ReplicaSet »](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/) : son objectif ; l'adoption des Pods sans propriétaire qui coïncident avec son sélecteur ; la recommandation d'utiliser des Deployments ; et comment sortir des Pods d'un ReplicaSet en changeant leurs étiquettes.
- [Kubernetes, « Pods »](https://kubernetes.io/docs/concepts/workloads/pods/) : pourquoi on crée rarement des Pods individuels et jusqu'à quand un Pod reste sur son nœud.
- [Kubernetes, « Pod Lifecycle »](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) : `restartPolicy` vaut `Always` par défaut ; la phase `Pending` inclut le téléchargement des images ; un Pod n'est jamais reprogrammé sur un autre nœud.
- [Kubernetes, « Restrict a Container's Syscalls with seccomp »](https://kubernetes.io/docs/tutorials/security/seccomp/) : sans `seccompDefault`, le profil par défaut est `Unconfined`.
- [Kubernetes, « Owners and Dependents »](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) : le champ `ownerReferences`.
- [Kubernetes, « Labels and Selectors »](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) : ce qu'est une étiquette, qu'elle n'est pas unique, les sélecteurs d'égalité et d'ensembles, et l'absence d'un opérateur « ou ».
- [Kubernetes, « Volumes »](https://kubernetes.io/docs/concepts/storage/volumes/), section `emptyDir` : quand il est créé, quand il est supprimé et `sizeLimit`.
- [Kubernetes, « Configure a Security Context for a Pod or Container »](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) : chaque champ du `securityContext` et ce qu'il contrôle.
- [Kubernetes, « Pod Security Standards »](https://kubernetes.io/docs/concepts/security/pod-security-standards/) : le niveau `restricted` et ses règles de non-`root`, d'élévation de privilèges, de capacités et de `seccomp`.

---

**Suivante :** [Leçon 3 — Services et DNS](03-services-dns.md)
