# Lição 9 — Escalar e atualizar, medindo cada interrupção

Segunda-feira, 8h57 da manhã. Às 9h a equipe de operação faz a sua reunião semanal de fechamento e quarenta pessoas vão abrir, quase ao mesmo tempo, o relatório do `revisor`. Na segunda passada aconteceu algo parecido. Às 9h01 o painel ficou lento; alguém subiu as réplicas na mão, de três para oito, para “aguentar”; e esqueceu de baixá-las. Às 9h04 outra pessoa aplicou uma correção urgente, e durante alguns segundos vários usuários viram um erro na tela. Ninguém sabe quantos. Hoje o diretor de operação faz três perguntas, e a reunião começa em três minutos: de quantas réplicas o serviço precisa de verdade e quem decide quando elas passam a sobrar?, quantas requisições se perdem quando se atualiza?, e o que acontece se um dos servidores do cluster cair? A resposta que a gente deu há uma semana às três foi a mesma: “deveria estar tudo bem”.

Essa frase é o problema. No Kubernetes, “deveria estar tudo bem” pode virar um número, e esta lição é a oficina em que isso se faz. Não é uma história inventada para assustar. Em 2019, um engenheiro chamado Phil Pearl contou em seu blog que, ao mover uma API para um cluster Kubernetes do Google atrás de um Ingress, os seus testes recebiam erros `502` de vez em quando. Ao procurar a causa, encontrou algo que quase ninguém dizia naquele momento: quando um Pod é desligado, o aviso de desligamento e a retirada desse Pod da lista de destinos da rede acontecem **ao mesmo tempo**, não um depois do outro; o passo que tira o Pod da lista não espera o passo que o desliga. O que varia é quanto tempo a notícia leva para chegar a cada balanceador: segundo Pearl, num Ingress muito e num Service pouco. Com essa condição de corrida (race condition), uma requisição pode chegar a um Pod que já está se encerrando ([Phil Pearl, “Kubernetes' dirty endpoint secret and Ingress”](https://philpearl.github.io/post/k8s_ingress/), 26 de julho de 2019). O que a gente aprende hoje é como medir essa condição de corrida no próprio cluster, como fechá-la com poucas linhas e como não acreditar numa medição mais do que ela merece.

Esta lição tem três partes. A primeira ensina o cluster a **escalar sozinho**: um medidor de consumo (`metrics-server`), um autoscaler que usa uma fórmula que dá para calcular à mão e uma regra de distribuição para que as réplicas não se amontoem num nó. A segunda ensina a **atualizar e drenar sem sustos**: uma atualização medida com um polling próprio, com e sem a pausa que fecha a condição de corrida, o histórico para voltar atrás e um orçamento de interrupções diante da manutenção de um nó. A terceira **derruba um servidor de propósito** e mede quanto dura a interrupção. Cada cifra que vai aparecer saiu de rodar o procedimento, e cada cifra vem com o que a limita.

**Tempo:** 2 × 45 min de leitura e prática; a execução completa do script leva bem mais (ver “Sobre as execuções”), porque as esperas fazem parte do que se ensina

**O que se constrói:** o `revisor` que sobe e desce réplicas com a carga, distribuído entre os dois nós de trabalho, que é atualizado com um polling que conta cada requisição perdida e que sobrevive a um nó desligado com uma perda medida e explicada

**O que se aprende:** por que o `metrics-server` sem ajustes não funciona no kind e o que muda a flag que o conserta; a fórmula do `HorizontalPodAutoscaler`, a sua tolerância de 10 % e a janela que atrasa a redução; por que um Deployment gerenciado por um autoscaler não leva `replicas`; a distribuição entre nós com `topologySpreadConstraints` e por que o nó de controle exige `nodeTaintsPolicy: Honor`; `RollingUpdate` com `maxSurge` e `maxUnavailable`; a condição de corrida entre o desligamento e os destinos do Service, e o `preStop` que a fecha; `rollout history` e `rollout undo`, e por que `rollout status` pode terminar enquanto os Pods antigos ainda respondem; o `PodDisruptionBudget` e um `drain` que trava de propósito; e a janela de um nó caído, com o que a encurta e o que não a encurta

**De onde a gente vem.** Da [Lição 8](08-datos-y-tareas.md): o `revisor` vive no seu próprio namespace, `revisor`, com a rede fechada da [Lição 7](07-aislar-permisos-red.md), um volume para os seus relatórios e uma tarefa agendada. Da [Lição 5](05-salud-recursos-apagado.md) vem o que hoje vira cálculo: os `requests` de CPU (`50m`), que são a referência com que o autoscaler mede a porcentagem, e o prazo de desligamento, que hoje se ajusta com uma pausa antes do sinal de encerramento. Da [Lição 6](06-entrar-al-cluster.md) vem a plataforma: MetalLB e Envoy Gateway já instalados, com a ordem “plataforma, espera, projeto” que hoje se repete em um único script. E da [Lição 3](03-services-dns.md), o Pod `depurar` e o hábito de olhar `ENDPOINTS` antes de culpar alguém.

**O que esta lição não faz.** Não escala **nós**: no kind os três nós são contêineres fixos, e adicionar ou retirar máquinas é trabalho de outra peça que um cluster real traz e este laboratório não. Não escala na vertical (dar mais CPU a cada réplica) nem com métricas próprias (requisições por segundo, tamanho de uma fila). Não faz atualizações blue-green nem canário: a única estratégia aqui é a gradual que o Kubernetes traz. Não coloca criptografia. E não é um teste de carga sério: a carga da lição é um Job de `curl` em laço, suficiente para ver o autoscaler reagir e nada mais. A [Lição 10](10-proyecto-final.md) junta tudo em dois comandos e lista o que falta a isto para ser produção.

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com `kind` v0.33.0, `kubectl` v1.37.1, a imagem de nó `kindest/node:v1.37.0` fixada pelo seu digest (Kubernetes v1.37.0), **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** e **`metrics-server` v0.9.0**, no cluster de três nós da Lição 1, aqui chamado de `curso-k8s-l9`. A máquina foi um Mac com processador ARM e Docker Engine 29.2.1 dentro de uma máquina virtual Linux (Colima) com 6 CPUs e 16 GiB de memória, **não** o Linux Mint, que é o sistema de referência do curso. E ela era **compartilhada**: enquanto esta lição rodava, rodavam na mesma máquina outras lições do curso com os seus próprios clusters, e a carga do sistema (a média que o `uptime` mostra) passou de menos de 5 para mais de 40 durante o trabalho. Isso importa para ler dois tipos de cifras: os **tempos** (baixar as imagens do MetalLB levou, em tentativas anteriores, vários minutos por nó, e o `preparar.sh` tem esperas longas por causa disso) e as **contagens de requisições** de 9.9 e 9.12, que dependem de quanta CPU o cliente do polling recebeu. Cada seção diz qual cifra depende de quê. O que muda no Mint: a arquitetura (`amd64` em vez de `arm64`), os IPs dos Pods, dos Services e dos nós, os sufixos dos nomes, as idades, o nó em que cai cada réplica e, sobretudo, as cifras de requisições: são de quem acompanha, não se comparam com as daqui. Há ainda uma diferença de rede que convém mencionar. **A execução desta lição usou uma rede de Docker própria**, `curso-k8s-red-l9`, com a sub-rede `172.29.0.0/16`, para poder rodar ao mesmo tempo que outras lições que também instalam o MetalLB sem se sobrepor; por isso os IPs dos nós saem em `172.29.0.x` e o ponto de entrada do Gateway em `172.29.255.200`. Na máquina de quem acompanha, com a rede `kind` normal, os IPs saem em `172.18.0.x` e o ponto de entrada em `172.18.255.200`, que é o que o `preparar.sh` faz por padrão. O `correr.sh` faz o mesmo se for executado com `RED=kind SUBRED=172.18.0.0/16` (são os seus valores padrão) e para antes de criar qualquer coisa se a rede não tiver a sub-rede esperada. O percurso completo está em [`programas/09-escalar-y-actualizar/`](../programas/09-escalar-y-actualizar): o `correr.sh` cria o cluster, carrega nele as três imagens, deixa-o no estado da Lição 8 com o `preparar.sh`, percorre a lição em ordem e o apaga. A saída é `correr.salida.txt`. A execução completa levou 1.809 segundos (30 minutos e 9 segundos): criar o cluster e esperar que ficasse pronto, 37 segundos; o `preparar.sh`, 343; apagar o cluster, 2; o resto são as esperas que a lição ensina a fazer (a carga e a redução do autoscaler, os sete pollings de atualização, o nó desligado). A imagem inexistente de 9.10.4 roda à parte, com o `fig09_02.imagen-rota.sh` (a saída é `fig09_02.imagen-rota.salida.txt`), em um cluster próprio e mínimo que leva uns quatro minutos. Precisa de internet: os manifestos do `metrics-server`, do MetalLB e do Envoy Gateway são baixados das suas releases, fixadas na versão, e as suas imagens são baixadas na primeira vez.

## Ao terminar, a gente vai conseguir

- Explicar por que o `metrics-server` não inicia no kind sem ajustes, interpretar o `x509` dos seus logs, aplicar a flag que o conserta e dizer por que essa flag é só de laboratório.
- Calcular à mão quantas réplicas um `HorizontalPodAutoscaler` pedirá a partir das réplicas atuais, da porcentagem de CPU medida e da meta, aplicando a tolerância de 10 %, e conferir contra a coluna `TARGETS`.
- Escrever um `HorizontalPodAutoscaler` com mínimo, máximo e janela de redução, e explicar por que o Deployment que ele governa já não declara `replicas`.
- Distribuir as réplicas entre os nós com `topologySpreadConstraints` e explicar `maxSkew`, `DoNotSchedule`, `nodeTaintsPolicy: Honor` e `matchLabelKeys`.
- Medir com um polling quantas requisições falham durante uma atualização, com e sem `preStop`, e dizer o que essa medição prova e o que não prova.
- Usar `rollout history` e `rollout undo`, olhar o `deletionTimestamp` antes de concluir que um retorno à versão anterior não funcionou, e interpretar uma atualização com uma imagem que não existe (`ErrImagePull`), conferindo que o serviço não é interrompido.
- Provocar um `drain` bloqueado por um `PodDisruptionBudget` rígido demais, interpretá-lo e corrigi-lo; desligar um nó, medir a janela de falha e explicar o que a encurta e o que não a encurta.

## O porquê antes do como

Até agora, o número de réplicas do `revisor` era decidido pela gente, escrito em um arquivo. É uma boa decisão para aprender e uma má decisão para uma segunda-feira às 9h. Se a carga triplica, ninguém está escrevendo nesse arquivo. E se a carga cai, três réplicas continuam consumindo CPU e memória que outros Pods poderiam usar. A primeira pergunta da lição é, então, **quem decide quantas réplicas são necessárias, com que informação e com que freio?** A resposta tem três peças. Um medidor, o `metrics-server`, que olha quanta CPU e memória cada Pod usa. Um controlador, o `HorizontalPodAutoscaler` (HPA), que compara o medido com uma meta e ajusta o número de réplicas. E uma regra de distribuição, para que as réplicas novas não caiam todas na mesma máquina, porque três réplicas em um só nó caem juntas com esse nó.

A segunda pergunta é **o que acontece com o tráfego enquanto algo muda?** Muitas coisas mudam num cluster vivo: uma versão nova, um nó que vai para manutenção, um nó que cai sem avisar. Cada uma tem uma resposta diferente, e a diferença importa. Uma atualização é *planejada*: o Kubernetes pode ir trocando réplicas uma a uma e esperar que a nova esteja pronta. Uma manutenção é *negociada*: dá para dizer ao cluster quantas réplicas precisam continuar de pé, e o cluster respeita esse número ao remover os Pods. Uma queda *surpreende*: ninguém pediu licença e o cluster demora para perceber. A lição usa os três casos como pretexto para medir. Medir, não adivinhar, porque cada uma das três respostas é um número que muda com a configuração, e esse número é a resposta ao diretor.

E há uma terceira pergunta, mais incômoda: **como se mede a interrupção sem se enganar?** Um polling que manda algumas requisições e não vê nenhuma falha não demonstra que não há falhas; demonstra que *dessa vez, com esse ritmo*, elas não apareceram. A lição diz isso toda vez que mede algo e repete as medições onde custa pouco. É o hábito que separa um relatório de uma anedota.

A lição tem dez partes de conceitos e depois as seções de sempre:

1. **O cluster e o ponto de partida** (9.1): o estado com que a Lição 8 termina, levantado com um script.
2. **Medir antes de escalar** (9.2): `metrics-server`, a flag e o porquê.
3. **O autoscaler e a sua fórmula** (9.3): `HorizontalPodAutoscaler`, tolerância, janela e por que `replicas` sai do Deployment.
4. **Distribuir as réplicas** (9.4): `topologySpreadConstraints`.
5. **Aplicar as mudanças** (9.5): o que o `kubectl diff` mostra e a bagunça de réplicas que se esconde ali.
6. **Com carga, o autoscaler sobe** (9.6).
7. **Sem carga, desce, depois da janela** (9.7).
8. **Quem manda nas réplicas** (9.8).
9. **Atualizar e medir a interrupção** (9.9), com o polling, o `preStop` e o retorno à versão anterior (9.10).
10. **Manutenção e queda de um nó** (9.11 e 9.12): `PodDisruptionBudget`, `drain` e um nó desligado.

Este é o destino. No fim de 9.6, com carga, o autoscaler já mudou o número de réplicas e o mostra em uma única linha:

```text
$ kubectl get hpa revisor -n revisor --no-headers
revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

É uma linha da execução (a última da espera de 9.6): o HPA `revisor`, que governa o Deployment `revisor`, mede `38 %` contra uma meta de `50 %`, tem um mínimo de 2 réplicas, um máximo de 6 e hoje está com 4.

## Se a imagem do curso de Docker não estiver disponível

Esta lição usa três imagens locais: `curso-docker-revisor:1.6.0`, a do `revisor` da Lição 2; `curso-docker-prueba:1.0.0`, a do serviço que falha de propósito; e uma nova, `curso-docker-revisor:1.6.1`, que serve para que a atualização da lição tenha o que atualizar. As duas do `revisor` saem do mesmo `Dockerfile` e do mesmo código: a única coisa que muda é a versão que o serviço informa em `/salud` (`"version":"1.6.0"` ou `"version":"1.6.1"`), e é justamente isso que permite ver, requisição por requisição, qual réplica respondeu. Confira se as três estão aí:

```text
$ docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E '^curso-docker-(revisor|prueba):'
curso-docker-revisor:1.6.1 61c70431badb
curso-docker-prueba:1.0.0 400d3fd59edc
curso-docker-revisor:1.6.0 bd1b2e7d91b8
```

(Esta saída é da máquina do autor e não está em `correr.salida.txt`. Os identificadores vêm dela; na máquina de quem acompanha podem ser outros, se as imagens foram construídas por conta própria. O que importa é que existam as três tags.) Se faltar a `1.6.1`, construa-a como a `1.6.0`, a partir do repositório do curso de Docker, com o `Dockerfile` da sua Lição 10 sobre a pasta `programas/revisor` e com `--build-arg VERSION=1.6.1`, atribuindo exatamente a tag `curso-docker-revisor:1.6.1`. É uma imagem de laboratório: serve para ver uma atualização, não é uma versão nova do serviço.

## Os conceitos

### 9.1 O cluster e o ponto de partida

#### 9.1.1 Uma regra de convivência, outra vez

Esta lição instala o MetalLB (por meio do `preparar.sh`, 9.1.3), e a regra da Lição 6 continua valendo: dois clusters com MetalLB e a mesma faixa de endereços, na mesma rede de Docker, se sobrescrevem. Antes de criar o cluster, confira a rede `kind` e se ninguém já responde no primeiro endereço da faixa:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar en 172.18.255.200. Si este curl responde, hay otro
# clúster con MetalLB vivo: espera a que termine.
# Si imprime un número (200, 404…), alguien contesta; si imprime 000, nadie.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -o /dev/null -w '%{http_code}\n' -m 3 http://172.18.255.200/
kind get clusters
```

Se a rede `kind` ainda não existir porque nunca se criou um cluster, crie o cluster e confira a rede logo depois. Há ainda um detalhe de laboratório que convém dizer desde já, porque muda os endereços que vão aparecer nas saídas: a execução desta lição usou **uma rede de Docker própria**, `curso-k8s-red-l9`, com a sub-rede `172.29.0.0/16`, para poder rodar ao mesmo tempo que outras lições que também instalam o MetalLB. Na máquina de quem acompanha, com a rede `kind` normal, os endereços da faixa saem em `172.18.255.x`, não em `172.29.255.x`; o script `correr.sh` se adapta com duas variáveis, `RED` e `SUBRED`, e traz o freio de sempre: se a rede não tiver a sub-rede esperada, ele para antes de criar qualquer coisa.

#### 9.1.2 Criar o cluster e carregar as imagens

Desde a raiz do repositório do curso:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l9.XXXX)/kubeconfig"
# curso-k8s-l9 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l9 --config programas/09-escalar-y-actualizar/kind-curso.yaml
# Debe decir kind-curso-k8s-l9. Si dice otra cosa, no sigas.
kubectl config current-context
# La guarda de siempre, con el nombre de este clúster. Va delante de cada
# comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-revisor:1.6.1 curso-docker-prueba:1.0.0 --name curso-k8s-l9
cd programas/09-escalar-y-actualizar
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

A função `ctx` compara o contexto ativo com o esperado; se coincidir, não imprime nada, e se não coincidir, escreve “contexto equivocado: no sigo” e devolve um erro que corta a cadeia `&&`. Nesta lição ela vai antes de cada comando que **muda** algo (`apply`, `patch`, `scale`, `drain`, `delete`); nas saídas que seguem ela é omitida para que caibam, mas no terminal de quem acompanha ela vai. Os comandos que só **leem** (`get`, `top`, `describe`) não precisam dela, embora não atrapalhe. O `correr.sh` faz a conferência antes de cada comando de outra forma, com uma função que para sozinha.

O `(umask 077; …)` faz o `token.txt` nascer `-rw-------`: a máscara `077` tira todas as permissões do grupo e dos demais, e os parênteses fazem a mudança valer só para esse comando. É o cuidado das Lições 4 a 6, e se repete porque um hábito que se omite uma vez já não é um hábito.

```text
$ kind create cluster --name curso-k8s-l9 --config kind-curso.yaml
(crear el clúster y esperar a que estuviera listo tardó 37 s)

$ kubectl config current-context
kind-curso-k8s-l9

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l9-control-plane  Ready   v1.37.0  172.29.0.2
curso-k8s-l9-worker         Ready   v1.37.0  172.29.0.4
curso-k8s-l9-worker2        Ready   v1.37.0  172.29.0.3
```

Criar o cluster e esperar que os seus nós e os Pods de `kube-system` estivessem prontos levou 37 segundos, com a imagem do nó já baixada antes. São três nós `Ready` em `v1.37.0`: um nó de controle e dois de trabalho. A coluna `INTERNAL-IP` é o endereço de cada nó na rede de Docker; aqui cai em `172.29.0.x` por causa da rede própria da execução, e na máquina de quem acompanha cairá em `172.18.0.x`. Carregar as três imagens com `kind load` imprime as suas linhas de sempre (`not yet present on node … loading...`); o `correr.sh` as silencia e, em seu lugar, anota que ficaram carregadas.

#### 9.1.3 O ponto de partida: `preparar.sh`

A Lição 8 termina com um cluster que já traz a plataforma da Lição 6 e o projeto da Lição 8. Para não repetir uns minutos de instalação manual, o `preparar.sh` os refaz com os **três passos da Lição 6, à vista e na mesma ordem**: a plataforma (MetalLB e Envoy Gateway), a espera com `kubectl wait` até que estejam prontos, e por último a faixa de endereços, a classe de gateway e o projeto da pasta `punto-de-partida/`. Se a gente vem da Lição 8 com o cluster vivo, não precisa dele; se começa aqui, ou se já o apagou, ele é executado:

```bash
ctx && ./preparar.sh
```

É um **programa**: o `preparar.sh`. Leia-o antes de rodá-lo: ele não esconde nada. Cada passo confere o contexto, imprime o comando que vai rodar e para se falhar. Aceita uma variável, `POOL_RANGO`, para mudar a faixa do MetalLB se a rede não for a `172.18.0.0/16`. Uma observação sobre a largura: o `infra/metallb-pool.yaml` e o `preparar.sh` trazem `.200-.220`, enquanto o `correr.sh` calcula `.200-.250`, que é o que se vê abaixo. Aqui não importa, porque só se usa o primeiro endereço da faixa, o do Gateway.

```text
$ POOL_RANGO=172.29.255.200-172.29.255.250 ./preparar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb >/dev/null

$ kubectl apply --server-side -k infra/envoy-gateway >/dev/null

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=1200s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=1200s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=1200s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f /tmp/curso-k8s-l9.wJDg/metallb-pool.Xbdv -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k punto-de-partida >/dev/null

$ kubectl rollout status deployment/revisor deployment/prueba -n revisor --timeout=600s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=1200s
gateway.gateway.networking.k8s.io/revisor condition met
(preparar.sh tardó 343 s)
```

Lê-se em três tempos, os mesmos da Lição 6. No **passo 1** são aplicadas a plataforma do MetalLB e a do Envoy Gateway; as suas saídas vão para `/dev/null` porque são dezenas de linhas sem interesse. No **passo 2** vêm as esperas, todas com `kubectl wait` ou `rollout status` e todas com prazo: os tipos novos do MetalLB (`condition met`), o controlador, um `speaker` pronto em cada um dos três nós, os tipos da Gateway API, o controlador do Envoy Gateway. No **passo 3** são aplicados a faixa de endereços (um arquivo temporário que o `preparar.sh` gerou a partir de `infra/metallb-pool.yaml` com a faixa da rede própria: é o efeito de `POOL_RANGO`), a classe de gateway `eg` e, por fim, o projeto de `punto-de-partida/`, com o seu `rollout status` e a espera de que o Gateway esteja `Programmed`. Tudo levou 343 segundos; a maior parte, esperando o download das imagens. Este é o ponto de partida da lição:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           22s
deployment.apps/revisor   3/3     3            3           22s

$ kubectl get gateway -n revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.29.255.200   True         22s

$ docker run --rm --network curso-k8s-red-l9 --name curso-k8s-l9-cliente curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 5 http://172.29.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

Três réplicas do `revisor`, a do serviço de teste, nenhum HPA nem PDB ainda (o último `get` não os lista porque não existem) e um Gateway `PROGRAMMED True` no primeiro endereço da faixa. O último comando é o cliente “de fora” da Lição 6, um contêiner de `curl` conectado à rede de Docker, pedindo `/salud` pelo ponto de entrada: `{"estado":"vivo","version":"1.6.0"}`. Se isso responder, a plataforma e o projeto estão de pé.

### 9.2 Medir antes de escalar: `metrics-server`

#### 9.2.1 O que o cluster ainda não sabe

Antes de decidir quantas réplicas são necessárias, é preciso saber quanta CPU as que existem usam. O cluster não sabe isso de fábrica. Se a gente perguntar com `kubectl top`, o comando que mostra o consumo:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]
```

`error: Metrics API not available`: “a API de métricas não está disponível”. A frase tem um sujeito exato. O Kubernetes define uma API para o consumo de CPU e memória de nós e Pods, a **Metrics API**, e a documentação a descreve assim: oferece “um conjunto básico de métricas para dar suporte ao escalonamento automático e a casos semelhantes” ([Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)). Mas essa API é só uma *forma* de perguntar: alguém precisa responder. A mesma página diz isso sem enfeites: é preciso implantar o `metrics-server` “ou um adaptador alternativo” para poder usá-la, e o seu papel principal é “alimentar com métricas de uso de recursos os componentes de autoscaling”. Um cluster recém-criado não o traz, e por isso o `top` não tem a quem perguntar.

Como se pluga um respondedor na API do Kubernetes? Com um objeto que a gente já conhece da Lição 6, por parentesco: um recurso que ensina algo novo ao `kube-apiserver`. Aqui não é um CRD, mas um `APIService`, que diz ao `kube-apiserver`: “as perguntas que chegarem a `/apis/metrics.k8s.io/v1beta1` não as responda diretamente; encaminhe-as a este Service”. Antes de instalar qualquer coisa, esse objeto não existe:

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
Error from server (NotFound): apiservices.apiregistration.k8s.io "v1beta1.metrics.k8s.io" not found
[código de salida: 1]
```

Com `NotFound`: o `kube-apiserver` não tem para quem encaminhar. É a mesma situação da Lição 6 com `Gateway`, vista de outro lado: antes de a peça existir, perguntar por ela é perguntar ao vazio.

#### 9.2.2 Instalar o `metrics-server` do jeito que vem

O projeto publica um manifesto por versão. A que esta lição usa é a **v0.9.0**, e ela é fixada na URL, como tudo o mais foi fixado no curso: sem versão fixa, no dia em que a última versão mudar, o laboratório muda sem avisar. Ele é aplicado do jeito que vem, sem alterar nada, para ver o que acontece:

```text
$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml | tail -3
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
(espera visible: hasta 600 s a que metrics-server descargue su imagen, arranque e intente leer a los kubelet)
```

As três linhas que se veem são as últimas de várias (`| tail -3`): um `Service`, um `Deployment` e o `APIService` que conecta os dois ao `kube-apiserver`. Sobre o momento de olhar: o Deployment não fica pronto na hora. Primeiro precisa baixar a sua imagem e iniciar, e depois tentar a sua primeira leitura. O script espera, à vista, até que os logs do Pod mostrem o erro que se quer interpretar (até 600 segundos, porque numa máquina lenta o download demora). No terminal de quem acompanha, dá para repetir `kubectl get deployment metrics-server -n kube-system` até ver `0/1` com alguns segundos de idade. É uma espera de outro tipo que a do `kubectl wait`: aqui não se espera que uma condição *chegue*, espera-se para *dar tempo de falhar* e poder ler como.

```text
$ kubectl get deployment metrics-server -n kube-system
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   0/1     1            0           30s
```

`READY 0/1` e `AVAILABLE 0`: o Pod existe, mas não está pronto. Segue-se a ordem da Lição 5, que diz o que olhar primeiro quando algo não inicia: os logs do Pod.

```text
$ kubectl logs -n kube-system deployment/metrics-server --tail=200 | grep -E 'x509|tls|certificate' | tail -1
E1021 23:14:05.707527       1 scraper.go:149] "Failed to scrape node" err="Get \"https://172.29.0.2:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs" node="curso-k8s-l9-control-plane"
```

Lê-se da esquerda para a direita. `E1021` é uma linha de nível *error* de 21 de outubro. `scraper.go:149` é o lugar do código que falhou, e `Failed to scrape node` diz o que ele tentava fazer: “raspar” (coletar) as métricas do nó, que é o que o `metrics-server` faz a cada poucos segundos, perguntando a cada `kubelet` pela CPU e pela memória que os seus Pods usam. O endereço é `https://172.29.0.2:10250/metrics/resource`: o `kubelet` desse nó (o de controle; na máquina de quem acompanha será `172.18.0.x`), pelo seu IP, na porta 10250. E a causa, no final: `tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs`.

É preciso desmontar essa frase. TLS é a criptografia com a qual o `metrics-server` fala com o `kubelet` (HTTPS). Para que a criptografia valha, o `metrics-server` verifica o **certificado** que o `kubelet` lhe apresenta: confere se foi assinado por uma autoridade em que ele confia e se o certificado diz ser do endereço ao qual ele se conectou. Um certificado leva uma lista de nomes e endereços válidos, os *Subject Alternative Names* (SAN). Aqui o certificado do `kubelet` não traz nenhum **IP** nessa lista, e o `metrics-server` se conectou por IP: por isso não consegue validar que “`172.29.0.2`” seja quem diz ser. O que os logs demonstram é só isto: o certificado não traz nenhum IP. O README do `metrics-server` coloca como requisito que o certificado do `kubelet` esteja assinado pela autoridade do cluster ([metrics-server](https://github.com/kubernetes-sigs/metrics-server)), e no kind os nós não o cumprem tal como vêm. Num cluster real, isso se resolve nos nós; neste laboratório não se tenta.

Com o Pod fora de pronto, o `Service` do `metrics-server` não tem destinos, e o `APIService` reflete isso:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]

$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE                  AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   False (MissingEndpoints)   30s
```

`AVAILABLE False (MissingEndpoints)`: “faltam destinos”. O Service não tem para quem mandar as perguntas porque o único Pod não está pronto. Agora o erro do `kubectl top` tem a sua cadeia completa: o comando pergunta ao `kube-apiserver`; este encaminha ao Service; o Service não tem destinos; o único destino não está pronto; e não está pronto porque não consegue verificar o certificado do `kubelet`. Cinco elos, e a mensagem de cima só mostrava o último. É o mesmo ofício da Lição 3: desce-se andar por andar até encontrar o que falha.

#### 9.2.3 A flag, e por que ela é só de laboratório

O `metrics-server` tem uma opção para não verificar o certificado dos `kubelet`: `--kubelet-insecure-tls`. O seu README a descreve em duas frases curtas que convém ler devagar: “Do not verify the CA of serving certificates presented by Kubelets. For testing purposes only” (“Não verifica a autoridade dos certificados apresentados pelos kubelet. Somente para testes”). Não é um modo de falar para ficar bem: é um aviso, e a lição o respeita. Essa flag vale num laboratório em que os nós são contêineres da própria pessoa, na máquina dela, e não vale num cluster em que alguém mais poderia se colocar na rede entre o `metrics-server` e um nó, porque sem verificar o certificado não há como saber com quem se está falando.

O manifesto da v0.9.0 não traz a flag; ela é acrescentada com um *patch* do Kustomize. É um **programa**: `metrics-server/kustomization.yaml`.

```yaml
# metrics-server — Lección 9. Versión fijada (v0.9.0). En kind, el certificado de
# cada kubelet no trae ninguna IP y metrics-server no lo acepta sin
# --kubelet-insecure-tls. Eso SOLO vale en un clúster de laboratorio.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
patches:
- target:
    kind: Deployment
    name: metrics-server
    namespace: kube-system
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --kubelet-insecure-tls
```

O patch diz: no Deployment `metrics-server` do namespace `kube-system`, acrescente ao final da lista de argumentos do primeiro contêiner, `--kubelet-insecure-tls`. O `op: add` com `args/-` é a forma de “acrescentar ao final” de uma lista num patch do tipo JSON. É aplicado com `-k`, como todo o resto:

```text
$ kubectl apply -k metrics-server | tail -3
service/metrics-server unchanged
deployment.apps/metrics-server configured
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io unchanged
```

Dois objetos `unchanged` (o Service e o APIService não mudam) e um `configured`: o Deployment. Mudou o seu template, então haverá uma substituição do Pod, e desta vez a espera é mesmo de condição:

```text
$ kubectl rollout status deployment/metrics-server -n kube-system --timeout=600s
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
deployment "metrics-server" successfully rolled out
(espera de 45 s: metrics-server mide en ventanas y necesita un par de ellas)
```

Depois vem uma pausa que não é de condição, e convém dizê-lo: o `metrics-server` mede por janelas de tempo e precisa de um par delas antes de poder responder com dados, então a lição espera 45 segundos de relógio. Em vez de adivinhar, há uma forma de conferir que ele já responde: perguntar pelo `APIService`, que deve passar a `True`.

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        98s
```

`AVAILABLE True`. Agora o `top` tem a quem perguntar:

```text
$ kubectl top nodes
NAME                         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
curso-k8s-l9-control-plane   139m         2%       974Mi           6%          
curso-k8s-l9-worker          92m          1%       272Mi           1%          
curso-k8s-l9-worker2         53m          0%       316Mi           1%          

$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-cgzkw    1m           1Mi             
revisor-67b97d67c9-fnpdj   1m           1Mi             
revisor-67b97d67c9-jfdw4   1m           1Mi             
revisor-67b97d67c9-tqffn   1m           1Mi             
```

A coluna `CPU(cores)` está em **milicores**: `1m` é um milésimo de um núcleo, a mesma unidade dos `requests` da Lição 5. A documentação explica de onde vem: a CPU é informada “como o uso médio de núcleos”, calculado “como uma taxa sobre um contador acumulado de CPU fornecido pelo kernel” do Linux, numa janela de tempo que a própria API informa (campo `window`). Não é uma foto de um instante, é uma média de uma janela curta. E `CPU(%)` no `top nodes` é a porcentagem da CPU **do nó**, não do `request` de ninguém; essa é outra conta, e a que importa ao autoscaler é a que vem a seguir. Olhe os Pods do `revisor`: algumas décimas de milicore ou uns poucos milicores de uso, contra os `50m` que pediram:

```text
$ kubectl describe pod -n revisor -l app=revisor | grep -E 'Requests|cpu:' | head -4
      cpu:     200m
    Requests:
      cpu:      50m
      cpu:     200m
```

(O primeiro `cpu: 200m` é o `limit`; o `Requests` e o seu `cpu: 50m`, o mínimo. O terceiro é o `limit` do outro contêiner listado; o filtro `head -4` corta a saída onde cabe.) Um Pod que usa `4m` de `50m` está em 8 % do que pediu. Essa porcentagem, a de **uso contra `requests`**, é a referência do autoscaler.

A documentação do `metrics-server` também diz para que ele **não** serve, e vale ouvir antes de confiar: os seus casos de uso são o escalonamento horizontal por CPU e memória, e o seu README adverte que ele não é “uma fonte exata do uso de recursos”. Para olhar o consumo com precisão, para plotá-lo em gráficos ou para alertar, existem outras ferramentas. Para decidir quantas réplicas, basta.

### 9.3 O autoscaler e a sua fórmula

#### 9.3.1 O que é e a cada quanto tempo ele olha

O `HorizontalPodAutoscaler` é um controlador, mais um dos que a gente viu na Lição 0 fazendo o mesmo de sempre: comparar o estado desejado com o real e empurrar o segundo em direção ao primeiro. A diferença é o que ele entende por “estado desejado”: não um número de réplicas, mas uma **meta de consumo**. “Horizontal” quer dizer que muda o *número* de réplicas, não o tamanho de cada uma. A documentação diz que o laço roda a cada 15 segundos por padrão (`--horizontal-pod-autoscaler-sync-period`) ([Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)).

A cada volta ele faz três coisas: lê as métricas dos Pods do alvo, calcula quantas réplicas pediria e, se o resultado muda o número atual, pede-o ao Deployment. A parte que dá para calcular à mão é a segunda, e é esta:

```text
réplicas deseadas = ceil( réplicas actuales × (métrica actual ÷ métrica deseada) )
```

É a fórmula que a documentação dá: `desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]`. `ceil` é “arredondar para cima”. Com uma meta de CPU de 50 %: se há 2 réplicas e a média de uso é de 100 % do que pediram, a conta é `ceil(2 × 100 ÷ 50) = ceil(4) = 4`. Se a média de uso é de 25 %, `ceil(2 × 25 ÷ 50) = ceil(1) = 1`. O arredondamento para cima tem uma razão: é preferível um Pod a mais do que um a menos quando a meta está a ponto de ser ultrapassada.

E a “porcentagem”? Com uma meta do tipo `Utilization`, o controlador calcula o uso “como uma porcentagem da solicitação (`request`) equivalente dos contêineres de cada Pod” e tira a média de todos os Pods alvo. Por isso um Pod sem `requests` de CPU é um Pod que o autoscaler não consegue medir: a documentação diz que, se algum contêiner não tem a solicitação, “a utilização de CPU do Pod não fica definida e o autoscaler não fará nada com essa métrica”. A Lição 5 colocou `requests` em todo contêiner “para que o scheduler saiba onde colocá-lo”; hoje essa decisão serve para uma segunda coisa que então não se via.

#### 9.3.2 A tolerância de 10 %

Se o cálculo fosse aplicado do jeito que está, o autoscaler mudaria o número de réplicas por diferenças de um ponto percentual, e o cluster estaria em ajuste perpétuo. Para evitá-lo, o controlador pula qualquer ajuste quando a razão `métrica atual ÷ métrica desejada` está “suficientemente perto de 1,0”, e a documentação dá a medida: uma tolerância de 0,1 por padrão, isto é, de 10 % (desde o Kubernetes 1.37, cada HPA pode fixar a sua própria tolerância em `behavior.scaleUp.tolerance` e `behavior.scaleDown.tolerance`; esta lição deixa a do cluster, os 10 %). Com uma meta de 50 %, só há ajuste se o uso medido cair fora de 45 % a 55 %: a razão tem de ser menor que 0,9 ou maior que 1,1.

Um exemplo com números, para calcular à mão antes de ver o cluster. Com 3 réplicas e uma meta de 50 %:

| Uso medido | Razão | Fora de 0,9 a 1,1? | `ceil(3 × razão)` | O que faz |
|---|---|---|---|---|
| 54 % | 1,08 | não | — | nada |
| 57 % | 1,14 | sim | `ceil(3,42)` = 4 | sobe para 4 |
| 40 % | 0,80 | sim | `ceil(2,4)` = 3 | não muda (3), mas a recomendação é anotada |
| 20 % | 0,40 | sim | `ceil(1,2)` = 2 | desce para 2 (se a janela permitir) |

Quando o cluster der números, a gente os conferirá contra esta tabela.

#### 9.3.3 O manifesto

É um **programa**: `escalado.yaml`. Traz dois objetos, o autoscaler e um orçamento de interrupções que é explicado em 9.11.

```yaml
# escalado.yaml — Lección 9: réplicas según la carga, con límites, y al menos
# una disponible durante un mantenimiento.
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: revisor
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: revisor
  minReplicas: 2
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: revisor
```

Lê-se campo por campo:

- **`scaleTargetRef`**: quem ele governa. Um `Deployment` chamado `revisor` do mesmo namespace. O HPA não toca nos Pods: pede ao Deployment que mude o seu número de réplicas, e o Deployment faz o resto, como sempre.
- **`minReplicas: 2` e `maxReplicas: 6`**: o mínimo e o máximo. O mínimo é 2 por duas razões: com uma única réplica, qualquer substituição é uma interrupção, e com duas (uma em cada nó de trabalho) a atualização de 9.9 e a manutenção de 9.11 podem ser feitas sem perder o serviço. O máximo é 6 pelo hábito de segurança que fecha esta lição: um autoscaler sem teto transforma uma avalanche de requisições, ou um erro num laço, numa fatura ou num nó esgotado.
- **`metrics`**: o que mede e contra o quê. Um recurso, a CPU, com uma meta de utilização média de 50 % *dos `requests`*. É uma meta intermediária de propósito: se fosse de 90 %, o autoscaler reagiria quando o serviço já está quase saturado.
- **`behavior.scaleDown.stabilizationWindowSeconds: 60`**: a janela de redução, que é explicada a seguir.

O campo `behavior` merece um parágrafo próprio. Sem ele, o HPA usa os valores padrão da documentação: para **subir**, uma janela de estabilização de 0 segundo e uma política que permite somar até 4 Pods ou dobrar as réplicas a cada 15 segundos, a que for maior; para **descer**, uma janela de **300 segundos** (cinco minutos) e uma política que permite retirar de uma vez todas as réplicas excedentes. A lição usa 60 segundos em vez de 300 para que dê para ver a redução sem esperar cinco minutos, e diz isso porque não é um valor para copiar: em produção, a janela longa protege contra o vaivém (“subo, desço, subo, desço”) quando a carga é irregular.

O que a janela faz, exatamente? A documentação explica com precisão: logo antes de escalar, o controlador anota a recomendação do momento e depois “considera todas as recomendações dentro da janela configurada e escolhe a mais alta”. Ou seja: para **descer**, o HPA não usa o que vê agora, mas o **máximo** do que recomendou nos últimos 60 segundos. Se há 40 segundos recomendava 4 réplicas e agora recomenda 2, continua em 4 até que essa recomendação de 4 saia da janela. É uma memória deliberada do pior recente, e é a razão pela qual a redução é lenta e o aumento não.

Por último, o `kubectl diff` de 9.5 vai mostrar que o HPA, ao ser aplicado, traz escritos na saída os valores padrão de `scaleUp` e `scaleDown` (`selectPolicy: Max`, as políticas de 15 segundos): o servidor completa o que não foi escrito.

#### 9.3.4 Por que o Deployment já não leva `replicas`

Na pasta da Lição 8, o Deployment do `revisor` dizia `replicas: 3`. Na de hoje, esse campo não está. Não é um descuido: é a recomendação explícita da documentação do HPA. Quando há um autoscaler, o campo `spec.replicas` do Deployment deveria ser retirado do manifesto, porque senão, “toda vez que se aplica uma mudança a esse objeto, por exemplo com `kubectl apply -f deployment.yaml`, o Kubernetes escalará o número atual de Pods para o valor de `spec.replicas`”, o que “pode ser problemático quando um HPA está ativo, e causar *vaivém*”. Dois donos de um mesmo número brigam: o arquivo diz 3, o HPA acaba de pedir 5, e cada `apply` desfaz o que o outro fez.

A documentação acrescenta um aviso que 9.5 vai tornar visível: retirar o campo “pode causar uma degradação única do número de Pods, porque o valor padrão dessa chave é 1”. Ou seja, ao aplicar pela primeira vez o Deployment **sem** `replicas`, o cluster o lê como “volte ao valor padrão” e propõe descer para uma única réplica. Em 9.5 aparecerá esse `replicas: 1` no `kubectl diff`, e se verá o que acontece depois.

### 9.4 Distribuir as réplicas

#### 9.4.1 O problema: nada distribui por conta própria

Um autoscaler que sobe para quatro réplicas não diz onde as coloca; isso é decidido pelo scheduler, que procura o nó que melhor encaixa por recursos e outras regras, e por padrão não se esforça para distribuir. Veja como ficaram as três réplicas da pasta da Lição 8, sem nenhuma regra de distribuição:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>
```

A coluna `NODE` diz onde está cada uma. Nesta execução, duas das três réplicas caíram juntas em `curso-k8s-l9-worker2` e uma em `curso-k8s-l9-worker`. Não é azar: nesta execução e em três anteriores que não foram conservadas, duas das três réplicas caíram juntas, umas vezes em um nó e outras no outro. O scheduler não promete distribuir. Se o nó com duas réplicas cair, o serviço perde 67 % da sua capacidade de uma vez, e o autoscaler não ajuda: o trabalho dele é olhar a CPU, não a distribuição.

#### 9.4.2 `topologySpreadConstraints`

O Kubernetes tem uma peça para isto: as **restrições de dispersão por topologia**. “Topologia” aqui quer dizer “em que parte da infraestrutura vive cada coisa”: em que nó, em que zona de uma nuvem, em que rack. A documentação define o vocabulário ([Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/)): um rótulo (label) de nó, `topologyKey`, divide os nós em **domínios**, e os nós que têm o mesmo valor desse rótulo formam um mesmo domínio. O rótulo `kubernetes.io/hostname` tem um valor diferente por nó, então com ele *cada nó é o seu próprio domínio*. É isso que se quer aqui: distribuir entre nós.

A restrição do `revisor` é esta. É um fragmento do **programa** `revisor-deployment.yaml`, dentro de `spec.template.spec`:

```yaml
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        nodeTaintsPolicy: Honor
        labelSelector:
          matchLabels:
            app: revisor
        matchLabelKeys:
        - pod-template-hash
```

Cada campo, em ordem:

- **`topologyKey: kubernetes.io/hostname`**: cada nó é um domínio, como foi dito.
- **`labelSelector`**: quais Pods são contados em cada domínio. Os que têm `app: revisor`; as réplicas de `prueba` ou os Pods de carga não contam, nem atrapalham.
- **`maxSkew: 1`**: a **assimetria** (*skew*) máxima permitida: a diferença entre o número de Pods de um domínio e o do domínio com menos. A documentação define assim: com `DoNotSchedule`, `maxSkew` “é a diferença máxima permitida entre o número de Pods correspondentes no domínio alvo e o *mínimo global*”. Com `maxSkew: 1` e dois nós de trabalho, 2 + 0 não é permitido (diferença de 2), 1 + 1 sim, 2 + 1 sim, 3 + 1 não.
- **`whenUnsatisfiable: DoNotSchedule`**: o que fazer se colocar o Pod quebra a restrição. `DoNotSchedule` (o valor padrão) diz “não o agende”: o Pod fica `Pending`. `ScheduleAnyway` diz “agende-o mesmo assim, mas preferindo os lugares que reduzam a assimetria”: é uma preferência, não uma regra. Esta lição usa a regra dura, porque a suave deixa passar justamente o que se quer evitar: a restrição existe para que a distribuição *seja de fato cumprida*, e uma preferência não a garante.
- **`nodeTaintsPolicy: Honor`**: como tratar os *taints* dos nós ao calcular a assimetria. É explicado em 9.4.3 e conferido em 9.5.4, porque é o campo que parece sobrar e não sobra.
- **`matchLabelKeys: [pod-template-hash]`**: restringe a contagem às réplicas da **mesma versão**. O Deployment coloca em cada Pod um rótulo, `pod-template-hash`, com um valor diferente para cada versão do template. A documentação diz que esse rótulo, que “o controlador do Deployment adiciona automaticamente”, serve “para distinguir entre revisões diferentes de um mesmo Deployment”. Durante uma atualização convivem réplicas antigas e novas; sem este campo, as antigas contariam para a distribuição das novas e atrapalhariam; com ele, cada versão é distribuída por conta própria.

#### 9.4.3 Por que o nó de controle exige `Honor`

O cluster tem três nós e só dois recebem réplicas. O nó de controle leva um *taint* (`node-role.kubernetes.io/control-plane:NoSchedule`) que impede agendar Pods de usuário ali. Mas ele conta como domínio, para o cálculo do “mínimo global”? Depende de `nodeTaintsPolicy`. A documentação define as duas opções: `Honor` inclui “os nós sem taints, junto com os nós com taints para os quais o Pod que chega tem uma tolerância”; `Ignore` ignora os taints e inclui todos os nós; e se o campo estiver vazio, o comportamento equivale a `Ignore`.

Isso significa que, **sem** `Honor`, o nó de controle entra na conta como um domínio com zero Pods, e o “mínimo global” é 0, porque esse nó não pode receber uma réplica. Com esse zero fixo, `maxSkew: 1` permite no máximo 1 Pod por domínio: a terceira réplica não teria para onde ir. É o tipo de regra que funciona com duas réplicas e quebra com a terceira, e por isso mesmo é um erro que se encontra em produção numa segunda-feira às 9h. A seção 9.5.4 o provoca para que se veja.

#### 9.4.4 O que a restrição não faz

A documentação desta peça traz uma advertência na seção de limitações: “não há garantia de que as restrições continuem sendo cumpridas quando Pods são removidos. Por exemplo, reduzir um Deployment pode deixar os Pods desbalanceados”, e recomenda ferramentas como o *Descheduler* para rebalancear. A regra se aplica **ao agendar** um Pod novo, não antes nem depois. A seção 9.11 vai mostrá-lo com uma manutenção que deixa as réplicas juntas, e mostrará também como se remedeia sem instalar nada.

### 9.5 Aplicar as mudanças

#### 9.5.1 O que muda, antes de aplicar

Com a pasta da Lição 9 pronta, o primeiro passo não é aplicar, e sim perguntar o que vai mudar. O `kubectl diff -k .` manda ao servidor o resultado do `-k` e mostra a diferença contra o que existe. O comando é filtrado (`grep -E '^[+-] '`) para ficar com as linhas que mudam e tirar o ruído de metadados (`creationTimestamp`, `uid`, `resourceVersion`):

```text
$ kubectl diff -k . | grep -E '^[+-] ' | grep -v -E 'creationTimestamp|generation|resourceVersion|uid:|managedFields'
-  replicas: 3
+  replicas: 1
-      maxSurge: 25%
-      maxUnavailable: 25%
+      maxSurge: 1
+      maxUnavailable: 0
+        lifecycle:
+          preStop:
+            sleep:
+              seconds: 5
-      terminationGracePeriodSeconds: 10
+      terminationGracePeriodSeconds: 15
+      topologySpreadConstraints:
+      - labelSelector:
+          matchLabels:
+            app: revisor
+        matchLabelKeys:
+        - pod-template-hash
+        maxSkew: 1
+        nodeTaintsPolicy: Honor
+        topologyKey: kubernetes.io/hostname
+        whenUnsatisfiable: DoNotSchedule
+  name: revisor
+  namespace: revisor
+  behavior:
+    scaleDown:
+      policies:
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 60
+    scaleUp:
+      policies:
+      - periodSeconds: 15
+        type: Pods
+        value: 4
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 0
+  maxReplicas: 6
+  metrics:
+  - resource:
+      name: cpu
+      target:
+        averageUtilization: 50
+        type: Utilization
+    type: Resource
+  minReplicas: 2
+  scaleTargetRef:
+    apiVersion: apps/v1
+    kind: Deployment
+    name: revisor
+  currentMetrics: null
+  desiredReplicas: 0
+  name: revisor
+  namespace: revisor
+  minAvailable: 1
+  selector:
+    matchLabels:
+      app: revisor
+  currentHealthy: 0
+  desiredHealthy: 0
+  disruptionsAllowed: 0
+  expectedPods: 0
[código de salida: 1]
```

O código `1` no final não é um erro: o `kubectl diff` sai com 1 quando **há** diferenças e com 0 quando não há, para poder ser usado num script. Lê-se em três blocos:

1. **`-  replicas: 3` / `+  replicas: 1`.** O que foi anunciado em 9.3.4. O arquivo já não diz `replicas`, e o servidor, que traz o seu valor padrão, propõe **1**. Se isso for aplicado sem pensar, o `revisor` passa de três réplicas para uma, nem que seja por um instante, antes que o autoscaler o corrija. Aqui não é grave; com 40 pessoas conectadas às 9h, seria. É o custo único de entregar o controle do número de réplicas, e convém saber disso antes de pagá-lo.
2. **`maxSurge: 25%` → `1` e `maxUnavailable: 25%` → `0`.** Os valores padrão da estratégia de atualização se tornam explícitos. São explicados em 9.9.
3. **`lifecycle` / `preStop`, `terminationGracePeriodSeconds: 10` → `15` e `topologySpreadConstraints`.** A pausa antes de desligar, o prazo mais longo de que essa pausa precisa e a distribuição de 9.4. E abaixo, os objetos novos: o HPA (com os valores padrão escritos) e o PodDisruptionBudget.

#### 9.5.2 Aplicar e observar

```text
$ kubectl apply -k . | grep -E 'horizontalpod|poddisruption|deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
poddisruptionbudget.policy/revisor created
horizontalpodautoscaler.autoscaling/revisor created

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
(espera de 30 s: el HPA necesita su primera lectura de métricas)
```

Quatro linhas: `deployment.apps/revisor configured`, o PDB e o HPA `created`, e `prueba unchanged` (o que não mudou não é tocado). O `rollout status` mostra a substituição das réplicas, porque o template mudou (o `preStop`, o prazo e a distribuição) e por isso há uma substituição ordenada, uma a uma, como na Lição 2. Depois há uma pausa de 30 segundos à vista: o HPA precisa da sua primeira leitura de métricas antes de mostrar um número.

```text
$ kubectl get hpa,pdb -n revisor
NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          32s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     32s
```

Leia a coluna `TARGETS` do HPA: `cpu: 2%/50%` é “uso atual / meta”. O uso é a média, sobre os `requests` dos Pods, que a seção 9.2 explicou. `MINPODS 2` e `MAXPODS 6` são o mínimo e o máximo, e `REPLICAS` é o número atual. No PDB, `ALLOWED DISRUPTIONS` diz quantos Pods podem ser perdidos voluntariamente agora mesmo; é explicado em 9.11.

Um detalhe de leitura: na primeira vez que o HPA é aplicado, se for olhado cedo demais, `TARGETS` diz `cpu: <unknown>/50%`. Não é uma falha: o controlador ainda não tem uma medição dos Pods novos. Os eventos do HPA, que são lidos em 9.6, guardam o rastro desses primeiros segundos.

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-5xvt5   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-857qf   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.replicas}{"\n"}'
2
```

Duas réplicas, **uma em cada nó de trabalho**. A distribuição foi cumprida, e o número de réplicas foi colocado pelo HPA: `.spec.replicas` vale 2, o mínimo. A cadeia mais provável, e a que o evento `Current number of replicas below Spec.MinReplicas` de 9.6 sugere, foi: o `apply` deixou o Deployment em 1 (o valor padrão), o HPA viu que 1 estava abaixo do mínimo de 2 e o subiu, e a substituição distribuiu as duas réplicas pela restrição.

#### 9.5.3 O histórico de eventos do HPA conta o que ele fez

O HPA deixa as suas decisões nos eventos. Eles são lidos com `describe`, que será mostrado completo em 9.6 depois da carga, e a primeira linha é o rastro do que está acima: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. “O número atual de réplicas está abaixo do mínimo”: o HPA não estava reagindo à carga, e sim aplicando o mínimo.

#### 9.5.4 O erro: a distribuição sem `nodeTaintsPolicy: Honor`

Agora o erro prometido em 9.4.3. Ele é provocado retirando somente o `nodeTaintsPolicy` do Deployment vivo, com um patch, e pedindo uma terceira réplica na mão:

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/topologySpreadConstraints/0/nodeTaintsPolicy"}]'
deployment.apps/revisor patched

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running       0          6s    10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running       0          3s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5xvt5   1/1     Terminating   0          38s   10.244.2.8   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-857qf   1/1     Terminating   0          38s   10.244.1.8   curso-k8s-l9-worker    <none>           <none>
```

Com duas réplicas tudo parece normal. É o que torna este erro traiçoeiro: o defeito não aparece até que a terceira chegue.

```text
$ kubectl scale deployment/revisor -n revisor --replicas=3
deployment.apps/revisor scaled
(espera de 6 s: el planificador decide en un instante)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running   0          12s   10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-4nwx5   0/1     Pending   0          6s    <none>       <none>                 <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running   0          9s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
```

A terceira réplica fica `Pending`, sem nó atribuído. Segue-se a ordem da Lição 5: o `describe` do Pod pendente (o nome muda na execução de quem acompanha), seção de eventos.

```text
$ kubectl describe pod revisor-574b5b6c4c-4nwx5 -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  6s    default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match pod topology spread constraints. preemption: 0/3 nodes are available: 1 Preemption is not helpful for scheduling, 2 No preemption victims found for incoming pod.
```

Leia: `0/3 nodes are available` diz que dos três nós, nenhum serve. E dá o motivo de cada um: um nó tem um taint que o Pod não tolera (*untolerated taint*; é o de controle), e os outros dois “não correspondem às restrições de dispersão por topologia” (*didn't match pod topology spread constraints*). É justamente o que foi anunciado: o nó de controle conta como domínio com zero Pods, o mínimo global é 0, e colocar a terceira réplica em qualquer um dos outros dois daria uma assimetria de 2.

A correção é aplicar de novo o arquivo, que traz `Honor`:

```text
# --- La corrección: volver a aplicar la carpeta (trae Honor) ---

$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Terminating   0          18s   10.244.1.9    curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Terminating   0          15s   10.244.2.9    curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running       0          6s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-76td2   1/1     Running       0          2s    10.244.1.11   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running       0          4s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
(espera de 75 s: la ventana de bajada del autoescalador es de 60 s)
```

Com `Honor`, o nó de controle sai da conta: três réplicas em dois domínios, 2 + 1, assimetria de 1. Cabe. E como o `apply -k` não traz `replicas`, o número vive no Deployment até que o HPA o corrija: depois da janela de redução de 60 segundos (à vista, 75 de espera), o HPA devolve a contagem a 2, que é o que a carga pede.

```text
$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           4m11s
deployment.apps/revisor   2/2     2            2           4m11s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          2m5s

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          82s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          80s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

### 9.6 Com carga, o autoscaler sobe

#### 9.6.1 Uma carga que se pode desligar

Para ver o autoscaler trabalhar é preciso carga, e a carga tem de poder ser desligada quando a gente quiser. É um **programa**: `carga.yaml`.

```yaml
# carga.yaml — Lección 9: genera carga contra el revisor para ver subir el HPA.
# No forma parte del proyecto: se aplica con -f, se observa y se borra.
apiVersion: batch/v1
kind: Job
metadata:
  name: carga
  namespace: revisor
spec:
  parallelism: 4
  backoffLimit: 0
  activeDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app: carga
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
      - name: carga
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["sh", "-c", "while true; do curl -s -o /dev/null http://revisor/salud; done"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 200m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

É um `Job`, o objeto da Lição 8 para tarefas que terminam, com quatro Pods em paralelo (`parallelism: 4`) que repetem sem parar uma requisição a `http://revisor/salud`. Não há pausa entre uma e outra: cada Pod pede, recebe e volta a pedir. Lê-se por decisões:

- **`activeDeadlineSeconds: 600`**: aconteça o que acontecer, o Job para aos 10 minutos: tem de sobreviver ao download da imagem mais os 200 segundos de observação. Um gerador de carga sem freio é uma avaria à espera; este termina mesmo que se esqueça de apagá-lo.
- **`backoffLimit: 0`**: se um Pod falha, não há nova tentativa. É uma carga de laboratório, não uma tarefa que importe.
- **`acceso-revisor: permitido`**: o rótulo (label) que a rede fechada da Lição 7 exige para chegar ao `revisor`. Sem ele, os Pods de carga não chegariam a lugar nenhum, e o HPA não veria nenhuma carga. É a mesma permissão do Pod `depurar`.
- **`limits: cpu: 200m`**: cada Pod de carga pode consumir até um quinto de um núcleo. Isso coloca um **teto na carga que se pode gerar**: quatro Pods de 200m são 800m no total, e quanto disso se converte em CPU do `revisor` depende de quantas requisições por segundo ele consegue responder. Não é um teste de desempenho; é uma alavanca com limite.
- **A imagem do `curl`, fixada pelo seu digest**, como na Lição 3. Na primeira vez que um nó a usa, ele a baixa da internet; por isso o script espera (à vista) que os Pods de carga estejam prontos antes de começar a olhar o relógio.

#### 9.6.2 Aplicar, esperar, olhar

```text
$ kubectl apply -f carga.yaml
job.batch/carga created
(espera visible: hasta 600 s a que los Pods de carga arranquen; la primera vez descargan la imagen de curl)
```

Depois vem uma espera com `kubectl wait`, pela razão acima: até que os Pods de carga estejam `Ready`, não há carga, e olhar o HPA antes seria medir o silêncio.

```text
$ kubectl wait --for=condition=Ready pod -l app=carga -n revisor --timeout=600s
pod/carga-29s8s condition met
pod/carga-bz6zl condition met
pod/carga-nv5tb condition met
pod/carga-rnhz5 condition met
```

Agora o tempo corre. O script imprime uma linha do HPA a cada 20 segundos durante 200 segundos. No terminal de quem acompanha, o equivalente é `kubectl get hpa revisor -n revisor --watch` (que imprime uma linha nova cada vez que algo muda), ou um laço de `get` e `sleep 20` como o do script. A espera faz parte da lição: o autoscaler não é instantâneo, e ver quanto ele demora é o que se aprende.

```text
(un renglón del HPA cada 20 s, durante 200 s; empieza a las 17:18:00)
[+ 20s] revisor   Deployment/revisor   cpu: 27%/50%   2     6     2     2m50s
[+ 40s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     2     3m10s
[+ 60s] revisor   Deployment/revisor   cpu: 72%/50%   2     6     2     3m30s
[+ 80s] revisor   Deployment/revisor   cpu: 58%/50%   2     6     3     3m51s
[+100s] revisor   Deployment/revisor   cpu: 44%/50%   2     6     4     4m11s
[+120s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     4     4m31s
[+140s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     4m51s
[+160s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m11s
[+180s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m31s
[+200s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

Cada linha se lê da mesma forma: o tempo desde que a carga começou, o nome, o alvo, a coluna `TARGETS` (`uso atual / meta`), o mínimo, o máximo, as réplicas e a idade do HPA. É preciso lê-las com a fórmula de 9.3 na mão.

As linhas, com a fórmula de 9.3 aplicada a cada uma:

| Tempo | Uso medido | Réplicas | Razão (uso ÷ 50) | Conta | O que faz |
|---|---|---|---|---|---|
| +20 s | 27 % | 2 | 0,54 | — | a carga mal chega |
| +40 s | 46 % | 2 | 0,92 | dentro de 0,9 a 1,1 | nada: a tolerância o detém |
| +60 s | 72 % | 2 | 1,44 | `ceil(2 × 1,44)` = `ceil(2,88)` = 3 | decide subir para 3 |
| +80 s | 58 % | 3 | 1,16 | `ceil(3 × 1,16)` = `ceil(3,48)` = 4 | decide subir para 4 |
| +100 s | 44 % | 4 | 0,88 | `ceil(4 × 0,88)` = `ceil(3,52)` = 4 | fica em 4 |
| +120 s | 46 % | 4 | 0,92 | dentro da tolerância | nada |
| +140 a +200 s | 38 % | 4 | 0,76 | `ceil(4 × 0,76)` = `ceil(3,04)` = 4 | fica em 4 |

Há três coisas para ver aí. **Primeira**: a linha de +40 segundos, com 46 %, não faz nada embora a carga já esteja em cima. Não é lentidão, é a tolerância: 46 % está 8 % abaixo da meta, dentro dos 10 % que o controlador perdoa. **Segunda**: em +60 s o uso é de 72 % com 2 réplicas e o autoscaler decide subir para 3; a linha de +80 s já mostra 3, porque entre uma linha e outra passam 20 segundos e a decisão foi tomada no intervalo. A mudança de 3 para 4 está separada da primeira por uns 30 segundos (os eventos abaixo dizem há `2m37s` e há `2m7s`), provavelmente porque os Pods novos precisam nascer e começar a trabalhar antes que o seu consumo conte. **Terceira**, e é a mais instrutiva: de +140 a +200 segundos o uso fica em 38 % com 4 réplicas, uma razão de 0,76 que está **fora** da tolerância por baixo, e mesmo assim o autoscaler não reduz. A conta explica por quê: `ceil(4 × 0,76)` é `ceil(3,04)`, que é 4. O arredondamento para cima mantém a quarta réplica por quatro centésimos. O sistema se estabilizou sozinho: cada réplica nova repartiu a carga, a média baixou de 72 para 38 %, e com essa média quatro réplicas são o número que a fórmula quer. O teto de 6 não foi tocado.

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-4q7wh   1/1     Running   0          2m5s    10.244.2.13   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running   0          5m9s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-pchj4   1/1     Running   0          2m36s   10.244.1.14   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          5m7s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-4q7wh   18m          6Mi             
revisor-767bdf965b-5b6k9   19m          7Mi             
revisor-767bdf965b-pchj4   20m          7Mi             
revisor-767bdf965b-vcznx   20m          6Mi             
$ kubectl get hpa revisor -n revisor -o jsonpath='réplicas={.status.currentReplicas} deseadas={.status.desiredReplicas} cpu={.status.currentMetrics[0].resource.current.averageUtilization} % ({.status.currentMetrics[0].resource.current.averageValue}){"\n"}'
réplicas=4 deseadas=4 cpu=38 % (19m)
```

O `kubectl top pods` mostra o consumo real de cada réplica no instante da consulta: 18, 19, 20 e 20 milicores. Contra os `50m` que cada uma pediu, são 36 a 40 %. E o HPA, com a sua própria consulta, diz numa linha: `cpu=38 % (19m)` é “utilização média de 38 %, que equivale a 19 milicores por Pod”. A conta dá para fazer à mão: (18 + 19 + 20 + 20) ÷ 4 = 19,25 milicores, que arredonda para `19m`, e 19 ÷ 50 é 0,38. A coluna `TARGETS` não é um mistério: é esta divisão. `réplicas=4 deseadas=4` diz o que já se viu: o que existe é o que a fórmula quer.

Os eventos do HPA são o seu histórico, e contam o mesmo com outras palavras:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                    From                       Message
  ----     ------                        ----                   ----                       -------
  Normal   SuccessfulRescale             5m54s                  horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             4m39s                  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             2m37s                  horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m7s                   horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
```

Leia-os de baixo para cima, do mais antigo ao mais novo. `SuccessfulRescale … New size: 2; reason: Current number of replicas below Spec.MinReplicas` é o primeiro ajuste, o de 9.5: o mínimo. Os dois `Warning` que seguem (`FailedGetResourceMetric`, `FailedComputeMetricsReplicas`) são o autoscaler dizendo que ainda não tem métricas dos Pods novos: `unable to get metrics for resource cpu: no metrics returned from resource metrics API`. São normais nos primeiros segundos de vida de um Pod, enquanto o `metrics-server` faz a sua primeira leitura; o `(x3 over 5m39s)` diz que se repetiram três vezes. O seguinte, `New size: 2; reason: All metrics below target`, não é desta carga: é o HPA devolvendo a 2 a terceira réplica que 9.5.4 pediu na mão. E os dois últimos, com 30 segundos de diferença (há `2m37s` e há `2m7s`), são as decisões desta seção: `New size: 3` e `New size: 4`, os dois com o motivo `cpu resource utilization (percentage of request) above target`: o consumo, medido como porcentagem da solicitação, acima da meta.

### 9.7 Sem carga, desce, depois da janela

O Job é apagado, e o HPA é observado a cada 20 segundos durante 260 segundos. O que se vai ver é a janela de redução de 9.3.3:

```text
$ kubectl delete -f carga.yaml
job.batch "carga" deleted from revisor namespace

(un renglón del HPA cada 20 s, durante 260 s; empieza a las 17:21:25)
[+ 20s] revisor   Deployment/revisor   cpu: 36%/50%   2     6     4     6m15s
[+ 40s] revisor   Deployment/revisor   cpu: 39%/50%   2     6     4     6m35s
[+ 60s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     6m55s
[+ 80s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     4     7m15s
[+100s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     7m35s
[+120s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     7m56s
[+140s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     8m16s
[+160s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m36s
[+180s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m56s
[+200s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     9m16s
[+220s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     2     9m36s
[+240s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     9m56s
[+260s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     10m
```

O relógio conta assim. O Job é apagado no segundo 0, mas a leitura de +20 e a de +40 continuam altas (36 % e 39 %): o mais provável é que os Pods de carga demorem alguns segundos para terminar, e o `metrics-server` calcula a média do consumo de uma janela curta, não de um instante. Em +60 s a leitura já é de 3 %, e fica aí. Com 4 réplicas e 3 % de uso, a conta é `ceil(4 × 0,06)` = `ceil(0,24)` = 1, mas o mínimo é 2, então o que o autoscaler *quer* é 2. E, no entanto, a coluna de réplicas diz 4 em +60, +80 e +100, e só passa a 2 na linha de +120. Essa diferença é a janela de redução de 60 segundos de 9.3.3: durante esse minuto, o HPA não usa a recomendação de hoje, mas a mais alta dos últimos 60 segundos, e a última recomendação de 4 réplicas foi feita com as leituras altas do início.

Os eventos dão os horários com mais precisão que a tabela. Para lê-los é preciso subtrair a partir do momento em que o `describe` foi executado (logo ao terminar a tabela, uns 262 segundos depois de apagar o Job): `New size: 3` ocorreu há `2m54s`, ou seja, por volta de +88 s, e `New size: 2` há `2m39s`, por volta de +103 s. Isto é, a redução ocorreu em dois degraus, de 4 para 3 e 15 segundos depois de 3 para 2, a uns 50 ou 60 segundos da última leitura alta. É o que se espera de uma janela: as recomendações da parte alta vão saindo dela uma a uma. (A tabela nunca mostra o degrau de 3 porque a coluna `REPLICAS` do HPA é atualizada com atraso em relação ao Deployment: é `status.currentReplicas`, que o HPA escreve na sua própria volta, a cada 15 s; por isso a linha de +100 ainda diz 4 embora o evento de descer para 3 seja de +88. Que número o HPA vê em cada volta não foi medido.)

Mais dois trechos do `describe` completam a leitura. A tabela de condições:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Conditions:/,/Events:/p'
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScaledToZero    False   NotScaledToZero   the HPA controller did not scale the workload to zero
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
Events:
```

`ScalingLimited True TooFewReplicas: the desired replica count is less than the minimum replica count` é o HPA dizendo, com todas as letras, o que foi calculado acima: o que a fórmula pede (1) é **menos** que o mínimo (2), e por isso fica em 2. `ScalingActive True ValidMetricFound` diz que ele consegue calcular, ou seja, que o `metrics-server` continua respondendo. É a tabela que se olha quando um HPA “não faz nada” e é preciso saber se é porque não pode ou porque não quer. E o consumo real das duas réplicas que restam:

```text
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-5b6k9   1m           6Mi             
revisor-767bdf965b-vcznx   1m           5Mi             
```

Um milicore cada uma: a carga foi embora de verdade. Os eventos completos, e as réplicas que restam:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                   From                       Message
  ----     ------                        ----                  ----                       -------
  Normal   SuccessfulRescale             10m                   horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       9m17s (x3 over 10m)   horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  9m17s (x3 over 10m)   horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             7m                    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             6m30s                 horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m54s                 horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             2m39s (x2 over 9m2s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          9m33s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          9m31s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

O evento `New size: 2; reason: All metrics below target` (“todas as métricas abaixo da meta”) é a redução. E as duas réplicas que restam são uma em cada nó de trabalho: a restrição de distribuição de 9.4 continua cumprida depois de retirar dois Pods.

### 9.8 Quem manda nas réplicas

O Deployment tem `replicas` vazio no arquivo, mas continua tendo um número. O que acontece se alguém mais o mudar na mão? Testa-se com `kubectl scale`, que escreve o número de réplicas no Deployment, o mesmo campo que o HPA escreve:

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

Quarenta segundos depois, o Deployment tem outra vez 2 réplicas, e o último evento do HPA diz isso: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. O HPA não discutiu nem perguntou: na volta seguinte viu que o Deployment tinha menos réplicas que o mínimo, e o devolveu. Isso responde a uma pergunta prática: **com um HPA ativo, o `kubectl scale` serve de pouco**. Se baixar abaixo do mínimo, o HPA corrige; se subir acima do que a carga pede, ele corrige para baixo assim que a janela passa (9.5.4 mostrou isso com a terceira réplica: aos 75 segundos o Deployment já estava de volta em 2). Para mudar o número de réplicas com um HPA vivo, é preciso mudar o HPA: o seu `minReplicas` ou o seu `maxReplicas`. Quem quiser dois donos para o mesmo número tem o problema de 9.3.4.

### 9.9 Atualizar e medir a interrupção

#### 9.9.1 Como um Deployment atualiza

Quando se muda o template de Pods de um Deployment (a imagem, uma variável, um `preStop`), não se desligam todas as réplicas para ligar outras. O Deployment cria um `ReplicaSet` novo para o template novo e vai movendo réplicas do antigo para o novo, de poucas em poucas. A documentação descreve assim: declara-se o estado novo atualizando o template, “cria-se um novo ReplicaSet, e o Deployment vai escalando-o enquanto reduz o antigo, garantindo que os Pods sejam substituídos num ritmo controlado” ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). Dois números governam esse ritmo, e estão no Deployment desde 9.5:

- **`maxSurge`**: quantos Pods **a mais** podem ser criados acima do número desejado durante a atualização. A documentação: “o número máximo de Pods que podem ser criados acima do número desejado de Pods”, como número ou porcentagem; o valor padrão é 25 %.
- **`maxUnavailable`**: quantos Pods podem ser perdidos, isto é, ficar **indisponíveis**, durante a atualização. Por padrão também 25 %; a documentação esclarece que não pode ser 0 se `maxSurge` for 0 (senão, a atualização não conseguiria avançar).

O `revisor` os fixa em `maxSurge: 1` e `maxUnavailable: 0`. Lê-se como uma regra de segurança: “não retire uma réplica que responde até que haja outra nova pronta para substituí-la”. Com duas réplicas, o Deployment cria **uma** réplica nova (a terceira, pelo `maxSurge`), espera que esteja pronta e só então desliga uma antiga; depois repete com a outra. Em nenhum momento há menos de duas réplicas disponíveis. É a parte da atualização que o Kubernetes sabe fazer sozinho, e por isso o `rollout status` imprime `1 out of 2 new replicas have been updated`: vai contando as novas.

Mas “disponível” é uma palavra do plano de controle. O que as requisições sentem é outra coisa, e a diferença se chama *condição de corrida*.

#### 9.9.2 A condição de corrida do desligamento

Quando o Deployment decide retirar uma réplica antiga, essa réplica percorre os passos que a documentação do ciclo de vida de um Pod descreve como o fluxo de terminação ([Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)):

1. O Pod é marcado como *terminando* na API, com um prazo (por padrão, 30 segundos; o do `revisor` é de 15).
2. No nó, o `kubelet` vê a marca e começa o desligamento local: se o contêiner declara um hook `preStop`, ele o executa primeiro. Depois, o runtime de contêineres manda o sinal `TERM` ao processo 1 de cada contêiner, e o processo tem o que restar do prazo para terminar. Se continuar vivo ao vencer o prazo, recebe `KILL`.
3. **“Ao mesmo tempo que o kubelet começa o desligamento ordenado do Pod”**, o plano de controle avalia se é preciso tirá-lo dos `EndpointSlice` dos Services que o usam. A documentação acrescenta um detalhe útil: um destino que representa um Pod que está sendo desligado não é retirado de imediato; é marcado como *terminando* e com `ready: false`, e os balanceadores deixam de usá-lo para o tráfego normal.

O passo 2 e o passo 3 **não esperam um pelo outro**. Essa é a condição de corrida. É a observação de Phil Pearl da cena, medida em outro contexto: o aviso de desligamento chega ao processo no mesmo momento em que começa a correr a notícia “tire-o da lista”, e a notícia precisa viajar: do plano de controle aos `EndpointSlice`, de lá ao `kube-proxy` em cada nó, e de lá às regras de rede de cada nó. Enquanto viaja, alguns nós ainda enviam requisições ao Pod antigo. Se o processo já fechou a sua porta ao receber `TERM`, essas requisições encontram uma porta fechada: `Connection refused`, ou silêncio.

O `revisor` faz bem a sua parte: ao receber `TERM`, escreve `recibí terminated, apagando`, termina as requisições que tem em andamento e sai com `apagado limpio`, com um prazo interno de 5 segundos (a Lição 5 o mediu). Mas “termina as que tem em andamento” não inclui “continua aceitando novas”. O desligamento do `revisor` usa `Server.Shutdown`, da biblioteca padrão do Go, e a documentação dessa função diz como ela trabalha: “primeiro fecha todos os listeners abertos, depois fecha todas as conexões ociosas e depois espera” que as conexões ativas terminem ([Go, `net/http`](https://pkg.go.dev/net/http#Server.Shutdown)). A porta de entrada é fechada **primeiro**. O que falta não é um defeito do `revisor`; é tempo para que a notícia chegue.

Desde que Pearl escreveu (2019), o Kubernetes adicionou aos `EndpointSlice` as condições `serving` e `terminating`, e permitiu que o `kube-proxy` use destinos que estão terminando quando nenhum está pronto. Isso evita perder tráfego quando *todos* os destinos estão sendo desligados, mas não muda o fato de que o aviso de desligamento e a retirada de destinos viajam por caminhos diferentes: a condição de corrida continua existindo e é a que esta lição mede.

#### 9.9.3 A pausa que fecha a condição de corrida: `preStop`

Um hook `preStop` roda **antes** do sinal `TERM`. Se tudo o que ele faz é esperar uns segundos, o processo continua respondendo normalmente durante essa espera, enquanto a notícia de “tire-o da lista” termina de viajar. Quando por fim chega o `TERM`, já ninguém lhe manda tráfego novo. O Pod do `revisor` não tem shell (a imagem é mínima, da Lição 5), então o hook não pode ser um `sh -c "sleep 5"`; o Kubernetes traz uma ação de espera nativa:

```yaml
        lifecycle:
          preStop:
            sleep:
              seconds: 5
```

Isso é tudo o que foi acrescentado ao Deployment. Cinco segundos é uma escolha, não uma lei: têm de bastar para que a notícia chegue a todos os nós do cluster, e quanto isso demora depende do tamanho e da carga do cluster. Pearl, no seu caso, recomendava esperar mais do que o tempo que o balanceador leva para se reprogramar. A pausa também conta contra o prazo de desligamento: a documentação diz que o tempo do `preStop` faz parte do `terminationGracePeriodSeconds`, e que, se for preciso mais, é necessário aumentar o prazo. Por isso o Deployment passou de 10 para **15 segundos**: 5 de pausa, até 5 de desligamento do `revisor` e 5 de margem.

Tudo isso é teoria até ser medido. Medir exige uma ferramenta, e a ferramenta é um programa.

#### 9.9.4 O polling

A medição tem de cumprir três coisas: **contar** cada requisição, não uma amostra; **rodar durante** a mudança, não antes nem depois; e **distinguir** qual versão respondeu e de que maneira falhou cada falha. É um **programa**: `sondeo.sh`.

```bash
#!/usr/bin/env bash
# sondeo.sh — Lección 9: mide cuántas peticiones se pierden mientras haces algo.
#
# Uso:  ./sondeo.sh DURACION PAUSA HILOS [argumentos de curl]
#   DURACION  segundos que dura el sondeo
#   PAUSA     segundos entre una petición y la siguiente, en cada hilo (0 = sin pausa)
#   HILOS     cuántos ciclos de peticiones corren a la vez
#   lo demás  se le pasa a curl (por ejemplo: --retry 3 --retry-all-errors)
#
# Las peticiones salen del Pod «depurar» (curl dentro del clúster) hacia
# http://revisor/salud, es decir, por el Service, como cualquier cliente de dentro.
# Cada petición deja una línea «segundo cuerpo código rc=salida-de-curl». Al final se cuenta.
#
# 🔴 Antes de hablarle al clúster comprueba que el contexto activo es
# kind-curso-k8s-l9 y, si no, se detiene.
set -euo pipefail

[ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo" >&2; exit 1; }
[ "$#" -ge 3 ] || { echo "uso: $0 DURACION PAUSA HILOS [argumentos de curl]" >&2; exit 2; }
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
EXTRA="$*"

# Este guion corre DENTRO de depurar (por la entrada estándar de kubectl exec).
kubectl exec -i -n revisor depurar -- sh -s -- "$DURACION" "$PAUSA" "$HILOS" $EXTRA <<'DENTRO' |
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
inicio=$(date +%s); fin=$((inicio + DURACION))
for h in $(seq 1 "$HILOS"); do
  (
    while [ "$(date +%s)" -lt "$fin" ]; do
      r=$(curl -s -m 2 -w ' %{http_code}' "$@" http://revisor/salud; echo " rc=$?")
      echo "$(( $(date +%s) - inicio )) $(echo $r)"
      [ "$PAUSA" = 0 ] || sleep "$PAUSA"
    done
  ) &
done
wait
DENTRO
awk '
  { rc = $NF; code = $(NF - 1); v = "-"
    if (match($0, /"version":"[0-9.]+"/)) v = substr($0, RSTART + 11, RLENGTH - 12)
    n++; cuenta[code " " rc " " v]++
    if (code != "200") { f++; if (nf < 40) { seg[nf++] = $1 } } }
  END {
    printf "peticiones=%d fallidas=%d\n", n, f
    for (k in cuenta) { split(k, a, " "); printf "  %5d  código %s  curl %s  versión %s\n", cuenta[k], a[1], a[2], a[3] }
    if (f > 0) { printf "  segundos (desde el inicio) de las primeras fallas:"; for (i = 0; i < nf; i++) printf " +%s", seg[i]; printf "\n" }
  }' | sort
```

Lê-se por partes.

- **Onde roda.** O laço de requisições roda **dentro** do Pod `depurar` da Lição 3, o do `curl`, e é enviado pela entrada padrão do `kubectl exec -i`. Assim as requisições nascem dentro do cluster e passam pelo Service, igual às de qualquer cliente interno (por exemplo, a tarefa agendada da Lição 8). **Alcance:** esta medição cobre o caminho de um cliente dentro do cluster, isto é, o Service e o `kube-proxy`. Não passa pelo Gateway do Envoy, por onde entrariam os usuários de fora: essa peça fica sabendo das mudanças de destinos por conta própria e pode demorar mais ou menos que o `kube-proxy`, e esse caminho não foi medido aqui. Pearl observou o problema num Ingress, não num Service, e diz que nos Services a janela costuma ser curta. O `<<'DENTRO'` com aspas simples impede que o shell interprete qualquer coisa desse bloco: ele é enviado tal como está.
- **O que faz cada thread.** Um laço que, enquanto o tempo não acabar, pede `http://revisor/salud` com `curl -s -m 2`: silencioso (`-s`) e com um máximo de **2 segundos** por requisição (`-m 2`). `-w ' %{http_code}'` acrescenta ao final o código HTTP, e o `echo " rc=$?"` acrescenta a saída do próprio `curl`. Essa segunda cifra importa muito, porque distingue **como** uma requisição falhou, e cada modo conta uma história diferente (mais abaixo).
- **Uma linha por requisição.** `echo "$(( $(date +%s) - inicio )) $(echo $r)"` junta, numa só linha, o segundo em que ocorreu, o corpo da resposta, o código e a saída do `curl`. Uma linha por requisição evita que as linhas das quatro threads se misturem: cada `echo` é uma única escrita. (O `$(echo $r)` sem aspas achata as quebras de linha do corpo; a resposta do `revisor` traz uma no final, e sem esse truque a linha se partiria em duas.)
- **A contagem.** O `awk` final agrupa por (código, saída do `curl`, versão que respondeu) e imprime quantas houve de cada uma, e os segundos das primeiras 40 falhas. “Falha” é qualquer código diferente de `200`, incluindo `000`, que é o que o `curl` imprime quando não chegou a receber uma resposta HTTP.
- **Os dois modos de falha que vão aparecer.** O `curl` sai com **7** quando não conseguiu se conectar (`Failed to connect`): chegou a um endereço onde ninguém escuta, ou a conexão foi recusada. Sai com **28** quando o tempo se esgotou (`-m 2`) sem resposta. Do primeiro se pode dizer algo concreto: alguém respondeu “aqui não há ninguém”. Do segundo, só que ninguém respondeu a tempo; a causa pode estar no destino, na rede ou no próprio cliente.

Uma advertência de honestidade sobre o instrumento: o Pod `depurar` tem um limite de CPU de `100m`, e quatro laços de `curl` sem pausa o ocupam por completo. Um cliente no teto da sua CPU pode atrasar as suas próprias requisições e produzir tempos de espera que não são culpa do servidor. O que se mede é o *conjunto* cliente, rede e servidor. Por isso o polling base de 9.9.5 vem antes de qualquer mudança: mede que ruído o polling produz por si mesmo.

#### 9.9.5 Primeiro, o ruído; depois, a atualização com `preStop`

Antes de mudar qualquer coisa, o polling é medido contra um cluster quieto, para saber quanto ruído ele produz por si só. São 15 segundos, com quatro threads e sem pausa. Depois vem a primeira atualização, a do manifesto como está, com o `preStop` colocado. O script lança o polling em segundo plano (`&`), espera 3 segundos para que já esteja rodando, troca a imagem de `1.6.0` para `1.6.1` e espera que a implantação termine:

```text
$ ./sondeo.sh 15 0 4
    172  código 200  curl rc=0  versión 1.6.0
peticiones=172 fallidas=0

$ ./sondeo.sh 45 0 4 &   # empieza a las 17:26:44
(pausa de 3 s: que el sondeo ya esté corriendo)

$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:1.6.1
deployment.apps/revisor image updated

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

# resultado del sondeo (A, con preStop):
     56  código 200  curl rc=0  versión 1.6.0
    416  código 200  curl rc=0  versión 1.6.1
peticiones=472 fallidas=0
```

O `kubectl set image` muda a imagem do contêiner `revisor` dentro do Deployment `revisor`, sem tocar em nenhum arquivo; é o caminho curto para esta medição (o hábito de segurança, mais abaixo, diz por que não é o caminho de um projeto real). O `rollout status` vai contando: “1 out of 2 new replicas have been updated”: das duas réplicas novas, uma já foi atualizada; e depois “1 old replicas are pending termination”: uma antiga ainda não terminou. É a mecânica do `maxSurge: 1` de 9.9.1 vista de fora: primeiro uma réplica nova, depois se retira uma antiga, depois outra nova.

A contagem se lê assim. O **polling base** fez 172 requisições em 15 segundos, 172 com código `200` e todas da versão `1.6.0`. Sem falhas: portanto o instrumento, naquele momento, não produz ruído visível. Mas 172 requisições são poucas para estimar o ruído: um ruído de 0,24 % esperaria menos de uma falha em 172 requisições, então esta rodada não distingue “zero” de “algumas por mil”. A **atualização A** fez 472 requisições em 45 segundos: 56 foram respondidas pela versão `1.6.0` (as anteriores à substituição e as que caíram em réplicas antigas enquanto avançava) e 416 pela `1.6.1`, e nenhuma falhou. Em nenhum momento houve uma linha com outro código. Se esta fosse a única rodada, a manchete seria “zero falhas em 472”. Mas uma rodada não basta, e o resto da seção existe para dizer por quê.

#### 9.9.6 O mesmo experimento, sem a pausa

Para saber o que o `preStop` evita, é preciso retirá-lo e medir o mesmo. Ele é retirado com um patch do tipo JSON que apaga o campo `lifecycle` do primeiro contêiner:

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/lifecycle"}]'
deployment.apps/revisor patched
```

`op: remove` com um `path` é “apague este campo”. O patch muda o template de Pods, então provoca a sua própria substituição; o script espera que termine com `rollout status` e confere que o hook já não está lá. A conferência é esta:

```text
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].lifecycle}{"|"}{.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
|15
```

A saída é `|15`: antes da barra, o conteúdo de `lifecycle`, que está **vazio**; depois, o `terminationGracePeriodSeconds`, 15. (O `|` é escrito pelo próprio comando entre os dois campos, para poder ver o vazio.) Sem o hook, o Pod recebe `TERM` no mesmo instante em que o seu desligamento começa.

Com esse template, a atualização é repetida três vezes, indo e voltando entre as duas versões, para que cada rodada troque de imagem e haja uma substituição de verdade:

```text
# resultado del sondeo (B, ronda 1, sin preStop, hacia 1.6.0):
      2  código 000  curl rc=7  versión -
      7  código 000  curl rc=28  versión -
     51  código 200  curl rc=0  versión 1.6.1
    403  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +7 +7 +9 +9 +9 +9 +30
peticiones=463 fallidas=9

# resultado del sondeo (B, ronda 2, sin preStop, hacia 1.6.1):
      1  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
     47  código 200  curl rc=0  versión 1.6.0
    465  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +5 +7 +7 +8 +9 +9 +10 +10 +16
peticiones=521 fallidas=9

# resultado del sondeo (B, ronda 3, sin preStop, hacia 1.6.0):
      3  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
    105  código 200  curl rc=0  versión 1.6.1
    469  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +5 +7 +7 +8 +8 +9 +10 +10 +10
peticiones=585 fallidas=11
```

Há linhas novas, e cada uma conta algo diferente:

- `código 000  curl rc=7`: o código HTTP `000` é o que o `curl` imprime quando **não recebeu resposta HTTP**, e `rc=7` é a sua própria saída: “Failed to connect to host”. Alguém respondeu “aqui não há ninguém” à conexão. É a assinatura que se esperaria da condição de corrida de 9.9.2: uma requisição chegou, pelo Service, a uma réplica que já havia fechado a sua porta.
- `código 000  curl rc=28`: `rc=28` é “Operation timeout”: passaram os 2 segundos do `-m 2` sem resposta. Ninguém disse “não”; ninguém disse nada. Acontece quando o pacote chega a um endereço que já não existe (o Pod já desapareceu e a rede ainda o aponta) ou quando alguém demora demais para responder. O tempo esgotado, então, tem várias causas possíveis, e uma delas é a mesma condição de corrida.
- A linha **“segundos (desde el inicio) de las primeras fallas”** dá o segundo, contado desde que o polling começou, em que *terminou* cada requisição que falhou; uma falha `curl 28` foi enviada uns 2 segundos antes. Nas três rodadas sem pausa, as falhas caem entre `+5` e `+10` segundos, salvo uma ou duas mais tardias. É o momento em que as réplicas antigas são desligadas: o `set image` foi enviado 3 segundos depois de lançar o polling.

A soma das três rodadas sem `preStop`: 463 + 521 + 585 = 1.569 requisições, das quais falharam 9 + 9 + 11 = 29. Seis foram `curl 7` (2, 1 e 3) e 23 foram `curl 28` (7, 8 e 8).

#### 9.9.7 Com a pausa de novo, mais três rodadas

A pasta, que traz o `preStop`, é aplicada outra vez, e a atualização é repetida mais três vezes:

```text
$ kubectl apply -k . | grep -E 'deployment|horizontal'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
horizontalpodautoscaler.autoscaling/revisor unchanged
```

```text
# resultado del sondeo (C, ronda 1, con preStop, hacia 1.6.1):
      4  código 000  curl rc=28  versión -
     57  código 200  curl rc=0  versión 1.6.0
    471  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +2 +2 +2 +2
peticiones=532 fallidas=4

# resultado del sondeo (C, ronda 2, con preStop, hacia 1.6.0):
     97  código 200  curl rc=0  versión 1.6.1
    515  código 200  curl rc=0  versión 1.6.0
peticiones=612 fallidas=0

# resultado del sondeo (C, ronda 3, con preStop, hacia 1.6.1):
      1  código 000  curl rc=28  versión -
     72  código 200  curl rc=0  versión 1.6.0
    360  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +25
peticiones=433 fallidas=1
```

#### 9.9.8 O que dizem as sete rodadas, e o que não dizem

Juntando todas as rodadas da execução:

| Variante | Rodadas | Requisições | Falhas | `curl 7` | `curl 28` |
|---|---|---|---|---|---|
| Polling base, sem tocar em nada | 1 | 172 | 0 | 0 | 0 |
| **Com** `preStop` (A e C1 a C3) | 4 | 2.049 | 5 | 0 | 5 |
| **Sem** `preStop` (B1 a B3) | 3 | 1.569 | 29 | 6 | 23 |

Com `preStop`, 5 falhas em 2.049 requisições (0,24 %; intervalo de 95 %, método de Wilson: 0,10 a 0,57 %). Sem ele, 29 em 1.569 (1,85 %; 1,29 a 2,64 %). Os intervalos não se sobrepõem, mas supõem requisições independentes, e aqui elas não são (quatro threads que compartilham o cliente, e as quatro falhas da rodada C1 são do mesmo instante); leia-os como uma indicação de tamanho, não como uma garantia. O que essas cifras permitem dizer, com cuidado:

1. **A conexão recusada só apareceu sem a pausa.** As seis conexões recusadas (`curl 7`) ocorreram nas rodadas sem `preStop`, e nenhuma nas quatro rodadas com ele. É o efeito que 9.9.2 prevê: sem pausa, uma réplica fecha a sua porta enquanto alguém ainda lhe manda requisições. Com a pausa ficaram cinco tempos esgotados (`curl 28`) que esta medição não permite atribuir nem ao ruído nem a uma condição de corrida residual: esse código tem as duas causas possíveis.
2. **As falhas se agrupam onde se espera.** Nas rodadas sem pausa, caem numa janela de uns cinco ou seis segundos, a que segue o `set image`. Nas rodadas com pausa, não há falhas nessa janela: as quatro da rodada C1 ocorreram no mesmo segundo, `+2`, isto é, quando o polling mal começava (o `set image` é enviado 3 segundos depois de lançá-lo), e a única da rodada C3 caiu em `+25`, já com a atualização em andamento; não registramos quando cada Pod foi desligado, então não podemos relacioná-la com nenhum momento. Que as quatro falhas de C1 sejam simultâneas aponta para uma partida lenta do cliente (quatro threads que começam ao mesmo tempo dentro de um Pod com um limite de `100m` de CPU numa máquina compartilhada e carregada), mas a medição não o demonstra: é uma hipótese, não uma conclusão.
3. **Zero não é o que se mediu.** A rodada A, a primeira, deu 0 em 472; as outras três rodadas com pausa deram 4, 0 e 1. Uma lição que dissesse “com `preStop` não se perde nenhuma requisição” teria escolhido a rodada A e teria mentido. O que a medição sustenta: a pausa reduziu as falhas da janela de atualização a um número pequeno que tampouco é zero, e as rodadas com pausa deram, em conjunto, 5 falhas em 2.049 requisições. Não sabemos quanto disso é ruído do cliente: o polling base, de 172 requisições sem falha, é curto demais para estimá-lo.
4. **Isto não é um teste estatístico.** São sete rodadas de 45 segundos, numa máquina compartilhada com muita carga, com um cliente que divide os núcleos com o cluster que mede. As rodadas não foram alternadas (primeiro a A, depois as três sem pausa e depois as três com pausa), então a variante e o momento andam juntos, e a carga da máquina mudou durante o trabalho; para separar os dois efeitos seria preciso alternar com e sem pausa. As cifras servem para comparar variantes dentro desta execução; não para prometer uma porcentagem no cluster de quem acompanha. O que é transferível é o método: contar todas as requisições, distinguir como falham, repetir e não acreditar numa só rodada.

A pausa de 5 segundos, então, fecha a parte da condição de corrida que se pode fechar com uma pausa. Não é uma garantia: a própria documentação dos hooks diz que a sua entrega é “pelo menos uma vez” e que não há mais promessa. E há uma fonte de falhas que nenhuma pausa toca: a queda de um nó, que vem em 9.12.

### 9.10 O histórico e o retorno à versão anterior

#### 9.10.1 Um ReplicaSet por versão

Cada vez que o template do Deployment muda, o Deployment cria um `ReplicaSet` novo, e o antigo fica ali, com zero réplicas, em vez de ser apagado. Cada um desses ReplicaSets guarda o template de uma versão: a sua imagem, os seus probes, o seu `preStop`. É o que torna possível voltar atrás, e a documentação diz isso sem rodeios: “a configuração de cada revisão do Deployment é guardada nos seus ReplicaSets; portanto, uma vez que um ReplicaSet antigo é apagado, perde-se a capacidade de voltar a essa revisão”. Quantos são conservados é decidido por `.spec.revisionHistoryLimit`, que vale 10 por padrão.

Dá para pôr um comentário em cada revisão com uma anotação, `kubernetes.io/change-cause`, que o `rollout history` mostra numa coluna. A documentação diz que ela pode ser colocada com `kubectl annotate`, editando o manifesto ou com ferramentas que a coloquem sozinhas, e que a flag `--record`, que antes a preenchia, está obsoleta e será retirada. Ela é aplicada à revisão atual:

```text
$ kubectl annotate deployment/revisor -n revisor kubernetes.io/change-cause='ronda de pruebas de la Leccion 9' --overwrite
deployment.apps/revisor annotated

$ kubectl rollout history deployment/revisor -n revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
3         <none>
8         <none>
9         <none>
12        <none>
13        ronda de pruebas de la Leccion 9
```

A coluna `CHANGE-CAUSE` só tem texto na revisão atual, porque a anotação é copiada para uma revisão quando essa revisão é criada, e as demais já existiam. Os números de revisão não precisam ser consecutivos: aqui são 1, 3, 8, 9, 12 e 13. Cada vez que o template volta a ser idêntico ao de um ReplicaSet que já existia, o Deployment **reutiliza** esse ReplicaSet e lhe dá o número de revisão mais novo, de modo que as revisões intermediárias que passaram a ser “a mesma” desaparecem da lista. Os ReplicaSets confirmam a conta:

```text
$ kubectl get replicasets -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-574b5b6c4c   0         0         0       16m
revisor-5978745747   0         0         0       4m33s
revisor-5cc67d8975   2         2         2       5m33s
revisor-67b97d67c9   0         0         0       18m
revisor-767bdf965b   0         0         0       16m
revisor-7f759cd976   0         0         0       4m51s
(imagen actual: curso-docker-revisor:1.6.1)
```

Seis ReplicaSets, um para cada template diferente que passou pelo Deployment nesta execução: com `preStop` e sem ele, com uma versão ou com outra, com `nodeTaintsPolicy` e sem ele. Só um tem réplicas. Os outros cinco são o histórico.

#### 9.10.2 `rollout undo`

O `rollout undo` leva o Deployment à revisão anterior. Não executa nada especial: escreve no Deployment o template do ReplicaSet anterior, e o Deployment faz a mesma substituição gradual de sempre, mas ao contrário.

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back
```

O aviso (`Warning: resource deployments/revisor was previously managed with 'kubectl apply'…`) merece ser lido completo. Diz que o retorno à versão anterior **não atualiza** a anotação `last-applied-configuration`, a que guarda o último estado aplicado com `kubectl apply`, e que isso “pode causar um comportamento inesperado em futuros `kubectl apply`”. Traduzindo: o arquivo diz uma coisa, o cluster voltou a outra, e o próximo `apply -k .` fará a sua própria comparação e pode desfazer o retorno. O `rollout undo` é uma ferramenta para apagar um incêndio; o conserto de verdade é mudar o arquivo e aplicá-lo. A documentação do `kubectl` sugere isso com as mesmas palavras no fim do aviso: “considere usar `kubectl apply` com a sua configuração anterior”.

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

#### 9.10.3 Quando termina de verdade

O `rollout status` disse `successfully rolled out`. Já não resta nada da versão que foi retirada? Olha-se com a coluna necessária, a que o script leva em todas as suas listagens de Pods:

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-5cc67d8975-qbzsl   curso-docker-revisor:1.6.1   curso-k8s-l9-worker2   2026-10-21T23:32:40Z
revisor-5cc67d8975-ttszb   curso-docker-revisor:1.6.1   curso-k8s-l9-worker    2026-10-21T23:32:37Z
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
```

Olhe a coluna `BORRANDOSE`: é o campo `deletionTimestamp` do Pod, a hora (em UTC) em que o cluster lhe ordenou terminar. Os Pods de `1.6.1` a têm: estão terminando, continuam na sua pausa de `preStop` (o prazo de 15 segundos ainda não venceu), e **continuam respondendo**. Os Pods de `1.6.0` não a têm: são os vivos de agora. O `rollout status` terminou porque o Deployment já cumpre o que lhe foi pedido (as réplicas desejadas da versão boa estão prontas e as ruins já foram marcadas para terminar), não porque o último Pod ruim tenha acabado de morrer. As requisições mostram isso:

```text
$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}
```

Quatro das seis respostas dizem `1.6.1`: **a versão que acabou de ser retirada**. Só duas dizem `1.6.0`, a que ficou. Se alguém tivesse concluído naquele momento que o `undo` não funcionou, teria se enganado. É a mesma condição de corrida de 9.9.2, vista a partir do retorno à versão anterior: a retirada dos destinos demora um pouco para chegar a todos. Doze segundos depois, com a pausa vencida:

```text
(espera de 12 s: que termine el preStop de los Pods viejos)

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>

$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}
```

Já não resta nenhuma linha com `BORRANDOSE`, e as seis respostas dizem `1.6.0`. Um `rollout undo` que parece não ter funcionado porque uma requisição respondeu a versão antiga costuma ser isto: concluiu-se cedo demais. A regra: antes de decidir que o retorno falhou, olhe o `deletionTimestamp` e espere que o prazo se esgote.

Para ver o que uma revisão guardava, o `rollout history` aceita `--revision=N` e mostra o template completo dessa versão, a imagem inclusive. O script pede a primeira:

```text
$ kubectl rollout history deployment/revisor -n revisor --revision=1 | head -14
deployment.apps/revisor with revision #1
Pod Template:
  Labels:	app=revisor
	pod-template-hash=67b97d67c9
  Service Account:	revisor
  Containers:
   revisor:
    Image:	curso-docker-revisor:1.6.0
    Port:	8080/TCP (http)
    Host Port:	0/TCP (http)
    Limits:
      cpu:	200m
      memory:	64Mi
    Requests:
```

É o template com que o Deployment nasceu na pasta da Lição 8: imagem `1.6.0`, sem `preStop`. (A saída é cortada em 14 linhas com `head` para que caiba; o resto são os `Requests`, os probes e os volumes.) Para voltar a ela seria preciso dizer `kubectl rollout undo deployment/revisor --to-revision=1`, a forma que a documentação traz.

E para fechar o círculo com a disciplina do hábito de segurança, o script aplica a pasta outra vez, de modo que o cluster e os arquivos fiquem iguais:

```text
$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
```

`unchanged`: o template que o `undo` deixou é idêntico ao do arquivo, e o `apply` não tem nada a fazer.

#### 9.10.4 O erro: uma imagem que não existe

Uma das razões mais comuns para um retorno à versão anterior é uma atualização que deu errado, e nem sempre por um defeito do programa, mas por um descuido de escrita: a tag da imagem está escrita errada, ou aponta para uma versão que ninguém publicou. Ele é provocado de propósito, com um script à parte que monta o seu próprio cluster mínimo: **`fig09_02.imagen-rota.sh`**, um **programa** que falha de propósito. Cria o `curso-k8s-l9` só com o que é necessário (o `revisor` e o de teste, sem MetalLB nem Envoy Gateway, que não intervêm), coloca duas réplicas, lança o polling de 9.9.4 e troca a imagem para `curso-docker-revisor:9.9.9`, uma tag que não existe. A sua saída é `fig09_02.imagen-rota.salida.txt`. Roda-se assim, a partir da pasta da lição:

```bash
./fig09_02.imagen-rota.sh > fig09_02.imagen-rota.salida.txt 2>&1
```

Não leva `ctx &&` na frente porque cria o seu próprio cluster e o contexto ainda não existe; traz as suas próprias guardas (kubeconfig temporário, contexto conferido antes de cada `kubectl`, remoção do cluster ao sair). Se já houver um `curso-k8s-l9` vivo, o script para: não toca no existente. Leva uns quatro minutos. O comando que provoca o erro é este, e sai bem:

```text
$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:9.9.9
deployment.apps/revisor image updated
```

`image updated`, sem reclamações: o `kube-apiserver` não sabe se a imagem existe. É a mesma situação do `selector` mal escrito da Lição 3: um nome válido que aponta para nada. O que segue se lê em ordem, como qualquer falha.

**Primeiro, `rollout status`.**

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]
(espera de 10 s: que el kubelet registre el fallo de descarga)
```

Fica em “1 out of 2 new replicas have been updated” e, ao se esgotar o prazo de 40 segundos que lhe foi dado, sai com `error: timed out waiting for the condition` e código 1. Repare que ele **não diz o que está errado**: só diz que não termina. O `rollout status` espera, e a causa tem de ser buscada em outra parte. Sem um `--timeout`, esperaria até que o Deployment declare que não progride: o campo `.spec.progressDeadlineSeconds`, que vale 600 segundos por padrão, depois dos quais o Deployment acrescenta uma condição `Progressing` em `False` com a razão `ProgressDeadlineExceeded` ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). A documentação adverte que o Kubernetes **não faz nada** com um Deployment travado além de reportá-lo: não o desfaz sozinho.

**Segundo, os Pods.**

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS         RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-6586779dc4-96dfn   0/1     ErrImagePull   0          50s   10.244.2.5   curso-k8s-l9-worker    <none>           <none>
revisor-85f8668b64-2tjx4   1/1     Running        0          60s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running        0          60s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>
```

Três Pods, não dois. Os dois antigos (`85f8668b64`) continuam `1/1 Running`. O novo (`6586779dc4`) está em `0/1 ErrImagePull`: o nó tentou baixar a imagem, não a encontrou, e não há contêiner para iniciar. É o mesmo estado da Lição 2, com a mesma saída, e se lê igual: o passo seguinte é o `describe`.

**Terceiro, os eventos do Pod novo.**

```text
$ kubectl describe pod revisor-6586779dc4-96dfn -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  50s                default-scheduler  Successfully assigned revisor/revisor-6586779dc4-96dfn to curso-k8s-l9-worker
  Normal   Pulling    13s (x3 over 50s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:9.9.9": failed to pull and unpack image "docker.io/library/curso-docker-revisor:9.9.9": failed to resolve reference "docker.io/library/curso-docker-revisor:9.9.9": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
  Normal   BackOff    2s (x3 over 49s)   kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     2s (x3 over 49s)   kubelet            spec.containers{revisor}: Error: ImagePullBackOff
```

O evento `Failed to pull image "curso-docker-revisor:9.9.9"` diz, com mais texto do que cabe na página, que não conseguiu resolver `docker.io/library/curso-docker-revisor:9.9.9`: o nó buscou a tag no Docker Hub, onde ela não existe, porque a imagem do curso vive só na máquina de quem acompanha. Depois `ErrImagePull`, `BackOff` e `ImagePullBackOff`: o `kubelet` tenta de novo com esperas cada vez mais longas. `(x3 over 50s)` diz quantas vezes tentou.

**Quarto, o que diz o Deployment.**

```text
$ kubectl get deployment revisor -n revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   2/2     1            2           60s
```

`READY 2/2`, `UP-TO-DATE 1`, `AVAILABLE 2`. “Prontas: 2 de 2; atualizadas: 1; disponíveis: 2”. O Deployment fez exatamente o que `maxSurge: 1` e `maxUnavailable: 0` lhe pediam: criou **uma** réplica nova, esperou que estivesse pronta para poder retirar uma antiga, e como ela nunca esteve, não retirou nenhuma. As duas antigas continuam atendendo.

**E o polling, que rodou durante todo o travamento:**

```text
# resultado del sondeo (durante toda la actualización rota):
    811  código 200  curl rc=0  versión 1.6.0
peticiones=811 fallidas=0
```

Nesta rodada nenhuma das 811 requisições falhou: todas foram respondidas pela versão `1.6.0`, a antiga, porque nenhuma réplica antiga foi retirada. É uma única rodada, mas o que torna o resultado possível é mecânico, não estatístico: com `maxUnavailable: 0`, o Deployment não retira uma réplica antiga sem ter pronta uma nova, e a nova nunca chegou a ficar pronta. Esta é a utilidade concreta de `maxUnavailable: 0`: uma atualização quebrada fica travada *sem tirar o que funciona*. Atenção ao que não se mede: como nunca se desligou uma réplica antiga, também não se prova nada sobre a condição de corrida do desligamento. Com o valor padrão de 25 %, um Deployment de quatro réplicas poderia retirar uma antes de ter a nova pronta, e um tropeço assim poderia ser notado.

**A correção** é a causa, e a ferramenta é a de 9.10.2:

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-85f8668b64-2tjx4   1/1     Running   0          65s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running   0          65s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curso-docker-revisor:1.6.0
```

O `undo` leva o template ao anterior, o Pod que não iniciava desaparece, e a imagem volta a `curso-docker-revisor:1.6.0`. (Aqui não houve nenhum Pod da versão ruim que continuasse respondendo, como em 9.10.3: ela nunca chegou a ficar pronta.) Num projeto real, a correção definitiva é arrumar a tag no arquivo e aplicá-lo; o `undo` é o primeiro socorro.

### 9.11 Manutenção de um nó: o orçamento de interrupções

#### 9.11.1 Duas classes de interrupção

Nem tudo o que tira um Pod de um serviço é igual. A documentação do Kubernetes separa as **interrupções involuntárias**, que são “casos inevitáveis” como “uma falha de hardware da máquina que sustenta o nó”, das **voluntárias**, que são as ações de quem opera o sistema: a pessoa dona da aplicação, ou o administrador do cluster, que entre outras coisas pode “drenar um nó para repará-lo ou atualizá-lo” ([Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)). A diferença importa porque sobre as voluntárias se pode **negociar**: o cluster deixa dizer quanto se está disposto a perder. Sobre as involuntárias não: ninguém pergunta a um disco se ele pode falhar.

A ferramenta da negociação é o **PodDisruptionBudget** (PDB), o segundo objeto do `escalado.yaml`. A documentação define as suas duas formas: `minAvailable`, o número de Pods que precisam continuar disponíveis depois de uma remoção (eviction), e `maxUnavailable`, o número que pode ficar indisponível; declara-se uma ou outra, não as duas. O do `revisor` diz `minAvailable: 1`: com duas réplicas, uma pode sair, e a outra tem de ficar. Lê-se o seu estado:

```text
$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     17m
```

`ALLOWED DISRUPTIONS 1` é a conta que o cluster leva neste instante: duas réplicas saudáveis, menos uma que tem de continuar de pé, deixa uma que se pode perder. Se uma das duas deixa de estar saudável, esse número cai para 0, e a remoção seguinte é rejeitada.

#### 9.11.2 Como se drena um nó

`kubectl drain` é a ordem de “este nó vai para manutenção”. Faz duas coisas, nesta ordem: marca-o como não agendável (`cordon`: nenhum Pod novo chega) e remove (evict) um por um os Pods que rodam nele. A documentação ([Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)) explica que uma remoção segura permite que os contêineres terminem com ordem e “respeita os PodDisruptionBudgets que tenham sido especificados”. A disciplina por trás, segundo a página de interrupções: o `kubectl` pede cada remoção pela API de eviction; esse pedido pode ser rejeitado temporariamente, e a ferramenta tenta de novo os que falham até que todos os Pods do nó terminem ou se esgote um prazo que se configura (`--timeout`). O comando do script leva duas flags. `--ignore-daemonsets`: a documentação diz que é necessária quando há Pods de um DaemonSet (como os `speaker` do MetalLB), que são deixados onde estão e retirados quando o nó sai do cluster. `--delete-emptydir-data`: aceita perder os dados dos volumes `emptyDir`, como o `/datos` do `revisor`, que de qualquer modo morre com o Pod.

#### 9.11.3 O erro: um orçamento sem margem

Ele é provocado com `fig09_01.pdb-estricto.yaml`, um **programa** que falha de propósito: o mesmo PDB, com `minAvailable: 2`.

```yaml
# fig09_01.pdb-estricto.yaml — FALLA A PROPÓSITO: un PodDisruptionBudget que no deja
# perder NI UNA réplica (minAvailable: 2 con solo 2 réplicas). Mientras exista,
# «kubectl drain» no puede desalojar ningún Pod del revisor y se queda reintentando.
# Se deshace con: kubectl apply -k .   (escalado.yaml trae el PDB bueno)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: revisor
```

Ele é aplicado **no namespace do `revisor`**, com `-n revisor`: o arquivo não declara namespace, e um `apply -f` sem `-n` cria o objeto onde o contexto apontar (o namespace `default`), que não protege ninguém. É um erro fácil de cometer, e foi cometido ao preparar esta lição: esquecer o `-n revisor`. O cluster não reclama: a mensagem foi `poddisruptionbudget.policy/revisor created` em vez de `configured`, o orçamento bom do namespace `revisor` ficou intacto (`ALLOWED DISRUPTIONS 1`) e o `drain` passou sem obstáculos, como se o experimento não existisse. A pista estava na palavra: `created` em vez de `configured`. Lê-se a mensagem do `apply` e confere-se com `get pdb -n revisor`.

```text
$ kubectl apply -n revisor -f fig09_01.pdb-estricto.yaml
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   2               N/A               0                     17m
(el nodo que se va a vaciar: curso-k8s-l9-worker2)
```

`configured`: o objeto já existia e agora diz outra coisa. `MIN AVAILABLE 2` e, a cifra que importa, `ALLOWED DISRUPTIONS 0`. Com duas réplicas e a obrigação de conservar duas, não há nenhuma que se possa perder. Agora tenta-se drenar um nó, com um prazo curto para que o script não fique esperando:

```text
$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=30s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/prueba-6899c74865-cgzkw
evicting pod metallb-system/controller-76f4cf76b7-m9mlh
evicting pod revisor/revisor-767bdf965b-58sd9
evicting pod envoy-gateway-system/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/controller-76f4cf76b7-m9mlh evicted
pod/prueba-6899c74865-cgzkw evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
There are pending pods in node "curso-k8s-l9-worker2" when an error occurred: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
pod/revisor-767bdf965b-58sd9
error: unable to drain node "curso-k8s-l9-worker2" due to error: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s, continuing command...
There are pending nodes to be drained:
 curso-k8s-l9-worker2
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
[código de salida: 1]
```

Lê-se como um roteiro de teatro. O nó é isolado (`cordoned`). São pedidas remoções dos Pods que vivem ali, e saem os que não estão protegidos: `prueba`, o `controller` do MetalLB e o Pod do Envoy que atende o ponto de entrada terminam (`evicted`). E então aparece, uma e outra vez, a cada 5 segundos:

`error when evicting pods/"revisor-…" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.`

“Não é possível remover o Pod porque violaria o orçamento de interrupções”. O cluster não se enganou: fez exatamente o que lhe foi pedido. Aos 30 segundos o prazo do `drain` se esgota (`global timeout reached: 30s`) e o comando sai com código 1. Observe em que estado ficou o nó:

```text
$ kubectl get nodes
NAME                         STATUS                     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready                      control-plane   26m   v1.37.0
curso-k8s-l9-worker          Ready                      <none>          26m   v1.37.0
curso-k8s-l9-worker2         Ready,SchedulingDisabled   <none>          26m   v1.37.0
```

`Ready,SchedulingDisabled`: continua saudável, mas **isolado**. Um `drain` interrompido deixa o nó nesse estado até que alguém o devolva com `uncordon`; se não, nenhum Pod novo cai ali, e é uma das maneiras de ficar sem capacidade sem que nada esteja quebrado. O script o devolve:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
```

A correção é aplicar de novo a pasta, que traz o PDB bom (`minAvailable: 1`), e repetir o `drain`. Agora `ALLOWED DISRUPTIONS` volta a 1 e a remoção do `revisor` passa:

```text
# --- La corrección: el PDB de la carpeta ---

$ kubectl apply -k . | grep -E 'poddisruption'
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     18m

$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=120s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/revisor-767bdf965b-58sd9
pod/revisor-767bdf965b-58sd9 evicted
node/curso-k8s-l9-worker2 drained
```

`evicted` na primeira tentativa, sem repetições nem erros. Mas olhe onde ficaram as réplicas:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          6s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          109s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

**As duas réplicas ficaram no mesmo nó**, `curso-k8s-l9-worker`. A remoção do `revisor` passou (o PDB permitiu perder uma), mas a réplica nova nasceu no único nó que podia recebê-la, e agora as duas vivem juntas: a perda desse nó levaria o serviço inteiro. O mais provável é que isso se explique por `Honor`: um nó isolado leva o taint `node.kubernetes.io/unschedulable`, e com `nodeTaintsPolicy: Honor` os nós com taint (para os quais o Pod não tem tolerância) saem da conta da distribuição. Enquanto o `worker2` esteve isolado, o único domínio era o `worker`, com assimetria 0, e a distribuição permitiu ambas as réplicas ali. A restrição foi cumprida; não havia outro lugar.

#### 9.11.4 Recuperar a distribuição

O nó é devolvido ao serviço e espera-se para ver se o cluster cuida disso sozinho:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
(espera de 30 s: ¿vuelve el reparto por sí solo?)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          37s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          2m20s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

Não. As duas réplicas continuam juntas: nada as moveu. É exatamente a limitação de 9.4.4: a restrição de distribuição é avaliada **ao agendar um Pod**, não depois, e a documentação diz que não há garantia de que continue sendo cumprida quando Pods são retirados, e recomenda ferramentas como o *Descheduler* para rebalancear. Sem instalar nada, o remédio é provocar um agendamento novo, e o `kubectl rollout restart` o faz: substitui as réplicas com o mesmo procedimento gradual de uma atualização, e cada Pod novo é agendado com a restrição em vigor.

```text
$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          12s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          10s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

De novo uma réplica em cada nó de trabalho. A distribuição se mantém com um hábito, não com uma configuração: depois de uma manutenção, olha-se `-o wide`.

### 9.12 Um nó que cai

Até aqui tudo foi *planejado*: uma atualização que a gente lança, uma manutenção que a gente pede. Falta o outro: a máquina que se desliga sem avisar. É a terceira pergunta do diretor. Responde-se desligando um dos nós de trabalho de propósito, medindo, e perguntando ao cluster quando ele ficou sabendo.

#### 9.12.1 O que o cluster sabe, e quando

Um nó caído não manda aviso: deixa de mandar *heartbeats*. A documentação de “Node Status” descreve duas formas de heartbeat: as atualizações do `.status` do nó e uns objetos `Lease` dentro do namespace `kube-node-lease`, um por nó; o `kubelet` renova o seu a cada 10 segundos por padrão ([Node Status](https://kubernetes.io/docs/reference/node/node-status/)). Quando os heartbeats param de chegar, o controlador de nós espera um prazo, `node-monitor-grace-period`, antes de declarar qualquer coisa. A condição `Ready` do nó passa a `Unknown` se o controlador de nós “não teve notícias do nó nos últimos `node-monitor-grace-period` (por padrão, **50 segundos**)”. É o prazo de detecção, e é o centro da seção.

Enquanto esses 50 segundos correm, o plano de controle acredita que o nó está bem. Os seus Pods constam como `Running` e `Ready`, os seus endereços continuam nos `EndpointSlice`, e os Services continuam repartindo requisições para eles. Quando o prazo vence, acontecem duas coisas distintas:

1. O nó passa a `NotReady` (`Unknown`), e os Pods que viviam ali deixam de contar como prontos; os seus endereços são marcados `ready: false` nos `EndpointSlice`, e o Service deixa de usá-los. **Aqui termina a janela de falha para o tráfego.**
2. O nó recebe o taint `node.kubernetes.io/unreachable` com efeito `NoExecute`. Os Pods que vivem ali têm, de fábrica, uma tolerância a esse taint de **300 segundos**: a documentação de “Taints and Tolerations” diz que o Kubernetes adiciona sozinho as tolerâncias de `not-ready` e `unreachable` com `tolerationSeconds=300`, e que por isso os Pods “permanecem vinculados aos nós por 5 minutos depois que um desses problemas é detectado”. Passado esse prazo, os Pods são removidos (evicted) e o ReplicaSet cria substitutos em outro nó. **Aqui termina a janela de capacidade**, e demora muito mais que a de falha.

Convém separar as duas janelas porque elas se confundem. A de **falha** (requisições que se perdem) dura desde que o nó cai até que o cluster fique sabendo: uns 50 segundos. A de **capacidade** (serviço com uma réplica a menos) dura 5 minutos a mais, até que os substitutos nasçam. Esta lição mede a primeira, que é a que os usuários sentem. A segunda não foi medida, porque o nó é religado antes que ela venza.

#### 9.12.2 O experimento

O script escolhe o nó que vai desligar com uma condição: tem de ser um nó que **tenha uma réplica** do `revisor` e que **não** seja onde vive o Pod `depurar`, que é de onde saem as requisições (se o nó do cliente fosse desligado, a medição morreria com ele). Com duas réplicas distribuídas, um dos dois nós de trabalho cumpre. Depois lança **dois** pollings ao mesmo tempo, com uma requisição a cada 2 segundos e uma só thread, durante 100 segundos:

- o primeiro, tal como está: `./sondeo.sh 100 2 1`;
- o segundo, com novas tentativas do cliente: `./sondeo.sh 100 2 1 --retry 3 --retry-all-errors`.

`--retry 3` pede ao `curl` que tente de novo até 3 vezes uma requisição que falhou, e `--retry-all-errors` estende “falhou” a qualquer erro, incluindo os tempos esgotados; o manual do `curl` descreve a espera entre as novas tentativas: primeiro um segundo, e depois “dobra o tempo de espera” a cada uma. O manual chama o `--retry-all-errors` de a “marreta” (sledgehammer) das novas tentativas e desaconselha usá-lo por padrão; aqui é um experimento controlado contra um serviço que sabemos ser seguro repetir (`GET /salud`). Com uma requisição idempotente (que pode ser repetida sem efeitos) as novas tentativas são inócuas; com uma que não seja, seriam um risco.

Dez segundos depois de lançar os pollings, `docker stop` para o contêiner do nó, que é o mais parecido que o kind tem de “a máquina caiu”: o `kubelet` e tudo o que roda dentro deixam de existir de uma vez. A lição espera 25 segundos e pergunta duas coisas: como o cluster vê o nó, e o que dizem os `EndpointSlice` dos endereços do `revisor`.

```text
$ ./sondeo.sh 100 2 1 &                                     # sin reintentos, empieza a las 17:34:53
$ ./sondeo.sh 100 2 1 --retry 3 --retry-all-errors &       # con reintentos
(pausa de 10 s: ambos sondeos ya corren)

$ docker stop curso-k8s-l9-worker
curso-k8s-l9-worker
(nodo apagado a las 17:35:04)
(espera de 25 s: el nodo ya no contesta, pero el clúster todavía no lo sabe)
[+ 25s desde docker stop] curso-k8s-l9-worker Ready
```

Aos 25 segundos de desligado, o nó ainda diz `Ready`. O cluster não sabe de nada. E a prova de que continua sem saber está nos destinos:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=true nodo=curso-k8s-l9-worker
(el nodo pasó a NotReady a los 57 s de docker stop)
```

Os dois destinos do `revisor` constam `ready=true`, **incluindo o que vive no nó desligado** (`nodo=curso-k8s-l9-worker`). Qualquer requisição que o Service reparta para esse endereço vai a um Pod que já não existe. Essa é a causa das falhas, escrita numa linha.

O script consulta a cada 3 segundos o estado do nó até vê-lo `NotReady`, e então pergunta de novo:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=false nodo=curso-k8s-l9-worker
```

O nó passou a `NotReady` aos 57 segundos de desligado (o prazo da documentação é de 50; o resto soma até 5 segundos do ciclo do controlador, `node-monitor-period`, e 3 da consulta do script; além disso, o último heartbeat do nó pode ter sido anterior ao desligamento). E agora o destino do nó caído consta `ready=false`: o cluster deixou de repartir tráfego para ele. Esse é o momento em que acaba a janela de falha.

#### 9.12.3 O que os pollings mediram

```text
# resultado SIN reintentos (los segundos cuentan desde el inicio del sondeo; docker stop fue en +10):
      7  código 000  curl rc=28  versión -
     35  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +21 +25 +29 +38 +42 +60 +64
peticiones=42 fallidas=7

# resultado CON reintentos de curl:
      1  código 000  curl rc=28  versión -
     31  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +37
peticiones=32 fallidas=1
```

Um esclarecimento sobre o cabeçalho: o script anota “+10”, que é a pausa que programou antes de desligar o nó. A hora impressa diz que o nó ficou desligado 11 segundos depois de iniciar o polling, porque o `docker stop` demorou cerca de um segundo. Os cálculos que seguem usam 11.

O polling **sem novas tentativas** fez 42 requisições em 100 segundos, não as 50 que caberiam num ritmo de uma a cada 2 segundos, porque cada requisição que falha ocupa os 2 segundos completos do seu tempo de espera além da pausa. Falharam 7, todas com `curl 28` (tempo esgotado, não conexão recusada: o destino já não existia). Os segundos das falhas, contados desde o início do polling, são `+21 +25 +29 +38 +42 +60 +64`. Como o `docker stop` foi dado no segundo 11 do polling, subtraindo se obtém quanto cada uma demorou depois do desligamento: de 10 a 53 segundos. A última falha, aos 53 segundos do desligamento, cai logo antes da observação de `NotReady` aos 57: as sete falhas caíram entre 10 e 53 segundos depois do desligamento (medido ao terminar cada requisição). Que não se tenham visto mais não prova que o Service já tivesse deixado de usar o destino morto: com uma requisição a cada 2 segundos e metade delas caindo, segundo o modelo, na réplica viva, algumas seguidas podem acertar sem que nada tenha mudado. O que foi de fato medido é que o destino passou a `ready=false` quando o nó constou `NotReady`, aos 57 segundos.

Isso dá 7 falhas em 42, 17 %. Essa cifra mistura a janela de falha com o resto dos 100 segundos do polling, então não diz “o serviço falha uma vez em cada seis”: diz o que aconteceu neste experimento. O que explica as falhas é que, durante a janela (até 57 segundos, até que o destino passasse a `ready=false`), **um dos dois destinos do Service estava morto**, e o Service reparte entre os seus destinos sem saber qual está morto, então uma parte das requisições desse período ia parar na réplica que já não existia. Com duas réplicas e um nó morto, essa parte seria de cerca da metade; com quatro réplicas distribuídas, seria de cerca de um quarto; com dez, de um décimo. Essa proporção (uma réplica em N) é um modelo, não uma medição desta execução: o medido é 7 em 42, mas é o que explica por que “mais réplicas distribuídas” encurta o dano sem encurtar o tempo.

O polling **com novas tentativas** fez 32 requisições e foi mais lento (cada nova tentativa espera 1, 2 e 4 segundos antes de tentar outra vez). Falhou uma, aos 37 segundos, em 32: uma falha contra sete do outro polling, em troca de que algumas respostas demorassem mais. É uma única rodada, de tamanho pequeno e com menos requisições que a outra: sugere que as novas tentativas ajudam, mas não basta para prometer quantas requisições são recuperadas. É a segunda alavanca: **novas tentativas no cliente**. Funcionam porque na vez seguinte em que o `curl` pergunta, o Service pode escolher a réplica viva, e não funcionam se o destino for o mesmo (por exemplo, com uma única réplica).

Depois, o estado do cluster no momento de religar o nó:

```text
$ kubectl get nodes
NAME                         STATUS     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready      control-plane   29m   v1.37.0
curso-k8s-l9-worker          NotReady   <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready      <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          114s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          112s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

Com o nó `NotReady`, os dois Pods do `revisor` continuam constando `Running`, incluindo o do nó desligado: o cluster ainda não os remove, porque a tolerância de 300 segundos não venceu. E não os removerá: o nó é religado.

```text
$ docker start curso-k8s-l9-worker
curso-k8s-l9-worker

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready    control-plane   29m   v1.37.0
curso-k8s-l9-worker          Ready    <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready    <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS      AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0             2m16s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   1 (21s ago)   2m14s   10.244.1.4    curso-k8s-l9-worker    <none>           <none>
```

O nó volta a `Ready`, e o Pod que vivia nele continua ali: o contêiner foi reiniciado (`RESTARTS 1`), não foi criado outro Pod, e mudou de endereço de rede (`10.244.1.4` em vez de `10.244.1.33`), mas é o mesmo Pod. Nesta execução o nó voltou muito antes dos 300 segundos e os seus Pods ficaram.

#### 9.12.4 O que encurta a janela e o que não encurta

| Alavanca | Encurta? | Por quê |
|---|---|---|
| **Mais réplicas, distribuídas entre nós** | encurta o *dano*, não o tempo | com N réplicas distribuídas, o modelo da distribuição espera uma em cada N na morta (cálculo, não medição) |
| **Novas tentativas no cliente** | sim, para requisições seguras de repetir | a segunda vez pode tocar numa réplica viva (medido acima) |
| **Baixar o `node-monitor-grace-period`** (no plano de controle) | sim, em troca de falsos alarmes | o cluster declara caído um nó que apenas se atrasou |
| **Os probes de disponibilidade (readiness)** | não | quem os executa é o `kubelet` do próprio nó caído, que já não reporta nada |
| **`tolerationSeconds`** | não | decide quando os Pods são repostos, não quando deixam de receber tráfego |

As duas últimas linhas são as que mais se acredita e as que menos funcionam, e por isso o Exercício 4 as põe à prova. Um probe de disponibilidade (a `readinessProbe` da Lição 5) tira um Pod dos destinos do Service quando falha, mas quem faz a pergunta é o `kubelet` *daquele* nó. Se o nó inteiro está desligado, não há `kubelet` que pergunte nem que reporte; o cluster só pode esperar que o prazo de detecção se esgote. E `tolerationSeconds` é o prazo de graça antes de remover os Pods de um nó já declarado `unreachable`, ou seja, uma conta que começa *depois* da detecção: quanto mais curto, mais cedo os Pods são repostos, mas isso não tira antes os destinos mortos do Service.

Baixar o `node-monitor-grace-period` é a única alavanca que ataca o tempo, e custa falsos alarmes (não convém baixá-lo demais: tem de ser várias vezes maior que a frequência com que o `kubelet` reporta; confira a flag na referência do `kube-controller-manager` da versão em uso): um nó com um atraso de rede de dez segundos seria declarado caído, os seus Pods seriam marcados como não prontos e o Service deixaria de usá-los sem razão. É uma flag do `kube-controller-manager`, que no kind vive dentro do contêiner do nó de controle; não é algo que se mude com `kubectl`, e esta lição não a toca.

Respondido o diretor, com o que foi medido nesta execução: **com duas réplicas, sete de 42 requisições (17 %) se perderam durante a janela de um nó caído**, cuja última falha caiu 53 segundos depois do desligamento e que acabou quando o destino passou a `ready=false`, aos 57. Pela distribuição do Service, esperaríamos que cerca da metade das requisições dessa janela caísse na réplica morta (é um cálculo, não uma medição). Com novas tentativas no cliente houve uma falha em 32, mas uma única rodada não basta para prometer quantas são recuperadas. Quando o nó volta, o cluster se recompõe sozinho.

#### 9.12.5 Depois do experimento: o `<unknown>` do autoscaler

A última pergunta da execução é se tudo ficou como os arquivos dizem, e a resposta tem um detalhe que pertence a esta lição:

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           24m
deployment.apps/revisor   2/2     2            2           24m

NAME                                          REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          21m

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     21m
```

Com `sin diferencias con los archivos`, o cluster e a pasta coincidem: tudo o que foi feito com comandos (`set image`, `patch`, `scale`, `rollout undo`) foi desfeito ou aplicado de novo. E no HPA, `TARGETS` diz `cpu: <unknown>/50%`. É a mesma palavra que aparece às vezes nos primeiros segundos de 9.5.2, e convém saber interpretá-la, porque é a pergunta mais comum sobre autoscalers: **`<unknown>` significa “não sei quanto os Pods consomem”**, e tem três causas distintas:

1. **O `metrics-server` não responde.** É a causa de 9.2. Confere-se com `kubectl get apiservice v1beta1.metrics.k8s.io`: se disser `False`, é o medidor.
2. **Os Pods não têm `requests` de CPU.** Sem eles não há contra o que calcular a porcentagem, e a documentação diz que o autoscaler não fará nada com essa métrica. Confere-se com `kubectl describe pod`.
3. **Os Pods são novos e ainda não têm a sua primeira leitura.** Vê-se nos eventos do HPA (`kubectl describe hpa`) como `FailedGetResourceMetric … no metrics returned from resource metrics API`, o mesmo aviso que 9.6 mostrou nos primeiros segundos dos Pods novos, e some sozinho.

Neste final, a terceira é a candidata: a execução religou o nó desligado, esperou 20 segundos e capturou o estado; o Pod do `revisor` desse nó foi reiniciado um instante antes (`RESTARTS 1`) e ainda não tinha leitura. A medição não distingue essa causa da primeira, porque não se consultou o `APIService` naquele momento nem se conferiu em que nó rodava o `metrics-server` (se rodasse no nó desligado, seria a primeira); o que se pode dizer é como distingui-las. Se fosse a terceira, bastaria esperar alguns segundos; se não, o `<unknown>` permanece. O hábito: diante de um `<unknown>`, primeiro `get apiservice`, depois `describe pod` procurando os `requests`, e depois o relógio.

## O hábito de segurança da lição: limites ao escalonamento, e atualizações que não derrubam o serviço

A tabela de hábitos do curso atribui a esta lição uma frase com duas metades: **limites ao escalonamento** e **as atualizações não derrubam o serviço**. Conferem-se com o cluster à frente.

**Limites ao escalonamento.** Um autoscaler converte *carga* em *recursos*: mais requisições, mais réplicas, mais CPU e memória reservadas. Isso é justamente o que se quer diante de uma segunda-feira às 9h, e é justamente o que um atacante, ou um erro, pode aproveitar. Um cliente que manda requisições em laço (o Job `carga` da lição é um, em escala pequena) custa ao serviço cada vez mais réplicas. Sem teto, o limite é posto pelo cluster inteiro, e um serviço mal comportado deixa os demais sem recursos. Há três freios em camadas, do mais próximo ao mais geral:

1. **O teto do próprio autoscaler.** `maxReplicas: 6`. Com os `requests` da Lição 5, seis réplicas reservam `6 × 50m = 300m` de CPU e `6 × 32Mi = 192Mi` de memória, um número que se pode escrever e discutir, em vez de “o que houver”. Na execução desta lição o autoscaler não chegou a esse teto: a carga de um Job de `curl` em laço se conteve em quatro réplicas. O teto é um guarda-corpo; não se provou que ele detenha algo, e essa distinção conta.
2. **Quem pode gerar a carga.** A rede fechada da Lição 7 deixa passar para o `revisor` unicamente os Pods com o rótulo (label) `acceso-revisor: permitido` e os Envoy do ponto de entrada. O Job `carga` leva esse rótulo de propósito; sem ele, as suas requisições não chegariam e o autoscaler não veria nada. Quem controla o ponto de entrada controla quem pode aumentar a fatura de CPU.
3. **O orçamento do namespace.** Existem objetos (`ResourceQuota`, `LimitRange`) que colocam um limite **total** de CPU, memória e número de Pods a um namespace inteiro, de modo que um autoscaler mal configurado não possa passar disso, ainda que o seu próprio teto seja alto. A Lição 5 os nomeou e os deixou fora do curso; num cluster compartilhado são a camada que de fato protege os vizinhos.

Há ainda um hábito para quem escala com o `metrics-server`: a flag `--kubelet-insecure-tls` de 9.2 existe só neste laboratório. Convém escrevê-lo onde o veja quem herdar o arquivo (o comentário de `metrics-server/kustomization.yaml` o diz), porque uma flag de laboratório que se copia para outro cluster é uma brecha de segurança com aparência de configuração.

**As atualizações não derrubam o serviço.** O que foi feito para cumprir isso, e quanto cumpre, é o conteúdo de 9.9 e de 9.11:

| Peça | O que impede | Onde se mede |
|---|---|---|
| `maxUnavailable: 0` com `maxSurge: 1` | que haja menos réplicas que as desejadas durante a substituição | 9.9 |
| `preStop` com `sleep` | que cheguem requisições a uma réplica que já fechou a sua porta | 9.9 |
| `PodDisruptionBudget` | que uma manutenção voluntária tire mais réplicas do que o serviço aguenta | 9.11 |
| distribuição com `topologySpreadConstraints` | que uma só máquina concentre todas as réplicas | 9.4 e 9.11 |

Repare que a frase da tabela de hábitos diz “não derrubam”, não “não perdem nada”. O medido em 9.9 diz quanto se perde com e sem cada peça, e essa cifra, com a sua incerteza, é o que se entrega a quem pergunta. Uma promessa de “zero” que ninguém mediu é pior que uma cifra pequena que foi.

E mais uma disciplina: a lição atualiza com `kubectl set image` e `kubectl patch`, comandos *imperativos*, porque são o caminho curto para medir. Num projeto real, a mudança é escrita no arquivo, revisada e aplicada com `kubectl apply -k .`, para que o que roda no cluster e o que está no repositório sejam a mesma coisa. O final da execução confere isso com `kubectl diff -k .`: “sin diferencias con los archivos”.

## O que se faz errado

**Deixar `replicas` no Deployment que um HPA governa.** Cada `apply` devolve ao número o valor do arquivo e desfaz o que o autoscaler decidiu. Ele é retirado do manifesto.

**Um HPA sobre Pods sem `requests` de CPU.** A porcentagem é medida contra os `requests`; sem eles, o autoscaler não tem com que calcular e não faz nada.

**Copiar `--kubelet-insecure-tls` para um cluster real.** É a saída rápida para o `metrics-server` iniciar num laboratório. Num cluster com mais gente, a solução é que os certificados dos `kubelet` estejam assinados pela autoridade do cluster.

**Acreditar que o HPA reage a uma diferença de alguns pontos.** Dentro da tolerância de 10 % ele não faz nada. E ao reduzir, não usa o que vê hoje, mas o mais alto que recomendou na janela.

**Uma meta de CPU muito alta (90 %).** Quando o autoscaler reage, o serviço já está saturado, e as réplicas novas demoram a nascer.

**`ScheduleAnyway` quando o que se precisa é de uma garantia.** É uma preferência: o scheduler a quebra se não encontrar lugar melhor.

**Uma distribuição por topologia sem `nodeTaintsPolicy: Honor` num cluster com um nó de controle com taint.** Funciona com duas réplicas e deixa a terceira `Pending`.

**Acreditar que a distribuição se mantém sozinha.** Ela é aplicada ao agendar um Pod; uma manutenção pode deixar as réplicas juntas e nada as separa sem uma substituição.

**Atualizar sem uma pausa antes de desligar.** Uma réplica antiga fecha a sua porta enquanto a rede ainda lhe manda requisições.

**Concluir “sem falhas” a partir de um único polling curto.** Uma rodada sem falhas não demonstra que não as haja; com três rodadas de cada variante, o medido em 9.9 mostra que as falhas aparecem e desaparecem.

**Acreditar que `rollout status` significa “já não resta nada antigo respondendo”.** Termina quando o Deployment cumpre o que lhe foi pedido (as réplicas desejadas da versão nova estão prontas), não quando o último Pod antigo acabou o seu `preStop`. Olha-se o `deletionTimestamp`.

**Um `PodDisruptionBudget` que não deixa perder nenhuma réplica.** O `drain` fica tentando de novo e a manutenção não avança. O orçamento tem de deixar margem.

**Um PDB sem o seu namespace.** Um objeto com `-f` e sem `-n` é criado onde o contexto apontar, e um PDB no namespace errado não protege ninguém. Lê-se a mensagem `created` e confere-se com `get pdb -n revisor`.

**Contar com os probes para encurtar a queda de um nó.** Quem os executa é o `kubelet` do nó caído; eles não podem reportar nada.

**Confiar em que o cluster fica sabendo de imediato de uma queda.** Há uma janela de detecção, e as requisições que caem nela se perdem.

## Exercícios

Os três primeiros são feitos no cluster da lição, em ordem e com o estado em que ficou depois de 9.12. Antes de cada comando que muda algo, o `ctx` deve dar sucesso. O `correr.sh` percorre a lição, não os exercícios; as suas soluções citam o medido na lição ou o calculam, e dizem isso. **Antes** de rodar ou calcular cada um, escreva na [diário de bordo](bitacora.md) o que se acha que vai acontecer. O quarto se escreve com as próprias palavras.

### Exercício 1 — A fórmula, à mão

Com a meta de 50 %, `minReplicas: 2` e `maxReplicas: 6`, calcule o que o autoscaler faria em cada caso e diga se a tolerância o detém:

a) 2 réplicas com um uso médio de 63 %.
b) 3 réplicas com um uso médio de 46 %.
c) 4 réplicas com um uso médio de 90 %.
d) 6 réplicas com um uso médio de 20 %, um minuto depois de o uso ter baixado.

Depois compare (a) e (b) com a coluna `TARGETS` e os eventos de 9.6.

### Exercício 2 — Quem manda

Sem olhar 9.8, escreva que número de réplicas se acha que o Deployment terá 40 segundos depois de `kubectl scale deployment/revisor -n revisor --replicas=1`, e de que evento do HPA se vai perceber. Rode o comando e confira.

### Exercício 3 — O próprio polling

Rode `./sondeo.sh 45 0 4` enquanto se faz `kubectl set image` entre `1.6.0` e `1.6.1`, três vezes com o `preStop` da pasta. Anote por rodada as requisições, as falhas e o tipo de cada falha (`curl 7` ou `curl 28`). Retire o hook com `kubectl patch` (o comando de 9.9.6) e repita. Compare os totais com os da lição e explique, em três frases, por que os de quem faz podem diferir e que conclusão eles sustentam. Para separar o efeito da pausa do efeito do momento, alterne as variantes (uma rodada com pausa, uma sem, outra com...) em vez de fazer todas as de uma e depois todas da outra. Ao terminar, volte a `apply -k .`.

### Exercício 4 — Defenda a decisão

Um colega diz: “os probes de disponibilidade já tiram do Service uma réplica caída, e `tolerationSeconds` é o prazo de detecção de um nó, então baixando-o para 5 segundos a interrupção do nó acaba”. Em no máximo cinco frases, diga a ele o que acontece de fato quando um nó se desliga sem avisar, o que cada um desses dois ajustes mede, e o que sim encurtaria a janela e a que preço.

## Soluções

### Solução 1

É cálculo, não medição, salvo onde se diz o contrário.

a) **2 réplicas, 63 %.** Razão 1,26, fora de 0,9 a 1,1. `ceil(2 × 1,26)` = `ceil(2,52)` = **3**. Sobe para 3. (Em 9.6, com 72 % e 2 réplicas, pediu 3 pela mesma regra.)

b) **3 réplicas, 46 %.** Razão 0,92: dentro da tolerância. **Não faz nada.** Ainda que a tolerância não existisse, `ceil(3 × 0,92)` = `ceil(2,76)` = 3, o mesmo número. (Em 9.6, com 4 réplicas e 46 %, ficou em 4: a mesma situação.)

c) **4 réplicas, 90 %.** Razão 1,8. `ceil(4 × 1,8)` = `ceil(7,2)` = 8. Mas `maxReplicas` é 6, então o HPA fica em **6**. Anotaria isso na condição `ScalingLimited`, a mesma que 9.7 mostra pelo mínimo, agora pelo teto; esse caso não foi medido nesta execução porque a carga nunca chegou ao teto. Este é o caso do teto: sem `maxReplicas`, seriam 8.

d) **6 réplicas, 20 %, um minuto depois de o uso ter baixado.** Razão 0,4. `ceil(6 × 0,4)` = `ceil(2,4)` = 3. A conta diz 3, mas a janela de 60 segundos diz que se usa a recomendação **mais alta** dos últimos 60 segundos: se há 59 segundos a recomendação era de 6, continua sendo 6 por mais um instante. Desce quando essa recomendação sai da janela.

### Solução 2

Medido em `correr.salida.txt`:

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

**Duas réplicas, outra vez.** O Deployment ficou em 2/2 aos 40 segundos, e o último evento do HPA diz isso: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`, de há `33s`. O `kubectl scale` baixou o campo `spec.replicas` para 1; o HPA, na volta seguinte, viu que 1 era menos que o mínimo de 2 e o corrigiu. Com um autoscaler vivo, o número de réplicas é dele. O que se muda é o HPA.

### Solução 3

Depende da máquina de quem faz, e nisso consiste o exercício. Os totais desta execução estão em 9.9.8: com `preStop`, 5 falhas em 2.049 requisições em quatro rodadas, todas `curl 28`; sem ele, 29 em 1.569 em três rodadas, 6 delas `curl 7`. O que se pode dizer, e o que não:

- **Os totais de quem faz não vão coincidir com os daqui**, porque dependem de quanta CPU o cliente teve, de quão carregada estava a máquina e de quantas requisições cada rodada conseguiu fazer (aqui houve rodadas de 433 e de 612 requisições no mesmo tempo).
- **O que deve se repetir** é a forma: as falhas sem pausa se agrupam nos segundos que seguem o `set image`, há conexões recusadas (`curl 7`) só sem pausa, e com pausa as rodadas dão poucas falhas, com rodadas em zero e outras com algumas isoladas.
- **O que a medição de quem faz não sustenta**: uma porcentagem exata, nem a frase “com `preStop` não se perde nada”. Se uma das rodadas com pausa deu zero, isso não significa que a pausa elimine as falhas; significa que essa rodada não viu nenhuma.
- Se as rodadas com pausa não se distinguirem das rodadas sem ela, a conclusão honesta é que essa máquina, com esse cliente, não tem resolução para ver a diferença. Não que a pausa não sirva.

### Solução 4

Uma resposta possível: “Quando um nó se desliga sem avisar, o cluster não fica sabendo de imediato: espera o `node-monitor-grace-period`, 50 segundos por padrão, para que o nó reporte. Durante esse tempo, os destinos dos Pods do nó continuam marcados como prontos e o Service reparte requisições que se perdem; na execução da lição perderam-se 7 em 42, e a última falha foi 53 segundos depois do desligamento. Os probes de disponibilidade não ajudam porque quem os executa é o `kubelet` desse nó, que está desligado. O `tolerationSeconds`, de 300 segundos por padrão, é o prazo que o cluster espera *depois* de declarar o nó inalcançável antes de repor os seus Pods, então baixá-lo repõe antes os Pods, mas não tira antes os destinos mortos do Service. O que sim ajuda é ter mais réplicas distribuídas (pela distribuição, é de esperar que caia na morta uma requisição em cada N), novas tentativas no cliente para requisições que podem ser repetidas e, à custa de falsos alarmes, baixar o `node-monitor-grace-period` no plano de controle.”

## Apagar o cluster

Quando os exercícios terminarem, apague o cluster da lição. Com ele vão embora o MetalLB, o Envoy Gateway, o `metrics-server`, o Pod `depurar` e tudo o mais:

```text
$ kind delete cluster --name curso-k8s-l9
Deleting cluster "curso-k8s-l9" ...
Deleted nodes: ["curso-k8s-l9-control-plane" "curso-k8s-l9-worker2" "curso-k8s-l9-worker"]
(borrar tardó 2 s)

$ kind get clusters | grep -c curso-k8s-l9
0
```

Depois apague os `token.txt` e a pasta temporária do `kubeconfig`, que guarda a credencial de administrador do cluster que acabou de ser apagado. O `rm -rf` é perigoso se a variável estiver vazia ou apontar para outro lugar, então vai protegido por um `case` que só o deixa rodar se o caminho for o que o `mktemp` criou em 9.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 9.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l9.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt punto-de-partida/token.txt
```

Confira ainda que não restou nenhum contêiner de cliente (`docker ps -a --filter name=curso-k8s-l9` não deve mostrar nada) e que o nó desligado em 9.12 não ficou desligado: se o cluster foi apagado com o nó parado, o `kind delete cluster` também o remove. Se foi criada uma rede de Docker própria para rodar várias lições ao mesmo tempo, ela é apagada depois do cluster, e só ela: `docker network rm <a-rede-criada>`. A rede `kind` normal não é tocada.

## Como sei que consegui

- [ ] Diante de `error: Metrics API not available`, dizer o que falta (um respondedor da API de métricas), e diante de `x509: cannot validate certificate for … because it doesn't contain any IP SANs`, dizer o que acontece e o que a flag conserta, e por que ela é só de laboratório.
- [ ] Calcular à mão as réplicas que o HPA pedirá com `ceil(atuais × medida ÷ meta)`, aplicar a tolerância de 10 % e conferir contra a coluna `TARGETS` e os eventos `SuccessfulRescale`.
- [ ] Explicar por que o Deployment já não leva `replicas` e o que o `kubectl diff` mostrou em `replicas: 3` → `replicas: 1`.
- [ ] Explicar por que a janela de redução torna lenta a descida e rápida a subida, e tê-lo visto no relógio.
- [ ] Ler o `FailedScheduling` de uma restrição de distribuição e dizer por que o nó de controle exige `nodeTaintsPolicy: Honor`.
- [ ] Rodar `./sondeo.sh`, ler as três colunas (código, saída do `curl`, versão) e dizer o que distingue um `curl 7` de um `curl 28`.
- [ ] Dizer, com os números de quem mede, quanto se perde numa atualização com e sem `preStop`, e que limites tem a medição.
- [ ] Fazer `rollout undo`, olhar o `deletionTimestamp` e dizer por que uma requisição pôde responder com a versão que acabou de ser retirada.
- [ ] Provocar um `drain` bloqueado por um PDB que não deixa margem, ler e corrigi-lo; e dizer por que, depois de uma manutenção, as réplicas podem ficar juntas.
- [ ] Desligar um nó, medir a janela de falha, e dizer o que a encurta (mais réplicas distribuídas, novas tentativas do cliente, um prazo de detecção menor no plano de controle) e o que não (os probes, `tolerationSeconds`).
- [ ] Rodar `programas/09-escalar-y-actualizar/correr.sh > /tmp/mi-corrida-l9.txt 2>&1` e comparar com `correr.salida.txt` (sem redirecionar para esse arquivo: ele é a referência) o que não muda: o `x509`, o `Metrics API not available` e o `MissingEndpoints`; `replicas: 3` → `replicas: 1` no `diff`; o mínimo de 2 réplicas, uma por nó; o `FailedScheduling` com `didn't match pod topology spread constraints`; o HPA que sobe ao ultrapassar 55 % e desce uma janela depois; os dois modos de falha do polling; o retorno à versão anterior com uma requisição que ainda responde a versão retirada; o `drain` bloqueado pelo PDB estrito; e o nó que passa a `NotReady` depois de uns 50 segundos. Os números exatos de requisições, os tempos, os nomes dos Pods, os IPs e a distribuição das falhas entre as rodadas mudam a cada execução: observam-se, não se comparam.
- [ ] Provocar uma atualização com uma imagem que não existe, ler `ErrImagePull` e `ImagePullBackOff`, ver que o Deployment fica `UP-TO-DATE 1` com as réplicas antigas disponíveis, e voltá-la com `rollout undo`.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l9`, a pasta temporária do `kubeconfig` já não existe em `/tmp`, e não restou nenhum `token.txt`.

## Resumo

Responder sem olhar a lição:

1. O que falta num cluster recém-criado para que o `kubectl top` funcione, e por que o `metrics-server` não inicia sem ajustes no kind?
2. Qual é a fórmula do HPA, contra o que se mede a porcentagem, e o que faz a tolerância?
3. O que faz a janela de redução de 60 segundos, e por que a subida não tem uma parecida?
4. Por que um Deployment governado por um HPA não deve levar `replicas`?
5. O que dizem `maxSkew`, `DoNotSchedule` e `nodeTaintsPolicy: Honor`, e o que acontece sem o último?
6. Que duas coisas acontecem ao mesmo tempo quando um Pod é desligado, e o que o `preStop` fecha?
7. O que distingue uma falha `curl 7` de uma `curl 28`?
8. O que mostrou o polling com e sem `preStop`, e o que ele não demonstra?
9. Por que pode responder uma versão que acabou de ser retirada com `rollout undo`?
10. O que é um PDB, a que tipo de interrupções se aplica, e o que acontece com um `drain` quando não há margem?
11. Quanto demorou o cluster a perceber o nó caído, e o que encurta essa janela?
12. O que acontece com o serviço quando uma atualização aponta para uma imagem que não existe, e por quê?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Horizontal Pod Autoscaling”](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/): a fórmula `desiredReplicas`, o cálculo contra os `requests`, a tolerância de 10 %, a janela de estabilização de 300 segundos por padrão para reduzir, a política de comportamento padrão e a recomendação de retirar `spec.replicas` do Deployment.
- [Kubernetes, “Pod Topology Spread Constraints”](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/): `topologyKey`, `maxSkew`, `whenUnsatisfiable`, `nodeTaintsPolicy`, `matchLabelKeys` com `pod-template-hash` e a limitação sobre Pods que são retirados.
- [Kubernetes, “Pod Lifecycle”](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): o fluxo de terminação de um Pod: `preStop`, sinal `TERM`, prazo, `KILL`, e a retirada dos destinos em paralelo.
- [Kubernetes, “Container Lifecycle Hooks”](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/): os três tipos de hook (Exec, HTTP, Sleep) e o prazo de desligamento que inclui o `preStop`.
- [Kubernetes, “Deployments”](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxSurge`, `maxUnavailable`, `rollout undo`, `--to-revision`, a anotação `kubernetes.io/change-cause`, `revisionHistoryLimit` e a condição `Available`.
- [Kubernetes, “Disruptions”](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/): interrupções voluntárias e involuntárias, o orçamento que não evita as segundas mas as conta, e `kubectl drain` com a API de eviction.
- [Kubernetes, “Specifying a Disruption Budget for your Application”](https://kubernetes.io/docs/tasks/run-application/configure-pdb/): `minAvailable` e `maxUnavailable`.
- [Kubernetes, “Safely Drain a Node”](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/): o que faz o `kubectl drain` e por que ele respeita os PDBs; `--ignore-daemonsets`.
- [Kubernetes, “Node Status”](https://kubernetes.io/docs/reference/node/node-status/): a condição `Ready` em `Unknown` se o controlador de nós não tem notícias do nó em `node-monitor-grace-period` (50 segundos por padrão) e os heartbeats com `Lease`.
- [Kubernetes, “Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): os taints `not-ready` e `unreachable`, e as tolerâncias de 300 segundos que são adicionadas sozinhas.
- [Kubernetes, “Resource metrics pipeline”](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/): a Metrics API, o `metrics-server` e o `kubectl top`; a CPU como taxa numa janela.
- [metrics-server, README](https://github.com/kubernetes-sigs/metrics-server): os requisitos (certificado do `kubelet` assinado pela autoridade do cluster), `--kubelet-insecure-tls` “somente para testes”, e os usos e não usos.
- [metrics-server, notas da v0.9.0](https://github.com/kubernetes-sigs/metrics-server/releases/tag/v0.9.0): a versão que a lição usa.
- [Phil Pearl, “Kubernetes' dirty endpoint secret and Ingress”](https://philpearl.github.io/post/k8s_ingress/) (26 de julho de 2019): a retirada de destinos e o desligamento acontecem ao mesmo tempo; a pausa antes de desligar.
- [Go, `net/http`, `Server.Shutdown`](https://pkg.go.dev/net/http#Server.Shutdown): o desligamento ordenado fecha primeiro os listeners abertos e depois as conexões ociosas.
- [Kubernetes, “Job”](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-termination-and-cleanup): `activeDeadlineSeconds` corre desde que o Job é criado e o termina aconteça o que acontecer.
- [Kubernetes, “kube-controller-manager”](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/): `--node-monitor-grace-period` (50 s) e `--node-monitor-period` (5 s).
- [curl, “man page”](https://curl.se/docs/manpage.html): `--retry`, `--retry-all-errors` e `--max-time`.
- [curl, “libcurl error codes”](https://curl.se/libcurl/c/libcurl-errors.html): os códigos 7 e 28.

---

**Próxima:** [Lição 10 — O projeto terminado e o que muda em um cluster real](10-proyecto-final.md)
