# 🐘 Hadoop-кластер на 3 ноутбуках

<p align="center">
  <b>Hadoop 3.3.6</b> &nbsp;|&nbsp; HDFS + YARN + MapReduce &nbsp;|&nbsp; Docker &nbsp;|&nbsp; Windows
</p>

Развёртывание распределённого Hadoop-кластера на **3 Windows-ноутбуках** с помощью Docker.
В комплекте — учебное MapReduce-приложение **SimpleApp (LineCount)**.

---

## Содержание

1. [Архитектура](#архитектура)
2. [Требования](#требования)
3. [Быстрый старт (3 шага)](#быстрый-старт-3-шага)
4. [Остановка кластера](#остановка-кластера)
5. [Запуск SimpleApp (LineCount)](#запуск-simpleapp-linecount)
6. [Настройка ролей](#настройка-ролей)
7. [Генератор конфигов (setup-cluster)](#генератор-конфигов-setup-cluster)
8. [Ручная настройка (без скрипта)](#ручная-настройка-без-скрипта)
9. [Локальный тест на одном ноуте](#локальный-тест-на-одном-ноуте)
10. [Веб-интерфейсы](#веб-интерфейсы)
11. [Структура проекта](#структура-проекта)
12. [Решение проблем](#решение-проблем)

---

## Архитектура

```
┌─────────────────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│        MASTER (ноут 1)      │     │  WORKER1 (ноут 2)│     │  WORKER2 (ноут 3)│
│                             │     │                  │     │                  │
│  ┌─────────┐ ┌────────────┐ │     │  ┌──────────┐   │     │  ┌──────────┐   │
│  │NameNode │ │ResourceMgr │ │     │  │ DataNode │   │     │  │ DataNode │   │
│  └─────────┘ └────────────┘ │     │  └──────────┘   │     │  └──────────┘   │
│  ┌─────────┐ ┌────────────┐ │     │  ┌──────────┐   │     │  ┌──────────┐   │
│  │ 2NN     │ │HistoryServ │ │     │  │NodeMgr   │   │     │  │NodeMgr   │   │
│  └─────────┘ └────────────┘ │     │  └──────────┘   │     │  └──────────┘   │
└──────────┬──────────────────┘     └────────┬─────────┘     └────────┬─────────┘
           │         LAN (192.168.x.x)       │                        │
           └─────────────────────────────────┴────────────────────────┘
```

| Ноут       | Контейнеры                                                  |
|------------|-------------------------------------------------------------|
| **master** | NameNode, SecondaryNameNode, ResourceManager, HistoryServer |
| **worker1**| DataNode, NodeManager                                       |
| **worker2**| DataNode, NodeManager                                       |

---

## Требования

| Требование | Детали |
|-----------|--------|
| **ОС** | Windows 10/11 на всех 3 ноутбуках |
| **Docker** | Docker Desktop с включённым WSL2 backend |
| **RAM** | Минимум 4 ГБ свободной памяти для Docker на каждом ноуте |
| **Сеть** | Все 3 ноута в одной локальной сети (проверка: `ping <IP_другого_ноута>`) |
| **Git** | Для клонирования репозитория |

### Порты, которые нужно открыть в файрволе

| Ноут | Порты |
|------|-------|
| **master** | 9000, 9870, 9868, 8030–8033, 8088, 19888, 10020 |
| **worker1/worker2** | 9864, 9866, 9867, 8040–8042, 13562, 32000–32001 |

> **Совет:** на время работы можно разрешить весь трафик от подсети ноутбуков:
> Windows Defender → Advanced settings → Inbound rules → New rule → Custom → Remote IPs.

---

## Быстрый старт (3 шага)

### Шаг 1. Клонирование

На **каждом** ноутбуке:

```powershell
git clone https://github.com/SailorVAC/clustrer_hadoop.git
cd clustrer_hadoop
```

### Шаг 2. Конфигурация

На **одном** ноуте создайте `cluster.conf`:

```powershell
copy cluster.conf.example cluster.conf
notepad cluster.conf
```

Впишите реальные IP ваших ноутбуков (`ipconfig`):

```ini
192.168.1.10  namenode,secondarynamenode,resourcemanager,historyserver
192.168.1.11  datanode
192.168.1.12  datanode
```

Роли можно распределять гибко (подробнее — [Настройка ролей](#настройка-ролей)).

Скопируйте `cluster.conf` на **все** остальные ноуты (через USB, по сети, или просто создайте одинаковый файл).

### Шаг 3. Запуск

На **каждом** ноуте — один и тот же скрипт:

```powershell
start.bat
```

Скрипт **автоматически определяет** какая это машина по IP, генерирует нужный docker-compose и запускает контейнеры. Первый запуск долгий — скачивается образ (~700 МБ).

**Порядок:** сначала мастер (NameNode), потом воркеры. Но даже если запустить одновременно — воркеры подождут мастера автоматически.

**Проверка** (на мастере, через ~30 сек после запуска):

```powershell
docker exec namenode hdfs dfsadmin -report
docker exec resourcemanager yarn node -list
```

**Кластер готов!**

---

## Остановка кластера

На каждом ноуте:

```powershell
stop.bat
```

С удалением данных HDFS (полный сброс):
```powershell
stop.bat -v
```

---

## Настройка ролей

В `cluster.conf` можно назначить любые роли на любую машину:

| Роль | Описание | Ограничение |
|------|----------|-------------|
| `namenode` | Метаданные HDFS | ровно 1 |
| `secondarynamenode` | Чекпоинт NameNode | — |
| `resourcemanager` | Управление YARN | ровно 1 |
| `historyserver` | История MapReduce-задач | — |
| `datanode` | Хранение данных + выполнение задач | минимум 1 |

**Примеры:**

Стандартная (3 машины):
```ini
192.168.1.10  namenode,secondarynamenode,resourcemanager,historyserver
192.168.1.11  datanode
192.168.1.12  datanode
```

YARN на отдельном (4 машины):
```ini
192.168.1.10  namenode,secondarynamenode,historyserver
192.168.1.20  resourcemanager
192.168.1.11  datanode
192.168.1.12  datanode
```

Всё раздельно (5 машин):
```ini
192.168.1.10  namenode,secondarynamenode
192.168.1.20  resourcemanager
192.168.1.30  historyserver
192.168.1.11  datanode
192.168.1.12  datanode
```

При смене сети — отредактируйте IP в `cluster.conf` и перезапустите `start.bat`.

---

## Генератор конфигов (setup-cluster)

Если нужно сгенерировать compose-файлы **без запуска** (например, для переноса на другие машины):

```powershell
.\scripts\setup-cluster.ps1        # PowerShell
bash scripts/setup-cluster.sh      # Bash
```

Скрипт читает `cluster.conf` (или спрашивает интерактивно, если файла нет) и создаёт файлы в `generated/`.

---

## Ручная настройка (без скрипта)

> Используйте `start.bat` — он всё делает автоматически. Раздел ниже — если хотите настроить вручную.

### Клонирование

На **каждом** из 3 ноутбуков:

```powershell
git clone https://github.com/SailorVAC/clustrer_hadoop.git
cd clustrer_hadoop
```

### Шаг 2. Узнать IP всех 3 ноутбуков

На каждом ноуте в PowerShell:

```powershell
ipconfig
```

Найдите IPv4-адрес сетевого адаптера (обычно Wi-Fi или Ethernet), по которому ноуты в одной сети. Запишите три адреса:

```
master   = 192.168.1.10   (пример)
worker1  = 192.168.1.11   (пример)
worker2  = 192.168.1.12   (пример)
```

### Шаг 3. Создать `.env` на каждом ноуте

Скопируйте `.env.example` в `.env` и впишите реальные IP-адреса. **Файл `.env` одинаковый на всех ноутах**, кроме строки `NODE_NAME` на воркерах.

```powershell
copy .env.example .env
notepad .env
```

**На мастере:**
```env
MASTER_IP=192.168.1.10
WORKER1_IP=192.168.1.11
WORKER2_IP=192.168.1.12
```

**На worker1:**
```env
MASTER_IP=192.168.1.10
WORKER1_IP=192.168.1.11
WORKER2_IP=192.168.1.12
NODE_NAME=worker1
```

**На worker2:**
```env
MASTER_IP=192.168.1.10
WORKER1_IP=192.168.1.11
WORKER2_IP=192.168.1.12
NODE_NAME=worker2

# DataNode-порты worker2 смещены, чтобы не конфликтовать с worker1
# (NameNode видит оба DataNode с одного gateway IP мастера)
DN_HTTP_PORT=9874
DN_XFER_PORT=9876
DN_IPC_PORT=9877
```

### Шаг 4. Запуск мастера

На **master**-ноуте:

```powershell
docker compose -f docker-compose.master.yml up -d --build
```

> Первый запуск долгий — скачивается образ Hadoop (~700 МБ). Дождитесь готовности:

```powershell
docker logs -f namenode
# Ждите строку: "NameNode RPC up at: ..."
# Ctrl+C чтобы выйти из логов
```

Проверьте: откройте в браузере `http://localhost:9870` — должна появиться NameNode UI.

### Шаг 5. Запуск воркеров

На **worker1**-ноуте (убедитесь, что в `.env` стоит `NODE_NAME=worker1`):

```powershell
docker compose -f docker-compose.worker.yml up -d --build
```

На **worker2**-ноуте (в `.env` должно быть `NODE_NAME=worker2`):

```powershell
docker compose -f docker-compose.worker.yml up -d --build
```

> Воркеры ожидают подключения к NameNode — это нормально, если мастер ещё запускается.

### Шаг 6. Проверка кластера

С **мастер**-ноута:

```powershell
# Проверить DataNode'ы (должно быть 2 Live datanodes)
docker exec namenode hdfs dfsadmin -report

# Проверить NodeManager'ы (должно быть 2 active nodes)
docker exec resourcemanager yarn node -list
```

Также можно проверить через веб-интерфейс:
- `http://<MASTER_IP>:9870` → вкладка Datanodes — 2 live nodes
- `http://<MASTER_IP>:8088` → вкладка Nodes — 2 active nodes

**Кластер развёрнут и готов к работе!**

---

## Запуск SimpleApp (LineCount)

**SimpleApp** — учебное MapReduce-приложение, которое считает количество строк во входных файлах.
Исходный код: `app/SimpleApp/`.

### Автоматический запуск

Скрипт сам соберёт JAR (Maven в Docker, ничего ставить не нужно), проверит данные в HDFS и запустит задачу на YARN.

На **мастер**-ноуте из корня репозитория:

```powershell
.\scripts\run-simpleapp.ps1
```

По умолчанию скрипт берёт данные из `/user/demo/input` в HDFS. Результат выведет в консоль:

```
=== Result ===
Number of lines:    3500
=== Done! ===
```

Можно указать свои пути:

```powershell
.\scripts\run-simpleapp.ps1 -InputPath /my/input -OutputPath /my/output
```

### Ручной запуск (пошагово)

#### 1. Сборка JAR

Maven и JDK на ноут ставить **не нужно** — сборка идёт в Docker-контейнере:

```powershell
.\scripts\build-app.ps1
```

JAR появится в `app\SimpleApp\target\SimpleApp-1.0-SNAPSHOT.jar`.

#### 2. Копирование JAR в контейнер

```powershell
docker cp app\SimpleApp\target\SimpleApp-1.0-SNAPSHOT.jar resourcemanager:/tmp/
```

#### 3. Загрузка данных в HDFS

```powershell
# Скопировать файл с ноута в контейнер, затем положить в HDFS
docker cp data.txt namenode:/tmp/data.txt
docker exec namenode hdfs dfs -mkdir -p /user/demo/input
docker exec namenode hdfs dfs -put /tmp/data.txt /user/demo/input/
```

#### 4. Запуск MapReduce-задачи

```powershell
docker exec resourcemanager hadoop jar /tmp/SimpleApp-1.0-SNAPSHOT.jar `
    "-Ddfs.client.use.datanode.hostname=true" `
    /user/demo/input /user/demo/output
```

> **Важно:**
> - Имя main-класса указывать **не нужно** — оно прописано в манифесте JAR.
> - Флаг `-Ddfs.client.use.datanode.hostname=true` обязателен для multi-host Docker-кластера — без него HDFS-клиент пытается подключиться к DataNode по Docker bridge IP (172.18.0.1) вместо LAN IP.

Map- и reduce-задачи распределяются по NodeManager'ам на разных воркерах — полноценное распределённое выполнение (`uber mode : false`).

#### 5. Просмотр результата

```powershell
docker exec namenode hdfs dfs -cat /user/demo/output/part-r-00000
```

> Перед повторным запуском удалите выходную директорию:
> ```powershell
> docker exec namenode hdfs dfs -rm -r /user/demo/output
> ```

### Свой входной файл

```powershell
docker cp my-file.txt namenode:/tmp/my-file.txt
docker exec namenode hdfs dfs -mkdir -p /mydata/input
docker exec namenode hdfs dfs -put /tmp/my-file.txt /mydata/input/
.\scripts\run-simpleapp.ps1 -InputPath /mydata/input -OutputPath /mydata/output
```

### Как работает межузловая коммуникация

В multi-host Docker-кластере каждый ноутбук имеет свою **изолированную Docker bridge-сеть** (172.18.x.x). Контейнеры на разных ноутах не видят друг друга по этим IP. Это вызывает две проблемы, которые решены в проекте:

#### Проблема 1: Java-сервисы рекламируют Docker bridge IP

Docker автоматически добавляет в `/etc/hosts` контейнера запись `172.18.0.3 worker1`.
Если в `docker-compose.worker.yml` также заданы `extra_hosts` (например `192.168.1.11 worker1`),
то в `/etc/hosts` оказываются **две** записи для одного hostname.
`InetAddress.getLocalHost()` в Java может взять bridge IP (172.18.0.3),
и MRAppMaster/NodeManager будут рекламировать адрес, недостижимый с других ноутов.

**Решение (entrypoint.sh):** при старте DataNode и NodeManager функция `fix_hostname_for_lan()`
удаляет из `/etc/hosts` строку с bridge IP (172.x.x.x), оставляя только LAN IP из `extra_hosts`.
Теперь Java-сервисы рекламируют LAN IP ноутбука.

#### Проблема 2: NameNode подменяет IP DataNode'ов

Когда DataNode на worker1 подключается к NameNode на мастере, соединение проходит
через Docker port forwarding. NameNode видит source IP = `172.18.0.1` (gateway bridge-сети мастера)
и записывает его как адрес DataNode. Когда HDFS-клиент просит записать данные, NameNode
возвращает `172.18.0.1:9866` — адрес, по которому DataNode **не** доступен.

**Решение (mapred-site.xml + флаг -D):** параметр `dfs.client.use.datanode.hostname=true`
заставляет HDFS-клиент подключаться к DataNode по **hostname** (`worker1`, `worker2`),
который через `extra_hosts` резолвится в правильный LAN IP. Параметр задан и в конфигах,
и явно в скриптах запуска (`-Ddfs.client.use.datanode.hostname=true`).

#### Порты DataNode

Worker2 использует **смещённые** порты DataNode (9874/9876/9877 вместо 9864/9866/9867).
Это нужно потому, что NameNode видит оба DataNode с одного gateway IP (`172.18.0.1`) —
если бы порты совпадали, NameNode не смог бы их различить.

Все нужные порты (8041, 9866, 13562, 32000–32001 и т.д.) проброшены через Docker,
поэтому коммуникация между узлами работает через LAN.

**Результат: map- и reduce-задачи выполняются распределённо на разных воркерах** (`uber mode : false`).

---

## Локальный тест на одном ноуте

Перед развёртыванием на 3 машины можно убедиться, что образ и конфиги работают, запустив всё на одном ноуте:

```powershell
docker compose -f docker-compose.local.yml up -d --build

# Проверка: должно быть 2 DataNode и 2 NodeManager
docker exec namenode hdfs dfsadmin -report
docker exec resourcemanager yarn node -list -all

# Уборка
docker compose -f docker-compose.local.yml down -v
```

---

## Веб-интерфейсы

| URL | Описание |
|-----|----------|
| `http://<MASTER_IP>:9870` | **NameNode** — состояние HDFS, DataNode'ы, файловая система |
| `http://<MASTER_IP>:8088` | **ResourceManager** — YARN, запущенные приложения, NodeManager'ы |
| `http://<MASTER_IP>:19888` | **JobHistory** — история завершённых MapReduce-задач |
| `http://<MASTER_IP>:9868` | **SecondaryNameNode** |
| `http://<WORKER_IP>:9864` | **DataNode** на воркере |
| `http://<WORKER_IP>:8042` | **NodeManager** на воркере |

---

## Структура проекта

```
clustrer_hadoop/
├── start.bat                    # Запуск кластера (на каждом ноуте)
├── stop.bat                     # Остановка кластера
├── cluster.conf.example         # Шаблон конфигурации → скопировать в cluster.conf
│
├── Dockerfile                   # Единый образ Hadoop для всех ролей
├── docker-compose.master.yml    # Compose для ручной настройки (мастер)
├── docker-compose.worker.yml    # Compose для ручной настройки (воркер)
├── docker-compose.local.yml     # All-in-one для теста на 1 машине
├── .env.example                 # Шаблон .env для ручной настройки
│
├── app/
│   └── SimpleApp/               # MapReduce-приложение LineCount
│       ├── pom.xml              # Maven-конфиг (Hadoop 3.3.6, Java 11)
│       └── src/                 # Исходники Java
│
├── config/                      # Конфиги Hadoop (копируются в образ)
│   ├── core-site.xml
│   ├── hdfs-site.xml
│   ├── yarn-site.xml
│   ├── mapred-site.xml
│   ├── hadoop-env.sh
│   └── workers
│
└── scripts/
    ├── entrypoint.sh            # Стартовый скрипт контейнера (выбор роли)
    ├── start.ps1                # Логика запуска (вызывается из start.bat)
    ├── stop.ps1                 # Логика остановки
    ├── setup-cluster.ps1        # Генератор конфигов (PowerShell)
    ├── setup-cluster.sh         # Генератор конфигов (Bash)
    ├── build-app.ps1            # Сборка JAR через Maven в Docker
    ├── build-app.sh             # Сборка JAR (Bash)
    ├── run-simpleapp.ps1        # Полный цикл: сборка + запуск MR
    └── run-simpleapp.sh         # Полный цикл (Bash)
```

---

## Решение проблем

### `MASTER_IP должен быть задан в .env`

Забыли скопировать `.env.example` в `.env` или не заполнили IP-адреса.

```powershell
copy .env.example .env
notepad .env
```

### DataNode не появляется в `hdfs dfsadmin -report`

NameNode не может подключиться к DataNode по hostname `worker1` / `worker2`. Проверьте:

1. IP-адреса в `.env` совпадают с реальными (`ipconfig` на каждом ноуте)
2. Порты 9866, 9867 не заблокированы файрволом на воркере
3. Логи DataNode: `docker logs datanode` — нет ли ошибок подключения

### MR-задача висит в ACCEPTED

У NodeManager не хватает памяти. Варианты:

- Уменьшить `yarn.nodemanager.resource.memory-mb` в `config/yarn-site.xml`
- Дать Docker Desktop больше RAM: Settings → Resources

### NameNode не стартует (ошибка формата)

Обычно после смены конфигов с уже отформатированной FS. Полный сброс:

```powershell
docker compose -f docker-compose.master.yml down -v
docker compose -f docker-compose.master.yml up -d --build
```

### Не открываются файлы в NameNode Web UI

Браузер получает ошибку вида `Failed to load http://worker2:9874/...`. Это нормальное поведение — HDFS перенаправляет на hostname DataNode, который браузер на вашем ноуте не может разрешить.

**Решение 1** — добавить записи в `C:\Windows\System32\drivers\etc\hosts`:
```
192.168.1.11  worker1
192.168.1.12  worker2
```

**Решение 2** — просматривать файлы через командную строку:
```powershell
docker exec namenode hdfs dfs -cat /path/to/file
```

### MapReduce-задача падает с Connection refused

Ошибка `java.net.ConnectException: Connection refused` при доступе к `172.18.0.1:9866` или подобным адресам:

1. **HDFS-клиент использует bridge IP вместо hostname.** Убедитесь, что в команде запуска есть флаг `-Ddfs.client.use.datanode.hostname=true` (автоматический скрипт уже его включает).

2. **entrypoint.sh не обновлён.** Пересоберите контейнеры на **всех** ноутах (мастер + воркеры):
   ```powershell
   docker compose -f docker-compose.worker.yml down
   docker compose -f docker-compose.worker.yml up -d --build
   ```

3. **Порты worker2 не смещены.** В `.env` на worker2 должны быть `DN_HTTP_PORT=9874`, `DN_XFER_PORT=9876`, `DN_IPC_PORT=9877`.

4. **Файрвол.** Проверьте что порты 9866, 9876, 13562, 32000–32001 открыты на воркерах.

---

## Лицензия

Учебный проект. Apache Hadoop распространяется под Apache License 2.0.
