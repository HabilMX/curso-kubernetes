# Cours de Kubernetes avec kind — déploie, configure, mets à l'échelle et protège un service sur ta propre machine

**Par Dorian Chávez, fondateur de Hábil et architecte d'intégration.**

**À qui il s'adresse :** à qui a déjà suivi le [cours de Docker](https://www.habil.mx/fr/cours/docker/) de Hábil, ou à qui empaquette aisément des services dans des conteneurs : tu construis des images, tu les exécutes, tu leur donnes des volumes et tu les lances ensemble avec Compose. Niveau intermédiaire. On ne suppose pas que tu aies touché à Kubernetes ni que tu aies un cluster : le cours t'en donne un, local, qui se crée et se détruit en quelques minutes. Chaque concept est expliqué au moment où il apparaît, et l'on explique pourquoi il existe, pas seulement comment il s'écrit.

**Ce que tu sauras faire à la fin :** déployer un service dans un cluster Kubernetes et l'exploiter —le configurer, le surveiller, le publier, le limiter, conserver ses données, le mettre à l'échelle et le mettre à jour en mesurant chaque coupure— ; lire ce que le cluster te dit quand quelque chose échoue (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) au lieu de supprimer et de réessayer ; et expliquer, sans fioritures, quelle distance il y a entre ton cluster local et un cluster de production.

**D'où il vient :** ce cours fait suite à celui de [**Docker**](https://www.habil.mx/fr/cours/docker/) de Hábil et utilise comme point de départ son image terminée du `revisor`. Si tu n'as pas suivi ce cours, tu as besoin d'une image d'un service HTTP qui sache dire s'il est en vie et qui s'exécute sans être `root` ; la [Leçon 2](02-pods-deployments.md) te dit exactement ce qu'elle doit respecter.

**Ce dont tu as besoin avant de commencer :** un ordinateur avec Linux Mint 22.x, Docker Engine fonctionnel et les droits d'administrateur (`sudo`). La [Leçon 1](01-instalacion-primer-cluster.md) installe `kubectl` et `kind` et crée le cluster.

## Le projet que tu vas construire

Le **`revisor`** : le serveur HTTP qui interroge une liste de services **en même temps** et livre son rapport, le même que dans les cours de [Go](https://www.habil.mx/fr/cours/go/), de [Rust](https://www.habil.mx/fr/cours/rust/), de [TypeScript](https://www.habil.mx/fr/cours/typescript/) et de [Docker](https://www.habil.mx/fr/cours/docker/) de Hábil ; son serveur est écrit en Go et écoute sur le port 8080 (`GET /salud`, `GET /api/estados`, configuration par variables d'environnement, sous-commande `healthcheck`). Ici, tu ne le programmes plus et tu ne l'empaquettes plus : tu le **fais vivre dans un cluster**. Tu le déploies avec plusieurs répliques, tu le rends trouvable par son nom, tu le configures sans reconstruire l'image, tu apprends au cluster à le surveiller, tu le publies vers l'extérieur, tu l'isoles avec des permissions minimales et un réseau fermé, tu lui donnes un endroit où stocker son rapport, tu le transformes en tâche planifiée et tu le fais passer à l'échelle avec la charge. À la fin, tout se déploie avec deux `kubectl apply -k` —la plateforme et le projet— et une attente entre les deux.

Il est accompagné du **service de test qui échoue exprès** du cours de Docker (sain, lent ou en panne), parce qu'on comprend vraiment un cluster quand quelque chose casse et que l'on voit ce qu'il fait.

## Les onze leçons

| Leçon | | Ce que tu construis | Ce que tu apprends |
|---|---|---|---|
| 0 | [Ce qu'est Kubernetes et ce que kind n'est PAS](00-que-es-kubernetes.md) | rien pour l'instant (lecture) | le plan de contrôle et les nœuds ; déclarer l'état souhaité et laisser le cluster l'atteindre ; la correspondance de Docker à Kubernetes ; ce que kind permet de tester et ce qu'il ne permet pas |
| 1 | [Installer kubectl et kind ; ton premier cluster](01-instalacion-primer-cluster.md) | le cluster du cours : un nœud de contrôle et deux de travail | `kubectl` et `kind` avec version figée et somme de contrôle ; le réglage d'`inotify` ; contextes et `kubeconfig` ; créer, observer, supprimer et recréer |
| 2 | [Pods et Deployments](02-pods-deployments.md) | le `revisor` en marche, avec des répliques qui renaissent | `kind load docker-image` ; l'`ErrImagePull` provoqué exprès ; Pod, ReplicaSet et Deployment ; étiquettes ; `rollout` ; `securityContext` dès le premier manifeste |
| 3 | [Services et DNS](03-services-dns.md) | le `revisor` trouvable par son nom | `ClusterIP` ; sélecteurs et `EndpointSlice` ; `port`, `targetPort` et `containerPort` ; le DNS du cluster ; `port-forward` ; un Pod de débogage |
| 4 | [Configuration et secrets](04-configuracion-secretos.md) | le `revisor` configuré sans reconstruire | `ConfigMap` en variables d'environnement (le `revisor` ne lit que des variables) et `Secret` en fichier, et pourquoi base64 n'est pas du chiffrement ; Kustomize avec générateurs et le *hash* qui déclenche le rollout |
| 5 | [Contrôles de santé, ressources et arrêt ordonné](05-salud-recursos-apagado.md) | un `revisor` que le cluster sait surveiller | startup, readiness et liveness probes ; pourquoi `/salud` n'interroge personne ; `requests` et `limits` ; `OOMKilled` et `Pending` provoqués exprès ; le délai d'arrêt |
| 6 | [Entrer dans le cluster](06-entrar-al-cluster.md) | le `revisor` publié vers l'extérieur | `LoadBalancer` avec MetalLB et Gateway API avec Envoy Gateway, installés dans le cluster ; pourquoi pas Cloud Provider KIND sur une machine partagée (il agit sur tous les clusters kind) ; `Ingress` comme API gelée ; pourquoi pas `ingress-nginx` ; ce qui est exposé et par où |
| 7 | [Isoler : espaces, permissions et réseau](07-aislar-permisos-red.md) | un espace de noms dédié avec des règles | `Namespace` ; Pod Security Admission au niveau `restricted` ; `ServiceAccount` et RBAC minimal avec `auth can-i` ; `NetworkPolicy` « tout fermé » et ses ouvertures (on mesure que kindnet, le CNI fourni avec kind, les applique ; il n'est pas nécessaire d'en installer un autre) |
| 8 | [Données et tâches](08-datos-y-tareas.md) | le rapport stocké et le `revisor` en tâche planifiée | `PersistentVolumeClaim` et la classe de stockage de kind ; `Job` et `CronJob` ; le propriétaire des fichiers avec `fsGroup` ; ce qui est perdu quand on supprime un Pod |
| 9 | [Mettre à l'échelle et mettre à jour en mesurant chaque coupure](09-escalar-y-actualizar.md) | le `revisor` qui augmente et réduit ses répliques avec la charge | `metrics-server` ; `HorizontalPodAutoscaler` et sa formule ; la fenêtre de réduction ; répartition avec `topologySpreadConstraints` ; `RollingUpdate` et `preStop` mesurés avec une interrogation périodique ; `rollout undo` ; `PodDisruptionBudget` et `drain` ; la fenêtre d'un nœud en panne |
| 10 | [Le projet terminé et ce qui change dans un vrai cluster](10-proyecto-final.md) | tout avec deux `kubectl apply -k` (plateforme et projet) et une attente | Kustomize avec base et *overlays* ; vérification par rapport au niveau `restricted` ; Helm, simplement mentionné ; ce qu'il manque à cela pour être en production |

À la fin de chaque leçon, il y a des exercices avec leurs solutions. Et le [journal de bord](bitacora.md) est à toi : note-y ce qui t'a donné du mal.

## Trois principes qui traversent tout le cours

**La sécurité n'est pas une leçon, c'est une habitude.** La leçon 7 rassemble les permissions, les espaces et le réseau parce qu'on les y étudie pour eux-mêmes, mais le reste du cours les met déjà en pratique dès le premier manifeste :

| Leçon | L'habitude qui s'installe |
|---|---|
| 0 | savoir ce qu'un cluster local défend et ce qu'il ne défend pas |
| 1 | binaires avec somme de contrôle ; l'image du nœud figée ; vérifier le contexte avant chaque commande qui modifie quelque chose |
| 2 | `securityContext` dans le premier Deployment : sans `root`, sans élévation de privilèges, sans capacités, système de fichiers en lecture seule, profil `seccomp` |
| 3 | `ClusterIP` par défaut ; rien n'est publié sans raison ; `port-forward` uniquement vers `127.0.0.1` |
| 4 | un `Secret` n'est pas chiffré : on ne le versionne pas, on le monte comme fichier et on le marque immuable |
| 5 | `requests` et `limits` sur chaque conteneur ; les probes ne dépendent pas de services tiers |
| 6 | on expose le minimum, par un point d'entrée nommé, et l'on précise ce qui manque (chiffrement en transit) |
| 7 | espace dédié, niveau `restricted`, permissions minimales, réseau fermé par défaut |
| 8 | le `ServiceAccount` sans identifiants montés s'il n'en a pas besoin ; les données avec leur propriétaire |
| 9 | limites à la mise à l'échelle ; les mises à jour maintiennent le service en marche, avec les rares échecs mesurés et expliqués |
| 10 | vérification finale par rapport au niveau `restricted` et la liste de ce qu'exige un vrai cluster |

**On lit avant de supprimer.** Quand quelque chose ne démarre pas, le réflexe du débutant est de le supprimer et de le réappliquer. Ici, le réflexe est tout autre : `describe`, `logs`, `get events`. Chaque leçon provoque exprès une panne typique et t'apprend l'ordre dans lequel la lire, parce que cet ordre, c'est le métier.

**On n'enseigne que ce qui est en vigueur, et ce qui a été retiré est nommé pour savoir le reconnaître.** `ingress-nginx` n'est plus maintenu depuis mars 2026 et les tutoriels d'il y a deux ans l'enseignent encore ; `Ingress` est une API gelée et Gateway API est son successeur. Le cours dit qui est quoi. Et chaque version est donnée avec sa date : celles de ce cours ont été relevées le 7 octobre 2026 (Kubernetes 1.37.1 ; kind v0.33.0, dont le nœud par défaut est 1.37.0). Ce qui dépend d'une brique externe (MetalLB, Envoy Gateway, l'application de `NetworkPolicy`, `metrics-server` dans kind) est vérifié en direct au moment d'écrire chaque leçon et n'est pas affirmé avant.

## Comment savoir que tu as terminé

Le cours ne se termine pas quand tu as lu la leçon 10, mais quand ton projet remplit ces sept conditions. Ce sont des objectifs de conception : ils sont mesurés et ajustés au moment d'écrire les leçons, et chaque leçon reprend celui qui la concerne une fois mesuré.

1. **Depuis un cluster fraîchement créé, le `revisor` se met en marche en trois étapes, toujours dans le même ordre :** un `kubectl apply -k` de la plateforme (MetalLB et Envoy Gateway, avec leurs CRD), un `kubectl wait` jusqu'à ce qu'elle soit prête, puis le `kubectl apply -k` du projet. L'ordre compte parce que les CRD et les *webhooks* doivent exister avant les ressources qui les utilisent. Et `kind delete cluster` suivi des trois mêmes étapes le reconstruit sans que tu corriges quoi que ce soit manuellement.
2. **L'espace de noms du `revisor` est au niveau `restricted`** de Pod Security Admission et ne reçoit pas le moindre avertissement lors de l'application.
3. **Tu arrêtes le conteneur d'un nœud de travail** (`docker stop`) et le service continue de répondre grâce à la réplique de l'autre nœud, **avec une fenêtre mesurée** : pendant des dizaines de secondes —le temps que met le cluster à déclarer le nœud perdu (`node-monitor-grace-period`, 50 s par défaut) : dans les quatre rondes de la leçon 10, le service a répondu de nouveau entre 34 et 51 s après l'arrêt du nœud, et dans la leçon 9 le nœud est passé à `NotReady` à 57 s— les requêtes qui tombent sur la réplique morte échouent (mesuré sur une ronde, avec 2 répliques : 7 requêtes sur 42 ont échoué, et la dernière panne est survenue 53 s après l'arrêt). Tu sais dire ce qui raccourcit ou adoucit cette fenêtre (plus de répliques réparties, des nouvelles tentatives côté client, un délai de détection plus court dans le plan de contrôle) et ce qui ne le fait pas (les probes, exécutées par le nœud en panne lui-même, ni `tolerationSeconds`, qui décide seulement quand les Pods sont remplacés). Et une mise à jour avec `preStop` réduit les coupures sans garantir zéro : sur quatre rondes elle a mesuré 0, 4, 0 et 1 échecs, soit 5 sur 2 049 requêtes au total, contre 29 sur 1 569 sans `preStop` sur trois rondes (mesuré depuis l'intérieur du cluster, via le Service et `kube-proxy`, pas via la porte d'entrée ; avec quatre fils `curl` sur une machine partagée et sans alterner les rondes). Quand tu relances le nœud, le cluster se recompose tout seul.
4. **Tu modifies la liste de services dans le `ConfigMap`** et le cluster effectue le rollout tout seul, sans que tu reconstruises l'image.
5. **Sous charge, `kubectl get hpa --watch` montre les répliques monter, puis redescendre quelques minutes plus tard**, et tu peux expliquer pourquoi la descente prend ce temps-là.
6. **Un Pod étranger au `revisor` ne peut pas lui parler** (la `NetworkPolicy` le bloque ; objectif soumis au fait que le cluster l'applique) et le compte de service du `revisor` **ne peut rien faire dont il n'ait besoin** (`kubectl auth can-i` te le démontre).
7. **Tu sais énoncer, par écrit, cinq raisons pour lesquelles ce que tu as construit n'est pas de la production**, et ce que l'on ferait pour chacune dans un vrai cluster.
