# Leçon 10 — Le projet terminé et ce qui change dans un vrai cluster

Lundi, 7 h 50 du matin. À 9 h 00, réunion avec la direction, et le `revisor` est la démonstration. Tu ouvres l'ordinateur portable et le cluster n'existe plus : pendant le week-end, quelqu'un a mis Docker à jour, quelqu'un d'autre a nettoyé les images et les conteneurs « qui ne servaient plus », et `kind get clusters` te répond par une liste vide. Tu as les manifestes, qui sont dans Git, et tu as la page du wiki que tu as écrite il y a un mois : « Pour le démarrer, `kubectl apply -k .` ». Tu essaies. La première commande te dit `no matches for kind "IPAddressPool"`. Tu la répètes et elle dit maintenant `failed calling webhook`. Tu la répètes une troisième fois et presque tout est créé, mais le Gateway reste sans adresse, et tu ne sais pas si c'est parce qu'il manque quelque chose ou parce que le temps n'a pas encore passé. À 8 h 35, tu as un cluster qui fonctionne *presque*, un wiki qui n'indique pas l'ordre parce que, quand tu l'as écrit, l'ordre « s'est fait tout seul », et le soupçon désagréable que, si on te demande « peux-tu le redémarrer ? », la réponse honnête est « je crois que oui, si je recommence plusieurs fois ».

Cette réponse n'en est pas une. Un projet est terminé quand n'importe qui —toi dans six mois, une nouvelle collègue, une étape automatique d'un *pipeline*— peut partir d'un cluster vide, exécuter une recette courte et arriver au même endroit, sans rien corriger manuellement et en sachant à quoi s'attendre entre une étape et l'autre. Voici la dernière leçon du cours, et elle fait deux choses. La première : elle rassemble tout ce que tu as construit dans les neuf précédentes en une structure qui se déploie avec **deux commandes et une attente**, avec **Kustomize** (une base et des couches par-dessus), et l'automatise avec un script qui **ne cache pas l'ordre**. La seconde est moins confortable et c'est pourquoi elle est la plus importante : elle te dit, en face, **ce qu'il manque à tout cela pour être autre chose qu'un laboratoire**.

**Durée :** 2 × 45 min

**Ce que tu construis :** le `revisor` complet —les neuf leçons réunies— organisé en une base et deux couches Kustomize (la plateforme et le projet), qui se déploie depuis un cluster vide avec deux `kubectl apply` et une attente, et qu'un script répète, supprime et répète à nouveau sans que tu corriges rien manuellement ; et, en plus, une liste écrite de ce qui lui manque pour fonctionner pour de vrai

**Ce que tu apprends :** ce qu'est une base et ce qu'est un *overlay* dans Kustomize, et comment on lit ce qu'ils assemblent ; pourquoi la plateforme (nouveaux types, contrôleurs et *webhooks*) passe avant le projet, et ce que dit le cluster quand cet ordre est rompu ; ce qu'est `kubectl apply --server-side` et quelle erreur il évite ; comment attendre sans `sleep` (avec `kubectl wait`) et comment automatiser le déploiement sans cacher l'ordre ; la vérification finale du projet par rapport au niveau `restricted`, champ par champ ; les tests des objectifs du cours (un nœud qui tombe en panne, une configuration qui change, un Pod étranger, une mise à l'échelle qui lit des métriques) ; ce qu'est Helm et quand il convient plutôt que Kustomize ; et ce qui change, et ce qui se perd, entre un cluster `kind` et un vrai cluster

**D'où tu viens.** Des neuf leçons précédentes, qui se lisent maintenant comme les couches d'un même édifice. De la [Leçon 2](02-pods-deployments.md) : le Deployment, le `securityContext` et les images chargées avec `kind load`. De la [Leçon 3](03-services-dns.md) : les Services et le Pod `depurar`. De la [Leçon 4](04-configuracion-secretos.md) : Kustomize avec ses générateurs et le *hash* qui déclenche le *rollout*. De la [Leçon 5](05-salud-recursos-apagado.md) : les probes, les `requests` et les `limits`. De la [Leçon 6](06-entrar-al-cluster.md) : MetalLB et Envoy Gateway, et l'idée que la plateforme passe avant le projet ; cette leçon transforme cette idée en structure de dossiers. De la [Leçon 7](07-aislar-permisos-red.md) : l'espace de noms `revisor` au niveau `restricted`, les comptes aux permissions minimales et le réseau fermé. De la [Leçon 8](08-datos-y-tareas.md) : le volume et le `CronJob` du rapport. De la [Leçon 9](09-escalar-y-actualizar.md) : `metrics-server`, la mise à l'échelle automatique et l'arrêt avec `preStop`. Si l'une des neuf t'est restée à moitié faite, le tableau de 10.2 te dit dans quel fichier vit chaque pièce.

**Ce que cette leçon ne fait pas.** Elle n'enseigne rien de nouveau sur le `revisor` : tout ce qu'il contient, tu l'as déjà construit. Elle n'installe pas Helm et ne l'exécute pas : elle le nomme, le compare à Kustomize et te dit quand tu devrais l'utiliser. Elle ne transforme pas le cluster en cluster de production : c'est exactement ce qu'elle **ne** fait pas, et la section 10.10 t'explique pourquoi dans chaque cas. Et elle ne répète pas les longues mesures des leçons 6 et 9 (combien de temps la mise à l'échelle met à monter et à descendre, comment MetalLB se comporte de près) : elle s'en sert, et renvoie à ces leçons pour le détail.

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1 (`kubectl version --client` indique `Kustomize Version: v5.8.1`), l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** (avec Gateway API v1.6.1) et **metrics-server v0.9.0**, sur le cluster à trois nœuds de la Leçon 1, qu'on appelle ici `curso-k8s-l10`. La machine était un Mac à processeur ARM avec Docker Engine 29.2.1 dans une machine virtuelle Linux (Colima), et **non** Linux Mint, qui est le système de référence du cours. Ce qui change sur ton Mint : l'architecture (`amd64` au lieu de `arm64`) ; les IP des Pods, des Services et des nœuds ; les suffixes aléatoires des noms, les âges et le nœud sur lequel atterrit chaque réplique ; et, surtout, les durées, qui dépendent de ta connexion (les nœuds téléchargent depuis internet les images de la plateforme) et de la charge de la machine. **Une différence de réseau compte :** cette exécution a utilisé un **réseau Docker dédié**, `curso-k8s-red-l10` (`172.30.0.0/16`), créé avec `docker network create --subnet 172.30.0.0/16 curso-k8s-red-l10` avant le premier cluster et supprimé après le dernier, et chaque cluster a été créé avec la variable `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l10`. On a procédé ainsi parce que la machine était partagée et que d'autres leçons installaient aussi MetalLB : deux clusters qui partagent la même plage sur le même réseau se marchent dessus. `kind` l'annonce dans la sortie de création avec `WARNING: Overriding docker network…` et `Here be dragons! This is not supported currently` (la variable est expérimentale). Sur ta machine, avec le réseau `kind` normal (`172.18.0.0/16` sur Mint), tu n'as besoin de rien de tout cela, et les adresses du point d'entrée sortent en `172.18.255.x` : change la plage de `overlays/kind/metallb-pool.yaml` en `172.18.255.200-172.18.255.250` (10.1.1 et 10.6.2 expliquent pourquoi) et, là où les sorties disent `172.30.255.200`, tu liras `172.18.255.200`. Les clients « extérieurs » des sorties se sont connectés au réseau dédié ; sur ta machine, à `kind`. Le parcours complet se trouve dans [`programas/10-proyecto-final/`](../programas/10-proyecto-final) : `correr.sh` crée un cluster, provoque les deux erreurs de 10.4 (chacune dans un cluster neuf), en crée un autre et parcourt 10.1 à 10.8 et les Exercices 1 à 3, le supprime, puis se termine avec `probar-levantar.sh` (deux clusters de plus). Au total, cinq clusters, l'un après l'autre, et les cinq ont été supprimés. Sa sortie est `correr.salida.txt` (les trois exécutions antérieures citées en 10.8.3 et dans l'Exercice 3 se trouvent dans `corridas-preparacion/` ; `psa-comprobacion.sh` et `crd-tamanos.sh`, avec leurs `.salida.txt`, sont deux mesures isolées citées en 10.7.3 et 10.4.3) ; tu y verras quelques lignes « espera de cupo » : c'est le script qui attendait qu'une autre leçon libère une place sur la machine partagée. L'exécution complète a duré 1 755 secondes (presque une demi-heure), dont environ 6 minutes pour ces attentes. Créer un cluster, attendre les nœuds et charger les images a pris entre 35 et 60 secondes ; l'attente de la plateforme, 153 secondes dans le cluster de 10.5, et dans `probar-levantar.sh` l'étape 2 s'est terminée 234 et 250 secondes après le démarrage du script (l'attente elle-même, environ 229 et 246) ; dans l'une des exécutions de préparation, cette même attente a atteint 881 secondes (elle se trouve dans `programas/10-proyecto-final/corridas-preparacion/corrida4.txt`). Une connexion à internet est nécessaire.

## À la fin, tu seras capable de

- Expliquer avec tes mots ce que sont une **base** et un ***overlay*** dans Kustomize, ouvrir un `kustomization.yaml` et dire quelles ressources il assemble, ce qu'il leur change et comment le vérifier avec `kubectl kustomize` sans toucher au cluster.
- Distinguer une pièce de **plateforme** (nouveaux types, contrôleurs, *webhooks*) d'une pièce de **projet**, et déployer les deux depuis un cluster vide avec deux `kubectl apply --server-side -k` et une attente avec `kubectl wait`, dans le bon ordre.
- Reconnaître et lire les deux erreurs qu'on obtient en rompant cet ordre : celle qui vient de l'application de la plateforme sans `--server-side`, et celle qui vient de la réunion de la plateforme et du projet dans une seule commande.
- Écrire un script de déploiement qui ne cache pas l'ordre —trois étapes nommées, une vérification du contexte avant chacune, et des attentes par condition, non par durée— et le tester en créant, supprimant et recréant le cluster.
- Vérifier le projet par rapport au niveau `restricted` des *Pod Security Standards*, champ par champ et avec le cluster, et expliquer pourquoi la plateforme vit dans des espaces de noms qui ne le respectent pas.
- Mesurer ce qui se passe quand on arrête un nœud de travail (ce qui échoue, pendant combien de temps et pourquoi) et dire ce qui réduit cette fenêtre et ce qui ne la réduit pas.
- Écrire, avec tes mots, cinq raisons pour lesquelles ce que tu as construit n'est pas un vrai cluster et ce qu'on ferait pour chacune.

## Le pourquoi avant le comment

Jusqu'ici, chaque leçon a laissé le cluster *un peu plus loin* de là où il avait commencé : plus de fichiers, plus de pièces, plus de choses à appliquer. Cette accumulation est normale tant que tu apprends, et elle a un coût qu'on ne voit pas avant le lundi de la scène : personne n'a écrit **à un seul endroit** comment tout se déploie. Les leçons le disent, chacune à sa manière ; mais un projet qu'on ne peut reconstruire qu'en relisant neuf leçons n'est pas terminé.

Il existe un cas réel qui montre pourquoi cela compte, et il ne vient pas de Kubernetes. Le 31 janvier 2017, un ingénieur de GitLab a supprimé par erreur le répertoire de données de la base de données principale de GitLab.com : environ 300 Go, selon le rapport public que l'entreprise a publié le 10 février. Ce qui fait de cette histoire une leçon pour nous, c'est ce qui est venu ensuite. L'entreprise avait plusieurs mécanismes de sauvegarde et de récupération sur le papier, et quand on les a cherchés, le rapport dit (traduit) : « le processus de recherche et d'utilisation des sauvegardes a complètement échoué ». La sauvegarde quotidienne avec `pg_dump` n'existait pas : le dossier de stockage était vide, parce que le programme qui la faisait était d'une version différente de celle de la base et se terminait par une erreur, et les courriels qui signalaient cette erreur étaient rejetés par le serveur de destination, si bien que personne ne l'a su avant qu'il soit trop tard. La récupération s'est faite avec une copie prise six heures plus tôt pour une autre raison, et la copier depuis l'environnement de test a pris environ 18 heures. Les modifications faites entre 17 h 20 et près de minuit (UTC ; le rapport donne 23 h 30 dans le détail et 0 h 00 dans le résumé) ce jour-là ont été perdues : selon leur estimation, environ 5 000 projets, 5 000 commentaires et 700 nouveaux comptes.

Cela n'est pas arrivé par manque de recettes. Cela est arrivé parce que **personne n'avait su qu'elles ne fonctionnaient pas** : la sauvegarde échouait et rien ne prévenait. Une recette de récupération que personne n'a exécutée de bout en bout est une hypothèse, comme « je crois que oui, si je recommence plusieurs fois ». C'est pourquoi cette leçon ne se contente pas d'écrire la recette : elle l'**exécute**, la casse volontairement, la supprime et la répète dans un cluster neuf, et t'apprend à le faire toi-même.

La leçon compte dix parties de concepts, puis les sections habituelles :

1. **Le cluster de la leçon** (10.1) : le créer avec son propre `kubeconfig` et sa garde de contexte.
2. **La carte du dossier** (10.2) : ce qu'il y a dans `programas/10-proyecto-final/` et quelle leçon a apporté chaque pièce.
3. **Kustomize : base et *overlays*** (10.3) : comment on l'assemble, comment on le lit et comment on le vérifie.
4. **Pourquoi deux commandes et une attente** (10.4) : les deux erreurs qui enseignent l'ordre.
5. **Déployer manuellement** (10.5) : plateforme, attente, projet, et le voir fonctionner de l'extérieur.
6. **Automatiser sans cacher l'ordre** (10.6) : `levantar.sh` et le test de créer, supprimer et recréer.
7. **La vérification finale par rapport à `restricted`** (10.7).
8. **Tester les objectifs** (10.8) : le nœud qui tombe en panne, la configuration qui change, le Pod étranger, la mise à l'échelle.
9. **Helm, en une mention** (10.9).
10. **Ce qui change dans un vrai cluster** (10.10) : la liste de ce qui manque.

Voici la destination. À la fin de 10.5, un cluster vide contient le projet complet, et le point d'entrée que tu as construit à la Leçon 6 reçoit une adresse que MetalLB lui a attribuée :

```text
$ kubectl get all,pvc,cronjob,hpa,pdb,networkpolicy,gateway,httproute -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rzh88    1/1     Running   0          82s
pod/revisor-654b5d75dc-6m6s6   1/1     Running   0          82s
pod/revisor-654b5d75dc-dq4pp   1/1     Running   0          82s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.57.22     <none>        9000/TCP   82s
service/revisor   ClusterIP   10.96.239.233   <none>        80/TCP     82s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           82s
deployment.apps/revisor   2/2     2            2           82s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       82s
replicaset.apps/revisor-654b5d75dc   2         2         2       82s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          82s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          82s

NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 82s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     82s

NAME                                                    POD-SELECTOR               AGE
networkpolicy.networking.k8s.io/acceso-revisor-salida   acceso-revisor=permitido   82s
networkpolicy.networking.k8s.io/cerrado                 <none>                     82s
networkpolicy.networking.k8s.io/dns                     <none>                     82s
networkpolicy.networking.k8s.io/prueba-entrada          app=prueba                 82s
networkpolicy.networking.k8s.io/revisor-entrada         app=revisor                82s
networkpolicy.networking.k8s.io/revisor-salida          app=revisor                82s

NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.30.255.200   True         82s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               82s
```

(Ce tableau est long à dessein : c'est la preuve que les neuf leçons sont là. Tu le liras ligne par ligne en 10.5.)

## Si tu n'as pas les images du cours de Docker

Cette leçon utilise les mêmes deux images que les Leçons 3 à 9 : `curso-docker-revisor:1.6.0`, celle du `revisor`, et `curso-docker-prueba:1.0.0`, celle du service qui échoue à dessein. Vérifie que tu les as :

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Pour l'autre, la même commande avec `curso-docker-prueba:1.0.0`. S'il t'en manque une, la [Leçon 3](03-services-dns.md) explique comment les construire depuis le dépôt du cours de Docker. Cette leçon ne demande rien de nouveau à aucune des deux. Ce qui est nouveau vient d'internet : les manifestes de MetalLB, d'Envoy Gateway et de `metrics-server` sont téléchargés depuis leurs versions publiées chaque fois que tu appliques la plateforme, et les images de ces trois composants et celle de `curl` sont téléchargées par chaque nœud la première fois. Il te faut une connexion.

## Les concepts

### 10.1 Le cluster de la leçon

#### 10.1.1 Avant de créer : la place, le réseau et le disque

Cette leçon installe **MetalLB**, comme la Leçon 6, et en traîne la règle de cohabitation : MetalLB attribue des adresses IP du réseau Docker où vivent les nœuds de `kind`, et deux clusters avec MetalLB et la même plage, sur le même réseau, annoncent les mêmes adresses et se marchent dessus. Si tu travailles seul sur ta machine, cela ne te concerne pas : tu auras un seul cluster à la fois. Si tu partages la machine avec quelqu'un, ou si tu as un autre cluster du cours en vie, vérifie avant de créer :

```bash
# ¿Hay otro clúster del curso vivo? Si lo hay y tiene MetalLB, espera a que termine.
kind get clusters
# Espacio de tu disco: si el uso pasa de 80 %, libera lo tuyo antes de seguir.
df -h /
# Cuánto ocupa Docker (imágenes, contenedores, volúmenes), para saber qué liberar.
docker system df
```

`kind get clusters` liste les clusters que `kind` connaît sur ta machine. Si tu vois `curso-k8s-l10` et que tu ne l'as pas créé, arrête-toi : il appartient à quelqu'un d'autre. `df -h /` indique quel pourcentage de ton disque est utilisé (la colonne `Use%`) ; `docker system df` ne donne pas de pourcentages : il résume l'espace occupé par les images, les conteneurs et les volumes de Docker, et sert à savoir quoi libérer. Cette leçon crée plusieurs clusters, l'un après l'autre, et chacun télécharge les images de la plateforme : aucun chiffre d'espace n'a été mesuré, alors garde de la marge.

Et une note sur **le réseau** qui décide de la plage d'adresses, parce qu'elle apparaît dans un fichier de cette leçon. Par défaut, `kind` crée un réseau Docker appelé `kind` et y place tous les nœuds. Sur Linux Mint, ce réseau est généralement `172.18.0.0/16`. Vérifie-le :

```bash
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

Le fichier `overlays/kind/metallb-pool.yaml` fourni par le dossier dit `172.30.255.200-172.30.255.250`, la plage du réseau dédié avec lequel les exécutions de cette leçon ont été faites (expliqué dans « À propos des exécutions »). C'est pourquoi, **même si ton réseau est `172.18.0.0/16`, tu dois changer cette plage toi-même** : en `172.18.255.200-172.18.255.250` si ton réseau est le réseau habituel, ou avec le préfixe de ton réseau si c'est un autre `/16`. C'est **une ligne** dans un fichier, et 10.6 te montre un script qui vérifie que la plage tombe bien dans le réseau avant d'appliquer quoi que ce soit (si tu ne la changes pas, il s'arrête avec un `ALTO` et te le dit).

#### 10.1.2 Créer le cluster

Crée-le depuis `programas/10-proyecto-final/`, avec le même soin que d'habitude : un `kubeconfig` temporaire qui t'appartient, une fonction qui vérifie le contexte avant chaque changement et les images chargées.

```bash
cd programas/10-proyecto-final
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L10_TMP="$(mktemp -d /tmp/curso-k8s-l10.XXXX)"
export KUBECONFIG="$L10_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: una segunda terminal la necesita
# curso-k8s-l10 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
# La guarda: devuelve error si el contexto activo no es el de esta lección.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l10 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
kind create cluster --name curso-k8s-l10 --config kind-curso.yaml
ctx && kubectl get nodes
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l10 > "$L10_TMP/cargar.log" 2>&1
```

Deux choses qui ne sont pas nouvelles mais que cette leçon utilise plus que toute autre. La première : `ctx` est une **fonction du terminal**, pas un programme. Si `kubectl config current-context` ne dit pas `kind-curso-k8s-l10`, elle affiche « contexto equivocado: no sigo » et renvoie une erreur ; le `&&` fait que la commande de droite **ne s'exécute pas** quand la fonction échoue. C'est pourquoi, à partir de maintenant, toute commande qui **change** quelque chose s'écrit `ctx && kubectl apply …`. Une commande qui ne fait que lire (`get`, `describe`) n'en a pas besoin, mais elle ne gêne pas non plus. La seconde : le `export` ne vaut que dans ce terminal. Si tu en ouvres un autre, répète le `export KUBECONFIG=…` avec le chemin qu'a affiché le `echo`, et redéfinis `ctx`.

Et cette leçon a quelque chose que les précédentes n'avaient pas : **un token factice que le Secret généré va lire** (Leçon 4). On le crée une fois, avec des permissions réservées à toi, et on ne le versionne pas (le `.gitignore` du dossier l'exclut) :

```bash
(umask 077; openssl rand -hex 16 > base/token.txt)
TOKEN="$(cat base/token.txt)"
```

Les parenthèses font que le `umask 077` ne vaut que pour cette commande, et le fichier naît avec la permission `0600` (`-rw-------`) : lisible seulement par toi. On le vérifie :

```text
$ /bin/ls -l base/token.txt | cut -d' ' -f1
-rw-------

$ wc -c < base/token.txt
      33
```

Les 33 octets sont les trente-deux caractères hexadécimaux de `openssl rand -hex 16` plus le saut de ligne. Et l'état du cluster tout juste créé, avec ses trois nœuds et les deux images déjà à l'intérieur :

```text
$ kubectl config current-context
kind-curso-k8s-l10

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE   VERSION
curso-k8s-l10-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l10-worker          Ready    <none>          18s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          17s   v1.37.0

$ cat $L10_TMP/cargar.log
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-worker", loading...
```

Six lignes `not yet present on node … loading...` : deux images par trois nœuds, y compris celui du plan de contrôle. Mais « loading » n'est pas une preuve que l'image est arrivée. Une vérification qu'il convient de prendre l'habitude de faire est de demander à chaque nœud quelles images il possède, avec `crictl`, l'outil du *runtime* de conteneurs que tu as déjà utilisé à la Leçon 2 :

```text
$ for n in control-plane worker worker2; do echo "-- curso-k8s-l10-$n"; docker exec curso-k8s-l10-$n crictl images | grep -E 'IMAGE|curso-docker'; done
-- curso-k8s-l10-control-plane
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
-- curso-k8s-l10-worker
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
-- curso-k8s-l10-worker2
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Chacun des trois nœuds liste les deux images, avec le tag que tu leur as donné (`1.6.0` et `1.0.0`). `crictl` leur ajoute `docker.io/library/` devant parce que c'est le nom que `containerd` donne à une image sans registre, et cela ne veut pas dire qu'elles ont été téléchargées de là. La colonne `IMAGE ID` (`70e09194319be`, `5f32d8833d958`) ne coïncide pas avec celle que montre `docker image ls` sur ta machine (`bd1b2e7d91b8` pour le `revisor`) : ce sont deux magasins distincts et chacun identifie l'image à sa façon. Il en va de même pour la taille : `crictl` indique 3,68 Mo pour le `revisor` et Docker, 16,2 Mo ; chaque outil mesure différemment et on ne les compare pas entre eux. Ce qui compte, c'est que le nom et le tag soient présents sur **chaque** nœud : s'il manque sur l'un, un Pod qui atterrit là essaiera de télécharger l'image depuis internet et restera en `ErrImagePull`, comme à la Leçon 2, et cette requête est celle qui l'explique.

**Un avertissement sur `kind load`.** Si tu as obtenu l'image depuis un registre, ne la charge pas avec `kind load docker-image repo@sha256:…`. Dans les tests du cours de Docker de Hábil (kind v0.33.0, Docker 29.2.1 avec magasin containerd, processeur arm64), cette commande a répondu « loading… » sans erreur et l'image **est bien arrivée sur le nœud, mais sans nom** : `docker exec <nœud> crictl images` l'a montrée comme `docker.io/library/import-AAAA-MM-DD` avec le tag `<none>` (le nom de remplissage que `ctr images import` donne à ce qu'il importe sans référence propre ; la date est celle de l'horloge du nœud, en UTC), et un Pod qui demandait la même référence avec *digest* est resté en `ErrImageNeverPull`, parce que sur le nœud il n'existe aucune image portant ce nom, même si son contenu y est. Donne-lui d'abord un tag local (`docker tag repo@sha256:… curso-docker-revisor:1.6.0`), charge ce tag et vérifie toujours avec `crictl images`, **en regardant aussi les lignes `<none>`** : un filtre qui ne laisse passer que le nom de ton image (comme le `grep -E 'IMAGE|curso-docker'` ci-dessus) ne les montre pas. C'est un cas mesuré, sans source officielle pour ce symptôme exact ; les *issues* de kind [#4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) et [#4224](https://github.com/kubernetes-sigs/kind/issues/4224) décrivent des défaillances voisines (avec erreur) de `kind load` avec un Docker récent, la plupart liées au magasin de `containerd` de Docker (#3795 et #4066 ; le #4224 concerne OrbStack). Les deux images de cette leçon sont chargées par leur tag local (`curso-docker-revisor:1.6.0`, `curso-docker-prueba:1.0.0`), et la sortie ci-dessus en est la vérification.

Le cluster vide ne contient aucun type d'objet que Kubernetes n'apporte pas lui-même. On le vérifie, parce que c'est le point de départ de tout ce qui suit :

```text
$ kubectl get crd
No resources found
```

`crd` est l'abréviation de *CustomResourceDefinition*, la définition d'un nouveau type d'objet (tu l'as vu à la Leçon 6). « No resources found » signifie que le cluster ne connaît que les types avec lesquels il naît. Ni `Gateway`, ni `IPAddressPool`, ni `HTTPRoute` n'existent encore. C'est ce vide que l'ordre de 10.4 doit remplir.

### 10.2 La carte du dossier

#### 10.2.1 Ce qu'il y a et quelle leçon l'a apporté

Le dossier `programas/10-proyecto-final/` contient trois choses : la **base** (le projet), les **overlays** (comment on l'installe dans un cluster concret) et les **scripts** (comment on le déploie). Voici les fichiers des deux premières :

```text
$ find base overlays -type f ! -name token.txt | sort
base/.gitignore
base/cuentas.yaml
base/escalado.yaml
base/gateway.yaml
base/kustomization.yaml
base/namespace.yaml
base/prueba-deployment.yaml
base/prueba-service.yaml
base/red.yaml
base/reporte.yaml
base/revisor-deployment.yaml
base/revisor-service.yaml
overlays/ejemplo-nube/kustomization.yaml
overlays/kind/gatewayclass.yaml
overlays/kind/kustomization.yaml
overlays/kind/metallb-pool.yaml
overlays/kind/plataforma/envoy-gateway/kustomization.yaml
overlays/kind/plataforma/kustomization.yaml
overlays/kind/plataforma/metallb/kustomization.yaml
overlays/kind/plataforma/metrics-server/kustomization.yaml
```

(`find` parcourt les dossiers et liste les fichiers ; le `! -name token.txt` omet le token et `sort` les trie. `.gitignore` apparaît parce que `find` ne cache pas les fichiers qui commencent par un point.)

Chaque fichier de la base est une leçon que tu as déjà faite. Ce tableau est la carte ; si quelque chose t'est resté à moitié fait, voici où regarder :

| Fichier | Ce que c'est | De quelle leçon il vient |
|---|---|---|
| `base/namespace.yaml` | l'espace `revisor`, au niveau `restricted` avec la version de la politique figée | 7 |
| `base/cuentas.yaml` | les comptes de service sans identifiants montés et le rôle en lecture seule `observador` | 7 |
| `base/red.yaml` | les six `NetworkPolicy` : tout est fermé et seules les ouvertures nécessaires sont permises | 7 |
| `base/revisor-deployment.yaml` | le `revisor` : image, variables, token sous forme de fichier, probes, ressources, arrêt ordonné, répartition entre les nœuds et `securityContext` | 2, 4, 5, 7, 9 |
| `base/revisor-service.yaml` | le nom stable `revisor` à l'intérieur du cluster | 3 |
| `base/prueba-deployment.yaml` et `base/prueba-service.yaml` | le service de test qui échoue à dessein | 2, 3, 5, 7 |
| `base/gateway.yaml` | le point d'entrée (`Gateway`) et la route (`HTTPRoute`) | 6 |
| `base/reporte.yaml` | le volume du rapport et le `CronJob` qui l'enregistre | 8 |
| `base/escalado.yaml` | la mise à l'échelle automatique (`HorizontalPodAutoscaler`) et le `PodDisruptionBudget` | 9 |
| `base/kustomization.yaml` | les générateurs du `ConfigMap` et du `Secret` avec *hash*, et la liste de ce qui précède | 4 |
| `overlays/kind/metallb-pool.yaml` | la plage d'adresses que MetalLB peut attribuer | 6 |
| `overlays/kind/gatewayclass.yaml` | la classe de point d'entrée `eg`, desservie par Envoy Gateway | 6 |
| `overlays/kind/plataforma/` | MetalLB, Envoy Gateway et `metrics-server`, chacun dans son dossier | 6, 9 |

Trois familles de fichiers manquent à dessein. Le `LoadBalancer` direct de la Leçon 6 (`revisor-publico`) a été retiré à la 7 : le seul point d'entrée vers l'extérieur est le Gateway. Les Pods d'appui —`depurar`, `intruso`, `memoria`, le Job de charge— sont des **outils pour observer et pour provoquer**, et non des parties du projet : rien n'oblige à les avoir dans chaque cluster que tu déploies, et c'est pourquoi `depurar.yaml` et `intruso.yaml` vivent à la racine du dossier et non dans la base. Et le token : il n'est pas versionné.

#### 10.2.2 Trois questions pour décider où va chaque fichier

L'ordre des dossiers n'est pas un caprice. Chaque fichier répond à trois questions, dans cet ordre :

1. **Le `revisor` en a-t-il besoin dans n'importe quel cluster où on l'installe ?** Alors il va dans la **base**. Le Deployment, le Service, les règles réseau et le niveau `restricted` valent autant sur `kind`, dans le cluster de ton entreprise ou dans le cloud.
2. **Dépend-il de *ce* cluster ?** Alors il va dans un **overlay**. La plage d'adresses de MetalLB vient du réseau Docker de kind ; dans un cloud, elle n'existerait pas, parce que le fournisseur donne les équilibreurs de charge. Ce qui dépend de l'environnement ne se mélange pas avec ce qui n'en dépend pas.
3. **S'installe-t-il une seule fois par cluster et plusieurs projets l'utilisent-ils ?** Alors c'est de la **plateforme**. MetalLB, Envoy Gateway et `metrics-server` ne sont pas au `revisor` : le jour où tu publieras un second service, il utilisera la même classe de point d'entrée et la même plage. C'est pourquoi ils ont leur propre dossier et leur propre commande.

Tu verras que la troisième question n'est pas une affaire de goût : c'est elle qui décide de *l'ordre d'application*. La plateforme apporte de nouveaux types, et le projet les utilise. 10.4 le démontre.

### 10.3 Kustomize : base et *overlays*

#### 10.3.1 Une base qui ne connaît personne

Tu as déjà utilisé Kustomize à la Leçon 4, avec des générateurs. Ici, on l'utilise pour ce pour quoi il a été conçu : **composer**. La [documentation de Kubernetes](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) le définit ainsi (traduit) : une **base** est un répertoire avec un `kustomization.yaml` qui contient un ensemble de ressources et les personnalisations associées ; un ***overlay*** est un répertoire avec un `kustomization.yaml` qui désigne *d'autres* répertoires de kustomisation comme ses bases. Et la phrase qui compte : « une base ne sait rien d'un *overlay* et peut être utilisée dans plusieurs ».

Voici le `kustomization.yaml` de la base. Tu en connais presque tout ; le commentaire du haut est nouveau et dit ce que tu viens de lire :

```yaml
# kustomization.yaml — Lección 10: la BASE del proyecto. No se aplica sola: la
# aplica un overlay (overlays/kind). Una base no sabe que existen sus overlays.
#
# El token NO se versiona: token.txt lo genera quien levanta el proyecto
# ((umask 077; openssl rand -hex 16 > base/token.txt)) y está en .gitignore. Los
# generadores agregan un hash al nombre: si cambia el contenido, cambia el
# nombre, y eso dispara el rollout del Deployment.
#
# Esta base necesita que la PLATAFORMA (MetalLB, Envoy Gateway y metrics-server)
# ya esté instalada y lista: sin sus tipos nuevos (CRD), Gateway y HTTPRoute no
# existen. Por eso el overlay se aplica DESPUÉS de overlays/kind/plataforma.
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
- reporte.yaml
- escalado.yaml
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

Trois champs font tout le travail. `resources` est la liste des fichiers qu'il assemble. `namespace: revisor` est un **transformateur** : il met cet espace de noms sur tout ce qui l'admet, sans que chaque fichier le répète (c'est pourquoi il n'y a pas de `namespace:` dans `deployment.yaml`). Et les deux **générateurs** créent le `ConfigMap` et le `Secret` avec le nom plus un *hash* du contenu : si le contenu change, le nom change, et le Deployment —que le générateur réécrit pour qu'il pointe vers le nouveau nom— fait un *rollout* tout seul. C'était la Leçon 4.

#### 10.3.2 Un overlay qui ne fait que pointer

Le `kustomization.yaml` de l'overlay de `kind` est plus court que la base :

```yaml
# overlays/kind — Lección 10: el proyecto completo para un clúster de kind que ya
# tiene su plataforma (ver plataforma/). Dos comandos y una espera, en este orden:
#
#   kubectl apply --server-side -k overlays/kind/plataforma
#   (esperar a que MetalLB, Envoy Gateway y metrics-server estén listos)
#   kubectl apply --server-side -k overlays/kind
#
# No lleva «namespace:» a propósito: la base ya pone todo en «revisor», y el rango
# de MetalLB y la GatewayClass viven fuera de ese espacio.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
- metallb-pool.yaml
- gatewayclass.yaml
```

Trois lignes de ressources : la base (le dossier, pas un fichier), la plage de MetalLB et la classe de point d'entrée. L'overlay **ne copie** rien de la base ; il ne fait que la nommer. C'est pourquoi, si demain tu changes le Deployment du `revisor`, les overlays ne s'en aperçoivent pas et n'ont pas à s'en apercevoir. Et remarque ce que le commentaire dit du `namespace:` : cet overlay ne le met **pas**, parce qu'il mettrait `revisor` aussi à la plage de MetalLB, qui doit vivre dans `metallb-system`, et la `GatewayClass` n'appartient même à aucun espace (elle vaut pour tout le cluster). Le transformateur de la base s'est déjà occupé de ce qui le concerne.

Pour voir ce qu'un overlay assemble sans toucher au cluster, il existe `kubectl kustomize`, qui **affiche** les manifestes obtenus. C'est la commande que tu utiliseras le plus en travaillant avec Kustomize : elle assemble, elle n'applique pas. Combien d'objets, de quels types :

```text
$ kubectl kustomize overlays/kind | grep '^kind:' | sort | uniq -c | sort -rn
   6 kind: NetworkPolicy
   4 kind: ServiceAccount
   2 kind: Service
   2 kind: Deployment
   1 kind: Secret
   1 kind: RoleBinding
   1 kind: Role
   1 kind: PodDisruptionBudget
   1 kind: PersistentVolumeClaim
   1 kind: Namespace
   1 kind: L2Advertisement
   1 kind: IPAddressPool
   1 kind: HTTPRoute
   1 kind: HorizontalPodAutoscaler
   1 kind: GatewayClass
   1 kind: Gateway
   1 kind: CronJob
   1 kind: ConfigMap

$ kubectl kustomize overlays/kind | grep -c '^kind:'
28
```

(`grep '^kind:'` ne garde que les lignes qui *commencent* par `kind:`, une par objet ; `sort | uniq -c` compte combien il y en a de chaque type et le dernier `sort -rn` trie du plus au moins.) C'est le projet complet : chaque ligne du tableau de 10.2 y a sa part. Trois lignes méritent un regard. Les `ServiceAccount` et les `NetworkPolicy` sont plus d'un parce que chaque charge a son compte et chaque ouverture réseau sa règle. Le `ConfigMap` et le `Secret` sont un de chaque : les générateurs. Et `Gateway`, `HTTPRoute`, `GatewayClass`, `IPAddressPool` et `L2Advertisement` sont les objets de **types qui n'existent pas dans un cluster vide**, le point de 10.4.

Les chiffres ci-dessus sont le total que verra `kubectl apply`. Si un jour tu doutes de ce que le cluster va recevoir, voici la première question que tu poses, avant d'appliquer : `kubectl kustomize`, et compte.

#### 10.3.3 Changer sans copier : un overlay d'exemple

Les overlays servent à ce qui *change* d'un environnement à l'autre. Pour voir ce qu'une couche peut changer sans toucher à la base, ce fichier décrit à quoi ressemblerait la même base dans un vrai cluster. **Il ne s'applique à rien** : on le fait seulement rendre.

```yaml
# overlays/ejemplo-nube — Lección 10: un overlay de EJEMPLO que solo se RENDERIZA
# (kubectl kustomize); no se aplica a ningún clúster del curso. Muestra qué
# cambiaría la misma base en un clúster de verdad: la imagen sale de un registro,
# hay más réplicas y el reparto se hace por zona, no por nodo. No incluye la
# plataforma de kind (MetalLB, rango, GatewayClass): en la nube eso lo da el
# proveedor o el equipo de plataforma.
# registry.example.com es un dominio reservado para ejemplos: no existe.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
images:
- name: curso-docker-revisor
  newName: registry.example.com/equipo/revisor
  newTag: "1.6.0"
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: revisor
  patch: |-
    - op: replace
      path: /spec/minReplicas
      value: 3
    - op: replace
      path: /spec/maxReplicas
      value: 10
- target:
    kind: Deployment
    name: revisor
  patch: |-
    - op: replace
      path: /spec/template/spec/topologySpreadConstraints/0/topologyKey
      value: topology.kubernetes.io/zone
```

Il y a trois outils de changement, et les trois sont là. **`images`** change le nom et le tag d'une image dans tout l'arbre sans modifier les Deployments : ici, l'image vient d'un registre au lieu d'être chargée manuellement avec `kind load`. **`patches`** avec une liste d'opérations (`op: replace`) est un *JSON Patch* ([RFC 6902](https://www.rfc-editor.org/rfc/rfc6902.html)) : il dit quel objet (`target`, par type et par nom), quel chemin changer (`path`) et la nouvelle valeur. C'est précis et parfois peu commode, parce que le chemin s'écrit avec l'indice de la liste (`topologySpreadConstraints/0` est la première contrainte). La [documentation](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) propose aussi le correctif par *fusion stratégique* (on écrit un morceau de l'objet et il est fusionné), plus lisible pour de gros changements ; pour un nombre ou une clé, celui par opérations est plus direct. Et le domaine `registry.example.com` dépend de `example.com`, un nom que la [RFC 2606](https://www.rfc-editor.org/rfc/rfc2606.html) réserve aux exemples et à la documentation : personne ne peut l'enregistrer, et il n'y a donc aucun risque qu'une autre personne l'utilise et reçoive tes images.

La comparaison entre l'overlay de `kind` et celui-ci est la meilleure façon de voir *ce qui* change :

```text
$ diff <(kubectl kustomize overlays/kind) <(kubectl kustomize overlays/ejemplo-nube)
229c229
<         image: curso-docker-revisor:1.6.0
---
>         image: registry.example.com/equipo/revisor:1.6.0
293c293
<         topologyKey: kubernetes.io/hostname
---
>         topologyKey: topology.kubernetes.io/zone
391c391
<   maxReplicas: 6
---
>   maxReplicas: 10
399c399
<   minReplicas: 2
---
>   minReplicas: 3
418,424d417
< kind: GatewayClass
< metadata:
<   name: eg
< spec:
<   controllerName: gateway.envoyproxy.io/gatewayclass-controller
< ---
< apiVersion: gateway.networking.k8s.io/v1
440,457d432
< ---
< apiVersion: metallb.io/v1beta1
< kind: IPAddressPool
< metadata:
<   name: curso
<   namespace: metallb-system
< spec:
<   addresses:
<   - 172.30.255.200-172.30.255.250
< ---
< apiVersion: metallb.io/v1beta1
< kind: L2Advertisement
< metadata:
<   name: curso
<   namespace: metallb-system
< spec:
<   ipAddressPools:
<   - curso
[código de salida: 1]
```

(`diff` compare deux textes ; `<( … )` lui remet la sortie d'une commande comme si c'était un fichier, et fonctionne dans `bash` et dans `zsh`. Les lignes avec `<` viennent de l'overlay de `kind` ; celles avec `>` viennent de celui d'exemple.) Lis-le bloc par bloc. Dans le premier, il y a un changement d'image : celle du `revisor` vient d'un registre, non de `kind load`. Le deuxième est la contrainte de répartition : de `kubernetes.io/hostname` (répartit entre les *nœuds*) à `topology.kubernetes.io/zone` (répartit entre les *zones*, qui dans un cloud sont des centres de données distincts à l'intérieur d'une région). Ensuite, `maxReplicas` et `minReplicas` de la mise à l'échelle : de 6 à 10 et de 2 à 3. Et à la fin, ce qui **sort** de l'arbre : la `GatewayClass`, la plage et l'annonce de MetalLB, qui appartiennent à `kind` et non à la base. Quatre changements et une soustraction, et la base n'a pas été touchée. (Si tu vois `[código de salida: 1]` sous le `diff`, ce n'est pas une erreur : `diff` sort avec 1 quand il trouve des différences, et avec 0 quand il n'en trouve pas.)

#### 10.3.4 Deux avertissements sur ce qui vient d'internet

Le dossier `plataforma` contient un `kustomization.yaml` par pièce, et chacun pointe vers un **fichier distant** :

```text
$ kubectl kustomize overlays/kind/plataforma | grep -c '^kind:'
76
```

C'est le nombre d'objets assemblés à partir de trois adresses d'internet. Une pièce en particulier, `metrics-server`, porte en plus un correctif que tu connais déjà de la Leçon 9 :

```text
$ kubectl kustomize overlays/kind/plataforma | grep -B1 -A1 'kubelet-insecure-tls'
        - --metric-resolution=15s
        - --kubelet-insecure-tls
        image: registry.k8s.io/metrics-server/metrics-server:v0.9.0
```

L'option `--kubelet-insecure-tls` fait que `metrics-server` ne vérifie pas le certificat avec lequel chaque `kubelet` se présente. Le README de `metrics-server` v0.9.0 la décrit sans fard : « à des fins de test uniquement ». Dans `kind`, les certificats des `kubelet` ne sont pas signés par l'autorité du cluster, donc sans cette option `metrics-server` ne peut pas lire les nœuds. Dans un vrai cluster, elle **n'est pas utilisée** : les certificats sont correctement signés et l'option est superflue. C'est la sixième des choses que 10.10 note dans la liste de ce qui manque.

Les deux avertissements sur le distant :

- **Chaque fois que tu appliques, tu télécharges.** Une adresse avec la version dans le chemin (`…/v0.16.1/…`) fige *quelle version* tu demandes, mais le contenu continue de venir d'internet chaque fois que `kustomize` assemble l'arbre. Sans connexion, pas de plateforme. Une équipe réelle conserve généralement une copie de ces fichiers dans son dépôt (ou sur un miroir à elle), de sorte que le déploiement ne dépende ni d'un site extérieur ni de l'absence de modification d'un fichier distant en dessous de ses pieds. Ici, on ne le fait pas pour que tu voies d'où vient chaque pièce.
- **Fige la version, et note-la.** Les versions de ce cours sont MetalLB v0.16.1, Envoy Gateway v1.9.2 et `metrics-server` v0.9.0. Ce n'est pas un détail : le [guide d'installation d'Envoy Gateway](https://gateway.envoyproxy.io/docs/install/install-yaml/) explique que, lors d'une mise à jour, il faut d'abord mettre à jour les CRD de Gateway API, et que si on ne le fait pas, les routes TCP et UDP sont « ignorées en silence » jusqu'à ce que les CRD soient appliqués. Une version qui bouge sans que personne l'ait décidé est à l'origine de bien des lundis matin.

### 10.4 Pourquoi deux commandes et une attente

#### 10.4.1 Trois choses qu'une installation apporte avec elle

À la Leçon 6, tu as vu que MetalLB et Envoy Gateway ne sont pas « un Deployment de plus » : en s'installant, ils ajoutent au cluster des **types d'objet nouveaux**, des **contrôleurs** qui les desservent et des **gardiens** qui vérifient ce qui est créé. Avant de continuer, les trois avec leurs noms exacts, parce que l'ordre de cette leçon en découle.

- **Un CRD (*CustomResourceDefinition*)** est la définition d'un type d'objet que Kubernetes n'apporte pas d'origine. Tant qu'il n'existe pas, écrire un `IPAddressPool` revient à écrire un mot que le dictionnaire ne contient pas : le `kube-apiserver` répond `no matches for kind`. Et un CRD n'est pas « prêt » dès sa création. La [documentation des CRD](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) le dit ainsi (traduit) : le serveur met quelques secondes à créer le *endpoint* du nouveau type, et tu peux surveiller la condition `Established` du CRD, ou la liste des types que le serveur annonce, pour savoir quand il existe. Cette condition, `Established`, est celle qu'attend `kubectl wait` en 10.5.
- **Un contrôleur** est un programme (un Pod) qui regarde les objets d'un type et fait en sorte que le monde coïncide avec eux : celui de MetalLB attribue des adresses ; celui d'Envoy Gateway crée l'Envoy qui dessert le point d'entrée. Tant qu'il ne tourne pas, l'objet est accepté, mais personne ne s'en occupe : le Gateway existe et n'a pas d'adresse. Un Deployment est *prêt* quand sa condition `Available` est vraie.
- **Un *webhook* d'admission** est un gardien que le `kube-apiserver` consulte *avant* d'enregistrer un objet, pour l'accepter, le rejeter ou le corriger. MetalLB en a un qui valide les plages. La [documentation du contrôle d'admission dynamique](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) contient un point qu'il faut connaître : si le serveur n'arrive pas à parler au *webhook* (réseau, délai d'attente dépassé, connexion refusée), la politique `failurePolicy` décide de ce qui se passe, et **la valeur par défaut est `Fail`** : la requête est rejetée. C'est-à-dire que tant que le Pod du gardien ne répond pas, aucun objet des types qu'il surveille ne peut être enregistré.

Les trois choses arrivent au même moment et ne sont pas prêtes en même temps. Ce qui prend du temps, c'est ce qui oblige à attendre.

#### 10.4.2 `--server-side` : pourquoi la plateforme s'applique autrement

Avant l'ordre, la deuxième commande de la recette comporte une option que tu n'avais pas utilisée : `kubectl apply --server-side`. Mieux vaut la comprendre avant de la voir échouer.

Le `kubectl apply` habituel se fait *côté client* (*client-side*) : `kubectl` calcule ce qui a changé et, pour se souvenir de « la dernière chose que j'ai appliquée », enregistre une copie de tout le manifeste dans une annotation de l'objet lui-même, `kubectl.kubernetes.io/last-applied-configuration`. La [documentation de *Server-Side Apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) décrit l'autre manière (traduit) : au lieu que le client calcule et se souvienne, c'est le serveur qui suit quel **gestionnaire** (*field manager*) est propriétaire de chaque champ de l'objet. Elle est stable depuis Kubernetes 1.22. On la demande avec `--server-side`.

Deux conséquences comptent pour cette leçon. La première : sans la copie de « la dernière chose appliquée » dans l'objet lui-même, une limite disparaît. Une annotation a une taille maximale, et les CRD de Gateway API et d'Envoy Gateway sont énormes (ils décrivent en détail chaque champ de chaque type). Le guide officiel d'installation d'Envoy Gateway, que tu as déjà cité à la Leçon 6, installe avec `kubectl apply --server-side`, et en 10.4.3 tu verras ce que répond le cluster quand on l'omet. La seconde : avec *Server-Side Apply*, celui qui applique est un gestionnaire nommé, et si deux gestionnaires touchent le même champ avec des valeurs différentes, le serveur signale un **conflit** au lieu d'écraser en silence. C'est ce que tu veux quand plusieurs outils (toi, un contrôleur, un *pipeline*) touchent le même cluster.

Et une distinction pour ne pas confondre : `--server-side` change *qui calcule le changement*, pas *ce qui est appliqué*. Le projet s'applique de la même façon dans les deux modes ; cette leçon utilise `--server-side` dans les deux commandes pour que l'habitude soit unique.

#### 10.4.3 Première erreur : la plateforme sans `--server-side`

On applique la plateforme « comme d'habitude », sans l'option, dans un cluster vide. La sortie est longue, on la garde donc dans un fichier et on la regarde par parties : d'abord combien d'objets ont été créés, ensuite **seulement ce qui n'est pas un « created »** :

```text
$ kubectl apply -k overlays/kind/plataforma > $L10_TMP/cliente.txt 2>&1; echo "código: $?"
código: 1

$ grep -c ' created$' $L10_TMP/cliente.txt
73

$ grep -v ' created$' $L10_TMP/cliente.txt | cut -c1-330
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "httproutes.gateway.networking.k8s.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "securitypolicies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(`> fichier 2>&1` enregistre dans le fichier ce qui sort par la sortie normale *et* par la sortie d'erreurs ; `$?` est le code de sortie de la commande précédente ; `grep -v` affiche les lignes qui **ne** correspondent **pas** ; `cut -c1-330` tronque chaque ligne à 330 caractères pour qu'elle tienne.)

Lis-le dans l'ordre. **Le code de sortie est 1** : l'`apply` s'est terminé en erreur. **73 objets ont été créés**, et trois lignes disent ce qui n'a pas pu l'être : les CRD `envoyproxies.gateway.envoyproxy.io`, `httproutes.gateway.networking.k8s.io` et `securitypolicies.gateway.envoyproxy.io` « are invalid: `metadata.annotations: Too long: may not be more than 262144 bytes` ». Cela fait 262 144 octets, soit 256 Kio (256 × 1024) : le plafond que le `kube-apiserver` fixe aux annotations d'un objet. Cette annotation est la copie de « la dernière chose appliquée » dont parlait 10.4.2, et ces trois CRD décrivent tant de champs que leur propre définition, copiée à l'intérieur de l'objet, dépasse le plafond. On a mesuré chaque CRD de la plateforme converti en JSON compact (`programas/10-proyecto-final/crd-tamanos.sh` ; sa sortie, `crd-tamanos.salida.txt`) : `envoyproxies` pèse environ 649 000 octets, `httproutes` environ 299 000 et `securitypolicies` environ 274 000 ; le suivant en taille, `backendtrafficpolicies`, tourne autour de 128 000. Ce sont exactement les trois qui ont échoué, et aucun autre.

Remarque ce que ce message **ne** fait **pas** : il ne dit pas « il manque une option ». Il dit qu'un objet ne tient pas, et il faut savoir que la cause est la manière d'appliquer. Et remarque l'état dans lequel il laisse le cluster, ce qui est grave : 73 objets sur 76 sont créés, donc le cluster *semble* avoir une plateforme, mais il lui manque `httproutes`, le type de la route qu'utilise la Leçon 6, et il lui manque deux types d'Envoy Gateway. Un état à moitié fait qui a l'air presque sain est pire qu'un état qui échoue complètement. Ce cluster a été supprimé, et un autre a été créé pour l'expérience suivante : c'est la méthode du cours.

#### 10.4.4 Seconde erreur : plateforme et projet dans une seule commande

La question naturelle est : pourquoi deux commandes ? On ne peut pas tout réunir en une seule, avec l'option ? `fig10_01.todo-junto/kustomization.yaml` est un **programme qui échoue à dessein** (sa première ligne le signale) : une seule kustomisation qui contient la plateforme et le projet.

```yaml
# fig10_01.todo-junto/kustomization.yaml — FALLA A PROPÓSITO (o funciona a medias):
# junta la plataforma y el proyecto en UN solo «kubectl apply». Las dos mitades
# no tienen orden de espera entre sí: el proyecto pide tipos (IPAddressPool,
# GatewayClass, Gateway, HTTPRoute) que la plataforma todavía no ha registrado.
# Se aplica con:  kubectl apply --server-side -k fig10_01.todo-junto
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../overlays/kind/plataforma
- ../overlays/kind
```

On l'applique dans un cluster vide (un autre, tout juste créé) avec la bonne option. On regarde la même chose qu'avant : combien d'objets sont entrés et lesquels ne l'ont pas fait.

```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto1.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto1.txt
99

$ grep -v serverside-applied $L10_TMP/junto1.txt | cut -c1-330
resource mapping not found for name: "revisor" namespace: "revisor" from "fig10_01.todo-junto": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "eg" namespace: "" from "fig10_01.todo-junto": no matches for kind "GatewayClass" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "revisor" namespace: "revisor" from "fig10_01.todo-junto": no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "curso" namespace: "metallb-system" from "fig10_01.todo-junto": no matches for kind "IPAddressPool" in version "metallb.io/v1beta1"
ensure CRDs are installed first
resource mapping not found for name: "curso" namespace: "metallb-system" from "fig10_01.todo-junto": no matches for kind "L2Advertisement" in version "metallb.io/v1beta1"
ensure CRDs are installed first
```

Lis-le de la même façon. Le code est de nouveau 1, et cette fois **99 objets** sont entrés sur les 104 que l'arbre assemble (76 de la plateforme et 28 du projet). Les cinq qui ne sont pas entrés disent la même chose : `no matches for kind "Gateway"`, `"GatewayClass"`, `"HTTPRoute"`, `"IPAddressPool"` et `"L2Advertisement"`, chacun avec l'avis `ensure CRDs are installed first` (« assure-toi que les CRD sont installés d'abord »). Compare-les aux cinq conditions `Established` qu'attend 10.5.2 : ce sont les mêmes cinq types. Sont entrés les Deployments, les Services, les règles réseau, l'espace de noms et les CRD eux-mêmes, qui ne dépendent d'aucun nouveau type ; n'est entré rien de ce qui en dépend. `kubectl` détermine **au début**, avant de créer quoi que ce soit, quels types le serveur connaît, et avec cette liste il vérifie les 104 objets. Les CRD figurent dans la liste, mais les objets qui les utilisent sont vérifiés par rapport au catalogue qui existait *avant* leur création : c'est pourquoi cinq échouent même si leurs CRD sont créés dans la même commande. Un `apply` ne redemande pas en cours de route ([`mapper.go` de cli-runtime](https://github.com/kubernetes/cli-runtime/blob/master/pkg/resource/mapper.go)).

La tentation qui suit est la pire : répéter la même commande, sans rien changer et sans attendre, pour voir si ça passe cette fois. On l'a fait, et voici ce qui s'est passé :

```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto2.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto2.txt
102

$ grep -v serverside-applied $L10_TMP/junto2.txt | cut -c1-330
Error from server (InternalError): Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
Error from server (InternalError): Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
```

Il y a eu du progrès, et c'est ce qui rend la méthode traîtresse. Maintenant **102 objets** sont entrés : les trois types de Gateway API existaient déjà, donc `Gateway`, `GatewayClass` et `HTTPRoute` sont passés. Il en reste deux, la plage et son annonce, et ils échouent pour une autre cause : `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connect: connection refused`. Le type `IPAddressPool` existe déjà, mais le gardien que MetalLB place devant lui (10.4.1) n'écoute pas encore : le Pod du contrôleur est en train de démarrer. Comme `failurePolicy` vaut `Fail`, le `kube-apiserver` rejette l'objet. `connection refused` signifie que l'adresse du Service du gardien (celle qui apparaît après `dial tcp`, une IP du cluster qui sera différente dans ton exécution) existe, mais que personne ne répond derrière.

Chaque nouvel essai découvre la couche suivante de ce qui manquait : d'abord les types, ensuite les gardiens. Un troisième essai passerait probablement (il n'a pas été mesuré, car cela n'a aucun sens de le mesurer), et il resterait alors écrit dans le wiki « répète jusqu'à ce que ça passe ». C'est le contraire d'une recette : elle ne dit pas combien de fois, elle ne dit pas à quoi s'attendre et, le jour où un essai échouera pour une cause différente, il n'y aurait aucun moyen de la distinguer. La seule chose qui a changé entre l'essai 1 et l'essai 2, c'est le temps qui a passé ; ce qu'il faut, c'est nommer ce qu'on attend.

#### 10.4.5 Ce qu'enseignent les deux erreurs

Les deux erreurs sont des versions du même fait, et elles servent à fixer trois règles :

1. **La plateforme passe en premier et avec `--server-side`.** Elle apporte de nouveaux types, des contrôleurs et des gardiens. C'est une commande à part parce qu'elle a une condition de sortie : « les types sont établis et les contrôleurs sont en marche ».
2. **Entre la plateforme et le projet, il y a une attente par condition.** Non pas un `sleep 30`, qui fonctionne sur ta machine et échoue sur une machine plus lente, mais `kubectl wait --for=condition=…`. La [documentation de `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) le décrit comme l'attente d'« une condition spécifique sur une ou plusieurs ressources » et il sort en erreur si elle n'arrive pas dans le délai que tu as donné (`--timeout`). Dans l'exécution, tu verras que, quand elle est remplie, il affiche `condition met`. Un `sleep` te dit « du temps a passé » ; `wait` te dit « ce dont j'avais besoin est arrivé ». Et quand il échoue, il échoue avec un nom.
3. **Le projet vient après, dans sa propre commande.** Tout ce qui utilise un nouveau type, un contrôleur ou un gardien de la plateforme va ici.

La recette tient en trois lignes : `apply` de la plateforme, `wait`, `apply` du projet. C'est le « deux commandes et une attente » du titre de la leçon, et le premier objectif du cours le compte ainsi : ce sont trois étapes, et l'ordre est ce qui les définit.

Il y a aussi une raison de fond, qui n'est pas propre à ce cours. La documentation de Helm, que 10.9 nomme, a le même problème et le dit avec d'autres mots dans ses [bonnes pratiques sur les CRD](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) (traduit) : « la déclaration [du CRD] doit être enregistrée avant qu'une ressource de ce type puisse être utilisée, et l'enregistrement prend parfois quelques secondes ». Ce n'est pas une bizarrerie de Kustomize ni de `kubectl` ; c'est une propriété de la façon dont Kubernetes étend ses types.

### 10.5 Déployer manuellement : plateforme, attente, projet

Voici maintenant le bon chemin, dans un cluster tout juste créé, avec chaque étape sous les yeux. C'est le cluster de 10.1 (celui des sorties de cette section) : trois nœuds, les deux images chargées, aucun CRD. Et avant **chaque** commande qui change quelque chose, `ctx &&`.

#### 10.5.1 Étape 1 : la plateforme

```bash
ctx && kubectl apply --server-side -k overlays/kind/plataforma > "$L10_TMP/plataforma.txt"
```

Avec l'option et dans un cluster vide, tout entre. La commande affiche une ligne par objet ; on l'a enregistrée dans un fichier et voici ce qu'on en voit :

```text
$ kubectl apply --server-side -k overlays/kind/plataforma > $L10_TMP/plataforma.txt; grep -c serverside-applied $L10_TMP/plataforma.txt
76

$ head -4 $L10_TMP/plataforma.txt
namespace/envoy-gateway-system serverside-applied
namespace/metallb-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
```

Ce sont **76** lignes, une par objet, et aucune ne dit `Error`. `serverside-applied` signifie que le serveur a appliqué l'objet : il l'a créé ou mis à jour ; dans un cluster vide, ce sont toutes des créations. Les deux premières lignes créent les espaces de noms `envoy-gateway-system` et `metallb-system`, et les suivantes sont des CRD (`backends.gateway.envoyproxy.io`, `backendtlspolicies.gateway.networking.k8s.io`…). Compare avec 10.4.3 : avec `--server-side`, les trois CRD qui ne tenaient pas entrent comme les autres, parce qu'on ne leur colle plus la copie de « la dernière chose appliquée ».

Le cluster connaît déjà les nouveaux types, mais leurs contrôleurs sont encore en train de démarrer. Voici l'aspect à cet instant :

```text
$ kubectl get crd | wc -l
      31

$ kubectl get pods -n metallb-system
NAME                          READY   STATUS              RESTARTS   AGE
controller-76f4cf76b7-kclm8   0/1     ContainerCreating   0          0s
speaker-cbfnt                 0/1     ContainerCreating   0          0s
speaker-dgln6                 0/1     ContainerCreating   0          0s
speaker-swc2d                 0/1     ContainerCreating   0          0s
```

Le cluster connaît déjà **30** nouveaux types (`kubectl get crd | wc -l` en compte 31 parce qu'il inclut la ligne d'en-têtes). Et les Pods de MetalLB, à la première seconde, sont tous en `0/1 ContainerCreating` : le `controller` et un `speaker` par nœud sont encore en train de télécharger leur image et de démarrer. C'est l'instant dangereux de 10.4 : les types existent et les gardiens ne répondent pas. Appliquer le projet *maintenant* donnerait le `connection refused` de la seconde erreur.

#### 10.5.2 Étape 2 : l'attente

Cinq attentes, chacune avec sa condition. Les cinq ensemble signifient « la plateforme est prête » :

```bash
ctx && kubectl wait --for=condition=Established --timeout=120s \
  crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
ctx && kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
ctx && kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
ctx && kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
ctx && kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
```

```text
$ kubectl wait --for=condition=Established --timeout=120s crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
deployment.apps/controller condition met

$ kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
deployment.apps/envoy-gateway condition met

$ kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
deployment.apps/metrics-server condition met
```

Les cinq se terminent bien. La première, celle des types, répond immédiatement `condition met` pour les cinq CRD : ils étaient déjà établis. Les autres sont les lentes : le `controller` de MetalLB, les trois `speaker` (la progression dit `0 of 3 updated pods are available…`, puis `1 of 3`, `2 of 3`, et enfin `successfully rolled out`), le contrôleur d'Envoy Gateway et `metrics-server`. Les nœuds sont neufs et n'ont aucune image : chacun doit télécharger depuis internet celles de MetalLB, d'Envoy Gateway et de `metrics-server` avant de pouvoir démarrer les Pods. Dans cette exécution, l'attente complète a duré 153 secondes ; dans les exécutions de préparation de la leçon, elle a varié de ces 153 secondes jusqu'à 881 secondes (presque quinze minutes), selon la connexion et la charge de la machine. Chaque `kubectl wait` porte son propre plafond de 600 secondes ; les 881 étaient la somme des cinq attentes, non une seule (la sortie se trouve dans `corridas-preparacion/corrida4.txt`). Si, sur ta connexion, une seule épuise les 600, l'erreur ne défait rien : répète la même commande. On n'a pas séparé la part de ce temps qui est du téléchargement et celle qui est du démarrage, donc on ne l'affirme pas. Ce qu'on affirme, c'est ce que tu dois prévoir : **l'attente est la partie la plus longue du déploiement**, et c'est pourquoi il convient que ce soit une attente par condition et non une durée fixe que quelqu'un doit deviner.

Et une attente sert aussi à savoir quand quelque chose **n'**arrive **pas**. Si tu demandes à `kubectl wait` une condition qui ne se remplit pas, avec un plafond court, il abandonne avec une erreur au lieu de se bloquer. Ici, on demande au contrôleur d'Envoy Gateway, qui est `Available`, de passer à l'état contraire, et on lui laisse 5 secondes :

```text
$ kubectl wait --for=condition=Available=false --timeout=5s -n envoy-gateway-system deployment/envoy-gateway
error: timed out waiting for the condition on deployments/envoy-gateway
[código de salida: 1]
```

`error: timed out waiting for the condition on deployments/envoy-gateway`, et le script note `[código de salida: 1]`. C'est le comportement que tu veux d'une attente : elle ne se bloque pas, n'invente pas de succès et dit quelle condition de quel objet n'est pas arrivée. Un `sleep 300` suivi d'un `apply` t'aurait laissé sans cette information.

Lis-les avec la liste de trois choses de 10.4.1 sous la main. La première attente concerne les **types** : `Established` est la condition du CRD. Les quatre autres concernent les **contrôleurs** : `Available` pour les Deployments (`controller` de MetalLB, `envoy-gateway`, `metrics-server`) et `rollout status` pour le `DaemonSet` `speaker`. Un `DaemonSet` n'a pas de `Available` ; il a une progression du type « combien des Pods qui doivent exister sont prêts », et `rollout status` la suit jusqu'à ce qu'ils le soient tous (un par nœud). Le *webhook* de MetalLB est desservi par le Pod `controller` : quand il est `Available`, le gardien répond déjà.

#### 10.5.3 Étape 3 : le projet

```bash
ctx && kubectl apply --server-side -k overlays/kind
```

```text
$ kubectl apply --server-side -k overlays/kind
namespace/revisor serverside-applied
serviceaccount/observador serverside-applied
serviceaccount/prueba serverside-applied
serviceaccount/reporte serverside-applied
serviceaccount/revisor serverside-applied
role.rbac.authorization.k8s.io/observador serverside-applied
rolebinding.rbac.authorization.k8s.io/observador serverside-applied
configmap/revisor-config-t6cm6872fk serverside-applied
secret/revisor-token-fgdb694k82 serverside-applied
service/prueba serverside-applied
service/revisor serverside-applied
persistentvolumeclaim/reportes serverside-applied
deployment.apps/prueba serverside-applied
deployment.apps/revisor serverside-applied
cronjob.batch/reporte serverside-applied
poddisruptionbudget.policy/revisor serverside-applied
horizontalpodautoscaler.autoscaling/revisor serverside-applied
gateway.gateway.networking.k8s.io/revisor serverside-applied
gatewayclass.gateway.networking.k8s.io/eg serverside-applied
httproute.gateway.networking.k8s.io/revisor serverside-applied
ipaddresspool.metallb.io/curso serverside-applied
l2advertisement.metallb.io/curso serverside-applied
networkpolicy.networking.k8s.io/acceso-revisor-salida serverside-applied
networkpolicy.networking.k8s.io/cerrado serverside-applied
networkpolicy.networking.k8s.io/dns serverside-applied
networkpolicy.networking.k8s.io/prueba-entrada serverside-applied
networkpolicy.networking.k8s.io/revisor-entrada serverside-applied
networkpolicy.networking.k8s.io/revisor-salida serverside-applied
```

Ce sont **28** lignes, et chaque ligne du tableau de 10.2 y est : l'espace de noms, les quatre comptes de service, le rôle et son attribution, le `ConfigMap` et le `Secret` avec leur *hash*, les deux Services, le volume, les deux Deployments, le `CronJob`, le `PodDisruptionBudget`, la mise à l'échelle, le `Gateway` avec sa `HTTPRoute`, les six règles réseau et les **trois** objets qui n'existent que par l'overlay : la `GatewayClass` `eg`, la plage et l'annonce de MetalLB. Remarque qu'ils ne sortent pas à la fin mais répartis : Kustomize ordonne la sortie par type d'objet, non par le fichier dont ils viennent. Le nom du `ConfigMap`, `revisor-config-t6cm6872fk`, est **le même** que dans les Leçons 4 et 5, parce que la liste de services est la même : le *hash* est celui de son contenu. Celui du `Secret` change à chaque exécution, parce que le token est neuf. Et aucune ligne ne commence par `Warning`, mais cette absence se prouve, elle ne se regarde pas.

Une affirmation comme « il n'y a aucun avertissement » se prouve en comptant, et avec un cas où il y en a (10.7 le fait). Voici le comptage, avec `-i` pour ne pas dépendre des majuscules :

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -ci warning
0
[código de salida: 1]
```

Le `0` est le comptage. Le `[código de salida: 1]` que note le script n'est pas un échec : `grep` sort avec 1 quand il ne trouve aucune ligne, même si avec `-c` il affiche le zéro. Ici, cela signifie « zéro avertissement ».

Ensuite, deux attentes de plus : que les Deployments soient `Available` et que le point d'entrée soit `Programmed` (la condition du `Gateway` qui dit « il a déjà une adresse et un Envoy qui le dessert ») :

```bash
ctx && kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
ctx && kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
```

```text
$ kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
deployment.apps/revisor condition met
deployment.apps/prueba condition met

$ kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
gateway.gateway.networking.k8s.io/revisor condition met
```

Il manque une attente que `kubectl wait` ne couvre pas bien : la mise à l'échelle automatique a besoin de quelques secondes pour lire ses premières métriques, et tant qu'elle ne les a pas, elle affiche `<unknown>`. Cette fois, on ne la résout pas avec un `sleep` à l'aveugle mais avec une boucle courte et **visible**, qui vérifie toutes les 5 secondes pendant deux minutes au plus et s'arrête dès que la mise à l'échelle a une métrique :

```bash
for _ in $(seq 1 24); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

Il y a un `sleep`, et c'est bien : c'est l'**attente d'une condition avec un plafond**. À chaque tour, on demande si ce qui compte est arrivé. Si cela n'arrive pas en 24 tours, la boucle abandonne et la commande suivante te montre le `<unknown>` au lieu de le cacher.

#### 10.5.4 Le voir fonctionner

Tout ce que les neuf leçons ont construit, en une seule requête :

```text
$ kubectl get all,pvc,cronjob,hpa,pdb,networkpolicy,gateway,httproute -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rzh88    1/1     Running   0          82s
pod/revisor-654b5d75dc-6m6s6   1/1     Running   0          82s
pod/revisor-654b5d75dc-dq4pp   1/1     Running   0          82s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.57.22     <none>        9000/TCP   82s
service/revisor   ClusterIP   10.96.239.233   <none>        80/TCP     82s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           82s
deployment.apps/revisor   2/2     2            2           82s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       82s
replicaset.apps/revisor-654b5d75dc   2         2         2       82s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          82s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          82s

NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 82s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     82s

NAME                                                    POD-SELECTOR               AGE
networkpolicy.networking.k8s.io/acceso-revisor-salida   acceso-revisor=permitido   82s
networkpolicy.networking.k8s.io/cerrado                 <none>                     82s
networkpolicy.networking.k8s.io/dns                     <none>                     82s
networkpolicy.networking.k8s.io/prueba-entrada          app=prueba                 82s
networkpolicy.networking.k8s.io/revisor-entrada         app=revisor                82s
networkpolicy.networking.k8s.io/revisor-salida          app=revisor                82s

NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.30.255.200   True         82s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               82s
```

Lis-la par blocs, de haut en bas.

- **Pods.** Les deux du `revisor` et celui de `prueba`, les trois en `1/1 Running`. Si tu déploies le projet juste à une minute multiple de cinq, tu verras aussi un quatrième Pod, `reporte-…`, en `0/1 Completed` : la tâche planifiée de la Leçon 8, qui s'est déjà exécutée et s'est bien terminée (dans une exécution de préparation de cette leçon, il est bien apparu ; dans celle qu'on colle ici, pas encore).
- **Services.** Les deux sont `ClusterIP`, sans `EXTERNAL-IP` : le `LoadBalancer` direct de la Leçon 6 n'existe plus. Le seul point d'entrée est le Gateway.
- **Deployments et ReplicaSets.** `2/2` et `1/1`. Chaque Deployment a un ReplicaSet avec son *hash*. Si tu le vois différent dans ton exécution, c'est normal : il dépend du nom du `Secret`, qui change avec le token.
- **Mise à l'échelle.** `cpu: …/50%`, `MINPODS 2`, `MAXPODS 6`, et les deux répliques actuelles. Qu'il y ait un pourcentage et non `<unknown>` signifie que `metrics-server` a déjà livré sa première lecture ; c'est pourquoi on attend avec la boucle de 10.5.3.
- **CronJob.** L'horaire `*/5 * * * *`, non suspendu, `ACTIVE 0` et `LAST SCHEDULE <none>` : il ne s'est pas encore déclenché une seule fois. Quand il se déclenchera, un Job apparaîtra avec son Pod.
- **Volume.** Le PVC `reportes` est en `Pending`, et c'est normal : à la Leçon 8, tu as vu que la classe `standard` attend le premier Pod qui l'utilise (`WaitForFirstConsumer`) avant de créer le disque. Il passera à `Bound` quand le `CronJob` se déclenchera pour la première fois.
- **`PodDisruptionBudget`.** `MIN AVAILABLE 1`, et `ALLOWED DISRUPTIONS 1` : avec deux répliques, le cluster peut en retirer une à la fois.
- **Règles réseau.** Les six de la Leçon 7, avec leurs sélecteurs.
- **Gateway.** Classe `eg`, **adresse `172.30.255.200`** (la première de la plage de l'overlay) et `PROGRAMMED True`. C'est l'adresse que MetalLB a attribuée. **`HTTPRoute`.** Sans noms de site (`HOSTNAMES` vide) : elle dessert n'importe lequel.

Et les métriques, qui sont la preuve que `metrics-server` et la mise à l'échelle sont connectés :

```text
$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-rzh88    1m           1Mi             
revisor-654b5d75dc-6m6s6   1m           1Mi             
revisor-654b5d75dc-dq4pp   2m           1Mi             
```

Il manque le plus important : que **quelqu'un de l'extérieur** arrive jusque-là. L'adresse du point d'entrée vient du `Gateway` lui-même, et le client est un conteneur Docker connecté au même réseau que les nœuds, **hors** du cluster (la même astuce que la Leçon 6) :

```bash
IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
CURL='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
docker run --rm --network kind $CURL -s -m 5 "http://$IP_GW/salud"
docker run --rm --network kind $CURL -s -m 5 -o /dev/null -w '%{http_code}\n' "http://$IP_GW/api/estados"
docker run --rm --network kind $CURL -s -m 5 -H "Authorization: Bearer $TOKEN" "http://$IP_GW/api/estados?formato=tabla"
```

(Dans le bloc de sortie ci-dessous, le script abrège chaque `docker run … curl` en `curl`, pour que ça tienne. `$TOKEN` est la variable de 10.1.2.)

```text
$ curl -s -m 5 http://172.30.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.30.255.200/api/estados
401

$ curl -s -m 5 -H "Authorization: Bearer $TOKEN" 'http://172.30.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200
```

Les trois requêtes sont arrivées de l'extérieur du cluster à l'adresse que MetalLB a donnée au Gateway. `/salud` répond sans rien demander. `/api/estados` **sans token** renvoie `401` (la Leçon 4 : le `revisor` exige `Authorization: Bearer …`). Et avec le token, le tableau du rapport. Remarque que le token arrive par le point d'entrée dans un en-tête, en clair : c'est le point 4 de la liste de 10.10.

Sur ton terminal, le nom du réseau est `kind` (c'est ainsi que l'a laissé le bloc ci-dessus). Si l'exécution n'a pas utilisé ce réseau, la section « À propos des exécutions » le dit.

### 10.6 Automatiser sans cacher l'ordre

#### 10.6.1 Ce qu'on automatise et ce qu'on ne doit pas cacher

Manuellement, le déploiement, ce sont trois blocs et huit attentes. Pour le répéter dans chaque nouveau cluster —le tien demain, celui d'une collègue, celui d'une étape automatique d'un *pipeline*— un script est utile. Et il y a ici une décision de conception qui sépare un script qui aide d'un script qui gêne. Il y a deux façons de l'écrire :

- **Le script qui cache l'ordre.** Une seule ligne qui « réessaie jusqu'à ce que ça passe » : `until kubectl apply -k .; do sleep 5; done`, ou un `sleep 120` entre deux applications, ou un `|| true` pour que rien ne s'arrête. Il fonctionne presque toujours et, quand il échoue, il ne dit pas pourquoi : la boucle tourne en rond, ou le `sleep` était trop court sur la machine lente, ou l'erreur a été avalée en silence. En 10.4.4, tu as vu ce que fait la nouvelle tentative à l'aveugle : elle applique à moitié et te laisse deviner ce qui manque.
- **Le script qui montre l'ordre.** Les trois mêmes étapes, chacune avec un nom, chacune avec sa vérification de contexte, avec des attentes par **condition** et avec un plafond de temps. Quand il échoue, il échoue à une étape nommée, avec un message de `kubectl` qui dit quelle condition n'est pas arrivée. Et celui qui le lit apprend l'ordre, ce qui est la moitié de sa valeur.

Voici le second. Il s'appelle `levantar.sh`, vit dans le dossier de la leçon et c'est ce qu'une étape de *pipeline* appellerait tel quel :

```bash
#!/usr/bin/env bash
# levantar.sh — Lección 10: el proyecto completo en un clúster recién creado, en
# TRES pasos explícitos, sin esconder el orden. Es lo que un paso de pipeline
# haría igual: la única entrada es el contexto de kubectl que espera encontrar.
#
#   1. la plataforma: metrics-server, MetalLB y Envoy Gateway (traen tipos nuevos,
#      controladores y webhooks)
#   2. esperar a que la plataforma esté lista (tipos registrados, controladores arriba)
#   3. el proyecto
#
# Por qué hay orden: un IPAddressPool, una GatewayClass o un Gateway solo existen
# cuando su CRD ya está registrado, y MetalLB rechaza su rango si su webhook
# todavía no atiende.
#
# Requisitos: un clúster de kind con las dos imágenes cargadas (kind load
# docker-image) y su contexto activo. Uso, desde esta carpeta:
#   ./levantar.sh kind-curso-k8s-l10
set -euo pipefail
cd "$(dirname "$0")"
ESPERADO="${1:?uso: ./levantar.sh <contexto-esperado>   (por ejemplo kind-curso-k8s-l10)}"
NODO_CONTROL="${ESPERADO#kind-}-control-plane"

# Antes de CADA paso que cambia algo: ¿el contexto activo es el esperado?
contexto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  [ "$actual" = "$ESPERADO" ] || { echo "ALTO: el contexto activo es «$actual», no «$ESPERADO»." >&2; exit 1; }
}

# El token no se versiona: si falta, se genera uno nuevo (de mentira, para el curso).
[ -s base/token.txt ] || (umask 077; openssl rand -hex 16 > base/token.txt)

echo "== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?"
contexto
RANGO="$(sed -n 's/^ *- *\([0-9.]*\)-.*/\1/p' overlays/kind/metallb-pool.yaml | head -1)"
IP_NODO="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODO_CONTROL")"
echo "primer IP del rango: $RANGO · IP del nodo de control: $IP_NODO"
[ "${RANGO%.*.*}" = "${IP_NODO%.*.*}" ] || {
  echo "ALTO: el rango de overlays/kind/metallb-pool.yaml no está en la red de los nodos (se compara la red /16)." >&2; exit 1; }

echo "== 1. Plataforma"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind/plataforma)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
echo "(paso 1 terminó a los $SECONDS s)"

echo "== 2. Esperar a la plataforma"
contexto
kubectl wait --for=condition=Established --timeout=120s \
  crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
echo "(paso 2 terminó a los $SECONDS s)"

echo "== 3. Proyecto"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
kubectl get gateway revisor -n revisor
echo "(paso 3 terminó a los $SECONDS s)"
```

#### 10.6.2 Le script, ligne par ligne

Il se lit de haut en bas, et presque tout est quelque chose que tu connais déjà sous un autre visage.

**`set -euo pipefail`.** Trois options de `bash` en une. `-e` arrête le script à la première commande qui échoue. `-u` fait qu'utiliser une variable qui n'existe pas est une erreur, au lieu de la lire vide. `-o pipefail` fait qu'un tube (`a | b`) échoue si *n'importe laquelle* de ses parties échoue, pas seulement la dernière. Ensemble, elles font la différence entre un script qui s'arrête là où est le problème et un script qui continue comme si de rien n'était. C'est la même raison pour laquelle `levantar.sh` utilise `|| true` à un seul endroit : à la lecture du contexte actif, où un échec est accepté (le script le compare ensuite et s'arrête avec un message clair). Il en va de même dans `probar-levantar.sh`, dans le nettoyage du cluster et le comptage des clusters vivants, et dans les échecs volontaires de `correr.sh` : chaque `|| true` est collé à une commande concrète dont l'échec est accepté et dont on dit pourquoi, ce qui est la seule chose que « Les erreurs courantes » admet.

**`ESPERADO="${1:?uso: …}"`.** Le script **ne devine pas** dans quel cluster il se trouve : il reçoit le contexte comme argument et, s'il manque, affiche l'usage et s'arrête. `${1:?message}` signifie « le premier argument, et s'il est vide, échoue avec ce message ». C'est le contraire d'un script qui utilise « le cluster qui est actif » : un script qui installe MetalLB et Envoy Gateway dans le contexte actif, sans demander, peut installer ces choses dans le mauvais cluster.

**`contexto()`.** La fonction `ctx` de 10.1, mais pour un script : elle compare `kubectl config current-context` avec `ESPERADO` et, s'ils ne coïncident pas, affiche « ALTO » et fait `exit 1`. On l'appelle **avant chaque étape**, et non une seule fois au début, parce qu'un long script tourne pendant des minutes et que quelqu'un (ou quelque chose) peut changer le contexte entre deux étapes.

**L'étape 0 : le réseau.** C'est nouveau et cela existe pour une raison concrète. La plage d'adresses de MetalLB vit dans `overlays/kind/metallb-pool.yaml`. Si cette plage ne tombe pas dans le même réseau que les nœuds, MetalLB attribue une adresse au Gateway, `kubectl` dit que tout va bien, et personne de l'extérieur ne peut l'atteindre : l'échec est silencieux. Le `sed` extrait la première adresse de la plage, `docker inspect` extrait l'IP du nœud de contrôle, et la comparaison `${RANGO%.*.*}` (retirer les deux derniers nombres : `172.30.255.200` devient `172.30`) avec `${IP_NODO%.*.*}` vérifie que les deux sont dans le même réseau `/16`. C'est une vérification simple —elle suppose des réseaux de cette taille, et le message d'erreur le dit—, mais elle transforme un échec muet en un « ALTO » avec une cause.

**L'étape 1.** Elle capture la sortie de `kubectl apply` dans une variable (`SALIDA="$(…)"`) et n'affiche que le comptage de `serverside-applied`. Si `kubectl apply` échoue, l'affectation échoue et `set -e` arrête le script : on n'arrive pas au comptage. La sortie n'est pas jetée avec `>/dev/null` : elle est **mesurée**.

**L'étape 2.** Les cinq attentes de 10.5.2, sans changement. Chacune avec son plafond (`--timeout`) : 120 secondes pour que les CRD existent, 600 (dix minutes) pour les contrôleurs, qui dépendent du temps que met ta connexion à télécharger les images.

**L'étape 3.** Elle applique le projet et attend deux choses : les Deployments `Available` et le point d'entrée `Programmed`. À la fin, `kubectl get gateway` affiche le résultat que tu veux voir.

**`$SECONDS`.** Une variable de `bash` qui compte les secondes écoulées depuis le démarrage du script. Chaque étape indique au bout de combien de secondes elle s'est terminée. Ce n'est pas de la décoration : si une étape devient lente, tu le vois, et les durées de ce script sont celles que 10.6.3 utilise pour dire combien de temps prend le déploiement du projet.

Ce qu'il **ne** fait **pas** est aussi une décision. Il ne crée pas le cluster (c'est à celui qui l'appelle : toi, ou une étape préalable du *pipeline*). Il ne charge pas les images. Et il ne fait pas de `curl` : vérifier que le point d'entrée répond de l'extérieur demande un client dans le réseau Docker, et c'est un test, non un déploiement. Un script qui déploie et un autre qui teste peuvent être modifiés séparément.

Un dernier détail sur le code de sortie. `levantar.sh` sort avec 0 seulement si **tout** le parcours est terminé ; avec n'importe quel échec, il sort avec un code différent de 0 à l'étape où cela s'est produit. C'est la seule chose qu'un *pipeline* a besoin de savoir pour marquer une étape en vert ou en rouge, et c'est pourquoi le script y veille et ne dépend pas de quelqu'un qui lirait le texte de la sortie.

#### 10.6.3 Le tester pour de vrai : créer, déployer, supprimer, recréer

Un script qui n'a jamais été exécuté contre un cluster vide est comme la sauvegarde du cas GitLab : il existe et on ne sait pas s'il sert. On le teste avec `probar-levantar.sh` : il crée le cluster, exécute `levantar.sh`, vérifie de l'extérieur que le point d'entrée répond, **supprime le cluster** et répète le tout une seconde fois. Si le premier tour passe par hasard (quelque chose qui existait déjà, un cache, une attente qui a suffi), le second le trahit, parce qu'il repart de zéro.

```bash
#!/usr/bin/env bash
# probar-levantar.sh — comprueba levantar.sh en un clúster NUEVO curso-k8s-l10, con
# un kubeconfig temporal propio, y borra el clúster al terminar. Dos vueltas: crear,
# levantar, borrar, recrear y levantar otra vez (meta 1 del curso).
#
# Uso, desde esta carpeta:   ./probar-levantar.sh
# Variables opcionales:
#   RED_DOCKER   red de Docker donde viven los nodos (por omisión «kind»). Si usas
#                otra, el rango de overlays/kind/metallb-pool.yaml debe caer en ella.
#   CUPO_MAXIMO  en una máquina compartida: antes de crear un clúster espera a que
#                haya menos de CUPO_MAXIMO clústeres «curso-k8s-*».
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=curso-k8s-l10
CONTEXTO="kind-$CLUSTER"
RED_DOCKER="${RED_DOCKER:-kind}"
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
L10_TMP="$(mktemp -d /tmp/curso-k8s-l10.XXXX)"
export KUBECONFIG="$L10_TMP/kubeconfig"

limpiar() {
  if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  rm -f base/token.txt
  case "$L10_TMP" in /tmp/curso-k8s-l10.?*) rm -rf -- "$L10_TMP" ;; esac
  return 0
}
trap limpiar EXIT

if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster llamado «$CLUSTER»; este guion no lo toca." >&2; exit 1
fi

crear() {
  if [ -n "${CUPO_MAXIMO:-}" ]; then
    until [ "$(kind get clusters 2>/dev/null | grep -c '^curso-k8s-' || true)" -lt "$CUPO_MAXIMO" ]; do
      echo "(espera de cupo: ya hay $CUPO_MAXIMO clústeres de curso; reviso en 60 s)"; sleep 60
    done
  fi
  if [ "$RED_DOCKER" = kind ]; then
    kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  else
    KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED_DOCKER" \
      kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  fi
  [ "$(kubectl config current-context)" = "$CONTEXTO" ] || { echo "ALTO: contexto equivocado" >&2; exit 1; }
  kubectl wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
  kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name "$CLUSTER" >/dev/null 2>&1
}

for vuelta in 1 2; do
  printf '\n## Vuelta %s: clúster recién creado\n' "$vuelta"
  t0=$SECONDS; crear; echo "(crear el clúster y cargar las imágenes tardó $((SECONDS - t0)) s)"
  t0=$SECONDS
  printf '\n$ ./levantar.sh %s\n' "$CONTEXTO"
  ./levantar.sh "$CONTEXTO" 2>&1
  echo "(levantar.sh tardó $((SECONDS - t0)) s)"
  IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
  printf '\n$ curl -s http://%s/salud   # desde un contenedor fuera del clúster\n' "$IP_GW"
  docker run --rm --network "$RED_DOCKER" "$CURL_IMAGEN" -s -m 5 "http://$IP_GW/salud"; echo
  rm -f base/token.txt
  kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  echo "(clúster borrado)"
done
```

Les parties qui ne relèvent pas du déploiement, tu les as déjà vues : le `kubeconfig` temporaire, le `trap limpiar EXIT` qui **supprime le cluster même si le script échoue à mi-chemin** (un `trap … EXIT` s'exécute à la sortie du script, que ce soit parce qu'il s'est terminé ou à cause d'une erreur), et la vérification que `curso-k8s-l10` n'existe pas déjà avant de le créer. `limpiar` ne supprime qu'un cluster appelé exactement `curso-k8s-l10`, et le dossier temporaire seulement si son chemin commence par `/tmp/curso-k8s-l10.` (le `case` habituel).

Ce qui est vraiment nouveau, c'est `CUPO_MAXIMO`. Il est pour les machines partagées, et l'exécution de cette leçon l'a utilisé : avant de créer un cluster, il attend qu'il y ait moins de ce nombre de clusters `curso-k8s-*` en vie. Sans la variable, il n'attend pas. Sur ta machine, seule, tu n'en as pas besoin.

`probar-levantar.sh` utilise son propre `base/token.txt` (`levantar.sh` le génère s'il n'existe pas) et **le supprime à la fin** : si tu en as déjà un, sauvegarde-le avant ou laisse-le se régénérer.

La sortie complète du test, avec les deux tours :

```text
## Vuelta 1: clúster recién creado
(crear el clúster y cargar las imágenes tardó 39 s)

$ ./levantar.sh kind-curso-k8s-l10
== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?
primer IP del rango: 172.30.255.200 · IP del nodo de control: 172.30.0.4
== 1. Plataforma
objetos aplicados: 76
(paso 1 terminó a los 5 s)
== 2. Esperar a la plataforma
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
deployment.apps/controller condition met
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out
deployment.apps/envoy-gateway condition met
deployment.apps/metrics-server condition met
(paso 2 terminó a los 234 s)
== 3. Proyecto
objetos aplicados: 28
deployment.apps/revisor condition met
deployment.apps/prueba condition met
gateway.gateway.networking.k8s.io/revisor condition met
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.30.255.200   True         22s
(paso 3 terminó a los 256 s)
(levantar.sh tardó 256 s)

$ curl -s http://172.30.255.200/salud   # desde un contenedor fuera del clúster
{"estado":"vivo","version":"1.6.0"}

(clúster borrado)

## Vuelta 2: clúster recién creado
(crear el clúster y cargar las imágenes tardó 35 s)

$ ./levantar.sh kind-curso-k8s-l10
== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?
primer IP del rango: 172.30.255.200 · IP del nodo de control: 172.30.0.3
== 1. Plataforma
objetos aplicados: 76
(paso 1 terminó a los 4 s)
== 2. Esperar a la plataforma
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
deployment.apps/controller condition met
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out
deployment.apps/envoy-gateway condition met
deployment.apps/metrics-server condition met
(paso 2 terminó a los 250 s)
== 3. Proyecto
objetos aplicados: 28
deployment.apps/revisor condition met
deployment.apps/prueba condition met
gateway.gateway.networking.k8s.io/revisor condition met
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.30.255.200   True         61s
(paso 3 terminó a los 315 s)
(levantar.sh tardó 315 s)

$ curl -s http://172.30.255.200/salud   # desde un contenedor fuera del clúster
{"estado":"vivo","version":"1.6.0"}

(clúster borrado)
(la corrida completa tardó 1755 s)
```

Les deux tours disent la même chose, et c'est ce qu'on voulait prouver. L'étape 0 confirme que la plage commence à `172.30.255.200` et que le nœud de contrôle est en `172.30.0.x` (l'IP du nœud change d'un tour à l'autre : `.4` et `.3` ; la seule chose qui compte est le réseau). L'étape 1 applique **76** objets en environ 5 secondes. L'étape 2 est celle qui dure : de la seconde 5 à 234 au premier tour et de 4 à 250 au second (repères cumulés depuis le démarrage du script), c'est-à-dire que **presque tout le déploiement consiste à attendre** que les nœuds téléchargent des images et démarrent la plateforme. L'étape 3 applique **28** objets et attend : 22 secondes au premier tour et 65 au second (le Gateway marquait 22 s et 61 s d'âge à la fin : `AGE` est l'âge de l'objet au moment du `get`, non le temps écoulé jusqu'à `Programmed`). Chaque « paso N terminó a los X s » est le temps cumulé depuis le démarrage du script, non la durée de l'étape. `levantar.sh` a pris 256 et 315 secondes. Aux deux tours, le point d'entrée a pris `172.30.255.200`, `curl` depuis l'extérieur a répondu `{"estado":"vivo","version":"1.6.0"}`, et le cluster a été supprimé. Que le second tour, repartant de zéro à nouveau, passe tout aussi bien est l'**objectif 1** du cours : reconstruire sans rien corriger manuellement.

#### 10.6.4 À quoi cela ressemblerait dans un *pipeline*

Il n'est pas nécessaire d'avoir un *pipeline* pour cette leçon, mais il faut savoir comment il se brancherait, parce que c'est l'usage pour lequel le script est conçu. Une étape de *pipeline* de n'importe quel outil se réduit à quatre choses, et `levantar.sh` les a toutes :

1. **Une entrée explicite.** Le contexte (`kind-curso-k8s-l10`) est un argument, non une supposition. Dans un *pipeline* réel, ce serait le cluster auquel cette étape a des identifiants.
2. **Des identifiants minimaux.** Ce script crée des CRD et des *webhooks*, qui sont des objets de tout le cluster, donc il a besoin de permissions d'administrateur du cluster. Dans un environnement réel, on ne donne pas à un *pipeline* le compte de l'administrateur de tout : on lui donne un compte à lui (RBAC, Leçon 7) avec les permissions justes pour ce qu'il installe. Dans `kind`, il n'y a pas deux comptes, donc le cours ne le pratique pas, mais il le nomme.
3. **Un code de sortie honnête.** 0 si tout s'est terminé, différent de 0 sinon. C'est la seule information que le *pipeline* lit.
4. **Une sortie qu'on puisse lire après coup.** Les trois en-têtes `== 1.`, `== 2.`, `== 3.`, les comptages et les secondes par étape sont ce que quelqu'un lit à 7 h 50 un lundi quand l'étape 2 est passée au rouge.

Et ce que le script ne doit pas devenir : un endroit où s'accumulent des rustines. Si une étape se casse pour une cause nouvelle, on corrige la cause, on n'ajoute pas un `sleep`.

### 10.7 La vérification finale par rapport à `restricted`

#### 10.7.1 Ce que demande `restricted`, concrètement

La Leçon 2 a mis le `securityContext` dans le premier Deployment ; la 7 a mis le niveau `restricted` dans l'espace de noms. Il s'agit maintenant de vérifier, avec le cluster et non de mémoire, que **tout** ce qui est dans l'espace `revisor` le respecte. D'abord, ce qu'il exige. Les *Pod Security Standards* ([documentation](https://kubernetes.io/docs/concepts/security/pod-security-standards/)) définissent trois niveaux ; `restricted` est le plus strict et ajoute six contrôles à ceux de `baseline` :

| Contrôle de `restricted` | Ce qu'il exige (champ et valeur permise) | Où le projet le respecte |
|---|---|---|
| Types de volume | chaque volume est d'un type permis : `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected` ou `secret` | `emptyDir` et `secret` dans le `revisor` ; `persistentVolumeClaim` et `secret` dans le `CronJob` |
| Élévation de privilèges | `allowPrivilegeEscalation: false` dans chaque conteneur | le `securityContext` de chaque conteneur, dans les deux Deployments (`revisor` et `prueba`) et le `CronJob` |
| Exécuter en non-`root` | `runAsNonRoot: true` (dans le Pod ou dans chaque conteneur) | le `securityContext` du Pod |
| Utilisateur non-`root` | `runAsUser` différent de 0, ou non défini | 65532 dans le `revisor` et `prueba` ; 100 dans le `CronJob` |
| *Seccomp* | `seccompProfile.type` explicite : `RuntimeDefault` ou `Localhost` ; ni `Unconfined` ni absent | `RuntimeDefault`, dans le `securityContext` du Pod |
| Capacités | `capabilities.drop` inclut `ALL` ; on ne peut rajouter que `NET_BIND_SERVICE` | `drop: ["ALL"]` dans chaque conteneur |

(Les contrôles de `baseline` dont `restricted` hérite —pas de conteneurs privilégiés, pas de réseau de l'hôte, pas de `hostPath`, pas de ports de l'hôte, entre autres— sont respectés parce qu'aucun manifeste du projet ne demande rien de tel.)

Et maintenant, ce que **`restricted` ne demande pas** et que le projet fait malgré tout, pour que tu ne le confondes pas avec la norme :

- `readOnlyRootFilesystem: true`. Aucun des trois niveaux ne l'exige. Le projet le met parce qu'un système de fichiers qu'on ne peut pas écrire limite ce qu'un attaquant ferait à l'intérieur du conteneur, et c'est pourquoi le `revisor` conserve son rapport dans un volume et non dans `/`.
- `requests` et `limits` (Leçon 5), `automountServiceAccountToken: false` (Leçon 7), le `Secret` marqué immuable et monté comme fichier (Leçon 4), le réseau fermé (Leçon 7). Ce sont des décisions du projet, non des contrôles de `restricted`.

Distinguer les deux listes compte : « respecte `restricted` » est un fait que le cluster peut te confirmer avec une requête (la section suivante), et « suit les pratiques du cours » est un jugement que tu portes toi-même.

#### 10.7.2 Comment le cluster l'applique

Le niveau ne s'enseigne pas à chaque Pod : on le dit à l'**espace de noms**, avec des étiquettes. Voici ce que contient `base/namespace.yaml` :

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

La [documentation de *Pod Security Admission*](https://kubernetes.io/docs/concepts/security/pod-security-admission/) définit trois **modes**, chacun avec son étiquette : `enforce` (la violation **rejette** le Pod), `audit` (la violation laisse une annotation dans le journal d'audit, mais est permise) et `warn` (la violation produit un avertissement pour celui qui a appliqué, mais est permise). Chaque mode a en plus une étiquette `…-version` qui fige la politique à celle qui accompagnait une version de Kubernetes, ici la v1.37, pour qu'une mise à jour du cluster ne change pas les règles sous tes pieds sans que tu l'aies décidé.

Un détail qui explique ce que tu verras en 10.7.4 : selon la même documentation, les modes `audit` et `warn` s'appliquent aussi aux objets qui *créent* des Pods (Deployments, Jobs, CronJobs), « pour aider à détecter les violations tôt », mais `enforce` ne s'applique **pas** à ces objets, seulement aux Pods qui en résultent. Dit avec un exemple : un Deployment non conforme est *accepté* (avec un avertissement), et les Pods qu'il essaie de créer sont *rejetés*. Le Deployment reste donc existant avec zéro réplique, et c'est pourquoi il faut lire les avertissements d'`apply` et ne pas se fier à un « appliqué sans problème ».

#### 10.7.3 La vérification dans le cluster

D'abord, la requête que la [documentation](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) recommande avant de changer un niveau : `kubectl label --dry-run=server --overwrite`. La documentation explique que, lorsqu'une étiquette `enforce` (ou sa version) est **ajoutée ou modifiée**, le contrôleur d'admission teste chaque Pod de l'espace par rapport à la nouvelle politique et renvoie les violations sous forme d'avertissements, et qu'avec `--dry-run=server` ce test s'exécute sans rien appliquer. Tout dépend de « ajoutée ou modifiée ». La première chose qu'on écrit sur `revisor`, qui a déjà `enforce=restricted`, **ne change rien**, et c'est pourquoi (on l'a mesuré, plus bas) elle ne vérifie aucun Pod :

```text
$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)

$ kubectl get namespace revisor --show-labels
NAME      STATUS   AGE   LABELS
revisor   Active   83s   kubernetes.io/metadata.name=revisor,pod-security.kubernetes.io/audit-version=v1.37,pod-security.kubernetes.io/audit=restricted,pod-security.kubernetes.io/enforce-version=v1.37,pod-security.kubernetes.io/enforce=restricted,pod-security.kubernetes.io/warn-version=v1.37,pod-security.kubernetes.io/warn=restricted
```

`namespace/revisor not labeled (server dry run)` ne dit qu'une chose : l'étiquette était déjà celle-là et il n'y avait rien à changer. **Elle n'a vérifié aucun Pod**, donc ce n'est pas la preuve que le projet est conforme ; avec n'importe quel Pod à l'intérieur, elle aurait dit la même chose. Dans la seconde sortie, on voit les six étiquettes des trois modes, chacun avec sa version `v1.37`, plus celle que Kubernetes met tout seul (`kubernetes.io/metadata.name`).

**La requête qui vérifie vraiment ce qui existe déjà.** Si le niveau et la version se répètent, le serveur n'évalue pas ; si la politique **change**, il évalue. Alors, pour auditer un espace qui est déjà en `restricted:v1.37`, on lui demande une politique différente, sans l'appliquer : la même étiquette de version avec une autre valeur, par exemple `enforce-version=v1.36`. Le serveur teste chaque Pod par rapport à `restricted` de cette version (pas de la v1.37 : c'est une voisine, non la même) et rend compte. Comme une absence d'avertissements ne vaut rien sans un témoin, `psa-comprobacion.sh` le teste d'abord dans un espace d'essai, `psa-control`, avec deux Pods : `viola` (qui ne dit rien de sécurité) et `cumple` (qui respecte les six contrôles de `restricted`). On lui applique pour de bon `restricted:v1.37` et on répète les deux requêtes. Cela a été exécuté dans un cluster `curso-k8s-l10` de trois nœuds avec le projet appliqué (l'espace `revisor`) mais sans la plateforme, dont ce test n'a pas besoin :

```text
## El control: un espacio con un Pod que viola y otro que cumple

$ kubectl apply -f psa-control.yaml
namespace/psa-control created
pod/viola created
pod/cumple created

$ kubectl get pods -n psa-control
NAME     READY   STATUS    RESTARTS   AGE
cumple   1/1     Running   0          1s
viola    1/1     Running   0          1s

## Se le pone restricted de verdad: el servidor sí avisa, porque el nivel CAMBIA

$ kubectl label --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
Warning: existing pods in namespace "psa-control" violate the new PodSecurity enforce level "restricted:v1.37"
Warning: viola: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/psa-control labeled

## La consulta de antes: repetir el nivel que el espacio ya tiene

$ kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
namespace/psa-control not labeled (server dry run)

## La consulta que sí revisa: pedir otra versión de la política

$ kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce-version=v1.36
Warning: existing pods in namespace "psa-control" violate the new PodSecurity enforce level "restricted:v1.36"
Warning: viola: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/psa-control labeled (server dry run)

## Lo mismo sobre el espacio del proyecto

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
namespace/revisor not labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce-version=v1.36
namespace/revisor labeled (server dry run)

$ kubectl get pods -n revisor --no-headers | wc -l
       4
```

Lis-le de haut en bas. Quand on applique vraiment `restricted`, le serveur prévient et nomme **`viola`** (avec les quatre contrôles qu'il enfreint) et non `cumple`. Répéter le même niveau et la même version sur `psa-control` dit `not labeled`, **avec un Pod non conforme à l'intérieur** : c'est la requête qui ne vérifie pas. Demander `v1.36` prévient bien, et seulement pour `viola` : la requête vérifie, et distingue. Avec le témoin sous les yeux, le résultat sur `revisor` a de la valeur : répéter le niveau dit `not labeled` (sans information) et demander `v1.36` dit `labeled (server dry run)` **sans un seul avertissement** sur les 4 Pods de l'espace (les deux du `revisor`, celui de `prueba` et celui que le `CronJob` a laissé). Cela, c'est bien « le serveur a vérifié les Pods de `revisor` et aucun n'enfreint `restricted` ».

Une absence d'avertissements ne vaut que si tu sais que l'outil en donnerait ; cette vérification (le témoin ci-dessus, et le Deployment `malo` de 10.7.5) est déjà faite. Ensuite, la preuve champ par champ : le tableau de 10.7.1, mais lu sur les Pods vivants de l'espace (le jsonpath demande, pour chaque Pod, les champs que `restricted` examine) :

```text
$ kubectl get pods -n revisor -o jsonpath='{range .items[*]}{.metadata.name}{" noroot="}{.spec.securityContext.runAsNonRoot}{" seccomp="}{.spec.securityContext.seccompProfile.type}{" priv-esc="}{.spec.containers[0].securityContext.allowPrivilegeEscalation}{" drop="}{.spec.containers[0].securityContext.capabilities.drop}{" ro="}{.spec.containers[0].securityContext.readOnlyRootFilesystem}{" automount="}{.spec.automountServiceAccountToken}{"\n"}{end}'
prueba-6899c74865-rzh88 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-6m6s6 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-dq4pp noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
```

Trois Pods, trois lignes identiques : les deux du `revisor` et celui de `prueba` (si le `CronJob` s'est déjà déclenché, un quatrième apparaîtrait, avec les mêmes valeurs). Dans chacun : `noroot=true` (le Pod s'exécute en non-`root`), `seccomp=RuntimeDefault`, `priv-esc=false`, `drop=["ALL"]`, et en plus `ro=true` et `automount=false`, qui sont du cours et non de `restricted`. Seul le premier conteneur a été demandé (`containers[0]`), et chacun de ces Pods n'en a qu'un. Cette requête ne remplace pas le `dry-run` (qui vérifie tous les contrôles, pas seulement ceux que j'ai écrits dans le `jsonpath`) ; elle le complète : elle te permet de *voir* les valeurs.

#### 10.7.4 Une partie de la plateforme ne respecte pas `restricted`, et c'est acceptable (à une condition)

L'espace `revisor` est le seul à porter les étiquettes. Que dirait le serveur si tu les mettais aux espaces de la plateforme ? On pose la question avec la même requête, sans rien changer (`cut` tronque chaque ligne pour qu'elle tienne). Ici, la requête vérifie bien les Pods, parce que ces espaces n'ont pas l'étiquette et que la mettre est un changement. Autre différence avec la requête précédente : ces espaces n'ont pas d'étiquette de version, donc le serveur compare avec la version la plus récente de la politique (`restricted:latest`) et le dit dans le premier avertissement :

```text
$ kubectl label --dry-run=server --overwrite namespace envoy-gateway-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
namespace/envoy-gateway-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace metallb-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
Warning: existing pods in namespace "metallb-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: controller-76f4cf76b7-kclm8: unrestricted capabilities, seccompProfile
Warning: speaker-cbfnt (and 2 other pods): host namespaces, hostPort, probe or lifecycle host, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/metallb-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: coredns-559f6c778d-9fhdt (and 1 other pod): runAsNonRoot != true, seccompProfile
Warning: etcd-curso-k8s-l10-control-plane (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
Warning: kindnet-6qh25 (and 2 other pods): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: kube-proxy-6rwpd (and 2 other pods): host namespaces, privileged, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
namespace/kube-system labeled (server dry run)
```

Trois espaces, trois réponses différentes :

- **`envoy-gateway-system` : aucun avertissement.** Il dit « labeled (server dry run) » et rien de plus. Les Pods d'Envoy Gateway (le contrôleur et les Envoy qui desservent le point d'entrée) respectent `restricted`. C'est une information utile à savoir et qui n'est pas évidente : toute la plateforme ne demande pas des privilèges.
- **`metallb-system` : oui.** Le `controller` enfreint deux contrôles : « unrestricted capabilities » (il conserve des capacités Linux que `restricted` oblige à retirer) et « seccompProfile » (il ne déclare pas de profil). Les trois `speaker` en enfreignent davantage : « host namespaces » et « hostPort » (ils partagent le réseau du nœud), « probe or lifecycle host », « runAsNonRoot != true » et les mêmes capacités et profil. Le `speaker` est celui qui répond aux requêtes ARP du réseau (la couche 2 de 10.10, point 5) et, pour cela, il doit voir le réseau du nœud et non un réseau à lui : l'avertissement « host namespaces » est le nom technique de ce besoin.
- **`kube-system` : oui, et beaucoup.** Les deux `coredns` enfreignent `runAsNonRoot` et le profil `seccomp`. Les quatre Pods du plan de contrôle (`etcd` et ses trois compagnons) partagent le réseau de l'hôte et montent des chemins du nœud (les « restricted volume types »). `kindnet` et `kube-proxy` partagent le réseau de l'hôte et conservent des capacités, et `kube-proxy` s'exécute en plus en `privileged`.

(Le « (and 2 other pods) » vient du serveur : il regroupe les Pods qui enfreignent la même chose pour ne pas répéter la ligne.)

Ce n'est pas un défaut du cours : c'est ce qui se passe quand une pièce d'infrastructure a besoin de privilèges pour faire son travail (parler au réseau des nœuds, annoncer des adresses, monter des chemins du nœud). Le point est double. D'abord, **les privilèges existent et sont quelque part** : la plateforme les concentre dans ses propres espaces, et le projet, qui est ce qui change tous les jours, vit sans eux. Ensuite, ces espaces ont une **condition** : personne d'autre ne doit pouvoir y créer de Pods, parce que celui qui peut créer un Pod dans `metallb-system` ou `kube-system` a, de fait, les privilèges de cet espace. Dans un vrai cluster, cela se résout avec RBAC (qui peut créer quoi et où) et avec un niveau `baseline` ou `privileged` *déclaré* pour chaque espace de plateforme —une décision écrite, avec un responsable—, non avec un espace sans étiquette. Ici, on ne les étiquette pas, et 10.10 le note.

#### 10.7.5 Le témoin positif : un Deployment qui enfreint bien `restricted`

Pour savoir que « pas un seul avertissement » signifie quelque chose, on teste avec un Deployment qui **doit** en produire. `fig10_02.deployment-malo.yaml` est un **programme qui échoue à dessein** : un Deployment qui ne dit rien de la sécurité.

```yaml
# fig10_02.deployment-malo.yaml — FALLA A PROPÓSITO: un Deployment que NO cumple el
# nivel «restricted». No dice nada de seguridad: ni usuario, ni capacidades, ni
# perfil seccomp. En el espacio «revisor» el clúster avisa al aplicarlo y rechaza
# sus Pods. Se aplica con:  kubectl apply -n revisor -f fig10_02.deployment-malo.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: malo
  labels:
    app: malo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: malo
  template:
    metadata:
      labels:
        app: malo
    spec:
      containers:
      - name: malo
        image: curso-docker-prueba:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 9000
```

```text
$ kubectl apply -n revisor -f fig10_02.deployment-malo.yaml
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "malo" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/malo created

$ kubectl get deployment malo -n revisor
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
malo   0/1     0            0           8s

$ kubectl get events -n revisor --field-selector reason=FailedCreate -o custom-columns=RAZON:.reason,MENSAJE:.message | cut -c1-400 | head -3
RAZON          MENSAJE
FailedCreate   Error creating: pods "malo-89fb7566-9zgxl" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonR
FailedCreate   Error creating: pods "malo-89fb7566-wps2l" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonR
```

Trois choses dans cet ordre. **À l'application**, un `Warning` avec quatre contrôles enfreints : `allowPrivilegeEscalation != false`, `unrestricted capabilities`, `runAsNonRoot != true` et `seccompProfile`, chacun avec le champ exact qui manque (`container "malo" must set securityContext.allowPrivilegeEscalation=false`…). Et en dessous, `deployment.apps/malo created` : le Deployment **a bien été créé**. Deuxièmement, le Deployment est en `READY 0/1` : il n'a aucun Pod. Troisièmement, les événements du ReplicaSet : `FailedCreate`, « Error creating: pods "malo-…" is forbidden: violates PodSecurity "restricted:v1.37" », avec la même liste. C'est là qu'est intervenu le mode `enforce`, et on voit qu'il l'a fait à la création des Pods, non à celle du Deployment.

C'est ce qu'annonçait 10.7.2 : le Deployment *est accepté* (avec des avertissements, par le mode `warn`) et les Pods *sont rejetés* (par le mode `enforce`) ; le ReplicaSet enregistre chaque rejet comme un événement `FailedCreate`. Et c'est la raison de lire la sortie d'`apply`. On le supprime :

```text
$ kubectl delete -n revisor -f fig10_02.deployment-malo.yaml
deployment.apps "malo" deleted from revisor namespace
```

Avec cela, l'affirmation du projet tient avec un témoin : le projet ne produit pas d'avertissements (comptage 0 en 10.5.3), et un Deployment qui enfreint la politique en produit **bien**. L'Exercice 2 te demande de corriger celui-ci.

### 10.8 Tester les objectifs

Le README du cours se termine par sept objectifs : non pas « tu as lu les leçons » mais « ton projet remplit ceci ». Cette section vérifie dans le cluster ceux qui peuvent être mesurés. D'abord, la carte, pour que tu saches où se trouve chacun :

| Objectif | Ce qu'il dit | Où on le vérifie |
|---|---|---|
| 1 | depuis un cluster tout juste créé, le projet fonctionne en trois étapes, et se reconstruit après suppression | 10.5 (manuellement) et 10.6 (avec le script, deux tours) |
| 2 | l'espace de noms est en `restricted` et il n'y a pas d'avertissements à l'application | 10.5.3 et 10.7 |
| 3 | un nœud de travail est arrêté et le service continue de répondre, avec une fenêtre mesurée | 10.8.3 |
| 4 | changer la liste de services déclenche le *rollout* tout seul | 10.8.1 |
| 5 | avec de la charge, la mise à l'échelle monte et descend les répliques | mesuré à la Leçon 9 ; 10.8.4 vérifie qu'elle reste connectée |
| 6 | un Pod étranger ne parle pas au `revisor`, et le compte du `revisor` ne peut rien | 10.8.2 |
| 7 | tu sais dire, par écrit, cinq raisons pour lesquelles ceci n'est pas de la production | 10.10 et l'Exercice 4 |

#### 10.8.1 Objectif 4 : changer la liste change les répliques, sans toucher à l'image

C'est la Leçon 4 vue depuis la fin : la configuration vit hors de l'image. D'abord, l'état avant le changement : le ReplicaSet qui a les répliques et le `ConfigMap` généré avec son *hash*.

```text
$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-654b5d75dc   2         2         2       92s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      92s
revisor-config-t6cm6872fk   1      92s
```

On change le délai limite du service de test de `2s` à `1s` dans la base. `sed -i.bak` modifie le fichier sur place et laisse une copie avec l'extension `.bak` (la forme qui fonctionne de la même manière sous Linux et sous macOS) ; `diff` compare la copie avec le nouveau fichier pour que tu voies exactement ce qui a changé :

```text
$ sed -i.bak 's#http://prueba:9000/ 2s#http://prueba:9000/ 1s#' base/kustomization.yaml; diff base/kustomization.yaml.bak base/kustomization.yaml
29c29
<   - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s
---
>   - REVISOR_SERVICIOS=prueba http://prueba:9000/ 1s
[código de salida: 1]
```

```bash
ctx && kubectl apply --server-side -k overlays/kind
```

Ici, la commande filtre les deux lignes qui comptent :

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-cmb662hmbh serverside-applied
deployment.apps/revisor serverside-applied
```

On restaure le fichier (le `.bak` retrouve son nom) et on attend la fin du *rollout* :

```text
$ mv base/kustomization.yaml.bak base/kustomization.yaml && grep REVISOR_SERVICIOS base/kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-548956488d   2         2         2       5s
revisor-654b5d75dc   0         0         0       97s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      97s
revisor-config-cmb662hmbh   1      5s
revisor-config-t6cm6872fk   1      97s
```

Ce qui a changé : le `diff` montre une seule ligne, `2s` par `1s`. L'`apply` a appliqué deux objets : un `ConfigMap` **neuf**, `revisor-config-cmb662hmbh` (un autre *hash*, parce que le contenu est autre), et le Deployment, que le générateur a réécrit pour qu'il pointe vers lui. Le *rollout* a créé un nouveau ReplicaSet avec les deux répliques et a laissé l'ancien à `0 0 0`. Et ce qui n'a pas changé : l'image. `curso-docker-revisor:1.6.0` n'a pas été reconstruite, n'a pas été rechargée et n'a pas été touchée. L'ancien `ConfigMap` reste dans le cluster, sans que personne l'utilise : c'est le prix de la Leçon 4. `kube-root-ca.crt` n'est pas à toi : Kubernetes le crée dans chaque espace de noms.

Et comme le fichier dit de nouveau `2s`, le cluster doit revenir lui aussi. **Le fichier est la vérité** : si le cluster et les fichiers diffèrent, on corrige le cluster en appliquant de nouveau, on ne note pas « je sais que c'est différent » :

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-t6cm6872fk serverside-applied
deployment.apps/revisor serverside-applied

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-548956488d   0         0         0       11s
revisor-654b5d75dc   2         2         2       103s
```

En revenant au fichier d'origine, le `ConfigMap` qui s'applique est de nouveau `revisor-config-t6cm6872fk`, celui d'avant. Comme le modèle du Pod redevient identique à celui du premier ReplicaSet, le Deployment **le réutilise** : il remonte l'ancien de 0 à 2 et fait redescendre celui qu'il venait de créer, au lieu d'en monter un troisième. Il reste deux ReplicaSets, un actif et un à `0 0 0` ; ces ReplicaSets vides sont ce que `rollout undo` utilise pour revenir en arrière (Leçon 9).

#### 10.8.2 Objectif 6 : le réseau et les permissions

Deux petits tests, dans l'espace `revisor` : un Pod **avec** l'étiquette `acceso-revisor: permitido` (`depurar`) et un autre **sans** elle (`intruso`). Les deux sont des Pods de `curl` qui respectent déjà `restricted`, donc le cluster les accepte :

```bash
ctx && kubectl apply -n revisor -f depurar.yaml -f intruso.yaml
ctx && kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso --timeout=180s
```

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

Le premier est le témoin positif : sans lui, le second ne prouverait rien, parce qu'un `curl` qui échoue peut échouer pour mille raisons. `depurar` arrive (le réseau le laisse), `intruso` non. La lecture du code est la clé. `curl` sort avec **28** (*operation timed out*) : les 3 secondes du `-m 3` sont passées sans réponse. Si le réseau refusait la connexion, `curl` sortirait avec 7 (« impossible de se connecter »), comme à la Leçon 3. Une `NetworkPolicy` qui ne laisse pas passer un paquet **l'abandonne sans répondre**, et le client reste à attendre : c'est pourquoi le 28 est l'empreinte d'un réseau fermé et non d'un service en panne.

Et les permissions des comptes, avec `kubectl auth can-i`, qui demande au cluster si une identité pourrait faire quelque chose, sans le faire :

```text
$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador
yes

$ kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]
```

Quatre réponses, qu'un tableau résume : le compte `revisor` **ne peut pas** lire les Pods ni les Secrets (`no`, `no`) ; le compte `observador` **peut** lire les Pods (`yes`) et **ne peut pas** les supprimer (`no`). Le code de sortie de `can-i` est 1 quand la réponse est `no`, et c'est pourquoi le script note `[código de salida: 1]` sans qu'il y ait le moindre échec. Le compte du `revisor` n'a même pas d'identifiants montés (`automountServiceAccountToken: false`), donc la réponse est double : il ne peut pas, et même s'il le pouvait, le Pod n'a rien avec quoi appeler l'API.

#### 10.8.3 Objectif 3 : un nœud est arrêté et le service continue de répondre

C'est le test le plus proche de ce qui se passe dans un vrai cluster, et celui qui enseigne le plus. Un nœud de travail est un conteneur Docker ; l'arrêter avec `docker stop` ressemble à une machine qui s'éteint brusquement. On veut savoir trois choses : le service continue-t-il de répondre ? quelque chose échoue-t-il entre-temps ? combien de temps cela dure-t-il ?

**Avant de prédire, les chiffres du cluster.** La [documentation de l'état des nœuds](https://kubernetes.io/docs/reference/node/node-status/) décrit le mécanisme : chaque `kubelet` renouvelle l'objet `Lease` de son nœud **toutes les 10 secondes** (c'est le battement), le contrôleur de nœuds vérifie les battements **toutes les 5 secondes** (`node-monitor-period`), et la condition `Ready` passe à `Unknown` s'il n'a pas eu de nouvelles du nœud pendant `node-monitor-grace-period` : **50 secondes par défaut** (aussi comme valeur par défaut dans la [référence de `kube-controller-manager`](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)). Les 50 secondes se comptent depuis le **dernier battement que le contrôleur a reçu**, non depuis le `docker stop` : ce battement a pu arriver jusqu'à 10 secondes avant l'arrêt du nœud, et le contrôleur ne le remarque qu'à sa vérification suivante (jusqu'à 5 secondes plus tard). Somme faite, le cluster l'apprend entre environ 40 et environ 55 secondes après le `docker stop` ; comme la boucle de mesure démarre quelques secondes plus tard, depuis son horloge la fenêtre tombe quelques secondes plus tôt. Tant que le délai n'est pas écoulé, le cluster *ne sait pas* que le nœud est parti. Et la [documentation des *taints* et tolérances](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) dit que, lorsque le nœud est déjà `Unknown`, les Pods ne sont pas évincés immédiatement : par défaut, ils tolèrent la souillure « nœud injoignable » pendant **300 secondes** (`tolerationSeconds`), et ce n'est qu'alors qu'ils sont recréés sur un autre nœud.

La prédiction, donc : avec deux répliques (une par nœud de travail), quand on arrête un nœud, **en moyenne la moitié des requêtes** devrait échouer pendant cette fenêtre (des dizaines de secondes). La [documentation des Services](https://kubernetes.io/docs/reference/networking/virtual-ips/) dit que, dans les modes `iptables` et `nftables`, `kube-proxy` installe des règles qui choisissent par défaut le Pod de destination **au hasard** : ce n'est pas un tour de rôle strict, donc avec une vingtaine de requêtes, la proportion réelle peut s'éloigner de la moitié. Pendant ce temps, une adresse ne répond plus et le cluster ne le sait pas encore. Une fois la fenêtre passée, la réplique morte sort de la liste d'adresses et tout devrait passer.

L'expérience. Un détail avant : le test du *rollout* de 10.8.1 vient de remplacer les Pods, et les anciens mettent quelques secondes à disparaître. Pour ne pas mesurer avec des Pods qui s'en vont, on attend qu'il ne reste que les deux actuels (une autre boucle avec plafond, comme celle de la mise à l'échelle) :

```bash
for _ in $(seq 1 60); do
  [ "$(kubectl get pods -n revisor -l app=revisor --no-headers | wc -l | tr -d ' ')" = 2 ] && break
  sleep 2
done
```

Et maintenant, où sont les répliques, pour ne pas arrêter le nœud du Pod qui sert de client :

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          15s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          17s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

On choisit comme victime un nœud de travail qui n'est pas celui de `depurar` (le client qui va mesurer depuis l'intérieur du cluster), et on arrête son conteneur. La victime sort d'une liste de nœuds de travail moins celui du client ; la leçon utilise le `case` que tu connais déjà pour n'arrêter rien qui ne soit de ce cluster :

```bash
NODO_DEPURAR="$(kubectl get pod -n revisor depurar -o jsonpath='{.spec.nodeName}')"
VICTIMA="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name | sed 's#node/##' | grep -vx "$NODO_DEPURAR" | head -1)"
case "$VICTIMA" in curso-k8s-l10-*) ;; *) echo "ALTO: «$VICTIMA» no es un nodo de este clúster"; false ;; esac
docker stop "$VICTIMA"
```

```text
$ docker stop curso-k8s-l10-worker2
curso-k8s-l10-worker2
```

Et le client : une boucle dans `depurar` qui fait une requête toutes les 2 secondes pendant 90, avec une limite de 2 secondes chacune, et qui n'affiche que lorsque le résultat **change** (une ligne par changement, non une par requête) :

```bash
ctx && kubectl exec -n revisor depurar -- sh -c 'inicio=$(date +%s); ok=0; mal=0; ant=""; while [ $(( $(date +%s) - inicio )) -lt 90 ]; do t=$(( $(date +%s) - inicio )); if curl -s -m 2 -o /dev/null http://revisor/salud; then r=ok; ok=$((ok+1)); else r=FALLA; mal=$((mal+1)); fi; [ "$r" != "$ant" ] && echo "[+${t}s] $r"; ant=$r; sleep 2; done; echo "bien=$ok mal=$mal"'
```

(La boucle est écrite entre apostrophes pour que le `$(…)` soit interprété par le `sh` de l'*intérieur* du Pod et non par le tien. `date +%s` donne les secondes depuis 1970 ; la soustraction avec `inicio` est le temps écoulé ; `curl -m 2` abandonne au bout de 2 secondes.)

```text
[+0s] FALLA
[+4s] ok
[+6s] FALLA
[+22s] ok
[+31s] FALLA
[+51s] ok
bien=24 mal=10
```

Lis-le comme une ligne du temps (les lignes sont des *changements*, non des requêtes). Il commence en échec (`[+0s] FALLA`), répond de nouveau à 4 secondes, échoue à nouveau à 6 et ne répond pas avant 22 ; il répond jusqu'à 31, échoue encore jusqu'à 51, et **à partir de la seconde 51 tout répond** jusqu'à la fin des 90. À la fin : `bien=24 mal=10`, 34 requêtes, et les 10 échecs sont tous tombés avant la seconde 51. Cela coïncide avec le mécanisme ci-dessus : le cluster a mis le temps que mettent ses battements et son délai à s'en apercevoir. Avec ce qui ne coïncide pas parfaitement, c'est l'« alternance » : il y a des tronçons de plusieurs secondes d'échecs d'affilée, non un échec et un succès à tour de rôle. C'est ce que dit la documentation des Services : la destination est choisie **au hasard** à chaque connexion, donc de temps en temps plusieurs requêtes de suite partent vers l'adresse morte. (Chaque requête échouée coûte en plus 2 secondes de limite, c'est pourquoi il tient moins de requêtes dans la fenêtre que pendant le reste du test.) Il ne faut pas non plus prendre 51 pour une constante : dans les trois autres exécutions de préparation de la leçon (conservées dans `programas/10-proyecto-final/corridas-preparacion/`), le service a répondu de nouveau sans échec à 36, 50 et 34 secondes. Les quatre fenêtres, de 34 à 51 secondes, sont ce que prédit le mécanisme : elles dépendent de l'ancienneté du dernier battement quand le nœud s'est arrêté (de 0 à 10 secondes), de la vérification du contrôleur (toutes les 5) et des secondes qui s'écoulent entre le `docker stop` et le premier essai de la boucle. La [Leçon 9](09-escalar-y-actualizar.md) (9.12.2) a mesuré le même mécanisme sous un autre angle : le nœud est passé à `NotReady` à 57 secondes de l'arrêt. Ce qui se maintient d'une exécution à l'autre, c'est l'ordre de grandeur : des dizaines de secondes, non des minutes.

Et l'état du cluster à cet instant, **avant** de relancer le nœud :

```text
$ kubectl get nodes
NAME                          STATUS     ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready      control-plane   6m46s   v1.37.0
curso-k8s-l10-worker          Ready      <none>          6m35s   v1.37.0
curso-k8s-l10-worker2         NotReady   <none>          6m34s   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          106s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          108s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>

$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]}{" listo="}{.conditions.ready}{"\n"}{end}'
10.244.1.7 listo=true
10.244.2.7 listo=false
```

Trois données qui semblent se contredire et ne le font pas. Le nœud `curso-k8s-l10-worker2` est `NotReady` : le cluster l'a déjà donné pour perdu. Mais le Pod qui y vit apparaît toujours comme `1/1 Running` : le cluster continuera de le lister jusqu'à épuisement des 300 secondes de tolérance, et ce n'est qu'alors qu'il le recréera sur un autre nœud. Et l'`EndpointSlice` du Service marque déjà l'adresse de ce Pod (`10.244.2.7`) avec `listo=false` : il **a cessé de recevoir du trafic** même si la liste des Pods l'affiche encore. La leçon pratique est que `READY 1/1` dans `kubectl get pods` et « reçoit du trafic » ne sont pas la même chose ; pour savoir si un Pod reçoit des requêtes, on regarde l'`EndpointSlice` (Leçon 3).

On relance le nœud et on attend qu'il revienne :

```text
$ docker start curso-k8s-l10-worker2
curso-k8s-l10-worker2

$ kubectl wait --for=condition=Ready node/curso-k8s-l10-worker2 --timeout=180s
node/curso-k8s-l10-worker2 condition met

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready    control-plane   6m48s   v1.37.0
curso-k8s-l10-worker          Ready    <none>          6m37s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          6m36s   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          108s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          110s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

Le changement du compteur de redémarrages met du temps à apparaître. Regarde le compteur un instant après que le nœud est revenu à `Ready` (ci-dessus, `RESTARTS`), attends qu'il enregistre le redémarrage avec une autre boucle avec plafond et regarde à nouveau :

```bash
for _ in $(seq 1 36); do
  [ "$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | grep -vc '^0$')" -ge 1 ] && break
  sleep 5
done
```

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS     AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   1 (7s ago)   113s   10.244.2.5   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0            115s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>

$ kubectl get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name}{" reinicios="}{.status.containerStatuses[0].restartCount}{" último fin: "}{.status.containerStatuses[0].lastState.terminated.reason}{" código "}{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}{end}'
revisor-654b5d75dc-qcqfz reinicios=1 último fin: Unknown código 255
revisor-654b5d75dc-xmvc5 reinicios=0 último fin:  código 
```

Le nœud revient à `Ready`, et la première liste de Pods trompe : elle dit encore `RESTARTS 0` et l'IP d'avant (`10.244.2.7`). Quelques secondes plus tard, le compteur change bien : le Pod `…-qcqfz` dit `1 (7s ago)` et, de plus, **il a une autre IP** : `10.244.2.5`. C'est le même Pod, avec le même nom, mais son conteneur a redémarré et son adresse a changé. La requête sur `lastState` l'explique : le dernier arrêt du conteneur a pour raison `Unknown` et pour code `255`, c'est-à-dire que ni une probe ni un `OOMKilled` ne l'a tué ; il a disparu avec son nœud, qui s'est éteint tout entier, et personne n'a pu enregistrer un code de sortie normal. L'autre réplique, celle du nœud qui n'a jamais été arrêté, est restée à zéro redémarrage. Deux conséquences pour toi : un compteur de redémarrages différent de zéro ne signifie **pas** toujours que quelque chose a échoué dans ton programme (ici, c'était le nœud), et une IP de Pod ne se garde pas pour plus tard, ce qui est de nouveau la Leçon 3.

**Ce qui réduit cette fenêtre et ce qui ne la réduit pas.** Avec ce que tu as mesuré, la réponse honnête :

- **Plus de répliques, réparties entre davantage de nœuds.** Si au lieu de deux il y en a six réparties sur trois nœuds, arrêter un nœud touche une part moindre des requêtes. C'est ce que la mise à l'échelle et la répartition de la Leçon 9 font déjà : elles ne raccourcissent pas la durée, elles réduisent la proportion.
- **Des nouvelles tentatives côté client.** Une requête qui échoue et qu'on répète tombe, avec une bonne probabilité, sur l'autre réplique. Le client de ce test ne réessaie pas à dessein, pour que tu voies l'effet brut ; un client réel devrait le faire.
- **Un `node-monitor-grace-period` plus court**, dans le plan de contrôle, qui raccourcit la fenêtre en échange de plus de fausses alertes (un nœud avec un accroc réseau de quelques secondes serait donné pour perdu). Dans un cluster géré, on le demande au fournisseur ; dans `kind`, tu ne le changes pas dans cette leçon.

Et ce qui ne la raccourcit **pas**, même si cela y ressemble :

- **Les probes.** Elles sont exécutées par le `kubelet` du nœud lui-même, qui est justement celui qui a cessé d'exister. Une probe ne peut pas signaler l'absence du programme qui l'exécute.
- **`tolerationSeconds`.** Il décide au bout de combien de temps les Pods sont *recréés* sur un autre nœud, non quand ils cessent de recevoir du trafic. Le raccourcir fait recréer plus tôt, mais le trafic continuerait d'aller vers l'adresse morte jusqu'à ce que le nœud soit donné pour perdu.

Une phrase qui vaut résumé : le cluster tolère qu'un nœud tombe en panne, **pas qu'il tombe en panne sans que personne le remarque pendant des dizaines de secondes**. C'est la différence entre « survit » et « sans coupure », et c'est pourquoi l'objectif du cours dit « avec une fenêtre mesurée ».

#### 10.8.4 Objectif 5 : la mise à l'échelle reste connectée

Mesurer combien de temps la mise à l'échelle met à monter et à descendre avec de la charge occupe 15 minutes et une leçon entière : c'est la Leçon 9, et on ne la répète pas ici. Ce qu'on vérifie, c'est que, dans le cluster déployé à partir de zéro, elle **reste connectée aux métriques** :

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          3m32s
```

Dans cette exécution, juste après le redémarrage du nœud, la mise à l'échelle a dit `cpu: <unknown>/50%` : elle avait perdu la lecture des métriques. On n'a pas cherché sur quel nœud tourne `metrics-server` ni pourquoi elle a été interrompue ; ce qui est mesuré, c'est qu'un nœud redémarré a laissé la mise à l'échelle sans données pendant un moment. (Dans d'autres exécutions de préparation de la leçon, cela n'est pas arrivé : elle affichait déjà le pourcentage.) C'est un exemple de la raison pour laquelle le `<unknown>` ne s'interprète pas sans regarder ce qui vient de se passer dans le cluster.

Si dans ton cluster il dit `<unknown>`, ne t'alarme pas encore : c'est la cause de la Leçon 9 et elle se résout en attendant, mais avec un plafond. La même boucle que celle de 10.5.3, qui vérifie toutes les 5 secondes pendant trois minutes au plus :

```bash
for _ in $(seq 1 36); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: 3%/50%   2         6         2          4m33s
```

La boucle a attendu et la mise à l'échelle s'est rétablie toute seule : `cpu: 3%/50%`, `MINPODS 2`, `MAXPODS 6` et deux répliques. Entre les deux `get`, un peu plus d'une minute s'est écoulée (la colonne `AGE` va de 3m32s à 4m33s). Avec cela, l'objectif 5 est vérifié dans ce que cette leçon peut vérifier : la mise à l'échelle est connectée aux métriques et ses limites sont celles de la base. Monter et descendre des répliques avec de la charge, c'est la Leçon 9.

Et si la boucle abandonne et continue de dire `<unknown>`, l'autre cause que tu as vue à la Leçon 9 est `metrics-server` sans l'option `--kubelet-insecure-tls` (dont `kind` a besoin).

### 10.9 Helm, en une mention

Il existe un outil que tu verras dans presque n'importe quel projet Kubernetes et que ce cours n'utilise pas : **Helm**. La [documentation de Helm](https://helm.sh/docs/intro/using_helm/) l'appelle un gestionnaire de paquets pour Kubernetes. Quatre mots qu'il convient de reconnaître : un **chart** est un paquet (un dossier de modèles de manifestes plus leurs valeurs par défaut) ; les **values** sont les valeurs que tu changes pour ton installation ; une **release** est une installation concrète d'un chart dans un cluster ; et un **dépôt** (ou un registre d'images OCI) est l'endroit où ils sont publiés.

L'exemple se trouve dans le guide d'Envoy Gateway que tu connais déjà. En plus de l'installer avec le `install.yaml` qu'utilise le cours, [ce guide](https://gateway.envoyproxy.io/docs/install/install-helm/) l'installe avec Helm ainsi (la commande est celle du guide pour la version v1.9.2 ; **elle n'a pas été exécutée dans cette leçon**) :

```text
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.9.2 -n envoy-gateway-system --create-namespace
```

`eg` est le nom de la *release*, `oci://docker.io/envoyproxy/gateway-helm` est le chart et `--version` fige sa version, avec `--create-namespace` pour créer l'espace où il s'installe.

Pourquoi le cours utilise-t-il Kustomize et non Helm ? Parce qu'il compare deux idées différentes, et que pour apprendre il vaut mieux voir d'abord la plus simple :

| | Kustomize | Helm |
|---|---|---|
| Idée | part d'un YAML complet et **le modifie** avec des couches | part de **modèles** avec des trous et les **remplit** avec des valeurs |
| Ce que tu lis | du YAML normal ; ce que tu vois est ce qui est appliqué | des modèles avec de la logique ; pour voir le résultat, `helm template` |
| Changements entre environnements | overlays et correctifs | fichiers de valeurs (`values`) |
| Ce qu'il fait de plus | rien : il assemble et remet à `kubectl` | tient l'historique des *releases*, met à jour et peut revenir à une version antérieure |
| Fourni avec `kubectl` | oui (`kubectl kustomize`, `apply -k`) | non : c'est un programme à part |

Une règle pratique très utilisée, qui est ici une opinion et non une norme : **Kustomize pour ce qui est à toi, Helm pour ce qui est aux autres.** Ce qui est à toi, c'est du YAML que tu as écrit et que tu veux lire ; ce qui est aux autres (MetalLB, Envoy Gateway, une supervision) est généralement publié sous forme de chart avec des dizaines d'options auxquelles quelqu'un d'autre a déjà pensé. Beaucoup d'équipes utilisent les deux : elles installent la plateforme avec Helm et leur projet avec Kustomize.

Et le problème de cette leçon existe là aussi. Les [bonnes pratiques de Helm sur les CRD](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) disent que les CRD d'un chart s'installent en premier (ils vivent dans un dossier spécial, `crds/`), que **Helm ne les met pas à jour et ne les supprime pas** à cause du risque de perdre des données, et que si un chart doit utiliser les types qu'il définit lui-même, le plus commode est de les séparer en deux charts qui s'installent séparément. C'est le même ordre —types, contrôleur, projet— sous un autre nom.

### 10.10 Ce qui change dans un vrai cluster

#### 10.10.1 Ce que tu as construit et ce qui lui manque

Il y a une tentation à la fin d'un cours : croire que ce qui fonctionne sur ta machine est « presque » prêt à tourner pour de vrai. Cette section existe pour la désarmer avec honnêteté, sans dramatisme. `kind` fait bien ce qu'il promet : prouver que tu **comprends** Kubernetes. Sa propre page dit qu'il a été « conçu principalement pour tester Kubernetes lui-même », même s'il peut servir au développement local ou à l'intégration continue. Il ne promet pas un cluster qui supporte ce qu'exige un vrai service. La [documentation de Kubernetes sur les environnements de production](https://kubernetes.io/docs/setup/production-environment/) s'ouvre sur une phrase qui résume la différence (traduit) : un environnement de production typique « a plus d'exigences qu'un environnement personnel d'apprentissage, de développement ou de test ».

La liste qui suit compte quatorze points. Tu n'as pas besoin de tous les retenir ; il faut que tu reconnaisses le motif : presque chacun est une pièce qui **dans `kind` existe en version de laboratoire** et qu'il faut, dans un vrai cluster, remplacer, renforcer ou ajouter. Chacun dit ce que fait le cours, ce qu'exige un vrai cluster, ce qu'on ferait, et d'où cela vient.

**1. Un plan de contrôle à un seul nœud.** Le cours a un seul nœud de contrôle. S'il s'arrête, tu ne peux rien changer, et ce qui cesse d'autre de fonctionner n'est pas sûr : dans l'Exercice 3, les conteneurs déjà démarrés ont continué de tourner, mais le point d'entrée n'a continué de répondre que dans 1 exécution sur 4. Un vrai cluster réplique le plan de contrôle sur plusieurs nœuds et répartit la charge vers le serveur d'API ; la [documentation des environnements de production](https://kubernetes.io/docs/setup/production-environment/) énumère justement ces pièces, et rappelle qu'un environnement sur une seule machine « a un point de défaillance unique ». Beaucoup d'équipes préfèrent un plan de contrôle géré par un fournisseur.

**2. Un `etcd` sans sauvegarde testée.** Tout l'état du cluster —les objets que tu as appliqués— vit dans `etcd`. S'il est perdu, le cluster est perdu. Le [guide d'exploitation d'`etcd`](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) enseigne comment obtenir une copie avec `etcdctl snapshot save` et comment la vérifier avec `etcdutl snapshot status`. Et ici revient le cas de GitLab de l'ouverture : la sauvegarde qui n'a pas été restaurée lors d'un exercice n'est pas une sauvegarde. On la planifie, et on la **restaure pour de bon** dans un cluster de test avec une périodicité que quelqu'un décide.

**3. Des secrets stockés sans chiffrement.** Tu l'as vu à la Leçon 4 : un `Secret` est du base64, et dans `etcd` il est stocké en clair, sauf si l'administrateur configure le chiffrement au repos. Le [guide du chiffrement des données au repos](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) explique comment le configurer dans le `kube-apiserver`, et la [liste de vérification de sécurité](https://kubernetes.io/docs/concepts/security/security-checklist/) le demande : « le chiffrement au repos est configuré pour l'API des Secrets ». Pour les secrets qui ne devraient pas vivre dans le cluster, la même liste mentionne de les injecter depuis un magasin externe.

**4. Du HTTP en clair.** Le point d'entrée du `revisor` parle HTTP sur le port 80, et le token voyage dans un en-tête non chiffré (la Leçon 6 l'a mesuré). Un vrai cluster termine TLS dans le *Gateway* : le [guide TLS de Gateway API](https://gateway-api.sigs.k8s.io/guides/tls/) décrit comment un *listener* HTTPS termine le chiffrement avec un certificat. Il faut en outre l'émettre et le renouveler, et la liste de sécurité s'interroge sur le chiffrement à l'intérieur du cluster (qui dépend du CNI ou d'un maillage de services).

**5. Une adresse que MetalLB attribue dans un réseau Docker.** En couche 2, la [documentation de MetalLB](https://metallb.io/concepts/layer2/) le dit : tout le trafic d'une IP va vers **un seul nœud**, et de là `kube-proxy` le répartit. « En ce sens, la couche 2 n'implémente pas un équilibreur de charge : elle implémente un mécanisme de *failover*. » Ses deux limites sont un goulot d'étranglement sur un nœud et une bascule potentiellement lente. Dans le cloud, l'équilibreur est fourni par le fournisseur ; dans un centre de données à soi, on utilise généralement MetalLB en mode BGP ou un autre équilibreur.

**6. `metrics-server` avec `--kubelet-insecure-tls`.** Tu l'as vu en 10.3.4 : « uniquement pour les tests », dit son propre README. Dans un vrai cluster, les certificats des `kubelet` sont signés par l'autorité du cluster et l'option est superflue. Son README ajoute quelque chose qui compte : `metrics-server` sert **uniquement** à la mise à l'échelle automatique ; pour la supervision, on utilise autre chose.

**7. Des nœuds qui sont des conteneurs sur ta machine.** Les trois « nœuds » partagent ton processeur, ta mémoire, ton disque et ton noyau. Si ton ordinateur s'éteint, tout s'éteint ; il n'y a ni zones de disponibilité ni centres de données distincts. Un vrai cluster répartit les nœuds entre des zones et répartit les répliques entre elles (le correctif de `ejemplo-nube` en 10.3.3 change justement cela, des nœuds aux zones), et il a plus d'un exemplaire de tout ce qui compte.

**8. Un stockage qui vit sur le nœud.** Le volume du rapport est un répertoire du disque d'un nœud (`local-path`, Leçon 8) : si le nœud s'en va, les données aussi. Un vrai cluster utilise un stockage externe avec réplication et copies, et les données ont la même histoire de sauvegarde qu'`etcd` : il y a une copie, et il y a un exercice de restauration.

**9. Des images chargées manuellement.** Les deux images du cours sont arrivées avec `kind load docker-image`, avec un tag local. Un vrai cluster les télécharge depuis un registre. La [liste de sécurité](https://kubernetes.io/docs/concepts/security/security-checklist/) demande de s'y référer **par empreinte `sha256`** (parce qu'un tag peut être déplacé dans le registre), de les examiner avec un scanner de vulnérabilités et de vérifier leur signature avec un contrôleur d'admission. Le cours fige déjà l'empreinte de l'image de `curl` ; celles du `revisor` et de l'image de test, qui sont locales, non.

**10. Un seul administrateur et aucune identité.** Ton `kubeconfig` de `kind` est celui d'un administrateur total ; personne d'autre n'entre. Un vrai cluster a des utilisateurs et des groupes avec des permissions différentes, un fournisseur d'identité et une revue périodique des accès. La liste de sécurité demande, par exemple, que le groupe `system:masters` ne soit pas utilisé pour authentifier des personnes ni des composants après le démarrage, et une revue des accès « pas plus de 24 mois » entre deux revues.

**11. Une observabilité qui se résume à `kubectl logs`.** Tu as un journal tant que le Pod existe. La [documentation du *logging*](https://kubernetes.io/docs/concepts/cluster-administration/logging/) l'explique clairement (traduit) : si un conteneur tombe en panne, qu'un Pod est évincé ou qu'un nœud meurt, tu veux continuer à voir ses journaux ; c'est pourquoi ils doivent avoir un stockage « avec un cycle de vie indépendant des nœuds, des Pods et des conteneurs », et Kubernetes « ne fournit pas de solution native » pour cela. Il manque aussi la partie des métriques historiques et des alertes : quelqu'un qui te prévient avant que la direction ne le découvre.

**12. Des mises à jour sans plan.** Le cluster du cours se crée et se supprime ; un vrai cluster se met à jour à chaud, pendant des années. La [politique des versions prises en charge](https://kubernetes.io/releases/version-skew-policy/) dit que le projet maintient les trois versions mineures les plus récentes (aujourd'hui 1.37, 1.36 et 1.35), avec environ un an de correctifs, et fixe quel écart peut exister entre les composants (un `kubelet` peut avoir jusqu'à trois versions mineures de retard sur le serveur d'API, jamais d'avance). Et chaque pièce de la plateforme a son propre ordre de mise à jour : le guide d'Envoy Gateway demande de mettre à jour d'abord les CRD de Gateway API, et prévient de ce qui arrive si on ne le fait pas.

**13. Pas de quotas ni de limites par équipe.** La Leçon 5 a mis des `requests` et des `limits` dans chaque conteneur, mais rien n'empêche quelqu'un de créer cent Pods. La [documentation des quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) décrit le `ResourceQuota` : des restrictions sur la consommation totale **par espace de noms**, et sur le nombre d'objets de chaque type. Avec plusieurs équipes dans un cluster, c'est ce qui évite que l'une avale ce qui revient aux autres.

**14. Une plateforme sans responsable ni niveau de sécurité déclaré.** 10.7.4 l'a montré : les espaces de MetalLB et de `kube-system` ne respectent pas `restricted` (celui d'Envoy Gateway, lui, les respecte), et ici aucun des trois n'a d'étiquette ni de responsable. Dans un vrai cluster, chaque espace de plateforme a un niveau déclaré et une équipe responsable, et les *webhooks* de cette plateforme sont une **dépendance du cluster** : comme la `failurePolicy` par défaut est `Fail` (10.4.1), si le Pod du gardien est en panne, les objets qu'il surveille ne peuvent pas être créés. C'est pourquoi on leur donne plus d'une réplique et on les surveille comme n'importe quel service critique.

Rien de tout cela ne rend inutile ce que tu as construit. Au contraire : le projet de cette leçon, la base, avec tous ses objets, **est** ce qu'on emporterait dans un vrai cluster. Ce qui change, c'est la couche du dessous —l'overlay et la plateforme—, et c'est justement la couche que Kustomize sépare.

#### 10.10.2 Les quatorze, dans un tableau

| # | Dans le cours | Dans un vrai cluster |
|---|---|---|
| 1 | un nœud de contrôle | plusieurs nœuds de contrôle, ou un nœud géré |
| 2 | `etcd` sans sauvegarde | copies d'`etcd` avec des exercices de restauration |
| 3 | `Secret` non chiffré dans `etcd` | chiffrement au repos et/ou magasin externe de secrets |
| 4 | HTTP sur le port 80 | TLS terminé dans le Gateway |
| 5 | MetalLB en couche 2 sur un réseau Docker | équilibreur du fournisseur, ou MetalLB avec BGP |
| 6 | `--kubelet-insecure-tls` | certificats de `kubelet` signés par le cluster |
| 7 | nœuds qui sont des conteneurs | nœuds dans plusieurs zones, avec des répliques réparties entre elles |
| 8 | volume sur le disque d'un nœud | stockage externe répliqué, avec copies |
| 9 | images chargées manuellement | registre, empreinte `sha256`, analyse et signature |
| 10 | un administrateur | identités, groupes, revue des accès |
| 11 | `kubectl logs` | journaux et métriques avec stockage propre et alertes |
| 12 | cluster jetable | plan de mise à jour par version |
| 13 | pas de quotas | `ResourceQuota` par espace |
| 14 | plateforme sans niveau déclaré | niveau et responsable par espace, et répliques pour les *webhooks* |

Si tu devais ordonner cette liste selon « ce qui m'inquiéterait en premier », il n'y a pas de réponse unique : cela dépend de ce que tu perds si cela échoue. Mais un critère raisonnable est de commencer par ce qui **ne peut pas être reconstruit**. Le projet peut être reconstruit (tu viens de le faire, deux fois) ; les données du rapport et l'état d'`etcd`, non. C'est pourquoi la sauvegarde avec restauration éprouvée (les points 2 et 8) passe généralement avant presque tout le reste, et le chiffrement et le TLS (les points 3 et 4) vont avec ce qui est exposé. L'Exercice 4 te demande justement cela.

## L'erreur que tu vas voir

Cette leçon contient trois erreurs à dessein, et tu les as déjà vues dans leur section : la plateforme appliquée sans `--server-side` (10.4.3), la plateforme et le projet réunis dans une seule commande (10.4.4) et un Deployment qui enfreint `restricted` (10.7.5). Les trois ont un point commun qu'il convient de dire en toutes lettres, parce que c'est ce qu'on apprend vraiment : **aucune n'est une erreur du cluster**. Le cluster a fait exactement ce qu'on lui demandait et a dit clairement pourquoi il ne pouvait pas. Ce qui a changé entre la tentative échouée et celle qui a réussi, c'est *l'ordre ou la manière de demander*, non le cluster.

L'ordre pour lire n'importe laquelle d'entre elles est le même que dans les leçons précédentes, maintenant avec les outils de celle-ci :

1. Que dit le **code de sortie** de l'`apply` et quelles lignes **ne** sont **pas** un `created` ou un `serverside-applied` ? C'est là qu'est le message.
2. Le message mentionne-t-il un **type qui n'existe pas** (`no matches for kind`, `ensure CRDs are installed first`) ou un **gardien qui ne répond pas** (`failed calling webhook`) ? Alors il faut attendre la plateforme : une attente par condition, non une nouvelle tentative.
3. Mentionne-t-il une **taille** ou un **conflit de gestionnaire** (`Too long`, `conflict`) ? Alors cela tient à la manière d'appliquer : `--server-side`.
4. Est-ce un **avertissement** (`Warning: would violate PodSecurity`) ? L'objet a été accepté et ne fonctionnera pas : corrige le manifeste.

Et avant de changer quoi que ce soit, appliquer la même commande une seconde fois pour « voir si ça passe » **n'est pas un diagnostic** : 10.4.4 t'a montré que parfois cela passe à moitié et laisse le pire, un état qui a l'air sain et ne l'est pas.

## L'habitude de sécurité de la leçon : on vérifie par rapport à la norme, et on dit ce qui manque

Le tableau des habitudes du cours assigne à cette leçon deux choses : la vérification finale par rapport au niveau `restricted` et la liste de ce qu'exige un vrai cluster. Les deux sont des habitudes de **ne pas se fier à ce qui paraît**.

**La vérification avec témoin.** Une requête qui dit « sans avertissements » ne vaut rien à elle seule, parce qu'un outil qui ne vérifie pas et un outil qui vérifie et ne trouve rien disent la même chose. C'est pourquoi 10.5.3 compte les avertissements (`grep -ci warning`), 10.7.5 applique un Deployment qui **doit** en produire et 10.7.3 teste la requête de vérification dans un espace avec un Pod non conforme : la première requête écrite sur `revisor` donnait zéro avertissement et ne vérifiait rien, et c'est ce témoin qui l'a montré. Si le second cas n'avait pas produit d'avertissements, le premier n'aurait rien signifié. C'est le même principe que pour mesurer n'importe quoi : avant de croire un zéro, montre-lui quelque chose qui devrait compter.

**La liste de ce qui manque.** C'est la seconde habitude et la plus inconfortable : écrire ce que tu n'as *pas*. Un projet qui dit « respecte `restricted` » et passe sous silence que son `etcd` n'a pas de sauvegarde donne une idée fausse de son niveau de protection. La liste de 10.10 n'est pas une excuse ; c'est le document qui permet à celui qui prend les décisions de savoir quel risque il court.

**Ce qu'elle protège et ce qu'elle ne protège pas.** La vérification par rapport à `restricted` protège contre une configuration négligée : un conteneur qui démarre en `root`, qui peut gagner des privilèges ou qui conserve des capacités dont il n'a pas besoin. Elle ne protège pas contre une vulnérabilité dans le programme du `revisor`, contre un token qui fuit, ni contre une image manipulée en chemin. Et la liste de 10.10 te dit ce qu'il faudrait de plus, mais elle ne l'installe pas : nommer un manque n'est pas le résoudre.

## Les erreurs courantes

**Réessayer jusqu'à ce que ça passe.** C'est la boucle `until kubectl apply …; do sleep 5; done`. Elle cache la cause, laisse parfois un état à moitié fait, et le jour où elle échoue pour de bon, elle tourne en rond en silence. On attend la condition, avec un plafond.

**Un `sleep` fixe entre la plateforme et le projet.** Il fonctionne sur ta machine et échoue sur une machine plus lente ou plus chargée. Un `sleep` mesure l'horloge ; `kubectl wait` mesure la condition.

**Réunir plateforme et projet dans un seul `kustomization`.** Cela semble plus ordonné et rompt l'ordre (10.4.4). Les deux moitiés ont des conditions de sortie différentes, et c'est pourquoi ce sont des commandes différentes.

**Appliquer la plateforme sans `--server-side`.** Les gros CRD ne tiennent pas dans l'annotation que conserve le client (10.4.3). Le guide officiel d'Envoy Gateway apporte déjà l'option.

**Un overlay qui copie la base.** Si tu copies les fichiers de la base dans le dossier de l'overlay « pour y changer une ligne », tu as deux copies qui vont diverger. Un overlay pointe (`resources: ../../base`) et corrige.

**Un script qui utilise « le cluster actif ».** Il installe des choses dans le contexte qui est à portée de main, qui peut ne pas être le tien. Le contexte attendu se passe en argument et se vérifie avant chaque étape.

**`|| true` pour que rien ne s'arrête.** Un script qui ne s'arrête pas devant une erreur ne te dit pas qu'il y en a eu une. Si un échec est acceptable, on traite ce cas et on dit lequel.

**Dire « sans erreurs » sans l'avoir mesuré.** Ou « sans avertissements » sans un cas qui en produise. Une affirmation d'absence a besoin d'un témoin positif.

**Des versions non figées.** Une adresse qui pointe vers « la dernière version » change toute seule. Toutes les pièces de cette leçon portent leur version dans le chemin, et les images de `curl` leur empreinte.

**Versionner le token.** Il est factice, mais c'est l'habitude qui compte : le `.gitignore` et le `umask 077`.

**Étiqueter avec `enforce: restricted` un espace de plateforme sans l'avoir vérifié.** 10.7.4 l'a montré : MetalLB et `kube-system` ont des Pods que `restricted` rejetterait. Un `dry-run` avant l'étiquette évite de casser le réseau d'un cluster.

**Prendre `kind` pour un vrai cluster.** C'est celle que 10.10 développe en quatorze points, et celle qui coûte le plus cher quand on l'oublie.

## Exercices

Les exercices 1 à 3 s'exécutent dans le cluster de la leçon, déjà déployé comme 10.8 l'a laissé. Avant chacun, `ctx` (10.1.2) doit passer. `correr.sh` les exécute de la même façon, et sa sortie est dans `correr.salida.txt`. **Avant** d'exécuter chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes mots.

### Exercice 1 — Un overlay à toi

Écris un overlay qui part de l'overlay de `kind` et change **une seule chose** : que la mise à l'échelle automatique ne dépasse pas 4 répliques (aujourd'hui elle va jusqu'à 6). Sans toucher à la base ni à l'overlay de `kind`. Avant de l'exécuter, prédis : combien de lignes du manifeste assemblé changent, par rapport à `overlays/kind` ? Comment le vérifierais-tu **sans rien appliquer**, et comment avec le cluster mais sans le modifier ?

### Exercice 2 — De « malo » à `restricted`

`fig10_02.deployment-malo.yaml` enfreint le niveau `restricted`. Corrige-le jusqu'à ce qu'il s'applique dans l'espace `revisor` **sans un seul avertissement** et que ses Pods arrivent à `Available`. Avant de commencer, prédis : quels sont les contrôles qui lui manquent ? Après la correction, quel comptage d'avertissements attends-tu ? Indice : la liste est en 10.7.1, et le test positif, tu l'as déjà avec 10.7.5.

### Exercice 3 — Le plan de contrôle s'arrête

En 10.8.3, tu as arrêté un nœud de travail. Maintenant, arrête le nœud de contrôle (`docker stop curso-k8s-l10-control-plane`) pendant une minute. Prédis avant, et écris-le : `kubectl get nodes` répond-il ? Les conteneurs du `revisor` continuent-ils de tourner sur les nœuds de travail ? (Sans API, tu peux interroger le nœud lui-même : `docker exec <nœud> crictl ps`.) Et le point d'entrée, `http://<adresse>/salud` depuis l'extérieur du cluster, continue-t-il de répondre ? Note ce que tu vois même si cela ne coïncide pas avec la solution : le résultat n'est pas toujours le même. Ensuite, relance le nœud, mesure combien de temps l'API met à revenir et vérifie que le gardien de MetalLB répond avant d'appliquer quoi que ce soit. Avec tes mesures, explique pourquoi le plan de contrôle et les nœuds de travail s'appellent ainsi, et ce que dirait la liste de 10.10 sur le point 1. **Un avertissement :** sur ta machine, le nœud de contrôle peut changer d'adresse IP en redémarrant si un autre conteneur a pris la sienne dans le réseau Docker ; si cela arrive, le cluster cesse de fonctionner et on le recrée. Dans le cluster de l'exécution de cette leçon, avec un réseau dédié et sans autres conteneurs, cela n'est pas arrivé.

### Exercice 4 — Défends ta liste

Choisis **cinq** des quatorze points de 10.10 et, en cinq lignes au plus par point : ce que fait ton projet aujourd'hui, ce qu'exigerait un vrai cluster et ce que tu ferais, dans quel ordre. Ensuite, classe-les selon « ce qui m'inquiéterait en premier » et défends la première place en trois phrases : que perd-on si cela échoue, et peut-on le reconstruire ?

## Solutions

### Solution 1

L'overlay est `fig10_03.overlay-mio/kustomization.yaml` :

```yaml
# fig10_03.overlay-mio/kustomization.yaml — solución del Ejercicio 1: un overlay
# propio que parte del overlay de kind y cambia UNA cosa (el máximo de réplicas del
# HPA, de 6 a 4) sin tocar la base. Se comprueba con:
#   kubectl kustomize fig10_03.overlay-mio
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../overlays/kind
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: revisor
  patch: |-
    - op: replace
      path: /spec/maxReplicas
      value: 4
```

Mesuré dans `correr.salida.txt` :

```text
$ kubectl kustomize fig10_03.overlay-mio | grep -n -E 'maxReplicas|minReplicas'
391:  maxReplicas: 4
399:  minReplicas: 2

$ kubectl diff --server-side -k fig10_03.overlay-mio | grep -E '^[+-] +(max|min)Replicas'
-  maxReplicas: 6
+  maxReplicas: 4
[código de salida: 1]

$ grep -c maxReplicas base/escalado.yaml
1
```

Une seule ligne change. `kubectl kustomize` affiche le résultat sans rien toucher : `maxReplicas: 4` à la ligne 391, et `minReplicas: 2` intact à la 399. Avec le cluster, `kubectl diff --server-side` compare ce que tu appliquerais avec ce qui existe et montre exactement `-  maxReplicas: 6` et `+  maxReplicas: 4` ; le `[código de salida: 1]` est celui de `kubectl diff` quand il **y a** des différences (0 s'il n'y en a pas). Et la preuve que la base n'a pas été touchée : `base/escalado.yaml` a toujours son unique ligne `maxReplicas`. Pour l'appliquer, `kubectl apply --server-side -k fig10_03.overlay-mio` suffirait ; l'exercice ne le demande pas, pour que le cluster reste ce que disent les fichiers de la leçon.

### Solution 2

La correction est `fig10_04.deployment-corregido.yaml` : le même Deployment avec `automountServiceAccountToken: false`, le `securityContext` du Pod (non-`root`, utilisateur 65532, *seccomp* `RuntimeDefault`) et celui du conteneur (sans élévation de privilèges, système de fichiers en lecture seule, sans capacités), plus un plancher et un plafond de ressources.

```yaml
# fig10_04.deployment-corregido.yaml — solución del Ejercicio 2: el mismo Deployment
# de fig10_02.deployment-malo.yaml, ahora con todo lo que pide el nivel «restricted»
# (y lo que el curso pide además: sin credenciales de la API, sistema de archivos
# de solo lectura, piso y techo de recursos).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: malo
  labels:
    app: malo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: malo
  template:
    metadata:
      labels:
        app: malo
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: malo
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
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Mesuré dans `correr.salida.txt` :

```text
$ kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml 2>&1 | grep -ci warning
0
[código de salida: 1]

$ kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml
deployment.apps/malo unchanged

$ kubectl get deployment malo -n revisor
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
malo   1/1     1            1           2s

$ kubectl delete -n revisor -f fig10_04.deployment-corregido.yaml
deployment.apps "malo" deleted from revisor namespace
```

Le comptage d'avertissements donne **0**. Cette commande a déjà appliqué le Deployment (le `grep` ne compte que ce qu'`apply` affiche), et c'est pourquoi le second `apply` dit `unchanged` : il n'y avait rien à changer. Le Deployment arrive à `1/1` et à `Available`, donc les Pods ne sont plus rejetés. Chaque contrôle a son champ : `allowPrivilegeEscalation: false` et `capabilities.drop: ["ALL"]` dans le conteneur ; `runAsNonRoot: true` (avec `runAsUser: 65532`) et `seccompProfile.type: RuntimeDefault` dans le Pod. Le reste —`readOnlyRootFilesystem`, `automountServiceAccountToken: false`, plancher et plafond— n'est pas demandé par `restricted` ; c'est le cours qui le demande.

### Solution 3

Mesuré dans `correr.salida.txt` :

```text
$ kubectl get servicel2statuses -n metallb-system
NAME       ALLOCATED NODE          SERVICE NAME                     SERVICE NAMESPACE
l2-pkb9d   curso-k8s-l10-worker2   envoy-revisor-revisor-b269644b   envoy-gateway-system

# el Pod revisor-654b5d75dc-qcqfz vive en curso-k8s-l10-worker2 con la IP 10.244.2.5

$ docker stop curso-k8s-l10-control-plane
curso-k8s-l10-control-plane

$ kubectl get nodes --request-timeout=5s 2>&1 | cut -c1-200
The connection to the server 127.0.0.1:64201 was refused - did you specify the right host or port?
[código de salida: 1]

# una petición cada 2 s durante 45 s a la puerta, desde fuera del clúster (se muestran los cambios)
[+0s] ok
bien=23 mal=0

# sin API, pero con acceso al nodo: ¿los contenedores siguen corriendo y contestando?

$ docker exec curso-k8s-l10-worker2 crictl ps | grep -E 'CONTAINER|revisor'
CONTAINER           IMAGE               CREATED              STATE               NAME                ATTEMPT             POD ID              POD                                               NAMESPACE
05a1aec248153       a25150a910b03       2 minutes ago        Running             shutdown-manager    1                   50c0eb8926152       envoy-revisor-revisor-b269644b-867f46cd7d-vsnj9   envoy-gateway-system
1edc39ddbcac7       370bbc1c75d75       2 minutes ago        Running             envoy               1                   50c0eb8926152       envoy-revisor-revisor-b269644b-867f46cd7d-vsnj9   envoy-gateway-system
515dc19d2f9d1       70e09194319be       2 minutes ago        Running             revisor             1                   6515939e5a0b1       revisor-654b5d75dc-qcqfz                          revisor

$ docker exec curso-k8s-l10-worker2 curl -s -m 3 http://10.244.2.5:8080/salud
{"estado":"vivo","version":"1.6.0"}

$ docker start curso-k8s-l10-control-plane
curso-k8s-l10-control-plane
(la API volvió a contestar 59 s después de detener el nodo de control)

$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l10-control-plane condition met
node/curso-k8s-l10-worker condition met
node/curso-k8s-l10-worker2 condition met

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready    control-plane   9m8s    v1.37.0
curso-k8s-l10-worker          Ready    <none>          8m57s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          8m56s   v1.37.0

$ kubectl get servicel2statuses -n metallb-system
NAME       ALLOCATED NODE          SERVICE NAME                     SERVICE NAMESPACE
l2-pkb9d   curso-k8s-l10-worker2   envoy-revisor-revisor-b269644b   envoy-gateway-system

$ kubectl get pods -n revisor -o wide
NAME                       READY   STATUS      RESTARTS        AGE     IP            NODE                    NOMINATED NODE   READINESS GATES
depurar                    1/1     Running     0               4m4s    10.244.1.9    curso-k8s-l10-worker    <none>           <none>
intruso                    1/1     Running     0               4m4s    10.244.1.10   curso-k8s-l10-worker    <none>           <none>
prueba-6899c74865-rzh88    1/1     Running     0               5m47s   10.244.1.4    curso-k8s-l10-worker    <none>           <none>
reporte-29877095-rwc6k     0/1     Completed   0               4m7s    10.244.1.11   curso-k8s-l10-worker    <none>           <none>
revisor-654b5d75dc-qcqfz   1/1     Running     1 (2m22s ago)   4m8s    10.244.2.5    curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running     0               4m10s   10.244.1.7    curso-k8s-l10-worker    <none>           <none>

# ¿contesta ya el guardián (webhook) de MetalLB? Una prueba en seco del rango, sin aplicar nada

$ kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300
Warning: resource ipaddresspools/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation w
ipaddresspool.metallb.io/curso configured (server dry run)
Warning: resource l2advertisements/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation
l2advertisement.metallb.io/curso configured (server dry run)

# espera (hasta 3 minutos) a que el guardián de MetalLB conteste

$ kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300
Warning: resource ipaddresspools/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation w
ipaddresspool.metallb.io/curso configured (server dry run)
Warning: resource l2advertisements/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation
l2advertisement.metallb.io/curso configured (server dry run)
```

Lis-le dans l'ordre. **L'API ne répond pas** : `kubectl` reste avec `connection … was refused` contre `127.0.0.1` (le port que `kind` publie depuis le nœud de contrôle). Sans le plan de contrôle, tu ne peux rien voir, créer, modifier ni supprimer. **Les conteneurs sont restés en vie** dans les deux exécutions où on l'a vérifié (la 5 de préparation et celle de la leçon) : sans API, mais avec accès au nœud, `crictl ps` liste le `revisor` et les deux conteneurs d'Envoy en cours d'exécution, et un `curl` depuis le nœud vers l'IP du Pod répond `{"estado":"vivo","version":"1.6.0"}`. Cela dit que les conteneurs ne s'arrêtent pas tout seuls ; cela ne dit pas que le service atteint celui qui le demande. **Le point d'entrée**, dans cette exécution, a répondu aux 23 requêtes (`bien=23 mal=0`) pendant les 45 secondes. Et voici un avertissement qui a été mesuré et non expliqué : dans **trois exécutions de préparation** de cette même leçon (conservées dans `programas/10-proyecto-final/corridas-preparacion/` : `corrida1.txt`, `corrida4.txt` et `corrida5.txt`), avec le même exercice, le point d'entrée n'a répondu à aucune de ses requêtes pendant que le plan de contrôle était arrêté (`bien=0 mal=12`, 12 sur 12 en échec, dans la 4 et la 5 ; dans la 1, `curl` est sorti avec le code 7, connexion refusée, instantanément). Au total, le point d'entrée a répondu dans 1 exécution sur 4, bien que `ServiceL2Status` (mesuré par les deux dernières) ait dit qu'un nœud de travail annonçait l'adresse. On n'a pas trouvé la cause. L'honnête tient en une phrase : dans `kind`, avec MetalLB et Envoy Gateway, **ne tiens pas pour acquis** que le point d'entrée survit sans plan de contrôle, ni le contraire : avec 4 exécutions on ne peut dire que « 1 sur 4 ». Note ce que tu vois dans la tienne ; ce peut être différent de cette solution. **L'API est revenue** 59 secondes après l'arrêt du nœud de contrôle.

Et une seconde leçon, tirée de la dernière vérification. Quand le nœud de contrôle revient, `kubectl wait` dit que les trois nœuds sont `Ready`, mais cela ne veut pas dire que tout le reste est prêt. Dans une exécution de préparation, le `kubectl diff` final a échoué avec `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connection refused` : le gardien de MetalLB ne répondait pas encore (10.4.1, encore une fois). C'est pourquoi le script interroge le gardien avec un essai à blanc de la plage —`kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml`— et attend avec un plafond qu'il réponde. Dans cette exécution, il a répondu au premier essai : `ipaddresspool.metallb.io/curso configured (server dry run)`. Les deux lignes `Warning` qui l'accompagnent ne concernent pas la sécurité : elles disent que la plage a été créée avec `--server-side` et n'a pas l'annotation `last-applied-configuration` qu'utilise l'`apply` côté client. C'est la différence de 10.4.2, et ici elle est inoffensive parce que c'est un essai à blanc. Après l'attente, `kubectl diff --server-side -k overlays/kind` dit `sin diferencias con los archivos`.

Ce que cela dit du point 1 de 10.10 : un plan de contrôle à un seul nœud est un point de défaillance unique : sans lui, tu ne peux rien **changer** et personne ne recrée ni ne met à l'échelle ; ce qui tourne déjà peut continuer de tourner (les conteneurs l'ont fait) ou cesser d'être joignable (le point d'entrée, 3 fois sur 4), et on n'a pas trouvé de quoi cela dépend. Et pourquoi ils s'appellent ainsi : le plan de contrôle **décide** (ce qui doit exister et où) ; les nœuds de travail **exécutent**.

### Solution 4

Une réponse possible, pour la liste de cinq : « **(2) `etcd` sans sauvegarde** : aujourd'hui il n'y a pas de copie ; un vrai cluster planifie `etcdctl snapshot save` et *restaure pour de bon* dans un cluster de test de temps en temps, et je le fais en premier parce que c'est la seule chose que je ne peux pas reconstruire avec `kubectl apply`. **(8) Volume sur le disque d'un nœud** : aujourd'hui le rapport vit sur le nœud ; dans un vrai cluster, stockage répliqué et copies, avec le même test de restauration. **(3) Secrets non chiffrés** : aujourd'hui ils sont en base64 dans `etcd` ; je configurerais le chiffrement au repos et, pour les secrets qui ne doivent pas vivre dans le cluster, un magasin externe. **(4) HTTP sur le port 80** : je terminerais TLS dans le Gateway et je ferais tourner le token, qui a voyagé en clair. **(1) Plan de contrôle à un nœud** : trois nœuds de contrôle ou un plan géré. » L'ordre d'inquiétude : d'abord ce qui ne se reconstruit pas (2 et 8), ensuite ce qui est exposé (3 et 4), à la fin la disponibilité (1). Défense de la première place : « Si l'`etcd` sans sauvegarde échoue, je perds l'état du cluster ; le projet se reconstruit avec deux commandes et une attente (je l'ai testé deux fois), mais ce que le cluster savait de lui-même, non. Et une sauvegarde qui n'a jamais été restaurée n'est pas une réponse : c'est une hypothèse. »

## Supprimer le cluster

Quand tu as terminé, supprime le cluster de la leçon et ce que tu as laissé sur ta machine. Ne laisse rien en vie :

```bash
# El clúster (con su nombre: sin --name, kind borra el llamado «kind»).
kind delete cluster --name curso-k8s-l10
kind get clusters | grep -c curso-k8s-l10    # debe decir 0
# El token de la lección: es de mentira, pero un token suelto no se deja.
rm -f -- base/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 10.1.2.
case "$L10_TMP" in
  /tmp/curso-k8s-l10.?*) rm -rf -- "$L10_TMP" ;;
  *) echo "No borro «$L10_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L10_TMP
```

```text
$ kind delete cluster --name curso-k8s-l10
Deleting cluster "curso-k8s-l10" ...
Deleted nodes: ["curso-k8s-l10-worker2" "curso-k8s-l10-control-plane" "curso-k8s-l10-worker"]

$ kind get clusters | grep -c curso-k8s-l10
0
[código de salida: 1]
```

(Les lignes entre parenthèses sont écrites par le script, qui mesure la suppression. Le `grep -c` affiche `0` et sort avec le code 1, parce qu'il n'a trouvé aucun cluster portant ce nom : c'est la réponse que tu cherches.) Le `case` ne laisse passer qu'un chemin qui commence par `/tmp/curso-k8s-l10.` et qui a quelque chose après, la forme exacte de celui que tu as créé en 10.1.2. Si `L10_TMP` est vide ou vaut autre chose, il ne supprime rien et te dit pourquoi. Si tu as fait l'Exercice 3 dans un second terminal, ferme-le. Et si tu as utilisé un réseau Docker dédié (l'exécution de cette leçon l'a fait ; toi, avec le réseau `kind`, non), supprime-le **après** le cluster et seulement si tu l'as créé toi-même : `docker network rm <nom>`.

Ce fut le dernier cluster du cours. Ceux des leçons précédentes, tu les as déjà supprimés, un par leçon, et c'est ainsi que se termine la méthode : créer, utiliser, supprimer, et pouvoir recréer.

## Comment savoir que tu y es arrivé

- [ ] Tu ouvres un `kustomization.yaml` et tu dis ce qu'est une base, ce qu'est un overlay, ce qu'il assemble et comment le vérifier avec `kubectl kustomize` sans rien appliquer.
- [ ] Depuis un cluster vide, tu déploies le projet avec la plateforme, une attente par condition et le projet, et tu expliques pourquoi cet ordre.
- [ ] Tu lis `no matches for kind … ensure CRDs are installed first` et le message d'un CRD trop gros sans `--server-side`, et tu dis ce qui les cause.
- [ ] Tu exécutes `programas/10-proyecto-final/probar-levantar.sh` et tu compares sa sortie avec `programas/10-proyecto-final/correr.salida.txt` sur ce qui ne change pas d'une exécution à l'autre : la plateforme appliquée avec `serverside-applied` ; les cinq attentes avec `condition met` ou `successfully rolled out` ; le projet avec ses objets et sans une seule ligne `Warning` ; le Gateway `Programmed` ; `{"estado":"vivo","version":"1.6.0"}` depuis l'extérieur, aux deux tours ; et le cluster qui n'existe plus à la fin. Les IP, les suffixes des noms, les âges et les secondes changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] Tu sais pourquoi `kubectl label --dry-run=server … enforce=restricted` sur `revisor` (qui l'a déjà) répond `not labeled` sans vérifier aucun Pod, et tu vérifies les Pods existants en demandant une politique différente (`enforce-version=v1.36`), avec le témoin de l'espace `psa-control` qui nomme le Pod qui enfreint et non celui qui respecte.
- [ ] Tu arrêtes un nœud de travail, tu mesures la fenêtre pendant laquelle des requêtes échouent et tu expliques pourquoi elle dure ce qu'elle dure et ce qui la réduit.
- [ ] Tu changes la liste de services et tu vois un nouveau `ConfigMap` et un nouveau ReplicaSet sans reconstruire l'image.
- [ ] `intruso` n'atteint pas le `revisor`, `depurar` y arrive ; le compte `revisor` ne peut même pas lire les Pods.
- [ ] `kubectl get hpa` affiche un pourcentage, non `<unknown>`.
- [ ] Tu écris, avec tes mots, cinq raisons pour lesquelles ce que tu as construit n'est pas un vrai cluster, ce que tu ferais pour chacune et par laquelle tu commencerais.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l10`.

## Résumé

Réponds sans regarder la leçon :

1. Qu'est-ce qu'une base et qu'est-ce qu'un overlay ? Une base connaît-elle ses overlays ?
2. Quelle différence y a-t-il entre une pièce de plateforme et une pièce de projet, et quelles trois choses apporte une plateforme ?
3. Quelle condition `kubectl wait` attend-il sur un CRD, et laquelle sur un Deployment ?
4. Qu'est-ce que `--server-side` change et quelle erreur évite-t-il dans la plateforme ?
5. Que se passe-t-il si tu réunis plateforme et projet dans une seule commande, et pourquoi la répéter « pour voir si ça passe » n'est-il pas une méthode ?
6. Pourquoi un script de déploiement reçoit-il le contexte en argument et le vérifie-t-il avant chaque étape ?
7. Que demande le niveau `restricted` et que fait le projet en plus de cela ?
8. Pourquoi une partie de la plateforme (MetalLB, `kube-system`) ne respecte-t-elle pas `restricted`, et quelle condition poses-tu pour que ce soit acceptable ?
9. Avec un nœud de travail arrêté, pourquoi des requêtes échouent-elles pendant des dizaines de secondes et qu'est-ce qui ne raccourcit pas cette fenêtre ?
10. Quand utiliserais-tu Helm plutôt que Kustomize ?
11. Nomme cinq raisons pour lesquelles le cluster du cours n'est pas un vrai cluster et ce que tu ferais pour chacune.

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Declarative Management of Kubernetes Objects Using Kustomize »](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) : bases et overlays, générateurs avec *hash*, `patches`, `images`, et `kubectl kustomize` / `apply -k`.
- [Kubernetes, « Server-Side Apply »](https://kubernetes.io/docs/reference/using-api/server-side-apply/) : gestionnaires de champs, conflits, et la comparaison avec l'`apply` côté client.
- [Kubernetes, « Custom Resources » : CustomResourceDefinition](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) : la condition `Established` d'un CRD.
- [Kubernetes, « Dynamic Admission Control »](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) : *webhooks* d'admission et `failurePolicy` (par défaut `Fail`).
- [Kubernetes, « kubectl wait »](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) : attendre une condition sur une ou plusieurs ressources.
- [Kubernetes, « Virtual IPs and Service Proxies »](https://kubernetes.io/docs/reference/networking/virtual-ips/) : `kube-proxy` choisit au hasard le Pod de destination d'un Service dans les modes `iptables` et `nftables`.
- [Kubernetes, « Pod Security Standards »](https://kubernetes.io/docs/concepts/security/pod-security-standards/) : les contrôles de `baseline` et `restricted`, champ par champ.
- [Kubernetes, « Pod Security Admission »](https://kubernetes.io/docs/concepts/security/pod-security-admission/) et [« Enforce Pod Security Standards with Namespace Labels »](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) : les modes `enforce`, `audit` et `warn`, les versions figées, et le test avec `--dry-run=server`.
- [Kubernetes, « Node Status »](https://kubernetes.io/docs/reference/node/node-status/), [« kube-controller-manager »](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) et [« Taints and Tolerations »](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) : les 50 secondes de `node-monitor-grace-period` et la tolérance de 300 secondes.
- [Kubernetes, « Production environment »](https://kubernetes.io/docs/setup/production-environment/), [« Security checklist »](https://kubernetes.io/docs/concepts/security/security-checklist/), [« Encrypting Confidential Data at Rest »](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/), [« Operating etcd clusters »](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/), [« Logging Architecture »](https://kubernetes.io/docs/concepts/cluster-administration/logging/), [« Resource Quotas »](https://kubernetes.io/docs/concepts/policy/resource-quotas/) et [« Version Skew Policy »](https://kubernetes.io/releases/version-skew-policy/) : ce qu'exige un vrai cluster et la politique des versions.
- [kind, *issues* #4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) et [#4224](https://github.com/kubernetes-sigs/kind/issues/4224) : défaillances de `kind load` avec Docker 29 et le magasin de `containerd` (l'avertissement de 10.1.2).
- [kind](https://kind.sigs.k8s.io/) : pour quoi `kind` a été conçu. Et [`provider.go` de kind v0.33.0](https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provider.go) : la variable `KIND_EXPERIMENTAL_DOCKER_NETWORK`, utilisée par l'exécution de cette leçon.
- [Envoy Gateway, « Install with Kubernetes YAML »](https://gateway.envoyproxy.io/docs/install/install-yaml/) et [« Install with Helm »](https://gateway.envoyproxy.io/docs/install/install-helm/) : l'installation avec `--server-side`, l'installation avec Helm et l'ordre de mise à jour des CRD.
- [MetalLB, « Layer 2 mode »](https://metallb.io/concepts/layer2/) : comment il fonctionne et ses deux limites.
- [metrics-server v0.9.0, README](https://github.com/kubernetes-sigs/metrics-server/blob/v0.9.0/README.md) : `--kubelet-insecure-tls` « uniquement pour les tests », et le fait qu'il sert uniquement à la mise à l'échelle automatique.
- [Gateway API, « TLS »](https://gateway-api.sigs.k8s.io/guides/tls/) : terminer TLS dans un *listener*.
- [Helm, « Using Helm »](https://helm.sh/docs/intro/using_helm/) et [« Custom Resource Definitions »](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) : ce qu'est un chart et comment il traite les CRD.
- [RFC 6902, « JavaScript Object Notation (JSON) Patch »](https://www.rfc-editor.org/rfc/rfc6902.html) : les opérations `op: replace` des correctifs de 10.3.3.
- [RFC 2606, « Reserved Top Level DNS Names »](https://www.rfc-editor.org/rfc/rfc2606.html) : `example.com` réservé aux exemples.
- [GitLab, « Postmortem of database outage of January 31 »](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/) : le rapport public du cas de l'ouverture.

---

**Fin du cours.** Retourne à l'[index](README.md) ou ouvre le [journal de bord](bitacora.md) et écris ce que tu veux construire ensuite.
