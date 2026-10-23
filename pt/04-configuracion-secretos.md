# Lição 4 — Configuração e segredos

Quarta-feira, 18h40. Amanhã às 8h começa a revisão de segurança do projeto e cabe a quem está de plantão preparar o repositório. Abre-se o histórico e lá está: há três semanas alguém adicionou o token do `revisor` ao manifesto do Deployment, em uma linha `REVISOR_TOKEN`, “só para testar”. Já não está na versão de hoje, mas continua no histórico do Git, onde qualquer pessoa que tenha clonado o repositório pode lê-lo. Enquanto se pensa nisso, chega outra mensagem: a equipe de pagamentos quer que o `revisor` vigie também o serviço dela, e para acrescentá-lo à lista é preciso editar o mesmo Deployment: não é preciso reconstruir a imagem, mas sim mexer outra vez no arquivo onde o token morou. Alguém propõe resolver o primeiro problema com um Secret “que já vem em base64, então está protegido”. São 18h55 e há dois problemas que parecem um só.

Não são um só. O primeiro é **onde vive um dado que não deve ser visto**; o segundo é **como mudar a configuração de um serviço sem mexer na receita dele**. O Kubernetes tem um objeto para cada um, e esta lição ensina a usá-los sem acreditar neles mais do que prometem: um `ConfigMap` não é secreto, um `Secret` não está cifrado, e nenhum dos dois faz o programa perceber sozinho que algo mudou.

**Tempo:** 2 × 45 min

**O que se constrói:** o `revisor` configurado sem reconstruir a imagem: a lista de serviços sai do Deployment e vive em um `ConfigMap`; o token de acesso vive em um `Secret` que é montado como arquivo e não pode ser editado; e uma mudança na lista dispara sozinha um *rollout*

**O que se aprende:** `ConfigMap` como variáveis de ambiente (o `revisor` só lê variáveis) e por que alterá-lo manualmente não reinicia ninguém; `Secret` como arquivo, quem pode lê-lo e por que base64 não é cifragem; `fsGroup` e o dono dos arquivos montados; Kustomize com `configMapGenerator` e `secretGenerator`, e o *hash* que dispara o *rollout*; os Secrets imutáveis

**De onde a gente vem.** Da [Lição 3](03-services-dns.md): o `revisor` tem três réplicas atrás de um Service chamado `revisor`, o serviço de teste que falha de propósito vive atrás de outro chamado `prueba`, e já se sabe usar um Pod de depuração com `curl` (`depurar`) para falar com o `revisor` por dentro do cluster. Da [Lição 2](02-pods-deployments.md) vem a cadeia Deployment → ReplicaSet → Pod e a regra que aqui importa mais do que nunca: um *rollout* ocorre **se e somente se o template do Pod muda**. E do [curso de Docker](https://www.habil.mx/pt/cursos/docker/) vem um costume: o token do `revisor` é entregue por arquivo (`REVISOR_TOKEN_ARCHIVO`), nunca por variável, porque uma variável se lê com `docker inspect`.

**O que esta lição não faz.** Não cifra os Secrets dentro do cluster: isso se configura no `kube-apiserver` de um cluster real e a [Lição 10](10-proyecto-final.md) o coloca na lista do que falta a isto para ser pronto para produção. Tampouco decide **quem** pode ler os Secrets com permissões finas: aqui se vai ver que quem faz o curso pode, e a [Lição 7](07-aislar-permisos-red.md) dá a cada programa a sua própria conta e permissões mínimas. E o cluster ainda não sabe distinguir um `revisor` que iniciou de um que pode atender; nesta lição se vai ver quanto isso custa, e os *probes* chegam na [Lição 5](05-salud-recursos-apagado.md).

**Sobre as execuções.** Todas as saídas desta lição foram obtidas em 21 de outubro de 2026 com o `kind` v0.33.0, o `kubectl` v1.37.1 (que traz dentro o Kustomize v5.8.1) e a imagem de nó `kindest/node:v1.37.0` fixada pelo digest, no cluster de três nós da Lição 1, aqui chamado `curso-k8s-l4`. A máquina foi um Mac com processador ARM e Docker Engine 29.2.1 dentro de uma máquina virtual Linux (Colima), **não** Linux Mint, que é o sistema de referência do curso. O que muda no Mint: a arquitetura, os sufixos aleatórios de Pods e ReplicaSets, os IPs, as idades, o nó onde cai cada réplica, o tamanho que o `tmpfs` reporta e, sobretudo, **o token e o nome do Secret**, que são novos em cada execução (o nome do ConfigMap, em compensação, deve sair idêntico: `revisor-config-t6cm6872fk`). Um detalhe a mais: o `wc -c` do macOS preenche o número com espaços à esquerda (`      33`) e o do Linux não (`33`). O percurso completo está em [`programas/04-configuracion-secretos/`](../programas/04-configuracion-secretos): o `correr.sh` cria o cluster, carrega nele as duas imagens do curso, deixa-o como terminou a Lição 3, percorre a lição em ordem, executa os Exercícios 1 a 3 (o 3, em um namespace descartável que apaga ao terminar) e apaga o cluster. Levou 2 minutos e 43 segundos; criar o cluster e esperar que ficasse pronto foram 42 segundos, e apagá-lo, 4. A saída é o `correr.salida.txt`. O script gera o próprio token, apaga-o ao terminar e deixa o `kustomization.yaml` como estava, mesmo que pare no meio; e se o `kind create cluster` falhar, para ali com código 1, em vez de continuar sobre um cluster que não existe.

## Ao terminar, a gente vai conseguir

- Tirar uma variável de ambiente de um Deployment para um `ConfigMap` e ler em `kubectl describe pod` de onde sai cada variável.
- Demonstrar com o relatório do `revisor` que alterar um `ConfigMap` manualmente não muda as variáveis dos Pods que já estão rodando, e explicar por quê.
- Escrever um `kustomization.yaml` com `configMapGenerator` e `secretGenerator`, ver com `kubectl kustomize` o que ele vai gerar e aplicá-lo com `kubectl apply -k`.
- Prever que uma mudança no conteúdo de um ConfigMap gerado dá outro sufixo ao nome dele (e que o mesmo conteúdo de antes devolve exatamente o mesmo nome), e conferir com `kubectl diff -k` que essa mudança de nome dispara um *rollout*.
- Montar um `Secret` como arquivo com `defaultMode: 0440` e `fsGroup`, e localizar esse arquivo no nó, em um `tmpfs`.
- Decodificar um Secret com `base64 -d` para demonstrar que base64 não é cifragem, e mudar o conteúdo de um Secret imutável da única forma possível: com outro Secret.
- Reconhecer o `permission denied` de um Secret ilegível e o `couldn't find key` de uma chave mal escrita, e dizer qual dos dois derruba o serviço e por quê.

## O porquê antes do como

Até a Lição 3, a lista de serviços que o `revisor` verifica estava escrita dentro do Deployment, em uma linha `value: "prueba http://prueba:9000/ 2s"`. Funciona, mas junta duas coisas que mudam em ritmos diferentes. A **receita** do serviço (que imagem, quantas réplicas, que segurança) muda pouco e quem a cuida é quem opera o cluster. A **configuração** (que serviços verificar, com que tempo limite) muda com frequência e às vezes é pedida por outra equipe. Se vivem no mesmo arquivo, cada mudança da lista é uma mudança da receita, com a sua revisão e o seu risco. A [documentação de ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) diz assim: um ConfigMap permite “separar a configuração específica do ambiente das imagens de contêiner, para que as aplicações sejam facilmente portáteis”.

O token é outro assunto. Não é configuração que alguém queira ler: é uma chave. Escrito no Deployment, viaja com o manifesto para o Git, para cada cópia do repositório e para cada tela onde alguém faça `kubectl get deployment -o yaml`. O Kubernetes tem um objeto à parte para isso, o **Secret**, e esta lição mostra com saídas reais o que ele protege e o que não. Porque o Secret tem uma fama que não conquistou: muita gente acredita que, como os dados dele aparecem em base64, estão cifrados. Não estão, e isso se comprova com um único comando.

E há uma terceira pergunta, a mais sutil: **quando o programa percebe que a configuração dele mudou?** O `revisor` lê as variáveis de ambiente uma única vez, ao iniciar. O Kubernetes não reinicia ninguém porque um ConfigMap mudou. Se isso não for visto, muda-se a configuração, vê-se o objeto alterado no cluster e acredita-se que está pronto, quando os Pods continuam trabalhando com a lista antiga. A solução desta lição é uma ferramenta que já vem dentro do `kubectl`, o Kustomize, e um truque tão simples que parece trapaça: mudar o **nome** do ConfigMap toda vez que o conteúdo dele muda.

A lição tem sete partes de conceitos e depois as seções de sempre:

1. **A configuração escrita no Deployment** (4.1): o ponto de partida.
2. **Um ConfigMap escrito à mão** (4.2) e como se conecta a uma variável.
3. **Mudar um ConfigMap não reinicia ninguém** (4.3), medido.
4. **O token como Secret, e por que como arquivo** (4.4).
5. **Kustomize: os geradores e o *hash*** (4.5).
6. **base64 não é cifragem** (4.6).
7. **Mudar a lista dispara o *rollout*** (4.7).

Este é o destino. No final de 4.5, o `revisor` é configurado por fora, e cada objeto leva no nome o digest do seu conteúdo:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

## Os conceitos

### 4.0 O cluster, como terminou a Lição 3

Esta lição usa o seu próprio cluster, `curso-k8s-l4`, com a configuração de três nós da Lição 1, recém-criado. Cria-se assim, a partir da raiz do repositório do curso, com o mesmo cuidado aprendido na Lição 1, e carregam-se nele as duas imagens do curso de Docker:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l4.XXXX)/kubeconfig"
# curso-k8s-l4 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l4 --config programas/04-configuracion-secretos/kind-curso.yaml
# Debe decir kind-curso-k8s-l4. Si dice otra cosa, no sigas.
kubectl config current-context
kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l4
# El resto de la lección se trabaja desde la carpeta de sus programas.
cd programas/04-configuracion-secretos
```

O `export` só vale naquele terminal. Se for aberto outro, repete-se o `export` com o mesmo caminho, ou o `kubectl` falará com outro cluster. E se o `kind create cluster` falhar, não prosseguir: ler a mensagem dele, porque tudo o que viesse depois supõe um cluster que não existe.

Em seguida aplica-se o que a Lição 3 deixou. Os arquivos estão na pasta de programas desta lição: o Deployment de partida, em `punto-de-partida/revisor-deployment.yaml`, e os dois Services, o Deployment do `prueba` e o Pod `depurar`, sem alterações. As saídas desta seção são da execução do `correr.sh`, que faz exatamente isso:

```text
$ kubectl config current-context
kind-curso-k8s-l4

$ kubectl apply -f punto-de-partida/revisor-deployment.yaml -f revisor-service.yaml -f prueba-deployment.yaml -f prueba-service.yaml -f depurar.yaml
deployment.apps/revisor created
service/revisor created
deployment.apps/prueba created
service/prueba created
pod/depurar created

$ kubectl get deployment,service
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           9s
deployment.apps/revisor   3/3     3            3           9s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
service/kubernetes   ClusterIP   10.96.0.1      <none>        443/TCP    46s
service/prueba       ClusterIP   10.96.199.61   <none>        9000/TCP   9s
service/revisor      ClusterIP   10.96.4.106    <none>        80/TCP     9s
```

Como sempre, o primeiro comando pergunta a que cluster se está falando. Nesta lição vão ser criados e apagados Secrets, e `kind-curso-k8s-l4` é a única resposta que deixa seguir. **Repetir `kubectl config current-context` antes de cada comando que altera algo** (`apply`, `patch`, `delete`, `rollout restart`) e antes de cada exercício: o script faz isso antes de cada `kubectl`, e quem faz o curso também. Para não encher a lição de linhas iguais, só aparece nos pontos onde mais importa.

### 4.1 A configuração escrita dentro do Deployment

Assim está hoje a configuração do `revisor`:

```text
$ kubectl get deployment revisor -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
[{"name":"REVISOR_SERVICIOS","value":"prueba http://prueba:9000/ 2s"}]

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

Uma variável, com o valor escrito ali mesmo (`value`). E o `/api/estados` responde a qualquer um que o peça: o `revisor` ainda não tem token, então não o exige. Essa tabela é o **instrumento de medição** em toda a lição. O `revisor` não tem *shell*, então não é possível entrar para ver as variáveis dele com `env`; mas o relatório dele lista exatamente os serviços que leu de `REVISOR_SERVICIOS` ao iniciar. Se a tabela diz `prueba` e nada mais, o `revisor` está trabalhando com essa lista, diga o que disser qualquer objeto do cluster.

Uma pergunta para guardar: o que seria preciso fazer para acrescentar um serviço à lista? Editar este Deployment. Isso muda o template dele, então dispara um *rollout* (a regra da Lição 2). Funciona. O problema não é técnico, é de quem mexe em quê.

### 4.2 Um ConfigMap escrito à mão

#### 4.2.1 O objeto

Um **ConfigMap** é, segundo a documentação dele, “um objeto da API usado para guardar dados não confidenciais em pares de chave e valor”. As duas palavras que importam são **não confidenciais**: a mesma página traz um aviso em destaque, “ConfigMap não oferece sigilo nem cifragem”, e manda usar um Secret se o dado for confidencial. E outro aviso: o que se guardar em um ConfigMap não pode passar de 1 MiB. É para configuração, não para arquivos grandes.

Este é o primeiro, escrito à mão. É um **programa**: `programas/04-configuracion-secretos/fig04_01.configmap.yaml`.

```yaml
# fig04_01.configmap.yaml — Lección 4, sección 4.2: un ConfigMap escrito a mano.
# Guarda la lista de servicios que el revisor revisa, fuera del Deployment. Tiene
# un nombre FIJO (revisor-config): la sección 4.3 muestra por qué eso es un
# problema y la 4.5 lo resuelve con el generador de Kustomize.
apiVersion: v1
kind: ConfigMap
metadata:
  name: revisor-config
  labels:
    app: revisor
data:
  REVISOR_SERVICIOS: "prueba http://prueba:9000/ 2s"
```

Lê-se como qualquer objeto: `apiVersion: v1` (o grupo central da API, como os Pods), `kind: ConfigMap`, um nome e um rótulo. O novo é `data`: um mapa de chaves e valores, todos texto. Aqui há uma única chave, `REVISOR_SERVICIOS`, e tem o mesmo nome da variável de propósito: assim ninguém precisa traduzir entre dois nomes.

```text
$ kubectl apply -f fig04_01.configmap.yaml
configmap/revisor-config created

$ kubectl get configmap revisor-config -o jsonpath='{.data}{"\n"}'
{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s"}
```

(Antes desse `apply`, `kubectl config current-context` disse `kind-curso-k8s-l4`.) Até aqui o ConfigMap existe, mas ninguém o usa. Um ConfigMap não faz nada por si só: é um dado guardado no cluster, esperando que um Pod o peça.

#### 4.2.2 De ConfigMap a variável

A documentação dá quatro formas de usar um ConfigMap a partir de um Pod: como argumentos do comando do contêiner, como **variáveis de ambiente**, como **arquivos** em um volume somente leitura, ou lendo-o com código que fale com a API do Kubernetes. O `revisor` decide qual serve: só lê variáveis de ambiente (`REVISOR_SERVICIOS`, `REVISOR_PUERTO`, `REVISOR_REPORTE` e `REVISOR_TOKEN_ARCHIVO`). Um arquivo com a lista não serviria de nada, porque ele não o procuraria. Por isso, neste curso, **o ConfigMap vai como variável**.

Este Deployment (`fig04_02.revisor-con-configmap.yaml`, outro **programa**) é o da Lição 3 com uma única diferença. Onde antes dizia `value: "prueba http://prueba:9000/ 2s"`, agora diz de onde tirar o valor:

```yaml
        env:
        - name: REVISOR_SERVICIOS
          valueFrom:
            configMapKeyRef:
              name: revisor-config
              key: REVISOR_SERVICIOS
```

Leia-se como uma frase: a variável `REVISOR_SERVICIOS` toma o valor (`valueFrom`) da chave `REVISOR_SERVICIOS` do ConfigMap chamado `revisor-config`. O resto do arquivo não muda, e dá para conferir com `diff punto-de-partida/revisor-deployment.yaml fig04_02.revisor-con-configmap.yaml`.

Existe outra forma, `envFrom`, que converte **todas** as chaves de um ConfigMap em variáveis de uma vez. É cômoda, mas esconde que variáveis o contêiner recebe: seria preciso ir ver o ConfigMap para saber. Como o `revisor` ignora em silêncio as variáveis que não conhece, aqui convém `configMapKeyRef`: cada variável fica escrita, com seu nome, no Deployment.

```text
$ kubectl apply -f fig04_02.revisor-con-configmap.yaml
deployment.apps/revisor configured

$ kubectl describe pod revisor-66db8c7755-6mwlw | sed -n '/Environment:/,/Mounts:/p'
    Environment:
      REVISOR_SERVICIOS:  <set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>  Optional: false
    Mounts:

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

`configured`: o template mudou, então houve *rollout* e há Pods novos. O `kubectl describe pod` mostra a variável e, em vez do valor, **de onde ela sai**: “definida com a chave `REVISOR_SERVICIOS` do ConfigMap `revisor-config`”. `Optional: false` quer dizer que, se esse ConfigMap ou essa chave não existirem, o contêiner não inicia. Isso será provocado no Exercício 1. A tabela continua igual a antes, como deve: mesma lista, outro lugar.

### 4.3 Mudar um ConfigMap não reinicia ninguém

Agora o pedido da cena: acrescentar um serviço. Para não depender de nada fora do cluster, o “serviço novo” é o mesmo `prueba` com outro nome, `lento`, e um tempo limite mais curto, de meio segundo. O que importa é que apareça uma linha nova na tabela.

Antes de mudar qualquer coisa, conferir o contexto (`kubectl config current-context` → `kind-curso-k8s-l4`) e olhar os ReplicaSets. O de cima é o do `fig04_02`; o de baixo, o da Lição 3, em `0 0 0`:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       3s
revisor-697fb84f97   0         0         0       12s

$ kubectl patch configmap revisor-config -p '{"data":{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms"}}'
configmap/revisor-config patched
(30 s después)
```

O `kubectl patch` muda somente os campos que lhe são dados. Aqui deu à chave uma lista com dois serviços separados por vírgula. O cluster diz `patched`: o ConfigMap mudou. Trinta segundos depois:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       34s
revisor-697fb84f97   0         0         0       43s

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           4ms  200
```

Nenhum ReplicaSet novo, e a tabela continua dizendo somente `prueba`. **O ConfigMap mudou e o `revisor` não percebeu.** Não é um atraso que se resolva esperando: vai continuar assim até que o Pod renasça.

A razão tem duas metades, e convém ver as duas.

**A metade do Kubernetes.** Uma variável de ambiente é fixada quando o contêiner inicia. É assim que as variáveis funcionam no Linux: o processo recebe o ambiente ao nascer e ninguém o altera depois, por fora. A documentação de ConfigMaps diz sem rodeios: “os ConfigMaps consumidos como variáveis de ambiente não são atualizados automaticamente e exigem reiniciar o Pod”. E o Deployment não tem por que reiniciar nada: o template dele diz “pegue a variável do ConfigMap `revisor-config`”, e isso não mudou. Mudou o conteúdo do ConfigMap, não o template, então a regra “se e somente se” da Lição 2 não se cumpre. Não há *rollout*.

**A metade do `revisor`.** Mesmo que o Kubernetes pudesse mudar a variável, não adiantaria: o `revisor` lê a configuração uma única vez, ao iniciar. O código dele (`cmd/revisor/config.go`, do curso de Docker) monta a lista em uma função que é chamada no início e nunca mais.

E se o ConfigMap fosse montado como arquivo? A documentação diz que então sim ele é atualizado sozinho, “eventualmente”, com o atraso da sincronização do `kubelet`. Mas isso só ajuda um programa que volte a ler o arquivo, e o `revisor` não o faz. Muitos programas reais tampouco. Por isso a pergunta correta nunca é “o ConfigMap mudou?”, mas “o programa já está rodando com a configuração nova?”. E essa pergunta se responde com o programa, não com o ConfigMap: aqui, com a tabela.

A saída manual é a da Lição 2:

```text
$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
lento     OK           1ms  200
prueba    OK           2ms  200

$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>
```

Agora sim: dois serviços. O `rollout restart` acrescentou a anotação `restartedAt` ao template, o template mudou e os Pods novos leram a lista nova ao nascer. Revisão 3.

Funciona, mas depende de que alguém **se lembre** de reiniciar. E repare no que não fica registrado em lugar nenhum: o histórico do Deployment diz que houve três revisões, mas nenhuma diz que a terceira foi por uma mudança de lista. Se amanhã alguém fizer `rollout undo` para voltar à revisão 2, volta ao template da revisão 2, que aponta para o mesmo ConfigMap `revisor-config`… que já tem a lista nova. Não há como voltar à configuração antiga, porque a configuração antiga já não existe. A seção 4.5 resolve as duas coisas com uma única ideia.

### 4.4 O token: um Secret, e como arquivo

#### 4.4.1 O que é um Secret

Um **Secret**, segundo a [documentação](https://kubernetes.io/docs/concepts/configuration/secret/) dele, é “um objeto que contém uma pequena quantidade de dados sensíveis, como uma senha, um token ou uma chave”. Parece-se muito com um ConfigMap: também é um mapa de chaves e valores, também tem um teto de 1 MiB, e também é usado como variável ou como arquivo. As diferenças estão no tratamento que o cluster lhe dá:

- **Só viaja para os nós que o necessitam.** Um Secret é enviado a um nó somente se um Pod desse nó o pedir.
- **No nó, se montado como arquivo, vive em memória.** O `kubelet` guarda a cópia em um `tmpfs`, um sistema de arquivos em RAM, “para que o dado confidencial não seja escrito em armazenamento durável”; e a apaga quando o Pod que a usava vai embora. Essa proteção é do volume: se o Secret for consumido como variável de ambiente, não há `tmpfs` no meio, porque o valor viaja na definição do processo que o *runtime* recebe. O `tmpfs` se verá em 4.5.6.
- **Pode ser tratado à parte nas permissões.** Uma regra de RBAC (Lição 7) pode permitir ler ConfigMaps e não Secrets.

E uma coisa que **não** faz: cifrar. A mesma página abre com um aviso em destaque que convém ler completo: “Os Secrets do Kubernetes são guardados, por padrão, sem cifrar no armazenamento de dados do servidor da API (etcd). Qualquer pessoa com acesso à API pode ler ou modificar um Secret, e também qualquer pessoa com acesso ao etcd. Além disso, qualquer pessoa autorizada a criar um Pod em um namespace pode usar esse acesso para ler qualquer Secret desse namespace”. A seção 4.6 coloca isso à prova.

#### 4.4.2 O token se gera, não se escreve

O token do `revisor` não é um valor que se escolhe, nem um que se copia de um documento. É gerado, ao acaso, cada vez que é preciso um novo:

```text
$ (umask 077; openssl rand -hex 16 > token.txt)

$ ls -l token.txt | cut -d' ' -f1
-rw-------

$ wc -c < token.txt
      33

$ cat .gitignore
token.txt

$ git check-ignore -v token.txt
programas/04-configuracion-secretos/.gitignore:1:token.txt	token.txt
```

O `openssl rand -hex 16` pede 16 bytes ao acaso e os escreve em hexadecimal: 32 caracteres, mais a quebra de linha que ele acrescenta no final. Por isso o `wc -c` conta 33. Os parênteses e o `umask 077` mudam a máscara de permissões **somente para esse comando**: o arquivo nasce com permissão `0600` (`-rw-------`), que só o dono pode ler, em vez do `0644` que a máscara habitual deixaria, legível por qualquer usuário da máquina. É o mesmo token que, dentro do Pod, terá `0440`: cuida-se dele igual na máquina local e no cluster. Essa quebra de linha não atrapalha: o `revisor`, ao ler o arquivo, tira os espaços e quebras das pontas (`strings.TrimSpace`, no código dele).

Os dois últimos comandos são o hábito desta lição. O `.gitignore` diz que `token.txt` **não** entra no repositório, e o `git check-ignore -v` confirma, dizendo que arquivo e que linha o excluem. A cena começou com um token no histórico do Git, e esta é a forma de isso não voltar a acontecer: o arquivo existe na máquina local, o cluster o recebe, e o Git nunca o vê. Se se trabalhar fora de um repositório, o `git check-ignore` dirá que não é um repositório; a regra continua valendo para o dia em que for.

#### 4.4.3 Por que como arquivo e não como variável?

Um Secret pode ser passado como variável de ambiente (com `secretKeyRef`, gêmeo do `configMapKeyRef`). Este curso não o faz, e não é por gosto:

- **Uma variável é herdada.** Todo processo que o contêiner lança recebe uma cópia do ambiente dele. Um arquivo não é copiado para cada processo filho: é preciso ir abri-lo de propósito, e só pode abri-lo quem tiver permissão.
- **Uma variável é impressa sem querer.** Em um despejo de erros, em um `env` de depuração, no log de um programa que, ao falhar, escreve “iniciei com esta configuração”. O [guia de boas práticas de Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) pede a cada aplicação que, depois de ler o Secret, evite “registrar o dado em claro”.
- **O próprio `revisor` pede.** Se recebe o token em `REVISOR_TOKEN`, inicia, mas escreve no log um aviso: `el token llegó por REVISOR_TOKEN: cualquiera con docker inspect lo puede leer; usa REVISOR_TOKEN_ARCHIVO`. O programa dele já votou.

Então o `revisor` recebe duas coisas: o Secret montado como arquivo em `/secretos/token`, e uma variável normal, não secreta, que diz onde procurá-lo: `REVISOR_TOKEN_ARCHIVO=/secretos/token`. O caminho não é um segredo; o conteúdo, sim.

### 4.5 Kustomize: os geradores e o *hash*

#### 4.5.1 A ideia: o nome muda quando o conteúdo muda

Lembrar dos dois problemas de 4.3: a mudança de ConfigMap não disparava um *rollout*, e não havia como voltar à configuração antiga. Os dois vêm do mesmo lugar: o ConfigMap tem um **nome fixo**, então o template do Deployment nunca muda, ainda que mude o que há dentro.

Agora imagine que o ConfigMap se chamasse diferente conforme o conteúdo: `revisor-config-t6cm6872fk` com uma lista, `revisor-config-7fbkh2926f` com outra. Mudar a lista criaria **outro** ConfigMap, e o Deployment teria de apontar para o nome novo. O template dele mudaria, e a regra da Lição 2 faria o resto: *rollout*. E o ConfigMap antigo continuaria ali, intacto, para que uma revisão antiga do Deployment aponte para ele. Isso tem um custo: o Kustomize não apaga os antigos, então eles vão se acumulando. No curso não importa, porque no final se apaga o cluster inteiro; em um que viva meses, seria preciso limpar manualmente (`kubectl delete configmap <nome>`) os que nenhuma revisão conserve mais, e o mesmo com os Secrets.

Fazer isso à mão seria um tormento: calcular um nome, escrevê-lo em dois lugares, nunca errar. Para isso existe o **Kustomize**, que vem dentro do `kubectl` desde a versão 1.14 (`kubectl kustomize` e `kubectl apply -k`); neste curso é a v5.8.1, a que o `kubectl` v1.37.1 traz. O [guia do Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) explica em uma frase: os ConfigMaps e Secrets gerados “levam um sufixo com o *hash* do conteúdo. Isso garante que um ConfigMap ou Secret novo seja gerado quando o conteúdo muda”. E o Kustomize não gera só o nome: conhece os campos dos objetos do Kubernetes que apontam para um ConfigMap ou um Secret (`configMapKeyRef`, `secretKeyRef`, `envFrom`, os `volumes`) e neles põe o nome novo. Não é uma substituição de texto: uma menção a `revisor-config` em uma anotação ou em um campo de um recurso estendido não é atualizada sozinha.

#### 4.5.2 O `kustomization.yaml`

O Kustomize lê um arquivo chamado `kustomization.yaml` em uma pasta. Este é o da lição, um **programa**:

```yaml
# kustomization.yaml — Lección 4. Se aplica con: kubectl apply -k .
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- revisor-deployment.yaml
- revisor-service.yaml
- prueba-deployment.yaml
- prueba-service.yaml
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

Três blocos:

- **`resources`**: os manifestos que já se conhecem, tal qual. O Kustomize os lê, os ajusta e os entrega juntos. O `depurar.yaml` não está na lista de propósito: é uma ferramenta de depuração, não parte do serviço.
- **`configMapGenerator`**: “gere um ConfigMap chamado `revisor-config`, com esta chave e este valor”. `literals` é para valores escritos ali mesmo, com a forma `CHAVE=valor`. A lista de serviços já não está no Deployment: está aqui, em uma linha que pode ser revisada sozinha.
- **`secretGenerator`**: “gere um Secret chamado `revisor-token`, com uma chave `token` cujo conteúdo é o do arquivo `token.txt`”. A forma `token=token.txt` separa o nome da chave (à esquerda) do arquivo de onde sai (à direita). Sem o `token=`, a chave se chamaria como o arquivo, `token.txt`. E `options: immutable: true` marca o Secret como imutável; a seção “O hábito de segurança” explica por quê.

Repare no que **não** está neste arquivo: o token. O `kustomization.yaml` sim vai para o repositório, e apenas diz de onde tirá-lo.

#### 4.5.3 O Deployment final

O Deployment da lição é o `revisor-deployment.yaml`, um **programa**. Em relação ao `fig04_02` mudam três coisas: o token montado como arquivo, a variável que diz onde está, e uma linha nova no `securityContext` do Pod:

```yaml
# revisor-deployment.yaml — Lección 4: la configuración llega de un ConfigMap
# (por variable) y el token de un Secret (por archivo, inmutable).
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

Percorra-se de baixo para cima, seguindo a viagem do token:

- **O volume `token`**, do tipo `secret`, toma o Secret `revisor-token` e converte cada chave em um arquivo. O Secret tem uma chave, `token`, então o volume terá um arquivo, `token`.
- **`defaultMode: 0440`**: as permissões desse arquivo. `0440` em octal é “o dono pode ler, o grupo pode ler, os demais nada, e ninguém escreve”. Se não for posto, o [guia para distribuir credenciais](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) diz que se usa `0644`, que deixa todos lerem. Aqui não há outros usuários dentro do contêiner, mas a permissão mínima não custa nada.
- **A montagem** põe esse volume em `/secretos`, com `readOnly: true`. Assim, o arquivo fica em `/secretos/token`.
- **A variável `REVISOR_TOKEN_ARCHIVO`** diz ao `revisor` esse caminho. É um `value` normal: o caminho não é secreto.
- **`fsGroup: 65532`**, em cima, no `securityContext` do Pod. É a linha mais curta e a que mais custa entender, então tem a sua própria explicação em 4.5.6.

Repare em `name: revisor-config` e `secretName: revisor-token`: aqui vão **sem** *hash*. Escrevem-se assim, com o nome base, e o Kustomize os troca pelo nome gerado ao montar o resultado. Se o nome fosse escrito com *hash*, teria de ser mudado manualmente a cada mudança de lista, que é justamente o que se queria evitar.

#### 4.5.4 Ver antes de aplicar

`kubectl kustomize .` monta o resultado e o imprime, **sem** tocar no cluster. É a forma de ver o que vai acontecer:

```text
$ kubectl kustomize . | grep -E '^  name: revisor-(config|token)'
  name: revisor-config-t6cm6872fk
  name: revisor-token-bh266kt42m

$ kubectl kustomize . | grep -B4 -A3 '^kind: Secret'
apiVersion: v1
data:
  token: NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK
immutable: true
kind: Secret
metadata:
  name: revisor-token-bh266kt42m
type: Opaque
```

Ali estão os nomes gerados: `revisor-config-t6cm6872fk` e `revisor-token-bh266kt42m`. O sufixo do ConfigMap depende somente do conteúdo dele, então em outra máquina deve sair o mesmo, `t6cm6872fk`. O do Secret depende do token, que é novo em cada execução; o de outra máquina será outro.

E ali está o Secret como o cluster vai recebê-lo. `type: Opaque` é o tipo genérico, “dados quaisquer”. `immutable: true` vem das `options`. E em `data`, a chave `token` com um valor que não se parece com o token. Guardar essa cadeia: em 4.6 ela será desmontada.

#### 4.5.5 Aplicar

Conferir o contexto e aplicar:

```text
$ kubectl config current-context
kind-curso-k8s-l4

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

`apply -k .` é `apply` com Kustomize: monta a pasta e aplica o resultado. O Kustomize ordena os objetos para que o ConfigMap e o Secret sejam criados **antes** do Deployment que os usa. Os Services e o `prueba` não mudaram (`unchanged`). O `revisor` sim (`configured`): o template dele agora aponta para nomes novos e monta um volume novo.

Agora olhar o que ficou no cluster. Para os Secrets usa-se um **seletor de campo** (`--field-selector`), que filtra por um campo do objeto e não pelos rótulos dele: `type!=kubernetes.io/service-account-token` deixa de fora os Secrets do tipo “token de conta de serviço”, se existirem, para ver só os do curso:

```text
$ kubectl get configmap
NAME                        DATA   AGE
kube-root-ca.crt            1      77s
revisor-config              1      41s
revisor-config-t6cm6872fk   1      4s

$ kubectl get secret --field-selector type!=kubernetes.io/service-account-token
NAME                       TYPE     DATA   AGE
revisor-token-bh266kt42m   Opaque   1      4s

$ kubectl delete configmap revisor-config
configmap "revisor-config" deleted from default namespace
```

Três ConfigMaps. `kube-root-ca.crt` é posto pelo Kubernetes em cada namespace, com o certificado do cluster; não é do curso. `revisor-config-t6cm6872fk` é o gerado. E `revisor-config`, o que foi escrito à mão em 4.2, **continua ali**. O `kubectl apply` cria e atualiza o que recebe; não apaga o que não recebe. Ninguém mais o usa, então foi apagado manualmente. Lembrar disso em 4.7 e no Exercício 2: cada mudança deixa para trás o objeto anterior.

Agora o Pod por dentro:

```text
$ kubectl describe pod revisor-f6dd4cb4d-cg7tb | sed -n '/Environment:/,/Conditions:/p'
    Environment:
      REVISOR_SERVICIOS:      <set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config-t6cm6872fk'>  Optional: false
      REVISOR_TOKEN_ARCHIVO:  /secretos/token
    Mounts:
      /datos from datos (rw)
      /secretos from token (ro)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-2gqd7 (ro)
Conditions:
```

`config map 'revisor-config-t6cm6872fk'`: o Deployment já aponta para o nome com *hash*, embora no arquivo tenha sido escrito `revisor-config`. O Kustomize o trocou ao montar. E em `Mounts`, `/secretos from token (ro)`: o Secret montado, somente leitura. A terceira montagem é a credencial da conta de serviço que a Lição 2 deixou anotada como dívida; a Lição 7 a remove.

E o `revisor`? Agora tem token, então o exige:

```text
$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' http://revisor/api/estados
401

$ kubectl exec depurar -- curl -s http://revisor/api/estados
{"error":"falta el token o no es válido"}

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200

$ kubectl exec deployment/revisor -- /revisor healthcheck
sano
```

Sem token, `401` e uma mensagem clara. Com o cabeçalho `Authorization: Bearer …`, a tabela. Repare nas aspas do terceiro comando: `$(cat token.txt)` está entre aspas duplas, então o *shell* o substitui **na máquina local**, antes de mandar o comando ao Pod. O token nunca aparece escrito no histórico de comandos, só o `cat`. Aparece, sim, enquanto dura o comando, como argumento do processo: em um `ps` da máquina local e dentro do `depurar`. Para um exercício local basta; em um cluster compartilhado, o token não se passa pela linha de comando. E o `/salud` (o que o `healthcheck` consulta) não pede token, de propósito: os *probes* da Lição 5 vão chamá-lo sem credenciais.

A tabela voltou a dizer somente `prueba`, e isso também está correto: a lista do `kustomization.yaml` tem um único serviço. O `lento` acrescentado manualmente em 4.3 vivia no ConfigMap que acabou de ser apagado.

#### 4.5.6 O Secret, visto a partir do nó

Onde está fisicamente o arquivo `/secretos/token`? O `revisor` não tem *shell* para ir olhá-lo, mas o nó do kind tem, e o `kubelet` guarda os volumes de cada Pod em uma pasta com o identificador (`uid`) do Pod. Para este Pod, no nó `curso-k8s-l4-worker`:

```text
$ docker exec curso-k8s-l4-worker ls -ln /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 65532 33 Oct 21 13:27 token

$ docker exec curso-k8s-l4-worker sh -c 'mount | grep a415d22b-9837-4123-a7d9-82b1baf9435a | grep -E "secret/token "'
tmpfs on /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token type tmpfs (rw,relatime,size=16342676k,inode64,noswap)
```

O nome do nó e o `uid` do Pod saem de `kubectl get pod <pod> -o jsonpath='{.spec.nodeName}'` e `'{.metadata.uid}'`; o script os procura sozinho. Duas coisas a conferir com os próprios olhos:

- **`-r--r----- 1 0 65532 33 … token`**: o arquivo tem as permissões `0440` que foram pedidas (`r--r-----`), mede 33 bytes (o token com a sua quebra de linha), o dono dele é o usuário `0` (`root`) e o grupo é o **65532**. Esse grupo foi posto pelo `fsGroup`.
- **`tmpfs`**: a pasta do volume é um sistema de arquivos em memória, como promete a documentação. O token não foi escrito no disco do nó.

A pasta `..data` é um detalhe de como o `kubelet` atualiza os volumes de Secrets: o arquivo `token` que o contêiner vê é um link para `..data/token`, e, quando o Secret muda, o `kubelet` prepara uma pasta nova e troca o link de uma vez. Com um Secret imutável, como este, isso nunca vai acontecer.

Agora juntar a linha do `ls` com o `securityContext`. O `revisor` roda como usuário 65532 e grupo 65532. O arquivo é do `root` e do grupo 65532, com permissão de leitura para o grupo. O `revisor` o lê **por ser do grupo**. Sem `fsGroup`, o grupo do arquivo seria outro e o `revisor` não teria como lê-lo. O [guia do `securityContext`](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) descreve o `fsGroup` assim: os processos do contêiner passam a fazer parte desse grupo como grupo adicional, e “os volumes que admitem administração de donos são modificados para pertencer ao GID indicado pelo `fsGroup`”. A seção “O erro que se vai ver” mostra o que acontece se isso for ignorado, e não é o que se esperaria.

### 4.6 base64 não é cifragem

Pegar a cadeia que foi vista no Secret e a do cluster:

```text
$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}{"\n"}'
NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK

$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}' | base64 -d
433c7adfa6fc6fc3d03676b7f5c2339e

$ cat token.txt
433c7adfa6fc6fc3d03676b7f5c2339e
```

(O `grep revisor-token | xargs` encontra o Secret mesmo que o nome dele mude a cada execução.) Um comando, sem chave, sem senha, sem nada a adivinhar: `base64 -d` devolve o token completo, idêntico ao arquivo. **base64 não é cifragem.** É uma **codificação**: uma forma de escrever qualquer sequência de bytes usando somente letras, números, `+` e `/`, mais um `=` de preenchimento no final quando necessário (como o `eA==` mais adiante), para que caiba em um arquivo de texto como um YAML. Cifrar quer dizer que, sem uma chave, não se pode ler. Codificar quer dizer que se pode ler com uma tabela pública. O guia de boas práticas diz em uma linha: “a codificação base64 **não** é um método de cifragem; não dá nenhuma confidencialidade adicional sobre o texto puro”. E avisa do erro da cena: se um manifesto de Secret for guardado em um repositório, “o segredo fica ao alcance de todos os que puderem ler o manifesto”.

Por que existe então o base64? Porque um Secret pode guardar qualquer coisa, também dados binários, como um certificado ou uma chave, e um YAML é texto. O base64 é o envelope que permite meter bytes em um arquivo de texto. Não é um cofre.

Quem pode fazer o que acabou de ser feito?

```text
$ kubectl auth can-i get secrets
yes
```

`kubectl auth can-i` pergunta ao cluster se **quem executa** pode fazer algo, sem fazê-lo. Pode, porque o `kubeconfig` que o kind entregou é de administrador. Em um cluster real, isso é controlado pelo RBAC, e a Lição 7 o pratica. Mas a documentação de Secrets avisa de uma porta dos fundos: quem pode criar um Pod em um namespace pode montar nele qualquer Secret desse namespace e lê-lo por dentro, ainda que não tenha permissão para `get secrets`. Por isso os Secrets de um serviço vivem no namespace desse serviço, e não em um compartilhado com outros (Lição 7).

E mais uma, que não se vê daqui: dentro do cluster, o Secret é guardado no `etcd` **sem cifrar**, a menos que o administrador ative a cifragem em repouso do `kube-apiserver`. O guia de boas práticas a põe como a primeira recomendação: “deve-se configurar a cifragem dos dados dos Secrets no etcd”. No kind isso não é feito; a Lição 10 anota isso na lista do que falta para produção.

O que sim um Secret dá, em comparação com escrever o token no Deployment, é isto: o token não está no manifesto nem no Git; viaja somente para os nós que o usam e ali vive em memória; e pode-se dar permissão de ler Deployments sem dar permissão de ler Secrets. É bastante. Só que não é cifragem.

### 4.7 Mudar a lista dispara o *rollout*

Agora sim, o pedido da cena, com a ferramenta completa. Antes da mudança, os ReplicaSets do `revisor` (quatro revisões: a da Lição 3, a do `fig04_02`, a do `rollout restart` e a do `apply -k`):

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   0         0         0       43s
revisor-697fb84f97   0         0         0       52s
revisor-99546b58f    0         0         0       9s
revisor-f6dd4cb4d    3         3         3       6s
```

A mudança é feita **no `kustomization.yaml`**, não no cluster (e antes de aplicá-la, outra vez `kubectl config current-context`). Abre-se o arquivo e acrescenta-se o serviço no final da lista, separado por uma vírgula:

```text
$ grep REVISOR_SERVICIOS kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
```

Antes de aplicar, perguntar ao cluster o que mudaria. O `kubectl diff -k .` compara o que o Kustomize montaria com o que há no cluster; aqui foi filtrado para ver somente as linhas que importam:

```text
$ kubectl diff -k . | grep -E '^[-+] .*(REVISOR_SERVICIOS|name: revisor-config)'
-              name: revisor-config-t6cm6872fk
+              name: revisor-config-7fbkh2926f
+  REVISOR_SERVICIOS: prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
+  name: revisor-config-7fbkh2926f
[código de salida: 1]
```

Leia-se linha por linha. As duas primeiras são do **Deployment**: a referência dele passa de `revisor-config-t6cm6872fk` a `revisor-config-7fbkh2926f`. As duas últimas são de um **ConfigMap novo**, com a lista nova e o nome novo. Essas duas primeiras linhas são o *rollout*, anunciado antes de acontecer: o template do Pod muda. (O código de saída 1 é do `kubectl diff`, que assim avisa que **sim** encontrou diferenças. Não é um erro.)

Com o mesmo conteúdo, o mesmo nome: o `7fbkh2926f` de outra máquina deve ser idêntico a este. Aplicar:

```text
$ kubectl apply -k .
configmap/revisor-config-7fbkh2926f created
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

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
revisor-66db8c7755   0         0         0       46s
revisor-697fb84f97   0         0         0       55s
revisor-769ff55c9c   3         3         3       3s
revisor-99546b58f    0         0         0       12s
revisor-f6dd4cb4d    0         0         0       9s

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
lento     OK           1ms  200
prueba    OK           1ms  200
```

Um ConfigMap novo (`created`), o Secret sem mudanças (`unchanged`: o token não mudou, nem o nome dele), um ReplicaSet novo, `revisor-769ff55c9c`, que assumiu as três réplicas por turnos, e a tabela com dois serviços. **Ninguém precisou lembrar de reiniciar nada.** É a meta 4 do curso: muda-se a lista, aplica-se com `kubectl apply -k .` e o cluster faz o *rollout* sozinho, sem reconstruir a imagem e sem que seja preciso lembrar de reiniciar o Deployment. Nada vigia os arquivos: sem o `apply`, o cluster nem percebe que a lista foi mudada.

E a volta atrás, que em 4.3 era impossível, aqui é trivial. O `kustomization.yaml` foi devolvido à lista original e aplicado:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl exec depurar -- curl -s -H "Authorization: Bearer $(cat token.txt)" 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

`revisor-config-t6cm6872fk unchanged`: o ConfigMap da lista original **nunca foi embora**. O Kustomize calculou o mesmo nome para o mesmo conteúdo, o Deployment voltou a apontar para ele e o template dele voltou a ser idêntico ao do ReplicaSet `revisor-f6dd4cb4d`. Cada configuração tem o seu próprio objeto, e cada revisão do Deployment aponta para o seu.

O preço disso já foi visto em 4.5.5: `revisor-config-7fbkh2926f` ficou no cluster, sem ninguém que o use. Com o tempo se acumulam. É um preço pequeno (cada um pesa uns poucos bytes) e se paga em troca de poder voltar atrás; a forma de limpá-los com ordem faz parte do que a Lição 10 deixa para um cluster real.

## O erro que se vai ver

O erro desta lição aparece justo quando se acredita ter terminado: o Secret existe, a montagem está bem escrita, o caminho está correto… e o `revisor` não inicia. Foi provocado de propósito tirando do Deployment a linha `fsGroup` com um `patch`, depois de conferir o contexto:

```text
$ kubectl patch deployment revisor --type=json -p='[{"op":"remove","path":"/spec/template/spec/securityContext/fsGroup"}]'
deployment.apps/revisor patched
```

(`--type=json` permite operações precisas como `remove`, sobre um caminho exato do objeto. É a forma de tirar **uma** linha sem reescrever o arquivo.) Vinte e cinco segundos depois, lê-se na ordem de sempre.

**Primeiro, o estado.**

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS   RESTARTS      AGE
revisor-7ffcfb7646-2lsmc   0/1     Error    2 (23s ago)   24s
revisor-7ffcfb7646-k4s2b   0/1     Error    2 (23s ago)   25s
revisor-7ffcfb7646-th42g   0/1     Error    2 (24s ago)   25s
```

`Error` e `RESTARTS 2`: o contêiner **sim iniciou**, e o programa terminou com erro; o `kubelet` o reiniciou e ele voltou a terminar. É um estado diferente dos da Lição 2. Não é `ImagePullBackOff` (a imagem existe) nem `CreateContainerConfigError` (a configuração pôde ser montada). É o programa que cai. Em alguns segundos mais, o estado passa a `CrashLoopBackOff`: a [documentação do ciclo de vida de um Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) explica que o `kubelet` reinicia com uma espera que cresce (10 s, 20 s, 40 s…) até um teto de 300 s, e que `CrashLoopBackOff` é o nome dessa espera. `Error` e `CrashLoopBackOff` se alternam: um é “caiu”, o outro é “espero antes de tentar de novo”.

**Segundo, os `logs`**, porque, se o programa iniciou, o programa tem algo a dizer:

```text
$ kubectl logs revisor-7ffcfb7646-2lsmc
revisor: leyendo el token de REVISOR_TOKEN_ARCHIVO: open /secretos/token: permission denied
```

Uma linha, e diz tudo: o `revisor` foi ler o arquivo que o `REVISOR_TOKEN_ARCHIVO` indicava, o sistema operacional lhe negou a permissão (`permission denied`), e o `revisor` se recusou a iniciar sem o token. Essa recusa é uma decisão do código dele, e é a correta: um `revisor` que iniciasse sem token deixaria o `/api/estados` aberto a qualquer um.

Por que não conseguiu lê-lo? Olhar no nó, como em 4.5.6, agora para um dos Pods que falham:

```text
$ docker exec curso-k8s-l4-worker2 ls -ln /var/lib/kubelet/pods/c26f312f-6841-4911-bea8-6f14513b4a11/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 0 33 Oct 21 13:28 token
```

Compare-se com o de 4.5.6, `-r--r----- 1 0 65532`. As permissões são as mesmas, `0440`, e o dono também, `root`. O que mudou é o **grupo**: com `fsGroup` era o 65532 e o `revisor` o lia por ser do grupo; sem `fsGroup` é o `0`, o do `root`. O usuário 65532 não é nem o dono nem do grupo, e para ele `0440` é “nada”.

**Terceiro, `describe`**, para confirmar quem fala:

```text
$ kubectl describe pod revisor-7ffcfb7646-2lsmc | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  24s                default-scheduler  Successfully assigned default/revisor-7ffcfb7646-2lsmc to curso-k8s-l4-worker2
  Normal   Pulled     11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container image "curso-docker-revisor:1.6.0" already present on machine and can be accessed by the pod
  Normal   Created    11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container created
  Normal   Started    11s (x3 over 24s)  kubelet            spec.containers{revisor}: Container started
  Warning  BackOff    10s (x2 over 22s)  kubelet            spec.containers{revisor}: Back-off restarting failed container revisor in pod revisor-7ffcfb7646-2lsmc_default(c26f312f-6841-4911-bea8-6f14513b4a11)
```

Tudo `Normal` até `Started`, três vezes (`x3`): a imagem existia, o contêiner foi criado e iniciou. O único `Warning` é `BackOff`, “espero antes de reiniciar o contêiner que falhou”. Os eventos não dizem **por que** falhou, porque o cluster não sabe: o programa caiu por conta própria. Por isso, quando o contêiner chegou a iniciar, os `logs` vêm antes do `describe`. Na Lição 2, com `ImagePullBackOff`, era ao contrário: não havia programa que falasse, e a resposta estava nos eventos.

**E agora o que não se esperava:**

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   0/3     3            0           83s
```

`0/3`. **Não sobra nem uma réplica saudável.** No Exercício 3 da Lição 2, uma imagem quebrada deixou o *rollout* travado com o serviço intacto: três Pods antigos vivos e um novo falhando. Aqui, os três Pods antigos já não existem. O que mudou, se a estratégia é a mesma (`maxSurge` 1, `maxUnavailable` 0)?

A diferença é **quando** o Pod novo falha. Com a imagem quebrada, o contêiner nunca iniciava, então o Pod nunca esteve pronto e o Deployment nunca removeu um antigo. Aqui, o contêiner **sim inicia**, e vive uns milissegundos antes de ler o token e cair. Para o Deployment, isso basta. Sem um *probe* que pergunte “já pode atender?”, o Kubernetes dá um contêiner por pronto assim que ele inicia. A [documentação de Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) define quando um Pod novo conta como disponível: quando está pronto, sem que nenhum contêiner dele caia, durante pelo menos `minReadySeconds`, que por padrão é **zero**. Cada Pod novo esteve “pronto” por um instante, o Deployment o contou e removeu um antigo. Nesta execução aconteceu três vezes, e os três Pods que sobraram não funcionam. Quanto a mudança avança depende de quantos Pods novos chegam a contar como prontos antes de cair: em uma repetição deste mesmo experimento, o *rollout* ficou no meio do caminho, com dois Pods antigos saudáveis e `AVAILABLE 2`, e o `kubectl rollout status` expirou com `error: timed out waiting for the condition`. O que não muda é a causa. E em nenhum caso o `kubectl rollout status` teria dito `successfully rolled out` com `AVAILABLE 0`: essa mensagem exige que todas as réplicas estejam disponíveis. O dano já estava feito antes que o comando pudesse avisar.

Isto é o mais importante da seção, e não é um defeito do Kubernetes: **o cluster só sabe o que se lhe ensina a perguntar.** Um `revisor` que inicia não é um `revisor` que pode atender. A Lição 5 dá ao Deployment um *readiness probe*, e com ele este mesmo erro deixa três réplicas antigas vivas, como na Lição 2.

**A saída** é a de sempre neste curso: o arquivo é a verdade, e se aplica de novo.

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-bh266kt42m unchanged
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
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
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

O `apply -k` devolveu a linha `fsGroup` e o template voltou a ser o de antes do `patch`. Repare que o *rollout* de volta também foi por turnos: aqui sim, os Pods novos leem o token, continuam vivos e o Deployment avança sobre Pods que funcionam.

**A ordem, para um Pod que inicia e cai:** o estado (`get pods`: `Error` ou `CrashLoopBackOff`, com `RESTARTS` subindo), os `logs` (o que o programa disse antes de cair; se o contêiner já reiniciou, `kubectl logs --previous` mostra os da tentativa anterior) e, por último, o `describe`. E antes de concluir que “não aconteceu nada grave”, `kubectl get deployment`: quantas réplicas sobram **de verdade** atendendo.

## O hábito de segurança da lição: o Secret não se versiona, monta-se como arquivo e marca-se como imutável

A tabela de hábitos do curso atribui a esta lição três regras sobre o Secret. As três já foram vistas funcionando; aqui vão juntas, com o que cada uma defende.

**Não se versiona.** O token vive em `token.txt`, que o `.gitignore` deixa fora do repositório, e o `kustomization.yaml` só diz de onde lê-lo. O que vai para o Git é a receita, nunca o valor. É a resposta direta à cena: um segredo que entra no Git uma vez fica no histórico para sempre, mesmo que seja apagado na versão seguinte, e o único reparo real é trocá-lo.

**Monta-se como arquivo**, com `defaultMode: 0440`, `readOnly: true` e `fsGroup` para que só o grupo do `revisor` o leia. Vivendo em um `tmpfs`, não toca o disco do nó. E não é herdado por outros processos nem aparece em uma listagem de variáveis.

**Marca-se como imutável.** Com `immutable: true`, o cluster se recusa a mudar o conteúdo do Secret:

```text
$ kubectl get secret -o name | grep revisor-token | xargs -I{} kubectl patch {} -p '{"data":{"token":"eA=="}}'
The Secret "revisor-token-bh266kt42m" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]
```

`eA==` é a letra `x` em base64: a tentativa era trocar o token por uma única letra. O `kube-apiserver` a rejeitou antes de guardá-la: “proibido: o campo é imutável quando `immutable` está definido”. A [documentação de Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) dá duas razões para usá-lo. A primeira, que protege de “atualizações acidentais (ou indesejadas) que poderiam causar quedas das aplicações”. A segunda é de desempenho: o `kubelet` não precisa vigiar os Secrets imutáveis, e em um cluster com milhares deles isso tira carga do `kube-apiserver`. E um aviso que é preciso saber: a marca **não tem volta**. “Uma vez que um Secret ou um ConfigMap é marcado como imutável, não é possível reverter a mudança nem modificar o conteúdo de `data`. Só é possível apagar o Secret e recriá-lo”.

Então como se troca o token? Com **outro** Secret. E isso, com o Kustomize, já está pronto: um token novo dá um *hash* novo, um nome novo, e o Deployment passa a montar o Secret novo com um *rollout*. Nenhum Pod vê o arquivo mudar no meio do caminho; cada Pod nasce com um token e morre com ele. O Exercício 2 faz isso. O gerador e a marca de imutável foram feitos um para o outro: o gerador nunca quer modificar um Secret, sempre cria outro.

**O que ele protege e o que não.** Estas três regras cuidam do token **fora** do cluster (Git) e **no nó** (memória, permissões). Não o cuidam **dentro** do `kube-apiserver`: quem tiver permissão de ler Secrets, ou de criar Pods no namespace, o lê com `base64 -d`, como foi feito em 4.6. Isso é defendido pelas permissões (Lição 7) e pela cifragem em repouso de um cluster real (Lição 10).

## Erros comuns

**Acreditar que base64 protege alguma coisa.** É uma codificação, não uma cifragem. Um manifesto de Secret com o `data` dele em um repositório é o segredo publicado. Viu-se em 4.6: um `base64 -d`.

**Versionar o Secret “porque assim o cluster se reconstrói sozinho”.** O que se reconstrói é o que está no Git, e isso inclui quem não devia ver o token. O token é gerado ou trazido de um lugar feito para guardar segredos (um gerenciador de segredos, em um cluster real), e o Git guarda só de onde tirá-lo.

**Mudar um ConfigMap manualmente e dar por certo que o programa já sabe.** Se o programa o lê como variável, não percebe até que o Pod renasça. Mediu-se em 4.3: o ConfigMap dizia dois serviços e o `revisor` continuava reportando um. A prova de que uma mudança chegou é o comportamento do programa, não o objeto.

**Escrever no Deployment o nome com *hash*.** `name: revisor-config-t6cm6872fk` escrito à mão deixa de servir na mudança de lista seguinte. Escreve-se o nome base e o Kustomize o traduz.

**Desativar o *hash* para que o nome fique limpo.** `disableNameSuffixHash: true` existe, e devolve ao problema de 4.3: a mudança de conteúdo não muda o template, e não há *rollout*. Será conferido no Exercício 3.

**Dar o token por variável de ambiente “porque é mais fácil”.** É herdada, é impressa sem querer, e o próprio `revisor` avisa no log dele que não se faça.

**Tirar o `fsGroup`, ou pôr `defaultMode: 0444`, “para que ele consiga ler”.** O `fsGroup` é a forma correta de o `revisor` ler o arquivo **por ser do grupo dele**. Abrir o arquivo a todos funciona, mas abre-se mão da permissão mínima. E se o `fsGroup` for tirado sem entender, já se viu quanto custa.

**Acreditar que um *rollout* em andamento protege o serviço.** Sem *probes*, o Deployment conta como pronto um Pod que acabou de iniciar e remove um Pod antigo saudável por cada novo, ainda que o novo caia ao ler a configuração. Antes de dar algo por bom, `kubectl get deployment` (que `AVAILABLE` iguale as réplicas desejadas) e uma requisição de verdade.

**Esquecer que o `apply` não apaga.** Cada mudança com geradores deixa para trás o ConfigMap ou o Secret anterior, e um ConfigMap escrito à mão que ninguém mais usa também fica. Não fazem dano, mas um Secret antigo que ninguém usa continua sendo um Secret: um token antigo legível. Os Secrets que já não servem são apagados.

## Exercícios

Os três primeiros são executados no cluster da lição, em ordem, a partir do estado em que ficou no final de “O hábito de segurança”, e a partir da pasta `programas/04-configuracion-secretos`. **Antes de cada exercício, `kubectl config current-context` deve dizer `kind-curso-k8s-l4`; se disser outra coisa, não prossiga.** O `correr.sh` os executa do mesmo modo, e a saída está em `correr.salida.txt`. **Antes** de executar cada um, escrever no [diário de bordo](bitacora.md) o que se acredita que vai acontecer. O quarto é escrito com palavras próprias.

### Exercício 1 — Uma chave que não existe

Mudar, com um `patch`, a chave que o Deployment busca no ConfigMap, como se houvesse um erro ao escrevê-la (`REVISOR_SERVICIO`, sem o S final):

```bash
kubectl patch deployment revisor --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key","value":"REVISOR_SERVICIO"}]'
```

Prever: em que estado fica o Pod novo? O contêiner inicia? Quantas réplicas antigas continuam atendendo, e por que desta vez não se repete o `0/3` de “O erro que se vai ver”? Conferir com `kubectl get pods -l app=revisor` e com os eventos `Failed` do Pod novo. Para sair, aplicar de novo o `kustomization.yaml`.

### Exercício 2 — Rotacionar o token (projeto)

Alguém viu o token em uma tela compartilhada e é preciso trocá-lo. Antes de gerar o novo, guardar o antigo em uma variável do terminal, `VIEJO="$(cat token.txt)"`, para poder testá-lo depois. Gerar o novo com `(umask 077; openssl rand -hex 16 > token.txt)` e aplicar `kubectl apply -k .`. Antes de aplicar, prever: o Secret que existia é modificado, ou aparece outro? Há *rollout*? O que responde o `revisor` a uma requisição com o token **antigo**, e o que a uma com o novo? Conferir com `kubectl get secret -o name | grep revisor-token` e com dois `curl` a partir do `depurar`, um com `-H "Authorization: Bearer $VIEJO"` e outro com `-H "Authorization: Bearer $(cat token.txt)"`. Para terminar, explicar o que seria preciso fazer com o Secret antigo, e por quê.

### Exercício 3 — Sem o *hash*

Copiar a pasta da lição para outro lugar, acrescentar ao final da cópia do `kustomization.yaml` estas duas linhas e olhar o resultado com `kubectl kustomize` (sem aplicá-lo):

```yaml
generatorOptions:
  disableNameSuffixHash: true
```

Prever antes: como se vão chamar o ConfigMap e o Secret? Para que nome vai apontar o Deployment? Depois, sem executar, responder: se com esta opção a lista for mudada e se aplicar, há *rollout*? Que parte da lição acabou de ser repetida? E, como o Secret é imutável, o que se acredita que aconteceria ao rotacionar o token com esta opção?

### Exercício 4 — Defender o arquivo

Um colega propõe passar o token com `secretKeyRef`, como variável de ambiente, “porque é uma linha e não um volume, e o Secret é igualmente secreto nos dois casos”. Em no máximo cinco frases, responder-lhe: em que ele tem razão, que risco a variável acrescenta que o arquivo não tem, o que diz o próprio `revisor` quando recebe o token por variável, e o que seria preciso acrescentar ao Deployment para que o arquivo possa ser lido sem abri-lo a todos.

## Soluções

### Solução 1

Medido em `correr.salida.txt`:

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS                       RESTARTS   AGE
revisor-84564b6875-ssrsx   0/1     CreateContainerConfigError   0          15s
revisor-f6dd4cb4d-6nrc8    1/1     Running                      0          17s
revisor-f6dd4cb4d-9sjs2    1/1     Running                      0          17s
revisor-f6dd4cb4d-s5h4z    1/1     Running                      0          18s

$ kubectl get events --field-selector involvedObject.name=revisor-84564b6875-ssrsx,reason=Failed -o custom-columns=MENSAJE:.message | head -2
MENSAJE
Error: couldn't find key REVISOR_SERVICIO in ConfigMap default/revisor-config-t6cm6872fk
```

O Pod novo fica em **`CreateContainerConfigError`**, o mesmo estado do `runAsNonRoot` da Lição 2: o `kubelet` não conseguiu montar a configuração do contêiner e **não o iniciou**. O evento diz exatamente o que faltou: a chave `REVISOR_SERVICIO` no ConfigMap `default/revisor-config-t6cm6872fk`. É o que anunciava `Optional: false` no `describe` de 4.2.

**As três réplicas antigas continuam atendendo.** A diferença em relação ao `0/3` do `fsGroup` é o momento da falha. Aqui o contêiner nunca iniciou, então o Pod novo nunca esteve pronto, nem por um instante, e com `maxUnavailable: 0` o Deployment não removeu nenhum Pod antigo. Com o `fsGroup`, o contêiner iniciava, estava “pronto” uns milissegundos e caía, e isso bastou ao Deployment para avançar. A lição de fundo: **um erro que impede de iniciar é mais seguro que um que inicia e cai**, enquanto não houver *probes*.

Ao aplicar de novo o `kustomization.yaml`, o template voltou ao de `revisor-f6dd4cb4d` e o Pod quebrado desapareceu:

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           103s
```

### Solução 2

Medido em `correr.salida.txt`:

```text
$ kubectl get secret -o name | grep revisor-token
secret/revisor-token-bh266kt42m

$ VIEJO="$(cat token.txt)"

$ (umask 077; openssl rand -hex 16 > token.txt)

$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk unchanged
secret/revisor-token-ttgcdb7g7c created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl get secret -o name | grep revisor-token
secret/revisor-token-bh266kt42m
secret/revisor-token-ttgcdb7g7c
```

```text
(con el token VIEJO)

$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $VIEJO" http://revisor/api/estados
401

(con el token NUEVO)

$ kubectl exec depurar -- curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(cat token.txt)" http://revisor/api/estados
200
```

`VIEJO` é uma variável do terminal: o token não fica escrito no histórico, só o nome `$VIEJO`. (Não guardá-lo em outro arquivo, como `token.viejo`: o `.gitignore` só exclui `token.txt`.)

**Aparece outro Secret**, `revisor-token-ttgcdb7g7c`; o antigo não é tocado, e não poderia ser: é imutável. O token novo mudou o *hash*, o *hash* mudou o nome, o nome mudou o template do Deployment, e houve *rollout* (`deployment.apps/revisor configured`, e `rollout status` com os mesmos turnos de 4.7). O ConfigMap não mudou (`unchanged`). Ao terminar, o token antigo dá `401` e o novo `200`: os Pods novos nasceram com o arquivo novo, e os antigos, que conheciam o token antigo, já não existem.

**O Secret antigo precisa ser apagado** (`kubectl delete secret revisor-token-bh266kt42m`). Nenhum Pod o usa, mas ele continua no cluster, e qualquer pessoa com permissão de ler Secrets pode tirar dele, com `base64 -d`, um token que alguém viu em uma tela. Se se quisesse poder voltar à revisão anterior do Deployment, esse Secret teria de existir; mas um token comprometido é justamente o que **não** se quer poder voltar a usar. Rotacionar não termina quando o novo funciona: termina quando o antigo já não serve em lugar nenhum.

### Solução 3

Medido em `correr.salida.txt`, sobre uma cópia em uma pasta temporária:

```text
$ tail -2 $TEMPORAL/sin-hash/kustomization.yaml
generatorOptions:
  disableNameSuffixHash: true

$ kubectl kustomize $TEMPORAL/sin-hash | grep -E '^  name: revisor-(config|token)|name: revisor-(config|token)$'
  name: revisor-config
  name: revisor-token
              name: revisor-config
```

O ConfigMap se chama `revisor-config` e o Secret `revisor-token`, sem mais, e o Deployment aponta para `revisor-config` (a terceira linha, com mais recuo, é o `configMapKeyRef` dele). Nomes limpos, e **nenhum *rollout*** quando a lista mudar: o ConfigMap conserva o nome, o template do Deployment não muda, e a regra “se e somente se” não se cumpre. Acabou-se de repetir a seção 4.3, só que com Kustomize: o objeto muda e o `revisor` continua com a lista antiga até que alguém lembre do `rollout restart`.

Com o Secret é pior, e foi medido. O script montou uma pasta à parte com **somente** o Secret, imutável e sem *hash*, em um namespace descartável, `sin-hash`. Aplicou-o, mudou o token dessa cópia e aplicou-o de novo:

```text
$ kubectl create namespace sin-hash
namespace/sin-hash created

$ kubectl apply -k $TEMPORAL/rotar
secret/revisor-token created

(token nuevo en la copia)

$ kubectl apply -k $TEMPORAL/rotar
The Secret "revisor-token" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]

$ kubectl delete namespace sin-hash
namespace "sin-hash" deleted
```

Como o nome já não muda, o `apply -k` tentou **modificar** o Secret que já existia, e o cluster se recusou com o mesmo `field is immutable` de “O hábito de segurança”. Para rotacionar o token seria preciso apagar o Secret manualmente antes de aplicar, e enquanto isso os Pods que reiniciassem não encontrariam o token. Desativar o *hash* e marcar como imutável são duas decisões que se contradizem. O *hash* é o que torna prática a imutabilidade. (Apagar o namespace `sin-hash` levou esse Secret junto.)

### Solução 4

Uma resposta possível: “Esse colega tem razão em que o Secret guarda o mesmo dado das duas formas, e em que no `etcd` está igualmente exposto. Mas uma variável é herdada por todo processo que o contêiner lança e aparece em qualquer despejo do ambiente ou log que imprima a configuração, enquanto um arquivo somente leitura em `tmpfs` não é copiado para cada processo: é preciso ir abri-lo de propósito, e só pode abri-lo quem tiver permissão. O próprio `revisor`, se recebe o token em `REVISOR_TOKEN`, escreve no log dele que qualquer um com `docker inspect` pode lê-lo e que se use `REVISOR_TOKEN_ARCHIVO`. Para ler o arquivo sem abri-lo a todos, o Deployment precisa de `defaultMode: 0440` e `fsGroup: 65532` no `securityContext` do Pod, que faz do grupo do `revisor` o dono do arquivo. São três linhas a mais que a variável, e valem a pena.”

## Apagar o cluster

Quando terminar os exercícios, apague o cluster da lição. Nada deve ficar vivo na máquina:

```text
$ kind delete cluster --name curso-k8s-l4
Deleting cluster "curso-k8s-l4" ...
Deleted nodes: ["curso-k8s-l4-control-plane" "curso-k8s-l4-worker2" "curso-k8s-l4-worker"]

$ kind get clusters | grep -c curso-k8s-l4
0
```

O `--name` é obrigatório aqui também: sem ele, o kind apagaria o cluster chamado `kind`, que pode ser de outra pessoa ou de outro projeto. Com o cluster vão-se os Secrets, os ConfigMaps e a cópia do token que vivia no `tmpfs` de cada nó.

Ficam duas coisas na máquina local, e as duas são apagadas:

```bash
# El token de la lección: ya no lo usa nadie, y un token suelto no se deja.
rm -f token.txt
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 4.0.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l4.*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

O `case` só deixa passar um caminho que comece com `/tmp/curso-k8s-l4.` e termine em `/kubeconfig`, a forma exata da que foi criada em 4.0; então o `dirname` tira o nome do arquivo e o `rm -rf` apaga essa pasta e nada mais. Se o terminal apontar para outro lugar (por exemplo, para o `~/.kube/config`, porque foi aberto outro terminal e não se repetiu o `export`), não apaga nada e diz por quê. É a mesma proteção que o `correr.sh` usa ao limpar: um `rm -rf` que pode ser copiado e colado precisa se proteger sozinho. Fechar esse terminal também deixa de usar o `kubeconfig` temporário. O cluster da lição seguinte é criado do zero, como este.

## Como saber que deu certo

- [ ] Explicar, com a tabela do `revisor` como prova, por que mudar um ConfigMap manualmente não mudou a lista de serviços dos Pods que já estavam rodando.
- [ ] Ler em `kubectl describe pod` de que ConfigMap e de que chave sai cada variável, e o que significa `Optional: false`.
- [ ] Escrever de memória um `kustomization.yaml` com `resources`, `configMapGenerator` (com `literals`) e `secretGenerator` (com `files: - token=token.txt`), e explicar o que faz o `token=`.
- [ ] Prever, antes de aplicar, que uma mudança de lista produz um ConfigMap com outro nome e um ReplicaSet novo, e conferi-lo com `kubectl diff -k .`.
- [ ] Decodificar um Secret com `base64 -d` e explicar em duas frases a diferença entre codificar e cifrar.
- [ ] Explicar o que o `fsGroup` faz com o arquivo do Secret, e reconhecer nos `logs` o `permission denied` da ausência dele.
- [ ] Explicar por que o erro do `fsGroup` deixou o Deployment em `0/3` e o da chave mal escrita não.
- [ ] Rotacionar o token com um Secret novo e saber o que fazer com o antigo.
- [ ] Executar `programas/04-configuracion-secretos/correr.sh > /tmp/mi-corrida-l4.txt 2>&1` e comparar `/tmp/mi-corrida-l4.txt` com `programas/04-configuracion-secretos/correr.salida.txt` (não redirecionar para esse arquivo: é a referência) no que não muda entre execuções: três nós `Ready` em `v1.37.0`; a tabela com `prueba OK … 200`; `<set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>`; a tabela que **não** mostra `lento` 30 s depois do `patch` e sim depois do `rollout restart`; `-rw-------` para `token.txt` e `wc -c` em 33; `token.txt` no `.gitignore`; `revisor-config-t6cm6872fk` como nome gerado; `immutable: true`; `401` sem token, `{"error":"falta el token o no es válido"}` e a tabela com token; `-r--r----- 1 0 65532 33 … token` sobre um `tmpfs`; o token idêntico depois do `base64 -d`; `revisor-config-7fbkh2926f` no `diff` e um ReplicaSet novo com `lento` na tabela; `permission denied` nos `logs`, o arquivo como `-r--r----- 1 0 0` e o Deployment em `0/3` sem `fsGroup`; ``field is immutable when `immutable` is set``; `couldn't find key REVISOR_SERVICIO`; dois Secrets depois de rotacionar, `401` com o antigo e `200` com o novo; os nomes sem sufixo do Exercício 3 e o `field is immutable` dele ao rotacionar; e no final `sin diferencias con la kustomization`. O token, o nome do Secret, os sufixos de Pods e ReplicaSets, os IPs, os `uid`, o nó de cada Pod, as idades, os tempos da tabela e as vezes que se repete cada linha do `rollout status` mudam em cada execução: observam-se, não se comparam.
- [ ] Ao terminar, `kind get clusters` já não mostra `curso-k8s-l4`, na pasta da lição não ficou nenhum `token.txt` e não resta nenhuma pasta `/tmp/curso-k8s-l4.*`.

## Resumo

Responda sem olhar a lição:

1. O que é um ConfigMap e o que diz a documentação dele sobre guardar dados confidenciais nele?
2. Por que mudar um ConfigMap que é usado como variável não muda o que faz o `revisor`? Dar as duas razões: a do Kubernetes e a do programa.
3. O que faz o `configMapKeyRef`, e por que este curso o prefere ao `envFrom`?
4. O que o Kustomize acrescenta ao nome de um ConfigMap gerado, e como isso converte uma mudança de conteúdo em um *rollout*?
5. Por que, ao voltar à lista original em 4.7, o ConfigMap saiu `unchanged` e não `created`?
6. Que diferença há entre codificar e cifrar? O que é base64?
7. Quem pode ler um Secret em um cluster, além de quem tem permissão de `get secrets`?
8. O que faz o `fsGroup` com o arquivo de um Secret montado, e o que aconteceu ao tirá-lo?
9. Por que o erro do `fsGroup` deixou o serviço sem réplicas e o da chave mal escrita não?
10. O que não se pode fazer com um Secret imutável, e como se muda então o conteúdo dele?

## Fontes

Todas consultadas em 21 de outubro de 2026.

- [Kubernetes, “ConfigMaps”](https://kubernetes.io/docs/concepts/configuration/configmap/): a definição; que não oferece sigilo nem cifragem; o teto de 1 MiB; as quatro formas de usá-lo a partir de um Pod; que os ConfigMaps montados como arquivo são atualizados “eventualmente” e os usados como variáveis “não são atualizados automaticamente e exigem reiniciar o Pod”; e os ConfigMaps imutáveis.
- [Kubernetes, “Configure a Pod to Use a ConfigMap”](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/): `configMapKeyRef`, `envFrom` e as referências opcionais.
- [Kubernetes, “Secrets”](https://kubernetes.io/docs/concepts/configuration/secret/): a definição; o aviso de que são guardados sem cifrar no etcd e de que quem pode criar um Pod pode ler os Secrets do namespace dele; o teto de 1 MiB; a atualização “eventualmente consistente” dos volumes; a cópia em `tmpfs` no nó; e os Secrets imutáveis, as duas vantagens deles e que a marca não pode ser revertida.
- [Kubernetes, “Good practices for Kubernetes Secrets”](https://kubernetes.io/docs/concepts/security/secrets-good-practices/): a cifragem em repouso; o acesso mínimo; que base64 não é um método de cifragem; que um manifesto de Secret em um repositório expõe o segredo; e que a aplicação não deve registrar o dado em claro.
- [Kubernetes, “Distribute Credentials Securely Using Secrets”](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/): `defaultMode` e o valor padrão dele, `0644`.
- [Kubernetes, “Declarative Management of Kubernetes Objects Using Kustomize”](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): o Kustomize dentro do `kubectl` desde a 1.14; `configMapGenerator` e `secretGenerator`; o sufixo com o *hash* do conteúdo e `generatorOptions` com `disableNameSuffixHash`.
- [Kubernetes, “Configure a Security Context for a Pod or Container”](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` como grupo adicional dos processos e como dono dos volumes que admitem administração de donos.
- [Kubernetes, “Deployments”](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `minReadySeconds` e quando um Pod novo conta como disponível.
- [Kubernetes, “Pod Lifecycle”](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): a espera crescente entre reinícios (10 s, 20 s, 40 s… até 300 s) e o estado `CrashLoopBackOff`.

---

**Próxima:** [Lição 5 — Verificação de saúde (*health check*), recursos e desligamento ordenado](05-salud-recursos-apagado.md)
