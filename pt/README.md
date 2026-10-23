# Curso de Kubernetes com kind — implante, configure, escale e proteja um serviço na própria máquina

**Por Dorian Chávez, fundador da Hábil e arquiteto de integração.**

**Para quem é:** quem já fez o [curso de Docker](https://www.habil.mx/pt/cursos/docker/) da Hábil, ou quem empacota serviços em contêineres com desenvoltura: constrói imagens, coloca-as para rodar, monta volumes nelas e sobe todas juntas com o Compose. Nível intermediário. Não se supõe contato prévio com o Kubernetes nem ter um cluster: o curso entrega um, local, que é criado e destruído em minutos. Cada conceito é explicado quando aparece, e explica-se por que existe, não só como se escreve.

**O que a gente vai saber ao terminar:** implantar um serviço em um cluster de Kubernetes e operá-lo (configurá-lo, vigiá-lo, publicá-lo, limitá-lo, guardar os dados dele, escalá-lo e atualizá-lo medindo cada interrupção); ler o que o cluster diz quando algo falha (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) em vez de apagar e tentar de novo; e explicar, sem rodeios, que distância há entre o cluster local e um de produção.

**De onde vem:** este curso continua o de [**Docker**](https://www.habil.mx/pt/cursos/docker/) da Hábil e usa como ponto de partida a imagem terminada do `revisor`. Quem não fez esse curso precisa de uma imagem de um serviço HTTP que saiba dizer se está vivo e que rode sem ser `root`; a [Lição 2](02-pods-deployments.md) diz exatamente o que ela deve cumprir.

**O que é preciso antes de começar:** um computador com Linux Mint 22.x, Docker Engine funcionando e permissão de administrador (`sudo`). A [Lição 1](01-instalacion-primer-cluster.md) instala o `kubectl` e o `kind` e cria o cluster.

## O projeto que a gente vai construir

O **`revisor`**: o servidor HTTP que consulta uma lista de serviços **ao mesmo tempo** e entrega o relatório, o mesmo dos cursos de [Go](https://www.habil.mx/pt/cursos/go/), [Rust](https://www.habil.mx/pt/cursos/rust/), [TypeScript](https://www.habil.mx/pt/cursos/typescript/) e [Docker](https://www.habil.mx/pt/cursos/docker/) da Hábil; o servidor dele é escrito em Go e atende na porta 8080 (`GET /salud`, `GET /api/estados`, configuração por variáveis de ambiente, subcomando `healthcheck`). Aqui a gente já não o programa nem o empacota: **faz com que ele viva em um cluster**. A gente o implanta com várias réplicas, torna-o encontrável pelo nome, configura-o sem reconstruir a imagem, ensina o cluster a vigiá-lo, publica-o para fora, isola-o com permissões mínimas e uma rede fechada, dá a ele um lugar onde guardar o relatório, converte-o em tarefa agendada e faz com que escale com a carga. No final, tudo sobe com dois `kubectl apply -k` —a plataforma e o projeto— e uma espera entre os dois.

Ele vem acompanhado do **serviço de teste que falha de propósito** do curso de Docker (saudável, lento ou fora do ar), porque um cluster é entendido de verdade quando algo quebra e se vê o que ele faz.

## As onze lições

| Lição | | O que se constrói | O que se aprende |
|---|---|---|---|
| 0 | [O que é Kubernetes e o que NÃO é kind](00-que-es-kubernetes.md) | nada ainda (leitura) | o plano de controle e os nós; declarar o estado desejado e deixar que o cluster o alcance; o mapa do Docker para o Kubernetes; o que o kind prova e o que não |
| 1 | [Instalar kubectl e kind; o primeiro cluster](01-instalacion-primer-cluster.md) | o cluster do curso: um nó de controle e dois de trabalho | `kubectl` e `kind` com versão fixada e soma de verificação; o ajuste do `inotify`; contextos e `kubeconfig`; criar, olhar, apagar e recriar |
| 2 | [Pods e Deployments](02-pods-deployments.md) | o `revisor` rodando, com réplicas que renascem | `kind load docker-image`; o `ErrImagePull` que se provoca de propósito; Pod, ReplicaSet e Deployment; rótulos (*labels*); `rollout`; `securityContext` desde o primeiro manifesto |
| 3 | [Services e DNS](03-services-dns.md) | o `revisor` encontrável pelo nome | `ClusterIP`; seletores e `EndpointSlice`; `port`, `targetPort` e `containerPort`; o DNS do cluster; `port-forward`; um Pod de depuração |
| 4 | [Configuração e segredos](04-configuracion-secretos.md) | o `revisor` configurado sem reconstruir | `ConfigMap` como variáveis de ambiente (o `revisor` só lê variáveis) e `Secret` como arquivo, e por que base64 não é criptografia; Kustomize com geradores e o *hash* que dispara o rollout |
| 5 | [Verificação de saúde (*health check*), recursos e desligamento ordenado](05-salud-recursos-apagado.md) | um `revisor` que o cluster sabe vigiar | *probes* `startup`, `readiness` e `liveness`; por que `/salud` não consulta ninguém; `requests` e `limits`; `OOMKilled` e `Pending` de propósito; o prazo de desligamento |
| 6 | [Entrar no cluster](06-entrar-al-cluster.md) | o `revisor` publicado para fora | `LoadBalancer` com MetalLB e Gateway API com Envoy Gateway, instalados dentro do cluster; por que não Cloud Provider KIND numa máquina compartilhada (ele age sobre todos os clusters kind); `Ingress` como API congelada; por que não `ingress-nginx`; o que se expõe e por onde |
| 7 | [Isolar: namespaces, permissões e rede](07-aislar-permisos-red.md) | um namespace próprio com regras | `Namespace`; Pod Security Admission em nível `restricted`; `ServiceAccount` e RBAC mínimo com `auth can-i`; `NetworkPolicy` de “tudo fechado” e as respectivas aberturas (mede-se que o kindnet, o CNI que o kind traz, as aplica; não é preciso instalar outro) |
| 8 | [Dados e tarefas](08-datos-y-tareas.md) | o relatório salvo e o `revisor` como tarefa agendada | `PersistentVolumeClaim` e a classe de armazenamento do kind; `Job` e `CronJob`; o dono dos arquivos com `fsGroup`; o que se perde ao apagar um Pod |
| 9 | [Escalar e atualizar, medindo cada interrupção](09-escalar-y-actualizar.md) | o `revisor` que sobe e desce réplicas com a carga | `metrics-server`; `HorizontalPodAutoscaler` e a respectiva fórmula; a janela de redução; distribuição com `topologySpreadConstraints`; `RollingUpdate` e `preStop` medidos com um polling; `rollout undo`; `PodDisruptionBudget` e `drain`; a janela de um nó caído |
| 10 | [O projeto terminado e o que muda em um cluster real](10-proyecto-final.md) | tudo com dois `kubectl apply -k` (plataforma e projeto) e uma espera | Kustomize com base e *overlays*; validação com base no nível `restricted`; Helm como menção; o que falta a isto para ser produção |

No final de cada lição há exercícios com as respectivas soluções. E o [diário de bordo](bitacora.md) é para uso próprio: anote ali o que foi mais difícil.

## Três princípios que atravessam todo o curso

**A segurança não é uma lição, é um hábito.** A lição 7 reúne permissões, namespaces e rede porque ali eles são estudados por si mesmos, mas o resto do curso já os pratica desde o primeiro manifesto:

| Lição | O hábito que se instala |
|---|---|
| 0 | saber contra o que um cluster local protege e contra o que não protege |
| 1 | binários com soma de verificação; a imagem do nó fixada; conferir o contexto antes de cada comando que altera algo |
| 2 | `securityContext` no primeiro Deployment: sem `root`, sem escalonamento de privilégios, sem capacidades, sistema de arquivos somente leitura, perfil `seccomp` |
| 3 | por padrão `ClusterIP`; nada é publicado à toa; `port-forward` apenas para `127.0.0.1` |
| 4 | um `Secret` não é criptografia: não é versionado, é montado como arquivo e marcado como imutável |
| 5 | `requests` e `limits` em todo contêiner; as *probes* não dependem de serviços alheios |
| 6 | expõe-se o mínimo, por um ponto de entrada nomeado, e diz-se o que falta (criptografia em trânsito) |
| 7 | namespace próprio, nível `restricted`, permissões mínimas, rede fechada por padrão |
| 8 | o `ServiceAccount` sem credenciais montadas se não precisar delas; os dados com o respectivo dono |
| 9 | limites ao escalonamento; as atualizações mantêm o serviço no ar, com as poucas falhas medidas e explicadas |
| 10 | validação final com base no nível `restricted` e a lista do que um cluster real exige |

**Lê-se antes de apagar.** Quando algo não inicia, o reflexo de quem está começando é apagar e aplicar de novo. Aqui o reflexo é outro: `describe`, `logs`, `get events`. Cada lição provoca de propósito uma falha típica e ensina a ordem para diagnosticá-la, porque essa ordem é o ofício.

**Só se ensina o que está vigente, e o que foi aposentado é nomeado para ser reconhecido.** O `ingress-nginx` deixou de receber manutenção em março de 2026 e os tutoriais de dois anos atrás ainda o ensinam; `Ingress` é uma API congelada e a Gateway API é a sucessora dela. O curso diz qual é qual. E cada versão é informada com a respectiva data: as deste curso foram medidas em 7 de outubro de 2026 (Kubernetes 1.37.1; kind v0.33.0, cujo nó padrão é 1.37.0). O que depende de uma peça externa (MetalLB, Envoy Gateway, a aplicação de `NetworkPolicy`, `metrics-server` no kind) é verificado ao vivo ao escrever cada lição e não é afirmado antes.

## Como a gente sabe que terminou

O curso não termina ao ler a lição 10, mas quando o projeto cumpre estas sete coisas. São metas de projeto: são medidas e ajustadas ao escrever as lições, e cada lição repete a que cabe a ela já medida.

1. **A partir de um cluster recém-criado, o `revisor` fica funcionando em três passos, sempre na mesma ordem:** um `kubectl apply -k` da plataforma (MetalLB e Envoy Gateway, com seus CRDs), um `kubectl wait` até que ela esteja pronta e o `kubectl apply -k` do projeto. Há ordem porque os CRDs e os *webhooks* precisam existir antes dos recursos que os usam. E `kind delete cluster` seguido dos mesmos três passos o reconstrói sem precisar corrigir nada manualmente.
2. **O namespace do `revisor` está no nível `restricted`** do Pod Security Admission e não recebe nenhum aviso ao aplicar.
3. **Ao parar o contêiner de um nó de trabalho** (`docker stop`), o serviço continua respondendo pela réplica do outro nó, **com uma janela medida**: durante dezenas de segundos —o tempo que o cluster leva para dar o nó como perdido (`node-monitor-grace-period`, 50 s por padrão): nas quatro rodadas da lição 10 o serviço voltou a responder de 34 a 51 s depois de parar o nó, e na lição 9 o nó passou a `NotReady` aos 57 s— falham as requisições que caem na réplica morta (medido em uma rodada, com 2 réplicas: 7 de 42 requisições falharam, e a última falha ocorreu 53 s após o desligamento). É possível dizer o que encurta ou suaviza essa janela (mais réplicas distribuídas, novas tentativas no cliente, um prazo de detecção menor no plano de controle) e o que não (as *probes*, que o próprio nó fora do ar executa, nem `tolerationSeconds`, que só decide quando os Pods são repostos). E uma atualização com `preStop` reduz os cortes, mas não garante zero: em quatro rodadas mediu 0, 4, 0 e 1 falhas, 5 de 2.049 requisições no total, contra 29 de 1.569 sem `preStop` em três rodadas (medido de dentro do cluster, pelo Service e pelo `kube-proxy`, não pela porta de entrada; com quatro threads de `curl` em uma máquina compartilhada e sem alternar as rodadas). Ao subir o nó de novo, o cluster se recompõe sozinho.
4. **Ao alterar a lista de serviços no `ConfigMap`**, o cluster faz o rollout por conta própria, sem precisar reconstruir a imagem.
5. **Com carga, `kubectl get hpa --watch` mostra as réplicas subirem e, minutos depois, descerem**, e a gente consegue explicar por que a redução demora o tempo que demora.
6. **Um Pod alheio ao `revisor` não consegue falar com ele** (a `NetworkPolicy` corta a comunicação; meta sujeita a que o cluster a aplique) e a conta de serviço do `revisor` **não pode fazer nada de que não precise** (`kubectl auth can-i` demonstra isso).
7. **A gente sabe dizer, por escrito, cinco razões pelas quais o que foi construído não é produção**, e o que seria feito com cada uma em um cluster real.
