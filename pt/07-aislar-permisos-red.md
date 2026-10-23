# Lição 7 — Isolar: namespaces, permissões e rede

Sexta-feira, 5h50 da tarde. A equipe de dados faz duas semanas que pede um lugar para testar o serviço dela, e o cluster de kind tem espaço de sobra. Ficou combinado que sim. Às 5h58, alguém da equipe de segurança, que revisa o que é publicado antes do fim de semana, manda três perguntas seguidas. Uma: “um Pod deles consegue ler o token do `revisor`?”. Duas: “consegue falar com o `revisor` sem passar pelo ponto de entrada que foi publicado?”. Três: “consegue pedir à API do cluster a lista de Secrets?”. Quem montou o `revisor` sabe que ele roda sem ser `root`, com probes, com limites e atrás de um ponto de entrada nomeado. Mas essas três perguntas não são sobre o `revisor`. São sobre **o que rodeia o `revisor`**, e não existe nenhuma resposta medida. São 6h. A equipe de dados já colou o primeiro Pod no namespace `default`, que é onde mora tudo o que é da casa.

A história da segurança na nuvem tem muitas versões desta tarde. Em 20 de fevereiro de 2018, a empresa de segurança RedLock contou que tinha encontrado a Tesla com um console de administração de Kubernetes aberto, sem proteção. Segundo a própria RedLock, quem entrou por ali encontrou credenciais de acesso a um depósito de dados da Amazon Web Services e colocou o cluster para minerar criptomoedas. A Tesla respondeu que o impacto parecia limitado a veículos de teste de engenharia e que corrigiu o problema em questão de horas. A reportagem que conta isso está nas fontes desta lição. Essa porta aberta não é a que esta lição estuda. O que ela ensina é a pergunta que vem **depois** de qualquer porta aberta, por descuido ou por erro de outra equipe: uma vez lá dentro, até onde chega o que entrou?

Até hoje, no cluster, a resposta é “até onde der”. Esta lição põe paredes, em quatro camadas, e ensina a **medir** cada uma com o atacante mais modesto que existe: um Pod com `curl` que não deveria poder nada. A primeira decide **onde mora cada coisa** (o namespace). A segunda decide **o que se permite criar** (Pod Security Admission). A terceira decide **quem pode fazer o que com a API** (contas de serviço e RBAC), e a quarta, **quem pode falar com quem** (as políticas de rede). Ao terminar, as três perguntas das 5h58 terão resposta, com um comando ao lado.

**Tempo:** 2 × 45 min

**O que se constrói:** um namespace próprio, `revisor`, com regras: todo o projeto mora ali, o cluster rejeita qualquer Pod que não cumpra o nível `restricted`, cada programa tem a sua conta de serviço sem permissões e sem credenciais montadas (exceto uma conta somente leitura, para observar), e a rede fica fechada por padrão, com seis políticas que abrem só o necessário

**O que se aprende:** o que é um namespace e o que ele **não** isola; Pod Security Admission com os três modos e os três níveis, e como se leem as rejeições; `ServiceAccount`, `Role` e `RoleBinding` com permissões mínimas e como verificá-las com `kubectl auth can-i`, com uma requisição personificada e de dentro de um Pod; `NetworkPolicy`: o modelo (aberto até que uma política selecione o Pod, e as regras se somam), quem as aplica no kind (isso se mede), o que quebra com “tudo fechado” e para que serve cada uma das seis aberturas, retirando-as uma a uma; e como uma rota de outro namespace se pendura no ponto de entrada (`allowedRoutes` e `ReferenceGrant`)

**De onde a gente vem.** Da [Lição 6](06-entrar-al-cluster.md): o `revisor` roda com três réplicas e o serviço de teste com uma, com probes, `requests` e `limits`; o MetalLB e o Envoy Gateway estão instalados dentro do cluster; o ponto de entrada é um `Gateway` chamado `revisor` com a sua `HTTPRoute`; e há um `Service` `LoadBalancer` direto, `revisor-publico`, que esta lição retira. Tudo mora no namespace `default`. Da [Lição 5](05-salud-recursos-apagado.md) vem que as probes são feitas pelo `kubelet` do nó, um dado que hoje decide se a rede fechada derruba ou não os Pods. Da [Lição 3](03-services-dns.md), o Pod `depurar`, o DNS do cluster e que uma consulta de nome é tráfego de rede como qualquer outro. E da [Lição 2](02-pods-deployments.md), o `securityContext` que, desde o primeiro manifesto, cumpre, sem que ninguém soubesse, o nível `restricted`: hoje o cluster passa a exigi-lo.

**O que esta lição não faz.** Não criptografa o tráfego: o ponto de entrada continua falando HTTP puro, e dentro do cluster os Pods também não criptografam o que dizem uns aos outros. Não instala outro plugin de rede: o curso previa instalar o Calico se a rede do kind não aplicasse as políticas, e a seção 7.5 mede que ela as aplica, então não é preciso. Não limita quantos recursos um namespace pode criar (`ResourceQuota` e `LimitRange`, que a [Lição 5](05-salud-recursos-apagado.md) mencionou) nem instala políticas de admissão próprias. Não guarda dados nem agenda tarefas: isso é a [Lição 8](08-datos-y-tareas.md), que vai precisar desta lição de duas coisas, uma conta de serviço sem credenciais para a tarefa e o rótulo (label) `acceso-revisor: permitido`, para que a tarefa possa falar com o `revisor`. E tampouco é uma auditoria de segurança de um cluster real: a seção do hábito de segurança diz, com medições, o que isto protege e o que não protege.

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com `kind` v0.33.0, `kubectl` v1.37.1, a imagem de nó `kindest/node:v1.37.0` fixada pelo *digest*, **MetalLB v0.16.1** e **Envoy Gateway v1.9.2**, no cluster de três nós da Lição 1, aqui chamado de `curso-k8s-l7`. A máquina foi um Mac com processador ARM (`arm64`) e Docker Engine 29.2.1 dentro de uma máquina virtual Ubuntu 24.04.4 (Colima). A primeira linha de `correr.salida.txt` registra o que o script consegue medir: `Docker 29.2.1 en Ubuntu 24.04.4 LTS (arm64)`; que o host seja um Mac com Colima, o script não vê. **Não** foi o Linux Mint, que é o sistema de referência do curso. **Esta execução usou uma rede de Docker própria**, `curso-k8s-red-l7`, com a sub-rede `172.27.0.0/16`, porque na mesma máquina rodavam ao mesmo tempo outras lições com o seu próprio MetalLB, e dois MetalLB com a mesma faixa na mesma rede se sobrescrevem (isso apareceu na Lição 6). Por isso os endereços dos nós e do ponto de entrada saem aqui como `172.27.…`. No Mint, com a rede `kind` normal, o ponto de entrada recebe `172.18.255.200` e os nós ficam em `172.18.0.0/16`; o resto das saídas não muda. O `correr.sh` faz as duas coisas: com a rede `kind` padrão, e com uma rede própria se for indicada a qual, com `CURSO_RED` e `CURSO_SUBRED`; nos dois casos ele confere que a sub-rede seja exatamente a esperada e para se não for (com uma rede própria, antes de criar o cluster; com a rede `kind`, logo depois de criá-lo). O resto que muda na máquina de cada um: a arquitetura, os sufixos dos nomes, as idades, o nó de cada Pod, o nome do Secret (o token é novo a cada execução) e os milissegundos. O percurso completo está em [`programas/07-aislar-permisos-red/`](../programas/07-aislar-permisos-red): o `correr.sh` cria o cluster, carrega nele as duas imagens, instala a plataforma da Lição 6, deixa tudo como essa lição deixou, percorre esta em ordem, roda os Exercícios 1 a 3 e apaga o cluster. A execução completa levou 26 minutos e 9 segundos, longa porque a máquina estava carregada com outros clusters e porque a lição espera pela rede; criar o cluster e esperar que ficasse pronto foram 39 segundos, instalar a plataforma, 411, e apagá-lo, 1, e o disco do Docker estava em 79 % no início e em 77 % no fim. As esperas da instalação e do ponto de entrada (`speaker`, `Programmed`, o Pod `viejo`) têm prazos folgados (480, 360 e 300 segundos), porque numa máquina carregada as imagens demoram para baixar; se uma espera estourar o prazo, não siga às cegas: repita-a e veja com `kubectl get pods -A` o que falta. A saída é `correr.salida.txt`; precisa de internet (os manifestos do MetalLB e do Envoy Gateway são baixados das releases, fixadas na versão). As esperas ficam à vista: onde o script espera, a saída mostra isso com um `kubectl wait`, um `rollout status` ou um `sleep`. Usa a porta 18087 da máquina para um `port-forward` e para antes de começar se essa porta já estiver ocupada.

## Ao terminar, a gente vai conseguir

- Explicar o que um namespace isola (os nomes e o alcance das permissões) e o que não isola (a rede), e demonstrar isso com um Pod de um namespace falando com um Service de outro.
- Mudar o projeto de `default` para um namespace próprio com `kubectl apply -k`, e distinguir o que vive dentro de um namespace do que vale para o cluster inteiro.
- Pôr um namespace no nível `restricted` com os seus rótulos (labels), fixar a versão da política e ler, linha por linha, a rejeição de um Pod que não a cumpre.
- Provocar um Deployment que é criado mas fica sem Pods por causa do Pod Security Admission, e encontrar o motivo nos eventos do ReplicaSet.
- Escrever um `Role` e um `RoleBinding` somente leitura, verificar o que permitem e o que negam com `kubectl auth can-i` e com uma requisição real feita de dentro de um Pod, e explicar por que o `revisor` não leva credenciais montadas.
- Fechar a rede de um namespace com uma política, medir o que quebra (inclusive o DNS e o ponto de entrada), abrir só o necessário e dizer, para cada uma das seis políticas, o que deixaria de funcionar se ela faltasse.
- Explicar sob que condição uma `NetworkPolicy` “fechada por padrão” protege alguma coisa, e verificá-la no cluster.
- Pendurar uma rota de outro namespace no ponto de entrada, e distinguir `allowedRoutes` (quem pode se pendurar no Gateway) de `ReferenceGrant` (quem pode ser destino de uma rota).

## O porquê antes do como

Imagine um prédio de escritórios com um único corredor comprido e todas as portas sem chave. Alguém colou plaquinhas nas portas (`datos`, `finanzas`, `revisor`) e tudo parece organizado. Mas a plaquinha não tranca nada: qualquer um que entre no prédio pode abrir qualquer porta. É isso que o cluster é hoje. Os namespaces que a gente já conhece são as plaquinhas. Esta lição lhes põe chaves, um regulamento e portas com fechadura, e faz isso por camadas, porque cada camada responde a uma pergunta diferente e falha de um jeito diferente:

1. **Onde mora cada coisa?** O **namespace**. Agrupa objetos, permite que duas equipes usem o mesmo nome sem colidir e é a unidade à qual se prendem permissões e regras. Não é uma parede de rede: isso se mede em 7.5.
2. **O que se permite criar?** **Pod Security Admission**. É um guarda na porta do `kube-apiserver` que revisa cada Pod que quer nascer em um namespace e o rejeita se não cumprir o nível que esse namespace exige. Protege contra o Pod mal escrito, não contra o Pod que já está rodando.
3. **Quem pode fazer o que com a API?** **Contas de serviço e RBAC**. Cada programa que roda no cluster tem uma identidade, e cada identidade tem uma lista (por padrão, vazia) de verbos que pode aplicar a certos objetos.
4. **Quem pode falar com quem?** **Políticas de rede**. Hoje todo Pod pode falar com todo Pod. Uma política muda isso Pod a Pod, e só funciona se a rede do cluster as aplicar.

As camadas se complementam porque protegem contra coisas diferentes. O PSA impede que alguém (ou um descuido) crie um contêiner com privilégios demais. O RBAC limita o que um programa faz **com a API**. A rede limita o que ele faz **com os outros Pods**. E o namespace é o lugar onde as três se aplicam. Se uma falta, as outras não a cobrem: um Pod `restricted` sem política de rede continua podendo falar com todos, e uma rede fechada com uma conta de serviço generosa deixa um Pod comprometido pedir à API tudo o que essa permissão alcançar.

A lição tem cinco partes de conceitos e depois as seções de sempre:

1. **O cluster da lição** (7.1), com a plataforma da Lição 6 e o ponto de partida.
2. **Um namespace próprio** (7.2): o que é, o que contém e a mudança.
3. **Pod Security Admission** (7.3): modos, níveis, rótulos e a rejeição que se aprende a ler.
4. **Contas de serviço e permissões mínimas** (7.4): `ServiceAccount`, `Role`, `RoleBinding`, `auth can-i`, e uma requisição real de dentro de um Pod.
5. **A rede** (7.5): o modelo, quem a aplica, sem regras, tudo fechado, as aberturas e para que serve cada uma.

Este é o destino. No final de 7.5, um Pod com o rótulo correto pode falar com o `revisor`, um Pod sem ele não, e as duas respostas saem de comandos que podem ser repetidos:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

## Se a imagem do curso de Docker não estiver disponível

Esta lição usa as mesmas duas imagens das Lições 3 a 6: `curso-docker-revisor:1.6.0` e `curso-docker-prueba:1.0.0`. Confira que elas existem:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para a outra, o mesmo comando com `curso-docker-prueba:1.0.0`. Se faltar alguma, a [Lição 3](03-services-dns.md) diz como construir as duas a partir do repositório do curso de Docker. Esta lição não exige nada de novo de nenhuma das duas. Os Pods de apoio (`depurar`, `intruso` e `lector`) usam a imagem do `curl` fixada pelo *digest*, como nas lições anteriores; cada nó a baixa da internet na primeira vez.

## Os conceitos

### 7.1 O cluster da lição

#### 7.1.1 Criar, com a trava de contexto

Esta lição cria o seu próprio cluster, `curso-k8s-l7`, com a configuração de três nós da Lição 1. Até aqui, nas lições anteriores, a verificação do contexto era uma linha que se copiava na frente de cada comando. Hoje ela vira uma função, para ficar curta e não ser esquecida. Crie-o assim, a partir da raiz do repositório do curso:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L7_TMP="$(mktemp -d /tmp/curso-k8s-l7.XXXX)"
export KUBECONFIG="$L7_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: si abres otra terminal, la necesitas

# La guarda: se escribe una vez y va delante de cada comando que cambia algo.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l7 ] || { echo "contexto equivocado: no sigo"; return 1; }; }

# curso-k8s-l7 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l7 --config programas/07-aislar-permisos-red/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l7

# Desde aquí, todo se ejecuta dentro de la carpeta de la lección:
cd programas/07-aislar-permisos-red
```

A função `ctx` faz uma coisa só: compara o contexto ativo do `kubectl` com `kind-curso-k8s-l7`. Se coincidir, não imprime nada e termina bem, e o `&&` deixa passar para o comando seguinte. Se não coincidir, imprime “contexto equivocado: no sigo” e termina com erro, e o `&&` **corta a cadeia**: o comando que muda alguma coisa não é executado. A partir daqui, **todo comando desta lição que muda alguma coisa** (`apply`, `delete`, `patch`, `label`, `run`, `exec` que apaga…) se escreve assim: `ctx && kubectl apply -k .`. Nas saídas que seguem, a linha que começa com `$` mostra só o comando do `kubectl`, sem o `ctx &&`, para caber; o script `correr.sh` faz a mesma verificação antes de **cada** `kubectl`, inclusive as leituras, e para se o contexto não for o da lição. A razão de tanto cuidado já é conhecida desde a Lição 1: um `delete -k` no contexto errado apagaria objetos de outro cluster, e esta lição apaga e recria vários.

Duas verificações de convivência, as mesmas da Lição 6 (com uma rede própria elas são feitas antes de criar o cluster; com a rede `kind` padrão, que nasce com o primeiro cluster, logo depois de criá-lo): a rede `kind` deve ser `172.18.0.0/16` (dela sai a faixa do MetalLB) e ninguém deve responder em `172.18.255.200`. Se outro cluster com MetalLB estiver vivo, espere que termine. O `correr.sh` as faz e para se falharem; nesta execução ele as fez contra a rede própria, `curso-k8s-red-l7`, que a seção “Sobre as execuções” explica.

```text
$ kubectl config current-context
kind-curso-k8s-l7

$ kubectl get nodes -o wide | awk '{print $1, $2, $3, $6}' | column -t
NAME                        STATUS  ROLES          INTERNAL-IP
curso-k8s-l7-control-plane  Ready   control-plane  172.27.0.4
curso-k8s-l7-worker         Ready   <none>         172.27.0.2
curso-k8s-l7-worker2        Ready   <none>         172.27.0.3
```

Os três nós vivem na rede de Docker da execução (`172.27.0.x`; no Mint, `172.18.0.x`). `kubectl wait` e `kubectl get` não mudam nada, então não precisam da trava; todo o resto precisa.

#### 7.1.2 A plataforma da Lição 6, em três passos

A Lição 6 deixou duas instalações que não são do `revisor`, e sim do cluster: o MetalLB e o Envoy Gateway. Esta lição precisa delas porque o projeto inclui um `Gateway`. Elas são instaladas como lá, na ordem que a gente aprendeu: plataforma, espera, projeto. Os comandos são os mesmos da seção 6.9, e a saída mostra cada espera:

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=480s | tail -1
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io crd/referencegrants.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
(en esta corrida el rango del archivo se cambió a 172.27.255.200-172.27.255.250, dentro de la red curso-k8s-red-l7)
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met
```

Duas coisas que já se sabem e uma que mudou. Já se sabe que é preciso esperar o `controller` do MetalLB antes de entregar a faixa a ele (o *webhook* precisa estar escutando) e que a faixa e a classe `eg` são aplicadas no final. O que mudou foi a espera dos CRDs: desta vez ela inclui `referencegrants.gateway.networking.k8s.io`, um tipo da Gateway API que o Exercício 3 usa e que vem no mesmo pacote que o Envoy Gateway instalou.

Sobre a linha entre parênteses de `kubectl apply -f infra/metallb-pool.yaml`: o arquivo do curso traz a faixa `172.18.255.200-172.18.255.220`, a do Mint. Nesta execução, o `correr.sh` mudou essa faixa, **com `sed` e na hora**, para `172.27.255.200-172.27.255.250`, que cai dentro da rede própria. É a única mudança: o arquivo do repositório não foi tocado. Na máquina de cada um ele é aplicado tal como está.

#### 7.1.3 O ponto de partida: a Lição 6, em `default`

A pasta `punto-de-partida/` traz, sem mudar uma vírgula, os manifestos com os quais a Lição 6 terminou. A gente já está na pasta da lição. O token é de mentira e não é versionado; ele é gerado a cada execução com o `umask` que já se conhece, para nascer com permissão `0600`, e é copiado para a pasta da lição porque o `kustomization.yaml` das duas o pede:

```bash
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
```

Os parênteses e o `umask 077` são o costume da Lição 4: o arquivo é criado fechado desde o primeiro byte, e não criado aberto e fechado depois. Agora, com o `revisor`, o `prueba`, o `Service` público e o ponto de entrada em `default`, isto é o que o cluster sabe do estado “antes”:

```text
$ /bin/ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=360s
gateway.gateway.networking.k8s.io/revisor condition met
```

Faltam quatro leituras do “antes”, as que vão mudar no final da lição:

```text
$ kubectl get namespaces
NAME                   STATUS   AGE
default                Active   11m
envoy-gateway-system   Active   11m
kube-node-lease        Active   11m
kube-public            Active   11m
kube-system            Active   11m
local-path-storage     Active   11m
metallb-system         Active   11m

$ kubectl get namespace default --show-labels
NAME      STATUS   AGE   LABELS
default   Active   11m   kubernetes.io/metadata.name=default

$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.serviceAccountName} | {.items[0].spec.automountServiceAccountToken} | {.items[0].spec.volumes[*].name}{"\n"}'
default |  | datos token kube-api-access-5q29h

$ kubectl auth can-i --list --as=system:serviceaccount:default:default | head -4
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
```

Leia-se assim. Os namespaces são os de sempre mais os dois da plataforma (`envoy-gateway-system` e `metallb-system`); `default` não tem mais rótulo do que o que o sistema lhe põe, `kubernetes.io/metadata.name`: nenhuma regra. O terceiro comando pergunta, à primeira réplica do `revisor` (`.items[0]`; as três são iguais porque saem do mesmo modelo), três coisas: com que conta ela roda (`default`), se foi pedido que não lhe montassem credenciais (o campo `automountServiceAccountToken` aparece **vazio**, ou seja, ninguém disse nada) e que volumes ela tem: `datos`, `token` (o Secret da Lição 4) e um terceiro com nome aleatório, `kube-api-access-…`. Esse terceiro é o que ninguém pediu: **o cluster montou no `revisor` uma credencial para falar com a API**, e o `revisor` não fala com a API. É a primeira coisa que esta lição tira. E o último comando lista o que a conta `default` pode fazer: quase nada (criar revisões sobre si mesma, que são perguntas do tipo “o que eu posso fazer?”), mas “quase nada” não é o mesmo que “nada”, e 7.4 mede a diferença.


### 7.2 Um namespace próprio

#### 7.2.1 O que é e o que não é

Um **namespace** é um grupo com nome dentro do cluster. A [documentação de namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) diz isso em uma frase: os namespaces “fornecem um mecanismo para isolar grupos de recursos dentro de um único cluster”, e os nomes dos recursos precisam ser únicos **dentro** de um namespace, não entre namespaces. Isso traz três consequências práticas, que são as que importam hoje:

- **Os nomes não colidem.** A equipe de dados pode ter o seu próprio Service chamado `revisor` no namespace dela sem pisar no nosso. E o DNS reflete isso: o que a Lição 3 chamou de `revisor`, sem mais nada, é na verdade `revisor.<namespace>.svc.cluster.local`, e de outro namespace é preciso escrevê-lo completo.
- **As permissões têm alcance.** Um `Role` (7.4) vale dentro de um namespace. Dar permissão sobre os Pods de `revisor` não dá permissão sobre os de `default`.
- **As regras se prendem a um namespace.** Os rótulos do Pod Security Admission (7.3) e as políticas de rede (7.5) se aplicam ao namespace onde vivem.

O que ele **não** faz, ainda que o nome e os tutoriais sugiram: não fecha a rede. A mesma página não menciona isolamento de rede, porque ele não existe: um Pod de um namespace pode falar com um Service de outro só escrevendo o nome completo. 7.5.3 mede isso, e é por isso que a quarta camada existe.

Nem tudo vive dentro de um namespace. Dá para perguntar ao cluster, que sabe quais tipos pertencem a um e quais valem para todo o cluster:

```text
$ kubectl api-resources --namespaced=false -o name | grep -E '^(nodes|namespaces|persistentvolumes|storageclasses|clusterroles|clusterrolebindings|gatewayclasses\.)'
namespaces
nodes
persistentvolumes
gatewayclasses.gateway.networking.k8s.io
clusterrolebindings.rbac.authorization.k8s.io
clusterroles.rbac.authorization.k8s.io
storageclasses.storage.k8s.io

$ kubectl api-resources --namespaced=true -o name | grep -E '^(pods|services|secrets|serviceaccounts|roles|rolebindings|networkpolicies)(\.|$)'
pods
secrets
serviceaccounts
services
networkpolicies.networking.k8s.io
rolebindings.rbac.authorization.k8s.io
roles.rbac.authorization.k8s.io
```

A primeira lista, tipos **sem** namespace: os próprios namespaces, os nós, os volumes persistentes, as classes de armazenamento, os papéis de alcance de cluster (`clusterroles`) e as suas associações, e a `GatewayClass` que foi criada na Lição 6. A segunda, tipos **com** namespace: os Pods, os Services, os Secrets, as contas de serviço e, no grupo de RBAC e de rede, os `roles`, os `rolebindings` e as `networkpolicies` desta lição. A regra para lembrar: o que descreve **uma carga de trabalho** vive em um namespace; o que descreve **a infraestrutura que todas compartilham** não. Por isso a `GatewayClass` `eg` não muda hoje, e por isso o MetalLB e o Envoy Gateway, que são plataforma, continuam em `metallb-system` e `envoy-gateway-system`. Só o projeto muda.

#### 7.2.2 O que muda nos manifestos

A mudança se reduz a poucas alterações, quase todas no `kustomization.yaml`. Leia-o completo, com o comentário:

```yaml
# kustomization.yaml — Lección 7. Se aplica con: kubectl apply -k .
# Todo va al espacio de nombres «revisor» (namespace: revisor, abajo), que nace
# aquí mismo (namespace.yaml) en el nivel «restricted» de Pod Security.
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Requiere la infraestructura de la Lección 6 (MetalLB y Envoy Gateway) ya
# instalada: sin sus CRD, Gateway y HTTPRoute no existen.
# revisor-publico.yaml (el LoadBalancer directo de la 6) ya no está: desde la
# Lección 7 la única puerta es el Gateway. El estado de la Lección 6 vive en
# punto-de-partida/, y se retira con: kubectl delete -k punto-de-partida
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: revisor
resources:
- namespace.yaml
- cuentas.yaml
- red.yaml
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
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

A linha nova que mais faz é `namespace: revisor`. O Kustomize a aplica como uma transformação: a **todo** objeto com namespace que aparece em `resources` ele escreve `metadata.namespace: revisor`, sem que seja preciso repetir em cada arquivo. Por isso os Deployments, os Services e o `Gateway` não mudaram uma letra do seu `metadata`. As outras mudanças são três arquivos novos na lista: `namespace.yaml` (o próprio namespace, com os seus rótulos, 7.3), `cuentas.yaml` (as contas e as permissões, 7.4) e `red.yaml` (as seis políticas, 7.5). E os dois Deployments agora declaram a sua conta de serviço e pedem ao cluster que não lhes monte credenciais:

```yaml
    spec:
      serviceAccountName: revisor
      automountServiceAccountToken: false
```

(É um trecho: são duas linhas de `revisor-deployment.yaml`, que 7.4 explica. O de `prueba` diz `prueba`.) Repare também no que **não** está na lista: `revisor-publico.yaml`, o `LoadBalancer` direto da Lição 6. O comentário dele mesmo já anunciava: de hoje em diante o único ponto de entrada para fora é o `Gateway`. O arquivo é mantido em `punto-de-partida/` como referência.

#### 7.2.3 A mudança

Um namespace novo não “move” objetos; os objetos de um namespace não podem ser passados para outro. Eles são **apagados de um e criados no outro**. Primeiro se retira o estado da Lição 6 com o mesmo `kustomization` que o criou, e depois se aplica o desta lição. O token fica: é o mesmo arquivo para as duas, e por isso o Secret gerado conserva o nome.

```bash
ctx && kubectl delete -k punto-de-partida
rm -f -- punto-de-partida/token.txt
ctx && kubectl apply -k .
```

```text
$ kubectl delete -k punto-de-partida
configmap "revisor-config-t6cm6872fk" deleted from default namespace
secret "revisor-token-mgc44f554f" deleted from default namespace
service "prueba" deleted from default namespace
service "revisor" deleted from default namespace
service "revisor-publico" deleted from default namespace
deployment.apps "prueba" deleted from default namespace
deployment.apps "revisor" deleted from default namespace
gateway.gateway.networking.k8s.io "revisor" deleted from default namespace
httproute.gateway.networking.k8s.io "revisor" deleted from default namespace

$ kubectl apply -k .
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
service/prueba created
service/revisor created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created
networkpolicy.networking.k8s.io/acceso-revisor-salida created
networkpolicy.networking.k8s.io/cerrado created
networkpolicy.networking.k8s.io/dns created
networkpolicy.networking.k8s.io/prueba-entrada created
networkpolicy.networking.k8s.io/revisor-entrada created
networkpolicy.networking.k8s.io/revisor-salida created

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba -n revisor --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Leia os dois primeiros blocos de cima para baixo. O `delete -k` apaga nove objetos, e cada linha diz **de onde** os apaga (`from default namespace`). O `apply -k` cria vinte: o namespace (`namespace/revisor`), as três contas, o `Role` e o seu `RoleBinding`, o ConfigMap e o Secret com o hash de sempre, os dois Services, os dois Deployments, o ponto de entrada e a rota, e as seis políticas de rede. Repare na ordem: o namespace sai primeiro. O Kustomize entrega os objetos com os namespaces na frente, e por isso não foram precisos dois passos. Com os tipos de uma plataforma nova, como `Gateway` na Lição 6, a espera continua sendo de quem executa: ali não é uma questão de ordem da lista, e sim de o tipo existir.

Ficou tudo onde devia?

```text
$ kubectl get namespace revisor -o go-template='{{range $k, $v := .metadata.labels}}{{$k}}={{$v}}{{"\n"}}{{end}}'
kubernetes.io/metadata.name=revisor
pod-security.kubernetes.io/audit=restricted
pod-security.kubernetes.io/audit-version=v1.37
pod-security.kubernetes.io/enforce=restricted
pod-security.kubernetes.io/enforce-version=v1.37
pod-security.kubernetes.io/warn=restricted
pod-security.kubernetes.io/warn-version=v1.37

$ kubectl get all -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rgh68    1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          2m52s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.130.233   <none>        9000/TCP   2m52s
service/revisor   ClusterIP   10.96.146.219   <none>        80/TCP     2m52s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           2m52s
deployment.apps/revisor   3/3     3            3           2m52s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       2m52s
replicaset.apps/revisor-5d6fd4d6bd   3         3         3       2m52s

$ kubectl get all -n default
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   14m

$ kubectl get gateway,httproute -n revisor
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.27.255.200   True         2m52s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               2m52s

$ kubectl wait --for=condition=Available deployment -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=revisor --timeout=180s
deployment.apps/envoy-revisor-revisor-b269644b condition met

$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-gateway-5fc4949dcb-k6s46                    1/1     Running   0          14m
pod/envoy-revisor-revisor-b269644b-867f46cd7d-rbkcf   2/2     Running   0          2m52s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-gateway                    ClusterIP      10.96.130.219   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   14m
service/envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       2m52s
```

`default` ficou com uma única coisa, o Service `kubernetes`, que o cluster cria sozinho: o namespace está limpo. Todo o projeto está em `revisor`, e o ponto de entrada o atende a partir de `envoy-gateway-system`, um terceiro namespace: **o ponto de entrada não mora onde mora o projeto**. Anote isso, porque a política de rede de 7.5 precisa deixá-lo passar, e isso se faz com um `namespaceSelector`. E uma verificação de fora do cluster, como na Lição 6, para ver que a mudança não fechou o ponto de entrada:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Uma última decisão da lição. Com o projeto já mudado, o script retira as seis políticas de rede:

```text
$ kubectl delete -n revisor -f red.yaml
networkpolicy.networking.k8s.io "cerrado" deleted from revisor namespace
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace
networkpolicy.networking.k8s.io "prueba-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace
```

Não é um erro nem uma prova de que elas não servem. É para estudar **uma camada de cada vez**. As seis políticas estão no `kustomization.yaml` porque o estado final do projeto as leva, mas, se estivessem em vigor enquanto se estuda Pod Security e RBAC, cada Pod de prática nasceria sem poder falar com a API, e não se saberia se o que se vê é causado por uma camada ou por outra. Elas voltam em 7.5, com a sua explicação.

### 7.3 Pod Security Admission

#### 7.3.1 O que é: um guarda na porta do `kube-apiserver`

Quando se faz `kubectl apply`, a requisição passa por uma cadeia de controles antes de ser gravada. Um deles se chama **admissão**. A [documentação do Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) o descreve: é um controlador que revisa cada Pod que vai ser criado contra um **padrão** (os *Pod Security Standards*), e decide segundo um rótulo do namespace onde ele nasceria. Não instala nada: vem com o `kube-apiserver`. É configurado **com rótulos do namespace**, e esses rótulos têm três partes:

- **O modo**, que diz o que fazer com uma violação. Há três: `enforce` (“os Pods que violam a política são rejeitados”), `audit` (“uma anotação é adicionada ao registro de auditoria, mas o Pod é permitido”) e `warn` (“o usuário recebe um aviso, mas o Pod é permitido”). Um namespace pode usar um, dois ou os três, e até com níveis diferentes.
- **O nível**, que diz quanto se exige. Os [padrões de segurança de Pods](https://kubernetes.io/docs/concepts/security/pod-security-standards/) definem três. `privileged` é “deliberadamente aberto e completamente sem restrições”. `baseline` busca “facilitar a adoção para cargas de trabalho comuns” e, ao mesmo tempo, impedir as escaladas de privilégio conhecidas. `restricted` é uma política “muito restrita”, que segue as práticas atuais de *hardening*.
- **A versão** (opcional), que fixa com que edição do padrão o Pod é comparado. Cada versão do Kubernetes pode refinar o que `baseline` e `restricted` pedem; com `latest` o padrão se move com o cluster, e com `v1.37` ele fica fixo.

O rótulo tem esta forma: `pod-security.kubernetes.io/<MODO>: <NÍVEL>` e, à parte, `pod-security.kubernetes.io/<MODO>-version: <VERSÃO>`. Veja como ficou o namespace da lição com as três:

```yaml
# namespace.yaml — Lección 7: un espacio propio, en el nivel «restricted» de
# Pod Security Admission, con la versión de la política fijada.
apiVersion: v1
kind: Namespace
metadata:
  name: revisor
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: v1.37
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.37
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.37
```

O namespace `revisor` usa **os três modos no mesmo nível**, `restricted`, e os três fixados em `v1.37`. Os três juntos fazem sentido: `enforce` é o que protege (rejeita), `warn` é o que avisa **ao aplicar** um Deployment, antes que ele falhe (7.3.4), e `audit` deixa rastro no registro de auditoria do `kube-apiserver`, que o curso não ativa nem mede. O guia da documentação para aplicar esses níveis a um namespace mostra a mesma divisão de papéis: `enforce` no nível que já se cumpre e `audit` e `warn` no nível ao qual se quer chegar, para ver o que falharia antes de exigi-lo.

#### 7.3.2 Os três níveis, medidos

Antes do namespace da lição, os três níveis frente a frente. São criados dois namespaces de teste, um `privileged` e um `baseline`, e a cada um (e a `revisor`) se pede que aceite dois Pods, sem criá-los: `--dry-run=server` manda a requisição completa ao `kube-apiserver`, que a valida com todos os seus controles de admissão e não grava nada. O primeiro Pod pede `hostNetwork: true`, ou seja, usar a rede do nó em vez da sua, algo que o `baseline` já proíbe. O segundo é um Pod de `curl` escrito sem `securityContext`, como em um tutorial qualquer.

```text
$ kubectl create namespace nivel-privileged
namespace/nivel-privileged created

$ kubectl create namespace nivel-baseline
namespace/nivel-baseline created

$ kubectl label namespace nivel-privileged pod-security.kubernetes.io/enforce=privileged
namespace/nivel-privileged labeled

$ kubectl label namespace nivel-baseline pod-security.kubernetes.io/enforce=baseline
namespace/nivel-baseline labeled

$ kubectl wait --for=create serviceaccount/default -n nivel-privileged --timeout=60s
serviceaccount/default condition met

$ kubectl wait --for=create serviceaccount/default -n nivel-baseline --timeout=60s
serviceaccount/default condition met
```

O `kubectl wait --for=create` é uma espera que talvez ninguém esperasse: cada namespace novo recebe a sua conta `default` alguns instantes **depois** de nascer, quem a cria é um controlador, e um Pod pedido antes de a conta existir é rejeitado por outra razão (`serviceaccount "default" not found`). Em uma das execuções de teste desta lição (sem saída guardada), sem essa espera, os seis testes abaixo falharam com essa mensagem e não com a de segurança. Por isso hoje a espera fica à vista.

```text
--- espacio nivel-privileged ---
$ kubectl run hostnet -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
pod/hostnet created (server dry run)

$ kubectl run sinreglas -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio nivel-baseline ---

$ kubectl run hostnet -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true)
[código de salida: 1]

$ kubectl run sinreglas -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio revisor ---

$ kubectl run hostnet -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "restricted:v1.37": host namespaces (hostNetwork=true), allowPrivilegeEscalation != false (container "hostnet" must set securityContext.allowPrivilegeEscalation=false), unrestrict
[código de salida: 1]

$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinr
[código de salida: 1]
```

As saídas estão cortadas em 260 caracteres com `cut` para caberem; a mensagem completa aparece em 7.3.3. Leiam-se como uma tabela:

| Namespace | `hostNetwork: true` | Pod sem `securityContext` |
|---|---|---|
| `nivel-privileged` | criado (`server dry run`) | criado |
| `nivel-baseline` | **rejeitado**: `host namespaces (hostNetwork=true)` | criado |
| `revisor` (`restricted`) | **rejeitado**, e com mais motivos | **rejeitado** |

Três coisas. Primeira: o `baseline` freia o que se sabe perigoso (compartilhar a rede do nó) e deixa passar um Pod normal, escrito sem cuidado. O `restricted` pede além disso as boas práticas, e por isso o mesmo Pod simples que o `baseline` aceita aqui é rejeitado. Segunda: a mensagem de `nivel-baseline` diz `"baseline:latest"`, sem versão. Como esse namespace não fixou `enforce-version`, o padrão é o da versão do cluster, **qualquer que seja**; o de `revisor` diz `"restricted:v1.37"`, fixado. Se o cluster for atualizado, o primeiro pode começar a rejeitar o que antes aceitava; o segundo não muda até que o rótulo mude. Terceira: o script apaga os dois namespaces de teste ao terminar (`kubectl delete namespace`), o que apaga com eles tudo o que tivessem.

```text
$ kubectl delete namespace nivel-privileged nivel-baseline
namespace "nivel-privileged" deleted
namespace "nivel-baseline" deleted
```

#### 7.3.3 `restricted`, lido linha por linha

O Pod de prática que foi rejeitado duas vezes acima é um Pod de `curl` normal. Agora sem cortes, no namespace da lição:

```text
$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never -- sleep 60
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinreglas" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "sinreglas" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "sinreglas" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
[código de salida: 1]

$ kubectl get pods -n revisor -l run=sinreglas
No resources found in revisor namespace.
```

A mensagem tem a forma “o Pod X não pode ser criado: viola PodSecurity "restricted:v1.37": ” seguida de uma lista separada por vírgulas, e cada elemento é uma regra descumprida, com o campo que a corrige entre parênteses. Quatro:

1. `allowPrivilegeEscalation != false`: o contêiner deve declarar `securityContext.allowPrivilegeEscalation=false`. Sem essa linha, um processo lá dentro poderia ganhar mais privilégios do que o processo pai (por exemplo, executando um programa com o bit *setuid*).
2. `unrestricted capabilities`: deve declarar `securityContext.capabilities.drop=["ALL"]`. As *capabilities* do Linux são pedacinhos do que antes só o `root` fazia; um contêiner que não pede nada recebe um conjunto padrão, e o `restricted` exige tirar tudo.
3. `runAsNonRoot != true`: o Pod ou o contêiner deve declarar `runAsNonRoot=true`. Não basta que a imagem *seja* de um usuário normal: o manifesto deve **dizer** que exige isso, para que o cluster rejeite uma imagem que um dia mude para `root`.
4. `seccompProfile`: deve declarar `seccompProfile.type` como `RuntimeDefault` ou `Localhost`. O `seccomp` é o filtro de chamadas ao kernel; o perfil do *runtime* bloqueia as mais perigosas.

E não foi rejeitado por uma quinta, `readOnlyRootFilesystem`, que o curso põe desde a Lição 2: é boa prática, mas o nível `restricted` **não** a exige. É a diferença entre o que o cluster impõe e o que a gente se impõe. Cada linha dessa lista é uma das quatro que o `securityContext` do `revisor` leva desde a Lição 2; por isso o `revisor` e o `prueba` nasceram sem problema neste mesmo namespace. E o `get pods` confirma: `No resources found`. A rejeição acontece **antes** de criar: o Pod não existe, nem em estado de erro.

#### 7.3.4 O que se pode (e o que não se pode) endurecer: `kube-system` e o `dry-run`

Por que não pôr `restricted` em todos os namespaces, sem pensar? O mesmo `--dry-run=server` usado com os Pods serve para ver o que aconteceria com um **rótulo**: ele calcula contra os Pods que já existem e avisa, sem mudar nada. Testa-se com dois namespaces:

```text
$ kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: coredns-559f6c778d-q8k29 (and 1 other pod): runAsNonRoot != true, seccompProfile
Warning: etcd-curso-k8s-l7-control-plane (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
Warning: kindnet-82j5f (and 2 other pods): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: kube-proxy-d6hbh (and 2 other pods): host namespaces, privileged, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
namespace/kube-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

Com `kube-system` há quatro avisos, um por grupo de Pods, e todos começam com `Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"`: o CoreDNS não declara `runAsNonRoot` nem `seccompProfile`; `etcd`, `kindnet` e `kube-proxy` usam a rede do nó (`host namespaces`) e pedem volumes do tipo `hostPath` (`restricted volume types`), e o `kube-proxy` além disso é *privileged*. Pedem isso porque o trabalho deles é tocar o nó. Por isso **um nível não se aplica por moda**: mede-se primeiro, e há namespaces (os do sistema) onde o `restricted` não cabe. E o mesmo `--dry-run` em `revisor` diz `namespace/revisor not labeled (server dry run)` sem um único aviso: o projeto já cumpre o que se exige.

E os Pods que já rodavam quando o rótulo é posto? A documentação diz que, ao adicionar ou mudar um rótulo `enforce`, o controlador testa cada Pod do namespace contra a política nova e devolve as violações como avisos. Não diz o que acontece com o Pod. Mede-se com um namespace de teste: ele nasce sem rótulos, recebe um Pod que não cumpre o `restricted`, e **depois** recebe `enforce=restricted`.

```text
$ kubectl create namespace nivel-previo
namespace/nivel-previo created

$ kubectl wait --for=create serviceaccount/default -n nivel-previo --timeout=60s
serviceaccount/default condition met

$ kubectl run viejo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600
pod/viejo created

$ kubectl wait --for=condition=Ready pod/viejo -n nivel-previo --timeout=300s
pod/viejo condition met

$ kubectl label namespace nivel-previo pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "nivel-previo" violate the new PodSecurity enforce level "restricted:latest"
Warning: viejo: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/nivel-previo labeled

$ kubectl get pod viejo -n nivel-previo
NAME    READY   STATUS    RESTARTS   AGE
viejo   1/1     Running   0          21s

$ kubectl run nuevo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600 2>&1 | cut -c1-200
Error from server (Forbidden): pods "nuevo" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nuevo" must set securityContext.allowPrivilegeEscalati
[código de salida: 1]

$ kubectl delete namespace nivel-previo
namespace "nivel-previo" deleted
```

A linha do `label` traz o aviso do controlador, que nomeia o Pod `viejo` e as regras que ele viola. E o `get pod` seguinte o deixa `Running`: **o rótulo informou e não despejou**. O Pod `nuevo`, pedido com o mesmo manifesto, é rejeitado. Pôr `enforce` não limpa um namespace; fecha a porta para o que chegar a partir desse momento. Um Pod velho que viola o nível fica até ser recriado (por exemplo, com um `rollout restart`), e então já não pode nascer. É uma armadilha de operação: em um namespace com `enforce`, um reinício pode derrubar um Deployment que funcionava havia meses, se o modelo dele nunca cumpriu o nível.

Outra prova do mesmo estilo, desta vez com o modo `warn`. Pede-se ao `kube-apiserver`, sem aplicar a mudança, que tire uma linha do `revisor` (o perfil `seccomp`) e diga o que acha:

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/securityContext/seccompProfile"}]' --dry-run=server
Warning: would violate PodSecurity "restricted:v1.37": seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/revisor patched

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}{"\n"}'
RuntimeDefault
```

O patch **é aceito** (`deployment.apps/revisor patched`, mas é `--dry-run=server`: nada foi gravado) e vem com um aviso em uma única linha: `would violate PodSecurity "restricted:v1.37": seccompProfile …`. Isso é o `warn`: avisa quem aplica, sem rejeitar. O segundo comando confirma que o Deployment continua dizendo `RuntimeDefault`. E essa diferença, “avisa” contra “rejeita”, é o erro seguinte.

### O erro que a gente vai ver

O erro desta lição é dos que mais desconcertam, porque o comando sai **bem** e o serviço não aparece. Ele é provocado com `fig07_01.sin-reglas.yaml`, um **programa** que falha de propósito: um Deployment do `revisor` escrito como em um tutorial, sem `securityContext`.

```yaml
# fig07_01.sin-reglas.yaml — FALLA A PROPÓSITO: un Deployment del revisor escrito
# como en un tutorial cualquiera, SIN securityContext. La imagen ya corre sin ser
# root (usuario 65532), pero el manifiesto no lo DECLARA. En el espacio «revisor»
# (nivel restricted) el Deployment se crea con una advertencia y sus Pods no
# nacen: el ReplicaSet registra FailedCreate. Se borra con kubectl delete -f.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sinreglas
  labels:
    app: sinreglas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sinreglas
  template:
    metadata:
      labels:
        app: sinreglas
    spec:
      containers:
      - name: revisor
        image: curso-docker-revisor:1.6.0
        imagePullPolicy: IfNotPresent
        env:
        - name: REVISOR_SERVICIOS
          value: "prueba http://prueba:9000/ 2s"
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
```

A imagem roda, sim, sem ser `root` (usuário 65532), mas o manifesto não declara isso, e é isso que o nível `restricted` revisa. Aplica-se no namespace da lição:

```text
$ kubectl apply -n revisor -f fig07_01.sin-reglas.yaml
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/sinreglas created

$ kubectl wait --for=condition=ReplicaFailure deployment/sinreglas -n revisor --timeout=120s
deployment.apps/sinreglas condition met

$ kubectl get deployment sinreglas -n revisor
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
sinreglas   0/1     0            0           1s

$ kubectl get replicaset -n revisor -l app=sinreglas
NAME                   DESIRED   CURRENT   READY   AGE
sinreglas-7c585c788d   1         0         0       1s

$ kubectl get pods -n revisor -l app=sinreglas
No resources found in revisor namespace.

$ kubectl describe replicaset -n revisor -l app=sinreglas | sed -n '/^Events:/,$p' | head -4
Events:
  Type     Reason        Age   From                   Message
  ----     ------        ----  ----                   -------
  Warning  FailedCreate  2s    replicaset-controller  Error creating: pods "sinreglas-7c585c788d-47khh" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Lê-se em ordem, do sintoma à causa.

**Primeiro, o que o `apply` disse.** Duas linhas: um aviso (`Warning: would violate PodSecurity "restricted:v1.37": …`) e `deployment.apps/sinreglas created`. **Foi criado.** O Deployment é um objeto, não um Pod, e não viola nada. O aviso é o modo `warn`, que sim revisa o modelo de Pod que o Deployment leva dentro, para avisar antes. Se o terminal ou o *pipeline* não mostra os avisos, aqui o aviso passou em branco. Isto é o que a documentação diz: os modos `audit` e `warn` se aplicam também aos recursos de carga de trabalho, mas **o `enforce` não**: ele só se aplica aos Pods resultantes.

**Segundo, o sintoma.** O `kubectl wait` espera uma condição pouco comum, `ReplicaFailure`, que o Deployment ativa quando o seu ReplicaSet não consegue criar réplicas, e a encontra na hora. Depois: `READY 0/1`, `UP-TO-DATE 0`, `AVAILABLE 0`. O ReplicaSet existe e pede 1 Pod, `DESIRED 1`, mas tem `CURRENT 0`. E `get pods` diz `No resources found`. O Deployment nunca falhou em voz alta; simplesmente não tem Pods.

**Terceiro, a causa.** Está nos eventos do ReplicaSet, não nos do Deployment nem nos do Pod (que não existe): `Warning FailedCreate … replicaset-controller Error creating: pods "sinreglas-…" is forbidden: violates PodSecurity "restricted:v1.37": …`. É a mesma mensagem de 7.3.3, mas agora quem a recebe é o controlador, que a registra e tenta de novo. Por isso é preciso procurar no **ReplicaSet**.

**A correção.** Corrige-se o manifesto, não o namespace: um `securityContext` como o do `revisor` e o do serviço de teste, com as quatro linhas de 7.3.3. Aqui, como o Deployment não vai ser usado, ele é apagado.

```text
$ kubectl delete -n revisor -f fig07_01.sin-reglas.yaml
deployment.apps "sinreglas" deleted from revisor namespace
```

**A ordem, quando um Deployment não tem Pods:**

1. `kubectl get deployment`: `READY 0/N`?
2. `kubectl get replicaset -l app=…`: `CURRENT` menor que `DESIRED`?
3. `kubectl describe replicaset`: os eventos, `FailedCreate`, e o motivo completo.
4. Se disser `PodSecurity`, não se baixa o nível do namespace; corrige-se o manifesto.


### 7.4 Contas de serviço e permissões mínimas

#### 7.4.1 O que é uma conta de serviço

Quando se faz `kubectl get pods`, a API sabe quem a pessoa é pelo `kubeconfig`. Quando um **programa que roda dentro do cluster** fala com a API (um controlador, uma ferramenta de implantação, um serviço que precisa saber que outros Pods existem), a API também precisa saber quem ele é. Essa identidade se chama **conta de serviço** (*ServiceAccount*). A [documentação](https://kubernetes.io/docs/concepts/security/service-accounts/) a define como “um tipo de conta não humana que, no Kubernetes, dá uma identidade distinta dentro do cluster”. Tem três propriedades que importam aqui:

- **É um objeto com namespace**, como um Pod. Chama-se `revisor` no namespace `revisor`, e o seu nome completo para o RBAC tem a forma `system:serviceaccount:<namespace>:<conta>`, que para a conta `revisor` do namespace `revisor` fica `system:serviceaccount:revisor:revisor` (o nome se repete porque coincidem). Será escrito em 7.4.3.
- **Todo namespace nasce com uma chamada `default`.** O cluster a cria sozinho (a seção 7.3.2 acabou de esperá-la) e a atribui a todo Pod que não peça outra. Por padrão não tem permissões além da descoberta básica da API.
- **Por padrão, o cluster monta as credenciais dela em cada Pod.** A mesma página: “por padrão, o Kubernetes dá ao Pod as credenciais da conta atribuída”. Desde a versão 1.22 são um token de vida curta que se renova sozinho, entregue como um volume projetado; antes era um Secret de vida longa. Esse é o volume `kube-api-access-…` visto em 7.1.3: o Pod pode ler o seu token em um arquivo e se apresentar com ele diante da API.

O fato do último ponto é o importante. **Se um programa dentro de um Pod está comprometido, a primeira pergunta dele é “o que eu posso fazer com o token que tenho?”**, e essa credencial está montada mesmo que o programa nunca a use. Para o `revisor` e para o `prueba`, que não falam com a API, é um risco sem nenhum benefício. Por isso os dois Deployments da lição declaram `automountServiceAccountToken: false`. O [guia de contas de serviço](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) explica que isso pode ser desativado na conta ou no Pod, e que, se os dois dizem alguma coisa, manda o Pod.

#### 7.4.2 As permissões: `Role` e `RoleBinding`

Uma conta recém-criada não pode nada. As permissões são adicionadas com dois objetos. A [documentação do RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (controle de acesso baseado em papéis) os separa assim: um `Role` “contém regras que representam um conjunto de permissões”, e as permissões são **puramente aditivas**: não existem regras de “negar”. Um `Role` “sempre define permissões dentro de um namespace”. O seu parente `ClusterRole` é o mesmo, mas sem namespace, para recursos que não têm um (os nós, por exemplo) ou para repetir um conjunto de regras em vários namespaces. Um `RoleBinding` é a cola: “concede as permissões definidas em um papel a um conjunto de sujeitos” (usuários, grupos ou contas de serviço), dentro de um namespace. Dois objetos e não um porque o papel se escreve uma vez e pode ser ligado a muitas contas.

Cada regra de um `Role` tem três partes: `apiGroups` (o grupo da API: `""` é o core, onde vivem os Pods e os Services; `apps` é onde vivem os Deployments), `resources` (os tipos) e `verbs` (o que se pode fazer: `get` ler um, `list` listar, `watch` ficar escutando mudanças, e os que modificam, `create`, `update`, `patch` e `delete`). Leia-se no `cuentas.yaml`, completo:

```yaml
# cuentas.yaml — Lección 7: cada carga con su cuenta, y ninguna con permisos que
# no necesita. El revisor y prueba no le hablan a la API: cero permisos y sin
# credenciales montadas. «observador» puede mirar y nada más.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: revisor
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prueba
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: observador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: observador
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: observador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: observador
subjects:
- kind: ServiceAccount
  name: observador
  namespace: revisor
```

Três contas e um par de objetos de permissões. `revisor` e `prueba` são contas **sem permissões**: nenhum `RoleBinding` as menciona, e as duas levam `automountServiceAccountToken: false` também no nível da conta. `observador` é a conta de leitura: o `Role` `observador` lhe dá `get`, `list` e `watch`, só esses três verbos, sobre Pods, os logs deles (`pods/log`, um subrecurso), Services e eventos do core, e sobre Deployments e ReplicaSets do grupo `apps`. Repare no que **não** está: Secrets (o token do `revisor` é um Secret), `create`, `update`, `patch`, `delete`, `exec` (`pods/exec` é outro subrecurso, e não está listado) e qualquer coisa fora do namespace. A regra de projeto é “o que precisa, e nada mais”, e se escreve nomeando cada recurso, sem curingas (`*`), porque um curinga inclui o que um dia o cluster adicionar.

O `RoleBinding` diz a **quem** se dá: a conta `observador` do namespace `revisor`. Mesmo assim, essa conta não é usada por nenhum Deployment da lição. Existe para que se veja o que significa “somente leitura” com uma conta de verdade, e para o Exercício 2.

```text
$ kubectl get serviceaccounts -n revisor
NAME         AGE
default      5m2s
observador   5m2s
prueba       5m2s
revisor      5m2s

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name'
POD                        CUENTA    AUTOMOUNT   VOLUMENES
prueba-6899c74865-rgh68    prueba    false       <none>
revisor-5d6fd4d6bd-6kb4k   revisor   false       datos,token
revisor-5d6fd4d6bd-jdmx8   revisor   false       datos,token
revisor-5d6fd4d6bd-pj8r9   revisor   false       datos,token
```

Lê-se assim: quatro contas, não três. A quarta, `default`, foi criada pelo próprio cluster. E a tabela de Pods diz, para cada um, com que conta roda, que `AUTOMOUNT` é `false` e que volumes tem: `datos` e `token` no `revisor`, nenhum no `prueba`, e **nenhum dos dois tem o `kube-api-access-…` de 7.1.3**. Comparado com o “antes”, esse volume desapareceu.

```text
$ kubectl get role,rolebinding -n revisor -o wide
NAME                                        CREATED AT
role.rbac.authorization.k8s.io/observador   2026-10-21T22:52:57Z

NAME                                               ROLE              AGE    USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/observador   Role/observador   5m3s                    revisor/observador

$ kubectl describe role observador -n revisor
Name:         observador
Labels:       <none>
Annotations:  <none>
PolicyRule:
  Resources         Non-Resource URLs  Resource Names  Verbs
  ---------         -----------------  --------------  -----
  events            []                 []              [get list watch]
  pods/log          []                 []              [get list watch]
  pods              []                 []              [get list watch]
  services          []                 []              [get list watch]
  deployments.apps  []                 []              [get list watch]
  replicasets.apps  []                 []              [get list watch]
```

#### 7.4.3 Perguntar sem testar: `kubectl auth can-i`

Como saber o que uma conta pode fazer? Pergunta-se à API com `kubectl auth can-i`, que responde `yes` ou `no`. Para perguntar por **outra** identidade usa-se `--as`, que faz o `kubectl` personificar (*impersonate*) essa identidade na requisição; a conta de serviço se escreve com o nome completo, `system:serviceaccount:<namespace>:<conta>`. (Personificar é uma permissão que a gente tem como administrador do próprio cluster de kind; um usuário normal de um cluster real não a teria.) Primeiro o `revisor`, que não deve poder nada, e o `observador`, que deve poder ler:

```text
$ kubectl auth can-i --list -n revisor --as=system:serviceaccount:revisor:revisor | head -5
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
clustertrustbundles.certificates.k8s.io         []                                     []               [get list watch]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador
yes

$ kubectl auth can-i get pods --subresource=log -n revisor --as=system:serviceaccount:revisor:observador
yes
```

A lista do `revisor` não está vazia, e isso precisa ser lido com cuidado. As quatro linhas são permissões que quase toda identidade recebe por padrão. Três são *revisões sobre si mesmo*: `selfsubjectreviews` (quem eu sou?, segundo o `kubectl explain`, devolve as informações de usuário que o `kube-apiserver` tem de quem pergunta), `selfsubjectaccessreviews` (eu posso fazer isto?, que é a pergunta que o próprio `can-i` faz) e `selfsubjectrulesreviews` (que ações eu posso fazer neste namespace?). A quarta, `clustertrustbundles`, são pacotes de certificados raiz públicos; a descrição do tipo diz que todas as contas de serviço podem lê-los por padrão. Os papéis que dão as três primeiras vêm com o cluster (`system:basic-user`, que a documentação descreve como acesso somente leitura a informações básicas sobre si mesmo, ligado ao grupo `system:authenticated`). Nenhuma é uma permissão sobre **os nossos** objetos. A pergunta que importa, `get pods`, responde `no`, com código de saída 1: o `kubectl auth can-i` devolve 0 quando a resposta é `yes` e 1 quando é `no`, e isso serve para usá-lo em um script. O `observador` responde `yes` a ler Pods e a ler os logs deles (`--subresource=log`). Agora o que **não** deve poder:

```text
$ kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get pods -n default --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]
```

Três `no`: não pode apagar Pods (o `Role` não inclui `delete`), não pode ler Secrets (não estão na lista) e não pode ler Pods de `default` (o `Role` e o `RoleBinding` vivem em `revisor`; um papel de namespace não cruza para outro). É a prova direta de que o namespace é, sim, a unidade das permissões, ainda que não seja a da rede.

O `can-i` pergunta; a requisição de verdade confirma. Com `--as`, o `kubectl` faz a operação como se fosse essa conta:

```text
$ kubectl get deployments -n revisor --as=system:serviceaccount:revisor:observador
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
prueba    1/1     1            1           5m5s
revisor   3/3     3            3           5m5s

$ kubectl delete pod -n revisor -l app=prueba --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): pods "prueba-6899c74865-rgh68" is forbidden: User "system:serviceaccount:revisor:observador" cannot delete resource "pods" in API group "" in the namespace "revisor"
[código de salida: 1]

$ kubectl get secrets -n revisor --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"
[código de salida: 1]
```

Listar Deployments funciona. Apagar um Pod e listar Secrets dão `Error from server (Forbidden)`, e vale a pena ler a mensagem completa, porque tem a forma dos erros de RBAC e é o que se vai ver no dia em que algo falhar: `secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"`. Quem (`User "system:serviceaccount:revisor:observador"`), que verbo e sobre o quê (`cannot list resource "secrets"`), em que grupo da API (`""`, o core) e em que namespace. Com essas cinco peças sabe-se exatamente que regra adicionar se a permissão era legítima, ou o que deixar como está se não era. Um detalhe: o verbo da segunda mensagem é `list`, não `get`; foram pedidos “todos os Secrets”, e isso é `list`. Ler um por nome é `get`. Os dois verbos são separados de propósito.

#### 7.4.4 O mesmo, de dentro de um Pod

Até aqui tudo foi testado personificando a partir do terminal. Falta a prova que mais se parece com um ataque: um programa **dentro** de um Pod, com o que o Pod tem à mão. Usam-se três Pods de apoio, todos de `curl`: `depurar` (o da Lição 3, com o rótulo `acceso-revisor: permitido` de que a rede vai precisar), `intruso` (igual, mas **sem** esse rótulo; é o Pod da equipe de dados da cena) e `lector`, um novo que leva a conta `observador` **com o token montado**. Os três cumprem o `restricted`, como tudo o que nasça neste namespace. Leia o `fig07_04.lector.yaml`:

```yaml
# fig07_04.lector.yaml — un Pod que SÍ lleva credenciales: usa la cuenta «observador»
# y pide que se le monte su token (automountServiceAccountToken: true). Sirve para
# ver, desde dentro de un Pod, lo que el RBAC de cuentas.yaml permite y lo que no.
# Cumple «restricted». Se aplica con: kubectl apply -n revisor -f fig07_04.lector.yaml
apiVersion: v1
kind: Pod
metadata:
  name: lector
  labels:
    app: lector
spec:
  restartPolicy: Never
  serviceAccountName: observador
  automountServiceAccountToken: true
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: lector
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

É uma exceção deliberada à regra de 7.4.1: `automountServiceAccountToken: true`, que é o valor padrão escrito em voz alta. Existe para mostrar o que um token montado permite. Leia-se contra a lista do `intruso`, que usa a conta `default` **sem** token (`depurar` e `intruso` o declaram desligado):

```text
$ kubectl apply -n revisor -f depurar.yaml -f intruso.yaml -f fig07_04.lector.yaml
pod/depurar created
pod/intruso created
pod/lector created

$ kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso pod/lector --timeout=180s
pod/depurar condition met
pod/intruso condition met
pod/lector condition met

$ kubectl exec -n revisor lector -- /bin/ls /var/run/secrets/kubernetes.io/serviceaccount
ca.crt
namespace
token
```

O `lector` tem três arquivos em `/var/run/secrets/kubernetes.io/serviceaccount`: `ca.crt` (o certificado com o qual reconhecer a API), `namespace` (o seu namespace) e `token` (a sua credencial). Com eles, o `curl` se apresenta diante da API com o cabeçalho `Authorization: Bearer <token>`. O endereço é `https://kubernetes.default.svc`, o nome do Service `kubernetes` de `default`, que é o ponto de entrada da API para os Pods. Quatro requisições:

```text
$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 200

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "secrets %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets'
secrets 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods-default %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/default/pods'
pods-default 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets | grep -E "message|code"'
  "message": "secrets is forbidden: User \"system:serviceaccount:revisor:observador\" cannot list resource \"secrets\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

Um `200` e três `403`. Com o token do `observador`, o `lector` **consegue** listar os Pods de `revisor` (a permissão que demos), e **não** consegue listar os Secrets do mesmo namespace nem os Pods de `default`. O quarto bloco é a mesma requisição de Secrets com a resposta crua filtrada: é o JSON de erro da API, com a mesma mensagem vista com `--as`. Isto é o que o RBAC promete, mas visto do lado de quem ataca: um token roubado do `observador` tem o alcance do `Role` e nem um recurso a mais. Por isso o `Role` se escreve curto.

E agora o Pod que **não** tem token:

```text
$ kubectl exec -n revisor intruso -- sh -c '/bin/ls /var/run/secrets/kubernetes.io; echo código=$?' 2>&1
ls: /var/run/secrets/kubernetes.io: No such file or directory
código=1

$ kubectl exec -n revisor intruso -- sh -c 'curl -s -k https://kubernetes.default.svc/api/v1/namespaces/revisor/pods | grep -E "message|code"'
  "message": "pods is forbidden: User \"system:anonymous\" cannot list resource \"pods\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

O diretório não existe: `ls: /var/run/secrets/kubernetes.io: No such file or directory`. O `intruso` não tem nem sequer uma credencial para apresentar. Se mesmo assim ele fala com a API (`curl -k`, que não verifica o certificado, só para este teste), a API o recebe como `system:anonymous`, a identidade de quem não se identifica, e responde `403`: `pods is forbidden: User "system:anonymous" cannot list resource "pods"`. Zero permissões e zero credenciais; é o estado que se quer para todo Pod que não fala com a API. (Que a API responda `403` quer dizer que o `intruso` **chegou** à API: a única coisa que o freia aqui é o RBAC. O que impediria que ele chegasse é a rede, e 7.5 mede isso.)


### 7.5 A rede: aberta até que alguém a feche

#### 7.5.1 O modelo, antes de tocar em qualquer coisa

A [documentação de políticas de rede](https://kubernetes.io/docs/concepts/services-networking/network-policies/) descreve o modelo com três frases que convém aprender de cor, porque delas sai todo o resto:

- **Por padrão, um Pod não é isolado.** “Por padrão, um Pod não é isolado para a saída; todas as conexões de saída são permitidas”, e o mesmo para a entrada: “todas as conexões de entrada são permitidas”. Este é o estado em que os Pods estão hoje.
- **Um Pod é isolado quando uma política o seleciona.** “Um Pod é isolado para a saída se há alguma `NetworkPolicy` que o seleciona e tem `Egress` nos seus `policyTypes`”, e de forma equivalente para a entrada com `Ingress`. As duas direções são isoladas separadamente. Uma política que só diz `Ingress` não toca a saída.
- **As políticas se somam.** “As políticas de rede não entram em conflito; são aditivas.” Se várias políticas se aplicam a um Pod em uma direção, o permitido é a **união** do que cada uma permite. A ordem não importa. E não existe regra de “negar”: o que nenhuma permite é proibido, mas só para os Pods que já estão isolados.

Uma política tem quatro partes: um `podSelector` (a que Pods **do namespace** se aplica; `{}` significa todos), uns `policyTypes` (se isola a entrada, a saída ou as duas), e listas `ingress` e `egress` do que se **permite**, cada uma com um `from` ou um `to` (de onde ou para onde) e uns `ports`. E o `from` ou o `to` podem ser três coisas: um `podSelector` (Pods **deste** namespace), um `namespaceSelector` (todos os Pods dos namespaces escolhidos) ou, juntos no mesmo elemento, ambos (Pods escolhidos de namespaces escolhidos). Um detalhe que morde: o `from` é uma lista, e cada elemento da lista é uma alternativa (um **ou**); o que vai dentro de um mesmo elemento se combina com **e**.

E a condição que mais importa: a própria documentação adverte que “os clusters devem usar um plugin de rede que suporte `NetworkPolicy`” e que “criar um recurso `NetworkPolicy` sem um controlador que o implemente não tem efeito”. O cluster guarda a política sem reclamar, e o tráfego continua passando. É uma falha silenciosa. Por isso o plano do curso dizia “se o plugin de rede do kind não a aplicar, instala-se outro”. Mede-se, não se supõe.

#### 7.5.2 Quem as aplica no kind?

Os nós do kind usam por padrão um plugin de rede chamado `kindnetd` (a [configuração do kind](https://kind.sigs.k8s.io/docs/user/configuration/) o descreve como uma implementação simples de rede baseada em plugins CNI padrão; *CNI* é a interface com a qual o Kubernetes pede a um plugin que dê rede aos Pods). Pergunta-se ao cluster o que roda:

```text
$ kubectl get daemonset -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kindnet      3         3         3       3            3           kubernetes.io/os=linux   17m
kube-proxy   3         3         3       3            3           kubernetes.io/os=linux   17m

$ kubectl get daemonset kindnet -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
docker.io/kindest/kindnetd:v20260820-69b56db7
```

Há um DaemonSet `kindnet` com um Pod por nó, e a imagem dele é `kindest/kindnetd:v20260820-69b56db7`. Saber qual é não diz se aplica políticas. As notas da versão [v0.24.0 do kind](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0) anunciam, entre os pontos principais, “suporte a políticas de rede usando `sigs.k8s.io/kube-network-policies`”. Isso é o que o papel diz. O que importa é o que o cluster mede, e para medir é preciso uma testemunha: dois Pods de `curl` que não estão na lista de ninguém.

```text
$ kubectl apply -n default -f intruso.yaml
pod/intruso created

$ kubectl wait -n default --for=condition=Ready pod/intruso --timeout=180s
pod/intruso condition met

$ kubectl get pods -A -l 'app in (depurar,intruso,lector)' -L acceso-revisor
NAMESPACE   NAME      READY   STATUS    RESTARTS   AGE   ACCESO-REVISOR
default     intruso   1/1     Running   0          1s    
revisor     depurar   1/1     Running   0          14s   permitido
revisor     intruso   1/1     Running   0          14s   
revisor     lector    1/1     Running   0          13s   
```

Há um `intruso` em `revisor` e outro em `default`: o do namespace próprio é o Pod da equipe de dados da cena; o de `default` é outra equipe qualquer do cluster. Os dois nasceram sem o rótulo `acceso-revisor`. O `depurar` o tem (`permitido`); `intruso` e `lector` não, e a tabela diz isso com a coluna vazia. Isso importa em 7.5.4.

#### 7.5.3 Sem regras: o que o namespace NÃO isola

Com as seis políticas retiradas (7.2.3), isto é o que pode fazer o `intruso` de `revisor`, e o que pode fazer o de `default`:

```text
$ kubectl get networkpolicy -n revisor
No resources found in revisor namespace.

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://prueba:9000/
sano

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez
ok

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

Leem-se quatro respostas e as quatro são más notícias:

1. O `intruso` fala com o `revisor` e recebe o `/salud` dele. Sem o token não consegue pedir o relatório (dá `401`), mas chegou.
2. Fala com `prueba:9000`, que não é dele, e recebe `sano`, o modo do serviço de teste. Com um `POST` em `/modo/caido` poderia colocá-lo em `caido`: o serviço de teste **não tem autenticação** e a rede não o protege.
3. Fala com a API do cluster, em `/livez`, e ela responde `ok`. Esse caminho de saúde responde sem credenciais de propósito (a documentação do RBAC o chama de informação não sensível, o papel `system:public-info-viewer`), então a resposta não é um defeito da API. O que importa é outra coisa: um Pod qualquer tem **rota de rede** até o `kube-apiserver` (pelo Service `kubernetes`, porta 443), e ninguém a tirou.
4. O `intruso` de `default` alcança o `revisor` de `revisor` escrevendo o nome completo do Service, `revisor.revisor.svc.cluster.local`. **Dois namespaces diferentes, e nem uma parede entre eles.** Isto é o que a documentação de namespaces não afirma e o que muita gente assume.

É a resposta à segunda pergunta das 5h58, e não é a que se queria: sim, um Pod da equipe de dados pode falar com o `revisor` sem passar pelo ponto de entrada.

#### 7.5.4 Tudo fechado

A primeira política fecha tudo, sem nenhuma abertura. É um **programa** curto:

```yaml
# fig07_02.cerrado.yaml — la primera regla de red.yaml, sola: cierra la entrada
# y la salida de TODOS los Pods del espacio donde se aplica, sin ninguna apertura.
# Se aplica con -n revisor para ver qué se rompe (hasta el DNS), y después se
# completa con red.yaml. No forma parte de la kustomization.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

`podSelector: {}` seleciona todos os Pods do namespace, e `policyTypes: [Ingress, Egress]` os isola nas duas direções. Como não há listas `ingress` nem `egress`, nada é permitido. Aplica-se e mede-se o mesmo de antes:

```text
$ kubectl apply -n revisor -f fig07_02.cerrado.yaml
networkpolicy.networking.k8s.io/cerrado created

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- timeout 8 nslookup revisor.revisor.svc.cluster.local
;; connection timed out; no servers could be reached

command terminated with exit code 1
[código de salida: 1]

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Tudo deixou de funcionar, e convém separar três sinais que se parecem. `command terminated with exit code 28` é o código do `curl` para **tempo esgotado**: não houve resposta nos 3 segundos que foram dados com `-m 3`. Um `curl` contra uma política que descarta pacotes não recebe uma recusa, só silêncio. É diferente de `connection refused` (código 7, em que alguém responde dizendo “aqui não tem nada”, o que apareceu nas Lições 3 e 5) e de um `403` (em que alguém que de fato escutou responde que não). Há três tipos de “não”, e eles se distinguem pelo código. Segundo sinal: o `depurar`, o Pod **com** o rótulo, também não chega. Ainda não foi aberto nada. Terceiro: o `nslookup` também estourou o tempo, `;; connection timed out; no servers could be reached`. **A consulta de nomes é tráfego de rede** que sai do Pod para o DNS do cluster, e a política `cerrado` também fechou isso. Com a saída fechada, os Pods do namespace não conseguem perguntar quem é `revisor`.

Entre o `apply` e os testes há uma espera de 8 segundos (`$ sleep 8`, à vista na saída completa de `correr.salida.txt`); 7.5.7 mede quanto tempo uma política leva para ser programada, e daí sai a margem.

Há mais efeitos, que se medem com três comandos a partir da máquina e um a partir do Pod que lê a API:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
000
[código de salida: 28]

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ sleep 3
Forwarding from 127.0.0.1:18087 -> 8080

$ curl -s -m 8 -H 'Authorization: Bearer …' 'http://127.0.0.1:18087/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     1.998s  se acabo el tiempo de espera

$ kubectl exec -n revisor lector -- sh -c 'curl -s -m 3 -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 000
command terminated with exit code 28
[código de salida: 28]
```

O ponto de entrada deixou de entrar: o cliente de fora recebe `000` e código 28. A política `cerrado` isola a entrada de **todos** os Pods do namespace, inclusive o `revisor`, e os Pods do Envoy (que vivem em outro namespace) ficaram sem permissão para falar com ele. O `port-forward`, em compensação, **continua funcionando**: o túnel foi aberto e o `revisor` respondeu. (O [guia do `port-forward`](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) não descreve por que caminho ele viaja; mas diz algo útil para esta lição: o acesso ao `port-forward` é controlado pelo RBAC, com a permissão `create` sobre `pods/portforward`, então quem a tiver entra no Pod mesmo com a rede fechada.) Mas o que o `revisor` responde já não é o relatório completo: a tabela diz `prueba FALLA` com o detalhe `se acabo el tiempo de espera`, porque o `revisor` não consegue sair para perguntar ao `prueba`. A saída do próprio `revisor` também está fechada. E o `lector`, o Pod com token válido, já não chega à API: `pods 000`, código 28. **A rede fechada protege a API de quem tem permissão.** O RBAC diz o que se *pode* pedir; a rede diz aonde se *chega*. As duas precisam dizer que sim.

Uma dúvida razoável neste ponto: se tudo está fechado, as probes não deveriam falhar? Não falham. As probes são executadas pelo `kubelet` do nó (Lição 5), e a documentação de políticas de rede diz que, quando um Pod é isolado para a entrada, “as únicas conexões permitidas para o Pod são as que vêm do nó do Pod e as que a lista `ingress` de alguma política permite”. O tráfego do próprio nó fica fora do filtro. Verifica-se com as seis regras em vigor, 45 segundos depois, em 7.5.5.

#### 7.5.5 As aberturas necessárias

Agora as outras cinco políticas, que juntas com `cerrado` formam o `red.yaml`. Leiam-se uma por uma antes de aplicá-las; cada uma tem um comentário que diz a quem abre e por quê:

```yaml
# red.yaml — Lección 7: todo cerrado por defecto, y solo las aperturas necesarias.
# ⚠️ Que el clúster APLIQUE estas reglas depende de la red (CNI). kindnet, la red
# de kind desde la v0.24.0, sí las aplica: la Lección 7 lo mide con intruso y
# depurar. Con un CNI que no las aplique, estos objetos se guardan y no hacen nada.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# Todos pueden preguntarle al DNS del clúster (si no, ningún nombre resuelve).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
---
# El revisor sale solo hacia prueba:9000.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-salida
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: prueba
    ports:
    - {protocol: TCP, port: 9000}
---
# prueba solo recibe del revisor.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prueba-entrada
spec:
  podSelector:
    matchLabels:
      app: prueba
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 9000}
---
# Al revisor solo entran los Pods marcados «acceso-revisor: permitido» y los
# Envoy de la puerta (Lección 6), que viven en el espacio envoy-gateway-system.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-entrada
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          acceso-revisor: permitido
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: envoy-gateway-system
    ports:
    - {protocol: TCP, port: 8080}
---
# …y esos mismos Pods pueden SALIR hacia el revisor:8080. Con «cerrado» también
# la salida está prohibida: abrir solo la entrada del revisor no basta (medido).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: acceso-revisor-salida
spec:
  podSelector:
    matchLabels:
      acceso-revisor: permitido
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 8080}
```

Em ordem:

- **`cerrado`**: a de cima. Com `podSelector: {}` e os dois tipos, deixa todos os Pods do namespace sem entrada nem saída.
- **`dns`**: abre a **saída** de todos os Pods para o DNS. O destino se escreve com as duas condições juntas em um único elemento (`namespaceSelector` **e** `podSelector`): os Pods com o rótulo `k8s-app: kube-dns` do namespace `kube-system`. As portas são 53 sobre UDP e sobre TCP. O namespace é selecionado com o rótulo `kubernetes.io/metadata.name`, que o cluster põe sozinho em todo namespace, com o nome dele; a documentação adverte que não se pode escrever o nome de um namespace diretamente em uma política e que esse rótulo existe para isso.
- **`revisor-salida`**: a **saída** do `revisor` para os Pods com `app: prueba`, só na porta 9000. É a única coisa de que o `revisor` precisa da rede: consultar o `prueba`.
- **`prueba-entrada`**: a **entrada** do `prueba`, só a partir dos Pods `app: revisor`, e só na 9000. A política de saída do `revisor` e a de entrada do `prueba` são duas metades de uma mesma porta: para o tráfego passar, as duas direções precisam dizer que sim.
- **`revisor-entrada`**: a **entrada** do `revisor`, na porta 8080, a partir de duas origens (dois elementos de `from`, ou seja, uma **ou** a outra): os Pods com o rótulo `acceso-revisor: permitido` (deste namespace) e **todos os Pods** do namespace `envoy-gateway-system`, onde vive o ponto de entrada da Lição 6.
- **`acceso-revisor-salida`**: a **saída** dos Pods com o rótulo `acceso-revisor: permitido` para o `revisor`, porta 8080. É o par da anterior. Existe por uma lição que custou uma primeira versão desta rede: abrir só a entrada do `revisor` não basta, porque `cerrado` também fecha a saída de quem quer falar com ele.

Duas observações antes de aplicá-las. O rótulo `acceso-revisor: permitido` faz de **chave**: quem o levar pode falar com o `revisor`, e quem tiver permissão de criar Pods no namespace o põe em um Pod. Por isso o rótulo não é um segredo, e sim um acordo, e 7.5.8 o comenta. E as políticas usam a porta `8080`, a do contêiner, **não** a 80 do Service. Não é uma decisão deste cluster: a [referência da API](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/) define o campo `port` de uma política como “uma porta numérica ou nomeada de um Pod”. O Service já escolheu a réplica e traduziu a porta antes que a política olhe o pacote; a política vê o destino final. Aqui se mediu que o kindnet cumpre isso (se não, o `depurar` não teria chegado), e em outro cluster vale medir do mesmo jeito, porque o que se verifica é que o plugin aplique a API, não qual porta manda.

```text
$ kubectl apply -n revisor -f red.yaml
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns created
networkpolicy.networking.k8s.io/revisor-salida created
networkpolicy.networking.k8s.io/prueba-entrada created
networkpolicy.networking.k8s.io/revisor-entrada created
networkpolicy.networking.k8s.io/acceso-revisor-salida created

$ kubectl get networkpolicy -n revisor
NAME                    POD-SELECTOR               AGE
acceso-revisor-salida   acceso-revisor=permitido   8s
cerrado                 <none>                     50s
dns                     <none>                     8s
prueba-entrada          app=prueba                 8s
revisor-entrada         app=revisor                8s
revisor-salida          app=revisor                8s

$ kubectl describe networkpolicy revisor-entrada -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     app=revisor
  Allowing ingress traffic:
    To Port: 8080/TCP
    From:
      PodSelector: acceso-revisor=permitido
    From:
      NamespaceSelector: kubernetes.io/metadata.name=envoy-gateway-system
  Not affecting egress traffic
  Policy Types: Ingress

$ kubectl describe networkpolicy cerrado -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Allowing egress traffic:
    <none> (Selected pods are isolated for egress connectivity)
  Policy Types: Ingress, Egress
```

`cerrado` saiu `unchanged` (já estava) e as outras cinco `created`. O `describe` de `revisor-entrada` o lê em linguagem simples: “permitindo tráfego de entrada na porta 8080/TCP, a partir de (PodSelector: `acceso-revisor=permitido`) e a partir de (NamespaceSelector: `kubernetes.io/metadata.name=envoy-gateway-system`); sem afetar a saída; tipo de política: Ingress”. Os dois `From:` são as duas alternativas. E o de `cerrado` repete, com outras palavras, o que já se sabia: “Pods selecionados: isolados para entrada e para saída”.

Agora o teste, com os mesmos comandos de sempre:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor depurar -- curl -s -m 3 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           9ms  200

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://prueba:9000/
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez

command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- nslookup revisor.revisor.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.revisor.svc.cluster.local
Address: 10.96.146.219

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Seis resultados, um por pergunta:

- **`depurar` (com o rótulo) chega ao `revisor`** e recebe o `/salud` dele, e com o token recebe o relatório completo: `prueba OK`. Isso quer dizer que o `revisor` voltou a poder sair para o `prueba` e que o `prueba` o aceita. São as duas metades.
- **`intruso` (sem o rótulo) não chega**: código 28. A resposta à segunda pergunta das 5h58 já é “não”.
- **`depurar` não chega a `prueba:9000`**: código 28. O rótulo abre o caminho para o `revisor`, não para o serviço de teste. Um Pod com a chave do `revisor` não é um Pod com a chave de tudo.
- **`intruso` não chega à API**: o `curl` estoura o tempo. A terceira pergunta já tem uma parede antes do RBAC.
- **O DNS responde**: o `intruso` resolve `revisor.revisor.svc.cluster.local` para o IP do Service. Um Pod sem chave pode perguntar por nomes (a regra `dns` é para todos) e recebe resposta, mas não consegue se conectar ao que encontra. Que o DNS funcione não quer dizer que o caminho esteja aberto.
- **O `intruso` de `default` também não chega**: o nome completo do Service já não lhe serve.

E as rotas legítimas que poderiam ter quebrado:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ curl -s -m 5 http://127.0.0.1:18087/salud   # por port-forward
{"estado":"vivo","version":"1.6.0"}
```

O ponto de entrada responde de novo a partir de fora, porque `revisor-entrada` admite os Pods de `envoy-gateway-system`. E o `port-forward` continua funcionando. Agora, com todas as regras em vigor, uma espera de 45 segundos, a de algumas voltas das probes da Lição 5, e uma olhada nos Pods:

```text
$ sleep 45

$ kubectl get pods -n revisor -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-6899c74865-rgh68    1/1     Running   0          7m15s
revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          7m15s
```

`RESTARTS 0` nos quatro, `1/1`. A rede fechada **não** derrubou as probes, e a razão é a da documentação que acabou de ser lida: quem as faz é o `kubelet`, a partir do nó.

#### 7.5.6 Para que serve cada regra: tira-se uma, mede-se, devolve-se

Ler uma política diz o que ela *deveria* fazer. Para saber o que ela faz, tira-se do cluster, **uma de cada vez**, e medem-se quatro coisas do mesmo lugar: o `depurar` pede o `/salud` ao `revisor`; o `depurar` pede o relatório (que obriga o `revisor` a sair para o `prueba`); o `depurar` resolve o nome do `revisor`; e o cliente de fora pede o `/salud` pelo ponto de entrada. Depois se aplica de novo o `red.yaml` e se passa à seguinte. O `nslookup` desta tabela é feito com um `sh -c` que imprime a última linha útil, ou `sin respuesta`, para caber em uma linha.

```text
$ kubectl delete networkpolicy dns -n revisor
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/salud
000
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- sh -c 'r=$(timeout 8 nslookup revisor.revisor.svc.cluster.local 2>&1 | grep -E "^Address: [0-9]|timed out" | tail -1); echo "${r:-sin respuesta}"'
;; connection timed out; no servers could be reached

$ curl -s -m 4 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
200
```

Essa é a primeira: sem `dns`, o nome `revisor` não se resolve, então a requisição a `/salud` e a do relatório estouram o tempo (código 28) e o `nslookup` também. O ponto de entrada, em compensação, responde `200`: o que se mediu é que o Envoy chega ao `revisor` mesmo com o DNS fechado para os Pods do namespace; como o Envoy encontra as réplicas é assunto do Envoy Gateway, e o curso não mediu. As outras quatro se leem igual. A tabela completa:

| Regra retirada | `depurar` → `/salud` | `depurar` → relatório | Resolver o nome | De fora, `/salud` |
|---|---|---|---|---|
| `dns` | 28 (esgotado) | 28 | esgotado | 200 |
| `revisor-salida` | 200 | `prueba FALLA`, esgotado | responde | 200 |
| `prueba-entrada` | 200 | `prueba FALLA`, esgotado | responde | 200 |
| `revisor-entrada` | 28 | 28 | responde | **000** (28) |
| `acceso-revisor-salida` | 28 | 28 | responde | 200 |
| (as seis em vigor) | 200 | `prueba OK` | responde | 200 |

Cada linha conta algo diferente. Tirar `revisor-entrada` é a única que derruba o ponto de entrada, porque é a que deixa o Envoy passar. Tirar `acceso-revisor-salida` deixa o `depurar` sem saída, mas o ponto de entrada continua (neste cluster ninguém criou políticas no namespace do Envoy, então ele não tem a saída fechada). Tirar `revisor-salida` ou `prueba-entrada` produz **o mesmo sintoma**, `prueba FALLA` por tempo esgotado, com causas diferentes: em um caso o `revisor` não consegue sair, no outro o `prueba` não consegue receber. E um sintoma assim não diz qual das duas políticas falta. É o tipo de falha para o qual o `describe networkpolicy` serve.

Os blocos completos dos cinco testes, com os seus comandos, estão em `correr.salida.txt`. Aqui vai o trecho que tem uma história, o de `revisor-salida`. Em uma execução anterior, que não foi guardada, essa linha saiu `prueba OK` mesmo sem a regra. Não foi possível repetir (nesta execução saiu `FALLA` de primeira) e não sabemos a causa. Há duas explicações possíveis e nenhuma foi comprovada. Uma: uma conexão que já estava aberta continuou viva com a regra retirada; a documentação de políticas de rede deixa esse caso a cada plugin (“fica definido pela implementação” se a mudança tem efeito sobre uma conexão existente) e recomenda não modificar políticas de modo que as afete. Outra: a política ainda não estava programada, que é o que 7.5.7 mede. Por isso o script espera, e aqui além disso **reinicia o `revisor`**, para que o teste abra uma conexão nova:

```text
$ kubectl delete networkpolicy revisor-salida -n revisor
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.001s  se acabo el tiempo de espera

$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 3 new replicas have been updated...
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

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera
```

Os dois relatórios dizem `prueba FALLA`: o de antes de reiniciar e o de depois. Nesta execução o reinício não mudou o resultado (o relatório já dizia `FALLA` antes); é uma precaução do método, não uma prova da causa.

A moral é de método, e vale mais do que a tabela. **Um resultado que diz “continua funcionando” depois de retirar uma regra não prova que a regra era desnecessária.** Pode ser uma conexão velha, um cache, ou um teste que não pergunta o que se acredita. Um teste de rede deve abrir uma conexão nova a cada vez.

### O erro que a gente vai ver (o segundo)

O segundo erro é o que mais tempo faz perder com as políticas de rede. Parece com a cena, mas em pequeno: há uma política que **abre** a entrada do `revisor`, há um Pod com o rótulo correto, e o Pod não chega. Ele é provocado apagando a última política, `acceso-revisor-salida`, que é o par da entrada:

```text
$ kubectl delete networkpolicy acceso-revisor-salida -n revisor
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl get networkpolicy -n revisor
NAME              POD-SELECTOR   AGE
cerrado           <none>         41s
dns               <none>         41s
prueba-entrada    app=prueba     41s
revisor-entrada   app=revisor    41s
revisor-salida    app=revisor    41s

$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          7m38s   acceso-revisor=permitido,app=depurar
```

Lê-se nesta ordem. **Primeiro, o sintoma:** código 28, tempo esgotado; o Pod tem o rótulo `acceso-revisor=permitido` e a política `revisor-entrada` existe. Tudo o que se olha diz que deveria passar. **Segundo, a lista de políticas:** estão `cerrado`, `dns`, `prueba-entrada`, `revisor-entrada` e `revisor-salida`; falta `acceso-revisor-salida`. **Terceiro, o princípio:** uma política de entrada abre um lado da porta. O Pod que quer chegar está isolado para a **saída** por `cerrado`, e nada a abre para ele. A primeira versão desta rede, que abria só a entrada, deixou o `depurar` sem poder sair. **A correção** é o arquivo, como sempre: `kubectl apply -k .` recria a que falta, e o `depurar` volta a chegar.

```text
$ kubectl apply -k . | grep networkpolicy
networkpolicy.networking.k8s.io/acceso-revisor-salida created
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

**A ordem, quando um Pod não chega a outro com políticas de rede:**

1. `kubectl exec … curl -m 3`: que código? 28 é silêncio de rede; 7 é que não há ninguém; 4xx ou 5xx é que chegou.
2. `kubectl get networkpolicy -n <namespace>` no namespace de **ambas** as pontas.
3. Para cada ponta, que políticas a selecionam e para que direção? Falta a saída de quem chama ou a entrada de quem recebe.
4. O nome se resolve? Se não, `dns`.
5. O rótulo está no Pod, ou no Deployment mas **não** no modelo do Pod?

#### 7.5.7 As políticas não são aplicadas instantaneamente

Até aqui, cada vez que o script muda uma política, ele espera antes de perguntar: são os `sleep 8` que aparecem nas saídas. Não são decoração, e esta seção conta de onde sai o oito. Uma espera de três segundos não bastou em uma das execuções de teste desta lição (dessa execução a saída não foi guardada): com as seis políticas já em vigor, o `intruso` pediu o `/livez` à API e recebeu `ok`, enquanto nas demais execuções essa mesma pergunta estourava o tempo. Nada estava quebrado: a pergunta foi feita **antes de a rede terminar de aprender** as políticas novas. Mediu-se de propósito. O script repete seis vezes esta sequência: apaga as seis políticas, espera um segundo, aplica-as de novo e, desde esse momento, pergunta seis vezes à API a partir do `intruso`, com um tempo máximo de um segundo por pergunta, anotando quantos segundos se passaram e que código recebeu:

```text
$ for ciclo in 1 2 3 4 5 6; do   # borrar las seis, esperar 1 s, volver a aplicarlas y preguntar seis veces a la API desde el intruso
ciclo 1: +0s:200 +0s:200 +0s:200 +2s:000 +3s:000 +6s:000
ciclo 2: +2s:000 +3s:000 +5s:000 +6s:000 +7s:000 +9s:000
ciclo 3: +0s:200 +1s:200 +1s:200 +2s:000 +7s:000 +10s:000
ciclo 4: +5s:000 +6s:000 +9s:000 +12s:000 +17s:000 +20s:000
ciclo 5: +6s:000 +9s:000 +12s:000 +15s:000 +19s:000 +23s:000
ciclo 6: +3s:000 +6s:000 +9s:000 +12s:000 +13s:000 +15s:000
```

Lê-se assim: `+1s:200` é “um segundo depois de aplicar, a API respondeu (200)”, e `000` é “não respondeu” (o tempo se esgotou). Nos ciclos 1 e 3, as primeiras perguntas obtêm resposta e as seguintes já não: a última resposta chegou entre 0 e 1 segundo depois do `apply`, e a primeira pergunta sem resposta, aos 2 segundos (com um máximo de um segundo por pergunta, e com o que soma cada `kubectl exec`, a imprecisão do relógio é desse tamanho). Nos ciclos 2, 4, 5 e 6 a primeira pergunta já sai aos 2, 5, 6 e 3 segundos, porque nesta máquina carregada cada `kubectl exec` levou segundos para iniciar, e já encontra a rede fechada. Em nenhum ciclo voltou a passar uma pergunta depois da primeira sem resposta. O `kubectl apply` já tinha terminado e o objeto `NetworkPolicy` já existia na API: o que faltava era que o plugin de rede, em cada nó, o lesse e o convertesse em regras. Essa conversão leva segundos e, enquanto isso, o Pod continua aberto. Com o que foi medido aqui, a janela é de uns 2 segundos no máximo (em uma execução anterior, que não foi guardada, viu-se até 3); oito segundos são uma margem escolhida, de duas vezes e meia a quatro vezes isso, e não um resultado. Passados os oito segundos do script, a mesma pergunta estourou o tempo, e nesta execução nenhuma das esperas de oito segundos mostrou o contrário:

```text
$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -o /dev/null -w '%{http_code}\n' https://kubernetes.default.svc/livez
000
command terminated with exit code 28
[código de salida: 28]
```

Limites desta medição: seis ciclos, uma máquina carregada, um único efeito medido (que `cerrado` feche a saída do `intruso`; as seis políticas são aplicadas juntas) e só a direção “fechar”; a direção “abrir” (apagar uma política, que é o que os `sleep 8` de 7.5.6 fazem) não foi medida. Três consequências práticas, que são o que justifica uma seção inteira:

1. **Um teste de rede feito cedo demais dá um falso “sim, chega”.** É o mesmo defeito de método de 7.5.6, em sentido contrário. Depois de mudar políticas, espere e meça mais de uma vez. A documentação de políticas de rede não promete uma velocidade de aplicação: a única coisa que diz é que o efeito sobre conexões já existentes fica definido pela implementação. O tempo medido aqui é desta máquina, com três nós de kind carregados com outros clusters, e não um dado do plugin.
2. **Mudar uma política é uma operação com uma janela.** Apagar as políticas e aplicá-las de novo (o ciclo desta mesma seção, ou um `kubectl delete -f red.yaml` seguido de um `kubectl apply -f red.yaml`) deixa os Pods abertos durante a janela, em um cluster onde as políticas são a única coisa que os fecha. Para mudar uma política em um cluster vivo, cria-se a nova **antes** de tirar a velha; não se apaga para recriar.
3. **A ordem de criação importa.** Se um Pod nasce antes de as políticas que o fecham estarem programadas, ele nasce aberto por um momento. Em 7.2.3 viu-se que o `kubectl apply -k` criou as seis políticas **depois** dos Deployments (a ordem da lista de `resources` não manda: o Kustomize entrega os objetos na sua própria ordem), então as primeiras réplicas do `revisor` puderam nascer abertas por alguns segundos (é uma dedução da ordem das linhas, não uma medição de um Pod recém-nascido). Em um cluster real, as políticas de um namespace são aplicadas primeiro e se espera, e depois vai o projeto.

#### 7.5.8 O que esta rede não protege

Esta rede é melhor do que não ter rede, e convém dizer com exatidão o quanto melhor.

- **O rótulo `acceso-revisor` é posto por quem cria o Pod.** Qualquer pessoa com permissão de criar Pods em `revisor` pode dar a chave a si mesma. A política protege contra Pods que **não** sabem que o rótulo existe, não contra quem tem acesso ao namespace. A camada que cuida disso é o RBAC: em um cluster real, criar Pods em `revisor` é uma permissão dada a conta-gotas. O Exercício 1 mostra, além disso, que o rótulo não serve de nada no namespace errado.
- **`revisor-entrada` confia no namespace inteiro do ponto de entrada.** Admite **todos** os Pods de `envoy-gateway-system`. Se esse namespace abriga outra coisa, essa outra coisa também entra. A política é tão estrita quanto quem controla esse namespace.
- **Não criptografa nada.** Um Pod autorizado fala HTTP puro com o `revisor`. A rede diz quem pode chegar, não que o que trafega vá protegido.
- **Os Pods com `hostNetwork` e o tráfego do nó.** A documentação diz que o comportamento das políticas com Pods em `hostNetwork` é indefinido e que o mais comum é o plugin ignorá-los e tratar o tráfego deles como tráfego do nó. E o tráfego do nó para os seus Pods (as probes) não é bloqueado. O `port-forward` também não é detido pela política, e o guia do `port-forward` avisa que ele pode driblar os controles de rede: esse é cuidado pelo RBAC (`create` sobre `pods/portforward`). Por isso o nível `restricted` de 7.3, que proíbe `hostNetwork`, e a rede se complementam.
- **Não existe política padrão para o cluster inteiro.** A mesma página lista como limite da API que não se pode aplicar políticas padrão a todos os namespaces ou Pods. `cerrado` precisa ser escrita em cada namespace, e um namespace novo nasce aberto.
- **Só funciona porque o plugin as aplica.** Nesta execução mediu-se que o kindnet as aplica. Em outro cluster é preciso medir do mesmo jeito: o cluster guarda as políticas sem reclamar mesmo que ninguém as faça cumprir.


## O hábito de segurança da lição: namespace próprio, nível `restricted`, permissões mínimas e rede fechada por padrão

A tabela de hábitos do curso atribui a esta lição quatro coisas em uma única linha: namespace próprio, nível `restricted`, permissões mínimas, rede fechada por padrão. Cada uma se verifica com um comando, e a verificação mais honesta é a que procura o que falta, não o que sobra. O inventário:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       13m

$ kubectl apply -k . 2>&1 | grep -c -i warning || true
0

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken'
POD                       CUENTA       AUTOMOUNT
depurar                   default      false
intruso                   default      false
lector                    observador   true
prueba-6899c74865-rgh68   prueba       false
revisor-d86b5794d-5fspg   revisor      false
revisor-d86b5794d-hx92n   revisor      false
revisor-d86b5794d-tmq5g   revisor      false
```

Leia-se como quatro perguntas. **O que está publicado para fora?** Um único Service do tipo `LoadBalancer` em todo o cluster: o do Envoy, em `envoy-gateway-system`, com o IP que o MetalLB lhe deu. O `revisor-publico` da Lição 6 já não existe, e o único ponto de entrada é o nomeado. **O projeto cumpre o nível que o seu namespace exige?** Aplicar de novo o `kustomization` não produz um único aviso (`0` linhas com `warning`), e o teste com `--dry-run=server` do estado final (em “Como sei que consegui”) diz `not labeled`. **Quem tem credenciais?** Só o `lector`, o Pod da prática de 7.4.4, que as pediu de propósito (`AUTOMOUNT true`); o `revisor`, o `prueba`, o `depurar` e o `intruso` dizem `false`. **A rede está fechada?** Seis políticas em `revisor`, e 7.5 mediu o que cada uma abre.

Por que são hábitos de **segurança** e não só de organização? Porque cada camada fecha um caminho concreto que foi medido aberto. Um namespace com `restricted` freia a equipe de dados (ou um descuido próprio) antes que exista um Pod com privilégios demais. Uma conta sem permissões e sem token deixa um contêiner comprometido sem nada para apresentar diante da API (o `intruso` de 7.4.4 não tinha nem um arquivo). E a rede fechada converte “qualquer Pod fala com qualquer Pod” em uma lista curta que pode ser lida, revisada e discutida, que é a mudança mais valiosa da lição: a superfície passou de implícita a escrita.

**O que protege e o que não protege.** Isto foi medido pela lição, uma camada de cada vez:

| Camada | Protege contra | Não protege contra |
|---|---|---|
| Namespace | colisões de nomes; alcance de permissões | tráfego entre Pods (7.5.3: foram alcançados entre namespaces) |
| Pod Security `restricted` | criar Pods com privilégios, `root`, `hostNetwork` | Pods que já rodavam (7.3.4); alguém com permissão de mudar o rótulo do namespace |
| Conta sem token nem permissões | roubo de credenciais de um Pod que não as precisa | um Pod que as precisa e está comprometido (o `lector`: alcança o que o seu `Role` alcança) |
| Rede fechada | movimento lateral entre Pods; acesso à API a partir de Pods sem chave | quem pode pôr o rótulo; o tráfego do nó; o conteúdo do que trafega (HTTP puro) |

E o panorama completo, para que isto não seja lido como uma receita de produção: faltam a criptografia em trânsito, um teto de recursos por namespace (`ResourceQuota`, `LimitRange`), a criptografia dos Secrets dentro do cluster, a auditoria do `kube-apiserver` e a gestão de quem tem permissão de tocar neste namespace. A Lição 10 reúne a lista do que falta a todo o projeto para rodar de verdade.

## O que se faz errado

**Acreditar que um namespace isola a rede.** Parece, porque os rótulos estão por toda parte. 7.5.3 mediu: um Pod de `default` alcançou o Service de `revisor` escrevendo o nome completo dele.

**Aplicar uma política de rede e não verificar que o plugin a cumpre.** O cluster guarda o objeto sem reclamar e o tráfego continua igual. Testa-se com um Pod sem chave que deve falhar, não com a leitura do manifesto.

**Fechar a entrada e esquecer a saída.** `cerrado` isola as duas direções, e abrir só a entrada do destino deixa quem chama sem poder sair. São duas metades de uma única permissão. É o segundo erro da lição.

**Fechar a saída e esquecer o DNS.** Sem a regra `dns`, os nomes não se resolvem e o sintoma parece que “a rede está quebrada”, quando só faltam as consultas de nomes.

**Concluir por um “continua funcionando”.** Uma conexão já aberta pode sobreviver à mudança de uma política, e a documentação deixa isso à decisão de cada plugin. Um teste de rede abre uma conexão nova a cada vez.

**Pôr `enforce` e acreditar que o namespace ficou limpo.** O rótulo rejeita o que chegar, não despeja o que já roda. E o Pod velho que viola o nível morre num rollout: no dia em que for recriado, já não nasce.

**Deixar `enforce` sem versão.** `restricted:latest` muda quando o cluster é atualizado. Fixe a versão (`enforce-version`) e suba-a de propósito.

**Olhar só o modo `enforce`.** Um Deployment que viola a política **é criado**, com um aviso que quase ninguém lê, e fica sem Pods. Os avisos do modo `warn` são lidos, ou redirecionados a um registro que alguém revise.

**Dar permissões com curingas (`*`).** A documentação do RBAC adverte: um curinga em recursos ou verbos concede também o que um dia o cluster adicionar. Nomeia-se cada recurso e cada verbo.

**Deixar montado o token de uma conta que não o usa.** É uma credencial em cada réplica, sem nenhum benefício. `automountServiceAccountToken: false`, na conta ou no Pod.

**Dar o rótulo `acceso-revisor` a qualquer Pod “para funcionar”.** Cada Pod com a chave é mais um Pod que pode falar com o `revisor`. A chave se dá a quem precisa, e se pergunta por quê.

**Confiar em um namespace inteiro como origem.** `revisor-entrada` aceita todos os Pods de `envoy-gateway-system`. É uma decisão razoável enquanto esse namespace for só da plataforma, e deixa de ser no dia em que outra coisa viver ali.

## Exercícios

Os três primeiros rodam no cluster da lição, em ordem e a partir do estado em que ele ficou depois de 7.5. Antes de cada um, o `ctx` deve deixar a cadeia passar. O `correr.sh` os roda do mesmo jeito, e a saída está em `correr.salida.txt`. **Antes** de rodar cada um, escreva na [bitácora](bitacora.md) o que se acredita que vai acontecer. O quarto se escreve com palavras próprias.

### Exercício 1 — O rótulo correto no namespace errado

Aplique `depurar.yaml` no namespace `default`, com `ctx && kubectl apply -n default -f depurar.yaml`. É o mesmo manifesto, com o mesmo rótulo `acceso-revisor: permitido`. Antes de olhar, preveja: esse Pod consegue falar com o `revisor` pelo nome completo, `http://revisor.revisor.svc.cluster.local/salud`? E o `depurar` do namespace `revisor`? Explique a diferença com as palavras de 7.5.5: o que a política `revisor-entrada` seleciona e de **qual namespace**? Ao terminar, apague o Pod de `default`.

### Exercício 2 — Uma conta que só reinicia o `revisor`

O `fig07_03.reiniciador.yaml` cria uma conta, um `Role` e um `RoleBinding`:

```yaml
# fig07_03.reiniciador.yaml — Ejercicio 2: una cuenta que puede reiniciar el
# revisor y NADA más. rollout restart necesita leer el Deployment (get) y
# cambiarle una anotación (patch); resourceNames lo limita a UN Deployment.
# Se aplica con: kubectl apply -n revisor -f fig07_03.reiniciador.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reiniciador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: reiniciador
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["revisor"]
  verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: reiniciador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: reiniciador
subjects:
- kind: ServiceAccount
  name: reiniciador
  namespace: revisor
```

O `kubectl rollout restart` precisa ler o Deployment (`get`) e mudar uma anotação dele (`patch`). Aplique-o com `ctx && kubectl apply -n revisor -f fig07_03.reiniciador.yaml` e preveja, antes de rodar qualquer coisa: a conta consegue reiniciar o `revisor`? E o `prueba`? Consegue **listar** os Deployments? Confira as três previsões com `kubectl auth can-i … --as=system:serviceaccount:revisor:reiniciador` e depois com `kubectl rollout restart` de verdade. Por que `can-i list deployments` responde diferente de `can-i patch deployment/revisor`? Ao terminar, apague o que foi criado com `ctx && kubectl delete -n revisor -f fig07_03.reiniciador.yaml`.

### Exercício 3 — Uma rota que vem de outro namespace (projeto)

O ponto de entrada vive em `revisor`. Outra equipe, em `default`, quer publicar uma rota própria por esse mesmo ponto de entrada. `fig07_05.ruta-ajena.yaml` é a `HTTPRoute` dela:

```yaml
# fig07_05.ruta-ajena.yaml — Ejercicio 3: una HTTPRoute que vive en el espacio
# «default» y pide colgarse del Gateway «revisor», que vive en «revisor».
# Pregunta: ¿la acepta el Gateway? ¿Qué dice su estado? Se aplica con:
#   kubectl apply -n default -f fig07_05.ruta-ajena.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ajena
spec:
  parentRefs:
  - name: revisor
    namespace: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /ajena
    backendRefs:
    - name: revisor
      namespace: revisor
      port: 80
```

Antes de começar, duas permissões diferentes que convém não confundir. `allowedRoutes`, dentro do `listeners` do `Gateway`, diz **quem pode se pendurar no ponto de entrada**: por padrão (`from: Same`) só as rotas do mesmo namespace do `Gateway`; `All` e `Selector` abrem o ponto de entrada a outros namespaces. `ReferenceGrant` vive no namespace do **destino** e diz **quem pode apontar para os seus Services**: uma rota de outro namespace não pode usar como destino um Service de `revisor` se o dono desse namespace não permitir. A primeira é dada pelo dono do ponto de entrada; a segunda, pelo dono do Service. As páginas de referência: [`ReferenceGrant`](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/), a [referência da API](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) e o [guia de rotas entre namespaces](https://gateway-api.sigs.k8s.io/guides/multiple-ns/).

Aplique-a em `default`. Leia o estado dela com `kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'`. Há **dois** problemas diferentes nesse estado. Antes de olhar o resultado, preveja quais são, de que objeto depende cada um e quem precisa dar cada permissão: o dono do ponto de entrada, o dono do Service ou a equipe que escreve a rota? Corrija primeiro o que vem do ponto de entrada (a pista: `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces`) e depois o outro com `fig07_06.referencegrant.yaml`:

```yaml
# fig07_06.referencegrant.yaml — Ejercicio 3: el permiso que da el DUEÑO del Service.
# Vive en el espacio «revisor» (el del Service destino) y dice: las HTTPRoute del
# espacio «default» pueden usar como destino los Service de este espacio.
# Se aplica con: kubectl apply -n revisor -f fig07_06.referencegrant.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: rutas-de-default
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: default
  to:
  - group: ""
    kind: Service
    name: revisor
```

Confira ao final que `GET /ajena` pelo ponto de entrada chega ao `revisor` (a resposta é um `404` do `revisor`, não do ponto de entrada: como se demonstra isso com o log dele?), e desfaça tudo o que foi mudado, inclusive o `Gateway`.

### Exercício 4 — Defenda o projeto

Em no máximo cinco frases, responda: (1) por que esta lição não instalou o Calico, e que prova a respalda? (2) O que aconteceria com as probes se o `kindnet` aplicasse as políticas mas o tráfego do nó também fosse bloqueado? (3) Qual das seis políticas se mudaria se a equipe de dados precisasse de um serviço **próprio** no namespace `revisor` que também receba tráfego do ponto de entrada? (4) O que falta para que `acceso-revisor: permitido` seja uma proteção e não só um acordo? (5) A política `dns` abre a saída para os Pods `k8s-app: kube-dns` de `kube-system`; o que aconteceria com a resolução de nomes se o CoreDNS fosse para outro namespace?

## Soluções

### Solução 1

Medido em `correr.salida.txt`:

```text
$ kubectl apply -n default -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -n default --show-labels
NAME      READY   STATUS    RESTARTS   AGE   LABELS
depurar   1/1     Running   0          6s    acceso-revisor=permitido,app=depurar

$ kubectl exec -n default depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

O Pod de `default` tem o rótulo, e mesmo assim **código 28**. O `depurar` de `revisor` responde. A política `revisor-entrada` não seleciona “os Pods com o rótulo” e ponto: na lista `from` dela, o `podSelector` sem `namespaceSelector` se refere aos Pods **do namespace onde vive a política**, ou seja, `revisor`. O rótulo em outro namespace não conta. O segundo elemento da lista (`namespaceSelector`), em compensação, escolhe namespaces inteiros, e por isso o Envoy entra. Para que o Pod de `default` entrasse, seria preciso adicionar um elemento com `namespaceSelector` e `podSelector` **juntos**: os Pods com esse rótulo, desse namespace. Repare também que o nome longo foi, sim, resolvido (a regra `dns` está aberta para todos); o que falhou foi a conexão.

### Solução 2

Medido em `correr.salida.txt`:

```text
$ kubectl apply -n revisor -f fig07_03.reiniciador.yaml
serviceaccount/reiniciador created
role.rbac.authorization.k8s.io/reiniciador created
rolebinding.rbac.authorization.k8s.io/reiniciador created

$ kubectl auth can-i patch deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
yes

$ kubectl auth can-i patch deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl auth can-i list deployments -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl rollout restart deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
deployment.apps/revisor restarted

$ kubectl rollout restart deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
Error from server (Forbidden): deployments.apps "prueba" is forbidden: User "system:serviceaccount:revisor:reiniciador" cannot get resource "deployments" in API group "apps" in the namespace "revisor"
[código de salida: 1]
```

`patch` sobre `deployment/revisor` responde `yes`, sobre `prueba` `no`: o `Role` nomeia o Deployment com `resourceNames: ["revisor"]`. O reinício do `revisor` funciona (`restarted`) e o do `prueba` dá um `Forbidden` que diz `cannot get resource "deployments"`: o `rollout restart` começa lendo o Deployment, e essa leitura já está proibida. `list deployments` responde `no` pela razão mais simples: o `Role` só concede `get` e `patch`, e `list` é outro verbo. Que `get` esteja limitado a um nome não converte `get` em `list`: ler um por nome e listar são permissões separadas (viu-se em 7.4.3 com os Secrets). E mesmo que o `Role` adicionasse `list`, a documentação do RBAC avisa que restringir `list` ou `watch` com `resourceNames` obriga o cliente a mandar `--field-selector=metadata.name=revisor`: um `kubectl get deployments` puro continuaria dando `no`. Essa conta pode reiniciar um serviço e não pode ver os demais. É a permissão mínima que a lição descreve, e é o exemplo de por que se escreve `resourceNames` em vez de dar `patch` sobre todos os Deployments.

### Solução 3

Medido em `correr.salida.txt`:

```text
$ kubectl get gateway revisor -n revisor -o jsonpath='{.spec.listeners[0].allowedRoutes}{"\n"}'
{"namespaces":{"from":"Same"}}

$ kubectl apply -n default -f fig07_05.ruta-ajena.yaml
httproute.gateway.networking.k8s.io/ajena created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=False NotAllowedByListeners: No listeners included by this parent ref allowed this attachment.
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

O `Gateway` diz `{"namespaces":{"from":"Same"}}`: **só rotas do próprio namespace**. Ninguém escreveu isso; é o valor padrão do tipo (`kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` diz “restringido ao namespace deste Gateway por padrão”). E a rota de `default` sai com duas condições em falso, de dois mecanismos diferentes:

- **`Accepted=False NotAllowedByListeners`**: o *listener* do Gateway não admite rotas de `default`. Quem decide é o dono do ponto de entrada, com `allowedRoutes`, **no Gateway**.
- **`ResolvedRefs=False RefNotPermitted`**: a rota aponta para um Service de outro namespace, `revisor/revisor`, e nenhum `ReferenceGrant` o permite. Quem decide é o dono do **destino**, com um objeto no **namespace dele**.

O estado da rota o resume em duas linhas: cruzar namespaces ao **se pendurar** em um Gateway é governado pelo Gateway; cruzar namespaces ao **apontar** para um Service é governado por quem é dono do Service (`kubectl explain referencegrant.spec` o descreve como os namespaces e tipos de confiança que podem referenciar os recursos de `to`). São duas permissões com dois donos, e o estado as separa: `Accepted` responde ao listener do Gateway (`allowedRoutes`) e `ResolvedRefs` responde ao `ReferenceGrant`. Um `ReferenceGrant` fala de a quem uma rota pode **apontar**; que uma rota possa **se pendurar** em um Gateway alheio é assunto de `allowedRoutes`. Corrige-se o primeiro rotulando o namespace da rota e dizendo ao listener que aceite os namespaces com esse rótulo:

```text
$ kubectl label namespace default acceso-puerta=permitido
namespace/default labeled

$ kubectl patch gateway revisor -n revisor --type=json -p '[{"op":"add","path":"/spec/listeners/0/allowedRoutes","value":{"namespaces":{"from":"Selector","selector":{"matchLabels":{"acceso-puerta":"permitido"}}}}}]'
gateway.gateway.networking.k8s.io/revisor patched

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

`Accepted` passou a `True`; `ResolvedRefs` continua em `RefNotPermitted`: a primeira permissão não conserta a segunda. A permissão do destino é o `ReferenceGrant`, que vive no namespace do Service (`revisor`) e nomeia de quem aceita referências:

```text
$ kubectl apply -n revisor -f fig07_06.referencegrant.yaml
referencegrant.gateway.networking.k8s.io/rutas-de-default created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=True ResolvedRefs: Resolved all the Object references for the Route
```

As duas condições, verdadeiras. E a prova de que a rota chega ao `revisor`:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/ajena   # desde fuera del clúster
404

$ kubectl logs -n revisor -l app=revisor --tail=-1 | grep -E 'GET /ajena'
revisor: GET /ajena 404 0s
```

O cliente de fora recebe `404`. Esse `404` **não é do ponto de entrada**: o log do `revisor` tem a linha `GET /ajena 404`, ou seja, a requisição chegou a uma réplica do `revisor`, que não conhece essa rota. (Se o ponto de entrada não tivesse encontrado rota, o `404` não apareceria no log do `revisor`.) A política de rede não atrapalhou porque o destino é o próprio `revisor`, e `revisor-entrada` já admite os Pods do Envoy: as duas camadas, a de rotas e a de rede, disseram que sim. São camadas diferentes, e as duas precisam dizer. Esse `Same` é o valor padrão que a [referência da API da Gateway API](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) documenta para `allowedRoutes.namespaces.from`, e o cluster o confirmou com o primeiro comando; o [guia de rotas entre namespaces](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) explica como abri-lo com `Selector` ou `All`.

O script desfaz tudo: apaga a rota, o `ReferenceGrant`, o rótulo de `default` e o campo `allowedRoutes` que foi adicionado ao `Gateway`; o `kubectl diff -k .` do estado final confirma que o cluster voltou ao que os arquivos dizem.

### Solução 4

Uma resposta possível: “(1) Porque o kindnet aplicou as políticas: com `cerrado` sozinha, o `intruso` e o Pod com o rótulo deixaram de chegar (código 28), e com as seis abriu-se somente o que elas diziam; essa é a medição que o plano do curso deixou pendente. (2) As probes falhariam: o `kubelet` as faz a partir do nó e ficariam bloqueadas, a probe de readiness tiraria da lista todas as réplicas e a de liveness as reiniciaria; a documentação diz que o tráfego do nó é permitido, e esta lição mediu `RESTARTS 0`. (3) Nenhuma das seis: adicionaria-se uma política nova, `entrada` para esse serviço, com o mesmo `namespaceSelector` do ponto de entrada; as políticas se somam e as alheias não se editam. (4) Que quem pode criar Pods em `revisor` não possa pôr o rótulo: RBAC que limite quem cria ou muda Pods no namespace, ou uma política de admissão que valide o rótulo. (5) A saída para o DNS deixaria de coincidir com os Pods novos de DNS e os nomes deixariam de se resolver, com o mesmo sintoma de tirar a regra `dns` em 7.5.6: o `nslookup` estoura o tempo e o `curl` por nome falha com 28, enquanto o ponto de entrada segue respondendo, como nessa linha da tabela.”

## Apagar o cluster

Quando os exercícios terminarem, apague o cluster da lição. Não deixe nada vivo na máquina:

```text
$ kind delete cluster --name curso-k8s-l7
Deleting cluster "curso-k8s-l7" ...
Deleted nodes: ["curso-k8s-l7-worker2" "curso-k8s-l7-worker" "curso-k8s-l7-control-plane"]

$ kind get clusters | grep -c curso-k8s-l7
0

# disco de Docker: 77% usado
# la corrida completa tardó 1569 s
```

(A linha entre parênteses é escrita pelo script, que mede a remoção.) O `--name` é obrigatório: sem ele, o kind apagaria o cluster chamado `kind`, que pode ser de outra pessoa.

Ficam na máquina a pasta temporária do `kubeconfig` e o `token.txt` (o de `punto-de-partida/` foi apagado em 7.2.3; o `rm` abaixo o inclui por via das dúvidas). Apagam-se assim, a partir de `programas/07-aislar-permisos-red`:

```bash
# Los tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 7.1.1.
case "$L7_TMP" in
  /tmp/curso-k8s-l7.?*) rm -rf -- "$L7_TMP" ;;
  *) echo "No borro «$L7_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L7_TMP
unset -f ctx
```

O `case` só deixa passar um caminho que comece com `/tmp/curso-k8s-l7.` e tenha algo depois, a forma exata da que foi criada em 7.1.1. Se `L7_TMP` estiver vazia (porque se está em outro terminal onde nunca foi definida) ou valer outra coisa, não apaga nada e diz por quê. É a mesma proteção que o `correr.sh` usa ao limpar. A última linha tira a função `ctx` do terminal.

Se nesta máquina a lição foi rodada com uma rede de Docker própria (a variável `CURSO_RED` do `correr.sh`), essa rede também é de quem a criou e quem a criou a apaga, **depois** do cluster e só se foi criada para isto: `docker network rm curso-k8s-red-l7`. Com a rede `kind` de sempre não há nada a apagar: é de todos os clusters. O cluster da lição seguinte é criado do zero, igual a este.

## Como sei que consegui

Antes das caixas de seleção, o estado final tal como a execução o deixou, copiado de `correr.salida.txt`. Primeiro apagam-se os Pods dos exercícios e pergunta-se ao cluster se algo difere dos arquivos do projeto, e depois olha-se o ponto de entrada de fora e repete-se o teste de 7.3:

```text
$ kubectl delete -n revisor pod depurar intruso lector --wait=false
pod "depurar" deleted from revisor namespace
pod "intruso" deleted from revisor namespace
pod "lector" deleted from revisor namespace

$ kubectl delete -n default pod intruso --wait=false
pod "intruso" deleted from default namespace

$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/api/estados   # desde fuera del clúster
401

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

Leem-se assim. `sin diferencias con los archivos` quer dizer que os exercícios foram desfeitos: o cluster é exatamente o que os arquivos dizem. O `401` é o `revisor` atrás do seu ponto de entrada: o ponto de entrada responde, mas `/api/estados` pede o token e de fora ele não é levado. E `not labeled (server dry run)` sem avisos fecha 7.3: pedir outra vez o nível `restricted` para `revisor` não muda nada porque ele já o tem, e nenhum Pod existente o descumpre.

- [ ] Dizer, com um comando, o que um namespace **não** isola: um Pod de `default` alcança `revisor.revisor.svc.cluster.local` se não há políticas.
- [ ] Diante de um Deployment com `READY 0/1` e sem Pods, ir ao ReplicaSet e encontrar `FailedCreate … violates PodSecurity`; e saber por que o `apply` não falhou.
- [ ] Ler uma rejeição de `restricted` e nomear as quatro regras e a linha do `securityContext` que corrige cada uma.
- [ ] Escrever um `Role` e um `RoleBinding` sem curingas, e testar o permitido e o negado com `kubectl auth can-i … --as=…`, com uma requisição real e de dentro de um Pod.
- [ ] Explicar por que o `revisor` não leva token montado e o `lector` sim, e o que o `lector` alcança com o dele.
- [ ] Distinguir `exit code 28` (silêncio de rede), `7` (ninguém escuta) e `403` (chegou e foi negado).
- [ ] Dizer, para cada uma das seis políticas, o que quebra se ela faltar, e por que `revisor-salida` e `prueba-entrada` produzem o mesmo sintoma.
- [ ] Rodar `programas/07-aislar-permisos-red/correr.sh > /tmp/mi-corrida-l7.txt 2>&1` e comparar `/tmp/mi-corrida-l7.txt` com `programas/07-aislar-permisos-red/correr.salida.txt` (não redirecione para esse arquivo: é a referência) no que não muda entre execuções: três nós `Ready` (a versão do nó é fixada pelo `kind-curso.yaml` por *digest*); `-rw-------` nos dois `token.txt`; os sete rótulos do namespace `revisor` com `restricted` e `v1.37`; `default` com só o Service `kubernetes`; a rejeição `violates PodSecurity "restricted:v1.37"` com as suas quatro regras; `baseline:latest` rejeita `hostNetwork` e aceita o Pod simples; `namespace/revisor not labeled (server dry run)`; a ReplicaFailure de `sinreglas`; nos `can-i`, `no` para o `revisor`, `yes` ao ler Pods e logs com `observador` e `no` ao apagar, ao ler Secrets e ao ler em `default`; `pods 200`, `secrets 403`, `pods-default 403` e o diretório ausente no `intruso`; sem regras, os testes respondem; com `cerrado`, dão 28 e `000` de fora; com as seis, o `depurar` chega e o `intruso` não; e as cinco linhas da tabela de 7.5.6. Os IPs, os sufixos dos nomes, as idades, o nome do Secret, os milissegundos e os tempos de inicialização mudam a cada execução: observam-se, não se comparam.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l7`.

## Resumo

Responda sem olhar a lição:

1. Que duas coisas um namespace isola e qual ele não isola? O que 7.5.3 mediu para demonstrar isso?
2. Quais são os três modos e os três níveis do Pod Security Admission, e como se escrevem no namespace?
3. Por que um Deployment que viola o `restricted` é criado e fica sem Pods? Onde está o motivo?
4. O que um `Role` adiciona e o que um `RoleBinding` adiciona? O que quer dizer que as permissões são aditivas?
5. O que faz `kubectl auth can-i … --as=system:serviceaccount:NAMESPACE:CONTA` e que código de saída devolve com `no`?
6. Por que o `revisor` declara `automountServiceAccountToken: false`, e o que se mede com o `lector`, que o tem em `true`?
7. Quando um Pod é isolado para a entrada? O que acontece se duas políticas o selecionam?
8. Que condição uma `NetworkPolicy` precisa para ter efeito, e como isso foi verificado no kind?
9. O que significam `exit code 28`, `exit code 7` e `403`?
10. Por que `acceso-revisor-salida` existe? E por que `dns`?
11. O que `allowedRoutes` cobre e o que `ReferenceGrant` cobre?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Namespaces”](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/): os namespaces como mecanismo para isolar grupos de recursos, nomes únicos por namespace, objetos com e sem namespace, o namespace `kube-system`, e o rótulo automático `kubernetes.io/metadata.name`.
- [Kubernetes, “Pod Security Admission”](https://kubernetes.io/docs/concepts/security/pod-security-admission/): os três modos (`enforce`, `audit`, `warn`), os três níveis, a sintaxe dos rótulos com e sem versão, e que o `enforce` se aplica aos Pods e não às cargas de trabalho.
- [Kubernetes, “Pod Security Standards”](https://kubernetes.io/docs/concepts/security/pod-security-standards/): as definições de `privileged`, `baseline` e `restricted`.
- [Kubernetes, “Enforce Pod Security Standards with Namespace Labels”](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): como pôr os rótulos em um namespace novo e em um existente, o `--dry-run=server`, e que ao adicionar `enforce` o controlador testa os Pods existentes e devolve avisos.
- [Kubernetes, “Service Accounts”](https://kubernetes.io/docs/concepts/security/service-accounts/): o que é uma conta de serviço, a conta `default` de cada namespace, a montagem automática de credenciais e os tokens de vida curta desde a 1.22.
- [Kubernetes, “Configure Service Accounts for Pods”](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/): como desativar a montagem na conta e no Pod, e que o Pod tem precedência.
- [Kubernetes, “Using RBAC Authorization”](https://kubernetes.io/docs/reference/access-authn-authz/rbac/): `Role` e `ClusterRole`, `RoleBinding`, que as permissões são puramente aditivas, os papéis padrão (`system:basic-user`, `system:discovery`), o risco dos curingas e as restrições por `resourceNames`.
- [Kubernetes, “Network Policies”](https://kubernetes.io/docs/concepts/services-networking/network-policies/): o modelo de isolamento (não isolado até que uma política selecione o Pod, e políticas aditivas), o requisito de um plugin que as aplique, o tráfego do nó, `hostNetwork`, os limites da API, e o impacto em conexões existentes.
- [Kubernetes, “Use Port Forwarding to Access Applications in a Cluster”](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/): que o `port-forward` é autorizado pelo RBAC com `create` sobre `pods/portforward`.
- [kind, “Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/): o plugin de rede padrão (`kindnetd`) e como desativá-lo.
- [kind, notas da versão v0.24.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0): o suporte a políticas de rede com `sigs.k8s.io/kube-network-policies`.
- [Gateway API, “Cross-Namespace routing”](https://gateway-api.sigs.k8s.io/guides/multiple-ns/): rotas que se penduram em um Gateway de outro namespace com `allowedRoutes`.
- [Gateway API, “ReferenceGrant”](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): a permissão do namespace de destino para que uma rota aponte para o seu Service; os campos `from` e `to`, e que só autoriza referências a recursos do próprio namespace.
- [Gateway API, referência da API (spec)](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/): `RouteNamespaces` e o valor padrão dele, `from: Same`. O mesmo foi lido no próprio cluster com `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` e `kubectl explain referencegrant.spec`, e o estado `RefNotPermitted` da rota o confirma.
- [CyberScoop, “Tesla falls victim to cryptomining scheme, minor breach”](https://cyberscoop.com/tesla-cryptomining-redlock-cloud-breach/) (20 de fevereiro de 2018): o caso com que a lição abre, a partir do relatório da RedLock.

---

**Próxima:** [Lição 8 — Dados e tarefas](08-datos-y-tareas.md)
