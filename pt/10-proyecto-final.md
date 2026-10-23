# Lição 10 — O projeto terminado e o que muda em um cluster real

Segunda-feira, 7h50 da manhã. Às 9h tem reunião com a diretoria e o `revisor` é a demonstração. Abre-se o notebook e o cluster não está mais lá: no fim de semana, alguém atualizou o Docker, outra pessoa limpou imagens e contêineres “que não se usavam mais”, e `kind get clusters` responde com uma lista vazia. Os manifestos estão no Git, e há a página da wiki escrita um mês atrás: “Para subir, `kubectl apply -k .`”. A gente tenta. O primeiro comando diz `no matches for kind "IPAddressPool"`. Repete, e agora diz `failed calling webhook`. Repete uma terceira vez e quase tudo é criado, mas o Gateway fica sem endereço, e não se sabe se é porque falta algo ou porque o tempo ainda não passou. Às 8h35 há um cluster que *quase* funciona, uma wiki que não diz a ordem porque, quando foi escrita, a ordem “saiu sozinha”, e a suspeita incômoda de que, se perguntarem “dá para subir de novo?”, a resposta honesta é “acho que sim, se eu repetir várias vezes”.

Essa resposta não é uma resposta. Um projeto está terminado quando qualquer pessoa —a gente mesma daqui a seis meses, uma colega nova, uma etapa automática de um *pipeline*— consegue partir de um cluster vazio, rodar uma receita curta e chegar ao mesmo lugar, sem corrigir nada manualmente e sabendo o que esperar entre um passo e outro. Esta é a última lição do curso e faz duas coisas. A primeira: reúne tudo o que se construiu nas nove anteriores em uma estrutura que sobe com **dois comandos e uma espera**, com **Kustomize** (uma base e camadas por cima dela), e a automatiza com um script que **não esconde a ordem**. A segunda é menos confortável e por isso a mais importante: diz, sem rodeios, **o que falta a tudo isto para ser algo além de um laboratório**.

**Tempo:** 2 × 45 min

**O que se constrói:** o `revisor` completo —as nove lições juntas— organizado em uma base e duas camadas de Kustomize (a plataforma e o projeto), que sobe a partir de um cluster vazio com dois `kubectl apply` e uma espera, e que um script repete, apaga e repete de novo sem que nada seja corrigido manualmente; além disso, uma lista escrita do que falta para rodar de verdade

**O que se aprende:** o que é uma base e o que é um *overlay* no Kustomize, e como se lê o que eles montam; por que a plataforma (tipos novos, controladores e *webhooks*) vem antes do projeto, e o que o cluster diz quando essa ordem é quebrada; o que é `kubectl apply --server-side` e que erro ele evita; como esperar sem `sleep` (com `kubectl wait`) e como automatizar a subida sem esconder a ordem; a revisão final do projeto contra o nível `restricted`, campo por campo; as provas das metas do curso (um nó que cai, uma configuração que muda, um Pod alheio, um escalonamento que lê métricas); o que é o Helm e quando ele vale mais que o Kustomize; e o que muda, e o que se perde, entre um cluster de `kind` e um real

**De onde a gente vem.** Das nove lições anteriores, que agora se leem como camadas de um mesmo edifício. Da [Lição 2](02-pods-deployments.md): o Deployment, o `securityContext` e as imagens carregadas com `kind load`. Da [Lição 3](03-services-dns.md): os Services e o Pod `depurar`. Da [Lição 4](04-configuracion-secretos.md): o Kustomize com geradores e o *hash* que dispara o *rollout*. Da [Lição 5](05-salud-recursos-apagado.md): os *probes*, os `requests` e os `limits`. Da [Lição 6](06-entrar-al-cluster.md): o MetalLB e o Envoy Gateway, e a ideia de que a plataforma vem antes do projeto; esta lição transforma essa ideia na estrutura de pastas. Da [Lição 7](07-aislar-permisos-red.md): o namespace `revisor` em nível `restricted`, as contas com permissões mínimas e a rede fechada. Da [Lição 8](08-datos-y-tareas.md): o volume e o `CronJob` do relatório. Da [Lição 9](09-escalar-y-actualizar.md): o `metrics-server`, o escalonamento automático e o desligamento com `preStop`. Se alguma das nove ficou pela metade, a tabela da seção 10.2 diz em que arquivo vive cada peça.

**O que esta lição não faz.** Não ensina nada novo sobre o `revisor`: tudo o que ele leva já foi construído. Não instala o Helm nem o roda: apenas o nomeia, compara com o Kustomize e diz quando seria preciso usá-lo. Não converte o cluster em um de produção: isso é exatamente o que **não** se faz, e a seção 10.10 explica por que, em cada caso. E não repete as medições longas das lições 6 e 9 (quanto o escalonamento demora para subir e descer, como o MetalLB se comporta de perto): usa-as e remete a essas lições para o detalhe.

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com `kind` v0.33.0, `kubectl` v1.37.1 (`kubectl version --client` diz `Kustomize Version: v5.8.1`), a imagem de nó `kindest/node:v1.37.0` fixada pelo seu *digest*, **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** (com Gateway API v1.6.1) e **metrics-server v0.9.0**, no cluster de três nós da Lição 1, aqui chamado de `curso-k8s-l10`. A máquina foi um Mac com processador ARM e Docker Engine 29.2.1 dentro de uma máquina virtual Linux (Colima), **não** Linux Mint, que é o sistema de referência do curso. O que muda no Mint: a arquitetura (`amd64` em vez de `arm64`); os IPs dos Pods, dos Services e dos nós; os sufixos aleatórios dos nomes, as idades e em que nó cai cada réplica; e, sobretudo, os tempos, que dependem da conexão (os nós baixam da internet as imagens da plataforma) e da carga da máquina. **Uma diferença de rede importa:** esta execução usou uma **rede Docker própria**, `curso-k8s-red-l10` (`172.30.0.0/16`), criada com `docker network create --subnet 172.30.0.0/16 curso-k8s-red-l10` antes do primeiro cluster e apagada depois do último, e cada cluster foi criado com a variável `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l10`. Fez-se assim porque a máquina era compartilhada e outras lições também instalavam o MetalLB: dois clusters com a mesma faixa na mesma rede se atropelam. O `kind` avisa isso na saída da criação com `WARNING: Overriding docker network…` e `Here be dragons! This is not supported currently` (a variável é experimental). Na máquina de quem acompanha, com a rede `kind` normal (`172.18.0.0/16` no Mint), nada disso é necessário, e os endereços do ponto de entrada saem em `172.18.255.x`: troque a faixa de `overlays/kind/metallb-pool.yaml` por `172.18.255.200-172.18.255.250` (as seções 10.1.1 e 10.6.2 explicam por quê) e, onde as saídas dizem `172.30.255.200`, leia `172.18.255.200`. Os clientes “de fora” das saídas se conectaram à rede própria; na máquina de quem acompanha, ao `kind`. O percurso completo está em [`programas/10-proyecto-final/`](../programas/10-proyecto-final): `correr.sh` cria um cluster, provoca os dois erros da seção 10.4 (cada um em um cluster novo), cria outro e percorre as seções 10.1 a 10.8 e os Exercícios 1 a 3, apaga-o, e termina com `probar-levantar.sh` (mais dois clusters). No total, cinco clusters, um de cada vez, e os cinco foram apagados. A saída está em `correr.salida.txt` (as três execuções anteriores citadas na seção 10.8.3 e no Exercício 3 estão em `corridas-preparacion/`; `psa-comprobacion.sh` e `crd-tamanos.sh`, com seus `.salida.txt`, são duas medições avulsas citadas nas seções 10.7.3 e 10.4.3); ali aparecem algumas linhas “espera de cupo”, que são do script esperando que outra lição liberasse uma vaga na máquina compartilhada. A execução completa levou 1.755 segundos (quase meia hora), dos quais uns 6 minutos foram essas esperas. Criar um cluster, esperar os nós e carregar as imagens levou entre 35 e 60 segundos; a espera da plataforma, 153 segundos no cluster da seção 10.5, e em `probar-levantar.sh` o passo 2 terminou aos 234 e 250 segundos de iniciado o script (a espera em si, uns 229 e 246); em uma das execuções de preparação, essa mesma espera chegou a 881 segundos (está em `programas/10-proyecto-final/corridas-preparacion/corrida4.txt`). Precisa de internet.

## Ao terminar, a gente vai conseguir

- Explicar com as próprias palavras o que é uma **base** e o que é um ***overlay*** no Kustomize, abrir um `kustomization.yaml` e dizer que recursos ele monta, o que muda neles e como conferir isso com `kubectl kustomize` sem tocar no cluster.
- Distinguir uma peça de **plataforma** (tipos novos, controladores, *webhooks*) de uma de **projeto**, e subir as duas a partir de um cluster vazio com dois `kubectl apply --server-side -k` e uma espera com `kubectl wait`, na ordem correta.
- Reconhecer e interpretar os dois erros de quebrar essa ordem: o que sai de aplicar a plataforma sem `--server-side` e o que sai de juntar plataforma e projeto em um único comando.
- Escrever um script de subida que não esconda a ordem —três passos com nome, uma verificação de contexto antes de cada um e esperas por condição, não por tempo— e testá-lo criando, apagando e recriando o cluster.
- Revisar o projeto contra o nível `restricted` dos *Pod Security Standards*, campo por campo e com o cluster, e explicar por que a plataforma vive em namespaces que não o cumprem.
- Medir o que acontece quando um nó de trabalho é parado (o que falha, por quanto tempo e por quê) e dizer o que reduz essa janela e o que não reduz.
- Escrever, com as próprias palavras, cinco motivos pelos quais o que se construiu não é um cluster real e o que se faria com cada um.

## O porquê antes do como

Até agora cada lição deixou o cluster *um pouco mais longe* de onde começou: mais arquivos, mais peças, mais coisas a aplicar. Esse acúmulo é normal enquanto se aprende, e tem um custo que não se vê até a segunda-feira da cena: ninguém escreveu **em um só lugar** como tudo se sobe. As lições dizem, cada uma à sua maneira; mas um projeto que só se reconstrói relendo nove lições não está terminado.

Há um caso real que mostra por que isso importa, e não é de Kubernetes. Em 31 de janeiro de 2017, um engenheiro do GitLab apagou por engano o diretório de dados do banco de dados principal do GitLab.com: uns 300 GB, segundo o relatório público que a empresa publicou em 10 de fevereiro. O que faz dessa história uma lição para a gente é o que veio depois. A empresa tinha vários mecanismos de backup e recuperação no papel, e quando foram procurá-los, o relatório diz (traduzido): “o processo de encontrar e usar os backups falhou por completo”. O backup diário com `pg_dump` não existia: a pasta de armazenamento estava vazia, porque o programa que o fazia era de uma versão diferente da do banco e terminava com erro, e os e-mails que avisavam desse erro eram rejeitados pelo servidor de destino, de modo que ninguém soube até ser tarde. A recuperação foi feita com uma cópia tirada seis horas antes por outro motivo, e copiá-la do ambiente de testes levou umas 18 horas. Perderam-se as mudanças feitas entre 17h20 e perto da meia-noite (UTC; o relatório dá 23h30 no detalhe e 0h no resumo) daquele dia: segundo a estimativa deles, cerca de 5.000 projetos, 5.000 comentários e 700 contas novas.

Não aconteceu por falta de receitas. Aconteceu porque **ninguém tinha percebido que elas não funcionavam**: o backup falhava e nada avisava. Uma receita de recuperação que ninguém rodou de ponta a ponta é uma hipótese, igual a “acho que sim, se eu repetir várias vezes”. Por isso esta lição não se limita a escrever a receita: ela a **executa**, quebra de propósito, apaga e repete em um cluster novo, e ensina a fazer o mesmo.

A lição tem dez partes de conceitos e depois as seções de sempre:

1. **O cluster da lição** (10.1): criá-lo com seu `kubeconfig` próprio e sua trava de contexto.
2. **O mapa da pasta** (10.2): o que há em `programas/10-proyecto-final/` e que lição pôs cada peça.
3. **Kustomize: base e *overlays*** (10.3): como se monta, como se lê e como se confere.
4. **Por que dois comandos e uma espera** (10.4): os dois erros que ensinam a ordem.
5. **Subir manualmente** (10.5): plataforma, espera, projeto, e vê-lo funcionar de fora.
6. **Automatizar sem esconder a ordem** (10.6): `levantar.sh` e a prova de criar, apagar e recriar.
7. **A revisão final contra `restricted`** (10.7).
8. **Provar as metas** (10.8): o nó que cai, a configuração que muda, o Pod alheio, o escalonamento.
9. **Helm, em uma menção** (10.9).
10. **O que muda em um cluster real** (10.10): a lista do que falta.

Este é o destino. No final da seção 10.5, um cluster vazio tem o projeto completo, e o ponto de entrada construído na Lição 6 recebe um endereço que o MetalLB distribuiu:

```text
$ kubectl get all,pvc,cronjob,hpa,pdb,networkpolicy,gateway,httproute -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rzh88    1/1     Running   0          82s
pod/revisor-654b5d75dc-6m6s6   1/1     Running   0          82s
pod/revisor-654b5d75dc-dq4pp   1/1     Running   0          82s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.57.22     <none>        9000/TCP   82s
service/revisor   ClusterIP   10.96.239.233   <none>        80/TCP     82s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           82s
deployment.apps/revisor   2/2     2            2           82s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       82s
replicaset.apps/revisor-654b5d75dc   2         2         2       82s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          82s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          82s

NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 82s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     82s

NAME                                                    POD-SELECTOR               AGE
networkpolicy.networking.k8s.io/acceso-revisor-salida   acceso-revisor=permitido   82s
networkpolicy.networking.k8s.io/cerrado                 <none>                     82s
networkpolicy.networking.k8s.io/dns                     <none>                     82s
networkpolicy.networking.k8s.io/prueba-entrada          app=prueba                 82s
networkpolicy.networking.k8s.io/revisor-entrada         app=revisor                82s
networkpolicy.networking.k8s.io/revisor-salida          app=revisor                82s

NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.30.255.200   True         82s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               82s
```

(Essa tabela é longa de propósito: é a prova de que as nove lições estão ali. A gente vai lê-la linha por linha na seção 10.5.)

## Se as imagens do curso de Docker não estiverem à mão

Esta lição usa as mesmas duas imagens das Lições 3 a 9: `curso-docker-revisor:1.6.0`, a do `revisor`, e `curso-docker-prueba:1.0.0`, a do serviço que falha de propósito. Confira se elas existem:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Para a outra, o mesmo comando com `curso-docker-prueba:1.0.0`. Se alguma faltar, a [Lição 3](03-services-dns.md) diz como construí-las a partir do repositório do curso de Docker. Esta lição não pede nada novo a nenhuma das duas. O novo vem da internet: os manifestos do MetalLB, do Envoy Gateway e do `metrics-server` são baixados dos respectivos lançamentos toda vez que a plataforma é aplicada, e as imagens desses três componentes e a do `curl` são baixadas por cada nó na primeira vez. É preciso ter conexão.

## Os conceitos

### 10.1 O cluster da lição

#### 10.1.1 Antes de criar: a cota, a rede e o disco


Esta lição instala o **MetalLB**, como a Lição 6, e traz junto a sua regra de convivência: o MetalLB distribui endereços IP da rede Docker onde vivem os nós do `kind`, e dois clusters com MetalLB e a mesma faixa, na mesma rede, anunciam os mesmos endereços e se atropelam. Quem trabalha sozinho na própria máquina não tem esse problema: terá um cluster de cada vez. Quem divide a máquina com alguém, ou tem outro cluster do curso vivo, confere antes de criar:

```bash
# ¿Hay otro clúster del curso vivo? Si lo hay y tiene MetalLB, espera a que termine.
kind get clusters
# Espacio de tu disco: si el uso pasa de 80 %, libera lo tuyo antes de seguir.
df -h /
# Cuánto ocupa Docker (imágenes, contenedores, volúmenes), para saber qué liberar.
docker system df
```

`kind get clusters` lista os clusters que o `kind` conhece na máquina. Se aparecer `curso-k8s-l10` e não foi criado por quem está acompanhando, pare: é de outra pessoa. `df -h /` diz que porcentagem do disco está usada (a coluna `Use%`); `docker system df` não dá porcentagens: resume quanto ocupam as imagens, os contêineres e os volumes do Docker, e serve para saber o que liberar. Esta lição cria vários clusters, um de cada vez, e cada um baixa as imagens da plataforma: não há um número de espaço medido, então deixe folga.

E uma nota sobre **a rede** que decide a faixa de endereços, porque ela aparece em um arquivo desta lição. Por padrão, o `kind` cria uma rede Docker chamada `kind` e coloca ali todos os nós. No Linux Mint, essa rede costuma ser `172.18.0.0/16`. Confira:

```bash
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

O arquivo `overlays/kind/metallb-pool.yaml` que a pasta traz diz `172.30.255.200-172.30.255.250`, a faixa da rede própria com a qual as execuções desta lição foram feitas (a seção “Sobre as execuções” explica). Por isso, **mesmo que a rede seja `172.18.0.0/16`, é preciso trocar essa faixa**: para `172.18.255.200-172.18.255.250` se a rede for a de sempre, ou com o prefixo da rede em uso se for outra `/16`. É **uma linha** de um arquivo, e a seção 10.6 ensina um script que confere se a faixa cai dentro da rede antes de aplicar qualquer coisa (se não for trocada, ele para com um `ALTO` e avisa).

#### 10.1.2 Criar o cluster

Crie-o a partir de `programas/10-proyecto-final/`, com o mesmo cuidado de sempre: um `kubeconfig` temporário próprio, uma função que confere o contexto antes de cada mudança e as imagens carregadas.

```bash
cd programas/10-proyecto-final
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L10_TMP="$(mktemp -d /tmp/curso-k8s-l10.XXXX)"
export KUBECONFIG="$L10_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: una segunda terminal la necesita
# curso-k8s-l10 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
# La guarda: devuelve error si el contexto activo no es el de esta lección.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l10 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
kind create cluster --name curso-k8s-l10 --config kind-curso.yaml
ctx && kubectl get nodes
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l10 > "$L10_TMP/cargar.log" 2>&1
```

Duas coisas que não são novas mas que esta lição usa mais que todas. A primeira: `ctx` é uma **função do terminal**, não um programa. Se `kubectl config current-context` não disser `kind-curso-k8s-l10`, ela imprime “contexto equivocado: no sigo” e devolve um erro; o `&&` faz com que o comando da direita **não rode** quando a função falha. Por isso, daqui em diante, todo comando que **muda** algo se escreve `ctx && kubectl apply …`. Um comando que só lê (`get`, `describe`) não precisa dela, mas também não atrapalha. A segunda: o `export` só vale naquele terminal. Se abrir outro, repita o `export KUBECONFIG=…` com o caminho que o `echo` imprimiu e defina `ctx` de novo.

E esta lição tem algo que as anteriores não tinham: **um token falso que o Secret gerado vai ler** (Lição 4). Ele é criado uma vez, com permissões só para quem o cria, e não é versionado (o `.gitignore` da pasta o exclui):

```bash
(umask 077; openssl rand -hex 16 > base/token.txt)
TOKEN="$(cat base/token.txt)"
```

Os parênteses fazem com que o `umask 077` valha só para aquele comando, e o arquivo nasce com permissão `0600` (`-rw-------`): legível apenas por quem o criou. Conferimos:

```text
$ /bin/ls -l base/token.txt | cut -d' ' -f1
-rw-------

$ wc -c < base/token.txt
      33
```

Os 33 bytes são os trinta e dois caracteres hexadecimais de `openssl rand -hex 16` mais a quebra de linha. E o estado do cluster recém-criado, com seus três nós e as duas imagens já dentro:

```text
$ kubectl config current-context
kind-curso-k8s-l10

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE   VERSION
curso-k8s-l10-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l10-worker          Ready    <none>          18s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          17s   v1.37.0

$ cat $L10_TMP/cargar.log
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l10-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l10-worker", loading...
```

Seis linhas `not yet present on node … loading...`: duas imagens por três nós, incluindo o de controle. Mas “loading” não prova que a imagem chegou. Uma verificação que vale virar hábito é perguntar a cada nó que imagens ele tem, com `crictl`, a ferramenta do *runtime* de contêineres que já foi usada na Lição 2:

```text
$ for n in control-plane worker worker2; do echo "-- curso-k8s-l10-$n"; docker exec curso-k8s-l10-$n crictl images | grep -E 'IMAGE|curso-docker'; done
-- curso-k8s-l10-control-plane
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
-- curso-k8s-l10-worker
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
-- curso-k8s-l10-worker2
IMAGE                                           TAG                  IMAGE ID            SIZE
docker.io/library/curso-docker-prueba           1.0.0                5f32d8833d958       3.37MB
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Cada um dos três nós lista as duas imagens, com o *tag* que foi dado a elas (`1.6.0` e `1.0.0`). O `crictl` coloca `docker.io/library/` na frente porque é o nome que o `containerd` dá a uma imagem sem registro, e isso não significa que tenham sido baixadas dali. A coluna `IMAGE ID` (`70e09194319be`, `5f32d8833d958`) não coincide com a que o `docker image ls` mostra na máquina (`bd1b2e7d91b8` para o `revisor`): são dois armazenamentos distintos e cada um identifica a imagem à sua maneira. O mesmo vale para o tamanho: o `crictl` diz 3,68 MB para o `revisor` e o Docker, 16,2 MB; cada ferramenta mede de um jeito e não se comparam entre si. O que importa é que o nome e o *tag* estejam em **cada** nó: se faltar em um, um Pod que cair ali tentará baixar a imagem da internet e ficará em `ErrImagePull`, como na Lição 2, e esta é a consulta que explica isso.

**Um aviso sobre o `kind load`.** Se a imagem foi baixada de um registro, não a carregue com `kind load docker-image repo@sha256:…`. Nos testes do curso de Docker da Hábil (kind v0.33.0, Docker 29.2.1 com armazenamento containerd, processador arm64), esse comando respondeu “loading…” sem erro e a imagem **chegou ao nó, mas sem nome**: `docker exec <nó> crictl images` a mostrou como `docker.io/library/import-AAAA-MM-DD` com *tag* `<none>` (o nome de preenchimento que o `ctr images import` dá ao que importa sem uma referência própria; a data é a do relógio do nó, em UTC), e um Pod que pediu a mesma referência com *digest* ficou em `ErrImageNeverPull`, porque no nó não há nenhuma imagem com esse nome embora o conteúdo esteja lá. Coloque antes um *tag* local (`docker tag repo@sha256:… curso-docker-revisor:1.6.0`), carregue esse *tag* e confira sempre com `crictl images`, **olhando também as linhas `<none>`**: um filtro que só deixa passar o nome da imagem (como o `grep -E 'IMAGE|curso-docker'` acima) não as mostra. É um caso medido sem fonte oficial para esse sintoma exato; os *issues* do kind [#4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) e [#4224](https://github.com/kubernetes-sigs/kind/issues/4224) descrevem falhas vizinhas (com erro) do `kind load` com Docker recente, a maioria ligada ao armazenamento do `containerd` do Docker (#3795 e #4066; o #4224 é no OrbStack). As duas imagens desta lição são carregadas pelo *tag* local (`curso-docker-revisor:1.6.0`, `curso-docker-prueba:1.0.0`), e a saída acima é a verificação.

O cluster vazio não tem nenhum tipo de objeto que o Kubernetes não traga de fábrica. Conferimos, porque é o ponto de partida de tudo o que vem a seguir:

```text
$ kubectl get crd
No resources found
```

`crd` é a abreviação de *CustomResourceDefinition*, a definição de um tipo de objeto novo (visto na Lição 6). “No resources found” quer dizer que o cluster só conhece os tipos com os quais nasce. Nem `Gateway`, nem `IPAddressPool`, nem `HTTPRoute` existem ainda. É esse vazio que a ordem da seção 10.4 precisa preencher.

### 10.2 O mapa da pasta

#### 10.2.1 O que há e que lição pôs cada coisa

A pasta `programas/10-proyecto-final/` tem três coisas: a **base** (o projeto), os **overlays** (como ele é instalado em um cluster concreto) e os **scripts** (como se sobe). Assim ficam os arquivos das duas primeiras:

```text
$ find base overlays -type f ! -name token.txt | sort
base/.gitignore
base/cuentas.yaml
base/escalado.yaml
base/gateway.yaml
base/kustomization.yaml
base/namespace.yaml
base/prueba-deployment.yaml
base/prueba-service.yaml
base/red.yaml
base/reporte.yaml
base/revisor-deployment.yaml
base/revisor-service.yaml
overlays/ejemplo-nube/kustomization.yaml
overlays/kind/gatewayclass.yaml
overlays/kind/kustomization.yaml
overlays/kind/metallb-pool.yaml
overlays/kind/plataforma/envoy-gateway/kustomization.yaml
overlays/kind/plataforma/kustomization.yaml
overlays/kind/plataforma/metallb/kustomization.yaml
overlays/kind/plataforma/metrics-server/kustomization.yaml
```

(`find` percorre as pastas e lista arquivos; o `! -name token.txt` omite o token e `sort` os ordena. Aparece `.gitignore` porque o `find` não esconde arquivos que começam com ponto.)

Cada arquivo da base é uma lição que já foi feita. Esta tabela é o mapa; se algo ficou pela metade, aqui está onde olhar:

| Arquivo | O que é | De que lição vem |
|---|---|---|
| `base/namespace.yaml` | o namespace `revisor`, em nível `restricted` com a versão da política fixada | 7 |
| `base/cuentas.yaml` | as contas de serviço sem credenciais montadas e o papel (*role*) de somente leitura `observador` | 7 |
| `base/red.yaml` | as seis `NetworkPolicy`: tudo fechado e só as aberturas necessárias | 7 |
| `base/revisor-deployment.yaml` | o `revisor`: imagem, variáveis, token como arquivo, *probes*, recursos, desligamento ordenado, distribuição entre nós e `securityContext` | 2, 4, 5, 7, 9 |
| `base/revisor-service.yaml` | o nome estável `revisor` dentro do cluster | 3 |
| `base/prueba-deployment.yaml` e `base/prueba-service.yaml` | o serviço de teste que falha de propósito | 2, 3, 5, 7 |
| `base/gateway.yaml` | o ponto de entrada (`Gateway`) e a rota (`HTTPRoute`) | 6 |
| `base/reporte.yaml` | o volume do relatório e o `CronJob` que o guarda | 8 |
| `base/escalado.yaml` | o escalonamento automático (`HorizontalPodAutoscaler`) e o `PodDisruptionBudget` | 9 |
| `base/kustomization.yaml` | os geradores do `ConfigMap` e do `Secret` com *hash*, e a lista do que foi dito acima | 4 |
| `overlays/kind/metallb-pool.yaml` | a faixa de endereços que o MetalLB pode distribuir | 6 |
| `overlays/kind/gatewayclass.yaml` | a classe de entrada `eg`, atendida pelo Envoy Gateway | 6 |
| `overlays/kind/plataforma/` | MetalLB, Envoy Gateway e `metrics-server`, cada um na sua pasta | 6, 9 |

Faltam de propósito três famílias de arquivos. O `LoadBalancer` direto da Lição 6 (`revisor-publico`) foi retirado na 7: o único ponto de entrada para fora é o Gateway. Os Pods de apoio —`depurar`, `intruso`, `memoria`, o Job de carga— são **ferramentas para olhar e para provocar**, não parte do projeto: não precisam estar em todo cluster que se sobe, e por isso `depurar.yaml` e `intruso.yaml` vivem na raiz da pasta e não dentro da base. E o token: não é versionado.

#### 10.2.2 Três perguntas para decidir onde vai cada arquivo

A ordem das pastas não é capricho. Cada arquivo responde a três perguntas, nesta ordem:

1. **O `revisor` precisa dele em qualquer cluster onde for instalado?** Então vai na **base**. O Deployment, o Service, as regras de rede e o nível `restricted` valem igual no `kind`, no cluster da empresa ou na nuvem.
2. **Depende *deste* cluster?** Então vai em um **overlay**. A faixa de endereços do MetalLB sai da rede Docker do kind; em uma nuvem ela não existiria, porque o provedor fornece os balanceadores. O que depende do ambiente não se mistura com o que não depende.
3. **Instala-se uma só vez por cluster e vários projetos o usam?** Então é **plataforma**. MetalLB, Envoy Gateway e `metrics-server` não são do `revisor`: no dia em que um segundo serviço for publicado, ele usará a mesma classe de entrada e a mesma faixa. Por isso têm pasta própria e comando próprio.

Repare que a terceira pergunta não é questão de gosto: é a que decide *a ordem de aplicar*. A plataforma traz tipos novos, e o projeto os usa. A seção 10.4 demonstra isso.

### 10.3 Kustomize: base e *overlays*

#### 10.3.1 Uma base que não sabe de ninguém

O Kustomize já foi usado na Lição 4, com geradores. Aqui ele é usado para aquilo para que foi pensado: **compor**. A [documentação do Kubernetes](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) o define assim (traduzido): uma **base** é um diretório com um `kustomization.yaml` que contém um conjunto de recursos e as personalizações associadas; um ***overlay*** é um diretório com um `kustomization.yaml` que se refere a *outros* diretórios de kustomização como suas bases. E a frase que importa: “uma base não sabe nada de um *overlay* e pode ser usada em vários”.

Este é o `kustomization.yaml` da base. Quase tudo nele já é conhecido; o comentário do topo é novo e diz o que acabou de ser lido:

```yaml
# kustomization.yaml — Lección 10: la BASE del proyecto. No se aplica sola: la
# aplica un overlay (overlays/kind). Una base no sabe que existen sus overlays.
#
# El token NO se versiona: token.txt lo genera quien levanta el proyecto
# ((umask 077; openssl rand -hex 16 > base/token.txt)) y está en .gitignore. Los
# generadores agregan un hash al nombre: si cambia el contenido, cambia el
# nombre, y eso dispara el rollout del Deployment.
#
# Esta base necesita que la PLATAFORMA (MetalLB, Envoy Gateway y metrics-server)
# ya esté instalada y lista: sin sus tipos nuevos (CRD), Gateway y HTTPRoute no
# existen. Por eso el overlay se aplica DESPUÉS de overlays/kind/plataforma.
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
- reporte.yaml
- escalado.yaml
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

Três campos fazem todo o trabalho. `resources` é a lista de arquivos que ele monta. `namespace: revisor` é um **transformador**: coloca esse namespace em tudo o que o admite, sem que cada arquivo o repita (por isso no `deployment.yaml` não há `namespace:`). E os dois **geradores** criam o `ConfigMap` e o `Secret` com o nome mais um *hash* do conteúdo: se o conteúdo muda, o nome muda, e o Deployment —que o gerador reescreve para apontar para o nome novo— faz um *rollout* sozinho. Essa foi a Lição 4.

#### 10.3.2 Um overlay que só aponta

O `kustomization.yaml` do overlay de `kind` é mais curto que o da base:

```yaml
# overlays/kind — Lección 10: el proyecto completo para un clúster de kind que ya
# tiene su plataforma (ver plataforma/). Dos comandos y una espera, en este orden:
#
#   kubectl apply --server-side -k overlays/kind/plataforma
#   (esperar a que MetalLB, Envoy Gateway y metrics-server estén listos)
#   kubectl apply --server-side -k overlays/kind
#
# No lleva «namespace:» a propósito: la base ya pone todo en «revisor», y el rango
# de MetalLB y la GatewayClass viven fuera de ese espacio.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
- metallb-pool.yaml
- gatewayclass.yaml
```

Três linhas de recursos: a base (a pasta, não um arquivo), a faixa do MetalLB e a classe de entrada. O overlay **não copia** nada da base; só a nomeia. Por isso, se amanhã o Deployment do `revisor` mudar, os overlays não ficam sabendo nem precisam ficar. E repare no que o comentário diz sobre o `namespace:`: este overlay **não** o define, porque colocaria `revisor` também na faixa do MetalLB, que precisa viver em `metallb-system`, e a `GatewayClass` nem pertence a um namespace (vale para o cluster inteiro). O transformador da base já cuidou do que era dele.

Para ver o que um overlay monta sem tocar no cluster existe o `kubectl kustomize`, que **imprime** os manifestos resultantes. É o comando mais usado no trabalho com Kustomize: monta, não aplica. Quantos objetos, de que tipos:

```text
$ kubectl kustomize overlays/kind | grep '^kind:' | sort | uniq -c | sort -rn
   6 kind: NetworkPolicy
   4 kind: ServiceAccount
   2 kind: Service
   2 kind: Deployment
   1 kind: Secret
   1 kind: RoleBinding
   1 kind: Role
   1 kind: PodDisruptionBudget
   1 kind: PersistentVolumeClaim
   1 kind: Namespace
   1 kind: L2Advertisement
   1 kind: IPAddressPool
   1 kind: HTTPRoute
   1 kind: HorizontalPodAutoscaler
   1 kind: GatewayClass
   1 kind: Gateway
   1 kind: CronJob
   1 kind: ConfigMap

$ kubectl kustomize overlays/kind | grep -c '^kind:'
28
```

(`grep '^kind:'` fica com as linhas que *começam* com `kind:`, uma por objeto; `sort | uniq -c` conta quantos há de cada tipo e o último `sort -rn` ordena do maior para o menor.) É o projeto completo: cada linha da tabela da seção 10.2 tem a sua parte aqui. Três linhas merecem uma olhada. Os `ServiceAccount` e as `NetworkPolicy` são mais de um porque cada carga tem a sua conta e cada abertura de rede a sua regra. O `ConfigMap` e o `Secret` são um de cada: os geradores. E `Gateway`, `HTTPRoute`, `GatewayClass`, `IPAddressPool` e `L2Advertisement` são os objetos de **tipos que não existem em um cluster vazio**, o ponto da seção 10.4.

Os números acima são o total que o `kubectl apply` vai ver. Se alguma vez houver dúvida sobre o que o cluster vai receber, esta é a primeira pergunta a fazer, antes de aplicar: `kubectl kustomize` e contar.

#### 10.3.3 Mudar sem copiar: um overlay de exemplo

Os overlays servem para o que *muda* entre ambientes. Para ver o que uma camada pode mudar sem tocar na base, este arquivo descreve como seria a mesma base em um cluster de verdade. **Não é aplicado a nada**: apenas renderizado.

```yaml
# overlays/ejemplo-nube — Lección 10: un overlay de EJEMPLO que solo se RENDERIZA
# (kubectl kustomize); no se aplica a ningún clúster del curso. Muestra qué
# cambiaría la misma base en un clúster de verdad: la imagen sale de un registro,
# hay más réplicas y el reparto se hace por zona, no por nodo. No incluye la
# plataforma de kind (MetalLB, rango, GatewayClass): en la nube eso lo da el
# proveedor o el equipo de plataforma.
# registry.example.com es un dominio reservado para ejemplos: no existe.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
images:
- name: curso-docker-revisor
  newName: registry.example.com/equipo/revisor
  newTag: "1.6.0"
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: revisor
  patch: |-
    - op: replace
      path: /spec/minReplicas
      value: 3
    - op: replace
      path: /spec/maxReplicas
      value: 10
- target:
    kind: Deployment
    name: revisor
  patch: |-
    - op: replace
      path: /spec/template/spec/topologySpreadConstraints/0/topologyKey
      value: topology.kubernetes.io/zone
```

Há três ferramentas de mudança, e as três estão ali. **`images`** troca o nome e o *tag* de uma imagem em toda a árvore sem editar os Deployments: aqui a imagem sai de um registro em vez de estar carregada manualmente com `kind load`. **`patches`** com uma lista de operações (`op: replace`) é um *JSON Patch* ([RFC 6902](https://www.rfc-editor.org/rfc/rfc6902.html)): diz qual objeto (`target`, por tipo e nome), qual caminho mudar (`path`) e o valor novo. É preciso e às vezes incômodo, porque o caminho se escreve com o índice da lista (`topologySpreadConstraints/0` é a primeira restrição). A [documentação](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) também oferece o *patch* de mesclagem estratégica (escreve-se um pedaço do objeto e ele é mesclado), que é mais legível para mudanças grandes; para um número ou uma chave, o de operações é mais direto. E o domínio `registry.example.com` pende de `example.com`, um nome que a [RFC 2606](https://www.rfc-editor.org/rfc/rfc2606.html) reserva para exemplos e documentação: ninguém pode registrá-lo, e por isso não há risco de outra pessoa usá-lo e receber as imagens.

A comparação entre o overlay de `kind` e este é a melhor maneira de ver *o que* muda:

```text
$ diff <(kubectl kustomize overlays/kind) <(kubectl kustomize overlays/ejemplo-nube)
229c229
<         image: curso-docker-revisor:1.6.0
---
>         image: registry.example.com/equipo/revisor:1.6.0
293c293
<         topologyKey: kubernetes.io/hostname
---
>         topologyKey: topology.kubernetes.io/zone
391c391
<   maxReplicas: 6
---
>   maxReplicas: 10
399c399
<   minReplicas: 2
---
>   minReplicas: 3
418,424d417
< kind: GatewayClass
< metadata:
<   name: eg
< spec:
<   controllerName: gateway.envoyproxy.io/gatewayclass-controller
< ---
< apiVersion: gateway.networking.k8s.io/v1
440,457d432
< ---
< apiVersion: metallb.io/v1beta1
< kind: IPAddressPool
< metadata:
<   name: curso
<   namespace: metallb-system
< spec:
<   addresses:
<   - 172.30.255.200-172.30.255.250
< ---
< apiVersion: metallb.io/v1beta1
< kind: L2Advertisement
< metadata:
<   name: curso
<   namespace: metallb-system
< spec:
<   ipAddressPools:
<   - curso
[código de salida: 1]
```

(`diff` compara dois textos; `<( … )` entrega a saída de um comando como se fosse um arquivo, e funciona no `bash` e no `zsh`. As linhas com `<` são do overlay de `kind`; as que têm `>` são do de exemplo.) Leia por blocos. No primeiro há uma troca de imagem: a do `revisor` sai de um registro, não de `kind load`. O segundo é a restrição de distribuição: de `kubernetes.io/hostname` (distribui entre *nós*) para `topology.kubernetes.io/zone` (distribui entre *zonas*, que em uma nuvem são data centers distintos dentro de uma região). Depois, `maxReplicas` e `minReplicas` do escalonamento: de 6 para 10 e de 2 para 3. E no final, o que **sai** da árvore: a `GatewayClass`, a faixa e o anúncio do MetalLB, que são de `kind` e não da base. Quatro mudanças e uma subtração, e a base não foi tocada. (Se aparecer `[código de salida: 1]` embaixo do `diff`, não é um erro: o `diff` sai com 1 quando encontra diferenças, e com 0 quando não encontra.)

#### 10.3.4 Duas advertências sobre o que vem da internet

A pasta `plataforma` tem um `kustomization.yaml` por peça, e cada um aponta para um **arquivo remoto**:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -c '^kind:'
76
```

Esse é o número de objetos montados a partir de três endereços da internet. Uma peça em particular, o `metrics-server`, leva ainda um *patch* que já é conhecido da Lição 9:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -B1 -A1 'kubelet-insecure-tls'
        - --metric-resolution=15s
        - --kubelet-insecure-tls
        image: registry.k8s.io/metrics-server/metrics-server:v0.9.0
```

A flag `--kubelet-insecure-tls` faz com que o `metrics-server` não verifique o certificado com o qual cada `kubelet` se apresenta. O README do `metrics-server` v0.9.0 a descreve sem enfeites: “apenas para fins de teste”. No `kind` os certificados dos `kubelet` não são assinados pela autoridade do cluster, então sem a flag o `metrics-server` não consegue ler os nós. Em um cluster real **ela não se usa**: os certificados são bem assinados e a flag sobra. É a sexta das coisas que a seção 10.10 anota na lista do que falta.

As duas advertências sobre o remoto:

- **Toda vez que se aplica, baixa-se.** Um endereço com a versão no caminho (`…/v0.16.1/…`) fixa *qual versão* se pede, mas o conteúdo continua vindo da internet toda vez que o `kustomize` monta a árvore. Sem conexão, não há plataforma. Uma equipe de verdade costuma guardar uma cópia desses arquivos dentro do próprio repositório (ou em um espelho próprio), de modo que a subida não dependa de um site alheio nem de que um arquivo remoto não mude por baixo. Aqui isso não é feito para que se veja de onde sai cada peça.
- **Fixe a versão e anote-a.** As versões deste curso são MetalLB v0.16.1, Envoy Gateway v1.9.2 e `metrics-server` v0.9.0. Não é um detalhe: o [guia de instalação do Envoy Gateway](https://gateway.envoyproxy.io/docs/install/install-yaml/) explica que, ao atualizá-lo, é preciso atualizar primeiro os CRDs da Gateway API, e que se isso não for feito, as rotas TCP e UDP “são ignoradas em silêncio” até que os CRDs sejam aplicados. Uma versão que se move sem que ninguém decida é a origem de muitas manhãs de segunda-feira.

### 10.4 Por que dois comandos e uma espera

#### 10.4.1 Três coisas que uma instalação traz consigo

Na Lição 6 viu-se que o MetalLB e o Envoy Gateway não são “mais um Deployment”: ao serem instalados, adicionam ao cluster **tipos de objeto novos**, **controladores** que os atendem e **guardiões** que revisam o que é criado. Antes de seguir, os três com seus nomes exatos, porque a ordem desta lição nasce daí.

- **Um CRD (*CustomResourceDefinition*)** é a definição de um tipo de objeto que o Kubernetes não traz de fábrica. Enquanto não existir, escrever um `IPAddressPool` é como escrever uma palavra que o dicionário não tem: o `kube-apiserver` responde `no matches for kind`. E um CRD não está “pronto” ao ser criado. A [documentação de CRD](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) diz assim (traduzido): o servidor leva alguns segundos para criar o *endpoint* do tipo novo, e é possível vigiar a condição `Established` do CRD, ou a lista de tipos que o servidor anuncia, para saber quando ele já existe. Essa condição, `Established`, é a que o `kubectl wait` espera na seção 10.5.
- **Um controlador** é um programa (um Pod) que olha os objetos de um tipo e faz o mundo coincidir com eles: o do MetalLB distribui endereços; o do Envoy Gateway cria o Envoy que atende o ponto de entrada. Enquanto não estiver rodando, o objeto é aceito, mas ninguém o atende: o Gateway existe e não tem endereço. Um Deployment está *pronto* quando a sua condição `Available` é verdadeira.
- **Um *webhook* de admissão** é um guardião que o `kube-apiserver` consulta *antes* de gravar um objeto, para aceitá-lo, rejeitá-lo ou corrigi-lo. O MetalLB tem um que valida as faixas. A [documentação de controle de admissão dinâmico](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) tem uma peça que é preciso conhecer: se o servidor não consegue falar com o *webhook* (rede, tempo de espera esgotado, conexão recusada), a política `failurePolicy` decide o que acontece, e **o valor padrão é `Fail`**: a requisição é rejeitada. Ou seja, enquanto o Pod do guardião não atende, nenhum objeto dos tipos que ele vigia pode ser gravado.

As três coisas chegam no mesmo momento e não ficam prontas ao mesmo tempo. O que demora é o que obriga a esperar.

#### 10.4.2 `--server-side`: por que a plataforma é aplicada de outro jeito

Antes da ordem, o segundo comando da receita tem uma flag que ainda não tinha sido usada: `kubectl apply --server-side`. Convém entendê-la antes de vê-la falhar.

O `kubectl apply` de sempre é *do lado do cliente* (*client-side*): o `kubectl` calcula o que mudou e, para lembrar “o último que apliquei”, guarda uma cópia de todo o manifesto em uma anotação do próprio objeto, `kubectl.kubernetes.io/last-applied-configuration`. A [documentação do *Server-Side Apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) descreve a outra forma (traduzido): em vez de o cliente calcular e lembrar, o servidor acompanha qual **gestor** (*field manager*) é dono de cada campo do objeto. É estável desde o Kubernetes 1.22. Pede-se com `--server-side`.

Para esta lição importam duas consequências. A primeira: sem a cópia de “o último que apliquei” dentro do próprio objeto, acaba um limite. Uma anotação tem um tamanho máximo, e os CRDs da Gateway API e do Envoy Gateway são enormes (descrevem em detalhe cada campo de cada tipo). O guia oficial de instalação do Envoy Gateway, já citado na Lição 6, instala com `kubectl apply --server-side`, e na seção 10.4.3 se verá o que o cluster responde quando a flag é omitida. A segunda: com o *Server-Side Apply*, quem aplica é um gestor com nome, e se dois gestores tocam o mesmo campo com valores distintos, o servidor avisa de um **conflito** em vez de sobrescrever em silêncio. É isso o que se quer quando várias ferramentas (uma pessoa, um controlador, um *pipeline*) tocam o mesmo cluster.

E uma distinção para não confundir: `--server-side` muda *quem calcula a mudança*, não *o que é aplicado*. O projeto é aplicado igual com os dois modos; esta lição usa `--server-side` nos dois comandos para que o hábito seja um só.

#### 10.4.3 Primeiro erro: a plataforma sem `--server-side`

Aplica-se a plataforma “como sempre”, sem a flag, em um cluster vazio. A saída é longa, então é guardada em um arquivo e vista por partes: primeiro quanto foi criado, depois **só o que não é um “created”**:

```text
$ kubectl apply -k overlays/kind/plataforma > $L10_TMP/cliente.txt 2>&1; echo "código: $?"
código: 1

$ grep -c ' created$' $L10_TMP/cliente.txt
73

$ grep -v ' created$' $L10_TMP/cliente.txt | cut -c1-330
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "httproutes.gateway.networking.k8s.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
Error from server (Invalid): error when creating "overlays/kind/plataforma": CustomResourceDefinition.apiextensions.k8s.io "securitypolicies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(`> arquivo 2>&1` guarda no arquivo o que sai pela saída normal *e* pela de erros; `$?` é o código de saída do comando anterior; `grep -v` imprime as linhas que **não** coincidem; `cut -c1-330` corta cada linha em 330 caracteres para que caiba.)

Leia em ordem. **O código de saída é 1**: o `apply` terminou com erro. **Foram criados 73 objetos**, e três linhas dizem o que não foi possível: os CRDs `envoyproxies.gateway.envoyproxy.io`, `httproutes.gateway.networking.k8s.io` e `securitypolicies.gateway.envoyproxy.io` “are invalid: `metadata.annotations: Too long: may not be more than 262144 bytes`”. São 262.144 bytes, isto é, 256 KiB (256 × 1024): o teto que o `kube-apiserver` impõe às anotações de um objeto. Essa anotação é a cópia de “o último que apliquei” de que falou a seção 10.4.2, e esses três CRDs descrevem tantos campos que a própria definição, copiada dentro do objeto, passa do teto. Mediu-se cada CRD da plataforma convertido em JSON compacto (`programas/10-proyecto-final/crd-tamanos.sh`; a saída, `crd-tamanos.salida.txt`): `envoyproxies` pesa uns 649 mil bytes, `httproutes` uns 299 mil e `securitypolicies` uns 274 mil; o seguinte em tamanho, `backendtrafficpolicies`, fica em torno de 128 mil. São exatamente os três que falharam e nenhum a mais.

Repare no que essa mensagem **não** faz: não diz “falta uma flag”. Diz que um objeto não cabe, e é preciso saber que a causa é a forma de aplicar. E repare no estado em que ela deixa o cluster, que é o grave: 73 de 76 objetos estão criados, então o cluster *parece* ter plataforma, mas lhe falta `httproutes`, o tipo da rota usada na Lição 6, e lhe faltam dois tipos do Envoy Gateway. Um estado pela metade que parece quase saudável é pior que um que falha por completo. Este cluster foi apagado, e outro foi criado para o experimento seguinte: é o método do curso.

#### 10.4.4 Segundo erro: plataforma e projeto em um único comando

A pergunta natural é: por que dois comandos? Não dá para juntar tudo em um, com a flag? `fig10_01.todo-junto/kustomization.yaml` é um **programa que falha de propósito** (a primeira linha avisa): uma única kustomização que contém a plataforma e o projeto.

```yaml
# fig10_01.todo-junto/kustomization.yaml — FALLA A PROPÓSITO (o funciona a medias):
# junta la plataforma y el proyecto en UN solo «kubectl apply». Las dos mitades
# no tienen orden de espera entre sí: el proyecto pide tipos (IPAddressPool,
# GatewayClass, Gateway, HTTPRoute) que la plataforma todavía no ha registrado.
# Se aplica con:  kubectl apply --server-side -k fig10_01.todo-junto
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../overlays/kind/plataforma
- ../overlays/kind
```

Aplica-se em um cluster vazio (outro, recém-criado) com a flag correta. Olha-se o mesmo que antes: quantos objetos entraram e quais não.

```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto1.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto1.txt
99

$ grep -v serverside-applied $L10_TMP/junto1.txt | cut -c1-330
resource mapping not found for name: "revisor" namespace: "revisor" from "fig10_01.todo-junto": no matches for kind "Gateway" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "eg" namespace: "" from "fig10_01.todo-junto": no matches for kind "GatewayClass" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "revisor" namespace: "revisor" from "fig10_01.todo-junto": no matches for kind "HTTPRoute" in version "gateway.networking.k8s.io/v1"
ensure CRDs are installed first
resource mapping not found for name: "curso" namespace: "metallb-system" from "fig10_01.todo-junto": no matches for kind "IPAddressPool" in version "metallb.io/v1beta1"
ensure CRDs are installed first
resource mapping not found for name: "curso" namespace: "metallb-system" from "fig10_01.todo-junto": no matches for kind "L2Advertisement" in version "metallb.io/v1beta1"
ensure CRDs are installed first
```

Leia do mesmo jeito. O código volta a ser 1, e desta vez entraram **99 objetos** dos 104 que a árvore monta (76 da plataforma e 28 do projeto). Os cinco que não entraram dizem a mesma coisa: `no matches for kind "Gateway"`, `"GatewayClass"`, `"HTTPRoute"`, `"IPAddressPool"` e `"L2Advertisement"`, cada um com o aviso `ensure CRDs are installed first` (“garanta que os CRDs estejam instalados primeiro”). Compare-os com as cinco condições `Established` que a seção 10.5.2 espera: são os mesmos cinco tipos. Entraram os Deployments, os Services, as regras de rede, o namespace e os próprios CRDs, que não dependem de nenhum tipo novo; não entrou nada que dependa. O `kubectl` resolve **no início**, antes de criar qualquer coisa, que tipos o servidor conhece, e com essa lista revisa os 104 objetos. Os CRDs entram na lista, mas os objetos que os usam são verificados contra o catálogo que existia *antes* de eles serem criados: por isso cinco falham mesmo que os CRDs sejam criados no mesmo comando. Um `apply` não volta a perguntar no meio do caminho ([`mapper.go` do cli-runtime](https://github.com/kubernetes/cli-runtime/blob/master/pkg/resource/mapper.go)).

A tentação seguinte é a pior: repetir o mesmo comando, sem mudar nada e sem esperar, para ver se desta vez passa. Foi feito, e foi isto que aconteceu:


```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto2.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto2.txt
102

$ grep -v serverside-applied $L10_TMP/junto2.txt | cut -c1-330
Error from server (InternalError): Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
Error from server (InternalError): Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
```

Houve progresso, e é isso que torna o método traiçoeiro. Agora entraram **102 objetos**: os três tipos da Gateway API já existiam, então `Gateway`, `GatewayClass` e `HTTPRoute` passaram. Restam dois, a faixa e o seu anúncio, e falham por outra causa: `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connect: connection refused`. O tipo `IPAddressPool` já existe, mas o guardião que o MetalLB coloca na frente dele (seção 10.4.1) ainda não está escutando: o Pod do controlador está iniciando. Como a `failurePolicy` é `Fail`, o `kube-apiserver` rejeita o objeto. `connection refused` quer dizer que o endereço do Service do guardião (o que aparece depois de `dial tcp`, um IP do cluster que em outra execução será outro) existe, mas ninguém atende por trás.

Cada nova tentativa descobre a camada seguinte do que faltava: primeiro os tipos, depois os guardiões. Uma terceira tentativa provavelmente passaria (não foi medida, porque não faz sentido medi-la), e então ficaria escrito na wiki “repita até passar”. Isso é o contrário de uma receita: não diz quantas vezes, não diz o que esperar e, no dia em que uma tentativa falhar por uma causa diferente, não haveria como distingui-la. A única coisa que mudou entre a tentativa 1 e a 2 foi a passagem do tempo; o que faz falta é nomear o que se espera.

#### 10.4.5 O que os dois erros ensinam

Os dois erros são versões do mesmo fato, e servem para fixar três regras:

1. **A plataforma vai primeiro e com `--server-side`.** Traz tipos novos, controladores e guardiões. É um comando à parte porque tem uma condição de saída: “os tipos estão estabelecidos e os controladores estão no ar”.
2. **Entre a plataforma e o projeto há uma espera por condição.** Não um `sleep 30`, que funciona na máquina de quem escreve e falha em uma mais lenta, mas `kubectl wait --for=condition=…`. A [documentação do `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) o descreve como esperar “uma condição específica em um ou vários recursos” e sai com erro se ela não chegar no tempo dado (`--timeout`). Na execução se verá que, quando a condição é cumprida, ele imprime `condition met`. Um `sleep` diz “passou tempo”; o `wait` diz “aconteceu o que eu precisava”. E quando falha, falha com nome.
3. **O projeto vai depois, no seu próprio comando.** Tudo o que usa um tipo novo, um controlador ou um guardião da plataforma vai aqui.

A receita fica em três linhas: `apply` da plataforma, `wait`, `apply` do projeto. É o “dois comandos e uma espera” do título da lição, e a primeira meta do curso conta assim: são três passos, e a ordem é o que os define.

Também há uma razão de fundo, e não só deste curso. A documentação do Helm, que a seção 10.9 nomeia, tem o mesmo problema e o diz com outras palavras nas suas [práticas recomendadas sobre CRDs](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) (traduzido): “a declaração [do CRD] deve estar registrada antes que qualquer recurso desse tipo possa ser usado, e o registro às vezes leva alguns segundos”. Não é uma esquisitice do Kustomize nem do `kubectl`; é uma propriedade de como o Kubernetes estende os seus tipos.

### 10.5 Subir manualmente: plataforma, espera, projeto

Agora o caminho bom, em um cluster recém-criado, com cada passo à vista. É o cluster da seção 10.1 (o das saídas dessa seção): três nós, as duas imagens carregadas, nenhum CRD. E antes de **cada** comando que muda algo, `ctx &&`.

#### 10.5.1 Passo 1: a plataforma

```bash
ctx && kubectl apply --server-side -k overlays/kind/plataforma > "$L10_TMP/plataforma.txt"
```

Com a flag e em um cluster vazio, tudo entra. O comando imprime uma linha por objeto; foi guardado em um arquivo e isto é o que se vê dele:

```text
$ kubectl apply --server-side -k overlays/kind/plataforma > $L10_TMP/plataforma.txt; grep -c serverside-applied $L10_TMP/plataforma.txt
76

$ head -4 $L10_TMP/plataforma.txt
namespace/envoy-gateway-system serverside-applied
namespace/metallb-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
```

São **76** linhas, uma por objeto, e nenhuma diz `Error`. `serverside-applied` quer dizer que o servidor aplicou o objeto: criou-o ou atualizou-o; em um cluster vazio, todos são criações. As duas primeiras linhas criam os namespaces `envoy-gateway-system` e `metallb-system`, e as seguintes são CRDs (`backends.gateway.envoyproxy.io`, `backendtlspolicies.gateway.networking.k8s.io`…). Compare com a seção 10.4.3: com `--server-side`, os três CRDs que não cabiam entram como os demais, porque já não se cola neles a cópia de “o último que apliquei”.

O cluster já conhece os tipos novos, mas os controladores ainda estão iniciando. Assim fica neste instante:

```text
$ kubectl get crd | wc -l
      31

$ kubectl get pods -n metallb-system
NAME                          READY   STATUS              RESTARTS   AGE
controller-76f4cf76b7-kclm8   0/1     ContainerCreating   0          0s
speaker-cbfnt                 0/1     ContainerCreating   0          0s
speaker-dgln6                 0/1     ContainerCreating   0          0s
speaker-swc2d                 0/1     ContainerCreating   0          0s
```

O cluster já conhece **30** tipos novos (`kubectl get crd | wc -l` conta 31 porque inclui a linha de cabeçalhos). E os Pods do MetalLB, no primeiro segundo, estão todos em `0/1 ContainerCreating`: o `controller` e um `speaker` por nó ainda estão baixando a imagem e iniciando. Este é o instante perigoso da seção 10.4: os tipos existem e os guardiões não atendem. Aplicar o projeto *agora* daria o `connection refused` do segundo erro.

#### 10.5.2 Passo 2: a espera

Cinco esperas, cada uma com a sua condição. As cinco juntas são “a plataforma está pronta”:

```bash
ctx && kubectl wait --for=condition=Established --timeout=120s \
  crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
ctx && kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
ctx && kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
ctx && kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
ctx && kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
```

```text
$ kubectl wait --for=condition=Established --timeout=120s crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
deployment.apps/controller condition met

$ kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
deployment.apps/envoy-gateway condition met

$ kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
deployment.apps/metrics-server condition met
```

As cinco terminam bem. A primeira, de tipos, responde de imediato `condition met` para os cinco CRDs: já estavam estabelecidos. As outras são as lentas: o `controller` do MetalLB, os três `speaker` (o progresso diz `0 of 3 updated pods are available…`, depois `1 of 3`, `2 of 3`, e por fim `successfully rolled out`), o controlador do Envoy Gateway e o `metrics-server`. Os nós são novos e não têm nenhuma imagem: cada um precisa baixar da internet as do MetalLB, do Envoy Gateway e do `metrics-server` antes de poder iniciar os Pods. Nesta execução a espera completa durou 153 segundos; nas execuções de preparação da lição variou desde esses 153 até 881 segundos (quase quinze minutos), conforme a conexão e a carga da máquina. Cada `kubectl wait` leva o seu próprio teto de 600 segundos; os 881 foram a soma das cinco esperas, não uma só (a saída está em `corridas-preparacion/corrida4.txt`). Se na conexão de quem acompanha uma única esgotar os 600, o erro não desfaz nada: repita o mesmo comando. Não se separou quanto desse tempo é download e quanto é inicialização, então isso não é afirmado. O que se afirma é o que é preciso planejar: **a espera é a parte mais longa da subida**, e por isso convém que seja uma espera por condição e não um tempo fixo que alguém tenha que adivinhar.

E uma espera também serve para saber quando algo **não** chega. Se for pedida ao `kubectl wait` uma condição que não se cumpre, com um teto curto, ele desiste com um erro em vez de travar. Aqui se pede ao controlador do Envoy Gateway, que está `Available`, que passe a não estar, e dão-se 5 segundos:

```text
$ kubectl wait --for=condition=Available=false --timeout=5s -n envoy-gateway-system deployment/envoy-gateway
error: timed out waiting for the condition on deployments/envoy-gateway
[código de salida: 1]
```

`error: timed out waiting for the condition on deployments/envoy-gateway`, e o script anota `[código de salida: 1]`. É o comportamento que se quer de uma espera: não trava, não inventa um sucesso e diz que condição de que objeto não chegou. Um `sleep 300` seguido de um `apply` teria deixado sem essa informação.

Leia-as com a lista de três coisas da seção 10.4.1 em mãos. A primeira espera é de **tipos**: `Established` é a condição do CRD. As outras quatro são de **controladores**: `Available` para os Deployments (`controller` do MetalLB, `envoy-gateway`, `metrics-server`) e `rollout status` para o `DaemonSet` `speaker`. Um `DaemonSet` não tem `Available`; tem um progresso de “quantos dos Pods que deve haver estão prontos”, e o `rollout status` o acompanha até que sejam todos (um por nó). O *webhook* do MetalLB é atendido pelo Pod `controller`: quando ele está `Available`, o guardião já responde.

#### 10.5.3 Passo 3: o projeto

```bash
ctx && kubectl apply --server-side -k overlays/kind
```

```text
$ kubectl apply --server-side -k overlays/kind
namespace/revisor serverside-applied
serviceaccount/observador serverside-applied
serviceaccount/prueba serverside-applied
serviceaccount/reporte serverside-applied
serviceaccount/revisor serverside-applied
role.rbac.authorization.k8s.io/observador serverside-applied
rolebinding.rbac.authorization.k8s.io/observador serverside-applied
configmap/revisor-config-t6cm6872fk serverside-applied
secret/revisor-token-fgdb694k82 serverside-applied
service/prueba serverside-applied
service/revisor serverside-applied
persistentvolumeclaim/reportes serverside-applied
deployment.apps/prueba serverside-applied
deployment.apps/revisor serverside-applied
cronjob.batch/reporte serverside-applied
poddisruptionbudget.policy/revisor serverside-applied
horizontalpodautoscaler.autoscaling/revisor serverside-applied
gateway.gateway.networking.k8s.io/revisor serverside-applied
gatewayclass.gateway.networking.k8s.io/eg serverside-applied
httproute.gateway.networking.k8s.io/revisor serverside-applied
ipaddresspool.metallb.io/curso serverside-applied
l2advertisement.metallb.io/curso serverside-applied
networkpolicy.networking.k8s.io/acceso-revisor-salida serverside-applied
networkpolicy.networking.k8s.io/cerrado serverside-applied
networkpolicy.networking.k8s.io/dns serverside-applied
networkpolicy.networking.k8s.io/prueba-entrada serverside-applied
networkpolicy.networking.k8s.io/revisor-entrada serverside-applied
networkpolicy.networking.k8s.io/revisor-salida serverside-applied
```

São **28** linhas, e cada linha da tabela da seção 10.2 está ali: o namespace, as quatro contas de serviço, o papel (*role*) e a sua associação, o `ConfigMap` e o `Secret` com o seu *hash*, os dois Services, o volume, os dois Deployments, o `CronJob`, o `PodDisruptionBudget`, o escalonamento, o `Gateway` com o seu `HTTPRoute`, as seis regras de rede e os **três** objetos que só existem por causa do overlay: a `GatewayClass` `eg`, a faixa e o anúncio do MetalLB. Repare que eles não saem no final, mas espalhados: o Kustomize ordena a saída por tipo de objeto, não pelo arquivo de onde vêm. O nome do `ConfigMap`, `revisor-config-t6cm6872fk`, é **o mesmo** das Lições 4 e 5, porque a lista de serviços é a mesma: o *hash* é do conteúdo. O do `Secret` muda a cada execução, porque o token é novo. E não há nenhuma linha que comece com `Warning`, mas essa ausência se prova, não se olha.

Uma afirmação como “não há avisos” se prova contando, e com um caso em que haja (a seção 10.7 faz isso). Aqui a contagem, com `-i` para não depender de maiúsculas:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -ci warning
0
[código de salida: 1]
```

O `0` é a contagem. O `[código de salida: 1]` que o script anota não é uma falha: o `grep` sai com 1 quando não encontra nenhuma linha, ainda que com `-c` imprima o zero. Aqui significa “zero avisos”.

Depois, mais duas esperas: que os Deployments estejam `Available` e que o ponto de entrada esteja `Programmed` (a condição do `Gateway` que diz “já tem endereço e um Envoy que o atende”):

```bash
ctx && kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
ctx && kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
```

```text
$ kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
deployment.apps/revisor condition met
deployment.apps/prueba condition met

$ kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
gateway.gateway.networking.k8s.io/revisor condition met
```

Falta uma espera que o `kubectl wait` não cobre bem: o escalonamento automático precisa de alguns segundos para ler as primeiras métricas, e enquanto não as tem mostra `<unknown>`. Desta vez isso não se resolve com um `sleep` às cegas, mas com um ciclo curto e **visível**, que confere a cada 5 segundos por até dois minutos e para assim que o escalonamento já tem uma métrica:

```bash
for _ in $(seq 1 24); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

Há um `sleep`, e está certo: é a **espera de uma condição com um teto**. A cada volta se pergunta se já aconteceu o que importa. Se não acontecer em 24 voltas, o ciclo desiste e o comando seguinte mostra o `<unknown>` em vez de escondê-lo.

#### 10.5.4 Vê-lo funcionando

Tudo o que as nove lições construíram, em uma única consulta:

```text
$ kubectl get all,pvc,cronjob,hpa,pdb,networkpolicy,gateway,httproute -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rzh88    1/1     Running   0          82s
pod/revisor-654b5d75dc-6m6s6   1/1     Running   0          82s
pod/revisor-654b5d75dc-dq4pp   1/1     Running   0          82s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.57.22     <none>        9000/TCP   82s
service/revisor   ClusterIP   10.96.239.233   <none>        80/TCP     82s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           82s
deployment.apps/revisor   2/2     2            2           82s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       82s
replicaset.apps/revisor-654b5d75dc   2         2         2       82s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          82s

NAME                    SCHEDULE      TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/reporte   */5 * * * *   <none>     False     0        <none>          82s

NAME                             STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/reportes   Pending                                      standard       <unset>                 82s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     82s

NAME                                                    POD-SELECTOR               AGE
networkpolicy.networking.k8s.io/acceso-revisor-salida   acceso-revisor=permitido   82s
networkpolicy.networking.k8s.io/cerrado                 <none>                     82s
networkpolicy.networking.k8s.io/dns                     <none>                     82s
networkpolicy.networking.k8s.io/prueba-entrada          app=prueba                 82s
networkpolicy.networking.k8s.io/revisor-entrada         app=revisor                82s
networkpolicy.networking.k8s.io/revisor-salida          app=revisor                82s

NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.30.255.200   True         82s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               82s
```

Leia por blocos, de cima para baixo.

- **Pods.** Os dois do `revisor` e o de `prueba`, os três `1/1 Running`. Se o projeto for subido justo em um minuto múltiplo de cinco, aparecerá ainda um quarto Pod, `reporte-…`, em `0/1 Completed`: a tarefa agendada da Lição 8, que já rodou e terminou bem (em uma execução de preparação desta lição ele apareceu; na que se cola aqui, ainda não).
- **Services.** Os dois são `ClusterIP`, sem `EXTERNAL-IP`: o `LoadBalancer` direto da Lição 6 já não existe. O único ponto de entrada é o Gateway.
- **Deployments e ReplicaSets.** `2/2` e `1/1`. Cada Deployment tem um ReplicaSet com o seu *hash*. Se ele for diferente em outra execução, é normal: depende do nome do `Secret`, que muda com o token.
- **Escalonamento.** `cpu: …/50%`, `MINPODS 2`, `MAXPODS 6`, e as duas réplicas atuais. Que haja uma porcentagem e não `<unknown>` quer dizer que o `metrics-server` já entregou a primeira leitura; por isso se espera com o ciclo da seção 10.5.3.
- **CronJob.** O horário `*/5 * * * *`, sem suspender, `ACTIVE 0` e `LAST SCHEDULE <none>`: ainda não disparou nem uma vez. Quando disparar, aparecerá um Job com o seu Pod.
- **Volume.** O PVC `reportes` está em `Pending`, e é o correto: na Lição 8 viu-se que a classe `standard` espera o primeiro Pod que o use (`WaitForFirstConsumer`) antes de criar o disco. Passará a `Bound` quando o `CronJob` disparar pela primeira vez.
- **`PodDisruptionBudget`.** `MIN AVAILABLE 1`, e `ALLOWED DISRUPTIONS 1`: com duas réplicas, o cluster pode retirar uma de cada vez.
- **Regras de rede.** As seis da Lição 7, com os seus seletores.
- **Gateway.** Classe `eg`, **endereço `172.30.255.200`** (o primeiro da faixa do overlay) e `PROGRAMMED True`. É o endereço que o MetalLB distribuiu. **`HTTPRoute`.** Sem nomes de site (`HOSTNAMES` vazio): atende qualquer um.

E as métricas, que são a prova de que o `metrics-server` e o escalonamento estão conectados:

```text
$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-rzh88    1m           1Mi             
revisor-654b5d75dc-6m6s6   1m           1Mi             
revisor-654b5d75dc-dq4pp   2m           1Mi             
```

Falta o mais importante: que **alguém de fora** chegue. O endereço do ponto de entrada sai do próprio `Gateway`, e o cliente é um contêiner Docker conectado à mesma rede dos nós, **fora** do cluster (o mesmo truque da Lição 6):

```bash
IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
CURL='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
docker run --rm --network kind $CURL -s -m 5 "http://$IP_GW/salud"
docker run --rm --network kind $CURL -s -m 5 -o /dev/null -w '%{http_code}\n' "http://$IP_GW/api/estados"
docker run --rm --network kind $CURL -s -m 5 -H "Authorization: Bearer $TOKEN" "http://$IP_GW/api/estados?formato=tabla"
```

(No bloco de saída abaixo, o script abrevia cada `docker run … curl` para `curl`, para que caiba. `$TOKEN` é a variável da seção 10.1.2.)

```text
$ curl -s -m 5 http://172.30.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.30.255.200/api/estados
401

$ curl -s -m 5 -H "Authorization: Bearer $TOKEN" 'http://172.30.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200
```

As três requisições chegaram de fora do cluster ao endereço que o MetalLB deu ao Gateway. `/salud` responde sem pedir nada. `/api/estados` **sem token** dá `401` (a Lição 4: o `revisor` exige `Authorization: Bearer …`). E com o token, a tabela do relatório. Repare que o token chega pelo ponto de entrada em um cabeçalho, em texto puro: é o ponto 4 da lista da seção 10.10.

No terminal de quem acompanha, o nome da rede é `kind` (assim ficou o bloco acima). Se a execução não usou essa rede, a seção “Sobre as execuções” explica.

### 10.6 Automatizar sem esconder a ordem

#### 10.6.1 O que se automatiza e o que não se deve esconder

Manualmente, a subida são três blocos e oito esperas. Para repeti-la em cada cluster novo —o de quem acompanha amanhã, o de uma colega, o de uma etapa automática de um *pipeline*— convém um script. E aqui há uma decisão de projeto que separa um script que ajuda de um que atrapalha. Há duas maneiras de escrevê-lo:

- **O script que esconde a ordem.** Uma única linha que “tenta de novo até passar”: `until kubectl apply -k .; do sleep 5; done`, ou um `sleep 120` entre duas aplicações, ou um `|| true` para que nada pare. Funciona quase sempre e, quando falha, não diz por quê: o ciclo fica dando voltas, ou o `sleep` foi curto na máquina lenta, ou o erro foi engolido em silêncio. Na seção 10.4.4 viu-se o que faz a nova tentativa às cegas: aplica pela metade e deixa a quem executa adivinhar o que falta.
- **O script que mostra a ordem.** Os mesmos três passos, cada um com nome, cada um com a sua verificação de contexto, com esperas por **condição** e com um teto de tempo. Quando falha, falha em um passo com nome, com uma mensagem do `kubectl` que diz que condição não chegou. E quem o lê aprende a ordem, que é metade do valor.

Este é o segundo. Chama-se `levantar.sh`, vive na pasta da lição e é o que uma etapa de um *pipeline* chamaria tal qual:

```bash
#!/usr/bin/env bash
# levantar.sh — Lección 10: el proyecto completo en un clúster recién creado, en
# TRES pasos explícitos, sin esconder el orden. Es lo que un paso de pipeline
# haría igual: la única entrada es el contexto de kubectl que espera encontrar.
#
#   1. la plataforma: metrics-server, MetalLB y Envoy Gateway (traen tipos nuevos,
#      controladores y webhooks)
#   2. esperar a que la plataforma esté lista (tipos registrados, controladores arriba)
#   3. el proyecto
#
# Por qué hay orden: un IPAddressPool, una GatewayClass o un Gateway solo existen
# cuando su CRD ya está registrado, y MetalLB rechaza su rango si su webhook
# todavía no atiende.
#
# Requisitos: un clúster de kind con las dos imágenes cargadas (kind load
# docker-image) y su contexto activo. Uso, desde esta carpeta:
#   ./levantar.sh kind-curso-k8s-l10
set -euo pipefail
cd "$(dirname "$0")"
ESPERADO="${1:?uso: ./levantar.sh <contexto-esperado>   (por ejemplo kind-curso-k8s-l10)}"
NODO_CONTROL="${ESPERADO#kind-}-control-plane"

# Antes de CADA paso que cambia algo: ¿el contexto activo es el esperado?
contexto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  [ "$actual" = "$ESPERADO" ] || { echo "ALTO: el contexto activo es «$actual», no «$ESPERADO»." >&2; exit 1; }
}

# El token no se versiona: si falta, se genera uno nuevo (de mentira, para el curso).
[ -s base/token.txt ] || (umask 077; openssl rand -hex 16 > base/token.txt)

echo "== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?"
contexto
RANGO="$(sed -n 's/^ *- *\([0-9.]*\)-.*/\1/p' overlays/kind/metallb-pool.yaml | head -1)"
IP_NODO="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODO_CONTROL")"
echo "primer IP del rango: $RANGO · IP del nodo de control: $IP_NODO"
[ "${RANGO%.*.*}" = "${IP_NODO%.*.*}" ] || {
  echo "ALTO: el rango de overlays/kind/metallb-pool.yaml no está en la red de los nodos (se compara la red /16)." >&2; exit 1; }

echo "== 1. Plataforma"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind/plataforma)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
echo "(paso 1 terminó a los $SECONDS s)"

echo "== 2. Esperar a la plataforma"
contexto
kubectl wait --for=condition=Established --timeout=120s \
  crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io \
  crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io
kubectl wait --for=condition=Available --timeout=600s -n metallb-system deployment/controller
kubectl rollout status --timeout=600s -n metallb-system daemonset/speaker
kubectl wait --for=condition=Available --timeout=600s -n envoy-gateway-system deployment/envoy-gateway
kubectl wait --for=condition=Available --timeout=600s -n kube-system deployment/metrics-server
echo "(paso 2 terminó a los $SECONDS s)"

echo "== 3. Proyecto"
contexto
SALIDA="$(kubectl apply --server-side -k overlays/kind)"
echo "objetos aplicados: $(printf '%s\n' "$SALIDA" | grep -c serverside-applied)"
kubectl wait --for=condition=Available --timeout=600s -n revisor deployment/revisor deployment/prueba
kubectl wait --for=condition=Programmed --timeout=600s -n revisor gateway/revisor
kubectl get gateway revisor -n revisor
echo "(paso 3 terminó a los $SECONDS s)"
```

#### 10.6.2 O script, linha por linha

Lê-se de cima para baixo, e quase tudo é algo que já se conhece com outra cara.

**`set -euo pipefail`.** Três opções do `bash` em uma. `-e` interrompe o script no primeiro comando que falha. `-u` faz com que usar uma variável que não existe seja um erro, em vez de lê-la vazia. `-o pipefail` faz com que um encadeamento (`a | b`) falhe se falhar *qualquer* uma das partes, não só a última. Juntas são a diferença entre um script que para onde está o problema e um que segue como se nada tivesse acontecido. É a mesma razão pela qual o `levantar.sh` usa `|| true` em um único lugar: ao ler o contexto ativo, onde uma falha é aceita (o script o compara depois e para com uma mensagem clara). O mesmo no `probar-levantar.sh`, na limpeza do cluster e na contagem de clusters vivos, e nas falhas de propósito do `correr.sh`: cada `|| true` está colado a um comando concreto cuja falha é aceita e se diz por quê, que é o único uso que “O que se faz errado” admite.

**`ESPERADO="${1:?uso: …}"`.** O script **não adivinha** em que cluster está: recebe o contexto como argumento e, se faltar, imprime o uso e para. `${1:?mensagem}` significa “o primeiro argumento, e se estiver vazio, falha com esta mensagem”. É o contrário de um script que usa “o cluster que estiver ativo”: um script que instala o MetalLB e o Envoy Gateway no contexto ativo, sem perguntar, pode instalar essas coisas no cluster errado.

**`contexto()`.** A função `ctx` da seção 10.1, mas para um script: compara `kubectl config current-context` com `ESPERADO` e, se não coincidirem, imprime “ALTO” e faz `exit 1`. É chamada **antes de cada passo**, não uma única vez no começo, porque um script longo roda por minutos e alguém (ou algo) pode mudar o contexto entre um passo e outro.

**O passo 0: a rede.** Isto é novo e existe por uma razão concreta. A faixa de endereços do MetalLB vive em `overlays/kind/metallb-pool.yaml`. Se essa faixa não cair na mesma rede dos nós, o MetalLB atribui um endereço ao Gateway, o `kubectl` diz que tudo está bem, e ninguém de fora consegue chegar a ele: a falha é silenciosa. O `sed` extrai o primeiro endereço da faixa, o `docker inspect` extrai o IP do nó de controle, e a comparação `${RANGO%.*.*}` (tirar os dois últimos números: `172.30.255.200` vira `172.30`) contra `${IP_NODO%.*.*}` confere que os dois estão na mesma rede `/16`. É uma verificação simples —supõe redes desse tamanho, e a mensagem de erro diz isso—, mas converte uma falha muda em um “ALTO” com causa.

**O passo 1.** Captura a saída do `kubectl apply` em uma variável (`SALIDA="$(…)"`) e mostra só a contagem de `serverside-applied`. Se o `kubectl apply` falhar, a atribuição falha e o `set -e` interrompe o script: não se chega à contagem. A saída não é descartada com `>/dev/null`: é **medida**.

**O passo 2.** As cinco esperas da seção 10.5.2, sem mudanças. Cada uma com o seu teto (`--timeout`): 120 segundos para que os CRDs existam, 600 (dez minutos) para os controladores, que dependem do tempo que a conexão levar para baixar imagens.

**O passo 3.** Aplica o projeto e espera duas coisas: os Deployments `Available` e o ponto de entrada `Programmed`. No final, `kubectl get gateway` imprime o resultado que se quer ver.

**`$SECONDS`.** Uma variável do `bash` que conta os segundos desde que o script iniciou. Cada passo informa em quantos segundos terminou. Não é decoração: se um passo ficar lento, vê-se, e os tempos deste script são os que a seção 10.6.3 usa para dizer quanto demora subir o projeto.

O que ele **não** faz também é uma decisão. Não cria o cluster (isso é de quem o chama: a gente mesma, ou uma etapa anterior do *pipeline*). Não carrega as imagens. E não faz `curl`: conferir que o ponto de entrada responde de fora precisa de um cliente na rede Docker, e isso é uma prova, não uma subida. Um script que sobe e outro que prova podem ser trocados separadamente.

Um detalhe mais sobre o código de saída. O `levantar.sh` sai com 0 somente se **todo** o percurso terminou; com qualquer falha, sai com um código diferente de 0 no passo onde ocorreu. É a única coisa que um *pipeline* precisa saber para marcar uma etapa como verde ou vermelha, e por isso o script cuida disso e não depende de que alguém leia o texto da saída.

#### 10.6.3 Prová-lo de verdade: criar, subir, apagar, recriar

Um script que nunca foi rodado contra um cluster vazio é como o backup do caso do GitLab: existe e não se sabe se serve. Prova-se com o `probar-levantar.sh`: cria o cluster, roda o `levantar.sh`, confere de fora que o ponto de entrada responde, **apaga o cluster** e repete tudo uma segunda vez. Se a primeira volta passar por acaso (algo que já estava ali, um cache, uma espera que bastou), a segunda a entrega, porque parte do zero outra vez.

```bash
#!/usr/bin/env bash
# probar-levantar.sh — comprueba levantar.sh en un clúster NUEVO curso-k8s-l10, con
# un kubeconfig temporal propio, y borra el clúster al terminar. Dos vueltas: crear,
# levantar, borrar, recrear y levantar otra vez (meta 1 del curso).
#
# Uso, desde esta carpeta:   ./probar-levantar.sh
# Variables opcionales:
#   RED_DOCKER   red de Docker donde viven los nodos (por omisión «kind»). Si usas
#                otra, el rango de overlays/kind/metallb-pool.yaml debe caer en ella.
#   CUPO_MAXIMO  en una máquina compartida: antes de crear un clúster espera a que
#                haya menos de CUPO_MAXIMO clústeres «curso-k8s-*».
set -euo pipefail
cd "$(dirname "$0")"
CLUSTER=curso-k8s-l10
CONTEXTO="kind-$CLUSTER"
RED_DOCKER="${RED_DOCKER:-kind}"
CURL_IMAGEN='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
L10_TMP="$(mktemp -d /tmp/curso-k8s-l10.XXXX)"
export KUBECONFIG="$L10_TMP/kubeconfig"

limpiar() {
  if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
    kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1 || true
  fi
  rm -f base/token.txt
  case "$L10_TMP" in /tmp/curso-k8s-l10.?*) rm -rf -- "$L10_TMP" ;; esac
  return 0
}
trap limpiar EXIT

if kind get clusters 2>/dev/null | grep -qx -- "$CLUSTER"; then
  echo "ALTO: ya existe un clúster llamado «$CLUSTER»; este guion no lo toca." >&2; exit 1
fi

crear() {
  if [ -n "${CUPO_MAXIMO:-}" ]; then
    until [ "$(kind get clusters 2>/dev/null | grep -c '^curso-k8s-' || true)" -lt "$CUPO_MAXIMO" ]; do
      echo "(espera de cupo: ya hay $CUPO_MAXIMO clústeres de curso; reviso en 60 s)"; sleep 60
    done
  fi
  if [ "$RED_DOCKER" = kind ]; then
    kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  else
    KIND_EXPERIMENTAL_DOCKER_NETWORK="$RED_DOCKER" \
      kind create cluster --name "$CLUSTER" --config kind-curso.yaml --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  fi
  [ "$(kubectl config current-context)" = "$CONTEXTO" ] || { echo "ALTO: contexto equivocado" >&2; exit 1; }
  kubectl wait --for=condition=Ready nodes --all --timeout=240s >/dev/null
  kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name "$CLUSTER" >/dev/null 2>&1
}

for vuelta in 1 2; do
  printf '\n## Vuelta %s: clúster recién creado\n' "$vuelta"
  t0=$SECONDS; crear; echo "(crear el clúster y cargar las imágenes tardó $((SECONDS - t0)) s)"
  t0=$SECONDS
  printf '\n$ ./levantar.sh %s\n' "$CONTEXTO"
  ./levantar.sh "$CONTEXTO" 2>&1
  echo "(levantar.sh tardó $((SECONDS - t0)) s)"
  IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
  printf '\n$ curl -s http://%s/salud   # desde un contenedor fuera del clúster\n' "$IP_GW"
  docker run --rm --network "$RED_DOCKER" "$CURL_IMAGEN" -s -m 5 "http://$IP_GW/salud"; echo
  rm -f base/token.txt
  kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null 2>&1
  echo "(clúster borrado)"
done
```

As partes que não são da subida já são conhecidas: o `kubeconfig` temporário, o `trap limpiar EXIT` que **apaga o cluster mesmo que o script falhe pela metade** (um `trap … EXIT` é executado ao sair do script, seja por terminar ou por um erro), e a verificação de que `curso-k8s-l10` ainda não exista antes de criá-lo. O `limpiar` só apaga um cluster chamado exatamente `curso-k8s-l10`, e a pasta temporária só se o caminho começar com `/tmp/curso-k8s-l10.` (o `case` de sempre).

O que é novo é o `CUPO_MAXIMO`. É para máquinas compartilhadas, e a execução desta lição o usou: antes de criar um cluster, espera que haja menos desse número de clusters `curso-k8s-*` vivos. Sem a variável, não espera. Na máquina de quem acompanha, sozinha, não é necessária.

O `probar-levantar.sh` usa o seu próprio `base/token.txt` (o `levantar.sh` o gera se não existir) e **o apaga ao terminar**: se já houver um, guarde-o antes ou deixe que seja regenerado.

A saída completa da prova, com as duas voltas:

```text
## Vuelta 1: clúster recién creado
(crear el clúster y cargar las imágenes tardó 39 s)

$ ./levantar.sh kind-curso-k8s-l10
== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?
primer IP del rango: 172.30.255.200 · IP del nodo de control: 172.30.0.4
== 1. Plataforma
objetos aplicados: 76
(paso 1 terminó a los 5 s)
== 2. Esperar a la plataforma
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
deployment.apps/controller condition met
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out
deployment.apps/envoy-gateway condition met
deployment.apps/metrics-server condition met
(paso 2 terminó a los 234 s)
== 3. Proyecto
objetos aplicados: 28
deployment.apps/revisor condition met
deployment.apps/prueba condition met
gateway.gateway.networking.k8s.io/revisor condition met
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.30.255.200   True         22s
(paso 3 terminó a los 256 s)
(levantar.sh tardó 256 s)

$ curl -s http://172.30.255.200/salud   # desde un contenedor fuera del clúster
{"estado":"vivo","version":"1.6.0"}

(clúster borrado)

## Vuelta 2: clúster recién creado
(crear el clúster y cargar las imágenes tardó 35 s)

$ ./levantar.sh kind-curso-k8s-l10
== 0. La red: ¿el rango de MetalLB cae dentro de la red de los nodos?
primer IP del rango: 172.30.255.200 · IP del nodo de control: 172.30.0.3
== 1. Plataforma
objetos aplicados: 76
(paso 1 terminó a los 4 s)
== 2. Esperar a la plataforma
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
deployment.apps/controller condition met
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out
deployment.apps/envoy-gateway condition met
deployment.apps/metrics-server condition met
(paso 2 terminó a los 250 s)
== 3. Proyecto
objetos aplicados: 28
deployment.apps/revisor condition met
deployment.apps/prueba condition met
gateway.gateway.networking.k8s.io/revisor condition met
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.30.255.200   True         61s
(paso 3 terminó a los 315 s)
(levantar.sh tardó 315 s)

$ curl -s http://172.30.255.200/salud   # desde un contenedor fuera del clúster
{"estado":"vivo","version":"1.6.0"}

(clúster borrado)
(la corrida completa tardó 1755 s)
```

As duas voltas dizem o mesmo, e é isso o que se queria provar. O passo 0 confirma que a faixa começa em `172.30.255.200` e que o nó de controle está em `172.30.0.x` (o IP do nó muda de uma volta para outra: `.4` e `.3`; o único que importa é a rede). O passo 1 aplica **76** objetos em uns 5 segundos. O passo 2 é o que dura: do segundo 5 ao 234 na primeira volta e do 4 ao 250 na segunda (marcas acumuladas desde que o script iniciou), isto é, **quase toda a subida é esperar** que os nós baixem imagens e iniciem a plataforma. O passo 3 aplica **28** objetos e espera: 22 segundos na primeira volta e 65 na segunda (o Gateway marcava 22 s e 61 s de idade no final: `AGE` é a idade do objeto quando o `get` foi feito, não o tempo até `Programmed`). Cada “paso N terminó a los X s” é o tempo acumulado desde que o script iniciou, não a duração do passo. O `levantar.sh` levou 256 e 315 segundos. Nas duas voltas o ponto de entrada tomou `172.30.255.200`, o `curl` de fora respondeu `{"estado":"vivo","version":"1.6.0"}`, e o cluster foi apagado. Que a segunda volta, partindo do zero outra vez, passe igual é a **meta 1** do curso: reconstruir sem corrigir nada manualmente.

#### 10.6.4 Como ficaria em um *pipeline*

Não é preciso um *pipeline* para esta lição, mas convém saber como ele se conectaria, porque é o uso para o qual o script foi pensado. Uma etapa de *pipeline* de qualquer ferramenta se reduz a quatro coisas, e o `levantar.sh` já tem todas:

1. **Uma entrada explícita.** O contexto (`kind-curso-k8s-l10`) é um argumento, não uma suposição. Em um *pipeline* real seria o cluster ao qual aquela etapa tem credenciais.
2. **Credenciais mínimas.** Este script cria CRDs e *webhooks*, que são objetos do cluster inteiro, então precisa de permissões de administrador do cluster. Em um ambiente real não se dá a um *pipeline* a conta do administrador de tudo: dá-se a ele uma conta própria (RBAC, Lição 7) com as permissões justas para o que instala. No `kind` não há duas contas, então o curso não pratica isso, mas o nomeia.
3. **Um código de saída honesto.** 0 se tudo terminou, diferente de 0 se não. É a única informação que o *pipeline* lê.
4. **Uma saída que possa ser lida depois.** Os três cabeçalhos `== 1.`, `== 2.`, `== 3.`, as contagens e os segundos por passo são o que alguém lê às 7h50 de uma segunda-feira quando o passo 2 ficou vermelho.

E o que o script não deve se tornar: um lugar onde se acumulem remendos. Se um passo quebrar por uma causa nova, conserta-se a causa, não se acrescenta um `sleep`.

### 10.7 A revisão final contra `restricted`

#### 10.7.1 O que o `restricted` pede, em concreto

A Lição 2 colocou o `securityContext` no primeiro Deployment; a 7 colocou o nível `restricted` no namespace. Agora é preciso conferir, com o cluster e não de memória, que **tudo** o que está no namespace `revisor` o cumpre. Primeiro, o que ele exige. Os *Pod Security Standards* ([documentação](https://kubernetes.io/docs/concepts/security/pod-security-standards/)) definem três níveis; `restricted` é o mais estrito e soma seis controles aos do `baseline`:

| Controle do `restricted` | O que exige (campo e valor permitido) | Onde o projeto o cumpre |
|---|---|---|
| Tipos de volume | cada volume é de um tipo permitido: `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected` ou `secret` | `emptyDir` e `secret` no `revisor`; `persistentVolumeClaim` e `secret` no `CronJob` |
| Escalada de privilégios | `allowPrivilegeEscalation: false` em cada contêiner | o `securityContext` de cada contêiner, nos dois Deployments (`revisor` e `prueba`) e no `CronJob` |
| Executar como não-`root` | `runAsNonRoot: true` (no Pod ou em cada contêiner) | o `securityContext` do Pod |
| Usuário não-`root` | `runAsUser` diferente de 0, ou indefinido | 65532 no `revisor` e `prueba`; 100 no `CronJob` |
| *Seccomp* | `seccompProfile.type` explícito: `RuntimeDefault` ou `Localhost`; nem `Unconfined` nem ausente | `RuntimeDefault`, no `securityContext` do Pod |
| Capacidades | `capabilities.drop` inclui `ALL`; só se pode voltar a adicionar `NET_BIND_SERVICE` | `drop: ["ALL"]` em cada contêiner |

(Os controles do `baseline` que o `restricted` herda —sem contêineres privilegiados, sem rede do host, sem `hostPath`, sem portas do host, entre outros— são cumpridos porque nenhum manifesto do projeto pede nada disso.)

E agora, o que o **`restricted` não pede** e o projeto faz de qualquer maneira, para não confundir com a norma:

- `readOnlyRootFilesystem: true`. Nenhum dos três níveis o exige. O projeto o coloca porque um sistema de arquivos que não pode ser escrito limita o que um atacante faria dentro do contêiner, e por isso o `revisor` guarda o seu relatório em um volume e não em `/`.
- `requests` e `limits` (Lição 5), `automountServiceAccountToken: false` (Lição 7), o `Secret` marcado como imutável e montado como arquivo (Lição 4), a rede fechada (Lição 7). São decisões do projeto, não controles do `restricted`.

Distinguir as duas listas importa: “cumpre o `restricted`” é um fato que o cluster pode confirmar com uma consulta (a seção seguinte), e “segue as práticas do curso” é um juízo de quem avalia.

#### 10.7.2 Como o cluster aplica isso

O nível não é ensinado a cada Pod: é dito ao **namespace**, com rótulos (*labels*). Isto é o que leva o `base/namespace.yaml`:

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

A [documentação do *Pod Security Admission*](https://kubernetes.io/docs/concepts/security/pod-security-admission/) define três **modos**, cada um com o seu rótulo: `enforce` (a violação **rejeita** o Pod), `audit` (a violação deixa uma anotação no registro de auditoria, mas é permitida) e `warn` (a violação produz um aviso para quem aplicou, mas é permitida). Cada modo tem ainda um rótulo `…-version` que fixa a política que acompanhava uma versão do Kubernetes, aqui a v1.37, para que uma atualização do cluster não mude as regras por baixo sem que ninguém decida.

Um detalhe que explica o que se verá na seção 10.7.4: segundo a mesma documentação, os modos `audit` e `warn` se aplicam também aos objetos que *criam* Pods (Deployments, Jobs, CronJobs), “para ajudar a detectar violações cedo”, mas o `enforce` **não** se aplica a esses objetos, só aos Pods resultantes. Dito com um exemplo: um Deployment que não cumpre é *aceito* (com aviso), e os Pods que ele tenta criar são *rejeitados*. O Deployment fica existindo com zero réplicas, e por isso é preciso ler os avisos do `apply` e não confiar em que “aplicou bem”.

#### 10.7.3 A revisão no cluster

Primeiro, a consulta que a [documentação](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) recomenda antes de mudar um nível: `kubectl label --dry-run=server --overwrite`. A documentação explica que, quando um rótulo `enforce` (ou a sua versão) é **adicionado ou mudado**, o controlador de admissão testa cada Pod do namespace contra a política nova e devolve as violações como avisos, e que com `--dry-run=server` esse teste roda sem aplicar nada. Tudo depende de “adicionado ou mudado”. O primeiro que se escreve sobre o `revisor`, que já tem `enforce=restricted`, **não muda nada**, e por isso (foi medido, mais abaixo) não revisa nenhum Pod:

```text
$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)

$ kubectl get namespace revisor --show-labels
NAME      STATUS   AGE   LABELS
revisor   Active   83s   kubernetes.io/metadata.name=revisor,pod-security.kubernetes.io/audit-version=v1.37,pod-security.kubernetes.io/audit=restricted,pod-security.kubernetes.io/enforce-version=v1.37,pod-security.kubernetes.io/enforce=restricted,pod-security.kubernetes.io/warn-version=v1.37,pod-security.kubernetes.io/warn=restricted
```

`namespace/revisor not labeled (server dry run)` diz uma única coisa: o rótulo já era esse e não houve nada a mudar. **Não revisou nenhum Pod**, então não é evidência de que o projeto cumpre; com qualquer Pod dentro teria dito o mesmo. Na segunda saída estão os seis rótulos dos três modos, cada um com a sua versão `v1.37`, mais o que o Kubernetes coloca sozinho (`kubernetes.io/metadata.name`).

**A consulta que revisa o que já existe.** Se o nível e a versão se repetem, o servidor não avalia; se a política **muda**, avalia. Então, para auditar um namespace que já está em `restricted:v1.37`, pede-se uma política distinta, sem aplicá-la: o mesmo rótulo de versão com outro valor, por exemplo `enforce-version=v1.36`. O servidor testa cada Pod contra o `restricted` dessa versão (não da v1.37: é uma vizinha, não a mesma) e informa. Como uma ausência de avisos não vale sem um controle, o `psa-comprobacion.sh` o prova primeiro em um namespace de teste, `psa-control`, com dois Pods: `viola` (não diz nada de segurança) e `cumple` (cumpre os seis controles do `restricted`). Coloca-se `restricted:v1.37` de verdade e repetem-se as duas consultas. Isto foi rodado em um cluster `curso-k8s-l10` de três nós com o projeto aplicado (o namespace `revisor`) mas sem a plataforma, que esta prova não precisa:

```text
## El control: un espacio con un Pod que viola y otro que cumple

$ kubectl apply -f psa-control.yaml
namespace/psa-control created
pod/viola created
pod/cumple created

$ kubectl get pods -n psa-control
NAME     READY   STATUS    RESTARTS   AGE
cumple   1/1     Running   0          1s
viola    1/1     Running   0          1s

## Se le pone restricted de verdad: el servidor sí avisa, porque el nivel CAMBIA

$ kubectl label --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
Warning: existing pods in namespace "psa-control" violate the new PodSecurity enforce level "restricted:v1.37"
Warning: viola: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/psa-control labeled

## La consulta de antes: repetir el nivel que el espacio ya tiene

$ kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
namespace/psa-control not labeled (server dry run)

## La consulta que sí revisa: pedir otra versión de la política

$ kubectl label --dry-run=server --overwrite namespace psa-control pod-security.kubernetes.io/enforce-version=v1.36
Warning: existing pods in namespace "psa-control" violate the new PodSecurity enforce level "restricted:v1.36"
Warning: viola: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/psa-control labeled (server dry run)

## Lo mismo sobre el espacio del proyecto

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/enforce-version=v1.37
namespace/revisor not labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce-version=v1.36
namespace/revisor labeled (server dry run)

$ kubectl get pods -n revisor --no-headers | wc -l
       4
```

Leia de cima para baixo. Ao colocar `restricted` de verdade, o servidor avisa e nomeia **`viola`** (com os quatro controles que descumpre) e não `cumple`. Repetir o mesmo nível e a mesma versão sobre o `psa-control` diz `not labeled`, **com um Pod que viola dentro**: essa é a consulta que não revisa. Pedir `v1.36` sim avisa, e só de `viola`: a consulta revisa, e distingue. Com o controle à vista, o resultado sobre o `revisor` vale: repetir o nível diz `not labeled` (sem informação) e pedir `v1.36` diz `labeled (server dry run)` **sem um único aviso** sobre os 4 Pods do namespace (os dois do `revisor`, o de `prueba` e o que o `CronJob` deixou). Isso sim é “o servidor revisou os Pods do `revisor` e nenhum descumpre o `restricted`”.

Uma ausência de avisos só vale se se sabe que a ferramenta os daria; essa verificação (o controle acima, e o Deployment `malo` da seção 10.7.5) já está feita. Além disso, a prova campo por campo: a tabela da seção 10.7.1, mas lida dos Pods vivos do namespace (o jsonpath pede, por Pod, os campos que o `restricted` examina):

```text
$ kubectl get pods -n revisor -o jsonpath='{range .items[*]}{.metadata.name}{" noroot="}{.spec.securityContext.runAsNonRoot}{" seccomp="}{.spec.securityContext.seccompProfile.type}{" priv-esc="}{.spec.containers[0].securityContext.allowPrivilegeEscalation}{" drop="}{.spec.containers[0].securityContext.capabilities.drop}{" ro="}{.spec.containers[0].securityContext.readOnlyRootFilesystem}{" automount="}{.spec.automountServiceAccountToken}{"\n"}{end}'
prueba-6899c74865-rzh88 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-6m6s6 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-dq4pp noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
```

Três Pods, três linhas idênticas: os dois do `revisor` e o de `prueba` (se o `CronJob` já tiver disparado, apareceria um quarto, com os mesmos valores). Em cada um: `noroot=true` (o Pod roda como não-`root`), `seccomp=RuntimeDefault`, `priv-esc=false`, `drop=["ALL"]`, e além disso `ro=true` e `automount=false`, que são do curso e não do `restricted`. Pediu-se apenas o primeiro contêiner (`containers[0]`), e cada um desses Pods tem um só. Esta consulta não substitui o `dry-run` (que revisa todos os controles, não só os que foram escritos no `jsonpath`); ela o complementa: permite *ver* os valores.

#### 10.7.4 Parte da plataforma não cumpre o `restricted`, e está certo (com uma condição)

O namespace `revisor` é o único com os rótulos. O que o servidor diria se eles fossem colocados nos namespaces da plataforma? Pergunta-se com a mesma consulta, sem mudar nada (`cut` corta cada linha para que caiba). Aqui a consulta revisa os Pods, porque esses namespaces não têm o rótulo e colocá-lo é uma mudança. Outra diferença em relação à consulta anterior: esses namespaces não têm um rótulo de versão, então o servidor compara contra a versão mais recente da política (`restricted:latest`) e diz isso no primeiro aviso:

```text
$ kubectl label --dry-run=server --overwrite namespace envoy-gateway-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
namespace/envoy-gateway-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace metallb-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
Warning: existing pods in namespace "metallb-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: controller-76f4cf76b7-kclm8: unrestricted capabilities, seccompProfile
Warning: speaker-cbfnt (and 2 other pods): host namespaces, hostPort, probe or lifecycle host, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/metallb-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted 2>&1 | cut -c1-300
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: coredns-559f6c778d-9fhdt (and 1 other pod): runAsNonRoot != true, seccompProfile
Warning: etcd-curso-k8s-l10-control-plane (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
Warning: kindnet-6qh25 (and 2 other pods): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: kube-proxy-6rwpd (and 2 other pods): host namespaces, privileged, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
namespace/kube-system labeled (server dry run)
```

Três namespaces, três respostas distintas:

- **`envoy-gateway-system`: sem avisos.** Diz “labeled (server dry run)” e nada mais. Os Pods do Envoy Gateway (o controlador e os Envoy que atendem o ponto de entrada) cumprem o `restricted`. É um dado que convém saber e que não é óbvio: nem toda a plataforma pede privilégios.
- **`metallb-system`: sim.** O `controller` viola dois controles: “unrestricted capabilities” (conserva capacidades do Linux que o `restricted` obriga a retirar) e “seccompProfile” (não declara perfil). Os três `speaker` violam mais: “host namespaces” e “hostPort” (compartilham a rede do nó), “probe or lifecycle host”, “runAsNonRoot != true” e as mesmas capacidades e perfil. O `speaker` é o que responde às perguntas ARP da rede (a camada 2 da seção 10.10, ponto 5) e, para isso, precisa ver a rede do nó e não uma rede própria: o aviso “host namespaces” é o nome técnico dessa necessidade.
- **`kube-system`: sim, e muito.** Os dois `coredns` violam `runAsNonRoot` e o perfil `seccomp`. Os quatro Pods do plano de controle (`etcd` e seus três companheiros) compartilham a rede do host e montam caminhos do nó (os “restricted volume types”). `kindnet` e `kube-proxy` compartilham a rede do host e conservam capacidades, e o `kube-proxy` ainda roda como `privileged`.

(O “(and 2 other pods)” é do servidor: agrupa os Pods que violam o mesmo para não repetir a linha.)

Isso não é um defeito do curso: é o que acontece quando uma peça de infraestrutura precisa de privilégios para fazer o seu trabalho (falar com a rede dos nós, anunciar endereços, montar caminhos do nó). O ponto é duplo. Primeiro, **os privilégios existem e estão em algum lugar**: a plataforma os concentra nos seus próprios namespaces, e o projeto, que é o que muda todos os dias, vive sem eles. Segundo, esses namespaces têm uma **condição**: ninguém mais deve poder criar Pods ali, porque quem puder criar um Pod em `metallb-system` ou `kube-system` tem, de fato, os privilégios desse namespace. Em um cluster real, isso se resolve com RBAC (quem pode criar o quê, onde) e com um nível `baseline` ou `privileged` *declarado* para cada namespace de plataforma —uma decisão escrita, com dono—, não com um namespace sem rótulo. Aqui eles não são rotulados, e a seção 10.10 anota isso.

#### 10.7.5 O controle positivo: um Deployment que viola o `restricted` de verdade

Para saber que “nem um aviso” significa algo, prova-se com um Deployment que **deve** produzi-los. `fig10_02.deployment-malo.yaml` é um **programa que falha de propósito**: um Deployment que não diz nada de segurança.

```yaml
# fig10_02.deployment-malo.yaml — FALLA A PROPÓSITO: un Deployment que NO cumple el
# nivel «restricted». No dice nada de seguridad: ni usuario, ni capacidades, ni
# perfil seccomp. En el espacio «revisor» el clúster avisa al aplicarlo y rechaza
# sus Pods. Se aplica con:  kubectl apply -n revisor -f fig10_02.deployment-malo.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: malo
  labels:
    app: malo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: malo
  template:
    metadata:
      labels:
        app: malo
    spec:
      containers:
      - name: malo
        image: curso-docker-prueba:1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 9000
```

```text
$ kubectl apply -n revisor -f fig10_02.deployment-malo.yaml
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "malo" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/malo created

$ kubectl get deployment malo -n revisor
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
malo   0/1     0            0           8s

$ kubectl get events -n revisor --field-selector reason=FailedCreate -o custom-columns=RAZON:.reason,MENSAJE:.message | cut -c1-400 | head -3
RAZON          MENSAJE
FailedCreate   Error creating: pods "malo-89fb7566-9zgxl" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonR
FailedCreate   Error creating: pods "malo-89fb7566-wps2l" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "malo" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "malo" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "malo" must set securityContext.runAsNonR
```

Três coisas, nesta ordem. **Ao aplicar**, um `Warning` com quatro controles violados: `allowPrivilegeEscalation != false`, `unrestricted capabilities`, `runAsNonRoot != true` e `seccompProfile`, cada um com o campo exato que falta (`container "malo" must set securityContext.allowPrivilegeEscalation=false`…). E embaixo, `deployment.apps/malo created`: o Deployment **foi** criado. Segundo, o Deployment está em `READY 0/1`: não tem nenhum Pod. Terceiro, os eventos do ReplicaSet: `FailedCreate`, “Error creating: pods "malo-…" is forbidden: violates PodSecurity "restricted:v1.37"”, com a mesma lista. Ali atuou o modo `enforce`, e vê-se que ele o fez ao criar os Pods, não o Deployment.

Isto é o que a seção 10.7.2 anunciava: o Deployment *é aceito* (com avisos, pelo modo `warn`) e os Pods *são rejeitados* (pelo modo `enforce`); o ReplicaSet registra cada rejeição como um evento `FailedCreate`. E é a razão de ler a saída do `apply`. Apaga-se:

```text
$ kubectl delete -n revisor -f fig10_02.deployment-malo.yaml
deployment.apps "malo" deleted from revisor namespace
```

Com isso, a afirmação do projeto fica de pé com um controle: o projeto não produz avisos (contagem 0 na seção 10.5.3), e um Deployment que viola a política **sim** os produz. O Exercício 2 pede para consertar este.

### 10.8 Provar as metas

O README do curso termina com sete metas: não “as lições foram lidas”, mas “o projeto cumpre isto”. Esta seção confere no cluster as que podem ser medidas. Antes, o mapa, para saber onde está cada uma:

| Meta | O que diz | Onde se confere |
|---|---|---|
| 1 | a partir de um cluster recém-criado, o projeto fica funcionando em três passos, e se reconstrói depois de apagado | 10.5 (manualmente) e 10.6 (com o script, duas voltas) |
| 2 | o namespace está em `restricted` e não há avisos ao aplicar | 10.5.3 e 10.7 |
| 3 | um nó de trabalho é parado e o serviço continua respondendo, com uma janela medida | 10.8.3 |
| 4 | mudar a lista de serviços faz o *rollout* sozinho | 10.8.1 |
| 5 | com carga, o escalonamento sobe e desce réplicas | medido na Lição 9; a seção 10.8.4 confere que continua conectado |
| 6 | um Pod alheio não fala com o `revisor`, e a conta do `revisor` não pode nada | 10.8.2 |
| 7 | sabe-se dizer, por escrito, cinco motivos pelos quais isto não é produção | 10.10 e o Exercício 4 |

#### 10.8.1 Meta 4: mudar a lista muda as réplicas, sem tocar na imagem

É a Lição 4 vista do final: a configuração vive fora da imagem. Primeiro, o estado antes da mudança: o ReplicaSet que tem as réplicas e o `ConfigMap` gerado com o seu *hash*.

```text
$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-654b5d75dc   2         2         2       92s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      92s
revisor-config-t6cm6872fk   1      92s
```

Muda-se o tempo limite do serviço de teste de `2s` para `1s` na base. `sed -i.bak` edita o arquivo no lugar e deixa uma cópia com a extensão `.bak` (a forma que funciona igual no Linux e no macOS); `diff` compara a cópia com o arquivo novo para que se veja exatamente o que mudou:

```text
$ sed -i.bak 's#http://prueba:9000/ 2s#http://prueba:9000/ 1s#' base/kustomization.yaml; diff base/kustomization.yaml.bak base/kustomization.yaml
29c29
<   - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s
---
>   - REVISOR_SERVICIOS=prueba http://prueba:9000/ 1s
[código de salida: 1]
```

```bash
ctx && kubectl apply --server-side -k overlays/kind
```

Aqui o comando filtra as duas linhas que importam:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-cmb662hmbh serverside-applied
deployment.apps/revisor serverside-applied
```

Restaura-se o arquivo (o `.bak` volta ao seu nome) e espera-se que o *rollout* termine:

```text
$ mv base/kustomization.yaml.bak base/kustomization.yaml && grep REVISOR_SERVICIOS base/kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-548956488d   2         2         2       5s
revisor-654b5d75dc   0         0         0       97s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      97s
revisor-config-cmb662hmbh   1      5s
revisor-config-t6cm6872fk   1      97s
```

O que mudou: o `diff` mostra uma única linha, `2s` por `1s`. O `apply` aplicou dois objetos: um `ConfigMap` **novo**, `revisor-config-cmb662hmbh` (outro *hash*, porque o conteúdo é outro), e o Deployment, que o gerador reescreveu para apontar para ele. O *rollout* criou um ReplicaSet novo com as duas réplicas e deixou o velho em `0 0 0`. E o que não mudou: a imagem. `curso-docker-revisor:1.6.0` não foi reconstruída, não foi carregada de novo e não foi tocada. O `ConfigMap` velho continua no cluster, sem que ninguém o use: é o preço da Lição 4. `kube-root-ca.crt` não é do projeto: o Kubernetes o cria em cada namespace.

E como o arquivo volta a dizer `2s`, o cluster também precisa voltar. **O arquivo é a verdade**: se o cluster e os arquivos diferem, corrige-se o cluster aplicando de novo, não se anota “já sei que está diferente”:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-t6cm6872fk serverside-applied
deployment.apps/revisor serverside-applied

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-548956488d   0         0         0       11s
revisor-654b5d75dc   2         2         2       103s
```

Ao voltar ao arquivo original, o `ConfigMap` que se aplica é outra vez `revisor-config-t6cm6872fk`, o de antes. Como o modelo do Pod volta a ser idêntico ao do primeiro ReplicaSet, o Deployment **o reutiliza**: sobe o velho de 0 para 2 e baixa o que acabava de criar, em vez de montar um terceiro. Ficam dois ReplicaSets, um ativo e um em `0 0 0`; esses ReplicaSets vazios são o que o `rollout undo` usa para voltar (Lição 9).

#### 10.8.2 Meta 6: a rede e as permissões

Duas provas pequenas, no namespace `revisor`: um Pod **com** o rótulo `acceso-revisor: permitido` (`depurar`) e outro **sem** ele (`intruso`). Os dois são Pods de `curl` que já cumprem o `restricted`, então o cluster os aceita:

```bash
ctx && kubectl apply -n revisor -f depurar.yaml -f intruso.yaml
ctx && kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso --timeout=180s
```

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

O primeiro é o controle positivo: sem ele, o segundo não provaria nada, porque um `curl` que falha pode falhar por mil razões. O `depurar` chega (a rede deixa), o `intruso` não. A leitura do código é a chave. O `curl` sai com **28** (*operation timed out*): passaram os 3 segundos do `-m 3` sem resposta. Se a rede rejeitasse a conexão, o `curl` sairia com 7 (“não consegui conectar”), como na Lição 3. Uma `NetworkPolicy` que não deixa passar um pacote **o descarta sem responder**, e o cliente fica esperando: por isso o 28 é a marca de uma rede fechada e não de um serviço fora do ar.

E as permissões das contas, com `kubectl auth can-i`, que pergunta ao cluster se uma identidade poderia fazer algo, sem fazê-lo:

```text
$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador
yes

$ kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]
```

Quatro respostas, e uma tabela as resume: a conta `revisor` **não** pode ler Pods nem Secrets (`no`, `no`); a conta `observador` **pode** ler Pods (`yes`) e **não** pode apagá-los (`no`). O código de saída do `can-i` é 1 quando a resposta é `no`, e por isso o script anota `[código de salida: 1]` sem que haja nenhuma falha. A conta do `revisor` nem sequer tem credenciais montadas (`automountServiceAccountToken: false`), então a resposta é dupla: não pode, e ainda que pudesse, o Pod não tem com que chamar a API.

#### 10.8.3 Meta 3: um nó é parado e o serviço continua respondendo

Esta é a prova mais próxima do que acontece em um cluster real, e a que mais ensina. Um nó de trabalho é um contêiner Docker; pará-lo com `docker stop` se parece com a máquina desligar de repente. Quer-se saber três coisas: o serviço continua respondendo? Algo falha enquanto isso? Quanto dura?

**Antes de prever, os números do cluster.** A [documentação do estado dos nós](https://kubernetes.io/docs/reference/node/node-status/) descreve o mecanismo: cada `kubelet` renova o objeto `Lease` do seu nó **a cada 10 segundos** (esse é o latido, ou *heartbeat*), o controlador de nós revisa os latidos **a cada 5 segundos** (`node-monitor-period`), e a condição `Ready` passa a `Unknown` se em `node-monitor-grace-period` não soube nada do nó: **50 segundos por padrão** (também como valor padrão na [referência do `kube-controller-manager`](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)). Os 50 segundos são contados a partir do **último latido que o controlador recebeu**, não do `docker stop`: esse latido pode ter chegado até 10 segundos antes de o nó ser parado, e o controlador só percebe na revisão seguinte (até 5 segundos depois). Feita a soma, o cluster fica sabendo entre uns 40 e uns 55 segundos depois do `docker stop`; como o ciclo de medição começa alguns segundos mais tarde, pelo relógio dele a janela cai alguns segundos antes. Enquanto o prazo não se cumpre, o cluster *não sabe* que o nó se foi. E a [documentação de *taints* e tolerâncias](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) diz que, quando o nó já é `Unknown`, os Pods não são removidos de imediato: por padrão toleram o *taint* de “nó inalcançável” durante **300 segundos** (`tolerationSeconds`), e só então são repostos em outro nó.

A previsão, então: com duas réplicas (uma por nó de trabalho), ao parar um nó, **em média a metade das requisições** deveria falhar enquanto dura essa janela (dezenas de segundos). A [documentação de Services](https://kubernetes.io/docs/reference/networking/virtual-ips/) diz que, nos modos `iptables` e `nftables`, o `kube-proxy` instala regras que por padrão escolhem o Pod de destino **ao acaso**: não é um rodízio estrito, então com umas 25 requisições a proporção real pode se afastar da metade. Enquanto isso, um endereço já não responde e o cluster ainda não sabe. Passada a janela, a réplica morta sai da lista de endereços e tudo deveria passar.

O experimento. Um detalhe antes: a prova do *rollout* da seção 10.8.1 acabou de substituir os Pods, e os velhos levam alguns segundos para desaparecer. Para não medir com Pods que estão indo embora, espera-se que fiquem só os dois vigentes (outro ciclo com teto, como o do escalonamento):

```bash
for _ in $(seq 1 60); do
  [ "$(kubectl get pods -n revisor -l app=revisor --no-headers | wc -l | tr -d ' ')" = 2 ] && break
  sleep 2
done
```

E agora sim, onde estão as réplicas, para não parar o nó do Pod que faz de cliente:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          15s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          17s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

Escolhe-se como vítima um nó de trabalho que não seja o do `depurar` (o cliente que vai medir de dentro do cluster), e para-se o seu contêiner. A vítima sai de uma lista de nós de trabalho menos o do cliente; a lição usa o `case` já conhecido para não parar nada que não seja deste cluster:

```bash
NODO_DEPURAR="$(kubectl get pod -n revisor depurar -o jsonpath='{.spec.nodeName}')"
VICTIMA="$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o name | sed 's#node/##' | grep -vx "$NODO_DEPURAR" | head -1)"
case "$VICTIMA" in curso-k8s-l10-*) ;; *) echo "ALTO: «$VICTIMA» no es un nodo de este clúster"; false ;; esac
docker stop "$VICTIMA"
```

```text
$ docker stop curso-k8s-l10-worker2
curso-k8s-l10-worker2
```

E o cliente: um ciclo dentro do `depurar` que faz uma requisição a cada 2 segundos durante 90, com um limite de 2 segundos cada uma, e só imprime quando o resultado **muda** (uma linha por mudança, não uma por requisição):

```bash
ctx && kubectl exec -n revisor depurar -- sh -c 'inicio=$(date +%s); ok=0; mal=0; ant=""; while [ $(( $(date +%s) - inicio )) -lt 90 ]; do t=$(( $(date +%s) - inicio )); if curl -s -m 2 -o /dev/null http://revisor/salud; then r=ok; ok=$((ok+1)); else r=FALLA; mal=$((mal+1)); fi; [ "$r" != "$ant" ] && echo "[+${t}s] $r"; ant=$r; sleep 2; done; echo "bien=$ok mal=$mal"'
```

(O ciclo está escrito entre aspas simples para que o `$(…)` seja interpretado pelo `sh` de *dentro* do Pod e não pelo da máquina de quem acompanha. `date +%s` dá os segundos desde 1970; a subtração com `inicio` é o tempo decorrido; `curl -m 2` desiste aos 2 segundos.)

```text
[+0s] FALLA
[+4s] ok
[+6s] FALLA
[+22s] ok
[+31s] FALLA
[+51s] ok
bien=24 mal=10
```

Leia como uma linha do tempo (as linhas são *mudanças*, não requisições). Começa falhando (`[+0s] FALLA`), volta a responder aos 4 segundos, falha de novo aos 6 e não responde até o 22; responde até o 31, falha outra vez até o 51, e **a partir do segundo 51 tudo responde** até o final dos 90. Ao terminar: `bien=24 mal=10`, 34 requisições, e as 10 falhas caíram todas antes do segundo 51. Isso coincide com o mecanismo acima: o cluster demorou o que demoram os seus latidos e o seu prazo para perceber. Com o que não coincide à perfeição é com o “alternado”: há trechos de vários segundos seguidos falhando, não uma falha e um acerto por vez. É o que diz a documentação de Services: o destino é escolhido **ao acaso** em cada conexão, então de vez em quando saem várias seguidas para o endereço morto. (Cada requisição que falha custa além disso 2 segundos de limite, por isso na janela cabem menos requisições do que durante o resto da prova.) Tampouco convém tomar o 51 como uma constante: nas outras três execuções de preparação da lição (guardadas em `programas/10-proyecto-final/corridas-preparacion/`), o serviço voltou a responder sem falhar aos 36, 50 e 34 segundos. As quatro janelas, de 34 a 51 segundos, são o que o mecanismo prevê: dependem de quão velho era o último latido quando o nó foi parado (de 0 a 10 segundos), da revisão do controlador (a cada 5) e dos segundos que passam entre o `docker stop` e a primeira tentativa do ciclo. A [Lição 9](09-escalar-y-actualizar.md) (9.12.2) mediu o mesmo mecanismo por outro ângulo: o nó passou a `NotReady` aos 57 segundos de desligado. O que se mantém de uma execução para outra é a ordem de grandeza: dezenas de segundos, não minutos.

E o estado do cluster nesse instante, **antes** de subir o nó de novo:

```text
$ kubectl get nodes
NAME                          STATUS     ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready      control-plane   6m46s   v1.37.0
curso-k8s-l10-worker          Ready      <none>          6m35s   v1.37.0
curso-k8s-l10-worker2         NotReady   <none>          6m34s   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          106s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          108s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>

$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]}{" listo="}{.conditions.ready}{"\n"}{end}'
10.244.1.7 listo=true
10.244.2.7 listo=false
```

Três dados que parecem se contradizer e não se contradizem. O nó `curso-k8s-l10-worker2` está `NotReady`: o cluster já o deu por perdido. Mas o Pod que vive nele continua aparecendo como `1/1 Running`: o cluster continuará listando-o até esgotar os 300 segundos de tolerância, e só então o reporá em outro nó. E o `EndpointSlice` do Service já marca o endereço desse Pod (`10.244.2.7`) com `listo=false`: **deixou de receber tráfego** ainda que a lista de Pods ainda o mostre. A lição prática é que `READY 1/1` no `kubectl get pods` e “recebe tráfego” não são a mesma coisa; para saber se um Pod recebe requisições olha-se o `EndpointSlice` (Lição 3).

Sobe-se o nó e espera-se que volte:

```text
$ docker start curso-k8s-l10-worker2
curso-k8s-l10-worker2

$ kubectl wait --for=condition=Ready node/curso-k8s-l10-worker2 --timeout=180s
node/curso-k8s-l10-worker2 condition met

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready    control-plane   6m48s   v1.37.0
curso-k8s-l10-worker          Ready    <none>          6m37s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          6m36s   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          108s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          110s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

A mudança do contador de reinícios demora a aparecer. Olhe o contador um momento depois de o nó voltar a `Ready` (acima, `RESTARTS`), espere que ele registre o reinício com outro ciclo com teto e olhe de novo:

```bash
for _ in $(seq 1 36); do
  [ "$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | grep -vc '^0$')" -ge 1 ] && break
  sleep 5
done
```

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS     AGE    IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   1 (7s ago)   113s   10.244.2.5   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0            115s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>

$ kubectl get pods -n revisor -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name}{" reinicios="}{.status.containerStatuses[0].restartCount}{" último fin: "}{.status.containerStatuses[0].lastState.terminated.reason}{" código "}{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}{end}'
revisor-654b5d75dc-qcqfz reinicios=1 último fin: Unknown código 255
revisor-654b5d75dc-xmvc5 reinicios=0 último fin:  código 
```

O nó volta a `Ready`, e a primeira lista de Pods engana: continua dizendo `RESTARTS 0` e o IP de antes (`10.244.2.7`). Alguns segundos depois, o contador sim muda: o Pod `…-qcqfz` diz `1 (7s ago)` e, além disso, **tem outro IP**: `10.244.2.5`. É o mesmo Pod, com o mesmo nome, mas o seu contêiner reiniciou e o seu endereço mudou. A consulta de `lastState` explica: o último fim do contêiner foi de razão `Unknown` e código `255`, isto é, não o matou nenhuma *probe* nem um `OOMKilled`; desapareceu com o seu nó, que foi desligado inteiro, e ninguém pôde registrar um código de saída normal. A outra réplica, a do nó que nunca foi parado, ficou em zero reinícios. Duas consequências: um contador de reinícios diferente de zero **nem sempre** quer dizer que algo falhou no programa (aqui foi o nó), e um IP de Pod não se guarda para depois, que é a Lição 3 outra vez.

**O que reduz essa janela e o que não reduz.** Com o que foi medido, a resposta honesta:

- **Mais réplicas, distribuídas entre mais nós.** Se em vez de duas houver seis distribuídas em três nós, parar um afeta uma parte menor das requisições. É o que o escalonamento e a distribuição da Lição 9 já fazem: não encurtam o tempo, reduzem a porção.
- **Novas tentativas no cliente.** Uma requisição que falha e é repetida cai, com boa probabilidade, na outra réplica. O cliente desta prova não repete de propósito, para que se veja o efeito cru; um real deveria repetir.
- **Um `node-monitor-grace-period` mais curto**, no plano de controle, que encurta a janela em troca de mais alarmes falsos (um nó com um tropeço de rede de alguns segundos seria dado por perdido). Em um cluster gerenciado, pede-se ao provedor; no `kind`, não se muda nesta lição.

E o que **não** a encurta, ainda que pareça:

- **As *probes*.** Quem as roda é o `kubelet` do próprio nó, que é justamente o que deixou de existir. Uma *probe* não pode reportar a falta do programa que a executa.
- **`tolerationSeconds`.** Decide em quanto tempo os Pods são *repostos* em outro nó, não quando deixam de receber tráfego. Encurtá-lo repõe antes, mas o tráfego continuaria indo para o endereço morto até que o nó seja dado por perdido.

Uma frase que vale como resumo: o cluster tolera que um nó caia, **não que caia sem que ninguém perceba durante dezenas de segundos**. Essa é a diferença entre “sobrevive” e “sem interrupções”, e por isso a meta do curso diz “com uma janela medida”.

#### 10.8.4 Meta 5: o escalonamento continua conectado

Medir quanto o escalonamento demora para subir e para descer com carga ocupa 15 minutos e uma lição inteira: é a Lição 9, e não se repete aqui. O que se confere é que, no cluster subido do zero, ele **continua conectado às métricas**:

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          3m32s
```

Nesta execução, logo depois de reiniciar o nó, o escalonamento disse `cpu: <unknown>/50%`: perdeu a leitura das métricas. Não se investigou em que nó roda o `metrics-server` nem por que foi interrompido; o medido é que um nó reiniciado deixou o escalonamento sem dados por um tempo. (Em outras execuções de preparação da lição isso não aconteceu: já trazia a porcentagem.) É um exemplo de por que o `<unknown>` não se interpreta sem olhar o que acabou de acontecer no cluster.

Se em outro cluster disser `<unknown>`, não é preciso se alarmar ainda: é a causa da Lição 9 e se resolve esperando, mas com teto. O mesmo ciclo da seção 10.5.3, que confere a cada 5 segundos por até três minutos:

```bash
for _ in $(seq 1 36); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: 3%/50%   2         6         2          4m33s
```

O ciclo esperou e o escalonamento se recuperou sozinho: `cpu: 3%/50%`, `MINPODS 2`, `MAXPODS 6` e duas réplicas. Entre os dois `get` passou pouco mais de um minuto (a coluna `AGE` vai de 3m32s a 4m33s). Com isso, a meta 5 fica conferida no que esta lição pode conferir: o escalonamento está conectado às métricas e os seus limites são os da base. Subir e descer réplicas com carga é a Lição 9.

E se o ciclo desistir e continuar dizendo `<unknown>`, a outra causa vista na Lição 9 é o `metrics-server` sem a flag `--kubelet-insecure-tls` (que o `kind` necessita).

### 10.9 Helm, em uma menção

Há uma ferramenta que se verá em quase qualquer projeto de Kubernetes e que este curso não usa: o **Helm**. A [documentação do Helm](https://helm.sh/docs/intro/using_helm/) o chama de gerenciador de pacotes para o Kubernetes. Quatro palavras que convém reconhecer: um **chart** é um pacote (uma pasta de modelos de manifestos mais os seus valores padrão); os **values** são os valores que se mudam para a instalação em questão; uma **release** é uma instalação concreta de um chart em um cluster; e um **repositório** (ou um registro de imagens OCI) é onde eles são publicados.

O exemplo está no guia do Envoy Gateway que já é conhecido. Além de instalá-lo com o `install.yaml` que o curso usa, [esse guia](https://gateway.envoyproxy.io/docs/install/install-helm/) o instala com o Helm assim (o comando é o do guia para a versão v1.9.2; **não foi rodado nesta lição**):

```text
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.9.2 -n envoy-gateway-system --create-namespace
```

`eg` é o nome da *release*, `oci://docker.io/envoyproxy/gateway-helm` é o chart e `--version` fixa a sua versão, com `--create-namespace` para criar o namespace onde é instalado.

Por que o curso usa Kustomize e não Helm? Porque compara duas ideias distintas, e para aprender convém ver primeiro a mais simples:

| | Kustomize | Helm |
|---|---|---|
| Ideia | parte de YAML completo e **o muda** com camadas | parte de **modelos** com lacunas e as **preenche** com valores |
| O que se lê | YAML normal; o que se vê é o que se aplica | modelos com lógica; para ver o resultado, `helm template` |
| Mudanças entre ambientes | overlays e *patches* | arquivos de valores (`values`) |
| O que mais faz | nada: monta e entrega ao `kubectl` | mantém o histórico de *releases*, atualiza e pode voltar a uma versão anterior |
| Vem com o `kubectl` | sim (`kubectl kustomize`, `apply -k`) | não: é um programa à parte |

Uma regra prática muito usada, que aqui é uma opinião e não uma norma: **Kustomize para o que é da casa, Helm para o que é de fora.** O que é próprio é YAML escrito por quem o usa e que se quer ler; o que é de fora (MetalLB, Envoy Gateway, um monitoramento) costuma ser publicado como chart com dezenas de opções que outra pessoa já pensou. Muitas equipes usam os dois: instalam a plataforma com o Helm e o projeto com o Kustomize.

E o problema desta lição existe também ali. As [práticas recomendadas do Helm sobre CRDs](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) dizem que os CRDs de um chart são instalados primeiro (vivem em uma pasta especial, `crds/`), que **o Helm não os atualiza nem os apaga** pelo perigo de perder dados, e que se um chart precisa usar os tipos que ele mesmo define, o mais cômodo é separá-los em dois charts instalados separadamente. É a mesma ordem —tipos, controlador, projeto— com outro nome.

### 10.10 O que muda em um cluster real

#### 10.10.1 O que se construiu e o que falta

Há uma tentação ao terminar um curso: acreditar que o que funciona na máquina de quem estuda está “quase” pronto para rodar de verdade. Esta seção existe para desarmá-la com honestidade, sem dramatismo. O `kind` faz bem o que promete: provar que se **entende** o Kubernetes. A própria página dele diz que foi “projetado principalmente para testar o próprio Kubernetes”, embora possa ser usado para desenvolvimento local ou integração contínua. Não promete um cluster que aguente o que um serviço real exige. A [documentação do Kubernetes sobre ambientes de produção](https://kubernetes.io/docs/setup/production-environment/) abre com uma frase que resume a diferença (traduzido): um ambiente de produção típico “tem mais requisitos que um ambiente pessoal de aprendizado, desenvolvimento ou testes”.

A lista a seguir tem catorze itens. Não é preciso lembrar de todos; é preciso reconhecer o padrão: quase todos são uma peça que **no `kind` existe em versão de laboratório** e em um cluster real precisa ser substituída, reforçada ou acrescentada. Cada um diz o que o curso faz, o que um cluster real exige, o que se faria, e de onde sai.

**1. Um plano de controle de um só nó.** O curso tem um nó de controle. Se ele parar, não se pode mudar nada, e o que mais deixa de funcionar não é certo: no Exercício 3, os contêineres já iniciados continuaram rodando, mas o ponto de entrada só continuou respondendo em 1 de 4 execuções. Um cluster real replica o plano de controle em vários nós e balanceia a carga para o servidor da API; a [documentação de ambientes de produção](https://kubernetes.io/docs/setup/production-environment/) enumera justamente essas peças, e lembra que um ambiente de uma só máquina “tem um único ponto de falha”. Muitas equipes preferem um plano de controle gerenciado por um provedor.

**2. Um `etcd` sem backup testado.** Todo o estado do cluster —os objetos aplicados— vive no `etcd`. Se ele se perde, o cluster se perde. O [guia de operação do `etcd`](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) ensina como tirar uma cópia com `etcdctl snapshot save` e como verificá-la com `etcdutl snapshot status`. E aqui volta o caso do GitLab da abertura: o backup que não foi restaurado em um ensaio não é um backup. Ele é agendado, e é **restaurado de verdade** em um cluster de testes com uma periodicidade que alguém decida.

**3. Segredos guardados sem criptografia.** Viu-se na Lição 4: um `Secret` é base64, e dentro do `etcd` é guardado em texto claro, a menos que o administrador configure a criptografia em repouso. O [guia de criptografia de dados em repouso](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) explica como se configura no `kube-apiserver`, e a [lista de verificação de segurança](https://kubernetes.io/docs/concepts/security/security-checklist/) a pede: “a criptografia em repouso está configurada para a API de Secrets”. Para segredos que não deveriam viver no cluster, a mesma lista menciona injetá-los a partir de um armazenamento externo.

**4. HTTP em texto puro.** O ponto de entrada do `revisor` fala HTTP na porta 80, e o token viaja em um cabeçalho sem criptografia (a Lição 6 mediu isso). Um cluster real termina o TLS no *Gateway*: o [guia de TLS da Gateway API](https://gateway-api.sigs.k8s.io/guides/tls/) descreve como um *listener* HTTPS termina a criptografia com um certificado. Além disso, é preciso emiti-lo e renová-lo, e a lista de segurança pergunta pela criptografia dentro do cluster (que depende do CNI ou de uma malha de serviços).

**5. Um endereço que o MetalLB distribui em uma rede Docker.** Em camada 2, a [documentação do MetalLB](https://metallb.io/concepts/layer2/) diz: todo o tráfego de um IP vai para **um único nó**, e dali o `kube-proxy` o distribui. “Nesse sentido, a camada 2 não implementa um balanceador de carga: implementa um mecanismo de *failover*.” Seus dois limites são um gargalo em um nó e uma comutação potencialmente lenta. Na nuvem, o balanceador é do provedor; em um data center próprio costuma-se usar o MetalLB em modo BGP ou outro balanceador.

**6. `metrics-server` com `--kubelet-insecure-tls`.** Viu-se na seção 10.3.4: “apenas para testes”, diz o próprio README. Em um cluster real os certificados dos `kubelet` são assinados com a autoridade do cluster e a flag sobra. O README acrescenta algo que importa: o `metrics-server` é **apenas** para o escalonamento automático; para monitoramento usa-se outra coisa.

**7. Nós que são contêineres na máquina.** Os três “nós” compartilham o processador, a memória, o disco e o kernel da máquina. Se o computador desliga, desliga tudo; não há zonas de disponibilidade nem data centers distintos. Um cluster real distribui nós entre zonas e distribui as réplicas entre elas (o *patch* de `ejemplo-nube` da seção 10.3.3 muda justamente isso, de nós para zonas), e tem mais de um de cada coisa que importe.

**8. Armazenamento que vive no nó.** O volume do relatório é um diretório do disco de um nó (`local-path`, Lição 8): se o nó se vai, os dados também. Um cluster real usa armazenamento externo com replicação e cópias, e os dados têm a mesma história de backup que o `etcd`: há cópia, e há um ensaio de restauração.

**9. Imagens carregadas manualmente.** As duas imagens do curso chegaram com `kind load docker-image`, com um *tag* local. Um cluster real as baixa de um registro. A [lista de segurança](https://kubernetes.io/docs/concepts/security/security-checklist/) pede referir-se a elas **pelo *digest* `sha256`** (porque um *tag* pode ser movido no registro), revisá-las com um scanner de vulnerabilidades e verificar a sua assinatura com um controlador de admissão. O curso já fixa o *digest* da imagem do `curl`; as do `revisor` e a de teste, que são locais, não.

**10. Um só administrador e nenhuma identidade.** O `kubeconfig` do `kind` é de administrador total; ninguém mais entra. Um cluster real tem usuários e grupos com permissões distintas, um provedor de identidade e uma revisão periódica de acessos. A lista de segurança pede, por exemplo, que o grupo `system:masters` não seja usado para autenticar pessoas nem componentes depois da inicialização, e uma revisão de acessos “a cada 24 meses, no máximo”.

**11. Observabilidade que é `kubectl logs`.** Há registro enquanto o Pod existe. A [documentação de *logging*](https://kubernetes.io/docs/concepts/cluster-administration/logging/) explica com clareza (traduzido): se um contêiner cai, um Pod é removido ou um nó morre, quer-se continuar vendo os logs deles; por isso devem ter um armazenamento “com um ciclo de vida independente dos nós, dos Pods e dos contêineres”, e o Kubernetes “não fornece uma solução nativa” para isso. Falta também a parte de métricas históricas e alertas: alguém que avise antes que a diretoria descubra.

**12. Atualizações sem plano.** O cluster do curso é criado e apagado; um real é atualizado com o serviço em execução, durante anos. A [política de versões suportadas](https://kubernetes.io/releases/version-skew-policy/) diz que o projeto mantém as três versões menores mais recentes (hoje 1.37, 1.36 e 1.35), com cerca de um ano de correções, e fixa quanta diferença pode haver entre componentes (um `kubelet` pode ficar até três versões menores atrás do servidor da API, nunca à frente). E cada peça da plataforma tem a sua própria ordem de atualização: o guia do Envoy Gateway pede atualizar primeiro os CRDs da Gateway API, e avisa do que acontece se isso não for feito.

**13. Sem cotas nem limites por equipe.** A Lição 5 colocou `requests` e `limits` em cada contêiner, mas nada impede que alguém crie cem Pods. A [documentação de cotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/) descreve o `ResourceQuota`: restrições ao consumo total **por namespace**, e à quantidade de objetos de cada tipo. Com várias equipes em um cluster, é o que evita que uma devore o que é das demais.

**14. Uma plataforma sem dono nem nível de segurança declarado.** A seção 10.7.4 mostrou: os namespaces do MetalLB e do `kube-system` não cumprem `restricted` (o do Envoy Gateway sim), e aqui nenhum dos três tem rótulo nem responsável. Em um cluster real, cada namespace de plataforma tem um nível declarado e uma equipe responsável, e os *webhooks* dessa plataforma são uma **dependência do cluster**: como a `failurePolicy` padrão é `Fail` (seção 10.4.1), se o Pod do guardião estiver fora do ar, não se podem criar os objetos que ele vigia. Por isso se dá a eles mais de uma réplica e são vigiados como qualquer serviço crítico.

Nada disso torna inútil o que se construiu. Pelo contrário: o projeto desta lição, a base, com todos os seus objetos, **é** o que se levaria a um cluster real. O que muda é a camada de baixo —o overlay e a plataforma—, e essa é justamente a camada que o Kustomize separa.

#### 10.10.2 Os catorze, em uma tabela

| # | No curso | Em um cluster real |
|---|---|---|
| 1 | um nó de controle | vários nós de controle, ou um gerenciado |
| 2 | `etcd` sem backup | cópias do `etcd` com ensaios de restauração |
| 3 | `Secret` sem criptografia no `etcd` | criptografia em repouso e/ou armazenamento externo de segredos |
| 4 | HTTP na porta 80 | TLS terminado no Gateway |
| 5 | MetalLB em camada 2 sobre uma rede Docker | balanceador do provedor, ou MetalLB com BGP |
| 6 | `--kubelet-insecure-tls` | certificados de `kubelet` assinados pelo cluster |
| 7 | nós que são contêineres | nós em várias zonas, com réplicas distribuídas entre elas |
| 8 | volume no disco de um nó | armazenamento externo replicado, com cópias |
| 9 | imagens carregadas manualmente | registro, *digest* `sha256`, scanner e assinatura |
| 10 | um administrador | identidades, grupos, revisão de acessos |
| 11 | `kubectl logs` | logs e métricas com armazenamento próprio e alertas |
| 12 | cluster descartável | plano de atualização por versão |
| 13 | sem cotas | `ResourceQuota` por namespace |
| 14 | plataforma sem nível declarado | nível e dono por namespace, e réplicas para os *webhooks* |

Se fosse preciso ordenar esta lista por “o que preocuparia primeiro”, não há uma resposta única: depende do que se perde se falhar. Mas um critério razoável é começar pelo que **não se pode reconstruir**. O projeto pode ser reconstruído (acabou de ser feito, duas vezes); os dados do relatório e o estado do `etcd` não. Por isso o backup com restauração testada (o 2 e o 8) costuma vir antes de quase tudo o mais, e a criptografia e o TLS (o 3 e o 4) vão junto ao que é exposto. O Exercício 4 pede justamente isso.

## O erro que a gente vai ver

Esta lição tem três erros de propósito, e já foram vistos na sua seção: a plataforma aplicada sem `--server-side` (seção 10.4.3), a plataforma e o projeto juntos em um único comando (seção 10.4.4) e um Deployment que viola o `restricted` (seção 10.7.5). Os três têm algo em comum que convém dizer com todas as letras, porque é o que de fato se aprende: **nenhum é um erro do cluster**. O cluster fez exatamente o que lhe foi pedido e disse claramente por que não podia. O que mudou entre a tentativa que falhou e a que deu certo foi *a ordem ou a forma de pedir*, não o cluster.

A ordem para ler qualquer um deles é a mesma das lições anteriores, agora com as ferramentas desta:

1. O que diz o **código de saída** do `apply` e que linhas **não** são um `created` ou um `serverside-applied`? Ali está a mensagem.
2. A mensagem menciona um **tipo que não existe** (`no matches for kind`, `ensure CRDs are installed first`) ou um **guardião que não atende** (`failed calling webhook`)? Então falta esperar a plataforma: uma espera por condição, não uma nova tentativa.
3. Menciona um **tamanho** ou um **conflito de gestor** (`Too long`, `conflict`)? Então é da forma de aplicar: `--server-side`.
4. É um **aviso** (`Warning: would violate PodSecurity`)? O objeto foi aceito e não vai funcionar: corrija o manifesto.

E antes de mudar qualquer coisa, aplicar o mesmo comando uma segunda vez para “ver se passa” **não é um diagnóstico**: a seção 10.4.4 mostrou que às vezes passa pela metade e deixa o pior, um estado que parece saudável e não é.

## O hábito de segurança da lição: revisa-se contra a norma, e diz-se o que falta

A tabela de hábitos do curso atribui a esta lição duas coisas: a revisão final contra o nível `restricted` e a lista do que um cluster real exige. As duas são hábitos de **não confiar no que parece**.

**A revisão com controle.** Uma consulta que diz “sem avisos” não vale nada por si só, porque uma ferramenta que não revisa e uma que revisa e não encontra nada dizem a mesma coisa. Por isso a seção 10.5.3 conta os avisos (`grep -ci warning`), a 10.7.5 aplica um Deployment que **deve** produzi-los e a 10.7.3 prova a consulta de revisão em um namespace com um Pod que viola: a primeira consulta escrita sobre o `revisor` dava zero avisos e não revisava nada, e foi esse controle que mostrou isso. Se o segundo caso não tivesse produzido avisos, o primeiro não teria significado nada. É o mesmo princípio com o qual se mede qualquer coisa: antes de acreditar em um zero, mostre-lhe algo que deveria contar.

**A lista do que falta.** É o segundo hábito e o mais incômodo: escrever o que *não* se tem. Um projeto que diz “cumpre o `restricted`” e cala que o seu `etcd` não tem backup passa uma ideia falsa de quão protegido está. A lista da seção 10.10 não é uma desculpa; é o documento que permite a quem toma decisões saber que risco corre.

**O que ela protege e o que não.** A revisão contra o `restricted` protege contra uma configuração descuidada: um contêiner que inicia como `root`, que pode ganhar privilégios ou que conserva capacidades de que não precisa. Não protege contra uma vulnerabilidade dentro do programa do `revisor`, contra um token que vaza, nem contra uma imagem adulterada no caminho. E a lista da seção 10.10 diz o que mais faria falta, mas não o instala: nomear uma falta não é resolvê-la.

## O que se faz errado

**Tentar de novo até passar.** É o ciclo `until kubectl apply …; do sleep 5; done`. Esconde a causa, às vezes deixa um estado pela metade, e no dia em que falha de verdade fica dando voltas em silêncio. Espera-se a condição, com teto.

**Um `sleep` fixo entre a plataforma e o projeto.** Funciona na máquina de quem escreve e falha em uma mais lenta ou mais carregada. Um `sleep` mede o relógio; o `kubectl wait` mede a condição.

**Juntar plataforma e projeto em um único `kustomization`.** Parece mais organizado e quebra a ordem (seção 10.4.4). As duas metades têm condições de saída distintas, e por isso são comandos distintos.

**Aplicar a plataforma sem `--server-side`.** Os CRDs grandes não cabem na anotação que o cliente guarda (seção 10.4.3). O guia oficial do Envoy Gateway já traz a flag.

**Um overlay que copia a base.** Se os arquivos da base são copiados para a pasta do overlay “para mudar uma linha deles”, há duas cópias que vão se separar. Um overlay aponta (`resources: ../../base`) e aplica *patches*.

**Um script que usa “o cluster ativo”.** Instala coisas no contexto que estiver à mão, que pode não ser o certo. O contexto esperado é passado como argumento e conferido antes de cada passo.

**`|| true` para que nada pare.** Um script que não para diante de um erro não avisa que houve um. Se uma falha é aceitável, trata-se esse caso e diz-se qual é.

**Dizer “sem erros” sem ter medido.** Ou “sem avisos” sem um caso que os produza. Uma afirmação de ausência precisa de um controle positivo.

**Versões sem fixar.** Um endereço que aponta para “a última versão” muda sozinho. Todas as peças desta lição vão com a versão no caminho, e as imagens do `curl` com o *digest*.

**Versionar o token.** É falso, mas o hábito é o que importa: o `.gitignore` e o `umask 077`.

**Aplicar o rótulo `enforce: restricted` em um namespace de plataforma sem revisá-lo.** A seção 10.7.4 mostrou: o MetalLB e o `kube-system` têm Pods que o `restricted` rejeitaria. Um `dry-run` antes do rótulo evita quebrar a rede de um cluster.

**Tomar o `kind` por um cluster real.** É a que a seção 10.10 desenvolve em catorze pontos, e a que mais custa quando se esquece.

## Exercícios

Os exercícios 1 a 3 rodam no cluster da lição, já no estado em que a seção 10.8 o deixou. Antes de cada um, o `ctx` (seção 10.1.2) deve passar. O `correr.sh` os roda igual, e a saída está em `correr.salida.txt`. **Antes** de rodar cada um, escreva no [diário de bordo](bitacora.md) o que se acha que vai acontecer. O quarto se escreve com as próprias palavras.

### Exercício 1 — Um overlay próprio

Escreva um overlay que parta do overlay de `kind` e mude **uma única coisa**: que o escalonamento automático não passe de 4 réplicas (hoje chega a 6). Sem tocar na base nem no overlay de `kind`. Antes de rodá-lo, preveja: quantas linhas do manifesto montado mudam, em relação a `overlays/kind`? Como conferir **sem aplicar** nada, e como com o cluster mas sem mudá-lo?

### Exercício 2 — De “malo” a `restricted`

`fig10_02.deployment-malo.yaml` viola o nível `restricted`. Corrija-o até que seja aplicado no namespace `revisor` **sem um único aviso** e que os seus Pods cheguem a `Available`. Antes de começar, preveja: quais são os controles que lhe faltam? Depois de corrigi-lo, que contagem de avisos se espera? Dica: a lista está na seção 10.7.1, e a prova positiva já existe desde a seção 10.7.5.

### Exercício 3 — Para-se o plano de controle

Na seção 10.8.3 um nó de trabalho foi parado. Agora pare o nó de controle (`docker stop curso-k8s-l10-control-plane`) durante um minuto. Preveja antes, e escreva: o `kubectl get nodes` responde? Os contêineres do `revisor` continuam rodando nos nós de trabalho? (Sem API, é possível perguntar ao próprio nó: `docker exec <nó> crictl ps`.) E o ponto de entrada, `http://<endereço>/salud` de fora do cluster, continua respondendo? Anote o que se vir, ainda que não coincida com a solução: o resultado nem sempre é o mesmo. Depois suba o nó, meça quanto a API demora para voltar e confira que o guardião do MetalLB responde antes de aplicar qualquer coisa. Com as medidas obtidas, explique por que o plano de controle e os nós de trabalho têm esses nomes, e o que a lista da seção 10.10 diria sobre o ponto 1. **Um aviso:** na máquina de quem acompanha, o nó de controle pode mudar de endereço IP ao reiniciar, se outro contêiner tomou o dele na rede Docker; se isso acontecer, o cluster deixa de funcionar e é recriado. No cluster da execução desta lição, com uma rede própria e sem outros contêineres, isso não aconteceu.

### Exercício 4 — Defenda a lista

Escolha **cinco** dos catorze pontos da seção 10.10 e, em no máximo cinco linhas por ponto: o que o projeto faz hoje, o que um cluster real exigiria e o que seria feito, em que ordem. Depois ordene-os por “o que preocuparia primeiro” e defenda o primeiro lugar em três frases: o que se perde se falhar, e dá para reconstruir?

## Soluções

### Solução 1

O overlay é `fig10_03.overlay-mio/kustomization.yaml`:

```yaml
# fig10_03.overlay-mio/kustomization.yaml — solución del Ejercicio 1: un overlay
# propio que parte del overlay de kind y cambia UNA cosa (el máximo de réplicas del
# HPA, de 6 a 4) sin tocar la base. Se comprueba con:
#   kubectl kustomize fig10_03.overlay-mio
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../overlays/kind
patches:
- target:
    kind: HorizontalPodAutoscaler
    name: revisor
  patch: |-
    - op: replace
      path: /spec/maxReplicas
      value: 4
```

Medido em `correr.salida.txt`:

```text
$ kubectl kustomize fig10_03.overlay-mio | grep -n -E 'maxReplicas|minReplicas'
391:  maxReplicas: 4
399:  minReplicas: 2

$ kubectl diff --server-side -k fig10_03.overlay-mio | grep -E '^[+-] +(max|min)Replicas'
-  maxReplicas: 6
+  maxReplicas: 4
[código de salida: 1]

$ grep -c maxReplicas base/escalado.yaml
1
```

Uma única linha muda. O `kubectl kustomize` imprime o resultado sem tocar em nada: `maxReplicas: 4` na linha 391, e `minReplicas: 2` intacto na 399. Com o cluster, `kubectl diff --server-side` compara o que seria aplicado com o que existe e mostra exatamente `-  maxReplicas: 6` e `+  maxReplicas: 4`; o `[código de salida: 1]` é o do `kubectl diff` quando **há** diferenças (0 se não há). E a prova de que a base não foi tocada: `base/escalado.yaml` continua tendo a sua única linha `maxReplicas`. Para aplicá-lo bastaria `kubectl apply --server-side -k fig10_03.overlay-mio`; o exercício não pede isso para que o cluster continue sendo o que os arquivos da lição dizem.

### Solução 2

A correção é `fig10_04.deployment-corregido.yaml`: o mesmo Deployment com `automountServiceAccountToken: false`, o `securityContext` do Pod (não-`root`, usuário 65532, *seccomp* `RuntimeDefault`) e o do contêiner (sem escalada de privilégios, sistema de arquivos somente leitura, sem capacidades), mais piso e teto de recursos.

```yaml
# fig10_04.deployment-corregido.yaml — solución del Ejercicio 2: el mismo Deployment
# de fig10_02.deployment-malo.yaml, ahora con todo lo que pide el nivel «restricted»
# (y lo que el curso pide además: sin credenciales de la API, sistema de archivos
# de solo lectura, piso y techo de recursos).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: malo
  labels:
    app: malo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: malo
  template:
    metadata:
      labels:
        app: malo
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: malo
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
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Medido em `correr.salida.txt`:

```text
$ kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml 2>&1 | grep -ci warning
0
[código de salida: 1]

$ kubectl apply -n revisor -f fig10_04.deployment-corregido.yaml
deployment.apps/malo unchanged

$ kubectl get deployment malo -n revisor
NAME   READY   UP-TO-DATE   AVAILABLE   AGE
malo   1/1     1            1           2s

$ kubectl delete -n revisor -f fig10_04.deployment-corregido.yaml
deployment.apps "malo" deleted from revisor namespace
```

A contagem de avisos dá **0**. Esse comando já aplicou o Deployment (o `grep` só conta o que o `apply` imprime), e por isso o segundo `apply` diz `unchanged`: não havia nada a mudar. O Deployment chega a `1/1` e a `Available`, então os Pods já não são rejeitados. Cada controle tem o seu campo: `allowPrivilegeEscalation: false` e `capabilities.drop: ["ALL"]` no contêiner; `runAsNonRoot: true` (com `runAsUser: 65532`) e `seccompProfile.type: RuntimeDefault` no Pod. O resto —`readOnlyRootFilesystem`, `automountServiceAccountToken: false`, piso e teto— não é pedido pelo `restricted`; é pedido pelo curso.

### Solução 3

Medido em `correr.salida.txt`:

```text
$ kubectl get servicel2statuses -n metallb-system
NAME       ALLOCATED NODE          SERVICE NAME                     SERVICE NAMESPACE
l2-pkb9d   curso-k8s-l10-worker2   envoy-revisor-revisor-b269644b   envoy-gateway-system

# el Pod revisor-654b5d75dc-qcqfz vive en curso-k8s-l10-worker2 con la IP 10.244.2.5

$ docker stop curso-k8s-l10-control-plane
curso-k8s-l10-control-plane

$ kubectl get nodes --request-timeout=5s 2>&1 | cut -c1-200
The connection to the server 127.0.0.1:64201 was refused - did you specify the right host or port?
[código de salida: 1]

# una petición cada 2 s durante 45 s a la puerta, desde fuera del clúster (se muestran los cambios)
[+0s] ok
bien=23 mal=0

# sin API, pero con acceso al nodo: ¿los contenedores siguen corriendo y contestando?

$ docker exec curso-k8s-l10-worker2 crictl ps | grep -E 'CONTAINER|revisor'
CONTAINER           IMAGE               CREATED              STATE               NAME                ATTEMPT             POD ID              POD                                               NAMESPACE
05a1aec248153       a25150a910b03       2 minutes ago        Running             shutdown-manager    1                   50c0eb8926152       envoy-revisor-revisor-b269644b-867f46cd7d-vsnj9   envoy-gateway-system
1edc39ddbcac7       370bbc1c75d75       2 minutes ago        Running             envoy               1                   50c0eb8926152       envoy-revisor-revisor-b269644b-867f46cd7d-vsnj9   envoy-gateway-system
515dc19d2f9d1       70e09194319be       2 minutes ago        Running             revisor             1                   6515939e5a0b1       revisor-654b5d75dc-qcqfz                          revisor

$ docker exec curso-k8s-l10-worker2 curl -s -m 3 http://10.244.2.5:8080/salud
{"estado":"vivo","version":"1.6.0"}

$ docker start curso-k8s-l10-control-plane
curso-k8s-l10-control-plane
(la API volvió a contestar 59 s después de detener el nodo de control)

$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l10-control-plane condition met
node/curso-k8s-l10-worker condition met
node/curso-k8s-l10-worker2 condition met

$ kubectl get nodes
NAME                          STATUS   ROLES           AGE     VERSION
curso-k8s-l10-control-plane   Ready    control-plane   9m8s    v1.37.0
curso-k8s-l10-worker          Ready    <none>          8m57s   v1.37.0
curso-k8s-l10-worker2         Ready    <none>          8m56s   v1.37.0

$ kubectl get servicel2statuses -n metallb-system
NAME       ALLOCATED NODE          SERVICE NAME                     SERVICE NAMESPACE
l2-pkb9d   curso-k8s-l10-worker2   envoy-revisor-revisor-b269644b   envoy-gateway-system

$ kubectl get pods -n revisor -o wide
NAME                       READY   STATUS      RESTARTS        AGE     IP            NODE                    NOMINATED NODE   READINESS GATES
depurar                    1/1     Running     0               4m4s    10.244.1.9    curso-k8s-l10-worker    <none>           <none>
intruso                    1/1     Running     0               4m4s    10.244.1.10   curso-k8s-l10-worker    <none>           <none>
prueba-6899c74865-rzh88    1/1     Running     0               5m47s   10.244.1.4    curso-k8s-l10-worker    <none>           <none>
reporte-29877095-rwc6k     0/1     Completed   0               4m7s    10.244.1.11   curso-k8s-l10-worker    <none>           <none>
revisor-654b5d75dc-qcqfz   1/1     Running     1 (2m22s ago)   4m8s    10.244.2.5    curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running     0               4m10s   10.244.1.7    curso-k8s-l10-worker    <none>           <none>

# ¿contesta ya el guardián (webhook) de MetalLB? Una prueba en seco del rango, sin aplicar nada

$ kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300
Warning: resource ipaddresspools/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation w
ipaddresspool.metallb.io/curso configured (server dry run)
Warning: resource l2advertisements/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation
l2advertisement.metallb.io/curso configured (server dry run)

# espera (hasta 3 minutos) a que el guardián de MetalLB conteste

$ kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml 2>&1 | cut -c1-300
Warning: resource ipaddresspools/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation w
ipaddresspool.metallb.io/curso configured (server dry run)
Warning: resource l2advertisements/curso is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation
l2advertisement.metallb.io/curso configured (server dry run)
```

Leia em ordem. **A API não responde**: o `kubectl` fica com `connection … was refused` contra `127.0.0.1` (a porta que o `kind` publica do nó de controle). Sem o plano de controle não se pode ver, criar, mudar nem apagar nada. **Os contêineres continuaram vivos** nas duas execuções em que isso foi conferido (a 5 de preparação e a da lição): sem API, mas com acesso ao nó, o `crictl ps` lista rodando o `revisor` e os dois contêineres do Envoy, e um `curl` do nó ao IP do Pod responde `{"estado":"vivo","version":"1.6.0"}`. Isso diz que os contêineres não se desligam sozinhos; não diz que o serviço chegue a quem o pede. **O ponto de entrada**, nesta execução, respondeu as 23 requisições (`bien=23 mal=0`) durante os 45 segundos. E aqui vai um aviso que foi medido e não foi explicado: em **três execuções de preparação** desta mesma lição (guardadas em `programas/10-proyecto-final/corridas-preparacion/`: `corrida1.txt`, `corrida4.txt` e `corrida5.txt`), com o mesmo exercício, o ponto de entrada não respondeu nenhuma das requisições enquanto o plano de controle estava parado (`bien=0 mal=12`, 12 de 12 falhas, na 4 e na 5; na 1, o `curl` saiu com código 7, conexão recusada, no mesmo instante). No total, o ponto de entrada respondeu em 1 de 4 execuções, embora o `ServiceL2Status` (medido nas duas últimas) dissesse que um nó de trabalho anunciava o endereço. A causa não foi encontrada. O honesto cabe em uma frase: no `kind`, com MetalLB e Envoy Gateway, **não se deve dar por certo** que o ponto de entrada sobrevive sem plano de controle, nem tampouco o contrário: com 4 execuções não se pode dizer mais que “1 de 4”. Anote o que se vir na execução própria; pode ser diferente do desta solução. **A API voltou** 59 segundos depois de parado o nó de controle.

E uma segunda lição, da última verificação. Quando o nó de controle volta, o `kubectl wait` diz que os três nós estão `Ready`, mas isso não quer dizer que todo o resto esteja pronto. Em uma execução de preparação, o `kubectl diff` final falhou com `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connection refused`: o guardião do MetalLB ainda não respondia (seção 10.4.1, outra vez). Por isso o script pergunta ao guardião com uma prova a seco da faixa —`kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml`— e espera com teto que ele responda. Nesta execução respondeu na primeira tentativa: `ipaddresspool.metallb.io/curso configured (server dry run)`. As duas linhas `Warning` que a acompanham não são de segurança: dizem que a faixa foi criada com `--server-side` e não tem a anotação `last-applied-configuration` que o `apply` do lado do cliente usa. É a diferença da seção 10.4.2, e aqui é inofensiva porque é uma prova a seco. Depois da espera, `kubectl diff --server-side -k overlays/kind` diz `sin diferencias con los archivos`.

O que isso diz do ponto 1 da seção 10.10: um plano de controle de um só nó é um ponto único de falha: sem ele não se pode **mudar** nada e ninguém repõe nem escala; o que já está rodando pode continuar rodando (os contêineres fizeram isso) ou deixar de ser alcançável (o ponto de entrada, 3 de 4 vezes), e não se encontrou de que isso depende. E por que se chamam assim: o plano de controle **decide** (o que deve existir e onde); os nós de trabalho **executam**.

### Solução 4

Uma resposta possível, para a lista de cinco: “**(2) `etcd` sem backup**: hoje não há cópia; um cluster real agenda o `etcdctl snapshot save` e *restaura de verdade* em um cluster de testes de tempos em tempos, e eu faria isso primeiro porque é a única coisa que não posso reconstruir com `kubectl apply`. **(8) Volume no disco de um nó**: hoje o relatório vive no nó; em um real, armazenamento replicado e cópias, com a mesma prova de restauração. **(3) Segredos sem criptografia**: hoje estão em base64 dentro do `etcd`; configuraria a criptografia em repouso e, para segredos que não devam viver no cluster, um armazenamento externo. **(4) HTTP na porta 80**: terminaria o TLS no Gateway e trocaria o token, que viajou em texto puro. **(1) Plano de controle de um nó**: três nós de controle ou um plano gerenciado.” A ordem de preocupação: primeiro o que não se reconstrói (2 e 8), depois o que é exposto (3 e 4), por último a disponibilidade (1). Defesa do primeiro lugar: “Se o `etcd` sem backup falhar, perco o estado do cluster; o projeto se reconstrói com dois comandos e uma espera (provei duas vezes), mas o que o cluster sabia de si mesmo não. E um backup que nunca foi restaurado não é uma resposta: é uma hipótese.”

## Apagar o cluster

Ao terminar, apague o cluster da lição e o que foi deixado na máquina. Não deixe nada vivo:

```bash
# El clúster (con su nombre: sin --name, kind borra el llamado «kind»).
kind delete cluster --name curso-k8s-l10
kind get clusters | grep -c curso-k8s-l10    # debe decir 0
# El token de la lección: es de mentira, pero un token suelto no se deja.
rm -f -- base/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 10.1.2.
case "$L10_TMP" in
  /tmp/curso-k8s-l10.?*) rm -rf -- "$L10_TMP" ;;
  *) echo "No borro «$L10_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L10_TMP
```

```text
$ kind delete cluster --name curso-k8s-l10
Deleting cluster "curso-k8s-l10" ...
Deleted nodes: ["curso-k8s-l10-worker2" "curso-k8s-l10-control-plane" "curso-k8s-l10-worker"]

$ kind get clusters | grep -c curso-k8s-l10
0
[código de salida: 1]
```

(As linhas entre parênteses são escritas pelo script, que mede a remoção. O `grep -c` imprime `0` e sai com código 1, porque não encontrou nenhum cluster com esse nome: é a resposta que se procura.) O `case` só deixa passar um caminho que comece com `/tmp/curso-k8s-l10.` e tenha algo depois, a forma exata da que foi criada na seção 10.1.2. Se `L10_TMP` estiver vazia ou valer outra coisa, não apaga nada e diz por quê. Se o Exercício 3 foi feito em um segundo terminal, feche-o. E se foi usada uma rede Docker própria (a execução desta lição fez isso; na rede `kind`, não), apague-a **depois** do cluster e só se foi criada por quem acompanha: `docker network rm <nome>`.

Este foi o último cluster do curso. Os das lições anteriores já foram apagados, um por lição, e com isso termina o método: criar, usar, apagar, e poder criar de novo.

## Como sei que consegui

- [ ] Abro um `kustomization.yaml` e digo o que é uma base, o que é um overlay, o que ele monta e como conferir com `kubectl kustomize` sem aplicar nada.
- [ ] A partir de um cluster vazio, subo o projeto com a plataforma, uma espera por condição e o projeto, e explico por que essa ordem.
- [ ] Interpreto `no matches for kind … ensure CRDs are installed first` e a mensagem de um CRD grande demais sem `--server-side`, e digo o que as causa.
- [ ] Rodo `programas/10-proyecto-final/probar-levantar.sh` e comparo a saída com `programas/10-proyecto-final/correr.salida.txt` no que não muda entre execuções: a plataforma aplicada com `serverside-applied`; as cinco esperas com `condition met` ou `successfully rolled out`; o projeto com os seus objetos e sem uma única linha `Warning`; o Gateway `Programmed`; `{"estado":"vivo","version":"1.6.0"}` de fora, nas duas voltas; e que o cluster já não existe ao terminar. Os IPs, os sufixos dos nomes, as idades e os segundos mudam a cada execução: observam-se, não se comparam.
- [ ] Sei por que `kubectl label --dry-run=server … enforce=restricted` sobre o `revisor` (que já o tem) responde `not labeled` sem revisar nenhum Pod, e reviso os Pods existentes pedindo uma política distinta (`enforce-version=v1.36`), com o controle do namespace `psa-control` que nomeia o Pod que viola e não o que cumpre.
- [ ] Paro um nó de trabalho, meço a janela em que as requisições falham e explico por que ela dura o que dura e o que a reduz.
- [ ] Mudo a lista de serviços e vejo um `ConfigMap` novo e um ReplicaSet novo sem reconstruir a imagem.
- [ ] O `intruso` não chega ao `revisor` e o `depurar` chega; a conta `revisor` não consegue nem ler Pods.
- [ ] `kubectl get hpa` mostra uma porcentagem, não `<unknown>`.
- [ ] Escrevo, com as próprias palavras, cinco motivos pelos quais o que construí não é um cluster real, o que faria com cada um e por qual começaria.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l10`.

## Resumo

Responda sem olhar a lição:

1. O que é uma base e o que é um overlay? Uma base conhece os seus overlays?
2. Que diferença há entre uma peça de plataforma e uma de projeto, e que três coisas uma plataforma traz?
3. Que condição o `kubectl wait` espera em um CRD, e qual em um Deployment?
4. O que o `--server-side` muda e que erro evita na plataforma?
5. O que acontece se plataforma e projeto forem juntados em um único comando, e por que repeti-lo “para ver se passa” não é um método?
6. Por que um script de subida recebe o contexto como argumento e o confere antes de cada passo?
7. O que o nível `restricted` pede e o que o projeto faz além disso?
8. Por que parte da plataforma (MetalLB, `kube-system`) não cumpre o `restricted`, e que condição se impõe para que isso seja aceitável?
9. Com um nó de trabalho parado, por que as requisições falham durante dezenas de segundos e o que não encurta essa janela?
10. Quando se usaria o Helm em vez do Kustomize?
11. Nomeie cinco motivos pelos quais o cluster do curso não é um cluster real e o que faria com cada um.

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Declarative Management of Kubernetes Objects Using Kustomize”](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): bases e overlays, geradores com *hash*, `patches`, `images`, e `kubectl kustomize` / `apply -k`.
- [Kubernetes, “Server-Side Apply”](https://kubernetes.io/docs/reference/using-api/server-side-apply/): gestores de campos, conflitos, e a comparação com o `apply` do lado do cliente.
- [Kubernetes, “Custom Resources”: CustomResourceDefinition](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/): a condição `Established` de um CRD.
- [Kubernetes, “Dynamic Admission Control”](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): *webhooks* de admissão e `failurePolicy` (padrão `Fail`).
- [Kubernetes, “kubectl wait”](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): esperar uma condição em um ou vários recursos.
- [Kubernetes, “Virtual IPs and Service Proxies”](https://kubernetes.io/docs/reference/networking/virtual-ips/): que o `kube-proxy` escolhe ao acaso o Pod de destino de um Service nos modos `iptables` e `nftables`.
- [Kubernetes, “Pod Security Standards”](https://kubernetes.io/docs/concepts/security/pod-security-standards/): os controles do `baseline` e do `restricted`, campo por campo.
- [Kubernetes, “Pod Security Admission”](https://kubernetes.io/docs/concepts/security/pod-security-admission/) e [“Enforce Pod Security Standards with Namespace Labels”](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): os modos `enforce`, `audit` e `warn`, as versões fixadas, e a prova com `--dry-run=server`.
- [Kubernetes, “Node Status”](https://kubernetes.io/docs/reference/node/node-status/), [“kube-controller-manager”](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) e [“Taints and Tolerations”](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): os 50 segundos do `node-monitor-grace-period` e a tolerância de 300 segundos.
- [Kubernetes, “Production environment”](https://kubernetes.io/docs/setup/production-environment/), [“Security checklist”](https://kubernetes.io/docs/concepts/security/security-checklist/), [“Encrypting Confidential Data at Rest”](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/), [“Operating etcd clusters”](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/), [“Logging Architecture”](https://kubernetes.io/docs/concepts/cluster-administration/logging/), [“Resource Quotas”](https://kubernetes.io/docs/concepts/policy/resource-quotas/) e [“Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/): o que um cluster real exige e a política de versões.
- [kind, *issues* #4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) e [#4224](https://github.com/kubernetes-sigs/kind/issues/4224): falhas do `kind load` com Docker 29 e o armazenamento do `containerd` (o aviso da seção 10.1.2).
- [kind](https://kind.sigs.k8s.io/): para que o `kind` foi projetado. E [`provider.go` do kind v0.33.0](https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provider.go): a variável `KIND_EXPERIMENTAL_DOCKER_NETWORK`, que a execução desta lição usou.
- [Envoy Gateway, “Install with Kubernetes YAML”](https://gateway.envoyproxy.io/docs/install/install-yaml/) e [“Install with Helm”](https://gateway.envoyproxy.io/docs/install/install-helm/): a instalação com `--server-side`, a instalação com Helm e a ordem de atualização dos CRDs.
- [MetalLB, “Layer 2 mode”](https://metallb.io/concepts/layer2/): como funciona e os seus dois limites.
- [metrics-server v0.9.0, README](https://github.com/kubernetes-sigs/metrics-server/blob/v0.9.0/README.md): `--kubelet-insecure-tls` “apenas para testes”, e que é só para o escalonamento automático.
- [Gateway API, “TLS”](https://gateway-api.sigs.k8s.io/guides/tls/): terminar o TLS em um *listener*.
- [Helm, “Using Helm”](https://helm.sh/docs/intro/using_helm/) e [“Custom Resource Definitions”](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/): o que é um chart e como trata os CRDs.
- [RFC 6902, “JavaScript Object Notation (JSON) Patch”](https://www.rfc-editor.org/rfc/rfc6902.html): as operações `op: replace` dos *patches* da seção 10.3.3.
- [RFC 2606, “Reserved Top Level DNS Names”](https://www.rfc-editor.org/rfc/rfc2606.html): `example.com` reservado para exemplos.
- [GitLab, “Postmortem of database outage of January 31”](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): o relatório público do caso da abertura.

---

**Fim do curso.** Volte ao [índice](README.md) ou abra o [diário de bordo](bitacora.md) e escreva o que se quer construir depois.
