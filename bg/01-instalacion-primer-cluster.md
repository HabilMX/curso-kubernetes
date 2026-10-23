# Урок 1 — Инсталиране на kubectl и kind; първият ти клъстер

Вторник, 8:20 сутринта. В десет трябва да покажеш `revisor`, работещ в клъстер, а на лаптопа ти няма дори `kubectl`. Търсиш „как се инсталира kind“ и първият блог ти дава два реда: един `curl` към адрес, който завършва на `latest`, и един `sudo mv`. Копираш ги. Колега ти праща по чата „kubectl-а, който работи при мен“ — файл без версия и без произход. Ползваш и него. В 8:50 `kind create cluster` отпечатва колона от зелени отметки, включително `✓ Joining worker nodes`. Отдъхваш си. В 9:30 първият Deployment остава наполовина и откриваш, че клъстерът ти от три възела има само един. Не знаеш каква версия на всеки инструмент имаш, нито откъде е дошъл двоичният файл от чата, нито защо два възела, които „се присъединиха“, не съществуват. А остават тридесет минути.

Нищо от това не беше лош късмет. Бяха три решения, които никой не взе: коя версия да се инсталира, как да разбереш, че двоичният файл е този, за който се представя, и кой лимит на системата трябва да се увеличи, преди да създадеш клъстера. Този урок ги взема вместо теб, едно по едно, и ти оставя клъстер, който умееш да създаваш, разглеждаш, изтриваш и създаваш отново за по-малко от половин минута, щом образът на възела вече е на диска ти (първия път трябва да се изтегли, а това зависи от връзката ти).

**Време:** 90 мин

**Какво изграждаш:** клъстера на курса. Един контролен възел и два работни, създадени с `kind` от конфигурационен файл, който фиксира образа на възела чрез неговия отпечатък. Преди това — `kubectl` и `kind`, инсталирани с фиксирана версия и проверена контролна сума, и лимитът на `inotify`, измерен и настроен. Програмите са в [`programas/01-instalacion-primer-cluster/`](../programas/01-instalacion-primer-cluster).

**Какво научаваш:** какво инсталираш и къде работи всяка част; защо версията се фиксира, вместо да се сваля „последната“; какво е контролна сума `sha256`, как се проверява и какво да правиш, когато не съвпада; какво е `inotify`, как се измерва и защо клъстер от три възела го изчерпва; какво е `kubeconfig` и какво е контекст; как да създадеш, разгледаш, изтриеш и създадеш отново клъстера и как да възстановиш контекста, ако го загубиш

**Откъде идваш.** От [Урок 0](00-que-es-kubernetes.md) носиш картата. Един клъстер има контролна равнина и работни възли. `kubectl` говори с `kube-apiserver` и с нищо друго. kind сглобява клъстер от възли, които са контейнери на Docker, всички върху едно и също ядро на твоята машина. И видя две предупреждения, които тук стават практика: при лимит на `inotify` от 128 клъстер от три възела не стартира, дори kind да казва, че е успял, а без контекст `kubectl` не знае с кого да говори. От [курса по Docker](https://www.habil.mx/bg/courses/docker/) носиш Docker Engine, инсталиран в твоя Linux Mint, и потребителя си в групата `docker`.

**Какво не прави този урок.** Не разгръща нищо в клъстера: `revisor` идва в [Урок 2](02-pods-deployments.md). Не инсталира Docker: това го направи Урок 1 от курса по Docker. Не използва мениджъри на пакети (`apt`, `snap`, Homebrew) за `kubectl` и `kind`, а в 1.2 се казва защо. Не обяснява още обектите, които виждаш в `kube-system`: само ги разглежда.

**За изпълненията.** Изходите са получени на 21 октомври 2026 г. на Mac с процесор ARM, с Docker Engine 29.2.1 във виртуална машина Ubuntu 24.04.4, която стартира Colima. **Не** на Linux Mint, който е референтната система на курса. За да знаеш откъде идва всеки изход, всеки от тях има един от тези етикети:

| Етикет | Какво означава |
|---|---|
| **Реално изпълнение · Mac** | Изпълнено на Mac. Двоичните файлове за Linux бяха изтеглени и контролната им сума беше проверена там, във временна папка, която беше изтрита накрая. Клъстерът също беше създаден от Mac. |
| **Реално изпълнение · Ubuntu 24.04 amd64** | Изпълнено в еднократен контейнер с Ubuntu 24.04 за `amd64`, основата на Linux Mint 22 на компютър с Intel или AMD. Там контролните суми бяха проверени със `sha256sum` на GNU, както в твоя Mint, а двоичните файлове бяха инсталирани и изпълнени. Контейнерът беше изтрит при излизане. |
| **Реално изпълнение · виртуална машина** | Изпълнено във виртуалната машина на Colima, където живее ядрото, което Docker използва на Mac. Там беше измерен `inotify`. |
| **Реално изпълнение · контейнер без привилегии** | Изпълнено в еднократен контейнер, който не може да променя ядрото. Там бяха изпробвани защитите на настройката на `inotify`, без да се настройва нищо. |

Какво се променя в твоя Mint. Командите `install` и настройката на `inotify` са със `sudo` и променят системата ти наистина (на Mac не беше променено нищо). Колоната `KERNEL-VERSION` ще показва твоето ядро и `amd64`. IP адресите, портът на API сървъра и наставките на обектите Pod ще са други. Има още една разлика и тя е поучителна. На Mac `kind version` казва `go1.27.0 darwin/arm64`: този `kind` е компилиран от Homebrew, а не от проекта, и затова компилаторът е различен. Това е точно онова, което този урок избягва в твоя Mint: твоят ще е официалният двоичен файл, проверен с контролната му сума, и ще казва `go1.26.7 linux/amd64`, както в изпълнението в Ubuntu от 1.3.5.

## След урока ще можеш да

- Изтегляш `kubectl` v1.37.1 и `kind` v0.33.0 от официалния им източник, проверяваш контролната им сума `sha256` и разпознаваш съобщението `FAILED`, когато не съвпада.
- Измерваш лимитите на `inotify` на ядрото си със `sysctl`, настройваш ги постоянно с файл в `/etc/sysctl.d/` и обясняваш защо три възела на kind ги изчерпват.
- Създаваш клъстера на курса с временен собствен `kubeconfig` и проверяваш с `kubectl get nodes`, че трите възела са `Ready`, без да се доверяваш на отметките.
- Четеш `kubeconfig` с `kubectl config view --minify` и казваш кой клъстер, кой потребител и кой контекст съдържа.
- Проверяваш активния контекст преди една команда и го сменяш с `use-context` или с `--context`.
- Изтриваш клъстера, създаваш го отново и възстановяваш контекста му с `kind export kubeconfig`, ако си го загубил.

## Защо, преди как

Инсталирането на две програми изглежда най-скучното в курса. Не е така, защото в този урок се решава **кой софтуер работи с твоя потребител и със `sudo` на твоята машина**, а това има последствия.

`kubectl` ще държи в ръцете си администраторското удостоверение на клъстера ти. В Урок 0 видя, че потребителят на kind е `kubernetes-admin`, от групата `kubeadm:cluster-admins`. `kind` пък създава привилегировани контейнери в твоя Docker. Подменен двоичен файл на който и да е от двата би имал достъп до целия ти клъстер и до машината ти. Затова не е достатъчно „нещо, което се казва `kubectl` и работи“. Трябва да е **точно онзи** `kubectl`, който е публикувал проектът Kubernetes, във версията, която си поискал. Контролната сума е начинът да го провериш за секунда.

Втората причина е възпроизводимостта. Ако колежката ти и ти инсталирате „последната“, всяка от вас има тази, която е била последна в деня, в който я е свалила. След три месеца някой изход от курса не съвпада с твоя и никой не знае защо. Kubernetes пуска нова минорна версия около три пъти годишно ([kubernetes.io, „Kubernetes Release Cycle“](https://kubernetes.io/releases/release/)). Фиксирането на версията превръща „при мен работи“ в нещо, което може да се сравни.

Третата е тази, която видя в сцената: **клъстер на kind от три възела зависи от лимит на ядрото**, който в Ubuntu и в Mint е нисък по подразбиране. Ако не го увеличиш преди това, kind не те предупреждава. Казва ти, че всичко е минало добре.

Урокът върви в този ред:

1. **Какво ще инсталираш** и къде работи всяка част (1.1).
2. **Фиксиране на версията** (1.2).
3. **Изтегляне и проверка на контролната сума**, с грешката нарочно (1.3).
4. **Настройката на `inotify`**: измерване, настройване и поглед колко изразходва клъстерът (1.4).
5. **Файлът на клъстера**, с фиксиран образ (1.5).
6. **Създаване на клъстера** със собствен `kubeconfig` (1.6).
7. **Контексти и `kubeconfig`** (1.7).
8. **Разглеждане на клъстера** (1.8).
9. **Изтриване, повторно създаване и възстановяване** (1.9).

Това е крайната цел, последната команда на урока, след като изтриеш клъстера и го създадеш отново за 26 секунди:

```text
$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

## Понятията

### 1.1 Какво ще инсталираш

#### 1.1.1 Частите

| Част | Какво е | Къде работи | Инсталираш ли я тук? |
|---|---|---|---|
| Docker Engine | двигателят, който изпълнява контейнерите | твоят Mint | не, вече го имаш от курса по Docker |
| `kind` | програма, която създава и изтрива клъстери, направени от контейнери | твоят Mint | **да**, един-единствен двоичен файл |
| образ `kindest/node` | „машината“ на всеки възел: Debian със `systemd`, `kubelet` и `containerd` | вътре в Docker | не, `kind` я изтегля първия път |
| `kubectl` | клиентът, който говори с `kube-apiserver` | твоят Mint | **да**, един-единствен двоичен файл |
| клъстерът | три контейнера с Kubernetes вътре | вътре в Docker | **създаваш** го с `kind` |

Двете неща, които инсталираш, са **по един файл**. Нито `kubectl`, нито `kind` включват библиотеки, услуги или *daemon*-и. Те са двоични файлове на Go, които се копират в една папка от `PATH` и толкова. Затова инсталирането е кратко и затова е добре да се прави ръчно: виждаш точно какво влиза в системата ти.

#### 1.1.2 Защо не с `apt` или `snap`

Ubuntu, а оттам и Mint, предлага `kubectl` чрез `snap`, а има и хранилища на `apt` на проекта Kubernetes. Работят, но имат проблем за този курс: **решават версията вместо теб** и я обновяват, когато им дойде редът. Един `snap` се обновява сам във фонов режим. Хранилище на `apt` те премества на нова версия при следващия `apt upgrade`. В курс, в който всеки изход се сравнява с твоя, искаш версията да се променя **когато ти решиш**. Официалната страница за инсталиране на `kubectl` предлага директния двоичен файл като първа възможност и той е този, който се използва тук ([kubernetes.io, „Install and Set Up kubectl on Linux“](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)). Бързото ръководство на kind прави същото с двоичния файл на изданието ([kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/)).

### 1.2 Фиксиране на версията

#### 1.2.1 Версиите на курса

| Инструмент | Версия | Откъде |
|---|---|---|
| `kubectl` | **v1.37.1** | `dl.k8s.io`, сайтът за изтегляне на проекта Kubernetes |
| `kind` | **v0.33.0** | изданието v0.33.0 в GitHub (`kubernetes-sigs/kind`) |
| образ на възела | `kindest/node:v1.37.0` с неговия отпечатък | бележките към изданието v0.33.0 на kind |

Официалното ръководство за `kubectl` използва един трик: пита коя е стабилната версия в `https://dl.k8s.io/release/stable.txt` и изтегля нея. На 21 октомври 2026 г. този файл казваше `v1.37.1`, същата като в курса. Но **утре може да казва друга** и командата от ръководството ще изтегли друга, без да те предупреди. Затова програмите от този урок записват пълната версия в адреса, без да питат.

#### 1.2.2 Защо `kubectl` 1.37.1 с клъстер 1.37.0?

Това са две различни числа и Урок 0 вече ги раздели. Клъстерът изпълнява това, което съдържа образът на възела, `v1.37.0`. `kubectl` е инструментът на твоята машина. Официалната политика е ясна: „трябва да използваш версия на `kubectl`, която е в рамките на една минорна версия разлика спрямо твоя клъстер. Например клиент v1.37 може да комуникира с контролни равнини v1.36, v1.37 и v1.38“ ([kubernetes.io, „Install and Set Up kubectl on Linux“](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/); [„Version Skew Policy“](https://kubernetes.io/releases/version-skew-policy/)). Patch версията, третото число, не се брои за това правило.

### 1.3 Изтегляне и проверка на контролната сума

#### 1.3.1 Какво е контролна сума `sha256`

Контролната сума `sha256` е число от 256 бита, което се записва с 64 шестнайсетични знака (от `0` до `9` и от `a` до `f`) и се изчислява от **всички** байтове на един файл. Има две свойства, които я правят полезна. Винаги дава едно и също за един и същ файл. А ако се промени един-единствен байт, излиза напълно различно число, без прилика с предишното. Няма практичен начин да се изработи друг файл, който да даде същата сума.

Проектът публикува заедно с всеки двоичен файл и неговата сума. Ти теглиш двата, изчисляваш сумата на двоичния файл, който ти е пристигнал, и я сравняваш с публикуваната. Ако съвпадат, файлът, който имаш, е, байт по байт, този, който проектът е публикувал с тази сума. Ако не, нещо се е променило по пътя: прекъснато изтегляне, остарял *mirror*, файл от друга версия или променен файл. Във всеки от тези случаи **не се инсталира**.

Трябва да сме честни за това, което сумата не доказва. Двоичният файл и неговата сума идват от едно и също място. Ако някой контролираше `dl.k8s.io` и подменеше и двете, те щяха да съвпаднат. Сумата те пази от повреди и от прекъснати изтегляния **между** официалния сайт и твоя диск, както и от смесване на версии или файлове, без да разбереш: ако това, което е останало на диска ти, съвпада със сумата, то е това, което сайтът е публикувал. Не те пази от двоичен файл, дошъл от място, което не е официалното: „`kubectl`, който работи при мен“, пристигнал по чата, няма сума или има такава, която не можеш да сравниш с нищо. Затова произходът е важен колкото сумата.

#### 1.3.2 Програмата, която изтегля и проверява

`fig01_01.sh` изтегля и проверява двата двоични файла, с версията, записана в самия скрипт. Не инсталира нищо и не иска `sudo`. Оставя файловете в папката, която му кажеш.

```bash
#!/usr/bin/env bash
# fig01_01.sh — Lección 1, sección 1.3: descargar kubectl y kind con la versión
# FIJADA y comprobar su suma sha256 ANTES de instalarlos.
#
# Solo descarga y comprueba: no instala nada ni pide sudo. Los dos binarios
# quedan en la carpeta que le des, listos para el «sudo install» de la lección.
#
# Uso:  ./fig01_01.sh CARPETA        (una carpeta nueva y vacía, por ejemplo ~/descargas-k8s)
#
# Descarga los binarios de Linux para amd64, los de Linux Mint en un equipo
# Intel o AMD. Si tu equipo es ARM, cambia ARQ=arm64.
set -euo pipefail

KUBECTL_VERSION=v1.37.1
KIND_VERSION=v0.33.0
ARQ=amd64

DESTINO="${1:?uso: ./fig01_01.sh CARPETA}"
mkdir -p "$DESTINO"
cd "$DESTINO"

# Muestra el comando como lo teclearías y luego lo corre.
paso() { printf '\n$ %s\n' "$*"; "$@"; }

echo "# kubectl $KUBECTL_VERSION y kind $KIND_VERSION para linux/$ARQ"

# kubectl: el binario y su suma salen de dl.k8s.io, con la MISMA versión.
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl"
paso curl -fsSLO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARQ/kubectl.sha256"
paso cat kubectl.sha256; echo
# El archivo .sha256 de kubectl trae solo la suma; se le pega el nombre del
# archivo, como lo pide la guía oficial. El «-» final dice «lee la lista de la
# entrada»: en Linux es opcional, y con él el guion corre igual en macOS.
printf '\n$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -\n'
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -

# kind: el binario y su suma salen del lanzamiento en GitHub. El .sha256sum de
# kind ya trae «suma  nombre», así que se comprueba directo.
paso curl -fsSLo "kind-linux-$ARQ" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ"
paso curl -fsSLo "kind-linux-$ARQ.sha256sum" "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-linux-$ARQ.sha256sum"
paso cat "kind-linux-$ARQ.sha256sum"
paso sha256sum --check "kind-linux-$ARQ.sha256sum"

# Lo que quedó: dos binarios comprobados. wc -c da su tamaño en bytes, para
# compararlo con el de la lección.
paso wc -c kubectl "kind-linux-$ARQ"
```

Три подробности, отгоре надолу:

- **`set -euo pipefail`** кара скрипта да спре при първата команда, която се провали. Ако сумата не съвпада, `sha256sum` излиза с код 1 и скриптът спира там, преди да изтегли `kind` и преди финалния `wc -c`.
- **`curl -fsSL`**: `-f` прави така, че грешка от сървъра (404, защото си написал грешно версията) да е провал, а не файл с грешка, записан с името на двоичния файл. `-L` следва пренасочванията, които GitHub използва във всичките си изтегляния. `-sS` заглушава лентата за напредъка, но оставя грешките да се виждат.
- **Два формата на сума.** `kubectl.sha256` на проекта Kubernetes съдържа само 64-те знака. Затова официалното ръководство сглобява реда „сума, два интервала, име“ с `echo` и го подава на `sha256sum --check`. `.sha256sum` на kind вече съдържа целия ред и `sha256sum --check` го чете директно.

#### 1.3.3 Изпълнението

**Реално изпълнение · Mac** (временната папка беше изтрита накрая):

```text
# kubectl v1.37.1 y kind v0.33.0 para linux/amd64

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ cat kubectl.sha256
65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
kubectl: OK

$ curl -fsSLo kind-linux-amd64 https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64

$ curl -fsSLo kind-linux-amd64.sha256sum https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-amd64.sha256sum

$ cat kind-linux-amd64.sha256sum
aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d  kind-linux-amd64

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ wc -c kubectl kind-linux-amd64
 61886626 kubectl
 10530942 kind-linux-amd64
 72417568 total
```

Важните са двата `OK`. Запиши си и двете суми: ако след месец изтеглиш отново същите двоични файлове със същите версии, трябва да излязат **точно** тези. Ако излязат други, или не е същата версия, или не е същият файл. `wc -c` в края показа, че `kubectl` тежи 61,886,626 байта, а `kind` — 10,530,942.

Бързото ръководство на kind дава командата за изтегляне на двоичния файл, но не споменава контролната сума ([kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/)). Изданието v0.33.0 обаче публикува `.sha256sum` за всеки двоичен файл (Linux `amd64` и `arm64`, macOS и Windows), и това се вижда в списъка с файлове на [страницата на изданието](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0). Това, че ръководството не го изисква, не значи, че не е нужно. Този курс го изисква.

#### 1.3.4 Нарочната грешка: `FAILED`

`fig01_02.sh` предизвиква грешката по двата начина, по които се случва наистина. В първия случай двоичният файл е от **друга версия**, v1.37.0, а контролната сума — от v1.37.1. Това ти се случва, когато теглиш двоичния файл с командата на `stable.txt` в един ден, а контролната сума — в друг, или когато копираш адреса от един урок, а контролната сума от друг. Във втория случай двоичният файл е правилният, но с **един байт повече** в края, като такъв, който се е повредил или който някой е пипал. **Реално изпълнение · Mac** (`fig01_02.error-esperado.txt`):

```text
## Caso 1: binario de v1.37.0, suma de v1.37.1

$ curl -fsSLO https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]

## Caso 2: el binario correcto, con un byte de más

$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check -
sha256sum: WARNING: 1 computed checksum did NOT match
kubectl: FAILED
[código de salida: 1]
```

Чете се така: `kubectl: FAILED` е присъдата за този файл, а предупреждението казва колко от проверените файлове не съвпадат (тук — един от един). Изходният код 1 е това, което спира `set -e` в един скрипт. Официалното ръководство показва първо присъдата, а после предупреждението, и това ще видиш в терминала на твоя Mint. Изходът по-горе идва от `sha256sum` на macOS, който отпечата предупреждението преди това. Двата реда пътуват по различни канали (стандартния изход и изхода за грешки), така че когато ги запишеш във файл, редът им може да се промени. Това, което не се променя, е `FAILED` и изходният код 1.

Обърни внимание на това, което съобщението **не** ти казва: не различава „друга версия“ от „променен файл“. Двата случая изглеждат еднакво. И е правилно да е така: не е твоя работа да откриваш кой от двата е бил, а да не инсталираш. Какво правиш при `FAILED`: изтриваш двоичния файл и неговата сума, проверяваш дали двата адреса казват една и съща версия и теглиш двата файла отново. Ако пак се провали със същата версия, не инсталираш нищо и проучваш откъде теглиш.

#### 1.3.5 Инсталиране

В твоя Mint инсталирането са две команди — тази от официалното ръководство за `kubectl` и нейният еквивалент за `kind`:

```bash
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
sudo install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind
```

(На ARM компютър файлът на kind се казва `kind-linux-arm64`, двата двоични файла са други и сумите им също: сравнявай ги с тези, които публикува всяко издание, а не с тези от този урок.)

`install` прави с една стъпка това, което биха направили `cp`, `chown` и `chmod`. Копира файла, оставя го със собственик `root` (`-o root -g root`) и с право `0755`: всеки може да го изпълнява, само `root` може да го променя. Последното е важно. Двоичен файл в твоя `PATH`, който потребителят ти може да презапише, е двоичен файл, който всяка програма, работеща като теб, може да замени. Бързото ръководство на kind използва `chmod +x` и `sudo mv`. Резултатът е почти същият, но файлът остава със собственик твоя потребител. `install` е по-чист и затова курсът го използва и за двата. `/usr/local/bin` е папката, която Linux запазва за програмите, които инсталираш ти ръчно, извън мениджъра на пакети. Тя вече е в `PATH` на Mint.

Тъй като на Mac не беше инсталирано нищо, `fig01_03.sh` прави пълното инсталиране **вътре в еднократен контейнер** с Ubuntu 24.04 за `amd64`, със същите файлове, които изтегли `fig01_01.sh`. Файловете влизат през `tar` на стандартния вход, без да се монтират папки. Вътре в контейнера вече си `root`, затова командите `install` са без `sudo`. **Реално изпълнение · Ubuntu 24.04 amd64** (`fig01_03.salida.txt`):

```text
# Ubuntu 24.04.5 LTS, x86_64, sha256sum (GNU coreutils) 9.4

$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: OK

$ sha256sum --check kind-linux-amd64.sha256sum
kind-linux-amd64: OK

$ install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
$ install -o root -g root -m 0755 kind-linux-amd64 /usr/local/bin/kind

$ ls -l /usr/local/bin/kubectl /usr/local/bin/kind
-rwxr-xr-x 1 root root 10530942 Oct 21 09:53 /usr/local/bin/kind
-rwxr-xr-x 1 root root 61886626 Oct 21 09:53 /usr/local/bin/kubectl

$ command -v kubectl kind
/usr/local/bin/kubectl
/usr/local/bin/kind

$ kubectl version --client
Client Version: v1.37.1
Kustomize Version: v5.8.1

$ kind version
kind v0.33.0 go1.26.7 linux/amd64
```

Тук проверката използва командата от ръководството **буква по буква**, без последното `-`, и `sha256sum` на GNU пак казва `OK`. След това — три проверки, които ще повториш в твоя Mint:

- **`ls -l`**: правата `-rwxr-xr-x`, собственикът `root root` и размерът, който трябва да е същият като този, който видя при изтеглянето.
- **`command -v kubectl kind`**: кой файл се изпълнява наистина, когато напишеш името. Ако си имал инсталиран друг `kubectl` преди това (например чрез `snap`), тук виждаш кой печели. Правилното е `/usr/local/bin/kubectl`.
- **`kubectl version --client`** и **`kind version`**: версиите, които поиска. `--client` казва на `kubectl` да не търси клъстер, защото още няма. `Kustomize Version: v5.8.1` е инструментът от Урок 4, който е **вграден** в `kubectl` и не се инсталира отделно.

Едно предупреждение, което излезе от самия Mac на изпълненията. Там, в интерактивния терминал, `type kubectl` отговори `kubectl: aliased to kubecolor`: псевдоним, който някой е настроил, за да оцветява изхода. Скриптовете не виждат псевдонимите на твоя терминал, така че изпълняваха истинския `kubectl`, но това, което пишеше ръчно, минаваше през друга програма. `command -v` не винаги разкрива псевдоним; `type kubectl` го прави. Ако изходът ти не прилича на този от курса, започни оттам.

### 1.4 Настройката на `inotify`

#### 1.4.1 Какво е `inotify`

Много програми трябва да научат, че един файл се е променил, без да го четат всяка секунда. Linux им дава механизъм за това: „API на `inotify` предоставя механизъм за наблюдение на събития във файловата система“ ([man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html)). Една програма отваря **инстанция** на `inotify` и ѝ добавя **наблюдения** (*watches*), по едно за файл или папка. Ядрото я предупреждава, когато нещо се промени.

Всяка инстанция и всяко наблюдение заемат памет на ядрото, затова ядрото налага два лимита, **за потребител**:

- `fs.inotify.max_user_instances`: „горна граница на броя на инстанциите на `inotify`, които могат да се създадат за един реален потребител“.
- `fs.inotify.max_user_watches`: същото за наблюденията.

В един възел на Kubernetes `kubelet`, `kube-proxy`, `containerd` и компонентите на контролната равнина наблюдават файлове непрекъснато: сертификати, манифести, конфигурации, логовете на контейнерите. В нормална машина един възел е една машина. В kind **три възела са три контейнера върху едно и също ядро** и почти всички техни процеси работят като един и същ потребител, `root`. И трите си делят един-единствен лимит.

Ръководството на kind за известните проблеми го казва така: лимитите „се определят със системните променливи `fs.inotify.max_user_watches` и `fs.inotify.max_user_instances`. Например в Ubuntu са съответно 8192 и 128, което не е достатъчно за създаване на клъстер с много възли“ ([kind, „Known Issues“](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files)). И дава стойностите, които препоръчва: 524288 наблюдения и 512 инстанции.

#### 1.4.2 Измерване, преди да пипнеш

Настройката се прави **преди** да създадеш клъстера и се започва с измерване. `fig01_04.sh` без аргументи само чете; с `--ajustar` променя системата ти, и това го виждаме в 1.4.3:

```bash
#!/usr/bin/env bash
# fig01_04.sh — Lección 1, sección 1.4: MEDIR los límites de inotify del núcleo
# y, solo si se lo pides, AJUSTARLOS como pide la guía de kind.
#
# Uso:  ./fig01_04.sh                → solo mide. No cambia nada.
#       sudo ./fig01_04.sh --ajustar → copia 99-kind-inotify.conf a /etc/sysctl.d/
#                                      y lo carga. Cambia tu sistema: LÉELO ANTES,
#                                      a él y a 99-kind-inotify.conf.
#
# Corre en la máquina donde corre Docker: en Linux Mint, tu propia máquina.
set -euo pipefail
cd "$(dirname "$0")"

MINIMO_INSTANCIAS=512
MINIMO_VIGILANCIAS=524288
ARCHIVO=99-kind-inotify.conf
DESTINO=/etc/sysctl.d/$ARCHIVO

medir() {
  printf '\n$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches\n'
  sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches

  # Cuántas instancias de inotify están abiertas AHORA. Cada una es un
  # descriptor que apunta a «anon_inode:inotify». Sin sudo solo ves las de tus
  # procesos; con sudo, las de todos los usuarios (el límite es por usuario).
  printf '\n$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l\n'
  # (find se queja de las carpetas que no puede leer: eso no es un fallo aquí)
  { find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null || true; } | wc -l | tr -d ' '

  # ¿Quedó escrito en algún archivo, o solo vale hasta reiniciar? Se buscan las
  # líneas que FIJAN un valor (empiezan con fs.inotify), no los comentarios, en
  # todas las carpetas que lee el sistema al arrancar (sysctl.d(5)).
  printf "\n\$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/\n"
  grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/ 2>/dev/null \
    || echo "(ninguna: lo que mide sysctl vale hasta el próximo reinicio)"

  local inst vig
  inst="$(cat /proc/sys/fs/inotify/max_user_instances)"
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  echo
  if [ "$inst" -ge "$MINIMO_INSTANCIAS" ] && [ "$vig" -ge "$MINIMO_VIGILANCIAS" ]; then
    echo "LISTO: instancias $inst (mínimo $MINIMO_INSTANCIAS) y vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
  else
    echo "FALTA AJUSTAR: instancias $inst (mínimo $MINIMO_INSTANCIAS), vigilancias $vig (mínimo $MINIMO_VIGILANCIAS)."
    echo "Lee este guion y $ARCHIVO, y luego corre: sudo ./fig01_04.sh --ajustar"
  fi
}

ajustar() {
  [ "$(id -u)" -eq 0 ] || { echo "ALTO: --ajustar necesita sudo." >&2; exit 1; }

  # 1. No BAJAR las vigilancias. En núcleos recientes el valor por omisión
  #    depende de la memoria y puede pasar de 524288; en ese caso se instala el
  #    archivo SIN la línea de vigilancias, y solo se suben las instancias.
  local vig contenido
  vig="$(cat /proc/sys/fs/inotify/max_user_watches)"
  contenido="$(mktemp)"
  if [ "$vig" -gt "$MINIMO_VIGILANCIAS" ]; then
    echo "Tus vigilancias ya son $vig, más que $MINIMO_VIGILANCIAS: no se tocan."
    grep -v '^fs.inotify.max_user_watches' "$ARCHIVO" > "$contenido"
  else
    cat "$ARCHIVO" > "$contenido"
  fi

  # 2. No pisar un archivo que ya existe con otro contenido.
  if [ -e "$DESTINO" ] && ! cmp -s "$contenido" "$DESTINO"; then
    echo "ALTO: ya existe $DESTINO con otro contenido. No lo piso:" >&2
    diff "$DESTINO" "$contenido" >&2 || true
    rm -f "$contenido"
    exit 1
  fi

  # Un archivo propio en /etc/sysctl.d/, en vez de editar /etc/sysctl.conf: se ve
  # de un vistazo qué se cambió y por qué, y se quita borrando un archivo.
  install -o root -g root -m 0644 "$contenido" "$DESTINO"
  rm -f "$contenido"
  printf '\n$ sysctl --load=%s\n' "$DESTINO"
  sysctl --load="$DESTINO"

  # 3. Avisar si /etc/sysctl.conf fija inotify: en Ubuntu y Mint se aplica
  #    DESPUÉS (por 99-sysctl.conf) y su valor ganaría al reiniciar.
  if grep -q '^fs.inotify' /etc/sysctl.conf 2>/dev/null; then
    echo "AVISO: /etc/sysctl.conf también fija inotify y se aplica después de $ARCHIVO:" >&2
    grep -n '^fs.inotify' /etc/sysctl.conf >&2
  fi
  medir
}

case "${1:-}" in
  "") medir ;;
  --ajustar) ajustar ;;
  *) echo "uso: ./fig01_04.sh [--ajustar]" >&2; exit 2 ;;
esac
```

Новото е в две команди на измерването. Първата **брои отворените инстанции**. Всяка инстанция е файлов дескриптор на някакъв процес и в `/proc/<pid>/fd/` този дескриптор се появява като връзка към `anon_inode:inotify`. `find ... -lname` търси точно тези връзки. Без `sudo` можеш да виждаш само дескрипторите на собствените си процеси; със `sudo` виждаш тези на всички потребители, макар лимитът да се брои за потребител. Втората, `grep`, търси **къде е записана** стойността, във всички папки, които системата чете при стартиране. Търси редове, които започват с `fs.inotify`, тоест тези, които фиксират стойност, а не коментарите, които само споменават думата.

На Mac ядрото, което Docker използва, е това на виртуалната машина на Colima, затова там беше измерено. **Реално изпълнение · виртуална машина** (`fig01_04.salida.txt`, само измерване, без настройване):

```text
# máquina virtual de Colima: Ubuntu 24.04.4 LTS, núcleo 6.8.0-100-generic
## sin sudo

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
3

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).

## con sudo (solo mide)

$ sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
fs.inotify.max_user_instances = 512
fs.inotify.max_user_watches = 1048576

$ find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l
110

$ grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/ /run/sysctl.d/ /usr/local/lib/sysctl.d/ /usr/lib/sysctl.d/
(ninguna: lo que mide sysctl vale hasta el próximo reinicio)

LISTO: instancias 512 (mínimo 512) y vigilancias 1048576 (mínimo 524288).
```

Тази машина вече имаше 512 инстанции и наблюдения в излишък. Разликата между 3 и 110 инстанции е тази между „без `sudo`“ и „със `sudo`“: обикновеният потребител имаше 3 отворени, а цялата система — 110, с клъстер на kind от друг урок, работещ в онзи момент. Това число се променя с всичко, което работи. Сравнява се лимитът.

И обърни внимание на `grep`: **нито един файл** от папките, които се четат при стартиране, не фиксира `inotify`. 512 е жива в ядрото, но не е записана. Урок 0 разказва, че същата тази машина беше на 128 и че лимитът беше увеличен до 512 за неговия опит; `grep` показва, че е бил увеличен, без да остане файл. Ако е така, в деня, в който виртуалната машина се рестартира, се връща към стойността по подразбиране и следващият клъстер от три възела се проваля без обяснение. Измерването казва колко е днес; `grep` казва колко ще е след рестартиране. Трябва да погледнеш и двете и затова скриптът ги гледа заедно.

В твоя току-що инсталиран Mint най-вероятно ще видиш `max_user_instances = 128` и скриптът ще каже `FALTA AJUSTAR`. Linux Mint 22 се основава на Ubuntu 24.04 ([Linux Mint, бележки към версия 22](https://www.linuxmint.com/rel_wilma.php)), а Ubuntu има 128. Наблюденията, напротив, може да ти излязат високи: във виртуалната машина на изпълненията, също Ubuntu 24.04, ядрото даваше 1048576, много над 8192, които споменава ръководството на kind. В скорошните ядра тази стойност зависи от паметта на машината, така че това, което почти винаги липсва, са инстанциите.

#### 1.4.3 Настройване, което да трае

Ръководството на kind дава два начина. **Временният**, който важи до рестартиране:

```bash
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512
```

И **постоянният**: да запишеш двата реда в `/etc/sysctl.conf`. Курсът прави постоянното с вариант: вместо да редактира `/etc/sysctl.conf`, поставя собствен файл в `/etc/sysctl.d/`. Ето файла, `99-kind-inotify.conf`:

```ini
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
```

Защо отделен файл? Защото „при стартиране `systemd-sysctl.service` чете конфигурационните файлове“ от `/etc/sysctl.d/*.conf`, наред с други папки ([man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html)). Имаш в един файл, с неговия коментар, какво си променил и защо, а за да го отмениш, го изтриваш и рестартираш.

Но има клопка в реда. Същата страница казва, че всички файлове се подреждат по името си, независимо в коя папка са, и че ако два фиксират едно и също, **печели този, който е след това**. `99-` оставя файла на курса почти в края. Почти, защото Ubuntu, а с него и Mint, има още един. Измерено във виртуалната машина на изпълненията:

```text
$ ls /etc/sysctl.d/
10-bufferbloat.conf
10-console-messages.conf
10-ipv6-privacy.conf
10-kernel-hardening.conf
10-magic-sysrq.conf
10-map-count.conf
10-network-security.conf
10-ptrace.conf
10-zeropage.conf
99-cloudimg-ipv6.conf
99-lima.conf
99-sysctl.conf
README.sysctl

$ ls -l /etc/sysctl.d/99-sysctl.conf
lrwxrwxrwx 1 root root 14 Nov 25  2025 /etc/sysctl.d/99-sysctl.conf -> ../sysctl.conf
```

`99-sysctl.conf` е символна връзка към `/etc/sysctl.conf`, а `99-sysctl.conf` идва след `99-kind-inotify.conf` по азбучен ред (`s` е след `k`). Така че **ако някой е поставил стойност за `inotify` в `/etc/sysctl.conf`, тази стойност печели** при рестартиране, а тази от курса не върши работа. Затова `--ajustar` проверява `/etc/sysctl.conf` и те предупреждава, и затова измерването търси във всички папки.

В твоя Mint настройката е `sudo ./fig01_04.sh --ajustar`. **Преди да го изпълниш със `sudo`, прочети го изцяло, заедно с `99-kind-inotify.conf`.** Това е същият навик като с двоичните файлове: всичко, което работи като `root`, си го прочел преди това. Какво ще намериш в `ajustar`:

1. **Не намалява наблюденията ти.** Ако ядрото ти вече има повече от 524288, файлът, който инсталира, е без реда `max_user_watches` и увеличава само инстанциите. Без тази защита настройката на kind би ти **отнела** наблюдения.
2. **Не презаписва файл, който вече съществува.** Ако `/etc/sysctl.d/99-kind-inotify.conf` съществува с друго съдържание, ти показва разликата и спира.
3. Копира файла със собственик `root` и право `0644`, зарежда го веднага със `sysctl --load` (без да чака рестартиране), предупреждава те, ако `/etc/sysctl.conf` също фиксира `inotify`, и измерва отново. Трябва да завърши с `LISTO`.

Истинската настройка не беше изпълнена на машината на изпълненията: вече имаше 512 и беше споделена машина, на която не биваше да се променя нищо. Това, което беше изпробвано, са двете защити, в еднократен контейнер **без привилегии**, където `/proc/sys` е само за четене и `sysctl` не може да променя ядрото на никого. **Реално изпълнение · контейнер без привилегии** (`fig01_04.prueba-ajustar.txt`):

```text
$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.

$ sysctl --load=/etc/sysctl.d/99-kind-inotify.conf
sysctl: permission denied on key "fs.inotify.max_user_instances"
[código de salida: 1]

$ cat /etc/sysctl.d/99-kind-inotify.conf
# /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
# kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
# Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
# arranca: el kubelet de los nodos de trabajo cae con «too many open files».
fs.inotify.max_user_instances = 512

$ echo otro > /etc/sysctl.d/99-kind-inotify.conf

$ ./fig01_04.sh --ajustar
Tus vigilancias ya son 1048576, más que 524288: no se tocan.
ALTO: ya existe /etc/sysctl.d/99-kind-inotify.conf con otro contenido. No lo piso:
1c1,5
< otro
---
> # /etc/sysctl.d/99-kind-inotify.conf — límites de inotify que pide la guía de
> # kind («Known Issues», https://kind.sigs.k8s.io/docs/user/known-issues/).
> # Con los de Ubuntu y Linux Mint (128 instancias), un clúster de tres nodos no
> # arranca: el kubelet de los nodos de trabajo cae con «too many open files».
> fs.inotify.max_user_instances = 512
[código de salida: 1]
```

Първото изпълнение видя 1048576 наблюдения и инсталира файла **без** реда за наблюденията: `cat` го доказва. `permission denied` е очакваното в контейнер без привилегии; в твоя Mint, със `sudo`, `sysctl --load` отговаря с редовете, които е заредил. Второто изпълнение намери файл с друго съдържание и спря, без да го пипа.

#### 1.4.4 Колко изразходва един клъстер

След като клъстерът е създаден (1.6), скриптът на урока гледа лимита **отвътре** във всеки възел и брои инстанциите, които отваря всеки. **Реално изпълнение · Mac**, извадка от `correr.salida.txt`:

```text
$ docker exec curso-k8s-l1-control-plane cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-worker2 cat /proc/sys/fs/inotify/max_user_instances
512

$ docker exec curso-k8s-l1-control-plane sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
45

$ docker exec curso-k8s-l1-worker sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18

$ docker exec curso-k8s-l1-worker2 sh -c 'find /proc/[0-9]*/fd -lname anon_inode:inotify 2>/dev/null | wc -l'
18
```

И трите възела казват 512: нямат собствен лимит, виждат **този на ядрото на машината**. Това е същата следа като колоната `KERNEL-VERSION` от Урок 0, сега с число, което има значение. И броенето: 45 инстанции в контролния възел и 18 във всеки работен. Общо 81, при **празен** клъстер, току-що създаден, без нито един твой Pod. Почти всички са на процеси на `root`, а лимитът е за потребител: към тези 81 се добавят тези, които `root` вече има отворени на собствената ти машина, които можеш да преброиш с `find` от `fig01_04.sh`, изпълнен със `sudo`. При лимит от 128 запасът е малък. Какво става при стартиране, когато трите възела стартират процесите си едновременно, не беше измерено тук; Урок 0 видя резултата: работните възли не се появиха. При 512 има място в излишък за този клъстер и за още един.

### 1.5 Файлът на клъстера

`kind create cluster` без нищо повече създава клъстер от един-единствен възел, наречен `kind`, с образа на възела по подразбиране за тази версия на kind. Курсът има нужда от три възела, собствено име и фиксиран образ, а това се записва във файл:

```yaml
# kind-curso.yaml — el clúster del curso: un nodo de control y dos de trabajo,
# con la imagen del nodo fijada por su huella (notas de la versión v0.33.0 de kind).
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
- role: worker
  image: kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

Чете се отгоре надолу. `kind: Cluster` и `apiVersion: kind.x-k8s.io/v1alpha4` казват, че това е конфигурацията на клъстер на kind. Прилича на манифест на Kubernetes, но не е: този файл го чете `kind`, никога клъстерът. `nodes` е списъкът с възли, по един на ред с `role`: `control-plane` за контролната равнина и `worker` за работните. Това е същата форма, която използва бързото ръководство на kind за клъстер „от три възела (два работни)“ ([kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/)).

И всеки възел има своя `image` **с отпечатък**. Това е същият навик като контролната сума на двоичните файлове, приложен към един образ. Тагът `v1.37.0` е име, което този, който публикува образа, може да премести към друг. Отпечатъкът `sha256:a1ed…` е сумата на съдържанието. Ръководството на kind го иска така: „използвай сумата `sha256` на версията на Kubernetes, която искаш“, както я публикуват бележките към всяко издание ([kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/); [kind v0.33.0](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)). Ако някой подмени образа, Docker не го приема, защото отпечатъкът престава да съвпада.

Името на клъстера не е във файла, а в командата: `--name curso-k8s-l1`. Така един и същ файл може да се използва за създаване на клъстери с други имена.

Командата търси `kind-curso.yaml` по пътя, който ѝ дадеш. Командите в този урок предполагат, че си във `programas/01-instalacion-primer-cluster/`, където се намира файлът. Ако копираш файла в друга папка, изпълни командата оттам или напиши пълния път в `--config`.

### 1.6 Създаване на клъстера

#### 1.6.1 Собствен `kubeconfig` за курса

Преди да създадеш каквото и да било — едно решение за сигурността. Когато kind създава клъстер, той **записва в твоя `kubeconfig`** адреса на клъстера и администраторското удостоверение и го оставя като активен контекст. Ако не му кажеш друго, този файл е `~/.kube/config`. Ако в този файл вече има клъстер от работата или от друг курс, kind сменя активния контекст, без да те пита.

Затова в този курс kind пише във **временен и собствен** файл. Ръчно, в твоя терминал, е така:

```bash
export KUBECONFIG="$(mktemp -d /tmp/curso-k8s-l1.XXXX)/kubeconfig"
```

`mktemp -d` създава папка с име, което никой друг няма. `export KUBECONFIG=…` кара `kind` и `kubectl` да използват този файл **в този терминал** и в никой друг. Твоят `~/.kube/config` нито се чете, нито се пипа. Затваряш терминала и обичайната ти конфигурация си остава същата като преди.

Това, което **не** изчезва при затваряне на терминала: клъстерът, който продължава да работи, и временната папка, с администраторското удостоверение вътре. Освен това при затваряне губиш пътя на `KUBECONFIG`. Затова при ръчния път, преди да затвориш:

```bash
kind delete cluster --name curso-k8s-l1
# La carpeta temporal del kubeconfig, y SOLO si es la que creó mktemp arriba.
case "$KUBECONFIG" in
  /tmp/curso-k8s-l1.*/kubeconfig) rm -r -- "$(dirname "$KUBECONFIG")" ;;
  *) echo "No borro nada: KUBECONFIG es «$KUBECONFIG», no la carpeta de la lección." ;;
esac
unset KUBECONFIG
```

`case` пропуска само път с точната форма на този, който е създал `mktemp`; ако твоят `KUBECONFIG` сочи другаде, например към `~/.kube/config`, защото си отворил друг терминал и не си повторил `export`, не изтрива нищо и ти казва защо, вместо да отнесе цялата ти папка `~/.kube`.

Ако вече си затворил, `kind get clusters` ти казва какво е останало живо, а `ls -d /tmp/curso-k8s-l1.*` — какви папки са останали. Скриптът на урока, `correr.sh`, прави всичко това сам: създава своята временна папка и при излизане изтрива клъстера и папката.

#### 1.6.2 Скриптът на урока

`correr.sh` минава през всичко, което остава от урока: създава клъстера, разглежда го, си играе с контекстите, предизвиква грешките, изтрива го, създава го отново и при излизане го изтрива пак. Заглавният му коментар обяснява трите му защити и те са същите, които ще ползваш в целия курс:

```bash
# 🔴 SEGURIDAD, las tres protecciones de la lección:
#   1. KUBECONFIG apunta a un archivo TEMPORAL propio: tu ~/.kube/config ni se
#      lee ni se toca, y tus otros clústeres no se enteran.
#   2. Antes de cada kubectl que le habla al clúster, se comprueba que el
#      contexto activo es kind-curso-k8s-l1; si no, el guion se detiene.
#   3. Un trap borra al salir el clúster que ESTA corrida creó y el temporal,
#      aunque el guion falle a la mitad. Si al empezar ya existe un clúster
#      llamado curso-k8s-l1, se detiene sin tocarlo.
```

Третата заслужава обяснение. `trap limpiar EXIT` казва на Bash: „когато този скрипт приключи, по каквато и да е причина, изпълни `limpiar`“. Ако една команда се провали по средата и `set -e` спре скрипта, `limpiar` се изпълнява пак и изтрива клъстера. Така не ти остава забравен клъстер, който харчи памет. Но `limpiar` изтрива само ако променливата `CREADO_AQUI` казва `si`, а тази променлива се включва **само ако `kind create cluster` от това изпълнение е завършил добре**. Ако вече е имало `curso-k8s-l1` отпреди, скриптът спира в началото и не го пипа: този клъстер не е негов. А ако друг процес го е създал миг след тази проверка, `create` на скрипта се проваля с `node(s) already exist`, скриптът спира и променливата си остава на `no`: и тогава не го пипа.

Втората защита е една къса функция, същата като в Урок 0:

```bash
contexto_correcto() {
  local actual
  actual="$(kubectl config current-context 2>/dev/null || true)"
  if [ "$actual" != "$CONTEXTO" ]; then
    echo "ALTO: el contexto activo es «$actual», no «$CONTEXTO». No sigo." >&2
    return 1
  fi
}
k() { contexto_correcto || exit 1; paso kubectl "$@"; }
```

Всеки `kubectl`, който говори с клъстера, минава през `k`, която първо пита за контекста. Командите `kubectl config`, които само четат или редактират файла `kubeconfig`, без да говорят с никакъв клъстер, минават през друга функция, `kc`, без проверка. Не се нуждаят от нея, а в раздел 1.7 скриптът сменя контекста нарочно.

#### 1.6.3 Създаването

Преди да създаде каквото и да било, скриптът разглежда временния `kubeconfig`. Празен е: няма контексти, нито активен контекст.

```text
$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]
```

И създава клъстера. **Реално изпълнение · Mac:**

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
 • Ensuring node image (kindest/node:v1.37.0) 🖼️  ...
 ✓ Ensuring node image (kindest/node:v1.37.0) 🖼️
 • Preparing nodes 📦 📦 📦   ...
 ✓ Preparing nodes 📦 📦 📦 
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
 • Joining worker nodes 🚜  ...
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-curso-k8s-l1"
You can now use your cluster with:

kubectl cluster-info --context kind-curso-k8s-l1

Have a nice day! 👋
(crear tardó 23 s)
```

Всяка двойка редове е стъпка. *Ensuring node image* търси образа на възела и, ако го няма, го изтегля; първия път в твоя Mint тази стъпка трае колкото трае изтеглянето на образа, а следващите са мигновени. *Preparing nodes* създава трите контейнера (по един 📦 на възел). *Writing configuration* записва конфигурацията на `kubeadm`, официалния инструмент, който сглобява клъстера. *Starting control-plane* стартира контролната равнина. *Installing CNI* поставя мрежата между Pod-овете, `kindnet`. *Installing StorageClass* поставя хранилището по подразбиране. *Joining worker nodes* присъединява двата работни възела. Накрая `Set kubectl context to "kind-curso-k8s-l1"` е редът, който най-много те интересува в този урок: kind записа контекста в твоя `kubeconfig` (временния) и го остави активен. Прощалната фраза се сменя на случаен принцип при всяко изпълнение.

С вече изтегления образ създаването отне 23 секунди. И сега урокът от Урок 0: **отметката не е доказателство**. Доказателството има две части. Първата е да изчакаш възлите да кажат `Ready`:

```text
$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met
```

`kubectl wait` остава да чака, докато всички възли (`--all`) изпълнят условието `Ready` или докато минат 240 секунди. Но има сляпо петно: чака възлите, които **съществуват**. При провала от Урок 0 работните възли така и не стигнаха да се регистрират; там `kubectl wait --all` би изчакал един, би казал `condition met` само веднъж и би приключил без грешка. Затова втората част е да **броиш**:

```text
$ kubectl get nodes --no-headers | wc -l
3
```

`--no-headers` маха реда със заглавията, а `wc -l` брои оставащите редове: по един на възел. Трябва да каже 3. Скриптът не се доверява на четенето с очи: ако не е 3, спира с `ALTO: el clúster tiene N nodos, no 3`. (В `correr.sh` изчакването и броенето идват след разглеждането на `kubeconfig`, в раздел 5 на изхода му; тук се разказват заедно, защото са едно и също доказателство.)

### 1.7 Контексти и `kubeconfig`

#### 1.7.1 Какво има в един `kubeconfig`

Документацията го определя така: „файл, който се използва за конфигуриране на достъпа до клъстери, се нарича файл *kubeconfig*. Това е общ начин да се говори за конфигурационните файлове; не означава, че съществува файл с име `kubeconfig`“ ([kubernetes.io, „Organizing Cluster Access Using kubeconfig Files“](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). По подразбиране `kubectl` търси такъв с име `config` в `$HOME/.kube`.

Един `kubeconfig` има три списъка и един указател:

- **`clusters`**: с кой адрес да говориш и с кой сертификат да разпознаеш сървъра.
- **`users`**: с какво удостоверение да се представиш.
- **`contexts`**: именувани комбинации от клъстер, потребител и, по избор, пространство от имена (*namespace*). Документацията: „всеки контекст има три параметъра: клъстер, пространство от имена и потребител. По подразбиране `kubectl` използва параметрите на *текущия контекст*, за да комуникира с клъстера“.
- **`current-context`**: указателят. Кой от контекстите използва `kubectl`, когато не му кажеш друг.

Скриптът го разглежда веднага след създаването на клъстера:

```text
$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   

$ kubectl config view --minify
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: DATA+OMITTED
    server: https://127.0.0.1:54589
  name: kind-curso-k8s-l1
contexts:
- context:
    cluster: kind-curso-k8s-l1
    user: kind-curso-k8s-l1
  name: kind-curso-k8s-l1
current-context: kind-curso-k8s-l1
kind: Config
users:
- name: kind-curso-k8s-l1
  user:
    client-certificate-data: DATA+OMITTED
    client-key-data: DATA+OMITTED

$ stat -c %A "$KUBECONFIG"
-rw-------
```

Четири неща за четене:

- **Името на контекста е `kind-` плюс името на клъстера.** kind винаги ги именува така: клъстерът `curso-k8s-l1` дава контекста `kind-curso-k8s-l1`, а клъстерът по подразбиране `kind` дава `kind-kind`. Клъстерът и потребителят в `kubeconfig` имат същото име.
- **`get-contexts`** е късата таблица. Звездичката в `CURRENT` отбелязва активния. `AUTHINFO` е потребителят. Празен `NAMESPACE` означава `default`.
- **`view --minify`** показва само това, което използва активният контекст. Адресът на сървъра е `https://127.0.0.1:54589`: високият порт, който Docker публикува на твоята машина за `kube-apiserver` на контролния възел, на `127.0.0.1` по подразбиране. kind позволява да се смени този адрес с `networking.apiServerAddress`, но документацията му не препоръчва да се излага към нищо, различно от локалния интерфейс, и този курс не го променя. Трите полета `DATA+OMITTED` са сертификатът на сървъра и **администраторското удостоверение**. `kubectl` ги скрива, защото са тайни. Във файла са пълни.
- **`stat -c %A`** дава правата на файла: `-rw-------`, само твоят потребител може да го чете. kind го създава така, защото съдържа това удостоверение. Ако някога копираш `kubeconfig` другаде, запази тези права. (В твоя Mint `ls -l "$KUBECONFIG"` казва същото, заедно с името на потребителя ти.)

Документацията добавя едно предупреждение, което важи завинаги: „използвай само файлове `kubeconfig` от надеждни източници. Нарочно направен файл `kubeconfig` може да доведе до изпълнение на зловреден код или до излагане на файлове. Ако трябва да използваш такъв, на който не се доверяваш, прегледай го внимателно преди това, както би прегледал скрипт на *shell*“. Един `kubeconfig` може да поиска да се изпълни програма, за да се получи удостоверението: затова се чете, преди да се използва.

#### 1.7.2 Два контекста и грешката без съобщение

Урок 0 описа най-опасната грешка на `kubectl`: да говориш с грешния клъстер, без нищо да те предупреди. Скриптът я подготвя нарочно, само във временния `kubeconfig`. Добавя втори контекст, `otro`, със симулирано удостоверение и адрес, на който няма никого, `127.0.0.1:1`, и го оставя активен:

```text
$ kubectl config set-cluster otro --server=https://127.0.0.1:1
Cluster "otro" set.

$ kubectl config set-credentials nadie --token=token-de-mentira
User "nadie" set.

$ kubectl config set-context otro --cluster=otro --user=nadie
Context "otro" created.

$ kubectl config get-contexts
CURRENT   NAME                CLUSTER             AUTHINFO            NAMESPACE
*         kind-curso-k8s-l1   kind-curso-k8s-l1   kind-curso-k8s-l1   
          otro                otro                nadie               

$ kubectl config use-context otro
Switched to context "otro".
```

Обърни внимание на реда. Трите `set-…` сглобяват клъстер, потребител и контекст, който ги събира, в този ред. `get-contexts` показва двата контекста, със звездичката още при този на kind. `use-context otro` премества указателя. Оттам нататък всеки `kubectl` без повече уточнения отива към `otro`. Какво казва проверката:

```text
$ (la comprobación del contexto, antes de un kubectl get nodes)
ALTO: el contexto activo es «otro», no «kind-curso-k8s-l1». No sigo.
[el guion NO corre kubectl get nodes: se detuvo a tiempo]

(Sin la comprobación, kubectl le habla a «otro»:)
```

И какво става, ако не провериш:

```text
$ kubectl get nodes --request-timeout=5s
E1021 07:11:02.007697   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.007948   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009279   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.009582   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
E1021 07:11:02.010566   96846 memcache.go:381] "Couldn't get current server API group list" err="Get \"https://127.0.0.1:1/api?timeout=5s\": dial tcp 127.0.0.1:1: connect: connection refused"
The connection to the server 127.0.0.1:1 was refused - did you specify the right host or port?
[código de salida: 1]
```

Редовете, които започват с `E1021 … memcache.go:381`, ги пише самият клиент на `kubectl`, а не клъстерът: `E` е нивото на грешката, `1021` е месецът и денят, а `memcache.go` е кодът, с който `kubectl` държи в паметта списъка с ресурси, които предлага един сървър. Преди да изпълни твоята команда, `kubectl` пита сървъра какви ресурси има и тук този въпрос се провали пет пъти, защото никой не слушаше. Това е повтарящ се шум, а важен е последният ред.

Тук имаше късмет, защото `otro` не съществува и грешката е шумна. Прочети последния ред: казва **с кой сървър** е опитал да говори, `127.0.0.1:1`, а това не е този на твоя клъстер, който беше на `127.0.0.1:54589`. Ако `otro` беше истински клъстер, отговорът щеше да е списък от чужди възли, без нито една грешка. Упражнението да четеш **с кого** си говорил е същото и в двата случая.

Има начин да не зависиш от указателя: да кажеш на всяка команда към кой контекст отива, с `--context`.

```text
$ kubectl --context kind-curso-k8s-l1 get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

С активен `otro` тази команда говори с kind, защото опцията има предимство пред `current-context` във файла. Според документацията контекстът се избира по „първото съвпадение“ в тази верига: първо опцията `--context`, после `current-context` от файловете ([kubernetes.io, „Organizing Cluster Access…“](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). В скриптове, които се споделят, добавянето на `--context` към всяка команда е толкова добра защита, колкото и проверката на контекста преди това. Курсът използва проверката, защото освен това те учи на навика.

Скриптът оставя всичко, както е било: връща се към `kind-curso-k8s-l1` с `use-context` и изтрива симулирания контекст, клъстер и потребител с `delete-context`, `delete-cluster` и `delete-user`. Всяка от командите отговори `deleted … from /tmp/curso-k8s-l1.LWx1/kubeconfig`. Този ред ти казва и **кой файл** е променен, и там се вижда, че е бил временният.

#### 1.7.3 `KUBECONFIG` като списък

Още нещо, което е добре да знаеш, макар курсът да не го използва. `KUBECONFIG` може да съдържа **няколко файла**, разделени с двоеточие в Linux. `kubectl` ги слива в един. За стойностите, които се повтарят, печели първият файл, който ги определя. По-конкретно печели `current-context` на първия файл, който го има ([kubernetes.io, „Organizing Cluster Access…“](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)). А когато `kubectl` създава нова стойност, я записва в първия съществуващ файл от списъка ([kubernetes.io, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/)). Полезно е и е клопка: с два файла в списъка един `use-context` може да промени файл, който не очакваш. С един-единствен временен файл на клъстер, както в този курс, няма съмнения.

### 1.8 Разглеждане на клъстера

След като контекстът е проверен, скриптът разглежда клъстера от четири страни. Първо, от Kubernetes:

```text
$ kubectl get nodes -o wide
NAME                         STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION              CONTAINER-RUNTIME
curso-k8s-l1-control-plane   Ready    control-plane   31s   v1.37.0   172.18.0.5    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker          Ready    <none>          16s   v1.37.0   172.18.0.6    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0   172.18.0.7    <none>        Debian GNU/Linux 13 (trixie)   6.8.0-100-generic (arm64)   containerd://2.3.4
```

Три възела `Ready`, версия `v1.37.0`, с *runtime* `containerd://2.3.4`. Контролният е с 15 секунди по-стар от другите два: беше създаден първи, а работните се присъединиха след това. Колоната `ROLES` казва `control-plane` за единия и `<none>` за работните. Не е грешка: `ROLES` идва от етикетите (*labels*) `node-role.kubernetes.io/…` на всеки възел и при създаването на клъстера само контролният възел получава такъв (`control-plane`). `INTERNAL-IP` са адреси от мрежата `kind` на Docker, `172.18.0.x`, които на твоята машина ще са други. А `KERNEL-VERSION` казва ядрото на машината, на която работи Docker, едно и също и за трите.

```text
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:54589
CoreDNS is running at https://127.0.0.1:54589/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

`cluster-info` отговаря на въпроса „с какво говоря?“ с адреса на сървъра. Той е същият като във `view --minify`. Ако някога се усъмниш в контекста си, тази команда ти казва реалния адрес.

Второ, от kind и от Docker:

```text
$ kind get nodes --name curso-k8s-l1
curso-k8s-l1-worker
curso-k8s-l1-control-plane
curso-k8s-l1-worker2

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
NAMES                        IMAGE                  PORTS
curso-k8s-l1-worker          kindest/node:v1.37.0   
curso-k8s-l1-control-plane   kindest/node:v1.37.0   127.0.0.1:54589->6443/tcp
curso-k8s-l1-worker2         kindest/node:v1.37.0   
```

`kind get nodes --name` изброява контейнерите на **този** клъстер, без фиксиран ред. Съществува и `kind get clusters`, който изброява всички клъстери на kind на твоята машина: полезно е, за да разбереш дали има други, но не го използвай, за да решаваш какво да изтриеш, без да прочетеш всяко име. `docker ps` с филтъра по етикета `io.x-k8s.kind.cluster` показва същите три контейнера. Само един публикува порт: контролният, `127.0.0.1:54589->6443/tcp`. Това е пътят на `kubectl` към `kube-apiserver`, който слуша на 6443 вътре във възела. Работните не публикуват нищо и никой извън твоята машина не може да говори с твоя клъстер.

Трето, това, което работи вътре, без да пипаш нищо:

```text
$ kubectl get pods -n kube-system -o wide
NAME                                                 READY   STATUS    RESTARTS   AGE   IP           NODE                         NOMINATED NODE   READINESS GATES
coredns-559f6c778d-27jlk                             1/1     Running   0          23s   10.244.0.4   curso-k8s-l1-control-plane   <none>           <none>
coredns-559f6c778d-fd4kh                             1/1     Running   0          23s   10.244.0.2   curso-k8s-l1-control-plane   <none>           <none>
etcd-curso-k8s-l1-control-plane                      1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-n44qw                                        1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kindnet-rf64g                                        1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kindnet-xsc6h                                        1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-apiserver-curso-k8s-l1-control-plane            1/1     Running   0          31s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-controller-manager-curso-k8s-l1-control-plane   1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-proxy-hxjzg                                     1/1     Running   0          18s   172.18.0.7   curso-k8s-l1-worker2         <none>           <none>
kube-proxy-jp497                                     1/1     Running   0          18s   172.18.0.6   curso-k8s-l1-worker          <none>           <none>
kube-proxy-m4r92                                     1/1     Running   0          23s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
kube-scheduler-curso-k8s-l1-control-plane            1/1     Running   0          32s   172.18.0.5   curso-k8s-l1-control-plane   <none>           <none>
```

Това са частите от Урок 0, сега разпределени в три възела. Колоната `NODE` го разказва. Контролната равнина (`etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`) живее само в контролния възел. `kube-proxy` и `kindnet` има **по един на възел**, по три от всеки: те са частите, от които всяка машина се нуждае за мрежата. А колоната `IP` има два вида адреси. Системните Pod-ове, които използват мрежата на възела, имат `172.18.0.x` на своя възел. Двата `coredns` имат `10.244.0.x`, адреси от мрежата **на Pod-овете**, която е поставил `kindnet`. Урок 3 се връща към това.

Четвърто, хранилището, което kind инсталира:

```text
$ kubectl get storageclass
NAME                 PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
standard (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  29s
```

Един клас на съхранение (*StorageClass*), `standard`, отбелязан като този по подразбиране. Пази данните на диска на самия възел. Това е редът `Installing StorageClass` от създаването и Урок 8 го използва.

### 1.9 Изтриване, повторно създаване и възстановяване

#### 1.9.1 Загуба на контекста

Случва се по-често, отколкото мислиш: някой чисти своя `kubeconfig` или изтрива един контекст, мислейки за друг. Клъстерът си остава жив, но `kubectl` вече не знае как да стигне до него. Скриптът го предизвиква:

```text
$ kubectl config delete-context kind-curso-k8s-l1
warning: this removed your active context, use "kubectl config use-context" to select a different one
deleted context kind-curso-k8s-l1 from /tmp/curso-k8s-l1.LWx1/kubeconfig

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE
```

`kubectl` предупреждава, че си изтрил **активния** контекст. Таблицата остава празна. Клъстерът не разбра: трите му контейнера продължават да работят. Това, което се загуби, е пътят. kind умее да го възстанови, защото клъстерът пази собствената си конфигурация:

```text
$ kind export kubeconfig --name curso-k8s-l1
Set kubectl context to "kind-curso-k8s-l1"

$ kubectl config current-context
kind-curso-k8s-l1

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   34s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          19s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          19s   v1.37.0
```

`kind export kubeconfig` записва отново контекста на клъстера в `kubeconfig`, който сочи `KUBECONFIG`, и го оставя активен. Неговият събрат, `kind get kubeconfig --name curso-k8s-l1`, не записва нищо: според собствената му помощ „отпечатва kubeconfig на клъстера“ на екрана. Отпечатан `kubeconfig` е отпечатано удостоверение, така че тази команда не се изпълнява, докато някой гледа, и не се поставя в чат.

#### 1.9.2 Изтриване

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
Deleted nodes: ["curso-k8s-l1-worker" "curso-k8s-l1-control-plane" "curso-k8s-l1-worker2"]
(borrar tardó 1 s)

$ kubectl config current-context
error: current-context is not set
[código de salida: 1]

$ kubectl config get-contexts
CURRENT   NAME   CLUSTER   AUTHINFO   NAMESPACE

$ docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'
```

Една секунда. Изтриването на клъстер на kind е изтриване на три контейнера, а освен това kind маха от `kubeconfig` това, което е записал: контекстът вече не съществува и указателят остана празен. Ако сега изпълниш `kubectl get nodes`, ще видиш грешката `localhost:8080`, която Урок 0 те научи да разчиташ. `docker ps` с филтъра не връща нищо.

**Винаги с `--name`.** Без него kind изтрива клъстера, който се казва `kind`, този по подразбиране: „ако пропуснеш `--name`, kind ще използва името на контекста по подразбиране, `kind`, и ще изтрие този клъстер“ ([kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/)). Ако имаш клъстер `kind` от друг курс, той изчезва.

И една полезна странност: изтриването на клъстер, който **не съществува**, не е грешка. Скриптът го прави нарочно, точно след като го е изтрил:

```text
$ kind delete cluster --name curso-k8s-l1
Deleting cluster "curso-k8s-l1" ...
```

Без `Deleted nodes` и без грешка. Ръководството на kind го обяснява: „по дизайн, заявката за изтриване на клъстер, който не съществува, не връща грешка“. Затова можеш да го сложиш в началото на един скрипт, „за всеки случай“. Но това означава и че ако напишеш грешно името, kind не те предупреждава: казва `Deleting cluster` и не изтрива нищо. Редът `Deleted nodes` е доказателството, че е изтрил нещо.

#### 1.9.3 Повторно създаване

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
Creating cluster "curso-k8s-l1" ...
…
Set kubectl context to "kind-curso-k8s-l1"
…
(recrear tardó 26 s)

$ kubectl wait --for=condition=Ready nodes --all --timeout=240s
node/curso-k8s-l1-control-plane condition met
node/curso-k8s-l1-worker condition met
node/curso-k8s-l1-worker2 condition met

$ kubectl get nodes --no-headers | wc -l
3

$ kubectl get nodes
NAME                         STATUS   ROLES           AGE   VERSION
curso-k8s-l1-control-plane   Ready    control-plane   30s   v1.37.0
curso-k8s-l1-worker          Ready    <none>          15s   v1.37.0
curso-k8s-l1-worker2         Ready    <none>          16s   v1.37.0
```

(Пропуснати са междинните стъпки на kind, същите като в 1.6.3; има ги пълни в `correr.salida.txt`.)

Двайсет и шест секунди и клъстерът е като нов, с преброени три възела. Това променя начина ти на работа в останалата част от курса. Клъстер, който се прави наново за половин минута, **не се поправя**: ако си го оставил в състояние, което не разбираш, го изтриваш и го създаваш отново. Това, което не се губи, е онова, което е във файлове: `kind-curso.yaml` и, от Урок 2 нататък, твоите манифести. Това е идеята от Урок 0, пренесена върху целия клъстер: файлът е истината.

Накрая скриптът излиза и `trap` изтрива пресъздадения клъстер и временната папка. На машината на изпълненията, след излизането, `docker ps` не показваше нито един контейнер на `curso-k8s-l1`, а папката `/tmp/curso-k8s-l1.*` вече не съществуваше.

## Грешката, която ще видиш

Този урок има три грешки със съобщение и една без съобщение.

**1. `ERROR: failed to create cluster: node(s) already exist`.** Създаване на клъстер с име, което вече съществува:

```text
$ kind create cluster --name curso-k8s-l1 --config kind-curso.yaml
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "curso-k8s-l1"
[código de salida: 1]
```

Чете се буквално: вече има възли, тоест контейнери, на клъстер с това име. kind не го заменя, нито го поправя. Преди да направиш каквото и да било, попитай се **чий е**. Ако е твой, от предишно изпълнение, което е останало живо, `kind delete cluster --name curso-k8s-l1` и го създаваш отново. Ако не знаеш чий е, не го изтриваш: това е случаят на споделена машина и затова скриптът на курса спира, вместо да го изтрие.

**2. `kubectl: FAILED`.** Видя го в 1.3.4: сумата на двоичния файл не съвпада с публикуваната. Не се инсталира. Теглят се отново двоичният файл **и** сумата му, със същата версия в двата адреса.

**3. `The connection to the server 127.0.0.1:1 was refused`.** Видя го в 1.7.2: `kubectl` е говорил със сървър, на който няма никого. Нужната информация е в адреса на последния ред. Сравни го с този от `kubectl cluster-info` на твоя клъстер: ако не съвпадат, контекстът ти не е този, който мислиш. Ако адресът е `localhost:8080`, няма активен контекст (Урок 0).

**4. Грешката без съобщение: възлите, които така и не стигнаха.** При `max_user_instances = 128` kind отпечатва всичките си отметки, включително `✓ Joining worker nodes`, и въпреки това работните възли не се присъединяват. Логовете казват `inotify_init: too many open files`. Тази грешка **не беше възпроизведена в този урок**: за да се направи, трябваше да се намали лимитът на споделена машина, на която в онзи момент работеха други клъстери, а намаляването му би ги сринало. Вече я измери Урок 0, в 0.6.3, с реалните ѝ съобщения. Тук се предотвратява: измерва се и се настройва преди това (1.4), а след създаването се чака `Ready` с `kubectl wait` и възлите се **броят** с `kubectl get nodes --no-headers | wc -l`, защото `wait` чака само съществуващите (1.6.3). Ако бройката не е 3, следите, които остави Урок 0, са две: `kubectl get pods -n kube-system` показва някой `kube-proxy` в `Error`, а `kubectl logs -n kube-system` на този Pod казва `too many open files`. Тогава клъстерът се изтрива, `inotify` се измерва и настройва (1.4) и клъстерът се създава отново.

## Навикът за сигурност от урока

Таблицата с навици на курса определя за този урок три:

**Двоични файлове с контролна сума.** Това, което работи с твоя потребител и със `sudo`, се тегли от официалния източник, с написана версия и проверена сума преди инсталиране. Двоичен файл без произход и без сума, като този, който идва по чата, не се инсталира, дори да „работи“. И се инсталира със собственик `root` и право `0755`, за да не може никоя програма, работеща като теб, да го замени.

**Фиксираният образ на възела.** Образът на всеки възел се задава чрез отпечатъка си, а не чрез тага си. Това е същият навик като сумата, приложен към това, което Docker изтегля.

**Проверка на контекста преди всяка команда, която променя нещо.** Временен и собствен `kubeconfig` за курса, за да не променя kind обичайния ти контекст. `kubectl config current-context` преди да действаш или `--context` във всяка команда. И `kubeconfig`, третиран като това, което е — администраторско удостоверение: права `600`, никога в чат или в хранилище и само от източници, на които се доверяваш.

Това, което предотвратяват и трите заедно, е онова от сцената: да не знаеш какво работи на машината ти, нито срещу кой клъстер.

## Какво се прави погрешно

**Теглене на „последната“.** Един `curl` към `latest` или към `stable.txt` ти дава днес една версия, а утре друга. Изходите на курса престават да съвпадат и не знаеш защо. Версията се записва.

**Теглене на двоичния файл и на сумата поотделно, с различни команди.** Това е случай 1 от 1.3.4: две смесени версии и `FAILED`, който прилича на атака. Теглят се заедно, с една и съща версия, записана само веднъж.

**Пропускане на сумата „защото е официалният сайт“.** Сумата проверява онова, което е стигнало до диска ти, а не онова, което има на сървъра. Прекъснато изтегляне тежи по-малко, понякога работи и се проваля по странни начини. Сумата струва една команда.

**`sudo mv` на двоичен файл на твоя потребител.** Остава в `PATH` със собственик твоя потребител и всяка програма, работеща като теб, може да го замени. `install -o root -g root -m 0755`.

**Увеличаване на `inotify` със `sysctl` и забравяне.** Работи до следващото рестартиране. После клъстерът се проваля и никой вече не помни защо. Настройката отива във файл в `/etc/sysctl.d/`, с коментар.

**Създаване на клъстера в обичайния ти `~/.kube/config`.** kind сменя активния ти контекст, без да пита. Следващият `kubectl`, който напишеш в друг прозорец, мислейки за клъстера от работата, ще говори с този на kind или обратното. Един временен `KUBECONFIG` на клъстер.

**`kind delete cluster` без `--name`.** Изтрива клъстера `kind`, който може да не е твоят. А тъй като изтриването на несъществуващ не дава грешка, и неправилно написаното име не те предупреждава. Чете се редът `Deleted nodes`.

**Поправяне на клъстер на kind.** Ако си го оставил в състояние, което не разбираш, го изтриваш и го създаваш отново за половин минута. Това, което има значение, живее във файлове.

## Упражнения

Упражнения 1 и 2 се отговарят с изходите от урока. Упражнение 3 изисква твоя Mint с инсталирани `kubectl` и `kind`. Упражнение 4 изисква клъстера. Запиши отговорите си в [дневника](bitacora.md), преди да погледнеш решенията.

### Упражнение 1 — Какво се случи с този двоичен файл?

Колежка изпълни това и те моли за помощ:

```text
$ curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$ curl -fsSLO https://dl.k8s.io/release/v1.37.1/bin/linux/amd64/kubectl.sha256
$ echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
kubectl: FAILED
sha256sum: WARNING: 1 computed checksum did NOT match
```

1. Дай вероятна причина, която **не** е атака, и обясни как би я проверил.
2. Какво би променил в двете команди, за да не се случва това?
3. Инсталира ли двоичния файл, докато разбира? Защо?

### Упражнение 2 — Прочети `kubeconfig`

С изхода на `kubectl config view --minify` от 1.7.1 отговори:

1. Какъв адрес и какъв порт използва `kubectl`, за да стигне до клъстера? Къде другаде в урока се появява този порт?
2. Как се казват клъстерът, потребителят и контекстът и каква връзка имат с името, което даде на kind?
3. Какво има зад `DATA+OMITTED` и защо `kubectl` го скрива?
4. Ако някой ти прати своя `kubeconfig` по чата „за да видиш моя клъстер“, какво правиш, преди да го използваш?

### Упражнение 3 — Предскажи и измери `inotify`

Без да изпълняваш нищо, предскажи какво ще каже `./fig01_04.sh` в твоя току-що инсталиран Mint, преди каквато и да е настройка. После го изпълни. Настрой със `sudo ./fig01_04.sh --ajustar` и го изпълни отново без аргументи. След това отговори:

1. Съвпадна ли предвиждането ти? Какви стойности излязоха преди и след това?
2. Къде е записана настройката и коя команда ти го доказва?
3. Ако рестартираш машината, каква стойност очакваш и защо?

### Упражнение 4 — Два клъстера, два контекста (проект)

В терминал с временен `KUBECONFIG` (1.6.1) създай клъстера на курса с `kind-curso.yaml`. В **същия** `KUBECONFIG` създай друг клъстер от един-единствен възел с `kind create cluster --name curso-k8s-l1b` (без конфигурационен файл). После:

1. Кой остана като активен контекст? Предскажи го, преди да погледнеш с `kubectl config get-contexts`.
2. Без да променяш активния контекст, покажи възлите на **всеки** клъстер.
3. Изтрий **само** `curso-k8s-l1b` и провери, че клъстерът на курса е още жив и че можеш пак да говориш с него.
4. Накрая изтрий клъстера на курса и провери с `docker ps`, че не е останал нито един контейнер на нито един от двата.

Когато го направиш ръчно, сравни с `programas/01-instalacion-primer-cluster/ejercicio4.sh`, който прави четирите стъпки със защитите на `correr.sh`, и с изхода му, `ejercicio4.salida.txt`. (Вторият клъстер използва образа на възела по подразбиране на kind v0.33.0, без отпечатък: това е клъстер за еднократна употреба, а не този на курса.)

## Решения

### Решение 1

1. **Две различни версии.** Двоичният файл е излязъл от това, което е казвал `stable.txt` в онзи момент, а сумата е фиксирана на v1.37.1. Ако `stable.txt` вече казва друга версия, това са файлове от различни версии и сумата не може да съвпадне. Проверява се с `curl -L -s https://dl.k8s.io/release/stable.txt`: ако не казва `v1.37.1`, там е причината. Друга възможна причина е прекъснато изтегляне; `ls -l kubectl` спрямо очаквания размер (61,886,626 байта за v1.37.1 в `amd64`) го показва.
2. Версията се записва **веднъж**, в променлива, и се използва и в двата адреса, както прави `fig01_01.sh`: `KUBECTL_VERSION=v1.37.1`, и `…/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl` и `…/kubectl.sha256`.
3. **Не.** `FAILED` не казва дали файлът е от друга версия, или е променен; двата случая изглеждат еднакво (1.3.4). Докато една сума не каже `OK`, двоичният файл не влиза в `/usr/local/bin`.

### Решение 2

1. `https://127.0.0.1:54589`. Същият порт се появява в `kubectl cluster-info` и в колоната `PORTS` на `docker ps`: `127.0.0.1:54589->6443/tcp`, портът, който Docker публикува на твоята машина за `kube-apiserver`, който вътре във възела слуша на 6443. При твоето изпълнение ще е друг.
2. И трите се казват `kind-curso-k8s-l1`: `kind-` плюс името, което си дал с `--name`. kind винаги ги именува така.
3. Сертификатът, с който `kubectl` разпознава сървъра (`certificate-authority-data`), и **администраторското удостоверение** на клъстера (`client-certificate-data` и `client-key-data`). `kubectl` ги скрива, защото този, който има тези данни, е администратор на клъстера.
4. Прочиташ го изцяло, преди да го използваш, както един скрипт: документацията предупреждава, че нарочно направен `kubeconfig` може да изпълни код. Използваш го във временен `KUBECONFIG`, не го смесваш със своя и напомняш на този, който ти го е пратил, че току-що е споделил удостоверение.

### Решение 3

1. Очакваното в Mint 22, основан на Ubuntu 24.04: `fs.inotify.max_user_instances = 128` и `FALTA AJUSTAR`. Наблюденията зависят от твоята система и от паметта ти, така че може да излязат различни от 8192, които споменава ръководството на kind за Ubuntu. След настройката: 512 инстанции, поне 524288 наблюдения и `LISTO`. Във виртуалната машина на изпълненията, също Ubuntu 24.04, наблюденията вече бяха 1048576. Ако първото ти измерване вече е казало `LISTO`, някой го е настроил преди това; потърси къде с въпрос 2.
2. В `/etc/sysctl.d/99-kind-inotify.conf`. Доказват го `cat /etc/sysctl.d/99-kind-inotify.conf` и `grep -rn '^fs.inotify' /etc/sysctl.conf /etc/sysctl.d/`, който трябва да намери редовете на този файл (два или само този за инстанциите, ако наблюденията ти вече са били по-високи) и нито един в друг. Ако се появи друг в `/etc/sysctl.conf`, той печели при рестартиране (1.4.3).
3. 512 инстанции и поне 524288 наблюдения: при стартиране `systemd-sysctl` чете `/etc/sysctl.d/*.conf` и прилага файла, освен ако `/etc/sysctl.conf` не фиксира друга стойност. Ако го беше увеличил само със `sudo sysctl …`, щеше да се върне на 128, както би станало с виртуалната машина на изпълненията.

### Решение 4

Четирите отговора бяха измерени с `ejercicio4.sh` (`ejercicio4.salida.txt`).

1. **`kind-curso-k8s-l1b`**, последният създаден: kind оставя активен контекста на клъстера, който току-що е създал. `get-contexts` показва двата, със звездичката при `kind-curso-k8s-l1b`. Това е точно клопката на контекста: клъстерът на курса си е там, но вече не е този, с който говориш.
2. С `--context`, който има предимство пред активния контекст:

   ```bash
   kubectl --context kind-curso-k8s-l1 get nodes
   kubectl --context kind-curso-k8s-l1b get nodes
   ```

   Първият показва три възела, а вторият — един, `curso-k8s-l1b-control-plane`, с `ROLES control-plane` и `v1.37.0`.
3. `kind delete cluster --name curso-k8s-l1b`. Трябва да каже `Deleted nodes: ["curso-k8s-l1b-control-plane"]`. kind маха контекста му от `kubeconfig` и указателят остава празен, защото той е бил активният. `kubectl config get-contexts` показва само `kind-curso-k8s-l1`, без звездичка. `kubectl config use-context kind-curso-k8s-l1` и `kubectl get nodes` показват трите възела на курса.
4. `kind delete cluster --name curso-k8s-l1` и после `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` и същото с `curso-k8s-l1b`. И двата отговора трябва да са празни и при изпълнението бяха.

## Как разбирам, че съм успял

- [ ] `kubectl version --client` казва `Client Version: v1.37.1` и `Kustomize Version: v5.8.1`, а `kind version` казва `kind v0.33.0 go1.26.7 linux/amd64`.
- [ ] `command -v kubectl kind` казва `/usr/local/bin/kubectl` и `/usr/local/bin/kind`, а `ls -l` ги показва със собственик `root root` и права `-rwxr-xr-x`.
- [ ] Изпълняваш `./fig01_01.sh` в нова папка и получаваш `kubectl: OK` и `kind-linux-amd64: OK`, с двете суми от 1.3.3 (на ARM компютър — тези на изданието за `arm64`).
- [ ] `./fig01_04.sh` завършва с `LISTO`, неговият `grep` намира редовете на `/etc/sysctl.d/99-kind-inotify.conf` и нито един в `/etc/sysctl.conf`.
- [ ] Изпълняваш `./correr.sh` и сверяваш с `correr.salida.txt` това, което не се променя между изпълненията: празният `kubeconfig` в началото; трите възела `Ready` и преброени (`3`) с `v1.37.0`, `Debian GNU/Linux 13 (trixie)` и `containerd://2.3.4`, с `ROLES <none>` при работните; един-единствен контейнер, който публикува порт, `127.0.0.1:<puerto>->6443/tcp`; класът `standard (default)`; `512` в трите възела; `ALTO` от проверката с контекста `otro`; грешката `node(s) already exist`; контекстът, възстановен с `kind export kubeconfig`; `error: current-context is not set` след изтриването; и три възела `Ready` след повторното създаване. Възрастите на обектите, IP адресите, портът, наставките на Pod-овете, редът на възлите в `kind get nodes` и `docker ps`, прощалната фраза на kind, времената, резултатите от броенето на `inotify` и временният път се променят при всяко изпълнение: наблюдават се, не се сравняват.
- [ ] След края на `correr.sh` командата `docker ps --filter label=io.x-k8s.kind.cluster=curso-k8s-l1 --format '{{.Names}}'` не връща нищо.

## Обобщение

Отговори, без да гледаш урока:

1. Защо курсът инсталира `kubectl` и `kind` като двоични файлове, а не с `apt` или `snap`?
2. Какво доказва съвпадаща сума `sha256` и какво не доказва?
3. Кои две чести причини дават `kubectl: FAILED` и какво правиш и в двата случая?
4. Какво е `inotify` и защо три възела на kind го изчерпват, когато един-единствен не го изчерпва?
5. Каква е разликата между `sudo sysctl fs.inotify.max_user_instances=512` и един файл в `/etc/sysctl.d/`?
6. Кои три списъка и какъв указател има един `kubeconfig`?
7. За какво служи да експортираш `KUBECONFIG` към временен файл, преди да създадеш клъстера?
8. Кое печели, когато в командата има `--context`, а във файла — друг `current-context`?
9. Какво отговаря kind, ако изтриеш клъстер, който не съществува, и защо това е едновременно удобно и опасно?
10. Загубил си контекста, но клъстерът е още жив. С коя команда го възстановяваш?

## Източници

Всички посетени на 21 октомври 2026 г.

- [Kubernetes, „Install and Set Up kubectl on Linux“](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/): изтеглянето на двоичния файл и на сумата му, проверката със `sha256sum --check` и съобщенията `OK` и `FAILED`, `install -o root -g root -m 0755` и правилото за една минорна версия разлика.
- [Kubernetes, „Version Skew Policy“](https://kubernetes.io/releases/version-skew-policy/) и [„Kubernetes Release Cycle“](https://kubernetes.io/releases/release/): кои версии на `kubectl` вършат работа с кой клъстер и ритъмът на версиите.
- [Kubernetes, „Organizing Cluster Access Using kubeconfig Files“](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/): какво е `kubeconfig`, какво е контекст, `KUBECONFIG` като списък, правилата за сливане на файлове, как се избира контекстът и предупреждението за файлове от ненадеждни източници.
- [Kubernetes, `kubectl config`](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_config/): подкомандите на `kubectl config` и редът, в който `kubectl` зарежда файловете.
- [kind, „Quick Start“](https://kind.sigs.k8s.io/docs/user/quick-start/): инсталирането от двоичния файл на изданието, създаването с `--name` и с конфигурационен файл, образът по неговата сума `sha256`, изтриването без `--name` и това, че изтриването на несъществуващ клъстер не е грешка.
- [kind, „Known Issues“, „Pod errors due to too many open files“](https://kind.sigs.k8s.io/docs/user/known-issues/#pod-errors-due-to-too-many-open-files): лимитите на `inotify`, стойностите на Ubuntu и препоръчаните.
- [kind v0.33.0, страницата на изданието](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0): двоичните файлове с техния `.sha256sum` и образът на възела `kindest/node:v1.37.0` с неговия отпечатък.
- [man7, `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html): какво е `inotify` и какво ограничават `max_user_instances` и `max_user_watches`.
- [man7, `sysctl.d(5)`](https://man7.org/linux/man-pages/man5/sysctl.d.5.html): папките, които се четат при стартиране, и редът, в който се прилагат.
- [Linux Mint 22, бележки към версията](https://www.linuxmint.com/rel_wilma.php): Mint 22 се основава на Ubuntu 24.04.

---

**Предишен:** [Урок 0 — Какво е Kubernetes и какво НЕ е kind](00-que-es-kubernetes.md) · **Следващ:** [Урок 2 — Pods и Deployments](02-pods-deployments.md)
