# Lição 0 — O que é Kubernetes e o que NÃO é kind

Sexta-feira, 11h40 da noite. O `revisor` está há três semanas rodando em um único servidor, subido com um `docker run --restart always` que alguém digitou numa tarde e nunca anotou em lugar nenhum. Nessa hora o servidor desliga: uma fonte de alimentação que pifa. O contêiner morre com ele, e junto morre o *daemon* do Docker, o único que sabia reiniciá-lo. Na segunda-feira às nove, a equipe de operações precisa do relatório de status para a reunião semanal e a página está em branco. Alguém tem que acordar, conseguir outra máquina, lembrar das variáveis de ambiente exatas, da porta, do volume, da versão da imagem… e tudo isso estava no histórico do terminal do servidor que já não liga mais.

O problema não foi o contêiner. Foi que **ninguém, exceto uma pessoa dormindo, sabia como o serviço deveria estar**. Esta lição trata da ferramenta que existe para que o sistema saiba disso, e não uma pessoa às três da manhã.

**Tempo:** 90 min

**O que se constrói:** nada ainda. É uma lição de leitura: aqui se monta o mapa mental com o qual o resto do curso se torna previsível

**O que se aprende:** que problema o Kubernetes resolve que o Docker sozinho não resolve; o plano de controle e os nós, peça por peça; declarar o estado desejado e deixar que o cluster o alcance (o ciclo de controle); o mapa do Docker para o Kubernetes; o que é o kind, o que um cluster do kind prova e o que não prova; e contra o que um cluster local protege e contra o que não protege

**De onde a gente vem.** Do [curso de Docker](https://www.habil.mx/pt/cursos/docker/) da Hábil, ou de uma prática equivalente: já se sabe construir uma imagem, rodá-la com `docker run`, passar variáveis de ambiente, uma porta e um volume, e subir várias juntas com o Compose. Além disso, o `revisor` já está empacotado: um servidor em Go que escuta na porta 8080, responde `GET /salud` e `GET /api/estados`, e é configurado por variáveis de ambiente. O que ainda falta é o mapa de **como um cluster pensa**, que é diferente do mapa do Docker e que explica por que os comandos das lições seguintes são como são.

**O que esta lição não faz.** Não instala nada (isso é a [Lição 1](01-instalacion-primer-cluster.md)) e não implanta o `revisor` (isso começa na [Lição 2](02-pods-deployments.md)). Traz um percurso real por um cluster do kind, com as respectivas saídas, para se ver com os próprios olhos o que a lição afirma. Não é preciso entender cada linha de cada saída ainda: o que importa é **o que elas contam**. Quem quiser repetir o percurso pode fazer isso depois da Lição 1, quando já tiver o `kubectl` e o `kind`.

**Sobre as execuções.** As saídas desta lição foram obtidas em 21 de outubro de 2026 com `kind` v0.33.0, `kubectl` v1.37.1 e a imagem de nó `kindest/node:v1.37.0` fixada pelo *digest*, sobre Docker Engine 29.2.1. A máquina foi um Mac com processador ARM, com o Docker dentro de uma máquina virtual Linux (Colima), **não** o Linux Mint, que é o sistema de referência do curso. O que muda no Linux Mint: a coluna `KERNEL-VERSION` mostrará o kernel da máquina e `amd64` em vez de `arm64`, os endereços IP e as portas serão outros, e os nomes dos Pods terão outros sufixos aleatórios. Todo o resto deve coincidir. Houve mais uma diferença, e ela é instrutiva: nessa máquina um cluster de **três** nós não subiu, porque o limite de monitoramento de arquivos do sistema estava em 128 e se esgotou (a seção 0.6.3 conta isso). Por isso o percurso usa **um único nó**; o cluster de três nós do curso chega na Lição 1, que primeiro ajusta esse limite. O percurso completo está em [`programas/00-que-es-kubernetes/`](../programas/00-que-es-kubernetes): `recorrido.sh` o executa do início ao fim em cerca de dois minutos e `recorrido.salida.txt` é a saída dele; `ejercicio3.sh` e `ejercicio3.salida.txt` fazem o mesmo com o Exercício 3.

## Ao terminar, a gente vai conseguir

- Explicar com um exemplo por que `docker run --restart always` não basta para manter um serviço vivo quando a máquina que o executa cai.
- Nomear as peças do plano de controle (`kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager`) e as de cada nó (`kubelet`, `kube-proxy`, o *runtime* de contêineres), e dizer o que cada uma faz em uma frase.
- Descrever passo a passo o que ocorre no cluster entre um `kubectl apply` e um contêiner rodando.
- Distinguir um comando imperativo (`kubectl scale`) de uma declaração (`kubectl apply -f`) e prever o que acontece quando os dois são misturados.
- Traduzir cinco conceitos do Docker para o equivalente no Kubernetes, e nomear um que não tem equivalente.
- Dizer o que é o kind, o que um cluster do kind demonstra e o que não demonstra.
- Ler o erro `The connection to the server localhost:8080 was refused` e dizer o que significa.

## O porquê antes do como

Com o Docker aprende-se a responder à pergunta “como rodo este programa?”. A resposta é uma imagem e um `docker run`. É uma grande resposta, e o Kubernetes não a muda: as imagens construídas no curso de Docker são exatamente as que o cluster vai rodar.

Mas há outra pergunta, que aparece assim que um serviço passa a importar: **“quem garante que ele continue rodando?”**. Com o Docker, a resposta é o *daemon* daquela máquina, e só enquanto aquela máquina estiver viva. A documentação do Docker deixa isso claro: as políticas de reinício, como `always` ou `unless-stopped`, aplicam-se aos contêineres daquele *daemon* ([Docker, “Start containers automatically”](https://docs.docker.com/engine/containers/start-containers-automatically/)). Se a máquina desaparece, não sobra ninguém que lembre que ali rodava alguma coisa.

O Kubernetes responde à segunda pergunta. Diz-se a ele **como o serviço deve estar** (“três cópias do `revisor`, com esta imagem, com esta configuração”) e ele se encarrega de mantê-lo assim, nas máquinas que tiver, mesmo que alguma caia. Isso muda o trabalho: deixa-se de dar comandos imperativos (“inicie isto”, “reinicie aquilo”) e passa-se a escrever **descrições** do estado desejado, que o cluster persegue sem descanso.

Há uma segunda razão para começar pela leitura e não pela instalação. O Kubernetes tem muitas peças com nomes estranhos, e as mensagens que vão aparecer nas lições seguintes (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) mencionam essas peças. Sem saber quem é o *scheduler*, um Pod `Pending` é um mistério; sabendo, é uma pista. E uma terceira razão: neste curso usa-se o **kind**, um cluster que vive dentro do Docker na máquina local. É uma ferramenta excelente para aprender, mas sem saber o que ele é, corre-se o risco de achar que o cluster local demonstra coisas que ele não demonstra.

A lição tem oito partes, nesta ordem:

1. **O problema que o Kubernetes resolve** (0.1).
2. **Declarar em vez de comandar: o ciclo de controle** (0.2), com um cluster real que conserta o que a gente quebra.
3. **As peças: o plano de controle e os nós** (0.3), vistas por dentro.
4. **Um comando imperativo versus uma declaração** (0.4): o que acontece quando os dois se misturam.
5. **O mapa do Docker para o Kubernetes** (0.5).
6. **O que é o kind e o que NÃO é** (0.6): o que o cluster local demonstra e o que não demonstra.
7. **As versões** (0.7): quais o curso usa e por quê.
8. **O que vem no resto do curso** (0.8).

Para antecipar aonde se chega, isto é o que aparecerá na seção 0.2. Apagou-se um de três Pods e, um segundo depois, o cluster já havia criado outro no lugar sem que ninguém pedisse. Essa é a ideia central de toda a lição:

```text
$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

## Os conceitos

### 0.1 O problema que o Kubernetes resolve

#### 0.1.1 De “rodar um contêiner” a “manter um serviço”

Um contêiner é um processo com sistema de arquivos próprio e rede própria, em **uma** máquina. Um serviço que as pessoas usam precisa de mais do que isso:

- Que haja **várias cópias**, para que a queda de uma não deixe ninguém sem serviço.
- Que essas cópias estejam em **máquinas diferentes**, para que a queda de uma máquina também não deixe.
- Que, se uma cópia morrer, **alguém a reponha** sem esperar por uma pessoa.
- Que os demais programas o **encontrem pelo nome**, mesmo que as cópias mudem de máquina e de endereço.
- Que a configuração possa ser **alterada sem reconstruir** a imagem.
- Que uma versão nova **substitua a antiga sem interromper** o serviço.

Com o Docker e o Compose dá para resolver algumas dessas coisas em uma única máquina. Nenhuma em várias. O Kubernetes é a ferramenta que resolve as seis, em um grupo de máquinas que ele chama de **cluster**.

A definição oficial é esta: o Kubernetes é “uma plataforma portátil, extensível e de código aberto para gerenciar cargas de trabalho e serviços em contêineres, que facilita tanto a configuração declarativa quanto a automação” ([kubernetes.io, “Overview”](https://kubernetes.io/docs/concepts/overview/)). Repare na palavra *declarativa*: é a que importa, e a seção 0.2 a explica.

Duas curiosidades, para ninguém ser pego de surpresa. O nome vem do grego e significa “timoneiro” ou “piloto”, e a abreviação **K8s** sai da contagem das oito letras que existem entre o “K” e o “s”. O Google liberou o projeto como código aberto em 2014 (as três coisas estão na mesma página oficial).

#### 0.1.2 O que o Kubernetes não é

A mesma página oficial dedica uma seção ao que o Kubernetes **não** faz, e convém lê-la antes de começar porque evita falsas expectativas. Entre outras coisas, o Kubernetes não constrói a aplicação nem implanta código-fonte (quem traz a imagem é a gente, como no curso de Docker), não traz bancos de dados nem filas de mensagens incluídos, e não impõe uma solução de logs nem de monitoramento. E a frase que mais vale a pena: o Kubernetes “não é um mero sistema de orquestração”. Orquestrar, em sentido técnico, é executar um fluxo definido: “primeiro A, depois B, depois C”. O Kubernetes, por outro lado, é “um conjunto de processos de controle independentes e combináveis que levam continuamente o estado atual em direção ao estado desejado”.

Essa última frase é o resumo desta lição. O restante a desmonta.

### 0.2 Declarar em vez de comandar: o ciclo de controle

#### 0.2.1 O termostato

A documentação do Kubernetes explica essa ideia central com um aparelho conhecido: um termostato ([kubernetes.io, “Controllers”](https://kubernetes.io/docs/concepts/architecture/controller/)). Quando se ajusta a temperatura em 22 graus, está se dizendo ao termostato qual é o **estado desejado**. A temperatura real do quarto é o **estado atual**. O termostato liga ou desliga o ar-condicionado para aproximar o estado atual do desejado. Não se diz a ele “ligue o ar por dez minutos”; diz-se “quero 22”, e ele decide o que fazer, repetidas vezes, enquanto estiver ligado.

Isso é um **ciclo de controle** (*control loop*): um processo que não termina, que observa, compara e corrige. No Kubernetes, cada um desses ciclos é chamado de **controlador**: “os controladores são ciclos de controle que vigiam o estado do cluster e então fazem ou solicitam alterações onde é necessário. Cada controlador tenta levar o estado atual do cluster para mais perto do estado desejado”.

A consequência prática é a da cena inicial, só que ao contrário. Com o Docker, o conhecimento de como o `revisor` deveria estar vivia na memória de uma pessoa. Com o Kubernetes, vive **no cluster**, por escrito, e um programa o compara com a realidade o tempo todo.

#### 0.2.2 Um estado desejado, escrito em um arquivo

No Kubernetes, o estado desejado é escrito em um **manifesto**: um arquivo YAML que descreve um objeto. Este é o primeiro manifesto do curso. Ele pede três cópias de um contêiner:

```yaml
# fig00_02.deployment.yaml — un estado deseado: «quiero tres copias de este contenedor».
# La imagen es `pause`, un contenedor que no hace nada más que esperar; viene ya
# dentro del nodo de kind, así que no se descarga nada. El `revisor` llega en la
# Lección 2; aquí solo importa ver qué hace el clúster con lo que declaras.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: espera
spec:
  replicas: 3
  selector:
    matchLabels:
      app: espera
  template:
    metadata:
      labels:
        app: espera
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65535
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: espera
        image: registry.k8s.io/pause:3.10
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Não é preciso entendê-lo inteiro; a Lição 2 o desmonta campo por campo. Por enquanto, três coisas. `kind: Deployment` diz que tipo de objeto ele é: um **Deployment** é a forma normal de pedir “mantenha rodando N cópias deste contêiner”. `replicas: 3` é o estado desejado: três cópias. E `template` é o modelo de cada cópia: que imagem usa e com que rótulo (*label*) `app: espera` é reconhecida. Os dois blocos `securityContext` dizem que o contêiner roda sem ser `root`, sem poder ganhar privilégios e com o sistema de arquivos em modo somente leitura; estão aqui porque neste curso todo manifesto traz esses blocos desde o primeiro, e a Lição 2 explica cada um.

A imagem, `registry.k8s.io/pause`, é um contêiner minúsculo que não faz nada além de esperar. Foi escolhida porque já vem dentro do nó do kind (o próprio Kubernetes a utiliza internamente), de modo que o exemplo não depende de baixar nada da internet.

#### 0.2.3 O que o cluster faz com a declaração

O manifesto é entregue ao cluster com `kubectl apply -f`. Isto foi o que o cluster do percurso respondeu:

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera created

$ kubectl rollout status deployment/espera --timeout=90s
Waiting for deployment "espera" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "espera" rollout to finish: 2 of 3 updated replicas are available...
deployment "espera" successfully rolled out
```

Leia a primeira resposta com cuidado: `deployment.apps/espera created`. Ela não diz “três contêineres iniciados”. Diz que o objeto Deployment foi **salvo**. Naquele instante não havia nenhum contêiner rodando; havia uma descrição. O segundo comando, `rollout status`, fica esperando e vai contando: zero de três disponíveis, uma, duas, e no final “concluído”. Entre a primeira linha e a última, o cluster esteve trabalhando para que a realidade alcançasse o que foi declarado.

Agora veja o que ficou:

```text
$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/3     3            3           1s

$ kubectl get replicaset -l app=espera
NAME                DESIRED   CURRENT   READY   AGE
espera-68b9d575f7   3         3         3       1s

$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-9gbtr   1/1     Running   0          1s
espera-68b9d575f7-cprg7   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          1s
```

Pediu-se **um** objeto e existem **três tipos** de objeto. É uma cadeia, e convém vê-la assim desde o primeiro dia:

```text
Deployment espera            «quiero 3 copias de este molde»
   └── ReplicaSet espera-68b9d575f7       «hay que tener 3 Pods con este molde exacto»
         ├── Pod espera-68b9d575f7-9gbtr
         ├── Pod espera-68b9d575f7-cprg7
         └── Pod espera-68b9d575f7-gsrlf
```

O **Deployment** é o que a gente escreve. O **ReplicaSet** é criado pelo Deployment, e o único trabalho dele é contar: garantir que existam tantos Pods quanto diz `replicas`. O sufixo `68b9d575f7` identifica o modelo; quando a imagem mudar, na Lição 2, aparecerá outro ReplicaSet com outro sufixo, e é assim que o Kubernetes muda de versão sem interromper o serviço. E o **Pod** é a unidade que de fato roda: a documentação o define como “a menor unidade implantável” do Kubernetes, “um grupo de um ou mais contêineres, com armazenamento e rede compartilhados” ([kubernetes.io, “Pods”](https://kubernetes.io/docs/concepts/workloads/pods/)). Quase sempre, um Pod tem um único contêiner; neste curso, sempre.

Repare também nos nomes dos Pods: o sufixo final (`9gbtr`, `cprg7`…) é aleatório. Em outra execução serão outros. Por isso, neste curso, nunca se digita manualmente o nome de um Pod: busca-se o Pod pelo rótulo, com `-l app=espera`.

#### 0.2.4 Quebrar algo de propósito

Agora o teste do termostato. Apagou-se um dos três Pods, manualmente, como se tivesse morrido:

```text
$ kubectl delete pod espera-68b9d575f7-9gbtr
pod "espera-68b9d575f7-9gbtr" deleted from default namespace

$ kubectl get pods -l app=espera
NAME                      READY   STATUS    RESTARTS   AGE
espera-68b9d575f7-cprg7   1/1     Running   0          3s
espera-68b9d575f7-fjx8v   1/1     Running   0          1s
espera-68b9d575f7-gsrlf   1/1     Running   0          3s
```

Continuam sendo três. O `9gbtr` já não está lá, e há um novo, `fjx8v`, com um segundo de idade. Ninguém o pediu. O ReplicaSet viu que o estado atual (dois Pods) não coincidia com o desejado (três) e criou um. O cluster registra o que faz nos **eventos**, e ali aparece a história completa:

```text
$ kubectl get events --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp
LAST SEEN   TYPE     REASON             OBJECT                         MESSAGE
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-9gbtr
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-gsrlf
3s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-cprg7
1s          Normal   SuccessfulCreate   replicaset/espera-68b9d575f7   Created pod: espera-68b9d575f7-fjx8v
```

Quatro criações: as três do início e a reposição. Os eventos são a primeira coisa que se olha quando algo não sai como esperado, e o curso os utiliza em cada lição.

Isso tem uma consequência que muda a forma de trabalhar: **no Kubernetes, apagar um Pod não desliga nada**. Para ter menos cópias, muda-se o estado desejado. Para não ter nenhuma, apaga-se o Deployment. Apagar o Pod só faz nascer outro.

#### 0.2.5 E quando o que cai é uma máquina

A cena do início não era um contêiner que morre: era uma máquina que desliga. O Kubernetes também cobre isso, mas convém saber **quanto tempo demora**, porque não é instantâneo. Quando um nó deixa de responder, o cluster o marca como indisponível, e os Pods que rodavam nele permanecem alocados ali por um tempo antes de serem repostos em outro nó. Esse tempo vem escrito em cada Pod. Este é o valor lido no Pod do percurso:

```text
[{"effect":"NoExecute","key":"node.kubernetes.io/not-ready","operator":"Exists","tolerationSeconds":300},{"effect":"NoExecute","key":"node.kubernetes.io/unreachable","operator":"Exists","tolerationSeconds":300}]
```

São 300 segundos. A documentação confirma: o Kubernetes adiciona essas duas tolerâncias automaticamente, e elas significam que os Pods “permanecem alocados aos nós durante 5 minutos depois que se detecta um desses problemas” ([kubernetes.io, “Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)). A espera existe para não mover tudo por causa de uma interrupção de rede de dez segundos.

Então o serviço fica fora do ar por cinco minutos? Não, se for feito o que este curso ensina: **ter várias réplicas distribuídas em nós diferentes**. Enquanto as do nó fora do ar aguardam reposição, as dos outros nós continuam atendendo. Cuidado com uma suposição cômoda: o Deployment cuida de **quantas** réplicas existem, não de **onde** ficam. Por padrão, o `kube-scheduler` *procura* distribuí-las entre os nós, mas se não puder, empilha todas em um só (a documentação diz que ele age como se tivesse a regra `whenUnsatisfiable: ScheduleAnyway`, “agende de qualquer maneira”). Para **exigir** a distribuição, o manifesto precisa declará-la com `topologySpreadConstraints` ou com antiafinidade ([kubernetes.io, “Pod Topology Spread Constraints”](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)); o manifesto desta lição não faz isso, e o curso volta ao tema quando o `revisor` precisar sobreviver a um nó desligado. Essa é uma das metas do curso: parar um nó de trabalho e ver o `revisor` continuar respondendo.

### 0.3 As peças: o plano de controle e os nós

#### 0.3.1 Dois tipos de máquina

Um cluster tem dois tipos de máquina, que o Kubernetes chama de **nós**:

- O **plano de controle** (*control plane*): as máquinas onde vive o “cérebro”. Guardam o estado desejado, decidem onde cada coisa roda e executam os controladores.
- Os **nós de trabalho** (*worker nodes*): as máquinas onde rodam os contêineres das aplicações.

Em um cluster de produção, o plano de controle costuma ficar em três máquinas dedicadas, para que a queda de uma não o pare. No cluster desta lição há **um único nó** que faz as duas coisas; no da Lição 1 haverá um de controle e dois de trabalho.

#### 0.3.2 As peças, uma por uma

As definições saem da página oficial de componentes ([kubernetes.io, “Kubernetes Components”](https://kubernetes.io/docs/concepts/overview/components/)); a coluna da direita é a tradução para o que se vê no curso.

| Peça | Onde vive | O que faz, segundo a documentação | O que significa na prática |
|---|---|---|---|
| `kube-apiserver` | plano de controle | “o servidor que expõe a API HTTP do Kubernetes” | é o único ponto de entrada: o `kubectl` fala com ele, e as demais peças também |
| `etcd` | plano de controle | “armazenamento de chave e valor, consistente e de alta disponibilidade, para todos os dados do servidor da API” | aqui fica escrito o manifesto; se o `etcd` for perdido, perde-se o estado desejado |
| `kube-scheduler` | plano de controle | “busca Pods que ainda não estão alocados a um nó e aloca cada um a um nó adequado” | decide **onde** cada Pod roda; quando não encontra lugar, o Pod fica `Pending` (Lição 5) |
| `kube-controller-manager` | plano de controle | “executa controladores para implementar o comportamento da API do Kubernetes” | aqui vivem os termostatos: o de Deployments, o de ReplicaSets, o de nós… |
| `cloud-controller-manager` | plano de controle, opcional | “integra-se com os provedores de nuvem subjacentes” | no kind não existe; por isso um `LoadBalancer` precisa de ajuda (Lição 6) |
| `kubelet` | cada nó | “garante que os Pods estejam rodando, incluindo os respectivos contêineres” | o agente de cada máquina: recebe Pods e os torna realidade |
| `kube-proxy` | cada nó, opcional | “mantém regras de rede nos nós para implementar os Services” | direciona o tráfego que chega ao endereço e à porta de um Service para os Pods que o atendem naquele momento; quem resolve o nome do Service é o DNS do cluster, não ele (Lição 3) |
| *runtime* de contêineres | cada nó | “o software responsável por rodar contêineres” | no kind é o `containerd`, não o Docker |

#### 0.3.3 Vendo as peças no cluster

Tudo isso não é teoria: dá para ver. Os componentes do plano de controle rodam como Pods em um namespace reservado, `kube-system`:

```text
$ kubectl get pods -n kube-system
NAME                                                 READY   STATUS    RESTARTS   AGE
coredns-559f6c778d-gg7jc                             1/1     Running   0          15s
coredns-559f6c778d-wcmct                             1/1     Running   0          15s
etcd-curso-k8s-l0-control-plane                      1/1     Running   0          23s
kindnet-2cfgd                                        1/1     Running   0          15s
kube-apiserver-curso-k8s-l0-control-plane            1/1     Running   0          22s
kube-controller-manager-curso-k8s-l0-control-plane   1/1     Running   0          22s
kube-proxy-cnp6z                                     1/1     Running   0          15s
kube-scheduler-curso-k8s-l0-control-plane            1/1     Running   0          22s
```

Aí estão quatro das peças da tabela: `etcd`, `kube-apiserver`, `kube-controller-manager` e `kube-scheduler`, cada uma com o nome do nó colado no final. Está o `kube-proxy`. E há três que a tabela não menciona: `coredns` (duas cópias), que é o DNS interno do cluster e o que faz um Pod encontrar outro pelo nome (Lição 3); e `kindnet`, a rede entre Pods que o kind instala por padrão. O Kubernetes não traz uma rede própria: quem a fornece é um plugin chamado CNI, e cada instalação escolhe o próprio CNI. O [guia de configuração do kind](https://kind.sigs.k8s.io/docs/user/configuration/) chama o dele de `kindnetd` e explica como trocá-lo; a Lição 7 volta a isso, porque depende da rede uma `NetworkPolicy` ser aplicada ou não.

Falta uma peça na lista: o `kubelet`. Ele não é um Pod. É um programa normal do nó, e aparece ao olhar os processos **dentro** do nó:

```text
$ docker exec curso-k8s-l0-control-plane sh -c "ps -eo comm | grep -E '^(kubelet|containerd|kube-|etcd)' | sort"
containerd
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
containerd-shim
etcd
kube-apiserver
kube-controller
kube-proxy
kube-scheduler
kubelet
```

`kubelet` e `containerd` são processos do nó. Os demais (`etcd`, `kube-apiserver`, etc.) são contêineres que o `containerd` iniciou, e cada `containerd-shim` é um pequeno processo auxiliar que vigia contêineres. Nesta execução há nove, um por Pod, porque o *shim* do `runc` agrupa em um mesmo processo os contêineres de um mesmo Pod; mas quem decide essa relação é o *runtime*, então não conte Pods contando *shims* ([containerd, “Runtime v2”](https://github.com/containerd/containerd/blob/main/docs/runtime-v2.md)). (O nome `kube-controller` aparece cortado porque o `ps` mostra apenas os primeiros quinze caracteres do nome do programa.)

#### 0.3.4 O ovo e a galinha

Aqui há um enigma. Quase todos os Pods nascem igual: um controlador (o de ReplicaSets, por exemplo) os escreve no `kube-apiserver`, o `kube-scheduler` encontra os que ainda não têm nó e escolhe um para cada Pod, e o `kubelet` desse nó os inicia. O `kube-scheduler` não cria Pods: ele os aloca ([kubernetes.io, “Kubernetes Scheduler”](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)). Mas o `kube-apiserver` é, ele mesmo, um Pod. Quem iniciou o Pod do servidor da API antes de existir o servidor da API?

A resposta está em uma pasta do nó:

```text
$ docker exec curso-k8s-l0-control-plane ls /etc/kubernetes/manifests
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

São quatro manifestos, um por peça do plano de controle. O `kubelet` lê essa pasta diretamente, sem perguntar a ninguém, e inicia o que encontrar. Esses Pods são chamados de **Pods estáticos**: são gerenciados pelo `kubelet` a partir de arquivos, não pelo servidor da API ([kubernetes.io, “Create static Pods”](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)). O que aparece com `kubectl get pods -n kube-system` é um reflexo deles que o `kubelet` publica na API para que possam ser vistos. Por isso os nomes deles terminam com o nome do nó, e por isso não têm o sufixo aleatório dos Pods que um ReplicaSet cria.

Não se vai mexer nessa pasta neste curso. Mas agora fica claro por que o plano de controle “sobe sozinho”, e o que perguntar se algum dia ele não subir.

#### 0.3.5 A viagem completa de um `kubectl apply`

Com as peças à vista, este é o percurso do que aconteceu em 0.2.3, de ponta a ponta:

1. O `kubectl` lê `fig00_02.deployment.yaml` e o envia ao **`kube-apiserver`**, por HTTPS.
2. O `kube-apiserver` verifica quem faz o pedido e se há permissão, valida o objeto e o salva no **`etcd`**. Responde `deployment.apps/espera created`. Até aqui não existe nenhum contêiner.
3. O controlador de Deployments, dentro do **`kube-controller-manager`**, vê um Deployment novo sem ReplicaSet e cria um.
4. O controlador de ReplicaSets vê um ReplicaSet que pede três Pods e não tem nenhum, e cria três objetos Pod, ainda sem nó alocado.
5. O **`kube-scheduler`** vê três Pods sem nó, escolhe um para cada um e anota isso no Pod.
6. O **`kubelet`** do nó escolhido vê que tem Pods alocados, pede ao **`containerd`** que inicie os contêineres, e informa o status deles ao `kube-apiserver`.
7. O `kubectl rollout status`, que estava perguntando, vê os três Pods disponíveis e escreve `successfully rolled out`.

Observe que nenhuma peça dá ordens a outra. Cada uma vigia os objetos que interessam a ela e age quando o estado atual não coincide com o desejado. Se uma peça cair por um instante, ao voltar encontra o que está pendente e faz o trabalho. Por isso o projeto tolera falhas: não há uma cadeia de chamadas que se quebre no meio.

### 0.4 Um comando imperativo versus uma declaração

#### 0.4.1 As duas maneiras de falar com o cluster

O `kubectl` permite trabalhar de duas maneiras, e a documentação as distingue com cuidado ([kubernetes.io, “Kubernetes Object Management”](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/)):

- **Comandos imperativos** (*imperative commands*): diz-se ao cluster o que fazer, com um verbo. `kubectl create deployment`, `kubectl scale`, `kubectl delete`. São rápidos, e a documentação os recomenda “para começar ou para uma tarefa única”. O problema deles: não deixam registro. O único lugar que sabe como o objeto está é o próprio cluster.
- **Declarações** (*declarative object configuration*): escreve-se um arquivo com o estado desejado e entrega-se com `kubectl apply -f`. O arquivo é guardado no Git, revisado antes de ser aplicado, e se o cluster for perdido, aplica-se novamente e tudo fica igual.

Este curso usa declarações para tudo o que importa. Os comandos imperativos aparecem apenas para inspecionar (`get`, `describe`, `logs`) e para experimentos descartáveis.

#### 0.4.2 O que acontece quando os dois se misturam

A documentação traz um aviso breve e sério: “um objeto do Kubernetes deve ser gerenciado com uma única técnica; misturar técnicas no mesmo objeto produz comportamento indefinido”. No percurso, os dois foram misturados de propósito, para mostrar um desses comportamentos. Primeiro, um comando imperativo: subir de três para cinco cópias.

```text
$ kubectl scale deployment espera --replicas=5
deployment.apps/espera scaled

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/5     5            3           3s
```

O cluster obedeceu: agora quer cinco (`3/5` significa “três prontas de cinco desejadas”; as outras duas estão iniciando). Mas o arquivo `fig00_02.deployment.yaml` continua dizendo `replicas: 3`. Agora o cluster e o arquivo **não coincidem**, e nada avisa disso. Para ver a diferença existe o `kubectl diff`, que compara o arquivo com o que há no cluster sem alterar nada:

```text
$ kubectl diff -f fig00_02.deployment.yaml
@@ -6,14 +6,14 @@
     kubectl.kubernetes.io/last-applied-configuration: |
       {"apiVersion":"apps/v1","kind":"Deployment","metadata":{"annotations":{},"name":"espera","namespace":"default"},"spec":{"replicas":3,"selector":{"matchLabels":{"app":"espera"}},"template":{"metadata":{"labels":{"app":"espera"}},"spec":{"containers":[{"image":"registry.k8s.io/pause:3.10","name":"espera","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}}],"securityContext":{"runAsNonRoot":true,"runAsUser":65535,"seccompProfile":{"type":"RuntimeDefault"}}}}}}
   creationTimestamp: "2026-10-21T07:52:14Z"
-  generation: 2
+  generation: 3
   name: espera
   namespace: default
   resourceVersion: "587"
   uid: 0e26d2f6-3277-4f4f-9dc0-592b883974f8
 spec:
   progressDeadlineSeconds: 600
-  replicas: 5
+  replicas: 3
   revisionHistoryLimit: 10
   selector:
     matchLabels:
```

(Foram omitidas as três primeiras linhas da saída, que apenas nomeiam dois arquivos temporários com caminhos que mudam a cada execução; estão completas em `recorrido.salida.txt`.)

É um *diff* como o do Git: a linha com `-` é o que há no cluster, a linha com `+` é o que ficaria se o arquivo fosse aplicado. O detalhe que importa é `-  replicas: 5` / `+  replicas: 3`: ao aplicar o arquivo, **perdem-se as duas cópias** que o comando adicionou. A linha de `generation` é um contador que sobe toda vez que o estado desejado muda; e a anotação longa, `last-applied-configuration`, é a cópia que o `kubectl apply` guarda do último arquivo aplicado, para saber quais campos são “dele”. (Um detalhe útil: o `kubectl diff` sai com código 1 quando encontra diferenças, segundo a própria ajuda do comando; não é uma falha, é a resposta.)

Aplicou-se o arquivo:

```text
$ kubectl apply -f fig00_02.deployment.yaml
deployment.apps/espera configured

$ kubectl get deployment espera
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
espera   3/3     3            3           4s
```

De volta a três. Ganhou o arquivo, porque `replicas` é um campo que o arquivo declara. A lição não é “os comandos imperativos são ruins”; é que, **quando existe um arquivo, o arquivo é a verdade**, e um comando que o contradiga dura até o próximo `apply`. Imagine que outra pessoa tenha executado esse comando, à noite, para aguentar um pico de carga, e que pela manhã alguém aplique o arquivo sem olhar. Por isso, neste curso, antes de aplicar sobre algo que já existe, olha-se o `kubectl diff`.

### 0.5 O mapa do Docker para o Kubernetes

Quase tudo o que se sabe de Docker tem um equivalente no Kubernetes. Não é idêntico, mas o mapa economiza metade do curso:

| No Docker | No Kubernetes | Onde aparece no curso |
|---|---|---|
| uma imagem | a **mesma** imagem | Lição 2 (`kind load docker-image`) |
| `docker run` de um contêiner | um **Pod** (e quase nunca sozinho: dentro de um Deployment) | Lição 2 |
| `--restart always` | o **Deployment** e o respectivo ReplicaSet, que repõem os Pods que faltam em um nó onde caibam | Lição 2 |
| `docker compose up --scale revisor=3` | `replicas: 3` no Deployment | Lição 2 |
| `-p 8080:8080` | um **Service**, e `kubectl port-forward` para testar a partir da máquina local | Lição 3 |
| o nome do serviço na rede do Compose | o **DNS do cluster**: `revisor.<namespace>.svc` | Lição 3 |
| `-e` e `--env-file` | **ConfigMap** e **Secret** | Lição 4 |
| `HEALTHCHECK` no Dockerfile | ***probes*** `startup`, `readiness` e `liveness` | Lição 5 |
| `--memory` e `--cpus` | `resources.requests` e `resources.limits` | Lição 5 |
| `--user`, `--read-only`, `--cap-drop ALL` | `securityContext` | Lição 2 |
| um volume nomeado | um **PersistentVolumeClaim** | Lição 8 |
| um contêiner que roda e termina | um **Job**; agendado, um **CronJob** | Lição 8 |
| o arquivo `compose.yaml` | manifestos YAML, reunidos com **Kustomize** | Lições 4 e 10 |

E há coisas que **não têm equivalente** no Docker, porque só fazem sentido quando há várias máquinas e várias pessoas: o *scheduler* que escolhe a máquina; os **Namespaces**, que separam equipes ou projetos dentro do mesmo cluster; as permissões por conta de serviço (**RBAC**); as políticas de rede entre Pods; e o escalonamento automático conforme a carga. Essas são as Lições 7 e 9.

Uma pergunta que sempre surge: se os nós não usam Docker, as imagens construídas com o Docker funcionam? Sim. O Kubernetes deixou de falar diretamente com o Docker Engine na versão 1.24 ([kubernetes.io, contexto histórico do dockershim](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/)), mas isso não afetou as imagens. O blog oficial explica assim: “a imagem que o Docker produz não é na verdade uma imagem específica do Docker: é uma imagem OCI”, e o `containerd` sabe baixá-la e executá-la ([kubernetes.io, “Don't Panic: Kubernetes and Docker”](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/)). O percurso confirma: a coluna `CONTAINER-RUNTIME` do nó diz `containerd://2.3.4`.

### 0.6 O que é o kind e o que NÃO é

#### 0.6.1 Kubernetes dentro do Docker

**kind** é a sigla de *Kubernetes IN Docker*. A página oficial o descreve em uma frase: “uma ferramenta para rodar clusters locais do Kubernetes usando ‘nós’ que são contêineres do Docker”, e acrescenta que “foi projetada principalmente para testar o próprio Kubernetes, mas pode ser usada para desenvolvimento local ou integração contínua” ([kind.sigs.k8s.io](https://kind.sigs.k8s.io/)).

A parte de “nós que são contêineres” vê-se sem truques. Pelo lado do Kubernetes, o cluster tem um nó:

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l0-control-plane   Ready    control-plane   25s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

E pelo lado do Docker, esse mesmo nó é um contêiner:

```text
$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l0 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l0-control-plane   kindest/node:v1.37.0   127.0.0.1:60004->6443/tcp
```

O mesmo nome, `curso-k8s-l0-control-plane`. A imagem `kindest/node` traz dentro um sistema Debian completo, com `systemd`, o `kubelet` e o `containerd`: é uma “máquina” simulada, feita de contêiner. Dentro dela, o `containerd` roda os contêineres dos Pods. São contêineres dentro de um contêiner. (O filtro `--filter label=...` foi usado para listar apenas os contêineres deste cluster; se na máquina houver outros contêineres, eles não aparecem.)

Repare em duas colunas de `get nodes`. `OS-IMAGE` diz Debian, mesmo que o sistema instalado seja o Mint: é o sistema **da imagem do nó**. Mas `KERNEL-VERSION` mostra o kernel **da máquina que roda o Docker**, porque os contêineres não trazem kernel próprio: todos usam o do host. Essa coluna é a primeira pista do que o kind não é.

#### 0.6.2 O que um cluster do kind demonstra e o que não demonstra

O kind roda o Kubernetes de verdade: o mesmo `kube-apiserver`, o mesmo `etcd`, o mesmo *scheduler*, instalados com o `kubeadm`, a ferramenta oficial ([design do kind](https://kind.sigs.k8s.io/docs/design/initial/)). Entre as metas de projeto dele está passar em todos os testes de conformidade do Kubernetes. Tudo o que se aprende sobre a **API** (Deployments, Services, ConfigMaps, *probes*, permissões) vale igualmente em um cluster de produção.

O que não é igual é **o que está por baixo**. Esta tabela é a que convém ter à mão durante o curso:

| O que se testa no kind | Demonstra isso? | Por quê |
|---|---|---|
| Que os manifestos são válidos e fazem o esperado | **Sim** | é a mesma API e o mesmo código do Kubernetes |
| Que os Pods renascem quando morrem | **Sim** | o controlador é o mesmo |
| Que as permissões (RBAC) e o nível `restricted` funcionam | **Sim** | quem os aplica é o `kube-apiserver`, igual em produção |
| Que o serviço sobrevive à queda de uma máquina | **Em parte** | `docker stop` em um nó se parece com isso, mas os três “nós” compartilham a máquina, o disco e o kernel: se o computador cair, cai tudo |
| Que a `NetworkPolicy` corta o tráfego | **Depende** | quem a aplica é a rede (CNI), não o Kubernetes; a Lição 7 mede isso ao vivo |
| Que o serviço aguenta determinada carga | **Não** | os nós dividem o mesmo processador e a mesma memória; os números não se transferem para outra máquina |
| Que um `LoadBalancer` entrega um IP público | **Não** | o kind não traz balanceador; é necessária uma peça à parte ([Cloud Provider KIND](https://kind.sigs.k8s.io/docs/user/loadbalancer/)), e a Lição 6 verifica isso |
| Que os dados estão a salvo | **Não** | o armazenamento padrão do kind (um provisionador chamado `local-path-provisioner`, que o kind instala ao criar o cluster) guarda os dados no próprio nó, que é um contêiner na máquina local; a Lição 8 mede o que se perde e quando |
| Que o plano de controle tolera falhas | **Não** neste curso | o kind permite vários nós de controle, mas em uma única máquina isso testa a configuração, não a tolerância real |

Resumo honesto: **o kind demonstra que a gente entende o Kubernetes; não demonstra que o sistema esteja pronto para produção.** A Lição 10 termina, justamente, com a lista do que falta.

#### 0.6.3 Um exemplo real de “compartilham a máquina”

A história de que “os nós compartilham o kernel” não é um detalhe acadêmico, e a preparação desta lição demonstrou isso sem querer. Na primeira vez, tentou-se criar o cluster com três nós, como o da Lição 1. O `kind` disse que tudo tinha corrido bem, incluindo a linha `✓ Joining worker nodes`. Mas `kubectl get nodes` mostrava um único nó, e o Pod do `kube-proxy` estava em estado `Error`. O log dele dizia:

```text
"command failed" err="failed complete: fsnotify watcher init: too many open files"
```

E o `kubelet` dos nós de trabalho, dentro do contêiner, parava com:

```text
"Failed to start cAdvisor" err="inotify_init: too many open files"
```

A causa: os programas do Linux que monitoram alterações em arquivos usam um recurso do **kernel** chamado `inotify`, e o kernel tem um limite de quantos monitores cada usuário pode abrir. Naquela máquina o limite estava em 128 (`fs.inotify.max_user_instances = 128`). Cada nó do kind inicia um `kubelet` próprio e um `kube-proxy` próprio, todos contra **o mesmo kernel**, e juntos os três esgotaram o limite. Com um único nó, o limite bastou.

O guia de problemas conhecidos do kind descreve exatamente isto: o Ubuntu traz esse limite em 128, “o que não basta para criar um cluster com muitos nós”, e recomenda subi-lo para 512 ([kind, “Known Issues”](https://kind.sigs.k8s.io/docs/user/known-issues/)). O Linux Mint 22 baseia-se no Ubuntu 24.04 ([Linux Mint, notas da versão 22](https://www.linuxmint.com/rel_wilma.php)), então na máquina do curso é provável que aconteça o mesmo. Por isso a Lição 1 ajusta esse limite **antes** de criar o cluster do curso. E por isso esta lição usa um único nó.

A prova de que essa era a causa: na mesma máquina subiu-se o limite para 512 e criou-se novamente o cluster de três nós, sem mudar mais nada. Desta vez os três ficaram prontos, cada um com o respectivo `kube-proxy` rodando (o script é `tres-nodos.sh` e a saída completa, `tres-nodos.salida.txt`):

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l0-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l0-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l0-worker2         Ready    <none>          19s   v1.37.0
```

Duas lições saem daqui. A primeira: três “máquinas” do kind são três processos em uma única máquina, e compartilham os limites dela. A segunda, mais geral: **um comando que diz “✓” não prova que o sistema ficou bom**. Olha-se o estado (`kubectl get nodes`, `kubectl get pods -A`) antes de dar algo como certo.

### 0.7 As versões

O Kubernetes lança uma versão menor aproximadamente **três vezes por ano** ([kubernetes.io, “Kubernetes Release Cycle”](https://kubernetes.io/releases/release/)), e mantém ao mesmo tempo as três mais recentes, cada uma com cerca de **um ano** de correções ([kubernetes.io, “Releases”](https://kubernetes.io/releases/)). Isto era o que essa página publicava em 21 de outubro de 2026:

| Versão menor | Último patch | Fim do suporte |
|---|---|---|
| **1.37** | 1.37.1 | 28 de outubro de 2027 |
| 1.36 | 1.36.5 | 28 de junho de 2027 |
| 1.35 | 1.35.9 | 28 de fevereiro de 2027 |
| 1.34 | 1.34.12 | 27 de outubro de 2026 |

(A mesma página diz que são mantidas “as três mais recentes” e ao mesmo tempo lista a 1.34 com a data de término; naquela data restavam seis dias.)

O curso usa o **Kubernetes 1.37**, a mais recente. Há dois números diferentes que convém não confundir:

- **O cluster roda 1.37.0.** É a versão que traz a imagem de nó padrão do kind v0.33.0. Em `kubectl get nodes` ela aparece na coluna `VERSION`: `v1.37.0`.
- **O `kubectl` é 1.37.1.** É a ferramenta instalada na máquina local. A política oficial diz que o `kubectl` funciona com um servidor da API até **uma versão menor** mais antiga ou mais nova ([kubernetes.io, “Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/)): com um cluster 1.37, servem `kubectl` 1.36, 1.37 e 1.38. A diferença de patch não importa.

E mais uma: **a imagem do nó é fixada pelo *digest***. As notas da versão v0.33.0 do kind publicam, para cada versão do Kubernetes, a imagem com o *digest* `sha256`, e dizem que é preciso usá-la para obter a imagem construída para aquela versão do kind ([kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). Por isso o arquivo de configuração do percurso a escreve por completo:

```yaml
# fig00_01.kind.yaml — el clúster de prueba de la Lección 0.
# Un solo nodo, que hace a la vez de plano de control y de nodo de trabajo.
# La imagen del nodo va fijada por su huella (sha256), copiada de las notas de la
# versión v0.33.0 de kind. El clúster del curso (tres nodos) llega en la Lección 1.
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

Uma tag como `v1.37.0` pode ser movida por quem publica a imagem; um *digest*, não. Se alguém substituísse a imagem por outra, o *digest* deixaria de coincidir e o download falharia. É o mesmo hábito que a Lição 1 aplica aos binários do `kubectl` e do `kind`.

### 0.8 O que vem no resto do curso

Tudo o que foi visto é colocado em prática nas lições seguintes. Cada uma acrescenta uma peça ao `revisor` no cluster:

| Lição | O que é acrescentado | Que ideia desta lição entra em ação |
|---|---|---|
| 1 | Instalar `kubectl` e `kind` e criar o cluster de três nós | o ajuste do `inotify` de 0.6.3; contextos e o hábito de conferi-los |
| 2 | O `revisor` como Deployment | a cadeia Deployment, ReplicaSet e Pod de 0.2.3 |
| 3 | Um Service e o respectivo nome no DNS | `kube-proxy` e `coredns` de 0.3.3 |
| 4 | Configuração sem reconstruir | o mapa de `-e` para ConfigMap de 0.5 |
| 5 | *Probes*, recursos e desligamento ordenado | o `kubelet` vigiando e o *scheduler* que deixa um Pod `Pending` |
| 6 | Publicar para fora | o `LoadBalancer` que o kind não traz (0.6.2) |
| 7 | Namespaces, permissões e rede | a rede que depende do CNI (0.3.3 e 0.6.2) |
| 8 | Dados e tarefas | o armazenamento que vive no próprio nó (0.6.2) |
| 9 | Escalar e atualizar sem interrupções | outro controlador, o que ajusta `replicas` automaticamente |
| 10 | Tudo em um único `kubectl apply -k` | o arquivo como verdade (0.4) |

## O erro que a gente vai ver

Esta lição tem um erro principal, que aparece assim que algo não estiver conectado, e um erro **sem mensagem**, que é mais perigoso.

**O erro principal: `The connection to the server localhost:8080 was refused`.** No final do percurso apagou-se o cluster e tentou-se usá-lo:

```text
$ kubectl config current-context
error: current-context is not set

$ kubectl get nodes
E1021 01:52:19.535319   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.535953   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.536970   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.537419   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
E1021 01:52:19.538619   95580 memcache.go:381] "Couldn't get current server API group list" err="Get \"http://localhost:8080/api?timeout=32s\": dial tcp [::1]:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
```

Lê-se de baixo para cima, porque a última linha é o resumo: “a conexão ao servidor `localhost:8080` foi recusada; o host ou a porta foram indicados corretamente?”. As cinco linhas com `E1021` são novas tentativas, uma por tentativa de descobrir que tipos de objeto existem; dizem o mesmo e podem ser ignoradas.

A pista está no primeiro comando: **não há contexto ativo**. Um **contexto** é a entrada do arquivo de configuração do `kubectl` (o `kubeconfig`) que diz com qual cluster falar e com qual credencial. O `kind` adicionou um ao criar o cluster e o removeu ao apagá-lo. Sem contexto, o `kubectl` não sabe para onde ir e tenta um endereço padrão, `localhost:8080`, onde não há ninguém. A mensagem não quer dizer “o cluster caiu”: quer dizer **“não sei qual é o cluster”**. Corrige-se informando um contexto, que neste curso é sempre o criado pelo `kind` (Lição 1).

**O erro sem mensagem: o contexto errado.** Agora imagine o contrário: existe contexto, mas não é o esperado. O computador tem configurado um cluster do trabalho, da faculdade ou de um projeto anterior, e esse é o ativo. Digita-se `kubectl delete deployment revisor` pensando no kind local. O cluster responde `deployment.apps "revisor" deleted`, sem erro, sem aviso. Foi apagado **em outro lugar**.

Esse erro não pode ser lido porque não produz mensagem. Só se previne com um hábito: **antes de cada comando que altera algo, `kubectl config current-context`**. No percurso, a resposta foi esta, e só depois de vê-la seguiu-se adiante:

```text
$ kubectl config current-context
kind-curso-k8s-l0
```

O script `recorrido.sh` faz isso sozinho: antes de cada `kubectl`, compara o contexto ativo com `kind-curso-k8s-l0` e, se não coincidir, para. Além disso, entrega ao kind um arquivo `kubeconfig` próprio e temporário, de modo que a configuração habitual da máquina nem é tocada. E só apaga o que ele mesmo criou: se ao começar já existir um cluster chamado `curso-k8s-l0`, ele para sem mexer nele, e se falhar no meio do caminho, ao sair apaga unicamente o cluster que aquela execução chegou a criar. A Lição 1 ensina a fazer o mesmo manualmente.

## O hábito de segurança da lição: contra o que um cluster local protege e contra o que não protege

A tabela de hábitos do curso atribui a esta lição um só: **saber contra o que um cluster local protege e contra o que não protege**. O percurso olhou três coisas.

**Primeira: o servidor da API só escuta na própria máquina.**

```text
$ docker inspect curso-k8s-l0-control-plane --format 'privilegiado={{.HostConfig.Privileged}}  puerto_api={{json .NetworkSettings.Ports}}'
privilegiado=true  puerto_api={"6443/tcp":[{"HostIp":"127.0.0.1","HostPort":"60004"}]}
```

A porta 6443 do nó, onde o `kube-apiserver` atende, é publicada em `127.0.0.1`: o endereço que só é alcançável a partir do próprio computador. Ninguém na rede local consegue falar com o cluster. O guia de configuração do kind diz que é possível alterar isso, e desaconselha com firmeza: recomenda deixar `127.0.0.1` “por razões de segurança” e “não expor o kind a nada que não seja a interface de loopback local” ([kind, “Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/)). Contra o que ele protege: o acesso vindo de fora.

**Segunda: o `kubeconfig` é a chave mestra.**

```text
$ kubectl auth whoami
ATTRIBUTE                                           VALUE
Username                                            kubernetes-admin
Groups                                              [kubeadm:cluster-admins system:authenticated]
```

(A linha `Extra` com o *digest* da credencial foi omitida aqui; está em `recorrido.salida.txt`.) O usuário com o qual se trabalha é `kubernetes-admin`, do grupo `kubeadm:cluster-admins`: **administrador total** do cluster. A credencial vive no `kubeconfig`, nos campos `client-certificate-data` e `client-key-data`, que o `kubectl config view` oculta com `DATA+OMITTED` justamente porque são segredos. Em um cluster local o dano possível é menor, mas o `kubeconfig` continua sendo uma credencial de administrador, e em um cluster real equivale à senha de administrador: nos dois casos não se copia em um chat nem se sobe para um repositório. A Lição 7 cria uma conta com permissões mínimas para o `revisor`, porque o `revisor` não deve ter essa chave.

**Terceira: o nó é um contêiner privilegiado.** O mesmo `docker inspect` diz `privilegiado=true`. Para que um contêiner possa se passar por uma máquina completa, com `systemd` e `containerd` próprios, ele precisa de quase todos os poderes do host. Isso quer dizer que **o kind não é uma fronteira de segurança**: um cluster do kind não isola do computador aquilo que rodar lá dentro. O que ele não protege: a máquina local contra o que for colocado no cluster. Por isso, neste curso, no kind só rodam imagens conhecidas: a do `revisor`, a do serviço de teste e as oficiais do Kubernetes.

As três juntas dão a regra: um cluster do kind é bem protegido **para fora** e não protege nada **para dentro**. É um laboratório, não um cofre.

## O que se faz errado

**Apagar um Pod para “desligar” algo.** O ReplicaSet o repõe em um segundo, como visto em 0.2.4. Para desligar, muda-se o estado desejado (`replicas: 0`) ou apaga-se o Deployment.

**Executar comandos imperativos sobre algo gerenciado com arquivos.** Um `kubectl scale` ou um `kubectl edit` sobre um objeto que vive no Git dura até o próximo `apply`, e a próxima pessoa que aplicar não saberá que aquilo existiu. Se a mudança vale, ela é feita no arquivo.

**Aplicar sem olhar o `kubectl diff`.** É a única forma de saber o que vai mudar antes que mude. Custa um comando.

**Não conferir o contexto.** É o erro sem mensagem de “O erro que a gente vai ver”. Em uma máquina com um único cluster parece desnecessário; assim que existem dois, é a diferença entre um experimento e um incidente.

**Acreditar que o kind demonstra produção.** O fato de o serviço aguentar no kind a queda de um “nó” não diz nada sobre como ele aguenta a queda de uma máquina real, nem a carga real, nem um disco real. O kind demonstra que se entende a API.

**Confiar no ✓ verde.** `kind create cluster` disse `✓ Joining worker nodes` com dois nós que nunca chegaram a se juntar ao cluster (0.6.3). Depois de criar algo, olha-se o estado.

**Digitar manualmente o nome de um Pod.** O sufixo é aleatório e muda toda vez que o Pod renasce. Busca-se por rótulo (`-l app=...`).

**Copiar um tutorial sem olhar a data.** O Kubernetes muda três vezes por ano. O que foi aposentado continua na internet: tutoriais que instalam o Docker dentro dos nós (o dockershim foi removido na 1.24) ou que usam `ingress-nginx`, que o projeto Kubernetes aposentou em março de 2026: sem versões novas nem correções de segurança ([kubernetes.io, “Ingress NGINX Retirement”](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)). A Lição 6 explica o que é usado no lugar.

## Exercícios

Os exercícios desta lição não exigem um cluster. O primeiro e o segundo são respondidos lendo as saídas da lição; o terceiro é respondido **antes** de rodar qualquer coisa e conferido depois da Lição 1 com `ejercicio3.sh`; o quarto é escrito com as próprias palavras. Anote as respostas no [diário de bordo](bitacora.md) antes de olhar as soluções.

### Exercício 1 — A noite de sexta-feira (projeto)

Volte à cena do início. Para cada uma destas coisas que se perderam com o servidor, diga que objeto ou peça do Kubernetes a teria guardado ou resolvido, usando o mapa de 0.5:

1. Que houvesse três cópias do `revisor` e não uma.
2. Que, ao cair a máquina, alguém subisse as cópias em outra.
3. As variáveis de ambiente com a lista de serviços a revisar.
4. A porta pela qual se fala com ele.
5. “Como estava rodando”, que vivia no histórico de um terminal.

### Exercício 2 — Quem fez isso?

Para cada um destes fatos do percurso, diga que peça de 0.3 é a responsável:

1. Salvou-se o Deployment `espera` e o `kubectl` respondeu `created`.
2. Apareceu o ReplicaSet `espera-68b9d575f7`.
3. Cada um dos três Pods ficou alocado ao nó `curso-k8s-l0-control-plane`.
4. Os contêineres dos Pods iniciaram dentro do nó.
5. Ao apagar `espera-68b9d575f7-9gbtr`, apareceu `espera-68b9d575f7-fjx8v`.
6. O Pod `kube-apiserver-curso-k8s-l0-control-plane` existia antes que houvesse um servidor da API que o criasse.

### Exercício 3 — Preveja antes de rodar

Sem rodar nada, preveja o que o cluster responde em cada caso. Depois da Lição 1, confira com `programas/00-que-es-kubernetes/ejercicio3.sh`, que cria um cluster de teste, executa os quatro casos e o apaga.

1. O Deployment `espera` tem `replicas: 3`. Apagam-se **os três** Pods com `kubectl delete pods -l app=espera`. Quantos Pods existem dez segundos depois?
2. Executa-se `kubectl scale deployment espera --replicas=1` e depois `kubectl apply -f fig00_02.deployment.yaml`. Quantas réplicas ficam?
3. Executa-se `kubectl delete deployment espera`. O que acontece com o ReplicaSet e com os Pods?
4. Apaga-se o cluster com `kind delete cluster --name curso-k8s-l0` e executa-se `kubectl get pods`. Que mensagem é esperada?

### Exercício 4 — O kind em cinco frases

Uma colega pergunta: “se no notebook o `revisor` no kind sobrevive quando eu desligo um nó, já posso dizer que em produção ele também sobrevive?”. Responda em no máximo cinco frases, usando as palavras *contêiner*, *kernel*, *API* e *produção*. Sem olhar a lição.

## Soluções

### Solução 1

1. **Três cópias:** o campo `replicas: 3` de um **Deployment**; o **ReplicaSet** que ele cria é quem conta para que sejam três.
2. **Subi-las em outra máquina:** o **ReplicaSet** repõe os Pods que faltam, o **`kube-scheduler`** escolhe um nó vivo para cada um e o **`kubelet`** desse nó os inicia. Com a espera de 300 segundos de 0.2.5, salvo se houver réplicas em outros nós que continuem atendendo enquanto isso.
3. **As variáveis de ambiente:** um **ConfigMap** (e um **Secret** se alguma for confidencial), Lição 4.
4. **A porta:** um **Service**, Lição 3.
5. **“Como estava rodando”:** o **manifesto**, salvo em um arquivo e no Git, e aplicado com `kubectl apply`. É a resposta que mais importa: o conhecimento deixa de viver em uma pessoa ou em um terminal e fica escrito. O cluster o guarda no `etcd`, e a equipe o guarda no repositório, de modo que pode ser reconstruído mesmo que se perca o cluster inteiro.

### Solução 2

1. O **`kube-apiserver`**, que valida o objeto e o salva no **`etcd`**.
2. O controlador de Deployments, dentro do **`kube-controller-manager`**.
3. O **`kube-scheduler`**. (Em um cluster de um único nó não há muito o que escolher, mas quem toma a decisão é ele mesmo assim.)
4. O **`kubelet`** do nó, que pede isso ao *runtime*, **`containerd`**.
5. O controlador de ReplicaSets, dentro do **`kube-controller-manager`**. Ele deixou isso registrado no evento `SuccessfulCreate`.
6. O **`kubelet`**, a partir do arquivo `/etc/kubernetes/manifests/kube-apiserver.yaml`: é um **Pod estático** (0.3.4).

### Solução 3

As quatro foram medidas com `ejercicio3.sh`; a saída completa está em `ejercicio3.salida.txt`.

1. **Três.** O ReplicaSet vê zero Pods onde deve haver três e cria três novos, com sufixos novos. Apagar todos não muda o estado desejado. Na execução, os três apagados foram `khb2n`, `phxml` e `srfng`, e dez segundos depois havia três diferentes: `kcvgl`, `qbnbx` e `qz6pc`.
2. **Três.** O comando imperativo baixou para uma, mas `replicas: 3` está no arquivo, e o `apply` volta a impor esse valor, igual ao que aconteceu em 0.4.2 com cinco. Se antes do `apply` for executado `kubectl diff -f fig00_02.deployment.yaml`, aparece `-  replicas: 1` / `+  replicas: 3`.
3. **Apagam-se os três níveis.** O ReplicaSet pertence ao Deployment e os Pods pertencem ao ReplicaSet; ao apagar o dono, o Kubernetes apaga o que depende dele. Cinco segundos depois, `kubectl get replicaset,pods -l app=espera` respondeu `No resources found in default namespace.` Aqui sim o serviço é desligado, porque desaparece o estado desejado.
4. `The connection to the server localhost:8080 was refused - did you specify the right host or port?`, precedido de várias linhas `E…` de novas tentativas. O kind removeu o contexto ao apagar o cluster, e sem contexto o `kubectl` tenta `localhost:8080`. Atenção: o script usa um `kubeconfig` próprio no qual só existia o cluster do curso. Se no `kubeconfig` habitual houver outros clusters configurados, a resposta depende de qual ficar ativo, e corre-se o risco de estar falando com outro sem saber: por isso confere-se com `kubectl config current-context` e não se supõe.

### Solução 4

Uma resposta possível: “Ainda não. No kind, cada nó é um *contêiner* no notebook, de modo que os três nós compartilham o disco, a memória e o *kernel* da máquina: desligar um se parece com perder uma máquina, mas se o notebook cair, cai tudo. O que ficou demonstrado é que a configuração da *API* está correta: as réplicas, a distribuição e a reposição funcionam igual em qualquer Kubernetes. Para afirmar isso em *produção*, falta testar em máquinas separadas de verdade, com rede, discos e carga reais. O kind demonstra que a gente entende o funcionamento; produção se demonstra em produção”.

## Como sei que consegui

- [ ] Explicar, com a cena de sexta-feira, por que `--restart always` não basta quando a máquina cai.
- [ ] Desenhar de memória o plano de controle e um nó, com as sete peças, e dizer o que cada uma faz em uma frase.
- [ ] Contar os sete passos de 0.3.5, do `kubectl apply` ao contêiner rodando.
- [ ] Saber por que o `kube-apiserver` pode ser um Pod sem que ninguém peça à API que o crie.
- [ ] Diante de `kubectl scale` seguido de `kubectl apply`, prever que número de réplicas fica.
- [ ] Traduzir pelo menos cinco conceitos do Docker para o Kubernetes e nomear um sem equivalente.
- [ ] Dizer duas coisas que um cluster do kind demonstra e três que não demonstra.
- [ ] Diante de `The connection to the server localhost:8080 was refused`, dizer o que significa sem procurar.
- [ ] Depois da Lição 1, executar `programas/00-que-es-kubernetes/recorrido.sh` e conferir contra `recorrido.salida.txt` o que não muda entre execuções: um nó `Ready`; o Deployment em `3/3` e o respectivo ReplicaSet com `3` desejados, `3` atuais e `3` prontos; três Pods `Running` depois de apagar um; o `diff` que mostra `replicas: 5` versus `replicas: 3`; o usuário `kubernetes-admin`; e o erro final `localhost:8080`. Os nomes gerados, as idades, os IPs, as portas, os eventos, o progresso do `kind` e do `rollout` e os caminhos temporários mudam a cada execução: observam-se, não se comparam.

## Resumo

Responda sem olhar a lição:

1. Que pergunta o Docker responde e que pergunta o Kubernetes responde?
2. O que é um ciclo de controle? Explique com o termostato.
3. Que diferença há entre um Deployment, um ReplicaSet e um Pod?
4. O que o `kubectl apply` responde quando cria um Deployment, e por que essa resposta não quer dizer que existam contêineres rodando?
5. Quanto tempo o Kubernetes espera antes de repor os Pods de um nó que deixou de responder? Por que não espera zero?
6. O que é um Pod estático e quem o inicia?
7. O que acontece ao executar um comando imperativo que contradiz o arquivo e depois aplicar o arquivo?
8. O que o kernel da máquina tem a ver com um cluster de três nós do kind não subir?
9. Contra o que um cluster do kind protege, e contra o que não protege?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Overview”](https://kubernetes.io/docs/concepts/overview/): a definição do Kubernetes, a origem do nome, a abreviação K8s, o ano em que foi liberado e a lista do que o Kubernetes não é.
- [Kubernetes, “Controllers”](https://kubernetes.io/docs/concepts/architecture/controller/): o ciclo de controle, o termostato e o estado desejado versus o atual.
- [Kubernetes, “Kubernetes Components”](https://kubernetes.io/docs/concepts/overview/components/): as peças do plano de controle e dos nós, de onde saem as definições da tabela de 0.3.2.
- [Kubernetes, “Pods”](https://kubernetes.io/docs/concepts/workloads/pods/): a definição de Pod e por que quase nunca são criados sozinhos.
- [Kubernetes, “Create static Pods”](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/): os Pods estáticos que o `kubelet` lê de uma pasta.
- [Kubernetes, “Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): as tolerâncias automáticas de 300 segundos.
- [Kubernetes, “Kubernetes Object Management”](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/): comandos imperativos versus declarações, e o aviso de não misturá-las.
- [Kubernetes, “Releases”](https://kubernetes.io/releases/) e [“Kubernetes Release Cycle”](https://kubernetes.io/releases/release/): as versões vigentes, o fim do suporte e o ritmo de três por ano.
- [Kubernetes, “Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/): que versões do `kubectl` servem com qual servidor.
- [Kubernetes, “Dockershim: The Historical Context”](https://kubernetes.io/blog/2022/05/03/dockershim-historical-context/) e [“Don't Panic: Kubernetes and Docker”](https://kubernetes.io/blog/2020/12/02/dont-panic-kubernetes-and-docker/): por que os nós já não usam o Docker e por que as imagens continuam funcionando.
- [Docker, “Start containers automatically”](https://docs.docker.com/engine/containers/start-containers-automatically/): as políticas de reinício do Docker.
- [kind](https://kind.sigs.k8s.io/), [o design inicial](https://kind.sigs.k8s.io/docs/design/initial/), [“Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/), [“Known Issues”](https://kind.sigs.k8s.io/docs/user/known-issues/) e [“LoadBalancer”](https://kind.sigs.k8s.io/docs/user/loadbalancer/): o que é o kind, para que foi projetado, o endereço do servidor da API, a rede padrão, o limite de `inotify` e o balanceador que ele não traz.
- [Kubernetes, “Ingress NGINX Retirement: What You Need to Know”](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/): a aposentadoria do `ingress-nginx` em março de 2026.
- [kind v0.33.0, notas da versão](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0): a imagem de nó padrão e o respectivo *digest*.
- [Linux Mint 22, notas da versão](https://www.linuxmint.com/rel_wilma.php): o Mint 22 baseia-se no Ubuntu 24.04.

---

**Próxima:** [Lição 1 — Instalar kubectl e kind; o primeiro cluster](01-instalacion-primer-cluster.md)
