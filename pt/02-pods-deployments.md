# Lição 2 — Pods e Deployments

Segunda-feira, 8h50 da manhã. Às 9h30 a equipe tem a demonstração do cluster novo, e a parte que cabe a quem escreve é a mais simples: que o `revisor` apareça rodando, com três cópias. A imagem está no notebook desde sexta-feira, construída e testada com `docker run`. Escreve-se o manifesto, aplica-se, e o `kubectl` responde `deployment.apps/revisor created`. Respira-se. Pedem-se os Pods e os três dizem a mesma coisa: `ImagePullBackOff`. Alguém da equipe, sem erguer os olhos, diz: “apague e aplique de novo”. Faz-se isso. Mesmo estado. Faz-se outra vez. São 9h05 e a imagem continua lá, no `docker image ls`, a dois centímetros do cluster que diz não encontrá-la.

Apagar e aplicar de novo não ia adiantar nada nessa situação, porque o cluster não estava confuso: estava dizendo exatamente o que lhe faltava. Esta lição ensina a escutá-lo, a dar-lhe o que ele pede e a entender que objetos nascem quando se aplica um Deployment. Assim, quando algo falhar às 9h05, a gente sabe onde olhar.

**Tempo:** 2 × 45 min

**O que se constrói:** o `revisor` rodando no cluster do curso, com três réplicas que renascem quando morrem, endurecido (*hardening*) desde o primeiro manifesto

**O que se aprende:** por que o Docker e os nós do cluster não compartilham imagens, e como o `kind load docker-image` as leva até lá; o `ErrImagePull` que se provoca de propósito e como se interpreta; o que é um Pod, um ReplicaSet e um Deployment, e quem é dono de quem; rótulos (*labels*) e seletores; o que é um *rollout* e como se vê o histórico dele; e o `securityContext` que todo contêiner deste curso leva

**De onde a gente vem.** Da [Lição 1](01-instalacion-primer-cluster.md): estão instalados o `kubectl` e o `kind` com a soma de verificação conferida, o limite de `inotify` está ajustado e já se sabe criar, olhar e apagar o cluster de três nós do curso. Da [Lição 0](00-que-es-kubernetes.md) vem o mapa: o `kube-apiserver` guarda o que se declara, os controladores o perseguem, o `kube-scheduler` escolhe o nó e o `kubelet` inicia os contêineres. E do [curso de Docker](https://www.habil.mx/pt/cursos/docker/) vem a imagem pronta do `revisor`, `curso-docker-revisor:1.6.0`.

**O que esta lição não faz.** O `revisor` fica rodando, mas ainda ninguém consegue falar com ele: não há um nome estável para encontrá-lo nem uma forma de chegar a ele a partir da máquina local. Isso é a [Lição 3](03-services-dns.md), com os Services e o DNS do cluster. Também ainda não se configura por fora: a lista de serviços que ele verifica vai escrita no manifesto, e a [Lição 4](04-configuracion-secretos.md) a transfere para um `ConfigMap`. E o cluster ainda não sabe se o `revisor` está saudável ou apenas vivo: os *probes* chegam na [Lição 5](05-salud-recursos-apagado.md).

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com o `kind` v0.33.0, o `kubectl` v1.37.1 e a imagem de nó `kindest/node:v1.37.0` fixada pelo digest, no cluster de três nós da Lição 1, aqui chamado `curso-k8s-l2`. A máquina foi um Mac com processador ARM e Docker Engine 29.2.1 dentro de uma máquina virtual Linux (Colima), **não** Linux Mint, que é o sistema de referência do curso. O que muda no Mint: a arquitetura (`amd64` em vez de `arm64`), os endereços IP dos Pods, os sufixos aleatórios dos nomes de Pods e ReplicaSets, as idades e em que nó cai cada réplica. Os comandos são os mesmos. O percurso completo está em [`programas/02-pods-deployments/`](../programas/02-pods-deployments): o `correr.sh` cria o cluster **sem** a imagem do `revisor`, percorre a lição em ordem, executa os Exercícios 1 a 3 e apaga o cluster; levou 2 minutos e 25 segundos medidos com o relógio do terminal; o script registra por conta própria quanto levou cada passo longo: criar o cluster e esperar que ficasse pronto, 34 segundos; carregar a imagem, 2; apagá-lo, 1. A saída dele é o `correr.salida.txt`. Ali, a parte do hábito de segurança aparece antes da do *rollout* (2.8), porque o script a executa nessa ordem.

## Ao terminar, a gente vai conseguir

- Conferir com `crictl images` se uma imagem está dentro de um nó do kind, e carregá-la com `kind load docker-image`.
- Provocar um `ErrImagePull`, interpretá-lo com `kubectl describe` e `kubectl get events`, e dizer o que significa cada linha.
- Escrever de memória o esqueleto de um Deployment (`replicas`, `selector`, `template`) e explicar por que o seletor e os rótulos do template precisam coincidir.
- Seguir com `ownerReferences` a cadeia Deployment → ReplicaSet → Pod, e prever o que acontece ao apagar cada elo.
- Filtrar objetos com seletores de rótulo (`-l app=revisor`, `-l 'app in (…)'`) e explicar o que é o rótulo `pod-template-hash`.
- Ler o histórico de um Deployment com `kubectl rollout history` e provocar uma reinicialização ordenada com `kubectl rollout restart`.
- Justificar cada linha do `securityContext` do `revisor` e reconhecer o erro `CreateContainerConfigError` que uma contradição nele produz.

## O porquê antes do como

Na Lição 0 se viu um Deployment que mantinha três cópias de um contêiner que não fazia nada. Era a ideia pura: declara-se “quero três” e o cluster persegue esse número. Agora vem a versão com um programa de verdade, e aparecem três perguntas que o exemplo de brinquedo escondia.

A primeira: **de onde o cluster tira a imagem?** A da Lição 0 já vinha dentro do nó, porque o próprio Kubernetes a usa. A do `revisor` foi construída por quem faz o curso e vive no Docker dele. Um nó do kind parece estar “na máquina local”, mas por dentro tem o seu próprio armazenamento de imagens, que não é o do Docker. É a causa exata da cena de segunda-feira, e é a primeira coisa que se vai ver falhar.

A segunda: **que objetos existem e quem cuida de quem?** Um Deployment não roda contêineres. Ele cria um ReplicaSet, que cria Pods, que são os que rodam. Se essa cadeia não for vista, “apagar um Pod” e “apagar o Deployment” parecem a mesma operação, e não são: uma se repara sozinha em um segundo e a outra desliga o serviço.

A terceira: **o que o contêiner pode fazer se alguém o atacar?** Com o `docker run` se aprendeu a tirar privilégios dele com `--user`, `--read-only` e `--cap-drop ALL`. No Kubernetes essas mesmas decisões são escritas no manifesto, em um bloco chamado `securityContext`, e este curso as põe desde o primeiro Deployment. Elas não esperam pela Lição 7. A segurança que se acrescenta no final fica numa lista de pendências; a que nasce com o manifesto viaja com ele para qualquer cluster.

A lição tem oito partes de conceitos e depois as seções de sempre:

1. **Dois armazenamentos de imagens** (2.1): o Docker e o de cada nó.
2. **O manifesto do `revisor`, campo por campo** (2.2).
3. **Aplicar e não encontrar a imagem** (2.3), o erro de propósito.
4. **`kind load docker-image`** (2.4) e o cluster que se recupera sozinho.
5. **A cadeia de donos** (2.5): Deployment, ReplicaSet e Pod.
6. **Rótulos e seletores** (2.6).
7. **Um Pod avulso versus um Pod do Deployment** (2.7).
8. **O *rollout*** (2.8): revisões, histórico e reinicialização.

Este é o destino. No final de 2.4, o `revisor` está rodando com três réplicas, em um cluster que meio minuto antes não tinha a imagem dele:

```text
$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           32s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-697fb84f97   3         3         3       32s
```

## Se a imagem do curso de Docker não estiver à mão

Esta lição usa a imagem entregue pela Lição 10 do curso de Docker, `curso-docker-revisor:1.6.0`. Antes de seguir, convém conferir se ela existe:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Se não existir, construa-a a partir do repositório daquele curso, com o `Dockerfile` da Lição 10 sobre a pasta `programas/revisor` e com `--build-arg VERSION=1.6.0`, dando-lhe exatamente a tag `curso-docker-revisor:1.6.0`. Se for usada outra imagem, de um serviço próprio, isto é o que o curso exige dela, e convém ler porque cada ponto explica uma decisão do manifesto:

- **Escuta HTTP em uma porta alta**, a 8080, e responde `GET /salud` sem consultar mais ninguém.
- **Roda com um usuário numérico que não é `root`**: o 65532, o usuário `nonroot` das imagens *distroless*. O manifesto exige isso com `runAsNonRoot: true`.
- **Funciona com o sistema de arquivos somente leitura**, exceto uma pasta de dados (`/datos`), que o manifesto monta à parte.
- **Traz o próprio verificador de saúde (*health check*)** como subcomando (`/revisor healthcheck`), porque a imagem não tem *shell* nem `curl`.
- **Tem uma tag fixa**, nunca `:latest`. A seção 2.2.3 explica por que isso importa no kind.
- **Configura-se por variáveis de ambiente.** O `revisor` exige `REVISOR_SERVICIOS`, com a lista de serviços que verifica, e entende `REVISOR_PUERTO`, `REVISOR_REPORTE` e `REVISOR_TOKEN_ARCHIVO`. Uma variável que ele não lê é ignorada em silêncio, então não se devem inventar outras.

## Os conceitos

### 2.1 Dois armazenamentos de imagens

Esta lição usa o seu próprio cluster, `curso-k8s-l2`, com a configuração de três nós da Lição 1, recém-criado e **sem** nada carregado nele. Cria-se assim, a partir da raiz do repositório do curso, com o mesmo cuidado aprendido na Lição 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l2.XXXX)/kubeconfig"
# curso-k8s-l2 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l2 --config programas/02-pods-deployments/kind-curso.yaml
# Debe decir kind-curso-k8s-l2. Si dice otra cosa, no sigas.
kubectl config current-context
```

O `export` só vale naquele terminal. Se for aberto outro, é preciso repetir o `export` com o mesmo caminho, ou o `kubectl` falará com outro cluster. As saídas desta seção são da execução do `correr.sh`, que faz exatamente isso:

```text
$ kubectl config current-context
kind-curso-k8s-l2

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l2-control-plane   Ready    control-plane   26s   v1.37.0
curso-k8s-l2-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l2-worker2         Ready    <none>          16s   v1.37.0
```

O primeiro comando não é decoração. É o hábito da Lição 1: antes de mudar algo, perguntar a que cluster se está falando. Nesta lição vão ser criados e apagados objetos, e `kind-curso-k8s-l2` é a única resposta que deixa seguir. Repete-se **antes de cada** `apply`, `delete`, `label` ou `rollout restart` da lição, não só aqui. O script faz isso sozinho: antes de cada `kubectl`, compara o contexto e para se não for `kind-curso-k8s-l2`.

Agora a pergunta da cena. O Docker tem a imagem; o nó a tem? Lembre-se da Lição 0: um nó do kind é um contêiner que traz dentro o seu próprio `containerd`, e esse `containerd` tem o seu próprio armazenamento de imagens. Para perguntar a ele, entra-se no nó e usa-se o `crictl`, a ferramenta de linha de comando que fala com o *runtime* do nó. O guia de início do kind a recomenda justamente para isso ([kind, “Quick Start”, seção “Loading an Image Into Your Cluster”](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)):

```text
$ docker exec curso-k8s-l2-worker crictl images | grep -c curso-docker-revisor
0
[código de salida: 1]
```

Zero. (O código de saída 1 é do `grep`, que assim avisa que não encontrou nada; não é uma falha do nó.) A imagem está na máquina e não está no nó. São dois armazenamentos distintos, embora os dois vivam no mesmo computador, e nada os sincroniza.

Em um cluster de verdade isso se resolve com um **registry**: sobe-se a imagem para um servidor de imagens (Docker Hub, o registry da empresa ou o do provedor de nuvem) e cada nó a baixa de lá. No kind, que é um laboratório na máquina local, há um atalho: copiar a imagem direto do Docker para cada nó. Esse atalho é o `kind load docker-image` e chega em 2.4. Primeiro vai-se ver o que acontece sem ele, porque a mensagem de erro é das que mais se encontram na vida com o Kubernetes.

### 2.2 O manifesto do `revisor`, campo por campo

Este é o manifesto que a lição constrói. É um **programa**: aplica-se sozinho e vive em `programas/02-pods-deployments/revisor-deployment.yaml`.

```yaml
# revisor-deployment.yaml — Lección 2: el revisor con tres réplicas que renacen.
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
          value: "prueba http://prueba:9000/ 2s"
        # La imagen de Docker trae REVISOR_REPORTE=/datos/reporte.json: con el
        # sistema de archivos de solo lectura, /datos necesita un volumen. emptyDir
        # vive y muere con el Pod (la Lección 8 lo contrasta con un PVC).
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
        emptyDir:
          sizeLimit: 10Mi
```

Parece muito. Lê-se por camadas, de fora para dentro, e cada camada responde a uma pergunta.

#### 2.2.1 O que é e como se chama

As três primeiras chaves todo objeto do Kubernetes leva. `apiVersion: apps/v1` diz em que grupo da API vive o tipo: os Deployments vivem no grupo `apps`, versão `v1`, que é estável. `kind: Deployment` diz o tipo. E `metadata` traz o nome (`revisor`) e os rótulos do próprio Deployment (`app: revisor`). O nome é único dentro do seu namespace; os rótulos, como se verá em 2.6, não são, e esse é justamente o valor deles.

#### 2.2.2 Quantos, quais e com que modelo

`spec` é o estado desejado, e em um Deployment tem três peças que andam juntas:

- **`replicas: 3`**: quantas cópias se quer. É o número que o cluster persegue.
- **`selector`**: como o Deployment reconhece **os seus** Pods. Aqui diz: “os meus são os que levam o rótulo `app: revisor`”.
- **`template`**: o modelo de cada Pod. Leva os seus próprios rótulos (`app: revisor`) e a sua própria `spec`, que é a de um Pod: contêineres, volumes e segurança.

O seletor e os rótulos do template **precisam coincidir**. Se o modelo produzisse Pods com `app: outro` e o seletor procurasse `app: revisor`, o Deployment criaria Pods que nunca reconheceria como seus e continuaria criando mais, sem fim. Por isso o `kube-apiserver` rejeita um Deployment cujo seletor não coincide com os rótulos do template, antes de guardá-lo. A [documentação de Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) acrescenta um aviso que convém ter presente desde já: o Kubernetes não impede que dois controladores tenham seletores que se sobrepõem, e, se os tiverem, “podem entrar em conflito e se comportar de forma inesperada”. O Exercício 2 mostra uma versão desse problema.

#### 2.2.3 O contêiner

Dentro do template, `containers` é uma lista; neste curso sempre traz um único contêiner. Os campos dele:

- **`name: revisor`**: o nome do contêiner dentro do Pod. Aparecerá nos eventos como `spec.containers{revisor}`.
- **`image: curso-docker-revisor:1.6.0`**: a imagem, com a tag fixa.
- **`imagePullPolicy: IfNotPresent`**: quando baixar a imagem. `IfNotPresent` significa “baixe somente se ela ainda não estiver no nó”. A [documentação de imagens](https://kubernetes.io/docs/concepts/containers/images/) define também `Always` (consultar o registry toda vez que um contêiner inicia; o *runtime* só baixa as camadas que faltam, mas, se o registry não responder ou não tiver a imagem, falha mesmo que o nó já a tenha) e `Never` (nunca tentar baixá-la). Se o campo for omitido, o Kubernetes o decide pela tag: com uma tag que não é `:latest` põe `IfNotPresent`, e com `:latest` ou sem tag põe `Always`. É isso que faz de `:latest` uma armadilha no kind: com `Always`, o nó tentaria ir ao Docker Hub mesmo que a imagem já tivesse sido carregada nele, e falharia. O guia do kind avisa: com `:latest` ou sem tag a política padrão é `Always`, e pede para não usar `:latest` ou escrever `imagePullPolicy: IfNotPresent` (ou `Never`) ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)). O manifesto escreve `IfNotPresent` embora fosse o valor padrão, para que quem o leia não precise saber a regra de cor.
- **`ports`**: declara que o contêiner escuta na 8080 e dá a ela um nome, `http`. Declarar não publica nada nem abre porta nenhuma para fora: é informação para quem lê o manifesto e para os objetos que o usarão depois. Na Lição 3, o Service apontará para a porta **pelo nome**, `http`, e não pelo número.
- **`env`**: as variáveis de ambiente. Aqui vai uma só, `REVISOR_SERVICIOS`, a que o `revisor` exige, com um serviço chamado `prueba` em `http://prueba:9000/` e um tempo limite de 2 segundos. Esse serviço ainda não existe no cluster, e não importa: o `revisor` inicia do mesmo jeito e vai reportá-lo com o estado `FALLA` quando alguém pedir o relatório. Na Lição 4 essa lista sai do manifesto e passa para um `ConfigMap`.

#### 2.2.4 O volume `datos`

No final há um volume, `datos`, do tipo `emptyDir`, montado em `/datos`. Está ali por uma razão concreta. A imagem do curso de Docker define `REVISOR_REPORTE=/datos/reporte.json`: cada vez que alguém lhe pede o relatório, o `revisor` o guarda nesse arquivo. Mas o `securityContext` do contêiner (2.2.5) põe **todo** o sistema de arquivos dele em somente leitura. Sem um volume, o `revisor` iniciaria sem reclamar e falharia depois, na primeira vez que tentasse guardar um relatório: no código dele, esse caso responde com um erro 500 e a mensagem `no pude guardar el reporte`.

Um `emptyDir` é a forma mais simples de dar um lugar onde escrever. A [documentação de volumes](https://kubernetes.io/docs/concepts/storage/volumes/) o descreve assim: é criado quando o Pod é atribuído a um nó, começa vazio e “quando um Pod é removido de um nó por qualquer razão, os dados do `emptyDir` são apagados para sempre”. Se o contêiner cair e reiniciar, os dados sobrevivem, porque o Pod continua no nó. O `sizeLimit: 10Mi` põe um teto: um relatório pesa alguns poucos kilobytes, e um teto evita que um erro encha o disco do nó. A Lição 8 contrasta este `emptyDir` com um volume persistente e mede o que se perde com cada um.

#### 2.2.5 Os dois `securityContext`

Há dois blocos `securityContext`: um no nível do Pod (`template.spec.securityContext`) e outro no nível do contêiner. O do Pod vale para todos os contêineres dele; o do contêiner, só para ele. A seção “O hábito de segurança da lição” os desmonta linha por linha, com o cluster mostrando o que cada um faz. Por ora basta a ideia: o contêiner roda como o usuário 65532, não pode virar `root`, não tem nenhuma capability especial do kernel, não pode escrever no próprio sistema de arquivos e fica sob o filtro de chamadas de sistema que o *runtime* traz.

### 2.3 Aplicar e não encontrar a imagem

Com o cluster recém-criado e sem a imagem carregada, aplicou-se o manifesto:

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created
```

Lembre-se da Lição 0 o que significa essa resposta: o objeto foi **guardado**. Ela não diz nada sobre contêineres. Vinte segundos depois:

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS             RESTARTS   AGE
revisor-697fb84f97-gn68x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-qvs7x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-vq4ld   0/1     ImagePullBackOff   0          20s
```

Os três Pods existem, cada um já tem nó, e nenhum roda: `0/1` em `READY` quer dizer “zero de um contêiner pronto”. O estado, `ImagePullBackOff`, é a cena de segunda-feira. Repare no que **funcionou**: o Deployment criou o seu ReplicaSet, o ReplicaSet criou três Pods e o `kube-scheduler` os distribuiu. Todo o plano de controle fez o seu trabalho. O que falhou está no final da cadeia, no `kubelet` de cada nó, que não conseguiu obter a imagem.

A seção “O erro que se vai ver” interpreta esse erro linha por linha. A versão curta, para seguir: o `kubelet` procurou a imagem no nó, não a encontrou e, como a política é `IfNotPresent`, tentou baixá-la. A imagem não diz de que registry vem, então foi ao Docker Hub, onde ela não existe. Tenta outra vez, cada vez esperando um pouco mais. Apagar e aplicar de novo não muda nada disso: o Pod novo cai em um nó que também não tem a imagem e chega ao mesmo lugar.

### 2.4 `kind load docker-image`: levar a imagem a cada nó

O remédio é dar ao nó o que ele pede:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 --name curso-k8s-l2
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-control-plane", loading...
```

O `kind` tirou a imagem do Docker e a copiou para dentro de **cada** nó do cluster, um por linha: “ainda não está no nó tal, carregando”. Aparece também o nó de controle, embora ali não rode nenhum Pod do `revisor`. O kind não sabe onde a imagem vai ser usada e a põe em todos. Levou 2 segundos, porque a imagem pesa uns 16 MB. O `--name curso-k8s-l2` é obrigatório quando o cluster não se chama `kind`, que é o nome padrão. Sem ele, o kind procuraria um cluster que não existe, e em uma máquina com vários clusters é a forma de ter certeza de que a imagem é carregada no certo e não em outro.

Agora o nó a tem:

```text
$ docker exec curso-k8s-l2-worker crictl images | grep curso-docker-revisor
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Veja o nome com que ficou guardada: `docker.io/library/curso-docker-revisor`. É o nome completo que corresponde a `curso-docker-revisor`: quando uma imagem não diz de que registry vem, entende-se que é do Docker Hub (`docker.io`) e, se tampouco diz de que usuário, do espaço de imagens oficiais dele (`library`). A documentação de imagens explica isso com o exemplo do `busybox`, que equivale a `docker.io/library/busybox:latest`. É o mesmo nome que aparecia no erro de 2.3, e por isso agora o `kubelet` a encontra. (Os números parecem diferentes, mas têm explicação. O `crictl` diz 3.68MB. Com o Docker Engine 29, `docker image ls curso-docker-revisor:1.6.0` mostra duas colunas: `DISK USAGE` 16.2MB, o que ocupa descomprimida em disco, e `CONTENT SIZE` 3.68MB, o conteúdo comprimido; o `crictl` reporta esta segunda. Se o Docker for anterior, o `docker image ls` mostra uma cifra só e pode não coincidir. O identificador do `crictl`, `70e09194319be`, tampouco é o `sha256:bd1b2e7d…` do `kind load`: cada ferramenta identifica a imagem com um resumo (digest) diferente. Que seja a mesma, provam o nome e a tag, e que o `kubelet` a encontre no passo seguinte.)

Não é preciso aplicar nada de novo. O `kubelet` continuava tentando por conta própria; na tentativa seguinte encontrou a imagem e iniciou o contêiner:

```text
$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-gn68x   1/1     Running   0          33s   10.244.1.3   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   10.244.1.2   curso-k8s-l2-worker2   <none>           <none>
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   10.244.2.2   curso-k8s-l2-worker    <none>           <none>
```

Esta é a lição de fundo da cena: **o cluster se recuperou sozinho porque o estado desejado nunca mudou**. Continuava dizendo “três réplicas com esta imagem”. A única coisa que faltava era a imagem, e assim que ela chegou, cada peça terminou o seu trabalho. Apagar e aplicar de novo teria sido, no melhor dos casos, inútil.

Olhe a coluna `NODE`. Duas réplicas ficaram em `curso-k8s-l2-worker2` e uma em `curso-k8s-l2-worker`. O Deployment cuida de **quantas** réplicas existem, não de **onde** ficam. A Lição 0 antecipou: o *scheduler* procura distribuir, mas não garante, e em outra execução podem cair de forma diferente. Se o `worker2` fosse desligado, duas das três réplicas morreriam ao mesmo tempo. A distribuição garantida se declara com regras próprias, e o curso faz isso quando o `revisor` precisar sobreviver a um nó desligado (Lição 9). Repare também na coluna `IP`: cada Pod tem a sua, e ela muda cada vez que um Pod renasce. Por isso ninguém deve falar com um Pod pelo IP dele, e por isso existe a Lição 3.

O log do `revisor` confirma que o programa iniciou:

```text
$ kubectl logs deployment/revisor
Found 3 pods, using pod/revisor-697fb84f97-gn68x
revisor 1.6.0 escuchando en :8080 (1 servicio(s))
```

`kubectl logs deployment/revisor` é um atalho: escolhe um dos Pods do Deployment e mostra o log dele, e diz qual escolheu. É a mesma linha que ele imprimia com o `docker run` no curso de Docker: a imagem é a mesma, só mudou quem a executa.

### 2.5 A cadeia de donos: Deployment, ReplicaSet e Pod

Na Lição 0 se viu a cadeia desenhada. Agora ela pode ser lida no próprio cluster, porque cada objeto diz quem é o seu dono em um campo chamado `metadata.ownerReferences`. A [documentação de donos e dependentes](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) explica assim: os objetos dependentes têm esse campo, que aponta para o dono, e o Kubernetes o preenche sozinho para os objetos que os controladores criam, como os ReplicaSets.

```text
$ kubectl get pod revisor-697fb84f97-gn68x -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ReplicaSet/revisor-697fb84f97

$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
Deployment/revisor

$ kubectl get deployment revisor -o jsonpath='{.metadata.ownerReferences}{"\n"}'

```

O Pod pertence ao ReplicaSet, o ReplicaSet pertence ao Deployment, e o Deployment não pertence a ninguém: a resposta dele é uma linha vazia. O Deployment foi escrito por quem faz o curso, e o dono é essa pessoa.

A opção `-o jsonpath=…` merece um momento, porque o curso a usa muito. O `kubectl get` pode devolver o objeto completo (`-o yaml`), mas quase sempre se quer um único valor. O `jsonpath` permite pedir um campo pelo caminho dele: `{.metadata.ownerReferences[0].kind}` significa “do objeto, entre em `metadata`, depois em `ownerReferences`, pegue o primeiro elemento e me dê o `kind` dele”. O `{"\n"}` do final apenas acrescenta uma quebra de linha.

Cada elo tem um trabalho diferente:

| Objeto | Quem o cria | Seu trabalho | Se for apagado |
|---|---|---|---|
| **Deployment** | quem faz o curso | guardar o estado desejado e administrar versões: quando o template muda, cria um ReplicaSet novo e passa as réplicas do antigo para o novo | os ReplicaSets e os Pods dele são apagados; o serviço é desligado |
| **ReplicaSet** | o Deployment | contar: que haja tantos Pods com o template exato dele quanto diz `replicas` | o Deployment cria outro igual, mas o `kubectl delete` apaga em cascata os Pods dele: medido, os três Pods passaram a `Terminating` ao mesmo tempo e o substituto começou do zero, com uma interrupção; por isso não se mexe neles manualmente |
| **Pod** | o ReplicaSet | rodar o contêiner | o ReplicaSet cria outro |

A [documentação de ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/) define o propósito dele em uma frase: “manter um conjunto estável de Pods réplica rodando a todo momento”. E recomenda não usá-los diretamente: “recomendamos usar Deployments em vez de ReplicaSets diretamente”, salvo casos especiais. A de Deployments é ainda mais taxativa: “não administre ReplicaSets que pertencem a um Deployment”. Neste curso nunca se vai escrever um ReplicaSet. Vão ser **vistos**, porque lê-los explica o que o Deployment faz.

E o Pod? A [documentação de Pods](https://kubernetes.io/docs/concepts/workloads/pods/) diz sem rodeios: “raramente se criam Pods individuais diretamente no Kubernetes, nem sequer Pods solitários”, porque os Pods são projetados como entidades “relativamente efêmeras e descartáveis”. A seção 2.7 mostra o que quer dizer “descartável” com um Pod sem dono.

### 2.6 Rótulos e seletores

Até aqui se escreveu `-l app=revisor` muitas vezes. É o momento de ver o que há por trás.

Um **rótulo** (*label*) é um par chave e valor colado a um objeto. A [documentação de rótulos](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) os define como pares que “servem para especificar atributos identificadores dos objetos, significativos para os usuários”, e acrescenta o que os torna úteis: “ao contrário dos nomes e dos UIDs, os rótulos não são únicos”. Muitos objetos levam o mesmo. Com um **seletor** de rótulos escolhe-se um conjunto de objetos, e, segundo a mesma página, o seletor é “a primitiva central de agrupamento no Kubernetes”.

Assim se veem os rótulos dos Pods do `revisor`:

```text
$ kubectl get pods --show-labels
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
revisor-697fb84f97-gn68x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
```

`app=revisor` foi colocado por quem escreveu o manifesto, no template. Mas há outro que ninguém escreveu: `pod-template-hash=697fb84f97`. Quem o pôs foi o Deployment, e o número é o mesmo sufixo que o nome do ReplicaSet leva. Veja o seletor do ReplicaSet:

```text
$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.spec.selector}{"\n"}'
{"matchLabels":{"app":"revisor","pod-template-hash":"697fb84f97"}}
```

O ReplicaSet não busca só `app: revisor`: busca `app: revisor` **e** `pod-template-hash: 697fb84f97`. A documentação de Deployments explica por quê: o controlador de Deployments adiciona esse rótulo a cada ReplicaSet que cria, calculado com um *hash* do template do Pod, e “esse rótulo garante que os ReplicaSets filhos de um Deployment não se sobreponham”. Quando o template mudar, em 2.8, aparecerá outro ReplicaSet com outro *hash*. Cada um contará somente os seus próprios Pods, ainda que todos levem `app=revisor`. A mesma página traz um aviso em vermelho: “não altere este rótulo”.

Os seletores têm duas formas. A de **igualdade** é a que se tem usado: `app=revisor`, ou `app!=revisor` para o contrário. A de **conjuntos** pergunta por pertencimento:

```text
$ kubectl get pods -l 'app in (revisor,prueba)' -o name
pod/revisor-697fb84f97-gn68x
pod/revisor-697fb84f97-qvs7x
pod/revisor-697fb84f97-vq4ld

$ kubectl get pods -l app=prueba
No resources found in default namespace.
```

O primeiro pede os Pods cujo rótulo `app` seja `revisor` ou `prueba`, e como ainda não há nenhum `prueba`, devolve só os do `revisor`. O segundo confirma. Duas regras da documentação para não errar: vários requisitos separados por vírgula se combinam com “e” (`app=revisor,pod-template-hash=697fb84f97` exige os dois), e **não existe** operador “ou” entre requisitos distintos. Para um “ou” sobre uma mesma chave existe o `in`.

`No resources found` não é um erro. É uma resposta: não há nada que coincida. Distinguir “não há nada” de “algo falhou” faz parte de interpretar o que diz o cluster.

Por que o curso busca sempre por rótulo e nunca pelo nome do Pod? Porque o nome muda cada vez que o Pod renasce, e o rótulo não. Um comando que escreve `revisor-697fb84f97-gn68x` deixa de servir assim que esse Pod morre. Um que escreve `-l app=revisor` continua funcionando através das substituições, dentro do mesmo namespace e enquanto nenhum outro Pod usar esse rótulo (o Exercício 2 mostra o que acontece quando algum usa). Os Services da Lição 3 escolhem os seus Pods do mesmo modo: por rótulo. Isso torna importante o que o Exercício 2 mostra.

### 2.7 Um Pod avulso versus um Pod do Deployment

#### 2.7.1 O Pod avulso

Um Pod pode ser criado sozinho, sem Deployment. Este manifesto é um **programa** (`fig02_01.pod.yaml`). É o mesmo template do Deployment, mas escrito como Pod, com nome fixo e **sem** o rótulo `app: revisor`, para que nenhum ReplicaSet o confunda com um dos seus:

```yaml
# fig02_01.pod.yaml — un Pod suelto: el revisor sin Deployment que lo cuide.
# Sirve para ver qué hace un Pod por sí solo, y qué NO hace: si lo borras, nadie
# lo repone. No lleva etiqueta app: revisor a propósito, para que ningún
# ReplicaSet lo confunda con uno de los suyos.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-suelto
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
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
      value: "prueba http://prueba:9000/ 2s"
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
    emptyDir:
      sizeLimit: 10Mi
```

Repare na diferença em relação ao Deployment: `apiVersion: v1` (os Pods vivem no grupo central da API, que não leva nome) e `kind: Pod`. O que no Deployment estava dentro de `template.spec`, aqui está direto em `spec`. Um Deployment é, em boa parte, um modelo de Pod com um contador por cima.

```text
$ kubectl apply -f fig02_01.pod.yaml
pod/revisor-suelto created

$ kubectl get pod revisor-suelto -o jsonpath='{.metadata.name} dueños={.metadata.ownerReferences}{"\n"}'
revisor-suelto dueños=

$ kubectl delete pod revisor-suelto
pod "revisor-suelto" deleted from default namespace

$ kubectl get pods
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-gn68x   1/1     Running   0          40s
revisor-697fb84f97-qvs7x   1/1     Running   0          40s
revisor-697fb84f97-vq4ld   1/1     Running   0          40s
```

`dueños=` vazio: ninguém é dono deste Pod. Foi apagado, o script esperou cinco segundos e o `revisor-suelto` já não existe. Ninguém o repôs, porque nenhum controlador tinha “quero um `revisor-suelto`” no seu estado desejado.

Atenção ao que um Pod avulso **faz**. Se o seu **processo** cair, o `kubelet` o inicia de novo dentro do mesmo Pod, porque o campo `restartPolicy` vale `Always` por padrão ([kubernetes.io, “Pod Lifecycle”](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). Parece um `docker run --restart always` em uma única máquina: aguenta que o programa falhe, e a coluna `RESTARTS` conta isso. O que não aguenta é perder o próprio Pod. A documentação de Pods diz que um Pod permanece no seu nó “até que termine, o objeto Pod seja apagado, seja removido por falta de recursos ou o nó falhe”, e a do ciclo de vida acrescenta que um Pod nunca é “reprogramado” em outro nó: em vez disso, alguém pode criar um novo quase idêntico. Em um Pod avulso, esse alguém não existe. Se for apagado, removido ou se o nó dele for desligado, acabou.

#### 2.7.2 O Pod do Deployment

Agora o mesmo com um Pod que tem dono:

```text
$ kubectl delete pod revisor-697fb84f97-gn68x
pod "revisor-697fb84f97-gn68x" deleted from default namespace

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-nrwht   1/1     Running   0          1s
revisor-697fb84f97-qvs7x   1/1     Running   0          41s
revisor-697fb84f97-vq4ld   1/1     Running   0          41s

$ kubectl get events --field-selector involvedObject.kind=ReplicaSet,reason=SuccessfulCreate -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message
OBJETO               MENSAJE
revisor-697fb84f97   Created pod: revisor-697fb84f97-vq4ld
revisor-697fb84f97   Created pod: revisor-697fb84f97-gn68x
revisor-697fb84f97   Created pod: revisor-697fb84f97-qvs7x
revisor-697fb84f97   Created pod: revisor-697fb84f97-nrwht
```

Um segundo depois há um Pod novo, `nrwht`, e os eventos contam a história: três criações no começo e uma quarta, a reposição. É o termostato da Lição 0, agora com um programa de verdade.

`-o custom-columns=…` é a irmã do `jsonpath` para tabelas: diz-se quais colunas se quer e de que campo sai cada uma. Foi usada aqui para que cada evento coubesse em uma linha.

A comparação é a ideia mais importante da lição: **o Pod roda, mas quem o repõe é o dono dele.** Um Pod sem dono reinicia o contêiner se o processo cair, mas o Pod em si não renasce: se for apagado, removido ou se o nó dele for perdido, acabou. Por isso, neste curso, tudo o que deve continuar rodando vive dentro de um Deployment. Os Pods avulsos aparecem só para depurar ou para demonstrar algo, e são apagados ao terminar.

### 2.8 O *rollout*: revisões, histórico e reinicialização

#### 2.8.1 O que é uma revisão

Um **rollout** é a passagem de uma versão dos Pods para outra. A documentação de Deployments diz quando ocorre, e a regra é precisa: um *rollout* é disparado “se e somente se o template do Pod do Deployment (`.spec.template`) mudar”, por exemplo os rótulos ou a imagem. Outras mudanças, como escalar de três para cinco réplicas, não o disparam. Cada *rollout* deixa uma **revisão** no histórico, e cada revisão é um ReplicaSet.

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
```

Uma revisão: a que nasceu com o `apply`. A coluna `CHANGE-CAUSE` diz `<none>` porque ninguém anotou o motivo. Ela pode ser preenchida com uma anotação do Deployment; o curso não faz isso, porque o motivo de cada mudança vive no histórico do Git dos manifestos.

#### 2.8.2 Reiniciar sem mudar nada

Às vezes se quer que todos os Pods sejam substituídos sem mudar a imagem nem a configuração: por exemplo, para que voltem a ler algo que mudou fora deles. Apagá-los manualmente funciona, mas todos são apagados ao mesmo tempo e o serviço fica sem réplicas por um momento. Para isso existe o `kubectl rollout restart`:

```text
$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

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
revisor-55cc969586   3         3         3       2s
revisor-697fb84f97   0         0         0       55s
```

Leia o avanço do `rollout status`: um de três novos, dois de três, e no final “uma réplica antiga pendente de término”. Os Pods não foram substituídos de uma vez: foi-se criando um novo e removendo um antigo, por turnos. Essa é a estratégia padrão de um Deployment, `RollingUpdate`. Os dois botões dela valem 25 % se ninguém mexer: `maxSurge`, quantos Pods a mais pode haver durante a troca (arredonda-se para cima), e `maxUnavailable`, quantos podem faltar (arredonda-se para baixo). Com três réplicas, 25 % é 0,75: `maxSurge` fica em 1 e `maxUnavailable` em 0. Dito de forma simples: durante a troca pode haver até quatro Pods, e o controlador não remove nenhum antigo até que o novo esteja pronto, de modo que o plano dele nunca cai abaixo de três disponíveis. É uma promessa do controlador, não do universo: se um nó cair ou um processo morrer nesse momento, a conta baixa por causas alheias a ele. E com outro número de réplicas o arredondamento muda: com quatro, 25 % já é 1 e `maxUnavailable` valeria 1. A Lição 9 volta a isso com carga de verdade e mede se alguma requisição se perde.

E o resultado: um ReplicaSet novo, `revisor-55cc969586`, com as três réplicas, e o antigo, `revisor-697fb84f97`, em `0 0 0`. O antigo **não foi apagado**: ficou vazio, como registro da revisão 1. A documentação diz que, por padrão, guardam-se 10 ReplicaSets antigos (`revisionHistoryLimit`), e que apagar um é perder a possibilidade de voltar àquela revisão. A Lição 9 usa essa possibilidade com `rollout undo`.

Por que houve *rollout* se nada foi mudado? Algo mudou, sim:

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>


$ kubectl get deployment revisor -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
{"kubectl.kubernetes.io/restartedAt":"2026-10-21T03:55:53-06:00"}
```

O `rollout restart` adicionou ao template uma anotação com a hora da reinicialização. O template mudou e a regra “se e somente se” se cumpriu: template novo, *hash* novo, ReplicaSet novo, revisão 2. Não há mágica, só a mesma regra aplicada a um campo que foi posto sem ser digitado.

Essa anotação não está no arquivo, e isso tem uma consequência. Se amanhã o `revisor-deployment.yaml` for aplicado outra vez, o `kubectl apply` não a remove, porque só administra os campos que o arquivo declara (a Lição 0 explicou a anotação `last-applied-configuration`, que é como ele mantém essa conta). O estado final desta lição é conferido com `kubectl diff`, que não encontra diferenças.

## O erro que se vai ver

O erro desta lição é o de 2.3: `ErrImagePull`, que depois vira `ImagePullBackOff`. Foi provocado de propósito e é interpretado em ordem, porque essa ordem serve para qualquer Pod que não inicia.

**Primeiro, o estado.** O `kubectl get pods` mostrou `ImagePullBackOff` e `0/1`. A coluna `STATUS` diz **em que etapa** o Pod travou. Um `Pending` seco costuma querer dizer “ainda não tem nó” (o *scheduler* não encontrou lugar; isso aparece na Lição 5). Quando há algo mais concreto, o `kubectl` mostra isso no lugar da fase: `ImagePullBackOff` é “já tem nó, e o `kubelet` desse nó não consegue a imagem”, e `CrashLoopBackOff` seria “a imagem iniciou e o programa falha”. Um detalhe: a **fase** do Pod, que é outro campo, continua sendo `Pending` enquanto a imagem é baixada. A documentação do ciclo de vida diz assim: `Pending` inclui o tempo de espera até que um nó seja atribuído e “o tempo de download das imagens pela rede” ([kubernetes.io, “Pod Lifecycle”](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). A fase se lê com `kubectl get pod <pod> -o jsonpath='{.status.phase}'`. Só com a coluna `STATUS` já se sabe a que peça da Lição 0 perguntar.

**Segundo, os eventos.** O cluster deixa registro de cada tentativa:

```text
$ kubectl get events --field-selector reason=Failed -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message | head -4
OBJETO                     MENSAJE
revisor-697fb84f97-gn68x   Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
revisor-697fb84f97-gn68x   Error: ErrImagePull
revisor-697fb84f97-gn68x   Error: ImagePullBackOff
```

A primeira mensagem é longa, e se lê como uma cadeia de “porque”, da esquerda para a direita:

- `Failed to pull image "curso-docker-revisor:1.6.0"`: não consegui baixar a imagem pedida…
- `failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0"`: …que, com o nome completo, é esta do Docker Hub…
- `failed to resolve reference`: …porque não consegui encontrar essa referência…
- `pull access denied, repository does not exist or may require authorization`: …porque o Docker Hub me negou o acesso: o repositório não existe ou pede credenciais.

A pista decisiva é `docker.io/library/…`. O nó foi buscar a imagem na internet. Nunca olhou o Docker local, porque não pode: não é o armazenamento dele. O Docker Hub diz “não existe ou é preciso permissão” e não esclarece qual das duas. É assim que os registries se comportam, para não revelar quais repositórios privados existem. Aqui é a primeira: não existe.

**Terceiro, `describe`.** O `kubectl get events` mistura os eventos de todo o namespace. O `kubectl describe pod` reúne tudo de **um** Pod, e os eventos dele no final. Atenção: um evento repetido é agrupado em uma só linha e ordenado pela **última** vez que ocorreu, então `Pulling (x2 over 20s)` aparece depois de `BackOff` embora tenha ocorrido primeiro:

```text
$ kubectl describe pod revisor-697fb84f97-gn68x | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned default/revisor-697fb84f97-gn68x to curso-k8s-l2-worker2
  Normal   BackOff    19s               kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     19s               kubelet            spec.containers{revisor}: Error: ImagePullBackOff
  Normal   Pulling    6s (x2 over 20s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:1.6.0"
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
```

(O `sed` corta a saída para mostrar só a partir de `Events:`; acima disso, o `describe` traz a imagem, o nó, os volumes, o `securityContext` e as condições do Pod.) A coluna `From` diz **quem** fala, e é a que mais ensina. Em ordem lógica:

- `default-scheduler`, `Scheduled`: o *scheduler* atribuiu o Pod a `curso-k8s-l2-worker2`. A parte dele deu certo.
- `kubelet`, `Pulling`: o `kubelet` desse nó tentou baixar a imagem. `(x2 over 20s)` quer dizer que o mesmo evento ocorreu duas vezes em 20 segundos; o cluster agrupa os repetidos em vez de escrevê-los todos.
- `kubelet`, `Failed` com `ErrImagePull`: a tentativa falhou.
- `kubelet`, `BackOff` e `Failed` com `ImagePullBackOff`: o `kubelet` decidiu esperar antes da tentativa seguinte.

**`ErrImagePull` e `ImagePullBackOff` são o mesmo problema em dois momentos.** `ErrImagePull` é a falha de uma tentativa. `ImagePullBackOff` é a espera entre tentativas. A documentação de imagens explica: a parte `BackOff` indica que o Kubernetes continuará tentando, com uma espera que cresce a cada tentativa, até um limite fixo de 300 segundos (5 minutos). Por isso o Pod alterna entre os dois estados enquanto a imagem não é fornecida. E por isso a recuperação de 2.4 não foi imediata para qualquer Pod que estivesse no meio de uma espera longa: o `kubelet` pega a imagem na tentativa seguinte, não antes. Se um Pod está esperando há muito tempo e não se quer aguardar, apagá-lo **depois** de corrigir a causa funciona: o ReplicaSet cria outro, que tenta de imediato. Apagar **antes** de corrigir é o que fez a equipe da cena.

**A ordem, para qualquer Pod que não inicia:** o estado (`get pods`), o `describe` do Pod (os eventos dele e a coluna `From`) e, se o contêiner chegou a iniciar, os `logs` dele. Primeiro se lê e depois se muda algo. E o que se muda é a causa, não o Pod.

## O hábito de segurança da lição: `securityContext` desde o primeiro manifesto

A tabela de hábitos do curso atribui a esta lição o `securityContext` do primeiro Deployment: sem `root`, sem escalada de privilégios, sem capabilities, sistema de arquivos somente leitura e perfil `seccomp`. Assim ficou aplicado no cluster:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
{"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}
{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}
```

A primeira linha é a do Pod; a segunda, a do contêiner. Linha por linha, com o que cada uma evita:

| Linha | O que faz | O que evita | Equivalente no Docker |
|---|---|---|---|
| `runAsNonRoot: true` | o `kubelet` se recusa a iniciar o contêiner se ele fosse rodar como usuário 0 | que uma imagem mal feita, ou uma linha mal escrita, rode como `root` sem que ninguém perceba | não tem: o Docker não verifica |
| `runAsUser: 65532`, `runAsGroup: 65532` | fixa o usuário e o grupo numéricos com que o processo roda | depender do que a imagem disser; o número fica escrito no manifesto | `--user 65532:65532` |
| `seccompProfile: RuntimeDefault` | aplica o filtro de chamadas de sistema que o *runtime* traz | que o processo use chamadas do kernel de que um servidor HTTP nunca precisa. **Sem esta linha, o Kubernetes roda o contêiner sem filtro (`Unconfined`)**, a não ser que o `kubelet` tenha ativada a opção `seccompDefault` | o Docker aplica o perfil padrão sem que se peça; o Kubernetes não |
| `allowPrivilegeEscalation: false` | um processo não pode ganhar mais privilégios que o pai, por exemplo executando um binário *setuid* | que alguém que entre no contêiner vire `root` por dentro | `--security-opt no-new-privileges` |
| `capabilities: drop: ["ALL"]` | remove todas as capabilities especiais do kernel | que o processo possa, por exemplo, trocar o dono de arquivos (`CHOWN`) ou abrir *sockets* brutos para fabricar pacotes de rede (`NET_RAW`) | `--cap-drop ALL` |
| `readOnlyRootFilesystem: true` | monta o sistema de arquivos do contêiner em somente leitura | que um atacante deixe ferramentas ou modifique o programa | `--read-only` |

As definições vêm do guia oficial [“Configure a Security Context for a Pod or Container”](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/). Sobre `allowPrivilegeEscalation`, por exemplo, ele diz que “controla se um processo pode obter mais privilégios que o processo pai” e que ativa a flag `no_new_privs` do kernel. E o tutorial de `seccomp` explica a diferença em relação ao Docker que a tabela marca: se a opção `seccompDefault` estiver ativada, os Pods usam `RuntimeDefault` quando não pedem outro perfil; “caso contrário, o valor padrão é `Unconfined`” ([kubernetes.io, “Restrict a Container's Syscalls with seccomp”](https://kubernetes.io/docs/tutorials/security/seccomp/)). Por isso a linha é sempre escrita.

Há uma referência que importa mais que qualquer guia: os **Pod Security Standards**, os três níveis de segurança que o Kubernetes define ([kubernetes.io, “Pod Security Standards”](https://kubernetes.io/docs/concepts/security/pod-security-standards/)). O mais estrito, `restricted`, foi pensado para “fazer cumprir as melhores práticas atuais de hardening de Pods”. Exige quatro destas linhas: rodar como não-`root` (`runAsNonRoot: true`), não permitir escalada de privilégios, remover **todas** as capabilities (só deixa voltar a adicionar `NET_BIND_SERVICE`) e fixar explicitamente o perfil `seccomp` (“tanto o perfil `Unconfined` quanto a ausência de perfil são proibidos”). Além disso, o `restricted` proíbe pedir `runAsUser: 0` (justamente o que faz o `fig02_02.raiz.yaml`, mais adiante) e só permite certos tipos de volume, entre eles `emptyDir`. O manifesto do `revisor` cumpre tudo isso desde hoje. Quando a Lição 7 puser o namespace no nível `restricted`, o `revisor` já estará pronto, e não será preciso reescrever nada na última hora.

O `readOnlyRootFilesystem` **não** é exigido pelo `restricted`. O curso o põe porque o `revisor` aguenta: o único arquivo de escrita dele vai para `/datos`, e para isso existe o `emptyDir`.

**O que se vê por dentro.** A imagem do `revisor` não tem *shell*. Foi conferido:

```text
$ kubectl exec deployment/revisor -- /revisor healthcheck
sano

$ kubectl exec deployment/revisor -- /revisor version
1.6.0

$ kubectl exec deployment/revisor -- sh -c 'id'
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "d8ccff765090d70932ea2f15a41fa34693c57f56ad0106eeb012a0a816fa701d": OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH
[código de salida: 1]
```

O `kubectl exec` executa um programa dentro de um contêiner que já está rodando, como o `docker exec`. Com `deployment/revisor`, escolhe um dos Pods dele. Os dois subcomandos do próprio `revisor` funcionam: `healthcheck` consulta o `/salud` dele por dentro e responde `sano`, e `version` diz `1.6.0`. Mas o `sh` não existe: `executable file not found in $PATH`. Isso não é um defeito, é uma defesa. Quem conseguir executar algo dentro do contêiner não encontra *shell*, nem `curl`, nem gerenciador de pacotes. A forma de depurar sem *shell* chega na Lição 3: um Pod à parte, feito para isso.

As montagens do contêiner confirmam o volume de dados e revelam algo mais:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.containers[0].volumeMounts}{"\n"}'
[{"mountPath":"/datos","name":"datos"},{"mountPath":"/var/run/secrets/kubernetes.io/serviceaccount","name":"kube-api-access-vxlgn","readOnly":true}]
```

`/datos` é o `emptyDir`. A segunda montagem ninguém escreveu: o Kubernetes montou no Pod uma **credencial** para falar com o `kube-apiserver`, a da conta de serviço padrão do namespace. O `revisor` nunca fala com o servidor da API, então não precisa dela. Fica anotado como dívida conhecida, com a sua lição: a Lição 7 dá ao `revisor` a sua própria conta de serviço, sem permissões, e a partir daí todas as contas do curso levam `automountServiceAccountToken: false`, para que essa credencial não seja montada.

**A rede de segurança em ação.** O `runAsNonRoot` parece redundante se já se escreveu `runAsUser: 65532`. O valor dele aparece quando alguém se engana. Este Pod (`fig02_02.raiz.yaml`, um **programa** que falha de propósito) pede as duas coisas ao mesmo tempo: não ser `root` e ser o usuário 0, que é `root`:

```yaml
# fig02_02.raiz.yaml — FALLA A PROPÓSITO: pide correr como root (runAsUser: 0)
# y a la vez exige no ser root (runAsNonRoot: true). El kubelet se niega a
# arrancar el contenedor. Es la red de seguridad de runAsNonRoot en acción.
apiVersion: v1
kind: Pod
metadata:
  name: revisor-raiz
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 0
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: revisor
    image: curso-docker-revisor:1.6.0
    imagePullPolicy: IfNotPresent
    env:
    - name: REVISOR_SERVICIOS
      value: "prueba http://prueba:9000/ 2s"
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

```text
$ kubectl apply -f fig02_02.raiz.yaml
pod/revisor-raiz created

$ kubectl get pod revisor-raiz
NAME           READY   STATUS                       RESTARTS   AGE
revisor-raiz   0/1     CreateContainerConfigError   0          10s

$ kubectl get events --field-selector involvedObject.name=revisor-raiz,reason=Failed -o custom-columns=MENSAJE:.message | head -2
MENSAJE
Error: container's runAsUser breaks non-root policy (pod: "revisor-raiz_default(49586352-b84d-462b-9ded-e41bb2d2123a)", container: revisor)
```

O `kube-apiserver` aceitou o Pod (`created`), porque não há nada inválido na forma dele. Quem se recusou foi o `kubelet`, ao ir criar o contêiner: `CreateContainerConfigError`, “a configuração do contêiner não pode ser usada”, e o evento diz por quê: “o `runAsUser` do contêiner viola a política de não-`root`”. A imagem estava no nó e o programa nunca chegou a rodar. Essa é a função do `runAsNonRoot`: uma segunda chave que não depende de a primeira estar bem escrita. O Pod foi apagado ao terminar.

**O que ele protege e o que não.** O `securityContext` limita o que **o processo** pode fazer se alguém o comprometer: não ser `root`, não ganhar privilégios, não modificar os próprios arquivos. Não protege o `revisor` de requisições maliciosas (isso é o código dele), não decide quem pode falar com ele (isso é a rede, Lição 7) e não protege a máquina local do nó do kind, que, como se viu na Lição 0, é um contêiner privilegiado.

## Erros comuns

**Apagar e aplicar de novo diante de um erro.** É a cena de segunda-feira. Se a causa não mudou, o Pod novo chega ao mesmo erro. Primeiro se lê o `describe`, depois se corrige a causa.

**Usar `:latest` no kind.** Com `:latest` ou sem tag, a política de download padrão é `Always`, e o nó tenta ir ao registry mesmo que a imagem já tenha sido carregada nele. Além disso, `:latest` não diz que versão está rodando: dois nós podem ter duas imagens distintas com a mesma tag. Tag fixa e `IfNotPresent`.

**Esquecer o `--name` no `kind load docker-image`.** Sem ele, o kind procura o cluster chamado `kind`. Se não existir, falha. Se existir e não for o certo, a imagem foi carregada no lugar errado e o cluster continua sem ela.

**Criar Pods avulsos para algo que deve continuar rodando.** Um Pod sem dono não renasce. Para um serviço, sempre um Deployment.

**Pôr em um Pod avulso os rótulos de um Deployment.** Vai-se ver isso no Exercício 2: o Deployment não o adota, mas tudo o que buscar por esse rótulo o encontra. É um Pod que aparece nas contagens e no tráfego sem que ninguém cuide dele.

**Editar ou apagar manualmente o ReplicaSet de um Deployment.** O Deployment é o dono e o reconstrói. A documentação diz com todas as letras: não administre ReplicaSets que pertencem a um Deployment.

**Mexer no rótulo `pod-template-hash`.** Quem o põe é o Deployment, para que os ReplicaSets dele não se sobreponham. Mudá-lo quebra essa separação.

**Tirar o `securityContext` “para funcionar”.** Se um contêiner não inicia com o `securityContext` do curso, o problema quase sempre está na imagem (roda como `root`, escreve onde não deve) e se resolve na imagem ou com um volume, não tirando defesas do manifesto.

**Confiar no `Running`.** Sem o `emptyDir`, o `revisor` também estaria `Running` e `1/1`, e falharia na primeira requisição que pedisse para guardar o relatório. `Running` quer dizer que o processo está vivo, não que faz bem o trabalho dele. A Lição 5 ensina o cluster a distinguir isso.

## Exercícios

Os três primeiros são executados no cluster da lição, em ordem e a partir do estado em que ele ficou no final de 2.8. Antes de cada exercício, `kubectl config current-context` deve dizer `kind-curso-k8s-l2`; se disser outra coisa, não prossiga. O `correr.sh` os executa do mesmo modo, e a saída está em `correr.salida.txt`. **Antes** de executar cada um, escrever no [diário de bordo](bitacora.md) o que se acredita que vai acontecer. O quarto é escrito com palavras próprias.

### Exercício 1 — Tirar um Pod do rebanho

Escolher um dos Pods do `revisor` e mudar o rótulo `app` dele para outro valor:

```bash
kubectl label pod <un-pod-del-revisor> app=fuera --overwrite
```

Prever: quantos Pods há cinco segundos depois? O Pod que foi alterado continua rodando? Quem é o dono dele agora? Conferir com `kubectl get pods -L app` (a opção `-L` acrescenta uma coluna com o valor desse rótulo) e com o `jsonpath` de 2.7.1, `-o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'`, que funciona quando a lista de donos está vazia (o `[0]` de 2.5 sobre uma lista vazia imprime só uma barra, `/`, e sai com código 0, sem avisar que não havia nada). Ao terminar, apagar o Pod que foi retirado.

### Exercício 2 — O Pod que se infiltra (projeto)

O `fig02_03.adoptado.yaml` é um Pod avulso, `revisor-extra`, idêntico aos do `revisor` e **com** o rótulo `app: revisor`:

```yaml
# fig02_03.adoptado.yaml — Ejercicio 2: un Pod suelto que SÍ lleva app: revisor.
# Pregunta: el Deployment selecciona app: revisor. ¿Se queda con este Pod? ¿Borra
# uno de los suyos para seguir en tres? ¿Y qué ve quien busca por app=revisor?
apiVersion: v1
kind: Pod
metadata:
  name: revisor-extra
  labels:
    app: revisor
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
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
      value: "prueba http://prueba:9000/ 2s"
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
    emptyDir:
      sizeLimit: 10Mi
```

Antes de aplicá-lo, responder às três perguntas do comentário dele. Depois aplicá-lo e conferir com `kubectl get pods -l app=revisor`, `kubectl get deployment revisor` e o seletor dos ReplicaSets. Para terminar, explicar que problema este Pod causaria quando, na Lição 3, um Service escolher os seus Pods por `app: revisor`. Apagá-lo ao terminar.

### Exercício 3 — Uma tag que não existe

O `fig02_04.etiqueta-mala.yaml` é o mesmo Deployment com uma única diferença: pede a imagem `curso-docker-revisor:1.6.9`, que não existe nem no Docker local nem no cluster. Antes de aplicá-lo, prever: quantos Pods do `revisor` continuam rodando enquanto o *rollout* está travado? Quantos Pods novos ele tenta criar? (Dica: os números de `maxSurge` e `maxUnavailable` de 2.8.2.) Depois aplicá-lo, esperar com `kubectl rollout status deployment/revisor --timeout=40s` e olhar `kubectl get pods -l app=revisor` e `kubectl get deployment revisor`. Para sair do impasse, aplicar de novo o `revisor-deployment.yaml` e explicar por que o *rollout* termina na hora.

### Exercício 4 — Defender o `securityContext`

Um colega propõe tirar o `readOnlyRootFilesystem: true` e o volume `datos` “porque são duas coisas a manter e o `revisor` inicia do mesmo jeito”. Em no máximo cinco frases, responder-lhe: o que essa linha evita, por que o volume existe justamente por causa dela, o que aconteceria com o relatório se só o volume fosse tirado e a linha ficasse, e se tirá-la quebra ou não o nível `restricted`.

## Soluções

### Solução 1

Medido em `correr.salida.txt`:

```text
$ kubectl label pod revisor-55cc969586-6m76h app=fuera --overwrite
pod/revisor-55cc969586-6m76h labeled

$ kubectl get pods -L app
NAME                       READY   STATUS    RESTARTS   AGE   APP
revisor-55cc969586-6m76h   1/1     Running   0          8s    fuera
revisor-55cc969586-7tmfc   1/1     Running   0          7s    revisor
revisor-55cc969586-f8dk6   1/1     Running   0          6s    revisor
revisor-55cc969586-x6vfq   1/1     Running   0          5s    revisor

$ kubectl get pod revisor-55cc969586-6m76h -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=
```

**Quatro Pods.** O que foi alterado continua `Running`: mudar um rótulo não o para. Mas deixou de coincidir com o seletor do ReplicaSet, então o ReplicaSet o **soltou** (o `ownerReferences` dele ficou vazio) e, como agora contava dois onde devia haver três, criou um novo. Ficam os três do rebanho, mais um avulso que ninguém cuida. A documentação de ReplicaSet descreve essa técnica: é possível retirar Pods de um ReplicaSet mudando os rótulos deles, por exemplo “para depuração ou recuperação de dados”, e os que forem retirados assim são substituídos sozinhos. É útil: separa-se um Pod que se comporta mal para estudá-lo, sem que o serviço perca uma réplica. Mas não convém esquecê-lo ali: o script o apagou ao terminar.

### Solução 2

Medido em `correr.salida.txt`. (O `fig02_03.adoptado.yaml` declara a porta `http`, igual ao template do Deployment. O campo é informativo e não muda nenhuma destas saídas, mas importa para o tráfego da Lição 3: por isso o Pod é idêntico aos do Deployment.)

```text
$ kubectl apply -f fig02_03.adoptado.yaml
pod/revisor-extra created

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running   0          13s
revisor-55cc969586-f8dk6   1/1     Running   0          12s
revisor-55cc969586-x6vfq   1/1     Running   0          11s
revisor-extra              1/1     Running   0          5s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           67s

$ kubectl get pod revisor-extra -o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'
dueños=

$ kubectl get replicaset -l app=revisor -o custom-columns=NOMBRE:.metadata.name,DESEADOS:.spec.replicas,SELECTOR:.spec.selector.matchLabels
NOMBRE               DESEADOS   SELECTOR
revisor-55cc969586   3          map[app:revisor pod-template-hash:55cc969586]
revisor-697fb84f97   0          map[app:revisor pod-template-hash:697fb84f97]
```

As três respostas:

1. **Não fica com ele.** O `revisor-extra` continua sem dono. A razão está no seletor do ReplicaSet: ele não busca só `app: revisor`, busca também `pod-template-hash: 55cc969586`, e o `revisor-extra` não leva esse rótulo. A documentação de ReplicaSet diz que um ReplicaSet adota de imediato um Pod sem dono que coincide com **o seu** seletor, e que por isso convém que os Pods avulsos não levem rótulos que coincidam com o seletor de um ReplicaSet. Aqui o rótulo `pod-template-hash` evitou a adoção.
2. **Não apaga nenhum dos seus.** O Deployment diz `3/3`: para ele só existem os três dele.
3. **Quem busca por `app=revisor` vê quatro.** O `kubectl get pods -l app=revisor` lista o `revisor-extra` como se fosse mais uma réplica.

Esse terceiro ponto é o problema. Um Service, na Lição 3, escolhe os seus Pods por rótulo, e pelo do manifesto, `app: revisor`, não por `pod-template-hash`, e aponta para a porta chamada `http`. Este Pod avulso leva as duas coisas: o rótulo e a porta com esse nome. Então este Pod, que ninguém repõe se morrer e que ninguém atualiza quando a imagem muda, receberia a parte dele do tráfego como se fosse mais uma réplica. É justamente o que a documentação quer dizer quando avisa que seletores que se sobrepõem produzem comportamentos inesperados. O script o apagou ao terminar.

### Solução 3

Medido em `correr.salida.txt`:

```text
$ kubectl apply -f fig02_04.etiqueta-mala.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS         RESTARTS   AGE
revisor-55cc969586-7tmfc   1/1     Running        0          55s
revisor-55cc969586-f8dk6   1/1     Running        0          54s
revisor-55cc969586-x6vfq   1/1     Running        0          53s
revisor-b8b699487-fc4gn    0/1     ErrImagePull   0          41s

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     1            3           109s
```

**Três Pods antigos continuam rodando e há um único Pod novo, travado em `ErrImagePull`.** Com três réplicas, `maxSurge` é 1 (pode haver um Pod a mais) e `maxUnavailable` é 0 (não pode faltar nenhum). O Deployment criou um Pod novo e, para remover um antigo, esperou que o novo estivesse disponível. Nunca esteve, então não removeu nenhum. O `kubectl get deployment` resume: `READY 3/3` (o serviço continua completo), `UP-TO-DATE 1` (só uma réplica tem o template novo). **Aqui, um *rollout* com uma imagem quebrada não derruba o serviço**: trava com o serviço intacto, porque com três réplicas `maxUnavailable` é 0. Não é uma lei: com quatro réplicas 25 % já é 1 e o Deployment sim removeria uma réplica saudável antes de saber se a nova inicia, e, se um Pod antigo cair enquanto o *rollout* está travado, a capacidade diminui. O `rollout status` desistiu aos 40 segundos porque foi isso que se pediu; o Deployment, por conta própria, esperaria 600 segundos (`progressDeadlineSeconds`, cujo valor padrão segundo a documentação é 600) antes de marcar o *rollout* como falho com a condição `ProgressDeadlineExceeded`.

Ao aplicar de novo o arquivo bom:

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           109s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-55cc969586   3         3         3       56s
replicaset.apps/revisor-697fb84f97   0         0         0       109s
replicaset.apps/revisor-b8b699487    0         0         0       41s
```

Terminou na hora porque o template voltou a ser **idêntico** ao do ReplicaSet `revisor-55cc969586`: a mesma imagem e a mesma anotação de `restartedAt`, que o `apply` não remove porque o arquivo não a declara. Mesmo modelo, mesmo *hash*, mesmo ReplicaSet. O Deployment não criou um novo: deixou em zero o quebrado, `revisor-b8b699487`, e como o bom já tinha as suas três réplicas, não havia mais nada a fazer. Voltar à versão anterior com `kubectl rollout undo` é a forma curta de fazer isso, e chega na Lição 9. Aqui foi feito do jeito que o curso ensina: o arquivo é a verdade, e se aplica de novo.

### Solução 4

Uma resposta possível: “`readOnlyRootFilesystem` impede que alguém que entre no contêiner modifique o programa ou deixe ferramentas, e é barato porque o `revisor` só escreve um arquivo. Justamente por essa linha existe o volume `datos`: é o único lugar onde o `revisor` pode escrever o relatório. Se o volume for tirado e a linha ficar, o `revisor` inicia e aparece como `Running`, mas na primeira vez que tentar guardar um relatório responde 500 com `no pude guardar el reporte`. Tirar a linha não quebra o nível `restricted`, que não a exige, mas abre-se mão de uma defesa que não custa nada. E ‘inicia do mesmo jeito’ não é a prova: o que importa é se continua funcionando quando alguém o ataca e quando alguém lhe pede trabalho.”

## Apagar o cluster

Quando terminar os exercícios, apague o cluster da lição. Nada deve ficar vivo na máquina:

```text
$ kind delete cluster --name curso-k8s-l2
Deleting cluster "curso-k8s-l2" ...
Deleted nodes: ["curso-k8s-l2-worker" "curso-k8s-l2-worker2" "curso-k8s-l2-control-plane"]

$ kind get clusters | grep -c curso-k8s-l2
0
```

O `--name` é obrigatório aqui também: sem ele, o kind apagaria o cluster chamado `kind`, que pode ser de outra pessoa ou de outro projeto. Depois, apagar a pasta temporária do `kubeconfig` (a que o `mktemp` criou, com o prefixo `/tmp/curso-k8s-l2.`) ou fechar aquele terminal. O cluster da lição seguinte é criado do zero, como este.

## Como saber que deu certo

- [ ] Diante de `ImagePullBackOff`, dizer que peça falhou (o `kubelet` do nó) e por que a mensagem menciona `docker.io/library/…`, sem consultar.
- [ ] Conferir com `docker exec <nó> crictl images` se uma imagem está em um nó do kind, e carregá-la com `kind load docker-image <imagem> --name <cluster>`.
- [ ] Escrever de memória o esqueleto de um Deployment e explicar por que `selector` e `template.metadata.labels` devem coincidir.
- [ ] Prever o que acontece ao apagar um Pod avulso, um Pod de um Deployment e o Deployment inteiro.
- [ ] Explicar para que serve o rótulo `pod-template-hash` e por que o Pod do Exercício 2 não foi adotado.
- [ ] Justificar cada linha do `securityContext` do `revisor` e dizer quais o nível `restricted` exige.
- [ ] Executar `programas/02-pods-deployments/correr.sh > /tmp/mi-corrida-l2.txt 2>&1` e comparar `/tmp/mi-corrida-l2.txt` com `programas/02-pods-deployments/correr.salida.txt` (não redirecionar para esse arquivo: é a referência) no que não muda entre execuções: três nós `Ready` em `v1.37.0`; `0` imagens do `revisor` no nó antes de carregá-la; os três Pods em `ImagePullBackOff` e o evento `pull access denied` com `docker.io/library/curso-docker-revisor:1.6.0`; as três linhas `not yet present on node … loading...`, uma por nó, incluindo a do nó de controle; `deployment.apps/revisor 3/3`; `revisor 1.6.0 escuchando en :8080 (1 servicio(s))`; `sano` e `1.6.0`; `executable file not found in $PATH`; o `securityContext` em JSON; `CreateContainerConfigError` com `breaks non-root policy`; duas revisões em `rollout history` e o ReplicaSet antigo em `0 0 0`; e no final `sin diferencias con el archivo`. Os sufixos dos nomes, os IPs, em que nó cai cada Pod, as idades, a ordem das linhas do `kind load` e as vezes que se repete cada linha do `rollout status` mudam em cada execução: observam-se, não se comparam.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l2`.

## Resumo

Responda sem olhar a lição:

1. Por que um nó do kind não enxerga as imagens do Docker, e o que faz o `kind load docker-image`?
2. Que diferença há entre `ErrImagePull` e `ImagePullBackOff`? Quanto o `kubelet` chega a esperar entre tentativas?
3. Que três peças tem a `spec` de um Deployment e o que acontece se o seletor não coincidir com os rótulos do template?
4. Quem é dono de quem na cadeia Deployment, ReplicaSet e Pod, e em que campo isso se lê?
5. O que faz um ReplicaSet com um Pod ao qual se tira o rótulo do seletor dele?
6. Quando um *rollout* é disparado? Por que o `rollout restart` dispara um se nada foi mudado?
7. Com três réplicas e os valores padrão, quantos Pods pode haver durante um *rollout* e quantos podem faltar?
8. O que o `runAsNonRoot: true` evita que o `runAsUser: 65532` ainda não evite?
9. Por que o `revisor` precisa de um `emptyDir` em `/datos`?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/), seção “Loading an Image Into Your Cluster”: `kind load docker-image`, a opção `--name` para clusters com nome, `crictl images` dentro do nó e o aviso sobre `:latest` e a política de download.
- [Kubernetes, “Images”](https://kubernetes.io/docs/concepts/containers/images/): as políticas `IfNotPresent`, `Always` e `Never`; a política padrão segundo a tag; o Docker Hub como registry padrão (`docker.io/library/…`); e `ImagePullBackOff`, com a espera crescente até 300 segundos.
- [Kubernetes, “Deployments”](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): quando um *rollout* é disparado; `maxSurge` e `maxUnavailable` (25 %, com o arredondamento); `revisionHistoryLimit` (10); `progressDeadlineSeconds` (600) e `ProgressDeadlineExceeded`; o rótulo `pod-template-hash`; o aviso de não administrar os ReplicaSets de um Deployment e o dos seletores que se sobrepõem.
- [Kubernetes, “ReplicaSet”](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/): o propósito dele; a adoção de Pods sem dono que coincidem com o seletor; a recomendação de usar Deployments; e como retirar Pods de um ReplicaSet mudando os rótulos deles.
- [Kubernetes, “Pods”](https://kubernetes.io/docs/concepts/workloads/pods/): por que raramente se criam Pods individuais e até quando um Pod permanece no seu nó.
- [Kubernetes, “Pod Lifecycle”](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): `restartPolicy` vale `Always` por padrão; a fase `Pending` inclui o download de imagens; um Pod nunca é reprogramado em outro nó.
- [Kubernetes, “Restrict a Container's Syscalls with seccomp”](https://kubernetes.io/docs/tutorials/security/seccomp/): sem `seccompDefault`, o perfil padrão é `Unconfined`.
- [Kubernetes, “Owners and Dependents”](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/): o campo `ownerReferences`.
- [Kubernetes, “Labels and Selectors”](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/): o que é um rótulo, que não é único, os seletores de igualdade e de conjuntos, e a ausência de um operador “ou”.
- [Kubernetes, “Volumes”](https://kubernetes.io/docs/concepts/storage/volumes/), seção `emptyDir`: quando é criado, quando é apagado e `sizeLimit`.
- [Kubernetes, “Configure a Security Context for a Pod or Container”](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): cada campo do `securityContext` e o que ele controla.
- [Kubernetes, “Pod Security Standards”](https://kubernetes.io/docs/concepts/security/pod-security-standards/): o nível `restricted` e as regras dele de não-`root`, escalada de privilégios, capabilities e `seccomp`.

---

**Próxima:** [Lição 3 — Services e DNS](03-services-dns.md)
