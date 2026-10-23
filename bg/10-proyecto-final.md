# Урок 10 — Завършеният проект и какво се променя в истински клъстер

Понеделник, 7:50 сутринта. В 9:00 има среща с ръководството и `revisor` е демонстрацията. Отваряш лаптопа и клъстерът го няма: през почивните дни някой е обновил Docker, друг е почистил образите и контейнерите, „които вече не се ползвали“, и `kind get clusters` ти отговаря с празен списък. Имаш манифестите, които са в Git, и имаш страницата от wiki-то, която написа преди месец: „За да го стартираш, `kubectl apply -k .`“. Опитваш. Първата команда ти казва `no matches for kind "IPAddressPool"`. Повтаряш я и сега казва `failed calling webhook`. Повтаряш я трети път и почти всичко се създава, но Gateway-ът остава без адрес и не знаеш дали е, защото нещо липсва, или защото още не е минало достатъчно време. В 8:35 имаш клъстер, който *почти* работи, wiki, което не казва реда, защото когато го писа, редът „се получи от само себе си“, и неприятното подозрение, че ако те попитат „можеш ли да го вдигнеш отново?“, честният отговор е „мисля, че да, ако го повторя няколко пъти“.

Това не е отговор. Един проект е завършен, когато всеки —ти след шест месеца, нова колежка, автоматична стъпка на един *pipeline*— може да тръгне от празен клъстер, да изпълни кратка рецепта и да стигне до същото място, без да поправя нищо ръчно и знаейки какво да очаква между една стъпка и друга. Това е последният урок от курса и прави две неща. Първото: събира всичко, което изгради в предишните девет, в структура, която се разгръща с **две команди и едно изчакване**, с **Kustomize** (една база и слоеве върху нея), и го автоматизира със скрипт, който **не крие реда**. Второто е по-неудобно и затова е най-важното: казва ти направо **какво му липсва на всичко това, за да бъде нещо повече от лаборатория**.

**Време:** 2 × 45 мин

**Какво изграждаш:** пълният `revisor` —деветте урока заедно— организиран в една база и два слоя на Kustomize (платформата и проектът), който се разгръща от празен клъстер с две `kubectl apply` и едно изчакване и който един скрипт повтаря, изтрива и повтаря отново, без да поправяш нищо ръчно; освен това, написан списък с това, което му липсва, за да работи наистина

**Какво научаваш:** какво е база и какво е *overlay* в Kustomize и как се чете онова, което те сглобяват; защо платформата (нови типове, контролери и *webhooks*) идва преди проекта и какво казва клъстерът, когато този ред се наруши; какво е `kubectl apply --server-side` и коя грешка избягва; как се чака без `sleep` (с `kubectl wait`) и как се автоматизира разгръщането, без да се крие редът; финалният преглед на проекта спрямо нивото `restricted`, поле по поле; проверките на целите на курса (възел, който пада, конфигурация, която се променя, чужд Pod, мащабиране, което чете метрики); какво е Helm и кога е по-подходящ от Kustomize; и какво се променя, и какво се губи, между един клъстер на `kind` и един истински

**Откъде идваш.** От деветте предишни урока, които сега се четат като слоеве на една и съща сграда. От [Урок 2](02-pods-deployments.md): Deployment-ът, `securityContext` и образите, заредени с `kind load`. От [Урок 3](03-services-dns.md): Service-ите и Pod-ът `depurar`. От [Урок 4](04-configuracion-secretos.md): Kustomize с генератори и *хешът (hash)*, който задейства *rollout*. От [Урок 5](05-salud-recursos-apagado.md): проби (probes), `requests` и `limits`. От [Урок 6](06-entrar-al-cluster.md): MetalLB и Envoy Gateway и идеята, че платформата идва преди проекта; този урок превръща тази идея в структура от папки. От [Урок 7](07-aislar-permisos-red.md): пространството от имена `revisor` на ниво `restricted`, акаунтите с минимални права и затворената мрежа. От [Урок 8](08-datos-y-tareas.md): томът и `CronJob`-ът на отчета. От [Урок 9](09-escalar-y-actualizar.md): `metrics-server`, автоматичното мащабиране и изключването с `preStop`. Ако някой от деветте ти е останал недовършен, таблицата в 10.2 ти казва в кой файл живее всяко парче.

**Какво не прави този урок.** Не учи на нищо ново за `revisor`: всичко, което носи, вече си го изградил. Не инсталира Helm и не го изпълнява: назовава го, сравнява го с Kustomize и ти казва кога би трябвало да го ползваш. Не превръща клъстера в продукционен: точно това е, което **не** прави, а раздел 10.10 ти обяснява защо, във всеки отделен случай. И не повтаря дългите измервания от уроци 6 и 9 (колко време отнема на мащабирането да качи и да свали реплики, как се държи MetalLB отблизо): използва ги и те праща към тези уроци за подробностите.

**За изпълненията.** Всички изходи от този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1 (`kubectl version --client` казва `Kustomize Version: v5.8.1`), образа на възела `kindest/node:v1.37.0`, фиксиран чрез отпечатъка му (digest), **MetalLB v0.16.1**, **Envoy Gateway v1.9.2** (с Gateway API v1.6.1) и **metrics-server v0.9.0**, в клъстера с три възела от Урок 1, който тук се нарича `curso-k8s-l10`. Машината беше Mac с ARM процесор и Docker Engine 29.2.1 във виртуална Linux машина (Colima), **не** Linux Mint, който е референтната система на курса. Какво се променя при твоя Mint: архитектурата (`amd64` вместо `arm64`); IP адресите на Pod-овете, на Service-ите и на възлите; случайните наставки в имената, възрастите и възелът, на който попада всяка реплика; и най-вече времената, които зависят от връзката ти (възлите свалят от интернет образите на платформата) и от натоварването на машината. **Една разлика в мрежата има значение:** това изпълнение използва **собствена Docker мрежа**, `curso-k8s-red-l10` (`172.30.0.0/16`), създадена с `docker network create --subnet 172.30.0.0/16 curso-k8s-red-l10` преди първия клъстер и изтрита след последния, а всеки клъстер беше създаден с променливата `KIND_EXPERIMENTAL_DOCKER_NETWORK=curso-k8s-red-l10`. Така се направи, защото машината беше споделена и други уроци също инсталираха MetalLB: два клъстера със същия диапазон в една и съща мрежа си пречат взаимно. `kind` предупреждава за това в изхода при създаването с `WARNING: Overriding docker network…` и `Here be dragons! This is not supported currently` (променливата е експериментална). На твоята машина, с обичайната мрежа `kind` (`172.18.0.0/16` на Mint), не ти трябва нищо от това, а адресите на входната точка излизат като `172.18.255.x`: смени диапазона в `overlays/kind/metallb-pool.yaml` на `172.18.255.200-172.18.255.250` (10.1.1 и 10.6.2 обясняват защо) и там, където изходите казват `172.30.255.200`, ще четеш `172.18.255.200`. Клиентите „отвън“ в изходите се свързаха към собствената мрежа; на твоята машина — към `kind`. Пълният преглед е в [`programas/10-proyecto-final/`](../programas/10-proyecto-final): `correr.sh` създава клъстер, предизвиква двете грешки от 10.4 (всяка в нов клъстер), създава друг и преминава през 10.1 до 10.8 и Упражнения 1 до 3, изтрива го и завършва с `probar-levantar.sh` (още два клъстера). Общо пет клъстера, един по един, и петте бяха изтрити. Изходът му е `correr.salida.txt` (трите предишни изпълнения, цитирани в 10.8.3 и в Упражнение 3, са в `corridas-preparacion/`; `psa-comprobacion.sh` и `crd-tamanos.sh`, със своите `.salida.txt`, са две отделни измервания, цитирани в 10.7.3 и в 10.4.3); ще видиш там няколко реда „espera de cupo“, които са на скрипта, докато чака друг урок да освободи място на споделената машина. Цялото изпълнение отне 1755 секунди (почти половин час), от които около 6 минути бяха тези изчаквания. Създаването на клъстер, изчакването на възлите и зареждането на образите отне между 35 и 60 секунди; изчакването на платформата — 153 секунди в клъстера от 10.5, а в `probar-levantar.sh` стъпка 2 приключи на 234-та и 250-та секунда от стартирането на скрипта (самото изчакване — около 229 и 246); при едно от подготвителните изпълнения същото изчакване достигна 881 секунди (намира се в `programas/10-proyecto-final/corridas-preparacion/corrida4.txt`). Нужен е интернет.

## След урока ще можеш да

- Обясняваш със свои думи какво е **база** и какво е ***overlay*** в Kustomize, отваряш `kustomization.yaml` и казваш какви ресурси сглобява, какво им променя и как да го провериш с `kubectl kustomize`, без да докосваш клъстера.
- Различаваш едно парче от **платформата** (нови типове, контролери, *webhooks*) от едно от **проекта** и разгръщаш двете от празен клъстер с две `kubectl apply --server-side -k` и изчакване с `kubectl wait`, в правилния ред.
- Разпознаваш и разчиташ двете грешки при нарушаване на този ред: онази, която идва от прилагането на платформата без `--server-side`, и онази, която идва от събирането на платформата и проекта в една-едничка команда.
- Пишеш скрипт за разгръщане, който не крие реда —три стъпки с име, проверка на контекста преди всяка и изчаквания по условие, не по време— и го изпитваш, като създаваш, изтриваш и пресъздаваш клъстера.
- Преглеждаш проекта спрямо нивото `restricted` на *Pod Security Standards*, поле по поле и с клъстера, и обясняваш защо платформата живее в пространства от имена, които не го изпълняват.
- Измерваш какво се случва, когато се спре един работен възел (какво се проваля, за колко време и защо) и казваш какво скъсява този прозорец и какво не.
- Описваш със свои думи пет причини, поради които онова, което си изградил, не е истински клъстер, и какво би се направило за всяка.

## Защо, преди как

Досега всеки урок оставяше клъстера *малко по-далече* от мястото, откъдето е започнал: повече файлове, повече парчета, повече неща за прилагане. Това натрупване е нормално, докато учиш, и има цена, която не се вижда до понеделника от сцената: никой не е написал **на едно място** как се разгръща всичко. Уроците го казват, всеки посвоему; но един проект, който може да се възстанови само като се препрочетат девет урока, не е завършен.

Има един действителен случай, който показва защо това има значение, и той не е от Kubernetes. На 31 януари 2017 г. един инженер на GitLab изтри по погрешка директорията с данните на основната база данни на GitLab.com: около 300 GB, според публичния доклад, който компанията публикува на 10 февруари. Онова, което превръща тази история в урок за нас, е това, което последва. Компанията имаше няколко механизма за резервни копия и възстановяване на хартия и когато ги потърсили, докладът казва (в превод): „процесът на намиране и използване на резервните копия се провали напълно“. Ежедневното копие с `pg_dump` не съществуваше: папката за съхранение беше празна, защото програмата, която го правеше, беше от версия, различна от тази на базата, и завършваше с грешка, а писмата, които известяваха за тази грешка, бяха отхвърляни от сървъра на получателя, така че никой не разбра, докато не стана късно. Възстановяването стана с копие, взето шест часа по-рано по друга причина, и копирането му от тестовата среда отне около 18 часа. Бяха загубени промените, направени между 17:20 и около полунощ (UTC; докладът дава 23:30 в подробностите и 00:00 в резюмето) на този ден: според оценката им, около 5000 проекта, 5000 коментара и 700 нови акаунта.

Не се случи от липса на рецепти. Случи се, защото **никой не беше разбрал, че не работят**: резервното копие се проваляше и нищо не предупреждаваше. Рецепта за възстановяване, която никой не е изпълнил от край до край, е хипотеза, също като „мисля, че да, ако го повторя няколко пъти“. Затова този урок не се задоволява с писането на рецептата: **изпълнява я**, нарочно я чупи, изтрива и я повтаря в нов клъстер и те учи да го правиш и ти.

Урокът има десет части с понятия, а после обичайните раздели:

1. **Клъстерът на урока** (10.1): създаване със собствен `kubeconfig` и защита на контекста.
2. **Картата на папката** (10.2): какво има в `programas/10-proyecto-final/` и кой урок е добавил всяко парче.
3. **Kustomize: база и *overlays*** (10.3): как се сглобява, как се чете и как се проверява.
4. **Защо две команди и едно изчакване** (10.4): двете грешки, които учат на реда.
5. **Разгръщане ръчно** (10.5): платформа, изчакване, проект и да го видиш как работи отвън.
6. **Автоматизиране, без да се крие редът** (10.6): `levantar.sh` и изпитването със създаване, изтриване и пресъздаване.
7. **Финалният преглед спрямо `restricted`** (10.7).
8. **Проверка на целите** (10.8): възелът, който пада, конфигурацията, която се променя, чуждият Pod, мащабирането.
9. **Helm, с едно споменаване** (10.9).
10. **Какво се променя в истински клъстер** (10.10): списъкът с онова, което липсва.

Това е целта. В края на 10.5 един празен клъстер има пълния проект, а входната точка, която изгради в Урок 6, получава адрес, който MetalLB ѝ е разпределил:

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

(Тази таблица е дълга нарочно: тя е доказателството, че деветте урока са там. Ще я четеш ред по ред в 10.5.)

## Ако нямаш образите от курса по Docker

Този урок използва същите два образа като уроци 3 до 9: `curso-docker-revisor:1.6.0`, този на `revisor`, и `curso-docker-prueba:1.0.0`, този на услугата, която се проваля нарочно. Провери, че ги имаш:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

За другия — същата команда с `curso-docker-prueba:1.0.0`. Ако ти липсва някой, [Урок 3](03-services-dns.md) казва как да ги изградиш от хранилището на курса по Docker. Този урок не иска нищо ново от нито един от двата. Новото идва от интернет: манифестите на MetalLB, на Envoy Gateway и на `metrics-server` се свалят от изданията им всеки път, когато приложиш платформата, а образите на тези три компонента и този на `curl` ги сваля всеки възел при първото ползване. Трябва ти връзка.

## Понятията

### 10.1 Клъстерът на урока

#### 10.1.1 Преди да създадеш: квотата, мрежата и дискът

Този урок инсталира **MetalLB**, както Урок 6, и носи със себе си правилото му за съжителство: MetalLB разпределя IP адреси от Docker мрежата, където живеят възлите на `kind`, и два клъстера с MetalLB и същия диапазон в една и съща мрежа обявяват едни и същи адреси и си пречат. Ако работиш сам на машината си, това не те засяга: ще имаш по един клъстер наведнъж. Ако делиш машината с някого или ако имаш друг жив клъстер от курса, провери, преди да създаваш:

```bash
# ¿Hay otro clúster del curso vivo? Si lo hay y tiene MetalLB, espera a que termine.
kind get clusters
# Espacio de tu disco: si el uso pasa de 80 %, libera lo tuyo antes de seguir.
df -h /
# Cuánto ocupa Docker (imágenes, contenedores, volúmenes), para saber qué liberar.
docker system df
```

`kind get clusters` изброява клъстерите, които `kind` познава на твоята машина. Ако видиш `curso-k8s-l10` и не си го създал ти, спри: той е на някой друг. `df -h /` казва какъв процент от диска ти е зает (колоната `Use%`); `docker system df` не дава проценти: обобщава колко заемат образите, контейнерите и томовете на Docker и служи, за да знаеш какво да освободиш. Този урок създава няколко клъстера, един по един, и всеки сваля образите на платформата: няма измерена цифра за място, затова остави запас.

И една бележка за **мрежата**, която определя диапазона от адреси, защото се появява във файл от този урок. По подразбиране `kind` създава Docker мрежа на име `kind` и слага там всички възли. На Linux Mint тази мрежа обикновено е `172.18.0.0/16`. Провери:

```bash
docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}'
```

Файлът `overlays/kind/metallb-pool.yaml`, който идва с папката, казва `172.30.255.200-172.30.255.250`, диапазона на собствената мрежа, с която са направени изпълненията на този урок (обяснява го „За изпълненията“). Затова, **дори мрежата ти да е `172.18.0.0/16`, този диапазон трябва да го смениш ти**: на `172.18.255.200-172.18.255.250`, ако мрежата ти е обичайната, или с префикса на твоята мрежа, ако е друга `/16`. Това е **един ред** от един файл, а 10.6 те учи на скрипт, който проверява, че диапазонът попада в мрежата, преди да приложи каквото и да е (ако не го смениш, спира с `ALTO` и ти го казва).

#### 10.1.2 Създаване на клъстера

Създай го от `programas/10-proyecto-final/`, с обичайната грижа: собствен временен `kubeconfig`, функция, която проверява контекста преди всяка промяна, и заредени образи.

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

Две неща, които не са нови, но които този урок използва повече от всеки друг. Първото: `ctx` е **функция на терминала**, не програма. Ако `kubectl config current-context` не казва `kind-curso-k8s-l10`, тя отпечатва „contexto equivocado: no sigo“ и връща грешка; `&&` кара командата отдясно **да не се изпълни**, когато функцията се провали. Затова оттук нататък всяка команда, която **променя** нещо, се пише `ctx && kubectl apply …`. Команда, която само чете (`get`, `describe`), не се нуждае от нея, но и не пречи. Второто: `export` важи само в този терминал. Ако отвориш друг, повтори `export KUBECONFIG=…` с пътя, който отпечата `echo`, и дефинирай `ctx` отново.

И този урок има нещо, каквото предишните нямаха: **един симулиран токен, който генерираният Secret ще прочете** (Урок 4). Създава се веднъж, с права само за теб, и не се версионира (`.gitignore` на папката го изключва):

```bash
(umask 077; openssl rand -hex 16 > base/token.txt)
TOKEN="$(cat base/token.txt)"
```

Скобите правят `umask 077` да важи само за тази команда, а файлът се ражда с права `0600` (`-rw-------`): четим само от теб. Проверяваме:

```text
$ /bin/ls -l base/token.txt | cut -d' ' -f1
-rw-------

$ wc -c < base/token.txt
      33
```

Тридесет и трите байта са тридесет и двата шестнадесетични знака на `openssl rand -hex 16` плюс знакът за нов ред. И състоянието на току-що създадения клъстер, с трите му възела и двата образа вече вътре:

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

Шест реда `not yet present on node … loading...`: два образа по три възела, включително контролния. Но „loading“ не е доказателство, че образът е пристигнал. Проверка, която си струва да стане навик, е да попиташ всеки възел какви образи има, с `crictl`, инструмента на средата за изпълнение (*runtime*) на контейнери, който вече си ползвал в Урок 2:

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

Всеки от трите възела изброява двата образа, с етикета, който им сложи (`1.6.0` и `1.0.0`). `crictl` им слага отпред `docker.io/library/`, защото това е името, което `containerd` дава на образ без регистър, и не означава, че са свалени оттам. Колоната `IMAGE ID` (`70e09194319be`, `5f32d8833d958`) не съвпада с онази, която показва `docker image ls` на твоята машина (`bd1b2e7d91b8` за `revisor`): това са две различни хранилища и всяко идентифицира образа посвоему. Същото е и с размера: `crictl` казва 3.68 MB за `revisor`, а Docker — 16.2 MB; всеки инструмент мери различно и те не се сравняват помежду си. Важното е името и етикетът да са във **всеки** възел: ако липсват в един, Pod, който попадне там, ще се опита да свали образа от интернет и ще остане в `ErrImagePull`, както в Урок 2, а това е заявката, която го обяснява.

**Едно предупреждение за `kind load`.** Ако си свалил образа от регистър, не го зареждай с `kind load docker-image repo@sha256:…`. При изпитанията на курса по Docker в Hábil (kind v0.33.0, Docker 29.2.1 с хранилище containerd, процесор arm64) тази команда отговори „loading…“ без грешка и образът **стигна до възела, но без име**: `docker exec <nodo> crictl images` го показа като `docker.io/library/import-AAAA-MM-DD` с етикет `<none>` (името за запълване, което `ctr images import` дава на онова, което внася без собствена референция; датата е на часовника на възела, в UTC), а Pod, който поиска същата референция с *digest*, остана в `ErrImageNeverPull`, защото във възела няма образ с това име, макар съдържанието му да е там. Първо му сложи локален етикет (`docker tag repo@sha256:… curso-docker-revisor:1.6.0`), зареди този етикет и винаги проверявай с `crictl images`, **като гледаш и редовете `<none>`**: филтър, който пропуска само името на твоя образ (като `grep -E 'IMAGE|curso-docker'` по-горе), не ги показва. Това е измерен случай без официален източник за точно този симптом; проблемите (*issues*) на kind [#4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) и [#4224](https://github.com/kubernetes-sigs/kind/issues/4224) описват съседни неизправности (с грешка) на `kind load` с нов Docker, повечето свързани с хранилището на `containerd` на Docker (#3795 и #4066; #4224 е в OrbStack). Двата образа на този урок се зареждат по локалния им етикет (`curso-docker-revisor:1.6.0`, `curso-docker-prueba:1.0.0`), а изходът по-горе е проверката.

Празният клъстер няма никакъв тип обект, който Kubernetes не носи сам. Проверяваме, защото това е изходната точка на всичко, което следва:

```text
$ kubectl get crd
No resources found
```

`crd` е съкращението на *CustomResourceDefinition*, дефиницията на нов тип обект (видя го в Урок 6). „No resources found“ означава, че клъстерът познава само типовете, с които се ражда. Нито `Gateway`, нито `IPAddressPool`, нито `HTTPRoute` съществуват още. Именно тази празнота редът от 10.4 трябва да запълни.

### 10.2 Картата на папката

#### 10.2.1 Какво има и кой урок го е добавил

Папката `programas/10-proyecto-final/` има три неща: **базата** (проектът), **overlays** (как се инсталира в конкретен клъстер) и **скриптовете** (как се разгръща). Така изглеждат файловете на първите две:

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

(`find` обхожда папките и изброява файлове; `! -name token.txt` пропуска токена, а `sort` ги подрежда. Излиза `.gitignore`, защото `find` не крие файловете, които започват с точка.)

Всеки файл на базата е урок, който вече си направил. Тази таблица е картата; ако нещо ти е останало недовършено, ето къде да гледаш:

| Файл | Какво е | От кой урок идва |
|---|---|---|
| `base/namespace.yaml` | пространството `revisor`, на ниво `restricted` с фиксирана версия на политиката | 7 |
| `base/cuentas.yaml` | сервизните акаунти без монтирани удостоверения и ролята само за четене `observador` | 7 |
| `base/red.yaml` | шестте `NetworkPolicy`: всичко затворено и само необходимите отваряния | 7 |
| `base/revisor-deployment.yaml` | `revisor`: образ, променливи, токен като файл, probes, ресурси, подредено изключване, разпределение между възли и `securityContext` | 2, 4, 5, 7, 9 |
| `base/revisor-service.yaml` | стабилното име `revisor` вътре в клъстера | 3 |
| `base/prueba-deployment.yaml` и `base/prueba-service.yaml` | тестовата услуга, която се проваля нарочно | 2, 3, 5, 7 |
| `base/gateway.yaml` | входната точка (`Gateway`) и маршрутът (`HTTPRoute`) | 6 |
| `base/reporte.yaml` | томът на отчета и `CronJob`-ът, който го записва | 8 |
| `base/escalado.yaml` | автоматичното мащабиране (`HorizontalPodAutoscaler`) и `PodDisruptionBudget` | 9 |
| `base/kustomization.yaml` | генераторите на `ConfigMap` и на `Secret` с *hash* и списъкът на всичко предишно | 4 |
| `overlays/kind/metallb-pool.yaml` | диапазонът от адреси, които MetalLB може да разпределя | 6 |
| `overlays/kind/gatewayclass.yaml` | класът входна точка `eg`, който обслужва Envoy Gateway | 6 |
| `overlays/kind/plataforma/` | MetalLB, Envoy Gateway и `metrics-server`, всеки в своята папка | 6, 9 |

Липсват нарочно три семейства файлове. Директният `LoadBalancer` от Урок 6 (`revisor-publico`) беше изтеглен в Урок 7: единствената входна точка навън е Gateway-ът. Помощните Pod-ове —`depurar`, `intruso`, `memoria`, Job-ът за натоварване— са **инструменти за наблюдение и за предизвикване на повреди**, не част от проекта: не е нужно да присъстват във всеки клъстер, който разгръщаш, и затова `depurar.yaml` и `intruso.yaml` живеят в корена на папката, а не в базата. И токенът: той не се версионира.

#### 10.2.2 Три въпроса, за да решиш къде отива всеки файл

Редът на папките не е каприз. Всеки файл отговаря на три въпроса, в този ред:

1. **Нужен ли е на `revisor` във всеки клъстер, където се инсталира?** Тогава отива в **базата**. Deployment-ът, Service-ът, мрежовите правила и нивото `restricted` важат еднакво в `kind`, в клъстера на твоята компания или в облака.
2. **Зависи ли от *този* клъстер?** Тогава отива в един **overlay**. Диапазонът от адреси на MetalLB идва от Docker мрежата на kind; в облака нямаше да съществува, защото доставчикът дава балансьорите. Онова, което зависи от средата, не се смесва с онова, което не зависи.
3. **Инсталира ли се само веднъж на клъстер и ползват ли го няколко проекта?** Тогава е **платформа**. MetalLB, Envoy Gateway и `metrics-server` не са на `revisor`: в деня, в който публикуваш втора услуга, тя ще ползва същия клас входна точка и същия диапазон. Затова имат своя папка и своя команда.

Ще видиш, че третият въпрос не е въпрос на вкус: той решава *реда на прилагане*. Платформата носи нови типове, а проектът ги ползва. 10.4 го доказва.

### 10.3 Kustomize: база и *overlays*

#### 10.3.1 База, която не знае за никого

Вече си ползвал Kustomize в Урок 4, с генератори. Тук се ползва за онова, за което е измислен: **да композира**. [Документацията на Kubernetes](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) го определя така (в превод): **база** е директория с `kustomization.yaml`, която съдържа набор от ресурси и свързаните с тях персонализации; ***overlay*** е директория с `kustomization.yaml`, който се позовава на *други* директории с kustomization като на свои бази. И изречението, което има значение: „базата не знае нищо за един *overlay* и може да се ползва в няколко“.

Това е `kustomization.yaml` на базата. Почти всичко в него го познаваш; коментарът отгоре е нов и казва онова, което току-що прочете:

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

Три полета вършат цялата работа. `resources` е списъкът с файлове, които сглобява. `namespace: revisor` е **трансформатор**: слага това пространство от имена на всичко, което го допуска, без всеки файл да го повтаря (затова в `deployment.yaml` няма `namespace:`). А двата **генератора** създават `ConfigMap` и `Secret` с име плюс *hash* на съдържанието: ако съдържанието се промени, името се променя и Deployment-ът —който генераторът пренаписва, за да сочи към новото име— прави *rollout* сам. Това беше Урок 4.

#### 10.3.2 Overlay, който само сочи

`kustomization.yaml` на overlay-а на `kind` е по-къс от базата:

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

Три реда ресурси: базата (папката, не файл), диапазонът на MetalLB и класът входна точка. Overlay-ът **не копира** нищо от базата; само я назовава. Затова, ако утре промениш Deployment-а на `revisor`, overlay-ите не научават и не е нужно да научават. И обърни внимание на онова, което коментарът казва за `namespace:`: този overlay **не** го слага, защото би сложил `revisor` и на диапазона на MetalLB, който трябва да живее в `metallb-system`, а `GatewayClass` дори не принадлежи към пространство от имена (важи за целия клъстер). Трансформаторът на базата вече се е погрижил за своето.

За да видиш какво сглобява един overlay, без да докосваш клъстера, има `kubectl kustomize`, което **отпечатва** получените манифести. Това е командата, която най-често ще ползваш при работа с Kustomize: сглобява, не прилага. Колко обекта, от какви типове:

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

(`grep '^kind:'` оставя редовете, които *започват* с `kind:`, по един на обект; `sort | uniq -c` брои колко има от всеки тип, а последното `sort -rn` ги подрежда от най-много към най-малко.) Това е пълният проект: всеки ред от таблицата в 10.2 има своя дял тук. Три реда заслужават поглед. `ServiceAccount` и `NetworkPolicy` са повече от един, защото всяко натоварване има свой акаунт, а всяко мрежово отваряне — свое правило. `ConfigMap` и `Secret` са по един: генераторите. А `Gateway`, `HTTPRoute`, `GatewayClass`, `IPAddressPool` и `L2Advertisement` са обектите от **типове, които не съществуват в празен клъстер**, точката на 10.4.

Цифрите по-горе са общият брой, който ще види `kubectl apply`. Ако някога се усъмниш какво ще получи клъстерът, това е първият въпрос, който си задаваш, преди да приложиш: `kubectl kustomize` и преброй.

#### 10.3.3 Промяна без копиране: примерен overlay

Overlay-ите служат за онова, което се *променя* между среди. За да видиш какво може да промени един слой, без да докосва базата, този файл описва как би изглеждала същата база в истински клъстер. **Не се прилага никъде**: само се визуализира (render).

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

Има три инструмента за промяна и всичките са там. **`images`** променя името и етикета на един образ из цялото дърво, без да се редактират Deployment-ите: тук образът идва от регистър, вместо да е зареден ръчно с `kind load`. **`patches`** със списък от операции (`op: replace`) е *JSON Patch* ([RFC 6902](https://www.rfc-editor.org/rfc/rfc6902.html)): казва кой обект (`target`, по тип и име), кой път да се промени (`path`) и новата стойност. Точен е и понякога неудобен, защото пътят се пише с индекса на списъка (`topologySpreadConstraints/0` е първото ограничение). [Документацията](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) предлага и *strategic merge* кръпката (пишеш част от обекта и тя се слива), която е по-четлива при големи промени; за едно число или за един ключ операциите са по-директни. А домейнът `registry.example.com` е от `example.com`, име, което [RFC 2606](https://www.rfc-editor.org/rfc/rfc2606.html) резервира за примери и документация: никой не може да го регистрира и затова няма риск друг да го ползва и да получи твоите образи.

Сравнението между overlay-а на `kind` и този е най-добрият начин да видиш *какво* се променя:

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

(`diff` сравнява два текста; `<( … )` му подава изхода на една команда като файл и работи в `bash` и в `zsh`. Редовете с `<` са от overlay-а на `kind`; тези с `>` са от примерния.) Чети го по блокове. В първия има смяна на образ: този на `revisor` идва от регистър, не от `kind load`. Вторият е ограничението за разпределение: от `kubernetes.io/hostname` (разпределя между *възли*) към `topology.kubernetes.io/zone` (разпределя между *зони*, които в облака са различни центрове за данни в един регион). След това `maxReplicas` и `minReplicas` на мащабирането: от 6 на 10 и от 2 на 3. И накрая онова, което **излиза** от дървото: `GatewayClass`, диапазонът и обявяването на MetalLB, които са на `kind`, а не на базата. Четири промени и едно изваждане, а базата не е докосната. (Ако видиш `[código de salida: 1]` под `diff`, това не е грешка: `diff` излиза с 1, когато намери разлики, и с 0, когато не намери.)

#### 10.3.4 Две предупреждения за онова, което идва от интернет

Папката `plataforma` има по един `kustomization.yaml` на парче и всеки сочи към **отдалечен файл**:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -c '^kind:'
76
```

Това е броят обекти, които се сглобяват от три интернет адреса. Едно конкретно парче, `metrics-server`, носи и кръпка, която вече познаваш от Урок 9:

```text
$ kubectl kustomize overlays/kind/plataforma | grep -B1 -A1 'kubelet-insecure-tls'
        - --metric-resolution=15s
        - --kubelet-insecure-tls
        image: registry.k8s.io/metrics-server/metrics-server:v0.9.0
```

Флагът `--kubelet-insecure-tls` кара `metrics-server` да не проверява сертификата, с който се представя всеки `kubelet`. README-то на `metrics-server` v0.9.0 го описва без украса: „само за целите на тестването“. В `kind` сертификатите на `kubelet` не са подписани от удостоверителния орган на клъстера, така че без флага `metrics-server` не може да чете възлите. В истински клъстер **не се ползва**: сертификатите се подписват както трябва и флагът е излишен. Това е шестото от нещата, които 10.10 вписва в списъка с онова, което липсва.

Двете предупреждения за отдалеченото:

- **Всеки път, когато прилагаш, сваляш.** Адрес с версията в пътя (`…/v0.16.1/…`) фиксира *коя версия* искаш, но съдържанието продължава да идва от интернет всеки път, когато `kustomize` сглобява дървото. Без връзка няма платформа. Един истински екип обикновено пази копие на тези файлове в своето хранилище (или в собствено огледало), така че разгръщането да не зависи от чужд сайт, нито от това отдалечен файл да не се промени под краката му. Тук това не се прави, за да видиш откъде идва всяко парче.
- **Фиксирай версията и я запиши.** Версиите на този курс са MetalLB v0.16.1, Envoy Gateway v1.9.2 и `metrics-server` v0.9.0. Това не е подробност: [ръководството за инсталиране на Envoy Gateway](https://gateway.envoyproxy.io/docs/install/install-yaml/) обяснява, че при обновяване първо трябва да се обновят CRD-тата на Gateway API и че ако това не се направи, TCP и UDP маршрутите „се пропускат безшумно“, докато не се приложат CRD-тата. Версия, която се мести, без никой да го е решил, е източникът на много понеделнишки сутрини.

### 10.4 Защо две команди и едно изчакване

#### 10.4.1 Три неща, които носи една инсталация

В Урок 6 видя, че MetalLB и Envoy Gateway не са „още един Deployment“: когато се инсталират, добавят към клъстера **нови типове обекти**, **контролери**, които ги обслужват, и **пазачи**, които проверяват какво се създава. Преди да продължим, трите с точните им имена, защото редът на този урок идва оттам.

- **CRD (*CustomResourceDefinition*)** е дефиницията на тип обект, който Kubernetes не носи от завода. Докато не съществува, да напишеш `IPAddressPool` е като да напишеш дума, която речникът няма: `kube-apiserver` отговаря `no matches for kind`. А един CRD не е „готов“, когато се създаде. [Документацията за CRD](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/) го казва така (в превод): на сървъра му трябват няколко секунди, за да създаде *endpoint*-а на новия тип, и можеш да следиш условието `Established` на CRD-то или списъка с типове, които сървърът обявява, за да разбереш кога вече съществува. Това условие, `Established`, е онова, което `kubectl wait` чака в 10.5.
- **Контролерът** е програма (Pod), която наблюдава обектите от един тип и прави така, че светът да съвпада с тях: този на MetalLB разпределя адреси; този на Envoy Gateway създава Envoy, който обслужва входната точка. Докато не работи, обектът се приема, но никой не го обслужва: Gateway-ът съществува и няма адрес. Един Deployment е *готов*, когато условието му `Available` е истинно.
- **Admission *webhook*** е пазач, когото `kube-apiserver` пита *преди* да запише един обект, за да го приеме, отхвърли или поправи. MetalLB има такъв, който валидира диапазоните. [Документацията за динамичния контрол на допускането](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/) има едно парче, което трябва да се знае: ако сървърът не успее да говори с *webhook*-а (мрежа, изтекло време, отказана връзка), политиката `failurePolicy` решава какво става, и **стойността по подразбиране е `Fail`**: заявката се отхвърля. С други думи, докато Pod-ът на пазача не обслужва, нито един обект от типовете, които той наблюдава, не може да се запише.

Трите неща пристигат в един и същи момент и не са готови едновременно. Онова, което се бави, е онова, което налага изчакването.

#### 10.4.2 `--server-side`: защо платформата се прилага по-различно

Преди реда, втората команда от рецептата има флаг, който не си ползвал: `kubectl apply --server-side`. Добре е да го разбереш, преди да го видиш как се проваля.

Обичайният `kubectl apply` е *от страна на клиента* (*client-side*): `kubectl` изчислява какво се е променило и, за да помни „последното, което приложих“, записва копие на целия манифест в анотация на самия обект, `kubectl.kubernetes.io/last-applied-configuration`. [Документацията за *Server-Side Apply*](https://kubernetes.io/docs/reference/using-api/server-side-apply/) описва другия начин (в превод): вместо клиентът да изчислява и да помни, сървърът проследява кой **мениджър** (*field manager*) е собственик на всяко поле на обекта. Стабилен е от Kubernetes 1.22. Иска се с `--server-side`.

За този урок имат значение две последици. Първата: без копирането на „последното, което приложих“ в самия обект се премахва едно ограничение. Анотацията има максимален размер, а CRD-тата на Gateway API и на Envoy Gateway са огромни (описват подробно всяко поле на всеки тип). Официалното ръководство за инсталиране на Envoy Gateway, което вече цитира в Урок 6, инсталира с `kubectl apply --server-side`, а в 10.4.3 ще видиш какво отговаря клъстерът, когато се пропусне. Втората: със *Server-Side Apply* този, който прилага, е мениджър с име, и ако двама мениджъри пипат едно и също поле с различни стойности, сървърът съобщава за **конфликт**, вместо да презапише безшумно. Това е, което искаш, когато няколко инструмента (ти, един контролер, един *pipeline*) пипат един и същи клъстер.

И едно разграничение, за да не се обърка: `--server-side` променя *кой изчислява промяната*, не *какво се прилага*. Проектът се прилага еднакво и в двата режима; този урок ползва `--server-side` в двете команди, за да е един и същи навикът.

#### 10.4.3 Първа грешка: платформата без `--server-side`

Платформата се прилага „както обикновено“, без флага, в празен клъстер. Изходът е дълъг, затова се записва във файл и се разглежда на части: първо колко е създадено, после **само онова, което не е „created“**:

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

(`> файл 2>&1` записва във файла и каквото излиза през нормалния изход, *и* каквото излиза през изхода за грешки; `$?` е кодът на излизане на предишната команда; `grep -v` отпечатва редовете, които **не** съвпадат; `cut -c1-330` отрязва всеки ред на 330 знака, за да се събере.)

Чети го по ред. **Кодът на излизане е 1**: `apply` завърши с грешка. **Бяха създадени 73 обекта** и три реда казват какво не се получи: CRD-тата `envoyproxies.gateway.envoyproxy.io`, `httproutes.gateway.networking.k8s.io` и `securitypolicies.gateway.envoyproxy.io` „are invalid: `metadata.annotations: Too long: may not be more than 262144 bytes`“. Това са 262144 байта, тоест 256 KiB (256 × 1024): горната граница, която `kube-apiserver` слага на анотациите на един обект. Тази анотация е копието на „последното, което приложих“, за което стана дума в 10.4.2, а тези три CRD-та описват толкова полета, че собствената им дефиниция, копирана в обекта, надхвърля границата. Беше измерено всяко CRD на платформата, преобразувано в компактен JSON (`programas/10-proyecto-final/crd-tamanos.sh`; изходът му е `crd-tamanos.salida.txt`): `envoyproxies` тежи около 649 хиляди байта, `httproutes` около 299 хиляди и `securitypolicies` около 274 хиляди; следващото по големина, `backendtrafficpolicies`, е около 128 хиляди. Те са точно трите, които се провалиха, и никое друго.

Обърни внимание на онова, което това съобщение **не** прави: не казва „липсва флаг“. Казва, че един обект не се побира, и трябва да знаеш, че причината е в начина на прилагане. И обърни внимание в какво състояние оставя клъстера, което е най-сериозното: 73 от 76 обекта са създадени, така че клъстерът *изглежда* да има платформа, но му липсва `httproutes`, типът на маршрута, който ползва Урок 6, и му липсват два типа на Envoy Gateway. Едно полусъстояние, което изглежда почти здраво, е по-лошо от такова, което се проваля напълно. Този клъстер беше изтрит и беше създаден друг за следващия експеримент: това е методът на курса.

#### 10.4.4 Втора грешка: платформата и проектът в една команда

Естественият въпрос е: защо две команди? Не може ли всичко да се събере в една, с флага? `fig10_01.todo-junto/kustomization.yaml` е **програма, която се проваля нарочно** (първият ѝ ред предупреждава за това): една-единствена kustomization, която съдържа платформата и проекта.

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

Прилага се в празен клъстер (друг, току-що създаден) с правилния флаг. Гледа се същото като преди: колко обекта влязоха и кои не.

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

Чети го по същия начин. Кодът пак е 1 и този път влязоха **99 обекта** от 104, които сглобява дървото (76 от платформата и 28 от проекта). Петте, които не влязоха, казват едно и също: `no matches for kind "Gateway"`, `"GatewayClass"`, `"HTTPRoute"`, `"IPAddressPool"` и `"L2Advertisement"`, всеки със съобщението `ensure CRDs are installed first` („увери се, че CRD-тата са инсталирани първо“). Сравни ги с петте условия `Established`, които чака 10.5.2: това са същите пет типа. Влязоха Deployment-ите, Service-ите, мрежовите правила, пространството от имена и самите CRD-та, които не зависят от никакъв нов тип; не влезе нищо, което зависи. `kubectl` определя **в началото**, преди да създаде каквото и да е, какви типове познава сървърът и с този списък проверява 104-те обекта. CRD-тата влизат в списъка, но обектите, които ги ползват, се проверяват спрямо каталога, който е имало *преди* да бъдат създадени: затова пет се провалят, макар CRD-тата им да се създават в същата команда. Един `apply` не пита отново по средата на пътя ([`mapper.go` на cli-runtime](https://github.com/kubernetes/cli-runtime/blob/master/pkg/resource/mapper.go)).

Изкушението, което следва, е най-лошото: да повториш същата команда, без да променяш нищо и без да чакаш, да видиш дали този път ще мине. Направено беше и ето какво се случи:


```text
$ kubectl apply --server-side -k fig10_01.todo-junto > $L10_TMP/junto2.txt 2>&1; echo "código: $?"
código: 1

$ grep -c serverside-applied $L10_TMP/junto2.txt
102

$ grep -v serverside-applied $L10_TMP/junto2.txt | cut -c1-330
Error from server (InternalError): Internal error occurred: failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-ipaddresspool?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
Error from server (InternalError): Internal error occurred: failed calling webhook "l2advertisementvalidationwebhook.metallb.io": failed to call webhook: Post "https://metallb-webhook-service.metallb-system.svc:443/validate-metallb-io-v1beta1-l2advertisement?timeout=10s": dial tcp 10.96.187.239:443: connect: connection refused
```

Имаше напредък и това прави метода коварен. Сега влязоха **102 обекта**: трите типа на Gateway API вече съществуваха, така че `Gateway`, `GatewayClass` и `HTTPRoute` минаха. Остават два, диапазонът и обявяването му, и се провалят по друга причина: `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connect: connection refused`. Типът `IPAddressPool` вече съществува, но пазачът, който MetalLB слага пред него (10.4.1), още не слуша: Pod-ът на контролера се стартира. Тъй като `failurePolicy` е `Fail`, `kube-apiserver` отхвърля обекта. `connection refused` означава, че адресът на Service-а на пазача (онзи след `dial tcp`, IP на клъстера, който при твоето изпълнение ще е друг) съществува, но отзад никой не обслужва.

Всеки опит разкрива следващия слой от онова, което е липсвало: първо типовете, после пазачите. Трети опит вероятно щеше да мине (не е измерен, защото няма смисъл да се измерва) и тогава в wiki-то щеше да остане написано „повтаряй, докато мине“. Това е обратното на рецепта: не казва колко пъти, не казва какво да се очаква и в деня, в който някой опит се провали по друга причина, нямаше да има как да я различиш. Единственото, което се промени между опит 1 и опит 2, беше времето, което мина; онова, което трябва, е да се назове това, което се чака.

#### 10.4.5 Какво учат двете грешки

Двете грешки са версии на един и същи факт и служат, за да се фиксират три правила:

1. **Платформата идва първа и с `--server-side`.** Носи нови типове, контролери и пазачи. Това е отделна команда, защото има условие за излизане: „типовете са установени и контролерите работят“.
2. **Между платформата и проекта има изчакване по условие.** Не `sleep 30`, който работи на твоята машина и се проваля на по-бавна, а `kubectl wait --for=condition=…`. [Документацията на `kubectl wait`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) го описва като чакане на „конкретно условие върху един или няколко ресурса“ и излиза с грешка, ако то не настъпи за времето, което си му дал (`--timeout`). При изпълнението ще видиш, че когато условието е изпълнено, отпечатва `condition met`. `sleep` ти казва „мина време“; `wait` ти казва „стана онова, което ми трябваше“. И когато се провали, се проваля с име.
3. **Проектът идва след това, в своя собствена команда.** Всичко, което ползва нов тип, контролер или пазач на платформата, отива тук.

Рецептата остава в три реда: `apply` на платформата, `wait`, `apply` на проекта. Това е „две команди и едно изчакване“ от заглавието на урока, а първата цел на курса го брои така: това са три стъпки и редът е онова, което ги определя.

Има и принципна причина, не само за този курс. Документацията на Helm, който 10.9 назовава, има същия проблем и го казва с други думи в своите [препоръчани практики за CRD](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) (в превод): „декларацията [на CRD] трябва да е регистрирана, преди да може да се ползва какъвто и да е ресурс от този тип, а регистрацията понякога отнема няколко секунди“. Това не е странност на Kustomize, нито на `kubectl`; това е свойство на начина, по който Kubernetes разширява своите типове.

### 10.5 Разгръщане ръчно: платформа, изчакване, проект

Сега добрият път, в току-що създаден клъстер, с всяка стъпка на показ. Това е клъстерът от 10.1 (този на изходите от този раздел): три възела, двата образа заредени, нито един CRD. И преди **всяка** команда, която променя нещо, `ctx &&`.

#### 10.5.1 Стъпка 1: платформата

```bash
ctx && kubectl apply --server-side -k overlays/kind/plataforma > "$L10_TMP/plataforma.txt"
```

С флага и в празен клъстер всичко влиза. Командата отпечатва по един ред на обект; записа се във файл и ето какво се вижда от него:

```text
$ kubectl apply --server-side -k overlays/kind/plataforma > $L10_TMP/plataforma.txt; grep -c serverside-applied $L10_TMP/plataforma.txt
76

$ head -4 $L10_TMP/plataforma.txt
namespace/envoy-gateway-system serverside-applied
namespace/metallb-system serverside-applied
customresourcedefinition.apiextensions.k8s.io/backends.gateway.envoyproxy.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
```

Редовете са **76**, по един на обект, и нито един не казва `Error`. `serverside-applied` означава, че сървърът е приложил обекта: създал го е или го е обновил; в празен клъстер всички са създавания. Първите два реда създават пространствата от имена `envoy-gateway-system` и `metallb-system`, а следващите са CRD-та (`backends.gateway.envoyproxy.io`, `backendtlspolicies.gateway.networking.k8s.io`…). Сравни с 10.4.3: с `--server-side` трите CRD-та, които не се побираха, влизат като останалите, защото вече не им се лепи копието на „последното, което приложих“.

Клъстерът вече познава новите типове, но контролерите им още се стартират. Така изглежда в този миг:

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

Клъстерът вече познава **30** нови типа (`kubectl get crd | wc -l` брои 31, защото включва реда със заглавията). А Pod-овете на MetalLB, в първата секунда, са всички в `0/1 ContainerCreating`: `controller` и по един `speaker` на възел още свалят образа си и се стартират. Това е опасният миг от 10.4: типовете съществуват, а пазачите не обслужват. Прилагането на проекта *сега* би дало `connection refused` от втората грешка.

#### 10.5.2 Стъпка 2: изчакването

Пет изчаквания, всяко със своето условие. И петте заедно са „платформата е готова“:

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

И петте завършват добре. Първото, на типовете, отговаря веднага `condition met` за петте CRD-та: вече бяха установени. Останалите са бавните: `controller` на MetalLB, трите `speaker` (напредъкът казва `0 of 3 updated pods are available…`, после `1 of 3`, `2 of 3` и накрая `successfully rolled out`), контролерът на Envoy Gateway и `metrics-server`. Възлите са нови и нямат нито един образ: всеки трябва да свали от интернет тези на MetalLB, Envoy Gateway и `metrics-server`, преди да може да стартира Pod-овете. При това изпълнение пълното изчакване продължи 153 секунди; при подготвителните изпълнения на урока варираше от тези 153 до 881 секунди (почти петнайсет минути), според връзката и натоварването на машината. Всеки `kubectl wait` носи своя собствена горна граница от 600 секунди; 881-те бяха сборът на петте изчаквания, не на едно (изходът е в `corridas-preparacion/corrida4.txt`). Ако при твоята връзка само едно изчерпи 600-те, грешката не отменя нищо: повтори същата команда. Не беше отделено колко от това време е сваляне и колко е стартиране, затова не се твърди. Онова, което се твърди, е това, което трябва да планираш: **изчакването е най-дългата част от разгръщането** и затова е добре да бъде изчакване по условие, а не фиксирано време, което някой трябва да налучква.

И едно изчакване служи и за да разбереш кога нещо **не** настъпва. Ако поискаш от `kubectl wait` условие, което не се изпълнява, с кратка горна граница, то се предава с грешка, вместо да увисне. Тук се иска от контролера на Envoy Gateway, който е `Available`, да премине в състояние да не е такъв, и му се дават 5 секунди:

```text
$ kubectl wait --for=condition=Available=false --timeout=5s -n envoy-gateway-system deployment/envoy-gateway
error: timed out waiting for the condition on deployments/envoy-gateway
[código de salida: 1]
```

`error: timed out waiting for the condition on deployments/envoy-gateway`, а скриптът отбелязва `[código de salida: 1]`. Това е поведението, което искаш от едно изчакване: не виси, не измисля успех и казва кое условие на кой обект не настъпи. Един `sleep 300`, последван от `apply`, щеше да те остави без тази информация.

Чети ги със списъка от три неща от 10.4.1 под ръка. Първото изчакване е за **типове**: `Established` е условието на CRD. Останалите четири са за **контролери**: `Available` за Deployment-ите (`controller` на MetalLB, `envoy-gateway`, `metrics-server`) и `rollout status` за `DaemonSet`-а `speaker`. Един `DaemonSet` няма `Available`; има напредък от рода „колко от Pod-овете, които трябва да има, са готови“, а `rollout status` го следи, докато са всички (по един на възел). *Webhook*-ът на MetalLB го обслужва Pod-ът `controller`: когато е `Available`, пазачът вече отговаря.

#### 10.5.3 Стъпка 3: проектът

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

Редовете са **28** и всеки ред от таблицата на 10.2 е там: пространството от имена, четирите сервизни акаунта, ролята и нейното свързване, `ConfigMap` и `Secret` с техния *hash*, двата Service-а, томът, двата Deployment-а, `CronJob`-ът, `PodDisruptionBudget`, мащабирането, `Gateway` със своя `HTTPRoute`, шестте мрежови правила и **трите** обекта, които съществуват само заради overlay-а: `GatewayClass` `eg`, диапазонът и обявяването на MetalLB. Обърни внимание, че не излизат накрая, а разпръснати: Kustomize подрежда изхода по тип обект, не по файла, от който идват. Името на `ConfigMap`, `revisor-config-t6cm6872fk`, е **същото** като в Уроци 4 и 5, защото списъкът от услуги е същият: *hash*-ът е на съдържанието му. Този на `Secret` се променя при всяко изпълнение, защото токенът е нов. И няма нито един ред, който да започва с `Warning`, но това отсъствие се доказва, не се гледа.

Твърдение като „няма предупреждения“ се доказва с броене и със случай, в който ги има (10.7 го прави). Ето броенето, с `-i`, за да не зависи от главни букви:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -ci warning
0
[código de salida: 1]
```

`0` е броенето. `[código de salida: 1]`, което скриптът отбелязва, не е неуспех: `grep` излиза с 1, когато не намери нито един ред, макар с `-c` да отпечатва нулата. Тук означава „нула предупреждения“.

След това още две изчаквания: Deployment-ите да са `Available` и входната точка да е `Programmed` (условието на `Gateway`, което казва „вече има адрес и Envoy, който я обслужва“):

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

Остава едно изчакване, което `kubectl wait` не покрива добре: автоматичното мащабиране има нужда от няколко секунди, за да прочете първите си метрики, а докато ги няма, показва `<unknown>`. Този път не се решава със сляп `sleep`, а с кратък и **видим** цикъл, който проверява на всеки 5 секунди до две минути и спира веднага щом мащабирането вече има метрика:

```bash
for _ in $(seq 1 24); do
  [ -n "$(kubectl get hpa revisor -n revisor -o jsonpath='{.status.currentMetrics[*].type}')" ] && break
  sleep 5
done
```

Има един `sleep` и е допустимо: това е **изчакване на условие с горна граница**. Всяка итерация пита дали вече е станало онова, което има значение. Ако не стане за 24 итерации, цикълът се предава и следващата команда ти показва `<unknown>`, вместо да го скрие.

#### 10.5.4 Да го видиш как работи

Всичко, което деветте урока изградиха, в една-едничка заявка:

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

Чети я по блокове, отгоре надолу.

- **Pod-ове.** Двата на `revisor` и този на `prueba`, и трите `1/1 Running`. Ако разгърнеш проекта точно в минута, кратна на пет, ще видиш и четвърти Pod, `reporte-…`, в `0/1 Completed`: планираната задача от Урок 8, която вече се е изпълнила и е завършила добре (при едно подготвително изпълнение на този урок се появи; при онова, което се вмъква тук, още не).
- **Service-и.** И двата са `ClusterIP`, без `EXTERNAL-IP`: директният `LoadBalancer` от Урок 6 вече не съществува. Единствената входна точка е Gateway-ът.
- **Deployment-и и ReplicaSet-и.** `2/2` и `1/1`. Всеки Deployment има ReplicaSet със своя *hash*. Ако при твоето изпълнение е различен, е нормално: зависи от името на `Secret`, което се променя с токена.
- **Мащабиране.** `cpu: …/50%`, `MINPODS 2`, `MAXPODS 6` и двете текущи реплики. Че има процент, а не `<unknown>`, означава, че `metrics-server` вече е предал първото си отчитане; затова се чака с цикъла от 10.5.3.
- **CronJob.** Графикът `*/5 * * * *`, неспрян, `ACTIVE 0` и `LAST SCHEDULE <none>`: още не се е задействал нито веднъж. Когато се задейства, ще се появи Job със своя Pod.
- **Том.** PVC-то `reportes` е в `Pending` и това е правилно: в Урок 8 видя, че класът `standard` чака първия Pod, който ще го ползва (`WaitForFirstConsumer`), преди да създаде диска. Ще премине в `Bound`, когато `CronJob`-ът се задейства за първи път.
- **`PodDisruptionBudget`.** `MIN AVAILABLE 1` и `ALLOWED DISRUPTIONS 1`: с две реплики клъстерът може да изважда по една наведнъж.
- **Мрежови правила.** Шестте от Урок 7, със своите селектори.
- **Gateway.** Клас `eg`, **адрес `172.30.255.200`** (първият от диапазона на overlay-а) и `PROGRAMMED True`. Това е адресът, който MetalLB разпредели. **`HTTPRoute`.** Без имена на сайтове (`HOSTNAMES` празно): обслужва всякакви.

И метриките, които са доказателството, че `metrics-server` и мащабирането са свързани:

```text
$ kubectl top pods -n revisor
NAME                       CPU(cores)   MEMORY(bytes)   
prueba-6899c74865-rzh88    1m           1Mi             
revisor-654b5d75dc-6m6s6   1m           1Mi             
revisor-654b5d75dc-dq4pp   2m           1Mi             
```

Остава най-важното: **някой отвън** да стигне. Адресът на входната точка идва от самия `Gateway`, а клиентът е Docker контейнер, свързан към същата мрежа като възлите, **извън** клъстера (същият трик като в Урок 6):

```bash
IP_GW="$(kubectl get gateway revisor -n revisor -o jsonpath='{.status.addresses[0].value}')"
CURL='curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777'
docker run --rm --network kind $CURL -s -m 5 "http://$IP_GW/salud"
docker run --rm --network kind $CURL -s -m 5 -o /dev/null -w '%{http_code}\n' "http://$IP_GW/api/estados"
docker run --rm --network kind $CURL -s -m 5 -H "Authorization: Bearer $TOKEN" "http://$IP_GW/api/estados?formato=tabla"
```

(В блока с изхода по-долу скриптът съкращава всяко `docker run … curl` до `curl`, за да се събере. `$TOKEN` е променливата от 10.1.2.)

```text
$ curl -s -m 5 http://172.30.255.200/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.30.255.200/api/estados
401

$ curl -s -m 5 -H "Authorization: Bearer $TOKEN" 'http://172.30.255.200/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           3ms  200
```

Трите заявки стигнаха отвън клъстера до адреса, който MetalLB даде на Gateway-а. `/salud` отговаря, без да иска нищо. `/api/estados` **без токен** дава `401` (Урок 4: `revisor` изисква `Authorization: Bearer …`). А с токена — таблицата на отчета. Обърни внимание, че токенът минава през входната точка в заглавие, в чист текст: това е точка 4 от списъка на 10.10.

В твоя терминал името на мрежата е `kind` (така го остави блокът по-горе). Ако изпълнението не е ползвало тази мрежа, разделът „За изпълненията“ го казва.

### 10.6 Автоматизиране, без да се крие редът

#### 10.6.1 Какво се автоматизира и какво не бива да се крие

Ръчно разгръщането са три блока и осем изчаквания. За да го повтаряш във всеки нов клъстер —твоя утре, на една колежка, на автоматична стъпка на един *pipeline*— е удобен един скрипт. И тук има проектантско решение, което разделя скрипта, който помага, от този, който пречи. Има два начина да го напишеш:

- **Скриптът, който крие реда.** Един-единствен ред, който „повтаря, докато мине“: `until kubectl apply -k .; do sleep 5; done`, или `sleep 120` между две прилагания, или `|| true`, за да не спре нищо. Работи почти винаги, а когато се провали, не казва защо: цикълът се върти без край, или `sleep`-ът е бил къс на бавната машина, или грешката е била погълната безшумно. В 10.4.4 видя какво прави сляпото повторение: прилага наполовина и те оставя ти да гадаеш какво липсва.
- **Скриптът, който показва реда.** Същите три стъпки, всяка с име, всяка със своята проверка на контекста, с изчаквания по **условие** и с горна граница на времето. Когато се провали, се проваля в стъпка с име, със съобщение от `kubectl`, което казва кое условие не настъпи. И който го чете, научава реда, което е половината от стойността.

Това е вторият. Казва се `levantar.sh`, живее в папката на урока и е онова, което една стъпка на един *pipeline* би извикала такова, каквото е:

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

#### 10.6.2 Скриптът, ред по ред

Чете се отгоре надолу и почти всичко в него е нещо, което вече познаваш с друго лице.

**`set -euo pipefail`.** Три опции на `bash` в една. `-e` спира скрипта при първата команда, която се провали. `-u` прави използването на несъществуваща променлива грешка, вместо да се чете празна. `-o pipefail` прави така, че една тръба (`a | b`) да се проваля, ако се провали *коя да е* от частите ѝ, не само последната. Заедно са разликата между скрипт, който спира там, където е проблемът, и такъв, който продължава, сякаш нищо не е станало. Това е същата причина, поради която `levantar.sh` ползва `|| true` само на едно място: при четенето на активния контекст, където провалът се приема (скриптът го сравнява след това и спира с ясно съобщение). Същото в `probar-levantar.sh`, при почистването на клъстера и при преброяването на живите клъстери, и в нарочните провали на `correr.sh`: всяко `|| true` е залепено за конкретна команда, чийто провал се приема и се казва защо, което е единственото, което „Какво се прави погрешно“ допуска.

**`ESPERADO="${1:?uso: …}"`.** Скриптът **не налучква** в кой клъстер е: получава контекста като аргумент и, ако липсва, отпечатва начина на ползване и спира. `${1:?mensaje}` означава „първият аргумент, а ако е празен, се проваля с това съобщение“. Това е обратното на скрипт, който ползва „клъстера, който е активен“: скрипт, който инсталира MetalLB и Envoy Gateway в активния контекст, без да пита, може да инсталира тези неща в погрешния клъстер.

**`contexto()`.** Функцията `ctx` от 10.1, но за скрипт: сравнява `kubectl config current-context` с `ESPERADO` и, ако не съвпадат, отпечатва „ALTO“ и прави `exit 1`. Вика се **преди всяка стъпка**, не само веднъж в началото, защото един дълъг скрипт работи минути и някой (или нещо) може да смени контекста между една стъпка и друга.

**Стъпка 0: мрежата.** Това е ново и съществува по конкретна причина. Диапазонът от адреси на MetalLB живее в `overlays/kind/metallb-pool.yaml`. Ако този диапазон не попада в същата мрежа като възлите, MetalLB присвоява адрес на Gateway-а, `kubectl` казва, че всичко е наред, и никой отвън не може да стигне до него: провалът е безмълвен. `sed` извлича първия адрес от диапазона, `docker inspect` извлича IP на контролния възел, а сравнението `${RANGO%.*.*}` (премахване на последните две числа: `172.30.255.200` остава `172.30`) с `${IP_NODO%.*.*}` проверява, че двата са в една и съща мрежа `/16`. Проверката е проста —предполага мрежи с такъв размер, а съобщението за грешка го казва—, но превръща безмълвен провал в „ALTO“ с причина.

**Стъпка 1.** Улавя изхода на `kubectl apply` в променлива (`SALIDA="$(…)"`) и показва само броя на `serverside-applied`. Ако `kubectl apply` се провали, присвояването се проваля и `set -e` спира скрипта: до броенето не се стига. Изходът не се изхвърля с `>/dev/null`: **измерва се**.

**Стъпка 2.** Петте изчаквания от 10.5.2, без промяна. Всяко със своя горна граница (`--timeout`): 120 секунди, за да съществуват CRD-тата, 600 (десет минути) за контролерите, които зависят от това колко време ще отнеме на твоята връзка да свали образите.

**Стъпка 3.** Прилага проекта и чака две неща: Deployment-ите `Available` и входната точка `Programmed`. Накрая `kubectl get gateway` отпечатва резултата, който искаш да видиш.

**`$SECONDS`.** Променлива на `bash`, която брои секундите от стартирането на скрипта. Всяка стъпка съобщава на колко секунди е приключила. Не е украса: ако някоя стъпка се забави, го виждаш, а времената на този скрипт са онези, които 10.6.3 ползва, за да каже колко време отнема разгръщането на проекта.

Онова, което **не** прави, също е решение. Не създава клъстера (това е работа на този, който го вика: ти или предишна стъпка на *pipeline*-а). Не зарежда образите. И не прави `curl`: проверката, че входната точка отговаря отвън, изисква клиент в Docker мрежата, а това е проверка, не разгръщане. Скрипт, който разгръща, и друг, който проверява, могат да се сменят поотделно.

Още една подробност за кода на излизане. `levantar.sh` излиза с 0 само ако **целият** път е завършил; при каквото и да е неуспех излиза с код, различен от 0, в стъпката, където е станал. Това е единственото, което трябва да знае един *pipeline*, за да отбележи една стъпка като зелена или червена, и затова скриптът се грижи за него и не зависи от това някой да чете текста на изхода.

#### 10.6.3 Да го изпиташ наистина: създаване, разгръщане, изтриване, пресъздаване

Скрипт, който никога не е изпълняван срещу празен клъстер, е като резервното копие от случая с GitLab: съществува и не се знае дали върши работа. Изпитва се с `probar-levantar.sh`: създава клъстера, изпълнява `levantar.sh`, проверява отвън, че входната точка отговаря, **изтрива клъстера** и повтаря всичко втори път. Ако първият кръг мине случайно (нещо, което вече е било там, кеш, изчакване, което е стигнало), вторият го издава, защото тръгва от нула отново.

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

Частите, които не са от разгръщането, вече си ги виждал: временният `kubeconfig`, `trap limpiar EXIT`, който **изтрива клъстера, дори скриптът да се провали по средата** (един `trap … EXIT` се изпълнява при излизане от скрипта, било при завършване, било при грешка), и проверката, че `curso-k8s-l10` не съществува вече преди да го създаде. `limpiar` изтрива само клъстер, наречен точно `curso-k8s-l10`, и временната папка само ако пътят ѝ започва с `/tmp/curso-k8s-l10.` (обичайният `case`).

Новото е `CUPO_MAXIMO`. Служи за споделени машини и изпълнението на този урок я ползва: преди да създаде клъстер, чака да има по-малко от това число живи клъстери `curso-k8s-*`. Без променливата не чака. На твоята машина, сам, не ти трябва.

`probar-levantar.sh` ползва собствения си `base/token.txt` (`levantar.sh` го генерира, ако не съществува) и **го изтрива при завършване**: ако вече имаш такъв, запази го преди това или го остави да се генерира наново.

Пълният изход на изпитването, с двата кръга:

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

Двата кръга казват едно и също и това е, което се искаше да се докаже. Стъпка 0 потвърждава, че диапазонът започва от `172.30.255.200` и че контролният възел е в `172.30.0.x` (IP на възела се променя от кръг на кръг: `.4` и `.3`; единственото, което има значение, е мрежата). Стъпка 1 прилага **76** обекта за около 5 секунди. Стъпка 2 е тази, която продължава: от секунда 5 до 234 в първия кръг и от 4 до 250 във втория (натрупани отметки от стартирането на скрипта), тоест **почти цялото разгръщане е чакане** възлите да свалят образи и да стартират платформата. Стъпка 3 прилага **28** обекта и чака: 22 секунди в първия кръг и 65 във втория (Gateway-ът отбелязваше 22 s и 61 s възраст накрая: `AGE` е възрастта на обекта в момента на `get`, не времето до `Programmed`). Всяко „paso N terminó a los X s“ е натрупаното време от стартирането на скрипта, не продължителността на стъпката. `levantar.sh` отне 256 и 315 секунди. И в двата кръга входната точка получи `172.30.255.200`, `curl` отвън отговори `{"estado":"vivo","version":"1.6.0"}` и клъстерът беше изтрит. Че вторият кръг, тръгвайки от нула отново, минава по същия начин, е **целта 1** на курса: да възстановиш, без да поправяш нищо ръчно.

#### 10.6.4 Как би изглеждало в един *pipeline*

За този урок не е нужен *pipeline*, но е добре да знаеш как би се свързал, защото това е употребата, за която е предвиден скриптът. Една стъпка на *pipeline* на който и да е инструмент се свежда до четири неща и `levantar.sh` вече ги има всичките:

1. **Явен вход.** Контекстът (`kind-curso-k8s-l10`) е аргумент, не предположение. В един истински *pipeline* би бил клъстерът, до който тази стъпка има удостоверения.
2. **Минимални удостоверения.** Този скрипт създава CRD-та и *webhooks*, които са обекти на целия клъстер, така че му трябват права на администратор на клъстера. В реална среда на един *pipeline* не се дава акаунтът на администратора на всичко: дава му се собствен акаунт (RBAC, Урок 7) с точно необходимите права за онова, което инсталира. В `kind` няма два акаунта, така че курсът не го упражнява, но го назовава.
3. **Честен код на излизане.** 0, ако всичко е завършило, различен от 0, ако не. Това е единствената информация, която *pipeline*-ът чете.
4. **Изход, който може да се чете по-късно.** Трите заглавия `== 1.`, `== 2.`, `== 3.`, броячите и секундите за стъпка са онова, което някой чете в 7:50 в един понеделник, когато стъпка 2 е станала червена.

И онова, което скриптът не бива да става: място, където се трупат кръпки. Ако една стъпка се счупи по нова причина, поправя се причината, не се добавя `sleep`.

### 10.7 Финалният преглед спрямо `restricted`

#### 10.7.1 Какво иска `restricted`, конкретно

Урок 2 сложи `securityContext` в първия Deployment; Урок 7 сложи нивото `restricted` на пространството от имена. Сега е време да провериш, с клъстера, а не по памет, че **всичко**, което е в пространството `revisor`, го изпълнява. Първо, какво изисква. *Pod Security Standards* ([документация](https://kubernetes.io/docs/concepts/security/pod-security-standards/)) определят три нива; `restricted` е най-строгото и добавя шест контрола към тези на `baseline`:

| Контрол на `restricted` | Какво изисква (поле и допустима стойност) | Къде го изпълнява проектът |
|---|---|---|
| Типове томове | всеки том е от допустим тип: `configMap`, `csi`, `downwardAPI`, `emptyDir`, `ephemeral`, `persistentVolumeClaim`, `projected` или `secret` | `emptyDir` и `secret` в `revisor`; `persistentVolumeClaim` и `secret` в `CronJob` |
| Ескалация на привилегиите | `allowPrivilegeEscalation: false` във всеки контейнер | `securityContext` на всеки контейнер, в двата Deployment-а (`revisor` и `prueba`) и в `CronJob` |
| Изпълнение като не-`root` | `runAsNonRoot: true` (в Pod-а или във всеки контейнер) | `securityContext` на Pod-а |
| Потребител не-`root` | `runAsUser` различен от 0 или недефиниран | 65532 в `revisor` и `prueba`; 100 в `CronJob` |
| *Seccomp* | явен `seccompProfile.type`: `RuntimeDefault` или `Localhost`; нито `Unconfined`, нито липсващ | `RuntimeDefault`, в `securityContext` на Pod-а |
| Възможности (capabilities) | `capabilities.drop` включва `ALL`; може да се добави отново само `NET_BIND_SERVICE` | `drop: ["ALL"]` във всеки контейнер |

(Контролите на `baseline`, които `restricted` наследява —без привилегировани контейнери, без мрежата на хоста, без `hostPath`, без портове на хоста, между другото— се изпълняват, защото никой манифест на проекта не иска нищо такова.)

А сега онова, което **`restricted` не изисква** и проектът прави така или иначе, за да не го бъркаш с нормата:

- `readOnlyRootFilesystem: true`. Нито едно от трите нива не го изисква. Проектът го слага, защото файлова система, в която не може да се пише, ограничава онова, което един нападател би направил в контейнера, и затова `revisor` пази отчета си в том, а не в `/`.
- `requests` и `limits` (Урок 5), `automountServiceAccountToken: false` (Урок 7), `Secret`, маркиран като неизменим и монтиран като файл (Урок 4), затворената мрежа (Урок 7). Това са решения на проекта, не контроли на `restricted`.

Разграничаването на двата списъка има значение: „изпълнява `restricted`“ е факт, който клъстерът може да ти потвърди със заявка (следващият раздел), а „следва практиките на курса“ е преценка, която правиш ти.

#### 10.7.2 Как го прилага клъстерът

Нивото не се обяснява на всеки Pod: казва се на **пространството от имена**, с етикети. Това носи `base/namespace.yaml`:

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

[Документацията за *Pod Security Admission*](https://kubernetes.io/docs/concepts/security/pod-security-admission/) определя три **режима**, всеки със своя етикет: `enforce` (нарушението **отхвърля** Pod-а), `audit` (нарушението оставя анотация в одитния журнал, но се допуска) и `warn` (нарушението предизвиква предупреждение към този, който е приложил, но се допуска). Всеки режим има и етикет `…-version`, който фиксира политиката на тази, която е идвала с дадена версия на Kubernetes, тук v1.37, за да не промени едно обновяване на клъстера правилата под краката ти, без да си го решил.

Една подробност, която обяснява онова, което ще видиш в 10.7.4: според същата документация режимите `audit` и `warn` се прилагат и към обектите, които *създават* Pod-ове (Deployment, Job, CronJob), „за да се помогне да се открият нарушенията рано“, но `enforce` **не** се прилага към тези обекти, а само към Pod-овете, които се получават. С пример: един Deployment, който не отговаря, се *приема* (с предупреждение), а Pod-овете, които се опитва да създаде, се *отхвърлят*. Deployment-ът остава да съществува с нула реплики и затова трябва да четеш предупрежденията на `apply` и да не се доверяваш, че „се е приложило добре“.

#### 10.7.3 Прегледът в клъстера

Първо, заявката, която [документацията](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/) препоръчва, преди да смениш ниво: `kubectl label --dry-run=server --overwrite`. Документацията обяснява, че когато етикет `enforce` (или версията му) се **добавя или се променя**, контролерът за допускане изпитва всеки Pod на пространството спрямо новата политика и връща нарушенията като предупреждения, и че с `--dry-run=server` това изпитване се изпълнява, без да се приложи нищо. Всичко зависи от „добавя или променя“. Първото, което човек пише върху `revisor`, който вече има `enforce=restricted`, **не променя нищо** и затова (измерено е, по-долу) не проверява нито един Pod:

```text
$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)

$ kubectl get namespace revisor --show-labels
NAME      STATUS   AGE   LABELS
revisor   Active   83s   kubernetes.io/metadata.name=revisor,pod-security.kubernetes.io/audit-version=v1.37,pod-security.kubernetes.io/audit=restricted,pod-security.kubernetes.io/enforce-version=v1.37,pod-security.kubernetes.io/enforce=restricted,pod-security.kubernetes.io/warn-version=v1.37,pod-security.kubernetes.io/warn=restricted
```

`namespace/revisor not labeled (server dry run)` казва само едно: етикетът вече е бил такъв и нямаше какво да се променя. **Не провери нито един Pod**, така че не е доказателство, че проектът отговаря; с какъвто и да е Pod вътре би казало същото. Във втория изход са шестте етикета на трите режима, всеки със своята версия `v1.37`, плюс този, който Kubernetes слага сам (`kubernetes.io/metadata.name`).

**Заявката, която наистина проверява съществуващото.** Ако нивото и версията се повторят, сървърът не оценява; ако политиката се **промени**, оценява. Тогава, за да одитираш пространство, което вече е на `restricted:v1.37`, му искаш друга политика, без да я прилагаш: същия етикет за версия с друга стойност, например `enforce-version=v1.36`. Сървърът изпитва всеки Pod спрямо `restricted` от тази версия (не от v1.37: тя е съседна, не същата) и докладва. Тъй като отсъствието на предупреждения не струва нищо без контрола, `psa-comprobacion.sh` го изпитва първо в тестово пространство, `psa-control`, с два Pod-а: `viola` (не казва нищо за сигурността) и `cumple` (изпълнява шестте контрола на `restricted`). Слага му се `restricted:v1.37` наистина и двете заявки се повтарят. Това беше изпълнено в клъстер `curso-k8s-l10` с три възела, с приложения проект (пространството `revisor`), но без платформата, която този тест не изисква:

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

Чети го отгоре надолу. Когато се сложи `restricted` наистина, сървърът предупреждава и назовава **`viola`** (с четирите контрола, които нарушава), а не `cumple`. Повторението на същото ниво и същата версия върху `psa-control` казва `not labeled`, **с Pod, който нарушава, вътре**: това е заявката, която не проверява. Исканата `v1.36` предупреждава и то само за `viola`: заявката проверява и разграничава. С контрола пред очите резултатът върху `revisor` има стойност: повторението на нивото казва `not labeled` (без информация), а искането на `v1.36` казва `labeled (server dry run)` **без нито едно предупреждение** върху 4-те Pod-а на пространството (двата на `revisor`, този на `prueba` и този, който остави `CronJob`). Това вече е „сървърът провери Pod-овете на `revisor` и нито един не нарушава `restricted`“.

Отсъствието на предупреждения има стойност само ако знаеш, че инструментът наистина би ги дал; тази проверка (контролът по-горе и Deployment-ът `malo` от 10.7.5) вече е направена. Освен това, доказателството поле по поле: таблицата от 10.7.1, но прочетена от живите Pod-ове на пространството (jsonpath иска, за всеки Pod, полетата, които `restricted` разглежда):

```text
$ kubectl get pods -n revisor -o jsonpath='{range .items[*]}{.metadata.name}{" noroot="}{.spec.securityContext.runAsNonRoot}{" seccomp="}{.spec.securityContext.seccompProfile.type}{" priv-esc="}{.spec.containers[0].securityContext.allowPrivilegeEscalation}{" drop="}{.spec.containers[0].securityContext.capabilities.drop}{" ro="}{.spec.containers[0].securityContext.readOnlyRootFilesystem}{" automount="}{.spec.automountServiceAccountToken}{"\n"}{end}'
prueba-6899c74865-rzh88 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-6m6s6 noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
revisor-654b5d75dc-dq4pp noroot=true seccomp=RuntimeDefault priv-esc=false drop=["ALL"] ro=true automount=false
```

Три Pod-а, три еднакви реда: двата на `revisor` и този на `prueba` (ако `CronJob`-ът вече се е задействал, щеше да се появи четвърти, със същите стойности). Във всеки: `noroot=true` (Pod-ът работи като не-`root`), `seccomp=RuntimeDefault`, `priv-esc=false`, `drop=["ALL"]`, а освен това `ro=true` и `automount=false`, които са на курса, а не на `restricted`. Поискан беше само първият контейнер (`containers[0]`), а всеки от тези Pod-ове има само един. Тази заявка не замества `dry-run` (който проверява всички контроли, не само онези, които написах в `jsonpath`); допълва го: позволява ти да *видиш* стойностите.

#### 10.7.4 Част от платформата не отговаря на `restricted` и това е наред (с едно условие)

Пространството `revisor` е единственото с етикети. Какво би казал сървърът, ако ги сложиш на пространствата на платформата? Пита се със същата заявка, без да се променя нищо (`cut` отрязва всеки ред, за да се събере). Тук заявката наистина проверява Pod-овете, защото тези пространства нямат етикета и слагането му е промяна. Друга разлика от предишната заявка: тези пространства нямат етикет за версия, така че сървърът сравнява с най-новата версия на политиката (`restricted:latest`) и го казва в първото предупреждение:

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

Три пространства, три различни отговора:

- **`envoy-gateway-system`: без предупреждения.** Казва „labeled (server dry run)“ и нищо повече. Pod-овете на Envoy Gateway (контролерът и Envoy-ите, които обслужват входната точка) отговарят на `restricted`. Това е информация, която е добре да знаеш и която не е очевидна: не цялата платформа иска привилегии.
- **`metallb-system`: да.** `controller` нарушава два контрола: „unrestricted capabilities“ (запазва възможности на Linux, които `restricted` задължава да се премахнат) и „seccompProfile“ (не декларира профил). Трите `speaker` нарушават повече: „host namespaces“ и „hostPort“ (споделят мрежата на възела), „probe or lifecycle host“, „runAsNonRoot != true“ и същите възможности и профил. `speaker` е този, който отговаря на ARP въпросите на мрежата (слой 2 от 10.10, точка 5) и за това трябва да вижда мрежата на възела, а не собствена мрежа: предупреждението „host namespaces“ е техническото име на тази нужда.
- **`kube-system`: да, и то много.** Двата `coredns` нарушават `runAsNonRoot` и профила `seccomp`. Четирите Pod-а на контролната равнина (`etcd` и трите му събратя) споделят мрежата на хоста и монтират пътища на възела („restricted volume types“). `kindnet` и `kube-proxy` споделят мрежата на хоста и запазват възможности, а `kube-proxy` освен това работи като `privileged`.

(„(and 2 other pods)“ е на сървъра: групира Pod-овете, които нарушават едно и също, за да не повтаря реда.)

Това не е дефект на курса: това е, което се случва, когато едно парче инфраструктура има нужда от привилегии, за да върши работата си (да говори с мрежата на възлите, да обявява адреси, да монтира пътища на възела). Смисълът е двоен. Първо, **привилегиите съществуват и са някъде**: платформата ги концентрира в собствените си пространства, а проектът, който е онова, което се променя всеки ден, живее без тях. Второ, тези пространства имат **условие**: никой друг не бива да може да създава Pod-ове там, защото който може да създаде Pod в `metallb-system` или в `kube-system`, има, фактически, привилегиите на това пространство. В истински клъстер това се решава с RBAC (кой какво може да създава къде) и с ниво `baseline` или `privileged`, *декларирано* за всяко пространство на платформата —писмено решение, със собственик—, а не с пространство без етикет. Тук не се слагат етикети и 10.10 го отбелязва.

#### 10.7.5 Положителният контрол: Deployment, който наистина нарушава `restricted`

За да знаеш, че „нито едно предупреждение“ значи нещо, изпитва се с Deployment, който **трябва** да ги произведе. `fig10_02.deployment-malo.yaml` е **програма, която се проваля нарочно**: Deployment, който не казва нищо за сигурността.

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

Три неща, в този ред. **При прилагането**, едно `Warning` с четири нарушени контрола: `allowPrivilegeEscalation != false`, `unrestricted capabilities`, `runAsNonRoot != true` и `seccompProfile`, всеки с точното поле, което липсва (`container "malo" must set securityContext.allowPrivilegeEscalation=false`…). И отдолу, `deployment.apps/malo created`: Deployment-ът **е създаден**. Второ, Deployment-ът е в `READY 0/1`: няма нито един Pod. Трето, събитията на ReplicaSet-а: `FailedCreate`, „Error creating: pods "malo-…" is forbidden: violates PodSecurity "restricted:v1.37"“, със същия списък. Там действа режимът `enforce` и се вижда, че го е направил при създаването на Pod-овете, не на Deployment-а.

Това е, което 10.7.2 обявяваше: Deployment-ът *се приема* (с предупреждения, от режима `warn`), а Pod-овете *се отхвърлят* (от режима `enforce`); ReplicaSet-ът записва всяко отхвърляне като събитие `FailedCreate`. И това е причината да четеш изхода на `apply`. Изтрива се:

```text
$ kubectl delete -n revisor -f fig10_02.deployment-malo.yaml
deployment.apps "malo" deleted from revisor namespace
```

С това твърдението на проекта остава в сила с контрол: проектът не произвежда предупреждения (броене 0 в 10.5.3), а Deployment, който нарушава политиката, **ги** произвежда. Упражнение 2 те моли да поправиш този.

### 10.8 Проверка на целите

README-то на курса завършва със седем цели: не „прочете уроците“, а „проектът ти изпълнява това“. Този раздел проверява в клъстера онези, които могат да се измерят. Първо, картата, за да знаеш къде е всяка:

| Цел | Какво казва | Къде се проверява |
|---|---|---|
| 1 | от току-що създаден клъстер проектът остава да работи в три стъпки и се възстановява след изтриване | 10.5 (ръчно) и 10.6 (със скрипта, два кръга) |
| 2 | пространството от имена е на `restricted` и няма предупреждения при прилагане | 10.5.3 и 10.7 |
| 3 | един работен възел се спира и услугата продължава да отговаря, с измерен прозорец | 10.8.3 |
| 4 | промяната на списъка от услуги прави *rollout* сама | 10.8.1 |
| 5 | с натоварване мащабирането качва и сваля реплики | измерено в Урок 9; 10.8.4 проверява, че е все още свързано |
| 6 | чужд Pod не говори с `revisor`, а акаунтът на `revisor` не може нищо | 10.8.2 |
| 7 | можеш да кажеш, писмено, пет причини, поради които това не е продукция | 10.10 и Упражнение 4 |

#### 10.8.1 Цел 4: промяната на списъка променя репликите, без да се докосва образът

Това е Урок 4, видян от края: конфигурацията живее извън образа. Първо, състоянието преди промяната: ReplicaSet-ът, който има репликите, и генерираният `ConfigMap` с неговия *hash*.

```text
$ kubectl get replicaset -n revisor -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-654b5d75dc   2         2         2       92s

$ kubectl get configmap -n revisor
NAME                        DATA   AGE
kube-root-ca.crt            1      92s
revisor-config-t6cm6872fk   1      92s
```

Времето за изчакване на тестовата услуга се сменя от `2s` на `1s` в базата. `sed -i.bak` редактира файла на място и оставя копие с разширение `.bak` (начинът, който работи еднакво в Linux и в macOS); `diff` сравнява копието с новия файл, за да видиш точно какво се е променило:

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

Тук командата филтрира двата реда, които имат значение:

```text
$ kubectl apply --server-side -k overlays/kind 2>&1 | grep -E 'configmap|deployment.apps/revisor'
configmap/revisor-config-cmb662hmbh serverside-applied
deployment.apps/revisor serverside-applied
```

Файлът се възстановява (`.bak` се връща на името си) и се чака да завърши *rollout*-ът:

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

Какво се промени: `diff` показва един-единствен ред, `2s` вместо `1s`. `apply` приложи два обекта: **нов** `ConfigMap`, `revisor-config-cmb662hmbh` (друг *hash*, защото съдържанието е друго), и Deployment-а, който генераторът пренаписа, за да сочи към него. *Rollout*-ът създаде нов ReplicaSet с двете реплики и остави стария в `0 0 0`. И онова, което не се промени: образът. `curso-docker-revisor:1.6.0` не беше изграден наново, не беше зареден отново и не беше докосван. Старият `ConfigMap` си стои в клъстера, без никой да го ползва: това е цената на Урок 4. `kube-root-ca.crt` не е твой: Kubernetes го създава във всяко пространство от имена.

И тъй като файлът пак казва `2s`, трябва да се върне и клъстерът. **Файлът е истината**: ако клъстерът и файловете се различават, клъстерът се коригира с ново прилагане, не се отбелязва „знам, че е различно“:

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

При връщането към оригиналния файл `ConfigMap`-ът, който се прилага, е отново `revisor-config-t6cm6872fk`, предишният. Тъй като шаблонът на Pod-а пак е идентичен с този на първия ReplicaSet, Deployment-ът **го преизползва**: качва стария от 0 на 2 и сваля току-що създадения, вместо да сглоби трети. Остават два ReplicaSet-а, единият активен и единият в `0 0 0`; тези празни ReplicaSet-и са онова, което `rollout undo` ползва, за да се върне (Урок 9).

#### 10.8.2 Цел 6: мрежата и правата

Две малки проверки, в пространството `revisor`: един Pod **с** етикета `acceso-revisor: permitido` (`depurar`) и друг **без** него (`intruso`). И двата са Pod-ове с `curl`, които вече отговарят на `restricted`, така че клъстерът ги приема:

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

Първият е положителният контрол: без него вторият не би доказал нищо, защото един `curl`, който се проваля, може да се провали по хиляда причини. `depurar` стига (мрежата го пуска), `intruso` не. Четенето на кода е ключът. `curl` излиза с **28** (*operation timed out*): минаха 3-те секунди на `-m 3` без отговор. Ако мрежата отхвърляше връзката, `curl` щеше да излезе със 7 („не можах да се свържа“), както в Урок 3. Една `NetworkPolicy`, която не пуска пакет, **го изхвърля, без да отговори**, и клиентът остава да чака: затова 28 е отпечатъкът на затворена мрежа, а не на недостъпна услуга.

И правата на акаунтите, с `kubectl auth can-i`, който пита клъстера дали една идентичност би могла да направи нещо, без да го прави:

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

Четири отговора и една таблица ги обобщава: акаунтът `revisor` **не** може да чете Pod-ове, нито Secret-и (`no`, `no`); акаунтът `observador` **може** да чете Pod-ове (`yes`) и **не** може да ги изтрива (`no`). Кодът на излизане на `can-i` е 1, когато отговорът е `no`, и затова скриптът отбелязва `[código de salida: 1]`, без да има никакъв провал. Акаунтът на `revisor` дори няма монтирани удостоверения (`automountServiceAccountToken: false`), така че отговорът е двоен: не може и дори да можеше, Pod-ът няма с какво да извика API-то.

#### 10.8.3 Цел 3: един възел се спира и услугата продължава да отговаря

Това е изпитването, най-близко до онова, което се случва в истински клъстер, и това, което най-много учи. Един работен възел е Docker контейнер; спирането му с `docker stop` прилича на внезапно изключване на машината. Иска се да се знаят три неща: услугата продължава ли да отговаря? Проваля ли се нещо междувременно? Колко продължава?

**Преди да предскажеш, числата на клъстера.** [Документацията за състоянието на възлите](https://kubernetes.io/docs/reference/node/node-status/) описва механизма: всеки `kubelet` подновява обекта `Lease` на своя възел **на всеки 10 секунди** (това е пулсът), контролерът на възлите проверява пулсовете **на всеки 5 секунди** (`node-monitor-period`), а условието `Ready` преминава в `Unknown`, ако в рамките на `node-monitor-grace-period` не е чул нищо от възела: **50 секунди по подразбиране** (също като стойност по подразбиране в [справочника на `kube-controller-manager`](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/)). 50-те секунди се броят от **последния пулс, който контролерът е получил**, не от `docker stop`: този пулс може да е пристигнал до 10 секунди преди изключването на възела, а контролерът го забелязва едва при следващата си проверка (до 5 секунди по-късно). След сумирането, клъстерът научава между около 40 и около 55 секунди след `docker stop`; тъй като цикълът на измерване стартира няколко секунди по-късно, от неговия часовник прозорецът пада няколко секунди по-рано. Докато срокът не изтече, клъстерът *не знае*, че възелът е изчезнал. А [документацията за *taints* и толеранси](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) казва, че когато възелът вече е `Unknown`, Pod-овете не се изселват веднага: по подразбиране понасят петното „недостижим възел“ в продължение на **300 секунди** (`tolerationSeconds`) и едва тогава се подменят на друг възел.

Прогнозата, значи: с две реплики (по една на работен възел), при спиране на единия възел **средно половината от заявките** трябва да се провалят, докато трае този прозорец (десетки секунди). [Документацията за Services](https://kubernetes.io/docs/reference/networking/virtual-ips/) казва, че в режимите `iptables` и `nftables` `kube-proxy` инсталира правила, които по подразбиране избират целевия Pod **на случаен принцип**: не е стриктен ред, така че при около 25 заявки реалното съотношение може да се отдалечи от половината. Междувременно един адрес вече не отговаря, а клъстерът още не го знае. Щом прозорецът мине, мъртвата реплика излиза от списъка с адреси и всичко трябва да се оправи.

Експериментът. Една подробност преди това: проверката на *rollout* от 10.8.1 току-що замени Pod-овете, а старите се забавят няколко секунди да изчезнат. За да не се мери с Pod-ове, които си отиват, се чака да останат само двата актуални (още един цикъл с горна граница, като този на мащабирането):

```bash
for _ in $(seq 1 60); do
  [ "$(kubectl get pods -n revisor -l app=revisor --no-headers | wc -l | tr -d ' ')" = 2 ] && break
  sleep 2
done
```

И сега наистина, къде са репликите, за да не спираме възела на Pod-а, който играе ролята на клиент:

```text
$ kubectl get pods -n revisor -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                    NOMINATED NODE   READINESS GATES
revisor-654b5d75dc-qcqfz   1/1     Running   0          15s   10.244.2.7   curso-k8s-l10-worker2   <none>           <none>
revisor-654b5d75dc-xmvc5   1/1     Running   0          17s   10.244.1.7   curso-k8s-l10-worker    <none>           <none>
```

Като жертва се избира работен възел, който не е този на `depurar` (клиентът, който ще мери отвътре на клъстера), и контейнерът му се спира. Жертвата излиза от списък на работните възли без този на клиента; урокът ползва `case`, който вече познаваш, за да не се спре нищо, което не е на този клъстер:

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

И клиентът: цикъл вътре в `depurar`, който прави една заявка на всеки 2 секунди в продължение на 90, с ограничение от 2 секунди за всяка, и отпечатва само когато резултатът **се променя** (един ред на промяна, не един на заявка):

```bash
ctx && kubectl exec -n revisor depurar -- sh -c 'inicio=$(date +%s); ok=0; mal=0; ant=""; while [ $(( $(date +%s) - inicio )) -lt 90 ]; do t=$(( $(date +%s) - inicio )); if curl -s -m 2 -o /dev/null http://revisor/salud; then r=ok; ok=$((ok+1)); else r=FALLA; mal=$((mal+1)); fi; [ "$r" != "$ant" ] && echo "[+${t}s] $r"; ant=$r; sleep 2; done; echo "bien=$ok mal=$mal"'
```

(Цикълът е написан в единични кавички, за да го интерпретира `sh`-ът *вътре* в Pod-а, а не твоят. `date +%s` дава секундите от 1970; изваждането с `inicio` е изтеклото време; `curl -m 2` се предава на 2-рата секунда.)

```text
[+0s] FALLA
[+4s] ok
[+6s] FALLA
[+22s] ok
[+31s] FALLA
[+51s] ok
bien=24 mal=10
```

Чети го като времева линия (редовете са *промени*, не заявки). Започва с провал (`[+0s] FALLA`), отново отговаря на 4-тата секунда, пак се проваля на 6-тата и не отговаря до 22-рата; отговаря до 31-вата, проваля се пак до 51-вата и **от секунда 51 всичко отговаря** до края на 90-те. В края: `bien=24 mal=10`, 34 заявки, и 10-те провала паднаха всички преди секунда 51. Това съвпада с механизма по-горе: на клъстера му трябваше толкова, колкото им трябва на пулсовете и на срока му, за да се усети. С „редуването“ не съвпада съвършено: има отрязъци от по няколко секунди последователни провала, а не един провал и един успех на ход. Така казва документацията за Services: целта се избира **на случаен принцип** при всяка връзка, така че от време на време излизат няколко поредни към мъртвия адрес. (Всяка неуспешна заявка струва и 2 секунди ограничение, затова в прозореца се побират по-малко заявки, отколкото през останалата част на изпитването.) Не бива и да се приема 51 за константа: при другите три подготвителни изпълнения на урока (записани в `programas/10-proyecto-final/corridas-preparacion/`) услугата отново отговори без провал на 36, 50 и 34 секунди. Четирите прозореца, от 34 до 51 секунди, са онова, което предсказва механизмът: зависят от това колко стар е бил последният пулс, когато възелът е спрян (от 0 до 10 секунди), от проверката на контролера (на всеки 5) и от секундите, които минават между `docker stop` и първия опит на цикъла. [Урок 9](09-escalar-y-actualizar.md) (9.12.2) измери същия механизъм от друг ъгъл: възелът премина в `NotReady` на 57-ата секунда след изключването. Онова, което се запазва от изпълнение в изпълнение, е порядъкът: десетки секунди, не минути.

И състоянието на клъстера в този миг, **преди** да вдигнем възела:

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

Три данни, които изглежда си противоречат и не е така. Възелът `curso-k8s-l10-worker2` е `NotReady`: клъстерът вече го е сметнал за изгубен. Но Pod-ът, който живее в него, продължава да се води `1/1 Running`: клъстерът ще го изброява, докато не изтекат 300-те секунди толерантност, и едва тогава ще го подмени на друг възел. А `EndpointSlice`-ът на Service-а вече отбелязва адреса на този Pod (`10.244.2.7`) с `listo=false`: **спря да получава трафик**, макар списъкът с Pod-ове още да го показва. Практическият урок е, че `READY 1/1` в `kubectl get pods` и „получава трафик“ не са едно и също; за да знаеш дали един Pod получава заявки, гледаш `EndpointSlice` (Урок 3).

Възелът се вдига и се чака да се върне:

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

Промяната на брояча на рестартиранията се бави да се види. Погледни брояча малко след като възелът се върне в `Ready` (по-горе, `RESTARTS`), изчакай да отчете рестарта с още един цикъл с горна граница и погледни отново:

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

Възелът се връща в `Ready` и първият списък с Pod-ове заблуждава: продължава да казва `RESTARTS 0` и IP от преди (`10.244.2.7`). Няколко секунди по-късно броячът наистина се променя: Pod-ът `…-qcqfz` казва `1 (7s ago)` и освен това **има друг IP**: `10.244.2.5`. Това е същият Pod, със същото име, но контейнерът му е рестартиран и адресът му се е променил. Заявката за `lastState` го обяснява: последният край на контейнера е с причина `Unknown` и код `255`, тоест не го е убила никоя проба, нито `OOMKilled`; изчезна заедно с възела си, който се изключи цял, и никой не успя да запише нормален код на излизане. Другата реплика, на възела, който никога не е бил спиран, остана с нула рестартирания. Две последици за теб: брояч на рестартирания, различен от нула, **не** значи винаги, че нещо се е счупило в твоята програма (тук беше възелът), и IP на Pod не се запазва за после, което е Урок 3 отново.

**Какво скъсява този прозорец и какво не.** С онова, което измери, честният отговор:

- **Повече реплики, разпределени между повече възли.** Ако вместо две има шест, разпределени в три възела, спирането на един засяга по-малка част от заявките. Това вече правят мащабирането и разпределението от Урок 9: не скъсяват времето, намаляват дела.
- **Повторни опити в клиента.** Заявка, която се проваля и се повтаря, пада, с голяма вероятност, на другата реплика. Клиентът на това изпитване не повтаря нарочно, за да видиш суровия ефект; един истински би трябвало.
- **По-кратък `node-monitor-grace-period`**, в контролната равнина, който скъсява прозореца срещу повече фалшиви тревоги (възел с кратък мрежов проблем от няколко секунди би се сметнал за изгубен). В управляван клъстер се иска от доставчика; в `kind` не го променяш в този урок.

И онова, което **не** го скъсява, макар да изглежда:

- **Пробите.** Изпълнява ги `kubelet`-ът на самия възел, който е точно този, който е престанал да съществува. Една проба не може да съобщи за отсъствието на програмата, която я изпълнява.
- **`tolerationSeconds`.** Решава за колко време Pod-овете се *подменят* на друг възел, не кога престават да получават трафик. Скъсяването му подменя по-рано, но трафикът би продължил да отива към мъртвия адрес, докато възелът не се сметне за изгубен.

Едно изречение, което важи като резюме: клъстерът понася падането на възел, **но не и падането му, без никой да го забележи в продължение на десетки секунди**. Това е разликата между „оцелява“ и „без прекъсвания“ и затова целта на курса казва „с измерен прозорец“.

#### 10.8.4 Цел 5: мащабирането е все още свързано

Измерването колко време му трябва на мащабирането да качи и да свали с натоварване заема 15 минути и цял урок: това е Урок 9 и не се повтаря тук. Онова, което се проверява, е че в клъстера, разгърнат от нулата, **е все още свързано с метриките**:

```text
$ kubectl get hpa -n revisor
NAME      REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
revisor   Deployment/revisor   cpu: <unknown>/50%   2         6         2          3m32s
```

При това изпълнение, точно след рестартирането на възела, мащабирането каза `cpu: <unknown>/50%`: загуби четенето на метриките. Не беше проучено на кой възел работи `metrics-server`, нито защо се прекъсна; измереното е, че един рестартиран възел остави мащабирането без данни за известно време. (При други подготвителни изпълнения на урока не се случи: вече носеше процента.) Това е пример защо `<unknown>` не се тълкува, без да се погледне какво току-що е станало в клъстера.

Ако в твоя клъстер казва `<unknown>`, не се тревожи още: това е причината от Урок 9 и се решава с чакане, но с горна граница. Същият цикъл от 10.5.3, който проверява на всеки 5 секунди до три минути:

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

Цикълът изчака и мащабирането се възстанови само: `cpu: 3%/50%`, `MINPODS 2`, `MAXPODS 6` и две реплики. Между двете `get` мина малко повече от минута (колоната `AGE` върви от 3m32s до 4m33s). С това целта 5 е проверена в онова, което този урок може да провери: мащабирането е свързано с метриките, а границите му са тези на базата. Качването и свалянето на реплики с натоварване е Урок 9.

А ако цикълът се предаде и продължава да казва `<unknown>`, другата причина, която видя в Урок 9, е `metrics-server` без флага `--kubelet-insecure-tls` (от който `kind` има нужда).

### 10.9 Helm, с едно споменаване

Има един инструмент, който ще видиш в почти всеки проект на Kubernetes и който този курс не ползва: **Helm**. [Документацията на Helm](https://helm.sh/docs/intro/using_helm/) го нарича мениджър на пакети за Kubernetes. Четири думи, които е добре да разпознаваш: **chart** е пакет (папка с шаблони на манифести плюс стойностите им по подразбиране); **values** са стойностите, които променяш за твоята инсталация; **release** е конкретна инсталация на един chart в един клъстер; а **хранилище** (или регистър на OCI образи) е мястото, където се публикуват.

Примерът е в ръководството на Envoy Gateway, което вече познаваш. Освен че го инсталира с `install.yaml`, което ползва курсът, [това ръководство](https://gateway.envoyproxy.io/docs/install/install-helm/) го инсталира с Helm така (командата е тази на ръководството за версия v1.9.2; **не беше изпълнявана в този урок**):

```text
helm install eg oci://docker.io/envoyproxy/gateway-helm --version v1.9.2 -n envoy-gateway-system --create-namespace
```

`eg` е името на *release*-а, `oci://docker.io/envoyproxy/gateway-helm` е chart-ът, а `--version` фиксира версията му, с `--create-namespace`, за да се създаде пространството, където се инсталира.

Защо курсът ползва Kustomize, а не Helm? Защото сравнява две различни идеи и за да се учи, е добре първо да се види по-простата:

| | Kustomize | Helm |
|---|---|---|
| Идея | тръгва от пълен YAML и **го променя** със слоеве | тръгва от **шаблони** с празни места и **ги попълва** със стойности |
| Какво четеш | обикновен YAML; каквото виждаш, това се прилага | шаблони с логика; за да видиш резултата, `helm template` |
| Промени между среди | overlays и кръпки | файлове със стойности (`values`) |
| Какво още прави | нищо: сглобява и предава на `kubectl` | води история на *releases*, обновява и може да се върне към предишна версия |
| Идва с `kubectl` | да (`kubectl kustomize`, `apply -k`) | не: е отделна програма |

Едно много ползвано практическо правило, което тук е мнение, а не норма: **Kustomize за твоето, Helm за чуждото.** Твоето е YAML, който си написал и искаш да четеш; чуждото (MetalLB, Envoy Gateway, мониторинг) обикновено се публикува като chart с дузини опции, които някой друг вече е обмислил. Много екипи ползват и двата: инсталират платформата с Helm, а проекта си — с Kustomize.

И проблемът на този урок съществува и там. [Препоръчаните практики на Helm за CRD](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) казват, че CRD-тата на един chart се инсталират първи (живеят в специална папка, `crds/`), че **Helm не ги обновява и не ги изтрива** заради опасността от загуба на данни и че ако един chart трябва да ползва типове, които самият той дефинира, най-удобно е да се разделят на два chart-а, които се инсталират поотделно. Това е същият ред —типове, контролер, проект— с друго име.

### 10.10 Какво се променя в истински клъстер

#### 10.10.1 Какво изгради и какво му липсва

В края на един курс има изкушение: да повярваш, че онова, което работи на машината ти, е „почти“ готово да работи наистина. Този раздел съществува, за да го разруши честно, без драматизъм. `kind` върши добре онова, което обещава: да докаже, че **разбираш** Kubernetes. Собствената му страница казва, че е „проектиран главно за тестване на самия Kubernetes“, макар да може да се ползва за локална разработка или за непрекъсната интеграция. Не обещава клъстер, който да издържи онова, което изисква една истинска услуга. [Документацията на Kubernetes за продукционни среди](https://kubernetes.io/docs/setup/production-environment/) започва с изречение, което обобщава разликата (в превод): една типична продукционна среда „има повече изисквания от лична среда за учене, разработка или тестване“.

Списъкът, който следва, има четиринайсет неща. Не е нужно да ги запомниш всичките; нужно е да разпознаеш модела: почти всяко е парче, което **в `kind` съществува в лабораторна версия** и в истински клъстер трябва да се замени, подсили или добави. Всяко казва какво прави курсът, какво изисква един истински клъстер, какво би се направило и откъде идва.

**1. Контролна равнина само с един възел.** Курсът има един контролен възел. Ако се спре, не можеш да промениш нищо, а какво още спира да работи не е сигурно: в Упражнение 3 вече стартираните контейнери продължиха да работят, но входната точка продължи да отговаря само в 1 от 4 изпълнения. Един истински клъстер репликира контролната равнина в няколко възела и разпределя натоварването към сървъра на API-то; [документацията за продукционни среди](https://kubernetes.io/docs/setup/production-environment/) изброява точно тези парчета и напомня, че среда от една-единствена машина „има единична точка на отказ“. Много екипи предпочитат контролна равнина, управлявана от доставчик.

**2. `etcd` без изпитано резервно копие.** Цялото състояние на клъстера —обектите, които си приложил— живее в `etcd`. Ако се загуби, губи се клъстерът. [Ръководството за работа с `etcd`](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) показва как да се направи копие с `etcdctl snapshot save` и как да се провери с `etcdutl snapshot status`. И тук се връща случаят с GitLab от началото: резервното копие, което не е възстановявано на проба, не е резервно копие. Планира се и се **възстановява наистина** в тестов клъстер с периодичност, която някой решава.

**3. Тайни, съхранявани нешифровани.** Видя го в Урок 4: един `Secret` е base64 и в `etcd` се съхранява в чист текст, освен ако администраторът не настрои шифроването в покой. [Ръководството за шифроване на данните в покой](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) обяснява как се настройва в `kube-apiserver`, а [контролният списък за сигурност](https://kubernetes.io/docs/concepts/security/security-checklist/) го изисква: „шифроването в покой е настроено за API-то на Secrets“. За тайни, които не би трябвало да живеят в клъстера, същият списък споменава да се инжектират от външно хранилище.

**4. HTTP в чист текст.** Входната точка на `revisor` говори HTTP на порт 80, а токенът пътува в заглавие без шифроване (Урок 6 го измери). Един истински клъстер прекратява TLS в *Gateway*: [ръководството за TLS на Gateway API](https://gateway-api.sigs.k8s.io/guides/tls/) описва как един HTTPS *listener* прекратява шифроването със сертификат. Освен това трябва да се издава и подновява, а списъкът за сигурност пита за шифроването вътре в клъстера (което зависи от CNI или от service mesh).

**5. Адрес, който MetalLB разпределя в Docker мрежа.** На слой 2, [документацията на MetalLB](https://metallb.io/concepts/layer2/) го казва: целият трафик на един IP отива към **един-единствен възел** и оттам `kube-proxy` го разпределя. „В този смисъл слой 2 не реализира балансьор на натоварването: реализира механизъм за *failover*.“ Двете му ограничения са тясно място в един възел и потенциално бавно превключване. В облака балансьорът го дава доставчикът; в собствен център за данни обикновено се ползва MetalLB в режим BGP или друг балансьор.

**6. `metrics-server` с `--kubelet-insecure-tls`.** Видя го в 10.3.4: „само за тестове“, казва собственото му README. В истински клъстер сертификатите на `kubelet` се подписват с удостоверителния орган на клъстера и флагът е излишен. README-то му добавя нещо, което има значение: `metrics-server` е **само** за автоматичното мащабиране; за мониторинг се ползва друго нещо.

**7. Възли, които са контейнери на твоята машина.** Трите „възела“ споделят твоя процесор, твоята памет, твоя диск и твоя kernel. Ако компютърът ти се изключи, изключва се всичко; няма зони на достъпност, нито различни центрове за данни. Един истински клъстер разпределя възлите между зони и разпределя репликите между тях (кръпката на `ejemplo-nube` от 10.3.3 променя точно това, от възли на зони) и има повече от един от всичко, което има значение.

**8. Съхранение, което живее във възела.** Томът на отчета е директория от диска на един възел (`local-path`, Урок 8): ако възелът изчезне, изчезват и данните. Един истински клъстер ползва външно съхранение с репликация и копия, а данните имат същата история на резервно копие като `etcd`: има копие и има изпитание на възстановяването.

**9. Ръчно заредени образи.** Двата образа на курса пристигнаха с `kind load docker-image`, с локален етикет. Един истински клъстер ги сваля от регистър. [Списъкът за сигурност](https://kubernetes.io/docs/concepts/security/security-checklist/) изисква да се сочат **по отпечатък `sha256`** (digest; защото един етикет може да се премести в регистъра), да се проверяват със скенер за уязвимости и да се проверява подписът им с контролер за допускане. Курсът вече фиксира отпечатъка на образа на `curl`; тези на `revisor` и на тестовия, които са локални, не.

**10. Един администратор и никаква идентичност.** Твоят `kubeconfig` на `kind` е на пълен администратор; никой друг не влиза. Един истински клъстер има потребители и групи с различни права, доставчик на идентичност и периодичен преглед на достъпите. Списъкът за сигурност изисква, например, групата `system:masters` да не се ползва за удостоверяване на хора или компоненти след стартирането, и преглед на достъпите „не повече от 24 месеца“ между единия и другия.

**11. Наблюдаемост, която е `kubectl logs`.** Имаш журнал, докато Pod-ът съществува. [Документацията за *logging*](https://kubernetes.io/docs/concepts/cluster-administration/logging/) го обяснява ясно (в превод): ако един контейнер падне, един Pod бъде изселен или един възел умре, искаш да продължиш да виждаш журналите им; затова те трябва да имат съхранение „с жизнен цикъл, независим от възлите, Pod-овете и контейнерите“, а Kubernetes „не предоставя вградено решение“ за това. Липсва и частта с исторически метрики и аларми: някой, който да те предупреди, преди да го открие ръководството.

**12. Обновявания без план.** Клъстерът на курса се създава и се изтрива; истинският се обновява в движение, в продължение на години. [Политиката за поддържани версии](https://kubernetes.io/releases/version-skew-policy/) казва, че проектът поддържа трите най-нови минорни версии (днес 1.37, 1.36 и 1.35), с около година корекции, и определя каква разлика може да има между компонентите (един `kubelet` може да е до три минорни версии зад сървъра на API-то, никога пред него). А всяко парче на платформата има свой собствен ред на обновяване: ръководството на Envoy Gateway изисква първо да се обновят CRD-тата на Gateway API и предупреждава какво става, ако не се направи.

**13. Без квоти и ограничения по екип.** Урок 5 сложи `requests` и `limits` във всеки контейнер, но нищо не пречи на някого да създаде сто Pod-а. [Документацията за квотите](https://kubernetes.io/docs/concepts/policy/resource-quotas/) описва `ResourceQuota`: ограничения на общата консумация **на пространство от имена** и на броя обекти от всеки тип. С няколко екипа в един клъстер това е, което пречи на един да изяде дела на останалите.

**14. Платформа без собственик и без декларирано ниво на сигурност.** 10.7.4 го показа: пространствата на MetalLB и на `kube-system` не отговарят на `restricted` (това на Envoy Gateway — да), а тук нито едно от трите няма етикет, нито отговорник. В истински клъстер всяко пространство на платформата има декларирано ниво и отговорен екип, а *webhooks* на тази платформа са **зависимост на клъстера**: тъй като `failurePolicy` по подразбиране е `Fail` (10.4.1), ако Pod-ът на пазача е паднал, не могат да се създават обектите, които той наблюдава. Затова им се дава повече от една реплика и се наблюдават като всяка критична услуга.

Нищо от това не прави безполезно онова, което изгради. Напротив: проектът на този урок, базата, с всичките си обекти, **е** онова, което би се пренесло в истински клъстер. Онова, което се променя, е долният слой —overlay-ът и платформата—, а това е точно слоят, който Kustomize отделя.

#### 10.10.2 Четиринайсетте, в една таблица

| # | В курса | В истински клъстер |
|---|---|---|
| 1 | един контролен възел | няколко контролни възела или един управляван |
| 2 | `etcd` без резервно копие | копия на `etcd` с изпитания на възстановяването |
| 3 | `Secret` нешифриран в `etcd` | шифроване в покой и/или външно хранилище за тайни |
| 4 | HTTP на порт 80 | TLS, прекратен в Gateway |
| 5 | MetalLB на слой 2 върху Docker мрежа | балансьор на доставчика или MetalLB с BGP |
| 6 | `--kubelet-insecure-tls` | сертификати на `kubelet`, подписани от клъстера |
| 7 | възли, които са контейнери | възли в няколко зони, с реплики, разпределени между тях |
| 8 | том на диска на един възел | външно репликирано съхранение, с копия |
| 9 | ръчно заредени образи | регистър, отпечатък `sha256`, сканиране и подпис |
| 10 | един администратор | идентичности, групи, преглед на достъпите |
| 11 | `kubectl logs` | журнали и метрики със собствено съхранение и аларми |
| 12 | клъстер за еднократна употреба | план за обновяване по версия |
| 13 | без квоти | `ResourceQuota` на пространство |
| 14 | платформа без декларирано ниво | ниво и собственик на пространство и реплики за *webhooks* |

Ако трябваше да подредиш този списък по „какво ме тревожи първо“, няма единствен отговор: зависи от това какво губиш, ако се провали. Но разумен критерий е да се започне с онова, което **не може да се възстанови**. Проектът може да се възстанови (току-що го направи, два пъти); данните на отчета и състоянието на `etcd` — не. Затова резервното копие с изпитано възстановяване (2 и 8) обикновено е преди почти всичко останало, а шифроването и TLS (3 и 4) са наред с онова, което се излага. Упражнение 4 те моли точно за това.

## Грешката, която ще видиш

Този урок има три нарочни грешки и вече ги видя в техния раздел: платформата, приложена без `--server-side` (10.4.3), платформата и проектът заедно в една команда (10.4.4) и един Deployment, който нарушава `restricted` (10.7.5). И трите имат нещо общо, което е добре да се каже с всички букви, защото е онова, което наистина се научава: **нито една не е грешка на клъстера**. Клъстерът направи точно онова, което му беше поискано, и каза ясно защо не може. Онова, което се промени между неуспешния и успешния опит, беше *редът или начинът на искане*, не клъстерът.

Редът за разчитане на която и да е от тях е същият като в предишните уроци, сега с инструментите на този:

1. Какво казва **кодът на излизане** на `apply` и кои редове **не** са `created` или `serverside-applied`? Там е съобщението.
2. Съобщението споменава ли **тип, който не съществува** (`no matches for kind`, `ensure CRDs are installed first`) или **пазач, който не обслужва** (`failed calling webhook`)? Тогава остава да се изчака платформата: изчакване по условие, не повторен опит.
3. Споменава ли **размер** или **конфликт на мениджър** (`Too long`, `conflict`)? Тогава е от начина на прилагане: `--server-side`.
4. **Предупреждение** ли е (`Warning: would violate PodSecurity`)? Обектът е приет и няма да работи: поправи манифеста.

И преди да промениш каквото и да е, прилагането на същата команда втори път, за да „видиш дали ще мине“, **не е диагноза**: 10.4.4 ти показа, че понякога минава наполовина и оставя най-лошото, състояние, което изглежда здраво и не е.

## Навикът за сигурност от урока: проверява се спрямо нормата и се казва какво липсва

Таблицата с навиците на курса възлага на този урок две неща: финалния преглед спрямо нивото `restricted` и списъка с онова, което един истински клъстер изисква. И двете са навици да **не се доверяваш на онова, което изглежда**.

**Прегледът с контрол.** Една заявка, която казва „без предупреждения“, не струва нищо сама по себе си, защото инструмент, който не проверява, и такъв, който проверява и не намира нищо, казват едно и също. Затова 10.5.3 брои предупрежденията (`grep -ci warning`), 10.7.5 прилага Deployment, който **трябва** да ги произведе, а 10.7.3 изпитва заявката за преглед в пространство с Pod, който нарушава: първата заявка, написана върху `revisor`, даваше нула предупреждения и не проверяваше нищо, и именно този контрол го показа. Ако вторият случай не беше произвел предупреждения, първият не би означавал нищо. Това е същият принцип, с който се мери всичко: преди да повярваш на една нула, покажи ѝ нещо, което трябва да се брои.

**Списъкът с онова, което липсва.** Това е вторият навик и най-неудобният: да запишеш онова, което *нямаш*. Проект, който казва „отговаря на `restricted`“ и премълчава, че `etcd` няма резервно копие, дава невярна представа колко е защитен. Списъкът от 10.10 не е извинение; той е документът, който позволява на този, който взима решения, да знае какъв риск поема.

**От какво защитава и от какво не.** Прегледът спрямо `restricted` защитава от небрежна конфигурация: контейнер, който стартира като `root`, който може да получи привилегии или който запазва възможности, от които няма нужда. Не защитава от уязвимост в програмата на `revisor`, от изтекъл токен, нито от манипулиран по пътя образ. А списъкът от 10.10 ти казва какво още би трябвало, но не го инсталира: да назовеш липсата не значи да я решиш.

## Какво се прави погрешно

**Повтаряне, докато мине.** Това е цикълът `until kubectl apply …; do sleep 5; done`. Крие причината, понякога оставя полусъстояние и в деня, в който се провали наистина, остава да се върти мълчаливо. Чака се условието, с горна граница.

**Фиксиран `sleep` между платформата и проекта.** Работи на твоята машина и се проваля на по-бавна или по-натоварена. `sleep` мери часовника; `kubectl wait` мери условието.

**Събиране на платформата и проекта в една `kustomization`.** Изглежда по-подредено и разваля реда (10.4.4). Двете половини имат различни условия за излизане и затова са различни команди.

**Прилагане на платформата без `--server-side`.** Големите CRD-та не се побират в анотацията, която пази клиентът (10.4.3). Официалното ръководство на Envoy Gateway вече носи флага.

**Overlay, който копира базата.** Ако копираш файловете на базата в папката на overlay-а, „за да им промениш един ред“, имаш две копия, които ще се разделят. Един overlay сочи (`resources: ../../base`) и кърпи.

**Скрипт, който ползва „активния клъстер“.** Инсталира неща в контекста, който е под ръка, а той може да не е твоят. Очакваният контекст се подава като аргумент и се проверява преди всяка стъпка.

**`|| true`, за да не спре нищо.** Скрипт, който не спира при грешка, не ти казва, че е имало такава. Ако един провал е допустим, обработва се този случай и се казва кой е.

**Да кажеш „без грешки“, без да си го измерил.** Или „без предупреждения“ без случай, който ги произвежда. Твърдение за отсъствие има нужда от положителен контрол.

**Нефиксирани версии.** Адрес, който сочи към „последната версия“, се променя сам. Всички парчета на този урок са с версията в пътя, а образите на `curl` — с отпечатъка им.

**Версиониране на токена.** Той е симулиран, но навикът е онова, което има значение: `.gitignore` и `umask 077`.

**Етикетиране с `enforce: restricted` на пространство на платформата, без да е прегледано.** 10.7.4 го показа: MetalLB и `kube-system` имат Pod-ове, които `restricted` би отхвърлил. Един `dry-run` преди етикета избягва да се счупи мрежата на един клъстер.

**Да вземеш `kind` за истински клъстер.** Това е онова, което 10.10 разгръща в четиринайсет точки, и онова, което най-много струва, когато се забрави.

## Упражнения

Упражнения 1 до 3 се изпълняват в клъстера на урока, вече разгърнат така, както го остави 10.8. Преди всяко от тях `ctx` (10.1.2) трябва да минава. `correr.sh` ги изпълнява по същия начин, а изходът им е в `correr.salida.txt`. **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще се случи. Четвъртото се пише със свои думи.

### Упражнение 1 — Собствен overlay

Напиши overlay, който тръгва от overlay-а на `kind` и променя **само едно нещо**: автоматичното мащабиране да не надхвърля 4 реплики (днес стига до 6). Без да докосваш базата, нито overlay-а на `kind`. Преди да го изпълниш, предскажи: колко реда на сглобения манифест се променят спрямо `overlays/kind`? Как би го проверил **без да прилагаш** нищо и как — с клъстера, но без да го променяш?

### Упражнение 2 — От „лош“ към `restricted`

`fig10_02.deployment-malo.yaml` нарушава нивото `restricted`. Поправи го, докато се приложи в пространството `revisor` **без нито едно предупреждение** и Pod-овете му достигнат `Available`. Преди да започнеш, предскажи: кои са контролите, които му липсват? След като го поправиш, какъв брой предупреждения очакваш? Подсказка: списъкът е в 10.7.1, а положителното доказателство вече го имаш от 10.7.5.

### Упражнение 3 — Спира се контролната равнина

В 10.8.3 спря един работен възел. Сега спри контролния възел (`docker stop curso-k8s-l10-control-plane`) за една минута. Предскажи преди това и го запиши: отговаря ли `kubectl get nodes`? Продължават ли контейнерите на `revisor` да работят в работните възли? (Без API можеш да попиташ самия възел: `docker exec <nodo> crictl ps`.) А входната точка, `http://<dirección>/salud` отвън на клъстера, продължава ли да отговаря? Запиши каквото видиш, дори да не съвпада с решението: резултатът не е винаги един и същ. След това вдигни възела, измери колко време отнема на API-то да се върне и провери, че пазачът на MetalLB отговаря, преди да приложиш каквото и да е. С твоите измервания обясни защо контролната равнина и работните възли се наричат така и какво би казал списъкът от 10.10 за точка 1. **Едно предупреждение:** на твоята машина контролният възел може да смени IP адреса си при рестартиране, ако друг контейнер е заел неговия в Docker мрежата; ако това стане, клъстерът спира да работи и се създава наново. В клъстера на изпълнението на този урок, със собствена мрежа и без други контейнери, не се случи.

### Упражнение 4 — Защити своя списък

Избери **пет** от четиринайсетте точки на 10.10 и, най-много в пет реда на точка: какво прави проектът ти днес, какво би изисквал един истински клъстер и какво би направил ти, в какъв ред. След това ги подреди по „какво ме тревожи първо“ и защити първото място в три изречения: какво се губи, ако се провали, и може ли да се възстанови?

## Решения

### Решение 1

Overlay-ът е `fig10_03.overlay-mio/kustomization.yaml`:

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

Измерено в `correr.salida.txt`:

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

Променя се един-единствен ред. `kubectl kustomize` отпечатва резултата, без да докосва нищо: `maxReplicas: 4` на ред 391 и `minReplicas: 2` непроменено на 399. С клъстера `kubectl diff --server-side` сравнява онова, което би приложил, с онова, което има, и показва точно `-  maxReplicas: 6` и `+  maxReplicas: 4`; `[código de salida: 1]` е този на `kubectl diff`, когато **има** разлики (0, ако няма). И доказателството, че базата не е докосната: `base/escalado.yaml` продължава да има своя единствен ред `maxReplicas`. За да се приложи, би стигнало `kubectl apply --server-side -k fig10_03.overlay-mio`; упражнението не го иска, за да остане клъстерът такъв, какъвто го казват файловете на урока.

### Решение 2

Поправката е `fig10_04.deployment-corregido.yaml`: същият Deployment с `automountServiceAccountToken: false`, `securityContext` на Pod-а (не-`root`, потребител 65532, *seccomp* `RuntimeDefault`) и този на контейнера (без ескалация на привилегиите, файлова система само за четене, без възможности), плюс долна и горна граница на ресурсите.

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

Измерено в `correr.salida.txt`:

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

Броят на предупрежденията е **0**. Тази команда вече приложи Deployment-а (`grep` брои само онова, което `apply` отпечатва), и затова вторият `apply` казва `unchanged`: нямаше какво да се променя. Deployment-ът достига `1/1` и `Available`, така че Pod-овете вече не се отхвърлят. Всеки контрол има своето поле: `allowPrivilegeEscalation: false` и `capabilities.drop: ["ALL"]` в контейнера; `runAsNonRoot: true` (с `runAsUser: 65532`) и `seccompProfile.type: RuntimeDefault` в Pod-а. Останалото —`readOnlyRootFilesystem`, `automountServiceAccountToken: false`, долната и горната граница— не го изисква `restricted`; изисква го курсът.

### Решение 3

Измерено в `correr.salida.txt`:

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

Чети го по ред. **API-то не отговаря**: `kubectl` остава със `connection … was refused` срещу `127.0.0.1` (портът, който `kind` публикува от контролния възел). Без контролната равнина не можеш да видиш, създадеш, промениш или изтриеш нищо. **Контейнерите останаха живи** в двете изпълнения, където беше проверено (5-то подготвително и това на урока): без API, но с достъп до възела, `crictl ps` показва `revisor` и двата контейнера на Envoy да работят, а един `curl` от възела към IP на Pod-а отговаря `{"estado":"vivo","version":"1.6.0"}`. Това казва, че контейнерите не се изключват сами; не казва, че услугата стига до този, който я иска. **Входната точка**, при това изпълнение, отговори на 23-те заявки (`bien=23 mal=0`) през 45-те секунди. И тук има предупреждение, което беше измерено и не беше обяснено: при **три подготвителни изпълнения** на този същия урок (записани в `programas/10-proyecto-final/corridas-preparacion/`: `corrida1.txt`, `corrida4.txt` и `corrida5.txt`), със същото упражнение, входната точка не отговори на нито една от заявките си, докато контролната равнина беше спряна (`bien=0 mal=12`, 12 от 12 неуспешни, в 4 и 5; в 1 `curl` излезе с код 7, отказана връзка, веднага). Общо входната точка отговори в 1 от 4 изпълнения, макар че `ServiceL2Status` (измерено от последните две) казваше, че един работен възел обявява адреса. Причината не беше намерена. Честното е едно изречение: в `kind`, с MetalLB и Envoy Gateway, **не приемай за сигурно**, че входната точка оцелява без контролна равнина, нито обратното: с 4 изпълнения не може да се каже нищо повече от „1 от 4“. Запиши каквото видиш при теб; може да е различно от това на това решение. **API-то се върна** 59 секунди след спирането на контролния възел.

И един втори урок, от последната проверка. Когато контролният възел се върне, `kubectl wait` казва, че трите възела са `Ready`, но това не значи, че всичко останало е готово. При едно подготвително изпълнение финалният `kubectl diff` се провали с `failed calling webhook "ipaddresspoolvalidationwebhook.metallb.io" … connection refused`: пазачът на MetalLB още не отговаряше (10.4.1, отново). Затова скриптът пита пазача с проба на сухо на диапазона —`kubectl apply --dry-run=server -f overlays/kind/metallb-pool.yaml`— и чака с горна граница да отговори. При това изпълнение отговори от първия опит: `ipaddresspool.metallb.io/curso configured (server dry run)`. Двата реда `Warning`, които го придружават, не са за сигурност: казват, че диапазонът е създаден с `--server-side` и няма анотацията `last-applied-configuration`, която ползва `apply` от страна на клиента. Това е разликата от 10.4.2 и тук е безвредна, защото е проба на сухо. След изчакването `kubectl diff --server-side -k overlays/kind` казва `sin diferencias con los archivos`.

Какво казва това за точка 1 от 10.10: контролна равнина само с един възел е единична точка на отказ: без нея не можеш да **променяш** нищо и никой не подменя, нито мащабира; онова, което вече работи, може да продължи да работи (контейнерите го направиха) или да престане да бъде достижимо (входната точка, 3 от 4 пъти), и не беше намерено от какво зависи. И защо се наричат така: контролната равнина **решава** (какво трябва да съществува и къде); работните възли **изпълняват**.

### Решение 4

Един възможен отговор, за списъка от пет: „**(2) `etcd` без резервно копие**: днес няма копие; един истински клъстер планира `etcdctl snapshot save` и *възстановява наистина* в тестов клъстер от време на време, и го правя първо, защото е единственото, което не мога да възстановя с `kubectl apply`. **(8) Том на диска на един възел**: днес отчетът живее във възела; в истински — репликирано съхранение и копия, със същото изпитание на възстановяването. **(3) Нешифровани тайни**: днес са в base64 вътре в `etcd`; бих настроил шифроване в покой и, за тайни, които не бива да живеят в клъстера, външно хранилище. **(4) HTTP на порт 80**: бих прекратил TLS в Gateway и бих сменил токена, който е пътувал в чист текст. **(1) Контролна равнина с един възел**: три контролни възела или управлявана равнина.“ Редът на тревога: първо онова, което не се възстановява (2 и 8), след това онова, което се излага (3 и 4), накрая достъпността (1). Защита на първото място: „Ако `etcd` без резервно копие се провали, губя състоянието на клъстера; проектът се възстановява с две команди и едно изчакване (изпитах го два пъти), но онова, което клъстерът знаеше за себе си, не. А резервно копие, което никога не е било възстановявано, не е отговор: е хипотеза.“

## Изтриване на клъстера

Когато свършиш, изтрий клъстера на урока и онова, което си оставил на машината си. Не оставяй нищо живо:

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

(Редовете в скоби ги пише скриптът, който мери изтриването. `grep -c` отпечатва `0` и излиза с код 1, защото не е намерил нито един клъстер с това име: това е отговорът, който търсиш.) `case` пропуска само път, който започва с `/tmp/curso-k8s-l10.` и има нещо след това, точната форма на онзи, който създаде в 10.1.2. Ако `L10_TMP` е празна или има друга стойност, не изтрива нищо и ти казва защо. Ако си направил Упражнение 3 във втори терминал, затвори го. А ако си ползвал собствена Docker мрежа (изпълнението на този урок го направи; ти, с мрежата `kind`, не), изтрий я **след** клъстера и само ако си я създал ти: `docker network rm <nombre>`.

Това беше последният клъстер на курса. Тези от предишните уроци вече си ги изтрил, по един на урок, и с това завършва методът: да създадеш, да ползваш, да изтриеш и да можеш да създадеш отново.

## Как разбирам, че съм успял

- [ ] Отваряш `kustomization.yaml` и казваш какво е база, какво е overlay, какво сглобява и как да го провериш с `kubectl kustomize`, без да прилагаш нищо.
- [ ] От празен клъстер разгръщаш проекта с платформата, изчакване по условие и проекта и обясняваш защо е този редът.
- [ ] Четеш `no matches for kind … ensure CRDs are installed first` и съобщението за прекалено голямо CRD без `--server-side` и казваш какво ги причинява.
- [ ] Изпълняваш `programas/10-proyecto-final/probar-levantar.sh` и сравняваш изхода му с `programas/10-proyecto-final/correr.salida.txt` в онова, което не се променя между изпълненията: платформата, приложена със `serverside-applied`; петте изчаквания с `condition met` или `successfully rolled out`; проектът с обектите си и без нито един ред `Warning`; Gateway-ът `Programmed`; `{"estado":"vivo","version":"1.6.0"}` отвън, в двата кръга; и че клъстерът вече не съществува накрая. IP адресите, наставките на имената, възрастите и секундите се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] Знаеш защо `kubectl label --dry-run=server … enforce=restricted` върху `revisor` (който вече го има) отговаря `not labeled`, без да провери нито един Pod, и проверяваш съществуващите Pod-ове, като искаш друга политика (`enforce-version=v1.36`), с контрола на пространството `psa-control`, който назовава Pod-а, който нарушава, а не този, който отговаря.
- [ ] Спираш един работен възел, измерваш прозореца, в който заявките се провалят, и обясняваш защо трае колкото трае и какво го скъсява.
- [ ] Променяш списъка от услуги и виждаш нов `ConfigMap` и нов ReplicaSet без да изграждаш образа наново.
- [ ] `intruso` не стига до `revisor`, а `depurar` стига; акаунтът `revisor` не може дори да чете Pod-ове.
- [ ] `kubectl get hpa` показва процент, не `<unknown>`.
- [ ] Описваш със свои думи пет причини, поради които онова, което си изградил, не е истински клъстер, какво би направил за всяка и с коя би започнал.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l10`.

## Обобщение

Отговори, без да гледаш урока:

1. Какво е база и какво е overlay? Знае ли една база за своите overlay-и?
2. Каква е разликата между парче от платформата и парче от проекта и кои три неща носи една платформа?
3. Какво условие чака `kubectl wait` при едно CRD и какво при един Deployment?
4. Какво променя `--server-side` и коя грешка избягва в платформата?
5. Какво става, ако съединиш платформата и проекта в една команда, и защо повторението „да видим дали ще мине“ не е метод?
6. Защо един скрипт за разгръщане получава контекста като аргумент и го проверява преди всяка стъпка?
7. Какво изисква нивото `restricted` и какво прави проектът освен това?
8. Защо част от платформата (MetalLB, `kube-system`) не отговаря на `restricted` и какво условие поставяш, за да е това приемливо?
9. При спрян работен възел защо заявките се провалят в продължение на десетки секунди и какво не скъсява този прозорец?
10. Кога би ползвал Helm вместо Kustomize?
11. Назови пет причини, поради които клъстерът на курса не е истински клъстер, и какво би направил за всяка.

## Източници

Всички консултирани на 21 октомври 2026 г.

- [Kubernetes, «Declarative Management of Kubernetes Objects Using Kustomize»](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): бази и overlays, генератори с *hash*, `patches`, `images` и `kubectl kustomize` / `apply -k`.
- [Kubernetes, «Server-Side Apply»](https://kubernetes.io/docs/reference/using-api/server-side-apply/): мениджъри на полета, конфликти и сравнението с `apply` от страна на клиента.
- [Kubernetes, «Custom Resources»: CustomResourceDefinition](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/): условието `Established` на едно CRD.
- [Kubernetes, «Dynamic Admission Control»](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/): admission *webhooks* и `failurePolicy` (по подразбиране `Fail`).
- [Kubernetes, «kubectl wait»](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/): чакане на условие върху един или няколко ресурса.
- [Kubernetes, «Virtual IPs and Service Proxies»](https://kubernetes.io/docs/reference/networking/virtual-ips/): че `kube-proxy` избира на случаен принцип целевия Pod на един Service в режимите `iptables` и `nftables`.
- [Kubernetes, «Pod Security Standards»](https://kubernetes.io/docs/concepts/security/pod-security-standards/): контролите на `baseline` и `restricted`, поле по поле.
- [Kubernetes, «Pod Security Admission»](https://kubernetes.io/docs/concepts/security/pod-security-admission/) и [«Enforce Pod Security Standards with Namespace Labels»](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): режимите `enforce`, `audit` и `warn`, фиксираните версии и изпитването с `--dry-run=server`.
- [Kubernetes, «Node Status»](https://kubernetes.io/docs/reference/node/node-status/), [«kube-controller-manager»](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) и [«Taints and Tolerations»](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/): 50-те секунди на `node-monitor-grace-period` и толерансът от 300 секунди.
- [Kubernetes, «Production environment»](https://kubernetes.io/docs/setup/production-environment/), [«Security checklist»](https://kubernetes.io/docs/concepts/security/security-checklist/), [«Encrypting Confidential Data at Rest»](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/), [«Operating etcd clusters»](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/), [«Logging Architecture»](https://kubernetes.io/docs/concepts/cluster-administration/logging/), [«Resource Quotas»](https://kubernetes.io/docs/concepts/policy/resource-quotas/) и [«Version Skew Policy»](https://kubernetes.io/releases/version-skew-policy/): какво изисква един истински клъстер и политиката за версиите.
- [kind, *issues* #4066](https://github.com/kubernetes-sigs/kind/issues/4066), [#3795](https://github.com/kubernetes-sigs/kind/issues/3795) и [#4224](https://github.com/kubernetes-sigs/kind/issues/4224): неизправности на `kind load` с Docker 29 и хранилището на `containerd` (предупреждението от 10.1.2).
- [kind](https://kind.sigs.k8s.io/): за какво е проектиран `kind`. И [`provider.go` на kind v0.33.0](https://github.com/kubernetes-sigs/kind/blob/v0.33.0/pkg/cluster/internal/providers/docker/provider.go): променливата `KIND_EXPERIMENTAL_DOCKER_NETWORK`, която изпълнението на този урок използва.
- [Envoy Gateway, «Install with Kubernetes YAML»](https://gateway.envoyproxy.io/docs/install/install-yaml/) и [«Install with Helm»](https://gateway.envoyproxy.io/docs/install/install-helm/): инсталирането с `--server-side`, инсталирането с Helm и редът на обновяване на CRD-тата.
- [MetalLB, «Layer 2 mode»](https://metallb.io/concepts/layer2/): как работи и двете му ограничения.
- [metrics-server v0.9.0, README](https://github.com/kubernetes-sigs/metrics-server/blob/v0.9.0/README.md): `--kubelet-insecure-tls` „само за тестове“ и че е само за автоматичното мащабиране.
- [Gateway API, «TLS»](https://gateway-api.sigs.k8s.io/guides/tls/): прекратяване на TLS в един *listener*.
- [Helm, «Using Helm»](https://helm.sh/docs/intro/using_helm/) и [«Custom Resource Definitions»](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/): какво е chart и как третира CRD-тата.
- [RFC 6902, «JavaScript Object Notation (JSON) Patch»](https://www.rfc-editor.org/rfc/rfc6902.html): операциите `op: replace` на кръпките от 10.3.3.
- [RFC 2606, «Reserved Top Level DNS Names»](https://www.rfc-editor.org/rfc/rfc2606.html): `example.com`, резервиран за примери.
- [GitLab, «Postmortem of database outage of January 31»](https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/): публичният доклад за случая от началото.

---

**Край на курса.** Върни се към [съдържанието](README.md) или отвори [дневника](bitacora.md) и запиши какво искаш да изградиш след това.
