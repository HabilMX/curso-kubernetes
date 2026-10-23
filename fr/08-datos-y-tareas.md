# Leçon 8 — Données et tâches

Lundi, 7 h 12 du matin. À 9 h 00, réunion avec le fournisseur du service de paiement, et ta responsable t'écrit un message d'une ligne : « J'ai besoin du rapport de vendredi, 18 h, celui qui montrait `prueba` en panne pendant quarante minutes. C'est la preuve de la réclamation ». Tu ouvres le cluster avec la tranquillité de celui qui sait que le `revisor` conserve son rapport dans un fichier, `/datos/reporte.json`. Tu demandes les Pods et tu vois quelque chose d'inattendu : les trois répliques ont moins de deux jours. Samedi, lors de la maintenance de la nuit, quelqu'un a vidé les nœuds un par un pour les mettre à jour (avec `kubectl drain`, qui évince les Pods d'un nœud) et le cluster a fait ce qu'il sait faire : il a supprimé les anciens Pods et le Deployment a créé de nouveaux Pods sur d'autres nœuds. Tu cherches le fichier. Il n'est pas là. Tu cherches dans les deux autres répliques. Pas là non plus. Et même s'il y avait été, tu t'aperçois en y réfléchissant d'un problème pire : le `revisor` conserve **le dernier** rapport et écrit par-dessus le précédent. Celui de vendredi aurait été perdu de toute façon dès la première consultation du samedi.

Il est 7 h 20. Il te reste cent minutes pour trouver une façon de dire « je ne l'ai pas » qui ne sonne pas comme « je ne l'ai pas conservé ».

Ce n'est pas un cas rare de malchance. C'est ce qui arrive quand on confond un conteneur avec un coffre-fort. En 2017, l'équipe de GitLab a publié le récit des heures pendant lesquelles elle a perdu des données de production et découvert que ses mécanismes de sauvegarde ne fonctionnaient pas au moment où il le fallait : les copies quotidiennes échouaient en silence et le bucket où elles devaient se trouver était vide, les instantanés de disque n'étaient pas activés sur les serveurs de la base de données et la réplique était cassée. Leur rapport (les sources le citent, avec le lien) rappelle utilement que la question n'est pas « ai-je une sauvegarde ? », mais « l'ai-je testée ? ». Cette leçon est plus modeste : elle ne construit pas de sauvegardes. Elle t'enseigne la moitié qui vient avant, celle que presque tout le monde découvre trop tard : **quelle part de ce qu'écrit un Pod survit au Pod lui-même, et quelle part ne survit pas**. Avec cette réponse en main, le rapport de vendredi cesse de dépendre de la chance : une tâche planifiée demande son rapport au `revisor` et l'enregistre, avec la date dans le nom, dans un volume qui survit aux Pods (tant que la demande de volume existe, ainsi que le nœud où vit le disque). Ce n'est plus une ligne qu'on écrase : c'est un fichier avec un nom et une date.

La leçon a deux moitiés qui ont besoin l'une de l'autre. La première est le **où** : des volumes qui vivent plus longtemps que les Pods. La seconde est le **quand** : des tâches qui s'exécutent une fois, ou toutes les cinq minutes, sans que personne ne les lance. Ensemble, elles résolvent la scène : une tâche planifiée demande son rapport au `revisor` toutes les cinq minutes et l'enregistre avec la date dans le nom, dans un volume qui survit aux Pods.

**Durée :** 2 × 45 min

**Ce que tu construis :** le rapport conservé et le `revisor` en tâche planifiée : un volume persistant appelé `reportes`, une tâche (`Job`) qui demande son rapport au `revisor` avec le token et l'écrit avec la date dans le nom, et un `CronJob` qui la répète toutes les cinq minutes, avec un compte de service sans permissions ni identifiants montés

**Ce que tu apprends :** ce qui survit et ce qui ne survit pas quand un conteneur tombe en panne et quand un Pod est supprimé (`emptyDir`) ; `PersistentVolume`, `PersistentVolumeClaim` et `StorageClass`, et la classe de stockage de kind ; pourquoi la demande de volume attend son premier Pod ; `Job` et `CronJob` avec leurs nouvelles tentatives, leur horaire et leur historique ; le propriétaire des fichiers avec `fsGroup` ; ce qui est perdu quand on supprime la demande de volume ; et une taille demandée que le cluster ne fait pas respecter

**D'où tu viens.** De la Leçon 7 : le `revisor` et le service de test vivent dans un espace de noms à part, `revisor`, qui exige le niveau `restricted` de Pod Security Admission ; chaque charge a son compte de service sans identifiants montés ; et le réseau est fermé par défaut, avec des ouvertures nommées : au `revisor` n'entrent que les Pods portant l'étiquette `acceso-revisor: permitido` et les Envoy du point d'entrée. De la [Leçon 4](04-configuracion-secretos.md), le token sous forme de `Secret` monté comme fichier et les noms avec *hash* que Kustomize ajoute. De la [Leçon 5](05-salud-recursos-apagado.md), `requests` et `limits` dans tout conteneur ; aujourd'hui, les tâches les portent aussi. Et de la [Leçon 6](06-entrar-al-cluster.md), la plateforme (MetalLB et Envoy Gateway) que cette leçon réinstalle en créant son cluster, parce que le point de départ inclut le Gateway.

**Ce que cette leçon ne fait pas.** Elle ne place pas le rapport du `revisor` dans le volume persistant : l'Exercice 2 te laisse l'essayer et voir pourquoi le cours ne le fait pas (cela attache toutes les répliques à un seul nœud). Elle n'installe pas de système de stockage réseau, n'enseigne pas `StatefulSet` et ne prend ni instantanés ni sauvegardes d'un volume : elle les nomme à la fin de « L'habitude de sécurité », avec une phrase sur le problème que chacun résout. Elle ne fait rien passer à l'échelle (c'est la [Leçon 9](09-escalar-y-actualizar.md), qui part de ce que tu laisses ici) et n'évalue pas le projet complet face à un vrai cluster (la [Leçon 10](10-proyecto-final.md)).

**À propos des exécutions.** Toutes les sorties de cette leçon ont été obtenues le 21 octobre 2026 avec `kind` v0.33.0, `kubectl` v1.37.1 et l'image de nœud `kindest/node:v1.37.0` figée par son empreinte, sur le cluster à trois nœuds de la Leçon 1, qu'on appelle ici `curso-k8s-l8`. La machine était un Mac à processeur ARM avec Docker Engine dans une machine virtuelle Linux (Colima), et **non** Linux Mint, qui est le système de référence du cours. **L'exécution a utilisé un réseau Docker dédié**, `curso-k8s-red-l8`, avec le sous-réseau `172.28.0.0/16`, parce que la machine était partagée et que d'autres leçons tournaient à ce moment-là avec MetalLB : deux clusters qui partagent la même plage d'IP sur le même réseau se marchent dessus. C'est pourquoi les adresses du Gateway apparaissent ici en `172.28.255.x`. **Sur ta machine, avec le réseau `kind` normal que Docker crée au démarrage du premier cluster, les IP sortent en `172.18.255.x`** (la plage de `infra/metallb-pool.yaml` est `172.18.255.200-172.18.255.220`), et tu n'as aucun réseau à créer. Cela suppose que ton réseau `kind` ait le sous-réseau `172.18.0.0/16` ; vérifie-le d'abord avec `docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'` et, s'il est autre, ajuste la plage du fichier. Le reste de ce qui change sur ton Mint : l'architecture (`amd64` au lieu de `arm64`), les suffixes aléatoires des noms de Pods et de Jobs, les âges, le nœud sur lequel atterrit chaque réplique, l'*uid* de chaque Pod, l'heure et les noms des volumes (`pvc-` et un identifiant). Les commandes sont les mêmes. Le parcours complet se trouve dans [`programas/08-datos-y-tareas/`](../programas/08-datos-y-tareas) : `correr.sh` crée le cluster, y installe la plateforme, remet tout dans l'état où la Leçon 7 l'a laissé, parcourt la leçon dans l'ordre, exécute les Exercices 1 à 3 et supprime le cluster ; sa sortie est `correr.salida.txt`. L'exécution complète a duré 19 minutes et 17 secondes (les trois essais de `concurrencyPolicy` de l'Exercice 3 totalisent environ huit minutes d'attentes) : créer le cluster et attendre qu'il soit prêt a pris 42 secondes, installer la plateforme en a pris 175 (le script ne chronomètre pas chaque étape, donc je ne sais pas laquelle des attentes a été la longue) et supprimer le cluster, 4. Ces durées varient beaucoup avec la charge de la machine : lors d'une autre exécution du même script, avec la machine occupée, l'installation de la plateforme a pris 678 secondes et le `kubectl wait` d'Envoy Gateway a fini par épuiser son délai de 300 secondes, même si le Gateway a fini par fonctionner. Les longues attentes de la leçon (regarder passer l'horaire d'un `CronJob`, regarder un `Job` épuiser ses nouvelles tentatives) sont écrites à la vue de tous : le script imprime toutes les combien de secondes il regarde et ce qu'il voit, il ne les cache pas. Il n'utilise aucun port de ta machine.

## À la fin, tu seras capable de

- Démontrer avec l'exécution ce qui survit et ce qui ne survit pas dans un `emptyDir` : le redémarrage d'un conteneur, oui ; la suppression du Pod, non.
- Expliquer avec tes mots ce que sont un `PersistentVolume`, une `PersistentVolumeClaim` et une `StorageClass`, et pourquoi la demande de volume du cours reste en `Pending` jusqu'à l'apparition du premier Pod qui l'utilise.
- Lire l'état d'une demande de volume, son volume et le répertoire réel qui le soutient sur le nœud.
- Écrire un `Job`, dire combien de fois il réessaie et avec quelles attentes, et lire un `BackoffLimitExceeded`.
- Écrire un `CronJob`, lire son horaire à cinq champs, et expliquer `concurrencyPolicy`, l'historique des tâches et pourquoi une tâche planifiée doit pouvoir s'exécuter deux fois sans rien abîmer.
- Provoquer et corriger un `Permission denied` sur un volume avec `fsGroup`, et dire sur lequel des volumes de la leçon `fsGroup` a changé le groupe et sur lequel non, et pourquoi tu ne peux pas le tenir pour acquis.
- Dire ce qu'il advient des données quand on supprime une demande de volume selon la politique de récupération, et pourquoi la suppression peut rester bloquée en `Terminating`.

## Le pourquoi avant le comment

Jusqu'à aujourd'hui, tout ce que le `revisor` écrit vit dans un endroit que le cluster traite comme jetable. Tu l'as aperçu en passant à la Leçon 2, quand le Deployment a monté un `emptyDir` sur `/datos` pour que le système de fichiers en lecture seule n'empêche pas de conserver le rapport, et tu l'utilises depuis sans te demander combien de temps il dure. La première question de la leçon est celle-là : **combien de temps dure ce qu'écrit un Pod ?** La réponse a deux paliers, parce qu'un Pod n'est pas la même chose qu'un conteneur : le conteneur peut tomber en panne et revenir (le `kubelet` le redémarre), et le Pod peut être supprimé et remplacé par un autre, avec un autre nom, sur un autre nœud. Ce qui survit au premier cas ne survit pas forcément au second, et nous le mesurons.

La deuxième question est **comment conserve-t-on vraiment quelque chose ?** Kubernetes sépare deux rôles que Docker réunissait. Celui qui administre le cluster décide quel stockage existe (disques, dossiers, services réseau) ; celui qui déploie une application décide de combien il a besoin et de quel type. Le pont entre les deux, ce sont trois objets aux noms voisins et aux fonctions distinctes, que cette leçon présente un par un avant de les utiliser.

La troisième est **comment fait-on quelque chose qui n'est pas un service ?** Un Deployment maintient des processus qui ne doivent pas s'arrêter. Demander son rapport au `revisor` toutes les cinq minutes est le contraire : un processus qui démarre, fait une chose et se termine, et que le cluster doit répéter à heure fixe sans que personne n'y pense. Pour cela existent le `Job` (faire quelque chose jusqu'à ce que ça réussisse ou jusqu'à abandonner) et le `CronJob` (créer des Jobs selon un horaire).

Et il y a une quatrième question, moins spectaculaire, qui décide si tout ce qui précède fonctionne : **qui est le propriétaire de ce qui est écrit ?** Un volume qui naît avec un propriétaire et une permission, et un processus qui s'exécute sous un autre utilisateur, c'est la recette d'un `Permission denied`. `fsGroup`, la ligne de la Leçon 4 dont l'histoire complète était restée en suspens, revient ici.

La leçon compte huit parties de concepts, puis les sections habituelles :

1. **Le cluster de la leçon et son point de départ** (8.1).
2. **Ce qui est perdu : l'`emptyDir` d'aujourd'hui** (8.2).
3. **Volumes, demandes et classes** (8.3).
4. **La demande de volume et son attente** (8.4).
5. **`Job` : la tâche qui se termine** (8.5).
6. **`CronJob` : la tâche avec un horaire** (8.6).
7. **Le propriétaire des fichiers : `fsGroup`** (8.7).
8. **Supprimer la demande de volume : là, on perd vraiment** (8.8).

Voici la destination. À la fin de 8.5, une tâche lancée manuellement laisse un fichier avec la date dans son nom à l'intérieur d'un volume qui survit à son Pod, et une seconde tâche voit le fichier de la première :

```text
$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json
```

## Si tu n'as pas les images du cours de Docker

Cette leçon utilise les deux mêmes images que les précédentes : `curso-docker-revisor:1.6.0` et `curso-docker-prueba:1.0.0`. Vérifie que tu les as :

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Pour l'autre, la même commande avec `curso-docker-prueba:1.0.0`. S'il t'en manque une, la [Leçon 3](03-services-dns.md) explique comment construire chacune depuis le dépôt du cours de Docker. Les tâches de cette leçon utilisent en plus l'image publique de `curl` que tu connais déjà par `depurar`, figée par son empreinte `sha256` ; chaque nœud la télécharge depuis internet la première fois.

## Les concepts

### 8.1 Le cluster de la leçon et son point de départ

#### 8.1.1 Créer le cluster

Cette leçon utilise son propre cluster, `curso-k8s-l8`, avec la configuration à trois nœuds de la Leçon 1. Les chemins `programas/08-datos-y-tareas/…` du bloc suivant supposent que tu te trouves à la racine du dépôt du cours. Avant de le créer, deux précautions devenues habituelles : un `kubeconfig` temporaire et propre, pour que ton `~/.kube/config` ne soit ni lu ni touché, et une fonction qui vérifie à quel cluster tu parles. Nous l'appellerons `ctx` et elle va **devant chaque commande qui change quelque chose** : si le contexte n'est pas celui de la leçon, elle renvoie une erreur et la commande suivante ne s'exécute pas, parce qu'elle lui est liée par `&&`.

```bash
# Un kubeconfig temporal y propio. La carpeta queda guardada en una variable:
# la necesitas para abrir una segunda terminal y para borrarla al final.
L8_TMP="$(mktemp -d /tmp/curso-k8s-l8.XXXX)"
export KUBECONFIG="$L8_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta
# La guarda: el contexto debe ser el de la lección, o el comando que sigue no corre.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l8 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
# curso-k8s-l8 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l8 --config programas/08-datos-y-tareas/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l8
# El resto de la lección se trabaja desde la carpeta de sus programas.
cd programas/08-datos-y-tareas
```

(L'exécution de cette leçon, pour ce qui a été dit dans « À propos des exécutions », a placé `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l8` devant `kind create cluster` pour utiliser son réseau dédié. Tu n'en as pas besoin.)

L'`export` et la fonction `ctx` ne vivent que dans ce terminal. Si tu en ouvres un autre, tu répètes les deux lignes (`export KUBECONFIG=…` avec le chemin qu'a imprimé l'`echo`, et la définition de `ctx`), sinon `kubectl` parlera à un autre cluster. À partir d'ici, **tout bloc de code qui change quelque chose commence par `ctx &&`**. Dans les sorties collées plus bas, la ligne qui commence par `$` est la commande telle que le script l'a imprimée, sans `ctx &&` : le script vérifie le contexte avant chaque `kubectl` de son côté, et toi tu le fais avec la fonction.

Les sorties de cette section viennent de l'exécution de `correr.sh`, qui fait exactement cela, avec le réseau dédié expliqué dans « À propos des exécutions » :

```text
$ kubectl config current-context
kind-curso-k8s-l8

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l8-control-plane   Ready    control-plane   27s   v1.37.0
curso-k8s-l8-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l8-worker2         Ready    <none>          17s   v1.37.0
```

`kind load` imprime six lignes `not yet present on node …, loading...`, deux images pour trois nœuds, comme dans les leçons précédentes.

#### 8.1.2 La plateforme de la Leçon 6, encore une fois

Le point de départ de cette leçon inclut le Gateway de la Leçon 6, et un Gateway a besoin des nouveaux types (CRD) de Gateway API et du contrôleur d'Envoy Gateway. Comme le cluster est neuf, il faut les installer de nouveau, dans le même ordre qu'à la Leçon 6 : d'abord la plateforme, puis une attente, puis sa configuration. L'ordre compte parce que les CRD et les *webhooks* doivent exister avant les ressources qui les utilisent.

```bash
ctx && kubectl apply -k infra/metallb
ctx && kubectl apply --server-side -k infra/envoy-gateway
# La espera: los tipos nuevos establecidos y los controladores disponibles.
ctx && kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
ctx && kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
ctx && kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
# La configuración: el rango de IP de MetalLB y la clase de puerta «eg».
ctx && kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ctx && kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
```

La sortie, avec la plage du réseau dédié de l'exécution :

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ sed 's#172.18.255.200-172.18.255.220#172.28.255.200-172.28.255.250#' infra/metallb-pool.yaml | kubectl apply -f - && kubectl apply -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s | tail -1
daemon set "speaker" successfully rolled out
(la plataforma tardó 175 s)
```

Deux remarques sur cette sortie. Celle du `sed` ne vaut que pour l'exécution : il remplace la plage du fichier (`172.18.255.200-220`) par celle du réseau dédié (`172.28.255.200-250`) avant de l'appliquer. Sur ta machine, avec le réseau `kind` normal, tu appliques le fichier tel quel : `kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml`. Et les 175 secondes, c'est beaucoup pour cela (avec la machine plus chargée, on est monté à 678), et le script ne chronomètre pas chaque étape : la machine était occupée par d'autres clusters. Lors d'un essai antérieur de cette même leçon, le dernier à se déclarer prêt a été le *speaker* de MetalLB (un Pod par nœud qui annonce les IP sur le réseau). Si, sur ta machine, le `rollout status` traîne, `kubectl get pods -n metallb-system` te dit combien des trois *speakers* sont prêts.

#### 8.1.3 Le point de départ : la Leçon 7

Le dossier `programas/08-datos-y-tareas/punto-de-partida/` apporte, sans changer une virgule, les manifestes avec lesquels la Leçon 7 s'est terminée : l'espace de noms `revisor` avec le niveau `restricted`, les comptes de service, les six politiques réseau, le `revisor` et le service de test avec leurs Services, le Gateway et la `kustomization.yaml`. Comme dans les leçons précédentes, le token n'est pas versionné : il est généré à chaque exécution, avec la permission `0600`, et copié dans les deux dossiers (celui du point de départ et celui de la leçon) pour que les deux génèrent **le même** Secret.

```bash
ctx && (umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
ctx && cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
ctx && kubectl rollout status deployment/revisor -n revisor --timeout=180s
ctx && kubectl rollout status deployment/prueba -n revisor --timeout=180s
ctx && kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
ctx && kubectl apply -n revisor -f depurar.yaml
```

```text
$ ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-hbc69k5m5c created
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

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met

$ kubectl apply -n revisor -f depurar.yaml
pod/depurar created
```

Le nom du `ConfigMap` est celui de la Leçon 4, `revisor-config-t6cm6872fk`, parce que la liste de services n'a pas changé ; celui du `Secret` change à chaque exécution, parce que le token est neuf. Les deux `rollout status` du bloc précédent n'impriment rien ici parce que le script les exécute en silence ; dans ton terminal, tu verras `deployment "revisor" successfully rolled out` et l'équivalent pour `prueba`. Le Pod `depurar` est le même que d'habitude, avec une différence que tu connais depuis la Leçon 7 : il porte l'étiquette `acceso-revisor: permitido`, et c'est pourquoi le réseau fermé le laisse parler au `revisor`.

```text
$ kubectl get pods -n revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
depurar                    1/1     Running   0          8s    10.244.2.5   curso-k8s-l8-worker    <none>           <none>
prueba-6899c74865-9dckl    1/1     Running   0          52s   10.244.1.4   curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-g6wc5   1/1     Running   0          52s   10.244.2.4   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-rxlw6   1/1     Running   0          52s   10.244.2.3   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-wk56w   1/1     Running   0          52s   10.244.1.5   curso-k8s-l8-worker2   <none>           <none>

$ kubectl get pvc,cronjob,job -n revisor
No resources found in revisor namespace.

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Trois répliques du `revisor`, le service de test et `depurar`. Et la dernière ligne de `kubectl get` : il n'y a ni volumes, ni tâches, ni horaires. C'est la question ouverte de la leçon. La dernière sortie est une requête qui vient d'un conteneur Docker hors du cluster, sur le même réseau que les nœuds, et qui arrive par le Gateway : le point d'entrée de la Leçon 6 fonctionne dans l'espace de noms de la Leçon 7 avec le réseau fermé. Si, sur ta machine, il ne répond pas, `kubectl get gateway -n revisor` indique l'IP reçue ; lors de l'exécution, c'était `172.28.255.200`, et sur ton réseau `kind` ce serait `172.18.255.200`.

### 8.2 Ce qui est perdu : l'`emptyDir` d'aujourd'hui

#### 8.2.1 Où se trouve le fichier

D'abord, que le `revisor` écrive son rapport. Chaque requête vers `/api/estados` construit le rapport et, avant de répondre, l'enregistre dans le fichier que désigne la variable `REVISOR_REPORTE` de l'image, `/datos/reporte.json`. L'image n'a pas de *shell*, donc tu ne peux pas entrer voir le fichier ; mais le fichier existe sur un disque quelque part, et les nœuds de kind sont des conteneurs Docker dans lesquels tu peux entrer. On demande un rapport et on cherche :

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid
POD                        NODO                   UID
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347
revisor-6b7f4d564d-wk56w   curso-k8s-l8-worker2   510c7d49-6be3-4fac-947d-18783838b9e5
```

(Dans la première commande, le token apparaît sous la forme `…` : le script le masque dans ce qu'il imprime, et toi tu le passes avec `$TOKEN`, comme dans les leçons précédentes.) L'`uid` est l'identifiant unique que le cluster donne à chaque Pod, et c'est le nom du dossier où le `kubelet` du nœud range ce qui le concerne. Les volumes d'un Pod vivent dans `/var/lib/kubelet/pods/<uid>/volumes/`, et ceux de type `emptyDir`, dans le sous-dossier `kubernetes.io~empty-dir`. On regarde celui de chacune des trois répliques, sur le nœud où elle tourne :

```text
$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/961791a4-d756-4382-a1de-ae62d7bc11b1/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/29162810-cd29-4693-89bf-ed789dd8f347/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

Ces trois sorties livrent trois constats, et tous les trois comptent pour la suite.

**Le premier : une seule des trois répliques possède le fichier.** La requête vers `http://revisor/` a été répartie par le Service vers l'une des trois, et c'est celle-là qui a conservé le rapport. Les deux autres ont leur `/datos` vide. Chaque réplique a son **propre** `emptyDir` : rien n'est partagé entre les Pods. Si tu demandais à « le `revisor` » quel a été son dernier rapport, la réponse dépendrait de la réplique qui te répond. Cela suffit, à lui seul, à disqualifier l'`emptyDir` comme lieu pour une histoire.

**Le deuxième : le propriétaire du répertoire.** La première colonne de `ls -l` est `drwxrwsrwx` : le répertoire a la permission de lecture, d'écriture et d'accès pour tous, et un `s` à la place du `x` dans la position du groupe, qui est le *setgid*. Le propriétaire est l'utilisateur `0` (`root`) et le groupe, le `65532`. Ce groupe n'est pas un hasard : c'est le `fsGroup: 65532` que la Leçon 4 a placé dans le Deployment. Pour ne pas attribuer à `fsGroup` plus qu'il ne fait : la permission ouverte `777` est la valeur par défaut d'un `emptyDir` selon la documentation des volumes ; ce que pose `fsGroup`, c'est le groupe `65532` et le bit *setgid*. La section 8.7 raconte ce que `fsGroup` a fait ici et ce qu'il ne fait pas sur d'autres volumes.

**Le troisième : le fichier appartient à l'utilisateur du `revisor`.** `-rw------- 1 65532 65532 92` : le propriétaire et le groupe sont le 65532, l'utilisateur sous lequel tourne le `revisor`, et la permission `0600` (propriétaire seul) vient de la façon dont le `revisor` le crée : il écrit d'abord un fichier temporaire dans le même dossier, puis le renomme, pour que celui qui le lit voie l'ancien rapport ou le nouveau, jamais un rapport à moitié écrit. Et 92 octets : un rapport d'un seul service.

Avec `root` sur le nœud, on peut lire ce que le `revisor` a conservé :

```text
$ docker exec curso-k8s-l8-worker2 stat -c '%a %U:%g %n' /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
2777 root:65532 /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos

$ docker exec curso-k8s-l8-worker2 cat /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos/reporte.json
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 6
  }
]
```

`stat` traduit la permission en octal : `2777` est le `777` de lecture et d'écriture pour tous, plus le `2` du *setgid*. C'est la même information que le `s`, sous une autre forme. Le contenu est le rapport en JSON : le nom du service, s'il va bien, le code HTTP et le temps en millisecondes.

(Les sorties de cette section supposent que tu sais entrer dans un nœud avec `docker exec` ; c'est ce que tu as fait à la Leçon 4 avec le `Secret` et à la Leçon 5 avec `crictl`. Cela fonctionne parce que, dans kind, les nœuds sont des conteneurs. Dans un vrai cluster, le dossier existe tout autant, mais le nœud est une machine où tu entres par un autre mécanisme et avec d'autres permissions.)

#### 8.2.2 Un conteneur qui tombe en panne : l'`emptyDir` survit

La documentation des volumes de Kubernetes ([lien dans les sources](#sources)) dit de `emptyDir` : le volume est créé « quand le Pod est affecté à un nœud » ; il démarre vide ; et « quand un Pod est retiré d'un nœud pour quelque raison que ce soit, les données de l'`emptyDir` sont supprimées définitivement ». Et elle ajoute une note qui paraît petite et qui est la moitié de la leçon : « un conteneur qui plante ne retire **pas** le Pod du nœud. Les données d'un volume `emptyDir` sont à l'abri des plantages de conteneurs ».

On le vérifie. Avec `crictl`, l'outil de la Leçon 5, on arrête le conteneur du `revisor` qui possède le fichier. L'identifiant du conteneur se cherche par l'`uid` du Pod, pour ne pas arrêter un conteneur étranger :

```bash
CID="$(docker exec curso-k8s-l8-worker2 crictl ps --label "io.kubernetes.pod.uid=510c7d49-6be3-4fac-947d-18783838b9e5" --name revisor -q)"
docker exec curso-k8s-l8-worker2 crictl stop "$CID"
```

```text
$ docker exec curso-k8s-l8-worker2 crictl stop a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090
a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090

(esperando 10 s a que el kubelet reinicie el contenedor)

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w
NAME                       READY   STATUS    RESTARTS      AGE
revisor-6b7f4d564d-wk56w   1/1     Running   1 (10s ago)   65s

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} {.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
Error 137

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

On lit dans l'ordre. `RESTARTS 1 (10s ago)` : le `kubelet` a vu mourir le conteneur et l'a redémarré il y a 10 secondes ; le Pod est toujours le même (même nom, même `uid`, `AGE` de 65 secondes). La dernière terminaison était un `Error` avec le code `137`, le même qu'à la Leçon 5 : 128 plus le signal 9, celui qu'on ne peut pas ignorer. Et la dernière sortie est celle qui compte : **le fichier est intact**, avec la même heure (`23:24`) et les mêmes 92 octets. Le nouveau conteneur a monté le même volume et a trouvé le rapport là où l'ancien l'avait laissé.

Cela a une conséquence pratique qu'il vaut mieux dire clairement : si ton application plante et redémarre toute seule, ce qu'elle a conservé dans un `emptyDir`, le nouveau conteneur le retrouve. C'est l'usage que propose la documentation : espace de travail, points de contrôle d'un long calcul pour le reprendre après un plantage. Ce n'est pas un endroit pour ce qui doit survivre au Pod.

#### 8.2.3 Un Pod supprimé : l'`emptyDir` part avec lui

Le deuxième palier. On supprime le Pod entier, et pas seulement son conteneur, et on regarde le dossier du volume :

```bash
ctx && kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
```

```text
$ kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
pod "revisor-6b7f4d564d-wk56w" deleted from revisor namespace

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
ls: cannot access '/var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos': No such file or directory
[código de salida: 2]

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5
containers
etc-hosts
plugins
volumes

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid,LISTO:.status.containerStatuses[0].ready
POD                        NODO                   UID                                    LISTO
revisor-6b7f4d564d-4mnvh   curso-k8s-l8-worker2   d61911b6-d777-4c4c-a159-e2a782fc69d8   true
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1   true
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347   true
```

Le dossier du volume n'existe plus : `No such file or directory`, avec le code de sortie 2. Le `kubelet` a supprimé le volume en retirant le Pod. La deuxième sortie est une nuance à lire avec soin : le dossier du Pod montre encore quatre entrées (`containers`, `etc-hosts`, `plugins` et `volumes`) quelques secondes après la suppression. Je n'ai pas cherché pourquoi (il s'agit probablement d'un nettoyage du `kubelet` qui n'était pas encore terminé) ; ce qui compte pour la leçon est déjà arrivé : le dossier du volume de données n'existe pas. Et le ReplicaSet a remis la réplique : `4mnvh` est nouvelle (autre nom, autre `uid`) et, cette fois, elle a atterri sur le même nœud, `curso-k8s-l8-worker2` ; le planificateur répartit, mais ne promet pas un nœud différent. Le nouveau `revisor` a démarré avec son `/datos` vide.

Avec cela, le vendredi après-midi de la scène s'explique en deux mesures. Un redémarrage du conteneur est sauf. La maintenance du samedi n'a pas redémarré de conteneurs : elle a évincé des Pods, et chaque nouveau Pod est né avec un nouvel `emptyDir`, sur un nœud qui n'était peut-être pas le même. (Un simple redémarrage du nœud est autre chose : la documentation du cycle de vie du Pod distingue ce cas, où le Pod n'est pas évincé et où le `kubelet` redémarre ses conteneurs, de l'éviction ou de la perte du nœud. Les Pods sont remplacés quand quelqu'un les supprime, que le nœud est vidé ou qu'il est déclaré perdu.) Pour qu'une donnée survive au Pod, il te faut un volume qui **ne dépende pas du Pod** : c'est ce qui suit.

### 8.3 Volumes, demandes et classes

#### 8.3.1 Trois objets, trois rôles

Avant de les utiliser, les trois objets avec un exemple de la vie quotidienne. Imagine un immeuble de bureaux. Les **espaces de bureau** existent : quelqu'un les a construits, ils ont une taille et un emplacement. Une **demande de location** dit « j'ai besoin d'un bureau de tant de mètres carrés, pour qu'une seule entreprise y travaille » ; elle ne dit pas lequel. Et le **type de bureau** (avec vue, sans vue, au sous-sol) décrit comment ils sont construits et combien ils coûtent. Dans Kubernetes :

| Dans l'immeuble | Dans Kubernetes | Qui le crée | Ce qu'il dit |
|---|---|---|---|
| l'espace de bureau | `PersistentVolume` (PV) | l'administrateur du cluster, ou le système, à la demande | « il existe un stockage de cette taille, à cet endroit, avec ces règles » |
| la demande de location | `PersistentVolumeClaim` (PVC) | celui qui déploie l'application | « j'ai besoin de cette taille, avec ce mode d'accès » |
| le type de bureau | `StorageClass` | l'administrateur du cluster | « voici comment se crée un volume de cette classe » |

La [documentation des volumes persistants](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) définit les deux premiers en ces termes : un PersistentVolume est « un morceau de stockage dans le cluster qui a été provisionné par un administrateur ou provisionné dynamiquement à l'aide de classes de stockage. C'est une ressource du cluster, tout comme un nœud ». Et une PersistentVolumeClaim « est une demande de stockage faite par un utilisateur. Elle est similaire à un Pod ». L'analogie avec le Pod va plus loin qu'il n'y paraît : de même qu'un Pod consomme des ressources d'un nœud, une demande consomme des ressources d'un volume ; et de même qu'un Pod peut demander du CPU et de la mémoire, une demande réclame une taille et un mode d'accès.

Un détail de nommage qui trouble ceux qui arrivent : le PV **n'a pas d'espace de noms** (il appartient au cluster, comme un nœud ; dans la sortie de `kubectl api-resources --namespaced=false`, il apparaît à côté de `nodes` et `namespaces`), et la PVC **en a un** (elle vit dans `revisor`, à côté des Pods qui l'utilisent).

```text
$ kubectl api-resources --api-group='' --namespaced=false -o name | grep -E '^(persistentvolumes|nodes|namespaces)$'
namespaces
nodes
persistentvolumes
```

#### 8.3.2 Les deux chemins pour obtenir un volume

La même page décrit deux façons pour qu'une demande trouve son volume :

- **Statique.** « Un administrateur du cluster crée un certain nombre de PV. » Les PV existent déjà, et une demande qui correspond à l'un d'eux (en taille, en mode d'accès, en classe) s'y lie. C'est ce qui se passe avec des disques que quelqu'un a préparés manuellement.
- **Dynamique.** « Quand aucun des PV statiques créés par l'administrateur ne correspond à la demande d'un utilisateur, le cluster peut tenter de provisionner dynamiquement un volume pour elle. » Personne ne crée le PV : c'est un programme du cluster, le *provisionneur*, qui le crée à partir de la classe demandée par la demande.

Et le déroulement, que la documentation appelle le cycle de vie : d'abord le provisionnement ; puis la liaison (*binding*) : « une boucle de contrôle du plan de contrôle surveille les nouvelles PVC, trouve un PV correspondant (si possible) et les lie » ; ensuite l'utilisation : « une fois que l'utilisateur a une demande et qu'elle est liée, le PV lié lui appartient aussi longtemps qu'il en a besoin » ; et à la fin la récupération (*reclaim*), quand l'utilisateur n'en a plus besoin. Note une phrase de cette page, car tu vas la voir se réaliser : « les demandes restent indéfiniment non liées s'il n'existe aucun volume correspondant ». La liaison est aussi un-à-un : un PV pour une demande, et une demande pour un PV.

Le cours utilise les deux chemins, chacun là où il enseigne quelque chose. Le dynamique est le chemin normal et c'est celui qu'utilise le rapport de la leçon. Le statique, tu l'utiliseras en 8.7 pour fabriquer un disque avec les règles d'un vrai.

#### 8.3.3 La classe de kind

Ce cluster apporte déjà une classe. On l'interroge :

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  4m31s

$ kubectl get storageclass standard -o jsonpath='{.provisioner} {.reclaimPolicy} {.volumeBindingMode} {.allowVolumeExpansion}{"\n"}'
rancher.io/local-path Delete WaitForFirstConsumer

$ kubectl get pods -n local-path-storage
NAME                                      READY   STATUS    RESTARTS   AGE
local-path-provisioner-75f7fc7dc5-xl4bd   1/1     Running   0          4m26s

$ kubectl get pv
No resources found
```

Une classe avec quatre informations qui comptent (et une cinquième, qui n'a pas de valeur ici) :

- **`standard (default)`** est son nom, et la parenthèse dit que c'est la **classe par défaut** : la documentation des classes dit que, quand une demande ne fixe pas `storageClassName`, « la classe par défaut est utilisée ». Le cours la nomme tout de même dans son manifeste, parce qu'un manifeste qui dit ce qu'il utilise se lit sans dépendre d'une configuration du cluster.
- **`rancher.io/local-path`** est le provisionneur. Dans l'espace de noms `local-path-storage`, il y a un Pod, `local-path-provisioner`, qui surveille les demandes de cette classe et leur crée le volume. La documentation du projet le décrit ainsi : « offre aux utilisateurs de Kubernetes un moyen d'utiliser le stockage local de chaque nœud », et le volume qu'il crée est, par défaut, un dossier du nœud, de type `hostPath`. Deux phrases de ce même README, dont nous nous servirons plus loin, note-les : il ne prend pas en charge de limite de capacité (« la capacité est ignorée pour l'instant »), et le dossier est créé avec la permission `0777`.
- **`Delete`** est la **politique de récupération** des volumes de cette classe : ce qu'on fait du volume quand la demande qui l'utilisait est supprimée. La documentation des volumes persistants le dit ainsi : avec `Delete`, la suppression retire à la fois l'objet PV de Kubernetes et le stockage associé. L'alternative est `Retain`, qui conserve le volume pour qu'un administrateur le récupère manuellement. La section 8.8 le mesure avec les deux.
- **`WaitForFirstConsumer`** est le **mode de liaison**, et c'est l'information la plus importante pour comprendre ce qui suit. La documentation des classes l'explique par contraste. Avec le mode `Immediate`, qui s'applique si tu ne mets rien, « la liaison de volume et le provisionnement dynamique ont lieu dès que la demande est créée ». Cela peut mal tourner quand le stockage est attaché à un lieu (un nœud, une zone), parce qu'on créerait le volume sans savoir où le Pod va tourner. Le remède : le mode `WaitForFirstConsumer` « retardera la liaison et le provisionnement d'un PersistentVolume jusqu'à ce qu'un Pod utilisant la PersistentVolumeClaim soit créé ». On décide d'abord où le Pod va tourner ; ensuite on crée le volume **à cet endroit**.
- **`ALLOWVOLUMEEXPANSION false`** (et vide dans le `jsonpath`, parce que le champ n'est pas écrit dans la classe) : la classe ne permet pas d'agrandir un volume après sa création. Tu n'en auras pas besoin ici ; si un jour un volume se remplit, cette colonne décide si la sortie est de l'agrandir ou d'en créer un plus grand et de déménager les données.

Et la fin de la sortie : **`No resources found`** dans `kubectl get pv`. Il n'y a encore aucun volume. La classe existe, le provisionneur attend, et les volumes se créent quand quelqu'un en demande et qu'un Pod les utilise.

### 8.4 La demande de volume et son attente

#### 8.4.1 Le manifeste

La leçon ajoute un fichier au projet, `reporte.yaml`, avec trois objets : le compte de service `reporte`, la demande `reportes` et le `CronJob` `reporte`. Les deux premiers se lisent maintenant ; le troisième a sa propre section, la 8.6, parce qu'il faut d'abord que tu saches ce qu'est un Job. Le fichier complet est un **programme** : `programas/08-datos-y-tareas/reporte.yaml`, et la `kustomization.yaml` de la leçon l'ajoute à sa liste de ressources.

```yaml
# reporte.yaml — Lección 8: el reporte guardado y el revisor como tarea programada.
# Cada 5 minutos, un Job le pide al revisor su reporte y lo guarda en un volumen
# persistente. El binario del revisor solo sirve HTTP (no tiene modo «una vez»),
# por eso la tarea es un curl contra su API; la lección (8.6) explica por qué.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reporte
automountServiceAccountToken: false
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reportes
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 100Mi
```

(La troisième pièce, le `CronJob`, est complète en 8.6 ; ici, on coupe pour lire d'abord la demande.) Le compte de service suit l'habitude de la Leçon 7 : un compte propre pour la tâche, sans permissions et avec `automountServiceAccountToken: false`, parce que la tâche parle au `revisor`, pas à l'API du cluster. La demande a quatre lignes qui comptent :

- **`accessModes: [ReadWriteOnce]`** est le **mode d'accès**. On l'abrège en RWO et la documentation le définit ainsi : « le volume peut être monté en lecture-écriture par **un seul nœud** ». Ce dernier mot est celui qu'on comprend de travers : c'est un nœud, pas un Pod. La même page précise que RWO « peut tout de même permettre à plusieurs Pods d'accéder (lire ou écrire) au volume quand les Pods tournent sur le même nœud ». Retiens-le, parce que l'Exercice 2 s'en sert. D'autres modes existent (`ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`) ; avec la classe de kind, celui qui s'applique est celui-ci : le tableau de la même page indique qu'un volume `HostPath` ne prend en charge que `ReadWriteOnce`, et le dossier vit sur un nœud.
- **`storageClassName: standard`** nomme la classe. Écrire le nom, même s'il s'agit de la classe par défaut, évite les surprises au manifeste dans un cluster où la classe par défaut serait une autre.
- **`storage: 100Mi`** est la taille demandée : 100 mébioctets, la même unité de mémoire que la Leçon 5. En arithmétique pure, 100 Mi suffisent pour plus d'un million de rapports de 92 octets. Dans un vrai système de fichiers, chaque fichier occupe au moins un bloc (j'ai vérifié sur la machine Docker de l'exécution qu'un fichier de 92 octets occupe 8 blocs de 512, soit 4096 octets, avec des blocs de système de fichiers de 4096), donc 100 Mi contiennent environ 25 600 fichiers, et avec 288 rapports par jour (un toutes les cinq minutes), cela fait environ 89 jours d'historique avant de devoir purger. Il y aura quelque chose à dire plus tard sur le sérieux avec lequel un cluster prend ce chiffre.
- **Il n'y a pas de `volumeName`** : la demande ne nomme aucun volume. Elle demande une classe et une taille, et le système résoudra le reste.

Avant d'appliquer, la question que la Leçon 5 a appris à poser : qu'est-ce qui changerait ?

```bash
kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
```

```text
$ kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
+  concurrencyPolicy: Forbid
+          schedulerName: default-scheduler
+  schedule: '*/5 * * * *'
+      storage: 100Mi
+  storageClassName: standard
[código de salida: 1]
```

Le `diff` ne filtre que ce qui est ajouté (les lignes qui commencent par `+ `) et, parmi elles, celles qui nomment les nouveautés de la leçon : la politique de concurrence, l'horaire, la taille et la classe. Le script imprime `[código de salida: 1]` parce qu'il tourne avec `pipefail` et conserve le 1 de `kubectl diff` (il y a des différences, comme à la Leçon 5) ; dans ton terminal, le pipeline renvoie le code de `grep` et tu verras 0. (La ligne `schedulerName` est ajoutée par le cluster comme valeur par défaut ; le `grep` l'a attrapée parce qu'elle contient le mot `schedule`.)

#### 8.4.2 Appliquer, et lire le `Pending`

```bash
ctx && kubectl apply -k .
```

```text
$ kubectl apply -k .
namespace/revisor unchanged
serviceaccount/observador unchanged
serviceaccount/prueba unchanged
serviceaccount/reporte created
serviceaccount/revisor unchanged
role.rbac.authorization.k8s.io/observador unchanged
rolebinding.rbac.authorization.k8s.io/observador unchanged
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hbc69k5m5c unchanged
service/prueba unchanged
service/revisor unchanged
persistentvolumeclaim/reportes created
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
cronjob.batch/reporte created
gateway.gateway.networking.k8s.io/revisor configured
httproute.gateway.networking.k8s.io/revisor configured
networkpolicy.networking.k8s.io/acceso-revisor-salida unchanged
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged
```

Les Deployments n'ont pas changé (`unchanged`) : aucune réplique n'a redémarré. Les nouveautés sont trois objets, `serviceaccount/reporte`, `persistentvolumeclaim/reportes` et `cronjob.batch/reporte`. (Que `gateway` et `httproute` affichent `configured` apparaît dans cet `apply` et ne change rien de visible dans le service ; la leçon ne l'investigue pas.) Et maintenant, ce qui compte :

```text
$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 1s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          0s

$ kubectl describe pvc reportes -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason                Age   From                         Message
  ----    ------                ----  ----                         -------
  Normal  WaitForFirstConsumer  1s    persistentvolume-controller  waiting for first consumer to be created before binding

$ kubectl get pv
No resources found
```

`STATUS Pending`, `VOLUME` vide, `CAPACITY` vide. Pour qui vient des leçons précédentes, `Pending` sonne comme un problème (le Pod de la Leçon 5 qui ne tenait sur aucun nœud). Ici, **ce n'en est pas un**, et l'événement le dit en toutes lettres : `waiting for first consumer to be created before binding`, « en attente de la création du premier consommateur avant la liaison ». C'est le mode `WaitForFirstConsumer` de 8.3.3 en action. Il n'y a encore aucun Pod qui utilise la demande, donc le cluster n'a pas décidé sur quel nœud quoi que ce soit va tourner, et il ne peut donc pas décider sur quel nœud créer le dossier. Et `kubectl get pv` le confirme : pas de volume.

La différence avec le `Pending` de la Leçon 5 est ce qui sépare un diagnostic d'un autre. Ici, l'événement est de niveau `Normal`, il est émis par `persistentvolume-controller` et il dit qu'il attend ; là-bas, c'était un `Warning` du planificateur qui disait qu'il n'y avait nulle part où aller. La règle pour lire n'importe quel `Pending` est toujours la même : les événements disent qui attend et quoi. Un `Pending` avec `WaitForFirstConsumer` et aucun Pod qui utilise la demande, c'est un système qui fonctionne.

Le `CronJob`, pendant ce temps, existe et n'a pas encore tourné : `LAST SCHEDULE <none>`, `ACTIVE 0`. Sa première exécution arrivera au prochain multiple de cinq minutes de l'horloge. Pour ne pas attendre, la section 8.5 apprend à en demander une manuellement.

### 8.5 `Job` : la tâche qui se termine

#### 8.5.1 Le plus petit qui serve

Un **`Job`** est, selon les mots de sa documentation, une tâche qui s'exécute « jusqu'à son achèvement, puis s'arrête ». Il crée un ou plusieurs Pods et réessaie « jusqu'à ce qu'un nombre spécifié d'entre eux se terminent avec succès ». Quand ce nombre est atteint, le Job est terminé. L'important, face au Deployment, est ce qui compte comme un succès : un Pod d'un Job qui se termine avec le code 0 **est** le résultat attendu ; dans un Deployment, ce même Pod serait un échec, et le cluster le remplacerait.

Avant le vrai Job, un Job d'entraînement : `fig08_01.job-salud.yaml`, qui, une seule fois, interroge `/salud` du `revisor` puis se termine. C'est un **programme**.

```yaml
# fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
# a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
# cerrada de la Lección 7 exige para que un Pod hable con el revisor.
apiVersion: batch/v1
kind: Job
metadata:
  name: salud
  namespace: revisor
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 120
  template:
    metadata:
      labels:
        app: salud
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
      - name: salud
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["curl", "-fsS", "-m", "5", "http://revisor/salud"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Lis-le de haut en bas ; tu en reconnais presque tout. `apiVersion: batch/v1` et `kind: Job` : le groupe `batch` regroupe les Jobs et les CronJobs. Le `namespace: revisor` est écrit dans le fichier pour que le Job atterrisse là sans que tu aies à penser au `-n`. `spec.template` est le modèle de Pod, comme dans un Deployment, mais avec deux différences. La première : **il n'a pas de sélecteur**, parce que le Job l'attribue tout seul (la documentation avertit que « dans presque tous les cas, tu ne devrais pas le spécifier »). La seconde : `restartPolicy` est obligatoire et n'admet que deux valeurs, `Never` et `OnFailure`. Avec `Never`, si le conteneur échoue, le Pod reste `Failed` et le Job en crée un autre ; avec `OnFailure`, le `kubelet` redémarre le conteneur dans le même Pod. Le cours utilise `Never` : chaque tentative est un Pod à part, avec son propre journal et son propre code de sortie, et tu peux lire ce qui s'est passé dans chacun. Avec `OnFailure`, les tentatives s'empileraient dans un seul Pod.

Les deux champs du Job qui ne sont pas ceux du Pod :

- **`backoffLimit: 2`** : combien de fois réessayer avant d'abandonner. La documentation indique que la valeur par défaut est 6, et que les Pods échoués sont recréés « avec un délai d'attente exponentiel (10 s, 20 s, 40 s…) plafonné à dix minutes ». Ici, 2 signifie : la tentative initiale plus deux nouvelles tentatives, trois Pods au maximum.
- **`activeDeadlineSeconds: 120`** : un plafond de temps pour le Job entier, **quel que soit le nombre de Pods qu'il crée**. Quand il est atteint, le cluster arrête les Pods en cours et le Job passe à `Failed` avec la raison `DeadlineExceeded`. Et la documentation précise que ce délai a priorité sur `backoffLimit` : un Job qui est en train de réessayer ne crée plus de Pods quand le délai arrive, même s'il n'a pas épuisé ses tentatives. Les deux plafonds couvrent des pannes différentes : l'un est pour « échoue vite, plusieurs fois », l'autre pour « reste bloqué ».

La tâche elle-même, `curl -fsS -m 5 http://revisor/salud`, se lit lettre par lettre. `-f` fait sortir curl en erreur quand le serveur répond 400 ou plus (sans cette lettre, un 503 sortirait avec le code 0, et le Job le compterait comme un succès). `-sS` est silencieux mais affiche les erreurs. `-m 5` est le temps maximal de toute l'opération : 5 secondes. Et la commande s'écrit comme une liste (`["curl", ...]`) et non comme un texte pour un *shell*, parce que l'image de `curl` n'en a pas besoin ici.

```bash
ctx && kubectl apply -f fig08_01.job-salud.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/salud --timeout=180s
```

```text
$ kubectl apply -f fig08_01.job-salud.yaml
job.batch/salud created

$ kubectl get job,pods -n revisor -l app=salud
NAME              STATUS     COMPLETIONS   DURATION   AGE
job.batch/salud   Complete   1/1           4s         4s

NAME              READY   STATUS      RESTARTS   AGE
pod/salud-svx9s   0/1     Completed   0          4s

$ kubectl logs -n revisor job/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor salud -o jsonpath='{range .status.conditions[*]}{.type} {.status}{"\n"}{end}'
SuccessCriteriaMet True
Complete True
```

Le Job a duré 4 secondes et s'est terminé avec `COMPLETIONS 1/1`. Le Pod est resté `Completed` avec `READY 0/1` : ce n'est pas une erreur. Le conteneur s'est bien terminé et ne tourne plus, et le Pod est conservé pour que tu puisses lire son journal. `kubectl logs job/salud` trouve le Pod du Job et affiche ce qu'a imprimé `curl` : le JSON de `/salud`. Les conditions du Job sont deux : `SuccessCriteriaMet` (le critère de succès est rempli) et `Complete` (terminé). Qu'il y en ait deux et non une tient à ce que dit la documentation : depuis la version 1.31, le contrôleur de Jobs retarde la condition terminale (`Complete` ou `Failed`) jusqu'à ce que tous les Pods du Job soient terminés. `SuccessCriteriaMet` (et sa jumelle `FailureTarget`, que tu verras dans « L'erreur que tu vas voir ») sont les conditions qui apparaissent avant : elles disent que l'issue est déjà décidée.

On le supprime pour laisser l'espace comme il était :

```text
$ kubectl delete -f fig08_01.job-salud.yaml
job.batch "salud" deleted from revisor namespace
```

La documentation le dit : supprimer un Job nettoie les Pods qu'il a créés. Cela compte en 8.8, où la suppression des Jobs fait partie de la manœuvre.

#### 8.5.2 Le rapport conservé : la première tâche

Voici maintenant le Job de la leçon. On ne l'écrit pas à part : le `CronJob` `reporte` le porte déjà à l'intérieur, comme modèle, et `kubectl` sait créer un Job à partir de lui à tout moment, sans attendre l'horaire. C'est la façon de tester une tâche planifiée sans rester à regarder l'horloge :

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
```

```text
$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
job.batch/reporte-manual-1 created

$ kubectl get pods -n revisor -l app=reporte -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE        READINESS GATES
reporte-manual-1-t7d8l   0/1     Pending   0          3s    <none>   <none>   curso-k8s-l8-worker   <none>

$ kubectl describe pvc reportes -n revisor | sed -n '/^Used By:/,$p'
Used By:       reporte-manual-1-t7d8l
Events:
  Type    Reason                Age              From                                                                                                Message
  ----    ------                ----             ----                                                                                                -------
  Normal  WaitForFirstConsumer  7s (x2 over 9s)  persistentvolume-controller                                                                         waiting for first consumer to be created before binding
  Normal  ExternalProvisioning  3s (x2 over 3s)  persistentvolume-controller                                                                         Waiting for a volume to be created either by the external provisioner 'rancher.io/local-path' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
  Normal  Provisioning          3s               rancher.io/local-path_local-path-provisioner-75f7fc7dc5-xl4bd_3605f90f-a3ba-46c3-a75e-a794883e9732  External provisioner is provisioning volume for claim "revisor/reportes"
```

Voilà, en trois secondes, l'histoire qu'annonçait 8.3.3. Le Pod de la tâche existe et il est `Pending`, mais regarde la colonne `NOMINATED NODE` : le planificateur a déjà **désigné** un nœud, `curso-k8s-l8-worker`, même si le Pod n'est pas encore affecté (la colonne `NODE` reste à `<none>`). Avec le mode `WaitForFirstConsumer`, le planificateur décide d'abord où le Pod tournera ; la documentation des classes le dit ainsi : le volume est sélectionné ou provisionné « conformément à la topologie spécifiée par les contraintes de planification du Pod ». Cette décision prise, le provisionneur de la classe peut agir. Les événements de la demande racontent ce qui s'est passé, de haut en bas (la colonne `Age` diminue : 7 s, 3 s, 3 s) : la demande attendait un consommateur (`WaitForFirstConsumer`) ; le Pod est apparu et le contrôleur l'a fait savoir au provisionneur (`ExternalProvisioning`, ce qui signifie « un provisionneur externe doit créer le volume ») ; le provisionneur `rancher.io/local-path` a commencé (`Provisioning`). La capture a été faite à 3 secondes et c'est pourquoi elle s'arrête là ; l'événement suivant, `ProvisioningSucceeded`, avec le nom du volume créé (ici `pvc-5fcf36b8-…`), arrive un instant plus tard (lors d'une autre exécution du même script, il a eu le temps d'apparaître dans la capture). D'où le « externe » : le provisionneur est un programme à part, un Pod du cluster, et non une partie du plan de contrôle.

La ligne du haut, `Used By: reporte-manual-1-t7d8l`, est une nouveauté de cette version : elle dit quel Pod utilise la demande. À côté, `kubectl describe` peut afficher un tableau `Conditions` avec la condition `Unused`, et il faut ici être exact sur ce qui a été mesuré : dans cette capture, le tableau **n'est pas apparu** : le contrôleur de protection n'avait pas encore écrit la condition (la capture a été faite à 3 secondes). Remarque que `Used By:` liste déjà le Pod alors qu'il est `Pending` : pour cette condition, un Pod compte comme utilisateur tant qu'il n'est pas terminé, même avant d'être affecté à un nœud ; lors d'une autre exécution du même script, à 3 secondes, une condition `Unused False` est bien apparue, avec la raison `PodUsingPVC` (« un Pod utilise la demande »). Autrement dit, la condition apparaît selon l'instant où tu regardes, et tu ne peux pas compter sur elle. Attention à sa portée : la documentation définit `Unused` seulement avec les Pods qui ne sont pas terminés (un Pod en phase `Succeeded` ou `Failed` ne compte pas), alors que la protection contre la suppression de 8.8 compte n'importe quel objet Pod qui utilise la demande. Un Pod `Completed` ne maintient pas `Unused` à `False`, mais il peut maintenir la demande en `Terminating`. Le journal des modifications de Kubernetes v1.37 l'explique : la fonctionnalité `PersistentVolumeClaimUnusedSinceTime` est passée en bêta et activée par défaut, et les demandes « signalent la condition `Unused`, qui indique depuis combien de temps une demande n'est pas utilisée, pour aider à identifier les candidates au nettoyage ». C'est un indice utile dans un vieux cluster : les demandes avec `Unused True` depuis des mois sont des candidates à examiner (il se peut qu'elles aient encore des Pods terminés qui les maintiennent protégées).

```text
$ kubectl logs -n revisor job/reporte-manual-1
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json

$ kubectl get pvc -n revisor
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 13s

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,CLASE:.spec.storageClassName,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],RUTA:.spec.hostPath.path
NOMBRE                                     CLASE      NODO                  RUTA
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   standard   curso-k8s-l8-worker   /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
```

Le journal de la tâche est le `ls -ln` qu'elle imprime elle-même après avoir enregistré : un fichier, `reporte-20261021T232446Z.json`, avec la date dans son nom (année, mois, jour, `T`, heure, minute, seconde, `Z` pour UTC). C'est la réponse à la moitié de la scène : rien n'est écrasé. Propriétaire `100`, groupe `101` : ceux de l'utilisateur de la tâche, celui de l'image de `curl`.

La demande est maintenant `Bound` (liée), avec le volume `pvc-5fcf36b8-…`, 100Mi, RWO, classe `standard`. Et le volume, regardé avec les colonnes qui comptent, présente deux informations qui méritent une explication :

- **`NODO curso-k8s-l8-worker`** : le volume a une **affinité de nœud**. Il est attaché à un seul nœud, celui qu'a choisi le planificateur. C'est ce qui en fait un volume **local** : ses données sont sur le disque de cette machine, et tout Pod qui l'utilise doit y tourner. Si ce nœud est perdu, les données partent avec lui.
- **`RUTA /var/local-path-provisioner/pvc-…_revisor_reportes`** : le vrai dossier, sur le nœud. Le nom suit le modèle `<volume>_<espace de noms>_<demande>`, et c'est l'endroit où l'on peut aller regarder.

```text
$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
777 0:0 /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
total 12
drwxrwxrwx 2   0   0 4096 Oct 21 23:24 .
drwxr-xr-x 3   0   0 4096 Oct 21 23:24 ..
-rw-r--r-- 1 100 101   92 Oct 21 23:24 reporte-20261021T232446Z.json
```

Le répertoire a la permission `777` et le propriétaire `0:0` (`root`). Compare-le à celui de l'`emptyDir` de 8.2.1 : là-bas, c'était `2777` et le groupe `65532`. Ici, il n'y a ni *setgid* ni groupe de la tâche. **Bien que le Pod de la tâche déclare `fsGroup: 101`, le répertoire de ce volume n'a pas changé de propriétaire.** C'est le contraste avec le deuxième constat de 8.2.1, et la section 8.7 le développe : ce qui est mesuré ici, c'est que `fsGroup` n'a rien fait de visible sur ce type de volume. La permission `777` vient du provisionneur, qui, d'après son README, crée le dossier avec `mkdir -m 0777`. C'est pourquoi la tâche a pu écrire : non pas grâce à son groupe, mais parce que le dossier laisse entrer n'importe qui.

#### 8.5.3 Le Pod s'est terminé ; le fichier est toujours là

La preuve du volume, c'est qu'il survive au Pod qui l'a rempli. Le Pod de la première tâche est déjà terminé. On lance une seconde tâche, un nouveau Pod, avec un autre nom, qui n'a rien à voir avec le premier, sauf qu'il monte la même demande :

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
```

```text
$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-manual-1-t7d8l   0/1     Completed   0          7s

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
job.batch/reporte-manual-2 created

$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-manual-1   Complete   1/1           7s         15s
reporte-manual-2   Complete   1/1           5s         6s
```

Le second Pod voit **deux** fichiers : le sien, de `23:24:51`, et celui de la première tâche, de `23:24:46`, d'un Pod qui ne tourne plus. C'est ce que l'`emptyDir` ne pouvait pas faire. La demande, et le volume qui la soutient, ont un cycle de vie indépendant de celui des Pods. Tant que la demande existe et que le disque du nœud qui contient le dossier reste intact, les données sont conservées, même si les Pods qui les ont écrites sont terminés.

On confirme le contenu avec le nœud. La première commande est le rapport au format tableau que tu connais déjà (elle confirme seulement que le `revisor` répond comme avant) ; la seconde lit les fichiers laissés par les tâches, qui contiennent ce qu'a répondu `/api/estados` à chaque moment :

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ docker exec curso-k8s-l8-worker sh -c 'cat /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes/reporte-*.json | head -9'
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 5
  }
]
[
```

(Le `head -9` coupe la sortie à neuf lignes : le premier fichier complet et le début du second.) La scène du lundi est résolue dans sa forme : le rapport de vendredi à 18 h, heure de Mexico, serait un fichier `reporte-20261017T0000…Z.json` (18 h à Mexico, c'est 00 h UTC le samedi, et les secondes ne valent presque jamais `00` parce que le Pod démarre quelques secondes après l'horaire), l'un parmi des dizaines, aucun écrasé par le suivant.

Avant de continuer, deux questions que ce design laisse ouvertes et auxquelles la leçon répond en son lieu. La première : si le `CronJob` le fait toutes les cinq minutes, qui le fait fonctionner ? C'est la section 8.6. La seconde : si la tâche conserve un fichier et que le `revisor` conserve aussi `reporte.json` dans son `emptyDir`, pourquoi le `revisor` n'écrit-il pas directement dans le volume ? La décision du cours est que non, et l'Exercice 2 te laisse vérifier pourquoi.

### 8.6 `CronJob` : la tâche avec un horaire

#### 8.6.1 L'objet, champ par champ

Un **`CronJob`** crée des Jobs selon un horaire répété. La [documentation](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) le compare à quelque chose que tu connais peut-être déjà : « un objet CronJob ressemble à une ligne d'un fichier *crontab* (table cron) d'un système Unix. Il exécute un Job périodiquement selon un horaire donné, écrit au format Cron ». Ce qui suit est la troisième pièce de `reporte.yaml`, celle qui avait été coupée en 8.4.1 :

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: reporte
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 60
      template:
        metadata:
          labels:
            app: reporte
            # la red (red.yaml) deja a estos Pods hablar con el revisor:8080
            acceso-revisor: permitido
        spec:
          serviceAccountName: reporte
          automountServiceAccountToken: false
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 100
            runAsGroup: 101
            fsGroup: 101
            seccompProfile:
              type: RuntimeDefault
          containers:
          - name: reporte
            image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
            command:
            - sh
            - -c
            - >-
              curl -fsS -m 20
              -H "Authorization: Bearer $(cat /secretos/token)"
              -o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json
              http://revisor/api/estados
              && ls -ln /datos
            resources:
              requests: {cpu: 10m, memory: 16Mi}
              limits: {cpu: 100m, memory: 32Mi}
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
            persistentVolumeClaim:
              claimName: reportes
          - name: token
            secret:
              secretName: revisor-token
              defaultMode: 0440
```

Voici les nouveautés, de haut en bas :

**`schedule: "*/5 * * * *"`** est l'horaire, au format cron à cinq champs. Selon la documentation, de gauche à droite : minute (0 à 59), heure (0 à 23), jour du mois (1 à 31), mois (1 à 12) et jour de la semaine (0 à 6, de dimanche à samedi). Un astérisque signifie « n'importe lequel », et `*/5` signifie « toutes les cinq » : `*/5 * * * *` veut dire « toutes les cinq minutes, à n'importe quelle heure, n'importe quel jour ». Les exemples de la documentation aident à en lire d'autres : `0 3 * * 1` signifie « le lundi à 3 h du matin ». Et les abréviations `@hourly`, `@daily`, `@weekly`, `@monthly` et `@yearly` existent comme raccourcis. L'Exercice 4 te demande d'écrire deux horaires.

**Dans quel fuseau horaire ?** La documentation le dit clairement : pour un CronJob sans fuseau horaire, le `kube-controller-manager` interprète l'horaire dans son fuseau local, qui dans kind est UTC. La colonne `TIMEZONE` de la sortie indiquait `<none>`, ce qui revient exactement à cela. On peut le fixer avec `.spec.timeZone` (par exemple `"America/Mexico_City"`) ; mettre `TZ=` ou `CRON_TZ=` à l'intérieur de l'horaire n'est pas admis et le cluster le rejette avec une erreur de validation, d'après la documentation. Dans un vrai cluster, le cours recommande d'écrire le fuseau ; c'est la cause de plus d'un « pourquoi s'est-il exécuté à 4 h du matin ? ».

**`concurrencyPolicy: Forbid`** : que faire si l'heure d'une nouvelle exécution arrive alors que la précédente tourne encore. Les trois valeurs, selon la documentation : `Allow` (la valeur par défaut) laisse tourner les deux en même temps ; `Forbid` n'autorise pas les exécutions concurrentes et saute la nouvelle ; `Replace` remplace celle qui tourne par la nouvelle. Pour la tâche du rapport, `Forbid` est le choix prudent : deux tâches qui écrivent en même temps dans le même volume seraient plus compliquées que nécessaire. L'Exercice 3 te laisse voir les trois à l'œuvre.

**`successfulJobsHistoryLimit: 3` et `failedJobsHistoryLimit: 3`** : combien de Jobs terminés conserver. Les valeurs par défaut sont 3 et 1, et une valeur de zéro n'en conserve aucun. On les conserve parce qu'ils sont la preuve : sans eux, un Job échoué disparaîtrait avec son journal et personne ne saurait pourquoi. On les borne parce que, sans plafond, ils s'accumuleraient (un Job toutes les 5 minutes, cela fait 288 par jour).

**`jobTemplate`** est un Job complet, celui que le CronJob crée à chaque fois. À l'intérieur, `backoffLimit: 2` et `activeDeadlineSeconds: 60` sont ceux de 8.5.1, avec un délai d'une minute : si la tâche reste bloquée, le cluster la coupe avant qu'elle ne chevauche la suivante.

**Le modèle de Pod** est déjà familier : le compte `reporte`, sans identifiants montés ; le `securityContext` de la Leçon 7 (sans `root`, utilisateur 100 et groupe 101 de l'image de `curl`) ; les ressources de la Leçon 5. L'étiquette `acceso-revisor: permitido` est celle qui ouvre le réseau : sans elle, le Pod n'atteint pas le `revisor`, et la section « L'erreur que tu vas voir » le démontre. Le volume `datos` est la demande `reportes`. Et le volume `token` monte le `Secret` de la Leçon 4, comme fichier, avec `defaultMode: 0440`.

Une remarque sur le chemin `/secretos/token` : le fichier porte le nom de la **clé** du Secret, et la Leçon 4 l'a générée avec `token=token.txt` dans Kustomize. Si un jour tu construis le Secret à la main avec `kubectl create secret generic revisor-token --from-file=token.txt`, la clé sera `token.txt` et le fichier `/secretos/token.txt` ; pour que cela coïncide, utilise `--from-file=token=token.txt`.

Un point qui mérite qu'on s'y arrête : le `secretName` du fichier dit `revisor-token`, sans le *hash*, comme dans le Deployment du `revisor`. Kustomize le réécrit en construisant le résultat, **y compris à l'intérieur d'un CronJob**. On le vérifie :

```text
$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.schedule}{" "}{.spec.concurrencyPolicy}{" "}{.spec.successfulJobsHistoryLimit}{" "}{.spec.failedJobsHistoryLimit}{" "}{.spec.timeZone}{"\n"}'
*/5 * * * * Forbid 3 3

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[1].secret.secretName}{"\n"}'
revisor-token-hbc69k5m5c

$ kubectl get secret -n revisor -o name
secret/revisor-token-hbc69k5m5c
```

Le champ `timeZone` est sorti vide (l'horaire est en UTC). Le nom du Secret dans le modèle du CronJob est le nom généré, avec son *hash* : Kustomize a trouvé la référence et l'a changée, comme il l'avait fait pour le Deployment. Cela compte pour les programmes de la leçon : les exemples `fig08_NN` qui ne passent pas par Kustomize (ceux qui s'appliquent avec `kubectl apply -f`) ne peuvent pas désigner le Secret par son nom de base, et c'est pourquoi aucun ne le monte.

La tâche elle-même est un `sh -c` avec deux commandes reliées par `&&` : le `curl` (avec quatre options et une adresse) et `ls -ln /datos`. Elle se lit option par option, de gauche à droite : `curl -fsS -m 20` (comme dans le Job d'entraînement, mais avec 20 secondes, parce que construire un rapport interroge des services et peut prendre plus de temps) ; `-H "Authorization: Bearer $(cat /secretos/token)"` (l'en-tête avec le token, lu dans le fichier monté au moment de l'exécution et qui n'apparaît jamais écrit dans le manifeste) ; `-o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json` (enregistre la réponse dans un fichier dont le nom porte l'heure UTC de cet instant, avec `date -u`) ; et `http://revisor/api/estados`, l'adresse du Service. Si le `curl` échoue, le `&&` empêche la suite et la tâche sort avec le code de `curl` : le Job le compte comme un échec. S'il fonctionne, `ls -ln /datos` imprime la liste, ce que tu as vu dans le journal des tâches manuelles.

Pourquoi un `curl` contre l'API et non une tâche qui exécute le `revisor` lui-même une fois puis se termine ? Parce que le `revisor` est un serveur HTTP et n'offre pas de mode « vérifie une fois ». C'est une décision du cours, pas une astuce : on préfère tirer parti du programme tel que le livre le cours de Docker, sans le modifier. La tâche est un client du `revisor` comme n'importe quel autre.

#### 8.6.2 Voir passer l'horaire

Le vrai horaire est de cinq minutes. Pour le voir fonctionner sans l'attendre, `fig08_03.cron-cada-minuto.yaml` est un CronJob qui s'exécute chaque minute (`* * * * *`) et interroge `/salud`, qui ne demande pas de token. C'est un **programme** ; son modèle est celui du Job d'entraînement et la nouveauté est l'en-tête.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: salud-cada-minuto
  namespace: revisor
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 30
      template:
        # … la plantilla del Job de práctica (etiqueta acceso-revisor incluida), con una
        # diferencia: el comando imprime primero la hora, para poder leerla en la bitácora:
        #   command: ["sh", "-c", "date -u +%T; curl -fsS -m 5 http://revisor/salud"]
```

(Le fichier complet, avec le modèle, se trouve dans le dossier des programmes.) Ce qui change par rapport à `reporte` : l'horaire, un historique plus court et `backoffLimit: 0`, ce qui signifie « sans nouvelle tentative » : une tâche qui s'exécute chaque minute n'a pas besoin de réessayer, car la minute suivante est la nouvelle tentative. L'attente est visible : le script regarde toutes les 10 secondes combien de Jobs le CronJob a terminés et s'arrête quand il y en a deux.

```bash
ctx && kubectl apply -f fig08_03.cron-cada-minuto.yaml
```

```text
$ date -u +%H:%M:%S
23:24:56

$ kubectl get cronjob reporte -n revisor
NAME      SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
reporte   */5 * * * *   <none>     False     0        <none>          20s

$ kubectl apply -f fig08_03.cron-cada-minuto.yaml
cronjob.batch/salud-cada-minuto created

(esperando hasta 200 s a que el CronJob cree y termine 2 Job(s) «salud-cada-minuto…»; se mira cada 10 s)
  +  0 s: 0 Job(s) terminados
  + 10 s: 1 Job(s) terminados
  + 20 s: 1 Job(s) terminados
  + 30 s: 1 Job(s) terminados
  + 40 s: 1 Job(s) terminados
  + 50 s: 1 Job(s) terminados
  + 60 s: 1 Job(s) terminados
  + 70 s: 2 Job(s) terminados
```

Dix secondes après sa création, il y avait déjà un Job terminé : le CronJob n'a pas attendu une minute complète, mais la **minute suivante de l'horloge** (`:25:00`), qui est arrivée 4 secondes après `23:24:56`. Un horaire cron ne compte pas « toutes les 60 secondes depuis ta création » : il se déclenche aux instants que sa formule marque sur l'horloge. Et à 70 secondes, le second (le script regarde toutes les 10 secondes, et la minute suivante est arrivée à 64).

```text
$ kubectl get cronjob,jobs -n revisor
NAME                              SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte             */5 * * * *   <none>     False     0        67s             91s
cronjob.batch/salud-cada-minuto   * * * * *     <none>     False     0        7s              71s

NAME                                   STATUS     COMPLETIONS   DURATION   AGE
job.batch/reporte-29877085             Complete   1/1           4s         67s
job.batch/reporte-manual-1             Complete   1/1           7s         86s
job.batch/reporte-manual-2             Complete   1/1           5s         77s
job.batch/salud-cada-minuto-29877085   Complete   1/1           4s         67s
job.batch/salud-cada-minuto-29877086   Complete   1/1           3s         7s
```

Il y a beaucoup à lire ici, et tout est la preuve que l'horaire fonctionne :

- **`cronjob.batch/reporte` s'est aussi exécuté, tout seul.** `LAST SCHEDULE 67s` et un nouveau Job, `reporte-29877085`, que personne n'a créé : c'est le CronJob qui l'a créé à `23:25:00`, le multiple de cinq minutes le plus proche, pendant que la leçon attendait autre chose. La vraie tâche du projet est déjà au travail.
- **Les noms des Jobs.** `reporte-manual-1`, c'est toi qui l'as nommé. `reporte-29877085`, c'est le CronJob qui l'a nommé : son nom, un tiret et un nombre. Le nombre, ce sont les **minutes écoulées depuis le 1er janvier 1970 (UTC)**, l'époque Unix : `29877085 × 60` secondes donne `2026-10-21T23:25:00Z`, et `29877086`, la minute suivante. C'est un détail observé, non documenté, qui permet de lire d'un coup d'œil une liste de Jobs : deux nombres consécutifs, ce sont deux minutes qui se suivent. Et de là vient une contrainte que la documentation énonce bel et bien : le nom d'un CronJob ne doit pas dépasser 52 caractères, car, selon la documentation, le contrôleur lui en ajoute 11 et le nom d'un Job ne peut pas dépasser 63 (lors de l'exécution, 9 ont été ajoutés : un tiret et 8 chiffres ; la documentation en réserve davantage par prudence).
- **Le CronJob de chaque minute a deux Jobs, `…085` et `…086`**, de minutes consécutives, et `LAST SCHEDULE 7s` : le dernier date d'il y a 7 secondes.

```text
$ kubectl logs -n revisor -l app=salud --prefix --tail=3
[pod/salud-cada-minuto-29877085-lbt8h/salud] 23:25:01
[pod/salud-cada-minuto-29877085-lbt8h/salud] {"estado":"vivo","version":"1.6.0"}
[pod/salud-cada-minuto-29877086-j7h2l/salud] 23:26:01
[pod/salud-cada-minuto-29877086-j7h2l/salud] {"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor -l app=salud -o custom-columns=NOMBRE:.metadata.name,PROGRAMADA:.metadata.annotations.batch\\.kubernetes\\.io/cronjob-scheduled-timestamp
NOMBRE                       PROGRAMADA
salud-cada-minuto-29877085   2026-10-21T23:25:00Z
salud-cada-minuto-29877086   2026-10-21T23:26:00Z
```

Regarde les heures des journaux : `23:25:01` et `23:26:01` ; elles viennent de ce `date -u +%T` que la commande de `fig08_03` imprime avant le `curl`. Le Job était planifié pour `:00`, mais le Pod a commencé à tourner 1 seconde plus tard dans les deux cas (lors d'une autre exécution du même script, c'était 5 et 9 : l'écart change avec la charge). Entre l'instant de l'horaire et l'instant de l'exécution, il y a un intervalle : le CronJob crée le Job, le Job crée le Pod, le planificateur l'affecte et le `kubelet` démarre le conteneur. L'annotation `batch.kubernetes.io/cronjob-scheduled-timestamp`, que le CronJob écrit sur chaque Job depuis la version 1.32, conserve l'heure **d'origine** de l'horaire, au format RFC 3339 (la forme `2026-10-21T23:25:00Z` que tu vois dans la colonne `PROGRAMADA`) : elle sert à savoir quelle exécution était laquelle même si elles ont pris du retard. La documentation le dit avec un avertissement qu'il vaut mieux lire en entier : un CronJob crée un Job « environ une fois par instant de son horaire », et c'est approximatif parce qu'« il existe des circonstances où deux Jobs pourraient être créés, ou aucun. Kubernetes essaie d'éviter ces situations, mais ne les évite pas complètement. Par conséquent, les Jobs que tu définis doivent être **idempotents** ».

**Idempotent**, au sens strict, signifie : l'exécuter deux fois laisse le monde dans le même état que l'exécuter une fois. La tâche du rapport n'est **pas** strictement idempotente : si, par un faux pas, elle s'exécutait deux fois dans la même minute, elle laisserait deux fichiers et non un. Ce qu'elle est : **sûre face aux répétitions**. Comme l'heure du nom comporte les secondes, deux exécutions écrivent deux fichiers différents et aucun n'écrase l'autre (si deux Pods tournaient à la même seconde exacte, le second remplacerait le premier par un rapport équivalent, sans rien corrompre). Une tâche qui incrémenterait un compteur ou enverrait un e-mail ne serait pas sûre ainsi, et il faudrait la protéger autrement, par exemple avec une clé unique par horaire. C'est la raison de fond pour laquelle les noms portent l'heure et non un numéro consécutif.

On supprime le CronJob d'entraînement, et avec lui ses Jobs et ses Pods :

```text
$ kubectl delete -f fig08_03.cron-cada-minuto.yaml
cronjob.batch "salud-cada-minuto" deleted from revisor namespace

$ kubectl get jobs,pods -n revisor -l app=salud
No resources found in revisor namespace.
```

Deux autres choses qu'enseigne la documentation du CronJob, même si cette leçon ne les exécute pas. La première : `.spec.suspend: true` suspend les exécutions suivantes sans rien supprimer ; celles qui tombent pendant la suspension comptent comme manquées. La seconde : `startingDeadlineSeconds` dit combien de secondes après son heure on peut encore créer le Job, et si ce délai est dépassé, cette exécution est sautée. Sans ce champ, un contrôleur en panne pendant quelques heures peut laisser de nombreuses exécutions en attente ; la documentation explique que, s'il y a plus de 100 exécutions manquées depuis la dernière, le CronJob refuse de démarrer et enregistre une erreur. En production, avec des tâches importantes, mieux vaut le fixer.

### 8.7 Le propriétaire des fichiers : `fsGroup`

#### 8.7.1 Ce que `fsGroup` a changé, et ce qu'il n'a pas changé

Depuis la Leçon 4, le Deployment du `revisor` porte `fsGroup: 65532` et le CronJob, `fsGroup: 101`. Il est temps de donner l'histoire complète. Le [guide du contexte de sécurité](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) l'explique par un exemple. Un Pod avec `fsGroup: 2000` fait que « tous les processus du conteneur font aussi partie du groupe supplémentaire 2000 », et que « le propriétaire du volume `/data/demo` et de tout fichier créé dans ce volume sera le groupe 2000 ». Sa sortie d'exemple est le répertoire avec le groupe 2000 et les permissions `drwxrwsrwx`, le même schéma que tu as déjà vu. Et dans la section de discussion : `fsGroup` s'applique aux volumes « qui prennent en charge la gestion des propriétaires », qui sont modifiés pour appartenir au groupe indiqué par `fsGroup` et être accessibles en écriture par lui.

Ces deux mots, **qui prennent en charge**, sont ceux qu'on mesure ici. Les trois volumes de la leçon, côte à côte. La dernière commande a besoin du nom du nœud et de l'`uid` d'une réplique **de ton cluster**, qui sont différents ; on les obtient ainsi :

```bash
REV_POD="$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
REV_NODE="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.spec.nodeName}')"
REV_UID="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.metadata.uid}')"
docker exec "$REV_NODE" stat -c '%a %u:%g %n' "/var/lib/kubelet/pods/$REV_UID/volumes/kubernetes.io~empty-dir/datos"
```

La sortie de l'exécution, avec le nœud et l'`uid` de cette réplique :

```text
$ kubectl get pod -n revisor -l app=revisor -o jsonpath='{.items[0].spec.securityContext.fsGroup}{"\n"}'
65532

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.securityContext}{"\n"}'
{"fsGroup":101,"runAsGroup":101,"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}}

$ docker exec curso-k8s-l8-worker2 stat -c '%a %u:%g %n' /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
2777 0:65532 /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
```

Voilà les deux `fsGroup` déclarés (65532 dans le `revisor`, 101 dans la tâche). Et le `stat` de l'`emptyDir` d'un `revisor` actuel : `2777` et groupe `65532` : **dans l'`emptyDir`, `fsGroup` a bien changé le groupe et posé le *setgid***. En revanche, le volume de la demande `reportes` (8.5.2) avait `777 0:0` bien que son Pod déclare `fsGroup: 101`. La raison, comme l'a raconté le README du provisionneur et comme la mesure le confirme : le provisionneur crée un dossier ordinaire du nœud avec la permission `0777`, et la mesure montre que le `kubelet` n'en a pas changé le groupe (la documentation dit seulement que `fsGroup` agit sur les volumes « qui prennent en charge la gestion des propriétaires » et ne donne pas la liste ; ce que nous avons mesuré, c'est que, sur ce volume, il ne l'a pas fait, et que, sur l'`emptyDir` et sur le volume `local` de 8.7.2, il l'a fait. Le PV que crée ce provisionneur est de type `hostPath` : la colonne `RUTA` de 8.5.2 vient de `spec.hostPath.path`). Ce n'était d'ailleurs pas nécessaire : avec `777`, n'importe quel utilisateur écrit.

Ce n'est pas un oubli du cours : c'est une différence entre la classe `standard` de kind et un disque qui naît avec le propriétaire `root` et la permission `755`, comme celui que 8.7.2 fabrique à la main. Là, un conteneur qui tourne comme utilisateur 100 reçoit `Permission denied` en essayant d'écrire, **à moins que** `fsGroup` ne lui donne le groupe du répertoire. Avec la classe `standard` de kind, il est peu probable que tu voies cette erreur, et c'est précisément le danger : un manifeste qui fonctionne parce que le dossier est en `777` peut échouer dans un autre cluster pour la raison même qui fait exister `fsGroup`. Un manifeste qui porte déjà `fsGroup` est plus près de fonctionner avec un tel disque. C'est pourquoi le cours l'écrit même si cela ne se voit pas ici.

#### 8.7.2 Un disque comme les vrais

Pour voir `fsGroup` à l'œuvre, il faut un volume qui le prenne en charge. Kubernetes en a un sous la main : le type `local`, un dossier d'un nœud présenté comme un disque (la documentation le décrit comme « un périphérique de stockage local monté : un disque, une partition ou un répertoire »). À la différence du provisionneur de kind, ici **c'est toi** l'administrateur : tu crées le dossier sur le nœud, tu crées le PV qui le décrit, et tu crées la demande qui le réclame. C'est le chemin statique de 8.3.2. On prend comme exemple `fig08_04.disco-local.yaml`, un **programme** avec deux objets :

```yaml
# fig08_04.disco-local.yaml — Lección 8: un volumen creado a mano por «el administrador»,
# como los de un clúster real. Un PersistentVolume de tipo local (una carpeta de UN nodo,
# que hay que crear antes: mkdir -p /mnt/disco-reportes dentro del nodo curso-k8s-l8-worker)
# y la solicitud (PersistentVolumeClaim) que lo reclama. Su clase «manual» no existe como
# objeto: sirve solo de etiqueta para que la solicitud encuentre este volumen y no pida uno
# nuevo a la clase por omisión.
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disco-reportes
spec:
  capacity:
    storage: 100Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  local:
    path: /mnt/disco-reportes
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [curso-k8s-l8-worker]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: disco
  namespace: revisor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources:
    requests:
      storage: 100Mi
```

Les nouveaux champs du PV : **`capacity`** est la taille qu'il offre ; **`persistentVolumeReclaimPolicy: Retain`** est la politique de récupération que mesure 8.8 ; **`local.path`** est le dossier du nœud ; et **`nodeAffinity`** est obligatoire dans un volume `local` : la documentation dit « tu dois mettre un `nodeAffinity` sur le PersistentVolume quand tu utilises des volumes `local`. Le planificateur de Kubernetes utilise cette affinité pour planifier les Pods sur le bon nœud ». Ici, elle dit que le volume se trouve sur le nœud dont le nom est `curso-k8s-l8-worker`. La classe `manual` n'existe pas comme objet ; c'est seulement un mot qui relie les deux objets entre eux et évite que la demande ne tombe dans la classe par défaut. Que la demande n'échoue pas à cause d'une classe inexistante (comme cela arrive dans l'Exercice 1) s'explique : le provisionnement dynamique n'est tenté que lorsqu'aucun volume déjà existant ne correspond à la demande, et ici le PV existait.

Le dossier du nœud se prépare d'abord, avec les permissions de `root` et le mode `755`, comme le laisserait un disque tout juste formaté, puis on applique le fichier :

```bash
docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes
docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
ctx && kubectl apply -f fig08_04.disco-local.yaml
```

```text
$ docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
755 0:0 /mnt/disco-reportes

$ kubectl apply -f fig08_04.disco-local.yaml
persistentvolume/disco-reportes created
persistentvolumeclaim/disco created

$ kubectl get pv,pvc -n revisor
NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/disco-reportes                             100Mi      RWO            Retain           Bound    revisor/disco      manual         <unset>                          0s
persistentvolume/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound    revisor/reportes   standard       <unset>                          85s

NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/disco      Bound    disco-reportes                             100Mi      RWO            manual         <unset>                 0s
persistentvolumeclaim/reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 94s
```

Le `stat` du nœud dit `755 0:0` : appartenant à `root`, et seul `root` peut écrire. Le PV `disco-reportes` naît `Bound` (lié) dans la seconde même où il existe, avec la politique `Retain`, et la demande `disco` sort elle aussi `Bound` dans cette capture. Attention : l'instant compte. Lors de deux autres exécutions du même script, la capture est tombée avant la fin de la liaison : une fois avec la demande encore `Pending` et le volume déjà `Bound`, une autre avec le volume encore `Available`. La liaison prend une fraction de seconde ; si tu vois `Pending` dans ton terminal, répète le `get` et elle se complète. Il n'y a pas eu d'attente du premier consommateur : la classe `manual` n'est pas une classe à mode de liaison retardée, et le volume existait déjà. Plus bas, le volume `pvc-5fcf36b8-…` est celui de `reportes`, avec la politique `Delete` de sa classe. Dans un vrai cluster, tu ne laisserais pas la classe comme une étiquette libre : la documentation demande de créer une `StorageClass` pour les volumes `local` avec `volumeBindingMode: WaitForFirstConsumer`, pour que la demande ne se lie pas à un disque d'un nœud avant de savoir où le Pod va tourner. Ici, on l'omet parce qu'il n'y a qu'un PV et que son affinité décide du nœud.

Voici maintenant deux Pods qui font la même chose et ne diffèrent que d'une ligne. Ils écrivent un fichier dans `/datos`, en tournant sous l'utilisateur 100 et le groupe 101, sans `root`. Le premier, `fig08_05.escritor-sin-fsgroup.yaml`, ne déclare pas `fsGroup` :

```yaml
# fig08_05.escritor-sin-fsgroup.yaml — Lección 8: un Pod que corre sin root (usuario 100,
# grupo 101) e intenta escribir en el disco local de fig08_04, cuyo directorio es de root
# con permiso 0755. Sin fsGroup, nadie le cambia el dueño al directorio: Permission denied.
apiVersion: v1
kind: Pod
metadata:
  name: sin-fsgroup
  namespace: revisor
  labels:
    app: escritor
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
  - name: escritor
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sh", "-c", "id; ls -lnd /datos; echo hola > /datos/a.txt && ls -ln /datos"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
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
    persistentVolumeClaim:
      claimName: disco
```

Le second, `fig08_06.escritor-con-fsgroup.yaml`, est le même fichier avec `name: con-fsgroup` et une ligne de plus dans le `securityContext` du Pod : `fsGroup: 101`. La commande des deux est courte : `id` imprime qui est le processus ; `ls -lnd /datos` imprime le propriétaire et la permission du répertoire monté ; et `echo hola > /datos/a.txt && ls -ln /datos` essaie d'écrire et, si cela a réussi, liste.

```bash
ctx && kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
```

```text
$ kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
pod/sin-fsgroup created

$ kubectl get pod -n revisor sin-fsgroup
NAME          READY   STATUS   RESTARTS   AGE
sin-fsgroup   0/1     Error    0          4s

$ kubectl logs -n revisor sin-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxr-xr-x    2 0        0             4096 Oct 21 23:26 /datos
sh: can't create /datos/a.txt: Permission denied
```

Voilà l'erreur que `fsGroup` évite, mesurée. Elle se lit en trois lignes : le processus est l'utilisateur 100, avec le groupe 101 et aucun autre ; le répertoire appartient à `0:0` avec `drwxr-xr-x` (seul `root` écrit : l'utilisateur 100 tombe dans la catégorie « autres », qui a la lecture et l'accès, mais pas l'écriture) ; et le `sh` le dit sans détour, `can't create /datos/a.txt: Permission denied`. Le Pod est resté en `Error` : la commande a échoué, et avec `restartPolicy: Never` il ne redémarre pas. Voici maintenant le même Pod avec la ligne en plus :

```bash
ctx && kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
ctx && kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
```

```text
$ kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
pod "sin-fsgroup" deleted from revisor namespace

$ kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
pod/con-fsgroup created

$ kubectl get pod -n revisor con-fsgroup
NAME          READY   STATUS      RESTARTS   AGE
con-fsgroup   0/1     Completed   0          3s

$ kubectl logs -n revisor con-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxrwsr-x    2 0        101           4096 Oct 21 23:26 /datos
total 4
-rw-r--r--    1 100      101              5 Oct 21 23:26 a.txt

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
2775 0:101 /mnt/disco-reportes
```

`Completed`, et le fichier `a.txt` de 5 octets (`hola` et un saut de ligne) est écrit. Regarde le répertoire dans le journal : `drwxrwsr-x`, groupe `101`. Et sur le nœud, `stat` indique `2775 0:101` : **le `kubelet` a changé le groupe du dossier en 101 et a donné la permission d'écriture à ce groupe, avec *setgid*, avant de démarrer le conteneur**. Le processus appartient au groupe 101, et c'est pourquoi il peut écrire. Le propriétaire reste `root` ; ce qui a changé, c'est le groupe. C'est ce que dit la documentation : les volumes qui prennent en charge la gestion des propriétaires « sont modifiés pour appartenir au GID indiqué par `fsGroup` et être accessibles en écriture par lui ».

Le *setgid* (le `s`) a un effet pratique qui fait que `fsGroup` en vaut la peine : les fichiers créés dans le répertoire **héritent de son groupe**, le 101, et non du groupe primaire du processus qui les crée. Ici l'effet ne se voit pas, parce que le processus est déjà du groupe 101 (`runAsGroup: 101`) ; il se verrait avec un processus d'un autre groupe primaire. Et pour qu'un autre Pod du groupe 101 puisse *modifier* ces fichiers, chaque fichier aurait besoin d'une permission de groupe (umask 002), ce que cette tâche ne demande pas : ses fichiers sortent en `-rw-r--r--`.

Une remarque de coût, qu'explique la documentation du contexte de sécurité : par défaut, Kubernetes change le propriétaire et les permissions de **tout le contenu** du volume à chaque montage. Pour un volume de plusieurs millions de fichiers, cela prend du temps et retarde le démarrage du Pod. Le champ `fsGroupChangePolicy: OnRootMismatch` demande que le changement ne se fasse que si le propriétaire ou la permission de la racine du volume ne correspondent pas à ce qui est attendu, et évite de le parcourir quand tout est déjà en ordre. Avec des volumes de 100 Mi, cela ne se remarque pas ; avec de gros disques, si.

#### 8.7.3 Retain : le volume survit à sa demande

Les deux Pods ne sont plus nécessaires. Et le disque fait à la main sert aussi à voir ce qu'on ne peut pas voir avec `Delete` : la politique `Retain`. On supprime la demande :

```bash
ctx && kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
ctx && kubectl delete pvc -n revisor disco
```

```text
$ kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
pod "con-fsgroup" deleted from revisor namespace

$ kubectl delete pvc -n revisor disco
persistentvolumeclaim "disco" deleted from revisor namespace

$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
disco-reportes                             100Mi      RWO            Retain           Released   revisor/disco      manual         <unset>                          11s
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound      revisor/reportes   standard       <unset>                          96s
```

La demande est partie ; le volume, **non**. Son état est `Released` (« libéré »), que la documentation définit ainsi : « la demande a été supprimée, mais la ressource de stockage associée n'a pas encore été récupérée par le cluster ». Avec `Retain`, le volume garde son `CLAIM revisor/disco` annoté et n'est pas disponible pour une autre demande, car « les données du demandeur précédent restent sur le volume ». Le récupérer est un travail manuel de l'administrateur, en trois étapes que dit la documentation : supprimer le PV, nettoyer les données du stockage et supprimer le stockage associé (ou le réutiliser avec un nouveau PV). On supprime le PV et on regarde le disque :

```text
$ kubectl delete pv disco-reportes
persistentvolume "disco-reportes" deleted

$ docker exec curso-k8s-l8-worker ls -ln /mnt/disco-reportes
total 4
-rw-r--r-- 1 100 101 5 Oct 21 23:26 a.txt
```

L'objet PV a disparu de Kubernetes ; le dossier du nœud, et le fichier `a.txt` qu'a écrit le Pod, sont toujours là. C'est `Retain` : le cluster lâche l'objet et ne touche pas aux données. C'est la politique qu'on choisit pour des données qui ne doivent pas disparaître à cause d'un `kubectl delete` malheureux, en échange d'un travail de nettoyage manuel. (Le dossier vit à l'intérieur du conteneur du nœud, donc `kind delete cluster` l'emporte. Si tu voulais que des données survivent au cluster entier, la [configuration de kind](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts) permet de monter un dossier de ta machine dans un nœud avec `extraMounts` ; le cours ne le fait pas.)

### 8.8 Supprimer la demande de volume : là, on perd vraiment

La politique de la classe `standard` est `Delete`. On mesure ce qui se passe avec la demande `reportes`, celle qui conserve les rapports de la leçon. D'abord on regarde la politique, puis on demande la suppression **sans attendre** (`--wait=false`), parce que ce qui suit peut rester en attente :

```bash
ctx && kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
ctx && kubectl delete pvc -n revisor reportes --wait=false
```

```text
$ kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
Delete

$ kubectl delete pvc -n revisor reportes --wait=false
persistentvolumeclaim "reportes" deleted from revisor namespace

$ kubectl get pvc -n revisor
NAME       STATUS        VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Terminating   pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 111s

$ kubectl get pvc -n revisor reportes -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}{"\n"}'
["kubernetes.io/pvc-protection"] 2026-10-21T23:26:21Z

$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-29877085-6q87g   0/1     Completed   0          86s
reporte-manual-1-t7d8l   0/1     Completed   0          105s
reporte-manual-2-4hmmf   0/1     Completed   0          96s
```

`Terminating` : tu as demandé la suppression et elle n'a pas lieu. La commande a rendu la main parce qu'elle avait `--wait=false` ; sans cette option, `kubectl delete` serait resté en attente. L'explication est dans `finalizers: ["kubernetes.io/pvc-protection"]`, qui est une *marque* empêchant un objet de disparaître tant que quelque chose ne l'a pas retirée. La documentation appelle cette fonction **protection des objets de stockage en cours d'utilisation**, et son but est « de garantir que les demandes activement utilisées par un Pod, et les volumes liés à des demandes, ne soient pas retirés du système, car cela pourrait entraîner une perte de données ». Et elle définit ce qu'est « activement utilisée » : **une demande est utilisée quand il existe un objet Pod qui l'utilise.** Si tu la supprimes dans ce cas, « la suppression est reportée jusqu'à ce qu'aucun Pod ne l'utilise ».

Regarde la dernière sortie : trois Pods `Completed`. Ils sont terminés depuis longtemps et ne tournent plus, mais **ils existent comme objets** (on les a conservés pour lire leur journal), et chacun déclare dans ses volumes la demande `reportes`. Pour la protection, ils continuent de l'utiliser. La demande attend que ces Pods cessent d'exister. La sortie n'est pas de forcer la suppression, mais de retirer ceux qui la retiennent : supprimer les Jobs, qui emportent leurs Pods.

```bash
ctx && kubectl delete jobs -n revisor --all
```

```text
$ kubectl delete jobs -n revisor --all
job.batch "reporte-29877085" deleted from revisor namespace
job.batch "reporte-manual-1" deleted from revisor namespace
job.batch "reporte-manual-2" deleted from revisor namespace

$ kubectl get pvc,pv
No resources found

$ docker exec curso-k8s-l8-worker ls -la /var/local-path-provisioner/
total 8
drwxr-xr-x  2 root root 4096 Oct 21 23:26 .
drwxr-xr-x 12 root root 4096 Oct 21 23:24 ..
```

Dès que les Pods sont partis, la suppression de la demande a avancé : il n'y a plus ni demande ni volume (`No resources found`), et le dossier du nœud, `pvc-5fcf36b8-…_revisor_reportes`, **a disparu avec tous ses rapports**. Le répertoire `/var/local-path-provisioner/` est resté vide. C'est la politique `Delete` à l'œuvre : on supprime la demande, on supprime le volume et on supprime le stockage. Lors de la suppression de l'exécution, on n'a pas pu voir l'état intermédiaire `Released` du volume dynamique (le script a regardé 8 secondes après avoir supprimé les Jobs et, à ce moment-là, le volume n'existait déjà plus ; je ne sais pas en combien de temps exact il a disparu) ; celui de 8.7.3, avec `Retain`, l'a bien montré.

Recréer la demande et lancer une nouvelle tâche montre ce qui reste : rien du passé.

```bash
ctx && kubectl apply -k . | grep persistentvolumeclaim
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
```

```text
$ kubectl apply -k . | grep persistentvolumeclaim
persistentvolumeclaim/reportes created

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
job.batch/reporte-manual-3 created

$ kubectl logs -n revisor job/reporte-manual-3
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
```

Un seul fichier : celui d'aujourd'hui. Les rapports du passé ne sont plus là. Avec cela, la règle de la section tient en une phrase, pour le jour où tu le feras sans le vouloir : **avec la politique `Delete`, les données vivent aussi longtemps que vit la demande et la suppression de la demande emporte les données ; avec `Retain`, elles lui survivent et quelqu'un doit les nettoyer** (8.7.3). La politique est celle de la classe, pas de celui qui supprime : c'est pourquoi il faut savoir quelle est la classe avant de supprimer quoi que ce soit qui s'appelle `pvc`.

## L'erreur que tu vas voir

Cette leçon contient deux erreurs à dessein. La seconde, tu l'as déjà vue en 8.7.2 : le `Permission denied` du Pod qui écrit dans un volume de `root` sans `fsGroup`. La première est celle d'une tâche qui n'atteint jamais le `revisor`.

### BackoffLimitExceeded : un Job qui ne peut pas aboutir

`fig08_02.job-sin-etiqueta.yaml` est le Job d'entraînement de 8.5.1 avec **une** différence : il lui manque l'étiquette `acceso-revisor: permitido`. C'est l'erreur qu'on commet en copiant un modèle et en oubliant une ligne qui ne se voit pas.

```bash
diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
ctx && kubectl apply -f fig08_02.job-sin-etiqueta.yaml
```

Le `diff` n'est pas exécuté par le script (il ne touche pas au cluster) ; voici sa sortie, exécutée dans le dossier des programmes. Hormis les commentaires de l'en-tête et du nom, la seule différence de contenu est la ligne de l'étiquette :

```text
$ diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
1,3c1,4
< # fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
< # a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
< # cerrada de la Lección 7 exige para que un Pod hable con el revisor.
---
> # fig08_02.job-sin-etiqueta.yaml — Lección 8: el MISMO Job de fig08_01, sin la etiqueta
> # acceso-revisor. La red cerrada de la Lección 7 no lo deja salir hacia el revisor: curl se
> # rinde a los 5 s (código 28), el Job reintenta dos veces y termina Failed con
> # BackoffLimitExceeded.
7c8
<   name: salud
---
>   name: salud-sin-etiqueta
16d16
<         acceso-revisor: permitido
```

Un Job comme celui-ci n'échoue pas immédiatement. Il réessaie, avec les attentes que 8.5.1 a décrites, et la leçon le regarde à la vue de tous, toutes les 15 secondes :

```text
$ kubectl apply -f fig08_02.job-sin-etiqueta.yaml
job.batch/salud-sin-etiqueta created

(esperando hasta 150 s a que el Job agote sus reintentos; se mira cada 15 s)
  + 15 s: 1 fallidos,  activos, condiciones:
  + 30 s: 2 fallidos,  activos, condiciones:
  + 45 s: 2 fallidos, 1 activos, condiciones:
  + 60 s: 3 fallidos,  activos, condiciones: FailureTarget=True Failed=True

$ kubectl get job,pods -n revisor -l app=salud
NAME                           STATUS   COMPLETIONS   DURATION   AGE
job.batch/salud-sin-etiqueta   Failed   0/1           61s        61s

NAME                           READY   STATUS   RESTARTS   AGE
pod/salud-sin-etiqueta-9bnv9   0/1     Error    0          61s
pod/salud-sin-etiqueta-svs9r   0/1     Error    0          44s
pod/salud-sin-etiqueta-tr95q   0/1     Error    0          19s
```

**D'abord, l'état.** À 61 secondes, le Job est `Failed` et a trois Pods, tous les trois en `Error`. Ce sont exactement ceux qu'a annoncés `backoffLimit: 2` : l'original et deux nouvelles tentatives. Les âges (`61s`, `44s`, `19s` depuis leur création, lus à l'envers) racontent l'attente croissante de la documentation : le deuxième Pod est né 17 secondes après le premier (5 de `curl` plus 10 d'attente) et le troisième 25 après le deuxième (5 de plus 20). Ce ne sont pas des secondes rondes parce que le cluster en ajoute quelques-unes en créant les Pods.

**Ensuite, le journal, parce que le conteneur a bien tourné.**

```text
$ kubectl logs -n revisor job/salud-sin-etiqueta
Found 3 pods, using pod/salud-sin-etiqueta-9bnv9
curl: (28) Connection timed out after 5000 milliseconds

$ kubectl get pods -n revisor -l app=salud -o custom-columns=POD:.metadata.name,CODIGO:.status.containerStatuses[0].state.terminated.exitCode,RAZON:.status.containerStatuses[0].state.terminated.reason
POD                        CODIGO   RAZON
salud-sin-etiqueta-9bnv9   28       Error
salud-sin-etiqueta-svs9r   28       Error
salud-sin-etiqueta-tr95q   28       Error
```

`kubectl logs job/…` prévient qu'il y a trois Pods et qu'il en montre un. Le message de `curl` est celui que tu connais depuis la Leçon 7 : **code 28**, « le délai de connexion est dépassé ». Le réseau fermé ne laisse pas sortir vers le `revisor` un Pod sans l'étiquette d'accès, et il ne répond pas par un refus : il ne répond tout simplement pas, et `curl` attend ses 5 secondes (`-m 5`) puis renonce. Les trois Pods se sont terminés avec le code 28. C'est la même panne de « l'entrée ouverte par laquelle on n'entre pas » de la Leçon 7, vue depuis une tâche.

**Troisièmement, le Job : pourquoi il a renoncé.**

```text
$ kubectl get job -n revisor salud-sin-etiqueta -o jsonpath='{range .status.conditions[*]}{.type} {.status} {.reason}: {.message}{"\n"}{end}'
FailureTarget True BackoffLimitExceeded: Job has reached the specified backoff limit
Failed True BackoffLimitExceeded: Job has reached the specified backoff limit

$ kubectl describe job -n revisor salud-sin-etiqueta | sed -n '/^Events:/,$p'
Events:
  Type     Reason                Age   From            Message
  ----     ------                ----  ----            -------
  Normal   SuccessfulCreate      62s   job-controller  Created pod: salud-sin-etiqueta-9bnv9
  Normal   SuccessfulCreate      45s   job-controller  Created pod: salud-sin-etiqueta-svs9r
  Normal   SuccessfulCreate      20s   job-controller  Created pod: salud-sin-etiqueta-tr95q
  Warning  BackoffLimitExceeded  10s   job-controller  Job has reached the specified backoff limit
```

`BackoffLimitExceeded` (« la limite de nouvelles tentatives est dépassée ») est la raison de l'échec, telle que la documentation liste les causes pour lesquelles un Job échoue : « le nombre d'échecs de Pods a dépassé `.spec.backoffLimit` ». Les événements, de haut en bas, sont l'histoire en quatre lignes : trois créations et le renoncement.

**Quatrièmement, la cause, que le Job ne sait pas dire.** Rien de ce qui précède ne dit *pourquoi* le `curl` expire. C'est la comparaison avec ce qui fonctionne qui le dit. `depurar`, qui parlait bien au `revisor` en 8.1, porte une étiquette que ce Job n'a pas :

```text
$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          3m36s   acceso-revisor=permitido,app=depurar
```

`acceso-revisor=permitido` est l'étiquette que demandent les politiques réseau de la Leçon 7. Le Job de la leçon, le `CronJob` réel, la porte dans son modèle, avec un commentaire qui l'explique ; celui-ci, non. **La correction** est la même que toujours : le fichier est la vérité. On ajoute la ligne au manifeste et on l'applique de nouveau ; ici, on supprime simplement l'expérience :

```text
$ kubectl delete -f fig08_02.job-sin-etiqueta.yaml
job.batch "salud-sin-etiqueta" deleted from revisor namespace
```

Deux leçons de cette erreur. **La première** : un Job qui échoue dit qu'il a échoué, pas pourquoi ; la cause est dans le journal de ses Pods (`curl: (28)`) et dans ce que tu sais du réseau. **La seconde** : une tâche planifiée qui échoue à 3 h du matin ne réveille personne. Le `CronJob` conserve les trois derniers Jobs échoués (`failedJobsHistoryLimit: 3`) précisément pour que quelqu'un, le lendemain, puisse aller lire ce qui leur est arrivé. Sans surveillance, une tâche qui échoue en silence pendant des semaines produit le contraire de ce qu'elle promettait : le sentiment qu'il y a une sauvegarde là où il n'y en a pas. C'est la leçon du récit de GitLab qui ouvrait la leçon, en petit.

L'ordre à suivre pour une tâche qui n'a pas fonctionné : `kubectl get jobs` (`Failed` ?) ; les Pods du Job (`kubectl get pods -l …`) et le code de sortie de chacun ; le journal (`kubectl logs job/…`) ; et, si le Job n'a pas créé un seul Pod, les événements du Job lui-même (`kubectl describe job`). Avant de changer quoi que ce soit, savoir s'il a échoué une fois, toujours, ou parfois.

## L'habitude de sécurité de la leçon : les données avec leur propriétaire

Le tableau des habitudes du cours assigne deux choses à cette leçon : le `ServiceAccount` sans identifiants montés s'il n'en a pas besoin, et les données avec leur propriétaire. Les deux se vérifient dans le cluster.

**Le compte de service de la tâche.** La tâche parle au `revisor` en HTTP ; elle ne parle pas à l'API du cluster. Elle n'a pas besoin d'un identifiant pour cela, et donc on ne lui en monte pas :

```text
$ kubectl get serviceaccount reporte -n revisor -o jsonpath='{.automountServiceAccountToken}{"\n"}'
false

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.automountServiceAccountToken}{" "}{.spec.jobTemplate.spec.template.spec.containers[0].env}{"\n"}'
false

$ kubectl get pods -n revisor -l app=reporte -o custom-columns=POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name
POD                      CUENTA    AUTOMOUNT   VOLUMENES
reporte-manual-3-2657n   reporte   false       datos,token

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/api/estados
401
```

`false` dans le compte, `false` dans le modèle du CronJob, et `env` vide (la seconde valeur de la deuxième sortie est vide : la tâche ne reçoit pas de variables contenant des secrets). Les volumes du Pod de la tâche sont deux et s'appellent `datos` et `token` : **aucun n'est l'identifiant de l'API**. Si quelqu'un parvenait à exécuter du code dans la tâche, il ne trouverait aucun token du cluster à voler. Et le token du `revisor` arrive comme fichier en lecture seule avec `0440`, pas comme variable d'environnement : c'est ce qu'a enseigné la Leçon 4. La dernière sortie est la preuve que le `revisor` continue de l'exiger : sans token, `401`.

**Les données avec leur propriétaire.** Les trois éléments mesurés :

- **Le groupe du volume est posé par `fsGroup`**, pas par une permission ouverte. Sur un vrai disque, la solution à un `Permission denied` est de donner le groupe, pas un `chmod 777`. En 8.7.2, le volume appartenait à `root` avec `755`, et avec une ligne il est passé à `2775 0:101` : à `root`, groupe 101, accessible en écriture uniquement par ce groupe (et lisible par tous).
- **Le processus tourne sans `root`** et le fichier qu'il crée lui appartient : `-rw-r--r-- 1 100 101` dans la tâche ; `-rw------- 1 65532 65532` dans le `revisor`. Chaque écrivain laisse sa marque, et on peut savoir qui a écrit quoi.
- **Le token n'arrive pas dans le volume de données.** La tâche lit le token dans `/secretos`, un volume en lecture seule, et n'écrit que dans `/datos`. Garder l'entrée et la sortie séparées empêche qu'une erreur de la tâche écrive le secret à un endroit où il serait conservé.

**La taille que le cluster ne fait pas respecter.** Il reste une surprise, celle de la section 8.4.1, où l'on avait dit qu'il y aurait quelque chose à dire sur le sérieux avec lequel un cluster prend le nombre `100Mi`. Le volume a demandé 100 mébioctets et le cluster a répondu `CAPACITY 100Mi`. On le teste avec un Job, `fig08_07.llenar-el-volumen.yaml`, qui écrit 150 millions d'octets (environ 143 MiB) dans ce même volume :

```bash
ctx && kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
ctx && kubectl apply -f fig08_07.llenar-el-volumen.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/llenar --timeout=180s
ctx && kubectl logs -n revisor job/llenar
ctx && kubectl delete -f fig08_07.llenar-el-volumen.yaml
```

(Le `wait` évite de demander le journal avant que le Pod ait fini d'écrire ; le script l'exécute sans l'imprimer.)

```text
$ kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
100Mi 100Mi

$ kubectl apply -f fig08_07.llenar-el-volumen.yaml
job.batch/llenar created

$ kubectl logs -n revisor job/llenar
total 146496
-rw-r--r--    1 100      101      150000000 Oct 21 23:27 grande.bin
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
/dev/root                57.1G     48.4G      8.6G  85% /datos

$ kubectl delete -f fig08_07.llenar-el-volumen.yaml
job.batch "llenar" deleted from revisor namespace
```

Le Job s'est terminé sans erreur et `ls` montre `grande.bin` de **150000000 octets** dans un volume qui a demandé et reçu 100Mi. Et le `df` à l'intérieur du Pod en donne la raison : le « volume » `/datos` apparaît comme `/dev/root`, de 57,1 Go, utilisé à 85 % : c'est le disque du nœud, qui dans kind est celui de la machine Docker, et non un morceau de 100 Mi (le nom du périphérique et la taille changent sur ta machine). C'est exactement ce qu'avait annoncé le README du provisionneur (« la capacité est ignorée pour l'instant ») : le nombre de `storage` décide avec quel PV la demande se lie, mais la classe de kind ne limite pas ce qui est écrit.

C'est un constat de laboratoire qu'il vaut mieux ne pas oublier : **avec la classe de kind, ce que tu demandes n'est pas ce que tu obtiens ; avec d'autres stockages, cela dépend du système, et il faut le mesurer**. Dans un vrai cluster, le stockage réel a bien une taille et se remplit (avec une erreur `No space left on device` qui fait planter l'application en pleine écriture), et un espace de noms sans quota peut créer des demandes de n'importe quelle taille. Le quota de stockage (`ResourceQuota`, avec `requests.storage`) pose un maximum par espace de noms, comme on l'a évoqué à la Leçon 5 pour le CPU et la mémoire ; le cours le nomme et ne l'installe pas.

**Ce qu'elle protège et ce qu'elle ne protège pas.** Ces habitudes protègent contre le fait que la tâche ait plus de pouvoir qu'il ne lui en faut, contre la fuite du token vers le disque, et garantissent que les fichiers ont un propriétaire identifiable. Elles ne protègent pas les données : un `Delete` les supprime (8.8), un nœud en panne les rend inaccessibles (le volume est sur un seul disque), et personne ne les sauvegarde. Ce qui protège vraiment les données, c'est la ligne que la leçon 10 place dans la liste de ce qui manque pour la production : un stockage répliqué hors du nœud, des instantanés de volume et des sauvegardes qu'on **teste** en les restaurant. Une phrase sur chacun, pour que tu saches quel problème il résout : un `StatefulSet` est l'objet pour les applications avec état, dont les Pods ont une identité stable et chacun son propre volume (le cours ne l'utilise pas) ; un instantané de volume est une copie du volume à un instant donné, qui sert à revenir en arrière ; et une sauvegarde testée est la copie que quelqu'un a déjà restaurée ailleurs et vérifiée, ce qui est justement ce qui a manqué au récit de GitLab du début.

## Les erreurs courantes

**Conserver dans un `emptyDir` ce qui doit survivre au Pod.** Tu l'as vu en 8.2.3 : le conteneur survit à une panne, le Pod ne survit pas à une suppression, et vider un nœud (`drain`), une éviction ou un nœud déclaré perdu suppriment des Pods ; un redémarrage du nœud, pas nécessairement, mais il ne vaut pas la peine de parier là-dessus. Un `emptyDir` sert d'espace de travail, pas d'historique.

**Croire que `Pending` sur une demande est une erreur.** Avec `WaitForFirstConsumer`, une demande sans Pod reste `Pending`, et c'est normal. On lit l'événement avant d'agir.

**Écrire `storage: 100Mi` et croire que tout s'arrête là.** Dans kind, la taille n'est pas imposée (« L'habitude de sécurité » le mesure). En production, le disque se remplit. Il faut surveiller l'utilisation, avec des alertes, avant qu'elle n'atteigne le plafond.

**Supprimer une demande (`pvc`) sans connaître la politique de la classe.** Avec `Delete`, les données sont supprimées. Avec `Retain`, elles sont conservées et quelqu'un doit les nettoyer. On regarde `RECLAIMPOLICY` avant.

**Supprimer un PV à la main pour « libérer » une demande coincée.** La demande en `Terminating` attend les Pods qui l'utilisent ; le PV a sa propre protection. Forcer les finalizers (`kubectl patch … finalizers`) en contournant la protection est la façon d'endommager des données en cours d'utilisation. On trouve et on supprime ce qui la retient (dans cette leçon, les Jobs).

**Utiliser `chmod 777` ou un volume ouvert pour que « ça écrive enfin ».** C'est ce que fait le provisionneur de kind, et c'est pourquoi le problème se remarque rarement. Sur un vrai disque, le remède est `fsGroup` et un utilisateur sans `root`, pas ouvrir le répertoire à tout le monde.

**Écrire une tâche qui ne supporte pas de s'exécuter deux fois.** La documentation l'avertit : le CronJob peut créer deux Jobs ou aucun. Une tâche qui additionne, envoie ou facture sans protection est un doublon qui attend.

**Laisser `concurrencyPolicy: Allow` par défaut dans une tâche qui écrit dans un volume partagé.** Deux tâches en même temps dans le même dossier, et une tâche lente qui chevauche la suivante, peuvent accumuler des Pods sans que personne ne le remarque. `Forbid` ou `Replace` disent explicitement ce que tu veux.

**Un Job sans `backoffLimit` ni `activeDeadlineSeconds`.** La valeur par défaut des nouvelles tentatives est 6 et le temps n'a pas de plafond : une tâche bloquée reste bloquée. On met les deux dans les vraies tâches, avec des nombres qu'on peut justifier (les Jobs d'entraînement de la leçon, qui durent quelques secondes, ne les portent pas tous).

**Un CronJob sans historique ou avec un historique énorme.** Sans historique (`0`), il n'y a aucune preuve de ce qui a échoué. Avec un très grand nombre, les Jobs et les Pods s'accumulent par milliers. On choisit un petit nombre et on le revoit.

**Donner à la tâche un compte de service avec des permissions « au cas où ».** La tâche qui ne parle qu'en HTTP n'a pas besoin d'identifiant de l'API. `automountServiceAccountToken: false` et un compte propre sans permissions.

**Mettre le token dans la commande ou dans une variable d'environnement de la tâche.** On le lit dans le fichier monté au moment de l'exécution, comme le fait la tâche de la leçon.

**Oublier le fuseau horaire d'un CronJob.** Sans `timeZone`, l'horaire est celui du contrôleur (UTC dans kind). « Tous les jours à 3 h » n'est pas ce que tu crois si tu es à six heures d'UTC.

**Conserver le rapport de toutes les répliques dans un volume `ReadWriteOnce` local.** L'Exercice 2 le démontre : cela attache toutes les répliques à un seul nœud.

## Exercices

Les trois premiers s'exécutent dans le cluster de la leçon, dans l'ordre et à partir de l'état dans lequel il est resté après « l'habitude de sécurité ». Avant chacun, la fonction `ctx` doit te donner un succès (`ctx && echo ok`). **Avant** d'exécuter chacun, écris dans le [journal de bord](bitacora.md) ce que tu crois qu'il va se passer. Le quatrième s'écrit avec tes mots.

### Exercice 1 — Une classe de stockage qui n'existe pas

`fig08_08.pvc-clase-inexistente.yaml` crée une demande de volume qui réclame la classe `rapido` (que ce cluster n'a pas) et un Pod, `lector`, qui l'utilise. Applique-le. Avant de regarder, prédis : dans quel état la demande reste-t-elle ? Et le Pod ? Quel événement crois-tu que chacun produit, et qui l'émet ? Vérifie avec `kubectl get pvc rapido -n revisor`, `kubectl get pod lector -n revisor` et les `describe` des deux. Et la question difficile : combien de temps attendrais-tu avant de conclure que cela ne se résoudra pas tout seul ? Une fois terminé, supprime-le avec `kubectl delete -f fig08_08.pvc-clase-inexistente.yaml`.

### Exercice 2 — Le rapport du `revisor`, dans le volume

La décision du cours est que le `revisor` conserve son `reporte.json` dans l'`emptyDir` et que la tâche conserve les siens dans le volume. Vérifie-le avec un changement d'une ligne. Avec `kubectl patch`, remplace le volume `datos` du Deployment du `revisor` (le premier de la liste, `/spec/template/spec/volumes/0`) par un volume qui utilise la demande `reportes` :

```bash
ctx && kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
```

Prédis : les trois répliques démarrent-elles ? Sur quel nœud atterrit chacune ? Que dit `kubectl get pv` du volume ? Demande un rapport avec `depurar` et cherche le fichier sur le nœud. Ensuite, annule le changement avec `kubectl apply -k .` (le fichier est la vérité) et vérifie où se retrouvent les répliques. Explique en cinq phrases pourquoi ce n'est pas ce que tu veux pour le projet, et ce qui est perdu de ce que la Leçon 9 va demander.

### Exercice 3 — Une tâche qui dure plus longtemps que son horaire

`fig08_09.cron-lento.yaml` est un CronJob qui s'exécute chaque minute (`* * * * *`) avec `concurrencyPolicy: Forbid`, et dont la tâche dure **100 secondes** (`sleep 100`). Prédis, avant de l'appliquer : au bout de 2 minutes et demie, combien de Jobs tourneront en même temps ? Les Jobs des minutes intermédiaires seront-ils créés ? Quel événement le CronJob laisse-t-il quand il en saute un ? Applique-le, regarde toutes les 35 secondes pendant environ 210 secondes (la première tâche dure près de deux minutes et il faut voir comment elle se termine) avec `kubectl get cronjob lento -n revisor` et `kubectl get jobs -n revisor`, et lis `kubectl describe cronjob lento -n revisor`. Ensuite, supprime le CronJob (`ctx && kubectl delete -f fig08_09.cron-lento.yaml`), attends le début d'une minute et recrée-le avec la politique changée sans toucher au fichier : `sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -` ; répète avec `Replace`. Ainsi le fichier reste intact pour l'exécution de `correr.sh`. Compare : que vois-tu avec chaque valeur ? Une fois terminé, supprime-le avec `ctx && kubectl delete -f fig08_09.cron-lento.yaml` : si tu le laisses, il continue de créer un Job par minute, et `kubectl diff -k .` ne le détecte pas parce qu'il ne fait pas partie des fichiers de la leçon.

### Exercice 4 — Deux horaires

En cinq phrases au maximum, écris ta réponse à ceci. (a) L'horaire cron d'une tâche qui s'exécute **les jours de semaine à 7 h 30 du matin, heure de Mexico**, et quel champ de la spécification du CronJob il te faut en plus de l'horaire. (b) L'horaire d'une tâche qui s'exécute **toutes les deux heures pile**. (c) Ce qui arrive à une exécution planifiée à 3 h 00 si le contrôleur de CronJobs a été en panne de 2 h 50 à 3 h 20 et que le CronJob a `startingDeadlineSeconds: 600` ; et ce qui change s'il ne l'a pas. (d) Pourquoi la tâche du rapport peut s'exécuter deux fois dans la même minute sans rien abîmer.

## Solutions

### Solution 1

Mesuré dans `correr.salida.txt` :

```text
$ kubectl apply -f fig08_08.pvc-clase-inexistente.yaml
persistentvolumeclaim/rapido created
pod/lector created

$ kubectl get pvc rapido -n revisor
NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
rapido   Pending                                      rapido         <unset>                 12s

$ kubectl get pod lector -n revisor
NAME     READY   STATUS    RESTARTS   AGE
lector   0/1     Pending   0          12s

$ kubectl describe pvc rapido -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason              Age               From                         Message
  ----     ------              ----              ----                         -------
  Warning  ProvisioningFailed  6s (x2 over 12s)  persistentvolume-controller  storageclass.storage.k8s.io "rapido" not found

$ kubectl describe pod lector -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  13s   default-scheduler  0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
```

**Les deux sont `Pending`, mais pour des raisons de propriétaires différents.** La demande l'est parce que le `persistentvolume-controller` cherche la classe `rapido`, ne la trouve pas, et émet un `Warning` avec la cause exacte : `storageclass.storage.k8s.io "rapido" not found`. À la différence du `Pending` de 8.4, celui-ci est de niveau `Warning` et ne dit pas « en attente » : il dit que quelque chose n'existe pas. Le Pod l'est parce que le planificateur, qui le voit avec une demande non liée, répond `0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims` : aucun nœud ne convient tant que la demande n'est pas liée. (Le message se termine par un `not found` isolé, tel que l'a imprimé le cluster de l'exécution ; le texte des événements change selon les versions, et ce que tu dois lire, c'est la cause dans l'événement de la demande.)

La lecture est la même que toujours : le Pod `Pending` n'est pas le problème, c'est le symptôme. La cause est un objet plus bas, dans la demande, et son événement dit quelle classe manque. La correction est d'écrire une classe qui existe (`kubectl get storageclass` donne la liste) ou de créer celle qui manque. Quant à combien de temps attendre : rien de tout cela ne se résout tout seul. La demande sans classe reste `Pending` « indéfiniment », comme le dit la documentation des volumes persistants pour une demande sans volume correspondant, jusqu'à ce que quelqu'un crée la classe ; il n'y a ni délai d'attente ni erreur finale. Un `Pending` avec `ProvisioningFailed` n'est pas une attente, c'est un avertissement.

### Solution 2

Mesuré dans `correr.salida.txt` :

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
deployment.apps/revisor patched

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-6d9bd59b8b-5wnrq   1/1     Running   0          7s    10.244.2.24   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-sjjkr   1/1     Running   0          10s   10.244.2.23   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-z7sc9   1/1     Running   0          12s   10.244.2.22   curso-k8s-l8-worker   <none>           <none>

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
NOMBRE                                     NODO
pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   curso-k8s-l8-worker

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40_revisor_reportes
total 146508
drwxrwxrwx 2     0     0      4096 Oct 21 23:28 .
drwxr-xr-x 3     0     0      4096 Oct 21 23:26 ..
-rw-r--r-- 1   100   101 150000000 Oct 21 23:27 grande.bin
-rw-r--r-- 1   100   101        92 Oct 21 23:26 reporte-20261021T232640Z.json
-rw------- 1 65532 65532        93 Oct 21 23:28 reporte.json

$ kubectl apply -k . | grep -E 'deployment|persistentvolumeclaim'
persistentvolumeclaim/reportes unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-6b7f4d564d-mgzwr   1/1     Running       0          2s    10.244.1.9    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-nxzdj   1/1     Running       0          7s    10.244.1.8    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-tk4tr   1/1     Running       0          5s    10.244.2.25   curso-k8s-l8-worker    <none>           <none>
revisor-6d9bd59b8b-5wnrq   1/1     Terminating   0          15s   10.244.2.24   curso-k8s-l8-worker    <none>           <none>
```

**Les trois répliques démarrent, et toutes les trois atterrissent sur le même nœud** : `curso-k8s-l8-worker`, celui qui possède le volume. Le planificateur n'a pas pu les répartir parce que le PV a une affinité de nœud (8.5.2) : tout Pod qui utilise la demande doit tourner là où est le disque. Et ce sont bien les trois, parce que ce mode, `ReadWriteOnce`, signifie « un nœud », pas « un Pod » : plusieurs Pods sur le même nœud peuvent monter le volume en même temps. La documentation le dit, et ici on l'a vu. Le `reporte.json` du `revisor` apparaît dans le même dossier que les rapports de la tâche, à côté de `grande.bin` (les 150 Mo de « l'habitude de sécurité », toujours là parce que le volume est le même) et du fichier daté de la tâche 3.

On annule avec `kubectl apply -k .` : les répliques retournent à l'`emptyDir` et se répartissent de nouveau sur les deux nœuds de travail (`worker` et `worker2`). Ce qui serait mauvais pour le projet, en cinq phrases : (1) toutes les répliques restent sur un seul nœud, parce que le volume est sur un seul disque ; (2) si ce nœud tombe, le `revisor` tout entier se retrouve sans endroit où tourner, parce que les Pods ne peuvent pas aller sur un autre nœud avec leur volume ; (3) les trois répliques écriraient le **même** `reporte.json`, en s'écrasant mutuellement, ce qui est pire qu'avant ; (4) la répartition des répliques entre les nœuds dont la Leçon 9 a besoin pour passer à l'échelle et pour mettre à jour en mesurant chaque coupure disparaît ; (5) ce dont le rapport a besoin, c'est d'un historique avec nom et date, et cela, la tâche le fait déjà.

### Solution 3

Mesuré dans `correr.salida.txt`. D'abord `Forbid` (le script attend le début d'une minute de l'horloge avant d'appliquer chaque variante, pour que la première tâche tombe au `:00` suivant) :

```text
$ kubectl apply -f fig08_09.cron-lento.yaml
cronjob.batch/lento created

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:30:45
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        45s             105s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Running    0/1           45s        45s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:31:56
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        56s             2m56s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Complete   1/1           103s       117s
lento-29877091     Running    0/1           14s        14s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age                From                Message
  ----    ------            ----               ----                -------
  Normal  SuccessfulCreate  2m32s              cronjob-controller  Created job lento-29877090
  Normal  SawCompletedJob   49s                cronjob-controller  Saw completed job: lento-29877090, condition: Complete
  Normal  SuccessfulCreate  49s                cronjob-controller  Created job lento-29877091
  Normal  JobAlreadyActive  32s (x4 over 92s)  cronjob-controller  Not starting job because prior execution is running and concurrency policy is Forbid
```

**Avec `Forbid`, un seul Job à la fois, et les minutes intermédiaires ne sont pas créées.** Le premier Job, `lento-29877090`, est né à `23:30:00` et a duré 103 secondes (100 de `sleep` plus le temps de démarrer et de se terminer). Pendant qu'il tournait, l'horaire de `23:31:00` est arrivé et rien n'a été créé : le CronJob a laissé `ACTIVE 1` et a continué avec le même. Quand le Job s'est terminé, vers `23:31:43`, le CronJob l'a vu (`SawCompletedJob`) et en a créé **un autre** aussitôt, `lento-29877091`. Remarque le nom du second : `…091` est celui de `23:31:00`, et non celui de `23:32:00`. La raison est dans la documentation : quand l'exécution précédente se termine, `startingDeadlineSeconds` (qui n'a pas été fixé ici, et n'a donc pas de plafond) compte encore, et l'exécution de `23:31:00` qui avait été sautée est enfin créée. (Dans `correr.salida.txt`, il y a une capture de plus, à 35 secondes après l'application, qui n'a encore aucun Job : le CronJob a été créé à `23:29:00` et son premier horaire a été celui de `23:30:00` ; c'est pourquoi `lento-29877090` correspond à la minute suivante.)

L'événement que laissent les horaires sautés est `JobAlreadyActive`, avec le message `Not starting job because prior execution is running and concurrency policy is Forbid` (« le Job n'est pas démarré parce que l'exécution précédente tourne encore et que la politique de concurrence est Forbid »), et le compteur `x4 over 92s` dit combien de fois cela s'est produit pendant le temps où tu regardais. La documentation ajoute une conséquence : une exécution sautée par `Forbid` compte comme manquée.

Voici maintenant la même tâche avec `Allow`, la valeur par défaut, puis avec `Replace`. Ce sont deux mesures, pas de l'arithmétique :

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Allow

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:35:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     2        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877094     Running    0/1           81s        81s
lento-29877095     Running    0/1           21s        21s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877094-mt8vs   1/1     Running   0          81s
lento-29877095-hqn7d   1/1     Running   0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877094
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877095
```

**Avec `Allow`, deux Jobs tournent en même temps.** Le premier (`lento-29877094`) a commencé à `23:34:00` ; à `23:35:00`, le second (`lento-29877095`) est arrivé sans attendre que le premier se termine, et la capture montre `ACTIVE 2`, deux Jobs `Running` et deux Pods `Running` en même temps, avec 81 et 21 secondes de vie. Les événements sont seulement `SuccessfulCreate`, un par horaire : il n'y a pas de `JobAlreadyActive`, parce que rien n'est sauté. Comme la tâche dure 100 secondes et que l'horaire est de 60, en régime établi il y a toujours entre un et deux Jobs actifs (ce dernier point vient de l'arithmétique ; ce qui est mesuré, c'est le premier chevauchement). Avec une tâche qui écrit dans un volume partagé, ces deux Pods écriraient en même temps : c'est pourquoi la section 8.6 choisit `Forbid` pour le rapport.

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Replace/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Replace

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:37:46
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        46s             106s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877097     Running    0/1           46s        46s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877097-n8cpx   1/1     Running   0          46s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:38:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877098     Running    0/1           21s        21s
NAME                   READY   STATUS        RESTARTS   AGE
lento-29877097-n8cpx   1/1     Terminating   0          81s
lento-29877098-g6cvv   1/1     Running       0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877097
  Normal  SuccessfulDelete  21s   cronjob-controller  Deleted job lento-29877097
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877098
```

**Avec `Replace`, le Job en cours est supprimé et un autre est démarré, et aucun ne finit par se terminer.** Le premier (`lento-29877097`) a commencé à `23:37:00` ; à `23:38:00`, le CronJob l'a **supprimé** (`SuccessfulDelete`) et a créé `lento-29877098` à sa place. Dans la dernière capture, l'ancien Pod est `Terminating` et le nouveau `Running` avec 21 secondes. Le premier Job a vécu 60 secondes, moins que les 100 qu'il lui faut, et ne s'est pas terminé. Cela a été mesuré une fois (le premier remplacement) ; que les suivants répètent la même chose découle du fait que l'horaire reste de 60 secondes et la tâche de 100. `Replace` est la valeur pour les tâches dont le dernier résultat est le seul qui compte et qu'on peut redémarrer sans dommage, et la mauvaise pour une tâche qui a besoin de ses 100 secondes complètes.

Les trois politiques sont une réponse à « que se passe-t-il quand la tâche est plus lente que son horaire », et la bonne réponse est celle qui décrit ce dont ta tâche a besoin, pas la valeur par défaut.

### Solution 4

Une réponse possible : « (a) `30 7 * * 1-5`, soit minute 30, heure 7, n'importe quel jour du mois, n'importe quel mois, du lundi (1) au vendredi (5) ; et en plus `timeZone: "America/Mexico_City"` dans la spécification, parce que sans lui l'horaire est interprété dans le fuseau du contrôleur, UTC dans kind, et la tâche s'exécuterait à 1 h 30 du matin. (b) `0 */2 * * *` : minute 0 de chaque deuxième heure. (c) Avec `startingDeadlineSeconds: 600`, à 3 h 20, le CronJob voit que l'exécution de 3 h 00 a pris 1200 secondes de retard, plus que le délai de 600, et la saute, car il est déjà trop tard pour elle ; avec le champ non fixé, il n'y a pas de délai et il la crée dès que le contrôleur revient, à 3 h 20, avec 20 minutes de retard, sauf si plus de 100 exécutions manquées se sont accumulées, auquel cas il refuse de démarrer. (d) Parce qu'elle est sûre face aux répétitions : le nom du fichier porte la date avec les secondes et chaque exécution écrit un fichier différent, donc deux exécutions laissent deux fichiers et rien n'est corrompu ni perdu (elle n'est pas idempotente au sens strict : le résultat n'est pas le même qu'avec une seule). »

## Supprimer le cluster

Avant de supprimer, l'état final. D'abord on retire le Pod `depurar`, qui ne fait pas partie des fichiers de la leçon (`ctx && kubectl delete pod depurar -n revisor --wait=false`) ; c'est pourquoi, dans la sortie ci-dessous, `Terminating` apparaît dans la liste des Pods. Si la chaîne de la leçon a été suivie dans l'ordre et que les expériences ont été annulées, le cluster doit être exactement ce que disent les fichiers. C'est le `kubectl diff` de la Leçon 5, maintenant dans l'autre sens : sans différences, il sort avec 0.

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Bound    pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   100Mi      RWO            standard       <unset>                 12m

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        3m53s           14m

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-29877090   Complete   1/1           4s         8m53s
reporte-29877095   Complete   1/1           4s         3m53s
reporte-manual-3   Complete   1/1           8s         12m

$ kubectl get pods -n revisor
NAME                       READY   STATUS        RESTARTS   AGE
depurar                    1/1     Terminating   0          14m
prueba-6899c74865-9dckl    1/1     Running       0          15m
reporte-29877090-8ms5h     0/1     Completed     0          8m53s
reporte-29877095-wbx85     0/1     Completed     0          3m53s
reporte-manual-3-2657n     0/1     Completed     0          12m
revisor-6b7f4d564d-mgzwr   1/1     Running       0          10m
revisor-6b7f4d564d-nxzdj   1/1     Running       0          10m
revisor-6b7f4d564d-tk4tr   1/1     Running       0          10m

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

La demande `reportes` est liée, le `CronJob` `reporte` est planifié et s'est déjà exécuté tout seul (les Jobs `reporte-29877090` et `reporte-29877095`, de `23:30` et `23:35`, c'est lui qui les a créés), et le point d'entrée du Gateway répond toujours depuis l'extérieur. C'est l'état avec lequel commence la Leçon 9. (Le seul Pod `Terminating` est `depurar`, supprimé juste avant cette vérification ; les Pods `lento-…` de l'Exercice 3 ne sont plus là parce que le script a attendu qu'ils disparaissent avant de mesurer.)

Quand tu as fini, supprime le cluster de la leçon. Ne laisse rien de vivant sur la machine :

```text
$ kind delete cluster --name curso-k8s-l8
Deleting cluster "curso-k8s-l8" ...
Deleted nodes: ["curso-k8s-l8-worker2" "curso-k8s-l8-control-plane" "curso-k8s-l8-worker"]
(borrar tardó 4 s)

$ kind get clusters | grep -c curso-k8s-l8
0
```

(La ligne entre parenthèses est écrite par le script, qui mesure la suppression.) Le `--name` est obligatoire : sans lui, kind supprimerait le cluster appelé `kind`, qui peut appartenir à quelqu'un d'autre ou à un autre projet. Avec le cluster partent le dossier `/mnt/disco-reportes` du nœud et les volumes qui resteraient : tout vivait à l'intérieur des conteneurs des nœuds.

Il reste sur ta machine le dossier temporaire du `kubeconfig` et les deux `token.txt`. On les supprime ainsi, depuis `programas/08-datos-y-tareas` :

```bash
# Los dos tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 8.1.1.
case "$L8_TMP" in
  /tmp/curso-k8s-l8.?*) rm -rf -- "$L8_TMP" ;;
  *) echo "No borro «$L8_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L8_TMP
unset -f ctx
```

Le `case` ne laisse passer qu'un chemin qui commence par `/tmp/curso-k8s-l8.` et qui a quelque chose après, la forme exacte de celui que tu as créé en 8.1.1. Si `L8_TMP` est vide (par exemple parce que tu es dans un autre terminal, où tu ne l'as jamais définie) ou vaut autre chose, il ne supprime rien et te dit pourquoi. C'est la même protection qu'utilise `correr.sh` en nettoyant : un `rm -rf` qu'on peut copier-coller doit se protéger tout seul. Si ton `correr.sh` a utilisé le réseau dédié des notes d'exécution, ce réseau (`docker network rm curso-k8s-red-l8`) c'est toi qui le supprimes aussi, et seulement celui-là.

## Comment savoir que tu y es arrivé

- [ ] Tu expliques, avec la mesure de 8.2, ce qui survit à la panne d'un conteneur et ce qui ne survit pas à la suppression d'un Pod, et pourquoi.
- [ ] Tu distingues `PersistentVolume`, `PersistentVolumeClaim` et `StorageClass`, et tu dis qui crée chacun.
- [ ] Tu lis `Pending` sur une demande avec `WaitForFirstConsumer` et tu sais que ce n'est pas une erreur, et tu lis `ProvisioningFailed` avec une classe inexistante et tu sais que, là, c'en est une.
- [ ] Tu écris un `Job` avec `backoffLimit` et `activeDeadlineSeconds` et tu dis combien de Pods au maximum il crée et avec quelles attentes.
- [ ] Tu lis un horaire cron à cinq champs et tu écris celui de « toutes les cinq minutes » et celui de « du lundi au vendredi à 7 h 30 ».
- [ ] Tu dis ce que fait `Forbid` face à `Allow` et `Replace`, et pourquoi la tâche du rapport doit pouvoir s'exécuter deux fois.
- [ ] Tu provoques et tu corriges un `Permission denied` sur un volume avec `fsGroup`, et tu dis sur quel volume de la leçon `fsGroup` a changé le groupe et sur lequel non.
- [ ] Tu dis ce qui est perdu en supprimant une demande avec la politique `Delete` et ce qui l'est avec `Retain`, et pourquoi une suppression reste en `Terminating`.
- [ ] Tu exécutes `programas/08-datos-y-tareas/correr.sh > /tmp/mi-corrida-l8.txt 2>&1` et tu compares `/tmp/mi-corrida-l8.txt` à `programas/08-datos-y-tareas/correr.salida.txt` (ne redirige pas vers ce fichier : c'est la référence) sur ce qui ne change pas d'une exécution à l'autre : trois nœuds `Ready` en `v1.37.0` ; six lignes `not yet present on node … loading...` ; `-rw-------` sur les deux `token.txt` ; dans l'`emptyDir`, le répertoire `2777` avec le groupe `65532` et un seul `reporte.json` d'environ 92 octets dans l'une des trois répliques (93 si le temps mesuré a deux chiffres) ; `RESTARTS 1` et `Error 137` après l'arrêt du conteneur, avec le fichier intact ; le dossier du volume qui n'existe plus après la suppression du Pod ; la classe `standard (default)` avec `rancher.io/local-path`, `Delete` et `WaitForFirstConsumer` ; `No resources found` dans `kubectl get pv` ; la demande `Pending` avec l'événement `waiting for first consumer to be created before binding` ; le Job `salud` avec `Complete` et `{"estado":"vivo","version":"1.6.0"}` ; le Pod de la tâche `Pending` avec un nœud désigné et l'événement `Provisioning` (`ProvisioningSucceeded` arrive un instant plus tard et peut ou non figurer dans la capture) ; la demande `Bound`, `100Mi`, `RWO`, `standard` ; le volume attaché à un nœud, avec le chemin `/var/local-path-provisioner/pvc-…_revisor_reportes` et la permission `777 0:0` ; un fichier `reporte-…Z.json` dans la première tâche et deux dans la seconde ; des Jobs de CronJob nommés `<cronjob>-<nombre>` à huit chiffres et l'annotation `cronjob-scheduled-timestamp` à `:00` ; `Permission denied` et `755 0:0` sans `fsGroup`, `Completed` et `2775 0:101` avec lui ; `Released` avec `Retain` ; `Terminating` avec le finalizer `kubernetes.io/pvc-protection` jusqu'à la suppression des Jobs ; `BackoffLimitExceeded` avec trois Pods en `Error`, code `28` ; `150000000` octets écrits dans un volume de `100Mi` ; `ProvisioningFailed … "rapido" not found` ; les trois répliques du `revisor` sur un seul nœud ; `JobAlreadyActive … concurrency policy is Forbid` ; et `sin diferencias con los archivos`. Les IP, les suffixes des noms, les `uid`, les âges, le nœud qui reçoit le volume, les secondes exactes, l'identifiant de chaque `pvc-…` et l'heure des fichiers changent à chaque exécution : on les observe, on ne les compare pas.
- [ ] À la fin, `kind get clusters` n'affiche plus `curso-k8s-l8`.

## Résumé

Réponds sans regarder la leçon :

1. Qu'est-ce qui survit à la panne d'un conteneur et qu'est-ce qui ne survit pas à la suppression d'un Pod, dans un `emptyDir` ?
2. Quel rôle a chacun de ces trois objets : `PersistentVolume`, `PersistentVolumeClaim`, `StorageClass` ?
3. Pourquoi la demande `reportes` reste-t-elle en `Pending` quand on l'applique, et quand cesse-t-elle de l'être ?
4. Que signifie `ReadWriteOnce`, et quelle conséquence a-t-il sur l'endroit où peuvent tourner les Pods qui utilisent le volume ?
5. En quoi un `Job` ressemble-t-il à un Deployment, et en quoi s'en distingue-t-il ?
6. Combien de Pods crée au maximum un Job avec `backoffLimit: 2`, et avec quelles attentes entre eux ?
7. Que disent les cinq champs de `*/5 * * * *` ? Dans quel fuseau horaire s'exécutent-ils si tu ne mets pas `timeZone` ?
8. Que fait `concurrencyPolicy: Forbid` et quel événement laisse-t-il ?
9. Que veut dire qu'une tâche est idempotente, et pourquoi cela compte-t-il dans un CronJob ?
10. Que fait `fsGroup`, sur quel volume de la leçon a-t-il changé quelque chose et sur lequel non ?
11. Pourquoi une demande peut-elle rester en `Terminating` ? Comment le résout-on sans rien forcer ?
12. Quelle différence y a-t-il entre `Delete` et `Retain` ?

## Sources

Toutes consultées le 21 octobre 2026.

- [Kubernetes, « Persistent Volumes »](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) : les définitions de `PersistentVolume` et `PersistentVolumeClaim` ; le provisionnement statique et le dynamique ; la liaison un-à-un et le fait qu'une demande sans volume correspondant attend indéfiniment ; la protection des objets de stockage en cours d'utilisation et sa définition de « en cours d'utilisation » ; les politiques de récupération `Retain` et `Delete` ; les phases `Bound` et `Released` ; les modes d'accès et la définition de `ReadWriteOnce` (un nœud, plusieurs Pods).
- [Kubernetes, « Storage Classes »](https://kubernetes.io/docs/concepts/storage/storage-classes/) : ce qu'est une classe ; la classe par défaut ; la politique de récupération par défaut (`Delete`) ; le mode de liaison `Immediate` face à `WaitForFirstConsumer`.
- [Kubernetes, « Volumes »](https://kubernetes.io/docs/concepts/storage/volumes/) : `emptyDir` (créé à l'affectation du Pod à un nœud, supprimé au retrait du Pod, survit à la panne d'un conteneur, la permission `0777` par défaut) et le volume `local` (statique seulement, `nodeAffinity` obligatoire).
- [Kubernetes, « Jobs »](https://kubernetes.io/docs/concepts/workloads/controllers/job/) : la définition du Job ; `restartPolicy` `Never` ou `OnFailure` ; `backoffLimit` (6 par défaut) et l'attente exponentielle ; `activeDeadlineSeconds` et sa priorité ; les causes d'échec (`BackoffLimitExceeded`, `DeadlineExceeded`) ; les conditions terminales retardées depuis la 1.31 ; le fait que le même programme peut démarrer deux fois.
- [Kubernetes, « CronJob »](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) : le format cron à cinq champs ; le fuseau horaire et `.spec.timeZone` ; `concurrencyPolicy` ; les limites d'historique (3 et 1 par défaut) ; `startingDeadlineSeconds` et le plafond de 100 exécutions manquées ; `suspend` ; le nom de 52 caractères au maximum ; l'annotation `cronjob-scheduled-timestamp` depuis la 1.32 ; l'avertissement que les Jobs doivent être idempotents.
- [Kubernetes, « Configure a Security Context for a Pod or Container »](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) : `fsGroup` et le groupe du volume ; les volumes « qui prennent en charge la gestion des propriétaires » ; `fsGroupChangePolicy`.
- [Kubernetes v1.37, journal des modifications](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.37.md) : la condition `Unused` des demandes de volume (`PersistentVolumeClaimUnusedSinceTime`, bêta et activée depuis la 1.37).
- [Local Path Provisioner (Rancher), README](https://github.com/rancher/local-path-provisioner) : le provisionneur qu'utilise la classe `standard` de kind ; le volume comme dossier `hostPath` du nœud ; la capacité ignorée ; la permission `0777` du dossier ; la suppression du contenu à la suppression du volume.
- [kind, « Configuration »](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts) : les montages supplémentaires (`extraMounts`), la façon de passer du stockage de ta machine à un nœud de kind pour que les données persistent au-delà du conteneur du nœud.
- [Kubernetes, « StatefulSets »](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) : identité réseau stable et stockage stable par Pod (`volumeClaimTemplates`).
- [Kubernetes, « Volume Snapshots »](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) : les instantanés de volume.
- [Kubernetes, « Resource Quotas »](https://kubernetes.io/docs/concepts/policy/resource-quotas/) : `requests.storage`, la somme maximale de stockage que peuvent demander les demandes d'un espace de noms.
- [GitLab, « Postmortem of database outage of January 31 »](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/) : le récit public, de février 2017, d'une perte de données de production et des mécanismes de sauvegarde qui ne fonctionnaient pas (une copie quotidienne qui échouait en silence, des instantanés non activés sur les serveurs de la base, une réplique cassée) : la raison de tester les sauvegardes au lieu de les supposer.

---

**Suivante :** [Leçon 9 — Mettre à l'échelle et mettre à jour en mesurant chaque coupure](09-escalar-y-actualizar.md)
