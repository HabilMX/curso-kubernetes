# Journal de bord

Ce carnet t'appartient. C'est lui qui fait de ce cours *ton* cours.

**Ce qu'il faut noter :** ce que tu n'as pas compris du premier coup · l'état ou l'erreur du cluster que tu n'as pas su lire · ce que tu croyais savoir de Kubernetes et qui s'est avéré faux · ce qui t'a surpris · les chiffres que tu as mesurés (temps, réplicas).

**Pourquoi c'est important :** dans deux semaines, tu ne te souviendras plus de ce qui t'a donné du mal. Et c'est exactement ce qu'il faut réviser.

---

## Leçon 0 — Ce qu'est Kubernetes et ce que kind n'est PAS

_date :_

- Avec mes mots, ce que fait un Deployment :
- La pièce de Docker à laquelle je n'ai pas trouvé d'équivalent direct dans Kubernetes :
- Ce qui m'a surpris :

## Leçon 1 — Installer kubectl et kind ; ton premier cluster

_date :_

- Versions que j'ai obtenues (`kubectl version --client`, `kind version`) :
- Quel contexte était actif avant et après avoir créé le cluster :
- Temps pour créer le cluster : ____ s. Pour le supprimer et le recréer : ____ s

## Leçon 2 — Pods et Deployments

_date :_

- L'`ErrImagePull` que j'ai provoqué et ce que disait `describe pod` :
- Ce que j'ai fait pour que l'image chargée soit vraiment utilisée :
- Ce que le cluster a rejeté de mon `securityContext` et pourquoi :

## Leçon 3 — Services et DNS

_date :_

- Un Service qui n'avait pas d'endpoints et pourquoi :
- Les trois ports de ma chaîne (`port`, `targetPort`, `containerPort`) et qui est qui :

## Leçon 4 — Configuration et secrets

_date :_

- Ce que j'ai vu en décodant mon `Secret` :
- Ce qui s'est passé avec les Pods quand j'ai changé le `ConfigMap` par variable et quand je l'ai changé par fichier :
- Avec Kustomize, combien de temps a pris le rollout :

## Leçon 5 — Contrôles de santé, ressources et arrêt propre

_date :_

- Une probe que j'ai cassée exprès et quel état j'ai vu :
- Un `OOMKilled` ou un `Pending` : comment je l'ai lu dans `describe` :
- Secondes que met un Pod à s'arrêter de mon `revisor` : ____

## Leçon 6 — Entrer dans le cluster

_date :_

- Comment je suis arrivé depuis mon navigateur jusqu'au `revisor` et par où est passée la requête :
- Ce qu'il me manque pour que ce point d'entrée soit vraiment sûr :

## Leçon 7 — Isoler : espaces, permissions et réseau

_date :_

- Un manifeste que le niveau `restricted` m'a rejeté et ce qu'il lui manquait :
- Un `kubectl auth can-i` qui m'a surpris :
- Ce qui a cessé de fonctionner en fermant le réseau et ce que j'ai ouvert pour le récupérer :

## Leçon 8 — Données et tâches

_date :_

- Ce qui s'est perdu et ce qui ne s'est pas perdu en supprimant le Pod avec et sans volume :
- Combien de fois mon `CronJob` s'est exécuté et comment je l'ai vérifié :

## Leçon 9 — Mettre à l'échelle et mettre à jour sans coupure

_date :_

- Le `<unknown>` du HPA : pourquoi il est apparu et comment je l'ai résolu :
- Réplicas en montant la charge : ____ → en la baissant : ____ ; temps de descente : ____ min
- Ce qui s'est passé quand j'ai mis à jour avec une image cassée et comment je suis revenu en arrière :

## Leçon 10 — Le projet terminé et ce qui change dans un vrai cluster

_date :_

- Les cinq choses pour lesquelles mon cluster n'est pas de la production :
- Celle qui m'inquiéterait le plus en premier et pourquoi :

---

## Ce que je veux construire ensuite

_La liste des choses qui te viennent à l'esprit pendant que tu avances. C'est le meilleur signe que le cours a fonctionné._

-
