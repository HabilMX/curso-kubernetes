# Урок 3 — Services и DNS

Вторник, 10:20 сутринта. В 11:00 екипът по експлоатация преглежда таблото и иска да види отчета на `revisor` в зелено. Вчера, за да се измъкне от положението, един колега копира IP адреса на Pod от тестовата услуга, `10.244.1.3`, и го постави в списъка с услуги, които `revisor` проверява. Работеше цял следобед. Тази сутрин отчетът казва `FALLA` на всички редове, а никой нищо не е пипал. Или поне така си мислят: през нощта някой е рестартирал обектите Pod, за да приложи промяна, обектите Pod са се родили отново и нито един не се е върнал с вчерашния IP адрес. Адресът, който постави колегата ти, сега не е на никого или, още по-лошо, е на друг Pod, който няма нищо общо. Остават четиридесет минути и въпросът не е какъв IP адрес да поставиш сега, а как да спреш да поставяш IP адреси.

Kubernetes вече е решил този проблем и решението има две части: **Service**, който е име и адрес, които не се променят, макар обектите Pod зад тях да се сменят постоянно, и **DNS на клъстера**, който превръща това име в този адрес за всеки Pod, който попита. Този урок те учи да пишеш първото, да разпитваш второто и да разчиташ какво става, когато един Service не намира никого, към когото да прати трафик.

**Време:** 2 × 45 мин

**Какво изграждаш:** `revisor`, откриваем по име вътре в клъстера, и неговия спътник, тестовата услуга, също откриваема, така че отчетът най-сетне да проверява някого наистина

**Какво научаваш:** какво е Service от тип `ClusterIP` и защо това е типът по подразбиране; как селектор по етикети решава до кои обекти Pod стига трафикът и къде се записва това решение (`EndpointSlice`); веригата от три порта, `port`, `targetPort` и `containerPort`; как DNS на клъстера разрешава имена и защо само `revisor` работи; `kubectl port-forward` към `127.0.0.1`; и Pod за отстраняване на грешки, за да гледаш отвътре, когато образът няма *shell*

**Откъде идваш.** От [Урок 2](02-pods-deployments.md): `revisor` работи с три реплики в Deployment, с пълния си `securityContext` и `emptyDir` в `/datos`. Знаеш, че всеки Pod има свой IP адрес и че той се сменя всеки път, когато Pod се роди отново, и видя, че образът на `revisor` няма *shell*, нито `curl`. От [Урок 0](00-que-es-kubernetes.md) носиш две имена, които досега бяха само имена: `kube-proxy`, от който има по един на всеки възел, и `coredns`, който работи на контролния възел. В този урок и двата се захващат за работа.

**Какво не прави този урок.** `revisor` остава откриваем **вътре** в клъстера, а за теб — през временен тунел (`port-forward`). Не остава публикуван навън: `LoadBalancer` и входна точка с Gateway API са [Урок 6](06-entrar-al-cluster.md). Още не се ограничава и кой с кого може да говори: днес всеки Pod в клъстера стига до `revisor`, а [Урок 7](07-aislar-permisos-red.md) поставя мрежата в режим „всичко забранено по подразбиране“ (default-deny). И обектът Service праща трафик към всеки Pod, който работи, изправен или не: да кажеш на клъстера кога един Pod е готов да получава трафик е работа на probes от [Урок 5](05-salud-recursos-apagado.md).

**За изпълненията.** Всички изходи в този урок са получени на 21 октомври 2026 г. с `kind` v0.33.0, `kubectl` v1.37.1 и образа на възел `kindest/node:v1.37.0`, фиксиран чрез отпечатъка си, в клъстера от три възела от Урок 1, който тук се нарича `curso-k8s-l3`. Машината беше Mac с процесор ARM и Docker Engine 29.2.1 във виртуална машина с Linux (Colima), а **не** Linux Mint, който е референтната система на курса. Какво се променя в твоя Mint: архитектурата (`amd64` вместо `arm64`), IP адресите на обектите Pod и на обектите Service, случайните наставки в имената, възрастите, на кой възел попада всяка реплика, портът, който Docker дава на контролния възел, и колко заявки се падат на всяка реплика в 3.8. Командите са същите. Цялата обиколка е в [`programas/03-services-dns/`](../programas/03-services-dns): `correr.sh` създава клъстера, зарежда му образите, оставя `revisor` така, както го остави Урок 2, минава през урока по ред, изпълнява Упражнения 1 до 3 и изтрива клъстера; отне 2 минути и 16 секунди (последният ред на изхода го казва: `la corrida completa tardó 136 s`), от които създаването на клъстера и изчакването да е готов бяха 46 секунди. Изходът му е `correr.salida.txt`. Там разделът за навика за сигурност се появява преди този за грешката, защото скриптът ги изпълнява в този ред. `port-forward` използва порт `18080` на твоята машина; ако е зает, скриптът спира, преди да създаде каквото и да е, и ти казва как да избереш друг (`PUERTO_LOCAL=18081 ./correr.sh …`). На машината, на която беше написан този урок, едновременно работеха клъстерите на други уроци и за да не се сблъска с тях, скриптът беше изпълнен с `PUERTO_LOCAL=18300`; в `correr.salida.txt` и в този урок числото е заменено с `18080` — онова, което ще използваш ти. Това е единственото, което е пипано в изхода.

## След урока ще можеш да

- Обясняваш с пример защо никоя програма не бива да пази IP адреса на Pod и какво ѝ дава вместо това един Service.
- Пишеш по памет Service `ClusterIP` с неговия `selector` и списъка му `ports` и проследяваш веригата `port` → `targetPort` → `containerPort` в конкретен случай.
- Намираш `EndpointSlice` на даден Service с `-l kubernetes.io/service-name=…` и казваш, с него в ръка, до кои обекти Pod стига трафикът.
- Разрешаваш името на Service от Pod за отстраняване на грешки и обясняваш всеки ред от неговия `/etc/resolv.conf`, включително `NXDOMAIN`, които отпечатва `nslookup`.
- Отваряш `port-forward`, който слуша само на `127.0.0.1`, и казваш кога се прекъсва.
- Предизвикваш Service без endpoints, разпознаваш го по `<unset>` и по код 7 на `curl` и го поправяш.

## Защо, преди как

В Урок 2 остави три реплики на `revisor` да работят, а раздел 2.4 завърши с предупреждение: всеки Pod има свой IP адрес и той се сменя всеки път, когато Pod се роди отново. Това е сцената от вторник. Един Pod е за еднократна употреба по замисъл. ReplicaSet го възстановява, когато умре, а заместникът е **друг** Pod, с друго име и друг адрес. Ако клиентите пазят адреса на Pod, всяко възстановяване ги оставя да говорят с никого.

Има и втора причина, по-фина. Дори обектите Pod никога да не умираха, ти имаш **три**. С кой говори клиентът? Ако избере един, другите два са излишни. Ако искаш да разпределя, ще трябва да дадеш на клиента пълния списък и да го поддържаш актуален. Точно това правеше Compose в курса по Docker, скрито: име на услуга, което мрежата на Compose разрешаваше до нейните контейнери. В Kubernetes същата идея има собствено име и собствен манифест.

**Service** отговаря на двата въпроса едновременно. Дава ти виртуален IP адрес, който не се променя, докато обектът Service съществува, а зад него — живия списък с обекти Pod, които го обслужват. Списъка не го пишеш ти: пише го контролер, въз основа на правило, което ти пишеш — **селектора**. А за да не се налага никой да знае този виртуален IP адрес, **DNS на клъстера** му дава име: `revisor`, или с пълното име, `revisor.default.svc.cluster.local`.

Урокът има девет части с понятия и след тях обичайните раздели:

1. **IP адресът на Pod не става за адрес** (3.1): какво се променя, когато Pod се роди отново.
2. **Обектът Service на `revisor`** (3.2), поле по поле.
3. **Трите порта** (3.3): `port`, `targetPort` и `containerPort`.
4. **Селектори и `EndpointSlice`** (3.4): къде се записва списъкът с обекти Pod.
5. **Pod за отстраняване на грешки** (3.5), защото `revisor` няма *shell*.
6. **DNS на клъстера** (3.6).
7. **Тестовата услуга** (3.7): `revisor` най-сетне проверява някого.
8. **Как разпределя един Service** (3.8).
9. **`port-forward`** (3.9): тунел от твоята машина, само към `127.0.0.1`.

Това е целта. В края на 3.7 който и да е Pod в клъстера иска отчета от `revisor` по неговото име, а `revisor` намира тестовата услуга също по името ѝ:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

## Ако нямаш образа от курса по Docker

Този урок използва два образа от курса по Docker: този на `revisor`, `curso-docker-revisor:1.6.0`, който предава неговият Урок 10, и този на услугата, която се проваля нарочно, `curso-docker-prueba:1.0.0`. Преди да продължиш, провери, че имаш и двата:

```text
$ docker image ls curso-docker-revisor:1.6.0 --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
curso-docker-revisor:1.6.0 bd1b2e7d91b8 16.2MB
```

За другия — същата команда с `curso-docker-prueba:1.0.0`. Ако ти липсва образът на `revisor`, изгради го от хранилището на онзи курс, с `Dockerfile` от неговия Урок 10 върху папката `programas/revisor` и с `--build-arg VERSION=1.6.0`, като му дадеш точно тага `curso-docker-revisor:1.6.0`. Ако ти липсва тестовият, изгради го от папката `programas/servicio-prueba` на същото хранилище, с таг `curso-docker-prueba:1.0.0`. [Урок 2](02-pods-deployments.md) съдържа, в същия този раздел, списъка с това, което курсът изисква от твой образ, ако предпочиташ да използваш друг.

Какво този урок изисква **допълнително** от тестовата услуга — и си струва да го прочетеш, защото всяка точка обяснява един ред от нейния манифест:

- **Слуша HTTP на порт 9000** и отговаря на `GET /` с `200`, когато е изправна, с `503`, когато е паднала, и със закъснение, когато е бавна.
- **Сменя режима си с `POST /modo/sano`, `POST /modo/lento` и `POST /modo/caido`** и казва в какъв режим е с `GET /modo`. Така можеш да я счупиш отвън, без да изграждаш нищо наново.
- **Работи като потребител 65532**, без `root`, и **понася файлова система само за четене** без том: не записва нищо на диска.

И двата се зареждат в клъстера както в Урок 2, с `kind load docker-image` и името на клъстера. Могат да се заредят и двата с една команда:

```text
$ kind load docker-image curso-docker-revisor:1.6.0 curso-docker-prueba:1.0.0 --name curso-k8s-l3
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-revisor:1.6.0" with ID "sha256:bd1b2e7d91b822f31b25e7ca52c4d0ccd5b81807695860bc13a7acf8169b2e59" not yet present on node "curso-k8s-l3-worker2", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-control-plane", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker", loading...
Image: "curso-docker-prueba:1.0.0" with ID "sha256:400d3fd59edc9ceafa87d21e2fd0ab93f92e04701a38572c4d1c6960d79012db" not yet present on node "curso-k8s-l3-worker2", loading...
```

Шест реда: два образа по три възела. (При твоето изпълнение редът на редовете може да е друг.) Обектът Pod за отстраняване на грешки от 3.5 използва трети образ, `curlimages/curl`, който **не** се зарежда: той е публичен, фиксиран е чрез отпечатъка си `sha256` и възелът, на който попадне обектът Pod, го изтегля от Docker Hub първия път. За тази стъпка ти трябва интернет.

## Понятията

### 3.1 IP адресът на Pod не става за адрес

Този урок използва собствен клъстер, `curso-k8s-l3`, с конфигурацията от три възела от Урок 1, току-що създаден. Създай го така, от корена на хранилището на курса, със същото внимание, което научи в Урок 1:

```bash
# Un kubeconfig temporal y propio: tu ~/.kube/config ni se lee ni se toca.
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l3.XXXX)/kubeconfig"
# curso-k8s-l3 NO debe aparecer aquí. Si aparece y no es tuyo, detente.
kind get clusters
kind create cluster --name curso-k8s-l3 --config programas/03-services-dns/kind-curso.yaml
# Debe decir kind-curso-k8s-l3. Si dice otra cosa, no sigas.
kubectl config current-context
```

`export` важи само в този терминал. Ако отвориш друг (в 3.9 ще ти трябва един за `port-forward`), повтори `export` със същия път, иначе `kubectl` ще говори с друг клъстер. После зареди двата образа, както се видя по-горе, и приложи Deployment от Урок 2 както си е, без да променяш и запетая; оттук нататък командите се изпълняват вътре в `programas/03-services-dns/` (влез с `cd programas/03-services-dns`, иначе `kubectl apply -f revisor-deployment.yaml` ще каже, че пътят не съществува). Изходите са от изпълнението на `correr.sh`, който прави точно това:

```text
$ kubectl config current-context
kind-curso-k8s-l3

$ kubectl apply -f revisor-deployment.yaml
deployment.apps/revisor created

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-82d87   1/1     Running   0          1s    10.244.1.2   curso-k8s-l3-worker2   <none>           <none>
revisor-697fb84f97-drv5h   1/1     Running   0          1s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          1s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
```

Първата команда е обичайният навик: преди да промениш нещо, питаш с кой клъстер говориш. Повтаряй я **преди всеки** `apply`, `delete`, `rollout restart` или `port-forward` в урока, а не само тук; скриптът го прави сам, преди всяко `kubectl`, и спира, ако отговорът не е `kind-curso-k8s-l3`. Сега погледни колоната `IP`. Трите адреса започват с `10.244.`: това е мрежата на обектите Pod, която kind изгражда по подразбиране. Неговото [ръководство за конфигурация](https://kind.sigs.k8s.io/docs/user/configuration/) го казва така: „по подразбиране kind използва подмрежата за Pod `10.244.0.0/16` за IPv4“. Всеки възел получава парче от тази мрежа: в това изпълнение обектите Pod на `worker2` са в `10.244.1.x`, а тези на `worker` — в `10.244.2.x` (кое парче се пада на всеки възел се променя от изпълнение на изпълнение).

Сега сцената от вторник, в малък мащаб. Изтрива се един:

```text
$ kubectl delete pod revisor-697fb84f97-82d87
pod "revisor-697fb84f97-82d87" deleted from default namespace

$ kubectl get pods -l app=revisor -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
revisor-697fb84f97-drv5h   1/1     Running   0          2s    10.244.2.3   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-nq74v   1/1     Running   0          2s    10.244.2.2   curso-k8s-l3-worker    <none>           <none>
revisor-697fb84f97-z79jh   1/1     Running   0          1s    10.244.1.3   curso-k8s-l3-worker2   <none>           <none>
```

ReplicaSet го възстанови за секунда, както в Урок 2 (ако изброиш обектите Pod веднага след изтриването, може да видиш стария в `Terminating` и новия в `ContainerCreating`; изчакай няколко секунди или изпълни `kubectl rollout status deployment/revisor` и ще останат три). Но новият Pod, `z79jh`, не е онзи, който умря: друго име и друг IP адрес (`10.244.1.3` вместо `10.244.1.2`). Обърни внимание, че попадна на **същия** възел, `worker2`, и въпреки това адресът се смени: не е нужно обектът Pod да се премести, за да е друг неговият IP адрес. При друго изпълнение може да попадне освен това и на друг възел. Адресът `10.244.1.2` вече не е на никого. Ако някоя програма го е пазила, от тази секунда тя говори с празен адрес. А ако след малко на `worker2` се роди друг Pod, той може да получи точно този адрес и програмата ще говори с непознат, без да разбере.

Това не е дефект на kind, нито на този клъстер: това е замисълът. Обектите Pod са, по думите на [документацията за Pods](https://kubernetes.io/docs/concepts/workloads/pods/), „сравнително ефимерни, за еднократна употреба“ същности. Онова, което трябва да е стабилно, не е обектът Pod, а **достъпът** до съвкупността от обекти Pod. Това е Service.

### 3.2 Обектът Service на `revisor`

[Документацията за Services](https://kubernetes.io/docs/concepts/services-networking/service/) го определя с едно изречение: Service е „метод за излагане на мрежово приложение, което работи като един или повече Pod в твоя клъстер“. И уточнява какво пази: всеки Service „определя логически набор от *endpoints* (обикновено тези *endpoints* са обекти Pod) заедно с политика за това как тези обекти Pod да бъдат направени достъпни“.

Това е обектът Service на `revisor`. Той е **програма**: прилага се сам и живее в `programas/03-services-dns/revisor-service.yaml`.

```yaml
# revisor-service.yaml — Lección 3: un nombre estable para las réplicas del revisor.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: http
```

Много по-кратък е от Deployment и се чете по същия начин, отвън навътре.

#### 3.2.1 Какво е и как се казва

`apiVersion: v1` и `kind: Service`: обектите Service живеят в основната група на API, същата като на обектите Pod, която няма име. `metadata.name: revisor` е името на Service и това не е подробност: **това име е, което ще пишеш в URL адресите**. DNS на клъстера (3.6) го превръща в адрес. Затова обектът Service се казва като Deployment, макар да не е задължително: Deployment се казва `revisor` за теб, а Service се казва `revisor` за клиентите. Етикетът `app: revisor` на самия Service е, както при Deployment, за да го намираш с `-l app=revisor`; той не решава нищо за трафика.

#### 3.2.2 Какъв тип Service

`type: ClusterIP` казва какъв вид адрес получава. Документацията за Services описва този тип така: „излага Service на вътрешен IP адрес на клъстера. Изборът на тази стойност прави Service достъпен само отвътре на клъстера. Това е стойността по подразбиране, която се използва, ако не зададеш `type`“. Манифестът го пише, макар да е стойността по подразбиране, по същата причина, по която Урок 2 написа `IfNotPresent`: за да не се налага онзи, който го чете, да знае правилото, и за да остане на показ решението **да не се** публикува. Същата страница казва как се публикува нещо към интернет: „с Ingress или Gateway“. Това е Урок 6. Днес, нарочно, нищо не излиза навън.

#### 3.2.3 Към кого праща трафик

`selector: {app: revisor}` е правилото: „моите обекти Pod са онези, които носят етикета `app: revisor`“. Това е същият етикет, който Deployment слага в шаблона си, и затова Service намира трите реплики. Обърни внимание какво **не** казва: не споменава Deployment, нито ReplicaSet, нито `pod-template-hash`. Обектът Service не знае, че съществува Deployment. Избира обекти Pod по етикет и нищо повече. Упражнение 2 ти показва последицата, онази, която Урок 2 ти остави анонсирана.

#### 3.2.4 През къде

`ports` е списък; тук съдържа един-единствен порт, наречен `http`. `port: 80` е портът **на Service**: онзи, който използват клиентите. `targetPort: http` е портът **на обекта Pod**, към който се препраща трафикът, и не е като число, а по **име**. Раздел 3.3 проследява тази верига с клъстера пред себе си.

#### 3.2.5 Прилагане и преглед

```text
$ kubectl apply -f revisor-service.yaml
service/revisor created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP   41s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP    2s
```

Два обекта Service. Твоят, `revisor`, получи IP адреса `10.96.144.175`. Той е от друга мрежа, `10.96.`, различна от тази на обектите Pod: ръководството на kind казва, че по подразбиране използва „подмрежата за Services `10.96.0.0/16` за IPv4“. Другият, `kubernetes`, не си го създал ти: това е обектът Service на самия `kube-apiserver`, на първия адрес от тази мрежа, за да могат обектите Pod, които трябва да говорят с API, да го намират по име като всеки друг. `EXTERNAL-IP <none>`: няма адрес навън, както беше поискано.

`kubectl describe` събира всичко за обекта Service:

```text
$ kubectl describe service revisor
Name:                     revisor
Namespace:                default
Labels:                   app=revisor
Annotations:              <none>
Selector:                 app=revisor
Type:                     ClusterIP
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.96.144.175
IPs:                      10.96.144.175
Port:                     http  80/TCP
TargetPort:               http/TCP
Endpoints:                10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

Редовете, които днес имат значение:

- `Selector: app=revisor`: правилото, което написа.
- `IP: 10.96.144.175`: стабилният адрес. Документацията го нарича *cluster IP* и обяснява, че „се използва от механизма за виртуални IP адреси“. Не принадлежи на никоя машина, нито на никой Pod; 3.8 разказва кой го кара да работи.
- `Port: http 80/TCP` и `TargetPort: http/TCP`: двата края на веригата от портове.
- `Endpoints: 10.244.2.2:8080,10.244.2.3:8080,10.244.1.3:8080`: **трите реплики**, с техния IP адрес и реалния им порт. Сравни ги с втората таблица от 3.1: това са точно тези на трите живи обекта Pod, включително `10.244.1.3` на току-що родения Pod. `10.244.1.2` на изтрития Pod не се появява. Никой не го е махнал ръчно.
- `Session Affinity: None`: всяка връзка може да отиде към която и да е реплика; 3.8 го измерва.

Този списък `Endpoints` е отговорът на сцената: клиентът използва `10.96.144.175`, който не се променя, а клъстерът поддържа актуално на кого всъщност се пада.

### 3.3 Трите порта

В сцената с Docker имаше един порт, който имаше значение: `-p 8080:8080` на `docker run`. Тук са три и всеки се декларира от различен обект. Объркването им е от най-честите грешки в началото, така че си струва да ги проследиш с клъстера пред себе си.

```text
$ kubectl get service revisor -o jsonpath='port={.spec.ports[0].port} targetPort={.spec.ports[0].targetPort}{"\n"}'
port=80 targetPort=http

$ kubectl get pods -l app=revisor -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].ports[0].name}={.spec.containers[0].ports[0].containerPort}{"\n"}{end}'
revisor-697fb84f97-drv5h http=8080
revisor-697fb84f97-nq74v http=8080
revisor-697fb84f97-z79jh http=8080

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].ports}{"\n"}'
[{"name":"http","port":8080,"protocol":"TCP"}]
```

(Вторият `jsonpath` използва `{range .items[*]}…{end}`, което повтаря средата за всеки Pod от списъка. Това е начинът да поискаш една стойност от няколко обекта наведнъж.)

Ето как се чете веригата, от клиента до програмата:

| Порт | Къде се декларира | Стойност в `revisor` | Кой го използва |
|---|---|---|---|
| `port` | обектът Service | `80` | клиентът: `http://revisor/…` отива на 80, порта по подразбиране на HTTP |
| `targetPort` | обектът Service | `http` (име) | клъстерът, за да знае към кой порт на обекта Pod да препраща |
| `containerPort` | шаблонът на Pod, с името си | `http` = `8080` | онзи, който търси името `http` в обекта Pod; програмата слуша на 8080 сама по себе си |

Третата команда показва как беше разрешено името: `EndpointSlice` (3.4) вече съдържа числото, `8080`, което е взел от обектите Pod. Документацията за Services описва двете части, които правят това възможно. Първата: „Service може да съпостави всеки входящ `port` с `targetPort`. По подразбиране и за удобство `targetPort` има същата стойност като полето `port`“. Втората: „дефинициите на портове в обектите Pod имат имена и можеш да се позоваваш на тези имена в атрибута `targetPort` на Service“.

Защо курсът използва името, а не числото? Защото така числото живее на **едно-единствено място** — шаблона на Pod. Ако един ден `revisor` слуша на друг порт, сменяш `containerPort` в Deployment и обектът Service продължава да работи, без да го пипаш. С `targetPort: 8080` ще трябва да помниш да смениш два файла, а в деня, в който забравиш единия, обектът Service праща трафик към порт, на който никой не слуша. Упражнение 1 ти показва точно как изглежда това.

Едно пояснение, което предотвратява често объркване: Урок 2 каза, че `containerPort` **не публикува нищо**. Това продължава да е вярно. Програмата слуша на 8080, дори да не го декларираш. Декларирането с име служи, за да може обектът Service да го сочи по това име, и за да знае онзи, който чете манифеста, къде слуша.

А портът 80 на Service? Не го отваря нито `revisor`, нито някой друг процес: той е част от виртуалния адрес на Service. Програмата продължава да слуша на своя 8080, с всички ограничения от Урок 2, а клъстерът превежда. Така клиентите пишат `http://revisor/` без номер и никой не е трябвало да сменя порта на програмата, за да се постигне това.

### 3.4 Селектори и `EndpointSlice`

#### 3.4.1 Къде се записва списъкът

Списъкът `Endpoints`, който показа `describe`, не се пази в обекта Service. Той живее в друг обект, **EndpointSlice**. [Документацията за EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/) го обобщава: „EndpointSlices водят сметка за IP адресите на *endpoints* на даден *backend*. Обикновено са свързани с Service, а *endpoints* обикновено са обекти Pod“.

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.2.3,10.244.1.3   3s
```

Обърни внимание как беше потърсен: не по име (`revisor-6jh2f` носи случайна наставка, като Pod), а по етикета `kubernetes.io/service-name=revisor`. Същата страница обяснява защо съществува този етикет: всеки EndpointSlice носи препратка към собственика си и „етикет `kubernetes.io/service-name`, който позволява лесно да се намерят всички EndpointSlices, принадлежащи на даден Service“. Това е същата идея от Урок 2: търси се по етикет, никога по име, което се променя.

Защо „всички“? Защото един Service може да има няколко. Документацията казва, че по подразбиране контролната равнина създава EndpointSlices „с не повече от 100 *endpoints* всеки“. При три реплики всичко се побира в един; при триста ще има поне три. Затова таблицата по-горе е списък, макар днес да има само един ред.

С `jsonpath` се вижда всеки *endpoint* отвътре, както и собственикът му:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.2.3 revisor-697fb84f97-drv5h curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}{"\n"}'
Service/revisor
```

Всеки ред казва кой адрес, на кой Pod (`targetRef`), на кой възел и дали е готов. А собственикът на EndpointSlice е обектът Service, със същото поле `ownerReferences` от Урок 2. Това е същата верига на собствениците: ако изтриеш обекта Service, отива си и неговият EndpointSlice.

#### 3.4.2 Кой го пише

Никой не го пише ръчно. Документацията за отстраняване на проблеми с Services го разказва така: „вътре в Kubernetes има контролен цикъл, който оценява селектора на всеки Service и записва резултата в един или повече обекти EndpointSlice“ ([„Debug Services“](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)). Това отново е термостатът от Урок 0, с друго желано състояние: „този Service праща трафик към обектите Pod, които съвпадат с неговия селектор“. Когато съвкупността от обекти Pod се промени, контролерът коригира списъка.

Вижда се, като се изтрие още един Pod:

```text
$ kubectl delete pod revisor-697fb84f97-drv5h
pod "revisor-697fb84f97-drv5h" deleted from default namespace

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name} {.nodeName} ready={.conditions.ready}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v curso-k8s-l3-worker ready=true
10.244.1.3 revisor-697fb84f97-z79jh curso-k8s-l3-worker2 ready=true
10.244.1.4 revisor-697fb84f97-mjbff curso-k8s-l3-worker2 ready=true
```

Обектът Pod `drv5h` и неговият `10.244.2.3` излязоха от списъка, а влезе новият Pod, `mjbff`, с `10.244.1.4`. Същият EndpointSlice, ново съдържание. Обектът Service не се промени с нищо: неговият IP адрес продължава да е `10.96.144.175`. В това е цялата идея.

#### 3.4.3 Какво означава `ready=true`

Колоната `ready` е онази, която решава дали един *endpoint* получава трафик. Документацията за EndpointSlices казва, че условието `serving` показва, че *endpoint* обслужва, и че за Pod то „съответства на условието `Ready` на обекта Pod“; и че `ready` по същество е „`serving` и не `terminating`“. В превод: един Pod получава трафик, докато е готов и не се изключва.

Днес „готов“ означава малко: `revisor` няма probes, така че неговият Pod се отбелязва като готов веднага щом контейнерът стартира, макар програмата още да не слуша. Затова Урок 5 е този, който допълва тази колона: с readiness probe обектът Pod се отбелязва като готов само когато `/salud` отговаря, а обектът Service спира да му праща трафик, ако престане да отговаря.

#### 3.4.4 `Endpoints`, старият API

В ръководствата ще срещнеш командата `kubectl get endpoints`. Тя още работи, но виж какво казва:

```text
$ kubectl get endpoints revisor
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS                                         AGE
revisor   10.244.1.3:8080,10.244.1.4:8080,10.244.2.2:8080   6s
```

`Endpoints` е предишният API и самият сървър те предупреждава: „остарял от v1.33; използвай EndpointSlice“. Документацията за Services го отбелязва по същия начин („Deprecated since Kubernetes v1.33“) и дава причините: не става за клъстери с IPv4 и IPv6 едновременно, не носи информацията, която искат новите функции, и „съкращава списъка с *endpoints*, ако е твърде дълъг, за да се побере в един обект“. Този курс използва EndpointSlice. `Endpoints` е остарял, не премахнат: продължава да работи, както току-що видя, но вече не е препоръчваният API. Споменава се тук, за да го разпознаваш, когато го видиш, което е правилото на курса за остарялото и премахнатото: споменава се, за да се разпознава, не се преподава.

### 3.5 Pod за отстраняване на грешки

#### 3.5.1 Защо е нужен

За да изпробваш обекта Service, ти трябва клиент **вътре** в клъстера, защото един `ClusterIP` е достъпен само оттам. Очевидният кандидат би бил самият `revisor`, но в Урок 2 видя, че образът му няма *shell*, нито `curl`: `kubectl exec deployment/revisor -- sh` се проваля с `executable file not found in $PATH`. Това е защита и курсът няма да я маха, за да отстранява грешки. Изходът е друг: отделен Pod, направен за гледане, който се създава, когато е нужен, и се изтрива накрая.

Той е **програма**: `programas/03-services-dns/depurar.yaml`.

```yaml
# depurar.yaml — Lección 3: un Pod de depuración con curl, que se borra al terminar.
# Ya cumple el nivel «restricted» (Lección 7), para que sirva igual en el espacio
# de nombres revisor. La imagen va fijada por su huella.
apiVersion: v1
kind: Pod
metadata:
  name: depurar
  labels:
    app: depurar
    acceso-revisor: permitido
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
  - name: depurar
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

#### 3.5.2 Поле по поле

Това е самостоятелен Pod, нарочно: в Урок 2 научи, че Pod без собственик не се ражда отново, и тук точно това искаш. Когато го изтриеш, остава изтрит. Останалото:

- **Образът** е `curlimages/curl`, малък образ с `curl` и основните инструменти на Alpine Linux (`sh`, `nslookup`, `cat`), които идват от BusyBox. Фиксиран е чрез отпечатъка си `sha256`, а не само чрез тага си `8.22.0`. Един таг може да бъде преместен към друг образ в регистъра; отпечатък — не. Тъй като този образ наистина се изтегля от интернет, отпечатъкът идентифицира по съдържание манифеста на образа, така че твоят клъстер ще изтегли същите слоеве, които са изпробвани тук, дори някой да премести тага `8.22.0` в регистъра.
- **`imagePullPolicy` не е написан.** За разлика от `revisor`, този манифест не го декларира: с таг, който не е `:latest`, стойността по подразбиране е `IfNotPresent`, същата, която Урок 2 написа на показ. Тук се оставя стойността по подразбиране.
- **`command: ["sleep", "3600"]`** заменя програмата на образа, която би била `curl`, приключващ веднага, с изчакване от един час. Така обектът Pod остава жив и можеш да му пращаш команди с `kubectl exec`. С `restartPolicy: Never`, когато часът изтече, обектът Pod приключва и не се рестартира.
- **`securityContext`** е същият модел като на `revisor`, с потребител 100 и група 101 — онези, които носи образът на curl. Това, че един Pod е „само за отстраняване на грешки“, не е оправдание да работи като `root`: забравеният Pod за отстраняване на грешки е точно онзи, който някой намира по-късно.
- **`resources`** слага долна граница и таван за CPU и памет. Обясняват се в Урок 5; тук са, защото един помощен Pod не бива да може да изяде възела.
- **`automountServiceAccountToken: false`** не позволява да се монтират идентификационните данни за API, които Урок 2 намери в `revisor`. `curl` не се нуждае от тях. Урок 7 обобщава това.
- **Етикетът `acceso-revisor: permitido`** още не прави нищо. В Урок 7, когато мрежата бъде затворена, той ще е ключът, който позволява на този Pod да говори с `revisor`. Слага се още от днес, за да служи един и същ файл и в двата урока.

#### 3.5.3 Първи контакт

```text
$ kubectl apply -f depurar.yaml
pod/depurar created

$ kubectl get pod depurar -o wide
NAME      READY   STATUS    RESTARTS   AGE   IP           NODE                  NOMINATED NODE   READINESS GATES
depurar   1/1     Running   0          29s   10.244.2.4   curso-k8s-l3-worker   <none>           <none>

$ kubectl exec depurar -- id
uid=100(curl_user) gid=101(curl_group) groups=101(curl_group)

$ kubectl exec depurar -- curl -s http://revisor/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl exec depurar -- curl -s http://10.96.144.175/salud
{"estado":"vivo","version":"1.6.0"}
```

`id` потвърждава потребител 100. А последните две заявки са сърцето на урока. Първата използва **името** на Service, без порт (80 е портът по подразбиране на HTTP) и без да знае нищо за обектите Pod. Втората използва IP адреса на Service. И двете стигат до реплика на `revisor`, която отговаря на своя `/salud` с версията `1.6.0`. Никой не е написал IP адрес на Pod никъде. Това, че името `revisor` се превърна в `10.96.144.175`, е работа на DNS на клъстера и това следва.

### 3.6 DNS на клъстера

#### 3.6.1 Кой отговаря

Всеки Pod знае кого да пита за имена, защото `kubelet` му записва `/etc/resolv.conf` при създаването му:

```text
$ kubectl exec depurar -- cat /etc/resolv.conf
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

Три реда. Средният казва кого да пита: `10.96.0.10`. Този адрес е в мрежата на обектите Service и това не е случайно:

```text
$ kubectl get service -n kube-system kube-dns
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   74s

$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-cf8pv   1/1     Running   0          65s   10.244.0.2   curso-k8s-l3-control-plane   <none>           <none>
coredns-559f6c778d-h2hgl   1/1     Running   0          65s   10.244.0.4   curso-k8s-l3-control-plane   <none>           <none>
```

DNS на клъстера сам по себе си е **Service със селектор**: `kube-dns`, в пространството от имена `kube-system`, порт 53 (този на DNS), който праща въпросите към двата Pod на `coredns`, които видя в Урок 0. Точно моделът, който току-що написа за `revisor`. Ако утре един от `coredns` падне, неговият Service остава на `10.96.0.10` и другият отговаря. Kubernetes използва собствените си части, за да реши собствения си проблем.

(`-n kube-system` казва на `kubectl` в кое пространство от имена да търси. Досега всичко живееше в `default`. Пространствата от имена се изучават в Урок 7.)

#### 3.6.2 Пълното име на един Service

[Документацията за DNS за Services и Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/) дава формата на името: обикновеният Service получава запис с име във формата `mi-servicio.mi-espacio.svc.dominio-del-cluster`, който „се разрешава до *cluster IP* на Service“. За твоя:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

Чете се отляво надясно, от частното към общото:

| Част | Какво е |
|---|---|
| `revisor` | името на обекта Service |
| `default` | пространството от имена, в което живее |
| `svc` | че е Service (а не нещо друго) |
| `cluster.local` | домейнът на клъстера, този по подразбиране |

А отговорът, `10.96.144.175`, е IP адресът на обекта Service, този от 3.2. DNS не ти дава IP адресите на обектите Pod: дава ти стабилния адрес, а за разпределянето се грижи обектът Service.

#### 3.6.3 Защо само `revisor` работи

В 3.5 написа `http://revisor/salud`, а не пълното име, и сработи. Това го прави възможно първият ред на `resolv.conf`, `search`. Документацията за DNS го обяснява: заявките „могат да бъдат разширени с помощта на `/etc/resolv.conf` на обекта Pod“ и „стойностите на опцията `search` се използват за разширяване на заявките“. Онзи, който разширява, не е обектът Pod, а DNS библиотеката на програмата, която пита. Когато `curl` пита за `revisor`, библиотеката му добавя, един по един, домейните от `search`: `revisor.default.svc.cluster.local`, `revisor.svc.cluster.local` и `revisor.cluster.local`, и спира при първия, който отговори. Тук първият вече отговаря. В 3.6.4 ще видиш, че `nslookup` от този образ не спира: пита за всички едновременно.

Третият ред, `options ndots:5`, решава **кога** се използва този списък. Ръководството за отстраняване на проблеми с Services го казва така: редът `options` „трябва да задава `ndots` достатъчно високо, за да може твоята DNS библиотека да взема предвид пътищата за търсене“, а Kubernetes го слага на 5 по подразбиране, „достатъчно високо, за да покрие всички имена, които генерира“. На практика: име с по-малко от пет точки се пробва първо със списъка `search`. `revisor` няма нито една, така че се разширява. Затова работи и междинната форма, с пространството от имена:

```text
$ kubectl exec depurar -- curl -s http://revisor.default/salud
{"estado":"vivo","version":"1.6.0"}
```

`revisor.default` плюс `svc.cluster.local`, вторият елемент на `search`, дава пълното име. Документацията го поставя като правило: заявките, които не казват пространство от имена, „се ограничават до пространството от имена на обекта Pod“; за да стигнеш до Service от друго пространство, пишеш пространството в името. Днес всичко живее в `default` и това не се забелязва. От Урок 7 нататък, когато `revisor` се премести в собствено пространство, `revisor.revisor` ще е начинът да бъде достигнат извън него.

#### 3.6.4 `NXDOMAIN`, които не са грешка

Сега попитай `nslookup` за краткото име:

```text
$ kubectl exec depurar -- nslookup revisor
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find revisor.cluster.local: NXDOMAIN

Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175

** server can't find revisor.svc.cluster.local: NXDOMAIN


** server can't find revisor.cluster.local: NXDOMAIN

** server can't find revisor.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

Изглежда като катастрофа: четири „не намирам“ и изходен код 1. Прочети го бавно. Сред тях е правилният отговор: `revisor.default.svc.cluster.local` е `10.96.144.175`. Четирите `NXDOMAIN` (*non-existent domain*, „това име не съществува“) са **другите** разширения от списъка `search`: `revisor.svc.cluster.local` и `revisor.cluster.local` не съществуват, и това е вярно — не съществуват. Всяко се появява два пъти, защото `nslookup` от този образ, този на BusyBox, пита за всяко име две неща: неговия IPv4 адрес (запис `A`) и неговия IPv6 адрес (запис `AAAA`). За пълното име, което съществува, също е попитал и за двете; тъй като обектът Service няма IPv6 адрес, вторият въпрос се връща без записи и това не се отпечатва като грешка (име, което съществува, но няма такъв тип запис, е различно от име, което не съществува). Отпечатва всеки неуспех и, ако е имало такъв, завършва с код 1, макар да е намерил отговора. Редът на редовете се променя от изпълнение на изпълнение, защото въпросите излизат едновременно: при друго изпълнение на същия този урок отговорът излезе накрая, след четирите `NXDOMAIN`.

`curl` не се оплаква от нищо от това, защото го интересува само да намери **един** адрес, и го намери. Практическият урок: с `nslookup` питай за пълното име; в този образ излиза чисто, както видя в 3.6.2. Внимавай защо: не е, че правилото го гарантира. С `ndots:5` дори `revisor.default.svc.cluster.local` (четири точки) се брои за „кратко“ от библиотека, която спазва правилото буквално, и това е точно известната цена на `ndots:5`: излишни заявки дори с пълното име. Това, че излиза чисто, е измереното поведение на този `nslookup`. За да е едно име абсолютно и никога да не се разширява, завърши го с точка: `revisor.default.svc.cluster.local.` А ако видиш `NXDOMAIN` с краткото име, потърси реда `Name:`, преди да се разтревожиш.

За сравнение, ето как изглежда име, което наистина не съществува:

```text
$ kubectl exec depurar -- nslookup no-existe.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

** server can't find no-existe.default.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
[código de salida: 1]
```

Без ред `Name:` и без `Address:` накрая. Това отсъствие е разликата, не `NXDOMAIN`.

### 3.7 Тестовата услуга: `revisor` най-сетне проверява някого

От Урок 2 насам `revisor` има записано в манифеста си `REVISOR_SERVICIOS=prueba http://prueba:9000/ 2s`. Този ред вече беше обещание за този урок: иска от него да проверява услуга на име `prueba` на `http://prueba:9000/`, с ограничение от 2 секунди. Този URL използва **име**, а не IP адрес. Виж какво става днес, преди това име да съществува:

```text
$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        4ms  no responde: Get "http://prueba:9000/": dial tcp: lookup prueba on 10.96.0.10:53: no such host
```

`revisor` си върши работата добре: казва, че `prueba` се проваля, и защо. `lookup prueba on 10.96.0.10:53: no such host`: попитал е DNS на клъстера (`10.96.0.10` от 3.6) за `prueba` и DNS е отговорил, че не съществува. Няма Pod, няма Service, няма име.

Това са двата манифеста на тестовата услуга. И двата са **програми**: `prueba-deployment.yaml` и `prueba-service.yaml`.

```yaml
# prueba-deployment.yaml — Lección 3: el servicio que falla a propósito.
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
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
```

```yaml
# prueba-service.yaml — Lección 3: el nombre «prueba» que el revisor consulta.
apiVersion: v1
kind: Service
metadata:
  name: prueba
  labels:
    app: prueba
spec:
  type: ClusterIP
  selector:
    app: prueba
  ports:
  - name: http
    port: 9000
    targetPort: http
```

Deployment е моделът от Урок 2, със същия `securityContext` и **една** реплика: това е тестова услуга, не е нужно повече. Няма том, защото не записва нищо на диска. Обектът Service има една разлика с този на `revisor`, която си струва да се отбележи: тук `port` е `9000`, същият като на контейнера, защото така го изисква URL адресът, който `revisor` вече има записан (`http://prueba:9000/`). `targetPort` продължава да е по име. Правилото не е „Service винаги на 80“: портът на Service е онзи, който очакват клиентите ти.

```text
$ kubectl apply -f prueba-deployment.yaml -f prueba-service.yaml
deployment.apps/prueba created
service/prueba created

$ kubectl get services
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
kubernetes   ClusterIP   10.96.0.1       <none>        443/TCP    79s
prueba       ClusterIP   10.96.236.7     <none>        9000/TCP   3s
revisor      ClusterIP   10.96.144.175   <none>        80/TCP     40s

$ kubectl exec depurar -- curl -s http://prueba:9000/modo
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

`OK`, за 1 милисекунда, с код `200`. `revisor` не беше рестартиран, конфигурацията му не беше променена, не му беше даден никакъв IP адрес. Манифестът му казваше `prueba` от самото начало; единственото, което се промени, е, че сега това име съществува. Всеки път, когато `revisor` сглобява отчета си, пита отново за името. Това беше нужно на сцената от вторник: конфигурацията казва **кого**, а не **къде е**.

Сега се чупи нарочно, в трите си режима:

```text
$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/caido
modo: caido

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA        1ms  codigo 503

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/lento
modo: lento

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    FALLA     2.002s  se acabo el tiempo de espera

$ kubectl exec depurar -- curl -s -X POST http://prueba:9000/modo/sano
modo: sano

$ kubectl exec depurar -- curl -s 'http://revisor/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK           1ms  200
```

Всеки режим разказва нещо различно. В `caido` `prueba` отговаря, но с `503`: `revisor` казва `FALLA codigo 503`. В `lento` `prueba` се бави повече от 2-те секунди, които ѝ дава списъкът, и `revisor` се отказва на `2.002s` с `se acabo el tiempo de espera`. (Състоянието `LENTO` на `revisor` е за услуга, която отговаря правилно, но се бави повече от 1 секунда, **без** да надвиши ограничението; тук го надвиши.) А в `sano` всичко се връща към `OK`. Трите случая минаха през обекта Service и през DNS на клъстера и `revisor` ги различи.

С това `revisor` прави вътре в клъстера същото, което правеше в Compose в курса по Docker. Таблицата за превод от Урок 0 го предвиждаше: името на услугата в мрежата на Compose става DNS на клъстера.

### 3.8 Как разпределя един Service

#### 3.8.1 Измерване

Обектът Service има три реплики зад себе си. Използва ли и трите? Измерва се с тридесет заявки и журнала на `revisor`, който записва по един ред за всяка заявка, която обслужва:

```text
$ kubectl exec depurar -- sh -c 'for i in $(seq 1 30); do curl -s -o /dev/null http://revisor/salud; done; echo 30 peticiones'
30 peticiones

$ kubectl logs -l app=revisor --prefix --tail=-1 | grep 'GET /salud' | cut -d' ' -f1 | sort | uniq -c
   6 [pod/revisor-697fb84f97-mjbff/revisor]
  13 [pod/revisor-697fb84f97-nq74v/revisor]
  14 [pod/revisor-697fb84f97-z79jh/revisor]
```

Втората команда съчетава няколко инструмента и си струва да я разглобим:

- `kubectl logs -l app=revisor` иска журнала на **всички** обекти Pod с този етикет, не на един;
- `--prefix` поставя пред всеки ред обекта Pod, от който е дошъл;
- `--tail=-1` иска целия журнал (със селектор по етикет `kubectl logs` по подразбиране показва само последните редове на всеки Pod);
- `grep` оставя редовете на `/salud`, `cut` — префикса, а `sort | uniq -c` брои колко има от всеки Pod.

Трите реплики получиха трафик. Сборът е 33, а не 30, защото трите заявки към `/salud` от 3.5 и 3.6 също са в журнала. А разпределението не е равномерно: 14, 13 и 6. Не е задължително да бъде.

#### 3.8.2 Кой върши работата

IP адресът на Service не го притежава никоя машина. [Справочникът за виртуалните IP адреси](https://kubernetes.io/docs/reference/networking/virtual-ips/) казва кой го кара да работи: „компонентът `kube-proxy` отговаря за реализирането на механизъм за виртуални IP адреси за обектите Service“. `kube-proxy` работи на всеки възел (трите, които видя в Урок 1), чете обектите EndpointSlice и записва правила в мрежата на възела. Когато пакет излезе към `10.96.144.175:80`, тези правила го отклоняват към IP адреса и порта на реален Pod, например `10.244.1.4:8080`.

Как избира обекта Pod? Същият справочник казва, че режимът по подразбиране в Linux, за Kubernetes 1.37, е `iptables` и че в този режим правилата „по подразбиране избират *backend* Pod на случаен принцип“. Случайно, а не на смени. При тридесет хвърляния разпределение 14, 13 и 6 е напълно възможно. При много повече заявки всяка реплика би се доближила до една трета. А `Session Affinity: None` от `describe` е онова, което позволява тази случайност: справочникът обяснява, че ако искаш един и същ клиент винаги да отива към един и същ Pod, можеш да зададеш `sessionAffinity: ClientIP`, а стойността по подразбиране е `None`. `revisor` не пази нищо между заявките, така че не се нуждае от това.

Това има последица, която е добре да знаеш още отсега: обектът Service разпределя **връзки**, а не заявки. Всеки `curl` от цикъла отваря нова връзка и затова всеки попада където му се падне. Клиент, който преизползва една-единствена връзка за много заявки, говори винаги с един и същ Pod, докато тази връзка е жива.

### 3.9 `port-forward`: тунел от твоята машина

Всичко дотук се случи **вътре** в клъстера. А ти, от своя терминал? IP адресът `10.96.144.175` не върши работа извън клъстера (разделът за навика за сигурност го проверява). За да изпробваш от машината си, без да публикуваш нищо, съществува `kubectl port-forward`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &
Forwarding from 127.0.0.1:18080 -> 8080

$ curl -s http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ curl -s 'http://127.0.0.1:18080/api/estados?formato=tabla'
SERVICIO  ESTADO    TIEMPO  DETALLE
prueba    OK            0s  200
```

Чете се така: слушай на порт `18080` на моята машина, само на адреса `127.0.0.1`, и препращай каквото пристигне към порт `80` на обекта Service `revisor`. `&` накрая го оставя да работи във фонов режим, за да можеш да използваш същия терминал. Докато работи, всеки път, когато му направиш заявка, `kubectl` ще отпечатва `Handling connection for 18080` в този терминал: това е нормално. Спираш го с `kill %1` или като го извадиш на преден план с `fg` и `Ctrl+C`. Ако предпочиташ да го оставиш в отделен терминал, спомни си казаното в 3.1: в този нов терминал първо същото `export KUBECONFIG=…` и `kubectl config current-context`, който трябва да казва `kind-curso-k8s-l3`.

Прочети внимателно първия му ред: `Forwarding from 127.0.0.1:18080 -> 8080`. Не казва `-> 80`. `kubectl` преведе `80` на обекта Service в неговия `targetPort`, а него — в `8080` на обекта Pod, и отвори тунела **директно към един Pod**. [Справочникът за `kubectl port-forward`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/) го казва още в първото си изречение: „препраща един или повече локални порта към Pod“. И добавя: когато му дадеш ресурс като Deployment или Service, `kubectl` избира един Pod; „ако има няколко съвпадащи Pod, се избира един автоматично. Сесията за препращане приключва, когато избраният Pod приключи, и командата трябва да се изпълни отново“. Тоест: `port-forward service/revisor` **не** разпределя като обекта Service. Използва обекта Service само за да намери един Pod. Упражнение 3 ти показва какво става, когато този Pod си отиде.

А `--address 127.0.0.1`? Справочникът казва, че стойността по подразбиране на `--address` е `localhost`, с която `kubectl` се опитва да слуша на `127.0.0.1` и на `::1` (адреса на собствената ти машина в IPv6). Курсът пише `127.0.0.1`: един-единствен адрес, на показ, по същата причина, по която пише `type: ClusterIP`. Решението да не се отваря тунелът към мрежата остава записано и никой не трябва да знае стойността по подразбиране. Същият справочник съдържа сред примерите си `--address 0.0.0.0`, който слуша „на всички адреси“. Това би превърнало лаптопа ти във входна точка към този Pod за всеки в твоята мрежа, без парола и с твоите идентификационни данни за клъстера отзад. Проверява се какво е отворил тунелът:

```text
$ lsof -nP -iTCP:18080 -sTCP:LISTEN | awk '{print $1, $8, $9, $10}'
COMMAND NODE NAME 
kubectl TCP 127.0.0.1:18080 (LISTEN)
```

Един-единствен процес, `kubectl`, който слуша на `127.0.0.1:18080` и никъде другаде. (`lsof` изброява кой държи отворен даден порт; `awk` оставя четири колони, за да се побере. В Linux Mint работи по същия начин; можеш да използваш и `ss -ltnp | grep 18080`.)

`port-forward` е за изпробване, не за обслужване. Живее, докато живеят командата и сесията ти, зависи от твоите идентификационни данни за клъстера и се прекъсва, когато обектът Pod, който е избрал, си отиде. Истинското публикуване на `revisor`, през входна точка с име, е Урок 6.

## Грешката, която ще видиш

Грешката в този урок е от най-честите при обектите Service и самото ръководство за отстраняване на проблеми я споменава като такава: Service, чийто селектор не избира никого. Предизвиква се с `fig03_01.selector-malo.yaml`, **програма**, която се проваля нарочно: същият Service на `revisor` с една буква по-малко.

```yaml
# fig03_01.selector-malo.yaml — FALLA A PROPÓSITO: el mismo Service del revisor
# con una letra de menos en el selector (revisr). Se aplica encima del bueno, el
# Service se queda sin a quién mandar tráfico y curl sale con código 7. Se
# corrige volviendo a aplicar revisor-service.yaml.
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisr
  ports:
  - name: http
    port: 80
    targetPort: http
```

Преди да го приложиш, `kubectl config current-context` трябва да казва `kind-curso-k8s-l3`.

```text
$ kubectl apply -f fig03_01.selector-malo.yaml
service/revisor configured
```

`configured`: `kube-apiserver` прие промяната, без да се оплаче, и е прав. Селекторът `app: revisr` е напълно валиден; просто не съвпада с нищо. Kubernetes не може да знае, че си искал да напишеш `revisor`.

**Дай на клъстера миг.** Преди да изпробваш, провери дали EndpointSlice вече е празен: `kubectl get endpointslices -l kubernetes.io/service-name=revisor` трябва да казва `<unset>` в колоната `ENDPOINTS`. Ако изпробваш в същата секунда на `apply`, `kube-proxy` още не е разбрал за промяната, `curl` отговаря, сякаш нищо не е станало, и ще повярваш, че грешката „не се е появила“. Скриптът прави точно това: изчаква списъкът да се изпразни и едва тогава изпробва. След това се разчита по ред, както в Урок 2.

**Първо, симптомът.** От обекта Pod за отстраняване на грешки, като поискаш от `curl` да каже колко време е отнело:

```text
$ kubectl exec depurar -- curl -s -m 3 -o /dev/null -w 'tardó %{time_total} s\n' http://revisor/salud
tardó 0.001120 s
command terminated with exit code 7
[código de salida: 7]
```

(`-o /dev/null` изхвърля отговора, който тук няма, а `-w` иска от `curl` да напише накрая общото време на заявката.) `-m 3` слага ограничение от 3 секунди, за да не чака безкрайно; не се наложи: отне една хилядна от секундата. Код 7 според [списъка с грешки на curl](https://curl.se/libcurl/c/libcurl-errors.html) е „не можа да се свърже с *хоста*“ (*Failed to connect() to host or proxy*). Не е 6, „не можа да разреши *хоста*“: името беше разрешено. И не е 28, „времето изтече“: връзката не остана да чака, някой я отказа веднага. Това разграничение вече ти казва къде да гледаш.

**Второ, DNS.** Щом името е разрешено, DNS не е проблемът. Проверява се:

```text
$ kubectl exec depurar -- nslookup revisor.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	revisor.default.svc.cluster.local
Address: 10.96.144.175
```

Името продължава да съществува и продължава да дава същия IP адрес. Обектът Service е там. Онова, което липсва, е някой зад него.

**Трето, *endpoints*.** Това е решаващата стъпка:

```text
$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS     ENDPOINTS   AGE
revisor-6jh2f   IPv4          <unset>   <unset>     51s

$ kubectl describe service revisor | grep -E '^(Selector|Endpoints):'
Selector:                 app=revisr
Endpoints:                
```

`ENDPOINTS <unset>`: обектът EndpointSlice продължава да съществува, но празен, без адреси и без портове. `describe` го потвърждава с празен `Endpoints:` и, един ред по-горе, показва причината: `Selector: app=revisr`. Ръководството за отстраняване на проблеми с Services го казва почти с тези думи: ако списъкът с *endpoints* е празен, „провери дали полето `spec.selector` на твоя Service наистина избира стойностите от `metadata.labels` на твоите обекти Pod. Честа грешка е правописна грешка“.

**Четвърто, селекторът срещу етикетите.** Проверява се със същия селектор, който е точно инструментът от Урок 2:

```text
$ kubectl get pods -l app=revisr
No resources found in default namespace.

$ kubectl get pods -l app=revisor
NAME                       READY   STATUS    RESTARTS   AGE
revisor-697fb84f97-mjbff   1/1     Running   0          48s
revisor-697fb84f97-nq74v   1/1     Running   0          53s
revisor-697fb84f97-z79jh   1/1     Running   0          52s
```

Нула обекта Pod с `app=revisr`, три с `app=revisor`, и трите `Running`. Обектите Pod са в отлично състояние. Обектът Service търси други.

**Защо код 7, а не изтичане на времето.** При празен списък `kube-proxy` няма накъде да прати връзката. Измереното е кодът, 7, и времето, една хилядна от секундата: връзката не чака до ограничението от 3 секунди, а беше отказана веднага щом излезе. (В режим `iptables` `kube-proxy` поставя правило за отказ за обектите Service без *endpoints*. Това е поведението, наблюдавано при това изпълнение, а не нещо, което документацията обещава.) Това е същият сигнал като в Упражнение 1, по различна причина: там обектът Service има към кого да прати трафик, но към грешния порт. Онова, което отделя единия случай от другия, е колоната `ENDPOINTS`.

**Поправката** е на причината, не на обекта Pod: прилагаш отново добрия файл.

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   53s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

Трите адреса се върнаха в същия EndpointSlice (`revisor-6jh2f`, чиято възраст продължи да се брои: не беше изтрит, нито беше създаден друг), а `revisor` отговаря. Обърни внимание на реда на поправката: скриптът изчака да види трите адреса в EndpointSlice, преди да изпробва с `curl`. Това е същото предупреждение от началото, наобратно: между това да приложиш поправения Service и всеки `kube-proxy` да обнови правилата си минава миг, и проба, направена точно в този момент, може още да се провали, макар поправката вече да е направена. Първо се проверява дали списъкът е пълен; после се изпробва.

**Редът, за всеки Service, който не отговаря:**

1. Какъв код дава `curl`? 6 е името, 7 е отказ, 28 е мълчание.
2. Разрешава ли се пълното име?
3. Има ли адреси неговият EndpointSlice?
4. Ако няма, съвпада ли неговият `Selector` с етикетите на обектите Pod (`get pods -l …`)?
5. Ако има, портът от колоната `PORTS` ли е онзи, на който слуша програмата?

## Навикът за сигурност от урока: нищо не се публикува просто така

Таблицата с навици на курса възлага на този урок три неща: по подразбиране `ClusterIP`; нищо не се публикува просто така; `port-forward` само към `127.0.0.1`. И трите се проверяват с клъстера пред себе си.

**Един `ClusterIP` не се вижда от твоята машина.** От твоя терминал, извън клъстера, същият IP адрес, който обектът Pod за отстраняване на грешки използва без проблем:

```text
$ curl -s -m 3 http://10.96.144.175/salud
[código de salida: 28]
```

Код 28: „времето за изчакване изтече“. Твоята машина няма собствен маршрут към `10.96.0.0/16`: пакетът излиза по маршрута ти по подразбиране, към твоя модем или мрежата на офиса ти, които не знаят нищо за клъстера, и никой не отговаря. (Ако твоята мрежа използва адреси `10.96.x.x`, може да получиш друг отговор, от машина, която няма нищо общо с клъстера; още повече основание — този IP адрес не е твой извън него.) `10.96.144.175` има смисъл само в правилата, които `kube-proxy` записва **вътре** във възлите.

**Възлите не публикуват нищо от `revisor`.** Всеки възел на kind е контейнер на Docker, а Docker казва кои портове публикува всеки от тях:

```text
$ docker port curso-k8s-l3-control-plane
6443/tcp -> 127.0.0.1:59190

$ docker port curso-k8s-l3-worker

$ docker port curso-k8s-l3-worker2
```

Контролният възел публикува един-единствен порт, `6443` на `kube-apiserver`, и само към `127.0.0.1` (числото от твоята страна kind го избира на случаен принцип; на твоята машина ще е друго). Това е входната точка, през която говори твоят `kubectl`, и Урок 1 я видя. Двата работни възела, на които работи `revisor`, не публикуват **нищо**: редовете им излизат празни. Няма никакъв път от твоята мрежа до порт 8080 на `revisor`. Така трябва да бъде до Урок 6, който отваря входна точка с име и казва какво минава през нея.

**Тунелът слуша само на твоята машина.** Вече го видя в 3.9: `kubectl`, който слуша на `127.0.0.1:18080` и никъде другаде.

Защо има значение: всеки отворен път към дадена услуга е път, който някой може да използва. В истински клъстер рефлексът „ще го сменя на `NodePort`, за да пробвам“ или „ще му сложа `--address 0.0.0.0`, за да го види колегата ми“ оставя отворено онова, което никой не помни да затвори. Правилото на курса е обратното: всичко се ражда затворено, всяко отваряне е решение, записано в манифест, и има своя урок.

**Какво защитава и какво не.** Един `ClusterIP` не позволява `revisor` да бъде достигнат **отвън** клъстера. Не забранява нищо **вътре**: всеки Pod от всяко пространство от имена може да говори с него, както направи `depurar`, който няма нищо общо с `revisor`. Не криптира и трафика между обектите Pod: той върви по чист HTTP през мрежата на обектите Pod. Ограничаването на това кой с кого говори е работа на `NetworkPolicy` от Урок 7. Криптирането се обсъжда в Урок 6.

## Какво се прави погрешно

**Да пазиш IP адреса на Pod в конфигурацията.** Това е сцената от вторник. Работи, докато обектът Pod не се роди отново. Винаги името на Service.

**Да пазиш IP адреса на Service вместо името му.** Той е стабилен, докато обектът Service съществува, но ако го изтриеш и го създадеш отново, получава друг. Името оцелява след това; IP адресът — не.

**Да пишеш `targetPort` като число, когато контейнерът има име.** Работи днес и те задължава да поддържаш същото число в два файла. В деня, в който единият се промени, обектът Service праща трафик към порт, на който никой не слуша (Упражнение 1).

**Да сменяш на `NodePort` или `LoadBalancer`, „за да пробваш“.** За пробване има `port-forward`, който не отваря нищо към мрежата. Публикуването е решение на Урок 6, а не пряк път.

**Да отваряш `port-forward` с `--address 0.0.0.0`.** Излага порта на този Pod на всеки, който достига до машината ти, без парола, с твоите идентификационни данни за клъстера, докато командата е жива.

**Да използваш `port-forward`, сякаш е Service.** Говори с **един** Pod, не разпределя и пада, когато този Pod си отиде (Упражнение 3). Служи за гледане, не за обслужване.

**Да отвориш друг терминал и да забравиш `export KUBECONFIG`.** В новия терминал `kubectl` говори с клъстера, който казва твоят `~/.kube/config`, а той може да е всеки друг. Първо `export`, после `kubectl config current-context` и едва тогава командата.

**Да се тревожиш от `NXDOMAIN` на `nslookup`.** При краткото име това са разширенията от `search`, които не съществуват. Потърси реда `Name:` или питай за пълното име.

**Да даваш на самостоятелен Pod етикетите от селектора на Service.** Deployment не го осиновява, но обектът Service го използва и му праща трафик (Упражнение 2).

**Да изпробваш веднага след промяна на Service и да правиш изводи.** Както при чупенето, така и при поправката: първо колоната `ENDPOINTS`; после `curl`.

**Да махнеш `securityContext` от обекта Pod за отстраняване на грешки, „защото е временен“.** Временното се забравя, а забравен Pod като `root` е отворена врата. Този от курса вече отговаря на нивото `restricted`.

## Упражнения

Първите три се изпълняват в клъстера на урока, по ред и от състоянието, в което остана след поправката на грешката. Преди всяко упражнение `kubectl config current-context` трябва да казва `kind-curso-k8s-l3`; ако казва нещо друго, не продължавай. `correr.sh` ги изпълнява по същия начин, а изходът му е в `correr.salida.txt`. **Преди** да изпълниш всяко, запиши в [дневника](bitacora.md) какво мислиш, че ще стане. Четвъртото се пише със собствени думи.

### Упражнение 1 — `targetPort`, на който никой не слуша

`fig03_02.puerto-malo.yaml` е същият Service на `revisor` с правилен селектор и една-единствена разлика: `targetPort: 8081`, число, вместо `http`.

```yaml
# fig03_02.puerto-malo.yaml — Ejercicio 1: el selector está bien, pero el
# targetPort apunta a un número donde el revisor no escucha (8081 en lugar del
# 8080 que se llama «http»). Pregunta: ¿el Service tiene endpoints? ¿Responde?
apiVersion: v1
kind: Service
metadata:
  name: revisor
  labels:
    app: revisor
spec:
  type: ClusterIP
  selector:
    app: revisor
  ports:
  - name: http
    port: 80
    targetPort: 8081
```

Преди да го приложиш, предвиди: колко адреса ще има EndpointSlice? Какво ще казва колоната му `PORTS`? Какъв код ще даде `curl -s -m 3 http://revisor/salud` от `depurar`? После го приложи, изчакай няколко секунди колоната `PORTS` да се промени (скриптът чака пет), провери и обясни по какво прилича и по какво се различава този провал от онзи в „Грешката, която ще видиш“. Накрая приложи отново `revisor-service.yaml`.

### Упражнение 2 — Обектът Pod, който се промъква в Service

`fig03_03.colado.yaml` е `revisor-extra` от Упражнение 2 на Урок 2: самостоятелен Pod, идентичен с репликите, **с** етикета `app: revisor` и с порт, наречен `http`. В Урок 2 видя, че Deployment не го осиновява. Сега има Service, който избира по `app: revisor`.

Предвиди: колко реплики казва Deployment? Колко адреса има EndpointSlice на `revisor`? Ако пратиш 40 заявки към `http://revisor/salud`, колко горе-долу се падат на `revisor-extra`? Приложи го, провери с `kubectl get deployment revisor`, с `jsonpath` от 3.4 (адрес и `targetRef.name`) и с `kubectl logs revisor-extra | grep -c 'GET /salud'` след цикъла от 3.8 с 40 заявки. После обясни какво би станало с този Pod в деня, в който смениш образа на Deployment. Накрая провери контекста и го изтрий: `kubectl delete pod revisor-extra`.

### Упражнение 3 — Тунелът и *rollout*

Отвори отново `port-forward` от 3.9 и провери, че `curl -s -m 3 http://127.0.0.1:18080/salud` отговаря. Предвиди: ако сега изпълниш `kubectl rollout restart deployment/revisor` и изчакаш да приключи, същият `curl` ще продължи ли да отговаря? Направи го и прочети какво е написал `port-forward` в своя терминал. Обясни какво се случи с изречението от справочника за `kubectl port-forward`, което цитира 3.9.

### Упражнение 4 — Четирите `NXDOMAIN`

Колежка изпълнява `kubectl exec depurar -- nslookup revisor`, вижда четири реда `server can't find … NXDOMAIN` и изходен код 1 и заключава, че „DNS на клъстера е счупен“. В най-много пет изречения ѝ отговори: откъде идват тези имена, защо всяко се появява два пъти, защо кодът е 1, как в същия изход се разпознава, че името все пак е разрешено, и каква команда би ѝ дал, за да го провери без шум.

## Решения

### Решение 1

Измерено в `correr.salida.txt`:

```text
$ kubectl apply -f fig03_02.puerto-malo.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8081    10.244.2.2,10.244.1.4,10.244.1.3   59s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
command terminated with exit code 7
[código de salida: 7]
```

**Три адреса, порт `8081` и `curl` с код 7.** Селекторът е правилен, така че EndpointSlice има трите реплики. Но колоната му `PORTS` казва `8081`: с число клъстерът не търси нищо в обекта Pod, взема числото както си е. Връзката стига до правилния IP адрес на реален Pod, на порт, на който `revisor` не слуша, и обектът Pod я отказва: код 7, „не можа да се свърже“.

Прилича на грешката от урока по симптома: същият код 7. Различава се по колоната `ENDPOINTS`: там беше `<unset>` (няма към кого), тук е пълна (има към кого, но през грешния порт). Затова редът на диагностиката гледа първо адресите и после порта. Ръководството за отстраняване на проблеми с Services пита точно това: „правилен ли е `targetPort` за твоите обекти Pod?“. И това е аргументът в полза на `targetPort: http`: с името тази грешка не може да се напише, без да се промени и Deployment.

При повторното прилагане на добрия:

```text
$ kubectl apply -f revisor-service.yaml
service/revisor configured

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor
NAME            ADDRESSTYPE   PORTS   ENDPOINTS                          AGE
revisor-6jh2f   IPv4          8080    10.244.2.2,10.244.1.4,10.244.1.3   64s

$ kubectl exec depurar -- curl -s -m 3 http://revisor/salud
{"estado":"vivo","version":"1.6.0"}
```

`PORTS 8080`: името `http` отново беше разрешено до порта на обектите Pod.

### Решение 2

Измерено в `correr.salida.txt`:

```text
$ kubectl apply -f fig03_03.colado.yaml
pod/revisor-extra created

$ kubectl get deployment revisor
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
revisor   3/3     3            3           69s

$ kubectl get endpointslices -l kubernetes.io/service-name=revisor -o jsonpath='{range .items[0].endpoints[*]}{.addresses[0]} {.targetRef.name}{"\n"}{end}'
10.244.2.2 revisor-697fb84f97-nq74v
10.244.1.4 revisor-697fb84f97-mjbff
10.244.1.3 revisor-697fb84f97-z79jh
10.244.2.6 revisor-extra

$ kubectl exec depurar -- sh -c 'for i in $(seq 1 40); do curl -s -o /dev/null http://revisor/salud; done; echo 40 peticiones'
40 peticiones

$ kubectl logs revisor-extra | grep -c 'GET /salud'
12

$ kubectl delete pod revisor-extra
pod "revisor-extra" deleted from default namespace
```

**Deployment казва `3/3`, обектът Service има четири адреса, а на `revisor-extra` се паднаха 12 от 40.** Deployment не го брои, по причината, която видя в Урок 2: неговият ReplicaSet търси и `pod-template-hash`. Обектът Service го брои, защото търси само `app: revisor`, а `revisor-extra` го носи. За Service това е още една реплика: появява се в неговия EndpointSlice и получава своя дял от трафика на случаен принцип. При четири *endpoints* очакваното е около 10 от 40, а 12 е близо. При твоето изпълнение ще е друго число и няма значение какво: важното е, че не е нула.

В деня, в който смениш образа на Deployment, *rollout* заменя трите реплики, а `revisor-extra` остава със стария образ, защото не е на никого. Обектът Service ще продължи да му праща своя дял от трафика и част от потребителите ти ще виждат предишната версия, без нито един `kubectl get deployment` да те предупреди. Това е предупреждението от Урок 2 за припокриващите се селектори, сега с истински трафик.

### Решение 3

Измерено в `correr.salida.txt`:

```text
$ kubectl port-forward --address 127.0.0.1 service/revisor 18080:80 &

$ curl -s -m 3 http://127.0.0.1:18080/salud
{"estado":"vivo","version":"1.6.0"}

$ kubectl rollout restart deployment/revisor
deployment.apps/revisor restarted

$ kubectl rollout status deployment/revisor --timeout=180s
Waiting for deployment "revisor" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "revisor" rollout to finish: 1 old replicas are pending termination...
deployment "revisor" successfully rolled out

$ curl -s -m 3 http://127.0.0.1:18080/salud
[código de salida: 52]
```

(Изходът на `rollout status` е съкратен: в `correr.salida.txt` всеки ред се повтаря няколко пъти, както в Урок 2.) А ето какво написа `port-forward`:

```text
Forwarding from 127.0.0.1:18080 -> 8080
Handling connection for 18080
Handling connection for 18080
E1021 07:23:02.902759   47411 portforward.go:549] "An error occurred forwarding" err="error forwarding port 8080 to pod 0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb, uid : network namespace for sandbox \"0fca0827e49054df03968556e140e1217908dcc55efd6d20e7210aa4479c36eb\" is closed" localPort=18080 remotePort=8080
error: lost connection to pod
```

**`curl` след *rollout* се проваля с 52**, което в списъка с грешки на curl е „сървърът не върна нищо“. Тунелът не отиваше към обекта Service: отиваше към **един** Pod, избран при отварянето му. `rollout restart` замени трите обекта Pod, включително този. Следващата връзка стигна до тунела, тунелът се опита да я препрати към Pod, чиято мрежа вече беше затворена (`network namespace for sandbox … is closed`), и `kubectl` се отказа: `error: lost connection to pod`. Точно това казва справочникът: „сесията за препращане приключва, когато избраният Pod приключи, и командата трябва да се изпълни отново“. Междувременно обектът Service запази адреса и селектора си за клиентите отвътре на клъстера: онзи, който падна, беше твоят тунел. Този урок не измери дали вътрешен клиент губи някоя заявка по време на *rollout*: `revisor` все още няма readiness probes, нито подредено изключване, а това идва в Урок 5; Урок 9 го измерва с истинско натоварване. Затова `port-forward` е за гледане и затова не става за публикуване на каквото и да е.

### Решение 4

Един възможен отговор: „Тези имена са другите разширения от списъка `search` в `/etc/resolv.conf`: към `revisor` се добавя всеки домейн от списъка, а `revisor.svc.cluster.local` и `revisor.cluster.local` наистина не съществуват. Всяко излиза два пъти, защото `nslookup` на BusyBox пита за IPv4 и за IPv6 адреса на всяко име. Отпечатва всеки неуспех и завършва с код 1, ако е имало такъв, макар да е намерил отговора. Доказателството, че името е разрешено, е в същия изход: редът `Name: revisor.default.svc.cluster.local` с неговия `Address`. За да го провериш без шум: `kubectl exec depurar -- nslookup revisor.default.svc.cluster.local`, който в този образ излиза чисто.“

## Изтриване на клъстера

Когато приключиш с упражненията, изтрий клъстера на урока. Не оставяй нищо живо на машината. Ако си оставил отворен `port-forward` в друг терминал, спри го преди това с `Ctrl+C`.

```text
$ kind delete cluster --name curso-k8s-l3
Deleting cluster "curso-k8s-l3" ...
Deleted nodes: ["curso-k8s-l3-control-plane" "curso-k8s-l3-worker" "curso-k8s-l3-worker2"]

$ kind get clusters | grep -c curso-k8s-l3
0
```

`--name` е задължителен и тук: без него kind би изтрил клъстера с име `kind`, който може да е на друг човек или от друг проект. След това изтрий временната папка на `kubeconfig` (онази, която създаде `mktemp`, с префикса `/tmp/curso-k8s-l3.`; там са администраторските идентификационни данни за клъстера) или затвори този терминал. Клъстерът за следващия урок се създава от нулата, точно като този.

## Как разбирам, че съм успял

- [ ] Обясняваш, с изхода от 3.1 пред себе си, защо IP адресът на Pod не става за адрес и какво се променя, когато клиентът използва името на Service.
- [ ] Пишеш по памет Service `ClusterIP` със `selector` и `ports`, а в този на `revisor` казваш кое е `port`, кое `targetPort`, кое `containerPort` и каква стойност има всяко.
- [ ] Намираш EndpointSlice на всеки Service с `kubectl get endpointslices -l kubernetes.io/service-name=<nombre>` и казваш, по адресите му, до кои обекти Pod стига трафикът.
- [ ] Обясняваш всеки ред от `/etc/resolv.conf` на Pod и защо `revisor`, `revisor.default` и `revisor.default.svc.cluster.local` водят до едно и също място.
- [ ] При `curl` с код 7 срещу Service проверяваш по ред името, колоната `ENDPOINTS` и порта и различаваш зле написан селектор от зле написан `targetPort`.
- [ ] Отваряш `port-forward`, който слуша само на `127.0.0.1`, проверяваш го с `lsof` (или `ss` в Linux Mint) и казваш защо пада при *rollout*.
- [ ] Изпълняваш `programas/03-services-dns/correr.sh > /tmp/mi-corrida-l3.txt 2>&1` и сравняваш `/tmp/mi-corrida-l3.txt` с `programas/03-services-dns/correr.salida.txt` (не пренасочвай към този файл: той е еталонът) по онова, което не се променя между изпълненията: три възела `Ready` на `v1.37.0`; шест реда `not yet present on node … loading...`; обектът Service `revisor` като `ClusterIP` на `80/TCP` с `EXTERNAL-IP <none>`; `TargetPort: http/TCP` и три `Endpoints` на `8080`; EndpointSlice с `PORTS 8080`, три адреса и собственик `Service/revisor`; предупреждението `v1 Endpoints is deprecated in v1.33+`; `uid=100(curl_user)`; `{"estado":"vivo","version":"1.6.0"}` по име и по IP адрес; `resolv.conf` с трите му реда; `kube-dns` на `10.96.0.10`; `lookup prueba … no such host` преди създаването на тестовата услуга, а след това `OK … 200`, `FALLA … codigo 503` и `FALLA … se acabo el tiempo de espera`; трите реплики с поне по една заявка в 3.8; `Forwarding from 127.0.0.1:18080 -> 8080` и `kubectl TCP 127.0.0.1:18080 (LISTEN)`; код 28 от твоята машина; двата работни възела без публикувани портове; код 7 с лошия селектор, за хилядни от секундата, и `<unset>` в неговия EndpointSlice; `PORTS 8081` и код 7 в Упражнение 1; четири адреса с `revisor-extra` в Упражнение 2; код 52 и `lost connection to pod` в Упражнение 3; `sin diferencias con los archivos`; и накрая `0` клъстера `curso-k8s-l3` и редът `la corrida completa tardó … s`. IP адресите, наставките в имената, възрастите, портът, който публикува контролният възел, на кой възел попада всеки Pod, редът на редовете от `kind load` и от `nslookup`, точното разпределение на заявките, времената и колко пъти се повтаря всеки ред от `rollout status` се променят при всяко изпълнение: наблюдават се, не се сравняват. Ако си използвал друг порт с `PUERTO_LOCAL`, ще видиш това число вместо `18080`.
- [ ] Накрая `kind get clusters` вече не показва `curso-k8s-l3`.

## Обобщение

Отговори, без да поглеждаш урока:

1. Защо не бива да се пази IP адресът на Pod в конфигурацията на друга програма? Какво се промени в обекта Pod от 3.1 освен IP адреса?
2. Какво прави Service от тип `ClusterIP`, откъде е достъпен и защо е типът по подразбиране, който този курс въпреки това пише?
3. В обекта Service на `revisor` какво е `port`, какво е `targetPort` и откъде идва `8080`? Защо `targetPort` е по име?
4. Кой обект пази списъка с обекти Pod на даден Service, кой го пише и с какъв етикет го намираш?
5. Какво е `kube-dns`, на какъв IP адрес е и защо толкова прилича на твоя Service?
6. Кои три реда има `/etc/resolv.conf` на Pod и какво прави всеки от тях?
7. Как `kube-proxy` избира към коя реплика да прати една връзка, в режима по подразбиране?
8. Кои кодове на `curl` различават „не разреши името“, „отказа връзката“ и „не отговори навреме“?
9. С колко обекта Pod говори `kubectl port-forward service/revisor` и какво става с него при *rollout*?

## Източници

Всички са консултирани на 21 октомври 2026 г.

- [Kubernetes, „Service“](https://kubernetes.io/docs/concepts/services-networking/service/): какво е Service; типът `ClusterIP` като стойност по подразбиране и достъпен само отвътре на клъстера; `targetPort`, равен на `port` по подразбиране; портовете с име; *cluster IP*; API `Endpoints`, остарял от v1.33, и защо.
- [Kubernetes, „EndpointSlices“](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/): какво пази един EndpointSlice; етикетът `kubernetes.io/service-name` и препратката към собственика му; таванът от 100 *endpoints* на EndpointSlice; условията `serving`, `terminating` и `ready`.
- [Kubernetes, „DNS for Services and Pods“](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/): формата на името на Service; заявките без пространство от имена, ограничени до това на обекта Pod; `/etc/resolv.conf` със `search` и `ndots:5`.
- [Kubernetes, „Debug Services“](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/): контролният цикъл, който попълва обектите EndpointSlice; селекторът с правописна грешка като честа грешка; въпросите за `targetPort`; и защо `ndots` е 5.
- [Kubernetes, „Virtual IPs and Service Proxies“](https://kubernetes.io/docs/reference/networking/virtual-ips/): `kube-proxy` като отговорен за виртуалните IP адреси; `iptables` като режим по подразбиране в Kubernetes 1.37 и случайният избор на Pod; `sessionAffinity` и стойността му по подразбиране `None`.
- [Kubernetes, „kubectl port-forward“](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/): че препраща към Pod; автоматичният избор на Pod и краят на сесията, когато този Pod приключи; `--address` и стойността му по подразбиране `localhost`; примерът с `0.0.0.0`.
- [Kubernetes, „Pods“](https://kubernetes.io/docs/concepts/workloads/pods/): обектите Pod като ефимерни същности за еднократна употреба.
- [kind, „Configuration“](https://kind.sigs.k8s.io/docs/user/configuration/): подмрежите по подразбиране за обектите Pod (`10.244.0.0/16`) и за обектите Service (`10.96.0.0/16`) и `kindnetd` като мрежа по подразбиране.
- [kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster): `kind load docker-image` с `--name`.
- [curl, „libcurl error codes“](https://curl.se/libcurl/c/libcurl-errors.html): значението на изходните кодове 6, 7, 28 и 52.

---

**Следващ:** [Урок 4 — Конфигурация и тайни](04-configuracion-secretos.md)
