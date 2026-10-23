# Leçon 7 — Isoler : espaces, permissions et réseau

Vendredi, 17 h 50. L'équipe data réclame depuis deux semaines un endroit où tester son service, et ton cluster kind a de la place à revendre. Tu leur as dit oui. À 17 h 58, quelqu'un de l'équipe sécurité, qui passe en revue ce qui est publié avant le week-end, t'écrit trois questions d'affilée. Une : « un Pod de leur côté peut-il lire le token du `revisor` ? ». Deux : « peut-il parler au `revisor` sans passer par le point d'entrée que tu as publié ? ». Trois : « peut-il demander à l'API du cluster la liste des Secrets ? ». Tu sais que le `revisor` tourne sans être `root`, avec des probes, des limites et derrière un point d'entrée nommé. Mais ces trois questions ne portent pas sur le `revisor`. Elles portent sur **ce qui entoure le `revisor`**, et tu n'as pas une seule réponse mesurée. Il est 18 h 00. L'équipe data a déjà collé son premier Pod dans l'espace `default`, celui où vit tout ce qui est à toi.

L'histoire de la sécurité dans le cloud compte bien des versions de cette soirée. Le 20 février 2018, l'entreprise de sécurité RedLock a raconté avoir trouvé chez Tesla une console d'administration Kubernetes ouverte, sans protection. Selon RedLock elle-même, la personne entrée par là y a trouvé des identifiants d'accès à un espace de stockage de données d'Amazon Web Services et a mis le cluster au travail pour miner des cryptomonnaies. Tesla a répondu que l'impact semblait limité à des véhicules de test d'ingénierie et qu'elle avait corrigé le problème en quelques heures. L'article de presse qui le raconte figure dans les sources de cette leçon. Cette porte ouverte n'est pas ce que la leçon étudie. Ce qu'elle enseigne, c'est la question qui vient **après** n'importe quelle porte ouverte, par négligence ou par erreur d'une autre équipe : une fois à l'intérieur, jusqu'où va ce qui est entré ?

Jusqu'à aujourd'hui, dans ton cluster, la réponse est « aussi loin que ça peut aller ». Cette leçon y dresse des murs, en quatre couches, et t'apprend à **mesurer** chacune avec l'attaquant le plus modeste qui soit : un Pod avec `curl` qui ne devrait rien pouvoir faire. La première décide **où vit chaque chose** (l'espace de noms). La deuxième décide **ce qu'on a le droit de créer** (Pod Security Admission). La troisième décide **qui peut faire quoi avec l'API** (comptes de service et RBAC), et la quatrième, **qui peut parler à qui** (les politiques réseau). Quand tu auras terminé, les trois questions de 17 h 58 auront chacune une réponse avec une commande à côté.

**Durée :** 2 × 45 min

**Ce que tu construis :** un espace de noms dédié, `revisor`, avec des règles : tout le projet y vit, le cluster rejette tout Pod qui ne respecte pas le niveau `restricted`, chaque programme a son compte de service sans permissions et sans identifiants montés (sauf un compte en lecture seule pour observer), et le réseau est fermé par défaut grâce à six politiques qui n'ouvrent que le strict nécessaire

**Ce que tu apprends :** ce qu'est un espace de noms et ce qu'il n'isole **pas** ; Pod Security Admission avec ses trois modes et ses trois niveaux, et comment lire ses rejets ; `ServiceAccount`, `Role` et `RoleBinding` avec des permissions minimales et comment les vérifier avec `kubectl auth can-i`, avec une requête en usurpant une identité et depuis l'intérieur d'un Pod ; `NetworkPolicy` : le modèle (ouvert tant qu'aucune politique ne sélectionne le Pod, et les règles s'additionnent), qui les applique dans kind (on le mesure), ce qui casse avec « tout fermé » et à quoi sert chacune des six ouvertures, en les retirant une à une ; et comment une route d'un autre espace se rattache au point d'entrée (`allowedRoutes` et `ReferenceGrant`)

**D'où tu viens.** De la [Leçon 6](06-entrar-al-cluster.md) : le `revisor` tourne avec trois répliques et le service de test avec une, avec des probes, des `requests` et des `limits` ; MetalLB et Envoy Gateway sont installés dans le cluster ; le point d'entrée est un `Gateway` appelé `revisor` avec sa `HTTPRoute` ; et il y a un `Service` `LoadBalancer` direct, `revisor-publico`, que cette leçon retire. Tout vit dans l'espace `default`. De la [Leçon 5](05-salud-recursos-apagado.md), tu retiens que les probes sont exécutées par le `kubelet` du nœud, une information qui décide aujourd'hui si le réseau fermé fait tomber ou non les Pods. De la [Leçon 3](03-services-dns.md), le Pod `depurar`, le DNS du cluster et le fait qu'une requête de nom est du trafic réseau comme un autre. Et de la [Leçon 2](02-pods-deployments.md), le `securityContext` qui, dès le premier manifeste, respecte sans que tu le saches le niveau `restricted` : aujourd'hui, le cluster commence à l'exiger.

**Ce que cette leçon ne fait pas.** Elle ne chiffre pas le trafic : le point d'entrée continue de parler en HTTP en clair, et à l'intérieur du cluster les Pods ne chiffrent pas non plus ce qu'ils s'échangent. Elle n'installe pas d'autre extension réseau : le cours prévoyait d'installer Calico si le réseau de kind n'appliquait pas les politiques, et la section 7.5 mesure qu'il les applique, donc ce n'est pas nécessaire. Elle ne limite pas le nombre de ressources qu'un espace de noms peut créer (`ResourceQuota` et `LimitRange`, que la [Leçon 5](05-salud-recursos-apagado.md) a nommés) et n'installe pas de politiques d'admission personnalisées. Elle ne stocke pas de données et ne planifie pas de tâches : c'est la [Leçon 8](08-datos-y-tareas.md), qui aura besoin de cette leçon pour deux choses, un compte de service sans identifiants pour la tâche et l'étiquette `acceso-revisor: permitido` pour que la tâche puisse parler au `revisor`. Et ce n'est pas non plus un audit de sécurité d'un cluster réel : la section sur l'habitude de sécurité dit, chiffres à l'appui, ce que tout cela défend et ce qu'il ne défend pas.

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1, l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, **MetalLB v0.16.1** et **Envoy Gateway v1.9.2**, sur le cluster de trois nœuds de la Leçon 1, qu'on appelle ici `curso-k8s-l7`. La machine était un Mac à processeur ARM (`arm64`) avec Docker Engine 29.2.1 dans une machine virtuelle Ubuntu 24.04.4 (Colima). La première ligne de `correr.salida.txt` consigne ce que le script peut mesurer : `Docker 29.2.1 en Ubuntu 24.04.4 LTS (arm64)` ; que la machine hôte soit un Mac avec Colima, le script ne le voit pas. Ce n'était **pas** Linux Mint, qui est le système de référence du cours. **Cette exécution a utilisé un réseau Docker dédié**, `curso-k8s-red-l7`, avec le sous-réseau `172.27.0.0/16`, parce que, sur la même machine, d'autres leçons tournaient en même temps avec leur propre MetalLB, et deux MetalLB ayant la même plage sur le même réseau se marchent dessus (tu l'as vu dans la Leçon 6). C'est pourquoi les adresses des nœuds et du point d'entrée apparaissent ici sous la forme `172.27.…`. Sur ton Mint, avec le réseau `kind` normal, le point d'entrée reçoit `172.18.255.200` et les nœuds se rattachent à `172.18.0.0/16` ; le reste des sorties ne change pas. `correr.sh` gère les deux cas : avec le réseau `kind` par défaut, et avec un réseau dédié si tu lui indiques lequel avec `CURSO_RED` et `CURSO_SUBRED` ; dans les deux cas, il vérifie que le sous-réseau est exactement celui que tu attends et s'arrête s'il ne l'est pas (avec un réseau dédié, avant de créer le cluster ; avec le réseau `kind`, juste après l'avoir créé). Ce qui change d'autre sur ta machine : l'architecture, les suffixes des noms, les âges, le nœud de chaque Pod, le nom du Secret (le token est nouveau à chaque exécution) et les millisecondes. Le parcours complet se trouve dans [`programas/07-aislar-permisos-red/`](../programas/07-aislar-permisos-red) : `correr.sh` crée le cluster, y charge les deux images, installe la plateforme de la Leçon 6, remet tout dans l'état où cette leçon l'a laissé, parcourt celle-ci dans l'ordre, exécute les Exercices 1 à 3 et supprime le cluster. L'exécution complète a duré 26 minutes et 9 secondes, longue parce que la machine était chargée par d'autres clusters et parce que la leçon attend le réseau ; créer le cluster et attendre qu'il soit prêt a pris 39 secondes, installer la plateforme 411 et le supprimer 1, et le disque de Docker était à 79 % au début et à 77 % à la fin. Les attentes de l'installation et du point d'entrée (`speaker`, `Programmed`, le Pod `viejo`) ont des délais généreux (480, 360 et 300 secondes) parce que, sur une machine chargée, les images mettent du temps à être téléchargées ; si, chez toi, une attente dépasse son délai, ne continue pas à l'aveugle : relance-la et regarde avec `kubectl get pods -A` ce qui manque. Sa sortie est `correr.salida.txt` ; il faut internet (les manifestes de MetalLB et d'Envoy Gateway sont téléchargés depuis leurs versions publiées, figées sur leur version). Les attentes sont visibles : là où le script attend, la sortie l'indique avec un `kubectl wait`, un `rollout status` ou un `sleep`. Il utilise le port 18087 de ta machine pour un `port-forward` et s'arrête avant de commencer si ce port est déjà occupé.

## À la fin, tu seras capable de

- Expliquer ce qu'un espace de noms isole (les noms et la portée des permissions) et ce qu'il n'isole pas (le réseau), et le démontrer avec un Pod d'un espace qui parle à un Service d'un autre.
- Faire migrer le projet de `default` vers un espace dédié avec `kubectl apply -k`, et distinguer ce qui vit à l'intérieur d'un espace de ce qui vaut pour tout le cluster.
- Placer un espace de noms au niveau `restricted` avec ses étiquettes, figer la version de la politique, et lire ligne par ligne le rejet d'un Pod qui ne la respecte pas.
- Provoquer un Deployment qui est créé mais reste sans Pods à cause de Pod Security Admission, et trouver la raison dans les événements du ReplicaSet.
- Écrire un `Role` et un `RoleBinding` en lecture seule, vérifier ce qu'ils permettent et ce qu'ils refusent avec `kubectl auth can-i` et avec une vraie requête depuis un Pod, et expliquer pourquoi le `revisor` n'a pas d'identifiants montés.
- Fermer le réseau d'un espace avec une politique, mesurer ce qui casse (y compris le DNS et le point d'entrée), n'ouvrir que le nécessaire et dire, pour chacune des six politiques, ce qui cesserait de fonctionner si elle manquait.
- Expliquer à quelle condition une `NetworkPolicy` « fermée par défaut » protège quelque chose, et le vérifier sur ton cluster.
- Rattacher une route d'un autre espace au point d'entrée, et distinguer `allowedRoutes` (qui peut se rattacher au Gateway) de `ReferenceGrant` (qui peut être la destination d'une route).

## Le pourquoi avant le comment

Imagine un immeuble de bureaux avec un seul long couloir et des portes sans serrure. Quelqu'un a posé des plaques sur les portes (`datos`, `finanzas`, `revisor`) et ça a l'air bien rangé. Mais la plaque ne ferme rien : n'importe qui entrant dans l'immeuble peut ouvrir n'importe quelle porte. C'est ton cluster aujourd'hui. Les espaces de noms que tu connais déjà sont les plaques. Cette leçon lui ajoute des clés, un règlement et des portes à serrure, et elle le fait par couches, parce que chaque couche répond à une question différente et échoue d'une manière différente :

1. **Où vit chaque chose ?** L'**espace de noms** (*namespace*). Il regroupe des objets, permet à deux équipes d'utiliser le même nom sans collision, et c'est l'unité à laquelle on attache permissions et règles. Ce n'est pas un mur réseau : on le mesure en 7.5.
2. **Qu'a-t-on le droit de créer ?** **Pod Security Admission**. C'est un garde posté à l'entrée du `kube-apiserver` qui examine chaque Pod voulant naître dans un espace et le rejette s'il ne respecte pas le niveau que cet espace exige. Il protège contre le Pod mal écrit, pas contre le Pod qui tourne déjà.
3. **Qui peut faire quoi avec l'API ?** **Comptes de service et RBAC**. Chaque programme qui s'exécute dans le cluster a une identité, et chaque identité a une liste (vide par défaut) de verbes qu'elle peut appliquer à certains objets.
4. **Qui peut parler à qui ?** **Politiques réseau**. Aujourd'hui, tout Pod peut parler à tout Pod. Une politique change cela Pod par Pod, et ne fonctionne que si le réseau du cluster les applique.

Les couches se complètent parce qu'elles protègent contre des choses différentes. PSA empêche que quelqu'un (ou une étourderie de ta part) crée un conteneur avec trop de privilèges. RBAC limite ce qu'un programme fait **avec l'API**. Le réseau limite ce qu'il fait **avec les autres Pods**. Et l'espace de noms est l'endroit où les trois s'appliquent. Si l'une manque, les autres ne la remplacent pas : un Pod `restricted` sans politique réseau peut toujours parler à tout le monde, et un réseau fermé avec un compte de service trop généreux laisse un Pod compromis demander à l'API tout ce que cette permission permet.

La leçon comporte cinq parties de concepts, puis les sections habituelles :

1. **Le cluster de la leçon** (7.1), avec la plateforme de la Leçon 6 et le point de départ.
2. **Un espace de noms dédié** (7.2) : ce que c'est, ce qu'il contient et la migration.
3. **Pod Security Admission** (7.3) : modes, niveaux, étiquettes et le rejet qu'on apprend à lire.
4. **Comptes de service et permissions minimales** (7.4) : `ServiceAccount`, `Role`, `RoleBinding`, `auth can-i`, et une vraie requête depuis l'intérieur d'un Pod.
5. **Le réseau** (7.5) : le modèle, qui l'applique, sans règles, tout fermé, les ouvertures et à quoi sert chacune.

Voici la destination. À la fin de 7.5, un Pod portant la bonne étiquette peut parler au `revisor`, un Pod sans elle ne le peut pas, et les deux réponses viennent de commandes que tu peux répéter :

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

## Si tu n'as pas les images du cours de Docker

Cette leçon utilise les deux mêmes images que les Leçons 3 à 6 : `curso-docker-revisor:1.6.0` et `curso-docker-prueba:1.0.0`. Vérifie que tu les as :

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Pour l'autre, la même commande avec `curso-docker-prueba:1.0.0`. S'il t'en manque une, la [Leçon 3](03-services-dns.md) explique comment construire les deux à partir du dépôt du cours de Docker. Cette leçon ne demande rien de nouveau à ces deux images. Les Pods d'appui (`depurar`, `intruso` et `lector`) utilisent l'image de `curl` figée par son empreinte, comme dans les leçons précédentes ; chaque nœud la télécharge depuis internet la première fois.

## Les concepts

### 7.1 Le cluster de la leçon

#### 7.1.1 Créer, avec la garde de contexte

Cette leçon crée son propre cluster, `curso-k8s-l7`, avec la configuration à trois nœuds de la Leçon 1. Jusqu'ici, dans les leçons précédentes, la vérification du contexte était une ligne que tu copiais devant chaque commande. Aujourd'hui, elle devient une fonction, pour qu'elle soit courte et que tu ne l'oublies pas. Crée-le ainsi, depuis la racine du dépôt du cours :

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

La fonction `ctx` fait une seule chose : elle compare le contexte actif de `kubectl` avec `kind-curso-k8s-l7`. S'ils coïncident, elle n'affiche rien et se termine bien, et le `&&` laisse passer la commande suivante. S'ils ne coïncident pas, elle affiche « contexto equivocado: no sigo » et se termine en erreur, et le `&&` **coupe la chaîne** : la commande qui modifie quelque chose ne s'exécute pas. À partir d'ici, **toute commande de cette leçon qui modifie quelque chose** (`apply`, `delete`, `patch`, `label`, `run`, `exec` qui supprime…) s'écrit ainsi : `ctx && kubectl apply -k .`. Dans les sorties qui suivent, la ligne qui commence par `$` montre seulement la commande `kubectl`, sans le `ctx &&`, pour qu'elle tienne ; le script `correr.sh` fait la même vérification avant **chaque** `kubectl`, lectures comprises, et s'arrête si le contexte n'est pas celui de la leçon. Tu connais la raison de tant de précautions depuis la Leçon 1 : un `delete -k` dans le mauvais contexte supprimerait des objets d'un autre cluster, et cette leçon supprime et recrée pas mal de choses.

Deux vérifications de cohabitation, les mêmes que dans la Leçon 6 (avec un réseau dédié, elles se font avant de créer le cluster ; avec le réseau `kind` par défaut, qui naît avec le premier cluster, juste après l'avoir créé) : le réseau `kind` doit être `172.18.0.0/16` (c'est de là que vient la plage de MetalLB) et personne ne doit déjà répondre sur `172.18.255.200`. Si un autre de tes clusters avec MetalLB est vivant, attends qu'il se termine. `correr.sh` les fait et s'arrête si elles échouent ; dans cette exécution, il les a faites contre le réseau dédié, `curso-k8s-red-l7`, que la section « À propos des exécutions » explique.

```text
$ kubectl config current-context
kind-curso-k8s-l7

$ kubectl get nodes -o wide | awk '{print $1, $2, $3, $6}' | column -t
NAME                        STATUS  ROLES          INTERNAL-IP
curso-k8s-l7-control-plane  Ready   control-plane  172.27.0.4
curso-k8s-l7-worker         Ready   <none>         172.27.0.2
curso-k8s-l7-worker2        Ready   <none>         172.27.0.3
```

Les trois nœuds vivent dans le réseau Docker de l'exécution (`172.27.0.x` ; sur ton Mint, `172.18.0.x`). `kubectl wait` et `kubectl get` ne modifient rien, donc ils n'ont pas besoin de la garde ; tout le reste, si.

#### 7.1.2 La plateforme de la Leçon 6, en trois étapes

La Leçon 6 a laissé deux installations qui ne sont pas celles du `revisor` mais celles du cluster : MetalLB et Envoy Gateway. Cette leçon en a besoin parce que le projet inclut un `Gateway`. Elles s'installent comme là-bas, dans l'ordre que tu as appris : plateforme, attente, projet. Les commandes sont les mêmes que dans la section 6.9, et la sortie montre chaque attente :

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

Deux choses que tu sais déjà et une qui a changé. Tu sais déjà qu'il faut attendre le `controller` de MetalLB avant de lui donner la plage (le *webhook* doit être à l'écoute) et que la plage et la classe `eg` s'appliquent à la fin. Ce qui a changé, c'est l'attente des CRD : cette fois, elle inclut `referencegrants.gateway.networking.k8s.io`, un type de Gateway API qu'utilise l'Exercice 3 et qui vient dans le même paquet qu'Envoy Gateway a installé.

À propos de la ligne entre parenthèses de `kubectl apply -f infra/metallb-pool.yaml` : le fichier du cours contient la plage `172.18.255.200-172.18.255.220`, celle de ton Mint. Dans cette exécution, `correr.sh` a changé cette plage, **avec `sed` et à la volée**, en `172.27.255.200-172.27.255.250`, qui tombe dans le réseau dédié. C'est le seul changement : le fichier du dépôt n'a pas été touché. Sur ta machine, il s'applique tel quel.

#### 7.1.3 Le point de départ : la Leçon 6, dans `default`

Le dossier `punto-de-partida/` contient, sans changer une virgule, les manifestes avec lesquels la Leçon 6 s'est terminée. Tu es déjà dans le dossier de la leçon. Le token est factice et n'est pas versionné ; il est généré à chaque exécution avec l'`umask` que tu connais déjà, pour qu'il naisse avec la permission `0600`, et il est copié dans le dossier de la leçon parce que la `kustomization.yaml` des deux le demande :

```bash
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
```

Les parenthèses et l'`umask 077` sont l'habitude de la Leçon 4 : le fichier est créé fermé dès le premier octet, il n'est pas créé ouvert puis fermé après. Maintenant, avec le `revisor`, `prueba`, le `Service` public et le point d'entrée dans `default`, voici ce que le cluster sait de l'état « avant » :

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

Avec les neuf objets créés et le point d'entrée `Programmed`, l'état est celui de la Leçon 6. Il manque quatre lectures de l'« avant », celles qui vont changer à la fin de la leçon :

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

Voici comment les lire. Les espaces de noms sont les habituels plus les deux de la plateforme (`envoy-gateway-system` et `metallb-system`) ; `default` n'a pas d'autre étiquette que celle que lui met le système, `kubernetes.io/metadata.name` : aucune règle. La troisième commande demande, à la première réplique du `revisor` (`.items[0]` ; les trois sont identiques parce qu'elles sortent du même modèle), trois choses : avec quel compte elle tourne (`default`), si elle a demandé qu'on ne lui monte pas d'identifiants (le champ `automountServiceAccountToken` apparaît **vide**, c'est-à-dire qu'elle n'a rien dit) et quels volumes elle a : `datos`, `token` (le Secret de la Leçon 4) et un troisième au nom aléatoire, `kube-api-access-…`. Ce troisième, personne ne l'a demandé : **le cluster a monté dans le `revisor` un identifiant pour parler à l'API**, et le `revisor` ne parle pas à l'API. C'est la première chose que cette leçon retire. Et la dernière commande liste ce que le compte `default` peut faire : presque rien (créer des revues sur lui-même, qui sont des questions du type « que puis-je faire, moi ? »), mais « presque rien » n'est pas « rien », et 7.4 mesure la différence.


### 7.2 Un espace de noms dédié

#### 7.2.1 Ce que c'est et ce que ce n'est pas

Un **espace de noms** (*namespace*) est un groupe nommé à l'intérieur du cluster. La [documentation sur les espaces de noms](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) le dit en une phrase : les espaces de noms « fournissent un mécanisme pour isoler des groupes de ressources au sein d'un même cluster », et les noms de ressources doivent être uniques **à l'intérieur** d'un espace, pas entre espaces. Cela entraîne trois conséquences pratiques, qui sont celles qui comptent aujourd'hui :

- **Les noms n'entrent pas en collision.** L'équipe data peut avoir son propre Service appelé `revisor` dans son espace sans écraser le tien. Et le DNS le reflète : ce que la Leçon 3 appelait simplement `revisor` est en réalité `revisor.<espace>.svc.cluster.local`, et depuis un autre espace, il faut l'écrire en entier.
- **Les permissions ont une portée.** Un `Role` (7.4) vaut à l'intérieur d'un espace. Donner une permission sur les Pods de `revisor` ne donne pas de permission sur ceux de `default`.
- **Les règles se rattachent à un espace.** Les étiquettes de Pod Security Admission (7.3) et les politiques réseau (7.5) s'appliquent à l'espace où elles vivent.

Ce qu'il ne fait **pas**, même si le nom et les tutoriels le suggèrent : il ne ferme pas le réseau. La même page ne mentionne aucune isolation réseau, parce qu'elle n'existe pas : un Pod d'un espace peut parler à un Service d'un autre en écrivant simplement son nom complet. 7.5.3 le mesure, et c'est pourquoi la quatrième couche existe.

Tout ne vit pas à l'intérieur d'un espace. Tu peux poser la question au cluster, qui sait quels types appartiennent à un espace et lesquels valent pour tout le cluster :

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

La première liste, ce sont les types **sans** espace : les espaces de noms eux-mêmes, les nœuds, les volumes persistants, les classes de stockage, les rôles à portée de cluster (`clusterroles`) et leurs liaisons, et la `GatewayClass` que tu as créée dans la Leçon 6. La seconde, les types **avec** espace : les Pods, les Services, les Secrets, les comptes de service et, dans le groupe RBAC et réseau, les `roles`, les `rolebindings` et les `networkpolicies` de cette leçon. La règle pour s'en souvenir : ce qui décrit **une charge de travail** vit dans un espace ; ce qui décrit **l'infrastructure que toutes partagent** n'y vit pas. C'est pourquoi la `GatewayClass` `eg` ne migre pas aujourd'hui, et pourquoi MetalLB et Envoy Gateway, qui sont de la plateforme, restent dans `metallb-system` et `envoy-gateway-system`. Seul le projet migre.

#### 7.2.2 Ce qui change dans les manifestes

La migration se réduit à peu de changements, presque tous dans la `kustomization.yaml`. Lis-la en entier, avec son commentaire :

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

La ligne nouvelle qui fait le plus est `namespace: revisor`. Kustomize l'applique comme une transformation : à **tout** objet à espace de noms qui figure dans `resources`, elle écrit `metadata.namespace: revisor`, sans que tu le répètes dans chaque fichier. C'est pourquoi les Deployments, les Services et le `Gateway` n'ont pas changé une lettre de leur `metadata`. Les autres changements sont trois nouveaux fichiers dans la liste : `namespace.yaml` (l'espace lui-même, avec ses étiquettes, 7.3), `cuentas.yaml` (les comptes et les permissions, 7.4) et `red.yaml` (les six politiques, 7.5). Et les deux Deployments déclarent désormais leur compte de service et demandent au cluster de ne pas leur monter d'identifiants :

```yaml
    spec:
      serviceAccountName: revisor
      automountServiceAccountToken: false
```

(C'est un extrait : ce sont deux lignes de `revisor-deployment.yaml`, que 7.4 explique. Celui de `prueba` dit `prueba`.) Remarque aussi ce qui ne figure **pas** dans la liste : `revisor-publico.yaml`, le `LoadBalancer` direct de la Leçon 6. Son propre commentaire l'annonçait : à partir d'aujourd'hui, le seul point d'entrée vers l'extérieur est le `Gateway`. Le fichier est conservé dans `punto-de-partida/` comme référence.

#### 7.2.3 La migration

Un nouvel espace ne « déplace » pas d'objets ; les objets d'un espace ne peuvent pas être passés dans un autre. On les **supprime d'un côté et on les crée de l'autre**. D'abord on retire l'état de la Leçon 6 avec la même `kustomization` qui l'avait créé, puis on applique celle de cette leçon. Le token reste : c'est le même fichier pour les deux, et c'est pourquoi le Secret généré conserve son nom.

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

Lis les deux premiers blocs de haut en bas. Le `delete -k` supprime neuf objets, et chaque ligne dit **d'où** il les supprime (`from default namespace`). Le `apply -k` en crée vingt : l'espace (`namespace/revisor`), les trois comptes, le `Role` et son `RoleBinding`, le ConfigMap et le Secret avec le *hash* habituel, les deux Services, les deux Deployments, le point d'entrée et la route, et les six politiques réseau. Remarque l'ordre : l'espace sort en premier. Kustomize livre les objets avec les espaces de noms d'abord, et c'est pourquoi tu n'as pas eu besoin de deux étapes. Avec les types d'une nouvelle plateforme, comme `Gateway` dans la Leçon 6, l'attente reste à ta charge : là, il ne s'agit pas d'un ordre dans la liste mais de l'existence du type.

Tout est-il resté où il devait ?

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

`default` n'a gardé qu'une seule chose, le Service `kubernetes` que le cluster crée tout seul : l'espace est propre. Tout le projet est dans `revisor`, et le point d'entrée est servi depuis `envoy-gateway-system`, un troisième espace : **le point d'entrée ne vit pas là où vit le projet**. Note-le, parce que la politique réseau de 7.5 doit le laisser passer et cela se fait avec un `namespaceSelector`. Et une vérification depuis l'extérieur du cluster, comme dans la Leçon 6, pour voir que la migration n'a pas fermé le point d'entrée :

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Une dernière décision de la leçon. Le projet étant migré, le script retire les six politiques réseau :

```text
$ kubectl delete -n revisor -f red.yaml
networkpolicy.networking.k8s.io "cerrado" deleted from revisor namespace
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace
networkpolicy.networking.k8s.io "prueba-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace
```

Ce n'est pas une erreur ni une preuve qu'elles ne servent à rien. C'est pour étudier **une couche à la fois**. Les six politiques figurent dans la `kustomization.yaml` parce que l'état final du projet les inclut, mais si elles étaient en place pendant que tu étudies Pod Security et RBAC, chaque Pod d'exercice naîtrait sans pouvoir parler à l'API, et tu ne saurais pas si ce que tu vois vient d'une couche ou d'une autre. Elles reviennent en 7.5, avec leur explication.

### 7.3 Pod Security Admission

#### 7.3.1 Ce que c'est : un garde à l'entrée du `kube-apiserver`

Quand tu fais `kubectl apply`, ta requête traverse une chaîne de contrôles avant d'être enregistrée. L'un d'eux s'appelle l'**admission**. La [documentation de Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) le décrit : c'est un contrôleur qui examine chaque Pod sur le point d'être créé par rapport à un **standard** (les *Pod Security Standards*), et décide d'après une étiquette de l'espace de noms où il naîtrait. Il n'installe rien : il vient avec le `kube-apiserver`. Il se configure **avec des étiquettes de l'espace**, et ces étiquettes ont trois parties :

- **Le mode**, qui dit quoi faire face à une violation. Il y en a trois : `enforce` (« les Pods qui violent la politique sont rejetés »), `audit` (« une annotation est ajoutée au journal d'audit, mais le Pod est autorisé ») et `warn` (« l'utilisateur reçoit un avertissement, mais le Pod est autorisé »). Un espace peut en utiliser un, deux ou les trois, et même avec des niveaux différents.
- **Le niveau**, qui dit à quel point on exige. Les [standards de sécurité des Pods](https://kubernetes.io/docs/concepts/security/pod-security-standards/) en définissent trois. `privileged` est « délibérément ouvert et totalement sans restrictions ». `baseline` vise à « faciliter l'adoption pour les charges de travail courantes » tout en empêchant les escalades de privilèges connues. `restricted` est une politique « très restrictive », qui suit les pratiques actuelles de durcissement.
- **La version** (facultative), qui fixe à quelle édition du standard le Pod est comparé. Chaque version de Kubernetes peut affiner ce que demandent `baseline` et `restricted` ; avec `latest`, le standard évolue avec le cluster, et avec `v1.37` il reste figé.

L'étiquette a cette forme : `pod-security.kubernetes.io/<MODE>: <NIVEAU>` et, à part, `pod-security.kubernetes.io/<MODE>-version: <VERSION>`. Regarde comment l'espace de la leçon se présente avec les trois :

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

L'espace `revisor` utilise **les trois modes au même niveau**, `restricted`, et les trois figés sur `v1.37`. Les trois ensemble ont du sens : `enforce` est celui qui protège (il rejette), `warn` est celui qui t'avertit **à l'application** d'un Deployment, avant qu'il échoue (7.3.4), et `audit` laisse une trace dans le journal d'audit du `kube-apiserver`, que le cours n'active ni ne mesure. Le guide de la documentation pour appliquer ces niveaux à un espace montre la même répartition des rôles : `enforce` au niveau que tu respectes déjà, et `audit` et `warn` au niveau que tu veux atteindre, pour voir ce qui échouerait avant de l'exiger.

#### 7.3.2 Les trois niveaux, mesurés

Avant l'espace de la leçon, les trois niveaux face à face. On crée deux espaces de test, un `privileged` et un `baseline`, et à chacun (et à `revisor`) on demande d'accepter deux Pods, sans les créer : `--dry-run=server` envoie la requête complète au `kube-apiserver`, qui la valide avec tous ses contrôles d'admission et n'enregistre rien. Le premier Pod demande `hostNetwork: true`, c'est-à-dire utiliser le réseau du nœud plutôt que le sien, ce que `baseline` interdit déjà. Le second est un Pod `curl` écrit sans `securityContext`, comme dans n'importe quel tutoriel.

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

Le `kubectl wait --for=create` est une attente à laquelle tu ne t'attendais peut-être pas : chaque nouvel espace reçoit son compte `default` quelques instants **après** sa naissance, c'est un contrôleur qui le crée, et un Pod demandé avant que le compte existe est rejeté pour une autre raison (`serviceaccount "default" not found`). Lors d'une des exécutions d'essai de cette leçon (sans sortie conservée), sans cette attente, les six tests ci-dessous ont échoué avec ce message et non avec celui de la sécurité. C'est pourquoi l'attente est ici bien visible.

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

Les sorties sont tronquées à 260 caractères avec `cut` pour qu'elles tiennent ; le message complet, tu le vois en 7.3.3. Lis-les comme un tableau :

| Espace | `hostNetwork: true` | Pod sans `securityContext` |
|---|---|---|
| `nivel-privileged` | créé (`server dry run`) | créé |
| `nivel-baseline` | **rejeté** : `host namespaces (hostNetwork=true)` | créé |
| `revisor` (`restricted`) | **rejeté**, et pour plus de motifs | **rejeté** |

Trois choses. Première : `baseline` bloque ce que l'on sait dangereux (partager le réseau du nœud) et laisse passer un Pod normal, écrit sans soin. `restricted` exige en plus les bonnes pratiques, et c'est pourquoi le même Pod simple que `baseline` accepte est ici rejeté. Deuxième : le message de `nivel-baseline` dit `"baseline:latest"`, sans version. Comme cet espace n'a pas figé `enforce-version`, le standard est celui de la version du cluster, **quelle qu'elle soit** ; celui de `revisor` dit `"restricted:v1.37"`, figé. Si le cluster est mis à jour, le premier peut se mettre à rejeter ce qu'il acceptait avant ; le second ne change pas tant que tu ne changes pas l'étiquette. Troisième : le script supprime les deux espaces de test à la fin (`kubectl delete namespace`), ce qui supprime avec eux tout ce qu'ils contenaient.

```text
$ kubectl delete namespace nivel-privileged nivel-baseline
namespace "nivel-privileged" deleted
namespace "nivel-baseline" deleted
```

#### 7.3.3 `restricted`, lu ligne par ligne

Le Pod d'exercice qui a été rejeté deux fois plus haut est un Pod `curl` normal. Maintenant sans troncature, dans l'espace de la leçon :

```text
$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never -- sleep 60
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinreglas" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "sinreglas" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "sinreglas" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
[código de salida: 1]

$ kubectl get pods -n revisor -l run=sinreglas
No resources found in revisor namespace.
```

Le message a la forme « le Pod X ne peut pas être créé : il viole PodSecurity "restricted:v1.37" : » suivie d'une liste séparée par des virgules, et chaque élément est une règle non respectée avec, entre parenthèses, le champ qui la corrige. Quatre :

1. `allowPrivilegeEscalation != false` : le conteneur doit déclarer `securityContext.allowPrivilegeEscalation=false`. Sans cette ligne, un processus à l'intérieur pourrait gagner plus de privilèges que son processus parent (par exemple en exécutant un programme avec le bit *setuid*).
2. `unrestricted capabilities` : il doit déclarer `securityContext.capabilities.drop=["ALL"]`. Les *capabilities* de Linux sont de petits morceaux de ce que seul `root` faisait autrefois ; un conteneur qui ne demande rien reçoit un ensemble par défaut, et `restricted` exige de tout retirer.
3. `runAsNonRoot != true` : le Pod ou le conteneur doit déclarer `runAsNonRoot=true`. Il ne suffit pas que l'image *soit* celle d'un utilisateur normal : le manifeste doit **dire** qu'il l'exige, pour que le cluster rejette une image qui passerait un jour à `root`.
4. `seccompProfile` : il doit déclarer `seccompProfile.type` comme `RuntimeDefault` ou `Localhost`. `seccomp` est le filtre des appels au noyau ; le profil du *runtime* bloque les plus dangereux.

Et il n'a pas été rejeté pour une cinquième règle, `readOnlyRootFilesystem`, que le cours applique depuis la Leçon 2 : c'est une bonne pratique, mais le niveau `restricted` ne l'exige **pas**. C'est la différence entre ce que le cluster impose et ce que tu t'imposes. Chaque ligne de cette liste correspond à l'une des quatre que le `securityContext` du `revisor` porte depuis la Leçon 2 ; c'est pourquoi le `revisor` et `prueba` sont nés sans problème dans ce même espace. Et le `get pods` le confirme : `No resources found`. Le rejet intervient **avant** la création : le Pod n'existe pas, pas même à l'état d'erreur.

#### 7.3.4 Ce qu'on peut (et ne peut pas) durcir : `kube-system` et le `dry-run`

Pourquoi ne pas mettre `restricted` dans tous les espaces, sans réfléchir ? Le même `--dry-run=server` que tu as utilisé avec les Pods permet de voir ce qui se passerait avec une **étiquette** : il calcule par rapport aux Pods qui existent déjà et avertit, sans rien changer. On le teste avec deux espaces :

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

Avec `kube-system`, il y a quatre avertissements, un par groupe de Pods, et tous commencent par `Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"` : CoreDNS ne déclare ni `runAsNonRoot` ni `seccompProfile` ; `etcd`, `kindnet` et `kube-proxy` utilisent le réseau du nœud (`host namespaces`) et demandent des volumes de type `hostPath` (`restricted volume types`), et `kube-proxy` est en plus *privileged*. Ils les demandent parce que leur travail consiste à toucher le nœud. C'est pourquoi **un niveau ne s'applique pas par effet de mode** : on le mesure d'abord, et il y a des espaces (ceux du système) où `restricted` ne convient pas. Et le même `--dry-run` sur `revisor` dit `namespace/revisor not labeled (server dry run)` sans un seul avertissement : le projet respecte déjà ce qui est exigé.

Et les Pods qui tournaient déjà quand on pose l'étiquette ? La documentation dit que, lorsqu'on ajoute ou modifie une étiquette `enforce`, le contrôleur teste chaque Pod de l'espace par rapport à la nouvelle politique et renvoie les violations sous forme d'avertissements. Elle ne dit pas ce qu'il arrive au Pod. On le mesure avec un espace de test : il naît sans étiquettes, reçoit un Pod qui ne respecte pas `restricted`, et **ensuite** on lui pose `enforce=restricted`.

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

La ligne du `label` contient l'avertissement du contrôleur, qui nomme le Pod `viejo` et les règles qu'il viole. Et le `get pod` qui suit le laisse en `Running` : **l'étiquette a informé et n'a pas expulsé**. Le Pod `nuevo`, demandé avec le même manifeste, est rejeté. Poser `enforce` ne nettoie pas un espace ; cela ferme la porte à ce qui arrive à partir de ce moment. Un ancien Pod qui viole le niveau reste jusqu'à ce qu'il soit recréé (par exemple avec un `rollout restart`), et alors il ne peut plus naître. C'est un piège d'exploitation : dans un espace avec `enforce`, un redémarrage peut faire tomber un Deployment qui fonctionnait depuis des mois, si son modèle n'a jamais respecté le niveau.

Un autre test du même genre, cette fois avec le mode `warn`. On demande au `kube-apiserver`, sans appliquer le changement, de retirer une ligne du `revisor` (le profil `seccomp`) et de dire ce qu'il en pense :

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/securityContext/seccompProfile"}]' --dry-run=server
Warning: would violate PodSecurity "restricted:v1.37": seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/revisor patched

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}{"\n"}'
RuntimeDefault
```

Le correctif **est accepté** (`deployment.apps/revisor patched`, mais c'est un `--dry-run=server` : rien n'a été enregistré) et s'accompagne d'un avertissement sur une seule ligne : `would violate PodSecurity "restricted:v1.37": seccompProfile …`. Voilà ce qu'est `warn` : il avertit celui qui applique, sans rejeter. La deuxième commande confirme que le Deployment dit toujours `RuntimeDefault`. Et cette différence, « avertit » contre « rejette », est l'erreur suivante.

### L'erreur que tu vas voir

L'erreur de cette leçon est de celles qui déroutent le plus, parce que la commande se termine **bien** et que le service n'apparaît pas. On la provoque avec `fig07_01.sin-reglas.yaml`, un **programme** qui échoue exprès : un Deployment du `revisor` écrit comme dans un tutoriel, sans `securityContext`.

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

L'image tourne bien sans être `root` (utilisateur 65532), mais le manifeste ne le déclare pas, et c'est ce que vérifie le niveau `restricted`. On l'applique dans l'espace de la leçon :

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

Cela se lit dans l'ordre, du symptôme à la cause.

**D'abord, ce qu'a dit `apply`.** Deux lignes : un avertissement (`Warning: would violate PodSecurity "restricted:v1.37": …`) et `deployment.apps/sinreglas created`. **Il a été créé.** Le Deployment est un objet, pas un Pod, et il ne viole rien. L'avertissement vient du mode `warn`, qui examine bien le modèle de Pod que le Deployment porte à l'intérieur, pour te prévenir à l'avance. Si ton terminal ou ton *pipeline* n'affiche pas les avertissements, l'avis t'a ici échappé. Voici ce que dit la documentation : les modes `audit` et `warn` s'appliquent aussi aux ressources de charge de travail, mais **pas `enforce`** : il ne s'applique qu'aux Pods résultants.

**Ensuite, le symptôme.** Le `kubectl wait` attend une condition peu courante, `ReplicaFailure`, que le Deployment active quand son ReplicaSet ne peut pas créer de répliques, et il la trouve aussitôt. Puis : `READY 0/1`, `UP-TO-DATE 0`, `AVAILABLE 0`. Le ReplicaSet existe et demande 1 Pod, `DESIRED 1`, mais il a `CURRENT 0`. Et `get pods` dit `No resources found`. Le Deployment n'a jamais échoué à voix haute ; il n'a simplement pas de Pods.

**Enfin, la cause.** Elle se trouve dans les événements du ReplicaSet, pas dans ceux du Deployment ni dans ceux du Pod (qui n'existe pas) : `Warning FailedCreate … replicaset-controller Error creating: pods "sinreglas-…" is forbidden: violates PodSecurity "restricted:v1.37": …`. C'est le même message qu'en 7.3.3, mais cette fois c'est le contrôleur qui le reçoit, l'enregistre et réessaie. C'est pourquoi il faut chercher dans le **ReplicaSet**.

**La correction.** On corrige le manifeste, pas l'espace : un `securityContext` comme celui du `revisor` et du service de test, avec les quatre lignes de 7.3.3. Ici, comme le Deployment ne servira pas, on le supprime.

```text
$ kubectl delete -n revisor -f fig07_01.sin-reglas.yaml
deployment.apps "sinreglas" deleted from revisor namespace
```

**L'ordre à suivre quand un Deployment n'a pas de Pods :**

1. `kubectl get deployment` : `READY 0/N` ?
2. `kubectl get replicaset -l app=…` : `CURRENT` inférieur à `DESIRED` ?
3. `kubectl describe replicaset` : les événements, `FailedCreate`, et le motif complet.
4. Si c'est écrit `PodSecurity`, on ne baisse pas le niveau de l'espace ; on corrige le manifeste.


### 7.4 Comptes de service et permissions minimales

#### 7.4.1 Ce qu'est un compte de service

Quand tu fais `kubectl get pods`, l'API sait qui tu es grâce à ton `kubeconfig`. Quand un **programme qui tourne dans le cluster** parle à l'API (un contrôleur, un outil de déploiement, un service qui a besoin de savoir quels autres Pods existent), l'API a elle aussi besoin de savoir qui il est. Cette identité s'appelle un **compte de service** (*ServiceAccount*). La [documentation](https://kubernetes.io/docs/concepts/security/service-accounts/) le définit comme « un type de compte non humain qui, dans Kubernetes, fournit une identité distincte au sein du cluster ». Il a trois propriétés qui comptent ici :

- **C'est un objet à espace de noms**, comme un Pod. Il s'appelle `revisor` dans l'espace `revisor`, et son nom complet pour RBAC a la forme `system:serviceaccount:<espace>:<compte>`, ce qui, pour le compte `revisor` de l'espace `revisor`, donne `system:serviceaccount:revisor:revisor` (le nom se répète parce qu'ils coïncident). Tu vas l'écrire en 7.4.3.
- **Tout espace naît avec un compte appelé `default`.** Le cluster le crée tout seul (la section 7.3.2 vient de l'attendre) et l'attribue à tout Pod qui n'en demande pas un autre. Par défaut, il n'a pas de permissions au-delà de la découverte de base de l'API.
- **Par défaut, le cluster monte ses identifiants dans chaque Pod.** La même page : « par défaut, Kubernetes donne au Pod les identifiants du compte attribué ». Depuis la version 1.22, c'est un token à courte durée de vie qui se renouvelle tout seul, fourni sous forme de volume projeté ; auparavant, c'était un Secret à longue durée de vie. C'est le volume `kube-api-access-…` que tu as vu en 7.1.3 : le Pod peut lire son token dans un fichier et se présenter avec lui devant l'API.

Le fait du dernier point est l'important. **Si un programme dans un Pod est compromis, sa première question est « que puis-je faire avec le token que j'ai ? »**, et cet identifiant est monté même si le programme ne l'utilise jamais. Pour le `revisor` et pour `prueba`, qui ne parlent pas à l'API, c'est un risque sans le moindre avantage. C'est pourquoi les deux Deployments de la leçon déclarent `automountServiceAccountToken: false`. Le [guide des comptes de service](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) explique qu'on peut le désactiver sur le compte ou sur le Pod, et que si les deux disent quelque chose, c'est le Pod qui l'emporte.

#### 7.4.2 Les permissions : `Role` et `RoleBinding`

Un compte tout juste créé ne peut rien. Les permissions s'ajoutent avec deux objets. La [documentation de RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (contrôle d'accès basé sur les rôles) les sépare ainsi : un `Role` « contient des règles qui représentent un ensemble de permissions », et les permissions sont **purement additives** : il n'y a pas de règles de « refus ». Un `Role` « fixe toujours des permissions à l'intérieur d'un espace de noms ». Son cousin `ClusterRole` est la même chose mais sans espace, pour des ressources qui n'en ont pas (les nœuds, par exemple) ou pour répéter un ensemble de règles dans plusieurs espaces. Un `RoleBinding` est la colle : il « accorde les permissions définies dans un rôle à un ensemble de sujets » (utilisateurs, groupes ou comptes de service), à l'intérieur d'un espace. Deux objets et non un seul parce que le rôle s'écrit une fois et peut être lié à de nombreux comptes.

Chaque règle d'un `Role` a trois parties : `apiGroups` (le groupe de l'API : `""` est le cœur, où vivent les Pods et les Services ; `apps` est l'endroit où vivent les Deployments), `resources` (les types) et `verbs` (ce qu'on peut faire : `get` lire un objet, `list` lister, `watch` rester à l'écoute des changements, et ceux qui modifient, `create`, `update`, `patch` et `delete`). Lis-le dans `cuentas.yaml`, en entier :

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

Trois comptes et une paire d'objets de permissions. `revisor` et `prueba` sont des comptes **sans permissions** : aucun `RoleBinding` ne les mentionne, et tous deux portent aussi `automountServiceAccountToken: false` au niveau du compte. `observador` est le compte de lecture : le `Role` `observador` lui donne `get`, `list` et `watch`, uniquement ces trois verbes, sur les Pods, leurs journaux (`pods/log`, une sous-ressource), les Services et les événements du cœur, et sur les Deployments et ReplicaSets du groupe `apps`. Remarque ce qui n'y est **pas** : les Secrets (le token du `revisor` est un Secret), `create`, `update`, `patch`, `delete`, `exec` (`pods/exec` est une autre sous-ressource, et elle n'est pas listée) et tout ce qui est hors de l'espace. La règle de conception est « ce dont il a besoin, et rien de plus », et elle s'écrit en nommant chaque ressource, sans caractères génériques (`*`), parce qu'un caractère générique inclut ce que le cluster ajoutera un jour.

Le `RoleBinding` dit **à qui** on le donne : le compte `observador` de l'espace `revisor`. Pourtant, ce compte n'est utilisé par aucun Deployment de la leçon. Il existe pour qu'on voie ce que veut dire « lecture seule » avec un vrai compte, et pour l'Exercice 2.

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

Cela se lit ainsi : quatre comptes, pas trois. Le quatrième, `default`, a été créé par le cluster tout seul. Et le tableau des Pods indique, pour chacun, avec quel compte il tourne, que `AUTOMOUNT` vaut `false` et quels volumes il a : `datos` et `token` dans le `revisor`, aucun dans `prueba`, et **aucun des deux n'a le `kube-api-access-…` de 7.1.3**. Par rapport à l'« avant », ce volume a disparu.

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

#### 7.4.3 Demander sans essayer : `kubectl auth can-i`

Comment savoir ce qu'un compte peut faire ? On le demande à l'API avec `kubectl auth can-i`, qui répond `yes` ou `no`. Pour interroger une **autre** identité, on utilise `--as`, qui fait usurper à `kubectl` cette identité dans la requête ; le compte de service s'écrit avec son nom complet, `system:serviceaccount:<espace>:<compte>`. (Usurper une identité est une permission que tu as en tant qu'administrateur de ton cluster kind ; un utilisateur ordinaire d'un cluster réel ne l'aurait pas.) D'abord le `revisor`, qui ne doit rien pouvoir faire, et l'`observador`, qui doit pouvoir lire :

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

La liste du `revisor` n'est pas vide, et il faut la lire avec précaution. Les quatre lignes sont des permissions que presque toute identité reçoit par défaut. Trois sont des *revues sur soi-même* : `selfsubjectreviews` (qui suis-je ? d'après `kubectl explain`, il renvoie les informations d'utilisateur que le `kube-apiserver` détient sur celui qui demande), `selfsubjectaccessreviews` (puis-je faire ceci ? c'est la question que pose `can-i` lui-même) et `selfsubjectrulesreviews` (quelles actions puis-je faire dans cet espace ?). La quatrième, `clustertrustbundles`, ce sont des paquets de certificats racine publics ; la description du type dit que tous les comptes de service peuvent les lire par défaut. Les rôles qui donnent les trois premières viennent avec le cluster (`system:basic-user`, que la documentation décrit comme un accès en lecture seule aux informations de base sur soi-même, lié au groupe `system:authenticated`). Aucune n'est une permission sur **tes** objets. La question qui compte, `get pods`, répond `no`, avec le code de sortie 1 : `kubectl auth can-i` renvoie 0 quand la réponse est `yes` et 1 quand elle est `no`, ce qui permet de l'utiliser dans un script. L'`observador` répond `yes` pour lire les Pods et pour lire leurs journaux (`--subresource=log`). Maintenant, ce qu'il ne doit **pas** pouvoir faire :

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

Trois `no` : il ne peut pas supprimer de Pods (le `Role` n'inclut pas `delete`), il ne peut pas lire les Secrets (ils ne sont pas dans la liste) et il ne peut pas lire les Pods de `default` (le `Role` et le `RoleBinding` vivent dans `revisor` ; un rôle d'espace ne passe pas dans un autre). C'est la preuve directe que l'espace de noms est bien l'unité des permissions, même s'il ne l'est pas du réseau.

`can-i` pose la question ; la vraie requête confirme. Avec `--as`, `kubectl` effectue l'opération comme s'il était ce compte :

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

Lister les Deployments fonctionne. Supprimer un Pod et lister les Secrets donnent `Error from server (Forbidden)`, et cela vaut la peine de lire le message complet, parce qu'il a la forme des erreurs RBAC et que c'est ce que tu verras le jour où quelque chose échouera : `secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"`. Qui (`User "system:serviceaccount:revisor:observador"`), quel verbe et sur quoi (`cannot list resource "secrets"`), dans quel groupe de l'API (`""`, le cœur) et dans quel espace. Avec ces cinq éléments, tu sais exactement quelle règle ajouter si la permission était légitime, ou quoi laisser tel quel dans le cas contraire. Un détail : le verbe du deuxième message est `list`, pas `get` ; tu as demandé « tous les Secrets » et c'est `list`. En lire un par son nom, c'est `get`. Les deux verbes sont séparés exprès.

#### 7.4.4 La même chose, depuis l'intérieur d'un Pod

Jusqu'ici, tout a été testé en usurpant une identité depuis ton terminal. Il manque le test qui ressemble le plus à une attaque : un programme **dans** un Pod, avec ce que le Pod a sous la main. On utilise trois Pods d'appui, tous `curl` : `depurar` (celui de la Leçon 3, avec l'étiquette `acceso-revisor: permitido` dont le réseau va avoir besoin), `intruso` (identique mais **sans** cette étiquette ; c'est le Pod de l'équipe data de la scène) et `lector`, un nouveau qui porte le compte `observador` **avec le token monté**. Les trois respectent `restricted`, comme tout ce qui naît dans cet espace. Lis `fig07_04.lector.yaml` :

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

C'est une exception délibérée à la règle de 7.4.1 : `automountServiceAccountToken: true`, qui est la valeur par défaut écrite à voix haute. Il existe pour montrer ce qu'un token monté permet. Lis-le en regard de la liste d'`intruso`, qui utilise le compte `default` **sans** token (`depurar` et `intruso` le déclarent désactivé) :

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

Le `lector` a trois fichiers dans `/var/run/secrets/kubernetes.io/serviceaccount` : `ca.crt` (le certificat avec lequel reconnaître l'API), `namespace` (son espace) et `token` (son identifiant). Avec eux, `curl` se présente devant l'API avec l'en-tête `Authorization: Bearer <token>`. L'adresse est `https://kubernetes.default.svc`, le nom du Service `kubernetes` de `default`, qui est le point d'entrée de l'API pour les Pods. Quatre requêtes :

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

Un `200` et trois `403`. Avec le token d'`observador`, le `lector` **peut** lister les Pods de `revisor` (la permission que nous lui avons donnée), et il **ne peut pas** lister les Secrets du même espace ni les Pods de `default`. Le quatrième bloc est la même requête de Secrets avec la réponse brute filtrée : c'est le JSON d'erreur de l'API, avec le même message que tu as vu avec `--as`. C'est ce que RBAC promet, mais vu du côté de celui qui attaque : un token volé d'`observador` a la portée du `Role` et pas une ressource de plus. C'est pourquoi le `Role` s'écrit court.

Et maintenant le Pod qui n'a **pas** de token :

```text
$ kubectl exec -n revisor intruso -- sh -c '/bin/ls /var/run/secrets/kubernetes.io; echo código=$?' 2>&1
ls: /var/run/secrets/kubernetes.io: No such file or directory
código=1

$ kubectl exec -n revisor intruso -- sh -c 'curl -s -k https://kubernetes.default.svc/api/v1/namespaces/revisor/pods | grep -E "message|code"'
  "message": "pods is forbidden: User \"system:anonymous\" cannot list resource \"pods\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

Le répertoire n'existe pas : `ls: /var/run/secrets/kubernetes.io: No such file or directory`. L'`intruso` n'a même pas un identifiant à présenter. S'il parle quand même à l'API (`curl -k`, qui ne vérifie pas le certificat, uniquement pour ce test), l'API le reçoit comme `system:anonymous`, l'identité de qui ne s'identifie pas, et lui répond `403` : `pods is forbidden: User "system:anonymous" cannot list resource "pods"`. Zéro permission et zéro identifiant ; c'est l'état que tu veux pour tout Pod qui ne parle pas à l'API. (Que l'API réponde `403` signifie que l'`intruso` **est bien arrivé** jusqu'à l'API : la seule chose qui l'arrête ici, c'est RBAC. Ce qui l'empêcherait même d'y arriver, c'est le réseau, et 7.5 le mesure.)


### 7.5 Le réseau : ouvert jusqu'à ce que quelqu'un le ferme

#### 7.5.1 Le modèle, avant de toucher à quoi que ce soit

La [documentation des politiques réseau](https://kubernetes.io/docs/concepts/services-networking/network-policies/) décrit le modèle en trois phrases qu'il convient d'apprendre par cœur, parce que tout le reste en découle :

- **Par défaut, un Pod n'est pas isolé.** « Par défaut, un Pod n'est pas isolé en sortie ; toutes les connexions sortantes sont autorisées », et de même pour l'entrée : « toutes les connexions entrantes sont autorisées ». C'est l'état dans lequel se trouvent tes Pods aujourd'hui.
- **Un Pod est isolé quand une politique le sélectionne.** « Un Pod est isolé en sortie s'il existe une `NetworkPolicy` qui le sélectionne et qui a `Egress` dans ses `policyTypes` », et de façon équivalente pour l'entrée avec `Ingress`. Les deux directions s'isolent séparément. Une politique qui ne dit que `Ingress` ne touche pas à la sortie.
- **Les politiques s'additionnent.** « Les politiques réseau n'entrent pas en conflit ; elles sont additives. » Si plusieurs politiques s'appliquent à un Pod dans une direction, ce qui est autorisé est l'**union** de ce que chacune autorise. L'ordre n'a pas d'importance. Et il n'existe pas de règle de « refus » : ce qu'aucune n'autorise est interdit, mais seulement pour les Pods déjà isolés.

Une politique a quatre parties : un `podSelector` (à quels Pods **de l'espace** elle s'applique ; `{}` signifie tous), des `policyTypes` (si elle isole l'entrée, la sortie ou les deux), et des listes `ingress` et `egress` de ce qui est **autorisé**, chacune avec un `from` ou un `to` (d'où ou vers où) et des `ports`. Et le `from` ou le `to` peut être trois choses : un `podSelector` (Pods de **cet** espace), un `namespaceSelector` (tous les Pods des espaces choisis) ou, ensemble dans le même élément, les deux (Pods choisis d'espaces choisis). Un détail qui mord : le `from` est une liste, et chaque élément de la liste est une alternative (un **ou**) ; ce qui se trouve à l'intérieur d'un même élément se combine avec **et**.

Et la condition qui compte le plus : la documentation elle-même avertit que « les clusters doivent utiliser un plugin réseau qui prend en charge `NetworkPolicy` » et que « créer une ressource `NetworkPolicy` sans contrôleur qui l'implémente n'a aucun effet ». Le cluster enregistre ta politique sans se plaindre, et le trafic continue de passer. C'est une défaillance silencieuse. C'est pourquoi le plan du cours disait « si le plugin réseau de kind ne l'applique pas, on en installe un autre ». On le mesure, on ne le suppose pas.

#### 7.5.2 Qui les applique dans kind ?

Les nœuds de kind utilisent par défaut un plugin réseau appelé `kindnetd` (la [configuration de kind](https://kind.sigs.k8s.io/docs/user/configuration/) le décrit comme une implémentation réseau simple basée sur des plugins CNI standard ; *CNI* est l'interface par laquelle Kubernetes demande à un plugin de fournir du réseau aux Pods). On demande au cluster ce qui tourne :

```text
$ kubectl get daemonset -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kindnet      3         3         3       3            3           kubernetes.io/os=linux   17m
kube-proxy   3         3         3       3            3           kubernetes.io/os=linux   17m

$ kubectl get daemonset kindnet -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
docker.io/kindest/kindnetd:v20260820-69b56db7
```

Il y a un DaemonSet `kindnet` avec un Pod par nœud, et son image est `kindest/kindnetd:v20260820-69b56db7`. Savoir lequel c'est ne dit pas s'il applique des politiques. Les notes de version de [kind v0.24.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0) annoncent, parmi leurs points principaux, la « prise en charge des politiques réseau avec `sigs.k8s.io/kube-network-policies` ». Voilà ce que dit le papier. Ce qui compte, c'est ce que mesure ton cluster, et pour le mesurer il faut un témoin : deux Pods `curl` qui ne figurent sur la liste de personne.

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

Il y a un `intruso` dans `revisor` et un autre dans `default` : celui de l'espace dédié est le Pod de l'équipe data de la scène ; celui de `default` est une autre équipe quelconque du cluster. Les deux sont nés sans l'étiquette `acceso-revisor`. `depurar` l'a (`permitido`) ; `intruso` et `lector` non, et le tableau le dit avec la colonne vide. Cela compte en 7.5.4.

#### 7.5.3 Sans règles : ce que l'espace de noms n'isole PAS

Avec les six politiques retirées (7.2.3), voici ce que peut faire l'`intruso` de `revisor`, et ce que peut faire celui de `default` :

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

On lit quatre réponses, et les quatre sont de mauvaises nouvelles :

1. L'`intruso` parle au `revisor` et reçoit son `/salud`. Sans le token, il ne peut pas demander le rapport (il obtient `401`), mais il est arrivé.
2. Il parle à `prueba:9000`, qui n'est pas à lui, et reçoit `sano`, le mode du service de test. Avec un `POST` sur `/modo/caido`, il pourrait le mettre en `caido` : le service de test **n'a pas d'authentification** et le réseau ne le protège pas.
3. Il parle à l'API du cluster, sur `/livez`, et elle répond `ok`. Ce chemin de contrôle de santé (health check) répond sans identifiants exprès (la documentation de RBAC l'appelle une information non sensible, le rôle `system:public-info-viewer`), donc la réponse n'est pas un défaut de l'API. Ce qui compte, c'est autre chose : un Pod quelconque a une **route réseau** jusqu'au `kube-apiserver` (par le Service `kubernetes`, port 443), et personne ne la lui a retirée.
4. L'`intruso` de `default` atteint le `revisor` de `revisor` en écrivant le nom complet du Service, `revisor.revisor.svc.cluster.local`. **Deux espaces de noms distincts, et pas un mur entre eux.** C'est ce que la documentation sur les espaces de noms n'affirme pas et que beaucoup supposent.

C'est la réponse à la deuxième question de 17 h 58, et ce n'est pas celle que tu voulais : oui, un Pod de l'équipe data peut parler au `revisor` sans passer par le point d'entrée.

#### 7.5.4 Tout fermé

La première politique ferme tout, sans aucune ouverture. C'est un **programme** court :

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

`podSelector: {}` sélectionne tous les Pods de l'espace, et `policyTypes: [Ingress, Egress]` les isole dans les deux directions. Comme il n'y a ni liste `ingress` ni liste `egress`, rien n'est autorisé. On l'applique et on mesure la même chose qu'avant :

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

Tout a cessé de fonctionner, et il convient de séparer trois signaux qui se ressemblent. `command terminated with exit code 28` est le code de `curl` pour **délai dépassé** : il n'y a pas eu de réponse dans les 3 secondes que tu lui as données avec `-m 3`. Un `curl` contre une politique qui abandonne les paquets ne reçoit pas de refus, seulement du silence. C'est différent de `connection refused` (code 7, où quelqu'un te répond « il n'y a rien ici », ce que tu as vu dans les Leçons 3 et 5) et d'un `403` (où quelqu'un qui t'a bien entendu te dit non). Il y a trois sortes de « non » et on les distingue par le code. Deuxième signal : `depurar`, le Pod **avec** l'étiquette, n'arrive pas non plus. Tu n'as encore rien ouvert. Troisième : le `nslookup` a lui aussi dépassé le délai, `;; connection timed out; no servers could be reached`. **La résolution de noms est du trafic réseau** qui sort du Pod vers le DNS du cluster, et la politique `cerrado` a aussi fermé cela. Avec la sortie fermée, les Pods de l'espace ne peuvent pas demander qui est `revisor`.

Entre l'`apply` et les tests, il y a une attente de 8 secondes (`$ sleep 8`, visible dans la sortie complète de `correr.salida.txt`) ; 7.5.7 mesure le temps que met une politique à être programmée, et c'est de là que vient la marge.

Il y a d'autres effets, qui se mesurent avec trois commandes depuis ta machine et une depuis le Pod qui lit l'API :

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

Le point d'entrée n'entre plus : le client extérieur reçoit `000` et le code 28. La politique `cerrado` isole l'entrée de **tous** les Pods de l'espace, y compris le `revisor`, et les Pods d'Envoy (qui vivent dans un autre espace) n'ont plus la permission de lui parler. Le `port-forward`, en revanche, **continue de fonctionner** : le tunnel s'est ouvert et le `revisor` a répondu. (Le [guide de `port-forward`](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) ne décrit pas par quel chemin il voyage ; en revanche, il dit quelque chose d'utile pour cette leçon : l'accès à `port-forward` est contrôlé par RBAC, avec la permission `create` sur `pods/portforward`, donc celui qui l'a entre dans le Pod même si le réseau est fermé.) Mais ce que le `revisor` répond n'est plus le rapport complet : le tableau dit `prueba FALLA` avec le détail `se acabo el tiempo de espera`, parce que le `revisor` ne peut pas sortir interroger `prueba`. La sortie du `revisor` lui-même est elle aussi fermée. Et le `lector`, le Pod avec un token valide, n'atteint plus l'API : `pods 000`, code 28. **Le réseau fermé protège l'API de celui qui a la permission.** RBAC dit ce que tu *peux* demander ; le réseau dit où tu *arrives*. Les deux doivent dire oui.

Un doute raisonnable à ce stade : si tout est fermé, les probes ne devraient-elles pas échouer ? Elles n'échouent pas. Les probes sont exécutées par le `kubelet` du nœud (Leçon 5), et la documentation des politiques réseau dit que, lorsqu'un Pod est isolé en entrée, « les seules connexions autorisées vers le Pod sont celles qui viennent du nœud du Pod et celles que permet la liste `ingress` d'une politique ». Le trafic du nœud lui-même échappe au filtre. On le vérifie avec les six règles en place, 45 secondes plus tard, en 7.5.5.

#### 7.5.5 Les ouvertures nécessaires

Voyons maintenant les cinq autres politiques, qui, avec `cerrado`, forment `red.yaml`. Lis-les une par une avant de les appliquer ; chacune a un commentaire qui dit à qui elle ouvre et pourquoi :

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

Dans l'ordre :

- **`cerrado`** : celle du dessus. Avec `podSelector: {}` et les deux types, elle laisse tous les Pods de l'espace sans entrée ni sortie.
- **`dns`** : elle ouvre la **sortie** de tous les Pods vers le DNS. La destination s'écrit avec les deux conditions ensemble dans un seul élément (`namespaceSelector` **et** `podSelector`) : les Pods portant l'étiquette `k8s-app: kube-dns` de l'espace `kube-system`. Les ports sont 53 en UDP et en TCP. L'espace est sélectionné avec l'étiquette `kubernetes.io/metadata.name`, que le cluster pose tout seul sur tout espace, avec son nom ; la documentation avertit qu'on ne peut pas écrire directement le nom d'un espace dans une politique et que cette étiquette existe pour cela.
- **`revisor-salida`** : la **sortie** du `revisor` vers les Pods `app: prueba`, uniquement sur le port 9000. C'est la seule chose dont le `revisor` a besoin sur le réseau : interroger `prueba`.
- **`prueba-entrada`** : l'**entrée** de `prueba`, uniquement depuis les Pods `app: revisor`, et uniquement sur le 9000. La politique de sortie du `revisor` et celle d'entrée de `prueba` sont les deux moitiés d'une même porte : pour que le trafic passe, les deux directions doivent dire oui.
- **`revisor-entrada`** : l'**entrée** du `revisor`, sur le port 8080, depuis deux origines (deux éléments de `from`, donc l'un **ou** l'autre) : les Pods portant l'étiquette `acceso-revisor: permitido` (de cet espace) et **tous les Pods** de l'espace `envoy-gateway-system`, où vit le point d'entrée de la Leçon 6.
- **`acceso-revisor-salida`** : la **sortie** des Pods portant l'étiquette `acceso-revisor: permitido` vers le `revisor`, port 8080. C'est la jumelle de la précédente. Elle existe à cause d'une leçon qu'a coûtée une première version de ce réseau : n'ouvrir que l'entrée du `revisor` ne suffit pas, parce que `cerrado` ferme aussi la sortie de celui qui veut lui parler.

Deux observations avant de les appliquer. L'étiquette `acceso-revisor: permitido` joue le rôle de **clé** : qui la porte peut parler au `revisor`, et c'est celui qui a la permission de créer des Pods dans l'espace qui la pose sur un Pod. C'est pourquoi l'étiquette n'est pas un secret mais un accord, et 7.5.8 le commente. Et les politiques utilisent le port `8080`, celui du conteneur, **pas** le 80 du Service. Ce n'est pas une décision propre à ce cluster : la [référence de l'API](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/) définit le champ `port` d'une politique comme « un port numérique ou nommé d'un Pod ». Le Service a déjà choisi la réplique et traduit le port avant que la politique regarde le paquet ; la politique voit la destination finale. Ici, on a mesuré que kindnet le respecte (sinon `depurar` ne serait pas arrivé), et dans un autre cluster il vaut la peine de le mesurer de la même façon, parce que ce que l'on vérifie, c'est que le plugin applique l'API, pas quel port fait foi.

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

`cerrado` est sorti `unchanged` (il était déjà là) et les cinq autres `created`. Le `describe` de `revisor-entrada` le lit en langage clair : « autorisant le trafic entrant sur le port 8080/TCP, depuis (PodSelector : `acceso-revisor=permitido`) et depuis (NamespaceSelector : `kubernetes.io/metadata.name=envoy-gateway-system`) ; sans affecter la sortie ; type de politique : Ingress ». Les deux `From:` sont les deux alternatives. Et celui de `cerrado` répète, avec d'autres mots, ce que tu savais déjà : « Pods sélectionnés : isolés en entrée et en sortie ».

Maintenant le test, avec les mêmes commandes que d'habitude :

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

Six résultats, un par question :

- **`depurar` (avec l'étiquette) atteint le `revisor`** et reçoit son `/salud`, et avec le token il reçoit le rapport complet : `prueba OK`. Cela veut dire que le `revisor` peut de nouveau sortir vers `prueba` et que `prueba` l'accepte. Ce sont les deux moitiés.
- **`intruso` (sans l'étiquette) n'arrive pas** : code 28. La réponse à la deuxième question de 17 h 58 est maintenant « non ».
- **`depurar` n'atteint pas `prueba:9000`** : code 28. L'étiquette ouvre le chemin vers le `revisor`, pas vers le service de test. Un Pod qui a la clé du `revisor` n'est pas un Pod qui a la clé de tout.
- **`intruso` n'atteint pas l'API** : `curl` dépasse le délai. La troisième question a désormais un mur avant RBAC.
- **Le DNS répond** : l'`intruso` résout `revisor.revisor.svc.cluster.local` en l'IP du Service. Un Pod sans clé peut demander des noms (la règle `dns` vaut pour tous) et reçoit une réponse, mais il ne peut pas se connecter à ce qu'il trouve. Que le DNS fonctionne ne veut pas dire que le chemin soit ouvert.
- **L'`intruso` de `default` n'arrive pas non plus** : le nom complet du Service ne lui sert plus à rien.

Et les routes légitimes qui auraient pu casser :

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ curl -s -m 5 http://127.0.0.1:18087/salud   # por port-forward
{"estado":"vivo","version":"1.6.0"}
```

Le point d'entrée répond de nouveau depuis l'extérieur, parce que `revisor-entrada` admet les Pods de `envoy-gateway-system`. Et le `port-forward` fonctionne toujours. Maintenant, avec toutes les règles en place, une attente de 45 secondes, celle de quelques tours des probes de la Leçon 5, et un coup d'œil aux Pods :

```text
$ sleep 45

$ kubectl get pods -n revisor -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-6899c74865-rgh68    1/1     Running   0          7m15s
revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          7m15s
```

`RESTARTS 0` sur les quatre, `1/1`. Le réseau fermé n'a **pas** fait tomber les probes, et la raison est celle de la documentation que tu viens de lire : c'est le `kubelet` qui les exécute, depuis le nœud.

#### 7.5.6 À quoi sert chaque règle : on en retire une, on mesure, on la remet

Lire une politique dit ce qu'elle *devrait* faire. Pour savoir ce qu'elle fait, on la retire du cluster, **une à la fois**, et on mesure quatre choses depuis le même endroit : `depurar` demande `/salud` au `revisor` ; `depurar` demande le rapport (ce qui oblige le `revisor` à sortir vers `prueba`) ; `depurar` résout le nom du `revisor` ; et le client extérieur demande `/salud` par le point d'entrée. Puis on réapplique `red.yaml` et on passe à la suivante. Le `nslookup` de ce tableau se fait avec un `sh -c` qui affiche la dernière ligne utile, ou `sin respuesta`, pour que cela tienne sur une ligne.

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

Voilà la première : sans `dns`, le nom `revisor` ne se résout pas, donc la requête sur `/salud` et celle du rapport dépassent le délai (code 28), et le `nslookup` aussi. Le point d'entrée, en revanche, répond `200` : ce qui a été mesuré, c'est qu'Envoy atteint le `revisor` même si le DNS est fermé pour les Pods de l'espace ; comment Envoy trouve les répliques relève d'Envoy Gateway, et le cours ne l'a pas mesuré. Les quatre autres se lisent de la même façon. Le tableau complet :

| Règle retirée | `depurar` → `/salud` | `depurar` → rapport | Résoudre le nom | Depuis l'extérieur, `/salud` |
|---|---|---|---|---|
| `dns` | 28 (délai dépassé) | 28 | délai dépassé | 200 |
| `revisor-salida` | 200 | `prueba FALLA`, délai dépassé | répond | 200 |
| `prueba-entrada` | 200 | `prueba FALLA`, délai dépassé | répond | 200 |
| `revisor-entrada` | 28 | 28 | répond | **000** (28) |
| `acceso-revisor-salida` | 28 | 28 | répond | 200 |
| (les six en place) | 200 | `prueba OK` | répond | 200 |

Chaque ligne raconte quelque chose de différent. Retirer `revisor-entrada` est la seule qui fait tomber le point d'entrée, parce que c'est celle qui laisse passer Envoy. Retirer `acceso-revisor-salida` laisse `depurar` sans sortie, mais le point d'entrée continue (dans ce cluster, personne n'a créé de politiques dans l'espace d'Envoy, donc sa sortie n'est pas fermée). Retirer `revisor-salida` ou `prueba-entrada` produit **le même symptôme**, `prueba FALLA` par délai dépassé, avec des causes différentes : dans un cas le `revisor` ne peut pas sortir, dans l'autre `prueba` ne peut pas recevoir. Et un symptôme comme celui-là ne dit pas laquelle des deux politiques manque. C'est le genre de panne pour lequel `describe networkpolicy` est utile.

Les blocs complets des cinq tests, avec leurs commandes, se trouvent dans `correr.salida.txt`. Voici le passage qui a une histoire, celui de `revisor-salida`. Lors d'une exécution précédente, qui n'a pas été conservée, cette ligne était sortie `prueba OK` même sans la règle. On n'a pas pu la reproduire (dans cette exécution, elle est sortie `FALLA` du premier coup) et nous n'en connaissons pas la cause. Il y a deux explications possibles et aucune n'a été vérifiée. L'une : une connexion déjà ouverte est restée vivante alors que la règle avait été retirée ; la documentation des politiques réseau laisse ce cas à chaque plugin (« c'est défini par l'implémentation » si le changement prend effet sur une connexion existante) et recommande de ne pas modifier les politiques d'une façon qui les affecte. L'autre : la politique n'était pas encore programmée, ce que mesure 7.5.7. C'est pourquoi le script attend, et ici il **redémarre en plus le `revisor`**, pour que le test ouvre une nouvelle connexion :

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

Les deux rapports disent `prueba FALLA` : celui d'avant le redémarrage et celui d'après. Dans cette exécution, le redémarrage n'a pas changé le résultat (le rapport disait déjà `FALLA` avant) ; c'est une précaution de méthode, pas une preuve de la cause.

La morale est de méthode, et elle vaut plus que le tableau. **Un résultat qui dit « ça fonctionne toujours » après avoir retiré une règle ne prouve pas que la règle était superflue.** Ce peut être une vieille connexion, un cache, ou un test qui ne demande pas ce que tu crois. Un test réseau doit ouvrir une nouvelle connexion à chaque fois.

### L'erreur que tu vas voir (la deuxième)

La deuxième erreur est celle qui fait perdre le plus de temps avec les politiques réseau. Elle ressemble à la scène, mais en petit : tu as une politique qui **ouvre** l'entrée du `revisor`, tu as un Pod avec la bonne étiquette, et le Pod n'arrive pas. On la provoque en supprimant la dernière politique, `acceso-revisor-salida`, la jumelle de l'entrée :

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

Cela se lit dans cet ordre. **D'abord, le symptôme :** code 28, délai dépassé ; le Pod a l'étiquette `acceso-revisor=permitido` et la politique `revisor-entrada` existe. Tout ce que tu regardes dit que cela devrait passer. **Ensuite, la liste des politiques :** il y a `cerrado`, `dns`, `prueba-entrada`, `revisor-entrada` et `revisor-salida` ; il manque `acceso-revisor-salida`. **Enfin, le principe :** une politique d'entrée ouvre un côté de la porte. Le Pod qui veut arriver est isolé en **sortie** par `cerrado`, et rien ne la lui ouvre. La première version de ce réseau, qui n'ouvrait que l'entrée, a laissé `depurar` sans pouvoir sortir. **La correction** est le fichier, comme toujours : `kubectl apply -k .` recrée celle qui manque, et `depurar` arrive de nouveau.

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

**L'ordre à suivre quand un Pod n'atteint pas un autre avec des politiques réseau :**

1. `kubectl exec … curl -m 3` : quel code ? 28, c'est le silence du réseau ; 7, c'est qu'il n'y a personne ; 4xx ou 5xx, c'est qu'il est bien arrivé.
2. `kubectl get networkpolicy -n <espace>` dans l'espace **des deux** extrémités.
3. Pour chaque extrémité, quelles politiques la sélectionnent et pour quelle direction ? Il manque la sortie de celui qui appelle ou l'entrée de celui qui reçoit.
4. Le nom se résout-il ? Sinon, `dns`.
5. L'étiquette est-elle sur le Pod, ou sur le Deployment mais **pas** dans le modèle du Pod ?

#### 7.5.7 Les politiques ne s'appliquent pas instantanément

Jusqu'ici, chaque fois que le script modifie une politique, il attend avant de poser la question : ce sont les `sleep 8` que tu vois dans les sorties. Ce n'est pas de la décoration, et cette section raconte d'où vient le huit. Une attente de trois secondes n'a pas suffi lors d'une des exécutions d'essai de cette leçon (la sortie de cette exécution n'a pas été conservée) : avec les six politiques déjà en place, l'`intruso` a demandé `/livez` à l'API et a reçu `ok`, alors que dans les autres exécutions cette même question dépassait le délai. Rien n'était cassé : la question a été posée **avant que le réseau ait fini d'apprendre** les nouvelles politiques. On l'a mesuré exprès. Le script répète six fois cette séquence : il supprime les six politiques, attend une seconde, les réapplique et, à partir de ce moment, pose six fois la question à l'API depuis l'`intruso`, avec un temps maximal d'une seconde par question, en notant combien de secondes se sont écoulées et quel code il a reçu :

```text
$ for ciclo in 1 2 3 4 5 6; do   # borrar las seis, esperar 1 s, volver a aplicarlas y preguntar seis veces a la API desde el intruso
ciclo 1: +0s:200 +0s:200 +0s:200 +2s:000 +3s:000 +6s:000
ciclo 2: +2s:000 +3s:000 +5s:000 +6s:000 +7s:000 +9s:000
ciclo 3: +0s:200 +1s:200 +1s:200 +2s:000 +7s:000 +10s:000
ciclo 4: +5s:000 +6s:000 +9s:000 +12s:000 +17s:000 +20s:000
ciclo 5: +6s:000 +9s:000 +12s:000 +15s:000 +19s:000 +23s:000
ciclo 6: +3s:000 +6s:000 +9s:000 +12s:000 +13s:000 +15s:000
```

Cela se lit ainsi : `+1s:200` veut dire « une seconde après l'application, l'API a répondu (200) », et `000` « elle n'a pas répondu » (le délai a été dépassé). Dans les cycles 1 et 3, les premières questions obtiennent une réponse et les suivantes plus : la dernière réponse est arrivée entre 0 et 1 seconde après l'`apply`, et la première question sans réponse, à 2 secondes (avec un maximum d'une seconde par question, et avec ce qu'ajoute chaque `kubectl exec`, l'imprécision de l'horloge est de cet ordre). Dans les cycles 2, 4, 5 et 6, la première question part déjà à 2, 5, 6 et 3 secondes, parce que, sur cette machine chargée, chaque `kubectl exec` a mis des secondes à démarrer, et elle trouve déjà le réseau fermé. Dans aucun cycle une question n'est repassée après la première sans réponse. Le `kubectl apply` avait déjà terminé et l'objet `NetworkPolicy` existait déjà dans l'API : ce qui manquait, c'était que le plugin réseau, sur chaque nœud, le lise et le convertisse en règles. Cette conversion prend des secondes et, pendant ce temps, le Pod reste ouvert. Avec ce qui a été mesuré ici, la fenêtre est d'environ 2 secondes au maximum (lors d'une exécution précédente, qui n'a pas été conservée, on a vu jusqu'à 3) ; huit secondes sont une marge choisie, de deux fois et demie à quatre fois cela, et non un résultat. Passé les huit secondes du script, la même question dépassait le délai, et dans cette exécution aucune des attentes de huit secondes n'a montré le contraire :

```text
$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -o /dev/null -w '%{http_code}\n' https://kubernetes.default.svc/livez
000
command terminated with exit code 28
[código de salida: 28]
```

Limites de cette mesure : six cycles, une machine chargée, un seul effet mesuré (que `cerrado` ferme la sortie de l'`intruso` ; les six politiques sont appliquées ensemble) et seulement la direction « fermer » ; la direction « ouvrir » (supprimer une politique, ce que font les `sleep 8` de 7.5.6) n'a pas été mesurée. Trois conséquences pratiques, qui justifient toute une section :

1. **Un test réseau fait trop tôt donne un faux « ça passe ».** C'est le même défaut de méthode que celui de 7.5.6, en sens inverse. Après avoir changé des politiques, attends et mesure plus d'une fois. La documentation des politiques réseau ne promet pas de vitesse d'application : elle dit seulement que l'effet sur les connexions déjà existantes est défini par l'implémentation. Le temps mesuré ici est celui de cette machine, avec trois nœuds kind chargés par d'autres clusters, et non une donnée du plugin.
2. **Changer une politique est une opération avec une fenêtre.** Supprimer les politiques et les réappliquer (le cycle de cette même section, ou un `kubectl delete -f red.yaml` suivi d'un `kubectl apply -f red.yaml`) laisse les Pods ouverts pendant la fenêtre, dans un cluster où les politiques sont la seule chose qui les ferme. Pour changer une politique dans un cluster vivant, on crée la nouvelle **avant** de retirer l'ancienne ; on ne la supprime pas pour la recréer.
3. **L'ordre de création compte.** Si un Pod naît avant que les politiques qui le ferment soient programmées, il naît ouvert un instant. En 7.2.3, tu as vu que `kubectl apply -k` a créé les six politiques **après** les Deployments (l'ordre de la liste `resources` ne fait pas foi : Kustomize livre les objets dans son propre ordre), donc les premières répliques du `revisor` ont pu naître ouvertes quelques secondes (c'est une déduction de l'ordre des lignes, pas une mesure sur un Pod tout juste né). Dans un cluster réel, les politiques d'un espace s'appliquent d'abord et l'on attend, puis vient le projet.

#### 7.5.8 Ce que ce réseau ne défend pas

Ce réseau vaut mieux que pas de réseau du tout, et il convient de dire avec exactitude de combien.

- **L'étiquette `acceso-revisor` est posée par celui qui crée le Pod.** Toute personne ayant la permission de créer des Pods dans `revisor` peut se donner la clé à elle-même. La politique protège contre les Pods qui **ne savent pas** que l'étiquette existe, pas contre qui a accès à l'espace. La couche qui veille là-dessus est RBAC : dans un cluster réel, créer des Pods dans `revisor` est une permission qui se donne au compte-gouttes. L'Exercice 1 montre en outre que l'étiquette ne sert à rien dans le mauvais espace.
- **`revisor-entrada` fait confiance à tout l'espace du point d'entrée.** Elle admet **tous** les Pods de `envoy-gateway-system`. Si cet espace héberge autre chose, cela entre aussi. La politique est aussi stricte que l'est celui qui contrôle cet espace.
- **Elle ne chiffre rien.** Un Pod autorisé parle en HTTP en clair avec le `revisor`. Le réseau dit qui peut arriver, pas que ce qui circule soit protégé.
- **Les Pods en `hostNetwork` et le trafic du nœud.** La documentation dit que le comportement des politiques avec des Pods en `hostNetwork` est indéfini et que le plus courant est que le plugin les ignore et traite leur trafic comme du trafic du nœud. Et le trafic du nœud vers ses Pods (les probes) n'est pas bloqué. Le `port-forward` n'est pas arrêté non plus par la politique, et le guide de `port-forward` avertit qu'il peut contourner les contrôles réseau : celui-là est surveillé par RBAC (`create` sur `pods/portforward`). C'est pourquoi le niveau `restricted` de 7.3, qui interdit `hostNetwork`, et le réseau se complètent.
- **Il n'y a pas de politique par défaut pour tout le cluster.** La même page cite comme limite de l'API qu'on ne peut pas appliquer de politiques par défaut à tous les espaces ou Pods. `cerrado` doit être écrite dans chaque espace, et un nouvel espace naît ouvert.
- **Cela ne fonctionne que parce que le plugin les applique.** Dans cette exécution, on a mesuré que kindnet les applique. Dans un autre cluster, il faut le mesurer de la même façon : le cluster enregistre les politiques sans se plaindre même si personne ne les fait respecter.


## L'habitude de sécurité de la leçon : espace dédié, niveau `restricted`, permissions minimales et réseau fermé par défaut

Le tableau des habitudes du cours attribue à cette leçon quatre choses en une seule ligne : espace dédié, niveau `restricted`, permissions minimales, réseau fermé par défaut. Chacune se vérifie avec une commande, et la vérification la plus honnête est celle qui cherche ce qui manque, pas ce qui est en trop. L'inventaire :

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

Lis-le comme quatre questions. **Qu'est-ce qui est publié vers l'extérieur ?** Un seul Service de type `LoadBalancer` dans tout le cluster : celui d'Envoy, dans `envoy-gateway-system`, avec l'IP que lui a donnée MetalLB. Le `revisor-publico` de la Leçon 6 n'existe plus, et le seul point d'entrée est le point d'entrée nommé. **Le projet respecte-t-il le niveau qu'exige son espace ?** Réappliquer la `kustomization` ne produit pas un seul avertissement (`0` ligne avec `warning`), et le test avec `--dry-run=server` de l'état final (dans « Comment savoir que j'ai réussi ») dit `not labeled`. **Qui a des identifiants ?** Seulement `lector`, le Pod de l'exercice de 7.4.4, qui les a demandés exprès (`AUTOMOUNT true`) ; le `revisor`, `prueba`, `depurar` et `intruso` disent `false`. **Le réseau est-il fermé ?** Six politiques dans `revisor`, et 7.5 a mesuré ce qu'ouvre chacune.

Pourquoi sont-ce des habitudes de **sécurité** et pas seulement d'ordre ? Parce que chaque couche ferme un chemin concret qui a été mesuré ouvert. Un espace en `restricted` arrête l'équipe data (ou ta propre étourderie) avant qu'un Pod avec trop de privilèges n'existe. Un compte sans permissions et sans token laisse un conteneur compromis sans rien à présenter devant l'API (l'`intruso` de 7.4.4 n'avait pas même un fichier). Et le réseau fermé transforme « n'importe quel Pod parle à n'importe quel Pod » en une courte liste que l'on peut lire, relire et discuter, ce qui est le changement le plus précieux de la leçon : la surface est passée d'implicite à écrite.

**Ce qu'elle défend et ce qu'elle ne défend pas.** La leçon l'a mesuré, un point après l'autre :

| Couche | Défend contre | Ne défend pas contre |
|---|---|---|
| Espace de noms | collisions de noms ; portée des permissions | trafic entre Pods (7.5.3 : ils se sont atteints d'un espace à l'autre) |
| Pod Security `restricted` | créer des Pods avec privilèges, `root`, `hostNetwork` | Pods qui tournaient déjà (7.3.4) ; quelqu'un ayant la permission de changer l'étiquette de l'espace |
| Compte sans token ni permissions | vol d'identifiants d'un Pod qui n'en a pas besoin | un Pod qui en a besoin et qui est compromis (le `lector` : il atteint ce que son `Role` atteint) |
| Réseau fermé | mouvement latéral entre Pods ; accès à l'API depuis des Pods sans clé | celui qui peut poser l'étiquette ; le trafic du nœud ; le contenu de ce qui circule (HTTP en clair) |

Et le tableau complet, pour qu'on ne le lise pas comme une recette de production : il manque le chiffrement en transit, un plafond de ressources par espace (`ResourceQuota`, `LimitRange`), le chiffrement des Secrets à l'intérieur du cluster, l'audit du `kube-apiserver` et la gestion de qui a la permission de toucher à cet espace. La Leçon 10 rassemble la liste de ce qui manque à tout le projet pour tourner pour de vrai.

## Ce qui se fait de travers

**Croire qu'un espace de noms isole le réseau.** On le croirait, parce que les plaques sont partout. 7.5.3 l'a mesuré : un Pod de `default` a atteint le Service de `revisor` en écrivant son nom complet.

**Appliquer une politique réseau sans vérifier que le plugin la respecte.** Le cluster enregistre l'objet sans se plaindre et le trafic reste le même. On le teste avec un Pod sans clé qui doit échouer, pas en lisant le manifeste.

**Fermer l'entrée et oublier la sortie.** `cerrado` isole les deux directions, et n'ouvrir que l'entrée de la destination laisse celui qui appelle sans pouvoir sortir. Ce sont les deux moitiés d'une seule permission. C'est la deuxième erreur de la leçon.

**Fermer la sortie et oublier le DNS.** Sans la règle `dns`, les noms ne se résolvent pas et le symptôme ressemble à « le réseau est en panne » alors qu'il ne manque que les requêtes de noms.

**Conclure à partir d'un « ça fonctionne toujours ».** Une connexion déjà ouverte peut survivre au changement d'une politique, et la documentation laisse cela à la décision de chaque plugin. Un test réseau ouvre une nouvelle connexion à chaque fois.

**Poser `enforce` et croire que l'espace est propre.** L'étiquette rejette ce qui arrive, elle n'expulse pas ce qui tourne déjà. Et l'ancien Pod qui viole le niveau meurt d'un rollout : le jour où tu le recrées, il ne naît plus.

**Laisser `enforce` sans version.** `restricted:latest` change quand le cluster est mis à jour. Fige la version (`enforce-version`) et monte-la volontairement.

**Ne regarder que le mode `enforce`.** Un Deployment qui viole la politique **est créé**, avec un avertissement que presque personne ne lit, et reste sans Pods. Les avertissements du mode `warn` se lisent, ou se redirigent vers un journal que quelqu'un examine.

**Donner des permissions avec des caractères génériques (`*`).** La documentation de RBAC l'avertit : un caractère générique sur les ressources ou les verbes accorde aussi ce que le cluster ajoutera un jour. On nomme chaque ressource et chaque verbe.

**Laisser monté le token d'un compte qui ne l'utilise pas.** C'est un identifiant dans chaque réplique, sans aucun avantage. `automountServiceAccountToken: false`, sur le compte ou sur le Pod.

**Donner l'étiquette `acceso-revisor` à n'importe quel Pod « pour que ça marche ».** Chaque Pod qui a la clé est un Pod de plus qui peut parler au `revisor`. La clé se donne à qui en a besoin, et l'on demande pourquoi.

**Faire confiance à tout un espace de noms comme origine.** `revisor-entrada` accepte tous les Pods de `envoy-gateway-system`. C'est une décision raisonnable tant que cet espace n'appartient qu'à la plateforme, et elle cesse de l'être le jour où autre chose y vit.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre et à partir de l'état dans lequel il est resté après 7.5. Avant chacun, `ctx` doit laisser passer la chaîne. `correr.sh` les exécute aussi, et sa sortie est dans `correr.salida.txt`. **Avant** d'exécuter chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes propres mots.

### Exercice 1 — La bonne étiquette dans le mauvais espace

Applique `depurar.yaml` dans l'espace `default`, avec `ctx && kubectl apply -n default -f depurar.yaml`. C'est le même manifeste, avec la même étiquette `acceso-revisor: permitido`. Avant de regarder, prédis : ce Pod peut-il parler au `revisor` avec le nom complet, `http://revisor.revisor.svc.cluster.local/salud` ? Et le `depurar` de l'espace `revisor` ? Explique la différence avec les mots de 7.5.5 : que sélectionne la politique `revisor-entrada` et dans **quel espace** ? À la fin, supprime le Pod de `default`.

### Exercice 2 — Un compte qui ne fait que redémarrer le `revisor`

`fig07_03.reiniciador.yaml` crée un compte, un `Role` et un `RoleBinding` :

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

`kubectl rollout restart` a besoin de lire le Deployment (`get`) et de lui modifier une annotation (`patch`). Applique-le avec `ctx && kubectl apply -n revisor -f fig07_03.reiniciador.yaml` et prédis, avant d'exécuter quoi que ce soit : le compte peut-il redémarrer le `revisor` ? Et `prueba` ? Peut-il **lister** les Deployments ? Vérifie tes trois prédictions avec `kubectl auth can-i … --as=system:serviceaccount:revisor:reiniciador`, puis avec un vrai `kubectl rollout restart`. Pourquoi `can-i list deployments` répond-il autrement que `can-i patch deployment/revisor` ? À la fin, supprime ce que tu as créé avec `ctx && kubectl delete -n revisor -f fig07_03.reiniciador.yaml`.

### Exercice 3 — Une route qui vient d'un autre espace (projet)

Le point d'entrée vit dans `revisor`. Une autre équipe, dans `default`, veut publier sa propre route par ce même point d'entrée. `fig07_05.ruta-ajena.yaml` est sa `HTTPRoute` :

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

Avant de commencer, deux permissions distinctes qu'il vaut mieux ne pas confondre. `allowedRoutes`, dans les `listeners` du `Gateway`, dit **qui peut se rattacher au point d'entrée** : par défaut (`from: Same`), seulement les routes du même espace que le `Gateway` ; `All` et `Selector` ouvrent le point d'entrée à d'autres espaces. `ReferenceGrant` vit dans l'espace de la **destination** et dit **qui peut pointer vers ses Services** : une route d'un autre espace ne peut pas utiliser comme destination un Service de `revisor` si le propriétaire de cet espace ne l'autorise pas. La première, c'est le propriétaire du point d'entrée qui la donne ; la seconde, le propriétaire du Service. Les pages de référence : [`ReferenceGrant`](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/), la [référence de l'API](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) et le [guide des routes inter-espaces](https://gateway-api.sigs.k8s.io/guides/multiple-ns/).

Applique-la dans `default`. Lis son état avec `kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'`. Il y a **deux** problèmes distincts dans cet état. Avant de regarder le tien, prédis lesquels, de quel objet dépend chacun et qui doit donner chaque permission : le propriétaire du point d'entrée, le propriétaire du Service ou l'équipe qui écrit la route ? Corrige d'abord celui qui vient du point d'entrée (l'indice : `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces`) puis l'autre avec `fig07_06.referencegrant.yaml` :

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

Vérifie à la fin que `GET /ajena` par le point d'entrée arrive au `revisor` (la réponse est un `404` du `revisor`, pas du point d'entrée : comment le démontres-tu avec son journal ?), et défais tout ce que tu as changé, y compris le `Gateway`.

### Exercice 4 — Défends la conception

En cinq phrases au maximum, réponds : (1) pourquoi cette leçon n'a-t-elle pas installé Calico, et quelle preuve l'appuie ? (2) Qu'arriverait-il aux probes si `kindnet` appliquait les politiques mais que le trafic du nœud était lui aussi bloqué ? (3) Laquelle des six politiques changerais-tu si l'équipe data avait besoin d'un service **à elle** dans l'espace `revisor` qui reçoive aussi le trafic du point d'entrée ? (4) Que faut-il pour que `acceso-revisor: permitido` soit une protection et pas seulement un accord ? (5) La politique `dns` ouvre la sortie vers les Pods `k8s-app: kube-dns` de `kube-system` ; qu'arriverait-il à la résolution de noms si CoreDNS migrait vers un autre espace ?

## Solutions

### Solution 1

Mesuré dans `correr.salida.txt` :

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

Le Pod de `default` a l'étiquette, et pourtant **code 28**. Le `depurar` de `revisor` répond. La politique `revisor-entrada` ne sélectionne pas « les Pods avec l'étiquette » tout court : dans sa liste `from`, le `podSelector` sans `namespaceSelector` désigne les Pods **de l'espace où vit la politique**, c'est-à-dire `revisor`. L'étiquette dans un autre espace ne compte pas. Le second élément de la liste (`namespaceSelector`), en revanche, choisit des espaces entiers, et c'est pourquoi Envoy entre. Pour que le Pod de `default` entre, il faudrait ajouter un élément avec `namespaceSelector` et `podSelector` **ensemble** : les Pods portant cette étiquette, de cet espace. Remarque aussi que le nom long s'est bien résolu (la règle `dns` est ouverte pour tous) ; ce qui a échoué, c'est la connexion.

### Solution 2

Mesuré dans `correr.salida.txt` :

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

`patch` sur `deployment/revisor` répond `yes`, sur `prueba` `no` : le `Role` nomme le Deployment avec `resourceNames: ["revisor"]`. Le redémarrage du `revisor` fonctionne (`restarted`) et celui de `prueba` donne un `Forbidden` qui dit `cannot get resource "deployments"` : `rollout restart` commence par lire le Deployment, et cette lecture est déjà interdite. `list deployments` répond `no` pour la raison la plus simple : le `Role` n'accorde que `get` et `patch`, et `list` est un autre verbe. Que `get` soit limité à un nom ne fait pas de `get` un `list` : lire un objet par son nom et lister sont des permissions séparées (tu l'as vu en 7.4.3 avec les Secrets). Et même si le `Role` ajoutait `list`, la documentation de RBAC prévient que restreindre `list` ou `watch` avec `resourceNames` oblige le client à envoyer `--field-selector=metadata.name=revisor` : un `kubectl get deployments` tout court continuerait de donner `no`. Ce compte peut redémarrer un service et ne peut pas voir les autres. C'est la permission minimale que décrit la leçon, et c'est l'exemple de la raison pour laquelle on écrit `resourceNames` au lieu de donner `patch` sur tous les Deployments.

### Solution 3

Mesuré dans `correr.salida.txt` :

```text
$ kubectl get gateway revisor -n revisor -o jsonpath='{.spec.listeners[0].allowedRoutes}{"\n"}'
{"namespaces":{"from":"Same"}}

$ kubectl apply -n default -f fig07_05.ruta-ajena.yaml
httproute.gateway.networking.k8s.io/ajena created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=False NotAllowedByListeners: No listeners included by this parent ref allowed this attachment.
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

Le `Gateway` dit `{"namespaces":{"from":"Same"}}` : **seulement les routes de son propre espace**. Ce n'est pas toi qui l'as écrit ; c'est la valeur par défaut du type (`kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` dit « limité à l'espace de ce Gateway par défaut »). Et la route de `default` sort avec deux conditions à faux, de deux mécanismes distincts :

- **`Accepted=False NotAllowedByListeners`** : l'*écouteur* (`listener`) du Gateway n'admet pas les routes de `default`. C'est le propriétaire du point d'entrée qui en décide, avec `allowedRoutes`, **dans le Gateway**.
- **`ResolvedRefs=False RefNotPermitted`** : la route pointe vers un Service d'un autre espace, `revisor/revisor`, et aucun `ReferenceGrant` ne l'autorise. C'est le propriétaire de la **destination** qui en décide, avec un objet dans **son** espace.

L'état de la route le résume en deux lignes : traverser les espaces en **se rattachant** à un Gateway est gouverné par le Gateway ; traverser les espaces en **pointant** vers un Service est gouverné par le propriétaire du Service (`kubectl explain referencegrant.spec` le décrit comme les espaces et les types de confiance qui peuvent référencer les ressources de `to`). Ce sont deux permissions avec deux propriétaires, et l'état les sépare : `Accepted` répond à l'écouteur du Gateway (`allowedRoutes`) et `ResolvedRefs` répond au `ReferenceGrant`. Un `ReferenceGrant` parle de ce vers quoi une route peut **pointer** ; qu'une route puisse **se rattacher** à un Gateway étranger relève d'`allowedRoutes`. On corrige la première en étiquetant l'espace de la route et en disant à l'écouteur d'accepter les espaces portant cette étiquette :

```text
$ kubectl label namespace default acceso-puerta=permitido
namespace/default labeled

$ kubectl patch gateway revisor -n revisor --type=json -p '[{"op":"add","path":"/spec/listeners/0/allowedRoutes","value":{"namespaces":{"from":"Selector","selector":{"matchLabels":{"acceso-puerta":"permitido"}}}}}]'
gateway.gateway.networking.k8s.io/revisor patched

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

`Accepted` est passé à `True` ; `ResolvedRefs` reste en `RefNotPermitted` : la première permission ne règle pas la seconde. La permission de la destination est le `ReferenceGrant`, qui vit dans l'espace du Service (`revisor`) et nomme de qui il accepte les références :

```text
$ kubectl apply -n revisor -f fig07_06.referencegrant.yaml
referencegrant.gateway.networking.k8s.io/rutas-de-default created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=True ResolvedRefs: Resolved all the Object references for the Route
```

Les deux conditions sont vraies. Et la preuve que la route arrive au `revisor` :

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/ajena   # desde fuera del clúster
404

$ kubectl logs -n revisor -l app=revisor --tail=-1 | grep -E 'GET /ajena'
revisor: GET /ajena 404 0s
```

Le client extérieur reçoit `404`. Ce `404` **n'est pas celui du point d'entrée** : le journal du `revisor` contient la ligne `GET /ajena 404`, donc la requête est arrivée à une réplique du `revisor`, qui ne connaît pas cette route. (Si le point d'entrée n'avait trouvé aucune route, le `404` n'apparaîtrait pas dans le journal du `revisor`.) La politique réseau n'a pas gêné parce que la destination est le `revisor` lui-même, et `revisor-entrada` admet déjà les Pods d'Envoy : les deux couches, celle des routes et celle du réseau, ont dit oui. Ce sont des couches distinctes, et toutes deux doivent le dire. Ce `Same` est la valeur par défaut que documente la [référence de l'API de Gateway API](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) pour `allowedRoutes.namespaces.from`, et le cluster l'a confirmé avec la première commande ; le [guide des routes inter-espaces](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) explique comment l'ouvrir avec `Selector` ou `All`.

Le script défait tout : il supprime la route, le `ReferenceGrant`, l'étiquette de `default` et le champ `allowedRoutes` que tu as ajouté au `Gateway` ; le `kubectl diff -k .` de l'état final confirme que le cluster est revenu à ce que disent les fichiers.

### Solution 4

Une réponse possible : « (1) Parce que kindnet a appliqué les politiques : avec `cerrado` seule, l'`intruso` et le Pod avec l'étiquette ont cessé d'arriver (code 28), et avec les six, seul ce qu'elles disaient s'est ouvert ; c'est la mesure que le plan du cours avait laissée en suspens. (2) Les probes échoueraient : le `kubelet` les exécute depuis le nœud et elles seraient bloquées, la readiness probe retirerait toutes les répliques de la liste et la liveness probe les redémarrerait ; la documentation dit que le trafic du nœud est autorisé, et cette leçon a mesuré `RESTARTS 0`. (3) Aucune des six : on ajouterait une nouvelle politique, `entrada` pour ce service, avec le même `namespaceSelector` que le point d'entrée ; les politiques s'additionnent et l'on ne modifie pas celles des autres. (4) Que celui qui peut créer des Pods dans `revisor` ne puisse pas se poser l'étiquette : un RBAC qui limite qui crée ou modifie des Pods dans l'espace, ou une politique d'admission qui valide l'étiquette. (5) La sortie vers le DNS cesserait de correspondre aux nouveaux Pods DNS et les noms ne se résoudraient plus, avec le même symptôme que le retrait de la règle `dns` en 7.5.6 : le `nslookup` dépasse le délai et `curl` par nom échoue avec 28, tandis que le point d'entrée continue de répondre, comme dans cette ligne du tableau. »

## Supprimer le cluster

Quand tu as terminé les exercices, supprime le cluster de la leçon. Ne laisse rien de vivant sur la machine :

```text
$ kind delete cluster --name curso-k8s-l7
Deleting cluster "curso-k8s-l7" ...
Deleted nodes: ["curso-k8s-l7-worker2" "curso-k8s-l7-worker" "curso-k8s-l7-control-plane"]

$ kind get clusters | grep -c curso-k8s-l7
0

# disco de Docker: 77% usado
# la corrida completa tardó 1569 s
```

(La ligne entre parenthèses est écrite par le script, qui mesure la suppression.) Le `--name` est obligatoire : sans lui, kind supprimerait le cluster appelé `kind`, qui peut appartenir à quelqu'un d'autre.

Il reste sur ta machine le dossier temporaire du `kubeconfig` et `token.txt` (celui de `punto-de-partida/` a été supprimé en 7.2.3 ; le `rm` ci-dessous l'inclut au cas où tu ne l'aurais pas fait). On les supprime ainsi, depuis `programas/07-aislar-permisos-red` :

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

Le `case` ne laisse passer qu'un chemin qui commence par `/tmp/curso-k8s-l7.` et a quelque chose après, la forme exacte de celui que tu as créé en 7.1.1. Si `L7_TMP` est vide (parce que tu es dans un autre terminal où tu ne l'as jamais définie) ou vaut autre chose, il ne supprime rien et te dit pourquoi. C'est la même protection qu'utilise `correr.sh` pour nettoyer. La dernière ligne retire la fonction `ctx` de ton terminal.

Si, sur cette machine, tu as exécuté la leçon avec un réseau Docker dédié (la variable `CURSO_RED` de `correr.sh`), ce réseau est aussi à toi et c'est toi qui le supprimes, **après** le cluster et seulement si tu l'as créé toi-même pour cela : `docker network rm curso-k8s-red-l7`. Avec le réseau `kind` habituel, il n'y a rien à supprimer : il appartient à tous tes clusters. Le cluster de la leçon suivante se crée de zéro, comme celui-ci.

## Comment savoir que j'ai réussi

Avant les cases, l'état final tel que l'exécution l'a laissé, copié de `correr.salida.txt`. D'abord on supprime les Pods des exercices et l'on demande au cluster si quelque chose diffère des fichiers du projet, puis on regarde le point d'entrée depuis l'extérieur et l'on répète le test de 7.3 :

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

Cela se lit ainsi. `sin diferencias con los archivos` veut dire que les exercices ont été défaits : le cluster est exactement ce que disent les fichiers. Le `401` est le `revisor` derrière son point d'entrée : le point d'entrée répond, mais `/api/estados` demande le token et, depuis l'extérieur, tu ne le portes pas. Et `not labeled (server dry run)` sans avertissements clôt 7.3 : redemander le niveau `restricted` pour `revisor` ne change rien parce qu'il l'a déjà, et aucun Pod existant ne l'enfreint.

- [ ] Tu dis, avec une commande, ce qu'un espace de noms n'isole **pas** : un Pod de `default` atteint `revisor.revisor.svc.cluster.local` s'il n'y a pas de politiques.
- [ ] Devant un Deployment avec `READY 0/1` et sans Pods, tu vas au ReplicaSet et tu trouves `FailedCreate … violates PodSecurity` ; et tu sais pourquoi `apply` n'a pas échoué.
- [ ] Tu lis un rejet de `restricted` et tu nommes les quatre règles et la ligne du `securityContext` qui corrige chacune.
- [ ] Tu écris un `Role` et un `RoleBinding` sans caractères génériques, et tu testes ce qui est permis et ce qui est refusé avec `kubectl auth can-i … --as=…`, avec une vraie requête et depuis un Pod.
- [ ] Tu expliques pourquoi le `revisor` n'a pas de token monté et le `lector` en a un, et ce que le `lector` atteint avec le sien.
- [ ] Tu distingues `exit code 28` (silence du réseau), `7` (personne n'écoute) et `403` (il est bien arrivé et on le lui a refusé).
- [ ] Tu dis, pour chacune des six politiques, ce qui casse si elle manque, et pourquoi `revisor-salida` et `prueba-entrada` produisent le même symptôme.
- [ ] Tu exécutes `programas/07-aislar-permisos-red/correr.sh > /tmp/mi-corrida-l7.txt 2>&1` et tu compares `/tmp/mi-corrida-l7.txt` à `programas/07-aislar-permisos-red/correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) sur ce qui ne change pas d'une exécution à l'autre : trois nœuds `Ready` (la version du nœud est figée par `kind-curso.yaml` via son empreinte) ; `-rw-------` sur les deux `token.txt` ; les sept étiquettes de l'espace `revisor` avec `restricted` et `v1.37` ; `default` avec seulement le Service `kubernetes` ; le rejet `violates PodSecurity "restricted:v1.37"` avec ses quatre règles ; `baseline:latest` rejette `hostNetwork` et accepte le Pod simple ; `namespace/revisor not labeled (server dry run)` ; la ReplicaFailure de `sinreglas` ; dans les `can-i`, `no` pour le `revisor`, `yes` pour lire les Pods et les journaux avec `observador` et `no` pour supprimer, lire les Secrets et lire dans `default` ; `pods 200`, `secrets 403`, `pods-default 403` et le répertoire absent dans `intruso` ; sans règles, les tests répondent ; avec `cerrado`, ils donnent 28 et `000` depuis l'extérieur ; avec les six, `depurar` arrive et `intruso` non ; et les cinq lignes du tableau de 7.5.6. Les IP, les suffixes des noms, les âges, le nom du Secret, les millisecondes et les temps de démarrage changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l7`.

## Résumé

Réponds sans regarder la leçon :

1. Quelles sont les deux choses qu'un espace de noms isole et celle qu'il n'isole pas ? Qu'a mesuré 7.5.3 pour le démontrer ?
2. Quels sont les trois modes et les trois niveaux de Pod Security Admission, et comment s'écrivent-ils dans l'espace ?
3. Pourquoi un Deployment qui viole `restricted` est-il créé et reste-t-il sans Pods ? Où se trouve le motif ?
4. Qu'ajoute un `Role` et qu'ajoute un `RoleBinding` ? Que signifie le fait que les permissions soient additives ?
5. Que fait `kubectl auth can-i … --as=system:serviceaccount:ESPACE:COMPTE` et quel code de sortie renvoie-t-il avec `no` ?
6. Pourquoi le `revisor` déclare-t-il `automountServiceAccountToken: false`, et que mesure-t-on avec le `lector` qui l'a à `true` ?
7. Quand un Pod est-il isolé en entrée ? Que se passe-t-il si deux politiques le sélectionnent ?
8. De quelle condition une `NetworkPolicy` a-t-elle besoin pour avoir un effet, et comment l'a-t-on vérifiée dans kind ?
9. Que signifient `exit code 28`, `exit code 7` et `403` ?
10. Pourquoi `acceso-revisor-salida` existe-t-elle ? Et pourquoi `dns` ?
11. Que couvre `allowedRoutes` et que couvre `ReferenceGrant` ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Namespaces »](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) : les espaces comme mécanisme d'isolation de groupes de ressources, des noms uniques par espace, les objets avec et sans espace, l'espace `kube-system`, et l'étiquette automatique `kubernetes.io/metadata.name`.
- [Kubernetes, « Pod Security Admission »](https://kubernetes.io/docs/concepts/security/pod-security-admission/) : les trois modes (`enforce`, `audit`, `warn`), les trois niveaux, la syntaxe des étiquettes avec et sans version, et le fait que `enforce` s'applique aux Pods et non aux charges de travail.
- [Kubernetes, « Pod Security Standards »](https://kubernetes.io/docs/concepts/security/pod-security-standards/) : les définitions de `privileged`, `baseline` et `restricted`.
- [Kubernetes, « Enforce Pod Security Standards with Namespace Labels »](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) : comment poser les étiquettes sur un espace neuf et sur un espace existant, le `--dry-run=server`, et le fait qu'en ajoutant `enforce` le contrôleur teste les Pods existants et renvoie des avertissements.
- [Kubernetes, « Service Accounts »](https://kubernetes.io/docs/concepts/security/service-accounts/) : ce qu'est un compte de service, le compte `default` de chaque espace, le montage automatique des identifiants et les tokens à courte durée de vie depuis la 1.22.
- [Kubernetes, « Configure Service Accounts for Pods »](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) : comment désactiver le montage sur le compte et sur le Pod, et le fait que le Pod a la priorité.
- [Kubernetes, « Using RBAC Authorization »](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) : `Role` et `ClusterRole`, `RoleBinding`, des permissions purement additives, les rôles par défaut (`system:basic-user`, `system:discovery`), le risque des caractères génériques et les restrictions par `resourceNames`.
- [Kubernetes, « Network Policies »](https://kubernetes.io/docs/concepts/services-networking/network-policies/) : le modèle d'isolation (non isolé tant qu'aucune politique ne sélectionne le Pod, et politiques additives), l'exigence d'un plugin qui les applique, le trafic du nœud, `hostNetwork`, les limites de l'API, et l'impact sur les connexions existantes.
- [Kubernetes, « Use Port Forwarding to Access Applications in a Cluster »](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) : le fait que `port-forward` est autorisé par RBAC avec `create` sur `pods/portforward`.
- [kind, « Configuration »](https://kind.sigs.k8s.io/docs/user/configuration/) : le plugin réseau par défaut (`kindnetd`) et comment le désactiver.
- [kind, notes de version v0.24.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0) : la prise en charge des politiques réseau avec `sigs.k8s.io/kube-network-policies`.
- [Gateway API, « Cross-Namespace routing »](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) : des routes qui se rattachent à un Gateway d'un autre espace avec `allowedRoutes`.
- [Gateway API, « ReferenceGrant »](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/) : la permission de l'espace de destination pour qu'une route pointe vers son Service ; les champs `from` et `to`, et le fait qu'il n'autorise que des références vers des ressources de son propre espace.
- [Gateway API, référence de l'API (spec)](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) : `RouteNamespaces` et sa valeur par défaut, `from: Same`. La même chose a été lue dans le cluster lui-même avec `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` et `kubectl explain referencegrant.spec`, et l'état `RefNotPermitted` de la route le confirme.
- [CyberScoop, « Tesla falls victim to cryptomining scheme, minor breach »](https://cyberscoop.com/tesla-cryptomining-redlock-cloud-breach/) (20 février 2018) : le cas qui ouvre la leçon, d'après le rapport de RedLock.

---

**Suivante :** [Leçon 8 — Données et tâches](08-datos-y-tareas.md)
