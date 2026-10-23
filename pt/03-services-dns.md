# Lição 3 — Services e DNS

Terça-feira, 10h20 da manhã. Às 11h a área de operação revisa o painel e quer ver o relatório do `revisor` em verde. Ontem, para quebrar o galho, um colega copiou o IP de um Pod do serviço de teste, `10.244.1.3`, e o colou na lista de serviços que o `revisor` verifica. Funcionou a tarde toda. Hoje de manhã o relatório diz `FALLA` em todas as linhas, e ninguém mexeu em nada. Ou assim se acredita: à noite alguém reiniciou os Pods para aplicar uma mudança, os Pods renasceram e nenhum voltou com o IP de ontem. O endereço que o colega colou agora não é de ninguém, ou pior, é de outro Pod que não tem nada a ver. Faltam quarenta minutos e a pergunta não é que IP colar agora, mas como parar de colar IPs.

O Kubernetes já resolveu esse problema, e a solução tem duas peças: um **Service**, que é um nome e um endereço que não mudam ainda que os Pods por trás mudem o tempo todo, e o **DNS do cluster**, que converte esse nome nesse endereço para qualquer Pod que pergunte. Esta lição ensina a escrever o primeiro, a interrogar o segundo e a interpretar o que acontece quando um Service não encontra ninguém a quem mandar tráfego.

**Tempo:** 2 × 45 min

**O que se constrói:** o `revisor` encontrável por nome dentro do cluster, e o companheiro dele, o serviço de teste, também encontrável, de modo que o relatório finalmente verifica alguém de verdade

**O que se aprende:** o que é um Service do tipo `ClusterIP` e por que é o tipo padrão; como um seletor de rótulos decide para que Pods vai o tráfego e onde essa decisão fica escrita (`EndpointSlice`); a cadeia de três portas, `port`, `targetPort` e `containerPort`; como o DNS do cluster resolve nomes e por que `revisor` sozinho funciona; `kubectl port-forward` para `127.0.0.1`; e um Pod de depuração para olhar por dentro quando a imagem não tem *shell*

**De onde a gente vem.** Da [Lição 2](02-pods-deployments.md): o `revisor` roda com três réplicas em um Deployment, com o `securityContext` completo e um `emptyDir` em `/datos`. Já se sabe que cada Pod tem o seu IP e que esse IP muda cada vez que o Pod renasce, e viu-se que a imagem do `revisor` não traz *shell* nem `curl`. Da [Lição 0](00-que-es-kubernetes.md) vêm dois nomes que até agora eram só nomes: o `kube-proxy`, que existe um por nó, e o `coredns`, que roda no nó de controle. Nesta lição os dois se põem a trabalhar.

**O que esta lição não faz.** O `revisor` fica encontrável **dentro** do cluster e, para quem faz o curso, por um túnel temporário (`port-forward`). Não fica publicado para fora: um `LoadBalancer` e um ponto de entrada com Gateway API são a [Lição 6](06-entrar-al-cluster.md). Também ainda não se fecha quem pode falar com quem: hoje qualquer Pod do cluster chega ao `revisor`, e a [Lição 7](07-aislar-permisos-red.md) põe a rede em *default-deny*. E o Service manda tráfego a qualquer Pod que esteja rodando, saudável ou não: dizer ao cluster quando um Pod está pronto para receber tráfego é trabalho dos *probes* da [Lição 5](05-salud-recursos-apagado.md).

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com o `kind` v0.33.0, o `kubectl` v1.37.1 e a imagem de nó `kindest/node:v1.37.0` fixada pelo digest, no cluster de três nós da Lição 1, aqui chamado `curso-k8s-l3`. A máquina foi um Mac com processador ARM e Docker Engine 29.2.1 dentro de uma máquina virtual Linux (Colima), **não** Linux Mint, que é o sistema de referência do curso. O que muda no Mint: a arquitetura (`amd64` em vez de `arm64`), os endereços IP dos Pods e dos Services, os sufixos aleatórios dos nomes, as idades, em que nó cai cada réplica, a porta que o Docker dá ao nó de controle e quantas requisições cabem a cada réplica em 3.8. Os comandos são os mesmos. O percurso completo está em [`programas/03-services-dns/`](../programas/03-services-dns): o `correr.sh` cria o cluster, carrega as imagens nele, deixa o `revisor` como a Lição 2 o deixou, percorre a lição em ordem, executa os Exercícios 1 a 3 e apaga o cluster; levou 2 minutos e 16 segundos (a última linha da saída diz: `la corrida completa tardó 136 s`), dos quais criar o cluster e esperar que ficasse pronto foram 46 segundos. A saída é o `correr.salida.txt`. Ali, a seção do hábito de segurança aparece antes da do erro, porque o script a executa nessa ordem. O `port-forward` usa a porta `18080` da máquina local; se estiver ocupada, o script para antes de criar qualquer coisa e explica como escolher outra (`PUERTO_LOCAL=18081 ./correr.sh …`). Na máquina onde esta lição foi escrita corriam ao mesmo tempo os clusters de outras lições, e para não colidir com eles o script foi executado com `PUERTO_LOCAL=18300`; em `correr.salida.txt` e nesta lição o número foi reescrito para `18080`, o que será usado de fato. É a única coisa que foi alterada na saída.

## Ao terminar, a gente vai conseguir

- Explicar com um exemplo por que nenhum programa deve guardar o IP de um Pod, e o que um Service dá em troca.
- Escrever de memória um Service `ClusterIP` com o seu `selector` e a sua lista de `ports`, e seguir a cadeia `port` → `targetPort` → `containerPort` em um caso concreto.
- Encontrar o `EndpointSlice` de um Service com `-l kubernetes.io/service-name=…` e dizer, com ele em mãos, para que Pods vai o tráfego.
- Resolver o nome de um Service a partir de um Pod de depuração e explicar cada linha do `/etc/resolv.conf` dele, incluindo os `NXDOMAIN` que o `nslookup` imprime.
- Abrir um `port-forward` que escute somente em `127.0.0.1` e dizer quando ele se rompe.
- Provocar um Service sem endpoints, reconhecê-lo por `<unset>` e pelo código 7 do `curl`, e corrigi-lo.

## O porquê antes do como

Na Lição 2 ficaram três réplicas do `revisor` rodando, e a seção 2.4 terminou com um aviso: cada Pod tem o seu IP, e esse IP muda cada vez que o Pod renasce. É a cena de terça-feira. Um Pod é descartável por projeto. O ReplicaSet o repõe quando morre, e o substituto é **outro** Pod, com outro nome e outro endereço. Se os clientes guardam o endereço de um Pod, cada reposição os deixa falando com ninguém.

Há uma segunda razão, mais sutil. Mesmo que os Pods nunca morressem, são **três**. Com qual deles o cliente fala? Se escolher um, os outros dois sobram. Se se quer que reparta, seria preciso dar ao cliente a lista completa e mantê-la atualizada. Era isso que o Compose fazia no curso de Docker, de forma escondida: um nome de serviço que a rede do Compose resolvia para os contêineres dele. No Kubernetes, a mesma ideia tem nome próprio e manifesto próprio.

Um **Service** responde às duas perguntas ao mesmo tempo. Dá um IP virtual que não muda enquanto o Service existir e, atrás dele, a lista viva de Pods que o atendem. A lista não é escrita por quem faz o curso: é escrita por um controlador, a partir de uma regra que sim se escreve, o **seletor**. E para que ninguém precise saber esse IP virtual, o **DNS do cluster** lhe dá um nome: `revisor`, ou, com nome completo, `revisor.default.svc.cluster.local`.

A lição tem nove partes de conceitos e depois as seções de sempre:

1. **Um IP de Pod não serve como endereço** (3.1): o que muda quando um Pod renasce.
2. **O Service do `revisor`** (3.2), campo por campo.
3. **As três portas** (3.3): `port`, `targetPort` e `containerPort`.
4. **Seletores e `EndpointSlice`** (3.4): onde fica escrita a lista de Pods.
5. **Um Pod de depuração** (3.5), porque o `revisor` não tem *shell*.
6. **O DNS do cluster** (3.6).
7. **O serviço de teste** (3.7): o `revisor` finalmente verifica alguém.
8. **Como um Service reparte** (3.8).
9. **`port-forward`** (3.9): um túnel a partir da máquina local, somente para `127.0.0.1`.

Este é o destino. No final de 3.7, um Pod qualquer do cluster pede o relatório ao `revisor` pelo nome dele, e o `revisor` encontra o serviço de teste também pelo nome:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

## Se a imagem do curso de Docker não estiver à mão

Esta lição usa duas imagens do curso de Docker: a do `revisor`, `curso-docker-revisor:1.6.0`, entregue pela Lição 10 dele, e a do serviço que falha de propósito, `curso-docker-prueba:1.0.0`. Antes de seguir, convém conferir se as duas existem:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para a outra, o mesmo comando com `curso-docker-prueba:1.0.0`. Se faltar a do `revisor`, construí-la a partir do repositório daquele curso, com o `Dockerfile` da Lição 10 sobre a pasta `programas/revisor` e com `--build-arg VERSION=1.6.0`, dando-lhe exatamente a tag `curso-docker-revisor:1.6.0`. Se faltar a de teste, construí-la a partir da pasta `programas/servicio-prueba` desse mesmo repositório, com a tag `curso-docker-prueba:1.0.0`. A [Lição 2](02-pods-deployments.md) traz, nesta mesma seção, a lista do que o curso exige de uma imagem própria, caso se prefira usar outra.

O que esta lição exige **além disso** do serviço de teste, e convém ler porque cada ponto explica uma linha do manifesto dele:

- **Escuta HTTP na porta 9000** e responde `GET /` com `200` quando está saudável, com `503` quando está fora do ar e com demora quando está lento.
- **Muda de modo com `POST /modo/sano`, `POST /modo/lento` e `POST /modo/caido`**, e diz em que modo está com `GET /modo`. Assim dá para quebrá-lo por fora sem reconstruir nada.
- **Roda como o usuário 65532**, sem `root`, e aguenta o sistema de arquivos somente leitura **sem volume**: não escreve nada em disco.

E as duas são carregadas no cluster como na Lição 2, com `kind load docker-image` e o nome do cluster. Podem ser carregadas as duas em um só comando:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l3
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker2", loading...
```

Seis linhas: duas imagens por três nós. (Em outra execução a ordem das linhas pode ser outra.) O Pod de depuração de 3.5 usa uma terceira imagem, `curlimages/curl`, que **não** é carregada: é pública, vai fixada pelo digest `sha256` e o nó onde o Pod cair a baixa do Docker Hub na primeira vez. É preciso internet para esse passo.

## Os conceitos

### 3.1 Um IP de Pod não serve como endereço

Esta lição usa o seu próprio cluster, `curso-k8s-l3`, com a configuração de três nós da Lição 1, recém-criado. Cria-se assim, a partir da raiz do repositório do curso, com o mesmo cuidado aprendido na Lição 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l3.XXXX)/kubeconfig"
# curso-k8s-l3 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l3 --config programas/03-services-dns/kind-curso.yaml
# Debe decir kind-curso-k8s-l3. Si dice otra cosa, no sigas.
kubectl config current-context
```

O `export` só vale naquele terminal. Se for aberto outro (em 3.9 vai ser preciso um para o `port-forward`), repete-se o `export` com o mesmo caminho, ou o `kubectl` falará com outro cluster. Depois carregam-se as duas imagens, como se viu acima, e aplica-se o Deployment da Lição 2 tal qual, sem mudar uma vírgula; a partir daqui os comandos são executados dentro de `programas/03-services-dns/` (entra-se com `cd programas/03-services-dns`, ou `kubectl apply -f revisor-deployment.yaml` dirá que o caminho não existe). As saídas são da execução do `correr.sh`, que faz exatamente isso:

```text
$ kubectl config current-context
kind-curso-k8s-l3

$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-82d87   1/1     Running   0          1s    10.244.1.2   curso-k8s-l3-worker2   <none>           <none>
revisor-697fb84f97-drv5h   1/1     Running   0          1s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          1s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
```

O primeiro comando é o hábito de sempre: antes de mudar algo, perguntar a que cluster se está falando. Repete-se **antes de cada** `apply`, `delete`, `rollout restart` ou `port-forward` da lição, não só aqui; o script faz isso sozinho, antes de cada `kubectl`, e para se a resposta não for `kind-curso-k8s-l3`. Agora olhe a coluna `IP`. Os três endereços começam com `10.244.`: é a rede de Pods que o kind monta por padrão. O [guia de configuração](https://kind.sigs.k8s.io/docs/user/configuration/) dele diz assim: “por padrão, o kind usa a sub-rede de Pods `10.244.0.0/16` para IPv4”. Cada nó recebe um pedaço dessa rede: nesta execução, os Pods do `worker2` estão em `10.244.1.x` e os do `worker` em `10.244.2.x` (qual pedaço cabe a cada nó muda de uma execução para outra).

Agora a cena de terça-feira, em ponto pequeno. Apaga-se um:

```text
$ kubectl delete pod revisor-697fb84f97-82d87
pod "revisor-697fb84f97-82d87" deleted from default namespace

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-drv5h   1/1     Running   0          2s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          2s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-z79jh   1/1     Running   0          1s    10.244.1.3   curso-k8s-l3-worker2   <none>           <none>
```

O ReplicaSet o repôs em um segundo, como na Lição 2 (se os Pods forem listados logo depois de apagar, talvez apareça o antigo em `Terminating` e o novo em `ContainerCreating`; basta esperar alguns segundos ou executar `kubectl rollout status deployment/revisor`, e ficarão três). Mas o Pod novo, `z79jh`, não é o que morreu: outro nome e outro IP (`10.244.1.3` em vez de `10.244.1.2`). Repare que caiu no **mesmo** nó, `worker2`, e mesmo assim o endereço mudou: não é preciso que o Pod se mude para que o IP seja outro. Em outra execução pode cair também em outro nó. O endereço `10.244.1.2` já não é de ninguém. Se um programa o tinha guardado, a partir deste segundo ele fala com um endereço vazio. E se daqui a pouco outro Pod nascer no `worker2`, pode receber justamente esse endereço, e o programa estaria falando com um desconhecido sem perceber.

Não é um defeito do kind nem deste cluster: é o projeto. Os Pods são, nas palavras da [documentação de Pods](https://kubernetes.io/docs/concepts/workloads/pods/), entidades “relativamente efêmeras e descartáveis”. O que precisa ser estável não é o Pod, é o **acesso** ao conjunto de Pods. Isso é um Service.

### 3.2 O Service do `revisor`

A [documentação de Services](https://kubernetes.io/docs/concepts/services-networking/service/) o define em uma frase: um Service é “um método para expor uma aplicação de rede que roda como um ou mais Pods no seu cluster”. E precisa o que ele guarda: cada Service “define um conjunto lógico de *endpoints* (normalmente esses *endpoints* são Pods) junto com uma política sobre como tornar esses Pods acessíveis”.

Este é o do `revisor`. É um **programa**: aplica-se sozinho e vive em `programas/03-services-dns/revisor-service.yaml`.

```yaml
# revisor-service.yaml — Lección 3: un nombre estable para las réplicas del revisor.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

É muito mais curto que o Deployment, e se lê do mesmo jeito, de fora para dentro.

#### 3.2.1 O que é e como se chama

`apiVersion: v1` e `kind: Service`: os Services vivem no grupo central da API, o mesmo dos Pods, que não leva nome. `metadata.name: revisor` é o nome do Service, e não é um detalhe: **esse nome é o que se vai escrever nas URLs**. O DNS do cluster (3.6) o converte em endereço. Por isso o Service se chama igual ao Deployment, embora não precise: o Deployment se chama `revisor` para quem opera o cluster, e o Service se chama `revisor` para os clientes. O rótulo `app: revisor` do próprio Service é, como no Deployment, para que seja encontrado com `-l app=revisor`; não decide nada do tráfego.

#### 3.2.2 Que tipo de Service

`type: ClusterIP` diz que classe de endereço ele recebe. A documentação de Services descreve este tipo assim: “expõe o Service em um IP interno do cluster. Escolher este valor faz com que o Service seja alcançável somente de dentro do cluster. É o valor padrão usado se não se especificar um `type`”. O manifesto o escreve embora seja o valor padrão, pela mesma razão que a Lição 2 escreveu `IfNotPresent`: para que quem o leia não precise saber a regra, e para que a decisão de **não** publicar fique à vista. A mesma página diz como se publica algo para a internet: “com um Ingress ou um Gateway”. Isso é a Lição 6. Hoje, de propósito, nada sai.

#### 3.2.3 Para quem manda tráfego

`selector: {app: revisor}` é a regra: “os meus Pods são os que levam o rótulo `app: revisor`”. É o mesmo rótulo que o Deployment põe no template dele, e por isso o Service encontra as três réplicas. Repare no que ele **não** diz: não menciona o Deployment, nem o ReplicaSet, nem o `pod-template-hash`. O Service não sabe que existe um Deployment. Escolhe Pods por rótulo e nada mais. O Exercício 2 mostra a consequência, a que a Lição 2 deixou anunciada.

#### 3.2.4 Por onde

`ports` é uma lista; aqui traz uma única porta, chamada `http`. `port: 80` é a porta **do Service**: a que os clientes usam. `targetPort: http` é a porta **do Pod** para a qual o tráfego é reenviado, e não vai como número, mas por **nome**. A seção 3.3 segue essa cadeia com o cluster à frente.

#### 3.2.5 Aplicar e olhar

```text
$ kubectl apply -f revisor-service.yaml
service/revisor created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   41s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP    2s
```

Dois Services. O `revisor` recebeu o IP `10.96.144.175`. É de outra rede, `10.96.`, distinta da dos Pods: o guia do kind diz que, por padrão, usa “a sub-rede de Services `10.96.0.0/16` para IPv4”. O outro, `kubernetes`, não foi criado por ninguém do curso: é o Service do próprio `kube-apiserver`, no primeiro endereço dessa rede, para que os Pods que precisem falar com a API o encontrem por nome como qualquer outro. `EXTERNAL-IP <none>`: não há endereço para fora, como se pediu.

O `kubectl describe` reúne tudo do Service:

```text
$ kubectl describe service revisor
Name:                     revisor
Namespace:                default
Labels:                   app=revisor
Annotations:              <none>
Selector:                 app=revisor
Type:                     ClusterIP
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.96.144.175
IPs:                      10.96.144.175
Port:                     http  80/TCP
TargetPort:               http/TCP
Endpoints:                10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

As linhas que importam hoje:

- `Selector: app=revisor`: a regra que foi escrita.
- `IP: 10.96.144.175`: o endereço estável. A documentação o chama de *cluster IP* e explica que “é usado pelo mecanismo de endereços IP virtuais”. Não pertence a nenhuma máquina nem a nenhum Pod; 3.8 conta quem o faz funcionar.
- `Port: http 80/TCP` e `TargetPort: http/TCP`: as duas pontas da cadeia de portas.
- `Endpoints: 10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080`: **as três réplicas**, com o IP e a porta reais. Compare-as com a segunda tabela de 3.1: são exatamente as dos três Pods vivos, incluindo a `10.244.1.3` do Pod que acabou de nascer. A `10.244.1.2` do Pod apagado não aparece. Ninguém a removeu manualmente.
- `Session Affinity: None`: cada conexão pode ir para qualquer réplica; 3.8 mede isso.

Essa lista de `Endpoints` é a resposta à cena: o cliente usa `10.96.144.175`, que não muda, e o cluster mantém atualizado a quem ela corresponde de verdade.

### 3.3 As três portas

Na cena do Docker havia uma porta que importava: o `-p 8080:8080` do `docker run`. Aqui há três, e cada uma é declarada por um objeto diferente. Confundi-las é um dos erros mais comuns no começo, então vale a pena segui-las com o cluster à frente.

```text
$ kubectl get service revisor -o jsonpath='port={.spec.ports[0].port} targetPort={.spec.ports[0].targetPort}{"\n"}'
port=80 targetPort=http

$ kubectl get pods -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].ports[0].name}={.spec.containers[0].ports[0].containerPort}{"\n"}{end}'
revisor-697fb84f97-drv5h http=8080
revisor-697fb84f97-nq74v http=8080
revisor-697fb84f97-z79jh http=8080

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].ports}{"\n"}'
[{"name":"http","port":8080,"protocol":"TCP"}]
```

(O segundo `jsonpath` usa `{range .items[*]}…{end}`, que repete o que está no meio para cada Pod da lista. É a forma de pedir um valor de vários objetos de uma vez.)

Assim se lê a cadeia, do cliente ao programa:

| Porta | Onde é declarada | Valor no `revisor` | Quem a usa |
|---|---|---|---|
| `port` | o Service | `80` | o cliente: `http://revisor/…` vai para a 80, a porta padrão do HTTP |
| `targetPort` | o Service | `http` (um nome) | o cluster, para saber para que porta do Pod reenviar |
| `containerPort` | o template do Pod, com o nome dela | `http` = `8080` | quem busca o nome `http` no Pod; o programa escuta na 8080 por conta própria |

O terceiro comando mostra como o nome foi resolvido: o `EndpointSlice` (3.4) já traz o número, `8080`, que tirou dos Pods. A documentação de Services descreve as duas peças que tornam isso possível. A primeira: “um Service pode mapear qualquer `port` de entrada para um `targetPort`. Por padrão, e por comodidade, o `targetPort` vale o mesmo que o campo `port`”. A segunda: “as definições de portas dos Pods têm nomes, e é possível referir-se a esses nomes no atributo `targetPort` de um Service”.

Por que o curso usa o nome e não o número? Porque assim o número vive em **um único lugar**, o template do Pod. Se um dia o `revisor` escutar em outra porta, muda-se o `containerPort` no Deployment e o Service continua funcionando sem ser tocado. Com `targetPort: 8080`, seria preciso lembrar de mudar dois arquivos, e no dia em que um fosse esquecido, o Service mandaria tráfego para uma porta onde ninguém escuta. O Exercício 1 mostra exatamente como isso se vê.

Um esclarecimento que evita uma confusão frequente: a Lição 2 disse que o `containerPort` **não publica nada**. Continua sendo verdade. O programa escuta na 8080 mesmo que não seja declarada. Declará-la com nome serve para que o Service possa apontar para ela por esse nome, e para que quem leia o manifesto saiba onde ele escuta.

E a 80 do Service? Não é aberta pelo `revisor` nem por nenhum outro processo: faz parte do endereço virtual do Service. O programa continua escutando na 8080, com todas as restrições da Lição 2, e o cluster traduz. Assim os clientes escrevem `http://revisor/` sem número, e ninguém precisou mudar a porta do programa para conseguir isso.

### 3.4 Seletores e `EndpointSlice`

#### 3.4.1 Onde fica escrita a lista

A lista de `Endpoints` que o `describe` mostrou não está guardada no Service. Vive em outro objeto, um **EndpointSlice**. A [documentação de EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) resume: “os EndpointSlices acompanham os endereços IP dos *endpoints* de um *backend*. Normalmente estão associados a um Service, e os *endpoints* costumam ser Pods”.

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.2.3,10.244.1.3   3s
```

Repare em como foi buscado: não pelo nome (`revisor-6jh2f` leva um sufixo aleatório, como um Pod), mas pelo rótulo `kubernetes.io/service-name=revisor`. A mesma página explica por que esse rótulo existe: cada EndpointSlice leva uma referência ao seu dono e “um rótulo `kubernetes.io/service-name` que permite buscar facilmente todos os EndpointSlices que pertencem a um Service”. É a mesma ideia da Lição 2: busca-se por rótulo, nunca por um nome que muda.

Por que “todos”? Porque um Service pode ter vários. A documentação diz que, por padrão, o plano de controle cria EndpointSlices “de no máximo 100 *endpoints* cada um”. Com três réplicas tudo cabe em um; com trezentas haveria pelo menos três. Por isso a tabela acima é uma lista, embora hoje tenha uma única linha.

Com `jsonpath` vê-se cada *endpoint* por dentro, e o dono dele:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.2.3 revisor-697fb84f97-drv5h curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{"\n"}'
Service/revisor
```

Cada linha diz que endereço, de que Pod (`targetRef`), em que nó e se está pronto. E o dono do EndpointSlice é o Service, com o mesmo campo `ownerReferences` da Lição 2. É a mesma cadeia de donos: se o Service for apagado, o EndpointSlice dele vai junto.

#### 3.4.2 Quem a escreve

Ninguém a escreve manualmente. A documentação de depuração de Services conta assim: “dentro do Kubernetes há um ciclo de controle que avalia o seletor de cada Service e guarda o resultado em um ou mais objetos EndpointSlice” ([“Debug Services”](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)). É o termostato da Lição 0 outra vez, com outro estado desejado: “este Service manda tráfego aos Pods que coincidem com o seu seletor”. Quando o conjunto de Pods muda, o controlador corrige a lista.

Vê-se apagando outro Pod:

```text
$ kubectl delete pod revisor-697fb84f97-drv5h
pod "revisor-697fb84f97-drv5h" deleted from default namespace

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true
10.244.1.4 revisor-697fb84f97-mjbff curso-k8s-l3-worker2 ready=true
```

O Pod `drv5h` e o seu `10.244.2.3` saíram da lista, e entrou o Pod novo, `mjbff`, com `10.244.1.4`. Mesmo EndpointSlice, conteúdo novo. O Service não mudou em nada: o IP dele continua sendo `10.96.144.175`. Essa é toda a ideia.

#### 3.4.3 O que significa `ready=true`

A coluna `ready` é a que decide se um *endpoint* recebe tráfego. A documentação de EndpointSlices diz que a condição `serving` indica que o *endpoint* está atendendo e que, para um Pod, “corresponde à condição `Ready` do Pod”; e que `ready` é, em essência, “`serving` e não `terminating`”. Traduzindo: um Pod recebe tráfego enquanto estiver pronto e não estiver sendo desligado.

Hoje, “pronto” quer dizer pouco: o `revisor` não tem *probes*, então o Pod dele é marcado como pronto assim que o contêiner inicia, mesmo que o programa ainda não escute. Por isso é a Lição 5 que completa esta coluna: com um *readiness probe*, o Pod só é marcado como pronto quando o `/salud` responde, e o Service deixa de mandar tráfego a ele se deixar de responder.

#### 3.4.4 `Endpoints`, a API antiga

Vai-se encontrar em tutoriais o comando `kubectl get endpoints`. Ainda funciona, mas veja o que diz:

```text
$ kubectl get endpoints revisor
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS                                         AGE
revisor   10.244.1.3:8080,10.244.1.4:8080,10.244.2.2:8080   6s
```

`Endpoints` é a API anterior, e o próprio servidor avisa: “obsoleta desde a v1.33; use EndpointSlice”. A documentação de Services a marca igual (“Deprecated since Kubernetes v1.33”) e dá as razões: não serve para clusters com IPv4 e IPv6 ao mesmo tempo, não traz as informações que funcionalidades novas pedem, e “trunca a lista de *endpoints* se for longa demais para caber em um único objeto”. Este curso usa EndpointSlice. `Endpoints` está obsoleta, não removida: continua funcionando, como se acabou de ver, mas já não é a API recomendada. Ela é nomeada aqui para que seja reconhecida quando aparecer, que é a regra do curso para o obsoleto e o removido: nomeia-se para reconhecer, não se ensina.

### 3.5 Um Pod de depuração

#### 3.5.1 Por que é necessário

Para testar o Service é preciso um cliente **dentro** do cluster, porque um `ClusterIP` só é alcançável de lá. O candidato óbvio seria o próprio `revisor`, mas na Lição 2 viu-se que a imagem dele não tem *shell* nem `curl`: `kubectl exec deployment/revisor -- sh` falha com `executable file not found in $PATH`. Isso é uma defesa, e o curso não vai tirá-la para depurar. A saída é outra: um Pod à parte, feito para olhar, que se cria quando é necessário e se apaga ao terminar.

É um **programa**: `programas/03-services-dns/depurar.yaml`.

```yaml
# depurar.yaml — Lección 3: un Pod de depuración con curl, que se borra al terminar.
# Ya cumple el nivel «restricted» (Lección 7), para que sirva igual en el espacio
# de nombres revisor. La imagen va fijada por su huella.
apiVersion: v1
kind: Pod
metadata:
  name: depurar
  labels:
    app: depurar
    acceso-revisor: permitido
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
  - name: depurar
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

#### 3.5.2 Campo por campo

É um Pod avulso, de propósito: na Lição 2 aprendeu-se que um Pod sem dono não renasce, e aqui isso é exatamente o que se quer. Quando for apagado, fica apagado. O resto:

- **A imagem** é `curlimages/curl`, uma imagem pequena com `curl` e as ferramentas básicas do Alpine Linux (`sh`, `nslookup`, `cat`), que vêm do BusyBox. Vai fixada pelo digest `sha256`, não só pela tag `8.22.0`. Uma tag pode ser movida para outra imagem no registry; um digest, não. Como esta imagem é de fato baixada da internet, o digest identifica pelo conteúdo o manifesto da imagem, de modo que o cluster baixará as mesmas camadas que foram testadas aqui, ainda que alguém mova a tag `8.22.0` no registry.
- **`imagePullPolicy` não está escrito.** Diferentemente do `revisor`, este manifesto não o declara: com uma tag que não é `:latest`, o valor padrão é `IfNotPresent`, o mesmo que a Lição 2 escreveu à vista. Aqui se deixa o valor padrão.
- **`command: ["sleep", "3600"]`** substitui o programa da imagem, que seria um `curl` que termina logo, por uma espera de uma hora. Assim o Pod permanece vivo e dá para mandar comandos com `kubectl exec`. Com `restartPolicy: Never`, quando a hora passar o Pod termina e não é reiniciado.
- **O `securityContext`** é o mesmo padrão do `revisor`, com o usuário 100 e o grupo 101, os que a imagem do curl traz. Que um Pod seja “só para depurar” não é desculpa para rodar como `root`: um Pod de depuração esquecido é justamente o que alguém encontra depois.
- **`resources`** põe um piso e um teto de CPU e memória. São explicados na Lição 5; estão aqui porque um Pod de apoio não deve poder devorar o nó.
- **`automountServiceAccountToken: false`** evita que seja montada a credencial da API que a Lição 2 encontrou no `revisor`. O `curl` não precisa dela. A Lição 7 generaliza isso.
- **O rótulo `acceso-revisor: permitido`** ainda não faz nada. Na Lição 7, quando a rede for fechada, será a chave que deixa este Pod falar com o `revisor`. Vai desde hoje para que o mesmo arquivo sirva nas duas lições.

#### 3.5.3 Primeiro contato

```text
$ kubectl apply -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -o wide
NAME      READY   STATUS    RESTARTS   AGE   IP           NODE                  NOMINATED NODE   READINESS GATES
depurar   1/1     Running   0          29s   10.244.2.4   curso-k8s-l3-worker   <none>           <none>

$ kubectl exec depurar -- id
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)

$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec depurar -- curl -s http://10.96.144.175/salud
{"estado":"vivo","version":"1.6.0"}
```

O `id` confirma o usuário 100. E as duas últimas requisições são o coração da lição. A primeira usa o **nome** do Service, sem porta (a 80 é a do HTTP por padrão) e sem saber nada dos Pods. A segunda usa o IP do Service. As duas chegam a uma réplica do `revisor`, que responde o `/salud` dela com a versão `1.6.0`. Ninguém escreveu um IP de Pod em lugar nenhum. Que o nome `revisor` tenha sido convertido em `10.96.144.175` é trabalho do DNS do cluster, e é isso que vem a seguir.

### 3.6 O DNS do cluster

#### 3.6.1 Quem responde

Todo Pod sabe a quem perguntar por nomes porque o `kubelet` escreve um `/etc/resolv.conf` para ele ao criá-lo:

```text
$ kubectl exec depurar -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

Três linhas. A do meio diz a quem perguntar: `10.96.0.10`. Esse endereço está na rede de Services, e não é por acaso:

```text
$ kubectl get service -n kube-system kube-dns
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   74s

$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-cf8pv   1/1     Running   0          65s   10.244.0.2   curso-k8s-l3-control-plane   <none>           <none>
coredns-559f6c778d-h2hgl   1/1     Running   0          65s   10.244.0.4   curso-k8s-l3-control-plane   <none>           <none>
```

O DNS do cluster é, ele mesmo, **um Service com um seletor**: `kube-dns`, no namespace `kube-system`, porta 53 (a do DNS), que manda as perguntas aos dois Pods do `coredns` vistos na Lição 0. Exatamente o padrão que acabou de ser escrito para o `revisor`. Se amanhã um dos `coredns` cair, o Service dele continua em `10.96.0.10` e o outro responde. O Kubernetes usa as suas próprias peças para resolver o seu próprio problema.

(`-n kube-system` diz ao `kubectl` em que namespace procurar. Até agora tudo viveu em `default`. Os namespaces são estudados na Lição 7.)

#### 3.6.2 O nome completo de um Service

A [documentação de DNS para Services e Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) dá a forma do nome: um Service normal recebe um registro com um nome da forma `meu-servico.meu-namespace.svc.dominio-do-cluster`, que “resolve para o *cluster IP* do Service”. Para o do `revisor`:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

Lê-se da esquerda para a direita, do particular ao geral:

| Parte | O que é |
|---|---|
| `revisor` | o nome do Service |
| `default` | o namespace onde vive |
| `svc` | que é um Service (e não outra coisa) |
| `cluster.local` | o domínio do cluster, o padrão |

E a resposta, `10.96.144.175`, é o IP do Service, o de 3.2. O DNS não entrega os IPs dos Pods: entrega o endereço estável, e de repartir se encarrega o Service.

#### 3.6.3 Por que `revisor` sozinho funciona

Em 3.5 escreveu-se `http://revisor/salud`, não o nome completo, e funcionou. Quem torna isso possível é a primeira linha do `resolv.conf`, `search`. A documentação de DNS explica: as consultas “podem ser expandidas usando o `/etc/resolv.conf` do Pod” e “os valores da opção `search` são usados para expandir as consultas”. Quem expande não é o Pod, mas a biblioteca de DNS do programa que pergunta. Quando o `curl` pergunta por `revisor`, a biblioteca dele acrescenta, um por um, os domínios de `search`: `revisor.default.svc.cluster.local`, `revisor.svc.cluster.local` e `revisor.cluster.local`, e para no primeiro que responde. Aqui o primeiro já responde. Em 3.6.4 se verá que o `nslookup` desta imagem não para: pergunta todos ao mesmo tempo.

A terceira linha, `options ndots:5`, decide **quando** essa lista é usada. O guia de depuração de Services diz assim: a linha `options` “deve pôr `ndots` alto o bastante para que a biblioteca de DNS considere os caminhos de busca”, e o Kubernetes o põe em 5 por padrão, “alto o bastante para cobrir todos os nomes que ele gera”. Na prática: um nome com menos de cinco pontos é testado primeiro com a lista `search`. `revisor` não tem nenhum, então é expandido. Por isso também funciona a forma intermediária, com o namespace:

```text
$ kubectl exec depurar -- curl -s http://revisor.default/salud
{"estado":"vivo","version":"1.6.0"}
```

`revisor.default` mais `svc.cluster.local`, o segundo elemento de `search`, dá o nome completo. A documentação põe isso como regra: as consultas que não dizem o namespace “ficam limitadas ao namespace do Pod”; para chegar a um Service de outro namespace, escreve-se o namespace no nome. Hoje tudo vive em `default` e não se nota. A partir da Lição 7, quando o `revisor` se mudar para o seu próprio namespace, `revisor.revisor` será a forma de alcançá-lo de fora dele.

#### 3.6.4 Os `NXDOMAIN` que não são um erro

Agora pergunte ao `nslookup` pelo nome curto:

```text
$ kubectl exec depurar -- nslookup revisor
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find revisor.cluster.local: NXDOMAIN

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175

** server can't find revisor.svc.cluster.local: NXDOMAIN


** server can't find revisor.cluster.local: NXDOMAIN

** server can't find revisor.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

Parece um desastre: quatro “não encontro” e um código de saída 1. Leia devagar. No meio deles está a resposta correta: `revisor.default.svc.cluster.local` é `10.96.144.175`. Os quatro `NXDOMAIN` (*non-existent domain*, “esse nome não existe”) são as **outras** expansões da lista `search`: `revisor.svc.cluster.local` e `revisor.cluster.local` não existem, e é verdade, não existem. Saem duas vezes cada uma porque o `nslookup` desta imagem, o do BusyBox, pergunta por cada nome duas coisas: o endereço IPv4 (registro `A`) e o endereço IPv6 (registro `AAAA`). Ao nome completo, que existe, também perguntou as duas; como o Service não tem endereço IPv6, essa segunda pergunta volta sem registros, e isso não é impresso como erro (um nome que existe mas não tem esse tipo de registro é diferente de um que não existe). Ele imprime cada falha e, se houve alguma, termina com código 1 mesmo que tenha encontrado a resposta. A ordem das linhas muda de uma execução para outra, porque as perguntas saem ao mesmo tempo: em outra execução desta mesma lição, a resposta saiu no final, depois dos quatro `NXDOMAIN`.

O `curl` não reclama de nada disso porque só lhe importa encontrar **um** endereço, e ele o encontrou. A lição prática: com o `nslookup`, perguntar pelo nome completo; nesta imagem sai limpo, como se viu em 3.6.2. Atenção ao porquê: não é que a regra garanta isso. Com `ndots:5`, até `revisor.default.svc.cluster.local` (quatro pontos) conta como “curto” para uma biblioteca que respeite a regra ao pé da letra, e é justamente o custo conhecido do `ndots:5`: consultas a mais mesmo com o nome completo. Que saia limpo é o comportamento medido deste `nslookup`. Para que um nome seja absoluto e nunca seja expandido, termina-se em ponto: `revisor.default.svc.cluster.local.` E se aparecer `NXDOMAIN` com o nome curto, procurar a linha `Name:` antes de se alarmar.

Para comparar, assim se vê um nome que de fato não existe:

```text
$ kubectl exec depurar -- nslookup no-existe.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

Sem linha `Name:` e sem `Address:` no final. Essa ausência é a diferença, não os `NXDOMAIN`.

### 3.7 O serviço de teste: o `revisor` finalmente verifica alguém

Desde a Lição 2, o `revisor` tem escrito no manifesto `REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s`. Essa linha já era uma promessa sobre esta lição: pede que ele verifique um serviço chamado `prueba` em `http://prueba:9000/`, com 2 segundos de limite. Essa URL usa um **nome**, não um IP. Veja o que acontece hoje, antes que esse nome exista:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        4ms  no responde: Get "http://prueba:9000/": dial tcp: lookup prueba on 10.96.0.10:53: no such host
```

O `revisor` faz bem o trabalho dele: diz que `prueba` falha, e por quê. `lookup prueba on 10.96.0.10:53: no such host`: perguntou ao DNS do cluster (o `10.96.0.10` de 3.6) por `prueba` e o DNS respondeu que não existe. Não há Pod, não há Service, não há nome.

Estes são os dois manifestos do serviço de teste. Os dois são **programas**: `prueba-deployment.yaml` e `prueba-service.yaml`.

```yaml
# prueba-deployment.yaml — Lección 3: el servicio que falla a propósito.
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
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

```yaml
# prueba-service.yaml — Lección 3: el nombre «prueba» que el revisor consulta.
apiVersion: v1
kind: Service
metadata:
  name: prueba
  labels:
    app: prueba
spec:
  type: ClusterIP
  selector:
    app: prueba
  ports:
  - name: http
    port: 9000
    targetPort: http
```

O Deployment é o padrão da Lição 2, com o mesmo `securityContext` e **uma** réplica: é um serviço de teste, não é preciso mais. Não leva volume, porque não escreve nada em disco. O Service tem uma diferença em relação ao do `revisor` que vale a pena notar: aqui `port` é `9000`, igual ao do contêiner, porque assim pede a URL que o `revisor` já tem escrita (`http://prueba:9000/`). O `targetPort` continua sendo por nome. A regra não é “o Service sempre na 80”: a porta do Service é a que os clientes esperam.

```text
$ kubectl apply -f prueba-deployment.yaml -f prueba-service.yaml
deployment.apps/prueba created
service/prueba created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP    79s
prueba       ClusterIP   10.96.236.7     <none>        9000/TCP   3s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP     40s

$ kubectl exec depurar -- curl -s http://prueba:9000/modo
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

`OK`, em 1 milissegundo, com código `200`. O `revisor` não foi reiniciado, a configuração dele não foi alterada, nenhum IP lhe foi dado. O manifesto dele dizia `prueba` desde o princípio; a única coisa que mudou é que agora esse nome existe. Toda vez que o `revisor` monta o relatório, pergunta de novo pelo nome. Isso é o que a cena de terça-feira precisava: a configuração diz **a quem**, não **onde está**.

Agora o serviço é quebrado de propósito, nos três modos:

```text
$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  codigo 503

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/lento
modo: lento

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

Cada modo conta algo diferente. Em `caido`, `prueba` responde, mas com `503`: o `revisor` diz `FALLA codigo 503`. Em `lento`, `prueba` demora mais que os 2 segundos que a lista lhe dá, e o `revisor` desiste aos `2.002s` com `se acabo el tiempo de espera`. (O estado `LENTO` do `revisor` é para um serviço que responde bem mas demora mais de 1 segundo **sem** passar do limite; aqui passou.) E em `sano`, tudo volta a `OK`. Os três casos passaram pelo Service e pelo DNS do cluster, e o `revisor` os distinguiu.

Com isso, o `revisor` faz dentro do cluster o mesmo que fazia no Compose no curso de Docker. A tabela de tradução da Lição 0 antecipava: o nome do serviço na rede do Compose vira o DNS do cluster.

### 3.8 Como um Service reparte

#### 3.8.1 Medir

O Service tem três réplicas por trás. Ele usa as três? Mede-se com trinta requisições e o log do `revisor`, que escreve uma linha por cada requisição que atende:

```text
$ kubectl exec depurar -- sh -c 'for i in $(seq 1 30); do curl -s -o /dev/null http://revisor/salud; done; echo 30 peticiones'
30 peticiones

$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /salud' | cut -d' ' -f1 | sort | uniq -c
   6 [pod/revisor-697fb84f97-mjbff/revisor]
  13 [pod/revisor-697fb84f97-nq74v/revisor]
  14 [pod/revisor-697fb84f97-z79jh/revisor]
```

O segundo comando junta várias ferramentas, e vale a pena desmontá-lo:

- `kubectl logs -l app=revisor` pede o log de **todos** os Pods com esse rótulo, não de um;
- `--prefix` antepõe a cada linha o Pod de onde saiu;
- `--tail=-1` pede o log completo (com seletor de rótulo, o `kubectl logs` mostra por padrão só as últimas linhas de cada Pod);
- `grep` fica com as linhas de `/salud`, `cut` com o prefixo, e `sort | uniq -c` conta quantas há de cada Pod.

As três réplicas receberam tráfego. Somam 33 e não 30 porque as três requisições a `/salud` de 3.5 e 3.6 também estão no log. E a distribuição não é uniforme: 14, 13 e 6. Não tem por que ser.

#### 3.8.2 Quem faz o trabalho

O IP de um Service não pertence a nenhuma máquina. A [referência de IPs virtuais](https://kubernetes.io/docs/reference/networking/virtual-ips/) diz quem o faz funcionar: “o componente `kube-proxy` é responsável por implementar um mecanismo de IP virtual para os Services”. O `kube-proxy` roda em cada nó (os três vistos na Lição 1), lê os EndpointSlices e escreve regras na rede do nó. Quando um pacote sai em direção a `10.96.144.175:80`, essas regras o desviam para o IP e a porta de um Pod real, por exemplo `10.244.1.4:8080`.

Como ele escolhe o Pod? A mesma referência diz que o modo padrão no Linux, para o Kubernetes 1.37, é `iptables`, e que nesse modo as regras, “por padrão, escolhem um Pod de *backend* ao acaso”. Ao acaso, não em rodízio. Em trinta sorteios, uma distribuição de 14, 13 e 6 é perfeitamente possível. Com muitas mais requisições, cada réplica se aproximaria de um terço. E o `Session Affinity: None` do `describe` é o que permite esse acaso: a referência explica que, se se quer que um mesmo cliente vá sempre para o mesmo Pod, pode-se pôr `sessionAffinity: ClientIP`, e que o valor padrão é `None`. O `revisor` não guarda nada entre requisições, então não precisa disso.

Isso tem uma consequência que convém saber desde já: o Service reparte **conexões**, não requisições. Cada `curl` do laço abre uma conexão nova, e por isso cada um cai onde calha. Um cliente que reutiliza uma única conexão para muitas requisições fala sempre com o mesmo Pod enquanto essa conexão viver.

### 3.9 `port-forward`: um túnel a partir da máquina local

Tudo o que foi visto passou **dentro** do cluster. E a partir do terminal local? O IP `10.96.144.175` não serve fora do cluster (a seção do hábito de segurança confere isso). Para testar a partir da máquina local sem publicar nada existe o `kubectl port-forward`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &
Forwarding from 127.0.0.1:18080 -> 8080

$ curl -s http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s 'http://127.0.0.1:18080/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK            0s  200
```

Lê-se assim: escuta na porta `18080` da máquina local, somente no endereço `127.0.0.1`, e reenvia o que chegar à porta `80` do Service `revisor`. O `&` final o deixa rodando em segundo plano, para que o mesmo terminal possa ser usado. Enquanto estiver rodando, cada vez que se fizer uma requisição o `kubectl` imprimirá `Handling connection for 18080` nesse terminal: é normal. Interrompe-se com `kill %1` ou trazendo-o para o primeiro plano com `fg` e `Ctrl+C`. Se se preferir deixá-lo em um terminal à parte, lembrar de 3.1: nesse terminal novo, primeiro o mesmo `export KUBECONFIG=…` e `kubectl config current-context`, que deve dizer `kind-curso-k8s-l3`.

Leia bem a primeira linha: `Forwarding from 127.0.0.1:18080 -> 8080`. Não diz `-> 80`. O `kubectl` traduziu a 80 do Service para o `targetPort` dele e este para a 8080 do Pod, e abriu o túnel **direto para um Pod**. A [referência do `kubectl port-forward`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/) diz isso desde a primeira frase: “reenvia uma ou mais portas locais para um Pod”. E acrescenta: quando se dá um recurso como um Deployment ou um Service, o `kubectl` escolhe um Pod; “se houver vários Pods que coincidem, um é escolhido automaticamente. A sessão de reenvio termina quando o Pod escolhido termina, e é preciso executar o comando de novo”. Ou seja: `port-forward service/revisor` **não** reparte como o Service. Usa o Service só para encontrar um Pod. O Exercício 3 mostra o que acontece quando esse Pod some.

E o `--address 127.0.0.1`? A referência diz que o valor padrão de `--address` é `localhost`, com o qual o `kubectl` tenta escutar em `127.0.0.1` e em `::1` (o endereço da própria máquina em IPv6). O curso escreve `127.0.0.1`: um único endereço, à vista, pela mesma razão por que escreve `type: ClusterIP`. A decisão de não abrir o túnel para a rede fica escrita, e ninguém precisa saber o valor padrão. A mesma referência traz, entre os exemplos, `--address 0.0.0.0`, que escuta “em todos os endereços”. Isso transformaria o notebook em uma porta para esse Pod para qualquer um na rede, sem senha e com as credenciais do cluster por trás. Confere-se o que abriu o túnel:

```text
$ lsof -nP -iTCP:18080 -sTCP:LISTEN | awk '{print $1, $8, $9, $10}'
COMMAND NODE NAME 
kubectl TCP 127.0.0.1:18080 (LISTEN)
```

Um único processo, `kubectl`, escutando em `127.0.0.1:18080` e em nenhum outro lugar. (`lsof` lista quem tem uma porta aberta; `awk` fica com quatro colunas para que caiba. No Linux Mint funciona igual; também dá para usar `ss -ltnp | grep 18080`.)

Um `port-forward` é para testar, não para servir. Vive enquanto viver o comando e a sessão, depende das credenciais do cluster e se rompe quando o Pod que escolheu some. Publicar o `revisor` de verdade, por um ponto de entrada com nome, é a Lição 6.

## O erro que se vai ver

O erro desta lição é dos mais comuns com Services, e o próprio guia de depuração o menciona como tal: um Service cujo seletor não seleciona ninguém. É provocado com `fig03_01.selector-malo.yaml`, um **programa** que falha de propósito: o mesmo Service do `revisor`, com uma letra a menos.

```yaml
# fig03_01.selector-malo.yaml — FALLA A PROPÓSITO: el mismo Service del revisor
# con una letra de menos en el selector (revisr). Se aplica encima del bueno, el
# Service se queda sin a quién mandar tráfico y curl sale con código 7. Se
# corrige volviendo a aplicar revisor-service.yaml.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisr
  ports:
  - name: http
    port: 80
    targetPort: http
```

Antes de aplicá-lo, `kubectl config current-context` deve dizer `kind-curso-k8s-l3`.

```text
$ kubectl apply -f fig03_01.selector-malo.yaml
service/revisor configured
```

`configured`: o `kube-apiserver` aceitou a mudança sem reclamar, e tem razão. Um seletor `app: revisr` é perfeitamente válido; simplesmente não coincide com nada. O Kubernetes não pode saber que se queria escrever `revisor`.

**Dar um momento ao cluster.** Antes de testar, ver se o EndpointSlice já está vazio: `kubectl get endpointslices -l kubernetes.io/service-name=revisor` deve dizer `<unset>` na coluna `ENDPOINTS`. Se se testar no mesmo segundo do `apply`, o `kube-proxy` ainda não percebeu a mudança, o `curl` responde como se nada e vai-se achar que o erro “não saiu”. O script faz justamente isso: espera a lista esvaziar e só então testa. Depois, lê-se em ordem, como na Lição 2.

**Primeiro, o sintoma.** A partir do Pod de depuração, pedindo ao `curl` que diga quanto demorou:

```text
$ kubectl exec depurar -- curl -s -m 3 -o /dev/null -w 'tardó %{time_total} s\n' http://revisor/salud
tardó 0.001120 s
command terminated with exit code 7
[código de salida: 7]
```

(`-o /dev/null` descarta a resposta, que aqui não existe, e `-w` pede ao `curl` que escreva no final o tempo total da requisição.) `-m 3` põe um limite de 3 segundos, para que não espere sem fim; não foi necessário: levou um milésimo de segundo. O código 7 é, segundo a [lista de erros do curl](https://curl.se/libcurl/c/libcurl-errors.html), “não foi possível conectar ao *host*” (*Failed to connect() to host or proxy*). Não é o 6, “não foi possível resolver o *host*”: o nome sim foi resolvido. E não é o 28, “tempo esgotado”: a conexão não ficou esperando, alguém a recusou de imediato. Essa distinção já diz onde olhar.

**Segundo, o DNS.** Se o nome foi resolvido, o DNS não é o problema. Confere-se:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

O nome continua existindo e continua dando o mesmo IP. O Service está ali. O que não há é ninguém por trás.

**Terceiro, os *endpoints*.** Este é o passo decisivo:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS     ENDPOINTS   AGE
revisor-6jh2f   IPv4          <unset>   <unset>     51s

$ kubectl describe service revisor | grep -E '^(Selector|Endpoints):'
Selector:                 app=revisr
Endpoints:                
```

`ENDPOINTS <unset>`: o EndpointSlice continua existindo, mas vazio, sem endereços e sem portas. O `describe` confirma com um `Endpoints:` em branco e, uma linha acima, mostra a causa: `Selector: app=revisr`. O guia de depuração de Services diz quase com estas palavras: se a lista de *endpoints* está vazia, “verifique se o campo `spec.selector` do Service realmente seleciona os valores de `metadata.labels` dos Pods. Um erro comum é haver um erro de digitação”.

**Quarto, o seletor contra os rótulos.** Confere-se com o mesmo seletor, que é justamente a ferramenta da Lição 2:

```text
$ kubectl get pods -l app=revisr
No resources found in default namespace.

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-mjbff   1/1     Running   0          48s
revisor-697fb84f97-nq74v   1/1     Running   0          53s
revisor-697fb84f97-z79jh   1/1     Running   0          52s
```

Zero Pods com `app=revisr`, três com `app=revisor`, os três `Running`. Os Pods estão perfeitos. O Service procura outros.

**Por que o código 7 e não um tempo esgotado.** Com a lista vazia, o `kube-proxy` não tem para onde mandar a conexão. O que foi medido é o código, 7, e o tempo, um milésimo de segundo: a conexão não esperou até o limite de 3 segundos, foi recusada assim que saiu. (No modo `iptables`, o `kube-proxy` põe uma regra de rejeição para os Services sem *endpoints*. É o comportamento observado nesta execução, não algo que a documentação prometa.) É o mesmo sinal do Exercício 1, por uma causa diferente: ali o Service sim tem a quem mandar tráfego, mas para a porta errada. O que separa um caso do outro é a coluna `ENDPOINTS`.

**A correção** é a causa, não o Pod: aplicar de novo o arquivo bom.

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   53s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

Os três endereços voltaram ao mesmo EndpointSlice (`revisor-6jh2f`, cuja idade continuou contando: não foi apagado nem foi criado outro), e o `revisor` responde. Repare na ordem da correção: o script esperou ver os três endereços no EndpointSlice antes de testar com o `curl`. É o mesmo aviso do começo, ao contrário: entre aplicar o Service corrigido e cada `kube-proxy` atualizar as suas regras passa um momento, e um teste feito justo nesse instante ainda pode falhar mesmo que o conserto já esteja feito. Primeiro se confere que a lista esteja cheia; depois se testa.

**A ordem, para qualquer Service que não responde:**

1. Que código o `curl` dá? O 6 é o nome, o 7 é recusa e o 28 é silêncio.
2. O nome completo resolve?
3. O EndpointSlice dele tem endereços?
4. Se não tem, o `Selector` dele coincide com os rótulos dos Pods (`get pods -l …`)?
5. Se tem, a porta da coluna `PORTS` é onde o programa escuta?

## O hábito de segurança da lição: nada se publica à toa

A tabela de hábitos do curso atribui a esta lição três coisas: por padrão `ClusterIP`; nada se publica à toa; `port-forward` somente para `127.0.0.1`. As três são conferidas com o cluster à frente.

**Um `ClusterIP` não se vê a partir da máquina local.** A partir do terminal local, fora do cluster, o mesmo IP que o Pod de depuração usou sem problema:

```text
$ curl -s -m 3 http://10.96.144.175/salud
[código de salida: 28]
```

Código 28: “tempo esgotado”. A máquina local não tem uma rota própria para `10.96.0.0/16`: o pacote sai pela rota padrão, em direção ao modem ou à rede do escritório, que não sabem nada do cluster, e ninguém responde. (Se a rede usar endereços `10.96.x.x`, poderia haver outra resposta, de uma máquina que não tem nada a ver com o cluster; com mais razão ainda, esse IP não é da máquina local fora dele.) O `10.96.144.175` só faz sentido nas regras que o `kube-proxy` escreve **dentro** dos nós.

**Os nós não publicam nada do `revisor`.** Cada nó do kind é um contêiner do Docker, e o Docker diz que portas cada um publica:

```text
$ docker port curso-k8s-l3-control-plane
6443/tcp -> 127.0.0.1:59190

$ docker port curso-k8s-l3-worker

$ docker port curso-k8s-l3-worker2
```

O nó de controle publica uma única porta, a `6443` do `kube-apiserver`, e somente para `127.0.0.1` (o número do lado local é escolhido pelo kind ao acaso; em outra máquina será outro). É a porta por onde fala o `kubectl`, e a Lição 1 a viu. Os dois nós de trabalho, onde roda o `revisor`, não publicam **nada**: as linhas deles saem vazias. Não há nenhum caminho da rede local até a porta 8080 do `revisor`. Assim deve ser até a Lição 6, que abre um ponto de entrada com nome e diz o que cruza por ele.

**O túnel só escuta na máquina local.** Já se viu em 3.9: o `kubectl` escutando em `127.0.0.1:18080` e em nenhum outro lugar.

Por que importa: cada caminho aberto para um serviço é um caminho que alguém pode usar. Em um cluster real, o reflexo de “mudo para `NodePort` para testar” ou “ponho `--address 0.0.0.0` para o colega ver” deixa aberto o que ninguém lembra de fechar. A regra do curso é a inversa: tudo nasce fechado, cada abertura é uma decisão escrita em um manifesto e tem a sua lição.

**O que ele protege e o que não.** Um `ClusterIP` impede que o `revisor` seja alcançado de **fora** do cluster. Não impede nada **dentro**: qualquer Pod de qualquer namespace pode falar com ele, como fez o `depurar`, que não tem nada a ver com o `revisor`. Tampouco cifra o tráfego entre Pods: vai em HTTP puro pela rede de Pods. Fechar quem fala com quem é trabalho das `NetworkPolicy` da Lição 7. A cifragem é discutida na Lição 6.

## Erros comuns

**Guardar o IP de um Pod na configuração.** É a cena de terça-feira. Funciona até o Pod renascer. Sempre o nome do Service.

**Guardar o IP do Service em vez do nome.** É estável enquanto o Service existir, mas, se for apagado e recriado, recebe outro. O nome sobrevive a isso; o IP não.

**Escrever `targetPort` como número quando o contêiner tem nome.** Funciona hoje e obriga a manter o mesmo número em dois arquivos. No dia em que um mudar, o Service manda tráfego para uma porta onde ninguém escuta (Exercício 1).

**Mudar para `NodePort` ou `LoadBalancer` “para testar”.** Para testar existe o `port-forward`, que não abre nada para a rede. Publicar é uma decisão da Lição 6, não um atalho.

**Abrir o `port-forward` com `--address 0.0.0.0`.** Expõe a porta desse Pod a qualquer um que alcance a máquina, sem senha, usando as credenciais do cluster, enquanto o comando viver.

**Usar o `port-forward` como se fosse um Service.** Fala com **um** Pod, não reparte e cai quando esse Pod some (Exercício 3). Serve para olhar, não para servir.

**Abrir outro terminal e esquecer o `export KUBECONFIG`.** No terminal novo, o `kubectl` fala com o cluster que o `~/.kube/config` indicar, que pode ser qualquer outro. Primeiro o `export`, depois `kubectl config current-context`, e só então o comando.

**Alarmar-se com os `NXDOMAIN` do `nslookup`.** Com o nome curto, são as expansões de `search` que não existem. Procurar a linha `Name:`, ou perguntar pelo nome completo.

**Dar a um Pod avulso os rótulos do seletor de um Service.** O Deployment não o adota, mas o Service sim o usa, e manda tráfego a ele (Exercício 2).

**Testar logo depois de mudar o Service e tirar conclusões.** Tanto ao quebrá-lo quanto ao corrigi-lo: primeiro a coluna `ENDPOINTS`; depois, `curl`.

**Tirar o `securityContext` do Pod de depuração “porque é temporário”.** O temporário é esquecido, e um Pod `root` esquecido é uma porta aberta. O deste curso já cumpre o nível `restricted`.

## Exercícios

Os três primeiros são executados no cluster da lição, em ordem e a partir do estado em que ficou depois de corrigir o erro. Antes de cada exercício, `kubectl config current-context` deve dizer `kind-curso-k8s-l3`; se disser outra coisa, não prossiga. O `correr.sh` os executa do mesmo modo, e a saída está em `correr.salida.txt`. **Antes** de executar cada um, escrever no [diário de bordo](bitacora.md) o que se acredita que vai acontecer. O quarto é escrito com palavras próprias.

### Exercício 1 — Um `targetPort` onde ninguém escuta

O `fig03_02.puerto-malo.yaml` é o mesmo Service do `revisor` com o seletor certo e uma única diferença: `targetPort: 8081`, um número, em vez de `http`.

```yaml
# fig03_02.puerto-malo.yaml — Ejercicio 1: el selector está bien, pero el
# targetPort apunta a un número donde el revisor no escucha (8081 en lugar del
# 8080 que se llama «http»). Pregunta: ¿el Service tiene endpoints? ¿Responde?
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: 8081
```

Antes de aplicá-lo, prever: quantos endereços terá o EndpointSlice? O que dirá a coluna `PORTS` dele? Que código dará `curl -s -m 3 http://revisor/salud` a partir do `depurar`? Depois aplicá-lo, esperar alguns segundos até que a coluna `PORTS` mude (o script espera cinco), conferir, e explicar em que esta falha se parece e em que se distingue da de “O erro que se vai ver”. Ao terminar, aplicar de novo o `revisor-service.yaml`.

### Exercício 2 — O Pod que se infiltra no Service

O `fig03_03.colado.yaml` é o `revisor-extra` do Exercício 2 da Lição 2: um Pod avulso, idêntico às réplicas, **com** o rótulo `app: revisor` e com a porta dele chamada `http`. Na Lição 2 viu-se que o Deployment não o adota. Agora há um Service que escolhe por `app: revisor`.

Prever: quantas réplicas diz o Deployment? Quantos endereços tem o EndpointSlice do `revisor`? Se forem mandadas 40 requisições a `http://revisor/salud`, quantas caberão ao `revisor-extra`, mais ou menos? Aplicá-lo, conferir com `kubectl get deployment revisor`, com o `jsonpath` de 3.4 (endereço e `targetRef.name`) e com `kubectl logs revisor-extra | grep -c 'GET /salud'` depois do laço de 3.8 com 40 requisições. Depois explicar o que aconteceria com esse Pod no dia em que a imagem do Deployment mudasse. Ao terminar, conferir o contexto e apagá-lo: `kubectl delete pod revisor-extra`.

### Exercício 3 — O túnel e o *rollout*

Abrir outra vez o `port-forward` de 3.9 e conferir que `curl -s -m 3 http://127.0.0.1:18080/salud` responde. Prever: se agora se executar `kubectl rollout restart deployment/revisor` e se esperar que termine, o mesmo `curl` continua respondendo? Fazer isso, e ler o que o `port-forward` escreveu no terminal dele. Explicar o que aconteceu com a frase da referência do `kubectl port-forward` citada em 3.9.

### Exercício 4 — Os quatro `NXDOMAIN`

Uma colega executa `kubectl exec depurar -- nslookup revisor`, vê quatro linhas `server can't find … NXDOMAIN` e o código de saída 1, e conclui que “o DNS do cluster está quebrado”. Em no máximo cinco frases, responder-lhe: de onde saem esses nomes, por que cada um aparece duas vezes, por que o código é 1, como se reconhece na mesma saída que o nome sim foi resolvido, e que comando se lhe daria para conferir sem ruído.

## Soluções

### Solução 1

Medido em `correr.salida.txt`:

```text
$ kubectl apply -f fig03_02.puerto-malo.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8081    10.244.2.2,10.244.1.4,10.244.1.3   59s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 7
[código de salida: 7]
```

**Três endereços, porta `8081`, e `curl` com código 7.** O seletor está certo, então o EndpointSlice tem as três réplicas. Mas a coluna `PORTS` dele diz `8081`: com um número, o cluster não procura nada no Pod, toma o número tal qual. A conexão chega ao IP correto de um Pod real, a uma porta onde o `revisor` não escuta, e o Pod a recusa: código 7, “não foi possível conectar”.

Parece-se com o erro da lição no sintoma: o mesmo código 7. Distingue-se na coluna `ENDPOINTS`: lá estava em `<unset>` (não há a quem), aqui está cheia (há a quem, pela porta errada). Por isso a ordem de diagnóstico olha primeiro os endereços e depois a porta. O guia de depuração de Services pergunta exatamente isto: “o `targetPort` está correto para os Pods?”. E é o argumento a favor de `targetPort: http`: com o nome, este erro não pode ser escrito sem mudar também o Deployment.

Ao aplicar de novo o bom:

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   64s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

`PORTS 8080`: o nome `http` foi resolvido outra vez para a porta dos Pods.

### Solução 2

Medido em `correr.salida.txt`:

```text
$ kubectl apply -f fig03_03.colado.yaml
pod/revisor-extra created

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           69s

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v
10.244.1.4 revisor-697fb84f97-mjbff
10.244.1.3 revisor-697fb84f97-z79jh
10.244.2.6 revisor-extra

$ kubectl exec depurar -- sh -c 'for i in $(seq 1 40); do curl -s -o /dev/null http://revisor/salud; done; echo 40 peticiones'
40 peticiones

$ kubectl logs revisor-extra | grep -c 'GET /salud'
12

$ kubectl delete pod revisor-extra
pod "revisor-extra" deleted from default namespace
```

**O Deployment diz `3/3`, o Service tem quatro endereços e ao `revisor-extra` couberam 12 de 40.** O Deployment não o conta, pelo que se viu na Lição 2: o ReplicaSet dele busca também `pod-template-hash`. O Service sim, porque busca só `app: revisor`, e o `revisor-extra` o leva. Para o Service é mais uma réplica: aparece no EndpointSlice dele e recebe a parte do tráfego ao acaso. Com quatro *endpoints*, o esperado são umas 10 de 40, e 12 está perto. Em outra execução será outro número, e não importa qual: o que importa é que não é zero.

No dia em que a imagem do Deployment mudar, o *rollout* substitui as três réplicas e o `revisor-extra` fica com a imagem antiga, porque não é de ninguém. O Service continuaria mandando a parte dele do tráfego, e parte dos usuários veria a versão anterior sem que nenhum `kubectl get deployment` avise. É o aviso da Lição 2 sobre os seletores que se sobrepõem, agora com tráfego de verdade.

### Solução 3

Medido em `correr.salida.txt`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &

$ curl -s -m 3 http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ curl -s -m 3 http://127.0.0.1:18080/salud
[código de salida: 52]
```

(A saída do `rollout status` está recortada: em `correr.salida.txt` cada linha se repete várias vezes, como na Lição 2.) E o que o `port-forward` escreveu:

```text
Forwarding from 127.0.0.1:18080 -> 8080
Handling connection for 18080
Handling connection for 18080
E1021 07:23:02.902759   47411 portforward.go:549] "An error occurred forwarding" err="error forwarding port 8080 to pod 0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb, uid : network namespace for sandbox \"0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb\" is closed" localPort=18080 remotePort=8080
error: lost connection to pod
```

**O `curl` depois do *rollout* falha com 52**, que na lista de erros do curl é “o servidor não devolveu nada”. O túnel não ia ao Service: ia a **um** Pod, escolhido ao abri-lo. O `rollout restart` substituiu os três Pods, incluindo esse. A conexão seguinte chegou ao túnel, o túnel tentou reenviá-la a um Pod cuja rede já estava fechada (`network namespace for sandbox … is closed`) e o `kubectl` desistiu: `error: lost connection to pod`. É exatamente o que diz a referência: “a sessão de reenvio termina quando o Pod escolhido termina, e é preciso executar o comando de novo”. O Service, entretanto, conservou o endereço e o seletor para os clientes de dentro do cluster: o que caiu foi o túnel. Esta lição não mediu se um cliente interno perde alguma requisição durante o *rollout*: o `revisor` ainda não tem *readiness probes* nem desligamento ordenado, e isso chega na Lição 5; a Lição 9 mede com carga de verdade. Por isso o `port-forward` é para olhar, e por isso não serve para publicar nada.

### Solução 4

Uma resposta possível: “Esses nomes são as outras expansões da lista `search` do `/etc/resolv.conf`: a `revisor` se acrescenta cada domínio da lista, e `revisor.svc.cluster.local` e `revisor.cluster.local` de fato não existem. Cada um sai duas vezes porque o `nslookup` do BusyBox pergunta pelo endereço IPv4 e pelo IPv6 de cada nome. Imprime cada falha e termina com código 1 se houve alguma, mesmo que tenha encontrado a resposta. A prova de que sim foi resolvido está na mesma saída: a linha `Name: revisor.default.svc.cluster.local` com o seu `Address`. Para conferir sem ruído: `kubectl exec depurar -- nslookup revisor.default.svc.cluster.local`, que nesta imagem sai limpo.”

## Apagar o cluster

Quando terminar os exercícios, apague o cluster da lição. Nada deve ficar vivo na máquina. Se um `port-forward` ficou aberto em outro terminal, interrompê-lo antes com `Ctrl+C`.

```text
$ kind delete cluster --name curso-k8s-l3
Deleting cluster "curso-k8s-l3" ...
Deleted nodes: ["curso-k8s-l3-control-plane" "curso-k8s-l3-worker" "curso-k8s-l3-worker2"]

$ kind get clusters | grep -c curso-k8s-l3
0
```

O `--name` é obrigatório aqui também: sem ele, o kind apagaria o cluster chamado `kind`, que pode ser de outra pessoa ou de outro projeto. Depois, apagar a pasta temporária do `kubeconfig` (a que o `mktemp` criou, com o prefixo `/tmp/curso-k8s-l3.`; ali está a credencial de administrador do cluster) ou fechar aquele terminal. O cluster da lição seguinte é criado do zero, como este.

## Como saber que deu certo

- [ ] Explicar, com a saída de 3.1 à frente, por que o IP de um Pod não serve como endereço, e o que muda quando o cliente usa o nome de um Service.
- [ ] Escrever de memória um Service `ClusterIP` com `selector` e `ports`, e no do `revisor` dizer qual é `port`, qual `targetPort`, qual `containerPort` e que valor cada um tem.
- [ ] Encontrar o EndpointSlice de qualquer Service com `kubectl get endpointslices -l kubernetes.io/service-name=<nome>` e dizer, pelos endereços dele, para que Pods vai o tráfego.
- [ ] Explicar cada linha do `/etc/resolv.conf` de um Pod e por que `revisor`, `revisor.default` e `revisor.default.svc.cluster.local` levam ao mesmo lugar.
- [ ] Diante de um `curl` com código 7 contra um Service, revisar em ordem o nome, a coluna `ENDPOINTS` e a porta, e distinguir um seletor mal escrito de um `targetPort` mal escrito.
- [ ] Abrir um `port-forward` que escuta só em `127.0.0.1`, conferi-lo com `lsof` (ou `ss` no Linux Mint) e dizer por que ele cai com um *rollout*.
- [ ] Executar `programas/03-services-dns/correr.sh > /tmp/mi-corrida-l3.txt 2>&1` e comparar `/tmp/mi-corrida-l3.txt` com `programas/03-services-dns/correr.salida.txt` (não redirecionar para esse arquivo: é a referência) no que não muda entre execuções: três nós `Ready` em `v1.37.0`; seis linhas `not yet present on node … loading...`; o Service `revisor` como `ClusterIP` em `80/TCP` com `EXTERNAL-IP <none>`; `TargetPort: http/TCP` e três `Endpoints` na `8080`; o EndpointSlice com `PORTS 8080`, três endereços e dono `Service/revisor`; o aviso `v1 Endpoints is deprecated in v1.33+`; `uid=100(curl_user)`; `{"estado":"vivo","version":"1.6.0"}` por nome e por IP; o `resolv.conf` com as suas três linhas; `kube-dns` em `10.96.0.10`; `lookup prueba … no such host` antes de criar o serviço de teste, e depois `OK … 200`, `FALLA … codigo 503` e `FALLA … se acabo el tiempo de espera`; as três réplicas com alguma requisição em 3.8; `Forwarding from 127.0.0.1:18080 -> 8080` e `kubectl TCP 127.0.0.1:18080 (LISTEN)`; o código 28 a partir da máquina local; os dois nós de trabalho sem portas publicadas; código 7 com o seletor ruim, em milésimos de segundo, e `<unset>` no EndpointSlice dele; `PORTS 8081` e código 7 no Exercício 1; quatro endereços com `revisor-extra` no Exercício 2; o código 52 e `lost connection to pod` no Exercício 3; `sin diferencias con los archivos`; e no final `0` clusters `curso-k8s-l3` e a linha `la corrida completa tardó … s`. Os IPs, os sufixos dos nomes, as idades, a porta que o nó de controle publica, em que nó cai cada Pod, a ordem das linhas do `kind load` e das do `nslookup`, a distribuição exata das requisições, os tempos e as vezes que se repete cada linha do `rollout status` mudam em cada execução: observam-se, não se comparam. Se outra porta foi usada com `PUERTO_LOCAL`, aparecerá esse número no lugar do `18080`.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l3`.

## Resumo

Responda sem olhar a lição:

1. Por que não se deve guardar o IP de um Pod na configuração de outro programa? O que mudou no Pod de 3.1 além do IP?
2. O que faz um Service do tipo `ClusterIP`, de onde ele é alcançado e por que é o tipo padrão que este curso escreve mesmo assim?
3. No Service do `revisor`, o que é `port`, o que é `targetPort` e de onde sai a `8080`? Por que `targetPort` vai por nome?
4. Que objeto guarda a lista de Pods de um Service, quem a escreve e com que rótulo se encontra?
5. O que é `kube-dns`, em que IP está e por que se parece tanto com o Service do `revisor`?
6. Que três linhas tem o `/etc/resolv.conf` de um Pod e o que faz cada uma?
7. Como o `kube-proxy` escolhe para que réplica manda uma conexão, no modo padrão?
8. Que códigos do `curl` distinguem “não resolveu o nome”, “recusou a conexão” e “não respondeu a tempo”?
9. Com quantos Pods fala o `kubectl port-forward service/revisor`, e o que acontece com ele em um *rollout*?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Service”](https://kubernetes.io/docs/concepts/services-networking/service/): o que é um Service; o tipo `ClusterIP` como valor padrão e alcançável somente de dentro do cluster; `targetPort` igual a `port` por padrão; as portas com nome; o *cluster IP*; a API `Endpoints`, obsoleta desde a v1.33, e por quê.
- [Kubernetes, “EndpointSlices”](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/): o que guarda um EndpointSlice; o rótulo `kubernetes.io/service-name` e a referência ao dono; o teto de 100 *endpoints* por EndpointSlice; as condições `serving`, `terminating` e `ready`.
- [Kubernetes, “DNS for Services and Pods”](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): a forma do nome de um Service; as consultas sem namespace limitadas ao do Pod; o `/etc/resolv.conf` com `search` e `ndots:5`.
- [Kubernetes, “Debug Services”](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/): o laço de controle que preenche os EndpointSlices; o seletor com erro de digitação como erro comum; as perguntas sobre `targetPort`; e por que `ndots` vale 5.
- [Kubernetes, “Virtual IPs and Service Proxies”](https://kubernetes.io/docs/reference/networking/virtual-ips/): o `kube-proxy` como responsável pelos IPs virtuais; `iptables` como modo padrão no Kubernetes 1.37 e a escolha do Pod ao acaso; `sessionAffinity` e o valor padrão `None`.
- [Kubernetes, “kubectl port-forward”](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/): que reenvia para um Pod; a escolha automática de um Pod e o fim da sessão quando esse Pod termina; `--address` e o valor padrão `localhost`; o exemplo com `0.0.0.0`.
- [Kubernetes, “Pods”](https://kubernetes.io/docs/concepts/workloads/pods/): os Pods como entidades efêmeras e descartáveis.
- [kind, “Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/): as sub-redes padrão de Pods (`10.244.0.0/16`) e de Services (`10.96.0.0/16`), e o `kindnetd` como rede padrão.
- [kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind load docker-image` com `--name`.
- [curl, “libcurl error codes”](https://curl.se/libcurl/c/libcurl-errors.html): o significado dos códigos de saída 6, 7, 28 e 52.

---

**Próxima:** [Lição 4 — Configuração e segredos](04-configuracion-secretos.md)
