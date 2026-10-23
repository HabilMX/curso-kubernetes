# Leçon 5 — Contrôles de santé, ressources et arrêt ordonné

Jeudi, 18 h 40. Le service de test est en panne depuis dix minutes et le tableau de bord le dit très bien : `FALLA codigo 503`. C'est pour cela que le `revisor` existe. Mais à 18 h 42, le tableau de bord cesse de se charger. Tu demandes les Pods et tu vois quelque chose que tu n'attendais pas : les trois répliques du `revisor` affichent `RESTARTS 4`, `RESTARTS 5`, `RESTARTS 5`, et deux d'entre elles disent `CrashLoopBackOff`. Personne n'a touché au `revisor`. Ce que quelqu'un a touché, mardi, c'est son contrôle de santé (health check) : « pour qu'il soit plus complet », on lui a demandé d'interroger aussi le service de test. Maintenant le service de test est en panne, le contrôle du `revisor` échoue, le cluster conclut que le `revisor` est mort et le redémarre, encore et encore. L'outil qui devait te prévenir du problème est la première victime du problème. Et à 19 h 00, tu dois expliquer ce qui s'est passé.

Le cluster ne s'est pas trompé : il a fait exactement ce qu'on lui a dit. Cette leçon t'apprend à lui dire la bonne chose. Comment le cluster sait qu'un conteneur a démarré, qu'il peut recevoir du trafic et qu'il est toujours vivant, et pourquoi ces trois questions sont différentes. Combien de CPU et de mémoire revient à chaque conteneur, et ce qui se passe quand il en demande trop. Et ce que fait le `revisor` pendant les quelques secondes que le cluster lui accorde quand il lui demande de s'arrêter.

**Durée :** 2 × 45 min

**Ce que tu construis :** un `revisor` que le cluster sait surveiller : avec des probes de démarrage, de disponibilité et de vie, avec un plancher et un plafond de CPU et de mémoire, et avec un délai d'arrêt à sa mesure ; et le service de test avec sa propre probe et ses propres limites

**Ce que tu apprends :** ce que demande chaque probe (`startupProbe`, `readinessProbe`, `livenessProbe`), qui la lance et ce qui se passe quand elle échoue ; pourquoi `/salud` n'interroge personne ; ce que sont les `requests` et les `limits`, qui utilise chacun et dans quelles unités ils s'écrivent ; les classes de qualité de service (QoS) ; un `OOMKilled` et un `Pending` provoqués exprès et comment les lire ; et ce qui se passe entre `kubectl delete pod` et la disparition du Pod, avec `terminationGracePeriodSeconds`

**D'où tu viens.** De la [Leçon 4](04-configuracion-secretos.md) : le `revisor` et le service de test s'appliquent avec `kubectl apply -k .` ; la liste des services arrive depuis un `ConfigMap` généré et le token depuis un `Secret` monté comme fichier, et `/api/estados` demande `Authorization: Bearer …`. De la [Leçon 3](03-services-dns.md), tu apportes le Pod `depurar`, les EndpointSlices et leur colonne `ready`, que la section 3.4.3 avait laissée en suspens pour cette leçon. Et de la [Leçon 2](02-pods-deployments.md), le fait que le `kubelet` de chaque nœud est celui qui démarre les conteneurs.

**Ce que cette leçon ne fait pas.** Elle ne répartit pas les répliques entre les nœuds et ne fait pas non plus en sorte qu'une mise à jour ne perde aucune requête : c'est la [Leçon 9](09-escalar-y-actualizar.md), avec `preStop`, `PodDisruptionBudget` et la mise à l'échelle automatique, qui utilise les `requests` d'aujourd'hui pour calculer. Elle ne publie pas le `revisor` vers l'extérieur : c'est la [Leçon 6](06-entrar-al-cluster.md). Et elle ne pose pas de règles pour tout un espace de noms (un maximum par conteneur, un total par équipe) : elles sont nommées dans l'habitude de sécurité de la leçon et restent hors du cours.

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1 et l'image de nœud `kindest/node:v1.37.0` figée par son empreinte (digest), sur le cluster de trois nœuds de la Leçon 1, appelé ici `curso-k8s-l5`. La machine était un Mac à processeur ARM avec Docker Engine 29.2.1 dans une machine virtuelle Linux (Colima) avec 6 CPU et 16 GiB de mémoire, **pas** Linux Mint, qui est le système de référence du cours. Ce qui change sur ta Mint : l'architecture (`amd64` au lieu de `arm64`) ; le CPU et la mémoire que chaque nœud dit avoir, qui dans kind sont ceux de ta machine (5.6 l'explique), et avec eux les pourcentages de `describe node` ; les adresses IP, les suffixes aléatoires des noms, les âges, le nœud où atterrit chaque réplique, l'heure du journal et la mémoire exacte qu'utilise le `revisor`. Les commandes sont les mêmes. Le parcours complet se trouve dans [`programas/05-salud-recursos-apagado/`](../programas/05-salud-recursos-apagado) : `correr.sh` crée le cluster, y charge les images, remet tout comme l'a laissé la Leçon 4, parcourt la leçon dans l'ordre, exécute les Exercices 1 à 3 et supprime le cluster. L'exécution complète a duré 4 minutes et 48 secondes, et le script note ce qu'a pris chaque étape longue : créer le cluster et attendre qu'il soit prêt, 34 secondes ; le supprimer, 1. Sa sortie est `correr.salida.txt`. Là-bas, la capacité des nœuds (5.6) et l'erreur volontaire apparaissent avant l'arrêt (5.7), et l'habitude de sécurité avant les exercices, parce que le script les exécute dans cet ordre. Il n'utilise aucun port de ta machine.

## À la fin, tu seras capable de

- Expliquer avec un exemple la différence entre « a démarré », « est prêt » et « est vivant », et dire quelle probe pose chaque question et ce que fait le cluster quand la réponse est « non ».
- Écrire les trois probes du `revisor` et calculer, avec leurs chiffres, combien de temps met le cluster à réagir à chaque défaillance.
- Justifier pourquoi la liveness probe ne doit pas interroger d'autres services, et le démontrer avec le service de test en panne.
- Écrire des `requests` et des `limits` en millicores et en mébioctets (Mi), et dire qui utilise chacun : l'ordonnanceur (scheduler), le `kubelet` ou le noyau Linux.
- Provoquer un `OOMKilled` et un `Pending`, les lire avec `kubectl get`, `describe` et les événements, et les corriger.
- Mesurer combien de temps met un Pod à s'arrêter et expliquer le rôle de SIGTERM, de SIGKILL et de `terminationGracePeriodSeconds`.

## Le pourquoi avant le comment

Jusqu'à aujourd'hui, le cluster ne sait qu'une chose de tes conteneurs : si le processus tourne. Si le processus meurt, le `kubelet` le redémarre ; tu l'as vu dans la Leçon 2. Mais un processus peut tourner sans rien servir. Il peut être encore en train de démarrer, sans écouter sur son port. Il peut être bloqué dans un verrou, vivant pour le système d'exploitation et mort pour ses clients. Il peut être en bonne santé et pourtant ne pas vouloir de trafic pour un moment. Pour le cluster, aujourd'hui, les trois cas sont identiques : `Running`. Et le Service de la Leçon 3 envoie du trafic aux trois.

La première question de la leçon est donc : **comment un conteneur raconte-t-il au cluster comment il va ?** La réponse, ce sont les **probes** (*sondes*) : des questions que le `kubelet` pose au conteneur à intervalles réguliers. Il y en a trois, parce qu'il y a trois questions différentes, et chaque réponse négative a une conséquence différente : attendre, cesser de lui envoyer du trafic ou le redémarrer. Les confondre, c'est la scène du jeudi.

La deuxième question est : **combien revient à chacun ?** Aujourd'hui, le `revisor` ne dit pas de combien de CPU ni de mémoire il a besoin, et le cluster le place n'importe où, sans compter. Un conteneur sans plafond peut avaler la mémoire d'un nœud entier et entraîner tous ses voisins avec lui. Les **`requests`** disent ce dont il a besoin pour que l'ordonnanceur lui trouve une place ; les **`limits`** disent jusqu'où il peut aller.

La troisième est : **comment s'en va-t-il ?** Chaque fois que tu supprimes un Pod, que tu fais un *rollout* ou que le cluster déplace quelque chose, un conteneur reçoit l'ordre de s'arrêter. S'il l'écoute, il termine ce qu'il était en train de faire et il sort. Sinon, le cluster attend un délai et le tue. Ce délai s'écrit dans le manifeste.

La leçon comporte sept parties de concepts, puis les sections habituelles :

1. **Le cluster de la leçon et ce qu'il sait aujourd'hui** (5.1).
2. **Les manifestes de la leçon** (5.2), champ par champ.
3. **Les trois probes** (5.3) : ce que demande chacune et quand elle réagit.
4. **Les probes en marche** (5.4) : appliquer, regarder et les lire dans le journal.
5. **Pourquoi `/salud` n'interroge personne** (5.5) : la scène du jeudi, à l'envers.
6. **`requests`, `limits` et la capacité des nœuds** (5.6).
7. **L'arrêt ordonné** (5.7).

Voici la destination. À la fin de 5.4, chaque réplique du `revisor` a ses trois probes, son plancher et son plafond, et un délai d'arrêt de 10 secondes :

```text
$ kubectl describe pod revisor-578c8dc8d9-g9lhl | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests|cpu:|memory:'
Name:             revisor-578c8dc8d9-g9lhl
    Limits:
      cpu:     200m
      memory:  64Mi
    Requests:
      cpu:      50m
      memory:   32Mi
    Liveness:   http-get http://:http/salud delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
    Readiness:  http-get http://:http/salud delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=2
    Startup:    http-get http://:http/salud delay=0s timeout=1s period=1s successThreshold=1 failureThreshold=10
QoS Class:                   Burstable
```

## Si tu n'as pas les images du cours de Docker

Cette leçon utilise les deux mêmes images que la Leçon 3 : `curso-docker-revisor:1.6.0` et `curso-docker-prueba:1.0.0`. Vérifie que tu les as :

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Pour l'autre, la même commande avec `curso-docker-prueba:1.0.0`. S'il t'en manque une, la [Leçon 3](03-services-dns.md) explique, dans cette même section, comment construire chacune à partir du dépôt du cours de Docker. Ce que cette leçon demande **en plus** aux deux images, et qu'il vaut la peine de lire parce que chaque point explique une ligne des manifestes :

- **Le `revisor` répond à `GET /salud` sans interroger personne** : il renvoie `{"estado":"vivo","version":"1.6.0"}` avec le code 200 dès qu'il écoute. Les trois probes interrogent ce point.
- **Le `revisor` gère SIGTERM** : en le recevant, il écrit `revisor: recibí terminated, apagando`, termine les requêtes en cours avec un délai propre de 5 secondes et écrit `revisor: apagado limpio`.
- **Le service de test répond toujours à `GET /modo`**, quel que soit le mode, tant que le processus vit. `GET /` est celui qui répond 503 en mode `caido`. Cette différence décide où sa probe interroge.

L'image de `curl` du Pod `depurar` reste publique et figée par son empreinte (digest) ; chaque nœud la télécharge depuis internet la première fois.

## Les concepts

### 5.1 Le cluster de la leçon et ce qu'il sait aujourd'hui

#### 5.1.1 Créer le cluster

Cette leçon utilise son propre cluster, `curso-k8s-l5`, avec la configuration à trois nœuds de la Leçon 1. Crée-le ainsi, depuis la racine du dépôt du cours, avec le même soin que d'habitude :

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L5_TMP="$(mktemp -d /tmp/curso-k8s-l5.XXXX)"
export KUBECONFIG="$L5_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: la segunda terminal de 5.7 la necesita
# curso-k8s-l5 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l5 --config programas/05-salud-recursos-apagado/kind-curso.yaml
# Debe decir kind-curso-k8s-l5. Si dice otra cosa, no sigas.
kubectl config current-context
kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l5
```

Le `export` ne vaut que dans ce terminal. C'est pourquoi le dossier temporaire est gardé dans une variable, `L5_TMP`, et le `echo` t'affiche le chemin complet : si tu ouvres un autre terminal (en 5.7 tu en auras besoin d'un second), tu y répètes le `export` avec **ce** chemin, sinon `kubectl` parlera à un autre cluster. Et à la fin de la leçon, la même variable te permet de supprimer le dossier sans écrire le chemin à l'œil. Et la règle des leçons précédentes tient toujours : **avant chaque** `apply`, `delete`, `patch` ou `exec` de cette leçon, `kubectl config current-context` doit dire `kind-curso-k8s-l5`. Le script le vérifie tout seul avant chaque `kubectl` et s'arrête si le contexte ne correspond pas.

Les sorties de cette section viennent de l'exécution de `correr.sh`, qui fait exactement cela :

```text
$ kubectl config current-context
kind-curso-k8s-l5

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l5-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l5-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l5-worker2         Ready    <none>          15s   v1.37.0
```

`kind load` affiche six lignes `not yet present on node …, loading...`, deux images par trois nœuds, comme dans la Leçon 3.

#### 5.1.2 Le point de départ : ce qu'a laissé la Leçon 4

Le dossier `programas/05-salud-recursos-apagado/punto-de-partida/` apporte, sans changer une virgule, les manifestes avec lesquels s'est terminée la Leçon 4 : son `kustomization.yaml`, les deux Deployments et les deux Services. Comme dans cette leçon, le token n'est pas versionné : il est généré à chaque exécution. Cette fois, on le copie dans les deux dossiers, celui du point de départ et celui de la leçon, pour que les deux génèrent **le même** Secret :

```bash
cd programas/05-salud-recursos-apagado
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
ls -l punto-de-partida/token.txt token.txt  # los dos: -rw-------
TOKEN="$(cat token.txt)"
```

```text
$ ls -l punto-de-partida/token.txt token.txt | cut -d' ' -f1
-rw-------
-rw-------

$ wc -c < punto-de-partida/token.txt
      33

$ kubectl apply -k punto-de-partida
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-hct4cckkgd created
service/prueba created
service/revisor created
deployment.apps/prueba created
deployment.apps/revisor created
```

Trente-deux caractères hexadécimaux et un saut de ligne : 33 octets. Comme dans la Leçon 4, les parenthèses et le `umask 077` font naître le fichier avec la permission `0600` (`-rw-------`), lisible par toi seul, au lieu du `0644` que laisserait ton masque habituel ; `cp` sans `-p` ne copie pas les permissions de l'original : il crée le nouveau fichier avec le mode de l'original filtré par ton `umask`. Comme `0600` n'a déjà aucune permission pour le groupe ni pour les autres, le masque n'y ajoute rien et la copie reste elle aussi en `0600` ; avec un fichier `0664` ou `0755`, le résultat dépendrait de ton `umask`, et `cp -p` est l'option qui conserve mode, propriétaire et dates. La première ligne du bloc est la vérification du contexte écrite comme une commande : si le contexte n'est pas celui de la leçon, elle affiche « contexto equivocado » et ne continue pas. Utilise-la avant chaque changement ; le script le fait tout seul. Le nom du ConfigMap est le même que dans la Leçon 4, `revisor-config-t6cm6872fk`, parce que la liste des services n'a pas changé. Celui du Secret est différent à chaque exécution, parce que le token est nouveau.

#### 5.1.3 Ce que le cluster sait aujourd'hui

```text
$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6f4dfdb898-8p5j2   1/1     Running   0          4s
revisor-f65c6dd96-248bg   1/1     Running   0          4s
revisor-f65c6dd96-575nn   1/1     Running   0          4s
revisor-f65c6dd96-pzxpk   1/1     Running   0          4s
```

Regarde la colonne `READY` : `1/1` à **4 secondes**. Le `revisor` écoutait-il déjà sur son port à cet âge ? Sûrement, parce qu'il démarre vite. Mais le cluster ne l'a pas vérifié : il a marqué le Pod comme prêt dès que le conteneur a démarré. C'est ce que la Leçon 3 annonçait en 3.4.3 : sans probes, « prêt » veut dire « le processus existe ». Si le `revisor` mettait dix secondes à ouvrir son port, le Service lui enverrait du trafic pendant ces dix secondes, et ces requêtes échoueraient.

Maintenant, ce que le Pod dit de lui-même :

```text
$ kubectl describe pod revisor-f65c6dd96-248bg | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests'
Name:             revisor-f65c6dd96-248bg
QoS Class:                   BestEffort

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
30

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
PodReadyToStartContainers=True Initialized=True Ready=True ContainersReady=True PodScheduled=True 
```

Le `grep` a cherché des probes, `Limits` et `Requests`, et n'en a trouvé aucun : seulement le nom et une ligne, `QoS Class: BestEffort`. C'est la classe de qualité de service du Pod, et `BestEffort` (« au mieux ») est celle que reçoit un Pod qui ne déclare rien de CPU ni de mémoire. 5.6 explique ce que cela signifie ; en avant-première : c'est le premier que le nœud expulse quand il manque de mémoire. Le délai d'arrêt est de `30` secondes, la valeur par défaut, que personne n'a choisie. Et les conditions du Pod disent `Ready=True` : c'est la condition que l'EndpointSlice copie dans sa colonne `ready`, et aujourd'hui elle est devenue vraie sans que personne ne pose de question.

Trois trous : personne ne vérifie que le `revisor` sert, personne ne dit de quoi il a besoin, et le délai d'arrêt est un nombre hérité. Les trois se referment avec les manifestes de cette leçon.

### 5.2 Les manifestes de la leçon

La leçon change deux fichiers : les Deployments du `revisor` et du service de test. Le `kustomization.yaml`, les deux Services et `depurar.yaml` sont les mêmes que dans la Leçon 4 (le commentaire de la première ligne du `kustomization.yaml` dit maintenant « Lecciones 4 y 5 »). Les deux Deployments sont des **programmes** : ils s'appliquent avec `kubectl apply -k .` depuis `programas/05-salud-recursos-apagado/`.

#### 5.2.1 Le `revisor`

```yaml
# revisor-deployment.yaml — Lección 5: sondas, recursos y apagado ordenado.
# /salud no consulta a nadie: si dependiera de «prueba», una caída de prueba
# reiniciaría el revisor, que no tiene la culpa.
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
      terminationGracePeriodSeconds: 10
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
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
          limits:
            cpu: 200m
            memory: 64Mi
        startupProbe:
          httpGet: {path: /salud, port: http}
          periodSeconds: 1
          failureThreshold: 10
        readinessProbe:
          httpGet: {path: /salud, port: http}
          periodSeconds: 5
          failureThreshold: 2
        livenessProbe:
          httpGet: {path: /salud, port: http}
          periodSeconds: 10
          failureThreshold: 3
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

Tout ce qui n'est pas nouveau, tu l'as déjà lu dans les Leçons 2 à 4. Le nouveau, ce sont trois blocs et un nombre :

- **`terminationGracePeriodSeconds: 10`**, dans le modèle (template) du Pod (pas dans le conteneur) : combien de secondes le Pod a pour s'arrêter de lui-même avant que le cluster ne le tue. 5.7.
- **`resources`**, dans le conteneur : le plancher (`requests`) et le plafond (`limits`) de CPU et de mémoire. 5.6.
- **`startupProbe`, `readinessProbe` et `livenessProbe`**, dans le conteneur : les trois probes. 5.3.

Remarque le `port: http` des trois probes. C'est la même astuce que dans la Leçon 3 avec le `targetPort` du Service : le port est désigné par son **nom**, donc le nombre `8080` continue de vivre à un seul endroit, `containerPort`. Et `{path: /salud, port: http}` est du YAML sur une ligne : les accolades regroupent les deux champs de `httpGet` exactement comme si tu les écrivais sur deux lignes en retrait. On les écrit ainsi parce que les trois probes partagent la même question et que ce qui change entre elles, ce sont les nombres.

#### 5.2.2 Le service de test

```yaml
# prueba-deployment.yaml — Lección 5: el servicio de prueba también se vigila
# y tiene sus límites. La sonda de vida usa GET /modo y NO GET /: en modo «caido»
# GET / responde 503 a propósito, y el clúster no debe matarlo por eso.
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
      terminationGracePeriodSeconds: 10
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
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
        livenessProbe:
          httpGet: {path: /modo, port: http}
          periodSeconds: 10
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Une seule probe, celle de vie (liveness), et elle pointe vers `/modo`, **pas** vers `/`. Le commentaire du fichier le dit et 5.5 le démontre : `GET /` est justement ce que le service de test casse exprès en mode `caido`. Si la liveness probe interrogeait là, le cluster le redémarrerait chaque fois que tu le mets dans ce mode, ce qui est le contraire de ce que tu attends d'un service qui existe pour échouer. Il n'a pas de startup probe parce qu'il démarre en quelques millisecondes, ni de readiness probe parce que le cours veut que le `revisor` puisse lui parler même quand il est en panne ; l'Exercice 1 t'apprend ce qui se passerait avec elle.

Les ressources sont plus petites que celles du `revisor` parce qu'il en fait moins : il n'interroge personne et ne garde pas de rapports.

### 5.3 Les trois probes

#### 5.3.1 Qui demande, et comment

La [documentation des probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/) commence ainsi : une probe est « un diagnostic que le `kubelet` effectue périodiquement sur un conteneur », et grâce à ses résultats « Kubernetes peut redémarrer les conteneurs défaillants ou cesser d'envoyer du trafic aux conteneurs qui ne sont pas prêts ». Retiens les deux éléments : **le `kubelet`**, celui du nœud où tourne le Pod, pas le plan de contrôle ; et **deux réactions différentes**, redémarrer ou cesser d'envoyer du trafic.

Les trois probes du `revisor` utilisent `httpGet` : le `kubelet` fait une requête HTTP vers l'IP du Pod, au port et au chemin que tu lui indiques. Le [guide de configuration des probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) dit quand cela compte comme un succès : « tout code supérieur ou égal à 200 et inférieur à 400 indique un succès. Tout autre code indique un échec ». Une réponse qui n'arrive pas à temps est aussi un échec. Il existe d'autres façons de poser la question (exécuter une commande dans le conteneur, ouvrir une connexion TCP ou un appel gRPC), mais pour un serveur HTTP qui a déjà sa route de contrôle de santé (health check), la requête HTTP est celle qui pose la question qui compte : non pas « le processus existe-t-il ? », mais « répond-il ? ». Et le `revisor` n'a pas de *shell* pour exécuter des commandes à l'intérieur, comme tu l'as vu dans la Leçon 2.

#### 5.3.2 Les nombres d'une probe

Chaque probe se règle avec cinq champs. Les valeurs par défaut viennent de la même documentation des probes :

| Champ | Ce que c'est | Par défaut |
|---|---|---|
| `initialDelaySeconds` | combien attendre avant la première question | 0 s |
| `periodSeconds` | à quelle fréquence interroger | 10 s (minimum 1) |
| `timeoutSeconds` | combien attendre une réponse | 1 s |
| `successThreshold` | combien de succès d'affilée, après un échec, pour revenir à « bien » | 1 (pour liveness et startup, **doit** être 1) |
| `failureThreshold` | combien d'échecs d'affilée pour conclure « mal » | 3 |

La règle pour les lire : **une probe réagit après `failureThreshold` échecs d'affilée, séparés par `periodSeconds`**. Un échec isolé ne fait rien. Cela évite qu'un faux pas d'une seconde déclenche un redémarrage. La documentation le dit en ces termes : une fois qu'une probe a échoué `failureThreshold` fois de suite, « Kubernetes considère que la vérification complète a échoué ».

#### 5.3.3 La startup probe : « as-tu fini de démarrer ? »

La documentation des probes : celles de démarrage « vérifient si l'application à l'intérieur d'un conteneur a démarré. Si une startup probe est définie, Kubernetes n'exécute ni les liveness ni les readiness probes tant que la startup probe n'a pas réussi ». Et si elle échoue pour de bon, « le `kubelet` tue le conteneur », qui est alors soumis à sa politique de redémarrage.

Celle du `revisor` : `periodSeconds: 1` et `failureThreshold: 10`. Elle interroge chaque seconde et laisse au programme jusqu'à **10 tentatives**, environ 10 secondes, pour répondre la première fois (1 × 10). C'est le calcul quand chaque tentative échoue immédiatement ; si le programme est bloqué et que chaque tentative doit épuiser son `timeoutSeconds` (1 seconde par défaut), le délai approche 20. Dès qu'il répond, elle cesse d'interroger tant que ce conteneur vit ; si le conteneur redémarre, elle recommence. Contrairement aux deux autres, elle ne tourne qu'au démarrage. Pourquoi 10 secondes si le `revisor` démarre en moins d'une ? Parce que ce nombre n'est pas pour le bon jour, il est pour le mauvais : un nœud chargé, une image lue lentement. Et il en reste peu : un programme qui ne répond pas en 10 secondes a un problème.

Le guide de configuration des probes explique pourquoi cette probe existe. Certains programmes sont longs à démarrer, et si la liveness probe devait les attendre, il faudrait la rendre lente et elle cesserait de détecter à temps un blocage. La solution est de séparer : une startup probe avec un `failureThreshold * periodSeconds` « assez long pour couvrir le pire cas de démarrage », et une fois qu'elle a réussi, « la liveness probe prend le relais ». Son exemple est un programme qui dispose de 5 minutes au maximum pour démarrer (30 × 10 s). Le `revisor` a besoin de beaucoup moins, mais le schéma est le même.

#### 5.3.4 La readiness probe : « t'envoie-t-on du trafic ? »

La documentation : les readiness probes « déterminent quand un conteneur est prêt à accepter du trafic », et si l'une échoue, « le contrôleur d'EndpointSlices retire l'IP du Pod des EndpointSlices de tous les Services qui correspondent au Pod ». C'est la colonne `ready` de la Leçon 3, enfin avec du contenu. Une nuance que tu verras dans l'Exercice 1 : en pratique, l'adresse ne disparaît pas de l'EndpointSlice, elle reste avec `ready=false`, et cela suffit pour que `kube-proxy` cesse de lui envoyer du trafic. « Retirer du trafic » est l'effet ; « marquer comme non prête » est le mécanisme. Et une chose qui la distingue de la startup probe : « les readiness probes s'exécutent sur le conteneur pendant tout son cycle de vie ».

Le plus important, c'est ce qu'elle **ne** fait **pas** : elle ne redémarre rien. La documentation des probes, dans la description de `failureThreshold` : avec une readiness probe en échec, « le `kubelet` continue d'exécuter le conteneur qui a échoué et continue de lancer d'autres probes », et il met seulement la condition `Ready` du Pod à `false`. Quand la probe repasse, le Pod revient dans la liste. C'est la probe du « je vais bien, mais pas maintenant ».

Celle du `revisor` : toutes les 5 secondes, et 2 échecs d'affilée le sortent du Service. Au pire, un `revisor` qui cesse de répondre continue de recevoir du trafic pendant environ **10 secondes** (2 × 5) avant de sortir de la liste.

#### 5.3.5 La liveness probe : « es-tu toujours vivant ? »

La documentation : les liveness probes « déterminent quand redémarrer un conteneur ». L'exemple qu'elle donne est un blocage (*deadlock*), « où une application tourne mais ne peut pas progresser ». Si le conteneur échoue plus de fois que ce qui est toléré, « le `kubelet` redémarre ce conteneur ».

C'est la seule des trois qui détruit quelque chose : un redémarrage coupe les connexions ouvertes et l'état en mémoire. C'est pourquoi la même page l'accompagne d'un avertissement, qui est la scène du jeudi en langage de manuel : les liveness probes « doivent être configurées avec soin pour s'assurer qu'elles indiquent vraiment une défaillance irrécupérable de l'application », et « une mise en œuvre incorrecte des liveness probes peut provoquer des défaillances en cascade ».

Celle du `revisor` : toutes les 10 secondes, et 3 échecs d'affilée le redémarrent. Un `revisor` bloqué est redémarré en environ **30 secondes** (3 × 10). Plus lente que la readiness probe, exprès : la documentation décrit ce schéma comme le courant, la même route peu coûteuse pour les deux et un `failureThreshold` plus grand pour la liveness, afin que le Pod apparaisse « non prêt » un moment avant d'être tué. Ainsi, un faux pas passager sort le Pod du trafic (ce qui est bon marché) bien avant de le redémarrer (ce qui est coûteux).

#### 5.3.6 Les trois ensemble

| Probe | Question | Si la réponse est « non » | Quand elle s'exécute | Dans le `revisor` |
|---|---|---|---|---|
| startup | as-tu fini de démarrer ? | attend ; si le délai est écoulé, redémarre | seulement au démarrage | jusqu'à 10 s (1 s × 10) |
| readiness | t'envoie-t-on du trafic ? | te sort du Service ; **ne** redémarre **pas** | toujours | sort en ~10 s (5 s × 2) |
| liveness | es-tu toujours vivant ? | **redémarre** le conteneur | toujours, après la startup probe | redémarre en ~30 s (10 s × 3) |

Les trois probes du `revisor` posent la même question, `GET /salud`. Ce n'est pas de la redondance : c'est la même question avec trois conséquences et trois patiences différentes.

### 5.4 Les probes en marche

#### 5.4.1 Avant d'appliquer, regarder ce qui change

On vérifie d'abord que les deux dossiers ont le même token, puis on demande au cluster ce qui changerait :

```text
$ diff punto-de-partida/token.txt token.txt && echo 'mismo token'
mismo token

$ kubectl diff -k . | grep -E '^\+ ' | grep -vE 'generation|resourceVersion|uid:|creationTimestamp'
+        livenessProbe:
+          failureThreshold: 3
+          httpGet:
+            path: /modo
+            port: http
+            scheme: HTTP
+          periodSeconds: 10
+          successThreshold: 1
+          timeoutSeconds: 1
+        resources:
+          limits:
+            cpu: 100m
+            memory: 32Mi
+          requests:
+            cpu: 10m
+            memory: 16Mi
+      terminationGracePeriodSeconds: 10
+        livenessProbe:
+          failureThreshold: 3
+          httpGet:
+            path: /salud
+            port: http
+            scheme: HTTP
+          periodSeconds: 10
+          successThreshold: 1
+          timeoutSeconds: 1
+        readinessProbe:
+          failureThreshold: 2
+          httpGet:
+            path: /salud
+            port: http
+            scheme: HTTP
+          periodSeconds: 5
+          successThreshold: 1
+          timeoutSeconds: 1
+        resources:
+          limits:
+            cpu: 200m
+            memory: 64Mi
+          requests:
+            cpu: 50m
+            memory: 32Mi
+        startupProbe:
+          failureThreshold: 10
+          httpGet:
+            path: /salud
+            port: http
+            scheme: HTTP
+          periodSeconds: 1
+          successThreshold: 1
+          timeoutSeconds: 1
+      terminationGracePeriodSeconds: 10
[código de salida: 1]
```

`kubectl diff -k .` compare ce que tu appliquerais avec ce qui existe ; les deux `grep` ne gardent que les lignes **ajoutées** (elles commencent par `+ `) et retirent celles qui changent toujours. Le Deployment de test vient d'abord, puis celui du `revisor`. Remarque trois choses. Aucun ConfigMap ni Secret n'apparaît : le token est le même et la liste aussi, donc leurs noms avec *hash* ne changent pas. Les champs que tu n'as pas écrits (`scheme: HTTP`, `successThreshold: 1`, `timeoutSeconds: 1`) apparaissent avec leur valeur par défaut, celle du tableau de 5.3.2 : c'est ainsi que l'on voit ce qui va réellement tourner. Et le code de sortie 1 n'est pas une erreur : `kubectl diff` sort avec 1 quand il **y a** des différences, et avec 0 quand il n'y en a pas. À la fin de la leçon, tu t'en serviras à l'envers, pour vérifier qu'il n'en reste aucune.

À propos de cette dernière ligne, `[código de salida: 1]` : ce n'est pas `kubectl` qui l'écrit, c'est le script chaque fois qu'une commande sort avec un code différent de 0, et tu la verras dans d'autres blocs de la leçon. Le script tourne avec `set -o pipefail`, donc le code d'un pipeline est celui de la première commande qui échoue, ici `kubectl diff`. Dans ton terminal, sans cette option, `echo $?` te donnerait le code du dernier `grep`, qui est 0. Pour le vérifier sans pipeline : `kubectl diff -k . >/dev/null; echo $?`, qui donne `1`.

#### 5.4.2 Appliquer

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hct4cckkgd unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba configured
deployment.apps/revisor configured

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-g9lhl   1/1     Running   0          11s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          9s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          12s
```

Seuls les deux Deployments changent, et modifier le modèle (template) d'un Pod est un *rollout* : un nouveau ReplicaSet (`revisor-578c8dc8d9`) qui remplace les répliques une par une. Les âges le racontent : 12, 11 et 9 secondes, une ou deux secondes d'écart entre l'une et l'autre. Et cette fois, le remplacement a attendu que chaque nouvelle réplique passe sa readiness probe avant de retirer une ancienne : un Deployment ne compte comme « disponible » qu'un Pod prêt. Sans probes, « prêt » arrivait avant de rien savoir.

Le `describe` de l'une des nouvelles répliques est la destination que tu as vue au début :

```text
$ kubectl describe pod revisor-578c8dc8d9-g9lhl | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests|cpu:|memory:'
Name:             revisor-578c8dc8d9-g9lhl
    Limits:
      cpu:     200m
      memory:  64Mi
    Requests:
      cpu:      50m
      memory:   32Mi
    Liveness:   http-get http://:http/salud delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
    Readiness:  http-get http://:http/salud delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=2
    Startup:    http-get http://:http/salud delay=0s timeout=1s period=1s successThreshold=1 failureThreshold=10
QoS Class:                   Burstable

$ kubectl get pod revisor-578c8dc8d9-g9lhl -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
10
```

Voici comment lire une probe dans `describe` : `http-get http://:http/salud` veut dire « requête HTTP vers l'IP du Pod (elle est vide, entre `//` et `:`), au port nommé `http`, chemin `/salud` » ; viennent ensuite les cinq nombres de 5.3.2, avec `delay` à la place de `initialDelaySeconds` et `period` à la place de `periodSeconds`. La classe est passée de `BestEffort` à `Burstable`, et le délai d'arrêt de 30 à 10.

#### 5.4.3 Lire les probes dans le journal

Chaque probe est une vraie requête HTTP, et le `revisor` écrit une ligne pour chaque requête qu'il traite. Son journal, avec l'heure de chaque ligne :

```text
$ kubectl logs --timestamps revisor-578c8dc8d9-g9lhl | head -9 | sed -E 's/^[0-9-]+T([0-9:]+)\.[0-9]+Z/\1/'
13:45:44 revisor 1.6.0 escuchando en :8080 (1 servicio(s))
13:45:45 revisor: GET /salud 200 0s
13:45:45 revisor: GET /salud 200 0s
13:45:50 revisor: GET /salud 200 0s
13:45:54 revisor: GET /salud 200 0s
13:45:55 revisor: GET /salud 200 0s
13:46:00 revisor: GET /salud 200 0s
13:46:04 revisor: GET /salud 200 0s
13:46:05 revisor: GET /salud 200 0s

$ kubectl get pod revisor-578c8dc8d9-g9lhl -o jsonpath='{.status.startTime} {.status.containerStatuses[0].started} {.status.containerStatuses[0].ready}{"\n"}'
2026-10-21T13:45:43Z true true
```

(`--timestamps` ajoute devant chaque ligne l'heure à laquelle elle a été écrite, en UTC et avec des nanosecondes ; le `sed` ne fait que retirer la date et les décimales pour que cela tienne. Le journal de personne d'autre n'affiche ces heures : ce sont celles de cette exécution.)

Maintenant, lis-le comme une horloge (ce sont les minutes 45 et 46). Le programme a commencé à écouter à `:44`. À `:45`, il y a **deux** requêtes. La première est la **startup probe**, qui interroge chaque seconde et n'a pas eu besoin de plus d'une fois ici ; à partir de ce moment, elle n'interroge plus, et les deux autres entrent en jeu. La seconde, dans la même seconde, est la première **readiness probe** : la documentation des probes prévient que, tant qu'un conteneur n'est pas prêt, cette probe peut s'exécuter en dehors de sa période, pour que le Pod soit prêt plus tôt. À partir de là, il y a une ligne toutes les 5 secondes (`:45`, `:50`, `:55`, `:00`, `:05`) : celle de la readiness. Et entre elles, une toutes les 10 (`:54`, `:04`) : celle de la **liveness**. Exactement les `periodSeconds` du manifeste. La seconde commande confirme le résultat : le conteneur a démarré (`started` à `true`) et il est prêt (`ready` à `true`).

Deux conséquences pratiques. La première : à ce rythme, chaque réplique écrit environ 18 lignes par minute rien que pour les probes, plus de 25 000 par jour. Si ton programme écrit une ligne par requête, les probes vont remplir son journal, et il vaut mieux le savoir avant d'y chercher quelque chose. La seconde : les probes **coûtent**. Chaque question est du travail pour le `kubelet` et pour le programme. C'est pourquoi `/salud` doit être peu coûteuse, et pourquoi on ne règle pas les périodes à une seconde « au cas où ».

### 5.5 Pourquoi `/salud` n'interroge personne

#### 5.5.1 La scène du jeudi, à l'envers

Le `revisor` existe pour te dire que d'autres services échouent. Si son contrôle de santé dépendait de ces services, le cluster le punirait au moment précis où il fait son travail. On le vérifie : le Pod `depurar` de la Leçon 3, le service de test en mode `caido`, et 35 secondes d'attente, plus que les 30 que met la liveness probe à redémarrer.

```text
$ kubectl apply -f depurar.yaml
pod/depurar created

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-b896986b5-kzrmk     1/1     Running   0          92s
revisor-578c8dc8d9-g9lhl   1/1     Running   0          91s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          89s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          92s

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $TOKEN" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  codigo 503

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano
modo: sano
```

(Dans `correr.salida.txt`, le token apparaît en clair : le script le colle dans la commande. C'est un faux token de cette exécution, qui est mort avec le cluster.)

Zéro redémarrage dans les quatre Pods, tous `1/1`, et le rapport dit ce qu'il doit dire : `prueba FALLA codigo 503`. C'est le contraire de la scène du jeudi, et la différence tient à une seule décision de conception : `/salud` répond « je suis vivant » sans rien demander à personne. Le commentaire de la première ligne du manifeste le laisse écrit pour celui qui viendra après.

Remarque aussi le service de test : `RESTARTS 0` et `1/1`, alors qu'il répond 503 sur `/` depuis plus de 35 secondes. Sa liveness probe interroge `/modo`, qui continue de répondre. Le cluster distingue « il échoue exprès » de « il est mort » parce que tu lui as posé la bonne question.

#### 5.5.2 Et la documentation ne dit-elle pas de vérifier les dépendances ?

Elle le dit, avec une nuance, et il vaut la peine de la lire en entier. La documentation des probes, dans la partie sur le moment d'utiliser chacune : « quand ton application a une dépendance stricte envers des services de *backend*, tu peux mettre en place une liveness probe et une readiness probe. La liveness probe réussit quand l'application elle-même est saine, mais la readiness probe vérifie en plus que chaque service de *backend* requis est disponible ».

Deux choses. La première est la règle qui ne change jamais : **la liveness probe ne regarde que l'application**. Même dans ce paragraphe, la dépendance va dans la readiness, jamais dans la liveness. Redémarrer ton programme ne répare pas la base de données d'une autre équipe ; cela te laisse seulement sans programme.

La seconde est un critère, et elle dépend de ce que fait ton service. Si ton service ne peut rien répondre d'utile sans sa base de données, le sortir du trafic tant qu'elle manque a du sens. Le `revisor` est le cas opposé : **sa réponse utile est justement de dire qui manque**. Si sa readiness probe dépendait de `prueba`, quand `prueba` tomberait en panne, le Service du `revisor` se retrouverait sans répliques et le tableau de bord ne se chargerait pas, ce qui est le symptôme de la scène par un autre chemin. C'est pourquoi les trois probes du `revisor` interrogent `/salud`, et `/salud` n'interroge personne. L'Exercice 1 te laisse voir cet autre chemin avec le service de test.

### 5.6 `requests`, `limits` et la capacité des nœuds

#### 5.6.1 Deux nombres, deux propriétaires différents

La [documentation de gestion des ressources](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) les sépare selon qui les utilise : « quand tu spécifies le *request* d'une ressource pour les conteneurs d'un Pod, le `kube-scheduler` utilise cette information pour décider sur quel nœud placer le Pod. Quand tu spécifies un *limit* pour un conteneur, le `kubelet` fait respecter cette limite pour que le conteneur n'utilise pas plus de cette ressource que la limite que tu as fixée ».

- **`requests` est une réservation.** L'ordonnanceur l'utilise pour choisir un nœud, et le `kubelet` la respecte ensuite : la même page dit que le `kubelet` met aussi de côté « au moins la quantité du *request* » pour ce conteneur, donc, quand il y a concurrence pour le CPU, le conteneur conserve sa part. Sur l'ordonnanceur, la même page : il s'assure que, pour chaque ressource, la somme des *requests* des conteneurs d'un nœud est inférieure à sa capacité, et il le fait même si l'utilisation réelle est très faible : « l'ordonnanceur refuse de placer un Pod sur un nœud si la vérification de capacité échoue ». Le `request` n'est pas ce que le conteneur utilise : c'est ce que le nœud lui réserve.
- **`limits` est un plafond**, et le `kubelet` et le noyau Linux le font respecter en permanence.

#### 5.6.2 Les unités

**CPU.** La même page : « 1 unité de CPU équivaut à 1 cœur physique de CPU, ou à 1 cœur virtuel » si le nœud est une machine virtuelle, et les fractions sont admises : `0.1` est la même chose que `100m`, « qui se lit cent millicpu ». Le `revisor` demande `50m`, le vingtième d'un cœur, et son plafond est `200m`, le cinquième. La documentation recommande la forme avec `m` pour les quantités inférieures à 1, parce qu'elle se lit mieux.

**Mémoire.** En octets, avec des suffixes. Il y a deux familles : `M`, `G` (puissances de 10) et `Mi`, `Gi` (puissances de 2). `32Mi` font 32 mébioctets, 33 554 432 octets ; `32M` en feraient 32 000 000. Le cours utilise `Mi`. Et un piège que la documentation signale en toutes lettres : « fais attention à la casse des suffixes ». `400m` de mémoire font 0,4 **octet**, pas 400 mégas : le `m` minuscule veut dire « milli ». Un `memory: 64m` écrit par erreur est un plafond d'une fraction d'octet : le conteneur ne peut même pas démarrer. (Cela n'a pas été mesuré dans la leçon ; ce qui a été mesuré en préparant le cours, c'est qu'avec un plafond de `4Mi` le `revisor` donne déjà `StartError`, comme le dit le commentaire de `memoria.yaml`.)

#### 5.6.3 Que se passe-t-il en atteignant le plafond

Le plafond ne s'applique pas de la même façon aux deux ressources, et la différence est de celles qui comptent le plus dans ce cours. La documentation de gestion des ressources :

- **CPU :** « les limites de `cpu` s'appliquent en bridant le CPU » (*throttling*). Si le `revisor` voulait plus de `200m`, le noyau ne les lui donne tout simplement pas : le programme va plus lentement, mais reste vivant.
- **Mémoire :** « les limites de `memory` sont appliquées par le noyau avec des arrêts pour manque de mémoire (OOM) ». La mémoire qu'un programme possède déjà ne peut pas lui être reprise à moitié, donc, quand il dépasse et que le noyau ne peut pas récupérer de mémoire ailleurs (par exemple, dans le cache de fichiers), il le tue. La documentation appelle cela une limite « réactive » : elle n'empêche pas le dépassement, elle le punit. L'erreur volontaire de cette leçon est exactement cela.

La règle pratique qui en découle : un plafond de CPU bas rend ton programme **lent** ; un plafond de mémoire bas le fait **mourir**. On pose les deux, mais celui de la mémoire se pose avec plus de marge.

#### 5.6.4 Ce qu'un nœud kind dit avoir

Combien tient-il dans un nœud ? On le lui demande :

```text
$ kubectl get nodes -o custom-columns='NODO:.metadata.name,CPU:.status.allocatable.cpu,MEMORIA:.status.allocatable.memory'
NODO                         CPU   MEMORIA
curso-k8s-l5-control-plane   6     16342676Ki
curso-k8s-l5-worker          6     16342676Ki
curso-k8s-l5-worker2         6     16342676Ki
```

(`custom-columns` construit un tableau avec les champs que tu demandes ; `allocatable` est ce que le nœud offre aux Pods.)

Chaque nœud dit avoir 6 CPU et environ 15,6 GiB. Ce sont, pour les trois, **toute** la machine virtuelle Docker de cette exécution : 6 CPU et 16 GiB. C'est kind, ne l'oublie jamais : ses nœuds sont des conteneurs sur la même machine, et chacun voit et annonce l'intégralité des ressources de l'hôte. Pour l'ordonnanceur, il y a 18 CPU ; sur le matériel, il y en a 6. Dans un cluster réel, chaque nœud annonce les siennes. Dans kind, `requests` et `limits` fonctionnent comme dans un vrai cluster — l'ordonnanceur compte et le noyau coupe —, mais la capacité que tu vois est un mirage de laboratoire. Sur ta Mint, les nombres seront ceux de ton ordinateur.

Ce que l'ordonnanceur a déjà réservé sur un nœud de travail :

```text
$ kubectl describe node curso-k8s-l5-worker | sed -n '/^Allocated resources:/,/^Events:/p' | head -8
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests   Limits
  --------           --------   ------
  cpu                150m (2%)  200m (3%)
  memory             82Mi (0%)  64Mi (0%)
  ephemeral-storage  0 (0%)     0 (0%)
  hugepages-1Gi      0 (0%)     0 (0%)
```

`Requests` additionne ce que demandent tous les Pods du nœud, les tiens et ceux du système. Dans cette exécution, une réplique du `revisor` est tombée sur `worker` (ses `50m` et `32Mi`, et ses `200m` et `64Mi` de plafond, qui constituent toute la colonne `Limits`) ; le reste des *requests* vient des Pods du système qui tournent sur chaque nœud, comme le réseau de kind. La note du début, « les limites totales peuvent dépasser 100 % », dit quelque chose d'important : l'ordonnanceur ne compte **pas** les `limits`. Tu peux promettre plus de plafond qu'il n'y en a, parce qu'on suppose que tous n'atteignent pas leur plafond en même temps. Ce que l'ordonnanceur ne laisse pas dépasser 100 % de la capacité allouable, c'est la somme des `requests` au moment de décider où tombe un Pod ordinaire (les Pods statiques du nœud lui-même n'y passent pas).

#### 5.6.5 Combien utilise vraiment le `revisor`

Les nombres du manifeste sont des décisions. Sont-ils proches de la réalité ? Le `kubelet` parle au `containerd` du nœud, et `crictl` peut lui demander combien utilise chaque conteneur (c'est le même outil que dans la Leçon 2, à l'intérieur du nœud) :

```text
$ docker exec curso-k8s-l5-worker2 crictl stats --label io.kubernetes.container.name=revisor | sed 's/^.\[2J.\[H//'
CONTAINER           NAME                CPU %               MEM                 DISK                INODES              SWAP
060935005135f       revisor             0.02                1.733MB             45.06kB             13                  0B
1be34aa64c901       revisor             0.03                1.733MB             45.06kB             13                  0B
```

(`--label` filtre les conteneurs qui s'appellent `revisor` ; sur `worker2`, deux répliques sont tombées. `crictl stats` imprime au début des codes pour effacer l'écran, et le `sed` les retire.)

Moins de 2 Mo de mémoire et le CPU presque à zéro, au repos. Le `request` de `32Mi` représente plus de quinze fois cela. Ce n'est pas une erreur : le `revisor` grossit quand il construit un rapport et interroge plusieurs services à la fois, et un `request` est ce dont le programme a besoin dans sa journée normale sous charge, pas au repos. Mais le chiffre confirme quelque chose dont tu vas te servir dans un instant : le `revisor` **ne convient pas** pour provoquer un `OOMKilled`, parce qu'il n'utilise presque pas de mémoire. Pour le voir, il faut un programme qui en demande.

Dans un cluster réel, cette mesure se fait avec `kubectl top`, qui a besoin de `metrics-server`. Il arrive dans la Leçon 9, parce que c'est lui qui alimente la mise à l'échelle automatique.

#### 5.6.6 Les classes de qualité de service

Avec `requests` et `limits`, le cluster classe chaque Pod dans l'une de trois classes. La [documentation des classes de QoS](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) donne les critères :

| Classe | Quand | Dans ce cours |
|---|---|---|
| `Guaranteed` | chaque conteneur a des `requests` et des `limits` de CPU et de mémoire, et dans chacun le `request` est **égal** au `limit` | aucun |
| `Burstable` | n'est pas `Guaranteed`, mais au moins un conteneur a un `request` ou un `limit` | `revisor`, `prueba`, `depurar`, `memoria` |
| `BestEffort` | aucun conteneur ne déclare rien de CPU ni de mémoire | le `revisor` de 5.1 |

Et à quoi cela sert : quand un nœud manque de ressources, « Kubernetes expulse d'abord les Pods `BestEffort` de ce nœud, puis les `Burstable` et enfin les `Guaranteed` ». Et elle ajoute que, lorsque l'éviction est due à un manque de ressources, seuls sont candidats les Pods qui utilisent plus que ce qu'ils ont demandé. La page plus détaillée sur l'éviction par pression sur le nœud le précise : le `kubelet` expulse d'abord les `BestEffort` et les `Burstable` qui dépassent leur `request`, et les `Guaranteed` et les `Burstable` qui ne le dépassent pas sont évincés en dernier, si ce qui précède n'a pas suffi. Autrement dit, respecter ton `request` te met à la fin de la file, pas hors de la file. Une autre raison pour que le `request` ressemble à l'utilisation réelle. Le `revisor` de 5.1 était le premier de la file. Aujourd'hui, il est `Burstable`, parce que son plafond est supérieur à son plancher : il peut « s'étirer » de `50m` à `200m` s'il y a du CPU libre. Pour le rendre `Guaranteed`, il faudrait égaliser les deux nombres, et payer toujours le plafond comme réservation. Pour un programme qui utilise 2 Mo au repos, le cours préfère `Burstable`.

### 5.7 L'arrêt ordonné

#### 5.7.1 Que se passe-t-il quand tu supprimes un Pod

La [documentation du cycle de vie d'un Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) raconte la séquence. Quand on demande la suppression d'un Pod, le cluster note un délai, et le `kubelet` du nœud commence l'arrêt : il demande au *runtime* du conteneur d'envoyer « un signal TERM » (SIGTERM) « au processus 1 dans chaque conteneur », c'est-à-dire au processus principal, celui qui a le PID 1. Et ensuite : « une fois le délai échu, le signal KILL est envoyé aux processus restants ». SIGTERM est une demande (« arrête-toi, s'il te plaît ») ; SIGKILL n'est pas une demande, c'est le noyau qui termine le processus sans lui demander son avis. Le délai par défaut est de **30 secondes**, et il se change avec `terminationGracePeriodSeconds`.

En même temps, il se passe autre chose, qui rejoint la Leçon 3 : le plan de contrôle sort du trafic le Pod qui s'arrête. La même page : ses *endpoints* ne sont pas supprimés immédiatement de l'EndpointSlice, mais ils sont marqués `terminating` et « ont toujours leur état `ready` à `false` », donc ils ne reçoivent plus de nouveau trafic. (La page des EndpointSlices ajoute une exception que le cours n'utilise pas : `ready` est toujours vrai dans un Service avec `publishNotReadyAddresses: true`.) Les deux choses se produisent en même temps, pas l'une après l'autre. Cette course entre « le Pod reçoit SIGTERM » et « tous les nœuds apprennent qu'ils ne doivent plus lui envoyer de trafic » est celle que la Leçon 9 résout avec `preStop`. Aujourd'hui, il suffit de savoir qu'elle existe.

#### 5.7.2 Le voir

*Un avertissement sur les noms.* Les sorties de cette section et des deux suivantes viennent de l'exécution du script, où l'arrêt a eu lieu **après** les deux erreurs de « L'erreur que tu vas voir ». C'est pourquoi le Pod supprimé ici, `g9lhl`, apparaît encore vivant dans la section sur `Pending`, et le `hfjmq` qui le remplace apparaît déjà dans l'habitude de sécurité : ce n'est pas une erreur de ton cluster ni de la leçon. Sur ta machine, si tu suis la leçon dans l'ordre du texte, les noms seront différents.

Pour voir ce que le `revisor` écrit dans ses dernières secondes, ouvre un **second terminal** et prépare-le ainsi, avec le chemin qu'a affiché le `echo` de 5.1.1 (dans le premier terminal, `echo "$KUBECONFIG"` te le redonne) :

```bash
# En la SEGUNDA terminal. Pega la ruta completa; la de abajo es solo la forma.
export KUBECONFIG=/tmp/curso-k8s-l5.XXXX/kubeconfig
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
kubectl logs -f <nombre de una réplica del revisor>
```

Si la vérification dit « contexto equivocado », le chemin n'est pas le bon : ne continue pas. Avec `kubectl logs -f` qui tourne là-bas, supprime cette réplique dans le premier terminal :

```text
$ kubectl delete pod revisor-578c8dc8d9-g9lhl
pod "revisor-578c8dc8d9-g9lhl" deleted from default namespace
(el borrado tardó 0 s)

$ kubectl logs -f revisor-578c8dc8d9-g9lhl   # lo que se alcanzó a leer, en otra terminal
revisor: GET /salud 200 0s
revisor: GET /salud 200 0s
revisor: recibí terminated, apagando
revisor: apagado limpio

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-hfjmq   1/1     Running   0          3s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          2m23s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          2m26s
```

(`-f` suit le journal en direct jusqu'à ce que le conteneur se termine ; le script l'enregistre dans un fichier et en montre les quatre dernières lignes.)

`kubectl delete` attend que le Pod disparaisse vraiment, et il a mis **moins d'une seconde** (le script mesure en secondes entières et a noté `0 s` ; lors d'autres exécutions, il a noté 1 et 3). Les deux dernières lignes du journal sont l'arrêt ordonné : le `revisor` a reçu `terminated` (c'est ainsi que Go appelle SIGTERM), a cessé d'accepter de nouvelles connexions, a attendu que se terminent celles qu'il avait et est sorti de lui-même : `apagado limpio`. Il n'est jamais arrivé au SIGKILL. Et le ReplicaSet avait déjà remplacé la réplique : `hfjmq`, de 3 secondes.

#### 5.7.3 Pourquoi 10 secondes

Si le `revisor` est parti en moins d'une seconde, pourquoi changer le délai de 30 à 10 ? Parce que le délai n'est pas pour l'arrêt réussi, il est pour l'arrêt **raté**. Si un jour le `revisor` se bloque et n'écoute pas SIGTERM, le cluster le tue au bout de 10 secondes et non de 30. Pendant ce temps, le Pod occupe sa place : un *rollout* de trois répliques qui s'arrêtent mal pourrait prendre des minutes de trop.

Le nombre n'est pas non plus pris au hasard : le `revisor` se donne à lui-même 5 secondes pour terminer les requêtes en cours, et le délai du cluster doit être **supérieur** à celui de l'application, sinon le SIGKILL l'interrompt au milieu de ses adieux. 10 est le double de 5. Quand la Leçon 9 ajoutera `preStop`, qui s'exécute lui aussi dans ce délai, le nombre montera à 15.

L'Exercice 3 t'apprend ce qui se passe avec un processus qui n'écoute **pas** SIGTERM : le Pod `depurar`.

## L'erreur que tu vas voir

Cette leçon contient deux erreurs volontaires, une pour chaque nombre de `resources` : le plafond de mémoire et le plancher de CPU.

### OOMKilled : dépasser le plafond de mémoire

Comme tu l'as vu en 5.6.5, le `revisor` utilise moins de 2 Mo ; avec lui, on ne peut pas voir un `OOMKilled`. On utilise un Pod isolé, `memoria.yaml`, qui est un **programme** qui échoue exprès : il essaie de stocker 40 Mo dans une variable de *shell* avec un plafond de 16 MiB.

```yaml
# memoria.yaml — Lección 5: el OOMKilled a propósito.
# El revisor en reposo usa menos de 5 MiB (medido: con un límite de 5Mi corre
# sin problema, y con 4Mi ni siquiera arranca: StartError). Para ver un
# OOMKilled de verdad hace falta un proceso que PIDA memoria: este Pod intenta
# guardar 40 MB en una variable con un límite de 16 MiB.
apiVersion: v1
kind: Pod
metadata:
  name: memoria
  labels:
    app: memoria
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
  - name: memoria
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sh", "-c", "echo 'pidiendo 40 MB'; a=$(head -c 40000000 /dev/zero | tr '\\000' x); echo 'no debería llegar aquí'"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 16Mi}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

C'est l'image de `curl` de `depurar`, avec le même `securityContext`, et un autre programme : `head -c 40000000 /dev/zero` produit 40 millions d'octets à zéro, `tr` les convertit en lettres `x`, et `a=$(…)` oblige le *shell* à tous les garder en mémoire. `restartPolicy: Never` fait que, en mourant, il reste mort pour qu'on puisse l'examiner.

```text
$ kubectl apply -f memoria.yaml
pod/memoria created

$ kubectl get pod memoria
NAME      READY   STATUS      RESTARTS   AGE
memoria   0/1     OOMKilled   0          20s
```

`STATUS OOMKilled` : mort par manque de mémoire (*Out Of Memory*). On le lit dans l'ordre, du symptôme à la cause.

**D'abord, la raison et le code :**

```text
$ kubectl get pod memoria -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
OOMKilled 137
```

Le code de sortie `137` est une convention Unix : 128 plus le numéro du signal qui a tué le processus. 137 − 128 = 9, et le signal 9 est SIGKILL. Personne n'a demandé au programme de partir ; le noyau l'a terminé. Mais attention : un 137 dit « on l'a tué avec SIGKILL », pas qui ni pourquoi. Cela peut être le noyau pour la mémoire, comme ici, ou le `kubelet` parce que le délai d'arrêt est échu, ce que provoque l'Exercice 3. Ce qui sépare les deux cas, c'est la raison : `OOMKilled` dans l'un, autre chose dans l'autre. Regarde toujours la raison à côté du code.

**Ensuite, jusqu'où il est allé :**

```text
$ kubectl logs memoria
pidiendo 40 MB
```

Il a écrit sa première ligne et jamais la seconde, `no debería llegar aquí`. Il est mort en pleine allocation.

**Enfin, le plafond qui l'explique :**

```text
$ kubectl describe pod memoria | grep -E '^QoS Class:|Reason:|Exit Code:|Limits:|memory:'
      Reason:       OOMKilled
      Exit Code:    137
    Limits:
      memory:  16Mi
      memory:     16Mi
QoS Class:                    Burstable
```

`Limits: memory: 16Mi` (le second `memory: 16Mi` est celui du bloc `Requests`, que le `grep` attrape aussi). Il a demandé 40 Mo contre un plafond de 16 MiB : le noyau a fait exactement ce que dit 5.6.3. Le [guide pour allouer de la mémoire](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) provoque la même erreur avec un autre programme et, dans sa section « Exceed a Container's memory limit », le résume ainsi : un conteneur peut dépasser son `request` si le nœud a de la mémoire, mais pas son `limit`.

**Comment on corrige.** Pas avec un plafond plus haut « pour voir ». La documentation de gestion des ressources, dans sa section de dépannage, donne l'ordre : face à un `OOMKilled`, l'étape suivante est de vérifier le code à la recherche d'une fuite de mémoire ; si le programme se comporte comme tu l'attends, alors oui, relève le plafond (et peut-être le plancher). Ici, le programme fait exactement ce qu'il doit faire, c'est-à-dire échouer ; on le supprime :

```text
$ kubectl delete pod memoria
pod "memoria" deleted from default namespace
```

Si c'était un conteneur d'un Deployment, le `kubelet` le redémarrerait encore et encore, avec des attentes croissantes entre les tentatives : la documentation du cycle de vie donne la série, « 10 s, 20 s, 40 s, … », avec un plafond de 5 minutes. Cette attente est ce que `kubectl get pods` affiche comme `CrashLoopBackOff`. Si tu vois un `CrashLoopBackOff`, regarde la colonne `RESTARTS` et la raison de la dernière terminaison avant de toucher à quoi que ce soit : ce peut être un `OOMKilled`, un programme qui sort en erreur, une liveness probe mal écrite. Ce sont trois corrections différentes.

### Pending : demander un plancher qui ne tient pas

La seconde erreur va vers l'autre nombre : un `request` de CPU qu'aucun nœud ne peut réserver. On la provoque avec un correctif (patch) direct sur le Deployment, pour que la correction consiste à réappliquer le fichier.

Avant un tel changement, la vérification de contexte de 5.1.2 :

```bash
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
```

```text
$ kubectl patch deployment revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"50"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"50"}]'
deployment.apps/revisor patched
```

`kubectl patch --type=json` modifie des champs isolés d'un objet vivant : ici, le `request` et le `limit` de CPU du premier conteneur passent à `50`. **Cinquante CPU**, pas cinquante millicpu : le `m` manque. C'est une faute de frappe facile à commettre, et le cluster l'accepte sans se plaindre : `50` est une quantité valide.

**D'abord, le symptôme :**

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-g9lhl   1/1     Running   0          2m3s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          2m1s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          2m4s
revisor-5b8f867ccf-9x42x   0/1     Pending   0          10s

$ kubectl rollout status deployment/revisor --timeout=15s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]
```

Quatre Pods : un nouveau ReplicaSet (`revisor-5b8f867ccf`) avec une réplique en `Pending`, et les trois anciennes intactes. `Pending` veut dire que le Pod existe dans le `kube-apiserver` mais que personne ne lui a donné de nœud. Et le *rollout* est resté coincé à « 1 sur 3 » : `rollout status` a abandonné au bout des 15 secondes que tu lui as données.

**Ensuite, la cause, dans les événements du Pod :**

```text
$ kubectl describe pod revisor-5b8f867ccf-9x42x | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  25s   default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

(`sed -n '/^Events:/,$p'` affiche depuis la ligne `Events:` jusqu'à la fin.) Celui qui parle est l'ordonnanceur (`default-scheduler`), et son message se lit nœud par nœud :

- `0/3 nodes are available` : aucun des trois nœuds ne convient.
- `1 node(s) had untolerated taint(s)` : l'un a une « souillure » (*taint*) que ce Pod ne tolère pas. C'est le nœud de contrôle, qui par défaut ne reçoit pas tes Pods ; tu l'as vu dans la Leçon 1 quand les Pods ne tombaient que sur les nœuds de travail.
- `2 Insufficient cpu` : les deux autres n'ont pas assez de CPU. Ils demandent 50 ; chacun en annonce 6.
- `preemption: … Preemption is not helpful` : l'ordonnanceur a aussi envisagé d'expulser des Pods de moindre priorité pour faire de la place, et a conclu que cela n'aiderait pas. Même en vidant un nœud, 50 ne tiennent pas dans 6.

La documentation de gestion des ressources présente ce même événement comme son premier cas de dépannage : si l'ordonnanceur ne trouve pas de nœud où le Pod tienne, « le Pod reste non assigné jusqu'à ce qu'une place soit trouvée », et un événement est produit à chaque échec. Les issues qu'elle suggère sont d'ajouter des nœuds ou de libérer de la place ; celle qui s'applique ici est la troisième, l'évidente : demander ce qu'il faut.

**Enfin, ce qui ne s'est pas cassé :**

```text
$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

Le service continue de répondre. Pourquoi le Deployment n'a-t-il retiré aucune ancienne réplique ? À cause de sa stratégie de mise à jour, que la Leçon 9 étudie en profondeur : la [documentation des Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) dit que, par défaut, `maxUnavailable` vaut 25 % « arrondi à l'inférieur » et `maxSurge` vaut 25 % « arrondi au supérieur ». Avec 3 répliques : 0,75 descend à **0** réplique qui peut manquer, et 0,75 monte à **1** qui peut être en surplus. Le Deployment a créé une nouvelle réplique en plus et s'est mis à attendre qu'elle soit disponible pour retirer une ancienne. Elle ne l'a jamais été. Un *rollout* bloqué est gênant ; un *rollout* qui ferait tomber les bonnes répliques pour les remplacer par des répliques qui ne tiennent pas serait une panne générale. Cette règle te protège de ta propre faute de frappe.

**La correction** est celle de toujours dans ce cours : le fichier est la vérité, et on le réapplique.

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hct4cckkgd unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-578c8dc8d9-g9lhl   1/1     Running   0          2m19s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          2m17s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          2m20s
```

Les trois mêmes répliques qu'avant, avec les mêmes âges. Le modèle (template) est redevenu identique à celui du ReplicaSet `revisor-578c8dc8d9`, qui avait déjà ses trois répliques, donc il n'y avait rien à remplacer : le Deployment a ramené à zéro le ReplicaSet cassé et le Pod `Pending` a disparu. C'est le même effet que tu as vu dans la Solution 3 de la Leçon 2.

**L'ordre, pour tout Pod qui n'est pas `Running` :**

1. `kubectl get pods` : `Pending`, `OOMKilled`, `CrashLoopBackOff` ?
2. Si c'est `Pending`, les événements du Pod : que dit l'ordonnanceur de chaque nœud ?
3. S'il est mort, la raison et le code de sa dernière terminaison (`OOMKilled 137`, une `Error` avec un autre code) et son journal (`kubectl logs`, ou `--previous` s'il a déjà redémarré).
4. Avant de changer un nombre, se demander si c'est le nombre qui est faux ou le programme.

## L'habitude de sécurité de la leçon : tout conteneur avec un plancher et un plafond

Le tableau des habitudes du cours assigne deux choses à cette leçon : `requests` et `limits` dans tout conteneur ; les probes ne dépendent pas de services extérieurs. La seconde, tu l'as vérifiée en 5.5. La première se vérifie d'un coup d'œil :

```text
$ kubectl get pods -o custom-columns='POD:.metadata.name,QOS:.status.qosClass,CPU_PIDE:.spec.containers[0].resources.requests.cpu,CPU_TOPE:.spec.containers[0].resources.limits.cpu,MEM_PIDE:.spec.containers[0].resources.requests.memory,MEM_TOPE:.spec.containers[0].resources.limits.memory'
POD                        QOS         CPU_PIDE   CPU_TOPE   MEM_PIDE   MEM_TOPE
depurar                    Burstable   10m        100m       16Mi       32Mi
prueba-b896986b5-kzrmk     Burstable   10m        100m       16Mi       32Mi
revisor-578c8dc8d9-hfjmq   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-jlh4b   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-xhqt8   Burstable   50m        200m       32Mi       64Mi
```

Cinq Pods, cinq lignes complètes, aucune `<none>`, aucun `BestEffort`. Y compris `depurar`, qui est « seulement pour regarder » : la Leçon 3 lui a mis un plafond dès le début, et aujourd'hui tu sais pourquoi.

Pourquoi est-ce une habitude de **sécurité** et pas seulement d'ordre ? Parce qu'un conteneur sans plafond de mémoire est un conteneur qui peut faire planter ses voisins. La [documentation de `LimitRange`](https://kubernetes.io/docs/concepts/policy/limit-range/) commence par la phrase qui l'explique : « par défaut, les conteneurs s'exécutent avec des ressources de calcul illimitées dans un cluster Kubernetes ». Une erreur de programmation (une fuite de mémoire, une boucle qui ne se termine pas) ou une attaque (quelqu'un qui envoie exprès des requêtes énormes) dans un conteneur sans plafond devient un problème du **nœud entier** : le nœud manque de mémoire et commence à expulser des Pods, en commençant par les `BestEffort`, qui peuvent appartenir à une autre équipe. Avec un plafond, les dégâts restent dans le conteneur qui les a causés : lui seul meurt, avec un `OOMKilled` qui dit exactement ce qui s'est passé, et personne d'autre.

Même chose pour le CPU, avec une nuance : un conteneur sans plafond de CPU qui entre dans une boucle infinie avale tout le CPU libre du nœud et ralentit ses voisins. Ceux qui ont déclaré des `requests` conservent leur part, et c'est pourquoi le plancher protège aussi ; ceux qui n'ont rien déclaré se contentent de ce qui reste. Avec un plafond, c'est lui qui s'étouffe.

**Ce que cela protège et ce que cela ne protège pas.** Les plafonds limitent les dégâts **à l'intérieur d'un nœud** ; ils n'empêchent pas quelqu'un de créer cent Pods. Pour cela, un cluster réel utilise `ResourceQuota` (un total par espace de noms) et `LimitRange` (un maximum et une valeur par défaut par conteneur). Ce cours ne les installe pas, et les nomme pour que tu saches qu'ils existent. Et les probes ne sont pas une défense : un attaquant qui entre dans le `revisor` ne va pas casser `/salud`. Ce qu'elles évitent, c'est l'autre moitié du problème, qu'une erreur de ta part transforme une petite défaillance en panne en cascade.

## Ce qui se fait de travers

**Mettre dans la liveness probe quelque chose qui dépend des autres.** C'est la scène du jeudi. Une base de données en panne ne se répare pas en redémarrant ses clients. La liveness probe interroge le processus, et rien d'autre.

**Avoir la même patience pour les trois probes.** Si la liveness réagit aussi vite que la readiness, un faux pas de dix secondes déclenche un redémarrage au lieu de simplement écarter du trafic. La liveness est plus lente.

**Une liveness probe sans startup probe dans un programme lent à démarrer.** Le `kubelet` commence à interroger dès que le conteneur démarre ; si le programme met plus de `failureThreshold × periodSeconds`, il redémarre avant d'avoir fini de démarrer, et encore, et encore. La startup probe existe pour cela.

**Une route de contrôle de santé coûteuse.** Si `/salud` interroge la base de données, construit un rapport ou écrit sur le disque, chaque probe le fait, dans chaque réplique, toutes les quelques secondes. Peu coûteuse et locale.

**Pointer la probe vers une route qui change de code exprès.** Le `GET /` du service de test en fait partie : 503 en mode `caido` par conception. L'Exercice 2 le mesure.

**Des conteneurs sans `requests` ni `limits`.** Ils restent `BestEffort` : l'ordonnanceur ne leur réserve rien, personne ne leur met de plafond et ils sont les premiers à sortir quand le nœud est sous pression.

**Écrire `memory: 64m` ou `cpu: 50`.** Le `m` minuscule en mémoire, ce sont des millioctets ; un nombre sans `m` en CPU, ce sont des cœurs entiers. Le second est le `Pending` de cette leçon.

**Relever le plafond de mémoire à chaque `OOMKilled`.** Si c'est une fuite, tu ne fais que la retarder. On commence par se demander si le programme est correct.

**Prendre la capacité d'un nœud kind pour la réalité.** Chaque nœud annonce toute ta machine. Ce qui tient dans kind ne te dit pas ce qui tient en production.

**Laisser le délai d'arrêt par défaut sans y penser.** Trente secondes peuvent être beaucoup pour un programme qui s'arrête en une, et trop peu pour un autre qui doit terminer un long travail. On le choisit, et on le choisit supérieur au délai interne du programme.

**Un processus principal qui ignore SIGTERM.** Le cluster attendra le délai complet chaque fois que tu l'arrêteras. L'Exercice 3 le mesure.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre et à partir de l'état où il est resté après 5.7, avec le Pod `depurar` encore vivant. Avant chacun, `kubectl config current-context` doit dire `kind-curso-k8s-l5`. `correr.sh` les exécute de la même façon, et sa sortie se trouve dans `correr.salida.txt`. **Avant** d'exécuter chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes propres mots.

### Exercice 1 — Une readiness probe dans le service de test

`fig05_01.prueba-disponibilidad.yaml` est le Deployment de test de cette leçon avec une seule différence : il ajoute une readiness probe sur `GET /`, toutes les 5 secondes, avec 2 échecs pour sortir du trafic.

```yaml
# fig05_01.prueba-disponibilidad.yaml — Ejercicio 1: el servicio de prueba con una
# sonda de DISPONIBILIDAD a GET / (la que responde 503 en modo «caido»).
# Pregunta: al ponerlo en «caido», ¿se reinicia? ¿Sigue recibiendo tráfico?
# ¿Qué dice el reporte del revisor? Se deshace con: kubectl apply -k .
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
      terminationGracePeriodSeconds: 10
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
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
        readinessProbe:
          httpGet: {path: /, port: http}
          periodSeconds: 5
          failureThreshold: 2
        livenessProbe:
          httpGet: {path: /modo, port: http}
          periodSeconds: 10
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Applique-le, attends que le nouveau Pod soit `1/1` et mets-le en mode `caido`. Avant de regarder, prédis : au bout de 15 secondes, que dit la colonne `READY` ? Et `RESTARTS` ? Que dit l'EndpointSlice du Service `prueba` ? Demande-le avec `kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}'`. Quel détail donne le rapport du `revisor` ? Et la question difficile : `kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano` fonctionne-t-il pour réparer la situation ? Sinon, comment le remets-tu en `sano` ? Pour finir, réapplique `kubectl apply -k .`.

### Exercice 2 — Une liveness probe qui demande ce qu'elle ne devrait pas

`fig05_02.prueba-vida-mala.yaml` est le Deployment de test de la leçon avec une seule ligne différente : la liveness probe interroge `GET /` au lieu de `GET /modo`.

```yaml
# fig05_02.prueba-vida-mala.yaml — Ejercicio 2: el servicio de prueba con su sonda
# de VIDA apuntando a GET / en lugar de GET /modo. Es el error de la escena en
# pequeño: la sonda de vida pregunta algo que no dice si el proceso está vivo.
# Pregunta: en modo «caido», ¿cuánto tarda en reiniciarse? Después del reinicio,
# ¿en qué modo está? Se deshace con: kubectl apply -k .
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
      terminationGracePeriodSeconds: 10
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
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 100m
            memory: 32Mi
        livenessProbe:
          httpGet: {path: /, port: http}
          periodSeconds: 10
          failureThreshold: 3
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Applique-le, attends qu'il soit `1/1` et mets-le en mode `caido`. Prédis, avec les nombres de la probe : au bout de combien de secondes environ a lieu le premier redémarrage ? Quels événements le Pod laisse-t-il (cherche les raisons `Unhealthy` et `Killing`) ? Après le redémarrage, que répond `GET /modo` ? Que dit le rapport du `revisor` ? Et explique pourquoi c'est pire qu'il n'y paraît : qu'est-il arrivé à la preuve ? Pour finir, réapplique `kubectl apply -k .`.

### Exercice 3 — Combien de temps met le Pod de débogage à partir (projet)

En 5.7, le `revisor` s'est arrêté en moins d'une seconde. C'est maintenant le tour de `depurar`, le Pod de curl de la Leçon 3. Avant de le supprimer, regarde deux choses : son `terminationGracePeriodSeconds` (il ne le déclare pas) et quel processus porte le numéro 1 dans son conteneur (`kubectl exec depurar -- ps`). Prédis combien de temps va prendre `kubectl delete pod depurar`, mesure-le avec la montre et explique le nombre. Ensuite, propose deux façons de le faire partir plus vite, l'une dans le manifeste et l'autre dans la commande.

### Exercice 4 — Une quatrième réplique tient-elle ?

Avec les nombres de cette leçon : le `revisor` demande `50m` de CPU et `32Mi` de mémoire, et dans l'exécution de la leçon chaque nœud de travail annonçait 6 CPU (utilise le nombre de ton `kubectl get nodes` s'il est différent). En cinq phrases au maximum : combien de répliques du `revisor` tiendraient, en théorie, dans un nœud de travail, en ne comptant que le CPU ? Pourquoi ce nombre est-il trompeur dans kind ? Quel nombre l'ordonnanceur regarderait-il pour décider, le `request` ou le `limit` ? Et quelle classe de QoS aurait le `revisor` si tu écrivais des `requests` et des `limits` égaux, `200m` et `64Mi`, et qu'y gagnerais-tu et que paierais-tu ?

## Solutions

### Solution 1

Mesuré dans `correr.salida.txt` :

```text
$ kubectl apply -f fig05_01.prueba-disponibilidad.yaml
deployment.apps/prueba configured

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl get pods -l app=prueba
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6fd58ccd6d-z29zj   0/1     Running   0          19s

$ kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}'
10.244.2.10 prueba-6fd58ccd6d-z29zj ready=false serving=false

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $TOKEN" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  no responde: Get "http://prueba:9000/": dial tcp 10.96.222.53:9000: connect: connection refused

$ kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano
command terminated with exit code 7
[código de salida: 7]

$ kubectl exec depurar -- curl -s -X POST http://10.244.2.10:9000/modo/sano
modo: sano

$ kubectl get pods -l app=prueba
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6fd58ccd6d-z29zj   1/1     Running   0          23s
```

**`READY 0/1` avec `RESTARTS 0`.** La readiness probe a échoué deux fois de suite (503 sur `/`) et le `kubelet` a marqué le Pod comme non prêt, sans le redémarrer : c'est exactement la différence de 5.3.4. L'EndpointSlice le confirme : l'adresse reste dans la liste, mais avec `ready=false` et `serving=false`, donc personne ne lui envoie de trafic.

**Le rapport a changé de détail.** En 5.5, il disait `FALLA codigo 503` : le service répondait, mal. Maintenant il dit `connection refused` : avec sa seule réplique hors de la liste, le Service `prueba` n'a personne à qui envoyer la connexion et la refuse instantanément, le même code 7 que dans la Leçon 3. Le `revisor` continue de dire `FALLA`, mais il a perdu de l'information : tu ne sais plus **ce que** le service a répondu, seulement qu'il n'y a personne.

**Et tu t'es retrouvé sans porte pour réparer.** Le `POST /modo/sano` par le nom `prueba` passe lui aussi par le Service, et il est lui aussi refusé (code 7). Le Pod est vivant et il écoute ; ce qui n'existe plus, c'est le chemin. La sortie est de parler directement à l'IP du Pod, qui ne passe pas par le Service : `10.244.2.10`, prise dans le même EndpointSlice ou dans `kubectl get pods -o wide`. Il a répondu `modo: sano`, la probe est repassée et le Pod est revenu à `1/1` en quelques secondes. C'est la Leçon 3 à l'envers : là-bas, tu as appris à **ne pas** utiliser les IP des Pods ; ici, tu l'utilises exprès, une fois, pour déboguer.

La leçon générale : une readiness probe sort le Pod de **tout** le trafic du Service, y compris le tien, celui d'administration. Pour un service comme celui-ci, dont le travail est d'échouer de façon visible, c'est la mauvaise décision. C'est pourquoi le manifeste de la leçon n'en comporte pas.

### Solution 2

Mesuré dans `correr.salida.txt` :

```text
$ kubectl apply -f fig05_02.prueba-vida-mala.yaml
deployment.apps/prueba configured

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido
(el primer reinicio llegó 27 s después de ponerlo en «caido»)

$ kubectl get pods -l app=prueba
NAME                      READY   STATUS    RESTARTS     AGE
prueba-7dd568849d-hllzl   1/1     Running   1 (4s ago)   34s

$ kubectl get events --field-selector involvedObject.name=prueba-7dd568849d-hllzl -o custom-columns=RAZON:.reason,MENSAJE:.message | grep -E 'RAZON|Unhealthy|Killing'
RAZON       MENSAJE
Unhealthy   Liveness probe failed: HTTP probe failed with statuscode: 503
Killing     Container prueba failed liveness probe, will be restarted

$ kubectl exec depurar -- curl -s http://prueba:9000/modo
modo: sano

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $TOKEN" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

**27 secondes, et le conteneur a redémarré.** La probe interroge toutes les 10 secondes et tolère 3 échecs : trois questions échouées tiennent en 20 à 30 secondes environ, selon l'endroit du cycle où se trouvait la probe quand tu as changé de mode. Les événements racontent l'histoire en deux lignes : `Unhealthy … statuscode: 503` (la probe a échoué) et `Killing … failed liveness probe, will be restarted` (le `kubelet` l'a tué pour cette raison). `RESTARTS 1 (4s ago)` : le redémarrage date de 4 secondes. (Un événement `Unhealthy` se répète à chaque échec, mais le cluster regroupe les identiques en une seule ligne avec un compteur.)

**Et voici le plus grave : après le redémarrage, `modo: sano` et le rapport dit `OK`.** Le service de test garde son mode en mémoire ; en redémarrant, il démarre dans le mode par défaut. Le cluster a « réparé » le symptôme en effaçant la preuve. Si c'était un vrai service avec un vrai problème, le `revisor` aurait signalé la défaillance pendant 27 secondes puis tout serait redevenu vert, et quelqu'un en conclurait que « ça s'est arrangé tout seul ». Et la fois suivante où cela échouera, ce sera pareil. Avec la probe bien écrite (`/modo`), en 5.5 le service est resté en `caido` aussi longtemps que tu l'as voulu et le rapport a dit la vérité tout le temps. C'est l'avertissement de la documentation en petit : une liveness probe qui ne détecte pas une défaillance irrécupérable mais autre chose finit par faire du mal.

Après les deux exercices, le script réapplique `kubectl apply -k .` et vérifie que le cluster est de nouveau exactement ce que disent les fichiers. C'est le `kubectl diff` de 5.4.1, maintenant à l'envers : sans différences, il sort avec 0 et le message s'affiche.

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-b896986b5-57pgj     1/1     Running   0          5s
revisor-578c8dc8d9-hfjmq   1/1     Running   0          70s
revisor-578c8dc8d9-jlh4b   1/1     Running   0          3m30s
revisor-578c8dc8d9-xhqt8   1/1     Running   0          3m33s
```

Fais la même chose dans ton cluster avant l'Exercice 3 : si le `diff` affiche quelque chose, un exercice est resté sans être défait.

### Solution 3

Mesuré dans `correr.salida.txt` :

```text
$ kubectl get pod depurar -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
30

$ kubectl exec depurar -- ps
PID   USER     TIME  COMMAND
    1 curl_use  0:00 sleep 3600
  109 curl_use  0:00 ps

$ kubectl delete pod depurar
pod "depurar" deleted from default namespace
(el borrado tardó 32 s)
```

**32 secondes : le délai complet, plus le temps que prennent le SIGKILL et le nettoyage.** Le manifeste ne déclare pas de délai, donc c'est celui par défaut, 30, qui vaut. Le processus numéro 1 du conteneur est `sleep 3600`. Le `kubelet` lui a envoyé SIGTERM, et `sleep` n'a rien fait : sous Linux, le processus de PID 1 d'un espace de processus ignore les signaux pour lesquels il n'a pas installé de gestionnaire (handler), et `sleep` n'en installe aucun. Alors le cluster a attendu les 30 secondes et envoyé SIGKILL, qu'on ne peut pas ignorer. Pendant ce temps, `kubectl delete` attendait. Le `revisor`, lui, installe bien son gestionnaire de SIGTERM (c'est pourquoi il écrit `recibí terminated`), et il est parti en 1 seconde.

Deux façons de le faire partir plus vite :

- **Dans le manifeste :** `terminationGracePeriodSeconds: 1` dans le Pod `depurar`. Il n'a rien à terminer avec ordre ; un délai court ne lui enlève rien. (Une autre option est que son processus principal écoute SIGTERM, par exemple avec un `sh` qui installe un `trap` ; c'est plus de travail pour un Pod jetable.)
- **Dans la commande :** `kubectl delete pod depurar --wait=false`, qui demande la suppression et rend la main immédiatement sans attendre. Le Pod met le même temps à partir ; c'est toi seul qui cesses d'attendre. C'est ce que fait le script de la Leçon 3 à la fin. Il existe aussi `--grace-period` dans `kubectl delete` pour changer le délai de cette suppression. Son aide (`kubectl delete --help`) dit que `--grace-period=1` est l'arrêt immédiat, et que 0 n'est accepté qu'avec `--force`, qui en plus supprime le Pod de l'API sans attendre que le nœud confirme que le conteneur est terminé. À utiliser avec précaution.

### Solution 4

Une réponse possible : « En ne comptant que le CPU, dans un nœud qui annonce 6 CPU (ceux de cette exécution) il tient 6 000 m / 50 m = 120 répliques, moins ce que demandent déjà les Pods du système (dans cette exécution, le nœud avait déjà `150m` réservés en comptant une réplique). Ce nombre est trompeur parce que, dans kind, les trois nœuds annoncent la même machine entière : l'ordonnanceur croit qu'il y a 18 CPU là où il y en a 6, et les répliques des trois nœuds se disputeraient les mêmes cœurs. L'ordonnanceur décide avec le `request`, jamais avec le `limit` : les limites peuvent additionner plus de 100 % d'un nœud. Avec des `requests` et des `limits` égaux à `200m` et `64Mi`, le Pod serait `Guaranteed` : le dernier à être évincé quand le nœud est sous pression, et avec son CPU toujours réservé. Tu le paierais en réservant quatre fois plus de CPU et le double de mémoire que ce dont le `revisor` a besoin dans sa journée normale, donc il tiendrait quatre fois moins de répliques par nœud. »

## Supprimer le cluster

Quand tu as fini les exercices, supprime le cluster de la leçon. Ne laisse rien de vivant sur la machine :

```text
$ kind delete cluster --name curso-k8s-l5
Deleting cluster "curso-k8s-l5" ...
Deleted nodes: ["curso-k8s-l5-worker" "curso-k8s-l5-control-plane" "curso-k8s-l5-worker2"]
(borrar tardó 1 s)

$ kind get clusters | grep -c curso-k8s-l5
0
```

(La ligne entre parenthèses est écrite par le script, qui mesure la suppression.) Le `--name` est obligatoire : sans lui, kind supprimerait le cluster appelé `kind`, qui peut appartenir à quelqu'un d'autre ou à un autre projet.

Il reste sur ta machine le dossier temporaire du `kubeconfig` et les deux `token.txt`. On les supprime ainsi, depuis `programas/05-salud-recursos-apagado` :

```bash
# Los dos tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 5.1.1.
case "$L5_TMP" in
  /tmp/curso-k8s-l5.?*) rm -rf -- "$L5_TMP" ;;
  *) echo "No borro «$L5_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L5_TMP
```

Le `case` ne laisse passer qu'un chemin qui commence par `/tmp/curso-k8s-l5.` et qui a quelque chose après, la forme exacte de celui que tu as créé en 5.1.1. Si `L5_TMP` est vide (par exemple parce que tu es dans un autre terminal, où tu ne l'as jamais définie) ou vaut autre chose, il ne supprime rien et te dit pourquoi. C'est la même protection que `correr.sh` utilise au nettoyage : un `rm -rf` que l'on peut copier-coller doit se protéger tout seul. Si le second terminal de 5.7 est encore ouvert, ferme-le : tu n'y as fait que l'`export`. Le cluster de la leçon suivante se crée de zéro, comme celui-ci.

## Comment savoir que j'ai réussi

- [ ] Face à un Pod qui redémarre tout seul, tu distingues avec les événements si c'était une liveness probe (`Killing … failed liveness probe`), un `OOMKilled` ou le programme qui est sorti en erreur.
- [ ] Tu écris les trois probes du `revisor` et tu dis, pour chacune, ce qu'elle demande, ce qui se passe si elle échoue et combien de secondes elle met à réagir avec ses nombres.
- [ ] Tu expliques, avec la sortie de 5.5 et celle de l'Exercice 2, pourquoi la liveness probe ne doit dépendre de personne d'autre ni d'une route qui échoue exprès.
- [ ] Tu lis une ligne `Liveness:` de `describe` et tu nommes chaque nombre.
- [ ] Tu écris `requests` et `limits` en millicores et en mébioctets sans confondre `m` et `M`, et tu dis qui utilise chacun.
- [ ] Face à un `Pending`, tu lis le `FailedScheduling` nœud par nœud ; face à un `OOMKilled`, tu trouves le `137` et le plafond qui l'explique.
- [ ] Tu expliques ce que fait le cluster entre `kubectl delete pod` et la disparition du Pod, et pourquoi `depurar` met plus de 30 secondes et le `revisor` moins d'une.
- [ ] Tu exécutes `programas/05-salud-recursos-apagado/correr.sh > /tmp/mi-corrida-l5.txt 2>&1` et tu compares `/tmp/mi-corrida-l5.txt` à `programas/05-salud-recursos-apagado/correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) sur ce qui ne change pas d'une exécution à l'autre : trois nœuds `Ready` en `v1.37.0` ; six lignes `not yet present on node … loading...` ; `33` octets de token et `-rw-------` dans les deux `token.txt` ; `QoS Class: BestEffort` et `30` avant la leçon ; `mismo token` ; le `kubectl diff` avec les probes, les ressources et les deux `terminationGracePeriodSeconds: 10`, et son code 1 ; seuls les Deployments en `configured` ; les lignes `Limits`, `Requests`, `Liveness`, `Readiness` et `Startup` avec leurs nombres, `QoS Class: Burstable` et `10` ; dans le journal, une ligne de `GET /salud` toutes les 5 secondes et une autre toutes les 10 ; `RESTARTS 0` dans les quatre Pods avec le service de test en `caido` et `FALLA … codigo 503` ; les trois nœuds avec le même CPU et la même mémoire ; `OOMKilled`, `OOMKilled 137` et `pidiendo 40 MB` ; le `Pending`, `timed out waiting for the condition` et `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu` ; `revisor: recibí terminated, apagando` et `revisor: apagado limpio` ; les cinq lignes avec plancher et plafond, toutes `Burstable` ; `0/1` avec `ready=false`, `connection refused` et le code 7 dans l'Exercice 1 ; `RESTARTS 1`, les événements `Unhealthy … 503` et `Killing … will be restarted` et `modo: sano` dans l'Exercice 2 ; `sin diferencias con los archivos` ; `30`, `sleep 3600` comme PID 1 et une suppression de 30 s ou un peu plus dans l'Exercice 3. Les IP, les suffixes des noms, les âges, l'heure du journal, le CPU et la mémoire des nœuds et leurs pourcentages, la mémoire exacte du `revisor` dans `crictl stats`, le nœud où tombe chaque Pod, l'ordre des lignes de `kind load` et les secondes exactes du premier redémarrage dans l'Exercice 2 changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l5`.

## Résumé

Réponds sans regarder la leçon :

1. Que savait le cluster du `revisor` avant cette leçon, et pourquoi son Pod était-il `1/1` à 4 secondes ?
2. Que demande chacune des trois probes et que fait le cluster quand la réponse est « non » ?
3. Qui exécute les probes, et quels codes HTTP comptent comme un succès ?
4. Avec `periodSeconds: 10` et `failureThreshold: 3`, combien de temps met une liveness probe à réagir ?
5. Pourquoi `/salud` n'interroge-t-il pas le service de test, et pourquoi la probe du service de test interroge-t-elle `/modo` et non `/` ?
6. Qui utilise les `requests` et qui utilise les `limits` ? Que devient un conteneur qui dépasse son plafond de CPU, et que devient-il s'il dépasse celui de la mémoire ?
7. Que sont `100m` de CPU ? Et `100m` de mémoire ?
8. Quelles sont les trois classes de QoS et dans quel ordre les Pods sont-ils évincés quand un nœud manque de ressources ?
9. Que signifie le code 137 ?
10. Que se passe-t-il, dans l'ordre, quand tu supprimes un Pod, et à quoi sert `terminationGracePeriodSeconds` ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Liveness, Readiness, and Startup Probes »](https://kubernetes.io/docs/concepts/workloads/pods/probes/) : ce qu'est une probe et que le `kubelet` l'exécute ; ce que demande chacune et ce qui se passe en cas d'échec ; que la startup probe suspend les deux autres jusqu'à son succès ; que la readiness probe retire l'IP du Pod des EndpointSlices et s'exécute pendant tout le cycle de vie ; l'avertissement sur les défaillances en cascade ; les dépendances de *backend* dans la readiness probe et non dans la liveness ; le schéma d'un `failureThreshold` plus grand pour la liveness probe ; les champs d'une probe et leurs valeurs par défaut.
- [Kubernetes, « Configure Liveness, Readiness and Startup Probes »](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) : les codes de 200 à 399 comme succès d'une probe HTTP ; la startup probe avec `failureThreshold * periodSeconds` pour couvrir le pire démarrage, et l'exemple de 30 × 10 s.
- [Kubernetes, « Resource Management for Pods and Containers »](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) : le `request` pour l'ordonnanceur et le `limit` pour le `kubelet` ; le plafond de CPU par bridage (throttling) et celui de la mémoire par arrêt OOM ; les unités de CPU (`100m`, « cent millicpu ») et de mémoire (`Mi`, le piège du `m` minuscule) ; que l'ordonnanceur additionne les `requests` et refuse même si l'utilisation réelle est faible ; l'événement `FailedScheduling` et l'`OOMKilled` comme cas de dépannage.
- [Kubernetes, « Pod Quality of Service Classes »](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) : les critères de `Guaranteed`, `Burstable` et `BestEffort`, et l'ordre d'éviction.
- [Kubernetes, « Pod Lifecycle »](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) : la terminaison d'un Pod avec TERM, le délai de 30 secondes par défaut et le KILL à l'échéance ; les *endpoints* qui s'arrêtent, marqués `terminating` et avec `ready` à `false` ; l'attente croissante entre les redémarrages (10 s, 20 s, 40 s… jusqu'à 5 minutes) et `CrashLoopBackOff`.
- [Kubernetes, « Assign Memory Resources to Containers and Pods »](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) : un conteneur qui dépasse son plafond de mémoire et finit `OOMKilled`.
- [Kubernetes, « Deployments »](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) : `maxUnavailable` et `maxSurge` à 25 % par défaut, arrondis à l'inférieur et au supérieur.
- [Kubernetes, « Limit Ranges »](https://kubernetes.io/docs/concepts/policy/limit-range/) : que, par défaut, les conteneurs s'exécutent sans limite de ressources.
- [kind, « Quick Start »](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster) : `kind create cluster` et `kind load docker-image` avec `--name`, et `crictl` à l'intérieur d'un nœud.

---

**Suivante :** [Leçon 6 — Entrer dans le cluster](06-entrar-al-cluster.md)
