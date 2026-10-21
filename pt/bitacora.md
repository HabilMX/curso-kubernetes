# Diário de bordo

Isto é pessoal. É o que faz do curso o curso *da gente*.

**O que anotar:** o que a gente não entendeu de primeira · o estado ou o erro do cluster que não soube interpretar · o que achava do Kubernetes e acabou sendo diferente · o que surpreendeu · os números medidos (tempos, réplicas).

**Por que importa:** em duas semanas a gente não vai lembrar o que foi difícil. E o que foi difícil é exatamente o que precisa ser revisado.

---

## Lição 0 — O que é Kubernetes e o que NÃO é kind

_data:_

- Com as minhas palavras, o que faz um Deployment:
- A peça do Docker para a qual não encontrei equivalente direto no Kubernetes:
- O que me surpreendeu:

## Lição 1 — Instalar kubectl e kind; o primeiro cluster

_data:_

- Versões que obtive (`kubectl version --client`, `kind version`):
- Que contexto estava ativo antes e depois de criar o cluster:
- Tempo para criar o cluster: ____ s. Para apagá-lo e recriá-lo: ____ s

## Lição 2 — Pods e Deployments

_data:_

- O `ErrImagePull` que provoquei e o que dizia `describe pod`:
- O que fiz para que a imagem carregada fosse usada de verdade:
- O que o cluster rejeitou do meu `securityContext` e por quê:

## Lição 3 — Services e DNS

_data:_

- Um Service que não tinha endpoints e por quê:
- As três portas da minha cadeia (`port`, `targetPort`, `containerPort`) e quem é quem:

## Lição 4 — Configuração e segredos

_data:_

- O que vi ao decodificar o meu `Secret`:
- O que aconteceu com os Pods quando mudei o `ConfigMap` por variável e quando o mudei por arquivo:
- Com o Kustomize, quanto demorou o rollout:

## Lição 5 — Verificação de saúde, recursos e desligamento ordenado

_data:_

- Uma *probe* que quebrei de propósito e que estado vi:
- Um `OOMKilled` ou um `Pending`: como o interpretei em `describe`:
- Segundos que um Pod do meu `revisor` demora para encerrar: ____

## Lição 6 — Entrar no cluster

_data:_

- Como cheguei do meu navegador ao `revisor` e por onde passou a requisição:
- O que me falta para que esse ponto de entrada seja seguro de verdade:

## Lição 7 — Isolar: namespaces, permissões e rede

_data:_

- Um manifesto que o nível `restricted` me rejeitou e o que faltava nele:
- Um `kubectl auth can-i` que me surpreendeu:
- O que deixou de funcionar ao fechar a rede e o que abri para recuperá-lo:

## Lição 8 — Dados e tarefas

_data:_

- O que se perdeu e o que não se perdeu ao apagar o Pod com e sem volume:
- Quantas vezes o meu `CronJob` rodou e como conferi isso:

## Lição 9 — Escalar e atualizar sem interrupções

_data:_

- O `<unknown>` do HPA: por que apareceu e como o resolvi:
- Réplicas ao aumentar a carga: ____ → ao reduzi-la: ____ ; tempo de redução (*scale down*): ____ min
- O que aconteceu quando atualizei com uma imagem quebrada e como voltei atrás:

## Lição 10 — O projeto terminado e o que muda em um cluster real

_data:_

- As cinco coisas pelas quais o meu cluster não é produção:
- A que mais me preocuparia primeiro e por quê:

---

## O que quero construir depois

_A lista de ideias que surgirem enquanto se avança. É o melhor sinal de que o curso funcionou._

-
