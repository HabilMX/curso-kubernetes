# Урок 4 — Конфигурация и тайни

Сряда, 6:40 следобед. Утре в 8 започва прегледът на сигурността на проекта и на теб се пада да подготвиш хранилището. Отваряш историята и го виждаш: преди три седмици някой е добавил токена на `revisor` в манифеста на Deployment, на ред `REVISOR_TOKEN`, „само за проба“. В днешната версия вече го няма, но остава в историята на Git, където може да го прочете всеки, който е клонирал хранилището. Докато мислиш за това, пристига още едно съобщение: екипът по плащанията иска `revisor` да наблюдава и тяхната услуга, а за да я добавиш към списъка, трябва да редактираш същия Deployment: не е нужно образът да се изгражда наново, но трябва отново да пипнеш файла, в който е живял токенът. Някой предлага първото да се реши със Secret, „който вече идва в base64, значи е защитен“. Часът е 6:55 и имаш два проблема, които изглеждат като един.

Не са един. Първият е **къде живеят данни, които не бива да се виждат**; вторият е **как променяш конфигурацията на една услуга, без да пипаш рецептата ѝ**. Kubernetes има по един обект за всеки от тях и този урок те учи да ги използваш, без да им вярваш повече, отколкото обещават: `ConfigMap` не е тайна, `Secret` не е криптиран и нито един от двата не кара програмата ти сама да разбере, че нещо се е променило.

**Време:** 2 × 45 мин

**Какво изграждаш:** `revisor`, конфигуриран без повторно изграждане на образа: списъкът с услуги излиза от Deployment и живее в `ConfigMap`; токенът за достъп живее в `Secret`, който се монтира като файл и не може да се редактира; а промяна в списъка сама задейства *rollout*

**Какво научаваш:** `ConfigMap` като променливи на средата (`revisor` чете само променливи) и защо ръчната му промяна не рестартира никого; `Secret` като файл, кой може да го чете и защо base64 не е криптиране; `fsGroup` и собственикът на монтираните файлове; Kustomize с `configMapGenerator` и `secretGenerator` и *hash*-ът, който задейства *rollout*; неизменимите Secrets

**Откъде идваш.** От [Урок 3](03-services-dns.md): `revisor` има три реплики зад Service на име `revisor`, тестовата услуга, която се проваля нарочно, живее зад друг, на име `prueba`, и умееш да използваш Pod за отстраняване на грешки с `curl` (`depurar`), за да говориш с `revisor` отвътре на клъстера. От [Урок 2](02-pods-deployments.md) носиш веригата Deployment → ReplicaSet → Pod и правилото, което тук има повече значение от всякога: *rollout* се случва **ако и само ако се промени шаблонът на Pod**. А от [курса по Docker](https://www.habil.mx/bg/courses/docker/) носиш един навик: токенът се дава на `revisor` чрез файл (`REVISOR_TOKEN_ARCHIVO`), никога чрез променлива, защото променливата се чете с `docker inspect`.

**Какво не прави този урок.** Не криптира обектите Secret вътре в клъстера: това се конфигурира в `kube-apiserver` на истински клъстер и [Урок 10](10-proyecto-final.md) го слага в списъка с онова, което липсва, за да е това готово за продукция. Не решава и **кой** може да чете обектите Secret с фини права: тук ще видиш, че ти можеш, а [Урок 7](07-aislar-permisos-red.md) дава на всяка програма собствен акаунт и минимални права. И клъстерът все още не умее да различи `revisor`, който е стартирал, от такъв, който може да обслужва; в този урок ще видиш какво струва това, а probes идват в [Урок 5](05-salud-recursos-apagado.md).

**За изпълненията.** Всички изходи в този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1 (който носи вграден Kustomize v5.8.1) и образа на възел `kindest/node:v1.37.0`, фиксиран чрез отпечатъка си, в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l4`. Машината беше Mac с процесор ARM и Docker Engine 29.2.1 във виртуална машина с Linux (Colima), а **не** Linux Mint, който е референтната система на курса. Какво се променя в твоя Mint: архитектурата, случайните наставки на обектите Pod и ReplicaSet, IP адресите, възрастите, възелът, на който попада всяка реплика, размерът, който отчита `tmpfs`, и най-вече **токенът и името на обекта Secret**, които са нови при всяко изпълнение (името на ConfigMap, напротив, трябва да ти излезе идентично: `revisor-config-t6cm6872fk`). Още една подробност: `wc -c` в macOS допълва числото с интервали отляво (`      33`), а този в Linux — не (`33`). Цялата обиколка е в [`programas/04-configuracion-secretos/`](../programas/04-configuracion-secretos): `correr.sh` създава клъстера, зарежда му двата образа на курса, оставя го така, както завърши Урок 3, минава през урока по ред, изпълнява Упражнения 1 до 3 (третото — в пространство от имена за еднократна употреба, което изтрива накрая) и изтрива клъстера. Отне 2 минути и 43 секунди; създаването на клъстера и изчакването да е готов бяха 42 секунди, а изтриването му — 4. Изходът му е `correr.salida.txt`. Скриптът генерира собствен токен, изтрива го накрая и оставя `kustomization.yaml` както си е бил, дори да спре по средата; а ако `kind create cluster` се провали, спира там с код 1, вместо да продължи върху клъстер, който не съществува.

## След урока ще можеш да

- Изнасяш променлива на средата от Deployment в `ConfigMap` и разчиташ в `kubectl describe pod` откъде идва всяка променлива.
- Доказваш с отчета на `revisor`, че ръчната промяна на `ConfigMap` не променя променливите на обектите Pod, които вече работят, и обясняваш защо.
- Пишеш `kustomization.yaml` с `configMapGenerator` и `secretGenerator`, виждаш с `kubectl kustomize` какво ще генерира и я прилагаш с `kubectl apply -k`.
- Предвиждаш, че промяна в съдържанието на генериран ConfigMap слага друга наставка на името му (и че същото съдържание като преди връща точно същото име), и проверяваш с `kubectl diff -k`, че тази смяна на името задейства *rollout*.
- Монтираш `Secret` като файл с `defaultMode: 0440` и `fsGroup` и откриваш този файл във възела, в `tmpfs`.
- Декодираш Secret с `base64 -d`, за да докажеш, че base64 не е криптиране, и сменяш съдържанието на неизменим Secret по единствения възможен начин: с друг Secret.
- Разпознаваш `permission denied` на нечетим Secret и `couldn't find key` на зле написан ключ и казваш кое от двете сваля услугата и защо.

## Защо, преди как

До Урок 3 списъкът с услуги, които `revisor` проверява, беше записан вътре в Deployment, на ред `value: "prueba http://prueba:9000/ 2s"`. Работи, но събира две неща, които се променят с различно темпо. **Рецептата** на услугата (кой образ, колко реплики, каква сигурност) се променя рядко и за нея се грижи онзи, който оперира клъстера. **Конфигурацията** (кои услуги да се проверяват, с какво времево ограничение) се променя често и понякога я иска друг екип. Ако живеят в един и същ файл, всяка промяна на списъка е промяна на рецептата, със своя преглед и своя риск. [Документацията за ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) го казва така: ConfigMap ти позволява „да отделиш специфичната за средата конфигурация от образите на контейнерите си, така че приложенията ти да са лесно преносими“.

Токенът е друга работа. Той не е конфигурация, която някой иска да чете: той е ключ. Записан в Deployment, той пътува с манифеста до Git, до всяко копие на хранилището и до всеки екран, на който някой изпълни `kubectl get deployment -o yaml`. Kubernetes има отделен обект за това, **Secret**, и този урок ти показва с реални изходи какво защитава и какво не. Защото обектът Secret има слава, която не е заслужил: много хора вярват, че щом данните му се появяват в base64, те са криптирани. Не са и ще го провериш с една-единствена команда.

И има трети въпрос, най-финият: **кога програмата разбира, че конфигурацията ѝ се е променила?** `revisor` чете променливите си на средата само веднъж, при стартиране. Kubernetes не рестартира никого, защото се е променил някой ConfigMap. Ако не виждаш това, ще промениш конфигурацията, ще видиш обекта променен в клъстера и ще повярваш, че е готово, докато обектите Pod продължават да работят със стария списък. Решението на този урок е инструмент, който вече носиш вътре в `kubectl`, Kustomize, и трик, толкова прост, че изглежда като измама: да сменяш **името** на ConfigMap всеки път, когато се промени съдържанието му.

Урокът има седем части с понятия и след тях обичайните раздели:

1. **Конфигурацията, записана в Deployment** (4.1): отправната точка.
2. **Ръчно написан ConfigMap** (4.2) и как се свързва с променлива.
3. **Промяната на ConfigMap не рестартира никого** (4.3), измерено.
4. **Токенът като Secret и защо като файл** (4.4).
5. **Kustomize: генераторите и *hash*-ът** (4.5).
6. **base64 не е криптиране** (4.6).
7. **Промяната на списъка задейства *rollout*** (4.7).

Това е целта. В края на 4.5 `revisor` се конфигурира отвън и всеки обект носи в името си отпечатъка на своето съдържание:

```text
$ kubectl apply -k .
configmap/revisor-config-t6cm6872fk created
secret/revisor-token-bh266kt42m created
service/prueba unchanged
service/revisor unchanged
deployment.apps/prueba unchanged
deployment.apps/revisor configured
```

## Понятията

### 4.0 Клъстерът, както завърши Урок 3

Този урок използва собствен клъстер, `curso-k8s-l4`, с конфигурацията от три възела от Урок 1, току-що създаден. Създай го така, от корена на хранилището на курса, със същото внимание, което научи в Урок 1, и му зареди двата образа от курса по Docker:

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

`export` важи само в този терминал. Ако отвориш друг, повтори `export` със същия път, иначе `kubectl` ще говори с друг клъстер. А ако `kind create cluster` се провали, не продължавай: прочети съобщението му, защото всичко, което следва, би предполагало клъстер, който не съществува.

След това му се прилага онова, което остави Урок 3. Файловете са в папката с програмите на този урок: изходният Deployment, в `punto-de-partida/revisor-deployment.yaml`, и двата обекта Service, Deployment на `prueba` и обектът Pod `depurar`, без промени. Изходите в този раздел са от изпълнението на `correr.sh`, който прави точно това:

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

Както винаги, първата команда пита с кой клъстер говориш. В този урок ще създаваш и изтриваш обекти Secret и `kind-curso-k8s-l4` е единственият отговор, който ти позволява да продължиш. **Повтаряй `kubectl config current-context` преди всяка команда, която променя нещо** (`apply`, `patch`, `delete`, `rollout restart`) и преди всяко упражнение: скриптът го прави преди всяко `kubectl`, и ти също. За да не се пълни урокът с еднакви редове, той се показва само там, където е най-важно.

### 4.1 Конфигурацията, записана вътре в Deployment

Ето как изглежда днес конфигурацията на `revisor`:

```text
$ kubectl get deployment revisor -o jsonpath='{.spec.template.spec.containers[0].env}{"\n"}'
[{"name":"REVISOR_SERVICIOS","value":"prueba http://prueba:9000/ 2s"}]

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           2ms  200
```

Една променлива, със стойността, записана направо там (`value`). А `/api/estados` отговаря на всеки, който го поиска: `revisor` все още няма токен, така че не го изисква. Тази таблица е твоят **измервателен инструмент** през целия урок. `revisor` няма *shell*, така че не можеш да влезеш и да видиш променливите му с `env`; но отчетът му изброява точно услугите, които е прочел от `REVISOR_SERVICIOS` при стартиране. Ако таблицата казва `prueba` и нищо повече, `revisor` работи с този списък, каквото и да казва който и да е обект в клъстера.

Един въпрос, който да запомниш: какво би трябвало да направиш, за да добавиш услуга към списъка? Да редактираш този Deployment. Това променя шаблона му, така че задейства *rollout* (правилото от Урок 2). Работи. Проблемът не е технически, а в това кой какво пипа.

### 4.2 Ръчно написан ConfigMap

#### 4.2.1 Обектът

**ConfigMap** е, според документацията си, „обект на API, който се използва за съхраняване на неповерителни данни в двойки ключ–стойност“. Двете думи, които имат значение, са **неповерителни**: същата страница съдържа предупреждение в каре, „ConfigMap не предоставя нито тайна, нито криптиране“, и те праща да използваш Secret, ако данните са поверителни. И още едно предупреждение: онова, което пазиш в ConfigMap, не може да надхвърля 1 MiB. Той е за конфигурация, не за големи файлове.

Ето първия, написан ръчно. Той е **програма**: `programas/04-configuracion-secretos/fig04_01.configmap.yaml`.

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

Чете се като всеки обект: `apiVersion: v1` (основната група на API, както обектите Pod), `kind: ConfigMap`, име и етикет. Новото е `data`: карта от ключове и стойности, всички текст. Тук има само един ключ, `REVISOR_SERVICIOS`, и той се казва като променливата нарочно: така никой не трябва да превежда между две имена.

```text
$ kubectl apply -f fig04_01.configmap.yaml
configmap/revisor-config created

$ kubectl get configmap revisor-config -o jsonpath='{.data}{"\n"}'
{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s"}
```

(Преди този `apply` `kubectl config current-context` каза `kind-curso-k8s-l4`.) Дотук обектът ConfigMap съществува, но никой не го използва. Един ConfigMap не прави нищо сам по себе си: това са данни, съхранени в клъстера, които чакат някой Pod да ги поиска.

#### 4.2.2 От ConfigMap към променлива

Документацията дава четири начина да се използва ConfigMap от Pod: като аргументи на командата на контейнера, като **променливи на средата**, като **файлове** в том само за четене или като се чете с код, който говори с API на Kubernetes. `revisor` решава вместо теб кой върши работа: той чете само променливи на средата (`REVISOR_SERVICIOS`, `REVISOR_PUERTO`, `REVISOR_REPORTE` и `REVISOR_TOKEN_ARCHIVO`). Файл със списъка не би му свършил никаква работа, защото не би го търсил. Затова в този курс **ConfigMap се подава като променлива**.

Този Deployment (`fig04_02.revisor-con-configmap.yaml`, още една **програма**) е онзи от Урок 3 с една-единствена разлика. Там, където преди пишеше `value: "prueba http://prueba:9000/ 2s"`, сега пише откъде да се вземе стойността:

```yaml
        env:
        - name: REVISOR_SERVICIOS
          valueFrom:
            configMapKeyRef:
              name: revisor-config
              key: REVISOR_SERVICIOS
```

Прочети го като изречение: променливата `REVISOR_SERVICIOS` взема стойността си (`valueFrom`) от ключа `REVISOR_SERVICIOS` на ConfigMap с име `revisor-config`. Останалата част от файла не се променя и можеш да го провериш сам с `diff punto-de-partida/revisor-deployment.yaml fig04_02.revisor-con-configmap.yaml`.

Има и друг начин, `envFrom`, който превръща **всички** ключове на един ConfigMap в променливи наведнъж. Удобен е, но скрива кои променливи получава контейнерът: ще трябва да отидеш да видиш ConfigMap, за да разбереш. Тъй като `revisor` безшумно пренебрегва непознатите променливи, тук е уместен `configMapKeyRef`: всяка променлива е записана, с името си, в Deployment.

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

`configured`: шаблонът се промени, значи имаше *rollout* и има нови обекти Pod. `kubectl describe pod` показва променливата и вместо стойността ѝ — **откъде идва**: „зададена с ключа `REVISOR_SERVICIOS` от ConfigMap `revisor-config`“. `Optional: false` означава, че ако този ConfigMap или този ключ не съществуват, контейнерът не стартира. Ще го предизвикаш в Упражнение 1. Таблицата остава същата като преди, както трябва: същият списък, друго място.

### 4.3 Промяната на ConfigMap не рестартира никого

Сега молбата от сцената: да се добави услуга. За да не зависиш от нищо извън клъстера, „новата услуга“ е същата `prueba` с друго име, `lento`, и по-кратко времево ограничение, половин секунда. Важното е да се появи нов ред в таблицата.

Преди да промениш каквото и да е, провери контекста (`kubectl config current-context` → `kind-curso-k8s-l4`) и погледни обектите ReplicaSet. Горният е този от `fig04_02`; долният — този от Урок 3, на `0 0 0`:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       3s
revisor-697fb84f97   0         0         0       12s

$ kubectl patch configmap revisor-config -p '{"data":{"REVISOR_SERVICIOS":"prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms"}}'
configmap/revisor-config patched
(30 s después)
```

`kubectl patch` променя само полетата, които му подадеш. Тук даде на ключа списък с две услуги, разделени със запетая. Клъстерът казва `patched`: обектът ConfigMap се промени. Тридесет секунди по-късно:

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   3         3         3       34s
revisor-697fb84f97   0         0         0       43s

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           4ms  200
```

Нито един нов ReplicaSet, а таблицата продължава да казва само `prueba`. **ConfigMap се промени, а `revisor` не разбра.** Това не е закъснение, което се оправя с чакане: така ще остане, докато обектът Pod не се роди отново.

Причината има две половини и е добре да видиш и двете.

**Половината на Kubernetes.** Променливата на средата се фиксира, когато контейнерът стартира. Така работят променливите в Linux: процесът получава средата си при раждането си и никой не му я променя после отвън. Документацията за ConfigMaps го казва без заобикалки: „ConfigMaps, консумирани като променливи на средата, не се обновяват автоматично и изискват рестартиране на обекта Pod“. А Deployment няма защо да рестартира нищо: неговият шаблон казва „вземи променливата от ConfigMap `revisor-config`“, а това не се е променило. Промени се съдържанието на ConfigMap, не шаблонът, така че правилото „ако и само ако“ от Урок 2 не се изпълнява. Няма *rollout*.

**Половината на `revisor`.** Дори Kubernetes да можеше да му смени променливата, това нямаше да помогне: `revisor` чете конфигурацията си само веднъж, при стартиране. Неговият код (`cmd/revisor/config.go`, от курса по Docker) сглобява списъка във функция, която се извиква в началото и никога повече.

А ако ConfigMap беше монтиран като файл? Документацията казва, че тогава той наистина се обновява сам, „в крайна сметка“, със закъснението на синхронизацията на `kubelet`. Но това помага само на програма, която чете файла отново, а `revisor` не го прави. Много реални програми — също. Затова правилният въпрос никога не е „промени ли се ConfigMap?“, а „работи ли програмата вече с новата конфигурация?“. И на този въпрос се отговаря с програмата, а не с ConfigMap: тук — с таблицата.

Ръчният изход е онзи от Урок 2:

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

Сега вече да: две услуги. `rollout restart` добави анотацията `restartedAt` към шаблона, шаблонът се промени и новите обекти Pod прочетоха новия списък при раждането си. Ревизия 3.

Работи, но зависи от това някой **да се сети** да рестартира. И обърни внимание какво не остава записано никъде: историята на Deployment казва, че е имало три ревизии, но нито една не казва, че третата е била заради промяна на списъка. Ако утре някой направи `rollout undo`, за да се върне към ревизия 2, той се връща към шаблона на ревизия 2, който сочи към същия ConfigMap `revisor-config`… който вече съдържа новия списък. Няма начин да се върнеш към старата конфигурация, защото старата конфигурация вече не съществува. Раздел 4.5 решава и двете неща с една-единствена идея.

### 4.4 Токенът: Secret, и то като файл

#### 4.4.1 Какво е Secret

**Secret**, според неговата [документация](https://kubernetes.io/docs/concepts/configuration/secret/), е „обект, който съдържа малко количество чувствителни данни, като парола, токен или ключ“. Много прилича на ConfigMap: също е карта от ключове и стойности, също има таван от 1 MiB и също се използва като променлива или като файл. Разликите са в отношението на клъстера към него:

- **Пътува само до възлите, които се нуждаят от него.** Secret се изпраща до възел само ако Pod на този възел го поиска.
- **Във възела, ако го монтираш като файл, живее в паметта.** `kubelet` пази копието в `tmpfs`, файлова система в RAM, „за да не се записват поверителните данни в постоянно хранилище“; и го изтрива, когато си отиде обектът Pod, който го е използвал. Тази защита е на тома: ако Secret се консумира като променлива на средата, няма `tmpfs` по пътя, защото стойността пътува в дефиницията на процеса, която получава *runtime*-ът. `tmpfs` ще видиш в 4.5.6.
- **Може да се третира отделно в правата.** Правило на RBAC (Урок 7) може да позволи четене на ConfigMaps, но не и на Secrets.

И едно нещо, което **не** прави: криптиране. Същата страница започва с предупреждение в каре, което си струва да се прочете изцяло: „Обектите Secret на Kubernetes се съхраняват по подразбиране некриптирани в хранилището за данни на сървъра на API (etcd). Всеки с достъп до API може да прочете или промени Secret, както и всеки с достъп до etcd. Освен това всеки, който е упълномощен да създава Pod в дадено пространство от имена, може да използва този достъп, за да прочете всеки Secret от това пространство от имена“. Раздел 4.6 го подлага на проверка.

#### 4.4.2 Токенът се генерира, не се пише

Токенът на `revisor` не е стойност, която се избира, нито такава, която се копира от документ. Генерира се, на случаен принцип, всеки път, когато е нужен нов:

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

`openssl rand -hex 16` иска 16 случайни байта и ги записва в шестнадесетичен вид: 32 знака плюс знака за нов ред, който добавя накрая. Затова `wc -c` брои 33. Скобите и `umask 077` сменят маската на правата **само за тази команда**: файлът се ражда с права `0600` (`-rw-------`), които позволяват четене само на теб, вместо `0644`, които би оставила обичайната ти маска, четими за всеки потребител на машината. Това е същият токен, който вътре в обекта Pod ще има `0440`: пази се по един и същ начин на твоята машина и в клъстера. Този знак за нов ред не пречи: `revisor`, когато чете файла, маха интервалите и новите редове от краищата (`strings.TrimSpace`, в кода му).

Последните две команди са навикът на този урок. `.gitignore` казва, че `token.txt` **не** влиза в хранилището, а `git check-ignore -v` го потвърждава, като казва кой файл и кой ред го изключват. Сцената започна с токен в историята на Git и това е начинът да не се случи отново: файлът съществува на твоята машина, клъстерът го получава, а Git никога не го вижда. Ако работиш извън хранилище, `git check-ignore` ще ти каже, че това не е хранилище; правилото остава валидно за деня, в който стане.

#### 4.4.3 Защо като файл, а не като променлива?

Secret може да се подаде като променлива на средата (със `secretKeyRef`, близнак на `configMapKeyRef`). Този курс не го прави, и не по прищявка:

- **Променливата се наследява.** Всеки процес, който контейнерът стартира, получава копие от средата му. Файлът не се копира във всеки дъщерен процес: трябва да отидеш да го отвориш нарочно и може да го отвори само онзи, който има право.
- **Променливата се отпечатва неволно.** В дъмп при грешка, в `env` при отстраняване на грешки, в журнала на програма, която при провал пише „стартирах с тази конфигурация“. [Ръководството с добри практики за Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/) изисква от всяко приложение, след като прочете Secret, да избягва „записването на данните в явен вид“.
- **Самият `revisor` го иска.** Ако получи токена в `REVISOR_TOKEN`, стартира, но записва в журнала си предупреждение: `el token llegó por REVISOR_TOKEN: cualquiera con docker inspect lo puede leer; usa REVISOR_TOKEN_ARCHIVO`. Неговата програма вече е гласувала.

Така че `revisor` получава две неща: обекта Secret, монтиран като файл в `/secretos/token`, и обикновена, нетайна променлива, която му казва къде да го търси: `REVISOR_TOKEN_ARCHIVO=/secretos/token`. Пътят не е тайна; съдържанието — да.

### 4.5 Kustomize: генераторите и *hash*-ът

#### 4.5.1 Идеята: името се сменя, когато се смени съдържанието

Спомни си двата проблема от 4.3: промяната на ConfigMap не задействаше *rollout* и нямаше начин да се върнеш към старата конфигурация. И двата идват от едно и също място: обектът ConfigMap има **фиксирано име**, така че шаблонът на Deployment никога не се променя, макар да се променя онова, което е вътре.

Сега си представи, че ConfigMap се казва различно според съдържанието си: `revisor-config-t6cm6872fk` с един списък, `revisor-config-7fbkh2926f` с друг. Промяната на списъка ще създаде **друг** ConfigMap и Deployment ще трябва да сочи към новото име. Шаблонът му ще се промени, а правилото от Урок 2 ще свърши останалото: *rollout*. А старият ConfigMap ще остане там, непокътнат, за да може стара ревизия на Deployment да сочи към него. Това си има цена: Kustomize не изтрива старите, така че те се трупат. В курса това няма значение, защото накрая изтриваш целия клъстер; в клъстер, който живее с месеци, ще трябва да изчистваш ръчно (`kubectl delete configmap <nombre>`) онези, които вече не пази нито една ревизия, и същото с обектите Secret.

Да се прави това ръчно би било мъчение: да изчисляваш име, да го пишеш на две места, никога да не сбъркаш. За това е **Kustomize**, който е вграден в `kubectl` от версия 1.14 (`kubectl kustomize` и `kubectl apply -k`); в този курс това е v5.8.1, онзи, който носи `kubectl` v1.37.1. [Ръководството за Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/) го обяснява с едно изречение: генерираните ConfigMaps и Secrets „носят наставка с *hash* на съдържанието си. Това гарантира, че се генерира нов ConfigMap или Secret, когато се промени съдържанието“. И Kustomize не само генерира името: той познава полетата на обектите в Kubernetes, които сочат към ConfigMap или Secret (`configMapKeyRef`, `secretKeyRef`, `envFrom`, `volumes`), и в тях слага новото име. Това не е замяна на текст: споменаване на `revisor-config` в анотация или в поле на разширен ресурс не се обновява само.

#### 4.5.2 `kustomization.yaml`

Kustomize чете файл с име `kustomization.yaml` в дадена папка. Ето този на урока, **програма**:

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

Три блока:

- **`resources`**: манифестите, които вече познаваш, както са си. Kustomize ги чете, нагласява ги и ги предава заедно. `depurar.yaml` нарочно не е в списъка: той е инструмент за отстраняване на грешки, а не част от услугата.
- **`configMapGenerator`**: „генерирай ConfigMap с име `revisor-config`, с този ключ и тази стойност“. `literals` е за стойности, записани направо там, във формата `LLAVE=valor`. Списъкът с услуги вече не е в Deployment: той е тук, на ред, който може да се преглежда самостоятелно.
- **`secretGenerator`**: „генерирай Secret с име `revisor-token`, с ключ `token`, чието съдържание е това на файла `token.txt`“. Формата `token=token.txt` отделя името на ключа (отляво) от файла, от който идва (отдясно). Без `token=` ключът би се казвал като файла, `token.txt`. А `options: immutable: true` отбелязва обекта Secret като неизменим; разделът „Навикът за сигурност“ обяснява защо.

Обърни внимание какво **не** е в този файл: токенът. `kustomization.yaml` наистина отива в хранилището и само казва откъде да се вземе токенът.

#### 4.5.3 Окончателният Deployment

Deployment на урока е `revisor-deployment.yaml`, **програма**. Спрямо `fig04_02` се променят три неща: токенът, монтиран като файл, променливата, която казва къде е той, и нов ред в `securityContext` на обекта Pod:

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

Проследи го отдолу нагоре, следвайки пътя на токена:

- **Томът `token`**, от тип `secret`, взема обекта Secret `revisor-token` и превръща всеки ключ във файл. Обектът Secret има един ключ, `token`, така че томът ще има един файл, `token`.
- **`defaultMode: 0440`**: правата на този файл. `0440` в осмична система е „собственикът може да чете, групата може да чете, другите — нищо, и никой не пише“. Ако не го зададеш, [ръководството за разпространяване на идентификационни данни](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/) казва, че се използва `0644`, което позволява четене на всички. Тук няма други потребители вътре в контейнера, но минималното право не струва нищо.
- **Монтирането** поставя този том в `/secretos`, с `readOnly: true`. Така файлът остава в `/secretos/token`.
- **Променливата `REVISOR_TOKEN_ARCHIVO`** казва на `revisor` този път. Тя е обикновен `value`: пътят не е тайна.
- **`fsGroup: 65532`**, горе, в `securityContext` на обекта Pod. Това е най-краткият ред и онзи, който се разбира най-трудно, затова има собствено обяснение в 4.5.6.

Обърни внимание на `name: revisor-config` и `secretName: revisor-token`: тук те са **без** *hash*. Пишеш ги така, с базовото име, а Kustomize ги сменя с генерираното име, когато сглобява резултата. Ако напишеш името с *hash*, ще трябва да го сменяш ръчно при всяка промяна на списъка, а точно това искахме да избегнем.

#### 4.5.4 Преглед преди прилагане

`kubectl kustomize .` сглобява резултата и го отпечатва, **без** да пипа клъстера. Това е начинът да видиш какво ще стане:

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

Ето ги генерираните имена: `revisor-config-t6cm6872fk` и `revisor-token-bh266kt42m`. Наставката на ConfigMap зависи само от съдържанието му, така че на твоята машина трябва да излезе същата, `t6cm6872fk`. Тази на Secret зависи от токена, който е нов при всяко изпълнение; твоята ще е друга.

А ето и обекта Secret така, както ще го получи клъстерът. `type: Opaque` е общият тип, „произволни данни“. `immutable: true` идва от `options`. А в `data` е ключът `token` със стойност, която не прилича на твоя токен. Запомни този низ: в 4.6 ще го разглобиш.

#### 4.5.5 Прилагане

Провери контекста и приложи:

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

`apply -k .` е `apply` с Kustomize: сглобява папката и прилага резултата. Kustomize подрежда обектите така, че ConfigMap и Secret да се създадат **преди** Deployment, който ги използва. Обектите Service и `prueba` не се промениха (`unchanged`). `revisor` — да (`configured`): шаблонът му сега сочи към нови имена и монтира нов том.

Сега виж какво остана в клъстера. За обектите Secret се използва **селектор по поле** (`--field-selector`), който филтрира по поле на обекта, а не по етикетите му: `type!=kubernetes.io/service-account-token` оставя настрана обектите Secret от тип „токен на сервизен акаунт“, ако има такива, за да видиш само своите:

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

Три обекта ConfigMap. `kube-root-ca.crt` го слага Kubernetes във всяко пространство от имена, със сертификата на клъстера; не е твой. `revisor-config-t6cm6872fk` е генерираният. А `revisor-config`, който написа ръчно в 4.2, **още е там**. `kubectl apply` създава и обновява онова, което му подадеш; не изтрива онова, което не му подадеш. Никой вече не го използва, така че беше изтрит ръчно. Запомни това за 4.7 и за Упражнение 2: всяка промяна оставя след себе си предишния обект.

Сега обектът Pod отвътре:

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

`config map 'revisor-config-t6cm6872fk'`: Deployment вече сочи към името с *hash*, макар в твоя файл да си написал `revisor-config`. Kustomize го смени при сглобяването. А в `Mounts` — `/secretos from token (ro)`: монтираният Secret, само за четене. Третото монтиране са идентификационните данни на сервизния акаунт, които Урок 2 остави записани като дълг; Урок 7 ги маха.

А `revisor`? Сега има токен, така че го изисква:

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

Без токен — `401` и ясно съобщение. С заглавката `Authorization: Bearer …` — таблицата. Обърни внимание на кавичките в третата команда: `$(cat token.txt)` е в двойни кавички, така че твоят *shell* го замества **на твоята машина**, преди да прати командата към обекта Pod. Токенът никога не се появява написан в историята ти на команди, само `cat`. Появява се обаче, докато трае командата, като аргумент на процеса: в `ps` на твоята машина и вътре в `depurar`. За локално упражнение това стига; в споделен клъстер токенът не се подава през командния ред. А `/salud` (онзи, който проверява `healthcheck`) не иска токен, нарочно: probes от Урок 5 ще го извикват без идентификационни данни.

Таблицата отново казва само `prueba` и това също е правилно: списъкът в `kustomization.yaml` има само една услуга. `lento`, която добави ръчно в 4.3, живееше в ConfigMap, който току-що изтри.

#### 4.5.6 Обектът Secret, погледнат от възела

Къде физически е файлът `/secretos/token`? `revisor` няма *shell*, за да отиде да го погледне, но възелът на kind има, а `kubelet` пази томовете на всеки Pod в папка с идентификатора (`uid`) на обекта Pod. За този Pod, на възела `curso-k8s-l4-worker`:

```text
$ docker exec curso-k8s-l4-worker ls -ln /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 65532 33 Oct 21 13:27 token

$ docker exec curso-k8s-l4-worker sh -c 'mount | grep a415d22b-9837-4123-a7d9-82b1baf9435a | grep -E "secret/token "'
tmpfs on /var/lib/kubelet/pods/a415d22b-9837-4123-a7d9-82b1baf9435a/volumes/kubernetes.io~secret/token type tmpfs (rw,relatime,size=16342676k,inode64,noswap)
```

Името на възела и `uid` на обекта Pod идват от `kubectl get pod <pod> -o jsonpath='{.spec.nodeName}'` и `'{.metadata.uid}'`; скриптът ги търси сам. Две неща за проверка със собствените ти очи:

- **`-r--r----- 1 0 65532 33 … token`**: файлът има правата `0440`, които поиска (`r--r-----`), заема 33 байта (твоят токен със знака за нов ред), собственикът му е потребител `0` (`root`), а групата му е **65532**. Тази група я сложи `fsGroup`.
- **`tmpfs`**: папката на тома е файлова система в паметта, както обещава документацията. Токенът не е записан на диска на възела.

Папката `..data` е подробност от начина, по който `kubelet` обновява томовете на обектите Secret: файлът `token`, който контейнерът вижда, е връзка към `..data/token`, а когато обектът Secret се промени, `kubelet` подготвя нова папка и сменя връзката наведнъж. С неизменим Secret като този това никога няма да се случи.

Сега събери реда от `ls` със `securityContext`. `revisor` работи като потребител 65532 и група 65532. Файлът е на `root` и на група 65532, с право на четене за групата. `revisor` го чете, **защото е от групата**. Без `fsGroup` групата на файла би била друга и `revisor` нямаше да има откъде да го прочете. [Ръководството за `securityContext`](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) описва `fsGroup` така: процесите на контейнера стават част от тази група като допълнителна група и „томовете, които поддържат управление на собствеността, се променят така, че да са на GID, посочен от `fsGroup`“. Разделът „Грешката, която ще видиш“ ти показва какво става, ако го пропуснеш, и не е онова, което би очаквал.

### 4.6 base64 не е криптиране

Вземи низа, който видя в обекта Secret, и този от клъстера:

```text
$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}{"\n"}'
NDMzYzdhZGZhNmZjNmZjM2QwMzY3NmI3ZjVjMjMzOWUK

$ kubectl get secret -o name | grep revisor-token | xargs kubectl get -o jsonpath='{.data.token}' | base64 -d
433c7adfa6fc6fc3d03676b7f5c2339e

$ cat token.txt
433c7adfa6fc6fc3d03676b7f5c2339e
```

(`grep revisor-token | xargs` намира обекта Secret, макар името му да се сменя при всяко изпълнение.) Една команда, без ключ, без парола, без нищо за отгатване: `base64 -d` връща целия токен, идентичен с файла. **base64 не е криптиране.** То е **кодиране**: начин да се запише произволна поредица от байтове само с букви, цифри, `+` и `/`, плюс `=` за допълване накрая, когато е нужно (като `eA==` по-нататък), за да се побере в текстов файл като YAML. Да криптираш означава, че без ключ не може да се прочете. Да кодираш означава, че може да се прочете с публична таблица. Ръководството с добри практики го казва в един ред: „кодирането base64 **не** е метод за криптиране; не дава никаква допълнителна поверителност спрямо явния текст“. И предупреждава за грешката от сцената: ако пазиш манифест на Secret в хранилище, „тайната остава достъпна за всички, които могат да четат манифеста“.

Защо тогава съществува base64? Защото един Secret може да пази каквото и да е, включително двоични данни, като сертификат или ключ, а YAML е текст. base64 е пликът, който позволява да се сложат байтове в текстов файл. Не е сейф.

Кой може да направи това, което току-що направи?

```text
$ kubectl auth can-i get secrets
yes
```

`kubectl auth can-i` пита клъстера дали **ти** можеш да направиш нещо, без да го правиш. Ти можеш, защото `kubeconfig`, който ти даде kind, е на администратор. В истински клъстер това се контролира от RBAC, а Урок 7 го упражнява. Но документацията за Secrets предупреждава за една задна врата: който може да създаде Pod в дадено пространство от имена, може да монтира в него всеки Secret от това пространство и да го прочете отвътре, макар да няма право на `get secrets`. Затова обектите Secret на една услуга живеят в пространството от имена на тази услуга, а не в такова, споделено с други (Урок 7).

И още едно, което не се вижда оттук: вътре в клъстера обектът Secret се съхранява в `etcd` **некриптиран**, освен ако администраторът не включи криптирането в покой на `kube-apiserver`. Ръководството с добри практики го поставя като първа препоръка: „трябва да конфигурираш криптирането на данните на твоите Secrets в etcd“. В kind това не се прави; Урок 10 го отбелязва в списъка с онова, което липсва за продукция.

Онова, което Secret наистина ти дава в сравнение с писането на токена в Deployment, е следното: токенът не е в манифеста ти, нито в Git; пътува само до възлите, които го използват, и там живее в паметта; и може да се даде право за четене на Deployments, без да се дава право за четене на Secrets. Това е доста. Просто не е криптиране.

### 4.7 Промяната на списъка задейства *rollout*

Сега вече молбата от сцената, с пълния инструмент. Преди промяната — обектите ReplicaSet на `revisor` (четири ревизии: тази от Урок 3, тази от `fig04_02`, тази от `rollout restart` и тази от `apply -k`):

```text
$ kubectl get replicaset -l app=revisor
NAME                 DESIRED   CURRENT   READY   AGE
revisor-66db8c7755   0         0         0       43s
revisor-697fb84f97   0         0         0       52s
revisor-99546b58f    0         0         0       9s
revisor-f6dd4cb4d    3         3         3       6s
```

Промяната се прави **в `kustomization.yaml`**, а не в клъстера (и преди да я приложиш, отново `kubectl config current-context`). Отвори файла и добави услугата в края на списъка, отделена със запетая:

```text
$ grep REVISOR_SERVICIOS kustomization.yaml
  - REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
```

Преди да приложиш, попитай клъстера какво би се променило. `kubectl diff -k .` сравнява онова, което Kustomize би сглобил, с онова, което има в клъстера; тук е филтрирано, за да се виждат само редовете, които имат значение:

```text
$ kubectl diff -k . | grep -E '^[-+] .*(REVISOR_SERVICIOS|name: revisor-config)'
-              name: revisor-config-t6cm6872fk
+              name: revisor-config-7fbkh2926f
+  REVISOR_SERVICIOS: prueba http://prueba:9000/ 2s,lento http://prueba:9000/ 500ms
+  name: revisor-config-7fbkh2926f
[código de salida: 1]
```

Прочети го ред по ред. Първите два са на **Deployment**: препратката му минава от `revisor-config-t6cm6872fk` към `revisor-config-7fbkh2926f`. Последните два са на **нов ConfigMap**, с новия списък и новото име. Тези първи два реда са *rollout*, обявен преди да се случи: шаблонът на Pod се променя. (Изходният код 1 е на `kubectl diff`, който така съобщава, че **е** намерил разлики. Не е грешка.)

При същото съдържание — същото име: твоят `7fbkh2926f` трябва да е идентичен с този. Прилагане:

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

Нов ConfigMap (`created`), обектът Secret без промени (`unchanged`: токенът не се е променил, нито името му), нов ReplicaSet, `revisor-769ff55c9c`, който пое трите реплики на смени, и таблицата с две услуги. **Никой не трябваше да се сеща да рестартира каквото и да е.** Това е цел 4 на курса: сменяш списъка, прилагаш с `kubectl apply -k .` и клъстерът прави *rollout* сам, без повторно изграждане на образа и без да трябва да помниш да рестартираш Deployment. Нищо не наблюдава файловете ти: без `apply` клъстерът дори не разбира, че си сменил списъка.

А връщането назад, което в 4.3 беше невъзможно, тук е тривиално. `kustomization.yaml` беше върнат към оригиналния си списък и приложен:

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

`revisor-config-t6cm6872fk unchanged`: ConfigMap с оригиналния списък **никога не си е отивал**. Kustomize изчисли същото име за същото съдържание, Deployment отново посочи към него и шаблонът му отново стана идентичен с този на ReplicaSet `revisor-f6dd4cb4d`. Всяка конфигурация има собствен обект и всяка ревизия на Deployment сочи към своя.

Цената на това вече я видя в 4.5.5: `revisor-config-7fbkh2926f` остана в клъстера, без никой да го използва. С времето се натрупват. Цената е малка (всеки тежи няколко байта) и се плаща срещу възможността да се върнеш назад; подреденият начин за почистването им е част от онова, което Урок 10 оставя за истински клъстер.

## Грешката, която ще видиш

Грешката в този урок се появява точно когато мислиш, че си приключил: обектът Secret съществува, монтирането е написано правилно, пътят е верен… а `revisor` не стартира. Предизвикана е нарочно, като от Deployment беше махнат редът `fsGroup` с `patch`, след проверка на контекста:

```text
$ kubectl patch deployment revisor --type=json -p='[{"op":"remove","path":"/spec/template/spec/securityContext/fsGroup"}]'
deployment.apps/revisor patched
```

(`--type=json` позволява точни операции като `remove` върху точен път в обекта. Това е начинът да махнеш **един** ред, без да пренаписваш файла.) Двадесет и пет секунди по-късно се разчита в обичайния ред.

**Първо, състоянието.**

```text
$ kubectl get pods -l app=revisor
NAME                       READY   STATUS   RESTARTS      AGE
revisor-7ffcfb7646-2lsmc   0/1     Error    2 (23s ago)   24s
revisor-7ffcfb7646-k4s2b   0/1     Error    2 (23s ago)   25s
revisor-7ffcfb7646-th42g   0/1     Error    2 (24s ago)   25s
```

`Error` и `RESTARTS 2`: контейнерът **наистина стартира**, а програмата завърши с грешка; `kubelet` го рестартира и той отново завърши. Това е състояние, различно от онези в Урок 2. Не е `ImagePullBackOff` (образът е там), нито `CreateContainerConfigError` (конфигурацията можа да се сглоби). Програмата е тази, която пада. След още няколко секунди състоянието минава в `CrashLoopBackOff`: [документацията за жизнения цикъл на Pod](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/) обяснява, че `kubelet` рестартира с изчакване, което расте (10 s, 20 s, 40 s…) до таван от 300 s, и че `CrashLoopBackOff` е името на това изчакване. `Error` и `CrashLoopBackOff` се редуват: едното е „падна“, другото е „чакам, преди да опитам отново“.

**Второ, `logs`**, защото щом програмата е стартирала, тя има какво да каже:

```text
$ kubectl logs revisor-7ffcfb7646-2lsmc
revisor: leyendo el token de REVISOR_TOKEN_ARCHIVO: open /secretos/token: permission denied
```

Един ред, и казва всичко: `revisor` е отишъл да чете файла, посочен от `REVISOR_TOKEN_ARCHIVO`, операционната система му е отказала правото (`permission denied`) и `revisor` е отказал да стартира без токена си. Това „отказване“ е решение на неговия код, и то правилното: `revisor`, който стартира без токен, би оставил `/api/estados` отворен за всеки.

Защо не можа да го прочете? Погледни във възела, както в 4.5.6, сега за един от обектите Pod, които се провалят:

```text
$ docker exec curso-k8s-l4-worker2 ls -ln /var/lib/kubelet/pods/c26f312f-6841-4911-bea8-6f14513b4a11/volumes/kubernetes.io~secret/token/..data/
total 4
-r--r----- 1 0 0 33 Oct 21 13:28 token
```

Сравни го с този от 4.5.6, `-r--r----- 1 0 65532`. Правата са същите, `0440`, и собственикът също, `root`. Онова, което се е променило, е **групата**: с `fsGroup` беше 65532 и `revisor` го четеше, защото е от групата; без `fsGroup` е `0`, тази на `root`. Потребител 65532 не е нито собственикът, нито от групата, и за него `0440` е „нищо“.

**Трето, `describe`**, за да потвърдиш кой говори:

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

Всичко е `Normal` до `Started`, три пъти (`x3`): образът беше там, контейнерът беше създаден и стартира. Единственото `Warning` е `BackOff`, „чакам, преди да рестартирам контейнера, който се провали“. Събитията не казват **защо** се е провалил, защото клъстерът не знае: програмата падна сама. Затова, когато контейнерът е успял да стартира, `logs` идват преди `describe`. В Урок 2, с `ImagePullBackOff`, беше обратното: нямаше програма, която да говори, и отговорът беше в събитията.

**А сега онова, което не очакваше:**

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   0/3     3            0           83s
```

`0/3`. **Не остава нито една изправна реплика.** В Упражнение 3 от Урок 2 счупеният образ остави *rollout* заседнал с непокътната услуга: три стари живи обекта Pod и един нов, който се проваля. Тук трите стари обекта Pod вече ги няма. Какво се е променило, щом стратегията е същата (`maxSurge` 1, `maxUnavailable` 0)?

Разликата е **кога** се проваля новият Pod. При счупения образ контейнерът никога не стартираше, така че обектът Pod никога не беше готов и Deployment никога не махна стар. Тук контейнерът **наистина стартира** и живее няколко милисекунди, преди да прочете токена и да падне. За Deployment това е достатъчно. Без probe, която да пита „можеш ли вече да обслужваш?“, Kubernetes смята контейнера за готов веднага щом стартира. [Документацията за Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) определя кога нов Pod се брои за наличен: когато е готов, без да падне нито един от контейнерите му, в продължение на поне `minReadySeconds`, който по подразбиране е **нула**. Всеки нов Pod е бил „готов“ за миг, Deployment го е отброил и е махнал един стар. При това изпълнение това се случи три пъти и трите обекта Pod, които останаха, не работят. Колко напредва промяната зависи от това колко нови обекта Pod успеят да се отброят като готови, преди да паднат: при повторение на същия този експеримент *rollout* спря по средата, с два стари изправни обекта Pod и `AVAILABLE 2`, а `kubectl rollout status` изтече с `error: timed out waiting for the condition`. Онова, което не се променя, е причината. И в никакъв случай `kubectl rollout status` не би казал `successfully rolled out` при `AVAILABLE 0`: това съобщение изисква всички реплики да са налични. Щетата вече беше нанесена, преди командата да може да предупреди.

Това е най-важното в раздела и не е дефект на Kubernetes: **клъстерът знае само онова, което ти го научиш да пита.** `revisor`, който стартира, не е `revisor`, който може да обслужва. Урок 5 дава на Deployment readiness probe и с нея същата тази грешка оставя три стари реплики живи, както в Урок 2.

**Изходът** е обичайният в този курс: файлът е истината и се прилага отново.

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

`apply -k` върна реда `fsGroup` и шаблонът отново стана такъв, какъвто беше преди `patch`. Обърни внимание, че *rollout* на връщане също мина на смени: тук вече новите обекти Pod четат токена, остават живи и Deployment напредва върху обекти Pod, които работят.

**Редът, за Pod, който стартира и пада:** състоянието (`get pods`: `Error` или `CrashLoopBackOff`, с растящ `RESTARTS`), `logs` (онова, което програмата е казала, преди да падне; ако контейнерът вече е рестартирал, `kubectl logs --previous` показва тези от предишния опит) и накрая `describe`. А преди да заключиш, че „не се е случило нищо сериозно“ — `kubectl get deployment`: колко реплики **наистина** обслужват.

## Навикът за сигурност от урока: Secret не се версионира, монтира се като файл и се отбелязва като неизменим

Таблицата с навици на курса възлага на този урок три правила за Secret. И трите вече ги видя в действие; тук са заедно, с онова, което защитава всяко от тях.

**Не се версионира.** Токенът живее в `token.txt`, който `.gitignore` оставя извън хранилището, а `kustomization.yaml` само казва откъде да се прочете. Онова, което отива в Git, е рецептата, никога стойността. Това е прекият отговор на сцената: тайна, която веднъж влезе в Git, остава в историята завинаги, дори да я изтриеш в следващата версия, а единствената истинска поправка е да я смениш.

**Монтира се като файл**, с `defaultMode: 0440`, `readOnly: true` и `fsGroup`, за да я чете само групата на `revisor`. Живеейки в `tmpfs`, тя не докосва диска на възела. И не се наследява от други процеси, нито се появява в списък с променливи.

**Отбелязва се като неизменим.** С `immutable: true` клъстерът отказва да промени съдържанието на обекта Secret:

```text
$ kubectl get secret -o name | grep revisor-token | xargs -I{} kubectl patch {} -p '{"data":{"token":"eA=="}}'
The Secret "revisor-token-bh266kt42m" is invalid: data: Forbidden: field is immutable when `immutable` is set
[código de salida: 1]
```

`eA==` е буквата `x` в base64: опитът беше токенът да се смени с една-единствена буква. `kube-apiserver` го отхвърли, преди да го запише: „забранено: полето е неизменимо, когато е зададено `immutable`“. [Документацията за Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) дава две причини да се използва. Първата — че те пази от „случайни (или нежелани) обновявания, които биха могли да причинят срив на приложенията“. Втората е за производителност: `kubelet` не трябва да наблюдава неизменимите Secrets, а в клъстер с хиляди от тях това сваля товар от `kube-apiserver`. И едно предупреждение, което трябва да се знае: отбелязването **няма връщане назад**. „Щом един Secret или ConfigMap бъде отбелязан като неизменим, не е възможно да се отмени промяната, нито да се промени съдържанието на `data`. Можеш само да изтриеш обекта Secret и да го създадеш отново“.

Как тогава се сменя токенът? С **друг** Secret. А това, с Kustomize, вече го имаш: нов токен дава нов *hash*, ново име и Deployment започва да монтира новия Secret с *rollout*. Нито един Pod не вижда файла си да се променя по средата; всеки Pod се ражда с токен и умира с него. Упражнение 2 го прави. Генераторът и отбелязването като неизменим са създадени един за друг: генераторът никога не иска да променя Secret, винаги създава друг.

**Какво защитава и какво не.** Тези три правила пазят токена **извън** клъстера (Git) и **във възела** (памет, права). Не го пазят **вътре** в `kube-apiserver`: който има право да чете Secrets или да създава обекти Pod в пространството от имена, го прочита с `base64 -d`, както направи ти в 4.6. Това го защитават правата (Урок 7) и криптирането в покой на истински клъстер (Урок 10).

## Какво се прави погрешно

**Да вярваш, че base64 защитава нещо.** То е кодиране, не криптиране. Манифест на Secret с неговия `data` в хранилище е публикувана тайна. Видя го в 4.6: един `base64 -d`.

**Да версионираш Secret, „защото така клъстерът се възстановява сам“.** Възстановява се онова, което е в Git, а това включва и онзи, който не е трябвало да вижда токена. Токенът се генерира или се взема от място, създадено за пазене на тайни (мениджър на тайни, в истински клъстер), а Git пази само откъде да се вземе.

**Да промениш ConfigMap ръчно и да приемеш, че програмата вече знае.** Ако програмата го чете като променлива, тя не разбира, докато обектът Pod не се роди отново. Измери го в 4.3: ConfigMap казваше две услуги, а `revisor` продължаваше да отчита една. Доказателството, че една промяна е пристигнала, е поведението на програмата, а не обектът.

**Да пишеш в Deployment името с *hash*.** `name: revisor-config-t6cm6872fk`, написано ръчно, престава да върши работа при следващата промяна на списъка. Пише се базовото име и Kustomize го превежда.

**Да изключваш *hash*-а, за да изглежда името чисто.** `disableNameSuffixHash: true` съществува и те връща към проблема от 4.3: промяната на съдържанието не променя шаблона и няма *rollout*. Ще го провериш в Упражнение 3.

**Да подаваш токена чрез променлива на средата, „защото е по-лесно“.** Наследява се, отпечатва се неволно, а самият `revisor` те предупреждава в журнала си да не го правиш.

**Да махаш `fsGroup` или да слагаш `defaultMode: 0444`, „за да може да го чете“.** `fsGroup` е правилният начин `revisor` да чете файла, **защото е от неговата група**. Отварянето на файла за всички работи, но се отказваш от минималното право. А ако махнеш `fsGroup`, без да разбираш, вече видя какво струва.

**Да вярваш, че текущ *rollout* защитава услугата ти.** Без probes Deployment смята за готов Pod, който едва е стартирал, и маха по един изправен стар Pod за всеки нов, макар новият да пада при четенето на конфигурацията си. Преди да приемеш нещо за добро — `kubectl get deployment` (`AVAILABLE` да е равно на желаните реплики) и една истинска заявка.

**Да забравиш, че `apply` не изтрива.** Всяка промяна с генератори оставя след себе си предишния ConfigMap или Secret, а ръчно написан ConfigMap, който вече никой не използва, също остава. Не вредят, но стар Secret, който никой не използва, продължава да е Secret: стар четим токен. Обектите Secret, които вече не служат, се изтриват.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред, от състоянието, в което остана в края на „Навикът за сигурност“, и от папката `programas/04-configuracion-secretos`. **Преди всяко упражнение `kubectl config current-context` трябва да казва `kind-curso-k8s-l4`; ако казва нещо друго, не продължавай.** `correr.sh` ги изпълнява по същия начин, а изходът му е в `correr.salida.txt`. **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще стане. Четвъртото се пише със собствени думи.

### Упражнение 1 — Ключ, който не съществува

Смени, с `patch`, ключа, който Deployment търси в ConfigMap, сякаш си сбъркал при писането му (`REVISOR_SERVICIO`, без крайното S):

```bash
kubectl patch deployment revisor --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/configMapKeyRef/key","value":"REVISOR_SERVICIO"}]'
```

Предвиди: в какво състояние остава новият Pod? Стартира ли контейнерът? Колко стари реплики продължават да обслужват и защо този път не се повтаря `0/3` от „Грешката, която ще видиш“? Провери с `kubectl get pods -l app=revisor` и със събитията `Failed` на новия Pod. За да излезеш, приложи отново `kustomization.yaml`.

### Упражнение 2 — Ротация на токена (проект)

Някой е видял токена на споделен екран и той трябва да се смени. Преди да генерираш новия, запази стария в променлива на терминала си, `VIEJO="$(cat token.txt)"`, за да можеш да го изпробваш после. Генерирай новия с `(umask 077; openssl rand -hex 16 > token.txt)` и приложи `kubectl apply -k .`. Преди да приложиш, предвиди: променя ли се съществуващият Secret, или се появява друг? Има ли *rollout*? Какво отговаря `revisor` на заявка със **стария** токен и какво — на такава с новия? Провери с `kubectl get secret -o name | grep revisor-token` и с два `curl` от `depurar`, единия с `-H "Authorization: Bearer $VIEJO"`, а другия с `-H "Authorization: Bearer $(cat token.txt)"`. Накрая обясни какво би трябвало да направиш със стария Secret и защо.

### Упражнение 3 — Без *hash*

Копирай папката на урока на друго място, добави в края на копието на `kustomization.yaml` тези два реда и виж резултата с `kubectl kustomize` (без да го прилагаш):

```yaml
generatorOptions:
  disableNameSuffixHash: true
```

Предвиди предварително: как ще се казват ConfigMap и Secret? Към кое име ще сочи Deployment? После, без да го изпълняваш, отговори: ако с тази опция смениш списъка и приложиш, има ли *rollout*? Коя част от урока току-що повтори? И тъй като обектът Secret е неизменим, какво мислиш, че би станало при ротация на токена с тази опция?

### Упражнение 4 — Защити файла

Колега предлага токенът да се подава със `secretKeyRef`, като променлива на средата, „защото това е един ред, а не том, и Secret е еднакво таен и в двата случая“. В най-много пет изречения му отговори: в какво е прав, какъв риск добавя променливата, който файлът няма, какво казва самият `revisor`, когато получи токена чрез променлива, и какво трябва да се добави към Deployment, за да може файлът да се чете, без да се отваря за всички.

## Решения

### Решение 1

Измерено в `correr.salida.txt`:

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

Новият Pod остава в **`CreateContainerConfigError`**, същото състояние като при `runAsNonRoot` от Урок 2: `kubelet` не успя да сглоби конфигурацията на контейнера и **не го стартира**. Събитието казва точно какво е липсвало: ключът `REVISOR_SERVICIO` в ConfigMap `default/revisor-config-t6cm6872fk`. Това е, което обявяваше `Optional: false` в `describe` от 4.2.

**Трите стари реплики продължават да обслужват.** Разликата с `0/3` при `fsGroup` е моментът на провала. Тук контейнерът никога не стартира, така че новият Pod никога не е бил готов, нито за миг, а с `maxUnavailable: 0` Deployment не махна нито един стар Pod. При `fsGroup` контейнерът стартираше, беше „готов“ няколко милисекунди и падаше, и това стигаше на Deployment, за да напредне. Дълбокият урок: **грешка, която пречи на стартирането, е по-безопасна от такава, която стартира и пада**, докато нямаш probes.

При повторното прилагане на `kustomization.yaml` шаблонът се върна към този на `revisor-f6dd4cb4d` и счупеният Pod изчезна:

```text
$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           103s
```

### Решение 2

Измерено в `correr.salida.txt`:

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

`VIEJO` е променлива на твоя терминал: токенът не остава записан в историята ти, само името `$VIEJO`. (Не го пази в друг файл, като `token.viejo`: `.gitignore` изключва само `token.txt`.)

**Появява се друг Secret**, `revisor-token-ttgcdb7g7c`; старият не се пипа, а и не би могъл: той е неизменим. Новият токен промени *hash*-а, *hash*-ът промени името, името промени шаблона на Deployment и имаше *rollout* (`deployment.apps/revisor configured` и `rollout status` със същите смени като в 4.7). ConfigMap не се промени (`unchanged`). Накрая старият токен дава `401`, а новият — `200`: новите обекти Pod се родиха с новия файл, а старите, които познаваха стария токен, вече не съществуват.

**Старият Secret трябва да се изтрие** (`kubectl delete secret revisor-token-bh266kt42m`). Нито един Pod не го използва, но той остава в клъстера и всеки с право да чете Secrets може да извади от него, с `base64 -d`, токен, който някой е видял на екран. Ако искаш да можеш да се върнеш към предишната ревизия на Deployment, този Secret би трябвало да съществува; но компрометираният токен е точно онзи, който **не** искаш да можеш да използваш отново. Ротацията не приключва, когато новият заработи: приключва, когато старият вече не върши работа никъде.

### Решение 3

Измерено в `correr.salida.txt`, върху копие във временна папка:

```text
$ tail -2 $TEMPORAL/sin-hash/kustomization.yaml
generatorOptions:
  disableNameSuffixHash: true

$ kubectl kustomize $TEMPORAL/sin-hash | grep -E '^  name: revisor-(config|token)|name: revisor-(config|token)$'
  name: revisor-config
  name: revisor-token
              name: revisor-config
```

ConfigMap се казва `revisor-config`, а Secret — `revisor-token`, без нищо повече, и Deployment сочи към `revisor-config` (третият ред, с по-голям отстъп, е неговият `configMapKeyRef`). Чисти имена и **никакъв *rollout***, когато се промени списъкът: ConfigMap запазва името си, шаблонът на Deployment не се променя и правилото „ако и само ако“ не се изпълнява. Току-що повтори раздел 4.3, само че с Kustomize: обектът се променя, а `revisor` продължава със стария списък, докато някой не се сети за `rollout restart`.

С обекта Secret е по-лошо, и беше измерено. Скриптът сглоби отделна папка **само** с обекта Secret, неизменим и без *hash*, в пространство от имена за еднократна употреба, `sin-hash`. Приложи го, смени токена на това копие и го приложи отново:

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

Тъй като името вече не се променя, `apply -k` се опита да **промени** съществуващия Secret и клъстерът отказа със същото `field is immutable` от „Навикът за сигурност“. За да ротираш токена, ще трябва да изтриеш обекта Secret ръчно преди прилагането, а междувременно обектите Pod, които се рестартират, няма да намерят своя токен. Изключването на *hash*-а и отбелязването като неизменим са две решения, които си противоречат. *Hash*-ът е онова, което прави неизменимостта практична. (Изтриването на пространството от имена `sin-hash` отнесе и този Secret.)

### Решение 4

Един възможен отговор: „Прав си, че Secret пази едни и същи данни и по двата начина и че в `etcd` те са еднакво изложени. Но променливата се наследява от всеки процес, който контейнерът стартира, и се появява във всеки дъмп на средата или журнал, който отпечатва конфигурацията, докато файл само за четене в `tmpfs` не се копира във всеки процес: трябва да отидеш да го отвориш нарочно и може да го отвори само онзи, който има право. Самият `revisor`, ако получи токена в `REVISOR_TOKEN`, пише в журнала си, че всеки с `docker inspect` може да го прочете и че трябва да се използва `REVISOR_TOKEN_ARCHIVO`. За да се чете файлът, без да се отваря за всички, на Deployment му трябват `defaultMode: 0440` и `fsGroup: 65532` в `securityContext` на обекта Pod, което прави групата на `revisor` собственик на файла. Това са три реда повече от променливата и си заслужават.“

## Изтриване на клъстера

Когато приключиш с упражненията, изтрий клъстера на урока. Не оставяй нищо живо на машината:

```text
$ kind delete cluster --name curso-k8s-l4
Deleting cluster "curso-k8s-l4" ...
Deleted nodes: ["curso-k8s-l4-control-plane" "curso-k8s-l4-worker2" "curso-k8s-l4-worker"]

$ kind get clusters | grep -c curso-k8s-l4
0
```

`--name` е задължителен и тук: без него kind би изтрил клъстера с име `kind`, който може да е на друг човек или от друг проект. С клъстера си отиват неговите Secrets, неговите ConfigMaps и копието на токена, което живееше в `tmpfs` на всеки възел.

На твоята машина остават две неща и и двете се изтриват:

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

`case` пропуска само път, който започва с `/tmp/curso-k8s-l4.` и завършва на `/kubeconfig`, точната форма на онзи, който създаде в 4.0; тогава `dirname` маха името на файла, а `rm -rf` изтрива тази папка и нищо друго. Ако терминалът ти сочи другаде (например към твоя `~/.kube/config`, защото си отворил друг терминал и не си повторил `export`), не изтрива нищо и ти казва защо. Това е същата защита, която използва `correr.sh` при почистване: `rm -rf`, който може да се копира и постави, трябва да се пази сам. Затварянето на този терминал също спира използването на временния `kubeconfig`. Клъстерът за следващия урок се създава от нулата, точно като този.

## Как разбирам, че съм успял

- [ ] Обясняваш, с таблицата на `revisor` като доказателство, защо ръчната промяна на ConfigMap не промени списъка с услуги на обектите Pod, които вече работеха.
- [ ] Разчиташ в `kubectl describe pod` от кой ConfigMap и кой ключ идва всяка променлива и какво означава `Optional: false`.
- [ ] Пишеш по памет `kustomization.yaml` с `resources`, `configMapGenerator` (с `literals`) и `secretGenerator` (с `files: - token=token.txt`) и обясняваш какво прави `token=`.
- [ ] Предвиждаш, преди да приложиш, че промяна на списъка създава ConfigMap с друго име и нов ReplicaSet, и го проверяваш с `kubectl diff -k .`.
- [ ] Декодираш Secret с `base64 -d` и обясняваш в две изречения разликата между кодиране и криптиране.
- [ ] Обясняваш какво прави `fsGroup` с файла на обекта Secret и разпознаваш `permission denied` при липсата му в `logs`.
- [ ] Обясняваш защо грешката с `fsGroup` остави Deployment на `0/3`, а тази със зле написания ключ — не.
- [ ] Ротираш токена с нов Secret и знаеш какво да правиш със стария.
- [ ] Изпълняваш `programas/04-configuracion-secretos/correr.sh > /tmp/mi-corrida-l4.txt 2>&1` и сравняваш `/tmp/mi-corrida-l4.txt` с `programas/04-configuracion-secretos/correr.salida.txt` (не пренасочвай към този файл: той е еталонът) по онова, което не се променя между изпълненията: три възела `Ready` на `v1.37.0`; таблицата с `prueba OK … 200`; `<set to the key 'REVISOR_SERVICIOS' of config map 'revisor-config'>`; таблицата, която **не** показва `lento` 30 s след `patch`, а го показва след `rollout restart`; `-rw-------` за `token.txt` и `wc -c` на 33; `token.txt` в `.gitignore`; `revisor-config-t6cm6872fk` като генерирано име; `immutable: true`; `401` без токен, `{"error":"falta el token o no es válido"}` и таблицата с токен; `-r--r----- 1 0 65532 33 … token` върху `tmpfs`; идентичният токен след `base64 -d`; `revisor-config-7fbkh2926f` в `diff` и нов ReplicaSet с `lento` в таблицата; `permission denied` в `logs`, файлът като `-r--r----- 1 0 0` и Deployment на `0/3` без `fsGroup`; ``field is immutable when `immutable` is set``; `couldn't find key REVISOR_SERVICIO`; два Secrets след ротацията, `401` със стария и `200` с новия; имената без наставка от Упражнение 3 и неговото `field is immutable` при ротация; и накрая `sin diferencias con la kustomization`. Токенът, името на Secret, наставките на обектите Pod и ReplicaSet, IP адресите, `uid`, възелът на всеки Pod, възрастите, времената в таблицата и колко пъти се повтаря всеки ред от `rollout status` се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l4`, в папката на урока не е останал `token.txt` и не е останала папка `/tmp/curso-k8s-l4.*`.

## Обобщение

Отговори, без да поглеждаш урока:

1. Какво е ConfigMap и какво казва документацията му за съхраняването на поверителни данни в него?
2. Защо промяната на ConfigMap, който се използва като променлива, не променя онова, което прави `revisor`? Дай двете причини: тази на Kubernetes и тази на програмата.
3. Какво прави `configMapKeyRef` и защо този курс го предпочита пред `envFrom`?
4. Какво добавя Kustomize към името на генериран ConfigMap и как това превръща промяната на съдържанието в *rollout*?
5. Защо, при връщането към оригиналния списък в 4.7, ConfigMap излезе `unchanged`, а не `created`?
6. Каква е разликата между кодиране и криптиране? Какво е base64?
7. Кой може да прочете Secret в един клъстер, освен онзи, който има право на `get secrets`?
8. Какво прави `fsGroup` с файла на монтиран Secret и какво стана, когато беше махнат?
9. Защо грешката с `fsGroup` остави услугата без реплики, а тази със зле написания ключ — не?
10. Какво не може да се прави с неизменим Secret и как тогава се сменя съдържанието му?

## Източници

Всички са консултирани на 21 октомври 2026 г.

- [Kubernetes, „ConfigMaps“](https://kubernetes.io/docs/concepts/configuration/configmap/): определението; че не предоставя тайна, нито криптиране; таванът от 1 MiB; четирите начина да се използва от Pod; че монтираните като файл ConfigMaps се обновяват „в крайна сметка“, а използваните като променливи „не се обновяват автоматично и изискват рестартиране на обекта Pod“; и неизменимите ConfigMaps.
- [Kubernetes, „Configure a Pod to Use a ConfigMap“](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/): `configMapKeyRef`, `envFrom` и незадължителните препратки.
- [Kubernetes, „Secrets“](https://kubernetes.io/docs/concepts/configuration/secret/): определението; предупреждението, че се съхраняват некриптирани в etcd и че който може да създаде Pod, може да чете обектите Secret в неговото пространство от имена; таванът от 1 MiB; „в крайна сметка консистентното“ обновяване на томовете; копието в `tmpfs` във възела; и неизменимите Secrets, двете им предимства и че отбелязването не може да се отмени.
- [Kubernetes, „Good practices for Kubernetes Secrets“](https://kubernetes.io/docs/concepts/security/secrets-good-practices/): криптирането в покой; минималният достъп; че base64 не е метод за криптиране; че манифест на Secret в хранилище излага тайната; и че приложението не бива да записва данните в явен вид.
- [Kubernetes, „Distribute Credentials Securely Using Secrets“](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/): `defaultMode` и стойността му по подразбиране, `0644`.
- [Kubernetes, „Declarative Management of Kubernetes Objects Using Kustomize“](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/): Kustomize вътре в `kubectl` от 1.14; `configMapGenerator` и `secretGenerator`; наставката с *hash* на съдържанието и `generatorOptions` с `disableNameSuffixHash`.
- [Kubernetes, „Configure a Security Context for a Pod or Container“](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/): `fsGroup` като допълнителна група на процесите и като собственик на томовете, които поддържат управление на собствеността.
- [Kubernetes, „Deployments“](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/): `minReadySeconds` и кога нов Pod се брои за наличен.
- [Kubernetes, „Pod Lifecycle“](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/): растящото изчакване между рестартиранията (10 s, 20 s, 40 s… до 300 s) и състоянието `CrashLoopBackOff`.

---

**Следващ:** [Урок 5 — Проверки на състоянието, ресурси и подредено изключване](05-salud-recursos-apagado.md)
