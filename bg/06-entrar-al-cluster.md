# Урок 6 — Влизане в клъстера

Четвъртък, 4:40 следобед. Екипът по експлоатация иска да види отчета на `revisor` от собственото си табло, което работи на друга машина, извън клъстера, а презентацията пред ръководството е в 5:30. В чата на екипа вече има две предложения. Първото: „смени му Service-а на `NodePort` и им дай IP адреса на един възел“. Второто идва с връзка към урок отпреди две години: „инсталирай `ingress-nginx`, три команди са“. И двете работят този следобед. Първото оставя `revisor` отворен на случаен порт на **всички** възли, без никой да го е решил писмено. Второто инсталира компонент, който престана да получава актуализации за сигурност през март 2026 г. И има трета изкусителна възможност, тази от README на kind: програма, която се изпълнява на твоята машина и дава балансьори на натоварването на клъстерите ти… на **всичките** ти клъстери на kind, включително тези на колегите ти, ако споделяте машината.

Този урок те учи да отвориш входна точка към клъстера без тези преки пътища: `LoadBalancer` с MetalLB и именувана входна точка с Gateway API и Envoy Gateway, и двете инсталирани **вътре** в твоя клъстер, за да си отидат с него, когато го изтриеш. И те учи на нещо, което важи за всичко, което ще инсталираш в Kubernetes отсега нататък: има части, които са **платформа**, и части, които са **проект**, и платформата трябва да е готова, преди проектът да я използва.

**Време:** 2 × 45 мин

**Какво изграждаш:** `revisor`, публикуван извън клъстера, първо със Service `LoadBalancer`, който получава IP адреса `172.18.255.200`, а после през именувана входна точка, Gateway `revisor`, с маршрут към обичайния Service

**Какво научаваш:** защо `LoadBalancer` остава в `<pending>` в kind и какво отваря, макар да е в изчакване (`NodePort` във всеки възел); какво прави MetalLB на слой 2 и защо диапазонът му идва от мрежата `kind` на Docker; какво са персонализираните ресурси (CRD) и *webhook*-овете за допускане (*admission webhooks*) и защо налагат инсталиране по ред; Gateway API с трите си части, `GatewayClass`, `Gateway` и `HTTPRoute`, обслужвани от Envoy Gateway; защо не се използва Cloud Provider KIND на споделена машина; `Ingress` като замразен API и защо не `ingress-nginx`; и какво остава изложено, през коя точка и без какво (криптиране при пренос)

**Откъде идваш.** От [Урок 5](05-salud-recursos-apagado.md): `revisor` работи с три реплики, със своите *probes* за стартиране, за готовност и за жизненост (*startup*, *readiness*, *liveness*), с `requests` и `limits`, със своя `ConfigMap` като променливи и токена си като файл, всичко приложено с `kubectl apply -k .`. Тестовата услуга също се наблюдава. От [Урок 3](03-services-dns.md) носиш правилото, че всичко се ражда като `ClusterIP` и нищо не се публикува току-така, и реда за диагностика на Service, който не отговаря: кодът на `curl`, името, колоната `ENDPOINTS`. Днес това правило се нарушава за първи път, нарочно и писмено.

**Какво не прави този урок.** Не слага криптиране: входната точка говори чист HTTP на порт 80, а разделът за навика за сигурност го измерва и го казва. Не затваря още кой с кого може да говори **вътре** в клъстера: това е [Урок 7](07-aislar-permisos-red.md), който освен това премахва директния `LoadBalancer` и оставя Gateway като единствената входна точка. Не ти дава име на домейн, нито истински балансьор от облачен доставчик: IP адресите, които MetalLB раздава тук, съществуват само в мрежата `kind` на Docker на твоята машина. И `revisor` остава в пространството от имена `default`; преместването в собствено пространство е в Урок 7.

**За изпълненията.** Всички изходи от този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1, образа на възела `kindest/node:v1.37.0`, фиксиран чрез отпечатъка му, **MetalLB v0.16.1** и **Envoy Gateway v1.9.2** (който включва Gateway API v1.6.1), в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l6`. Машината беше Mac с процесор ARM и Docker Engine 29.2.1 във виртуална машина с Linux (Colima), **не** Linux Mint, който е референтната система на курса. Какво се променя в твоя Mint: архитектурата, IP адресите на Pod-овете, на Service-ите и на възлите (`172.18.0.2` до `.4`, в друг ред), портовете `NodePort`, които клъстерът избира на случаен принцип, наставките на имената, възрастите и възелът, от който MetalLB обявява всеки IP адрес. Двата IP адреса на MetalLB, `172.18.255.200` и `172.18.255.201`, **трябва** да ти излязат същите, ако твоята мрежа `kind` е `172.18.0.0/16`. И има една разлика, която има значение: на Mac мрежата `kind` живее във виртуалната машина и терминалът ти не я достига (ще го видиш в навика за сигурност: код 28); в Linux Docker свързва машината ти с тази мрежа, така че в твоя Mint `curl http://172.18.255.200/salud` от терминала ти трябва да отговори. За да е примерът един и същ в двете системи, „клиентът отвън“ в този урок е контейнер на Docker, свързан към мрежата `kind`, извън клъстера. Пълната обиколка е в [`programas/06-entrar-al-cluster/`](../programas/06-entrar-al-cluster): `correr.sh` създава клъстера, зарежда в него двата образа, минава през урока по ред, изпълнява Упражнения 1 до 3 и изтрива клъстера. Накрая повтаря, в нов клъстер, трите стъпки от 6.9 с `levantar.sh`. Пълното изпълнение, с двата клъстера, отне 15 минути и 20 секунди (920 секунди): създаването на първия клъстер и изчакването да е готов бяха 40 секунди, създаването на втория — 46, изтриването на първия — 1, а `levantar.sh` отне 266. Изходът му е `correr.salida.txt`. Изисква интернет: манифестите на MetalLB и на Envoy Gateway се изтеглят от изданията им, фиксирани към версията им, а образите им се изтеглят първия път.

## След урока ще можеш да

- Обясняваш защо Service `LoadBalancer` остава в `<pending>` в kind и доказваш с `curl`, че въпреки това вече е отворил `NodePort` във всеки възел.
- Инсталираш MetalLB в клъстер, даваш му диапазон от IP адреси, взет от мрежата `kind`, и четеш в събитията на Service кой е определил IP адреса и от кой възел се обявява.
- Различаваш част от **платформата** (CRD, контролери, *webhook*-ове) от част от **проекта** и ги прилагаш в три стъпки: платформа, изчакване с `kubectl wait`, проект.
- Разпознаваш грешките при прилагане не по ред: `no matches for kind … ensure CRDs are installed first` и `failed calling webhook … connection refused`.
- Пишеш `Gateway` и `HTTPRoute` за `revisor` и четеш състоянието им (`PROGRAMMED`, `Accepted`, `ResolvedRefs`).
- Предизвикваш маршрут към Service, който не съществува, разпознаваш го по `ResolvedRefs=False BackendNotFound` и по `500` на входната точка и го поправяш.
- Казваш какво остава изложено след този урок, през коя входна точка и какво му липсва (криптиране при пренос), и обясняваш защо не Cloud Provider KIND и не `ingress-nginx`.

## Защо, преди как

Досега всичко, което говореше с `revisor`, беше **вътре** в клъстера: Pod-ът `depurar`, самият `revisor`, който питаше `prueba`, *probes* на `kubelet`. Ти влизаше през временен тунел, `port-forward`, който трае колкото трае командата ти и говори с един-единствен Pod. Това стига, за да гледаш. Не стига за таблото за експлоатация от сцената, което има нужда от стабилен адрес, който оцелява при *rollout*-ите, който разпределя между репликите и който не зависи от това лаптопът ти да е включен.

Kubernetes има три начина да отвори този адрес, от най-грубия до най-финия:

1. **`NodePort`**: клъстерът отваря висок порт (между 30000 и 32767) на **всички** възли и каквото пристигне там, отива към Service. Работи, но клиентът трябва да знае IP адреса на един възел и число, което клъстерът е избрал.
2. **`LoadBalancer`**: същото като `NodePort`, плюс балансьор **извън** клъстера, със собствен IP адрес, който разпределя между възлите. В облак този балансьор го създава доставчикът. В kind няма облак и затова Service-ът остава да чака.
3. **Входна точка от слой 7** (HTTP): една-единствена точка, която приема трафика и решава, по пътя или по името на сайта, към кой Service отива всяка заявка. Актуалният начин да се декларира е **Gateway API**. Старият начин, `Ingress`, още съществува и е замразен.

В kind вариантите 2 и 3 изискват нещо, което клъстерът няма вградено: някой, който да раздава IP адреси, и някой, който да обслужва входната точка. Този курс инсталира и двамата **вътре** в клъстера. **MetalLB** раздава IP адресите. **Envoy Gateway** обслужва входната точка. Всеки се инсталира със собствени типове обекти (персонализирани ресурси) и собствени пазачи (*webhook*-ове) и оттам идва най-полезният урок от днес, този, който ще използваш във всеки истински клъстер: платформата е първа, изчаква се да е готова и след това идва проектът. Не е прищявка. Това е, което клъстерът ти изисква, и ще го видиш как го изисква.

Урокът има осем части с понятия и после обичайните раздели:

1. **Клъстерът на урока** (6.1), със собствен `kubeconfig`.
2. **Проектът преди платформата** (6.2): какво се проваля и защо.
3. **`LoadBalancer` без никой, който да раздава адреси** (6.3), и `NodePort`, който вече е отворил.
4. **MetalLB** (6.4): диапазонът, слой 2 и *webhook*-ът, който още не слуша.
5. **Защо не Cloud Provider KIND** (6.5).
6. **Envoy Gateway и Gateway API** (6.6): платформата на входната точка.
7. **Входната точка на `revisor`** (6.7): `Gateway` и `HTTPRoute`.
8. **`Ingress` и `ingress-nginx`** (6.8): това, което е изведено от поддръжка, за да го разпознаваш.

И в края на понятията — **редът** (6.9), записан в три стъпки.

Това е целта. В края на 6.7 един клиент, който не е част от клъстера, иска отчета от `revisor` през именуваната входна точка:

```text
$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.201/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK          13ms  200
```

## Ако нямаш образа от курса по Docker

Този урок използва същите два образа като Уроци 3 до 5: `curso-docker-revisor:1.6.0`, на `revisor`, и `curso-docker-prueba:1.0.0`, на услугата, която се проваля нарочно. Провери, че ги имаш:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

Ако ти липсва някой, [Урок 3](03-services-dns.md) казва, в същия този раздел, как да изградиш двата от хранилището на курса по Docker. Този урок не иска нищо ново от нито един от двата образа. Новото идва отвън: образите на MetalLB и на Envoy, които не се зареждат с `kind load`, а всеки възел ги изтегля от интернет първия път, както този на `curl` в Урок 3.

## Понятията

### 6.1 Клъстерът на урока

#### 6.1.1 Преди да създадеш: правило за съжителство

Това е първият урок на курса, който инсталира **MetalLB**, а MetalLB има особеност, която налага ново правило. Ще вземе IP адреси от мрежата `kind` на Docker, мрежата, която споделят **всички** клъстери на kind на твоята машина. Ако два клъстера с MetalLB и един и същ диапазон работят едновременно, и двата обявяват едни и същи адреси и си пречат взаимно: част от заявките стигат до единия, а други до другия. Затова, преди да създадеш клъстера си, провери две неща:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar ya en 172.18.255.200. Si este curl responde algo,
# hay otro clúster con MetalLB vivo: espera a que termine.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 3 http://172.18.255.200/
```

Мрежата `kind` я създава kind първия път, когато създава клъстер, така че първата команда се проваля, ако никога не си създавал такъв; в този случай създай клъстера и я провери веднага след това, преди да инсталираш каквото и да било. При изпълнението на този урок мрежата излезе така:

```text
$ docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
fc00:f853:ccd:e793::/64 172.18.0.0/16 
```

Две подмрежи: една IPv6 и IPv4 `172.18.0.0/16`, която е важната. Ако твоята е друга (например `172.19.0.0/16`, защото на машината ти вече е имало друга мрежа с `172.18`), ще трябва да смениш диапазона в `infra/metallb-pool.yaml`, за да попада в твоята, и всички IP адреси от този урок ще ти излязат различни. Има и трета проверка, най-евтината: `kind get clusters`. Ако видиш друг жив клъстер, който не е твой, попитай собственика му дали използва MetalLB и с какъв диапазон, преди да продължиш; `curl` вижда само този, който отговаря на HTTP на порт 80 на `.200`, а чужд MetalLB с друг порт или с други адреси от диапазона (`.201` до `.220`) би минал, без да го забележиш. `correr.sh` прави първите две и спира, преди да създаде каквото и да било, ако някоя се провали; ако мрежата `kind` още не съществува, също спира, защото не може да прочете диапазона ѝ. В този случай създай ти един произволен пробен клъстер, виж мрежата и го изтрий, или създай мрежата ръчно със същата подмрежа.

#### 6.1.2 Създаване, проверка, зареждане

От корена на хранилището на курса, със същата грижа както винаги:

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

Функцията `ctx` сравнява активния контекст с този, който очакваш. Ако съвпадат, не печата нищо и връща успех; ако не, пише „contexto equivocado: no sigo“ и връща грешка, а `&&` прави така, че командата след нея **да не се изпълни**. Това е разликата между това да гледаш контекста „на око“, което зависи от това да си внимателен, и една защита, която те спира, дори да бързаш. Днес ще инсталираш компоненти, които създават десетки обекти в клъстера, включително обекти, които важат за целия клъстер, а не за едно пространство от имена; да ги приложиш в грешния контекст би означавало да ги инсталираш в клъстера на друг човек. Затова **пред всеки** `apply`, `delete` или `patch` в този урок стои `ctx &&`. В изходите по-долу е пропуснато, за да се побират, но в твоя терминал стои винаги. (`correr.sh` прави същото във всяка команда.)

`(umask 077; …)` заслужава обяснение. `umask` е маската, която казва на твоя shell какви права да **отнеме** на всеки нов файл; при обичайната (`022`) `token.txt` би се родил `-rw-r--r--`, четим от всеки потребител на машината. При `077` се ражда `-rw-------`: само ти. Скобите правят така, че промяната на маската да важи само за тази команда и да не остава в терминала ти. Това е същата грижа като в Уроци 4 и 5 и тежи повече днес, защото този урок говори за споделени машини.

```text
$ kubectl config current-context
kind-curso-k8s-l6

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l6-control-plane  Ready   v1.37.0  172.18.0.4
curso-k8s-l6-worker         Ready   v1.37.0  172.18.0.3
curso-k8s-l6-worker2        Ready   v1.37.0  172.18.0.2
```

Новата колона е `INTERNAL-IP`: адресът на всеки възел **в мрежата `kind`** на Docker. Спомни си от Урок 0, че един възел на kind е контейнер; това е IP адресът на този контейнер. И трите попадат в началото на `172.18.0.0/16`, защото Docker раздава отдолу. Запомни ги: в 6.3 един клиент отвън ще влезе през тях.

`kind load` отпечатва шестте си обичайни реда, `not yet present on node … loading...`, два образа по три възела. Има ги в `correr.salida.txt`.

#### 6.1.3 Клиентът отвън

За да тества отвън клъстера, този урок използва контейнер с `curl`, свързан към мрежата `kind`, с името `curso-k8s-l6-cliente` и `--rm`, за да се изтрива сам след всяка заявка. Това е истински клиент: не е Pod, клъстерът не го познава, не минава през DNS на клъстера, нито през `kube-proxy` от своя страна. Вижда мрежата така, както би я видяла машина, свързана към същия сегмент като възлите. За да не пишеш пълния ред всеки път, дефинирай функция в терминала си:

```bash
afuera() {
  docker run --rm --network kind --name curso-k8s-l6-cliente \
    curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 "$@"
}
# Uso:  afuera -s -m 5 http://172.18.255.200/salud
```

В изходите на този урок **редовете, които започват с `$ curl`, се изпълняват така**, от този контейнер, с изключение на един от раздела за навика за сигурност, който се изпълнява в терминала ти нарочно и го казва. В Linux Mint можеш да използваш `curl` директно от терминала си, ако предпочиташ; резултатът трябва да е същият.

Едно предупреждение за споделената машина: когато подаваш токена с `-H "Authorization: Bearer $(cat token.txt)"`, токенът остава като **аргумент на командата** и докато командата работи, всеки потребител на машината го вижда в списъка с процеси (`ps`). За симулирания токен на този курс е наред; с истински токен той се подава от файл (`-H @archivo`, което `curl` приема от версия 7.55) или през стандартния вход, но никога написан в реда.

### 6.2 Проектът преди платформата

#### 6.2.1 Какво съдържа папката

Папката на този урок съдържа същото, което остави Урок 5 — двата Deployment-а, двата Service-а, генератора на `ConfigMap` и този на `Secret` — и два нови файла. `kustomization.yaml` вече ги споменава. Това е **програма**: `programas/06-entrar-al-cluster/kustomization.yaml`.

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

Двата нови реда в `resources` са `revisor-publico.yaml` (6.3) и `gateway.yaml` (6.7). Коментарът отгоре вече предупреждава за това, което ще провериш сега: „преди тази kustomization идват частите от `infra/`“. Направи каквото би направил всеки, който бърза в 4:40: игнорирай предупреждението и приложи.

#### 6.2.2 Прилагане без платформа

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

Прочети изхода в две половини. Горе — седем обекта `created`: всичко, което клъстерът вече знаеше какво е. Имената на генерираните са като в Урок 4: `revisor-config-t6cm6872fk`, същото при твоето изпълнение, защото списъкът не се е променил, и `revisor-token-…`, различно, защото твоят токен е нов. Долу — два обекта, които клъстерът **не разпознава**: „не намирам типа `Gateway` във версията `gateway.networking.k8s.io/v1`“ и подсказката, на английски, „първо се увери, че CRD са инсталирани“. `kubectl` приложи каквото можа, прескочи каквото не можа и излезе с код 1. Скрипт със `set -e` би спрял тук; такъв без него би продължил, сякаш нищо не е станало, а това е по-лошо.

Първата команда, `kubectl get crd`, вече го обявяваше: `No resources found`. Този клъстер няма **никакъв** персонализиран ресурс. И пряката проверка:

```text
$ kubectl api-resources --api-group=gateway.networking.k8s.io
NAME   SHORTNAMES   APIVERSION   NAMESPACED   KIND
```

Само заглавия. Групата `gateway.networking.k8s.io` не съществува в този клъстер.

#### 6.2.3 Какво е CRD

Досега всички типове, които използва — `Pod`, `Deployment`, `Service`, `ConfigMap`, `Secret` — идват **вътре** в Kubernetes: `kube-apiserver` ги познава от момента, в който стартира. `Gateway` и `HTTPRoute` — не. [Документацията за персонализираните ресурси](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/) го казва така: един персонализиран ресурс „е разширение на API на Kubernetes, което не е непременно налично при инсталация по подразбиране“. И обяснява как се добавя един: с обект `CustomResourceDefinition` (CRD). „Дефинирането на обект CRD създава нов персонализиран ресурс, с името и схемата, които зададеш. API на Kubernetes обслужва и съхранява твоя персонализиран ресурс.“

Тоест: CRD е обект, който **учи** `kube-apiserver` на нов тип. Докато не съществува CRD на `Gateway`, манифест с `kind: Gateway` е за клъстера текст, който не означава нищо. Това е първата причина за реда: **типовете трябва да съществуват преди обектите от тези типове**.

[Страницата за Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) на Kubernetes го казва за собствения си случай: Gateway API „е добавка (*add-on*), която съдържа типове на API“ и нейните спецификации „са определени като персонализирани ресурси“. Не идва с Kubernetes. Някой трябва да я инсталира и в този курс я инсталира Envoy Gateway (6.6).

Обърни внимание на това, което **беше** създадено: `revisor` и `prueba` работят, със своите Service-и, и сред тях `revisor-publico`. Това е точно изходната позиция, от която този урок има нужда: онова от Урок 5, плюс една поискана и още неотворена входна точка.

### 6.3 `LoadBalancer` без никой, който да раздава адреси

#### 6.3.1 Манифестът

Това е **програма**: `revisor-publico.yaml`.

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

Това е Service-ът от Урок 3 с две разлики: казва се `revisor-publico` и `type` е `LoadBalancer`. Същият селектор, същият `port: 80`, същият `targetPort: http`. Не замества `revisor` `ClusterIP`: двата съществуват едновременно и избират едни и същи Pod-ове. Вътрешният си остава за вътрешните клиенти; този е входната точка навън. Това, че са два обекта, а не един със сменен тип, е решение: в деня, в който поискаш да затвориш входната точка (Урок 7 го прави), изтриваш `revisor-publico` и нищо от вътрешното не разбира.

#### 6.3.2 `<pending>`

```text
$ kubectl get services
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes        ClusterIP      10.96.0.1       <none>        443/TCP        36s
prueba            ClusterIP      10.96.248.146   <none>        9000/TCP       7s
revisor           ClusterIP      10.96.157.248   <none>        80/TCP         7s
revisor-publico   LoadBalancer   10.96.115.79    <pending>     80:30808/TCP   7s
```

`EXTERNAL-IP <pending>`: Service-ът поиска външен IP адрес и никой не му го е дал. [Документацията за Service-и](https://kubernetes.io/docs/concepts/services-networking/service/) обяснява чия е тази работа: „при облачни доставчици, които поддържат външни балансьори, задаването на полето `type` на `LoadBalancer` осигурява балансьор за твоя Service. Реалното създаване на балансьора става асинхронно, а информацията за осигурения балансьор се публикува в полето `.status.loadBalancer` на Service“. В kind няма облачен доставчик. Полето остава празно и `kubectl` го показва като `<pending>`, завинаги, без нито една грешка:

```text
$ kubectl describe service revisor-publico | grep -E '^(Type|LoadBalancer Ingress|Port|NodePort|Endpoints|Events):'
Type:                     LoadBalancer
Port:                     http  80/TCP
NodePort:                 http  30808/TCP
Endpoints:                10.244.2.3:8080,10.244.1.2:8080,10.244.2.4:8080
Events:                   <none>
```

Няма ред `LoadBalancer Ingress` (там би отишъл IP адресът) и няма събития: никой не е опитал нищо, така че никой не се е провалил. Това е вид състояние, което обърква, защото нищо не е червено. Единствената следа е думата `<pending>`.

#### 6.3.3 Какво отвори наистина: `NodePort` във всеки възел

Погледни пак колоната `PORT(S)`: `80:30808/TCP`. И в `describe`, `NodePort: http 30808/TCP`. Service-ът поиска балансьор, който не дойде, но нещо дойде: един **порт във възлите**. Същата документация го обяснява: „за да реализира Service с `type: LoadBalancer`, Kubernetes обикновено започва с промените, еквивалентни на заявка за Service с `type: NodePort`. След това `cloud-controller-manager` настройва външния балансьор да препраща трафика към този порт на възела“. `LoadBalancer` е `NodePort` **плюс** някой отвън. Тук този някой липсва, но `NodePort` вече е отворен. Проверява се от клиента отвън, срещу IP адреса на един работен възел и срещу този на контролния възел:

```text
$ curl -s -m 5 http://172.18.0.3:30808/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 http://172.18.0.4:30808/salud
{"estado":"vivo","version":"1.6.0"}
```

И двата отговарят. `172.18.0.3` е `worker`; `172.18.0.4` е **контролният** възел, където не работи никоя реплика на `revisor`. И въпреки това отговаря: `kube-proxy` на всеки възел, включително на контролния, слуша на 30808 и препраща към някоя реплика, където и да е тя. Това е, което първото предложение от сцената би оставило отворено, и е това, което **вече** е отворено, дори външният IP адрес никога да не дойде.

Документацията казва как да се избегне: с `spec.allocateLoadBalancerNodePorts: false`, което „трябва да се използва само с реализации на балансьор, които пращат трафика директно към Pod-овете, вместо да използват портове на възела“. Стойността му по подразбиране е `true`. MetalLB на слой 2, този, който инсталира този урок, предава трафика на един възел и оставя `kube-proxy` да го разпредели, така че този курс не го изключва; но го назовава, защото „какво е изложено“ включва този порт, а разделът за навика за сигурност го разказва.

### 6.4 MetalLB: този, който раздава адресите, вътре в клъстера

#### 6.4.1 Какво е

MetalLB е балансьор за клъстери, които не живеят в облак: тези от собствен център за данни, тези от дома ти и тези на kind. Неговото [ръководство за инсталиране](https://metallb.io/installation/) описва двете му части: `controller`, един Deployment, „контролерът на целия клъстер, който се грижи за присвояването на IP адресите“; и `speaker`, един DaemonSet (по един Pod на възел), „компонентът, който говори протоколите, които избереш, за да бъдат Service-ите достъпни“. Първият решава кой IP адрес на кой Service се пада. Вторият прави така, че този IP адрес да съществува в мрежата.

В този урок MetalLB работи на **слой 2**. Неговото [ръководство за конфигурация](https://metallb.io/configuration/) го обяснява с едно изречение: „работи, като отговаря директно на ARP заявките на твоята локална мрежа, за да даде на клиентите MAC адреса на машината“. ARP е въпросът, който задава един компютър в локална мрежа, за да разбере кой има даден IP адрес: „кой има `172.18.255.200`?“. Нито една машина няма този IP адрес настроен. Но `speaker` на един възел отговаря „аз“ и от този момент трафикът към този IP адрес стига до този възел, където `kube-proxy` го разпределя между репликите. Това е честен трик: няма балансиращо устройство, има възел, който поема адреса.

#### 6.4.2 Инсталиране: CRD и *webhook*-ът

Инсталирането е манифест от изданието v0.16.1, този, който дава официалното ръководство, фиксиран към версията си. Този курс го обвива в kustomization, за да може да се приложи с `-k` като всичко останало. Това е **програма**: `infra/metallb/kustomization.yaml`.

```yaml
# MetalLB v0.16.1 (modo nativo, capa 2), instalado SOLO en este clúster.
# Es la versión que indica la guía oficial de instalación (metallb.io/installation).
# Se aplica antes que todo lo demás de la Lección 6: kubectl apply -k infra/metallb
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
```

Ръководството казва нещо, което си струва да прочетеш преди да приложиш: без конфигурация „компонентите на MetalLB стартират, но стоят неподвижни“, докато не им дадеш диапазон. Така че стъпките са две: инсталиране и даване на диапазона. Направи пак каквото би направил всеки, който бърза: двете една след друга.

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

Грешка, различна от тази в 6.2. Този път типът **съществува** — `apply` на MetalLB създаде своите CRD в същия миг — и въпреки това клъстерът отхвърли двата обекта. Разчети я отдясно наляво: `connect: connection refused` към `10.96.93.252:443`; този IP адрес е на Service `metallb-webhook-service`, който току-що беше създаден (`created`, на втория ред на предишния изход); а това, което се провали, беше „извикването на *webhook* `ipaddresspoolvalidationwebhook.metallb.io`“.

***Webhook*-ът за допускане** е още един пазач, който платформата добавя към `kube-apiserver`. [Документацията за разширяемите контролери за допускане](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) ги определя така: „*webhook*-овете за допускане са HTTP повиквания, които получават заявки за допускане и правят нещо с тях“. Тези за валидиране „могат да отхвърлят заявки, за да наложат собствени политики“. MetalLB инсталира един, за да провери, че даден диапазон е написан правилно, преди да го приеме. `kube-apiserver`, преди да запази твоя `IPAddressPool`, пита *webhook*-а. Но Pod-ът, който отговаря на този въпрос, `controller`, още стартираше. Никой не слушаше на 443. А какво прави `kube-apiserver`, когато не може да попита? Това го решава едно поле на *webhook*-а, `failurePolicy`. Същата страница го казва: с `failurePolicy: Fail`, което е стойността по подразбиране, „грешка при извикването на *webhook*-а кара допускането да се провали, а заявката — да бъде отхвърлена“. MetalLB го записва изрично във всичките си шест *webhook*-а (може да се провери и изпълнението го проверява по-долу): по-добре да отхвърли, отколкото да пропусне обект, без да го провери.

Това е втората причина за реда: **пазачите трябва да слушат, преди да пристигне онова, което ще проверяват**. Политиката на *webhook*-а на MetalLB се чете в самия клъстер; има по една стойност за всеки от шестте му пазачи:

```text
$ kubectl get validatingwebhookconfiguration metallb-webhook-configuration -o jsonpath='{.webhooks[*].failurePolicy}{"\n"}'
Fail Fail Fail Fail Fail Fail
```

Шест `Fail`: нито един не пропуска обект, ако не може да го провери. И не е достатъчно CRD да съществува:

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

Девет нови типа, всички от групата `metallb.io`. Няколко са за другия режим на MetalLB, BGP, който този курс не използва. Двата днешни са `ipaddresspools` и `l2advertisements`.

#### 6.4.3 Изчакване с `kubectl wait`

Поправката не е да опитваш отново, докато мине. Тя е да **изчакаш едно условие** и после да приложиш:

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

[Справочникът за `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) го описва: командата „взема няколко ресурса и чака, докато посоченото условие се появи в полето `Status` на всеки от тях“. `condition=Available` при Deployment означава, че той има **минималната** наличност, която позволява стратегията му за обновяване (документацията за Deployment-и я определя така). При `controller` на MetalLB, който има една-единствена реплика, това е същото като „единствената му реплика е готова“; „готова“ в смисъла от Урок 5, този на *readiness probes*. При Deployment с три реплики и `maxUnavailable` от 25 % `Available` би настъпило с по-малко готови реплики, отколкото иска: не го чети като „всички“. При това изпълнение, веднага щом `controller` стана `Available`, *webhook*-ът вече отговаряше. За DaemonSet се използва `rollout status`, същата команда от Урок 2, която чака да има готов `speaker` във всеки от трите възела. С `--timeout` никое чакане не е безкрайно: ако нещо не дойде, командата се проваля и го разбираш.

Същият файл, без да сменим нито една запетая, и този път `created`. Файлът никога не е бил погрешен. Беше подаден твърде рано.

```text
$ kubectl get pods -n metallb-system -o wide | awk '{print $1, $2, $3, $6, $7}' | column -t
NAME                         READY  STATUS   IP          NODE
controller-76f4cf76b7-hpzjj  1/1    Running  10.244.1.3  curso-k8s-l6-worker
speaker-455xp                1/1    Running  172.18.0.3  curso-k8s-l6-worker
speaker-jvbvh                1/1    Running  172.18.0.2  curso-k8s-l6-worker2
speaker-xctwr                1/1    Running  172.18.0.4  curso-k8s-l6-control-plane
```

Един `controller` с IP адрес от мрежата на Pod-овете (`10.244.`) и три `speaker`, по един на възел, с IP адреса **на възела** (`172.18.0.`). Последното не е случайно: `speaker` трябва да отговаря на ARP в мрежата `kind`, затова работи с мрежата на възела, а не с мрежата на Pod-овете.

#### 6.4.4 Диапазонът

Това е **програма**: `infra/metallb-pool.yaml`.

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

Два обекта, две решения:

- **`IPAddressPool`** казва **кои** адреси може да раздава: от `172.18.255.200` до `172.18.255.220`, двайсет и един. Ръководството за конфигурация: „всички IP адреси, зададени чрез `IPAddressPool`, допринасят за множеството от IP адреси, което MetalLB използва, за да присвоява IP адреси на Service-ите“. Защо тези: трябва да са **вътре** в мрежата `kind` (иначе никой в тази мрежа не би питал за тях) и **далеч** от тези, които Docker раздава на контейнерите, които започват отдолу (`172.18.0.2`, `.3`, `.4`). Краят на мрежата е най-безопасното място.
- **`L2Advertisement`** казва **как** се обявяват: на слой 2, чрез ARP. Ръководството: „за да обявиш IP адреса, който идва от `IPAddressPool`, трябва да му асоциираш инстанция на `L2Advertisement`“. Без този втори обект MetalLB би присвоил IP адреса, но никой не би отговарял за него.

```text
$ kubectl get ipaddresspool,l2advertisement -n metallb-system
NAME                             AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
ipaddresspool.metallb.io/curso   true          false             ["172.18.255.200-172.18.255.220"]

NAME                               IPADDRESSPOOLS   IPADDRESSPOOL SELECTORS   INTERFACES
l2advertisement.metallb.io/curso   ["curso"]                                  
```

`AUTO ASSIGN true`: MetalLB взема IP адреси от този диапазон за всеки `LoadBalancer`, който ги поиска, без Service-ът да трябва да назовава диапазона.

#### 6.4.5 Първият IP адрес

```text
$ kubectl get service revisor-publico
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
revisor-publico   LoadBalancer   10.96.115.79   172.18.255.200   80:30808/TCP   119s
```

`172.18.255.200`, първият от диапазона. Service-ът беше почти две минути в `<pending>`; никой не го е прилагал отново. MetalLB, като получи диапазон, потърси `LoadBalancer`-ите без IP адрес и им даде. Това е пак термостатът от Урок 0: желаното състояние беше записано от 6.2 и щом се появи кой да го преследва, то беше достигнато. `NodePort` си остава `30808`: външният IP адрес се наслои **върху** порта на възела, както казва документацията.

Кой го направи и откъде? Казват го събитията на Service, които в 6.3 бяха празни:

```text
$ kubectl get events --field-selector involvedObject.name=revisor-publico --sort-by=.lastTimestamp | awk '{$1=""; print}' | sed 's/^ //'
SEEN TYPE REASON OBJECT MESSAGE
Normal IPAllocated service/revisor-publico Assigned IP ["172.18.255.200"]
Normal nodeAssigned service/revisor-publico announcing from node "curso-k8s-l6-worker2" with protocol "layer2"
```

(`awk` маха колоната за възрастта, за да се побере; заглавният ред запазва името си.) Две събития, и двете на MetalLB: `IPAllocated`, от `controller`, който избра IP адреса; и `nodeAssigned`, от `speaker`, което казва от кой възел го обявява: `curso-k8s-l6-worker2`, на слой 2. При твоето изпълнение възелът може да е друг. Този възел е, оттук нататък, физическата входна точка на `172.18.255.200`: ако падне, друг `speaker` поема обявяването.

И доказателството, което има значение, отвън:

```text
$ curl -s -m 5 http://172.18.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -H 'Authorization: Bearer …' 'http://172.18.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           7ms  200
```

Един стабилен адрес, на порт 80, без странно число, който разпределя между трите реплики и който си остава там, дори Pod-овете да се сменят. Това, от което таблото от сцената имаше нужда. (`…` замества токена в публикуваните изходи; в терминала ти влиза съдържанието на `token.txt`, с `-H "Authorization: Bearer $(cat token.txt)"`.)

### 6.5 Защо не Cloud Provider KIND

Ако потърсиш „LoadBalancer в kind“, първият отговор е този на самия kind. Неговото [ръководство за LoadBalancer](https://kind.sigs.k8s.io/docs/user/loadbalancer/) препоръчва **Cloud Provider KIND**, а неговото [ръководство за Ingress](https://kind.sigs.k8s.io/docs/user/ingress/) казва, че от v0.9.0 тази програма „поддържа Ingress нативно“ и че Gateway API „също е поддържан нативно“. Това е сериозен инструмент, от същата група, която поддържа kind. Защо този курс не го използва?

Заради **къде работи** и **върху какво действа**. Ръководството на kind го казва: Cloud Provider KIND „работи като самостоятелен двоичен файл на твоята машина и се свързва с твоя клъстер на kind“ и „изисква привилегии, за да отваря портове в системата и да се свързва с *runtime* на контейнерите“. Неговият [README](https://github.com/kubernetes-sigs/cloud-provider-kind) е по-точен: „`cloud-provider-kind` ще наблюдава **всичките** ти клъстери на kind“, а неговият контролер на Gateway API „е включен по подразбиране“. README не описва никаква опция за ограничаване до един.

На личния ти лаптоп, с един-единствен клъстер, това няма значение. На споделена машина — тази на лаборатория, тази на екип, който изпълнява тестове паралелно, или твоята, ако имаш клъстер от друг проект — има голямо значение: процес, който ти си стартирал за урока си, би започнал да създава балансьори, CRD и `GatewayClass` в клъстери, които не са твои, без собствениците им да са го поискали. Този курс има правило още от Урок 1: не пипай онова, което не е твое, нито друг контекст, нито друг клъстер. Cloud Provider KIND го нарушава по дизайн.

MetalLB и Envoy Gateway, напротив, са обекти **вътре** в клъстера. Инсталират се с `kubectl` в твоя контекст, живеят в своите пространства от имена (`metallb-system`, `envoy-gateway-system`) и изчезват с `kind delete cluster`. Цената е тази, която видя в 6.1: диапазонът на MetalLB идва от мрежата `kind`, която е споделена, и затова два клъстера с един и същ диапазон не бива да работят едновременно. Това е цена, която се контролира с проверка от един ред. Другото не се контролира.

### 6.6 Envoy Gateway и Gateway API: платформата на входната точка

#### 6.6.1 Трите части на Gateway API

Един `LoadBalancer` е входна точка на Service: всеки със свой IP адрес. Ако утре публикуваш пет услуги, това са пет IP адреса и нито един не знае нищо за HTTP: не може да реши по пътя, нито по името на сайта, нито да сложи общо криптиране. Gateway API решава това с **една** входна точка, която разбира HTTP, и правила, които казват какво влиза и къде отива. [Страницата за Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/) на Kubernetes описва трите му части:

| Част | Какво е, според документацията | В този курс |
|---|---|---|
| `GatewayClass` | „определя набор от входни точки с обща конфигурация, управлявани от контролер, който реализира класа“ | `eg`, тази на Envoy Gateway |
| `Gateway` | „определя екземпляр на инфраструктура, който обработва трафик, като например облачен балансьор“ | `revisor`: слуша HTTP на 80 |
| `HTTPRoute` | „определя специфични за HTTP правила за пренасяне на трафик от един *listener* на Gateway към представяне на мрежови *endpoints*“, които „често се представят със Service“ | `revisor`: всичко, което пристигне, отива към Service `revisor` |

Същата страница обяснява защо са три, а не една: Gateway API е „ориентиран към роли“. `GatewayClass` е на **доставчика на инфраструктура**; `Gateway` — на **оператора на клъстера**, който се занимава с „политики, мрежов достъп и разрешения“; `HTTPRoute` — на **разработчика на приложението**, който се занимава със своя Service. В твоя клъстер си и тримата, но файловете вече са разделени така: `infra/gatewayclass.yaml` е платформа, `gateway.yaml` е проект.

#### 6.6.2 Инсталиране с `--server-side` и защо

Envoy Gateway включва в един-единствен файл CRD на Gateway API и своите. [Ръководството му за инсталиране](https://gateway.envoyproxy.io/docs/install/install-yaml/) го казва: „манифестът `install.yaml` включва CRD на Gateway API и CRD на Envoy Gateway“. Този курс го обвива по същия начин като MetalLB. Това е **програма**: `infra/envoy-gateway/kustomization.yaml`.

```yaml
# Envoy Gateway v1.9.2, instalado SOLO en este clúster. Trae los CRD de Gateway API
# (bundle v1.6.1) y los suyos. Su guía oficial lo instala con server-side apply:
#   kubectl apply --server-side -k infra/envoy-gateway
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/envoyproxy/gateway/releases/download/v1.9.2/install.yaml
```

Официалното ръководство го инсталира с `kubectl apply --server-side`. Какво става без тази опция? Може да се попита, без да се променя нищо, с `--dry-run=server`, което праща всичко на `kube-apiserver`, за да го валидира, и не запазва нищо:

```text
$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -c 'Too long'
3

$ kubectl apply -k infra/envoy-gateway --dry-run=server 2>&1 | grep -m 1 'Too long' | sed 's/.*\(The CustomResourceDefinition\)/\1/'
Error from server (Invalid): error when creating "infra/envoy-gateway": CustomResourceDefinition.apiextensions.k8s.io "envoyproxies.gateway.envoyproxy.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

(В `correr.salida.txt` под всяка от тези две команди се появява `[código de salida: 1]`. Това е кодът на `kubectl apply`, чийто опит `kube-apiserver` отхвърли. Скриптът работи с `pipefail`, който кара една тръба (*pipe*) да се провали, ако се провали някоя от командите ѝ. В твоя терминал, без `pipefail`, тръбата връща кода на `grep`, който е 0, и няма да видиш този ред.) Три отхвърлени CRD, с една и съща причина: „`metadata.annotations`: твърде дълго; не може да надвишава 262144 байта“. Причината е в начина, по който работи обичайният `apply`, този, който използва от Урок 2. Този `apply` запазва във всеки обект анотация, `kubectl.kubernetes.io/last-applied-configuration`, с **пълно копие** на манифеста, който си приложил, за да може следващия път да изчисли разликата. При Deployment това копие тежи няколко килобайта. При CRD на `EnvoyProxy`, чиято схема описва стотици полета, копието надвишава лимита от 256 KiB, който `kube-apiserver` приема за всички анотации на един обект.

`--server-side` променя кой води сметката. [Документацията за *server-side apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) го обяснява: предлага „механизъм, чрез който контролната равнина на твоя клъстер води запис на промените в полетата на един обект“ и го сравнява с анотацията на `kubectl`: вместо да запазва „последното приложено състояние“, записва кои полета управлява всеки, в `metadata.managedFields`. Без копие на манифеста, без гигантска анотация.

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

Всеки ред казва `serverside-applied` вместо `created`. Последните четири вече разказват историята на този урок: политика за валидиране при допускане (`safe-upgrades`, „безопасни надграждания“, според името ѝ), един `Job` на име `certgen`, който, според името си, генерира сертификати, и още един *webhook*, този път от тези, които **променят** обекти (`mutatingwebhookconfiguration`). Пак пазачи. Но не всички блокират: този декларира `failurePolicy: Ignore`, тоест ако не отговори, `kube-apiserver` пропуска заявката. Кой е кой се чете в манифеста, не се предполага (изпълнението го показва по-долу). Десет CRD на Gateway API и осем на Envoy Gateway. Има и още, и се измерват:

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

Три неща се четат там. Десет CRD на `gateway.networking.k8s.io`, **всички** от канала `experimental` и от пакета `v1.6.1` на Gateway API (стандартният канал би бил само стабилното; експерименталният включва допълнително полета и версии в изпитание). Още три CRD, от групата `gateway.networking.x-k8s.io`, които `grep -c` по-горе не броеше: `x` е от experimental. И един *webhook* за промяна с `failurePolicy: Ignore`. `column -t` само подравнява таблицата. Общо, значи: десет плюс три на Gateway API и осем на Envoy Gateway.

#### 6.6.3 Изчакване, пак, и класът

Преди да се използват новите типове, се изчаква да са **установени**, а преди да се поиска входна точка — контролерът да е наличен:

```text
$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met
```

`Established` е условието, което `kube-apiserver` поставя на един CRD, когато вече обслужва новия тип. Един току-що създаден CRD може да се позабави, докато го получи; да чакаш условието означава да питаш клъстера, вместо да гадаеш. Тук вече го имаха: `condition met` веднага. Второто `wait` е като това, което използва с `controller` на MetalLB, сега с контролера на Envoy Gateway.

Сега класът. Това е **програма**: `infra/gatewayclass.yaml`.

```yaml
# gatewayclass.yaml — «eg»: la clase de puerta que atiende Envoy Gateway.
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

Един `GatewayClass` е къс: име, `eg`, и контролерът, който го обслужва. `controllerName` не е украшение: това е подписът, с който контролерът на Envoy Gateway разпознава класовете, които са за него. Ако напишеш друг, класът би съществувал, но никой не би го приел.

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

Между `apply` и `get` има едно трето `wait`, този път за условието `Accepted` на класа: контролерът се бави няколко секунди, докато го разпознае, и без това изчакване твоето `get` може да покаже `ACCEPTED Unknown`. `ACCEPTED True`: Envoy Gateway разпозна класа като свой. А същият `api-resources`, който в 6.2 даваше само заглавия, сега дава десет типа, които `api-resources` показва във `v1`. Внимавай с тази дума: това е **предпочитаната** версия, която клъстерът обслужва, а не гаранция, че всичко е стабилно. `install.yaml` на Envoy Gateway инсталира CRD от **експерименталния** канал на Gateway API (казва го анотацията `gateway.networking.k8s.io/channel: experimental` на всеки CRD, а изпълнението я чете по-горе), който включва, освен стабилното, полета и версии в изпитание, и още три типа от групата `gateway.networking.x-k8s.io`. Трите, които използва този урок, `GatewayClass`, `Gateway` и `HTTPRoute`, са стабилни. В истински клъстер се решава нарочно кой канал да се инсталира. Днес използваш три. `GRPCRoute`, `TCPRoute` и `UDPRoute` са маршрути за други протоколи; `TLSRoute` и `BackendTLSPolicy` са, съответно, да пропуснеш криптирането, без да го отваряш, и да криптираш участъка от входната точка до Service, неща, които този урок не слага. `ReferenceGrant` е разрешението, което дава собственикът на едно пространство от имена, за да може нещо от **друго** пространство да сочи към обектите му: например маршрут, който праща трафик към чужд Service, или Gateway, който използва сертификат, съхранен в чужд `Secret`. В този курс маршрутът и Service-ът винаги живеят в едно и също пространство, така че няма да имаш нужда от него. Дали един маршрут може да се закачи за Gateway от **друго** пространство не се решава с `ReferenceGrant`, а с полето `allowedRoutes` на *listener*-а на Gateway; [документацията за Gateway](https://kubernetes.io/docs/concepts/services-networking/gateway/) го казва така: „по подразбиране един Gateway приема маршрути само от същото пространство от имена“. Обърни внимание на колоната `NAMESPACED`: `gatewayclasses` е `false`, защото един клас важи за целия клъстер. Той е платформа.

### 6.7 Входната точка на `revisor`

#### 6.7.1 Манифестът

Това е **програма**: `gateway.yaml`.

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

Два обекта в един файл, разделени с `---`. Четат се така:

- **`Gateway`** иска входна точка от класа `eg` с един *listener* (ухо): `http`, протокол `HTTP`, порт `80`. Не казва нищо за IP адрес: IP адреса го иска Envoy Gateway от този, който го раздава, а в този клъстер това е MetalLB.
- **`HTTPRoute`** се закача за тази входна точка с `parentRefs: [revisor]` и има едно правило: всичко, което започва с `/` (`PathPrefix`), тоест всичко, отива към Service `revisor` на неговия порт `80`. Обърни внимание на целта: `revisor` `ClusterIP` от Урок 3, а не `revisor-publico`. Входната точка влиза в клъстера и оттам използва вътрешния Service, с неговия EndpointSlice и неговото разпределение.

[Справочникът за `HTTPRoute`](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/) казва още, че ако не напишеш `matches`, стойността по подразбиране е точно тази, префикс `/`, „който има ефект да съвпада с всяка HTTP заявка“. Курсът го пише въпреки това, по същата причина, по която писа `type: ClusterIP`: за да е на показ решението „всичко минава“. Упражнение 2 го променя.

#### 6.7.2 Прилагане, този път наистина

Същата команда от 6.2, с платформата на мястото ѝ:

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

Седем `unchanged` и две `created`. Нищо не се рестартира: `Secret` запази името си, защото `token.txt` е същият като в 6.2, а Deployment-ът нямаше причина за *rollout*. `apply` е декларативен и прилагането му два пъти е безопасно: каквото вече го е имало, си остава. Затова поправката на грешката с реда не беше „изтрий всичко и започни отначало“, а да се инсталира онова, което липсваше, и да се приложи отново същото.

`wait` чака условието `Programmed` на Gateway: контролерът вече да е настроил инфраструктурата, която го обслужва.

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

Gateway има адрес, `172.18.255.201`, вторият от диапазона на MetalLB (първият вече беше на `revisor-publico`), и `PROGRAMMED True`. Маршрутът има две условия, които ще използваш в „Грешката, която ще видиш“: `Accepted=True`, входната точка го прие като свой; и `ResolvedRefs=True`, всичко, което назовава (Service `revisor` и неговият порт), съществува.

#### 6.7.3 Кой обслужва входната точка

Един `Gateway` е декларация. Някой трябва да я направи реална:

```text
$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-default-revisor-4e6f5d7f-55b49857bd-25dqk   2/2     Running   0          113s
pod/envoy-gateway-5fc4949dcb-f8jss                    1/1     Running   0          5m44s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
service/envoy-gateway                    ClusterIP      10.96.233.233   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   5m45s
```

Два Pod-а. `envoy-gateway` е **контролерът**: чете твоите `Gateway` и `HTTPRoute` и превежда. `envoy-default-revisor-…` е **проксито**, Envoy, който наистина получава заявките; името му събира пространството от имена на Gateway (`default`) и името му (`revisor`). Създаден е от контролера, когато се е появил твоят Gateway, със собствен Service **от тип `LoadBalancer`**, и именно той получи `172.18.255.201` от MetalLB. Двете платформи в този урок работят заедно, без да се познават: Envoy Gateway иска `LoadBalancer`, MetalLB му го дава.

Всички `LoadBalancer` на клъстера, погледнати заедно:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
default                revisor-publico                  LoadBalancer   10.96.115.79    172.18.255.200   80:30808/TCP                                       8m21s
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   10.96.145.37    172.18.255.201   80:30581/TCP                                       113s
```

Две входни точки към `revisor`: директната, `.200`, и именуваната, `.201`. Запази тази таблица за навика за сигурност.

#### 6.7.4 Влизане

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

Трите отговора, които имат значение: `/salud` отговаря, `/api/estados` с токена дава таблицата, а без токен дава `401`. Този `401` го дава **`revisor`**, а не входната точка: Gateway пропуска всичко, а `revisor` продължава да изисква токена си като от Урок 4. Логът на `revisor` го потвърждава:

```text
$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /api/estados'
[pod/revisor-5674f7c4cc-bhbvp/revisor] revisor: GET /api/estados 200 17ms
[pod/revisor-5674f7c4cc-pbc9f/revisor] revisor: GET /api/estados 200 8ms
[pod/revisor-5674f7c4cc-w7hgf/revisor] revisor: GET /api/estados 401 1ms
```

(`kubectl logs -l` събира логовете на трите реплики, групирани по Pod, а не по час, така че редът на редовете не е този на заявките.) До този момент имаше три заявки към `/api/estados`: тази от 6.4.5 през `.200`, тази по-горе с токен през входната точка и тази по-горе без токен. Появяват се и трите, а онова, което може да се твърди със сигурност, е това, което казва `401`: записал го е един `revisor` в своя лог, тоест той го е дал, а не входната точка. Коя реплика е обслужила всяка не следва от този изход; за разпределението се грижи обичайното, Service `revisor`, а не входната точка.

Последният `curl` по-горе поиска заглавките с `-i`: `HTTP/1.1 200 OK`. Още нещо, което разделът за навика за сигурност подема: това е HTTP/1.1 на порт 80, без криптиране.

### 6.8 `Ingress`, замразеният API, и защо не `ingress-nginx`

Ще срещнеш `Ingress` в почти всеки урок по Kubernetes отпреди 2024 г. Той е дядото на онова, което току-що направи: обект, който казва „този маршрут отива към този Service“, обслужван от контролер. Още съществува и [документацията за Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) казва състоянието му с всички букви: „API на Ingress е замразен“; „вече не се разработва и няма да получава повече промени или актуализации“. И препоръката: „проектът Kubernetes препоръчва да се използва Gateway вместо Ingress“. Внимавай с това, което **не** казва: не е остарял в смисъл, че ще го махнат. Същата страница уточнява, че е стабилен API, подчинен на гаранциите на стабилните API, и че проектът „няма планове да премахва Ingress от Kubernetes“. Замразен означава: работи, не расте. Онова, което му липсва (маршрути за други протоколи, разделени роли, по-фини правила), няма да му дойде. Gateway API се роди за това.

`ingress-nginx` е нещо друго: не API, а **контролер** на Ingress, най-популярният с години, този от второто предложение в сцената. През ноември 2025 г. [блогът на Kubernetes](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) обяви извеждането му от поддръжка: „през март 2026 г. поддръжката на Ingress NGINX ще бъде спряна и проектът ще бъде изведен от поддръжка. След тази дата няма да има повече версии, нито поправки на грешки, нито актуализации за отстраняване на откритите уязвимости в сигурността“. Съществуващите инсталации продължават да работят и артефактите продължават да се теглят, казва същото съобщение. Затова урокът отпреди две години още „работи“ този следобед. Но компонент, който приема трафик отвън и вече не получава актуализации за сигурност, е точно онова, което не се инсталира днес. Съобщението препоръчва миграция към Gateway API или към друг контролер.

Три имена, три различни неща:

| Име | Какво е | Състояние |
|---|---|---|
| `Ingress` | API на Kubernetes | замразен: работи, не расте |
| `ingress-nginx` | контролер, който обслужва `Ingress` | изведен от поддръжка от март 2026 г.: без актуализации за сигурност |
| Gateway API | API-наследникът на `Ingress` | актуален; използва го този курс |

Упражнение 3 ти позволява да видиш `Ingress` в този клъстер и какво става с него, когато никой не го обслужва.

### 6.9 Редът: платформа, изчакване, проект

Събери онова, което видя. В 6.2 — проектът преди платформата: `no matches for kind`. В 6.4 — диапазонът преди пазача: `failed calling webhook … connection refused`. В 6.6 проектът също не би могъл да поиска своя Gateway, преди да съществува класът `eg`. И в трите случая файлът беше наред. Погрешният беше моментът.

Така се разгръща всичко от този урок от празен клъстер, в три стъпки. Не е фрагмент, написан по памет: това е програмата `levantar.sh` и тя беше изпълнена наистина. `correr.sh` изтрива клъстера на упражненията, създава **друг** същия, със заредени двата образа и без нито един персонализиран ресурс (`kubectl get crd` дава `No resources found`), и изпълнява `levantar.sh`, без да поправя нищо ръчно:

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

Функцията `paso` прави три неща: проверява контекста с `ctx` (и спира, ако не е `kind-curso-k8s-l6`: MetalLB и Envoy Gateway създават обекти, които важат за целия клъстер), отпечатва командата с `$` и я изпълнява. Със `set -euo pipefail` първата грешка спира скрипта, така че едно изпълнение без прекъсвания е доказателство, че редът работи.

Диапазонът и класът са в **стъпка 3**, а не в 1, заради онова, което видя: диапазонът изисква *webhook*-ът на MetalLB да отговаря (6.4.2), а класът изисква неговият CRD да е установен (6.6.3). README на курса ги нарича „три стъпки“, макар блокът да има повече от три команди: стъпките са по **ред**, а не по брой команди. (В Урок 10 двата `apply` на платформата от стъпка 1 се обединяват в един.) Това е изходът от това изпълнение:

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

Прочети го на стъпки. Стъпка 1: по един `created` за всеки обект на MetalLB и по един `serverside-applied` за всеки обект на Envoy Gateway; вторият изпраща наведнъж десетте плюс трите CRD на Gateway API и осемте на Envoy. Стъпка 2: пет изчаквания и всички завършват с `condition met` или `successfully rolled out`; `speaker` минава от 0 на 3 налични pods. Стъпка 3: диапазонът и класът се създават заедно, класът се изчаква до `Accepted`, проектът се създава целият (девет `created`, без нито едно `no matches for kind`) и Gateway стига до `Programmed`. Нито една грешка и нито един `sleep`. След това `correr.sh` проверява онова, което има значение:

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

Gateway и `LoadBalancer` получиха отново `172.18.255.201` и `.200`, в този ред, входната точка отговаря на `/salud` и на таблицата на отчета, а `.200` също. (Service-ът на този нов клъстер има друг `NodePort`, `31214`, а възрастта на Gateway е `82s`, защото `kubectl apply` и изчакванията от стъпка 3 се изпълняват преди този `get`.) С това целта на урока е изпълнена: нов клъстер, три стъпки, нищо поправено ръчно.

Три идеи, които ще разпознаеш в Урок 10, когато целият проект се разгръща с два `apply -k` и едно изчакване:

- **Платформата се инсталира веднъж на клъстер; проектът — всеки път, когато се промени.** MetalLB и Envoy Gateway не са на `revisor`: в деня, в който публикуваш втора услуга, тя ще използва същия клас `eg` и същия диапазон.
- **Изчакването не е `sleep`.** Един `sleep 30` работи на твоята машина и се проваля на по-бавна. `kubectl wait` пита за условието и се проваля ясно, ако то не дойде за времето, което си му дал.
- **Редът не се крие.** Ако го автоматизираш (скрипт, стъпка от *pipeline*), трите стъпки си остават там, с име, всяка със своята проверка на контекста (`ctx`). Скрипт, който „опитва отново, докато мине“, крие причината; такъв, който чака условието, я назовава.

## Грешката, която ще видиш

Грешката на този урок е най-честата с Gateway API и прилича на погрешно написания селектор от Урок 3: маршрут, който сочи към Service, който не съществува. Предизвиква се с `fig06_01.ruta-mala.yaml`, една **програма**, която се проваля нарочно: същият `HTTPRoute`, с една буква по-малко в целта.

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

`configured`, без оплаквания. Както със селектора от Урок 3, `kube-apiserver` не може да знае, че си искал да напишеш `revisor`: `revisr` е валидно име. Чете се по ред.

**Първо, симптомът**, отвън:

```text
$ curl -s -m 5 -i http://172.18.255.201/salud | grep -iE "^(HTTP|content-length)"
HTTP/1.1 500 Internal Server Error
content-length: 0
```

`500` и празно тяло. Обърни внимание на това, което **не** е. Не е код на `curl` (6, 7 или 28): връзката е осъществена, някой е отговорил. И не е `revisor`: `revisor` никога не отговаря с празно тяло. Отговорил е Envoy, входната точка, като казва „нямам на кого да те пратя“. [Спецификацията на Gateway API v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/) го изисква така: ако всички препратки на едно правило са невалидни и правилото няма филтри, „целият трафик, който съвпада с това правило, ТРЯБВА да получи код 500“.

**Второ, входната точка.** Ако е отговорила, входната точка е наред:

```text
$ kubectl get gateway revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.18.255.201   True         2m1s
```

`PROGRAMMED True`, същият адрес. Проблемът е зад нея.

**Трето, условията на маршрута.** Това е решаващата стъпка, еквивалентът на колоната `ENDPOINTS` от Урок 3:

```text
$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=False BackendNotFound

$ kubectl get httproute revisor -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].message}{"\n"}'
Failed to process route rule 0 backendRef 0: service default/revisr not found.
```

Две условия и тук е клопката: `Accepted=True`. Входната точка е приела маршрута. Който гледа само това условие, или само `kubectl get httproute` (което не показва никакво), заключава, че всичко е наред. Това, което казва истината, е второто: `ResolvedRefs=False`, причина `BackendNotFound`. А съобщението, на английски, не оставя съмнение: „неуспех при обработка на правило 0, препратка 0: не е намерен Service `default/revisr`“. (`.status.parents[0]` е състоянието на маршрута спрямо първата му входна точка; един маршрут може да се закачи за няколко и всяка му поставя своите условия.)

**Четвърто, потвърждението:**

```text
$ kubectl get service revisr
Error from server (NotFound): services "revisr" not found
[código de salida: 1]
```

**Поправката** е в причината, а не във входната точка: да приложиш отново добрия файл, който тук е цялата kustomization.

```text
$ kubectl apply -k . | grep httproute
httproute.gateway.networking.k8s.io/revisor configured

$ kubectl get httproute revisor -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
Accepted=True Accepted
ResolvedRefs=True ResolvedRefs

$ curl -s -m 5 http://172.18.255.201/salud
{"estado":"vivo","version":"1.6.0"}
```

Както в Урок 3, първо се гледа дали състоянието е наред (`ResolvedRefs=True`) и после се тества. Между прилагането на маршрута и момента, в който Envoy получи новата си конфигурация, минава малко време: ако първият ти `curl` още дава предишния код (`200` след лошия маршрут, `500` след добрия), повтори го. `correr.sh` изчаква входната точка да отговори с очаквания код, преди да покаже `curl`, и го отбелязва в изхода като `(espera: la puerta ya contesta 500 …)`.

**Редът за всяка входна точка, която не отговаря добре:**

1. Какво връща `curl`? Код на `curl` (7, 28) е мрежата или IP адресът; HTTP код (`404`, `500`) значи, че входната точка е отговорила.
2. Има ли Gateway `ADDRESS` и `PROGRAMMED True`? Ако няма адрес, виж MetalLB и неговия диапазон.
3. Има ли маршрутът `Accepted=True` **и** `ResolvedRefs=True`? Прочети и двете, и `message` на тази, която е в `False`.
4. Ако всичко това е наред, слез един етаж: целевият Service и неговият EndpointSlice, с реда от Урок 3.

## Навикът за сигурност от урока: излага се минимумът, през именувана входна точка, и се казва какво липсва

Таблицата с навици на курса определя за този урок три неща. Проверяват се с клъстера пред очите.

**Какво остана изложено.** Всичко, което приема трафик отвън на клъстера:

```text
$ kubectl get services -A -o custom-columns='ESPACIO:.metadata.namespace,NOMBRE:.metadata.name,TIPO:.spec.type,IP-EXTERNA:.status.loadBalancer.ingress[0].ip,NODEPORT:.spec.ports[*].nodePort' | grep -E 'ESPACIO|LoadBalancer|NodePort'
ESPACIO                NOMBRE                           TIPO           IP-EXTERNA       NODEPORT
default                revisor-publico                  LoadBalancer   172.18.255.200   30808
envoy-gateway-system   envoy-default-revisor-4e6f5d7f   LoadBalancer   172.18.255.201   30581
```

Записано като опис, така както трябва да може да се каже на глас:

| Входна точка | Адрес | Какво пропуска | Кой решава |
|---|---|---|---|
| `revisor-publico` | `172.18.255.200:80` | **целия** `revisor`, без правила | никой: това е директен `LoadBalancer` |
| неговият `NodePort` | `30808` във **всеки** възел | същото | никой |
| Gateway `revisor` | `172.18.255.201:80` | каквото каже `HTTPRoute` | маршрутът, версиониран файл |
| неговият `NodePort` | `30581` във всеки възел | същото като Gateway | маршрутът |

Днес има **две** входни точки към една и съща услуга и това е урок само по себе си: директната заобикаля всяко правило, което сложиш в именуваната. Упражнение 2 го измерва: когато маршрутът на Gateway пропуска само `/salud`, `.200` продължава да връща целия отчет. Затова „именувана входна точка“ е навикът и затова Урок 7 премахва `revisor-publico` и оставя Gateway като единствен вход. `NodePort`-овете си остават там по причината от 6.3.3; в истински клъстер е нормално мрежата на възлите да не е достъпна отвън и това да се осигури от защитна стена.

**Какво не остана изложено.** Възлите на kind продължават да не публикуват нищо към твоята машина, освен порта на API:

```text
$ docker port curso-k8s-l6-control-plane
6443/tcp -> 127.0.0.1:59736

$ docker port curso-k8s-l6-worker
```

А от твоя терминал, на Mac на изпълненията, IP адресът на Gateway не съществува:

```text
$ curl -s -m 3 http://172.18.255.201/salud
[código de salida: 28]
```

Този `curl` се изпълни в терминала на Mac, а не в контейнера. Код 28: времето изтече. Мрежата `kind` живее във виртуалната машина на Colima и Mac няма маршрут към нея. В твоя Linux Mint е различно: Docker свързва машината ти с мрежата `kind`, така че там `.201` трябва да отговори от терминала ти. Друг компютър от твоята мрежа не я достига: с правилата, които Docker поставя по подразбиране (от Docker Engine 28, който блокира достъпа чрез директно маршрутизиране до мрежите на контейнерите), мрежата `kind` се вижда само от твоята собствена машина. Но „твоята машина“ включва всички нейни потребители: на споделена машина всеки, който има сесия в нея, може да поиска отчета от `.200` или `.201`, или от `NodePort`-овете на трите възела, а който има `root`, може да прочете токена, който пътува некриптиран (например като наблюдава моста на Docker (*bridge*) с `tcpdump`). Това публикува тази лаборатория: малко и само навътре в машината, но не е „никой“.

**Какво липсва: криптирането.**

```text
$ curl -s -m 5 https://172.18.255.201/salud
[código de salida: 7]

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.18.255.201/api/estados -H 'Authorization: Bearer token-inventado'
401
```

През `https`, код 7: никой не слуша на 443, защото Gateway има само един *listener* `HTTP` на 80. А втората команда напомня какво пътува през тази входна точка: токенът на `revisor`, в заглавка, **като чист текст**. Всеки, който може да наблюдава мрежата между клиента и входната точка, го чете. `revisor` отхвърля измисления токен (`401`), но не може да направи нищо срещу някого, който е копирал истинския. Липсващата част е втори *listener* в Gateway, с `protocol: HTTPS`, порт 443 и `tls.certificateRefs`, който сочи към `Secret` със сертификата. `HTTPRoute` не се променя. (`TLSRoute` и `BackendTLSPolicy`, от списъка в 6.6.3, са други неща: да пропуснеш криптирането, без да го отваряш, и да криптираш участъка от входната точка до Service.) Този курс не го слага, защото истински сертификат изисква истинско име на домейн, което една лаборатория в kind няма. Но го казва, а това е навикът: **входна точка без криптиране се публикува със знанието, че го няма**, и в истински клъстер не се публикува така. Урок 10 го поставя в списъка с онова, което липсва на всичко това, за да бъде готово за продукция.

## Какво се прави погрешно

**Смяна на Service на `NodePort` „за да го видят“.** Отваря случаен порт на всички възли, без име и без правила. Това е първото предложение от сцената.

**Забравяне, че всеки `LoadBalancer` е също и `NodePort`.** Дори външният IP адрес никога да не дойде, портът на възела вече е отворен (6.3.3).

**Инсталиране на `ingress-nginx`, защото го казва един урок.** Без актуализации за сигурност от март 2026 г. А `Ingress`, API-то, е замразен: новото се пише с Gateway API.

**Изпълнение на Cloud Provider KIND на споделена машина.** Наблюдава всички клъстери на kind на машината, не само твоя.

**Прилагане на проекта преди платформата и „поправяне“ чрез повтаряне на командата, докато мине.** Понякога работи и крие причината. Инсталира се платформата, изчаква се условието с `kubectl wait` и после се прилага проектът.

**Чакане със `sleep`.** Брой секунди, който стига на твоята машина, не стига на друга. Чака се условието, с `--timeout`.

**Инсталиране на Envoy Gateway без `--server-side`.** Три от неговите CRD не се побират в анотацията на обичайния `apply`.

**Гледане само на `Accepted` при един маршрут.** `Accepted=True` с `ResolvedRefs=False` е приет маршрут, който не води наникъде. Четат се и двете условия.

**Избиране на диапазона на MetalLB на случаен принцип.** Трябва да попада в мрежата `kind`, далеч от IP адресите на възлите, и да не се повтаря в два живи клъстера едновременно.

**Оставяне на две входни точки към една и съща услуга.** Тази без правила заобикаля правилата на другата (Упражнение 2).

**Публикуване с чист HTTP, без да се казва.** Токенът пътува четим. Ако една лаборатория не може да сложи криптиране, поне го записва в списъка си с неизвършеното.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред и от състоянието, в което е останал след поправянето на грешката. Преди всяко упражнение `kubectl config current-context` трябва да казва `kind-curso-k8s-l6`. `correr.sh` ги изпълнява по същия начин, а изходът му е в `correr.salida.txt`. **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще се случи. Четвъртото се пише със свои думи.

### Упражнение 1 — Освобождаване на адрес и повторно искане

Изтрий Service `revisor-publico` с `kubectl delete service revisor-publico`. Предскажи: какво отговаря `curl -s -m 3 http://172.18.255.200/salud` от клиента отвън? Какви `LoadBalancer` остават в клъстера? Сега приложи отново kustomization с `kubectl apply -k .`: какъв IP адрес получава новият Service, `.200`, която беше освободена, или `.202`, следващата, която никога не е била използвана? А неговият `NodePort`, същият ли е като преди? Провери и обясни.

### Упражнение 2 — Входната точка, сведена до минимум

`fig06_02.solo-salud.yaml` е същият `HTTPRoute` с по-тясно правило: само `GET` към `/salud`, точно.

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

Приложи го и предскажи HTTP кода на всяка от тези пет заявки, всички от клиента отвън: `GET /salud` през Gateway; `GET /api/estados?formato=tabla` **с** токена, през Gateway; `GET /salud/` (с наклонена черта в края) през Gateway; `POST /salud` през Gateway; и `GET /api/estados?formato=tabla` с токена, през `172.18.255.200`. Провери с `curl -s -o /dev/null -w '%{http_code}\n'`. Кой отговаря за всеки `404`: Envoy или `revisor`? Какво казва последният отговор за наличието на две входни точки? Накрая приложи отново `kubectl apply -k .`.

### Упражнение 3 — `Ingress`, който никой не обслужва

`fig06_03.ingress.yaml` е `Ingress`, който праща всичко към Service `revisor`, като маршрута от 6.7:

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

Преди да го приложиш, изпълни `kubectl get ingressclass`. Предскажи: клъстерът приема ли `Ingress`, или го отхвърля, както отхвърли `Gateway` в 6.2? Ако го приеме, какъв адрес ще има след 15 секунди? Приложи го, провери с `kubectl get ingress revisor` и с `kubectl describe ingress revisor` и обясни разликата с 6.2 в две изречения. Изтрий го накрая.

### Упражнение 4 — Защити решението

Един колега ти казва: „ръководството на kind препоръчва Cloud Provider KIND, това е един-единствен двоичен файл и ти дава LoadBalancer, Ingress и Gateway API, без да инсталираш нищо в клъстера. За какво са ти толкова MetalLB и Envoy Gateway?“. Отговори му с най-много пет изречения: къде работи Cloud Provider KIND, върху кои клъстери действа, какво би станало на споделена машина, каква цена плаща решението на курса и как се контролира тази цена.

## Решения

### Решение 1

Измерено в `correr.salida.txt`:

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

**Без Service-а `curl` не се свързва**: излиза с 28 (времето изтече) или, според системата ти, със 7 (не успя да се свърже; в Linux, „No route to host“, когато ARP въпросът остава без отговор). Двата казват едно и също: никой не отговаря за `172.18.255.200`. Няма кой да откаже с HTTP, защото никой `speaker` вече не обявява този IP адрес, ARP въпросът остава без отговор и пакетът няма накъде да отиде. Когато изтри Service-а, MetalLB **освободи** адреса. Остава един-единствен `LoadBalancer`, този на Gateway, който не е разбрал нищо: още е на `.201`.

**Новият Service получава отново `.200`**, а не `.202`. MetalLB раздава първия свободен от диапазона си и `.200` отново беше свободна. Но това е нов обект: друг `CLUSTER-IP` (`10.96.129.166` вместо `10.96.115.79`) и **друг `NodePort`** (`31622` вместо `30808`). Външният IP адрес излезе същият, защото така работи разпределението на MetalLB, а не защото Kubernetes го помни. Ако между изтриването и създаването друг Service беше поискал IP адрес, той щеше да остане с `.200`, а твоят Service — с друг. Затова, ако един външен IP адрес трябва да е фиксиран (защото е в DNS или в конфигурацията на защитна стена), той се иска писмено в Service, с анотацията `metallb.io/loadBalancerIPs: 172.18.255.200` ([ръководството за използване на MetalLB](https://metallb.io/usage/) я предпочита пред `spec.loadBalancerIP`, което е на път да бъде премахнато), и не се разчита на случайността на реда.

### Решение 2

Измерено в `correr.salida.txt`:

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

**`200`, `404`, `404`, `404` и `200`.** През Gateway минава само точно `GET /salud`. `/api/estados` не съвпада с никакво правило, дори с токен: токенът дори не стига до `revisor`, защото **Envoy** отговаря `404` по-рано. `/salud/` също не, защото `Exact` е точно: една излишна наклонена черта е друг път. А `POST /salud` не съвпада заради метода. Трите `404` са на входната точка: никое правило не води тези заявки към `revisor`, така че Envoy отговаря сам.

**Петият е този, който има значение:** през `172.18.255.200`, директния `LoadBalancer`, отчетът излиза пълен, `200`. Правилото, което току-що сложи в именуваната входна точка, не защитава нищо, докато съществува друга входна точка без правила. Това е аргументът на Урок 7 за премахването на `revisor-publico`: намаляването на изложеното е от полза само ако има **един-единствен** вход.

Когато приложиш отново kustomization, маршрутът се връща към `PathPrefix /` и `/api/estados` без токен пак дава `401`, този път от `revisor`.

### Решение 3

Измерено в `correr.salida.txt`:

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

**Клъстерът го приема и никой не го обслужва.** За разлика от `Gateway` в 6.2, типът `Ingress` идва вътре в Kubernetes, в групата `networking.k8s.io`: не е нужен никакъв CRD, за да се създаде. Но `Ingress` е декларация, също като `Gateway`, и без контролер, който да я чете, не се случва нищо: няма `IngressClass` (`No resources found`), колоната `CLASS` казва `<none>`, `ADDRESS` е празна и няма нито едно събитие. Това е `<pending>` от 6.3 с друго лице: никаква грешка, никакъв резултат. Envoy Gateway, контролерът, който е инсталиран, обслужва Gateway API, а не този `Ingress`. Двете изречения: „`Gateway` не съществуваше като тип и клъстерът го отхвърли; `Ingress` съществува като тип и клъстерът го запази, но никой не го превръща във входна точка. Приет обект не е обслужван обект“.

### Решение 4

Един възможен отговор: „Cloud Provider KIND работи като програма на твоята машина, извън клъстерите, с права да отваря портове и да говори с Docker. Собственият му README казва, че наблюдава всичките ти клъстери на kind и не описва опция за ограничаване до един; освен това контролерът му за Gateway API е включен. На споделена машина програмата, която стартирах за урока си, би пипала клъстери на други хора, без те да са го поискали. MetalLB и Envoy Gateway живеят вътре в моя клъстер и се изтриват с него; цената е, че диапазонът от IP адреси на MetalLB идва от мрежата kind, която е споделена. Тази цена се контролира, като преди създаването на клъстера се провери, че никой не отговаря вече на първия IP адрес от диапазона, и като се изпълнява само един клъстер с MetalLB наведнъж.“

## Изтриване на клъстера

Когато приключиш упражненията, изтрий клъстера на урока. С него си отиват MetalLB, Envoy Gateway, техните CRD и техните IP адреси:

```text
$ kind delete cluster --name curso-k8s-l6
Deleting cluster "curso-k8s-l6" ...
Deleted nodes: ["curso-k8s-l6-control-plane" "curso-k8s-l6-worker" "curso-k8s-l6-worker2"]

$ kind get clusters | grep -c curso-k8s-l6
0
```

След това изтрий `token.txt` и временната папка на `kubeconfig`, която пази администраторското удостоверение на клъстера, който току-що изтри. `rm -rf` е опасен, ако променливата е празна или сочи другаде, затова е защитен с `case`, който го пуска да се изпълни само ако пътят е този, който е създал `mktemp` в 6.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 6.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l6.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt
```

Затварянето на терминала спира да използва този `kubeconfig`, но не го изтрива: без `case` удостоверението би останало в `/tmp`. Провери и че не е останал никакъв контейнер на клиента: `docker ps -a --filter name=curso-k8s-l6` не трябва да показва нищо. От този момент `172.18.255.200` отново е свободна за следващия клъстер, който има нужда от нея.

## Как разбирам, че съм успял

- [ ] Обясняваш защо `revisor-publico` остана в `<pending>` и доказваш с `curl` срещу IP адреса на един възел, че неговият `NodePort` вече е бил отворен.
- [ ] Инсталираш MetalLB, даваш му диапазона `172.18.255.200-172.18.255.220` и четеш в събитията на Service кой е присвоил IP адреса (`IPAllocated`) и от кой възел се обявява (`nodeAssigned`).
- [ ] При `no matches for kind … ensure CRDs are installed first` казваш какво липсва (един CRD), а при `failed calling webhook … connection refused` казваш какво да изчакаш (контролерът, който отговаря на *webhook*-а).
- [ ] Записваш по памет трите стъпки: платформа, `kubectl wait`, проект; и обясняваш защо `sleep` не е изчакване.
- [ ] Обясняваш какво са `GatewayClass`, `Gateway` и `HTTPRoute`, на коя роля съответства всеки и кой създава Pod `envoy-default-revisor-…`.
- [ ] При `500` от входната точка проверяваш Gateway, двете условия на маршрута и `message` и намираш `BackendNotFound`.
- [ ] Правиш описа на изложеното (двата IP адреса, двата `NodePort`, 6443 на `127.0.0.1`) и казваш какво липсва: криптиране.
- [ ] Обясняваш с по едно изречение: защо не Cloud Provider KIND, какво означава, че `Ingress` е замразен, и защо не `ingress-nginx`.
- [ ] Изпълняваш `programas/06-entrar-al-cluster/correr.sh > /tmp/mi-corrida-l6.txt 2>&1` и сверяваш с `correr.salida.txt` (не пренасочвай към този файл: той е еталонът) онова, което не се променя между изпълненията: три възела `Ready` във `v1.37.0`; мрежата `172.18.0.0/16`; `No resources found` при CRD; седем `created` и двете `no matches for kind` за `Gateway` и `HTTPRoute`; `revisor-publico` в `<pending>` и `/salud` през `NodePort` на два възела; `failed calling webhook … connection refused` от първия опит с диапазона (може да не ти излезе, ако машината ти е по-бърза от стартирането на MetalLB, и това също учи на нещо); девет CRD на `metallb.io`; `ipaddresspool.metallb.io/curso created` при втория опит; един `controller` и три `speaker`; **`172.18.255.200`** в `revisor-publico`, с `IPAllocated` и `nodeAssigned … layer2`; `3` реда `Too long` и лимитът от `262144 bytes`; `10` CRD на Gateway API и `8` на Envoy Gateway; `GatewayClass` `eg` с `ACCEPTED True` и десет типа в `api-resources`; седем `unchanged` и две `created`; Gateway на **`172.18.255.201`** с `PROGRAMMED True`; `Accepted=True` и `ResolvedRefs=True`; един Pod `envoy-default-revisor-…` с `2/2`; `/salud` и таблицата през входната точка и `401` без токен; при лошия маршрут `ResolvedRefs=False BackendNotFound`, `service default/revisr not found` и `HTTP/1.1 500`; кодът 7 през `https`; в Упражнение 1 — код на `curl` (28 или 7) и върнатата `.200`; в Упражнение 2 — `200 404 404 404 200`; в Упражнение 3 — празен `Address`; и накрая `sin diferencias con los archivos`. IP адресите на Pod-овете, Service-ите и възлите, `NodePort`-овете, наставките, възрастите, възелът, който обявява IP адреса, редът на редовете на `kind load` и колко пъти се повтаря всеки ред на `rollout status` се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] От току-що създаден клъстер, без нито един персонализиран ресурс, изпълняваш `./levantar.sh` и стига до `Programmed` без грешка и без да поправяш нищо ръчно; и казваш защо диапазонът и класът са в стъпка 3.
- [ ] Четеш изхода на `kubectl get crd` от 6.6.2 и казваш три неща: че CRD на Gateway API са от канала `experimental`, че има още три от `x-k8s.io` и че *webhook*-ът на Envoy е `Ignore`, а тези на MetalLB — `Fail`.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l6`, временната папка на `kubeconfig` вече не съществува в `/tmp` и никой не отговаря на `172.18.255.200`.

## Обобщение

Отговори, без да гледаш урока:

1. Защо `LoadBalancer` остава в `<pending>` в kind? Какво отваря въпреки това?
2. Какво правят `controller` и `speaker` на MetalLB и какво означава „слой 2“?
3. Защо диапазонът на MetalLB идва от мрежата `kind` и защо от края ѝ?
4. Какво е CRD и каква грешка дава прилагането на обект, чийто CRD не съществува?
5. Какво е *webhook* за допускане и какво прави `kube-apiserver`, когато не може да го извика, според `failurePolicy` на *webhook*-а? Каква стойност имат тези на MetalLB и каква стойност има този за промяна на Envoy Gateway?
6. Кои са трите стъпки за разгръщане на платформата и проекта и какво точно чака всяко `kubectl wait` от този урок?
7. Защо Envoy Gateway се инсталира с `--server-side`?
8. Каква роля има всяка от трите части на Gateway API и кой създава Pod-а, който наистина получава заявките?
9. Каква е разликата между `Ingress`, `ingress-nginx` и Gateway API и в какво състояние е всеки?
10. Какво остава изложено в края на този урок и какво липсва на входната точка?

## Източници

Всички посетени на 21 октомври 2026 г.

- [Kubernetes, „Service“](https://kubernetes.io/docs/concepts/services-networking/service/): типът `LoadBalancer`, осигуряван от облачния доставчик асинхронно и публикуван в `.status.loadBalancer`; реализацията му върху `NodePort`; `allocateLoadBalancerNodePorts` и стойността му по подразбиране `true`.
- [Kubernetes, „Gateway API“](https://kubernetes.io/docs/concepts/services-networking/gateway/): Gateway API като добавка, определена с персонализирани ресурси; `GatewayClass`, `Gateway` и `HTTPRoute`; дизайнът, ориентиран към роли.
- [Kubernetes, „Ingress“](https://kubernetes.io/docs/concepts/services-networking/ingress/): замразеният API на Ingress, без планове за премахването му; препоръката да се използва Gateway.
- [Kubernetes, блог, „Ingress NGINX Retirement: What You Need to Know“](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) (11 ноември 2025 г.): краят на поддръжката през март 2026 г., без версии, поправки или актуализации за сигурност след това; съществуващите инсталации продължават да работят; препоръката за миграция към Gateway API.
- [Kubernetes, „Custom Resources“](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/): какво е персонализиран ресурс и какво създава `CustomResourceDefinition`.
- [Kubernetes, „Dynamic Admission Control“](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): какво са *webhook*-овете за допускане, за валидиране и за промяна; `failurePolicy` с `Fail` по подразбиране.
- [Kubernetes, „Deployments“](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): условието `Available` като минимална наличност според стратегията за обновяване.
- [Gateway API, „ReferenceGrant“](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): разрешението за препратки между пространства от имена; връзката маршрут–Gateway между пространства се решава в *listeners* (`allowedRoutes`).
- [MetalLB, „Usage“](https://metallb.io/usage/): анотацията `metallb.io/loadBalancerIPs` за искане на конкретен IP адрес.
- [Docker, „Docker Engine 28: hardening container networking by default“](https://www.docker.com/blog/docker-engine-28-hardening-container-networking-by-default/) и [„Port publishing and mapping“](https://docs.docker.com/engine/network/port-publishing/): защо друга машина от твоята мрежа не достига мрежата на контейнерите.
- [Kubernetes, „kubectl wait“](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): изчакване на условие в `Status` на един или няколко ресурса; опцията `--for`.
- [Kubernetes, „Server-Side Apply“](https://kubernetes.io/docs/reference/using-api/server-side-apply/): контролната равнина води запис кои полета управлява всеки; сравнението с анотацията `last-applied-configuration`.
- [kind, „LoadBalancer“](https://kind.sigs.k8s.io/docs/user/loadbalancer/): Cloud Provider KIND като самостоятелен двоичен файл на твоята машина, с привилегии да отваря портове и да говори с *runtime* на контейнерите.
- [kind, „Ingress“](https://kind.sigs.k8s.io/docs/user/ingress/): нативната поддръжка на Ingress и Gateway API в Cloud Provider KIND.
- [Cloud Provider KIND, README](https://github.com/kubernetes-sigs/cloud-provider-kind): наблюдава всички клъстери на kind; контролерът му за Gateway API е включен по подразбиране.
- [MetalLB, „Installation“](https://metallb.io/installation/): манифестът `metallb-native.yaml` на v0.16.1; `controller` и `speaker`; компонентите, неподвижни, докато не се конфигурират.
- [MetalLB, „Configuration“](https://metallb.io/configuration/): `IPAddressPool`, `L2Advertisement` и тяхната асоциация; слой 2, който отговаря на ARP.
- [Envoy Gateway, „Install with Kubernetes YAML“](https://gateway.envoyproxy.io/docs/install/install-yaml/): `kubectl apply --server-side` с `install.yaml` на v1.9.2; манифестът включва CRD на Gateway API и тези на Envoy Gateway.
- [Gateway API, „HTTPRoute“](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/): без `matches` префиксът `/` съвпада с всяка заявка; всеки `match` е независим.
- [Gateway API, спецификация v1.6](https://gateway-api.sigs.k8s.io/reference/api-spec/1.6/spec/): невалидните препратки на едно правило и задължителният код 500.
- [curl, „libcurl error codes“](https://curl.se/libcurl/c/libcurl-errors.html): кодовете 7 и 28.

---

**Следващ:** [Урок 7 — Изолиране: пространства, права и мрежа](07-aislar-permisos-red.md)
