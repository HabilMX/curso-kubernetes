# Leçon 3 — Services et DNS

Mardi, 10 h 20 du matin. À 11 h 00, l'équipe d'exploitation passe en revue le tableau de bord et veut voir le rapport du `revisor` au vert. Hier, pour se dépanner, un collègue a copié l'IP d'un Pod du service de test, `10.244.1.3`, et l'a collée dans la liste des services que vérifie le `revisor`. Ça a fonctionné tout l'après-midi. Ce matin, le rapport affiche `FALLA` sur toutes les lignes, et personne n'a rien touché. Du moins, c'est ce qu'ils croient : dans la nuit, quelqu'un a redémarré les Pods pour appliquer un changement, les Pods ont été recréés et aucun n'est revenu avec l'IP d'hier. L'adresse que ton collègue a collée n'appartient plus à personne ou, pire, elle appartient à un autre Pod qui n'a rien à voir. Il reste quarante minutes, et la question n'est pas de savoir quelle IP coller maintenant, mais comment cesser de coller des IP.

Kubernetes a déjà résolu ce problème, et la solution tient en deux pièces : un **Service**, c'est-à-dire un nom et une adresse qui ne changent pas même si les Pods qui se trouvent derrière changent sans cesse, et le **DNS du cluster**, qui convertit ce nom en cette adresse pour n'importe quel Pod qui le demande. Cette leçon t'apprend à écrire le premier, à interroger le second et à lire ce qui se passe quand un Service ne trouve personne à qui envoyer du trafic.

**Durée :** 2 × 45 min

**Ce que tu construis :** le `revisor` joignable par son nom à l'intérieur du cluster, et son compagnon, le service de test, joignable lui aussi, de sorte que le rapport vérifie enfin quelqu'un pour de vrai

**Ce que tu apprends :** ce qu'est un Service de type `ClusterIP` et pourquoi c'est le type par défaut ; comment un sélecteur d'étiquettes décide des Pods qui reçoivent le trafic et où cette décision est écrite (`EndpointSlice`) ; la chaîne de trois ports, `port`, `targetPort` et `containerPort` ; comment le DNS du cluster résout les noms et pourquoi `revisor` tout court fonctionne ; `kubectl port-forward` vers `127.0.0.1` ; et un Pod de débogage pour regarder de l'intérieur quand l'image n'a pas de *shell*

**D'où tu viens.** De la [Leçon 2](02-pods-deployments.md) : le `revisor` tourne avec trois répliques dans un Deployment, avec son `securityContext` complet et un `emptyDir` sur `/datos`. Tu sais que chaque Pod a son IP et que cette IP change chaque fois que le Pod est recréé, et tu as vu que l'image du `revisor` n'a ni *shell* ni `curl`. De la [Leçon 0](00-que-es-kubernetes.md), tu apportes deux noms qui n'étaient jusqu'ici que des noms : `kube-proxy`, dont il y a un par nœud, et `coredns`, qui tourne sur le nœud de contrôle. Dans cette leçon, les deux se mettent au travail.

**Ce que cette leçon ne fait pas.** Le `revisor` devient joignable **à l'intérieur** du cluster et, pour toi, par un tunnel temporaire (`port-forward`). Il n'est pas publié vers l'extérieur : un `LoadBalancer` et un point d'entrée avec Gateway API, c'est la [Leçon 6](06-entrar-al-cluster.md). On ne ferme pas non plus encore qui peut parler à qui : aujourd'hui, n'importe quel Pod du cluster atteint le `revisor`, et la [Leçon 7](07-aislar-permisos-red.md) met le réseau en « default-deny ». Et le Service envoie du trafic à n'importe quel Pod en cours d'exécution, sain ou non : dire au cluster quand un Pod est prêt à recevoir du trafic, c'est le travail des probes de la [Leçon 5](05-salud-recursos-apagado.md).

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1 et l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, sur le cluster de trois nœuds de la Leçon 1, appelé ici `curso-k8s-l3`. La machine était un Mac à processeur ARM avec Docker Engine 29.2.1 dans une machine virtuelle Linux (Colima), **pas** Linux Mint, qui est le système de référence du cours. Ce qui change sur ta Mint : l'architecture (`amd64` au lieu de `arm64`), les adresses IP des Pods et des Services, les suffixes aléatoires des noms, les âges, le nœud sur lequel atterrit chaque réplique, le port que Docker attribue au nœud de contrôle et le nombre de requêtes que reçoit chaque réplique en 3.8. Les commandes sont les mêmes. Le parcours complet se trouve dans [`programas/03-services-dns/`](../programas/03-services-dns) : `correr.sh` crée le cluster, y charge les images, laisse le `revisor` comme l'a laissé la Leçon 2, parcourt la leçon dans l'ordre, exécute les Exercices 1 à 3 et supprime le cluster ; il a duré 2 minutes et 16 secondes (la dernière ligne de la sortie le dit : `la corrida completa tardó 136 s`), dont 46 secondes pour créer le cluster et attendre qu'il soit prêt. Sa sortie est `correr.salida.txt`. Dans ce fichier, la section de l'habitude de sécurité apparaît avant celle de l'erreur, parce que le script les exécute dans cet ordre. Le `port-forward` utilise le port `18080` de ta machine ; s'il est occupé, le script s'arrête avant de rien créer et te dit comment en choisir un autre (`PUERTO_LOCAL=18081 ./correr.sh …`). Sur la machine où cette leçon a été écrite, les clusters d'autres leçons tournaient en même temps, et pour ne pas entrer en collision avec eux, le script a été exécuté avec `PUERTO_LOCAL=18300` ; dans `correr.salida.txt` et dans cette leçon, le nombre a été réécrit en `18080`, celui que tu vas utiliser. C'est la seule chose qui a été retouchée dans la sortie.

## À la fin, tu seras capable de

- Expliquer avec un exemple pourquoi aucun programme ne doit conserver l'IP d'un Pod, et ce qu'un Service offre en échange.
- Écrire de mémoire un Service `ClusterIP` avec son `selector` et sa liste de `ports`, et suivre la chaîne `port` → `targetPort` → `containerPort` sur un cas concret.
- Trouver l'`EndpointSlice` d'un Service avec `-l kubernetes.io/service-name=…` et dire, avec elle sous les yeux, quels Pods reçoivent le trafic.
- Résoudre le nom d'un Service depuis un Pod de débogage et expliquer chaque ligne de son `/etc/resolv.conf`, y compris les `NXDOMAIN` qu'affiche `nslookup`.
- Ouvrir un `port-forward` qui n'écoute que sur `127.0.0.1` et dire quand il se rompt.
- Provoquer un Service sans endpoints, le reconnaître à `<unset>` et au code 7 de `curl`, et le corriger.

## Le pourquoi avant le comment

Dans la Leçon 2, tu as laissé trois répliques du `revisor` en marche, et la section 2.4 se terminait par un avertissement : chaque Pod a son IP, et cette IP change chaque fois que le Pod est recréé. C'est la scène du mardi. Un Pod est jetable par conception. Le ReplicaSet le remplace quand il meurt, et le remplaçant est **un autre** Pod, avec un autre nom et une autre adresse. Si les clients conservent l'adresse d'un Pod, chaque remplacement les laisse à parler dans le vide.

Il y a une seconde raison, plus subtile. Même si les Pods ne mouraient jamais, tu en as **trois**. À qui le client parle-t-il ? S'il en choisit un, les deux autres sont superflus. Si tu veux qu'il répartisse, il faudrait lui donner la liste complète et la lui tenir à jour. C'est ce que faisait Compose dans le cours de Docker, de façon cachée : un nom de service que le réseau de Compose résolvait vers ses conteneurs. Dans Kubernetes, la même idée a son nom propre et son manifeste propre.

Un **Service** répond aux deux questions à la fois. Il te donne une IP virtuelle qui ne change pas tant que le Service existe et, derrière elle, la liste vivante des Pods qui la servent. Cette liste, ce n'est pas toi qui l'écris : c'est un contrôleur qui l'écrit, à partir d'une règle que, elle, tu écris : le **sélecteur**. Et pour que personne n'ait à connaître cette IP virtuelle, le **DNS du cluster** lui donne un nom : `revisor`, ou, en nom complet, `revisor.default.svc.cluster.local`.

La leçon comporte neuf parties de concepts, puis les sections habituelles :

1. **Une IP de Pod ne sert pas d'adresse** (3.1) : ce qui change quand un Pod est recréé.
2. **Le Service du `revisor`** (3.2), champ par champ.
3. **Les trois ports** (3.3) : `port`, `targetPort` et `containerPort`.
4. **Sélecteurs et `EndpointSlice`** (3.4) : où la liste des Pods est écrite.
5. **Un Pod de débogage** (3.5), parce que le `revisor` n'a pas de *shell*.
6. **Le DNS du cluster** (3.6).
7. **Le service de test** (3.7) : le `revisor` vérifie enfin quelqu'un.
8. **Comment un Service répartit** (3.8).
9. **`port-forward`** (3.9) : un tunnel depuis ta machine, uniquement vers `127.0.0.1`.

Voici la destination. À la fin de 3.7, un Pod quelconque du cluster demande le rapport au `revisor` par son nom, et le `revisor` trouve lui aussi le service de test par son nom :

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

## Si tu n'as pas l'image du cours de Docker

Cette leçon utilise deux images du cours de Docker : celle du `revisor`, `curso-docker-revisor:1.6.0`, que livre sa Leçon 10, et celle du service qui échoue exprès, `curso-docker-prueba:1.0.0`. Avant de continuer, vérifie que tu as les deux :

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Pour l'autre, la même commande avec `curso-docker-prueba:1.0.0`. S'il te manque celle du `revisor`, construis-la depuis le dépôt de ce cours, avec le `Dockerfile` de sa Leçon 10 sur le dossier `programas/revisor` et avec `--build-arg VERSION=1.6.0`, en la taguant exactement `curso-docker-revisor:1.6.0`. S'il te manque celle de test, construis-la depuis le dossier `programas/servicio-prueba` de ce même dépôt, taguée `curso-docker-prueba:1.0.0`. La [Leçon 2](02-pods-deployments.md) contient, dans cette même section, la liste de ce que le cours demande à une image à toi si tu préfères en utiliser une autre.

Ce que cette leçon demande **en plus** au service de test, et qu'il vaut la peine de lire parce que chaque point explique une ligne de son manifeste :

- **Il écoute en HTTP sur le port 9000** et répond à `GET /` par `200` quand il est sain, par `503` quand il est en panne et tardivement quand il est lent.
- **Il change de mode avec `POST /modo/sano`, `POST /modo/lento` et `POST /modo/caido`**, et indique dans quel mode il se trouve avec `GET /modo`. Tu peux ainsi le casser de l'extérieur sans rien reconstruire.
- **Il tourne avec l'utilisateur 65532**, sans `root`, et **supporte le système de fichiers en lecture seule** sans volume : il n'écrit rien sur le disque.

Et les deux images se chargent dans le cluster comme dans la Leçon 2, avec `kind load docker-image` et le nom du cluster. On peut charger les deux en une seule commande :

```text
$ kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l3
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker2", loading...
```

Six lignes : deux images par trois nœuds. (Dans ton exécution, l'ordre des lignes peut être différent.) Le Pod de débogage de 3.5 utilise une troisième image, `curlimages/curl`, qui n'est **pas** chargée : elle est publique, figée par son empreinte `sha256`, et le nœud sur lequel atterrit le Pod la télécharge depuis Docker Hub la première fois. Tu as besoin d'internet pour cette étape.

## Les concepts

### 3.1 Une IP de Pod ne sert pas d'adresse

Cette leçon utilise son propre cluster, `curso-k8s-l3`, avec la configuration à trois nœuds de la Leçon 1, tout juste créé. Crée-le ainsi, depuis la racine du dépôt du cours, avec le même soin que dans la Leçon 1 :

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l3.XXXX)/kubeconfig"
# curso-k8s-l3 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l3 --config programas/03-services-dns/kind-curso.yaml
# Debe decir kind-curso-k8s-l3. Si dice otra cosa, no sigas.
kubectl config current-context
```

Le `export` ne vaut que dans ce terminal. Si tu en ouvres un autre (en 3.9, tu voudras en avoir un pour le `port-forward`), répète le `export` avec le même chemin, sinon `kubectl` parlera à un autre cluster. Charge ensuite les deux images, comme on l'a vu plus haut, et applique le Deployment de la Leçon 2 tel quel, sans changer une virgule ; à partir d'ici, les commandes s'exécutent dans `programas/03-services-dns/` (entre avec `cd programas/03-services-dns`, sinon `kubectl apply -f revisor-deployment.yaml` dira que le chemin n'existe pas). Les sorties proviennent de l'exécution de `correr.sh`, qui fait exactement cela :

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

La première commande est l'habitude de toujours : avant de changer quoi que ce soit, demander à quel cluster tu parles. Répète-la **avant chaque** `apply`, `delete`, `rollout restart` ou `port-forward` de la leçon, pas seulement ici ; le script le fait tout seul, avant chaque `kubectl`, et s'arrête si la réponse n'est pas `kind-curso-k8s-l3`. Regarde maintenant la colonne `IP`. Les trois adresses commencent par `10.244.` : c'est le réseau de Pods que kind met en place par défaut. Son [guide de configuration](https://kind.sigs.k8s.io/docs/user/configuration/) le dit ainsi : « par défaut, kind utilise le sous-réseau de Pods `10.244.0.0/16` pour IPv4 ». Chaque nœud reçoit un morceau de ce réseau : dans cette exécution, les Pods de `worker2` sont en `10.244.1.x` et ceux de `worker` en `10.244.2.x` (le morceau qui échoit à chaque nœud change d'une exécution à l'autre).

Voici maintenant la scène du mardi, en petit. On en supprime un :

```text
$ kubectl delete pod revisor-697fb84f97-82d87
pod "revisor-697fb84f97-82d87" deleted from default namespace

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-drv5h   1/1     Running   0          2s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          2s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-z79jh   1/1     Running   0          1s    10.244.1.3   curso-k8s-l3-worker2   <none>           <none>
```

Le ReplicaSet l'a remplacé en une seconde, comme dans la Leçon 2 (si tu listes les Pods juste après la suppression, tu verras peut-être l'ancien en `Terminating` et le nouveau en `ContainerCreating` ; attends quelques secondes ou exécute `kubectl rollout status deployment/revisor`, et il y en aura trois). Mais le nouveau Pod, `z79jh`, n'est pas celui qui est mort : autre nom et autre IP (`10.244.1.3` au lieu de `10.244.1.2`). Remarque qu'il a atterri sur le **même** nœud, `worker2`, et que l'adresse a pourtant changé : il n'est pas nécessaire que le Pod déménage pour que son IP soit différente. Dans une autre exécution, il peut en plus atterrir sur un autre nœud. L'adresse `10.244.1.2` n'appartient plus à personne. Si un programme l'avait conservée, il parle depuis cette seconde à une adresse vide. Et si, dans un moment, un autre Pod naît sur `worker2`, il peut recevoir précisément cette adresse, et le programme parlerait à un inconnu sans s'en apercevoir.

Ce n'est pas un défaut de kind ni de ce cluster : c'est la conception. Les Pods sont, selon les mots de la [documentation des Pods](https://kubernetes.io/docs/concepts/workloads/pods/), des entités « relativement éphémères et jetables ». Ce qui doit être stable, ce n'est pas le Pod, c'est l'**accès** à l'ensemble de Pods. C'est cela, un Service.

### 3.2 Le Service du `revisor`

La [documentation des Services](https://kubernetes.io/docs/concepts/services-networking/service/) le définit en une phrase : un Service est « une méthode pour exposer une application réseau qui s'exécute sous la forme d'un ou plusieurs Pods dans ton cluster ». Et elle précise ce qu'il conserve : chaque Service « définit un ensemble logique de *endpoints* (normalement, ces *endpoints* sont des Pods) ainsi qu'une politique sur la manière de rendre ces Pods accessibles ».

Voici celui du `revisor`. C'est un **programme** : il s'applique tout seul et vit dans `programas/03-services-dns/revisor-service.yaml`.

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

Il est beaucoup plus court que le Deployment, et il se lit de la même façon, de l'extérieur vers l'intérieur.

#### 3.2.1 Ce que c'est et comment il s'appelle

`apiVersion: v1` et `kind: Service` : les Services vivent dans le groupe central de l'API, le même que celui des Pods, qui ne porte pas de nom. `metadata.name: revisor` est le nom du Service, et ce n'est pas un détail : **c'est ce nom que tu vas écrire dans les URL**. Le DNS du cluster (3.6) le convertit en adresse. C'est pourquoi le Service s'appelle comme le Deployment, bien qu'il n'y soit pas obligé : le Deployment s'appelle `revisor` pour toi, et le Service s'appelle `revisor` pour les clients. L'étiquette `app: revisor` du Service lui-même sert, comme dans le Deployment, à ce que tu le retrouves avec `-l app=revisor` ; elle ne décide de rien pour le trafic.

#### 3.2.2 Quel type de Service

`type: ClusterIP` dit quelle sorte d'adresse il reçoit. La documentation des Services décrit ce type ainsi : « expose le Service sur une IP interne au cluster. Choisir cette valeur rend le Service accessible uniquement depuis l'intérieur du cluster. C'est la valeur par défaut utilisée si tu ne précises pas de `type` ». Le manifeste l'écrit bien que ce soit la valeur par défaut, pour la même raison que la Leçon 2 a écrit `IfNotPresent` : pour que celui qui le lit n'ait pas à connaître la règle, et pour que la décision de **ne pas** publier reste visible. La même page dit comment on publie quelque chose vers internet : « avec un Ingress ou un Gateway ». C'est la Leçon 6. Aujourd'hui, exprès, rien ne sort.

#### 3.2.3 À qui il envoie du trafic

`selector: {app: revisor}` est la règle : « mes Pods sont ceux qui portent l'étiquette `app: revisor` ». C'est la même étiquette que le Deployment met dans son modèle, et c'est pourquoi le Service trouve les trois répliques. Remarque ce qu'il **ne** dit **pas** : il ne mentionne ni le Deployment, ni le ReplicaSet, ni le `pod-template-hash`. Le Service ne sait pas qu'un Deployment existe. Il choisit des Pods par étiquette, et rien d'autre. L'Exercice 2 te montre la conséquence, celle que la Leçon 2 t'avait annoncée.

#### 3.2.4 Par où

`ports` est une liste ; ici, elle ne contient qu'un seul port, nommé `http`. `port: 80` est le port **du Service** : celui qu'utilisent les clients. `targetPort: http` est le port **du Pod** vers lequel le trafic est réexpédié, et il n'est pas donné sous forme de nombre mais par **nom**. La section 3.3 suit cette chaîne avec le cluster sous les yeux.

#### 3.2.5 L'appliquer et le regarder

```text
$ kubectl apply -f revisor-service.yaml
service/revisor created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   41s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP    2s
```

Deux Services. Le tien, `revisor`, a reçu l'IP `10.96.144.175`. Elle appartient à un autre réseau, `10.96.`, distinct de celui des Pods : le guide de kind dit que, par défaut, il utilise « le sous-réseau de Services `10.96.0.0/16` pour IPv4 ». L'autre, `kubernetes`, ce n'est pas toi qui l'as créé : c'est le Service du `kube-apiserver` lui-même, sur la première adresse de ce réseau, pour que les Pods qui ont besoin de parler à l'API le trouvent par nom comme n'importe quel autre. `EXTERNAL-IP <none>` : il n'y a pas d'adresse vers l'extérieur, comme demandé.

`kubectl describe` rassemble tout ce qui concerne le Service :

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

Les lignes qui comptent aujourd'hui :

- `Selector: app=revisor` : la règle que tu as écrite.
- `IP: 10.96.144.175` : l'adresse stable. La documentation l'appelle *cluster IP* et explique qu'« elle est utilisée par le mécanisme d'adresses IP virtuelles ». Elle n'appartient à aucune machine ni à aucun Pod ; 3.8 raconte qui la fait fonctionner.
- `Port: http 80/TCP` et `TargetPort: http/TCP` : les deux extrémités de la chaîne de ports.
- `Endpoints: 10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080` : **les trois répliques**, avec leur IP et leur port réel. Compare-les avec le deuxième tableau de 3.1 : ce sont exactement celles des trois Pods vivants, y compris la `10.244.1.3` du Pod qui vient de naître. La `10.244.1.2` du Pod supprimé n'apparaît pas. Personne ne l'a retirée à la main.
- `Session Affinity: None` : chaque connexion peut aller vers n'importe quelle réplique ; 3.8 le mesure.

Cette liste de `Endpoints` est la réponse à la scène : le client utilise `10.96.144.175`, qui ne change pas, et le cluster tient à jour ce à quoi elle correspond réellement.

### 3.3 Les trois ports

Dans la scène de Docker, un seul port comptait : le `-p 8080:8080` de `docker run`. Ici, il y en a trois, et chacun est déclaré par un objet différent. Les confondre est l'une des erreurs les plus courantes quand on débute ; cela vaut donc la peine de les suivre avec le cluster sous les yeux.

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

(Le deuxième `jsonpath` utilise `{range .items[*]}…{end}`, qui répète ce qui se trouve au milieu pour chaque Pod de la liste. C'est la façon de demander une valeur à plusieurs objets à la fois.)

Voici comment se lit la chaîne, du client jusqu'au programme :

| Port | Où il est déclaré | Valeur dans le `revisor` | Qui l'utilise |
|---|---|---|---|
| `port` | le Service | `80` | le client : `http://revisor/…` va au 80, le port HTTP par défaut |
| `targetPort` | le Service | `http` (un nom) | le cluster, pour savoir vers quel port du Pod réexpédier |
| `containerPort` | le modèle du Pod, avec son nom | `http` = `8080` | celui qui cherche le nom `http` dans le Pod ; le programme écoute sur le 8080 de lui-même |

La troisième commande montre comment le nom a été résolu : l'`EndpointSlice` (3.4) contient déjà le nombre, `8080`, qu'elle a tiré des Pods. La documentation des Services décrit les deux éléments qui rendent cela possible. Le premier : « un Service peut faire correspondre n'importe quel `port` entrant à un `targetPort`. Par défaut, et par commodité, le `targetPort` prend la même valeur que le champ `port` ». Le second : « les définitions de ports des Pods ont des noms, et tu peux te référer à ces noms dans l'attribut `targetPort` d'un Service ».

Pourquoi le cours utilise-t-il le nom et non le nombre ? Parce que de cette façon, le nombre vit à **un seul endroit**, le modèle du Pod. Si un jour le `revisor` écoute sur un autre port, tu changes `containerPort` dans le Deployment et le Service continue de fonctionner sans y toucher. Avec `targetPort: 8080`, tu devrais te souvenir de modifier deux fichiers, et le jour où tu en oublies un, le Service envoie du trafic vers un port où personne n'écoute. L'Exercice 1 t'apprend exactement à quoi cela ressemble.

Une précision qui évite une confusion fréquente : la Leçon 2 a dit que `containerPort` **ne publie rien**. C'est toujours vrai. Le programme écoute sur le 8080 même si tu ne le déclares pas. Le déclarer avec un nom sert à ce que le Service puisse le viser par ce nom, et à ce que celui qui lit le manifeste sache où il écoute.

Et le 80 du Service ? Ce n'est ni le `revisor` ni aucun autre processus qui l'ouvre : il fait partie de l'adresse virtuelle du Service. Le programme continue d'écouter sur son 8080, avec toutes les restrictions de la Leçon 2, et le cluster traduit. Ainsi les clients écrivent `http://revisor/` sans numéro, et personne n'a eu à changer le port du programme pour y parvenir.

### 3.4 Sélecteurs et `EndpointSlice`

#### 3.4.1 Où la liste est écrite

La liste de `Endpoints` qu'a montrée `describe` n'est pas conservée dans le Service. Elle vit dans un autre objet, un **EndpointSlice**. La [documentation des EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) le résume : « les EndpointSlices tiennent le compte des adresses IP des *endpoints* d'un *backend*. Normalement, ils sont associés à un Service, et les *endpoints* sont généralement des Pods ».

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.2.3,10.244.1.3   3s
```

Remarque comment on l'a cherché : pas par son nom (`revisor-6jh2f` porte un suffixe aléatoire, comme un Pod), mais par l'étiquette `kubernetes.io/service-name=revisor`. La même page explique pourquoi cette étiquette existe : chaque EndpointSlice porte une référence à son propriétaire et « une étiquette `kubernetes.io/service-name` qui permet de retrouver facilement tous les EndpointSlices appartenant à un Service ». C'est la même idée que dans la Leçon 2 : on cherche par étiquette, jamais par un nom qui change.

Pourquoi « tous » ? Parce qu'un Service peut en avoir plusieurs. La documentation dit que, par défaut, le plan de contrôle crée des EndpointSlices « de pas plus de 100 *endpoints* chacun ». Avec trois répliques, tout tient dans un seul ; avec trois cents, il y en aurait au moins trois. C'est pourquoi le tableau ci-dessus est une liste, même si aujourd'hui elle n'a qu'une ligne.

Avec `jsonpath`, on voit chaque *endpoint* de l'intérieur, et son propriétaire :

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.2.3 revisor-697fb84f97-drv5h curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{"\n"}'
Service/revisor
```

Chaque ligne dit quelle adresse, de quel Pod (`targetRef`), sur quel nœud et si elle est prête. Et le propriétaire de l'EndpointSlice est le Service, avec le même champ `ownerReferences` que dans la Leçon 2. C'est la même chaîne de propriétaires : si tu supprimes le Service, son EndpointSlice s'en va.

#### 3.4.2 Qui l'écrit

Personne ne l'écrit à la main. La documentation de débogage des Services le raconte ainsi : « à l'intérieur de Kubernetes, il y a une boucle de contrôle qui évalue le sélecteur de chaque Service et enregistre le résultat dans un ou plusieurs objets EndpointSlice » ([« Debug Services »](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)). C'est de nouveau le thermostat de la Leçon 0, avec un autre état désiré : « ce Service envoie du trafic aux Pods qui correspondent à son sélecteur ». Quand l'ensemble des Pods change, le contrôleur corrige la liste.

On le voit en supprimant un autre Pod :

```text
$ kubectl delete pod revisor-697fb84f97-drv5h
pod "revisor-697fb84f97-drv5h" deleted from default namespace

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true
10.244.1.4 revisor-697fb84f97-mjbff curso-k8s-l3-worker2 ready=true
```

Le Pod `drv5h` et son `10.244.2.3` sont sortis de la liste, et le nouveau Pod, `mjbff`, est entré avec `10.244.1.4`. Même EndpointSlice, contenu nouveau. Le Service n'a pas changé du tout : son IP est toujours `10.96.144.175`. Voilà toute l'idée.

#### 3.4.3 Ce que signifie `ready=true`

La colonne `ready` est celle qui décide si un *endpoint* reçoit du trafic. La documentation des EndpointSlices dit que la condition `serving` indique que l'*endpoint* est en train de servir et que, pour un Pod, elle « correspond à la condition `Ready` du Pod » ; et que `ready` est, en substance, « `serving` et non `terminating` ». Traduit : un Pod reçoit du trafic tant qu'il est prêt et qu'il n'est pas en train de s'arrêter.

Aujourd'hui, « prêt » ne veut pas dire grand-chose : le `revisor` n'a pas de probes, donc son Pod est marqué prêt dès que le conteneur démarre, même si le programme n'écoute pas encore. C'est pourquoi c'est la Leçon 5 qui complète cette colonne : avec une readiness probe, le Pod n'est marqué prêt que lorsque `/salud` répond, et le Service cesse de lui envoyer du trafic s'il cesse de répondre.

#### 3.4.4 `Endpoints`, l'ancienne API

Tu vas trouver dans des tutoriels la commande `kubectl get endpoints`. Elle fonctionne encore, mais regarde ce qu'elle dit :

```text
$ kubectl get endpoints revisor
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS                                         AGE
revisor   10.244.1.3:8080,10.244.1.4:8080,10.244.2.2:8080   6s
```

`Endpoints` est l'API précédente, et le serveur lui-même te prévient : « obsolète depuis la v1.33 ; utilise EndpointSlice ». La documentation des Services la marque de la même façon (« Deprecated since Kubernetes v1.33 ») et donne les raisons : elle ne convient pas aux clusters IPv4 et IPv6 à la fois, elle ne contient pas les informations que demandent les nouvelles fonctionnalités, et elle « tronque la liste des *endpoints* si elle est trop longue pour tenir dans un seul objet ». Ce cours utilise EndpointSlice. `Endpoints` est dépréciée, pas retirée : elle fonctionne encore, comme tu viens de le voir, mais ce n'est plus l'API recommandée. On la nomme ici pour que tu la reconnaisses quand tu la verras, ce qui est la règle du cours pour ce qui est déprécié et retiré : on le nomme pour le reconnaître, on ne l'enseigne pas.

### 3.5 Un Pod de débogage

#### 3.5.1 Pourquoi il le faut

Pour tester le Service, tu as besoin d'un client **à l'intérieur** du cluster, parce qu'un `ClusterIP` n'est joignable que de là. Le candidat évident serait le `revisor` lui-même, mais dans la Leçon 2 tu as vu que son image n'a ni *shell* ni `curl` : `kubectl exec deployment/revisor -- sh` échoue avec `executable file not found in $PATH`. C'est une protection, et le cours ne va pas l'enlever pour déboguer. La sortie est autre : un Pod à part, fait pour regarder, qu'on crée quand il le faut et qu'on supprime quand on a fini.

C'est un **programme** : `programas/03-services-dns/depurar.yaml`.

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

#### 3.5.2 Champ par champ

C'est un Pod isolé, exprès : dans la Leçon 2, tu as appris qu'un Pod sans propriétaire n'est pas recréé, et c'est ici précisément ce que tu veux. Quand tu le supprimes, il reste supprimé. Pour le reste :

- **L'image** est `curlimages/curl`, une petite image avec `curl` et les outils de base d'Alpine Linux (`sh`, `nslookup`, `cat`), qui viennent de BusyBox. Elle est figée par son empreinte `sha256`, et pas seulement par son tag `8.22.0`. Un tag peut être déplacé vers une autre image dans le registre ; une empreinte, non. Comme cette image-ci se télécharge bien depuis internet, l'empreinte identifie par son contenu le manifeste de l'image, de sorte que ton cluster téléchargera les mêmes couches que celles qui ont été testées ici, même si quelqu'un déplace le tag `8.22.0` dans le registre.
- **`imagePullPolicy` n'est pas écrit.** À la différence du `revisor`, ce manifeste ne le déclare pas : avec un tag qui n'est pas `:latest`, la valeur par défaut est `IfNotPresent`, la même que la Leçon 2 avait écrite en clair. Ici, on laisse la valeur par défaut.
- **`command: ["sleep", "3600"]`** remplace le programme de l'image, qui serait un `curl` qui se termine aussitôt, par une attente d'une heure. Ainsi le Pod reste vivant et tu peux lui envoyer des commandes avec `kubectl exec`. Avec `restartPolicy: Never`, quand l'heure est écoulée, le Pod se termine et n'est pas redémarré.
- **Le `securityContext`** est le même schéma que celui du `revisor`, avec l'utilisateur 100 et le groupe 101, ceux que l'image de curl apporte. Qu'un Pod soit « seulement pour déboguer » n'est pas une excuse pour qu'il tourne en `root` : un Pod de débogage oublié est précisément celui que quelqu'un trouve plus tard.
- **`resources`** fixe un plancher et un plafond de CPU et de mémoire. Ils sont expliqués dans la Leçon 5 ; ils sont là parce qu'un Pod d'appui ne doit pas pouvoir avaler le nœud.
- **`automountServiceAccountToken: false`** évite que soit monté l'identifiant de l'API que la Leçon 2 a trouvé dans le `revisor`. `curl` n'en a pas besoin. La Leçon 7 le généralise.
- **L'étiquette `acceso-revisor: permitido`** ne fait encore rien. Dans la Leçon 7, quand le réseau sera fermé, ce sera la clé qui permet à ce Pod de parler au `revisor`. Elle est là dès aujourd'hui pour que le même fichier serve dans les deux leçons.

#### 3.5.3 Premier contact

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

`id` confirme l'utilisateur 100. Et les deux dernières requêtes sont le cœur de la leçon. La première utilise le **nom** du Service, sans port (le 80 est celui de HTTP par défaut) et sans rien savoir des Pods. La seconde utilise l'IP du Service. Les deux arrivent sur une réplique du `revisor`, qui répond à son `/salud` avec la version `1.6.0`. Personne n'a écrit d'IP de Pod nulle part. Que le nom `revisor` se soit converti en `10.96.144.175`, c'est le travail du DNS du cluster, et c'est ce qui suit.

### 3.6 Le DNS du cluster

#### 3.6.1 Qui répond

Tout Pod sait à qui demander les noms parce que le `kubelet` lui écrit un `/etc/resolv.conf` à sa création :

```text
$ kubectl exec depurar -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

Trois lignes. Celle du milieu dit à qui demander : `10.96.0.10`. Cette adresse se trouve dans le réseau des Services, et ce n'est pas un hasard :

```text
$ kubectl get service -n kube-system kube-dns
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   74s

$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-cf8pv   1/1     Running   0          65s   10.244.0.2   curso-k8s-l3-control-plane   <none>           <none>
coredns-559f6c778d-h2hgl   1/1     Running   0          65s   10.244.0.4   curso-k8s-l3-control-plane   <none>           <none>
```

Le DNS du cluster est, lui-même, **un Service avec son sélecteur** : `kube-dns`, dans l'espace de noms `kube-system`, port 53 (celui du DNS), qui envoie les questions aux deux Pods de `coredns` que tu as vus dans la Leçon 0. Exactement le schéma que tu viens d'écrire pour le `revisor`. Si demain l'un des `coredns` tombe en panne, son Service reste en `10.96.0.10` et l'autre répond. Kubernetes utilise ses propres pièces pour résoudre son propre problème.

(`-n kube-system` dit à `kubectl` dans quel espace de noms chercher. Jusqu'ici, tout a vécu dans `default`. Les espaces de noms s'étudient dans la Leçon 7.)

#### 3.6.2 Le nom complet d'un Service

La [documentation du DNS pour les Services et les Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) donne la forme du nom : un Service normal reçoit un enregistrement dont le nom est de la forme `mon-service.mon-espace.svc.domaine-du-cluster`, qui « se résout vers la *cluster IP* du Service ». Pour le tien :

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

Cela se lit de gauche à droite, du particulier au général :

| Partie | Ce que c'est |
|---|---|
| `revisor` | le nom du Service |
| `default` | l'espace de noms où il vit |
| `svc` | que c'est un Service (et pas autre chose) |
| `cluster.local` | le domaine du cluster, celui par défaut |

Et la réponse, `10.96.144.175`, est l'IP du Service, celle de 3.2. Le DNS ne te donne pas les IP des Pods : il te donne l'adresse stable, et c'est le Service qui se charge de répartir.

#### 3.6.3 Pourquoi `revisor` tout court fonctionne

En 3.5, tu as écrit `http://revisor/salud`, et non le nom complet, et cela a fonctionné. C'est la première ligne de `resolv.conf`, `search`, qui le rend possible. La documentation du DNS l'explique : les requêtes « peuvent être étendues en utilisant le `/etc/resolv.conf` du Pod » et « les valeurs de l'option `search` sont utilisées pour étendre les requêtes ». Ce n'est pas le Pod qui étend, mais la bibliothèque DNS du programme qui interroge. Quand `curl` demande `revisor`, sa bibliothèque lui ajoute, un par un, les domaines de `search` : `revisor.default.svc.cluster.local`, `revisor.svc.cluster.local` et `revisor.cluster.local`, et s'arrête au premier qui répond. Ici, le premier répond déjà. En 3.6.4, tu verras que le `nslookup` de cette image ne s'arrête pas : il les demande tous à la fois.

La troisième ligne, `options ndots:5`, décide **quand** cette liste est utilisée. Le guide de débogage des Services le dit ainsi : la ligne `options` « doit fixer `ndots` assez haut pour que ta bibliothèque DNS prenne en compte les chemins de recherche », et Kubernetes le met à 5 par défaut, « assez haut pour couvrir tous les noms qu'il génère ». En pratique : un nom qui contient moins de cinq points est d'abord essayé avec la liste `search`. `revisor` n'en contient aucun, donc il est étendu. C'est aussi pourquoi la forme intermédiaire, avec l'espace de noms, fonctionne :

```text
$ kubectl exec depurar -- curl -s http://revisor.default/salud
{"estado":"vivo","version":"1.6.0"}
```

`revisor.default` plus `svc.cluster.local`, le deuxième élément de `search`, donne le nom complet. La documentation en fait une règle : les requêtes qui ne précisent pas l'espace de noms « se limitent à l'espace de noms du Pod » ; pour atteindre un Service d'un autre espace, on écrit l'espace dans le nom. Aujourd'hui, tout vit dans `default` et cela ne se remarque pas. À partir de la Leçon 7, quand le `revisor` déménagera dans son propre espace, `revisor.revisor` sera la façon de l'atteindre depuis l'extérieur de celui-ci.

#### 3.6.4 Les `NXDOMAIN` qui ne sont pas une erreur

Demande maintenant à `nslookup` le nom court :

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

On dirait un désastre : quatre « je ne trouve pas » et un code de sortie 1. Lis-le lentement. Au milieu de tout cela se trouve la bonne réponse : `revisor.default.svc.cluster.local` vaut `10.96.144.175`. Les quatre `NXDOMAIN` (*non-existent domain*, « ce nom n'existe pas ») sont les **autres** extensions de la liste `search` : `revisor.svc.cluster.local` et `revisor.cluster.local` n'existent pas, et c'est vrai, elles n'existent pas. Elles apparaissent deux fois chacune parce que le `nslookup` de cette image, celui de BusyBox, pose deux questions pour chaque nom : son adresse IPv4 (enregistrement `A`) et son adresse IPv6 (enregistrement `AAAA`). Pour le nom complet, qui existe bel et bien, il a lui aussi posé les deux ; comme le Service n'a pas d'adresse IPv6, cette seconde question revient sans enregistrements, et cela ne s'affiche pas comme une erreur (un nom qui existe mais n'a pas ce type d'enregistrement est différent d'un nom qui n'existe pas). Il affiche chaque échec et, s'il y en a eu un, se termine avec le code 1 même s'il a trouvé la réponse. L'ordre des lignes change d'une exécution à l'autre, parce que les questions partent en même temps : dans une autre exécution de cette même leçon, la réponse est sortie à la fin, après les quatre `NXDOMAIN`.

`curl` ne se plaint de rien de tout cela parce qu'il ne lui importe de trouver qu'**une** adresse, et il l'a trouvée. La leçon pratique : avec `nslookup`, demande le nom complet ; dans cette image, il sort proprement, comme tu l'as vu en 3.6.2. Attention au pourquoi : ce n'est pas que la règle le garantisse. Avec `ndots:5`, même `revisor.default.svc.cluster.local` (quatre points) compte comme « court » pour une bibliothèque qui respecte la règle à la lettre, et c'est précisément le coût connu de `ndots:5` : des requêtes en trop même avec le nom complet. Que la sortie soit propre est le comportement mesuré de ce `nslookup`. Pour qu'un nom soit absolu et ne soit jamais étendu, termine-le par un point : `revisor.default.svc.cluster.local.` Et si tu vois des `NXDOMAIN` avec le nom court, cherche la ligne `Name:` avant de t'alarmer.

Pour comparer, voici à quoi ressemble un nom qui n'existe vraiment pas :

```text
$ kubectl exec depurar -- nslookup no-existe.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

Pas de ligne `Name:` et pas de `Address:` à la fin. Cette absence est la différence, pas les `NXDOMAIN`.

### 3.7 Le service de test : le `revisor` vérifie enfin quelqu'un

Depuis la Leçon 2, le `revisor` a dans son manifeste `REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s`. Cette ligne était déjà une promesse sur cette leçon : elle lui demande de vérifier un service appelé `prueba` à l'adresse `http://prueba:9000/`, avec 2 secondes de limite. Cette URL utilise un **nom**, pas une IP. Regarde ce qui se passe aujourd'hui, avant que ce nom existe :

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        4ms  no responde: Get "http://prueba:9000/": dial tcp: lookup prueba on 10.96.0.10:53: no such host
```

Le `revisor` fait bien son travail : il dit que `prueba` échoue, et pourquoi. `lookup prueba on 10.96.0.10:53: no such host` : il a demandé au DNS du cluster (la `10.96.0.10` de 3.6) le nom `prueba`, et le DNS a répondu qu'il n'existe pas. Il n'y a ni Pod, ni Service, ni nom.

Voici les deux manifestes du service de test. Les deux sont des **programmes** : `prueba-deployment.yaml` et `prueba-service.yaml`.

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

Le Deployment est le schéma de la Leçon 2, avec le même `securityContext` et **une** réplique : c'est un service de test, il n'en faut pas plus. Il n'a pas de volume, parce qu'il n'écrit rien sur le disque. Le Service a une différence avec celui du `revisor` qui vaut la peine d'être notée : ici, `port` vaut `9000`, comme celui du conteneur, parce que l'URL que le `revisor` a déjà écrite le demande (`http://prueba:9000/`). Le `targetPort` reste donné par nom. La règle n'est pas « le Service toujours sur le 80 » : le port du Service est celui qu'attendent tes clients.

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

`OK`, en 1 milliseconde, avec le code `200`. Le `revisor` n'a pas été redémarré, sa configuration n'a pas été modifiée, aucune IP ne lui a été donnée. Son manifeste disait `prueba` depuis le début ; la seule chose qui a changé, c'est que ce nom existe maintenant. Chaque fois que le `revisor` construit son rapport, il redemande le nom. C'est ce dont la scène du mardi avait besoin : la configuration dit **à qui**, pas **où il se trouve**.

On le casse maintenant exprès, dans ses trois modes :

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

Chaque mode raconte quelque chose de différent. En `caido`, `prueba` répond, mais avec `503` : le `revisor` dit `FALLA codigo 503`. En `lento`, `prueba` met plus que les 2 secondes que lui accorde la liste, et le `revisor` abandonne à `2.002s` avec `se acabo el tiempo de espera`. (L'état `LENTO` du `revisor` est destiné à un service qui répond bien mais met plus d'1 seconde **sans** dépasser la limite ; ici, elle a été dépassée.) Et en `sano`, tout revient à `OK`. Les trois cas sont passés par le Service et par le DNS du cluster, et le `revisor` les a distingués.

Avec cela, le `revisor` fait à l'intérieur du cluster la même chose que ce qu'il faisait dans Compose dans le cours de Docker. Le tableau de traduction de la Leçon 0 l'annonçait : le nom du service dans le réseau de Compose devient le DNS du cluster.

### 3.8 Comment un Service répartit

#### 3.8.1 Le mesurer

Le Service a trois répliques derrière lui. Les utilise-t-il toutes les trois ? On le mesure avec trente requêtes et le journal du `revisor`, qui écrit une ligne pour chaque requête qu'il traite :

```text
$ kubectl exec depurar -- sh -c 'for i in $(seq 1 30); do curl -s -o /dev/null http://revisor/salud; done; echo 30 peticiones'
30 peticiones

$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /salud' | cut -d' ' -f1 | sort | uniq -c
   6 [pod/revisor-697fb84f97-mjbff/revisor]
  13 [pod/revisor-697fb84f97-nq74v/revisor]
  14 [pod/revisor-697fb84f97-z79jh/revisor]
```

La deuxième commande assemble plusieurs outils, et il vaut la peine de la démonter :

- `kubectl logs -l app=revisor` demande le journal de **tous** les Pods portant cette étiquette, pas d'un seul ;
- `--prefix` fait précéder chaque ligne du Pod d'où elle provient ;
- `--tail=-1` demande le journal complet (avec un sélecteur d'étiquettes, `kubectl logs` n'affiche par défaut que les dernières lignes de chaque Pod) ;
- `grep` ne garde que les lignes de `/salud`, `cut` le préfixe, et `sort | uniq -c` compte combien il y en a pour chaque Pod.

Les trois répliques ont reçu du trafic. Elles totalisent 33 et non 30 parce que les trois requêtes vers `/salud` de 3.5 et 3.6 figurent aussi dans le journal. Et la répartition n'est pas égale : 14, 13 et 6. Elle n'a aucune raison de l'être.

#### 3.8.2 Qui fait le travail

L'IP d'un Service n'appartient à aucune machine. La [référence des IP virtuelles](https://kubernetes.io/docs/reference/networking/virtual-ips/) dit qui la fait fonctionner : « le composant `kube-proxy` est responsable de la mise en œuvre d'un mécanisme d'IP virtuelle pour les Services ». `kube-proxy` tourne sur chaque nœud (les trois que tu as vus dans la Leçon 1), lit les EndpointSlices et écrit des règles dans le réseau du nœud. Quand un paquet part vers `10.96.144.175:80`, ces règles le détournent vers l'IP et le port d'un Pod réel, par exemple `10.244.1.4:8080`.

Comment choisit-il le Pod ? La même référence dit que le mode par défaut sous Linux, pour Kubernetes 1.37, est `iptables`, et que dans ce mode les règles, « par défaut, choisissent un Pod de *backend* au hasard ». Au hasard, pas à tour de rôle. Sur trente tirages, une répartition de 14, 13 et 6 est parfaitement possible. Avec beaucoup plus de requêtes, chaque réplique se rapprocherait d'un tiers. Et le `Session Affinity: None` de `describe` est ce qui permet ce hasard : la référence explique que, si tu veux qu'un même client aille toujours vers le même Pod, tu peux mettre `sessionAffinity: ClientIP`, et que la valeur par défaut est `None`. Le `revisor` ne conserve rien entre les requêtes, il n'en a donc pas besoin.

Cela a une conséquence qu'il vaut mieux connaître dès maintenant : le Service répartit des **connexions**, pas des requêtes. Chaque `curl` de la boucle ouvre une nouvelle connexion, et c'est pourquoi chacun tombe là où le sort le désigne. Un client qui réutilise une seule connexion pour de nombreuses requêtes parle toujours au même Pod tant que cette connexion vit.

### 3.9 `port-forward` : un tunnel depuis ta machine

Tout ce qui précède s'est passé **à l'intérieur** du cluster. Et toi, depuis ton terminal ? L'IP `10.96.144.175` ne sert à rien en dehors du cluster (la section de l'habitude de sécurité le vérifie). Pour tester depuis ta machine sans rien publier, il existe `kubectl port-forward` :

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &
Forwarding from 127.0.0.1:18080 -> 8080

$ curl -s http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s 'http://127.0.0.1:18080/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK            0s  200
```

Cela se lit ainsi : il écoute sur le port `18080` de ta machine, uniquement sur l'adresse `127.0.0.1`, et réexpédie ce qui arrive vers le port `80` du Service `revisor`. Le `&` final le laisse tourner en arrière-plan, pour que tu puisses utiliser le même terminal. Tant qu'il tourne, chaque fois que tu lui fais une requête, `kubectl` imprimera `Handling connection for 18080` dans ce terminal : c'est normal. Tu l'arrêtes avec `kill %1` ou en le ramenant au premier plan avec `fg` puis `Ctrl+C`. Si tu préfères le laisser dans un terminal à part, souviens-toi de 3.1 : dans ce nouveau terminal, d'abord le même `export KUBECONFIG=…` et `kubectl config current-context`, qui doit afficher `kind-curso-k8s-l3`.

Lis bien sa première ligne : `Forwarding from 127.0.0.1:18080 -> 8080`. Elle ne dit pas `-> 80`. `kubectl` a traduit le `80` du Service en son `targetPort` et celui-ci en le `8080` du Pod, et il a ouvert le tunnel **directement vers un Pod**. La [référence de `kubectl port-forward`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/) le dit dès sa première phrase : « redirige un ou plusieurs ports locaux vers un Pod ». Et elle ajoute : quand tu lui donnes une ressource comme un Deployment ou un Service, `kubectl` choisit un Pod ; « s'il y a plusieurs Pods qui correspondent, l'un est choisi automatiquement. La session de redirection se termine quand le Pod choisi se termine, et il faut relancer la commande ». Autrement dit : `port-forward service/revisor` ne répartit **pas** comme le Service. Il n'utilise le Service que pour trouver un Pod. L'Exercice 3 te montre ce qui se passe quand ce Pod s'en va.

Et `--address 127.0.0.1` ? La référence dit que la valeur par défaut de `--address` est `localhost`, avec laquelle `kubectl` essaie d'écouter sur `127.0.0.1` et sur `::1` (l'adresse de ta propre machine en IPv6). Le cours écrit `127.0.0.1` : une seule adresse, en clair, pour la même raison qu'il écrit `type: ClusterIP`. La décision de ne pas ouvrir le tunnel au réseau reste écrite, et personne n'a besoin de connaître la valeur par défaut. La même référence contient, parmi ses exemples, `--address 0.0.0.0`, qui écoute « sur toutes les adresses ». Cela ferait de ton portable un point d'entrée vers ce Pod pour n'importe qui sur ton réseau, sans mot de passe et avec tes identifiants du cluster derrière. On vérifie ce qu'a ouvert le tunnel :

```text
$ lsof -nP -iTCP:18080 -sTCP:LISTEN | awk '{print $1, $8, $9, $10}'
COMMAND NODE NAME 
kubectl TCP 127.0.0.1:18080 (LISTEN)
```

Un seul processus, `kubectl`, qui écoute sur `127.0.0.1:18080` et nulle part ailleurs. (`lsof` liste qui a un port ouvert ; `awk` ne garde que quatre colonnes pour que cela tienne. Sous Linux Mint, cela fonctionne de la même façon ; tu peux aussi utiliser `ss -ltnp | grep 18080`.)

Un `port-forward` sert à tester, pas à servir. Il vit tant que vivent ta commande et ta session, dépend de tes identifiants du cluster et se rompt quand le Pod qu'il a choisi s'en va. Publier le `revisor` pour de vrai, par un point d'entrée nommé, c'est la Leçon 6.

## L'erreur que tu vas voir

L'erreur de cette leçon est l'une des plus courantes avec les Services, et le guide de débogage lui-même la mentionne comme telle : un Service dont le sélecteur ne sélectionne personne. On la provoque avec `fig03_01.selector-malo.yaml`, un **programme** qui échoue exprès : le même Service du `revisor`, avec une lettre en moins.

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

Avant de l'appliquer, `kubectl config current-context` doit afficher `kind-curso-k8s-l3`.

```text
$ kubectl apply -f fig03_01.selector-malo.yaml
service/revisor configured
```

`configured` : le `kube-apiserver` a accepté le changement sans se plaindre, et il a raison. Un sélecteur `app: revisr` est parfaitement valide ; simplement, il ne correspond à rien. Kubernetes ne peut pas savoir que tu voulais écrire `revisor`.

**Laisse un moment au cluster.** Avant de tester, vérifie que l'EndpointSlice est déjà vide : `kubectl get endpointslices -l kubernetes.io/service-name=revisor` doit afficher `<unset>` dans la colonne `ENDPOINTS`. Si tu testes dans la même seconde que l'`apply`, `kube-proxy` n'a pas encore eu connaissance du changement, le `curl` répond comme si de rien n'était et tu vas croire que l'erreur « n'est pas sortie ». Le script fait précisément cela : il attend que la liste se vide et ne teste qu'ensuite. Après, on lit dans l'ordre, comme dans la Leçon 2.

**Premièrement, le symptôme.** Depuis le Pod de débogage, en demandant à `curl` de dire combien de temps il a pris :

```text
$ kubectl exec depurar -- curl -s -m 3 -o /dev/null -w 'tardó %{time_total} s\n' http://revisor/salud
tardó 0.001120 s
command terminated with exit code 7
[código de salida: 7]
```

(`-o /dev/null` jette la réponse, qui n'existe pas ici, et `-w` demande à `curl` d'écrire à la fin le temps total de la requête.) `-m 3` lui fixe une limite de 3 secondes, pour qu'il n'attende pas indéfiniment ; ce n'était pas nécessaire : il a mis une milliseconde. Le code 7 est, d'après la [liste des erreurs de curl](https://curl.se/libcurl/c/libcurl-errors.html), « impossible de se connecter à l'*hôte* » (*Failed to connect() to host or proxy*). Ce n'est pas le 6, « impossible de résoudre l'*hôte* » : le nom a bien été résolu. Et ce n'est pas le 28, « délai dépassé » : la connexion n'est pas restée à attendre, quelqu'un l'a refusée immédiatement. Cette distinction te dit déjà où regarder.

**Deuxièmement, le DNS.** Si le nom a été résolu, le DNS n'est pas le problème. On le vérifie :

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

Le nom existe toujours et donne la même IP. Le Service est là. Ce qu'il n'y a pas, c'est personne derrière.

**Troisièmement, les *endpoints*.** C'est l'étape décisive :

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS     ENDPOINTS   AGE
revisor-6jh2f   IPv4          <unset>   <unset>     51s

$ kubectl describe service revisor | grep -E '^(Selector|Endpoints):'
Selector:                 app=revisr
Endpoints:                
```

`ENDPOINTS <unset>` : l'EndpointSlice existe toujours, mais vide, sans adresses et sans ports. `describe` le confirme avec un `Endpoints:` en blanc et, une ligne plus haut, montre la cause : `Selector: app=revisr`. Le guide de débogage des Services le dit presque avec ces mots : si la liste des *endpoints* est vide, « vérifie que le champ `spec.selector` de ton Service sélectionne bien les valeurs de `metadata.labels` de tes Pods. Une erreur courante est d'avoir une faute de frappe ».

**Quatrièmement, le sélecteur contre les étiquettes.** On le vérifie avec le même sélecteur, qui est précisément l'outil de la Leçon 2 :

```text
$ kubectl get pods -l app=revisr
No resources found in default namespace.

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-mjbff   1/1     Running   0          48s
revisor-697fb84f97-nq74v   1/1     Running   0          53s
revisor-697fb84f97-z79jh   1/1     Running   0          52s
```

Zéro Pod avec `app=revisr`, trois avec `app=revisor`, les trois `Running`. Les Pods sont parfaits. Le Service en cherche d'autres.

**Pourquoi le code 7 et non un délai dépassé.** Avec la liste vide, `kube-proxy` n'a nulle part où envoyer la connexion. Ce qui est mesuré, c'est le code, 7, et le temps, une milliseconde : la connexion n'a pas attendu jusqu'à la limite de 3 secondes, elle a été refusée dès qu'elle est partie. (En mode `iptables`, `kube-proxy` met une règle de rejet pour les Services sans *endpoints*. C'est le comportement observé dans cette exécution, pas quelque chose que la documentation promette.) C'est le même signal que dans l'Exercice 1, pour une cause différente : là, le Service a bien quelqu'un à qui envoyer du trafic, mais vers le mauvais port. Ce qui sépare un cas de l'autre, c'est la colonne `ENDPOINTS`.

**La correction**, c'est la cause, pas le Pod : appliquer de nouveau le bon fichier.

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   53s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

Les trois adresses sont revenues dans le même EndpointSlice (`revisor-6jh2f`, dont l'âge a continué de courir : il n'a pas été supprimé ni un autre créé), et le `revisor` répond. Remarque l'ordre de la correction : le script a attendu de voir les trois adresses dans l'EndpointSlice avant de tester avec `curl`. C'est le même avertissement que celui du début, à l'envers : entre le moment où tu appliques le Service corrigé et celui où chaque `kube-proxy` met à jour ses règles, il s'écoule un instant, et un test fait précisément à ce moment peut encore échouer même si la réparation est déjà faite. D'abord on vérifie que la liste est pleine ; ensuite on teste.

**L'ordre, pour n'importe quel Service qui ne répond pas :**

1. Quel code donne `curl` ? Le 6 est le nom, le 7 est un refus et le 28 est le silence.
2. Le nom complet se résout-il ?
3. Son EndpointSlice a-t-elle des adresses ?
4. Si non, son `Selector` correspond-il aux étiquettes des Pods (`get pods -l …`) ?
5. Si oui, le port de la colonne `PORTS` est-il celui où le programme écoute ?

## L'habitude de sécurité de la leçon : rien n'est publié sans raison

Le tableau des habitudes du cours attribue à cette leçon trois choses : `ClusterIP` par défaut ; rien n'est publié sans raison ; `port-forward` uniquement vers `127.0.0.1`. On vérifie les trois avec le cluster sous les yeux.

**Un `ClusterIP` ne se voit pas depuis ta machine.** Depuis ton terminal, en dehors du cluster, la même IP que le Pod de débogage a utilisée sans problème :

```text
$ curl -s -m 3 http://10.96.144.175/salud
[código de salida: 28]
```

Code 28 : « délai dépassé ». Ta machine n'a pas de route propre vers `10.96.0.0/16` : le paquet sort par ta route par défaut, vers ton modem ou le réseau de ton bureau, qui ne savent rien du cluster, et personne ne répond. (Si ton réseau utilise des adresses `10.96.x.x`, tu pourrais obtenir une autre réponse, d'une machine qui n'a rien à voir avec le cluster ; raison de plus pour dire que cette IP n'est pas à toi en dehors de lui.) La `10.96.144.175` n'a de sens que dans les règles que `kube-proxy` écrit **à l'intérieur** des nœuds.

**Les nœuds ne publient rien du `revisor`.** Chaque nœud de kind est un conteneur Docker, et Docker dit quels ports chacun publie :

```text
$ docker port curso-k8s-l3-control-plane
6443/tcp -> 127.0.0.1:59190

$ docker port curso-k8s-l3-worker

$ docker port curso-k8s-l3-worker2
```

Le nœud de contrôle publie un seul port, le `6443` du `kube-apiserver`, et uniquement vers `127.0.0.1` (le numéro de ton côté, c'est kind qui le choisit au hasard ; sur ta machine, il sera différent). C'est le point d'entrée par lequel parle ton `kubectl`, et la Leçon 1 l'a vu. Les deux nœuds de travail, où tourne le `revisor`, ne publient **rien** : leurs lignes sortent vides. Il n'y a aucun chemin depuis ton réseau vers le port 8080 du `revisor`. Il doit en être ainsi jusqu'à la Leçon 6, qui ouvre un point d'entrée nommé et dit ce qui le traverse.

**Le tunnel n'écoute que sur ta machine.** Tu l'as déjà vu en 3.9 : `kubectl` qui écoute sur `127.0.0.1:18080` et nulle part ailleurs.

Pourquoi c'est important : chaque chemin ouvert vers un service est un chemin que quelqu'un peut emprunter. Dans un cluster réel, le réflexe du « je le passe en `NodePort` pour tester » ou du « je mets `--address 0.0.0.0` pour que mon collègue le voie » laisse ouvert ce que personne ne se souvient de fermer. La règle du cours est l'inverse : tout naît fermé, chaque ouverture est une décision écrite dans un manifeste et a sa leçon.

**Ce contre quoi il protège et ce contre quoi il ne protège pas.** Un `ClusterIP` empêche que le `revisor` soit atteint depuis l'**extérieur** du cluster. Il n'empêche rien à l'**intérieur** : n'importe quel Pod de n'importe quel espace de noms peut lui parler, comme l'a fait `depurar`, qui n'a rien à voir avec le `revisor`. Il ne chiffre pas non plus le trafic entre Pods : il circule en HTTP en clair sur le réseau de Pods. Fermer qui parle à qui, c'est le travail des `NetworkPolicy` de la Leçon 7. Le chiffrement est discuté dans la Leçon 6.

## Ce qui se fait de travers

**Conserver l'IP d'un Pod dans la configuration.** C'est la scène du mardi. Ça fonctionne jusqu'à ce que le Pod soit recréé. Toujours le nom du Service.

**Conserver l'IP du Service au lieu de son nom.** Elle est stable tant que le Service existe, mais si tu le supprimes et le recrées, il en reçoit une autre. Le nom survit à cela ; l'IP, non.

**Écrire `targetPort` sous forme de nombre quand le conteneur a un nom.** Ça fonctionne aujourd'hui et oblige à maintenir le même nombre dans deux fichiers. Le jour où l'un change, le Service envoie du trafic vers un port où personne n'écoute (Exercice 1).

**Passer à `NodePort` ou à `LoadBalancer` « pour tester ».** Pour tester, il y a `port-forward`, qui n'ouvre rien au réseau. Publier est une décision de la Leçon 6, pas un raccourci.

**Ouvrir `port-forward` avec `--address 0.0.0.0`.** Cela expose le port de ce Pod à quiconque atteint ta machine, sans mot de passe, en utilisant tes identifiants du cluster, tant que la commande vit.

**Utiliser `port-forward` comme s'il s'agissait d'un Service.** Il parle à **un** Pod, ne répartit pas et tombe quand ce Pod s'en va (Exercice 3). Il sert à regarder, pas à servir.

**Ouvrir un autre terminal et oublier le `export KUBECONFIG`.** Dans le nouveau terminal, `kubectl` parle au cluster que dit ton `~/.kube/config`, qui peut être n'importe quel autre. D'abord le `export`, ensuite `kubectl config current-context`, et seulement alors la commande.

**S'alarmer des `NXDOMAIN` de `nslookup`.** Avec le nom court, ce sont les extensions de `search` qui n'existent pas. Cherche la ligne `Name:`, ou demande le nom complet.

**Donner à un Pod isolé les étiquettes du sélecteur d'un Service.** Le Deployment ne l'adopte pas, mais le Service, lui, l'utilise et lui envoie du trafic (Exercice 2).

**Tester juste après avoir modifié le Service et en tirer des conclusions.** Aussi bien en le cassant qu'en le corrigeant : d'abord la colonne `ENDPOINTS` ; ensuite, `curl`.

**Retirer le `securityContext` du Pod de débogage « parce qu'il est temporaire ».** Ce qui est temporaire est oublié, et un Pod `root` oublié est une porte ouverte. Celui de ce cours respecte déjà le niveau `restricted`.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre et à partir de l'état dans lequel il est resté après la correction de l'erreur. Avant chaque exercice, `kubectl config current-context` doit afficher `kind-curso-k8s-l3` ; s'il affiche autre chose, ne continue pas. `correr.sh` les exécute de la même façon, et sa sortie se trouve dans `correr.salida.txt`. **Avant** d'exécuter chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes propres mots.

### Exercice 1 — Un `targetPort` où personne n'écoute

`fig03_02.puerto-malo.yaml` est le même Service du `revisor` avec le sélecteur correct et une seule différence : `targetPort: 8081`, un nombre, au lieu de `http`.

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

Avant de l'appliquer, prédis : combien d'adresses l'EndpointSlice aura-t-elle ? Que dira sa colonne `PORTS` ? Quel code donnera `curl -s -m 3 http://revisor/salud` depuis `depurar` ? Ensuite, applique-le, attends quelques secondes que la colonne `PORTS` change (le script attend cinq secondes), vérifie, et explique en quoi cet échec ressemble à celui de « L'erreur que tu vas voir » et en quoi il s'en distingue. À la fin, applique de nouveau `revisor-service.yaml`.

### Exercice 2 — Le Pod qui se glisse dans le Service

`fig03_03.colado.yaml` est le `revisor-extra` de l'Exercice 2 de la Leçon 2 : un Pod isolé, identique aux répliques, **avec** l'étiquette `app: revisor` et avec son port nommé `http`. Dans la Leçon 2, tu as vu que le Deployment ne l'adopte pas. Maintenant, il y a un Service qui choisit par `app: revisor`.

Prédis : combien de répliques le Deployment annonce-t-il ? Combien d'adresses l'EndpointSlice du `revisor` contient-elle ? Si tu envoies 40 requêtes à `http://revisor/salud`, combien en reçoit `revisor-extra`, à peu près ? Applique-le, vérifie avec `kubectl get deployment revisor`, avec le `jsonpath` de 3.4 (adresse et `targetRef.name`) et avec `kubectl logs revisor-extra | grep -c 'GET /salud'` après la boucle de 3.8 avec 40 requêtes. Ensuite, explique ce qui arriverait à ce Pod le jour où tu changes l'image du Deployment. À la fin, vérifie le contexte et supprime-le : `kubectl delete pod revisor-extra`.

### Exercice 3 — Le tunnel et le *rollout*

Ouvre de nouveau le `port-forward` de 3.9 et vérifie que `curl -s -m 3 http://127.0.0.1:18080/salud` répond. Prédis : si tu exécutes maintenant `kubectl rollout restart deployment/revisor` et que tu attends qu'il se termine, le même `curl` répond-il encore ? Fais-le, et lis ce que le `port-forward` a écrit dans son terminal. Explique ce qui s'est passé à l'aide de la phrase de la référence de `kubectl port-forward` que cite 3.9.

### Exercice 4 — Les quatre `NXDOMAIN`

Une collègue exécute `kubectl exec depurar -- nslookup revisor`, voit quatre lignes `server can't find … NXDOMAIN` et le code de sortie 1, et conclut que « le DNS du cluster est cassé ». En cinq phrases au maximum, réponds-lui : d'où viennent ces noms, pourquoi chacun apparaît deux fois, pourquoi le code est 1, comment on reconnaît dans la même sortie que le nom a bien été résolu, et quelle commande tu lui donnerais pour le vérifier sans bruit.

## Solutions

### Solution 1

Mesuré dans `correr.salida.txt` :

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

**Trois adresses, port `8081`, et `curl` avec le code 7.** Le sélecteur est correct, donc l'EndpointSlice contient les trois répliques. Mais sa colonne `PORTS` affiche `8081` : avec un nombre, le cluster ne cherche rien dans le Pod, il prend le nombre tel quel. La connexion arrive sur l'IP correcte d'un Pod réel, sur un port où le `revisor` n'écoute pas, et le Pod la refuse : code 7, « impossible de se connecter ».

Il ressemble à l'erreur de la leçon par le symptôme : le même code 7. Il s'en distingue par la colonne `ENDPOINTS` : là-bas, elle était en `<unset>` (il n'y a personne), ici elle est pleine (il y a quelqu'un, mais par le mauvais port). C'est pourquoi l'ordre de diagnostic regarde d'abord les adresses et ensuite le port. Le guide de débogage des Services pose la question telle quelle : « le `targetPort` est-il correct pour tes Pods ? ». Et c'est l'argument en faveur de `targetPort: http` : avec le nom, cette erreur ne peut pas s'écrire sans modifier aussi le Deployment.

En appliquant de nouveau le bon :

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   64s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

`PORTS 8080` : le nom `http` a de nouveau été résolu vers le port des Pods.

### Solution 2

Mesuré dans `correr.salida.txt` :

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

**Le Deployment dit `3/3`, le Service a quatre adresses et `revisor-extra` a reçu 12 requêtes sur 40.** Le Deployment ne le compte pas, pour ce que tu as vu dans la Leçon 2 : son ReplicaSet cherche aussi `pod-template-hash`. Le Service, si, parce qu'il ne cherche que `app: revisor`, et `revisor-extra` la porte. Pour le Service, c'est une réplique de plus : il apparaît dans son EndpointSlice et reçoit sa part du trafic au hasard. Avec quatre *endpoints*, on s'attend à environ 10 sur 40, et 12 en est proche. Dans ton exécution, ce sera un autre nombre, et peu importe lequel : ce qui compte, c'est que ce n'est pas zéro.

Le jour où tu changes l'image du Deployment, le *rollout* remplace les trois répliques et `revisor-extra` garde l'ancienne image, parce qu'il n'appartient à personne. Le Service continuerait de lui envoyer sa part du trafic, et une partie de tes utilisateurs verraient la version précédente sans qu'aucun `kubectl get deployment` ne t'en avertisse. C'est l'avertissement de la Leçon 2 sur les sélecteurs qui se chevauchent, maintenant avec du vrai trafic.

### Solution 3

Mesuré dans `correr.salida.txt` :

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

(La sortie de `rollout status` est abrégée : dans `correr.salida.txt`, chaque ligne se répète plusieurs fois, comme dans la Leçon 2.) Et ce qu'a écrit le `port-forward` :

```text
Forwarding from 127.0.0.1:18080 -> 8080
Handling connection for 18080
Handling connection for 18080
E1021 07:23:02.902759   47411 portforward.go:549] "An error occurred forwarding" err="error forwarding port 8080 to pod 0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb, uid : network namespace for sandbox \"0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb\" is closed" localPort=18080 remotePort=8080
error: lost connection to pod
```

**Le `curl` après le *rollout* échoue avec le 52**, qui dans la liste des erreurs de curl signifie « le serveur n'a rien renvoyé ». Le tunnel n'allait pas vers le Service : il allait vers **un** Pod, choisi à l'ouverture. `rollout restart` a remplacé les trois Pods, y compris celui-là. La connexion suivante est arrivée au tunnel, le tunnel a tenté de la réexpédier à un Pod dont le réseau était déjà fermé (`network namespace for sandbox … is closed`) et `kubectl` a abandonné : `error: lost connection to pod`. C'est exactement ce que dit la référence : « la session de redirection se termine quand le Pod choisi se termine, et il faut relancer la commande ». Le Service, pendant ce temps, a conservé son adresse et son sélecteur pour les clients de l'intérieur du cluster : ce qui est tombé, c'est ton tunnel. Cette leçon n'a pas mesuré si un client interne perd des requêtes pendant le *rollout* : le `revisor` n'a pas encore de readiness probes ni d'arrêt ordonné, et cela arrive dans la Leçon 5 ; la Leçon 9 le mesure avec une vraie charge. C'est pourquoi `port-forward` sert à regarder, et c'est pourquoi il ne sert pas à publier quoi que ce soit.

### Solution 4

Une réponse possible : « Ces noms sont les autres extensions de la liste `search` de `/etc/resolv.conf` : à `revisor` on ajoute chaque domaine de la liste, et `revisor.svc.cluster.local` et `revisor.cluster.local` n'existent vraiment pas. Chacun apparaît deux fois parce que le `nslookup` de BusyBox demande l'adresse IPv4 et l'adresse IPv6 de chaque nom. Il affiche chaque échec et se termine avec le code 1 s'il y en a eu un, même s'il a trouvé la réponse. La preuve que le nom a bien été résolu est dans la même sortie : la ligne `Name: revisor.default.svc.cluster.local` avec son `Address`. Pour le vérifier sans bruit : `kubectl exec depurar -- nslookup revisor.default.svc.cluster.local`, qui dans cette image sort proprement. »

## Supprimer le cluster

Quand tu as terminé les exercices, supprime le cluster de la leçon. Ne laisse rien de vivant sur la machine. Si tu as laissé un `port-forward` ouvert dans un autre terminal, arrête-le d'abord avec `Ctrl+C`.

```text
$ kind delete cluster --name curso-k8s-l3
Deleting cluster "curso-k8s-l3" ...
Deleted nodes: ["curso-k8s-l3-control-plane" "curso-k8s-l3-worker" "curso-k8s-l3-worker2"]

$ kind get clusters | grep -c curso-k8s-l3
0
```

Le `--name` est obligatoire ici aussi : sans lui, kind supprimerait le cluster appelé `kind`, qui peut appartenir à une autre personne ou à un autre projet. Ensuite, supprime le dossier temporaire du `kubeconfig` (celui qu'a créé `mktemp`, avec le préfixe `/tmp/curso-k8s-l3.` ; c'est là que se trouve l'identifiant d'administrateur du cluster) ou ferme ce terminal. Le cluster de la leçon suivante se crée de zéro, comme celui-ci.

## Comment savoir que j'ai réussi

- [ ] Tu expliques, avec la sortie de 3.1 sous les yeux, pourquoi l'IP d'un Pod ne sert pas d'adresse, et ce qui change quand le client utilise le nom d'un Service.
- [ ] Tu écris de mémoire un Service `ClusterIP` avec `selector` et `ports`, et dans celui du `revisor`, tu dis lequel est `port`, lequel est `targetPort`, lequel est `containerPort` et quelle valeur a chacun.
- [ ] Tu trouves l'EndpointSlice de n'importe quel Service avec `kubectl get endpointslices -l kubernetes.io/service-name=<nom>` et tu dis, d'après ses adresses, quels Pods reçoivent le trafic.
- [ ] Tu expliques chaque ligne du `/etc/resolv.conf` d'un Pod et pourquoi `revisor`, `revisor.default` et `revisor.default.svc.cluster.local` mènent au même endroit.
- [ ] Face à un `curl` avec le code 7 contre un Service, tu vérifies dans l'ordre le nom, la colonne `ENDPOINTS` et le port, et tu distingues un sélecteur mal écrit d'un `targetPort` mal écrit.
- [ ] Tu ouvres un `port-forward` qui n'écoute que sur `127.0.0.1`, tu le vérifies avec `lsof` (ou `ss` sous Linux Mint) et tu dis pourquoi il tombe avec un *rollout*.
- [ ] Tu exécutes `programas/03-services-dns/correr.sh > /tmp/mi-corrida-l3.txt 2>&1` et tu compares `/tmp/mi-corrida-l3.txt` avec `programas/03-services-dns/correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) sur ce qui ne change pas d'une exécution à l'autre : trois nœuds `Ready` en `v1.37.0` ; six lignes `not yet present on node … loading...` ; le Service `revisor` en `ClusterIP` sur `80/TCP` avec `EXTERNAL-IP <none>` ; `TargetPort: http/TCP` et trois `Endpoints` sur le `8080` ; l'EndpointSlice avec `PORTS 8080`, trois adresses et le propriétaire `Service/revisor` ; l'avertissement `v1 Endpoints is deprecated in v1.33+` ; `uid=100(curl_user)` ; `{"estado":"vivo","version":"1.6.0"}` par nom et par IP ; le `resolv.conf` avec ses trois lignes ; `kube-dns` en `10.96.0.10` ; `lookup prueba … no such host` avant de créer le service de test, puis `OK … 200`, `FALLA … codigo 503` et `FALLA … se acabo el tiempo de espera` ; les trois répliques avec au moins une requête en 3.8 ; `Forwarding from 127.0.0.1:18080 -> 8080` et `kubectl TCP 127.0.0.1:18080 (LISTEN)` ; le code 28 depuis ta machine ; les deux nœuds de travail sans ports publiés ; le code 7 avec le mauvais sélecteur, en millisecondes, et `<unset>` dans son EndpointSlice ; `PORTS 8081` et le code 7 dans l'Exercice 1 ; quatre adresses avec `revisor-extra` dans l'Exercice 2 ; le code 52 et `lost connection to pod` dans l'Exercice 3 ; `sin diferencias con los archivos` ; et à la fin `0` cluster `curso-k8s-l3` et la ligne `la corrida completa tardó … s`. Les IP, les suffixes des noms, les âges, le port que publie le nœud de contrôle, le nœud sur lequel atterrit chaque Pod, l'ordre des lignes de `kind load` et de celles de `nslookup`, la répartition exacte des requêtes, les temps et le nombre de répétitions de chaque ligne de `rollout status` changent à chaque exécution : on les observe, on ne les compare pas. Si tu as utilisé un autre port avec `PUERTO_LOCAL`, tu verras ce nombre à la place du `18080`.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l3`.

## Résumé

Réponds sans regarder la leçon :

1. Pourquoi ne faut-il pas conserver l'IP d'un Pod dans la configuration d'un autre programme ? Qu'est-ce qui a changé dans le Pod de 3.1 en plus de l'IP ?
2. Que fait un Service de type `ClusterIP`, d'où est-il joignable et pourquoi est-ce le type par défaut que ce cours écrit malgré tout ?
3. Dans le Service du `revisor`, qu'est-ce que `port`, qu'est-ce que `targetPort` et d'où sort le `8080` ? Pourquoi `targetPort` est-il donné par nom ?
4. Quel objet conserve la liste des Pods d'un Service, qui l'écrit et avec quelle étiquette le trouves-tu ?
5. Qu'est-ce que `kube-dns`, sur quelle IP se trouve-t-il et pourquoi ressemble-t-il tant à ton Service ?
6. Quelles trois lignes contient le `/etc/resolv.conf` d'un Pod et que fait chacune ?
7. Comment `kube-proxy` choisit-il la réplique vers laquelle il envoie une connexion, dans le mode par défaut ?
8. Quels codes de `curl` distinguent « n'a pas résolu le nom », « a refusé la connexion » et « n'a pas répondu à temps » ?
9. À combien de Pods `kubectl port-forward service/revisor` parle-t-il, et que lui arrive-t-il avec un *rollout* ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Service »](https://kubernetes.io/docs/concepts/services-networking/service/) : ce qu'est un Service ; le type `ClusterIP` comme valeur par défaut et joignable uniquement depuis l'intérieur du cluster ; `targetPort` égal à `port` par défaut ; les ports nommés ; la *cluster IP* ; l'API `Endpoints`, dépréciée depuis la v1.33, et pourquoi.
- [Kubernetes, « EndpointSlices »](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) : ce que conserve un EndpointSlice ; l'étiquette `kubernetes.io/service-name` et la référence à son propriétaire ; la limite de 100 *endpoints* par EndpointSlice ; les conditions `serving`, `terminating` et `ready`.
- [Kubernetes, « DNS for Services and Pods »](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) : la forme du nom d'un Service ; les requêtes sans espace de noms limitées à celui du Pod ; le `/etc/resolv.conf` avec `search` et `ndots:5`.
- [Kubernetes, « Debug Services »](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/) : la boucle de contrôle qui remplit les EndpointSlices ; le sélecteur avec faute de frappe comme erreur courante ; les questions sur `targetPort` ; et pourquoi `ndots` vaut 5.
- [Kubernetes, « Virtual IPs and Service Proxies »](https://kubernetes.io/docs/reference/networking/virtual-ips/) : `kube-proxy` comme responsable des IP virtuelles ; `iptables` comme mode par défaut dans Kubernetes 1.37 et le choix du Pod au hasard ; `sessionAffinity` et sa valeur par défaut `None`.
- [Kubernetes, « kubectl port-forward »](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/) : il redirige vers un Pod ; le choix automatique d'un Pod et la fin de la session quand ce Pod se termine ; `--address` et sa valeur par défaut `localhost` ; l'exemple avec `0.0.0.0`.
- [Kubernetes, « Pods »](https://kubernetes.io/docs/concepts/workloads/pods/) : les Pods comme entités éphémères et jetables.
- [kind, « Configuration »](https://kind.sigs.k8s.io/docs/user/configuration/) : les sous-réseaux par défaut des Pods (`10.244.0.0/16`) et des Services (`10.96.0.0/16`), et `kindnetd` comme réseau par défaut.
- [kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster) : `kind load docker-image` avec `--name`.
- [curl, « libcurl error codes »](https://curl.se/libcurl/c/libcurl-errors.html) : la signification des codes de sortie 6, 7, 28 et 52.

---

**Suivante :** [Leçon 4 — Configuration et secrets](04-configuracion-secretos.md)
