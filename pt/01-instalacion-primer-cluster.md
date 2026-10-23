# Lição 1 — Instalar kubectl e kind; o primeiro cluster

Terça-feira, 8h20 da manhã. Às dez é preciso mostrar o `revisor` rodando em um cluster, e o notebook não tem nem o `kubectl`. Busca-se “instalar kind” e o primeiro blog oferece duas linhas: um `curl` para um endereço que termina em `latest` e um `sudo mv`. Copia-se tudo. Um colega passa pelo chat “o kubectl que funciona para mim”, um arquivo sem versão nem origem. Usa-se esse também. Às 8h50, o `kind create cluster` imprime uma coluna de ✓ verdes, incluindo `✓ Joining worker nodes`. Dá para respirar. Às 9h30, o primeiro Deployment fica pela metade e descobre-se que o cluster de três nós, na verdade, tem um só. Não se sabe que versão de cada ferramenta está instalada, nem de onde saiu o binário do chat, nem por que dois nós que “se juntaram” não existem. E faltam trinta minutos.

Nada disso foi má sorte. Foram três decisões que ninguém tomou: que versão instalar, como saber se o binário é o que diz ser e que limite do sistema precisa ser aumentado antes de criar o cluster. Esta lição toma essas decisões, uma por uma, e deixa um cluster que a gente sabe criar, olhar, apagar e criar de novo em menos de meio minuto, desde que a imagem do nó já esteja no disco (na primeira vez é preciso baixá-la, e isso depende da conexão).

**Tempo:** 90 min

**O que se constrói:** o cluster do curso. Um nó de controle e dois de trabalho, criado com o `kind` a partir de um arquivo de configuração que fixa a imagem do nó pelo *digest*. Antes, o `kubectl` e o `kind` instalados com a versão fixada e a soma de verificação conferida, e o limite de `inotify` medido e ajustado. Os programas estão em [`programas/01-instalacion-primer-cluster/`](../programas/01-instalacion-primer-cluster).

**O que se aprende:** o que se instala e onde roda cada peça; por que se fixa a versão em vez de baixar “a última”; o que é uma soma de verificação (*checksum*) `sha256`, como se confere e o que fazer quando não coincide; o que é o `inotify`, como se mede e por que um cluster de três nós o esgota; o que é um `kubeconfig` e o que é um contexto; como criar, olhar, apagar e recriar o cluster, e como recuperar o contexto se ele for perdido

**De onde a gente vem.** Da [Lição 0](00-que-es-kubernetes.md) vem o mapa. Um cluster tem um plano de controle e nós de trabalho. O `kubectl` fala com o `kube-apiserver`, e com mais ninguém. O kind monta um cluster com nós que são contêineres do Docker, todos sobre o mesmo kernel da máquina. E houve dois avisos que aqui viram prática: com um limite de `inotify` de 128, um cluster de três nós não sobe mesmo que o kind diga que sim, e sem contexto o `kubectl` não sabe com quem falar. Do [curso de Docker](https://www.habil.mx/pt/cursos/docker/) vem o Docker Engine instalado no Linux Mint e o usuário no grupo `docker`.

**O que esta lição não faz.** Não implanta nada no cluster: o `revisor` chega na [Lição 2](02-pods-deployments.md). Não instala o Docker: isso foi feito na Lição 1 do curso de Docker. Não usa gerenciadores de pacotes (`apt`, `snap`, Homebrew) para o `kubectl` nem para o `kind`, e em 1.2 se diz por quê. Ainda não explica os objetos que aparecem no `kube-system`: apenas os olha.

**Sobre as execuções.** As saídas foram obtidas em 21 de outubro de 2026 em um Mac com processador ARM, com Docker Engine 29.2.1 dentro de uma máquina virtual Ubuntu 24.04.4 que o Colima sobe. **Não** no Linux Mint, que é o sistema de referência do curso. Para que se saiba de onde vem cada saída, cada uma leva um destes rótulos:

| Rótulo | O que significa |
|---|---|
| **Execução real · Mac** | Foi executado no Mac. Os binários de Linux foram baixados e o checksum foi conferido ali, em uma pasta temporária que foi apagada ao terminar. O cluster também foi criado a partir do Mac. |
| **Execução real · Ubuntu 24.04 amd64** | Foi executado em um contêiner descartável de Ubuntu 24.04 para `amd64`, a base do Linux Mint 22 em uma máquina Intel ou AMD. Ali os checksums foram conferidos com o `sha256sum` do GNU, como no Mint, e os binários foram instalados e executados. O contêiner foi apagado ao sair. |
| **Execução real · máquina virtual** | Foi executado dentro da máquina virtual do Colima, que é onde vive o kernel que o Docker usa no Mac. Ali foi medido o `inotify`. |
| **Execução real · contêiner sem privilégios** | Foi executado em um contêiner descartável que não pode alterar o kernel. Ali foram testadas as proteções do ajuste do `inotify`, sem ajustar nada. |

O que muda no Mint. Os `install` e o ajuste do `inotify` levam `sudo` e alteram o sistema de verdade (no Mac nada foi alterado). A coluna `KERNEL-VERSION` mostrará o kernel da máquina e `amd64`. Os endereços IP, a porta do servidor da API e os sufixos dos Pods serão outros. Há mais uma diferença, e ela é instrutiva. No Mac, `kind version` diz `go1.27.0 darwin/arm64`: esse `kind` foi compilado pelo Homebrew, não pelo projeto, e por isso o compilador muda. É justamente o que esta lição evita no Mint: o binário será o oficial, conferido pelo checksum, e dirá `go1.26.7 linux/amd64`, como na execução em Ubuntu de 1.3.5.

## Ao terminar, a gente vai conseguir

- Baixar o `kubectl` v1.37.1 e o `kind` v0.33.0 da origem oficial, conferir o checksum `sha256` e reconhecer a mensagem `FAILED` quando ele não coincide.
- Medir os limites de `inotify` do kernel com o `sysctl`, ajustá-los de forma persistente com um arquivo em `/etc/sysctl.d/` e explicar por que três nós do kind os esgotam.
- Criar o cluster do curso com um `kubeconfig` temporário próprio e conferir com `kubectl get nodes` que os três nós estão `Ready`, sem confiar nos ✓ verdes.
- Ler um `kubeconfig` com `kubectl config view --minify` e dizer que cluster, que usuário e que contexto ele contém.
- Conferir o contexto ativo antes de um comando e mudá-lo com `use-context` ou com `--context`.
- Apagar o cluster, recriá-lo e recuperar o contexto com `kind export kubeconfig` se ele for perdido.

## O porquê antes do como

Instalar dois programas parece a parte mais chata do curso. Não é, porque nesta lição se decide **que software roda com o usuário e com `sudo` na máquina**, e isso tem consequências.

O `kubectl` vai ter nas mãos a credencial de administrador do cluster. A Lição 0 mostrou que o usuário do kind é `kubernetes-admin`, do grupo `kubeadm:cluster-admins`. O `kind`, por outro lado, cria contêineres privilegiados no Docker. Um binário alterado de qualquer um dos dois teria acesso ao cluster inteiro e à máquina. Por isso não basta “algo que se chame `kubectl` e funcione”. Tem que ser **o** `kubectl` que o projeto Kubernetes publicou, na versão pedida. A soma de verificação é a forma de conferir isso em um segundo.

A segunda razão é a reprodutibilidade. Se duas pessoas instalam “a última”, cada uma fica com a que era a última no dia em que baixou. Dali a três meses, uma saída do curso não coincide com a da máquina de quem a executa e ninguém sabe por quê. O Kubernetes lança uma versão menor umas três vezes por ano ([kubernetes.io, “Kubernetes Release Cycle”](https://kubernetes.io/releases/release/)). Fixar a versão transforma “na minha máquina funciona” em algo que se pode comparar.

A terceira é a da cena: **um cluster de kind de três nós depende de um limite do kernel** que no Ubuntu e no Mint vem baixo. Se ele não for aumentado antes, o kind não avisa. Diz que tudo deu certo.

A lição segue esta ordem:

1. **O que a gente vai instalar** e onde roda cada peça (1.1).
2. **Fixar a versão** (1.2).
3. **Baixar e conferir a soma de verificação**, com o erro de propósito (1.3).
4. **O ajuste do `inotify`**: medir, ajustar e ver quanto o cluster consome (1.4).
5. **O arquivo do cluster**, com a imagem fixada (1.5).
6. **Criar o cluster** com um `kubeconfig` próprio (1.6).
7. **Contextos e `kubeconfig`** (1.7).
8. **Olhar o cluster** (1.8).
9. **Apagar, recriar e recuperar** (1.9).

Este é o destino, o último comando da lição, depois de apagar o cluster e criá-lo de novo em 26 segundos:

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

## Os conceitos

### 1.1 O que a gente vai instalar

#### 1.1.1 As peças

| Peça | O que é | Onde roda | Instala-se aqui? |
|---|---|---|---|
| Docker Engine | o motor que roda os contêineres | o Mint | não, já veio do curso de Docker |
| `kind` | um programa que cria e apaga clusters feitos de contêineres | o Mint | **sim**, um só binário |
| imagem `kindest/node` | a “máquina” de cada nó: Debian com `systemd`, `kubelet` e `containerd` | dentro do Docker | não, o `kind` a baixa na primeira vez |
| `kubectl` | o cliente que fala com o `kube-apiserver` | o Mint | **sim**, um só binário |
| o cluster | três contêineres com Kubernetes dentro | dentro do Docker | **cria-se** com o `kind` |

As duas coisas que se instalam são **um arquivo cada uma**. Nem o `kubectl` nem o `kind` trazem bibliotecas, serviços nem *daemons*. São binários de Go que se copiam para uma pasta do `PATH` e pronto. Por isso a instalação é curta, e por isso convém fazê-la manualmente: vê-se exatamente o que entra no sistema.

#### 1.1.2 Por que não com `apt` ou `snap`

O Ubuntu, e portanto o Mint, oferece o `kubectl` por `snap`, e existem repositórios de `apt` do projeto Kubernetes. Funcionam, mas têm um problema para este curso: **decidem a versão pela pessoa** e a atualizam quando lhes convém. Um `snap` se atualiza sozinho, em segundo plano. Um repositório de `apt` muda a versão no próximo `apt upgrade`. Em um curso em que cada saída é comparada com a da máquina de quem o faz, é preciso que a versão mude **quando a pessoa decidir**. A página oficial de instalação do `kubectl` oferece o binário direto como primeira opção, e é ele que se usa aqui ([kubernetes.io, “Install and Set Up kubectl on Linux”](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)). O guia rápido do kind faz o mesmo com o binário da release ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)).

### 1.2 Fixar a versão

#### 1.2.1 As versões do curso

| Ferramenta | Versão | De onde |
|---|---|---|
| `kubectl` | **v1.37.1** | `dl.k8s.io`, o site de downloads do projeto Kubernetes |
| `kind` | **v0.33.0** | a release v0.33.0 no GitHub (`kubernetes-sigs/kind`) |
| imagem do nó | `kindest/node:v1.37.0` com o *digest* | as notas da versão v0.33.0 do kind |

O guia oficial do `kubectl` usa um truque: pergunta qual é a versão estável em `https://dl.k8s.io/release/stable.txt` e baixa essa. Em 21 de outubro de 2026 esse arquivo dizia `v1.37.1`, a mesma do curso. Mas **amanhã pode dizer outra**, e o comando do guia baixaria outra sem avisar. Por isso os programas desta lição escrevem a versão completa no endereço, sem perguntar.

#### 1.2.2 Por que `kubectl` 1.37.1 com um cluster 1.37.0?

São dois números distintos e a Lição 0 já os separou. O cluster roda o que a imagem do nó traz, `v1.37.0`. O `kubectl` é a ferramenta da máquina. A política oficial é clara: “é preciso usar uma versão do `kubectl` que esteja a até uma versão menor de diferença do cluster. Por exemplo, um cliente v1.37 pode se comunicar com planos de controle v1.36, v1.37 e v1.38” ([kubernetes.io, “Install and Set Up kubectl on Linux”](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/); [“Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/)). O patch, o terceiro número, não conta para essa regra.

### 1.3 Baixar e conferir a soma de verificação

#### 1.3.1 O que é uma soma de verificação `sha256`

Uma soma de verificação `sha256` (em inglês, *checksum*) é um número de 256 bits, escrito com 64 caracteres hexadecimais (de `0` a `9` e de `a` a `f`), calculado a partir de **todos** os bytes de um arquivo. Tem duas propriedades que o tornam útil. Sempre dá o mesmo resultado para o mesmo arquivo. E se um único byte muda, sai um número completamente diferente, sem semelhança com o anterior. Não existe forma prática de fabricar outro arquivo que dê o mesmo checksum.

O projeto publica, junto a cada binário, o checksum dele. Baixam-se os dois, calcula-se o checksum do binário que chegou e compara-se com o publicado. Se coincidem, o arquivo que se tem é, byte a byte, o que o projeto publicou com aquele checksum. Se não, algo mudou no caminho: um download interrompido, um espelho desatualizado, um arquivo de outra versão ou um arquivo alterado. Em qualquer desses casos, **não se instala**.

É preciso ser honesto sobre o que o checksum não demonstra. O binário e o checksum saem do mesmo lugar. Se alguém controlasse o `dl.k8s.io` e alterasse os dois, eles coincidiriam. O checksum protege contra corrupções e downloads interrompidos **entre** o site oficial e o disco, e contra misturar versões ou arquivos sem perceber: se o que ficou no disco coincide com o checksum, é o que o site publicou. Não protege contra um binário que venha de um site que não é o oficial: o “`kubectl` que funciona para mim” que chega pelo chat não traz checksum, ou traz um que não dá para contrastar com nada. Por isso a origem importa tanto quanto o checksum.

#### 1.3.2 O programa que baixa e confere

O `fig01_01.sh` faz o download e a conferência dos dois binários, com a versão escrita no próprio script. Não instala nada nem pede `sudo`. Deixa os arquivos na pasta indicada.

```bash
#!/usr/bin/env bash
# fig01_01.sh — Lección 1, sección 1.3: descargar kubectl y kind con la versión
# FIJADA y comprobar su suma sha256 ANTES de instalarlos.
#
# Solo descarga y comprueba: no instala nada ni pide sudo. Los dos binarios
# quedan en la carpeta que le des, listos para el «sudo install» de la lección.
#
# Uso:  ./fig01_01.sh CARPETA        (una carpeta nueva y vacía, por ejemplo ~/descargas-k8s)
#
# Descarga los binarios de Linux para amd64, los de Linux Mint en un equipo
# Intel o AMD. Si tu equipo es ARM, cambia ARQ=arm64.
set -euo pipefail

KUBECTL_VERSION=v1.37.1
KIND_VERSION=v0.33.0
ARQ=amd64

DESTINO="${1:?uso: ./fig01_01.sh CARPETA}"
mkdir -p "$DESTINO"
cd "$DESTINO"

# Muestra el comando como lo teclearías y luego lo corre.
paso() { printf '\n$ %s\n' "$*"; "$@"; }

echo "# kubectl $KUBECTL_VERSION y kind $KIND_VERSION para linux/$ARQ"

# kubectl: el binario y su suma salen de dl.k8s.io, con la MISMA versión.
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl"
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl.sha256"
paso cat kubectl.sha256; echo
# El archivo .sha256 de kubectl trae solo la suma; se le pega el nombre del
# archivo, como lo pide la guía oficial. El «-» final dice «lee la lista de la
# entrada»: en Linux es opcional, y con él el guion corre igual en macOS.
printf '\n$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -\n'
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -

# kind: el binario y su suma salen del lanzamiento en GitHub. El .sha256sum de
# kind ya trae «suma  nombre», así que se comprueba directo.
paso curl -fsSLo "kind-linux-$ARQ" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ"
paso curl -fsSLo "kind-linux-$ARQ.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ.sha256sum"
paso cat "kind-linux-$ARQ.sha256sum"
paso sha256sum --check "kind-linux-$ARQ.sha256sum"

# Lo que quedó: dos binarios comprobados. wc -c da su tamaño en bytes, para
# compararlo con el de la lección.
paso wc -c kubectl "kind-linux-$ARQ"
```

Três detalhes, de cima para baixo:

- **`set -euo pipefail`** faz o script parar no primeiro comando que falhar. Se o checksum não coincide, o `sha256sum` sai com código 1 e o script para ali, antes de baixar o `kind` e antes do `wc -c` final.
- **`curl -fsSL`**: o `-f` faz um erro do servidor (um 404 porque a versão foi digitada errada) virar uma falha, e não um arquivo de erro salvo com o nome do binário. O `-L` segue os redirecionamentos, que o GitHub usa em todos os downloads. O `-sS` silencia a barra de progresso, mas deixa ver os erros.
- **Dois formatos de checksum.** O `kubectl.sha256` do projeto Kubernetes traz apenas os 64 caracteres. Por isso o guia oficial monta a linha “checksum, dois espaços, nome” com `echo` e a passa para o `sha256sum --check`. O `.sha256sum` do kind já traz a linha completa, e o `sha256sum --check` a lê direto.

#### 1.3.3 A execução

**Execução real · Mac** (a pasta temporária foi apagada ao terminar):

```text
# kubectl v1.37.1 y kind v0.33.0 para linux/amd64

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ cat kubectl.sha256
65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
kubectl: OK

$ curl -fsSLo kind-linux-amd64 https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64

$ curl -fsSLo kind-linux-amd64.sha256sum https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64.sha256sum

$ cat kind-linux-amd64.sha256sum
aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d  kind-linux-amd64

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ wc -c kubectl kind-linux-amd64
 61886626 kubectl
 10530942 kind-linux-amd64
 72417568 total
```

O que importa são os dois `OK`. Anote também os dois checksums: se daqui a um mês os mesmos binários, com as mesmas versões, forem baixados de novo, devem sair **exatamente** estes. Se saírem outros, não é a mesma versão ou não é o mesmo arquivo. O `wc -c` do final disse que o `kubectl` pesa 61.886.626 bytes e o `kind` 10.530.942.

O guia rápido do kind dá o comando de download do binário, mas não menciona o checksum ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)). A release v0.33.0 publica, sim, um `.sha256sum` para cada binário (Linux `amd64` e `arm64`, macOS e Windows), e isso se vê na lista de arquivos da [página da release](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0). Que o guia não o peça não quer dizer que não faça falta. Este curso o pede.

#### 1.3.4 O erro de propósito: `FAILED`

O `fig01_02.sh` provoca a falha das duas formas em que ela acontece de verdade. No primeiro caso, o binário é de **outra versão**, v1.37.0, e o checksum é o da v1.37.1. É o que acontece quando o binário é baixado com o comando do `stable.txt` em um dia e o checksum em outro, ou quando se copia o endereço de um tutorial e o checksum de outro. No segundo, o binário é o correto, mas com **um byte a mais** no final, como um arquivo que se corrompeu ou que alguém mexeu. **Execução real · Mac** (`fig01_02.error-esperado.txt`):

```text
## Caso 1: binario de v1.37.0, suma de v1.37.1

$ curl -fsSLO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]

## Caso 2: el binario correcto, con un byte de más

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]
```

Lê-se assim: `kubectl: FAILED` é o veredito sobre aquele arquivo, e o aviso diz quantos dos arquivos verificados não coincidiram (aqui, um de um). O código de saída 1 é o que faz o `set -e` parar um script. O guia oficial mostra o veredito primeiro e o aviso depois, que é o que aparece no terminal do Mint. A saída acima vem do `sha256sum` do macOS, que imprimiu o aviso antes. As duas linhas viajam por canais distintos (a saída normal e a de erros), de modo que, quando são capturadas em um arquivo, a ordem pode mudar. O que não muda é o `FAILED` e o código de saída 1.

Repare no que a mensagem **não** diz: não distingue “outra versão” de “arquivo alterado”. Os dois casos se parecem. E é correto que seja assim: a tarefa não é descobrir qual dos dois foi, e sim não instalar. O que se faz diante de um `FAILED`: apaga-se o binário e o checksum, confere-se que os dois endereços digam a mesma versão e baixam-se os dois de novo. Se falhar outra vez com a mesma versão, não se instala nada e investiga-se de onde se está baixando.

#### 1.3.5 Instalar

No Mint, a instalação são dois comandos, o do guia oficial do `kubectl` e o equivalente para o `kind`:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
sudo install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind
```

(Em uma máquina ARM, o arquivo do kind se chama `kind-linux-arm64`, os dois binários são outros e os checksums também: devem ser comparados com os que cada release publica, e não com os desta lição.)

O `install` faz em um passo o que fariam `cp`, `chown` e `chmod`. Copia o arquivo, deixa o `root` como dono (`-o root -g root`) e com permissão `0755`: todos podem executá-lo, só o `root` pode alterá-lo. Esse último ponto importa. Um binário no `PATH` que o usuário pode sobrescrever é um binário que qualquer programa executado por esse usuário pode substituir. O guia rápido do kind usa `chmod +x` e `sudo mv`. O resultado é quase o mesmo, mas o arquivo fica com o usuário como dono. O `install` é mais limpo, e por isso o curso o usa para os dois. `/usr/local/bin` é a pasta que o Linux reserva para os programas instalados manualmente, fora do gerenciador de pacotes. Ela já está no `PATH` do Mint.

Como no Mac nada foi instalado, o `fig01_03.sh` faz a instalação completa **dentro de um contêiner descartável** de Ubuntu 24.04 para `amd64`, com os mesmos arquivos que o `fig01_01.sh` baixou. Os arquivos entram por um `tar` na entrada padrão, sem montar pastas. Dentro do contêiner já se é `root`, então os `install` vão sem `sudo`. **Execução real · Ubuntu 24.04 amd64** (`fig01_03.salida.txt`):

```text
# Ubuntu 24.04.5 LTS, x86_64, sha256sum (GNU coreutils) 9.4

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: OK

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
$ install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind

$ ls -l /usr/local/bin/kubectl /usr/local/bin/kind
-rwxr-xr-x 1 root root 10530942 Oct 21 09:53 /usr/local/bin/kind
-rwxr-xr-x 1 root root 61886626 Oct 21 09:53 /usr/local/bin/kubectl

$ command -v kubectl kind
/usr/local/bin/kubectl
/usr/local/bin/kind

$ kubectl version --client
Client Version: v1.37.1
Kustomize Version: v5.8.1

$ kind version
kind v0.33.0 go1.26.7 linux/amd64
```

Aqui a conferência usa o comando do guia **letra por letra**, sem o `-` final, e o `sha256sum` do GNU diz `OK` do mesmo jeito. Depois, três conferências que a gente vai repetir no Mint:

- **`ls -l`**: as permissões `-rwxr-xr-x`, o dono `root root` e o tamanho, que deve ser o mesmo visto ao baixar.
- **`command -v kubectl kind`**: que arquivo roda de verdade quando se digita o nome. Se havia outro `kubectl` instalado antes (por `snap`, por exemplo), aqui se vê qual vence. O correto é `/usr/local/bin/kubectl`.
- **`kubectl version --client`** e **`kind version`**: as versões pedidas. O `--client` diz ao `kubectl` que não procure um cluster, porque ainda não existe. `Kustomize Version: v5.8.1` é a ferramenta da Lição 4, que vem **dentro** do `kubectl` e não se instala à parte.

Um aviso que saiu do próprio Mac das execuções. Ali, no terminal interativo, `type kubectl` respondeu `kubectl: aliased to kubecolor`: um alias que alguém configurou para colorir a saída. Os scripts não enxergam os aliases do terminal, então rodavam o `kubectl` real, mas o que era digitado manualmente passava por outro programa. O `command -v` nem sempre revela um alias; o `type kubectl` revela. Se a saída não se parece com a do curso, é por aí que se começa.

### 1.4 O ajuste do `inotify`

#### 1.4.1 O que é o `inotify`

Muitos programas precisam saber que um arquivo mudou sem ficar lendo-o a cada segundo. O Linux dá um mecanismo para isso: “a API do `inotify` oferece um mecanismo para monitorar eventos do sistema de arquivos” ([man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html)). Um programa abre uma **instância** do `inotify` e adiciona a ela **watches** (monitoramentos), um por arquivo ou pasta. O kernel avisa quando algo muda.

Cada instância e cada watch ocupam memória do kernel, então o kernel impõe dois limites, **por usuário**:

- `fs.inotify.max_user_instances`: “um limite superior para o número de instâncias do `inotify` que podem ser criadas por usuário real”.
- `fs.inotify.max_user_watches`: o mesmo para os watches.

Em um nó de Kubernetes, o `kubelet`, o `kube-proxy`, o `containerd` e os componentes do plano de controle monitoram arquivos o tempo todo: certificados, manifestos, configurações, os logs dos contêineres. Em uma máquina normal, um nó é uma máquina. No kind, **três nós são três contêineres sobre o mesmo kernel**, e quase todos os processos rodam como o mesmo usuário, `root`. Os três dividem um único limite.

O guia de problemas conhecidos do kind diz assim: os limites “são definidos pelas variáveis de sistema `fs.inotify.max_user_watches` e `fs.inotify.max_user_instances`. Por exemplo, no Ubuntu valem 8192 e 128, respectivamente, o que não basta para criar um cluster com muitos nós” ([kind, “Known Issues”](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files)). E dá os valores que recomenda: 524288 watches e 512 instâncias.

#### 1.4.2 Medir antes de mexer

O ajuste é feito **antes** de criar o cluster, e começa-se medindo. O `fig01_04.sh` sem argumentos apenas lê; com `--ajustar` altera o sistema, e isso a gente vê em 1.4.3:

```bash
#!/usr/bin/env bash
# fig01_04.sh — Lección 1, sección 1.4: MEDIR los límites de inotify del núcleo
# y, solo si se lo pides, AJUSTARLOS como pide la guía de kind.
#
# Uso:  ./fig01_04.sh                → solo mide. No cambia nada.
#       sudo ./fig01_04.sh --ajustar → copia 99-kind-inotify.conf a /etc/sysctl.d/
#                                      y lo carga. Cambia tu sistema: LÉELO ANTES,
#                                      a él y a 99-kind-inotify.conf.
#
# Corre en la máquina donde corre Docker: en Linux Mint, tu propia máquina.
set -euo pipefail
cd "$(dirname "$0")"

MINIMO_INSTANCIAS=512
MINIMO_VIGILANCIAS=524288
ARCHIVO=99-kind-inotify.conf
DESTINO=/etc/sysctl.d/$ARCHIVO

medir() {
  printf '\n$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches\n'
  sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches

  # Cuántas instancias de inotify están abiertas AHORA. Cada una es un
  # descriptor que apunta a «anon_inode:inotify». Sin sudo solo ves las de tus
  # procesos; con sudo, las de todos los usuarios (el límite es por usuario).
  printf '\n$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l\n'
  # (find se queja de las carpetas que no puede leer: eso no es un fallo aquí)
  { find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null || true; } | wc -l | tr -d ' '

  # ¿Quedó escrito en algún archivo, o solo vale hasta reiniciar? Se buscan las
  # líneas que FIJAN un valor (empiezan con fs.inotify), no los comentarios, en
  # todas las carpetas que lee el sistema al arrancar (sysctl.d(5)).
  printf "\n\$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/\n"
  grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/ 2>/dev/null \
    || echo "(ninguna: lo que mide sysctl vale hasta el próximo reinicio)"

  local inst vig
  inst="$(cat /proc/sys/fs/inotify/max_user_instances)"
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  echo
  if [ "$inst" -ge "$MINIMO_INSTANCIAS" ] && [ "$vig" -ge "$MINIMO_VIGILANCIAS" ]; then
    echo "LISTO: instancias $inst (mínimo $MINIMO_INSTANCIAS) y vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
  else
    echo "FALTA AJUSTAR: instancias $inst (mínimo $MINIMO_INSTANCIAS), vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
    echo "Lee este guion y $ARCHIVO, y luego corre: sudo ./fig01_04.sh --ajustar"
  fi
}

ajustar() {
  [ "$(id -u)" -eq 0 ] || { echo "ALTO: --ajustar necesita sudo." >&2; exit 1; }

  # 1. No BAJAR las vigilancias. En núcleos recientes el valor por omisión
  #    depende de la memoria y puede pasar de 524288; en ese caso se instala el
  #    archivo SIN la línea de vigilancias, y solo se suben las instancias.
  local vig contenido
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  contenido="$(mktemp)"
  if [ "$vig" -gt "$MINIMO_VIGILANCIAS" ]; then
    echo "Tus vigilancias ya son $vig, más que $MINIMO_VIGILANCIAS: no se tocan."
    grep -v '^fs.inotify.max_user_watches' "$ARCHIVO" > "$contenido"
  else
    cat "$ARCHIVO" > "$contenido"
  fi

  # 2. No pisar un archivo que ya existe con otro contenido.
  if [ -e "$DESTINO" ] && ! cmp -s "$contenido" "$DESTINO"; then
    echo "ALTO: ya existe $DESTINO con otro contenido. No lo piso:" >&2
    diff "$DESTINO" "$contenido" >&2 || true
    rm -f "$contenido"
    exit 1
  fi

  # Un archivo propio en /etc/sysctl.d/, en vez de editar /etc/sysctl.conf: se ve
  # de un vistazo qué se cambió y por qué, y se quita borrando un archivo.
  install -o root -g root -m 0644 "$contenido" "$DESTINO"
  rm -f "$contenido"
  printf '\n$ sysctl --load=%s\n' "$DESTINO"
  sysctl --load="$DESTINO"

  # 3. Avisar si /etc/sysctl.conf fija inotify: en Ubuntu y Mint se aplica
  #    DESPUÉS (por 99-sysctl.conf) y su valor ganaría al reiniciar.
  if grep -q '^fs.inotify' /etc/sysctl.conf 2>/dev/null; then
    echo "AVISO: /etc/sysctl.conf también fija inotify y se aplica después de $ARCHIVO:" >&2
    grep -n '^fs.inotify' /etc/sysctl.conf >&2
  fi
  medir
}

case "${1:-}" in
  "") medir ;;
  --ajustar) ajustar ;;
  *) echo "uso: ./fig01_04.sh [--ajustar]" >&2; exit 2 ;;
esac
```

O novo está em dois comandos da medição. O primeiro **conta as instâncias abertas**. Cada instância é um descritor de arquivo de algum processo, e em `/proc/<pid>/fd/` esse descritor aparece como um link para `anon_inode:inotify`. O `find ... -lname` busca exatamente esses links. Sem `sudo`, só se podem ver os descritores dos próprios processos; com `sudo`, veem-se os de todos os usuários, embora o limite seja contado por usuário. O segundo, o `grep`, busca **onde o valor ficou escrito**, em todas as pastas que o sistema lê ao iniciar. Busca linhas que comecem com `fs.inotify`, que são as que fixam um valor, e não os comentários que apenas mencionam a palavra.

No Mac, o kernel que o Docker usa é o da máquina virtual do Colima, então foi ali que se mediu. **Execução real · máquina virtual** (`fig01_04.salida.txt`, apenas medição, sem ajustar):

```text
# máquina virtual de Colima: Ubuntu 24.04.4 LTS, núcleo 6.8.0-100-generic
## sin sudo

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
3

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).

## con sudo (solo mide)

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
110

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).
```

Essa máquina já tinha 512 instâncias, e watches de sobra. A diferença entre 3 e 110 instâncias é a de “sem `sudo`” e “com `sudo`”: o usuário normal tinha 3 abertas, e o sistema inteiro 110, com um cluster de kind de outra lição rodando naquele momento. Esse número muda com tudo o que estiver rodando. O que se compara é o limite.

E repare no `grep`: **nenhum arquivo** das pastas lidas na inicialização fixa o `inotify`. O 512 está vivo no kernel, mas não escrito. A Lição 0 conta que essa mesma máquina estava em 128 e que foi aumentada para 512 para o teste; o `grep` mostra que foi aumentada sem deixar arquivo. Se é assim, no dia em que a máquina virtual for reiniciada, volta ao valor padrão, e o próximo cluster de três nós falha sem explicação. A medição diz quanto vale hoje; o `grep` diz quanto valerá depois de reiniciar. É preciso olhar as duas coisas, e por isso o script as olha juntas.

Em um Mint recém-instalado, o mais provável é aparecer `max_user_instances = 128` e o script dizer `FALTA AJUSTAR`. O Linux Mint 22 se baseia no Ubuntu 24.04 ([Linux Mint, notas da versão 22](https://www.linuxmint.com/rel_wilma.php)), e o Ubuntu traz 128. Os watches, por outro lado, podem aparecer altos: na máquina virtual das execuções, também um Ubuntu 24.04, o kernel dava 1048576, muito acima dos 8192 que o guia do kind menciona. Em kernels recentes esse valor depende da memória da máquina, então o que quase sempre falta são as instâncias.

#### 1.4.3 Ajustar, e fazer durar

O guia do kind dá duas formas. A **temporária**, que vale até reiniciar:

```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

E a **persistente**: escrever as duas linhas em `/etc/sysctl.conf`. O curso faz a persistente com uma variante: em vez de editar o `/etc/sysctl.conf`, coloca um arquivo próprio em `/etc/sysctl.d/`. Este é o arquivo, `99-kind-inotify.conf`:

```ini
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

Por que um arquivo separado? Porque “na inicialização, o `systemd-sysctl.service` lê os arquivos de configuração” de `/etc/sysctl.d/*.conf`, entre outras pastas ([man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html)). Fica tudo em um único arquivo, com o comentário, o que foi alterado e por quê, e para desfazer basta apagá-lo e reiniciar.

Mas há uma armadilha na ordem. A mesma página diz que todos os arquivos são ordenados pelo nome, não importa em que pasta estejam, e que se dois fixam a mesma coisa **vence o que vem depois**. O `99-` deixa o arquivo do curso quase no final. Quase, porque o Ubuntu, e com ele o Mint, traz outro. Medido na máquina virtual das execuções:

```text
$ ls /etc/sysctl.d/
10-bufferbloat.conf
10-console-messages.conf
10-ipv6-privacy.conf
10-kernel-hardening.conf
10-magic-sysrq.conf
10-map-count.conf
10-network-security.conf
10-ptrace.conf
10-zeropage.conf
99-cloudimg-ipv6.conf
99-lima.conf
99-sysctl.conf
README.sysctl

$ ls -l /etc/sysctl.d/99-sysctl.conf
lrwxrwxrwx 1 root root 14 Nov 25  2025 /etc/sysctl.d/99-sysctl.conf -> ../sysctl.conf
```

O `99-sysctl.conf` é um link para `/etc/sysctl.conf`, e o `99-sysctl.conf` vem depois do `99-kind-inotify.conf` em ordem alfabética (o `s` vem depois do `k`). Portanto, **se alguém colocou um valor de `inotify` em `/etc/sysctl.conf`, esse valor vence** ao reiniciar, e o do curso não serve de nada. Por isso o `--ajustar` revisa o `/etc/sysctl.conf` e avisa, e por isso a medição busca em todas as pastas.

No Mint, o ajuste é `sudo ./fig01_04.sh --ajustar`. **Antes de rodá-lo com `sudo`, leia-o por inteiro, junto com o `99-kind-inotify.conf`.** É o mesmo hábito dos binários: tudo o que roda como `root` foi lido antes. O que se encontra em `ajustar`:

1. **Não reduz os watches.** Se o kernel já tem mais de 524288, o arquivo que ele instala vai sem a linha `max_user_watches`, e só aumenta as instâncias. Sem essa proteção, o ajuste do kind **tiraria** watches.
2. **Não sobrescreve um arquivo que já existe.** Se `/etc/sysctl.d/99-kind-inotify.conf` existe com outro conteúdo, mostra a diferença e para.
3. Copia o arquivo com dono `root` e permissão `0644`, carrega-o na hora com `sysctl --load` (sem esperar reiniciar), avisa se o `/etc/sysctl.conf` também fixa o `inotify` e mede de novo. Deve terminar em `LISTO`.

O ajuste de verdade não foi executado na máquina das execuções: ela já tinha 512, e era uma máquina compartilhada em que não cabia alterar nada. O que foi testado são as duas proteções, em um contêiner descartável **sem privilégios**, onde `/proc/sys` é somente leitura e o `sysctl` não pode alterar o kernel de ninguém. **Execução real · contêiner sem privilégios** (`fig01_04.prueba-ajustar.txt`):

```text
$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.

$ sysctl --load=/etc/sysctl.d/99-kind-inotify.conf
sysctl: permission denied on key "fs.inotify.max_user_instances"
[código de salida: 1]

$ cat /etc/sysctl.d/99-kind-inotify.conf
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_instances = 512

$ echo otro > /etc/sysctl.d/99-kind-inotify.conf

$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.
ALTO: ya existe /etc/sysctl.d/99-kind-inotify.conf con otro contenido. No lo piso:
1c1,5
< otro
---
> # /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
> # kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
> # Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
> # arranca: el kubelet de los nodos de trabajo cae con «too many open files».
> fs.inotify.max_user_instances = 512
[código de salida: 1]
```

A primeira execução viu 1048576 watches e instalou o arquivo **sem** a linha de watches: o `cat` demonstra. O `permission denied` é o esperado em um contêiner sem privilégios; no Mint, com `sudo`, o `sysctl --load` responde com as linhas que carregou. A segunda execução encontrou um arquivo com outro conteúdo e parou sem tocá-lo.

#### 1.4.4 Quanto um cluster consome

Com o cluster criado (1.6), o script da lição olha o limite **de dentro** de cada nó, e conta as instâncias que cada um abre. **Execução real · Mac**, trecho de `correr.salida.txt`:

```text
$ docker exec curso-k8s-l1-control-plane cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker2 cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-control-plane sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
45

$ docker exec curso-k8s-l1-worker sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18

$ docker exec curso-k8s-l1-worker2 sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18
```

Os três nós dizem 512: não têm um limite próprio, veem **o do kernel da máquina**. É a mesma pista da coluna `KERNEL-VERSION` da Lição 0, agora com um número que importa. E a contagem: 45 instâncias no nó de controle e 18 em cada nó de trabalho. São 81, com o cluster **vazio**, recém-criado, sem um único Pod próprio. Quase todas são de processos do `root`, e o limite é por usuário: a essas 81 somam-se as que o `root` já tem abertas na própria máquina, que podem ser contadas com o `find` do `fig01_04.sh` rodado com `sudo`. Com um limite de 128, a margem é pequena. O que acontece na inicialização, quando os três nós sobem os processos ao mesmo tempo, não foi medido aqui; a Lição 0 viu o resultado: os nós de trabalho não chegaram. Com 512 há folga de sobra para este cluster e para mais um.

### 1.5 O arquivo do cluster

O `kind create cluster` sem mais nada cria um cluster de um só nó chamado `kind`, com a imagem de nó padrão daquela versão do kind. O curso precisa de três nós, um nome próprio e a imagem fixada, e isso se escreve em um arquivo:

```yaml
# kind-curso.yaml — el clúster del curso: un nodo de control y dos de trabajo,
# con la imagen del nodo fijada por su huella (notas de la versión v0.33.0 de kind).
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

Lê-se de cima para baixo. `kind: Cluster` e `apiVersion: kind.x-k8s.io/v1alpha4` dizem que é a configuração de um cluster do kind. Parece um manifesto do Kubernetes, mas não é: este arquivo é lido pelo `kind`, nunca pelo cluster. `nodes` é a lista de nós, um por item com `role`: `control-plane` para o plano de controle e `worker` para os de trabalho. É a mesma forma que o guia rápido do kind usa para um cluster “de três nós (dois de trabalho)” ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)).

E cada nó leva a `image` **com digest**. É o mesmo hábito do checksum dos binários, aplicado a uma imagem. A tag `v1.37.0` é um nome que quem publica a imagem pode mover para outra. O digest `sha256:a1ed…` é o checksum do conteúdo. O guia do kind pede assim: “use o hash `sha256` da versão do Kubernetes que quiser”, tal como as notas de cada release o publicam ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/); [kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). Se alguém substituir a imagem, o Docker não a aceita, porque o digest deixa de coincidir.

O nome do cluster não vai no arquivo, vai no comando: `--name curso-k8s-l1`. Assim o mesmo arquivo serve para criar clusters com outros nomes.

O comando procura o `kind-curso.yaml` pelo caminho indicado. Os comandos desta lição supõem que se está dentro de `programas/01-instalacion-primer-cluster/`, onde o arquivo vive. Se o arquivo for copiado para outra pasta, o comando deve ser rodado de lá, ou o caminho completo deve ser escrito em `--config`.

### 1.6 Criar o cluster

#### 1.6.1 Um `kubeconfig` próprio para o curso

Antes de criar qualquer coisa, uma decisão de segurança. Quando o kind cria um cluster, ele **escreve no `kubeconfig`** o endereço do cluster e a credencial de administrador, e o deixa como contexto ativo. Se nada for dito em contrário, esse arquivo é `~/.kube/config`. Se nesse arquivo já houver um cluster do trabalho ou de outro curso, o kind muda o contexto ativo sem perguntar.

Por isso, neste curso, o kind escreve em um arquivo **temporário e próprio**. Manualmente, no terminal, é assim:

```bash
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l1.XXXX)/kubeconfig"
```

O `mktemp -d` cria uma pasta com um nome que mais ninguém tem. O `export KUBECONFIG=…` faz o `kind` e o `kubectl` usarem esse arquivo **neste terminal**, e em nenhum outro. O `~/.kube/config` nem é lido nem é tocado. Fecha-se o terminal e a configuração de sempre continua como antes.

O que **não** vai embora ao fechar o terminal: o cluster, que continua rodando, e a pasta temporária, com a credencial de administrador dentro. Além disso, ao fechar perde-se o caminho do `KUBECONFIG`. Por isso, no caminho manual, antes de fechar:

```bash
kind delete cluster --name curso-k8s-l1
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp arriba.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l1.*/kubeconfig) rm -r -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

O `case` só deixa passar um caminho com a forma exata do que o `mktemp` criou; se o `KUBECONFIG` apontar para outro lugar, por exemplo para o `~/.kube/config` porque outro terminal foi aberto e o `export` não foi repetido, não apaga nada e diz por quê, em vez de levar a pasta `~/.kube` inteira.

Se o terminal já foi fechado, o `kind get clusters` diz o que ficou vivo, e o `ls -d /tmp/curso-k8s-l1.*` quais pastas ficaram. O script da lição, `correr.sh`, faz tudo isso sozinho: cria a própria pasta temporária e, ao sair, apaga o cluster e a pasta.

#### 1.6.2 O script da lição

O `correr.sh` percorre tudo o que resta da lição: cria o cluster, o olha, experimenta com os contextos, provoca os erros, o apaga, o recria e, ao sair, o apaga de novo. O cabeçalho explica as três proteções, e são as mesmas que a gente vai usar em todo o curso:

```bash
# 🔴 SEGURIDAD, las tres protecciones de la lección:
#   1. KUBECONFIG apunta a un archivo TEMPORAL propio: tu ~/.kube/config ni se
#      lee ni se toca, y tus otros clústeres no se enteran.
#   2. Antes de cada kubectl que le habla al clúster, se comprueba que el
#      contexto activo es kind-curso-k8s-l1; si no, el guion se detiene.
#   3. Un trap borra al salir el clúster que ESTA corrida creó y el temporal,
#      aunque el guion falle a la mitad. Si al empezar ya existe un clúster
#      llamado curso-k8s-l1, se detiene sin tocarlo.
```

A terceira merece uma explicação. `trap limpiar EXIT` diz ao Bash: “quando este script terminar, por qualquer motivo, rode `limpiar`”. Se um comando falha no meio e o `set -e` interrompe o script, o `limpiar` roda do mesmo jeito e apaga o cluster. Assim não sobra um cluster esquecido gastando memória. Mas o `limpiar` só apaga se a variável `CREADO_AQUI` disser `si`, e essa variável é ligada **somente se o `kind create cluster` desta execução terminou bem**. Se já havia um `curso-k8s-l1` de antes, o script para no início e não o toca: esse cluster não é dele. E se outro processo o criou um instante depois dessa verificação, o `create` do script falha com `node(s) already exist`, o script para e a variável continua em `no`: também não o toca.

A segunda proteção é uma função curta, a mesma da Lição 0:

```bash
contexto_correcto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    return 1
  fi
}
k() { contexto_correcto || exit 1; paso kubectl "$@"; }
```

Cada `kubectl` que fala com o cluster passa pelo `k`, que primeiro pergunta o contexto. Os `kubectl config`, que apenas leem ou editam o arquivo `kubeconfig` sem falar com nenhum cluster, passam por outra função, `kc`, sem verificação. Não precisam dela, e na seção 1.7 o script muda de contexto de propósito.

#### 1.6.3 A criação

Antes de criar qualquer coisa, o script olha o `kubeconfig` temporário. Está vazio: não há contextos nem contexto ativo.

```text
$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]
```

E cria o cluster. **Execução real · Mac:**

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
 • Ensuring node image (kindest/node:v1.37.0) 🖼️  ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
 • Preparing nodes 📦 📦 📦   ...
 ✓ Preparing nodes 📦 📦 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
 • Joining worker nodes 🚜  ...
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-curso-k8s-l1"
You can now use your cluster with:

kubectl cluster-info --context kind-curso-k8s-l1

Have a nice day! 👋
(crear tardó 23 s)
```

Cada par de linhas é um passo. *Ensuring node image* procura a imagem do nó e, se ela não estiver, a baixa; na primeira vez no Mint este passo leva o tempo que o download da imagem levar, e nas seguintes é instantâneo. *Preparing nodes* cria os três contêineres (um 📦 por nó). *Writing configuration* escreve a configuração do `kubeadm`, a ferramenta oficial que monta o cluster. *Starting control-plane* inicia o plano de controle. *Installing CNI* instala a rede entre Pods, o `kindnet`. *Installing StorageClass* instala o armazenamento padrão. *Joining worker nodes* junta os dois nós de trabalho. No final, `Set kubectl context to "kind-curso-k8s-l1"` é a linha que mais importa nesta lição: o kind escreveu o contexto no `kubeconfig` (o temporário) e o deixou ativo. A frase de despedida muda ao acaso a cada execução.

Com a imagem já baixada, criar levou 23 segundos. E agora, a lição da Lição 0: **o ✓ não é a prova**. A prova tem duas partes. A primeira é esperar que os nós digam `Ready`:

```text
$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met
```

O `kubectl wait` fica esperando até que todos os nós (`--all`) cumpram a condição `Ready`, ou até passarem 240 segundos. Mas tem um ponto cego: espera os nós que **existem**. Na falha da Lição 0, os nós de trabalho nunca chegaram a se registrar; ali o `kubectl wait --all` teria esperado por um só, teria dito `condition met` uma única vez e teria terminado sem erro. Por isso a segunda parte é **contar**:

```text
$ kubectl get nodes --no-headers | wc -l
3
```

O `--no-headers` tira a linha de títulos e o `wc -l` conta as linhas que sobram: uma por nó. Tem que dizer 3. O script não deixa isso por conta de quem lê: se não for 3, para com `ALTO: el clúster tiene N nodos, no 3`. (No `correr.sh`, a espera e a contagem vêm depois de olhar o `kubeconfig`, na seção 5 da saída; aqui são apresentadas juntas porque são a mesma prova.)

### 1.7 Contextos e `kubeconfig`

#### 1.7.1 O que há em um `kubeconfig`

A documentação o define assim: “um arquivo usado para configurar o acesso a clusters é chamado de arquivo *kubeconfig*. É uma forma genérica de se referir a arquivos de configuração; não significa que exista um arquivo chamado `kubeconfig`” ([kubernetes.io, “Organizing Cluster Access Using kubeconfig Files”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). Por padrão, o `kubectl` procura um chamado `config` em `$HOME/.kube`.

Um `kubeconfig` tem três listas e um ponteiro:

- **`clusters`**: com que endereço falar e com que certificado reconhecer o servidor.
- **`users`**: com que credencial se apresentar.
- **`contexts`**: combinações com nome de um cluster, um usuário e, opcionalmente, um namespace. A documentação: “cada contexto tem três parâmetros: cluster, namespace e usuário. Por padrão, o `kubectl` usa os parâmetros do *contexto atual* para se comunicar com o cluster”.
- **`current-context`**: o ponteiro. Qual dos contextos o `kubectl` usa quando nenhum outro é indicado.

O script o olha logo depois de criar o cluster:

```text
$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   

$ kubectl config view --minify
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://127.0.0.1:54589
  name: kind-curso-k8s-l1
contexts:
- context:
    cluster: kind-curso-k8s-l1
    user: kind-curso-k8s-l1
  name: kind-curso-k8s-l1
current-context: kind-curso-k8s-l1
kind: Config
users:
- name: kind-curso-k8s-l1
  user:
    client-certificate-data: DATA+OMITTED
    client-key-data: DATA+OMITTED

$ stat -c %A "$KUBECONFIG"
-rw-------
```

Quatro coisas para ler:

- **O nome do contexto é `kind-` mais o nome do cluster.** O kind sempre os nomeia assim: o cluster `curso-k8s-l1` dá o contexto `kind-curso-k8s-l1`, e o cluster padrão `kind` dá `kind-kind`. O cluster e o usuário do `kubeconfig` levam o mesmo nome.
- **`get-contexts`** é a tabela curta. O asterisco de `CURRENT` marca o ativo. `AUTHINFO` é o usuário. `NAMESPACE` vazio quer dizer `default`.
- **`view --minify`** mostra só o que o contexto ativo usa. O endereço do servidor é `https://127.0.0.1:54589`: a porta alta que o Docker publicou na máquina para o `kube-apiserver` do nó de controle, em `127.0.0.1` por padrão. O kind permite mudar esse endereço com `networking.apiServerAddress`, mas a documentação dele desaconselha expô-lo a algo que não seja a interface local, e este curso não o muda. Os três campos `DATA+OMITTED` são o certificado do servidor e **a credencial de administrador**. O `kubectl` os oculta porque são segredos. Estão completos no arquivo.
- **`stat -c %A`** dá as permissões do arquivo: `-rw-------`, só o próprio usuário pode lê-lo. O kind o cria assim porque ele contém essa credencial. Se um dia um `kubeconfig` for copiado para outro lugar, é preciso conservar essas permissões. (No Mint, `ls -l "$KUBECONFIG"` diz o mesmo, junto com o nome do usuário.)

A documentação acrescenta um aviso que vale para sempre: “use apenas arquivos `kubeconfig` de fontes confiáveis. Um arquivo `kubeconfig` feito de propósito poderia provocar a execução de código malicioso ou expor arquivos. Se for necessário usar um que não é confiável, revise-o com cuidado antes, como se revisaria um script de *shell*”. Um `kubeconfig` pode pedir que se execute um programa para obter a credencial: por isso ele é lido antes de ser usado.

#### 1.7.2 Dois contextos, e o erro sem mensagem

A Lição 0 descreveu o erro mais perigoso do `kubectl`: falar com o cluster errado, sem que nada avise. O script o monta de propósito, só dentro do `kubeconfig` temporário. Adiciona um segundo contexto, `otro`, com uma credencial fictícia e um endereço onde não há ninguém, `127.0.0.1:1`, e o deixa ativo:

```text
$ kubectl config set-cluster otro --server=https://127.0.0.1:1
Cluster "otro" set.

$ kubectl config set-credentials nadie --token=token-de-mentira
User "nadie" set.

$ kubectl config set-context otro --cluster=otro --user=nadie
Context "otro" created.

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   
          otro                otro                nadie               

$ kubectl config use-context otro
Switched to context "otro".
```

Repare na ordem. Os três `set-…` montam um cluster, um usuário e um contexto que os junta, nessa ordem. O `get-contexts` mostra os dois contextos, com o asterisco ainda no do kind. O `use-context otro` move o ponteiro. A partir daí, qualquer `kubectl` sem mais nada vai para `otro`. O que a verificação diz:

```text
$ (la comprobación del contexto, antes de un kubectl get nodes)
ALTO: el contexto activo es «otro», no «kind-curso-k8s-l1». No sigo.
[el guion NO corre kubectl get nodes: se detuvo a tiempo]

(Sin la comprobación, kubectl le habla a «otro»:)
```

E o que acontece se a verificação não for feita:

```text
$ kubectl get nodes --request-timeout=5s
E1021 07:11:02.007697   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.007948   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009279   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009582   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.010566   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
The connection to the server 127.0.0.1:1 was refused - did you specify the right host or port?
[código de salida: 1]
```

As linhas que começam com `E1021 … memcache.go:381` são escritas pelo próprio cliente do `kubectl`, não pelo cluster: o `E` é o nível de erro, `1021` o mês e o dia, e `memcache.go` é o código com que o `kubectl` guarda em memória a lista de recursos que um servidor oferece. Antes de executar o comando, o `kubectl` pergunta ao servidor que recursos ele tem, e aqui essa pergunta falhou cinco vezes porque não havia ninguém escutando. É ruído repetido, e o que importa é a última linha.

Aqui houve sorte, porque `otro` não existe e o erro é barulhento. Leia a última linha: diz **com que servidor** se tentou falar, `127.0.0.1:1`, e não é o do cluster, que estava em `127.0.0.1:54589`. Se `otro` fosse um cluster de verdade, a resposta teria sido uma lista de nós alheios, sem um único erro. O exercício de ler **com quem** se falou é o mesmo nos dois casos.

Há uma forma de não depender do ponteiro: dizer a cada comando a que contexto ele vai, com `--context`.

```text
$ kubectl --context kind-curso-k8s-l1 get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

Com `otro` ativo, este comando falou com o kind, porque a flag manda sobre o `current-context` do arquivo. Segundo a documentação, o contexto é escolhido pelo primeiro item aplicável desta cadeia: primeiro a flag `--context`, depois o `current-context` dos arquivos ([kubernetes.io, “Organizing Cluster Access…”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). Em scripts que são compartilhados, colocar `--context` em cada comando é uma proteção tão boa quanto verificar o contexto antes. O curso usa a verificação porque, além disso, ela ensina o hábito.

O script deixa tudo como estava: volta para `kind-curso-k8s-l1` com `use-context` e apaga o contexto, o cluster e o usuário fictícios com `delete-context`, `delete-cluster` e `delete-user`. Cada um respondeu `deleted … from /tmp/curso-k8s-l1.LWx1/kubeconfig`. Essa linha também diz **qual arquivo** foi modificado, e ali se vê que foi o temporário.

#### 1.7.3 `KUBECONFIG` como lista

Mais uma coisa que convém saber, embora o curso não a use. O `KUBECONFIG` pode ter **vários arquivos**, separados por dois-pontos no Linux. O `kubectl` os junta em um. Para os valores que se repetem, vence o primeiro arquivo que os define. Em particular, vence o `current-context` do primeiro arquivo que o tem ([kubernetes.io, “Organizing Cluster Access…”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). E quando o `kubectl` cria um valor novo, escreve-o no primeiro arquivo da lista que existir ([kubernetes.io, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/)). É útil e é uma armadilha: com dois arquivos na lista, um `use-context` pode alterar um arquivo que não era esperado. Com um único arquivo temporário por cluster, como neste curso, não há dúvidas.

### 1.8 Olhar o cluster

Com o contexto verificado, o script olha o cluster de quatro lados. Primeiro, a partir do Kubernetes:

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l1-control-plane   Ready    control-plane   31s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker          Ready    <none>          16s   v1.37.0   172.18.0.6    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0   172.18.0.7    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

Três nós `Ready`, versão `v1.37.0`, com o runtime `containerd://2.3.4`. O de controle é 15 segundos mais velho que os outros dois: foi criado primeiro e os de trabalho se juntaram depois. A coluna `ROLES` diz `control-plane` para um e `<none>` para os de trabalho. Não é um erro: `ROLES` sai dos rótulos (*labels*) `node-role.kubernetes.io/…` de cada nó, e ao criar o cluster só o nó de controle recebe um (`control-plane`). `INTERNAL-IP` são endereços da rede `kind` do Docker, `172.18.0.x`, que na máquina serão outros. E `KERNEL-VERSION` diz o kernel da máquina que roda o Docker, o mesmo para os três.

```text
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:54589
CoreDNS is running at https://127.0.0.1:54589/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

O `cluster-info` responde à pergunta “com o que estou falando?” com o endereço do servidor. É o mesmo do `view --minify`. Se um dia houver dúvida sobre o contexto, este comando diz o endereço real.

Segundo, a partir do kind e do Docker:

```text
$ kind get nodes --name curso-k8s-l1
curso-k8s-l1-worker
curso-k8s-l1-control-plane
curso-k8s-l1-worker2

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l1-worker          kindest/node:v1.37.0   
curso-k8s-l1-control-plane   kindest/node:v1.37.0   127.0.0.1:54589->6443/tcp
curso-k8s-l1-worker2         kindest/node:v1.37.0   
```

O `kind get nodes --name` lista os contêineres **desse** cluster, sem uma ordem fixa. Existe também o `kind get clusters`, que lista todos os clusters do kind da máquina: é útil para saber se há outros, mas não deve ser usado para decidir o que apagar sem ler cada nome. O `docker ps` com o filtro do rótulo `io.x-k8s.kind.cluster` mostra os mesmos três contêineres. Só um publica porta: o de controle, `127.0.0.1:54589->6443/tcp`. Esse é o caminho do `kubectl` até o `kube-apiserver`, que escuta na 6443 dentro do nó. Os de trabalho não publicam nada, e ninguém fora da máquina pode falar com o cluster.

Terceiro, o que roda dentro, sem tocar em nada:

```text
$ kubectl get pods -n kube-system -o wide
NAME                                                 READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-27jlk                             1/1     Running   0          23s   10.244.0.4   curso-k8s-l1-control-plane   <none>           <none>
coredns-559f6c778d-fd4kh                             1/1     Running   0          23s   10.244.0.2   curso-k8s-l1-control-plane   <none>           <none>
etcd-curso-k8s-l1-control-plane                      1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-n44qw                                        1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kindnet-rf64g                                        1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-xsc6h                                        1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-apiserver-curso-k8s-l1-control-plane            1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-controller-manager-curso-k8s-l1-control-plane   1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-proxy-hxjzg                                     1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kube-proxy-jp497                                     1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-proxy-m4r92                                     1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-scheduler-curso-k8s-l1-control-plane            1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
```

São as peças da Lição 0, agora distribuídas em três nós. A coluna `NODE` conta isso. O plano de controle (`etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`) vive só no nó de controle. De `kube-proxy` e `kindnet` há **um por nó**, três de cada: são as peças de que cada máquina precisa para a rede. E a coluna `IP` tem dois tipos de endereço. Os Pods do sistema que usam a rede do nó têm o `172.18.0.x` do respectivo nó. Os dois `coredns` têm `10.244.0.x`, endereços da rede **de Pods** que o `kindnet` configurou. A Lição 3 volta a isso.

Quarto, o armazenamento que o kind instalou:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  29s
```

Uma classe de armazenamento, `standard`, marcada como a padrão. Guarda os dados no disco do próprio nó. É a linha `Installing StorageClass` da criação, e a Lição 8 a usa.

### 1.9 Apagar, recriar e recuperar

#### 1.9.1 Perder o contexto

Acontece mais do que se imagina: alguém limpa o `kubeconfig`, ou apaga um contexto pensando em outro. O cluster continua vivo, mas o `kubectl` já não sabe chegar até ele. O script provoca isso:

```text
$ kubectl config delete-context kind-curso-k8s-l1
warning: this removed your active context, use "kubectl config use-context" to select a different one
deleted context kind-curso-k8s-l1 from /tmp/curso-k8s-l1.LWx1/kubeconfig

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE
```

O `kubectl` avisa que o contexto **ativo** foi apagado. A tabela fica vazia. O cluster não ficou sabendo: os três contêineres continuam rodando. O que se perdeu foi o caminho. O kind sabe reconstruí-lo, porque o cluster guarda a própria configuração:

```text
$ kind export kubeconfig --name curso-k8s-l1
Set kubectl context to "kind-curso-k8s-l1"

$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

O `kind export kubeconfig` volta a escrever o contexto do cluster no `kubeconfig` que o `KUBECONFIG` indicar e o deixa ativo. O irmão dele, `kind get kubeconfig --name curso-k8s-l1`, não escreve nada: segundo a própria ajuda, “imprime o kubeconfig do cluster” na tela. Um `kubeconfig` impresso é uma credencial impressa, então esse comando não se roda com alguém olhando nem se cola em um chat.

#### 1.9.2 Apagar

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
Deleted nodes: ["curso-k8s-l1-worker" "curso-k8s-l1-control-plane" "curso-k8s-l1-worker2"]
(borrar tardó 1 s)

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'
```

Um segundo. Apagar um cluster do kind é apagar três contêineres, e o kind ainda tira do `kubeconfig` o que havia escrito: o contexto já não existe e o ponteiro ficou vazio. Se agora fosse rodado `kubectl get nodes`, apareceria o erro `localhost:8080` que a Lição 0 ensinou a interpretar. O `docker ps` com o filtro não devolve nada.

**Sempre com `--name`.** Sem ele, o kind apaga o cluster que se chama `kind`, o padrão: “se `--name` for omitido, o kind usará o nome de contexto padrão, `kind`, e apagará esse cluster” ([kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/)). Se houver um cluster `kind` de outro curso, ele vai embora.

E uma peculiaridade útil: apagar um cluster que **não existe** não é um erro. O script faz isso de propósito, logo depois de apagá-lo:

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
```

Sem `Deleted nodes` e sem erro. O guia do kind explica: “por design, pedir para apagar um cluster que não existe não devolve um erro”. Por isso é possível colocá-lo no começo de um script, “por via das dúvidas”. Mas também quer dizer que, se o nome for digitado errado, o kind não avisa: diz `Deleting cluster` e não apaga nada. A linha `Deleted nodes` é a prova de que algo foi apagado.

#### 1.9.3 Recriar

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
…
Set kubectl context to "kind-curso-k8s-l1"
…
(recrear tardó 26 s)

$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met

$ kubectl get nodes --no-headers | wc -l
3

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

(Os passos intermediários do kind foram omitidos, iguais aos de 1.6.3; estão completos em `correr.salida.txt`.)

Vinte e seis segundos, e o cluster está como novo, com os três nós contados. Isso muda a forma de trabalhar no resto do curso. Um cluster que se refaz em meio minuto **não se conserta**: se ele ficou em um estado que não se entende, apaga-se e recria-se. O que não se perde é o que está em arquivos: `kind-curso.yaml` e, a partir da Lição 2, os manifestos. É a ideia da Lição 0 levada ao cluster inteiro: o arquivo é a verdade.

Ao terminar, o script sai e o `trap` apaga o cluster recriado e a pasta temporária. Na máquina das execuções, depois de sair, o `docker ps` não mostrava nenhum contêiner de `curso-k8s-l1` e a pasta `/tmp/curso-k8s-l1.*` já não existia.

## O erro que a gente vai ver

Esta lição tem três erros com mensagem e um sem mensagem.

**1. `ERROR: failed to create cluster: node(s) already exist`.** Criar um cluster com um nome que já existe:

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "curso-k8s-l1"
[código de salida: 1]
```

Lê-se ao pé da letra: já existem nós, ou seja, contêineres, de um cluster com esse nome. O kind não o substitui nem o conserta. Antes de fazer qualquer coisa, a pergunta é **de quem ele é**. Se é da própria pessoa, de uma execução anterior que ficou viva, basta `kind delete cluster --name curso-k8s-l1` e criar de novo. Se não se sabe de quem é, não se apaga: é o caso de uma máquina compartilhada, e por isso o script do curso para em vez de apagá-lo.

**2. `kubectl: FAILED`.** Visto em 1.3.4: o checksum do binário não coincide com o publicado. Não se instala. Baixam-se de novo o binário **e** o checksum, com a mesma versão nos dois endereços.

**3. `The connection to the server 127.0.0.1:1 was refused`.** Visto em 1.7.2: o `kubectl` falou com um servidor onde não há ninguém. A pista está no endereço da última linha. Compare-o com o do `kubectl cluster-info` do cluster: se não coincidem, o contexto não é o que se imagina. Se o endereço for `localhost:8080`, não há contexto ativo (Lição 0).

**4. O erro sem mensagem: os nós que nunca chegaram.** Com `max_user_instances = 128`, o kind imprime todos os ✓, incluindo `✓ Joining worker nodes`, e mesmo assim os nós de trabalho não se juntam. Os logs dizem `inotify_init: too many open files`. Esse erro **não foi reproduzido nesta lição**: fazê-lo exigia baixar o limite de uma máquina compartilhada em que outros clusters estavam rodando naquele momento, e baixá-lo os teria derrubado. A Lição 0 já o mediu, em 0.6.3, com as mensagens reais. Aqui ele é prevenido: mede-se e ajusta-se antes (1.4), e depois de criar espera-se `Ready` com `kubectl wait` e **contam-se** os nós com `kubectl get nodes --no-headers | wc -l`, porque o `wait` só espera os que existem (1.6.3). Se a contagem não der 3, as pistas deixadas pela Lição 0 são duas: `kubectl get pods -n kube-system` mostra algum `kube-proxy` em `Error`, e `kubectl logs -n kube-system` desse Pod diz `too many open files`. Então apaga-se o cluster, mede-se e ajusta-se o `inotify` (1.4) e cria-se de novo.

## O hábito de segurança da lição

A tabela de hábitos do curso atribui três a esta lição:

**Binários com soma de verificação.** O que roda com o usuário e com `sudo` é baixado da origem oficial, com a versão escrita e o checksum conferido antes de instalar. Um binário sem origem nem checksum, como o que chega pelo chat, não se instala, ainda que “funcione”. E ele é instalado com dono `root` e permissão `0755`, para que nenhum programa executado pelo usuário possa substituí-lo.

**A imagem do nó fixada.** A imagem de cada nó vai pelo digest, não pela tag. É o mesmo hábito do checksum, aplicado ao que o Docker baixa.

**Conferir o contexto antes de cada comando que muda algo.** Um `kubeconfig` temporário e próprio para o curso, para que o kind não mude o contexto de sempre. `kubectl config current-context` antes de agir, ou `--context` em cada comando. E o `kubeconfig` tratado como o que é, uma credencial de administrador: permissões `600`, nunca em um chat nem em um repositório, e só de fontes em que se confia.

O que os três evitam, juntos, é o da cena: não saber o que roda na máquina, nem em qual cluster se está atuando.

## O que se faz errado

**Baixar “a última”.** Um `curl` para `latest` ou para `stable.txt` dá hoje uma versão e amanhã outra. As saídas do curso deixam de coincidir e ninguém sabe por quê. Escreve-se a versão.

**Baixar o binário e o checksum separadamente, com comandos distintos.** É o caso 1 de 1.3.4: duas versões misturadas e um `FAILED` que parece um ataque. Baixam-se juntos, com a mesma versão escrita uma única vez.

**Pular o checksum “porque é o site oficial”.** O checksum confere o que chegou ao disco, não o que há no servidor. Um download interrompido pesa menos, às vezes roda e falha de formas estranhas. O checksum custa um comando.

**`sudo mv` de um binário do usuário.** Ele fica no `PATH` com o usuário como dono, e qualquer programa executado por esse usuário pode substituí-lo. O correto é `install -o root -g root -m 0755`.

**Aumentar o `inotify` com `sysctl` e esquecer.** Funciona até a próxima reinicialização. Depois o cluster falha e ninguém mais lembra por quê. O ajuste vai em um arquivo de `/etc/sysctl.d/`, com um comentário.

**Criar o cluster no `~/.kube/config` de sempre.** O kind muda o contexto ativo sem perguntar. O próximo `kubectl` digitado em outra janela, pensando no cluster do trabalho, vai falar com o do kind, ou o contrário. Um `KUBECONFIG` temporário por cluster.

**`kind delete cluster` sem `--name`.** Apaga o cluster `kind`, que pode não ser o da própria pessoa. E como apagar um que não existe não dá erro, um nome digitado errado também não avisa. Lê-se a linha `Deleted nodes`.

**Consertar um cluster do kind.** Se ele ficou em um estado que não se entende, apaga-se e recria-se em meio minuto. O que importa vive em arquivos.

## Exercícios

Os exercícios 1 e 2 são respondidos com as saídas da lição. O 3 precisa de um Mint com `kubectl` e `kind` instalados. O 4 precisa do cluster. Anote as respostas no [diário de bordo](bitacora.md) antes de olhar as soluções.

### Exercício 1 — O que aconteceu com este binário?

Uma colega rodou isto e pede ajuda:

```text
$ curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256
$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

1. Dê uma causa provável que **não** seja um ataque, e explique como ela seria verificada.
2. O que mudaria nos dois comandos para que isso não aconteça?
3. Instala-se o binário enquanto se investiga? Por quê?

### Exercício 2 — Ler o `kubeconfig`

Com a saída de `kubectl config view --minify` de 1.7.1, responda:

1. Que endereço e que porta o `kubectl` usa para chegar ao cluster? Em que outro lugar da lição essa porta aparece?
2. Como se chamam o cluster, o usuário e o contexto, e que relação têm com o nome dado ao kind?
3. O que há por trás de `DATA+OMITTED`, e por que o `kubectl` o esconde?
4. Se alguém manda o próprio `kubeconfig` pelo chat “para ver o meu cluster”, o que se faz antes de usá-lo?

### Exercício 3 — Preveja e meça o `inotify`

Sem rodar nada, preveja o que dirá o `./fig01_04.sh` em um Mint recém-instalado, antes de qualquer ajuste. Depois, rode-o. Ajuste com `sudo ./fig01_04.sh --ajustar` e rode-o outra vez sem argumentos. Em seguida, responda:

1. A previsão coincidiu? Que valores saíram antes e depois?
2. Onde o ajuste ficou escrito, e que comando demonstra isso?
3. Se a máquina for reiniciada, que valor se espera, e por quê?

### Exercício 4 — Dois clusters, dois contextos (projeto)

Em um terminal com `KUBECONFIG` temporário (1.6.1), crie o cluster do curso com `kind-curso.yaml`. No **mesmo** `KUBECONFIG`, crie outro cluster de um só nó com `kind create cluster --name curso-k8s-l1b` (sem arquivo de configuração). Depois:

1. Qual ficou como contexto ativo? Preveja antes de olhar com `kubectl config get-contexts`.
2. Sem mudar o contexto ativo, mostre os nós de **cada** cluster.
3. Apague **somente** o `curso-k8s-l1b` e confirme que o cluster do curso continua vivo e que é possível voltar a falar com ele.
4. Ao terminar, apague o cluster do curso e confirme com `docker ps` que não sobrou nenhum contêiner de nenhum dos dois.

Quando tiver feito manualmente, compare com `programas/01-instalacion-primer-cluster/ejercicio4.sh`, que faz os quatro passos com as proteções do `correr.sh`, e com a saída dele, `ejercicio4.salida.txt`. (O segundo cluster usa a imagem de nó padrão do kind v0.33.0, sem digest: é um cluster descartável, não o do curso.)

## Soluções

### Solução 1

1. **Duas versões distintas.** O binário saiu do que o `stable.txt` dizia naquele momento, e o checksum está fixo na v1.37.1. Se o `stable.txt` já diz outra versão, são arquivos de versões distintas e o checksum não pode coincidir. Confere-se com `curl -L -s https://dl.k8s.io/release/stable.txt`: se não disser `v1.37.1`, ali está a causa. Outra causa possível é um download interrompido; `ls -l kubectl` comparado com o tamanho esperado (61.886.626 bytes para a v1.37.1 em `amd64`) mostra isso.
2. Escrever a versão **uma vez**, em uma variável, e usá-la nos dois endereços, como o `fig01_01.sh`: `KUBECTL_VERSION=v1.37.1`, e `…/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl` e `…/kubectl.sha256`.
3. **Não.** Um `FAILED` não diz se o arquivo é de outra versão ou se está alterado; os dois casos se parecem (1.3.4). Enquanto um checksum não disser `OK`, o binário não entra em `/usr/local/bin`.

### Solução 2

1. `https://127.0.0.1:54589`. A mesma porta aparece no `kubectl cluster-info` e na coluna `PORTS` do `docker ps`: `127.0.0.1:54589->6443/tcp`, a porta que o Docker publicou na máquina para o `kube-apiserver`, que dentro do nó escuta na 6443. Em outra execução será outra.
2. Os três se chamam `kind-curso-k8s-l1`: `kind-` mais o nome dado com `--name`. O kind sempre os nomeia assim.
3. O certificado com o qual o `kubectl` reconhece o servidor (`certificate-authority-data`) e **a credencial de administrador** do cluster (`client-certificate-data` e `client-key-data`). O `kubectl` os oculta porque quem tiver esses dados é administrador do cluster.
4. Lê-se por inteiro antes de usá-lo, como um script: a documentação avisa que um `kubeconfig` feito de propósito pode executar código. Usa-se em um `KUBECONFIG` temporário, sem misturá-lo com o de uso diário, e lembra-se a quem o mandou que acabou de compartilhar uma credencial.

### Solução 3

1. O esperado no Mint 22, baseado no Ubuntu 24.04: `fs.inotify.max_user_instances = 128` e `FALTA AJUSTAR`. Os watches dependem do sistema e da memória, então podem sair diferentes dos 8192 que o guia do kind menciona para o Ubuntu. Depois de ajustar: 512 instâncias, pelo menos 524288 watches e `LISTO`. Na máquina virtual das execuções, também um Ubuntu 24.04, os watches já eram 1048576. Se a primeira medição já disse `LISTO`, alguém ajustou antes; procure onde com a pergunta 2.
2. Em `/etc/sysctl.d/99-kind-inotify.conf`. Demonstram isso `cat /etc/sysctl.d/99-kind-inotify.conf` e `grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/`, que deve encontrar as linhas desse arquivo (duas, ou só a de instâncias se os watches já eram mais altos) e nenhuma em outro. Se aparecer outra em `/etc/sysctl.conf`, essa vence ao reiniciar (1.4.3).
3. 512 instâncias, e watches de pelo menos 524288: na inicialização, o `systemd-sysctl` lê `/etc/sysctl.d/*.conf` e aplica o arquivo, a menos que `/etc/sysctl.conf` fixe outro valor. Se o valor tivesse sido aumentado só com `sudo sysctl …`, voltaria a 128, como teria acontecido com a máquina virtual das execuções.

### Solução 4

As quatro respostas foram medidas com o `ejercicio4.sh` (`ejercicio4.salida.txt`).

1. **`kind-curso-k8s-l1b`**, o último que foi criado: o kind deixa ativo o contexto do cluster que acabou de criar. O `get-contexts` mostra os dois, com o asterisco em `kind-curso-k8s-l1b`. Esta é exatamente a armadilha do contexto: o cluster do curso continua ali, mas já não é aquele com quem se está falando.
2. Com `--context`, que manda sobre o contexto ativo:

   ```bash
   kubectl --context kind-curso-k8s-l1 get nodes
   kubectl --context kind-curso-k8s-l1b get nodes
   ```

   O primeiro mostra três nós e o segundo um, `curso-k8s-l1b-control-plane`, com `ROLES control-plane` e `v1.37.0`.
3. `kind delete cluster --name curso-k8s-l1b`. Deve dizer `Deleted nodes: ["curso-k8s-l1b-control-plane"]`. O kind tira o contexto dele do `kubeconfig`, e o ponteiro fica vazio porque aquele era o ativo. `kubectl config get-contexts` mostra só `kind-curso-k8s-l1`, sem asterisco. `kubectl config use-context kind-curso-k8s-l1` e `kubectl get nodes` mostram os três nós do curso.
4. `kind delete cluster --name curso-k8s-l1` e depois `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` e o mesmo com `curso-k8s-l1b`. As duas respostas devem estar vazias, e na execução estiveram.

## Como sei que consegui

- [ ] `kubectl version --client` diz `Client Version: v1.37.1` e `Kustomize Version: v5.8.1`, e `kind version` diz `kind v0.33.0 go1.26.7 linux/amd64`.
- [ ] `command -v kubectl kind` diz `/usr/local/bin/kubectl` e `/usr/local/bin/kind`, e `ls -l` os mostra com dono `root root` e permissões `-rwxr-xr-x`.
- [ ] Rodar `./fig01_01.sh` em uma pasta nova e obter `kubectl: OK` e `kind-linux-amd64: OK`, com os dois checksums de 1.3.3 (em uma máquina ARM, os da release para `arm64`).
- [ ] `./fig01_04.sh` termina em `LISTO`, o `grep` dele encontra as linhas de `/etc/sysctl.d/99-kind-inotify.conf` e nenhuma em `/etc/sysctl.conf`.
- [ ] Rodar `./correr.sh` e conferir com `correr.salida.txt` o que não muda entre execuções: o `kubeconfig` vazio no início; os três nós `Ready` e contados (`3`) com `v1.37.0`, `Debian GNU/Linux 13 (trixie)` e `containerd://2.3.4`, com `ROLES <none>` nos de trabalho; um único contêiner que publica porta, `127.0.0.1:<porta>->6443/tcp`; a classe `standard (default)`; `512` nos três nós; o `ALTO` da verificação com o contexto `otro`; o erro `node(s) already exist`; o contexto recuperado com `kind export kubeconfig`; `error: current-context is not set` depois de apagar; e três nós `Ready` depois de recriar. As idades, os IPs, a porta, os sufixos dos Pods, a ordem dos nós em `kind get nodes` e `docker ps`, a frase de despedida do kind, os tempos, as contagens de `inotify` e o caminho temporário mudam a cada execução: observam-se, não se comparam.
- [ ] Ao terminar o `correr.sh`, `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` não devolve nada.

## Resumo

Responda sem olhar a lição:

1. Por que o curso instala o `kubectl` e o `kind` como binários e não com `apt` ou `snap`?
2. O que demonstra um checksum `sha256` que coincide, e o que não demonstra?
3. Que duas causas comuns produzem `kubectl: FAILED`, e o que se faz nos dois casos?
4. O que é o `inotify`, e por que três nós do kind o esgotam quando um nó sozinho não esgota?
5. Qual é a diferença entre `sudo sysctl fs.inotify.max_user_instances=512` e um arquivo em `/etc/sysctl.d/`?
6. Que três listas e que ponteiro tem um `kubeconfig`?
7. Para que serve exportar o `KUBECONFIG` para um arquivo temporário antes de criar o cluster?
8. Quem vence quando há `--context` no comando e outro `current-context` no arquivo?
9. O que o kind responde se um cluster que não existe é apagado, e por que isso é ao mesmo tempo cômodo e perigoso?
10. O contexto foi perdido, mas o cluster continua vivo. Com que comando ele é recuperado?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “Install and Set Up kubectl on Linux”](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/): o download do binário e do checksum dele, a conferência com `sha256sum --check` e as mensagens `OK` e `FAILED` dele, o `install -o root -g root -m 0755` e a regra de uma versão menor de diferença.
- [Kubernetes, “Version Skew Policy”](https://kubernetes.io/releases/version-skew-policy/) e [“Kubernetes Release Cycle”](https://kubernetes.io/releases/release/): que versões do `kubectl` servem com que cluster, e o ritmo das versões.
- [Kubernetes, “Organizing Cluster Access Using kubeconfig Files”](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/): o que é um `kubeconfig`, o que é um contexto, o `KUBECONFIG` como lista, as regras para juntar arquivos, como o contexto é escolhido e o aviso sobre arquivos de fontes não confiáveis.
- [Kubernetes, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/): os subcomandos de `kubectl config` e a ordem em que o `kubectl` carrega os arquivos.
- [kind, “Quick Start”](https://kind.sigs.k8s.io/docs/user/quick-start/): a instalação a partir do binário da release, a criação com `--name` e com arquivo de configuração, a imagem pelo hash `sha256`, a exclusão sem `--name` e que apagar um cluster inexistente não é um erro.
- [kind, “Known Issues”, “Pod errors due to too many open files”](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files): os limites de `inotify`, os valores do Ubuntu e os recomendados.
- [kind v0.33.0, página da release](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0): os binários com o `.sha256sum` e a imagem de nó `kindest/node:v1.37.0` com o digest.
- [man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html): o que é o `inotify` e o que limitam `max_user_instances` e `max_user_watches`.
- [man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html): as pastas lidas na inicialização e a ordem em que são aplicadas.
- [Linux Mint 22, notas da versão](https://www.linuxmint.com/rel_wilma.php): o Mint 22 se baseia no Ubuntu 24.04.

---

**Anterior:** [Lição 0 — O que é Kubernetes e o que NÃO é kind](00-que-es-kubernetes.md) · **Próxima:** [Lição 2 — Pods e Deployments](02-pods-deployments.md)
