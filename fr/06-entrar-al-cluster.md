# Leçon 6 — Entrer dans le cluster

Jeudi, 16 h 40. L'équipe d'exploitation veut voir le rapport du `revisor` depuis son propre tableau de bord, qui tourne sur une autre machine, en dehors du cluster, et la présentation devant la direction est à 17 h 30. Dans le chat de l'équipe, il y a déjà deux propositions. La première : « passe le Service en `NodePort` et donne-leur l'IP d'un nœud ». La seconde arrive avec un lien vers un tutoriel d'il y a deux ans : « installe `ingress-nginx`, c'est trois commandes ». Les deux fonctionnent cet après-midi. La première laisse le `revisor` ouvert sur **tous** les nœuds, sur un port choisi au hasard, sans que personne ne l'ait décidé par écrit. La seconde installe un composant qui ne reçoit plus de correctifs de sécurité depuis mars 2026. Et il y a une troisième tentation, celle du README de kind : un programme que l'on exécute sur ta machine et qui donne des équilibreurs de charge à tes clusters… à **tous** tes clusters kind, y compris ceux de tes collègues si tu partages la machine avec eux.

Cette leçon t'apprend à ouvrir un point d'entrée vers le cluster sans ces raccourcis : un `LoadBalancer` avec MetalLB et un point d'entrée nommé avec Gateway API et Envoy Gateway, tous deux installés **à l'intérieur** de ton cluster, pour qu'ils disparaissent avec lui quand tu le supprimes. Et elle t'apprend une chose qui vaut pour tout ce que tu installeras désormais dans Kubernetes : il y a des pièces qui relèvent de la **plateforme** et des pièces qui relèvent du **projet**, et la plateforme doit être prête avant que le projet ne l'utilise.

**Durée :** 2 × 45 min

**Ce que tu construis :** le `revisor` publié vers l'extérieur du cluster, d'abord avec un Service `LoadBalancer` qui reçoit l'IP `172.18.255.200`, puis par un point d'entrée nommé, le Gateway `revisor`, avec sa route vers le Service habituel

**Ce que tu apprends :** pourquoi un `LoadBalancer` reste en `<pending>` dans kind et ce qu'il ouvre même en attente (un `NodePort` sur chaque nœud) ; ce que fait MetalLB en couche 2 et pourquoi sa plage d'adresses provient du réseau `kind` de Docker ; ce que sont les ressources personnalisées (CRD) et les *webhooks* d'admission, et pourquoi ils obligent à installer dans l'ordre ; Gateway API et ses trois pièces, `GatewayClass`, `Gateway` et `HTTPRoute`, servies par Envoy Gateway ; pourquoi on n'utilise pas Cloud Provider KIND sur une machine partagée ; `Ingress` comme API gelée et pourquoi pas `ingress-nginx` ; et ce qui reste exposé, par où et sans quoi (chiffrement en transit)

**D'où tu viens.** De la [Leçon 5](05-salud-recursos-apagado.md) : le `revisor` tourne avec trois répliques, avec ses startup, readiness et liveness probes, avec des `requests` et des `limits`, avec son `ConfigMap` en variables et son token en fichier, le tout appliqué avec `kubectl apply -k .`. Le service de test est lui aussi surveillé. De la [Leçon 3](03-services-dns.md), tu apportes la règle selon laquelle tout naît en `ClusterIP` et rien n'est publié sans raison, ainsi que l'ordre pour diagnostiquer un Service qui ne répond pas : le code de `curl`, le nom, la colonne `ENDPOINTS`. Aujourd'hui, cette règle est enfreinte pour la première fois, exprès et par écrit.

**Ce que cette leçon ne fait pas.** Elle ne met pas en place de chiffrement : le point d'entrée parle HTTP en clair sur le port 80, et la section de l'habitude de sécurité le mesure et le dit. Elle ne restreint pas encore qui parle à qui **à l'intérieur** du cluster : c'est le rôle de la [Leçon 7](07-aislar-permisos-red.md), qui retire en outre le `LoadBalancer` direct et laisse le Gateway comme unique point d'entrée. Elle ne te donne ni nom de domaine ni véritable équilibreur de charge d'un fournisseur cloud : les IP que MetalLB distribue ici n'existent que dans le réseau `kind` de Docker de ta machine. Et le `revisor` reste dans l'espace de noms `default` ; son déménagement vers son propre espace relève de la Leçon 7.

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1, l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, **MetalLB v0.16.1** et **Envoy Gateway v1.9.2** (qui inclut Gateway API v1.6.1), sur le cluster de trois nœuds de la Leçon 1, appelé ici `curso-k8s-l6`. La machine était un Mac à processeur ARM avec Docker Engine 29.2.1 dans une machine virtuelle Linux (Colima), **pas** Linux Mint, qui est le système de référence du cours. Ce qui change sur ta Mint : l'architecture, les IP des Pods, des Services et des nœuds (`172.18.0.2` à `.4`, dans un autre ordre), les `NodePort` que le cluster choisit au hasard, les suffixes des noms, les âges et le nœud depuis lequel MetalLB annonce chaque IP. Les deux IP de MetalLB, `172.18.255.200` et `172.18.255.201`, doivent en revanche être **identiques** chez toi si ton réseau `kind` est `172.18.0.0/16`. Et il y a une différence qui compte : sur le Mac, le réseau `kind` vit à l'intérieur de la machine virtuelle et ton terminal ne l'atteint pas (tu le verras dans l'habitude de sécurité : code 28) ; sous Linux, Docker connecte ta machine à ce réseau, donc sur ta Mint `curl http://172.18.255.200/salud` lancé depuis ton terminal devrait répondre. Pour que l'exemple soit le même sur les deux systèmes, le « client de l'extérieur » de cette leçon est un conteneur Docker connecté au réseau `kind`, en dehors du cluster. Le parcours complet se trouve dans [`programas/06-entrar-al-cluster/`](../programas/06-entrar-al-cluster) : `correr.sh` crée le cluster, y charge les deux images, parcourt la leçon dans l'ordre, exécute les Exercices 1 à 3 et supprime le cluster. À la fin, il répète, dans un nouveau cluster, les trois étapes de 6.9 avec `levantar.sh`. L'exécution complète, avec les deux clusters, a duré 15 minutes et 20 secondes (920 secondes) : créer le premier cluster et attendre qu'il soit prêt a pris 40 secondes, créer le second 46, supprimer le premier 1, et `levantar.sh` a pris 266. Sa sortie est `correr.salida.txt`. Le parcours a besoin d'internet : les manifestes de MetalLB et d'Envoy Gateway sont téléchargés depuis leurs publications (*releases*), figés à leur version, et leurs images sont téléchargées la première fois.

## À la fin, tu seras capable de

- Expliquer pourquoi un Service `LoadBalancer` reste en `<pending>` dans kind, et démontrer avec `curl` qu'il a malgré tout déjà ouvert un `NodePort` sur chaque nœud.
- Installer MetalLB dans un cluster, lui donner une plage d'IP prise dans le réseau `kind` et lire dans les événements du Service qui a attribué l'IP et depuis quel nœud elle est annoncée.
- Distinguer une pièce de **plateforme** (CRD, contrôleurs, *webhooks*) d'une pièce de **projet**, et les appliquer en trois étapes : plateforme, attente avec `kubectl wait`, projet.
- Reconnaître les erreurs d'une application dans le désordre : `no matches for kind … ensure CRDs are installed first` et `failed calling webhook … connection refused`.
- Écrire un `Gateway` et une `HTTPRoute` pour le `revisor`, et lire leur état (`PROGRAMMED`, `Accepted`, `ResolvedRefs`).
- Provoquer une route vers un Service qui n'existe pas, la reconnaître à `ResolvedRefs=False BackendNotFound` et au `500` du point d'entrée, puis la corriger.
- Dire ce qui reste exposé après cette leçon, par quel point d'entrée, et ce qui lui manque (chiffrement en transit), et expliquer pourquoi on n'utilise ni Cloud Provider KIND ni `ingress-nginx`.

## Le pourquoi avant le comment

Jusqu'ici, tout ce qui parlait au `revisor` se trouvait **à l'intérieur** du cluster : le Pod `depurar`, le `revisor` lui-même quand il interroge `prueba`, les probes du `kubelet`. Toi, tu entrais par un tunnel temporaire, `port-forward`, qui dure le temps de ta commande et ne parle qu'à un seul Pod. Cela suffit pour regarder. Cela ne suffit pas pour le tableau de bord d'exploitation de la scène, qui a besoin d'une adresse stable, qui survive aux *rollouts*, qui répartisse entre les répliques et qui ne dépende pas du fait que ton ordinateur portable soit en marche.

Kubernetes a trois façons d'ouvrir cette adresse, de la plus grossière à la plus fine :

1. **`NodePort`** : le cluster ouvre un port élevé (entre 30000 et 32767) sur **tous** les nœuds, et ce qui y arrive va au Service. Cela fonctionne, mais le client doit connaître l'IP d'un nœud et un numéro que le cluster a choisi.
2. **`LoadBalancer`** : la même chose que `NodePort`, plus un équilibreur de charge **en dehors** du cluster, avec sa propre IP, qui répartit entre les nœuds. Dans un cloud, c'est le fournisseur qui crée cet équilibreur. Dans kind, il n'y a pas de cloud, et c'est pourquoi le Service reste en attente.
3. **Un point d'entrée de couche 7** (HTTP) : un endroit unique qui reçoit le trafic et décide, selon le chemin ou le nom du site, vers quel Service va chaque requête. La façon actuelle de le déclarer est **Gateway API**. L'ancienne, `Ingress`, existe toujours, et elle est gelée.

Dans kind, les options 2 et 3 ont besoin de quelque chose que le cluster n'inclut pas : quelqu'un qui distribue des adresses IP et quelqu'un qui s'occupe du point d'entrée. Ce cours installe les deux **à l'intérieur** du cluster. **MetalLB** distribue les IP. **Envoy Gateway** s'occupe du point d'entrée. Chacun s'installe avec ses propres types d'objet (des ressources personnalisées) et ses propres gardiens (des *webhooks*), et c'est de là que vient la leçon la plus utile d'aujourd'hui, celle que tu vas appliquer dans tout vrai cluster : la plateforme passe en premier, on attend qu'elle soit prête, puis vient le projet. Ce n'est pas une lubie. C'est ce que le cluster exige de toi, et tu vas le voir l'exiger.

La leçon comporte huit parties de concepts, puis les sections habituelles :

1. **Le cluster de la leçon** (6.1), avec son propre `kubeconfig`.
2. **Le projet avant la plateforme** (6.2) : ce qui échoue et pourquoi.
3. **Un `LoadBalancer` sans personne pour distribuer les adresses** (6.3), et le `NodePort` qu'il a déjà ouvert.
4. **MetalLB** (6.4) : la plage, la couche 2 et le *webhook* qui n'écoute pas encore.
5. **Pourquoi pas Cloud Provider KIND** (6.5).
6. **Envoy Gateway et Gateway API** (6.6) : la plateforme du point d'entrée.
7. **Le point d'entrée du `revisor`** (6.7) : `Gateway` et `HTTPRoute`.
8. **`Ingress` et `ingress-nginx`** (6.8) : ce qui a été retiré, pour savoir le reconnaître.

Et à la fin des concepts, **l'ordre** (6.9), écrit en trois étapes.

Voici la destination. À la fin de 6.7, un client qui ne fait pas partie du cluster demande le rapport au `revisor` par le point d'entrée nommé :

```text
$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200
```

## Si tu n'as pas l'image du cours de Docker

Cette leçon utilise les deux mêmes images que les Leçons 3 à 5 : `curso-docker-revisor:1.6.0`, celle du `revisor`, et `curso-docker-prueba:1.0.0`, celle du service qui échoue exprès. Vérifie que tu les as :

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

S'il t'en manque une, la [Leçon 3](03-services-dns.md) explique, dans cette même section, comment construire les deux à partir du dépôt du cours de Docker. Cette leçon ne demande rien de nouveau à aucune des deux images. La nouveauté vient de l'extérieur : les images de MetalLB et d'Envoy, qui ne se chargent pas avec `kind load`, mais que chaque nœud télécharge depuis internet la première fois, comme celle de `curl` dans la Leçon 3.

## Les concepts

### 6.1 Le cluster de la leçon

#### 6.1.1 Avant de créer : une règle de cohabitation

C'est la première leçon du cours qui installe **MetalLB**, et MetalLB a une particularité qui impose une règle nouvelle. Il va prendre des adresses IP dans le réseau `kind` de Docker, le réseau que partagent **tous** les clusters kind de ta machine. Si deux clusters avec MetalLB et la même plage tournent en même temps, les deux annoncent les mêmes adresses et se marchent dessus : certaines requêtes arrivent à l'un, d'autres à l'autre. Avant de créer ton cluster, vérifie donc deux choses :

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar ya en 172.18.255.200. Si este curl responde algo,
# hay otro clúster con MetalLB vivo: espera a que termine.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 3 http://172.18.255.200/
```

Le réseau `kind` est créé par kind la première fois qu'il crée un cluster, donc la première commande échoue si tu n'en as jamais créé ; dans ce cas, crée le cluster et vérifie le réseau juste après, avant d'installer quoi que ce soit. Lors de l'exécution de cette leçon, le réseau se présentait ainsi :

```text
$ docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
fc00:f853:ccd:e793::/64 172.18.0.0/16 
```

Deux sous-réseaux : un IPv6 et l'IPv4 `172.18.0.0/16`, qui est celui qui compte. Si le tien est différent (par exemple `172.19.0.0/16`, parce que ta machine avait déjà un autre réseau en `172.18`), tu devras modifier la plage de `infra/metallb-pool.yaml` pour qu'elle soit comprise dans le tien, et toutes les IP de cette leçon seront différentes chez toi. Il y a une troisième vérification, la moins coûteuse : `kind get clusters`. Si tu vois un autre cluster en vie qui n'est pas le tien, demande à son propriétaire s'il utilise MetalLB et avec quelle plage avant de continuer ; le `curl` ne voit que celui qui répond en HTTP sur le port 80 de la `.200`, et le MetalLB de quelqu'un d'autre sur un autre port ou avec d'autres adresses de la plage (`.201` à `.220`) passerait sans que tu le remarques. `correr.sh` fait les deux premières et s'arrête avant de créer quoi que ce soit si l'une d'elles échoue ; si le réseau `kind` n'existe pas encore, il s'arrête aussi, parce qu'il ne peut pas lire sa plage. Dans ce cas, crée toi-même un cluster de test quelconque, regarde le réseau et supprime le cluster, ou crée le réseau manuellement avec le même sous-réseau.

#### 6.1.2 Créer, vérifier, charger

Depuis la racine du dépôt du cours, avec le même soin que d'habitude :

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta se queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l6.XXXX)/kubeconfig"
# curso-k8s-l6 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l6 --config programas/06-entrar-al-cluster/kind-curso.yaml
# Debe decir kind-curso-k8s-l6. Si dice otra cosa, no sigas.
kubectl config current-context
# Una guarda que se detiene sola (la de la Lección 5, con el nombre de este clúster).
# Va delante de cada comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l6
cd programas/06-entrar-al-cluster
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

La fonction `ctx` compare le contexte actif avec celui que tu attends. S'ils coïncident, elle n'affiche rien et renvoie un succès ; sinon, elle écrit « contexto equivocado: no sigo » (« mauvais contexte : je ne continue pas ») et renvoie une erreur, et le `&&` fait que la commande qui suit **ne s'exécute pas**. C'est la différence entre vérifier le contexte « à l'œil », ce qui dépend de ton attention, et un garde-fou qui t'arrête même quand tu es pressé. Aujourd'hui, tu vas installer des composants qui créent des dizaines d'objets dans le cluster, y compris des objets qui valent pour tout le cluster et non pour un espace de noms ; les appliquer dans le mauvais contexte reviendrait à les installer dans le cluster de quelqu'un d'autre. C'est pourquoi, **devant chaque** `apply`, `delete` ou `patch` de cette leçon, il y a `ctx &&`. Dans les sorties qui suivent, on l'omet pour qu'elles tiennent en largeur, mais dans ton terminal il est toujours là. (`correr.sh` fait de même pour chaque commande.)

Le `(umask 077; …)` mérite une explication. Le `umask` est le masque qui indique à ton shell quelles permissions **retirer** à tout nouveau fichier ; avec le masque habituel (`022`), `token.txt` naîtrait `-rw-r--r--`, lisible par n'importe quel utilisateur de la machine. Avec `077`, il naît `-rw-------` : toi seul. Les parenthèses font que le changement de masque ne vaut que pour cette commande et ne reste pas dans ton terminal. C'est le même soin que dans les Leçons 4 et 5, et il pèse davantage aujourd'hui, parce que cette leçon parle de machines partagées.

```text
$ kubectl config current-context
kind-curso-k8s-l6

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l6-control-plane  Ready   v1.37.0  172.18.0.4
curso-k8s-l6-worker         Ready   v1.37.0  172.18.0.3
curso-k8s-l6-worker2        Ready   v1.37.0  172.18.0.2
```

La nouvelle colonne est `INTERNAL-IP` : l'adresse de chaque nœud **dans le réseau `kind`** de Docker. Souviens-toi de la Leçon 0 : un nœud kind est un conteneur ; voici l'IP de ce conteneur. Les trois se situent au début de `172.18.0.0/16`, parce que Docker distribue les adresses en partant du bas. Retiens-les : en 6.3, un client de l'extérieur va entrer par elles.

`kind load` affiche ses six lignes habituelles, `not yet present on node … loading...`, deux images sur chacun des trois nœuds. Elles sont dans `correr.salida.txt`.

#### 6.1.3 Le client de l'extérieur

Pour tester depuis l'extérieur du cluster, cette leçon utilise un conteneur `curl` connecté au réseau `kind`, nommé `curso-k8s-l6-cliente`, avec `--rm` pour qu'il se supprime tout seul à la fin de chaque requête. C'est un vrai client : ce n'est pas un Pod, le cluster ne le connaît pas, il ne passe ni par le DNS du cluster ni par un `kube-proxy` de son côté. Il voit le réseau comme le verrait une machine connectée au même segment que les nœuds. Pour ne pas écrire la ligne complète à chaque fois, définis une fonction dans ton terminal :

```bash
afuera() {
  docker run --rm --network kind --name curso-k8s-l6-cliente \
    curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 "$@"
}
# Uso:  afuera -s -m 5 http://172.18.255.200/salud
```

Dans les sorties de cette leçon, **les lignes qui commencent par `$ curl` s'exécutent ainsi**, depuis ce conteneur, sauf une dans la section de l'habitude de sécurité, qui s'exécute exprès dans ton terminal et le précise. Sous Linux Mint, tu peux utiliser `curl` directement depuis ton terminal si tu préfères ; le résultat doit être le même.

Un avertissement pour la machine partagée : quand tu passes le token avec `-H "Authorization: Bearer $(cat token.txt)"`, le token devient un **argument de la commande**, et tant que la commande s'exécute, n'importe quel utilisateur de la machine le voit dans la liste des processus (`ps`). Pour le token factice de ce cours, cela ne pose pas de problème ; avec un vrai token, on le passe depuis un fichier (`-H @fichier`, que `curl` accepte depuis la version 7.55) ou par l'entrée standard, jamais écrit sur la ligne de commande.

### 6.2 Le projet avant la plateforme

#### 6.2.1 Ce que contient le dossier

Le dossier de cette leçon contient ce qu'a laissé la Leçon 5 — les deux Deployments, les deux Services, le générateur du `ConfigMap` et celui du `Secret` — plus deux nouveaux fichiers. Le `kustomization.yaml` les mentionne déjà. C'est un **programme** : `programas/06-entrar-al-cluster/kustomization.yaml`.

```yaml
# kustomization.yaml — Lecciones 4 a 6. Se aplica con: kubectl apply -k .
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Antes de esta kustomization van las piezas de infra/ (MetalLB y Envoy Gateway):
# sin sus CRD, Gateway y HTTPRoute no existen. Ver correr.sh para el orden.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
- revisor-publico.yaml
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

Les deux nouvelles lignes de `resources` sont `revisor-publico.yaml` (6.3) et `gateway.yaml` (6.7). Le commentaire du haut annonce déjà ce que tu vas vérifier maintenant : « avant cette kustomization viennent les pièces de `infra/` ». Fais ce que ferait n'importe qui de pressé à 16 h 40 : ignore l'avertissement et applique.

#### 6.2.2 Appliquer sans plateforme

```text
$ kubectl get crd
No resources found

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
[código de salida: 1]
```

Lis la sortie en deux moitiés. En haut, sept objets `created` : tout ce que le cluster savait déjà identifier. Les noms des objets générés sont ceux de la Leçon 4 : `revisor-config-t6cm6872fk`, identique dans ton exécution parce que la liste n'a pas changé, et `revisor-token-…`, différent parce que ton token est nouveau. En bas, deux objets que le cluster **ne reconnaît pas** : « je ne trouve pas le type `Gateway` dans la version `gateway.networking.k8s.io/v1` », et la suggestion, en anglais, « assure-toi d'installer d'abord les CRD ». `kubectl` a appliqué ce qu'il a pu, a sauté le reste, et s'est terminé avec le code 1. Un script avec `set -e` s'arrêterait ici ; un script sans cette option continuerait comme si de rien n'était, et c'est pire.

La première commande, `kubectl get crd`, l'annonçait déjà : `No resources found`. Ce cluster n'a **aucune** ressource personnalisée. Et la preuve directe :

```text
$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME   SHORTNAMES   APIVERSION   NAMESPACED   KIND
```

Rien que des en-têtes. Le groupe `gateway.networking.k8s.io` n'existe pas dans ce cluster.

#### 6.2.3 Ce qu'est un CRD

Jusqu'ici, tous les types que tu as utilisés — `Pod`, `Deployment`, `Service`, `ConfigMap`, `Secret` — sont **intégrés** à Kubernetes : le `kube-apiserver` les connaît dès son démarrage. `Gateway` et `HTTPRoute`, non. La [documentation des ressources personnalisées](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) le dit ainsi : une ressource personnalisée « est une extension de l'API Kubernetes qui n'est pas nécessairement disponible dans une installation par défaut ». Et elle explique comment en ajouter une : avec un objet `CustomResourceDefinition` (CRD). « Définir un objet CRD crée une nouvelle ressource personnalisée, avec le nom et le schéma que tu spécifies. L'API Kubernetes sert et stocke ta ressource personnalisée. »

Autrement dit : un CRD est un objet qui **apprend** au `kube-apiserver` un type nouveau. Tant que le CRD de `Gateway` n'existe pas, un manifeste avec `kind: Gateway` n'est, pour le cluster, qu'un texte qui ne signifie rien. C'est la première raison de l'ordre : **les types doivent exister avant les objets de ces types**.

La [page Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) de Kubernetes le dit à propos de son propre cas : Gateway API « est un module complémentaire (*add-on*) qui contient des types d'API » et ses spécifications « sont définies comme des ressources personnalisées ». Elle n'est pas fournie avec Kubernetes. Quelqu'un doit l'installer, et dans ce cours c'est Envoy Gateway qui l'installe (6.6).

Regarde ce qui a **bel et bien** été créé : le `revisor` et `prueba` tournent, avec leurs Services, et parmi eux `revisor-publico`. C'est exactement le point de départ dont cette leçon a besoin : ce qu'avait laissé la Leçon 5, plus un point d'entrée demandé et pas encore ouvert.

### 6.3 Un `LoadBalancer` sans personne pour distribuer les adresses

#### 6.3.1 Le manifeste

C'est un **programme** : `revisor-publico.yaml`.

```yaml
# revisor-publico.yaml — Lección 6: un Service LoadBalancer. Su EXTERNAL-IP la
# reparte MetalLB (infra/metallb-pool.yaml); sin MetalLB se queda en <pending>.
# En la Lección 7 se retira: la única puerta que queda es el Gateway.
apiVersion: v1
kind: Service
metadata:
  name: revisor-publico
  labels:
    app: revisor
spec:
  type: LoadBalancer
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

C'est le Service de la Leçon 3 avec deux différences : il s'appelle `revisor-publico` et son `type` est `LoadBalancer`. Même sélecteur, même `port: 80`, même `targetPort: http`. Il ne remplace pas le `revisor` en `ClusterIP` : les deux existent en même temps et choisissent les mêmes Pods. Celui de l'intérieur reste destiné aux clients de l'intérieur ; celui-ci est le point d'entrée vers l'extérieur. Avoir deux objets, et non un seul dont on aurait changé le type, est un choix délibéré : le jour où tu voudras fermer ce point d'entrée (la Leçon 7 le fait), tu supprimes `revisor-publico` et rien de ce qui se trouve à l'intérieur ne s'en aperçoit.

#### 6.3.2 `<pending>`

```text
$ kubectl get services
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes        ClusterIP      10.96.0.1       <none>        443/TCP        36s
prueba            ClusterIP      10.96.248.146   <none>        9000/TCP       7s
revisor           ClusterIP      10.96.157.248   <none>        80/TCP         7s
revisor-publico   LoadBalancer   10.96.115.79    <pending>     80:30808/TCP   7s
```

`EXTERNAL-IP <pending>` : le Service a demandé une IP externe et personne ne la lui a donnée. La [documentation des Services](https://kubernetes.io/docs/concepts/services-networking/service/) explique à qui revient ce travail : « chez les fournisseurs de cloud qui prennent en charge les équilibreurs de charge externes, donner au champ `type` la valeur `LoadBalancer` provisionne un équilibreur de charge pour ton Service. La création effective de l'équilibreur de charge se fait de façon asynchrone, et les informations sur l'équilibreur provisionné sont publiées dans le champ `.status.loadBalancer` du Service ». Dans kind, il n'y a pas de fournisseur de cloud. Le champ reste vide et `kubectl` l'affiche comme `<pending>`, pour toujours, sans la moindre erreur :

```text
$ kubectl describe service revisor-publico | grep -E '^(Type|LoadBalancer Ingress|Port|NodePort|Endpoints|Events):'
Type:                     LoadBalancer
Port:                     http  80/TCP
NodePort:                 http  30808/TCP
Endpoints:                10.244.2.3:8080,10.244.1.2:8080,10.244.2.4:8080
Events:                   <none>
```

Il n'y a pas de ligne `LoadBalancer Ingress` (c'est là que figurerait l'IP) et il n'y a pas d'événements : personne n'a rien tenté, donc personne n'a échoué. C'est le genre d'état qui sème la confusion, parce que rien n'est en rouge. Le seul indice est le mot `<pending>`.

#### 6.3.3 Ce qu'il a bel et bien ouvert : un `NodePort` sur chaque nœud

Regarde à nouveau la colonne `PORT(S)` : `80:30808/TCP`. Et dans `describe`, `NodePort: http 30808/TCP`. Le Service a demandé un équilibreur de charge qui n'est jamais arrivé, mais quelque chose, lui, est bien arrivé : un **port sur les nœuds**. La même documentation l'explique : « pour mettre en œuvre un Service de `type: LoadBalancer`, Kubernetes commence en général par faire les mêmes changements que si tu avais demandé un Service de `type: NodePort`. Ensuite, le `cloud-controller-manager` configure l'équilibreur de charge externe pour qu'il transfère le trafic vers ce port de nœud ». Un `LoadBalancer`, c'est un `NodePort` **plus** quelqu'un à l'extérieur. Ici, ce quelqu'un manque, mais le `NodePort` est déjà ouvert. On le vérifie depuis le client de l'extérieur, sur l'IP d'un nœud de travail et sur celle du nœud de contrôle :

```text
$ curl -s -m 5 http://172.18.0.3:30808/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 http://172.18.0.4:30808/salud
{"estado":"vivo","version":"1.6.0"}
```

Les deux répondent. `172.18.0.3` est `worker` ; `172.18.0.4` est le nœud de **contrôle**, où ne tourne aucune réplique du `revisor`. Et pourtant il répond : le `kube-proxy` de chaque nœud, y compris celui du nœud de contrôle, écoute sur le 30808 et transfère vers une réplique, où qu'elle se trouve. C'est ce que la première proposition de la scène aurait laissé ouvert, et c'est ce qui est **déjà** ouvert même si l'IP externe n'arrive jamais.

La documentation dit comment l'éviter : avec `spec.allocateLoadBalancerNodePorts: false`, qui « ne doit être utilisé qu'avec des implémentations d'équilibreur de charge qui acheminent le trafic directement vers les Pods au lieu de passer par des ports de nœud ». Sa valeur par défaut est `true`. MetalLB en couche 2, celui qu'installe cette leçon, livre le trafic à un nœud et laisse `kube-proxy` le répartir, donc ce cours ne le désactive pas ; mais il le nomme, parce que « ce qui est exposé » inclut ce port, et la section de l'habitude de sécurité en tient compte.

### 6.4 MetalLB : celui qui distribue les adresses, à l'intérieur du cluster

#### 6.4.1 Ce que c'est

MetalLB est un équilibreur de charge pour les clusters qui ne vivent pas dans un cloud : ceux d'un centre de données en propre, ceux de chez toi et ceux de kind. Son [guide d'installation](https://metallb.io/installation/) décrit ses deux pièces : le `controller`, un Deployment, « le contrôleur à l'échelle du cluster qui se charge d'attribuer les adresses IP » ; et le `speaker`, un DaemonSet (un Pod par nœud), « le composant qui parle les protocoles de ton choix pour rendre les Services joignables ». Le premier décide quelle IP revient à chaque Service. Le second fait exister cette IP sur le réseau.

Dans cette leçon, MetalLB travaille en **couche 2**. Son [guide de configuration](https://metallb.io/configuration/) l'explique en une phrase : « il fonctionne en répondant directement aux requêtes ARP de ton réseau local, pour donner aux clients l'adresse MAC de la machine ». ARP est la question que pose un équipement sur un réseau local pour savoir qui possède une IP : « qui a `172.18.255.200` ? ». Aucune machine n'a cette IP configurée. Mais le `speaker` d'un nœud répond « moi », et à partir de ce moment le trafic vers cette IP arrive à ce nœud, où `kube-proxy` le répartit entre les répliques. C'est une astuce honnête : il n'y a pas d'appareil équilibreur de charge, il y a un nœud qui prend l'adresse en charge.

#### 6.4.2 Installer : les CRD et le *webhook*

L'installation tient en un manifeste de la publication v0.16.1, celui que donne le guide officiel, figé à cette version. Ce cours l'enveloppe dans une kustomization pour pouvoir l'appliquer avec `-k` comme tout le reste. C'est un **programme** : `infra/metallb/kustomization.yaml`.

```yaml
# MetalLB v0.16.1 (modo nativo, capa 2), instalado SOLO en este clúster.
# Es la versión que indica la guía oficial de instalación (metallb.io/installation).
# Se aplica antes que todo lo demás de la Lección 6: kubectl apply -k infra/metallb
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
```

Le guide dit une chose qui vaut la peine d'être lue avant d'appliquer : sans configuration, « les composants de MetalLB démarrent, mais restent inactifs » tant que tu ne leur donnes pas de plage. Il y a donc deux étapes : installer et donner la plage. Fais encore une fois ce que ferait n'importe qui de pressé : les deux à la suite.

```text
$ kubectl apply -k infra/metallb | tail -5
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply -f infra/metallb-pool.yaml
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
[código de salida: 1]
```

Une erreur différente de celle de 6.2. Cette fois, le type existe **bel et bien** — l'`apply` de MetalLB a créé ses CRD au même instant — et pourtant le cluster a rejeté les deux objets. Lis-la de droite à gauche : `connect: connection refused` vers `10.96.93.252:443` ; cette IP est celle du Service `metallb-webhook-service` qui venait d'être créé (`created`, à la deuxième ligne de la sortie précédente) ; et ce qui échouait, c'était « l'appel au *webhook* `ipaddresspoolvalidationwebhook.metallb.io` ».

Un ***webhook* d'admission** est un autre gardien que la plateforme ajoute au `kube-apiserver`. La [documentation des contrôleurs d'admission extensibles](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) les définit ainsi : « les *webhooks* d'admission sont des rappels HTTP qui reçoivent des requêtes d'admission et en font quelque chose ». Ceux de validation « peuvent rejeter des requêtes pour faire respecter des politiques personnalisées ». MetalLB en installe un pour vérifier qu'une plage est bien écrite avant de l'accepter. Avant d'enregistrer ton `IPAddressPool`, le `kube-apiserver` interroge le *webhook*. Mais le Pod qui répond à cette question, le `controller`, était encore en train de démarrer. Personne n'écoutait sur le 443. Et que fait le `kube-apiserver` quand il ne peut pas poser la question ? C'est un champ du *webhook* qui le décide, `failurePolicy`. La même page le dit : avec `failurePolicy: Fail`, qui est la valeur par défaut, « une erreur lors de l'appel du *webhook* fait échouer l'admission et la requête est rejetée ». MetalLB l'écrit explicitement dans ses six *webhooks* (on peut le vérifier, et l'exécution le vérifie plus bas) : mieux vaut rejeter que laisser passer un objet sans le vérifier.

C'est la deuxième raison de l'ordre : **les gardiens doivent être à l'écoute avant que n'arrive ce qu'ils vont vérifier**. La politique du *webhook* de MetalLB se lit dans le cluster lui-même ; il y a une valeur pour chacun de ses six gardiens :

```text
$ kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Fail Fail Fail Fail Fail Fail
```

Six `Fail` : aucun ne laisse passer un objet s'il ne peut pas le vérifier. Et il ne suffit pas que le CRD existe :

```text
$ kubectl get crd -o name | grep metallb.io
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io
```

Neuf nouveaux types, tous du groupe `metallb.io`. Plusieurs servent à l'autre mode de MetalLB, BGP, que ce cours n'utilise pas. Les deux d'aujourd'hui sont `ipaddresspools` et `l2advertisements`.

#### 6.4.3 Attendre, avec `kubectl wait`

La correction ne consiste pas à réessayer jusqu'à ce que ça passe. Elle consiste à **attendre une condition**, puis à appliquer :

```text
$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl apply -f infra/metallb-pool.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
```

La [référence de `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) la décrit : la commande « prend plusieurs ressources et attend que la condition indiquée apparaisse dans le champ `Status` de chacune ». `condition=Available` sur un Deployment veut dire qu'il dispose de la disponibilité **minimale** que permet sa stratégie de mise à jour (c'est ainsi que la documentation des Deployments la définit). Avec le `controller` de MetalLB, qui n'a qu'une seule réplique, cela revient à « sa seule réplique est prête » ; « prête » au sens de la Leçon 5, celui des readiness probes. Avec un Deployment de trois répliques et un `maxUnavailable` de 25 %, `Available` arriverait avec moins de répliques prêtes qu'il n'en demande : ne le lis pas comme « toutes ». Dans cette exécution, dès que le `controller` a été `Available`, le *webhook* répondait déjà. Pour le DaemonSet, on utilise `rollout status`, la même commande que dans la Leçon 2, qui attend qu'il y ait un `speaker` prêt sur chacun des trois nœuds. Avec `--timeout`, aucune attente n'est infinie : si quelque chose n'arrive pas, la commande échoue et tu le sais.

Même fichier, sans changer une virgule, et cette fois `created`. Le fichier n'a jamais été faux. Il était en avance.

```text
$ kubectl get pods -n metallb-system -o wide | awk '{print $1, $2, $3, $6, $7}' | column -t
NAME                         READY  STATUS   IP          NODE
controller-76f4cf76b7-hpzjj  1/1    Running  10.244.1.3  curso-k8s-l6-worker
speaker-455xp                1/1    Running  172.18.0.3  curso-k8s-l6-worker
speaker-jvbvh                1/1    Running  172.18.0.2  curso-k8s-l6-worker2
speaker-xctwr                1/1    Running  172.18.0.4  curso-k8s-l6-control-plane
```

Un `controller` avec une IP du réseau des Pods (`10.244.`) et trois `speaker`, un par nœud, avec l'IP **du nœud** (`172.18.0.`). Ce dernier point n'est pas un hasard : le `speaker` doit répondre aux requêtes ARP sur le réseau `kind`, donc il tourne avec le réseau du nœud, pas avec le réseau des Pods.

#### 6.4.4 La plage

C'est un **programme** : `infra/metallb-pool.yaml`.

```yaml
# metallb-pool.yaml — las IP que MetalLB puede repartir a los Services LoadBalancer.
# Salen de la red «kind» de Docker (en la máquina de las corridas, 172.18.0.0/16;
# compruébala con: docker network inspect kind). Se toma el final del rango, lejos
# de las IP que Docker da a los nodos.
# ⚠️ Dos clústeres de kind con MetalLB y el MISMO rango en la misma red se pisan
# (los dos anuncian las mismas IP): en una máquina compartida, un rango por clúster.
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: curso
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: curso
  namespace: metallb-system
spec:
  ipAddressPools:
  - curso
```

Deux objets, deux décisions :

- **`IPAddressPool`** dit **quelles** adresses MetalLB peut distribuer : de `172.18.255.200` à `172.18.255.220`, vingt et une. Le guide de configuration : « toutes les IP attribuées au moyen d'`IPAddressPool` contribuent à l'ensemble d'IP que MetalLB utilise pour attribuer des IP aux Services ». Pourquoi celles-là : elles doivent se trouver **dans** le réseau `kind` (sinon, personne sur ce réseau ne les demanderait) et **loin** de celles que Docker distribue aux conteneurs, qui commencent par le bas (`172.18.0.2`, `.3`, `.4`). La fin du réseau est l'endroit le plus sûr.
- **`L2Advertisement`** dit **comment** elles sont annoncées : en couche 2, par ARP. Le guide : « pour annoncer l'IP issue d'un `IPAddressPool`, il faut lui associer une instance de `L2Advertisement` ». Sans ce second objet, MetalLB attribuerait l'IP et personne ne répondrait pour elle.

```text
$ kubectl get ipaddresspool,l2advertisement -n metallb-system
NAME                             AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ipaddresspool.metallb.io/curso   true          false             ["172.18.255.200-172.18.255.220"]

NAME                               IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
l2advertisement.metallb.io/curso   ["curso"]                                  
```

`AUTO ASSIGN true` : MetalLB prend des IP dans cette plage pour n'importe quel `LoadBalancer` qui en demande, sans que le Service ait à nommer la plage.

#### 6.4.5 La première IP

```text
$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.115.79   172.18.255.200   80:30808/TCP   119s
```

`172.18.255.200`, la première de la plage. Le Service était en `<pending>` depuis presque deux minutes ; personne ne l'a réappliqué. Dès qu'il a eu une plage, MetalLB a cherché les `LoadBalancer` sans IP et leur en a donné une. C'est encore le thermostat de la Leçon 0 : l'état souhaité était écrit depuis 6.2, et dès qu'il y a eu quelqu'un pour le poursuivre, il a été atteint. Le `NodePort` est toujours `30808` : l'IP externe s'est ajoutée **par-dessus** le port de nœud, comme le dit la documentation.

Qui l'a fait, et depuis où ? Les événements du Service, qui étaient vides en 6.3, le disent :

```text
$ kubectl get events --field-selector involvedObject.name=revisor-publico --sort-by=.lastTimestamp | awk '{$1=""; print}' | sed 's/^ //'
SEEN TYPE REASON OBJECT MESSAGE
Normal IPAllocated service/revisor-publico Assigned IP ["172.18.255.200"]
Normal nodeAssigned service/revisor-publico announcing from node "curso-k8s-l6-worker2" with protocol "layer2"
```

(`awk` retire la colonne de l'âge pour que la sortie tienne en largeur ; l'en-tête conserve son nom.) Deux événements, tous deux de MetalLB : `IPAllocated`, du `controller`, qui a choisi l'IP ; et `nodeAssigned`, du `speaker`, qui dit depuis quel nœud il l'annonce : `curso-k8s-l6-worker2`, en couche 2. Dans ton exécution, le nœud peut être un autre. Ce nœud est désormais le point d'entrée physique de `172.18.255.200` : en cas de panne, un autre `speaker` reprend l'annonce.

Et la preuve qui compte, depuis l'extérieur :

```text
$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           7ms  200
```

Une adresse stable, sur le port 80, sans numéro bizarre, qui répartit entre les trois répliques et qui reste là même si les Pods changent. Ce dont le tableau de bord de la scène avait besoin. (Les `…` remplacent le token dans les sorties publiées ; dans ton terminal, c'est le contenu de `token.txt` qui y figure, avec `-H "Authorization: Bearer $(cat token.txt)"`.)

### 6.5 Pourquoi pas Cloud Provider KIND

Si tu cherches « LoadBalancer dans kind », la première réponse est celle de kind lui-même. Son [guide LoadBalancer](https://kind.sigs.k8s.io/docs/user/loadbalancer/) recommande **Cloud Provider KIND**, et son [guide Ingress](https://kind.sigs.k8s.io/docs/user/ingress/) dit que, depuis la v0.9.0, ce programme « prend en charge Ingress de façon native » et que Gateway API « est également prise en charge de façon native ». C'est un outil sérieux, maintenu par le même groupe que kind. Pourquoi ce cours ne l'utilise-t-il pas ?

À cause de **l'endroit où il tourne** et de **ce sur quoi il agit**. Le guide de kind le dit : Cloud Provider KIND « tourne comme un binaire indépendant sur ta machine et se connecte à ton cluster kind », et « nécessite des privilèges pour ouvrir des ports sur le système et pour se connecter au *runtime* de conteneurs ». Son [README](https://github.com/kubernetes-sigs/cloud-provider-kind) est plus précis : « `cloud-provider-kind` va surveiller **tous** tes clusters kind », et son contrôleur Gateway API « est activé par défaut ». Le README ne décrit aucune option pour se limiter à un seul.

Sur ton ordinateur portable personnel, avec un seul cluster, cela n'a pas d'importance. Sur une machine partagée — celle d'un laboratoire, celle d'une équipe qui exécute des tests en parallèle, ou la tienne si tu as un cluster d'un autre projet — cela compte beaucoup : un processus que tu as lancé pour ta leçon se mettrait à créer des équilibreurs de charge, des CRD et une `GatewayClass` dans des clusters qui ne sont pas les tiens, sans que leurs propriétaires l'aient demandé. Ce cours a une règle depuis la Leçon 1 : ne pas toucher à ce qui n'est pas à toi, ni à un autre contexte, ni à un autre cluster. Cloud Provider KIND l'enfreint par conception.

MetalLB et Envoy Gateway, en revanche, sont des objets **à l'intérieur** du cluster. Ils s'installent avec `kubectl` dans ton contexte, vivent dans leurs espaces de noms (`metallb-system`, `envoy-gateway-system`) et disparaissent avec `kind delete cluster`. Le prix est celui que tu as vu en 6.1 : la plage de MetalLB provient du réseau `kind`, qui, lui, est partagé, et c'est pourquoi deux clusters avec la même plage ne doivent pas tourner en même temps. C'est un prix que l'on maîtrise avec une vérification d'une ligne. L'autre, on ne le maîtrise pas.

### 6.6 Envoy Gateway et Gateway API : la plateforme du point d'entrée

#### 6.6.1 Les trois pièces de Gateway API

Un `LoadBalancer`, c'est un point d'entrée par Service : chacun avec son IP. Si demain tu publies cinq services, cela fait cinq IP, et aucune ne connaît quoi que ce soit à HTTP : aucune ne peut décider selon le chemin ou le nom du site, ni appliquer un chiffrement commun. Gateway API résout cela avec **un seul** point d'entrée qui comprend HTTP et des règles qui disent ce qui entre et où cela va. La [page Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) de Kubernetes décrit ses trois pièces :

| Pièce | Ce que c'est, selon la documentation | Dans ce cours |
|---|---|---|
| `GatewayClass` | « définit un ensemble de points d'entrée ayant une configuration commune, gérés par un contrôleur qui implémente la classe » | `eg`, celle d'Envoy Gateway |
| `Gateway` | « définit une instance d'infrastructure qui gère le trafic, comme un équilibreur de charge du cloud » | `revisor` : écoute en HTTP sur le 80 |
| `HTTPRoute` | « définit des règles propres à HTTP pour acheminer le trafic d'un *listener* du Gateway vers une représentation d'*endpoints* réseau », qui « sont souvent représentés par un Service » | `revisor` : tout ce qui arrive va au Service `revisor` |

La même page explique pourquoi il y en a trois et pas une seule : Gateway API est « orientée rôles ». La `GatewayClass` relève du **fournisseur d'infrastructure** ; le `Gateway`, de l'**opérateur du cluster**, qui s'occupe des « politiques, de l'accès réseau et des permissions » ; la `HTTPRoute`, du **développeur de l'application**, qui s'occupe de son Service. Dans ton cluster, tu joues les trois rôles, mais les fichiers sont déjà séparés ainsi : `infra/gatewayclass.yaml` relève de la plateforme, `gateway.yaml` du projet.

#### 6.6.2 Installer avec `--server-side`, et pourquoi

Envoy Gateway fournit dans un seul fichier les CRD de Gateway API et les siens. Son [guide d'installation](https://gateway.envoyproxy.io/docs/install/install-yaml/) le dit : « le manifeste `install.yaml` inclut les CRD de Gateway API et les CRD d'Envoy Gateway ». Ce cours l'enveloppe de la même façon que MetalLB. C'est un **programme** : `infra/envoy-gateway/kustomization.yaml`.

```yaml
# Envoy Gateway v1.9.2, instalado SOLO en este clúster. Trae los CRD de Gateway API
# (bundle v1.6.1) y los suyos. Su guía oficial lo instala con server-side apply:
#   kubectl apply --server-side -k infra/envoy-gateway
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/envoyproxy/gateway/releases/download/v1.9.2/install.yaml
```

Le guide officiel l'installe avec `kubectl apply --server-side`. Que se passe-t-il sans cette option ? On peut le demander sans rien changer, avec `--dry-run=server`, qui envoie tout au `kube-apiserver` pour qu'il le valide et n'enregistre rien :

```text
$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -c 'Too long'
3

$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -m 1 'Too long' | sed 's/.*\(The CustomResourceDefinition\)/\1/'
Error from server (Invalid): error when creating "infra/envoy-gateway": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(Dans `correr.salida.txt`, sous chacune de ces deux commandes apparaît `[código de salida: 1]`. C'est le code du `kubectl apply`, dont la tentative a été rejetée par le `kube-apiserver`. Le script s'exécute avec `pipefail`, qui fait échouer un pipeline si l'une de ses commandes échoue. Dans ton terminal, sans `pipefail`, le pipeline renvoie le code de `grep`, qui est 0, et tu ne verras pas cette ligne.) Trois CRD rejetés, pour le même motif : « `metadata.annotations` : trop long ; ne peut pas dépasser 262 144 octets ». La cause tient au fonctionnement de l'`apply` habituel, celui que tu utilises depuis la Leçon 2. Cet `apply` enregistre dans chaque objet une annotation, `kubectl.kubernetes.io/last-applied-configuration`, avec **une copie complète** du manifeste que tu as appliqué, pour pouvoir calculer la différence la fois suivante. Avec un Deployment, cette copie pèse quelques kilo-octets. Avec le CRD d'`EnvoyProxy`, dont le schéma décrit des centaines de champs, la copie dépasse le plafond de 256 Kio que le `kube-apiserver` accepte pour l'ensemble des annotations d'un objet.

`--server-side` change qui tient les comptes. La [documentation de *server-side apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) l'explique : il offre « un mécanisme permettant au plan de contrôle de ton cluster de suivre les modifications apportées aux champs d'un objet », et le compare à l'annotation de `kubectl` : au lieu d'enregistrer « le dernier état appliqué », il note quels champs gère chacun, dans `metadata.managedFields`. Pas de copie du manifeste, pas d'annotation géante.

```text
$ kubectl apply --server-side -k infra/envoy-gateway | tail -4
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl get crd -o name | grep -c gateway.networking.k8s.io
10

$ kubectl get crd -o name | grep -c gateway.envoyproxy.io
8
```

Chaque ligne dit `serverside-applied` au lieu de `created`. Les quatre dernières racontent déjà l'histoire de cette leçon : une politique de validation d'admission (`safe-upgrades`, « mises à jour sûres », d'après son nom), un `Job` appelé `certgen` qui, d'après son nom, génère des certificats, et un autre *webhook*, cette fois de ceux qui **modifient** les objets (`mutatingwebhookconfiguration`). Encore des gardiens. Mais tous ne bloquent pas : celui-ci déclare `failurePolicy: Ignore`, c'est-à-dire que s'il ne répond pas, le `kube-apiserver` laisse passer la requête. Lequel fait quoi, cela se lit dans le manifeste, cela ne se suppose pas (l'exécution le montre plus bas). Dix CRD de Gateway API et huit d'Envoy Gateway. Il y en a d'autres, et on les mesure :

```text
$ kubectl get crd -o name | grep gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io

$ kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.annotations.gateway\.networking\.k8s\.io/channel} {.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}{end}' | grep 'gateway.networking.k8s.io ' | column -t
backendtlspolicies.gateway.networking.k8s.io  experimental  v1.6.1
gatewayclasses.gateway.networking.k8s.io      experimental  v1.6.1
gateways.gateway.networking.k8s.io            experimental  v1.6.1
grpcroutes.gateway.networking.k8s.io          experimental  v1.6.1
httproutes.gateway.networking.k8s.io          experimental  v1.6.1
listenersets.gateway.networking.k8s.io        experimental  v1.6.1
referencegrants.gateway.networking.k8s.io     experimental  v1.6.1
tcproutes.gateway.networking.k8s.io           experimental  v1.6.1
tlsroutes.gateway.networking.k8s.io           experimental  v1.6.1
udproutes.gateway.networking.k8s.io           experimental  v1.6.1

$ kubectl get mutatingwebhookconfiguration envoy-gateway-topology-injector.envoy-gateway-system -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Ignore
```

On y lit trois choses. Dix CRD de `gateway.networking.k8s.io`, **tous** du canal `experimental` et du paquet `v1.6.1` de Gateway API (le canal standard ne contiendrait que ce qui est stable ; l'expérimental apporte en plus des champs et des versions à l'essai). Trois CRD de plus, du groupe `gateway.networking.x-k8s.io`, que le `grep -c` du haut ne comptait pas : le `x` vient d'*experimental*. Et un *webhook* de mutation avec `failurePolicy: Ignore`. Le `column -t` ne fait qu'aligner le tableau. Au total, donc : dix plus trois de Gateway API et huit d'Envoy Gateway.

#### 6.6.3 Attendre, encore une fois, et la classe

Avant d'utiliser les nouveaux types, on attend qu'ils soient **établis**, et avant de demander un point d'entrée, que le contrôleur soit disponible :

```text
$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met
```

`Established` est la condition que le `kube-apiserver` attribue à un CRD quand il sert déjà le nouveau type. Un CRD fraîchement créé peut mettre un moment à l'être ; attendre la condition, c'est interroger le cluster au lieu de deviner. Ici, ils l'étaient déjà : `condition met` immédiatement. Le second `wait` est identique à celui que tu as utilisé avec le `controller` de MetalLB, cette fois avec le contrôleur d'Envoy Gateway.

Maintenant, la classe. C'est un **programme** : `infra/gatewayclass.yaml`.

```yaml
# gatewayclass.yaml — «eg»: la clase de puerta que atiende Envoy Gateway.
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

Une `GatewayClass` est courte : un nom, `eg`, et le contrôleur qui la prend en charge. Le `controllerName` n'est pas décoratif : c'est la signature grâce à laquelle le contrôleur d'Envoy Gateway reconnaît les classes qui le concernent. Si tu en écrivais un autre, la classe existerait et personne ne l'accepterait.

```text
$ kubectl apply -f infra/gatewayclass.yaml
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl get gatewayclass
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       0s

$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME                 SHORTNAMES   APIVERSION                     NAMESPACED   KIND
backendtlspolicies   btlspolicy   gateway.networking.k8s.io/v1   true         BackendTLSPolicy
gatewayclasses       gc           gateway.networking.k8s.io/v1   false        GatewayClass
gateways             gtw          gateway.networking.k8s.io/v1   true         Gateway
grpcroutes                        gateway.networking.k8s.io/v1   true         GRPCRoute
httproutes                        gateway.networking.k8s.io/v1   true         HTTPRoute
listenersets         lset         gateway.networking.k8s.io/v1   true         ListenerSet
referencegrants      refgrant     gateway.networking.k8s.io/v1   true         ReferenceGrant
tcproutes                         gateway.networking.k8s.io/v1   true         TCPRoute
tlsroutes                         gateway.networking.k8s.io/v1   true         TLSRoute
udproutes                         gateway.networking.k8s.io/v1   true         UDPRoute
```

Entre l'`apply` et le `get`, il y a un troisième `wait`, cette fois sur la condition `Accepted` de la classe : le contrôleur met quelques secondes à la reconnaître, et sans cette attente ton `get` pourrait afficher `ACCEPTED Unknown`. `ACCEPTED True` : Envoy Gateway a reconnu la classe comme la sienne. Et le même `api-resources` qui en 6.2 ne donnait que des en-têtes donne maintenant dix types, que `api-resources` affiche en `v1`. Attention à ce mot : c'est la version **préférée** que sert le cluster, pas une garantie que tout est stable. L'`install.yaml` d'Envoy Gateway installe les CRD du canal **expérimental** de Gateway API (c'est ce que dit l'annotation `gateway.networking.k8s.io/channel: experimental` de chaque CRD, et l'exécution la lit plus haut), qui apporte, en plus de ce qui est stable, des champs et des versions à l'essai, et trois types de plus du groupe `gateway.networking.x-k8s.io`. Les trois qu'utilise cette leçon, `GatewayClass`, `Gateway` et `HTTPRoute`, sont stables. Dans un vrai cluster, on décide délibérément quel canal on installe. Aujourd'hui, tu en utilises trois. `GRPCRoute`, `TCPRoute` et `UDPRoute` sont des routes pour d'autres protocoles ; `TLSRoute` et `BackendTLSPolicy` servent respectivement à laisser passer le chiffrement sans l'ouvrir et à chiffrer le tronçon qui va du point d'entrée au Service, deux choses que cette leçon ne met pas en place. `ReferenceGrant` est la permission que donne le propriétaire d'un espace de noms pour qu'un élément d'un **autre** espace pointe vers ses objets : par exemple, une route qui envoie du trafic vers un Service appartenant à un autre espace, ou un Gateway qui utilise un certificat stocké dans un `Secret` d'un autre espace. Dans ce cours, la route et le Service vivent toujours dans le même espace, donc tu n'en auras pas besoin. Qu'une route se rattache à un Gateway d'un **autre** espace ne se décide pas avec `ReferenceGrant`, mais avec le champ `allowedRoutes` du *listener* du Gateway ; la [documentation de Gateway](https://kubernetes.io/docs/concepts/services-networking/gateway/) le dit ainsi : « par défaut, un Gateway n'accepte que les routes du même espace de noms ». Regarde la colonne `NAMESPACED` : `gatewayclasses` vaut `false`, parce qu'une classe vaut pour tout le cluster. C'est de la plateforme.

### 6.7 Le point d'entrée du `revisor`

#### 6.7.1 Le manifeste

C'est un **programme** : `gateway.yaml`.

```yaml
# gateway.yaml — Lección 6: Gateway API, la sucesora de Ingress.
# La puerta (Gateway «revisor», clase «eg» de Envoy Gateway) recibe una IP de
# MetalLB; la ruta (HTTPRoute) manda todo al Service revisor. Solo HTTP: el
# cifrado en tránsito es lo que la lección dice que falta.
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: revisor
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisor
      port: 80
```

Deux objets dans un fichier, séparés par `---`. Ils se lisent ainsi :

- **Le `Gateway`** demande un point d'entrée de la classe `eg` avec un *listener* (une oreille) : `http`, protocole `HTTP`, port `80`. Il ne dit rien de l'IP : c'est Envoy Gateway qui la demande à celui qui les distribue, et dans ce cluster c'est MetalLB.
- **La `HTTPRoute`** se rattache à ce point d'entrée avec `parentRefs: [revisor]` et a une règle : ce qui commence par `/` (`PathPrefix`), c'est-à-dire tout, va au Service `revisor` sur son port `80`. Regarde la destination : le `revisor` en `ClusterIP` de la Leçon 3, pas `revisor-publico`. Le point d'entrée entre dans le cluster et, de là, utilise le Service intérieur, avec son EndpointSlice et sa répartition.

La [référence d'`HTTPRoute`](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) dit en outre que, si tu n'écris pas `matches`, la valeur par défaut est justement celle-ci, un préfixe `/`, « qui a pour effet de correspondre à toute requête HTTP ». Le cours l'écrit malgré tout, pour la même raison qu'il a écrit `type: ClusterIP` : pour que la décision « tout passe » reste visible. L'Exercice 2 la change.

#### 6.7.2 Appliquer, cette fois pour de bon

La même commande qu'en 6.2, avec la plateforme en place :

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bmkbmd25cg unchanged
service/prueba unchanged
service/revisor unchanged
service/revisor-publico unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Sept `unchanged` et deux `created`. Rien n'a redémarré : le `Secret` a gardé son nom parce que `token.txt` est le même qu'en 6.2, et le Deployment n'avait aucune raison de faire un *rollout*. `apply` est déclaratif, et l'appliquer deux fois est sans danger : ce qui était déjà là reste. C'est pourquoi la correction de l'erreur d'ordre n'a pas été « tout supprimer et recommencer », mais installer ce qui manquait et réappliquer la même chose.

Le `wait` attend la condition `Programmed` du Gateway, c'est-à-dire que le contrôleur a déjà configuré l'infrastructure qui le prend en charge.

```text
$ kubectl get gateway,httproute
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.18.255.201   True         113s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               113s

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

Le Gateway a une adresse, `172.18.255.201`, la deuxième de la plage de MetalLB (la première appartenait déjà à `revisor-publico`), et `PROGRAMMED True`. La route a deux conditions, dont tu vas te servir dans « L'erreur que tu vas voir » : `Accepted=True`, le point d'entrée l'a acceptée comme sienne ; et `ResolvedRefs=True`, tout ce qu'elle nomme (le Service `revisor` et son port) existe.

#### 6.7.3 Qui s'occupe du point d'entrée

Un `Gateway` est une déclaration. Quelqu'un doit la rendre réelle :

```text
$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-default-revisor-4e6f5d7f-55b49857bd-25dqk   2/2     Running   0          113s
pod/envoy-gateway-5fc4949dcb-f8jss                    1/1     Running   0          5m44s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
service/envoy-gateway                    ClusterIP      10.96.233.233   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   5m45s
```

Deux Pods. `envoy-gateway` est le **contrôleur** : il lit tes `Gateway` et tes `HTTPRoute` et les traduit. `envoy-default-revisor-…` est le **proxy**, l'Envoy qui reçoit réellement les requêtes ; son nom réunit l'espace de noms du Gateway (`default`) et son nom (`revisor`). C'est le contrôleur qui l'a créé quand ton Gateway est apparu, avec un Service à lui **de type `LoadBalancer`**, et c'est ce Service qui a reçu `172.18.255.201` de MetalLB. Les deux plateformes de cette leçon travaillent ensemble sans se connaître : Envoy Gateway demande un `LoadBalancer`, MetalLB le lui donne.

Voici tous les `LoadBalancer` du cluster :

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
default                revisor-publico                  LoadBalancer   10.96.115.79    172.18.255.200   80:30808/TCP                                       8m21s
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
```

Deux points d'entrée vers le `revisor` : le direct, `.200`, et le nommé, `.201`. Retiens ce tableau pour l'habitude de sécurité.

#### 6.7.4 Entrer

```text
$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados
401

$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|server|content-type)"
HTTP/1.1 200 OK
content-type: application/json
```

Les trois réponses qui comptent : `/salud` répond, `/api/estados` avec le token donne le tableau, et sans token donne `401`. Ce `401`, c'est le **`revisor`** qui le renvoie, pas le point d'entrée : le Gateway laisse tout passer et le `revisor` continue d'exiger son token, comme depuis la Leçon 4. Le journal du `revisor` le confirme :

```text
$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /api/estados'
[pod/revisor-5674f7c4cc-bhbvp/revisor] revisor: GET /api/estados 200 17ms
[pod/revisor-5674f7c4cc-pbc9f/revisor] revisor: GET /api/estados 200 8ms
[pod/revisor-5674f7c4cc-w7hgf/revisor] revisor: GET /api/estados 401 1ms
```

(`kubectl logs -l` rassemble les journaux des trois répliques, regroupés par Pod et non par heure, donc l'ordre des lignes n'est pas celui des requêtes.) Jusque-là, il y a eu trois requêtes vers `/api/estados` : celle de 6.4.5 par la `.200`, celle du haut avec token par le point d'entrée et celle du haut sans token. Les trois apparaissent, et ce que l'on peut affirmer, c'est ce que dit le `401` : c'est un `revisor` qui l'a écrit dans son journal, donc c'est lui qui l'a renvoyé, et non le point d'entrée. Quelle réplique a traité chacune ne se déduit pas de cette sortie ; la répartition est assurée par le mécanisme habituel, le Service `revisor`, pas par le point d'entrée.

Le dernier `curl` du haut a demandé les en-têtes avec `-i` : `HTTP/1.1 200 OK`. Un détail de plus, que reprend la section de l'habitude de sécurité : c'est du HTTP/1.1 sur le port 80, sans chiffrement.

### 6.8 `Ingress`, l'API gelée, et pourquoi pas `ingress-nginx`

Tu vas trouver `Ingress` dans presque tous les tutoriels Kubernetes antérieurs à 2024. C'est l'ancêtre de ce que tu viens de faire : un objet qui dit « tel chemin va vers tel Service », pris en charge par un contrôleur. Il existe toujours, et la [documentation d'Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) énonce son état en toutes lettres : « l'API Ingress est gelée » ; « elle n'est plus développée et ne recevra plus de changements ni de mises à jour ». Et la recommandation : « le projet Kubernetes recommande d'utiliser Gateway plutôt qu'Ingress ». Attention à ce qu'elle ne dit **pas** : l'API n'est pas obsolète au sens où on va la retirer. La même page précise qu'il s'agit d'une API stable, soumise aux garanties des API stables, et que le projet « n'a pas l'intention de retirer Ingress de Kubernetes ». Gelée veut dire : elle fonctionne, elle ne grandit plus. Ce qui lui manque (des routes pour d'autres protocoles, des rôles séparés, des règles plus fines) ne lui viendra pas. Gateway API est née pour cela.

`ingress-nginx`, c'est autre chose : pas une API, mais **un contrôleur** d'Ingress, le plus populaire pendant des années, celui de la seconde proposition de la scène. En novembre 2025, le [blog de Kubernetes](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) a annoncé son retrait : « en mars 2026, la maintenance d'Ingress NGINX s'arrêtera et le projet sera retiré. Après cette date, il n'y aura plus de nouvelles versions, ni de corrections de bogues, ni de mises à jour pour combler les failles de sécurité qui seront découvertes ». Les installations existantes continuent de fonctionner et les artefacts restent téléchargeables, précise la même annonce. C'est pourquoi le tutoriel d'il y a deux ans « fonctionne » encore cet après-midi. Mais un composant qui reçoit du trafic de l'extérieur et ne reçoit plus de correctifs de sécurité est exactement ce qu'on n'installe pas aujourd'hui. L'annonce recommande de migrer vers Gateway API ou vers un autre contrôleur.

Trois noms, trois choses différentes :

| Nom | Ce que c'est | État |
|---|---|---|
| `Ingress` | une API de Kubernetes | gelée : elle fonctionne, elle ne grandit plus |
| `ingress-nginx` | un contrôleur qui prend en charge `Ingress` | retiré depuis mars 2026 : plus de correctifs |
| Gateway API | l'API qui succède à `Ingress` | en vigueur ; c'est celle qu'utilise ce cours |

L'Exercice 3 te permet de voir un `Ingress` dans ce cluster, et ce qui lui arrive quand personne ne le prend en charge.

### 6.9 L'ordre : plateforme, attente, projet

Rassemble ce que tu as vu. En 6.2, le projet avant la plateforme : `no matches for kind`. En 6.4, la plage avant le gardien : `failed calling webhook … connection refused`. En 6.6, le projet n'aurait pas pu non plus demander son Gateway avant que la classe `eg` n'existe. Dans les trois cas, le fichier était correct. Ce qui n'allait pas, c'était le moment.

Voici comment on déploie le contenu de cette leçon à partir d'un cluster vide, en trois étapes. Ce n'est pas un fragment écrit de mémoire : c'est le programme `levantar.sh`, et il a réellement été exécuté. `correr.sh` supprime le cluster des exercices, en crée un **autre** identique, avec les deux images chargées et sans la moindre ressource personnalisée (`kubectl get crd` donne `No resources found`), et exécute `levantar.sh` sans rien corriger manuellement :

```bash
#!/usr/bin/env bash
# levantar.sh — Lección 6, sección 6.9: la plataforma y el proyecto, desde un
# clúster recién creado, en tres pasos y en este orden:
#   1. la plataforma: los tipos nuevos (CRD), sus controladores y sus guardianes;
#   2. la espera: tipos establecidos y controladores listos (kubectl wait);
#   3. la configuración de la plataforma (rango y clase) y después el proyecto.
#
# Uso, desde esta carpeta y con el clúster curso-k8s-l6 recién creado, las dos
# imágenes cargadas y token.txt generado:   ./levantar.sh
#
# 🔴 Antes de CADA cambio, ctx comprueba que el contexto activo es
# kind-curso-k8s-l6 y, si no, el guion se detiene: MetalLB y Envoy Gateway crean
# objetos que valen para todo el clúster, y aplicarlos en otro sería instalarlos
# en el clúster de otra persona.
set -euo pipefail
cd "$(dirname "$0")"

ctx() { [ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo" >&2; return 1; }; }
# paso CADENA → comprueba el contexto, imprime «$ CADENA» y la corre. Si falla, se detiene.
paso() { ctx; printf '\n$ %s\n' "$*"; eval "$@"; }

[ -f token.txt ] || { echo "falta token.txt: (umask 077; openssl rand -hex 16 > token.txt)" >&2; exit 1; }

echo "## Paso 1: la plataforma"
paso "kubectl apply -k infra/metallb"
paso "kubectl apply --server-side -k infra/envoy-gateway"

echo
echo "## Paso 2: la espera"
paso "kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
paso "kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s"
paso "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"

echo
echo "## Paso 3: la configuración de la plataforma, y el proyecto"
paso "kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml"
paso "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
paso "kubectl apply -k ."
paso "kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s"
```

La fonction `paso` fait trois choses : elle vérifie le contexte avec `ctx` (et s'arrête si ce n'est pas `kind-curso-k8s-l6` : MetalLB et Envoy Gateway créent des objets qui valent pour tout le cluster), elle affiche la commande avec `$` et l'exécute. Avec `set -euo pipefail`, la première erreur arrête le script, donc une exécution sans interruption est la preuve que l'ordre fonctionne.

La plage et la classe vont à l'**étape 3** et non à la 1, pour la raison que tu as vue : la plage a besoin que le *webhook* de MetalLB réponde (6.4.2) et la classe a besoin que son CRD soit établi (6.6.3). Le README du cours parle de « trois étapes » même si le bloc compte plus de trois commandes : les étapes sont une question d'**ordre**, pas de nombre de commandes. (Dans la Leçon 10, les deux `apply` de plateforme de l'étape 1 sont réunis en un seul.) Voici la sortie de cette exécution :

```text
$ kubectl get crd
No resources found

$ ./levantar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb
namespace/metallb-system created
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io created
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io created
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io created
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io created
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io created
serviceaccount/controller created
serviceaccount/speaker created
role.rbac.authorization.k8s.io/controller created
role.rbac.authorization.k8s.io/pod-lister created
clusterrole.rbac.authorization.k8s.io/metallb-system:controller created
clusterrole.rbac.authorization.k8s.io/metallb-system:speaker created
rolebinding.rbac.authorization.k8s.io/controller created
rolebinding.rbac.authorization.k8s.io/pod-lister created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:controller created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:speaker created
configmap/metallb-excludel2 created
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway
namespace/envoy-gateway-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/clienttrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyextensionpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoypatchpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyproxies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutefilters.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/listenersets.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/securitypolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tcproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/udproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io serverside-applied
serviceaccount/eg-gateway-helm-certgen serverside-applied
serviceaccount/envoy-gateway serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-role serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-role serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-rolebinding serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-rolebinding serverside-applied
configmap/envoy-gateway-config serverside-applied
service/envoy-gateway serverside-applied
deployment.apps/envoy-gateway serverside-applied
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
(levantar.sh tardó 266 s)
```

Lis-la étape par étape. Étape 1 : un `created` pour chaque objet de MetalLB et un `serverside-applied` pour chaque objet d'Envoy Gateway ; le second envoie d'un coup les dix plus trois CRD de Gateway API et les huit d'Envoy. Étape 2 : cinq attentes, et toutes se terminent par `condition met` ou `successfully rolled out` ; le `speaker` passe de 0 à 3 pods disponibles. Étape 3 : la plage et la classe sont créées ensemble, on attend que la classe soit `Accepted`, le projet est créé en entier (neuf `created`, sans un seul `no matches for kind`) et le Gateway atteint `Programmed`. Aucune erreur, et aucun `sleep`. Ensuite, `correr.sh` vérifie ce qui compte :

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         82s

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.165.26   172.18.255.200   80:31214/TCP   82s
(espera: la puerta ya contesta 200 en http://172.18.255.201/salud)

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}


$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

Le Gateway et le `LoadBalancer` ont de nouveau reçu `172.18.255.201` et `.200`, dans cet ordre, le point d'entrée répond à `/salud` et renvoie le tableau du rapport, et la `.200` aussi. (Le Service de ce nouveau cluster a un autre `NodePort`, `31214`, et le Gateway a mis `82s` à exister, parce que le `kubectl apply` et les attentes de l'étape 3 s'exécutent avant ce `get`.) Avec cela, l'objectif de la leçon est atteint : un nouveau cluster, trois étapes, rien de corrigé manuellement.

Trois idées que tu reconnaîtras dans la Leçon 10, quand tout le projet sera déployé avec deux `apply -k` et une attente :

- **La plateforme s'installe une fois par cluster ; le projet, chaque fois qu'il change.** MetalLB et Envoy Gateway n'appartiennent pas au `revisor` : le jour où tu publieras un second service, il utilisera la même classe `eg` et la même plage.
- **L'attente n'est pas un `sleep`.** Un `sleep 30` fonctionne sur ta machine et échoue sur une machine plus lente. `kubectl wait` interroge la condition et échoue clairement si elle n'arrive pas dans le délai que tu lui as donné.
- **L'ordre ne se cache pas.** Si tu l'automatises (un script, une étape d'un *pipeline*), les trois étapes restent là, avec leur nom, chacune avec sa vérification de contexte (`ctx`). Un script qui « réessaie jusqu'à ce que ça passe » cache la cause ; un script qui attend la condition la nomme.

## L'erreur que tu vas voir

L'erreur de cette leçon est la plus courante avec Gateway API, et elle ressemble au sélecteur mal écrit de la Leçon 3 : une route qui pointe vers un Service qui n'existe pas. On la provoque avec `fig06_01.ruta-mala.yaml`, un **programme** qui échoue exprès : la même `HTTPRoute`, avec une lettre en moins dans la destination.

```yaml
# fig06_01.ruta-mala.yaml — FALLA A PROPÓSITO: la misma ruta del revisor con una
# letra de menos en el Service de destino (revisr). El Gateway la acepta, pero no
# encuentra a quién mandarle el tráfico: ResolvedRefs=False BackendNotFound, y la
# puerta responde 500. Se corrige volviendo a aplicar la kustomization (apply -k .).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisr
      port: 80
```

```text
$ kubectl apply -f fig06_01.ruta-mala.yaml
httproute.gateway.networking.k8s.io/revisor configured
```

`configured`, sans protester. Comme avec le sélecteur de la Leçon 3, le `kube-apiserver` ne peut pas savoir que tu voulais écrire `revisor` : `revisr` est un nom valide. On lit dans l'ordre.

**Premièrement, le symptôme**, depuis l'extérieur :

```text
$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|content-length)"
HTTP/1.1 500 Internal Server Error
content-length: 0
```

`500` et un corps vide. Remarque ce que ce n'est **pas**. Ce n'est pas un code de `curl` (6, 7 ou 28) : la connexion s'est établie, quelqu'un a répondu. Et ce n'est pas le `revisor` : le `revisor` ne répond jamais avec un corps vide. Celui qui a répondu, c'est Envoy, le point d'entrée, pour dire « je n'ai personne à qui t'envoyer ». La [spécification de Gateway API v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/) l'exige ainsi : si toutes les références d'une règle sont invalides et que la règle n'a pas de filtres, « tout le trafic qui correspond à cette règle DOIT recevoir un code 500 ».

**Deuxièmement, le point d'entrée.** S'il a répondu, le point d'entrée va bien :

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         2m1s
```

`PROGRAMMED True`, même adresse. Le problème est derrière.

**Troisièmement, les conditions de la route.** C'est l'étape décisive, l'équivalent de la colonne `ENDPOINTS` de la Leçon 3 :

```text
$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=False BackendNotFound

$ kubectl get httproute revisor -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].message}{"\n"}'
Failed to process route rule 0 backendRef 0: service default/revisr not found.
```

Deux conditions, et voici le piège : `Accepted=True`. Le point d'entrée a accepté la route. Qui ne regarde que cette condition, ou que `kubectl get httproute` (qui n'en affiche aucune), conclut que tout va bien. Celle qui dit la vérité, c'est la seconde : `ResolvedRefs=False`, motif `BackendNotFound`. Et le message, en anglais, ne laisse aucun doute : « échec du traitement de la règle 0, référence 0 : le Service `default/revisr` est introuvable ». (`.status.parents[0]` est l'état de la route par rapport à son premier point d'entrée ; une route peut se rattacher à plusieurs, et chacun lui attribue ses conditions.)

**Quatrièmement, la confirmation :**

```text
$ kubectl get service revisr
Error from server (NotFound): services "revisr" not found
[código de salida: 1]
```

**La correction** s'attaque à la cause, pas au point d'entrée : réappliquer le bon fichier, qui ici est la kustomization complète.

```text
$ kubectl apply -k . | grep httproute
httproute.gateway.networking.k8s.io/revisor configured

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}
```

Comme dans la Leçon 3, on vérifie d'abord que l'état est correct (`ResolvedRefs=True`), puis on teste. Entre le moment où tu appliques la route et celui où Envoy reçoit sa nouvelle configuration, il s'écoule un instant : si ton premier `curl` donne encore l'ancien code (`200` après la mauvaise route, `500` après la bonne), répète-le. `correr.sh` attend que le point d'entrée renvoie le code attendu avant d'afficher le `curl`, et le note dans la sortie sous la forme `(espera: la puerta ya contesta 500 …)`.

**L'ordre, pour tout point d'entrée qui ne répond pas correctement :**

1. Que renvoie `curl` ? Un code de `curl` (7, 28) désigne le réseau ou l'IP ; un code HTTP (`404`, `500`) signifie que le point d'entrée a répondu.
2. Le Gateway a-t-il une `ADDRESS` et `PROGRAMMED True` ? S'il n'a pas d'adresse, regarde MetalLB et sa plage.
3. La route a-t-elle `Accepted=True` **et** `ResolvedRefs=True` ? Lis les deux, ainsi que le `message` de celle qui est à `False`.
4. Si tout cela est correct, descends d'un étage : le Service de destination et son EndpointSlice, avec l'ordre de la Leçon 3.

## L'habitude de sécurité de la leçon : on expose le minimum, par un point d'entrée nommé, et l'on dit ce qui manque

Le tableau des habitudes du cours attribue trois choses à cette leçon. On les vérifie avec le cluster sous les yeux.

**Ce qui est resté exposé.** Tout ce qui reçoit du trafic de l'extérieur du cluster :

```text
$ kubectl get services -A -o custom-columns='ESPACIO:.metadata.namespace,NOMBRE:.metadata.name,TIPO:.spec.type,IP-EXTERNA:.status.loadBalancer.ingress[0].ip,NODEPORT:.spec.ports[*].nodePort' | grep -E 'ESPACIO|LoadBalancer|NodePort'
ESPACIO                NOMBRE                           TIPO           IP-EXTERNA       NODEPORT
default                revisor-publico                  LoadBalancer   172.18.255.200   30808
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   172.18.255.201   30581
```

Écrit sous forme d'inventaire, c'est-à-dire comme on doit pouvoir le dire à voix haute :

| Point d'entrée | Adresse | Ce qu'il laisse passer | Qui décide |
|---|---|---|---|
| `revisor-publico` | `172.18.255.200:80` | **tout** le `revisor`, sans règles | personne : c'est un `LoadBalancer` direct |
| son `NodePort` | `30808` sur **chaque** nœud | la même chose | personne |
| le Gateway `revisor` | `172.18.255.201:80` | ce que dit la `HTTPRoute` | la route, un fichier versionné |
| son `NodePort` | `30581` sur chaque nœud | la même chose que le Gateway | la route |

Aujourd'hui, il y a **deux** points d'entrée vers le même service, et c'est une leçon en soi : le direct contourne toute règle que tu mets sur le nommé. L'Exercice 2 le mesure : quand la route du Gateway ne laisse passer que `/salud`, la `.200` continue de livrer le rapport complet. C'est pourquoi « un point d'entrée nommé » est l'habitude, et c'est pourquoi la Leçon 7 retire `revisor-publico` et laisse le Gateway comme unique entrée. Les `NodePort` restent là pour la raison vue en 6.3.3 ; dans un vrai cluster, la norme est que le réseau des nœuds ne soit pas joignable depuis l'extérieur, et qu'un pare-feu le garantisse.

**Ce qui n'a pas été exposé.** Les nœuds kind ne publient toujours rien vers ta machine, sauf le port de l'API :

```text
$ docker port curso-k8s-l6-control-plane
6443/tcp -> 127.0.0.1:59736

$ docker port curso-k8s-l6-worker
```

Et depuis ton terminal, sur le Mac des exécutions, l'IP du Gateway n'existe pas :

```text
$ curl -s -m 3 http://172.18.255.201/salud
[código de salida: 28]
```

Ce `curl`-ci s'est bien exécuté dans le terminal du Mac, pas dans le conteneur. Code 28 : le délai a expiré. Le réseau `kind` vit à l'intérieur de la machine virtuelle de Colima, et le Mac n'a pas de route vers lui. Sur ton Linux Mint, c'est différent : Docker connecte ta machine au réseau `kind`, donc là, la `.201` devrait répondre depuis ton terminal. Un autre ordinateur de ton réseau ne l'atteint pas : avec les règles que Docker pose par défaut (depuis Docker Engine 28, qui bloque l'accès par routage direct aux réseaux des conteneurs), le réseau `kind` n'est visible que depuis ta propre machine. Mais « ta machine » inclut tous ses utilisateurs : sur une machine partagée, quiconque y a ouvert une session peut demander le rapport à `.200` ou à `.201`, ou aux `NodePort` des trois nœuds, et qui a `root` peut lire le token qui circule sans chiffrement (par exemple, en observant le pont de Docker avec `tcpdump`). Voilà ce que ce laboratoire publie : peu de chose, et seulement vers l'intérieur de la machine, mais ce n'est pas « personne ».

**Ce qui manque : le chiffrement.**

```text
$ curl -s -m 5 https://172.18.255.201/salud
[código de salida: 7]

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados -H 'Authorization: Bearer token-inventado'
401
```

En `https`, code 7 : personne n'écoute sur le 443, parce que le Gateway n'a qu'un *listener* `HTTP` sur le 80. Et la seconde commande rappelle ce qui circule par ce point d'entrée : le token du `revisor`, dans un en-tête, **en clair**. Quiconque peut observer le réseau entre le client et le point d'entrée le lit. Le `revisor` rejette le token inventé (`401`), mais il ne peut rien contre quelqu'un qui a copié le bon. La pièce qui manque est un second *listener* sur le Gateway, avec `protocol: HTTPS`, le port 443 et un `tls.certificateRefs` qui pointe vers un `Secret` contenant le certificat. La `HTTPRoute` ne change pas. (`TLSRoute` et `BackendTLSPolicy`, de la liste de 6.6.3, sont d'autres choses : laisser passer le chiffrement sans l'ouvrir et chiffrer le tronçon qui va du point d'entrée au Service.) Ce cours ne le met pas en place parce qu'un vrai certificat a besoin d'un vrai nom de domaine, et qu'un laboratoire dans kind n'en a pas. Mais il le dit, et c'est cela, l'habitude : **un point d'entrée sans chiffrement se publie en sachant qu'il n'en a pas**, et dans un vrai cluster on ne publie pas ainsi. La Leçon 10 l'inscrit sur la liste de ce qui manque à tout ceci pour être de la production.

## Ce qui se fait de travers

**Passer un Service en `NodePort` « pour qu'on puisse le voir ».** Cela ouvre un port pris au hasard sur tous les nœuds, sans nom et sans règles. C'est la première proposition de la scène.

**Oublier que tout `LoadBalancer` est aussi un `NodePort`.** Même si l'IP externe n'arrive jamais, le port de nœud est déjà ouvert (6.3.3).

**Installer `ingress-nginx` parce qu'un tutoriel le dit.** Plus de correctifs de sécurité depuis mars 2026. Et `Ingress`, l'API, est gelée : ce qui est nouveau s'écrit avec Gateway API.

**Exécuter Cloud Provider KIND sur une machine partagée.** Il surveille tous les clusters kind de la machine, pas seulement le tien.

**Appliquer le projet avant la plateforme, et « réparer » en répétant la commande jusqu'à ce que ça passe.** Cela fonctionne parfois et cache la cause. On installe la plateforme, on attend la condition avec `kubectl wait`, puis on applique le projet.

**Attendre avec `sleep`.** Un nombre de secondes qui suffit sur ta machine ne suffit pas sur une autre. On attend la condition, avec `--timeout`.

**Installer Envoy Gateway sans `--server-side`.** Trois de ses CRD ne tiennent pas dans l'annotation de l'`apply` habituel.

**Ne regarder que `Accepted` sur une route.** `Accepted=True` avec `ResolvedRefs=False`, c'est une route acceptée qui ne mène nulle part. On lit les deux conditions.

**Choisir la plage de MetalLB au hasard.** Elle doit se trouver dans le réseau `kind`, loin des IP des nœuds, et ne pas se répéter dans deux clusters en vie en même temps.

**Laisser deux points d'entrée vers le même service.** Celui qui n'a pas de règles contourne les règles de l'autre (Exercice 2).

**Publier en HTTP en clair sans le dire.** Le token circule de façon lisible. Si un laboratoire ne peut pas mettre de chiffrement, il l'inscrit au moins dans sa liste de choses à faire.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre et à partir de l'état dans lequel il est resté après la correction de l'erreur. Avant chaque exercice, `kubectl config current-context` doit afficher `kind-curso-k8s-l6`. `correr.sh` les exécute de la même façon, et sa sortie se trouve dans `correr.salida.txt`. **Avant** d'exécuter chacun d'eux, écris dans le [journal de bord](bitacora.md) ce qui, selon toi, va se passer. Le quatrième s'écrit avec tes propres mots.

### Exercice 1 — Libérer une adresse et la redemander

Supprime le Service `revisor-publico` avec `kubectl delete service revisor-publico`. Prédis : que répond `curl -s -m 3 http://172.18.255.200/salud` depuis le client de l'extérieur ? Quels `LoadBalancer` restent dans le cluster ? Réapplique maintenant la kustomization avec `kubectl apply -k .` : quelle IP reçoit le nouveau Service, la `.200` qui a été libérée ou la `.202`, la suivante, qui n'a jamais servi ? Et son `NodePort`, est-ce le même qu'avant ? Vérifie-le et explique.

### Exercice 2 — Le point d'entrée, réduit au minimum

`fig06_02.solo-salud.yaml` est la même `HTTPRoute` avec une règle plus étroite : uniquement `GET` sur `/salud`, exactement.

```yaml
# fig06_02.solo-salud.yaml — Ejercicio 2: la ruta del revisor, reducida a lo
# mínimo. Solo deja pasar GET /salud, exacto. Pregunta: ¿qué responde la puerta a
# /api/estados, con token y sin token? Se deshace con apply -k . (gateway.yaml).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: Exact
        value: /salud
      method: GET
    backendRefs:
    - name: revisor
      port: 80
```

Applique-le et prédis le code HTTP de chacune de ces cinq requêtes, toutes depuis le client de l'extérieur : `GET /salud` par le Gateway ; `GET /api/estados?formato=tabla` **avec** le token, par le Gateway ; `GET /salud/` (avec une barre oblique à la fin) par le Gateway ; `POST /salud` par le Gateway ; et `GET /api/estados?formato=tabla` avec le token, par `172.18.255.200`. Vérifie-le avec `curl -s -o /dev/null -w '%{http_code}\n'`. Qui renvoie chaque `404` : Envoy ou le `revisor` ? Que dit la dernière réponse sur le fait d'avoir deux points d'entrée ? À la fin, réapplique `kubectl apply -k .`.

### Exercice 3 — Un `Ingress` que personne ne prend en charge

`fig06_03.ingress.yaml` est un `Ingress` qui envoie tout au Service `revisor`, comme la route de 6.7 :

```yaml
# fig06_03.ingress.yaml — Ejercicio 3: un Ingress, la API congelada. El clúster
# lo acepta (la API existe desde siempre), pero en este clúster no hay ningún
# controlador de Ingress. Pregunta: ¿qué dirección recibe? ¿Quién la atiende?
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: revisor
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: revisor
            port:
              name: http
```

Avant de l'appliquer, exécute `kubectl get ingressclass`. Prédis : le cluster accepte-t-il l'`Ingress` ou le rejette-t-il comme il a rejeté le `Gateway` en 6.2 ? S'il l'accepte, quelle adresse aura-t-il au bout de 15 secondes ? Applique-le, vérifie avec `kubectl get ingress revisor` et avec `kubectl describe ingress revisor`, et explique la différence avec 6.2 en deux phrases. Supprime-le à la fin.

### Exercice 4 — Défends la décision

Un collègue te dit : « le guide de kind recommande Cloud Provider KIND, c'est un seul binaire et il te donne LoadBalancer, Ingress et Gateway API sans rien installer dans le cluster. Pourquoi s'embêter avec MetalLB et Envoy Gateway ? ». En cinq phrases au maximum, réponds-lui : où tourne Cloud Provider KIND, sur quels clusters il agit, ce qui se passerait sur une machine partagée, quel prix paie la solution du cours et comment on maîtrise ce prix.

## Solutions

### Solution 1

Mesuré dans `correr.salida.txt` :

```text
$ kubectl delete service revisor-publico
service "revisor-publico" deleted from default namespace

$ curl -s -m 3 http://172.18.255.200/salud
[código de salida: 28]

$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       2m18s

$ kubectl apply -k . | grep revisor-publico
service/revisor-publico created

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.129.166   172.18.255.200   80:31622/TCP   5s

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

**Sans le Service, `curl` ne se connecte pas** : il se termine avec 28 (le délai a expiré) ou, selon ton système, avec 7 (connexion impossible ; sous Linux, « No route to host » quand la requête ARP reste sans réponse). Les deux disent la même chose : personne ne répond pour `172.18.255.200`. Il n'y a personne pour refuser avec une réponse HTTP, parce qu'aucun `speaker` n'annonce plus cette IP, que la requête ARP reste sans réponse et que le paquet n'a nulle part où aller. Quand le Service a été supprimé, MetalLB a **libéré** l'adresse. Il ne reste qu'un seul `LoadBalancer`, celui du Gateway, qui ne s'est aperçu de rien : il est toujours sur `.201`.

**Le nouveau Service reçoit de nouveau la `.200`**, pas la `.202`. MetalLB distribue la première adresse libre de sa plage, et la `.200` était redevenue libre. Mais c'est un nouvel objet : une autre `CLUSTER-IP` (`10.96.129.166` au lieu de `10.96.115.79`) et **un autre `NodePort`** (`31622` au lieu de `30808`). L'IP externe est restée la même parce que c'est ainsi que fonctionne la distribution de MetalLB, pas parce que Kubernetes s'en souvient. Si, entre la suppression et la création, un autre Service avait demandé une IP, il aurait obtenu la `.200`, et ton Service une autre. C'est pourquoi, si une IP externe doit être fixe (parce qu'elle figure dans un DNS ou dans la configuration d'un pare-feu), on la demande par écrit dans le Service, avec l'annotation `metallb.io/loadBalancerIPs: 172.18.255.200` (le [guide d'utilisation de MetalLB](https://metallb.io/usage/) la préfère à `spec.loadBalancerIP`, qui est en voie de retrait), et on ne se fie pas au hasard de l'ordre.

### Solution 2

Mesuré dans `correr.salida.txt` :

```text
$ kubectl apply -f fig06_02.solo-salud.yaml
httproute.gateway.networking.k8s.io/revisor configured

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud
200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud/
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -X POST http://172.18.255.201/salud
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
200
```

**`200`, `404`, `404`, `404` et `200`.** Par le Gateway, seul passe exactement `GET /salud`. `/api/estados` ne correspond à aucune règle, même avec le token : le token n'arrive même pas jusqu'au `revisor`, parce qu'**Envoy** renvoie `404` avant. `/salud/` non plus, parce que `Exact` est exact : une barre oblique de trop, c'est un autre chemin. Et `POST /salud` ne correspond pas, à cause de la méthode. Les trois `404` viennent du point d'entrée : aucune règle n'amène ces requêtes au `revisor`, donc Envoy répond de lui-même.

**La cinquième est celle qui compte :** par `172.18.255.200`, le `LoadBalancer` direct, le rapport sort complet, `200`. La règle que tu viens de mettre sur le point d'entrée nommé ne protège rien tant qu'il existe un autre point d'entrée sans règles. C'est l'argument de la Leçon 7 pour retirer `revisor-publico` : réduire ce qui est exposé ne sert que s'il n'y a qu'**une** seule entrée.

Quand tu réappliques la kustomization, la route revient à `PathPrefix /` et `/api/estados` sans token renvoie de nouveau `401`, cette fois de la part du `revisor`.

### Solution 3

Mesuré dans `correr.salida.txt` :

```text
$ kubectl get ingressclass
No resources found

$ kubectl apply -f fig06_03.ingress.yaml
ingress.networking.k8s.io/revisor created

$ kubectl get ingress revisor
NAME      CLASS    HOSTS   ADDRESS   PORTS   AGE
revisor   <none>   *                 80      16s

$ kubectl describe ingress revisor | grep -E '^(Ingress Class|Address|Events):'
Address:          
Ingress Class:    <none>
Events:       <none>

$ kubectl delete -f fig06_03.ingress.yaml
ingress.networking.k8s.io "revisor" deleted from default namespace
```

**Le cluster l'accepte, et personne ne le prend en charge.** Contrairement à `Gateway` en 6.2, le type `Ingress` est intégré à Kubernetes, dans le groupe `networking.k8s.io` : aucun CRD n'est nécessaire pour le créer. Mais un `Ingress` est une déclaration, tout comme un `Gateway`, et sans contrôleur pour la lire, il ne se passe rien : il n'y a pas d'`IngressClass` (`No resources found`), la colonne `CLASS` indique `<none>`, `ADDRESS` est vide et il n'y a pas le moindre événement. C'est le `<pending>` de 6.3 sous un autre visage : aucune erreur, aucun résultat. Envoy Gateway, le contrôleur qui, lui, est installé, prend en charge Gateway API et non cet `Ingress`. Les deux phrases : « `Gateway` n'existait pas comme type et le cluster l'a rejeté ; `Ingress` existe comme type et le cluster l'a enregistré, mais personne ne le transforme en point d'entrée. Un objet accepté n'est pas un objet pris en charge ».

### Solution 4

Une réponse possible : « Cloud Provider KIND tourne comme un programme sur ta machine, en dehors des clusters, avec des permissions pour ouvrir des ports et parler à Docker. Son propre README dit qu'il surveille tous tes clusters kind, et ne décrit aucune option pour se limiter à un seul ; de plus, son contrôleur Gateway API est activé. Sur une machine partagée, le programme que j'ai lancé pour ma leçon toucherait aux clusters d'autres personnes sans qu'elles l'aient demandé. MetalLB et Envoy Gateway vivent à l'intérieur de mon cluster et sont supprimés avec lui ; le prix à payer, c'est que la plage d'IP de MetalLB provient du réseau kind, qui, lui, est partagé. Ce prix se maîtrise en vérifiant, avant de créer le cluster, que personne ne répond déjà sur la première IP de la plage, et en ne faisant tourner qu'un seul cluster avec MetalLB à la fois. »

## Supprimer le cluster

Quand tu as terminé les exercices, supprime le cluster de la leçon. Avec lui disparaissent MetalLB, Envoy Gateway, leurs CRD et leurs IP :

```text
$ kind delete cluster --name curso-k8s-l6
Deleting cluster "curso-k8s-l6" ...
Deleted nodes: ["curso-k8s-l6-control-plane" "curso-k8s-l6-worker" "curso-k8s-l6-worker2"]

$ kind get clusters | grep -c curso-k8s-l6
0
```

Ensuite, supprime `token.txt` et le dossier temporaire du `kubeconfig`, qui contient l'identifiant d'administrateur du cluster que tu viens de supprimer. Le `rm -rf` est dangereux si la variable est vide ou pointe ailleurs, il est donc protégé par un `case` qui ne le laisse s'exécuter que si le chemin est celui qu'a créé `mktemp` en 6.1.2 :

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 6.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l6.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt
```

Fermer le terminal met fin à l'utilisation de ce `kubeconfig`, mais ne le supprime pas : sans le `case`, l'identifiant resterait dans `/tmp`. Vérifie aussi qu'il ne reste aucun conteneur client : `docker ps -a --filter name=curso-k8s-l6` ne doit rien afficher. À partir de maintenant, `172.18.255.200` est de nouveau libre pour le prochain cluster qui en aura besoin.

## Comment savoir que j'ai réussi

- [ ] Tu expliques pourquoi `revisor-publico` est resté en `<pending>` et tu démontres avec `curl`, sur l'IP d'un nœud, que son `NodePort` était déjà ouvert.
- [ ] Tu installes MetalLB, tu lui donnes la plage `172.18.255.200-172.18.255.220` et tu lis dans les événements du Service qui a attribué l'IP (`IPAllocated`) et depuis quel nœud elle est annoncée (`nodeAssigned`).
- [ ] Face à `no matches for kind … ensure CRDs are installed first`, tu dis ce qui manque (un CRD) et face à `failed calling webhook … connection refused`, tu dis ce qu'il faut attendre (le contrôleur qui répond au *webhook*).
- [ ] Tu écris de mémoire les trois étapes : plateforme, `kubectl wait`, projet ; et tu expliques pourquoi un `sleep` n'est pas une attente.
- [ ] Tu expliques ce que sont `GatewayClass`, `Gateway` et `HTTPRoute`, à quel rôle correspond chacune et qui crée le Pod `envoy-default-revisor-…`.
- [ ] Face à un `500` du point d'entrée, tu vérifies le Gateway, les deux conditions de la route et le `message`, et tu trouves un `BackendNotFound`.
- [ ] Tu fais l'inventaire de ce qui est exposé (les deux IP, les deux `NodePort`, le 6443 sur `127.0.0.1`) et tu dis ce qui manque : le chiffrement.
- [ ] Tu expliques en une phrase chacun de ces points : pourquoi on n'utilise pas Cloud Provider KIND, ce que signifie le fait que l'API `Ingress` soit gelée et pourquoi on n'utilise pas `ingress-nginx`.
- [ ] Tu exécutes `programas/06-entrar-al-cluster/correr.sh > /tmp/mi-corrida-l6.txt 2>&1` et tu compares avec `correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) ce qui ne change pas d'une exécution à l'autre : trois nœuds `Ready` en `v1.37.0` ; le réseau `172.18.0.0/16` ; `No resources found` pour les CRD ; sept `created` et les deux `no matches for kind` de `Gateway` et `HTTPRoute` ; `revisor-publico` en `<pending>` et `/salud` par le `NodePort` de deux nœuds ; le `failed calling webhook … connection refused` de la première tentative avec la plage (il peut ne pas apparaître chez toi si ta machine est plus rapide que le démarrage de MetalLB, et cela aussi enseigne quelque chose) ; neuf CRD de `metallb.io` ; `ipaddresspool.metallb.io/curso created` à la deuxième tentative ; un `controller` et trois `speaker` ; **`172.18.255.200`** sur `revisor-publico`, avec `IPAllocated` et `nodeAssigned … layer2` ; `3` lignes `Too long` et le plafond de `262144 bytes` ; `10` CRD de Gateway API et `8` d'Envoy Gateway ; la `GatewayClass` `eg` avec `ACCEPTED True` et dix types dans `api-resources` ; sept `unchanged` et deux `created` ; le Gateway sur **`172.18.255.201`** avec `PROGRAMMED True` ; `Accepted=True` et `ResolvedRefs=True` ; un Pod `envoy-default-revisor-…` en `2/2` ; `/salud` et le tableau par le point d'entrée, et `401` sans token ; avec la mauvaise route, `ResolvedRefs=False BackendNotFound`, `service default/revisr not found` et `HTTP/1.1 500` ; le code 7 en `https` ; dans l'Exercice 1, un code de `curl` (28 ou 7) et le retour de la `.200` ; dans l'Exercice 2, `200 404 404 404 200` ; dans l'Exercice 3, une `Address` vide ; et à la fin `sin diferencias con los archivos` (« aucune différence avec les fichiers »). Les IP des Pods, des Services et des nœuds, les `NodePort`, les suffixes, les âges, le nœud qui annonce l'IP, l'ordre des lignes de `kind load` et le nombre de répétitions de chaque ligne de `rollout status` changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] À partir d'un cluster fraîchement créé, sans la moindre ressource personnalisée, tu exécutes `./levantar.sh` et il va jusqu'à `Programmed` sans la moindre erreur et sans que tu corriges quoi que ce soit manuellement ; et tu dis pourquoi la plage et la classe vont à l'étape 3.
- [ ] Tu lis la sortie de `kubectl get crd` de 6.6.2 et tu dis trois choses : que les CRD de Gateway API sont du canal `experimental`, qu'il y en a trois de plus de `x-k8s.io`, et que le *webhook* d'Envoy est `Ignore` et ceux de MetalLB `Fail`.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l6`, le dossier temporaire du `kubeconfig` n'existe plus dans `/tmp`, et personne ne répond sur `172.18.255.200`.

## Résumé

Réponds sans regarder la leçon :

1. Pourquoi un `LoadBalancer` reste-t-il en `<pending>` dans kind ? Qu'ouvre-t-il malgré tout, même en restant ainsi ?
2. Que font le `controller` et le `speaker` de MetalLB, et que veut dire « couche 2 » ?
3. Pourquoi la plage de MetalLB provient-elle du réseau `kind`, et pourquoi de sa fin ?
4. Qu'est-ce qu'un CRD, et quelle erreur obtient-on en appliquant un objet dont le CRD n'existe pas ?
5. Qu'est-ce qu'un *webhook* d'admission, et que fait le `kube-apiserver` quand il ne peut pas l'appeler, selon sa `failurePolicy` ? Quelle valeur ont ceux de MetalLB et quelle valeur a celui de mutation d'Envoy Gateway ?
6. Quelles sont les trois étapes pour déployer la plateforme et le projet, et qu'attend exactement chaque `kubectl wait` de cette leçon ?
7. Pourquoi Envoy Gateway s'installe-t-il avec `--server-side` ?
8. Quel rôle a chacune des trois pièces de Gateway API, et qui crée le Pod qui reçoit réellement les requêtes ?
9. Quelle différence y a-t-il entre `Ingress`, `ingress-nginx` et Gateway API, et dans quel état se trouve chacun ?
10. Qu'est-ce qui reste exposé à la fin de cette leçon, et que manque-t-il au point d'entrée ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Service »](https://kubernetes.io/docs/concepts/services-networking/service/) : le type `LoadBalancer`, provisionné de façon asynchrone par le fournisseur de cloud et publié dans `.status.loadBalancer` ; sa mise en œuvre au-dessus d'un `NodePort` ; `allocateLoadBalancerNodePorts` et sa valeur par défaut `true`.
- [Kubernetes, « Gateway API »](https://kubernetes.io/docs/concepts/services-networking/gateway/) : Gateway API comme module complémentaire défini avec des ressources personnalisées ; `GatewayClass`, `Gateway` et `HTTPRoute` ; la conception orientée rôles.
- [Kubernetes, « Ingress »](https://kubernetes.io/docs/concepts/services-networking/ingress/) : l'API Ingress gelée, sans projet de la retirer ; la recommandation d'utiliser Gateway.
- [Kubernetes, blog, « Ingress NGINX Retirement: What You Need to Know »](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) (11 novembre 2025) : la fin de la maintenance en mars 2026, sans versions, corrections ni correctifs de sécurité par la suite ; les installations existantes continuent de fonctionner ; la recommandation de migrer vers Gateway API.
- [Kubernetes, « Custom Resources »](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) : ce qu'est une ressource personnalisée et ce que crée un `CustomResourceDefinition`.
- [Kubernetes, « Dynamic Admission Control »](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) : ce que sont les *webhooks* d'admission, de validation et de mutation ; `failurePolicy` avec `Fail` par défaut.
- [Kubernetes, « Deployments »](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) : la condition `Available` comme disponibilité minimale selon la stratégie de mise à jour.
- [Gateway API, « ReferenceGrant »](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/) : la permission pour les références entre espaces de noms ; le rattachement route-Gateway entre espaces se décide dans les *listeners* (`allowedRoutes`).
- [MetalLB, « Usage »](https://metallb.io/usage/) : l'annotation `metallb.io/loadBalancerIPs` pour demander une IP précise.
- [Docker, « Docker Engine 28: hardening container networking by default »](https://www.docker.com/blog/docker-engine-28-hardening-container-networking-by-default/) et [« Port publishing and mapping »](https://docs.docker.com/engine/network/port-publishing/) : pourquoi une autre machine de ton réseau n'atteint pas le réseau des conteneurs.
- [Kubernetes, « kubectl wait »](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) : attendre une condition dans le `Status` d'une ou de plusieurs ressources ; l'option `--for`.
- [Kubernetes, « Server-Side Apply »](https://kubernetes.io/docs/reference/using-api/server-side-apply/) : le plan de contrôle note quels champs gère chacun ; la comparaison avec l'annotation `last-applied-configuration`.
- [kind, « LoadBalancer »](https://kind.sigs.k8s.io/docs/user/loadbalancer/) : Cloud Provider KIND comme binaire indépendant sur ta machine, avec des privilèges pour ouvrir des ports et parler au *runtime* de conteneurs.
- [kind, « Ingress »](https://kind.sigs.k8s.io/docs/user/ingress/) : la prise en charge native d'Ingress et de Gateway API dans Cloud Provider KIND.
- [Cloud Provider KIND, README](https://github.com/kubernetes-sigs/cloud-provider-kind) : il surveille tous les clusters kind ; son contrôleur Gateway API est activé par défaut.
- [MetalLB, « Installation »](https://metallb.io/installation/) : le manifeste `metallb-native.yaml` de la v0.16.1 ; le `controller` et le `speaker` ; les composants inactifs tant qu'ils ne sont pas configurés.
- [MetalLB, « Configuration »](https://metallb.io/configuration/) : `IPAddressPool`, `L2Advertisement` et leur association ; la couche 2 qui répond aux requêtes ARP.
- [Envoy Gateway, « Install with Kubernetes YAML »](https://gateway.envoyproxy.io/docs/install/install-yaml/) : `kubectl apply --server-side` avec l'`install.yaml` de la v1.9.2 ; le manifeste inclut les CRD de Gateway API et ceux d'Envoy Gateway.
- [Gateway API, « HTTPRoute »](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) : sans `matches`, le préfixe `/` correspond à toute requête ; chaque `match` est indépendant.
- [Gateway API, spécification v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/) : les références invalides d'une règle et le code 500 obligatoire.
- [curl, « libcurl error codes »](https://curl.se/libcurl/c/libcurl-errors.html) : les codes 7 et 28.

---

**Suivante :** [Leçon 7 — Isoler : espaces, permissions et réseau](07-aislar-permisos-red.md)
