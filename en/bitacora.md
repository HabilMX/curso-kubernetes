# Logbook

This is yours. It is what makes the course *your* course.

**What to write down:** what you did not understand the first time · the cluster status or error you could not read · what you believed about Kubernetes that turned out to be different · what surprised you · the numbers you measured (times, replicas).

**Why it matters:** in two weeks you will not remember what was hard for you. And what was hard for you is exactly what you need to review.

---

## Lesson 0 — What Kubernetes is and what kind is NOT

_date:_

- In my own words, what a Deployment does:
- The piece of Docker for which I found no direct equivalent in Kubernetes:
- What surprised me:

## Lesson 1 — Installing kubectl and kind; your first cluster

_date:_

- Versions I got (`kubectl version --client`, `kind version`):
- Which context was active before and after creating the cluster:
- Time to create the cluster: ____ s. To delete and recreate it: ____ s

## Lesson 2 — Pods and Deployments

_date:_

- The `ErrImagePull` I triggered and what `describe pod` said:
- What I did so the loaded image would actually be used:
- What the cluster rejected in my `securityContext` and why:

## Lesson 3 — Services and DNS

_date:_

- A Service that had no endpoints and why:
- The three ports in my chain (`port`, `targetPort`, `containerPort`) and which is which:

## Lesson 4 — Configuration and secrets

_date:_

- What I saw when decoding my `Secret`:
- What happened to the Pods when I changed the `ConfigMap` by variable and when I changed it by file:
- With Kustomize, how long the rollout took:

## Lesson 5 — Health checks, resources and graceful shutdown

_date:_

- A probe I broke on purpose and what status I saw:
- An `OOMKilled` or a `Pending`: how I read it in `describe`:
- Seconds it takes for a Pod of my `revisor` to shut down: ____

## Lesson 6 — Getting into the cluster

_date:_

- How I reached the `revisor` from my browser and which path the request took:
- What I still need for that entry point to be truly secure:

## Lesson 7 — Isolating: namespaces, permissions and network

_date:_

- A manifest that the `restricted` level rejected and what it was missing:
- A `kubectl auth can-i` that surprised me:
- What stopped working when closing the network and what I opened to get it back:

## Lesson 8 — Data and tasks

_date:_

- What was lost and what was not when deleting the Pod with and without a volume:
- How many times my `CronJob` ran and how I verified it:

## Lesson 9 — Scaling and updating without downtime

_date:_

- The `<unknown>` in the HPA: why it showed up and how I solved it:
- Replicas when raising the load: ____ → when lowering it: ____ ; time to scale down: ____ min
- What happened when I updated with a broken image and how I went back:

## Lesson 10 — The finished project and what changes in a real cluster

_date:_

- The five things that keep my cluster from being production-ready:
- The one I would worry about first and why:

---

## What I want to build next

_The list of things that occur to you as you go along. It is the best sign that the course worked._

-
