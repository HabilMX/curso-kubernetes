# Урок 9 — Мащабиране и обновяване с измерване на всяко прекъсване

Понеделник, 8:57 сутринта. В 9:00 екипът по операции прави седмичното си приключване и четиридесет души ще отворят, почти едновременно, отчета на `revisor`. Миналия понеделник стана нещо подобно. В 9:01 таблото се забави; някой вдигна ръчно репликите от три на осем, „за да издържи“; и забрави да ги свали. В 9:04 друг човек приложи спешна поправка и за няколко секунди няколко потребители видяха грешка на екрана. Никой не знае колко. Днес директорът по операции задава три въпроса, а срещата започва след три минути: колко реплики наистина му трябват на услугата и кой решава кога са излишни? Колко заявки се губят при обновяване? И какво става, ако падне един от сървърите на клъстера? Отговорът ти отпреди седмица и на трите беше един и същ: „би трябвало да е наред“.

Тази фраза е проблемът. В Kubernetes „би трябвало да е наред“ може да се превърне в число, а този урок е работилницата, в която става това. Не е измислена история, за да те уплаши. През 2019 г. инженер на име Phil Pearl разказа в блога си, че при преместването на едно API в клъстер на Kubernetes в Google, зад Ingress, тестовете му от време на време получавали грешки `502`. Като потърсил причината, открил нещо, което почти никой не казвал по онова време: когато един Pod се спира, известието за спиране и изваждането на този Pod от списъка с получатели в мрежата стават **едновременно**, а не едно след друго; стъпката, която го изважда от списъка, не изчаква стъпката, която го спира. Различно е само колко време отнема новината да стигне до всеки балансьор: според Pearl при Ingress — много, при Service — малко. Заради тази надпревара (*race condition*) една заявка може да стигне до Pod, който вече се затваря ([Phil Pearl, „Kubernetes' dirty endpoint secret and Ingress“](https://philpearl.github.io/post/k8s_ingress/), 26 юли 2019 г.). Днес ще научиш как да измериш тази надпревара в собствения си клъстер, как да я затвориш с няколко реда и как да не вярваш на едно измерване повече, отколкото заслужава.

Този урок има три части. Първата учи клъстера да **мащабира сам**: измервател на потреблението (`metrics-server`), автоматичен скалиращ механизъм с формула, която ще можеш да пресметнеш на ръка, и правило за разпределение, за да не се трупат репликите в един възел. Втората учи да **обновяваш и изпразваш възли без изненади**: обновяване, измерено със собствено сондиране, със и без паузата, която затваря надпреварата, историята за връщане назад и бюджет за прекъсвания срещу поддръжката на един възел. Третата **чупи сървър нарочно** и измерва колко трае прекъсването. Всяка цифра, която ще видиш, е получена от изпълнението на процедурата и всяка цифра е придружена от онова, което я ограничава.

**Време:** 2 × 45 мин четене и практика; пълното изпълнение на скрипта отнема доста повече (казва се в „За изпълненията“), защото изчакванията са част от онова, което се учи

**Какво изграждаш:** `revisor`, който вдига и сваля реплики според натоварването, разпределен между двата работни възела, който се обновява със сондиране, броящо всяка изгубена заявка, и който оцелява при изключен възел със загуба, която е измерена и обяснена

**Какво научаваш:** защо `metrics-server` в чистия си вид не работи в kind и какво променя флагът, който го оправя; формулата на `HorizontalPodAutoscaler`, неговия толеранс от 10 % и прозореца, който забавя намаляването; защо един Deployment, управляван от автоматичен скалиращ механизъм, не носи `replicas`; разпределението между възли с `topologySpreadConstraints` и защо контролният възел изисква `nodeTaintsPolicy: Honor`; `RollingUpdate` с `maxSurge` и `maxUnavailable`; надпреварата между спирането и крайните точки на Service и `preStop`, който я затваря; `rollout history` и `rollout undo` и защо `rollout status` може да приключи, докато старите Pod-ове още отговарят; `PodDisruptionBudget` и един `drain`, който нарочно засяда; и прозореца на паднал възел — с онова, което го скъсява, и онова, което не го скъсява

**Откъде идваш.** От [Урок 8](08-datos-y-tareas.md): `revisor` живее в собствено пространство от имена, `revisor`, със затворената мрежа от [Урок 7](07-aislar-permisos-red.md), том за отчетите си и планирана задача. От [Урок 5](05-salud-recursos-apagado.md) носиш онова, което днес става изчисление: `requests` за CPU (`50m`), които са мерилото, с което автоматичният скалиращ механизъм измерва процента, и срока за спиране, който днес се прецизира с пауза преди сигнала за приключване. От [Урок 6](06-entrar-al-cluster.md) носиш платформата: MetalLB и Envoy Gateway, вече инсталирани, с реда „платформа, изчакване, проект“, който днес се повтаря в един скрипт. А от [Урок 3](03-services-dns.md) — Pod-а `depurar` и навика да гледаш `ENDPOINTS`, преди да обвиняваш когото и да е.

**Какво не прави този урок.** Не мащабира **възли**: в kind трите възела са фиксирани контейнери, а добавянето или махането на машини е работа на друг компонент, който истинският клъстер има, а тази лаборатория — не. Не мащабира вертикално (повече CPU за всяка реплика) и не мащабира със собствени метрики (заявки в секунда, размер на опашка). Не прави сини-зелени или канарчени (canary) обновявания: единствената стратегия тук е постепенната, която носи Kubernetes. Не слага криптиране. И не е сериозен тест на натоварването: натоварването в урока е Job с `curl` в цикъл, достатъчно, за да видиш как автоматичният скалиращ механизъм реагира, и нищо повече. [Урок 10](10-proyecto-final.md) събира всичко в две команди и изброява какво липсва на това, за да е готово за продукция.

**За изпълненията.** Всички изходи от този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1, образа на възела `kindest/node:v1.37.0`, фиксиран чрез отпечатъка му (Kubernetes v1.37.0), **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** и **`metrics-server` v0.9.0**, в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l9`. Машината беше Mac с процесор ARM и Docker Engine 29.2.1 във виртуална машина с Linux (Colima) с 6 CPU и 16 GiB памет, **не** Linux Mint, който е референтната система на курса. И беше **споделена**: докато работеше този урок, на същата машина работеха други уроци от курса със свои клъстери, а натоварването на системата (средната стойност, която показва `uptime`) мина от под 5 до над 40 по време на работата. Това има значение при четенето на два вида цифри: **времената** (тегленето на образите на MetalLB отне, при предишни опити, по няколко минути на възел, и `preparar.sh` има дълги изчаквания заради това) и **броя на заявките** в 9.9 и 9.12, които зависят от това колко CPU е получил клиентът на сондирането. Всеки раздел казва коя цифра от какво зависи. Какво се променя в твоя Mint: архитектурата (`amd64` вместо `arm64`), IP адресите на Pod-овете, на Service-ите и на възлите, наставките на имената, възрастите, възелът, в който попада всяка реплика, и най-вече цифрите за заявките: те са твои и не се сравняват с тукашните. Има и една разлика в мрежата, която си струва да се каже. **Изпълнението на този урок използва собствена мрежа на Docker**, `curso-k8s-red-l9`, с подмрежата `172.29.0.0/16`, за да може да работи едновременно с други уроци, които също инсталират MetalLB, без да си пречат; затова IP адресите на възлите излизат като `172.29.0.x`, а входната точка на Gateway — като `172.29.255.200`. На твоята машина, с обикновената мрежа `kind`, IP адресите излизат като `172.18.0.x`, а входната точка — като `172.18.255.200`, което е онова, което `preparar.sh` прави по подразбиране. `correr.sh` прави същото, ако го пуснеш с `RED=kind SUBRED=172.18.0.0/16` (това са стойностите му по подразбиране) и спира, преди да създаде каквото и да е, ако мрежата няма очакваната подмрежа. Пълната обиколка е в [`programas/09-escalar-y-actualizar/`](../programas/09-escalar-y-actualizar): `correr.sh` създава клъстера, зарежда в него трите образа, довежда го до състоянието от Урок 8 с `preparar.sh`, минава през урока по ред и го изтрива. Изходът му е `correr.salida.txt`. Пълното изпълнение отне 1809 секунди (30 минути и 9 секунди): създаването на клъстера и изчакването да е готов — 37 секунди; `preparar.sh` — 343; изтриването на клъстера — 2; останалото са изчакванията, които урокът учи да правиш (натоварването и намаляването на автоматичния скалиращ механизъм, седемте сондирания при обновяване, изключеният възел). Образът, който не съществува, от 9.10.4 се пуска отделно, с `fig09_02.imagen-rota.sh` (изходът му е `fig09_02.imagen-rota.salida.txt`), в собствен минимален клъстер, който отнема около четири минути. Изисква интернет: манифестите на `metrics-server`, MetalLB и Envoy Gateway се изтеглят от изданията им, фиксирани към версията им, а образите им се теглят първия път.

## След урока ще можеш да

- Обясняваш защо `metrics-server` не стартира в чистия си вид в kind, разчиташ `x509` от лога му, прилагаш флага, който го оправя, и казваш защо този флаг е само за лаборатория.
- Пресмяташ на ръка колко реплики ще поиска един `HorizontalPodAutoscaler` от текущите реплики, измерения процент CPU и целта, като прилагаш толеранса от 10 %, и го сверяваш с колоната `TARGETS`.
- Пишеш `HorizontalPodAutoscaler` с долна граница, горна граница и прозорец за намаляване и обясняваш защо Deployment-ът, който той управлява, вече не декларира `replicas`.
- Разпределяш репликите между възлите с `topologySpreadConstraints` и обясняваш `maxSkew`, `DoNotSchedule`, `nodeTaintsPolicy: Honor` и `matchLabelKeys`.
- Измерваш със сондиране колко заявки се провалят по време на обновяване, със и без `preStop`, и казваш какво доказва това измерване и какво не доказва.
- Използваш `rollout history` и `rollout undo`, гледаш `deletionTimestamp`, преди да заключиш, че връщането назад не е проработило, и разчиташ обновяване с образ, който не съществува (`ErrImagePull`), като проверяваш, че услугата не се прекъсва.
- Предизвикваш `drain`, блокиран от прекалено строг `PodDisruptionBudget`, разчиташ го и го коригираш; изключваш възел, измерваш прозореца на отказа и обясняваш какво го скъсява и какво не.

## Защо, преди как

Досега броят на репликите на `revisor` го решаваше ти, записан във файл. Това е добро решение за учене и лошо за понеделник в 9:00. Ако натоварването се утрои, никой не пише в този файл. А ако натоварването спадне, три реплики продължават да ядат CPU и памет, които други Pod-ове биха могли да ползват. Първият въпрос на урока е следователно: **кой решава колко реплики трябват, с каква информация и с каква спирачка?** Отговорът има три части. Измервател, `metrics-server`, който гледа колко CPU и памет ползва всеки Pod. Контролер, `HorizontalPodAutoscaler` (HPA), който сравнява измереното с цел и коригира броя на репликите. И правило за разпределение, за да не попадат новите реплики всичките в една и съща машина, защото три реплики в един възел падат заедно с този възел.

Вторият въпрос е **какво става с трафика, докато нещо се променя?** В един жив клъстер се променят много неща: нова версия, възел, който отива на поддръжка, възел, който пада без предупреждение. Всяко има различен отговор и разликата има значение. Обновяването се *планира*: Kubernetes може да сменя реплики една по една и да изчаква новата да е готова. Поддръжката се *договаря*: можеш да кажеш на клъстера колко реплики трябва да останат на крак и клъстерът спазва това число, когато изпразва възела. Падането *изненадва*: никой не е искал разрешение и клъстерът се бави да разбере. Урокът използва трите случая като повод за измерване. Измервай, не гадай, защото всеки от трите отговора е число, което се променя с конфигурацията, а това число е отговорът към директора.

И има трети въпрос, по-неудобен: **как се измерва прекъсването, без да се самоизмамиш?** Сондиране, което изпраща няколко заявки и не вижда нито един отказ, не доказва, че няма откази; доказва, че *този път, с този ритъм*, не са се видели. Урокът го казва всеки път, когато измерва нещо, и повтаря измерванията там, където това струва малко. Това е навикът, който отделя един отчет от един анекдот.

Урокът има десет части с понятия и после обичайните раздели:

1. **Клъстерът и изходната точка** (9.1): състоянието, с което завършва Урок 8, стартирано със скрипт.
2. **Измерване, преди да мащабираш** (9.2): `metrics-server`, флагът и защо.
3. **Автоматичният скалиращ механизъм и неговата формула** (9.3): `HorizontalPodAutoscaler`, толеранс, прозорец и защо `replicas` излиза от Deployment-а.
4. **Разпределение на репликите** (9.4): `topologySpreadConstraints`.
5. **Прилагане на промените** (9.5): какво показва `kubectl diff` и бъркотията с репликите, която се крие там.
6. **С натоварване автоматичният механизъм вдига** (9.6).
7. **Без натоварване сваля, след прозореца** (9.7).
8. **Кой командва репликите** (9.8).
9. **Обновяване и измерване на прекъсването** (9.9), със сондирането, `preStop` и връщането назад (9.10).
10. **Поддръжка и падане на възел** (9.11 и 9.12): `PodDisruptionBudget`, `drain` и изключен възел.

Това е целта. В края на 9.6, с натоварване, автоматичният механизъм вече е променил броя на репликите и го показва в един ред:

```text
$ kubectl get hpa revisor -n revisor --no-headers
revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

Това е ред от изпълнението (последният от изчакването в 9.6): HPA `revisor`, който управлява Deployment-а `revisor`, измерва `38 %` срещу цел от `50 %`, има долна граница от 2 реплики, горна от 6 и днес държи 4.

## Ако нямаш образа от курса по Docker

Този урок използва три локални образа: `curso-docker-revisor:1.6.0`, този на `revisor` от Урок 2; `curso-docker-prueba:1.0.0`, този на услугата, която се проваля нарочно; и един нов, `curso-docker-revisor:1.6.1`, който служи, за да има какво да обнови обновяването в урока. Двата образа на `revisor` идват от един и същ `Dockerfile` и един и същ код: единственото, което се променя, е версията, която услугата казва в своя `/salud` (`"version":"1.6.0"` или `"version":"1.6.1"`), а това е точно онова, което позволява да се види, заявка по заявка, коя реплика е отговорила. Провери, че ги имаш:

```text
$ docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep -E '^curso-docker-(revisor|prueba):'
curso-docker-revisor:1.6.1 61c70431badb
curso-docker-prueba:1.0.0 400d3fd59edc
curso-docker-revisor:1.6.0 bd1b2e7d91b8
```

(Този изход е от машината на автора и не е в `correr.salida.txt`. Идентификаторите са от него; при теб може да са други, ако си построил образите сам. Важното е да съществуват трите тага.) Ако ти липсва `1.6.1`, построй го по същия начин като `1.6.0`, от хранилището на курса по Docker, с `Dockerfile` от неговия Урок 10 върху папката `programas/revisor` и с `--build-arg VERSION=1.6.1`, като го тагнеш точно `curso-docker-revisor:1.6.1`. Това е лабораторен образ: служи, за да видиш едно обновяване, не е нова версия на услугата.

## Понятията

### 9.1 Клъстерът и изходната точка

#### 9.1.1 Правило за съжителство, отново

Този урок инсталира MetalLB (чрез `preparar.sh`, 9.1.3) и правилото от Урок 6 остава в сила: два клъстера с MetalLB и един и същ диапазон от адреси, в една и съща мрежа на Docker, си пречат. Преди да създадеш твоя, провери мрежата `kind` и че никой не отговаря вече на първия адрес на диапазона:

```bash
# La red kind debe ser 172.18.0.0/16: de ahí sale el rango de MetalLB.
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
# Nadie debe contestar en 172.18.255.200. Si este curl responde, hay otro
# clúster con MetalLB vivo: espera a que termine.
# Si imprime un número (200, 404…), alguien contesta; si imprime 000, nadie.
docker run --rm --network kind curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -o /dev/null -w '%{http_code}\n' -m 3 http://172.18.255.200/
kind get clusters
```

Ако мрежата `kind` още не съществува, защото никога не си създавал клъстер, създай клъстера и провери мрежата веднага след това. Има и една лабораторна подробност, която си струва да се каже още сега, защото променя адресите, които ще видиш в изходите: изпълнението на този урок използва **собствена мрежа на Docker**, `curso-k8s-red-l9`, с подмрежата `172.29.0.0/16`, за да може да работи едновременно с други уроци, които също инсталират MetalLB. На твоята машина, с обикновената мрежа `kind`, адресите от диапазона излизат като `172.18.255.x`, а не като `172.29.255.x`; скриптът `correr.sh` се нагажда с две променливи, `RED` и `SUBRED`, и носи обичайната спирачка: ако мрежата няма очакваната подмрежа, спира, преди да е създал каквото и да е.

#### 9.1.2 Създаване на клъстера и зареждане на образите

От корена на хранилището на курса:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
# La ruta queda guardada en la variable KUBECONFIG para borrarla al final.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l9.XXXX)/kubeconfig"
# curso-k8s-l9 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l9 --config programas/09-escalar-y-actualizar/kind-curso.yaml
# Debe decir kind-curso-k8s-l9. Si dice otra cosa, no sigas.
kubectl config current-context
# La guarda de siempre, con el nombre de este clúster. Va delante de cada
# comando que cambie algo: ctx && kubectl apply ...
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo"; return 1; }; }
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-revisor:1.6.1 curso-docker-prueba:1.0.0 --name curso-k8s-l9
cd programas/09-escalar-y-actualizar
# El token de mentira de la Lección 4: nuevo, legible solo para ti (0600), y no se versiona.
(umask 077; openssl rand -hex 16 > token.txt)
ls -l token.txt     # -rw-------
```

Функцията `ctx` сравнява активния контекст с очаквания; ако съвпадат, не отпечатва нищо, а ако не — пише „contexto equivocado: no sigo“ и връща грешка, която прекъсва веригата с `&&`. В този урок стои пред всяка команда, която **променя** нещо (`apply`, `patch`, `scale`, `drain`, `delete`); в изходите, които следват, е пропусната, за да се събират, но в твоя терминал стои. Командите, които само **четат** (`get`, `top`, `describe`), не се нуждаят от нея, макар че не пречи. `correr.sh` прави проверката преди всяка команда по друг начин, с функция, която спира сама.

`(umask 077; …)` кара `token.txt` да се роди като `-rw-------`: маската `077` отнема всички права на групата и на останалите, а скобите правят промяната валидна само за тази команда. Това е грижата от Уроци 4 до 6 и се повтаря, защото навик, който веднъж си пропуснал, вече не е навик.

```text
$ kind create cluster --name curso-k8s-l9 --config kind-curso.yaml
(crear el clúster y esperar a que estuviera listo tardó 37 s)

$ kubectl config current-context
kind-curso-k8s-l9

$ kubectl get nodes -o wide | awk '{print $1, $2, $5, $6}' | column -t
NAME                        STATUS  VERSION  INTERNAL-IP
curso-k8s-l9-control-plane  Ready   v1.37.0  172.29.0.2
curso-k8s-l9-worker         Ready   v1.37.0  172.29.0.4
curso-k8s-l9-worker2        Ready   v1.37.0  172.29.0.3
```

Създаването на клъстера и изчакването възлите и Pod-овете на `kube-system` да са готови отне 37 секунди, с образа на възела, изтеглен предварително. Три възела `Ready` във `v1.37.0`: един контролен и два работни. Колоната `INTERNAL-IP` е адресът на всеки възел в мрежата на Docker; тук попада в `172.29.0.x` заради собствената мрежа на изпълнението, а на твоята машина ще попадне в `172.18.0.x`. Зареждането на трите образа с `kind load` отпечатва обичайните си редове (`not yet present on node … loading...`); `correr.sh` ги заглушава и вместо тях отбелязва, че са заредени.

#### 9.1.3 Изходната точка: `preparar.sh`

Урок 8 завършва с клъстер, който вече носи платформата от Урок 6 и проекта от Урок 8. За да не повтаряш на ръка няколко минути инсталация, `preparar.sh` ги възстановява с **трите стъпки от Урок 6, на показ и в същия ред**: платформата (MetalLB и Envoy Gateway), изчакването с `kubectl wait`, докато са готови, и накрая диапазонът от адреси, класът на входната точка и проектът от папката `punto-de-partida/`. Ако идваш от Урок 8 с жив клъстер, не ти трябва; ако започваш оттук или вече си го изтрил, го пускаш:

```bash
ctx && ./preparar.sh
```

Това е **програма**: `preparar.sh`. Прочети я, преди да я пуснеш: не крие нищо. Всяка стъпка проверява контекста, отпечатва командата, която ще изпълни, и спира, ако се провали. Приема една променлива, `POOL_RANGO`, за да смениш диапазона на MetalLB, ако мрежата ти не е `172.18.0.0/16`. Бележка за ширината: `infra/metallb-pool.yaml` и `preparar.sh` носят `.200-.220`, докато `correr.sh` пресмята `.200-.250`, което се вижда по-долу. Тук няма значение, защото се ползва само първият адрес от диапазона, този на Gateway.

```text
$ POOL_RANGO=172.29.255.200-172.29.255.250 ./preparar.sh
## Paso 1: la plataforma

$ kubectl apply -k infra/metallb >/dev/null

$ kubectl apply --server-side -k infra/envoy-gateway >/dev/null

## Paso 2: la espera

$ kubectl wait --for=condition=Established crd/ipaddresspools.metallb.io crd/l2advertisements.metallb.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/ipaddresspools.metallb.io condition met
customresourcedefinition.apiextensions.k8s.io/l2advertisements.metallb.io condition met

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=1200s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=1200s
Waiting for daemon set "speaker" rollout to finish: 0 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 1 of 3 updated pods are available...
Waiting for daemon set "speaker" rollout to finish: 2 of 3 updated pods are available...
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=1200s
deployment.apps/envoy-gateway condition met

## Paso 3: la configuración de la plataforma, y el proyecto

$ kubectl apply -f /tmp/curso-k8s-l9.wJDg/metallb-pool.Xbdv -f infra/gatewayclass.yaml
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met

$ kubectl apply -k punto-de-partida >/dev/null

$ kubectl rollout status deployment/revisor deployment/prueba -n revisor --timeout=600s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=1200s
gateway.gateway.networking.k8s.io/revisor condition met
(preparar.sh tardó 343 s)
```

Чете се на три хода, същите като в Урок 6. В **стъпка 1** се прилагат платформата на MetalLB и тази на Envoy Gateway; изходите им се пращат към `/dev/null`, защото са десетки безинтересни реда. В **стъпка 2** идват изчакванията, всички с `kubectl wait` или `rollout status` и всички съсъс срок: новите типове на MetalLB (`condition met`), контролерът, готов `speaker` във всеки от трите възела, типовете на Gateway API, контролерът на Envoy Gateway. В **стъпка 3** се прилагат диапазонът от адреси (временен файл, който `preparar.sh` е генерирал от `infra/metallb-pool.yaml` с диапазона на собствената мрежа: това е ефектът на `POOL_RANGO`), класът на входната точка `eg` и накрая проектът от `punto-de-partida/`, със своя `rollout status` и изчакването Gateway-ът да е `Programmed`. Всичко отне 343 секунди; по-голямата част — в чакане на теглене на образи. Това е изходната точка на урока:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           22s
deployment.apps/revisor   3/3     3            3           22s

$ kubectl get gateway -n revisor
NAME      CLASS   ADDRESS          PROGRAMMED   AGE
revisor   eg      172.29.255.200   True         22s

$ docker run --rm --network curso-k8s-red-l9 --name curso-k8s-l9-cliente curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 -s -m 5 http://172.29.255.200/salud
{"estado":"vivo","version":"1.6.0"}
```

Три реплики на `revisor`, тази на тестовата услуга, още никакъв HPA или PDB (последният `get` не ги изброява, защото не съществуват) и Gateway с `PROGRAMMED True` на първия адрес от диапазона. Последната команда е клиентът „отвън“ от Урок 6, контейнер с `curl`, свързан към мрежата на Docker, който иска `/salud` през входната точка: `{"estado":"vivo","version":"1.6.0"}`. Ако това отговаря, платформата и проектът са на крак.

### 9.2 Измерване, преди да мащабираш: `metrics-server`

#### 9.2.1 Какво клъстерът още не знае

Преди да решиш колко реплики трябват, трябва да знаеш колко CPU ползват съществуващите. Клъстерът не го знае от фабриката. Ако го попиташ с `kubectl top`, командата, която показва потреблението:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]
```

`error: Metrics API not available`: „API-то за метрики не е налично“. Фразата има точен подлог. Kubernetes дефинира API за потреблението на CPU и памет на възли и Pod-ове, **Metrics API**, и документацията го описва така: предлага „основен набор от метрики, които да поддържат автоматичното мащабиране и подобни случаи“ ([Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)). Но това API е само *начин* да попиташ: някой трябва да отговаря. Същата страница го казва без украшения: трябва да разгърнеш `metrics-server` „или алтернативен адаптер“, за да го ползваш, а основната му роля е „да подава метрики за използване на ресурси на компонентите за автоматично мащабиране“. Новосъздаденият клъстер не го носи и затова `top` няма към кого да се обърне.

Как се включва един отговарящ към API-то на Kubernetes? С обект, който вече познаваш от Урок 6, по родство: ресурс, който учи `kube-apiserver` на нещо ново. Тук не е CRD, а `APIService`, който казва на `kube-apiserver`: „въпросите, които пристигат на `/apis/metrics.k8s.io/v1beta1`, не ги отговаряй ти; препрати ги на този Service“. Преди да инсталираш каквото и да е, този обект не съществува:

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
Error from server (NotFound): apiservices.apiregistration.k8s.io "v1beta1.metrics.k8s.io" not found
[código de salida: 1]
```

С `NotFound`: `kube-apiserver` няма на кого да препрати. Това е същата ситуация като с `Gateway` в Урок 6, видяна от друга страна: преди да съществува компонентът, да питаш за него е да питаш в празното.

#### 9.2.2 Инсталиране на `metrics-server` в чистия му вид

Проектът публикува по един манифест за версия. Тази, която ползва урокът, е **v0.9.0** и се фиксира в URL адреса, както е фиксирано всичко останало в курса: без фиксирана версия, в деня, в който последната версия се промени, твоята лаборатория се променя, без да те предупреди. Прилага се такъв, какъвто е, без да се променя нищо, за да видиш какво става:

```text
$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml | tail -3
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
(espera visible: hasta 600 s a que metrics-server descargue su imagen, arranque e intente leer a los kubelet)
```

Трите реда, които се виждат, са последните от няколко (`| tail -3`): един `Service`, един `Deployment` и `APIService`, който свързва двата с `kube-apiserver`. За момента на гледане: Deployment-ът не става готов веднага. Първо трябва да изтегли образа си и да стартира, а после да направи първото си четене. Скриптът изчаква, на показ, докато логът на Pod-а покаже грешката, която искаме да прочетем (до 600 секунди, защото на бавна машина тегленето отнема). В твоя терминал можеш да повтаряш `kubectl get deployment metrics-server -n kube-system`, докато видиш `0/1` с няколко секунди възраст. Това е изчакване от друг вид от `kubectl wait`: тук не се чака да *настъпи* условие, чака се, за да се *даде време да се провали* и да може да се прочете как.

```text
$ kubectl get deployment metrics-server -n kube-system
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   0/1     1            0           30s
```

`READY 0/1` и `AVAILABLE 0`: Pod-ът съществува, но не е готов. Следва се редът от Урок 5, който казва какво да гледаш първо, когато нещо не стартира: логът на Pod-а.

```text
$ kubectl logs -n kube-system deployment/metrics-server --tail=200 | grep -E 'x509|tls|certificate' | tail -1
E1021 23:14:05.707527       1 scraper.go:149] "Failed to scrape node" err="Get \"https://172.29.0.2:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs" node="curso-k8s-l9-control-plane"
```

Чете се отляво надясно. `E1021` е ред от ниво *error* от 21 октомври. `scraper.go:149` е мястото в кода, което се е провалило, а `Failed to scrape node` казва какво се е опитвало да направи: да „изстърже“ (събере) метриките на възела, което `metrics-server` прави на всеки няколко секунди, като пита `kubelet` на всеки възел за CPU и паметта, които ползват Pod-овете му. Адресът е `https://172.29.0.2:10250/metrics/resource`: `kubelet` на този възел (контролния; на твоята машина ще е `172.18.0.x`), по IP адрес, на порт 10250. И причината, накрая: `tls: failed to verify certificate: x509: cannot validate certificate for 172.29.0.2 because it doesn't contain any IP SANs`.

Трябва да разглобиш тази фраза. TLS е криптирането, с което `metrics-server` говори с `kubelet` (HTTPS). За да има криптирането стойност, `metrics-server` проверява **сертификата**, който `kubelet` му представя: проверява, че го е подписал орган, на който се доверява, и че сертификатът твърди, че е за адреса, към който се е свързал. Сертификатът носи списък с валидни имена и адреси, *Subject Alternative Names* (SAN). Тук сертификатът на `kubelet` не носи нито един **IP** в този списък, а `metrics-server` се е свързал по IP: затова не може да потвърди, че „`172.29.0.2`“ е този, за когото се представя. Онова, което логът доказва, е само това: сертификатът не носи никакъв IP. README на `metrics-server` поставя като изискване сертификатът на `kubelet` да е подписан от органа на клъстера ([metrics-server](https://github.com/kubernetes-sigs/metrics-server)), а в kind възлите не го изпълняват в чистия си вид. В истински клъстер това се оправя във възлите; в тази лаборатория не се опитва.

Докато Pod-ът не е готов, `Service`-ът на `metrics-server` няма крайни точки и `APIService` го отразява:

```text
$ kubectl top nodes
error: Metrics API not available
[código de salida: 1]

$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE                  AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   False (MissingEndpoints)   30s
```

`AVAILABLE False (MissingEndpoints)`: „липсват крайни точки“. Service-ът няма на кого да праща въпросите, защото единственият Pod не е готов. Сега грешката на `kubectl top` има пълната си верига: командата пита `kube-apiserver`; той препраща към Service-а; Service-ът няма крайни точки; единствената крайна точка не е готова; и не е готова, защото не може да провери сертификата на `kubelet`. Пет звена, а съобщението отгоре показваше само последното. Това е същият занаят като в Урок 3: слиза се етаж по етаж, докато се намери този, който се проваля.

#### 9.2.3 Флагът и защо е само за лаборатория

`metrics-server` има опция да не проверява сертификата на `kubelet`: `--kubelet-insecure-tls`. README му я описва с две кратки изречения, които си струва да се четат бавно: „Do not verify the CA of serving certificates presented by Kubelets. For testing purposes only“ („Не проверявай органа на сертификатите, които представят kubelet. Само за тестове“). Не е начин на изразяване, за да звучи добре: това е предупреждение и урокът го спазва. Този флаг важи в лаборатория, в която възлите са твои контейнери на твоята машина, и не важи в клъстер, в който някой друг би могъл да се намести в мрежата между `metrics-server` и един възел, защото без проверка на сертификата няма начин да се знае с кого се говори.

Манифестът на v0.9.0 не носи флага; добавя се с *пач* (patch) на Kustomize. Това е **програма**: `metrics-server/kustomization.yaml`.

```yaml
# metrics-server — Lección 9. Versión fijada (v0.9.0). En kind, el certificado de
# cada kubelet no trae ninguna IP y metrics-server no lo acepta sin
# --kubelet-insecure-tls. Eso SOLO vale en un clúster de laboratorio.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
patches:
- target:
    kind: Deployment
    name: metrics-server
    namespace: kube-system
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/args/-
      value: --kubelet-insecure-tls
```

Пачът казва: в Deployment-а `metrics-server` на пространството `kube-system` добави в края на списъка с аргументи на първия контейнер `--kubelet-insecure-tls`. `op: add` с `args/-` е начинът да „добавиш в края“ на списък в пач от тип JSON. Прилага се с `-k`, както всичко останало:

```text
$ kubectl apply -k metrics-server | tail -3
service/metrics-server unchanged
deployment.apps/metrics-server configured
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io unchanged
```

Два обекта `unchanged` (Service-ът и APIService не се променят) и един `configured`: Deployment-ът. Шаблонът му се промени, така че ще има смяна на Pod-а, и този път изчакването е по условие:

```text
$ kubectl rollout status deployment/metrics-server -n kube-system --timeout=600s
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "metrics-server" rollout to finish: 1 old replicas are pending termination...
deployment "metrics-server" successfully rolled out
(espera de 45 s: metrics-server mide en ventanas y necesita un par de ellas)
```

После идва пауза, която не е по условие, и е добре да се каже: `metrics-server` измерва по времеви прозорци и му трябват два-три от тях, преди да може да отговаря с данни, така че урокът изчаква 45 секунди по часовник. Вместо да се гадае, има начин да се провери, че вече отговаря: да се попита `APIService`, който трябва да мине на `True`.

```text
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        98s
```

`AVAILABLE True`. Сега `top` има към кого да се обърне:

```text
$ kubectl top nodes
NAME                         CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
curso-k8s-l9-control-plane   139m         2%       974Mi           6%          
curso-k8s-l9-worker          92m          1%       272Mi           1%          
curso-k8s-l9-worker2         53m          0%       316Mi           1%          

$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-cgzkw    1m           1Mi             
revisor-67b97d67c9-fnpdj   1m           1Mi             
revisor-67b97d67c9-jfdw4   1m           1Mi             
revisor-67b97d67c9-tqffn   1m           1Mi             
```

Колоната `CPU(cores)` е в **милиядра** (millicores): `1m` е една хилядна от ядро, същата единица като `requests` от Урок 5. Документацията обяснява откъде идва: CPU се отчита „като средно използване на ядра“, изчислено „като скорост върху натрупан брояч на CPU, който дава ядрото“ на Linux, в времеви прозорец, който самото API съобщава (полето `window`). Не е снимка на един миг, а средна стойност на кратък прозорец. А `CPU(%)` в `top nodes` е процентът от CPU **на възела**, не от `request` на когото и да е; това е друга сметка, а онази, която интересува автоматичния скалиращ механизъм, е следващата. Виж Pod-овете на `revisor`: няколко десети от милиядро или няколко милиядра използване, срещу `50m`, които са поискали:

```text
$ kubectl describe pod -n revisor -l app=revisor | grep -E 'Requests|cpu:' | head -4
      cpu:     200m
    Requests:
      cpu:      50m
      cpu:     200m
```

(Първото `cpu: 200m` е `limit`; `Requests` и неговото `cpu: 50m` са долната граница. Третото е `limit` на другия изброен контейнер; филтърът `head -4` отрязва изхода там, където се събира.) Pod, който ползва `4m` от `50m`, е на 8 % от онова, което е поискал. Този процент, на **използване спрямо `requests`**, е мерилото на автоматичния скалиращ механизъм.

Документацията на `metrics-server` казва и за какво **не** служи и си струва да се чуе, преди да му се довериш: случаите му на употреба са хоризонталното мащабиране по CPU и памет, а README му предупреждава, че не е „точен източник за използването на ресурси“. За да гледаш потреблението с точност, за да го чертаеш или за да алармираш, има други инструменти. За да решиш колко реплики, стига.

### 9.3 Автоматичният скалиращ механизъм и неговата формула

#### 9.3.1 Какво е и на колко често гледа

`HorizontalPodAutoscaler` е контролер, още един от онези, които видя в Урок 0 да правят все същото: сравняват желаното състояние с реалното и избутват второто към първото. Разликата е какво разбира под „желано състояние“: не брой реплики, а **цел за потребление**. „Хоризонтален“ значи, че променя *броя* на репликите, а не размера на всяка. Документацията казва, че цикълът върви на всеки 15 секунди по подразбиране (`--horizontal-pod-autoscaler-sync-period`) ([Horizontal Pod Autoscaling](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)).

На всеки оборот прави три неща: чете метриките на Pod-овете на целта, пресмята колко реплики би поискал и, ако резултатът променя текущия брой, го поисква от Deployment-а. Частта, която може да се пресметне на ръка, е втората и е тази:

```text
réplicas deseadas = ceil( réplicas actuales × (métrica actual ÷ métrica deseada) )
```

Това е формулата, която дава документацията: `desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]`. `ceil` е „закръгляне нагоре“. С цел за CPU от 50 %: ако има 2 реплики и средното използване е 100 % от поисканото, сметката е `ceil(2 × 100 ÷ 50) = ceil(4) = 4`. Ако средното използване е 25 %, `ceil(2 × 25 ÷ 50) = ceil(1) = 1`. Закръгляването нагоре има причина: за предпочитане е един Pod повече, отколкото един по-малко, когато целта е на косъм да бъде надхвърлена.

А „процентът“? При цел от тип `Utilization` контролерът изчислява използването „като процент от съответния `request` на контейнерите на всеки Pod“ и взема средната стойност от всички Pod-ове на целта. Затова един Pod без `requests` за CPU е Pod, който автоматичният скалиращ механизъм не може да измери: документацията казва, че ако някой контейнер няма заявката, „използването на CPU на Pod-а не е дефинирано и автоматичният скалиращ механизъм не прави нищо с тази метрика“. Урок 5 сложи `requests` във всеки контейнер „за да знае планировчикът къде да го сложи“; днес това решение служи за втора цел, която тогава не се виждаше.

#### 9.3.2 Толерансът от 10 %

Ако изчислението се прилагаше такова, каквото е, автоматичният скалиращ механизъм би променял броя на репликите заради разлики от един процентен пункт и клъстерът би бил в непрекъснато нагаждане. За да се избегне това, контролерът прескача всяко нагаждане, когато отношението `текуща метрика ÷ желана метрика` е „достатъчно близо до 1.0“, а документацията дава мярката: толеранс 0.1 по подразбиране, тоест 10 % (от Kubernetes 1.37 всеки HPA може да задава свой собствен толеранс в `behavior.scaleUp.tolerance` и `behavior.scaleDown.tolerance`; този урок оставя този на клъстера, 10 %). С цел от 50 % има нагаждане само ако измереното използване излезе извън 45 % до 55 %: отношението трябва да е по-малко от 0.9 или по-голямо от 1.1.

Пример с числа, за да го пресметнеш на ръка, преди да видиш клъстера. С 3 реплики и цел от 50 %:

| Измерено използване | Отношение | Извън 0.9 до 1.1? | `ceil(3 × отношение)` | Какво прави |
|---|---|---|---|---|
| 54 % | 1.08 | не | — | нищо |
| 57 % | 1.14 | да | `ceil(3.42)` = 4 | вдига до 4 |
| 40 % | 0.80 | да | `ceil(2.4)` = 3 | не се променя (3), но препоръката се записва |
| 20 % | 0.40 | да | `ceil(1.2)` = 2 | сваля до 2 (ако прозорецът позволява) |

Когато клъстерът ти даде числа, ще ги сверяваш с тази таблица.

#### 9.3.3 Манифестът

Това е **програма**: `escalado.yaml`. Носи два обекта, автоматичния скалиращ механизъм и бюджет за прекъсвания, който се обяснява в 9.11.

```yaml
# escalado.yaml — Lección 9: réplicas según la carga, con límites, y al menos
# una disponible durante un mantenimiento.
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: revisor
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: revisor
  minReplicas: 2
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 60
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: revisor
```

Чете се поле по поле:

- **`scaleTargetRef`**: кого управлява. Един `Deployment` на име `revisor` от същото пространство от имена. HPA не пипа Pod-ове: иска от Deployment-а да промени броя на репликите си и Deployment-ът прави останалото, както винаги.
- **`minReplicas: 2` и `maxReplicas: 6`**: долната и горната граница. Долната е 2 по две причини: с една реплика всяка смяна е прекъсване, а с две (по една във всеки работен възел) обновяването от 9.9 и поддръжката от 9.11 могат да се правят, без да се губи услугата. Горната е 6 заради навика за сигурност, който затваря този урок: автоматичен скалиращ механизъм без горна граница превръща лавина от заявки, или грешка в един цикъл, в сметка или в изтощен възел.
- **`metrics`**: какво измерва и спрямо какво. Един ресурс, CPU, с цел за средно използване от 50 % *от `requests`*. Целта е междинна нарочно: ако беше 90 %, автоматичният скалиращ механизъм би реагирал, когато услугата вече е почти наситена.
- **`behavior.scaleDown.stabilizationWindowSeconds: 60`**: прозорецът за намаляване, който се обяснява веднага.

Полето `behavior` заслужава собствен абзац. Без него HPA използва стойностите по подразбиране от документацията: за **вдигане** — прозорец за стабилизиране от 0 секунди и политика, която позволява да се добавят до 4 Pod-а или да се удвоят репликите на всеки 15 секунди, което от двете е по-голямо; за **сваляне** — прозорец от **300 секунди** (пет минути) и политика, която позволява да се махнат всички излишни реплики наведнъж. Урокът използва 60 секунди вместо 300, за да можеш да видиш свалянето, без да чакаш пет минути, и го казва, защото не е стойност за копиране: в продукция дългият прозорец предпазва от люлеенето („вдигам, свалям, вдигам, свалям“), когато натоварването е неравномерно.

Какво прави прозорецът, точно? Документацията го обяснява прецизно: непосредствено преди да мащабира, контролерът записва препоръката за момента, а после „разглежда всички препоръки в настроения прозорец и избира най-високата“. Тоест: за да **свали**, HPA не използва онова, което вижда сега, а **максимума** от онова, което е препоръчвал през последните 60 секунди. Ако преди 40 секунди е препоръчвал 4 реплики, а сега препоръчва 2, остава на 4, докато тази препоръка за 4 излезе от прозореца. Това е нарочна памет за най-лошото от последно време и е причината свалянето да е бавно, а вдигането — не.

Накрая, `kubectl diff` от 9.5 ще покаже, че HPA, когато се приложи, носи записани в изхода стойностите по подразбиране на `scaleUp` и `scaleDown` (`selectPolicy: Max`, политиките от 15 секунди): сървърът допълва онова, което не си написал.

#### 9.3.4 Защо Deployment-ът вече не носи `replicas`

В папката на Урок 8 Deployment-ът на `revisor` казваше `replicas: 3`. В днешната това поле го няма. Не е недоглеждане: това е изричната препоръка на документацията на HPA. Когато има автоматичен скалиращ механизъм, полето `spec.replicas` на Deployment-а трябва да се махне от манифеста, защото иначе „всеки път, когато се приложи промяна към този обект, например с `kubectl apply -f deployment.yaml`, Kubernetes ще мащабира текущия брой Pod-ове до стойността на `spec.replicas`“, което „може да е проблемно, когато HPA е активен, и да причини *люлеене*“. Двама собственици на едно и също число се карат: твоят файл казва 3, HPA току-що е поискал 5 и всеки `apply` разваля онова, което другият е направил.

Документацията добавя предупреждение, което 9.5 ще направи видимо: махането на полето „може да причини еднократно намаляване на броя на Pod-овете, защото стойността по подразбиране на този ключ е 1“. Тоест, като приложиш за първи път Deployment-а **без** `replicas`, клъстерът го чете като „върни се към стойността по подразбиране“ и предлага да слезе до една реплика. В 9.5 ще видиш този `replicas: 1` в `kubectl diff` и ще видиш какво става после.

### 9.4 Разпределение на репликите

#### 9.4.1 Проблемът: нищо не разпределя вместо теб

Автоматичен скалиращ механизъм, който вдига до четири реплики, не казва къде ги слага; това решава планировчикът (*scheduler*), който търси възела, който най-добре пасва по ресурси и други правила, и по подразбиране не се старае да разпределя. Виж как се наредиха трите реплики от папката на Урок 8, без никакво правило за разпределение:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-67b97d67c9-fnpdj   1/1     Running   0          22s   10.244.2.6   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-jfdw4   1/1     Running   0          22s   10.244.2.5   curso-k8s-l9-worker2   <none>           <none>
revisor-67b97d67c9-tqffn   1/1     Running   0          22s   10.244.1.3   curso-k8s-l9-worker    <none>           <none>
```

Колоната `NODE` казва къде е всяка. В това изпълнение две от трите реплики попаднаха заедно в `curso-k8s-l9-worker2` и една в `curso-k8s-l9-worker`. Не е лош късмет: в това изпълнение и в три предишни, които не са запазени, две от трите реплики попадаха заедно, веднъж в единия възел, друг път в другия. Планировчикът не обещава да разпределя. Ако възелът с две реплики падне, услугата губи 67 % от капацитета си наведнъж, а автоматичният скалиращ механизъм не помага: работата му е да гледа CPU, не разпределението.

#### 9.4.2 `topologySpreadConstraints`

Kubernetes има компонент за това: **ограниченията за разпределение по топология**. „Топология“ тук значи „в коя част от инфраструктурата живее всяко нещо“: в кой възел, в коя зона на облака, в кой rack. Документацията дефинира речника ([Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/)): един етикет на възел, `topologyKey`, разделя възлите на **домейни**, а възлите, които имат една и съща стойност на този етикет, образуват един домейн. Етикетът `kubernetes.io/hostname` има различна стойност за всеки възел, така че с него *всеки възел е собствен домейн*. Точно това се иска тук: разпределение между възли.

Ограничението на `revisor` е това. Фрагмент е от **програмата** `revisor-deployment.yaml`, вътре в `spec.template.spec`:

```yaml
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        nodeTaintsPolicy: Honor
        labelSelector:
          matchLabels:
            app: revisor
        matchLabelKeys:
        - pod-template-hash
```

Всяко поле, по ред:

- **`topologyKey: kubernetes.io/hostname`**: всеки възел е домейн, както се каза.
- **`labelSelector`**: кои Pod-ове се броят във всеки домейн. Тези с `app: revisor`; репликите на `prueba` или Pod-овете на натоварването не се броят и не пречат.
- **`maxSkew: 1`**: максимално допустимата **асиметрия** (*skew*): разликата между броя Pod-ове в един домейн и този на домейна с най-малко. Документацията го дефинира така: с `DoNotSchedule`, `maxSkew` „е максимално допустимата разлика между броя съвпадащи Pod-ове в целевия домейн и *глобалния минимум*“. С `maxSkew: 1` и два работни възела 2 + 0 не е позволено (разлика 2), 1 + 1 е, 2 + 1 е, 3 + 1 не е.
- **`whenUnsatisfiable: DoNotSchedule`**: какво да се прави, ако поставянето на Pod-а нарушава ограничението. `DoNotSchedule` (стойността по подразбиране) казва „не го планирай“: Pod-ът остава `Pending`. `ScheduleAnyway` казва „планирай го все пак, но предпочитай местата, които намаляват асиметрията“: това е предпочитание, не правило. Този урок използва твърдото правило, защото меко пропуска точно онова, което се иска да се избегне: ограничението е, за да е разпределението *истинско*, а предпочитанието не го гарантира.
- **`nodeTaintsPolicy: Honor`**: как да се третират *taint*-овете на възлите при изчисляване на асиметрията. Обяснява се в 9.4.3 и се проверява в 9.5.4, защото е полето, което изглежда излишно и не е.
- **`matchLabelKeys: [pod-template-hash]`**: ограничава броенето до репликите от **същата версия**. Deployment-ът слага на всеки Pod етикет, `pod-template-hash`, с различна стойност за всяка версия на шаблона. Документацията казва, че този етикет, който „добавя автоматично контролерът на Deployment-а“, служи „за да се различават различните ревизии на един и същ Deployment“. При обновяване съжителстват стари и нови реплики; без това поле старите биха се броили за разпределението на новите и биха пречили; с него всяка версия се разпределя самостоятелно.

#### 9.4.3 Защо контролният възел изисква `Honor`

Клъстерът има три възела и само два получават реплики. Контролният възел носи *taint* (`node-role.kubernetes.io/control-plane:NoSchedule`), който пречи да се планират там потребителски Pod-ове. Но брои ли се като домейн за изчисляването на „глобалния минимум“? Зависи от `nodeTaintsPolicy`. Документацията дефинира двете опции: `Honor` включва „възлите без taint-ове, заедно с възлите с taint-ове, за които входящият Pod има толерантност“; `Ignore` игнорира taint-овете и включва всички възли; а ако полето е празно, поведението е равно на `Ignore`.

Това значи, че **без** `Honor` контролният възел влиза в сметката като домейн с нула Pod-а, а „глобалният минимум“ е 0, защото този възел не може да получи реплика. С тази фиксирана нула `maxSkew: 1` позволява най-много 1 Pod на домейн: третата реплика няма къде да отиде. Това е видът правило, което работи с две реплики и се чупи с третата, и именно затова е грешка, която се намира в продукция в понеделник в 9:00. 9.5.4 я предизвиква, за да я видиш.

#### 9.4.4 Какво ограничението не прави


Документацията на този компонент носи предупреждение в раздела си за ограниченията: „няма гаранция, че ограниченията продължават да се спазват, когато се махат Pod-ове. Например намаляването на един Deployment може да остави Pod-овете небалансирани“, и препоръчва инструменти като *Descheduler* за ребалансиране. Правилото се прилага **при планирането** на нов Pod, не преди, нито след. 9.11 ще го покаже с поддръжка, която оставя репликите заедно, и ще покаже и как се поправя, без да инсталираш нищо.

### 9.5 Прилагане на промените

#### 9.5.1 Какво се променя, преди да приложиш

С готова папка на Урок 9 първата стъпка не е да приложиш, а да попиташ какво ще се промени. `kubectl diff -k .` изпраща на сървъра резултата от `-k` и показва разликата спрямо онова, което има. Командата се филтрира (`grep -E '^[+-] '`), за да останат редовете, които се променят, и да се махне шумът от метаданни (`creationTimestamp`, `uid`, `resourceVersion`):

```text
$ kubectl diff -k . | grep -E '^[+-] ' | grep -v -E 'creationTimestamp|generation|resourceVersion|uid:|managedFields'
-  replicas: 3
+  replicas: 1
-      maxSurge: 25%
-      maxUnavailable: 25%
+      maxSurge: 1
+      maxUnavailable: 0
+        lifecycle:
+          preStop:
+            sleep:
+              seconds: 5
-      terminationGracePeriodSeconds: 10
+      terminationGracePeriodSeconds: 15
+      topologySpreadConstraints:
+      - labelSelector:
+          matchLabels:
+            app: revisor
+        matchLabelKeys:
+        - pod-template-hash
+        maxSkew: 1
+        nodeTaintsPolicy: Honor
+        topologyKey: kubernetes.io/hostname
+        whenUnsatisfiable: DoNotSchedule
+  name: revisor
+  namespace: revisor
+  behavior:
+    scaleDown:
+      policies:
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 60
+    scaleUp:
+      policies:
+      - periodSeconds: 15
+        type: Pods
+        value: 4
+      - periodSeconds: 15
+        type: Percent
+        value: 100
+      selectPolicy: Max
+      stabilizationWindowSeconds: 0
+  maxReplicas: 6
+  metrics:
+  - resource:
+      name: cpu
+      target:
+        averageUtilization: 50
+        type: Utilization
+    type: Resource
+  minReplicas: 2
+  scaleTargetRef:
+    apiVersion: apps/v1
+    kind: Deployment
+    name: revisor
+  currentMetrics: null
+  desiredReplicas: 0
+  name: revisor
+  namespace: revisor
+  minAvailable: 1
+  selector:
+    matchLabels:
+      app: revisor
+  currentHealthy: 0
+  desiredHealthy: 0
+  disruptionsAllowed: 0
+  expectedPods: 0
[código de salida: 1]
```

Кодът `1` накрая не е грешка: `kubectl diff` излиза с 1, когато **има** разлики, и с 0, когато няма, за да може да се ползва в скрипт. Чете се на три блока:

1. **`-  replicas: 3` / `+  replicas: 1`.** Обявеното в 9.3.4. Файлът вече не казва `replicas`, а сървърът, който носи стойността си по подразбиране, предлага **1**. Ако приложиш това, без да се замислиш, `revisor` минава от три реплики на една, макар и за миг, преди автоматичният скалиращ механизъм да го коригира. Тук не е сериозно; с 40 души, свързани в 9:00, би било. Това е еднократната цена за предаването на контрола върху броя на репликите и е добре да се знае, преди да се плати.
2. **`maxSurge: 25%` → `1` и `maxUnavailable: 25%` → `0`.** Стойностите по подразбиране на стратегията за обновяване стават изрични. Обясняват се в 9.9.
3. **`lifecycle` / `preStop`, `terminationGracePeriodSeconds: 10` → `15` и `topologySpreadConstraints`.** Паузата преди спиране, по-дългият срок, от който тази пауза се нуждае, и разпределението от 9.4. А отдолу — новите обекти: HPA (със записани стойностите по подразбиране) и PodDisruptionBudget.

#### 9.5.2 Прилагане и наблюдение

```text
$ kubectl apply -k . | grep -E 'horizontalpod|poddisruption|deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
poddisruptionbudget.policy/revisor created
horizontalpodautoscaler.autoscaling/revisor created

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
(espera de 30 s: el HPA necesita su primera lectura de métricas)
```

Четири реда: `deployment.apps/revisor configured`, PDB и HPA `created` и `prueba unchanged` (онова, което не се е променило, не се пипа). `rollout status` показва смяната на репликите, защото шаблонът се е променил (`preStop`, срокът и разпределението) и затова има подредена смяна, една по една, както в Урок 2. След това има пауза от 30 секунди на показ: HPA се нуждае от първото си четене на метрики, преди да покаже число.

```text
$ kubectl get hpa,pdb -n revisor
NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          32s

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     32s
```

Прочети колоната `TARGETS` на HPA: `cpu: 2%/50%` е „текущо използване / цел“. Използването е средното, върху `requests` на Pod-овете, което 9.2 обясни. `MINPODS 2` и `MAXPODS 6` са долната и горната граница, а `REPLICAS` е текущият брой. В PDB `ALLOWED DISRUPTIONS` казва колко Pod-а могат да се загубят доброволно в момента; обяснява се в 9.11.

Подробност при четенето: първия път, когато се приложи HPA, ако го погледнеш прекалено рано, `TARGETS` казва `cpu: <unknown>/50%`. Не е повреда: контролерът още няма измерване на новите Pod-ове. Събитията на HPA, които се четат в 9.6, пазят следата от тези първи секунди.

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-5xvt5   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-857qf   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.replicas}{"\n"}'
2
```

Две реплики, **по една във всеки работен възел**. Разпределението се изпълни, а броят на репликите го постави HPA: `.spec.replicas` е 2, долната граница. Най-вероятната верига, и тази, която подсказва събитието `Current number of replicas below Spec.MinReplicas` от 9.6, беше: `apply` остави Deployment-а на 1 (стойността по подразбиране), HPA видя, че 1 е под долната граница от 2, и го вдигна, а смяната разпредели двете реплики заради ограничението.

#### 9.5.3 Логът на HPA разказва какво е направил

HPA оставя решенията си в събитията. Четат се с `describe`, който ще се покаже цял в 9.6 след натоварването, а първият ред е следата от горното: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. „Текущият брой реплики е под минимума“: HPA не реагираше на натоварване, а прилагаше долната граница.

#### 9.5.4 Грешката: разпределение без `nodeTaintsPolicy: Honor`

Сега обещаната в 9.4.3 грешка. Предизвиква се като се махне само `nodeTaintsPolicy` от живия Deployment, с пач, и се поиска трета реплика на ръка:

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/topologySpreadConstraints/0/nodeTaintsPolicy"}]'
deployment.apps/revisor patched

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running       0          6s    10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running       0          3s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5xvt5   1/1     Terminating   0          38s   10.244.2.8   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-857qf   1/1     Terminating   0          38s   10.244.1.8   curso-k8s-l9-worker    <none>           <none>
```

С две реплики всичко изглежда нормално. Това прави тази грешка коварна: дефектът не се вижда, докато не дойде третата.

```text
$ kubectl scale deployment/revisor -n revisor --replicas=3
deployment.apps/revisor scaled
(espera de 6 s: el planificador decide en un instante)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Running   0          12s   10.244.1.9   curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-4nwx5   0/1     Pending   0          6s    <none>       <none>                 <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Running   0          9s    10.244.2.9   curso-k8s-l9-worker2   <none>           <none>
```

Третата реплика остава `Pending`, без назначен възел. Следва се редът от Урок 5: `describe` на чакащия Pod (името се променя при твоето изпълнение), раздел със събитията.

```text
$ kubectl describe pod revisor-574b5b6c4c-4nwx5 -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  6s    default-scheduler  0/3 nodes are available: 1 node(s) had untolerated taint(s), 2 node(s) didn't match pod topology spread constraints. preemption: 0/3 nodes are available: 1 Preemption is not helpful for scheduling, 2 No preemption victims found for incoming pod.
```

Прочети го: `0/3 nodes are available` казва, че от трите възела нито един не върши работа. И дава причината за всеки: един възел има taint, който Pod-ът не толерира (*untolerated taint*; това е контролният), а другите два „не съвпадат с ограниченията за разпределение по топология“ (*didn't match pod topology spread constraints*). Точно това, което беше обявено: контролният възел се брои като домейн с нула Pod-а, глобалният минимум е 0 и поставянето на третата реплика в кой да е от другите два би дало асиметрия 2.

Поправката е да приложиш отново файла, който носи `Honor`:

```text
# --- La corrección: volver a aplicar la carpeta (trae Honor) ---

$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor configured

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS        RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-574b5b6c4c-25h2z   1/1     Terminating   0          18s   10.244.1.9    curso-k8s-l9-worker    <none>           <none>
revisor-574b5b6c4c-mnskb   1/1     Terminating   0          15s   10.244.2.9    curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running       0          6s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-76td2   1/1     Running       0          2s    10.244.1.11   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running       0          4s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
(espera de 75 s: la ventana de bajada del autoescalador es de 60 s)
```

С `Honor` контролният възел излиза от сметката: три реплики в два домейна, 2 + 1, асиметрия 1. Събира се. И тъй като `apply -k` не носи `replicas`, числото живее в Deployment-а, докато HPA го коригира: след прозореца за намаляване от 60 секунди (на показ, 75 изчакване) HPA връща броя на 2, което е онова, което натоварването иска.

```text
$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           4m11s
deployment.apps/revisor   2/2     2            2           4m11s

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          2m5s

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          82s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          80s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

### 9.6 С натоварване автоматичният механизъм вдига

#### 9.6.1 Натоварване, което може да се изключи

За да видиш автоматичния скалиращ механизъм да работи, трябва натоварване, а натоварването трябва да може да се изключи, когато поискаш. Това е **програма**: `carga.yaml`.

```yaml
# carga.yaml — Lección 9: genera carga contra el revisor para ver subir el HPA.
# No forma parte del proyecto: se aplica con -f, se observa y se borra.
apiVersion: batch/v1
kind: Job
metadata:
  name: carga
  namespace: revisor
spec:
  parallelism: 4
  backoffLimit: 0
  activeDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app: carga
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
      - name: carga
        image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
        command: ["sh", "-c", "while true; do curl -s -o /dev/null http://revisor/salud; done"]
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 200m, memory: 32Mi}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

Това е `Job`, обектът от Урок 8 за задачи, които приключват, с четири Pod-а паралелно (`parallelism: 4`), които повтарят без прекъсване една заявка към `http://revisor/salud`. Няма пауза между едната и другата: всеки Pod пита, получава и пита отново. Чете се по решения:

- **`activeDeadlineSeconds: 600`**: каквото и да става, Job-ът спира след 10 минути: трябва да преживее тегленето на образа плюс 200-те секунди наблюдение. Генератор на натоварване без спирачка е повреда в очакване; този приключва, дори да забравиш да го изтриеш.
- **`backoffLimit: 0`**: ако един Pod се провали, не се опитва отново. Това е лабораторно натоварване, не задача, която има значение.
- **`acceso-revisor: permitido`**: етикетът, който затворената мрежа от Урок 7 изисква, за да се стигне до `revisor`. Без него Pod-овете на натоварването не биха стигнали доникъде и HPA не би видял никакво натоварване. Това е същото разрешение като на Pod-а `depurar`.
- **`limits: cpu: 200m`**: всеки Pod на натоварването може да консумира до една пета от ядро. Това поставя **таван на натоварването, което може да се генерира**: четири Pod-а по 200m са общо 800m, а колко от това се превръща в CPU на `revisor`, зависи от това колко заявки в секунда успява да отговори. Не е тест на производителността; това е лост с ограничител.
- **Образът на `curl`, фиксиран чрез отпечатъка му**, както в Урок 3. Първия път, когато един възел го ползва, го тегли от интернет; затова скриптът изчаква (на показ) Pod-овете на натоварването да са готови, преди да започне да гледа часовника.

#### 9.6.2 Прилагане, изчакване, гледане

```text
$ kubectl apply -f carga.yaml
job.batch/carga created
(espera visible: hasta 600 s a que los Pods de carga arranquen; la primera vez descargan la imagen de curl)
```

После идва изчакване с `kubectl wait`, по причината отгоре: докато Pod-овете на натоварването не са `Ready`, няма натоварване и да гледаш HPA преди това би било да измерваш тишината.

```text
$ kubectl wait --for=condition=Ready pod -l app=carga -n revisor --timeout=600s
pod/carga-29s8s condition met
pod/carga-bz6zl condition met
pod/carga-nv5tb condition met
pod/carga-rnhz5 condition met
```

Сега времето тече. Скриптът отпечатва ред от HPA на всеки 20 секунди в продължение на 200 секунди. В твоя терминал еквивалентът е `kubectl get hpa revisor -n revisor --watch` (който отпечатва нов ред всеки път, когато нещо се промени), или цикъл от `get` и `sleep 20` като този на скрипта. Чакането е част от урока: автоматичният скалиращ механизъм не е мигновен и да видиш колко се бави е онова, което се учи.

```text
(un renglón del HPA cada 20 s, durante 200 s; empieza a las 17:18:00)
[+ 20s] revisor   Deployment/revisor   cpu: 27%/50%   2     6     2     2m50s
[+ 40s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     2     3m10s
[+ 60s] revisor   Deployment/revisor   cpu: 72%/50%   2     6     2     3m30s
[+ 80s] revisor   Deployment/revisor   cpu: 58%/50%   2     6     3     3m51s
[+100s] revisor   Deployment/revisor   cpu: 44%/50%   2     6     4     4m11s
[+120s] revisor   Deployment/revisor   cpu: 46%/50%   2     6     4     4m31s
[+140s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     4m51s
[+160s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m11s
[+180s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m31s
[+200s] revisor   Deployment/revisor   cpu: 38%/50%   2     6     4     5m52s
```

Всеки ред се чете еднакво: времето от началото на натоварването, името, целта, колоната `TARGETS` (`текущо използване / цел`), долната граница, горната граница, репликите и възрастта на HPA. Трябва да ги четеш с формулата от 9.3 в ръка.

Редовете, с формулата от 9.3, приложена към всеки:

| Време | Измерено използване | Реплики | Отношение (използване ÷ 50) | Сметка | Какво прави |
|---|---|---|---|---|---|
| +20 s | 27 % | 2 | 0.54 | — | натоварването едва пристига |
| +40 s | 46 % | 2 | 0.92 | в рамките на 0.9 до 1.1 | нищо: толерансът го спира |
| +60 s | 72 % | 2 | 1.44 | `ceil(2 × 1.44)` = `ceil(2.88)` = 3 | решава да вдигне до 3 |
| +80 s | 58 % | 3 | 1.16 | `ceil(3 × 1.16)` = `ceil(3.48)` = 4 | решава да вдигне до 4 |
| +100 s | 44 % | 4 | 0.88 | `ceil(4 × 0.88)` = `ceil(3.52)` = 4 | остава на 4 |
| +120 s | 46 % | 4 | 0.92 | в рамките на толеранса | нищо |
| +140 до +200 s | 38 % | 4 | 0.76 | `ceil(4 × 0.76)` = `ceil(3.04)` = 4 | остава на 4 |

Има три неща за забелязване. **Първо**: редът на +40 секунди, с 46 %, не прави нищо, въпреки че натоварването вече е връхлетяло. Не е бавност, а толерансът: 46 % е с 8 % под целта, в рамките на 10 %, които контролерът прощава. **Второ**: на +60 s използването е 72 % с 2 реплики и автоматичният механизъм решава да вдигне до 3; редът на +80 s вече показва 3, защото между един ред и друг минават 20 секунди и решението е взето в интервала. Промяната от 3 на 4 е отделена от първата с около 30 секунди (събитията по-долу казват преди `2m37s` и преди `2m7s`), вероятно защото новите Pod-ове трябва да се родят и да започнат да работят, преди консумацията им да се брои. **Трето**, и най-поучително: от +140 до +200 секунди използването остава на 38 % с 4 реплики, отношение 0.76, което е **извън** толеранса отдолу, и все пак автоматичният механизъм не сваля. Сметката обяснява защо: `ceil(4 × 0.76)` е `ceil(3.04)`, което е 4. Закръглянето нагоре задържа четвъртата реплика за четири стотни. Системата се стабилизира сама: всяка нова реплика разпредели натоварването, средното спадна от 72 на 38 % и с това средно четири реплики са числото, което формулата иска. Горната граница от 6 не беше докосната.

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-4q7wh   1/1     Running   0          2m5s    10.244.2.13   curso-k8s-l9-worker2   <none>           <none>
revisor-767bdf965b-5b6k9   1/1     Running   0          5m9s    10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-pchj4   1/1     Running   0          2m36s   10.244.1.14   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          5m7s    10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-4q7wh   18m          6Mi             
revisor-767bdf965b-5b6k9   19m          7Mi             
revisor-767bdf965b-pchj4   20m          7Mi             
revisor-767bdf965b-vcznx   20m          6Mi             
$ kubectl get hpa revisor -n revisor -o jsonpath='réplicas={.status.currentReplicas} deseadas={.status.desiredReplicas} cpu={.status.currentMetrics[0].resource.current.averageUtilization} % ({.status.currentMetrics[0].resource.current.averageValue}){"\n"}'
réplicas=4 deseadas=4 cpu=38 % (19m)
```

`kubectl top pods` показва реалната консумация на всяка реплика в мига на запитването: 18, 19, 20 и 20 милиядра. Спрямо `50m`, които всяка е поискала, са 36 до 40 %. А HPA, със собствено запитване, го казва в един ред: `cpu=38 % (19m)` е „средно използване 38 %, което се равнява на 19 милиядра на Pod“. Сметката може да се направи на ръка: (18 + 19 + 20 + 20) ÷ 4 = 19.25 милиядра, което се закръглява на `19m`, а 19 ÷ 50 е 0.38. Колоната `TARGETS` не е загадка: това е тази делба. `réplicas=4 deseadas=4` казва онова, което вече се видя: каквото има, е каквото формулата иска.

Събитията на HPA са неговият лог и разказват същото с други думи:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                    From                       Message
  ----     ------                        ----                   ----                       -------
  Normal   SuccessfulRescale             5m54s                  horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  4m54s (x3 over 5m39s)  horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             4m39s                  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             2m37s                  horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m7s                   horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
```

Прочети ги отдолу нагоре, от най-старото към най-новото. `SuccessfulRescale … New size: 2; reason: Current number of replicas below Spec.MinReplicas` е първото нагаждане, това от 9.5: долната граница. Двете `Warning`, които следват (`FailedGetResourceMetric`, `FailedComputeMetricsReplicas`), са автоматичният механизъм, който казва, че още няма метрики от новите Pod-ове: `unable to get metrics for resource cpu: no metrics returned from resource metrics API`. Нормални са в първите секунди от живота на един Pod, докато `metrics-server` прави първото си четене; `(x3 over 5m39s)` казва, че са се повторили три пъти. Следващото, `New size: 2; reason: All metrics below target`, не е от това натоварване: това е HPA, който връща на 2 третата реплика, поискана на ръка в 9.5.4. А последните две, с разлика от 30 секунди (преди `2m37s` и преди `2m7s`), са решенията на този раздел: `New size: 3` и `New size: 4`, и двете с причина `cpu resource utilization (percentage of request) above target`: консумацията, измерена като процент от заявката, над целта.

### 9.7 Без натоварване сваля, след прозореца

Job-ът се изтрива и HPA се гледа на всеки 20 секунди в продължение на 260 секунди. Онова, което ще се види, е прозорецът за намаляване от 9.3.3:

```text
$ kubectl delete -f carga.yaml
job.batch "carga" deleted from revisor namespace

(un renglón del HPA cada 20 s, durante 260 s; empieza a las 17:21:25)
[+ 20s] revisor   Deployment/revisor   cpu: 36%/50%   2     6     4     6m15s
[+ 40s] revisor   Deployment/revisor   cpu: 39%/50%   2     6     4     6m35s
[+ 60s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     6m55s
[+ 80s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     4     7m15s
[+100s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     4     7m35s
[+120s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     7m56s
[+140s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     8m16s
[+160s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m36s
[+180s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     8m56s
[+200s] revisor   Deployment/revisor   cpu: 4%/50%   2     6     2     9m16s
[+220s] revisor   Deployment/revisor   cpu: 3%/50%   2     6     2     9m36s
[+240s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     9m56s
[+260s] revisor   Deployment/revisor   cpu: 2%/50%   2     6     2     10m
```

Часовникът се чете така. Job-ът се изтрива в секунда 0, но четенията на +20 и +40 остават високи (36 % и 39 %): най-вероятно Pod-овете на натоварването се бавят няколко секунди да приключат, а `metrics-server` усреднява консумацията на кратък прозорец, не на един миг. На +60 s четенето вече е 3 % и остава там. С 4 реплики и 3 % използване сметката е `ceil(4 × 0.06)` = `ceil(0.24)` = 1, но долната граница е 2, така че онова, което автоматичният механизъм *иска*, е 2. И все пак колоната с репликите казва 4 на +60, +80 и +100 и не минава на 2 до реда на +120. Тази разлика е прозорецът за намаляване от 60 секунди от 9.3.3: през тази минута HPA не използва днешната препоръка, а най-високата от последните 60 секунди, а последната препоръка за 4 реплики е направена с високите четения от началото.

Събитията дават часовете по-точно от таблицата. За да ги прочетеш, трябва да извадиш от момента, в който е пуснат `describe` (точно след края на таблицата, около 262 секунди след изтриването на Job-а): `New size: 3` се случи преди `2m54s`, тоест около +88 s, а `New size: 2` — преди `2m39s`, около +103 s. Значи свалянето стана на две стъпала, от 4 на 3 и 15 секунди по-късно от 3 на 2, на около 50 или 60 секунди от последното високо четене. Това е очакваното от един прозорец: препоръките от високата част излизат от него една по една. (Таблицата никога не показва стъпалото на 3, защото колоната `REPLICAS` на HPA се обновява със закъснение спрямо Deployment-а: тя е `status.currentReplicas`, което HPA записва в собствения си оборот на всеки 15 s; затова редът на +100 още казва 4, въпреки че събитието за сваляне до 3 е на +88. Кое число вижда HPA във всеки оборот, не е измерено.)

Още два обекта от `describe` допълват четенето. Таблицата с условията:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Conditions:/,/Events:/p'
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScaledToZero    False   NotScaledToZero   the HPA controller did not scale the workload to zero
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
Events:
```

`ScalingLimited True TooFewReplicas: the desired replica count is less than the minimum replica count` е HPA, който казва с всички букви онова, което беше пресметнато отгоре: това, което формулата иска (1), е **по-малко** от долната граница (2) и затова остава на 2. `ScalingActive True ValidMetricFound` казва, че може да пресмята, тоест че `metrics-server` продължава да отговаря. Това е таблицата, която се гледа, когато един HPA „не прави нищо“ и трябва да се знае дали е, защото не може, или защото не иска. И реалната консумация на двете останали реплики:

```text
$ kubectl top pods -n revisor -l app=revisor
NAME                       CPU(cores)   MEMORY(bytes)   
revisor-767bdf965b-5b6k9   1m           6Mi             
revisor-767bdf965b-vcznx   1m           5Mi             
```

По едно милиядро на всяка: натоварването наистина си отиде. Пълните събития и репликите, които остават:

```text
$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason                        Age                   From                       Message
  ----     ------                        ----                  ----                       -------
  Normal   SuccessfulRescale             10m                   horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
  Warning  FailedGetResourceMetric       9m17s (x3 over 10m)   horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  9m17s (x3 over 10m)   horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             7m                    horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             6m30s                 horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             2m54s                 horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             2m39s (x2 over 9m2s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-767bdf965b-5b6k9   1/1     Running   0          9m33s   10.244.1.10   curso-k8s-l9-worker    <none>           <none>
revisor-767bdf965b-vcznx   1/1     Running   0          9m31s   10.244.2.10   curso-k8s-l9-worker2   <none>           <none>
```

Събитието `New size: 2; reason: All metrics below target` („всички метрики под целта“) е свалянето. А двете реплики, които остават, са по една във всеки работен възел: ограничението за разпределение от 9.4 продължава да е изпълнено, след като са махнати два Pod-а.

### 9.8 Кой командва репликите

Deployment-ът има `replicas` празно във файла, но продължава да има число. Какво става, ако някой друг го промени на ръка? Проверява се с `kubectl scale`, който записва броя на репликите в Deployment-а, същото поле, което записва HPA:

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

Четиридесет секунди по-късно Deployment-ът отново има 2 реплики и последното събитие на HPA го казва: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`. HPA не спори и не пита: в следващия си оборот видя, че Deployment-ът има по-малко реплики от долната граница, и го върна. Това отговаря на един практичен въпрос: **при активен HPA `kubectl scale` върши малко работа**. Ако свалиш под долната граница, HPA те коригира; ако вдигнеш над онова, което натоварването иска, те коригира надолу веднага щом мине прозорецът (9.5.4 го показа с третата реплика: на 75-ата секунда Deployment-ът вече беше върнат на 2). За да промениш броя на репликите при жив HPA, трябва да промениш HPA: неговия `minReplicas` или `maxReplicas`. Който иска двама собственици за едно и също число, има проблема от 9.3.4.

### 9.9 Обновяване и измерване на прекъсването

#### 9.9.1 Как обновява един Deployment

Когато промениш шаблона на Pod-овете на един Deployment (образа, една променлива, един `preStop`), не се спират всички реплики, за да се пуснат други. Deployment-ът създава нов `ReplicaSet` за новия шаблон и започва да премества реплики от стария към новия, по малко. Документацията го описва така: новото състояние се декларира чрез обновяване на шаблона, „създава се нов ReplicaSet и Deployment-ът го мащабира нагоре, докато намалява стария, като гарантира, че Pod-овете се сменят с контролиран ритъм“ ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). Две числа управляват този ритъм и са в Deployment-а от 9.5:

- **`maxSurge`**: колко Pod-а **повече** могат да се създадат над желаното число по време на обновяването. Документацията: „максималният брой Pod-ове, които могат да се създадат над желания брой Pod-ове“, като число или процент; стойността по подразбиране е 25 %.
- **`maxUnavailable`**: колко Pod-а могат да се загубят, тоест да са **недостъпни**, по време на обновяването. По подразбиране също 25 %; документацията уточнява, че не може да е 0, ако `maxSurge` е 0 (иначе обновяването не би могло да напредне).

`revisor` ги фиксира на `maxSurge: 1` и `maxUnavailable: 0`. Чете се като правило за сигурност: „не махай реплика, която отговаря, докато няма друга, нова, готова да я замести“. С две реплики Deployment-ът създава **една** нова реплика (третата, заради `maxSurge`), изчаква да е готова и едва тогава спира една стара; после повтаря с другата. В нито един момент няма по-малко от две налични реплики. Това е частта от обновяването, която Kubernetes умее сам, и затова `rollout status` отпечатва `1 out of 2 new replicas have been updated`: брои новите.

Но „наличен“ е дума от контролната равнина. Онова, което усещат заявките, е друго нещо, и разликата се нарича *надпревара*.

#### 9.9.2 Надпреварата при спирането

Когато Deployment-ът реши да махне една стара реплика, тя минава през стъпките, които документацията за жизнения цикъл на един Pod описва като потока на прекратяване ([Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)):

1. Pod-ът се маркира като *прекратяващ се* в API със срок (по подразбиране 30 секунди; този на `revisor` е 15).
2. Във възела `kubelet` вижда маркировката и започва локалното спиране: ако контейнерът декларира куката `preStop`, първо я изпълнява. После средата за изпълнение на контейнери праща сигнала `TERM` на процес 1 на всеки контейнер и процесът има каквото остане от срока, за да приключи. Ако е още жив, когато срокът изтече, получава `KILL`.
3. **„В същото време, в което kubelet започва подредено спиране на Pod-а“**, контролната равнина преценява дали трябва да го махне от `EndpointSlice`-овете на Service-ите, които го ползват. Документацията добавя една полезна подробност: крайна точка, която представлява Pod, който се спира, не се премахва веднага; маркира се като *прекратяваща се* и с `ready: false`, а балансьорите спират да я ползват за нормален трафик.

Стъпка 2 и стъпка 3 **не се изчакват една друга**. Това е надпреварата. Това е наблюдението на Phil Pearl от сцената, измерено в друг контекст: известието за спиране стига до процеса в същия миг, в който започва да върви новината „махни го от списъка“, а новината трябва да пътува: от контролната равнина към `EndpointSlice`-овете, оттам към `kube-proxy` във всеки възел и оттам към мрежовите правила на всеки възел. Докато пътува, някои възли още изпращат заявки към стария Pod. Ако процесът вече е затворил порта си, като е получил `TERM`, тези заявки срещат затворена врата: `Connection refused`, или мълчание.

`revisor` си върши добре частта: като получи `TERM`, пише `recibí terminated, apagando`, довършва заявките, които има в ход, и излиза с `apagado limpio`, с вътрешен срок от 5 секунди (Урок 5 го измери). Но „довършва тези, които има в ход“ не включва „продължава да приема нови“. Спирането на `revisor` използва `Server.Shutdown` от стандартната библиотека на Go, а документацията на тази функция казва как работи: „първо затваря всички отворени портове, после затваря всички неактивни връзки и после чака“ активните връзки да приключат ([Go, `net/http`](https://pkg.go.dev/net/http#Server.Shutdown)). Входният порт се затваря **първи**. Онова, което липсва, не е дефект на `revisor`; това е време, за да стигне новината.

Откакто Pearl пише (2019), Kubernetes добави към `EndpointSlice` условията `serving` и `terminating` и позволи на `kube-proxy` да ползва крайни точки, които се прекратяват, когато не остане нито една готова. Това избягва загубата на трафик, когато *всички* крайни точки се спират, но не променя факта, че известието за спиране и изтеглянето на крайните точки пътуват по различни пътища: надпреварата продължава да съществува и тя е онази, която мери този урок.

#### 9.9.3 Паузата, която затваря надпреварата: `preStop`

Куката `preStop` се изпълнява **преди** сигнала `TERM`. Ако единственото, което прави, е да изчаква няколко секунди, процесът продължава да отговаря нормално през това чакане, докато новината „махни го от списъка“ довършва пътуването си. Когато накрая дойде `TERM`, вече никой не му праща нов трафик. Pod-ът на `revisor` няма shell (образът е минимален, от Урок 5), така че куката не може да е `sh -c "sleep 5"`; Kubernetes носи вградено действие за чакане:

```yaml
        lifecycle:
          preStop:
            sleep:
              seconds: 5
```

Това е всичко, което се добави към Deployment-а. Пет секунди е избор, не закон: трябва да стигнат, за да достигне новината до всички възли на клъстера, а колко време отнема това, зависи от размера и натоварването на клъстера. Pearl, в своя случай, препоръчваше да се чака повече от времето, което балансьорът отнема, за да се препрограмира. Паузата се брои и срещу срока за спиране: документацията казва, че времето на `preStop` е част от `terminationGracePeriodSeconds` и че ако трябва повече, срокът се вдига. Затова Deployment-ът мина от 10 на **15 секунди**: 5 пауза, до 5 за спирането на `revisor` и 5 резерв.

Всичко това е теория, докато не се измери. Измерването изисква инструмент и инструментът е програма.

#### 9.9.4 Сондирането

Измерването трябва да изпълнява три неща: да **брои** всяка заявка, не извадка; да **върви по време на** промяната, не преди, нито след; и да **различава** коя версия е отговорила и по какъв начин се е провалила всяка неуспешна заявка. Това е **програма**: `sondeo.sh`.

```bash
#!/usr/bin/env bash
# sondeo.sh — Lección 9: mide cuántas peticiones se pierden mientras haces algo.
#
# Uso:  ./sondeo.sh DURACION PAUSA HILOS [argumentos de curl]
#   DURACION  segundos que dura el sondeo
#   PAUSA     segundos entre una petición y la siguiente, en cada hilo (0 = sin pausa)
#   HILOS     cuántos ciclos de peticiones corren a la vez
#   lo demás  se le pasa a curl (por ejemplo: --retry 3 --retry-all-errors)
#
# Las peticiones salen del Pod «depurar» (curl dentro del clúster) hacia
# http://revisor/salud, es decir, por el Service, como cualquier cliente de dentro.
# Cada petición deja una línea «segundo cuerpo código rc=salida-de-curl». Al final se cuenta.
#
# 🔴 Antes de hablarle al clúster comprueba que el contexto activo es
# kind-curso-k8s-l9 y, si no, se detiene.
set -euo pipefail

[ "$(kubectl config current-context 2>/dev/null)" = kind-curso-k8s-l9 ] || { echo "contexto equivocado: no sigo" >&2; exit 1; }
[ "$#" -ge 3 ] || { echo "uso: $0 DURACION PAUSA HILOS [argumentos de curl]" >&2; exit 2; }
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
EXTRA="$*"

# Este guion corre DENTRO de depurar (por la entrada estándar de kubectl exec).
kubectl exec -i -n revisor depurar -- sh -s -- "$DURACION" "$PAUSA" "$HILOS" $EXTRA <<'DENTRO' |
DURACION="$1"; PAUSA="$2"; HILOS="$3"; shift 3
inicio=$(date +%s); fin=$((inicio + DURACION))
for h in $(seq 1 "$HILOS"); do
  (
    while [ "$(date +%s)" -lt "$fin" ]; do
      r=$(curl -s -m 2 -w ' %{http_code}' "$@" http://revisor/salud; echo " rc=$?")
      echo "$(( $(date +%s) - inicio )) $(echo $r)"
      [ "$PAUSA" = 0 ] || sleep "$PAUSA"
    done
  ) &
done
wait
DENTRO
awk '
  { rc = $NF; code = $(NF - 1); v = "-"
    if (match($0, /"version":"[0-9.]+"/)) v = substr($0, RSTART + 11, RLENGTH - 12)
    n++; cuenta[code " " rc " " v]++
    if (code != "200") { f++; if (nf < 40) { seg[nf++] = $1 } } }
  END {
    printf "peticiones=%d fallidas=%d\n", n, f
    for (k in cuenta) { split(k, a, " "); printf "  %5d  código %s  curl %s  versión %s\n", cuenta[k], a[1], a[2], a[3] }
    if (f > 0) { printf "  segundos (desde el inicio) de las primeras fallas:"; for (i = 0; i < nf; i++) printf " +%s", seg[i]; printf "\n" }
  }' | sort
```

Чете се по части.

- **Къде върви.** Цикълът от заявки върви **вътре** в Pod-а `depurar` от Урок 3, този с `curl`, който се изпраща през стандартния вход на `kubectl exec -i`. Така заявките се раждат вътре в клъстера и минават през Service-а, както тези на всеки вътрешен клиент (например планираната задача от Урок 8). **Обхват:** това измерване покрива пътя на клиент вътре в клъстера, тоест Service-а и `kube-proxy`. Не минава през Gateway на Envoy, откъдето биха влизали потребителите отвън: този компонент научава за промените на крайните точки по свой собствен начин и може да се бави повече или по-малко от `kube-proxy`, а този път не е измерен тук. Pearl е наблюдавал проблема при Ingress, не при Service, и казва, че при Service-ите прозорецът обикновено е къс. `<<'DENTRO'` с единични кавички пречи на твоя shell да интерпретира каквото и да е от този блок: изпраща се такъв, какъвто е.
- **Какво прави всяка нишка.** Цикъл, който, докато времето не изтече, иска `http://revisor/salud` с `curl -s -m 2`: тих (`-s`) и с максимум **2 секунди** на заявка (`-m 2`). `-w ' %{http_code}'` добавя накрая HTTP кода, а `echo " rc=$?"` добавя изхода на самия `curl`. Тази втора цифра има голямо значение, защото различава **как** се е провалила една заявка, а всеки начин разказва различна история (по-долу).
- **Един ред на заявка.** `echo "$(( $(date +%s) - inicio )) $(echo $r)"` събира в един ред секундата, в която е станало, тялото на отговора, кода и изхода на `curl`. Един ред на заявка пречи редовете на четирите нишки да се смесват: всеки `echo` е един-единствен запис. (`$(echo $r)` без кавички изравнява новите редове в тялото; отговорът на `revisor` носи един накрая и без този трик редът би се разделил на два.)
- **Преброяването.** Финалният `awk` групира по (код, изход на `curl`, версия, която е отговорила) и отпечатва колко е имало от всяко, и секундите на първите 40 неуспеха. „Неуспех“ е всеки код, различен от `200`, включително `000`, което е онова, което `curl` отпечатва, когато не е стигнал да получи HTTP отговор.
- **Двата начина на отказ, които ще видиш.** `curl` излиза със **7**, когато не е могъл да се свърже (`Failed to connect`): стигнал е до адрес, на който никой не слуша, или връзката е била отказана. Излиза с **28**, когато времето е изтекло (`-m 2`) без отговор. За първия може да се каже нещо конкретно: някой е отговорил „тук няма никого“. За втория — само че никой не е отговорил навреме; причината може да е в целта, в мрежата или в самия клиент.

Едно предупреждение за честност относно инструмента: Pod-ът `depurar` има лимит за CPU от `100m` и четири цикъла на `curl` без пауза го заемат изцяло. Клиент на тавана на своя CPU може да забави собствените си заявки и да произведе изтекли срокове, които не са вина на сървъра. Онова, което се мери, е *съвкупността* клиент, мрежа и сървър. Затова базовото сондиране от 9.9.5 е преди каквато и да е промяна: измерва какъв шум произвежда самото сондиране.

#### 9.9.5 Първо шумът; после обновяването с `preStop`

Преди да промениш каквото и да е, сондирането се мери срещу спокоен клъстер, за да се знае колко шум произвежда само по себе си. Това са 15 секунди, с четири нишки и без пауза. После идва първото обновяване, на манифеста такъв, какъвто е, с поставения `preStop`. Скриптът пуска сондирането във фонов режим (`&`), изчаква 3 секунди да върви, сменя образа от `1.6.0` на `1.6.1` и изчаква разгръщането да приключи:

```text
$ ./sondeo.sh 15 0 4
    172  código 200  curl rc=0  versión 1.6.0
peticiones=172 fallidas=0

$ ./sondeo.sh 45 0 4 &   # empieza a las 17:26:44
(pausa de 3 s: que el sondeo ya esté corriendo)

$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:1.6.1
deployment.apps/revisor image updated

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

# resultado del sondeo (A, con preStop):
     56  código 200  curl rc=0  versión 1.6.0
    416  código 200  curl rc=0  versión 1.6.1
peticiones=472 fallidas=0
```

`kubectl set image` сменя образа на контейнера `revisor` в Deployment-а `revisor`, без да пипа никакъв файл; това е късият път за това измерване (навикът за сигурност, по-долу, казва защо не е пътят на един истински проект). `rollout status` брои: „1 out of 2 new replicas have been updated“: от двете нови реплики една вече е обновена; и после „1 old replicas are pending termination“: една стара още не е приключила. Това е механиката на `maxSurge: 1` от 9.9.1, видяна отвън: първо една нова реплика, после се изтегля една стара, после друга нова.

Преброяването се чете така. **Базовото сондиране** направи 172 заявки за 15 секунди, 172 с код `200` и всички от версия `1.6.0`. Без откази: значи инструментът в този момент не произвежда видим шум. Но 172 заявки са малко, за да се оцени шумът: шум от 0.24 % би очаквал по-малко от един отказ в 172 заявки, така че този кръг не различава „нула“ от „няколко на хиляда“. **Обновяване A** направи 472 заявки за 45 секунди: 56 отговори версия `1.6.0` (тези преди смяната и тези, които попаднаха в стари реплики, докато напредваше) и 416 — `1.6.1`, и нито една не се провали. В нито един момент нямаше ред с друг код. Ако това беше единственият кръг, заглавието би било „нула откази от 472“. Но един кръг не стига и остатъкът от раздела съществува, за да каже защо.

#### 9.9.6 Същият експеримент, без паузата

За да се знае какво предотвратява `preStop`, трябва да се махне и да се измери същото. Маха се с пач от тип JSON, който изтрива полето `lifecycle` на първия контейнер:

```text
$ kubectl patch deployment/revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/lifecycle"}]'
deployment.apps/revisor patched
```

`op: remove` с `path` е „изтрий това поле“. Пачът променя шаблона на Pod-овете, така че предизвиква своя собствена смяна; скриптът изчаква да приключи с `rollout status` и проверява, че куката вече я няма. Проверката е тази:

```text
$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].lifecycle}{"|"}{.spec.template.spec.terminationGracePeriodSeconds}{"\n"}'
|15
```

Изходът е `|15`: преди чертата — съдържанието на `lifecycle`, което е **празно**; след нея — `terminationGracePeriodSeconds`, 15. (`|` го пише самата команда между двете полета, за да може да се види празното.) Без кука Pod-ът получава `TERM` в същия миг, в който започва спирането му.

С този шаблон обновяването се повтаря три пъти, като се върви напред-назад между двете версии, така че всеки кръг да сменя образа и да има истинска смяна:

```text
# resultado del sondeo (B, ronda 1, sin preStop, hacia 1.6.0):
      2  código 000  curl rc=7  versión -
      7  código 000  curl rc=28  versión -
     51  código 200  curl rc=0  versión 1.6.1
    403  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +7 +7 +9 +9 +9 +9 +30
peticiones=463 fallidas=9

# resultado del sondeo (B, ronda 2, sin preStop, hacia 1.6.1):
      1  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
     47  código 200  curl rc=0  versión 1.6.0
    465  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +5 +7 +7 +8 +9 +9 +10 +10 +16
peticiones=521 fallidas=9

# resultado del sondeo (B, ronda 3, sin preStop, hacia 1.6.0):
      3  código 000  curl rc=7  versión -
      8  código 000  curl rc=28  versión -
    105  código 200  curl rc=0  versión 1.6.1
    469  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +5 +5 +5 +7 +7 +8 +8 +9 +10 +10 +10
peticiones=585 fallidas=11
```

Има нови редове и всеки разказва нещо различно:

- `código 000  curl rc=7`: HTTP кодът `000` е онова, което `curl` отпечатва, когато **не е получил HTTP отговор**, а `rc=7` е собственият му изход: „Failed to connect to host“. Някой е отговорил „тук няма никого“ на връзката. Това е подписът, който би се очаквал от надпреварата от 9.9.2: една заявка е стигнала, през Service-а, до реплика, която вече е била затворила порта си.
- `código 000  curl rc=28`: `rc=28` е „Operation timeout“: минали са 2-те секунди на `-m 2` без отговор. Никой не е казал „не“; никой не е казал нищо. Случва се, когато пакетът стига до адрес, който вече не съществува (Pod-ът вече е изчезнал, а мрежата още сочи към него), или когато някой се бави твърде много да отговори. Изтеклото време има, значи, няколко възможни причини и една от тях е същата надпревара.
- Редът **„segundos (desde el inicio) de las primeras fallas“** дава секундата, броена от старта на сондирането, в която *приключи* всяка неуспешна заявка; отказ `curl 28` е бил изпратен около 2 секунди по-рано. В трите кръга без пауза отказите попадат между `+5` и `+10` секунди, освен един-два по-късни. Това е мигът, в който старите реплики се спират: `set image` беше изпратен 3 секунди след пускането на сондирането.

Сборът от трите кръга без `preStop`: 463 + 521 + 585 = 1569 заявки, от които се провалиха 9 + 9 + 11 = 29. Шест бяха `curl 7` (2, 1 и 3) и 23 бяха `curl 28` (7, 8 и 8).

#### 9.9.7 Отново с паузата, още три кръга

Папката, която носи `preStop`, се прилага отново и обновяването се повтаря още три пъти:

```text
$ kubectl apply -k . | grep -E 'deployment|horizontal'
deployment.apps/prueba unchanged
deployment.apps/revisor configured
horizontalpodautoscaler.autoscaling/revisor unchanged
```

```text
# resultado del sondeo (C, ronda 1, con preStop, hacia 1.6.1):
      4  código 000  curl rc=28  versión -
     57  código 200  curl rc=0  versión 1.6.0
    471  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +2 +2 +2 +2
peticiones=532 fallidas=4

# resultado del sondeo (C, ronda 2, con preStop, hacia 1.6.0):
     97  código 200  curl rc=0  versión 1.6.1
    515  código 200  curl rc=0  versión 1.6.0
peticiones=612 fallidas=0

# resultado del sondeo (C, ronda 3, con preStop, hacia 1.6.1):
      1  código 000  curl rc=28  versión -
     72  código 200  curl rc=0  versión 1.6.0
    360  código 200  curl rc=0  versión 1.6.1
  segundos (desde el inicio) de las primeras fallas: +25
peticiones=433 fallidas=1
```

#### 9.9.8 Какво казват седемте кръга и какво не казват

Събирайки всички кръгове от изпълнението:

| Вариант | Кръгове | Заявки | Неуспешни | `curl 7` | `curl 28` |
|---|---|---|---|---|---|
| Базово сондиране, без да се пипа нищо | 1 | 172 | 0 | 0 | 0 |
| **С** `preStop` (A и C1 до C3) | 4 | 2049 | 5 | 0 | 5 |
| **Без** `preStop` (B1 до B3) | 3 | 1569 | 29 | 6 | 23 |

С `preStop` — 5 отказа от 2049 заявки (0.24 %; 95 % интервал, метод на Wilson: 0.10 до 0.57 %). Без него — 29 от 1569 (1.85 %; 1.29 до 2.64 %). Интервалите не се припокриват, но предполагат независими заявки, а тук не са (четири нишки, които споделят клиент, и четирите отказа на кръг C1 са от един и същ миг); чети ги като указание за размера, не като гаранция. Какво позволяват тези цифри да се каже, внимателно:

1. **Отказаната връзка се появи само без паузата.** Шестте отказани връзки (`curl 7`) се случиха в кръговете без `preStop` и нито една в четирите кръга с него. Това е ефектът, който предсказва 9.9.2: без пауза една реплика затваря порта си, докато някой още ѝ праща заявки. С пауза останаха пет изтекли срока (`curl 28`), които това измерване не позволява да се припишат нито на шума, нито на остатъчна надпревара: този код има и двете възможни причини.
2. **Отказите се групират там, където се очаква.** В кръговете без пауза попадат в прозорец от около пет-шест секунди, този след `set image`. В кръговете с пауза няма откази в този прозорец: четирите от кръг C1 станаха в една и съща секунда, `+2`, тоест когато сондирането едва стартираше (`set image` се изпраща 3 секунди след пускането му), а единственият от кръг C3 попадна на `+25`, вече с обновяването в ход; не записахме кога е бил спрян всеки Pod, така че не можем да го свържем с никакъв момент. Че четирите отказа на C1 са едновременни, сочи към бавен старт на клиента (четири нишки, които започват наведнъж в един Pod с лимит от `100m` CPU на споделена и натоварена машина), но измерването не го доказва: това е хипотеза, не извод.
3. **Нула не е онова, което се измери.** Кръг A, първият, даде 0 от 472; другите три кръга с пауза дадоха 4, 0 и 1. Урок, който би казал „с `preStop` не се губи нито една заявка“, би избрал кръг A и би излъгал. Онова, което измерването подкрепя: паузата намали отказите в прозореца на обновяването до малко число, което също не е нула, а кръговете с пауза дадоха общо 5 отказа в 2049 заявки. Не знаем колко от това е шум на клиента: базовото сондиране, от 172 заявки без отказ, е твърде късо, за да се оцени.
4. **Това не е статистически тест.** Това са седем кръга от по 45 секунди, на споделена машина с много натоварване, с клиент, който дели ядрата с клъстера, който измерва. Кръговете не бяха редувани (първо A, после трите без пауза и после трите с пауза), така че вариантът и моментът вървят заедно, а натоварването на машината се промени по време на работата; за да се разделят двата ефекта, трябва да се редува със и без пауза. Цифрите служат за сравняване на варианти в това изпълнение; не за обещаване на процент в твоя клъстер. Онова, което се пренася, е методът: да броиш всички заявки, да различаваш как се провалят, да повтаряш и да не вярваш на един-единствен кръг.

Паузата от 5 секунди, значи, затваря частта от надпреварата, която може да се затвори с пауза. Не е гаранция: самата документация на куките казва, че доставката им е „поне веднъж“ и че няма повече обещание. И има един източник на откази, който никоя пауза не докосва: падането на един възел, което идва в 9.12.

### 9.10 Историята и връщането назад

#### 9.10.1 Един ReplicaSet за версия

Всеки път, когато шаблонът на Deployment-а се променя, Deployment-ът създава нов `ReplicaSet`, а старият остава там, с нула реплики, вместо да се изтрие. Всеки от тези ReplicaSet-и пази шаблона на една версия: образа ѝ, probes-ите ѝ, `preStop`-а ѝ. Това прави възможно връщането назад и документацията го казва без заобикалки: „конфигурацията на всяка ревизия на Deployment-а се пази в неговите ReplicaSet-и; следователно, щом един стар ReplicaSet бъде изтрит, се губи възможността да се върнеш към тази ревизия“. Колко се пазят, решава `.spec.revisionHistoryLimit`, който е 10 по подразбиране.

Можеш да сложиш коментар на всяка ревизия с анотация, `kubernetes.io/change-cause`, която `rollout history` показва в колона. Документацията казва, че може да се сложи с `kubectl annotate`, като се редактира манифестът или с инструменти, които го правят сами, и че флагът `--record`, който преди я попълваше, е отпаднал и ще бъде премахнат. Прилага се към текущата ревизия:

```text
$ kubectl annotate deployment/revisor -n revisor kubernetes.io/change-cause='ronda de pruebas de la Leccion 9' --overwrite
deployment.apps/revisor annotated

$ kubectl rollout history deployment/revisor -n revisor
deployment.apps/revisor 
REVISION  CHANGE-CAUSE
1         <none>
3         <none>
8         <none>
9         <none>
12        <none>
13        ronda de pruebas de la Leccion 9
```

Колоната `CHANGE-CAUSE` има текст само в текущата ревизия, защото анотацията се копира в една ревизия, когато тя се създава, а останалите вече са съществували. Номерата на ревизиите не е нужно да са последователни: тук са 1, 3, 8, 9, 12 и 13. Всеки път, когато шаблонът отново е идентичен с този на ReplicaSet, който вече е съществувал, Deployment-ът **преизползва** този ReplicaSet и му дава най-новия номер на ревизия, така че междинните ревизии, които са станали „същата“, изчезват от списъка. ReplicaSet-ите потвърждават сметката:

```text
$ kubectl get replicasets -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-574b5b6c4c   0         0         0       16m
revisor-5978745747   0         0         0       4m33s
revisor-5cc67d8975   2         2         2       5m33s
revisor-67b97d67c9   0         0         0       18m
revisor-767bdf965b   0         0         0       16m
revisor-7f759cd976   0         0         0       4m51s
(imagen actual: curso-docker-revisor:1.6.1)
```

Шест ReplicaSet-а, по един за всеки различен шаблон, минал през Deployment-а в това изпълнение: с `preStop` и без него, с една версия или с друга, с `nodeTaintsPolicy` и без него. Само един има реплики. Другите пет са историята.

#### 9.10.2 `rollout undo`

`rollout undo` води Deployment-а към предишната ревизия. Не изпълнява нищо специално: записва в Deployment-а шаблона на предишния ReplicaSet и Deployment-ът прави същата постепенна смяна както винаги, но наобратно.

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back
```

Предупреждението (`Warning: resource deployments/revisor was previously managed with 'kubectl apply'…`) заслужава да се прочете цялото. Казва, че връщането назад **не обновява** анотацията `last-applied-configuration`, тази, която пази последното състояние, което си приложил с `kubectl apply`, и че това „може да причини неочаквано поведение при бъдещи `kubectl apply`“. Преведено: твоят файл казва едно, клъстерът се е върнал на друго и следващият `apply -k .` ще направи свое собствено сравнение и може да развали твоето връщане назад. `rollout undo` е инструмент за гасене на пожар; истинската поправка е да промениш файла и да го приложиш. Документацията на `kubectl` го подсказва със същите думи в края на предупреждението: „помисли дали да не използваш `kubectl apply` с предишния си конфигурационен файл“.

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out
```

#### 9.10.3 Кога наистина приключва

`rollout status` каза `successfully rolled out`. Не е ли останало нищо от версията, която махна? Гледа се с колоната, която трябва, тази, която скриптът носи във всичките си списъци на Pod-ове:

```text
$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-5cc67d8975-qbzsl   curso-docker-revisor:1.6.1   curso-k8s-l9-worker2   2026-10-21T23:32:40Z
revisor-5cc67d8975-ttszb   curso-docker-revisor:1.6.1   curso-k8s-l9-worker    2026-10-21T23:32:37Z
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>
```

Виж колоната `BORRANDOSE`: това е полето `deletionTimestamp` на Pod-а, часът (в UTC), в който клъстерът му е наредил да приключи. Pod-овете на `1.6.1` го имат: приключват, още са в паузата си на `preStop` (срокът от 15 секунди още не е изтекъл) и **продължават да отговарят**. Pod-овете на `1.6.0` го нямат: това са живите в момента. `rollout status` приключи, защото Deployment-ът вече изпълнява онова, което му е поискано (желаните реплики на добрата версия са готови, а лошите вече са маркирани да приключат), а не защото последният лош Pod е свършил да умира. Заявките го показват:

```text
$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.1"}
```

Четири от шестте отговора казват `1.6.1`: **версията, която току-що махна**. Само два казват `1.6.0`, тази, която остана. Ако в този момент беше заключил, че `undo` не е проработил, щеше да сгрешиш. Това е същата надпревара от 9.9.2, видяна от връщането назад: изтеглянето на крайните точки се бави малко, докато стигне до всички. Дванайсет секунди по-късно, с изтекла пауза:

```text
(espera de 12 s: que termine el preStop de los Pods viejos)

$ kubectl get pods -n revisor -l app=revisor -o custom-columns=POD:.metadata.name,IMAGEN:.spec.containers[0].image,NODO:.spec.nodeName,BORRANDOSE:.metadata.deletionTimestamp
POD                        IMAGEN                       NODO                   BORRANDOSE
revisor-767bdf965b-58sd9   curso-docker-revisor:1.6.0   curso-k8s-l9-worker2   <none>
revisor-767bdf965b-jzpxs   curso-docker-revisor:1.6.0   curso-k8s-l9-worker    <none>

$ kubectl exec -n revisor depurar -- sh -c 'for i in 1 2 3 4 5 6; do curl -s http://revisor/salud; echo; done'
{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}

{"estado":"vivo","version":"1.6.0"}
```

Вече не остава нито един ред с `BORRANDOSE` и шестте отговора казват `1.6.0`. Един `rollout undo`, който изглежда, че не е проработил, защото една заявка е отговорила със старата версия, обикновено е това: заключило се е твърде рано. Правилото: преди да решиш, че връщането назад се е провалило, погледни `deletionTimestamp` и изчакай срокът да изтече.

За да видиш какво е пазела една ревизия, `rollout history` приема `--revision=N` и показва пълния шаблон на тази версия, включително образа. Скриптът иска първата:

```text
$ kubectl rollout history deployment/revisor -n revisor --revision=1 | head -14
deployment.apps/revisor with revision #1
Pod Template:
  Labels:	app=revisor
	pod-template-hash=67b97d67c9
  Service Account:	revisor
  Containers:
   revisor:
    Image:	curso-docker-revisor:1.6.0
    Port:	8080/TCP (http)
    Host Port:	0/TCP (http)
    Limits:
      cpu:	200m
      memory:	64Mi
    Requests:
```

Това е шаблонът, с който се роди Deployment-ът в папката на Урок 8: образ `1.6.0`, без `preStop`. (Изходът се реже на 14 реда с `head`, за да се събере; остатъкът са `Requests`, probes-ите и томовете.) За да се върнеш към него, трябва да кажеш `kubectl rollout undo deployment/revisor --to-revision=1`, формата, която носи документацията.

И за да затвори кръга с дисциплината на навика за сигурност, скриптът прилага отново папката, така че клъстерът и файловете да са еднакви:

```text
$ kubectl apply -k . | grep -E 'deployment'
deployment.apps/prueba unchanged
deployment.apps/revisor unchanged
```

`unchanged`: шаблонът, който остави `undo`, е идентичен с този на файла и `apply` няма какво да прави.

#### 9.10.4 Грешката: образ, който не съществува

Една от най-честите причини за връщане назад е обновяване, което е минало зле, и не винаги заради дефект на програмата, а заради грешка при писането: тагът на образа е сгрешен или сочи към версия, която никой не е публикувал. Предизвиква се нарочно, с отделен скрипт, който си прави собствен минимален клъстер: **`fig09_02.imagen-rota.sh`**, **програма**, която се проваля нарочно. Създава `curso-k8s-l9` само с онова, което трябва (`revisor` и теста, без MetalLB и Envoy Gateway, които не участват), слага две реплики, пуска сондирането от 9.9.4 и сменя образа на `curso-docker-revisor:9.9.9`, таг, който не съществува. Изходът му е `fig09_02.imagen-rota.salida.txt`. Пуска се така, от папката на урока:

```bash
./fig09_02.imagen-rota.sh > fig09_02.imagen-rota.salida.txt 2>&1
```

Няма `ctx &&` отпред, защото създава собствен клъстер и контекстът още не съществува; носи собствените си предпазители (временен kubeconfig, контекст, проверен преди всеки `kubectl`, изтриване на клъстера при излизане). Ако вече имаш жив `curso-k8s-l9`, скриптът спира: не пипа твоя. Отнема около четири минути. Командата, която предизвиква грешката, е тази и минава добре:

```text
$ kubectl set image deployment/revisor -n revisor revisor=curso-docker-revisor:9.9.9
deployment.apps/revisor image updated
```

`image updated`, без оплаквания: `kube-apiserver` не знае дали образът съществува. Това е същата ситуация като с погрешно написания `selector` от Урок 3: валидно име, което сочи към нищо. Онова, което следва, се чете по ред, както всеки отказ.

**Първо, `rollout status`.**

```text
$ kubectl rollout status deployment/revisor -n revisor --timeout=40s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
[código de salida: 1]
(espera de 10 s: que el kubelet registre el fallo de descarga)
```

Остава на „1 out of 2 new replicas have been updated“ и, когато изтече срокът от 40 секунди, който му беше даден, излиза с `error: timed out waiting for the condition` и код 1. Забележи, че **не казва какво не е наред**: казва само, че не приключва. `rollout status` чака, а причината трябва да се търси другаде. Без `--timeout` би чакал, докато Deployment-ът обяви, че не напредва: полето `.spec.progressDeadlineSeconds`, което е 600 секунди по подразбиране, след които Deployment-ът добавя условие `Progressing` на `False` с причина `ProgressDeadlineExceeded` ([Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)). Документацията предупреждава, че Kubernetes **не прави нищо** със засъхнал Deployment освен да го отчете: не го връща сам назад.

**Второ, Pod-овете.**

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS         RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-6586779dc4-96dfn   0/1     ErrImagePull   0          50s   10.244.2.5   curso-k8s-l9-worker    <none>           <none>
revisor-85f8668b64-2tjx4   1/1     Running        0          60s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running        0          60s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>
```

Три Pod-а, не два. Двата стари (`85f8668b64`) остават `1/1 Running`. Новият (`6586779dc4`) е в `0/1 ErrImagePull`: възелът се е опитал да изтегли образа, не го е намерил и няма контейнер, който да стартира. Това е същото състояние като в Урок 2, със същия изход, и се чете по същия начин: следващата стъпка е `describe`.

**Трето, събитията на новия Pod.**

```text
$ kubectl describe pod revisor-6586779dc4-96dfn -n revisor | sed -n '/Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  50s                default-scheduler  Successfully assigned revisor/revisor-6586779dc4-96dfn to curso-k8s-l9-worker
  Normal   Pulling    13s (x3 over 50s)  kubelet            spec.containers{revisor}: Pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Failed to pull image "curso-docker-revisor:9.9.9": failed to pull and unpack image "docker.io/library/curso-docker-revisor:9.9.9": failed to resolve reference "docker.io/library/curso-docker-revisor:9.9.9": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
  Warning  Failed     12s (x3 over 50s)  kubelet            spec.containers{revisor}: Error: ErrImagePull
  Normal   BackOff    2s (x3 over 49s)   kubelet            spec.containers{revisor}: Back-off pulling image "curso-docker-revisor:9.9.9"
  Warning  Failed     2s (x3 over 49s)   kubelet            spec.containers{revisor}: Error: ImagePullBackOff
```

Събитието `Failed to pull image "curso-docker-revisor:9.9.9"` казва, с повече текст, отколкото се събира в страницата, че не е могъл да разреши `docker.io/library/curso-docker-revisor:9.9.9`: възелът е потърсил тага в Docker Hub, където не съществува, защото образът на курса живее само на твоята машина. После `ErrImagePull`, `BackOff` и `ImagePullBackOff`: `kubelet` опитва отново с все по-дълги изчаквания. `(x3 over 50s)` казва колко пъти го е опитал.

**Четвърто, какво казва Deployment-ът.**

```text
$ kubectl get deployment revisor -n revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   2/2     1            2           60s
```

`READY 2/2`, `UP-TO-DATE 1`, `AVAILABLE 2`. „Готови: 2 от 2; обновени: 1; налични: 2“. Deployment-ът направи точно онова, което му искаха `maxSurge: 1` и `maxUnavailable: 0`: създаде **една** нова реплика, изчака да е готова, за да може да изтегли една стара, и тъй като никога не стана готова, не изтегли нито една. Двете стари продължават да обслужват.

**И сондирането, което вървеше по време на цялото засядане:**

```text
# resultado del sondeo (durante toda la actualización rota):
    811  código 200  curl rc=0  versión 1.6.0
peticiones=811 fallidas=0
```

В този кръг нито една от 811-те заявки не се провали: всичките ги отговори версия `1.6.0`, старата, защото никоя стара реплика не беше изтеглена. Това е един-единствен кръг, но онова, което прави резултата възможен, е механично, не статистическо: с `maxUnavailable: 0` Deployment-ът не изтегля стара реплика, без да има готова нова, а новата така и не стана готова. Това е конкретната полза от `maxUnavailable: 0`: едно развалено обновяване засяда *без да махне онова, което работи*. Внимание какво не мери: тъй като никоя стара реплика не беше спряна, не доказва нищо и за надпреварата при спирането. Със стойността по подразбиране от 25 % един Deployment от четири реплики би си позволил да махне една, преди да има готова новата, и такава спънка би могла да се усети.

**Поправката** е причината, а инструментът е този от 9.10.2:

```text
$ kubectl rollout undo deployment/revisor -n revisor
Warning: resource deployments/revisor was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/revisor rolled back

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-85f8668b64-2tjx4   1/1     Running   0          65s   10.244.1.2   curso-k8s-l9-worker2   <none>           <none>
revisor-85f8668b64-mqqjf   1/1     Running   0          65s   10.244.2.4   curso-k8s-l9-worker    <none>           <none>

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curso-docker-revisor:1.6.0
```

`undo` връща шаблона към предишния, Pod-ът, който не стартираше, изчезва, а образът се връща на `curso-docker-revisor:1.6.0`. (Тук нямаше нито един Pod на лошата версия, който да продължи да отговаря, както в 9.10.3: никога не стана готов.) В един истински проект окончателната поправка е да оправиш тага във файла и да го приложиш; `undo` е първата помощ.

### 9.11 Поддръжка на възел: бюджетът за прекъсвания

#### 9.11.1 Два вида прекъсване

Не всичко, което отнема един Pod от услугата, е еднакво. Документацията на Kubernetes разделя **неволните прекъсвания**, които са „неизбежни случаи“ като „хардуерен отказ на машината, която държи възела“, от **доброволните**, които са действия на онзи, който управлява системата: собственикът на приложението или администраторът на клъстера, който, между другото, може да „изпразни един възел, за да го поправи или обнови“ ([Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)). Разликата има значение, защото за доброволните може да се **преговаря**: клъстерът те оставя да кажеш колко си готов да загубиш. За неволните — не: никой не пита един диск дали може да се повреди.

Инструментът за преговорите е **PodDisruptionBudget** (PDB), вторият обект на `escalado.yaml`. Документацията дефинира двете му форми: `minAvailable`, броят на Pod-овете, които трябва да останат налични след едно изселване, и `maxUnavailable`, броят, който може да стане недостъпен; декларира се едното или другото, не и двете. Този на `revisor` казва `minAvailable: 1`: с две реплики една може да си отиде, а другата трябва да остане. Състоянието му се чете:

```text
$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     17m
```

`ALLOWED DISRUPTIONS 1` е сметката, която клъстерът води в този миг: две здрави реплики, минус една, която трябва да остане на крак, оставя една, която може да се загуби. Ако една от двете спре да е здрава, това число пада на 0 и следващото изселване се отхвърля.

#### 9.11.2 Как се изпразва един възел

`kubectl drain` е заповедта „този възел отива на поддръжка“. Прави две неща, в този ред: маркира го като непланируем (`cordon`: никакъв нов Pod не идва) и изселва един по един Pod-овете, които работят в него. Документацията ([Safely Drain a Node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)) обяснява, че безопасното изселване позволява на контейнерите да приключат с ред и „спазва PodDisruptionBudget-ите, които си указал“. Дисциплината зад това, според страницата за прекъсванията: `kubectl` иска всяко изселване през API за изселване; тази заявка може да бъде временно отхвърлена и инструментът повтаря неуспешните, докато всички Pod-ове на възела приключат или изтече срок, който ти настройваш (`--timeout`). Командата на скрипта носи два флага. `--ignore-daemonsets`: документацията казва, че е нужен, когато има Pod-ове на DaemonSet (като `speaker` на MetalLB), които се оставят където са и се махат, когато възелът напусне клъстера. `--delete-emptydir-data`: приема да се загубят данните на томовете `emptyDir`, като `/datos` на `revisor`, който така или иначе умира с Pod-а.

#### 9.11.3 Грешката: бюджет без резерв

Предизвиква се с `fig09_01.pdb-estricto.yaml`, **програма**, която се проваля нарочно: същият PDB, с `minAvailable: 2`.

```yaml
# fig09_01.pdb-estricto.yaml — FALLA A PROPÓSITO: un PodDisruptionBudget que no deja
# perder NI UNA réplica (minAvailable: 2 con solo 2 réplicas). Mientras exista,
# «kubectl drain» no puede desalojar ningún Pod del revisor y se queda reintentando.
# Se deshace con: kubectl apply -k .   (escalado.yaml trae el PDB bueno)
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: revisor
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: revisor
```

Прилага се **в пространството от имена на `revisor`**, с `-n revisor`: файлът не декларира пространство, а един `apply -f` без `-n` създава обекта там, където сочи контекстът (пространството `default`), което не пази никого. Лесно е да се сгреши и се сгреши при подготовката на този урок: забравено `-n revisor`. Клъстерът не се оплаква: съобщението беше `poddisruptionbudget.policy/revisor created` вместо `configured`, добрият бюджет на пространството `revisor` остана непокътнат (`ALLOWED DISRUPTIONS 1`) и `drain` мина без пречки, сякаш експериментът не съществуваше. Подсказката беше в думата: `created` вместо `configured`. Чете се съобщението на `apply` и се проверява с `get pdb -n revisor`.

```text
$ kubectl apply -n revisor -f fig09_01.pdb-estricto.yaml
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   2               N/A               0                     17m
(el nodo que se va a vaciar: curso-k8s-l9-worker2)
```

`configured`: обектът вече съществуваше и сега казва нещо друго. `MIN AVAILABLE 2` и, цифрата, която има значение, `ALLOWED DISRUPTIONS 0`. С две реплики и задължението да се запазят две няма нито една, която може да се загуби. Сега се опитва да се изпразни един възел, с кратък срок, за да не остане скриптът да чака:

```text
$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=30s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/prueba-6899c74865-cgzkw
evicting pod metallb-system/controller-76f4cf76b7-m9mlh
evicting pod revisor/revisor-767bdf965b-58sd9
evicting pod envoy-gateway-system/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/controller-76f4cf76b7-m9mlh evicted
pod/prueba-6899c74865-cgzkw evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
pod/envoy-revisor-revisor-b269644b-867f46cd7d-8fbvq evicted
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
evicting pod revisor/revisor-767bdf965b-58sd9
There are pending pods in node "curso-k8s-l9-worker2" when an error occurred: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
pod/revisor-767bdf965b-58sd9
error: unable to drain node "curso-k8s-l9-worker2" due to error: error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s, continuing command...
There are pending nodes to be drained:
 curso-k8s-l9-worker2
error when evicting pods/"revisor-767bdf965b-58sd9" -n "revisor": global timeout reached: 30s
[código de salida: 1]
```

Чете се като театрален сценарий. Възелът се огражда (`cordoned`). Искат се изселвания на Pod-овете, които живеят там, и излизат тези, които не са защитени: `prueba`, `controller` на MetalLB и Pod-ът на Envoy, който обслужва входната точка, приключват (`evicted`). И тогава се появява, отново и отново, на всеки 5 секунди:

`error when evicting pods/"revisor-…" -n "revisor" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.`

„Pod-ът не може да бъде изселен, защото би нарушил бюджета за прекъсвания“. Клъстерът не сгреши: направи точно онова, което му поискаха. След 30 секунди срокът на `drain` изтича (`global timeout reached: 30s`) и командата излиза с код 1. Виж в какво състояние остана възелът:

```text
$ kubectl get nodes
NAME                         STATUS                     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready                      control-plane   26m   v1.37.0
curso-k8s-l9-worker          Ready                      <none>          26m   v1.37.0
curso-k8s-l9-worker2         Ready,SchedulingDisabled   <none>          26m   v1.37.0
```

`Ready,SchedulingDisabled`: още е здрав, но е **ограден**. Прекъснат `drain` оставя възела в това състояние, докато някой не го върне с `uncordon`; ако не, нито един нов Pod не попада там и това е един от начините да останеш без капацитет, без нищо да е счупено. Скриптът го връща:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
```

Поправката е да приложиш отново папката, която носи добрия PDB (`minAvailable: 1`), и да повториш `drain`. Сега `ALLOWED DISRUPTIONS` се връща на 1 и изселването на `revisor` минава:

```text
# --- La corrección: el PDB de la carpeta ---

$ kubectl apply -k . | grep -E 'poddisruption'
poddisruptionbudget.policy/revisor configured

$ kubectl get pdb revisor -n revisor
NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
revisor   1               N/A               1                     18m

$ kubectl drain curso-k8s-l9-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=120s 2>&1 | grep -v -E '^(Warning: ignoring|evicting pod kube-system)'
node/curso-k8s-l9-worker2 cordoned
evicting pod revisor/revisor-767bdf965b-58sd9
pod/revisor-767bdf965b-58sd9 evicted
node/curso-k8s-l9-worker2 drained
```

`evicted` още от първия опит, без повторения и без грешки. Но виж къде останаха репликите:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          6s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          109s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

**Двете реплики останаха в един и същ възел**, `curso-k8s-l9-worker`. Изселването на `revisor` мина (PDB позволи да се загуби една), но новата реплика се роди в единствения възел, който можеше да я приеме, и сега двете живеят заедно: загубата на този възел би отнесла цялата услуга. Най-вероятно го обяснява `Honor`: огреден възел носи taint `node.kubernetes.io/unschedulable`, а с `nodeTaintsPolicy: Honor` възлите с taint (за които Pod-ът няма толерантност) излизат от сметката на разпределението. Докато `worker2` беше ограден, единственият домейн беше `worker`, с асиметрия 0, и разпределението позволи и двете реплики там. Ограничението беше спазено; нямаше къде другаде.

#### 9.11.4 Връщане на разпределението

Възелът се връща към услугата и се изчаква да се види дали клъстерът се справя сам:

```text
$ kubectl uncordon curso-k8s-l9-worker2
node/curso-k8s-l9-worker2 uncordoned
(espera de 30 s: ¿vuelve el reparto por sí solo?)

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE     IP            NODE                  NOMINATED NODE   READINESS GATES
revisor-767bdf965b-28v89   1/1     Running   0          37s     10.244.1.32   curso-k8s-l9-worker   <none>           <none>
revisor-767bdf965b-jzpxs   1/1     Running   0          2m20s   10.244.1.28   curso-k8s-l9-worker   <none>           <none>
```

Не. Двете реплики остават заедно: нищо не ги е преместило. Това е точно ограничението от 9.4.4: ограничението за разпределение се оценява **при планирането на един Pod**, не после, а документацията казва, че няма гаранция, че продължава да се спазва, когато се махат Pod-ове, и препоръчва инструменти като *Descheduler* за ребалансиране. Без да инсталираш нищо, лекарството е да предизвикаш ново планиране, а `kubectl rollout restart` го прави: сменя репликите със същата постепенна процедура като при обновяване, а всеки нов Pod се планира с поставеното ограничение.

```text
$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          12s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          10s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

Отново по една реплика във всеки работен възел. Разпределението се поддържа с навик, не с конфигурация: след поддръжка се гледа `-o wide`.

### 9.12 Възел, който пада

Дотук всичко беше *планирано*: обновяване, което ти пускаш, поддръжка, която ти искаш. Остава другото: машината, която се изключва без предупреждение. Това е третият въпрос на директора. Отговаря се, като се изключи нарочно един от работните възли, като се измери и като се попита клъстерът кога е разбрал.

#### 9.12.1 Какво знае клъстерът и кога

Падналият възел не праща известие: спира да праща *сърдечни удари* (heartbeats). Документацията на „Node Status“ описва две форми на удар: обновявания на `.status` на възела и обекти `Lease` (наеми) в пространството `kube-node-lease`, по един за възел; `kubelet` подновява своя на всеки 10 секунди по подразбиране ([Node Status](https://kubernetes.io/docs/reference/node/node-status/)). Когато ударите спрат да пристигат, контролерът на възлите изчаква срок, `node-monitor-grace-period`, преди да декларира каквото и да е. Условието `Ready` на възела минава на `Unknown`, ако контролерът на възлите „не е чул за възела през последните `node-monitor-grace-period` (по подразбиране **50 секунди**)“. Това е срокът за откриване и е центърът на раздела.

Докато тези 50 секунди текат, контролната равнина смята, че възелът е добре. Pod-овете му фигурират като `Running` и `Ready`, адресите им още са в `EndpointSlice`-овете и Service-ите продължават да им разпределят заявки. Когато срокът изтече, стават две различни неща:

1. Възелът минава на `NotReady` (`Unknown`), а Pod-овете, които живееха там, престават да се броят за готови; адресите им се маркират `ready: false` в `EndpointSlice`-овете и Service-ът спира да ги ползва. **Тук свършва прозорецът на отказа за трафика.**
2. Възелът получава taint `node.kubernetes.io/unreachable` с ефект `NoExecute`. Pod-овете, които живеят там, имат, по подразбиране, толерантност към този taint от **300 секунди**: документацията на „Taints and Tolerations“ казва, че Kubernetes сам добавя толерантностите `not-ready` и `unreachable` с `tolerationSeconds=300` и че затова Pod-овете „остават вързани за възлите 5 минути, след като бъде открит един от тези проблеми“. След този срок Pod-овете се изселват и ReplicaSet създава заместници в друг възел. **Тук свършва прозорецът на капацитета** и трае много повече от този на отказа.

Добре е да се разделят двата прозореца, защото се бъркат. Този на **отказа** (заявки, които се губят) трае от падането на възела до момента, в който клъстерът разбира: около 50 секунди. Този на **капацитета** (услуга с една реплика по-малко) трае още 5 минути, докато се родят заместниците. Този урок мери първия, който е онзи, който усещат потребителите ти. Вторият не е измерен, защото възелът се включва отново, преди да изтече.

#### 9.12.2 Експериментът

Скриптът избира възела, който ще изключи, с условие: трябва да е възел, който **има реплика** на `revisor` и **не** е онзи, в който живее Pod-ът `depurar`, откъдето излизат заявките (ако се изключи възелът на клиента, измерването би умряло с него). С две разпределени реплики един от двата работни възела отговаря. После пуска **две** сондирания едновременно, със заявка на всеки 2 секунди и една нишка, в продължение на 100 секунди:

- първото, такова, каквото е: `./sondeo.sh 100 2 1`;
- второто, с повторни опити на клиента: `./sondeo.sh 100 2 1 --retry 3 --retry-all-errors`.

`--retry 3` иска от `curl` да повтори до 3 пъти заявка, която се е провалила, а `--retry-all-errors` разширява „провалила се“ до всяка грешка, включително изтеклите срокове; ръководството на `curl` описва чакането между повторенията: първо една секунда и после „удвоява времето за чакане“ при всяко. Ръководството нарича `--retry-all-errors` „чука“ на повторните опити и не препоръчва да се ползва по подразбиране; тук е контролиран експеримент срещу услуга, за която знаем, че е безопасно да се повтаря (`GET /salud`). С идемпотентна заявка (която може да се повтори без последствия) повторните опити са безвредни; с такава, която не е, биха били риск.

Десет секунди след пускането на сондиранията `docker stop` спира контейнера на възела, което е най-близкото, което kind има до „машината падна“: `kubelet` и всичко, което работи вътре, престават да съществуват наведнъж. Урокът изчаква 25 секунди и пита две неща: как клъстерът вижда възела и какво казват `EndpointSlice`-овете за адресите на `revisor`.

```text
$ ./sondeo.sh 100 2 1 &                                     # sin reintentos, empieza a las 17:34:53
$ ./sondeo.sh 100 2 1 --retry 3 --retry-all-errors &       # con reintentos
(pausa de 10 s: ambos sondeos ya corren)

$ docker stop curso-k8s-l9-worker
curso-k8s-l9-worker
(nodo apagado a las 17:35:04)
(espera de 25 s: el nodo ya no contesta, pero el clúster todavía no lo sabe)
[+ 25s desde docker stop] curso-k8s-l9-worker Ready
```

След 25 секунди изключване възелът още казва `Ready`. Клъстерът не знае нищо. А доказателството, че още не знае, е в крайните точки:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=true nodo=curso-k8s-l9-worker
(el nodo pasó a NotReady a los 57 s de docker stop)
```

Двете крайни точки на `revisor` фигурират `ready=true`, **включително тази, която живее в изключения възел** (`nodo=curso-k8s-l9-worker`). Всяка заявка, която Service-ът разпредели към този адрес, отива към Pod, който вече не съществува. Това е причината за отказите, записана в един ред.

Скриптът пита на всеки 3 секунди за състоянието на възела, докато го види `NotReady`, и тогава пита отново:

```text
$ kubectl get endpointslices -n revisor -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready} nodo={.nodeName}{"\n"}{end}'
10.244.2.25 ready=true nodo=curso-k8s-l9-worker2
10.244.1.33 ready=false nodo=curso-k8s-l9-worker
```

Възелът мина на `NotReady` на 57-ата секунда след изключването (срокът в документацията е 50; остатъкът събира до 5 секунди от цикъла на контролера, `node-monitor-period`, и 3 от запитването на скрипта; освен това последният удар на възела може да е бил преди изключването). И сега крайната точка на падналия възел фигурира `ready=false`: клъстерът спря да ѝ разпределя трафик. Това е моментът, в който свършва прозорецът на отказа.

#### 9.12.3 Какво измериха сондиранията

```text
# resultado SIN reintentos (los segundos cuentan desde el inicio del sondeo; docker stop fue en +10):
      7  código 000  curl rc=28  versión -
     35  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +21 +25 +29 +38 +42 +60 +64
peticiones=42 fallidas=7

# resultado CON reintentos de curl:
      1  código 000  curl rc=28  versión -
     31  código 200  curl rc=0  versión 1.6.0
  segundos (desde el inicio) de las primeras fallas: +37
peticiones=32 fallidas=1
```

Едно пояснение за заглавния ред: скриптът отбелязва „+10“, което е паузата, която е програмирал преди изключването на възела. Отпечатаният час казва, че възелът е бил изключен 11 секунди след стартирането на сондирането, защото `docker stop` отне около секунда. Следващите изчисления използват 11.

Сондирането **без повторни опити** направи 42 заявки за 100 секунди, не 50-те, които биха се събрали при ритъм от една на 2 секунди, защото всяка заявка, която се провали, заема цели 2 секунди от времето си за чакане освен паузата. Провалиха се 7, всички с `curl 28` (изтекло време, не отказана връзка: целта вече не съществуваше). Секундите на отказите, броени от началото на сондирането, са `+21 +25 +29 +38 +42 +60 +64`. Тъй като `docker stop` е бил в секунда 11 от сондирането, като се извади, се получава колко време е минало за всеки след изключването: от 10 до 53 секунди. Последният отказ, на 53-ата секунда след изключването, попада точно преди наблюдението на `NotReady` на 57-ата: седемте отказа попаднаха между 10 и 53 секунди след изключването (измерено при приключването на всяка заявка). Фактът, че не се видяха повече, не доказва, че Service-ът вече е спрял да ползва мъртвата цел: с една заявка на всеки 2 секунди и половината от тях попадайки, според модела, в живата реплика, няколко поредни могат да уцелят, без нищо да се е променило. Онова, което е измерено, е, че целта мина на `ready=false`, когато възелът фигурира `NotReady`, на 57-ата секунда.

Това са 7 отказа от 42, 17 %. Тази цифра смесва прозореца на отказа с останалата част от 100-те секунди на сондирането, така че не казва „услугата се проваля един път от шест“: казва какво стана в този експеримент. Онова, което обяснява отказите, е, че по време на прозореца (до 57 секунди, докато целта мина на `ready=false`) **една от двете крайни точки на Service-а беше мъртва**, а Service-ът разпределя между крайните си точки, без да знае коя е мъртва, така че част от заявките от този период отиваха при реплика, която вече не съществуваше. С две реплики и мъртъв възел тази част би била около половината; с четири разпределени реплики — около една четвърт; с десет — една десета. Тази пропорция (една реплика от N) е модел, не измерване на това изпълнение: измереното е 7 от 42, но тя обяснява защо „повече разпределени реплики“ скъсява щетата, без да скъси времето.

Сондирането **с повторни опити** направи 32 заявки и беше по-бавно (всеки повторен опит чака 1, 2 и 4 секунди, преди да опита пак). Провали се една, на 37-ата секунда, от 32: един отказ срещу седем при другото сондиране, срещу цената, че някои отговори се забавиха. Това е един-единствен кръг, с малък размер и с по-малко заявки от другия: подсказва, че повторните опити помагат, но не стига, за да се обещае колко заявки се възстановяват. Това е вторият лост: **повторни опити в клиента**. Работят, защото следващия път, когато `curl` пита, Service-ът може да избере живата реплика, и не работят, ако целта е една и съща (например с една-единствена реплика).

После, състоянието на клъстера в мига на включването на възела:

```text
$ kubectl get nodes
NAME                         STATUS     ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready      control-plane   29m   v1.37.0
curso-k8s-l9-worker          NotReady   <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready      <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE    IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0          114s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   0          112s   10.244.1.33   curso-k8s-l9-worker    <none>           <none>
```

С възела в `NotReady` двата Pod-а на `revisor` продължават да фигурират `Running`, включително този на изключения възел: клъстерът още не ги изселва, защото толерантността от 300 секунди не е изтекла. И няма да ги изсели: възелът се включва отново.

```text
$ docker start curso-k8s-l9-worker
curso-k8s-l9-worker

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l9-control-plane   Ready    control-plane   29m   v1.37.0
curso-k8s-l9-worker          Ready    <none>          28m   v1.37.0
curso-k8s-l9-worker2         Ready    <none>          28m   v1.37.0

$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS      AGE     IP            NODE                   NOMINATED NODE   READINESS GATES
revisor-5877db576c-8bn64   1/1     Running   0             2m16s   10.244.2.25   curso-k8s-l9-worker2   <none>           <none>
revisor-5877db576c-mf7c2   1/1     Running   1 (21s ago)   2m14s   10.244.1.4    curso-k8s-l9-worker    <none>           <none>
```

Възелът се връща на `Ready`, а Pod-ът, който живееше в него, си остава там: контейнерът се рестартира (`RESTARTS 1`), не е създаден друг Pod и мрежовият му адрес се промени (`10.244.1.4` вместо `10.244.1.33`), но е същият Pod. В това изпълнение възелът се върна много преди 300-те секунди и Pod-овете му останаха.

#### 9.12.4 Какво скъсява прозореца и какво не

| Лост | Скъсява ли? | Защо |
|---|---|---|
| **Повече реплики, разпределени между възли** | скъсява *щетата*, не времето | с N разпределени реплики моделът на разпределението очаква една от N в мъртвата (изчисление, не измерване) |
| **Повторни опити в клиента** | да, за заявки, които е безопасно да се повтарят | втория път може да попадне в жива реплика (измерено по-горе) |
| **Намаляване на `node-monitor-grace-period`** (в контролната равнина) | да, срещу цената на фалшиви тревоги | клъстерът обявява за паднал възел, който само се е забавил |
| **Probes за готовност** | не | изпълнява ги `kubelet` на самия паднал възел, който вече не докладва нищо |
| **`tolerationSeconds`** | не | решава кога се заместват Pod-овете, не кога спират да получават трафик |

Последните два реда са тези, на които най-много се вярва и които най-малко работят, и затова Упражнение 4 ги подлага на проверка. Един probe за готовност (`readinessProbe` от Урок 5) изважда един Pod от крайните точки на Service-а, когато се провали, но който задава въпроса, е `kubelet` на *този* възел. Ако целият възел е изключен, няма `kubelet`, който да пита или да докладва; клъстерът може само да изчака срокът за откриване да изтече. А `tolerationSeconds` е гратисният срок преди изселването на Pod-овете на възел, вече обявен за `unreachable`, тоест сметка, която започва *след* откриването: колкото по-кратък, толкова по-рано се заместват Pod-овете, но не изваждат по-рано мъртвите крайни точки от Service-а.

Намаляването на `node-monitor-grace-period` е единственият лост, който атакува времето, и струва фалшиви тревоги (не е добре да се намалява много: трябва да е няколко пъти по-голям от честотата, с която `kubelet` докладва; провери флага в справката на `kube-controller-manager` за твоята версия): възел със закъснение в мрежата от десет секунди би бил обявен за паднал, Pod-овете му биха се маркирали като неготови и Service-ът би спрял да ги ползва без причина. Това е флаг на `kube-controller-manager`, който в kind живее вътре в контейнера на контролния възел; не е нещо, което се сменя с `kubectl`, и този урок не го докосва.

Отговорено на директора, с онова, което е измерено в това изпълнение: **с две реплики седем от 42 заявки (17 %) се загубиха по време на прозореца на един паднал възел**, чийто последен отказ попадна 53 секунди след изключването и който свърши, когато целта мина на `ready=false`, на 57-ата. Според разпределението на Service-а бихме очаквали около половината от заявките от този прозорец да попаднат в мъртвата реплика (това е изчисление, не измерване). С повторни опити в клиента имаше един отказ от 32, но един кръг не стига, за да се обещае колко се възстановяват. Когато възелът се върне, клъстерът се възстановява сам.

#### 9.12.5 След експеримента: `<unknown>` на автоматичния скалиращ механизъм

Последният въпрос на изпълнението е дали всичко е останало, както го казват файловете, и отговорът има една подробност, която принадлежи на този урок:

```text
$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ kubectl get deployment,hpa,pdb -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           24m
deployment.apps/revisor   2/2     2            2           24m

NAME                                          REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          21m

NAME                                 MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
poddisruptionbudget.policy/revisor   1               N/A               1                     21m
```

С `sin diferencias con los archivos` клъстерът и папката съвпадат: всичко, което се направи с команди (`set image`, `patch`, `scale`, `rollout undo`), беше отменено или приложено отново. А в HPA `TARGETS` казва `cpu: <unknown>/50%`. Това е същата дума, която понякога излиза в първите секунди на 9.5.2, и е добре да се научиш да я четеш, защото е най-честият въпрос за автоматичните скалиращи механизми: **`<unknown>` значи „не знам колко консумират Pod-овете“** и има три различни причини:

1. **`metrics-server` не отговаря.** Това е причината от 9.2. Проверява се с `kubectl get apiservice v1beta1.metrics.k8s.io`: ако казва `False`, е измервателят.
2. **Pod-овете нямат `requests` за CPU.** Без тях няма спрямо какво да се пресметне процентът, а документацията казва, че автоматичният механизъм няма да прави нищо с тази метрика. Проверява се с `kubectl describe pod`.
3. **Pod-овете са нови и още нямат първо четене.** Вижда се в събитията на HPA (`kubectl describe hpa`) като `FailedGetResourceMetric … no metrics returned from resource metrics API`, същото предупреждение, което 9.6 показа в първите секунди на новите Pod-ове, и изчезва само.

В този край кандидатът е третата: изпълнението включи отново изключения възел, изчака 20 секунди и записа състоянието; Pod-ът на `revisor` от този възел се беше рестартирал миг по-рано (`RESTARTS 1`) и още нямаше четене. Измерването не различава тази причина от първата, защото в този момент не беше питан `APIService` и не беше проверено в кой възел работи `metrics-server` (ако работеше в изключения възел, щеше да е първата); онова, което може да се каже, е как да се различат. Ако е третата, стига да се изчакат няколко секунди; ако не, `<unknown>` остава. Навикът: пред един `<unknown>` първо `get apiservice`, после `describe pod` в търсене на `requests` и после часовникът.

## Навикът за сигурност от урока: граници на мащабирането и обновявания, които не събарят услугата

Таблицата с навиците на курса отрежда на този урок една фраза с две половини: **граници на мащабирането** и **обновяванията не събарят услугата**. Проверяват се с клъстера пред теб.

**Граници на мащабирането.** Един автоматичен скалиращ механизъм превръща *натоварване* в *ресурси*: повече заявки, повече реплики, повече резервирани CPU и памет. Това е точно онова, което се иска пред един понеделник в 9:00, и е точно онова, с което един нападател или една грешка може да се възползва. Клиент, който праща заявки в цикъл (Job-ът `carga` от урока е един такъв, в малък мащаб), струва на услугата все повече реплики. Без таван границата я поставя целият клъстер, а една зле възпитана услуга оставя другите без ресурси. Има три спирачки на слоеве, от най-близката до най-общата:

1. **Таванът на самия автоматичен скалиращ механизъм.** `maxReplicas: 6`. С `requests` от Урок 5 шест реплики резервират `6 × 50m = 300m` CPU и `6 × 32Mi = 192Mi` памет, число, което можеш да запишеш и да обсъдиш, вместо „каквото има“. В изпълнението на този урок автоматичният механизъм не стигна до този таван: натоварването от един Job с `curl` в цикъл се задържа на четири реплики. Таванът е парапет; не е доказано, че спира нещо, и това разграничение има значение.
2. **Кой може да генерира натоварването.** Затворената мрежа от Урок 7 пропуска към `revisor` само Pod-овете с етикета `acceso-revisor: permitido` и Envoy-ите на входната точка. Job-ът `carga` носи този етикет нарочно; без него заявките му нямаше да стигнат и автоматичният механизъм нямаше да види нищо. Който контролира входната точка, контролира кой може да вдигне сметката за CPU.
3. **Бюджетът на пространството от имена.** Съществуват обекти (`ResourceQuota`, `LimitRange`), които слагат **общ** таван на CPU, памет и брой Pod-ове на цяло пространство от имена, така че един зле настроен автоматичен скалиращ механизъм да не може да надхвърли това, дори собственият му таван да е висок. Урок 5 ги спомена и ги остави извън курса; в споделен клъстер са слоят, който наистина пази съседите.

Има и навик за онзи, който мащабира с `metrics-server`: флагът `--kubelet-insecure-tls` от 9.2 съществува само в тази лаборатория. Добре е да се запише там, където ще го види онзи, който наследи файла (коментарът на `metrics-server/kustomization.yaml` го казва), защото лабораторен флаг, който се копира в друг клъстер, е дупка в сигурността с вид на конфигурация.

**Обновяванията не събарят услугата.** Какво е направено, за да се изпълни това, и доколко го изпълнява, е съдържанието на 9.9 и 9.11:

| Компонент | Какво предотвратява | Къде се мери |
|---|---|---|
| `maxUnavailable: 0` с `maxSurge: 1` | да има по-малко реплики от желаните по време на смяната | 9.9 |
| `preStop` със `sleep` | да стигат заявки до реплика, която вече е затворила вратата си | 9.9 |
| `PodDisruptionBudget` | доброволна поддръжка да изкара повече реплики, отколкото услугата издържа | 9.11 |
| разпределение с `topologySpreadConstraints` | една-единствена машина да концентрира всички реплики | 9.4 и 9.11 |

Забележи, че фразата от таблицата с навиците казва „не събарят“, не „не губят нищо“. Измереното в 9.9 казва колко се губи със и без всеки компонент и тази цифра, с несигурността си, е онова, което се дава на питащия. Обещание за „нула“, което никой не е измерил, е по-лошо от малка цифра, която е измерена.

И още една дисциплина: урокът обновява с `kubectl set image` и `kubectl patch`, *императивни* команди, защото са късият път за измерване. В един истински проект промяната се записва във файла, преглежда се и се прилага с `kubectl apply -k .`, така че онова, което работи в клъстера, и онова, което е в хранилището, да са едно и също. Краят на изпълнението го проверява с `kubectl diff -k .`: „sin diferencias con los archivos“.

## Какво се прави погрешно

**Да оставиш `replicas` в Deployment, който се управлява от HPA.** Всеки `apply` връща на числото стойността от файла и разваля онова, което автоматичният механизъм е решил. Маха се от манифеста.

**HPA върху Pod-ове без `requests` за CPU.** Процентът се мери спрямо `requests`; без тях автоматичният механизъм няма с какво да пресмята и не прави нищо.

**Да копираш `--kubelet-insecure-tls` в истински клъстер.** Това е бързият изход, за да стартира `metrics-server` в лаборатория. В клъстер с повече хора решението е сертификатите на `kubelet` да са подписани от органа на клъстера.

**Да вярваш, че HPA реагира на разлика от няколко пункта.** В рамките на толеранса от 10 % не прави нищо. А при сваляне не използва онова, което вижда днес, а най-високото, което е препоръчал в прозореца.

**Много висока цел за CPU (90 %).** Когато автоматичният механизъм реагира, услугата вече е наситена, а новите реплики се бавят да се родят.

**`ScheduleAnyway`, когато е нужна гаранция.** Това е предпочитание: планировчикът го нарушава, ако не намери по-добро място.

**Разпределение по топология без `nodeTaintsPolicy: Honor` в клъстер с контролен възел с taint.** Работи с две реплики и оставя третата `Pending`.

**Да вярваш, че разпределението се поддържа само.** Прилага се при планирането на един Pod; една поддръжка може да остави репликите заедно и нищо не ги разделя без смяна.

**Да обновяваш без пауза преди спиране.** Една стара реплика затваря вратата си, докато мрежата още ѝ праща заявки.

**Да заключиш „без откази“ от едно-единствено късо сондиране.** Кръг без откази не доказва, че ги няма; с три кръга от всеки вариант измереното в 9.9 показва, че отказите се появяват и изчезват.

**Да вярваш, че `rollout status` значи „вече не отговаря нищо старо“.** Приключва, когато Deployment-ът изпълни поисканото (желаните реплики на новата версия са готови), не когато последният стар Pod е свършил `preStop`. Гледа се `deletionTimestamp`.

**`PodDisruptionBudget`, който не позволява да се загуби нито една реплика.** `drain` остава да повтаря и поддръжката не напредва. Бюджетът трябва да остави резерв.

**PDB без пространство от имена.** Обект с `-f` и без `-n` се създава там, където сочи контекстът, а PDB в погрешното пространство не пази никого. Чете се съобщението `created` и се проверява с `get pdb -n revisor`.

**Да разчиташ на probes, за да скъсиш падането на един възел.** Изпълнява ги `kubelet` на падналия възел; не могат да докладват нищо.

**Да вярваш, че клъстерът разбира веднага за едно падане.** Има прозорец за откриване и заявките, които попаднат в него, се губят.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред и от състоянието, в което е останал след 9.12. Преди всяка команда, която променя нещо, `ctx` трябва да успее. `correr.sh` минава през урока, не през упражненията; решенията им цитират измереното в урока или го пресмятат, и го казват. **Преди** да изпълниш или пресметнеш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще стане. Четвъртото се пише със свои думи.

### Упражнение 1 — Формулата, на ръка

С цел 50 %, `minReplicas: 2` и `maxReplicas: 6` пресметни какво би направил автоматичният скалиращ механизъм във всеки случай и кажи дали толерансът го спира:

а) 2 реплики със средно използване 63 %.
б) 3 реплики със средно използване 46 %.
в) 4 реплики със средно използване 90 %.
г) 6 реплики със средно използване 20 %, една минута след като използването е паднало.

После сравни (а) и (б) с колоната `TARGETS` и събитията от 9.6.

### Упражнение 2 — Кой командва

Без да гледаш 9.8, запиши какъв брой реплики мислиш, че ще има Deployment-ът 40 секунди след `kubectl scale deployment/revisor -n revisor --replicas=1`, и по кое събитие на HPA ще го разбереш. Изпълни командата и провери.

### Упражнение 3 — Твоето собствено сондиране

Изпълни `./sondeo.sh 45 0 4`, докато правиш `kubectl set image` между `1.6.0` и `1.6.1`, три пъти с `preStop` от папката. Запиши за всеки кръг заявките, отказите и вида на всеки отказ (`curl 7` или `curl 28`). Махни куката с `kubectl patch` (командата от 9.9.6) и повтори. Сравни своите суми с тези от урока и обясни, в три изречения, защо твоите може да се различават и какво заключение все пак подкрепят. За да разделиш ефекта на паузата от ефекта на момента, редувай вариантите (един кръг с пауза, един без, друг с...) вместо да правиш всички от единия и после всички от другия. Накрая се върни към `apply -k .`.

### Упражнение 4 — Защити решението

Един колега казва: „probes за готовност вече изкарват падналата реплика от Service-а, а `tolerationSeconds` е срокът за откриване на един възел, така че ако го намалим на 5 секунди, прекъсването на възела свършва“. В най-много пет изречения му кажи какво става в действителност, когато един възел се изключи без предупреждение, какво мери всяка от тези две настройки и какво наистина би скъсило прозореца и на каква цена.

## Решения

### Решение 1

Това е изчисление, не измерване, освен където е казано.

а) **2 реплики, 63 %.** Отношение 1.26, извън 0.9 до 1.1. `ceil(2 × 1.26)` = `ceil(2.52)` = **3**. Вдига до 3. (В 9.6, с 72 % и 2 реплики, поиска 3 по същото правило.)

б) **3 реплики, 46 %.** Отношение 0.92: в рамките на толеранса. **Не прави нищо.** Дори да нямаше толеранс, `ceil(3 × 0.92)` = `ceil(2.76)` = 3, същото число. (В 9.6, с 4 реплики и 46 %, остана на 4: същата ситуация.)

в) **4 реплики, 90 %.** Отношение 1.8. `ceil(4 × 1.8)` = `ceil(7.2)` = 8. Но `maxReplicas` е 6, така че HPA остава на **6**. Би го отбелязал в условието `ScalingLimited`, същото, което 9.7 показва за долната граница, сега за тавана; този случай не е измерен в това изпълнение, защото натоварването никога не стигна до тавана. Това е случаят на тавана: без `maxReplicas` биха били 8.

г) **6 реплики, 20 %, една минута след като използването е паднало.** Отношение 0.4. `ceil(6 × 0.4)` = `ceil(2.4)` = 3. Сметката казва 3, но прозорецът от 60 секунди казва, че се използва **най-високата** препоръка от последните 60 секунди: ако преди 59 секунди препоръката е била 6, остава 6 още един миг. Слиза, когато тази препоръка излезе от прозореца.

### Решение 2

Измерено в `correr.salida.txt`:

```text
$ kubectl scale deployment/revisor -n revisor --replicas=1
deployment.apps/revisor scaled
(espera de 40 s)

$ kubectl get deployment,hpa -n revisor
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           13m
deployment.apps/revisor   2/2     2            2           13m

NAME                                          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/revisor   Deployment/revisor   cpu: 2%/50%   2         6         2          10m

$ kubectl describe hpa revisor -n revisor | sed -n '/Events:/,$p' | tail -3
  Normal   SuccessfulRescale             3m34s                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             3m19s (x2 over 9m42s)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal   SuccessfulRescale             33s (x2 over 10m)      horizontal-pod-autoscaler  New size: 2; reason: Current number of replicas below Spec.MinReplicas
```

**Две реплики, отново.** Deployment-ът остана на 2/2 след 40 секунди и последното събитие на HPA го казва: `New size: 2; reason: Current number of replicas below Spec.MinReplicas`, отпреди `33s`. `kubectl scale` свали полето `spec.replicas` на 1; HPA, в следващия си оборот, видя, че 1 е по-малко от долната граница от 2, и го коригира. При жив автоматичен скалиращ механизъм броят на репликите е негов. Онова, което се променя, е HPA.

### Решение 3

Зависи от твоята машина и в това се състои упражнението. Сумите на това изпълнение са в 9.9.8: с `preStop` — 5 отказа от 2049 заявки в четири кръга, всички `curl 28`; без него — 29 от 1569 в три кръга, 6 от тях `curl 7`. Какво може да се каже и какво не:

- **Твоите суми няма да съвпаднат с тукашните**, защото зависят от това колко CPU е имал клиентът ти, колко натоварена е била машината ти и колко заявки е успял да направи всеки кръг (тук имаше кръгове от 433 и от 612 заявки за същото време).
- **Онова, което трябва да се повтори**, е формата: отказите без пауза се групират в секундите след `set image`, има отказани връзки (`curl 7`) само без пауза, а с пауза кръговете дават малко откази, с кръгове на нула и други с няколко изолирани.
- **Онова, което твоето измерване не подкрепя**: точен процент, нито фразата „с `preStop` не се губи нищо“. Ако един от твоите кръгове с пауза е дал нула, това не значи, че паузата елиминира отказите; значи, че този кръг не е видял нито един.
- Ако твоите кръгове с пауза не се различават от кръговете без нея, честното заключение е, че тази машина, с този клиент, няма разделителна способност, за да види разликата. Не че паузата не върши работа.

### Решение 4

Възможен отговор: „Когато един възел се изключи без предупреждение, клъстерът не разбира веднага: изчаква `node-monitor-grace-period`, 50 секунди по подразбиране, възелът да докладва. През това време крайните точки на Pod-овете на възела продължават да са маркирани като готови и Service-ът им разпределя заявки, които се губят; в изпълнението на урока се загубиха 7 от 42 и последният отказ беше 53 секунди след изключването. Probes за готовност не помагат, защото ги прави `kubelet` на този възел, който е изключен. `tolerationSeconds`, 300 секунди по подразбиране, е срокът, който клъстерът чака *след* като обяви възела за недостъпен, преди да замести Pod-овете му, така че намаляването му замества по-рано Pod-овете, но не изважда по-рано мъртвите крайни точки от Service-а. Онова, което помага, е да има повече разпределени реплики (по разпределението може да се очаква, че една заявка от всеки N попада в мъртвата), повторни опити в клиента за заявки, които могат да се повтарят, и, срещу цената на фалшиви тревоги, намаляване на `node-monitor-grace-period` в контролната равнина.“

## Изтриване на клъстера

Когато приключиш упражненията, изтрий клъстера на урока. С него си отиват MetalLB, Envoy Gateway, `metrics-server`, Pod-ът `depurar` и всичко останало:

```text
$ kind delete cluster --name curso-k8s-l9
Deleting cluster "curso-k8s-l9" ...
Deleted nodes: ["curso-k8s-l9-control-plane" "curso-k8s-l9-worker2" "curso-k8s-l9-worker"]
(borrar tardó 2 s)

$ kind get clusters | grep -c curso-k8s-l9
0
```

После изтрий `token.txt` и временната папка на `kubeconfig`, която пази администраторското удостоверение на клъстера, който току-що изтри. `rm -rf` е опасен, ако променливата е празна или сочи другаде, затова е защитен с `case`, който го пуска да работи само ако пътят е този, който е създал `mktemp` в 9.1.2:

```bash
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp en 9.1.2.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l9.?*/kubeconfig) rm -rf -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
rm -f token.txt punto-de-partida/token.txt
```

Провери и че не е останал нито един контейнер на клиент (`docker ps -a --filter name=curso-k8s-l9` не трябва да показва нищо) и че възелът, който изключи в 9.12, не е останал изключен: ако си изтрил клъстера с възела спрян, `kind delete cluster` също го маха. Ако си създал собствена мрежа на Docker, за да пускаш няколко урока едновременно, тя се изтрива след клъстера и само тя: `docker network rm <твоята-мрежа>`. Обикновената мрежа `kind` не се пипа.

## Как разбирам, че съм успял

- [ ] Пред `error: Metrics API not available` казваш какво липсва (отговарящ на API-то за метрики), а пред `x509: cannot validate certificate for … because it doesn't contain any IP SANs` казваш какво става и какво оправя флагът, и защо е само за лаборатория.
- [ ] Пресмяташ на ръка репликите, които ще поиска HPA, с `ceil(текущи × измерено ÷ цел)`, прилагаш толеранса от 10 % и го провери с колоната `TARGETS` и събитията `SuccessfulRescale`.
- [ ] Обясняваш защо Deployment-ът вече не носи `replicas` и какво показа `kubectl diff` в `replicas: 3` → `replicas: 1`.
- [ ] Обясняваш защо прозорецът за намаляване прави свалянето бавно, а вдигането бързо, и го видя по часовника.
- [ ] Четеш `FailedScheduling` от ограничение за разпределение и казваш защо контролният възел изисква `nodeTaintsPolicy: Honor`.
- [ ] Изпълняваш `./sondeo.sh`, четеш трите колони (код, изход на `curl`, версия) и казваш какво отличава един `curl 7` от един `curl 28`.
- [ ] Казваш, с твоите числа, колко се губи при едно обновяване със и без `preStop` и какви граници има твоето измерване.
- [ ] Правиш `rollout undo`, гледаш `deletionTimestamp` и казваш защо една заявка е могла да отговори с версията, която току-що си махнал.
- [ ] Предизвикваш `drain`, блокиран от PDB без резерв, четеш го и го коригираш; и казваш защо след поддръжка репликите могат да останат заедно.
- [ ] Изключваш един възел, измерваш прозореца на отказа и казваш какво го скъсява (повече разпределени реплики, повторни опити на клиента, по-малък срок за откриване в контролната равнина) и какво не (probes, `tolerationSeconds`).
- [ ] Изпълняваш `programas/09-escalar-y-actualizar/correr.sh > /tmp/mi-corrida-l9.txt 2>&1` и сравняваш с `correr.salida.txt` (не пренасочвай към този файл: той е еталонът) онова, което не се променя: `x509`, `Metrics API not available` и `MissingEndpoints`; `replicas: 3` → `replicas: 1` в `diff`; долната граница от 2 реплики, по една на възел; `FailedScheduling` с `didn't match pod topology spread constraints`; HPA, който вдига, когато надхвърли 55 %, и сваля един прозорец по-късно; двата начина на отказ на сондирането; връщането назад със заявка, която още отговаря с махнатата версия; `drain`, блокиран от строгия PDB; и възелът, който минава на `NotReady` след около 50 секунди. Точните числа на заявките, времената, имената на Pod-овете, IP адресите и разпределението на отказите между кръговете се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] Предизвикваш обновяване с образ, който не съществува, четеш `ErrImagePull` и `ImagePullBackOff`, виждаш, че Deployment-ът остава `UP-TO-DATE 1` със старите реплики налични, и го връщаш с `rollout undo`.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l9`, временната папка на `kubeconfig` вече не съществува в `/tmp` и не е останал нито един `token.txt`.

## Обобщение

Отговори, без да гледаш урока:

1. Какво липсва в новосъздаден клъстер, за да работи `kubectl top`, и защо `metrics-server` не стартира в чистия си вид в kind?
2. Каква е формулата на HPA, спрямо какво се мери процентът и какво прави толерансът?
3. Какво прави прозорецът за намаляване от 60 секунди и защо вдигането няма подобен?
4. Защо един Deployment, управляван от HPA, не бива да носи `replicas`?
5. Какво казват `maxSkew`, `DoNotSchedule` и `nodeTaintsPolicy: Honor` и какво става без последното?
6. Кои две неща стават едновременно, когато се спира един Pod, и какво затваря `preStop`?
7. Какво отличава един отказ `curl 7` от един `curl 28`?
8. Какво показа сондирането със и без `preStop` и какво не доказва?
9. Защо може да отговори версия, която току-що си махнал с `rollout undo`?
10. Какво е PDB, за какъв вид прекъсвания важи и какво става с един `drain`, когато няма резерв?
11. Колко време отне на клъстера да забележи падналия възел и какво скъсява този прозорец?
12. Какво става с услугата, когато едно обновяване сочи към образ, който не съществува, и защо?

## Източници

Всички прегледани на 21 октомври 2026 г.

- [Kubernetes, „Horizontal Pod Autoscaling“](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/): формулата `desiredReplicas`, изчислението спрямо `requests`, толерансът от 10 %, прозорецът за стабилизиране от 300 секунди по подразбиране за сваляне, политиката за поведение по подразбиране и препоръката да се махне `spec.replicas` от Deployment-а.
- [Kubernetes, „Pod Topology Spread Constraints“](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/): `topologyKey`, `maxSkew`, `whenUnsatisfiable`, `nodeTaintsPolicy`, `matchLabelKeys` с `pod-template-hash` и ограничението за Pod-ове, които се махат.
- [Kubernetes, „Pod Lifecycle“](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): потокът на прекратяване на един Pod: `preStop`, сигнал `TERM`, срок, `KILL` и паралелното изтегляне на крайните точки.
- [Kubernetes, „Container Lifecycle Hooks“](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/): трите вида куки (Exec, HTTP, Sleep) и срокът за спиране, който включва `preStop`.
- [Kubernetes, „Deployments“](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `maxSurge`, `maxUnavailable`, `rollout undo`, `--to-revision`, анотацията `kubernetes.io/change-cause`, `revisionHistoryLimit` и условието `Available`.
- [Kubernetes, „Disruptions“](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/): доброволни и неволни прекъсвания, бюджетът, който не предотвратява вторите, но ги отчита, и `kubectl drain` с API за изселване.
- [Kubernetes, „Specifying a Disruption Budget for your Application“](https://kubernetes.io/docs/tasks/run-application/configure-pdb/): `minAvailable` и `maxUnavailable`.
- [Kubernetes, „Safely Drain a Node“](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/): какво прави `kubectl drain` и защо спазва PDB; `--ignore-daemonsets`.
- [Kubernetes, „Node Status“](https://kubernetes.io/docs/reference/node/node-status/): условието `Ready` на `Unknown`, ако контролерът на възлите не знае за възела в рамките на `node-monitor-grace-period` (50 секунди по подразбиране), и ударите с `Lease`.
- [Kubernetes, „Taints and Tolerations“](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): taint-овете `not-ready` и `unreachable` и толерантностите от 300 секунди, които се добавят сами.
- [Kubernetes, „Resource metrics pipeline“](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/): Metrics API, `metrics-server` и `kubectl top`; CPU като скорост в един прозорец.
- [metrics-server, README](https://github.com/kubernetes-sigs/metrics-server): изискванията (сертификат на `kubelet`, подписан от органа на клъстера), `--kubelet-insecure-tls` „само за тестове“, и употребите и неупотребите.
- [metrics-server, бележки за v0.9.0](https://github.com/kubernetes-sigs/metrics-server/releases/tag/v0.9.0): версията, която използва урокът.
- [Phil Pearl, „Kubernetes' dirty endpoint secret and Ingress“](https://philpearl.github.io/post/k8s_ingress/) (26 юли 2019 г.): изтеглянето на крайните точки и спирането стават едновременно; паузата преди спиране.
- [Go, `net/http`, `Server.Shutdown`](https://pkg.go.dev/net/http#Server.Shutdown): подреденото спиране затваря първо отворените портове и после неактивните връзки.
- [Kubernetes, „Job“](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-termination-and-cleanup): `activeDeadlineSeconds` тече от създаването на Job-а и го прекратява каквото и да стане.
- [Kubernetes, „kube-controller-manager“](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/): `--node-monitor-grace-period` (50 s) и `--node-monitor-period` (5 s).
- [curl, „man page“](https://curl.se/docs/manpage.html): `--retry`, `--retry-all-errors` и `--max-time`.
- [curl, „libcurl error codes“](https://curl.se/libcurl/c/libcurl-errors.html): кодовете 7 и 28.

---

**Следващ:** [Урок 10 — Завършеният проект и какво се променя в истински клъстер](10-proyecto-final.md)
