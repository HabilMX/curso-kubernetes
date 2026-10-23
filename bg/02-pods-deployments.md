# Урок 2 — Pods и Deployments

Понеделник, 8:50 сутринта. В 9:30 екипът има демонстрация на новия клъстер, а твоята част е най-простата: `revisor` да се появи работещ, с три копия. Образът е на лаптопа ти от петък, изграден и изпробван с `docker run`. Пишеш манифеста, прилагаш го и `kubectl` отговаря `deployment.apps/revisor created`. Отдъхваш си. Искаш списъка с обектите Pod и трите казват едно и също: `ImagePullBackOff`. Някой от екипа, без да вдигне поглед, ти казва: „изтрий го и го приложи пак“. Правиш го. Същото състояние. Правиш го още веднъж. Часът е 9:05, а образът си е там, в твоя `docker image ls`, на два сантиметра от клъстера, който твърди, че не може да го намери.

Изтриването и повторното прилагане нямаше да помогне с нищо в тази ситуация, защото клъстерът не беше объркан: казваше ти точно какво му липсва. Този урок те учи да го чуваш, да му даваш каквото иска и да разбираш кои обекти се раждат, когато приложиш един Deployment. Така, когато нещо се провали в 9:05, ще знаеш къде да погледнеш.

**Време:** 2 × 45 мин

**Какво изграждаш:** `revisor`, работещ в клъстера на курса, с три реплики, които се раждат отново, когато умрат, със защита (hardening) още от първия манифест

**Какво научаваш:** защо твоят Docker и възлите на клъстера не споделят образи и как `kind load docker-image` ги пренася; грешката `ErrImagePull`, предизвикана нарочно, и как се разчита; какво е Pod, ReplicaSet и Deployment и кой на кого е собственик; етикети и селектори; какво е *rollout* и как изглежда историята му; и `securityContext`, който носи всеки контейнер в този курс

**Откъде идваш.** От [Урок 1](01-instalacion-primer-cluster.md): имаш `kubectl` и `kind`, инсталирани с проверена контролна сума, настроен лимит на `inotify` и умееш да създаваш, разглеждаш и изтриваш клъстера на курса от три възела. От [Урок 0](00-que-es-kubernetes.md) носиш картата: `kube-apiserver` пази онова, което декларираш, контролерите го преследват, `kube-scheduler` избира възел, а `kubelet` стартира контейнери. А от [курса по Docker](https://www.habil.mx/bg/courses/docker/) носиш завършения образ на `revisor`, `curso-docker-revisor:1.6.0`.

**Какво не прави този урок.** `revisor` остава да работи, но все още никой не може да говори с него: няма стабилно име, по което да бъде намерен, нито начин да се стигне до него от твоята машина. Това е [Урок 3](03-services-dns.md), с обектите Service и DNS на клъстера. Още не се конфигурира и отвън: списъкът с услуги, които проверява, е записан в манифеста, а [Урок 4](04-configuracion-secretos.md) го изнася в `ConfigMap`. И клъстерът още не знае дали `revisor` е изправен или само жив: probes идват в [Урок 5](05-salud-recursos-apagado.md).

**За изпълненията.** Всички изходи в този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1 и образа на възел `kindest/node:v1.37.0`, фиксиран чрез отпечатъка си, в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l2`. Машината беше Mac с процесор ARM и Docker Engine 29.2.1 във виртуална машина с Linux (Colima), а **не** Linux Mint, който е референтната система на курса. Какво се променя в твоя Mint: архитектурата (`amd64` вместо `arm64`), IP адресите на обектите Pod, случайните наставки в имената на обектите Pod и ReplicaSet, възрастите и на кой възел попада всяка реплика. Командите са същите. Цялата обиколка е в [`programas/02-pods-deployments/`](../programas/02-pods-deployments): `correr.sh` създава клъстера **без** образа на `revisor`, минава през урока по ред, изпълнява Упражнения 1 до 3 и изтрива клъстера; отне 2 минути и 25 секунди, измерени с часовника на терминала; скриптът сам записва колко е отнела всяка дълга стъпка: създаването на клъстера и изчакването да е готов — 34 секунди; зареждането на образа — 2; изтриването му — 1. Изходът му е `correr.salida.txt`. Там частта за навика за сигурност се появява преди тази за *rollout* (2.8), защото скриптът ги изпълнява в този ред.

## След урока ще можеш да

- Проверяваш с `crictl images` дали даден образ е вътре във възел на kind и да го зареждаш с `kind load docker-image`.
- Предизвикваш `ErrImagePull`, разчиташ го с `kubectl describe` и `kubectl get events` и казваш какво означава всеки ред.
- Пишеш по памет скелета на един Deployment (`replicas`, `selector`, `template`) и обясняваш защо селекторът и етикетите на шаблона трябва да съвпадат.
- Проследяваш с `ownerReferences` веригата Deployment → ReplicaSet → Pod и предвиждаш какво става при изтриване на всяка брънка.
- Филтрираш обекти със селектори по етикет (`-l app=revisor`, `-l 'app in (…)'`) и обясняваш какво е етикетът `pod-template-hash`.
- Разчиташ историята на един Deployment с `kubectl rollout history` и предизвикваш подредено рестартиране с `kubectl rollout restart`.
- Обосноваваш всеки ред от `securityContext` на `revisor` и разпознаваш грешката `CreateContainerConfigError`, която предизвиква противоречие в него.

## Защо, преди как

В Урок 0 видя един Deployment, който поддържаше три копия на контейнер, който не правеше нищо. Това беше чистата идея: декларираш „искам три“ и клъстерът преследва това число. Сега е ред на версията с истинска програма и се появяват три въпроса, които играчката криеше.

Първият: **откъде клъстерът взима образа?** Този от Урок 0 вече беше вътре във възела, защото самият Kubernetes го използва. Образът на `revisor` го изгради ти и той живее в твоя Docker. Един възел на kind изглежда, че е „на твоята машина“, но отвътре има собствено хранилище за образи, което не е това на твоя Docker. Това е точната причина за сцената от понеделник и е първото, което ще видиш да се проваля.

Вторият: **какви обекти съществуват и кой за кого се грижи?** Един Deployment не изпълнява контейнери. Той създава ReplicaSet, който създава обекти Pod, а те са онези, които работят. Ако не виждаш тази верига, „изтриване на Pod“ и „изтриване на Deployment“ изглеждат като една и съща операция, а не са: едната се поправя сама за секунда, а другата спира услугата.

Третият: **какво може да направи контейнерът, ако някой го атакува?** С `docker run` се научи да му отнемаш привилегии с `--user`, `--read-only` и `--cap-drop ALL`. В Kubernetes същите решения се записват в манифеста, в блок, наречен `securityContext`, и този курс ги слага още от първия Deployment. Не чакат Урок 7. Сигурността, която се добавя накрая, остава в списък с неща за вършене; онази, която се ражда с манифеста, пътува с него до всеки клъстер.

Урокът има осем части с понятия и след тях обичайните раздели:

1. **Две хранилища за образи** (2.1): твоят Docker и това на всеки възел.
2. **Манифестът на `revisor`, поле по поле** (2.2).
3. **Прилагане и ненамерен образ** (2.3), нарочната грешка.
4. **`kind load docker-image`** (2.4) и клъстерът, който се възстановява сам.
5. **Веригата на собствениците** (2.5): Deployment, ReplicaSet и Pod.
6. **Етикети и селектори** (2.6).
7. **Самостоятелен Pod срещу Pod на Deployment** (2.7).
8. ***Rollout*** (2.8): ревизии, история и рестартиране.

Това е целта. В края на 2.4 `revisor` работи с три реплики в клъстер, който половин минута по-рано нямаше неговия образ:

```text
$ kubectl get deployment,replicaset -l app=revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/revisor   3/3     3            3           32s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/revisor-697fb84f97   3         3         3       32s
```

## Ако нямаш образа от курса по Docker

Този урок използва образа, който предава Урок 10 от курса по Docker, `curso-docker-revisor:1.6.0`. Преди да продължиш, провери, че го имаш:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Ако го нямаш, изгради го от хранилището на онзи курс, с `Dockerfile` от неговия Урок 10 върху папката `programas/revisor` и с `--build-arg VERSION=1.6.0`, като му дадеш точно тага `curso-docker-revisor:1.6.0`. Ако използваш друг образ на твоя собствена услуга, ето какво изисква курсът от него, и си струва да го прочетеш, защото всяка точка обяснява едно решение в манифеста:

- **Слуша HTTP на висок порт**, 8080, и отговаря на `GET /salud`, без да пита никой друг.
- **Работи с цифров потребител, който не е `root`**: 65532, потребителят `nonroot` от образите *distroless*. Манифестът го изисква с `runAsNonRoot: true`.
- **Работи с файлова система само за четене**, с изключение на една папка за данни (`/datos`), която манифестът монтира отделно.
- **Носи собствена проверка на състоянието (health check)** като подкоманда (`/revisor healthcheck`), защото образът няма *shell*, нито `curl`.
- **Има фиксиран таг**, никога `:latest`. Раздел 2.2.3 обяснява защо това има значение в kind.
- **Конфигурира се чрез променливи на средата.** `revisor` изисква `REVISOR_SERVICIOS` със списъка от услуги, които проверява, и разбира `REVISOR_PUERTO`, `REVISOR_REPORTE` и `REVISOR_TOKEN_ARCHIVO`. Променлива, която не чете, се пренебрегва безшумно, така че не измисляй други.

## Понятията

### 2.1 Две хранилища за образи

Този урок използва собствен клъстер, `curso-k8s-l2`, с конфигурацията от три възела от Урок 1, току-що създаден и **без** да му се зарежда нищо. Създай го така, от корена на хранилището на курса, със същото внимание, което научи в Урок 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l2.XXXX)/kubeconfig"
# curso-k8s-l2 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l2 --config programas/02-pods-deployments/kind-curso.yaml
# Debe decir kind-curso-k8s-l2. Si dice otra cosa, no sigas.
kubectl config current-context
```

`export` важи само в този терминал. Ако отвориш друг, повтори `export` със същия път, иначе `kubectl` ще говори с друг клъстер. Изходите в този раздел са от изпълнението на `correr.sh`, който прави точно това:

```text
$ kubectl config current-context
kind-curso-k8s-l2

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l2-control-plane   Ready    control-plane   26s   v1.37.0
curso-k8s-l2-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l2-worker2         Ready    <none>          16s   v1.37.0
```

Първата команда не е украса. Това е навикът от Урок 1: преди да промениш нещо, питаш с кой клъстер говориш. В този урок ще създаваш и изтриваш обекти и `kind-curso-k8s-l2` е единственият отговор, който ти позволява да продължиш. Повтаряй го **преди всеки** `apply`, `delete`, `label` или `rollout restart` в урока, а не само тук. Скриптът го прави сам: преди всяко `kubectl` сравнява контекста и спира, ако не е `kind-curso-k8s-l2`.

Сега въпросът от сцената. Твоят Docker има образа; има ли го възелът? Спомни си от Урок 0, че възелът на kind е контейнер, който носи вътре собствен `containerd`, а този `containerd` има собствено хранилище за образи. За да попиташ него, влизаш във възела и използваш `crictl`, инструмента от командния ред, който говори с *runtime*-а на възела. Ръководството за начало на kind го препоръчва точно за това ([kind, „Quick Start“, раздел „Loading an Image Into Your Cluster“](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)):

```text
$ docker exec curso-k8s-l2-worker crictl images | grep -c curso-docker-revisor
0
[código de salida: 1]
```

Нула. (Изходният код 1 е на `grep`, който така съобщава, че не е намерил нищо; не е повреда на възела.) Образът е на твоята машина и не е във възела. Това са две различни хранилища, макар и двете да живеят на един и същ компютър, и нищо не ги синхронизира.

В истински клъстер това се решава с **регистър**: качваш образа на сървър за образи (Docker Hub, регистъра на твоята фирма или този на облачния ти доставчик) и всеки възел го изтегля оттам. В kind, който е лаборатория на твоята машина, има пряк път: да копираш образа направо от твоя Docker във всеки възел. Този пряк път е `kind load docker-image` и идва в 2.4. Първо ще видиш какво става без него, защото съобщението за грешка е от онези, които ще срещаш най-често в живота си с Kubernetes.

### 2.2 Манифестът на `revisor`, поле по поле

Това е манифестът, който урокът изгражда. Той е **програма**: прилага се сам и живее в `programas/02-pods-deployments/revisor-deployment.yaml`.

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

Изглежда много. Чете се на слоеве, отвън навътре, и всеки слой отговаря на един въпрос.

#### 2.2.1 Какво е и как се казва

Първите три ключа ги носи всеки обект в Kubernetes. `apiVersion: apps/v1` казва в коя група на API живее типът: обектите Deployment живеят в групата `apps`, версия `v1`, която е стабилна. `kind: Deployment` казва типа. А `metadata` носи името (`revisor`) и етикетите на самия Deployment (`app: revisor`). Името е уникално в своето пространство от имена; етикетите, както ще видиш в 2.6, не са, и точно в това е ценността им.

#### 2.2.2 Колко, кои и с какъв шаблон

`spec` е желаното състояние и в един Deployment има три части, които вървят заедно:

- **`replicas: 3`**: колко копия искаш. Това е числото, което клъстерът преследва.
- **`selector`**: как Deployment разпознава **своите** обекти Pod. Тук казва: „моите са онези, които носят етикета `app: revisor`“.
- **`template`**: шаблонът на всеки Pod. Той носи собствени етикети (`app: revisor`) и собствен `spec`, който е този на един Pod: контейнери, томове и сигурност.

Селекторът и етикетите на шаблона **трябва да съвпадат**. Ако шаблонът произвеждаше обекти Pod с `app: otro`, а селекторът търсеше `app: revisor`, Deployment щеше да създава обекти Pod, които никога нямаше да разпознае като свои, и щеше да продължава да създава още, без край. Затова `kube-apiserver` отхвърля Deployment, чийто селектор не съвпада с етикетите на шаблона му, преди да го запише. [Документацията за Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) добавя едно предупреждение, което е добре да имаш предвид още отсега: Kubernetes не пречи на два контролера да имат селектори, които се припокриват, и ако ги имат, те „могат да влязат в конфликт и да се държат неочаквано“. Упражнение 2 ти показва една версия на този проблем.

#### 2.2.3 Контейнерът

Вътре в шаблона `containers` е списък; в този курс той винаги съдържа един-единствен контейнер. Неговите полета:

- **`name: revisor`**: името на контейнера вътре в обекта Pod. Ще го виждаш в събитията като `spec.containers{revisor}`.
- **`image: curso-docker-revisor:1.6.0`**: образът, с фиксирания си таг.
- **`imagePullPolicy: IfNotPresent`**: кога да се изтегля образът. `IfNotPresent` означава „изтегли го само ако вече не е във възела“. [Документацията за образите](https://kubernetes.io/docs/concepts/containers/images/) определя също `Always` (да се пита регистърът всеки път, когато стартира контейнер; *runtime*-ът изтегля само слоевете, които му липсват, но ако регистърът не отговаря или няма образа, се проваля, макар възелът вече да го има) и `Never` (никога да не се опитва изтегляне). Ако пропуснеш полето, Kubernetes решава според тага: с таг, който не е `:latest`, слага `IfNotPresent`, а с `:latest` или без таг слага `Always`. Това е, което прави `:latest` капан в kind: с `Always` възелът би се опитал да отиде до Docker Hub, макар вече да си му заредил образа, и би се провалил. Ръководството на kind предупреждава за това: с `:latest` или без таг политиката по подразбиране е `Always`, и съветва да не се използва `:latest` или да се напише `imagePullPolicy: IfNotPresent` (или `Never`) ([kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)). Манифестът пише `IfNotPresent`, макар това да е стойността по подразбиране, за да не се налага онзи, който го чете, да знае правилото.
- **`ports`**: декларира, че контейнерът слуша на 8080, и му дава име, `http`. Декларирането не публикува нищо и не отваря никакъв порт навън: това е информация за онзи, който чете манифеста, и за обектите, които го използват по-късно. В Урок 3 обектът Service ще сочи порта **по името му**, `http`, а не по номера му.
- **`env`**: променливите на средата. Тук има само една, `REVISOR_SERVICIOS`, онази, която `revisor` изисква, с услуга на име `prueba` на `http://prueba:9000/` и времево ограничение от 2 секунди. Тази услуга още не съществува в клъстера и това няма значение: `revisor` стартира въпреки това и ще я отчете със състояние `FALLA`, когато някой му поиска отчета. В Урок 4 този списък излиза от манифеста и отива в `ConfigMap`.

#### 2.2.4 Томът `datos`

Накрая има един том, `datos`, от тип `emptyDir`, монтиран в `/datos`. Той е там по конкретна причина. Образът от курса по Docker определя `REVISOR_REPORTE=/datos/reporte.json`: всеки път, когато някой му поиска отчета, `revisor` го записва в този файл. Но `securityContext` на контейнера (2.2.5) прави **цялата** му файлова система само за четене. Без том `revisor` би стартирал, без да се оплаче, и би се провалил по-късно, първия път, когато се опита да запише отчет: в кода му този случай отговаря с грешка 500 и съобщението `no pude guardar el reporte`.

`emptyDir` е най-простият начин да се даде място за писане. [Документацията за томовете](https://kubernetes.io/docs/concepts/storage/volumes/) го описва така: създава се, когато обектът Pod бъде разпределен към възел, започва празен и „когато един Pod бъде премахнат от възел по каквато и да е причина, данните в `emptyDir` се изтриват завинаги“. Ако контейнерът падне и се рестартира, данните оцеляват, защото обектът Pod остава на възела. `sizeLimit: 10Mi` му слага таван: един отчет тежи няколко килобайта, а таванът не позволява една грешка да напълни диска на възела. Урок 8 съпоставя този `emptyDir` с постоянен том и измерва какво се губи при всеки от тях.

#### 2.2.5 Двата `securityContext`

Има два блока `securityContext`: един на ниво Pod (`template.spec.securityContext`) и друг на ниво контейнер. Този на Pod важи за всички негови контейнери; този на контейнера — само за него. Разделът „Навикът за сигурност от урока“ ги разглобява ред по ред, като клъстерът показва какво прави всеки. Засега стига идеята: контейнерът работи като потребител 65532, не може да стане `root`, няма никаква специална способност (capability) на ядрото, не може да пише в собствената си файлова система и е под филтъра на системните извиквания, който носи *runtime*-ът.

### 2.3 Прилагане и ненамерен образ

С току-що създадения клъстер и без зареден образ манифестът беше приложен:

```text
$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created
```

Спомни си от Урок 0 какво означава този отговор: обектът е **записан**. Не казва нищо за контейнери. Двадесет секунди по-късно:

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS             RESTARTS   AGE
revisor-697fb84f97-gn68x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-qvs7x   0/1     ImagePullBackOff   0          20s
revisor-697fb84f97-vq4ld   0/1     ImagePullBackOff   0          20s
```

Трите обекта Pod съществуват, всеки вече има възел и нито един не работи: `0/1` в `READY` означава „нула от един контейнер е готов“. Състоянието, `ImagePullBackOff`, е сцената от понеделник. Обърни внимание на това, което **все пак** сработи: Deployment създаде своя ReplicaSet, ReplicaSet създаде три обекта Pod и `kube-scheduler` ги разпредели. Цялата контролна равнина свърши работата си. Онова, което се провали, е в края на веригата, в `kubelet` на всеки възел, който не успя да се сдобие с образа.

Разделът „Грешката, която ще видиш“ разчита тази грешка ред по ред. Кратката версия, за да продължим: `kubelet` потърси образа във възела, не го намери и, тъй като политиката е `IfNotPresent`, се опита да го изтегли. Образът не казва от кой регистър идва, така че отиде в Docker Hub, където не съществува. Опитва отново, като всеки път чака малко повече. Изтриването и повторното прилагане не променят нищо от това: новият Pod попада на възел, който също няма образа, и стига до същото място.

### 2.4 `kind load docker-image`: пренасяне на образа до всеки възел

Лекарството е да дадеш на възела каквото иска:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 --name curso-k8s-l2
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-worker2", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l2-control-plane", loading...
```

`kind` извади образа от твоя Docker и го копира вътре във **всеки** възел на клъстера, по един на ред: „все още не е на еди-кой си възел, зарежда се“. Появява се и контролният възел, макар там да не работи нито един Pod на `revisor`. kind не знае къде ще използваш образа и го слага на всички. Отне 2 секунди, защото образът тежи около 16 MB. `--name curso-k8s-l2` е задължителен, когато клъстерът не се казва `kind`, което е името по подразбиране. Без него kind би търсил клъстер, който не съществува, а на машина с няколко клъстера това е начинът да си сигурен, че зареждаш образа в своя, а не в друг.

Сега възелът вече го има:

```text
$ docker exec curso-k8s-l2-worker crictl images | grep curso-docker-revisor
docker.io/library/curso-docker-revisor          1.6.0                70e09194319be       3.68MB
```

Виж името, с което е записан: `docker.io/library/curso-docker-revisor`. Това е пълното име, което отговаря на `curso-docker-revisor`: когато образ не казва от кой регистър идва, се приема, че е от Docker Hub (`docker.io`), а ако не казва и от кой потребител, от пространството му с официални образи (`library`). Документацията за образите го обяснява с примера на `busybox`, който е равен на `docker.io/library/busybox:latest`. Това е същото име, което се появяваше в грешката от 2.3, и затова сега `kubelet` го намира. (Числата изглеждат различни, но си имат обяснение. `crictl` казва 3.68MB. С Docker Engine 29 `docker image ls curso-docker-revisor:1.6.0` показва две колони: `DISK USAGE` 16.2MB, колкото заема разкомпресиран на диска, и `CONTENT SIZE` 3.68MB, компресираното съдържание; `crictl` отчита второто. Ако твоят Docker е по-стар, `docker image ls` показва едно-единствено число и то може да не съвпада. Идентификаторът на `crictl`, `70e09194319be`, също не е `sha256:bd1b2e7d…` от `kind load`: всеки инструмент идентифицира образа с различен отпечатък. Че е един и същ, го доказват името и тагът и това, че `kubelet` го намира в следващата стъпка.)

Не е нужно да прилагаш нищо отново. `kubelet` продължаваше да опитва сам; при следващия опит намери образа и стартира контейнера:

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

Това е дълбокият урок от сцената: **клъстерът се възстанови сам, защото желаното състояние никога не се промени**. То продължаваше да казва „три реплики с този образ“. Единственото, което липсваше, беше образът, и щом пристигна, всяка част довърши работата си. Изтриването и повторното прилагане щяха да бъдат в най-добрия случай безполезни.

Погледни колоната `NODE`. Две реплики останаха на `curso-k8s-l2-worker2` и една на `curso-k8s-l2-worker`. Deployment се грижи за това **колко** реплики има, а не **къде** отиват. Урок 0 го предвиди: *scheduler*-ът се старае да разпределя, но не го гарантира, и при друго изпълнение може да попаднат различно. Ако `worker2` се изключи, две от трите реплики ще умрат едновременно. Гарантираното разпределение се декларира със собствени правила и курсът го прави, когато `revisor` трябва да преживее изключен възел (Урок 9). Обърни внимание и на колоната `IP`: всеки Pod има свой адрес и той се сменя всеки път, когато Pod се роди отново. Затова никой не бива да говори с Pod по неговия IP адрес и затова съществува Урок 3.

Журналът на `revisor` потвърждава, че програмата е стартирала:

```text
$ kubectl logs deployment/revisor
Found 3 pods, using pod/revisor-697fb84f97-gn68x
revisor 1.6.0 escuchando en :8080 (1 servicio(s))
```

`kubectl logs deployment/revisor` е пряк път: избира един от обектите Pod на Deployment, показва ти неговия журнал и ти казва кой е избрал. Това е същият ред, който се отпечатваше с `docker run` в курса по Docker: образът е същият, смени се само кой го изпълнява.

### 2.5 Веригата на собствениците: Deployment, ReplicaSet и Pod

В Урок 0 видя веригата нарисувана. Сега можеш да я прочетеш в самия клъстер, защото всеки обект казва кой е собственикът му в поле, наречено `metadata.ownerReferences`. [Документацията за собствениците и зависимите обекти](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/) го обяснява така: зависимите обекти имат това поле, което сочи към собственика им, и Kubernetes го попълва сам за обектите, които създават контролерите, като обектите ReplicaSet.

```text
$ kubectl get pod revisor-697fb84f97-gn68x -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ReplicaSet/revisor-697fb84f97

$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
Deployment/revisor

$ kubectl get deployment revisor -o jsonpath='{.metadata.ownerReferences}{"\n"}'

```

Обектът Pod принадлежи на ReplicaSet, ReplicaSet принадлежи на Deployment, а Deployment не принадлежи на никого: отговорът му е празен ред. Deployment го написа ти и собственикът си ти.

Опцията `-o jsonpath=…` заслужава малко внимание, защото курсът я използва много. `kubectl get` може да върне целия обект (`-o yaml`), но почти винаги искаш само една стойност. `jsonpath` ти позволява да поискаш поле по неговия път: `{.metadata.ownerReferences[0].kind}` означава „в обекта влез в `metadata`, после в `ownerReferences`, вземи първия елемент и ми дай неговия `kind`“. `{"\n"}` накрая само добавя нов ред.

Всяка брънка има различна работа:

| Обект | Създава го | Работата му | Ако го изтриеш |
|---|---|---|---|
| **Deployment** | ти | да пази желаното състояние и да управлява версиите: когато промениш шаблона, създава нов ReplicaSet и прехвърля репликите от стария към новия | изтриват се неговите обекти ReplicaSet и Pod; услугата спира |
| **ReplicaSet** | Deployment | да брои: да има толкова обекти Pod с точно неговия шаблон, колкото казва `replicas` | Deployment създава друг същия, но `kubectl delete` изтрива каскадно неговите обекти Pod: измерено, трите обекта Pod минаха в `Terminating` едновременно и заместникът стартира от нулата, с прекъсване; затова не се пипат ръчно |
| **Pod** | ReplicaSet | да изпълнява контейнера | ReplicaSet създава друг |

[Документацията за ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/) определя предназначението му с едно изречение: „да поддържа стабилен набор от реплики на Pod, работещи по всяко време“. И препоръчва да не се използват директно: „препоръчваме да използвате Deployments вместо директно ReplicaSets“, освен в специални случаи. Документацията за Deployments е още по-категорична: „не управлявайте ReplicaSets, които принадлежат на Deployment“. В този курс никога няма да напишеш ReplicaSet. Ще ги **виждаш**, защото разчитането им обяснява какво прави Deployment.

А обектът Pod? [Документацията за Pods](https://kubernetes.io/docs/concepts/workloads/pods/) го казва без заобикалки: „рядко ще създавате отделни обекти Pod директно в Kubernetes, дори единични Pod“, защото обектите Pod са проектирани като „сравнително ефимерни, за еднократна употреба“ същности. Раздел 2.7 ти показва какво означава „за еднократна употреба“ с един Pod без собственик.

### 2.6 Етикети и селектори

Дотук си писал `-l app=revisor` много пъти. Време е да видиш какво стои зад това.

**Етикетът** (label) е двойка ключ и стойност, закачена за обект. [Документацията за етикетите](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/) ги определя като двойки, които „служат за задаване на идентифициращи атрибути на обектите, значими за потребителите“, и добавя онова, което ги прави полезни: „за разлика от имената и UID, етикетите не са уникални“. Много обекти носят един и същ етикет. Със **селектор** по етикети избираш набор от обекти и според същата страница селекторът е „основният примитив за групиране в Kubernetes“.

Ето как изглеждат етикетите на обектите Pod на `revisor`:

```text
$ kubectl get pods --show-labels
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
revisor-697fb84f97-gn68x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-qvs7x   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
revisor-697fb84f97-vq4ld   1/1     Running   0          33s   app=revisor,pod-template-hash=697fb84f97
```

`app=revisor` го сложи ти, в шаблона. Но има още един, който не си написал: `pod-template-hash=697fb84f97`. Сложи го Deployment, а числото е същата наставка, която носи името на ReplicaSet. Погледни селектора на ReplicaSet:

```text
$ kubectl get replicaset revisor-697fb84f97 -o jsonpath='{.spec.selector}{"\n"}'
{"matchLabels":{"app":"revisor","pod-template-hash":"697fb84f97"}}
```

ReplicaSet не търси само `app: revisor`: търси `app: revisor` **и** `pod-template-hash: 697fb84f97`. Документацията за Deployments обяснява защо: контролерът за Deployments добавя този етикет към всеки ReplicaSet, който създава, изчислен с *hash* на шаблона на Pod, и „този етикет гарантира, че дъщерните ReplicaSets на един Deployment не се припокриват“. Когато промениш шаблона, в 2.8, ще се появи друг ReplicaSet с друг *hash*. Всеки ще брои само собствените си обекти Pod, макар всички да носят `app=revisor`. Същата страница има предупреждение в червено: „не променяйте този етикет“.

Селекторите имат две форми. Тази по **равенство** е онази, която използваше: `app=revisor`, или `app!=revisor` за обратното. Тази по **множества** пита за принадлежност:

```text
$ kubectl get pods -l 'app in (revisor,prueba)' -o name
pod/revisor-697fb84f97-gn68x
pod/revisor-697fb84f97-qvs7x
pod/revisor-697fb84f97-vq4ld

$ kubectl get pods -l app=prueba
No resources found in default namespace.
```

Първата иска обектите Pod, чийто етикет `app` е `revisor` или `prueba`, и тъй като все още няма нито един `prueba`, връща само тези на `revisor`. Втората го потвърждава. Две правила от документацията, за да не сбъркаш: няколко изисквания, разделени със запетая, се комбинират с „и“ (`app=revisor,pod-template-hash=697fb84f97` изисква и двете), а оператор „или“ между различни изисквания **не съществува**. За „или“ върху един и същ ключ има `in`.

`No resources found` не е грешка. Това е отговор: няма нищо, което да съвпада. Да различаваш „няма нищо“ от „нещо се провали“ е част от разчитането на това, което казва клъстерът.

Защо курсът винаги търси по етикет и никога по име на Pod? Защото името се сменя всеки път, когато обектът Pod се роди отново, а етикетът — не. Команда, в която пише `revisor-697fb84f97-gn68x`, престава да върши работа в мига, в който този Pod умре. Такава, в която пише `-l app=revisor`, продължава да работи през заместванията, в рамките на същото пространство от имена и докато никой друг Pod не използва този етикет (Упражнение 2 показва какво става, когато някой го използва). Обектите Service от Урок 3 избират своите обекти Pod по същия начин: по етикет. Това прави важно онова, което показва Упражнение 2.

### 2.7 Самостоятелен Pod срещу Pod на Deployment

#### 2.7.1 Самостоятелният Pod

Един Pod може да се създаде сам, без Deployment. Този манифест е **програма** (`fig02_01.pod.yaml`). Това е същият шаблон от Deployment, но написан като Pod, с фиксирано име и **без** етикета `app: revisor`, за да не го сбърка никой ReplicaSet с някой от своите:

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

Обърни внимание на разликата с Deployment: `apiVersion: v1` (обектите Pod живеят в основната група на API, която няма име) и `kind: Pod`. Онова, което в Deployment беше вътре в `template.spec`, тук е директно в `spec`. Един Deployment до голяма степен е шаблон на Pod с брояч отгоре.

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

`dueños=` празно: никой не е собственик на този Pod. Беше изтрит, скриптът изчака пет секунди и `revisor-suelto` вече го няма. Никой не го възстанови, защото нито един контролер нямаше „искам един `revisor-suelto`“ в желаното си състояние.

Внимавай с онова, което самостоятелният Pod **все пак** прави. Ако неговият **процес** падне, `kubelet` го стартира отново в същия Pod, защото полето `restartPolicy` по подразбиране е `Always` ([kubernetes.io, „Pod Lifecycle“](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). Прилича на `docker run --restart always` на една-единствена машина: издържа програмата да се срине, а колоната `RESTARTS` го отброява. Онова, което не издържа, е загубата на самия Pod. Документацията за Pods казва, че един Pod остава на своя възел, „докато не приключи, не бъде изтрит обектът Pod, не бъде изгонен поради липса на ресурси или възелът не откаже“, а тази за жизнения му цикъл добавя, че един Pod никога не се „препланира“ към друг възел: вместо това някой може да създаде нов, почти идентичен. При самостоятелния Pod този някой не съществува. Ако го изтрият, изгонят или се изключи възелът му, край.

#### 2.7.2 Обектът Pod на Deployment

Сега същото с Pod, който има собственик:

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

Секунда по-късно има нов Pod, `nrwht`, а събитията разказват историята: три създавания в началото и четвърто — възстановяването. Това е термостатът от Урок 0, сега с твоята програма.

`-o custom-columns=…` е сестрата на `jsonpath` за таблици: казваш му кои колони искаш и от кое поле идва всяка. Използва се тук, за да се побере всяко събитие на един ред.

Сравнението е най-важната идея в урока: **обектът Pod работи, но онзи, който го възстановява, е собственикът му.** Pod без собственик рестартира контейнера си, ако процесът падне, но самият Pod не се ражда отново: ако бъде изтрит, изгонен или загуби възела си, край. Затова в този курс всичко, което трябва да продължи да работи, живее вътре в Deployment. Самостоятелни обекти Pod се появяват само за отстраняване на грешки или за да се демонстрира нещо и се изтриват накрая.

### 2.8 *Rollout*: ревизии, история и рестартиране

#### 2.8.1 Какво е ревизия

**Rollout** е преминаването от една версия на обектите Pod към друга. Документацията за Deployments казва кога се случва, и правилото е точно: *rollout* се задейства „ако и само ако шаблонът на Pod в Deployment (`.spec.template`) се промени“, например етикетите или образът му. Други промени, като мащабирането от три на пет реплики, не го задействат. Всеки *rollout* оставя **ревизия** в историята, а всяка ревизия е един ReplicaSet.

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
```

Една ревизия: тази, която се роди с `apply`. Колоната `CHANGE-CAUSE` казва `<none>`, защото никой не е записал причината. Може да се попълни с анотация на Deployment; курсът не го прави, защото причината за всяка промяна живее в историята на Git на твоите манифести.

#### 2.8.2 Рестартиране, без да се променя нищо

Понякога искаш всички обекти Pod да бъдат заменени, без да се променя образът или конфигурацията: например, за да прочетат отново нещо, което се е променило извън тях. Ръчното им изтриване върши работа, но ги изтриваш всичките наведнъж и услугата остава за момент без реплики. За това съществува `kubectl rollout restart`:

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

Прочети напредъка на `rollout status`: един от три нови, два от три и накрая „една стара реплика чака да приключи“. Обектите Pod не бяха заменени изведнъж: създаваше се един нов и се махаше един стар, на смени. Това е стратегията по подразбиране на Deployment, `RollingUpdate`. Двата ѝ регулатора са 25 %, ако не ги пипаш: `maxSurge` — колко обекта Pod в повече може да има по време на промяната (закръгля се нагоре), и `maxUnavailable` — колко може да липсват (закръгля се надолу). При три реплики 25 % са 0.75: `maxSurge` става 1, а `maxUnavailable` — 0. Казано просто: по време на промяната може да има до четири обекта Pod и контролерът не маха нито един стар, докато новият не е готов, така че планът му никога не пада под три налични. Това е обещание на контролера, не на вселената: ако в този момент падне възел или умре процес, бройката намалява по причини извън него. А при друг брой реплики закръглянето се променя: при четири 25 % вече е 1 и `maxUnavailable` би бил 1. Урок 9 се връща към това с истинско натоварване и измерва дали се губи някоя заявка.

И резултатът: нов ReplicaSet, `revisor-55cc969586`, с трите реплики, и старият, `revisor-697fb84f97`, на `0 0 0`. Старият **не беше изтрит**: остана празен, като запис на ревизия 1. Документацията казва, че по подразбиране се пазят 10 стари ReplicaSet (`revisionHistoryLimit`) и че изтриването на един означава да загубиш възможността да се върнеш към тази ревизия. Урок 9 използва тази възможност с `rollout undo`.

Защо имаше *rollout*, ако не си променил нищо? Нещо все пак се промени:

```text
$ kubectl rollout history deployment/revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>


$ kubectl get deployment revisor -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
{"kubectl.kubernetes.io/restartedAt":"2026-10-21T03:55:53-06:00"}
```

`rollout restart` добави към шаблона анотация с часа на рестартирането. Шаблонът се промени и правилото „ако и само ако“ се изпълни: нов шаблон, нов *hash*, нов ReplicaSet, ревизия 2. Няма магия, само същото правило, приложено към поле, което си сложил, без да го въвеждаш.

Тази анотация не е в твоя файл и това има последица. Ако утре приложиш `revisor-deployment.yaml` отново, `kubectl apply` няма да я махне, защото управлява само полетата, които файлът декларира (Урок 0 обясни анотацията `last-applied-configuration`, чрез която води тази сметка). Крайното състояние на този урок се проверява с `kubectl diff`, който не намира разлики.

## Грешката, която ще видиш

Грешката в този урок е тази от 2.3: `ErrImagePull`, която после става `ImagePullBackOff`. Предизвикана е нарочно и се разчита по ред, защото този ред служи за всеки Pod, който не стартира.

**Първо, състоянието.** `kubectl get pods` ти даде `ImagePullBackOff` и `0/1`. Колоната `STATUS` ти казва **на кой етап** е заседнал обектът Pod. Самото `Pending` обикновено означава „все още няма възел“ (*scheduler*-ът не е намерил място; ще го видиш в Урок 5). Когато има нещо по-конкретно, `kubectl` показва него вместо фазата: `ImagePullBackOff` е „вече има възел, а `kubelet` на този възел не успява да се сдобие с образа“, а `CrashLoopBackOff` би било „образът стартира, а програмата пада“. Един нюанс: **фазата** на Pod, която е друго поле, остава `Pending`, докато образът се изтегля. Документацията за жизнения цикъл го казва така: `Pending` включва времето на изчакване да бъде разпределен възел и „времето за изтегляне на образите по мрежата“ ([kubernetes.io, „Pod Lifecycle“](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)). Фазата се разчита с `kubectl get pod <pod> -o jsonpath='{.status.phase}'`. Само от колоната `STATUS` вече знаеш коя част от Урок 0 да питаш.

**Второ, събитията.** Клъстерът оставя следа от всеки опит:

```text
$ kubectl get events --field-selector reason=Failed -o custom-columns=OBJETO:.involvedObject.name,MENSAJE:.message | head -4
OBJETO                     MENSAJE
revisor-697fb84f97-gn68x   Failed to pull image "curso-docker-revisor:1.6.0": failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0": failed to resolve reference "docker.io/library/curso-docker-revisor:1.6.0": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
revisor-697fb84f97-gn68x   Error: ErrImagePull
revisor-697fb84f97-gn68x   Error: ImagePullBackOff
```

Първото съобщение е дълго и се чете като верига от „защото“, отляво надясно:

- `Failed to pull image "curso-docker-revisor:1.6.0"`: не успях да изтегля образа, който поиска…
- `failed to pull and unpack image "docker.io/library/curso-docker-revisor:1.6.0"`: …който, с пълното си име, е този от Docker Hub…
- `failed to resolve reference`: …защото не успях да намеря тази препратка…
- `pull access denied, repository does not exist or may require authorization`: …защото Docker Hub ми отказа достъп: хранилището не съществува или изисква идентификационни данни.

Решаващата следа е `docker.io/library/…`. Възелът е отишъл да търси твоя образ в интернет. Никога не е погледнал в твоя Docker, защото не може: това не е неговото хранилище. Docker Hub казва „не съществува или ти трябва разрешение“ и не уточнява кое от двете. Така се държат регистрите, за да не издават кои частни хранилища съществуват. Тук е първото: не съществува.

**Трето, `describe`.** `kubectl get events` смесва събитията на цялото пространство от имена. `kubectl describe pod` събира всичко за **един** Pod, а събитията му — накрая. Внимание: повтарящо се събитие се групира в един ред и се подрежда по **последния** път, когато се е случило, така че `Pulling (x2 over 20s)` се появява след `BackOff`, макар да се е случило първо:

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

(`sed` реже изхода, за да покаже само от `Events:` нататък; над това `describe` показва образа, възела, томовете, `securityContext` и условията на обекта Pod.) Колоната `From` казва **кой** говори и тя те учи най-много. В логически ред:

- `default-scheduler`, `Scheduled`: *scheduler*-ът разпредели обекта Pod към `curso-k8s-l2-worker2`. Неговата част мина добре.
- `kubelet`, `Pulling`: `kubelet` на този възел се опита да изтегли образа. `(x2 over 20s)` означава, че същото събитие се е случило два пъти за 20 секунди; клъстерът групира повторенията, вместо да записва всички.
- `kubelet`, `Failed` с `ErrImagePull`: опитът се провали.
- `kubelet`, `BackOff` и `Failed` с `ImagePullBackOff`: `kubelet` реши да изчака преди следващия опит.

**`ErrImagePull` и `ImagePullBackOff` са един и същ проблем в два момента.** `ErrImagePull` е провалът на един опит. `ImagePullBackOff` е изчакването между опитите. Документацията за образите го обяснява: частта `BackOff` показва, че Kubernetes ще продължи да опитва, с изчакване, което расте при всеки опит, до фиксиран лимит от 300 секунди (5 минути). Затова обектът Pod редува двете състояния, докато не му дадеш образа. И затова възстановяването в 2.4 не беше мигновено за всеки Pod, който е бил по средата на дълго изчакване: `kubelet` взима образа при следващия си опит, не по-рано. Ако един Pod чака отдавна и не искаш да изчакваш, изтриването му **след** като си поправил причината наистина помага: ReplicaSet създава друг, който опитва веднага. Изтриването **преди** да поправиш е онова, което направи екипът от сцената.

**Редът, за всеки Pod, който не стартира:** състоянието (`get pods`), `describe` на обекта Pod (събитията му и колоната `From`) и, ако контейнерът е успял да стартира, неговите `logs`. Първо се разчита и после се променя нещо. А онова, което се променя, е причината, не обектът Pod.

## Навикът за сигурност от урока: `securityContext` още от първия манифест

Таблицата с навици на курса възлага на този урок `securityContext` на първия Deployment: без `root`, без ескалация на привилегии, без capabilities, файлова система само за четене и профил `seccomp`. Ето как беше приложен в клъстера:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
{"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}}
{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}
```

Първият ред е този на обекта Pod; вторият — на контейнера. Ред по ред, с онова, което предотвратява всеки от тях:

| Ред | Какво прави | Какво предотвратява | Еквивалентът му в Docker |
|---|---|---|---|
| `runAsNonRoot: true` | `kubelet` отказва да стартира контейнера, ако той би работил като потребител 0 | зле направен образ или зле написан ред да работи като `root`, без никой да забележи | няма: Docker не проверява |
| `runAsUser: 65532`, `runAsGroup: 65532` | фиксира цифровите потребител и група, с които работи процесът | зависимостта от това, което казва образът; числото остава записано в манифеста | `--user 65532:65532` |
| `seccompProfile: RuntimeDefault` | прилага филтъра на системните извиквания, който носи *runtime*-ът | процесът да използва извиквания към ядрото, от които един HTTP сървър никога не се нуждае. **Без този ред Kubernetes изпълнява контейнера без филтър (`Unconfined`)**, освен ако `kubelet` няма включена опцията `seccompDefault` | Docker прилага своя профил по подразбиране, без да го искаш; Kubernetes — не |
| `allowPrivilegeEscalation: false` | един процес не може да получи повече привилегии от родителя си, например като изпълни двоичен файл *setuid* | някой, който влезе в контейнера, да стане `root` отвътре | `--security-opt no-new-privileges` |
| `capabilities: drop: ["ALL"]` | премахва всички специални способности (capabilities) на ядрото | процесът да може например да сменя собственика на файлове (`CHOWN`) или да отваря сурови *sockets*, за да изработва мрежови пакети (`NET_RAW`) | `--cap-drop ALL` |
| `readOnlyRootFilesystem: true` | монтира файловата система на контейнера само за четене | нападател да остави инструменти или да промени програмата | `--read-only` |

Определенията идват от официалното ръководство [„Configure a Security Context for a Pod or Container“](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/). За `allowPrivilegeEscalation` например то казва, че „контролира дали един процес може да получи повече привилегии от родителския си процес“ и че включва флага `no_new_privs` на ядрото. А ръководството за `seccomp` обяснява разликата с Docker, която отбелязва таблицата: ако опцията `seccompDefault` е включена, обектите Pod използват `RuntimeDefault`, когато не искат друг профил; „в противен случай стойността по подразбиране е `Unconfined`“ ([kubernetes.io, „Restrict a Container's Syscalls with seccomp“](https://kubernetes.io/docs/tutorials/security/seccomp/)). Затова редът се пише винаги.

Има една отправна точка, която е по-важна от всяко ръководство: **Pod Security Standards**, трите нива на сигурност, които Kubernetes определя ([kubernetes.io, „Pod Security Standards“](https://kubernetes.io/docs/concepts/security/pod-security-standards/)). Най-строгото, `restricted`, е предназначено да „налага текущите най-добри практики за подсилване на защитата на обектите Pod“. То изисква четири от тези редове: работа като не-`root` (`runAsNonRoot: true`), забрана на ескалацията на привилегии, премахване на **всички** capabilities (позволява да се добави обратно само `NET_BIND_SERVICE`) и изрично фиксиране на профила `seccomp` („както профилът `Unconfined`, така и липсата на профил са забранени“). Освен това `restricted` забранява да се иска `runAsUser: 0` (точно каквото прави `fig02_02.raiz.yaml` по-долу) и позволява само определени типове томове, сред тях `emptyDir`. Манифестът на `revisor` изпълнява всичко това още от днес. Когато Урок 7 постави пространството от имена на ниво `restricted`, `revisor` вече ще е готов и няма да се налага да се преписва нищо в последния момент.

`readOnlyRootFilesystem` **не** се изисква от `restricted`. Курсът го слага, защото `revisor` го понася: единственият му файл за писане отива в `/datos`, а за това съществува `emptyDir`.

**Какво се вижда отвътре.** Образът на `revisor` няма *shell*. Беше проверено:

```text
$ kubectl exec deployment/revisor -- /revisor healthcheck
sano

$ kubectl exec deployment/revisor -- /revisor version
1.6.0

$ kubectl exec deployment/revisor -- sh -c 'id'
error: Internal error occurred: Internal error occurred: error executing command in container: failed to exec in container: failed to start exec "d8ccff765090d70932ea2f15a41fa34693c57f56ad0106eeb012a0a816fa701d": OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH
[código de salida: 1]
```

`kubectl exec` изпълнява програма вътре в контейнер, който вече работи, като `docker exec`. С `deployment/revisor` избира един от неговите обекти Pod. Двете подкоманди на самия `revisor` работят: `healthcheck` проверява неговия `/salud` отвътре и отговаря `sano`, а `version` казва `1.6.0`. Но `sh` не съществува: `executable file not found in $PATH`. Това не е дефект, а защита. Който успее да изпълни нещо вътре в контейнера, не намира нито *shell*, нито `curl`, нито мениджър на пакети. Начинът за отстраняване на грешки без *shell* идва в Урок 3: отделен Pod, направен за това.

Монтиранията на контейнера потвърждават тома за данни и разкриват още нещо:

```text
$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.containers[0].volumeMounts}{"\n"}'
[{"mountPath":"/datos","name":"datos"},{"mountPath":"/var/run/secrets/kubernetes.io/serviceaccount","name":"kube-api-access-vxlgn","readOnly":true}]
```

`/datos` е твоят `emptyDir`. Второто монтиране не си го написал ти: Kubernetes монтира в обекта Pod **идентификационни данни** за разговор с `kube-apiserver`, тези на сервизния акаунт (service account) по подразбиране на пространството от имена. `revisor` никога не говори със сървъра на API, така че не се нуждае от тях. Остава записано като известен дълг, със своя урок: Урок 7 дава на `revisor` собствен сервизен акаунт, без права, и оттам нататък всички акаунти в курса носят `automountServiceAccountToken: false`, за да не се монтират тези идентификационни данни.

**Предпазната мрежа в действие.** `runAsNonRoot` изглежда излишно, ако вече си написал `runAsUser: 65532`. Стойността му се проявява, когато някой сгреши. Този Pod (`fig02_02.raiz.yaml`, **програма**, която се проваля нарочно) иска две неща едновременно: да не е `root` и да е потребител 0, който е `root`:

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

`kube-apiserver` прие обекта Pod (`created`), защото във формата му няма нищо невалидно. Онзи, който отказа, беше `kubelet`, когато тръгна да създава контейнера: `CreateContainerConfigError`, „конфигурацията на контейнера не може да се използва“, а събитието казва защо: „`runAsUser` на контейнера нарушава политиката за не-`root`“. Образът беше във възела и програмата така и не стигна до изпълнение. Това е функцията на `runAsNonRoot`: втори ключ, който не зависи от това дали първият е написан правилно. Обектът Pod беше изтрит накрая.

**Какво защитава и какво не.** `securityContext` ограничава онова, което може да направи **процесът**, ако някой го компрометира: да не е `root`, да не получава привилегии, да не променя файловете си. Той не защитава `revisor` от злонамерени заявки (това е работа на кода му), не решава кой може да говори с него (това е мрежата, Урок 7) и не защитава твоята машина от възела на kind, който, както видя в Урок 0, е привилегирован контейнер.

## Какво се прави погрешно

**Да изтриеш и приложиш отново при грешка.** Това е сцената от понеделник. Ако причината не се е променила, новият Pod стига до същата грешка. Първо се разчита `describe`, после се поправя причината.

**Да използваш `:latest` в kind.** С `:latest` или без таг политиката за изтегляне по подразбиране е `Always` и възелът се опитва да отиде до регистъра, макар вече да си му заредил образа. Освен това `:latest` не казва коя версия работи: два възела могат да имат два различни образа с един и същ таг. Фиксиран таг и `IfNotPresent`.

**Да забравиш `--name` в `kind load docker-image`.** Без него kind търси клъстера с име `kind`. Ако не съществува, се проваля. Ако съществува и не е твоят, си заредил образа на грешното място, а твоят клъстер продължава да е без него.

**Да създаваш самостоятелни обекти Pod за нещо, което трябва да продължи да работи.** Pod без собственик не се ражда отново. За услуга — винаги Deployment.

**Да слагаш на самостоятелен Pod етикетите на Deployment.** Ще го видиш в Упражнение 2: Deployment не го осиновява, но всичко, което търси по този етикет, го намира. Това е Pod, който се появява в преброяванията и в трафика, без никой да се грижи за него.

**Да редактираш или изтриваш ръчно ReplicaSet на Deployment.** Deployment е негов собственик и го изгражда наново. Документацията го казва без заобикалки: не управлявай ReplicaSets, които принадлежат на Deployment.

**Да пипаш етикета `pod-template-hash`.** Слага го Deployment, за да не се застъпват неговите ReplicaSets. Промяната му разваля това разделение.

**Да махаш `securityContext`, „за да тръгне“.** Ако контейнер не стартира със `securityContext` на курса, проблемът почти винаги е в образа (работи като `root`, пише където не бива) и се поправя в образа или с том, а не като се отнемат защити от манифеста.

**Да се доверяваш на `Running`.** Без `emptyDir` `revisor` също щеше да е `Running` и `1/1`, и щеше да се провали при първата заявка, която го накара да запише отчета. `Running` означава, че процесът е жив, а не че си върши добре работата. Урок 5 учи клъстера да прави разлика.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред и от състоянието, в което остана в края на 2.8. Преди всяко упражнение `kubectl config current-context` трябва да казва `kind-curso-k8s-l2`; ако казва нещо друго, не продължавай. `correr.sh` ги изпълнява по същия начин, а изходът му е в `correr.salida.txt`. **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще стане. Четвъртото се пише със собствени думи.

### Упражнение 1 — Да извадиш Pod от стадото

Избери един от обектите Pod на `revisor` и смени етикета му `app` на друга стойност:

```bash
kubectl label pod <un-pod-del-revisor> app=fuera --overwrite
```

Предвиди: колко обекта Pod има пет секунди по-късно? Обектът Pod, който промени, продължава ли да работи? Кой е собственикът му сега? Провери го с `kubectl get pods -L app` (опцията `-L` добавя колона със стойността на този етикет) и с `jsonpath` от 2.7.1, `-o jsonpath='dueños={.metadata.ownerReferences}{"\n"}'`, който върши работа и когато списъкът със собственици е празен (`[0]` от 2.5 върху празен списък отпечатва само една наклонена черта, `/`, и излиза с код 0, без да предупреди, че няма нищо). Накрая изтрий обекта Pod, който извади.

### Упражнение 2 — Обектът Pod, който се промъква (проект)

`fig02_03.adoptado.yaml` е самостоятелен Pod, `revisor-extra`, идентичен с тези на `revisor` и **с** етикета `app: revisor`:

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

Преди да го приложиш, отговори на трите въпроса от коментара му. После го приложи и провери с `kubectl get pods -l app=revisor`, `kubectl get deployment revisor` и селектора на обектите ReplicaSet. Накрая обясни какъв проблем би причинил този Pod, когато в Урок 3 един Service избира своите обекти Pod по `app: revisor`. Изтрий го накрая.

### Упражнение 3 — Таг, който не съществува

`fig02_04.etiqueta-mala.yaml` е същият Deployment с една-единствена разлика: иска образа `curso-docker-revisor:1.6.9`, който не съществува нито в твоя Docker, нито в клъстера. Преди да го приложиш, предвиди: колко обекта Pod на `revisor` остават да работят, докато *rollout* е заседнал? Колко нови обекта Pod се опитва да създаде? (Подсказка: числата за `maxSurge` и `maxUnavailable` от 2.8.2.) После го приложи, изчакай с `kubectl rollout status deployment/revisor --timeout=40s` и погледни `kubectl get pods -l app=revisor` и `kubectl get deployment revisor`. За да излезеш от задръстването, приложи отново `revisor-deployment.yaml` и обясни защо *rollout* приключва мигновено.

### Упражнение 4 — Защити `securityContext`

Колега ти предлага да махнеш `readOnlyRootFilesystem: true` и тома `datos`, „защото са две неща за поддръжка, а `revisor` стартира и така“. В най-много пет изречения му отговори: какво предотвратява този ред, защо томът съществува именно заради него, какво би станало с отчета, ако махнеш само тома и оставиш реда, и дали махането му нарушава нивото `restricted`.

## Решения

### Решение 1

Измерено в `correr.salida.txt`:

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

**Четири обекта Pod.** Онзи, който промени, продължава да е `Running`: смяната на етикет не го спира. Но той престана да съвпада със селектора на ReplicaSet, така че ReplicaSet го **пусна** (неговият `ownerReferences` остана празен) и, тъй като сега броеше два там, където трябваше да има три, създаде нов. Остават трите от стадото плюс един самостоятелен, за когото никой не се грижи. Документацията за ReplicaSet описва тази техника: можеш да извадиш обекти Pod от ReplicaSet, като смениш етикетите им, например „за отстраняване на грешки или възстановяване на данни“, а извадените така се заместват сами. Полезно е: оставяш настрана Pod, който се държи зле, за да го изучиш, без услугата да губи реплика. Но не го забравяй там: скриптът го изтри накрая.

### Решение 2

Измерено в `correr.salida.txt`. (`fig02_03.adoptado.yaml` декларира порта `http`, също като шаблона на Deployment. Полето е информативно и не променя нито един от тези изходи, но има значение за трафика в Урок 3: затова обектът Pod е идентичен с тези на Deployment.)

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

Трите отговора:

1. **Не го взима.** `revisor-extra` продължава да е без собственик. Причината е в селектора на ReplicaSet: той не търси само `app: revisor`, търси и `pod-template-hash: 55cc969586`, а `revisor-extra` не носи този етикет. Документацията за ReplicaSet казва, че ReplicaSet веднага осиновява Pod без собственик, който съвпада с **неговия** селектор, и че затова е добре самостоятелните обекти Pod да не носят етикети, които съвпадат със селектора на някой ReplicaSet. Тук етикетът `pod-template-hash` предотврати осиновяването.
2. **Не изтрива нито един от своите.** Deployment казва `3/3`: за него съществуват само неговите три.
3. **Който търси по `app=revisor`, вижда четири.** `kubectl get pods -l app=revisor` изброява `revisor-extra`, сякаш е още една реплика.

Тази трета точка е проблемът. Един Service, в Урок 3, избира своите обекти Pod по етикет, и то по този от манифеста, `app: revisor`, а не по `pod-template-hash`, и сочи към порта с име `http`. Този самостоятелен Pod носи и двете неща: етикета и порта с това име. Така че този Pod, който никой не възстановява, ако умре, и който никой не обновява, когато смениш образа, би получавал своя дял от трафика, сякаш е още една реплика. Точно това има предвид документацията, когато предупреждава, че припокриващите се селектори водят до неочаквано поведение. Скриптът го изтри накрая.

### Решение 3

Измерено в `correr.salida.txt`:

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

**Три стари обекта Pod продължават да работят и има само един нов Pod, заседнал в `ErrImagePull`.** При три реплики `maxSurge` е 1 (може да има един Pod в повече), а `maxUnavailable` е 0 (не може да липсва нито един). Deployment създаде нов Pod и, за да махне един стар, изчака новият да стане наличен. Той така и не стана, така че не махна нито един. `kubectl get deployment` го обобщава: `READY 3/3` (услугата остава пълна), `UP-TO-DATE 1` (само една реплика има новия шаблон). **Тук *rollout* със счупен образ не сваля услугата**: заседва с непокътната услуга, защото при три реплики `maxUnavailable` е 0. Това не е закон: при четири реплики 25 % вече са 1 и Deployment наистина би махнал една изправна реплика, преди да знае дали новата стартира, а ако стар Pod падне, докато *rollout* е заседнал, капацитетът намалява. `rollout status` се отказа след 40 секунди, защото ти го поиска; Deployment, сам по себе си, би чакал 600 секунди (`progressDeadlineSeconds`, чиято стойност по подразбиране според документацията е 600), преди да отбележи *rollout* като неуспешен с условието `ProgressDeadlineExceeded`.

При повторното прилагане на добрия файл:

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

Приключи мигновено, защото шаблонът отново стана **идентичен** с този на ReplicaSet `revisor-55cc969586`: същият образ и същата анотация `restartedAt`, която `apply` не маха, защото файлът не я декларира. Същият шаблон, същият *hash*, същият ReplicaSet. Deployment не създаде нов: свали на нула счупения, `revisor-b8b699487`, и тъй като добрият вече имаше своите три реплики, нямаше какво повече да се прави. Връщането към предишната версия с `kubectl rollout undo` е краткият начин да се направи това и идва в Урок 9. Тук беше направено по начина, на който учи курсът: файлът е истината и се прилага отново.

### Решение 4

Един възможен отговор: „`readOnlyRootFilesystem` пречи на някой, който влезе в контейнера, да промени програмата или да остави инструменти, и е евтино, защото `revisor` пише само един файл. Именно заради този ред съществува томът `datos`: това е единственото място, където `revisor` може да запише отчета си. Ако махнеш тома и оставиш реда, `revisor` стартира и изглежда `Running`, но първия път, когато се опита да запише отчет, отговаря с 500 и `no pude guardar el reporte`. Махането на реда не нарушава нивото `restricted`, което не го изисква, но се отказваш от защита, която не струва нищо. А „стартира и така“ не е доказателство: важното е дали продължава да работи, когато някой го атакува и когато някой му възложи работа.“

## Изтриване на клъстера

Когато приключиш с упражненията, изтрий клъстера на урока. Не оставяй нищо живо на машината:

```text
$ kind delete cluster --name curso-k8s-l2
Deleting cluster "curso-k8s-l2" ...
Deleted nodes: ["curso-k8s-l2-worker" "curso-k8s-l2-worker2" "curso-k8s-l2-control-plane"]

$ kind get clusters | grep -c curso-k8s-l2
0
```

`--name` е задължителен и тук: без него kind би изтрил клъстера с име `kind`, който може да е на друг човек или от друг проект. След това изтрий временната папка на `kubeconfig` (онази, която създаде `mktemp`, с префикса `/tmp/curso-k8s-l2.`) или затвори този терминал. Клъстерът за следващия урок се създава от нулата, точно като този.

## Как разбирам, че съм успял

- [ ] При `ImagePullBackOff` казваш коя част се е провалила (`kubelet` на възела) и защо съобщението споменава `docker.io/library/…`, без да го търсиш.
- [ ] Проверяваш с `docker exec <nodo> crictl images` дали даден образ е във възел на kind и го зареждаш с `kind load docker-image <imagen> --name <clúster>`.
- [ ] Пишеш по памет скелета на един Deployment и обясняваш защо `selector` и `template.metadata.labels` трябва да съвпадат.
- [ ] Предвиждаш какво става при изтриване на самостоятелен Pod, на Pod на Deployment и на целия Deployment.
- [ ] Обясняваш за какво служи етикетът `pod-template-hash` и защо обектът Pod от Упражнение 2 не беше осиновен.
- [ ] Обосноваваш всеки ред от `securityContext` на `revisor` и казваш кои изисква нивото `restricted`.
- [ ] Изпълняваш `programas/02-pods-deployments/correr.sh > /tmp/mi-corrida-l2.txt 2>&1` и сравняваш `/tmp/mi-corrida-l2.txt` с `programas/02-pods-deployments/correr.salida.txt` (не пренасочвай към този файл: той е еталонът) по онова, което не се променя между изпълненията: три възела `Ready` на `v1.37.0`; `0` образа на `revisor` във възела преди зареждането; трите обекта Pod в `ImagePullBackOff` и събитието `pull access denied` с `docker.io/library/curso-docker-revisor:1.6.0`; трите реда `not yet present on node … loading...`, по един за всеки възел, включително контролния; `deployment.apps/revisor 3/3`; `revisor 1.6.0 escuchando en :8080 (1 servicio(s))`; `sano` и `1.6.0`; `executable file not found in $PATH`; `securityContext` в JSON; `CreateContainerConfigError` с `breaks non-root policy`; две ревизии в `rollout history` и старият ReplicaSet на `0 0 0`; и накрая `sin diferencias con el archivo`. Наставките в имената, IP адресите, на кой възел попада всеки Pod, възрастите, редът на редовете от `kind load` и колко пъти се повтаря всеки ред от `rollout status` се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l2`.

## Обобщение

Отговори, без да поглеждаш урока:

1. Защо възел на kind не вижда образите на твоя Docker и какво прави `kind load docker-image`?
2. Каква е разликата между `ErrImagePull` и `ImagePullBackOff`? Колко най-много чака `kubelet` между опитите?
3. Кои три части има `spec` на един Deployment и какво става, ако селекторът не съвпада с етикетите на шаблона?
4. Кой на кого е собственик във веригата Deployment, ReplicaSet и Pod и в кое поле се разчита това?
5. Какво прави ReplicaSet с Pod, от който махнеш етикета на неговия селектор?
6. Кога се задейства *rollout*? Защо `rollout restart` задейства такъв, ако не си променил нищо?
7. При три реплики и стойностите по подразбиране колко обекта Pod може да има по време на *rollout* и колко може да липсват?
8. Какво предотвратява `runAsNonRoot: true`, което `runAsUser: 65532` вече не предотвратява?
9. Защо `revisor` се нуждае от `emptyDir` в `/datos`?

## Източници

Всички са консултирани на 21 октомври 2026 г.

- [kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/), раздел „Loading an Image Into Your Cluster“: `kind load docker-image`, опцията `--name` за клъстери с име, `crictl images` вътре във възела и предупреждението за `:latest` и политиката за изтегляне.
- [Kubernetes, „Images“](https://kubernetes.io/docs/concepts/containers/images/): политиките `IfNotPresent`, `Always` и `Never`; политиката по подразбиране според тага; Docker Hub като регистър по подразбиране (`docker.io/library/…`); и `ImagePullBackOff`, с растящото изчакване до 300 секунди.
- [Kubernetes, „Deployments“](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): кога се задейства *rollout*; `maxSurge` и `maxUnavailable` (25 %, с тяхното закръгляне); `revisionHistoryLimit` (10); `progressDeadlineSeconds` (600) и `ProgressDeadlineExceeded`; етикетът `pod-template-hash`; предупреждението да не се управляват обектите ReplicaSet на Deployment и това за припокриващите се селектори.
- [Kubernetes, „ReplicaSet“](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/): предназначението му; осиновяването на обекти Pod без собственик, които съвпадат със селектора му; препоръката да се използват Deployments; и как се изваждат обекти Pod от ReplicaSet чрез смяна на етикетите им.
- [Kubernetes, „Pods“](https://kubernetes.io/docs/concepts/workloads/pods/): защо рядко се създават отделни обекти Pod и докога един Pod остава на своя възел.
- [Kubernetes, „Pod Lifecycle“](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): `restartPolicy` е `Always` по подразбиране; фазата `Pending` включва изтеглянето на образите; един Pod никога не се препланира към друг възел.
- [Kubernetes, „Restrict a Container's Syscalls with seccomp“](https://kubernetes.io/docs/tutorials/security/seccomp/): без `seccompDefault` профилът по подразбиране е `Unconfined`.
- [Kubernetes, „Owners and Dependents“](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/): полето `ownerReferences`.
- [Kubernetes, „Labels and Selectors“](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/): какво е етикет, че не е уникален, селекторите по равенство и по множества и липсата на оператор „или“.
- [Kubernetes, „Volumes“](https://kubernetes.io/docs/concepts/storage/volumes/), раздел `emptyDir`: кога се създава, кога се изтрива и `sizeLimit`.
- [Kubernetes, „Configure a Security Context for a Pod or Container“](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): всяко поле на `securityContext` и какво контролира.
- [Kubernetes, „Pod Security Standards“](https://kubernetes.io/docs/concepts/security/pod-security-standards/): нивото `restricted` и неговите правила за не-`root`, ескалация на привилегии, capabilities и `seccomp`.

---

**Следващ:** [Урок 3 — Services и DNS](03-services-dns.md)
