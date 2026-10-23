# Leçon 4 — Configuration et secrets

Mercredi, 18 h 40. Demain à 8 h commence la revue de sécurité du projet et c'est à toi de préparer le dépôt. Tu ouvres l'historique et tu le vois : il y a trois semaines, quelqu'un a ajouté le token du `revisor` au manifeste du Deployment, sur une ligne `REVISOR_TOKEN`, « juste pour tester ». Il n'est plus dans la version d'aujourd'hui, mais il est toujours dans l'historique de Git, où n'importe qui ayant cloné le dépôt peut le lire. Pendant que tu y réfléchis, un autre message arrive : l'équipe des paiements veut que le `revisor` surveille aussi son service, et pour l'ajouter à la liste il faut éditer le même Deployment : il n'est pas nécessaire de reconstruire l'image, mais il faut retoucher le fichier où le token a vécu. Quelqu'un propose de régler le premier problème avec un Secret « qui est déjà en base64, donc protégé ». Il est 18 h 55 et tu as deux problèmes qui ressemblent à un seul.

Ce n'en est pas un seul. Le premier est **l'endroit où vit une valeur qui ne doit pas être vue** ; le second est **comment tu changes la configuration d'un service sans toucher à sa recette**. Kubernetes a un objet pour chacun, et cette leçon t'apprend à les utiliser sans leur accorder plus de crédit qu'ils n'en promettent : un `ConfigMap` n'est pas secret, un `Secret` n'est pas chiffré, et aucun des deux ne fait que ton programme s'aperçoive tout seul que quelque chose a changé.

**Durée :** 2 × 45 min

**Ce que tu construis :** le `revisor` configuré sans reconstruire l'image : la liste de services sort du Deployment et vit dans un `ConfigMap` ; le token d'accès vit dans un `Secret` monté comme fichier et impossible à modifier ; et un changement dans la liste déclenche tout seul un *rollout*

**Ce que tu apprends :** `ConfigMap` comme variables d'environnement (le `revisor` ne lit que des variables) et pourquoi le modifier manuellement ne redémarre personne ; `Secret` comme fichier, qui peut le lire et pourquoi base64 n'est pas du chiffrement ; `fsGroup` et le propriétaire des fichiers montés ; Kustomize avec `configMapGenerator` et `secretGenerator`, et le *hash* qui déclenche le *rollout* ; les Secrets immuables

**D'où tu viens.** De la [Leçon 3](03-services-dns.md) : le `revisor` a trois répliques derrière un Service appelé `revisor`, le service de test qui échoue exprès vit derrière un autre appelé `prueba`, et tu sais utiliser un Pod de débogage avec `curl` (`depurar`) pour parler au `revisor` depuis l'intérieur du cluster. De la [Leçon 2](02-pods-deployments.md), tu apportes la chaîne Deployment → ReplicaSet → Pod et la règle qui compte ici plus que jamais : un *rollout* se produit **si et seulement si le modèle du Pod change**. Et du [cours de Docker](https://www.habil.mx/fr/cours/docker/), tu apportes une habitude : le token du `revisor` lui est donné par fichier (`REVISOR_TOKEN_ARCHIVO`), jamais par variable, parce qu'une variable se lit avec `docker inspect`.

**Ce que cette leçon ne fait pas.** Elle ne chiffre pas les Secrets à l'intérieur du cluster : cela se configure dans le `kube-apiserver` d'un cluster réel, et la [Leçon 10](10-proyecto-final.md) le met dans la liste de ce qui manque à ce projet pour être prêt pour la production. Elle ne décide pas non plus **qui** peut lire les Secrets avec des permissions fines : tu vas voir ici que, toi, tu le peux, et la [Leçon 7](07-aislar-permisos-red.md) donne à chaque programme son propre compte et des permissions minimales. Et le cluster ne sait pas encore distinguer un `revisor` qui a démarré d'un `revisor` qui peut servir ; dans cette leçon, tu vas voir ce que cela coûte, et les probes arrivent dans la [Leçon 5](05-salud-recursos-apagado.md).

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1 (qui embarque Kustomize v5.8.1) et l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, sur le cluster de trois nœuds de la Leçon 1, appelé ici `curso-k8s-l4`. La machine était un Mac à processeur ARM avec Docker Engine 29.2.1 dans une machine virtuelle Linux (Colima), **pas** Linux Mint, qui est le système de référence du cours. Ce qui change sur ta Mint : l'architecture, les suffixes aléatoires des Pods et des ReplicaSets, les IP, les âges, le nœud sur lequel atterrit chaque réplique, la taille que rapporte `tmpfs` et, surtout, **le token et le nom du Secret**, qui sont nouveaux à chaque exécution (le nom du ConfigMap, en revanche, doit sortir identique chez toi : `revisor-config-t6cm6872fk`). Un détail de plus : le `wc -c` de macOS remplit le nombre d'espaces à gauche (`      33`) et celui de Linux ne le fait pas (`33`). Le parcours complet se trouve dans [`programas/04-configuracion-secretos/`](../programas/04-configuracion-secretos) : `correr.sh` crée le cluster, y charge les deux images du cours, le laisse tel que l'a laissé la Leçon 3, parcourt la leçon dans l'ordre, exécute les Exercices 1 à 3 (le 3, dans un espace de noms jetable qu'il supprime à la fin) et supprime le cluster. Il a duré 2 minutes et 43 secondes ; créer le cluster et attendre qu'il soit prêt a pris 42 secondes, et le supprimer, 4. Sa sortie est `correr.salida.txt`. Le script génère son propre token, le supprime à la fin et laisse `kustomization.yaml` comme il était, même s'il s'arrête à mi-chemin ; et si `kind create cluster` échoue, il s'arrête là avec le code 1, au lieu de continuer sur un cluster qui n'existe pas.

## À la fin, tu seras capable de

- Sortir une variable d'environnement d'un Deployment vers un `ConfigMap` et lire dans `kubectl describe pod` d'où provient chaque variable.
- Démontrer avec le rapport du `revisor` que modifier un `ConfigMap` manuellement ne change pas les variables des Pods déjà en cours d'exécution, et expliquer pourquoi.
- Écrire une `kustomization.yaml` avec `configMapGenerator` et `secretGenerator`, voir avec `kubectl kustomize` ce qu'elle va générer et l'appliquer avec `kubectl apply -k`.
- Prédire qu'un changement dans le contenu d'un ConfigMap généré donne un autre suffixe à son nom (et que le même contenu qu'avant redonne exactement le même nom), et vérifier avec `kubectl diff -k` que ce changement de nom déclenche un *rollout*.
- Monter un `Secret` comme fichier avec `defaultMode: 0440` et `fsGroup`, et localiser ce fichier sur le nœud, dans un `tmpfs`.
- Décoder un Secret avec `base64 -d` pour démontrer que base64 n'est pas du chiffrement, et changer le contenu d'un Secret immuable de la seule façon possible : avec un autre Secret.
- Reconnaître le `permission denied` d'un Secret illisible et le `couldn't find key` d'une clé mal écrite, et dire lequel des deux fait planter le service et pourquoi.

## Le pourquoi avant le comment

Jusqu'à la Leçon 3, la liste de services que vérifie le `revisor` était écrite à l'intérieur du Deployment, sur une ligne `value: "prueba http://prueba:9000/ 2s"`. Cela fonctionne, mais cela réunit deux choses qui changent à des rythmes différents. La **recette** du service (quelle image, combien de répliques, quelle sécurité) change peu et est entretenue par celui qui exploite le cluster. La **configuration** (quels services vérifier, avec quel délai limite) change souvent et est parfois demandée par une autre équipe. Si les deux vivent dans le même fichier, chaque changement de la liste est un changement de la recette, avec sa relecture et son risque. La [documentation des ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) le formule ainsi : un ConfigMap te permet de « séparer la configuration propre à l'environnement de tes images de conteneur, afin que tes applications soient facilement portables ».

Le token est une autre affaire. Ce n'est pas une configuration que quelqu'un veut lire : c'est une clé. Écrit dans le Deployment, il voyage avec le manifeste vers Git, vers chaque copie du dépôt et vers chaque écran où quelqu'un fait `kubectl get deployment -o yaml`. Kubernetes a un objet à part pour cela, le **Secret**, et cette leçon te montre avec des sorties réelles ce qu'il protège et ce qu'il ne protège pas. Car le Secret a une réputation qu'il n'a pas méritée : beaucoup de gens croient que, parce que ses données apparaissent en base64, elles sont chiffrées. Elles ne le sont pas, et tu vas le vérifier avec une seule commande.

Et il y a une troisième question, la plus subtile : **quand le programme s'aperçoit-il que sa configuration a changé ?** Le `revisor` lit ses variables d'environnement une seule fois, au démarrage. Kubernetes ne redémarre personne parce qu'un ConfigMap a changé. Si tu ne vois pas cela, tu vas changer la configuration, tu vas voir l'objet modifié dans le cluster et tu vas croire que c'est fait, alors que les Pods continuent de travailler avec l'ancienne liste. La solution de cette leçon est un outil que tu as déjà dans `kubectl`, Kustomize, et une astuce si simple qu'elle ressemble à de la triche : changer le **nom** du ConfigMap chaque fois que son contenu change.

La leçon comporte sept parties de concepts, puis les sections habituelles :

1. **La configuration écrite dans le Deployment** (4.1) : le point de départ.
2. **Un ConfigMap écrit à la main** (4.2) et comment il se branche sur une variable.
3. **Modifier un ConfigMap ne redémarre personne** (4.3), mesuré.
4. **Le token comme Secret, et pourquoi comme fichier** (4.4).
5. **Kustomize : les générateurs et le *hash*** (4.5).
6. **base64 n'est pas du chiffrement** (4.6).
7. **Modifier la liste déclenche le *rollout*** (4.7).

Voici la destination. À la fin de 4.5, le `revisor` se configure de l'extérieur, et chaque objet porte dans son nom l'empreinte de son contenu :

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

## Les concepts

### 4.0 Le cluster, tel que l'a laissé la Leçon 3

Cette leçon utilise son propre cluster, `curso-k8s-l4`, avec la configuration à trois nœuds de la Leçon 1, tout juste créé. Crée-le ainsi, depuis la racine du dépôt du cours, avec le même soin que dans la Leçon 1, et charge-y les deux images du cours de Docker :

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

Le `export` ne vaut que dans ce terminal. Si tu en ouvres un autre, répète le `export` avec le même chemin, sinon `kubectl` parlera à un autre cluster. Et si `kind create cluster` échoue, ne continue pas : lis son message, car tout ce qui viendrait ensuite supposerait un cluster qui n'existe pas.

On lui applique ensuite ce qu'a laissé la Leçon 3. Les fichiers se trouvent dans le dossier des programmes de cette leçon : le Deployment de départ, dans `punto-de-partida/revisor-deployment.yaml`, et les deux Services, le Deployment de `prueba` et le Pod `depurar`, sans changement. Les sorties de cette section proviennent de l'exécution de `correr.sh`, qui fait exactement cela :

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

Comme toujours, la première commande demande à quel cluster tu parles. Dans cette leçon, tu vas créer et supprimer des Secrets, et `kind-curso-k8s-l4` est la seule réponse qui te laisse continuer. **Répète `kubectl config current-context` avant chaque commande qui change quelque chose** (`apply`, `patch`, `delete`, `rollout restart`) et avant chaque exercice : le script le fait avant chaque `kubectl`, et toi aussi. Pour ne pas remplir la leçon de lignes identiques, on ne l'affiche qu'aux endroits où cela compte le plus.

### 4.1 La configuration écrite à l'intérieur du Deployment

Voici comment est aujourd'hui la configuration du `revisor` :

```text
$ kubectl get deployment revisor -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
[{"name":"REVISOR_SERVICIOS","value":"prueba http://prueba:9000/ 2s"}]

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

Une variable, avec la valeur écrite directement (`value`). Et `/api/estados` répond à quiconque le demande : le `revisor` n'a pas encore de token, donc il ne l'exige pas. Ce tableau est ton **instrument de mesure** dans toute la leçon. Le `revisor` n'a pas de *shell*, donc tu ne peux pas entrer voir ses variables avec `env` ; mais son rapport liste exactement les services qu'il a lus dans `REVISOR_SERVICIOS` au démarrage. Si le tableau dit `prueba` et rien d'autre, le `revisor` travaille avec cette liste, quoi que dise n'importe quel objet du cluster.

Une question à garder : que devrais-tu faire pour ajouter un service à la liste ? Éditer ce Deployment. Cela change son modèle, donc cela déclenche un *rollout* (la règle de la Leçon 2). Ça fonctionne. Le problème n'est pas technique, il tient à qui touche à quoi.

### 4.2 Un ConfigMap écrit à la main

#### 4.2.1 L'objet

Un **ConfigMap** est, d'après sa documentation, « un objet de l'API qui sert à conserver des données non confidentielles sous forme de paires clé-valeur ». Les deux mots qui comptent sont **non confidentielles** : la même page contient un avertissement encadré, « un ConfigMap n'offre ni secret ni chiffrement », et te renvoie vers un Secret si la donnée est confidentielle. Et un autre avertissement : ce que tu conserves dans un ConfigMap ne peut pas dépasser 1 MiB. C'est fait pour la configuration, pas pour de gros fichiers.

Voici le premier, écrit à la main. C'est un **programme** : `programas/04-configuracion-secretos/fig04_01.configmap.yaml`.

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

Il se lit comme n'importe quel objet : `apiVersion: v1` (le groupe central de l'API, comme les Pods), `kind: ConfigMap`, un nom et une étiquette. Ce qui est nouveau, c'est `data` : une table de clés et de valeurs, toutes en texte. Il n'y a ici qu'une seule clé, `REVISOR_SERVICIOS`, et elle s'appelle comme la variable, exprès : ainsi personne n'a à traduire entre deux noms.

```text
$ kubectl apply -f fig04_01.configmap.yaml
configmap/revisor-config created

$ kubectl get configmap revisor-config -o jsonpath='{.data}{"\n"}'
{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s"}
```

(Avant cet `apply`, `kubectl config current-context` a affiché `kind-curso-k8s-l4`.) Jusqu'ici, le ConfigMap existe, mais personne ne l'utilise. Un ConfigMap ne fait rien par lui-même : c'est une donnée conservée dans le cluster, qui attend qu'un Pod la demande.

#### 4.2.2 Du ConfigMap à la variable

La documentation donne quatre façons d'utiliser un ConfigMap depuis un Pod : comme arguments de la commande du conteneur, comme **variables d'environnement**, comme **fichiers** dans un volume en lecture seule, ou en le lisant avec du code qui parle à l'API de Kubernetes. Le `revisor` décide pour toi laquelle convient : il ne lit que des variables d'environnement (`REVISOR_SERVICIOS`, `REVISOR_PUERTO`, `REVISOR_REPORTE` et `REVISOR_TOKEN_ARCHIVO`). Un fichier contenant la liste ne lui servirait à rien, parce qu'il ne le chercherait pas. C'est pourquoi, dans ce cours, **le ConfigMap va sous forme de variable**.

Ce Deployment (`fig04_02.revisor-con-configmap.yaml`, un autre **programme**) est celui de la Leçon 3 avec une seule différence. Là où il y avait `value: "prueba http://prueba:9000/ 2s"`, il indique maintenant d'où tirer la valeur :

```yaml
        env:
        - name: REVISOR_SERVICIOS
          valueFrom:
            configMapKeyRef:
              name: revisor-config
              key: REVISOR_SERVICIOS
```

Lis-le comme une phrase : la variable `REVISOR_SERVICIOS` prend sa valeur (`valueFrom`) de la clé `REVISOR_SERVICIOS` du ConfigMap appelé `revisor-config`. Le reste du fichier ne change pas, et tu peux le vérifier toi-même avec `diff punto-de-partida/revisor-deployment.yaml fig04_02.revisor-con-configmap.yaml`.

Il existe une autre forme, `envFrom`, qui convertit **toutes** les clés d'un ConfigMap en variables d'un seul coup. Elle est commode, mais elle cache quelles variables reçoit le conteneur : il faudrait aller voir le ConfigMap pour le savoir. Comme le `revisor` ignore en silence les variables qu'il ne connaît pas, `configMapKeyRef` convient ici : chaque variable est écrite, avec son nom, dans le Deployment.

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

`configured` : le modèle a changé, donc il y a eu un *rollout* et il y a de nouveaux Pods. `kubectl describe pod` montre la variable et, à la place de sa valeur, **d'où elle provient** : « définie avec la clé `REVISOR_SERVICIOS` du ConfigMap `revisor-config` ». `Optional: false` signifie que, si ce ConfigMap ou cette clé n'existent pas, le conteneur ne démarre pas. Tu vas le provoquer dans l'Exercice 1. Le tableau reste le même qu'avant, comme il se doit : même liste, autre endroit.

### 4.3 Modifier un ConfigMap ne redémarre personne

Voici maintenant la demande de la scène : ajouter un service. Pour ne dépendre de rien en dehors du cluster, le « nouveau service » est le même `prueba` sous un autre nom, `lento`, et avec un délai limite plus court, d'une demi-seconde. Ce qui compte, c'est qu'une nouvelle ligne apparaisse dans le tableau.

Avant de rien changer, vérifie le contexte (`kubectl config current-context` → `kind-curso-k8s-l4`) et regarde les ReplicaSets. Celui du dessus est celui de `fig04_02` ; celui du dessous, celui de la Leçon 3, à `0 0 0` :

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       3s
revisor-697fb84f97   0         0         0       12s

$ kubectl patch configmap revisor-config -p '{"data":{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms"}}'
configmap/revisor-config patched
(30 s después)
```

`kubectl patch` ne change que les champs que tu lui donnes. Ici, il a donné à la clé une liste de deux services séparés par une virgule. Le cluster dit `patched` : le ConfigMap a changé. Trente secondes plus tard :

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       34s
revisor-697fb84f97   0         0         0       43s

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           4ms  200
```

Pas un seul nouveau ReplicaSet, et le tableau continue de ne dire que `prueba`. **Le ConfigMap a changé et le `revisor` ne s'en est pas aperçu.** Ce n'est pas un retard qui se règle en attendant : il en sera ainsi jusqu'à ce que le Pod soit recréé.

La raison a deux moitiés, et il faut voir les deux.

**La moitié de Kubernetes.** Une variable d'environnement est fixée au démarrage du conteneur. C'est ainsi que fonctionnent les variables sous Linux : le processus reçoit son environnement à sa naissance et personne ne le lui change ensuite de l'extérieur. La documentation des ConfigMaps le dit sans détour : « les ConfigMaps consommés comme variables d'environnement ne sont pas mis à jour automatiquement et nécessitent le redémarrage du Pod ». Et le Deployment n'a aucune raison de redémarrer quoi que ce soit : son modèle dit « prends la variable dans le ConfigMap `revisor-config` », et cela n'a pas changé. Ce qui a changé, c'est le contenu du ConfigMap, pas le modèle ; la règle du « si et seulement si » de la Leçon 2 n'est donc pas remplie. Il n'y a pas de *rollout*.

**La moitié du `revisor`.** Même si Kubernetes pouvait lui changer la variable, cela ne servirait à rien : le `revisor` lit sa configuration une seule fois, au démarrage. Son code (`cmd/revisor/config.go`, du cours de Docker) construit la liste dans une fonction appelée au début et plus jamais ensuite.

Et si le ConfigMap était monté comme fichier ? La documentation dit qu'alors il se met bien à jour tout seul, « éventuellement », avec le délai de synchronisation du `kubelet`. Mais cela n'aide qu'un programme qui relit le fichier, et le `revisor` ne le fait pas. De nombreux programmes réels ne le font pas non plus. C'est pourquoi la bonne question n'est jamais « le ConfigMap a-t-il changé ? », mais « le programme tourne-t-il déjà avec la nouvelle configuration ? ». Et cette question se règle avec le programme, pas avec le ConfigMap : ici, avec le tableau.

Le remède manuel est celui de la Leçon 2 :

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

Cette fois, deux services. `rollout restart` a ajouté l'annotation `restartedAt` au modèle, le modèle a changé et les nouveaux Pods ont lu la nouvelle liste à leur naissance. Révision 3.

Cela fonctionne, mais cela dépend de quelqu'un qui **se souvienne** de redémarrer. Et remarque ce qui ne reste nulle part : l'historique du Deployment dit qu'il y a eu trois révisions, mais aucune ne dit que la troisième était due à un changement de liste. Si demain quelqu'un fait `rollout undo` pour revenir à la révision 2, il revient au modèle de la révision 2, qui pointe vers le même ConfigMap `revisor-config`… lequel contient déjà la nouvelle liste. Il n'y a aucun moyen de revenir à l'ancienne configuration, parce que l'ancienne configuration n'existe plus. La section 4.5 résout les deux problèmes avec une seule idée.

### 4.4 Le token : un Secret, et comme fichier

#### 4.4.1 Ce qu'est un Secret

Un **Secret**, d'après sa [documentation](https://kubernetes.io/docs/concepts/configuration/secret/), est « un objet qui contient une petite quantité de données sensibles, comme un mot de passe, un token ou une clé ». Il ressemble beaucoup à un ConfigMap : c'est aussi une table de clés et de valeurs, il a aussi une limite de 1 MiB, et il s'utilise aussi comme variable ou comme fichier. Les différences tiennent au traitement que lui réserve le cluster :

- **Il ne voyage que vers les nœuds qui en ont besoin.** Un Secret n'est envoyé à un nœud que si un Pod de ce nœud le demande.
- **Sur le nœud, si tu le montes comme fichier, il vit en mémoire.** Le `kubelet` conserve la copie dans un `tmpfs`, un système de fichiers en RAM, « pour que la donnée confidentielle ne soit pas écrite sur un stockage durable » ; et il la supprime quand le Pod qui l'utilisait s'en va. Cette protection est celle du volume : si le Secret est consommé comme variable d'environnement, il n'y a pas de `tmpfs` en jeu, parce que la valeur voyage dans la définition du processus que reçoit le *runtime*. Le `tmpfs`, tu le verras en 4.5.6.
- **Il peut être traité à part dans les permissions.** Une règle RBAC (Leçon 7) peut permettre de lire les ConfigMaps et pas les Secrets.

Et une chose qu'il ne fait **pas** : chiffrer. La même page s'ouvre sur un avertissement encadré qu'il vaut la peine de lire en entier : « Les Secrets de Kubernetes sont stockés, par défaut, non chiffrés dans le magasin de données du serveur d'API (etcd). Quiconque a accès à l'API peut lire ou modifier un Secret, et de même quiconque a accès à etcd. De plus, quiconque est autorisé à créer un Pod dans un espace de noms peut utiliser cet accès pour lire n'importe quel Secret de cet espace de noms ». La section 4.6 le met à l'épreuve.

#### 4.4.2 Le token se génère, il ne s'écrit pas

Le token du `revisor` n'est pas une valeur que l'on choisit, ni une que l'on copie depuis un document. Il se génère, au hasard, chaque fois qu'il en faut un nouveau :

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

`openssl rand -hex 16` demande 16 octets au hasard et les écrit en hexadécimal : 32 caractères, plus le saut de ligne qu'il ajoute à la fin. C'est pourquoi `wc -c` compte 33. Les parenthèses et le `umask 077` changent le masque de permissions **uniquement pour cette commande** : le fichier naît avec la permission `0600` (`-rw-------`), que toi seul peux lire, au lieu du `0644` que laisserait ton masque habituel, lisible par n'importe quel utilisateur de la machine. C'est le même token qui, dans le Pod, aura `0440` : on en prend le même soin sur ta machine que dans le cluster. Ce saut de ligne ne gêne pas : le `revisor`, en lisant le fichier, retire les espaces et les sauts de ligne des bords (`strings.TrimSpace`, dans son code).

Les deux dernières commandes sont l'habitude de cette leçon. `.gitignore` dit que `token.txt` n'entre **pas** dans le dépôt, et `git check-ignore -v` le confirme, en disant quel fichier et quelle ligne l'excluent. La scène a commencé avec un token dans l'historique de Git, et voici la façon d'éviter que cela se reproduise : le fichier existe sur ta machine, le cluster le reçoit, et Git ne le voit jamais. Si tu travailles en dehors d'un dépôt, `git check-ignore` te dira que ce n'est pas un dépôt ; la règle reste valable pour le jour où ce le sera.

#### 4.4.3 Pourquoi comme fichier et pas comme variable ?

Un Secret peut être passé comme variable d'environnement (avec `secretKeyRef`, jumeau de `configMapKeyRef`). Ce cours ne le fait pas, et ce n'est pas par goût :

- **Une variable s'hérite.** Tout processus lancé par le conteneur reçoit une copie de son environnement. Un fichier n'est pas copié dans chaque processus enfant : il faut aller l'ouvrir exprès, et seul peut l'ouvrir celui qui en a la permission.
- **Une variable s'imprime sans le vouloir.** Dans un vidage d'erreurs, dans un `env` de débogage, dans le journal d'un programme qui, en échouant, écrit « j'ai démarré avec cette configuration ». Le [guide des bonnes pratiques pour les Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) demande à chaque application qui a lu le Secret d'éviter de « consigner la donnée en clair ».
- **Le `revisor` lui-même le demande.** S'il reçoit le token dans `REVISOR_TOKEN`, il démarre, mais il écrit dans son journal un avertissement : `el token llegó por REVISOR_TOKEN: cualquiera con docker inspect lo puede leer; usa REVISOR_TOKEN_ARCHIVO`. Son programme a déjà voté.

Le `revisor` reçoit donc deux choses : le Secret monté comme fichier dans `/secretos/token`, et une variable normale, non secrète, qui lui dit où le chercher : `REVISOR_TOKEN_ARCHIVO=/secretos/token`. Le chemin n'est pas un secret ; le contenu, si.

### 4.5 Kustomize : les générateurs et le *hash*

#### 4.5.1 L'idée : le nom change quand le contenu change

Rappelle-toi les deux problèmes de 4.3 : le changement du ConfigMap ne déclenchait pas de *rollout*, et il n'y avait aucun moyen de revenir à l'ancienne configuration. Les deux viennent du même endroit : le ConfigMap a un **nom fixe**, donc le modèle du Deployment ne change jamais, même si ce qu'il y a à l'intérieur change.

Imagine maintenant que le ConfigMap s'appelle différemment selon son contenu : `revisor-config-t6cm6872fk` avec une liste, `revisor-config-7fbkh2926f` avec une autre. Changer la liste créerait **un autre** ConfigMap, et le Deployment devrait pointer vers le nouveau nom. Son modèle changerait, et la règle de la Leçon 2 ferait le reste : *rollout*. Et l'ancien ConfigMap resterait là, intact, pour qu'une ancienne révision du Deployment pointe vers lui. Cela a un coût : Kustomize ne supprime pas les anciens, ils s'accumulent donc. Dans le cours, cela n'a pas d'importance, parce qu'à la fin tu supprimes le cluster entier ; dans un cluster qui vit des mois, il faudrait nettoyer à la main (`kubectl delete configmap <nom>`) ceux qu'aucune révision ne conserve plus, et de même pour les Secrets.

Faire cela à la main serait un supplice : calculer un nom, l'écrire à deux endroits, ne jamais se tromper. C'est pour cela qu'existe **Kustomize**, qui est inclus dans `kubectl` depuis la version 1.14 (`kubectl kustomize` et `kubectl apply -k`) ; dans ce cours, c'est la v5.8.1, celle qu'embarque `kubectl` v1.37.1. Le [guide de Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) l'explique en une phrase : les ConfigMaps et les Secrets générés « portent un suffixe avec le *hash* de leur contenu. Cela garantit qu'un nouveau ConfigMap ou Secret est généré quand le contenu change ». Et Kustomize ne se contente pas de générer le nom : il connaît les champs des objets Kubernetes qui pointent vers un ConfigMap ou un Secret (`configMapKeyRef`, `secretKeyRef`, `envFrom`, les `volumes`) et y met le nouveau nom. Ce n'est pas un remplacement de texte : une mention de `revisor-config` dans une annotation ou dans un champ d'une ressource étendue ne se met pas à jour toute seule.

#### 4.5.2 La `kustomization.yaml`

Kustomize lit un fichier appelé `kustomization.yaml` dans un dossier. Voici celui de la leçon, un **programme** :

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

Trois blocs :

- **`resources`** : les manifestes que tu connais déjà, tels quels. Kustomize les lit, les ajuste et les livre ensemble. `depurar.yaml` n'est pas dans la liste exprès : c'est un outil de débogage, pas une partie du service.
- **`configMapGenerator`** : « génère un ConfigMap appelé `revisor-config`, avec cette clé et cette valeur ». `literals` sert aux valeurs écrites directement, sous la forme `CLÉ=valeur`. La liste de services n'est plus dans le Deployment : elle est ici, sur une ligne qui peut être relue seule.
- **`secretGenerator`** : « génère un Secret appelé `revisor-token`, avec une clé `token` dont le contenu est celui du fichier `token.txt` ». La forme `token=token.txt` sépare le nom de la clé (à gauche) du fichier d'où elle provient (à droite). Sans le `token=`, la clé s'appellerait comme le fichier, `token.txt`. Et `options: immutable: true` marque le Secret comme immuable ; la section « L'habitude de sécurité » explique pourquoi.

Remarque ce qui **n'est pas** dans ce fichier : le token. La `kustomization.yaml` va bien dans le dépôt, et elle dit seulement d'où le tirer.

#### 4.5.3 Le Deployment final

Le Deployment de la leçon est `revisor-deployment.yaml`, un **programme**. Par rapport à `fig04_02`, trois choses changent : le token monté comme fichier, la variable qui dit où il se trouve, et une nouvelle ligne dans le `securityContext` du Pod :

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

Parcours-le de bas en haut, en suivant le voyage du token :

- **Le volume `token`**, de type `secret`, prend le Secret `revisor-token` et convertit chaque clé en fichier. Le Secret a une clé, `token`, donc le volume aura un fichier, `token`.
- **`defaultMode: 0440`** : les permissions de ce fichier. `0440` en octal signifie « le propriétaire peut lire, le groupe peut lire, les autres rien, et personne n'écrit ». Si tu ne le mets pas, le [guide de distribution sécurisée des identifiants](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) dit que `0644` est utilisé, ce qui permet à tous de lire. Ici, il n'y a pas d'autres utilisateurs dans le conteneur, mais la permission minimale ne coûte rien.
- **Le montage** place ce volume dans `/secretos`, avec `readOnly: true`. Ainsi, le fichier se trouve dans `/secretos/token`.
- **La variable `REVISOR_TOKEN_ARCHIVO`** indique ce chemin au `revisor`. C'est un `value` normal : le chemin n'est pas secret.
- **`fsGroup: 65532`**, en haut, dans le `securityContext` du Pod. C'est la ligne la plus courte et celle qui coûte le plus à comprendre ; elle a donc sa propre explication en 4.5.6.

Remarque `name: revisor-config` et `secretName: revisor-token` : ici, ils sont écrits **sans** *hash*. Tu les écris ainsi, avec le nom de base, et Kustomize les remplace par le nom généré en assemblant le résultat. Si tu écrivais le nom avec le *hash*, tu devrais le changer à la main à chaque changement de liste, ce qui est précisément ce qu'on voulait éviter.

#### 4.5.4 Voir avant d'appliquer

`kubectl kustomize .` assemble le résultat et l'imprime, **sans** toucher au cluster. C'est la façon de voir ce qui va se passer :

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

Voilà les noms générés : `revisor-config-t6cm6872fk` et `revisor-token-bh266kt42m`. Le suffixe du ConfigMap ne dépend que de son contenu, donc sur ta machine, il doit sortir identique, `t6cm6872fk`. Celui du Secret dépend du token, qui est nouveau à chaque exécution ; le tien sera différent.

Et voilà le Secret tel que le cluster va le recevoir. `type: Opaque` est le type générique, « données quelconques ». `immutable: true` vient des `options`. Et dans `data`, la clé `token` avec une valeur qui ne ressemble pas à ton token. Garde cette chaîne : en 4.6, tu vas la démonter.

#### 4.5.5 Appliquer

Vérifie le contexte et applique :

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

`apply -k .` est `apply` avec Kustomize : il assemble le dossier et applique le résultat. Kustomize ordonne les objets pour que le ConfigMap et le Secret soient créés **avant** le Deployment qui les utilise. Les Services et `prueba` n'ont pas changé (`unchanged`). Le `revisor`, si (`configured`) : son modèle pointe maintenant vers de nouveaux noms et monte un nouveau volume.

Regarde maintenant ce qui est resté dans le cluster. Pour les Secrets, on utilise un **sélecteur de champ** (`--field-selector`), qui filtre sur un champ de l'objet et non sur ses étiquettes : `type!=kubernetes.io/service-account-token` écarte les Secrets de type « token de compte de service », s'il y en avait, pour ne voir que les tiens :

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

Trois ConfigMaps. `kube-root-ca.crt` est posé par Kubernetes dans chaque espace de noms, avec le certificat du cluster ; il n'est pas à toi. `revisor-config-t6cm6872fk` est celui qui a été généré. Et `revisor-config`, celui que tu as écrit à la main en 4.2, **est toujours là**. `kubectl apply` crée et met à jour ce que tu lui donnes ; il ne supprime pas ce que tu ne lui donnes pas. Personne ne l'utilise plus, il a donc été supprimé à la main. Souviens-toi de cela en 4.7 et dans l'Exercice 2 : chaque changement laisse derrière lui l'objet précédent.

Voyons maintenant le Pod de l'intérieur :

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

`config map 'revisor-config-t6cm6872fk'` : le Deployment pointe déjà vers le nom avec *hash*, bien que dans ton fichier tu aies écrit `revisor-config`. Kustomize l'a changé à l'assemblage. Et dans `Mounts`, `/secretos from token (ro)` : le Secret monté, en lecture seule. Le troisième montage est l'identifiant du compte de service que la Leçon 2 a noté comme dette ; la Leçon 7 le supprime.

Et le `revisor` ? Il a maintenant un token, donc il l'exige :

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

Sans token, `401` et un message clair. Avec l'en-tête `Authorization: Bearer …`, le tableau. Remarque les guillemets de la troisième commande : `$(cat token.txt)` est entre guillemets doubles, donc ton *shell* le substitue **sur ta machine**, avant d'envoyer la commande au Pod. Le token n'apparaît jamais écrit dans l'historique de tes commandes, seulement le `cat`. Il apparaît bien, le temps de la commande, comme argument du processus : dans un `ps` de ta machine et à l'intérieur de `depurar`. Pour un exercice local, cela suffit ; dans un cluster partagé, le token ne se passe pas par la ligne de commande. Et `/salud` (celle que consulte `healthcheck`) ne demande pas de token, exprès : les probes de la Leçon 5 vont l'appeler sans identifiants.

Le tableau a de nouveau dit seulement `prueba`, et cela aussi est correct : la liste de la `kustomization.yaml` ne contient qu'un seul service. Le `lento` que tu avais ajouté à la main en 4.3 vivait dans le ConfigMap que tu viens de supprimer.

#### 4.5.6 Le Secret, vu depuis le nœud

Où se trouve physiquement le fichier `/secretos/token` ? Le `revisor` n'a pas de *shell* pour aller le regarder, mais le nœud de kind, lui, en a un, et le `kubelet` conserve les volumes de chaque Pod dans un dossier portant l'identifiant (`uid`) du Pod. Pour ce Pod, sur le nœud `curso-k8s-l4-worker` :

```text
$ docker exec curso-k8s-l4-worker ls -ln /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 65532 33 Oct 21 13:27 token

$ docker exec curso-k8s-l4-worker sh -c 'mount | grep a415d22b-9837-4123-a7d9-82b1baf9435a | grep -E "secret/token "'
tmpfs on /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token type tmpfs (rw,relatime,size=16342676k,inode64,noswap)
```

Le nom du nœud et l'`uid` du Pod proviennent de `kubectl get pod <pod> -o jsonpath='{.spec.nodeName}'` et de `'{.metadata.uid}'` ; le script les cherche tout seul. Deux choses à vérifier de tes propres yeux :

- **`-r--r----- 1 0 65532 33 … token`** : le fichier a les permissions `0440` que tu as demandées (`r--r-----`), il fait 33 octets (ton token avec son saut de ligne), son propriétaire est l'utilisateur `0` (`root`) et son groupe est le **65532**. Ce groupe, c'est `fsGroup` qui l'a posé.
- **`tmpfs`** : le dossier du volume est un système de fichiers en mémoire, comme le promet la documentation. Le token n'a pas été écrit sur le disque du nœud.

Le dossier `..data` est un détail de la façon dont le `kubelet` met à jour les volumes de Secrets : le fichier `token` que voit le conteneur est un lien vers `..data/token`, et quand le Secret change, le `kubelet` prépare un nouveau dossier et change le lien d'un seul coup. Avec un Secret immuable, comme celui-ci, cela n'arrivera jamais.

Rapproche maintenant la ligne de `ls` du `securityContext`. Le `revisor` tourne avec l'utilisateur 65532 et le groupe 65532. Le fichier appartient à `root` et au groupe 65532, avec une permission de lecture pour le groupe. Le `revisor` le lit **parce qu'il fait partie du groupe**. Sans `fsGroup`, le groupe du fichier serait un autre et le `revisor` n'aurait aucun moyen de le lire. Le [guide du `securityContext`](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) décrit `fsGroup` ainsi : les processus du conteneur deviennent membres de ce groupe en tant que groupe supplémentaire, et « les volumes qui prennent en charge la gestion des propriétaires sont modifiés pour appartenir au GID indiqué par `fsGroup` ». La section « L'erreur que tu vas voir » t'apprend ce qui se passe si tu l'omets, et ce n'est pas ce que tu attendrais.

### 4.6 base64 n'est pas du chiffrement

Prends la chaîne que tu as vue dans le Secret et celle du cluster :

```text
$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}{"\n"}'
NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK

$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}' | base64 -d
433c7adfa6fc6fc3d03676b7f5c2339e

$ cat token.txt
433c7adfa6fc6fc3d03676b7f5c2339e
```

(Le `grep revisor-token | xargs` trouve le Secret même si son nom change à chaque exécution.) Une commande, sans clé, sans mot de passe, sans rien à deviner : `base64 -d` rend le token complet, identique au fichier. **base64 n'est pas du chiffrement.** C'est un **encodage** : une façon d'écrire n'importe quelle suite d'octets en n'utilisant que des lettres, des chiffres, `+` et `/`, plus un `=` de remplissage à la fin quand il le faut (comme le `eA==` plus loin), pour qu'elle tienne dans un fichier texte comme un YAML. Chiffrer signifie que, sans clé, on ne peut pas lire. Encoder signifie qu'on peut lire avec une table publique. Le guide de bonnes pratiques le dit en une ligne : « l'encodage base64 n'est **pas** une méthode de chiffrement ; il n'apporte aucune confidentialité supplémentaire par rapport au texte brut ». Et il met en garde contre l'erreur de la scène : si tu conserves un manifeste de Secret dans un dépôt, « le secret est à la portée de tous ceux qui peuvent lire le manifeste ».

Pourquoi base64 existe-t-il alors ? Parce qu'un Secret peut contenir n'importe quoi, y compris des données binaires, comme un certificat ou une clé, et qu'un YAML est du texte. Base64 est l'enveloppe qui permet de mettre des octets dans un fichier texte. Ce n'est pas un coffre-fort.

Qui peut faire ce que tu viens de faire ?

```text
$ kubectl auth can-i get secrets
yes
```

`kubectl auth can-i` demande au cluster si **toi** tu peux faire quelque chose, sans le faire. Toi, tu le peux, parce que le `kubeconfig` que t'a donné kind est celui d'un administrateur. Dans un cluster réel, c'est RBAC qui contrôle cela, et la Leçon 7 le pratique. Mais la documentation des Secrets met en garde contre une porte dérobée : celui qui peut créer un Pod dans un espace de noms peut y monter n'importe quel Secret de cet espace et le lire de l'intérieur, même s'il n'a pas la permission `get secrets`. C'est pourquoi les Secrets d'un service vivent dans l'espace de noms de ce service, et non dans un espace partagé avec d'autres (Leçon 7).

Et une de plus, qui ne se voit pas d'ici : à l'intérieur du cluster, le Secret est conservé dans `etcd` **sans être chiffré**, sauf si l'administrateur active le chiffrement au repos du `kube-apiserver`. Le guide de bonnes pratiques en fait la première recommandation : « tu devrais configurer le chiffrement des données de tes Secrets dans etcd ». Dans kind, on ne le fait pas ; la Leçon 10 le consigne dans la liste de ce qui manque pour la production.

Ce que te donne bel et bien un Secret, par comparaison avec l'écriture du token dans le Deployment, c'est ceci : le token n'est ni dans ton manifeste ni dans Git ; il ne voyage que vers les nœuds qui l'utilisent et y vit en mémoire ; et l'on peut donner la permission de lire les Deployments sans donner celle de lire les Secrets. C'est beaucoup. Simplement, ce n'est pas du chiffrement.

### 4.7 Modifier la liste déclenche le *rollout*

Maintenant, la demande de la scène, avec l'outil complet. Avant le changement, les ReplicaSets du `revisor` (quatre révisions : celle de la Leçon 3, celle de `fig04_02`, celle du `rollout restart` et celle de `apply -k`) :

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   0         0         0       43s
revisor-697fb84f97   0         0         0       52s
revisor-99546b58f    0         0         0       9s
revisor-f6dd4cb4d    3         3         3       6s
```

Le changement se fait **dans la `kustomization.yaml`**, pas dans le cluster (et avant de l'appliquer, de nouveau `kubectl config current-context`). Ouvre le fichier et ajoute le service à la fin de la liste, séparé par une virgule :

```text
$ grep REVISOR_SERVICIOS kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
```

Avant d'appliquer, demande au cluster ce qui changerait. `kubectl diff -k .` compare ce que Kustomize assemblerait avec ce qui se trouve dans le cluster ; ici, on l'a filtré pour ne voir que les lignes qui comptent :

```text
$ kubectl diff -k . | grep -E '^[-+] .*(REVISOR_SERVICIOS|name: revisor-config)'
-              name: revisor-config-t6cm6872fk
+              name: revisor-config-7fbkh2926f
+  REVISOR_SERVICIOS: prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
+  name: revisor-config-7fbkh2926f
[código de salida: 1]
```

Lis-le ligne par ligne. Les deux premières appartiennent au **Deployment** : sa référence passe de `revisor-config-t6cm6872fk` à `revisor-config-7fbkh2926f`. Les deux dernières appartiennent à un **nouveau ConfigMap**, avec la nouvelle liste et le nouveau nom. Ces deux premières lignes sont le *rollout*, annoncé avant qu'il se produise : le modèle du Pod change. (Le code de sortie 1 vient de `kubectl diff`, qui signale ainsi qu'il a **bien** trouvé des différences. Ce n'est pas une erreur.)

Avec le même contenu, le même nom : ton `7fbkh2926f` doit être identique à celui-ci. Appliquer :

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

Un nouveau ConfigMap (`created`), le Secret sans changement (`unchanged` : le token n'a pas changé, ni son nom), un nouveau ReplicaSet, `revisor-769ff55c9c`, qui a pris les trois répliques à tour de rôle, et le tableau avec deux services. **Personne n'a eu à se souvenir de redémarrer quoi que ce soit.** C'est l'objectif 4 du cours : tu changes la liste, tu appliques avec `kubectl apply -k .` et le cluster fait le *rollout* tout seul, sans reconstruire l'image et sans que tu aies à te souvenir de redémarrer le Deployment. Rien ne surveille tes fichiers : sans l'`apply`, le cluster ne sait même pas que tu as changé la liste.

Et le retour en arrière, qui en 4.3 était impossible, est ici trivial. On a remis la `kustomization.yaml` à sa liste d'origine et on l'a appliquée :

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

`revisor-config-t6cm6872fk unchanged` : le ConfigMap de la liste d'origine **n'est jamais parti**. Kustomize a calculé le même nom pour le même contenu, le Deployment a de nouveau pointé vers lui et son modèle est redevenu identique à celui du ReplicaSet `revisor-f6dd4cb4d`. Chaque configuration a son propre objet, et chaque révision du Deployment pointe vers le sien.

Le prix de cela, tu l'as déjà vu en 4.5.5 : `revisor-config-7fbkh2926f` est resté dans le cluster, sans que personne ne l'utilise. Avec le temps, ils s'accumulent. C'est un petit prix (chacun pèse quelques octets) et on le paie en échange de la possibilité de revenir en arrière ; la manière de les nettoyer avec méthode fait partie de ce que la Leçon 10 laisse pour un cluster réel.

## L'erreur que tu vas voir

L'erreur de cette leçon apparaît précisément au moment où tu crois avoir terminé : le Secret existe, le montage est bien écrit, le chemin est correct… et le `revisor` ne démarre pas. On l'a provoquée exprès en retirant au Deployment la ligne `fsGroup` avec un `patch`, après avoir vérifié le contexte :

```text
$ kubectl patch deployment revisor --type=json -p='[{"op":"remove","path":"/spec/template/spec/securityContext/fsGroup"}]'
deployment.apps/revisor patched
```

(`--type=json` permet des opérations précises comme `remove`, sur un chemin exact de l'objet. C'est la façon de retirer **une** ligne sans réécrire le fichier.) Vingt-cinq secondes plus tard, on lit dans l'ordre habituel.

**Premièrement, l'état.**

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS   RESTARTS      AGE
revisor-7ffcfb7646-2lsmc   0/1     Error    2 (23s ago)   24s
revisor-7ffcfb7646-k4s2b   0/1     Error    2 (23s ago)   25s
revisor-7ffcfb7646-th42g   0/1     Error    2 (24s ago)   25s
```

`Error` et `RESTARTS 2` : le conteneur **a bien démarré**, et le programme s'est terminé en erreur ; le `kubelet` l'a redémarré et il s'est terminé de nouveau. C'est un état différent de ceux de la Leçon 2. Ce n'est pas `ImagePullBackOff` (l'image est là) ni `CreateContainerConfigError` (la configuration a pu être construite). C'est le programme qui plante. Quelques secondes plus tard, l'état passe à `CrashLoopBackOff` : la [documentation du cycle de vie d'un Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) explique que le `kubelet` redémarre avec une attente croissante (10 s, 20 s, 40 s…) jusqu'à un plafond de 300 s, et que `CrashLoopBackOff` est le nom de cette attente. `Error` et `CrashLoopBackOff` alternent : l'un signifie « il a planté », l'autre « j'attends avant de réessayer ».

**Deuxièmement, les `logs`**, parce que si le programme a démarré, le programme a quelque chose à dire :

```text
$ kubectl logs revisor-7ffcfb7646-2lsmc
revisor: leyendo el token de REVISOR_TOKEN_ARCHIVO: open /secretos/token: permission denied
```

Une ligne, et elle dit tout : le `revisor` est allé lire le fichier que lui indiquait `REVISOR_TOKEN_ARCHIVO`, le système d'exploitation lui a refusé la permission (`permission denied`), et le `revisor` a refusé de démarrer sans son token. Ce « refus » est une décision de son code, et c'est la bonne : un `revisor` qui démarrerait sans token laisserait `/api/estados` ouvert à n'importe qui.

Pourquoi n'a-t-il pas pu le lire ? Regarde sur le nœud, comme en 4.5.6, cette fois pour l'un des Pods qui échouent :

```text
$ docker exec curso-k8s-l4-worker2 ls -ln /var/lib/kubelet/pods/c26f312f-6841-4911-bea8-6f14513b4a11/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 0 33 Oct 21 13:28 token
```

Compare avec celui de 4.5.6, `-r--r----- 1 0 65532`. Les permissions sont les mêmes, `0440`, et le propriétaire aussi, `root`. Ce qui a changé, c'est le **groupe** : avec `fsGroup`, c'était le 65532 et le `revisor` le lisait parce qu'il en faisait partie ; sans `fsGroup`, c'est le `0`, celui de `root`. L'utilisateur 65532 n'est ni le propriétaire ni du groupe, et pour lui `0440` signifie « rien ».

**Troisièmement, `describe`**, pour confirmer qui parle :

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

Tout est `Normal` jusqu'à `Started`, trois fois (`x3`) : l'image était là, le conteneur a été créé et a démarré. Le seul `Warning` est `BackOff`, « j'attends avant de redémarrer le conteneur qui a échoué ». Les événements ne disent pas **pourquoi** il a échoué, parce que le cluster ne le sait pas : le programme a planté de lui-même. C'est pourquoi, quand le conteneur est arrivé à démarrer, les `logs` passent avant le `describe`. Dans la Leçon 2, avec `ImagePullBackOff`, c'était l'inverse : il n'y avait pas de programme pour parler, et la réponse se trouvait dans les événements.

**Et maintenant, ce que tu n'attendais pas :**

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   0/3     3            0           83s
```

`0/3`. **Il ne reste pas une seule réplique saine.** Dans l'Exercice 3 de la Leçon 2, une image cassée avait laissé le *rollout* bloqué avec le service intact : trois anciens Pods vivants et un nouveau en échec. Ici, les trois anciens Pods ne sont plus là. Qu'est-ce qui a changé, si la stratégie est la même (`maxSurge` 1, `maxUnavailable` 0) ?

La différence tient à **quand** le nouveau Pod échoue. Avec l'image cassée, le conteneur ne démarrait jamais, donc le Pod n'était jamais prêt et le Deployment ne retirait jamais un ancien Pod. Ici, le conteneur **démarre**, et vit quelques millisecondes avant de lire le token et de planter. Pour le Deployment, cela suffit. Sans une probe qui demande « peux-tu déjà servir ? », Kubernetes considère un conteneur comme prêt dès qu'il démarre. La [documentation des Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) définit quand un nouveau Pod compte comme disponible : quand il est prêt, sans qu'aucun de ses conteneurs ait planté, pendant au moins `minReadySeconds`, qui vaut **zéro** par défaut. Chaque nouveau Pod a été « prêt » un instant, le Deployment l'a compté et a retiré un ancien. Dans cette exécution, cela s'est produit trois fois, et les trois Pods restants ne fonctionnent pas. Jusqu'où avance le changement dépend du nombre de nouveaux Pods qui parviennent à compter comme prêts avant de planter : dans une répétition de cette même expérience, le *rollout* s'est arrêté à mi-chemin, avec deux anciens Pods sains et `AVAILABLE 2`, et `kubectl rollout status` a expiré avec `error: timed out waiting for the condition`. Ce qui ne change pas, c'est la cause. Et en aucun cas `kubectl rollout status` n'aurait dit `successfully rolled out` avec `AVAILABLE 0` : ce message exige que toutes les répliques soient disponibles. Le mal était déjà fait avant que la commande puisse avertir.

C'est la chose la plus importante de la section, et ce n'est pas un défaut de Kubernetes : **le cluster ne sait que ce que tu lui apprends à demander.** Un `revisor` qui démarre n'est pas un `revisor` qui peut servir. La Leçon 5 donne au Deployment une readiness probe, et avec elle cette même erreur laisse trois anciennes répliques vivantes, comme dans la Leçon 2.

**La sortie** est celle de toujours dans ce cours : le fichier est la vérité, et on l'applique de nouveau.

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

`apply -k` a rendu la ligne `fsGroup` et le modèle est redevenu celui d'avant le `patch`. Remarque que le *rollout* de retour s'est lui aussi fait à tour de rôle : cette fois, les nouveaux Pods lisent le token, restent vivants et le Deployment avance sur des Pods qui fonctionnent.

**L'ordre, pour un Pod qui démarre et plante :** l'état (`get pods` : `Error` ou `CrashLoopBackOff`, avec `RESTARTS` qui augmente), les `logs` (ce qu'a dit le programme avant de planter ; si le conteneur a déjà redémarré, `kubectl logs --previous` montre ceux de la tentative précédente) et, à la fin, le `describe`. Et avant de conclure que « rien de grave n'est arrivé », `kubectl get deployment` : combien de répliques restent **réellement** en train de servir.

## L'habitude de sécurité de la leçon : le Secret ne se versionne pas, se monte comme fichier et se marque immuable

Le tableau des habitudes du cours attribue à cette leçon trois règles sur le Secret. Tu les as toutes les trois déjà vues à l'œuvre ; les voici ensemble, avec ce que chacune protège.

**Il ne se versionne pas.** Le token vit dans `token.txt`, que `.gitignore` laisse hors du dépôt, et la `kustomization.yaml` dit seulement d'où le lire. Ce qui va dans Git, c'est la recette, jamais la valeur. C'est la réponse directe à la scène : un secret qui entre une fois dans Git reste dans l'historique pour toujours, même si tu le supprimes dans la version suivante, et la seule vraie réparation est de le changer.

**Il se monte comme fichier**, avec `defaultMode: 0440`, `readOnly: true` et `fsGroup` pour que seul le groupe du `revisor` le lise. Vivant dans un `tmpfs`, il ne touche pas le disque du nœud. Et il n'est pas hérité par d'autres processus ni n'apparaît dans une liste de variables.

**Il se marque immuable.** Avec `immutable: true`, le cluster refuse de changer le contenu du Secret :

```text
$ kubectl get secret -o name | grep revisor-token | xargs -I{} kubectl patch {} -p '{"data":{"token":"eA=="}}'
The Secret "revisor-token-bh266kt42m" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]
```

`eA==` est la lettre `x` en base64 : la tentative consistait à remplacer le token par une seule lettre. Le `kube-apiserver` l'a rejetée avant de l'enregistrer : « interdit : le champ est immuable quand `immutable` est posé ». La [documentation des Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) donne deux raisons de l'utiliser. La première, qu'il te protège des « mises à jour accidentelles (ou non voulues) qui pourraient provoquer des pannes d'applications ». La seconde concerne les performances : le `kubelet` n'a pas besoin de surveiller les Secrets immuables, et dans un cluster qui en compte des milliers, cela décharge le `kube-apiserver`. Et un avertissement qu'il faut connaître : la marque **n'a pas de retour**. « Une fois qu'un Secret ou un ConfigMap est marqué comme immuable, il n'est pas possible d'annuler ce changement ni de modifier le contenu de `data`. Tu peux seulement supprimer le Secret et le recréer ».

Alors comment change-t-on le token ? Avec **un autre** Secret. Et cela, avec Kustomize, tu l'as déjà : un nouveau token donne un nouveau *hash*, un nouveau nom, et le Deployment passe à monter le nouveau Secret par un *rollout*. Aucun Pod ne voit son fichier changer à mi-chemin ; chaque Pod naît avec un token et meurt avec lui. L'Exercice 2 le fait. Le générateur et la marque immuable sont faits l'un pour l'autre : le générateur ne veut jamais modifier un Secret, il en crée toujours un autre.

**Ce contre quoi il protège et ce contre quoi il ne protège pas.** Ces trois règles protègent le token **hors** du cluster (Git) et **sur le nœud** (mémoire, permissions). Elles ne le protègent pas **à l'intérieur** du `kube-apiserver` : quiconque a la permission de lire les Secrets, ou de créer des Pods dans l'espace de noms, le lit avec `base64 -d`, comme tu l'as fait en 4.6. Cela, ce sont les permissions (Leçon 7) et le chiffrement au repos d'un cluster réel (Leçon 10) qui le protègent.

## Ce qui se fait de travers

**Croire que base64 protège quelque chose.** C'est un encodage, pas un chiffrement. Un manifeste de Secret avec son `data` dans un dépôt, c'est le secret publié. Tu l'as vu en 4.6 : un `base64 -d`.

**Versionner le Secret « parce que, comme ça, le cluster se reconstruit tout seul ».** Ce qui se reconstruit, c'est ce qui est dans Git, et cela inclut celui qui n'aurait pas dû voir le token. Le token se génère ou se récupère dans un endroit conçu pour conserver des secrets (un gestionnaire de secrets, dans un cluster réel), et Git ne conserve que l'endroit d'où le tirer.

**Modifier un ConfigMap à la main et tenir pour acquis que le programme le sait.** Si le programme le lit comme variable, il ne s'en aperçoit pas tant que le Pod n'est pas recréé. Tu l'as mesuré en 4.3 : le ConfigMap annonçait deux services et le `revisor` continuait d'en rapporter un. La preuve qu'un changement est arrivé, c'est le comportement du programme, pas l'objet.

**Écrire dans le Deployment le nom avec *hash*.** `name: revisor-config-t6cm6872fk` écrit à la main cesse de servir au changement de liste suivant. On écrit le nom de base et Kustomize le traduit.

**Désactiver le *hash* pour que le nom soit propre.** `disableNameSuffixHash: true` existe, et il te ramène au problème de 4.3 : le changement de contenu ne change pas le modèle, et il n'y a pas de *rollout*. Tu le vérifieras dans l'Exercice 3.

**Donner le token par variable d'environnement « parce que c'est plus facile ».** Elle s'hérite, elle s'imprime sans le vouloir, et le `revisor` lui-même t'avertit dans son journal de ne pas le faire.

**Retirer `fsGroup`, ou mettre `defaultMode: 0444`, « pour qu'il puisse le lire ».** `fsGroup` est la bonne façon de faire lire le fichier au `revisor` **parce qu'il fait partie de son groupe**. Ouvrir le fichier à tous fonctionne, mais tu renonces à la permission minimale. Et si tu retires `fsGroup` sans comprendre, tu as vu ce que cela coûte.

**Croire qu'un *rollout* en cours protège ton service.** Sans probes, le Deployment compte comme prêt un Pod qui vient à peine de démarrer et retire un ancien Pod sain pour chaque nouveau, même si le nouveau plante en lisant sa configuration. Avant de tenir quelque chose pour bon, `kubectl get deployment` (que `AVAILABLE` égale les répliques désirées) et une vraie requête.

**Oublier que `apply` ne supprime pas.** Chaque changement avec des générateurs laisse derrière lui le ConfigMap ou le Secret précédent, et un ConfigMap écrit à la main que plus personne n'utilise reste lui aussi. Ils ne font pas de mal, mais un vieux Secret que personne n'utilise reste un Secret : un vieux token lisible. Les Secrets qui ne servent plus se suppriment.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre, à partir de l'état dans lequel il est resté à la fin de « L'habitude de sécurité », et depuis le dossier `programas/04-configuracion-secretos`. **Avant chaque exercice, `kubectl config current-context` doit afficher `kind-curso-k8s-l4` ; s'il affiche autre chose, ne continue pas.** `correr.sh` les exécute de la même façon, et sa sortie se trouve dans `correr.salida.txt`. **Avant** d'exécuter chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes propres mots.

### Exercice 1 — Une clé qui n'existe pas

Change, avec un `patch`, la clé que le Deployment cherche dans le ConfigMap, comme si tu t'étais trompé en l'écrivant (`REVISOR_SERVICIO`, sans le S final) :

```bash
kubectl patch deployment revisor --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key","value":"REVISOR_SERVICIO"}]'
```

Prédis : dans quel état le nouveau Pod reste-t-il ? Le conteneur démarre-t-il ? Combien d'anciennes répliques continuent de servir, et pourquoi le `0/3` de « L'erreur que tu vas voir » ne se répète-t-il pas cette fois ? Vérifie-le avec `kubectl get pods -l app=revisor` et avec les événements `Failed` du nouveau Pod. Pour t'en sortir, applique de nouveau la `kustomization.yaml`.

### Exercice 2 — Faire tourner le token (projet)

Quelqu'un a vu le token sur un écran partagé et il faut le changer. Avant de générer le nouveau, conserve l'ancien dans une variable de ton terminal, `VIEJO="$(cat token.txt)"`, pour pouvoir le tester ensuite. Génère le nouveau avec `(umask 077; openssl rand -hex 16 > token.txt)` et applique `kubectl apply -k .`. Avant d'appliquer, prédis : le Secret qui existait est-il modifié, ou en apparaît-il un autre ? Y a-t-il un *rollout* ? Que répond le `revisor` à une requête avec l'**ancien** token, et que répond-il à une requête avec le nouveau ? Vérifie-le avec `kubectl get secret -o name | grep revisor-token` et avec deux `curl` depuis `depurar`, l'un avec `-H "Authorization: Bearer $VIEJO"` et l'autre avec `-H "Authorization: Bearer $(cat token.txt)"`. Pour finir, explique ce que tu devrais faire du vieux Secret, et pourquoi.

### Exercice 3 — Sans le *hash*

Copie le dossier de la leçon ailleurs, ajoute à la fin de la copie de `kustomization.yaml` ces deux lignes et regarde le résultat avec `kubectl kustomize` (sans l'appliquer) :

```yaml
generatorOptions:
  disableNameSuffixHash: true
```

Prédis d'abord : comment vont s'appeler le ConfigMap et le Secret ? Vers quel nom le Deployment va-t-il pointer ? Ensuite, sans l'exécuter, réponds : si, avec cette option, tu changes la liste et tu appliques, y a-t-il un *rollout* ? Quelle partie de la leçon viens-tu de répéter ? Et, comme le Secret est immuable, que crois-tu qu'il se passerait en faisant tourner le token avec cette option ?

### Exercice 4 — Défends le fichier

Un collègue propose de passer le token avec `secretKeyRef`, comme variable d'environnement, « parce que c'est une ligne et pas un volume, et que le Secret est tout aussi secret dans les deux cas ». En cinq phrases au maximum, réponds-lui : en quoi il a raison, quel risque ajoute la variable que le fichier n'a pas, ce que dit le `revisor` lui-même quand il reçoit le token par variable, et ce qu'il faudrait ajouter au Deployment pour que le fichier puisse être lu sans l'ouvrir à tous.

## Solutions

### Solution 1

Mesuré dans `correr.salida.txt` :

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

Le nouveau Pod reste en **`CreateContainerConfigError`**, le même état que celui du `runAsNonRoot` de la Leçon 2 : le `kubelet` n'a pas pu construire la configuration du conteneur et **ne l'a pas démarré**. L'événement dit exactement ce qui a manqué : la clé `REVISOR_SERVICIO` dans le ConfigMap `default/revisor-config-t6cm6872fk`. C'est ce qu'annonçait `Optional: false` dans le `describe` de 4.2.

**Les trois anciennes répliques continuent de servir.** La différence avec le `0/3` du `fsGroup` tient au moment de l'échec. Ici, le conteneur n'a jamais démarré, donc le nouveau Pod n'a jamais été prêt, pas même un instant, et avec `maxUnavailable: 0` le Deployment n'a retiré aucun ancien Pod. Avec le `fsGroup`, le conteneur démarrait, était « prêt » quelques millisecondes et plantait, et cela a suffi au Deployment pour avancer. La leçon de fond : **une erreur qui empêche de démarrer est plus sûre qu'une qui démarre puis plante**, tant que tu n'as pas de probes.

En appliquant de nouveau la `kustomization.yaml`, le modèle est redevenu celui de `revisor-f6dd4cb4d` et le Pod cassé a disparu :

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           103s
```

### Solution 2

Mesuré dans `correr.salida.txt` :

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

`VIEJO` est une variable de ton terminal : le token n'est pas écrit dans ton historique, seulement le nom `$VIEJO`. (Ne le conserve pas dans un autre fichier, comme `token.viejo` : `.gitignore` n'exclut que `token.txt`.)

**Un autre Secret apparaît**, `revisor-token-ttgcdb7g7c` ; l'ancien n'est pas touché, et il ne pourrait pas l'être : il est immuable. Le nouveau token a changé le *hash*, le *hash* a changé le nom, le nom a changé le modèle du Deployment, et il y a eu un *rollout* (`deployment.apps/revisor configured`, et `rollout status` avec les mêmes tours qu'en 4.7). Le ConfigMap n'a pas changé (`unchanged`). À la fin, l'ancien token donne `401` et le nouveau `200` : les nouveaux Pods sont nés avec le nouveau fichier, et les anciens, qui connaissaient l'ancien token, n'existent plus.

**Le vieux Secret, il faut le supprimer** (`kubectl delete secret revisor-token-bh266kt42m`). Aucun Pod ne l'utilise, mais il reste dans le cluster, et quiconque a la permission de lire les Secrets peut en tirer, avec `base64 -d`, un token que quelqu'un a vu sur un écran. Si tu voulais pouvoir revenir à la révision précédente du Deployment, ce Secret devrait exister ; mais un token compromis est précisément celui que tu **ne** veux **pas** pouvoir réutiliser. Faire tourner un token ne se termine pas quand le nouveau fonctionne : cela se termine quand l'ancien ne sert plus nulle part.

### Solution 3

Mesuré dans `correr.salida.txt`, sur une copie dans un dossier temporaire :

```text
$ tail -2 $TEMPORAL/sin-hash/kustomization.yaml
generatorOptions:
  disableNameSuffixHash: true

$ kubectl kustomize $TEMPORAL/sin-hash | grep -E '^  name: revisor-(config|token)|name: revisor-(config|token)$'
  name: revisor-config
  name: revisor-token
              name: revisor-config
```

Le ConfigMap s'appelle `revisor-config` et le Secret `revisor-token`, tout court, et le Deployment pointe vers `revisor-config` (la troisième ligne, plus indentée, est son `configMapKeyRef`). Des noms propres, et **aucun *rollout*** quand la liste changera : le ConfigMap garde son nom, le modèle du Deployment ne change pas, et la règle du « si et seulement si » n'est pas remplie. Tu viens de répéter la section 4.3, seulement avec Kustomize : l'objet change et le `revisor` reste avec l'ancienne liste jusqu'à ce que quelqu'un se souvienne du `rollout restart`.

Avec le Secret, c'est pire, et cela a été mesuré. Le script a monté un dossier à part avec **seulement** le Secret, immuable et sans *hash*, dans un espace de noms jetable, `sin-hash`. Il l'a appliqué, a changé le token de cette copie et l'a appliqué de nouveau :

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

Comme le nom ne change plus, `apply -k` a tenté de **modifier** le Secret qui existait déjà, et le cluster a refusé avec le même `field is immutable` que dans « L'habitude de sécurité ». Pour faire tourner le token, tu devrais supprimer le Secret à la main avant d'appliquer, et pendant ce temps les Pods qui redémarreraient ne trouveraient pas leur token. Désactiver le *hash* et marquer comme immuable sont deux décisions qui se contredisent. Le *hash* est ce qui rend l'immuabilité praticable. (Supprimer l'espace de noms `sin-hash` a emporté ce Secret avec lui.)

### Solution 4

Une réponse possible : « Tu as raison de dire que le Secret conserve la même donnée dans les deux cas, et qu'il est tout aussi exposé dans `etcd`. Mais une variable est héritée par tout processus lancé par le conteneur et apparaît dans n'importe quel vidage de l'environnement ou journal qui imprime la configuration, alors qu'un fichier en lecture seule dans un `tmpfs` n'est pas copié dans chaque processus : il faut aller l'ouvrir exprès, et seul peut l'ouvrir celui qui en a la permission. Le `revisor` lui-même, s'il reçoit le token dans `REVISOR_TOKEN`, écrit dans son journal que quiconque a `docker inspect` peut le lire et qu'il faut utiliser `REVISOR_TOKEN_ARCHIVO`. Pour lire le fichier sans l'ouvrir à tous, le Deployment a besoin de `defaultMode: 0440` et de `fsGroup: 65532` dans le `securityContext` du Pod, ce qui fait du groupe du `revisor` le propriétaire du fichier. Cela fait trois lignes de plus que la variable, et elles les valent. »

## Supprimer le cluster

Quand tu as terminé les exercices, supprime le cluster de la leçon. Ne laisse rien de vivant sur la machine :

```text
$ kind delete cluster --name curso-k8s-l4
Deleting cluster "curso-k8s-l4" ...
Deleted nodes: ["curso-k8s-l4-control-plane" "curso-k8s-l4-worker2" "curso-k8s-l4-worker"]

$ kind get clusters | grep -c curso-k8s-l4
0
```

Le `--name` est obligatoire ici aussi : sans lui, kind supprimerait le cluster appelé `kind`, qui peut appartenir à une autre personne ou à un autre projet. Avec le cluster partent ses Secrets, ses ConfigMaps et la copie du token qui vivait dans le `tmpfs` de chaque nœud.

Il reste deux choses sur ta machine, et toutes les deux se suppriment :

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

Le `case` ne laisse passer qu'un chemin qui commence par `/tmp/curso-k8s-l4.` et se termine par `/kubeconfig`, la forme exacte de celui que tu as créé en 4.0 ; ensuite `dirname` lui retire le nom du fichier et `rm -rf` supprime ce dossier et rien d'autre. Si ton terminal pointe ailleurs (par exemple vers ton `~/.kube/config`, parce que tu as ouvert un autre terminal sans répéter le `export`), il ne supprime rien et te dit pourquoi. C'est la même protection qu'utilise `correr.sh` au nettoyage : un `rm -rf` que l'on peut copier-coller doit se protéger tout seul. Fermer ce terminal cesse aussi d'utiliser le `kubeconfig` temporaire. Le cluster de la leçon suivante se crée de zéro, comme celui-ci.

## Comment savoir que j'ai réussi

- [ ] Tu expliques, avec le tableau du `revisor` comme preuve, pourquoi modifier un ConfigMap à la main n'a pas changé la liste de services des Pods déjà en cours d'exécution.
- [ ] Tu lis dans `kubectl describe pod` de quel ConfigMap et de quelle clé provient chaque variable, et ce que signifie `Optional: false`.
- [ ] Tu écris de mémoire une `kustomization.yaml` avec `resources`, `configMapGenerator` (avec `literals`) et `secretGenerator` (avec `files: - token=token.txt`), et tu expliques ce que fait le `token=`.
- [ ] Tu prédis, avant d'appliquer, qu'un changement de liste produit un ConfigMap avec un autre nom et un nouveau ReplicaSet, et tu le vérifies avec `kubectl diff -k .`.
- [ ] Tu décodes un Secret avec `base64 -d` et tu expliques en deux phrases la différence entre encoder et chiffrer.
- [ ] Tu expliques ce que fait `fsGroup` avec le fichier du Secret, et tu reconnais dans les `logs` le `permission denied` dû à son absence.
- [ ] Tu expliques pourquoi l'erreur du `fsGroup` a laissé le Deployment à `0/3` et celle de la clé mal écrite non.
- [ ] Tu fais tourner le token avec un nouveau Secret et tu sais quoi faire de l'ancien.
- [ ] Tu exécutes `programas/04-configuracion-secretos/correr.sh > /tmp/mi-corrida-l4.txt 2>&1` et tu compares `/tmp/mi-corrida-l4.txt` avec `programas/04-configuracion-secretos/correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) sur ce qui ne change pas d'une exécution à l'autre : trois nœuds `Ready` en `v1.37.0` ; le tableau avec `prueba OK … 200` ; `<set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>` ; le tableau qui **ne** montre **pas** `lento` 30 s après le `patch` et le montre après le `rollout restart` ; `-rw-------` pour `token.txt` et `wc -c` à 33 ; `token.txt` dans `.gitignore` ; `revisor-config-t6cm6872fk` comme nom généré ; `immutable: true` ; `401` sans token, `{"error":"falta el token o no es válido"}` et le tableau avec token ; `-r--r----- 1 0 65532 33 … token` sur un `tmpfs` ; le token identique après `base64 -d` ; `revisor-config-7fbkh2926f` dans le `diff` et un nouveau ReplicaSet avec `lento` dans le tableau ; `permission denied` dans les `logs`, le fichier en `-r--r----- 1 0 0` et le Deployment à `0/3` sans `fsGroup` ; ``field is immutable when `immutable` is set`` ; `couldn't find key REVISOR_SERVICIO` ; deux Secrets après la rotation, `401` avec l'ancien et `200` avec le nouveau ; les noms sans suffixe de l'Exercice 3 et son `field is immutable` à la rotation ; et à la fin `sin diferencias con la kustomization`. Le token, le nom du Secret, les suffixes des Pods et des ReplicaSets, les IP, les `uid`, le nœud de chaque Pod, les âges, les temps du tableau et le nombre de répétitions de chaque ligne de `rollout status` changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l4`, il ne reste aucun `token.txt` dans le dossier de la leçon et aucun dossier `/tmp/curso-k8s-l4.*`.

## Résumé

Réponds sans regarder la leçon :

1. Qu'est-ce qu'un ConfigMap et que dit sa documentation sur le fait d'y conserver des données confidentielles ?
2. Pourquoi modifier un ConfigMap utilisé comme variable ne change-t-il pas ce que fait le `revisor` ? Donne les deux raisons : celle de Kubernetes et celle du programme.
3. Que fait `configMapKeyRef`, et pourquoi ce cours le préfère-t-il à `envFrom` ?
4. Qu'ajoute Kustomize au nom d'un ConfigMap généré, et comment cela transforme-t-il un changement de contenu en *rollout* ?
5. Pourquoi, en revenant à la liste d'origine en 4.7, le ConfigMap est-il sorti `unchanged` et non `created` ?
6. Quelle différence y a-t-il entre encoder et chiffrer ? Qu'est-ce que base64 ?
7. Qui peut lire un Secret dans un cluster, en plus de celui qui a la permission `get secrets` ?
8. Que fait `fsGroup` avec le fichier d'un Secret monté, et que s'est-il passé quand on l'a retiré ?
9. Pourquoi l'erreur du `fsGroup` a-t-elle laissé le service sans répliques alors que celle de la clé mal écrite non ?
10. Que ne peut-on pas faire avec un Secret immuable, et comment change-t-on alors son contenu ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « ConfigMaps »](https://kubernetes.io/docs/concepts/configuration/configmap/) : la définition ; qu'il n'offre ni secret ni chiffrement ; la limite de 1 MiB ; les quatre façons de l'utiliser depuis un Pod ; que les ConfigMaps montés comme fichier sont mis à jour « éventuellement » et que ceux utilisés comme variables « ne sont pas mis à jour automatiquement et nécessitent le redémarrage du Pod » ; et les ConfigMaps immuables.
- [Kubernetes, « Configure a Pod to Use a ConfigMap »](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/) : `configMapKeyRef`, `envFrom` et les références optionnelles.
- [Kubernetes, « Secrets »](https://kubernetes.io/docs/concepts/configuration/secret/) : la définition ; l'avertissement qu'ils sont conservés non chiffrés dans etcd et que celui qui peut créer un Pod peut lire les Secrets de son espace de noms ; la limite de 1 MiB ; la mise à jour « éventuellement cohérente » des volumes ; la copie dans un `tmpfs` sur le nœud ; et les Secrets immuables, leurs deux avantages et le fait que la marque ne peut pas être annulée.
- [Kubernetes, « Good practices for Kubernetes Secrets »](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) : le chiffrement au repos ; l'accès minimal ; que base64 n'est pas une méthode de chiffrement ; qu'un manifeste de Secret dans un dépôt expose le secret ; et que l'application ne doit pas consigner la donnée en clair.
- [Kubernetes, « Distribute Credentials Securely Using Secrets »](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) : `defaultMode` et sa valeur par défaut, `0644`.
- [Kubernetes, « Declarative Management of Kubernetes Objects Using Kustomize »](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) : Kustomize dans `kubectl` depuis la 1.14 ; `configMapGenerator` et `secretGenerator` ; le suffixe avec le *hash* du contenu et `generatorOptions` avec `disableNameSuffixHash`.
- [Kubernetes, « Configure a Security Context for a Pod or Container »](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) : `fsGroup` comme groupe supplémentaire des processus et comme propriétaire des volumes qui prennent en charge la gestion des propriétaires.
- [Kubernetes, « Deployments »](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) : `minReadySeconds` et quand un nouveau Pod compte comme disponible.
- [Kubernetes, « Pod Lifecycle »](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) : l'attente croissante entre les redémarrages (10 s, 20 s, 40 s… jusqu'à 300 s) et l'état `CrashLoopBackOff`.

---

**Suivante :** [Leçon 5 — Contrôles de santé, ressources et arrêt ordonné](05-salud-recursos-apagado.md)
