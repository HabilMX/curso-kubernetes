# Leçon 9 — Mettre à l'échelle et mettre à jour en mesurant chaque coupure

Lundi, 8 h 57 du matin. À 9 h 00, l'équipe d'exploitation tient sa réunion hebdomadaire et quarante personnes vont ouvrir, presque en même temps, le rapport du `revisor`. Lundi dernier, il s'est passé quelque chose de semblable. À 9 h 01, le tableau de bord est devenu lent ; quelqu'un a augmenté les répliques manuellement, de trois à huit, pour « tenir le coup » ; et il a oublié de les redescendre. À 9 h 04, une autre personne a appliqué un correctif urgent, et pendant quelques secondes plusieurs utilisateurs ont vu une erreur à l'écran. Personne ne sait combien. Aujourd'hui, le directeur de l'exploitation pose trois questions, et la réunion commence dans trois minutes : de combien de répliques le service a-t-il vraiment besoin, et qui décide quand il y en a trop ? combien de requêtes sont perdues pendant une mise à jour ? et que se passe-t-il si l'un des serveurs du cluster tombe en panne ? Il y a une semaine, ta réponse aux trois était la même : « ça devrait aller ».

Cette phrase est le problème. Dans Kubernetes, « ça devrait aller » peut se transformer en un nombre, et cette leçon est l'atelier où l'on fait cette transformation. Ce n'est pas une histoire inventée pour faire peur. En 2019, un ingénieur nommé Phil Pearl a raconté sur son blog que, en déplaçant une API vers un cluster Kubernetes de Google derrière un Ingress, ses tests recevaient de temps en temps des erreurs `502`. En cherchant la cause, il a trouvé quelque chose que presque personne ne disait à l'époque : quand un Pod s'arrête, l'avis d'arrêt et le retrait de ce Pod de la liste des destinations du réseau se produisent **en même temps**, et non l'un après l'autre ; l'étape qui sort le Pod de la liste n'attend pas l'étape qui l'arrête. Ce qui varie, c'est le temps que met la nouvelle à parvenir à chaque répartiteur de charge : selon Pearl, beaucoup pour un Ingress et peu pour un Service. Avec cette situation de compétition (race condition), une requête peut arriver sur un Pod qui est déjà en train de se fermer ([Phil Pearl, « Kubernetes' dirty endpoint secret and Ingress »](https://philpearl.github.io/post/k8s_ingress/), 26 juillet 2019). Ce que tu apprends aujourd'hui, c'est comment mesurer cette situation de compétition sur ton propre cluster, comment la refermer avec quelques lignes, et comment ne pas accorder à une mesure plus de crédit qu'elle n'en mérite.

Cette leçon comporte trois parties. La première apprend au cluster à **se mettre à l'échelle tout seul** : un compteur de consommation (`metrics-server`), un autoscaler qui utilise une formule que tu pourras calculer manuellement, et une règle de répartition pour que les répliques ne s'entassent pas sur un seul nœud. La deuxième apprend à **mettre à jour et évincer sans surprises** : une mise à jour mesurée avec une interrogation périodique (polling) écrite par nous, avec et sans la pause qui referme la situation de compétition, l'historique pour revenir en arrière, et un budget d'interruptions face manuellementtenance d'un nœud. La troisième **casse un serveur exprès** et mesure combien dure la coupure. Chaque chiffre que tu verras est sorti de l'exécution de la procédure, et chaque chiffre vient avec ce qui le limite.

**Durée :** 2 × 45 min de lecture et de pratique ; l'exécution complète du script prend bien plus longtemps (c'est dit dans « À propos des exécutions »), parce que les attentes font partie de ce qu'on enseigne

**Ce que tu construis :** le `revisor` qui augmente et réduit ses répliques avec la charge, réparti entre les deux nœuds de travail, qui se met à jour avec une interrogation périodique comptant chaque requête perdue et qui survit à un nœud arrêté avec une perte mesurée et expliquée

**Ce que tu apprends :** pourquoi `metrics-server` tel quel ne fonctionne pas dans kind et ce que change le drapeau qui le corrige ; la formule du `HorizontalPodAutoscaler`, sa tolérance de 10 % et la fenêtre qui retarde la réduction ; pourquoi un Deployment géré par un autoscaler ne porte pas `replicas` ; la répartition entre nœuds avec `topologySpreadConstraints` et pourquoi le nœud de contrôle exige `nodeTaintsPolicy: Honor` ; `RollingUpdate` avec `maxSurge` et `maxUnavailable` ; la situation de compétition entre l'arrêt et les destinations du Service, et le `preStop` qui la referme ; `rollout history` et `rollout undo`, et pourquoi `rollout status` peut se terminer alors que les anciens Pods répondent encore ; le `PodDisruptionBudget` et un `drain` qui se bloque exprès ; et la fenêtre d'un nœud en panne, avec ce qui la raccourcit et ce qui ne la raccourcit pas

**D'où tu viens.** De la [Leçon 8](08-datos-y-tareas.md) : le `revisor` vit dans son propre espace de noms, `revisor`, avec le réseau fermé de la [Leçon 7](07-aislar-permisos-red.md), un volume pour ses rapports et une tâche planifiée. De la [Leçon 5](05-salud-recursos-apagado.md), tu apportes ce qui devient aujourd'hui un calcul : les `requests` de CPU (`50m`), qui sont l'étalon avec lequel l'autoscaler mesure le pourcentage, et le délai d'arrêt, qu'on affine aujourd'hui avec une pause avant le signal de terminaison. De la [Leçon 6](06-entrar-al-cluster.md), tu apportes la plateforme : MetalLB et Envoy Gateway déjà installés, avec l'ordre « plateforme, attente, projet » qui se répète aujourd'hui dans un seul script. Et de la [Leçon 3](03-services-dns.md), le Pod `depurar` et l'habitude de regarder `ENDPOINTS` avant d'accuser qui que ce soit.

**Ce que cette leçon ne fait pas.** Elle ne met pas à l'échelle les **nœuds** : dans kind, les trois nœuds sont des conteneurs fixes, et ajouter ou retirer des machines est le travail d'une autre pièce qu'un vrai cluster apporte et que ce laboratoire n'a pas. Elle ne met pas à l'échelle en vertical (donner plus de CPU à chaque réplique) ni avec des métriques personnalisées (requêtes par seconde, taille d'une file). Elle ne fait pas de mises à jour bleu-vert ni canari : la seule stratégie ici est la progressive qu'apporte Kubernetes. Elle ne met pas de chiffrement. Et ce n'est pas un vrai test de charge : la charge de la leçon est un Job de `curl` en boucle, suffisant pour voir l'autoscaler réagir, et rien de plus. La [Leçon 10](10-proyecto-final.md) rassemble tout en deux commandes et liste ce qui manque à ce montage pour être prêt pour la production.

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1, l'image de nœud `kindest/node:v1.37.0` figée par son empreinte (Kubernetes v1.37.0), **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** et **`metrics-server` v0.9.0**, sur le cluster à trois nœuds de la Leçon 1, qu'on appelle ici `curso-k8s-l9`. La machine était un Mac à processeur ARM avec Docker Engine 29.2.1 dans une machine virtuelle Linux (Colima) dotée de 6 CPU et de 16 GiB de mémoire, et **non** Linux Mint, qui est le système de référence du cours. Et elle était **partagée** : pendant que cette leçon tournait, d'autres leçons du cours tournaient sur la même machine avec leurs propres clusters, et la charge du système (la moyenne qu'affiche `uptime`) est passée de moins de 5 à plus de 40 pendant le travail. Cela compte pour lire deux types de chiffres : les **durées** (télécharger les images de MetalLB a pris, lors d'essais précédents, plusieurs minutes par nœud, et `preparar.sh` comporte de longues attentes pour cette raison) et les **comptes de requêtes** de 9.9 et 9.12, qui dépendent de la quantité de CPU reçue par le client de l'interrogation périodique. Chaque section dit quel chiffre dépend de quoi. Ce qui change sur ton Mint : l'architecture (`amd64` au lieu de `arm64`), les IP des Pods, des Services et des nœuds, les suffixes des noms, les âges, le nœud où atterrit chaque réplique et, surtout, les chiffres de requêtes : ce sont les tiens, ils ne se comparent pas à ceux d'ici. Il y a en outre une différence de réseau qu'il faut mentionner. **L'exécution de cette leçon a utilisé un réseau Docker dédié**, `curso-k8s-red-l9`, avec le sous-réseau `172.29.0.0/16`, afin de pouvoir tourner en même temps que d'autres leçons qui installent elles aussi MetalLB sans se marcher dessus ; c'est pourquoi les IP des nœuds apparaissent en `172.29.0.x` et le point d'entrée du Gateway en `172.29.255.200`. Sur ta machine, avec le réseau `kind` normal, les IP sont en `172.18.0.x` et le point d'entrée en `172.18.255.200`, ce que `preparar.sh` fait par défaut. `correr.sh` fait la même chose si tu le lances avec `RED=kind SUBRED=172.18.0.0/16` (ce sont ses valeurs par défaut) et s'arrête avant de rien créer si le réseau n'a pas le sous-réseau attendu. Le parcours complet se trouve dans [`programas/09-escalar-y-actualizar/`](../programas/09-escalar-y-actualizar) : `correr.sh` crée le cluster, y charge les trois images, le met dans l'état de la Leçon 8 avec `preparar.sh`, parcourt la leçon dans l'ordre et le supprime. Sa sortie est `correr.salida.txt`. L'exécution complète a duré 1 809 secondes (30 minutes et 9 secondes) : créer le cluster et attendre qu'il soit prêt, 37 secondes ; `preparar.sh`, 343 ; supprimer le cluster, 2 ; le reste, ce sont les attentes que la leçon apprend à faire (la charge et la réduction de l'autoscaler, les sept interrogations périodiques de mise à jour, le nœud arrêté). L'image qui n'existe pas de 9.10.4 s'exécute à part, avec `fig09_02.imagen-rota.sh` (sa sortie est `fig09_02.imagen-rota.salida.txt`), dans un cluster dédié et minimal qui prend environ quatre minutes. Il faut internet : les manifestes de `metrics-server`, MetalLB et Envoy Gateway sont téléchargés depuis leurs publications, figées à leur version, et leurs images sont téléchargées la première fois.

## À la fin, tu seras capable de

- Expliquer pourquoi `metrics-server` ne démarre pas tel quel dans kind, lire le `x509` de son journal, appliquer le drapeau qui le corrige et dire pourquoi ce drapeau n'est que pour le laboratoire.
- Calculer manuellement combien de répliques demandera un `HorizontalPodAutoscaler` à partir des répliques actuelles, du pourcentage de CPU mesuré et de la cible, en appliquant la tolérance de 10 %, et le vérifier avec la colonne `TARGETS`.
- Écrire un `HorizontalPodAutoscaler` avec plancher, plafond et fenêtre de réduction, et expliquer pourquoi le Deployment qu'il gouverne ne déclare plus `replicas`.
- Répartir les répliques entre les nœuds avec `topologySpreadConstraints`, et expliquer `maxSkew`, `DoNotSchedule`, `nodeTaintsPolicy: Honor` et `matchLabelKeys`.
- Mesurer avec une interrogation périodique combien de requêtes échouent pendant une mise à jour, avec et sans `preStop`, et dire ce que cette mesure prouve et ce qu'elle ne prouve pas.
- Utiliser `rollout history` et `rollout undo`, regarder `deletionTimestamp` avant de conclure qu'un retour en arrière n'a pas fonctionné, et lire une mise à jour avec une image qui n'existe pas (`ErrImagePull`), en vérifiant que le service n'est pas interrompu.
- Provoquer un `drain` bloqué par un `PodDisruptionBudget` trop strict, le lire et le corriger ; arrêter un nœud, mesurer la fenêtre de panne et expliquer ce qui la raccourcit et ce qui ne la raccourcit pas.

## Le pourquoi avant le comment

Jusqu'ici, le nombre de répliques du `revisor`, c'est toi qui le décidais, écrit dans un fichier. C'est une bonne décision pour apprendre, et une mauvaise pour un lundi à 9 h 00. Si la charge triple, personne n'est en train d'écrire dans ce fichier. Et si la charge baisse, trois répliques continuent de consommer du CPU et de la mémoire que d'autres Pods pourraient utiliser. La première question de la leçon est donc : **qui décide combien de répliques il faut, avec quelle information et avec quel frein ?** La réponse a trois éléments. Un compteur, `metrics-server`, qui regarde combien de CPU et de mémoire utilise chaque Pod. Un contrôleur, le `HorizontalPodAutoscaler` (HPA), qui compare ce qui est mesuré à une cible et ajuste le nombre de répliques. Et une règle de répartition, pour que les nouvelles répliques ne tombent pas toutes sur la même machine, car trois répliques sur un seul nœud tombent en panne ensemble avec ce nœud.

La deuxième question est : **que devient le trafic pendant que quelque chose change ?** Beaucoup de choses changent dans un cluster vivant : une nouvelle version, un nœud qui part en maintenance, un nœud qui tombe en panne sans prévenir. Chacune a une réponse différente, et la différence compte. Une mise à jour se *planifie* : Kubernetes peut remplacer les répliques une par une et attendre que la nouvelle soit prête. Une maintenance se *négocie* : tu peux dire au cluster combien de répliques doivent rester debout, et le cluster respecte ce nombre quand il évince. Une panne *surprend* : personne n'a demandé la permission et le cluster met du temps à s'en apercevoir. La leçon utilise les trois cas comme prétexte pour mesurer. Mesure, ne devine pas, parce que chacune des trois réponses est un nombre qui change avec la configuration, et ce nombre est la réponse au directeur.

Et il y a une troisième question, plus inconfortable : **comment mesure-t-on la coupure sans se tromper ?** Une interrogation périodique qui envoie quelques requêtes et ne voit aucun échec ne démontre pas qu'il n'y a pas d'échecs ; elle démontre que *cette fois-là, à ce rythme*, on n'en a pas vu. La leçon le dit chaque fois qu'elle mesure quelque chose, et répète les mesures là où cela coûte peu. C'est l'habitude qui sépare un rapport d'une anecdote.

La leçon compte dix parties de concepts, puis les sections habituelles :

1. **Le cluster et le point de départ** (9.1) : l'état dans lequel se termine la Leçon 8, démarré avec un script.
2. **Mesurer avant de mettre à l'échelle** (9.2) : `metrics-server`, le drapeau et pourquoi.
3. **L'autoscaler et sa formule** (9.3) : `HorizontalPodAutoscaler`, tolérance, fenêtre et pourquoi `replicas` sort du Deployment.
4. **Répartir les répliques** (9.4) : `topologySpreadConstraints`.
5. **Appliquer les changements** (9.5) : ce que montre `kubectl diff` et le désordre de répliques qui s'y cache.
6. **Avec de la charge, l'autoscaler monte** (9.6).
7. **Sans charge, il redescend, après la fenêtre** (9.7).
8. **Qui commande les répliques** (9.8).
9. **Mettre à jour et mesurer la coupure** (9.9), avec l'interrogation périodique, le `preStop` et le retour en arrière (9.10).
10. **Maintenance et panne d'un nœud** (9.11 et 9.12) : `PodDisruptionBudget`, `drain` et un nœud arrêté.

Voici la destination. À la fin de 9.6, avec de la charge, l'autoscaler a déjà changé le nombre de répliques et l'affiche sur une seule ligne :

```text
$ kubectl get hpa revisor -n revisor --no-headers
revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

C'est une ligne de l'exécution (la dernière de l'attente de 9.6) : le HPA `revisor`, qui gouverne le Deployment `revisor`, mesure `38 %` face à une cible de `50 %`, a un plancher de 2 répliques, un plafond de 6 et en compte aujourd'hui 4.

## Si tu n'as pas l'image du cours de Docker

Cette leçon utilise trois images locales : `curso-docker-revisor:1.6.0`, celle du `revisor` de la Leçon 2 ; `curso-docker-prueba:1.0.0`, celle du service qui échoue exprès ; et une nouvelle, `curso-docker-revisor:1.6.1`, qui sert à ce que la mise à jour de la leçon ait quelque chose à mettre à jour. Les deux images du `revisor` sortent du même `Dockerfile` et du même code : la seule chose qui change est la version que le service annonce dans son `/salud` (`"version":"1.6.0"` ou `"version":"1.6.1"`), et c'est justement ce qui permet de voir, requête par requête, quelle réplique a répondu. Vérifie que tu les as :

```text
$ docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E '^curso-docker-(revisor|prueba):'
curso-docker-revisor:1.6.1 61c70431badb
curso-docker-prueba:1.0.0 400d3fd59edc
curso-docker-revisor:1.6.0 bd1b2e7d91b8
```

(Cette sortie vient de la machine de l'auteur et n'est pas dans `correr.salida.txt`. Les identifiants en proviennent ; sur la tienne ils peuvent être autres si tu as construit les images toi-même. Ce qui compte, c'est que les trois tags existent.) S'il te manque la `1.6.1`, construis-la comme la `1.6.0`, depuis le dépôt du cours de Docker, avec le `Dockerfile` de sa Leçon 10 sur le dossier `programas/revisor` et avec `--build-arg VERSION=1.6.1`, en la taguant exactement `curso-docker-revisor:1.6.1`. C'est une image de laboratoire : elle sert à voir une mise à jour, ce n'est pas une nouvelle version du service.

## Les concepts

### 9.1 Le cluster et le point de départ

#### 9.1.1 Une règle de cohabitation, encore

Cette leçon installe MetalLB (par l'intermédiaire de `preparar.sh`, 9.1.3), et la règle de la Leçon 6 reste en vigueur : deux clusters avec MetalLB et la même plage d'adresses, sur le même réseau Docker, se marchent dessus. Avant de créer le tien, vérifie le réseau `kind` et que personne ne répond déjà sur la première adresse de la plage :

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar en 172.18.255.200. Si este curl responde, hay otro
# clúster con MetalLB vivo: espera a que termine.
# Si imprime un número (200, 404…), alguien contesta; si imprime 000, nadie.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -o /dev/null -w '%{http_code}\n' -m 3 http://172.18.255.200/
kind get clusters
```

Si le réseau `kind` n'existe pas encore parce que tu n'as jamais créé de cluster, crée le cluster et vérifie le réseau juste après. Il y a en outre un détail de laboratoire qu'il vaut mieux dire dès maintenant, parce qu'il change les adresses que tu verras dans les sorties : l'exécution de cette leçon a utilisé **un réseau Docker dédié**, `curso-k8s-red-l9`, avec le sous-réseau `172.29.0.0/16`, afin de pouvoir tourner en même temps que d'autres leçons qui installent elles aussi MetalLB. Sur ta machine, avec le réseau `kind` normal, les adresses de la plage sont en `172.18.255.x`, et non en `172.29.255.x` ; le script `correr.sh` s'adapte avec deux variables, `RED` et `SUBRED`, et comporte le frein habituel : si le réseau n'a pas le sous-réseau attendu, il s'arrête avant de rien créer.

#### 9.1.2 Créer le cluster et charger les images

Depuis la racine du dépôt du cours :

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l9.XXXX)/kubeconfig"
# curso-k8s-l9 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l9 --config programas/09-escalar-y-actualizar/kind-curso.yaml
# Debe decir kind-curso-k8s-l9. Si dice otra cosa, no sigas.
kubectl config current-context
# La guarda de siempre, con el nombre de este clúster. Va delante de cada
# comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-revisor:1.6.1 curso-docker-prueba:1.0.0 --name curso-k8s-l9
cd programas/09-escalar-y-actualizar
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

La fonction `ctx` compare le contexte actif avec celui qui est attendu ; s'ils coïncident, elle n'affiche rien, et sinon elle écrit « contexto equivocado: no sigo » et renvoie une erreur qui coupe la chaîne `&&`. Dans cette leçon, elle va devant chaque commande qui **change** quelque chose (`apply`, `patch`, `scale`, `drain`, `delete`) ; dans les sorties qui suivent elle est omise pour qu'elles tiennent, mais dans ton terminal elle y est. Les commandes qui ne font que **lire** (`get`, `top`, `describe`) n'en ont pas besoin, même si elle ne gêne pas. `correr.sh` fait la vérification avant chaque commande d'une autre façon, avec une fonction qui s'arrête toute seule.

Le `(umask 077; …)` fait naître `token.txt` en `-rw-------` : le masque `077` retire toutes les permissions au groupe et aux autres, et les parenthèses font que le changement ne vaut que pour cette commande. C'est le soin des Leçons 4 à 6, et il se répète parce qu'une habitude qu'on omet une fois n'est plus une habitude.

```text
$ kind create cluster --name curso-k8s-l9 --config kind-curso.yaml
(crear el clúster y esperar a que estuviera listo tardó 37 s)

$ kubectl config current-context
kind-curso-k8s-l9

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l9-control-plane  Ready   v1.37.0  172.29.0.2
curso-k8s-l9-worker         Ready   v1.37.0  172.29.0.4
curso-k8s-l9-worker2        Ready   v1.37.0  172.29.0.3
```

Créer le cluster et attendre que ses nœuds et les Pods de `kube-system` soient prêts a pris 37 secondes, avec l'image du nœud déjà téléchargée auparavant. Ce sont trois nœuds `Ready` en `v1.37.0` : un nœud de contrôle et deux nœuds de travail. La colonne `INTERNAL-IP` est l'adresse de chaque nœud sur le réseau Docker ; ici elle tombe en `172.29.0.x` à cause du réseau dédié de l'exécution, et sur ta machine elle tombera en `172.18.0.x`. Charger les trois images avec `kind load` imprime ses lignes habituelles (`not yet present on node … loading...`) ; `correr.sh` les fait taire et note à la place qu'elles ont été chargées.

#### 9.1.3 Le point de départ : `preparar.sh`

La Leçon 8 se termine avec un cluster qui porte déjà la plateforme de la Leçon 6 et le projet de la Leçon 8. Pour ne pas répéter manuellement quelques minutes d'installation, `preparar.sh` les refait avec les **trois étapes de la Leçon 6, à la vue de tous et dans le même ordre** : la plateforme (MetalLB et Envoy Gateway), l'attente avec `kubectl wait` jusqu'à ce qu'ils soient prêts, et enfin la plage d'adresses, la classe de passerelle et le projet du dossier `punto-de-partida/`. Si tu viens de la Leçon 8 avec ton cluster vivant, tu n'en as pas besoin ; si tu commences ici, ou si tu l'as déjà supprimé, tu le lances :

```bash
ctx && ./preparar.sh
```

C'est un **programme** : `preparar.sh`. Lis-le avant de le lancer : il ne cache rien. Chaque étape vérifie le contexte, imprime la commande qu'elle va lancer et s'arrête en cas d'échec. Il accepte une variable, `POOL_RANGO`, pour changer la plage de MetalLB si ton réseau n'est pas le `172.18.0.0/16`. Une remarque sur la largeur : `infra/metallb-pool.yaml` et `preparar.sh` portent `.200-.220`, tandis que `correr.sh` calcule `.200-.250`, qui est celle qu'on voit ci-dessous. Cela n'a pas d'importance ici, parce qu'on n'utilise que la première adresse de la plage, celle du Gateway.

```text
$ POOL_RANGO=172.29.255.200-172.29.255.250 ./preparar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb >/dev/null

$ kubectl apply --server-side -k infra/envoy-gateway >/dev/null

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=1200s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=1200s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=1200s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f /tmp/curso-k8s-l9.wJDg/metallb-pool.Xbdv -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k punto-de-partida >/dev/null

$ kubectl rollout status deployment/revisor deployment/prueba -n revisor --timeout=600s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=1200s
gateway.gateway.networking.k8s.io/revisor condition met
(preparar.sh tardó 343 s)
```

Cela se lit en trois temps, les mêmes que ceux de la Leçon 6. À l'**étape 1**, on applique la plateforme de MetalLB et celle d'Envoy Gateway ; leurs sorties sont envoyées vers `/dev/null` parce que ce sont des dizaines de lignes sans intérêt. À l'**étape 2** viennent les attentes, toutes avec `kubectl wait` ou `rollout status` et toutes avec un délai : les nouveaux types de MetalLB (`condition met`), le contrôleur, un `speaker` prêt sur chacun des trois nœuds, les types de Gateway API, le contrôleur d'Envoy Gateway. À l'**étape 3**, on applique la plage d'adresses (un fichier temporaire que `preparar.sh` a généré à partir de `infra/metallb-pool.yaml` avec la plage du réseau dédié : c'est l'effet de `POOL_RANGO`), la classe de passerelle `eg`, et enfin le projet de `punto-de-partida/`, avec son `rollout status` et l'attente que le Gateway soit `Programmed`. Le tout a pris 343 secondes ; en majeure partie à attendre les téléchargements d'images. Voici le point de départ de la leçon :

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           22s
deployment.apps/revisor   3/3     3            3           22s

$ kubectl get gateway -n revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.29.255.200   True         22s

$ docker run --rm --network curso-k8s-red-l9 --name curso-k8s-l9-cliente curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 5 http://172.29.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

Trois répliques du `revisor`, celle du service de test, aucun HPA ni PDB pour l'instant (le dernier `get` ne les liste pas parce qu'ils n'existent pas), et un Gateway `PROGRAMMED True` sur la première adresse de la plage. La dernière commande est le client « de l'extérieur » de la Leçon 6, un conteneur de `curl` branché au réseau Docker, qui demande `/salud` par le point d'entrée : `{"estado":"vivo","version":"1.6.0"}`. Si cela répond, la plateforme et le projet sont debout.

### 9.2 Mesurer avant de mettre à l'échelle : `metrics-server`

#### 9.2.1 Ce que le cluster ne sait pas encore

Avant de décider de combien de répliques on a besoin, il faut savoir combien de CPU utilisent celles qui existent. Le cluster ne le sait pas d'origine. Si tu le lui demandes avec `kubectl top`, la commande qui montre la consommation :

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]
```

`error: Metrics API not available` : « l'API de métriques n'est pas disponible ». La phrase a un sujet exact. Kubernetes définit une API pour la consommation de CPU et de mémoire des nœuds et des Pods, la **Metrics API**, et la documentation la décrit ainsi : elle offre « un ensemble basique de métriques pour prendre en charge l'autoscaling automatique et des cas similaires » ([Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)). Mais cette API n'est qu'une *forme* de poser la question : il faut que quelqu'un réponde. La même page le dit sans fard : il faut déployer `metrics-server` « ou un adaptateur alternatif » pour pouvoir l'utiliser, et son rôle principal est « d'alimenter en métriques d'utilisation des ressources les composants d'autoscaling ». Un cluster fraîchement créé ne l'a pas, et c'est pourquoi `top` n'a personne à qui demander.

Comment branche-t-on un répondeur sur l'API de Kubernetes ? Avec un objet que tu connais déjà par la Leçon 6, par parenté : une ressource qui enseigne quelque chose de nouveau au `kube-apiserver`. Ici ce n'est pas un CRD mais un `APIService`, qui dit au `kube-apiserver` : « les questions qui arrivent sur `/apis/metrics.k8s.io/v1beta1`, ne les traite pas toi-même ; transmets-les à ce Service ». Avant d'installer quoi que ce soit, cet objet n'existe pas :

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
Error from server (NotFound): apiservices.apiregistration.k8s.io "v1beta1.metrics.k8s.io" not found
[código de salida: 1]
```

Avec `NotFound` : le `kube-apiserver` n'a personne à qui transmettre. C'est la même situation que dans la Leçon 6 avec `Gateway`, vue sous un autre angle : avant que la pièce existe, poser une question sur elle revient à interroger le vide.

#### 9.2.2 Installer `metrics-server` tel quel

Le projet publie un manifeste par version. Celle qu'utilise cette leçon est la **v0.9.0**, et elle est figée dans l'URL, comme tout le reste a été figé dans le cours : sans version figée, le jour où la dernière version change, ton laboratoire change sans te prévenir. On l'applique tel quel, sans rien modifier, pour voir ce qui se passe :

```text
$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml | tail -3
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
(espera visible: hasta 600 s a que metrics-server descargue su imagen, arranque e intente leer a los kubelet)
```

Les trois lignes visibles sont les dernières de plusieurs (`| tail -3`) : un `Service`, un `Deployment` et l'`APIService` qui relie les deux au `kube-apiserver`. À propos du moment où regarder : le Deployment n'est pas prêt instantanément. Il doit d'abord télécharger son image et démarrer, puis tenter sa première lecture. Le script attend, à la vue de tous, que le journal du Pod montre l'erreur qu'on veut lire (jusqu'à 600 secondes, parce que sur une machine lente le téléchargement prend du temps). Dans ton terminal, tu peux répéter `kubectl get deployment metrics-server -n kube-system` jusqu'à voir `0/1` avec quelques secondes d'âge. C'est une attente d'un autre type que `kubectl wait` : ici on n'attend pas qu'une condition *arrive*, on attend pour *laisser le temps d'échouer* et pouvoir lire comment.

```text
$ kubectl get deployment metrics-server -n kube-system
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   0/1     1            0           30s
```

`READY 0/1` et `AVAILABLE 0` : le Pod existe mais n'est pas prêt. On suit l'ordre de la Leçon 5, qui dit quoi regarder en premier quand quelque chose ne démarre pas : le journal du Pod.

```text
$ kubectl logs -n kube-system deployment/metrics-server --tail=200 | grep -E 'x509|tls|certificate' | tail -1
E1021 23:14:05.707527       1 scraper.go:149] "Failed to scrape node" err="Get \"https://172.29.0.2:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs" node="curso-k8s-l9-control-plane"
```

Cela se lit de gauche à droite. `E1021` est une ligne de niveau *erreur* du 21 octobre. `scraper.go:149` est l'endroit du code qui a échoué, et `Failed to scrape node` dit ce qu'il essayait de faire : « racler » (collecter) les métriques du nœud, ce que fait `metrics-server` toutes les quelques secondes, en demandant à chaque `kubelet` le CPU et la mémoire qu'utilisent ses Pods. L'adresse est `https://172.29.0.2:10250/metrics/resource` : le `kubelet` de ce nœud (celui de contrôle ; sur ta machine ce sera `172.18.0.x`), par son IP, sur le port 10250. Et la cause, à la fin : `tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs`.

Il faut démonter cette phrase. TLS est le chiffrement avec lequel `metrics-server` parle au `kubelet` (HTTPS). Pour que le chiffrement vaille quelque chose, `metrics-server` vérifie le **certificat** que le `kubelet` lui présente : il contrôle qu'il a été signé par une autorité en laquelle il a confiance et que le certificat dit appartenir à l'adresse à laquelle il s'est connecté. Un certificat porte une liste de noms et d'adresses valides, les *Subject Alternative Names* (SAN). Ici le certificat du `kubelet` ne contient aucune **IP** dans cette liste, et `metrics-server` s'est connecté par IP : c'est pourquoi il ne peut pas valider que « `172.29.0.2` » est bien qui il prétend être. Ce que le journal démontre se limite à cela : le certificat ne contient aucune IP. Le README de `metrics-server` pose comme prérequis que le certificat du `kubelet` soit signé par l'autorité du cluster ([metrics-server](https://github.com/kubernetes-sigs/metrics-server)), et dans kind les nœuds ne le respectent pas tels quels. Dans un vrai cluster, cela se règle sur les nœuds ; dans ce laboratoire, on n'essaie pas.

Le Pod n'étant pas prêt, le `Service` de `metrics-server` n'a pas de destinations, et l'`APIService` le reflète :

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]

$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE                  AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   False (MissingEndpoints)   30s
```

`AVAILABLE False (MissingEndpoints)` : « les destinations manquent ». Le Service n'a personne à qui envoyer les questions parce que l'unique Pod n'est pas prêt. Maintenant l'erreur de `kubectl top` a sa chaîne complète : la commande interroge le `kube-apiserver` ; celui-ci transmet au Service ; le Service n'a pas de destinations ; l'unique destination n'est pas prête ; et elle n'est pas prête parce qu'elle ne peut pas vérifier le certificat du `kubelet`. Cinq maillons, et le message du dessus ne montrait que le dernier. C'est le même métier que dans la Leçon 3 : on descend d'étage en étage jusqu'à trouver celui qui est défaillant.

#### 9.2.3 Le drapeau, et pourquoi il n'est que pour le laboratoire

`metrics-server` a une option pour ne pas vérifier le certificat des `kubelet` : `--kubelet-insecure-tls`. Son README la décrit en deux phrases courtes qu'il convient de lire lentement : « Do not verify the CA of serving certificates presented by Kubelets. For testing purposes only » (« Ne vérifie pas l'autorité des certificats présentés par les kubelet. Uniquement pour des tests »). Ce n'est pas une façon de parler pour se donner bonne conscience : c'est un avertissement, et la leçon le respecte. Ce drapeau vaut dans un laboratoire où les nœuds sont des conteneurs à toi sur ta machine, et il ne vaut pas dans un cluster où quelqu'un d'autre pourrait se mettre sur le réseau entre `metrics-server` et un nœud, parce que sans vérifier le certificat il n'y a aucun moyen de savoir à qui on parle.

Le manifeste de la v0.9.0 ne porte pas le drapeau ; on l'ajoute avec un *patch* Kustomize. C'est un **programme** : `metrics-server/kustomization.yaml`.

```yaml
# metrics-server — Lección 9. Versión fijada (v0.9.0). En kind, el certificado de
# cada kubelet no trae ninguna IP y metrics-server no lo acepta sin
# --kubelet-insecure-tls. Eso SOLO vale en un clúster de laboratorio.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
patches:
- target:
    kind: Deployment
    name: metrics-server
    namespace: kube-system
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --kubelet-insecure-tls
```

Le patch dit : dans le Deployment `metrics-server` de l'espace de noms `kube-system`, ajoute à la fin de la liste d'arguments du premier conteneur `--kubelet-insecure-tls`. Le `op: add` avec `args/-` est la façon de dire « ajouter à la fin » d'une liste dans un patch de type JSON. On l'applique avec `-k`, comme tout le reste :

```text
$ kubectl apply -k metrics-server | tail -3
service/metrics-server unchanged
deployment.apps/metrics-server configured
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io unchanged
```

Deux objets `unchanged` (le Service et l'APIService ne changent pas) et un `configured` : le Deployment. Son modèle a changé, il y aura donc un remplacement du Pod, et cette fois l'attente est bien une attente de condition :

```text
$ kubectl rollout status deployment/metrics-server -n kube-system --timeout=600s
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
deployment "metrics-server" successfully rolled out
(espera de 45 s: metrics-server mide en ventanas y necesita un par de ellas)
```

Vient ensuite une pause qui n'est pas une attente de condition, et il vaut mieux le dire : `metrics-server` mesure par fenêtres de temps et a besoin de quelques-unes avant de pouvoir répondre avec des données, si bien que la leçon attend 45 secondes d'horloge. Au lieu de deviner, il existe une façon de vérifier qu'il répond déjà : interroger l'`APIService`, qui doit passer à `True`.

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        98s
```

`AVAILABLE True`. Maintenant `top` a quelqu'un à interroger :

```text
$ kubectl top nodes
NAME                         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
curso-k8s-l9-control-plane   139m         2%       974Mi           6%          
curso-k8s-l9-worker          92m          1%       272Mi           1%          
curso-k8s-l9-worker2         53m          0%       316Mi           1%          

$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-cgzkw    1m           1Mi             
revisor-67b97d67c9-fnpdj   1m           1Mi             
revisor-67b97d67c9-jfdw4   1m           1Mi             
revisor-67b97d67c9-tqffn   1m           1Mi             
```

La colonne `CPU(cores)` est en **millicores** : `1m` est un millième de cœur, la même unité que les `requests` de la Leçon 5. La documentation explique d'où elle sort : le CPU est rapporté « comme l'utilisation moyenne des cœurs », calculée « comme un taux sur un compteur cumulatif de CPU fourni par le noyau » de Linux, sur une fenêtre de temps que l'API elle-même indique (champ `window`). Ce n'est pas une photo d'un instant, c'est une moyenne sur une fenêtre courte. Et `CPU(%)` dans `top nodes` est le pourcentage du CPU **du nœud**, et non du `request` de qui que ce soit ; c'est un autre calcul, et celui qui importe à l'autoscaler est le suivant. Regarde les Pods du `revisor` : quelques dixièmes de millicore ou quelques millicores d'utilisation, contre les `50m` qu'ils ont demandés :

```text
$ kubectl describe pod -n revisor -l app=revisor | grep -E 'Requests|cpu:' | head -4
      cpu:     200m
    Requests:
      cpu:      50m
      cpu:     200m
```

(Le premier `cpu: 200m` est la `limit` ; le `Requests` et son `cpu: 50m`, le plancher. Le troisième est la `limit` de l'autre conteneur listé ; le filtre `head -4` coupe la sortie là où elle tient.) Un Pod qui utilise `4m` sur `50m` est à 8 % de ce qu'il a demandé. Ce pourcentage, celui de l'**utilisation par rapport aux `requests`**, est l'étalon de l'autoscaler.

La documentation de `metrics-server` dit aussi à quoi il ne sert **pas**, et il vaut la peine de l'entendre avant de lui faire confiance : ses cas d'usage sont la mise à l'échelle horizontale par CPU et mémoire, et son README avertit qu'il n'est pas « une source exacte de l'utilisation des ressources ». Pour observer la consommation avec précision, la représenter graphiquement ou alerter, d'autres outils existent. Pour décider du nombre de répliques, il suffit.

### 9.3 L'autoscaler et sa formule

#### 9.3.1 Ce que c'est et à quelle fréquence il regarde

Le `HorizontalPodAutoscaler` est un contrôleur, un de plus parmi ceux que tu as vus dans la Leçon 0 faire la même chose que d'habitude : comparer l'état souhaité avec l'état réel et pousser le second vers le premier. La différence tient à ce qu'il entend par « état souhaité » : non pas un nombre de répliques, mais une **cible de consommation**. « Horizontal » veut dire qu'il change le *nombre* de répliques, et non la taille de chacune. La documentation dit que la boucle tourne toutes les 15 secondes par défaut (`--horizontal-pod-autoscaler-sync-period`) ([Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)).

À chaque tour, il fait trois choses : il lit les métriques des Pods de la cible, il calcule combien de répliques il demanderait, et, si le résultat change le nombre actuel, il le demande au Deployment. La partie qui peut se calculer manuellement est la deuxième, et c'est celle-ci :

```text
réplicas deseadas = ceil( réplicas actuales × (métrica actual ÷ métrica deseada) )
```

C'est la formule que donne la documentation : `desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]`. `ceil` signifie « arrondir à l'entier supérieur ». Avec une cible de CPU de 50 % : s'il y a 2 répliques et que l'utilisation moyenne est de 100 % de ce qu'elles ont demandé, le calcul est `ceil(2 × 100 ÷ 50) = ceil(4) = 4`. Si l'utilisation moyenne est de 25 %, `ceil(2 × 25 ÷ 50) = ceil(1) = 1`. L'arrondi à l'entier supérieur a une raison : mieux vaut un Pod de trop qu'un Pod de moins quand la cible est sur le point d'être dépassée.

Et le « pourcentage » ? Avec une cible de type `Utilization`, le contrôleur calcule l'utilisation « comme un pourcentage de la demande (`request`) équivalente des conteneurs de chaque Pod », et prend la moyenne de tous les Pods cibles. C'est pourquoi un Pod sans `requests` de CPU est un Pod que l'autoscaler ne peut pas mesurer : la documentation dit que, si un conteneur n'a pas la demande, « l'utilisation de CPU du Pod n'est pas définie et l'autoscaler ne fera rien avec cette métrique ». La Leçon 5 a mis des `requests` dans chaque conteneur « pour que le planificateur sache où le placer » ; aujourd'hui cette décision sert à une seconde chose qu'on ne voyait pas alors.

#### 9.3.2 La tolérance de 10 %

Si le calcul s'appliquait tel quel, l'autoscaler changerait le nombre de répliques pour des différences d'un point de pourcentage, et le cluster serait en ajustement perpétuel. Pour l'éviter, le contrôleur saute tout ajustement quand le rapport `métrique actuelle ÷ métrique souhaitée` est « suffisamment proche de 1.0 », et la documentation donne la mesure : une tolérance de 0.1 par défaut, c'est-à-dire de 10 % (depuis Kubernetes 1.37, chaque HPA peut fixer sa propre tolérance dans `behavior.scaleUp.tolerance` et `behavior.scaleDown.tolerance` ; cette leçon laisse celle du cluster, 10 %). Avec une cible de 50 %, il n'y a d'ajustement que si l'utilisation mesurée tombe hors de 45 % à 55 % : le rapport doit être inférieur à 0.9 ou supérieur à 1.1.

Un exemple chiffré, pour le calculer manuellement avant de voir le cluster. Avec 3 répliques et une cible de 50 % :

| Utilisation mesurée | Rapport | Hors de 0.9 à 1.1 ? | `ceil(3 × rapport)` | Ce qu'il fait |
|---|---|---|---|---|
| 54 % | 1.08 | non | — | rien |
| 57 % | 1.14 | oui | `ceil(3.42)` = 4 | monte à 4 |
| 40 % | 0.80 | oui | `ceil(2.4)` = 3 | ne change pas (3), mais la recommandation est notée |
| 20 % | 0.40 | oui | `ceil(1.2)` = 2 | descend à 2 (si la fenêtre le permet) |

Quand le cluster te donnera des chiffres, tu les vérifieras avec ce tableau.

#### 9.3.3 Le manifeste

C'est un **programme** : `escalado.yaml`. Il contient deux objets, l'autoscaler et un budget d'interruptions qui s'explique en 9.11.

```yaml
# escalado.yaml — Lección 9: réplicas según la carga, con límites, y al menos
# una disponible durante un mantenimiento.
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: revisor
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: revisor
  minReplicas: 2
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: revisor
```

On le lit champ par champ :

- **`scaleTargetRef`** : qui il gouverne. Un `Deployment` nommé `revisor` du même espace de noms. Le HPA ne touche pas aux Pods : il demande au Deployment de changer son nombre de répliques, et le Deployment fait le reste, comme toujours.
- **`minReplicas: 2` et `maxReplicas: 6`** : le plancher et le plafond. Le plancher est 2 pour deux raisons : avec une seule réplique, tout remplacement est une coupure, et avec deux (une sur chaque nœud de travail) la mise à jour de 9.9 et la maintenance de 9.11 peuvent se faire sans perdre le service. Le plafond est 6 à cause de l'habitude de sécurité qui clôt cette leçon : un autoscaler sans plafond transforme une avalanche de requêtes, ou une erreur dans une boucle, en facture ou en nœud épuisé.
- **`metrics`** : ce qu'il mesure et par rapport à quoi. Une ressource, le CPU, avec une cible d'utilisation moyenne de 50 % *des `requests`*. C'est une cible intermédiaire exprès : si elle était de 90 %, l'autoscaler réagirait quand le service est déjà presque saturé.
- **`behavior.scaleDown.stabilizationWindowSeconds: 60`** : la fenêtre de réduction, qui s'explique ci-dessous.

Le champ `behavior` mérite un paragraphe à part. Sans lui, le HPA utilise les valeurs par défaut de la documentation : pour **monter**, une fenêtre de stabilisation de 0 seconde et une politique qui permet d'ajouter jusqu'à 4 Pods ou de doubler les répliques toutes les 15 secondes, la plus grande des deux ; pour **descendre**, une fenêtre de **300 secondes** (cinq minutes) et une politique qui permet de retirer d'un coup toutes les répliques excédentaires. La leçon utilise 60 secondes au lieu de 300 pour que tu puisses voir la réduction sans attendre cinq minutes, et elle le dit parce que ce n'est pas une valeur à copier : en production, la longue fenêtre protège contre le va-et-vient (« je monte, je descends, je monte, je descends ») quand la charge est irrégulière.

Que fait la fenêtre, exactement ? La documentation l'explique avec précision : juste avant de mettre à l'échelle, le contrôleur note la recommandation du moment, puis « considère toutes les recommandations à l'intérieur de la fenêtre configurée et choisit la plus haute ». Autrement dit : pour **descendre**, le HPA n'utilise pas ce qu'il voit maintenant, mais le **maximum** de ce qu'il a recommandé durant les 60 dernières secondes. S'il recommandait 4 répliques il y a 40 secondes et en recommande 2 maintenant, il reste à 4 jusqu'à ce que cette recommandation de 4 sorte de la fenêtre. C'est une mémoire délibérée du pire récent, et c'est la raison pour laquelle la réduction est lente et la montée ne l'est pas.

Enfin, le `kubectl diff` de 9.5 va montrer que le HPA, une fois appliqué, porte écrites dans la sortie les valeurs par défaut de `scaleUp` et `scaleDown` (`selectPolicy: Max`, les politiques de 15 secondes) : le serveur complète ce que tu n'as pas écrit.

#### 9.3.4 Pourquoi le Deployment ne porte plus `replicas`

Dans le dossier de la Leçon 8, le Deployment du `revisor` disait `replicas: 3`. Dans celui d'aujourd'hui, ce champ n'est plus là. Ce n'est pas un oubli : c'est la recommandation explicite de la documentation du HPA. Quand il y a un autoscaler, le champ `spec.replicas` du Deployment devrait être retiré du manifeste, car sinon, « chaque fois qu'un changement est appliqué à cet objet, par exemple avec `kubectl apply -f deployment.yaml`, Kubernetes mettra à l'échelle le nombre actuel de Pods à la valeur de `spec.replicas` », ce qui « peut être problématique quand un HPA est actif, et provoquer du *va-et-vient* ». Deux propriétaires d'un même nombre se disputent : ton fichier dit 3, le HPA vient d'en demander 5, et chaque `apply` défait ce que l'autre a fait.

La documentation ajoute un avertissement que 9.5 va rendre visible : retirer le champ « peut provoquer une unique dégradation du nombre de Pods, car la valeur par défaut de cette clé est 1 ». C'est-à-dire qu'en appliquant pour la première fois le Deployment **sans** `replicas`, le cluster le lit comme « retour à la valeur par défaut » et propose de descendre à une seule réplique. En 9.5 tu verras ce `replicas: 1` dans le `kubectl diff`, et tu verras ce qui se passe ensuite.

### 9.4 Répartir les répliques

#### 9.4.1 Le problème : rien ne répartit à ta place

Un autoscaler qui monte à quatre répliques ne dit pas où il les met ; cela, c'est le planificateur (*scheduler*) qui le décide, en cherchant le nœud qui convient le mieux par ressources et autres règles, et par défaut il ne s'efforce pas de répartir. Regarde comment se sont retrouvées les trois répliques du dossier de la Leçon 8, sans aucune règle de répartition :

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>
```

La colonne `NODE` dit où se trouve chacune. Dans cette exécution, deux des trois répliques sont tombées ensemble sur `curso-k8s-l9-worker2` et une sur `curso-k8s-l9-worker`. Ce n'est pas de la malchance : dans cette exécution et dans trois précédentes qui n'ont pas été conservées, deux des trois répliques sont tombées ensemble, tantôt sur un nœud, tantôt sur l'autre. Le planificateur ne promet pas de répartir. Si le nœud qui porte deux répliques tombe en panne, le service perd 67 % de sa capacité d'un coup, et l'autoscaler n'aide pas : son travail est de regarder le CPU, pas la répartition.

#### 9.4.2 `topologySpreadConstraints`

Kubernetes a une pièce pour cela : les **contraintes de répartition par topologie**. « Topologie » veut dire ici « dans quelle partie de l'infrastructure vit chaque chose » : sur quel nœud, dans quelle zone d'un cloud, dans quel rack. La documentation définit le vocabulaire ([Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/)) : une étiquette de nœud, `topologyKey`, divise les nœuds en **domaines**, et les nœuds qui ont la même valeur de cette étiquette forment un même domaine. L'étiquette `kubernetes.io/hostname` a une valeur différente par nœud, donc avec elle *chaque nœud est son propre domaine*. C'est ce qu'on veut ici : répartir entre les nœuds.

La contrainte du `revisor` est la suivante. C'est un fragment du **programme** `revisor-deployment.yaml`, à l'intérieur de `spec.template.spec` :

```yaml
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        nodeTaintsPolicy: Honor
        labelSelector:
          matchLabels:
            app: revisor
        matchLabelKeys:
        - pod-template-hash
```

Chaque champ, dans l'ordre :

- **`topologyKey: kubernetes.io/hostname`** : chaque nœud est un domaine, comme on l'a dit.
- **`labelSelector`** : quels Pods sont comptés dans chaque domaine. Ceux qui portent `app: revisor` ; les répliques de `prueba` ou les Pods de charge ne comptent pas, et ne gênent pas.
- **`maxSkew: 1`** : l'**asymétrie** (*skew*) maximale permise : la différence entre le nombre de Pods d'un domaine et celui du domaine qui en a le moins. La documentation le définit ainsi : avec `DoNotSchedule`, `maxSkew` « est la différence maximale permise entre le nombre de Pods correspondants dans le domaine cible et le *minimum global* ». Avec `maxSkew: 1` et deux nœuds de travail, 2 + 0 n'est pas permis (différence de 2), 1 + 1 oui, 2 + 1 oui, 3 + 1 non.
- **`whenUnsatisfiable: DoNotSchedule`** : que faire si placer le Pod enfreint la contrainte. `DoNotSchedule` (la valeur par défaut) dit « ne le planifie pas » : le Pod reste `Pending`. `ScheduleAnyway` dit « planifie-le quand même, mais en préférant les endroits qui réduisent l'asymétrie » : c'est une préférence, pas une règle. Cette leçon utilise la règle stricte, parce que la souple laisse passer justement ce qu'on veut éviter : la contrainte sert à ce que la répartition *soit réelle*, et une préférence ne le garantit pas.
- **`nodeTaintsPolicy: Honor`** : comment traiter les *taints* des nœuds (les « marques » qui repoussent les Pods) dans le calcul de l'asymétrie. Cela s'explique en 9.4.3 et se vérifie en 9.5.4, parce que c'est le champ qui semble superflu et qui ne l'est pas.
- **`matchLabelKeys: [pod-template-hash]`** : restreint le décompte aux répliques de la **même version**. Le Deployment met sur chaque Pod une étiquette, `pod-template-hash`, avec une valeur différente pour chaque version du modèle. La documentation dit que cette étiquette, qui est « ajoutée automatiquement par le contrôleur du Deployment », sert « à distinguer les différentes révisions d'un même Deployment ». Pendant une mise à jour, d'anciennes et de nouvelles répliques cohabitent ; sans ce champ, les anciennes compteraient dans la répartition des nouvelles et les gêneraient ; avec lui, chaque version se répartit pour son propre compte.

#### 9.4.3 Pourquoi le nœud de contrôle exige `Honor`

Le cluster a trois nœuds et seuls deux reçoivent des répliques. Le nœud de contrôle porte un *taint* (`node-role.kubernetes.io/control-plane:NoSchedule`) qui empêche d'y planifier des Pods d'utilisateur. Mais compte-t-il comme domaine pour le calcul du « minimum global » ? Cela dépend de `nodeTaintsPolicy`. La documentation définit les deux options : `Honor` inclut « les nœuds sans taints, ainsi que les nœuds marqués pour lesquels le Pod entrant a une tolérance » ; `Ignore` ignore les taints et inclut tous les nœuds ; et si le champ est vide, le comportement équivaut à `Ignore`.

Cela signifie que, **sans** `Honor`, le nœud de contrôle entre dans le compte comme un domaine à zéro Pod, et le « minimum global » est 0, parce que ce nœud ne peut pas recevoir de réplique. Avec ce zéro fixe, `maxSkew: 1` permet au plus 1 Pod par domaine : la troisième réplique n'aurait nulle part où aller. C'est le genre de règle qui fonctionne avec deux répliques et se brise avec la troisième, et c'est précisément pour cela que c'est une erreur qu'on découvre en production un lundi à 9 h 00. 9.5.4 la provoque pour que tu la voies.

#### 9.4.4 Ce que la contrainte ne fait pas

La documentation de cette pièce comporte un avertissement dans sa section des limitations : « il n'y a aucune garantie que les contraintes continuent d'être respectées quand des Pods sont retirés. Par exemple, réduire un Deployment peut laisser les Pods déséquilibrés », et elle recommande des outils comme le *Descheduler* pour rééquilibrer. La règle s'applique **au moment de planifier** un nouveau Pod, ni avant ni après. 9.11 va le montrer avec une maintenance qui laisse les répliques ensemble, et montrera aussi comment on y remédie sans rien installer.

### 9.5 Appliquer les changements

#### 9.5.1 Ce qui change, avant d'appliquer

Avec le dossier de la Leçon 9 prêt, la première étape n'est pas d'appliquer mais de demander ce qui va changer. `kubectl diff -k .` envoie au serveur le résultat du `-k` et montre la différence avec ce qui existe. La commande est filtrée (`grep -E '^[+-] '`) pour ne garder que les lignes qui changent et retirer le bruit des métadonnées (`creationTimestamp`, `uid`, `resourceVersion`) :

```text
$ kubectl diff -k . | grep -E '^[+-] ' | grep -v -E 'creationTimestamp|generation|resourceVersion|uid:|managedFields'
-  replicas: 3
+  replicas: 1
-      maxSurge: 25%
-      maxUnavailable: 25%
+      maxSurge: 1
+      maxUnavailable: 0
+        lifecycle:
+          preStop:
+            sleep:
+              seconds: 5
-      terminationGracePeriodSeconds: 10
+      terminationGracePeriodSeconds: 15
+      topologySpreadConstraints:
+      - labelSelector:
+          matchLabels:
+            app: revisor
+        matchLabelKeys:
+        - pod-template-hash
+        maxSkew: 1
+        nodeTaintsPolicy: Honor
+        topologyKey: kubernetes.io/hostname
+        whenUnsatisfiable: DoNotSchedule
+  name: revisor
+  namespace: revisor
+  behavior:
+    scaleDown:
+      policies:
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 60
+    scaleUp:
+      policies:
+      - periodSeconds: 15
+        type: Pods
+        value: 4
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 0
+  maxReplicas: 6
+  metrics:
+  - resource:
+      name: cpu
+      target:
+        averageUtilization: 50
+        type: Utilization
+    type: Resource
+  minReplicas: 2
+  scaleTargetRef:
+    apiVersion: apps/v1
+    kind: Deployment
+    name: revisor
+  currentMetrics: null
+  desiredReplicas: 0
+  name: revisor
+  namespace: revisor
+  minAvailable: 1
+  selector:
+    matchLabels:
+      app: revisor
+  currentHealthy: 0
+  desiredHealthy: 0
+  disruptionsAllowed: 0
+  expectedPods: 0
[código de salida: 1]
```

Le code `1` à la fin n'est pas une erreur : `kubectl diff` sort avec 1 quand il **y a** des différences, et avec 0 quand il n'y en a pas, pour pouvoir s'utiliser dans un script. Cela se lit en trois blocs :

1. **`-  replicas: 3` / `+  replicas: 1`.** Ce qui a été annoncé en 9.3.4. Le fichier ne dit plus `replicas`, et le serveur, qui apporte sa valeur par défaut, propose **1**. Si tu appliques cela sans réfléchir, le `revisor` passe de trois répliques à une, ne serait-ce qu'un instant, avant que l'autoscaler le corrige. Ici ce n'est pas grave ; avec 40 personnes connectées à 9 h 00, ce le serait. C'est le coût unique de la remise du contrôle du nombre de répliques, et mieux vaut le savoir avant de le payer.
2. **`maxSurge: 25%` → `1` et `maxUnavailable: 25%` → `0`.** Les valeurs par défaut de la stratégie de mise à jour deviennent explicites. Elles s'expliquent en 9.9.
3. **`lifecycle` / `preStop`, `terminationGracePeriodSeconds: 10` → `15` et `topologySpreadConstraints`.** La pause avant l'arrêt, le délai plus long dont cette pause a besoin et la répartition de 9.4. Et en dessous, les nouveaux objets : le HPA (avec les valeurs par défaut écrites) et le PodDisruptionBudget.

#### 9.5.2 Appliquer et observer

```text
$ kubectl apply -k . | grep -E 'horizontalpod|poddisruption|deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
poddisruptionbudget.policy/revisor created
horizontalpodautoscaler.autoscaling/revisor created

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
(espera de 30 s: el HPA necesita su primera lectura de métricas)
```

Quatre lignes : `deployment.apps/revisor configured`, le PDB et le HPA `created`, et `prueba unchanged` (ce qui n'a pas changé n'est pas touché). Le `rollout status` montre le remplacement des répliques, parce que le modèle a changé (le `preStop`, le délai et la répartition) et que, pour cette raison, il y a un remplacement ordonné, une réplique à la fois, comme dans la Leçon 2. Ensuite vient une pause de 30 secondes à la vue de tous : le HPA a besoin de sa première lecture de métriques avant d'afficher un nombre.

```text
$ kubectl get hpa,pdb -n revisor
NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          32s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     32s
```

Lis la colonne `TARGETS` du HPA : `cpu: 2%/50%` signifie « utilisation actuelle / cible ». L'utilisation est la moyenne, rapportée aux `requests` des Pods, qu'a expliquée 9.2. `MINPODS 2` et `MAXPODS 6` sont le plancher et le plafond, et `REPLICAS` est le nombre actuel. Dans le PDB, `ALLOWED DISRUPTIONS` dit combien de Pods peuvent être perdus volontairement à l'instant même ; cela s'explique en 9.11.

Un détail de lecture : la première fois qu'on applique le HPA, si tu regardes trop tôt, `TARGETS` dit `cpu: <unknown>/50%`. Ce n'est pas une panne : le contrôleur n'a pas encore de mesure des nouveaux Pods. Les événements du HPA, qui se lisent en 9.6, gardent la trace de ces premières secondes.

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-5xvt5   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-857qf   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.replicas}{"\n"}'
2
```

Deux répliques, **une sur chaque nœud de travail**. La répartition a été respectée, et c'est le HPA qui a fixé le nombre de répliques : `.spec.replicas` vaut 2, le plancher. L'enchaînement le plus probable, et celui que suggère l'événement `Current number of replicas below Spec.MinReplicas` de 9.6, a été : l'`apply` a laissé le Deployment à 1 (la valeur par défaut), le HPA a vu que 1 était en dessous du plancher de 2 et l'a relevé, et le remplacement a réparti les deux répliques grâce à la contrainte.

#### 9.5.3 Le journal du HPA raconte ce qu'il a fait

Le HPA laisse ses décisions dans les événements. On les lit avec `describe`, qui sera montré en entier en 9.6 après la charge, et la première ligne est la trace de ce qui précède : `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. « Le nombre actuel de répliques est en dessous du minimum » : le HPA ne réagissait pas à la charge, il appliquait le plancher.

#### 9.5.4 L'erreur : la répartition sans `nodeTaintsPolicy: Honor`

Voici maintenant l'erreur promise en 9.4.3. On la provoque en retirant seulement `nodeTaintsPolicy` du Deployment vivant, avec un patch, et en demandant une troisième réplique manuellement :

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/topologySpreadConstraints/0/nodeTaintsPolicy"}]'
deployment.apps/revisor patched

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running       0          6s    10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running       0          3s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5xvt5   1/1     Terminating   0          38s   10.244.2.8   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-857qf   1/1     Terminating   0          38s   10.244.1.8   curso-k8s-l9-worker    <none>           <none>
```

Avec deux répliques, tout semble normal. C'est ce qui rend cette erreur traîtresse : le défaut ne se voit pas avant l'arrivée de la troisième.

```text
$ kubectl scale deployment/revisor -n revisor --replicas=3
deployment.apps/revisor scaled
(espera de 6 s: el planificador decide en un instante)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running   0          12s   10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-4nwx5   0/1     Pending   0          6s    <none>       <none>                 <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running   0          9s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
```

La troisième réplique reste `Pending`, sans nœud attribué. On suit l'ordre de la Leçon 5 : le `describe` du Pod en attente (le nom change dans ton exécution), section des événements.

```text
$ kubectl describe pod revisor-574b5b6c4c-4nwx5 -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  6s    default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match pod topology spread constraints. preemption: 0/3 nodes are available: 1 Preemption is not helpful for scheduling, 2 No preemption victims found for incoming pod.
```

Lis-le : `0/3 nodes are available` dit que, sur les trois nœuds, aucun ne convient. Et il donne le motif de chacun : un nœud a un taint que le Pod ne tolère pas (*untolerated taint* ; c'est celui de contrôle), et les deux autres « ne correspondent pas aux contraintes de répartition par topologie » (*didn't match pod topology spread constraints*). C'est exactement ce qui était annoncé : le nœud de contrôle compte comme un domaine à zéro Pod, le minimum global est 0, et placer la troisième réplique sur l'un des deux autres donnerait une asymétrie de 2.

La correction consiste à réappliquer le fichier, qui porte `Honor` :

```text
# --- La corrección: volver a aplicar la carpeta (trae Honor) ---

$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Terminating   0          18s   10.244.1.9    curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Terminating   0          15s   10.244.2.9    curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running       0          6s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-76td2   1/1     Running       0          2s    10.244.1.11   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running       0          4s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
(espera de 75 s: la ventana de bajada del autoescalador es de 60 s)
```

Avec `Honor`, le nœud de contrôle sort du compte : trois répliques dans deux domaines, 2 + 1, asymétrie de 1. Cela tient. Et comme `apply -k` ne porte pas `replicas`, le nombre vit dans le Deployment jusqu'à ce que le HPA le corrige : après la fenêtre de réduction de 60 secondes (à la vue de tous, 75 d'attente), le HPA ramène le compte à 2, ce que la charge demande.

```text
$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           4m11s
deployment.apps/revisor   2/2     2            2           4m11s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          2m5s

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          82s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          80s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

### 9.6 Avec de la charge, l'autoscaler monte

#### 9.6.1 Une charge qu'on peut arrêter

Pour voir l'autoscaler travailler, il faut de la charge, et la charge doit pouvoir s'arrêter quand tu le veux. C'est un **programme** : `carga.yaml`.

```yaml
# carga.yaml — Lección 9: genera carga contra el revisor para ver subir el HPA.
# No forma parte del proyecto: se aplica con -f, se observa y se borra.
apiVersion: batch/v1
kind: Job
metadata:
  name: carga
  namespace: revisor
spec:
  parallelism: 4
  backoffLimit: 0
  activeDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app: carga
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
      - name: carga
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["sh", "-c", "while true; do curl -s -o /dev/null http://revisor/salud; done"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 200m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

C'est un `Job`, l'objet de la Leçon 8 pour les tâches qui se terminent, avec quatre Pods en parallèle (`parallelism: 4`) qui répètent sans arrêt une requête vers `http://revisor/salud`. Il n'y a pas de pause entre l'une et l'autre : chaque Pod demande, reçoit, et redemande. On le lit par décisions :

- **`activeDeadlineSeconds: 600`** : quoi qu'il arrive, le Job s'arrête au bout de 10 minutes : il doit survivre au téléchargement de l'image plus les 200 secondes d'observation. Un générateur de charge sans frein est une panne en attente ; celui-ci se termine même si tu oublies de le supprimer.
- **`backoffLimit: 0`** : si un Pod échoue, on ne réessaie pas. C'est une charge de laboratoire, pas une tâche qui compte.
- **`acceso-revisor: permitido`** : l'étiquette que le réseau fermé de la Leçon 7 exige pour atteindre le `revisor`. Sans elle, les Pods de charge n'arriveraient nulle part, et le HPA ne verrait aucune charge. C'est la même autorisation que celle du Pod `depurar`.
- **`limits: cpu: 200m`** : chaque Pod de charge peut consommer jusqu'à un cinquième de cœur. Cela pose un **plafond à la charge qu'on peut générer** : quatre Pods de 200m font 800m au total, et la part qui devient du CPU du `revisor` dépend du nombre de requêtes par seconde auxquelles il parvient à répondre. Ce n'est pas un test de performance ; c'est un levier avec une butée.
- **L'image de `curl`, figée par son empreinte**, comme dans la Leçon 3. La première fois qu'un nœud l'utilise, il la télécharge depuis internet ; c'est pourquoi le script attend (à la vue de tous) que les Pods de charge soient prêts avant de commencer à regarder l'horloge.

#### 9.6.2 Appliquer, attendre, regarder

```text
$ kubectl apply -f carga.yaml
job.batch/carga created
(espera visible: hasta 600 s a que los Pods de carga arranquen; la primera vez descargan la imagen de curl)
```

Vient ensuite une attente avec `kubectl wait`, pour la raison ci-dessus : tant que les Pods de charge ne sont pas `Ready`, il n'y a pas de charge, et regarder le HPA avant reviendrait à mesurer le silence.

```text
$ kubectl wait --for=condition=Ready pod -l app=carga -n revisor --timeout=600s
pod/carga-29s8s condition met
pod/carga-bz6zl condition met
pod/carga-nv5tb condition met
pod/carga-rnhz5 condition met
```

Maintenant le temps court. Le script imprime une ligne du HPA toutes les 20 secondes pendant 200 secondes. Dans ton terminal, l'équivalent est `kubectl get hpa revisor -n revisor --watch` (qui imprime une nouvelle ligne chaque fois que quelque chose change), ou une boucle de `get` et `sleep 20` comme celle du script. L'attente fait partie de la leçon : l'autoscaler n'est pas instantané, et voir combien il met est ce qu'on apprend.

```text
(un renglón del HPA cada 20 s, durante 200 s; empieza a las 17:18:00)
[+ 20s] revisor   Deployment/revisor   cpu: 27%/50%   2     6     2     2m50s
[+ 40s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     2     3m10s
[+ 60s] revisor   Deployment/revisor   cpu: 72%/50%   2     6     2     3m30s
[+ 80s] revisor   Deployment/revisor   cpu: 58%/50%   2     6     3     3m51s
[+100s] revisor   Deployment/revisor   cpu: 44%/50%   2     6     4     4m11s
[+120s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     4     4m31s
[+140s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     4m51s
[+160s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m11s
[+180s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m31s
[+200s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

Chaque ligne se lit de la même façon : le temps écoulé depuis le début de la charge, le nom, la cible, la colonne `TARGETS` (`utilisation actuelle / cible`), le plancher, le plafond, les répliques et l'âge du HPA. Il faut les lire avec la formule de 9.3 en main.

Les lignes, avec la formule de 9.3 appliquée à chacune :

| Temps | Utilisation mesurée | Répliques | Rapport (utilisation ÷ 50) | Calcul | Ce qu'il fait |
|---|---|---|---|---|---|
| +20 s | 27 % | 2 | 0.54 | — | la charge arrive à peine |
| +40 s | 46 % | 2 | 0.92 | dans 0.9 à 1.1 | rien : la tolérance l'arrête |
| +60 s | 72 % | 2 | 1.44 | `ceil(2 × 1.44)` = `ceil(2.88)` = 3 | décide de monter à 3 |
| +80 s | 58 % | 3 | 1.16 | `ceil(3 × 1.16)` = `ceil(3.48)` = 4 | décide de monter à 4 |
| +100 s | 44 % | 4 | 0.88 | `ceil(4 × 0.88)` = `ceil(3.52)` = 4 | reste à 4 |
| +120 s | 46 % | 4 | 0.92 | dans la tolérance | rien |
| +140 à +200 s | 38 % | 4 | 0.76 | `ceil(4 × 0.76)` = `ceil(3.04)` = 4 | reste à 4 |

Il y a trois choses à y voir. **Première** : la ligne de +40 secondes, avec 46 %, ne fait rien alors que la charge est déjà là. Ce n'est pas de la lenteur, c'est la tolérance : 46 % est 8 % en dessous de la cible, dans les 10 % que le contrôleur pardonne. **Deuxième** : à +60 s, l'utilisation est de 72 % avec 2 répliques et l'autoscaler décide de monter à 3 ; la ligne de +80 s en montre déjà 3, parce qu'entre une ligne et l'autre il s'écoule 20 secondes et que la décision a été prise dans l'intervalle. Le passage de 3 à 4 est séparé du premier d'environ 30 secondes (les événements ci-dessous disent il y a `2m37s` et il y a `2m7s`), probablement parce que les nouveaux Pods doivent naître et se mettre à travailler avant que leur consommation compte. **Troisième**, et c'est la plus instructive : de +140 à +200 secondes, l'utilisation reste à 38 % avec 4 répliques, un rapport de 0.76 qui est **hors** de la tolérance par le bas, et pourtant l'autoscaler ne descend pas. Le calcul explique pourquoi : `ceil(4 × 0.76)` vaut `ceil(3.04)`, c'est-à-dire 4. L'arrondi à l'entier supérieur maintient la quatrième réplique pour quatre centièmes. Le système s'est stabilisé tout seul : chaque nouvelle réplique a réparti la charge, la moyenne est descendue de 72 à 38 %, et avec cette moyenne quatre répliques sont le nombre que veut la formule. Le plafond de 6 n'a pas été touché.

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-4q7wh   1/1     Running   0          2m5s    10.244.2.13   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running   0          5m9s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-pchj4   1/1     Running   0          2m36s   10.244.1.14   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          5m7s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-4q7wh   18m          6Mi             
revisor-767bdf965b-5b6k9   19m          7Mi             
revisor-767bdf965b-pchj4   20m          7Mi             
revisor-767bdf965b-vcznx   20m          6Mi             
$ kubectl get hpa revisor -n revisor -o jsonpath='réplicas={.status.currentReplicas} deseadas={.status.desiredReplicas} cpu={.status.currentMetrics[0].resource.current.averageUtilization} % ({.status.currentMetrics[0].resource.current.averageValue}){"\n"}'
réplicas=4 deseadas=4 cpu=38 % (19m)
```

`kubectl top pods` montre la consommation réelle de chaque réplique à l'instant de la requête : 18, 19, 20 et 20 millicores. Face aux `50m` que chacune a demandés, cela fait 36 à 40 %. Et le HPA, avec sa propre requête, le dit en une ligne : `cpu=38 % (19m)` signifie « utilisation moyenne de 38 %, qui équivaut à 19 millicores par Pod ». Le calcul se fait manuellement : (18 + 19 + 20 + 20) ÷ 4 = 19.25 millicores, qui s'arrondit à `19m`, et 19 ÷ 50 vaut 0.38. La colonne `TARGETS` n'est pas un mystère : c'est cette division. `réplicas=4 deseadas=4` dit ce qu'on a déjà vu : ce qui existe est ce que veut la formule.

Les événements du HPA sont son journal, et racontent la même chose avec d'autres mots :

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                    From                       Message
  ----     ------                        ----                   ----                       -------
  Normal   SuccessfulRescale             5m54s                  horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             4m39s                  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             2m37s                  horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m7s                   horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
```

Lis-les de bas en haut, du plus ancien au plus récent. `SuccessfulRescale … New size: 2; reason: Current number of replicas below Spec.MinReplicas` est le premier ajustement, celui de 9.5 : le plancher. Les deux `Warning` qui suivent (`FailedGetResourceMetric`, `FailedComputeMetricsReplicas`) sont l'autoscaler qui dit qu'il n'a pas encore de métriques pour les nouveaux Pods : `unable to get metrics for resource cpu: no metrics returned from resource metrics API`. Ils sont normaux durant les premières secondes de vie d'un Pod, pendant que `metrics-server` fait sa première lecture ; le `(x3 over 5m39s)` dit qu'ils se sont répétés trois fois. Le suivant, `New size: 2; reason: All metrics below target`, n'appartient pas à cette charge : c'est le HPA qui ramène à 2 la troisième réplique que 9.5.4 avait demandée manuellement. Et les deux derniers, séparés de 30 secondes (il y a `2m37s` et il y a `2m7s`), sont les décisions de cette section : `New size: 3` et `New size: 4`, tous deux avec le motif `cpu resource utilization (percentage of request) above target` : la consommation, mesurée en pourcentage de la demande, au-dessus de la cible.

### 9.7 Sans charge, il redescend, après la fenêtre

On supprime le Job, et l'on regarde le HPA toutes les 20 secondes pendant 260 secondes. Ce que l'on va voir, c'est la fenêtre de réduction de 9.3.3 :

```text
$ kubectl delete -f carga.yaml
job.batch "carga" deleted from revisor namespace

(un renglón del HPA cada 20 s, durante 260 s; empieza a las 17:21:25)
[+ 20s] revisor   Deployment/revisor   cpu: 36%/50%   2     6     4     6m15s
[+ 40s] revisor   Deployment/revisor   cpu: 39%/50%   2     6     4     6m35s
[+ 60s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     6m55s
[+ 80s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     4     7m15s
[+100s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     7m35s
[+120s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     7m56s
[+140s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     8m16s
[+160s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m36s
[+180s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m56s
[+200s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     9m16s
[+220s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     2     9m36s
[+240s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     9m56s
[+260s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     10m
```

L'horloge se compte ainsi. On supprime le Job à la seconde 0, mais la lecture de +20 et celle de +40 restent hautes (36 % et 39 %) : le plus probable est que les Pods de charge mettent quelques secondes à se terminer, et `metrics-server` fait la moyenne de la consommation d'une fenêtre courte, non d'un instant. À +60 s la lecture est déjà de 3 %, et elle y reste. Avec 4 répliques et 3 % d'utilisation, le calcul est `ceil(4 × 0.06)` = `ceil(0.24)` = 1, mais le plancher est 2, donc ce que l'autoscaler *veut*, c'est 2. Et pourtant la colonne des répliques dit 4 à +60, +80 et +100, et ne passe à 2 qu'à la ligne de +120. Cette différence est la fenêtre de réduction de 60 secondes de 9.3.3 : pendant cette minute, le HPA n'utilise pas la recommandation d'aujourd'hui mais la plus haute des 60 dernières secondes, et la dernière recommandation de 4 répliques a été faite avec les lectures hautes du début.

Les événements donnent les heures avec plus de précision que le tableau. Pour les lire, il faut soustraire à partir du moment où l'on a lancé le `describe` (juste à la fin du tableau, environ 262 secondes après la suppression du Job) : `New size: 3` s'est produit il y a `2m54s`, c'est-à-dire vers +88 s, et `New size: 2` il y a `2m39s`, vers +103 s. Autrement dit, la réduction s'est faite en deux marches, de 4 à 3 puis, 15 secondes plus tard, de 3 à 2, à environ 50 ou 60 secondes de la dernière lecture haute. C'est ce qu'on attend d'une fenêtre : les recommandations du haut en sortent une par une. (Le tableau ne montre jamais la marche de 3 parce que la colonne `REPLICAS` du HPA se met à jour avec du retard par rapport au Deployment : c'est `status.currentReplicas`, que le HPA écrit à son propre tour, toutes les 15 s ; c'est pourquoi la ligne de +100 dit encore 4 alors que l'événement de passage à 3 date de +88. Quel nombre le HPA voit à chaque tour n'a pas été mesuré.)

Deux sorties de plus de `describe` complètent la lecture. Le tableau des conditions :

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Conditions:/,/Events:/p'
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScaledToZero    False   NotScaledToZero   the HPA controller did not scale the workload to zero
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
Events:
```

`ScalingLimited True TooFewReplicas: the desired replica count is less than the minimum replica count` est le HPA qui dit, en toutes lettres, ce qui a été calculé plus haut : ce que demande la formule (1) est **inférieur** au plancher (2), et c'est pourquoi il reste à 2. `ScalingActive True ValidMetricFound` dit qu'il peut bien calculer, c'est-à-dire que `metrics-server` continue de répondre. C'est le tableau qu'on regarde quand un HPA « ne fait rien » et qu'il faut savoir si c'est parce qu'il ne peut pas ou parce qu'il ne veut pas. Et la consommation réelle des deux répliques qui restent :

```text
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-5b6k9   1m           6Mi             
revisor-767bdf965b-vcznx   1m           5Mi             
```

Un millicore chacune : la charge est vraiment partie. Les événements complets, et les répliques qui restent :

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                   From                       Message
  ----     ------                        ----                  ----                       -------
  Normal   SuccessfulRescale             10m                   horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       9m17s (x3 over 10m)   horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  9m17s (x3 over 10m)   horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             7m                    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             6m30s                 horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m54s                 horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             2m39s (x2 over 9m2s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          9m33s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          9m31s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

L'événement `New size: 2; reason: All metrics below target` (« toutes les métriques sous la cible ») est la réduction. Et les deux répliques qui restent sont une sur chaque nœud de travail : la contrainte de répartition de 9.4 reste respectée après le retrait de deux Pods.

### 9.8 Qui commande les répliques

Le Deployment a `replicas` vide dans le fichier, mais il a quand même un nombre. Que se passe-t-il si quelqu'un d'autre le change manuellement ? On le teste avec `kubectl scale`, qui écrit le nombre de répliques dans le Deployment, le même champ que celui que le HPA écrit :

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

Quarante secondes plus tard, le Deployment a de nouveau 2 répliques, et le dernier événement du HPA le dit : `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. Le HPA n'a ni discuté ni demandé : à son tour suivant, il a vu que le Deployment avait moins de répliques que le plancher, et il l'a remis. Cela répond à une question pratique : **avec un HPA actif, `kubectl scale` ne sert pas à grand-chose**. Si tu descends sous le plancher, le HPA te corrige ; si tu montes au-dessus de ce que la charge demande, il te corrige à la baisse dès que la fenêtre est passée (9.5.4 l'a montré avec la troisième réplique : au bout de 75 secondes, le Deployment était déjà revenu à 2). Pour changer le nombre de répliques avec un HPA vivant, il faut changer le HPA : son `minReplicas` ou son `maxReplicas`. Qui veut deux propriétaires pour le même nombre a le problème de 9.3.4.

### 9.9 Mettre à jour et mesurer la coupure

#### 9.9.1 Comment un Deployment met à jour

Quand tu changes le modèle de Pods d'un Deployment (l'image, une variable, un `preStop`), on n'arrête pas toutes les répliques pour en démarrer d'autres. Le Deployment crée un `ReplicaSet` nouveau pour le nouveau modèle et déplace des répliques de l'ancien vers le nouveau, petit à petit. La documentation le décrit ainsi : on déclare le nouvel état en mettant à jour le modèle, « un nouveau ReplicaSet est créé, et le Deployment le fait monter en charge tout en réduisant l'ancien, en s'assurant que les Pods sont remplacés à un rythme contrôlé » ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). Deux nombres gouvernent ce rythme, et ils sont dans le Deployment depuis 9.5 :

- **`maxSurge`** : combien de Pods **en trop** peuvent être créés au-dessus du nombre souhaité pendant la mise à jour. La documentation : « le nombre maximal de Pods qui peuvent être créés au-dessus du nombre souhaité de Pods », en nombre ou en pourcentage ; la valeur par défaut est 25 %.
- **`maxUnavailable`** : combien de Pods peuvent être perdus, c'est-à-dire être **indisponibles**, pendant la mise à jour. Par défaut également 25 % ; la documentation précise qu'il ne peut pas valoir 0 si `maxSurge` vaut 0 (sinon, la mise à jour ne pourrait pas avancer).

Le `revisor` les fixe à `maxSurge: 1` et `maxUnavailable: 0`. Cela se lit comme une règle de sécurité : « ne retire pas une réplique qui répond tant qu'une nouvelle n'est pas prête à la remplacer ». Avec deux répliques, le Deployment crée **une** nouvelle réplique (la troisième, à cause du `maxSurge`), attend qu'elle soit prête, et seulement alors arrête une ancienne ; puis il recommence avec l'autre. À aucun moment il n'y a moins de deux répliques disponibles. C'est la partie de la mise à jour que Kubernetes sait faire tout seul, et c'est pourquoi `rollout status` imprime `1 out of 2 new replicas have been updated` : il compte les nouvelles.

Mais « disponible » est un mot du plan de contrôle. Ce que ressentent les requêtes est autre chose, et la différence s'appelle *situation de compétition* (race condition).

#### 9.9.2 La situation de compétition de l'arrêt

Quand le Deployment décide de retirer une ancienne réplique, cette réplique parcourt les étapes que la documentation du cycle de vie d'un Pod décrit comme le flux de terminaison ([Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)) :

1. Le Pod est marqué comme *en cours de terminaison* dans l'API, avec un délai (par défaut, 30 secondes ; celui du `revisor` est de 15).
2. Sur le nœud, le `kubelet` voit la marque et commence l'arrêt local : si le conteneur déclare un hook `preStop`, il l'exécute en premier. Ensuite, l'environnement d'exécution des conteneurs envoie le signal `TERM` au processus 1 de chaque conteneur, et le processus dispose de ce qui reste du délai pour se terminer. S'il est encore vivant à l'échéance, il reçoit `KILL`.
3. **« En même temps que le kubelet commence l'arrêt ordonné du Pod »**, le plan de contrôle évalue s'il faut le retirer des `EndpointSlice` des Services qui l'utilisent. La documentation ajoute un détail utile : une destination qui représente un Pod en cours d'arrêt n'est pas retirée immédiatement ; elle est marquée comme *en cours de terminaison* et avec `ready: false`, et les répartiteurs de charge cessent de l'utiliser pour le trafic normal.

L'étape 2 et l'étape 3 **ne s'attendent pas l'une l'autre**. C'est la situation de compétition. C'est l'observation de Phil Pearl de la scène d'ouverture, mesurée dans un autre contexte : l'avis d'arrêt arrive au processus au moment même où commence à circuler la nouvelle « retire-le de la liste », et la nouvelle doit voyager : du plan de contrôle aux `EndpointSlice`, de là à `kube-proxy` sur chaque nœud, et de là aux règles réseau de chaque nœud. Pendant qu'elle voyage, certains nœuds envoient encore des requêtes à l'ancien Pod. Si le processus a déjà fermé son port en recevant `TERM`, ces requêtes se heurtent à une porte fermée : `Connection refused`, ou au silence.

Le `revisor` fait bien sa part : en recevant `TERM`, il écrit `recibí terminated, apagando`, termine les requêtes qu'il a en cours et sort avec `apagado limpio`, avec un délai interne de 5 secondes (la Leçon 5 l'a mesuré). Mais « termine celles qu'il a en cours » n'inclut pas « continue d'accepter de nouvelles ». L'arrêt du `revisor` utilise `Server.Shutdown`, de la bibliothèque standard de Go, et la documentation de cette fonction dit comment elle travaille : « d'abord elle ferme tous les ports ouverts, puis ferme toutes les connexions inactives, puis attend » que les connexions actives se terminent ([Go, `net/http`](https://pkg.go.dev/net/http#Server.Shutdown)). Le port d'entrée se ferme **en premier**. Ce qui manque n'est pas un défaut du `revisor` ; c'est du temps pour que la nouvelle arrive.

Depuis que Pearl a écrit (2019), Kubernetes a ajouté aux `EndpointSlice` les conditions `serving` et `terminating`, et a permis à `kube-proxy` d'utiliser des destinations en cours de terminaison quand il n'en reste aucune de prête. Cela évite de perdre du trafic quand *toutes* les destinations sont en train de s'arrêter, mais ne change pas le fait que l'avis d'arrêt et le retrait des destinations voyagent par des chemins différents : la situation de compétition existe toujours et c'est celle que mesure cette leçon.

#### 9.9.3 La pause qui referme la situation de compétition : `preStop`

Un hook `preStop` s'exécute **avant** le signal `TERM`. Si tout ce qu'il fait est d'attendre quelques secondes, le processus continue de répondre normalement pendant cette attente, tandis que la nouvelle « retire-le de la liste » finit de voyager. Quand `TERM` arrive enfin, plus personne ne lui envoie de nouveau trafic. Le Pod du `revisor` n'a pas de shell (l'image est minimale, celle de la Leçon 5), donc le hook ne peut pas être un `sh -c "sleep 5"` ; Kubernetes fournit une action d'attente native :

```yaml
        lifecycle:
          preStop:
            sleep:
              seconds: 5
```

C'est tout ce qui a été ajouté au Deployment. Cinq secondes sont un choix, pas une loi : elles doivent suffire pour que la nouvelle atteigne tous les nœuds du cluster, et le temps que cela prend dépend de la taille et de la charge du cluster. Pearl, dans son cas, recommandait d'attendre plus longtemps que le temps que met le répartiteur de charge à se reprogrammer. La pause compte aussi dans le délai d'arrêt : la documentation dit que le temps du `preStop` fait partie du `terminationGracePeriodSeconds`, et que s'il en faut davantage, il faut augmenter le délai. C'est pourquoi le Deployment est passé de 10 à **15 secondes** : 5 de pause, jusqu'à 5 d'arrêt du `revisor`, et 5 de marge.

Tout cela reste de la théorie tant qu'on ne mesure pas. Mesurer exige un outil, et l'outil est un programme.

#### 9.9.4 L'interrogation périodique

La mesure doit remplir trois conditions : **compter** chaque requête, et non un échantillon ; **tourner pendant** le changement, ni avant ni après ; et **distinguer** quelle version a répondu et de quelle manière chaque échec s'est produit. C'est un **programme** : `sondeo.sh`.

```bash
#!/usr/bin/env bash
# sondeo.sh — Lección 9: mide cuántas peticiones se pierden mientras haces algo.
#
# Uso:  ./sondeo.sh DURACION PAUSA HILOS [argumentos de curl]
#   DURACION  segundos que dura el sondeo
#   PAUSA     segundos entre una petición y la siguiente, en cada hilo (0 = sin pausa)
#   HILOS     cuántos ciclos de peticiones corren a la vez
#   lo demás  se le pasa a curl (por ejemplo: --retry 3 --retry-all-errors)
#
# Las peticiones salen del Pod «depurar» (curl dentro del clúster) hacia
# http://revisor/salud, es decir, por el Service, como cualquier cliente de dentro.
# Cada petición deja una línea «segundo cuerpo código rc=salida-de-curl». Al final se cuenta.
#
# 🔴 Antes de hablarle al clúster comprueba que el contexto activo es
# kind-curso-k8s-l9 y, si no, se detiene.
set -euo pipefail

[ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo" >&2; exit 1; }
[ "$#" -ge 3 ] || { echo "uso: $0 DURACION PAUSA HILOS [argumentos de curl]" >&2; exit 2; }
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
EXTRA="$*"

# Este guion corre DENTRO de depurar (por la entrada estándar de kubectl exec).
kubectl exec -i -n revisor depurar -- sh -s -- "$DURACION" "$PAUSA" "$HILOS" $EXTRA <<'DENTRO' |
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
inicio=$(date +%s); fin=$((inicio + DURACION))
for h in $(seq 1 "$HILOS"); do
  (
    while [ "$(date +%s)" -lt "$fin" ]; do
      r=$(curl -s -m 2 -w ' %{http_code}' "$@" http://revisor/salud; echo " rc=$?")
      echo "$(( $(date +%s) - inicio )) $(echo $r)"
      [ "$PAUSA" = 0 ] || sleep "$PAUSA"
    done
  ) &
done
wait
DENTRO
awk '
  { rc = $NF; code = $(NF - 1); v = "-"
    if (match($0, /"version":"[0-9.]+"/)) v = substr($0, RSTART + 11, RLENGTH - 12)
    n++; cuenta[code " " rc " " v]++
    if (code != "200") { f++; if (nf < 40) { seg[nf++] = $1 } } }
  END {
    printf "peticiones=%d fallidas=%d\n", n, f
    for (k in cuenta) { split(k, a, " "); printf "  %5d  código %s  curl %s  versión %s\n", cuenta[k], a[1], a[2], a[3] }
    if (f > 0) { printf "  segundos (desde el inicio) de las primeras fallas:"; for (i = 0; i < nf; i++) printf " +%s", seg[i]; printf "\n" }
  }' | sort
```

On le lit par parties.

- **Où il tourne.** La boucle de requêtes tourne **à l'intérieur** du Pod `depurar` de la Leçon 3, celui de `curl`, auquel on l'envoie par l'entrée standard de `kubectl exec -i`. Ainsi les requêtes naissent à l'intérieur du cluster et passent par le Service, comme celles de n'importe quel client interne (par exemple, la tâche planifiée de la Leçon 8). **Portée :** cette mesure couvre le chemin d'un client à l'intérieur du cluster, c'est-à-dire le Service et `kube-proxy`. Elle ne passe pas par le Gateway d'Envoy, par où entreraient les utilisateurs de l'extérieur : cette pièce prend connaissance des changements de destinations de son côté et peut mettre plus ou moins de temps que `kube-proxy`, et ce chemin n'a pas été mesuré ici. Pearl a observé le problème sur un Ingress, non sur un Service, et dit que sur les Services la fenêtre est généralement courte. Le `<<'DENTRO'` avec des guillemets simples empêche ton shell d'interpréter quoi que ce soit de ce bloc : il est envoyé tel quel.
- **Ce que fait chaque fil.** Une boucle qui, tant que le temps n'est pas écoulé, demande `http://revisor/salud` avec `curl -s -m 2` : silencieux (`-s`) et avec un maximum de **2 secondes** par requête (`-m 2`). `-w ' %{http_code}'` lui ajoute à la fin le code HTTP, et l'`echo " rc=$?"` ajoute la sortie de `curl` lui-même. Ce second chiffre compte beaucoup, parce qu'il distingue **comment** une requête a échoué, et chaque mode raconte une histoire différente (plus bas).
- **Une ligne par requête.** `echo "$(( $(date +%s) - inicio )) $(echo $r)"` rassemble, sur une seule ligne, la seconde où cela s'est produit, le corps de la réponse, le code et la sortie de `curl`. Une ligne par requête évite que les lignes des quatre fils se mélangent : chaque `echo` est une seule écriture. (Le `$(echo $r)` sans guillemets aplatit les sauts de ligne du corps ; la réponse du `revisor` en comporte un à la fin, et sans cette astuce la ligne serait coupée en deux.)
- **Le décompte.** L'`awk` final regroupe par (code, sortie de `curl`, version qui a répondu) et imprime combien il y en a eu de chaque sorte, ainsi que les secondes des 40 premiers échecs. Un « échec » est tout code différent de `200`, y compris `000`, ce que `curl` imprime quand il n'a pas reçu de réponse HTTP.
- **Les deux modes d'échec que tu vas voir.** `curl` sort avec **7** quand il n'a pas pu se connecter (`Failed to connect`) : il est arrivé à une adresse où personne n'écoute, ou la connexion a été refusée. Il sort avec **28** quand le temps s'est écoulé (`-m 2`) sans réponse. Du premier on peut dire quelque chose de concret : quelqu'un a répondu « il n'y a personne ici ». Du second, seulement que personne n'a répondu à temps ; la cause peut se trouver dans la destination, dans le réseau ou dans le client lui-même.

Un avertissement d'honnêteté sur l'instrument : le Pod `depurar` a une limite de CPU de `100m`, et quatre boucles de `curl` sans pause l'occupent entièrement. Un client au plafond de son CPU peut retarder ses propres requêtes et produire des délais d'attente dépassés qui ne sont pas la faute du serveur. Ce qui est mesuré, c'est l'*ensemble* client, réseau et serveur. C'est pourquoi l'interrogation de référence de 9.9.5 passe avant tout changement : elle mesure le bruit que produit l'interrogation elle-même.

#### 9.9.5 D'abord, le bruit ; ensuite, la mise à jour avec `preStop`

Avant de rien changer, on mesure l'interrogation contre un cluster au repos, pour savoir combien de bruit elle produit à elle seule. Ce sont 15 secondes, avec quatre fils et sans pause. Vient ensuite la première mise à jour, celle du manifeste tel quel, avec le `preStop` en place. Le script lance l'interrogation en arrière-plan (`&`), attend 3 secondes qu'elle tourne déjà, change l'image de `1.6.0` à `1.6.1` et attend que le déploiement se termine :

```text
$ ./sondeo.sh 15 0 4
    172  código 200  curl rc=0  versión 1.6.0
peticiones=172 fallidas=0

$ ./sondeo.sh 45 0 4 &   # empieza a las 17:26:44
(pausa de 3 s: que el sondeo ya esté corriendo)

$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:1.6.1
deployment.apps/revisor image updated

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

# resultado del sondeo (A, con preStop):
     56  código 200  curl rc=0  versión 1.6.0
    416  código 200  curl rc=0  versión 1.6.1
peticiones=472 fallidas=0
```

`kubectl set image` change l'image du conteneur `revisor` à l'intérieur du Deployment `revisor`, sans toucher aucun fichier ; c'est le chemin court pour cette mesure (l'habitude de sécurité, plus bas, dit pourquoi ce n'est pas le chemin d'un vrai projet). Le `rollout status` compte au fur et à mesure : « 1 out of 2 new replicas have been updated » : sur les deux nouvelles répliques, une est déjà mise à jour ; puis « 1 old replicas are pending termination » : une ancienne n'est pas encore terminée. C'est la mécanique du `maxSurge: 1` de 9.9.1 vue de l'extérieur : d'abord une nouvelle réplique, puis on retire une ancienne, puis une autre nouvelle.

Le décompte se lit ainsi. L'**interrogation de référence** a fait 172 requêtes en 15 secondes, 172 avec le code `200` et toutes de la version `1.6.0`. Aucun échec : l'instrument, à ce moment-là, ne produit donc pas de bruit visible. Mais 172 requêtes, c'est peu pour estimer le bruit : un bruit de 0.24 % attendrait moins d'un échec sur 172 requêtes, si bien que cette ronde ne distingue pas « zéro » de « quelques pour mille ». La **mise à jour A** a fait 472 requêtes en 45 secondes : 56 ont été traitées par la version `1.6.0` (celles d'avant le remplacement et celles qui sont tombées sur d'anciennes répliques pendant son avancement) et 416 par la `1.6.1`, et aucune n'a échoué. À aucun moment il n'y a eu une ligne avec un autre code. Si c'était la seule ronde, le titre serait « zéro échec sur 472 ». Mais une ronde ne suffit pas, et le reste de la section existe pour dire pourquoi.

#### 9.9.6 La même expérience, sans la pause

Pour savoir ce qu'évite le `preStop`, il faut le retirer et mesurer la même chose. On le retire avec un patch de type JSON qui supprime le champ `lifecycle` du premier conteneur :

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/lifecycle"}]'
deployment.apps/revisor patched
```

`op: remove` avec un `path` signifie « supprime ce champ ». Le patch change le modèle de Pods, il provoque donc son propre remplacement ; le script attend qu'il se termine avec `rollout status` et vérifie que le hook n'est plus là. La vérification est la suivante :

```text
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].lifecycle}{"|"}{.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
|15
```

La sortie est `|15` : avant la barre, le contenu de `lifecycle`, qui est **vide** ; après, le `terminationGracePeriodSeconds`, 15. (Le `|` est écrit par la commande elle-même entre les deux champs, pour qu'on puisse voir le vide.) Sans hook, le Pod reçoit `TERM` à l'instant même où commence son arrêt.

Avec ce modèle, on répète la mise à jour trois fois, en allant et venant entre les deux versions, pour que chaque ronde change d'image et qu'il y ait un vrai remplacement :

```text
# resultado del sondeo (B, ronda 1, sin preStop, hacia 1.6.0):
      2  código 000  curl rc=7  versión -
      7  código 000  curl rc=28  versión -
     51  código 200  curl rc=0  versión 1.6.1
    403  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +7 +7 +9 +9 +9 +9 +30
peticiones=463 fallidas=9

# resultado del sondeo (B, ronda 2, sin preStop, hacia 1.6.1):
      1  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
     47  código 200  curl rc=0  versión 1.6.0
    465  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +5 +7 +7 +8 +9 +9 +10 +10 +16
peticiones=521 fallidas=9

# resultado del sondeo (B, ronda 3, sin preStop, hacia 1.6.0):
      3  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
    105  código 200  curl rc=0  versión 1.6.1
    469  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +5 +7 +7 +8 +8 +9 +10 +10 +10
peticiones=585 fallidas=11
```

Il y a de nouvelles lignes, et chacune raconte quelque chose de différent :

- `código 000  curl rc=7` : le code HTTP `000` est ce que `curl` imprime quand il **n'a pas reçu de réponse HTTP**, et `rc=7` est sa propre sortie : « Failed to connect to host ». Quelqu'un a répondu « il n'y a personne ici » à la connexion. C'est la signature qu'on attendrait de la situation de compétition de 9.9.2 : une requête est arrivée, par le Service, sur une réplique qui avait déjà fermé son port.
- `código 000  curl rc=28` : `rc=28` est « Operation timeout » : les 2 secondes de `-m 2` se sont écoulées sans réponse. Personne n'a dit « non » ; personne n'a rien dit. Cela arrive quand le paquet arrive à une adresse qui n'existe plus (le Pod a déjà disparu et le réseau le désigne encore) ou quand quelqu'un met trop longtemps à répondre. Le délai dépassé a donc plusieurs causes possibles, et l'une d'elles est la même situation de compétition.
- La ligne **« segundos (desde el inicio) de las primeras fallas »** donne la seconde, comptée depuis le démarrage de l'interrogation, où *s'est terminée* chaque requête échouée ; un échec `curl 28` a été envoyé environ 2 secondes plus tôt. Dans les trois rondes sans pause, les échecs tombent entre `+5` et `+10` secondes, sauf un ou deux plus tardifs. C'est le moment où les anciennes répliques s'arrêtent : le `set image` a été envoyé 3 secondes après le lancement de l'interrogation.

La somme des trois rondes sans `preStop` : 463 + 521 + 585 = 1 569 requêtes, dont 9 + 9 + 11 = 29 ont échoué. Six étaient des `curl 7` (2, 1 et 3) et 23 des `curl 28` (7, 8 et 8).

#### 9.9.7 Avec la pause de nouveau, trois rondes de plus

On réapplique le dossier, qui porte le `preStop`, et l'on répète la mise à jour trois fois de plus :

```text
$ kubectl apply -k . | grep -E 'deployment|horizontal'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
horizontalpodautoscaler.autoscaling/revisor unchanged
```

```text
# resultado del sondeo (C, ronda 1, con preStop, hacia 1.6.1):
      4  código 000  curl rc=28  versión -
     57  código 200  curl rc=0  versión 1.6.0
    471  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +2 +2 +2 +2
peticiones=532 fallidas=4

# resultado del sondeo (C, ronda 2, con preStop, hacia 1.6.0):
     97  código 200  curl rc=0  versión 1.6.1
    515  código 200  curl rc=0  versión 1.6.0
peticiones=612 fallidas=0

# resultado del sondeo (C, ronda 3, con preStop, hacia 1.6.1):
      1  código 000  curl rc=28  versión -
     72  código 200  curl rc=0  versión 1.6.0
    360  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +25
peticiones=433 fallidas=1
```

#### 9.9.8 Ce que disent les sept rondes, et ce qu'elles ne disent pas

En rassemblant toutes les rondes de l'exécution :

| Variante | Rondes | Requêtes | Échecs | `curl 7` | `curl 28` |
|---|---|---|---|---|---|
| Interrogation de référence, sans rien toucher | 1 | 172 | 0 | 0 | 0 |
| **Avec** `preStop` (A et C1 à C3) | 4 | 2 049 | 5 | 0 | 5 |
| **Sans** `preStop` (B1 à B3) | 3 | 1 569 | 29 | 6 | 23 |

Avec `preStop`, 5 échecs sur 2 049 requêtes (0.24 % ; intervalle à 95 %, méthode de Wilson : 0.10 à 0.57 %). Sans lui, 29 sur 1 569 (1.85 % ; 1.29 à 2.64 %). Les intervalles ne se chevauchent pas, mais ils supposent des requêtes indépendantes, et ici elles ne le sont pas (quatre fils qui partagent un client, et les quatre échecs de la ronde C1 datent du même instant) ; lis-les comme une indication de l'ordre de grandeur, non comme une garantie. Ce que ces chiffres permettent de dire, avec prudence :

1. **La connexion refusée n'est apparue que sans la pause.** Les six connexions refusées (`curl 7`) se sont produites dans les rondes sans `preStop`, et aucune dans les quatre rondes avec lui. C'est l'effet que prédit 9.9.2 : sans pause, une réplique ferme son port alors que quelqu'un lui envoie encore des requêtes. Avec la pause sont restés cinq délais dépassés (`curl 28`) que cette mesure ne permet d'attribuer ni au bruit ni à une situation de compétition résiduelle : ce code a les deux causes possibles.
2. **Les échecs se regroupent là où on les attend.** Dans les rondes sans pause, ils tombent dans une fenêtre d'environ cinq ou six secondes, celle qui suit le `set image`. Dans les rondes avec pause, il n'y a pas d'échecs dans cette fenêtre : les quatre de la ronde C1 se sont produits à la même seconde, `+2`, c'est-à-dire quand l'interrogation démarrait à peine (le `set image` est envoyé 3 secondes après son lancement), et l'unique échec de la ronde C3 est tombé à `+25`, la mise à jour étant déjà en cours ; nous n'avons pas enregistré le moment où chaque Pod s'est arrêté, nous ne pouvons donc pas le rattacher à un moment précis. Que les quatre échecs de C1 soient simultanés oriente vers un démarrage lent du client (quatre fils qui commencent en même temps dans un Pod limité à `100m` de CPU sur une machine partagée et chargée), mais la mesure ne le démontre pas : c'est une hypothèse, non une conclusion.
3. **Zéro n'est pas ce qui a été mesuré.** La ronde A, la première, a donné 0 sur 472 ; les trois autres rondes avec pause ont donné 4, 0 et 1. Une leçon qui dirait « avec `preStop`, aucune requête n'est perdue » aurait choisi la ronde A et aurait menti. Ce que la mesure soutient bel et bien : la pause a réduit les échecs de la fenêtre de mise à jour à un petit nombre qui n'est pas zéro non plus, et les rondes avec pause ont donné ensemble 5 échecs sur 2 049 requêtes. Nous ne savons pas quelle part vient du bruit du client : l'interrogation de référence, de 172 requêtes sans échec, est trop courte pour l'estimer.
4. **Ce n'est pas une preuve statistique.** Ce sont sept rondes de 45 secondes, sur une machine partagée très chargée, avec un client qui partage ses cœurs avec le cluster qu'il mesure. Les rondes n'ont pas été alternées (d'abord la A, puis les trois sans pause et ensuite les trois avec pause), si bien que la variante et le moment vont ensemble, et que la charge de la machine a changé pendant le travail ; pour séparer les deux effets, il faudrait alterner avec et sans pause. Les chiffres servent à comparer des variantes au sein de cette exécution ; non à promettre un pourcentage sur ton cluster. Ce qui est transférable, c'est la méthode : compter toutes les requêtes, distinguer comment elles échouent, répéter, et ne pas croire une seule ronde.

La pause de 5 secondes referme donc la partie de la situation de compétition qui peut se refermer avec une pause. Ce n'est pas une garantie : la documentation des hooks elle-même dit que leur remise est « au moins une fois » et qu'il n'y a pas d'autre promesse. Et il existe une source d'échecs qu'aucune pause ne touche : la panne d'un nœud, qui vient en 9.12.

### 9.10 L'historique et le retour en arrière

#### 9.10.1 Un ReplicaSet par version

Chaque fois que le modèle du Deployment change, le Deployment crée un `ReplicaSet` nouveau, et l'ancien reste là, avec zéro réplique, au lieu d'être supprimé. Chacun de ces ReplicaSet conserve le modèle d'une version : son image, ses probes, son `preStop`. C'est ce qui rend possible le retour en arrière, et la documentation le dit sans détour : « la configuration de chaque révision du Deployment est stockée dans ses ReplicaSet ; par conséquent, une fois qu'un ancien ReplicaSet est supprimé, on perd la capacité de revenir à cette révision ». Combien sont conservés, c'est `.spec.revisionHistoryLimit` qui le décide, et sa valeur par défaut est 10.

Tu peux mettre un commentaire sur chaque révision avec une annotation, `kubernetes.io/change-cause`, que `rollout history` montre dans une colonne. La documentation dit qu'on peut la poser avec `kubectl annotate`, en éditant le manifeste ou avec des outils qui le font automatiquement, et que le drapeau `--record`, qui la remplissait auparavant, est obsolète et va être retiré. On l'applique à la révision actuelle :

```text
$ kubectl annotate deployment/revisor -n revisor kubernetes.io/change-cause='ronda de pruebas de la Leccion 9' --overwrite
deployment.apps/revisor annotated

$ kubectl rollout history deployment/revisor -n revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
3         <none>
8         <none>
9         <none>
12        <none>
13        ronda de pruebas de la Leccion 9
```

La colonne `CHANGE-CAUSE` n'a du texte que sur la révision actuelle, parce que l'annotation est copiée sur une révision au moment où cette révision est créée, et que les autres existaient déjà. Les numéros de révision n'ont pas à être consécutifs : ici ils sont 1, 3, 8, 9, 12 et 13. Chaque fois que le modèle redevient identique à celui d'un ReplicaSet qui existait déjà, le Deployment **réutilise** ce ReplicaSet et lui donne le numéro de révision le plus récent, de sorte que les révisions intermédiaires devenues « la même » disparaissent de la liste. Les ReplicaSet confirment le compte :

```text
$ kubectl get replicasets -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-574b5b6c4c   0         0         0       16m
revisor-5978745747   0         0         0       4m33s
revisor-5cc67d8975   2         2         2       5m33s
revisor-67b97d67c9   0         0         0       18m
revisor-767bdf965b   0         0         0       16m
revisor-7f759cd976   0         0         0       4m51s
(imagen actual: curso-docker-revisor:1.6.1)
```

Six ReplicaSet, un pour chaque modèle différent qui est passé par le Deployment dans cette exécution : avec `preStop` et sans lui, avec une version ou une autre, avec `nodeTaintsPolicy` et sans lui. Un seul a des répliques. Les cinq autres sont l'historique.

#### 9.10.2 `rollout undo`

`rollout undo` ramène le Deployment à la révision précédente. Il n'exécute rien de spécial : il écrit dans le Deployment le modèle du ReplicaSet précédent, et le Deployment fait le même remplacement progressif que d'habitude, mais à l'envers.

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back
```

L'avertissement (`Warning: resource deployments/revisor was previously managed with 'kubectl apply'…`) mérite d'être lu en entier. Il dit que le retour en arrière **ne met pas à jour** l'annotation `last-applied-configuration`, celle qui conserve le dernier état que tu as appliqué avec `kubectl apply`, et que cela « peut provoquer un comportement inattendu lors de futurs `kubectl apply` ». Traduit : ton fichier dit une chose, le cluster est revenu à une autre, et le prochain `apply -k .` va faire sa propre comparaison et peut défaire ton retour en arrière. `rollout undo` est un outil pour éteindre un incendie ; la vraie réparation est de modifier le fichier et de l'appliquer. La documentation de `kubectl` le suggère avec les mêmes mots à la fin de l'avertissement : « envisage d'utiliser `kubectl apply` avec ta configuration précédente ».

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

#### 9.10.3 Quand cela se termine vraiment

`rollout status` a dit `successfully rolled out`. Est-ce qu'il ne reste plus rien de la version que tu as retirée ? On le regarde avec la colonne nécessaire, celle que le script porte dans tous ses listages de Pods :

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-5cc67d8975-qbzsl   curso-docker-revisor:1.6.1   curso-k8s-l9-worker2   2026-10-21T23:32:40Z
revisor-5cc67d8975-ttszb   curso-docker-revisor:1.6.1   curso-k8s-l9-worker    2026-10-21T23:32:37Z
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
```

Regarde la colonne `BORRANDOSE` : c'est le champ `deletionTimestamp` du Pod, l'heure (en UTC) à laquelle le cluster lui a ordonné de se terminer. Les Pods de `1.6.1` l'ont : ils sont en train de se terminer, ils sont encore dans leur pause de `preStop` (le délai de 15 secondes n'est pas encore échu), et ils **répondent encore**. Les Pods de `1.6.0` ne l'ont pas : ce sont les vivants d'aujourd'hui. `rollout status` s'est terminé parce que le Deployment remplit déjà ce qu'on lui a demandé (les répliques souhaitées de la bonne version sont prêtes et les mauvaises sont déjà marquées pour se terminer), et non parce que le dernier mauvais Pod a fini de mourir. Les requêtes le montrent :

```text
$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}
```

Quatre des six réponses disent `1.6.1` : **la version que tu viens de retirer**. Seules deux disent `1.6.0`, celle qui est restée. Si tu avais conclu à ce moment-là que le `undo` n'avait pas fonctionné, tu te serais trompé. C'est la même situation de compétition que 9.9.2, vue depuis le retour en arrière : le retrait des destinations met un peu de temps à parvenir à tous. Douze secondes plus tard, la pause étant échue :

```text
(espera de 12 s: que termine el preStop de los Pods viejos)

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>

$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}
```

Il ne reste plus aucune ligne avec `BORRANDOSE`, et les six réponses disent `1.6.0`. Un `rollout undo` qui semble ne pas avoir fonctionné parce qu'une requête a reçu la réponse de l'ancienne version, c'est le plus souvent cela : on a conclu trop tôt. La règle : avant de décider que le retour en arrière a échoué, regarde `deletionTimestamp` et attends que le délai soit échu.

Pour voir ce que conservait une révision, `rollout history` accepte `--revision=N`, et montre le modèle complet de cette version, image comprise. Le script demande la première :

```text
$ kubectl rollout history deployment/revisor -n revisor --revision=1 | head -14
deployment.apps/revisor with revision #1
Pod Template:
  Labels:	app=revisor
	pod-template-hash=67b97d67c9
  Service Account:	revisor
  Containers:
   revisor:
    Image:	curso-docker-revisor:1.6.0
    Port:	8080/TCP (http)
    Host Port:	0/TCP (http)
    Limits:
      cpu:	200m
      memory:	64Mi
    Requests:
```

C'est le modèle avec lequel est né le Deployment dans le dossier de la Leçon 8 : image `1.6.0`, sans `preStop`. (La sortie est coupée à 14 lignes avec `head` pour qu'elle tienne ; le reste, ce sont les `Requests`, les probes et les volumes.) Pour y revenir, il faudrait dire `kubectl rollout undo deployment/revisor --to-revision=1`, la forme que donne la documentation.

Et pour boucler la boucle avec la discipline de l'habitude de sécurité, le script réapplique le dossier, de sorte que le cluster et les fichiers soient identiques :

```text
$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
```

`unchanged` : le modèle laissé par le `undo` est identique à celui du fichier, et `apply` n'a rien à faire.

#### 9.10.4 L'erreur : une image qui n'existe pas

L'une des raisons les plus courantes d'un retour en arrière est une mise à jour qui a mal tourné, et pas toujours à cause d'un défaut du programme mais d'une faute de frappe : le tag de l'image est mal écrit, ou pointe vers une version que personne n'a publiée. On la provoque exprès, avec un script à part qui monte son propre cluster minimal : **`fig09_02.imagen-rota.sh`**, un **programme** qui échoue exprès. Il crée `curso-k8s-l9` avec seulement ce qui est nécessaire (le `revisor` et le service de test, sans MetalLB ni Envoy Gateway, qui n'interviennent pas), met deux répliques, lance l'interrogation de 9.9.4 et change l'image pour `curso-docker-revisor:9.9.9`, un tag qui n'existe pas. Sa sortie est `fig09_02.imagen-rota.salida.txt`. On le lance ainsi, depuis le dossier de la leçon :

```bash
./fig09_02.imagen-rota.sh > fig09_02.imagen-rota.salida.txt 2>&1
```

Il ne porte pas de `ctx &&` devant parce qu'il crée son propre cluster et que le contexte n'existe pas encore ; il a ses propres garde-fous (kubeconfig temporaire, contexte vérifié avant chaque `kubectl`, suppression du cluster à la sortie). Si tu as déjà un `curso-k8s-l9` vivant, le script s'arrête : il ne touche pas au tien. Il prend environ quatre minutes. La commande qui provoque l'erreur est celle-ci, et elle se passe bien :

```text
$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:9.9.9
deployment.apps/revisor image updated
```

`image updated`, sans protester : le `kube-apiserver` ne sait pas si l'image existe. C'est la même situation que le `selector` mal écrit de la Leçon 3 : un nom valide qui ne pointe sur rien. Ce qui suit se lit dans l'ordre, comme n'importe quelle panne.

**D'abord, `rollout status`.**

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]
(espera de 10 s: que el kubelet registre el fallo de descarga)
```

Il reste à « 1 out of 2 new replicas have been updated » et, le délai de 40 secondes qu'on lui avait donné étant épuisé, il sort avec `error: timed out waiting for the condition` et le code 1. Remarque qu'il **ne dit pas ce qui ne va pas** : il dit seulement que cela ne se termine pas. `rollout status` attend, et la cause doit être cherchée ailleurs. Sans `--timeout`, il attendrait jusqu'à ce que le Deployment déclare qu'il ne progresse pas : le champ `.spec.progressDeadlineSeconds`, qui vaut 600 secondes par défaut, après lesquelles le Deployment ajoute une condition `Progressing` à `False` avec la raison `ProgressDeadlineExceeded` ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). La documentation avertit que Kubernetes **ne fait rien** avec un Deployment bloqué sinon le signaler : il ne le défait pas tout seul.

**Deuxièmement, les Pods.**

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS         RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-6586779dc4-96dfn   0/1     ErrImagePull   0          50s   10.244.2.5   curso-k8s-l9-worker    <none>           <none>
revisor-85f8668b64-2tjx4   1/1     Running        0          60s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running        0          60s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>
```

Trois Pods, non deux. Les deux anciens (`85f8668b64`) sont toujours `1/1 Running`. Le nouveau (`6586779dc4`) est en `0/1 ErrImagePull` : le nœud a essayé de télécharger l'image, ne l'a pas trouvée, et il n'y a pas de conteneur à démarrer. C'est le même état que dans la Leçon 2, avec la même sortie, et il se lit de la même façon : l'étape suivante est le `describe`.

**Troisièmement, les événements du nouveau Pod.**

```text
$ kubectl describe pod revisor-6586779dc4-96dfn -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  50s                default-scheduler  Successfully assigned revisor/revisor-6586779dc4-96dfn to curso-k8s-l9-worker
  Normal   Pulling    13s (x3 over 50s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:9.9.9": failed to pull and unpack image "docker.io/library/curso-docker-revisor:9.9.9": failed to resolve reference "docker.io/library/curso-docker-revisor:9.9.9": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
  Normal   BackOff    2s (x3 over 49s)   kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     2s (x3 over 49s)   kubelet            spec.containers{revisor}: Error: ImagePullBackOff
```

L'événement `Failed to pull image "curso-docker-revisor:9.9.9"` dit, avec plus de texte qu'il n'en tient dans la page, qu'il n'a pas pu résoudre `docker.io/library/curso-docker-revisor:9.9.9` : le nœud a cherché le tag sur Docker Hub, où il n'existe pas, parce que l'image du cours ne vit que sur ta machine. Puis `ErrImagePull`, `BackOff` et `ImagePullBackOff` : le `kubelet` réessaie avec des attentes de plus en plus longues. `(x3 over 50s)` dit combien de fois il a essayé.

**Quatrièmement, ce que dit le Deployment.**

```text
$ kubectl get deployment revisor -n revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   2/2     1            2           60s
```

`READY 2/2`, `UP-TO-DATE 1`, `AVAILABLE 2`. « Prêtes : 2 sur 2 ; à jour : 1 ; disponibles : 2 ». Le Deployment a fait exactement ce que `maxSurge: 1` et `maxUnavailable: 0` lui demandaient : il a créé **une** nouvelle réplique, a attendu qu'elle soit prête pour pouvoir retirer une ancienne, et comme elle ne l'a jamais été, il n'en a retiré aucune. Les deux anciennes continuent de servir.

**Et l'interrogation périodique, qui a tourné pendant tout le blocage :**

```text
# resultado del sondeo (durante toda la actualización rota):
    811  código 200  curl rc=0  versión 1.6.0
peticiones=811 fallidas=0
```

Dans cette ronde, aucune des 811 requêtes n'a échoué : toutes ont été traitées par la version `1.6.0`, l'ancienne, parce qu'aucune ancienne réplique n'a été retirée. C'est une seule ronde, mais ce qui rend le résultat possible est mécanique, non statistique : avec `maxUnavailable: 0`, le Deployment ne retire pas une ancienne réplique sans en avoir une nouvelle prête, et la nouvelle n'est jamais arrivée à l'être. Voilà l'utilité concrète de `maxUnavailable: 0` : une mise à jour cassée reste bloquée *sans retirer ce qui fonctionne*. Attention à ce qu'elle ne mesure pas : comme aucune ancienne réplique n'a jamais été arrêtée, elle ne prouve rien non plus sur la situation de compétition de l'arrêt. Avec la valeur par défaut de 25 %, un Deployment de quatre répliques s'autoriserait à en retirer une avant d'avoir la nouvelle prête, et un faux pas de ce genre pourrait se remarquer.

**La correction** est la cause, et l'outil est celui de 9.10.2 :

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-85f8668b64-2tjx4   1/1     Running   0          65s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running   0          65s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curso-docker-revisor:1.6.0
```

Le `undo` ramène le modèle au précédent, le Pod qui ne démarrait pas disparaît, et l'image revient à `curso-docker-revisor:1.6.0`. (Ici, aucun Pod de la mauvaise version n'a continué de répondre, comme en 9.10.3 : il n'est jamais devenu prêt.) Dans un vrai projet, la correction définitive est de réparer le tag dans le fichier et de l'appliquer ; le `undo` est le premier secours.

### 9.11 Maintenance d'un nœud : le budget d'interruptions

#### 9.11.1 Deux sortes d'interruption

Tout ce qui retire un Pod à un service n'est pas équivalent. La documentation de Kubernetes sépare les **interruptions involontaires**, qui sont des « cas inévitables » comme « une panne matérielle de la machine qui porte le nœud », des **volontaires**, qui sont les actions de la personne qui exploite le système : la personne propriétaire de l'application, ou l'administrateur du cluster, qui peut entre autres « vider un nœud pour le réparer ou le mettre à jour » ([Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)). La différence compte parce que sur les volontaires on peut **négocier** : le cluster te laisse dire combien tu es prêt à perdre. Sur les involontaires, non : personne ne demande à un disque s'il peut tomber en panne.

L'outil de la négociation est le **PodDisruptionBudget** (PDB), le second objet de `escalado.yaml`. La documentation définit ses deux formes : `minAvailable`, le nombre de Pods qui doivent rester disponibles après une éviction, et `maxUnavailable`, le nombre qui peut devenir indisponible ; on déclare l'une ou l'autre, pas les deux. Celui du `revisor` dit `minAvailable: 1` : avec deux répliques, l'une peut partir, et l'autre doit rester. On lit son état :

```text
$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     17m
```

`ALLOWED DISRUPTIONS 1` est le compte que le cluster tient à cet instant : deux répliques saines, moins une qui doit rester debout, laissent une qui peut être perdue. Si l'une des deux cesse d'être saine, ce nombre tombe à 0, et la prochaine éviction est refusée.

#### 9.11.2 Comment on vide un nœud

`kubectl drain` est l'ordre « ce nœud part en maintenance ». Il fait deux choses, dans cet ordre : il le marque comme non planifiable (`cordon` : plus aucun nouveau Pod n'y arrive) et il évince un par un les Pods qui y tournent. La documentation ([Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)) explique qu'une éviction sûre permet aux conteneurs de se terminer avec ordre et « respecte les PodDisruptionBudget que tu as spécifiés ». La discipline qui se cache derrière, selon la page des interruptions : `kubectl` demande chaque éviction par l'API d'éviction ; cette demande peut être refusée temporairement, et l'outil réessaie celles qui échouent jusqu'à ce que tous les Pods du nœud se terminent ou qu'expire un délai que tu configures (`--timeout`). La commande du script porte deux drapeaux. `--ignore-daemonsets` : la documentation dit qu'il est nécessaire quand il y a des Pods d'un DaemonSet (comme les `speaker` de MetalLB), qui sont laissés où ils sont et retirés quand le nœud quitte le cluster. `--delete-emptydir-data` : il accepte de perdre les données des volumes `emptyDir`, comme le `/datos` du `revisor`, qui meurt de toute façon avec le Pod.

#### 9.11.3 L'erreur : un budget sans marge

On la provoque avec `fig09_01.pdb-estricto.yaml`, un **programme** qui échoue exprès : le même PDB, avec `minAvailable: 2`.

```yaml
# fig09_01.pdb-estricto.yaml — FALLA A PROPÓSITO: un PodDisruptionBudget que no deja
# perder NI UNA réplica (minAvailable: 2 con solo 2 réplicas). Mientras exista,
# «kubectl drain» no puede desalojar ningún Pod del revisor y se queda reintentando.
# Se deshace con: kubectl apply -k .   (escalado.yaml trae el PDB bueno)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: revisor
```

On l'applique **dans l'espace de noms du `revisor`**, avec `-n revisor` : le fichier ne déclare pas d'espace de noms, et un `apply -f` sans `-n` crée l'objet là où pointe le contexte (l'espace `default`), qui ne protège personne. C'est une erreur facile à commettre, et elle a été commise en préparant cette leçon : oublier le `-n revisor`. Le cluster ne se plaint pas : le message était `poddisruptionbudget.policy/revisor created` au lieu de `configured`, le bon budget de l'espace `revisor` est resté intact (`ALLOWED DISRUPTIONS 1`) et le `drain` est passé sans entraves, comme si l'expérience n'existait pas. L'indice était dans le mot : `created` au lieu de `configured`. On lit le message de l'`apply`, et l'on vérifie avec `get pdb -n revisor`.

```text
$ kubectl apply -n revisor -f fig09_01.pdb-estricto.yaml
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   2               N/A               0                     17m
(el nodo que se va a vaciar: curso-k8s-l9-worker2)
```

`configured` : l'objet existait déjà et dit maintenant autre chose. `MIN AVAILABLE 2` et, le chiffre qui compte, `ALLOWED DISRUPTIONS 0`. Avec deux répliques et l'obligation d'en conserver deux, aucune ne peut être perdue. On essaie maintenant de vider un nœud, avec un délai court pour que le script n'attende pas indéfiniment :

```text
$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=30s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/prueba-6899c74865-cgzkw
evicting pod metallb-system/controller-76f4cf76b7-m9mlh
evicting pod revisor/revisor-767bdf965b-58sd9
evicting pod envoy-gateway-system/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/controller-76f4cf76b7-m9mlh evicted
pod/prueba-6899c74865-cgzkw evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
There are pending pods in node "curso-k8s-l9-worker2" when an error occurred: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
pod/revisor-767bdf965b-58sd9
error: unable to drain node "curso-k8s-l9-worker2" due to error: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s, continuing command...
There are pending nodes to be drained:
 curso-k8s-l9-worker2
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
[código de salida: 1]
```

Cela se lit comme une pièce de théâtre. Le nœud est cordonné (`cordoned`). Des évictions sont demandées pour les Pods qui y vivent, et partent ceux qui ne sont pas protégés : `prueba`, le `controller` de MetalLB et le Pod d'Envoy qui dessert le point d'entrée se terminent (`evicted`). Et alors apparaît, encore et encore, toutes les 5 secondes :

`error when evicting pods/"revisor-…" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.`

« Impossible d'évincer le Pod car cela violerait le budget d'interruptions ». Le cluster ne s'est pas trompé : il a fait exactement ce qu'on lui demandait. Au bout de 30 secondes, le délai du `drain` expire (`global timeout reached: 30s`) et la commande sort avec le code 1. Regarde dans quel état est resté le nœud :

```text
$ kubectl get nodes
NAME                         STATUS                     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready                      control-plane   26m   v1.37.0
curso-k8s-l9-worker          Ready                      <none>          26m   v1.37.0
curso-k8s-l9-worker2         Ready,SchedulingDisabled   <none>          26m   v1.37.0
```

`Ready,SchedulingDisabled` : il est toujours sain mais **cordonné**. Un `drain` interrompu laisse le nœud dans cet état jusqu'à ce que quelqu'un le remette avec `uncordon` ; sinon, aucun nouveau Pod n'y tombe, et c'est l'une des façons de manquer de capacité sans que rien soit cassé. Le script le remet :

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
```

La correction consiste à réappliquer le dossier, qui porte le bon PDB (`minAvailable: 1`), et à répéter le `drain`. Maintenant `ALLOWED DISRUPTIONS` revient à 1 et l'éviction du `revisor` passe :

```text
# --- La corrección: el PDB de la carpeta ---

$ kubectl apply -k . | grep -E 'poddisruption'
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     18m

$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=120s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/revisor-767bdf965b-58sd9
pod/revisor-767bdf965b-58sd9 evicted
node/curso-k8s-l9-worker2 drained
```

`evicted` dès la première tentative, sans nouvelle tentative ni erreurs. Mais regarde où sont restées les répliques :

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          6s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          109s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

**Les deux répliques se sont retrouvées sur le même nœud**, `curso-k8s-l9-worker`. L'éviction du `revisor` est passée (le PDB permettait d'en perdre une), mais la nouvelle réplique est née sur le seul nœud qui pouvait la recevoir, et maintenant les deux vivent ensemble : la perte de ce nœud emporterait tout le service. Ce que `Honor` explique très probablement : un nœud cordonné porte le taint `node.kubernetes.io/unschedulable`, et avec `nodeTaintsPolicy: Honor` les nœuds marqués (pour lesquels le Pod n'a pas de tolérance) sortent du compte de la répartition. Tant que `worker2` était cordonné, le seul domaine était `worker`, avec une asymétrie de 0, et la répartition a permis les deux répliques là. La contrainte a été respectée ; il n'y avait pas d'autre endroit.

#### 9.11.4 Rétablir la répartition

On remet le nœud en service et l'on attend de voir si le cluster s'en charge tout seul :

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
(espera de 30 s: ¿vuelve el reparto por sí solo?)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          37s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          2m20s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

Non. Les deux répliques restent ensemble : rien ne les a déplacées. C'est exactement la limitation de 9.4.4 : la contrainte de répartition est évaluée **au moment de planifier un Pod**, pas après, et la documentation dit qu'il n'y a aucune garantie qu'elle continue d'être respectée quand des Pods sont retirés, et recommande des outils comme le *Descheduler* pour rééquilibrer. Sans rien installer, le remède est de provoquer une nouvelle planification, et `kubectl rollout restart` le fait : il remplace les répliques avec la même procédure progressive qu'une mise à jour, et chaque nouveau Pod est planifié avec la contrainte en place.

```text
$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          12s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          10s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

De nouveau une réplique sur chaque nœud de travail. La répartition se maintient grâce à une habitude, non à une configuration : après une maintenance, on regarde `-o wide`.

### 9.12 Un nœud qui tombe en panne

Jusqu'ici tout était *planifié* : une mise à jour que tu lances, une maintenance que tu demandes. Reste l'autre cas : la machine qui s'arrête sans prévenir. C'est la troisième question du directeur. On y répond en arrêtant exprès l'un des nœuds de travail, en mesurant, et en demandant au cluster quand il s'en est aperçu.

#### 9.12.1 Ce que sait le cluster, et quand

Un nœud en panne n'envoie pas d'avertissement : il cesse d'envoyer des *battements de cœur* (heartbeats). La documentation de « Node Status » décrit deux formes de battement : les mises à jour du `.status` du nœud et des objets `Lease` (baux) dans l'espace de noms `kube-node-lease`, un par nœud ; le `kubelet` renouvelle le sien toutes les 10 secondes par défaut ([Node Status](https://kubernetes.io/docs/reference/node/node-status/)). Quand les battements cessent d'arriver, le contrôleur de nœuds attend un délai, `node-monitor-grace-period`, avant de déclarer quoi que ce soit. La condition `Ready` du nœud passe à `Unknown` si le contrôleur de nœuds « n'a pas eu de nouvelles du nœud depuis `node-monitor-grace-period` (par défaut, **50 secondes**) ». C'est le délai de détection, et c'est le cœur de la section.

Pendant que ces 50 secondes s'écoulent, le plan de contrôle croit que le nœud va bien. Ses Pods figurent comme `Running` et `Ready`, leurs adresses restent dans les `EndpointSlice`, et les Services continuent de leur répartir des requêtes. Quand le délai expire, deux choses distinctes se produisent :

1. Le nœud passe à `NotReady` (`Unknown`), et les Pods qui y vivaient cessent de compter comme prêts ; leurs adresses sont marquées `ready: false` dans les `EndpointSlice`, et le Service cesse de les utiliser. **Ici se termine la fenêtre de panne pour le trafic.**
2. Le nœud reçoit le taint `node.kubernetes.io/unreachable` avec l'effet `NoExecute`. Les Pods qui y vivent ont, d'origine, une tolérance à ce taint de **300 secondes** : la documentation de « Taints and Tolerations » dit que Kubernetes ajoute automatiquement les tolérances de `not-ready` et `unreachable` avec `tolerationSeconds=300`, et que c'est pourquoi les Pods « restent liés aux nœuds pendant 5 minutes après la détection d'un de ces problèmes ». Ce délai passé, les Pods sont évincés et le ReplicaSet crée des remplaçants sur un autre nœud. **Ici se termine la fenêtre de capacité**, qui dure bien plus longtemps que celle de panne.

Il convient de séparer les deux fenêtres parce qu'on les confond. Celle de **panne** (requêtes perdues) dure depuis la chute du nœud jusqu'à ce que le cluster s'en aperçoive : environ 50 secondes. Celle de **capacité** (service avec une réplique de moins) dure 5 minutes de plus, jusqu'à la naissance des remplaçants. Cette leçon mesure la première, celle que ressentent tes utilisateurs. La seconde n'a pas été mesurée, parce que le nœud est rallumé avant qu'elle n'expire.

#### 9.12.2 L'expérience

Le script choisit le nœud qu'il va arrêter avec une condition : ce doit être un nœud qui **porte une réplique** du `revisor` et qui **n'est pas** celui où vit le Pod `depurar`, d'où partent les requêtes (si l'on arrêtait le nœud du client, la mesure mourrait avec lui). Avec deux répliques réparties, l'un des deux nœuds de travail remplit la condition. Il lance ensuite **deux** interrogations à la fois, avec une requête toutes les 2 secondes et un seul fil, pendant 100 secondes :

- la première, telle quelle : `./sondeo.sh 100 2 1` ;
- la seconde, avec des nouvelles tentatives du client : `./sondeo.sh 100 2 1 --retry 3 --retry-all-errors`.

`--retry 3` demande à `curl` de réessayer jusqu'à 3 fois une requête qui a échoué, et `--retry-all-errors` étend « échoué » à n'importe quelle erreur, délais dépassés compris ; le manuel de `curl` décrit l'attente entre les tentatives : d'abord une seconde, puis il « double le temps d'attente » à chaque fois. Le manuel appelle `--retry-all-errors` le « marteau » des nouvelles tentatives et déconseille de l'utiliser par défaut ; ici c'est une expérience contrôlée contre un service dont on sait qu'il peut être répété sans risque (`GET /salud`). Avec une requête idempotente (qui peut être répétée sans effets), les nouvelles tentatives sont inoffensives ; avec une qui ne l'est pas, elles seraient un risque.

Dix secondes après le lancement des interrogations, `docker stop` arrête le conteneur du nœud, ce qui est ce que kind a de plus proche de « la machine est tombée en panne » : le `kubelet` et tout ce qui tourne à l'intérieur cessent d'exister d'un coup. La leçon attend 25 secondes et pose deux questions : comment le cluster voit-il le nœud, et que disent les `EndpointSlice` des adresses du `revisor`.

```text
$ ./sondeo.sh 100 2 1 &                                     # sin reintentos, empieza a las 17:34:53
$ ./sondeo.sh 100 2 1 --retry 3 --retry-all-errors &       # con reintentos
(pausa de 10 s: ambos sondeos ya corren)

$ docker stop curso-k8s-l9-worker
curso-k8s-l9-worker
(nodo apagado a las 17:35:04)
(espera de 25 s: el nodo ya no contesta, pero el clúster todavía no lo sabe)
[+ 25s desde docker stop] curso-k8s-l9-worker Ready
```

À 25 secondes d'arrêt, le nœud dit encore `Ready`. Le cluster ne sait rien. Et la preuve qu'il ne le sait toujours pas se trouve dans les destinations :

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=true nodo=curso-k8s-l9-worker
(el nodo pasó a NotReady a los 57 s de docker stop)
```

Les deux destinations du `revisor` figurent `ready=true`, **y compris celle qui vit sur le nœud arrêté** (`nodo=curso-k8s-l9-worker`). Toute requête que le Service répartit vers cette adresse va vers un Pod qui n'existe plus. Voilà la cause des échecs, écrite en une ligne.

Le script interroge toutes les 3 secondes l'état du nœud jusqu'à le voir `NotReady`, puis il redemande :

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=false nodo=curso-k8s-l9-worker
```

Le nœud est passé à `NotReady` 57 secondes après l'arrêt (le délai de la documentation est de 50 ; le reste s'explique par jusqu'à 5 secondes du cycle du contrôleur, `node-monitor-period`, et 3 de l'interrogation du script ; en outre, le dernier battement du nœud a pu précéder l'arrêt). Et maintenant la destination du nœud en panne figure `ready=false` : le cluster a cessé de lui répartir du trafic. C'est le moment où se termine la fenêtre de panne.

#### 9.12.3 Ce qu'ont mesuré les interrogations

```text
# resultado SIN reintentos (los segundos cuentan desde el inicio del sondeo; docker stop fue en +10):
      7  código 000  curl rc=28  versión -
     35  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +21 +25 +29 +38 +42 +60 +64
peticiones=42 fallidas=7

# resultado CON reintentos de curl:
      1  código 000  curl rc=28  versión -
     31  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +37
peticiones=32 fallidas=1
```

Une précision sur l'en-tête : le script note « +10 », qui est la pause qu'il avait programmée avant d'arrêter le nœud. L'heure imprimée dit que le nœud s'est arrêté 11 secondes après le lancement de l'interrogation, parce que `docker stop` a pris près d'une seconde. Les calculs qui suivent utilisent 11.

L'interrogation **sans nouvelles tentatives** a fait 42 requêtes en 100 secondes, et non les 50 qu'un rythme d'une toutes les 2 secondes permettrait, parce que chaque requête qui échoue occupe les 2 secondes entières de son délai d'attente en plus de la pause. 7 ont échoué, toutes avec `curl 28` (délai dépassé, non connexion refusée : la destination n'existait plus). Les secondes des échecs, comptées depuis le début de l'interrogation, sont `+21 +25 +29 +38 +42 +60 +64`. Comme `docker stop` a été lancé à la seconde 11 de l'interrogation, en soustrayant on obtient combien de temps chacun est survenu après l'arrêt : de 10 à 53 secondes. Le dernier échec, à 53 secondes de l'arrêt, tombe juste avant l'observation de `NotReady` à 57 : les sept échecs sont tombés entre 10 et 53 secondes après l'arrêt (mesuré à la fin de chaque requête). Qu'on n'en ait pas vu davantage ne prouve pas que le Service avait déjà cessé d'utiliser la destination morte : avec une requête toutes les 2 secondes et la moitié d'entre elles tombant, selon le modèle, sur la réplique vivante, quelques-unes de suite peuvent réussir sans que rien n'ait changé. Ce qui a bien été mesuré, c'est que la destination est passée à `ready=false` quand le nœud a figuré `NotReady`, à 57 secondes.

Cela fait 7 échecs sur 42, soit 17 %. Ce chiffre mélange la fenêtre de panne avec le reste des 100 secondes de l'interrogation, il ne dit donc pas « le service échoue une fois sur six » : il dit ce qui s'est passé dans cette expérience. Ce qui explique les échecs, c'est que, pendant la fenêtre (jusqu'à 57 secondes, jusqu'à ce que la destination passe à `ready=false`), **l'une des deux destinations du Service était morte**, et le Service répartit entre ses destinations sans savoir laquelle est morte, si bien qu'une partie des requêtes de cette période allait atterrir sur la réplique qui n'existait plus. Avec deux répliques et un nœud mort, cette part serait d'environ la moitié ; avec quatre répliques réparties, elle serait d'environ un quart ; avec dix, d'un dixième. Cette proportion (une réplique sur N) est un modèle, non une mesure de cette exécution : ce qui a été mesuré, c'est 7 sur 42, mais c'est ce qui explique pourquoi « plus de répliques réparties » raccourcit les dégâts sans raccourcir la durée.

L'interrogation **avec nouvelles tentatives** a fait 32 requêtes et a été plus lente (chaque nouvelle tentative attend 1, 2 et 4 secondes avant d'essayer de nouveau). Une a échoué, à 37 secondes, sur 32 : un échec contre sept pour l'autre interrogation, en échange de quelques réponses plus longues. C'est une seule ronde, de petite taille et avec moins de requêtes que l'autre : elle suggère que les nouvelles tentatives aident, mais ne suffit pas pour promettre combien de requêtes sont récupérées. C'est le second levier : les **nouvelles tentatives côté client**. Elles fonctionnent parce que la fois suivante où `curl` demande, le Service peut choisir la réplique vivante, et elles ne fonctionnent pas si la destination est la même (par exemple, avec une seule réplique).

Ensuite, l'état du cluster au moment de rallumer le nœud :

```text
$ kubectl get nodes
NAME                         STATUS     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready      control-plane   29m   v1.37.0
curso-k8s-l9-worker          NotReady   <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready      <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          114s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          112s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

Le nœud étant `NotReady`, les deux Pods du `revisor` figurent toujours `Running`, y compris celui du nœud arrêté : le cluster ne les évince pas encore, parce que la tolérance de 300 secondes n'a pas expiré. Et il ne les évincera pas : le nœud est rallumé.

```text
$ docker start curso-k8s-l9-worker
curso-k8s-l9-worker

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready    control-plane   29m   v1.37.0
curso-k8s-l9-worker          Ready    <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready    <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS      AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0             2m16s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   1 (21s ago)   2m14s   10.244.1.4    curso-k8s-l9-worker    <none>           <none>
```

Le nœud revient à `Ready`, et le Pod qui y vivait est toujours là : le conteneur a redémarré (`RESTARTS 1`), aucun autre Pod n'a été créé, et il a changé d'adresse réseau (`10.244.1.4` au lieu de `10.244.1.33`), mais c'est le même Pod. Dans cette exécution, le nœud est revenu bien avant les 300 secondes et ses Pods sont restés.

#### 9.12.4 Ce qui raccourcit la fenêtre et ce qui ne la raccourcit pas

| Levier | Raccourcit-il ? | Pourquoi |
|---|---|---|
| **Plus de répliques, réparties entre les nœuds** | raccourcit les *dégâts*, non la durée | avec N répliques réparties, le modèle de répartition attend une requête sur N sur la réplique morte (calcul, non mesure) |
| **Nouvelles tentatives côté client** | oui, pour les requêtes qu'on peut répéter sans risque | la seconde fois peut tomber sur une réplique vivante (mesuré plus haut) |
| **Diminuer `node-monitor-grace-period`** (dans le plan de contrôle) | oui, au prix de fausses alertes | le cluster déclare en panne un nœud qui n'a fait que prendre du retard |
| **Les readiness probes** | non | elles sont exécutées par le `kubelet` du nœud en panne lui-même, qui ne rapporte plus rien |
| **`tolerationSeconds`** | non | il décide quand les Pods sont remplacés, non quand ils cessent de recevoir du trafic |

Les deux dernières lignes sont celles auxquelles on croit le plus et qui fonctionnent le moins, et c'est pourquoi l'Exercice 4 les met à l'épreuve. Une readiness probe (celle de la Leçon 5) sort un Pod des destinations du Service quand elle échoue, mais celui qui pose la question est le `kubelet` de *ce* nœud. Si le nœud entier est arrêté, il n'y a pas de `kubelet` pour poser la question ni pour rapporter ; le cluster ne peut qu'attendre que le délai de détection expire. Et `tolerationSeconds` est le délai de grâce avant d'évincer les Pods d'un nœud déjà déclaré `unreachable`, c'est-à-dire un compte qui commence *après* la détection : plus il est court, plus tôt les Pods sont remplacés, mais ils ne sortent pas plus tôt les destinations mortes du Service.

Diminuer `node-monitor-grace-period` est le seul levier qui s'attaque à la durée, et il coûte des fausses alertes (il ne faut pas trop le baisser : il doit être plusieurs fois supérieur à la fréquence à laquelle le `kubelet` rapporte ; vérifie le drapeau dans la référence du `kube-controller-manager` de ta version) : un nœud avec dix secondes de retard réseau serait déclaré en panne, ses Pods seraient marqués non prêts et le Service cesserait de les utiliser sans raison. C'est un drapeau du `kube-controller-manager`, qui dans kind vit à l'intérieur du conteneur du nœud de contrôle ; ce n'est pas quelque chose qu'on change avec `kubectl`, et cette leçon n'y touche pas.

Le directeur a sa réponse, avec ce qui a été mesuré dans cette exécution : **avec deux répliques, sept requêtes sur 42 (17 %) ont été perdues pendant la fenêtre d'un nœud en panne**, dont le dernier échec est tombé 53 secondes après l'arrêt et qui s'est terminée quand la destination est passée à `ready=false`, à 57. Par la répartition du Service, nous attendrions qu'environ la moitié des requêtes de cette fenêtre tombe sur la réplique morte (c'est un calcul, non une mesure). Avec des nouvelles tentatives côté client, il y a eu un échec sur 32, mais une seule ronde ne suffit pas pour promettre combien sont récupérées. Quand le nœud revient, le cluster se recompose tout seul.

#### 9.12.5 Après l'expérience : le `<unknown>` de l'autoscaler

La dernière question de l'exécution est de savoir si tout est resté comme les fichiers le disent, et la réponse comporte un détail qui appartient à cette leçon :

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           24m
deployment.apps/revisor   2/2     2            2           24m

NAME                                          REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          21m

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     21m
```

Avec `sin diferencias con los archivos`, le cluster et le dossier coïncident : tout ce qui a été fait avec des commandes (`set image`, `patch`, `scale`, `rollout undo`) a été défait ou réappliqué. Et dans le HPA, `TARGETS` dit `cpu: <unknown>/50%`. C'est le même mot qui apparaît parfois dans les premières secondes de 9.5.2, et il faut savoir le lire, car c'est la question la plus courante sur les autoscalers : **`<unknown>` signifie « je ne sais pas combien consomment les Pods »**, et il a trois causes distinctes :

1. **`metrics-server` ne répond pas.** C'est la cause de 9.2. On le vérifie avec `kubectl get apiservice v1beta1.metrics.k8s.io` : s'il dit `False`, c'est le compteur.
2. **Les Pods n'ont pas de `requests` de CPU.** Sans eux, il n'y a rien par rapport à quoi calculer le pourcentage, et la documentation dit que l'autoscaler ne fera rien avec cette métrique. On le vérifie avec `kubectl describe pod`.
3. **Les Pods sont nouveaux et n'ont pas encore leur première lecture.** Cela se voit dans les événements du HPA (`kubectl describe hpa`) sous la forme `FailedGetResourceMetric … no metrics returned from resource metrics API`, le même avertissement que 9.6 a montré dans les premières secondes des nouveaux Pods, et il disparaît tout seul.

Dans cette conclusion, la troisième est la candidate : l'exécution a rallumé le nœud arrêté, a attendu 20 secondes et a capturé l'état ; le Pod du `revisor` de ce nœud avait redémarré un instant avant (`RESTARTS 1`) et n'avait pas encore de lecture. La mesure ne distingue pas cette cause de la première, parce qu'on n'a pas interrogé l'`APIService` à ce moment-là ni vérifié sur quel nœud tournait `metrics-server` (s'il tournait sur le nœud arrêté, ce serait la première) ; ce qu'on peut dire, c'est comment les distinguer. Si c'était la troisième, il suffirait d'attendre quelques secondes ; sinon, le `<unknown>` reste. L'habitude : devant un `<unknown>`, d'abord `get apiservice`, puis `describe pod` en cherchant les `requests`, puis l'horloge.

## L'habitude de sécurité de la leçon : des limites à la mise à l'échelle, et des mises à jour qui ne font pas tomber le service

Le tableau des habitudes du cours assigne à cette leçon une phrase en deux moitiés : **des limites à la mise à l'échelle** et **les mises à jour ne font pas tomber le service**. On les vérifie avec le cluster sous les yeux.

**Des limites à la mise à l'échelle.** Un autoscaler convertit de la *charge* en *ressources* : plus de requêtes, plus de répliques, plus de CPU et de mémoire réservés. C'est exactement ce qu'on veut face à un lundi à 9 h 00, et c'est exactement ce qu'un attaquant, ou une erreur, peut exploiter. Un client qui envoie des requêtes en boucle (le Job `carga` de la leçon en est un, à petite échelle) coûte au service de plus en plus de répliques. Sans plafond, la limite est posée par le cluster entier, et un service mal élevé laisse les autres sans ressources. Il y a trois freins en couches, du plus proche au plus général :

1. **Le plafond de l'autoscaler lui-même.** `maxReplicas: 6`. Avec les `requests` de la Leçon 5, six répliques réservent `6 × 50m = 300m` de CPU et `6 × 32Mi = 192Mi` de mémoire, un nombre que tu peux écrire et discuter, au lieu de « ce qu'il y aura ». Dans l'exécution de cette leçon, l'autoscaler n'a pas atteint ce plafond : la charge d'un Job de `curl` en boucle s'est contenue à quatre répliques. Le plafond est un garde-fou ; on n'a pas prouvé qu'il arrête quoi que ce soit, et cette distinction compte.
2. **Qui peut générer la charge.** Le réseau fermé de la Leçon 7 ne laisse passer vers le `revisor` que les Pods portant l'étiquette `acceso-revisor: permitido` et les Envoy du point d'entrée. Le Job `carga` porte cette étiquette exprès ; sans elle, ses requêtes n'arriveraient pas et l'autoscaler ne verrait rien. Qui contrôle le point d'entrée contrôle qui peut faire monter la facture de CPU.
3. **Le budget de l'espace de noms.** Il existe des objets (`ResourceQuota`, `LimitRange`) qui posent un plafond **total** de CPU, de mémoire et de nombre de Pods à tout un espace de noms, de sorte qu'un autoscaler mal configuré ne puisse pas le dépasser même si son propre plafond est élevé. La Leçon 5 les a nommés et les a laissés hors du cours ; dans un cluster partagé, ils sont la couche qui protège réellement les voisins.

Il y a en outre une habitude pour qui met à l'échelle avec `metrics-server` : le drapeau `--kubelet-insecure-tls` de 9.2 n'existe que dans ce laboratoire. Il convient de l'écrire là où le verra qui héritera du fichier (le commentaire de `metrics-server/kustomization.yaml` le dit), parce qu'un drapeau de laboratoire copié dans un autre cluster est une faille de sécurité qui a l'air d'une configuration.

**Les mises à jour ne font pas tomber le service.** Ce qui a été fait pour y arriver, et dans quelle mesure on y arrive, est le contenu de 9.9 et de 9.11 :

| Pièce | Ce qu'elle empêche | Où c'est mesuré |
|---|---|---|
| `maxUnavailable: 0` avec `maxSurge: 1` | qu'il y ait moins de répliques que souhaité pendant le remplacement | 9.9 |
| `preStop` avec `sleep` | que des requêtes arrivent sur une réplique qui a déjà fermé sa porte | 9.9 |
| `PodDisruptionBudget` | qu'une maintenance volontaire retire plus de répliques que le service n'en supporte | 9.11 |
| répartition avec `topologySpreadConstraints` | qu'une seule machine concentre toutes les répliques | 9.4 et 9.11 |

Remarque que la phrase du tableau des habitudes dit « ne font pas tomber », non « ne perdent rien ». Ce qui a été mesuré en 9.9 dit combien on perd avec et sans chaque pièce, et ce chiffre, avec son incertitude, est ce qu'on remet à qui demande. Une promesse de « zéro » que personne n'a mesurée est pire qu'un petit chiffre qui, lui, l'a été.

Et une discipline de plus : la leçon met à jour avec `kubectl set image` et `kubectl patch`, des commandes *impératives*, parce que ce sont le chemin court pour mesurer. Dans un vrai projet, le changement s'écrit dans le fichier, se relit et s'applique avec `kubectl apply -k .`, pour que ce qui tourne dans le cluster et ce qui est dans le dépôt soient identiques. La fin de l'exécution le vérifie avec `kubectl diff -k .` : « sin diferencias con los archivos ».

## Les erreurs courantes

**Laisser `replicas` dans le Deployment que gouverne un HPA.** Chaque `apply` rend au nombre la valeur du fichier et défait ce que l'autoscaler a décidé. On le retire du manifeste.

**Un HPA sur des Pods sans `requests` de CPU.** Le pourcentage se mesure par rapport aux `requests` ; sans eux, l'autoscaler n'a rien pour calculer et ne fait rien.

**Copier `--kubelet-insecure-tls` dans un vrai cluster.** C'est la sortie rapide pour que `metrics-server` démarre dans un laboratoire. Dans un cluster où il y a plus de monde, la solution est que les certificats des `kubelet` soient signés par l'autorité du cluster.

**Croire que le HPA réagit à une différence de quelques points.** Dans les 10 % de tolérance, il ne fait rien. Et à la baisse, il n'utilise pas ce qu'il voit aujourd'hui, mais ce qu'il a recommandé de plus haut dans la fenêtre.

**Une cible de CPU très haute (90 %).** Quand l'autoscaler réagit, le service est déjà saturé, et les nouvelles répliques mettent du temps à naître.

**`ScheduleAnyway` quand ce qu'il faut est une garantie.** C'est une préférence : le planificateur la rompt s'il ne trouve pas de meilleur endroit.

**Une répartition par topologie sans `nodeTaintsPolicy: Honor` dans un cluster avec un nœud de contrôle marqué par un taint.** Elle fonctionne avec deux répliques et laisse la troisième en `Pending`.

**Croire que la répartition se maintient toute seule.** Elle s'applique au moment de planifier un Pod ; une maintenance peut laisser les répliques ensemble et rien ne les sépare sans un remplacement.

**Mettre à jour sans pause avant l'arrêt.** Une ancienne réplique ferme sa porte alors que le réseau lui envoie encore des requêtes.

**Conclure « sans échecs » à partir d'une seule interrogation courte.** Une ronde sans échecs ne démontre pas qu'il n'y en a pas ; avec trois rondes de chaque variante, ce qui a été mesuré en 9.9 montre que les échecs apparaissent et disparaissent.

**Croire que `rollout status` signifie « il ne reste plus rien d'ancien qui réponde ».** Il se termine quand le Deployment remplit ce qu'on lui a demandé (les répliques souhaitées de la nouvelle version sont prêtes), non quand le dernier ancien Pod a fini son `preStop`. On regarde `deletionTimestamp`.

**Un `PodDisruptionBudget` qui ne laisse perdre aucune réplique.** Le `drain` reste à réessayer et la maintenance n'avance pas. Le budget doit laisser de la marge.

**Un PDB sans son espace de noms.** Un objet avec `-f` et sans `-n` est créé là où pointe le contexte, et un PDB dans le mauvais espace de noms ne protège personne. On lit le message `created` et l'on vérifie avec `get pdb -n revisor`.

**Compter sur les probes pour raccourcir la panne d'un nœud.** Elles sont exécutées par le `kubelet` du nœud en panne ; elles ne peuvent rien rapporter.

**Faire confiance au fait que le cluster s'aperçoit immédiatement d'une panne.** Il y a une fenêtre de détection, et les requêtes qui y tombent sont perdues.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre et avec l'état dans lequel il est resté après 9.12. Avant chaque commande qui change quelque chose, `ctx` doit réussir. `correr.sh` parcourt la leçon, non les exercices ; leurs solutions citent ce qui a été mesuré dans la leçon ou le calculent, et le disent. **Avant** d'exécuter ou de calculer chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes mots.

### Exercice 1 — La formule, calculée manuellement

Avec la cible de 50 %, `minReplicas: 2` et `maxReplicas: 6`, calcule ce que ferait l'autoscaler dans chaque cas, et dis si la tolérance l'arrête :

a) 2 répliques avec une utilisation moyenne de 63 %.
b) 3 répliques avec une utilisation moyenne de 46 %.
c) 4 répliques avec une utilisation moyenne de 90 %.
d) 6 répliques avec une utilisation moyenne de 20 %, une minute après que l'utilisation a baissé.

Ensuite compare (a) et (b) avec la colonne `TARGETS` et les événements de 9.6.

### Exercice 2 — Qui commande

Sans regarder 9.8, écris quel nombre de répliques tu crois que le Deployment aura 40 secondes après `kubectl scale deployment/revisor -n revisor --replicas=1`, et à quel événement du HPA tu t'en rendras compte. Exécute la commande et vérifie.

### Exercice 3 — Ta propre interrogation périodique

Exécute `./sondeo.sh 45 0 4` pendant que tu fais `kubectl set image` entre `1.6.0` et `1.6.1`, trois fois avec le `preStop` du dossier. Note par ronde les requêtes, les échecs et le type de chaque échec (`curl 7` ou `curl 28`). Retire le hook avec `kubectl patch` (la commande de 9.9.6) et recommence. Compare tes totaux avec ceux de la leçon et explique, en trois phrases, pourquoi les tiens peuvent différer et quelle conclusion ils soutiennent bel et bien. Pour séparer l'effet de la pause de l'effet du moment, alterne les variantes (une ronde avec pause, une sans, une autre avec…) au lieu de faire toutes celles de l'une puis toutes celles de l'autre. À la fin, reviens à `apply -k .`.

### Exercice 4 — Défends la décision

Un collègue dit : « les readiness probes sortent déjà une réplique en panne du Service, et `tolerationSeconds` est le délai de détection d'un nœud, donc en le baissant à 5 secondes la coupure du nœud est finie ». En cinq phrases au maximum, dis-lui ce qui se passe réellement quand un nœud s'arrête sans prévenir, ce que mesure chacun de ces deux réglages, et ce qui raccourcirait vraiment la fenêtre et à quel prix.

## Solutions

### Solution 1

C'est du calcul, non de la mesure, sauf là où c'est dit.

a) **2 répliques, 63 %.** Rapport 1.26, hors de 0.9 à 1.1. `ceil(2 × 1.26)` = `ceil(2.52)` = **3**. Il monte à 3. (En 9.6, avec 72 % et 2 répliques, il a demandé 3 par la même règle.)

b) **3 répliques, 46 %.** Rapport 0.92 : dans la tolérance. **Il ne fait rien.** Même si la tolérance n'existait pas, `ceil(3 × 0.92)` = `ceil(2.76)` = 3, le même nombre. (En 9.6, avec 4 répliques et 46 %, il est resté à 4 : la même situation.)

c) **4 répliques, 90 %.** Rapport 1.8. `ceil(4 × 1.8)` = `ceil(7.2)` = 8. Mais `maxReplicas` vaut 6, donc le HPA reste à **6**. Il le noterait dans la condition `ScalingLimited`, la même que 9.7 montre pour le plancher, ici pour le plafond ; ce cas n'a pas été mesuré dans cette exécution parce que la charge n'a jamais atteint le plafond. C'est le cas du plafond : sans `maxReplicas`, ce serait 8.

d) **6 répliques, 20 %, une minute après la baisse de l'utilisation.** Rapport 0.4. `ceil(6 × 0.4)` = `ceil(2.4)` = 3. Le calcul dit 3, mais la fenêtre de 60 secondes dit qu'on utilise la recommandation **la plus haute** des 60 dernières secondes : si, il y a 59 secondes, la recommandation était de 6, elle reste à 6 un instant de plus. Il descend quand cette recommandation sort de la fenêtre.

### Solution 2

Mesuré dans `correr.salida.txt` :

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

**Deux répliques, de nouveau.** Le Deployment est revenu à 2/2 au bout de 40 secondes, et le dernier événement du HPA le dit : `New size: 2; reason: Current number of replicas below Spec.MinReplicas`, d'il y a `33s`. Le `kubectl scale` a baissé le champ `spec.replicas` à 1 ; le HPA, à son tour suivant, a vu que 1 était inférieur au plancher de 2 et l'a corrigé. Avec un autoscaler vivant, le nombre de répliques est le sien. Ce qu'on change, c'est le HPA.

### Solution 3

Cela dépend de ta machine, et c'est en cela que consiste l'exercice. Les totaux de cette exécution sont en 9.9.8 : avec `preStop`, 5 échecs sur 2 049 requêtes en quatre rondes, tous `curl 28` ; sans lui, 29 sur 1 569 en trois rondes, dont 6 `curl 7`. Ce qu'on peut dire, et ce qu'on ne peut pas :

- **Tes totaux ne vont pas coïncider avec ceux d'ici**, parce qu'ils dépendent du CPU qu'a eu ton client, de la charge de ta machine et du nombre de requêtes que chaque ronde a pu faire (ici il y a eu des rondes de 433 et de 612 requêtes dans le même temps).
- **Ce qui doit se répéter**, c'est la forme : les échecs sans pause se regroupent dans les secondes qui suivent le `set image`, il y a des connexions refusées (`curl 7`) seulement sans pause, et avec pause les rondes donnent peu d'échecs, avec des rondes à zéro et d'autres avec quelques-uns isolés.
- **Ce que ta mesure ne soutient pas** : un pourcentage exact, ni la phrase « avec `preStop`, rien n'est perdu ». Si l'une de tes rondes avec pause a donné zéro, cela ne signifie pas que la pause élimine les échecs ; cela signifie que cette ronde n'en a vu aucun.
- Si tes rondes avec pause ne se distinguent pas des rondes sans elle, la conclusion honnête est que cette machine, avec ce client, n'a pas la résolution pour voir la différence. Non que la pause ne serve à rien.

### Solution 4

Une réponse possible : « Quand un nœud s'arrête sans prévenir, le cluster ne s'en aperçoit pas immédiatement : il attend `node-monitor-grace-period`, 50 secondes par défaut, que le nœud rapporte. Pendant ce temps, les destinations des Pods du nœud restent marquées comme prêtes et le Service leur répartit des requêtes qui sont perdues ; dans l'exécution de la leçon, 7 sur 42 ont été perdues, et le dernier échec est survenu 53 secondes après l'arrêt. Les readiness probes n'aident pas parce qu'elles sont exécutées par le `kubelet` de ce nœud, qui est arrêté. `tolerationSeconds`, de 300 secondes par défaut, est le délai que le cluster attend *après* avoir déclaré le nœud injoignable avant de remplacer ses Pods ; le baisser remplace donc les Pods plus tôt mais ne sort pas plus tôt les destinations mortes du Service. Ce qui aide vraiment, c'est d'avoir plus de répliques réparties (par la répartition, on peut s'attendre à ce qu'une requête sur N tombe sur la morte), des nouvelles tentatives côté client pour les requêtes qu'on peut répéter, et, au prix de fausses alertes, de baisser `node-monitor-grace-period` dans le plan de contrôle. »

## Supprimer le cluster

Quand tu as fini les exercices, supprime le cluster de la leçon. Avec lui partent MetalLB, Envoy Gateway, `metrics-server`, le Pod `depurar` et tout le reste :

```text
$ kind delete cluster --name curso-k8s-l9
Deleting cluster "curso-k8s-l9" ...
Deleted nodes: ["curso-k8s-l9-control-plane" "curso-k8s-l9-worker2" "curso-k8s-l9-worker"]
(borrar tardó 2 s)

$ kind get clusters | grep -c curso-k8s-l9
0
```

Ensuite, supprime les `token.txt` et le dossier temporaire du `kubeconfig`, qui conserve l'identifiant d'administrateur du cluster que tu viens de supprimer. Le `rm -rf` est dangereux si la variable est vide ou pointe ailleurs, il est donc protégé par un `case` qui ne le laisse s'exécuter que si le chemin est celui qu'a créé `mktemp` en 9.1.2 :

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 9.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l9.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt punto-de-partida/token.txt
```

Vérifie en outre qu'il ne reste aucun conteneur client (`docker ps -a --filter name=curso-k8s-l9` ne doit rien montrer) et que le nœud que tu as arrêté en 9.12 n'est pas resté arrêté : si tu as supprimé le cluster avec le nœud arrêté, `kind delete cluster` le supprime aussi. Si tu as créé un réseau Docker dédié pour exécuter plusieurs leçons à la fois, on le supprime après le cluster, et seulement celui-là : `docker network rm <ton-réseau>`. Le réseau `kind` normal n'est pas touché.

## Comment savoir que tu y es arrivé

- [ ] Devant `error: Metrics API not available`, tu dis ce qui manque (un répondeur de l'API de métriques), et devant `x509: cannot validate certificate for … because it doesn't contain any IP SANs`, tu dis ce qui se passe et ce que corrige le drapeau, et pourquoi il n'est que pour le laboratoire.
- [ ] Tu calcules manuellement les répliques que demandera le HPA avec `ceil(actuelles × mesurée ÷ cible)`, tu appliques la tolérance de 10 % et tu l'as vérifié avec la colonne `TARGETS` et les événements `SuccessfulRescale`.
- [ ] Tu expliques pourquoi le Deployment ne porte plus `replicas` et ce qu'a montré `kubectl diff` en `replicas: 3` → `replicas: 1`.
- [ ] Tu expliques pourquoi la fenêtre de réduction rend la réduction lente et la montée rapide, et tu l'as vu sur l'horloge.
- [ ] Tu lis le `FailedScheduling` d'une contrainte de répartition et tu dis pourquoi le nœud de contrôle exige `nodeTaintsPolicy: Honor`.
- [ ] Tu exécutes `./sondeo.sh`, tu lis les trois colonnes (code, sortie de `curl`, version) et tu dis ce qui distingue un `curl 7` d'un `curl 28`.
- [ ] Tu dis, avec tes chiffres, combien on perd dans une mise à jour avec et sans `preStop`, et quelles limites a ta mesure.
- [ ] Tu fais un `rollout undo`, tu regardes `deletionTimestamp` et tu dis pourquoi une requête a pu répondre avec la version que tu viens de retirer.
- [ ] Tu provoques un `drain` bloqué par un PDB sans marge, tu le lis et tu le corriges ; et tu dis pourquoi, après une maintenance, les répliques peuvent se retrouver ensemble.
- [ ] Tu arrêtes un nœud, tu mesures la fenêtre de panne, et tu dis ce qui la raccourcit (plus de répliques réparties, nouvelles tentatives du client, un délai de détection plus court dans le plan de contrôle) et ce qui ne la raccourcit pas (les probes, `tolerationSeconds`).
- [ ] Tu exécutes `programas/09-escalar-y-actualizar/correr.sh > /tmp/mi-corrida-l9.txt 2>&1` et tu compares avec `correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) ce qui ne change pas : le `x509`, le `Metrics API not available` et le `MissingEndpoints` ; `replicas: 3` → `replicas: 1` dans le `diff` ; le plancher de 2 répliques, une par nœud ; le `FailedScheduling` avec `didn't match pod topology spread constraints` ; le HPA qui monte en dépassant 55 % et redescend une fenêtre plus tard ; les deux modes d'échec de l'interrogation ; le retour en arrière avec une requête qui répond encore avec la version retirée ; le `drain` bloqué par le PDB strict ; et le nœud qui passe à `NotReady` au bout d'environ 50 secondes. Les nombres exacts de requêtes, les durées, les noms des Pods, les IP et la répartition des échecs entre les rondes changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] Tu provoques une mise à jour avec une image qui n'existe pas, tu lis `ErrImagePull` et `ImagePullBackOff`, tu vois que le Deployment reste `UP-TO-DATE 1` avec les anciennes répliques disponibles, et tu la ramènes en arrière avec `rollout undo`.
- [ ] À la fin, `kind get clusters` ne montre plus `curso-k8s-l9`, le dossier temporaire du `kubeconfig` n'existe plus dans `/tmp`, et il ne reste aucun `token.txt`.

## Résumé

Réponds sans regarder la leçon :

1. Que manque-t-il dans un cluster fraîchement créé pour que `kubectl top` fonctionne, et pourquoi `metrics-server` ne démarre-t-il pas tel quel dans kind ?
2. Quelle est la formule du HPA, par rapport à quoi se mesure le pourcentage, et que fait la tolérance ?
3. Que fait la fenêtre de réduction de 60 secondes, et pourquoi la montée n'en a-t-elle pas une semblable ?
4. Pourquoi un Deployment gouverné par un HPA ne doit-il pas porter `replicas` ?
5. Que disent `maxSkew`, `DoNotSchedule` et `nodeTaintsPolicy: Honor`, et que se passe-t-il sans le dernier ?
6. Quelles deux choses se produisent en même temps quand un Pod s'arrête, et que referme le `preStop` ?
7. Qu'est-ce qui distingue un échec `curl 7` d'un `curl 28` ?
8. Qu'a montré l'interrogation périodique avec et sans `preStop`, et que ne démontre-t-elle pas ?
9. Pourquoi une version que tu viens de retirer avec `rollout undo` peut-elle encore répondre ?
10. Qu'est-ce qu'un PDB, à quel type d'interruptions s'applique-t-il, et que se passe-t-il avec un `drain` quand il n'y a pas de marge ?
11. Combien de temps le cluster a-t-il mis à remarquer le nœud en panne, et qu'est-ce qui raccourcit cette fenêtre ?
12. Que devient le service quand une mise à jour pointe vers une image qui n'existe pas, et pourquoi ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Horizontal Pod Autoscaling »](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) : la formule `desiredReplicas`, le calcul par rapport aux `requests`, la tolérance de 10 %, la fenêtre de stabilisation de 300 secondes par défaut pour la réduction, la politique de comportement par défaut et la recommandation de retirer `spec.replicas` du Deployment.
- [Kubernetes, « Pod Topology Spread Constraints »](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/) : `topologyKey`, `maxSkew`, `whenUnsatisfiable`, `nodeTaintsPolicy`, `matchLabelKeys` avec `pod-template-hash` et la limitation concernant les Pods retirés.
- [Kubernetes, « Pod Lifecycle »](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) : le flux de terminaison d'un Pod : `preStop`, signal `TERM`, délai, `KILL`, et le retrait des destinations en parallèle.
- [Kubernetes, « Container Lifecycle Hooks »](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/) : les trois types de hook (Exec, HTTP, Sleep) et le délai d'arrêt qui inclut le `preStop`.
- [Kubernetes, « Deployments »](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) : `maxSurge`, `maxUnavailable`, `rollout undo`, `--to-revision`, l'annotation `kubernetes.io/change-cause`, `revisionHistoryLimit` et la condition `Available`.
- [Kubernetes, « Disruptions »](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/) : interruptions volontaires et involontaires, le budget qui n'évite pas les secondes mais les compte, et `kubectl drain` avec l'API d'éviction.
- [Kubernetes, « Specifying a Disruption Budget for your Application »](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) : `minAvailable` et `maxUnavailable`.
- [Kubernetes, « Safely Drain a Node »](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) : ce que fait `kubectl drain` et pourquoi il respecte les PDB ; `--ignore-daemonsets`.
- [Kubernetes, « Node Status »](https://kubernetes.io/docs/reference/node/node-status/) : la condition `Ready` à `Unknown` si le contrôleur de nœuds n'a pas de nouvelles du nœud dans `node-monitor-grace-period` (50 secondes par défaut) et les battements de cœur avec `Lease`.
- [Kubernetes, « Taints and Tolerations »](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) : les taints `not-ready` et `unreachable`, et les tolérances de 300 secondes qui s'ajoutent toutes seules.
- [Kubernetes, « Resource metrics pipeline »](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/) : la Metrics API, `metrics-server` et `kubectl top` ; le CPU comme taux sur une fenêtre.
- [metrics-server, README](https://github.com/kubernetes-sigs/metrics-server) : les prérequis (certificat du `kubelet` signé par l'autorité du cluster), `--kubelet-insecure-tls` « uniquement pour des tests », et les usages et non-usages.
- [metrics-server, notes de la v0.9.0](https://github.com/kubernetes-sigs/metrics-server/releases/tag/v0.9.0) : la version qu'utilise la leçon.
- [Phil Pearl, « Kubernetes' dirty endpoint secret and Ingress »](https://philpearl.github.io/post/k8s_ingress/) (26 juillet 2019) : le retrait des destinations et l'arrêt se produisent en même temps ; la pause avant l'arrêt.
- [Go, `net/http`, `Server.Shutdown`](https://pkg.go.dev/net/http#Server.Shutdown) : l'arrêt ordonné ferme d'abord les ports ouverts puis les connexions inactives.
- [Kubernetes, « Job »](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-termination-and-cleanup) : `activeDeadlineSeconds` court depuis la création du Job et le termine quoi qu'il arrive.
- [Kubernetes, « kube-controller-manager »](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) : `--node-monitor-grace-period` (50 s) et `--node-monitor-period` (5 s).
- [curl, « man page »](https://curl.se/docs/manpage.html) : `--retry`, `--retry-all-errors` et `--max-time`.
- [curl, « libcurl error codes »](https://curl.se/libcurl/c/libcurl-errors.html) : les codes 7 et 28.

---

**Suivante :** [Leçon 10 — Le projet terminé et ce qui change dans un vrai cluster](10-proyecto-final.md)
