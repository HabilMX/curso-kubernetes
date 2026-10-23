# Урок 7 — Изолиране: пространства, права и мрежа

Петък, 5:50 следобед. Екипът по данни от две седмици иска място, където да изпробва услугата си, а твоят клъстер на kind има предостатъчно място. Казал си им да. В 5:58 някой от екипа по сигурност, който преглежда всичко, което се публикува преди почивните дни, ти пише три въпроса подред. Първи: „може ли Pod на тях да прочете токена на `revisor`?“. Втори: „може ли да говори с `revisor`, без да минава през входната точка, която ти си публикувал?“. Трети: „може ли да поиска от API-то на клъстера списъка със Secret-ите?“. Ти знаеш, че `revisor` работи без да е `root`, с *probes*, с ограничения и зад входна точка с име. Но тези три въпроса не са за `revisor`. Те са за **всичко, което го заобикаля**, а ти нямаш нито един измерен отговор. Часът е 6:00. Екипът по данни вече е закачил първия си Pod в пространството `default`, където живее всичко твое.

Историята на сигурността в облака има много варианти на този следобед. На 20 февруари 2018 г. фирмата за сигурност RedLock разказа, че е открила Tesla с отворена и незащитена административна конзола на Kubernetes. Според самата RedLock, който е влязъл оттам, е намерил данни за достъп до хранилище за данни на Amazon Web Services и е накарал клъстера да копае криптовалути. Tesla отговори, че въздействието изглежда е било ограничено до тестови инженерни превозни средства и че го е поправила за броени часове. Журналистическата статия, която го разказва, е в източниците на този урок. Тази отворена врата не е онова, което изучава този урок. Той учи на въпроса, който идва **след** всяка отворена врата, от немарливост или от грешка на друг екип: щом веднъж са вътре, докъде стига онова, което е влязло?

Към днешна дата, във твоя клъстер, отговорът е „докъдето стигне“. Този урок му слага стени, на четири слоя, и те учи да **измерваш** всеки от тях с най-скромния нападател, който съществува: Pod с `curl`, който не би трябвало да може нищо. Първият решава **къде живее всяко нещо** (пространството от имена). Вторият решава **какво е позволено да се създава** (Pod Security Admission). Третият решава **кой какво може да прави с API-то** (сервизни акаунти и RBAC), а четвъртият — **кой с кого може да говори** (мрежовите политики). Когато приключиш, трите въпроса от 5:58 ще имат отговор с команда до него.

**Време:** 2 × 45 мин

**Какво изграждаш:** собствено пространство от имена, `revisor`, с правила: целият проект живее там, клъстерът отхвърля всеки Pod, който не отговаря на нивото `restricted`, всяка програма има свой сервизен акаунт без права и без монтирани удостоверения (освен един акаунт само за четене, за наблюдение), а мрежата е затворена по подразбиране с шест политики, които отварят само необходимото

**Какво научаваш:** какво е пространство от имена и какво **не** изолира; Pod Security Admission с трите си режима и трите си нива и как се четат отказите му; `ServiceAccount`, `Role` и `RoleBinding` с минимални права и как се проверяват с `kubectl auth can-i`, с подправена заявка и отвътре на Pod; `NetworkPolicy`: моделът (отворено, докато политика не избере Pod-а, и правилата се сумират), кой ги прилага в kind (измерва се), какво се чупи при „всичко затворено“ и за какво служи всяко от шестте отваряния, като ги махаш едно по едно; и как маршрут от друго пространство се закача за входната точка (`allowedRoutes` и `ReferenceGrant`)

**Откъде идваш.** От [Урок 6](06-entrar-al-cluster.md): `revisor` работи с три реплики, а тестовата услуга — с една, с *probes*, `requests` и `limits`; MetalLB и Envoy Gateway са инсталирани вътре в клъстера; входната точка е `Gateway` на име `revisor` с неговия `HTTPRoute`; и има директен Service `LoadBalancer`, `revisor-publico`, който този урок премахва. Всичко живее в пространството `default`. От [Урок 5](05-salud-recursos-apagado.md) носиш, че *probes* ги изпълнява `kubelet` на възела, стойност, която днес решава дали затворената мрежа ще събори, или няма да събори Pod-овете. От [Урок 3](03-services-dns.md) — Pod-а `depurar`, DNS на клъстера и че заявката за име е мрежов трафик като всеки друг. И от [Урок 2](02-pods-deployments.md) — `securityContext`, който от първия манифест отговаря, без да го знаеш, на нивото `restricted`: днес клъстерът започва да го изисква.

**Какво не прави този урок.** Не криптира трафика: входната точка продължава да говори чист HTTP, а вътре в клъстера Pod-овете също не криптират онова, което си казват. Не инсталира друг мрежов компонент: курсът планираше да инсталира Calico, ако мрежата на kind не прилагаше политиките, а раздел 7.5 измерва, че ги прилага, така че не е нужно. Не ограничава колко ресурси може да създаде едно пространство от имена (`ResourceQuota` и `LimitRange`, които [Урок 5](05-salud-recursos-apagado.md) спомена) и не инсталира собствени политики за допускане. Не съхранява данни и не планира задачи: това е [Урок 8](08-datos-y-tareas.md), който ще има нужда от този урок за две неща — сервизен акаунт без удостоверения за задачата и етикета `acceso-revisor: permitido`, за да може задачата да говори с `revisor`. И също не е одит на сигурността на истински клъстер: разделът за навика за сигурност казва, с измервания, от какво предпазва това и от какво не.

**За изпълненията.** Всички изходи от този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1, образа на възела `kindest/node:v1.37.0`, фиксиран чрез отпечатъка му, **MetalLB v0.16.1** и **Envoy Gateway v1.9.2**, в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l7`. Машината беше Mac с процесор ARM (`arm64`) и Docker Engine 29.2.1 във виртуална машина с Ubuntu 24.04.4 (Colima). Първият ред на `correr.salida.txt` записва онова, което скриптът може да измери: `Docker 29.2.1 en Ubuntu 24.04.4 LTS (arm64)`; че домакинската машина е Mac с Colima, скриптът не го вижда. **Не** беше Linux Mint, който е референтната система на курса. **Това изпълнение използва собствена мрежа на Docker**, `curso-k8s-red-l7`, с подмрежата `172.27.0.0/16`, защото на същата машина едновременно работеха други уроци със свой MetalLB, а два MetalLB със същия диапазон в една мрежа си пречат (видя го в Урок 6). Затова адресите на възлите и на входната точка тук излизат като `172.27.…`. В твоя Mint, с обикновената мрежа `kind`, входната точка получава `172.18.255.200`, а възлите висят от `172.18.0.0/16`; останалите изходи не се променят. `correr.sh` прави и двете неща: с мрежата `kind` по подразбиране и със собствена мрежа, ако му кажеш коя с `CURSO_RED` и `CURSO_SUBRED`; и в двата случая проверява, че подмрежата е точно очакваната, и спира, ако не е (със собствена мрежа — преди да създаде клъстера, с мрежата `kind` — веднага след като го създаде). Останалото, което се променя на твоята машина: архитектурата, наставките на имената, възрастите, възелът на всеки Pod, името на Secret-а (токенът е нов във всяко изпълнение) и милисекундите. Пълната обиколка е в [`programas/07-aislar-permisos-red/`](../programas/07-aislar-permisos-red): `correr.sh` създава клъстера, зарежда в него двата образа, инсталира платформата от Урок 6, оставя всичко така, както го е оставил онзи урок, минава през този по ред, изпълнява Упражнения 1 до 3 и изтрива клъстера. Пълното изпълнение отне 26 минути и 9 секунди, дълго, защото машината беше натоварена с други клъстери и защото урокът изчаква мрежата; създаването на клъстера и изчакването да е готов бяха 39 секунди, инсталирането на платформата — 411, а изтриването му — 1, а дискът на Docker беше на 79 % в началото и на 77 % в края. Изчакванията при инсталацията и при входната точка (`speaker`, `Programmed`, Pod-ът `viejo`) имат щедри срокове (480, 360 и 300 секунди), защото на натоварена машина образите се теглят бавно; ако при теб някое изчакване изтече, не продължавай на сляпо: повтори го и виж с `kubectl get pods -A` какво липсва. Изходът му е `correr.salida.txt`; изисква интернет (манифестите на MetalLB и на Envoy Gateway се изтеглят от изданията им, фиксирани към версията им). Изчакванията се виждат: където скриптът чака, изходът го казва с `kubectl wait`, `rollout status` или `sleep`. Използва порт 18087 на твоята машина за `port-forward` и спира, преди да започне, ако този порт вече е зает.

## След урока ще можеш да

- Обясняваш какво изолира едно пространство от имена (имената и обхвата на правата) и какво не (мрежата) и го доказваш с Pod от едно пространство, който говори със Service от друго.
- Преместваш проекта от `default` в собствено пространство с `kubectl apply -k` и различаваш онова, което живее вътре в пространството, от онова, което важи за целия клъстер.
- Поставяш пространство от имена на ниво `restricted` с неговите етикети, фиксираш версията на политиката и четеш ред по ред отказа на Pod, който не я изпълнява.
- Предизвикваш Deployment, който се създава, но остава без Pod-ове заради Pod Security Admission, и намираш причината в събитията на ReplicaSet.
- Пишеш `Role` и `RoleBinding` само за четене, проверяваш какво позволяват и какво отказват с `kubectl auth can-i` и с истинска заявка от Pod и обясняваш защо `revisor` не носи монтирани удостоверения.
- Затваряш мрежата на пространство с една политика, измерваш какво се чупи (включително DNS и входната точка), отваряш само необходимото и казваш, за всяка от шест политики, какво би спряло да работи, ако липсва.
- Обясняваш при какво условие една `NetworkPolicy`, „затворена по подразбиране“, защитава нещо, и го проверяваш в твоя клъстер.
- Закачаш маршрут от друго пространство за входната точка и различаваш `allowedRoutes` (кой може да се закачи за Gateway-а) от `ReferenceGrant` (кой може да бъде цел на един маршрут).

## Защо, преди как

Представи си офис сграда с един дълъг коридор и всички врати без ключ. Някой е сложил табелки на вратите (`datos`, `finanzas`, `revisor`) и изглежда подредено. Но табелката не заключва нищо: който влезе в сградата, може да отвори всяка врата. Това е твоят клъстер днес. Пространствата от имена, които вече познаваш, са табелките. Този урок му слага ключове, правилник и врати с брава и го прави на слоеве, защото всеки слой отговаря на различен въпрос и се проваля по различен начин:

1. **Къде живее всяко нещо?** **Пространството от имена** (*namespace*). Групира обекти, позволява на два екипа да ползват едно и също име, без да се сблъскат, и е единицата, към която се лепят права и правила. Не е мрежова стена: това се измерва в 7.5.
2. **Какво е позволено да се създава?** **Pod Security Admission**. Той е пазач на вратата на `kube-apiserver`, който проверява всеки Pod, който иска да се роди в едно пространство, и го отхвърля, ако не отговаря на нивото, което пространството изисква. Предпазва от зле написания Pod, не от Pod, който вече работи.
3. **Кой какво може да прави с API-то?** **Сервизни акаунти и RBAC**. Всяка програма, която работи в клъстера, има идентичност, а всяка идентичност има списък (по подразбиране празен) от глаголи, които може да прилага към определени обекти.
4. **Кой с кого може да говори?** **Мрежови политики**. Днес всеки Pod може да говори с всеки Pod. Една политика променя това Pod по Pod и работи само ако мрежата на клъстера я прилага.

Слоевете се допълват, защото предпазват от различни неща. PSA пречи някой (или недоглеждане от твоя страна) да създаде контейнер с повече привилегии от нужното. RBAC ограничава какво прави една програма **с API-то**. Мрежата ограничава какво прави **с останалите Pod-ове**. А пространството от имена е мястото, където се прилагат и трите. Ако липсва един, останалите не го покриват: Pod от ниво `restricted` без мрежова политика все така може да говори с всички, а затворена мрежа със щедър сервизен акаунт позволява на компрометиран Pod да поиска от API-то всичко, до което стига това право.

Урокът има пет части с понятия и после обичайните раздели:

1. **Клъстерът на урока** (7.1), с платформата от Урок 6 и изходната точка.
2. **Собствено пространство от имена** (7.2): какво е, какво съдържа и преместването.
3. **Pod Security Admission** (7.3): режими, нива, етикети и отказът, който се учиш да четеш.
4. **Сервизни акаунти и минимални права** (7.4): `ServiceAccount`, `Role`, `RoleBinding`, `auth can-i` и истинска заявка отвътре на един Pod.
5. **Мрежата** (7.5): моделът, кой я прилага, без правила, всичко затворено, отварянията и за какво служи всяко.

Това е целта. В края на 7.5 един Pod с правилния етикет може да говори с `revisor`, един Pod без него — не, и двата отговора идват от команди, които можеш да повториш:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]
```

## Ако нямаш образите от курса по Docker

Този урок използва същите два образа като Уроци 3 до 6: `curso-docker-revisor:1.6.0` и `curso-docker-prueba:1.0.0`. Провери, че ги имаш:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

За другия — същата команда с `curso-docker-prueba:1.0.0`. Ако ти липсва някой, [Урок 3](03-services-dns.md) казва как да изградиш двата от хранилището на курса по Docker. Този урок не иска нищо ново от нито един от двата образа. Помощните Pod-ове (`depurar`, `intruso` и `lector`) използват образа на `curl`, фиксиран чрез отпечатъка му, както в предишните уроци; всеки възел го изтегля от интернет първия път.

## Понятията

### 7.1 Клъстерът на урока

#### 7.1.1 Създаване, със защитата на контекста

Този урок създава собствен клъстер, `curso-k8s-l7`, с конфигурацията от три възела от Урок 1. Досега, в предишните уроци, проверката на контекста беше ред, който копираше пред всяка команда. Днес тя става функция, за да е къса и да не я забравяш. Създай го така, от корена на хранилището на курса:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
L7_TMP="$(mktemp -d /tmp/curso-k8s-l7.XXXX)"
export KUBECONFIG="$L7_TMP/kubeconfig"
echo "$KUBECONFIG"     # anota esta ruta: si abres otra terminal, la necesitas

# La guarda: se escribe una vez y va delante de cada comando que cambia algo.
ctx() { [ "$(kubectl config current-context)" = kind-curso-k8s-l7 ] || { echo "contexto equivocado: no sigo"; return 1; }; }

# curso-k8s-l7 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l7 --config programas/07-aislar-permisos-red/kind-curso.yaml
ctx && kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l7

# Desde aquí, todo se ejecuta dentro de la carpeta de la lección:
cd programas/07-aislar-permisos-red
```

Функцията `ctx` върши едно-единствено нещо: сравнява активния контекст на `kubectl` с `kind-curso-k8s-l7`. Ако съвпада, не отпечатва нищо и завършва успешно, а `&&` пропуска към следващата команда. Ако не съвпада, отпечатва „contexto equivocado: no sigo“ и завършва с грешка, а `&&` **прекъсва веригата**: командата, която променя нещо, не се изпълнява. Отсега нататък **всяка команда от този урок, която променя нещо** (`apply`, `delete`, `patch`, `label`, `run`, `exec`, който трие…), се пише така: `ctx && kubectl apply -k .`. В изходите, които следват, редът, който започва с `$`, показва само командата на `kubectl`, без `ctx &&`, за да се побере; скриптът `correr.sh` прави същата проверка преди **всеки** `kubectl`, включително четенията, и спира, ако контекстът не е този на урока. Причината за толкова грижа я знаеш от Урок 1: един `delete -k` в погрешния контекст би изтрил обекти от друг клъстер, а този урок трие и пресъздава доста.

Две проверки за съжителство, същите като в Урок 6 (със собствена мрежа се правят, преди да създадеш клъстера; с мрежата `kind` по подразбиране, която се ражда с първия клъстер, — веднага след като го създадеш): мрежата `kind` трябва да е `172.18.0.0/16` (оттам идва диапазонът на MetalLB) и никой не бива вече да отговаря на `172.18.255.200`. Ако друг твой клъстер с MetalLB е жив, изчакай да приключи. `correr.sh` ги прави и спира, ако се провалят; в това изпълнение ги направи спрямо собствената мрежа, `curso-k8s-red-l7`, която разделът „За изпълненията“ обяснява.

```text
$ kubectl config current-context
kind-curso-k8s-l7

$ kubectl get nodes -o wide | awk '{print $1, $2, $3, $6}' | column -t
NAME                        STATUS  ROLES          INTERNAL-IP
curso-k8s-l7-control-plane  Ready   control-plane  172.27.0.4
curso-k8s-l7-worker         Ready   <none>         172.27.0.2
curso-k8s-l7-worker2        Ready   <none>         172.27.0.3
```

Трите възела живеят в мрежата на Docker от изпълнението (`172.27.0.x`; в твоя Mint — `172.18.0.x`). `kubectl wait` и `kubectl get` не променят нищо, така че не се нуждаят от защитата; всичко останало се нуждае.

#### 7.1.2 Платформата от Урок 6, в три стъпки

Урок 6 остави две инсталации, които не са на `revisor`, а на клъстера: MetalLB и Envoy Gateway. Този урок се нуждае от тях, защото проектът включва `Gateway`. Инсталират се както там, в реда, който научи: платформа, изчакване, проект. Командите са същите като в раздел 6.9, а изходът показва всяко изчакване:

```text
$ kubectl apply -k infra/metallb | tail -2
daemonset.apps/speaker created
validatingwebhookconfiguration.admissionregistration.k8s.io/metallb-webhook-configuration created

$ kubectl apply --server-side -k infra/envoy-gateway | tail -1
mutatingwebhookconfiguration.admissionregistration.k8s.io/envoy-gateway-topology-injector.envoy-gateway-system serverside-applied

$ kubectl wait --for=condition=Available deployment/controller -n metallb-system --timeout=240s
deployment.apps/controller condition met

$ kubectl rollout status daemonset/speaker -n metallb-system --timeout=480s | tail -1
daemon set "speaker" successfully rolled out

$ kubectl wait --for=condition=Established crd/gatewayclasses.gateway.networking.k8s.io crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io crd/referencegrants.gateway.networking.k8s.io --timeout=120s
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io condition met
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io condition met

$ kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=300s
deployment.apps/envoy-gateway condition met

$ kubectl apply -f infra/metallb-pool.yaml -f infra/gatewayclass.yaml
(en esta corrida el rango del archivo se cambió a 172.27.255.200-172.27.255.250, dentro de la red curso-k8s-red-l7)
ipaddresspool.metallb.io/curso created
l2advertisement.metallb.io/curso created
gatewayclass.gateway.networking.k8s.io/eg created

$ kubectl wait --for=condition=Accepted gatewayclass/eg --timeout=120s
gatewayclass.gateway.networking.k8s.io/eg condition met
```

Две неща, които вече знаеш, и едно, което се промени. Вече знаеш, че трябва да изчакаш `controller` на MetalLB, преди да му дадеш диапазона (*webhook*-ът трябва да слуша), и че диапазонът и класът `eg` се прилагат накрая. Променило се е изчакването на CRD: този път включва `referencegrants.gateway.networking.k8s.io`, тип на Gateway API, който Упражнение 3 използва и който идва в същия пакет, инсталиран от Envoy Gateway.

За реда в скоби на `kubectl apply -f infra/metallb-pool.yaml`: файлът на курса носи диапазона `172.18.255.200-172.18.255.220`, този на твоя Mint. В това изпълнение `correr.sh` смени този диапазон, **със `sed` в движение**, на `172.27.255.200-172.27.255.250`, който попада в собствената мрежа. Това е единствената промяна: файлът в хранилището не е пипан. На твоята машина се прилага какъвто е.

#### 7.1.3 Изходната точка: Урок 6, в `default`

Папката `punto-de-partida/` носи, без да е променена и запетая, манифестите, с които приключи Урок 6. Вече си в папката на урока. Токенът е симулиран и не се версионира; генерира се при всяко изпълнение с `umask`, който вече познаваш, за да се роди с права `0600`, и се копира в папката на урока, защото `kustomization.yaml` и на двата го изисква:

```bash
(umask 077; openssl rand -hex 16 > punto-de-partida/token.txt)
cp punto-de-partida/token.txt token.txt     # hereda el 0600 del original
TOKEN="$(cat token.txt)"
ctx && kubectl apply -k punto-de-partida
```

Скобите и `umask 077` са навикът от Урок 4: файлът се създава затворен от първия байт, не се създава отворен и после да се затваря. Сега, с `revisor`, `prueba`, публичния `Service` и входната точка в `default`, ето какво знае клъстерът за състоянието „преди“:

```text
$ /bin/ls -l token.txt punto-de-partida/token.txt | awk '{print $1, $NF}'
-rw------- punto-de-partida/token.txt
-rw------- token.txt

$ kubectl apply -k punto-de-partida
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
service/prueba created
service/revisor created
service/revisor-publico created
deployment.apps/prueba created
deployment.apps/revisor created
gateway.gateway.networking.k8s.io/revisor created
httproute.gateway.networking.k8s.io/revisor created

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor --timeout=360s
gateway.gateway.networking.k8s.io/revisor condition met
```

Девет създадени обекта и входна точка в състояние `Programmed` — състоянието е това от Урок 6. Остават четири четения на „преди“, онези, които ще се променят в края на урока:

```text
$ kubectl get namespaces
NAME                   STATUS   AGE
default                Active   11m
envoy-gateway-system   Active   11m
kube-node-lease        Active   11m
kube-public            Active   11m
kube-system            Active   11m
local-path-storage     Active   11m
metallb-system         Active   11m

$ kubectl get namespace default --show-labels
NAME      STATUS   AGE   LABELS
default   Active   11m   kubernetes.io/metadata.name=default

$ kubectl get pod -l app=revisor -o jsonpath='{.items[0].spec.serviceAccountName} | {.items[0].spec.automountServiceAccountToken} | {.items[0].spec.volumes[*].name}{"\n"}'
default |  | datos token kube-api-access-5q29h

$ kubectl auth can-i --list --as=system:serviceaccount:default:default | head -4
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
```

Четат се така. Пространствата от имена са обичайните плюс двете на платформата (`envoy-gateway-system` и `metallb-system`); `default` няма друг етикет освен този, който му слага системата, `kubernetes.io/metadata.name`: никакво правило. Третата команда пита първата реплика на `revisor` (`.items[0]`; трите са еднакви, защото излизат от един и същ шаблон) за три неща: с кой акаунт работи (`default`), дали е поискала да не ѝ монтират удостоверения (полето `automountServiceAccountToken` излиза **празно**, тоест не е казала нищо) и какви томове има: `datos`, `token` (Secret-ът от Урок 4) и трети със случайно име, `kube-api-access-…`. Този трети е онзи, който никой не е поискал: **клъстерът е монтирал на `revisor` удостоверение за разговор с API-то**, а `revisor` не говори с API-то. Това е първото нещо, което този урок премахва. А последната команда изброява какво може да прави акаунтът `default`: почти нищо (да създава проверки върху себе си, които са въпроси от рода „какво мога аз?“), но „почти нищо“ не е същото като „нищо“, и 7.4 измерва разликата.


### 7.2 Собствено пространство от имена

#### 7.2.1 Какво е и какво не е

**Пространството от имена** (*namespace*) е група с име вътре в клъстера. [Документацията за пространствата от имена](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) го казва с едно изречение: пространствата от имена „осигуряват механизъм за изолиране на групи ресурси в рамките на един клъстер“, а имената на ресурсите трябва да са уникални **в рамките на** едно пространство, не между пространствата. Това води до три практически последствия, които са важните днес:

- **Имената не се сблъскват.** Екипът по данни може да има свой Service на име `revisor` в своето пространство, без да нарушава твоя. И DNS го отразява: онова, което Урок 3 наричаше просто `revisor`, всъщност е `revisor.<пространство>.svc.cluster.local`, а от друго пространство трябва да се пише цялото.
- **Правата имат обхват.** Една `Role` (7.4) важи в рамките на едно пространство. Право върху Pod-овете на `revisor` не дава право върху тези на `default`.
- **Правилата се лепят към пространство.** Етикетите на Pod Security Admission (7.3) и мрежовите политики (7.5) се прилагат към пространството, където живеят.

Онова, което **не** прави, макар името и урочните материали да го внушават: не затваря мрежата. Същата страница не споменава мрежова изолация, защото я няма: Pod от едно пространство може да говори със Service от друго, като просто напише пълното му име. 7.5.3 го измерва и затова четвъртият слой съществува.

Не всичко живее в пространство. Можеш да попиташ клъстера, който знае кои типове принадлежат на пространство и кои важат за всичко:

```text
$ kubectl api-resources --namespaced=false -o name | grep -E '^(nodes|namespaces|persistentvolumes|storageclasses|clusterroles|clusterrolebindings|gatewayclasses\.)'
namespaces
nodes
persistentvolumes
gatewayclasses.gateway.networking.k8s.io
clusterrolebindings.rbac.authorization.k8s.io
clusterroles.rbac.authorization.k8s.io
storageclasses.storage.k8s.io

$ kubectl api-resources --namespaced=true -o name | grep -E '^(pods|services|secrets|serviceaccounts|roles|rolebindings|networkpolicies)(\.|$)'
pods
secrets
serviceaccounts
services
networkpolicies.networking.k8s.io
rolebindings.rbac.authorization.k8s.io
roles.rbac.authorization.k8s.io
```

Първият списък — типове **без** пространство: самите пространства от имена, възлите, постоянните томове, класовете за съхранение, ролите с обхват на клъстера (`clusterroles`) и техните връзки, и `GatewayClass`, която създаде в Урок 6. Вторият — типове **с** пространство: Pod-овете, Service-ите, Secret-ите, сервизните акаунти и, в групата на RBAC и на мрежата, `roles`, `rolebindings` и `networkpolicies` от този урок. Правилото за запомняне: онова, което описва **едно натоварване**, живее в пространство; онова, което описва **инфраструктурата, която всички споделят**, не. Затова `GatewayClass` `eg` днес не се мести, и затова MetalLB и Envoy Gateway, които са платформа, остават в `metallb-system` и `envoy-gateway-system`. Мести се само проектът.

#### 7.2.2 Какво се променя в манифестите

Преместването се свежда до малко промени, почти всички в `kustomization.yaml`. Прочети го цялото, с коментара му:

```yaml
# kustomization.yaml — Lección 7. Se aplica con: kubectl apply -k .
# Todo va al espacio de nombres «revisor» (namespace: revisor, abajo), que nace
# aquí mismo (namespace.yaml) en el nivel «restricted» de Pod Security.
# El token NO se versiona: token.txt lo genera correr.sh (openssl rand -hex 16)
# y está en .gitignore. Los generadores agregan un hash al nombre: si cambia el
# contenido, cambia el nombre, y eso dispara el rollout del Deployment.
# Requiere la infraestructura de la Lección 6 (MetalLB y Envoy Gateway) ya
# instalada: sin sus CRD, Gateway y HTTPRoute no existen.
# revisor-publico.yaml (el LoadBalancer directo de la 6) ya no está: desde la
# Lección 7 la única puerta es el Gateway. El estado de la Lección 6 vive en
# punto-de-partida/, y se retira con: kubectl delete -k punto-de-partida
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

Най-активният нов ред е `namespace: revisor`. Kustomize го прилага като трансформация: на **всеки** обект с пространство, който се появява в `resources`, записва `metadata.namespace: revisor`, без ти да го повтаряш във всеки файл. Затова Deployment-ите, Service-ите и `Gateway` не са променили буква от своя `metadata`. Другите промени са три нови файла в списъка: `namespace.yaml` (самото пространство, с етикетите му, 7.3), `cuentas.yaml` (акаунтите и правата, 7.4) и `red.yaml` (шестте политики, 7.5). А двата Deployment-а вече декларират своя сервизен акаунт и искат от клъстера да не им монтира удостоверения:

```yaml
    spec:
      serviceAccountName: revisor
      automountServiceAccountToken: false
```

(Това е откъс: два реда от `revisor-deployment.yaml`, които 7.4 обяснява. Този на `prueba` казва `prueba`.) Обърни внимание и на онова, което **не** е в списъка: `revisor-publico.yaml`, директният `LoadBalancer` от Урок 6. Собственият му коментар го обявяваше: отсега нататък единствената входна точка навън е `Gateway`. Файлът се пази в `punto-de-partida/` като справка.

#### 7.2.3 Преместването

Новото пространство не „премества“ обекти; обектите от едно пространство не могат да се прехвърлят в друго. **Трият се от едното и се създават в другото.** Първо се премахва състоянието от Урок 6 със същия `kustomization`, който го е създал, и после се прилага този на настоящия урок. Токенът остава: той е същият файл за двата, и затова генерираният Secret запазва името си.

```bash
ctx && kubectl delete -k punto-de-partida
rm -f -- punto-de-partida/token.txt
ctx && kubectl apply -k .
```

```text
$ kubectl delete -k punto-de-partida
configmap "revisor-config-t6cm6872fk" deleted from default namespace
secret "revisor-token-mgc44f554f" deleted from default namespace
service "prueba" deleted from default namespace
service "revisor" deleted from default namespace
service "revisor-publico" deleted from default namespace
deployment.apps "prueba" deleted from default namespace
deployment.apps "revisor" deleted from default namespace
gateway.gateway.networking.k8s.io "revisor" deleted from default namespace
httproute.gateway.networking.k8s.io "revisor" deleted from default namespace

$ kubectl apply -k .
namespace/revisor created
serviceaccount/observador created
serviceaccount/prueba created
serviceaccount/revisor created
role.rbac.authorization.k8s.io/observador created
rolebinding.rbac.authorization.k8s.io/observador created
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-mgc44f554f created
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

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "revisor" rollout to finish: 2 of 3 updated replicas are available...
deployment "revisor" successfully rolled out

$ kubectl rollout status deployment/prueba -n revisor --timeout=180s
deployment "prueba" successfully rolled out

$ kubectl wait --for=condition=Programmed gateway/revisor -n revisor --timeout=240s
gateway.gateway.networking.k8s.io/revisor condition met
```

Прочети първите два блока отгоре надолу. `delete -k` трие девет обекта, а всеки ред казва **откъде** ги трие (`from default namespace`). `apply -k` създава двадесет: пространството (`namespace/revisor`), трите акаунта, `Role` и нейния `RoleBinding`, ConfigMap и Secret с обичайния хеш, двата Service-а, двата Deployment-а, входната точка и маршрута, и шестте мрежови политики. Обърни внимание на реда: пространството излиза първо. Kustomize предава обектите с пространствата от имена първи и затова не ти трябваха две стъпки. При типове от нова платформа, като `Gateway` в Урок 6, изчакването си остава твое: там въпросът не е в реда на списъка, а в това дали типът съществува.

Остана ли всичко там, където трябва?

```text
$ kubectl get namespace revisor -o go-template='{{range $k, $v := .metadata.labels}}{{$k}}={{$v}}{{"\n"}}{{end}}'
kubernetes.io/metadata.name=revisor
pod-security.kubernetes.io/audit=restricted
pod-security.kubernetes.io/audit-version=v1.37
pod-security.kubernetes.io/enforce=restricted
pod-security.kubernetes.io/enforce-version=v1.37
pod-security.kubernetes.io/warn=restricted
pod-security.kubernetes.io/warn-version=v1.37

$ kubectl get all -n revisor
NAME                           READY   STATUS    RESTARTS   AGE
pod/prueba-6899c74865-rgh68    1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          2m52s
pod/revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          2m52s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/prueba    ClusterIP   10.96.130.233   <none>        9000/TCP   2m52s
service/revisor   ClusterIP   10.96.146.219   <none>        80/TCP     2m52s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/prueba    1/1     1            1           2m52s
deployment.apps/revisor   3/3     3            3           2m52s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/prueba-6899c74865    1         1         1       2m52s
replicaset.apps/revisor-5d6fd4d6bd   3         3         3       2m52s

$ kubectl get all -n default
NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   14m

$ kubectl get gateway,httproute -n revisor
NAME                                        CLASS   ADDRESS          PROGRAMMED   AGE
gateway.gateway.networking.k8s.io/revisor   eg      172.27.255.200   True         2m52s

NAME                                          HOSTNAMES   AGE
httproute.gateway.networking.k8s.io/revisor               2m52s

$ kubectl wait --for=condition=Available deployment -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=revisor --timeout=180s
deployment.apps/envoy-revisor-revisor-b269644b condition met

$ kubectl get pods,services -n envoy-gateway-system
NAME                                                  READY   STATUS    RESTARTS   AGE
pod/envoy-gateway-5fc4949dcb-k6s46                    1/1     Running   0          14m
pod/envoy-revisor-revisor-b269644b-867f46cd7d-rbkcf   2/2     Running   0          2m52s

NAME                                     TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
service/envoy-gateway                    ClusterIP      10.96.130.219   <none>           18000/TCP,18001/TCP,18002/TCP,19001/TCP,9443/TCP   14m
service/envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       2m52s
```

`default` остана с едно-единствено нещо, Service-а `kubernetes`, който клъстерът създава сам: пространството е чисто. Целият проект е в `revisor`, а входната точка го обслужва от `envoy-gateway-system`, трето пространство: **входната точка не живее там, където живее проектът**. Запиши си го, защото мрежовата политика от 7.5 трябва да я пропусне и това става с `namespaceSelector`. И една проверка отвън на клъстера, както в Урок 6, за да видиш, че преместването не е затворило входната точка:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}
```

Едно последно решение на урока. След като проектът е преместен, скриптът премахва шестте мрежови политики:

```text
$ kubectl delete -n revisor -f red.yaml
networkpolicy.networking.k8s.io "cerrado" deleted from revisor namespace
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace
networkpolicy.networking.k8s.io "prueba-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "revisor-entrada" deleted from revisor namespace
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace
```

Това не е грешка, нито доказателство, че не вършат работа. Така се изучава **един слой наведнъж**. Шестте политики са в `kustomization.yaml`, защото крайното състояние на проекта ги носи, но ако бяха поставени, докато изучаваш Pod Security и RBAC, всеки упражнителен Pod би се родил без възможност да говори с API-то и нямаше да знаеш дали онова, което виждаш, го причинява един слой или друг. Връщат се в 7.5, с обяснението им.

### 7.3 Pod Security Admission

#### 7.3.1 Какво е: пазач на вратата на `kube-apiserver`

Когато изпълняваш `kubectl apply`, заявката ти минава през верига от контроли, преди да бъде запазена. Една от тях се нарича **допускане** (*admission*). [Документацията за Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) я описва: това е контролер, който проверява всеки Pod, който ще бъде създаден, спрямо един **стандарт** (*Pod Security Standards*) и решава според един етикет на пространството от имена, където би се родил. Не инсталира нищо: идва с `kube-apiserver`. Настройва се **с етикети на пространството**, а тези етикети имат три части:

- **Режимът**, който казва какво да се прави при нарушение. Има три: `enforce` („Pod-овете, които нарушават политиката, се отхвърлят“), `audit` („към журнала за одит се добавя анотация, но Pod-ът се допуска“) и `warn` („потребителят получава предупреждение, но Pod-ът се допуска“). Едно пространство може да ползва един, два или и трите, дори с различни нива.
- **Нивото**, което казва колко се изисква. [Стандартите за сигурност на Pod-овете](https://kubernetes.io/docs/concepts/security/pod-security-standards/) определят три. `privileged` е „умишлено отворено и напълно без ограничения“. `baseline` цели „да улесни приемането за обичайни натоварвания“ и същевременно да попречи на известните ескалации на привилегии. `restricted` е „силно ограничена“ политика, която следва актуалните практики за подсилване на защитата.
- **Версията** (по избор), която фиксира с кое издание на стандарта се сравнява Pod-ът. Всяка версия на Kubernetes може да прецизира какво изискват `baseline` и `restricted`; с `latest` стандартът се движи с клъстера, а с `v1.37` остава фиксиран.

Етикетът има тази форма: `pod-security.kubernetes.io/<РЕЖИМ>: <НИВО>` и, отделно, `pod-security.kubernetes.io/<РЕЖИМ>-version: <ВЕРСИЯ>`. Виж как е останало пространството на урока с трите:

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

Пространството `revisor` използва **и трите режима на едно и също ниво**, `restricted`, и трите фиксирани на `v1.37`. И трите заедно имат смисъл: `enforce` е този, който предпазва (отхвърля), `warn` е този, който те предупреждава **при прилагане** на един Deployment, преди да се провали (7.3.4), а `audit` оставя следа в журнала за одит на `kube-apiserver`, който курсът нито включва, нито измерва. Ръководството в документацията за прилагане на тези нива към едно пространство показва същото разпределение на ролите: `enforce` на нивото, което вече изпълняваш, а `audit` и `warn` на нивото, до което искаш да стигнеш, за да видиш какво би се провалило, преди да го изискаш.

#### 7.3.2 Трите нива, измерени

Преди пространството на урока — трите нива едно срещу друго. Създават се две пробни пространства, едно `privileged` и едно `baseline`, и на всяко (и на `revisor`) се иска да приеме два Pod-а, без да ги създава: `--dry-run=server` изпраща пълната заявка до `kube-apiserver`, който я валидира с всичките си контроли за допускане и не запазва нищо. Първият Pod иска `hostNetwork: true`, тоест да използва мрежата на възела вместо своя, нещо, което `baseline` вече забранява. Вторият е Pod с `curl`, написан без `securityContext`, като в кой да е урок.

```text
$ kubectl create namespace nivel-privileged
namespace/nivel-privileged created

$ kubectl create namespace nivel-baseline
namespace/nivel-baseline created

$ kubectl label namespace nivel-privileged pod-security.kubernetes.io/enforce=privileged
namespace/nivel-privileged labeled

$ kubectl label namespace nivel-baseline pod-security.kubernetes.io/enforce=baseline
namespace/nivel-baseline labeled

$ kubectl wait --for=create serviceaccount/default -n nivel-privileged --timeout=60s
serviceaccount/default condition met

$ kubectl wait --for=create serviceaccount/default -n nivel-baseline --timeout=60s
serviceaccount/default condition met
```

`kubectl wait --for=create` е изчакване, което може да не си очаквал: всяко ново пространство получава своя акаунт `default` няколко мига **след** като се роди, създава го контролер, а един Pod, поискан, преди акаунтът да съществува, се отхвърля по друга причина (`serviceaccount "default" not found`). В едно от пробните изпълнения на този урок (без запазен изход), без това изчакване, шестте проби по-долу се провалиха с това съобщение, а не с това за сигурността. Затова днес изчакването е на показ.

```text
--- espacio nivel-privileged ---
$ kubectl run hostnet -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
pod/hostnet created (server dry run)

$ kubectl run sinreglas -n nivel-privileged --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio nivel-baseline ---

$ kubectl run hostnet -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true)
[código de salida: 1]

$ kubectl run sinreglas -n nivel-baseline --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
pod/sinreglas created (server dry run)

--- espacio revisor ---

$ kubectl run hostnet -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server --overrides='{"spec":{"hostNetwork":true}}' -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "hostnet" is forbidden: violates PodSecurity "restricted:v1.37": host namespaces (hostNetwork=true), allowPrivilegeEscalation != false (container "hostnet" must set securityContext.allowPrivilegeEscalation=false), unrestrict
[código de salida: 1]

$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never --dry-run=server -- sleep 5 2>&1 | cut -c1-260
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinr
[código de salida: 1]
```

Изходите са съкратени до 260 знака с `cut`, за да се побират; пълното съобщение го виждаш в 7.3.3. Чети ги като таблица:

| Пространство | `hostNetwork: true` | Pod без `securityContext` |
|---|---|---|
| `nivel-privileged` | създаден (`server dry run`) | създаден |
| `nivel-baseline` | **отхвърлен**: `host namespaces (hostNetwork=true)` | създаден |
| `revisor` (`restricted`) | **отхвърлен**, и с повече причини | **отхвърлен** |

Три неща. Първо: `baseline` спира онова, което е известно като опасно (споделяне на мрежата на възела), и пропуска един нормален Pod, написан без грижа. `restricted` изисква и добрите практики и затова същият прост Pod, който `baseline` приема, тук се отхвърля. Второ: съобщението на `nivel-baseline` казва `"baseline:latest"`, без версия. Тъй като това пространство не е фиксирало `enforce-version`, стандартът е този на версията на клъстера, **която и да е тя**; съобщението на `revisor` казва `"restricted:v1.37"`, фиксиран. Ако клъстерът се актуализира, първият може да започне да отхвърля онова, което преди е приемал; вторият не се променя, докато не смениш етикета. Трето: скриптът изтрива двете пробни пространства накрая (`kubectl delete namespace`), което трие с тях всичко, което са имали.

```text
$ kubectl delete namespace nivel-privileged nivel-baseline
namespace "nivel-privileged" deleted
namespace "nivel-baseline" deleted
```

#### 7.3.3 `restricted`, прочетен ред по ред

Пробният Pod, който беше отхвърлен два пъти по-горе, е нормален Pod с `curl`. Сега без съкращения, в пространството на урока:

```text
$ kubectl run sinreglas -n revisor --image=curlimages/curl:8.22.0 --restart=Never -- sleep 60
Error from server (Forbidden): pods "sinreglas" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "sinreglas" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "sinreglas" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "sinreglas" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "sinreglas" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
[código de salida: 1]

$ kubectl get pods -n revisor -l run=sinreglas
No resources found in revisor namespace.
```

Съобщението има формата „Pod X не може да се създаде: нарушава PodSecurity "restricted:v1.37": “, следвана от списък, разделен със запетаи, и всеки елемент е нарушено правило с полето, което го поправя, в скоби. Четири:

1. `allowPrivilegeEscalation != false`: контейнерът трябва да декларира `securityContext.allowPrivilegeEscalation=false`. Без този ред един процес вътре би могъл да получи повече привилегии от родителския си процес (например като изпълни програма с бита *setuid*).
2. `unrestricted capabilities`: трябва да декларира `securityContext.capabilities.drop=["ALL"]`. *Capabilities* на Linux са парченца от онова, което преди можеше само `root`; контейнер, който не иска нищо, получава набор по подразбиране, а `restricted` изисква да се махне всичко.
3. `runAsNonRoot != true`: Pod-ът или контейнерът трябва да декларира `runAsNonRoot=true`. Не стига образът *да е* на обикновен потребител: манифестът трябва да **казва**, че го изисква, за да отхвърли клъстерът образ, който един ден се превърне в `root`.
4. `seccompProfile`: трябва да декларира `seccompProfile.type` като `RuntimeDefault` или `Localhost`. `seccomp` е филтърът за извикванията към ядрото; профилът на *runtime* блокира най-опасните.

И не беше отхвърлен заради пето, `readOnlyRootFilesystem`, което курсът слага от Урок 2: това е добра практика, но **не** я изисква нивото `restricted`. Това е разликата между онова, което клъстерът налага, и онова, което ти си налагаш. Всеки ред от този списък е един от четирите, които `securityContext` на `revisor` носи от Урок 2; затова `revisor` и `prueba` се родиха без проблем в същото това пространство. А `get pods` го потвърждава: `No resources found`. Отказът е **преди** създаването: Pod-ът не съществува, дори в състояние на грешка.

#### 7.3.4 Какво може (и какво не може) да се подсили: `kube-system` и `dry-run`

Защо да не се сложи `restricted` във всички пространства, без да се мисли? Същият `--dry-run=server`, който използва с Pod-овете, служи, за да се види какво би станало с един **етикет**: изчислява спрямо Pod-овете, които вече съществуват, и предупреждава, без да променя нищо. Изпробва се с две пространства:

```text
$ kubectl label --dry-run=server --overwrite namespace kube-system pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"
Warning: coredns-559f6c778d-q8k29 (and 1 other pod): runAsNonRoot != true, seccompProfile
Warning: etcd-curso-k8s-l7-control-plane (and 3 other pods): host namespaces, hostPort, probe or lifecycle host, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true
Warning: kindnet-82j5f (and 2 other pods): host namespaces, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
Warning: kube-proxy-d6hbh (and 2 other pods): host namespaces, privileged, allowPrivilegeEscalation != false, unrestricted capabilities, restricted volume types, runAsNonRoot != true, seccompProfile
namespace/kube-system labeled (server dry run)

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

При `kube-system` има четири предупреждения, по едно за група Pod-ове, и всички започват с `Warning: existing pods in namespace "kube-system" violate the new PodSecurity enforce level "restricted:latest"`: CoreDNS не декларира `runAsNonRoot` нито `seccompProfile`; `etcd`, `kindnet` и `kube-proxy` ползват мрежата на възела (`host namespaces`) и искат томове от тип `hostPath` (`restricted volume types`), а `kube-proxy` освен това е *privileged*. Искат ги, защото работата им е да докосват възела. Затова **нивото не се прилага по мода**: първо се измерва и има пространства (системните), където `restricted` не се побира. А същият `--dry-run` върху `revisor` казва `namespace/revisor not labeled (server dry run)` без нито едно предупреждение: проектът вече изпълнява онова, което се изисква.

А Pod-овете, които вече са работели, когато се слага етикетът? Документацията казва, че при добавяне или смяна на етикет `enforce` контролерът проверява всеки Pod на пространството спрямо новата политика и връща нарушенията като предупреждения. Не казва какво става с Pod-а. Измерва се с пробно пространство: ражда се без етикети, получава Pod, който не изпълнява `restricted`, и **след това** му се слага `enforce=restricted`.

```text
$ kubectl create namespace nivel-previo
namespace/nivel-previo created

$ kubectl wait --for=create serviceaccount/default -n nivel-previo --timeout=60s
serviceaccount/default condition met

$ kubectl run viejo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600
pod/viejo created

$ kubectl wait --for=condition=Ready pod/viejo -n nivel-previo --timeout=300s
pod/viejo condition met

$ kubectl label namespace nivel-previo pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "nivel-previo" violate the new PodSecurity enforce level "restricted:latest"
Warning: viejo: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/nivel-previo labeled

$ kubectl get pod viejo -n nivel-previo
NAME    READY   STATUS    RESTARTS   AGE
viejo   1/1     Running   0          21s

$ kubectl run nuevo -n nivel-previo --image=curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777 --restart=Never -- sleep 3600 2>&1 | cut -c1-200
Error from server (Forbidden): pods "nuevo" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nuevo" must set securityContext.allowPrivilegeEscalati
[código de salida: 1]

$ kubectl delete namespace nivel-previo
namespace "nivel-previo" deleted
```

Редът на `label` носи предупреждението на контролера, което назовава Pod-а `viejo` и правилата, които нарушава. А следващият `get pod` го оставя `Running`: **етикетът информира и не изгони**. Pod-ът `nuevo`, поискан със същия манифест, се отхвърля. Поставянето на `enforce` не почиства едно пространство; затваря вратата за онова, което пристигне от този момент нататък. Един стар Pod, който нарушава нивото, остава, докато не бъде пресъздаден (например с `rollout restart`), и тогава вече не може да се роди. Това е капан в експлоатацията: в пространство с `enforce` едно рестартиране може да събори Deployment, който е работел с месеци, ако шаблонът му никога не е отговарял на нивото.

Още една проба от същия вид, този път с режима `warn`. На `kube-apiserver` се иска, без да се прилага промяната, да махне един ред от `revisor` (профила `seccomp`) и да каже какво мисли:

```text
$ kubectl patch deployment revisor -n revisor --type=json -p '[{"op":"remove","path":"/spec/template/spec/securityContext/seccompProfile"}]' --dry-run=server
Warning: would violate PodSecurity "restricted:v1.37": seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/revisor patched

$ kubectl get deployment revisor -n revisor -o jsonpath='{.spec.template.spec.securityContext.seccompProfile.type}{"\n"}'
RuntimeDefault
```

Кръпката **се приема** (`deployment.apps/revisor patched`, но е `--dry-run=server`: не е запазена) и идва с предупреждение в един ред: `would violate PodSecurity "restricted:v1.37": seccompProfile …`. Това е `warn`: предупреждава този, който прилага, без да отхвърля. Втората команда потвърждава, че Deployment-ът продължава да казва `RuntimeDefault`. И тази разлика, „предупреждава“ срещу „отхвърля“, е следващата грешка.

### Грешката, която ще видиш

Грешката на този урок е от онези, които най-много обърква, защото командата завършва **успешно**, а услугата не се появява. Предизвиква се с `fig07_01.sin-reglas.yaml`, **програма**, която се проваля нарочно: Deployment на `revisor`, написан както в кой да е урок, без `securityContext`.

```yaml
# fig07_01.sin-reglas.yaml — FALLA A PROPÓSITO: un Deployment del revisor escrito
# como en un tutorial cualquiera, SIN securityContext. La imagen ya corre sin ser
# root (usuario 65532), pero el manifiesto no lo DECLARA. En el espacio «revisor»
# (nivel restricted) el Deployment se crea con una advertencia y sus Pods no
# nacen: el ReplicaSet registra FailedCreate. Se borra con kubectl delete -f.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sinreglas
  labels:
    app: sinreglas
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sinreglas
  template:
    metadata:
      labels:
        app: sinreglas
    spec:
      containers:
      - name: revisor
        image: curso-docker-revisor:1.6.0
        imagePullPolicy: IfNotPresent
        env:
        - name: REVISOR_SERVICIOS
          value: "prueba http://prueba:9000/ 2s"
        resources:
          requests: {cpu: 10m, memory: 16Mi}
          limits: {cpu: 100m, memory: 32Mi}
```

Образът наистина работи без да е `root` (потребител 65532), но манифестът не го декларира, а точно това проверява нивото `restricted`. Прилага се в пространството на урока:

```text
$ kubectl apply -n revisor -f fig07_01.sin-reglas.yaml
Warning: would violate PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/sinreglas created

$ kubectl wait --for=condition=ReplicaFailure deployment/sinreglas -n revisor --timeout=120s
deployment.apps/sinreglas condition met

$ kubectl get deployment sinreglas -n revisor
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
sinreglas   0/1     0            0           1s

$ kubectl get replicaset -n revisor -l app=sinreglas
NAME                   DESIRED   CURRENT   READY   AGE
sinreglas-7c585c788d   1         0         0       1s

$ kubectl get pods -n revisor -l app=sinreglas
No resources found in revisor namespace.

$ kubectl describe replicaset -n revisor -l app=sinreglas | sed -n '/^Events:/,$p' | head -4
Events:
  Type     Reason        Age   From                   Message
  ----     ------        ----  ----                   -------
  Warning  FailedCreate  2s    replicaset-controller  Error creating: pods "sinreglas-7c585c788d-47khh" is forbidden: violates PodSecurity "restricted:v1.37": allowPrivilegeEscalation != false (container "revisor" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "revisor" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "revisor" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "revisor" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Чете се по ред, от симптома към причината.

**Първо, какво каза `apply`.** Два реда: предупреждение (`Warning: would violate PodSecurity "restricted:v1.37": …`) и `deployment.apps/sinreglas created`. **Създаде се.** Deployment-ът е обект, не Pod, и не нарушава нищо. Предупреждението е режимът `warn`, който проверява шаблона на Pod, който Deployment-ът носи вътре, за да те предупреди предварително. Ако твоят терминал или твоят *pipeline* не показва предупрежденията, тук ти е убягнало предупреждението. Това казва документацията: режимите `audit` и `warn` се прилагат и към ресурсите за натоварване, но **`enforce` не**: прилага се само към получените Pod-ове.

**Второ, симптомът.** `kubectl wait` чака рядко условие, `ReplicaFailure`, което Deployment-ът активира, когато неговият ReplicaSet не може да създаде реплики, и го намира веднага. После: `READY 0/1`, `UP-TO-DATE 0`, `AVAILABLE 0`. ReplicaSet-ът съществува и иска 1 Pod, `DESIRED 1`, но има `CURRENT 0`. А `get pods` казва `No resources found`. Deployment-ът никога не се провали на глас; просто няма Pod-ове.

**Трето, причината.** Тя е в събитията на ReplicaSet, не в тези на Deployment-а, нито в тези на Pod-а (който не съществува): `Warning FailedCreate … replicaset-controller Error creating: pods "sinreglas-…" is forbidden: violates PodSecurity "restricted:v1.37": …`. Това е същото съобщение като в 7.3.3, но сега го получава контролерът, който го записва и го повтаря. Затова трябва да се търси в **ReplicaSet**.

**Поправката.** Поправя се манифестът, не пространството: `securityContext`, какъвто има `revisor` и тестовата услуга, с четирите реда от 7.3.3. Тук, тъй като Deployment-ът няма да се използва, се изтрива.

```text
$ kubectl delete -n revisor -f fig07_01.sin-reglas.yaml
deployment.apps "sinreglas" deleted from revisor namespace
```

**Редът, когато един Deployment няма Pod-ове:**

1. `kubectl get deployment`: `READY 0/N`?
2. `kubectl get replicaset -l app=…`: `CURRENT` по-малко от `DESIRED`?
3. `kubectl describe replicaset`: събитията, `FailedCreate` и пълната причина.
4. Ако казва `PodSecurity`, нивото на пространството не се сваля; поправя се манифестът.


### 7.4 Сервизни акаунти и минимални права

#### 7.4.1 Какво е сервизен акаунт

Когато ти изпълняваш `kubectl get pods`, API-то знае кой си по твоя `kubeconfig`. Когато една **програма, която работи вътре в клъстера**, говори с API-то (контролер, инструмент за разгръщане, услуга, която трябва да знае какви други Pod-ове съществуват), API-то също трябва да знае коя е тя. Тази идентичност се нарича **сервизен акаунт** (*ServiceAccount*). [Документацията](https://kubernetes.io/docs/concepts/security/service-accounts/) го определя като „вид нечовешки акаунт, който в Kubernetes дава отделна идентичност в клъстера“. Има три свойства, които тук са важни:

- **Той е обект с пространство**, като Pod. Казва се `revisor` в пространството `revisor`, а пълното му име за RBAC има формата `system:serviceaccount:<пространство>:<акаунт>`, което за акаунта `revisor` в пространството `revisor` излиза `system:serviceaccount:revisor:revisor` (името се повтаря, защото съвпадат). Ще го напишеш в 7.4.3.
- **Всяко пространство се ражда с един на име `default`.** Клъстерът го създава сам (раздел 7.3.2 току-що го изчака) и го дава на всеки Pod, който не поиска друг. По подразбиране няма права извън основното откриване на API-то.
- **По подразбиране клъстерът монтира удостоверенията му във всеки Pod.** Същата страница: „по подразбиране Kubernetes дава на Pod-а удостоверенията на присвоения акаунт“. От версия 1.22 това е краткотраен токен, който се подновява сам, предаден като проектиран том; преди беше Secret с дълъг живот. Това е томът `kube-api-access-…`, който видя в 7.1.3: Pod-ът може да прочете токена си във файл и да се представи с него пред API-то.

Фактът от последната точка е важният. **Ако една програма във Pod е компрометирана, първият ѝ въпрос е „какво мога да правя с токена, който имам?“**, а това удостоверение е монтирано, дори програмата никога да не го ползва. За `revisor` и за `prueba`, които не говорят с API-то, това е риск без никаква полза. Затова двата Deployment-а на урока декларират `automountServiceAccountToken: false`. [Ръководството за сервизни акаунти](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/) обяснява, че може да се изключи в акаунта или в Pod-а, и че ако и двамата казват нещо, решава Pod-ът.

#### 7.4.2 Правата: `Role` и `RoleBinding`

Току-що създаденият акаунт не може нищо. Правата се добавят с два обекта. [Документацията за RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) (контрол на достъпа въз основа на роли) ги разграничава така: една `Role` „съдържа правила, които представляват набор от права“, а правата са **чисто адитивни**: няма правила за „отказ“. Една `Role` „винаги задава права в рамките на пространство от имена“. Роднината ѝ `ClusterRole` е същото, но без пространство, за ресурси, които нямат такова (например възлите), или за повтаряне на набор от правила в няколко пространства. `RoleBinding` е лепилото: „предоставя правата, определени в една роля, на набор от субекти“ (потребители, групи или сервизни акаунти), в рамките на пространство. Два обекта, а не един, защото ролята се пише веднъж и може да се свърже с много акаунти.

Всяко правило на една `Role` има три части: `apiGroups` (групата на API-то: `""` е ядрото, където живеят Pod-овете и Service-ите; `apps` е мястото на Deployment-ите), `resources` (типовете) и `verbs` (какво може да се прави: `get` да прочетеш един, `list` да изброиш, `watch` да слушаш за промени и тези, които променят — `create`, `update`, `patch` и `delete`). Прочети го в `cuentas.yaml`, цялото:

```yaml
# cuentas.yaml — Lección 7: cada carga con su cuenta, y ninguna con permisos que
# no necesita. El revisor y prueba no le hablan a la API: cero permisos y sin
# credenciales montadas. «observador» puede mirar y nada más.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: revisor
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prueba
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: observador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: observador
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: observador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: observador
subjects:
- kind: ServiceAccount
  name: observador
  namespace: revisor
```

Три акаунта и двойка обекти за права. `revisor` и `prueba` са акаунти **без права**: никой `RoleBinding` не ги споменава, и двата носят `automountServiceAccountToken: false` и на ниво акаунт. `observador` е акаунтът за четене: `Role` `observador` му дава `get`, `list` и `watch`, само тези три глагола, върху Pod-ове, техните журнали (`pods/log`, подресурс), Service-и и събития от ядрото, и върху Deployment-и и ReplicaSet-и от групата `apps`. Обърни внимание на онова, което **не** е там: Secret-и (токенът на `revisor` е Secret), `create`, `update`, `patch`, `delete`, `exec` (`pods/exec` е друг подресурс и не е изброен) и всичко извън пространството. Правилото за дизайн е „онова, което му трябва, и нищо повече“, и се пише, като се назовава всеки ресурс, без заместващи знаци (`*`), защото заместващият знак включва и онова, което някой ден добави клъстерът.

`RoleBinding` казва **на кого** се дава: на акаунта `observador` от пространството `revisor`. Въпреки това този акаунт не го ползва нито един Deployment на урока. Съществува, за да се види какво значи „само за четене“ с истински акаунт, и за Упражнение 2.

```text
$ kubectl get serviceaccounts -n revisor
NAME         AGE
default      5m2s
observador   5m2s
prueba       5m2s
revisor      5m2s

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken,VOLUMENES:.spec.volumes[*].name'
POD                        CUENTA    AUTOMOUNT   VOLUMENES
prueba-6899c74865-rgh68    prueba    false       <none>
revisor-5d6fd4d6bd-6kb4k   revisor   false       datos,token
revisor-5d6fd4d6bd-jdmx8   revisor   false       datos,token
revisor-5d6fd4d6bd-pj8r9   revisor   false       datos,token
```

Чете се така: четири акаунта, не три. Четвъртият, `default`, го е създал клъстерът сам. А таблицата с Pod-ове казва, за всеки, с кой акаунт работи, че `AUTOMOUNT` е `false` и какви томове има: `datos` и `token` при `revisor`, никакъв при `prueba`, и **никой от двамата няма `kube-api-access-…` от 7.1.3**. В сравнение с „преди“ този том изчезна.

```text
$ kubectl get role,rolebinding -n revisor -o wide
NAME                                        CREATED AT
role.rbac.authorization.k8s.io/observador   2026-10-21T22:52:57Z

NAME                                               ROLE              AGE    USERS   GROUPS   SERVICEACCOUNTS
rolebinding.rbac.authorization.k8s.io/observador   Role/observador   5m3s                    revisor/observador

$ kubectl describe role observador -n revisor
Name:         observador
Labels:       <none>
Annotations:  <none>
PolicyRule:
  Resources         Non-Resource URLs  Resource Names  Verbs
  ---------         -----------------  --------------  -----
  events            []                 []              [get list watch]
  pods/log          []                 []              [get list watch]
  pods              []                 []              [get list watch]
  services          []                 []              [get list watch]
  deployments.apps  []                 []              [get list watch]
  replicasets.apps  []                 []              [get list watch]
```

#### 7.4.3 Да питаш, без да пробваш: `kubectl auth can-i`

Как да разбереш какво може да прави един акаунт? Пита се API-то с `kubectl auth can-i`, който отговаря `yes` или `no`. За да попиташ за **друга** идентичност, се използва `--as`, който кара `kubectl` да се представи за тази идентичност в заявката; сервизният акаунт се пише с пълното си име, `system:serviceaccount:<пространство>:<акаунт>`. (Подмяната на идентичност е право, което ти имаш като администратор на твоя клъстер на kind; обикновен потребител на истински клъстер нямаше да го има.) Първо `revisor`, който не бива да може нищо, и `observador`, който трябва да може да чете:

```text
$ kubectl auth can-i --list -n revisor --as=system:serviceaccount:revisor:revisor | head -5
Resources                                       Non-Resource URLs                      Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                                     []               [create]
selfsubjectaccessreviews.authorization.k8s.io   []                                     []               [create]
selfsubjectrulesreviews.authorization.k8s.io    []                                     []               [create]
clustertrustbundles.certificates.k8s.io         []                                     []               [get list watch]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:revisor
no
[código de salida: 1]

$ kubectl auth can-i get pods -n revisor --as=system:serviceaccount:revisor:observador
yes

$ kubectl auth can-i get pods --subresource=log -n revisor --as=system:serviceaccount:revisor:observador
yes
```

Списъкът на `revisor` не е празен и това трябва да се чете внимателно. Четирите реда са права, които почти всяка идентичност получава по подразбиране. Три са *проверки върху себе си*: `selfsubjectreviews` (кой съм?, според `kubectl explain` връща информацията за потребителя, която `kube-apiserver` има за питащия), `selfsubjectaccessreviews` (мога ли да направя това?, което е въпросът, който задава самият `can-i`) и `selfsubjectrulesreviews` (какви действия мога да правя в това пространство?). Четвъртият, `clustertrustbundles`, са пакети от публични корени сертификати; описанието на типа казва, че всички сервизни акаунти могат да ги четат по подразбиране. Ролите, които дават първите три, идват с клъстера (`system:basic-user`, която документацията описва като достъп само за четене до основна информация за самия себе си, свързана с групата `system:authenticated`). Никое не е право върху **твоите** обекти. Въпросът, който има значение, `get pods`, отговаря `no`, с изходен код 1: `kubectl auth can-i` връща 0, когато отговорът е `yes`, и 1, когато е `no`, и това служи, за да се използва в скрипт. `observador` отговаря `yes` на четенето на Pod-ове и на четенето на журналите им (`--subresource=log`). Сега онова, което **не** бива да може:

```text
$ kubectl auth can-i delete pods -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get secrets -n revisor --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]

$ kubectl auth can-i get pods -n default --as=system:serviceaccount:revisor:observador
no
[código de salida: 1]
```

Три `no`: не може да трие Pod-ове (`Role` не включва `delete`), не може да чете Secret-и (не са в списъка) и не може да чете Pod-ове от `default` (`Role` и `RoleBinding` живеят в `revisor`; ролята на пространство не преминава в друго). Това е прякото доказателство, че пространството от имена е единицата на правата, макар да не е такава на мрежата.

`can-i` пита; истинската заявка потвърждава. С `--as` `kubectl` извършва операцията, сякаш е този акаунт:

```text
$ kubectl get deployments -n revisor --as=system:serviceaccount:revisor:observador
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
prueba    1/1     1            1           5m5s
revisor   3/3     3            3           5m5s

$ kubectl delete pod -n revisor -l app=prueba --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): pods "prueba-6899c74865-rgh68" is forbidden: User "system:serviceaccount:revisor:observador" cannot delete resource "pods" in API group "" in the namespace "revisor"
[código de salida: 1]

$ kubectl get secrets -n revisor --as=system:serviceaccount:revisor:observador
Error from server (Forbidden): secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"
[código de salida: 1]
```

Изброяването на Deployment-и работи. Изтриването на Pod и изброяването на Secret-и дават `Error from server (Forbidden)` и си струва да прочетеш цялото съобщение, защото има формата на грешките на RBAC и ще го видиш в деня, в който нещо се счупи: `secrets is forbidden: User "system:serviceaccount:revisor:observador" cannot list resource "secrets" in API group "" in the namespace "revisor"`. Кой (`User "system:serviceaccount:revisor:observador"`), кой глагол и върху какво (`cannot list resource "secrets"`), в коя група на API-то (`""`, ядрото) и в кое пространство. С тези пет части знаеш точно кое правило да добавиш, ако правото е било легитимно, или какво да оставиш, както е, ако не е. Една подробност: глаголът във второто съобщение е `list`, не `get`; поискал си „всички Secret-и“ и това е `list`. Да прочетеш един по име е `get`. Двата глагола са разделени нарочно.

#### 7.4.4 Същото, отвътре на един Pod

Дотук всичко се изпробва с подмяна на идентичност от твоя терминал. Липсва пробата, която най-много прилича на атака: програма **вътре** в Pod, с онова, което Pod-ът има подръка. Използват се три помощни Pod-а, всички с `curl`: `depurar` (този от Урок 3, с етикета `acceso-revisor: permitido`, от който мрежата ще има нужда), `intruso` (същият, но **без** този етикет; това е Pod-ът на екипа по данни от сцената) и `lector`, нов, който носи акаунта `observador` **с монтиран токен**. И трите отговарят на `restricted`, като всичко, което се ражда в това пространство. Прочети `fig07_04.lector.yaml`:

```yaml
# fig07_04.lector.yaml — un Pod que SÍ lleva credenciales: usa la cuenta «observador»
# y pide que se le monte su token (automountServiceAccountToken: true). Sirve para
# ver, desde dentro de un Pod, lo que el RBAC de cuentas.yaml permite y lo que no.
# Cumple «restricted». Se aplica con: kubectl apply -n revisor -f fig07_04.lector.yaml
apiVersion: v1
kind: Pod
metadata:
  name: lector
  labels:
    app: lector
spec:
  restartPolicy: Never
  serviceAccountName: observador
  automountServiceAccountToken: true
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: lector
    image: curlimages/curl:8.22.0@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777
    command: ["sleep", "3600"]
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

Това е умишлено изключение от правилото на 7.4.1: `automountServiceAccountToken: true`, което е стойността по подразбиране, написана на глас. Съществува, за да покаже какво позволява един монтиран токен. Прочети го срещу списъка на `intruso`, който ползва акаунта `default` **без** токен (`depurar` и `intruso` го декларират изключен):

```text
$ kubectl apply -n revisor -f depurar.yaml -f intruso.yaml -f fig07_04.lector.yaml
pod/depurar created
pod/intruso created
pod/lector created

$ kubectl wait -n revisor --for=condition=Ready pod/depurar pod/intruso pod/lector --timeout=180s
pod/depurar condition met
pod/intruso condition met
pod/lector condition met

$ kubectl exec -n revisor lector -- /bin/ls /var/run/secrets/kubernetes.io/serviceaccount
ca.crt
namespace
token
```

`lector` има три файла в `/var/run/secrets/kubernetes.io/serviceaccount`: `ca.crt` (сертификатът, с който да разпознае API-то), `namespace` (пространството му) и `token` (удостоверението му). С тях `curl` се представя пред API-то със заглавката `Authorization: Bearer <token>`. Адресът е `https://kubernetes.default.svc`, името на Service-а `kubernetes` от `default`, който е входната точка на API-то за Pod-овете. Четири заявки:

```text
$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 200

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "secrets %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets'
secrets 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s -o /dev/null -w "pods-default %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/default/pods'
pods-default 403

$ kubectl exec -n revisor lector -- sh -c 'curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/secrets | grep -E "message|code"'
  "message": "secrets is forbidden: User \"system:serviceaccount:revisor:observador\" cannot list resource \"secrets\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

Един `200` и три `403`. С токена на `observador` `lector` **може** да изброи Pod-овете на `revisor` (правото, което му дадохме) и **не може** да изброи Secret-ите на същото пространство, нито Pod-овете на `default`. Четвъртият блок е същата заявка за Secret-и със суровия отговор, филтриран: това е JSON грешката на API-то, със същото съобщение, което видя с `--as`. Това обещава RBAC, но погледнато от страната на онзи, който напада: откраднат токен на `observador` има обхвата на `Role` и нито един ресурс повече. Затова `Role` се пише къса.

А сега Pod-ът, който **няма** токен:

```text
$ kubectl exec -n revisor intruso -- sh -c '/bin/ls /var/run/secrets/kubernetes.io; echo código=$?' 2>&1
ls: /var/run/secrets/kubernetes.io: No such file or directory
código=1

$ kubectl exec -n revisor intruso -- sh -c 'curl -s -k https://kubernetes.default.svc/api/v1/namespaces/revisor/pods | grep -E "message|code"'
  "message": "pods is forbidden: User \"system:anonymous\" cannot list resource \"pods\" in API group \"\" in the namespace \"revisor\"",
  "code": 403
```

Директорията не съществува: `ls: /var/run/secrets/kubernetes.io: No such file or directory`. `intruso` няма дори удостоверение, което да представи. Ако въпреки това говори с API-то (`curl -k`, който не проверява сертификата, само за тази проба), API-то го приема като `system:anonymous`, идентичността на онзи, който не се идентифицира, и му отговаря `403`: `pods is forbidden: User "system:anonymous" cannot list resource "pods"`. Нула права и нула удостоверения; това е състоянието, което искаш за всеки Pod, който не говори с API-то. (Фактът, че API-то отговаря с `403`, означава, че `intruso` **е стигнал** до API-то: единственото, което го спира тук, е RBAC. Онова, което би му попречило дори да стигне, е мрежата, и 7.5 го измерва.)


### 7.5 Мрежата: отворена, докато някой не я затвори

#### 7.5.1 Моделът, преди да пипнеш каквото и да било

[Документацията за мрежовите политики](https://kubernetes.io/docs/concepts/services-networking/network-policies/) описва модела с три изречения, които си струва да се научат наизуст, защото от тях излиза всичко останало:

- **По подразбиране Pod не е изолиран.** „По подразбиране Pod не е изолиран за изходящия трафик; всички изходящи връзки са позволени“, и същото за входящия: „всички входящи връзки са позволени“. Това е състоянието, в което са днес твоите Pod-ове.
- **Pod се изолира, когато политика го избере.** „Pod е изолиран за изходящия трафик, ако има някоя `NetworkPolicy`, която го избира и има `Egress` в своите `policyTypes`“, и по същия начин за входящия с `Ingress`. Двете посоки се изолират поотделно. Политика, която казва само `Ingress`, не засяга изходящия трафик.
- **Политиките се сумират.** „Мрежовите политики не са в конфликт; те са адитивни.“ Ако няколко политики се отнасят до един Pod в една посока, позволеното е **обединението** на онова, което всяка позволява. Редът няма значение. И не съществува правило за „отказ“: онова, което никоя не позволява, е забранено, но само за Pod-овете, които вече са изолирани.

Една политика има четири части: `podSelector` (към кои Pod-ове **на пространството** се прилага; `{}` значи всички), `policyTypes` (дали изолира входящия, изходящия или двата) и списъци `ingress` и `egress` с онова, което се **позволява**, всеки с `from` или `to` (откъде или накъде) и `ports`. А `from` или `to` могат да бъдат три неща: `podSelector` (Pod-ове на **това** пространство), `namespaceSelector` (всички Pod-ове на избраните пространства) или, заедно в един и същ елемент, и двете (избрани Pod-ове от избрани пространства). Подробност, която хапе: `from` е списък и всеки елемент на списъка е алтернатива (**или**); онова, което е в един и същ елемент, се комбинира с **и**.

И условието, което има най-голямо значение: самата документация предупреждава, че „клъстерите трябва да използват мрежов плъгин, който поддържа `NetworkPolicy`“ и че „създаването на ресурс `NetworkPolicy` без контролер, който да го реализира, няма ефект“. Клъстерът запазва твоята политика, без да се оплаква, а трафикът продължава да минава. Това е тих провал. Затова планът на курса казваше „ако мрежовият плъгин на kind не я прилага, се инсталира друг“. Измерва се, не се предполага.

#### 7.5.2 Кой ги прилага в kind?

Възлите на kind ползват по подразбиране мрежов плъгин, наречен `kindnetd` ([конфигурацията на kind](https://kind.sigs.k8s.io/docs/user/configuration/) го описва като проста реализация на мрежа, базирана на стандартни CNI плъгини; *CNI* е интерфейсът, с който Kubernetes иска от един плъгин да осигури мрежа на Pod-овете). Пита се клъстерът какво работи:

```text
$ kubectl get daemonset -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kindnet      3         3         3       3            3           kubernetes.io/os=linux   17m
kube-proxy   3         3         3       3            3           kubernetes.io/os=linux   17m

$ kubectl get daemonset kindnet -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
docker.io/kindest/kindnetd:v20260820-69b56db7
```

Има DaemonSet `kindnet` с по един Pod на възел, а образът му е `kindest/kindnetd:v20260820-69b56db7`. Да знаеш кой е, не казва дали прилага политики. Бележките към изданието [v0.24.0 на kind](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0) обявяват, сред основните си точки, „поддръжка на мрежови политики чрез `sigs.k8s.io/kube-network-policies`“. Това е, което казва хартията. Важното е онова, което измерва твоят клъстер, а за да се измери, е нужен свидетел: два Pod-а с `curl`, които не са в списъка на никого.

```text
$ kubectl apply -n default -f intruso.yaml
pod/intruso created

$ kubectl wait -n default --for=condition=Ready pod/intruso --timeout=180s
pod/intruso condition met

$ kubectl get pods -A -l 'app in (depurar,intruso,lector)' -L acceso-revisor
NAMESPACE   NAME      READY   STATUS    RESTARTS   AGE   ACCESO-REVISOR
default     intruso   1/1     Running   0          1s    
revisor     depurar   1/1     Running   0          14s   permitido
revisor     intruso   1/1     Running   0          14s   
revisor     lector    1/1     Running   0          13s   
```

Има `intruso` в `revisor` и друг в `default`: този от собственото пространство е Pod-ът на екипа по данни от сцената; този от `default` е кой да е друг екип на клъстера. И двамата се родиха без етикета `acceso-revisor`. `depurar` я има (`permitido`); `intruso` и `lector` — не, а таблицата го казва с празната колона. Това има значение в 7.5.4.

#### 7.5.3 Без правила: онова, което пространството от имена НЕ изолира

С шестте премахнати политики (7.2.3), ето какво може да прави `intruso` от `revisor` и какво може този от `default`:

```text
$ kubectl get networkpolicy -n revisor
No resources found in revisor namespace.

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://prueba:9000/
sano

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez
ok

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

Четат се четири отговора и четирите са лоши новини:

1. `intruso` говори с `revisor` и получава неговия `/salud`. Без токена не може да поиска отчета (получава `401`), но стигна.
2. Говори с `prueba:9000`, който не е негов, и получава `sano`, режимът на тестовата услуга. С един `POST` към `/modo/caido` би могъл да го постави в `caido`: тестовата услуга **няма удостоверяване** и мрежата не я защитава.
3. Говори с API-то на клъстера, на `/livez`, и то отговаря `ok`. Този път за проверка на състоянието отговаря без удостоверения нарочно (документацията за RBAC го нарича неделикатна информация, ролята `system:public-info-viewer`), така че отговорът не е дефект на API-то. Важното е друго: един кой да е Pod има **мрежов път** до `kube-apiserver` (през Service-а `kubernetes`, порт 443) и никой не му го е отнел.
4. `intruso` от `default` стига до `revisor` от `revisor`, като напише пълното име на Service-а, `revisor.revisor.svc.cluster.local`. **Две различни пространства от имена и нито една стена между тях.** Това е онова, което документацията за пространствата от имена не твърди и което мнозина приемат за дадено.

Това е отговорът на втория въпрос от 5:58 и не е този, който искаше: да, един Pod на екипа по данни може да говори с `revisor`, без да минава през входната точка.

#### 7.5.4 Всичко затворено

Първата политика затваря всичко, без никакво отваряне. Това е къса **програма**:

```yaml
# fig07_02.cerrado.yaml — la primera regla de red.yaml, sola: cierra la entrada
# y la salida de TODOS los Pods del espacio donde se aplica, sin ninguna apertura.
# Se aplica con -n revisor para ver qué se rompe (hasta el DNS), y después se
# completa con red.yaml. No forma parte de la kustomization.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

`podSelector: {}` избира всички Pod-ове на пространството, а `policyTypes: [Ingress, Egress]` ги изолира и в двете посоки. Тъй като няма списъци `ingress` нито `egress`, не се позволява нищо. Прилага се и се измерва същото като преди:

```text
$ kubectl apply -n revisor -f fig07_02.cerrado.yaml
networkpolicy.networking.k8s.io/cerrado created

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- timeout 8 nslookup revisor.revisor.svc.cluster.local
;; connection timed out; no servers could be reached

command terminated with exit code 1
[código de salida: 1]

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Всичко спря да работи и е добре да се разграничат три сигнала, които си приличат. `command terminated with exit code 28` е кодът на `curl` за **изтекло време**: не е имало отговор в 3-те секунди, които му даде с `-m 3`. Един `curl` срещу политика, която изхвърля пакети, не получава отказ, а само мълчание. Различно е от `connection refused` (код 7, на който ти отговаря някой, който казва „тук няма нищо“, и който видя в Уроци 3 и 5) и от един `403` (на който отговаря някой, който те е чул и ти е казал не). Има три вида „не“ и се различават по кода. Втори сигнал: `depurar`, Pod-ът **с** етикета, също не стига. Още нищо не си отворил. Трети: `nslookup` също изтече, `;; connection timed out; no servers could be reached`. **Заявката за имена е мрежов трафик**, който излиза от Pod-а към DNS на клъстера, а политиката `cerrado` затвори и това. При затворен изходящ трафик Pod-овете на пространството не могат да попитат кой е `revisor`.

Между `apply` и пробите има изчакване от 8 секунди (`$ sleep 8`, на показ в пълния изход на `correr.salida.txt`); 7.5.7 измерва колко време отнема програмирането на една политика и оттам идва запасът.

Има и други ефекти, които се измерват с три команди от твоята машина и една от Pod-а, който чете API-то:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
000
[código de salida: 28]

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ sleep 3
Forwarding from 127.0.0.1:18087 -> 8080

$ curl -s -m 8 -H 'Authorization: Bearer …' 'http://127.0.0.1:18087/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     1.998s  se acabo el tiempo de espera

$ kubectl exec -n revisor lector -- sh -c 'curl -s -m 3 -o /dev/null -w "pods %{http_code}\n" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/revisor/pods'
pods 000
command terminated with exit code 28
[código de salida: 28]
```

Входната точка спря да пуска: клиентът отвън получава `000` и код 28. Политиката `cerrado` изолира входящия трафик на **всички** Pod-ове на пространството, включително `revisor`, а Pod-овете на Envoy (които живеят в друго пространство) останаха без право да му говорят. `port-forward`, напротив, **продължава да работи**: тунелът се отвори и `revisor` отговори. ([Ръководството за `port-forward`](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/) не описва по кой път пътува; казва нещо полезно за този урок: достъпът до `port-forward` се контролира от RBAC, с правото `create` върху `pods/portforward`, така че който го има, влиза в Pod-а, дори мрежата да е затворена.) Но онова, което `revisor` отговаря, вече не е пълният отчет: таблицата казва `prueba FALLA` с подробност `se acabo el tiempo de espera`, защото `revisor` не може да излезе, за да попита `prueba`. Изходящият трафик на самия `revisor` също е затворен. А `lector`, Pod-ът с валиден токен, вече не стига до API-то: `pods 000`, код 28. **Затворената мрежа предпазва API-то от онзи, който има право.** RBAC казва какво *можеш* да поискаш; мрежата казва докъде *стигаш*. И двете трябва да кажат да.

Основателно съмнение на този етап: ако всичко е затворено, не би ли трябвало да се провалят *probes*? Не се провалят. *Probes* ги изпълнява `kubelet` на възела (Урок 5), а документацията за мрежовите политики казва, че когато един Pod е изолиран за входящия трафик, „единствените разрешени връзки към Pod-а са тези, които идват от възела на Pod-а, и тези, които позволява списъкът `ingress` на някоя политика“. Трафикът на самия възел остава извън филтъра. Проверява се с шестте правила, 45 секунди по-късно, в 7.5.5.

#### 7.5.5 Необходимите отваряния

Сега другите пет политики, които заедно с `cerrado` образуват `red.yaml`. Прочети ги една по една, преди да ги приложиш; всяка има коментар, който казва на кого отваря и защо:

```yaml
# red.yaml — Lección 7: todo cerrado por defecto, y solo las aperturas necesarias.
# ⚠️ Que el clúster APLIQUE estas reglas depende de la red (CNI). kindnet, la red
# de kind desde la v0.24.0, sí las aplica: la Lección 7 lo mide con intruso y
# depurar. Con un CNI que no las aplique, estos objetos se guardan y no hacen nada.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cerrado
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
# Todos pueden preguntarle al DNS del clúster (si no, ningún nombre resuelve).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dns
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
---
# El revisor sale solo hacia prueba:9000.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-salida
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: prueba
    ports:
    - {protocol: TCP, port: 9000}
---
# prueba solo recibe del revisor.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: prueba-entrada
spec:
  podSelector:
    matchLabels:
      app: prueba
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 9000}
---
# Al revisor solo entran los Pods marcados «acceso-revisor: permitido» y los
# Envoy de la puerta (Lección 6), que viven en el espacio envoy-gateway-system.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: revisor-entrada
spec:
  podSelector:
    matchLabels:
      app: revisor
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels:
          acceso-revisor: permitido
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: envoy-gateway-system
    ports:
    - {protocol: TCP, port: 8080}
---
# …y esos mismos Pods pueden SALIR hacia el revisor:8080. Con «cerrado» también
# la salida está prohibida: abrir solo la entrada del revisor no basta (medido).
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: acceso-revisor-salida
spec:
  podSelector:
    matchLabels:
      acceso-revisor: permitido
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: revisor
    ports:
    - {protocol: TCP, port: 8080}
```

По ред:

- **`cerrado`**: тази отгоре. С `podSelector: {}` и двата типа оставя всички Pod-ове на пространството без вход и изход.
- **`dns`**: отваря **изхода** на всички Pod-ове към DNS. Целта се пише с двете условия заедно в един елемент (`namespaceSelector` **и** `podSelector`): Pod-овете с етикет `k8s-app: kube-dns` от пространството `kube-system`. Портовете са 53 върху UDP и върху TCP. Пространството се избира с етикета `kubernetes.io/metadata.name`, който клъстерът слага сам на всяко пространство, с неговото име; документацията предупреждава, че името на пространство не може да се пише директно в политика и че този етикет съществува именно за това.
- **`revisor-salida`**: **изходът** на `revisor` към Pod-овете с `app: prueba`, само към порт 9000. Това е единственото, което `revisor` иска от мрежата: да пита `prueba`.
- **`prueba-entrada`**: **входът** към `prueba`, само от Pod-овете `app: revisor` и само към 9000. Политиката за изход на `revisor` и тази за вход на `prueba` са две половини на една и съща врата: за да мине трафикът, и двете посоки трябва да кажат да.
- **`revisor-entrada`**: **входът** към `revisor`, на порт 8080, от два източника (два елемента на `from`, тоест единият **или** другият): Pod-овете с етикета `acceso-revisor: permitido` (от това пространство) и **всички Pod-ове** на пространството `envoy-gateway-system`, където живее входната точка от Урок 6.
- **`acceso-revisor-salida`**: **изходът** на Pod-овете с етикета `acceso-revisor: permitido` към `revisor`, порт 8080. Тя е двойката на предишната. Съществува заради един урок, който струва първата версия на тази мрежа: да отвориш само входа на `revisor` не стига, защото `cerrado` затваря и изхода на онзи, който иска да му говори.

Две бележки, преди да ги приложиш. Етикетът `acceso-revisor: permitido` служи като **ключ**: който го носи, може да говори с `revisor`, а слага го на един Pod онзи, който има право да създава Pod-ове в пространството. Затова етикетът не е тайна, а споразумение, и 7.5.8 го коментира. И политиките използват порт `8080`, този на контейнера, **не** 80 на Service-а. Това не е решение на този клъстер: [справочникът на API-то](https://kubernetes.io/docs/reference/kubernetes-api/policy-resources/network-policy-v1/) определя полето `port` на една политика като „числов или именуван порт на Pod“. Service-ът вече е избрал репликата и е превел порта, преди политиката да погледне пакета; политиката вижда крайната цел. Тук се измери, че kindnet го спазва (иначе `depurar` нямаше да стигне), а в друг клъстер си струва да се измери по същия начин, защото онова, което се проверява, е дали плъгинът прилага API-то, а не кой порт командва.

```text
$ kubectl apply -n revisor -f red.yaml
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns created
networkpolicy.networking.k8s.io/revisor-salida created
networkpolicy.networking.k8s.io/prueba-entrada created
networkpolicy.networking.k8s.io/revisor-entrada created
networkpolicy.networking.k8s.io/acceso-revisor-salida created

$ kubectl get networkpolicy -n revisor
NAME                    POD-SELECTOR               AGE
acceso-revisor-salida   acceso-revisor=permitido   8s
cerrado                 <none>                     50s
dns                     <none>                     8s
prueba-entrada          app=prueba                 8s
revisor-entrada         app=revisor                8s
revisor-salida          app=revisor                8s

$ kubectl describe networkpolicy revisor-entrada -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     app=revisor
  Allowing ingress traffic:
    To Port: 8080/TCP
    From:
      PodSelector: acceso-revisor=permitido
    From:
      NamespaceSelector: kubernetes.io/metadata.name=envoy-gateway-system
  Not affecting egress traffic
  Policy Types: Ingress

$ kubectl describe networkpolicy cerrado -n revisor | sed -n '/^Spec:/,$p'
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Allowing egress traffic:
    <none> (Selected pods are isolated for egress connectivity)
  Policy Types: Ingress, Egress
```

`cerrado` излезе `unchanged` (вече беше там), а другите пет `created`. `describe` на `revisor-entrada` го чете на разбираем език: „разрешава входящ трафик към порт 8080/TCP, от (PodSelector: `acceso-revisor=permitido`) и от (NamespaceSelector: `kubernetes.io/metadata.name=envoy-gateway-system`); без да засяга изхода; вид политика: Ingress“. Двете `From:` са двете алтернативи. А това на `cerrado` повтаря, с други думи, онова, което вече знаеше: „избраните Pod-ове: изолирани за вход и за изход“.

Сега пробата, със същите команди както винаги:

```text
$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec -n revisor depurar -- curl -s -m 3 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           9ms  200

$ kubectl exec -n revisor intruso -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://prueba:9000/
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -w '\n' https://kubernetes.default.svc/livez

command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor intruso -- nslookup revisor.revisor.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.revisor.svc.cluster.local
Address: 10.96.146.219

$ kubectl exec -n default intruso -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]
```

Шест резултата, по един за всеки въпрос:

- **`depurar` (с етикета) стига до `revisor`** и получава неговия `/salud`, а с токена получава пълния отчет: `prueba OK`. Това значи, че `revisor` отново може да излиза към `prueba` и че `prueba` го приема. Това са двете половини.
- **`intruso` (без етикета) не стига**: код 28. Отговорът на втория въпрос от 5:58 вече е „не“.
- **`depurar` не стига до `prueba:9000`**: код 28. Етикетът отваря пътя към `revisor`, не към тестовата услуга. Pod с ключа на `revisor` не е Pod с ключа на всичко.
- **`intruso` не стига до API-то**: `curl` изтича. Третият въпрос вече има стена преди RBAC.
- **DNS отговаря**: `intruso` разрешава `revisor.revisor.svc.cluster.local` до IP адреса на Service-а. Pod без ключ може да пита за имена (правилото `dns` е за всички) и получава отговор, но не може да се свърже с онова, което намира. Това, че DNS работи, не значи, че пътят е отворен.
- **`intruso` от `default` също не стига**: пълното име на Service-а вече не му върши работа.

И легитимните маршрути, които биха могли да се счупят:

```text
$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ kubectl port-forward -n revisor --address 127.0.0.1 service/revisor 18087:80 &

$ curl -s -m 5 http://127.0.0.1:18087/salud   # por port-forward
{"estado":"vivo","version":"1.6.0"}
```

Входната точка отговаря отново отвън, защото `revisor-entrada` допуска Pod-овете на `envoy-gateway-system`. И `port-forward` продължава да работи. Сега, с всички правила на място, изчакване от 45 секунди, колкото няколко оборота на *probes* от Урок 5, и поглед към Pod-овете:

```text
$ sleep 45

$ kubectl get pods -n revisor -l 'app in (revisor,prueba)'
NAME                       READY   STATUS    RESTARTS   AGE
prueba-6899c74865-rgh68    1/1     Running   0          7m15s
revisor-5d6fd4d6bd-6kb4k   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-jdmx8   1/1     Running   0          7m15s
revisor-5d6fd4d6bd-pj8r9   1/1     Running   0          7m15s
```

`RESTARTS 0` и при четирите, `1/1`. Затворената мрежа **не** събори *probes*, и причината е тази от документацията, която току-що прочете: изпълнява ги `kubelet`, от възела.

#### 7.5.6 За какво служи всяко правило: махаш едно, измерваш, връщаш го

Да прочетеш една политика казва какво *би трябвало* да прави. За да разбереш какво прави, я махаш от клъстера, **по една наведнъж**, и измерваш четири неща от едно и също място: `depurar` иска `/salud` от `revisor`; `depurar` иска отчета (който принуждава `revisor` да излезе към `prueba`); `depurar` разрешава името на `revisor`; и клиентът отвън иска `/salud` през входната точка. После `red.yaml` се прилага отново и се минава към следващата. `nslookup` в тази таблица се прави със `sh -c`, който отпечатва последния полезен ред, или `sin respuesta`, за да се побере в един ред.

```text
$ kubectl delete networkpolicy dns -n revisor
networkpolicy.networking.k8s.io "dns" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://revisor/salud
000
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- sh -c 'r=$(timeout 8 nslookup revisor.revisor.svc.cluster.local 2>&1 | grep -E "^Address: [0-9]|timed out" | tail -1); echo "${r:-sin respuesta}"'
;; connection timed out; no servers could be reached

$ curl -s -m 4 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/salud   # desde fuera del clúster
200
```

Това е първата: без `dns` името `revisor` не се разрешава, така че заявката към `/salud` и тази за отчета изтичат (код 28), а `nslookup` също. Входната точка, напротив, отговаря `200`: онова, което се измери, е, че Envoy стига до `revisor`, макар DNS да е затворен за Pod-овете на пространството; как Envoy намира репликите е работа на Envoy Gateway и курсът не го измери. Останалите четири се четат по същия начин. Пълната таблица:

| Махнато правило | `depurar` → `/salud` | `depurar` → отчет | Разрешаване на името | Отвън, `/salud` |
|---|---|---|---|---|
| `dns` | 28 (изтекло) | 28 | изтекло | 200 |
| `revisor-salida` | 200 | `prueba FALLA`, изтекло | отговаря | 200 |
| `prueba-entrada` | 200 | `prueba FALLA`, изтекло | отговаря | 200 |
| `revisor-entrada` | 28 | 28 | отговаря | **000** (28) |
| `acceso-revisor-salida` | 28 | 28 | отговаря | 200 |
| (всичките шест на място) | 200 | `prueba OK` | отговаря | 200 |

Всеки ред разказва нещо различно. Махането на `revisor-entrada` е единственото, което събаря входната точка, защото тя е правилото, което пропуска Envoy. Махането на `acceso-revisor-salida` оставя `depurar` без изход, но входната точка продължава (в този клъстер никой не е създавал политики в пространството на Envoy, така че изходът му не е затворен). Махането на `revisor-salida` или на `prueba-entrada` произвежда **същия симптом**, `prueba FALLA` по изтекло време, с различни причини: в единия случай `revisor` не може да излезе, в другия `prueba` не може да получи. А такъв симптом не казва коя от двете политики липсва. Това е видът повреда, за която служи `describe networkpolicy`.

Пълните блокове на петте проби, с командите им, са в `correr.salida.txt`. Ето участъка, който има история, този на `revisor-salida`. В едно предишно изпълнение, което не е запазено, този ред излезе `prueba OK` и без правилото. Не можа да се повтори (в това изпълнение излезе `FALLA` от първия път) и не знаем причината. Има две възможни обяснения и нито едно не е проверено. Първо: връзка, която вече е била отворена, е останала жива с махнатото правило; документацията за мрежовите политики оставя този случай на всеки плъгин („определя се от реализацията“ дали промяната влияе на съществуваща връзка) и препоръчва да не се променят политиките по начин, който я засяга. Второ: политиката още не е била програмирана, което е онова, което измерва 7.5.7. Затова скриптът чака, а тук освен това **рестартира `revisor`**, за да отвори пробата нова връзка:

```text
$ kubectl delete networkpolicy revisor-salida -n revisor
networkpolicy.networking.k8s.io "revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.001s  se acabo el tiempo de espera

$ kubectl rollout restart deployment/revisor -n revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor -n revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 0 out of 3 new replicas have been updated...
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

$ kubectl exec -n revisor depurar -- curl -s -m 4 -H 'Authorization: Bearer …' 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera
```

Двата отчета казват `prueba FALLA`: този отпреди рестартирането и този след него. В това изпълнение рестартирането не промени резултата (отчетът вече казваше `FALLA` преди); това е предпазна мярка на метода, не доказателство за причината.

Поуката е за метода и струва повече от таблицата. **Резултат, който казва „продължава да работи“ след махането на едно правило, не доказва, че правилото е било излишно.** Може да е стара връзка, кеш или проба, която не пита онова, което мислиш. Една мрежова проба трябва всеки път да отваря нова връзка.

### Грешката, която ще видиш (втората)

Втората грешка е онази, която най-много време губи с мрежовите политики. Прилича на сцената, но в малък мащаб: имаш политика, която **отваря** входа на `revisor`, имаш Pod с правилния етикет и Pod-ът не стига. Предизвиква се, като се изтрие последната политика, `acceso-revisor-salida`, която е двойката на входа:

```text
$ kubectl delete networkpolicy acceso-revisor-salida -n revisor
networkpolicy.networking.k8s.io "acceso-revisor-salida" deleted from revisor namespace

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl get networkpolicy -n revisor
NAME              POD-SELECTOR   AGE
cerrado           <none>         41s
dns               <none>         41s
prueba-entrada    app=prueba     41s
revisor-entrada   app=revisor    41s
revisor-salida    app=revisor    41s

$ kubectl get pod depurar -n revisor --show-labels
NAME      READY   STATUS    RESTARTS   AGE     LABELS
depurar   1/1     Running   0          7m38s   acceso-revisor=permitido,app=depurar
```

Чете се в този ред. **Първо, симптомът:** код 28, изтекло време; Pod-ът има етикета `acceso-revisor=permitido` и политиката `revisor-entrada` съществува. Всичко, което гледаш, казва, че би трябвало да минава. **Второ, списъкът с политики:** има `cerrado`, `dns`, `prueba-entrada`, `revisor-entrada` и `revisor-salida`; липсва `acceso-revisor-salida`. **Трето, принципът:** една политика за вход отваря едната страна на вратата. Pod-ът, който иска да стигне, е изолиран за **изход** от `cerrado` и нищо не му го отваря. Първата версия на тази мрежа, която отваряше само входа, остави `depurar` без възможност да излезе. **Поправката** е файлът, както винаги: `kubectl apply -k .` пресъздава липсващата и `depurar` отново стига.

```text
$ kubectl apply -k . | grep networkpolicy
networkpolicy.networking.k8s.io/acceso-revisor-salida created
networkpolicy.networking.k8s.io/cerrado unchanged
networkpolicy.networking.k8s.io/dns unchanged
networkpolicy.networking.k8s.io/prueba-entrada unchanged
networkpolicy.networking.k8s.io/revisor-entrada unchanged
networkpolicy.networking.k8s.io/revisor-salida unchanged

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

**Редът, когато един Pod не стига до друг с мрежови политики:**

1. `kubectl exec … curl -m 3`: какъв код? 28 е мрежово мълчание; 7 е, че няма никого; 4xx или 5xx е, че е стигнал.
2. `kubectl get networkpolicy -n <пространство>` в пространството на **двата** края.
3. За всеки край: кои политики го избират и за коя посока? Липсва изходът на онзи, който извиква, или входът на онзи, който получава.
4. Разрешава ли се името? Ако не, `dns`.
5. Етикетът върху Pod-а ли е, или е върху Deployment-а, но **не** в шаблона на Pod-а?

#### 7.5.7 Политиките не се прилагат мигновено

Дотук, всеки път когато скриптът променя политика, чака, преди да пита: това са `sleep 8`, които виждаш в изходите. Не са украса и този раздел разказва откъде идва осмицата. Изчакване от три секунди не стигна в едно от пробните изпълнения на този урок (изходът на онова изпълнение не е запазен): с вече поставени шестте политики `intruso` поиска `/livez` от API-то и получи `ok`, докато в останалите изпълнения същият въпрос изтичаше. Нищо не беше счупено: въпросът беше зададен **преди мрежата да е свършила да научава** новите политики. Измерено е нарочно. Скриптът повтаря шест пъти тази последователност: трие шестте политики, изчаква секунда, прилага ги отново и от този момент шест пъти пита API-то от `intruso`, с най-много една секунда за въпрос, като записва колко секунди са минали и какъв код е получен:

```text
$ for ciclo in 1 2 3 4 5 6; do   # borrar las seis, esperar 1 s, volver a aplicarlas y preguntar seis veces a la API desde el intruso
ciclo 1: +0s:200 +0s:200 +0s:200 +2s:000 +3s:000 +6s:000
ciclo 2: +2s:000 +3s:000 +5s:000 +6s:000 +7s:000 +9s:000
ciclo 3: +0s:200 +1s:200 +1s:200 +2s:000 +7s:000 +10s:000
ciclo 4: +5s:000 +6s:000 +9s:000 +12s:000 +17s:000 +20s:000
ciclo 5: +6s:000 +9s:000 +12s:000 +15s:000 +19s:000 +23s:000
ciclo 6: +3s:000 +6s:000 +9s:000 +12s:000 +13s:000 +15s:000
```

Чете се така: `+1s:200` е „една секунда след прилагането API-то отговори (200)“, а `000` е „не отговори“ (времето изтече). В цикли 1 и 3 първите въпроси получават отговор, а следващите вече не: последният отговор дойде между 0 и 1 секунда след `apply`, а първият въпрос без отговор — на 2-рата секунда (с най-много една секунда на въпрос и с онова, което добавя всеки `kubectl exec`, неточността на часовника е от този порядък). В цикли 2, 4, 5 и 6 първият въпрос излиза вече на 2, 5, 6 и 3 секунди, защото на тази натоварена машина всеки `kubectl exec` се стартираше по няколко секунди и вече намира мрежата затворена. В нито един цикъл не мина въпрос след първия без отговор. `kubectl apply` вече беше приключил и обектът `NetworkPolicy` вече съществуваше в API-то: липсваше мрежовият плъгин, на всеки възел, да го прочете и да го превърне в правила. Това преобразуване отнема секунди и междувременно Pod-ът остава отворен. С измереното тук прозорецът е най-много около 2 секунди (в едно предишно изпълнение, което не е запазено, се видяха до 3); осем секунди са избран запас, от две и половина до четири пъти повече, а не резултат. След осемте секунди на скрипта същият въпрос изтичаше и в това изпълнение нито едно от изчакванията от осем секунди не показа обратното:

```text
$ kubectl exec -n revisor intruso -- curl -s -m 3 -k -o /dev/null -w '%{http_code}\n' https://kubernetes.default.svc/livez
000
command terminated with exit code 28
[código de salida: 28]
```

Граници на това измерване: шест цикъла, натоварена машина, само един измерен ефект (че `cerrado` затваря изхода на `intruso`; шестте политики се прилагат заедно) и само посоката „затваряне“; посоката „отваряне“ (изтриване на политика, което правят `sleep 8` от 7.5.6) не е измерена. Три практически последствия, които оправдават цял раздел:

1. **Мрежова проба, направена твърде рано, дава фалшиво „да, стига“.** Това е същият дефект на метода от 7.5.6 в обратна посока. След като промениш политики, изчакай и измерявай повече от веднъж. Документацията за мрежовите политики не обещава скорост на прилагане: единственото, което казва, е, че ефектът върху съществуващи връзки се определя от реализацията. Времето, измерено тук, е от тази машина, с три възела на kind, натоварени с други клъстери, а не стойност на плъгина.
2. **Промяната на една политика е операция с прозорец.** Да изтриеш политиките и да ги приложиш отново (цикълът на този раздел или `kubectl delete -f red.yaml`, следван от `kubectl apply -f red.yaml`) оставя Pod-овете отворени за времето на прозореца, в клъстер, където политиките са единственото, което ги затваря. За да смениш политика в жив клъстер, новата се създава **преди** да махнеш старата; не се трие, за да се пресъздаде.
3. **Редът на създаване има значение.** Ако един Pod се роди, преди политиките, които го затварят, да са програмирани, се ражда отворен за малко. В 7.2.3 видя, че `kubectl apply -k` създаде шестте политики **след** Deployment-ите (редът в списъка `resources` не командва: Kustomize предава обектите в собствен ред), така че първите реплики на `revisor` са могли да се родят отворени за няколко секунди (това е извод от реда на редовете, не измерване на току-що роден Pod). В истински клъстер политиките на едно пространство се прилагат първи, изчаква се и след това идва проектът.

#### 7.5.8 От какво тази мрежа не защитава

Тази мрежа е по-добра от никаква мрежа и е добре да се каже точно колко по-добра.

- **Етикетът `acceso-revisor` го слага този, който създава Pod-а.** Всеки човек с право да създава Pod-ове в `revisor` може да си даде ключа сам. Политиката предпазва от Pod-ове, които **не** знаят, че етикетът съществува, не от онзи, който има достъп до пространството. Слоят, който пази това, е RBAC: в истински клъстер правото да се създават Pod-ове в `revisor` се дава със стиснати зъби. Упражнение 1 показва освен това, че етикетът не върши работа в погрешното пространство.
- **`revisor-entrada` се доверява на цялото пространство на входната точка.** Допуска **всички** Pod-ове на `envoy-gateway-system`. Ако това пространство приютява нещо друго, и то влиза. Политиката е толкова строга, колкото е онзи, който контролира това пространство.
- **Не криптира нищо.** Един упълномощен Pod говори чист HTTP с `revisor`. Мрежата казва кой може да стигне, а не че онова, което пътува, е защитено.
- **Pod-овете с `hostNetwork` и трафикът на възела.** Документацията казва, че поведението на политиките с Pod-ове в `hostNetwork` е недефинирано и че най-често плъгинът ги игнорира и третира трафика им като трафик на възела. А трафикът на възела към неговите Pod-ове (*probes*) не се блокира. `port-forward` също не го спира политиката, а ръководството за `port-forward` предупреждава, че може да заобиколи мрежовите контроли: него го пази RBAC (`create` върху `pods/portforward`). Затова нивото `restricted` от 7.3, което забранява `hostNetwork`, и мрежата се допълват.
- **Няма политика по подразбиране за целия клъстер.** Същата страница изброява като ограничение на API-то, че не могат да се прилагат политики по подразбиране към всички пространства или Pod-ове. `cerrado` трябва да се напише във всяко пространство, а ново пространство се ражда отворено.
- **Работи само защото плъгинът ги прилага.** В това изпълнение се измери, че kindnet ги прилага. В друг клъстер трябва да се измери по същия начин: клъстерът запазва политиките, без да се оплаква, дори никой да не ги изпълнява.


## Навикът за сигурност от урока: собствено пространство, ниво `restricted`, минимални права и мрежа, затворена по подразбиране

Таблицата с навици на курса възлага на този урок четири неща в един ред: собствено пространство, ниво `restricted`, минимални права, мрежа, затворена по подразбиране. Всяко се проверява с команда, а най-честната проверка е онази, която търси онова, което липсва, не онова, което е в повече. Инвентарът:

```text
$ kubectl get services -A | grep -E 'NAMESPACE|LoadBalancer'
NAMESPACE              NAME                             TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                            AGE
envoy-gateway-system   envoy-revisor-revisor-b269644b   LoadBalancer   10.96.221.218   172.27.255.200   80:31159/TCP                                       13m

$ kubectl apply -k . 2>&1 | grep -c -i warning || true
0

$ kubectl get pods -n revisor -o custom-columns='POD:.metadata.name,CUENTA:.spec.serviceAccountName,AUTOMOUNT:.spec.automountServiceAccountToken'
POD                       CUENTA       AUTOMOUNT
depurar                   default      false
intruso                   default      false
lector                    observador   true
prueba-6899c74865-rgh68   prueba       false
revisor-d86b5794d-5fspg   revisor      false
revisor-d86b5794d-hx92n   revisor      false
revisor-d86b5794d-tmq5g   revisor      false
```

Чети го като четири въпроса. **Какво е публикувано навън?** Един-единствен Service от тип `LoadBalancer` в целия клъстер: този на Envoy, в `envoy-gateway-system`, с IP адреса, който му е дал MetalLB. `revisor-publico` от Урок 6 вече не съществува, а единствената входна точка е именуваната. **Проектът отговаря ли на нивото, което изисква пространството му?** Повторното прилагане на `kustomization` не произвежда нито едно предупреждение (`0` реда с `warning`), а пробата с `--dry-run=server` на крайното състояние (в „Как разбирам, че съм успял“) казва `not labeled`. **Кой има удостоверения?** Само `lector`, Pod-ът от упражнението в 7.4.4, който ги поиска нарочно (`AUTOMOUNT true`); `revisor`, `prueba`, `depurar` и `intruso` казват `false`. **Затворена ли е мрежата?** Шест политики в `revisor` и 7.5 измери какво отваря всяка.

Защо са навици за **сигурност**, а не само за ред? Защото всеки слой затваря конкретен път, който е бил измерен като отворен. Едно пространство с `restricted` спира екипа по данни (или твоето собствено недоглеждане), преди да съществува Pod с повече привилегии от нужното. Акаунт без права и без токен оставя компрометиран контейнер без нищо, което да представи пред API-то (`intruso` от 7.4.4 нямаше дори един файл). А затворената мрежа превръща „всеки Pod говори с всеки Pod“ в къс списък, който може да се чете, преглежда и обсъжда, което е най-ценната промяна на урока: повърхността премина от неявна към записана.

**От какво защитава и от какво не.** Това го измери урокът, едно по едно:

| Слой | От какво защитава | От какво не защитава |
|---|---|---|
| Пространство от имена | сблъсъци на имена; обхват на правата | трафик между Pod-ове (7.5.3: достигнаха се между пространства) |
| Pod Security `restricted` | създаване на Pod-ове с привилегии, `root`, `hostNetwork` | Pod-ове, които вече са работели (7.3.4); някой с право да смени етикета на пространството |
| Акаунт без токен и без права | кражба на удостоверения от Pod, който не се нуждае от тях | Pod, който се нуждае от тях и е компрометиран (`lector`: стига до онова, до което стига неговата `Role`) |
| Затворена мрежа | странично движение между Pod-ове; достъп до API-то от Pod-ове без ключ | онзи, който може да сложи етикета; трафика на възела; съдържанието на онова, което пътува (чист HTTP) |

И пълната картина, за да не се чете това като рецепта за продукция: липсват криптирането при пренос, таван на ресурсите на пространство (`ResourceQuota`, `LimitRange`), криптирането на Secret-ите в клъстера, одитът на `kube-apiserver` и управлението на това кой има право да пипа това пространство. Урок 10 събира списъка с онова, което липсва на целия проект, за да работи истински.

## Какво се прави погрешно

**Да вярваш, че пространството от имена изолира мрежата.** Изглежда така, защото табелките са навсякъде. 7.5.3 го измери: Pod от `default` достигна Service-а на `revisor`, като написа пълното му име.

**Да приложиш мрежова политика и да не провериш дали плъгинът я изпълнява.** Клъстерът запазва обекта, без да се оплаква, а трафикът остава същият. Проверява се с Pod без ключ, който трябва да се провали, не с четене на манифеста.

**Да затвориш входа и да забравиш изхода.** `cerrado` изолира двете посоки, а отварянето само на входа на целта оставя викащия без възможност да излезе. Това са две половини на едно-единствено разрешение. Това е втората грешка на урока.

**Да затвориш изхода и да забравиш DNS.** Без правилото `dns` имената не се разрешават и симптомът изглежда, че „мрежата е счупена“, когато липсват само заявките за имена.

**Да заключиш от едно „продължава да работи“.** Връзка, която вече е отворена, може да преживее смяната на политика, а документацията го оставя на решението на всеки плъгин. Една мрежова проба всеки път отваря нова връзка.

**Да поставиш `enforce` и да вярваш, че пространството е останало чисто.** Етикетът отхвърля онова, което пристигне, не изгонва онова, което вече работи. А старият Pod, който нарушава нивото, умира от един rollout: в деня, в който го пресъздадеш, вече не се ражда.

**Да оставиш `enforce` без версия.** `restricted:latest` се променя, когато клъстерът се актуализира. Фиксирай версията (`enforce-version`) и вдигай я нарочно.

**Да гледаш само режима `enforce`.** Deployment, който нарушава политиката, **се създава**, с предупреждение, което почти никой не чете, и остава без Pod-ове. Предупрежденията на режима `warn` се четат или се пренасочват към журнал, който някой преглежда.

**Да даваш права със заместващи знаци (`*`).** Документацията за RBAC предупреждава: заместващ знак в ресурси или глаголи дава и онова, което някой ден добави клъстерът. Назовава се всеки ресурс и всеки глагол.

**Да оставиш монтиран токена на акаунт, който не го ползва.** Това е удостоверение във всяка реплика, без никаква полза. `automountServiceAccountToken: false`, в акаунта или в Pod-а.

**Да даваш етикета `acceso-revisor` на кой да е Pod, „за да работи“.** Всеки Pod с ключа е още един Pod, който може да говори с `revisor`. Ключът се дава на онзи, който го ползва, и се пита защо.

**Да се доверяваш на цяло пространство от имена като източник.** `revisor-entrada` приема всички Pod-ове на `envoy-gateway-system`. Това е разумно решение, докато това пространство е само на платформата, и престава да бъде такова в деня, в който там живее нещо друго.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред и от състоянието, в което е останал след 7.5. Преди всяко `ctx` трябва да пропуска веригата. `correr.sh` ги изпълнява по същия начин, а изходът му е в `correr.salida.txt`. **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще стане. Четвъртото се пише със свои думи.

### Упражнение 1 — Правилният етикет в погрешното пространство

Приложи `depurar.yaml` в пространството `default`, с `ctx && kubectl apply -n default -f depurar.yaml`. Това е същият манифест, със същия етикет `acceso-revisor: permitido`. Преди да погледнеш, предскажи: може ли този Pod да говори с `revisor` с пълното име, `http://revisor.revisor.svc.cluster.local/salud`? А `depurar` от пространството `revisor`? Обясни разликата с думите на 7.5.5: какво избира политиката `revisor-entrada` и от **кое пространство**? Накрая изтрий Pod-а от `default`.

### Упражнение 2 — Акаунт, който само рестартира `revisor`

`fig07_03.reiniciador.yaml` създава акаунт, `Role` и `RoleBinding`:

```yaml
# fig07_03.reiniciador.yaml — Ejercicio 2: una cuenta que puede reiniciar el
# revisor y NADA más. rollout restart necesita leer el Deployment (get) y
# cambiarle una anotación (patch); resourceNames lo limita a UN Deployment.
# Se aplica con: kubectl apply -n revisor -f fig07_03.reiniciador.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: reiniciador
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: reiniciador
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["revisor"]
  verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: reiniciador
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: reiniciador
subjects:
- kind: ServiceAccount
  name: reiniciador
  namespace: revisor
```

`kubectl rollout restart` трябва да прочете Deployment-а (`get`) и да му промени една анотация (`patch`). Приложи го с `ctx && kubectl apply -n revisor -f fig07_03.reiniciador.yaml` и предскажи, преди да изпълниш каквото и да било: може ли акаунтът да рестартира `revisor`? А `prueba`? Може ли да **изброи** Deployment-ите? Провери трите си предположения с `kubectl auth can-i … --as=system:serviceaccount:revisor:reiniciador` и после с истински `kubectl rollout restart`. Защо `can-i list deployments` отговаря различно от `can-i patch deployment/revisor`? Накрая изтрий онова, което си създал, с `ctx && kubectl delete -n revisor -f fig07_03.reiniciador.yaml`.

### Упражнение 3 — Маршрут, който идва от друго пространство (проект)

Входната точка живее в `revisor`. Друг екип, в `default`, иска да публикува собствен маршрут през същата входна точка. `fig07_05.ruta-ajena.yaml` е неговият `HTTPRoute`:

```yaml
# fig07_05.ruta-ajena.yaml — Ejercicio 3: una HTTPRoute que vive en el espacio
# «default» y pide colgarse del Gateway «revisor», que vive en «revisor».
# Pregunta: ¿la acepta el Gateway? ¿Qué dice su estado? Se aplica con:
#   kubectl apply -n default -f fig07_05.ruta-ajena.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ajena
spec:
  parentRefs:
  - name: revisor
    namespace: revisor
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /ajena
    backendRefs:
    - name: revisor
      namespace: revisor
      port: 80
```

Преди да започнеш, две различни разрешения, които е добре да не се бъркат. `allowedRoutes`, в `listeners` на `Gateway`, казва **кой може да се закачи за входната точка**: по подразбиране (`from: Same`) само маршрутите от същото пространство като `Gateway`; `All` и `Selector` отварят входната точка за други пространства. `ReferenceGrant` живее в пространството на **целта** и казва **кой може да сочи към неговите Service-и**: маршрут от друго пространство не може да използва като цел Service на `revisor`, ако собственикът на това пространство не го позволи. Първото го дава собственикът на входната точка; второто — собственикът на Service-а. Справочните страници: [`ReferenceGrant`](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/), [справочникът на API-то](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) и [ръководството за маршрути между пространства](https://gateway-api.sigs.k8s.io/guides/multiple-ns/).

Приложи го в `default`. Прочети състоянието му с `kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'`. В това състояние има **два** различни проблема. Преди да погледнеш своето, предскажи кои са, от кой обект зависи всеки и кой трябва да даде всяко разрешение: собственикът на входната точка, собственикът на Service-а или екипът, който пише маршрута? Поправи първо онзи, който идва от входната точка (подсказка: `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces`) и после другия с `fig07_06.referencegrant.yaml`:

```yaml
# fig07_06.referencegrant.yaml — Ejercicio 3: el permiso que da el DUEÑO del Service.
# Vive en el espacio «revisor» (el del Service destino) y dice: las HTTPRoute del
# espacio «default» pueden usar como destino los Service de este espacio.
# Se aplica con: kubectl apply -n revisor -f fig07_06.referencegrant.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: rutas-de-default
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: default
  to:
  - group: ""
    kind: Service
    name: revisor
```

Провери накрая, че `GET /ajena` през входната точка стига до `revisor` (отговорът е `404` от `revisor`, не от входната точка: как го доказваш с журнала му?), и върни всичко, което си променил, включително `Gateway`.

### Упражнение 4 — Защити дизайна

В най-много пет изречения отговори: (1) защо този урок не инсталира Calico и какво го подкрепя? (2) Какво би станало с *probes*, ако `kindnet` прилагаше политиките, но трафикът на възела също се блокираше? (3) Коя политика от шестте би променил, ако екипът по данни се нуждаеше от **собствена** услуга в пространството `revisor`, която също получава трафик от входната точка? (4) Какво липсва, за да бъде `acceso-revisor: permitido` защита, а не само споразумение? (5) Политиката `dns` отваря изхода към Pod-овете `k8s-app: kube-dns` на `kube-system`; какво би станало с разрешаването на имена, ако CoreDNS се премести в друго пространство?

## Решения

### Решение 1

Измерено в `correr.salida.txt`:

```text
$ kubectl apply -n default -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -n default --show-labels
NAME      READY   STATUS    RESTARTS   AGE   LABELS
depurar   1/1     Running   0          6s    acceso-revisor=permitido,app=depurar

$ kubectl exec -n default depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
command terminated with exit code 28
[código de salida: 28]

$ kubectl exec -n revisor depurar -- curl -s -m 3 http://revisor.revisor.svc.cluster.local/salud
{"estado":"vivo","version":"1.6.0"}
```

Pod-ът от `default` има етикета и въпреки това **код 28**. `depurar` от `revisor` отговаря. Политиката `revisor-entrada` не избира просто „Pod-овете с етикета“: в списъка `from` `podSelector` без `namespaceSelector` се отнася за Pod-овете **на пространството, където живее политиката**, тоест `revisor`. Етикетът в друго пространство не се брои. Вторият елемент на списъка (`namespaceSelector`), напротив, избира цели пространства и затова Envoy влиза. За да влезе Pod-ът от `default`, би трябвало да се добави елемент с `namespaceSelector` и `podSelector` **заедно**: Pod-овете с този етикет от това пространство. Обърни внимание и че дългото име се разреши (правилото `dns` е отворено за всички); провалила се е връзката.

### Решение 2

Измерено в `correr.salida.txt`:

```text
$ kubectl apply -n revisor -f fig07_03.reiniciador.yaml
serviceaccount/reiniciador created
role.rbac.authorization.k8s.io/reiniciador created
rolebinding.rbac.authorization.k8s.io/reiniciador created

$ kubectl auth can-i patch deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
yes

$ kubectl auth can-i patch deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl auth can-i list deployments -n revisor --as=system:serviceaccount:revisor:reiniciador
no
[código de salida: 1]

$ kubectl rollout restart deployment/revisor -n revisor --as=system:serviceaccount:revisor:reiniciador
deployment.apps/revisor restarted

$ kubectl rollout restart deployment/prueba -n revisor --as=system:serviceaccount:revisor:reiniciador
Error from server (Forbidden): deployments.apps "prueba" is forbidden: User "system:serviceaccount:revisor:reiniciador" cannot get resource "deployments" in API group "apps" in the namespace "revisor"
[código de salida: 1]
```

`patch` върху `deployment/revisor` отговаря `yes`, върху `prueba` — `no`: `Role` назовава Deployment-а с `resourceNames: ["revisor"]`. Рестартирането на `revisor` работи (`restarted`), а това на `prueba` дава `Forbidden`, който казва `cannot get resource "deployments"`: `rollout restart` започва с четене на Deployment-а и това четене вече е забранено. `list deployments` отговаря `no` по най-простата причина: `Role` дава само `get` и `patch`, а `list` е друг глагол. Това, че `get` е ограничен до едно име, не превръща `get` в `list`: да прочетеш един по име и да изброиш са отделни права (видя го в 7.4.3 със Secret-ите). И дори `Role` да добавеше `list`, документацията за RBAC предупреждава, че ограничаването на `list` или `watch` с `resourceNames` принуждава клиента да изпрати `--field-selector=metadata.name=revisor`: един гол `kubectl get deployments` пак би дал `no`. Този акаунт може да рестартира една услуга и не може да вижда останалите. Това е минималното право, което описва урокът, и е примерът защо се пише `resourceNames`, вместо да се дава `patch` върху всички Deployment-и.

### Решение 3

Измерено в `correr.salida.txt`:

```text
$ kubectl get gateway revisor -n revisor -o jsonpath='{.spec.listeners[0].allowedRoutes}{"\n"}'
{"namespaces":{"from":"Same"}}

$ kubectl apply -n default -f fig07_05.ruta-ajena.yaml
httproute.gateway.networking.k8s.io/ajena created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=False NotAllowedByListeners: No listeners included by this parent ref allowed this attachment.
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

`Gateway` казва `{"namespaces":{"from":"Same"}}`: **само маршрути от собственото му пространство**. Не си го писал ти; това е стойността по подразбиране на типа (`kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` казва „ограничено до пространството на този Gateway по подразбиране“). А маршрутът от `default` излиза с две условия в лъжа, от два различни механизма:

- **`Accepted=False NotAllowedByListeners`**: *слушателят* (`listener`) на Gateway-а не допуска маршрути от `default`. Решава го собственикът на входната точка, с `allowedRoutes`, **в Gateway-а**.
- **`ResolvedRefs=False RefNotPermitted`**: маршрутът сочи към Service от друго пространство, `revisor/revisor`, и никой `ReferenceGrant` не го позволява. Решава го собственикът на **целта**, с обект в **неговото** пространство.

Състоянието на маршрута го обобщава в два реда: преминаването между пространства при **закачане** за Gateway го управлява Gateway-ът; преминаването между пространства при **сочене** към Service го управлява онзи, който е собственик на Service-а (`kubectl explain referencegrant.spec` го описва като пространствата и типовете, на които се вярва, които могат да реферират ресурсите от `to`). Това са две разрешения с двама собственици и състоянието ги разделя: `Accepted` отговаря на слушателя на Gateway-а (`allowedRoutes`), а `ResolvedRefs` отговаря на `ReferenceGrant`. Един `ReferenceGrant` говори за това към какво **може да сочи** един маршрут; дали един маршрут може да се **закачи** за чужд Gateway е въпрос на `allowedRoutes`. Първото се поправя, като се сложи етикет на пространството на маршрута и се каже на слушателя да приема пространствата с този етикет:

```text
$ kubectl label namespace default acceso-puerta=permitido
namespace/default labeled

$ kubectl patch gateway revisor -n revisor --type=json -p '[{"op":"add","path":"/spec/listeners/0/allowedRoutes","value":{"namespaces":{"from":"Selector","selector":{"matchLabels":{"acceso-puerta":"permitido"}}}}}]'
gateway.gateway.networking.k8s.io/revisor patched

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=False RefNotPermitted: Failed to process route rule 0 backendRef 0: Backend ref to Service revisor/revisor not permitted by any ReferenceGrant.
```

`Accepted` стана `True`; `ResolvedRefs` остава в `RefNotPermitted`: първото разрешение не поправя второто. Разрешението на целта е `ReferenceGrant`, който живее в пространството на Service-а (`revisor`) и назовава от кого приема препратки:

```text
$ kubectl apply -n revisor -f fig07_06.referencegrant.yaml
referencegrant.gateway.networking.k8s.io/rutas-de-default created

$ kubectl get httproute ajena -n default -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
Accepted=True Accepted: Route is accepted
ResolvedRefs=True ResolvedRefs: Resolved all the Object references for the Route
```

И двете условия в истина. И доказателството, че маршрутът стига до `revisor`:

```text
$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/ajena   # desde fuera del clúster
404

$ kubectl logs -n revisor -l app=revisor --tail=-1 | grep -E 'GET /ajena'
revisor: GET /ajena 404 0s
```

Клиентът отвън получава `404`. Този `404` **не е от входната точка**: журналът на `revisor` има реда `GET /ajena 404`, тоест заявката е стигнала до реплика на `revisor`, която не познава този маршрут. (Ако входната точка не беше намерила маршрут, `404` нямаше да се появи в журнала на `revisor`.) Мрежовата политика не пречи, защото целта е самият `revisor`, а `revisor-entrada` вече допуска Pod-овете на Envoy: двата слоя, този на маршрутите и този на мрежата, казаха да. Те са различни слоеве и и двата трябва да го кажат. Това `Same` е стойността по подразбиране, която документира [справочникът на API-то на Gateway API](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/) за `allowedRoutes.namespaces.from`, а клъстерът я потвърди с първата команда; [ръководството за маршрути между пространства](https://gateway-api.sigs.k8s.io/guides/multiple-ns/) обяснява как да се отвори със `Selector` или `All`.

Скриптът връща всичко: трие маршрута, `ReferenceGrant`, етикета на `default` и полето `allowedRoutes`, което добави към `Gateway`; `kubectl diff -k .` на крайното състояние потвърждава, че клъстерът се е върнал към онова, което казват файловете.

### Решение 4

Възможен отговор: „(1) Защото kindnet приложи политиките: само с `cerrado`, `intruso` и Pod-ът с етикета спряха да стигат (код 28), а с шестте се отвори единствено онова, което те казваха; това е измерването, което планът на курса остави висящо. (2) *Probes* биха се провалили: `kubelet` ги изпълнява от възела и те биха били блокирани, *probe*-ът за готовност би извадил всички реплики от списъка, а този за жизненост би ги рестартирал; документацията казва, че трафикът на възела е позволен, а този урок измери `RESTARTS 0`. (3) Нито една от шестте: би се добавила нова политика, `entrada` за тази услуга, със същия `namespaceSelector` на входната точка; политиките се сумират и чуждите не се редактират. (4) Да не може онзи, който може да създава Pod-ове в `revisor`, да си сложи етикета: RBAC, който ограничава кой създава или променя Pod-ове в пространството, или политика за допускане, която валидира етикета. (5) Изходът към DNS би престанал да съвпада с новите Pod-ове на DNS и имената биха престанали да се разрешават, със същия симптом като махането на правилото `dns` в 7.5.6: `nslookup` изтича и `curl` по име се проваля с 28, докато входната точка продължава да отговаря, както в онзи ред на таблицата.“

## Изтриване на клъстера

Когато приключиш упражненията, изтрий клъстера на урока. Не оставяй нищо живо на машината:

```text
$ kind delete cluster --name curso-k8s-l7
Deleting cluster "curso-k8s-l7" ...
Deleted nodes: ["curso-k8s-l7-worker2" "curso-k8s-l7-worker" "curso-k8s-l7-control-plane"]

$ kind get clusters | grep -c curso-k8s-l7
0

# disco de Docker: 77% usado
# la corrida completa tardó 1569 s
```

(Редът в скоби го пише скриптът, който измерва изтриването.) `--name` е задължително: без него kind би изтрил клъстера на име `kind`, който може да е на някой друг.

На твоята машина остават временната папка на `kubeconfig` и `token.txt` (този от `punto-de-partida/` го изтри в 7.2.3; `rm` по-долу го включва, в случай че не си го направил). Изтриват се така, от `programas/07-aislar-permisos-red`:

```bash
# Los tokens de la lección: son de mentira, pero un token suelto no se deja.
rm -f -- token.txt punto-de-partida/token.txt
# La carpeta temporal, y SOLO si es la que creó mktemp en 7.1.1.
case "$L7_TMP" in
  /tmp/curso-k8s-l7.?*) rm -rf -- "$L7_TMP" ;;
  *) echo "No borro «$L7_TMP»: no es la carpeta de esta lección" ;;
esac
unset KUBECONFIG L7_TMP
unset -f ctx
```

`case` пропуска само път, който започва с `/tmp/curso-k8s-l7.` и има нещо след него, точната форма на онази, която създаде в 7.1.1. Ако `L7_TMP` е празна (защото си в друг терминал, където никога не си я дефинирал) или има друга стойност, не трие нищо и ти казва защо. Това е същата защита, която използва `correr.sh` при почистването. Последният ред маха функцията `ctx` от твоя терминал.

Ако на тази машина си изпълнил урока със собствена мрежа на Docker (променливата `CURSO_RED` на `correr.sh`), и тази мрежа е твоя и я трие ти, **след** клъстера и само ако си я създал ти за това: `docker network rm curso-k8s-red-l7`. С обичайната мрежа `kind` няма какво да се трие: тя е на всичките ти клъстери. Клъстерът на следващия урок се създава от нулата, както този.

## Как разбирам, че съм успял

Преди квадратчетата — крайното състояние така, както го остави изпълнението, копирано от `correr.salida.txt`. Първо се трият Pod-овете на упражненията и се пита клъстерът дали нещо се различава от файловете на проекта, а после се гледа входната точка отвън и се повтаря пробата от 7.3:

```text
$ kubectl delete -n revisor pod depurar intruso lector --wait=false
pod "depurar" deleted from revisor namespace
pod "intruso" deleted from revisor namespace
pod "lector" deleted from revisor namespace

$ kubectl delete -n default pod intruso --wait=false
pod "intruso" deleted from default namespace

$ kubectl diff -k . >/dev/null && echo 'sin diferencias con los archivos'
sin diferencias con los archivos

$ curl -s -m 5 http://172.27.255.200/salud   # desde fuera del clúster
{"estado":"vivo","version":"1.6.0"}

$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://172.27.255.200/api/estados   # desde fuera del clúster
401

$ kubectl label --dry-run=server --overwrite namespace revisor pod-security.kubernetes.io/enforce=restricted
namespace/revisor not labeled (server dry run)
```

Чете се така. `sin diferencias con los archivos` значи, че упражненията са били върнати: клъстерът е точно онова, което казват файловете. `401` е `revisor` зад входната си точка: входната точка отговаря, но `/api/estados` иска токена, а отвън не го носиш. А `not labeled (server dry run)` без предупреждения затваря 7.3: да поискаш отново нивото `restricted` за `revisor` не променя нищо, защото вече го има, и никой съществуващ Pod не го нарушава.

- [ ] Казваш, с една команда, какво **не** изолира едно пространство от имена: Pod от `default` достига `revisor.revisor.svc.cluster.local`, ако няма политики.
- [ ] Пред Deployment с `READY 0/1` и без Pod-ове отиваш при ReplicaSet и намираш `FailedCreate … violates PodSecurity`; и знаеш защо `apply` не се провали.
- [ ] Четеш отказ на `restricted` и назоваваш четирите правила и реда на `securityContext`, който поправя всяко.
- [ ] Пишеш `Role` и `RoleBinding` без заместващи знаци и изпробваш позволеното и отказаното с `kubectl auth can-i … --as=…`, с истинска заявка и от Pod.
- [ ] Обясняваш защо `revisor` няма монтиран токен, а `lector` има, и до какво стига `lector` със своя.
- [ ] Различаваш `exit code 28` (мрежово мълчание), `7` (никой не слуша) и `403` (стигна и му беше отказано).
- [ ] Казваш, за всяка от шестте политики, какво се чупи, ако липсва, и защо `revisor-salida` и `prueba-entrada` произвеждат същия симптом.
- [ ] Изпълняваш `programas/07-aislar-permisos-red/correr.sh > /tmp/mi-corrida-l7.txt 2>&1` и сравняваш `/tmp/mi-corrida-l7.txt` с `programas/07-aislar-permisos-red/correr.salida.txt` (не пренасочвай към този файл: той е справката) по онова, което не се променя между изпълненията: три възела `Ready` (версията на възела я фиксира `kind-curso.yaml` чрез отпечатъка ѝ); `-rw-------` в двата `token.txt`; седемте етикета на пространството `revisor` с `restricted` и `v1.37`; `default` само със Service-а `kubernetes`; отказът `violates PodSecurity "restricted:v1.37"` с неговите четири правила; `baseline:latest` отхвърля `hostNetwork` и приема простия Pod; `namespace/revisor not labeled (server dry run)`; ReplicaFailure на `sinreglas`; при `can-i`, `no` за `revisor`, `yes` за четене на Pod-ове и журнали с `observador` и `no` за триене, за четене на Secret-и и за четене в `default`; `pods 200`, `secrets 403`, `pods-default 403` и липсващата директория при `intruso`; без правила пробите отговарят; с `cerrado` дават 28 и `000` отвън; с шестте `depurar` стига, а `intruso` не; и петте реда на таблицата от 7.5.6. IP адресите, наставките на имената, възрастите, името на Secret-а, милисекундите и времената на стартиране се променят във всяко изпълнение: наблюдават се, не се сравняват.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l7`.

## Обобщение

Отговори, без да гледаш урока:

1. Кои две неща изолира едно пространство от имена и кое не? Какво измери 7.5.3, за да го докаже?
2. Кои са трите режима и трите нива на Pod Security Admission и как се пишат в пространството?
3. Защо Deployment, който нарушава `restricted`, се създава и остава без Pod-ове? Къде е причината?
4. Какво добавя една `Role` и какво добавя един `RoleBinding`? Какво значи, че правата са адитивни?
5. Какво прави `kubectl auth can-i … --as=system:serviceaccount:ПРОСТРАНСТВО:АКАУНТ` и какъв изходен код връща при `no`?
6. Защо `revisor` декларира `automountServiceAccountToken: false` и какво се измерва с `lector`, който го има на `true`?
7. Кога е изолиран един Pod за входящия трафик? Какво става, ако две политики го избират?
8. Какво условие е нужно на една `NetworkPolicy`, за да има ефект, и как се провери в kind?
9. Какво значат `exit code 28`, `exit code 7` и `403`?
10. Защо съществува `acceso-revisor-salida`? А защо `dns`?
11. Какво покрива `allowedRoutes` и какво покрива `ReferenceGrant`?

## Източници

Всички прегледани на 21 октомври 2026 г.

- [Kubernetes, „Namespaces“](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/): пространствата като механизъм за изолиране на групи ресурси, уникални имена в рамките на пространство, обекти с пространство и без него, пространството `kube-system` и автоматичният етикет `kubernetes.io/metadata.name`.
- [Kubernetes, „Pod Security Admission“](https://kubernetes.io/docs/concepts/security/pod-security-admission/): трите режима (`enforce`, `audit`, `warn`), трите нива, синтаксисът на етикетите с версия и без нея, и че `enforce` се прилага към Pod-овете, не към натоварванията.
- [Kubernetes, „Pod Security Standards“](https://kubernetes.io/docs/concepts/security/pod-security-standards/): определенията на `privileged`, `baseline` и `restricted`.
- [Kubernetes, „Enforce Pod Security Standards with Namespace Labels“](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/): как се слагат етикетите на ново и на съществуващо пространство, `--dry-run=server` и че при добавяне на `enforce` контролерът проверява съществуващите Pod-ове и връща предупреждения.
- [Kubernetes, „Service Accounts“](https://kubernetes.io/docs/concepts/security/service-accounts/): какво е сервизен акаунт, акаунтът `default` на всяко пространство, автоматичното монтиране на удостоверения и краткотрайните токени от 1.22.
- [Kubernetes, „Configure Service Accounts for Pods“](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/): как се изключва монтирането в акаунта и в Pod-а и че Pod-ът има предимство.
- [Kubernetes, „Using RBAC Authorization“](https://kubernetes.io/docs/reference/access-authn-authz/rbac/): `Role` и `ClusterRole`, `RoleBinding`, че правата са чисто адитивни, ролите по подразбиране (`system:basic-user`, `system:discovery`), рискът от заместващите знаци и ограниченията с `resourceNames`.
- [Kubernetes, „Network Policies“](https://kubernetes.io/docs/concepts/services-networking/network-policies/): моделът на изолация (неизолиран, докато политика не избере Pod-а, и адитивни политики), изискването за плъгин, който ги прилага, трафикът на възела, `hostNetwork`, ограниченията на API-то и въздействието върху съществуващи връзки.
- [Kubernetes, „Use Port Forwarding to Access Applications in a Cluster“](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/): че `port-forward` се разрешава от RBAC с `create` върху `pods/portforward`.
- [kind, „Configuration“](https://kind.sigs.k8s.io/docs/user/configuration/): мрежовият плъгин по подразбиране (`kindnetd`) и как се изключва.
- [kind, бележки към изданието v0.24.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.24.0): поддръжката на мрежови политики с `sigs.k8s.io/kube-network-policies`.
- [Gateway API, „Cross-Namespace routing“](https://gateway-api.sigs.k8s.io/guides/multiple-ns/): маршрути, които се закачат за Gateway от друго пространство с `allowedRoutes`.
- [Gateway API, „ReferenceGrant“](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/): разрешението на пространството на целта, за да може един маршрут да сочи към неговия Service; полетата `from` и `to` и че разрешава само препратки към ресурси от собственото му пространство.
- [Gateway API, справочник на API-то (spec)](https://gateway-api.sigs.k8s.io/reference/api-spec/main/spec/): `RouteNamespaces` и стойността му по подразбиране, `from: Same`. Същото беше прочетено и в самия клъстер с `kubectl explain gateway.spec.listeners.allowedRoutes.namespaces` и `kubectl explain referencegrant.spec`, а състоянието `RefNotPermitted` на маршрута го потвърждава.
- [CyberScoop, „Tesla falls victim to cryptomining scheme, minor breach“](https://cyberscoop.com/tesla-cryptomining-redlock-cloud-breach/) (20 февруари 2018 г.): случаят, с който започва урокът, въз основа на доклада на RedLock.

---

**Следващ:** [Урок 8 — Данни и задачи](08-datos-y-tareas.md)
