# Урок 5 — Проверки на състоянието, ресурси и подредено изключване

Четвъртък, 6:40 следобед. Тестовата услуга е паднала от десет минути и таблото го показва правилно: `FALLA codigo 503`. Точно за това съществува `revisor`. Но в 6:42 таблото спира да се зарежда. Искаш списъка с обектите Pod и виждаш нещо, което не си очаквал: трите реплики на `revisor` имат `RESTARTS 4`, `RESTARTS 5`, `RESTARTS 5`, а две от тях казват `CrashLoopBackOff`. Никой не е пипал `revisor`. Онова, което някой наистина е пипнал, във вторник, е неговата проверка на състоянието: „за да е по-пълна“, я е накарал да пита и за тестовата услуга. Сега тестовата услуга е паднала, проверката на `revisor` се проваля, клъстерът заключава, че `revisor` е мъртъв, и го рестартира отново и отново. Инструментът, който трябваше да те предупреди за проблема, е първата жертва на проблема. А в 7:00 трябва да обясниш какво се е случило.

Клъстерът не сгреши: направи точно онова, което му казаха. Този урок те учи да му казваш правилното. Как клъстерът разбира, че един контейнер е стартирал, че може да получава трафик и че е още жив, и защо тези три въпроса са различни. Колко CPU и памет се полагат на всеки контейнер и какво става, когато поиска повече. И какво прави `revisor` в секундите, които клъстерът му дава, когато го помоли да се изключи.

**Време:** 2 × 45 мин

**Какво изграждаш:** `revisor`, който клъстерът умее да наблюдава: със startup, readiness и liveness probes, с долна граница и таван за CPU и памет и със срок за изключване по негова мярка; и тестовата услуга със собствена probe и собствени лимити

**Какво научаваш:** какво пита всяка probe (`startupProbe`, `readinessProbe`, `livenessProbe`), кой я изпълнява и какво става, когато се провали; защо `/salud` не пита никого; какво са `requests` и `limits`, кой използва всяко от тях и в какви единици се пишат; класовете за качество на услугата; `OOMKilled` и `Pending`, предизвикани нарочно, и как се разчитат; и какво става между `kubectl delete pod` и изчезването на обекта Pod, с `terminationGracePeriodSeconds`

**Откъде идваш.** От [Урок 4](04-configuracion-secretos.md): `revisor` и тестовата услуга се прилагат с `kubectl apply -k .`; списъкът с услуги идва от генериран `ConfigMap`, а токенът — от `Secret`, монтиран като файл, и `/api/estados` иска `Authorization: Bearer …`. От [Урок 3](03-services-dns.md) носиш обекта Pod `depurar`, обектите EndpointSlice и тяхната колона `ready`, която раздел 3.4.3 остави за този урок. А от [Урок 2](02-pods-deployments.md) — че `kubelet` на всеки възел е този, който стартира контейнерите.

**Какво не прави този урок.** Не разпределя репликите между възлите и не прави така, че обновяването да не губи заявки: това е [Урок 9](09-escalar-y-actualizar.md), с `preStop`, `PodDisruptionBudget` и автоматичното мащабиране, което използва днешните `requests` за изчисленията си. Не публикува `revisor` навън: това е [Урок 6](06-entrar-al-cluster.md). И не поставя правила за цяло пространство от имена (максимум за контейнер, общо за екип): те се споменават в навика за сигурност от урока и остават извън курса.

**За изпълненията.** Всички изходи в този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1 и образа на възел `kindest/node:v1.37.0`, фиксиран чрез отпечатъка си, в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l5`. Машината беше Mac с процесор ARM и Docker Engine 29.2.1 във виртуална машина с Linux (Colima) с 6 CPU и 16 GiB памет, а **не** Linux Mint, който е референтната система на курса. Какво се променя в твоя Mint: архитектурата (`amd64` вместо `arm64`); CPU и паметта, които всеки възел казва, че има, а в kind те са тези на твоята машина (5.6 го обяснява), и заедно с тях процентите в `describe node`; IP адресите, случайните наставки в имената, възрастите, на кой възел попада всяка реплика, часът в журнала и точната памет, която използва `revisor`. Командите са същите. Цялата обиколка е в [`programas/05-salud-recursos-apagado/`](../programas/05-salud-recursos-apagado): `correr.sh` създава клъстера, зарежда му образите, оставя всичко така, както го остави Урок 4, минава през урока по ред, изпълнява Упражнения 1 до 3 и изтрива клъстера. Цялото изпълнение отне 4 минути и 48 секунди, а скриптът записва колко е отнела всяка дълга стъпка: създаването на клъстера и изчакването да е готов — 34 секунди; изтриването му — 1. Изходът му е `correr.salida.txt`. Там капацитетът на възлите (5.6) и нарочната грешка се появяват преди изключването (5.7), а навикът за сигурност — преди упражненията, защото скриптът ги изпълнява в този ред. Не използва нито един порт на твоята машина.

## След урока ще можеш да

- Обясняваш с пример разликата между „стартира“, „готов е“ и „жив е“ и казваш коя probe пита за всяко от тях и какво прави клъстерът, когато отговорът е „не“.
- Пишеш трите probes на `revisor` и изчисляваш, с техните числа, колко време отнема на клъстера да реагира на всеки провал.
- Обосноваваш защо liveness probe не бива да пита за други услуги и го доказваш с паднала тестова услуга.
- Пишеш `requests` и `limits` в миликорове и мебибайтове и казваш кой използва всяко от тях: планировчикът, `kubelet` или ядрото на Linux.
- Предизвикваш `OOMKilled` и `Pending`, разчиташ ги с `kubectl get`, `describe` и събитията и ги поправяш.
- Измерваш колко време отнема на един Pod да се изключи и обясняваш ролята на SIGTERM, SIGKILL и `terminationGracePeriodSeconds`.

## Защо, преди как

Досега клъстерът знае само едно нещо за твоите контейнери: дали процесът работи. Ако процесът умре, `kubelet` го рестартира; това го видя в Урок 2. Но един процес може да работи и да не обслужва. Може още да стартира, без да слуша на порта си. Може да е заседнал в блокиране — жив за операционната система и мъртъв за клиентите си. Може да е изправен и въпреки това за момент да не иска трафик. За клъстера днес трите случая са еднакви: `Running`. А обектът Service от Урок 3 праща трафик и към трите.

Първият въпрос в урока тогава е **как един контейнер казва на клъстера в какво състояние е?** Отговорът са **probes**: въпроси, които `kubelet` задава на контейнера през определено време. Те са три, защото има три различни въпроса и всеки отрицателен отговор има различна последица: изчакване, спиране на трафика към него или рестартирането му. Объркването им е сцената от четвъртък.

Вторият въпрос е **колко се полага на всеки?** Днес `revisor` не казва колко CPU, нито колко памет му трябват, и клъстерът го поставя където и да е, без да брои. Контейнер без таван може да изяде паметта на цял възел и да повлече всичките си съседи. **`requests`** казват колко му трябва, за да му намери място планировчикът; **`limits`** казват докъде може да стигне.

Третият е **как си отива?** Всеки път, когато изтриеш Pod, направиш *rollout* или клъстерът премести нещо, един контейнер получава заповед да се изключи. Ако я изпълни, довършва онова, което е правил, и излиза. Ако не, клъстерът изчаква определен срок и го убива. Този срок се пише в манифеста.

Урокът има седем части с понятия и след тях обичайните раздели:

1. **Клъстерът на урока и какво знае той днес** (5.1).
2. **Манифестите на урока** (5.2), поле по поле.
3. **Трите probes** (5.3): какво пита всяка и кога реагира.
4. **Probes в действие** (5.4): прилагане, преглед и разчитане в журнала.
5. **Защо `/salud` не пита никого** (5.5): сцената от четвъртък, наобратно.
6. **`requests`, `limits` и капацитетът на възлите** (5.6).
7. **Подреденото изключване** (5.7).

Това е целта. В края на 5.4 всяка реплика на `revisor` има своите три probes, своята долна граница и своя таван и срок за изключване от 10 секунди:

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

## Ако нямаш образите от курса по Docker

Този урок използва същите два образа като Урок 3: `curso-docker-revisor:1.6.0` и `curso-docker-prueba:1.0.0`. Провери, че ги имаш:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

За другия — същата команда с `curso-docker-prueba:1.0.0`. Ако ти липсва някой, [Урок 3](03-services-dns.md) казва, в същия този раздел, как да се изгради всеки от хранилището на курса по Docker. Какво този урок изисква **допълнително** от двата образа — и си струва да го прочетеш, защото всяка точка обяснява един ред от манифестите:

- **`revisor` отговаря на `GET /salud`, без да пита никого**: връща `{"estado":"vivo","version":"1.6.0"}` с код 200 веднага щом започне да слуша. Трите probes питат там.
- **`revisor` обработва SIGTERM**: когато го получи, пише `revisor: recibí terminated, apagando`, довършва текущите заявки със собствен срок от 5 секунди и пише `revisor: apagado limpio`.
- **Тестовата услуга винаги отговаря на `GET /modo`**, във всеки режим, докато процесът е жив. `GET /` е онзи, който отговаря с 503 в режим `caido`. Тази разлика решава накъде пита нейната probe.

Образът на `curl` на обекта Pod `depurar` продължава да е публичен и фиксиран чрез отпечатъка си; всеки възел го изтегля от интернет първия път.

## Понятията

### 5.1 Клъстерът на урока и какво знае той днес

#### 5.1.1 Създаване на клъстера

Този урок използва собствен клъстер, `curso-k8s-l5`, с конфигурацията от три възела от Урок 1. Създай го така, от корена на хранилището на курса, със същото обичайно внимание:

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

`export` важи само в този терминал. Затова временната папка остава запазена в променлива, `L5_TMP`, а `echo` ти показва целия път: ако отвориш друг терминал (в 5.7 ще ти трябва втори), там повтаряш `export` с **този** път, иначе `kubectl` ще говори с друг клъстер. А в края на урока същата променлива е онази, която ти позволява да изтриеш папката, без да пишеш пътя на око. И правилото от предишните уроци остава в сила: **преди всеки** `apply`, `delete`, `patch` или `exec` в този урок `kubectl config current-context` трябва да казва `kind-curso-k8s-l5`. Скриптът го проверява сам преди всяко `kubectl` и спира, ако не съвпада.

Изходите в този раздел са от изпълнението на `correr.sh`, който прави точно това:

```text
$ kubectl config current-context
kind-curso-k8s-l5

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l5-control-plane   Ready    control-plane   29s   v1.37.0
curso-k8s-l5-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l5-worker2         Ready    <none>          15s   v1.37.0
```

`kind load` отпечатва шест реда `not yet present on node …, loading...`, два образа по три възела, както в Урок 3.

#### 5.1.2 Отправната точка: какво остави Урок 4

Папката `programas/05-salud-recursos-apagado/punto-de-partida/` съдържа, без да е променена и запетая, манифестите, с които завърши Урок 4: неговия `kustomization.yaml`, двата обекта Deployment и двата обекта Service. Както в онзи урок, токенът не се версионира: генерира се при всяко изпълнение. Този път се копира в двете папки, тази на отправната точка и тази на урока, за да генерират и двете **един и същ** Secret:

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

Тридесет и два шестнадесетични знака и знак за нов ред: 33 байта. Както в Урок 4, скобите и `umask 077` карат файла да се роди с права `0600` (`-rw-------`), четим само за теб, вместо `0644`, които би оставила обичайната ти маска; `cp` без `-p` не копира правата на оригинала: създава новия файл с режима на оригинала, филтриран през твоя `umask`. Тъй като `0600` вече няма права за група, нито за други, маската не му добавя нищо и копието също остава `0600`; при файл `0664` или `0755` резултатът би зависел от твоя `umask`, а `cp -p` е опцията, която запазва режим, собственик и дати. Първият ред на блока е проверката на контекста, написана като команда: ако контекстът не е този на урока, отпечатва „contexto equivocado“ и не продължава. Използвай я преди всяка промяна; скриптът го прави сам. Името на ConfigMap е същото като в Урок 4, `revisor-config-t6cm6872fk`, защото списъкът с услуги не се е променил. Това на Secret е различно при всяко изпълнение, защото токенът е нов.

#### 5.1.3 Какво знае клъстерът днес

```text
$ kubectl get pods -l 'app in (revisor,prueba)'
NAME                      READY   STATUS    RESTARTS   AGE
prueba-6f4dfdb898-8p5j2   1/1     Running   0          4s
revisor-f65c6dd96-248bg   1/1     Running   0          4s
revisor-f65c6dd96-575nn   1/1     Running   0          4s
revisor-f65c6dd96-pzxpk   1/1     Running   0          4s
```

Погледни колоната `READY`: `1/1` на **4 секунди**. Слушаше ли вече `revisor` на порта си на тази възраст? Сигурно да, защото стартира бързо. Но клъстерът не го е проверил: отбелязал е обекта Pod като готов веднага щом контейнерът е стартирал. Това е, което Урок 3 предвиди в 3.4.3: без probes „готов“ означава „процесът съществува“. Ако `revisor` се бавеше десет секунди, за да отвори порта си, обектът Service щеше да му праща трафик през тези десет секунди и тези заявки щяха да се провалят.

А сега какво казва обектът Pod за себе си:

```text
$ kubectl describe pod revisor-f65c6dd96-248bg | grep -E '^(Name|QoS Class):|Liveness|Readiness|Startup|Limits|Requests'
Name:             revisor-f65c6dd96-248bg
QoS Class:                   BestEffort

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
30

$ kubectl get pod revisor-f65c6dd96-248bg -o jsonpath='{range .status.conditions[*]}{.type}={.status} {end}{"\n"}'
PodReadyToStartContainers=True Initialized=True Ready=True ContainersReady=True PodScheduled=True 
```

`grep` потърси probes, `Limits` и `Requests` и не намери нито едно: само името и един ред, `QoS Class: BestEffort`. Това е класът за качество на услугата на обекта Pod, а `BestEffort` („каквото може“) е онзи, който получава Pod, който не декларира нищо за CPU, нито за памет. 5.6 обяснява какво означава; предварително: това е първият, когото възелът изхвърля, когато остане без памет. Срокът за изключване е `30` секунди, стойността по подразбиране, която никой не е избрал. А условията на обекта Pod казват `Ready=True`: това е условието, което EndpointSlice копира в колоната си `ready`, и днес то е станало вярно, без никой да е питал нищо.

Три празнини: никой не проверява дали `revisor` обслужва, никой не казва колко му трябва, а срокът за изключване е наследено число. И трите се затварят с манифестите на този урок.

### 5.2 Манифестите на урока

Урокът променя два файла: обектите Deployment на `revisor` и на тестовата услуга. `kustomization.yaml`, двата обекта Service и `depurar.yaml` са същите като в Урок 4 (коментарът на първия ред на `kustomization.yaml` сега казва „Lecciones 4 y 5“). Двата обекта Deployment са **програми**: прилагат се с `kubectl apply -k .` от `programas/05-salud-recursos-apagado/`.

#### 5.2.1 `revisor`

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

Всичко, което не е ново, вече го прочете в Уроци 2 до 4. Новото са три блока и едно число:

- **`terminationGracePeriodSeconds: 10`**, в шаблона на Pod (не в контейнера): колко секунди има обектът Pod, за да се изключи сам, преди клъстерът да го убие. 5.7.
- **`resources`**, в контейнера: долната граница (`requests`) и таванът (`limits`) за CPU и памет. 5.6.
- **`startupProbe`, `readinessProbe` и `livenessProbe`**, в контейнера: трите probes. 5.3.

Обърни внимание на `port: http` в трите probes. Това е същият трик от Урок 3 с `targetPort` на Service: портът е по **име**, така че числото `8080` продължава да живее на едно-единствено място, `containerPort`. А `{path: /salud, port: http}` е YAML на един ред: къдравите скоби групират двете полета на `httpGet` по същия начин, както ако ги напишеш на два реда с отстъп. Пишат се така, защото трите probes споделят един и същ въпрос, а между тях се променят само числата.

#### 5.2.2 Тестовата услуга

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

Една-единствена probe, liveness, и тя сочи към `/modo`, **а не** към `/`. Коментарът на файла го казва, а 5.5 го доказва: `GET /` е точно онова, което тестовата услуга чупи нарочно в режим `caido`. Ако liveness probe питаше там, клъстерът щеше да я рестартира всеки път, когато я поставиш в този режим, което е обратното на онова, което искаш от услуга, която съществува, за да се проваля. Упражнение 2 го доказва. Няма startup probe, защото стартира за милисекунди, нито readiness probe, защото курсът иска `revisor` да може да говори с нея дори когато е паднала; Упражнение 1 ти показва какво би станало с нея.

Ресурсите са по-малки от тези на `revisor`, защото тя прави по-малко: не пита никого и не пази отчети.

### 5.3 Трите probes

#### 5.3.1 Кой пита и как

[Документацията за probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/) започва така: probe е „диагностика, която `kubelet` извършва периодично върху контейнер“, и с резултатите от нея „Kubernetes може да рестартира неизправни контейнери или да спре да праща трафик към контейнери, които не са готови“. Запомни двете части: **`kubelet`**, този на възела, на който работи обектът Pod, а не контролната равнина; и **две различни реакции** — рестартиране или спиране на трафика.

Трите probes на `revisor` използват `httpGet`: `kubelet` прави HTTP заявка към IP адреса на обекта Pod, към порта и пътя, които му зададеш. [Ръководството за конфигуриране на probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) казва кога се брои за успех: „всеки код, по-голям или равен на 200 и по-малък от 400, показва успех. Всеки друг код показва провал“. Отговор, който не пристига навреме, също е провал. Има и други начини за питане (изпълнение на команда вътре в контейнера, отваряне на TCP връзка или gRPC извикване), но за HTTP сървър, който вече има свой път за проверка на състоянието, HTTP заявката е онази, която пита за важното: не „съществува ли процесът?“, а „отговаря ли?“. А `revisor` няма *shell*, за да се изпълняват команди вътре, както видя в Урок 2.

#### 5.3.2 Числата на една probe

Всяка probe се настройва с пет полета. Стойностите по подразбиране са от същата документация за probes:

| Поле | Какво е | По подразбиране |
|---|---|---|
| `initialDelaySeconds` | колко да се чака преди първия въпрос | 0 s |
| `periodSeconds` | през колко време да се пита | 10 s (минимум 1) |
| `timeoutSeconds` | колко да се чака отговор | 1 s |
| `successThreshold` | колко поредни успеха, след провал, за връщане към „добре“ | 1 (за liveness и startup **трябва** да е 1) |
| `failureThreshold` | колко поредни провала, за да се заключи „зле“ | 3 |

Правилото за разчитането им: **една probe реагира след `failureThreshold` поредни провала, разделени с `periodSeconds`**. Единичен провал не прави нищо. Това не позволява едносекундно препъване да задейства рестартиране. Документацията го казва с тези думи: след като една probe се провали `failureThreshold` пъти поред, „Kubernetes смята, че цялостната проверка се е провалила“.

#### 5.3.3 Startup probe: „стартира ли вече?“

Документацията за probes: startup probes „проверяват дали приложението вътре в контейнера вече е стартирало. Ако има startup probe, Kubernetes не изпълнява liveness и readiness probes, докато startup probe не успее“. А ако се провали напълно, „`kubelet` убива контейнера“, който остава подчинен на политиката си за рестартиране.

Тази на `revisor`: `periodSeconds: 1` и `failureThreshold: 10`. Пита всяка секунда и дава на програмата до **10 опита**, около 10 секунди, за да отговори първия път (1 × 10). Това е сметката, когато всеки опит се проваля веднага; ако програмата е заседнала и всеки опит трябва да изчерпи своя `timeoutSeconds` (1 секунда по подразбиране), срокът се доближава до 20. Щом отговори, престава да пита, докато този контейнер е жив; ако контейнерът се рестартира, започва отначало. За разлика от другите две, тя работи само при стартиране. Защо 10 секунди, щом `revisor` стартира за по-малко от една? Защото числото не е за добрия ден, а за лошия: натоварен възел, образ, който се чете бавно. И излишъкът е малък: програма, която не отговаря за 10 секунди, има някакъв проблем.

Ръководството за конфигуриране на probes обяснява защо съществува тази probe. Има програми, които стартират бавно, и ако liveness probe трябваше да ги чака, тя трябваше да е бавна и щеше да престане да открива навреме блокиране. Решението е разделянето: startup probe с `failureThreshold * periodSeconds`, „достатъчно дълго, за да покрие най-лошия случай на стартиране“, и щом тя успее, „liveness probe поема контрола“. Неговият пример е програма с до 5 минути за стартиране (30 × 10 s). На `revisor` му трябва много по-малко, но моделът е същият.

#### 5.3.4 Readiness probe: „да ти пращам ли трафик?“

Документацията: readiness probes „определят кога контейнерът е готов да приема трафик“, а ако една се провали, „контролерът на EndpointSlices маха IP адреса на обекта Pod от обектите EndpointSlice на всички Services, които съвпадат с обекта Pod“. Това е колоната `ready` от Урок 3, най-сетне със съдържание. Един нюанс, който ще видиш в Упражнение 1: на практика адресът не изчезва от EndpointSlice, а остава с `ready=false`, и това стига, за да спре `kube-proxy` да му праща трафик. „Махане от трафика“ е ефектът; „отбелязване като неготов“ е механизмът. И нещо, което я отличава от startup probe: „readiness probes работят в контейнера през целия му жизнен цикъл“.

Най-важното е онова, което тя **не** прави: не рестартира нищо. Документацията за probes, в описанието на `failureThreshold`: при провалена readiness probe „`kubelet` продължава да изпълнява контейнера, който се е провалил, и продължава да прави още проверки“ и само поставя условието `Ready` на обекта Pod на `false`. Когато probe отново мине, обектът Pod се връща в списъка. Това е probe за „добре съм, но точно сега не“.

Тази на `revisor`: на всеки 5 секунди, а 2 поредни провала го изваждат от обекта Service. В най-лошия случай `revisor`, който престане да отговаря, продължава да получава трафик около **10 секунди** (2 × 5), преди да излезе от списъка.

#### 5.3.5 Liveness probe: „жив ли си още?“

Документацията: liveness probes „определят кога да се рестартира контейнер“. Примерът, който дава, е блокиране (*deadlock*), „при което приложението работи, но не може да напредва“. Ако контейнерът се провали повече пъти от допустимото, „`kubelet` рестартира този контейнер“.

Това е единствената от трите, която унищожава нещо: рестартирането прекъсва отворените връзки и състоянието в паметта. Затова същата страница я придружава с предупреждение, което е сцената от четвъртък на езика на ръководството: liveness probes „трябва да се конфигурират внимателно, за да е сигурно, че наистина показват непоправим провал на приложението“, и „неправилната реализация на liveness probes може да доведе до каскадни провали“.

Тази на `revisor`: на всеки 10 секунди, а 3 поредни провала го рестартират. Заседнал `revisor` се рестартира за около **30 секунди** (3 × 10). По-бавна от readiness probe нарочно: документацията описва този модел като обичайния — същият евтин път и за двете и по-голям `failureThreshold` при liveness, за да изглежда обектът Pod „неготов“ известно време, преди да бъде убит. Така временно препъване изважда обекта Pod от трафика (което е евтино) много преди да бъде рестартиран (което е скъпо).

#### 5.3.6 Трите заедно

| Probe | Въпрос | Ако отговорът е „не“ | Кога работи | В `revisor` |
|---|---|---|---|---|
| startup | стартира ли вече? | чака; ако срокът изтече, рестартира | само при стартиране | до 10 s (1 s × 10) |
| readiness | да ти пращам ли трафик? | изважда те от обекта Service; **не** рестартира | винаги | излиза за ~10 s (5 s × 2) |
| liveness | жив ли си още? | **рестартира** контейнера | винаги, след startup probe | рестартира за ~30 s (10 s × 3) |

Трите на `revisor` питат едно и също, `GET /salud`. Това не е излишък: това е един и същ въпрос с три различни последици и три различни степени на търпение.

### 5.4 Probes в действие

#### 5.4.1 Преди прилагане — преглед на промените

Първо се проверява, че двете папки имат един и същ токен, а после клъстерът се пита какво би се променило:

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

`kubectl diff -k .` сравнява онова, което би приложил, с онова, което има; двата `grep` оставят редовете, които се **добавят** (започват с `+ `), и махат онези, които се променят винаги. Първо идва Deployment на тестовата услуга, после този на `revisor`. Обърни внимание на три неща. Не се появява нито ConfigMap, нито Secret: токенът е същият, списъкът също, така че имената им с *hash* не се променят. Полетата, които не си написал (`scheme: HTTP`, `successThreshold: 1`, `timeoutSeconds: 1`), се появяват със стойността си по подразбиране, тази от таблицата в 5.3.2: така се вижда какво наистина ще работи. А изходният код 1 не е грешка: `kubectl diff` излиза с 1, когато **има** разлики, и с 0, когато няма. В края на урока ще го използваш наобратно, за да провериш, че не е останала нито една.

За последния ред, `[código de salida: 1]`: не го пише `kubectl`, пише го скриптът всеки път, когато команда излезе с код, различен от 0, и ще го виждаш и в други блокове на урока. Скриптът работи с `set -o pipefail`, така че кодът на един конвейер е този на първата команда, която се провали, тук `kubectl diff`. В твоя терминал, без тази опция, `echo $?` би ти дал кода на последния `grep`, който е 0. За да провериш без конвейер: `kubectl diff -k . >/dev/null; echo $?`, което дава `1`.

#### 5.4.2 Прилагане

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

Променят се само двата обекта Deployment, а промяната на шаблона на Pod е *rollout*: нов ReplicaSet (`revisor-578c8dc8d9`), който заменя репликите една по една. Възрастите го разказват: 12, 11 и 9 секунди, със секунда или две разлика между тях. И този път замяната изчакваше всяка нова реплика да мине своята readiness probe, преди да махне стара: Deployment брои за „наличен“ само готов Pod. Без probes „готов“ идваше, преди да се знае каквото и да е.

`describe` на една от новите реплики е целта, която видя в началото:

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

Ето как се чете една probe в `describe`: `http-get http://:http/salud` е „HTTP заявка към IP адреса на обекта Pod (той е празен, между `//` и `:`), към порта с име `http`, път `/salud`“; след това идват петте числа от 5.3.2, с `delay` вместо `initialDelaySeconds` и `period` вместо `periodSeconds`. Класът мина от `BestEffort` на `Burstable`, а срокът за изключване — от 30 на 10.

#### 5.4.3 Разчитане на probes в журнала

Всяка probe е истинска HTTP заявка, а `revisor` пише по един ред за всяка заявка, която обслужва. Ето журнала му, с часа на всеки ред:

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

(`--timestamps` поставя пред всеки ред часа, в който е записан, в UTC и с наносекунди; `sed` само отрязва датата и десетичните, за да се побере. Ничий друг журнал не казва тези часове: те са от това изпълнение.)

Сега го прочети като часовник (минутите са 45 и 46). Програмата започна да слуша в `:44`. В `:45` има **две** заявки. Първата е **startup probe**, която пита всяка секунда и тук не ѝ трябваше повече от една; от този момент тя вече не пита и влизат другите две. Втората, в същата секунда, е първата **readiness**: документацията за probes предупреждава, че докато контейнерът не е готов, тази probe може да работи извън своя период, за да стане обектът Pod готов по-рано. Оттам нататък има по един ред на всеки 5 секунди (`:45`, `:50`, `:55`, `:00`, `:05`): readiness probe. А между тях — по един на всеки 10 (`:54`, `:04`): **liveness**. Точно `periodSeconds` от манифеста. Втората команда потвърждава резултата: контейнерът е стартирал (`started` е `true`) и е готов (`ready` е `true`).

Две практически последици. Първата: при това темпо всяка реплика пише около 18 реда в минута само от probes, повече от 25 хиляди на ден. Ако програмата ти пише по ред на заявка, probes ще напълнят журнала ѝ и е добре да го знаеш, преди да търсиш нещо там. Втората: probes **струват**. Всеки въпрос е работа за `kubelet` и за програмата. Затова `/salud` трябва да е евтин и затова периодите не се слагат на една секунда „за всеки случай“.

### 5.5 Защо `/salud` не пита никого

#### 5.5.1 Сцената от четвъртък, наобратно

`revisor` съществува, за да ти казва, че други услуги се провалят. Ако проверката на състоянието му зависеше от тези услуги, клъстерът щеше да го наказва точно когато си върши работата. Проверява се: обектът Pod `depurar` от Урок 3, тестовата услуга в режим `caido` и 35 секунди изчакване, повече от 30-те, за които liveness probe рестартира.

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

(В `correr.salida.txt` токенът се вижда написан: скриптът го поставя в командата. Това е симулиран токен от онова изпълнение, който умря заедно с клъстера.)

Нула рестартирания и при четирите обекта Pod, всички `1/1`, а отчетът казва каквото трябва: `prueba FALLA codigo 503`. Това е обратното на сцената от четвъртък и разликата е в едно-единствено проектно решение: `/salud` отговаря „жив съм“, без да пита никого за нищо. Коментарът на първия ред на манифеста го оставя записано за онзи, който дойде след теб.

Обърни внимание и на тестовата услуга: `RESTARTS 0` и `1/1`, макар от повече от 35 секунди да отговаря с 503 на `/`. Нейната liveness probe пита за `/modo`, който продължава да отговаря. Клъстерът различава „проваля се нарочно“ от „мъртва е“, защото си го попитал правилното.

#### 5.5.2 А документацията не казва ли да се проверяват зависимостите?

Казва го, с уговорка, и си струва да се прочете изцяло. Документацията за probes, в частта за това кога да се използва всяка: „когато приложението ти има строга зависимост от *backend* услуги, можеш да реализираш liveness probe и readiness probe. Liveness probe минава, когато самото приложение е изправно, но readiness probe проверява освен това, че всяка необходима *backend* услуга е налична“.

Две неща. Първото е правилото, което никога не се променя: **liveness probe гледа само приложението**. Дори в този абзац зависимостта отива в readiness, никога в liveness. Рестартирането на твоята програма не поправя базата данни на друг екип; само те оставя без програма.

Второто е принцип и зависи от това какво прави услугата ти. Ако услугата ти не може да отговори с нищо полезно без базата си данни, изваждането ѝ от трафика, докато базата липсва, има смисъл. `revisor` е обратният случай: **неговият полезен отговор е именно да каже кой липсва**. Ако неговата readiness probe зависеше от `prueba`, при падането на `prueba` обектът Service на `revisor` щеше да остане без реплики и таблото нямаше да се зарежда, което е симптомът от сцената по друг път. Затова трите probes на `revisor` питат `/salud`, а `/salud` не пита никого. Упражнение 1 ти позволява да видиш този друг път с тестовата услуга.

### 5.6 `requests`, `limits` и капацитетът на възлите

#### 5.6.1 Две числа с двама различни собственици

[Документацията за управление на ресурсите](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) ги разделя според това кой ги използва: „когато зададеш *request* за ресурс на контейнерите в Pod, `kube-scheduler` използва тази информация, за да реши на кой възел да постави обекта Pod. Когато зададеш *limit* за контейнер, `kubelet` налага тези лимити, така че контейнерът да не използва от този ресурс повече от лимита, който си задал“.

- **`requests` е резервация.** Планировчикът я използва при избора на възел, а `kubelet` я спазва после: същата страница казва, че `kubelet` също заделя „поне количеството от *request*“ за този контейнер, така че когато има конкуренция за CPU, контейнерът запазва своя дял. За планировчика същата страница казва: планировчикът се грижи за всеки ресурс сборът от *requests* на контейнерите на един възел да е по-малък от капацитета му, и го прави дори реалната употреба да е много ниска: „планировчикът отказва да постави Pod на възел, ако проверката на капацитета не мине“. `request` не е онова, което контейнерът използва: то е онова, което възелът му заделя.
- **`limits` е таван**, и го налагат `kubelet` и ядрото на Linux през цялото време.

#### 5.6.2 Единиците

**CPU.** Същата страница: „1 единица CPU е равна на 1 физическо ядро на CPU или на 1 виртуално ядро“, ако възелът е виртуална машина, и се допускат дроби: `0.1` е същото като `100m`, „което се чете като сто милиCPU“. `revisor` иска `50m`, една двадесета от ядро, а таванът му е `200m`, една пета. Документацията препоръчва формата с `m` за количества под 1, защото се чете по-лесно.

**Памет.** В байтове, с наставки. Има две семейства: `M`, `G` (степени на 10) и `Mi`, `Gi` (степени на 2). `32Mi` са 32 мебибайта, 33,554,432 байта; `32M` биха били 32,000,000. Курсът използва `Mi`. И един капан, който документацията изтъква изрично: „внимавай с главните и малките букви в наставките“. `400m` памет са 0.4 **байта**, не 400 мегабайта: малкото `m` е „мили“. Погрешно написано `memory: 64m` е таван от част от байта: контейнерът не може дори да стартира. (Това не беше измерено в урока; онова, което беше измерено при подготовката на курса, е, че с таван от `4Mi` `revisor` вече дава `StartError`, както казва коментарът на `memoria.yaml`.)

#### 5.6.3 Какво става при достигане на тавана

Таванът не се прилага по един и същ начин за двата ресурса и разликата е от най-важните в този курс. Документацията за управление на ресурсите:

- **CPU:** „лимитите за `cpu` се налагат чрез ограничаване (throttling) на CPU“. Ако `revisor` поиска повече от `200m`, ядрото просто не му го дава: програмата работи по-бавно, но остава жива.
- **Памет:** „лимитите за `memory` се налагат от ядрото чрез убиване поради липса на памет (OOM)“. Паметта, която програмата вече има, не може да ѝ се отнеме наполовина, така че когато я надхвърли и ядрото не може да освободи памет отнякъде другаде (например от кеша на файловете), я убива. Документацията го нарича „реактивен“ лимит: не предотвратява превишаването, наказва го. Нарочната грешка в този урок е точно това.

Практическото правило, което следва оттук: нисък таван за CPU прави програмата ти **бавна**; нисък таван за памет я кара да **умре**. И двата се задават, но този за памет се задава с повече резерв.

#### 5.6.4 Какво казва, че има, един възел на kind

Колко се побира във възел? Питаш го:

```text
$ kubectl get nodes -o custom-columns='NODO:.metadata.name,CPU:.status.allocatable.cpu,MEMORIA:.status.allocatable.memory'
NODO                         CPU   MEMORIA
curso-k8s-l5-control-plane   6     16342676Ki
curso-k8s-l5-worker          6     16342676Ki
curso-k8s-l5-worker2         6     16342676Ki
```

(`custom-columns` сглобява таблица с полетата, които поискаш; `allocatable` е онова, което възелът предлага на обектите Pod.)

Всеки възел казва, че има 6 CPU и около 15.6 GiB. И трите са **цялата** виртуална машина на Docker от това изпълнение: 6 CPU и 16 GiB. Това е kind и никога не го забравяй: възлите му са контейнери на една и съща машина и всеки вижда и обявява пълните ресурси на хоста. За планировчика има 18 CPU; в хардуера са 6. В истински клъстер всеки възел обявява своето. В kind `requests` и `limits` работят както в истински — планировчикът брои, ядрото реже, — но капацитетът, който виждаш, е лабораторен мираж. В твоя Mint числата ще са тези на твоя компютър.

Онова, което планировчикът вече е заделил на един работен възел:

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

`Requests` сумира онова, което искат всички обекти Pod на възела, твоите и тези на системата. При това изпълнение на `worker` попадна една реплика на `revisor` (нейните `50m` и `32Mi` и нейните `200m` и `64Mi` таван, които са цялата колона `Limits`); останалите *requests* са на системните обекти Pod, които работят на всеки възел, като мрежата на kind. Бележката в началото, „общите лимити могат да надхвърлят 100 %“, казва нещо важно: планировчикът **не** брои `limits`. Можеш да обещаеш повече таван, отколкото има, защото се предполага, че не всички стигат тавана си едновременно. Онова, което планировчикът не позволява да надхвърли 100 % от разпределимия капацитет, е сборът от `requests`, когато решава къде попада обикновен Pod (статичните обекти Pod на самия възел не минават през него).

#### 5.6.5 Колко наистина използва `revisor`

Числата в манифеста са решения. Близо ли са до реалността? `kubelet` говори с `containerd` на възела, а `crictl` може да го попита колко използва всеки контейнер (това е същият инструмент от Урок 2, вътре във възела):

```text
$ docker exec curso-k8s-l5-worker2 crictl stats --label io.kubernetes.container.name=revisor | sed 's/^.\[2J.\[H//'
CONTAINER           NAME                CPU %               MEM                 DISK                INODES              SWAP
060935005135f       revisor             0.02                1.733MB             45.06kB             13                  0B
1be34aa64c901       revisor             0.03                1.733MB             45.06kB             13                  0B
```

(`--label` филтрира контейнерите с име `revisor`; на `worker2` попаднаха две реплики. `crictl stats` отпечатва в началото кодове за изчистване на екрана, а `sed` ги маха.)

По-малко от 2 MB памет и CPU почти на нула, в покой. `request` от `32Mi` е над петнадесет пъти повече. Това не е грешка: `revisor` расте, когато сглобява отчет и пита няколко услуги едновременно, а `request` е онова, от което програмата има нужда в нормалния си ден с натоварване, не в покой. Но числото потвърждава нещо, което ще използваш след малко: `revisor` **не става** за предизвикване на `OOMKilled`, защото почти не използва памет. За да го видиш, ти трябва програма, която я иска.

В истински клъстер това измерване се прави с `kubectl top`, който изисква `metrics-server`. Той идва в Урок 9, защото е онова, което захранва автоматичното мащабиране.

#### 5.6.6 Класовете за качество на услугата

С `requests` и `limits` клъстерът класифицира всеки Pod в един от три класа. [Документацията за класовете QoS](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) дава критериите:

| Клас | Кога | В този курс |
|---|---|---|
| `Guaranteed` | всеки контейнер има `requests` и `limits` за CPU и за памет и във всеки `request` е **равен** на `limit` | нито един |
| `Burstable` | не е `Guaranteed`, но поне един контейнер има някакъв `request` или `limit` | `revisor`, `prueba`, `depurar`, `memoria` |
| `BestEffort` | нито един контейнер не декларира нищо за CPU, нито за памет | `revisor` от 5.1 |

А за какво служи: когато възел остане без ресурси, „Kubernetes изгонва първо обектите Pod `BestEffort` от този възел, след това `Burstable` и накрая `Guaranteed`“. И добавя, че когато изгонването е поради липса на ресурси, кандидати са само обектите Pod, които използват повече, отколкото са поискали. По-подробната страница за изгонване при натиск върху възела уточнява: `kubelet` изгонва първо `BestEffort` и `Burstable`, които надхвърлят своя `request`, а `Guaranteed` и `Burstable`, които не го надхвърлят, се изгонват накрая, ако предишното не е стигнало. Тоест спазването на твоя `request` те поставя в края на опашката, а не извън нея. Още една причина `request` да прилича на реалната употреба. `revisor` от 5.1 беше първи на опашката. Днес той е `Burstable`, защото таванът му е по-голям от долната му граница: може да се „разтегне“ от `50m` до `200m`, ако има свободен CPU. За да го направиш `Guaranteed`, ще трябва да изравниш двете числа и винаги да плащаш тавана като резервация. За програма, която в покой използва 2 MB, курсът предпочита `Burstable`.

### 5.7 Подреденото изключване

#### 5.7.1 Какво става, когато изтриеш Pod

[Документацията за жизнения цикъл на Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination) разказва последователността. Когато поискаш изтриване на Pod, клъстерът записва срок, а `kubelet` на възела започва изключването: иска от *runtime*-а на контейнера да изпрати „сигнал TERM“ (SIGTERM) „до процес 1 във всеки контейнер“, тоест до главния процес, онзи с PID 1. А след това: „щом срокът изтече, на оставащите процеси се изпраща сигналът KILL“. SIGTERM е молба („изключи се, моля“); SIGKILL не е молба, това е ядрото, което прекратява процеса, без да го пита. Срокът по подразбиране е **30 секунди** и се променя с `terminationGracePeriodSeconds`.

Едновременно с това се случва и друго, което се свързва с Урок 3: контролната равнина изважда изключващия се Pod от трафика. Същата страница: неговите *endpoints* не се изтриват веднага от EndpointSlice, но се отбелязват като `terminating` и „винаги имат състояние `ready` на `false`“, така че не получават нов трафик. (Страницата за EndpointSlices добавя изключение, което курсът не използва: `ready` е винаги вярно при Service с `publishNotReadyAddresses: true`.) Двете неща се случват едновременно, не едно след друго. Тази надпревара между „обектът Pod получава SIGTERM“ и „всички възли разбират, че вече не бива да му пращат трафик“ е онази, която Урок 9 решава с `preStop`. Днес е достатъчно да знаеш, че съществува.

#### 5.7.2 Да го видим

*Предупреждение за имената.* Изходите в този раздел и в следващите два идват от изпълнението на скрипта, при което изключването се случи **след** двете грешки от „Грешката, която ще видиш“. Затова обектът Pod, който тук се изтрива, `g9lhl`, още се вижда жив в раздела за `Pending`, а `hfjmq`, който го заменя, вече се появява в навика за сигурност: това не е грешка на твоя клъстер, нито на урока. На твоята машина, ако следваш урока в реда на текста, имената ще са други.

За да видиш какво пише `revisor` в последните си секунди, отвори **втори терминал** и го подготви така, с пътя, който отпечата `echo` от 5.1.1 (в първия терминал `echo "$KUBECONFIG"` ти го дава отново):

```bash
# En la SEGUNDA terminal. Pega la ruta completa; la de abajo es solo la forma.
export KUBECONFIG=/tmp/curso-k8s-l5.XXXX/kubeconfig
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
kubectl logs -f <nombre de una réplica del revisor>
```

Ако проверката каже „contexto equivocado“, пътят не е правилният: не продължавай. Докато `kubectl logs -f` работи там, в първия терминал изтрий тази реплика:

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

(`-f` следи журнала на живо, докато контейнерът приключи; скриптът го пази във файл и показва последните му четири реда.)

`kubectl delete` чака обектът Pod наистина да изчезне и това отне **по-малко от секунда** (скриптът мери в цели секунди и записа `0 s`; при други изпълнения записа 1 и 3). Последните два реда на журнала са подреденото изключване: `revisor` получи `terminated` (така Go нарича SIGTERM), спря да приема нови връзки, изчака да приключат онези, които имаше, и излезе сам: `apagado limpio`. Така и не се стигна до SIGKILL. А ReplicaSet вече беше възстановил репликата: `hfjmq`, на 3 секунди.

#### 5.7.3 Защо 10 секунди

Щом `revisor` си отиде за по-малко от секунда, защо да се сменя срокът от 30 на 10? Защото срокът не е за доброто изключване, а за **лошото**. Ако един ден `revisor` заседне и не обработи SIGTERM, клъстерът го убива на 10-ата секунда, а не на 30-ата. През това време обектът Pod заема мястото си: *rollout* на три реплики, които се изключват зле, може да отнеме минути повече.

Числото също не е случайно: `revisor` си дава 5 секунди, за да довърши текущите заявки, а срокът на клъстера трябва да е **по-голям** от този на приложението, иначе SIGKILL го прекъсва по средата на сбогуването. 10 е двойно на 5. Когато Урок 9 добави `preStop`, който също работи в рамките на този срок, числото се качва на 15.

Упражнение 3 ти показва какво става с процес, който **не** обработва SIGTERM: обектът Pod `depurar`.

## Грешката, която ще видиш

Този урок има две нарочни грешки, по една за всяко число в `resources`: таванът за памет и долната граница за CPU.

### OOMKilled: надхвърляне на тавана за памет

Както видя в 5.6.5, `revisor` използва по-малко от 2 MB; с него не може да се види `OOMKilled`. Използва се самостоятелен Pod, `memoria.yaml`, който е **програма**, проваляща се нарочно: опитва се да запише 40 MB в променлива на *shell* с таван от 16 MiB.

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

Това е образът на `curl` от `depurar`, със същия `securityContext`, и друга програма: `head -c 40000000 /dev/zero` произвежда 40 милиона нулеви байта, `tr` ги превръща в букви `x`, а `a=$(…)` кара *shell*-а да ги задържи всичките в паметта. `restartPolicy: Never` прави така, че когато умре, да остане мъртъв, за да може да бъде разгледан.

```text
$ kubectl apply -f memoria.yaml
pod/memoria created

$ kubectl get pod memoria
NAME      READY   STATUS      RESTARTS   AGE
memoria   0/1     OOMKilled   0          20s
```

`STATUS OOMKilled`: убит поради липса на памет (*Out Of Memory*). Разчита се по ред, от симптома към причината.

**Първо, причината и кодът:**

```text
$ kubectl get pod memoria -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} {.status.containerStatuses[0].state.terminated.exitCode}{"\n"}'
OOMKilled 137
```

Изходният код `137` е конвенция на Unix: 128 плюс номера на сигнала, който е убил процеса. 137 − 128 = 9, а сигнал 9 е SIGKILL. Никой не е молил програмата да си отиде; ядрото я е прекратило. Но внимание: 137 казва „убит е със SIGKILL“, а не кой и защо. Може да е ядрото заради паметта, както тук, или `kubelet`, защото е изтекъл срокът за изключване, което предизвиква Упражнение 3. Онова, което разделя двата случая, е причината: `OOMKilled` в единия, нещо друго в другия. Винаги гледай причината заедно с кода.

**Второ, докъде е стигнал:**

```text
$ kubectl logs memoria
pidiendo 40 MB
```

Написал е първия си ред и никога втория, `no debería llegar aquí`. Умрял е по средата на заделянето.

**Трето, таванът, който го обяснява:**

```text
$ kubectl describe pod memoria | grep -E '^QoS Class:|Reason:|Exit Code:|Limits:|memory:'
      Reason:       OOMKilled
      Exit Code:    137
    Limits:
      memory:  16Mi
      memory:     16Mi
QoS Class:                    Burstable
```

`Limits: memory: 16Mi` (второто `memory: 16Mi` е от блока `Requests`, който `grep` също улавя). Поискал е 40 MB срещу таван от 16 MiB: ядрото направи точно онова, което казва 5.6.3. [Ръководството за заделяне на памет](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/) предизвиква същата грешка с друга програма и в раздела си „Exceed a Container's memory limit“ го обобщава така: контейнерът може да надхвърли своя `request`, ако възелът има памет, но не и своя `limit`.

**Как се поправя.** Не с по-висок таван „да видим дали така“. Документацията за управление на ресурсите, в раздела си за отстраняване на проблеми, казва реда: при `OOMKilled` следващата стъпка е да прегледаш кода за изтичане на памет; ако програмата се държи както очакваш, тогава да, вдигни тавана (и може би долната граница). Тук програмата прави точно каквото трябва, а то е да се провали; изтрива се:

```text
$ kubectl delete pod memoria
pod "memoria" deleted from default namespace
```

Ако беше контейнер на Deployment, `kubelet` щеше да го рестартира отново и отново, с растящи изчаквания между опитите: документацията за жизнения цикъл дава поредицата, „10 s, 20 s, 40 s, …“, с таван от 5 минути. Това изчакване е, което `kubectl get pods` показва като `CrashLoopBackOff`. Ако видиш `CrashLoopBackOff`, погледни колоната `RESTARTS` и причината за последното прекратяване, преди да пипнеш каквото и да е: може да е `OOMKilled`, може да е програма, която излиза с грешка, може да е зле написана liveness probe. Това са три различни поправки.

### Pending: искане на долна граница, която не се побира

Втората грешка е за другото число: `request` за CPU, който никой възел не може да задели. Предизвиква се с директна корекция на Deployment, така че поправката да е повторно прилагане на файла.

Преди такава промяна — проверката на контекста от 5.1.2:

```bash
[ "$(kubectl config current-context)" = kind-curso-k8s-l5 ] || { echo "contexto equivocado"; false; }
```

```text
$ kubectl patch deployment revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"50"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"50"}]'
deployment.apps/revisor patched
```

`kubectl patch --type=json` променя отделни полета на жив обект: тук `request` и `limit` за CPU на първия контейнер стават `50`. **Петдесет CPU**, не петдесет милиCPU: липсва `m`. Това е печатна грешка, която лесно се допуска, а клъстерът я приема, без да се оплаче: `50` е валидно количество.

**Първо, симптомът:**

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

Четири обекта Pod: нов ReplicaSet (`revisor-5b8f867ccf`) с една реплика в `Pending` и трите стари — непокътнати. `Pending` означава, че обектът Pod съществува в `kube-apiserver`, но никой не му е дал възел. А *rollout* заседна на „1 от 3“: `rollout status` се отказа след 15-те секунди, които му даде.

**Второ, причината, в събитията на обекта Pod:**

```text
$ kubectl describe pod revisor-5b8f867ccf-9x42x | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  25s   default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

(`sed -n '/^Events:/,$p'` отпечатва от реда `Events:` до края.) Онзи, който говори, е планировчикът (`default-scheduler`), а съобщението му се чете възел по възел:

- `0/3 nodes are available`: нито един от трите възела не става.
- `1 node(s) had untolerated taint(s)`: един има „петно“ (*taint*), което този Pod не толерира. Това е контролният възел, който по подразбиране не получава твоите обекти Pod; видя го в Урок 1, когато обектите Pod попадаха само на работните възли.
- `2 Insufficient cpu`: другите два нямат достатъчно CPU. Иска 50; всеки обявява 6.
- `preemption: … Preemption is not helpful`: планировчикът е обмислил и изгонване на обекти Pod с по-нисък приоритет, за да направи място, и е заключил, че това няма да помогне. Дори да изпразни възел, 50 не се побират в 6.

Документацията за управление на ресурсите посочва същото това събитие като първи случай за отстраняване на проблеми: ако планировчикът не намери възел, в който обектът Pod да се побере, „обектът Pod остава неразпределен, докато не се намери място“, и всеки път, когато се провали, се генерира събитие. Изходите, които предлага, са да се добавят възли или да се освободи място; този, който важи тук, е третият, очевидният: да се поиска правилното.

**Трето, онова, което не се счупи:**

```text
$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

Услугата продължава да отговаря. Защо Deployment не махна нито една стара реплика? Заради стратегията си за обновяване, която Урок 9 изучава задълбочено: [документацията за Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) казва, че по подразбиране `maxUnavailable` е 25 % „със закръгляне надолу“, а `maxSurge` е 25 % „със закръгляне нагоре“. При 3 реплики: 0.75 слиза до **0** реплики, които могат да липсват, а 0.75 се качва до **1**, която може да е в повече. Deployment създаде една нова в повече и остана да чака тя да стане налична, за да махне стара. Тя така и не стана. Заседналият *rollout* е неудобен; такъв, който сваля добрите реплики, за да ги замени с реплики, които не се побират, би бил срив. Това правило те пази от собствената ти печатна грешка.

**Поправката** е обичайната в този курс: файлът е истината и се прилага отново.

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

Същите три реплики като преди, със същите възрасти. Шаблонът отново стана идентичен с този на ReplicaSet `revisor-578c8dc8d9`, който вече имаше своите три реплики, така че нямаше какво да се заменя: Deployment свали на нула счупения ReplicaSet и обектът Pod в `Pending` изчезна. Това е същият ефект, който видя в Решение 3 от Урок 2.

**Редът, за всеки Pod, който не е `Running`:**

1. `kubectl get pods`: `Pending`, `OOMKilled`, `CrashLoopBackOff`?
2. Ако е `Pending` — събитията на обекта Pod: какво казва планировчикът за всеки възел?
3. Ако е умрял — причината и кодът на последното му прекратяване (`OOMKilled 137`, `Error` с друг код) и журналът му (`kubectl logs` или `--previous`, ако вече е рестартирал).
4. Преди да смениш число — да се запиташ дали числото е грешно, или програмата.

## Навикът за сигурност от урока: всеки контейнер с долна граница и таван

Таблицата с навици на курса възлага на този урок две неща: `requests` и `limits` във всеки контейнер; probes не зависят от чужди услуги. Второто го провери в 5.5. Първото се проверява с един поглед:

```text
$ kubectl get pods -o custom-columns='POD:.metadata.name,QOS:.status.qosClass,CPU_PIDE:.spec.containers[0].resources.requests.cpu,CPU_TOPE:.spec.containers[0].resources.limits.cpu,MEM_PIDE:.spec.containers[0].resources.requests.memory,MEM_TOPE:.spec.containers[0].resources.limits.memory'
POD                        QOS         CPU_PIDE   CPU_TOPE   MEM_PIDE   MEM_TOPE
depurar                    Burstable   10m        100m       16Mi       32Mi
prueba-b896986b5-kzrmk     Burstable   10m        100m       16Mi       32Mi
revisor-578c8dc8d9-hfjmq   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-jlh4b   Burstable   50m        200m       32Mi       64Mi
revisor-578c8dc8d9-xhqt8   Burstable   50m        200m       32Mi       64Mi
```

Пет обекта Pod, пет пълни реда, нито един `<none>`, нито един `BestEffort`. Включително `depurar`, който е „само за гледане“: Урок 3 му сложи таван още от самото начало и днес знаеш защо.

Защо това е навик за **сигурност**, а не само за ред? Защото контейнер без таван за памет е контейнер, който може да свали съседите си. [Документацията за `LimitRange`](https://kubernetes.io/docs/concepts/policy/limit-range/) започва с изречението, което го обяснява: „по подразбиране контейнерите работят с неограничени изчислителни ресурси в клъстер на Kubernetes“. Програмна грешка (изтичане на памет, цикъл, който не свършва) или атака (някой, който нарочно праща огромни заявки) в контейнер без таван се превръща в проблем на **целия възел**: възелът остава без памет и започва да изгонва обекти Pod, като започва от `BestEffort`, които може да са на друг екип. С таван щетата остава вътре в контейнера, който я е причинил: умира той, с `OOMKilled`, който казва точно какво е станало, и никой друг.

Същото е и с CPU, с един нюанс: контейнер без таван за CPU, който влезе в безкраен цикъл, изяжда целия свободен CPU на възела и прави съседите си бавни. Онези, които са декларирали `requests`, запазват своя дял и затова долната граница също защитава; онези, които не са декларирали нищо, остават с каквото е останало. С таван онзи, който се задушава, е самият той.

**Какво защитава и какво не.** Таваните ограничават щетите **в рамките на един възел**; не пречат на някой да създаде сто обекта Pod. За това истинският клъстер използва `ResourceQuota` (общо за пространство от имена) и `LimitRange` (максимум и стойност по подразбиране за контейнер). Този курс не ги инсталира и ги споменава, за да знаеш, че съществуват. А probes не са защита: нападател, който влезе в `revisor`, няма да чупи `/salud`. Онова, което те наистина предотвратяват, е другата половина на проблема: твоя грешка да превърне малък провал във верижен срив.

## Какво се прави погрешно

**Да слагаш в liveness probe нещо, което зависи от други.** Това е сцената от четвъртък. Паднала база данни не се оправя с рестартиране на клиентите ѝ. Liveness probe пита за процеса и за нищо друго.

**Да използваш едно и също търпение за трите probes.** Ако liveness реагира толкова бързо, колкото readiness, десетсекундно препъване рестартира, вместо само да отстрани от трафика. Liveness е по-бавна.

**Liveness probe без startup probe в програма, която стартира бавно.** `kubelet` започва да пита веднага щом контейнерът стартира; ако програмата се бави повече от `failureThreshold × periodSeconds`, тя се рестартира, преди да е довършила стартирането, и отново, и отново. Startup probe съществува за това.

**Скъп път за проверка на състоянието.** Ако `/salud` пита базата данни, сглобява отчет или пише на диска, всяка probe го прави, във всяка реплика, на всеки няколко секунди. Евтин и локален.

**Да насочваш probe към път, който нарочно сменя кода си.** `GET /` на тестовата услуга е такъв: 503 в режим `caido` по замисъл. Упражнение 2 го измерва.

**Контейнери без `requests` и `limits`.** Остават `BestEffort`: планировчикът не им заделя нищо, никой не им слага таван и са първите, които излизат, когато възелът е притиснат.

**Да пишеш `memory: 64m` или `cpu: 50`.** Малкото `m` при паметта е милибайтове; число без `m` при CPU е цели ядра. Второто е `Pending` от този урок.

**Да вдигаш тавана за памет при всеки `OOMKilled`.** Ако е изтичане, само го отлагаш. Първо се питаш дали програмата е наред.

**Да приемаш капацитета на възел на kind за реален.** Всеки възел обявява цялата ти машина. Онова, което се побира в kind, не ти казва какво се побира в продукция.

**Да оставиш срока за изключване по подразбиране, без да помислиш.** Тридесет секунди може да са много за програма, която се изключва за една, и малко за такава, която трябва да довърши дълга работа. Избира се и се избира по-голям от вътрешния срок на програмата.

**Главен процес, който пренебрегва SIGTERM.** Клъстерът ще чака целия срок всеки път, когато го изключиш. Упражнение 3 го измерва.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред и от състоянието, в което остана след 5.7, с обекта Pod `depurar` още жив. Преди всяко от тях `kubectl config current-context` трябва да казва `kind-curso-k8s-l5`. `correr.sh` ги изпълнява по същия начин, а изходът му е в `correr.salida.txt`. **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще стане. Четвъртото се пише със собствени думи.

### Упражнение 1 — Readiness probe в тестовата услуга

`fig05_01.prueba-disponibilidad.yaml` е Deployment на тестовата услуга от този урок с една-единствена разлика: добавя readiness probe към `GET /`, на всеки 5 секунди, с 2 провала за излизане от трафика.

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

Приложи го, изчакай новият Pod да стане `1/1` и го постави в режим `caido`. Преди да погледнеш, предвиди: на 15-ата секунда какво казва колоната `READY`? А `RESTARTS`? Какво казва EndpointSlice на обекта Service `prueba`? Попитай го с `kubectl get endpointslices -l kubernetes.io/service-name=prueba -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready} serving={.conditions.serving}{"\n"}{end}'`. Каква подробност дава отчетът на `revisor`? И трудният въпрос: върши ли работа `kubectl exec depurar -- curl -s -m 3 -X POST http://prueba:9000/modo/sano`, за да го поправиш? Ако не, как го връщаш в `sano`? Накрая приложи отново `kubectl apply -k .`.

### Упражнение 2 — Liveness probe, която пита каквото не бива

`fig05_02.prueba-vida-mala.yaml` е Deployment на тестовата услуга от урока с един-единствен различен ред: liveness probe пита `GET /` вместо `GET /modo`.

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

Приложи го, изчакай да стане `1/1` и го постави в режим `caido`. Предвиди, с числата на probe: след колко горе-долу секунди идва първото рестартиране? Какви събития оставя обектът Pod (търси причините `Unhealthy` и `Killing`)? След рестартирането какво отговаря `GET /modo`? Какво казва отчетът на `revisor`? И обясни защо това е по-лошо, отколкото изглежда: какво стана с доказателствата? Накрая приложи отново `kubectl apply -k .`.

### Упражнение 3 — Колко време отнема на обекта Pod за отстраняване на грешки да си отиде (проект)

В 5.7 `revisor` се изключи за по-малко от секунда. Сега е ред на `depurar`, обектът Pod с curl от Урок 3. Преди да го изтриеш, погледни две неща: неговия `terminationGracePeriodSeconds` (не го декларира) и кой процес е номер 1 вътре в контейнера му (`kubectl exec depurar -- ps`). Предвиди колко ще отнеме `kubectl delete pod depurar`, измери го с часовника и обясни числото. После предложи два начина той да си отиде по-бързо, единия в манифеста, а другия в командата.

### Упражнение 4 — Побира ли се четвърта реплика?

С числата от този урок: `revisor` иска `50m` CPU и `32Mi` памет, а при изпълнението на урока всеки работен възел обявяваше 6 CPU (използвай числото от твоя `kubectl get nodes`, ако е друго). В най-много пет изречения: колко реплики на `revisor` биха се побрали на теория в един работен възел, като се брои само CPU? Защо това число е подвеждащо в kind? Кое число би гледал планировчикът, за да реши, `request` или `limit`? И какъв клас QoS би имал `revisor`, ако напишеш равни `requests` и `limits`, `200m` и `64Mi`, и какво би спечелил и какво би платил?

## Решения

### Решение 1

Измерено в `correr.salida.txt`:

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

**`READY 0/1` с `RESTARTS 0`.** Readiness probe се провали два пъти поред (503 на `/`) и `kubelet` отбеляза обекта Pod като неготов, без да го рестартира: това е точно разликата от 5.3.4. EndpointSlice го потвърждава: адресът остава в списъка, но с `ready=false` и `serving=false`, така че никой не му праща трафик.

**Отчетът смени подробността.** В 5.5 казваше `FALLA codigo 503`: услугата отговаряше, лошо. Сега казва `connection refused`: с единствената си реплика извън списъка обектът Service `prueba` няма към кого да прати връзката и я отказва веднага, същият код 7 от Урок 3. `revisor` продължава да казва `FALLA`, но е загубил информация: вече не знаеш **какво** е отговорила услугата, а само че няма никого.

**И остана без входна точка, за да я поправиш.** `POST /modo/sano` през името `prueba` също минава през обекта Service и също се отказва (код 7). Обектът Pod е жив и слуша; онова, което вече не съществува, е пътят. Изходът е да говориш директно с IP адреса на обекта Pod, който не минава през обекта Service: `10.244.2.10`, взет от същия EndpointSlice или от `kubectl get pods -o wide`. Той отговори `modo: sano`, probe отново мина и обектът Pod се върна на `1/1` за няколко секунди. Това е Урок 3 наобратно: там се научи **да не** използваш IP адреси на обекти Pod; тук го използваш нарочно, веднъж, за отстраняване на грешки.

Общият урок: readiness probe изважда обекта Pod от **целия** трафик на Service, включително твоя административен. За услуга като тази, чиято работа е да се проваля видимо, това е грешното решение. Затова манифестът на урока няма такава probe.

### Решение 2

Измерено в `correr.salida.txt`:

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

**27 секунди и контейнерът се рестартира.** Probe пита на всеки 10 секунди и толерира 3 провала: три неуспешни въпроса се побират в около 20 до 30 секунди, в зависимост от това в коя точка от цикъла е била probe, когато си сменил режима. Събитията разказват историята на два реда: `Unhealthy … statuscode: 503` (probe се провали) и `Killing … failed liveness probe, will be restarted` (`kubelet` го уби заради това). `RESTARTS 1 (4s ago)`: рестартирането е било преди 4 секунди. (Събитието `Unhealthy` се повтаря при всеки провал, но клъстерът групира еднаквите в един ред с брояч.)

**А ето сериозното: след рестартирането — `modo: sano`, а отчетът казва `OK`.** Тестовата услуга пази режима си в паметта; при рестартиране тя стартира в режима по подразбиране. Клъстерът „поправи“ симптома, като изтри доказателствата. Ако това беше истинска услуга с истински проблем, `revisor` щеше да отчита провала 27 секунди и после всичко зелено, и някой щеше да заключи, че „се е оправило само“. А следващия път, когато се провали — същото. С правилно написаната probe (`/modo`) в 5.5 услугата остана в `caido`, колкото поиска, и отчетът казваше истината през цялото време. Това е предупреждението на документацията в малък мащаб: liveness probe, която не открива непоправим провал, а нещо друго, накрая нанася щети.

След двете упражнения скриптът отново прилага `kubectl apply -k .` и проверява, че клъстерът отново е точно онова, което казват файловете. Това е `kubectl diff` от 5.4.1, сега наобратно: без разлики излиза с 0 и се отпечатва съобщението.

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

Направи същото в своя клъстер преди Упражнение 3: ако `diff` отпечата нещо, някое упражнение е останало неотменено.

### Решение 3

Измерено в `correr.salida.txt`:

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

**32 секунди: целият срок плюс времето за SIGKILL и почистването.** Манифестът не декларира срок, така че важи този по подразбиране, 30. Процес номер 1 в контейнера е `sleep 3600`. `kubelet` му изпрати SIGTERM, а `sleep` не направи нищо: в Linux процесът с PID 1 в дадено пространство на процесите пренебрегва сигналите, за които не е инсталирал обработчик, а `sleep` не инсталира нито един. Така клъстерът изчака 30-те секунди и изпрати SIGKILL, който не може да се пренебрегне. Междувременно `kubectl delete` чакаше. `revisor`, напротив, инсталира свой обработчик на SIGTERM (затова пише `recibí terminated`) и си отиде за 1 секунда.

Два начина да си отиде по-бързо:

- **В манифеста:** `terminationGracePeriodSeconds: 1` в обекта Pod `depurar`. Той няма какво да довършва подредено; кратък срок не му отнема нищо. (Друга възможност е главният му процес да обработва SIGTERM, например със `sh`, който инсталира `trap`; това е повече работа за Pod за еднократна употреба.)
- **В командата:** `kubectl delete pod depurar --wait=false`, който иска изтриването и се връща веднага, без да чака. Обектът Pod отнема същото време, за да си отиде; само ти престава да го чакаш. Това прави скриптът на Урок 3 накрая. Съществува и `--grace-period` в `kubectl delete`, за да се смени срокът на това изтриване. Помощта му (`kubectl delete --help`) казва, че `--grace-period=1` е незабавното изключване и че 0 се приема само заедно с `--force`, който освен това изтрива обекта Pod от API, без да чака възелът да потвърди, че контейнерът е приключил. Използвай го внимателно.

### Решение 4

Един възможен отговор: „Като се брои само CPU, във възел, който обявява 6 CPU (тези от това изпълнение), се побират 6,000 m / 50 m = 120 реплики, минус онова, което вече искат системните обекти Pod (при това изпълнение възелът вече имаше заделени `150m`, като се брои една реплика). Това число е подвеждащо, защото в kind трите възела обявяват една и съща цяла машина: планировчикът мисли, че има 18 CPU, а са 6, и репликите от трите възела биха се борили за едни и същи ядра. Планировчикът решава с `request`, никога с `limit`: лимитите могат да сумират повече от 100 % от един възел. С равни `requests` и `limits` от `200m` и `64Mi` обектът Pod би бил `Guaranteed`: последният, който се изгонва, когато възелът е притиснат, и с винаги заделен CPU. Би го платил, като резервираш четири пъти повече CPU и двойно повече памет, отколкото `revisor` има нужда в нормалния си ден, така че в един възел биха се побрали четири пъти по-малко реплики.“

## Изтриване на клъстера

Когато приключиш с упражненията, изтрий клъстера на урока. Не оставяй нищо живо на машината:

```text
$ kind delete cluster --name curso-k8s-l5
Deleting cluster "curso-k8s-l5" ...
Deleted nodes: ["curso-k8s-l5-worker" "curso-k8s-l5-control-plane" "curso-k8s-l5-worker2"]
(borrar tardó 1 s)

$ kind get clusters | grep -c curso-k8s-l5
0
```

(Редът в скоби го пише скриптът, който мери изтриването.) `--name` е задължителен: без него kind би изтрил клъстера с име `kind`, който може да е на друг човек или от друг проект.

На твоята машина остават временната папка на `kubeconfig` и двата `token.txt`. Изтриват се така, от `programas/05-salud-recursos-apagado`:

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

`case` пропуска само път, който започва с `/tmp/curso-k8s-l5.` и има нещо след това, точната форма на онзи, който създаде в 5.1.1. Ако `L5_TMP` е празна (например, защото си в друг терминал, където никога не си я задал) или има друга стойност, не изтрива нищо и ти казва защо. Това е същата защита, която използва `correr.sh` при почистване: `rm -rf`, който може да се копира и постави, трябва да се пази сам. Ако вторият терминал от 5.7 още е отворен, затвори го: там направи само `export`. Клъстерът за следващия урок се създава от нулата, точно като този.

## Как разбирам, че съм успял

- [ ] При Pod, който се рестартира сам, различаваш по събитията дали е било liveness probe (`Killing … failed liveness probe`), `OOMKilled` или програмата, която е излязла с грешка.
- [ ] Пишеш трите probes на `revisor` и казваш за всяка какво пита, какво става, ако се провали, и за колко секунди реагира с нейните числа.
- [ ] Обясняваш, с изхода от 5.5 и този от Упражнение 2, защо liveness probe не бива да зависи от никой друг, нито от път, който се проваля нарочно.
- [ ] Разчиташ ред `Liveness:` от `describe` и назоваваш всяко число.
- [ ] Пишеш `requests` и `limits` в миликорове и мебибайтове, без да бъркаш `m` с `M`, и казваш кой използва всяко от тях.
- [ ] При `Pending` разчиташ `FailedScheduling` възел по възел; при `OOMKilled` намираш `137` и тавана, който го обяснява.
- [ ] Обясняваш какво прави клъстерът между `kubectl delete pod` и изчезването на обекта Pod и защо `depurar` се бави повече от 30 секунди, а `revisor` — по-малко от една.
- [ ] Изпълняваш `programas/05-salud-recursos-apagado/correr.sh > /tmp/mi-corrida-l5.txt 2>&1` и сравняваш `/tmp/mi-corrida-l5.txt` с `programas/05-salud-recursos-apagado/correr.salida.txt` (не пренасочвай към този файл: той е еталонът) по онова, което не се променя между изпълненията: три възела `Ready` на `v1.37.0`; шест реда `not yet present on node … loading...`; `33` байта токен и `-rw-------` за двата `token.txt`; `QoS Class: BestEffort` и `30` преди урока; `mismo token`; `kubectl diff` с probes, ресурсите и двата `terminationGracePeriodSeconds: 10` и неговият код 1; само обектите Deployment `configured`; редовете `Limits`, `Requests`, `Liveness`, `Readiness` и `Startup` с техните числа, `QoS Class: Burstable` и `10`; в журнала — ред `GET /salud` на всеки 5 секунди и друг на всеки 10; `RESTARTS 0` при четирите обекта Pod с тестовата услуга в `caido` и `FALLA … codigo 503`; трите възела с еднакви CPU и памет; `OOMKilled`, `OOMKilled 137` и `pidiendo 40 MB`; `Pending`, `timed out waiting for the condition` и `0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 Insufficient cpu`; `revisor: recibí terminated, apagando` и `revisor: apagado limpio`; петте реда с долна граница и таван, всички `Burstable`; `0/1` с `ready=false`, `connection refused` и код 7 в Упражнение 1; `RESTARTS 1`, събитията `Unhealthy … 503` и `Killing … will be restarted` и `modo: sano` в Упражнение 2; `sin diferencias con los archivos`; `30`, `sleep 3600` като PID 1 и изтриване за 30 s или малко повече в Упражнение 3. IP адресите, наставките в имената, възрастите, часът в журнала, CPU и паметта на възлите и техните проценти, точната памет на `revisor` в `crictl stats`, на кой възел попада всеки Pod, редът на редовете от `kind load` и точните секунди до първото рестартиране в Упражнение 2 се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l5`.

## Обобщение

Отговори, без да поглеждаш урока:

1. Какво знаеше клъстерът за `revisor` преди този урок и защо неговият Pod беше `1/1` на 4-тата секунда?
2. Какво пита всяка от трите probes и какво прави клъстерът, когато отговорът е „не“?
3. Кой изпълнява probes и кои HTTP кодове се броят за успех?
4. С `periodSeconds: 10` и `failureThreshold: 3` за колко време реагира една liveness probe?
5. Защо `/salud` не пита тестовата услуга и защо probe на тестовата услуга пита `/modo`, а не `/`?
6. Кой използва `requests` и кой `limits`? Какво става с контейнер, който надхвърли тавана си за CPU, и какво — ако надхвърли този за памет?
7. Какво е `100m` CPU? А `100m` памет?
8. Кои са трите класа QoS и в какъв ред се изгонват обектите Pod, когато възел остане без ресурси?
9. Какво означава код 137?
10. Какво става, по ред, когато изтриеш Pod, и за какво служи `terminationGracePeriodSeconds`?

## Източници

Всички са консултирани на 21 октомври 2026 г.

- [Kubernetes, „Liveness, Readiness, and Startup Probes“](https://kubernetes.io/docs/concepts/workloads/pods/probes/): какво е probe и че я изпълнява `kubelet`; какво пита всяка и какво става при провал; че startup probe спира другите две, докато не успее; че readiness probe изважда IP адреса на обекта Pod от обектите EndpointSlice и работи през целия жизнен цикъл; предупреждението за каскадните провали; *backend* зависимостите в readiness, а не в liveness; моделът с по-голям `failureThreshold` при liveness; полетата на една probe и стойностите им по подразбиране.
- [Kubernetes, „Configure Liveness, Readiness and Startup Probes“](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/): кодовете от 200 до 399 като успех на HTTP probe; startup probe с `failureThreshold * periodSeconds`, за да се покрие най-лошото стартиране, и примерът 30 × 10 s.
- [Kubernetes, „Resource Management for Pods and Containers“](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/): `request` за планировчика и `limit` за `kubelet`; таванът за CPU чрез ограничаване и този за памет чрез убиване поради OOM; единиците за CPU (`100m`, „сто милиCPU“) и за памет (`Mi`, капанът с малкото `m`); че планировчикът сумира `requests` и отказва, дори реалната употреба да е ниска; събитието `FailedScheduling` и `OOMKilled` като случаи за отстраняване на проблеми.
- [Kubernetes, „Pod Quality of Service Classes“](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/): критериите за `Guaranteed`, `Burstable` и `BestEffort` и редът на изгонване.
- [Kubernetes, „Pod Lifecycle“](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): прекратяването на Pod с TERM, срокът от 30 секунди по подразбиране и KILL при изтичането му; изключващите се *endpoints*, отбелязани `terminating` и с `ready` на `false`; растящото изчакване между рестартиранията (10 s, 20 s, 40 s… до 5 минути) и `CrashLoopBackOff`.
- [Kubernetes, „Assign Memory Resources to Containers and Pods“](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/): контейнер, който надхвърля тавана си за памет и завършва `OOMKilled`.
- [Kubernetes, „Deployments“](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxUnavailable` и `maxSurge` от 25 % по подразбиране, закръглени надолу и нагоре.
- [Kubernetes, „Limit Ranges“](https://kubernetes.io/docs/concepts/policy/limit-range/): че по подразбиране контейнерите работят без лимит на ресурсите.
- [kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind create cluster` и `kind load docker-image` с `--name`, и `crictl` вътре във възел.

---

**Следващ:** [Урок 6 — Влизане в клъстера](06-entrar-al-cluster.md)
