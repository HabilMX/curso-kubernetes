# Lição 6 — Entrar no cluster

Quinta-feira, 4h40 da tarde. A equipe de operação quer ver o relatório do `revisor` no próprio painel, que roda em outra máquina, fora do cluster, e a apresentação para a diretoria é às 5h30. No chat da equipe já há duas propostas. A primeira: “muda o Service para `NodePort` e passa o IP de um nó para eles”. A segunda vem com um link para um tutorial de dois anos atrás: “instala o `ingress-nginx`, são três comandos”. As duas funcionam esta tarde. A primeira deixa o `revisor` aberto em uma porta aleatória de **todos** os nós, sem que ninguém tenha decidido isso por escrito. A segunda instala um componente que deixou de receber patches de segurança em março de 2026. E há uma terceira tentação, a do README do kind: um programa que roda na máquina e dá balanceadores de carga aos clusters… a **todos** os clusters do kind, inclusive os dos colegas, se compartilharem a máquina.

Esta lição ensina a abrir uma entrada para o cluster sem esses atalhos: um `LoadBalancer` com MetalLB e um ponto de entrada nomeado com Gateway API e Envoy Gateway, os dois instalados **dentro** do cluster, para que vão embora com ele quando for apagado. E ensina algo que vale para tudo o que se instalar no Kubernetes daqui em diante: há peças que são **plataforma** e peças que são **projeto**, e a plataforma precisa estar pronta antes que o projeto a use.

**Tempo:** 2 × 45 min

**O que se constrói:** o `revisor` publicado para fora do cluster, primeiro com um Service `LoadBalancer` que recebe o IP `172.18.255.200` e depois por um ponto de entrada nomeado, o Gateway `revisor`, com a rota dele para o Service de sempre

**O que se aprende:** por que um `LoadBalancer` fica em `<pending>` no kind e o que ele abre mesmo pendente (um `NodePort` em cada nó); o que o MetalLB faz na camada 2 e por que a faixa de IPs dele sai da rede `kind` do Docker; o que são os recursos personalizados (CRDs) e os *webhooks* de admissão, e por que obrigam a instalar em ordem; a Gateway API com as três peças, `GatewayClass`, `Gateway` e `HTTPRoute`, atendidas pelo Envoy Gateway; por que não se usa o Cloud Provider KIND em uma máquina compartilhada; o `Ingress` como API congelada e por que não o `ingress-nginx`; e o que fica exposto, por onde e sem o quê (criptografia em trânsito)

**De onde a gente vem.** Da [Lição 5](05-salud-recursos-apagado.md): o `revisor` roda com três réplicas, com as *probes* `startup`, `readiness` e `liveness`, com `requests` e `limits`, com o `ConfigMap` como variáveis e o token como arquivo, tudo aplicado com `kubectl apply -k .`. O serviço de teste também é vigiado. Da [Lição 3](03-services-dns.md) vem a regra de que tudo nasce como `ClusterIP` e nada é publicado à toa, e a ordem para diagnosticar um Service que não responde: o código do `curl`, o nome, a coluna `ENDPOINTS`. Hoje essa regra se rompe pela primeira vez, de propósito e por escrito.

**O que esta lição não faz.** Não coloca criptografia: o ponto de entrada fala HTTP puro na porta 80, e a seção do hábito de segurança mede isso e o diz. Ainda não fecha quem fala com quem **dentro** do cluster: isso é a [Lição 7](07-aislar-permisos-red.md), que além disso retira o `LoadBalancer` direto e deixa o Gateway como o único ponto de entrada. Não dá um nome de domínio nem um balanceador de carga de verdade de um provedor de nuvem: os IPs que o MetalLB distribui aqui só existem na rede `kind` do Docker da máquina. E o `revisor` continua no namespace `default`; a mudança para um namespace próprio é da Lição 7.

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com `kind` v0.33.0, `kubectl` v1.37.1, a imagem de nó `kindest/node:v1.37.0` fixada pelo *digest*, **MetalLB v0.16.1** e **Envoy Gateway v1.9.2** (que traz a Gateway API v1.6.1), no cluster de três nós da Lição 1, aqui chamado de `curso-k8s-l6`. A máquina foi um Mac com processador ARM e Docker Engine 29.2.1 dentro de uma máquina virtual Linux (Colima), **não** o Linux Mint, que é o sistema de referência do curso. O que muda no Mint: a arquitetura, os IPs dos Pods, dos Services e dos nós (`172.18.0.2` a `.4`, em outra ordem), os `NodePort` que o cluster escolhe ao acaso, os sufixos dos nomes, as idades e o nó a partir do qual o MetalLB anuncia cada IP. Os dois IPs do MetalLB, `172.18.255.200` e `172.18.255.201`, **devem** sair idênticos se a rede `kind` for `172.18.0.0/16`. E há uma diferença que importa: no Mac, a rede `kind` vive dentro da máquina virtual e o terminal não a alcança (isso aparece no hábito de segurança: código 28); no Linux, o Docker conecta a máquina a essa rede, então no Mint `curl http://172.18.255.200/salud` a partir do terminal deveria responder. Para que o exemplo seja o mesmo nos dois sistemas, o “cliente de fora” desta lição é um contêiner do Docker conectado à rede `kind`, fora do cluster. O percurso completo está em [`programas/06-entrar-al-cluster/`](../programas/06-entrar-al-cluster): o `correr.sh` cria o cluster, carrega nele as duas imagens, percorre a lição em ordem, roda os Exercícios 1 a 3 e apaga o cluster. No final repete, em um cluster novo, os três passos de 6.9 com o `levantar.sh`. A execução completa, com os dois clusters, levou 15 minutos e 20 segundos (920 segundos): criar o primeiro cluster e esperar que ficasse pronto foram 40 segundos, criar o segundo, 46, apagar o primeiro, 1, e o `levantar.sh` levou 266. A saída é `correr.salida.txt`. Precisa de internet: os manifestos do MetalLB e do Envoy Gateway são baixados das releases, fixadas na versão, e as imagens são baixadas na primeira vez.

## Ao terminar, a gente vai conseguir

- Explicar por que um Service `LoadBalancer` fica em `<pending>` no kind, e demonstrar com `curl` que mesmo assim ele já abriu um `NodePort` em cada nó.
- Instalar o MetalLB dentro de um cluster, dar a ele uma faixa de IPs tirada da rede `kind` e ler nos eventos do Service quem atribuiu o IP e de que nó ele é anunciado.
- Distinguir uma peça de **plataforma** (CRDs, controladores, *webhooks*) de uma peça de **projeto**, e aplicá-las em três passos: plataforma, espera com `kubectl wait`, projeto.
- Reconhecer os erros de aplicar fora de ordem: `no matches for kind … ensure CRDs are installed first` e `failed calling webhook … connection refused`.
- Escrever um `Gateway` e uma `HTTPRoute` para o `revisor`, e ler o estado deles (`PROGRAMMED`, `Accepted`, `ResolvedRefs`).
- Provocar uma rota para um Service que não existe, reconhecê-la por `ResolvedRefs=False BackendNotFound` e pelo `500` do ponto de entrada, e corrigi-la.
- Dizer o que fica exposto depois desta lição, por que ponto de entrada, e o que falta (criptografia em trânsito), e explicar por que não o Cloud Provider KIND nem o `ingress-nginx`.

## O porquê antes do como

Até agora, tudo o que falou com o `revisor` estava **dentro** do cluster: o Pod `depurar`, o próprio `revisor` consultando o `prueba`, as *probes* do `kubelet`. A entrada era por um túnel temporário, o `port-forward`, que dura o que dura o comando e fala com um único Pod. Isso basta para olhar. Não basta para o painel de operação da cena, que precisa de um endereço estável, que sobreviva aos *rollouts*, que distribua entre réplicas e que não dependa de o notebook estar ligado.

O Kubernetes tem três formas de abrir esse endereço, da mais tosca à mais refinada:

1. **`NodePort`**: o cluster abre uma porta alta (entre 30000 e 32767) em **todos** os nós, e o que chegar ali vai para o Service. Funciona, mas o cliente precisa saber o IP de um nó e um número que o cluster escolheu.
2. **`LoadBalancer`**: o mesmo que o `NodePort`, mais um balanceador de carga **fora** do cluster, com IP próprio, que distribui entre os nós. Em uma nuvem, esse balanceador é criado pelo provedor. No kind não há nuvem, e por isso o Service fica esperando.
3. **Um ponto de entrada de camada 7** (HTTP): um único ponto que recebe o tráfego e decide, pelo caminho ou pelo nome do site, para que Service vai cada requisição. A forma vigente de declará-lo é a **Gateway API**. A forma antiga, o `Ingress`, continua existindo e está congelada.

No kind, as opções 2 e 3 precisam de algo que o cluster não traz: alguém que distribua endereços IP e alguém que atenda o ponto de entrada. Este curso instala os dois **dentro** do cluster. O **MetalLB** distribui os IPs. O **Envoy Gateway** atende o ponto de entrada. Cada um é instalado com os próprios tipos de objeto (recursos personalizados) e os próprios guardiões (*webhooks*), e daí sai a lição mais útil de hoje, a que a gente vai usar em todo cluster real: a plataforma vai primeiro, espera-se que esteja pronta, e depois vai o projeto. Não é mania. É o que o cluster exige, e a gente vai vê-lo exigir.

A lição tem oito partes de conceitos e depois as seções de sempre:

1. **O cluster da lição** (6.1), com `kubeconfig` próprio.
2. **O projeto antes da plataforma** (6.2): o que falha e por quê.
3. **Um `LoadBalancer` sem ninguém que distribua endereços** (6.3), e o `NodePort` que ele já abriu.
4. **MetalLB** (6.4): a faixa de IPs, a camada 2 e o *webhook* que ainda não escuta.
5. **Por que não o Cloud Provider KIND** (6.5).
6. **Envoy Gateway e Gateway API** (6.6): a plataforma do ponto de entrada.
7. **O ponto de entrada do `revisor`** (6.7): `Gateway` e `HTTPRoute`.
8. **`Ingress` e `ingress-nginx`** (6.8): o que foi aposentado, para reconhecê-lo.

E no final dos conceitos, **a ordem** (6.9), escrita em três passos.

Este é o destino. No final de 6.7, um cliente que não faz parte do cluster pede o relatório ao `revisor` pelo ponto de entrada nomeado:

```text
$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200
```

## Se a imagem do curso de Docker não estiver disponível

Esta lição usa as mesmas duas imagens das Lições 3 a 5: `curso-docker-revisor:1.6.0`, a do `revisor`, e `curso-docker-prueba:1.0.0`, a do serviço que falha de propósito. Confira que elas existem:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Se faltar alguma, a [Lição 3](03-services-dns.md) diz, nesta mesma seção, como construir as duas a partir do repositório do curso de Docker. Esta lição não exige nada de novo de nenhuma das duas imagens. O novo vem de fora: as imagens do MetalLB e do Envoy, que não são carregadas com `kind load`, e sim baixadas da internet por cada nó na primeira vez, como a do `curl` na Lição 3.

## Os conceitos

### 6.1 O cluster da lição

#### 6.1.1 Antes de criar: uma regra de convivência

Esta é a primeira lição do curso que instala o **MetalLB**, e o MetalLB tem uma particularidade que obriga a uma regra nova. Ele vai pegar endereços IP da rede `kind` do Docker, a rede que **todos** os clusters do kind da máquina compartilham. Se dois clusters com MetalLB e a mesma faixa rodarem ao mesmo tempo, os dois anunciam os mesmos endereços e entram em conflito: umas requisições chegam a um e outras ao outro. Por isso, antes de criar o cluster, confira duas coisas:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar ya en 172.18.255.200. Si este curl responde algo,
# hay otro clúster con MetalLB vivo: espera a que termine.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 3 http://172.18.255.200/
```

A rede `kind` é criada pelo kind na primeira vez que cria um cluster, então o primeiro comando falha se nunca foi criado um; nesse caso, crie o cluster e confira a rede logo depois, antes de instalar qualquer coisa. Na execução desta lição a rede saiu assim:

```text
$ docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
fc00:f853:ccd:e793::/64 172.18.0.0/16 
```

Duas sub-redes: uma IPv6 e a IPv4 `172.18.0.0/16`, que é a que importa. Se a da máquina for outra (por exemplo `172.19.0.0/16`, porque na máquina já havia outra rede com a `172.18`), será preciso mudar a faixa de `infra/metallb-pool.yaml` para que caia dentro dela, e todos os IPs desta lição sairão diferentes. Há uma terceira verificação, a mais barata: `kind get clusters`. Se aparecer outro cluster vivo que não é da própria pessoa, convém perguntar ao dono se ele usa MetalLB e com que faixa antes de seguir; o `curl` só vê quem responde HTTP na porta 80 do `.200`, e um MetalLB alheio com outra porta ou com outros endereços da faixa (`.201` a `.220`) passaria sem ser notado. O `correr.sh` faz as duas primeiras e para antes de criar qualquer coisa se alguma falhar; se a rede `kind` ainda não existir, também para, porque não consegue ler a faixa dela. Nesse caso, é preciso criar um cluster qualquer de teste, olhar a rede e apagá-lo, ou criar a rede manualmente com a mesma sub-rede.

#### 6.1.2 Criar, conferir, carregar

A partir da raiz do repositório do curso, com o mesmo cuidado de sempre:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta se queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l6.XXXX)/kubeconfig"
# curso-k8s-l6 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l6 --config programas/06-entrar-al-cluster/kind-curso.yaml
# Debe decir kind-curso-k8s-l6. Si dice otra cosa, no sigas.
kubectl config current-context
# Una guarda que se detiene sola (la de la Lección 5, con el nombre de este clúster).
# Va delante de cada comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l6
cd programas/06-entrar-al-cluster
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

A função `ctx` compara o contexto ativo com o esperado. Se coincide, não imprime nada e devolve sucesso; se não, escreve “contexto equivocado: no sigo” e devolve um erro, e o `&&` faz com que o comando seguinte **não seja executado**. É a diferença entre olhar o contexto “a olho”, que depende de se estar atento, e uma proteção que para a pessoa mesmo quando ela está com pressa. Hoje vão ser instalados componentes que criam dezenas de objetos no cluster, incluindo objetos que valem para o cluster inteiro e não para um namespace; aplicá-los no contexto errado seria instalá-los no cluster de outra pessoa. Por isso, **na frente de cada** `apply`, `delete` ou `patch` desta lição vai `ctx &&`. Nas saídas a seguir ele é omitido para que caibam, mas no terminal vai sempre. (O `correr.sh` faz o mesmo em cada comando.)

O `(umask 077; …)` merece uma explicação. O `umask` é a máscara que diz ao shell que permissões **tirar** de todo arquivo novo; com a habitual (`022`), o `token.txt` nasceria `-rw-r--r--`, legível por qualquer usuário da máquina. Com `077`, nasce `-rw-------`: só o dono. Os parênteses fazem a mudança de máscara valer só para esse comando e não ficar no terminal. É o mesmo cuidado das Lições 4 e 5, e pesa mais hoje, porque esta lição fala de máquinas compartilhadas.

```text
$ kubectl config current-context
kind-curso-k8s-l6

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l6-control-plane  Ready   v1.37.0  172.18.0.4
curso-k8s-l6-worker         Ready   v1.37.0  172.18.0.3
curso-k8s-l6-worker2        Ready   v1.37.0  172.18.0.2
```

A coluna nova é `INTERNAL-IP`: o endereço de cada nó **na rede `kind`** do Docker. Lembre-se da Lição 0: um nó do kind é um contêiner; este é o IP desse contêiner. Os três caem no começo de `172.18.0.0/16`, porque o Docker distribui de baixo para cima. Convém guardá-los na memória: em 6.3 um cliente de fora vai entrar por eles.

O `kind load` imprime as seis linhas de sempre, `not yet present on node … loading...`, duas imagens por três nós. Estão em `correr.salida.txt`.

#### 6.1.3 O cliente de fora

Para testar de fora do cluster, esta lição usa um contêiner de `curl` conectado à rede `kind`, com o nome `curso-k8s-l6-cliente` e `--rm` para que seja apagado sozinho ao terminar cada requisição. É um cliente de verdade: não é um Pod, o cluster não o conhece, não passa pelo DNS do cluster nem pelo `kube-proxy` dos nós. Vê a rede como a veria uma máquina conectada ao mesmo segmento que os nós. Para não escrever a linha completa toda vez, define-se uma função no terminal:

```bash
afuera() {
  docker run --rm --network kind --name curso-k8s-l6-cliente \
    curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 "$@"
}
# Uso:  afuera -s -m 5 http://172.18.255.200/salud
```

Nas saídas desta lição, **as linhas que começam com `$ curl` rodam assim**, a partir desse contêiner, exceto uma da seção do hábito de segurança, que roda no terminal de propósito e avisa isso. No Linux Mint é possível usar o `curl` direto do terminal, se preferir; o resultado deve ser o mesmo.

Um aviso para a máquina compartilhada: ao passar o token com `-H "Authorization: Bearer $(cat token.txt)"`, o token fica como **argumento do comando**, e enquanto o comando roda qualquer usuário da máquina o vê na lista de processos (`ps`). Para o token fictício deste curso não tem problema; com um token real, ele é passado a partir de um arquivo (`-H @arquivo`, que o `curl` aceita desde a versão 7.55) ou pela entrada padrão, nunca escrito na linha.

### 6.2 O projeto antes da plataforma

#### 6.2.1 O que a pasta traz

A pasta desta lição traz o mesmo que a Lição 5 deixou — os dois Deployments, os dois Services, o gerador do `ConfigMap` e o do `Secret` — e dois arquivos novos. O `kustomization.yaml` já os menciona. É um **programa**: `programas/06-entrar-al-cluster/kustomization.yaml`.

```yaml
# kustomization.yaml — Lecciones 4 a 6. Se aplica con: kubectl apply -k .
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Antes de esta kustomization van las piezas de infra/ (MetalLB y Envoy Gateway):
# sin sus CRD, Gateway y HTTPRoute no existen. Ver correr.sh para el orden.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
- revisor-publico.yaml
- gateway.yaml
configMapGenerator:
- name: revisor-config
  literals:
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s
secretGenerator:
- name: revisor-token
  files:
  - token=token.txt
  options:
    immutable: true
```

As duas linhas novas de `resources` são `revisor-publico.yaml` (6.3) e `gateway.yaml` (6.7). O comentário de cima já avisa o que vai ser conferido agora: “antes desta kustomization vão as peças de `infra/`”. Faça o que qualquer pessoa com pressa faria às 4h40: ignore o aviso e aplique.

#### 6.2.2 Aplicar sem a plataforma

```text
$ kubectl get crd
No resources found

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "revisor" namespace: "" from ".": no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
[código de salida: 1]
```

Leia a saída em duas metades. Em cima, sete objetos `created`: tudo o que o cluster já sabia o que era. Os nomes dos gerados são os da Lição 4: `revisor-config-t6cm6872fk`, idêntico em outra execução porque a lista não mudou, e `revisor-token-…`, diferente porque o token é novo. Embaixo, dois objetos que o cluster **não reconhece**: “não encontro o tipo `Gateway` na versão `gateway.networking.k8s.io/v1`”, e a sugestão, em inglês, “certifique-se de instalar primeiro os CRDs”. O `kubectl` aplicou o que pôde, pulou o que não pôde, e saiu com código 1. Um script com `set -e` pararia aqui; um sem ele continuaria como se nada tivesse acontecido, e isso é pior.

O primeiro comando, `kubectl get crd`, já anunciava isso: `No resources found`. Este cluster não tem **nenhum** recurso personalizado. E a prova direta:

```text
$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME   SHORTNAMES   APIVERSION   NAMESPACED   KIND
```

Só os cabeçalhos. O grupo `gateway.networking.k8s.io` não existe neste cluster.

#### 6.2.3 O que é um CRD

Até agora, todos os tipos usados — `Pod`, `Deployment`, `Service`, `ConfigMap`, `Secret` — vêm **dentro** do Kubernetes: o `kube-apiserver` os conhece desde que inicia. `Gateway` e `HTTPRoute` não. A [documentação de recursos personalizados](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) diz assim: um recurso personalizado “é uma extensão da API do Kubernetes que não está necessariamente disponível em uma instalação padrão”. E explica como se adiciona um: com um objeto `CustomResourceDefinition` (CRD). “Definir um objeto CRD cria um novo recurso personalizado, com o nome e o esquema especificados. A API do Kubernetes serve e armazena o recurso personalizado.”

Ou seja: um CRD é um objeto que **ensina** ao `kube-apiserver` um tipo novo. Enquanto não existir o CRD de `Gateway`, um manifesto com `kind: Gateway` é, para o cluster, um texto que não significa nada. É o primeiro motivo da ordem: **os tipos precisam existir antes dos objetos desses tipos**.

A [página da Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) do Kubernetes diz isso sobre o próprio caso: a Gateway API “é um complemento (*add-on*) que contém tipos de API” e as especificações dela “são definidas como recursos personalizados”. Não vem com o Kubernetes. Alguém precisa instalá-la, e neste curso quem a instala é o Envoy Gateway (6.6).

Repare no que **foi** criado: o `revisor` e o `prueba` estão rodando, com os Services, e entre eles o `revisor-publico`. É exatamente o ponto de partida de que esta lição precisa: o da Lição 5, mais um ponto de entrada pedido e ainda sem abrir.

### 6.3 Um `LoadBalancer` sem ninguém que distribua endereços

#### 6.3.1 O manifesto

É um **programa**: `revisor-publico.yaml`.

```yaml
# revisor-publico.yaml — Lección 6: un Service LoadBalancer. Su EXTERNAL-IP la
# reparte MetalLB (infra/metallb-pool.yaml); sin MetalLB se queda en <pending>.
# En la Lección 7 se retira: la única puerta que queda es el Gateway.
apiVersion: v1
kind: Service
metadata:
  name: revisor-publico
  labels:
    app: revisor
spec:
  type: LoadBalancer
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

É o Service da Lição 3 com duas diferenças: chama-se `revisor-publico` e o `type` dele é `LoadBalancer`. Mesmo seletor, mesmo `port: 80`, mesmo `targetPort: http`. Não substitui o `revisor` `ClusterIP`: os dois existem ao mesmo tempo e escolhem os mesmos Pods. O de dentro continua sendo para os clientes de dentro; este é a entrada para fora. Que sejam dois objetos e não um com o tipo alterado é uma decisão: no dia em que for preciso fechar a entrada (a Lição 7 faz isso), apaga-se o `revisor-publico` e nada do que está dentro percebe.

#### 6.3.2 `<pending>`

```text
$ kubectl get services
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes        ClusterIP      10.96.0.1       <none>        443/TCP        36s
prueba            ClusterIP      10.96.248.146   <none>        9000/TCP       7s
revisor           ClusterIP      10.96.157.248   <none>        80/TCP         7s
revisor-publico   LoadBalancer   10.96.115.79    <pending>     80:30808/TCP   7s
```

`EXTERNAL-IP <pending>`: o Service pediu um IP externo e ninguém o deu. A [documentação de Services](https://kubernetes.io/docs/concepts/services-networking/service/) explica de quem é esse trabalho: “em provedores de nuvem que oferecem suporte a balanceadores de carga externos, definir o campo `type` como `LoadBalancer` provisiona um balanceador de carga para o Service. A criação real do balanceador de carga acontece de forma assíncrona, e as informações sobre o balanceador provisionado são publicadas no campo `.status.loadBalancer` do Service”. No kind não há provedor de nuvem. O campo fica vazio e o `kubectl` o mostra como `<pending>`, para sempre, sem um único erro:

```text
$ kubectl describe service revisor-publico | grep -E '^(Type|LoadBalancer Ingress|Port|NodePort|Endpoints|Events):'
Type:                     LoadBalancer
Port:                     http  80/TCP
NodePort:                 http  30808/TCP
Endpoints:                10.244.2.3:8080,10.244.1.2:8080,10.244.2.4:8080
Events:                   <none>
```

Não há linha `LoadBalancer Ingress` (ali ficaria o IP) e não há eventos: ninguém tentou nada, então ninguém falhou. É o tipo de estado que confunde, porque nada está vermelho. A única pista é a palavra `<pending>`.

#### 6.3.3 O que ele abriu: um `NodePort` em cada nó

Olhe de novo a coluna `PORT(S)`: `80:30808/TCP`. E no `describe`, `NodePort: http 30808/TCP`. O Service pediu um balanceador de carga que não chegou, mas algo chegou: uma **porta nos nós**. A mesma documentação explica: “para implementar um Service de `type: LoadBalancer`, o Kubernetes normalmente começa fazendo as mudanças equivalentes a pedir um Service de `type: NodePort`. Depois, o `cloud-controller-manager` configura o balanceador de carga externo para encaminhar o tráfego para essa porta do nó”. Um `LoadBalancer` é um `NodePort` **mais** alguém de fora. Aqui falta esse alguém, mas o `NodePort` já está aberto. Confere-se a partir do cliente de fora, contra o IP de um nó de trabalho e contra o do nó de controle:

```text
$ curl -s -m 5 http://172.18.0.3:30808/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 http://172.18.0.4:30808/salud
{"estado":"vivo","version":"1.6.0"}
```

As duas respondem. `172.18.0.3` é o `worker`; `172.18.0.4` é o nó de **controle**, onde não roda nenhuma réplica do `revisor`. E mesmo assim responde: o `kube-proxy` de cada nó, inclusive o do nó de controle, escuta na 30808 e encaminha para uma réplica, esteja onde estiver. Isso é o que a primeira proposta da cena teria deixado aberto, e é o que **já** está aberto mesmo que o IP externo nunca chegue.

A documentação diz como evitá-lo: com `spec.allocateLoadBalancerNodePorts: false`, que “só deve ser usado com implementações de balanceador de carga que enviam o tráfego diretamente aos Pods, em vez de usar portas de nó”. O valor padrão é `true`. O MetalLB na camada 2, o que esta lição instala, entrega o tráfego a um nó e deixa que o `kube-proxy` o distribua, então este curso não o desliga; mas o nomeia, porque “o que fica exposto” inclui essa porta, e a seção do hábito de segurança conta isso.

### 6.4 MetalLB: quem distribui os endereços, dentro do cluster

#### 6.4.1 O que é

O MetalLB é um balanceador de carga para clusters que não vivem em uma nuvem: os de um data center próprio, os de casa e os do kind. O [guia de instalação](https://metallb.io/installation/) dele descreve as duas peças: o `controller`, um Deployment, “o controlador de todo o cluster, responsável por atribuir os endereços IP”; e o `speaker`, um DaemonSet (um Pod por nó), “o componente que fala os protocolos escolhidos para que os Services sejam alcançáveis”. O primeiro decide que IP cabe a cada Service. O segundo faz com que esse IP exista na rede.

Nesta lição o MetalLB trabalha na **camada 2**. O [guia de configuração](https://metallb.io/configuration/) dele explica em uma frase: “funciona respondendo diretamente às requisições ARP da rede local, para dar aos clientes o endereço MAC da máquina”. O ARP é a pergunta que um equipamento faz em uma rede local para saber quem tem um IP: “quem tem `172.18.255.200`?”. Nenhuma máquina tem esse IP configurado. Mas o `speaker` de um nó responde “eu”, e a partir desse momento o tráfego para esse IP chega a esse nó, onde o `kube-proxy` o distribui entre as réplicas. É um truque honesto: não há um aparelho balanceador, há um nó que assume o endereço.

#### 6.4.2 Instalar: os CRDs e o *webhook*

A instalação é um manifesto da release v0.16.1, o que o guia oficial indica, fixado na versão. Este curso o envolve em uma kustomization para poder aplicá-lo com `-k` como todo o resto. É um **programa**: `infra/metallb/kustomization.yaml`.

```yaml
# MetalLB v0.16.1 (modo nativo, capa 2), instalado SOLO en este clúster.
# Es la versión que indica la guía oficial de instalación (metallb.io/installation).
# Se aplica antes que todo lo demás de la Lección 6: kubectl apply -k infra/metallb
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
```

O guia diz algo que vale a pena ler antes de aplicar: sem configuração, “os componentes do MetalLB iniciam, mas ficam parados” até receberem uma faixa. Então são dois passos: instalar e dar a faixa. Faça o que qualquer pessoa com pressa faria, de novo: os dois seguidos.

```text
$ kubectl apply -k infra/metallb | tail -5
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply -f infra/metallb-pool.yaml
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
Error from server (InternalError): error when creating "infra/metallb-pool.yaml": Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.93.252:443: connect: connection refused
[código de salida: 1]
```

Um erro diferente do de 6.2. Desta vez o tipo **existe** — o `apply` do MetalLB criou os CRDs dele no mesmo instante —, e mesmo assim o cluster rejeitou os dois objetos. Interprete-o da direita para a esquerda: `connect: connection refused` contra `10.96.93.252:443`; esse IP é o do Service `metallb-webhook-service`, que acabava de ser criado (`created`, na linha dois da saída anterior); e o que falhava era “chamar o *webhook* `ipaddresspoolvalidationwebhook.metallb.io`”.

Um ***webhook* de admissão** é outro guardião que a plataforma adiciona ao `kube-apiserver`. A [documentação de controladores de admissão extensíveis](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) os define assim: “os *webhooks* de admissão são callbacks HTTP que recebem requisições de admissão e fazem algo com elas”. Os de validação “podem rejeitar requisições para aplicar políticas personalizadas”. O MetalLB instala um para conferir que uma faixa esteja bem escrita antes de aceitá-la. O `kube-apiserver`, antes de guardar o `IPAddressPool`, pergunta ao *webhook*. Mas o Pod que responde a essa pergunta, o `controller`, ainda estava iniciando. Ninguém escutava na 443. E o que faz o `kube-apiserver` quando não consegue perguntar? Isso é decidido por um campo do *webhook*, `failurePolicy`. A mesma página diz: com `failurePolicy: Fail`, que é o valor padrão, “uma falha ao chamar o *webhook* faz a admissão falhar e a requisição ser rejeitada”. O MetalLB o escreve explicitamente nos seis *webhooks* (dá para conferir, e a execução confere mais abaixo): melhor rejeitar do que deixar passar um objeto sem conferir.

Esse é o segundo motivo da ordem: **os guardiões precisam estar escutando antes que chegue aquilo que vão conferir**. A política do *webhook* do MetalLB se lê no próprio cluster; há um valor para cada um dos seis guardiões:

```text
$ kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Fail Fail Fail Fail Fail Fail
```

Seis `Fail`: nenhum deixa passar um objeto se não consegue conferi-lo. E não basta que o CRD exista:

```text
$ kubectl get crd -o name | grep metallb.io
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io
```

Nove tipos novos, todos do grupo `metallb.io`. Vários são para o outro modo do MetalLB, o BGP, que este curso não usa. Os dois de hoje são `ipaddresspools` e `l2advertisements`.

#### 6.4.3 Esperar, com `kubectl wait`

A correção não é tentar de novo até passar. É **esperar por uma condição** e depois aplicar:

```text
$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl apply -f infra/metallb-pool.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
```

A [referência do `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) descreve: o comando “recebe vários recursos e espera até que a condição indicada apareça no campo `Status` de cada um”. `condition=Available` em um Deployment quer dizer que ele tem a disponibilidade **mínima** que a estratégia de atualização permite (a documentação de Deployments a define assim). Com o `controller` do MetalLB, que tem uma única réplica, isso é o mesmo que “a única réplica está pronta”; “pronta” no sentido da Lição 5, o das *probes* `readiness`. Com um Deployment de três réplicas e `maxUnavailable` de 25 %, o `Available` chegaria com menos réplicas prontas do que as pedidas: não deve ser lido como “todas”. Nesta execução, assim que o `controller` ficou `Available`, o *webhook* já respondia. Para o DaemonSet usa-se `rollout status`, o mesmo comando da Lição 2, que espera que haja um `speaker` pronto em cada um dos três nós. Com `--timeout`, nenhuma espera é infinita: se algo não chega, o comando falha e dá para saber.

Mesmo arquivo, sem mudar uma vírgula, e desta vez `created`. O arquivo nunca esteve errado. Estava adiantado.

```text
$ kubectl get pods -n metallb-system -o wide | awk '{print $1, $2, $3, $6, $7}' | column -t
NAME                         READY  STATUS   IP          NODE
controller-76f4cf76b7-hpzjj  1/1    Running  10.244.1.3  curso-k8s-l6-worker
speaker-455xp                1/1    Running  172.18.0.3  curso-k8s-l6-worker
speaker-jvbvh                1/1    Running  172.18.0.2  curso-k8s-l6-worker2
speaker-xctwr                1/1    Running  172.18.0.4  curso-k8s-l6-control-plane
```

Um `controller` com IP da rede de Pods (`10.244.`) e três `speaker`, um por nó, com o IP **do nó** (`172.18.0.`). Isso último não é coincidência: o `speaker` precisa responder ARP na rede `kind`, então roda com a rede do nó, não com a rede de Pods.

#### 6.4.4 A faixa de IPs

É um **programa**: `infra/metallb-pool.yaml`.

```yaml
# metallb-pool.yaml — las IP que MetalLB puede repartir a los Services LoadBalancer.
# Salen de la red «kind» de Docker (en la máquina de las corridas, 172.18.0.0/16;
# compruébala con: docker network inspect kind). Se toma el final del rango, lejos
# de las IP que Docker da a los nodos.
# ⚠️ Dos clústeres de kind con MetalLB y el MISMO rango en la misma red se pisan
# (los dos anuncian las mismas IP): en una máquina compartida, un rango por clúster.
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: curso
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: curso
  namespace: metallb-system
spec:
  ipAddressPools:
  - curso
```

Dois objetos, duas decisões:

- **`IPAddressPool`** diz **quais** endereços ele pode distribuir: do `172.18.255.200` ao `172.18.255.220`, vinte e um. O guia de configuração: “todos os IPs atribuídos por meio de `IPAddressPool` contribuem para o conjunto de IPs que o MetalLB usa para atribuir IPs aos Services”. Por que esses: precisam estar **dentro** da rede `kind` (senão, ninguém nessa rede perguntaria por eles) e **longe** dos que o Docker distribui aos contêineres, que começam de baixo (`172.18.0.2`, `.3`, `.4`). O final da rede é o lugar mais seguro.
- **`L2Advertisement`** diz **como** eles são anunciados: na camada 2, por ARP. O guia: “para anunciar o IP que sai de um `IPAddressPool`, é preciso associar a ele uma instância de `L2Advertisement`”. Sem este segundo objeto, o MetalLB atribuiria o IP e ninguém responderia por ele.

```text
$ kubectl get ipaddresspool,l2advertisement -n metallb-system
NAME                             AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ipaddresspool.metallb.io/curso   true          false             ["172.18.255.200-172.18.255.220"]

NAME                               IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
l2advertisement.metallb.io/curso   ["curso"]                                  
```

`AUTO ASSIGN true`: o MetalLB pega IPs dessa faixa para qualquer `LoadBalancer` que os peça, sem que o Service precise nomear a faixa.

#### 6.4.5 O primeiro IP

```text
$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.115.79   172.18.255.200   80:30808/TCP   119s
```

`172.18.255.200`, a primeira da faixa. O Service estava quase dois minutos em `<pending>`; ninguém o aplicou de novo. O MetalLB, ao ter uma faixa, procurou os `LoadBalancer` sem IP e deu um a cada um. É de novo o termostato da Lição 0: o estado desejado estava escrito desde 6.2, e assim que houve quem o perseguisse, foi alcançado. O `NodePort` continua sendo `30808`: o IP externo foi montado **por cima** da porta do nó, como diz a documentação.

Quem fez isso e a partir de onde? Dizem os eventos do Service, que em 6.3 estavam vazios:

```text
$ kubectl get events --field-selector involvedObject.name=revisor-publico --sort-by=.lastTimestamp | awk '{$1=""; print}' | sed 's/^ //'
SEEN TYPE REASON OBJECT MESSAGE
Normal IPAllocated service/revisor-publico Assigned IP ["172.18.255.200"]
Normal nodeAssigned service/revisor-publico announcing from node "curso-k8s-l6-worker2" with protocol "layer2"
```

(O `awk` tira a coluna da idade para que caiba; o cabeçalho mantém o nome.) Dois eventos, os dois do MetalLB: `IPAllocated`, do `controller`, que escolheu o IP; e `nodeAssigned`, do `speaker`, que diz de que nó o anuncia: `curso-k8s-l6-worker2`, pela camada 2. Em outra execução o nó pode ser outro. Esse nó é, de agora em diante, o ponto de entrada físico de `172.18.255.200`: se ele cair, outro `speaker` assume o anúncio.

E a prova que importa, de fora:

```text
$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           7ms  200
```

Um endereço estável, na porta 80, sem número estranho, que distribui entre as três réplicas e que continua ali mesmo que os Pods mudem. O que o painel da cena precisava. (Os `…` substituem o token nas saídas publicadas; no terminal vai o conteúdo de `token.txt`, com `-H "Authorization: Bearer $(cat token.txt)"`.)

### 6.5 Por que não o Cloud Provider KIND

Quem procura “LoadBalancer no kind” encontra como primeira resposta a do próprio kind. O [guia de LoadBalancer](https://kind.sigs.k8s.io/docs/user/loadbalancer/) dele recomenda o **Cloud Provider KIND**, e o [guia de Ingress](https://kind.sigs.k8s.io/docs/user/ingress/) diz que, desde a v0.9.0, esse programa “suporta Ingress nativamente” e que a Gateway API “também é suportada nativamente”. É uma ferramenta séria, do mesmo grupo que mantém o kind. Por que este curso não a usa?

Por **onde roda** e **sobre o que atua**. O guia do kind diz: o Cloud Provider KIND “roda como um binário independente na máquina e se conecta ao cluster do kind”, e “exige privilégios para abrir portas no sistema e para se conectar ao *runtime* de contêineres”. O [README](https://github.com/kubernetes-sigs/cloud-provider-kind) dele é mais preciso: “o `cloud-provider-kind` vai monitorar **todos** os clusters do kind”, e o controlador de Gateway API dele “vem ativado por padrão”. O README não descreve nenhuma opção para se limitar a um.

Em um notebook pessoal, com um só cluster, isso não importa. Em uma máquina compartilhada — a de um laboratório, a de uma equipe que roda testes em paralelo, ou a própria, se houver um cluster de outro projeto — importa muito: um processo lançado para esta lição começaria a criar balanceadores de carga, CRDs e uma `GatewayClass` em clusters que não são de quem o lançou, sem que os donos tivessem pedido. Este curso tem uma regra desde a Lição 1: não mexer no que não pertence a quem está fazendo a lição, nem em outro contexto, nem em outro cluster. O Cloud Provider KIND a quebra por design.

O MetalLB e o Envoy Gateway, em contrapartida, são objetos **dentro** do cluster. Instalam-se com `kubectl` no contexto da lição, vivem nos próprios namespaces (`metallb-system`, `envoy-gateway-system`) e desaparecem com `kind delete cluster`. O preço é o que apareceu em 6.1: a faixa de IPs do MetalLB sai da rede `kind`, que é compartilhada, e por isso dois clusters com a mesma faixa não devem rodar ao mesmo tempo. É um preço que se controla com uma verificação de uma linha. O outro não se controla.

### 6.6 Envoy Gateway e Gateway API: a plataforma do ponto de entrada

#### 6.6.1 As três peças da Gateway API

Um `LoadBalancer` é uma entrada por Service: cada um com o IP dele. Se amanhã forem publicados cinco serviços, serão cinco IPs, e nenhum sabe nada de HTTP: não pode decidir pelo caminho, nem pelo nome do site, nem colocar uma criptografia comum. A Gateway API resolve isso com **um** ponto de entrada que entende HTTP e regras que dizem o que entra e para onde vai. A [página da Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) do Kubernetes descreve as três peças:

| Peça | O que é, segundo a documentação | Neste curso |
|---|---|---|
| `GatewayClass` | “define um conjunto de gateways com uma configuração comum, gerenciados por um controlador que implementa a classe” | `eg`, a do Envoy Gateway |
| `Gateway` | “define uma instância de infraestrutura que manipula tráfego, como um balanceador de carga em nuvem” | `revisor`: escuta HTTP na 80 |
| `HTTPRoute` | “define regras específicas de HTTP para levar tráfego de um *listener* do Gateway a uma representação de *endpoints* de rede”, que “muitas vezes são representados por um Service” | `revisor`: tudo o que chegar vai para o Service `revisor` |

A mesma página explica por que são três e não um: a Gateway API é “orientada a papéis”. A `GatewayClass` é do **provedor de infraestrutura**; o `Gateway`, do **operador do cluster**, que cuida de “políticas, acesso à rede e permissões”; a `HTTPRoute`, do **desenvolvedor da aplicação**, que cuida do Service dela. Neste cluster, uma só pessoa acumula os três papéis, mas os arquivos já ficam separados assim: `infra/gatewayclass.yaml` é plataforma, `gateway.yaml` é projeto.

#### 6.6.2 Instalar com `--server-side`, e por quê

O Envoy Gateway traz em um só arquivo os CRDs da Gateway API e os dele. O [guia de instalação](https://gateway.envoyproxy.io/docs/install/install-yaml/) diz: “o manifesto `install.yaml` inclui os CRDs da Gateway API e os CRDs do Envoy Gateway”. Este curso o envolve da mesma forma que o MetalLB. É um **programa**: `infra/envoy-gateway/kustomization.yaml`.

```yaml
# Envoy Gateway v1.9.2, instalado SOLO en este clúster. Trae los CRD de Gateway API
# (bundle v1.6.1) y los suyos. Su guía oficial lo instala con server-side apply:
#   kubectl apply --server-side -k infra/envoy-gateway
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/envoyproxy/gateway/releases/download/v1.9.2/install.yaml
```

O guia oficial o instala com `kubectl apply --server-side`. O que acontece sem essa flag? Dá para perguntar sem mudar nada, com `--dry-run=server`, que envia tudo ao `kube-apiserver` para ser validado e não guarda nada:

```text
$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -c 'Too long'
3

$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -m 1 'Too long' | sed 's/.*\(The CustomResourceDefinition\)/\1/'
Error from server (Invalid): error when creating "infra/envoy-gateway": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(Em `correr.salida.txt`, embaixo de cada um desses dois comandos aparece `[código de salida: 1]`. É o código do `kubectl apply`, cuja tentativa o `kube-apiserver` rejeitou. O script roda com `pipefail`, que faz um pipeline falhar se qualquer um dos comandos falhar. No terminal, sem `pipefail`, o pipeline devolve o código do `grep`, que é 0, e essa linha não aparece.) Três CRDs rejeitados, com o mesmo motivo: “`metadata.annotations`: muito longo; não pode passar de 262144 bytes”. A causa está em como funciona o `apply` de sempre, o que foi usado desde a Lição 2. Esse `apply` guarda em cada objeto uma anotação, `kubectl.kubernetes.io/last-applied-configuration`, com **uma cópia completa** do manifesto aplicado, para poder calcular a diferença na próxima vez. Com um Deployment, essa cópia pesa alguns quilobytes. Com o CRD de `EnvoyProxy`, cujo esquema descreve centenas de campos, a cópia passa do limite de 256 KiB que o `kube-apiserver` aceita para todas as anotações de um objeto.

O `--server-side` muda quem faz a contabilidade. A [documentação do *server-side apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) explica: ele oferece “um mecanismo para que o plano de controle do cluster acompanhe as mudanças nos campos de um objeto”, e o compara com a anotação do `kubectl`: em vez de guardar “o último estado aplicado”, registra quais campos cada um gerencia, em `metadata.managedFields`. Sem cópia do manifesto, sem anotação gigante.

```text
$ kubectl apply --server-side -k infra/envoy-gateway | tail -4
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl get crd -o name | grep -c gateway.networking.k8s.io
10

$ kubectl get crd -o name | grep -c gateway.envoyproxy.io
8
```

Cada linha diz `serverside-applied` em vez de `created`. As quatro últimas já contam a história desta lição: uma política de validação de admissão (`safe-upgrades`, “atualizações seguras”, pelo nome), um `Job` chamado `certgen` que, pelo nome, gera certificados, e outro *webhook*, desta vez dos que **modificam** objetos (`mutatingwebhookconfiguration`). De novo guardiões. Mas nem todos bloqueiam: este declara `failurePolicy: Ignore`, ou seja, se não responder, o `kube-apiserver` deixa a requisição passar. Qual é qual se lê no manifesto, não se supõe (a execução mostra mais abaixo). Dez CRDs da Gateway API e oito do Envoy Gateway. Há mais, e eles são medidos:

```text
$ kubectl get crd -o name | grep gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io

$ kubectl get crd -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.annotations.gateway\.networking\.k8s\.io/channel} {.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}{end}' | grep 'gateway.networking.k8s.io ' | column -t
backendtlspolicies.gateway.networking.k8s.io  experimental  v1.6.1
gatewayclasses.gateway.networking.k8s.io      experimental  v1.6.1
gateways.gateway.networking.k8s.io            experimental  v1.6.1
grpcroutes.gateway.networking.k8s.io          experimental  v1.6.1
httproutes.gateway.networking.k8s.io          experimental  v1.6.1
listenersets.gateway.networking.k8s.io        experimental  v1.6.1
referencegrants.gateway.networking.k8s.io     experimental  v1.6.1
tcproutes.gateway.networking.k8s.io           experimental  v1.6.1
tlsroutes.gateway.networking.k8s.io           experimental  v1.6.1
udproutes.gateway.networking.k8s.io           experimental  v1.6.1

$ kubectl get mutatingwebhookconfiguration envoy-gateway-topology-injector.envoy-gateway-system -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Ignore
```

Três coisas se leem ali. Dez CRDs de `gateway.networking.k8s.io`, **todos** do canal `experimental` e do pacote `v1.6.1` da Gateway API (o canal *standard* seria só o estável; o experimental traz, além disso, campos e versões em teste). Mais três CRDs, do grupo `gateway.networking.x-k8s.io`, que o `grep -c` de cima não contava: o `x` é de experimental. E um *webhook* de mutação com `failurePolicy: Ignore`. O `column -t` apenas alinha a tabela. No total, então: dez mais três da Gateway API e oito do Envoy Gateway.

#### 6.6.3 Esperar de novo, e a classe

Antes de usar os tipos novos, espera-se que estejam **estabelecidos** (`Established`), e antes de pedir um ponto de entrada, que o controlador esteja disponível:

```text
$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met
```

`Established` é a condição que o `kube-apiserver` coloca em um CRD quando ele já serve o tipo novo. Um CRD recém-criado pode demorar um momento para chegar a esse estado; esperar pela condição é perguntar ao cluster em vez de adivinhar. Aqui já estavam: `condition met` de imediato. O segundo `wait` é igual ao usado com o `controller` do MetalLB, agora com o controlador do Envoy Gateway.

Agora a classe. É um **programa**: `infra/gatewayclass.yaml`.

```yaml
# gatewayclass.yaml — «eg»: la clase de puerta que atiende Envoy Gateway.
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

Uma `GatewayClass` é curta: um nome, `eg`, e o controlador que a atende. O `controllerName` não é enfeite: é a assinatura com a qual o controlador do Envoy Gateway reconhece as classes que lhe cabem. Se fosse escrito outro, a classe existiria e ninguém a aceitaria.

```text
$ kubectl apply -f infra/gatewayclass.yaml
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl get gatewayclass
NAME   CONTROLLER                                      ACCEPTED   AGE
eg     gateway.envoyproxy.io/gatewayclass-controller   True       0s

$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME                 SHORTNAMES   APIVERSION                     NAMESPACED   KIND
backendtlspolicies   btlspolicy   gateway.networking.k8s.io/v1   true         BackendTLSPolicy
gatewayclasses       gc           gateway.networking.k8s.io/v1   false        GatewayClass
gateways             gtw          gateway.networking.k8s.io/v1   true         Gateway
grpcroutes                        gateway.networking.k8s.io/v1   true         GRPCRoute
httproutes                        gateway.networking.k8s.io/v1   true         HTTPRoute
listenersets         lset         gateway.networking.k8s.io/v1   true         ListenerSet
referencegrants      refgrant     gateway.networking.k8s.io/v1   true         ReferenceGrant
tcproutes                         gateway.networking.k8s.io/v1   true         TCPRoute
tlsroutes                         gateway.networking.k8s.io/v1   true         TLSRoute
udproutes                         gateway.networking.k8s.io/v1   true         UDPRoute
```

Entre o `apply` e o `get` vai um terceiro `wait`, desta vez pela condição `Accepted` da classe: o controlador demora alguns segundos para reconhecê-la, e sem essa espera o `get` poderia mostrar `ACCEPTED Unknown`. `ACCEPTED True`: o Envoy Gateway reconheceu a classe como própria. E o mesmo `api-resources` que em 6.2 dava só os cabeçalhos agora dá dez tipos, que o `api-resources` mostra em `v1`. Atenção com essa palavra: é a versão **preferida** que o cluster serve, não uma garantia de que tudo seja estável. O `install.yaml` do Envoy Gateway instala os CRDs do canal **experimental** da Gateway API (a anotação `gateway.networking.k8s.io/channel: experimental` de cada CRD diz isso, e a execução a lê acima), que traz, além do estável, campos e versões em teste, e três tipos a mais do grupo `gateway.networking.x-k8s.io`. Os três que esta lição usa, `GatewayClass`, `Gateway` e `HTTPRoute`, são estáveis. Em um cluster real, decide-se de propósito qual canal instalar. Hoje são usados três. `GRPCRoute`, `TCPRoute` e `UDPRoute` são rotas para outros protocolos; `TLSRoute` e `BackendTLSPolicy` são, respectivamente, deixar a criptografia passar sem abri-la e criptografar o trecho do ponto de entrada até o Service, coisas que esta lição não faz. `ReferenceGrant` é a permissão que o dono de um namespace dá para que algo de **outro** namespace aponte para os objetos dele: por exemplo, uma rota que manda tráfego para um Service alheio, ou um Gateway que usa um certificado guardado em um `Secret` alheio. Neste curso a rota e o Service vivem sempre no mesmo namespace, então não será necessário. Que uma rota se pendure em um Gateway de **outro** namespace não se decide com `ReferenceGrant`, e sim com o campo `allowedRoutes` do *listener* do Gateway; a [documentação do Gateway](https://kubernetes.io/docs/concepts/services-networking/gateway/) diz assim: “por padrão, um Gateway só aceita rotas do mesmo namespace”. Repare na coluna `NAMESPACED`: `gatewayclasses` é `false`, porque uma classe vale para o cluster inteiro. É plataforma.

### 6.7 O ponto de entrada do `revisor`

#### 6.7.1 O manifesto

É um **programa**: `gateway.yaml`.

```yaml
# gateway.yaml — Lección 6: Gateway API, la sucesora de Ingress.
# La puerta (Gateway «revisor», clase «eg» de Envoy Gateway) recibe una IP de
# MetalLB; la ruta (HTTPRoute) manda todo al Service revisor. Solo HTTP: el
# cifrado en tránsito es lo que la lección dice que falta.
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: revisor
spec:
  gatewayClassName: eg
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisor
      port: 80
```

Dois objetos em um arquivo, separados por `---`. Lêem-se assim:

- **O `Gateway`** pede um ponto de entrada da classe `eg` com um *listener* (um “ouvinte”): `http`, protocolo `HTTP`, porta `80`. Não diz nada de IP: o IP é pedido pelo Envoy Gateway a quem o distribui, que neste cluster é o MetalLB.
- **A `HTTPRoute`** se pendura nesse ponto de entrada com `parentRefs: [revisor]` e tem uma regra: o que começar com `/` (`PathPrefix`), ou seja, tudo, vai para o Service `revisor` na porta `80`. Repare no destino: o `revisor` `ClusterIP` da Lição 3, não o `revisor-publico`. O ponto de entrada entra no cluster e dali usa o Service de dentro, com o EndpointSlice e a distribuição dele.

A [referência do `HTTPRoute`](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) diz ainda que, se `matches` não for escrito, o valor padrão é justamente este, um prefixo `/`, “que tem o efeito de corresponder a toda requisição HTTP”. O curso o escreve mesmo assim, pela mesma razão que escreveu `type: ClusterIP`: para que a decisão “tudo passa” fique à vista. O Exercício 2 a muda.

#### 6.7.2 Aplicar, agora sim

O mesmo comando de 6.2, com a plataforma no lugar:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bmkbmd25cg unchanged
service/prueba unchanged
service/revisor unchanged
service/revisor-publico unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Sete `unchanged` e dois `created`. Nada reiniciou: o `Secret` conservou o nome porque o `token.txt` é o mesmo de 6.2, e o Deployment não teve motivo para um *rollout*. O `apply` é declarativo, e aplicá-lo duas vezes é seguro: o que já estava, fica. Por isso a correção do erro de ordem não foi “apagar tudo e começar de novo”, e sim instalar o que faltava e aplicar o mesmo de novo.

O `wait` espera a condição `Programmed` do Gateway: que o controlador já tenha configurado a infraestrutura que o atende.

```text
$ kubectl get gateway,httproute
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.18.255.201   True         113s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               113s

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
```

O Gateway tem endereço, `172.18.255.201`, o segundo da faixa do MetalLB (o primeiro já era do `revisor-publico`), e `PROGRAMMED True`. A rota tem duas condições, que serão usadas em “O erro que a gente vai ver”: `Accepted=True`, o ponto de entrada a aceitou como própria; e `ResolvedRefs=True`, tudo o que ela nomeia (o Service `revisor` e a porta dele) existe.

#### 6.7.3 Quem atende o ponto de entrada

Um `Gateway` é uma declaração. Alguém precisa torná-la real:

```text
$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-default-revisor-4e6f5d7f-55b49857bd-25dqk   2/2     Running   0          113s
pod/envoy-gateway-5fc4949dcb-f8jss                    1/1     Running   0          5m44s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
service/envoy-gateway                    ClusterIP      10.96.233.233   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   5m45s
```

Dois Pods. `envoy-gateway` é o **controlador**: lê os `Gateway` e as `HTTPRoute` e traduz. `envoy-default-revisor-…` é o **proxy**, o Envoy que de fato recebe as requisições; o nome dele junta o namespace do Gateway (`default`) e o nome do Gateway (`revisor`). Foi criado pelo controlador quando o Gateway apareceu, com um Service próprio **do tipo `LoadBalancer`**, e é esse que recebeu `172.18.255.201` do MetalLB. As duas plataformas desta lição trabalham juntas sem se conhecer: o Envoy Gateway pede um `LoadBalancer`, o MetalLB o dá.

Todos os `LoadBalancer` do cluster, vistos juntos:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
default                revisor-publico                  LoadBalancer   10.96.115.79    172.18.255.200   80:30808/TCP                                       8m21s
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
```

Dois pontos de entrada para o `revisor`: o direto, `.200`, e o nomeado, `.201`. Convém guardar esta tabela para o hábito de segurança.

#### 6.7.4 Entrar

```text
$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados
401

$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|server|content-type)"
HTTP/1.1 200 OK
content-type: application/json
```

As três respostas que importam: `/salud` responde, `/api/estados` com o token dá a tabela, e sem token dá `401`. Esse `401` quem dá é o **`revisor`**, não o ponto de entrada: o Gateway deixa tudo passar e o `revisor` continua exigindo o token, como desde a Lição 4. O log do `revisor` confirma:

```text
$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /api/estados'
[pod/revisor-5674f7c4cc-bhbvp/revisor] revisor: GET /api/estados 200 17ms
[pod/revisor-5674f7c4cc-pbc9f/revisor] revisor: GET /api/estados 200 8ms
[pod/revisor-5674f7c4cc-w7hgf/revisor] revisor: GET /api/estados 401 1ms
```

(O `kubectl logs -l` junta os logs das três réplicas, agrupados por Pod e não por hora, então a ordem das linhas não é a das requisições.) Até esse momento houve três requisições a `/api/estados`: a de 6.4.5 pelo `.200`, a de cima com token pelo ponto de entrada e a de cima sem token. As três aparecem, e o que se pode afirmar é o que o `401` diz: foi escrito por um `revisor` no log dele, ou seja, quem o deu foi ele e não o ponto de entrada. Qual réplica atendeu cada uma não se deduz desta saída; de distribuir se encarrega o de sempre, o Service `revisor`, não o ponto de entrada.

O último `curl` de cima pediu os cabeçalhos com `-i`: `HTTP/1.1 200 OK`. Mais um dado, que a seção do hábito de segurança retoma: é HTTP/1.1 na porta 80, sem criptografia.

### 6.8 `Ingress`, a API congelada, e por que não o `ingress-nginx`

O `Ingress` aparece em quase todo tutorial de Kubernetes anterior a 2024. É o avô do que acabou de ser feito: um objeto que diz “tal caminho vai para tal Service”, atendido por um controlador. Continua existindo, e a [documentação do Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) diz o estado dele com todas as letras: “a API do Ingress está congelada”; “não está mais sendo desenvolvida e não receberá mais mudanças nem atualizações”. E a recomendação: “o projeto Kubernetes recomenda usar o Gateway em vez do Ingress”. Atenção ao que **não** diz: não está obsoleta no sentido de que vão removê-la. A mesma página esclarece que é uma API estável, sujeita às garantias das APIs estáveis, e que o projeto “não tem planos de remover o Ingress do Kubernetes”. Congelada quer dizer: funciona, não cresce. O que lhe falta (rotas para outros protocolos, papéis separados, regras mais finas) não vai chegar. A Gateway API nasceu para isso.

O `ingress-nginx` é outra coisa: não uma API, e sim **um controlador** de Ingress, o mais popular durante anos, o da segunda proposta da cena. Em novembro de 2025, o [blog do Kubernetes](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) anunciou a aposentadoria dele: “em março de 2026, a manutenção do Ingress NGINX será interrompida e o projeto será aposentado. Depois dessa data, não haverá mais versões, nem correções de bugs, nem atualizações para resolver vulnerabilidades de segurança que forem descobertas”. As instalações existentes continuam funcionando e os artefatos continuam disponíveis para download, diz o mesmo anúncio. Por isso o tutorial de dois anos atrás continua “funcionando” esta tarde. Mas um componente que recebe tráfego de fora e já não recebe patches de segurança é exatamente o que não se instala hoje. O anúncio recomenda migrar para a Gateway API ou para outro controlador.

Três nomes, três coisas distintas:

| Nome | O que é | Estado |
|---|---|---|
| `Ingress` | uma API do Kubernetes | congelada: funciona, não cresce |
| `ingress-nginx` | um controlador que atende `Ingress` | aposentado desde março de 2026: sem patches |
| Gateway API | a API sucessora do `Ingress` | vigente; é a que este curso usa |

O Exercício 3 deixa ver um `Ingress` neste cluster, e o que acontece com ele quando ninguém o atende.

### 6.9 A ordem: plataforma, espera, projeto

Junte o que foi visto. Em 6.2, o projeto antes da plataforma: `no matches for kind`. Em 6.4, a faixa antes do guardião: `failed calling webhook … connection refused`. Em 6.6, o projeto também não teria podido pedir o Gateway antes que existisse a classe `eg`. Nos três casos, o arquivo estava certo. O que estava errado era o momento.

Assim se sobe o que esta lição monta, a partir de um cluster vazio, em três passos. Não é um trecho escrito de memória: é o programa `levantar.sh`, e foi executado de verdade. O `correr.sh` apaga o cluster dos exercícios, cria **outro** igual, com as duas imagens carregadas e sem um único recurso personalizado (`kubectl get crd` dá `No resources found`), e executa o `levantar.sh` sem corrigir nada manualmente:

```bash
#!/usr/bin/env bash
# levantar.sh — Lección 6, sección 6.9: la plataforma y el proyecto, desde un
# clúster recién creado, en tres pasos y en este orden:
#   1. la plataforma: los tipos nuevos (CRD), sus controladores y sus guardianes;
#   2. la espera: tipos establecidos y controladores listos (kubectl wait);
#   3. la configuración de la plataforma (rango y clase) y después el proyecto.
#
# Uso, desde esta carpeta y con el clúster curso-k8s-l6 recién creado, las dos
# imágenes cargadas y token.txt generado:   ./levantar.sh
#
# 🔴 Antes de CADA cambio, ctx comprueba que el contexto activo es
# kind-curso-k8s-l6 y, si no, el guion se detiene: MetalLB y Envoy Gateway crean
# objetos que valen para todo el clúster, y aplicarlos en otro sería instalarlos
# en el clúster de otra persona.
set -euo pipefail
cd "$(dirname "$0")"

ctx() { [ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l6 ] || { echo "contexto equivocado: no sigo" >&2; return 1; }; }
# paso CADENA → comprueba el contexto, imprime «$ CADENA» y la corre. Si falla, se detiene.
paso() { ctx; printf '\n$ %s\n' "$*"; eval "$@"; }

[ -f token.txt ] || { echo "falta token.txt: (umask 077; openssl rand -hex 16 > token.txt)" >&2; exit 1; }

echo "## Paso 1: la plataforma"
paso "kubectl apply -k infra/metallb"
paso "kubectl apply --server-side -k infra/envoy-gateway"

echo
echo "## Paso 2: la espera"
paso "kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s"
paso "kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s"
paso "kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
paso "kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s"

echo
echo "## Paso 3: la configuración de la plataforma, y el proyecto"
paso "kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml"
paso "kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s"
paso "kubectl apply -k ."
paso "kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s"
```

A função `paso` faz três coisas: confere o contexto com `ctx` (e para se não for `kind-curso-k8s-l6`: o MetalLB e o Envoy Gateway criam objetos que valem para o cluster inteiro), imprime o comando com `$` e o executa. Com `set -euo pipefail`, o primeiro erro interrompe o script, então uma execução sem interrupções é a prova de que a ordem funciona.

A faixa e a classe vão no **passo 3** e não no 1 pelo que foi visto: a faixa precisa que o *webhook* do MetalLB responda (6.4.2) e a classe precisa que o CRD dela esteja estabelecido (6.6.3). O README do curso os chama de “três passos” embora o bloco tenha mais de três comandos: os passos são de **ordem**, não de número de comandos. (Na Lição 10, os dois `apply` de plataforma do passo 1 se juntam em um.) Esta é a saída dessa execução:

```text
$ kubectl get crd
No resources found

$ ./levantar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb
namespace/metallb-system created
customresourcedefinition.apiextensions.k8s.io/bfdprofiles.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgpadvertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/bgppeers.metallb.io created
customresourcedefinition.apiextensions.k8s.io/communities.metallb.io created
customresourcedefinition.apiextensions.k8s.io/configurationstates.metallb.io created
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io created
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicebgpstatuses.metallb.io created
customresourcedefinition.apiextensions.k8s.io/servicel2statuses.metallb.io created
serviceaccount/controller created
serviceaccount/speaker created
role.rbac.authorization.k8s.io/controller created
role.rbac.authorization.k8s.io/pod-lister created
clusterrole.rbac.authorization.k8s.io/metallb-system:controller created
clusterrole.rbac.authorization.k8s.io/metallb-system:speaker created
rolebinding.rbac.authorization.k8s.io/controller created
rolebinding.rbac.authorization.k8s.io/pod-lister created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:controller created
clusterrolebinding.rbac.authorization.k8s.io/metallb-system:speaker created
configmap/metallb-excludel2 created
secret/metallb-webhook-cert created
service/metallb-webhook-service created
deployment.apps/controller created
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway
namespace/envoy-gateway-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/clienttrafficpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyextensionpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoypatchpolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/envoyproxies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutefilters.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/listenersets.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/securitypolicies.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tcproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/udproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackends.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xbackendtrafficpolicies.gateway.networking.x-k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/xmeshes.gateway.networking.x-k8s.io serverside-applied
serviceaccount/eg-gateway-helm-certgen serverside-applied
serviceaccount/envoy-gateway serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
role.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-role serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrole.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-role serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-infra-manager serverside-applied
rolebinding.rbac.authorization.k8s.io/eg-gateway-helm-leader-election-rolebinding serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-certgen:envoy-gateway-system serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/eg-gateway-helm-envoy-gateway-rolebinding serverside-applied
configmap/envoy-gateway-config serverside-applied
service/envoy-gateway serverside-applied
deployment.apps/envoy-gateway serverside-applied
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
job.batch/eg-gateway-helm-certgen serverside-applied
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bmkbmd25cg created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
(levantar.sh tardó 266 s)
```

Leia-a por passos. Passo 1: um `created` para cada objeto do MetalLB e um `serverside-applied` para cada objeto do Envoy Gateway; o segundo manda de uma vez os dez mais três CRDs da Gateway API e os oito do Envoy. Passo 2: cinco esperas, e todas terminam em `condition met` ou `successfully rolled out`; o `speaker` vai de 0 a 3 pods disponíveis. Passo 3: a faixa e a classe são criadas juntas, a classe é esperada até `Accepted`, o projeto é criado completo (nove `created`, sem um único `no matches for kind`) e o Gateway chega a `Programmed`. Nenhum erro, e nenhum `sleep`. Depois, o `correr.sh` confere o que importa:

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         82s

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.165.26   172.18.255.200   80:31214/TCP   82s
(espera: la puerta ya contesta 200 en http://172.18.255.201/salud)

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}


$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

O Gateway e o `LoadBalancer` receberam de novo `172.18.255.201` e `.200`, nessa ordem, o ponto de entrada responde `/salud` e a tabela do relatório, e o `.200` também. (O Service deste cluster novo traz outro `NodePort`, `31214`, e o Gateway levou `82s` para existir, porque o `kubectl apply` e as esperas do passo 3 rodam antes deste `get`.) Com isso, a meta da lição está cumprida: um cluster novo, três passos, nada corrigido manualmente.

Três ideias que vão reaparecer na Lição 10, quando o projeto inteiro subir com dois `apply -k` e uma espera:

- **A plataforma se instala uma vez por cluster; o projeto, toda vez que muda.** O MetalLB e o Envoy Gateway não são do `revisor`: no dia em que um segundo serviço for publicado, ele usará a mesma classe `eg` e a mesma faixa.
- **A espera não é um `sleep`.** Um `sleep 30` funciona na máquina de quem o escreveu e falha em uma mais lenta. O `kubectl wait` pergunta pela condição e falha com clareza se ela não chega no tempo dado.
- **A ordem não se esconde.** Se ela for automatizada (um script, um passo de um *pipeline*), os três passos continuam ali, com nome, cada um com a verificação de contexto (`ctx`). Um script que “tenta de novo até passar” esconde a causa; um que espera a condição a nomeia.

## O erro que a gente vai ver

O erro desta lição é o mais comum com a Gateway API, e se parece com o seletor mal escrito da Lição 3: uma rota que aponta para um Service que não existe. Ele é provocado com `fig06_01.ruta-mala.yaml`, um **programa** que falha de propósito: a mesma `HTTPRoute`, com uma letra a menos no destino.

```yaml
# fig06_01.ruta-mala.yaml — FALLA A PROPÓSITO: la misma ruta del revisor con una
# letra de menos en el Service de destino (revisr). El Gateway la acepta, pero no
# encuentra a quién mandarle el tráfico: ResolvedRefs=False BackendNotFound, y la
# puerta responde 500. Se corrige volviendo a aplicar la kustomization (apply -k .).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: revisr
      port: 80
```

```text
$ kubectl apply -f fig06_01.ruta-mala.yaml
httproute.gateway.networking.k8s.io/revisor configured
```

`configured`, sem reclamações. Como no seletor da Lição 3, o `kube-apiserver` não tem como saber que se queria escrever `revisor`: `revisr` é um nome válido. Interpreta-se em ordem.

**Primeiro, o sintoma**, de fora:

```text
$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|content-length)"
HTTP/1.1 500 Internal Server Error
content-length: 0
```

`500` e corpo vazio. Repare no que **não** é. Não é um código do `curl` (6, 7 ou 28): a conexão foi feita, alguém respondeu. E não é o `revisor`: o `revisor` nunca responde com corpo vazio. Quem respondeu foi o Envoy, o ponto de entrada, dizendo “não tenho para onde enviar isto”. A [especificação da Gateway API v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/) exige assim: se todas as referências de uma regra são inválidas e a regra não tem filtros, “todo o tráfego que corresponder a esta regra DEVE receber um código 500”.

**Segundo, o ponto de entrada.** Se respondeu, ele está bem:

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         2m1s
```

`PROGRAMMED True`, mesmo endereço. O problema está atrás.

**Terceiro, as condições da rota.** É o passo decisivo, o equivalente da coluna `ENDPOINTS` da Lição 3:

```text
$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=False BackendNotFound

$ kubectl get httproute revisor -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].message}{"\n"}'
Failed to process route rule 0 backendRef 0: service default/revisr not found.
```

Duas condições, e aqui está a armadilha: `Accepted=True`. O ponto de entrada aceitou a rota. Quem olhar só essa condição, ou só o `kubectl get httproute` (que não mostra nenhuma), conclui que está tudo bem. A que diz a verdade é a segunda: `ResolvedRefs=False`, motivo `BackendNotFound`. E a mensagem, em inglês, não deixa dúvidas: “falhou ao processar a regra 0, referência 0: o Service `default/revisr` não foi encontrado”. (`.status.parents[0]` é o estado da rota em relação ao primeiro ponto de entrada dela; uma rota pode se pendurar em vários, e cada um coloca nela as próprias condições.)

**Quarto, a confirmação:**

```text
$ kubectl get service revisr
Error from server (NotFound): services "revisr" not found
[código de salida: 1]
```

**A correção** é a causa, não o ponto de entrada: aplicar de novo o arquivo certo, que aqui é a kustomization completa.

```text
$ kubectl apply -k . | grep httproute
httproute.gateway.networking.k8s.io/revisor configured

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}
```

Como na Lição 3, primeiro se olha se o estado está bem (`ResolvedRefs=True`) e depois se testa. Entre aplicar a rota e o Envoy receber a configuração nova passa um momento: se o primeiro `curl` ainda der o código de antes (`200` depois da rota ruim, `500` depois da boa), é só repeti-lo. O `correr.sh` espera que o ponto de entrada responda o código esperado antes de mostrar o `curl`, e anota isso na saída como `(espera: la puerta ya contesta 500 …)`.

**A ordem, para qualquer ponto de entrada que não responde bem:**

1. O que o `curl` devolve? Um código do `curl` (7, 28) é a rede ou o IP; um código HTTP (`404`, `500`) quer dizer que o ponto de entrada respondeu.
2. O Gateway tem `ADDRESS` e `PROGRAMMED True`? Se não tem endereço, olhe o MetalLB e a faixa dele.
3. A rota tem `Accepted=True` **e** `ResolvedRefs=True`? Leia as duas, e o `message` da que estiver em `False`.
4. Se tudo isso está bem, desça um andar: o Service de destino e o EndpointSlice dele, com a ordem da Lição 3.

## O hábito de segurança da lição: expõe-se o mínimo, por um ponto de entrada nomeado, e diz-se o que falta

A tabela de hábitos do curso atribui três coisas a esta lição. Conferem-se com o cluster à frente.

**O que ficou exposto.** Tudo o que recebe tráfego de fora do cluster:

```text
$ kubectl get services -A -o custom-columns='ESPACIO:.metadata.namespace,NOMBRE:.metadata.name,TIPO:.spec.type,IP-EXTERNA:.status.loadBalancer.ingress[0].ip,NODEPORT:.spec.ports[*].nodePort' | grep -E 'ESPACIO|LoadBalancer|NodePort'
ESPACIO                NOMBRE                           TIPO           IP-EXTERNA       NODEPORT
default                revisor-publico                  LoadBalancer   172.18.255.200   30808
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   172.18.255.201   30581
```

Escrito como inventário, que é como se deve poder dizer em voz alta:

| Ponto de entrada | Endereço | O que deixa passar | Quem decide |
|---|---|---|---|
| `revisor-publico` | `172.18.255.200:80` | **todo** o `revisor`, sem regras | ninguém: é um `LoadBalancer` direto |
| o `NodePort` dele | `30808` em **cada** nó | o mesmo | ninguém |
| o Gateway `revisor` | `172.18.255.201:80` | o que a `HTTPRoute` disser | a rota, um arquivo versionado |
| o `NodePort` dele | `30581` em cada nó | o mesmo que o Gateway | a rota |

Hoje há **dois** pontos de entrada para o mesmo serviço, e isso é uma lição em si: o direto ignora qualquer regra colocada no nomeado. O Exercício 2 mede isso: quando a rota do Gateway só deixa passar `/salud`, o `.200` continua entregando o relatório completo. Por isso “um ponto de entrada nomeado” é o hábito, e por isso a Lição 7 retira o `revisor-publico` e deixa o Gateway como a única entrada. Os `NodePort` continuam ali pela razão de 6.3.3; em um cluster real, o normal é que a rede dos nós não seja alcançável de fora, e que um firewall garanta isso.

**O que não ficou exposto.** Os nós do kind continuam sem publicar nada para a máquina, exceto a porta da API:

```text
$ docker port curso-k8s-l6-control-plane
6443/tcp -> 127.0.0.1:59736

$ docker port curso-k8s-l6-worker
```

E a partir do terminal, no Mac das execuções, o IP do Gateway não existe:

```text
$ curl -s -m 3 http://172.18.255.201/salud
[código de salida: 28]
```

Este `curl` foi executado, sim, no terminal do Mac, não no contêiner. Código 28: acabou o tempo. A rede `kind` vive dentro da máquina virtual do Colima, e o Mac não tem rota até ela. No Linux Mint é diferente: o Docker conecta a máquina à rede `kind`, então ali o `.201` deveria responder a partir do terminal. Outro computador da rede não a alcança: com as regras que o Docker aplica por padrão (desde o Docker Engine 28, que bloqueia o acesso por roteamento direto às redes dos contêineres), a rede `kind` só é visível a partir da própria máquina. Mas “a própria máquina” inclui todos os usuários dela: em uma máquina compartilhada, qualquer um que tenha uma sessão nela pode pedir o relatório ao `.200` ou ao `.201`, ou aos `NodePort` dos três nós, e quem tiver `root` pode ler o token que viaja sem criptografia (por exemplo, olhando a bridge do Docker com `tcpdump`). Isso é o que este laboratório publica: pouco, e só para dentro da máquina, mas não é “ninguém”.

**O que falta: a criptografia.**

```text
$ curl -s -m 5 https://172.18.255.201/salud
[código de salida: 7]

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados -H 'Authorization: Bearer token-inventado'
401
```

Por `https`, código 7: ninguém escuta na 443, porque o Gateway só tem um *listener* `HTTP` na 80. E o segundo comando lembra o que viaja por esse ponto de entrada: o token do `revisor`, em um cabeçalho, **em texto puro**. Qualquer um que possa olhar a rede entre o cliente e o ponto de entrada o lê. O `revisor` rejeita o token inventado (`401`), mas não pode fazer nada contra alguém que copiou o verdadeiro. A peça que falta é um segundo *listener* no Gateway, com `protocol: HTTPS`, porta 443 e um `tls.certificateRefs` que aponte para um `Secret` com o certificado. A `HTTPRoute` não muda. (`TLSRoute` e `BackendTLSPolicy`, da lista de 6.6.3, são outras coisas: deixar a criptografia passar sem abri-la e criptografar o trecho do ponto de entrada até o Service.) Este curso não coloca isso porque um certificado de verdade precisa de um nome de domínio de verdade, que um laboratório no kind não tem. Mas diz, que é o hábito: **um ponto de entrada sem criptografia é publicado sabendo que não a tem**, e em um cluster real não se publica assim. A Lição 10 coloca isso na lista do que falta a este projeto para estar pronto para produção.

## O que se faz errado

**Mudar um Service para `NodePort` “para que o vejam”.** Abre uma porta aleatória em todos os nós, sem nome e sem regras. É a primeira proposta da cena.

**Esquecer que todo `LoadBalancer` é também um `NodePort`.** Mesmo que o IP externo nunca chegue, a porta do nó já está aberta (6.3.3).

**Instalar o `ingress-nginx` porque um tutorial manda.** Sem patches de segurança desde março de 2026. E o `Ingress`, a API, está congelada: o que é novo se escreve com a Gateway API.

**Rodar o Cloud Provider KIND em uma máquina compartilhada.** Ele monitora todos os clusters do kind da máquina, não só o próprio.

**Aplicar o projeto antes da plataforma, e “consertar” repetindo o comando até passar.** Funciona às vezes e esconde a causa. Instala-se a plataforma, espera-se a condição com `kubectl wait` e depois aplica-se o projeto.

**Esperar com `sleep`.** Um número de segundos que basta em uma máquina não basta em outra. Espera-se a condição, com `--timeout`.

**Instalar o Envoy Gateway sem `--server-side`.** Três dos CRDs dele não cabem na anotação do `apply` de sempre.

**Olhar só `Accepted` em uma rota.** `Accepted=True` com `ResolvedRefs=False` é uma rota aceita que não leva a lugar nenhum. Leem-se as duas condições.

**Escolher a faixa do MetalLB ao acaso.** Ela precisa cair na rede `kind`, longe dos IPs dos nós, e não se repetir em dois clusters vivos ao mesmo tempo.

**Deixar dois pontos de entrada para o mesmo serviço.** O que não tem regras ignora as regras do outro (Exercício 2).

**Publicar com HTTP puro sem dizer.** O token viaja legível. Se um laboratório não pode colocar criptografia, pelo menos escreve isso na lista de pendências.

## Exercícios

Os três primeiros são executados no cluster da lição, em ordem e a partir do estado em que ficou depois de corrigir o erro. Antes de cada exercício, `kubectl config current-context` deve dizer `kind-curso-k8s-l6`. O `correr.sh` os executa igualmente, e a saída está em `correr.salida.txt`. **Antes** de rodar cada um, anote no [diário de bordo](bitacora.md) o que se espera que aconteça. O quarto é escrito com as próprias palavras.

### Exercício 1 — Soltar um endereço e pedi-lo de novo

Apague o Service `revisor-publico` com `kubectl delete service revisor-publico`. Preveja: o que responde `curl -s -m 3 http://172.18.255.200/salud` a partir do cliente de fora? Que `LoadBalancer` ficam no cluster? Agora aplique de novo a kustomization com `kubectl apply -k .`: que IP o Service novo recebe, o `.200` que foi liberado ou o `.202`, o seguinte, que nunca foi usado? E o `NodePort` dele, é o mesmo de antes? Confira e explique.

### Exercício 2 — O ponto de entrada, reduzido ao mínimo

`fig06_02.solo-salud.yaml` é a mesma `HTTPRoute` com uma regra mais estreita: só `GET` em `/salud`, exato.

```yaml
# fig06_02.solo-salud.yaml — Ejercicio 2: la ruta del revisor, reducida a lo
# mínimo. Solo deja pasar GET /salud, exacto. Pregunta: ¿qué responde la puerta a
# /api/estados, con token y sin token? Se deshace con apply -k . (gateway.yaml).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: revisor
spec:
  parentRefs:
  - name: revisor
  rules:
  - matches:
    - path:
        type: Exact
        value: /salud
      method: GET
    backendRefs:
    - name: revisor
      port: 80
```

Aplique-o e preveja o código HTTP de cada uma destas cinco requisições, todas a partir do cliente de fora: `GET /salud` pelo Gateway; `GET /api/estados?formato=tabla` **com** o token, pelo Gateway; `GET /salud/` (com barra no final) pelo Gateway; `POST /salud` pelo Gateway; e `GET /api/estados?formato=tabla` com o token, por `172.18.255.200`. Confira com `curl -s -o /dev/null -w '%{http_code}\n'`. Quem responde cada `404`: o Envoy ou o `revisor`? O que a última resposta diz sobre ter dois pontos de entrada? Ao terminar, aplique de novo `kubectl apply -k .`.

### Exercício 3 — Um `Ingress` que ninguém atende

`fig06_03.ingress.yaml` é um `Ingress` que manda tudo para o Service `revisor`, como a rota de 6.7:

```yaml
# fig06_03.ingress.yaml — Ejercicio 3: un Ingress, la API congelada. El clúster
# lo acepta (la API existe desde siempre), pero en este clúster no hay ningún
# controlador de Ingress. Pregunta: ¿qué dirección recibe? ¿Quién la atiende?
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: revisor
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: revisor
            port:
              name: http
```

Antes de aplicá-lo, rode `kubectl get ingressclass`. Preveja: o cluster aceita o `Ingress` ou o rejeita, como rejeitou o `Gateway` em 6.2? Se aceitar, que endereço ele terá aos 15 segundos? Aplique-o, confira com `kubectl get ingress revisor` e com `kubectl describe ingress revisor`, e explique a diferença em relação a 6.2 em duas frases. Apague-o ao terminar.

### Exercício 4 — Defenda a decisão

Um colega diz: “o guia do kind recomenda o Cloud Provider KIND, é um binário só e dá LoadBalancer, Ingress e Gateway API sem instalar nada no cluster. Para que tanto MetalLB e Envoy Gateway?”. Em no máximo cinco frases, responda a ele: onde o Cloud Provider KIND roda, sobre quais clusters atua, o que aconteceria em uma máquina compartilhada, que preço a solução do curso paga e como esse preço é controlado.

## Soluções

### Solução 1

Medido em `correr.salida.txt`:

```text
$ kubectl delete service revisor-publico
service "revisor-publico" deleted from default namespace

$ curl -s -m 3 http://172.18.255.200/salud
[código de salida: 28]

$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       2m18s

$ kubectl apply -k . | grep revisor-publico
service/revisor-publico created

$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.129.166   172.18.255.200   80:31622/TCP   5s

$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

**Sem o Service, o `curl` não conecta**: sai com 28 (acabou o tempo) ou, conforme o sistema, com 7 (não conseguiu conectar; no Linux, “No route to host” quando a pergunta ARP fica sem resposta). Os dois dizem a mesma coisa: ninguém responde por `172.18.255.200`. Não há quem recuse com um HTTP, porque nenhum `speaker` anuncia mais esse IP, a pergunta ARP fica sem resposta e o pacote não tem para onde ir. Ao apagar o Service, o MetalLB **soltou** o endereço. Resta um único `LoadBalancer`, o do Gateway, que não ficou sabendo de nada: continua em `.201`.

**O Service novo recebe de novo o `.200`**, não o `.202`. O MetalLB distribui o primeiro livre da faixa, e o `.200` voltou a estar livre. Mas é um objeto novo: outro `CLUSTER-IP` (`10.96.129.166` em vez de `10.96.115.79`) e **outro `NodePort`** (`31622` em vez de `30808`). O IP externo saiu igual porque é assim que a distribuição do MetalLB funciona, não porque o Kubernetes o lembre. Se entre a exclusão e a criação outro Service tivesse pedido um IP, teria ficado com o `.200`, e o Service da lição com outro. Por isso, se um IP externo precisa ser fixo (porque está em um DNS ou na configuração de um firewall), ele é pedido por escrito no Service, com a anotação `metallb.io/loadBalancerIPs: 172.18.255.200` (o [guia de uso do MetalLB](https://metallb.io/usage/) a prefere ao `spec.loadBalancerIP`, que está a caminho de ser aposentado), e não se confia no acaso da ordem.

### Solução 2

Medido em `correr.salida.txt`:

```text
$ kubectl apply -f fig06_02.solo-salud.yaml
httproute.gateway.networking.k8s.io/revisor configured

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud
200

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/salud/
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -X POST http://172.18.255.201/salud
404

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
200
```

**`200`, `404`, `404`, `404` e `200`.** Pelo Gateway só passa exatamente `GET /salud`. `/api/estados` não corresponde a nenhuma regra, nem com token: o token nem chega ao `revisor`, porque o **Envoy** responde `404` antes. `/salud/` também não, porque `Exact` é exato: uma barra a mais é outra rota. E `POST /salud` não corresponde pelo método. Os três `404` são do ponto de entrada: nenhuma regra leva essas requisições ao `revisor`, então o Envoy responde por conta própria.

**O quinto é o que importa:** pelo `172.18.255.200`, o `LoadBalancer` direto, o relatório sai completo, `200`. A regra que acabou de ser colocada no ponto de entrada nomeado não protege nada enquanto existir outro ponto de entrada sem regras. É o argumento da Lição 7 para retirar o `revisor-publico`: reduzir o que fica exposto só serve se houver **uma** única entrada.

Ao aplicar de novo a kustomization, a rota volta para `PathPrefix /` e `/api/estados` sem token volta a dar `401`, desta vez do `revisor`.

### Solução 3

Medido em `correr.salida.txt`:

```text
$ kubectl get ingressclass
No resources found

$ kubectl apply -f fig06_03.ingress.yaml
ingress.networking.k8s.io/revisor created

$ kubectl get ingress revisor
NAME      CLASS    HOSTS   ADDRESS   PORTS   AGE
revisor   <none>   *                 80      16s

$ kubectl describe ingress revisor | grep -E '^(Ingress Class|Address|Events):'
Address:          
Ingress Class:    <none>
Events:       <none>

$ kubectl delete -f fig06_03.ingress.yaml
ingress.networking.k8s.io "revisor" deleted from default namespace
```

**O cluster o aceita, e ninguém o atende.** Diferentemente do `Gateway` em 6.2, o tipo `Ingress` vem dentro do Kubernetes, no grupo `networking.k8s.io`: não é preciso nenhum CRD para criá-lo. Mas um `Ingress` é uma declaração, como um `Gateway`, e sem um controlador que a leia não acontece nada: não há `IngressClass` (`No resources found`), a coluna `CLASS` diz `<none>`, `ADDRESS` está vazio e não há um único evento. É o `<pending>` de 6.3 com outra cara: nenhum erro, nenhum resultado. O Envoy Gateway, o controlador que está instalado, atende a Gateway API e não este `Ingress`. As duas frases: “O `Gateway` não existia como tipo e o cluster o rejeitou; o `Ingress` existe como tipo e o cluster o guardou, mas ninguém o converte em um ponto de entrada. Um objeto aceito não é um objeto atendido”.

### Solução 4

Uma resposta possível: “O Cloud Provider KIND roda como um programa na máquina, fora dos clusters, com permissões para abrir portas e falar com o Docker. O próprio README dele diz que monitora todos os clusters do kind, e não descreve uma opção para se limitar a um; além disso, o controlador de Gateway API dele vem ativado. Em uma máquina compartilhada, o programa que lancei para a minha lição mexeria em clusters de outras pessoas sem que elas pedissem. O MetalLB e o Envoy Gateway vivem dentro do meu cluster e são apagados com ele; o preço é que a faixa de IPs do MetalLB sai da rede kind, que é compartilhada. Esse preço se controla conferindo, antes de criar o cluster, que ninguém já responde no primeiro IP da faixa, e rodando um só cluster com MetalLB por vez.”

## Apagar o cluster

Quando os exercícios terminarem, apague o cluster da lição. Com ele vão embora o MetalLB, o Envoy Gateway, os CRDs deles e os IPs:

```text
$ kind delete cluster --name curso-k8s-l6
Deleting cluster "curso-k8s-l6" ...
Deleted nodes: ["curso-k8s-l6-control-plane" "curso-k8s-l6-worker" "curso-k8s-l6-worker2"]

$ kind get clusters | grep -c curso-k8s-l6
0
```

Depois, apague o `token.txt` e a pasta temporária do `kubeconfig`, que guarda a credencial de administrador do cluster que acabou de ser apagado. O `rm -rf` é perigoso se a variável estiver vazia ou apontar para outro lugar, então vai protegido por um `case` que só o deixa rodar se o caminho for o que o `mktemp` criou em 6.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 6.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l6.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt
```

Fechar o terminal deixa de usar esse `kubeconfig`, mas não o apaga: sem o `case`, a credencial ficaria em `/tmp`. Confira também que não sobrou nenhum contêiner de cliente: `docker ps -a --filter name=curso-k8s-l6` não deve mostrar nada. A partir deste momento, `172.18.255.200` volta a estar livre para o próximo cluster que precisar dele.

## Como sei que consegui

- [ ] Explicar por que o `revisor-publico` ficou em `<pending>` e demonstrar com `curl` contra o IP de um nó que o `NodePort` dele já estava aberto.
- [ ] Instalar o MetalLB, dar a ele a faixa `172.18.255.200-172.18.255.220` e ler nos eventos do Service quem atribuiu o IP (`IPAllocated`) e de que nó ele é anunciado (`nodeAssigned`).
- [ ] Diante de `no matches for kind … ensure CRDs are installed first`, dizer o que falta (um CRD) e, diante de `failed calling webhook … connection refused`, dizer o que esperar (o controlador que responde ao *webhook*).
- [ ] Escrever de memória os três passos: plataforma, `kubectl wait`, projeto; e explicar por que um `sleep` não é uma espera.
- [ ] Explicar o que são `GatewayClass`, `Gateway` e `HTTPRoute`, a que papel corresponde cada uma e quem cria o Pod `envoy-default-revisor-…`.
- [ ] Diante de um `500` do ponto de entrada, conferir o Gateway, as duas condições da rota e o `message`, e encontrar um `BackendNotFound`.
- [ ] Fazer o inventário do que está exposto (os dois IPs, os dois `NodePort`, a 6443 em `127.0.0.1`) e dizer o que falta: criptografia.
- [ ] Explicar em uma frase cada um: por que não o Cloud Provider KIND, o que quer dizer que o `Ingress` esteja congelado e por que não o `ingress-nginx`.
- [ ] Rodar `programas/06-entrar-al-cluster/correr.sh > /tmp/mi-corrida-l6.txt 2>&1` e conferir com `correr.salida.txt` (sem redirecionar para esse arquivo: ele é a referência) o que não muda entre execuções: três nós `Ready` em `v1.37.0`; a rede `172.18.0.0/16`; `No resources found` nos CRDs; sete `created` e os dois `no matches for kind` de `Gateway` e `HTTPRoute`; `revisor-publico` em `<pending>` e `/salud` pelo `NodePort` de dois nós; o `failed calling webhook … connection refused` da primeira tentativa com a faixa (pode não aparecer se a máquina for mais rápida que a inicialização do MetalLB, e isso também ensina algo); nove CRDs de `metallb.io`; `ipaddresspool.metallb.io/curso created` na segunda tentativa; um `controller` e três `speaker`; **`172.18.255.200`** no `revisor-publico`, com `IPAllocated` e `nodeAssigned … layer2`; `3` linhas `Too long` e o limite de `262144 bytes`; `10` CRDs da Gateway API e `8` do Envoy Gateway; a `GatewayClass` `eg` com `ACCEPTED True` e dez tipos em `api-resources`; sete `unchanged` e dois `created`; o Gateway em **`172.18.255.201`** com `PROGRAMMED True`; `Accepted=True` e `ResolvedRefs=True`; um Pod `envoy-default-revisor-…` com `2/2`; `/salud` e a tabela pelo ponto de entrada, e `401` sem token; com a rota ruim, `ResolvedRefs=False BackendNotFound`, `service default/revisr not found` e `HTTP/1.1 500`; o código 7 por `https`; no Exercício 1, um código do `curl` (28 ou 7) e o `.200` de volta; no Exercício 2, `200 404 404 404 200`; no Exercício 3, `Address` vazio; e no final `sin diferencias con los archivos`. Os IPs de Pods, Services e nós, os `NodePort`, os sufixos, as idades, o nó que anuncia o IP, a ordem das linhas do `kind load` e as vezes que cada linha do `rollout status` se repete mudam a cada execução: observam-se, não se comparam.
- [ ] A partir de um cluster recém-criado, sem um único recurso personalizado, rodar `./levantar.sh` e chegar até `Programmed` sem um erro e sem corrigir nada manualmente; e dizer por que a faixa e a classe vão no passo 3.
- [ ] Ler a saída de `kubectl get crd` de 6.6.2 e dizer três coisas: que os CRDs da Gateway API são do canal `experimental`, que há mais três de `x-k8s.io`, e que o *webhook* do Envoy é `Ignore` e os do MetalLB `Fail`.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l6`, a pasta temporária do `kubeconfig` já não existe em `/tmp`, e ninguém responde em `172.18.255.200`.

## Resumo

Responda sem olhar a lição:

1. Por que um `LoadBalancer` fica em `<pending>` no kind? O que ele abre mesmo ficando assim?
2. O que fazem o `controller` e o `speaker` do MetalLB, e o que quer dizer “camada 2”?
3. Por que a faixa do MetalLB sai da rede `kind`, e por que do final dela?
4. O que é um CRD, e que erro dá aplicar um objeto cujo CRD não existe?
5. O que é um *webhook* de admissão, e o que faz o `kube-apiserver` quando não consegue chamá-lo, segundo o `failurePolicy`? Que valor têm os do MetalLB e que valor tem o de mutação do Envoy Gateway?
6. Quais são os três passos para subir plataforma e projeto, e o que exatamente cada `kubectl wait` desta lição espera?
7. Por que o Envoy Gateway é instalado com `--server-side`?
8. Que papel tem cada uma das três peças da Gateway API, e quem cria o Pod que de fato recebe as requisições?
9. Qual é a diferença entre `Ingress`, `ingress-nginx` e Gateway API, e em que estado está cada um?
10. O que fica exposto ao terminar esta lição, e o que falta ao ponto de entrada?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Service”](https://kubernetes.io/docs/concepts/services-networking/service/): o tipo `LoadBalancer`, provisionado pelo provedor de nuvem de forma assíncrona e publicado em `.status.loadBalancer`; a implementação dele sobre um `NodePort`; `allocateLoadBalancerNodePorts` e o valor padrão `true`.
- [Kubernetes, “Gateway API”](https://kubernetes.io/docs/concepts/services-networking/gateway/): a Gateway API como complemento definido com recursos personalizados; `GatewayClass`, `Gateway` e `HTTPRoute`; o design orientado a papéis.
- [Kubernetes, “Ingress”](https://kubernetes.io/docs/concepts/services-networking/ingress/): a API do Ingress congelada, sem planos de removê-la; a recomendação de usar o Gateway.
- [Kubernetes, blog, “Ingress NGINX Retirement: What You Need to Know”](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) (11 de novembro de 2025): o fim da manutenção em março de 2026, sem versões, correções nem patches de segurança depois; as instalações existentes continuam funcionando; a recomendação de migrar para a Gateway API.
- [Kubernetes, “Custom Resources”](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/): o que é um recurso personalizado e o que um `CustomResourceDefinition` cria.
- [Kubernetes, “Dynamic Admission Control”](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): o que são os *webhooks* de admissão, de validação e de mutação; `failurePolicy` com `Fail` por padrão.
- [Kubernetes, “Deployments”](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): a condição `Available` como disponibilidade mínima segundo a estratégia de atualização.
- [Gateway API, “ReferenceGrant”](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): a permissão para referências entre namespaces; a ligação rota-Gateway entre namespaces é decidida nos *listeners* (`allowedRoutes`).
- [MetalLB, “Usage”](https://metallb.io/usage/): a anotação `metallb.io/loadBalancerIPs` para pedir um IP concreto.
- [Docker, “Docker Engine 28: hardening container networking by default”](https://www.docker.com/blog/docker-engine-28-hardening-container-networking-by-default/) e [“Port publishing and mapping”](https://docs.docker.com/engine/network/port-publishing/): por que outra máquina da rede não alcança a rede dos contêineres.
- [Kubernetes, “kubectl wait”](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): esperar uma condição no `Status` de um ou vários recursos; a flag `--for`.
- [Kubernetes, “Server-Side Apply”](https://kubernetes.io/docs/reference/using-api/server-side-apply/): o plano de controle registra quais campos cada um gerencia; a comparação com a anotação `last-applied-configuration`.
- [kind, “LoadBalancer”](https://kind.sigs.k8s.io/docs/user/loadbalancer/): o Cloud Provider KIND como binário independente na máquina, com privilégios para abrir portas e falar com o *runtime* de contêineres.
- [kind, “Ingress”](https://kind.sigs.k8s.io/docs/user/ingress/): o suporte nativo a Ingress e Gateway API no Cloud Provider KIND.
- [Cloud Provider KIND, README](https://github.com/kubernetes-sigs/cloud-provider-kind): monitora todos os clusters do kind; o controlador de Gateway API dele vem ativado por padrão.
- [MetalLB, “Installation”](https://metallb.io/installation/): o manifesto `metallb-native.yaml` da v0.16.1; o `controller` e o `speaker`; os componentes parados até serem configurados.
- [MetalLB, “Configuration”](https://metallb.io/configuration/): `IPAddressPool`, `L2Advertisement` e a associação entre eles; a camada 2 respondendo a ARP.
- [Envoy Gateway, “Install with Kubernetes YAML”](https://gateway.envoyproxy.io/docs/install/install-yaml/): `kubectl apply --server-side` com o `install.yaml` da v1.9.2; o manifesto traz os CRDs da Gateway API e os do Envoy Gateway.
- [Gateway API, “HTTPRoute”](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/): sem `matches`, o prefixo `/` corresponde a toda requisição; cada `match` é independente.
- [Gateway API, especificação v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/): as referências inválidas de uma regra e o código 500 obrigatório.
- [curl, “libcurl error codes”](https://curl.se/libcurl/c/libcurl-errors.html): os códigos 7 e 28.

---

**Próxima:** [Lição 7 — Isolar: namespaces, permissões e rede](07-aislar-permisos-red.md)
