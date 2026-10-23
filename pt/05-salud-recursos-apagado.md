# Lição 5 — Verificação de saúde (*health check*), recursos e desligamento ordenado

Quinta-feira, 18h40. O serviço de teste está fora do ar há dez minutos e o painel mostra isso direito: `FALLA codigo 503`. Para isso existe o `revisor`. Mas às 18h42 o painel deixa de carregar. Pedem-se os Pods e aparece algo inesperado: as três réplicas do `revisor` têm `RESTARTS 4`, `RESTARTS 5`, `RESTARTS 5`, e duas delas dizem `CrashLoopBackOff`. Ninguém mexeu no `revisor`. O que alguém sim mexeu, na terça-feira, foi a verificação de saúde (*health check*) dele: “para que seja mais completa”, pediu que perguntasse também pelo serviço de teste. Agora o serviço de teste está fora do ar, a verificação do `revisor` falha, o cluster conclui que o `revisor` está morto e o reinicia, uma e outra vez. A ferramenta que devia avisar do problema é a primeira vítima do problema. E às 19h é preciso explicar o que aconteceu.

O cluster não errou: fez exatamente o que lhe disseram. Esta lição ensina a dizer-lhe o que é certo. Como o cluster sabe que um contêiner iniciou, que pode receber tráfego e que continua vivo, e por que essas três perguntas são distintas. Quanta CPU e memória cabe a cada contêiner, e o que acontece quando ele pede demais. E o que faz o `revisor` nos segundos que o cluster lhe dá quando lhe pede que se desligue.

**Tempo:** 2 × 45 min

**O que se constrói:** um `revisor` que o cluster sabe vigiar: com *probes* de inicialização, de disponibilidade e de vida, com um valor reservado e um teto de CPU e memória, e com um prazo de desligamento sob medida; e o serviço de teste com o seu próprio *probe* e os seus próprios limites

**O que se aprende:** o que cada *probe* pergunta (`startupProbe`, `readinessProbe`, `livenessProbe`), quem o executa e o que acontece quando falha; por que `/salud` não consulta ninguém; o que são `requests` e `limits`, quem usa cada um e em que unidades se escrevem; as classes de qualidade de serviço (QoS); um `OOMKilled` e um `Pending` provocados de propósito e como se interpretam; e o que acontece entre o `kubectl delete pod` e o desaparecimento do Pod, com `terminationGracePeriodSeconds`

**De onde a gente vem.** Da [Lição 4](04-configuracion-secretos.md): o `revisor` e o serviço de teste são aplicados com `kubectl apply -k .`; a lista de serviços chega de um `ConfigMap` gerado e o token de um `Secret` montado como arquivo, e o `/api/estados` pede `Authorization: Bearer …`. Da [Lição 3](03-services-dns.md) vêm o Pod `depurar`, os EndpointSlices e a coluna `ready` deles, que a seção 3.4.3 deixou pendente para esta lição. E da [Lição 2](02-pods-deployments.md), que o `kubelet` de cada nó é quem inicia os contêineres.

**O que esta lição não faz.** Não reparte as réplicas entre nós nem faz com que uma atualização não perca requisições: isso é a [Lição 9](09-escalar-y-actualizar.md), com `preStop`, `PodDisruptionBudget` e o escalonamento automático, que usa os `requests` de hoje para calcular. Não publica o `revisor` para fora: isso é a [Lição 6](06-entrar-al-cluster.md). E não põe regras para todo um namespace (um máximo por contêiner, um total por equipe): são nomeadas no hábito de segurança da lição e ficam fora do curso.

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com o `kind` v0.33.0, o `kubectl` v1.37.1 e a imagem de nó `kindest/node:v1.37.0` fixada pelo digest, no cluster de três nós da Lição 1, aqui chamado `curso-k8s-l5`. A máquina foi um Mac com processador ARM e Docker Engine 29.2.1 dentro de uma máquina virtual Linux (Colima) com 6 CPUs e 16 GiB de memória, **não** Linux Mint, que é o sistema de referência do curso. O que muda no Mint: a arquitetura (`amd64` em vez de `arm64`); a CPU e a memória que cada nó diz ter, que no kind são as da máquina (5.6 explica), e com elas os percentuais do `describe node`; os endereços IP, os sufixos aleatórios dos nomes, as idades, em que nó cai cada réplica, a hora do log e a memória exata que o `revisor` usa. Os comandos são os mesmos. O percurso completo está em [`programas/05-salud-recursos-apagado/`](../programas/05-salud-recursos-apagado): o `correr.sh` cria o cluster, carrega as imagens nele, deixa tudo como a Lição 4 deixou, percorre a lição em ordem, executa os Exercícios 1 a 3 e apaga o cluster. A execução completa levou 4 minutos e 48 segundos, e o script registra quanto levou cada passo longo: criar o cluster e esperar que ficasse pronto, 34 segundos; apagá-lo, 1. A saída é o `correr.salida.txt`. Ali, a capacidade dos nós (5.6) e o erro de propósito aparecem antes do desligamento (5.7), e o hábito de segurança antes dos exercícios, porque o script os executa nessa ordem. Não usa nenhuma porta da máquina local.

## Ao terminar, a gente vai conseguir

- Explicar com um exemplo a diferença entre “iniciou”, “está pronto” e “está vivo”, e dizer que *probe* pergunta cada coisa e o que o cluster faz quando a resposta é “não”.
- Escrever os três *probes* do `revisor` e calcular, com os números deles, quanto o cluster demora para reagir a cada falha.
- Justificar por que o *liveness probe* não deve perguntar por outros serviços, e demonstrá-lo com o serviço de teste fora do ar.
- Escrever `requests` e `limits` em milicores e em mebibytes, e dizer quem usa cada um: o escalonador (*scheduler*), o `kubelet` ou o kernel do Linux.
- Provocar um `OOMKilled` e um `Pending`, interpretá-los com `kubectl get`, `describe` e os eventos, e corrigi-los.
- Medir quanto um Pod demora para se desligar e explicar o papel de SIGTERM, SIGKILL e `terminationGracePeriodSeconds`.

## O porquê antes do como

Até hoje, o cluster sabe uma única coisa dos contêineres: se o processo está rodando. Se o processo morre, o `kubelet` o reinicia; isso se viu na Lição 2. Mas um processo pode estar rodando e não servir. Pode estar ainda iniciando, sem escutar na porta. Pode estar travado em um bloqueio, vivo para o sistema operacional e morto para os clientes. Pode estar saudável e, mesmo assim, não querer tráfego por um momento. Para o cluster, hoje, os três casos são iguais: `Running`. E o Service da Lição 3 manda tráfego aos três.

A primeira pergunta da lição é, então, **como um contêiner conta ao cluster como está?** A resposta são os ***probes***: perguntas que o `kubelet` faz ao contêiner de tempos em tempos. Há três, porque há três perguntas distintas, e cada resposta negativa tem uma consequência diferente: esperar, deixar de mandar tráfego ou reiniciá-lo. Confundi-las é a cena de quinta-feira.

A segunda pergunta é **quanto cabe a cada um?** Hoje o `revisor` não diz quanta CPU nem quanta memória precisa, e o cluster o põe onde calhar, sem contar. Um contêiner sem teto pode devorar a memória de um nó inteiro e levar junto todos os vizinhos. Os **`requests`** dizem quanto ele precisa para que o escalonador lhe procure lugar; os **`limits`** dizem até onde pode chegar.

A terceira é **como ele se vai?** Cada vez que se apaga um Pod, se faz um *rollout* ou o cluster move algo, um contêiner recebe a ordem de se desligar. Se a atende, termina o que estava fazendo e sai. Se não, o cluster espera um prazo e o mata. Esse prazo se escreve no manifesto.

A lição tem sete partes de conceitos e depois as seções de sempre:

1. **O cluster da lição e o que ele sabe hoje** (5.1).
2. **Os manifestos da lição** (5.2), campo por campo.
3. **Os três *probes*** (5.3): o que cada um pergunta e quando reage.
4. **Os *probes* em ação** (5.4): aplicar, olhar e lê-los no log.
5. **Por que `/salud` não consulta ninguém** (5.5): a cena de quinta-feira, ao contrário.
6. **`requests`, `limits` e a capacidade dos nós** (5.6).
7. **O desligamento ordenado** (5.7).

Este é o destino. No final de 5.4, cada réplica do `revisor` tem os seus três *probes*, o seu valor reservado e o seu teto, e um prazo de desligamento de 10 segundos:

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

## Se as imagens do curso de Docker não estiverem à mão

Esta lição usa as mesmas duas imagens da Lição 3: `curso-docker-revisor:1.6.0` e `curso-docker-prueba:1.0.0`. Convém conferir se existem:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para a outra, o mesmo comando com `curso-docker-prueba:1.0.0`. Se faltar alguma, a [Lição 3](03-services-dns.md) diz, nesta mesma seção, como construir cada uma a partir do repositório do curso de Docker. O que esta lição exige **além disso** das duas imagens, e convém ler porque cada ponto explica uma linha dos manifestos:

- **O `revisor` responde `GET /salud` sem consultar ninguém**: devolve `{"estado":"vivo","version":"1.6.0"}` com código 200 assim que escuta. Os três *probes* perguntam ali.
- **O `revisor` atende SIGTERM**: ao recebê-lo escreve `revisor: recibí terminated, apagando`, termina as requisições em andamento com um prazo próprio de 5 segundos e escreve `revisor: apagado limpio`.
- **O serviço de teste responde `GET /modo` sempre**, em qualquer modo, enquanto o processo viver. `GET /` é o que responde 503 em modo `caido`. Essa diferença decide aonde o *probe* dele pergunta.

A imagem do `curl` do Pod `depurar` continua sendo pública e fixada pelo digest; cada nó a baixa da internet na primeira vez.

## Os conceitos

### 5.1 O cluster da lição e o que ele sabe hoje

#### 5.1.1 Criar o cluster

Esta lição usa o seu próprio cluster, `curso-k8s-l5`, com a configuração de três nós da Lição 1. Cria-se assim, a partir da raiz do repositório do curso, com o mesmo cuidado de sempre:

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

O `export` só vale naquele terminal. Por isso a pasta temporária fica guardada em uma variável, `L5_TMP`, e o `echo` mostra o caminho completo: se for aberto outro terminal (em 5.7 será preciso um segundo), ali se repete o `export` com **esse** caminho, ou o `kubectl` falará com outro cluster. E no final da lição, a mesma variável é a que permite apagar a pasta sem escrever o caminho de cabeça. E a regra das lições anteriores continua de pé: **antes de cada** `apply`, `delete`, `patch` ou `exec` desta lição, `kubectl config current-context` deve dizer `kind-curso-k8s-l5`. O script confere isso sozinho antes de cada `kubectl` e para se não coincidir.

As saídas desta seção são da execução do `correr.sh`, que faz exatamente isso:

```text
$ kubectl config current-context
kind-curso-k8s-l5

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l5-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l5-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l5-worker2         Ready    <none>          15s   v1.37.0
```

O `kind load` imprime seis linhas `not yet present on node …, loading...`, duas imagens por três nós, como na Lição 3.

#### 5.1.2 O ponto de partida: o que a Lição 4 deixou

A pasta `programas/05-salud-recursos-apagado/punto-de-partida/` traz, sem mudar uma vírgula, os manifestos com que terminou a Lição 4: o `kustomization.yaml`, os dois Deployments e os dois Services. Como naquela lição, o token não é versionado: é gerado a cada execução. Desta vez é copiado para as duas pastas, a do ponto de partida e a da lição, para que as duas gerem **o mesmo** Secret:

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

Trinta e dois caracteres hexadecimais e uma quebra de linha: 33 bytes. Como na Lição 4, os parênteses e o `umask 077` fazem o arquivo nascer com permissão `0600` (`-rw-------`), legível só pelo dono, em vez do `0644` que a máscara habitual deixaria; o `cp` sem `-p` não copia as permissões do original: cria o arquivo novo com o modo do original filtrado pelo `umask`. Como `0600` já não tem permissões para grupo nem outros, a máscara não lhe acrescenta nada e a cópia também fica em `0600`; com um arquivo `0664` ou `0755` o resultado dependeria do `umask`, e `cp -p` é a opção que conserva modo, dono e datas. A primeira linha do bloco é a conferência de contexto escrita como comando: se o contexto não for o da lição, imprime “contexto equivocado” e não prossegue. Usá-la antes de cada mudança; o script faz isso sozinho. O nome do ConfigMap é o mesmo da Lição 4, `revisor-config-t6cm6872fk`, porque a lista de serviços não mudou. O do Secret é outro em cada execução, porque o token é novo.

#### 5.1.3 O que o cluster sabe hoje

```text
$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6f4dfdb898-8p5j2   1/1     Running   0          4s
revisor-f65c6dd96-248bg   1/1     Running   0          4s
revisor-f65c6dd96-575nn   1/1     Running   0          4s
revisor-f65c6dd96-pzxpk   1/1     Running   0          4s
```

Olhe a coluna `READY`: `1/1` aos **4 segundos**. O `revisor` já escutava na porta dele com essa idade? Provavelmente sim, porque inicia rápido. Mas o cluster não conferiu: marcou o Pod como pronto assim que o contêiner iniciou. É o que a Lição 3 antecipou em 3.4.3: sem *probes*, “pronto” quer dizer “o processo existe”. Se o `revisor` demorasse dez segundos para abrir a porta, o Service lhe mandaria tráfego durante esses dez segundos, e essas requisições falhariam.

Agora, o que o Pod diz de si mesmo:

```text
$ kubectl describe pod revisor-f65c6dd96-248bg | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests'
Name:             revisor-f65c6dd96-248bg
QoS Class:                   BestEffort

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
30

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
PodReadyToStartContainers=True Initialized=True Ready=True ContainersReady=True PodScheduled=True 
```

O `grep` procurou *probes*, `Limits` e `Requests`, e não encontrou nenhum: só o nome e uma linha, `QoS Class: BestEffort`. É a classe de qualidade de serviço do Pod, e `BestEffort` (“o que for possível”) é a que recebe um Pod que não declara nada de CPU nem de memória. 5.6 explica o que significa; adianto: é o primeiro que o nó expulsa quando fica sem memória. O prazo de desligamento é `30` segundos, o valor padrão, que ninguém escolheu. E as condições do Pod dizem `Ready=True`: é a condição que o EndpointSlice copia na coluna `ready` dele, e hoje se tornou verdadeira sem que ninguém perguntasse nada.

Três lacunas: ninguém confere que o `revisor` serve, ninguém diz quanto ele precisa, e o prazo de desligamento é um número herdado. As três se fecham com os manifestos desta lição.

### 5.2 Os manifestos da lição

A lição muda dois arquivos: os Deployments do `revisor` e do serviço de teste. O `kustomization.yaml`, os dois Services e o `depurar.yaml` são os mesmos da Lição 4 (o comentário da primeira linha do `kustomization.yaml` agora diz “Lecciones 4 y 5”). Os dois Deployments são **programas**: são aplicados com `kubectl apply -k .` a partir de `programas/05-salud-recursos-apagado/`.

#### 5.2.1 O `revisor`

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

Tudo o que não é novo já foi lido nas Lições 2 a 4. O novo são três blocos e um número:

- **`terminationGracePeriodSeconds: 10`**, no template do Pod (não no contêiner): quantos segundos o Pod tem para se desligar por conta própria antes que o cluster o mate. 5.7.
- **`resources`**, no contêiner: o valor reservado (`requests`) e o teto (`limits`) de CPU e memória. 5.6.
- **`startupProbe`, `readinessProbe` e `livenessProbe`**, no contêiner: os três *probes*. 5.3.

Repare no `port: http` dos três *probes*. É o mesmo truque da Lição 3 com o `targetPort` do Service: a porta vai por **nome**, então o número `8080` continua vivendo em um único lugar, `containerPort`. E `{path: /salud, port: http}` é YAML de uma linha: as chaves agrupam os dois campos do `httpGet` do mesmo modo que se fossem escritos em duas linhas com recuo. Escrevem-se assim porque os três *probes* compartilham a mesma pergunta e o que muda entre eles são os números.

#### 5.2.2 O serviço de teste

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

Um único *probe*, o de vida, e aponta para `/modo`, **não** para `/`. O comentário do arquivo diz isso e 5.5 demonstra: `GET /` é justamente o que o serviço de teste quebra de propósito em modo `caido`. Se o *liveness probe* perguntasse ali, o cluster o reiniciaria cada vez que fosse posto nesse modo, que é o contrário do que se quer de um serviço que existe para falhar. O Exercício 2 testa isso. Não leva *startup probe* porque inicia em milissegundos, nem *readiness probe* porque o curso quer que o `revisor` possa falar com ele mesmo que esteja fora do ar; o Exercício 1 mostra o que aconteceria com ele.

Os recursos são menores que os do `revisor` porque ele faz menos: não consulta ninguém nem guarda relatórios.

### 5.3 Os três *probes*

#### 5.3.1 Quem pergunta e como

A [documentação de *probes*](https://kubernetes.io/docs/concepts/workloads/pods/probes/) começa assim: um *probe* é “um diagnóstico que o `kubelet` realiza periodicamente sobre um contêiner”, e com os resultados dele “o Kubernetes pode reiniciar contêineres não saudáveis ou deixar de mandar tráfego a contêineres que não estão prontos”. Reter as duas peças: **o `kubelet`**, o do nó onde o Pod roda, não o plano de controle; e **duas reações distintas**, reiniciar ou deixar de mandar tráfego.

Os três *probes* do `revisor` usam `httpGet`: o `kubelet` faz uma requisição HTTP ao IP do Pod, à porta e ao caminho indicados. O [guia para configurar *probes*](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) diz quando conta como sucesso: “qualquer código maior ou igual a 200 e menor que 400 indica sucesso. Qualquer outro código indica falha”. Uma resposta que não chega a tempo também é falha. Há outras formas de perguntar (executar um comando dentro do contêiner, abrir uma conexão TCP ou uma chamada gRPC), mas para um servidor HTTP que já tem a sua rota de saúde, a requisição HTTP é a que pergunta o que importa: não “o processo existe?”, mas “ele responde?”. E o `revisor` não tem *shell* para executar comandos dentro, como se viu na Lição 2.

#### 5.3.2 Os números de um *probe*

Cada *probe* se ajusta com cinco campos. Os valores padrão são da mesma documentação de *probes*:

| Campo | O que é | Padrão |
|---|---|---|
| `initialDelaySeconds` | quanto esperar antes da primeira pergunta | 0 s |
| `periodSeconds` | de quanto em quanto tempo perguntar | 10 s (mínimo 1) |
| `timeoutSeconds` | quanto esperar uma resposta | 1 s |
| `successThreshold` | quantos sucessos seguidos, depois de uma falha, para voltar a “bem” | 1 (para vida e inicialização, **deve** ser 1) |
| `failureThreshold` | quantas falhas seguidas para concluir “mal” | 3 |

A regra para lê-los: **um *probe* reage depois de `failureThreshold` falhas seguidas, separadas por `periodSeconds`**. Uma falha isolada não faz nada. Isso evita que um tropeço de um segundo dispare um reinício. A documentação diz com estas palavras: depois que um *probe* falha `failureThreshold` vezes seguidas, “o Kubernetes considera que a verificação completa falhou”.

#### 5.3.3 O *startup probe*: “já iniciou?”

A documentação de *probes*: os de inicialização “verificam se a aplicação dentro de um contêiner já iniciou. Se há um *startup probe*, o Kubernetes não executa os *liveness* nem os *readiness probes* até que o de inicialização tenha sucesso”. E se falhar de vez, “o `kubelet` mata o contêiner”, que fica sujeito à sua política de reinício.

O do `revisor`: `periodSeconds: 1` e `failureThreshold: 10`. Pergunta a cada segundo, e dá ao programa até **10 tentativas**, uns 10 segundos, para responder pela primeira vez (1 × 10). É a conta quando cada tentativa falha de imediato; se o programa está travado e cada tentativa precisa esgotar o seu `timeoutSeconds` (1 segundo por padrão), o prazo se aproxima de 20. Assim que ele responde, deixa de perguntar enquanto aquele contêiner viver; se o contêiner reinicia, volta a começar. Diferentemente dos outros dois, só roda ao iniciar. Por que 10 segundos se o `revisor` inicia em menos de um? Porque o número não é para o dia bom, é para o dia ruim: um nó carregado, uma imagem que se lê devagar. E sobra pouco: um programa que não responde em 10 segundos tem algum problema.

O guia para configurar *probes* explica para que existe este *probe*. Há programas que demoram a iniciar, e se o *liveness probe* tivesse de esperar por eles, teria de ser lento e deixaria de detectar a tempo um bloqueio. A solução é separar: um *startup probe* com `failureThreshold * periodSeconds` “longo o bastante para cobrir o pior caso de inicialização”, e, uma vez que tem sucesso, “o *liveness probe* assume o controle”. O exemplo dele é um programa com até 5 minutos para iniciar (30 × 10 s). O `revisor` precisa de muito menos, mas o padrão é o mesmo.

#### 5.3.4 O *readiness probe*: “mando-te tráfego?”

A documentação: os *readiness probes* “determinam quando um contêiner está pronto para aceitar tráfego”, e, se um falha, “o controlador de EndpointSlices remove o IP do Pod dos EndpointSlices de todos os Services que coincidem com o Pod”. É a coluna `ready` da Lição 3, finalmente com conteúdo. Um detalhe que se verá no Exercício 1: na prática, o endereço não desaparece do EndpointSlice, mas fica com `ready=false`, e isso basta para que o `kube-proxy` deixe de lhe mandar tráfego. “Tirar do tráfego” é o efeito; “marcar como não pronto” é o mecanismo. E algo que o distingue do de inicialização: “os *readiness probes* rodam no contêiner durante todo o ciclo de vida dele”.

O mais importante é o que ele **não** faz: não reinicia nada. A documentação de *probes*, na descrição de `failureThreshold`: com um *readiness probe* falhando, “o `kubelet` continua rodando o contêiner que falhou e continua fazendo mais *probes*”, e apenas põe a condição `Ready` do Pod em `false`. Quando o *probe* volta a passar, o Pod volta à lista. É o *probe* para “estou bem, mas agora não”.

O do `revisor`: a cada 5 segundos, e 2 falhas seguidas o tiram do Service. No pior caso, um `revisor` que deixa de responder continua recebendo tráfego uns **10 segundos** (2 × 5) antes de sair da lista.

#### 5.3.5 O *liveness probe*: “continua vivo?”

A documentação: os *liveness probes* “determinam quando reiniciar um contêiner”. O exemplo que dá é um bloqueio (*deadlock*), “onde uma aplicação está rodando mas não consegue avançar”. Se o contêiner falha mais vezes do que o tolerado, “o `kubelet` reinicia esse contêiner”.

É o único dos três que destrói algo: um reinício derruba as conexões abertas e o estado em memória. Por isso a mesma página o acompanha de um aviso, que é a cena de quinta-feira em linguagem de manual: os *liveness probes* “devem ser configurados com cuidado para garantir que realmente indiquem uma falha irrecuperável da aplicação”, e “uma implementação incorreta de *liveness probes* pode provocar falhas em cascata”.

O do `revisor`: a cada 10 segundos, e 3 falhas seguidas o reiniciam. Um `revisor` travado é reiniciado em uns **30 segundos** (3 × 10). Mais lento que o de *readiness* de propósito: a documentação descreve esse padrão como o comum, a mesma rota barata para os dois e um `failureThreshold` maior no de vida, para que o Pod pareça “não pronto” um tempo antes de ser morto. Assim, um tropeço passageiro tira o Pod do tráfego (o que é barato) muito antes de reiniciá-lo (o que é caro).

#### 5.3.6 Os três juntos

| *Probe* | Pergunta | Se a resposta é “não” | Quando roda | No `revisor` |
|---|---|---|---|---|
| inicialização | já iniciou? | espera; se o prazo acaba, reinicia | só ao iniciar | até 10 s (1 s × 10) |
| disponibilidade (*readiness*) | mando-te tráfego? | tira-te do Service; **não** reinicia | sempre | sai em ~10 s (5 s × 2) |
| vida (*liveness*) | continua vivo? | **reinicia** o contêiner | sempre, depois do de inicialização | reinicia em ~30 s (10 s × 3) |

Os três do `revisor` perguntam o mesmo, `GET /salud`. Não é redundância: é a mesma pergunta com três consequências e três paciências distintas.

### 5.4 Os *probes* em ação

#### 5.4.1 Antes de aplicar, olhar o que muda

Primeiro se confere que as duas pastas têm o mesmo token, e depois pergunta-se ao cluster o que mudaria:

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

O `kubectl diff -k .` compara o que seria aplicado com o que existe; os dois `grep` ficam com as linhas que são **acrescentadas** (começam com `+ `) e tiram as que sempre mudam. Primeiro vem o Deployment de teste, depois o do `revisor`. Repare em três coisas. Nenhum ConfigMap nem Secret aparece: o token é o mesmo e a lista também, então os nomes com *hash* deles não mudam. Os campos que não foram escritos (`scheme: HTTP`, `successThreshold: 1`, `timeoutSeconds: 1`) aparecem com o valor padrão, o da tabela de 5.3.2: assim se vê o que de fato vai rodar. E o código de saída 1 não é um erro: o `kubectl diff` sai com 1 quando **há** diferenças, e com 0 quando não há. No final da lição será usado ao contrário, para conferir que não resta nenhuma.

Sobre essa última linha, `[código de salida: 1]`: não é o `kubectl` que a escreve, é o script, cada vez que um comando sai com um código diferente de 0, e será vista em outros blocos da lição. O script roda com `set -o pipefail`, então o código de um pipeline é o do primeiro comando que falha, aqui o `kubectl diff`. No terminal, sem essa opção, `echo $?` daria o código do último `grep`, que é 0. Para conferir sem pipeline: `kubectl diff -k . >/dev/null; echo $?`, que dá `1`.

#### 5.4.2 Aplicar

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

Só os dois Deployments mudam, e mudar o template de um Pod é um *rollout*: um ReplicaSet novo (`revisor-578c8dc8d9`) que substitui as réplicas uma a uma. As idades contam: 12, 11 e 9 segundos, um ou dois de diferença entre uma e outra. E desta vez a substituição esperou que cada réplica nova passasse pelo *readiness probe* antes de retirar uma antiga: um Deployment só conta como “disponível” um Pod pronto. Sem *probes*, “pronto” chegava antes de saber qualquer coisa.

O `describe` de uma das réplicas novas é o destino visto no início:

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

Assim se lê um *probe* no `describe`: `http-get http://:http/salud` é “requisição HTTP ao IP do Pod (vai vazio, entre `//` e `:`), à porta chamada `http`, caminho `/salud`”; depois vêm os cinco números de 5.3.2, com `delay` em vez de `initialDelaySeconds` e `period` em vez de `periodSeconds`. A classe passou de `BestEffort` a `Burstable`, e o prazo de desligamento de 30 para 10.

#### 5.4.3 Ler os *probes* no log

Cada *probe* é uma requisição HTTP de verdade, e o `revisor` escreve uma linha por cada requisição que atende. O log dele, com a hora de cada linha:

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

(`--timestamps` antepõe a cada linha a hora em que foi escrita, em UTC e com nanossegundos; o `sed` só recorta a data e os decimais para que caiba. O log de nenhuma outra máquina dirá estas horas: são as desta execução.)

Agora lê-lo como um relógio (são os minutos 45 e 46). O programa começou a escutar às `:44`. Às `:45` há **duas** requisições. A primeira é o ***startup probe***, que pergunta a cada segundo e aqui não precisou de mais de uma; desse momento em diante não volta a perguntar, e entram os outros dois. A segunda, no mesmo segundo, é a primeira de *readiness*: a documentação de *probes* avisa que, enquanto um contêiner não está pronto, esse *probe* pode rodar fora do período dele, para que o Pod fique pronto antes. Dali em diante há uma linha a cada 5 segundos (`:45`, `:50`, `:55`, `:00`, `:05`): a de *readiness*. E entre elas, uma a cada 10 (`:54`, `:04`): a de **vida** (*liveness*). Exatamente os `periodSeconds` do manifesto. O segundo comando confirma o resultado: o contêiner iniciou (`started` em `true`) e está pronto (`ready` em `true`).

Duas consequências práticas. A primeira: nesse ritmo, cada réplica escreve umas 18 linhas por minuto só de *probes*, mais de 25 mil por dia. Se o programa escreve uma linha por requisição, os *probes* vão encher o log dele, e convém saber isso antes de procurar algo ali. A segunda: os *probes* **custam**. Cada pergunta é trabalho do `kubelet` e do programa. Por isso o `/salud` deve ser barato, e por isso os períodos não se põem em um segundo “por via das dúvidas”.

### 5.5 Por que `/salud` não consulta ninguém

#### 5.5.1 A cena de quinta-feira, ao contrário

O `revisor` existe para dizer que outros serviços falham. Se a saúde dele dependesse desses serviços, o cluster o castigaria justamente quando faz o seu trabalho. Confere-se: o Pod `depurar` da Lição 3, o serviço de teste em modo `caido`, e 35 segundos de espera, mais que os 30 que o *liveness probe* leva para reiniciar.

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

(Em `correr.salida.txt` o token aparece escrito: o script o cola no comando. É um token de mentira dessa execução, que morreu com o cluster.)

Zero reinícios nos quatro Pods, todos `1/1`, e o relatório diz o que tem de dizer: `prueba FALLA codigo 503`. É o contrário da cena de quinta-feira, e a diferença está numa única decisão de projeto: `/salud` responde “estou vivo” sem perguntar nada a ninguém. O comentário da primeira linha do manifesto deixa isso escrito para quem vier depois.

Repare também no serviço de teste: `RESTARTS 0` e `1/1`, embora leve mais de 35 segundos respondendo 503 em `/`. O *liveness probe* dele pergunta por `/modo`, que continua respondendo. O cluster distingue “está falhando de propósito” de “está morto” porque se lhe perguntou o certo.

#### 5.5.2 E a documentação não diz que se verifiquem as dependências?

Diz, com nuance, e convém lê-lo inteiro. A documentação de *probes*, na parte de quando usar cada um: “quando a aplicação tem uma dependência estrita de serviços de *backend*, pode-se implementar um *liveness probe* e um *readiness probe*. O *liveness probe* passa quando a aplicação em si está saudável, mas o *readiness probe* verifica além disso que cada serviço de *backend* necessário esteja disponível”.

Duas coisas. A primeira é a regra que nunca muda: **o *liveness probe* olha somente para a aplicação**. Mesmo nesse parágrafo, a dependência vai no de *readiness*, nunca no de vida. Reiniciar o programa não conserta o banco de dados de outra equipe; só deixa sem programa.

A segunda é um critério, e depende do que o serviço faz. Se o serviço não consegue responder nada útil sem o banco de dados, tirá-lo do tráfego enquanto ele falta faz sentido. O `revisor` é o caso oposto: **a resposta útil dele é justamente dizer quem falta**. Se o *readiness probe* dele dependesse do `prueba`, ao cair o `prueba` o Service do `revisor` ficaria sem réplicas e o painel não carregaria, que é o sintoma da cena por outra via. Por isso os três *probes* do `revisor` perguntam a `/salud`, e `/salud` não pergunta a ninguém. O Exercício 1 deixa ver essa outra via com o serviço de teste.

### 5.6 `requests`, `limits` e a capacidade dos nós

#### 5.6.1 Dois números com dois donos distintos

A [documentação de gestão de recursos](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) os separa por quem os usa: “quando se especifica o *request* de um recurso para os contêineres de um Pod, o `kube-scheduler` usa essa informação para decidir em que nó pôr o Pod. Quando se especifica um *limit* para um contêiner, o `kubelet` faz cumprir esses limites para que o contêiner não use mais desse recurso do que o limite fixado”.

- **`requests` é uma reserva.** O escalonador a usa ao escolher o nó, e o `kubelet` a respeita depois: a mesma página diz que o `kubelet` também reserva “pelo menos a quantidade do *request*” para esse contêiner, de modo que, quando há competição pela CPU, o contêiner conserva a sua parte. Sobre o escalonador, a mesma página: o escalonador garante que, para cada recurso, a soma dos *requests* dos contêineres de um nó seja menor que a capacidade dele, e o faz mesmo que o uso real seja muito baixo: “o escalonador se recusa a pôr um Pod em um nó se a verificação de capacidade falha”. O `request` não é o que o contêiner usa: é o que o nó reserva para ele.
- **`limits` é um teto**, e o `kubelet` e o kernel do Linux o fazem cumprir o tempo todo.

#### 5.6.2 As unidades

**CPU.** A mesma página: “1 unidade de CPU equivale a 1 núcleo físico de CPU, ou a 1 núcleo virtual” se o nó é uma máquina virtual, e admitem-se frações: `0.1` é o mesmo que `100m`, “que se lê como cem milicpu”. O `revisor` pede `50m`, a vigésima parte de um núcleo, e o teto dele é `200m`, a quinta parte. A documentação recomenda a forma com `m` para quantidades menores que 1, porque se lê melhor.

**Memória.** Em bytes, com sufixos. Há duas famílias: `M`, `G` (potências de 10) e `Mi`, `Gi` (potências de 2). `32Mi` são 32 mebibytes, 33.554.432 bytes; `32M` seriam 32.000.000. O curso usa `Mi`. E uma armadilha que a documentação assinala com todas as letras: “preste atenção às maiúsculas e minúsculas dos sufixos”. `400m` de memória são 0,4 **byte**, não 400 megas: o `m` minúsculo é “mili”. Um `memory: 64m` escrito por engano é um teto de uma fração de byte: o contêiner nem consegue iniciar. (Isto não foi medido na lição; o que sim foi medido ao preparar o curso é que com um teto de `4Mi` o `revisor` já dá `StartError`, como diz o comentário do `memoria.yaml`.)

#### 5.6.3 O que acontece ao chegar ao teto

O teto não se aplica igual aos dois recursos, e a diferença é das que mais importam neste curso. A documentação de gestão de recursos:

- **CPU:** “os limites de `cpu` são aplicados estrangulando a CPU”. Se o `revisor` quisesse mais de `200m`, o kernel simplesmente não a dá: o programa fica mais lento, mas continua vivo.
- **Memória:** “os limites de `memory` são aplicados pelo kernel com mortes por falta de memória (OOM)”. A memória que um programa já tem não pode ser tirada pela metade, então, quando ele passa do limite e o kernel não consegue recuperar memória de outro lugar (por exemplo, do cache de arquivos), o mata. A documentação o chama de limite “reativo”: não evita o excesso, castiga-o. O erro de propósito desta lição é exatamente isso.

A regra prática que sai dali: um teto de CPU baixo deixa o programa **lento**; um teto de memória baixo o faz **morrer**. Os dois se põem, mas o de memória se põe com mais margem.

#### 5.6.4 O que um nó do kind diz ter

Quanto cabe em um nó? Pergunta-se a ele:

```text
$ kubectl get nodes -o custom-columns='NODO:.metadata.name,CPU:.status.allocatable.cpu,MEMORIA:.status.allocatable.memory'
NODO                         CPU   MEMORIA
curso-k8s-l5-control-plane   6     16342676Ki
curso-k8s-l5-worker          6     16342676Ki
curso-k8s-l5-worker2         6     16342676Ki
```

(`custom-columns` monta uma tabela com os campos pedidos; `allocatable` é o que o nó oferece aos Pods.)

Cada nó diz ter 6 CPUs e uns 15,6 GiB. São, os três, **toda** a máquina virtual do Docker desta execução: 6 CPUs e 16 GiB. Isto é o kind, e nunca esquecer: os nós dele são contêineres na mesma máquina, e cada um vê e anuncia os recursos completos do host. Para o escalonador há 18 CPUs; no metal há 6. Em um cluster real, cada nó anuncia o seu. No kind, `requests` e `limits` funcionam igual a um real —o escalonador conta e o kernel corta—, mas a capacidade que se vê é uma miragem de laboratório. No Mint, os números serão os do computador usado.

O que o escalonador já reservou em um nó de trabalho:

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

`Requests` soma o que pedem todos os Pods do nó, os do curso e os do sistema. Nesta execução, no `worker` caiu uma réplica do `revisor` (os `50m` e `32Mi` dela, e os `200m` e `64Mi` de teto, que são toda a coluna `Limits`); o resto dos *requests* são dos Pods do sistema que rodam em cada nó, como a rede do kind. A nota do início, “os limites totais podem passar de 100 %”, diz algo importante: o escalonador **não** conta os `limits`. Pode-se prometer mais teto do que existe, porque se supõe que nem todos chegam ao teto ao mesmo tempo. O que o escalonador não deixa passar de 100 % da capacidade alocável é a soma de `requests` ao decidir onde cai um Pod comum (os Pods estáticos do próprio nó não passam por ele).

#### 5.6.5 Quanto o `revisor` usa de verdade

Os números do manifesto são decisões. Estão perto da realidade? O `kubelet` fala com o `containerd` do nó, e o `crictl` pode perguntar-lhe quanto cada contêiner usa (é a mesma ferramenta da Lição 2, dentro do nó):

```text
$ docker exec curso-k8s-l5-worker2 crictl stats --label io.kubernetes.container.name=revisor | sed 's/^.\[2J.\[H//'
CONTAINER           NAME                CPU %               MEM                 DISK                INODES              SWAP
060935005135f       revisor             0.02                1.733MB             45.06kB             13                  0B
1be34aa64c901       revisor             0.03                1.733MB             45.06kB             13                  0B
```

(`--label` filtra os contêineres chamados `revisor`; no `worker2` caíram duas réplicas. O `crictl stats` imprime no início uns códigos para limpar a tela, e o `sed` os remove.)

Menos de 2 MB de memória e a CPU quase em zero, em repouso. O `request` de `32Mi` é mais de quinze vezes isso. Não é um erro: o `revisor` cresce quando monta um relatório e consulta vários serviços ao mesmo tempo, e um `request` é o que o programa precisa no dia normal com carga, não em repouso. Mas o número confirma algo que será usado daqui a pouco: o `revisor` **não serve** para provocar um `OOMKilled`, porque quase não usa memória. Para vê-lo é preciso um programa que a peça.

Em um cluster real, essa medição se faz com `kubectl top`, que precisa do `metrics-server`. Chega na Lição 9, porque é ele que alimenta o escalonamento automático.

#### 5.6.6 As classes de qualidade de serviço

Com `requests` e `limits` o cluster classifica cada Pod em uma de três classes. A [documentação de classes de QoS](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) dá os critérios:

| Classe | Quando | Neste curso |
|---|---|---|
| `Guaranteed` | todo contêiner tem `requests` e `limits` de CPU e de memória, e em cada um o `request` é **igual** ao `limit` | nenhum |
| `Burstable` | não é `Guaranteed`, mas pelo menos um contêiner tem algum `request` ou `limit` | `revisor`, `prueba`, `depurar`, `memoria` |
| `BestEffort` | nenhum contêiner declara nada de CPU nem de memória | o `revisor` de 5.1 |

E para que serve: quando um nó fica sem recursos, “o Kubernetes expulsa primeiro os Pods `BestEffort` desse nó, depois os `Burstable` e por último os `Guaranteed`”. E acrescenta que, quando a expulsão é por falta de recursos, só são candidatos os Pods que usam mais do que pediram. A página mais detalhada de expulsão por pressão do nó precisa: o `kubelet` expulsa primeiro os `BestEffort` e os `Burstable` que excedem o `request`, e os `Guaranteed` e os `Burstable` que não o excedem são expulsos por último, se o anterior não bastou. Ou seja, respeitar o `request` coloca no final da fila, não fora dela. Outra razão para que o `request` se pareça com o uso real. O `revisor` de 5.1 era o primeiro da fila. Hoje é `Burstable`, porque o teto dele é maior que o valor reservado: pode “se esticar” de `50m` a `200m` se houver CPU livre. Para torná-lo `Guaranteed` seria preciso igualar os dois números, e pagar sempre o teto como reserva. Para um programa que em repouso usa 2 MB, o curso prefere `Burstable`.

### 5.7 O desligamento ordenado

#### 5.7.1 O que acontece quando um Pod é apagado

A [documentação do ciclo de vida de um Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) conta a sequência. Ao pedir que um Pod seja apagado, o cluster anota um prazo, e o `kubelet` do nó começa o desligamento: pede ao *runtime* do contêiner que mande “um sinal TERM” (SIGTERM) “ao processo 1 dentro de cada contêiner”, isto é, ao processo principal, o que tem o PID 1. E depois: “uma vez que o prazo vence, o sinal KILL é mandado aos processos que restarem”. SIGTERM é um pedido (“desligue-se, por favor”); SIGKILL não é um pedido, é o kernel terminando o processo sem lhe perguntar. O prazo padrão é de **30 segundos**, e se muda com `terminationGracePeriodSeconds`.

Ao mesmo tempo acontece outra coisa, a que conecta com a Lição 3: o plano de controle tira do tráfego o Pod que está se desligando. A mesma página: os *endpoints* dele não são apagados de imediato do EndpointSlice, mas ficam marcados como `terminating` e “sempre têm o estado `ready` em `false`”, então não recebem tráfego novo. (A página de EndpointSlices acrescenta uma exceção que o curso não usa: `ready` é sempre verdadeiro em um Service com `publishNotReadyAddresses: true`.) As duas coisas ocorrem ao mesmo tempo, não uma depois da outra. Essa corrida entre “o Pod recebe SIGTERM” e “todos os nós percebem que não devem mais lhe mandar tráfego” é a que a Lição 9 resolve com `preStop`. Hoje basta saber que existe.

#### 5.7.2 Vê-lo

*Um aviso sobre os nomes.* As saídas desta seção e das duas seguintes vêm da execução do script, onde o desligamento ocorreu **depois** dos dois erros de “O erro que se vai ver”. Por isso o Pod que aqui é apagado, `g9lhl`, ainda aparece vivo na seção do `Pending`, e o `hfjmq` que o repõe já aparece no hábito de segurança: não é um erro do cluster nem da lição. Em outra máquina, se a lição for seguida na ordem do texto, os nomes serão outros.

Para ver o que o `revisor` escreve nos últimos segundos dele, abrir um **segundo terminal** e prepará-lo assim, com o caminho que o `echo` de 5.1.1 imprimiu (no primeiro terminal, `echo "$KUBECONFIG"` o devolve):

```bash
# En la SEGUNDA terminal. Pega la ruta completa; la de abajo es solo la forma.
export KUBECONFIG=/tmp/curso-k8s-l5.XXXX/kubeconfig
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
kubectl logs -f <nombre de una réplica del revisor>
```

Se a conferência disser “contexto equivocado”, o caminho não é o certo: não prosseguir. Com o `kubectl logs -f` rodando ali, no primeiro terminal apaga-se essa réplica:

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

(`-f` segue o log ao vivo até o contêiner terminar; o script o guarda em um arquivo e mostra as quatro últimas linhas.)

O `kubectl delete` espera que o Pod desapareça de verdade, e levou **menos de um segundo** (o script mede em segundos inteiros e anotou `0 s`; em outras execuções anotou 1 e 3). As duas últimas linhas do log são o desligamento ordenado: o `revisor` recebeu `terminated` (assim o Go chama o SIGTERM), deixou de aceitar conexões novas, esperou que terminassem as que tinha e saiu por conta própria: `apagado limpio`. Nunca chegou ao SIGKILL. E o ReplicaSet já tinha reposto a réplica: `hfjmq`, de 3 segundos.

#### 5.7.3 Por que 10 segundos

Se o `revisor` se foi em menos de um segundo, para que mudar o prazo de 30 para 10? Porque o prazo não é para o desligamento bom, é para o **ruim**. Se um dia o `revisor` travar e não atender o SIGTERM, o cluster o mata aos 10 segundos e não aos 30. Durante esse tempo o Pod ocupa o seu lugar: um *rollout* de três réplicas que se desligam mal poderia demorar minutos a mais.

O número também não é ao acaso: o `revisor` dá a si mesmo 5 segundos para terminar as requisições em andamento, e o prazo do cluster tem de ser **maior** que o da aplicação, ou o SIGKILL a interrompe no meio da despedida. 10 é o dobro de 5. Quando a Lição 9 acrescentar o `preStop`, que também roda dentro deste prazo, o número sobe para 15.

O Exercício 3 mostra o que acontece com um processo que **não** atende o SIGTERM: o Pod `depurar`.

## O erro que se vai ver

Esta lição tem dois erros de propósito, um para cada número de `resources`: o teto de memória e o valor reservado de CPU.

### OOMKilled: passar do teto de memória

Como se viu em 5.6.5, o `revisor` usa menos de 2 MB; com ele não dá para ver um `OOMKilled`. Usa-se um Pod avulso, `memoria.yaml`, que é um **programa** que falha de propósito: tenta guardar 40 MB em uma variável de *shell* com um teto de 16 MiB.

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

É a imagem de `curl` do `depurar`, com o mesmo `securityContext`, e outro programa: `head -c 40000000 /dev/zero` produz 40 milhões de bytes em zero, `tr` os converte em letras `x`, e `a=$(…)` obriga o *shell* a guardá-los todos em memória. `restartPolicy: Never` faz com que, ao morrer, fique morto para que possa ser examinado.

```text
$ kubectl apply -f memoria.yaml
pod/memoria created

$ kubectl get pod memoria
NAME      READY   STATUS      RESTARTS   AGE
memoria   0/1     OOMKilled   0          20s
```

`STATUS OOMKilled`: morto por falta de memória (*Out Of Memory*). Lê-se em ordem, do sintoma à causa.

**Primeiro, a razão e o código:**

```text
$ kubectl get pod memoria -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
OOMKilled 137
```

O código de saída `137` é uma convenção do Unix: 128 mais o número do sinal que matou o processo. 137 − 128 = 9, e o sinal 9 é SIGKILL. Ninguém pediu ao programa que se fosse; o kernel o terminou. Mas atenção: um 137 diz “mataram com SIGKILL”, não quem nem por quê. Pode ser o kernel por memória, como aqui, ou o `kubelet` porque o prazo de desligamento venceu, que é o que o Exercício 3 provoca. O que separa os dois casos é a razão: `OOMKilled` em um, outra coisa no outro. Sempre olhar a razão junto com o código.

**Segundo, até onde chegou:**

```text
$ kubectl logs memoria
pidiendo 40 MB
```

Escreveu a primeira linha e nunca a segunda, `no debería llegar aquí`. Morreu no meio da alocação.

**Terceiro, o teto que o explica:**

```text
$ kubectl describe pod memoria | grep -E '^QoS Class:|Reason:|Exit Code:|Limits:|memory:'
      Reason:       OOMKilled
      Exit Code:    137
    Limits:
      memory:  16Mi
      memory:     16Mi
QoS Class:                    Burstable
```

`Limits: memory: 16Mi` (o segundo `memory: 16Mi` é o do bloco `Requests`, que o `grep` também pega). Pediu 40 MB contra um teto de 16 MiB: o kernel fez exatamente o que diz 5.6.3. O [guia de atribuir memória](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) provoca o mesmo erro com outro programa e, na seção “Exceed a Container's memory limit”, resume assim: um contêiner pode passar do `request` se o nó tem memória, mas não do `limit`.

**Como se corrige.** Não com um teto mais alto “para ver se assim vai”. A documentação de gestão de recursos, na seção de solução de problemas, diz a ordem: diante de um `OOMKilled`, o passo seguinte é revisar o código em busca de um vazamento de memória; se o programa se comporta como o esperado, então sim, sobe-se o teto (e talvez o valor reservado). Aqui o programa faz justamente o que deve fazer, que é falhar; apaga-se:

```text
$ kubectl delete pod memoria
pod "memoria" deleted from default namespace
```

Se fosse um contêiner de um Deployment, o `kubelet` o reiniciaria uma e outra vez, com esperas crescentes entre as tentativas: a documentação do ciclo de vida dá a série, “10 s, 20 s, 40 s, …”, com um teto de 5 minutos. Essa espera é o que o `kubectl get pods` mostra como `CrashLoopBackOff`. Se aparecer um `CrashLoopBackOff`, olhar a coluna `RESTARTS` e a razão do último término antes de mexer em qualquer coisa: pode ser um `OOMKilled`, pode ser um programa que sai com erro, pode ser um *liveness probe* mal escrito. São três consertos distintos.

### Pending: pedir um valor reservado que não cabe

O segundo erro vai ao outro número: um `request` de CPU que nenhum nó pode reservar. É provocado com um patch direto no Deployment, para que a correção seja aplicar de novo o arquivo.

Antes de uma mudança assim, a conferência de contexto de 5.1.2:

```bash
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
```

```text
$ kubectl patch deployment revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"50"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"50"}]'
deployment.apps/revisor patched
```

O `kubectl patch --type=json` muda campos soltos de um objeto vivo: aqui, o `request` e o `limit` de CPU do primeiro contêiner passam a `50`. **Cinquenta CPUs**, não cinquenta milicpu: falta o `m`. É um erro de digitação fácil de cometer, e o cluster o aceita sem reclamar: `50` é uma quantidade válida.

**Primeiro, o sintoma:**

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

Quatro Pods: um ReplicaSet novo (`revisor-5b8f867ccf`) com uma réplica em `Pending`, e as três antigas intactas. `Pending` quer dizer que o Pod existe no `kube-apiserver` mas ninguém lhe deu nó. E o *rollout* ficou travado em “1 de 3”: o `rollout status` desistiu aos 15 segundos que lhe foram dados.

**Segundo, a causa, nos eventos do Pod:**

```text
$ kubectl describe pod revisor-5b8f867ccf-9x42x | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  25s   default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

(`sed -n '/^Events:/,$p'` imprime desde a linha `Events:` até o final.) Quem fala é o escalonador (`default-scheduler`), e a mensagem dele se lê nó por nó:

- `0/3 nodes are available`: nenhum dos três nós serve.
- `1 node(s) had untolerated taint(s)`: um tem uma “mancha” (*taint*) que este Pod não tolera. É o nó de controle, que por padrão não recebe os Pods do curso; viu-se na Lição 1, quando os Pods só caíam nos nós de trabalho.
- `2 Insufficient cpu`: os outros dois não têm CPU suficiente. Pedem 50; cada um anuncia 6.
- `preemption: … Preemption is not helpful`: o escalonador também considerou tirar Pods de menor prioridade para abrir lugar, e concluiu que não ajudaria. Mesmo esvaziando um nó, 50 não cabem em 6.

A documentação de gestão de recursos traz este mesmo evento como o primeiro caso de solução de problemas: se o escalonador não encontra um nó onde caiba o Pod, “o Pod fica sem atribuição até que se encontre um lugar”, e um evento é produzido cada vez que falha. As saídas que sugere são adicionar nós ou liberar espaço; a que se aplica aqui é a terceira, a óbvia: pedir o certo.

**Terceiro, o que não quebrou:**

```text
$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

O serviço continua respondendo. Por que o Deployment não retirou nenhuma réplica antiga? Pela estratégia de atualização dele, que a Lição 9 estuda a fundo: a [documentação de Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) diz que, por padrão, `maxUnavailable` é 25 % “arredondando para baixo” e `maxSurge` é 25 % “arredondando para cima”. Com 3 réplicas: 0,75 desce para **0** réplicas que podem faltar, e 0,75 sobe para **1** que pode sobrar. O Deployment criou uma nova a mais e ficou esperando que estivesse disponível para retirar uma antiga. Nunca esteve. Um *rollout* travado é incômodo; um que derrubasse as réplicas boas para substituí-las por réplicas que não cabem seria um apagão. Essa regra protege de um erro de digitação.

**A correção** é a de sempre neste curso: o arquivo é a verdade, e se aplica de novo.

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

As mesmas três réplicas de antes, com as mesmas idades. O template voltou a ser idêntico ao do ReplicaSet `revisor-578c8dc8d9`, que já tinha as suas três réplicas, então não houve nada a substituir: o Deployment deixou em zero o ReplicaSet quebrado e o Pod `Pending` desapareceu. É o mesmo efeito visto na Solução 3 da Lição 2.

**A ordem, para qualquer Pod que não está `Running`:**

1. `kubectl get pods`: `Pending`, `OOMKilled`, `CrashLoopBackOff`?
2. Se é `Pending`, os eventos do Pod: o que diz o escalonador de cada nó?
3. Se morreu, a razão e o código do último término (`OOMKilled 137`, um `Error` com outro código) e o log dele (`kubectl logs`, ou `--previous` se já reiniciou).
4. Antes de mudar um número, perguntar se o número está errado ou se o programa está errado.

## O hábito de segurança da lição: todo contêiner com valor reservado e teto

A tabela de hábitos do curso atribui a esta lição duas coisas: `requests` e `limits` em todo contêiner; os *probes* não dependem de serviços alheios. A segunda foi conferida em 5.5. A primeira se confere num relance:

```text
$ kubectl get pods -o custom-columns='POD:.metadata.name,QOS:.status.qosClass,CPU_PIDE:.spec.containers[0].resources.requests.cpu,CPU_TOPE:.spec.containers[0].resources.limits.cpu,MEM_PIDE:.spec.containers[0].resources.requests.memory,MEM_TOPE:.spec.containers[0].resources.limits.memory'
POD                        QOS         CPU_PIDE   CPU_TOPE   MEM_PIDE   MEM_TOPE
depurar                    Burstable   10m        100m       16Mi       32Mi
prueba-b896986b5-kzrmk     Burstable   10m        100m       16Mi       32Mi
revisor-578c8dc8d9-hfjmq   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-jlh4b   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-xhqt8   Burstable   50m        200m       32Mi       64Mi
```

Cinco Pods, cinco linhas completas, nenhuma `<none>`, nenhum `BestEffort`. Incluindo o `depurar`, que é “só para olhar”: a Lição 3 lhe pôs teto desde o princípio, e hoje se sabe por quê.

Por que é um hábito de **segurança** e não só de ordem? Porque um contêiner sem teto de memória é um contêiner que pode derrubar os vizinhos. A [documentação de `LimitRange`](https://kubernetes.io/docs/concepts/policy/limit-range/) começa com a frase que explica: “por padrão, os contêineres rodam com recursos de computação sem limite em um cluster do Kubernetes”. Um erro de programação (um vazamento de memória, um laço que não termina) ou um ataque (alguém que manda requisições enormes de propósito) em um contêiner sem teto se converte em um problema do **nó inteiro**: o nó fica sem memória e começa a expulsar Pods, começando pelos `BestEffort`, que podem ser de outra equipe. Com um teto, o dano fica dentro do contêiner que o causou: morre ele, com um `OOMKilled` que diz exatamente o que aconteceu, e mais ninguém.

O mesmo com a CPU, com uma nuance: um contêiner sem teto de CPU que entra em um laço infinito devora toda a CPU livre do nó e deixa os vizinhos lentos. Os que declararam `requests` conservam a sua parte, e por isso o valor reservado também protege; os que não declararam nada ficam com o que sobrar. Com teto, quem se afoga é ele.

**O que ele protege e o que não.** Os tetos limitam o dano **dentro de um nó**; não impedem que alguém crie cem Pods. Para isso um cluster real usa `ResourceQuota` (um total por namespace) e `LimitRange` (um máximo e um valor padrão por contêiner). Este curso não os instala, e os nomeia para que se saiba que existem. E os *probes* não são uma defesa: um atacante que entra no `revisor` não vai quebrar o `/salud`. O que sim evitam é a outra metade do problema, que um erro humano converta uma falha pequena em uma queda em cadeia.

## Erros comuns

**Pôr no *liveness probe* algo que depende de outros.** É a cena de quinta-feira. Um banco de dados fora do ar não se conserta reiniciando os clientes dele. O *liveness probe* pergunta pelo processo, e nada mais.

**Usar a mesma paciência para os três *probes*.** Se o de vida reage tão rápido quanto o de *readiness*, um tropeço de dez segundos reinicia em vez de apenas afastar do tráfego. O de vida vai mais lento.

**Um *liveness probe* sem *startup probe* em um programa lento para iniciar.** O `kubelet` começa a perguntar assim que o contêiner inicia; se o programa demora mais que `failureThreshold × periodSeconds`, é reiniciado antes de terminar de iniciar, e outra vez, e outra. O *startup probe* existe para isso.

**Uma rota de saúde cara.** Se o `/salud` consulta o banco de dados, monta um relatório ou escreve em disco, cada *probe* faz isso, em cada réplica, a cada poucos segundos. Barata e local.

**Apontar o *probe* para uma rota que muda de código de propósito.** O `GET /` do serviço de teste é uma dessas: 503 em modo `caido` por projeto. O Exercício 2 mede isso.

**Contêineres sem `requests` nem `limits`.** Ficam `BestEffort`: o escalonador não lhes reserva nada, ninguém lhes põe teto e são os primeiros a sair quando o nó aperta.

**Escrever `memory: 64m` ou `cpu: 50`.** O `m` minúsculo em memória são milibytes; um número sem `m` em CPU são núcleos inteiros. O segundo é o `Pending` desta lição.

**Subir o teto de memória cada vez que há um `OOMKilled`.** Se é um vazamento, só o atrasa. Primeiro se pergunta se o programa está bem.

**Tomar a capacidade de um nó do kind como real.** Cada nó anuncia toda a máquina. O que cabe no kind não diz o que cabe em produção.

**Deixar o prazo de desligamento padrão sem pensar.** Trinta segundos pode ser muito para um programa que se desliga em um, e pouco para um que precisa terminar um trabalho longo. Escolhe-se, e se escolhe maior que o prazo interno do programa.

**Um processo principal que ignora o SIGTERM.** O cluster esperará o prazo completo cada vez que for desligado. O Exercício 3 mede isso.

## Exercícios

Os três primeiros são executados no cluster da lição, em ordem e a partir do estado em que ficou depois de 5.7, com o Pod `depurar` ainda vivo. Antes de cada um, `kubectl config current-context` deve dizer `kind-curso-k8s-l5`. O `correr.sh` os executa do mesmo modo, e a saída está em `correr.salida.txt`. **Antes** de executar cada um, escrever no [diário de bordo](bitacora.md) o que se acredita que vai acontecer. O quarto é escrito com palavras próprias.

### Exercício 1 — Um *readiness probe* no serviço de teste

O `fig05_01.prueba-disponibilidad.yaml` é o Deployment de teste desta lição com uma única diferença: acrescenta um *readiness probe* em `GET /`, a cada 5 segundos, com 2 falhas para sair do tráfego.

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

Aplicá-lo, esperar que o Pod novo esteja `1/1` e pô-lo em modo `caido`. Antes de olhar, prever: aos 15 segundos, o que diz a coluna `READY`? E `RESTARTS`? O que diz o EndpointSlice do Service `prueba`? Perguntar com `kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}'`. Que detalhe dá o relatório do `revisor`? E a pergunta difícil: `kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano` funciona para consertá-lo? Se não, como devolvê-lo a `sano`? Ao terminar, aplicar de novo `kubectl apply -k .`.

### Exercício 2 — Um *liveness probe* que pergunta o que não deve

O `fig05_02.prueba-vida-mala.yaml` é o Deployment de teste da lição com uma única linha diferente: o *liveness probe* pergunta a `GET /` em vez de `GET /modo`.

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

Aplicá-lo, esperar que esteja `1/1` e pô-lo em modo `caido`. Prever, com os números do *probe*: quantos segundos leva o primeiro reinício, mais ou menos? Que eventos o Pod deixa (procurar as razões `Unhealthy` e `Killing`)? Depois do reinício, o que responde `GET /modo`? O que diz o relatório do `revisor`? E explicar por que isto é pior do que parece: o que aconteceu com a evidência? Ao terminar, aplicar de novo `kubectl apply -k .`.

### Exercício 3 — Quanto demora para o Pod de depuração ir embora (projeto)

Em 5.7 o `revisor` se desligou em menos de um segundo. Agora é a vez do `depurar`, o Pod de curl da Lição 3. Antes de apagá-lo, olhar duas coisas: o `terminationGracePeriodSeconds` dele (não o declara) e que processo é o número 1 dentro do contêiner dele (`kubectl exec depurar -- ps`). Prever quanto vai demorar `kubectl delete pod depurar`, medi-lo com o relógio e explicar o número. Depois propor duas formas de ele ir embora mais rápido, uma no manifesto e outra no comando.

### Exercício 4 — Cabe uma quarta réplica?

Com os números desta lição: o `revisor` pede `50m` de CPU e `32Mi` de memória, e na execução da lição cada nó de trabalho anunciava 6 CPUs (usar o número do `kubectl get nodes` se for outro). Em no máximo cinco frases: quantas réplicas do `revisor` caberiam, em teoria, em um nó de trabalho, contando só a CPU? Por que esse número é enganoso no kind? Que número olharia o escalonador para decidir, o `request` ou o `limit`? E que classe de QoS teria o `revisor` se fossem escritos `requests` e `limits` iguais, `200m` e `64Mi`, e o que se ganharia e o que se pagaria?

## Soluções

### Solução 1

Medido em `correr.salida.txt`:

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

**`READY 0/1` com `RESTARTS 0`.** O *readiness probe* falhou duas vezes seguidas (503 em `/`) e o `kubelet` marcou o Pod como não pronto, sem reiniciá-lo: é exatamente a diferença de 5.3.4. O EndpointSlice confirma: o endereço continua na lista, mas com `ready=false` e `serving=false`, então ninguém lhe manda tráfego.

**O relatório mudou de detalhe.** Em 5.5 dizia `FALLA codigo 503`: o serviço respondia, mal. Agora diz `connection refused`: com a única réplica dele fora da lista, o Service `prueba` não tem a quem mandar a conexão e a recusa na hora, o mesmo código 7 da Lição 3. O `revisor` continua dizendo `FALLA`, mas perdeu informação: já não se sabe **o que** o serviço respondeu, só que não há ninguém.

**E ficou-se sem porta para consertá-lo.** O `POST /modo/sano` pelo nome `prueba` também passa pelo Service, e também é recusado (código 7). O Pod está vivo e escutando; o que já não existe é o caminho. A saída é falar com o IP do Pod diretamente, que não passa pelo Service: `10.244.2.10`, tirado do mesmo EndpointSlice ou de `kubectl get pods -o wide`. Respondeu `modo: sano`, o *probe* voltou a passar e o Pod voltou a `1/1` em alguns segundos. É a Lição 3 ao contrário: ali se aprendeu a **não** usar IPs de Pods; aqui se usa de propósito, uma vez, para depurar.

A lição geral: um *readiness probe* tira o Pod de **todo** o tráfego do Service, incluindo o de administração. Para um serviço como este, cujo trabalho é falhar de forma visível, é a decisão errada. Por isso o manifesto da lição não o leva.

### Solução 2

Medido em `correr.salida.txt`:

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

**27 segundos, e o contêiner foi reiniciado.** O *probe* pergunta a cada 10 segundos e tolera 3 falhas: três perguntas falhas cabem em uns 20 a 30 segundos, conforme o ponto do ciclo em que o *probe* estava quando o modo foi mudado. Os eventos contam a história em duas linhas: `Unhealthy … statuscode: 503` (o *probe* falhou) e `Killing … failed liveness probe, will be restarted` (o `kubelet` o matou por isso). `RESTARTS 1 (4s ago)`: o reinício foi há 4 segundos. (Um evento `Unhealthy` se repete a cada falha, mas o cluster agrupa os iguais em uma só linha com um contador.)

**E aqui está o grave: depois do reinício, `modo: sano` e o relatório diz `OK`.** O serviço de teste guarda o modo dele em memória; ao reiniciar, inicia no modo padrão. O cluster “consertou” o sintoma apagando a evidência. Se isto fosse um serviço de verdade com um problema de verdade, o `revisor` teria reportado a falha por 27 segundos e depois tudo verde, e alguém concluiria que “se consertou sozinho”. E da próxima vez que falhar, o mesmo. Com o *probe* bem escrito (`/modo`), em 5.5 o serviço ficou em `caido` o tempo que se quis e o relatório disse a verdade o tempo todo. Isto é o aviso da documentação em ponto pequeno: um *liveness probe* que não detecta uma falha irrecuperável e sim outra coisa acaba fazendo dano.

Depois dos dois exercícios, o script aplica de novo `kubectl apply -k .` e confere que o cluster é outra vez exatamente o que dizem os arquivos. É o `kubectl diff` de 5.4.1, agora ao contrário: sem diferenças, sai com 0 e a mensagem é impressa.

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

Fazer o mesmo no cluster antes do Exercício 3: se o `diff` imprimir algo, algum exercício ficou sem ser desfeito.

### Solução 3

Medido em `correr.salida.txt`:

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

**32 segundos: o prazo completo, mais o que levam o SIGKILL e a limpeza.** O manifesto não declara prazo, então vale o padrão, 30. O processo número 1 do contêiner é `sleep 3600`. O `kubelet` lhe mandou SIGTERM, e o `sleep` não fez nada: no Linux, o processo com PID 1 de um espaço de processos ignora os sinais para os quais não instalou um *handler*, e o `sleep` não instala nenhum. Então o cluster esperou os 30 segundos e mandou SIGKILL, que não pode ser ignorado. Enquanto isso, o `kubectl delete` esperava. O `revisor`, em compensação, sim instala o *handler* de SIGTERM dele (por isso escreve `recibí terminated`), e se foi em 1 segundo.

Duas formas de ele ir embora mais rápido:

- **No manifesto:** `terminationGracePeriodSeconds: 1` no Pod `depurar`. Não tem nada a terminar com ordem; um prazo curto não lhe tira nada. (Outra opção é que o processo principal dele atenda SIGTERM, por exemplo com um `sh` que instale um `trap`; dá mais trabalho para um Pod de usar e jogar fora.)
- **No comando:** `kubectl delete pod depurar --wait=false`, que pede a remoção e retorna de imediato sem esperar. O Pod demora o mesmo para ir embora; só quem opera deixa de esperá-lo. É o que o script da Lição 3 faz no final. Existe também `--grace-period` no `kubectl delete` para mudar o prazo dessa remoção. A ajuda dele (`kubectl delete --help`) diz que `--grace-period=1` é o desligamento imediato, e que o 0 só é aceito junto com `--force`, que além disso remove o Pod da API sem esperar que o nó confirme que o contêiner terminou. Usar com cuidado.

### Solução 4

Uma resposta possível: “Contando só a CPU, em um nó que anuncia 6 CPUs (os desta execução) cabem 6.000 m / 50 m = 120 réplicas, menos o que já pedem os Pods do sistema (nesta execução, o nó já tinha `150m` reservados contando uma réplica). Esse número é enganoso porque no kind os três nós anunciam a máquina completa: o escalonador acredita que há 18 CPUs onde há 6, e as réplicas dos três nós disputariam os mesmos núcleos. O escalonador decide com o `request`, nunca com o `limit`: os limites podem somar mais de 100 % de um nó. Com `requests` e `limits` iguais em `200m` e `64Mi`, o Pod seria `Guaranteed`: o último a ser expulso quando o nó aperta, e com a CPU sempre reservada. Pagar-se-ia reservando quatro vezes mais CPU e o dobro de memória do que o `revisor` precisa no dia normal, de modo que caberiam quatro vezes menos réplicas por nó.”

## Apagar o cluster

Quando terminar os exercícios, apague o cluster da lição. Nada deve ficar vivo na máquina:

```text
$ kind delete cluster --name curso-k8s-l5
Deleting cluster "curso-k8s-l5" ...
Deleted nodes: ["curso-k8s-l5-worker" "curso-k8s-l5-control-plane" "curso-k8s-l5-worker2"]
(borrar tardó 1 s)

$ kind get clusters | grep -c curso-k8s-l5
0
```

(A linha entre parênteses é escrita pelo script, que mede a remoção.) O `--name` é obrigatório: sem ele, o kind apagaria o cluster chamado `kind`, que pode ser de outra pessoa ou de outro projeto.

Ficam na máquina local a pasta temporária do `kubeconfig` e os dois `token.txt`. Apagam-se assim, a partir de `programas/05-salud-recursos-apagado`:

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

O `case` só deixa passar um caminho que comece com `/tmp/curso-k8s-l5.` e tenha algo depois, a forma exata da que foi criada em 5.1.1. Se `L5_TMP` estiver vazia (por exemplo, porque se está em outro terminal, onde nunca foi definida) ou valer outra coisa, não apaga nada e diz por quê. É a mesma proteção que o `correr.sh` usa ao limpar: um `rm -rf` que pode ser copiado e colado precisa se proteger sozinho. Se o segundo terminal de 5.7 continuar aberto, fechá-lo: ali só foi feito o `export`. O cluster da lição seguinte é criado do zero, como este.

## Como saber que deu certo

- [ ] Diante de um Pod que reinicia sozinho, distinguir pelos eventos se foi um *liveness probe* (`Killing … failed liveness probe`), um `OOMKilled` ou o programa que saiu com erro.
- [ ] Escrever os três *probes* do `revisor` e dizer, para cada um, o que pergunta, o que acontece se falha e quantos segundos leva para reagir com os números dele.
- [ ] Explicar, com a saída de 5.5 e a do Exercício 2, por que o *liveness probe* não deve depender de mais ninguém nem de uma rota que falha de propósito.
- [ ] Ler uma linha `Liveness:` do `describe` e nomear cada número.
- [ ] Escrever `requests` e `limits` em milicores e mebibytes sem confundir `m` com `M`, e dizer quem usa cada um.
- [ ] Diante de um `Pending`, ler o `FailedScheduling` nó por nó; diante de um `OOMKilled`, encontrar o `137` e o teto que o explica.
- [ ] Explicar o que o cluster faz entre o `kubectl delete pod` e o desaparecimento do Pod, e por que o `depurar` leva mais de 30 segundos e o `revisor` menos de um.
- [ ] Executar `programas/05-salud-recursos-apagado/correr.sh > /tmp/mi-corrida-l5.txt 2>&1` e comparar `/tmp/mi-corrida-l5.txt` com `programas/05-salud-recursos-apagado/correr.salida.txt` (não redirecionar para esse arquivo: é a referência) no que não muda entre execuções: três nós `Ready` em `v1.37.0`; seis linhas `not yet present on node … loading...`; `33` bytes de token e `-rw-------` nos dois `token.txt`; `QoS Class: BestEffort` e `30` antes da lição; `mismo token`; o `kubectl diff` com os *probes*, os recursos e os dois `terminationGracePeriodSeconds: 10`, e o código 1 dele; só os Deployments `configured`; as linhas `Limits`, `Requests`, `Liveness`, `Readiness` e `Startup` com os números delas, `QoS Class: Burstable` e `10`; no log, uma linha de `GET /salud` a cada 5 segundos e outra a cada 10; `RESTARTS 0` nos quatro Pods com o teste em `caido` e `FALLA … codigo 503`; os três nós com a mesma CPU e memória; `OOMKilled`, `OOMKilled 137` e `pidiendo 40 MB`; o `Pending`, `timed out waiting for the condition` e `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu`; `revisor: recibí terminated, apagando` e `revisor: apagado limpio`; as cinco linhas com valor reservado e teto, todas `Burstable`; `0/1` com `ready=false`, `connection refused` e código 7 no Exercício 1; `RESTARTS 1`, os eventos `Unhealthy … 503` e `Killing … will be restarted` e `modo: sano` no Exercício 2; `sin diferencias con los archivos`; `30`, `sleep 3600` como PID 1 e uma remoção de 30 s ou pouco mais no Exercício 3. Os IPs, os sufixos dos nomes, as idades, a hora do log, a CPU e a memória dos nós e os percentuais deles, a memória exata do `revisor` em `crictl stats`, em que nó cai cada Pod, a ordem das linhas do `kind load` e os segundos exatos do primeiro reinício no Exercício 2 mudam em cada execução: observam-se, não se comparam.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l5`.

## Resumo

Responda sem olhar a lição:

1. O que o cluster sabia do `revisor` antes desta lição, e por que o Pod dele estava `1/1` aos 4 segundos?
2. O que pergunta cada um dos três *probes* e o que o cluster faz quando a resposta é “não”?
3. Quem executa os *probes*, e que códigos HTTP contam como sucesso?
4. Com `periodSeconds: 10` e `failureThreshold: 3`, quanto demora a reagir um *liveness probe*?
5. Por que o `/salud` não consulta o serviço de teste, e por que o *probe* do serviço de teste pergunta a `/modo` e não a `/`?
6. Quem usa os `requests` e quem os `limits`? O que acontece com um contêiner que passa do teto de CPU, e o que acontece se passa do de memória?
7. O que é `100m` de CPU? E `100m` de memória?
8. Que três classes de QoS existem e em que ordem os Pods são expulsos quando um nó fica sem recursos?
9. O que significa o código 137?
10. O que acontece, em ordem, quando um Pod é apagado, e para que serve `terminationGracePeriodSeconds`?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Liveness, Readiness, and Startup Probes”](https://kubernetes.io/docs/concepts/workloads/pods/probes/): o que é um *probe* e que o executa o `kubelet`; o que cada um pergunta e o que acontece ao falhar; que o de inicialização detém os outros dois até ter sucesso; que o de *readiness* tira o IP do Pod dos EndpointSlices e roda durante todo o ciclo de vida; o aviso sobre as falhas em cascata; as dependências de *backend* no de *readiness* e não no de vida; o padrão de um `failureThreshold` maior no de vida; os campos de um *probe* e os valores padrão deles.
- [Kubernetes, “Configure Liveness, Readiness and Startup Probes”](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/): os códigos de 200 a 399 como sucesso de um *probe* HTTP; o *startup probe* com `failureThreshold * periodSeconds` para cobrir a pior inicialização, e o exemplo de 30 × 10 s.
- [Kubernetes, “Resource Management for Pods and Containers”](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/): o `request` para o escalonador e o `limit` para o `kubelet`; o teto de CPU por estrangulamento e o de memória por morte OOM; as unidades de CPU (`100m`, “cem milicpu”) e de memória (`Mi`, a armadilha do `m` minúsculo); que o escalonador soma os `requests` e se recusa mesmo que o uso real seja baixo; o evento `FailedScheduling` e o `OOMKilled` como casos de solução de problemas.
- [Kubernetes, “Pod Quality of Service Classes”](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/): os critérios de `Guaranteed`, `Burstable` e `BestEffort`, e a ordem de expulsão.
- [Kubernetes, “Pod Lifecycle”](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): o término de um Pod com TERM, o prazo de 30 segundos por padrão e o KILL ao vencer; os *endpoints* que se desligam, marcados `terminating` e com `ready` em `false`; a espera crescente entre reinícios (10 s, 20 s, 40 s… até 5 minutos) e `CrashLoopBackOff`.
- [Kubernetes, “Assign Memory Resources to Containers and Pods”](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/): um contêiner que passa do teto de memória e termina `OOMKilled`.
- [Kubernetes, “Deployments”](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxUnavailable` e `maxSurge` de 25 % por padrão, arredondados para baixo e para cima.
- [Kubernetes, “Limit Ranges”](https://kubernetes.io/docs/concepts/policy/limit-range/): que, por padrão, os contêineres rodam sem limite de recursos.
- [kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind create cluster` e `kind load docker-image` com `--name`, e `crictl` dentro de um nó.

---

**Próxima:** [Lição 6 — Entrar no cluster](06-entrar-al-cluster.md)
