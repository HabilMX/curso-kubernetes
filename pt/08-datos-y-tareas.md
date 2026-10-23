# Lição 8 — Dados e tarefas

Segunda-feira, 7h12 da manhã. Às 9h tem reunião com o fornecedor do serviço de pagamentos, e a chefe manda uma mensagem de uma linha: “Preciso do relatório de sexta, das 6 da tarde, o que mostrou `prueba` fora do ar por quarenta minutos. É a prova da reclamação”. A gente abre o cluster com a tranquilidade de quem sabe que o `revisor` guarda o seu relatório em um arquivo, `/datos/reporte.json`. Pede os Pods e vê algo que não esperava: as três réplicas têm menos de dois dias. No sábado, na manutenção da madrugada, alguém esvaziou os nós um por um para atualizá-los (com `kubectl drain`, que remove os Pods de um nó) e o cluster fez o que sabe fazer: apagou os Pods velhos e o Deployment criou Pods novos em outros nós. Pede o arquivo. Não está. Procura nas outras duas réplicas. Também não. E, mesmo que estivesse, percebe algo pior enquanto pensa: o `revisor` guarda **o último** relatório e escreve por cima do anterior. O de sexta teria se perdido de qualquer jeito com a primeira consulta de sábado.

São 7h20. Faltam cem minutos para encontrar um jeito de dizer “não tenho” que não soe como “não guardei”.

Não é um caso raro de má sorte. É o que acontece quando se confunde um contêiner com um cofre. Em 2017, a equipe do GitLab publicou o relato das horas em que perdeu dados de produção e descobriu que os mecanismos de backup não estavam funcionando quando foram necessários: as cópias diárias falhavam em silêncio e o bucket onde deveriam estar estava vazio, os snapshots de disco não estavam ativados nos servidores do banco de dados e a réplica estava quebrada. O relatório deles (as fontes o citam, com o link) é um bom lembrete de que a pergunta não é “eu tenho backup?”, e sim “eu já o testei?”. Esta lição é mais modesta: não constrói backups. Ela ensina a metade anterior, a que quase todo mundo descobre tarde: **que parte do que um Pod escreve sobrevive ao próprio Pod, e que parte não**. Com essa resposta em mãos, o relatório de sexta deixa de depender da sorte: uma tarefa agendada pede o relatório ao `revisor` e o guarda, com a data no nome, em um volume que sobrevive aos Pods (enquanto existir a solicitação e o nó onde vive o disco). Deixa de ser uma linha que se sobrescreve: passa a ser um arquivo com nome e data.

A lição tem duas metades que se completam. A primeira é o **onde**: volumes que vivem mais que os Pods. A segunda é o **quando**: tarefas que rodam uma vez, ou a cada cinco minutos, sem que ninguém as dispare. Juntas resolvem a cena: uma tarefa agendada pede ao `revisor` o seu relatório a cada cinco minutos e o guarda com a data no nome, em um volume que sobrevive aos Pods.

**Tempo:** 2 × 45 min

**O que se constrói:** o relatório guardado e o `revisor` como tarefa agendada: um volume persistente chamado `reportes`, uma tarefa (`Job`) que pede ao `revisor` o seu relatório com o token e o escreve com a data no nome, e um `CronJob` que a repete a cada cinco minutos, com uma conta de serviço sem permissões nem credenciais montadas

**O que se aprende:** o que sobrevive e o que não sobrevive quando um contêiner cai e quando um Pod é apagado (`emptyDir`); `PersistentVolume`, `PersistentVolumeClaim` e `StorageClass`, e a classe de armazenamento do kind; por que a solicitação espera pelo seu primeiro Pod; `Job` e `CronJob` com suas novas tentativas, seu horário e seu histórico; o dono dos arquivos com `fsGroup`; o que se perde ao apagar a solicitação; e um tamanho pedido que o cluster não faz respeitar

**De onde a gente vem.** Da Lição 7: o `revisor` e o serviço de teste vivem em um namespace próprio, `revisor`, que exige o nível `restricted` do Pod Security Admission; cada carga tem a sua conta de serviço sem credenciais montadas; e a rede está fechada por padrão, com aberturas nomeadas: só entram no `revisor` os Pods com o rótulo (label) `acceso-revisor: permitido` e os Envoy do ponto de entrada. Da [Lição 4](04-configuracion-secretos.md), o token como `Secret` montado como arquivo e os nomes com *hash* que o Kustomize coloca. Da [Lição 5](05-salud-recursos-apagado.md), `requests` e `limits` em todo contêiner; hoje as tarefas também os trazem. E da [Lição 6](06-entrar-al-cluster.md), a plataforma (MetalLB e Envoy Gateway) que esta lição instala de novo ao criar o seu cluster, porque o ponto de partida inclui o Gateway.

**O que esta lição não faz.** Não coloca o relatório do `revisor` dentro do volume persistente: o Exercício 2 deixa tentar e ver por que o curso não faz isso (prende todas as réplicas a um único nó). Não instala um sistema de armazenamento em rede, não ensina `StatefulSet`, nem tira snapshots ou backups de um volume: os menciona no fim de “O hábito de segurança”, com uma frase sobre o problema que cada um resolve. Não escala nada (isso é a [Lição 9](09-escalar-y-actualizar.md), que parte do que fica aqui) nem avalia o projeto completo contra um cluster real (a [Lição 10](10-proyecto-final.md)).

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com `kind` v0.33.0, `kubectl` v1.37.1 e a imagem de nó `kindest/node:v1.37.0` fixada pelo seu *digest*, no cluster de três nós da Lição 1, aqui chamado de `curso-k8s-l8`. A máquina foi um Mac com processador ARM e Docker Engine dentro de uma máquina virtual Linux (Colima), **não** o Linux Mint, que é o sistema de referência do curso. **A execução usou uma rede de Docker própria**, `curso-k8s-red-l8`, com a sub-rede `172.28.0.0/16`, porque a máquina era compartilhada e naquele momento rodavam outras lições com MetalLB: dois clusters com a mesma faixa de IP na mesma rede se sobrescrevem. Por isso os endereços do Gateway saem aqui em `172.28.255.x`. **Na máquina de quem acompanha, com a rede `kind` normal que o Docker cria ao subir o primeiro cluster, os IPs saem em `172.18.255.x`** (a faixa de `infra/metallb-pool.yaml` é `172.18.255.200-172.18.255.220`), e não é preciso criar nenhuma rede. Isso supõe que a rede `kind` tenha a sub-rede `172.18.0.0/16`; confira antes com `docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'` e, se for outra, ajuste a faixa do arquivo. O resto que muda no Mint: a arquitetura (`amd64` em vez de `arm64`), os sufixos aleatórios dos nomes de Pods e de Jobs, as idades, em que nó cai cada réplica, o *uid* de cada Pod, a hora e os nomes dos volumes (`pvc-` e um identificador). Os comandos são os mesmos. O percurso completo está em [`programas/08-datos-y-tareas/`](../programas/08-datos-y-tareas): o `correr.sh` cria o cluster, instala nele a plataforma, deixa tudo como a Lição 7 deixou, percorre a lição em ordem, roda os Exercícios 1 a 3 e apaga o cluster; a saída é `correr.salida.txt`. A execução completa levou 19 minutos e 17 segundos (os três ensaios de `concurrencyPolicy` do Exercício 3 somam uns oito minutos de esperas): criar o cluster e esperar que ficasse pronto levou 42 segundos, instalar a plataforma levou 175 (o script não cronometra cada passo, então não sei qual das esperas foi a longa) e apagar o cluster, 4. Esses tempos variam muito com a carga da máquina: em outra execução do mesmo script, com a máquina ocupada, instalar a plataforma levou 678 segundos e o `kubectl wait` do Envoy Gateway chegou a estourar o prazo de 300 segundos, embora o Gateway tenha acabado funcionando. As esperas longas da lição (ver passar o horário de um `CronJob`, ver como um `Job` esgota as suas novas tentativas) estão escritas à vista: o script imprime a cada quantos segundos olha e o que vê, não as esconde. Não usa nenhuma porta da máquina de quem acompanha.

## Ao terminar, a gente vai conseguir

- Demonstrar com a execução o que sobrevive e o que não sobrevive em um `emptyDir`: a reinicialização do contêiner sim, o apagamento do Pod não.
- Explicar com as próprias palavras o que são um `PersistentVolume`, uma `PersistentVolumeClaim` e uma `StorageClass`, e por que a solicitação do curso fica em `Pending` até aparecer o primeiro Pod que a usa.
- Ler o estado de uma solicitação de volume, o seu volume e o diretório real que o sustenta no nó.
- Escrever um `Job`, dizer quantas vezes ele tenta de novo e com que esperas, e interpretar um `BackoffLimitExceeded`.
- Escrever um `CronJob`, ler o seu horário de cinco campos, e explicar `concurrencyPolicy`, o histórico de tarefas e por que uma tarefa agendada deve poder rodar duas vezes sem danificar nada.
- Provocar e consertar um `Permission denied` em um volume com `fsGroup`, e dizer em qual dos volumes da lição o `fsGroup` mudou o grupo e em qual não, e por que não dá para presumir isso.
- Dizer o que acontece com os dados ao apagar uma solicitação de volume conforme a política de reclamação, e por que o apagamento pode ficar em `Terminating`.

## O porquê antes do como

Até hoje, tudo o que o `revisor` escreve vive em um lugar que o cluster trata como descartável. A gente viu isso de passagem na Lição 2, quando o Deployment montou um `emptyDir` em `/datos` para que o sistema de arquivos somente leitura não impedisse de guardar o relatório, e o usou desde então sem perguntar quanto ele dura. A primeira pergunta da lição é essa: **quanto dura o que um Pod escreve?** A resposta tem dois degraus, porque um Pod não é o mesmo que um contêiner: o contêiner pode cair e voltar (o `kubelet` o reinicia), e o Pod pode ser apagado e substituído por outro, com outro nome, em outro nó. O que sobrevive ao primeiro não tem por que sobreviver ao segundo, e a gente mede isso.

A segunda pergunta é **como se guarda algo de verdade?** O Kubernetes separa dois papéis que no Docker vinham juntos. Quem administra o cluster decide que armazenamento existe (discos, pastas, serviços de rede); quem implanta uma aplicação decide quanto precisa e de que tipo. A ponte entre os dois são três objetos com nomes parecidos e trabalhos distintos, que esta lição apresenta um por um antes de usá-los.

A terceira é **como se faz algo que não é um serviço?** Um Deployment mantém processos que não devem terminar. Pedir o relatório ao `revisor` a cada cinco minutos é o contrário: um processo que inicia, faz uma coisa e termina, e que o cluster deve repetir em horário fixo sem que ninguém se lembre. Para isso existem o `Job` (fazer algo até dar certo ou até desistir) e o `CronJob` (criar Jobs com um horário).

E há uma quarta pergunta, menos vistosa, que decide se o que vem acima funciona: **quem é o dono do que se escreve?** Um volume que nasce com um dono e uma permissão, e um processo que roda como outro usuário, são uma receita para um `Permission denied`. O `fsGroup`, a linha da Lição 4 que deixou pendente a sua história completa, volta aqui.

A lição tem oito partes de conceitos e depois as seções de sempre:

1. **O cluster da lição e o seu ponto de partida** (8.1).
2. **O que se perde: o `emptyDir` de hoje** (8.2).
3. **Volumes, solicitações e classes** (8.3).
4. **A solicitação de volume e a sua espera** (8.4).
5. **`Job`: a tarefa que termina** (8.5).
6. **`CronJob`: a tarefa com horário** (8.6).
7. **O dono dos arquivos: `fsGroup`** (8.7).
8. **Apagar a solicitação: aí sim se perde** (8.8).

Este é o destino. No fim de 8.5, uma tarefa disparada manualmente deixa um arquivo com a data no nome dentro de um volume que sobrevive ao seu Pod, e uma segunda tarefa vê o arquivo da primeira:

```text
$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json
```

## Se as imagens do curso de Docker não estiverem disponíveis

Esta lição usa as mesmas duas imagens das anteriores: `curso-docker-revisor:1.6.0` e `curso-docker-prueba:1.0.0`. Confira se elas estão aí:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para a outra, o mesmo comando com `curso-docker-prueba:1.0.0`. Se alguma faltar, a [Lição 3](03-services-dns.md) diz como construir cada uma a partir do repositório do curso de Docker. As tarefas desta lição usam também a imagem pública do `curl` que a gente já conhece do `depurar`, fixada pelo seu `sha256`; cada nó a baixa da internet na primeira vez.

## Os conceitos

### 8.1 O cluster da lição e o seu ponto de partida

#### 8.1.1 Criar o cluster

Esta lição usa o seu próprio cluster, `curso-k8s-l8`, com a configuração de três nós da Lição 1. Os caminhos `programas/08-datos-y-tareas/…` do bloco seguinte supõem que a pessoa esteja na raiz do repositório do curso. Antes de criá-lo, duas precauções que já viraram costume: um `kubeconfig` temporário e próprio, para que o `~/.kube/config` nem seja lido nem tocado, e uma função que confere com qual cluster se está falando. Vamos chamá-la de `ctx` e ela vai **antes de cada comando que mude algo**: se o contexto não for o da lição, devolve um erro e o comando seguinte não roda, porque está ligado a ela com `&&`.

```bash
# Un kubeconfig temporal y propio. La carpeta queda guardada en una variable:
# la necesitas para abrir una segunda terminal y para borrarla al final.
L8_TMP="$(mktemp -d /tmp/curso-k8s-l8.XXXX)"
export KUBECONFIG="$L8_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta
# La guarda: el contexto debe ser el de la lección, o el comando que sigue no corre.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l8 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
# curso-k8s-l8 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l8 --config programas/08-datos-y-tareas/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l8
# El resto de la lección se trabaja desde la carpeta de sus programas.
cd programas/08-datos-y-tareas
```

(A execução desta lição, pelo que foi dito em “Sobre as execuções”, antepôs `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l8` ao `kind create cluster` para usar a sua rede própria. Quem acompanha não precisa disso.)

O `export` e a função `ctx` só vivem nesse terminal. Ao abrir outro, é preciso repetir as duas linhas (`export KUBECONFIG=…` com o caminho que o `echo` imprimiu, e a definição de `ctx`), senão o `kubectl` vai falar com outro cluster. Daqui em diante, **todo bloco de código que mude algo começa com `ctx &&`**. Nas saídas coladas mais abaixo, a linha que começa com `$` é o comando tal como o script o imprimiu, sem `ctx &&`: o script confere o contexto antes de cada `kubectl` por conta própria, e quem acompanha faz isso com a função.

As saídas desta seção vêm da execução do `correr.sh`, que faz exatamente isso, com a rede própria explicada em “Sobre as execuções”:

```text
$ kubectl config current-context
kind-curso-k8s-l8

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l8-control-plane   Ready    control-plane   27s   v1.37.0
curso-k8s-l8-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l8-worker2         Ready    <none>          17s   v1.37.0
```

O `kind load` imprime seis linhas `not yet present on node …, loading...`, duas imagens por três nós, como nas lições anteriores.

#### 8.1.2 A plataforma da Lição 6, outra vez

O ponto de partida desta lição inclui o Gateway da Lição 6, e um Gateway precisa dos tipos novos (CRD) da Gateway API e do controlador do Envoy Gateway. Como o cluster é novo, é preciso instalá-los de novo, na mesma ordem da Lição 6: primeiro a plataforma, depois uma espera, depois a sua configuração. A ordem importa porque os CRDs e os *webhooks* devem existir antes dos recursos que os usam.

```bash
ctx && kubectl apply -k infra/metallb
ctx && kubectl apply --server-side -k infra/envoy-gateway
# La espera: los tipos nuevos establecidos y los controladores disponibles.
ctx && kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
ctx && kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
ctx && kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
# La configuración: el rango de IP de MetalLB y la clase de puerta «eg».
ctx && kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
ctx && kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s
```

A saída, com a faixa da rede própria da execução:

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ sed 's#172.18.255.200-172.18.255.220#172.28.255.200-172.28.255.250#' infra/metallb-pool.yaml | kubectl apply -f - && kubectl apply -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=240s | tail -1
daemon set "speaker" successfully rolled out
(la plataforma tardó 175 s)
```

Duas notas sobre esta saída. A do `sed` vale só para a execução: ele troca a faixa do arquivo (`172.18.255.200-220`) pela da rede própria (`172.28.255.200-250`) antes de aplicá-lo. Na máquina de quem acompanha, com a rede `kind` normal, o arquivo é aplicado tal qual: `kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml`. E os 175 segundos são muito para isto (com a máquina mais carregada chegaram a 678), e o script não cronometra cada passo: a máquina estava ocupada com outros clusters. Num ensaio anterior desta mesma lição, o último a se declarar pronto foi o *speaker* do MetalLB (um Pod por nó que anuncia os IPs na rede). Se na máquina de quem acompanha o `rollout status` demorar, `kubectl get pods -n metallb-system` mostra quantos dos três *speakers* estão prontos.

#### 8.1.3 O ponto de partida: a Lição 7

A pasta `programas/08-datos-y-tareas/punto-de-partida/` traz, sem mudar uma vírgula, os manifestos com que a Lição 7 terminou: o namespace `revisor` com o nível `restricted`, as contas de serviço, as seis políticas de rede, o `revisor` e o serviço de teste com seus Services, o Gateway e a `kustomization.yaml`. Como nas lições anteriores, o token não é versionado: é gerado a cada execução, com permissão `0600`, e copiado para as duas pastas (a do ponto de partida e a da lição) para que as duas gerem **o mesmo** Secret.

```bash
ctx && (umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
ctx && cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
ctx && kubectl rollout status deployment/revisor -n revisor --timeout=180s
ctx && kubectl rollout status deployment/prueba -n revisor --timeout=180s
ctx && kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
ctx && kubectl apply -n revisor -f depurar.yaml
```

```text
$ ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-hbc69k5m5c created
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

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met

$ kubectl apply -n revisor -f depurar.yaml
pod/depurar created
```

O nome do `ConfigMap` é o da Lição 4, `revisor-config-t6cm6872fk`, porque a lista de serviços não mudou; o do `Secret` muda a cada execução, porque o token é novo. Os dois `rollout status` do bloco anterior não imprimem nada aqui porque o script os roda em silêncio; no terminal de quem acompanha aparecerá `deployment "revisor" successfully rolled out` e o equivalente de `prueba`. O Pod `depurar` é o de sempre, com uma diferença que a gente já conhece da Lição 7: leva o rótulo (label) `acceso-revisor: permitido`, e por isso a rede fechada o deixa falar com o `revisor`.

```text
$ kubectl get pods -n revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
depurar                    1/1     Running   0          8s    10.244.2.5   curso-k8s-l8-worker    <none>           <none>
prueba-6899c74865-9dckl    1/1     Running   0          52s   10.244.1.4   curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-g6wc5   1/1     Running   0          52s   10.244.2.4   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-rxlw6   1/1     Running   0          52s   10.244.2.3   curso-k8s-l8-worker    <none>           <none>
revisor-6b7f4d564d-wk56w   1/1     Running   0          52s   10.244.1.5   curso-k8s-l8-worker2   <none>           <none>

$ kubectl get pvc,cronjob,job -n revisor
No resources found in revisor namespace.

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Três réplicas do `revisor`, o serviço de teste e o `depurar`. E a última linha do `kubectl get`: não há volumes, nem tarefas, nem horários. Essa é a pergunta aberta da lição. A última saída é uma requisição que vem de um contêiner de Docker fora do cluster, na mesma rede dos nós, e chega pelo Gateway: o ponto de entrada da Lição 6 funciona no namespace da Lição 7 com a rede fechada. Se na máquina de quem acompanha ela não responder, `kubectl get gateway -n revisor` diz que IP foi recebido; na execução foi `172.28.255.200`, e na rede `kind` normal seria `172.18.255.200`.

### 8.2 O que se perde: o `emptyDir` de hoje

#### 8.2.1 Onde está o arquivo

Primeiro, que o `revisor` escreva o seu relatório. Cada requisição a `/api/estados` monta o relatório e, antes de responder, o guarda no arquivo indicado pela variável `REVISOR_REPORTE` da imagem, `/datos/reporte.json`. A imagem não tem *shell*, então não dá para entrar para ver o arquivo; mas o arquivo existe em algum disco, e os nós do kind são contêineres de Docker em que dá para entrar. Pede-se um relatório e procura-se:

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid
POD                        NODO                   UID
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347
revisor-6b7f4d564d-wk56w   curso-k8s-l8-worker2   510c7d49-6be3-4fac-947d-18783838b9e5
```

(No primeiro comando, o token aparece como `…`: o script o oculta no que imprime, e quem acompanha o passa com `$TOKEN`, como nas lições anteriores.) O `uid` é o identificador único que o cluster dá a cada Pod, e é o nome da pasta onde o `kubelet` do nó guarda o que é dele. Os volumes de um Pod vivem em `/var/lib/kubelet/pods/<uid>/volumes/`, e os do tipo `emptyDir`, na subpasta `kubernetes.io~empty-dir`. Olha-se a de cada uma das três réplicas, no nó onde ela roda:

```text
$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/961791a4-d756-4382-a1de-ae62d7bc11b1/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker ls -lan /var/lib/kubelet/pods/29162810-cd29-4693-89bf-ed789dd8f347/volumes/kubernetes.io~empty-dir/datos
total 8
drwxrwsrwx 2 0 65532 4096 Oct 21 23:23 .
drwxr-xr-x 3 0     0 4096 Oct 21 23:23 ..

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

Há três achados nessas três saídas, e os três importam para o que vem a seguir.

**O primeiro: só uma das três réplicas tem o arquivo.** A requisição a `http://revisor/` foi repartida pelo Service para uma das três, e foi essa que guardou o relatório. As outras duas têm o `/datos` vazio. Cada réplica tem o seu **próprio** `emptyDir`: nada é compartilhado entre Pods. Se a gente perguntasse a “o `revisor`” qual foi o seu último relatório, a resposta dependeria de qual réplica responde. Isso, por si só, já desqualifica o `emptyDir` como lugar para um histórico.

**O segundo: o dono do diretório.** A primeira coluna do `ls -l` é `drwxrwsrwx`: o diretório tem permissão de leitura, escrita e entrada para todos, e um `s` no lugar do `x` do grupo, que é o *setgid*. O dono é o usuário `0` (`root`) e o grupo, o `65532`. Esse grupo não é casual: é o `fsGroup: 65532` que a Lição 4 colocou no Deployment. Para não atribuir ao `fsGroup` mais do que ele faz: a permissão aberta `777` é o valor padrão de um `emptyDir` segundo a documentação de volumes; o que o `fsGroup` coloca é o grupo `65532` e o bit *setgid*. A seção 8.7 conta o que o `fsGroup` fez aqui e o que ele não faz em outros volumes.

**O terceiro: o arquivo é do usuário do `revisor`.** `-rw------- 1 65532 65532 92`: o dono e o grupo são o 65532, o usuário com que o `revisor` roda, e a permissão `0600` (só o dono) vem de como o `revisor` o cria: escreve primeiro um arquivo temporário na mesma pasta e depois o renomeia, para que quem o leia veja o relatório velho ou o novo, nunca um pela metade. E 92 bytes: um relatório de um único serviço.

Com `root` no nó dá para ler o que o `revisor` guardou:

```text
$ docker exec curso-k8s-l8-worker2 stat -c '%a %U:%g %n' /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
2777 root:65532 /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos

$ docker exec curso-k8s-l8-worker2 cat /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos/reporte.json
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 6
  }
]
```

O `stat` traduz a permissão para octal: `2777` é o `777` de leitura e escrita para todos mais o `2` do *setgid*. É a mesma informação do `s`, em outra forma. O conteúdo é o relatório em JSON: o nome do serviço, se está bem, o código HTTP e o tempo em milissegundos.

(As saídas desta seção supõem que se saiba entrar em um nó com `docker exec`; é o mesmo que a gente fez na Lição 4 com o `Secret` e na Lição 5 com o `crictl`. Funciona porque no kind os nós são contêineres. Em um cluster de verdade, a pasta existe do mesmo jeito, mas o nó é uma máquina em que se entra por outro mecanismo e com outras permissões.)

#### 8.2.2 Um contêiner que cai: o `emptyDir` sobrevive

A documentação de volumes do Kubernetes ([link nas fontes](#fontes)) diz do `emptyDir`: o volume é criado “quando o Pod é atribuído a um nó”; começa vazio; e “quando um Pod é removido de um nó por qualquer motivo, os dados do `emptyDir` são apagados permanentemente”. E acrescenta uma nota que parece pequena e é metade da lição: “um contêiner que cai **não** remove o Pod do nó. Os dados de um volume `emptyDir` estão a salvo de quedas de contêiner”.

Vamos conferir. Com o `crictl`, a ferramenta da Lição 5, o contêiner do `revisor` que tem o arquivo é parado. O identificador do contêiner é procurado pelo `uid` do Pod, para não parar um alheio:

```bash
CID="$(docker exec curso-k8s-l8-worker2 crictl ps --label "io.kubernetes.pod.uid=510c7d49-6be3-4fac-947d-18783838b9e5" --name revisor -q)"
docker exec curso-k8s-l8-worker2 crictl stop "$CID"
```

```text
$ docker exec curso-k8s-l8-worker2 crictl stop a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090
a208caab7a28e3a47c90a21f11ccd62ffd1a723a411b85e63427d8d5744f8090

(esperando 10 s a que el kubelet reinicie el contenedor)

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w
NAME                       READY   STATUS    RESTARTS      AGE
revisor-6b7f4d564d-wk56w   1/1     Running   1 (10s ago)   65s

$ kubectl get pod -n revisor revisor-6b7f4d564d-wk56w -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason} {.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
Error 137

$ docker exec curso-k8s-l8-worker2 ls -lan /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
total 12
drwxrwsrwx 2     0 65532 4096 Oct 21 23:24 .
drwxr-xr-x 3     0     0 4096 Oct 21 23:23 ..
-rw------- 1 65532 65532   92 Oct 21 23:24 reporte.json
```

Lê-se em ordem. `RESTARTS 1 (10s ago)`: o `kubelet` viu o contêiner morrer e o reiniciou há 10 segundos; o Pod continua sendo o mesmo (mesmo nome, mesmo `uid`, `AGE` de 65 segundos). O último encerramento foi um `Error` com o código `137`, o mesmo da Lição 5: 128 mais o sinal 9, o que não pode ser ignorado. E a última saída é a que importa: **o arquivo está intacto**, com a mesma hora (`23:24`) e os mesmos 92 bytes. O contêiner novo montou o mesmo volume e encontrou o relatório onde o velho o deixou.

Isso tem uma consequência prática que convém dizer com clareza: se a aplicação cai e se reinicia sozinha, o que ela guardou em um `emptyDir` o contêiner novo encontra. Esse é o uso que a documentação propõe: espaço de trabalho, pontos de controle de um cálculo longo para retomá-lo depois de uma queda. Não é um lugar para o que deve sobreviver ao Pod.

#### 8.2.3 Um Pod que é apagado: o `emptyDir` vai junto

O segundo degrau. Apaga-se o Pod inteiro, não só o seu contêiner, e olha-se a pasta do volume:

```bash
ctx && kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
```

```text
$ kubectl delete pod -n revisor revisor-6b7f4d564d-wk56w
pod "revisor-6b7f4d564d-wk56w" deleted from revisor namespace

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos
ls: cannot access '/var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5/volumes/kubernetes.io~empty-dir/datos': No such file or directory
[código de salida: 2]

$ docker exec curso-k8s-l8-worker2 ls /var/lib/kubelet/pods/510c7d49-6be3-4fac-947d-18783838b9e5
containers
etc-hosts
plugins
volumes

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,NODO:.spec.nodeName,UID:.metadata.uid,LISTO:.status.containerStatuses[0].ready
POD                        NODO                   UID                                    LISTO
revisor-6b7f4d564d-4mnvh   curso-k8s-l8-worker2   d61911b6-d777-4c4c-a159-e2a782fc69d8   true
revisor-6b7f4d564d-g6wc5   curso-k8s-l8-worker    961791a4-d756-4382-a1de-ae62d7bc11b1   true
revisor-6b7f4d564d-rxlw6   curso-k8s-l8-worker    29162810-cd29-4693-89bf-ed789dd8f347   true
```

A pasta do volume já não existe: `No such file or directory`, com código de saída 2. O `kubelet` apagou o volume ao retirar o Pod. A segunda saída é um detalhe que convém ler com cuidado: a pasta do Pod ainda mostra quatro entradas (`containers`, `etc-hosts`, `plugins` e `volumes`) alguns segundos depois do apagamento. Não investiguei o motivo (provavelmente é uma limpeza do `kubelet` que ainda não tinha terminado); o que importa para a lição já aconteceu: a pasta do volume de dados não existe. E o ReplicaSet repôs a réplica: `4mnvh` é nova (outro nome, outro `uid`) e desta vez caiu no mesmo nó, `curso-k8s-l8-worker2`; o agendador distribui, mas não promete um nó diferente. O `revisor` novo iniciou com o `/datos` vazio.

Com isso, a sexta-feira da cena fica explicada em duas medições. Uma reinicialização do contêiner se salva. A manutenção de sábado não reiniciou contêineres: removeu Pods, e cada Pod novo nasceu com um `emptyDir` novo, em um nó que talvez não fosse o mesmo. (Uma simples reinicialização do nó é outra coisa: a documentação do ciclo de vida do Pod distingue esse caso, em que o Pod não é removido e o `kubelet` volta a subir seus contêineres, da remoção ou da perda do nó. Os Pods são substituídos quando alguém os apaga, o nó é esvaziado ou é declarado perdido.) Para que um dado sobreviva ao Pod é preciso um volume que **não dependa do Pod**: é isso que vem a seguir.

### 8.3 Volumes, solicitações e classes

#### 8.3.1 Três objetos, três papéis

Antes de usá-los, os três objetos com um exemplo da vida diária. Imagine um prédio de escritórios. Os **espaços de escritório** existem: alguém os construiu, têm um tamanho e uma localização. Uma **solicitação de aluguel** diz “preciso de um escritório de tantos metros, para uma única empresa trabalhar”; não diz qual. E o **tipo de escritório** (com vista, sem vista, no subsolo) descreve como são construídos e quanto custam. No Kubernetes:

| No prédio | No Kubernetes | Quem cria | O que diz |
|---|---|---|---|
| o espaço de escritório | `PersistentVolume` (PV) | o administrador do cluster, ou o sistema, sob demanda | “existe um armazenamento deste tamanho, neste lugar, com estas regras” |
| a solicitação de aluguel | `PersistentVolumeClaim` (PVC) | quem implanta a aplicação | “preciso deste tamanho, com este modo de acesso” |
| o tipo de escritório | `StorageClass` | o administrador do cluster | “é assim que se cria um volume desta classe” |

A [documentação de volumes persistentes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) define os dois primeiros com estas palavras: um PersistentVolume é “uma porção de armazenamento no cluster que foi provisionada por um administrador ou provisionada dinamicamente usando classes de armazenamento. É um recurso do cluster, assim como um nó”. E uma PersistentVolumeClaim “é uma solicitação de armazenamento feita por um usuário. É semelhante a um Pod”. A analogia com o Pod vai mais longe do que parece: assim como um Pod consome recursos de um nó, uma solicitação consome recursos de um volume; e assim como um Pod pode pedir CPU e memória, uma solicitação pede um tamanho e um modo de acesso.

Um detalhe de nomes que confunde quem chega: o PV **não tem namespace** (é do cluster, como um nó; na saída de `kubectl api-resources --namespaced=false` aparece ao lado de `nodes` e `namespaces`), e a PVC **tem** (vive em `revisor`, junto dos Pods que a usam).

```text
$ kubectl api-resources --api-group='' --namespaced=false -o name | grep -E '^(persistentvolumes|nodes|namespaces)$'
namespaces
nodes
persistentvolumes
```

#### 8.3.2 Os dois caminhos para ter um volume

A mesma página descreve duas formas de uma solicitação encontrar o seu volume:

- **Estática.** “Um administrador do cluster cria certo número de PVs.” Os PVs já existem, e uma solicitação que coincide com um (em tamanho, em modo de acesso, em classe) se une a ele. É o que acontece com discos que alguém preparou manualmente.
- **Dinâmica.** “Quando nenhum dos PVs estáticos que o administrador criou coincide com a solicitação de um usuário, o cluster pode tentar provisionar dinamicamente um volume para ela.” Ninguém cria o PV: quem o cria é um programa do cluster, o *provisionador*, a partir da classe que a solicitação pediu.

E o trâmite, que a documentação chama de ciclo de vida: primeiro o provisionamento; depois a ligação (*binding*): “um ciclo de controle do control plane observa as PVCs novas, encontra um PV que coincida (se puder) e as liga”; em seguida o uso: “uma vez que o usuário tem uma solicitação e ela está ligada, o PV ligado pertence a ele enquanto precisar”; e no fim a reclamação, quando o usuário já não precisa dele. Anote uma frase dessa página, porque a gente vai vê-la se cumprir: “as solicitações ficam sem ligar indefinidamente se não existe um volume que coincida”. A ligação também é de um para um: um PV com uma solicitação, e uma solicitação com um PV.

O curso usa os dois caminhos, cada um onde ensina algo. O dinâmico é o caminho normal e é o que o relatório da lição usa. O estático será usado em 8.7 para fabricar um disco com as regras de um de verdade.

#### 8.3.3 A classe do kind

Este cluster já traz uma classe. Pergunta-se a ele:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  4m31s

$ kubectl get storageclass standard -o jsonpath='{.provisioner} {.reclaimPolicy} {.volumeBindingMode} {.allowVolumeExpansion}{"\n"}'
rancher.io/local-path Delete WaitForFirstConsumer

$ kubectl get pods -n local-path-storage
NAME                                      READY   STATUS    RESTARTS   AGE
local-path-provisioner-75f7fc7dc5-xl4bd   1/1     Running   0          4m26s

$ kubectl get pv
No resources found
```

Uma classe com quatro dados que importam:

- **`standard (default)`** é o nome dela, e o parêntese diz que é a **classe padrão**: a documentação de classes diz que, quando uma solicitação não define `storageClassName`, “a classe padrão é usada”. O curso a nomeia mesmo assim no manifesto, porque um manifesto que diz o que usa se lê sem depender de uma configuração do cluster.
- **`rancher.io/local-path`** é o provisionador. No namespace `local-path-storage` há um Pod, `local-path-provisioner`, que observa as solicitações desta classe e cria o volume para elas. A documentação do projeto o descreve assim: “oferece uma maneira de os usuários do Kubernetes utilizarem o armazenamento local de cada nó”, e o volume que ele cria é, por padrão, uma pasta do nó, do tipo `hostPath`. Duas frases desse mesmo README, que usaremos mais adiante, convém anotar: não suporta limite de capacidade (“a capacidade é ignorada por enquanto”), e a pasta é criada com permissão `0777`.
- **`Delete`** é a **política de reclamação** (reclaim policy) dos volumes desta classe: o que se faz com o volume quando a solicitação que o usava é apagada. A documentação de volumes persistentes diz assim: com `Delete`, o apagamento remove tanto o objeto PV do Kubernetes quanto o armazenamento associado. A alternativa é `Retain`, que conserva o volume para que um administrador o recupere manualmente. A seção 8.8 mede as duas.
- **`WaitForFirstConsumer`** é o **modo de ligação** (binding mode), e é o dado mais importante para entender o que vem a seguir. A documentação de classes o explica por contraste. Com o modo `Immediate`, que é o usado quando nada é indicado, “a ligação do volume e o provisionamento dinâmico acontecem assim que a solicitação é criada”. Isso pode dar errado quando o armazenamento está preso a um lugar (um nó, uma zona), porque o volume seria criado sem saber onde o Pod vai rodar. O remédio: o modo `WaitForFirstConsumer` “atrasará a ligação e o provisionamento de um PersistentVolume até que seja criado um Pod que use a PersistentVolumeClaim”. Primeiro se decide onde o Pod vai rodar; depois o volume é criado **nesse lugar**.
- **`ALLOWVOLUMEEXPANSION false`** (e vazio no `jsonpath`, porque o campo não está escrito na classe): a classe não permite aumentar um volume depois de criado. Não será necessário aqui; se um dia um volume encher, esta coluna decide se a saída é aumentá-lo ou criar outro maior e migrar os dados.

E o fim da saída: **`No resources found`** no `kubectl get pv`. Ainda não há nenhum volume. A classe existe, o provisionador espera, e os volumes são criados quando alguém os pedir e houver um Pod que os use.

### 8.4 A solicitação de volume e a sua espera

#### 8.4.1 O manifesto

A lição acrescenta um arquivo ao projeto, `reporte.yaml`, com três objetos: a conta de serviço `reporte`, a solicitação `reportes` e o `CronJob` `reporte`. Os dois primeiros são lidos agora; o terceiro tem a sua própria seção, a 8.6, porque antes é preciso saber o que é um Job. O arquivo completo é um **programa**: `programas/08-datos-y-tareas/reporte.yaml`, e a `kustomization.yaml` da lição o soma à sua lista de recursos.

```yaml
# reporte.yaml — Lección 8: el reporte guardado y el revisor como tarea programada.
# Cada 5 minutos, un Job le pide al revisor su reporte y lo guarda en un volumen
# persistente. El binario del revisor solo sirve HTTP (no tiene modo «una vez»),
# por eso la tarea es un curl contra su API; la lección (8.6) explica por qué.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reporte
automountServiceAccountToken: false
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: reportes
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 100Mi
```

(A terceira peça, o `CronJob`, está completa em 8.6; aqui ela é cortada para ler primeiro a solicitação.) A conta de serviço é o costume da Lição 7: uma conta própria para a tarefa, sem permissões e com `automountServiceAccountToken: false`, porque a tarefa fala com o `revisor`, não com a API do cluster. A solicitação tem quatro linhas que importam:

- **`accessModes: [ReadWriteOnce]`** é o **modo de acesso**. Abrevia-se RWO e a documentação o define assim: “o volume pode ser montado como leitura e escrita por **um único nó**”. Essa última palavra é a que se interpreta mal: é um nó, não um Pod. A mesma página esclarece que o RWO “ainda pode permitir que vários Pods acessem (leiam ou escrevam) o volume quando os Pods rodam no mesmo nó”. Convém guardar isso, porque o Exercício 2 o usa. Existem outros modos (`ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`); com a classe do kind, o que se aplica é este: a tabela da mesma página marca que um volume `HostPath` suporta apenas `ReadWriteOnce`, e a pasta vive em um nó.
- **`storageClassName: standard`** nomeia a classe. Escrever o nome, mesmo sendo a classe padrão, deixa o manifesto sem surpresas em um cluster onde a classe padrão seja outra.
- **`storage: 100Mi`** é o tamanho pedido: 100 mebibytes, a mesma unidade de memória da Lição 5. Em aritmética pura, 100 Mi dão para mais de um milhão de relatórios de 92 bytes. Em um sistema de arquivos real cada arquivo ocupa pelo menos um bloco (conferi na máquina de Docker da execução que um arquivo de 92 bytes ocupa 8 blocos de 512, ou seja 4096 bytes, com blocos de sistema de arquivos de 4096), então em 100 Mi cabem uns 25.600 arquivos, e com 288 relatórios por dia (um a cada cinco minutos) isso dá uns 89 dias de histórico antes de precisar limpar. Haverá algo a dizer mais adiante sobre o quanto um cluster leva a sério esse número.
- **Não há `volumeName`**: a solicitação não nomeia um volume. Pede uma classe e um tamanho, e o sistema resolverá o resto.

Antes de aplicar, a pergunta que a Lição 5 ensinou a fazer: o que mudaria?

```bash
kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
```

```text
$ kubectl diff -k . | grep -E '^\+ ' | grep -E 'kind: (PersistentVolumeClaim|CronJob|ServiceAccount)|schedule|concurrencyPolicy|storageClassName|storage:'
+  concurrencyPolicy: Forbid
+          schedulerName: default-scheduler
+  schedule: '*/5 * * * *'
+      storage: 100Mi
+  storageClassName: standard
[código de salida: 1]
```

O `diff` filtra só o que é adicionado (linhas que começam com `+ `) e, dessas, as que nomeiam o novo da lição: a política de concorrência, o horário, o tamanho e a classe. O script imprime `[código de salida: 1]` porque roda com `pipefail` e conserva o 1 do `kubectl diff` (há diferenças, como na Lição 5); no terminal de quem acompanha, o pipeline devolve o código do `grep` e aparecerá 0. (A linha de `schedulerName` é adicionada pelo cluster como valor padrão; o `grep` a pegou por conter a palavra `schedule`.)

#### 8.4.2 Aplicar, e ler o `Pending`

```bash
ctx && kubectl apply -k .
```

```text
$ kubectl apply -k .
namespace/revisor unchanged
serviceaccount/observador unchanged
serviceaccount/prueba unchanged
serviceaccount/reporte created
serviceaccount/revisor unchanged
role.rbac.authorization.k8s.io/observador unchanged
rolebinding.rbac.authorization.k8s.io/observador unchanged
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-hbc69k5m5c unchanged
service/prueba unchanged
service/revisor unchanged
persistentvolumeclaim/reportes created
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
cronjob.batch/reporte created
gateway.gateway.networking.k8s.io/revisor configured
httproute.gateway.networking.k8s.io/revisor configured
networkpolicy.networking.k8s.io/acceso-revisor-salida unchanged
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged
```

Os Deployments não mudaram (`unchanged`): nenhuma réplica foi reiniciada. O novo são três objetos, `serviceaccount/reporte`, `persistentvolumeclaim/reportes` e `cronjob.batch/reporte`. (Que `gateway` e `httproute` digam `configured` aparece neste `apply` e não muda nada que se veja no serviço; a lição não investiga isso.) E agora, o que importa:

```text
$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 1s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          0s

$ kubectl describe pvc reportes -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason                Age   From                         Message
  ----    ------                ----  ----                         -------
  Normal  WaitForFirstConsumer  1s    persistentvolume-controller  waiting for first consumer to be created before binding

$ kubectl get pv
No resources found
```

`STATUS Pending`, `VOLUME` vazio, `CAPACITY` vazia. Para quem vem das lições anteriores, `Pending` soa como problema (o Pod da Lição 5 que não cabia em nenhum nó). Aqui **não é**, e o evento diz com todas as letras: `waiting for first consumer to be created before binding`, “esperando que o primeiro consumidor seja criado antes de ligar”. É o modo `WaitForFirstConsumer` de 8.3.3 em ação. Ainda não há nenhum Pod que use a solicitação, então o cluster não decidiu em que nó vai rodar nada e, por isso, não pode decidir em que nó criar a pasta. E o `kubectl get pv` confirma: sem volume.

A diferença em relação ao `Pending` da Lição 5 é a que separa um diagnóstico do outro. Aqui o evento é de nível `Normal`, é emitido pelo `persistentvolume-controller` e diz que espera; lá era um `Warning` do agendador que dizia que não havia onde. A regra para ler qualquer `Pending` é a de sempre: os eventos dizem quem espera e o quê. Um `Pending` com `WaitForFirstConsumer` e nenhum Pod usando a solicitação é um sistema funcionando.

O `CronJob`, enquanto isso, existe e não rodou: `LAST SCHEDULE <none>`, `ACTIVE 0`. A sua primeira execução chegará no próximo múltiplo de cinco minutos do relógio. Para não esperar, a seção 8.5 ensina a pedir uma manualmente.

### 8.5 `Job`: a tarefa que termina

#### 8.5.1 O menor que serve

Um **`Job`** é, nas palavras da documentação, uma tarefa que roda “até ser concluída e então para”. Cria um ou mais Pods e tenta de novo “até que um número especificado deles termine com sucesso”. Quando esse número é alcançado, o Job está completo. O importante em relação ao Deployment é o que se considera sucesso: um Pod de um Job que termina com código 0 **é** o resultado esperado; em um Deployment, esse mesmo Pod seria uma falha, e o cluster o substituiria.

Antes do Job de verdade, um de treino: `fig08_01.job-salud.yaml`, que uma única vez pergunta ao `/salud` do `revisor` e termina. É um **programa**.

```yaml
# fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
# a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
# cerrada de la Lección 7 exige para que un Pod hable con el revisor.
apiVersion: batch/v1
kind: Job
metadata:
  name: salud
  namespace: revisor
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 120
  template:
    metadata:
      labels:
        app: salud
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
      - name: salud
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["curl", "-fsS", "-m", "5", "http://revisor/salud"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Leia-o de cima para baixo; quase tudo é conhecido. `apiVersion: batch/v1` e `kind: Job`: o grupo `batch` reúne os Jobs e os CronJobs. O `namespace: revisor` vai escrito no arquivo para que o Job caia ali sem precisar lembrar do `-n`. `spec.template` é o modelo do Pod, igual ao de um Deployment, mas com duas diferenças. A primeira: **não tem seletor**, porque o Job o atribui sozinho (a documentação adverte que “em quase todos os casos não se deve especificá-lo”). A segunda: `restartPolicy` é obrigatório e só admite dois valores, `Never` e `OnFailure`. Com `Never`, se o contêiner falha, o Pod fica como `Failed` e o Job cria outro; com `OnFailure`, o `kubelet` reinicia o contêiner dentro do mesmo Pod. O curso usa `Never`: cada tentativa é um Pod à parte, com o seu próprio log e o seu próprio código de saída, e dá para ler o que aconteceu em cada um. Com `OnFailure`, as tentativas ficariam empilhadas em um único Pod.

Os dois campos do Job que não são do Pod:

- **`backoffLimit: 2`**: quantas vezes tentar de novo antes de desistir. A documentação diz que o valor padrão é 6, e que os Pods que falham são recriados “com um backoff exponencial (10 s, 20 s, 40 s…) limitado a dez minutos”. Aqui 2 significa: a tentativa original mais duas novas, três Pods no máximo.
- **`activeDeadlineSeconds: 120`**: um teto de tempo para o Job inteiro, **não importa quantos Pods ele crie**. Quando é atingido, o cluster encerra os Pods que estão rodando e o Job passa a `Failed` com o motivo `DeadlineExceeded`. E a documentação precisa que esse prazo tem precedência sobre o `backoffLimit`: um Job que está tentando de novo não cria mais Pods quando o prazo chega, mesmo que não tenha esgotado as tentativas. Os dois tetos cobrem falhas distintas: um é para “falha rápido muitas vezes”, o outro para “fica travado”.

A tarefa em si, `curl -fsS -m 5 http://revisor/salud`, lê-se letra por letra. `-f` faz o curl sair com erro quando o servidor responde 400 ou mais (sem essa letra, um 503 sairia com código 0, e o Job o contaria como sucesso). `-sS` é silencioso mas mostra os erros. `-m 5` é o tempo máximo de toda a operação: 5 segundos. E o comando é escrito como lista (`["curl", ...]`) e não como um texto para um *shell*, porque a imagem do `curl` não precisa de um para isso.

```bash
ctx && kubectl apply -f fig08_01.job-salud.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/salud --timeout=180s
```

```text
$ kubectl apply -f fig08_01.job-salud.yaml
job.batch/salud created

$ kubectl get job,pods -n revisor -l app=salud
NAME              STATUS     COMPLETIONS   DURATION   AGE
job.batch/salud   Complete   1/1           4s         4s

NAME              READY   STATUS      RESTARTS   AGE
pod/salud-svx9s   0/1     Completed   0          4s

$ kubectl logs -n revisor job/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor salud -o jsonpath='{range .status.conditions[*]}{.type} {.status}{"\n"}{end}'
SuccessCriteriaMet True
Complete True
```

O Job levou 4 segundos e terminou com `COMPLETIONS 1/1`. O Pod ficou como `Completed` com `READY 0/1`: não é um erro. O contêiner terminou bem e já não roda, e o Pod é conservado para que se possa ler o seu log. `kubectl logs job/salud` encontra o Pod do Job e mostra o que o `curl` imprimiu: o JSON de `/salud`. As condições do Job são duas: `SuccessCriteriaMet` (o critério de sucesso foi cumprido) e `Complete` (terminou). Que haja duas e não uma tem a ver com algo que a documentação diz: desde a versão 1.31, o controlador de Jobs adia a condição terminal (`Complete` ou `Failed`) até que todos os Pods do Job tenham terminado. `SuccessCriteriaMet` (e a sua gêmea `FailureTarget`, que aparece em “O erro que a gente vai ver”) são as condições que aparecem antes: dizem que o desfecho já foi decidido.

Apaga-se para deixar o espaço como estava:

```text
$ kubectl delete -f fig08_01.job-salud.yaml
job.batch "salud" deleted from revisor namespace
```

A documentação diz: apagar um Job limpa os Pods que ele criou. Isso importa em 8.8, onde o apagamento dos Jobs passa a fazer parte da manobra.

#### 8.5.2 O relatório guardado: a primeira tarefa

Agora o Job da lição. Não é escrito à parte: o `CronJob` `reporte` já o traz dentro, como modelo, e o `kubectl` sabe criar um Job a partir dele a qualquer momento, sem esperar o horário. É a forma de testar uma tarefa agendada sem ficar olhando o relógio:

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
```

```text
$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-1
job.batch/reporte-manual-1 created

$ kubectl get pods -n revisor -l app=reporte -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE        READINESS GATES
reporte-manual-1-t7d8l   0/1     Pending   0          3s    <none>   <none>   curso-k8s-l8-worker   <none>

$ kubectl describe pvc reportes -n revisor | sed -n '/^Used By:/,$p'
Used By:       reporte-manual-1-t7d8l
Events:
  Type    Reason                Age              From                                                                                                Message
  ----    ------                ----             ----                                                                                                -------
  Normal  WaitForFirstConsumer  7s (x2 over 9s)  persistentvolume-controller                                                                         waiting for first consumer to be created before binding
  Normal  ExternalProvisioning  3s (x2 over 3s)  persistentvolume-controller                                                                         Waiting for a volume to be created either by the external provisioner 'rancher.io/local-path' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
  Normal  Provisioning          3s               rancher.io/local-path_local-path-provisioner-75f7fc7dc5-xl4bd_3605f90f-a3ba-46c3-a75e-a794883e9732  External provisioner is provisioning volume for claim "revisor/reportes"
```

Aqui está, em três segundos, a história que a seção 8.3.3 anunciou. O Pod da tarefa existe e está `Pending`, mas repare na coluna `NOMINATED NODE`: o agendador já **nomeou** um nó, `curso-k8s-l8-worker`, embora o Pod ainda não esteja atribuído (a coluna `NODE` continua em `<none>`). Com o modo `WaitForFirstConsumer`, o agendador decide primeiro onde o Pod vai rodar; a documentação de classes diz assim: o volume é selecionado ou provisionado “conforme a topologia especificada pelas restrições de agendamento do Pod”. Com essa decisão tomada, o provisionador da classe pode agir. Os eventos da solicitação contam o que aconteceu, de cima para baixo (a coluna `Age` diminui: 7 s, 3 s, 3 s): a solicitação esperava um consumidor (`WaitForFirstConsumer`); apareceu o Pod e o controlador avisou o provisionador (`ExternalProvisioning`, que quer dizer “um provisionador externo deve criar o volume”); o provisionador `rancher.io/local-path` começou (`Provisioning`). A captura foi feita aos 3 segundos e por isso termina aí; o evento seguinte, `ProvisioningSucceeded`, com o nome do volume criado (aqui `pvc-5fcf36b8-…`), chega um instante depois (em outra execução do mesmo script chegou a aparecer na captura). Por isso o “externo”: o provisionador é um programa à parte, um Pod do cluster, não parte do control plane.

A linha de cima, `Used By: reporte-manual-1-t7d8l`, é uma novidade desta versão: diz que Pod usa a solicitação. Junto dela, o `kubectl describe` pode mostrar uma tabela `Conditions` com a condição `Unused`, e aqui é preciso ser exato sobre o que foi medido: nesta captura a tabela **não saiu**: o controlador de proteção ainda não tinha escrito a condição (a captura foi feita aos 3 segundos). Repare que `Used By:` já lista o Pod mesmo estando `Pending`: para essa condição, um Pod conta como usuário enquanto não terminou, mesmo antes de ser atribuído a um nó; em outra execução do mesmo script, aos 3 segundos, saiu sim uma condição `Unused False` com o motivo `PodUsingPVC` (“um Pod está usando a solicitação”). Ou seja, a condição aparece conforme o instante em que se olha, e não dá para contar com vê-la. Cuidado com o alcance dela: a documentação define `Unused` apenas com Pods que não terminaram (um Pod em fase `Succeeded` ou `Failed` não conta), enquanto a proteção contra apagamento de 8.8 conta qualquer objeto Pod que use a solicitação. Um Pod `Completed` não mantém `Unused` em `False`, mas pode manter a solicitação em `Terminating`. O registro de mudanças do Kubernetes v1.37 explica: o recurso `PersistentVolumeClaimUnusedSinceTime` passou a beta e ficou ativado por padrão, e as solicitações “relatam a condição `Unused`, que indica há quanto tempo uma solicitação está sem uso, para ajudar a identificar candidatas à limpeza”. É uma pista útil em um cluster antigo: as solicitações com `Unused True` há meses são candidatas a revisão (pode ser que ainda tenham Pods terminados que as mantenham protegidas).

```text
$ kubectl logs -n revisor job/reporte-manual-1
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json

$ kubectl get pvc -n revisor
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 13s

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,CLASE:.spec.storageClassName,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0],RUTA:.spec.hostPath.path
NOMBRE                                     CLASE      NODO                  RUTA
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   standard   curso-k8s-l8-worker   /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
```

O log da tarefa é o `ls -ln` que ela mesma imprime depois de guardar: um arquivo, `reporte-20261021T232446Z.json`, com a data no nome (ano, mês, dia, `T`, hora, minuto, segundo, `Z` de UTC). Essa é a resposta à metade da cena: nada é sobrescrito. Dono `100`, grupo `101`: os do usuário da tarefa, o da imagem do `curl`.

A solicitação já está `Bound` (ligada), com o volume `pvc-5fcf36b8-…`, 100Mi, RWO, classe `standard`. E o volume, visto com as colunas que importam, tem dois dados que merecem explicação:

- **`NODO curso-k8s-l8-worker`**: o volume tem uma **afinidade de nó**. Está preso a um único nó, o que o agendador escolheu. É isso que faz dele um volume **local**: os dados estão no disco dessa máquina, e qualquer Pod que o use tem que rodar ali. Se esse nó se perder, os dados vão junto.
- **`RUTA /var/local-path-provisioner/pvc-…_revisor_reportes`**: a pasta real, no nó. O nome segue o padrão `<volume>_<namespace>_<solicitação>`, e é o lugar aonde se pode ir olhar.

```text
$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
777 0:0 /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
total 12
drwxrwxrwx 2   0   0 4096 Oct 21 23:24 .
drwxr-xr-x 3   0   0 4096 Oct 21 23:24 ..
-rw-r--r-- 1 100 101   92 Oct 21 23:24 reporte-20261021T232446Z.json
```

O diretório tem permissão `777` e dono `0:0` (`root`). Compare com o do `emptyDir` de 8.2.1: lá era `2777` e o grupo `65532`. Aqui não há *setgid* nem grupo da tarefa. **Embora o Pod da tarefa declare `fsGroup: 101`, o diretório deste volume não mudou de dono.** É o contraste com o segundo achado de 8.2.1, e a seção 8.7 o desenvolve: o que se mediu aqui é que o `fsGroup` não fez nada visível neste tipo de volume. A permissão `777` vem do provisionador, que segundo o seu README cria a pasta com `mkdir -m 0777`. Por isso a tarefa pôde escrever: não pelo seu grupo, mas porque a pasta deixa qualquer um entrar.

#### 8.5.3 O Pod terminou; o arquivo continua lá

A prova do volume é sobreviver ao Pod que o encheu. O Pod da primeira tarefa já terminou. Lança-se uma segunda tarefa, um Pod novo, com outro nome, que não tem nada a ver com o primeiro exceto que monta a mesma solicitação:

```bash
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
```

```text
$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-manual-1-t7d8l   0/1     Completed   0          7s

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-2
job.batch/reporte-manual-2 created

$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-manual-1   Complete   1/1           7s         15s
reporte-manual-2   Complete   1/1           5s         6s
```

O segundo Pod vê **dois** arquivos: o dele, das `23:24:51`, e o da primeira tarefa, das `23:24:46`, de um Pod que já não está rodando. Isso é o que o `emptyDir` não podia fazer. A solicitação, e o volume que a sustenta, têm um ciclo de vida independente do dos Pods. Enquanto a solicitação existir e o disco do nó que guarda a pasta continuar íntegro, os dados são conservados mesmo que os Pods que os escreveram tenham terminado.

Confirma-se o conteúdo pelo nó. O primeiro comando é o relatório em formato de tabela que a gente já conhece (só confirma que o `revisor` responde igual a antes); o segundo lê os arquivos que as tarefas deixaram, que guardam o que o `/api/estados` respondeu em cada momento:

```text
$ kubectl exec -n revisor depurar -- curl -s -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           6ms  200

$ docker exec curso-k8s-l8-worker sh -c 'cat /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes/reporte-*.json | head -9'
[
  {
    "servicio": "prueba",
    "ok": true,
    "codigo": 200,
    "tiempo_ms": 5
  }
]
[
```

(O `head -9` corta a saída em nove linhas: o primeiro arquivo completo e o início do segundo.) A cena de segunda-feira fica resolvida na sua forma: o relatório de sexta às 6 da tarde, horário da Cidade do México, seria um arquivo `reporte-20261017T0000…Z.json` (as 18h do México são as 00h UTC de sábado, e os segundos quase nunca são `00` porque o Pod inicia alguns segundos depois do horário), um entre dezenas, nenhum sobrescrito pelo seguinte.

Antes de seguir, duas perguntas que este desenho deixa e que a lição responde no seu lugar. Primeira: se o `CronJob` faz isso a cada cinco minutos, quem o faz funcionar? É a seção 8.6. Segunda: se a tarefa guarda um arquivo e o `revisor` também guarda `reporte.json` no seu `emptyDir`, por que o `revisor` não guarda diretamente no volume? A decisão do curso é que não, e o Exercício 2 deixa conferir por quê.

### 8.6 `CronJob`: a tarefa com horário

#### 8.6.1 O objeto, campo por campo

Um **`CronJob`** cria Jobs em um horário repetido. A [documentação](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) o compara com algo que talvez já seja conhecido: “um objeto CronJob é como uma linha de um arquivo *crontab* (tabela de cron) de um sistema Unix. Executa um Job periodicamente em um horário dado, escrito em formato Cron”. O que vem a seguir é a terceira peça do `reporte.yaml`, a que foi cortada em 8.4.1:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: reporte
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 60
      template:
        metadata:
          labels:
            app: reporte
            # la red (red.yaml) deja a estos Pods hablar con el revisor:8080
            acceso-revisor: permitido
        spec:
          serviceAccountName: reporte
          automountServiceAccountToken: false
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            runAsUser: 100
            runAsGroup: 101
            fsGroup: 101
            seccompProfile:
              type: RuntimeDefault
          containers:
          - name: reporte
            image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
            command:
            - sh
            - -c
            - >-
              curl -fsS -m 20
              -H "Authorization: Bearer $(cat /secretos/token)"
              -o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json
              http://revisor/api/estados
              && ls -ln /datos
            resources:
              requests: {cpu: 10m, memory: 16Mi}
              limits: {cpu: 100m, memory: 32Mi}
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
            persistentVolumeClaim:
              claimName: reportes
          - name: token
            secret:
              secretName: revisor-token
              defaultMode: 0440
```

Isto é o novo, de cima para baixo:

**`schedule: "*/5 * * * *"`** é o horário, no formato de cinco campos do cron. Segundo a documentação, da esquerda para a direita são: minuto (0 a 59), hora (0 a 23), dia do mês (1 a 31), mês (1 a 12) e dia da semana (0 a 6, de domingo a sábado). Um asterisco quer dizer “qualquer”, e `*/5` quer dizer “a cada cinco”: `*/5 * * * *` é “a cada cinco minutos, a qualquer hora, qualquer dia”. Os exemplos da documentação ajudam a ler outros: `0 3 * * 1` é “às segundas-feiras às 3 da manhã”. E as abreviações `@hourly`, `@daily`, `@weekly`, `@monthly` e `@yearly` existem como atalhos. O Exercício 4 pede para escrever dois horários.

**Em que fuso horário?** A documentação diz com clareza: para um CronJob sem fuso horário, o `kube-controller-manager` interpreta o horário no seu fuso local, que no kind é UTC. A coluna `TIMEZONE` da saída dizia `<none>`, que é justamente isso. Dá para fixá-lo com `.spec.timeZone` (por exemplo `"America/Mexico_City"`); colocar `TZ=` ou `CRON_TZ=` dentro do horário não é admitido e o cluster o rejeita com um erro de validação, segundo a documentação. Em um cluster real, o curso recomenda escrever o fuso; é a causa de mais de um “por que rodou às 4 da madrugada?”.

**`concurrencyPolicy: Forbid`**: o que fazer se chega a hora de uma execução nova e a anterior continua rodando. Os três valores, segundo a documentação: `Allow` (o valor padrão) deixa as duas rodarem ao mesmo tempo; `Forbid` não permite execuções concorrentes e pula a nova; `Replace` substitui a que está rodando pela nova. Para a tarefa do relatório, `Forbid` é a escolha prudente: duas tarefas escrevendo no mesmo volume ao mesmo tempo seria mais complicado do que o necessário. O Exercício 3 deixa ver os três trabalhando.

**`successfulJobsHistoryLimit: 3` e `failedJobsHistoryLimit: 3`**: quantos Jobs terminados conservar. Os valores padrão são 3 e 1, e um valor zero não conserva nenhum. Conservam-se porque são a evidência: sem eles, um Job que falhou desapareceria com o seu log e ninguém saberia por quê. Limitam-se porque sem teto se acumulariam (um Job a cada 5 minutos são 288 por dia).

**`jobTemplate`** é um Job completo, o que o CronJob cria a cada vez. Dentro dele, `backoffLimit: 2` e `activeDeadlineSeconds: 60` são os de 8.5.1, com um prazo de um minuto: se a tarefa travar, o cluster a corta antes que se sobreponha à seguinte.

**O modelo do Pod** já é familiar: a conta `reporte`, sem credenciais montadas; o `securityContext` da Lição 7 (sem `root`, usuário 100 e grupo 101 da imagem do `curl`); os recursos da Lição 5. O rótulo (label) `acceso-revisor: permitido` é o que abre a rede: sem ele o Pod não chega ao `revisor`, e a seção “O erro que a gente vai ver” demonstra isso. O volume `datos` é a solicitação `reportes`. E o volume `token` monta o `Secret` da Lição 4, como arquivo, com `defaultMode: 0440`.

Uma nota sobre o caminho `/secretos/token`: o arquivo se chama como a **chave** do Secret, e a Lição 4 a gerou com `token=token.txt` no Kustomize. Se um dia o Secret for montado manualmente com `kubectl create secret generic revisor-token --from-file=token.txt`, a chave será `token.txt` e o arquivo `/secretos/token.txt`; para que coincida, use `--from-file=token=token.txt`.

Uma coisa que merece parada: o `secretName` do arquivo diz `revisor-token`, sem o *hash*, igual ao do Deployment do `revisor`. O Kustomize o reescreve ao montar o resultado, **também dentro de um CronJob**. Confere-se:

```text
$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.schedule}{" "}{.spec.concurrencyPolicy}{" "}{.spec.successfulJobsHistoryLimit}{" "}{.spec.failedJobsHistoryLimit}{" "}{.spec.timeZone}{"\n"}'
*/5 * * * * Forbid 3 3

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[1].secret.secretName}{"\n"}'
revisor-token-hbc69k5m5c

$ kubectl get secret -n revisor -o name
secret/revisor-token-hbc69k5m5c
```

O campo `timeZone` saiu vazio (o horário vai em UTC). O nome do Secret dentro do modelo do CronJob é o gerado, com o seu *hash*: o Kustomize encontrou a referência e a trocou, como fez com o Deployment. Isso importa para os programas da lição: os exemplos `fig08_NN` que não passam pelo Kustomize (os que são aplicados com `kubectl apply -f`) não podem se referir ao Secret pelo nome-base, e por isso nenhum deles o monta.

A tarefa em si é um `sh -c` com dois comandos unidos por `&&`: o `curl` (com quatro opções e um endereço) e `ls -ln /datos`. Lê-se opção por opção, da esquerda para a direita: `curl -fsS -m 20` (como no Job de treino, mas com 20 segundos, porque montar um relatório consulta serviços e pode demorar mais); `-H "Authorization: Bearer $(cat /secretos/token)"` (o cabeçalho com o token, que é lido do arquivo montado no momento de rodar e nunca aparece escrito no manifesto); `-o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json` (guarda a resposta em um arquivo cujo nome leva a hora UTC daquele instante, com `date -u`); e `http://revisor/api/estados`, o endereço do Service. Se o `curl` falha, o `&&` impede que continue e a tarefa sai com o código do `curl`: o Job o conta como falha. Se funciona, `ls -ln /datos` imprime a listagem, que é o que se viu no log das tarefas manuais.

Por que um `curl` contra a API e não uma tarefa que execute o próprio `revisor` uma vez e termine? Porque o `revisor` é um servidor HTTP e não traz um modo “verifica uma vez”. É uma decisão do curso, não um truque: prefere-se aproveitar o programa tal como o curso de Docker o entrega, sem alterá-lo. A tarefa é um cliente do `revisor` como qualquer outro.

#### 8.6.2 Ver o horário passar

O horário de verdade é de cinco minutos. Para vê-lo funcionando sem esperar, `fig08_03.cron-cada-minuto.yaml` é um CronJob que roda a cada minuto (`* * * * *`) e pergunta ao `/salud`, que não pede token. É um **programa**; o modelo dele é o do Job de treino e o novo é o cabeçalho.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: salud-cada-minuto
  namespace: revisor
spec:
  schedule: "* * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 30
      template:
        # … la plantilla del Job de práctica (etiqueta acceso-revisor incluida), con una
        # diferencia: el comando imprime primero la hora, para poder leerla en la bitácora:
        #   command: ["sh", "-c", "date -u +%T; curl -fsS -m 5 http://revisor/salud"]
```

(O arquivo completo, com o modelo, está na pasta de programas.) O que muda em relação ao `reporte`: o horário, um histórico mais curto e `backoffLimit: 0`, que quer dizer “sem novas tentativas”: uma tarefa que roda a cada minuto não precisa ser repetida, porque o minuto seguinte é a nova tentativa. A espera está à vista: o script olha a cada 10 segundos quantos Jobs o CronJob terminou e para quando são dois.

```bash
ctx && kubectl apply -f fig08_03.cron-cada-minuto.yaml
```

```text
$ date -u +%H:%M:%S
23:24:56

$ kubectl get cronjob reporte -n revisor
NAME      SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
reporte   */5 * * * *   <none>     False     0        <none>          20s

$ kubectl apply -f fig08_03.cron-cada-minuto.yaml
cronjob.batch/salud-cada-minuto created

(esperando hasta 200 s a que el CronJob cree y termine 2 Job(s) «salud-cada-minuto…»; se mira cada 10 s)
  +  0 s: 0 Job(s) terminados
  + 10 s: 1 Job(s) terminados
  + 20 s: 1 Job(s) terminados
  + 30 s: 1 Job(s) terminados
  + 40 s: 1 Job(s) terminados
  + 50 s: 1 Job(s) terminados
  + 60 s: 1 Job(s) terminados
  + 70 s: 2 Job(s) terminados
```

Aos 10 segundos de criado já havia um Job terminado: o CronJob não esperou um minuto completo, mas o próximo **minuto do relógio** (`:25:00`), que chegou 4 segundos depois das `23:24:56`. Um horário cron não conta “a cada 60 segundos desde que me criaram”: dispara nos instantes que a sua fórmula marca no relógio. E aos 70 segundos, o segundo (o script olha a cada 10 segundos, e o minuto seguinte chegou aos 64).

```text
$ kubectl get cronjob,jobs -n revisor
NAME                              SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte             */5 * * * *   <none>     False     0        67s             91s
cronjob.batch/salud-cada-minuto   * * * * *     <none>     False     0        7s              71s

NAME                                   STATUS     COMPLETIONS   DURATION   AGE
job.batch/reporte-29877085             Complete   1/1           4s         67s
job.batch/reporte-manual-1             Complete   1/1           7s         86s
job.batch/reporte-manual-2             Complete   1/1           5s         77s
job.batch/salud-cada-minuto-29877085   Complete   1/1           4s         67s
job.batch/salud-cada-minuto-29877086   Complete   1/1           3s         7s
```

Há muito a ler aqui, e tudo é evidência de que o horário funciona:

- **O `cronjob.batch/reporte` também rodou, sozinho.** `LAST SCHEDULE 67s` e um Job novo, `reporte-29877085`, que ninguém criou: foi criado pelo CronJob às `23:25:00`, o múltiplo de cinco minutos mais próximo, enquanto a lição esperava outra coisa. A tarefa real do projeto já está trabalhando.
- **Os nomes dos Jobs.** `reporte-manual-1` foi nomeado por quem acompanha. `reporte-29877085` foi nomeado pelo CronJob: o nome dele, um hífen e um número. O número são os **minutos transcorridos desde 1º de janeiro de 1970 (UTC)**, a época do Unix: `29877085 × 60` segundos é `2026-10-21T23:25:00Z`, e `29877086`, o minuto seguinte. É um detalhe observado, não documentado, que serve para ler uma lista de Jobs de relance: dois números consecutivos são dois minutos seguidos. E daqui sai uma restrição que a documentação sim diz: o nome de um CronJob não deve passar de 52 caracteres, porque, segundo a documentação, o controlador acrescenta 11 caracteres e o nome de um Job não pode passar de 63 (na execução foram acrescentados 9: um hífen e 8 dígitos; a documentação reserva mais por prudência).
- **O CronJob de cada minuto tem dois Jobs, `…085` e `…086`**, de minutos consecutivos, e `LAST SCHEDULE 7s`: o último foi há 7 segundos.

```text
$ kubectl logs -n revisor -l app=salud --prefix --tail=3
[pod/salud-cada-minuto-29877085-lbt8h/salud] 23:25:01
[pod/salud-cada-minuto-29877085-lbt8h/salud] {"estado":"vivo","version":"1.6.0"}
[pod/salud-cada-minuto-29877086-j7h2l/salud] 23:26:01
[pod/salud-cada-minuto-29877086-j7h2l/salud] {"estado":"vivo","version":"1.6.0"}

$ kubectl get job -n revisor -l app=salud -o custom-columns=NOMBRE:.metadata.name,PROGRAMADA:.metadata.annotations.batch\\.kubernetes\\.io/cronjob-scheduled-timestamp
NOMBRE                       PROGRAMADA
salud-cada-minuto-29877085   2026-10-21T23:25:00Z
salud-cada-minuto-29877086   2026-10-21T23:26:00Z
```

Veja as horas dos logs: `23:25:01` e `23:26:01`; saem desse `date -u +%T` que o comando de `fig08_03` imprime antes do `curl`. O Job estava agendado para as `:00`, mas o Pod começou a rodar 1 segundo depois nos dois casos (em outra execução do mesmo script foram 5 e 9: o intervalo muda com a carga). Entre o instante do horário e o instante da execução há um intervalo: o CronJob cria o Job, o Job cria o Pod, o agendador o atribui e o `kubelet` inicia o contêiner. A anotação `batch.kubernetes.io/cronjob-scheduled-timestamp`, que o CronJob escreve em cada Job desde a versão 1.32, guarda a hora **original** do horário, em formato RFC 3339 (a forma `2026-10-21T23:25:00Z` que aparece na coluna `PROGRAMADA`): serve para saber qual execução foi qual, mesmo que tenham se atrasado. A documentação diz isso com uma advertência que convém ler inteira: um CronJob cria um Job “aproximadamente uma vez para cada instante do seu horário”, e é aproximado porque “há circunstâncias em que dois Jobs poderiam ser criados, ou nenhum. O Kubernetes tenta evitar essas situações, mas não as evita por completo. Portanto, os Jobs que forem definidos devem ser **idempotentes**”.

**Idempotente**, em sentido estrito, quer dizer: rodá-lo duas vezes deixa o mundo igual a rodá-lo uma. A tarefa do relatório **não** é estritamente idempotente: se por um tropeço rodasse duas vezes no mesmo minuto, deixaria dois arquivos e não um. O que ela é: **segura diante de repetições**. Como a hora do nome leva segundos, duas execuções escrevem dois arquivos distintos e nenhum sobrescreve o outro (se dois Pods rodassem no mesmo segundo exato, o segundo substituiria o primeiro por um relatório equivalente, sem corromper nada). Uma tarefa que somasse um contador ou enviasse um e-mail não seria segura assim, e seria preciso protegê-la de outra forma, por exemplo com uma chave única por horário. Essa é a razão de fundo de os nomes levarem a hora e não um número sequencial.

Apaga-se o CronJob de treino, e com ele os seus Jobs e Pods:

```text
$ kubectl delete -f fig08_03.cron-cada-minuto.yaml
cronjob.batch "salud-cada-minuto" deleted from revisor namespace

$ kubectl get jobs,pods -n revisor -l app=salud
No resources found in revisor namespace.
```

Mais duas coisas que a documentação do CronJob ensina, embora esta lição não as rode. A primeira: `.spec.suspend: true` suspende as execuções seguintes sem apagar nada; as que caem enquanto está suspenso contam como perdidas. A segunda: `startingDeadlineSeconds` diz quantos segundos depois da sua hora o Job ainda pode ser criado, e se passar disso, aquela execução é pulada. Sem esse campo, um controlador fora do ar por duas horas pode deixar muitas execuções pendentes; a documentação explica que, se há mais de 100 perdidas desde a última, o CronJob se recusa a iniciar e registra um erro. Em produção, com tarefas importantes, convém fixá-lo.

### 8.7 O dono dos arquivos: `fsGroup`

#### 8.7.1 O que o `fsGroup` mudou, e o que não

Desde a Lição 4, o Deployment do `revisor` leva `fsGroup: 65532` e o CronJob, `fsGroup: 101`. É hora de contar a história completa. O [guia do contexto de segurança](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) a explica com um exemplo. Um Pod com `fsGroup: 2000` faz com que “todos os processos do contêiner também façam parte do grupo suplementar 2000”, e “o dono do volume `/data/demo` e de qualquer arquivo criado nesse volume será o grupo 2000”. A saída de exemplo é o diretório com grupo 2000 e permissões `drwxrwsrwx`, o mesmo padrão que a gente já viu. E na seção de discussão: o `fsGroup` se aplica aos volumes “que suportam gerenciamento de donos”, que são modificados para pertencer ao grupo indicado pelo `fsGroup` e ser graváveis por ele.

Essas duas palavras, **que suportam**, são as que se medem aqui. Os três volumes da lição, um ao lado do outro. O último comando precisa do nome do nó e do `uid` de uma réplica **do cluster de quem acompanha**, que são outros; obtêm-se assim:

```bash
REV_POD="$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
REV_NODE="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.spec.nodeName}')"
REV_UID="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.metadata.uid}')"
docker exec "$REV_NODE" stat -c '%a %u:%g %n' "/var/lib/kubelet/pods/$REV_UID/volumes/kubernetes.io~empty-dir/datos"
```

A saída da execução, com o nó e o `uid` dessa réplica:

```text
$ kubectl get pod -n revisor -l app=revisor -o jsonpath='{.items[0].spec.securityContext.fsGroup}{"\n"}'
65532

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.securityContext}{"\n"}'
{"fsGroup":101,"runAsGroup":101,"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}}

$ docker exec curso-k8s-l8-worker2 stat -c '%a %u:%g %n' /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
2777 0:65532 /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
```

Aí estão os dois `fsGroup` declarados (65532 no `revisor`, 101 na tarefa). E o `stat` do `emptyDir` de um `revisor` atual: `2777` e grupo `65532`: **no `emptyDir`, o `fsGroup` sim mudou o grupo e colocou o *setgid***. Já o volume da solicitação `reportes` (8.5.2) tinha `777 0:0`, embora o seu Pod declarasse `fsGroup: 101`. A razão, como o README do provisionador contou e a medição confirma: o provisionador cria uma pasta comum do nó com permissão `0777`, e a medição mostra que o `kubelet` não mudou o grupo dela (a documentação só diz que o `fsGroup` atua sobre os volumes “que suportam gerenciamento de donos” e não dá a lista; o que medimos é que neste volume ele não fez isso, e que no `emptyDir` e no volume `local` de 8.7.2 fez. O PV que este provisionador cria é do tipo `hostPath`: a coluna `RUTA` de 8.5.2 sai de `spec.hostPath.path`). Também não foi preciso: com `777`, qualquer usuário escreve.

Isso não é um descuido do curso: é uma diferença entre a classe `standard` do kind e um disco que nasce com dono `root` e permissão `755`, como o que 8.7.2 fabrica manualmente. Ali, um contêiner que roda como usuário 100 recebe `Permission denied` ao tentar escrever, **a menos que** o `fsGroup` lhe dê o grupo do diretório. Com a classe `standard` do kind é pouco provável ver esse erro, e esse é justamente o perigo: um manifesto que funciona porque a pasta é `777` pode falhar em outro cluster pela mesma razão pela qual o `fsGroup` existe. Um manifesto que já leva `fsGroup` está mais perto de funcionar com um disco assim. Por isso o curso o escreve mesmo que aqui não se note.

#### 8.7.2 Um disco como os de verdade

Para ver o `fsGroup` trabalhando é preciso um volume que o suporte. O Kubernetes tem um à mão: o tipo `local`, uma pasta de um nó apresentada como um disco (a documentação o descreve como “um dispositivo de armazenamento local montado: um disco, uma partição ou um diretório”). Ao contrário do provisionador do kind, aqui **a gente** é o administrador: cria a pasta no nó, cria o PV que a descreve e cria a solicitação que o reivindica. É o caminho estático de 8.3.2. Usa-se como exemplo `fig08_04.disco-local.yaml`, um **programa** com dois objetos:

```yaml
# fig08_04.disco-local.yaml — Lección 8: un volumen creado a mano por «el administrador»,
# como los de un clúster real. Un PersistentVolume de tipo local (una carpeta de UN nodo,
# que hay que crear antes: mkdir -p /mnt/disco-reportes dentro del nodo curso-k8s-l8-worker)
# y la solicitud (PersistentVolumeClaim) que lo reclama. Su clase «manual» no existe como
# objeto: sirve solo de etiqueta para que la solicitud encuentre este volumen y no pida uno
# nuevo a la clase por omisión.
apiVersion: v1
kind: PersistentVolume
metadata:
  name: disco-reportes
spec:
  capacity:
    storage: 100Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  local:
    path: /mnt/disco-reportes
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [curso-k8s-l8-worker]
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: disco
  namespace: revisor
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: manual
  resources:
    requests:
      storage: 100Mi
```

Os campos novos do PV: **`capacity`** é o tamanho que ele oferece; **`persistentVolumeReclaimPolicy: Retain`** é a política de reclamação que 8.8 mede; **`local.path`** é a pasta do nó; e **`nodeAffinity`** é obrigatória em um volume `local`: a documentação diz “é preciso definir um `nodeAffinity` no PersistentVolume ao usar volumes `local`. O agendador do Kubernetes usa essa afinidade para agendar os Pods no nó correto”. Aqui diz que o volume está no nó cujo nome é `curso-k8s-l8-worker`. A classe `manual` não existe como objeto; é só uma palavra que une os dois objetos entre si e evita que a solicitação caia na classe padrão. Que a solicitação não falhe por uma classe inexistente (como acontece no Exercício 1) tem uma explicação: o provisionamento dinâmico só é tentado quando nenhum volume que já existe coincide com a solicitação, e aqui o PV existia.

A pasta do nó é preparada primeiro, com permissões de `root` e modo `755`, como a deixaria um disco recém-formatado, e depois o arquivo é aplicado:

```bash
docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes
docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
ctx && kubectl apply -f fig08_04.disco-local.yaml
```

```text
$ docker exec curso-k8s-l8-worker mkdir -p /mnt/disco-reportes

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
755 0:0 /mnt/disco-reportes

$ kubectl apply -f fig08_04.disco-local.yaml
persistentvolume/disco-reportes created
persistentvolumeclaim/disco created

$ kubectl get pv,pvc -n revisor
NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/disco-reportes                             100Mi      RWO            Retain           Bound    revisor/disco      manual         <unset>                          0s
persistentvolume/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound    revisor/reportes   standard       <unset>                          85s

NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/disco      Bound    disco-reportes                             100Mi      RWO            manual         <unset>                 0s
persistentvolumeclaim/reportes   Bound    pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 94s
```

O `stat` do nó diz `755 0:0`: de `root`, e só o `root` pode escrever. O PV `disco-reportes` nasce `Bound` (ligado) no mesmo segundo em que existe, com política `Retain`, e a solicitação `disco` também sai `Bound` nesta captura. Atenção: o instante importa. Em outras duas execuções do mesmo script a captura caiu antes de a ligação terminar: uma vez com a solicitação ainda `Pending` e o volume já `Bound`, outra com o volume ainda `Available`. A ligação leva uma fração de segundo; se no terminal de quem acompanha aparecer `Pending`, é só repetir o `get` e ela se completa. Não houve espera pelo primeiro consumidor: a classe `manual` não é uma classe com modo de ligação adiada, e o volume já existia. Mais abaixo, o volume `pvc-5fcf36b8-…` é o de `reportes`, com a política `Delete` da sua classe. Em um cluster real a classe não ficaria como rótulo solto: a documentação pede criar uma `StorageClass` para os volumes `local` com `volumeBindingMode: WaitForFirstConsumer`, para que a solicitação não se ligue a um disco de um nó antes de saber onde o Pod vai rodar. Aqui isso é omitido porque há um único PV e a afinidade dele decide o nó.

Agora, dois Pods que fazem o mesmo e só se diferenciam em uma linha. Escrevem um arquivo em `/datos`, rodando como o usuário 100 e o grupo 101, sem `root`. O primeiro, `fig08_05.escritor-sin-fsgroup.yaml`, não declara `fsGroup`:

```yaml
# fig08_05.escritor-sin-fsgroup.yaml — Lección 8: un Pod que corre sin root (usuario 100,
# grupo 101) e intenta escribir en el disco local de fig08_04, cuyo directorio es de root
# con permiso 0755. Sin fsGroup, nadie le cambia el dueño al directorio: Permission denied.
apiVersion: v1
kind: Pod
metadata:
  name: sin-fsgroup
  namespace: revisor
  labels:
    app: escritor
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
  - name: escritor
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sh", "-c", "id; ls -lnd /datos; echo hola > /datos/a.txt && ls -ln /datos"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
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
    persistentVolumeClaim:
      claimName: disco
```

O segundo, `fig08_06.escritor-con-fsgroup.yaml`, é o mesmo arquivo com `name: con-fsgroup` e uma linha a mais no `securityContext` do Pod: `fsGroup: 101`. O comando de ambos é curto: `id` imprime quem é o processo; `ls -lnd /datos` imprime o dono e a permissão do diretório montado; e `echo hola > /datos/a.txt && ls -ln /datos` tenta escrever e, se conseguiu, lista.

```bash
ctx && kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
```

```text
$ kubectl apply -f fig08_05.escritor-sin-fsgroup.yaml
pod/sin-fsgroup created

$ kubectl get pod -n revisor sin-fsgroup
NAME          READY   STATUS   RESTARTS   AGE
sin-fsgroup   0/1     Error    0          4s

$ kubectl logs -n revisor sin-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxr-xr-x    2 0        0             4096 Oct 21 23:26 /datos
sh: can't create /datos/a.txt: Permission denied
```

Esse é o erro que o `fsGroup` evita, medido. Lê-se em três linhas: o processo é o usuário 100, com o grupo 101 e nenhum outro; o diretório é de `0:0` com `drwxr-xr-x` (só o `root` escreve: o usuário 100 cai na categoria “outros”, que tem leitura e entrada, mas não escrita); e o `sh` diz sem rodeios, `can't create /datos/a.txt: Permission denied`. O Pod ficou em `Error`: o comando falhou, e com `restartPolicy: Never` não é reiniciado. Agora o mesmo Pod com a linha a mais:

```bash
ctx && kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
ctx && kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
```

```text
$ kubectl delete -f fig08_05.escritor-sin-fsgroup.yaml
pod "sin-fsgroup" deleted from revisor namespace

$ kubectl apply -f fig08_06.escritor-con-fsgroup.yaml
pod/con-fsgroup created

$ kubectl get pod -n revisor con-fsgroup
NAME          READY   STATUS      RESTARTS   AGE
con-fsgroup   0/1     Completed   0          3s

$ kubectl logs -n revisor con-fsgroup
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)
drwxrwsr-x    2 0        101           4096 Oct 21 23:26 /datos
total 4
-rw-r--r--    1 100      101              5 Oct 21 23:26 a.txt

$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /mnt/disco-reportes
2775 0:101 /mnt/disco-reportes
```

`Completed`, e o arquivo `a.txt` de 5 bytes (`hola` e uma quebra de linha) escrito. Veja o diretório no log: `drwxrwsr-x`, grupo `101`. E no nó, o `stat` diz `2775 0:101`: **o `kubelet` mudou o grupo da pasta para 101 e deu permissão de escrita a esse grupo, com *setgid*, antes de iniciar o contêiner**. O processo é do grupo 101, e por isso pode escrever. O dono continua sendo `root`; o que mudou foi o grupo. É o que diz a documentação: os volumes que suportam gerenciamento de donos “são modificados para pertencer ao GID indicado pelo `fsGroup` e ser graváveis por ele”.

O *setgid* (o `s`) tem um efeito prático que faz o `fsGroup` valer a pena: os arquivos criados dentro do diretório **herdam o grupo dele**, o 101, e não o grupo primário do processo que os cria. Aqui o efeito não se nota, porque o processo já é do grupo 101 (`runAsGroup: 101`); notaria-se em um processo com outro grupo primário. E para que outro Pod do grupo 101 possa *modificar* esses arquivos, cada arquivo precisaria de permissão de grupo (umask 002), coisa que esta tarefa não pede: os arquivos dela saem `-rw-r--r--`.

Uma nota de custo, que a documentação do contexto de segurança explica: por padrão, o Kubernetes muda o dono e as permissões de **todo o conteúdo** do volume cada vez que ele é montado. Para um volume com milhões de arquivos, isso demora e atrasa a inicialização do Pod. O campo `fsGroupChangePolicy: OnRootMismatch` pede que a mudança seja feita só se o dono ou a permissão da raiz do volume não coincidirem com o esperado, e evita percorrê-lo quando já está em ordem. Com volumes de 100 Mi não se nota; com discos grandes, sim.

#### 8.7.3 Retain: o volume sobrevive à sua solicitação

Os dois Pods já não são necessários. E o disco manual serve, além disso, para ver o que não se pode ver com `Delete`: a política `Retain`. Apaga-se a solicitação:

```bash
ctx && kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
ctx && kubectl delete pvc -n revisor disco
```

```text
$ kubectl delete -f fig08_06.escritor-con-fsgroup.yaml
pod "con-fsgroup" deleted from revisor namespace

$ kubectl delete pvc -n revisor disco
persistentvolumeclaim "disco" deleted from revisor namespace

$ kubectl get pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM              STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
disco-reportes                             100Mi      RWO            Retain           Released   revisor/disco      manual         <unset>                          11s
pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            Delete           Bound      revisor/reportes   standard       <unset>                          96s
```

A solicitação foi embora; o volume **não**. O estado dele é `Released` (“liberado”), que a documentação define assim: “a solicitação foi apagada, mas o recurso de armazenamento associado ainda não foi reclamado pelo cluster”. Com `Retain`, o volume fica com o seu `CLAIM revisor/disco` anotado e não está disponível para outra solicitação, porque “os dados do reivindicante anterior continuam no volume”. Recuperá-lo é um trabalho manual do administrador, em três passos que a documentação indica: apagar o PV, limpar os dados do armazenamento e apagar o armazenamento associado (ou reutilizá-lo com um PV novo). Apaga-se o PV e olha-se o disco:

```text
$ kubectl delete pv disco-reportes
persistentvolume "disco-reportes" deleted

$ docker exec curso-k8s-l8-worker ls -ln /mnt/disco-reportes
total 4
-rw-r--r-- 1 100 101 5 Oct 21 23:26 a.txt
```

O objeto PV desapareceu do Kubernetes; a pasta do nó, e o arquivo `a.txt` que o Pod escreveu, continuam lá. Isso é `Retain`: o cluster solta o objeto e não toca nos dados. É a política que se escolhe para dados que não devem desaparecer por um `kubectl delete` equivocado, em troca de um trabalho de limpeza manual. (A pasta vive dentro do contêiner do nó, então o `kind delete cluster` a leva junto. Para que alguns dados sobrevivam ao cluster inteiro, a [configuração do kind](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts) permite montar uma pasta da máquina dentro de um nó com `extraMounts`; o curso não faz isso.)

### 8.8 Apagar a solicitação: aí sim se perde

A política da classe `standard` é `Delete`. Mede-se o que acontece com a solicitação `reportes`, a que guarda os relatórios da lição. Primeiro olha-se a política, depois pede-se o apagamento **sem esperar** (`--wait=false`), porque o que vem a seguir pode ficar esperando:

```bash
ctx && kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
ctx && kubectl delete pvc -n revisor reportes --wait=false
```

```text
$ kubectl get storageclass standard -o jsonpath='{.reclaimPolicy}{"\n"}'
Delete

$ kubectl delete pvc -n revisor reportes --wait=false
persistentvolumeclaim "reportes" deleted from revisor namespace

$ kubectl get pvc -n revisor
NAME       STATUS        VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
reportes   Terminating   pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804   100Mi      RWO            standard       <unset>                 111s

$ kubectl get pvc -n revisor reportes -o jsonpath='{.metadata.finalizers} {.metadata.deletionTimestamp}{"\n"}'
["kubernetes.io/pvc-protection"] 2026-10-21T23:26:21Z

$ kubectl get pods -n revisor -l app=reporte
NAME                     READY   STATUS      RESTARTS   AGE
reporte-29877085-6q87g   0/1     Completed   0          86s
reporte-manual-1-t7d8l   0/1     Completed   0          105s
reporte-manual-2-4hmmf   0/1     Completed   0          96s
```

`Terminating`: foi pedido que se apague e não é apagada. O comando devolveu o controle porque tinha `--wait=false`; sem essa opção, o `kubectl delete` teria ficado esperando. A explicação está em `finalizers: ["kubernetes.io/pvc-protection"]`, que é uma *marca* que impede que um objeto desapareça até que algo a retire. A documentação chama essa função de **proteção de objetos de armazenamento em uso**, e seu propósito é “garantir que as solicitações em uso ativo por um Pod, e os volumes ligados a solicitações, não sejam removidos do sistema, pois isso poderia resultar em perda de dados”. E define o que é “em uso ativo”: **uma solicitação está em uso quando existe um objeto Pod que a usa.** Se for apagada nesse caso, “o apagamento é adiado até que nenhum Pod a use”.

Veja a última saída: três Pods `Completed`. Terminaram há tempo e já não rodam, mas **existem como objetos** (foram conservados para ler o log), e cada um declara nos seus volumes a solicitação `reportes`. Para a proteção, continuam usando-a. A solicitação espera que esses Pods deixem de existir. A saída não é forçar o apagamento, e sim retirar quem a sustenta: apagar os Jobs, que levam os seus Pods junto.

```bash
ctx && kubectl delete jobs -n revisor --all
```

```text
$ kubectl delete jobs -n revisor --all
job.batch "reporte-29877085" deleted from revisor namespace
job.batch "reporte-manual-1" deleted from revisor namespace
job.batch "reporte-manual-2" deleted from revisor namespace

$ kubectl get pvc,pv
No resources found

$ docker exec curso-k8s-l8-worker ls -la /var/local-path-provisioner/
total 8
drwxr-xr-x  2 root root 4096 Oct 21 23:26 .
drwxr-xr-x 12 root root 4096 Oct 21 23:24 ..
```

Assim que os Pods foram embora, o apagamento da solicitação avançou: já não há solicitação nem volume (`No resources found`), e a pasta do nó, `pvc-5fcf36b8-…_revisor_reportes`, **desapareceu com todos os seus relatórios**. O diretório `/var/local-path-provisioner/` ficou vazio. É a política `Delete` em ação: apaga-se a solicitação, apaga-se o volume e apaga-se o armazenamento. No apagamento da execução não deu para ver o estado intermediário `Released` do volume dinâmico (o script olhou 8 segundos depois de apagar os Jobs e para então o volume já não existia; não sei em quanto tempo exato ele desapareceu); o de 8.7.3, com `Retain`, sim o mostrou.

Recriar a solicitação e pedir uma tarefa nova mostra o que sobra: nada do passado.

```bash
ctx && kubectl apply -k . | grep persistentvolumeclaim
ctx && kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
```

```text
$ kubectl apply -k . | grep persistentvolumeclaim
persistentvolumeclaim/reportes created

$ kubectl create job -n revisor --from=cronjob/reporte reporte-manual-3
job.batch/reporte-manual-3 created

$ kubectl logs -n revisor job/reporte-manual-3
total 4
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
```

Um único arquivo: o de agora. Os relatórios do passado não estão. Com isso, a regra da seção fica em uma frase para quando um dia isso for feito sem querer: **com a política `Delete`, os dados vivem o que viver a solicitação e o apagamento da solicitação leva os dados junto; com `Retain`, sobrevivem a ela e alguém tem que limpá-los** (8.7.3). A política é da classe, não de quem apaga: por isso convém saber qual é a classe antes de apagar qualquer coisa que se chame `pvc`.

## O erro que a gente vai ver

Esta lição tem dois erros de propósito. O segundo já apareceu em 8.7.2: o `Permission denied` do Pod que escreve em um volume de `root` sem `fsGroup`. O primeiro é o de uma tarefa que nunca chega ao `revisor`.

### BackoffLimitExceeded: um Job que não consegue sair

`fig08_02.job-sin-etiqueta.yaml` é o Job de treino de 8.5.1 com **uma** diferença: falta o rótulo (label) `acceso-revisor: permitido`. É o erro que se comete ao copiar um modelo e esquecer uma linha que não se vê.

```bash
diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
ctx && kubectl apply -f fig08_02.job-sin-etiqueta.yaml
```

O `diff` não é rodado pelo script (não toca o cluster); esta é a saída dele, rodada na pasta de programas. Além dos comentários do cabeçalho e do nome, a única diferença de conteúdo é a linha do rótulo:

```text
$ diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
1,3c1,4
< # fig08_01.job-salud.yaml — Lección 8: el Job más pequeño que sirve. Una vez, le pregunta
< # a /salud del revisor y termina. Lleva la etiqueta acceso-revisor: permitido, la que la red
< # cerrada de la Lección 7 exige para que un Pod hable con el revisor.
---
> # fig08_02.job-sin-etiqueta.yaml — Lección 8: el MISMO Job de fig08_01, sin la etiqueta
> # acceso-revisor. La red cerrada de la Lección 7 no lo deja salir hacia el revisor: curl se
> # rinde a los 5 s (código 28), el Job reintenta dos veces y termina Failed con
> # BackoffLimitExceeded.
7c8
<   name: salud
---
>   name: salud-sin-etiqueta
16d16
<         acceso-revisor: permitido
```

Um Job assim não falha de imediato. Tenta de novo, com as esperas que 8.5.1 contou, e a lição acompanha à vista, a cada 15 segundos:

```text
$ kubectl apply -f fig08_02.job-sin-etiqueta.yaml
job.batch/salud-sin-etiqueta created

(esperando hasta 150 s a que el Job agote sus reintentos; se mira cada 15 s)
  + 15 s: 1 fallidos,  activos, condiciones:
  + 30 s: 2 fallidos,  activos, condiciones:
  + 45 s: 2 fallidos, 1 activos, condiciones:
  + 60 s: 3 fallidos,  activos, condiciones: FailureTarget=True Failed=True

$ kubectl get job,pods -n revisor -l app=salud
NAME                           STATUS   COMPLETIONS   DURATION   AGE
job.batch/salud-sin-etiqueta   Failed   0/1           61s        61s

NAME                           READY   STATUS   RESTARTS   AGE
pod/salud-sin-etiqueta-9bnv9   0/1     Error    0          61s
pod/salud-sin-etiqueta-svs9r   0/1     Error    0          44s
pod/salud-sin-etiqueta-tr95q   0/1     Error    0          19s
```

**Primeiro, o estado.** Aos 61 segundos, o Job está `Failed` e tem três Pods, os três `Error`. São exatamente os que o `backoffLimit: 2` indicou: o original e duas novas tentativas. As idades (`61s`, `44s`, `19s` desde que foram criados, lidas ao contrário) contam a espera crescente da documentação: o segundo Pod nasceu 17 segundos depois do primeiro (5 do `curl` mais 10 de espera) e o terceiro 25 depois do segundo (5 mais 20). Não são segundos redondos porque o cluster acrescenta alguns a mais ao criar Pods.

**Segundo, o log, porque o contêiner sim rodou.**

```text
$ kubectl logs -n revisor job/salud-sin-etiqueta
Found 3 pods, using pod/salud-sin-etiqueta-9bnv9
curl: (28) Connection timed out after 5000 milliseconds

$ kubectl get pods -n revisor -l app=salud -o custom-columns=POD:.metadata.name,CODIGO:.status.containerStatuses[0].state.terminated.exitCode,RAZON:.status.containerStatuses[0].state.terminated.reason
POD                        CODIGO   RAZON
salud-sin-etiqueta-9bnv9   28       Error
salud-sin-etiqueta-svs9r   28       Error
salud-sin-etiqueta-tr95q   28       Error
```

O `kubectl logs job/…` avisa que há três Pods e que mostra um. A mensagem do `curl` é a que a gente conhece da Lição 7: **código 28**, “a conexão expirou”. A rede fechada não deixa sair um Pod sem o rótulo de acesso em direção ao `revisor`, e não responde com uma recusa: simplesmente não responde, e o `curl` espera os seus 5 segundos (`-m 5`) e desiste. Os três Pods terminaram com código 28. É a mesma falha da “entrada aberta que não entra” da Lição 7, vista a partir de uma tarefa.

**Terceiro, o Job: por que desistiu.**

```text
$ kubectl get job -n revisor salud-sin-etiqueta -o jsonpath='{range .status.conditions[*]}{.type} {.status} {.reason}: {.message}{"\n"}{end}'
FailureTarget True BackoffLimitExceeded: Job has reached the specified backoff limit
Failed True BackoffLimitExceeded: Job has reached the specified backoff limit

$ kubectl describe job -n revisor salud-sin-etiqueta | sed -n '/^Events:/,$p'
Events:
  Type     Reason                Age   From            Message
  ----     ------                ----  ----            -------
  Normal   SuccessfulCreate      62s   job-controller  Created pod: salud-sin-etiqueta-9bnv9
  Normal   SuccessfulCreate      45s   job-controller  Created pod: salud-sin-etiqueta-svs9r
  Normal   SuccessfulCreate      20s   job-controller  Created pod: salud-sin-etiqueta-tr95q
  Warning  BackoffLimitExceeded  10s   job-controller  Job has reached the specified backoff limit
```

`BackoffLimitExceeded` (“o limite de novas tentativas foi excedido”) é o motivo da falha, tal como a documentação lista as causas pelas quais um Job falha: “o número de falhas de Pods excedeu o `.spec.backoffLimit`”. Os eventos, de cima para baixo, são a história em quatro linhas: três criações e a desistência.

**Quarto, a causa, que o Job não sabe dizer.** Nada do que vem acima diz *por que* o `curl` expira. Isso quem diz é a comparação com o que funciona. O `depurar`, que em 8.1 falava bem com o `revisor`, leva um rótulo que este Job não tem:

```text
$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          3m36s   acceso-revisor=permitido,app=depurar
```

`acceso-revisor=permitido` é o rótulo (label) que as políticas de rede da Lição 7 exigem. O Job da lição, o `CronJob` real, o leva no seu modelo, com um comentário que o explica; este não. **A correção** é a de sempre: o arquivo é a verdade. Acrescenta-se a linha ao manifesto e aplica-se de novo; aqui, simplesmente, apaga-se o experimento:

```text
$ kubectl delete -f fig08_02.job-sin-etiqueta.yaml
job.batch "salud-sin-etiqueta" deleted from revisor namespace
```

Duas lições deste erro. **A primeira**: um Job que falha diz que falhou, não por quê; a causa está no log dos seus Pods (`curl: (28)`) e no que se sabe da rede. **A segunda**: uma tarefa agendada que falha às 3 da madrugada não acorda ninguém. O `CronJob` conserva os últimos três Jobs que falharam (`failedJobsHistoryLimit: 3`) justamente para que alguém, no dia seguinte, possa ir ler o que aconteceu com eles. Sem vigilância, uma tarefa que falha em silêncio durante semanas produz o contrário do que prometia: a sensação de que há um backup onde não há. É a lição do relato do GitLab que abriu a lição, em ponto pequeno.

A ordem para uma tarefa que não funcionou: `kubectl get jobs` (`Failed`?); os Pods do Job (`kubectl get pods -l …`) e o código de saída de cada um; o log (`kubectl logs job/…`); e, se o Job não criou nem um Pod, os eventos do próprio Job (`kubectl describe job`). Antes de mudar qualquer coisa, saber se falhou uma vez, sempre, ou às vezes.

## O hábito de segurança da lição: os dados com o seu dono

A tabela de hábitos do curso atribui a esta lição duas coisas: o `ServiceAccount` sem credenciais montadas se não precisar delas, e os dados com o seu dono. As duas se conferem no cluster.

**A conta de serviço da tarefa.** A tarefa fala com o `revisor` por HTTP; não fala com a API do cluster. Não precisa de uma credencial para isso e, portanto, ela não é montada:

```text
$ kubectl get serviceaccount reporte -n revisor -o jsonpath='{.automountServiceAccountToken}{"\n"}'
false

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.automountServiceAccountToken}{" "}{.spec.jobTemplate.spec.template.spec.containers[0].env}{"\n"}'
false

$ kubectl get pods -n revisor -l app=reporte -o custom-columns=POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name
POD                      CUENTA    AUTOMOUNT   VOLUMENES
reporte-manual-3-2657n   reporte   false       datos,token

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/api/estados
401
```

`false` na conta, `false` no modelo do CronJob, e `env` vazio (o segundo valor da segunda saída é nada: a tarefa não recebe variáveis com segredos). Os volumes do Pod da tarefa são dois e se chamam `datos` e `token`: **nenhum é a credencial da API**. Se alguém conseguisse executar código dentro da tarefa, não encontraria um token do cluster para roubar. E o token do `revisor` vai como arquivo somente leitura com `0440`, não como variável de ambiente: é o que a Lição 4 ensinou. A última saída é a prova de que o `revisor` continua exigindo-o: sem token, `401`.

**Os dados com o seu dono.** As três peças que foram medidas:

- **O grupo do volume quem coloca é o `fsGroup`**, não uma permissão aberta. Em um disco real, a solução para um `Permission denied` é dar o grupo, não `chmod 777`. Em 8.7.2 o volume era de `root` com `755`, e com uma linha ficou em `2775 0:101`: de `root`, grupo 101, gravável só por esse grupo (e legível por todos).
- **O processo roda sem `root`** e o arquivo que ele cria é dele: `-rw-r--r-- 1 100 101` na tarefa; `-rw------- 1 65532 65532` no `revisor`. Cada escritor deixa a sua marca, e dá para saber quem escreveu o quê.
- **O token não chega ao volume de dados.** A tarefa lê o token de `/secretos`, um volume somente leitura, e escreve só em `/datos`. Manter separadas a entrada e a saída impede que um erro da tarefa escreva o segredo em um lugar onde ele fique guardado.

**O tamanho que o cluster não faz respeitar.** Falta uma surpresa, a da seção 8.4.1, onde se comentou que haveria algo a dizer sobre o quanto um cluster leva a sério o número `100Mi`. O volume pediu 100 mebibytes e o cluster disse `CAPACITY 100Mi`. Testa-se com um Job, `fig08_07.llenar-el-volumen.yaml`, que escreve 150 milhões de bytes (uns 143 MiB) nesse mesmo volume:

```bash
ctx && kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
ctx && kubectl apply -f fig08_07.llenar-el-volumen.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/llenar --timeout=180s
ctx && kubectl logs -n revisor job/llenar
ctx && kubectl delete -f fig08_07.llenar-el-volumen.yaml
```

(O `wait` evita pedir o log antes de o Pod terminar de escrever; o script o roda sem imprimi-lo.)

```text
$ kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
100Mi 100Mi

$ kubectl apply -f fig08_07.llenar-el-volumen.yaml
job.batch/llenar created

$ kubectl logs -n revisor job/llenar
total 146496
-rw-r--r--    1 100      101      150000000 Oct 21 23:27 grande.bin
-rw-r--r--    1 100      101             92 Oct 21 23:26 reporte-20261021T232640Z.json
/dev/root                57.1G     48.4G      8.6G  85% /datos

$ kubectl delete -f fig08_07.llenar-el-volumen.yaml
job.batch "llenar" deleted from revisor namespace
```

O Job terminou sem erro e o `ls` mostra `grande.bin` de **150000000 bytes** em um volume que pediu e recebeu 100Mi. E o `df` de dentro do Pod mostra o motivo: o “volume” `/datos` aparece como `/dev/root`, de 57,1 GB, com 85 % usado: é o disco do nó, que no kind é o da máquina de Docker, não um pedaço de 100 Mi (o nome do dispositivo e o tamanho mudam na máquina de cada um). É exatamente o que o README do provisionador anunciou (“a capacidade é ignorada por enquanto”): o número de `storage` decide com que PV a solicitação se liga, mas a classe do kind não limita o que se escreve.

Este é um achado de laboratório que convém não esquecer: **com a classe do kind, o que se pede não é o que se obtém; em outros armazenamentos depende do sistema, e convém medir**. Em um cluster real, o armazenamento de verdade sim tem tamanho e enche (com um erro `No space left on device` que derruba a aplicação no meio de uma escrita), e um namespace sem cota pode criar solicitações de qualquer tamanho. A cota de armazenamento (`ResourceQuota`, com `requests.storage`) coloca um máximo por namespace, como se comentou na Lição 5 para a CPU e a memória; o curso a menciona e não a instala.

**O que protege e o que não protege.** Estes costumes protegem que a tarefa não tenha mais poder do que precisa, que o token não vaze para o disco, e que os arquivos tenham um dono identificável. Não protegem os dados: um `Delete` os apaga (8.8), um nó fora do ar os torna inacessíveis (o volume está em um único disco), e ninguém faz backup deles. O que cuida dos dados de verdade é a linha que a lição 10 coloca na lista do que falta para a produção: armazenamento replicado fora do nó, snapshots de volume e backups que sejam **testados** restaurando. Uma frase sobre cada um, para saber que problema resolve: um `StatefulSet` é o objeto para aplicações com estado, cujos Pods têm identidade estável e um volume próprio cada um (o curso não o usa); um snapshot de volume é uma cópia do volume em um instante, que serve para voltar atrás; e um backup testado é a cópia que alguém já restaurou em outro lugar e conferiu, que é justamente o que faltou ao relato do GitLab do começo.

## O que se faz errado

**Guardar em um `emptyDir` o que deve sobreviver ao Pod.** Viu-se em 8.2.3: o contêiner se salva de uma queda, o Pod não se salva de um apagamento, e esvaziar um nó (`drain`), uma remoção por pressão de recursos (*eviction*) ou um nó declarado perdido apagam Pods; uma reinicialização do nó não necessariamente, mas também não convém apostar nisso. Um `emptyDir` é para espaço de trabalho, não para histórico.

**Achar que `Pending` em uma solicitação é um erro.** Com `WaitForFirstConsumer`, uma solicitação sem Pod fica `Pending` corretamente. Lê-se o evento antes de agir.

**Colocar `storage: 100Mi` e achar que termina aí.** No kind, o tamanho não é imposto (o mede “O hábito de segurança”). Em produção, o disco enche. É preciso vigiar o uso, com alertas, antes que chegue ao teto.

**Apagar uma solicitação (`pvc`) sem saber a política da classe.** Com `Delete`, os dados são apagados. Com `Retain`, são conservados e alguém deve limpá-los. Olha-se `RECLAIMPOLICY` antes.

**Apagar um PV manualmente para “liberar” uma solicitação presa.** A solicitação em `Terminating` espera pelos Pods que a usam; o PV tem a sua própria proteção. Forçar finalizadores (`kubectl patch … finalizers`) pulando a proteção é a forma de danificar dados em uso. Encontra-se e apaga-se o que a sustenta (nesta lição, os Jobs).

**Usar `chmod 777` ou um volume aberto para que “agora escreva”.** É o que faz o provisionador do kind, e por isso o problema raramente aparece. Em um disco de verdade o remédio é `fsGroup` e um usuário sem `root`, não abrir o diretório para todos.

**Escrever uma tarefa que não suporta rodar duas vezes.** A documentação avisa: o CronJob pode criar dois Jobs ou nenhum. Uma tarefa que soma, envia ou cobra sem proteção é uma duplicata esperando para acontecer.

**Deixar `concurrencyPolicy: Allow` por padrão em uma tarefa que escreve em um volume compartilhado.** Duas tarefas ao mesmo tempo na mesma pasta, e uma tarefa lenta que se sobrepõe à seguinte, podem acumular Pods sem que ninguém perceba. `Forbid` ou `Replace` dizem explicitamente o que se quer.

**Um Job sem `backoffLimit` nem `activeDeadlineSeconds`.** O valor padrão de novas tentativas é 6 e o tempo não tem teto: uma tarefa travada fica travada. Os dois são definidos nas tarefas de verdade, com números que se possam justificar (os Jobs de treino da lição, que duram segundos, nem todos os levam).

**Um CronJob sem histórico ou com um histórico enorme.** Sem histórico (`0`), não há evidência do que falhou. Com um número muito grande, acumulam-se Jobs e Pods aos milhares. Escolhe-se um número pequeno e revisa-se.

**Dar à tarefa uma conta de serviço com permissões “por via das dúvidas”.** A tarefa que só fala HTTP não precisa de credencial da API. `automountServiceAccountToken: false` e uma conta própria sem permissões.

**Colocar o token no comando ou em uma variável de ambiente da tarefa.** Ele é lido do arquivo montado no momento de rodar, como faz a tarefa da lição.

**Esquecer o fuso horário de um CronJob.** Sem `timeZone`, o horário é o do controlador (UTC no kind). “Todos os dias às 3” não é o que se imagina para quem está a seis horas de UTC.

**Guardar o relatório de todas as réplicas em um volume `ReadWriteOnce` local.** O Exercício 2 prova: prende todas as réplicas a um único nó.

## Exercícios

Os três primeiros rodam no cluster da lição, em ordem e a partir do estado em que ele ficou depois do “hábito de segurança”. Antes de cada um, a função `ctx` deve passar (`ctx && echo ok`). **Antes** de rodar cada um, escreva na [bitácora](bitacora.md) o que se acredita que vai acontecer. O quarto se escreve com palavras próprias.

### Exercício 1 — Uma classe de armazenamento que não existe

`fig08_08.pvc-clase-inexistente.yaml` cria uma solicitação de volume que pede a classe `rapido` (que este cluster não tem) e um Pod, `lector`, que a usa. Aplique-o. Antes de olhar, preveja: em que estado fica a solicitação? Em qual, o Pod? Que evento cada um deve dar, e quem o emite? Confira com `kubectl get pvc rapido -n revisor`, `kubectl get pod lector -n revisor` e os `describe` dos dois. E a pergunta difícil: quanto tempo se esperaria antes de concluir que não vai se resolver sozinho? Ao terminar, apague-o com `kubectl delete -f fig08_08.pvc-clase-inexistente.yaml`.

### Exercício 2 — O relatório do `revisor`, no volume

A decisão do curso é que o `revisor` guarde o seu `reporte.json` no `emptyDir` e que a tarefa guarde os dela no volume. Confira com uma mudança de uma linha. Com `kubectl patch`, substitua o volume `datos` do Deployment do `revisor` (o primeiro da lista, `/spec/template/spec/volumes/0`) por um que use a solicitação `reportes`:

```bash
ctx && kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
```

Preveja: as três réplicas iniciam? Em que nó cai cada uma? O que o `kubectl get pv` diz do volume? Peça um relatório com o `depurar` e procure o arquivo no nó. Depois, desfaça a mudança com `kubectl apply -k .` (o arquivo é a verdade) e confira onde ficam as réplicas. Explique em cinco frases por que isso não é o que se quer para o projeto, e o que se perde do que a Lição 9 vai pedir.

### Exercício 3 — Uma tarefa que demora mais que o seu horário

`fig08_09.cron-lento.yaml` é um CronJob que roda a cada minuto (`* * * * *`) com `concurrencyPolicy: Forbid`, e cuja tarefa demora **100 segundos** (`sleep 100`). Preveja, antes de aplicá-lo: aos 2 minutos e meio, quantos Jobs estarão rodando ao mesmo tempo? Os dos minutos intermediários serão criados? Que evento o CronJob deixa quando pula um? Aplique-o, olhe a cada 35 segundos durante uns 210 segundos (a primeira tarefa demora perto de dois minutos e é preciso ver como termina) com `kubectl get cronjob lento -n revisor` e `kubectl get jobs -n revisor` e leia `kubectl describe cronjob lento -n revisor`. Depois, apague o CronJob (`ctx && kubectl delete -f fig08_09.cron-lento.yaml`), espere o início de um minuto e crie-o de novo com a política trocada sem tocar no arquivo: `sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -`; repita com `Replace`. Assim o arquivo fica intacto para a execução do `correr.sh`. Compare: o que se vê com cada valor? Ao terminar, apague-o com `ctx && kubectl delete -f fig08_09.cron-lento.yaml`: se for deixado, continua criando um Job por minuto, e o `kubectl diff -k .` não o detecta porque não faz parte dos arquivos da lição.

### Exercício 4 — Dois horários

Em cinco frases no máximo, escreva a resposta a isto. (a) O horário cron de uma tarefa que roda **nos dias úteis às 7h30 da manhã, horário da Cidade do México**, e que campo da especificação do CronJob é necessário além do horário. (b) O horário de uma tarefa que roda **a cada duas horas em ponto**. (c) O que acontece com uma execução agendada para as 3h00 se o controlador de CronJobs ficou fora do ar das 2h50 às 3h20 e o CronJob tem `startingDeadlineSeconds: 600`; e o que muda se não tiver. (d) Por que a tarefa do relatório pode rodar duas vezes no mesmo minuto sem danificar nada.

## Soluções

### Solução 1

Medido em `correr.salida.txt`:

```text
$ kubectl apply -f fig08_08.pvc-clase-inexistente.yaml
persistentvolumeclaim/rapido created
pod/lector created

$ kubectl get pvc rapido -n revisor
NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
rapido   Pending                                      rapido         <unset>                 12s

$ kubectl get pod lector -n revisor
NAME     READY   STATUS    RESTARTS   AGE
lector   0/1     Pending   0          12s

$ kubectl describe pvc rapido -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason              Age               From                         Message
  ----     ------              ----              ----                         -------
  Warning  ProvisioningFailed  6s (x2 over 12s)  persistentvolume-controller  storageclass.storage.k8s.io "rapido" not found

$ kubectl describe pod lector -n revisor | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  13s   default-scheduler  0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims. not found
```

**Os dois estão `Pending`, mas por razões de dono distinto.** A solicitação está porque o `persistentvolume-controller` procura a classe `rapido`, não a encontra, e emite um `Warning` com a causa exata: `storageclass.storage.k8s.io "rapido" not found`. Ao contrário do `Pending` de 8.4, este é de nível `Warning` e não diz “esperando”: diz que algo não existe. O Pod está porque o agendador, que o vê com uma solicitação sem ligar, responde `0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims`: nenhum nó serve enquanto a solicitação não estiver ligada. (A mensagem termina com um `not found` solto, tal como o cluster da execução a imprimiu; o texto dos eventos muda entre versões, e o que se deve ler é a causa no evento da solicitação.)

A leitura é a de sempre: o Pod `Pending` não é o problema, é o sintoma. A causa está um objeto mais abaixo, na solicitação, e o evento dela diz que classe falta. A correção é escrever uma classe que exista (`kubectl get storageclass` dá a lista) ou criar a que falta. Sobre quanto esperar: nada disso se resolve sozinho. A solicitação sem classe fica `Pending` “indefinidamente”, como diz a documentação de volumes persistentes para uma solicitação sem volume que coincida, até que alguém crie a classe; não há tempo limite nem erro final. Um `Pending` com `ProvisioningFailed` não é uma espera, é um aviso.

### Solução 2

Medido em `correr.salida.txt`:

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
deployment.apps/revisor patched

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-6d9bd59b8b-5wnrq   1/1     Running   0          7s    10.244.2.24   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-sjjkr   1/1     Running   0          10s   10.244.2.23   curso-k8s-l8-worker   <none>           <none>
revisor-6d9bd59b8b-z7sc9   1/1     Running   0          12s   10.244.2.22   curso-k8s-l8-worker   <none>           <none>

$ kubectl get pv -o custom-columns=NOMBRE:.metadata.name,NODO:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]
NOMBRE                                     NODO
pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   curso-k8s-l8-worker

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40_revisor_reportes
total 146508
drwxrwxrwx 2     0     0      4096 Oct 21 23:28 .
drwxr-xr-x 3     0     0      4096 Oct 21 23:26 ..
-rw-r--r-- 1   100   101 150000000 Oct 21 23:27 grande.bin
-rw-r--r-- 1   100   101        92 Oct 21 23:26 reporte-20261021T232640Z.json
-rw------- 1 65532 65532        93 Oct 21 23:28 reporte.json

$ kubectl apply -k . | grep -E 'deployment|persistentvolumeclaim'
persistentvolumeclaim/reportes unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-6b7f4d564d-mgzwr   1/1     Running       0          2s    10.244.1.9    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-nxzdj   1/1     Running       0          7s    10.244.1.8    curso-k8s-l8-worker2   <none>           <none>
revisor-6b7f4d564d-tk4tr   1/1     Running       0          5s    10.244.2.25   curso-k8s-l8-worker    <none>           <none>
revisor-6d9bd59b8b-5wnrq   1/1     Terminating   0          15s   10.244.2.24   curso-k8s-l8-worker    <none>           <none>
```

**As três réplicas iniciam, e as três caem no mesmo nó**: `curso-k8s-l8-worker`, o que tem o volume. O agendador não pôde distribuí-las porque o PV tem uma afinidade de nó (8.5.2): qualquer Pod que use a solicitação deve rodar onde está o disco. E foram as três porque esse modo, `ReadWriteOnce`, é “um nó”, não “um Pod”: vários Pods no mesmo nó podem montar o volume ao mesmo tempo. A documentação diz isso, e aqui se viu. O `reporte.json` do `revisor` aparece na mesma pasta dos relatórios da tarefa, junto a `grande.bin` (os 150 MB de “o hábito de segurança”, ainda ali porque o volume é o mesmo) e o arquivo com data da tarefa 3.

Desfaz-se com `kubectl apply -k .`: as réplicas voltam ao `emptyDir` e se distribuem de novo pelos dois nós de trabalho (`worker` e `worker2`). O que ficaria ruim no projeto, em cinco frases: (1) todas as réplicas ficam em um único nó, porque o volume está em um único disco; (2) se esse nó cair, o `revisor` inteiro fica sem lugar onde rodar, porque os Pods não podem ir para outro nó com o seu volume; (3) as três réplicas escreveriam o **mesmo** `reporte.json`, sobrescrevendo-se entre si, o que é pior que antes; (4) a distribuição de réplicas por nós de que a Lição 9 precisa para escalar e para atualizar medindo cada interrupção desaparece; (5) o que o relatório precisa é de histórico com nome e data, e isso a tarefa já faz.

### Solução 3

Medido em `correr.salida.txt`. Primeiro `Forbid` (o script espera o início de um minuto do relógio antes de aplicar cada variante, para que a primeira tarefa caia no `:00` seguinte):

```text
$ kubectl apply -f fig08_09.cron-lento.yaml
cronjob.batch/lento created

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:30:45
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        45s             105s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Running    0/1           45s        45s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'
23:31:56
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        56s             2m56s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877090     Complete   1/1           103s       117s
lento-29877091     Running    0/1           14s        14s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age                From                Message
  ----    ------            ----               ----                -------
  Normal  SuccessfulCreate  2m32s              cronjob-controller  Created job lento-29877090
  Normal  SawCompletedJob   49s                cronjob-controller  Saw completed job: lento-29877090, condition: Complete
  Normal  SuccessfulCreate  49s                cronjob-controller  Created job lento-29877091
  Normal  JobAlreadyActive  32s (x4 over 92s)  cronjob-controller  Not starting job because prior execution is running and concurrency policy is Forbid
```

**Com `Forbid`, um único Job por vez, e os minutos intermediários não são criados.** O primeiro Job, `lento-29877090`, nasceu às `23:30:00` e levou 103 segundos (100 de `sleep` mais o que leva para iniciar e terminar). Enquanto rodava, chegaram os horários das `23:31:00` e nada foi criado: o CronJob deixou `ACTIVE 1` e seguiu com o mesmo. Quando o Job terminou, por volta das `23:31:43`, o CronJob o viu (`SawCompletedJob`) e criou **outro** de imediato, `lento-29877091`. Repare no nome do segundo: `…091` é o das `23:31:00`, não o das `23:32:00`. A razão está na documentação: quando a execução anterior termina, o `startingDeadlineSeconds` (que aqui não foi fixado e, portanto, não tem teto) ainda conta, e a execução das `23:31:00` que tinha sido pulada é enfim criada. (No `correr.salida.txt` há uma captura a mais, aos 35 segundos de aplicar, que ainda não tem nenhum Job: o CronJob foi criado às `23:29:00` e o seu primeiro horário foi o das `23:30:00`; por isso `lento-29877090` é do minuto seguinte.)

O evento que os horários pulados deixam é `JobAlreadyActive`, com a mensagem `Not starting job because prior execution is running and concurrency policy is Forbid` (“não se inicia o Job porque a execução anterior continua rodando e a política de concorrência é Forbid”), e o contador `x4 over 92s` diz quantas vezes aconteceu no tempo em que se olhou. A documentação acrescenta uma consequência: uma execução pulada por `Forbid` conta como perdida.

Agora a mesma tarefa com `Allow`, o valor padrão, e depois com `Replace`. Os dois são medições, não aritmética:

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Allow

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:35:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     2        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877094     Running    0/1           81s        81s
lento-29877095     Running    0/1           21s        21s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877094-mt8vs   1/1     Running   0          81s
lento-29877095-hqn7d   1/1     Running   0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877094
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877095
```

**Com `Allow`, dois Jobs rodam ao mesmo tempo.** O primeiro (`lento-29877094`) começou às `23:34:00`; às `23:35:00` chegou o segundo (`lento-29877095`) sem esperar que o primeiro terminasse, e a captura mostra `ACTIVE 2`, dois Jobs `Running` e dois Pods `Running` ao mesmo tempo, com 81 e 21 segundos de vida. Os eventos são só `SuccessfulCreate`, um por horário: não há `JobAlreadyActive`, porque nada é pulado. Como a tarefa dura 100 segundos e o horário é de 60, em regime sempre há entre um e dois ativos (isto último sai da aritmética; o que foi medido é a primeira sobreposição). Com uma tarefa que escreve em um volume compartilhado, esses dois Pods escreveriam ao mesmo tempo: por isso a seção 8.6 escolhe `Forbid` para o relatório.

```text
$ sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Replace/' fig08_09.cron-lento.yaml | kubectl apply -f -
cronjob.batch/lento created

$ kubectl get cronjob lento -n revisor -o jsonpath='{.spec.concurrencyPolicy}{"\n"}'
Replace

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:37:46
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        46s             106s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877097     Running    0/1           46s        46s
NAME                   READY   STATUS    RESTARTS   AGE
lento-29877097-n8cpx   1/1     Running   0          46s

$ date -u +%T; kubectl get cronjob lento -n revisor; kubectl get jobs -n revisor | grep -E 'NAME|lento'; kubectl get pods -n revisor -l app=lento
23:38:21
NAME    SCHEDULE    TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
lento   * * * * *   <none>     False     1        21s             2m21s
NAME               STATUS     COMPLETIONS   DURATION   AGE
lento-29877098     Running    0/1           21s        21s
NAME                   READY   STATUS        RESTARTS   AGE
lento-29877097-n8cpx   1/1     Terminating   0          81s
lento-29877098-g6cvv   1/1     Running       0          21s

$ kubectl describe cronjob lento -n revisor | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                Message
  ----    ------            ----  ----                -------
  Normal  SuccessfulCreate  81s   cronjob-controller  Created job lento-29877097
  Normal  SuccessfulDelete  21s   cronjob-controller  Deleted job lento-29877097
  Normal  SuccessfulCreate  21s   cronjob-controller  Created job lento-29877098
```

**Com `Replace`, o Job em andamento é apagado e outro é iniciado, e nenhum chega a terminar.** O primeiro (`lento-29877097`) começou às `23:37:00`; às `23:38:00` o CronJob o **apagou** (`SuccessfulDelete`) e criou `lento-29877098` no lugar dele. Na última captura o Pod velho está `Terminating` e o novo `Running` com 21 segundos. O primeiro Job viveu 60 segundos, menos dos 100 de que precisa, e não chegou a terminar. Isso foi medido uma vez (a primeira substituição); que as seguintes repitam o mesmo sai de que o horário continua sendo de 60 segundos e a tarefa de 100. `Replace` é o valor para tarefas cujo último resultado é o único que importa e que podem ser reiniciadas sem dano, e o incorreto para uma que precisa dos seus 100 segundos completos.

As três políticas são uma resposta a “o que acontece quando a tarefa é mais lenta que o seu horário”, e a resposta correta é a que descreve o que a tarefa precisa, não o valor padrão.

### Solução 4

Uma resposta possível: “(a) `30 7 * * 1-5`, que é minuto 30, hora 7, qualquer dia do mês, qualquer mês, de segunda (1) a sexta (5); e além disso `timeZone: "America/Mexico_City"` na especificação, porque sem ele o horário é interpretado no fuso do controlador, UTC no kind, e a tarefa rodaria à 1h30 da madrugada. (b) `0 */2 * * *`: minuto 0 de cada segunda hora. (c) Com `startingDeadlineSeconds: 600`, às 3h20 o CronJob vê que a execução das 3h00 se atrasou 1200 segundos, mais que o prazo de 600, e a pula, porque já é tarde demais para ela; com o campo sem fixar, não há prazo e ele a cria assim que o controlador volta, às 3h20, com 20 minutos de atraso, a menos que se tenham acumulado mais de 100 execuções perdidas, caso em que se recusa a começar. (d) Porque é segura diante de repetições: o nome do arquivo leva a data com segundos e cada execução escreve um arquivo distinto, de modo que duas execuções deixam dois arquivos e nada se corrompe nem se perde (não é idempotente em sentido estrito: o resultado não é o mesmo que com uma só).”

## Apagar o cluster

Antes de apagar, o estado final. Primeiro retira-se o Pod `depurar`, que não faz parte dos arquivos da lição (`ctx && kubectl delete pod depurar -n revisor --wait=false`); por isso, na saída abaixo, aparece `Terminating` na lista de Pods. Se a cadeia da lição foi seguida em ordem e os experimentos foram desfeitos, o cluster deve ser exatamente o que os arquivos dizem. É o `kubectl diff` da Lição 5, agora ao contrário: sem diferenças, sai com 0.

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get pvc,cronjob -n revisor
NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Bound    pvc-54c37c25-a11a-4a37-b2da-ae67d36aea40   100Mi      RWO            standard       <unset>                 12m

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        3m53s           14m

$ kubectl get jobs -n revisor
NAME               STATUS     COMPLETIONS   DURATION   AGE
reporte-29877090   Complete   1/1           4s         8m53s
reporte-29877095   Complete   1/1           4s         3m53s
reporte-manual-3   Complete   1/1           8s         12m

$ kubectl get pods -n revisor
NAME                       READY   STATUS        RESTARTS   AGE
depurar                    1/1     Terminating   0          14m
prueba-6899c74865-9dckl    1/1     Running       0          15m
reporte-29877090-8ms5h     0/1     Completed     0          8m53s
reporte-29877095-wbx85     0/1     Completed     0          3m53s
reporte-manual-3-2657n     0/1     Completed     0          12m
revisor-6b7f4d564d-mgzwr   1/1     Running       0          10m
revisor-6b7f4d564d-nxzdj   1/1     Running       0          10m
revisor-6b7f4d564d-tk4tr   1/1     Running       0          10m

$ curl -s -m 5 http://172.28.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

A solicitação `reportes` está ligada, o `CronJob` `reporte` está agendado e já rodou sozinho (os Jobs `reporte-29877090` e `reporte-29877095`, das `23:30` e das `23:35`, foram criados por ele), e o ponto de entrada do Gateway continua respondendo de fora. Esse é o estado com que a Lição 9 começa. (O único Pod `Terminating` é o `depurar`, que foi apagado logo antes desta conferência; os Pods `lento-…` do Exercício 3 já não estão porque o script esperou que desaparecessem antes de medir.)

Quando terminar, apague o cluster da lição. Não deixe nada vivo na máquina:

```text
$ kind delete cluster --name curso-k8s-l8
Deleting cluster "curso-k8s-l8" ...
Deleted nodes: ["curso-k8s-l8-worker2" "curso-k8s-l8-control-plane" "curso-k8s-l8-worker"]
(borrar tardó 4 s)

$ kind get clusters | grep -c curso-k8s-l8
0
```

(A linha entre parênteses é escrita pelo script, que mede o apagamento.) O `--name` é obrigatório: sem ele, o kind apagaria o cluster chamado `kind`, que pode ser de outra pessoa ou de outro projeto. Com o cluster vai embora a pasta `/mnt/disco-reportes` do nó e os volumes que restarem: tudo vivia dentro dos contêineres dos nós.

Ficam na máquina a pasta temporária do `kubeconfig` e os dois `token.txt`. Apagam-se assim, a partir de `programas/08-datos-y-tareas`:

```bash
# Los dos tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 8.1.1.
case "$L8_TMP" in
  /tmp/curso-k8s-l8.?*) rm -rf -- "$L8_TMP" ;;
  *) echo "No borro «$L8_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L8_TMP
unset -f ctx
```

O `case` só deixa passar um caminho que comece com `/tmp/curso-k8s-l8.` e tenha algo depois, a forma exata da que foi criada em 8.1.1. Se `L8_TMP` estiver vazia (por exemplo, porque se está em outro terminal, onde nunca foi definida) ou valer outra coisa, não apaga nada e diz por quê. É a mesma proteção que o `correr.sh` usa ao limpar: um `rm -rf` que pode ser copiado e colado tem que se proteger sozinho. Se o `correr.sh` usou a rede própria das notas da execução, essa rede (`docker network rm curso-k8s-red-l8`) também é apagada por quem acompanha, e só ela.

## Como sei que consegui

- [ ] Explicar, com a medição de 8.2, o que sobrevive à queda de um contêiner e o que não sobrevive ao apagamento de um Pod, e por quê.
- [ ] Distinguir `PersistentVolume`, `PersistentVolumeClaim` e `StorageClass`, e dizer quem cria cada um.
- [ ] Ler `Pending` em uma solicitação com `WaitForFirstConsumer` e saber que não é um erro, e ler `ProvisioningFailed` com uma classe inexistente e saber que sim é.
- [ ] Escrever um `Job` com `backoffLimit` e `activeDeadlineSeconds` e dizer quantos Pods no máximo ele cria e com que esperas.
- [ ] Ler um horário cron de cinco campos e escrever o de “a cada cinco minutos” e o de “segunda a sexta às 7h30”.
- [ ] Dizer o que faz `Forbid` diante de `Allow` e `Replace`, e por que a tarefa do relatório deve poder rodar duas vezes.
- [ ] Provocar e consertar um `Permission denied` em um volume com `fsGroup`, e dizer em que volume da lição o `fsGroup` mudou o grupo e em qual não.
- [ ] Dizer o que se perde ao apagar uma solicitação com política `Delete` e o que com `Retain`, e por que um apagamento fica em `Terminating`.
- [ ] Rodar `programas/08-datos-y-tareas/correr.sh > /tmp/mi-corrida-l8.txt 2>&1` e comparar `/tmp/mi-corrida-l8.txt` com `programas/08-datos-y-tareas/correr.salida.txt` (sem redirecionar para esse arquivo: ele é a referência) no que não muda entre execuções: três nós `Ready` em `v1.37.0`; seis linhas `not yet present on node … loading...`; `-rw-------` nos dois `token.txt`; no `emptyDir`, o diretório `2777` com grupo `65532` e um único `reporte.json` de uns 92 bytes em uma das três réplicas (93 se o tempo medido tiver dois dígitos); `RESTARTS 1` e `Error 137` depois de parar o contêiner, com o arquivo intacto; a pasta do volume que já não existe depois de apagar o Pod; a classe `standard (default)` com `rancher.io/local-path`, `Delete` e `WaitForFirstConsumer`; `No resources found` no `kubectl get pv`; a solicitação `Pending` com o evento `waiting for first consumer to be created before binding`; o Job `salud` com `Complete` e `{"estado":"vivo","version":"1.6.0"}`; o Pod da tarefa `Pending` com um nó nomeado e o evento `Provisioning` (`ProvisioningSucceeded` chega um instante depois e pode ou não cair na captura); a solicitação `Bound`, `100Mi`, `RWO`, `standard`; o volume preso a um nó, com o caminho `/var/local-path-provisioner/pvc-…_revisor_reportes` e permissão `777 0:0`; um arquivo `reporte-…Z.json` na primeira tarefa e dois na segunda; Jobs de CronJob com nome `<cronjob>-<número>` de oito dígitos e a anotação `cronjob-scheduled-timestamp` em `:00`; `Permission denied` e `755 0:0` sem `fsGroup`, `Completed` e `2775 0:101` com ele; `Released` com `Retain`; `Terminating` com o finalizador `kubernetes.io/pvc-protection` até apagar os Jobs; `BackoffLimitExceeded` com três Pods em `Error`, código `28`; `150000000` bytes escritos em um volume de `100Mi`; `ProvisioningFailed … "rapido" not found`; as três réplicas do `revisor` em um único nó; `JobAlreadyActive … concurrency policy is Forbid`; e `sin diferencias con los archivos`. Os IPs, os sufixos dos nomes, os `uid`, as idades, o nó que recebe o volume, os segundos exatos, o identificador de cada `pvc-…` e a hora dos arquivos mudam a cada execução: observam-se, não se comparam.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l8`.

## Resumo

Responda sem olhar a lição:

1. O que sobrevive à queda de um contêiner e o que não sobrevive ao apagamento de um Pod, em um `emptyDir`?
2. Que papel tem cada um destes três objetos: `PersistentVolume`, `PersistentVolumeClaim`, `StorageClass`?
3. Por que a solicitação `reportes` fica em `Pending` ao ser aplicada, e quando deixa de ficar?
4. O que significa `ReadWriteOnce`, e que consequência tem sobre onde podem rodar os Pods que usam o volume?
5. Em que um `Job` se parece com um Deployment e em que se diferencia?
6. Quantos Pods no máximo cria um Job com `backoffLimit: 2`, e com que esperas entre eles?
7. O que dizem os cinco campos de `*/5 * * * *`? Em que fuso horário rodam se `timeZone` não for definido?
8. O que faz `concurrencyPolicy: Forbid` e que evento deixa?
9. O que quer dizer que uma tarefa seja idempotente, e por que importa em um CronJob?
10. O que faz o `fsGroup`, em que volume da lição mudou algo e em qual não?
11. Por que uma solicitação pode ficar `Terminating`? Como se resolve sem forçar nada?
12. Que diferença há entre `Delete` e `Retain`?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Persistent Volumes”](https://kubernetes.io/docs/concepts/storage/persistent-volumes/): as definições de `PersistentVolume` e `PersistentVolumeClaim`; o provisionamento estático e o dinâmico; a ligação de um para um e que uma solicitação sem volume que coincida espera indefinidamente; a proteção de objetos de armazenamento em uso e a sua definição de “em uso”; as políticas de reclamação `Retain` e `Delete`; as fases `Bound` e `Released`; os modos de acesso e a definição de `ReadWriteOnce` (um nó, vários Pods).
- [Kubernetes, “Storage Classes”](https://kubernetes.io/docs/concepts/storage/storage-classes/): o que é uma classe; a classe padrão; a política de reclamação padrão (`Delete`); o modo de ligação `Immediate` diante de `WaitForFirstConsumer`.
- [Kubernetes, “Volumes”](https://kubernetes.io/docs/concepts/storage/volumes/): `emptyDir` (é criado ao atribuir o Pod a um nó, é apagado ao remover o Pod, sobrevive à queda de um contêiner, a permissão `0777` padrão) e o volume `local` (só estático, `nodeAffinity` obrigatória).
- [Kubernetes, “Jobs”](https://kubernetes.io/docs/concepts/workloads/controllers/job/): a definição de Job; `restartPolicy` `Never` ou `OnFailure`; `backoffLimit` (6 por padrão) e a espera exponencial; `activeDeadlineSeconds` e a sua precedência; as causas de falha (`BackoffLimitExceeded`, `DeadlineExceeded`); as condições terminais adiadas desde a 1.31; que o mesmo programa pode iniciar duas vezes.
- [Kubernetes, “CronJob”](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/): o formato cron de cinco campos; o fuso horário e `.spec.timeZone`; `concurrencyPolicy`; os limites de histórico (3 e 1 por padrão); `startingDeadlineSeconds` e o teto de 100 execuções perdidas; `suspend`; o nome de no máximo 52 caracteres; a anotação `cronjob-scheduled-timestamp` desde a 1.32; o aviso de que os Jobs devem ser idempotentes.
- [Kubernetes, “Configure a Security Context for a Pod or Container”](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` e o grupo do volume; os volumes “que suportam gerenciamento de donos”; `fsGroupChangePolicy`.
- [Kubernetes v1.37, registro de mudanças](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.37.md): a condição `Unused` das solicitações de volume (`PersistentVolumeClaimUnusedSinceTime`, beta e ativada desde a 1.37).
- [Local Path Provisioner (Rancher), README](https://github.com/rancher/local-path-provisioner): o provisionador que a classe `standard` do kind usa; o volume como pasta `hostPath` do nó; que a capacidade é ignorada; a permissão `0777` da pasta; o apagamento do conteúdo ao apagar o volume.
- [kind, “Configuration”](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts): as montagens extras (`extraMounts`), a forma de passar armazenamento da máquina a um nó do kind para que os dados persistam além do contêiner do nó.
- [Kubernetes, “StatefulSets”](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/): identidade de rede estável e armazenamento estável por Pod (`volumeClaimTemplates`).
- [Kubernetes, “Volume Snapshots”](https://kubernetes.io/docs/concepts/storage/volume-snapshots/): os snapshots de volume.
- [Kubernetes, “Resource Quotas”](https://kubernetes.io/docs/concepts/policy/resource-quotas/): `requests.storage`, a soma máxima de armazenamento que as solicitações de um namespace podem pedir.
- [GitLab, “Postmortem of database outage of January 31”](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): o relato público, de fevereiro de 2017, de uma perda de dados de produção e dos mecanismos de backup que não estavam funcionando (uma cópia diária que falhava em silêncio, snapshots não ativados nos servidores do banco, uma réplica quebrada): a razão para testar os backups em vez de supô-los.

---

**Próxima:** [Lição 9 — Escalar e atualizar, medindo cada interrupção](09-escalar-y-actualizar.md)
