# Урок 8 — Данни и задачи

Понеделник, 7:12 сутринта. В 9:00 има среща с доставчика на услугата за плащания, а шефката ти пише съобщение от един ред: „Трябва ми отчетът от петък в 6 следобед, онзи, който показа `prueba` недостъпна четиридесет минути. Той е доказателството за рекламацията“. Отваряш клъстера със спокойствието на човек, който знае, че `revisor` пази отчета си във файл, `/datos/reporte.json`. Поискваш Pod-овете и виждаш нещо, което не очакваш: и трите реплики са на по-малко от два дни. В събота, при поддръжката на разсъмване, някой е изпразнил възлите един по един, за да ги обнови (с `kubectl drain`, което изселва Pod-овете от един възел), и клъстерът е направил онова, което умее: изтрил е старите Pod-ове, а Deployment-ът е създал нови на други възли. Поискваш файла. Няма го. Търсиш в другите две реплики. И там го няма. А дори да го имаше, докато мислиш, осъзнаваш нещо по-лошо: `revisor` пази **последния** отчет и го записва върху предишния. Този от петък така или иначе щеше да се изгуби още с първата заявка в събота.

Часът е 7:20. Остават сто минути, за да намериш начин да кажеш „нямам го“, който да не звучи като „не го запазих“.

Това не е рядък случай на лош късмет. Така става, когато един контейнер се бърка със сейф. През 2017 г. екипът на GitLab публикува разказа за часовете, в които загуби продукционни данни и откри, че механизмите му за резервни копия не са работели тъкмо когато са били нужни: дневните копия са се провалили безшумно, хранилището, в което е трябвало да са, е било празно, моментните снимки на диска не са били включени на сървърите на базата данни, а репликата е била повредена. Докладът им (източниците го цитират, с връзка) е добро напомняне, че въпросът не е „имам ли резервно копие?“, а „изпробвал ли съм го?“. Този урок е по-скромен: той не изгражда резервни копия. Учи те на предишната половина, която почти всички откриват късно: **коя част от онова, което пише един Pod, оцелява след самия Pod и коя не**. С този отговор в ръка отчетът от петък престава да зависи от късмета: една планирана задача поисква отчета от `revisor` и го запазва, с датата в името, в том, който оцелява след Pod-овете (докато съществува заявката и възелът, на който живее дискът). Това вече не е ред, който се презаписва: това е файл с име и дата.

Урокът има две половини, които си трябват една на друга. Първата е **къде**: томове, които живеят по-дълго от Pod-овете. Втората е **кога**: задачи, които се изпълняват веднъж или на всеки пет минути, без никой да ги пуска. Заедно те разрешават сцената: една планирана задача иска от `revisor` отчета му на всеки пет минути и го запазва с датата в името, в том, който оцелява след Pod-овете.

**Време:** 2 × 45 мин

**Какво изграждаш:** запазения отчет и `revisor` като планирана задача: един траен том, наречен `reportes`, една задача (`Job`), която иска от `revisor` отчета му с токена и го записва с датата в името, и един `CronJob`, който я повтаря на всеки пет минути, със сервизен акаунт без права и без монтирани удостоверения

**Какво научаваш:** какво оцелява и какво не, когато един контейнер падне и когато един Pod бъде изтрит (`emptyDir`); `PersistentVolume`, `PersistentVolumeClaim` и `StorageClass` и класа за съхранение на kind; защо заявката изчаква първия си Pod; `Job` и `CronJob` с повторните им опити, графика и историята им; собственика на файловете с `fsGroup`; какво се губи, когато се изтрие заявката; и един поискан размер, който клъстерът не налага

**Откъде идваш.** От Урок 7: `revisor` и тестовата услуга живеят в собствено пространство от имена, `revisor`, което изисква нивото `restricted` на Pod Security Admission; всяко натоварване има свой сервизен акаунт без монтирани удостоверения; а мрежата е затворена по подразбиране, с наименувани отваряния: в `revisor` влизат само Pod-овете с етикет `acceso-revisor: permitido` и Envoy-тата на входната точка. От [Урок 4](04-configuracion-secretos.md) — токена като `Secret`, монтиран като файл, и имената с *хеш*, които слага Kustomize. От [Урок 5](05-salud-recursos-apagado.md) — `requests` и `limits` във всеки контейнер; днес ги носят и задачите. И от [Урок 6](06-entrar-al-cluster.md) — платформата (MetalLB и Envoy Gateway), която този урок инсталира наново, когато създава своя клъстер, защото изходната точка включва Gateway-а.

**Какво не прави този урок.** Не поставя отчета на `revisor` вътре в трайния том: Упражнение 2 ти позволява да опиташ и да видиш защо курсът не го прави (връзва всички реплики към един-единствен възел). Не инсталира система за мрежово съхранение, не учи `StatefulSet` и не прави моментни снимки или резервни копия на том: назовава ги в края на „Навикът за сигурност“, с по едно изречение за проблема, който решава всяко от тях. Нищо не мащабира (това е [Урок 9](09-escalar-y-actualizar.md), който тръгва от онова, което оставяш тук) и не оценява целия проект срещу истински клъстер ([Урок 10](10-proyecto-final.md)).

**За изпълненията.** Всички изходи от този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1 и образа на възела `kindest/node:v1.37.0`, фиксиран чрез отпечатъка му, в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l8`. Машината беше Mac с процесор ARM и Docker Engine във виртуална машина с Linux (Colima), **не** Linux Mint, който е референтната система на курса. **Изпълнението използва собствена мрежа на Docker**, `curso-k8s-red-l8`, с подмрежата `172.28.0.0/16`, защото машината беше споделена и в същия момент се изпълняваха други уроци с MetalLB: два клъстера със същия диапазон от IP адреси в една и съща мрежа си пречат. Затова адресите на Gateway-а излизат тук като `172.28.255.x`. **На твоята машина, с обикновената мрежа `kind`, която Docker създава при стартирането на първия клъстер, IP адресите излизат като `172.18.255.x`** (диапазонът в `infra/metallb-pool.yaml` е `172.18.255.200-172.18.255.220`) и не е нужно да създаваш никаква мрежа. Това предполага, че твоята мрежа `kind` има подмрежа `172.18.0.0/16`; провери го преди това с `docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'` и, ако е друга, нагоди диапазона във файла. Другото, което се променя при твоя Mint: архитектурата (`amd64` вместо `arm64`), случайните наставки в имената на Pod-овете и на Job-овете, възрастите, на кой възел попада всяка реплика, *uid* на всеки Pod, часът и имената на томовете (`pvc-` и идентификатор). Командите са същите. Пълният преход е в [`programas/08-datos-y-tareas/`](../programas/08-datos-y-tareas): `correr.sh` създава клъстера, инсталира му платформата, оставя всичко така, както го остави Урок 7, преминава през урока по ред, изпълнява Упражнения 1 до 3 и изтрива клъстера; изходът му е `correr.salida.txt`. Пълното изпълнение отне 19 минути и 17 секунди (трите опита с `concurrencyPolicy` от Упражнение 3 събират около осем минути изчаквания): създаването на клъстера и изчакването да е готов отне 42 секунди, инсталирането на платформата отне 175 (скриптът не засича времето на всяка стъпка, така че не знам кое от изчакванията е било дългото), а изтриването на клъстера — 4. Тези времена варират много според натоварването на машината: при друго изпълнение на същия скрипт, със заета машина, инсталирането на платформата отне 678 секунди, а `kubectl wait` на Envoy Gateway стигна да изчерпи срока си от 300 секунди, въпреки че Gateway-ът накрая заработи. Дългите изчаквания в урока (да гледаш как минава графикът на един `CronJob`, да гледаш как един `Job` изчерпва повторните си опити) са написани открито: скриптът отпечатва на колко секунди гледа и какво вижда, не ги крие. Не използва никой порт от твоята машина.

## Като приключиш, ще можеш да

- Показваш с изпълнението какво оцелява и какво не в един `emptyDir`: рестартирането на контейнера — да, изтриването на Pod-а — не.
- Обясняваш със свои думи какво са `PersistentVolume`, `PersistentVolumeClaim` и `StorageClass` и защо заявката на курса остава в `Pending`, докато не се появи първият Pod, който я ползва.
- Четеш състоянието на една заявка за том, на нейния том и на реалната директория, която го подкрепя на възела.
- Пишеш `Job`, казваш колко пъти повтаря опита и с какви изчаквания, и четеш `BackoffLimitExceeded`.
- Пишеш `CronJob`, четеш графика му от пет полета и обясняваш `concurrencyPolicy`, историята на задачите и защо една планирана задача трябва да може да се изпълни два пъти, без да повреди нищо.
- Предизвикваш и отстраняваш `Permission denied` в том с `fsGroup` и казваш в кой от томовете на урока `fsGroup` промени групата и в кой не, и защо не можеш да го приемеш за даденост.
- Казваш какво става с данните, когато се изтрие една заявка за том, според политиката за възстановяване, и защо изтриването може да остане в `Terminating`.

## Защо, преди как

Досега всичко, което `revisor` записва, живее на място, което клъстерът третира като за еднократна употреба. Видя го мимоходом в Урок 2, когато Deployment-ът монтира `emptyDir` в `/datos`, за да не пречи файловата система само за четене да се запази отчетът, и оттогава го ползваш, без да се питаш колко трае. Първият въпрос на урока е този: **колко трае онова, което пише един Pod?** Отговорът има две стъпала, защото Pod не е същото като контейнер: контейнерът може да падне и да се върне (`kubelet` го рестартира), а Pod-ът може да бъде изтрит и заменен с друг, с друго име, на друг възел. Онова, което оцелява при първото, не е задължително да оцелее при второто, и ние го измерваме.

Вторият въпрос е **как се запазва нещо истински?** Kubernetes разделя две роли, които в Docker бяха заедно. Който администрира клъстера, решава какво съхранение съществува (дискове, папки, мрежови услуги); който разгръща приложение, решава колко му трябва и от какъв тип. Мостът между двамата са три обекта с подобни имена и различни задачи, които този урок представя един по един, преди да ги използва.

Третият е **как се прави нещо, което не е услуга?** Един Deployment поддържа процеси, които не бива да свършват. Да поискаш отчета от `revisor` на всеки пет минути е обратното: процес, който стартира, върши едно нещо и приключва, а клъстерът трябва да го повтаря в точен час, без някой да си спомня за него. За това съществуват `Job` (да направиш нещо, докато излезе добре или докато се откажеш) и `CronJob` (да създаваш Job-ове по график).

И има четвърти въпрос, по-невзрачен, който решава дали горното работи: **кой е собственикът на онова, което се записва?** Том, който се ражда с един собственик и едно разрешение, и процес, който работи като друг потребител, са рецепта за `Permission denied`. `fsGroup`, редът от Урок 4, който остави неразказана цялата си история, се връща тук.

Урокът има осем части с понятия и после обичайните раздели:

1. **Клъстерът на урока и изходната му точка** (8.1).
2. **Какво се губи: `emptyDir` днес** (8.2).
3. **Томове, заявки и класове** (8.3).
4. **Заявката за том и нейното изчакване** (8.4).
5. **`Job`: задачата, която свършва** (8.5).
6. **`CronJob`: задачата с график** (8.6).
7. **Собственикът на файловете: `fsGroup`** (8.7).
8. **Изтриване на заявката: там вече се губи** (8.8).

Това е крайната цел. В края на 8.5 една задача, пусната ръчно, оставя файл с дата в името във том, който оцелява след своя Pod, а втора задача вижда файла на първата:

```text
$ kubectl logs -n revisor job/reporte-manual-2
total 8
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232446Z.json
-rw-r--r--    1 100      101             92 Oct 21 23:24 reporte-20261021T232451Z.json
```

## Ако нямаш образите от курса по Docker

Този урок ползва същите два образа като предишните: `curso-docker-revisor:1.6.0` и `curso-docker-prueba:1.0.0`. Провери, че ги имаш:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

За другия — същата команда с `curso-docker-prueba:1.0.0`. Ако ти липсва някой, [Урок 3](03-services-dns.md) казва как да изградиш всеки от тях от хранилището на курса по Docker. Задачите от този урок ползват освен това публичния образ на `curl`, който вече познаваш от `depurar`, фиксиран чрез отпечатъка му `sha256`; всеки възел го изтегля от интернет първия път.

## Понятията

### 8.1 Клъстерът на урока и изходната му точка

#### 8.1.1 Създаване на клъстера

Този урок използва собствен клъстер, `curso-k8s-l8`, с конфигурацията от три възела от Урок 1. Пътищата `programas/08-datos-y-tareas/…` в следващия блок предполагат, че си в корена на хранилището на курса. Преди да го създадеш, две предпазни мерки, които вече са навик: временен и собствен `kubeconfig`, за да не се чете и да не се докосва твоят `~/.kube/config`, и една функция, която проверява с кой клъстер говориш. Ще я наречем `ctx` и тя стои **пред всяка команда, която променя нещо**: ако контекстът не е този на урока, връща грешка и командата след нея не се изпълнява, защото е свързана с нея чрез `&&`.

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

(Изпълнението на този урок, поради казаното в „За изпълненията“, постави `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l8` пред `kind create cluster`, за да използва собствената си мрежа. Ти не се нуждаеш от това.)

`export` и функцията `ctx` живеят само в този терминал. Ако отвориш друг, повтаряш двата реда (`export KUBECONFIG=…` с пътя, който отпечата `echo`, и дефиницията на `ctx`), иначе `kubectl` ще говори с друг клъстер. Оттук нататък **всеки блок код, който променя нещо, започва с `ctx &&`**. В изходите, поставени по-долу, редът, който започва с `$`, е командата така, както я отпечата скриптът, без `ctx &&`: скриптът проверява контекста преди всеки `kubectl` сам, а ти го правиш с функцията.

Изходите на този раздел идват от изпълнението на `correr.sh`, което прави точно това, със собствената мрежа, обяснена в „За изпълненията“:

```text
$ kubectl config current-context
kind-curso-k8s-l8

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l8-control-plane   Ready    control-plane   27s   v1.37.0
curso-k8s-l8-worker          Ready    <none>          16s   v1.37.0
curso-k8s-l8-worker2         Ready    <none>          17s   v1.37.0
```

`kind load` отпечатва шест реда `not yet present on node …, loading...`, по два образа на три възела, както в предишните уроци.

#### 8.1.2 Платформата от Урок 6, отново

Изходната точка на този урок включва Gateway-а от Урок 6, а един Gateway се нуждае от новите типове (CRD) на Gateway API и от контролера на Envoy Gateway. Тъй като клъстерът е нов, трябва да се инсталират отново, в същия ред като в Урок 6: първо платформата, после изчакване, после нейната конфигурация. Редът има значение, защото CRD-тата и *webhook-овете* трябва да съществуват преди ресурсите, които ги ползват.

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

Изходът, с диапазона на собствената мрежа на изпълнението:

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

Две бележки за този изход. Бележката за `sed` важи само за изпълнението: заменя диапазона на файла (`172.18.255.200-220`) с този на собствената мрежа (`172.28.255.200-250`), преди да го приложи. На твоята машина, с обикновената мрежа `kind`, прилагаш файла както си е: `kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml`. И 175-те секунди са много за това (при по-натоварена машина стигнаха 678), а скриптът не засича времето на всяка стъпка: машината беше заета с други клъстери. При предишен опит на същия урок последният, който се обяви за готов, беше *speaker*-ът на MetalLB (по един Pod на възел, който обявява IP адресите в мрежата). Ако на твоята машина `rollout status` се бави, `kubectl get pods -n metallb-system` ти казва колко от трите *speaker*-а са готови.

#### 8.1.3 Изходната точка: Урок 7

Папката `programas/08-datos-y-tareas/punto-de-partida/` носи, без да е променена и една запетая, манифестите, с които завърши Урок 7: пространството от имена `revisor` с нивото `restricted`, сервизните акаунти, шестте мрежови политики, `revisor` и тестовата услуга с техните Service-и, Gateway-ът и `kustomization.yaml`. Както в предишните уроци, токенът не се версионира: генерира се при всяко изпълнение, с разрешение `0600`, и се копира в двете папки (тази на изходната точка и тази на урока), за да генерират двете **един и същ** Secret.

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

Името на `ConfigMap` е това от Урок 4, `revisor-config-t6cm6872fk`, защото списъкът с услуги не се промени; това на `Secret` се променя при всяко изпълнение, защото токенът е нов. Двата `rollout status` от предишния блок не отпечатват нищо тук, защото скриптът ги изпълнява безшумно; в твоя терминал ще видиш `deployment "revisor" successfully rolled out` и еквивалента за `prueba`. Pod-ът `depurar` е обичайният, с една разлика, която вече познаваш от Урок 7: носи етикета `acceso-revisor: permitido` и затова затворената мрежа му позволява да говори с `revisor`.

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

Три реплики на `revisor`, тестовата услуга и `depurar`. И последният ред на `kubectl get`: няма томове, нито задачи, нито графици. Това е отвореният въпрос на урока. Последният изход е заявка, която идва от един контейнер на Docker извън клъстера, в същата мрежа като възлите, и стига по Gateway-а: входната точка от Урок 6 работи в пространството от имена от Урок 7 със затворената мрежа. Ако на твоята машина не отговаря, `kubectl get gateway -n revisor` казва кой IP е получил; при изпълнението беше `172.28.255.200`, а в твоята мрежа `kind` би бил `172.18.255.200`.

### 8.2 Какво се губи: `emptyDir` днес

#### 8.2.1 Къде е файлът

Първо, нека `revisor` запише отчета си. Всяка заявка към `/api/estados` съставя отчета и, преди да отговори, го запазва във файла, който казва променливата `REVISOR_REPORTE` на образа, `/datos/reporte.json`. Образът няма *shell*, така че не можеш да влезеш да видиш файла; но файлът съществува на някакъв диск, а възлите на kind са контейнери на Docker, в които можеш да влезеш. Иска се един отчет и се търси:

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

(В първата команда токенът се вижда като `…`: скриптът го скрива в онова, което отпечатва, а ти го подаваш с `$TOKEN`, както в предишните уроци.) `uid` е уникалният идентификатор, който клъстерът дава на всеки Pod, и е името на папката, в която `kubelet` на възела пази своето. Томовете на един Pod живеят в `/var/lib/kubelet/pods/<uid>/volumes/`, а тези от тип `emptyDir` — в подпапката `kubernetes.io~empty-dir`. Гледа се тази на всяка от трите реплики, на възела, където работи:

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

В тези три изхода има три находки и трите са важни за онова, което следва.

**Първата: само една от трите реплики има файла.** Заявката към `http://revisor/` беше разпределена от Service-а към една от трите и именно тя запази отчета. Другите две имат празен `/datos`. Всяка реплика има **свой собствен** `emptyDir`: между Pod-овете нищо не се споделя. Ако попиташ „`revisor`“ кой е бил последният му отчет, отговорът би зависел от това коя реплика ти отговаря. Само по себе си това вече дисквалифицира `emptyDir` като място за история.

**Втората: собственикът на директорията.** Първата колона на `ls -l` е `drwxrwsrwx`: директорията има разрешение за четене, писане и влизане за всички и `s` вместо `x` на мястото на групата, което е *setgid*. Собственик е потребител `0` (`root`), а групата е `65532`. Тази група не е случайна: тя е `fsGroup: 65532`, който Урок 4 постави в Deployment-а. За да не се приписва на `fsGroup` повече, отколкото върши: отвореното разрешение `777` е стойността по подразбиране на един `emptyDir` според документацията за томовете; онова, което слага `fsGroup`, е групата `65532` и битът *setgid*. 8.7 разказва какво направи `fsGroup` тук и какво не прави в други томове.

**Третата: файлът е на потребителя на `revisor`.** `-rw------- 1 65532 65532 92`: собственикът и групата са 65532, потребителят, с който работи `revisor`, а разрешението `0600` (само собственикът) идва от начина, по който `revisor` го създава: първо записва временен файл в същата папка и после го преименува, така че който го чете, да вижда стария или новия отчет, но никога половин. И 92 байта: отчет само на една услуга.

С `root` на възела може да се прочете онова, което `revisor` е запазил:

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

`stat` превежда разрешението в осмична форма: `2777` е `777` за четене и писане за всички плюс `2` на *setgid*. Това е същата информация като `s`, в друга форма. Съдържанието е отчетът в JSON: името на услугата, дали е наред, HTTP кодът и времето в милисекунди.

(Изходите на този раздел предполагат, че знаеш как да влезеш във възел с `docker exec`; това е същото, което направи в Урок 4 със `Secret` и в Урок 5 с `crictl`. Работи, защото в kind възлите са контейнери. В истински клъстер папката съществува също, но възелът е машина, в която влизаш с друг механизъм и с други права.)

#### 8.2.2 Контейнер, който пада: `emptyDir` оцелява

Документацията за томовете на Kubernetes ([връзка в източниците](#fuentes)) казва за `emptyDir`: томът се създава „когато Pod-ът бъде зададен на един възел“; започва празен; и „когато един Pod бъде премахнат от възел по каквато и да е причина, данните в `emptyDir` се изтриват завинаги“. И добавя една бележка, която изглежда малка, а е половината от урока: „един контейнер, който падне, **не** премахва Pod-а от възела. Данните в един том `emptyDir` са в безопасност при падане на контейнери“.

Проверява се. С `crictl`, инструмента от Урок 5, се спира контейнерът на `revisor`, който има файла. Идентификаторът на контейнера се търси по `uid` на Pod-а, за да не се спре чужд:

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

Чете се по ред. `RESTARTS 1 (10s ago)`: `kubelet` видя контейнера да умира и го рестартира преди 10 секунди; Pod-ът си е същият (същото име, същият `uid`, `AGE` 65 секунди). Последното прекратяване беше `Error` с код `137`, същият като в Урок 5: 128 плюс сигнал 9, който не може да се игнорира. И последният изход е важният: **файлът е непокътнат**, със същия час (`23:24`) и същите 92 байта. Новият контейнер монтира същия том и намери отчета там, където го остави старият.

Това има практическо следствие, което трябва да се каже ясно: ако приложението ти падне и се рестартира само, онова, което е запазило в един `emptyDir`, новият контейнер го намира. Това е употребата, която предлага документацията: работно пространство, контролни точки на едно дълго изчисление, за да го подновиш след падане. Не е място за онова, което трябва да оцелее след Pod-а.

#### 8.2.3 Pod, който се изтрива: `emptyDir` си отива с него

Второто стъпало. Изтрива се целият Pod, не само контейнерът му, и се гледа папката на тома:

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

Папката на тома вече не съществува: `No such file or directory`, с изходен код 2. `kubelet` изтри тома, когато премахна Pod-а. Вторият изход е нюанс, който трябва да се чете внимателно: папката на Pod-а още показва четири записа (`containers`, `etc-hosts`, `plugins` и `volumes`) няколко секунди след изтриването. Не проучих защо (вероятно е почистване на `kubelet`, което още не е било приключило); онова, което е важно за урока, вече се случи: папката на тома с данните не съществува. А ReplicaSet-ът възстанови репликата: `4mnvh` е нова (друго име, друг `uid`) и този път попадна на същия възел, `curso-k8s-l8-worker2`; планировчикът разпределя, но не обещава друг възел. Новият `revisor` стартира с празен `/datos`.

С това петъкът следобед от сцената е обяснен с две измервания. Рестартиране на контейнера се понася. Поддръжката в събота не рестартира контейнери: изсели Pod-ове и всеки нов Pod се роди с нов `emptyDir`, на възел, който може би не е бил същият. (Обикновено рестартиране на възела е друго нещо: документацията за жизнения цикъл на Pod-а разграничава този случай, в който Pod-ът не се изселва и `kubelet` стартира отново контейнерите му, от изселването или загубата на възела. Pod-овете се заменят, когато някой ги изтрие, възелът се изпразни или се обяви за изгубен.) За да оцелее една стойност след Pod-а, ти трябва том, който **не зависи от Pod-а**: за това е следващото.

### 8.3 Томове, заявки и класове

#### 8.3.1 Три обекта, три роли

Преди да ги използваш, трите обекта с пример от всекидневието. Представи си офис сграда. **Офис пространствата** съществуват: някой ги е построил, имат размер и местоположение. **Заявката за наем** казва „трябва ми офис от толкова квадратни метра, за да работи в него една-единствена фирма“; не казва кой. А **типът офис** (с гледка, без гледка, в мазето) описва как се строят и колко струват. В Kubernetes:

| В сградата | В Kubernetes | Кой го създава | Какво казва |
|---|---|---|---|
| офис пространството | `PersistentVolume` (PV) | администраторът на клъстера или системата, при поискване | „съществува съхранение с този размер, на това място, с тези правила“ |
| заявката за наем | `PersistentVolumeClaim` (PVC) | който разгръща приложението | „трябва ми този размер, с този режим на достъп“ |
| типът офис | `StorageClass` | администраторът на клъстера | „така се създава том от този клас“ |

[Документацията за трайните томове](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) определя първите два с тези думи: един PersistentVolume е „част от съхранението в клъстера, която е била осигурена от администратор или осигурена динамично чрез класове за съхранение. Той е ресурс на клъстера, също като възела“. А една PersistentVolumeClaim „е заявка за съхранение от страна на потребител. Подобна е на един Pod“. Аналогията с Pod-а отива по-далеч, отколкото изглежда: както един Pod консумира ресурси на един възел, така една заявка консумира ресурси на един том; и както един Pod може да поиска CPU и памет, така една заявка иска размер и режим на достъп.

Едно уточнение за имената, което обърква новодошлия: PV **няма пространство от имена** (той е на клъстера, като възела; в изхода на `kubectl api-resources --namespaced=false` се появява до `nodes` и `namespaces`), а PVC **има** (живее в `revisor`, до Pod-овете, които я ползват).

```text
$ kubectl api-resources --api-group='' --namespaced=false -o name | grep -E '^(persistentvolumes|nodes|namespaces)$'
namespaces
nodes
persistentvolumes
```

#### 8.3.2 Двата пътя към един том

Същата страница описва два начина една заявка да намери своя том:

- **Статичен.** „Администраторът на клъстера създава определен брой PV.“ PV-тата вече съществуват и една заявка, която съвпада с някое (по размер, по режим на достъп, по клас), се свързва с него. Така е с дисковете, които някой е подготвил ръчно.
- **Динамичен.** „Когато никое от статичните PV, създадени от администратора, не съвпада със заявката на потребителя, клъстерът може да се опита да осигури динамично том за нея.“ Никой не създава PV: създава го една програма на клъстера, *осигурителят* (provisioner), въз основа на класа, който е поискала заявката.

И процедурата, която документацията нарича жизнен цикъл: първо осигуряването; после свързването (*binding*): „един цикъл за управление на контролната равнина следи новите PVC, намира PV, което съвпада (ако може), и ги свързва“; после употребата: „щом потребителят има заявка и тя е свързана, свързаното PV му принадлежи, докато му е нужно“; и накрая възстановяването (reclaim), когато потребителят вече не се нуждае от него. Запиши си едно изречение от тази страница, защото ще го видиш изпълнено: „заявките остават несвързани безкрайно, ако не съществува том, който да съвпада“. Също и свързването е едно към едно: едно PV с една заявка и една заявка с едно PV.

Курсът използва и двата пътя, всеки там, където учи на нещо. Динамичният е нормалният път и е този, който ползва отчетът в урока. Статичният ще го ползваш в 8.7, за да изработиш диск с правилата на истински.

#### 8.3.3 Класът на kind

Този клъстер вече носи един клас. Пита се:

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

Клас с четири данни, които имат значение:

- **`standard (default)`** е името му, а скобите казват, че е **класът по подразбиране**: документацията за класовете казва, че когато една заявка не задава `storageClassName`, „се използва класът по подразбиране“. Курсът го назовава въпреки това в манифеста си, защото манифест, който казва какво ползва, се чете, без да зависи от настройка на клъстера.
- **`rancher.io/local-path`** е осигурителят. В пространството от имена `local-path-storage` има един Pod, `local-path-provisioner`, който следи заявките на този клас и им създава тома. Документацията на проекта го описва така: „предлага начин потребителите на Kubernetes да използват локалното съхранение на всеки възел“, а томът, който създава, е по подразбиране папка на възела, от тип `hostPath`. Две изречения от същия README, които ще използваме по-нататък, запиши ги: не поддържа ограничение на капацитета („капацитетът засега се игнорира“) и папката се създава с разрешение `0777`.
- **`Delete`** е **политиката за възстановяване** (reclaim policy) на томовете от този клас: какво се прави с тома, когато се изтрие заявката, която го е ползвала. Документацията за трайните томове го казва така: при `Delete` изтриването премахва както обекта PV на Kubernetes, така и свързаното съхранение. Алтернативата е `Retain`, която запазва тома, за да го възстанови администратор ръчно. 8.8 го измерва и с двете.
- **`WaitForFirstConsumer`** е **режимът на свързване** и е най-важната стойност, за да се разбере следващото. Документацията за класовете го обяснява по контраст. С режима `Immediate`, който се ползва, ако не зададеш нищо, „свързването на томовете и динамичното осигуряване стават веднага щом се създаде заявката“. Това може да излезе зле, когато съхранението е вързано за място (възел, зона), защото томът би се създал, без да се знае къде ще работи Pod-ът. Лекарството: режимът `WaitForFirstConsumer` „ще забави свързването и осигуряването на един PersistentVolume, докато не бъде създаден Pod, който използва PersistentVolumeClaim“. Първо се решава къде ще работи Pod-ът; после се създава томът **на това място**.
- **`ALLOWVOLUMEEXPANSION false`** (и празно в `jsonpath`, защото полето не е записано в класа): класът не позволява уголемяване на том след създаването му. Тук няма да ти трябва; ако някой ден един том се напълни, тази колона решава дали изходът е да го уголемиш, или да създадеш друг, по-голям, и да преместиш данните.

И краят на изхода: **`No resources found`** в `kubectl get pv`. Още няма никакъв том. Класът съществува, осигурителят чака и томовете се създават, когато някой ги поиска и има Pod, който да ги ползва.

### 8.4 Заявката за том и нейното изчакване

#### 8.4.1 Манифестът

Урокът добавя един файл към проекта, `reporte.yaml`, с три обекта: сервизния акаунт `reporte`, заявката `reportes` и `CronJob`-а `reporte`. Първите два се четат сега; третият има собствен раздел, 8.6, защото първо трябва да знаеш какво е един Job. Целият файл е **програма**: `programas/08-datos-y-tareas/reporte.yaml`, а `kustomization.yaml` на урока го добавя към списъка си с ресурси.

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

(Третата част, `CronJob`-ът, е цялостна в 8.6; тук е отрязана, за да се прочете първо заявката.) Сервизният акаунт е навикът от Урок 7: собствен акаунт за задачата, без права и с `automountServiceAccountToken: false`, защото задачата говори с `revisor`, а не с API-то на клъстера. Заявката има четири реда, които са важни:

- **`accessModes: [ReadWriteOnce]`** е **режимът на достъп**. Съкращава се RWO и документацията го определя така: „томът може да се монтира за четене и писане от **един-единствен възел**“. Последната дума е тази, която се разбира погрешно: това е един възел, не един Pod. Същата страница уточнява, че RWO „все още може да позволи на няколко Pod-а да достъпват (четат или пишат) тома, когато Pod-овете работят на един и същ възел“. Запомни го, защото Упражнение 2 го използва. Съществуват и други режими (`ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod`); с класа на kind приложимият е този: таблицата на същата страница отбелязва, че един том `HostPath` поддържа само `ReadWriteOnce`, а папката живее на един възел.
- **`storageClassName: standard`** назовава класа. Да напишеш името, макар да е класът по подразбиране, оставя манифеста без изненади в клъстер, където класът по подразбиране е друг.
- **`storage: 100Mi`** е поисканият размер: 100 мебибайта, същата единица за памет като в Урок 5. В чиста аритметика 100 Mi стигат за над един милион отчета от 92 байта. В една истинска файлова система всеки файл заема поне един блок (проверих на машината на Docker от изпълнението, че файл от 92 байта заема 8 блока от по 512, тоест 4096 байта, с блокове на файловата система от 4096), така че в 100 Mi се побират около 25 600 файла, а с 288 отчета на ден (един на всеки пет минути) това са около 89 дни история, преди да се наложи да се почиства. По-нататък ще има какво да се каже за това колко сериозно един клъстер приема това число.
- **Няма `volumeName`**: заявката не назовава никакъв том. Иска клас и размер, а системата ще разреши останалото.

Преди да приложиш, въпросът, който Урок 5 научи да задаваш: какво би се променило.

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

`diff` филтрира само онова, което се добавя (редовете, които започват с `+ `), и от тях тези, които назовават новото на урока: политиката за паралелност, графика, размера и класа. Скриптът отпечатва `[código de salida: 1]`, защото се изпълнява с `pipefail` и запазва 1-цата на `kubectl diff` (има разлики, както в Урок 5); в твоя терминал тръбата връща кода на `grep` и ще видиш 0. (Редът със `schedulerName` го добавя клъстерът като стойност по подразбиране; `grep` го хвана, защото съдържа думата `schedule`.)

#### 8.4.2 Прилагане и четене на `Pending`

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

Deployment-ите не се промениха (`unchanged`): нито една реплика не се рестартира. Новото са три обекта, `serviceaccount/reporte`, `persistentvolumeclaim/reportes` и `cronjob.batch/reporte`. (Това, че `gateway` и `httproute` казват `configured`, се появява в този `apply` и не променя нищо видимо в услугата; урокът не го проучва.) А сега онова, което е важно:

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

`STATUS Pending`, `VOLUME` празен, `CAPACITY` празен. На който идва от предишните уроци, `Pending` му звучи като проблем (Pod-ът от Урок 5, който не се побираше в нито един възел). Тук **не е**, и събитието го казва с всички букви: `waiting for first consumer to be created before binding`, „чака се да бъде създаден първият потребител, преди да се свърже“. Това е режимът `WaitForFirstConsumer` от 8.3.3 в действие. Още няма никакъв Pod, който да ползва заявката, така че клъстерът не е решил на кой възел ще работи каквото и да е и затова не може да реши на кой възел да създаде папката. И `kubectl get pv` го потвърждава: няма том.

Разликата с `Pending` от Урок 5 е онази, която отделя една диагноза от друга. Тук събитието е от ниво `Normal`, излъчва го `persistentvolume-controller` и казва, че чака; там беше `Warning` на планировчика, който казваше, че няма къде. Правилото за четене на всеки `Pending` е същото както винаги: събитията казват кой чака и какво. Един `Pending` с `WaitForFirstConsumer` и без никакъв Pod, който да ползва заявката, е система, която работи.

`CronJob`-ът междувременно съществува и не е работил: `LAST SCHEDULE <none>`, `ACTIVE 0`. Първото му изпълнение ще дойде на следващото кратно на пет минути по часовника. За да не чакаш, 8.5 учи как да поискаш едно ръчно.

### 8.5 `Job`: задачата, която свършва

#### 8.5.1 Най-малкият, който върши работа

Един **`Job`** е, с думите на документацията му, задача, която се изпълнява „докато приключи и после спира“. Създава един или повече Pod-ове и опитва отново „докато определен брой от тях завършат успешно“. Когато този брой се достигне, Job-ът е завършен. Важното в сравнение с Deployment-а е какво се счита за успех: един Pod на Job, който завършва с код 0, **е** очакваният резултат; в един Deployment същият този Pod би бил повреда и клъстерът би го заменил.

Преди истинския Job, един за упражнение: `fig08_01.job-salud.yaml`, който веднъж пита `/salud` на `revisor` и свършва. Той е **програма**.

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

Прочети го отгоре надолу; почти всичко разпознаваш. `apiVersion: batch/v1` и `kind: Job`: групата `batch` обединява Job-овете и CronJob-овете. `namespace: revisor` е написан във файла, за да попадне Job-ът там, без да се налага да си спомняш за `-n`. `spec.template` е шаблонът на Pod-а, както в един Deployment, но с две разлики. Първата: **няма селектор**, защото Job-ът го задава сам (документацията предупреждава, че „в почти всички случаи не бива да го задаваш“). Втората: `restartPolicy` е задължителен и допуска само две стойности, `Never` и `OnFailure`. При `Never`, ако контейнерът се провали, Pod-ът остава като `Failed` и Job-ът създава друг; при `OnFailure`, `kubelet` рестартира контейнера в същия Pod. Курсът ползва `Never`: всеки опит е отделен Pod, със свой дневник и свой изходен код, и можеш да прочетеш какво е станало във всеки. При `OnFailure` опитите се натрупват в един Pod.

Двете полета на Job-а, които не са на Pod-а:

- **`backoffLimit: 2`**: колко пъти да опита отново, преди да се откаже. Документацията казва, че стойността по подразбиране е 6 и че провалените Pod-ове се пресъздават „с експоненциално изчакване (10 s, 20 s, 40 s…) с таван от десет минути“. Тук 2 означава: първоначалният опит плюс два повторни, най-много три Pod-а.
- **`activeDeadlineSeconds: 120`**: таван на времето за целия Job, **независимо колко Pod-а създаде**. Когато изтече, клъстерът прекратява Pod-овете, които работят, и Job-ът минава в `Failed` с причина `DeadlineExceeded`. И документацията уточнява, че този срок има предимство пред `backoffLimit`: един Job, който повтаря опитите, не създава повече Pod-ове, когато срокът настъпи, дори да не е изчерпал опитите си. Двата тавана покриват различни повреди: единият е за „проваля се бързо много пъти“, другият — за „увисва“.

Самата задача, `curl -fsS -m 5 http://revisor/salud`, се чете по букви. `-f` кара curl да излезе с грешка, когато сървърът отговори 400 или повече (без тази буква един 503 би излязъл с код 0 и Job-ът би го отчел като успех). `-sS` е тих, но показва грешките. `-m 5` е максималното време на цялата операция: 5 секунди. А командата е написана като списък (`["curl", ...]`), а не като текст за един *shell*, защото образът на `curl` не се нуждае от такъв за това.

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

Job-ът отне 4 секунди и завърши с `COMPLETIONS 1/1`. Pod-ът остана като `Completed` с `READY 0/1`: не е грешка. Контейнерът завърши добре и вече не работи, а Pod-ът се пази, за да можеш да прочетеш дневника му. `kubectl logs job/salud` намира Pod-а на Job-а и показва онова, което е отпечатал `curl`: JSON-а на `/salud`. Условията на Job-а са две: `SuccessCriteriaMet` (критерият за успех е изпълнен) и `Complete` (завършен). Че са две, а не едно, е свързано с нещо, което казва документацията: от версия 1.31 контролерът на Job-овете забавя крайното условие (`Complete` или `Failed`), докато всички Pod-ове на Job-а не са приключили. `SuccessCriteriaMet` (и неговата близначка `FailureTarget`, която ще видиш в „Грешката, която ще видиш“) са условията, които се появяват преди това: казват, че изходът вече е решен.

Изтрива се, за да остане пространството както е било:

```text
$ kubectl delete -f fig08_01.job-salud.yaml
job.batch "salud" deleted from revisor namespace
```

Документацията го казва: изтриването на един Job почиства Pod-овете, които е създал. Това има значение в 8.8, където изтриването на Job-овете става част от маневрата.

#### 8.5.2 Запазеният отчет: първата задача

Сега Job-ът на урока. Не се пише отделно: `CronJob`-ът `reporte` вече го носи вътре, като шаблон, а `kubectl` умее да създаде Job от него по всяко време, без да чака графика. Това е начинът да изпробваш една планирана задача, без да се взираш в часовника:

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

Ето я, за три секунди, историята, която 8.3.3 обяви. Pod-ът на задачата съществува и е `Pending`, но обърни внимание на колоната `NOMINATED NODE`: планировчикът вече **номинира** един възел, `curso-k8s-l8-worker`, макар Pod-ът още да не е зададен (колоната `NODE` все още е `<none>`). С режима `WaitForFirstConsumer` планировчикът първо решава къде ще работи Pod-ът; документацията за класовете го казва така: томът се избира или осигурява „според топологията, която задават ограниченията за планиране на Pod-а“. С това решение взето, осигурителят на класа може да действа. Събитията на заявката разказват какво е станало, отгоре надолу (колоната `Age` намалява: 7 s, 3 s, 3 s): заявката чакаше потребител (`WaitForFirstConsumer`); появи се Pod-ът и контролерът го изясни пред осигурителя (`ExternalProvisioning`, което значи „външен осигурител трябва да създаде тома“); осигурителят `rancher.io/local-path` започна (`Provisioning`). Снимката е направена на 3-тата секунда и затова свършва дотук; следващото събитие, `ProvisioningSucceeded`, с името на създадения том (тук `pvc-5fcf36b8-…`), идва миг по-късно (при друго изпълнение на същия скрипт успя да излезе в снимката). Затова „външен“: осигурителят е отделна програма, един Pod на клъстера, не част от контролната равнина.

Редът отгоре, `Used By: reporte-manual-1-t7d8l`, е новост на тази версия: казва кой Pod ползва заявката. До него `kubectl describe` може да покаже таблица `Conditions` с условието `Unused`, а тук трябва да сме точни за онова, което е измерено: в този изход таблицата **не се появи**: контролерът за защита още не беше записал условието (снимката е направена на 3-тата секунда). Обърни внимание, че `Used By:` вече изброява Pod-а, макар да е `Pending`: за това условие един Pod се брои за потребител, докато не е приключил, дори преди да го зададат на възел; при друго изпълнение на същия скрипт, на 3-тата секунда, излезе условие `Unused False` с причина `PodUsingPVC` („един Pod ползва заявката“). Тоест условието се появява според мига, в който гледаш, и не можеш да разчиташ да го видиш. Внимание към обхвата му: документацията определя `Unused` само с Pod-ове, които не са приключили (един Pod във фаза `Succeeded` или `Failed` не се брои), докато защитата срещу изтриване от 8.8 брои всеки обект Pod, който ползва заявката. Един `Completed` Pod не държи `Unused` на `False`, но може да държи заявката в `Terminating`. Списъкът с промени на Kubernetes v1.37 го обяснява: функцията `PersistentVolumeClaimUnusedSinceTime` мина в бета и е включена по подразбиране, а заявките „отчитат условието `Unused`, което показва колко време една заявка не е ползвана, за да помогне да се определят кандидатите за почистване“. Полезна следа е в стар клъстер: заявките с `Unused True` от месеци са кандидати за преглед (може още да имат приключили Pod-ове, които ги държат защитени).

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

Дневникът на задачата е `ls -ln`, който тя сама отпечатва след запазването: един файл, `reporte-20261021T232446Z.json`, с датата в името (година, месец, ден, `T`, час, минута, секунда, `Z` от UTC). Това е отговорът на половината от сцената: нищо не се презаписва. Собственик `100`, група `101`: тези на потребителя на задачата, този на образа на `curl`.

Заявката вече е `Bound` (свързана), с тома `pvc-5fcf36b8-…`, 100Mi, RWO, клас `standard`. А томът, погледнат с колоните, които са важни, има две стойности, които заслужават обяснение:

- **`NODO curso-k8s-l8-worker`**: томът има **афинитет към възел**. Вързан е за един-единствен възел, този, който е избрал планировчикът. Това го прави **локален** том: данните му са на диска на онази машина и всеки Pod, който го ползва, трябва да работи там. Ако този възел се изгуби, данните си отиват с него.
- **`RUTA /var/local-path-provisioner/pvc-…_revisor_reportes`**: реалната папка, на възела. Името следва шаблона `<том>_<пространство от имена>_<заявка>` и е мястото, където можеш да отидеш да погледнеш.

```text
$ docker exec curso-k8s-l8-worker stat -c '%a %u:%g %n' /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
777 0:0 /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes

$ docker exec curso-k8s-l8-worker ls -lan /var/local-path-provisioner/pvc-5fcf36b8-f096-44c7-abdb-a86d1e815804_revisor_reportes
total 12
drwxrwxrwx 2   0   0 4096 Oct 21 23:24 .
drwxr-xr-x 3   0   0 4096 Oct 21 23:24 ..
-rw-r--r-- 1 100 101   92 Oct 21 23:24 reporte-20261021T232446Z.json
```

Директорията има разрешение `777` и собственик `0:0` (`root`). Сравни я с тази на `emptyDir` от 8.2.1: там беше `2777` и групата `65532`. Тук няма *setgid*, нито група на задачата. **Въпреки че Pod-ът на задачата декларира `fsGroup: 101`, директорията на този том не смени собственика си.** Това е контрастът с втората находка от 8.2.1 и 8.7 го развива: онова, което е измерено тук, е че `fsGroup` не направи нищо видимо в този тип том. Разрешението `777` идва от осигурителя, който според README-то си създава папката с `mkdir -m 0777`. Затова задачата можа да пише: не заради групата си, а защото папката пуска всекиго.

#### 8.5.3 Pod-ът приключи; файлът си е там

Доказателството за тома е да оцелее след Pod-а, който го е напълнил. Pod-ът на първата задача вече приключи. Пуска се втора задача, нов Pod, с друго име, който няма нищо общо с първия, освен че монтира същата заявка:

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

Вторият Pod вижда **два** файла: своя, от `23:24:51`, и този на първата задача, от `23:24:46`, от един Pod, който вече не работи. Това е, което не можеше да направи `emptyDir`. Заявката и томът, който я подкрепя, имат жизнен цикъл, независим от този на Pod-овете. Докато заявката съществува и дискът на възела, който пази папката, е цял, данните се запазват, макар Pod-овете, които са ги записали, да са приключили.

Съдържанието се потвърждава с възела. Първата команда е отчетът във формат таблица, който вече познаваш (само потвърждава, че `revisor` отговаря както преди); втората чете файловете, които са оставили задачите, и те пазят онова, което е отговорил `/api/estados` във всеки момент:

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

(`head -9` отрязва изхода до девет реда: първия файл цял и началото на втория.) Сцената от понеделника е разрешена по форма: отчетът от петък в 6 следобед, часа на Мексико Сити, би бил файл `reporte-20261017T0000…Z.json` (18:00 в Мексико са 00:00 UTC в събота, а секундите почти никога не са `00`, защото Pod-ът стартира няколко секунди след графика), един измежду десетки, нито един презаписан от следващия.

Преди да продължим, два въпроса, които този дизайн оставя и на които урокът отговаря на мястото им. Първо: ако `CronJob`-ът го прави на всеки пет минути, кой го кара да работи? Това е 8.6. Второ: ако задачата запазва файл и `revisor` също запазва `reporte.json` в своя `emptyDir`, защо `revisor` не запазва направо в тома? Решението на курса е, че не, а Упражнение 2 ти позволява да провериш защо.

### 8.6 `CronJob`: задачата с график

#### 8.6.1 Обектът, поле по поле

Един **`CronJob`** създава Job-ове по повтарящ се график. [Документацията](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) го сравнява с нещо, което може би вече познаваш: „един обект CronJob е като ред от файл *crontab* (таблица на cron) на една Unix система. Изпълнява периодично един Job по зададен график, написан във формат Cron“. Следва третата част на `reporte.yaml`, тази, която беше отрязана в 8.4.1:

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

Това е новото, отгоре надолу:

**`schedule: "*/5 * * * *"`** е графикът, във формата на cron с пет полета. Според документацията, отляво надясно, са: минута (0 до 59), час (0 до 23), ден от месеца (1 до 31), месец (1 до 12) и ден от седмицата (0 до 6, от неделя до събота). Звездичката означава „всеки“, а `*/5` означава „на всеки пет“: `*/5 * * * *` е „на всеки пет минути, в който и да е час, който и да е ден“. Примерите от документацията помагат да четеш други: `0 3 * * 1` е „понеделник в 3 сутринта“. А съкращенията `@hourly`, `@daily`, `@weekly`, `@monthly` и `@yearly` съществуват като преки пътища. Упражнение 4 ти иска да напишеш два графика.

**В коя часова зона?** Документацията го казва ясно: за един CronJob без часова зона `kube-controller-manager` тълкува графика в своята местна зона, която в kind е UTC. Колоната `TIMEZONE` в изхода казваше `<none>`, което е точно това. Може да се зададе с `.spec.timeZone` (например `"America/Mexico_City"`); да сложиш `TZ=` или `CRON_TZ=` вътре в графика не се допуска и клъстерът го отхвърля с грешка при валидация, според документацията. В истински клъстер курсът препоръчва да пишеш зоната; тя е причина за повече от едно „защо се изпълни в 4 сутринта?“.

**`concurrencyPolicy: Forbid`**: какво да се прави, ако настъпи часът на ново изпълнение, а предишното още работи. Трите стойности, според документацията: `Allow` (стойността по подразбиране) оставя двете да работят едновременно; `Forbid` не допуска едновременни изпълнения и пропуска новото; `Replace` заменя това, което работи, с новото. За задачата с отчета `Forbid` е благоразумният избор: две задачи, които пишат в същия том едновременно, биха били по-сложни от необходимото. Упражнение 3 ти позволява да видиш и трите в действие.

**`successfulJobsHistoryLimit: 3` и `failedJobsHistoryLimit: 3`**: колко приключили Job-а да се пазят. Стойностите по подразбиране са 3 и 1, а стойност нула не пази нито един. Пазят се, защото са доказателството: без тях един провален Job би изчезнал със своя дневник и никой не би знаел защо. Ограничават се, защото без таван биха се натрупали (един Job на всеки 5 минути са 288 на ден).

**`jobTemplate`** е цял Job, този, който CronJob-ът създава всеки път. Вътре `backoffLimit: 2` и `activeDeadlineSeconds: 60` са тези от 8.5.1, със срок от една минута: ако задачата увисне, клъстерът я прекъсва, преди да се застъпи със следващата.

**Шаблонът на Pod-а** вече е познат: акаунтът `reporte`, без монтирани удостоверения; `securityContext` от Урок 7 (без `root`, потребител 100 и група 101 от образа на `curl`); ресурсите от Урок 5. Етикетът `acceso-revisor: permitido` е този, който отваря мрежата: без него Pod-ът не стига до `revisor`, и разделът „Грешката, която ще видиш“ го показва. Томът `datos` е заявката `reportes`. А томът `token` монтира `Secret` от Урок 4, като файл, с `defaultMode: 0440`.

Бележка за пътя `/secretos/token`: файлът се казва като **ключа** на Secret-а, а Урок 4 го генерира с `token=token.txt` в Kustomize. Ако някой ден сглобиш Secret-а ръчно с `kubectl create secret generic revisor-token --from-file=token.txt`, ключът ще бъде `token.txt`, а файлът — `/secretos/token.txt`; за да съвпадне, ползвай `--from-file=token=token.txt`.

Нещо, на което си струва да се спрем: `secretName` във файла казва `revisor-token`, без *хеша*, както в Deployment-а на `revisor`. Kustomize го пренаписва, когато сглобява резултата, **и в един CronJob също**. Проверява се:

```text
$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.schedule}{" "}{.spec.concurrencyPolicy}{" "}{.spec.successfulJobsHistoryLimit}{" "}{.spec.failedJobsHistoryLimit}{" "}{.spec.timeZone}{"\n"}'
*/5 * * * * Forbid 3 3

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.volumes[1].secret.secretName}{"\n"}'
revisor-token-hbc69k5m5c

$ kubectl get secret -n revisor -o name
secret/revisor-token-hbc69k5m5c
```

Полето `timeZone` излезе празно (графикът е в UTC). Името на Secret-а в шаблона на CronJob-а е генерираното, с неговия *хеш*: Kustomize намери препратката и я смени, както направи с Deployment-а. Това има значение за програмите на урока: примерите `fig08_NN`, които не минават през Kustomize (тези, които се прилагат с `kubectl apply -f`), не могат да се позовават на Secret-а с основното му име и затова никой не го монтира.

Самата задача е `sh -c` с две команди, свързани с `&&`: `curl` (с четири опции и един адрес) и `ls -ln /datos`. Чете се опция по опция, отляво надясно: `curl -fsS -m 20` (както в Job-а за упражнение, но с 20 секунди, защото съставянето на отчет пита услуги и може да отнеме повече); `-H "Authorization: Bearer $(cat /secretos/token)"` (заглавката с токена, който се чете от монтирания файл в момента на изпълнението и никога не се появява написан в манифеста); `-o /datos/reporte-$(date -u +%Y%m%dT%H%M%SZ).json` (записва отговора във файл, чието име носи UTC часа на този миг, с `date -u`); и `http://revisor/api/estados`, адресът на Service-а. Ако `curl` се провали, `&&` не му позволява да продължи и задачата излиза с кода на `curl`: Job-ът го отчита като повреда. Ако сработи, `ls -ln /datos` отпечатва списъка, което си видял в дневника на ръчните задачи.

Защо `curl` срещу API-то, а не задача, която изпълнява самия `revisor` веднъж и свършва? Защото `revisor` е HTTP сървър и няма режим „провери веднъж“. Това е решение на курса, не трик: предпочита се да се използва програмата така, както я предава курсът по Docker, без да се променя. Задачата е клиент на `revisor`, като всеки друг.

#### 8.6.2 Да гледаш как минава графикът

Истинският график е на пет минути. За да го видиш да работи, без да го чакаш, `fig08_03.cron-cada-minuto.yaml` е CronJob, който се изпълнява всяка минута (`* * * * *`) и пита `/salud`, което не иска токен. Той е **програма**; шаблонът му е този на Job-а за упражнение, а новото е заглавната част.

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

(Целият файл, с шаблона, е в папката с програмите.) Какво се променя спрямо `reporte`: графикът, по-кратка история и `backoffLimit: 0`, което значи „без повторни опити“: задача, която се изпълнява всяка минута, не се нуждае от повторен опит, защото следващата минута е повторният опит. Чакането е на показ: скриптът гледа на всеки 10 секунди колко Job-а е приключил CronJob-ът и спира, когато са два.

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

На 10-ата секунда след създаването вече имаше един приключил Job: CronJob-ът не изчака цяла минута, а следващата **минута по часовника** (`:25:00`), която настъпи 4 секунди след `23:24:56`. Един cron график не брои „на всеки 60 секунди, откакто ме създаде“: задейства се в мигове, които формулата му отбелязва по часовника. А на 70-ата секунда — вторият (скриптът гледа на всеки 10 секунди, а следващата минута настъпи на 64-ата).

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

Тук има много за четене и всичко е доказателство, че графикът работи:

- **`cronjob.batch/reporte` също се изпълни, сам.** `LAST SCHEDULE 67s` и нов Job, `reporte-29877085`, който никой не е създал: създаде го CronJob-ът в `23:25:00`, най-близкото кратно на пет минути, докато урокът чакаше друго. Истинската задача на проекта вече работи.
- **Имената на Job-овете.** `reporte-manual-1` го назова ти. `reporte-29877085` го назова CronJob-ът: неговото име, тире и число. Числото са **минутите, изминали от 1 януари 1970 г. (UTC)**, епохата на Unix: `29877085 × 60` секунди е `2026-10-21T23:25:00Z`, а `29877086` е следващата минута. Това е наблюдавана подробност, а не документирана, която служи да четеш списък с Job-ове с един поглед: две поредни числа са две минути една след друга. И оттук идва едно ограничение, което документацията наистина казва: името на един CronJob не бива да надвишава 52 знака, защото, според документацията, контролерът му добавя 11 знака, а името на един Job не може да надвишава 63 (при изпълнението се добавиха 9: тире и 8 цифри; документацията резервира повече от предпазливост).
- **CronJob-ът за всяка минута има два Job-а, `…085` и `…086`**, от поредни минути, и `LAST SCHEDULE 7s`: последният беше преди 7 секунди.

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

Погледни часовете в дневниците: `23:25:01` и `23:26:01`; излизат от онзи `date -u +%T`, който командата на `fig08_03` отпечатва преди `curl`. Job-ът беше планиран за `:00`, но Pod-ът започна да работи 1 секунда по-късно и в двата случая (при друго изпълнение на същия скрипт бяха 5 и 9: разстоянието се променя според натоварването). Между мига на графика и мига на изпълнението има разстояние: CronJob-ът създава Job-а, Job-ът създава Pod-а, планировчикът го задава и `kubelet` стартира контейнера. Анотацията `batch.kubernetes.io/cronjob-scheduled-timestamp`, която CronJob-ът записва във всеки Job от версия 1.32, пази **първоначалния** час на графика, във формат RFC 3339 (формата `2026-10-21T23:25:00Z`, който виждаш в колоната `PROGRAMADA`): служи да се знае кое изпълнение кое е, макар да са се забавили. Документацията го казва с предупреждение, което си струва да се прочете цялото: един CronJob създава един Job „приблизително веднъж за всеки миг от графика си“, и е приблизително, защото „има обстоятелства, при които биха могли да се създадат два Job-а или нито един. Kubernetes се опитва да избегне тези ситуации, но не ги избягва напълно. Затова Job-овете, които определяш, трябва да са **идемпотентни**“.

**Идемпотентен**, в строг смисъл, значи: да го изпълниш два пъти оставя света същия, както ако го изпълниш веднъж. Задачата с отчета **не е** строго идемпотентна: ако поради спънка се изпълни два пъти в същата минута, би оставила два файла, а не един. Онова, което е: **безопасна при повторения**. Тъй като часът в името носи секунди, две изпълнения пишат два различни файла и нито един не презаписва другия (ако два Pod-а се изпълнят в една и съща точна секунда, вторият би заменил първия с еквивалентен отчет, без да повреди нищо). Задача, която би увеличавала брояч или би изпращала имейл, нямаше да е безопасна така и би трябвало да се защити по друг начин, например с уникален ключ за всеки график. Това е основната причина имената да носят часа, а не пореден номер.

Изтрива се CronJob-ът за упражнение, а с него и неговите Job-ове и Pod-ове:

```text
$ kubectl delete -f fig08_03.cron-cada-minuto.yaml
cronjob.batch "salud-cada-minuto" deleted from revisor namespace

$ kubectl get jobs,pods -n revisor -l app=salud
No resources found in revisor namespace.
```

Още две неща, на които учи документацията на CronJob, макар този урок да не ги изпълнява. Първото: `.spec.suspend: true` спира следващите изпълнения, без да изтрива нищо; тези, които попадат, докато е спрян, се броят за пропуснати. Второто: `startingDeadlineSeconds` казва колко секунди след часа му Job-ът все още може да бъде създаден, а ако се надвиши, това изпълнение се пропуска. Без това поле един контролер, който е бил недостъпен няколко часа, може да остави много изчакващи изпълнения; документацията обяснява, че ако има над 100 пропуснати от последното, CronJob-ът отказва да стартира и записва грешка. В продукция, със задачи, които са важни, си струва да се зададе.

### 8.7 Собственикът на файловете: `fsGroup`

#### 8.7.1 Какво `fsGroup` промени и какво не

От Урок 4 Deployment-ът на `revisor` носи `fsGroup: 65532`, а CronJob-ът — `fsGroup: 101`. Време е за пълната история. [Ръководството за контекста на сигурност](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) я обяснява с пример. Един Pod с `fsGroup: 2000` прави така, че „всички процеси на контейнера да са също част от допълнителната група 2000“, и „собственик на тома `/data/demo` и на всеки файл, създаден в този том, ще бъде групата 2000“. Примерният му изход е директорията с група 2000 и разрешения `drwxrwsrwx`, същият шаблон, който вече видя. А в раздела за обсъждане: `fsGroup` важи за томовете, „които поддържат управление на собствениците“, които се променят така, че да са на групата, посочена от `fsGroup`, и да са записваеми от нея.

Тези две думи, **които поддържат**, са онова, което се измерва тук. Трите тома на урока, един до друг. Последната команда се нуждае от името на възела и от `uid` на една реплика **от твоя клъстер**, които са други; получават се така:

```bash
REV_POD="$(kubectl get pods -n revisor -l app=revisor -o jsonpath='{.items[0].metadata.name}')"
REV_NODE="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.spec.nodeName}')"
REV_UID="$(kubectl get pod -n revisor "$REV_POD" -o jsonpath='{.metadata.uid}')"
docker exec "$REV_NODE" stat -c '%a %u:%g %n' "/var/lib/kubelet/pods/$REV_UID/volumes/kubernetes.io~empty-dir/datos"
```

Изходът от изпълнението, с възела и `uid` на онази реплика:

```text
$ kubectl get pod -n revisor -l app=revisor -o jsonpath='{.items[0].spec.securityContext.fsGroup}{"\n"}'
65532

$ kubectl get cronjob reporte -n revisor -o jsonpath='{.spec.jobTemplate.spec.template.spec.securityContext}{"\n"}'
{"fsGroup":101,"runAsGroup":101,"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}}

$ docker exec curso-k8s-l8-worker2 stat -c '%a %u:%g %n' /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
2777 0:65532 /var/lib/kubelet/pods/d61911b6-d777-4c4c-a159-e2a782fc69d8/volumes/kubernetes.io~empty-dir/datos
```

Ето ги двата декларирани `fsGroup` (65532 в `revisor`, 101 в задачата). И `stat` на `emptyDir` на един действащ `revisor`: `2777` и група `65532`: **в `emptyDir` `fsGroup` смени групата и постави *setgid***. За разлика от това, томът на заявката `reportes` (8.5.2) имаше `777 0:0`, макар Pod-ът му да декларираше `fsGroup: 101`. Причината, както я разказа README-то на осигурителя и както потвърждава измерването: осигурителят създава обикновена папка на възела с разрешение `0777`, а измерването показва, че `kubelet` не е сменил групата ѝ (документацията казва само, че `fsGroup` действа върху томовете, „които поддържат управление на собствениците“, и не дава списъка; онова, което измерихме, е че в този том не го направи, а в `emptyDir` и в тома `local` от 8.7.2 — да. PV, което създава този осигурител, е от тип `hostPath`: колоната `RUTA` от 8.5.2 идва от `spec.hostPath.path`). Нито се наложи: със `777` всеки потребител пише.

Това не е недоглеждане на курса: това е разлика между класа `standard` на kind и един диск, който се ражда със собственик `root` и разрешение `755`, като този, който 8.7.2 изработва ръчно. Там контейнер, който работи като потребител 100, получава `Permission denied`, когато опита да пише, **освен ако** `fsGroup` не му даде групата на директорията. С класа `standard` на kind е малко вероятно да видиш тази грешка и това е точно опасността: манифест, който работи, защото папката е `777`, може да се провали в друг клъстер по същата причина, поради която съществува `fsGroup`. Манифест, който вече носи `fsGroup`, е по-близо до това да работи с такъв диск. Затова курсът го пише, макар тук да не личи.

#### 8.7.2 Диск като истинските

За да видиш `fsGroup` в действие, ти трябва том, който наистина го поддържа. Kubernetes има такъв подръка: типът `local`, папка на един възел, представена като диск (документацията го описва като „монтирано локално устройство за съхранение: диск, дял или директория“). За разлика от осигурителя на kind, тук **ти** си администраторът: създаваш папката на възела, създаваш PV-то, което я описва, и създаваш заявката, която го иска. Това е статичният път от 8.3.2. Ползва се като пример `fig08_04.disco-local.yaml`, **програма** с два обекта:

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

Новите полета на PV-то: **`capacity`** е размерът, който предлага; **`persistentVolumeReclaimPolicy: Retain`** е политиката за възстановяване, която 8.8 измерва; **`local.path`** е папката на възела; а **`nodeAffinity`** е задължителна в един том `local`: документацията казва „трябва да зададеш `nodeAffinity` на PersistentVolume, когато ползваш томове `local`. Планировчикът на Kubernetes използва този афинитет, за да задава Pod-овете на правилния възел“. Тук казва, че томът е на възела, чието име е `curso-k8s-l8-worker`. Класът `manual` не съществува като обект; това е само дума, която свързва двата обекта помежду им и пречи заявката да попадне в класа по подразбиране. Защо заявката не се проваля заради несъществуващ клас (както става в Упражнение 1) има обяснение: динамичното осигуряване се опитва само когато никой от съществуващите томове не съвпада със заявката, а тук PV-то съществуваше.

Папката на възела се подготвя първо, с права на `root` и режим `755`, както би я оставил току-що форматиран диск, и после се прилага файлът:

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

`stat` на възела казва `755 0:0`: на `root`, и само `root` може да пише. PV-то `disco-reportes` се ражда `Bound` (свързано) в същата секунда, в която съществува, с политика `Retain`, а заявката `disco` също излиза `Bound` в този изход. Внимание: мигът има значение. При други две изпълнения на същия скрипт снимката попадна преди свързването да приключи: веднъж със заявката още `Pending` и тома вече `Bound`, друг път с тома още `Available`. Свързването отнема част от секундата; ако в твоя терминал видиш `Pending`, повтори `get` и ще се завърши. Нямаше изчакване на първия потребител: класът `manual` не е клас с отложен режим на свързване, а томът вече съществуваше. По-надолу томът `pvc-5fcf36b8-…` е този на `reportes`, с политиката `Delete` на своя клас. В истински клъстер не би оставил класа като свободен етикет: документацията иска да се създаде `StorageClass` за томовете `local` с `volumeBindingMode: WaitForFirstConsumer`, за да не се свърже заявката с диск на един възел, преди да се знае къде ще работи Pod-ът. Тук се пропуска, защото има само едно PV и афинитетът му решава възела.

Сега два Pod-а, които правят едно и също и се различават само по един ред. Пишат файл в `/datos`, работейки като потребител 100 и група 101, без `root`. Първият, `fig08_05.escritor-sin-fsgroup.yaml`, не декларира `fsGroup`:

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

Вторият, `fig08_06.escritor-con-fsgroup.yaml`, е същият файл с `name: con-fsgroup` и още един ред в `securityContext` на Pod-а: `fsGroup: 101`. Командата и на двата е кратка: `id` отпечатва кой е процесът; `ls -lnd /datos` отпечатва собственика и разрешението на монтираната директория; а `echo hola > /datos/a.txt && ls -ln /datos` се опитва да пише и, ако е успяло, изброява.

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

Това е грешката, която `fsGroup` избягва, измерена. Чете се в три реда: процесът е потребител 100, с група 101 и никоя друга; директорията е на `0:0` с `drwxr-xr-x` (пише само `root`: потребител 100 попада в категорията „други“, която има четене и влизане, но не и писане); и `sh` го казва без заобикалки, `can't create /datos/a.txt: Permission denied`. Pod-ът остана в `Error`: командата се провали и при `restartPolicy: Never` не се рестартира. Сега същият Pod с още един ред:

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

`Completed` и файлът `a.txt` от 5 байта (`hola` и нов ред) е записан. Погледни директорията в дневника: `drwxrwsr-x`, група `101`. А на възела `stat` казва `2775 0:101`: **`kubelet` смени групата на папката на 101 и даде разрешение за писане на тази група, със *setgid*, преди да стартира контейнера**. Процесът е от група 101 и затова може да пише. Собственикът си остава `root`; променила се е групата. Това е, което казва документацията: томовете, които поддържат управление на собствениците, „се променят така, че да са на GID, посочен от `fsGroup`, и да са записваеми от него“.

*Setgid* (буквата `s`) има практически ефект, заради който `fsGroup` си струва: файловете, създадени в директорията, **наследяват нейната група**, 101, а не първичната група на процеса, който ги създава. Тук ефектът не личи, защото процесът вече е от група 101 (`runAsGroup: 101`); би личал при процес с друга първична група. А за да може друг Pod от група 101 да *променя* тези файлове, всеки файл би се нуждаел от групово разрешение (umask 002), нещо, което тази задача не иска: файловете ѝ излизат `-rw-r--r--`.

Една бележка за цената, която документацията за контекста на сигурност обяснява: по подразбиране Kubernetes променя собственика и разрешенията на **цялото съдържание** на тома всеки път, когато се монтира. За том с милиони файлове това отнема време и забавя стартирането на Pod-а. Полето `fsGroupChangePolicy: OnRootMismatch` иска промяната да се прави само ако собственикът или разрешението на корена на тома не съвпадат с очакваното, и избягва да го обхожда, когато вече е наред. С томове от 100 Mi не личи; с големи дискове — личи.

#### 8.7.3 Retain: томът оцелява след заявката си

Двата Pod-а вече не са нужни. А дискът, направен ръчно, служи и за да се види онова, което не може да се види с `Delete`: политиката `Retain`. Изтрива се заявката:

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

Заявката я няма; томът **не**. Състоянието му е `Released` („освободен“), което документацията определя така: „заявката е изтрита, но свързаният ресурс за съхранение още не е бил възстановен от клъстера“. С `Retain` томът запазва своя `CLAIM revisor/disco` записан и не е достъпен за друга заявка, защото „данните на предишния заявител още са в тома“. Да го възстановиш е ръчна работа на администратора, в три стъпки, които казва документацията: да изтрие PV-то, да почисти данните в съхранението и да изтрие свързаното съхранение (или да го използва повторно с ново PV). Изтрива се PV-то и се гледа дискът:

```text
$ kubectl delete pv disco-reportes
persistentvolume "disco-reportes" deleted

$ docker exec curso-k8s-l8-worker ls -ln /mnt/disco-reportes
total 4
-rw-r--r-- 1 100 101 5 Oct 21 23:26 a.txt
```

Обектът PV изчезна от Kubernetes; папката на възела и файлът `a.txt`, който записа Pod-ът, си стоят там. Това е `Retain`: клъстерът пуска обекта и не докосва данните. Това е политиката, която се избира за данни, които не бива да изчезнат заради погрешен `kubectl delete`, срещу цената на ръчна работа по почистването. (Папката живее вътре в контейнера на възела, така че `kind delete cluster` я отнася със себе си. Ако искаш някакви данни да оцелеят след целия клъстер, [конфигурацията на kind](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts) позволява да монтираш папка от твоята машина във възел с `extraMounts`; курсът не го прави.)

### 8.8 Изтриване на заявката: там вече се губи

Политиката на класа `standard` е `Delete`. Измерва се какво става със заявката `reportes`, тази, която пази отчетите на урока. Първо се гледа политиката, после се иска изтриването **без изчакване** (`--wait=false`), защото следващото може да остане да чака:

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

`Terminating`: поискано е да се изтрие и не се изтрива. Командата върна управлението, защото имаше `--wait=false`; без тази опция `kubectl delete` би останал да чака. Обяснението е в `finalizers: ["kubernetes.io/pvc-protection"]`, което е *маркер*, който не позволява на обекта да изчезне, докато нещо не го махне. Документацията нарича тази функция **защита на обектите за съхранение, които са в употреба**, а целта ѝ е „да осигури, че заявките, които са в активна употреба от Pod, и томовете, свързани със заявки, не се премахват от системата, тъй като това би могло да доведе до загуба на данни“. И определя какво е „в активна употреба“: **една заявка е в употреба, когато съществува обект Pod, който я ползва.** Ако я изтриеш в този случай, „изтриването се отлага, докато никой не я ползва“.

Погледни последния изход: три Pod-а `Completed`. Приключили са отдавна и вече не работят, но **съществуват като обекти** (запазени са, за да се чете дневникът им), и всеки от тях декларира в томовете си заявката `reportes`. За защитата те продължават да я ползват. Заявката чака тези Pod-ове да спрат да съществуват. Изходът не е да се наложи изтриването, а да се махнат тези, които я държат: да се изтрият Job-овете, които отнасят своите Pod-ове.

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

Щом Pod-овете си отидоха, изтриването на заявката напредна: вече няма нито заявка, нито том (`No resources found`), а папката на възела, `pvc-5fcf36b8-…_revisor_reportes`, **изчезна заедно с всички свои отчети**. Директорията `/var/local-path-provisioner/` остана празна. Това е политиката `Delete` в действие: изтрива се заявката, изтрива се томът и се изтрива съхранението. При изтриването в изпълнението не се успя да се види междинното състояние `Released` на динамичния том (скриптът погледна 8 секунди след изтриването на Job-овете и дотогава томът вече не съществуваше; не знам за колко точно време изчезна); това от 8.7.3, с `Retain`, го показа.

Да създадеш наново заявката и да поискаш нова задача показва какво остава: нищо от миналото.

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

Един-единствен файл: днешният. Отчетите от миналото ги няма. С това правилото на раздела се събира в едно изречение за деня, когато някога го направиш неволно: **с политиката `Delete` данните живеят, докато живее заявката, и изтриването на заявката отнася данните; с `Retain` те оцеляват след нея и някой трябва да ги почисти** (8.7.3). Политиката е на класа, не на този, който изтрива: затова трябва да се знае кой е класът, преди да изтриеш каквото и да е, което се казва `pvc`.

## Грешката, която ще видиш

Този урок има две грешки нарочно. Втората вече я видя в 8.7.2: `Permission denied` на Pod, който пише в том на `root` без `fsGroup`. Първата е тази на задача, която никога не стига до `revisor`.

### BackoffLimitExceeded: Job, който не може да излезе

`fig08_02.job-sin-etiqueta.yaml` е Job-ът за упражнение от 8.5.1 с **една** разлика: липсва му етикетът `acceso-revisor: permitido`. Това е грешката, която се прави, когато копираш шаблон и забравиш ред, който не се вижда.

```bash
diff fig08_01.job-salud.yaml fig08_02.job-sin-etiqueta.yaml
ctx && kubectl apply -f fig08_02.job-sin-etiqueta.yaml
```

`diff` не го изпълнява скриптът (не докосва клъстера); това е неговият изход, изпълнен в папката с програмите. Освен коментарите в заглавната част и в името, единствената разлика в съдържанието е редът с етикета:

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

Един такъв Job не се проваля веднага. Опитва отново, с изчакванията, които 8.5.1 разказа, а урокът го гледа открито, на всеки 15 секунди:

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

**Първо, състоянието.** На 61-ата секунда Job-ът е `Failed` и има три Pod-а, и трите `Error`. Точно тези, които каза `backoffLimit: 2`: първоначалният и два повторни. Възрастите (`61s`, `44s`, `19s` от създаването, четени отзад напред) разказват нарастващото изчакване от документацията: вторият Pod се роди 17 секунди след първия (5 от `curl` плюс 10 изчакване), а третият — 25 след втория (5 плюс 20). Не са кръгли секунди, защото клъстерът добавя по малко при създаването на Pod-ове.

**Второ, дневникът, защото контейнерът наистина се изпълни.**

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

`kubectl logs job/…` предупреждава, че има три Pod-а и показва един. Съобщението на `curl` е онова, което познаваш от Урок 7: **код 28**, „връзката изтече“. Затворената мрежа не пуска Pod без етикета за достъп към `revisor` и не отговаря с отказ: просто не отговаря, а `curl` чака своите 5 секунди (`-m 5`) и се предава. И трите Pod-а завършиха с код 28. Това е същата повреда „отворена врата, през която не се влиза“ от Урок 7, гледана от една задача.

**Трето, Job-ът: защо се предаде.**

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

`BackoffLimitExceeded` („надхвърлен е лимитът на повторните опити“) е причината за повредата, точно както документацията изброява причините, поради които един Job се проваля: „броят на повредите на Pod-ове надхвърли `.spec.backoffLimit`“. Събитията, отгоре надолу, са историята в четири реда: три създавания и предаването.

**Четвърто, причината, която Job-ът не умее да каже.** Нищо от горното не казва *защо* `curl` изтича. Това го казва сравнението с онова, което работи. `depurar`, който в 8.1 говореше добре с `revisor`, носи етикет, който този Job няма:

```text
$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          3m36s   acceso-revisor=permitido,app=depurar
```

`acceso-revisor=permitido` е етикетът, който мрежовите политики от Урок 7 изискват. Job-ът на урока, истинският `CronJob`, го носи в шаблона си, с коментар, който го обяснява; този — не. **Поправката** е винаги една и съща: файлът е истината. Добавя се редът в манифеста и се прилага отново; тук просто се изтрива експериментът:

```text
$ kubectl delete -f fig08_02.job-sin-etiqueta.yaml
job.batch "salud-sin-etiqueta" deleted from revisor namespace
```

Два урока от тази грешка. **Първият**: един Job, който се проваля, казва, че се е провалил, не защо; причината е в дневника на неговите Pod-ове (`curl: (28)`) и в онова, което знаеш за мрежата. **Вторият**: една планирана задача, която се проваля в 3 сутринта, не буди никого. `CronJob`-ът пази последните три провалени Job-а (`failedJobsHistoryLimit: 3`) тъкмо за да може някой, на следващия ден, да отиде и да прочете какво им се е случило. Без наблюдение една задача, която се проваля безшумно седмици наред, създава обратното на онова, което обещава: усещането, че има резервно копие там, където го няма. Това е урокът от разказа за GitLab, с който започна урокът, в малък мащаб.

Редът при задача, която не е проработила: `kubectl get jobs` (`Failed`?); Pod-овете на Job-а (`kubectl get pods -l …`) и изходният код на всеки; дневникът (`kubectl logs job/…`); и, ако Job-ът не е създал нито един Pod, събитията на самия Job (`kubectl describe job`). Преди да промениш каквото и да е, да знаеш дали се е провалил веднъж, винаги или понякога.

## Навикът за сигурност от урока: данните със своя собственик

Таблицата с навици на курса възлага на този урок две неща: `ServiceAccount` без монтирани удостоверения, ако не се нуждае от тях, и данните със своя собственик. И двете се проверяват в клъстера.

**Сервизният акаунт на задачата.** Задачата говори с `revisor` по HTTP; не говори с API-то на клъстера. Не се нуждае от удостоверение за това и затова не ѝ се монтира:

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

`false` в акаунта, `false` в шаблона на CronJob-а и `env` празен (втората стойност на втория изход е нищо: задачата не получава променливи с тайни). Томовете на Pod-а на задачата са два и се казват `datos` и `token`: **нито един не е удостоверението за API-то**. Ако някой успее да изпълни код вътре в задачата, няма да намери токен на клъстера, който да открадне. А токенът на `revisor` е като файл само за четене с `0440`, не като променлива на средата: това е, което Урок 4 научи. Последният изход е доказателство, че `revisor` продължава да го изисква: без токен — `401`.

**Данните със своя собственик.** Трите измерени части:

- **Групата на тома я слага `fsGroup`**, не отворено разрешение. В истински диск решението на един `Permission denied` е да дадеш групата, а не `chmod 777`. В 8.7.2 томът беше на `root` с `755` и с един ред стана `2775 0:101`: на `root`, група 101, записваем само от тази група (и четим от всички).
- **Процесът работи без `root`** и файлът, който създава, е негов: `-rw-r--r-- 1 100 101` в задачата; `-rw------- 1 65532 65532` в `revisor`. Всеки пишещ оставя своя белег и може да се знае кой какво е записал.
- **Токенът не стига до тома с данни.** Задачата чете токена от `/secretos`, том само за четене, и пише само в `/datos`. Входът и изходът, държани отделно, не позволяват грешка на задачата да запише тайната на място, където се запазва.

**Размерът, който клъстерът не налага.** Остава една изненада, тази от раздел 8.4.1, където беше казано, че ще има какво да се каже за това колко сериозно един клъстер приема числото `100Mi`. Томът поиска 100 мебибайта и клъстерът каза `CAPACITY 100Mi`. Проверява се с един Job, `fig08_07.llenar-el-volumen.yaml`, който записва 150 милиона байта (около 143 MiB) в същия този том:

```bash
ctx && kubectl get pvc reportes -n revisor -o jsonpath='{.spec.resources.requests.storage} {.status.capacity.storage}{"\n"}'
ctx && kubectl apply -f fig08_07.llenar-el-volumen.yaml
ctx && kubectl wait -n revisor --for=condition=Complete job/llenar --timeout=180s
ctx && kubectl logs -n revisor job/llenar
ctx && kubectl delete -f fig08_07.llenar-el-volumen.yaml
```

(`wait` избягва да се иска дневникът, преди Pod-ът да е свършил да пише; скриптът го изпълнява, без да го отпечатва.)

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

Job-ът завърши без грешка и `ls` показва `grande.bin` от **150000000 байта** в том, който поиска и получи 100Mi. А `df` отвътре на Pod-а показва причината: „томът“ `/datos` се появява като `/dev/root`, от 57,1 GB, с 85 % използвани: това е дискът на възела, който в kind е този на машината на Docker, не парче от 100 Mi (името на устройството и размерът се променят на твоята машина). Точно това е, което README-то на осигурителя обяви („капацитетът засега се игнорира“): числото в `storage` решава с кое PV се свързва заявката, но класът на kind не ограничава онова, което се записва.

Това е находка от лабораторията, която не бива да се забравя: **с класа на kind онова, което искаш, не е онова, което получаваш; при други съхранения зависи от системата и трябва да се измери**. В истински клъстер истинското съхранение има размер и се пълни (с грешка `No space left on device`, която събаря приложението по средата на запис), а пространство от имена без квота може да създава заявки с какъвто и да е размер. Квотата за съхранение (`ResourceQuota`, с `requests.storage`) слага максимум на пространство от имена, както беше споменато в Урок 5 за CPU и паметта; курсът я назовава и не я инсталира.

**От какво защитава и от какво не.** Тези навици пазят задачата да няма повече власт, отколкото ѝ трябва, токенът да не изтече на диска и файловете да имат разпознаваем собственик. Не защитават данните: един `Delete` ги изтрива (8.8), един паднал възел ги прави недостъпни (томът е на един-единствен диск) и никой не прави резервни копия. Онова, което наистина пази данните, е редът, който Урок 10 поставя в списъка с това, което липсва за продукция: репликирано съхранение извън възела, моментни снимки на томове и резервни копия, които се **изпробват** с възстановяване. По едно изречение за всяко, за да знаеш какъв проблем решава: `StatefulSet` е обектът за приложения със състояние, чиито Pod-ове имат стабилна идентичност и собствен том всеки (курсът не го ползва); моментната снимка на том е копие на тома в един миг, което служи да се върнеш назад; а изпробваното резервно копие е копието, което някой вече е възстановил на друго място и е проверил, което е точно онова, което липсваше в разказа за GitLab от началото.

## Какво се прави погрешно

**Да запазваш в `emptyDir` онова, което трябва да оцелее след Pod-а.** Видя го в 8.2.3: контейнерът се спасява от падане, Pod-ът не се спасява от изтриване, а изпразването на възел (`drain`), изселване (eviction) или възел, обявен за изгубен, изтриват Pod-ове; рестартиране на възела не непременно, но и не си струва да се хазартира с това. Един `emptyDir` е за работно пространство, не за история.

**Да вярваш, че `Pending` на една заявка е грешка.** С `WaitForFirstConsumer` една заявка без Pod остава `Pending` правилно. Събитието се чете, преди да се действа.

**Да поставиш `storage: 100Mi` и да вярваш, че дотам свършва.** В kind размерът не се налага (измерва го „Навикът за сигурност“). В продукция дискът се пълни. Трябва да се следи използването, с аларми, преди да стигне тавана.

**Да изтриеш заявка (`pvc`), без да знаеш политиката на класа.** С `Delete` данните се изтриват. С `Retain` се запазват и някой трябва да ги почисти. Преди това се гледа `RECLAIMPOLICY`.

**Да изтриеш PV ръчно, за да „освободиш“ заяла заявка.** Заявката в `Terminating` чака Pod-овете, които я ползват; PV-то има своя собствена защита. Да насилваш финализаторите (`kubectl patch … finalizers`), заобикаляйки защитата, е начинът да повредиш данни в употреба. Намира се и се изтрива онова, което я държи (в този урок — Job-овете).

**Да ползваш `chmod 777` или отворен том, за да „почне да пише“.** Така прави осигурителят на kind и затова проблемът рядко си личи. В истински диск лекарството е `fsGroup` и потребител без `root`, не да отвориш директорията за всички.

**Да напишеш задача, която не понася да се изпълни два пъти.** Документацията предупреждава: CronJob-ът може да създаде два Job-а или нито един. Задача, която събира, изпраща или таксува без защита, е дубликат, който чака да се случи.

**Да оставиш `concurrencyPolicy: Allow` по подразбиране в задача, която пише в споделен том.** Две задачи едновременно в същата папка и една бавна задача, която се застъпва със следващата, могат да натрупат Pod-ове, без някой да го забележи. `Forbid` или `Replace` казват изрично какво искаш.

**Job без `backoffLimit` и `activeDeadlineSeconds`.** Стойността по подразбиране за повторните опити е 6, а времето няма таван: една увиснала задача си остава увиснала. Двете се задават в истинските задачи, с числа, които могат да се обосноват (Job-овете за упражнение в урока, които траят секунди, не ги носят всичките).

**CronJob без история или с огромна история.** Без история (`0`) няма доказателство за онова, което се е провалило. С много голямо число се трупат Job-ове и Pod-ове на хиляди. Избира се малко число и се преглежда.

**Да дадеш на задачата сервизен акаунт с права „за всеки случай“.** Задача, която говори само по HTTP, не се нуждае от удостоверение за API-то. `automountServiceAccountToken: false` и собствен акаунт без права.

**Да поставиш токена в командата или в променлива на средата на задачата.** Чете се от монтирания файл в момента на изпълнението, както прави задачата на урока.

**Да забравиш часовата зона на един CronJob.** Без `timeZone` графикът е този на контролера (UTC в kind). „Всеки ден в 3“ не е онова, което мислиш, ако си на шест часа от UTC.

**Да запазваш отчета на всички реплики в локален том `ReadWriteOnce`.** Упражнение 2 го доказва: връзва всички реплики към един-единствен възел.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред и от състоянието, в което остана след „навика за сигурност“. Преди всяко `ctx` трябва да ти връща успех (`ctx && echo ok`). **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще се случи. Четвъртото се пише със свои думи.

### Упражнение 1 — Клас за съхранение, който не съществува

`fig08_08.pvc-clase-inexistente.yaml` създава заявка за том, която иска класа `rapido` (който този клъстер няма), и един Pod, `lector`, който я ползва. Приложи го. Преди да погледнеш, предскажи: в какво състояние остава заявката? В кое — Pod-ът? Какво събитие мислиш, че дава всеки и кой го излъчва? Провери с `kubectl get pvc rapido -n revisor`, `kubectl get pod lector -n revisor` и `describe` на двата. И трудният въпрос: колко време би чакал, преди да заключиш, че няма да се разреши от само себе си? Като свършиш, изтрий го с `kubectl delete -f fig08_08.pvc-clase-inexistente.yaml`.

### Упражнение 2 — Отчетът на `revisor`, в тома

Решението на курса е `revisor` да запазва своя `reporte.json` в `emptyDir`, а задачата да запазва своите в тома. Провери го с промяна на един ред. С `kubectl patch` замени тома `datos` на Deployment-а на `revisor` (първия от списъка, `/spec/template/spec/volumes/0`) с такъв, който ползва заявката `reportes`:

```bash
ctx && kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"replace","path":"/spec/template/spec/volumes/0","value":{"name":"datos","persistentVolumeClaim":{"claimName":"reportes"}}}]'
```

Предскажи: стартират ли трите реплики? На кой възел попада всяка? Какво казва `kubectl get pv` за тома? Поискай отчет с `depurar` и потърси файла на възела. После отмени промяната с `kubectl apply -k .` (файлът е истината) и провери къде остават репликите. Обясни в пет изречения защо това не е онова, което искаш за проекта и какво се губи от онова, което Урок 9 ще поиска.

### Упражнение 3 — Задача, която трае повече от графика си

`fig08_09.cron-lento.yaml` е CronJob, който се изпълнява всяка минута (`* * * * *`) с `concurrencyPolicy: Forbid` и чиято задача трае **100 секунди** (`sleep 100`). Предскажи, преди да го приложиш: след 2 минути и половина колко Job-а ще работят едновременно? Ще се създадат ли тези от междинните минути? Какво събитие оставя CronJob-ът, когато пропусне един? Приложи го, гледай на всеки 35 секунди около 210 секунди (първата задача трае близо две минути и трябва да се види как свършва) с `kubectl get cronjob lento -n revisor` и `kubectl get jobs -n revisor` и прочети `kubectl describe cronjob lento -n revisor`. После изтрий CronJob-а (`ctx && kubectl delete -f fig08_09.cron-lento.yaml`), изчакай началото на една минута и го създай отново с променената политика, без да пипаш файла: `sed 's/concurrencyPolicy: Forbid/concurrencyPolicy: Allow/' fig08_09.cron-lento.yaml | kubectl apply -f -`; повтори с `Replace`. Така файлът остава непокътнат за изпълнението на `correr.sh`. Сравни: какво виждаш при всяка стойност? Като свършиш, изтрий го с `ctx && kubectl delete -f fig08_09.cron-lento.yaml`: ако го оставиш, продължава да създава по един Job на минута, а `kubectl diff -k .` не го засича, защото не е част от файловете на урока.

### Упражнение 4 — Два графика

В най-много пет изречения напиши своя отговор на следното. (а) Cron графикът на задача, която се изпълнява **в делничните дни в 7:30 сутринта, часа на Мексико Сити**, и кое поле от спецификацията на CronJob-а ти трябва освен графика. (б) Графикът на задача, която се изпълнява **на всеки два часа в точен час**. (в) Какво става с изпълнение, планирано за 3:00, ако контролерът на CronJob-овете е бил недостъпен от 2:50 до 3:20 и CronJob-ът има `startingDeadlineSeconds: 600`; и какво се променя, ако го няма. (г) Защо задачата с отчета може да се изпълни два пъти в една и съща минута, без да повреди нищо.

## Решения

### Решение 1

Измерено в `correr.salida.txt`:

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

**И двата са `Pending`, но по причини с различен собственик.** Заявката е такава, защото `persistentvolume-controller` търси класа `rapido`, не го намира и излъчва `Warning` с точната причина: `storageclass.storage.k8s.io "rapido" not found`. За разлика от `Pending` от 8.4, този е от ниво `Warning` и не казва „чака“: казва, че нещо не съществува. Pod-ът е такъв, защото планировчикът, който го вижда със заявка без връзка, отговаря `0/3 nodes are available: pod has unbound immediate PersistentVolumeClaims`: нито един възел не става, докато заявката не е свързана. (Съобщението завършва с един самотен `not found`, както го отпечата клъстерът от изпълнението; текстът на събитията се променя между версиите, а онова, което трябва да четеш, е причината в събитието на заявката.)

Четенето е обичайното: Pod-ът в `Pending` не е проблемът, а симптомът. Причината е един обект по-надолу, в заявката, и нейното събитие казва кой клас липсва. Поправката е да напишеш клас, който съществува (`kubectl get storageclass` дава списъка), или да създадеш този, който липсва. За колко да се чака: нищо от това не се решава само. Заявката без клас остава `Pending` „безкрайно“, както казва документацията за трайните томове за заявка без том, който да съвпада, докато някой не създаде класа; няма срок на изчакване, нито краен срив. Един `Pending` с `ProvisioningFailed` не е изчакване, а предупреждение.

### Решение 2

Измерено в `correr.salida.txt`:

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

**И трите реплики стартират и всички попадат на един и същ възел**: `curso-k8s-l8-worker`, този, който има тома. Планировчикът не можа да ги разпредели, защото PV има афинитет към възел (8.5.2): всеки Pod, който ползва заявката, трябва да работи там, където е дискът. А бяха и трите, защото този режим, `ReadWriteOnce`, е „един възел“, не „един Pod“: няколко Pod-а на един и същ възел могат да монтират тома едновременно. Документацията го казва и тук се видя. `reporte.json` на `revisor` се появява в същата папка като отчетите на задачата, до `grande.bin` (150-те MB от „навика за сигурност“, още там, защото томът е същият) и файла с дата на задача 3.

Отменя се с `kubectl apply -k .`: репликите се връщат към `emptyDir` и отново се разпределят на двата работни възела (`worker` и `worker2`). Какво би било лошо в проекта, в пет изречения: (1) всички реплики остават на един възел, защото томът е на един диск; (2) ако този възел падне, целият `revisor` остава без място, където да работи, защото Pod-овете не могат да отидат на друг възел със своя том; (3) трите реплики биха записвали **един и същ** `reporte.json`, презаписвайки се взаимно, което е по-лошо от преди; (4) разпределението на репликите по възли, от което Урок 9 се нуждае, за да мащабира и да обновява, измервайки всяко прекъсване, изчезва; (5) онова, от което отчетът се нуждае, е история с име и дата, а това вече го прави задачата.

### Решение 3

Измерено в `correr.salida.txt`. Първо `Forbid` (скриптът изчаква началото на една минута по часовника, преди да приложи всеки вариант, така че първата задача да попадне на следващото `:00`):

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

**С `Forbid` — само един Job наведнъж и междинните минути не се създават.** Първият Job, `lento-29877090`, се роди в `23:30:00` и отне 103 секунди (100 от `sleep` плюс това, което отнема стартирането и завършването). Докато работеше, настъпиха графиците от `23:31:00` и нищо не се създаде: CronJob-ът остави `ACTIVE 1` и продължи със същия. Когато Job-ът свърши, към `23:31:43`, CronJob-ът го видя (`SawCompletedJob`) и веднага създаде **друг**, `lento-29877091`. Обърни внимание на името на втория: `…091` е това от `23:31:00`, не това от `23:32:00`. Причината е в документацията: когато предишното изпълнение свърши, `startingDeadlineSeconds` (което тук не беше зададено и следователно няма таван) още се брои и изпълнението от `23:31:00`, което беше пропуснато, най-после се създава. (В `correr.salida.txt` има още една снимка, на 35-ата секунда след прилагането, която още няма никакъв Job: CronJob-ът беше създаден в `23:29:00` и първият му график беше този от `23:30:00`; затова `lento-29877090` е от следващата минута.)

Събитието, което оставят пропуснатите графици, е `JobAlreadyActive`, със съобщението `Not starting job because prior execution is running and concurrency policy is Forbid` („Job не се стартира, защото предишното изпълнение още работи и политиката за паралелност е Forbid“), а броячът `x4 over 92s` казва колко пъти се е случило за времето, в което си гледал. Документацията добавя едно следствие: изпълнение, пропуснато от `Forbid`, се брои за изгубено.

Сега същата задача с `Allow`, стойността по подразбиране, и после с `Replace`. И двете са измервания, не аритметика:

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

**С `Allow` два Job-а работят едновременно.** Първият (`lento-29877094`) започна в `23:34:00`; в `23:35:00` дойде вторият (`lento-29877095`), без да чака първият да свърши, и снимката показва `ACTIVE 2`, два Job-а `Running` и два Pod-а `Running` едновременно, с 81 и 21 секунди живот. Събитията са само `SuccessfulCreate`, по едно за всеки график: няма `JobAlreadyActive`, защото нищо не се пропуска. Тъй като задачата трае 100 секунди, а графикът е от 60, в установен режим винаги има между един и два активни (това последното идва от аритметиката; измереното е първото застъпване). При задача, която пише в споделен том, тези два Pod-а биха писали едновременно: затова 8.6 избира `Forbid` за отчета.

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

**С `Replace` текущият Job се изтрива и започва друг и нито един не стига до края.** Първият (`lento-29877097`) започна в `23:37:00`; в `23:38:00` CronJob-ът го **изтри** (`SuccessfulDelete`) и създаде `lento-29877098` на негово място. В последната снимка старият Pod е `Terminating`, а новият — `Running` с 21 секунди. Първият Job живя 60 секунди, по-малко от 100-те, които му трябват, и не стигна да свърши. Това е измерено веднъж (първата замяна); че следващите повтарят същото, идва от това, че графикът си остава от 60 секунди, а задачата — от 100. `Replace` е стойността за задачи, чийто последен резултат е единственият, който има значение, и които могат да се рестартират без вреда, и неправилната за такава, която се нуждае от пълните си 100 секунди.

Трите политики са отговор на „какво става, когато задачата е по-бавна от графика си“, а правилният отговор е онзи, който описва какво е нужно на твоята задача, не стойността по подразбиране.

### Решение 4

Един възможен отговор: „(а) `30 7 * * 1-5`, тоест минута 30, час 7, който и да е ден от месеца, който и да е месец, от понеделник (1) до петък (5); и освен това `timeZone: "America/Mexico_City"` в спецификацията, защото без него графикът се тълкува в зоната на контролера, UTC в kind, и задачата би се изпълнила в 1:30 през нощта. (б) `0 */2 * * *`: минута 0 на всеки втори час. (в) С `startingDeadlineSeconds: 600`, в 3:20 CronJob-ът вижда, че изпълнението от 3:00 е закъсняло с 1200 секунди, повече от срока от 600, и го пропуска, защото вече е твърде късно за него; с незададено поле няма срок и го създава веднага щом контролерът се върне, в 3:20, с 20 минути закъснение, освен ако не са се натрупали над 100 пропуснати изпълнения, в който случай отказва да започне. (г) Защото е безопасна при повторения: името на файла носи датата със секунди и всяко изпълнение пише различен файл, така че две изпълнения оставят два файла и нищо не се поврежда, нито губи (не е идемпотентна в строг смисъл: резултатът не е същият като с едно-единствено).“

## Изтриване на клъстера

Преди да изтриеш, крайното състояние. Първо се премахва Pod-ът `depurar`, който не е част от файловете на урока (`ctx && kubectl delete pod depurar -n revisor --wait=false`); затова в изхода по-долу в списъка с Pod-ове се появява `Terminating`. Ако веригата на урока е следвана по ред и експериментите са отменени, клъстерът трябва да бъде точно онова, което казват файловете. Това е `kubectl diff` от Урок 5, сега наобратно: без разлики, излиза с 0.

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

Заявката `reportes` е свързана, `CronJob`-ът `reporte` е планиран и вече се е изпълнил сам (Job-овете `reporte-29877090` и `reporte-29877095`, от `23:30` и `23:35`, ги създаде той), а входната точка на Gateway-а продължава да отговаря отвън. Това е състоянието, с което започва Урок 9. (Единственият Pod в `Terminating` е `depurar`, който беше изтрит точно преди тази проверка; Pod-овете `lento-…` от Упражнение 3 вече ги няма, защото скриптът изчака да изчезнат, преди да измерва.)

Когато приключиш, изтрий клъстера на урока. Не оставяй нищо живо на машината:

```text
$ kind delete cluster --name curso-k8s-l8
Deleting cluster "curso-k8s-l8" ...
Deleted nodes: ["curso-k8s-l8-worker2" "curso-k8s-l8-control-plane" "curso-k8s-l8-worker"]
(borrar tardó 4 s)

$ kind get clusters | grep -c curso-k8s-l8
0
```

(Реда в скоби го пише скриптът, който измерва изтриването.) `--name` е задължителен: без него kind би изтрил клъстера на име `kind`, който може да е на друг човек или на друг проект. С клъстера си отива папката `/mnt/disco-reportes` на възела и томовете, които са останали: всичко живееше вътре в контейнерите на възлите.

На твоята машина остават временната папка на `kubeconfig` и двата `token.txt`. Изтриват се така, от `programas/08-datos-y-tareas`:

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

`case` пуска само път, който започва с `/tmp/curso-k8s-l8.` и има нещо след него, точната форма на онзи, който създаде в 8.1.1. Ако `L8_TMP` е празна (например защото си в друг терминал, където никога не си я задавал) или има друга стойност, не изтрива нищо и ти казва защо. Това е същата защита, която ползва `correr.sh` при почистването: един `rm -rf`, който може да се копира и постави, трябва да се пази сам. Ако твоят `correr.sh` е използвал собствената мрежа от бележките за изпълнението, тази мрежа (`docker network rm curso-k8s-red-l8`) също я изтриваш ти, и само нея.

## Как разбирам, че съм успял

- [ ] Обясняваш, с измерването от 8.2, какво оцелява при падането на един контейнер и какво не оцелява при изтриването на един Pod, и защо.
- [ ] Разграничаваш `PersistentVolume`, `PersistentVolumeClaim` и `StorageClass` и казваш кой създава всеки от тях.
- [ ] Четеш `Pending` в една заявка с `WaitForFirstConsumer` и знаеш, че не е грешка, и четеш `ProvisioningFailed` при несъществуващ клас и знаеш, че е.
- [ ] Пишеш `Job` с `backoffLimit` и `activeDeadlineSeconds` и казваш колко Pod-а най-много създава и с какви изчаквания.
- [ ] Четеш cron график от пет полета и пишеш този за „на всеки пет минути“ и този за „от понеделник до петък в 7:30“.
- [ ] Казваш какво прави `Forbid` в сравнение с `Allow` и `Replace` и защо задачата с отчета трябва да може да се изпълни два пъти.
- [ ] Предизвикваш и отстраняваш `Permission denied` в том с `fsGroup` и казваш в кой том на урока `fsGroup` смени групата и в кой не.
- [ ] Казваш какво се губи при изтриване на заявка с политика `Delete` и какво при `Retain` и защо едно изтриване остава в `Terminating`.
- [ ] Изпълняваш `programas/08-datos-y-tareas/correr.sh > /tmp/mi-corrida-l8.txt 2>&1` и сравняваш `/tmp/mi-corrida-l8.txt` с `programas/08-datos-y-tareas/correr.salida.txt` (не пренасочвай към този файл: той е еталонът) в онова, което не се променя между изпълненията: три възела `Ready` във `v1.37.0`; шест реда `not yet present on node … loading...`; `-rw-------` в двата `token.txt`; в `emptyDir`, директорията `2777` с група `65532` и един-единствен `reporte.json` от около 92 байта в една от трите реплики (93, ако измереното време има две цифри); `RESTARTS 1` и `Error 137` след спирането на контейнера, с непокътнат файл; папката на тома, която вече не съществува след изтриването на Pod-а; класът `standard (default)` с `rancher.io/local-path`, `Delete` и `WaitForFirstConsumer`; `No resources found` в `kubectl get pv`; заявката `Pending` със събитието `waiting for first consumer to be created before binding`; Job-ът `salud` с `Complete` и `{"estado":"vivo","version":"1.6.0"}`; Pod-ът на задачата `Pending` с номиниран възел и събитието `Provisioning` (`ProvisioningSucceeded` идва миг по-късно и може да попадне или да не попадне в снимката); заявката `Bound`, `100Mi`, `RWO`, `standard`; томът, вързан за един възел, с пътя `/var/local-path-provisioner/pvc-…_revisor_reportes` и разрешение `777 0:0`; един файл `reporte-…Z.json` в първата задача и два във втората; Job-ове на CronJob с име `<cronjob>-<число>` от осем цифри и анотацията `cronjob-scheduled-timestamp` на `:00`; `Permission denied` и `755 0:0` без `fsGroup`, `Completed` и `2775 0:101` с него; `Released` с `Retain`; `Terminating` с финализатора `kubernetes.io/pvc-protection`, докато не се изтрият Job-овете; `BackoffLimitExceeded` с три Pod-а в `Error`, код `28`; `150000000` записани байта в том от `100Mi`; `ProvisioningFailed … "rapido" not found`; трите реплики на `revisor` на един-единствен възел; `JobAlreadyActive … concurrency policy is Forbid`; и `sin diferencias con los archivos`. IP адресите, наставките на имената, `uid`, възрастите, възелът, който получава тома, точните секунди, идентификаторът на всеки `pvc-…` и часът на файловете се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] Като приключиш, `kind get clusters` вече не показва `curso-k8s-l8`.

## Обобщение

Отговори, без да поглеждаш урока:

1. Какво оцелява при падането на един контейнер и какво не оцелява при изтриването на един Pod, в един `emptyDir`?
2. Каква роля има всеки от тези три обекта: `PersistentVolume`, `PersistentVolumeClaim`, `StorageClass`?
3. Защо заявката `reportes` остава в `Pending` при прилагането и кога престава да бъде?
4. Какво значи `ReadWriteOnce` и какво следствие има за това къде могат да работят Pod-овете, които ползват тома?
5. По какво си прилича и по какво се различава един `Job` от един Deployment?
6. Колко Pod-а най-много създава един Job с `backoffLimit: 2` и с какви изчаквания между тях?
7. Какво казват петте полета на `*/5 * * * *`? В коя часова зона се изпълняват, ако не зададеш `timeZone`?
8. Какво прави `concurrencyPolicy: Forbid` и какво събитие оставя?
9. Какво значи една задача да е идемпотентна и защо има значение в един CronJob?
10. Какво прави `fsGroup`, в кой том на урока промени нещо и в кой не?
11. Защо една заявка може да остане в `Terminating`? Как се решава, без да се насилва нищо?
12. Каква е разликата между `Delete` и `Retain`?

## Източници

Всички са прегледани на 21 октомври 2026 г.

- [Kubernetes, «Persistent Volumes»](https://kubernetes.io/docs/concepts/storage/persistent-volumes/): определенията на `PersistentVolume` и `PersistentVolumeClaim`; статичното и динамичното осигуряване; свързването едно към едно и че заявка без том, който да съвпада, чака безкрайно; защитата на обектите за съхранение в употреба и определението ѝ за „в употреба“; политиките за възстановяване `Retain` и `Delete`; фазите `Bound` и `Released`; режимите на достъп и определението на `ReadWriteOnce` (един възел, няколко Pod-а).
- [Kubernetes, «Storage Classes»](https://kubernetes.io/docs/concepts/storage/storage-classes/): какво е един клас; класът по подразбиране; политиката за възстановяване по подразбиране (`Delete`); режимът на свързване `Immediate` срещу `WaitForFirstConsumer`.
- [Kubernetes, «Volumes»](https://kubernetes.io/docs/concepts/storage/volumes/): `emptyDir` (създава се, когато Pod-ът се зададе на възел, изтрива се, когато Pod-ът бъде премахнат, оцелява при падане на контейнер, разрешението `0777` по подразбиране) и томът `local` (само статичен, задължителен `nodeAffinity`).
- [Kubernetes, «Jobs»](https://kubernetes.io/docs/concepts/workloads/controllers/job/): определението на Job; `restartPolicy` `Never` или `OnFailure`; `backoffLimit` (6 по подразбиране) и експоненциалното изчакване; `activeDeadlineSeconds` и предимството му; причините за повреда (`BackoffLimitExceeded`, `DeadlineExceeded`); крайните условия, забавени от 1.31; че една и съща програма може да стартира два пъти.
- [Kubernetes, «CronJob»](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/): cron форматът с пет полета; часовата зона и `.spec.timeZone`; `concurrencyPolicy`; ограниченията на историята (3 и 1 по подразбиране); `startingDeadlineSeconds` и таванът от 100 пропуснати изпълнения; `suspend`; името най-много от 52 знака; анотацията `cronjob-scheduled-timestamp` от 1.32; предупреждението, че Job-овете трябва да са идемпотентни.
- [Kubernetes, «Configure a Security Context for a Pod or Container»](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` и групата на тома; томовете, „които поддържат управление на собствениците“; `fsGroupChangePolicy`.
- [Kubernetes v1.37, списък с промени](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.37.md): условието `Unused` на заявките за том (`PersistentVolumeClaimUnusedSinceTime`, бета и включена от 1.37).
- [Local Path Provisioner (Rancher), README](https://github.com/rancher/local-path-provisioner): осигурителят, който ползва класът `standard` на kind; томът като папка `hostPath` на възела; че капацитетът се игнорира; разрешението `0777` на папката; изтриването на съдържанието, когато се изтрие томът.
- [kind, «Configuration»](https://kind.sigs.k8s.io/docs/user/configuration/#extra-mounts): допълнителните монтирания (`extraMounts`), начинът да предадеш съхранение от твоята машина на възел на kind, за да оцелеят данните отвъд контейнера на възела.
- [Kubernetes, «StatefulSets»](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/): стабилна мрежова идентичност и стабилно съхранение за всеки Pod (`volumeClaimTemplates`).
- [Kubernetes, «Volume Snapshots»](https://kubernetes.io/docs/concepts/storage/volume-snapshots/): моментните снимки на томове.
- [Kubernetes, «Resource Quotas»](https://kubernetes.io/docs/concepts/policy/resource-quotas/): `requests.storage`, максималната сума съхранение, което могат да поискат заявките на едно пространство от имена.
- [GitLab, «Postmortem of database outage of January 31»](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): публичният разказ, от февруари 2017 г., за загуба на продукционни данни и за механизми за резервни копия, които не работеха (дневно копие, което се проваляше безшумно, моментни снимки, които не бяха включени на сървърите на базата данни, повредена реплика): причината да се изпробват резервните копия, вместо да се предполага.

---

**Следващ:** [Урок 9 — Мащабиране и обновяване с измерване на всяко прекъсване](09-escalar-y-actualizar.md)
